' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "auto_import_completion.bmx"
Import "documents.bmx"
Import "import_completion.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

' Source-backed quick fixes. Each requested diagnostic is matched against the
' current immutable syntax tree before an edit is offered, preventing a stale
' or fabricated client range from deleting unrelated source text.
Type TBlitzMaxLspCodeActions
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, params:TJSONObject)
		Local result:TJSONArray = JsonArray()
		If Not document Or Not workspace Or Not params Then Return result
		Local context:TJSONObject = TJSONObject(params.Get("context"))
		If Not context Or Not AllowsQuickFix(TJSONArray(context.Get("only"))) Then Return result
		Local requestedDiagnostics:TJSONArray = TJSONArray(context.Get("diagnostics"))
		If Not requestedDiagnostics Or requestedDiagnostics.Size() = 0 Then Return result

		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.syntaxTree Or Not analysis.syntaxTree.source Then Return result

		For Local index:Int = 0 Until requestedDiagnostics.Size()
			Local requested:TJSONObject = TJSONObject(requestedDiagnostics.Get(index))
			If Not requested Then Continue
			If requested.GetString("source").length And requested.GetString("source") <> "blitzmax" Then Continue
			Local requestedRange:TJSONObject = TJSONObject(requested.Get("range"))
			If Not requestedRange Then Continue
			Select requested.GetString("code")
				Case "BMX2105"
					For Local diagnostic:TDiagnostic = EachIn analysis.syntaxTree.diagnostics
						If Not Matches(document, analysis.syntaxTree.source, diagnostic, requestedRange, "BMX2105") Then Continue
						result.Append(RemovePostfixTypeAction(document.uri, analysis.syntaxTree.source, diagnostic.span, requested))
						Exit
					Next
				Case "BMX3300"
					If Not analysis.model Then Continue
					For Local diagnostic:TDiagnostic = EachIn analysis.model.diagnostics
						If Not Matches(document, analysis.syntaxTree.source, diagnostic, requestedRange, "BMX3300") Then Continue
						Local action:TJSONObject = AddMissingImportAction(document, workspace, analysis, diagnostic, requested)
						If action Then result.Append(action)
						Exit
					Next
			End Select
		Next
		Return result
	End Function

	Function AllowsQuickFix:Int(only:TJSONArray)
		If Not only Or only.Size() = 0 Then Return True
		For Local index:Int = 0 Until only.Size()
			Local kind:TJSONString = TJSONString(only.Get(index))
			If kind And kind.Value() = "quickfix" Then Return True
		Next
		Return False
	End Function

	Function Matches:Int(document:TLspDocument, source:TSourceText, diagnostic:TDiagnostic, requestedRange:TJSONObject, code:String)
		If Not diagnostic Or diagnostic.code <> code Or Not diagnostic.span Then Return False
		If diagnostic.path.length And NormalizeWorkspacePath(diagnostic.path) <> NormalizeWorkspacePath(document.path) Then Return False
		Return SameRange(TLspPositions.Range(source, diagnostic.span), requestedRange)
	End Function

	Function AddMissingImportAction:TJSONObject(document:TLspDocument, workspace:TLspWorkspaceContext, analysis:TLanguageAnalysis, diagnostic:TDiagnostic, requested:TJSONObject)
		If Not diagnostic.message.StartsWith("Name '") Then Return Null
		Local name:String = analysis.syntaxTree.source.Slice(diagnostic.span)
		If Not IsIdentifier(name) Then Return Null
		Local moduleName:String = UniqueModuleForValue(workspace, name)
		If Not moduleName.length Then Return Null
		Local families:TMap = New TMap
		Local imported:TMap = New TMap
		TBlitzMaxLspImportCompletion.CollectWrittenModules(analysis.syntaxTree.source.text, families, imported)
		If imported.Contains(moduleName.ToLower()) Then Return Null

		Local edit:TJSONObject = TBlitzMaxLspAutoImportCompletion.ImportEdit(analysis.syntaxTree, analysis.syntaxTree.source, moduleName)
		Local edits:TJSONArray = JsonArray()
		edits.Append(edit)
		Local changes:TJSONObject = JsonObject()
		changes.Set(document.uri, edits)
		Local workspaceEdit:TJSONObject = JsonObject()
		workspaceEdit.Set("changes", changes)
		Local diagnostics:TJSONArray = JsonArray()
		diagnostics.Append(requested)
		Local action:TJSONObject = JsonObject()
		action.Set("title", "Import " + moduleName)
		action.Set("kind", "quickfix")
		action.Set("diagnostics", diagnostics)
		action.Set("isPreferred", New TJSONBool.Create(True))
		action.Set("edit", workspaceEdit)
		Return action
	End Function

	Function UniqueModuleForValue:String(workspace:TLspWorkspaceContext, name:String)
		If Not workspace Or Not name.length Then Return ""
		Local installed:TLspInstalledModuleCatalogue = workspace.InstalledCatalogue()
		If Not installed Or Not installed.catalogue Then Return ""
		Local moduleName:String
		For Local symbol:TModuleCatalogueSymbol = EachIn installed.catalogue.SymbolsNamed(name)
			If Not symbol Or symbol.parent Or Not symbol.isPublic Or Not symbol.moduleEntry Or symbol.moduleEntry.isCore Then Continue
			If TInterfaceSymbolImporter.IsLegacyGenericImplementation(symbol.record) Then Continue
			If symbol.kind <> SYMBOL_ROUTINE And symbol.kind <> SYMBOL_GLOBAL And symbol.kind <> SYMBOL_CONST Then Continue
			If Not moduleName.length Then
				moduleName = symbol.moduleEntry.name
			Else If moduleName.ToLower() <> symbol.moduleEntry.normalizedName Then
				Return ""
			End If
		Next
		Return moduleName
	End Function

	Function IsIdentifier:Int(value:String)
		If Not value.length Or Not TBlitzMaxLexer.IsIdentifierStart(value[0]) Then Return False
		For Local index:Int = 1 Until value.length
			If Not TBlitzMaxLexer.IsIdentifierPart(value[index]) Then Return False
		Next
		Return True
	End Function

	Function SameRange:Int(left:TJSONObject, right:TJSONObject)
		If Not left Or Not right Then Return False
		Local leftStart:TJSONObject = TJSONObject(left.Get("start"))
		Local leftEnd:TJSONObject = TJSONObject(left.Get("end"))
		Local rightStart:TJSONObject = TJSONObject(right.Get("start"))
		Local rightEnd:TJSONObject = TJSONObject(right.Get("end"))
		If Not leftStart Or Not leftEnd Or Not rightStart Or Not rightEnd Then Return False
		Return leftStart.GetInteger("line") = rightStart.GetInteger("line") And ..
			leftStart.GetInteger("character") = rightStart.GetInteger("character") And ..
			leftEnd.GetInteger("line") = rightEnd.GetInteger("line") And ..
			leftEnd.GetInteger("character") = rightEnd.GetInteger("character")
	End Function

	Function RemovePostfixTypeAction:TJSONObject(uri:String, source:TSourceText, span:TSourceSpan, diagnostic:TJSONObject)
		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, span))
		edit.Set("newText", "")
		Local edits:TJSONArray = JsonArray()
		edits.Append(edit)
		Local changes:TJSONObject = JsonObject()
		changes.Set(uri, edits)
		Local workspaceEdit:TJSONObject = JsonObject()
		workspaceEdit.Set("changes", changes)

		Local diagnostics:TJSONArray = JsonArray()
		diagnostics.Append(diagnostic)
		Local action:TJSONObject = JsonObject()
		action.Set("title", "Remove postfix type annotation")
		action.Set("kind", "quickfix")
		action.Set("diagnostics", diagnostics)
		action.Set("isPreferred", New TJSONBool.Create(True))
		action.Set("edit", workspaceEdit)
		Return action
	End Function
End Type
