' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BlitzMax.Language

Rem
bbdoc: Configures parser-aware formatting independently of an editor.
about: A new instance contains the default styles; copy it before applying temporary overrides.
End Rem
Type TBlitzMaxFormatOptions
	Field thenStyle:String = "preserve"
	Field endStyle:String = "preserve"
	Field inlineIfStyle:String = "preserve"
	Field tabSize:Int = 4
	Field insertSpaces:Int
	Field indent:Int = True
	Field spaceAfterComma:Int = True
	Field caseIndent:String = "indented"
	Field metadataBraceSpacing:String = "preserve"
	Field callParenSpacing:String = "preserve"
	Field assignmentSpacing:String = "preserve"
	Field binarySpacing:String = "preserve"
	Field trimTrailingWhitespace:Int = True
	Field declarationBlankLines:String = "preserve"
	Field controlBlankLines:String = "preserve"

	Method Copy:TBlitzMaxFormatOptions()
		Local result:TBlitzMaxFormatOptions = New TBlitzMaxFormatOptions
		result.thenStyle = thenStyle
		result.endStyle = endStyle
		result.inlineIfStyle = inlineIfStyle
		result.tabSize = tabSize
		result.insertSpaces = insertSpaces
		result.indent = indent
		result.spaceAfterComma = spaceAfterComma
		result.caseIndent = caseIndent
		result.metadataBraceSpacing = metadataBraceSpacing
		result.callParenSpacing = callParenSpacing
		result.assignmentSpacing = assignmentSpacing
		result.binarySpacing = binarySpacing
		result.trimTrailingWhitespace = trimTrailingWhitespace
		result.declarationBlankLines = declarationBlankLines
		result.controlBlankLines = controlBlankLines
		Return result
	End Method
End Type

Rem
bbdoc: A replacement using offsets into the original source String.
End Rem
Type TBlitzMaxFormatEdit
	Field start:Int
	Field finish:Int
	Field newText:String

	Function Create:TBlitzMaxFormatEdit(start:Int, finish:Int, newText:String)
		Local result:TBlitzMaxFormatEdit = New TBlitzMaxFormatEdit
		result.start = start
		result.finish = finish
		result.newText = newText
		Return result
	End Function
End Type

Rem
bbdoc: A collection of non-overlapping source edits.
End Rem
Type TBlitzMaxFormatEdits
	Field items:TBlitzMaxFormatEdit[]

	Method Append(edit:TBlitzMaxFormatEdit)
		items :+ [edit]
	End Method

	Method Size:Int()
		Return items.length
	End Method

	Method Get:TBlitzMaxFormatEdit(index:Int)
		Return items[index]
	End Method

	Method Apply:String(text:String)
		Local result:String = text
		Local preceding:Int = text.length + 1
		For Local count:Int = 0 Until items.length
			Local chosen:TBlitzMaxFormatEdit
			For Local edit:TBlitzMaxFormatEdit = EachIn items
				If edit.start >= preceding Or (chosen And edit.start <= chosen.start) Then Continue
				chosen = edit
			Next
			If Not chosen Or chosen.start < 0 Or chosen.finish < chosen.start Or chosen.finish > text.length Or chosen.finish > preceding Then Throw "Overlapping or invalid formatting edits"
			result = result[..chosen.start] + chosen.newText + result[chosen.finish..]
			preceding = chosen.start
		Next
		Return result
	End Method
End Type

