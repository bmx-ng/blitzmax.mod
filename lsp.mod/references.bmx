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

' Current-document references. Symbol identity comes from semantic binding;
' unopened files are deliberately not searched until a workspace source index
' can provide complete results.
Type TBlitzMaxLspReferences
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int, includeDeclaration:Int)
		Local result:TJSONArray = JsonArray()
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Or Not context.location Or Not context.location.symbol Then Return result
		Local symbol:TSymbol = context.location.symbol
		Local source:TSourceText = context.analysis.syntaxTree.source
		Local seen:TMap = New TMap
		For Local node:TSyntaxNode = EachIn context.navigator.nodes
			Local matches:Int = ReferencesSymbol(context.analysis.model, node, symbol)
			If includeDeclaration And context.analysis.model.DeclaredSymbol(node) = symbol Then matches = True
			If Not matches Then Continue
			Local span:TSourceSpan = TBlitzMaxLspNavigation.ReferenceSpan(node)
			If Not span Then Continue
			Local key:String = span.start + ":" + span.length
			If seen.Contains(key) Then Continue
			seen.Insert(key, span)
			Local location:TJSONObject = JsonObject()
			location.Set("uri", document.uri)
			location.Set("range", TLspPositions.Range(source, span))
			result.Append(location)
		Next
		Return result
	End Function

	Function ReferencesSymbol:Int(model:TSemanticModel, node:TSyntaxNode, symbol:TSymbol)
		If model.ReferencedSymbol(node) = symbol Then Return True
		Local typeReference:TTypeReferenceSyntax = TTypeReferenceSyntax(node)
		If typeReference And TBlitzMaxLspNavigation.TypeSymbol(model.TypeOf(typeReference)) = symbol Then Return True
		Return False
	End Function
End Type
