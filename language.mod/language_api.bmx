' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "cancellation.bmx"
Import "blitzmax_parser.bmx"
Import "snapshot_loader.bmx"
Import "semantic_analyzer.bmx"
Import "expression_binding.bmx"
Import "compile_time_analysis.bmx"
Import "control_flow_analysis.bmx"
Import "data_flow_analysis.bmx"

Rem
bbdoc: Configures the optional stages of a language analysis.
about: The default instance performs expression binding, compile-time evaluation,
control-flow analysis, and data-flow analysis. Disable stages when a consumer only
needs syntax or a partial semantic model.
End Rem
Type TLanguageAnalysisOptions
	Field typeResolution:TTypeResolutionOptions
	Field controlFlow:TControlFlowAnalysisOptions
	Field bindExpressions:Int = True
	Field evaluateCompileTime:Int = True
	Field analyzeControlFlow:Int = True
	Field analyzeDataFlow:Int = True
	Field cancellationToken:TLanguageCancellationToken

	Rem
	bbdoc: Creates analysis options with all standard analysis stages enabled.
	returns: A new options object.
	End Rem
	Function Create:TLanguageAnalysisOptions()
		Return New TLanguageAnalysisOptions
	End Function
End Type

Rem
bbdoc: Contains the syntax, dependency snapshot, and semantic results of an analysis.
about: Syntax, snapshot, and semantic diagnostics remain separate because snapshot
failures may refer to dependency paths which do not have a syntax-tree source span.
Timing fields contain elapsed milliseconds for the corresponding analysis stages.
End Rem
Type TLanguageAnalysis
	Field syntaxTree:TSyntaxTree
	Field snapshot:TCompilationSnapshot
	Field model:TSemanticModel
	Field cancelled:Int
	Field snapshotMilliseconds:Int
	Field semanticMilliseconds:Int
	Field bindingMilliseconds:Int
	Field compileTimeMilliseconds:Int
	Field controlFlowMilliseconds:Int
	Field dataFlowMilliseconds:Int

	Rem
	bbdoc: Returns a document-local view of this compilation-unit analysis.
	param: The path of the root or recursively included source document.
	returns: A view using that document's syntax tree, or #Null if it is not in the snapshot.
	about: The semantic model and compilation snapshot are shared with this analysis,
	while syntax positions come from the requested document.
	End Rem
	Method ViewForDocument:TLanguageAnalysis(path:String)
		If Not syntaxTree Then Return Null
		If SameDocumentPath(syntaxTree.source.path, path) Then Return Self
		If Not snapshot Then Return Null
		For Local document:TSourceDocumentModel = EachIn snapshot.documents
			If Not document Or Not document.tree Or Not SameDocumentPath(document.path, path) Then Continue
			Local result:TLanguageAnalysis = New TLanguageAnalysis
			result.syntaxTree = document.tree
			result.snapshot = snapshot
			result.model = model
			result.cancelled = cancelled
			Return result
		Next
		Return Null
	End Method

	Rem
	bbdoc: Reports whether the complete requested analysis succeeded.
	returns: #True when analysis was not cancelled, contains no error diagnostics, and produced a semantic model.
	End Rem
	Method Succeeded:Int()
		If cancelled Then Return False
		If snapshot And Not snapshot.succeeded Then Return False
		If syntaxTree Then
			For Local diagnostic:TDiagnostic = EachIn syntaxTree.diagnostics
				If diagnostic.severity = DIAGNOSTIC_ERROR Then Return False
			Next
		End If
		If model Then
			For Local diagnostic:TDiagnostic = EachIn model.diagnostics
				If diagnostic.severity = DIAGNOSTIC_ERROR Then Return False
			Next
		End If
		Return model <> Null
	End Method

	Function SameDocumentPath:Int(left:String, right:String)
		left = left.Replace(Chr(92), "/")
		right = right.Replace(Chr(92), "/")
		?win32
		left = left.ToLower()
		right = right.ToLower()
		?
		Return left = right
	End Function
End Type

Rem
bbdoc: Provides the stable entry points for parsing and analysing BlitzMax source.
about: Use #AnalyzeText for a self-contained source string, #AnalyzeSnapshot for an
already constructed dependency snapshot, or #BuildAndAnalyze to resolve imports and
includes before analysis.
End Rem
Type TBlitzMaxLanguage
	Rem
	bbdoc: Parses and analyses a self-contained BlitzMax source string.
	param: The source text to analyse.
	param: The source path used in diagnostics and source locations.
	param: Optional analysis-stage configuration.
	returns: The completed language analysis.
	about: This entry point does not resolve imported modules or included files. Use
