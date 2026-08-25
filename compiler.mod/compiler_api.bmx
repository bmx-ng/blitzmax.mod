' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.MaxUtil
Import BlitzMax.Language
Import "compiler_diagnostic.bmx"
Import "compiler_options.bmx"
Import "file_snapshot_resolver.bmx"
Import "ir_model.bmx"
Import "generic_application_plan.bmx"
Import "ir_lowering.bmx"
Import "c_backend.bmx"
Import "interface_emitter.bmx"
Import "build_output_plan.bmx"

Rem
bbdoc: Contains the products and diagnostics of a staged BlitzMax compilation.
about: A successful result contains the language analysis, typed compiler IR, and
generic application plan needed by the emission methods on #TBlitzMaxCompiler.
End Rem
Type TCompilerResult
	Field analysis:TLanguageAnalysis
	Field ir:TCompilerIrModule
	Field genericPlan:TCompilerGenericApplicationPlan
	Field diagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]
	Field sourceLoadMilliseconds:Int
	Field analysisMilliseconds:Int
	Field genericPlanMilliseconds:Int
	Field loweringMilliseconds:Int
	Field loweringProfile:TCompilerIrLoweringProfile

	Rem
	bbdoc: Reports whether compilation produced valid typed IR without diagnostics.
	End Rem
	Method Succeeded:Int()
		Return analysis <> Null And analysis.Succeeded() And diagnostics.length = 0 And ir <> Null
	End Method
End Type

