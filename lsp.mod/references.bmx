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

' References within the requesting semantic compilation unit. A BlitzMax root
' and its recursive Include files share one model, so every source tree already
' has exact symbol identity without requiring a speculative workspace scan.
Type TBlitzMaxLspReferences
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int, includeDeclaration:Int)
		Local result:TJSONArray = JsonArray()
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Or Not context.location Or Not context.location.symbol Then Return result
		Local symbol:TSymbol = context.location.symbol
		Local seen:TMap = New TMap
		If context.analysis.snapshot And context.analysis.snapshot.documents.length Then
			For Local sourceDocument:TSourceDocumentModel = EachIn context.analysis.snapshot.documents
				If Not sourceDocument Or Not sourceDocument.tree Then Continue
				AppendDocument(result, seen, context.analysis.model, symbol, sourceDocument.tree, sourceDocument.path, workspace, includeDeclaration)
			Next
		Else
			AppendDocument(result, seen, context.analysis.model, symbol, context.analysis.syntaxTree, document.path, workspace, includeDeclaration)
		End If
		Return result
	End Function

	Function AppendDocument(target:TJSONArray, seen:TMap, model:TSemanticModel, symbol:TSymbol, tree:TSyntaxTree, path:String, workspace:TLspWorkspaceContext, includeDeclaration:Int)
		If Not tree Or Not tree.source Then Return
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(tree)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local matches:Int = ReferencesSymbol(model, node, symbol)
			If includeDeclaration And model.DeclaredSymbol(node) = symbol Then matches = True
			If Not matches Then Continue
			Local span:TSourceSpan = TBlitzMaxLspNavigation.ReferenceSpan(node)
			If Not span Then Continue
			Local key:String = SnapshotPathKey(path) + "|" + span.start + ":" + span.length
			If seen.Contains(key) Then Continue
			seen.Insert(key, span)
			Local location:TJSONObject = JsonObject()
			location.Set("uri", TBlitzMaxLspNavigation.UriForPath(path, workspace.documents))
			location.Set("range", TLspPositions.Range(tree.source, span))
			target.Append(location)
		Next
	End Function

	Function ReferencesSymbol:Int(model:TSemanticModel, node:TSyntaxNode, symbol:TSymbol)
		If model.ReferencedSymbol(node) = symbol Then Return True
		Local typeReference:TTypeReferenceSyntax = TTypeReferenceSyntax(node)
		If typeReference And TBlitzMaxLspNavigation.TypeSymbol(model.TypeOf(typeReference)) = symbol Then Return True
		Return False
	End Function
End Type
