' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

Type TFoldingRangeEntry
	Field startLine:Int
	Field endLine:Int
	Field range:TJSONObject
End Type

Type TFoldingCommentEntry
	Field trivia:TSyntaxTrivia
	Field startLine:Int
	Field endLine:Int
End Type

' Syntax-backed folding for declarations and executable blocks, augmented by
' lexical comment ranges and grouped imports. No indentation assumptions are
' made here; editor indentation rules remain available as a client fallback.
Type TBlitzMaxLspFoldingRanges
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext)
		Local result:TJSONArray = JsonArray()
		If Not document Or Not workspace Then Return result
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.syntaxTree Or Not analysis.syntaxTree.source Then Return result
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not navigator Then navigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		If Not navigator Then Return result

		Local entries:TFoldingRangeEntry[]
		Local seen:TMap = New TMap
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local conditional:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
			If conditional Then
				AppendConditionalRanges(entries, seen, analysis.syntaxTree.source, conditional)
				Continue
			End If
			If IsFoldableNode(node) Then
				AppendRange(entries, seen, analysis.syntaxTree.source, node.span, "")
			End If
		Next
		AppendImportRanges(entries, seen, analysis.syntaxTree)
		AppendCommentRanges(entries, seen, analysis.syntaxTree)
		SortEntries(entries)
		For Local entry:TFoldingRangeEntry = EachIn entries
			result.Append(entry.range)
		Next
		Return result
	End Function

	Function IsFoldableNode:Int(node:TSyntaxNode)
		If Not node Then Return False
		Select node.kind
			Case SYNTAX_ROUTINE_DECLARATION, SYNTAX_FUNCTION_LITERAL_EXPRESSION, SYNTAX_TYPE_DECLARATION, SYNTAX_EXTERN_BLOCK, SYNTAX_ENUM_DECLARATION
				Return True
			Case SYNTAX_IF_STATEMENT, SYNTAX_WHILE_STATEMENT, SYNTAX_REPEAT_STATEMENT, SYNTAX_FOR_STATEMENT
				Return True
			Case SYNTAX_SELECT_STATEMENT, SYNTAX_TRY_STATEMENT, SYNTAX_USING_STATEMENT
				Return True
		End Select
		Return False
	End Function

	Function AppendConditionalRanges(entries:TFoldingRangeEntry[] Var, seen:TMap, source:TSourceText, conditional:TConditionalRegionSyntax)
		If Not conditional Or Not source Then Return
		For Local index:Int = 0 Until conditional.branches.length
			Local branch:TConditionalBranchSyntax = conditional.branches[index]
			If Not branch Or Not branch.directiveToken Then Continue
			Local endOffset:Int = source.Length()
			If index + 1 < conditional.branches.length And conditional.branches[index + 1].directiveToken Then
				endOffset = conditional.branches[index + 1].directiveToken.span.start
			Else If conditional.endDirectiveToken Then
				endOffset = conditional.endDirectiveToken.span.start
			End If
			AppendRange(entries, seen, source, TSourceSpan.Create(branch.directiveToken.span.start, endOffset - branch.directiveToken.span.start), "region")
		Next
	End Function

	Function AppendImportRanges(entries:TFoldingRangeEntry[] Var, seen:TMap, tree:TSyntaxTree)
		If Not tree Or Not tree.root Then Return
		Local first:TSourceSpan
		Local last:TSourceSpan
		Local count:Int
		Local lastLine:Int = -2
		For Local member:TSyntaxNode = EachIn tree.root.members
			Local imported:TImportDirectiveSyntax = TImportDirectiveSyntax(member)
			If imported And imported.span Then
				Local line:Int = tree.source.Position(imported.span.start).line
				If count And line > lastLine + 1 Then
					FlushImports(entries, seen, tree.source, first, last, count)
					first = Null; last = Null; count = 0
				End If
				If Not first Then first = imported.span
				last = imported.span
				count :+ 1
				lastLine = FoldEndLine(tree.source, imported.span)
			Else
				FlushImports(entries, seen, tree.source, first, last, count)
				first = Null; last = Null; count = 0; lastLine = -2
			End If
		Next
		FlushImports(entries, seen, tree.source, first, last, count)
	End Function

	Function FlushImports(entries:TFoldingRangeEntry[] Var, seen:TMap, source:TSourceText, first:TSourceSpan, last:TSourceSpan, count:Int)
		If count < 2 Or Not first Or Not last Then Return
		AppendRange(entries, seen, source, TSourceSpan.Create(first.start, last.EndOffset() - first.start), "imports")
	End Function

	Function AppendCommentRanges(entries:TFoldingRangeEntry[] Var, seen:TMap, tree:TSyntaxTree)
		If Not tree Or Not tree.root Then Return
		Local comments:TFoldingCommentEntry[]
		Local triviaSeen:TMap = New TMap
		For Local token:TSyntaxToken = EachIn tree.root.tokens
			AppendTokenComments(comments, triviaSeen, tree.source, token.leadingTrivia)
			AppendTokenComments(comments, triviaSeen, tree.source, token.trailingTrivia)
		Next
		SortComments(comments)
		Local first:TSyntaxTrivia
		Local last:TSyntaxTrivia
		Local count:Int
		Local lastLine:Int = -2
		For Local comment:TFoldingCommentEntry = EachIn comments
			If comment.trivia.kind = TRIVIA_BLOCK_COMMENT Then
				FlushLineComments(entries, seen, tree.source, first, last, count)
				first = Null; last = Null; count = 0; lastLine = -2
				AppendRange(entries, seen, tree.source, comment.trivia.span, "comment")
				Continue
			End If
			If count And comment.startLine <> lastLine + 1 Then
				FlushLineComments(entries, seen, tree.source, first, last, count)
				first = Null; last = Null; count = 0
			End If
			If Not first Then first = comment.trivia
			last = comment.trivia
			count :+ 1
			lastLine = comment.endLine
		Next
		FlushLineComments(entries, seen, tree.source, first, last, count)
	End Function

	Function AppendTokenComments(comments:TFoldingCommentEntry[] Var, seen:TMap, source:TSourceText, triviaItems:TSyntaxTrivia[])
		For Local trivia:TSyntaxTrivia = EachIn triviaItems
			If Not trivia Or (trivia.kind <> TRIVIA_LINE_COMMENT And trivia.kind <> TRIVIA_BLOCK_COMMENT) Then Continue
			Local key:String = trivia.span.start + ":" + trivia.span.length
			If seen.Contains(key) Then Continue
			seen.Insert(key, trivia)
			Local comment:TFoldingCommentEntry = New TFoldingCommentEntry
			comment.trivia = trivia
			comment.startLine = source.Position(trivia.span.start).line
			comment.endLine = FoldEndLine(source, trivia.span)
			comments :+ [comment]
		Next
	End Function

	Function FlushLineComments(entries:TFoldingRangeEntry[] Var, seen:TMap, source:TSourceText, first:TSyntaxTrivia, last:TSyntaxTrivia, count:Int)
		If count < 2 Or Not first Or Not last Then Return
		AppendRange(entries, seen, source, TSourceSpan.Create(first.span.start, last.span.EndOffset() - first.span.start), "comment")
	End Function

	Function AppendRange(entries:TFoldingRangeEntry[] Var, seen:TMap, source:TSourceText, span:TSourceSpan, kind:String)
		If Not source Or Not span Then Return
		Local startLine:Int = source.Position(span.start).line
		Local endLine:Int = FoldEndLine(source, span)
		If endLine <= startLine Then Return
		Local key:String = startLine + ":" + endLine + ":" + kind
		If seen.Contains(key) Then Return
		seen.Insert(key, key)
		Local range:TJSONObject = JsonObject()
		range.Set("startLine", startLine)
		range.Set("endLine", endLine)
		If kind.length Then range.Set("kind", kind)
		Local entry:TFoldingRangeEntry = New TFoldingRangeEntry
		entry.startLine = startLine
		entry.endLine = endLine
		entry.range = range
		entries :+ [entry]
	End Function

	Function FoldEndLine:Int(source:TSourceText, span:TSourceSpan)
		Local offset:Int = Max(span.start, Min(span.EndOffset(), source.Length()))
		While offset > span.start And (source.text[offset - 1] = 10 Or source.text[offset - 1] = 13)
			offset :- 1
		Wend
		Return source.Position(offset).line
	End Function

	Function SortEntries(entries:TFoldingRangeEntry[] Var)
		For Local index:Int = 1 Until entries.length
			Local value:TFoldingRangeEntry = entries[index]
			Local target:Int = index
			While target > 0 And ComesBefore(value, entries[target - 1])
				entries[target] = entries[target - 1]
				target :- 1
			Wend
			entries[target] = value
		Next
	End Function

	Function ComesBefore:Int(left:TFoldingRangeEntry, right:TFoldingRangeEntry)
		If left.startLine <> right.startLine Then Return left.startLine < right.startLine
		Return left.endLine > right.endLine
	End Function

	Function SortComments(comments:TFoldingCommentEntry[] Var)
		For Local index:Int = 1 Until comments.length
			Local value:TFoldingCommentEntry = comments[index]
			Local target:Int = index
			While target > 0 And value.trivia.span.start < comments[target - 1].trivia.span.start
				comments[target] = comments[target - 1]
				target :- 1
			Wend
			comments[target] = value
		Next
	End Function
End Type