' Formatting uses parsed block ownership and token spans. It never infers
' block structure from existing indentation or keyword text in comments.
Rem
bbdoc: Formats BlitzMax source without an LSP document or JSON protocol.
End Rem
Type TBlitzMaxFormatter
	Function FormatText:String(text:String, path:String = "", options:TBlitzMaxFormatOptions = Null)
		Return Query(text, path, options).Apply(text)
	End Function

	Function Query:TBlitzMaxFormatEdits(text:String, path:String = "", options:TBlitzMaxFormatOptions = Null)
		Local edits:TBlitzMaxFormatEdits = New TBlitzMaxFormatEdits
		If Not options Then options = New TBlitzMaxFormatOptions
		Local thenStyle:String = options.thenStyle.ToLower()
		Local endStyle:String = options.endStyle.ToLower()
		Local inlineIfStyle:String = options.inlineIfStyle.ToLower()
		Local tabSize:Int = options.tabSize
		Local insertSpaces:Int = options.insertSpaces
		Local formatIndent:Int = options.indent
		Local spaceAfterComma:Int = options.spaceAfterComma
		Local caseIndent:String = options.caseIndent.ToLower()
		Local metadataBraceSpacing:String = options.metadataBraceSpacing.ToLower()
		Local callParenSpacing:String = options.callParenSpacing.ToLower()
		Local assignmentSpacing:String = options.assignmentSpacing.ToLower()
		Local binarySpacing:String = options.binarySpacing.ToLower()
		Local trimTrailingWhitespace:Int = options.trimTrailingWhitespace
		Local declarationBlankLines:String = options.declarationBlankLines.ToLower()
		Local controlBlankLines:String = options.controlBlankLines.ToLower()
		Local parsed:TParseResult = TBlitzMaxParser.ParseText(text, path)
		If Not parsed Or Not parsed.syntaxTree Or parsed.syntaxTree.diagnostics.length Then Return edits
		Local source:TSourceText = parsed.syntaxTree.source
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(parsed.syntaxTree)
		If Not navigator Then Return edits
		Local spacingEdits:TBlitzMaxFormatEdits = New TBlitzMaxFormatEdits
		If spaceAfterComma Then FormatCommaSpacing(spacingEdits, source, parsed.syntaxTree.root.tokens)
		FormatDelimiterSpacing(spacingEdits, source, parsed.syntaxTree.root.tokens, navigator, metadataBraceSpacing, callParenSpacing)
		FormatOperatorSpacing(spacingEdits, source, parsed.syntaxTree.root.tokens, navigator, assignmentSpacing, binarySpacing)
		Local expandedLines:TMap = New TMap
		Local coveredTrailingLines:TMap = New TMap
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local statement:TIfStatementSyntax = TIfStatementSyntax(node)
			If statement Then
				If statement.singleLine Then
					If inlineIfStyle = "expand" Then ExpandInlineIf(edits, source, navigator, statement, thenStyle, endStyle, tabSize, insertSpaces, formatIndent, caseIndent, spacingEdits, expandedLines)
				Else
					FormatThen(edits, source, statement.condition, statement.thenToken, thenStyle, trimTrailingWhitespace, coveredTrailingLines)
				End If
			End If
			Local elseIfClause:TElseIfClauseSyntax = TElseIfClauseSyntax(node)
			If elseIfClause Then FormatThen(edits, source, elseIfClause.condition, elseIfClause.thenToken, thenStyle, trimTrailingWhitespace, coveredTrailingLines)
			Local terminator:TBlockTerminatorSyntax = TBlockTerminatorSyntax(node)
			If terminator Then FormatEnd(edits, source, terminator, endStyle)
		Next
		If declarationBlankLines <> "preserve" Or controlBlankLines <> "preserve" Then FormatBlankLines(edits, source, navigator, declarationBlankLines, controlBlankLines, coveredTrailingLines)
		If formatIndent Then FormatIndentation(edits, source, parsed.syntaxTree.root.tokens, navigator, tabSize, insertSpaces, caseIndent, expandedLines)
		If formatIndent Then FormatCommentIndentation(edits, source, parsed.syntaxTree.root.tokens, navigator, tabSize, insertSpaces, caseIndent, expandedLines)
		If trimTrailingWhitespace Then FormatTrailingWhitespace(edits, source, parsed.syntaxTree.root.tokens, expandedLines, coveredTrailingLines)
		For Local index:Int = 0 Until spacingEdits.Size()
				Local edit:TBlitzMaxFormatEdit = spacingEdits.Get(index)
				If Not expandedLines.Contains(String(source.Position(edit.start).line)) Then edits.Append(edit)
		Next
		Return ProtectMultilineStrings(edits, source, parsed.syntaxTree.root.tokens)
	End Function

	Function FormatBlankLines(edits:TBlitzMaxFormatEdits, source:TSourceText, navigator:TSyntaxNavigator, declarationStyle:String, controlStyle:String, coveredTrailingLines:TMap)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local siblings:TSyntaxNode[]
			Local unit:TCompilationUnitSyntax = TCompilationUnitSyntax(node)
			If unit Then siblings = unit.members
			Local block:TBlockSyntax = TBlockSyntax(node)
			If block Then siblings = block.statements
			If siblings.length < 2 Then Continue
			For Local index:Int = 0 Until siblings.length - 1
				Local current:TSyntaxNode = siblings[index]
				Local following:TSyntaxNode = siblings[index + 1]
				If Not current Or Not following Or Not current.span Or Not following.span Then Continue
				Local style:String
				If TRoutineDeclarationSyntax(current) Or TTypeDeclarationSyntax(current) Or TEnumDeclarationSyntax(current) Or TExternBlockSyntax(current) Then
					style = declarationStyle
				Else If TIfStatementSyntax(current) Or TForStatementSyntax(current) Or TWhileStatementSyntax(current) Or TRepeatStatementSyntax(current) Or TSelectStatementSyntax(current) Or TTryStatementSyntax(current) Or TUsingStatementSyntax(current) Then
					style = controlStyle
				End If
				If style <> "one" And style <> "none" Then Continue
				Local finish:Int = current.span.EndOffset()
				Local start:Int = following.span.start
				If finish >= start Then Continue
				Local closeLine:Int = source.Position(Max(0, finish - 1)).line
				Local nextLine:Int = source.Position(start).line
				If nextLine <= closeLine Then Continue
				Local lineEnd:Int = source.Offset(closeLine, 2147483647)
				Local nextLineStart:Int = source.Offset(nextLine, 0)
				If finish > lineEnd Or nextLineStart < lineEnd Then Continue
				' Leave comments, directives and other content between siblings in place.
				Local onlyWhitespace:Int = True
				For Local offset:Int = lineEnd Until nextLineStart
					Local character:Int = source.text[offset]
					If character <> 32 And character <> 9 And character <> 10 And character <> 13 Then onlyWhitespace = False; Exit
				Next
				If Not onlyWhitespace Then Continue
				Local newline:String = "~n"
				If lineEnd < source.text.length And source.text[lineEnd] = 13 Then newline = "~r~n"
				Local desired:String = newline
				If style = "one" Then desired :+ newline
				If source.text[lineEnd..nextLineStart] = desired Then Continue
				AppendEdit(edits, source, lineEnd, nextLineStart, desired)
				For Local line:Int = closeLine + 1 Until nextLine
					coveredTrailingLines.Insert(String(line), String(line))
				Next
			Next
		Next
	End Function

	Function FormatOperatorSpacing(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[], navigator:TSyntaxNavigator, assignmentStyle:String, binaryStyle:String)
		If (assignmentStyle <> "spaced" And assignmentStyle <> "compact") And (binaryStyle <> "spaced" And binaryStyle <> "compact") Then Return
		Local tokenIndexes:TMap = New TMap
		For Local index:Int = 0 Until tokens.length
			tokenIndexes.Insert(String(tokens[index].span.start), String(index))
		Next
		Local seen:TMap = New TMap
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local operatorToken:TSyntaxToken
			Local style:String
			Local assignment:TAssignmentStatementSyntax = TAssignmentStatementSyntax(node)
			If assignment Then operatorToken = assignment.operatorToken; style = assignmentStyle
			Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(node)
			If declarator Then operatorToken = declarator.assignmentToken; style = assignmentStyle
			Local parameter:TParameterSyntax = TParameterSyntax(node)
			If parameter Then operatorToken = parameter.assignmentToken; style = assignmentStyle
			Local enumValue:TEnumValueSyntax = TEnumValueSyntax(node)
			If enumValue Then operatorToken = enumValue.assignmentToken; style = assignmentStyle
			Local forHeader:TForHeaderSyntax = TForHeaderSyntax(node)
			If forHeader Then operatorToken = forHeader.assignmentToken; style = assignmentStyle
			Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(node)
			If binary Then operatorToken = binary.operatorToken; style = binaryStyle
			If Not operatorToken Or (style <> "spaced" And style <> "compact") Then Continue
			Local key:String = String(operatorToken.span.start)
			If seen.Contains(key) Or Not tokenIndexes.Contains(key) Then Continue
			seen.Insert(key, key)
			Local index:Int = Int(String(tokenIndexes.ValueForKey(key)))
			If index = 0 Or index >= tokens.length - 1 Then Continue
			Local previous:TSyntaxToken = tokens[index - 1]
			Local following:TSyntaxToken = tokens[index + 1]
			If previous.kind = TOKEN_NEWLINE Or following.kind = TOKEN_NEWLINE Then Continue
			If following.text = ".." Or following.text = "_" Then Continue
			Local line:Int = source.Position(operatorToken.span.start).line
			If source.Position(previous.span.start).line <> line Or source.Position(following.span.start).line <> line Then Continue
			Local replacement:String = " "
			If style = "compact" And CanCompactOperator(previous, operatorToken, following) Then replacement = ""
			FormatHorizontalGap(edits, source, previous, operatorToken, replacement)
			FormatHorizontalGap(edits, source, operatorToken, following, replacement)
		Next
	End Function

	Function CanCompactOperator:Int(previous:TSyntaxToken, operatorToken:TSyntaxToken, following:TSyntaxToken)
		If previous.kind = TOKEN_MULTILINE_STRING_LITERAL Or following.kind = TOKEN_MULTILINE_STRING_LITERAL Then Return False
		Local lexed:TSyntaxToken[] = TBlitzMaxLexer.Lex(previous.text + operatorToken.text + following.text).tokens
		If lexed.length <> 4 Then Return False
		If lexed[0].kind <> previous.kind Or lexed[0].text <> previous.text Then Return False
		If lexed[1].kind <> operatorToken.kind Or lexed[1].text <> operatorToken.text Then Return False
		If lexed[2].kind <> following.kind Or lexed[2].text <> following.text Then Return False
		Return lexed[3].kind = TOKEN_EOF
	End Function

	Function FormatCommaSpacing(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[])
		For Local index:Int = 0 Until tokens.length - 1
			Local comma:TSyntaxToken = tokens[index]
			If comma.kind <> TOKEN_SYMBOL Or comma.text <> "," Then Continue
			Local start:Int
			Local finish:Int
			If CommaSpacingRange(source, tokens, index, start, finish) Then AppendEdit(edits, source, start, finish, " ")
		Next
	End Function

	Function CommaSpacingRange:Int(source:TSourceText, tokens:TSyntaxToken[], index:Int, start:Int Var, finish:Int Var)
		Local comma:TSyntaxToken = tokens[index]
		If comma.kind <> TOKEN_SYMBOL Or comma.text <> "," Then Return False
		Local nextToken:TSyntaxToken = tokens[index + 1]
		If nextToken.kind = TOKEN_EOF Or nextToken.kind = TOKEN_NEWLINE Then Return False
		If nextToken.text = ")" Or nextToken.text = "]" Or nextToken.text = "}" Or nextToken.text = ";" Then Return False
		If source.Position(comma.span.start).line <> source.Position(nextToken.span.start).line Then Return False
		start = comma.span.EndOffset()
		finish = nextToken.span.start
		Local gap:String = source.text[start..finish]
		For Local character:Int = 0 Until gap.length
			If gap[character] <> 32 And gap[character] <> 9 Then Return False
		Next
		Return gap <> " "
	End Function

	Function FormatDelimiterSpacing(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[], navigator:TSyntaxNavigator, braceStyle:String, callStyle:String)
		Local tokenIndexes:TMap = New TMap
		Local braceStack:Int[]
		For Local index:Int = 0 Until tokens.length
			Local token:TSyntaxToken = tokens[index]
			tokenIndexes.Insert(String(token.span.start), String(index))
			If token.text = "{" Then
				braceStack :+ [index]
			Else If token.text = "}" And braceStack.length Then
				Local openIndex:Int = braceStack[braceStack.length - 1]
				braceStack = braceStack[..braceStack.length - 1]
				FormatDelimiterPair(edits, source, tokens, openIndex, index, braceStyle)
			End If
		Next
		Local seen:TMap = New TMap
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local openToken:TSyntaxToken
			Local closeToken:TSyntaxToken
			Local call:TCallExpressionSyntax = TCallExpressionSyntax(node)
			If call Then openToken = call.openToken; closeToken = call.closeToken
			Local constructor:TNewExpressionSyntax = TNewExpressionSyntax(node)
			If constructor Then openToken = constructor.openParenToken; closeToken = constructor.closeParenToken
			If Not openToken Or Not closeToken Then Continue
			Local key:String = String(openToken.span.start)
			If seen.Contains(key) Or Not tokenIndexes.Contains(key) Or Not tokenIndexes.Contains(String(closeToken.span.start)) Then Continue
			seen.Insert(key, key)
			FormatDelimiterPair(edits, source, tokens, Int(String(tokenIndexes.ValueForKey(key))), Int(String(tokenIndexes.ValueForKey(String(closeToken.span.start)))), callStyle)
		Next
	End Function

	Function FormatDelimiterPair(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[], openIndex:Int, closeIndex:Int, style:String)
		If style <> "spaced" And style <> "compact" Then Return
		If closeIndex <= openIndex + 1 Then Return
		If source.Position(tokens[openIndex].span.start).line <> source.Position(tokens[closeIndex].span.start).line Then Return
		Local replacement:String
		If style = "spaced" Then replacement = " "
		FormatHorizontalGap(edits, source, tokens[openIndex], tokens[openIndex + 1], replacement)
		FormatHorizontalGap(edits, source, tokens[closeIndex - 1], tokens[closeIndex], replacement)
	End Function

	Function FormatHorizontalGap(edits:TBlitzMaxFormatEdits, source:TSourceText, left:TSyntaxToken, right:TSyntaxToken, replacement:String)
		Local start:Int = left.span.EndOffset()
		Local finish:Int = right.span.start
		If source.Position(start).line <> source.Position(finish).line Then Return
		Local gap:String = source.text[start..finish]
		For Local character:Int = 0 Until gap.length
			If gap[character] <> 32 And gap[character] <> 9 Then Return
		Next
		If gap <> replacement Then AppendEdit(edits, source, start, finish, replacement)
	End Function

	Function TextWithEdits:String(source:TSourceText, start:Int, finish:Int, edits:TBlitzMaxFormatEdits)
		Local result:String = source.text[start..finish]
		Local preceding:Int = finish + 1
		For Local count:Int = 0 Until edits.Size()
			Local chosen:TBlitzMaxFormatEdit
			Local chosenStart:Int = -1
			Local chosenEnd:Int
			For Local index:Int = 0 Until edits.Size()
				Local edit:TBlitzMaxFormatEdit = edits.Get(index)
				Local editStart:Int = edit.start
				Local editEnd:Int = edit.finish
				If editStart < start Or editEnd > finish Or editStart >= preceding Or editStart <= chosenStart Then Continue
				chosen = edit
				chosenStart = editStart
				chosenEnd = editEnd
			Next
			If Not chosen Then Exit
			result = result[..chosenStart - start] + chosen.newText + result[chosenEnd - start..]
			preceding = chosenStart
		Next
		Return result
	End Function

	' The whitespace before a triple-quoted string's closing delimiter is part
	' of its value. Leave every physical line occupied by one untouched, even
	' when another formatting rule proposes an edit on that line.
	Function ProtectMultilineStrings:TBlitzMaxFormatEdits(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[])
		Local safeEdits:TBlitzMaxFormatEdits = New TBlitzMaxFormatEdits
		For Local index:Int = 0 Until edits.Size()
			Local edit:TBlitzMaxFormatEdit = edits.Get(index)
			Local editStart:Int = edit.start
			Local editEnd:Int = edit.finish
			Local startLine:Int = source.Position(editStart).line
			Local endLine:Int = source.Position(Max(editStart, editEnd - 1)).line
			Local touchesString:Int
			For Local token:TSyntaxToken = EachIn tokens
				If token.kind <> TOKEN_MULTILINE_STRING_LITERAL Then Continue
				Local tokenStartLine:Int = source.Position(token.span.start).line
				Local tokenEndLine:Int = source.Position(Max(token.span.start, token.span.EndOffset() - 1)).line
				If startLine <= tokenEndLine And endLine >= tokenStartLine Then
					touchesString = True
					Exit
				End If
			Next
			If Not touchesString Then safeEdits.Append(edit)
		Next
		Return safeEdits
	End Function

	Function FormatTrailingWhitespace(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[], expandedLines:TMap, coveredTrailingLines:TMap)
		Local protectedLines:TMap = New TMap
		For Local token:TSyntaxToken = EachIn tokens
			If token.kind = TOKEN_MULTILINE_STRING_LITERAL Or token.kind = TOKEN_NATIVE_LINE Or token.kind = TOKEN_PRAGMA Or token.kind = TOKEN_DIRECTIVE Then MarkSpanLines(protectedLines, source, token.span)
			If token.leadingTrivia Then
				For Local trivia:TSyntaxTrivia = EachIn token.leadingTrivia
					If trivia.kind = TRIVIA_BLOCK_COMMENT Then MarkSpanLines(protectedLines, source, trivia.span)
				Next
			End If
			If token.trailingTrivia Then
				For Local trivia:TSyntaxTrivia = EachIn token.trailingTrivia
					If trivia.kind = TRIVIA_BLOCK_COMMENT Then MarkSpanLines(protectedLines, source, trivia.span)
				Next
			End If
		Next
		For Local line:Int = 0 Until source.LineCount()
			Local key:String = String(line)
			If protectedLines.Contains(key) Or expandedLines.Contains(key) Or coveredTrailingLines.Contains(key) Then Continue
			Local lineStart:Int = source.Offset(line, 0)
			Local lineEnd:Int = source.Offset(line, 2147483647)
			Local start:Int = lineEnd
			While start > lineStart And (source.text[start - 1] = 32 Or source.text[start - 1] = 9)
				start :- 1
			Wend
			If start < lineEnd Then AppendEdit(edits, source, start, lineEnd, "")
		Next
	End Function

	Function MarkSpanLines(lines:TMap, source:TSourceText, span:TSourceSpan)
		If Not span Then Return
		Local startLine:Int = source.Position(span.start).line
		Local endLine:Int = source.Position(Max(span.start, span.EndOffset() - 1)).line
		For Local line:Int = startLine To endLine
			lines.Insert(String(line), String(line))
		Next
	End Function

	Function ExpandInlineIf(edits:TBlitzMaxFormatEdits, source:TSourceText, navigator:TSyntaxNavigator, statement:TIfStatementSyntax, thenStyle:String, endStyle:String, tabSize:Int, insertSpaces:Int, formatIndent:Int, caseIndent:String, spacingEdits:TBlitzMaxFormatEdits, expandedLines:TMap)
		If Not statement.ifToken Or Not statement.thenToken Or Not statement.thenBlock Or statement.elseClause Then Return
		If statement.thenBlock.statements.length <> 1 Then Return
		Local bodyStatement:TSyntaxNode = statement.thenBlock.statements[0]
		If Not TCallStatementSyntax(bodyStatement) And Not TAssignmentStatementSyntax(bodyStatement) And Not TReturnStatementSyntax(bodyStatement) And Not TThrowStatementSyntax(bodyStatement) And Not TExitStatementSyntax(bodyStatement) And Not TContinueStatementSyntax(bodyStatement) Then Return
		Local body:TSourceSpan = bodyStatement.span
		If Not body Then Return
		Local line:Int = source.Position(statement.ifToken.span.start).line
		Local lineStart:Int = source.Offset(line, 0)
		Local lineEnd:Int = source.Offset(line, 2147483647)
		If source.Position(body.EndOffset()).line <> line Then Return
		If source.text[lineStart..statement.ifToken.span.start].Trim().length Then Return
		If source.text[body.EndOffset()..lineEnd].Trim().length Then Return
		If source.text[statement.thenToken.span.EndOffset()..body.start].Trim().length Then Return
		Local indent:String = source.text[lineStart..statement.ifToken.span.start]
		If formatIndent Then indent = IndentText(IndentationDepth(navigator, statement, caseIndent), tabSize, insertSpaces)
		Local stepIndent:String = IndentText(1, tabSize, insertSpaces)
		Local newline:String = "~n"
		If lineEnd < source.text.length And source.text[lineEnd] = 13 Then newline = "~r~n"
		Local headerEnd:Int = statement.thenToken.span.EndOffset()
		If thenStyle = "remove" Then headerEnd = statement.thenToken.span.start
		Local header:String = TextWithEdits(source, statement.ifToken.span.start, headerEnd, spacingEdits).Trim()
		Local ending:String = "End If"
		If endStyle = "combined" Then ending = "EndIf"
		Local bodyText:String = TextWithEdits(source, body.start, body.EndOffset(), spacingEdits).Trim()
		Local expanded:String = indent + header + newline + indent + stepIndent + bodyText + newline + indent + ending
		AppendEdit(edits, source, lineStart, lineEnd, expanded)
		expandedLines.Insert(String(line), String(line))
	End Function

	Function FormatIndentation(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[], navigator:TSyntaxNavigator, tabSize:Int, insertSpaces:Int, caseIndent:String, expandedLines:TMap)
		Local anchors:TMap = New TMap
		For Local node:TSyntaxNode = EachIn navigator.nodes
			If node.span And IsIndentationAnchor(node, navigator.Parent(node)) Then anchors.Insert(String(node.span.start), node)
		Next
		Local previousLine:Int = -1
		For Local token:TSyntaxToken = EachIn tokens
			If token.kind = TOKEN_EOF Or token.kind = TOKEN_NEWLINE Then Continue
			Local line:Int = source.Position(token.span.start).line
			If line = previousLine Then Continue
			previousLine = line
			If expandedLines.Contains(String(line)) Then Continue
			If token.kind = TOKEN_DIRECTIVE Or token.kind = TOKEN_NATIVE_LINE Or token.kind = TOKEN_PRAGMA Or token.kind = TOKEN_MULTILINE_STRING_LITERAL Then Continue
			Local lineStart:Int = source.Offset(line, 0)
			If token.span.start < lineStart Then Continue
			Local original:String = source.text[lineStart..token.span.start]
			For Local index:Int = 0 Until original.length
				If original[index] <> 32 And original[index] <> 9 Then original = ""; Exit
			Next
			If token.span.start > lineStart And Not original.length Then Continue
			Local anchor:TSyntaxNode = TSyntaxNode(anchors.ValueForKey(String(token.span.start)))
			If Not anchor Then Continue
			Local desired:String = IndentText(IndentationDepth(navigator, anchor, caseIndent), tabSize, insertSpaces)
			If original <> desired Then AppendEdit(edits, source, lineStart, token.span.start, desired)
		Next
	End Function

	Function FormatCommentIndentation(edits:TBlitzMaxFormatEdits, source:TSourceText, tokens:TSyntaxToken[], navigator:TSyntaxNavigator, tabSize:Int, insertSpaces:Int, caseIndent:String, expandedLines:TMap)
		Local anchors:TMap = New TMap
		For Local node:TSyntaxNode = EachIn navigator.nodes
			If node.span And IsIndentationAnchor(node, navigator.Parent(node)) Then anchors.Insert(String(node.span.start), node)
		Next
		Local orderedAnchors:TSyntaxNode[]
		For Local token:TSyntaxToken = EachIn tokens
			Local anchor:TSyntaxNode = TSyntaxNode(anchors.ValueForKey(String(token.span.start)))
			If anchor Then orderedAnchors :+ [anchor]
		Next
		Local nextAnchorIndex:Int
		For Local token:TSyntaxToken = EachIn tokens
			If Not token.leadingTrivia Then Continue
			For Local trivia:TSyntaxTrivia = EachIn token.leadingTrivia
				If trivia.kind <> TRIVIA_LINE_COMMENT And trivia.kind <> TRIVIA_BLOCK_COMMENT Then Continue
				Local firstLine:Int = source.Position(trivia.span.start).line
				Local firstStart:Int = source.Offset(firstLine, 0)
				Local originalIndent:String = source.text[firstStart..trivia.span.start]
				If originalIndent.Trim().length Then Continue
				While nextAnchorIndex < orderedAnchors.length And orderedAnchors[nextAnchorIndex].span.start < trivia.span.EndOffset()
					nextAnchorIndex :+ 1
				Wend
				If nextAnchorIndex = orderedAnchors.length Then Continue
				Local following:TSyntaxNode = orderedAnchors[nextAnchorIndex]
				Local depth:Int = IndentationDepth(navigator, following, caseIndent)
				If TBlockTerminatorSyntax(following) Then depth :+ 1
				Local desiredIndent:String = IndentText(depth, tabSize, insertSpaces)
				Local lastLine:Int = firstLine
				If trivia.kind = TRIVIA_BLOCK_COMMENT Then lastLine = source.Position(Max(trivia.span.start, trivia.span.EndOffset() - 1)).line
				For Local line:Int = firstLine To lastLine
					If expandedLines.Contains(String(line)) Then Continue
					Local lineStart:Int = source.Offset(line, 0)
					Local lineEnd:Int = source.Offset(line, 2147483647)
					Local contentStart:Int = lineStart
					While contentStart < lineEnd And (source.text[contentStart] = 32 Or source.text[contentStart] = 9)
						contentStart :+ 1
					Wend
					If contentStart = lineEnd Then Continue
					Local indent:String = source.text[lineStart..contentStart]
					If Not indent.StartsWith(originalIndent) Then Continue
					Local replacement:String = desiredIndent + indent[originalIndent.length..]
					If replacement <> indent Then AppendEdit(edits, source, lineStart, contentStart, replacement)
				Next
			Next
		Next
	End Function

	Function IndentationDepth:Int(navigator:TSyntaxNavigator, node:TSyntaxNode, caseIndent:String)
		Local depth:Int
		Local caseDepth:Int
		For Local ancestor:TSyntaxNode = EachIn navigator.Ancestors(node)
			If TBlockSyntax(ancestor) Then depth :+ 1
			If TCaseClauseSyntax(ancestor) Or TDefaultClauseSyntax(ancestor) Then caseDepth :+ 1
		Next
		If caseIndent <> "aligned" Then depth :+ caseDepth
		Return depth
	End Function

	Function IndentText:String(depth:Int, tabSize:Int, insertSpaces:Int)
		Local unit:String = "~t"
		If insertSpaces Then
			unit = ""
			For Local index:Int = 0 Until Max(1, Min(tabSize, 16)); unit :+ " "; Next
		End If
		Local result:String
		For Local index:Int = 0 Until depth; result :+ unit; Next
		Return result
	End Function

	Function IsIndentationAnchor:Int(node:TSyntaxNode, parent:TSyntaxNode)
		If TBlockSyntax(parent) Or TCompilationUnitSyntax(parent) Then Return True
		If TBlockTerminatorSyntax(node) Or TElseIfClauseSyntax(node) Or TElseClauseSyntax(node) Or TCaseClauseSyntax(node) Or TDefaultClauseSyntax(node) Or TCatchClauseSyntax(node) Or TFinallyClauseSyntax(node) Then Return True
		Return False
	End Function

	Function FormatThen(edits:TBlitzMaxFormatEdits, source:TSourceText, condition:TExpressionSyntax, thenToken:TSyntaxToken, style:String, trimTrailingWhitespace:Int, coveredTrailingLines:TMap)
		If Not condition Or Not condition.span Then Return
		If style = "add" And Not thenToken Then
			Local finish:Int = condition.span.EndOffset()
			Local line:Int = source.Position(finish).line
			Local lineEnd:Int = source.Offset(line, 2147483647)
			' Only add Then when the rest of the physical header is whitespace or
			' a comment. An unrecognised trailing token is left untouched.
			Local tail:String = source.text[finish..lineEnd].Trim()
			If tail.length And Not tail.StartsWith("'") Then Return
			If trimTrailingWhitespace And Not tail.length And lineEnd > finish Then
				AppendEdit(edits, source, finish, lineEnd, " Then")
				coveredTrailingLines.Insert(String(line), String(line))
			Else
				AppendEdit(edits, source, finish, finish, " Then")
			End If
		Else If style = "remove" And thenToken Then
			Local start:Int = thenToken.span.start
			While start > condition.span.EndOffset() And (source.text[start - 1] = 32 Or source.text[start - 1] = 9)
				start :- 1
			Wend
			AppendEdit(edits, source, start, thenToken.span.EndOffset(), "")
		End If
	End Function

	Function FormatEnd(edits:TBlitzMaxFormatEdits, source:TSourceText, terminator:TBlockTerminatorSyntax, style:String)
		If Not terminator.endToken Or Not terminator.endToken.span Then Return
		If style = "combined" And terminator.blockToken Then
			Local start:Int = terminator.endToken.span.EndOffset()
			Local finish:Int = terminator.blockToken.span.start
			' Comments and newlines between End and the block name are significant.
			For Local index:Int = start Until finish
				If source.text[index] <> 32 And source.text[index] <> 9 Then Return
		Next
			AppendEdit(edits, source, start, finish, "")
		Else If style = "spaced" And Not terminator.blockToken Then
			Local original:String = terminator.endToken.text
			If original.ToLower().StartsWith("end") And original.length > 3 Then
				AppendEdit(edits, source, terminator.endToken.span.start + 3, terminator.endToken.span.start + 3, " ")
			End If
		End If
	End Function

	Function AppendEdit(edits:TBlitzMaxFormatEdits, source:TSourceText, start:Int, finish:Int, replacement:String)
		edits.Append(TBlitzMaxFormatEdit.Create(start, finish, replacement))
	End Function
End Type
