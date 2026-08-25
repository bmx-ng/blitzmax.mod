' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import Text.Json
Import BlitzMax.Language
Import "protocol.bmx"
Import "documents.bmx"
Import "workspaces.bmx"

Type TBlitzMaxLspDiagnostics
	Function Publish:TJSONObject(document:TLspDocument, workspace:TLspWorkspaceContext = Null, cancellationToken:TLanguageCancellationToken = Null)
		Local params:TJSONObject = JsonObject()
		params.Set("uri", document.uri)
		params.Set("version", document.version)
		Local items:TJSONArray = JsonArray()
		Local analysis:TLanguageAnalysis
		If workspace Then
			analysis = workspace.Analyze(document, cancellationToken)
		Else
			analysis = TBlitzMaxLanguage.AnalyzeText(document.text, document.path)
		End If
		If analysis.syntaxTree Then
			For Local diagnostic:TDiagnostic = EachIn analysis.syntaxTree.diagnostics
				If DiagnosticBelongsToDocument(diagnostic, document.path) Then items.Append(ToLspDiagnostic(diagnostic, analysis.syntaxTree.source))
			Next
		End If
		If analysis.model And analysis.syntaxTree Then
			For Local diagnostic:TDiagnostic = EachIn analysis.model.diagnostics
				If DiagnosticBelongsToDocument(diagnostic, document.path) Then items.Append(ToLspDiagnostic(diagnostic, analysis.syntaxTree.source))
			Next
		End If
		If analysis.snapshot Then
			For Local diagnostic:TSnapshotDiagnostic = EachIn analysis.snapshot.diagnostics
				' Parser diagnostics are already exposed by syntaxTree. Snapshot
				' diagnostics in the BMX4xxx range describe dependency loading.
				If diagnostic.code.StartsWith("BMX4") Then items.Append(ToLspSnapshotDiagnostic(diagnostic, analysis.syntaxTree.source))
			Next
		End If
		params.Set("diagnostics", items)
		Return JsonNotification("textDocument/publishDiagnostics", params)
	End Function

	' Diagnostics without provenance are retained for compatibility with custom
	' analysis stages. Built-in stages assign a path, allowing dependency and
	' included-file diagnostics to be kept off the requesting document.
	Function DiagnosticBelongsToDocument:Int(diagnostic:TDiagnostic, documentPath:String)
		If Not diagnostic Or diagnostic.path.length = 0 Then Return True
		Return NormalizeWorkspacePath(diagnostic.path) = NormalizeWorkspacePath(documentPath)
	End Function

	Function ToLspSnapshotDiagnostic:TJSONObject(diagnostic:TSnapshotDiagnostic, source:TSourceText)
		Local span:TSourceSpan = diagnostic.span
		If Not span Then span = TSourceSpan.Create(0, 0)
		Local startPosition:TSourcePosition = source.Position(span.start)
		Local endPosition:TSourcePosition = source.Position(span.EndOffset())
		Local range:TJSONObject = JsonObject()
		range.Set("start", Position(startPosition))
		range.Set("end", Position(endPosition))
		Local message:String = diagnostic.message
		If diagnostic.path.length And diagnostic.path <> source.path Then message = diagnostic.path + ": " + message
		Local result:TJSONObject = JsonObject()
		result.Set("range", range)
		result.Set("severity", 1)
		result.Set("code", diagnostic.code)
		result.Set("source", "blitzmax")
		result.Set("message", message)
		Return result
	End Function

	Function Clear:TJSONObject(uri:String)
		Local params:TJSONObject = JsonObject()
		params.Set("uri", uri)
		params.Set("diagnostics", JsonArray())
		Return JsonNotification("textDocument/publishDiagnostics", params)
	End Function

	Function ToLspDiagnostic:TJSONObject(diagnostic:TDiagnostic, source:TSourceText)
		Local startPosition:TSourcePosition = source.Position(diagnostic.span.start)
		Local endPosition:TSourcePosition = source.Position(diagnostic.span.EndOffset())
		Local range:TJSONObject = JsonObject()
		range.Set("start", Position(startPosition))
		range.Set("end", Position(endPosition))
		Local result:TJSONObject = JsonObject()
		result.Set("range", range)
		result.Set("severity", LspSeverity(diagnostic.severity))
		result.Set("code", diagnostic.code)
		result.Set("source", "blitzmax")
		result.Set("message", diagnostic.message)
		Return result
	End Function

	Function Position:TJSONObject(position:TSourcePosition)
		Local result:TJSONObject = JsonObject()
		result.Set("line", position.line)
		result.Set("character", position.column)
		Return result
	End Function

	Function LspSeverity:Int(severity:Int)
		Select severity
			Case DIAGNOSTIC_ERROR
				Return 1
			Case DIAGNOSTIC_WARNING
				Return 2
			Default
				Return 3
		End Select
	End Function
End Type