#BuildAndAnalyze when dependency resolution is required.
	End Rem
	Function AnalyzeText:TLanguageAnalysis(text:String, path:String = "<memory>", options:TLanguageAnalysisOptions = Null)
		Local result:TLanguageAnalysis = New TLanguageAnalysis
		Local effective:TLanguageAnalysisOptions = EffectiveOptions(options)
		Local parsed:TParseResult = TBlitzMaxParser.ParseText(text, path)
		result.syntaxTree = parsed.syntaxTree
		Local started:Int = MilliSecs()
		result.model = TBlitzMaxSemanticAnalyzer.Analyze(parsed.syntaxTree, effective.typeResolution, effective.cancellationToken)
		result.semanticMilliseconds = MilliSecs() - started
		result.cancelled = LanguageCancellationRequested(effective.cancellationToken)
		If Not result.cancelled Then RunOptionalPasses(result, effective)
		Return result
	End Function

	Rem
	bbdoc: Analyses a previously constructed compilation snapshot.
	param: The snapshot containing the root document and its dependencies.
	param: Optional analysis-stage configuration.
	returns: The completed language analysis.
	End Rem
	Function AnalyzeSnapshot:TLanguageAnalysis(snapshot:TCompilationSnapshot, options:TLanguageAnalysisOptions = Null)
		Local result:TLanguageAnalysis = New TLanguageAnalysis
		Local effective:TLanguageAnalysisOptions = EffectiveOptions(options)
		result.snapshot = snapshot
		If Not snapshot Or Not snapshot.rootDocument Then Return result
		result.syntaxTree = snapshot.rootDocument.tree
		Local started:Int = MilliSecs()
		result.model = TBlitzMaxSemanticAnalyzer.AnalyzeSnapshot(snapshot, effective.typeResolution, effective.cancellationToken)
		result.semanticMilliseconds = MilliSecs() - started
		result.cancelled = LanguageCancellationRequested(effective.cancellationToken)
		If Not result.cancelled Then RunOptionalPasses(result, effective)
		Return result
	End Function

	Rem
	bbdoc: Builds a dependency snapshot and analyses its root source document.
	param: The path of the root source document.
	param: The root source text.
	param: The resolver used to load includes, interfaces, and documentation.
	param: Snapshot construction options.
	param: Optional analysis-stage configuration.
	returns: The completed language analysis.
	End Rem
	Function BuildAndAnalyze:TLanguageAnalysis(path:String, text:String, resolver:TSnapshotResolver, snapshotOptions:TCompilationSnapshotOptions, analysisOptions:TLanguageAnalysisOptions = Null)
		Local started:Int = MilliSecs()
		Local snapshot:TCompilationSnapshot = TCompilationSnapshotBuilder.Build(path, text, resolver, snapshotOptions)
		Local snapshotMilliseconds:Int = MilliSecs() - started
		Local result:TLanguageAnalysis = AnalyzeSnapshot(snapshot, analysisOptions)
		result.snapshotMilliseconds = snapshotMilliseconds
		Return result
	End Function

	Function RunOptionalPasses(result:TLanguageAnalysis, options:TLanguageAnalysisOptions)
		Local model:TSemanticModel = result.model
		If Not model Or Not options.bindExpressions Then Return
		Local started:Int = MilliSecs()
		TExpressionBinder.Bind(model)
		result.bindingMilliseconds = MilliSecs() - started
		If options.evaluateCompileTime Then
			started = MilliSecs()
			TCompileTimeAnalyzer.Analyze(model)
			result.compileTimeMilliseconds = MilliSecs() - started
		End If
		If options.analyzeControlFlow Then
			started = MilliSecs()
			TControlFlowAnalyzer.Analyze(model, options.controlFlow)
			result.controlFlowMilliseconds = MilliSecs() - started
		End If
		If options.analyzeDataFlow Then
			started = MilliSecs()
			TDataFlowAnalyzer.Analyze(model)
			result.dataFlowMilliseconds = MilliSecs() - started
		End If
	End Function

	Function EffectiveOptions:TLanguageAnalysisOptions(options:TLanguageAnalysisOptions)
		If options Then Return options
		Return TLanguageAnalysisOptions.Create()
	End Function
End Type
