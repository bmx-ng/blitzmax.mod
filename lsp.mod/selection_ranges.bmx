' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

' LSP smart selection. Each requested position receives an innermost range
' whose parent chain follows the immutable syntax tree out to the document.
Type TBlitzMaxLspSelectionRanges
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, positions:TJSONArray)
		Local result:TJSONArray = JsonArray()
		If Not document Or Not workspace Or Not positions Then Return result
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.syntaxTree Or Not analysis.syntaxTree.source Then Return result
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not navigator Then navigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		If Not navigator Then Return result

		For Local index:Int = 0 Until positions.Size()
			Local position:TJSONObject = TJSONObject(positions.Get(index))
			Local offset:Int
			If position Then offset = TLspPositions.Offset(analysis.syntaxTree.source, Int(position.GetInteger("line")), Int(position.GetInteger("character")))
			result.Append(SelectionAt(analysis.syntaxTree.source, navigator, offset))
		Next
		Return result
	End Function

	Function SelectionAt:TJSONObject(source:TSourceText, navigator:TSyntaxNavigator, offset:Int)
		Local spans:TSourceSpan[]
		Local token:TSyntaxToken = navigator.TokenAt(offset)
		If token And token.span And token.span.length Then AppendSpan(spans, token.span)
		Local node:TSyntaxNode = navigator.NodeAt(offset)
		For Local ancestor:TSyntaxNode = EachIn navigator.Ancestors(node)
			If ancestor And ancestor.span And ancestor.span.length Then AppendSpan(spans, ancestor.span)
		Next
		AppendSpan(spans, source.FullSpan())

		Local parent:TJSONObject
		For Local index:Int = spans.length - 1 To 0 Step -1
			Local item:TJSONObject = JsonObject()
			item.Set("range", TLspPositions.Range(source, spans[index]))
			If parent Then item.Set("parent", parent)
			parent = item
		Next
		Return parent
	End Function

	Function AppendSpan(spans:TSourceSpan[] Var, span:TSourceSpan)
		If Not span Then Return
		If spans.length Then
			Local inner:TSourceSpan = spans[spans.length - 1]
			If inner.start = span.start And inner.length = span.length Then Return
			If span.start > inner.start Or span.EndOffset() < inner.EndOffset() Then Return
		End If
		spans :+ [span]
	End Function
End Type