Rem
bbdoc: Provides the stable entry points for compiling and emitting BlitzMax programs.
End Rem
Type TBlitzMaxCompiler
	Rem
	bbdoc: Compiles BlitzMax source text to typed compiler IR.
	param: The source path used for identity, imports, and diagnostics.
	param: The source text to compile.
	param: The dependency resolver, or #Null to use a filesystem resolver.
	param: Optional compiler configuration.
	param: Optional cache for reusable generic backend units.
	returns: The staged compilation result.
	End Rem
	Function Compile:TCompilerResult(path:String, text:String, resolver:TSnapshotResolver, options:TCompilerOptions = Null, backendUnitCache:TCompilerGenericBackendUnitCache = Null)
		If Not options Then options = TCompilerOptions.CreateDefault()
		Local result:TCompilerResult = New TCompilerResult
		If Not resolver Then resolver = TCompilerFileSnapshotResolver.Create(options)
		Local started:Int = MilliSecs()
		result.analysis = TBlitzMaxLanguage.BuildAndAnalyze(path, text, resolver, options.SnapshotOptions())
		result.analysisMilliseconds = MilliSecs() - started
		If result.analysis.Succeeded() Then
			result.diagnostics :+ ConfiguredSyntaxDiagnostics(result.analysis)
			result.diagnostics :+ ModuleDeclarationDiagnostics(result.analysis, options)
			If result.diagnostics.length Then Return result
			Local genericDiagnostics:TCompilerDiagnostic[]
			started = MilliSecs()
			result.genericPlan = TCompilerGenericApplicationPlanner.Build(result.analysis, options, genericDiagnostics, backendUnitCache)
			result.genericPlanMilliseconds = MilliSecs() - started
			result.diagnostics :+ genericDiagnostics
			Local loweringDiagnostics:TCompilerDiagnostic[]
			started = MilliSecs()
			result.ir = TCompilerIrLowerer.LowerProfiled(result.analysis, options, loweringDiagnostics, result.genericPlan, result.loweringProfile)
			result.loweringMilliseconds = MilliSecs() - started
			result.diagnostics :+ loweringDiagnostics
		End If
		Return result
	End Function

	Function ModuleDeclarationDiagnostics:TCompilerDiagnostic[](analysis:TLanguageAnalysis, options:TCompilerOptions)
		Local diagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]
		If Not analysis Or Not analysis.snapshot Or Not analysis.snapshot.rootDocument Or Not analysis.snapshot.rootDocument.tree Then Return diagnostics
		Local expected:String = BRL.MaxUtil.ModuleNameForPath(analysis.snapshot.rootDocument.path)
		If Not expected.length Then Return diagnostics
		For Local member:TSyntaxNode = EachIn analysis.snapshot.rootDocument.tree.root.members
			Local statement:TRawStatementSyntax = TRawStatementSyntax(member)
			If Not statement Or statement.tokens.length < 2 Or statement.tokens[0].text.ToLower() <> "module" Then Continue
			Local declared:String
			For Local index:Int = 1 Until statement.tokens.length
				declared :+ statement.tokens[index].text
			Next
			If declared.ToLower() <> expected.ToLower() Then
				diagnostics :+ [TCompilerDiagnostic.Create("BMXC0003", "Module declaration '" + declared + "' does not match path-derived module name '" + expected + "'", analysis.snapshot.rootDocument.path, statement.span)]
			End If
			Exit
		Next
		Return diagnostics
	End Function

	Function ConfiguredSyntaxDiagnostics:TCompilerDiagnostic[](analysis:TLanguageAnalysis)
		Local diagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]
		If Not analysis Or Not analysis.snapshot Then Return diagnostics
		For Local document:TSourceDocumentModel = EachIn analysis.snapshot.documents
			If Not document Or Not document.tree Then Continue
			For Local token:TSyntaxToken = EachIn document.tree.root.tokens
				If token.kind <> TOKEN_DIRECTIVE Then Continue
				diagnostics :+ [TCompilerDiagnostic.Create("BMXC0002", "Conditional directives remained after source configuration was applied", document.path, token.span)]
				Exit
			Next
		Next
		Return diagnostics
	End Function

	Rem
	bbdoc: Loads and compiles a BlitzMax source file to typed compiler IR.
	param: The path of the source file to compile.
	param: Optional compiler configuration.
	param: Optional cache for loaded snapshot text.
	param: Optional cache for reusable generic backend units.
	returns: The staged compilation result.
	End Rem
	Function CompileFile:TCompilerResult(path:String, options:TCompilerOptions = Null, snapshotTextCache:TCompilerSnapshotTextCache = Null, backendUnitCache:TCompilerGenericBackendUnitCache = Null)
		If Not options Then options = TCompilerOptions.CreateDefault()
		Local result:TCompilerResult = New TCompilerResult
		If FileType(path) <> FILETYPE_FILE Then
			result.diagnostics :+ [TCompilerDiagnostic.Create("BMXC0001", "Source file was not found", path)]
			Return result
		End If
		Local resolvedPath:String = RealPath(path)
		Local started:Int = MilliSecs()
		Local text:String = LoadText(resolvedPath)
		Local loadMilliseconds:Int = MilliSecs() - started
		result = Compile(resolvedPath, text, TCompilerFileSnapshotResolver.Create(options, snapshotTextCache), options, backendUnitCache)
		result.sourceLoadMilliseconds = loadMilliseconds
		Return result
	End Function

	Rem
	bbdoc: Emits standalone C source from a successful compiler result.
	param: The successful compiler result.
	param: Receives backend diagnostics.
	returns: The generated C source, or an empty string on failure.
	End Rem
	Function EmitC:String(result:TCompilerResult, diagnostics:TCompilerDiagnostic[] Var)
		If Not result Or Not result.Succeeded() Then
			diagnostics = [TCompilerDiagnostic.Create("BMXC2000", "Successful compiler IR is required before C emission")]
			Return ""
		End If
		Return TCompilerCBackend.Emit(result.ir, diagnostics)
	End Function

	Rem
	bbdoc: Emits BlitzMax-runtime-compatible C source from a successful compiler result.
	param: The successful compiler result.
	param: Receives backend diagnostics.
	returns: The generated C source, or an empty string on failure.
	End Rem
	Function EmitRuntimeC:String(result:TCompilerResult, diagnostics:TCompilerDiagnostic[] Var)
		If Not result Or Not result.Succeeded() Then
			diagnostics = [TCompilerDiagnostic.Create("BMXC2040", "Successful compiler IR is required before runtime-compatible C emission")]
			Return ""
		End If
		Return TCompilerCBackend.EmitRuntime(result.ir, diagnostics)
	End Function

	Rem
	bbdoc: Emits the runtime C header for a successful compiler result.
	param: The successful compiler result.
	param: Receives backend diagnostics.
	returns: The generated header source, or an empty string on failure.
	End Rem
	Function EmitRuntimeHeader:String(result:TCompilerResult, diagnostics:TCompilerDiagnostic[] Var)
		If Not result Or Not result.Succeeded() Then
			diagnostics = [TCompilerDiagnostic.Create("BMXC2041", "Successful compiler IR is required before runtime header emission")]
			Return ""
		End If
		Return TCompilerCBackend.EmitRuntimeHeader(result.ir, diagnostics)
	End Function

	Rem
	bbdoc: Emits the compact BlitzMax module interface for a successful compiler result.
	param: The successful compiler result.
	param: Receives interface-emission diagnostics.
	returns: The compact interface text, or an empty string on failure.
	End Rem
	Function EmitInterface:String(result:TCompilerResult, diagnostics:TCompilerDiagnostic[] Var)
		If Not result Or Not result.Succeeded() Then
			diagnostics = [TCompilerDiagnostic.Create("BMXC2060", "Successful compiler IR is required before compact interface emission")]
			Return ""
		End If
		Return TCompilerInterfaceEmitter.Emit(result.analysis, result.ir, diagnostics, result.genericPlan)
	End Function

	Rem
	bbdoc: Emits the generic template artifacts planned by compilation.
	param: A compiler result containing a generic application plan.
	param: Receives artifact-emission diagnostics.
	returns: The generated template outputs.
	End Rem
	Function EmitGenericTemplateArtifacts:TCompilerGenericTemplateOutput[](result:TCompilerResult, diagnostics:TCompilerDiagnostic[] Var)
		If Not result Or Not result.genericPlan Then
			diagnostics = [TCompilerDiagnostic.Create("BMXC3051", "Compiler generic application plan is required before template artifact emission")]
			Return New TCompilerGenericTemplateOutput[0]
		End If
		diagnostics = New TCompilerDiagnostic[0]
		Return result.genericPlan.templateOutputs
	End Function

	Rem
	bbdoc: Emits the generic-specialization manifest planned by compilation.
	param: A compiler result containing a generic application plan.
	param: Receives manifest-emission diagnostics.
	returns: The generated manifest text, or an empty string on failure.
	End Rem
	Function EmitGenericManifest:String(result:TCompilerResult, diagnostics:TCompilerDiagnostic[] Var)
		If Not result Or Not result.genericPlan Then
			diagnostics = [TCompilerDiagnostic.Create("BMXC3050", "Compiler generic application plan is required before manifest emission")]
			Return ""
		End If
		diagnostics = New TCompilerDiagnostic[0]
		Return result.genericPlan.manifest
	End Function

	Rem
	bbdoc: Plans the files produced by a successful compilation.
	param: The successful compiler result.
	param: The destination path for application C source.
	param: The destination path for the runtime header.
	param: The destination path for the compact module interface.
	param: Receives output-planning diagnostics.
	returns: The build-output plan.
	End Rem
	Function PlanBuildOutputs:TCompilerBuildOutputPlan(result:TCompilerResult, applicationCPath:String, headerPath:String, interfacePath:String, diagnostics:TCompilerDiagnostic[] Var)
		If Not result Or Not result.Succeeded() Then
			diagnostics = [TCompilerDiagnostic.Create("BMXC3062", "Successful compiler IR is required before build-output planning")]
			Return New TCompilerBuildOutputPlan
		End If
		Return TCompilerBuildOutputPlanner.Build(result.analysis, result.ir, result.genericPlan, applicationCPath, headerPath, interfacePath, diagnostics)
	End Function
End Type
