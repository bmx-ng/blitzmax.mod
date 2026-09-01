' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.FileSystem

Import "blitzmax_parser.bmx"
Import "conditional_evaluator.bmx"
Import "interface_documentation.bmx"
Import "generic_template_codec.bmx"
Import "snapshot_model.bmx"

Rem
bbdoc: Constructs a compilation snapshot by resolving a root document's dependencies.
End Rem
Type TCompilationSnapshotBuilder
	Field result:TCompilationSnapshot
	Field resolver:TSnapshotResolver
	Field options:TCompilationSnapshotOptions
	Field documentsByPath:TMap = New TMap
	Field documentStates:TMap = New TMap
	Field interfacesByPath:TMap = New TMap

	Rem
	bbdoc: Builds a parsed dependency snapshot for a BlitzMax compilation unit.
	param: The path identifying the root source document.
	param: The root source text.
	param: The resolver used for includes, interfaces, templates, and documentation.
	param: Optional snapshot construction settings.
	returns: The completed snapshot, including diagnostics when dependencies could not be resolved.
	End Rem
	Function Build:TCompilationSnapshot(rootPath:String, rootText:String, resolver:TSnapshotResolver, options:TCompilationSnapshotOptions = Null)
		Local builder:TCompilationSnapshotBuilder = New TCompilationSnapshotBuilder
		builder.result = New TCompilationSnapshot
		builder.resolver = resolver
		builder.options = options
		If Not builder.options Then builder.options = New TCompilationSnapshotOptions
		' bmxng and bmxng2 identify intrinsic compiler/language generations rather
		' than configurable target or build-profile symbols.
		builder.options.EnsureConditionalSymbol("bmxng")
		builder.options.EnsureConditionalSymbol("bmxng2")
		builder.result.options = builder.options

		If Not resolver Then
			builder.AddDiagnostic("BMX4000", "The compiler could not resolve source and module dependencies.", rootPath)
			builder.result.succeeded = False
			Return builder.result
		End If

		If builder.options.requireCoreInterface Then builder.LoadCore()
		builder.result.rootDocument = builder.LoadDocument(TSnapshotText.Create(rootPath, rootText), True, Null, Null)
		If builder.options.requireCoreInterface And builder.options.implicitRuntime And builder.result.coreInterface Then builder.LoadImplicitRuntime(rootPath, rootText)
		builder.LoadImplicitImports(rootPath)
		builder.result.succeeded = Not builder.HasErrors()
		Return builder.result
	End Function

	Method LoadImplicitRuntime(rootPath:String, rootText:String)
		' Module builds already carry their normalized ownership from bmk. Avoid
		' splitting, trimming and lowercasing the complete source merely to
		' rediscover the runtime module declaration.
		If options.sourceModuleName = "brl.blitz" Then Return
		If Not options.sourceModuleName.length And IsBrlBlitzSource(rootText) Then Return
		If RootImportsLogicalName("brl.blitz") Then Return
		Local resolved:TSnapshotText = resolver.ResolveInterface(rootPath, "brl.blitz", False, False)
		If Not resolved Then
			AddDiagnostic("BMX4003", "Compiler interface for implicit runtime module 'brl.blitz' is unavailable.", rootPath)
			Return
		End If
		Local edge:TImportEdge = New TImportEdge
		edge.target = LoadInterface(resolved, "brl.blitz", False)
		result.rootDocument.AddImport(edge)
	End Method

	Method LoadImplicitImports(rootPath:String)
		If Not result.rootDocument Then Return
		For Local moduleName:String = EachIn options.implicitImports
			moduleName = moduleName.Trim().ToLower()
			If Not moduleName.length Or RootImportsLogicalName(moduleName) Then Continue
			Local resolved:TSnapshotText = resolver.ResolveInterface(rootPath, moduleName, False, True)
			If Not resolved Then
				AddDiagnostic("BMX4003", "Compiler interface for implicit application module '" + moduleName + "' is unavailable.", rootPath)
				Continue
			End If
			Local edge:TImportEdge = New TImportEdge
			edge.target = LoadInterface(resolved, moduleName, False)
			result.rootDocument.AddImport(edge)
		Next
	End Method

	Method RootImportsLogicalName:Int(logicalName:String)
		If Not result.rootDocument Then Return False
		For Local edge:TImportEdge = EachIn result.rootDocument.imports
			If edge And edge.target And edge.target.logicalName.Compare(logicalName, False) = 0 Then Return True
		Next
		Return False
	End Method

	Function IsBrlBlitzSource:Int(text:String)
		For Local line:String = EachIn text.Replace(Chr(13), "").Split(Chr(10))
			If line.Trim().ToLower() = "module brl.blitz" Then Return True
		Next
		Return False
	End Function

	Method LoadCore()
		Local resolved:TSnapshotText = resolver.ResolveCoreInterface(options.targetPlatform)
		If Not resolved Then
			AddDiagnostic("BMX4001", "The core class interface is missing for target '" + options.targetPlatform + "'.", "")
			Return
		End If
		result.coreInterface = LoadInterface(resolved, "brl.classes", True)
		AddCoreIntrinsicDeclarations(result.coreInterface)
	End Method

	Method AddCoreIntrinsicDeclarations(dependency:TInterfaceDependency)
		If Not dependency Or Not dependency.interfaceFile Then Return
		' These callable language intrinsics are supplied by the runtime but are
		' not class declarations in blitz_classes.i. Production bcc injects the
		' same signatures through its keyword interface.
		Local intrinsicText:String = "superstrict~nIncbinPtr@*(value$)=~qbbIncbinPtr~q~nIncbinLen%(value$)=~qbbIncbinLen~q"
		Local intrinsicFile:TInterfaceFile = TBlitzMaxParser.ParseInterfaceText(intrinsicText, "<core-intrinsics>")
		For Local intrinsic:TInterfaceRecord = EachIn intrinsicFile.declarations
			Local present:Int
			For Local existing:TInterfaceRecord = EachIn dependency.interfaceFile.declarations
				If existing.name.ToLower() = intrinsic.name.ToLower() And existing.kind = intrinsic.kind Then present = True; Exit
			Next
			If Not present Then dependency.interfaceFile.AddDeclaration(intrinsic)
		Next
	End Method

	Method LoadDocument:TSourceDocumentModel(resolved:TSnapshotText, isRoot:Int, including:TSourceDocumentModel, includeSyntax:TIncludeDirectiveSyntax)
		Local key:String = PathKey(resolved.path)
		Local existing:TSourceDocumentModel = TSourceDocumentModel(documentsByPath.ValueForKey(key))
		Local state:String = String(documentStates.ValueForKey(key))
		If state = "loading" Then
			Local path:String = resolved.path
			Local span:TSourceSpan
			If including Then path = including.path
			If includeSyntax Then span = includeSyntax.span
			AddDiagnostic("BMX4004", "Include cycle reaches '" + resolved.path + "'.", path, span)
			Return existing
		End If
		If existing Then Return existing

		Local document:TSourceDocumentModel = New TSourceDocumentModel
		document.path = resolved.path
		document.isRoot = isRoot
		If options.parseConfiguredConditionals Then
			document.tree = TBlitzMaxParser.ParseConfiguredText(resolved.text, resolved.path, options.conditionalSymbols).syntaxTree
		Else
			document.tree = TBlitzMaxParser.ParseText(resolved.text, resolved.path).syntaxTree
		End If
		document.effectiveSourceMode = document.tree.root.sourceMode
		If including Then document.effectiveSourceMode = including.effectiveSourceMode
		For Local diagnostic:TDiagnostic = EachIn document.tree.diagnostics
			AddDiagnostic(diagnostic.code, diagnostic.message, resolved.path, diagnostic.span)
		Next
		documentsByPath.Insert(key, document)
		documentStates.Insert(key, "loading")
		result.AddDocument(document)
		VisitNodes(document, document.tree.root.members)
		documentStates.Insert(key, "loaded")
		Return document
	End Method

	Method VisitNodes(document:TSourceDocumentModel, nodes:TSyntaxNode[])
		For Local node:TSyntaxNode = EachIn nodes
			Local includeSyntax:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
			If includeSyntax Then
				LoadInclude(document, includeSyntax)
				Continue
			End If
			Local importSyntax:TImportDirectiveSyntax = TImportDirectiveSyntax(node)
			If importSyntax Then
				LoadSourceImport(document, importSyntax)
				Continue
			End If
			Local conditional:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
			If conditional Then
				Local indexes:Int[] = TConditionalEvaluator.ActiveBranchIndexes(conditional, options.conditionalSymbols)
				For Local index:Int = EachIn indexes
					VisitNodes(document, conditional.branches[index].body.statements)
				Next
				Continue
			End If
			Local block:TBlockSyntax = TBlockSyntax(node)
			If block Then VisitNodes(document, block.statements)
		Next
	End Method

	Method LoadInclude(document:TSourceDocumentModel, syntax:TIncludeDirectiveSyntax)
		If Not syntax.pathToken Then Return
		Local resolved:TSnapshotText = resolver.ResolveInclude(document.path, syntax.pathText)
		If Not resolved Then
			AddDiagnostic("BMX4002", "Included source '" + syntax.pathText + "' could not be found.", document.path, syntax.span)
			Return
		End If
		Local edge:TIncludeEdge = New TIncludeEdge
		edge.syntax = syntax
		edge.target = LoadDocument(resolved, False, document, syntax)
		document.AddInclude(edge)
	End Method

	Method LoadSourceImport(document:TSourceDocumentModel, syntax:TImportDirectiveSyntax)
		If Not syntax.targetText.length Then Return
		If syntax.isNativeImport Then Return
		Local resolved:TSnapshotText = resolver.ResolveInterface(document.path, syntax.targetText, syntax.isFileImport, syntax.isFramework)
		If Not resolved Then
			AddDiagnostic("BMX4003", "Compiler interface for '" + syntax.targetText + "' is unavailable.", document.path, syntax.span)
			Return
		End If
		Local edge:TImportEdge = New TImportEdge
		edge.syntax = syntax
		edge.target = LoadInterface(resolved, syntax.targetText, False)
		document.AddImport(edge)
	End Method

	Method LoadInterface:TInterfaceDependency(resolved:TSnapshotText, logicalName:String, isCore:Int)
		Local key:String = PathKey(resolved.path)
		Local existing:TInterfaceDependency = TInterfaceDependency(interfacesByPath.ValueForKey(key))
		If existing Then Return existing

		Local dependency:TInterfaceDependency = New TInterfaceDependency
		dependency.path = resolved.path
		dependency.logicalName = logicalName
		dependency.isCore = isCore
		If resolved.interfaceFile Then
			dependency.interfaceFile = resolved.interfaceFile
		Else
			dependency.interfaceFile = TBlitzMaxParser.ParseInterfaceText(resolved.text, resolved.path)
		End If
		interfacesByPath.Insert(key, dependency)
		result.AddInterface(dependency)

		If dependency.interfaceFile.documentationSource.length Then
			Local documentation:TSnapshotText = resolver.ResolveDocumentation(resolved.path, dependency.interfaceFile.documentationSource)
			If documentation Then
				dependency.documentationSource = documentation
				TInterfaceDocumentationMerger.Apply(dependency.interfaceFile, documentation.path, documentation.text)
			End If
		End If

		For Local diagnostic:TInterfaceDiagnostic = EachIn dependency.interfaceFile.diagnostics
			AddDiagnostic(diagnostic.code, diagnostic.message, resolved.path)
		Next
		LoadGenericTemplates(dependency, dependency.interfaceFile.declarations, resolved.path)

		For Local item:TInterfaceImport = EachIn dependency.interfaceFile.imports
			If item.isFileImport And Not item.name.ToLower().EndsWith(".bmx") Then Continue
			Local importingPath:String = InterfaceSourcePath(resolved.path)
			If item.originPath.length Then importingPath = item.originPath
			Local imported:TSnapshotText = resolver.ResolveInterface(importingPath, item.name, item.isFileImport, False)
			If Not imported Then
				AddDiagnostic("BMX4003", "Compiler interface for '" + item.name + "' is unavailable.", resolved.path)
				Continue
			End If
			dependency.AddImport(LoadInterface(imported, item.name, False))
		Next
		Return dependency
	End Method

	Method LoadGenericTemplates(dependency:TInterfaceDependency, records:TInterfaceRecord[], interfacePath:String)
		For Local record:TInterfaceRecord = EachIn records
			If record.genericTemplateReference.length Then
				If record.genericTemplateFormat < GENERIC_TEMPLATE_MIN_READ_VERSION Or record.genericTemplateFormat > GENERIC_TEMPLATE_FORMAT_VERSION Then
					AddDiagnostic("BMX4010", "Generic template reference for '" + record.name + "' uses unsupported format " + record.genericTemplateFormat + ".", interfacePath)
				Else
					Local resolved:TSnapshotText = resolver.ResolveGenericTemplate(interfacePath, record.genericTemplateReference)
					If Not resolved Then
						AddDiagnostic("BMX4011", "Generic template artifact '" + record.genericTemplateReference + "' for '" + record.name + "' is unavailable from the compiler interface.", interfacePath)
					Else
						Local decoded:TGenericTemplateArtifactDecodeResult
						If resolved.genericTemplateArtifact Or resolved.genericTemplateDiagnostics.length Then
							decoded = New TGenericTemplateArtifactDecodeResult
							decoded.artifact = resolved.genericTemplateArtifact
							decoded.diagnostics = resolved.genericTemplateDiagnostics[..]
							If decoded.artifact And record.genericTemplateRevision.length And decoded.artifact.EffectiveContentRevision().ToLower() <> record.genericTemplateRevision.ToLower() Then
								decoded.artifact = Null
								decoded.diagnostics = ["BMXGT106 generic template artifact revision does not match the interface reference"]
							End If
						Else
							decoded = TGenericTemplateArtifactCodec.Decode(resolved.text, record.genericTemplateRevision)
						End If
						If Not decoded.Succeeded() Then
							Local message:String = "Generic template artifact '" + resolved.path + "' for '" + record.name + "' is invalid."
							If decoded.diagnostics.length Then message :+ " " + decoded.diagnostics[0]
							AddDiagnostic("BMX4012", message, resolved.path)
						Else If decoded.artifact.identity.StableName() <> record.genericTemplateIdentity.ToLower() Then
							AddDiagnostic("BMX4013", "Generic template artifact identity '" + decoded.artifact.identity.StableName() + "' does not match interface identity '" + record.genericTemplateIdentity + "'.", resolved.path)
						Else If decoded.artifact.languageLinkageRevision.ToLower() <> record.genericTemplateLanguageRevision.ToLower() Then
							AddDiagnostic("BMX4014", "Generic template artifact language revision does not match its interface reference.", resolved.path)
						Else
							record.genericTemplateArtifact = decoded.artifact
							dependency.AddGenericTemplate(decoded.artifact)
						End If
					End If
				End If
			End If
			If record.members.length Then LoadGenericTemplates(dependency, record.members, interfacePath)
		Next
	End Method

	' A quoted import serialized into .bmx/name.bmx.<mung>.i remains relative
	' to the original name.bmx source, not to its hidden build directory.
	Function InterfaceSourcePath:String(interfacePath:String)
		Local normalized:String = interfacePath.Replace(Chr(92), "/")
		Local interfaceDirectory:String = ExtractDir(normalized)
		If StripDir(interfaceDirectory).ToLower() <> ".bmx" Then Return normalized
		Local fileName:String = StripDir(normalized)
		Local marker:Int = fileName.ToLower().Find(".bmx.")
		If marker < 0 Then Return normalized
		Return ExtractDir(interfaceDirectory) + "/" + fileName[..marker + 4]
	End Function

	Method HasErrors:Int()
		If result.diagnostics.length Then Return True
		For Local document:TSourceDocumentModel = EachIn result.documents
			If document.tree.diagnostics.length Then Return True
		Next
		Return False
	End Method

	Method AddDiagnostic(code:String, message:String, path:String, span:TSourceSpan = Null)
		result.AddDiagnostic(TSnapshotDiagnostic.Create(code, message, path, span))
	End Method

	Function PathKey:String(path:String)
		Return path.Replace(Chr(92), "/").ToLower()
	End Function
End Type
