' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "navigation_features.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

' Safe first-stage rename. Only lexically scoped symbols declared in the
' requesting source document are eligible, so the server never implies that a
' public or imported API was renamed across unopened source files.
Type TBlitzMaxLspRename
	Function Prepare:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		Local symbol:TSymbol = RenameTarget(context, document)
		If Not symbol Then Return JsonNull()
		Local span:TSourceSpan = TargetSpan(context, symbol)
		If Not span Then Return JsonNull()
		Local result:TJSONObject = JsonObject()
		result.Set("range", TLspPositions.Range(context.analysis.syntaxTree.source, span))
		result.Set("placeholder", symbol.name)
		Return result
	End Function

	Function Rename:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int, newName:String)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		Local symbol:TSymbol = RenameTarget(context, document)
		If Not symbol Or Not ValidIdentifier(newName) Then Return JsonNull()
		If Not CollisionFree(context, symbol, newName) Then Return JsonNull()
		Local edits:TJSONArray = JsonArray()
		Local seen:TMap = New TMap
		AppendEdit(edits, seen, context.analysis.syntaxTree.source, symbol.nameToken.span, newName)
		For Local value:Object = EachIn context.analysis.model.referencedSymbolMap.Keys()
			Local node:TSyntaxNode = TSyntaxNode(value)
			If Not node Or Not context.navigator.ContainsNode(node) Then Continue
			If context.analysis.model.ReferencedSymbol(node) <> symbol Then Continue
			AppendEdit(edits, seen, context.analysis.syntaxTree.source, TBlitzMaxLspNavigation.ReferenceSpan(node), newName)
		Next
		If edits.Size() = 0 Then Return JsonNull()
		Local changes:TJSONObject = JsonObject()
		changes.Set(document.uri, edits)
		Local result:TJSONObject = JsonObject()
		result.Set("changes", changes)
		Return result
	End Function

	Function RenameTarget:TSymbol(context:TLspFeatureContext, document:TLspDocument)
		If Not context Or Not context.location Or Not context.location.symbol Or Not document Then Return Null
		Local symbol:TSymbol = context.location.symbol
		If symbol.isImported Or Not SupportedKind(symbol.kind) Then Return Null
		If SnapshotPathKey(symbol.originPath) <> SnapshotPathKey(document.path) Then Return Null
		If Not symbol.declaration Or Not context.navigator.ContainsNode(symbol.declaration) Or Not symbol.nameToken Then Return Null
		Return symbol
	End Function

	Function SupportedKind:Int(kind:Int)
		Return kind = SYMBOL_LOCAL Or kind = SYMBOL_PARAMETER Or kind = SYMBOL_CATCH_PARAMETER Or kind = SYMBOL_TYPE_PARAMETER
	End Function

	Function TargetSpan:TSourceSpan(context:TLspFeatureContext, symbol:TSymbol)
		If Not context Or Not context.location Or Not context.location.syntax Then Return Null
		Local node:TSyntaxNode = context.location.syntax.node
		If node Then
			Local span:TSourceSpan = TBlitzMaxLspNavigation.ReferenceSpan(node)
			If span And span.Contains(context.offset) Then Return span
		End If
		Return symbol.nameToken.span
	End Function

	Function ValidIdentifier:Int(name:String)
		If Not name.length Or name <> name.Trim() Then Return False
		Local lexed:TLexResult = TBlitzMaxLexer.Lex(name, "<rename>")
		If Not lexed Or lexed.diagnostics.length Or lexed.tokens.length <> 2 Then Return False
		Local token:TSyntaxToken = lexed.tokens[0]
		Return token.kind = TOKEN_IDENTIFIER And token.text = name And token.span.length = name.length
	End Function

	Function CollisionFree:Int(context:TLspFeatureContext, symbol:TSymbol, newName:String)
		If symbol.normalizedName = newName.ToLower() Then Return True
		If ScopeHasOtherSymbol(symbol.containingScope, symbol, newName) Then Return False
		For Local value:Object = EachIn context.analysis.model.referencedSymbolMap.Keys()
			Local node:TSyntaxNode = TSyntaxNode(value)
			If Not node Or Not context.navigator.ContainsNode(node) Then Continue
			If context.analysis.model.ReferencedSymbol(node) <> symbol Then Continue
			Local scope:TScope = ScopeForNode(context.analysis.model, context.navigator, node)
			If ScopeHasOtherSymbol(scope, symbol, newName) Then Return False
		Next
		Return True
	End Function

	Function ScopeForNode:TScope(model:TSemanticModel, navigator:TSyntaxNavigator, node:TSyntaxNode)
		Local current:TSyntaxNode = node
		While current
			Local scope:TScope = model.ScopeFor(current)
			If scope Then Return scope
			current = navigator.Parent(current)
		Wend
		Return model.globalScope
	End Function

	Function ScopeHasOtherSymbol:Int(scope:TScope, symbol:TSymbol, name:String)
		If Not scope Then Return False
		For Local candidate:TSymbol = EachIn scope.Lookup(name)
			If candidate <> symbol Then Return True
		Next
		Return False
	End Function

	Function AppendEdit(edits:TJSONArray, seen:TMap, source:TSourceText, span:TSourceSpan, newName:String)
		If Not span Then Return
		Local key:String = span.start + ":" + span.length
		If seen.Contains(key) Then Return
		seen.Insert(key, span)
		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, span))
		edit.Set("newText", newName)
		edits.Append(edit)
	End Function
End Type
