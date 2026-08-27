' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "conditional_parser.bmx"
Import "expression_parser.bmx"
Import "lexer.bmx"
Import "signature_parser.bmx"
Import "syntax.bmx"
Import "type_declaration_parser.bmx"
Import "type_parser.bmx"

Const BOUNDARY_IF:Int = 1
Const BOUNDARY_WHILE:Int = 2
Const BOUNDARY_REPEAT:Int = 3
Const BOUNDARY_FOR:Int = 4
Const BOUNDARY_SELECT:Int = 5
Const BOUNDARY_TRY:Int = 6
Const BOUNDARY_USING:Int = 7
Const BOUNDARY_CONDITIONAL:Int = 8
Const BOUNDARY_CONDITIONAL_SELECT_CLAUSE:Int = 9
Const BOUNDARY_EXTERN:Int = 10

Type TSyntaxParseResult
	Field root:TCompilationUnitSyntax
	Field diagnostics:TDiagnostic[]
End Type

Type TParsedBlock
	Field block:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TParsedCaseHeader
	Field values:TExpressionSyntax[]
	Field inlineTokens:TSyntaxToken[]
End Type

Type TConditionalForHeaderGroup
	Field headers:TList = New TList
End Type

Type TConditionalIfHeaderGroup
	Field headers:TList = New TList
End Type

Type TBlitzMaxSyntaxParser
	Field tokens:TSyntaxToken[]
	Field position:Int
	Field diagnostics:TList = New TList
	Field interfaceDepth:Int
	Field typeDepth:Int
	Field externDepth:Int
	Field conditionalDepth:Int
	Field conditionalExternHeaderSeen:Int
	Field conditionalRoutineHeaders:TList
	Field conditionalForHeaderGroups:TList
	Field conditionalForHeaderIndex:Int
	Field conditionalOpenForBoundary:Int
	Field conditionalIfHeaderGroups:TList
	Field conditionalIfHeaderIndex:Int
	Field conditionalOpenIfBoundary:Int
	Field activeBoundary:Int
	Field closedBoundary:Int
	Field pendingMembers:TList = New TList
	Field sharedConditionalEndToken:TSyntaxToken
	Field sharedConditionalEndDepth:Int
	Field sourceMode:Int = SOURCE_MODE_STRICT
	Field sourceModeDeclaration:TSourceModeSyntax

	Function Parse:TSyntaxParseResult(lexResult:TLexResult)
		Local parser:TBlitzMaxSyntaxParser = New TBlitzMaxSyntaxParser
		parser.tokens = lexResult.tokens
		Return parser.ParseCompilationUnit()
	End Function

	Method ParseCompilationUnit:TSyntaxParseResult()
		Local members:TList = New TList
		SkipSeparators()

		While Current().kind <> TOKEN_EOF
			If TextEquals(Current().text, "strict") Or TextEquals(Current().text, "superstrict") Then
				members.AddLast(ParseSourceModeDeclaration())
			Else
				members.AddLast(ParseMember())
			End If
			SkipSeparators()
		Wend

		Local root:TCompilationUnitSyntax = New TCompilationUnitSyntax
		root.kind = SYNTAX_COMPILATION_UNIT
		root.tokens = tokens
		root.members = NodesToArray(members)
		root.endOfFileToken = Current()
		root.sourceMode = sourceMode
		root.sourceModeDeclaration = sourceModeDeclaration
		root.span = TSourceSpan.Create(0, Current().span.EndOffset())

		Local result:TSyntaxParseResult = New TSyntaxParseResult
		result.root = root
		result.diagnostics = DiagnosticsToArray(diagnostics)
		Return result
	End Method

	Method ParseSourceModeDeclaration:TSourceModeSyntax()
		Local values:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		Local node:TSourceModeSyntax = New TSourceModeSyntax
		node.kind = SYNTAX_SOURCE_MODE
		node.modeToken = values[0]
		node.sourceMode = SOURCE_MODE_STRICT
		If TextEquals(node.modeToken.text, "superstrict") Then node.sourceMode = SOURCE_MODE_SUPERSTRICT
		node.span = SpanOfTokens(values)
		If values.length > 1 Then AddDiagnostic("BMX2325", "Unexpected token '" + values[1].text + "' after '" + node.modeToken.text + "'.", values[1].span)
		sourceMode = node.sourceMode
		sourceModeDeclaration = node
		Return node
	End Method

	Method ParseMember:TSyntaxNode()
		If externDepth > 0 And IsBlockTerminator() And (TextEquals(Current().text, "endextern") Or TextEquals(Peek(1).text, "extern")) Then
			externDepth :- 1
			Return ParseBlockTerminator("extern")
		End If
		If Current().kind = TOKEN_DIRECTIVE Then Return ParseConditionalRegion()
		If Current().text = "#" Then Return ParseLoopLabelledStatement()
		If Current().kind = TOKEN_KEYWORD Then
			Local text:String = Current().text
			If TextEquals(text, "public") Or TextEquals(text, "private") Or TextEquals(text, "protected") Or TextEquals(text, "internal") Then Return ParseVisibilitySection()
			If TextEquals(text, "function") Or TextEquals(text, "method") Then Return ParseRoutineDeclaration()
			If TextEquals(text, "extern") Then Return ParseExternBlock()
			If TextEquals(text, "type") Or TextEquals(text, "interface") Or TextEquals(text, "struct") Then Return ParseTypeDeclaration()
			If TextEquals(text, "enum") Then Return ParseEnumDeclaration()
			If TextEquals(text, "if") Then Return ParseIfStatement()
			If TextEquals(text, "while") Then Return ParseWhileStatement()
			If TextEquals(text, "repeat") Then Return ParseRepeatStatement()
			If TextEquals(text, "for") Then Return ParseForStatement()
			If TextEquals(text, "select") Then Return ParseSelectStatement()
			If TextEquals(text, "try") Then Return ParseTryStatement()
			If TextEquals(text, "using") Then Return ParseUsingStatement()
		End If
		Return ParseSimpleStatement()
	End Method

	Method ParseExternBlock:TExternBlockSyntax()
		Local node:TExternBlockSyntax = New TExternBlockSyntax
		node.kind = SYNTAX_EXTERN_BLOCK
		node.externToken = Current()
		Local start:Int = Current().span.start
		Advance()
		node.headerTokens = TokensFromList(CollectUntilSeparator())
		If node.headerTokens.length And node.headerTokens[0].kind = TOKEN_STRING_LITERAL Then node.callingConventionToken = node.headerTokens[0]
		SkipSeparators()
		If conditionalDepth > 0 And Current().kind = TOKEN_DIRECTIVE Then
			node.body = EmptyBlockAt(Current().span.start)
			conditionalExternHeaderSeen = True
			node.span = TSourceSpan.Create(start, node.body.span.start - start)
			Return node
		End If
		externDepth :+ 1
		Local previousBoundary:Int = activeBoundary
		activeBoundary = BOUNDARY_EXTERN
		Local parsed:TParsedBlock = ParseBlock("extern")
		activeBoundary = previousBoundary
		externDepth :- 1
		node.body = parsed.block
		node.terminator = parsed.terminator
		Local endOffset:Int = node.body.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseVisibilitySection:TVisibilitySectionSyntax()
		Local node:TVisibilitySectionSyntax = New TVisibilitySectionSyntax
		node.kind = SYNTAX_VISIBILITY_SECTION
		node.visibilityToken = Current()
		node.visibility = VISIBILITY_PUBLIC
		Local isPrivate:Int = TextEquals(Current().text, "private")
		Local isProtected:Int = TextEquals(Current().text, "protected")
		If isPrivate Then
			node.visibility = VISIBILITY_PRIVATE
		Else If isProtected Then
			node.visibility = VISIBILITY_PROTECTED
		Else If TextEquals(Current().text, "internal") Then
			node.visibility = VISIBILITY_INTERNAL
		End If
		Local start:Int = Current().span.start
		Local endOffset:Int = Current().span.EndOffset()
		Advance()
		If (isPrivate Or isProtected) And TextEquals(Current().text, "internal") Then
			node.internalToken = Current()
			endOffset = Current().span.EndOffset()
			If isPrivate Then node.visibility = VISIBILITY_PRIVATE_INTERNAL Else node.visibility = VISIBILITY_PROTECTED_INTERNAL
			Advance()
		End If
		node.span = TSourceSpan.Create(start, endOffset - start)
		Local visibilityText:String = node.visibilityToken.text
		If node.internalToken Then visibilityText :+ " " + node.internalToken.text
		If typeDepth = 0 And node.visibility <> VISIBILITY_PUBLIC And node.visibility <> VISIBILITY_PRIVATE Then
			AddDiagnostic("BMX2326", "'" + visibilityText + "' visibility is only valid inside a type.", node.span)
		End If
		If interfaceDepth > 0 And node.visibility <> VISIBILITY_PUBLIC Then
			AddDiagnostic("BMX2327", "'" + visibilityText + "' visibility cannot be used with interfaces.", node.span)
		End If
		Return node
	End Method

	Method ParseEnumDeclaration:TEnumDeclarationSyntax()
		Local node:TEnumDeclarationSyntax = New TEnumDeclarationSyntax
		node.kind = SYNTAX_ENUM_DECLARATION
		node.enumToken = Current()
		Local start:Int = Current().span.start
		Advance()
		If IsNameToken(Current()) Then
			node.nameToken = Current()
			Advance()
		Else
			AddDiagnostic("BMX2010", "Expected an enum name.", Current().span)
		End If

		Local typeList:TList = New TList
		If TBlitzMaxTypeParser.IsTypeMarker(Current().text) Then
			Local marker:String = Current().text
			typeList.AddLast(Current())
			Advance()
			If marker = ":" And IsNameToken(Current()) Then
				typeList.AddLast(Current())
				Advance()
			Else If marker = ":" Then
				AddDiagnostic("BMX2011", "Expected an enum underlying type after ':'.", Current().span)
			End If
		End If
		node.typeTokens = TokensFromList(typeList)
		node.underlyingType = TBlitzMaxTypeParser.Parse(node.typeTokens)
		If TextEquals(Current().text, "flags") Then
			node.flagsToken = Current()
			Advance()
		End If

		Local values:TList = New TList
		SkipSeparators()
		While Current().kind <> TOKEN_EOF And Not IsEnumTerminator()
			Local value:TEnumValueSyntax = ParseEnumValue()
			values.AddLast(value)
			SkipSeparators()
		Wend
		node.values = EnumValuesToArray(values)
		If IsEnumTerminator() Then
			node.terminator = ParseBlockTerminator("enum")
		Else
			AddDiagnostic("BMX2012", "Expected 'End Enum' before end of file.", Current().span)
		End If
		' During live editing an unfinished Rem immediately after the header can
		' hide every value and the terminator from the lexer. Keep the recovered
		' declaration span large enough to contain every header token we did parse.
		Local endOffset:Int = node.enumToken.span.EndOffset()
		If node.nameToken Then endOffset = Max(endOffset, node.nameToken.span.EndOffset())
		For Local token:TSyntaxToken = EachIn node.typeTokens
			endOffset = Max(endOffset, token.span.EndOffset())
		Next
		If node.flagsToken Then endOffset = Max(endOffset, node.flagsToken.span.EndOffset())
		If node.values.length Then endOffset = node.values[node.values.length - 1].span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseEnumValue:TEnumValueSyntax()
		Local node:TEnumValueSyntax = New TEnumValueSyntax
		node.kind = SYNTAX_ENUM_VALUE
		Local start:Int = Current().span.start
		If IsNameToken(Current()) Then
			node.nameToken = Current()
			Advance()
		Else
			AddDiagnostic("BMX2013", "Expected an enum value name.", Current().span)
			Advance()
			node.span = TSourceSpan.Create(start, Current().span.start - start)
			Return node
		End If

		If Current().text = "=" Then
			node.assignmentToken = Current()
			Advance()
			Local candidates:TSyntaxToken[] = EnumExpressionCandidates()
			If candidates.length Then
				Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(candidates, diagnostics)
				node.value = parsed.expression
				For Local index:Int = 0 Until parsed.consumed
					Advance()
				Next
			Else
				AddDiagnostic("BMX2014", "Expected a constant expression after '='.", node.assignmentToken.span)
			End If
		End If
		If Current().text = "," Then
			node.separatorToken = Current()
			Advance()
		End If
		Local endOffset:Int = node.nameToken.span.EndOffset()
		If node.assignmentToken Then endOffset = node.assignmentToken.span.EndOffset()
		If node.value Then endOffset = node.value.span.EndOffset()
		If node.separatorToken Then endOffset = node.separatorToken.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method EnumExpressionCandidates:TSyntaxToken[]()
		Local result:TList = New TList
		Local index:Int = position
		Local parens:Int
		Local brackets:Int
		While index < tokens.length
			Local token:TSyntaxToken = tokens[index]
			If parens = 0 And brackets = 0 Then
				If token.kind = TOKEN_NEWLINE Or token.text = ";" Or token.text = "," Then Exit
				Local lower:String = token.text.ToLower()
				If lower = "endenum" Or (lower = "end" And index + 1 < tokens.length And tokens[index + 1].text.ToLower() = "enum") Then Exit
			End If
			result.AddLast(token)
			Select token.text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
			index :+ 1
		Wend
		Return TokensFromList(result)
	End Method

	Method IsEnumTerminator:Int()
		Local lower:String = Current().text.ToLower()
		Return lower = "endenum" Or (lower = "end" And Peek(1).text.ToLower() = "enum")
	End Method

	Method ParseLoopLabelledStatement:TSyntaxNode()
		Local values:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		Local label:TLabelSyntax = New TLabelSyntax
		label.kind = SYNTAX_LABEL
		label.hashToken = values[0]
		label.span = SpanOfTokens(values)
		If values.length > 1 And IsNameToken(values[1]) Then
			label.nameToken = values[1]
		Else
			AddDiagnostic("BMX2323", "Expected a loop-label name after '#'.", label.hashToken.span)
		End If
		If values.length > 2 Then AddDiagnostic("BMX2324", "Unexpected token '" + values[2].text + "' after loop label.", values[2].span)
		SkipSeparators()

		Local lower:String = Current().text.ToLower()
		If lower = "for" Then
			Local statement:TForStatementSyntax = ParseForStatement()
			statement.label = label
			statement.span = TSourceSpan.Create(label.span.start, statement.span.EndOffset() - label.span.start)
			Return statement
		Else If lower = "while" Then
			Local statement:TWhileStatementSyntax = ParseWhileStatement()
			statement.label = label
			statement.span = TSourceSpan.Create(label.span.start, statement.span.EndOffset() - label.span.start)
			Return statement
		Else If lower = "repeat" Then
			Local statement:TRepeatStatementSyntax = ParseRepeatStatement()
			statement.label = label
			statement.span = TSourceSpan.Create(label.span.start, statement.span.EndOffset() - label.span.start)
			Return statement
		Else If lower = "defdata" Then
			Local statement:TDefDataStatementSyntax = TDefDataStatementSyntax(ParseSimpleStatement())
			statement.label = label
			statement.span = TSourceSpan.Create(label.span.start, statement.span.EndOffset() - label.span.start)
			Return statement
		End If
		Return label
	End Method

	Method ParseIfStatement:TIfStatementSyntax()
		Local node:TIfStatementSyntax = New TIfStatementSyntax
		node.kind = SYNTAX_IF_STATEMENT
		node.ifToken = Current()
		Local start:Int = Current().span.start
		Advance()
		Local header:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		Local thenIndex:Int = FindToken(header, "then")
		Local conditionEnd:Int = header.length
		Local inlineStart:Int = header.length
		If thenIndex >= 0 Then
			Local prefixBeforeThen:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(header[..thenIndex], diagnostics)
			If prefixBeforeThen.consumed < thenIndex Then
				node.condition = prefixBeforeThen.expression
				conditionEnd = prefixBeforeThen.consumed
				inlineStart = prefixBeforeThen.consumed
			Else
				node.thenToken = header[thenIndex]
				conditionEnd = thenIndex
				inlineStart = thenIndex + 1
			End If
		Else If header.length And TextEquals(header[header.length - 1].text, "end") Then
			conditionEnd = header.length - 1
			inlineStart = conditionEnd
		Else
			Local prefix:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(header, diagnostics)
			node.condition = prefix.expression
			conditionEnd = prefix.consumed
			inlineStart = prefix.consumed
		End If
		If Not node.condition Then node.condition = TBlitzMaxExpressionParser.Parse(header[..conditionEnd], diagnostics)

		If inlineStart < header.length Then
			Local inlineTokens:TSyntaxToken[] = header[inlineStart..]
			If IsChainedMultilineIfHeader(inlineTokens) Then
				node.singleLine = True
				node.elseIfClauses = New TElseIfClauseSyntax[0]
				Local nested:TIfStatementSyntax = CreateChainedMultilineIfStatement(inlineTokens)
				node.thenBlock = BlockWithStatement(nested, node.ifToken.span.EndOffset())
				node.span = TSourceSpan.Create(start, nested.span.EndOffset() - start)
				Return node
			End If
			node.singleLine = True
			node.elseIfClauses = New TElseIfClauseSyntax[0]
			If Current().kind = TOKEN_SYMBOL And Current().text = ";" Then inlineTokens = CollectInlineLineTokens(inlineTokens)
			PopulateInlineBranches(node, inlineTokens)
			Local endOffset:Int = node.thenBlock.span.EndOffset()
			If node.elseClause Then endOffset = node.elseClause.span.EndOffset()
			node.span = TSourceSpan.Create(start, endOffset - start)
			Return node
		End If
		If Current().kind = TOKEN_SYMBOL And Current().text = ";" Then
			Advance()
			node.singleLine = True
			node.elseIfClauses = New TElseIfClauseSyntax[0]
			PopulateInlineBranches(node, CollectInlineLineTokens(New TSyntaxToken[0]))
			Local endOffset:Int = node.thenBlock.span.EndOffset()
			If node.elseClause Then endOffset = node.elseClause.span.EndOffset()
			node.span = TSourceSpan.Create(start, endOffset - start)
			Return node
		End If

		Return PopulateMultilineIfStatement(node)
	End Method

	' Production BlitzMax treats `If a If b` as a compact outer If whose only
	' statement is a multiline inner If. The inner statement owns the following
	' physical lines and the single EndIf. Preserve that ownership instead of
	' requiring one terminator for every condition in the chained header.
	Method IsChainedMultilineIfHeader:Int(values:TSyntaxToken[])
		If Not values.length Or Not TextEquals(values[0].text, "if") Then Return False
		Local scratch:TList = New TList
		Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(values[1..], scratch)
		If parsed.consumed <= 0 Then Return False
		Local nextIndex:Int = parsed.consumed + 1
		If nextIndex < values.length And TextEquals(values[nextIndex].text, "then") Then nextIndex :+ 1
		If nextIndex = values.length Then Return True
		If nextIndex < values.length And TextEquals(values[nextIndex].text, "if") Then Return IsChainedMultilineIfHeader(values[nextIndex..])
		Return False
	End Method

	Method CreateChainedMultilineIfStatement:TIfStatementSyntax(values:TSyntaxToken[])
		Local node:TIfStatementSyntax = New TIfStatementSyntax
		node.kind = SYNTAX_IF_STATEMENT
		node.ifToken = values[0]
		node.elseIfClauses = New TElseIfClauseSyntax[0]
		Local header:TSyntaxToken[] = values[1..]
		Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(header, diagnostics)
		node.condition = parsed.expression
		Local inlineStart:Int = parsed.consumed
		If inlineStart < header.length And TextEquals(header[inlineStart].text, "then") Then
			node.thenToken = header[inlineStart]
			inlineStart :+ 1
		End If
		If inlineStart < header.length Then
			node.singleLine = True
			Local nested:TIfStatementSyntax = CreateChainedMultilineIfStatement(header[inlineStart..])
			node.thenBlock = BlockWithStatement(nested, node.ifToken.span.EndOffset())
			node.span = TSourceSpan.Create(node.ifToken.span.start, nested.span.EndOffset() - node.ifToken.span.start)
			Return node
		End If
		Return PopulateMultilineIfStatement(node)
	End Method

	Method BlockWithStatement:TBlockSyntax(statement:TSyntaxNode, fallback:Int)
		If Not statement Then Return EmptyBlockAt(fallback)
		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = [statement]
		block.span = statement.span
		Return block
	End Method

	Method PopulateMultilineIfStatement:TIfStatementSyntax(node:TIfStatementSyntax)
		Local start:Int = node.ifToken.span.start
		SkipSeparators()
		If conditionalDepth > 0 And IsConditionalIfHeaderBoundary() Then
			node.thenBlock = EmptyBlockAt(Current().span.start)
			node.elseIfClauses = New TElseIfClauseSyntax[0]
			RegisterConditionalIfHeader(node)
			conditionalOpenIfBoundary = True
			Local endOffset:Int = node.condition.span.EndOffset()
			node.span = TSourceSpan.Create(start, endOffset - start)
			Return node
		End If
		node.thenBlock = ParseBoundaryBlock(BOUNDARY_IF)
		Local closingRegion:TConditionalRegionSyntax
		If node.thenBlock.statements.length Then closingRegion = TConditionalRegionSyntax(node.thenBlock.statements[node.thenBlock.statements.length - 1])
		Local conditionalElseToken:TSyntaxToken = ExtractConditionalElseToken(closingRegion)
		If conditionalElseToken Then
			' A compile-time region may conditionally introduce Else while the
			' matching If and EndIf remain outside the region. Model that as an
			' ordinary Else whose body contains the conditionally selected tail;
			' when no branch is active, an empty Else is equivalent to no Else.
			node.thenBlock = BlockWithoutLastStatement(node.thenBlock)
			Local conditionalElse:TElseClauseSyntax = New TElseClauseSyntax
			conditionalElse.kind = SYNTAX_ELSE_CLAUSE
			conditionalElse.elseToken = conditionalElseToken
			conditionalElse.block = BlockWithStatement(closingRegion, conditionalElseToken.span.EndOffset())
			conditionalElse.span = TSourceSpan.Create(conditionalElseToken.span.start, conditionalElse.block.span.EndOffset() - conditionalElseToken.span.start)
			node.elseClause = conditionalElse
		End If
		If closingRegion And closingRegion.sharedControlTerminator Then
			node.terminator = closingRegion.sharedControlTerminator
			closedBoundary = 0
			If closingRegion.trailingRegion Then pendingMembers.AddLast(closingRegion.trailingRegion)
		End If
		Local clauses:TList = New TList
		While IsElseIfBoundary()
			Local clause:TElseIfClauseSyntax = ParseElseIfClause()
			clauses.AddLast(clause)
			Local clauseClosingRegion:TConditionalRegionSyntax
			If clause.block.statements.length Then clauseClosingRegion = TConditionalRegionSyntax(clause.block.statements[clause.block.statements.length - 1])
			If clauseClosingRegion And clauseClosingRegion.sharedControlTerminator Then
				node.terminator = clauseClosingRegion.sharedControlTerminator
				closedBoundary = 0
				If clauseClosingRegion.trailingRegion Then pendingMembers.AddLast(clauseClosingRegion.trailingRegion)
			End If
		Wend
		node.elseIfClauses = ElseIfToArray(clauses)
		If TextEquals(Current().text, "else") Then
			Local elseClause:TElseClauseSyntax = New TElseClauseSyntax
			elseClause.kind = SYNTAX_ELSE_CLAUSE
			elseClause.elseToken = Current()
			Local elseStart:Int = Current().span.start
			Advance()
			SkipSeparators()
			elseClause.block = ParseBoundaryBlock(BOUNDARY_IF)
			elseClause.span = TSourceSpan.Create(elseStart, elseClause.block.span.EndOffset() - elseStart)
			node.elseClause = elseClause
			Local elseClosingRegion:TConditionalRegionSyntax
			If elseClause.block.statements.length Then elseClosingRegion = TConditionalRegionSyntax(elseClause.block.statements[elseClause.block.statements.length - 1])
			If elseClosingRegion And elseClosingRegion.sharedControlTerminator Then
				node.terminator = elseClosingRegion.sharedControlTerminator
				closedBoundary = 0
				If elseClosingRegion.trailingRegion Then pendingMembers.AddLast(elseClosingRegion.trailingRegion)
			End If
		End If
		If node.terminator Then
			' A platform-conditional region supplied the terminator.
		Else If IsIfTerminator() Then
			node.terminator = ParseControlTerminator("if")
		Else If conditionalDepth > 0 And Current().kind = TOKEN_DIRECTIVE Then
			RegisterConditionalIfHeader(node)
			conditionalOpenIfBoundary = True
		Else
			AddDiagnostic("BMX2300", "Expected 'End If' or 'EndIf'.", Current().span)
		End If
		Local endOffset:Int = node.thenBlock.span.EndOffset()
		If node.elseIfClauses.length Then endOffset = node.elseIfClauses[node.elseIfClauses.length - 1].span.EndOffset()
		If node.elseClause Then endOffset = node.elseClause.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseElseIfClause:TElseIfClauseSyntax()
		Local node:TElseIfClauseSyntax = New TElseIfClauseSyntax
		node.kind = SYNTAX_ELSEIF_CLAUSE
		node.elseIfToken = Current()
		Local start:Int = Current().span.start
		Advance()
		If TextEquals(node.elseIfToken.text, "else") And TextEquals(Current().text, "if") Then Advance()
		Local header:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		Local thenIndex:Int = FindToken(header, "then")
		Local conditionEnd:Int = header.length
		If thenIndex >= 0 Then
			node.thenToken = header[thenIndex]
			conditionEnd = thenIndex
		End If
		node.condition = TBlitzMaxExpressionParser.Parse(header[..conditionEnd], diagnostics)
		SkipSeparators()
		node.block = ParseBoundaryBlock(BOUNDARY_IF)
		node.span = TSourceSpan.Create(start, node.block.span.EndOffset() - start)
		Return node
	End Method

	Method ParseWhileStatement:TWhileStatementSyntax()
		Local node:TWhileStatementSyntax = New TWhileStatementSyntax
		node.kind = SYNTAX_WHILE_STATEMENT
		node.whileToken = Current()
		Local start:Int = Current().span.start
		Advance()
		node.condition = TBlitzMaxExpressionParser.Parse(TokensFromList(CollectUntilSeparator()), diagnostics)
		SkipSeparators()
		node.body = ParseBoundaryBlock(BOUNDARY_WHILE)
		If IsWhileTerminator() Then node.terminator = ParseControlTerminator("while") Else AddDiagnostic("BMX2301", "Expected 'Wend' or 'End While'.", Current().span)
		Local endOffset:Int = node.body.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseRepeatStatement:TRepeatStatementSyntax()
		Local node:TRepeatStatementSyntax = New TRepeatStatementSyntax
		node.kind = SYNTAX_REPEAT_STATEMENT
		node.repeatToken = Current()
		Local start:Int = Current().span.start
		Advance()
		SkipSeparators()
		node.body = ParseBoundaryBlock(BOUNDARY_REPEAT)
		If TextEquals(Current().text, "until") Or TextEquals(Current().text, "forever") Then
			node.terminationToken = Current()
			Advance()
			If TextEquals(node.terminationToken.text, "until") Then node.condition = TBlitzMaxExpressionParser.Parse(TokensFromList(CollectUntilSeparator()), diagnostics)
		Else
			AddDiagnostic("BMX2302", "Expected 'Until' or 'Forever'.", Current().span)
		End If
		Local endOffset:Int = node.body.span.EndOffset()
		If node.condition Then endOffset = node.condition.span.EndOffset() Else If node.terminationToken Then endOffset = node.terminationToken.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseForStatement:TForStatementSyntax()
		Local node:TForStatementSyntax = New TForStatementSyntax
		node.kind = SYNTAX_FOR_STATEMENT
		node.forToken = Current()
		Local start:Int = Current().span.start
		Advance()
		node.headerTokens = TokensFromList(CollectUntilSeparator())
		node.header = ParseForHeader(node.headerTokens)
		SkipSeparators()
		node.body = ParseBoundaryBlock(BOUNDARY_FOR)
		If TextEquals(Current().text, "next") Then
			node.terminator = ParseControlTerminator("for")
		Else If conditionalDepth > 0 And Current().kind = TOKEN_DIRECTIVE Then
			RegisterConditionalForHeader(node)
			conditionalOpenForBoundary = True
		Else
			AddDiagnostic("BMX2303", "Expected 'Next'.", Current().span)
		End If
		Local endOffset:Int = node.body.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseForHeader:TForHeaderSyntax(values:TSyntaxToken[])
		Local node:TForHeaderSyntax = New TForHeaderSyntax
		node.kind = SYNTAX_FOR_HEADER
		If values.length = 0 Then
			node.span = TSourceSpan.Create(Current().span.start, 0)
			AddDiagnostic("BMX2310", "Expected a For-loop header.", node.span)
			Return node
		End If
		' A declared loop variable can end in a constructed generic type. With
		' no separating whitespace, its closing angle and the header assignment
		' are lexed as >= (for example, value:TBox<Int>=EachIn values).
		' Normalize that declaration boundary before locating the assignment.
		If TextEquals(values[0].text, "local") Then values = TBlitzMaxTypeParser.SplitGenericCloseAssignment(values)
		node.span = SpanOfTokens(values)

		Local assignmentIndex:Int = FindTopLevelToken(values, "=", 0)
		If assignmentIndex < 0 Then
			AddDiagnostic("BMX2311", "Expected '=' in For-loop header.", node.span)
			Return node
		End If
		node.assignmentToken = values[assignmentIndex]

		If TextEquals(values[0].text, "local") Then
			node.localToken = values[0]
			If assignmentIndex > 1 Then
				node.declarations = ParseForDeclarators(values[1..assignmentIndex])
				If node.declarations.length Then node.declaration = node.declarations[0]
			Else
				AddDiagnostic("BMX2312", "Expected a local loop variable before '='.", node.assignmentToken.span)
			End If
		Else
			If assignmentIndex > 0 Then node.target = TBlitzMaxExpressionParser.Parse(values[..assignmentIndex], diagnostics) Else AddDiagnostic("BMX2313", "Expected a loop target before '='.", node.assignmentToken.span)
		End If

		Local clauseIndex:Int = FindTopLevelForClause(values, assignmentIndex + 1)
		If clauseIndex < 0 Then
			AddDiagnostic("BMX2314", "Expected 'EachIn', 'To', or 'Until' in For-loop header.", node.span)
			If assignmentIndex + 1 < values.length Then node.initialValue = TBlitzMaxExpressionParser.Parse(values[assignmentIndex + 1..], diagnostics)
			Return node
		End If

		Local clause:String = values[clauseIndex].text.ToLower()
		If clause = "eachin" Then
			node.eachInToken = values[clauseIndex]
			If clauseIndex <> assignmentIndex + 1 Then AddDiagnostic("BMX2315", "'EachIn' must immediately follow '='.", node.eachInToken.span)
			If clauseIndex + 1 < values.length Then
				node.collection = TBlitzMaxExpressionParser.Parse(values[clauseIndex + 1..], diagnostics)
			Else
				AddDiagnostic("BMX2316", "Expected a collection after 'EachIn'.", node.eachInToken.span)
			End If
			Return node
		End If
		If node.declarations.length > 1 Then AddDiagnostic("BMX2319", "Multiple For-loop bindings are valid only with 'EachIn'.", node.declarations[1].span)

		node.rangeToken = values[clauseIndex]
		If clauseIndex > assignmentIndex + 1 Then
			node.initialValue = TBlitzMaxExpressionParser.Parse(values[assignmentIndex + 1..clauseIndex], diagnostics)
		Else
			AddDiagnostic("BMX2317", "Expected an initial value before '" + values[clauseIndex].text + "'.", node.rangeToken.span)
		End If
		Local stepIndex:Int = FindTopLevelKeyword(values, "step", clauseIndex + 1)
		Local limitEnd:Int = values.length
		If stepIndex >= 0 Then limitEnd = stepIndex
		If limitEnd > clauseIndex + 1 Then
			node.limit = TBlitzMaxExpressionParser.Parse(values[clauseIndex + 1..limitEnd], diagnostics)
		Else
			AddDiagnostic("BMX2318", "Expected a range limit after '" + values[clauseIndex].text + "'.", node.rangeToken.span)
		End If
		If stepIndex >= 0 Then
			node.stepToken = values[stepIndex]
			If stepIndex + 1 < values.length Then node.stepExpression = TBlitzMaxExpressionParser.Parse(values[stepIndex + 1..], diagnostics) Else AddDiagnostic("BMX2319", "Expected an expression after 'Step'.", node.stepToken.span)
		End If
		Return node
	End Method

	Method ParseForDeclarators:TVariableDeclaratorSyntax[](values:TSyntaxToken[])
		Local result:TVariableDeclaratorSyntax[] = New TVariableDeclaratorSyntax[0]
		Local start:Int
		Local parens:Int
		Local brackets:Int
		Local angles:Int
		For Local index:Int = 0 To values.length
			Local split:Int = index = values.length
			If Not split Then
				If values[index].text = "," And parens = 0 And brackets = 0 And angles = 0 Then split = True
				If Not split Then
					Select values[index].text
						Case "(" parens :+ 1
						Case ")" parens :- 1
						Case "[" brackets :+ 1
						Case "]" brackets :- 1
						Case "<" angles :+ 1
						Case ">" If angles > 0 Then angles :- 1
					End Select
				End If
			End If
			If split Then
				If index > start Then
					result :+ [ParseVariableDeclarator(values[start..index])]
				Else
					Local span:TSourceSpan
					If index < values.length Then span = values[index].span Else If values.length Then span = values[values.length - 1].span
					AddDiagnostic("BMX2312", "Expected a local loop variable between commas.", span)
				End If
				start = index + 1
			End If
		Next
		Return result
	End Method

	Method ParseSelectStatement:TSelectStatementSyntax()
		Local node:TSelectStatementSyntax = New TSelectStatementSyntax
		node.kind = SYNTAX_SELECT_STATEMENT
		node.selectToken = Current()
		Local start:Int = Current().span.start
		Advance()
		node.expression = TBlitzMaxExpressionParser.Parse(TokensFromList(CollectUntilSeparator()), diagnostics)
		SkipSeparators()

		Local clauses:TList = New TList
		Local defaults:TList = New TList
		Local unconditionalDefault:TDefaultClauseSyntax
		While Current().kind <> TOKEN_EOF And Not IsSelectTerminator()
			Local lower:String = Current().text.ToLower()
			If lower = "case" Then
				If unconditionalDefault Then AddDiagnostic("BMX2401", "A Case clause cannot follow Default.", Current().span)
				clauses.AddLast(ParseCaseClause())
			Else If ConditionalDirectiveStartsSelectClause() Then
				ParseConditionalSelectClauses(node, clauses, defaults)
			Else If lower = "default" Then
				Local clause:TDefaultClauseSyntax = ParseDefaultClause()
				If unconditionalDefault Then
					AddDiagnostic("BMX2400", "A Select statement can contain only one Default clause.", clause.defaultToken.span)
				Else
					unconditionalDefault = clause
				End If
				defaults.AddLast(clause)
			Else
				AddDiagnostic("BMX2402", "Expected 'Case', 'Default', or 'End Select'.", Current().span)
				ParseMember()
				SkipSeparators()
			End If
		Wend
		node.cases = CasesToArray(clauses)
		node.defaultClauses = DefaultsToArray(defaults)
		If node.defaultClauses.length Then node.defaultClause = node.defaultClauses[0]
		If IsSelectTerminator() Then node.terminator = ParseControlTerminator("select") Else AddDiagnostic("BMX2403", "Expected 'End Select' or 'EndSelect'.", Current().span)
		Local endOffset:Int = node.selectToken.span.EndOffset()
		If node.expression Then endOffset = node.expression.span.EndOffset()
		If node.cases.length Then endOffset = node.cases[node.cases.length - 1].span.EndOffset()
		For Local defaultClause:TDefaultClauseSyntax = EachIn node.defaultClauses
			If defaultClause.span.EndOffset() > endOffset Then endOffset = defaultClause.span.EndOffset()
		Next
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseConditionalSelectClauses(node:TSelectStatementSyntax, clauses:TList, defaults:TList)
		Local conditionalCases:TList = New TList
		Local conditionalDefaults:TList = New TList
		While Current().kind = TOKEN_DIRECTIVE And Not IsBareDirective(Current())
			Local directive:TSyntaxToken = Current()
			Local condition:TConditionalExpressionSyntax = TConditionalExpressionParser.Parse(directive, diagnostics)
			Advance()
			SkipSeparators()
			While Current().kind <> TOKEN_EOF And Current().kind <> TOKEN_DIRECTIVE And Not IsSelectTerminator()
				Local lower:String = Current().text.ToLower()
				If lower = "case" Then
					Local clause:TCaseClauseSyntax = ParseCaseClause(True)
					clause.conditionalExpression = condition
					clauses.AddLast(clause)
					conditionalCases.AddLast(clause)
				Else If lower = "default" Then
					Local defaultClause:TDefaultClauseSyntax = ParseDefaultClause(True)
					defaultClause.conditionalExpression = condition
					defaults.AddLast(defaultClause)
					conditionalDefaults.AddLast(defaultClause)
				Else
					AddDiagnostic("BMX2402", "Expected 'Case', 'Default', or a conditional directive inside Select.", Current().span)
					ParseMember()
					SkipSeparators()
				End If
			Wend
		Wend
		If Current().kind = TOKEN_DIRECTIVE And IsBareDirective(Current()) Then
			Advance()
			SkipSeparators()
			' Conditional alternatives may select only the Case label and then
			' share the body following the closing bare directive:
			' ?ptr32 / Case A / ?ptr64 / Case B / ? / body.
			' After preprocessing, that body belongs to whichever label survived.
			Local sharedBody:TBlockSyntax = ParseBoundaryBlock(BOUNDARY_SELECT)
			If sharedBody And sharedBody.statements.length Then
				For Local conditionalCase:TCaseClauseSyntax = EachIn conditionalCases
					conditionalCase.body = BlockWithTrailingStatements(conditionalCase.body, sharedBody)
					conditionalCase.span = TSourceSpan.Create(conditionalCase.span.start, conditionalCase.body.span.EndOffset() - conditionalCase.span.start)
				Next
				For Local conditionalDefault:TDefaultClauseSyntax = EachIn conditionalDefaults
					conditionalDefault.body = BlockWithTrailingStatements(conditionalDefault.body, sharedBody)
					conditionalDefault.span = TSourceSpan.Create(conditionalDefault.span.start, conditionalDefault.body.span.EndOffset() - conditionalDefault.span.start)
				Next
			End If
		Else
			AddDiagnostic("BMX2430", "Expected '?' to end conditional Select clauses.", Current().span)
		End If
	End Method

	Method ParseCaseClause:TCaseClauseSyntax(conditionalClause:Int = False)
		Local node:TCaseClauseSyntax = New TCaseClauseSyntax
		node.kind = SYNTAX_CASE_CLAUSE
		node.caseToken = Current()
		Local start:Int = Current().span.start
		Advance()
		Local header:TParsedCaseHeader = ParseCaseHeader(TokensFromList(CollectUntilSeparator()))
		node.values = header.values
		SkipSeparators()
		Local boundary:Int = BOUNDARY_SELECT
		If conditionalClause Then boundary = BOUNDARY_CONDITIONAL_SELECT_CLAUSE
		node.body = ParseBoundaryBlock(boundary)
		If header.inlineTokens.length Then node.body = BlockWithLeadingStatements(node.body, BlockWithCompactInlineTokens(header.inlineTokens, node.caseToken.span.EndOffset()))
		Local endOffset:Int = node.caseToken.span.EndOffset()
		If node.values.length Then endOffset = node.values[node.values.length - 1].span.EndOffset()
		If node.body.statements.length Then endOffset = node.body.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseDefaultClause:TDefaultClauseSyntax(conditionalClause:Int = False)
		Local node:TDefaultClauseSyntax = New TDefaultClauseSyntax
		node.kind = SYNTAX_DEFAULT_CLAUSE
		node.defaultToken = Current()
		Local start:Int = Current().span.start
		Advance()
		Local inlineTokens:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		SkipSeparators()
		Local boundary:Int = BOUNDARY_SELECT
		If conditionalClause Then boundary = BOUNDARY_CONDITIONAL_SELECT_CLAUSE
		node.body = ParseBoundaryBlock(boundary)
		If inlineTokens.length Then node.body = BlockWithLeadingStatements(node.body, BlockWithCompactInlineTokens(inlineTokens, node.defaultToken.span.EndOffset()))
		Local endOffset:Int = node.defaultToken.span.EndOffset()
		If node.body.statements.length Then endOffset = node.body.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseTryStatement:TTryStatementSyntax()
		Local node:TTryStatementSyntax = New TTryStatementSyntax
		node.kind = SYNTAX_TRY_STATEMENT
		node.tryToken = Current()
		Local start:Int = Current().span.start
		Advance()
		Local unexpected:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		If unexpected.length Then AddDiagnostic("BMX2410", "Try does not accept a header expression.", SpanOfTokens(unexpected))
		SkipSeparators()
		node.body = ParseBoundaryBlock(BOUNDARY_TRY)

		Local catches:TList = New TList
		While TextEquals(Current().text, "catch")
			catches.AddLast(ParseCatchClause())
		Wend
		node.catches = CatchesToArray(catches)
		If TextEquals(Current().text, "finally") Then node.finallyClause = ParseFinallyClause()
		If TextEquals(Current().text, "catch") Then
			AddDiagnostic("BMX2411", "A Catch clause cannot follow Finally.", Current().span)
			While TextEquals(Current().text, "catch")
				ParseCatchClause()
			Wend
		End If
		While TextEquals(Current().text, "finally")
			AddDiagnostic("BMX2416", "A Try statement can contain only one Finally clause.", Current().span)
			ParseFinallyClause()
		Wend
		If node.catches.length = 0 And Not node.finallyClause Then AddDiagnostic("BMX2412", "A Try statement requires Catch or Finally.", node.tryToken.span)
		If IsTryTerminator() Then node.terminator = ParseControlTerminator("try") Else AddDiagnostic("BMX2413", "Expected 'End Try' or 'EndTry'.", Current().span)
		Local endOffset:Int = node.body.span.EndOffset()
		If node.catches.length Then endOffset = node.catches[node.catches.length - 1].span.EndOffset()
		If node.finallyClause Then endOffset = node.finallyClause.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseCatchClause:TCatchClauseSyntax()
		Local node:TCatchClauseSyntax = New TCatchClauseSyntax
		node.kind = SYNTAX_CATCH_CLAUSE
		node.catchToken = Current()
		Local start:Int = Current().span.start
		Advance()
		node.headerTokens = TokensFromList(CollectUntilSeparator())
		If node.headerTokens.length And IsNameToken(node.headerTokens[0]) Then
			node.nameToken = node.headerTokens[0]
			If node.headerTokens.length > 1 Then
				node.declaredType = TBlitzMaxTypeParser.Parse(node.headerTokens[1..])
			Else
				AddDiagnostic("BMX2417", "Expected a caught value type.", node.nameToken.span)
			End If
		Else
			AddDiagnostic("BMX2414", "Expected a caught value name.", node.catchToken.span)
		End If
		SkipSeparators()
		node.body = ParseBoundaryBlock(BOUNDARY_TRY)
		Local endOffset:Int = node.catchToken.span.EndOffset()
		If node.headerTokens.length Then endOffset = node.headerTokens[node.headerTokens.length - 1].span.EndOffset()
		If node.body.statements.length Then endOffset = node.body.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseFinallyClause:TFinallyClauseSyntax()
		Local node:TFinallyClauseSyntax = New TFinallyClauseSyntax
		node.kind = SYNTAX_FINALLY_CLAUSE
		node.finallyToken = Current()
		Local start:Int = Current().span.start
		Advance()
		Local unexpected:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		If unexpected.length Then AddDiagnostic("BMX2415", "Finally does not accept a header expression.", SpanOfTokens(unexpected))
		SkipSeparators()
		node.body = ParseBoundaryBlock(BOUNDARY_TRY)
		Local endOffset:Int = node.finallyToken.span.EndOffset()
		If node.body.statements.length Then endOffset = node.body.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseUsingStatement:TUsingStatementSyntax()
		Local node:TUsingStatementSyntax = New TUsingStatementSyntax
		node.kind = SYNTAX_USING_STATEMENT
		node.usingToken = Current()
		Local start:Int = Current().span.start
		Advance()
		Local inlineResource:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		Local resources:TList = New TList
		If inlineResource.length Then
			If TextEquals(inlineResource[0].text, "local") Then
				resources.AddLast(ParseVariableDeclaration(inlineResource, SpanOfTokens(inlineResource)))
			Else
				AddDiagnostic("BMX2420", "Expected a Local resource declaration after Using.", SpanOfTokens(inlineResource))
			End If
		End If
		SkipSeparators()

		While Current().kind <> TOKEN_EOF And Not TextEquals(Current().text, "do") And Not IsUsingTerminator()
			Local resource:TSyntaxNode = ParseMember()
			Local declaration:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(resource)
			If declaration And TextEquals(declaration.declarationToken.text, "local") Then
				resources.AddLast(declaration)
			Else
				AddDiagnostic("BMX2421", "Using requires Local resource declarations before Do.", resource.span)
			End If
			SkipSeparators()
		Wend
		node.resources = ResourceDeclarationsToArray(resources)
		If node.resources.length = 0 Then AddDiagnostic("BMX2422", "Using requires at least one Local resource declaration.", node.usingToken.span)
		If TextEquals(Current().text, "do") Then
			node.doToken = Current()
			Advance()
		Else
			AddDiagnostic("BMX2423", "Expected 'Do' after Using resources.", Current().span)
		End If
		SkipSeparators()
		node.body = ParseBoundaryBlock(BOUNDARY_USING)
		If IsUsingTerminator() Then node.terminator = ParseControlTerminator("using") Else AddDiagnostic("BMX2424", "Expected 'End Using' or 'EndUsing'.", Current().span)
		Local endOffset:Int = node.usingToken.span.EndOffset()
		If node.resources.length Then endOffset = node.resources[node.resources.length - 1].span.EndOffset()
		If node.body.statements.length Then endOffset = node.body.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseConditionalRegion:TConditionalRegionSyntax()
		Local node:TConditionalRegionSyntax = New TConditionalRegionSyntax
		node.kind = SYNTAX_CONDITIONAL_REGION
		Local start:Int = Current().span.start
		Local branches:TList = New TList
		Local previousExternHeaderSeen:Int = conditionalExternHeaderSeen
		Local previousRoutineHeaders:TList = conditionalRoutineHeaders
		Local previousForHeaderGroups:TList = conditionalForHeaderGroups
		Local previousForHeaderIndex:Int = conditionalForHeaderIndex
		Local previousOpenForBoundary:Int = conditionalOpenForBoundary
		Local previousIfHeaderGroups:TList = conditionalIfHeaderGroups
		Local previousIfHeaderIndex:Int = conditionalIfHeaderIndex
		Local previousOpenIfBoundary:Int = conditionalOpenIfBoundary
		conditionalRoutineHeaders = New TList
		conditionalForHeaderGroups = New TList
		conditionalIfHeaderGroups = New TList
		conditionalExternHeaderSeen = False
		conditionalDepth :+ 1
		Local outerBoundary:Int = activeBoundary

		While Current().kind = TOKEN_DIRECTIVE And Not IsBareDirective(Current())
			conditionalForHeaderIndex = 0
			conditionalOpenForBoundary = False
			conditionalIfHeaderIndex = 0
			conditionalOpenIfBoundary = False
			Local branch:TConditionalBranchSyntax = New TConditionalBranchSyntax
			branch.kind = SYNTAX_CONDITIONAL_BRANCH
			branch.directiveToken = Current()
			branch.conditionText = DirectiveCondition(Current())
			branch.condition = TConditionalExpressionParser.Parse(branch.directiveToken, diagnostics)
			Local branchStart:Int = Current().span.start
			Advance()
			SkipSeparators()
			branch.body = ParseConditionalBranchBody(outerBoundary, node, branch)
			Local branchEnd:Int = branch.directiveToken.span.EndOffset()
			If branch.body.statements.length Then branchEnd = branch.body.span.EndOffset()
			branch.span = TSourceSpan.Create(branchStart, branchEnd - branchStart)
			branches.AddLast(branch)
			If node.sharedControlTerminator Then Exit
		Wend

		node.branches = ConditionalBranchesToArray(branches)
		If Current().kind = TOKEN_DIRECTIVE And IsBareDirective(Current()) Then
			node.endDirectiveToken = Current()
			Advance()
			If conditionalDepth > 1 And node.sharedControlTerminator Then
				sharedConditionalEndToken = node.endDirectiveToken
				sharedConditionalEndDepth = conditionalDepth - 1
			End If
		Else If sharedConditionalEndToken And sharedConditionalEndDepth = conditionalDepth Then
			node.endDirectiveToken = sharedConditionalEndToken
			sharedConditionalEndToken = Null
			sharedConditionalEndDepth = 0
		Else If Current().kind <> TOKEN_EOF And Not node.sharedControlTerminator
			AddDiagnostic("BMX2430", "Expected '?' to end conditional region.", Current().span)
		End If
		conditionalDepth :- 1
		Local routineHeaders:TList = conditionalRoutineHeaders
		Local forHeaderGroups:TList = conditionalForHeaderGroups
		Local ifHeaderGroups:TList = conditionalIfHeaderGroups
		conditionalRoutineHeaders = previousRoutineHeaders
		conditionalForHeaderGroups = previousForHeaderGroups
		conditionalForHeaderIndex = previousForHeaderIndex
		conditionalOpenForBoundary = previousOpenForBoundary
		conditionalIfHeaderGroups = previousIfHeaderGroups
		conditionalIfHeaderIndex = previousIfHeaderIndex
		conditionalOpenIfBoundary = previousOpenIfBoundary
		Local openedExtern:Int = conditionalExternHeaderSeen
		conditionalExternHeaderSeen = previousExternHeaderSeen Or openedExtern
		Local sharedExtern:TParsedBlock
		If openedExtern And conditionalDepth = 0 Then
			SkipSeparators()
			externDepth :+ 1
			sharedExtern = ParseBlock("extern")
			externDepth :- 1
			For Local externBranch:TConditionalBranchSyntax = EachIn node.branches
				For Local externNode:TSyntaxNode = EachIn externBranch.body.statements
					Local external:TExternBlockSyntax = TExternBlockSyntax(externNode)
					If Not external Then Continue
					external.body = sharedExtern.block
					external.terminator = sharedExtern.terminator
					Local externalEnd:Int = external.body.span.EndOffset()
					If external.terminator Then externalEnd = external.terminator.span.EndOffset()
					external.span = TSourceSpan.Create(external.externToken.span.start, externalEnd - external.externToken.span.start)
				Next
			Next
		End If
		Local endOffset:Int = start
		If node.branches.length Then endOffset = node.branches[node.branches.length - 1].span.EndOffset()
		If node.endDirectiveToken Then endOffset = node.endDirectiveToken.span.EndOffset()
		If sharedExtern And sharedExtern.terminator Then endOffset = sharedExtern.terminator.span.EndOffset()
		For Local forGroup:TConditionalForHeaderGroup = EachIn forHeaderGroups
			SkipSeparators()
			Local sharedForBody:TBlockSyntax = ParseBoundaryBlock(BOUNDARY_FOR)
			Local sharedForTerminator:TBlockTerminatorSyntax
			If TextEquals(Current().text, "next") Then sharedForTerminator = ParseControlTerminator("for") Else AddDiagnostic("BMX2303", "Expected 'Next'.", Current().span)
			For Local header:TForStatementSyntax = EachIn forGroup.headers
				header.body = BlockWithTrailingStatements(header.body, sharedForBody)
				header.terminator = sharedForTerminator
				Local headerEnd:Int = header.body.span.EndOffset()
				If sharedForTerminator Then headerEnd = sharedForTerminator.span.EndOffset()
				header.span = TSourceSpan.Create(header.forToken.span.start, headerEnd - header.forToken.span.start)
			Next
			If sharedForTerminator Then endOffset = sharedForTerminator.span.EndOffset()
		Next
		For Local ifGroup:TConditionalIfHeaderGroup = EachIn ifHeaderGroups
			SkipSeparators()
			Local sharedIfBody:TBlockSyntax = ParseBoundaryBlock(BOUNDARY_IF)
			Local sharedElseIfClauses:TList = New TList
			While IsElseIfBoundary()
				sharedElseIfClauses.AddLast(ParseElseIfClause())
			Wend
			Local sharedElseClause:TElseClauseSyntax
			If TextEquals(Current().text, "else") Then
				sharedElseClause = New TElseClauseSyntax
				sharedElseClause.kind = SYNTAX_ELSE_CLAUSE
				sharedElseClause.elseToken = Current()
				Local elseStart:Int = Current().span.start
				Advance()
				SkipSeparators()
				sharedElseClause.block = ParseBoundaryBlock(BOUNDARY_IF)
				sharedElseClause.span = TSourceSpan.Create(elseStart, sharedElseClause.block.span.EndOffset() - elseStart)
			End If
			Local sharedIfTerminator:TBlockTerminatorSyntax
			If IsIfTerminator() Then sharedIfTerminator = ParseControlTerminator("if") Else AddDiagnostic("BMX2300", "Expected 'End If' or 'EndIf'.", Current().span)
			Local sharedElseIfArray:TElseIfClauseSyntax[] = ElseIfToArray(sharedElseIfClauses)
			For Local headerIf:TIfStatementSyntax = EachIn ifGroup.headers
				headerIf.thenBlock = BlockWithTrailingStatements(headerIf.thenBlock, sharedIfBody)
				headerIf.elseIfClauses = sharedElseIfArray
				headerIf.elseClause = sharedElseClause
				headerIf.terminator = sharedIfTerminator
				Local headerEnd:Int = headerIf.thenBlock.span.EndOffset()
				If sharedElseIfArray.length Then headerEnd = sharedElseIfArray[sharedElseIfArray.length - 1].span.EndOffset()
				If sharedElseClause Then headerEnd = sharedElseClause.span.EndOffset()
				If sharedIfTerminator Then headerEnd = sharedIfTerminator.span.EndOffset()
				headerIf.span = TSourceSpan.Create(headerIf.ifToken.span.start, headerEnd - headerIf.ifToken.span.start)
			Next
			If sharedIfTerminator Then endOffset = sharedIfTerminator.span.EndOffset()
		Next
		If routineHeaders.Count() Then
			Local firstRoutine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routineHeaders.First())
			Local expected:String = firstRoutine.declarationToken.text.ToLower()
			If Not node.sharedRoutineBody Then
				SkipSeparators()
				Local parsed:TParsedBlock = ParseBlock(expected)
				node.sharedRoutineBody = parsed.block
				node.sharedRoutineTerminator = parsed.terminator
			End If
			endOffset = node.sharedRoutineBody.span.EndOffset()
			If node.sharedRoutineTerminator Then endOffset = node.sharedRoutineTerminator.span.EndOffset()
			For Local headerRoutine:TRoutineDeclarationSyntax = EachIn routineHeaders
				headerRoutine.body = BlockWithTrailingStatements(headerRoutine.body, node.sharedRoutineBody)
				headerRoutine.terminator = node.sharedRoutineTerminator
				headerRoutine.span = TSourceSpan.Create(headerRoutine.span.start, endOffset - headerRoutine.span.start)
			Next
		End If
		If node.sharedControlTerminator Then
			node.trailingRegion = CreateTrailingConditionalRegion(node)
			closedBoundary = outerBoundary
		End If
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseBoundaryBlock:TBlockSyntax(boundary:Int)
		Local statements:TList = New TList
		Local start:Int = Current().span.start
		Local previousBoundary:Int = activeBoundary
		activeBoundary = boundary
		While Current().kind <> TOKEN_EOF And Not IsBoundary(boundary)
			If boundary = BOUNDARY_FOR And conditionalDepth > 0 And Current().kind = TOKEN_DIRECTIVE Then Exit
			statements.AddLast(ParseMember())
			SkipSeparators()
			If conditionalOpenForBoundary And Current().kind = TOKEN_DIRECTIVE Then Exit
			If conditionalOpenIfBoundary And Current().kind = TOKEN_DIRECTIVE Then Exit
			If closedBoundary = boundary Then Exit
			While pendingMembers.Count()
				statements.AddLast(TSyntaxNode(pendingMembers.RemoveFirst()))
			Wend
		Wend
		activeBoundary = previousBoundary
		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = NodesToArray(statements)
		Local endOffset:Int = Current().span.start
		If block.statements.length Then endOffset = block.statements[block.statements.length - 1].span.EndOffset()
		block.span = TSourceSpan.Create(start, Max(0, endOffset - start))
		Return block
	End Method

	Method IsConditionalIfHeaderBoundary:Int()
		If Current().kind <> TOKEN_DIRECTIVE Then Return False
		If IsBareDirective(Current()) Then Return True
		Local index:Int = position + 1
		While index < tokens.length And IsSeparator(tokens[index])
			index :+ 1
		Wend
		Return index < tokens.length And TextEquals(tokens[index].text, "if")
	End Method

	Method RegisterConditionalIfHeader(node:TIfStatementSyntax)
		If Not conditionalIfHeaderGroups Then conditionalIfHeaderGroups = New TList
		While conditionalIfHeaderGroups.Count() <= conditionalIfHeaderIndex
			conditionalIfHeaderGroups.AddLast(New TConditionalIfHeaderGroup)
		Wend
		Local index:Int
		For Local group:TConditionalIfHeaderGroup = EachIn conditionalIfHeaderGroups
			If index = conditionalIfHeaderIndex Then
				group.headers.AddLast(node)
				Exit
			End If
			index :+ 1
		Next
		conditionalIfHeaderIndex :+ 1
	End Method

	Method RegisterConditionalForHeader(node:TForStatementSyntax)
		If Not conditionalForHeaderGroups Then conditionalForHeaderGroups = New TList
		While conditionalForHeaderGroups.Count() <= conditionalForHeaderIndex
			conditionalForHeaderGroups.AddLast(New TConditionalForHeaderGroup)
		Wend
		Local index:Int
		For Local group:TConditionalForHeaderGroup = EachIn conditionalForHeaderGroups
			If index = conditionalForHeaderIndex Then
				group.headers.AddLast(node)
				Exit
			End If
			index :+ 1
		Next
		conditionalForHeaderIndex :+ 1
	End Method

	Method ParseConditionalBranchBody:TBlockSyntax(outerBoundary:Int, region:TConditionalRegionSyntax, branch:TConditionalBranchSyntax)
		Local statements:TList = New TList
		Local trailing:TList
		Local start:Int = Current().span.start
		Local previousBoundary:Int = activeBoundary
		activeBoundary = BOUNDARY_CONDITIONAL
		If conditionalRoutineHeaders And conditionalRoutineHeaders.Count() Then
			Local firstRoutine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(conditionalRoutineHeaders.First())
			Local expected:String = firstRoutine.declarationToken.text.ToLower()
			If HasRoutineTerminatorBeforeDirective(expected) Then
				Local parsed:TParsedBlock = ParseBlock(expected)
				region.sharedRoutineBody = parsed.block
				region.sharedRoutineTerminator = parsed.terminator
				SkipSeparators()
				activeBoundary = previousBoundary
				Return EmptyBlockAt(start)
			End If
		End If
		While Current().kind <> TOKEN_EOF And Current().kind <> TOKEN_DIRECTIVE
			If sharedConditionalEndToken And sharedConditionalEndDepth = conditionalDepth Then Exit
			If IsTerminatorForBoundary(outerBoundary) Then
				Local terminator:TBlockTerminatorSyntax = ParseBoundaryTerminator(outerBoundary)
				If Not region.sharedControlTerminator Then region.sharedControlTerminator = terminator
				SkipSeparators()
				trailing = New TList
				While Current().kind <> TOKEN_EOF And Current().kind <> TOKEN_DIRECTIVE
					If sharedConditionalEndToken And sharedConditionalEndDepth = conditionalDepth Then Exit
					trailing.AddLast(ParseMember())
					SkipSeparators()
					While pendingMembers.Count()
						trailing.AddLast(TSyntaxNode(pendingMembers.RemoveFirst()))
					Wend
				Wend
				Exit
			End If
			statements.AddLast(ParseMember())
			SkipSeparators()
			While pendingMembers.Count()
				statements.AddLast(TSyntaxNode(pendingMembers.RemoveFirst()))
			Wend
		Wend
		activeBoundary = previousBoundary
		Local block:TBlockSyntax = BlockFromStatements(statements, start)
		If trailing Then branch.trailingBody = BlockFromStatements(trailing, terminatorEnd(region.sharedControlTerminator))
		Return block
	End Method

	Method HasRoutineTerminatorBeforeDirective:Int(expected:String)
		Return HasRoutineTerminatorBeforeNextDirective(position, expected)
	End Method

	Method HasRoutineTerminatorBeforeNextDirective:Int(startIndex:Int, expected:String)
		For Local index:Int = startIndex Until tokens.length
			Local token:TSyntaxToken = tokens[index]
			If token.kind = TOKEN_DIRECTIVE Then Return False
			Local lower:String = token.text.ToLower()
			If lower = "end" + expected Then Return True
			If lower = "end" And index + 1 < tokens.length And tokens[index + 1].text.ToLower() = expected Then Return True
		Next
		Return False
	End Method

	Method IsTerminatorForBoundary:Int(boundary:Int)
		Select boundary
			Case BOUNDARY_IF Return IsIfTerminator()
			Case BOUNDARY_WHILE Return IsWhileTerminator()
			Case BOUNDARY_FOR Return TextEquals(Current().text, "next")
			Case BOUNDARY_SELECT, BOUNDARY_CONDITIONAL_SELECT_CLAUSE Return IsSelectTerminator()
			Case BOUNDARY_TRY Return IsTryTerminator()
			Case BOUNDARY_USING Return IsUsingTerminator()
			Case BOUNDARY_EXTERN Return IsBlockTerminator() And (TextEquals(Current().text, "endextern") Or TextEquals(Peek(1).text, "extern"))
		End Select
		Return False
	End Method

	Method ParseBoundaryTerminator:TBlockTerminatorSyntax(boundary:Int)
		Select boundary
			Case BOUNDARY_IF Return ParseControlTerminator("if")
			Case BOUNDARY_WHILE Return ParseControlTerminator("while")
			Case BOUNDARY_FOR Return ParseControlTerminator("for")
			Case BOUNDARY_SELECT, BOUNDARY_CONDITIONAL_SELECT_CLAUSE Return ParseControlTerminator("select")
			Case BOUNDARY_TRY Return ParseControlTerminator("try")
			Case BOUNDARY_USING Return ParseControlTerminator("using")
			Case BOUNDARY_EXTERN Return ParseBlockTerminator("extern")
		End Select
		Return Null
	End Method

	Function BlockFromStatements:TBlockSyntax(statements:TList, start:Int)
		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = NodesToArray(statements)
		Local endOffset:Int = start
		If block.statements.length Then endOffset = block.statements[block.statements.length - 1].span.EndOffset()
		block.span = TSourceSpan.Create(start, Max(0, endOffset - start))
		Return block
	End Function

	Function terminatorEnd:Int(terminator:TBlockTerminatorSyntax)
		If terminator Then Return terminator.span.EndOffset()
		Return 0
	End Function

	Function CreateTrailingConditionalRegion:TConditionalRegionSyntax(region:TConditionalRegionSyntax)
		Local result:TConditionalRegionSyntax = New TConditionalRegionSyntax
		result.kind = SYNTAX_CONDITIONAL_REGION
		result.endDirectiveToken = region.endDirectiveToken
		Local branches:TList = New TList
		For Local sourceBranch:TConditionalBranchSyntax = EachIn region.branches
			If Not sourceBranch.trailingBody Or Not sourceBranch.trailingBody.statements.length Then Continue
			Local branch:TConditionalBranchSyntax = New TConditionalBranchSyntax
			branch.kind = SYNTAX_CONDITIONAL_BRANCH
			branch.directiveToken = sourceBranch.directiveToken
			branch.conditionText = sourceBranch.conditionText
			branch.condition = sourceBranch.condition
			branch.body = sourceBranch.trailingBody
			branch.span = TSourceSpan.Create(branch.directiveToken.span.start, branch.body.span.EndOffset() - branch.directiveToken.span.start)
			branches.AddLast(branch)
		Next
		result.branches = ConditionalBranchesToArray(branches)
		If Not result.branches.length Then Return Null
		Local endOffset:Int = result.branches[result.branches.length - 1].span.EndOffset()
		If result.endDirectiveToken Then endOffset = result.endDirectiveToken.span.EndOffset()
		result.span = TSourceSpan.Create(result.branches[0].span.start, endOffset - result.branches[0].span.start)
		Return result
	End Function

	Method IsBoundary:Int(boundary:Int)
		Select boundary
			Case BOUNDARY_IF
				Return IsElseIfBoundary() Or TextEquals(Current().text, "else") Or IsIfTerminator()
			Case BOUNDARY_WHILE
				Return IsWhileTerminator()
			Case BOUNDARY_REPEAT
				Return TextEquals(Current().text, "until") Or TextEquals(Current().text, "forever")
			Case BOUNDARY_FOR
				Return TextEquals(Current().text, "next")
			Case BOUNDARY_SELECT
				Return ConditionalDirectiveStartsSelectClause() Or TextEquals(Current().text, "case") Or TextEquals(Current().text, "default") Or IsSelectTerminator()
			Case BOUNDARY_CONDITIONAL_SELECT_CLAUSE
				Return (Current().kind = TOKEN_DIRECTIVE And IsBareDirective(Current())) Or ConditionalDirectiveStartsSelectClause() Or TextEquals(Current().text, "case") Or TextEquals(Current().text, "default") Or IsSelectTerminator()
			Case BOUNDARY_TRY
				Return TextEquals(Current().text, "catch") Or TextEquals(Current().text, "finally") Or IsTryTerminator()
			Case BOUNDARY_USING
				Return IsUsingTerminator()
			Case BOUNDARY_CONDITIONAL
				Return Current().kind = TOKEN_DIRECTIVE
		End Select
		Return False
	End Method

	Method IsElseIfBoundary:Int()
		Return TextEquals(Current().text, "elseif") Or (TextEquals(Current().text, "else") And TextEquals(Peek(1).text, "if"))
	End Method

	Method ConditionalDirectiveStartsSelectClause:Int()
		If Current().kind <> TOKEN_DIRECTIVE Or IsBareDirective(Current()) Then Return False
		Local distance:Int = 1
		While position + distance < tokens.length And IsSeparator(Peek(distance))
			distance :+ 1
		Wend
		If position + distance >= tokens.length Then Return False
		Return TextEquals(Peek(distance).text, "case") Or TextEquals(Peek(distance).text, "default")
	End Method

	Method IsIfTerminator:Int()
		Return TextEquals(Current().text, "endif") Or (TextEquals(Current().text, "end") And TextEquals(Peek(1).text, "if"))
	End Method

	Method IsWhileTerminator:Int()
		Return TextEquals(Current().text, "wend") Or TextEquals(Current().text, "endwhile") Or (TextEquals(Current().text, "end") And TextEquals(Peek(1).text, "while"))
	End Method

	Method IsSelectTerminator:Int()
		Return TextEquals(Current().text, "endselect") Or (TextEquals(Current().text, "end") And TextEquals(Peek(1).text, "select"))
	End Method

	Method IsTryTerminator:Int()
		Return TextEquals(Current().text, "endtry") Or (TextEquals(Current().text, "end") And TextEquals(Peek(1).text, "try"))
	End Method

	Method IsUsingTerminator:Int()
		Return TextEquals(Current().text, "endusing") Or (TextEquals(Current().text, "end") And TextEquals(Peek(1).text, "using"))
	End Method

	Method ParseControlTerminator:TBlockTerminatorSyntax(expected:String)
		Local node:TBlockTerminatorSyntax = New TBlockTerminatorSyntax
		node.kind = SYNTAX_BLOCK_TERMINATOR
		node.expectedBlockKind = expected
		node.actualBlockKind = expected
		node.endToken = Current()
		Local start:Int = Current().span.start
		Local lower:String = Current().text.ToLower()
		Advance()
		If lower = "end" Then
			node.blockToken = Current()
			Advance()
		End If
		Local endOffset:Int = node.endToken.span.EndOffset()
		If node.blockToken Then endOffset = node.blockToken.span.EndOffset()
		If expected = "for" Then
			Local rest:TList = CollectUntilSeparator()
			For Local token:TSyntaxToken = EachIn rest
				endOffset = token.span.EndOffset()
			Next
		End If
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method CreateInlineStatement:TSyntaxNode(values:TSyntaxToken[])
		Local span:TSourceSpan = SpanOfTokens(values)
		If values.length And TextEquals(values[0].text, "if") Then Return CreateInlineIfStatement(values)
		If values.length And IsVariableDeclarationStatement(values) Then Return ParseVariableDeclaration(values, span)
		Local flowStatement:TSyntaxNode = ParseFlowStatement(values, span)
		If flowStatement Then Return flowStatement
		Local dataStatement:TSyntaxNode = ParseDataStatement(values, span)
		If dataStatement Then Return dataStatement
		If values.length = 1 And TextEquals(values[0].text, "end") Then
			Local node:TEndStatementSyntax = New TEndStatementSyntax
			node.kind = SYNTAX_END_STATEMENT
			node.endToken = values[0]
			node.span = span
			Return node
		End If
		Local assignmentIndex:Int = FindAssignmentOperator(values)
		If assignmentIndex > 0 And IsCommandCallBeforeAssignment(values, assignmentIndex) Then
			Return CreateCallStatement(values, span)
		End If
		If assignmentIndex > 0 And IsAssignmentTargetStart(values[0]) Then
			Local assignment:TAssignmentStatementSyntax = New TAssignmentStatementSyntax
			assignment.kind = SYNTAX_ASSIGNMENT_STATEMENT
			assignment.span = span
			assignment.operatorToken = values[assignmentIndex]
			If assignment.operatorToken.text = ":=" Then AddDiagnostic("BMX2053", "The ':=' syntax is only valid in an inferred Local declaration; use '=' for assignment.", assignment.operatorToken.span)
			assignment.left = TBlitzMaxExpressionParser.Parse(values[..assignmentIndex], diagnostics)
			assignment.right = TBlitzMaxExpressionParser.Parse(values[assignmentIndex + 1..], diagnostics)
			Return assignment
		End If
		If IsCallStatement(values) Then Return CreateCallStatement(values, span)
		Local raw:TRawStatementSyntax = New TRawStatementSyntax
		raw.kind = SYNTAX_RAW_STATEMENT
		raw.tokens = values
		raw.span = span
		Return raw
	End Method

	Method CreateInlineIfStatement:TIfStatementSyntax(values:TSyntaxToken[])
		Local node:TIfStatementSyntax = New TIfStatementSyntax
		node.kind = SYNTAX_IF_STATEMENT
		node.ifToken = values[0]
		node.singleLine = True
		node.elseIfClauses = New TElseIfClauseSyntax[0]
		Local header:TSyntaxToken[] = values[1..]
		Local thenIndex:Int = FindToken(header, "then")
		Local conditionEnd:Int
		Local inlineStart:Int
		If thenIndex >= 0 Then
			node.thenToken = header[thenIndex]
			conditionEnd = thenIndex
			inlineStart = thenIndex + 1
		Else
			Local prefix:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(header, diagnostics)
			conditionEnd = prefix.consumed
			inlineStart = prefix.consumed
			node.condition = prefix.expression
		End If
		If Not node.condition Then node.condition = TBlitzMaxExpressionParser.Parse(header[..conditionEnd], diagnostics)
		PopulateInlineBranches(node, header[inlineStart..])
		Local endOffset:Int = node.thenBlock.span.EndOffset()
		If node.elseClause Then endOffset = node.elseClause.span.EndOffset()
		node.span = TSourceSpan.Create(node.ifToken.span.start, endOffset - node.ifToken.span.start)
		Return node
	End Method

	Method PopulateInlineBranches(node:TIfStatementSyntax, values:TSyntaxToken[])
		Local elseIndex:Int = FindInlineElse(values)
		Local thenValues:TSyntaxToken[] = values
		If elseIndex >= 0 Then thenValues = values[..elseIndex]
		node.thenBlock = BlockWithInlineTokens(thenValues, node.ifToken.span.EndOffset())
		If elseIndex >= 0 Then
			If TextEquals(values[elseIndex].text, "elseif") Then
				Local nested:TIfStatementSyntax = CreateInlineIfStatement(values[elseIndex..])
				Local firstClause:TElseIfClauseSyntax = New TElseIfClauseSyntax
				firstClause.kind = SYNTAX_ELSEIF_CLAUSE
				firstClause.elseIfToken = values[elseIndex]
				firstClause.condition = nested.condition
				firstClause.thenToken = nested.thenToken
				firstClause.block = nested.thenBlock
				firstClause.span = TSourceSpan.Create(firstClause.elseIfToken.span.start, firstClause.block.span.EndOffset() - firstClause.elseIfToken.span.start)
				node.elseIfClauses = New TElseIfClauseSyntax[nested.elseIfClauses.length + 1]
				node.elseIfClauses[0] = firstClause
				For Local clauseIndex:Int = 0 Until nested.elseIfClauses.length
					node.elseIfClauses[clauseIndex + 1] = nested.elseIfClauses[clauseIndex]
				Next
				node.elseClause = nested.elseClause
				Return
			End If
			Local clause:TElseClauseSyntax = New TElseClauseSyntax
			clause.kind = SYNTAX_ELSE_CLAUSE
			clause.elseToken = values[elseIndex]
			clause.block = BlockWithInlineTokens(values[elseIndex + 1..], clause.elseToken.span.EndOffset())
			Local endOffset:Int = clause.block.span.EndOffset()
			clause.span = TSourceSpan.Create(clause.elseToken.span.start, endOffset - clause.elseToken.span.start)
			node.elseClause = clause
		End If
	End Method

	Method BlockWithInlineTokens:TBlockSyntax(values:TSyntaxToken[], fallback:Int)
		If values.length Then
			' Parse the complete branch as a bounded token stream so a compact
			' control statement retains its semicolon-delimited body and
			' terminator. Splitting every semicolon first would turn
			' `For ...; statement; Next` into three unrelated statements.
			Local inlineParser:TBlitzMaxSyntaxParser = New TBlitzMaxSyntaxParser
			Local endOffset:Int = values[values.length - 1].span.EndOffset()
			inlineParser.tokens = values + [TSyntaxToken.Create(TOKEN_EOF, TSourceSpan.Create(endOffset, 0), "")]
			inlineParser.sourceMode = sourceMode
			Local parsed:TSyntaxParseResult = inlineParser.ParseCompilationUnit()
			For Local diagnostic:TDiagnostic = EachIn parsed.diagnostics
				diagnostics.AddLast(diagnostic)
			Next
			If parsed.root.members.length Then
				Local block:TBlockSyntax = New TBlockSyntax
				block.kind = SYNTAX_BLOCK
				block.statements = parsed.root.members
				block.span = TSourceSpan.Create(block.statements[0].span.start, block.statements[block.statements.length - 1].span.EndOffset() - block.statements[0].span.start)
				Return block
			End If
		End If
		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = New TSyntaxNode[0]
		block.span = TSourceSpan.Create(fallback, 0)
		Return block
	End Method

	' Case clauses conventionally permit compact forms such as
	' "Case value Local n:Int Return n" without semicolons. Once a declaration
	' has started, a top-level flow keyword is an unambiguous next statement;
	' retain both statements instead of absorbing Return into the type spelling.
	Method BlockWithCompactInlineTokens:TBlockSyntax(values:TSyntaxToken[], fallback:Int)
		' A compact If owns its Return/Throw/Exit/Continue tokens.  Let the
		' bounded parser split its branches before applying the Case shorthand
		' rule below, otherwise `If condition Return value Else Return other`
		' is incorrectly divided at the first Return.
		If values.length And TextEquals(values[0].text, "if") Then Return BlockWithInlineTokens(values, fallback)
		Local statements:TList = New TList
		Local start:Int
		Local parens:Int
		Local brackets:Int
		For Local index:Int = 0 To values.length
			Local split:Int = index = values.length
			If Not split Then
				Select values[index].text
					Case "(" parens :+ 1
					Case ")" parens :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
				End Select
				If parens = 0 And brackets = 0 Then
					If values[index].text = ";" Then
						split = True
					Else If index > start And IsCompactFlowStatementStart(values[index]) Then
						split = True
					End If
				End If
			End If
			If split Then
				If index > start Then statements.AddLast(CreateInlineStatement(values[start..index]))
				If index < values.length And values[index].text = ";" Then
					start = index + 1
				Else
					start = index
				End If
			End If
		Next
		If Not statements.Count() Then Return BlockWithInlineTokens(values, fallback)
		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = NodesToArray(statements)
		block.span = TSourceSpan.Create(block.statements[0].span.start, block.statements[block.statements.length - 1].span.EndOffset() - block.statements[0].span.start)
		Return block
	End Method

	Function IsCompactFlowStatementStart:Int(token:TSyntaxToken)
		If Not token Then Return False
		Select token.text.ToLower()
			Case "return", "yield", "throw", "exit", "continue"
				Return True
		End Select
		Return False
	End Function

	' The first semicolon ends ParseIfStatement's initial header collection, but
	' subsequent statements on that physical line still belong to the single-line
	' If branch. Preserve their separators so BlockWithInlineTokens can split them.
	Method CollectInlineLineTokens:TSyntaxToken[](initial:TSyntaxToken[])
		Local result:TList = New TList
		For Local token:TSyntaxToken = EachIn initial
			result.AddLast(token)
		Next
		While Current().kind <> TOKEN_EOF And Current().kind <> TOKEN_NEWLINE
			result.AddLast(Current())
			Advance()
		Wend
		Return TokensFromList(result)
	End Method

	Function FindInlineElse:Int(values:TSyntaxToken[])
		Local parens:Int
		Local brackets:Int
		For Local index:Int = 0 Until values.length
			Select values[index].text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
			If parens = 0 And brackets = 0 And (TextEquals(values[index].text, "else") Or TextEquals(values[index].text, "elseif")) Then Return index
		Next
		Return -1
	End Function

	Method BlockWithSingleStatement:TBlockSyntax(statement:TSyntaxNode)
		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = [statement]
		block.span = statement.span
		Return block
	End Method

	Method BlockWithLeadingStatement:TBlockSyntax(block:TBlockSyntax, statement:TSyntaxNode)
		Local result:TBlockSyntax = New TBlockSyntax
		result.kind = SYNTAX_BLOCK
		result.statements = New TSyntaxNode[block.statements.length + 1]
		result.statements[0] = statement
		For Local index:Int = 0 Until block.statements.length
			result.statements[index + 1] = block.statements[index]
		Next
		Local endOffset:Int = statement.span.EndOffset()
		If block.statements.length Then endOffset = block.span.EndOffset()
		result.span = TSourceSpan.Create(statement.span.start, endOffset - statement.span.start)
		Return result
	End Method

	Method BlockWithLeadingStatements:TBlockSyntax(block:TBlockSyntax, leading:TBlockSyntax)
		If Not leading Or Not leading.statements.length Then Return block
		Local result:TBlockSyntax = New TBlockSyntax
		result.kind = SYNTAX_BLOCK
		result.statements = leading.statements + block.statements
		Local endOffset:Int = leading.span.EndOffset()
		If block And block.statements.length Then endOffset = block.span.EndOffset()
		result.span = TSourceSpan.Create(leading.span.start, endOffset - leading.span.start)
		Return result
	End Method

	Method ParseRoutineDeclaration:TRoutineDeclarationSyntax()
		Local node:TRoutineDeclarationSyntax = New TRoutineDeclarationSyntax
		node.kind = SYNTAX_ROUTINE_DECLARATION
		node.declarationToken = Current()
		node.isMethod = TextEquals(Current().text, "method")
		Local expected:String = Current().text.ToLower()
		Local start:Int = Current().span.start
		Advance()

		Local lineTokens:TSyntaxToken[] = TokensFromList(CollectUntilSeparator())
		Local inlineTerminatorStart:Int = FindInlineRoutineTerminator(lineTokens, expected)
		Local inlineBodyStart:Int = -1
		If inlineTerminatorStart >= 0 Then inlineBodyStart = FindInlineRoutineBodyStart(lineTokens, inlineTerminatorStart)
		If inlineBodyStart >= 0 Then node.headerTokens = lineTokens[..inlineBodyStart] Else node.headerTokens = lineTokens
		node.signature = TBlitzMaxSignatureParser.Parse(node.headerTokens, diagnostics)
		If node.signature And node.signature.nameToken And IsNameToken(node.signature.nameToken) Then
			node.nameToken = node.signature.nameToken
		Else
			AddDiagnostic("BMX2000", "Expected a routine name.", Current().span)
		End If
		SkipSeparators()
		Local interfaceDefault:Int = interfaceDepth > 0 And node.signature And ContainsToken(node.signature.modifierTokens, "default")
		If node.signature And (ContainsToken(node.signature.modifierTokens, "abstract") Or StartsWithToken(node.signature.modifierTokens, "=") Or (interfaceDepth > 0 And Not interfaceDefault) Or externDepth > 0) Then
			If interfaceDepth > 0 And TextEquals(Current().text, "return") Then
				AddDiagnostic("BMX2332", "Interface method declarations cannot contain a body.", Current().span)
			End If
			node.body = EmptyBlockAt(node.headerTokens[node.headerTokens.length - 1].span.EndOffset())
			node.span = TSourceSpan.Create(start, node.body.span.start - start)
			Return node
		End If
		If conditionalDepth > 0 And ConditionalRoutineHasSharedTail(expected, node.nameToken) Then
			node.body = ParseBoundaryBlock(BOUNDARY_CONDITIONAL)
			If conditionalRoutineHeaders Then conditionalRoutineHeaders.AddLast(node)
			node.span = TSourceSpan.Create(start, node.body.span.start - start)
			Return node
		End If
		If inlineBodyStart >= 0 Then
			node.body = EmptyBlockAt(lineTokens[inlineTerminatorStart].span.start)
			If inlineBodyStart < inlineTerminatorStart Then node.body = BlockWithLeadingStatement(node.body, CreateInlineStatement(lineTokens[inlineBodyStart..inlineTerminatorStart]))
			node.terminator = CreateInlineRoutineTerminator(lineTokens[inlineTerminatorStart..], expected)
			Local inlineEndOffset:Int = node.terminator.span.EndOffset()
			node.span = TSourceSpan.Create(start, inlineEndOffset - start)
			Return node
		End If

		Local parsed:TParsedBlock = ParseBlock(expected)
		node.body = parsed.block
		node.terminator = parsed.terminator
		Local endOffset:Int = node.body.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ConditionalRoutineHasSharedTail:Int(expected:String, nameToken:TSyntaxToken)
		Local nestedConditional:Int
		For Local index:Int = position Until tokens.length
			Local token:TSyntaxToken = tokens[index]
			Local lower:String = token.text.ToLower()
			If token.kind = TOKEN_DIRECTIVE Then
				If nestedConditional Then
					If IsBareDirective(token) Then nestedConditional = False
					Continue
				End If
				If IsBareDirective(token) Then Return True
				Local nextIndex:Int = index + 1
				While nextIndex < tokens.length And (tokens[nextIndex].kind = TOKEN_NEWLINE Or tokens[nextIndex].text = ";")
					nextIndex :+ 1
				Wend
				If nextIndex < tokens.length And (TextEquals(tokens[nextIndex].text, "method") Or TextEquals(tokens[nextIndex].text, "function")) Then
					Local candidateNameIndex:Int = nextIndex + 1
					If candidateNameIndex < tokens.length And nameToken And TextEquals(tokens[candidateNameIndex].text, nameToken.text) Then Return True
				End If
				If conditionalRoutineHeaders And conditionalRoutineHeaders.Count() And HasRoutineTerminatorBeforeNextDirective(nextIndex, expected) Then Return True
				' A different directive inside the routine body owns its own
				' closing bare '?'; ignore that nested region while looking for
				' this routine's actual terminator.
				nestedConditional = True
				Continue
			End If
			If lower = "end" And index + 1 < tokens.length And tokens[index + 1].text.ToLower() = expected Then Return False
			If lower = "end" + expected Then Return False
		Next
		Return False
	End Method

	Function BlockWithTrailingStatements:TBlockSyntax(prefix:TBlockSyntax, suffix:TBlockSyntax)
		If Not prefix Or Not prefix.statements.length Then Return suffix
		If Not suffix Or Not suffix.statements.length Then Return prefix
		Local result:TBlockSyntax = New TBlockSyntax
		result.kind = SYNTAX_BLOCK
		result.statements = prefix.statements + suffix.statements
		result.span = TSourceSpan.Create(prefix.span.start, suffix.span.EndOffset() - prefix.span.start)
		Return result
	End Function

	Function ExtractConditionalElseToken:TSyntaxToken(region:TConditionalRegionSyntax)
		If Not region Or Not region.branches.length Then Return Null
		Local elseToken:TSyntaxToken
		' Validate every non-empty branch before mutating any of them. A region
		' which mixes then-body statements with conditional Else clauses cannot
		' be represented by this source-preserving rewrite.
		For Local branch:TConditionalBranchSyntax = EachIn region.branches
			If Not branch.body Or Not branch.body.statements.length Then Continue
			Local raw:TRawStatementSyntax = TRawStatementSyntax(branch.body.statements[0])
			If Not raw Or raw.tokens.length <> 1 Or Not TextEquals(raw.tokens[0].text, "else") Then Return Null
			If Not elseToken Then elseToken = raw.tokens[0]
		Next
		If Not elseToken Then Return Null
		For Local branch:TConditionalBranchSyntax = EachIn region.branches
			If Not branch.body Or Not branch.body.statements.length Then Continue
			branch.body = BlockWithoutFirstStatement(branch.body)
		Next
		Return elseToken
	End Function

	Function BlockWithoutFirstStatement:TBlockSyntax(block:TBlockSyntax)
		If Not block Or block.statements.length <= 1 Then
			If block And block.statements.length Then Return EmptyBlockAt(block.statements[0].span.EndOffset())
			Return EmptyBlockAt(0)
		End If
		Local result:TBlockSyntax = New TBlockSyntax
		result.kind = SYNTAX_BLOCK
		result.statements = block.statements[1..]
		result.span = TSourceSpan.Create(result.statements[0].span.start, result.statements[result.statements.length - 1].span.EndOffset() - result.statements[0].span.start)
		Return result
	End Function

	Function BlockWithoutLastStatement:TBlockSyntax(block:TBlockSyntax)
		If Not block Or block.statements.length <= 1 Then
			If block Then Return EmptyBlockAt(block.span.start)
			Return EmptyBlockAt(0)
		End If
		Local result:TBlockSyntax = New TBlockSyntax
		result.kind = SYNTAX_BLOCK
		result.statements = block.statements[..block.statements.length - 1]
		result.span = TSourceSpan.Create(block.span.start, result.statements[result.statements.length - 1].span.EndOffset() - block.span.start)
		Return result
	End Function

	Function FindInlineRoutineTerminator:Int(values:TSyntaxToken[], expected:String)
		For Local index:Int = values.length - 1 To 0 Step -1
			Local lower:String = values[index].text.ToLower()
			If lower = "end" + expected And index = values.length - 1 Then Return index
			If lower = "end" And index + 1 = values.length - 1 And values[index + 1].text.ToLower() = expected Then Return index
		Next
		Return -1
	End Function

	Function FindInlineRoutineBodyStart:Int(values:TSyntaxToken[], terminatorStart:Int)
		Local openIndex:Int = TBlitzMaxSignatureParser.FindToken(values, "(", 0)
		If openIndex < 0 Then Return -1
		Local closeIndex:Int = TBlitzMaxSignatureParser.FindMatchingParen(values, openIndex)
		If closeIndex < 0 Or closeIndex >= terminatorStart Then Return -1
		Local cursor:Int = closeIndex + 1
		If cursor < terminatorStart And TextEquals(values[cursor].text, "where") Then Return -1
		While cursor < terminatorStart
			Local lower:String = values[cursor].text.ToLower()
			If lower = "abstract" Or lower = "final" Or lower = "override" Or lower = "export" Or lower = "inline" Or lower = "nodebug" Or lower = "stdcall" Then
				cursor :+ 1
				Continue
			End If
			If values[cursor].text = "{" Then
				Local closeMetadata:Int = TBlitzMaxTypeParser.FindMatching(values, cursor, "{", "}")
				If closeMetadata < 0 Or closeMetadata >= terminatorStart Then Return -1
				cursor = closeMetadata + 1
				Continue
			End If
			If values[cursor].text = "=" Then Return -1
			Exit
		Wend
		Return cursor
	End Function

	Function CreateInlineRoutineTerminator:TBlockTerminatorSyntax(values:TSyntaxToken[], expected:String)
		Local node:TBlockTerminatorSyntax = New TBlockTerminatorSyntax
		node.kind = SYNTAX_BLOCK_TERMINATOR
		node.expectedBlockKind = expected
		node.endToken = values[0]
		Local lower:String = values[0].text.ToLower()
		If lower.StartsWith("end") And lower <> "end" Then
			node.actualBlockKind = lower[3..]
		Else If values.length > 1 Then
			node.blockToken = values[1]
			node.actualBlockKind = values[1].text.ToLower()
		End If
		Local endOffset:Int = node.endToken.span.EndOffset()
		If node.blockToken Then endOffset = node.blockToken.span.EndOffset()
		node.span = TSourceSpan.Create(node.endToken.span.start, endOffset - node.endToken.span.start)
		Return node
	End Function

	Method ParseTypeDeclaration:TTypeDeclarationSyntax()
		Local node:TTypeDeclarationSyntax = New TTypeDeclarationSyntax
		node.kind = SYNTAX_TYPE_DECLARATION
		node.declarationToken = Current()
		Local expected:String = Current().text.ToLower()
		Local start:Int = Current().span.start
		Advance()

		Local header:TList = CollectUntilSeparator()
		node.headerTokens = TokensFromList(header)
		node.header = TTypeDeclarationHeaderParser.Parse(node.headerTokens)
		If node.headerTokens.length And IsNameToken(node.headerTokens[0]) Then
			node.nameToken = node.headerTokens[0]
		Else
			AddDiagnostic("BMX2003", "Expected a type name.", Current().span)
		End If
		SkipSeparators()

		typeDepth :+ 1
		If expected = "interface" Then interfaceDepth :+ 1
		Local parsed:TParsedBlock = ParseBlock(expected)
		If expected = "interface" Then interfaceDepth :- 1
		typeDepth :- 1
		node.body = parsed.block
		node.terminator = parsed.terminator
		Local endOffset:Int = node.body.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseBlock:TParsedBlock(expected:String)
		Local statements:TList = New TList
		Local start:Int = Current().span.start
		Local terminator:TBlockTerminatorSyntax

		While Current().kind <> TOKEN_EOF
			If IsBlockTerminator() Then
				terminator = ParseBlockTerminator(expected)
				Exit
			End If
			Local member:TSyntaxNode = ParseMember()
			statements.AddLast(member)
			Local closingRegion:TConditionalRegionSyntax = TConditionalRegionSyntax(member)
			If closingRegion And closingRegion.sharedControlTerminator And TextEquals(closingRegion.sharedControlTerminator.actualBlockKind, expected) Then
				terminator = closingRegion.sharedControlTerminator
				closedBoundary = 0
				If closingRegion.trailingRegion Then pendingMembers.AddLast(closingRegion.trailingRegion)
				Exit
			End If
			SkipSeparators()
		Wend

		If Not terminator Then
			AddDiagnostic("BMX2001", "Expected 'End " + Capitalize(expected) + "' before end of file.", Current().span)
		End If

		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = NodesToArray(statements)
		Local endOffset:Int = Current().span.start
		If terminator Then endOffset = terminator.span.start
		If block.statements.length Then endOffset = block.statements[block.statements.length - 1].span.EndOffset()
		block.span = TSourceSpan.Create(start, Max(0, endOffset - start))

		Local parsed:TParsedBlock = New TParsedBlock
		parsed.block = block
		parsed.terminator = terminator
		Return parsed
	End Method

	Method ParseBlockTerminator:TBlockTerminatorSyntax(expected:String)
		Local node:TBlockTerminatorSyntax = New TBlockTerminatorSyntax
		node.kind = SYNTAX_BLOCK_TERMINATOR
		node.expectedBlockKind = expected
		Local start:Int = Current().span.start

		Local lower:String = Current().text.ToLower()
		If lower.StartsWith("end") And lower <> "end" Then
			node.endToken = Current()
			node.actualBlockKind = lower[3..]
			Advance()
		Else
			node.endToken = Current()
			Advance()
			If Current().kind <> TOKEN_EOF And Current().kind <> TOKEN_NEWLINE Then
				node.blockToken = Current()
				node.actualBlockKind = Current().text.ToLower()
				Advance()
			End If
		End If

		Local endOffset:Int = node.endToken.span.EndOffset()
		If node.blockToken Then endOffset = node.blockToken.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)

		If node.actualBlockKind <> expected Then
			AddDiagnostic("BMX2002", "Expected 'End " + Capitalize(expected) + "' but found '" + TerminatorText(node) + "'.", node.span)
		End If
		Return node
	End Method

	Method ParseSimpleStatement:TSyntaxNode()
		Local statementTokens:TList = CollectUntilSeparator()
		Local values:TSyntaxToken[] = TokensFromList(statementTokens)
		If values.length = 0 Then
			' Defensive progress for malformed input.
			Local raw:TRawStatementSyntax = New TRawStatementSyntax
			raw.kind = SYNTAX_RAW_STATEMENT
			raw.tokens = values
			raw.span = TSourceSpan.Create(Current().span.start, 0)
			Advance()
			Return raw
		End If

		Local span:TSourceSpan = SpanOfTokens(values)
		Local firstText:String = values[0].text.ToLower()
		If firstText = "import" Or firstText = "framework" Then
			Return ParseImportDirective(values, span)
		End If
		If firstText = "include" Then
			Return ParseIncludeDirective(values, span)
		End If
		If IsVariableDeclarationStatement(values) Then
			Return ParseVariableDeclaration(values, span)
		End If

		Local flowStatement:TSyntaxNode = ParseFlowStatement(values, span)
		If flowStatement Then Return flowStatement
		Local dataStatement:TSyntaxNode = ParseDataStatement(values, span)
		If dataStatement Then Return dataStatement

		If values.length = 1 And values[0].kind = TOKEN_KEYWORD And TextEquals(values[0].text, "end") Then
			Local endStatement:TEndStatementSyntax = New TEndStatementSyntax
			endStatement.kind = SYNTAX_END_STATEMENT
			endStatement.endToken = values[0]
			endStatement.span = span
			Return endStatement
		End If

		Local assignmentIndex:Int = FindAssignmentOperator(values)
		If assignmentIndex > 0 And IsCommandCallBeforeAssignment(values, assignmentIndex) Then
			Return CreateCallStatement(values, span)
		End If
		If assignmentIndex > 0 And IsAssignmentTargetStart(values[0]) Then
			Local assignment:TAssignmentStatementSyntax = New TAssignmentStatementSyntax
			assignment.kind = SYNTAX_ASSIGNMENT_STATEMENT
			assignment.span = span
			assignment.operatorToken = values[assignmentIndex]
			If assignment.operatorToken.text = ":=" Then AddDiagnostic("BMX2053", "The ':=' syntax is only valid in an inferred Local declaration; use '=' for assignment.", assignment.operatorToken.span)
			assignment.left = TBlitzMaxExpressionParser.Parse(values[..assignmentIndex], diagnostics)
			assignment.right = TBlitzMaxExpressionParser.Parse(values[assignmentIndex + 1..], diagnostics)
			Return assignment
		End If

		If IsCallStatement(values) Then
			Return CreateCallStatement(values, span)
		End If

		Local raw:TRawStatementSyntax = New TRawStatementSyntax
		raw.kind = SYNTAX_RAW_STATEMENT
		raw.tokens = values
		raw.span = span
		Return raw
	End Method

	Method ParseImportDirective:TImportDirectiveSyntax(values:TSyntaxToken[], span:TSourceSpan)
		Local node:TImportDirectiveSyntax = New TImportDirectiveSyntax
		node.kind = SYNTAX_IMPORT_DIRECTIVE
		node.span = span
		node.importToken = values[0]
		node.isFramework = TextEquals(values[0].text, "framework")
		If values.length < 2 Then
			AddDiagnostic("BMX2440", "Expected a module name or file path after '" + values[0].text + "'.", values[0].span)
			Return node
		End If
		node.targetTokens = values[1..]
		node.isFileImport = values[1].kind = TOKEN_STRING_LITERAL
		If node.isFileImport Then
			node.targetText = StringLiteralValue(values[1].text)
			node.isSourceImport = node.targetText.ToLower().EndsWith(".bmx")
			node.isNativeImport = Not node.isSourceImport
			If values.length > 2 Then AddDiagnostic("BMX2441", "Unexpected token '" + values[2].text + "' after import file path.", values[2].span)
		Else
			For Local token:TSyntaxToken = EachIn node.targetTokens
				node.targetText :+ token.text
			Next
		End If
		Return node
	End Method

	Method ParseIncludeDirective:TIncludeDirectiveSyntax(values:TSyntaxToken[], span:TSourceSpan)
		Local node:TIncludeDirectiveSyntax = New TIncludeDirectiveSyntax
		node.kind = SYNTAX_INCLUDE_DIRECTIVE
		node.span = span
		node.includeToken = values[0]
		If values.length < 2 Or values[1].kind <> TOKEN_STRING_LITERAL Then
			AddDiagnostic("BMX2442", "Expected a quoted source path after 'Include'.", values[0].span)
			Return node
		End If
		node.pathToken = values[1]
		node.pathText = StringLiteralValue(values[1].text)
		If values.length > 2 Then AddDiagnostic("BMX2443", "Unexpected token '" + values[2].text + "' after include path.", values[2].span)
		Return node
	End Method

	Function StringLiteralValue:String(text:String)
		If text.length >= 2 And text.StartsWith(Chr(34)) And text.EndsWith(Chr(34)) Then Return text[1..text.length - 1]
		Return text
	End Function

	Method ParseFlowStatement:TSyntaxNode(values:TSyntaxToken[], span:TSourceSpan)
		If values.length = 0 Then Return Null
		Local lower:String = values[0].text.ToLower()
		Select lower
			Case "yield"
				Local node:TYieldStatementSyntax = New TYieldStatementSyntax
				node.kind = SYNTAX_YIELD_STATEMENT
				node.span = span
				node.yieldToken = values[0]
				Local expressionStart:Int = 1
				If values.length > 1 And values[1].text.ToLower() = "from" Then
					node.fromToken = values[1]
					expressionStart = 2
				End If
				If values.length > expressionStart Then
					node.expression = TBlitzMaxExpressionParser.Parse(values[expressionStart..], diagnostics)
				Else If node.fromToken Then
					AddDiagnostic("BMX2328", "Expected an expression after 'Yield From'.", node.fromToken.span)
				Else
					AddDiagnostic("BMX2324", "Expected an expression after 'Yield'.", node.yieldToken.span)
				End If
				Return node
			Case "return"
				Local node:TReturnStatementSyntax = New TReturnStatementSyntax
				node.kind = SYNTAX_RETURN_STATEMENT
				node.span = span
				node.returnToken = values[0]
				If values.length > 1 Then node.expression = TBlitzMaxExpressionParser.Parse(values[1..], diagnostics)
				Return node
			Case "throw"
				Local node:TThrowStatementSyntax = New TThrowStatementSyntax
				node.kind = SYNTAX_THROW_STATEMENT
				node.span = span
				node.throwToken = values[0]
				If values.length > 1 Then node.expression = TBlitzMaxExpressionParser.Parse(values[1..], diagnostics) Else AddDiagnostic("BMX2320", "Expected an expression after 'Throw'.", node.throwToken.span)
				Return node
			Case "exit"
				Local node:TExitStatementSyntax = New TExitStatementSyntax
				node.kind = SYNTAX_EXIT_STATEMENT
				node.span = span
				node.exitToken = values[0]
				If values.length > 1 Then node.label = TBlitzMaxExpressionParser.Parse(values[1..], diagnostics)
				Return node
			Case "continue"
				Local node:TContinueStatementSyntax = New TContinueStatementSyntax
				node.kind = SYNTAX_CONTINUE_STATEMENT
				node.span = span
				node.continueToken = values[0]
				If values.length > 1 Then node.label = TBlitzMaxExpressionParser.Parse(values[1..], diagnostics)
				Return node
			Case "assert"
				Return ParseAssertStatement(values, span)
			Case "release"
				Local node:TReleaseStatementSyntax = New TReleaseStatementSyntax
				node.kind = SYNTAX_RELEASE_STATEMENT
				node.span = span
				node.releaseToken = values[0]
				If values.length > 1 Then node.expression = TBlitzMaxExpressionParser.Parse(values[1..], diagnostics) Else AddDiagnostic("BMX2323", "Expected an integer variable after 'Release'.", node.releaseToken.span)
				Return node
		End Select
		Return Null
	End Method

	Method ParseDataStatement:TSyntaxNode(values:TSyntaxToken[], span:TSourceSpan)
		If values.length = 0 Then Return Null
		Select values[0].text.ToLower()
			Case "defdata"
				Local node:TDefDataStatementSyntax = New TDefDataStatementSyntax
				node.kind = SYNTAX_DEFDATA_STATEMENT
				node.span = span
				node.defDataToken = values[0]
				node.values = ParseDataExpressionSlots(values, 1)
				If node.values.length = 0 Then AddDiagnostic("BMX2330", "DefData requires at least one value.", node.defDataToken.span)
				Return node
			Case "readdata"
				Local node:TReadDataStatementSyntax = New TReadDataStatementSyntax
				node.kind = SYNTAX_READDATA_STATEMENT
				node.span = span
				node.readDataToken = values[0]
				node.targets = ParseDataExpressionSlots(values, 1)
				Return node
			Case "restoredata"
				Local node:TRestoreDataStatementSyntax = New TRestoreDataStatementSyntax
				node.kind = SYNTAX_RESTOREDATA_STATEMENT
				node.span = span
				node.restoreDataToken = values[0]
				If values.length > 1 Then node.label = TBlitzMaxExpressionParser.Parse(values[1..], diagnostics) Else AddDiagnostic("BMX2331", "RestoreData requires a data label.", node.restoreDataToken.span)
				Return node
		End Select
		Return Null
	End Method

	Method ParseDataExpressionSlots:TExpressionSyntax[](values:TSyntaxToken[], start:Int)
		Local slots:TList = New TList
		If start >= values.length Then Return New TExpressionSyntax[0]
		Local itemStart:Int = start
		Local parens:Int
		Local brackets:Int
		For Local index:Int = start To values.length
			Local split:Int = index = values.length
			If Not split Then
				Select values[index].text
					Case "(" parens :+ 1
					Case ")" parens :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
				End Select
				If values[index].text = "," And parens = 0 And brackets = 0 Then split = True
			End If
			If split Then
				Local slot:TExpressionSlot = New TExpressionSlot
				If index > itemStart Then slot.expression = TBlitzMaxExpressionParser.Parse(values[itemStart..index], diagnostics)
				slots.AddLast(slot)
				itemStart = index + 1
			End If
		Next
		Local result:TExpressionSyntax[] = New TExpressionSyntax[slots.Count()]
		Local resultIndex:Int
		For Local slot:TExpressionSlot = EachIn slots
			result[resultIndex] = slot.expression
			resultIndex :+ 1
		Next
		Return result
	End Method

	Method ParseAssertStatement:TAssertStatementSyntax(values:TSyntaxToken[], span:TSourceSpan)
		Local node:TAssertStatementSyntax = New TAssertStatementSyntax
		node.kind = SYNTAX_ASSERT_STATEMENT
		node.span = span
		node.assertToken = values[0]
		Local separatorIndex:Int = FindAssertSeparator(values)
		Local conditionEnd:Int = values.length
		If separatorIndex >= 0 Then conditionEnd = separatorIndex
		If conditionEnd > 1 Then
			node.condition = TBlitzMaxExpressionParser.Parse(values[1..conditionEnd], diagnostics)
		Else
			AddDiagnostic("BMX2321", "Expected a condition after 'Assert'.", node.assertToken.span)
		End If
		If separatorIndex >= 0 Then
			node.separatorToken = values[separatorIndex]
			If separatorIndex + 1 < values.length Then node.message = TBlitzMaxExpressionParser.Parse(values[separatorIndex + 1..], diagnostics) Else AddDiagnostic("BMX2322", "Expected a message after '" + node.separatorToken.text + "'.", node.separatorToken.span)
		End If
		Return node
	End Method

	Method IsCallStatement:Int(values:TSyntaxToken[])
		If values.length = 0 Then Return False
		' A leading dot explicitly selects a compilation-unit routine.  It is
		' valid in both parenthesized and command-call forms, including compact
		' single-line If branches such as `If ready Then .Flip 1`.
		If values[0].text = "." Then
			If values.length < 2 Or Not IsNameToken(values[1]) Then Return False
			Local scopedCalleeEnd:Int = CalleeEnd(values)
			If scopedCalleeEnd < values.length And IsAssignmentOperator(values[scopedCalleeEnd].text.ToLower()) Then Return False
			Return True
		End If
		' A statement may invoke a member on any expression, including a
		' parenthesized operator result: `(root / "sub").CreateDir(True)`.
		' Command-style calls still require a name-like prefix below.
		If values[0].text = "(" Then
			Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(values, New TList)
			Return parsed.consumed = values.length And TCallExpressionSyntax(parsed.expression) <> Null
		End If
		If values[0].kind <> TOKEN_IDENTIFIER Then
			Local receiverKeyword:String = values[0].text.ToLower()
			If values[0].kind <> TOKEN_KEYWORD Or (receiverKeyword <> "self" And receiverKeyword <> "super" And receiverKeyword <> "new" And receiverKeyword <> "field") Then Return False
		End If
		Local calleeEnd:Int = CalleeEnd(values)
		If calleeEnd < values.length And IsAssignmentOperator(values[calleeEnd].text.ToLower()) Then Return False
		Return True
	End Method

	Method IsCommandCallBeforeAssignment:Int(values:TSyntaxToken[], assignmentIndex:Int)
		If assignmentIndex <= 0 Then Return False
		' Equality is both the assignment operator and an expression operator.
		' In a command-style call such as `canvas.SetMask i=0,i=1`, a complete
		' callee and the first argument precede the first equality token.  An
		' ordinary assignment target consumes every token before that operator.
		Local calleeEnd:Int = CalleeEnd(values)
		Return calleeEnd > 0 And calleeEnd < assignmentIndex
	End Method

	Method CreateCallStatement:TCallStatementSyntax(values:TSyntaxToken[], span:TSourceSpan)
		Local node:TCallStatementSyntax = New TCallStatementSyntax
		node.kind = SYNTAX_CALL_STATEMENT
		node.tokens = values
		node.span = span
		Local calleeEnd:Int = CalleeEnd(values)
		node.calleeTokens = values[..calleeEnd]
		node.argumentTokens = values[calleeEnd..]
		node.hasParentheses = IsCompleteParenthesizedCall(values, calleeEnd)
		If node.hasParentheses Then
			node.expression = TBlitzMaxExpressionParser.Parse(values, diagnostics)
		Else
			node.expression = TBlitzMaxExpressionParser.Parse(values[..calleeEnd], diagnostics)
			If calleeEnd < values.length Then
				node.argumentExpressions = ParseStatementArguments(values[calleeEnd..])
			Else
				node.argumentExpressions = New TExpressionSyntax[0]
			End If
		End If
		Return node
	End Method

	Method ParseStatementArguments:TExpressionSyntax[](values:TSyntaxToken[])
		Local result:TList = New TList
		Local start:Int
		Local parens:Int
		Local brackets:Int
		For Local index:Int = 0 To values.length
			Local split:Int = index = values.length
			If Not split Then
				Select values[index].text
					Case "(" parens :+ 1
					Case ")" parens :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
				End Select
				If values[index].text = "," And parens = 0 And brackets = 0 Then split = True
			End If
			If split Then
				If index > start Then
					result.AddLast(TBlitzMaxExpressionParser.Parse(values[start..index], diagnostics))
				Else
					Local offset:Int
					If index < values.length Then offset = values[index].span.start Else If values.length Then offset = values[values.length - 1].span.EndOffset()
					result.AddLast(TBlitzMaxExpressionParser.OmittedArgumentAt(offset))
				End If
				start = index + 1
			End If
		Next
		Return ExpressionsToArray(result)
	End Method

	Method ParseVariableDeclaration:TVariableDeclarationStatementSyntax(values:TSyntaxToken[], span:TSourceSpan)
		Local node:TVariableDeclarationStatementSyntax = New TVariableDeclarationStatementSyntax
		node.kind = SYNTAX_VARIABLE_DECLARATION_STATEMENT
		node.span = span
		node.declarationToken = values[0]
		node.modifierTokens = New TSyntaxToken[0]
		Local declaratorList:TList = New TList
		Local start:Int = 1
		Local isStaticArray:Int
		While start < values.length
			Local modifier:String = values[start].text.ToLower()
			If modifier = "readonly" And node.declarationToken.text.ToLower() = "field" Then
				node.modifierTokens :+ [values[start]]
				start :+ 1
			Else If modifier = "staticarray" Then
				node.staticArrayToken = values[start]
				node.modifierTokens :+ [values[start]]
				isStaticArray = True
				start :+ 1
			Else
				Exit
			End If
		Wend
		Local parens:Int
		Local brackets:Int
		Local angles:Int
		Local seenAssignment:Int

		For Local index:Int = start To values.length
			Local split:Int = index = values.length
			If Not split Then
				Select values[index].text
					Case "(" parens :+ 1
					Case ")" parens :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
					Case "<"
						' Commas in constructed types and generic calls/casts belong
						' to their angle list, not to the surrounding variable
						' declaration. Other post-assignment '<' tokens remain
						' ordinary comparison operators.
						If Not seenAssignment Or angles > 0 Or IsNewGenericTypeOpen(values, index) Or IsGenericInvocationTypeOpen(values, index) Or IsGenericTypeQualifierOpen(values, index) Or IsGenericRoutineReferenceTypeOpen(values, index) Then angles :+ 1
					Case ">"
						If angles > 0 Then angles :- 1
					Case ">="
						If angles > 0 Then
							angles :- 1
							If angles = 0 And parens = 0 And brackets = 0 Then seenAssignment = True
						End If
					Case "=", ":="
						If parens = 0 And brackets = 0 And angles = 0 Then seenAssignment = True
				End Select
				If values[index].text = "," And parens = 0 And brackets = 0 And angles = 0 Then split = True
			End If

			If split Then
				Local allowKeywordName:Int = node.declarationToken.text.ToLower() = "field"
				If index > start Then declaratorList.AddLast(ParseVariableDeclarator(values[start..index], isStaticArray, allowKeywordName))
				start = index + 1
				seenAssignment = False
			End If
		Next

		node.declarators = DeclaratorsToArray(declaratorList)
		Local inferenceCount:Int
		For Local declarator:TVariableDeclaratorSyntax = EachIn node.declarators
			If declarator.inferenceToken Then inferenceCount :+ 1
		Next
		If inferenceCount Then
			Local isLocal:Int = node.declarationToken.text.ToLower() = "local"
			Local firstInferenceToken:TSyntaxToken
			For Local declarator:TVariableDeclaratorSyntax = EachIn node.declarators
				If Not declarator.inferenceToken Then Continue
				If Not firstInferenceToken Then firstInferenceToken = declarator.inferenceToken
				If Not isLocal Then AddDiagnostic("BMX2050", "Type inference with ':=' is only valid for Local declarations.", declarator.inferenceToken.span)
			Next
			If node.declarators.length <> 1 Then AddDiagnostic("BMX2051", "An inferred Local declaration must contain exactly one declarator.", firstInferenceToken.span)
		End If
		Return node
	End Method

	Function IsNewGenericTypeOpen:Int(values:TSyntaxToken[], index:Int)
		If index < 2 Or values[index].text <> "<" Or Not IsNameToken(values[index - 1]) Then Return False
		Return TextEquals(values[index - 2].text, "new")
	End Function

	Function IsGenericInvocationTypeOpen:Int(values:TSyntaxToken[], index:Int)
		If index < 1 Or values[index].text <> "<" Or Not IsNameToken(values[index - 1]) Then Return False
		Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(values, index, "<", ">")
		Return closeIndex > index + 1 And closeIndex + 1 < values.length And values[closeIndex + 1].text = "("
	End Function

	Function IsGenericTypeQualifierOpen:Int(values:TSyntaxToken[], index:Int)
		If index < 1 Or values[index].text <> "<" Or Not IsNameToken(values[index - 1]) Then Return False
		Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(values, index, "<", ">")
		Return closeIndex > index + 1 And closeIndex + 1 < values.length And values[closeIndex + 1].text = "."
	End Function

	Function IsGenericRoutineReferenceTypeOpen:Int(values:TSyntaxToken[], index:Int)
		If index < 1 Or values[index].text <> "<" Or Not IsNameToken(values[index - 1]) Then Return False
		Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(values, index, "<", ">")
		If closeIndex <= index + 1 Then Return False
		' An explicit specialization used as a value finishes its initializer.
		' A trailing comma begins the next declarator; commas before this matching
		' close belong to nested or multi-argument type references.
		Return closeIndex = values.length - 1 Or (closeIndex + 1 < values.length And values[closeIndex + 1].text = ",")
	End Function

	Method ParseVariableDeclarator:TVariableDeclaratorSyntax(values:TSyntaxToken[], isStaticArray:Int = False, allowKeywordName:Int = False)
		values = TBlitzMaxTypeParser.SplitGenericCloseAssignment(values)
		Local node:TVariableDeclaratorSyntax = New TVariableDeclaratorSyntax
		node.kind = SYNTAX_VARIABLE_DECLARATOR
		node.span = SpanOfTokens(values)
		' Step is the one keyword that cannot subsequently begin an assignment
		' statement because it is reserved for a For range clause. Retain the
		' established contextual-keyword extension for other declarations; the
		' compiler itself uses Local field and native mappings use Field Object.
		Local keywordIsUsable:Int
		If values.length Then keywordIsUsable = IsNameToken(values[0]) And (allowKeywordName Or values[0].text.ToLower() <> "step")
		If values.length And keywordIsUsable Then
			node.nameToken = values[0]
		Else
			AddDiagnostic("BMX2004", "Expected a variable name.", node.span)
		End If

		Local metadataIndex:Int = FindTopLevelToken(values, "{", 1)
		Local valueEnd:Int = values.length
		If metadataIndex >= 0 Then
			node.metadataTokens = values[metadataIndex..]
			valueEnd = metadataIndex
		Else
			node.metadataTokens = New TSyntaxToken[0]
		End If
		Local assignmentIndex:Int = -1
		For Local index:Int = 1 Until valueEnd
			If values[index].text = "=" Or values[index].text = ":=" Then
				assignmentIndex = index
				Exit
			End If
		Next
		Local typeEnd:Int = valueEnd
		If assignmentIndex >= 0 Then typeEnd = assignmentIndex
		If typeEnd > 1 Then node.typeTokens = values[1..typeEnd] Else node.typeTokens = New TSyntaxToken[0]
		If isStaticArray Then ExtractStaticArrayBound(node)
		Local parsedType:TTypeReferenceSyntax = TBlitzMaxTypeParser.Parse(node.typeTokens)
		Local callableOpen:Int = FindTopLevelToken(node.typeTokens, "(", 0)
		If callableOpen >= 0 Then
			node.callableType = TBlitzMaxSignatureParser.ParseCallableType(node.typeTokens, diagnostics)
		Else
			node.declaredType = parsedType
			If Not isStaticArray Then node.arrayDimensions = ParseDeclaratorArrayDimensions(node.declaredType)
		End If
		If assignmentIndex >= 0 Then
			node.assignmentToken = values[assignmentIndex]
			If node.assignmentToken.text = ":=" Then node.inferenceToken = node.assignmentToken
			node.initializer = TBlitzMaxExpressionParser.Parse(values[assignmentIndex + 1..valueEnd], diagnostics)
			If node.inferenceToken And Not node.initializer Then AddDiagnostic("BMX2052", "An inferred Local declaration requires an initializer after ':='.", node.inferenceToken.span)
		End If
		Return node
	End Method

	Method ParseDeclaratorArrayDimensions:TExpressionSyntax[](declaredType:TTypeReferenceSyntax)
		If Not declaredType Or Not declaredType.suffixes.length Then Return New TExpressionSyntax[0]
		' Production BlitzMax accepts the allocated dimension on either side of
		' an otherwise empty nested-array suffix: T[][4] and T[4][] both create
		' the four-element outer array. Find the rightmost suffix which actually
		' carries a dimension instead of requiring the final suffix to do so.
		Local suffix:TTypeSuffixSyntax
		For Local suffixIndex:Int = declaredType.suffixes.length - 1 To 0 Step -1
			Local candidate:TTypeSuffixSyntax = declaredType.suffixes[suffixIndex]
			If Not candidate Or candidate.suffixKind <> TYPE_SUFFIX_ARRAY Or candidate.tokens.length < 3 Then Continue
			For Local tokenIndex:Int = 1 Until candidate.tokens.length - 1
				If candidate.tokens[tokenIndex].text <> "," Then suffix = candidate; Exit
			Next
			If suffix Then Exit
		Next
		If Not suffix Then Return New TExpressionSyntax[0]
		Local inner:TSyntaxToken[] = suffix.tokens[1..suffix.tokens.length - 1]
		For Local token:TSyntaxToken = EachIn inner
			If token.text <> "," Then
				Local expressions:TList = New TList
				Local start:Int
				Local parentheses:Int
				Local brackets:Int
				For Local index:Int = 0 To inner.length
					Local split:Int = index = inner.length
					If Not split Then
						Select inner[index].text
							Case "(" parentheses :+ 1
							Case ")" parentheses :- 1
							Case "[" brackets :+ 1
							Case "]" brackets :- 1
							Case ","
								If parentheses = 0 And brackets = 0 Then split = True
						End Select
					End If
					If split Then
						If index > start Then expressions.AddLast(TBlitzMaxExpressionParser.Parse(inner[start..index], diagnostics))
						start = index + 1
					End If
				Next
				Return ExpressionsToArray(expressions)
			End If
		Next
		Return New TExpressionSyntax[0]
	End Method

	Method ExtractStaticArrayBound(node:TVariableDeclaratorSyntax)
		Local tokens:TSyntaxToken[] = node.typeTokens
		Local closeIndex:Int = tokens.length - 1
		If closeIndex < 2 Or tokens[closeIndex].text <> "]" Then
			AddDiagnostic("BMX2015", "StaticArray declaration requires a fixed length in brackets.", node.span)
			Return
		End If
		Local openIndex:Int = closeIndex - 1
		While openIndex >= 0 And tokens[openIndex].text <> "["
			openIndex :- 1
		Wend
		If openIndex < 0 Or openIndex + 1 = closeIndex Then
			AddDiagnostic("BMX2015", "StaticArray declaration requires a fixed length expression.", node.span)
			Return
		End If
		Local bound:TStaticArrayBoundSyntax = New TStaticArrayBoundSyntax
		bound.kind = SYNTAX_STATIC_ARRAY_BOUND
		bound.openToken = tokens[openIndex]
		bound.closeToken = tokens[closeIndex]
		bound.lengthExpression = TBlitzMaxExpressionParser.Parse(tokens[openIndex + 1..closeIndex], diagnostics)
		bound.span = TSourceSpan.Create(bound.openToken.span.start, bound.closeToken.span.EndOffset() - bound.openToken.span.start)
		node.staticArrayBound = bound
		node.typeTokens = tokens[..openIndex]
	End Method

	Method ParseCaseHeader:TParsedCaseHeader(values:TSyntaxToken[])
		Local expressions:TList = New TList
		Local cursor:Int
		While cursor < values.length
			Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(values[cursor..], diagnostics)
			If parsed.consumed = 0 Or Not parsed.expression Then Exit
			expressions.AddLast(parsed.expression)
			cursor :+ parsed.consumed
			If cursor < values.length And values[cursor].text = "," Then
				cursor :+ 1
				If cursor = values.length Then AddDiagnostic("BMX2405", "Expected a Case value after ','.", values[cursor - 1].span)
				Continue
			End If
			Exit
		Wend
		If expressions.Count() = 0 Then AddDiagnostic("BMX2405", "Expected a Case value.", IfExpressionListSpan(values, cursor))
		Local result:TParsedCaseHeader = New TParsedCaseHeader
		result.values = ExpressionsToArray(expressions)
		If cursor < values.length Then result.inlineTokens = values[cursor..] Else result.inlineTokens = New TSyntaxToken[0]
		Return result
	End Method

	Method CalleeEnd:Int(values:TSyntaxToken[])
		Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(values, New TList)
		Local index:Int = parsed.consumed
		Local finalCall:TCallExpressionSyntax = LeadingInvocation(parsed.expression)
		If finalCall And finalCall.callee Then
			Local calleeOffset:Int = finalCall.callee.span.EndOffset()
			index = 0
			While index < values.length And values[index].span.start < calleeOffset
				index :+ 1
			Wend
		Else
			' In command-call position a leading member name followed by +value
			' or -value is a callee with a unary argument, not a discarded
			' binary expression. This is the production spelling used by calls
			' such as `stream.WriteLine -mode`.
			Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(parsed.expression)
			If binary And IsCommandCalleeExpression(binary.left) And (binary.operatorToken.text = "+" Or binary.operatorToken.text = "-") Then
				index = 0
				While index < values.length And values[index].span.start < binary.operatorToken.span.start
					index :+ 1
				Wend
			End If
		End If
		If index < 1 Then index = 1
		If index < values.length And values[index].text = "<" Then
			Local genericClose:Int = TBlitzMaxTypeParser.FindMatching(values, index, "<", ">")
			If genericClose > index And genericClose + 1 < values.length And values[genericClose + 1].text = "(" Then index = genericClose + 1
		End If
		Return index
	End Method

	Function IsCommandCalleeExpression:Int(expression:TExpressionSyntax)
		Return TNameExpressionSyntax(expression) <> Null Or TMemberAccessExpressionSyntax(expression) <> Null
	End Function

	Function LeadingInvocation:TCallExpressionSyntax(expression:TExpressionSyntax)
		Local call:TCallExpressionSyntax = TCallExpressionSyntax(expression)
		If call Then Return call
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
		If binary Then Return LeadingInvocation(binary.left)
		Return Null
	End Function

	Function IsCompleteParenthesizedCall:Int(values:TSyntaxToken[], calleeEnd:Int)
		If calleeEnd >= values.length Or values[calleeEnd].text <> "(" Then Return False
		Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(values, New TList)
		Return parsed.consumed = values.length And TCallExpressionSyntax(parsed.expression) <> Null
	End Function

	Method IsBlockTerminator:Int()
		If Current().kind <> TOKEN_KEYWORD Then Return False
		Local lower:String = Current().text.ToLower()
		If IsCombinedTerminator(lower) Then Return True
		If lower <> "end" Then Return False
		If Peek(1).kind = TOKEN_NEWLINE Or Peek(1).kind = TOKEN_EOF Then Return False
		Return IsBlockKind(Peek(1).text.ToLower())
	End Method

	Method CollectUntilSeparator:TList()
		Local result:TList = New TList
		Local parens:Int
		Local brackets:Int
		Local braces:Int
		While Current().kind <> TOKEN_EOF
			If result.Count() > 0 And IsFunctionLiteralStart() Then
				Local literal:TFunctionLiteralExpressionSyntax = ParseFunctionLiteralExpression()
				Local embedded:TSyntaxToken = TSyntaxToken.Create(TOKEN_EMBEDDED_EXPRESSION, literal.span, "<Function>")
				embedded.payload = literal
				result.AddLast(embedded)
				Continue
			End If
			If (Current().text = ".." Or Current().text = "_") And Peek(1).kind = TOKEN_NEWLINE Then
				Advance()
				Advance()
				Continue
			End If
			If Current().kind = TOKEN_NEWLINE Then
				If parens > 0 Or brackets > 0 Or braces > 0 Then
					Advance()
					Continue
				End If
				Exit
			End If
			If Current().kind = TOKEN_SYMBOL And Current().text = ";" Then Exit
			result.AddLast(Current())
			Select Current().text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
				Case "{" braces :+ 1
				Case "}" braces :- 1
			End Select
			Advance()
		Wend
		Return result
	End Method

	Method IsFunctionLiteralStart:Int()
		If Current().kind <> TOKEN_KEYWORD Or Not TextEquals(Current().text, "function") Then Return False
		Local nextToken:TSyntaxToken = Peek(1)
		Return nextToken.text = "(" Or TBlitzMaxTypeParser.IsTypeMarker(nextToken.text)
	End Method

	Method ParseFunctionLiteralExpression:TFunctionLiteralExpressionSyntax()
		Local node:TFunctionLiteralExpressionSyntax = New TFunctionLiteralExpressionSyntax
		node.kind = SYNTAX_FUNCTION_LITERAL_EXPRESSION
		node.functionToken = Current()
		Local start:Int = Current().span.start
		Advance()

		node.headerTokens = TokensFromList(CollectUntilSeparator())
		Local openIndex:Int = TBlitzMaxSignatureParser.FindToken(node.headerTokens, "(", 0)
		If openIndex < 0 Then
			AddDiagnostic("BMX2450", "Expected '(' in Function literal.", node.functionToken.span)
			node.parameters = New TParameterSyntax[0]
		Else
			node.openParenToken = node.headerTokens[openIndex]
			If openIndex > 0 Then node.returnType = TBlitzMaxTypeParser.Parse(node.headerTokens[..openIndex])
			Local closeIndex:Int = TBlitzMaxSignatureParser.FindMatchingParen(node.headerTokens, openIndex)
			If closeIndex < 0 Then
				closeIndex = node.headerTokens.length
				AddDiagnostic("BMX2451", "Expected ')' in Function literal.", TSourceSpan.Create(node.headerTokens[node.headerTokens.length - 1].span.EndOffset(), 0))
			Else
				node.closeParenToken = node.headerTokens[closeIndex]
			End If
			node.parameters = TBlitzMaxSignatureParser.ParseParameters(node.headerTokens[openIndex + 1..closeIndex], diagnostics)
			If closeIndex + 1 < node.headerTokens.length Then
				AddDiagnostic("BMX2452", "Unexpected token '" + node.headerTokens[closeIndex + 1].text + "' after Function literal parameters.", node.headerTokens[closeIndex + 1].span)
			End If
		End If

		SkipSeparators()
		Local parsed:TParsedBlock = ParseBlock("function")
		node.body = parsed.block
		node.terminator = parsed.terminator
		Local endOffset:Int = node.body.span.EndOffset()
		If node.terminator Then endOffset = node.terminator.span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method SkipSeparators()
		' Source pragmas are build-manager directives. Keep their lexer tokens for
		' source tooling, but give them no BlitzMax syntax or semantic meaning.
		While IsSeparator(Current()) Or Current().kind = TOKEN_PRAGMA
			Advance()
		Wend
	End Method

	Method Advance()
		If position < tokens.length - 1 Then position :+ 1
	End Method

	Method Current:TSyntaxToken()
		Return tokens[position]
	End Method

	Method Peek:TSyntaxToken(distance:Int)
		Return tokens[Min(tokens.length - 1, position + distance)]
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan)
		diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span))
	End Method

	Function IsSeparator:Int(token:TSyntaxToken)
		Return token.kind = TOKEN_NEWLINE Or (token.kind = TOKEN_SYMBOL And token.text = ";")
	End Function

	Function IsBareDirective:Int(token:TSyntaxToken)
		Return token.kind = TOKEN_DIRECTIVE And token.text.Trim() = "?"
	End Function

	Function DirectiveCondition:String(token:TSyntaxToken)
		Local text:String = token.text.Trim()
		If text.length > 1 Then Return text[1..].Trim()
		Return ""
	End Function

	Function IsNameToken:Int(token:TSyntaxToken)
		Return token.kind = TOKEN_IDENTIFIER Or token.kind = TOKEN_KEYWORD
	End Function

	Function TextEquals:Int(left:String, right:String)
		Return left.Compare(right, False) = 0
	End Function

	Function IsAssignmentOperator:Int(text:String)
		Select text
			Case "=", ":*", ":/", ":+", ":-", ":&", ":|", ":~~", ":shl", ":shr", ":sar", ":mod", ":="
				Return True
		End Select
		Return False
	End Function

	Function IsAssignmentTargetStart:Int(token:TSyntaxToken)
		If token.kind = TOKEN_IDENTIFIER Then Return True
		If token.text = "(" Then Return True
		If token.kind <> TOKEN_KEYWORD Then Return False
		Select token.text.ToLower()
			Case "self", "field", "byte", "short", "int", "uint", "long", "ulong", "size_t", "float", "double", "string", "object"
				Return True
		End Select
		Return False
	End Function

	Function FindAssignmentOperator:Int(values:TSyntaxToken[])
		Local parens:Int
		Local brackets:Int
		For Local index:Int = 0 Until values.length
			Select values[index].text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
			If index > 0 And parens = 0 And brackets = 0 And IsAssignmentOperator(values[index].text.ToLower()) Then Return index
		Next
		Return -1
	End Function

	Function IsVariableDeclarationStart:Int(token:TSyntaxToken)
		If token.kind <> TOKEN_KEYWORD Then Return False
		Select token.text.ToLower()
			Case "local", "global", "field", "const", "threadedglobal"
				Return True
		End Select
		Return False
	End Function

	Function IsVariableDeclarationStatement:Int(values:TSyntaxToken[])
		If Not values.length Or Not IsVariableDeclarationStart(values[0]) Then Return False
		' Field is legal as an ordinary local name. Once followed by member
		' access it is an expression receiver, not a Field declaration keyword.
		If TextEquals(values[0].text, "field") And values.length > 1 And values[1].text = "." Then Return False
		Return True
	End Function

	Function FindToken:Int(tokens:TSyntaxToken[], text:String)
		For Local index:Int = 0 Until tokens.length
			If TextEquals(tokens[index].text, text) Then Return index
		Next
		Return -1
	End Function

	Function FindTopLevelToken:Int(tokens:TSyntaxToken[], text:String, start:Int)
		Local parens:Int
		Local brackets:Int
		Local angles:Int
		For Local index:Int = start Until tokens.length
			If parens = 0 And brackets = 0 And angles = 0 And tokens[index].text = text Then Return index
			Select tokens[index].text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
				Case "<" angles :+ 1
				Case ">" If angles > 0 Then angles :- 1
			End Select
		Next
		Return -1
	End Function

	Function FindTopLevelForClause:Int(tokens:TSyntaxToken[], start:Int)
		Local parens:Int
		Local brackets:Int
		For Local index:Int = start Until tokens.length
			If parens = 0 And brackets = 0 And (index = 0 Or tokens[index - 1].text <> ".") Then
				If TextEquals(tokens[index].text, "eachin") Or TextEquals(tokens[index].text, "to") Or TextEquals(tokens[index].text, "until") Then Return index
			End If
			Select tokens[index].text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
		Next
		Return -1
	End Function

	Function FindTopLevelKeyword:Int(tokens:TSyntaxToken[], text:String, start:Int)
		Local parens:Int
		Local brackets:Int
		For Local index:Int = start Until tokens.length
			If parens = 0 And brackets = 0 And (index = 0 Or tokens[index - 1].text <> ".") And TextEquals(tokens[index].text, text) Then Return index
			Select tokens[index].text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
		Next
		Return -1
	End Function

	Function FindAssertSeparator:Int(tokens:TSyntaxToken[])
		Local parens:Int
		Local brackets:Int
		For Local index:Int = 1 Until tokens.length
			If parens = 0 And brackets = 0 And (tokens[index].text = "," Or TextEquals(tokens[index].text, "else")) Then Return index
			Select tokens[index].text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
		Next
		Return -1
	End Function

	Function ContainsToken:Int(tokens:TSyntaxToken[], text:String)
		For Local token:TSyntaxToken = EachIn tokens
			If TextEquals(token.text, text) Then Return True
		Next
		Return False
	End Function

	Function StartsWithToken:Int(tokens:TSyntaxToken[], text:String)
		Return tokens.length > 0 And TextEquals(tokens[0].text, text)
	End Function

	Function EmptyBlockAt:TBlockSyntax(offset:Int)
		Local block:TBlockSyntax = New TBlockSyntax
		block.kind = SYNTAX_BLOCK
		block.statements = New TSyntaxNode[0]
		block.span = TSourceSpan.Create(offset, 0)
		Return block
	End Function

	Function IsCombinedTerminator:Int(text:String)
		Select text
			Case "endfunction", "endmethod", "endtype", "endinterface", "endstruct", "endextern"
				Return True
		End Select
		Return False
	End Function

	Function IsBlockKind:Int(text:String)
		Select text
			Case "function", "method", "type", "interface", "struct", "extern"
				Return True
		End Select
		Return False
	End Function

	Function SpanOfTokens:TSourceSpan(values:TSyntaxToken[])
		If values.length = 0 Then Return TSourceSpan.Create(0, 0)
		Local start:Int = values[0].span.start
		Return TSourceSpan.Create(start, values[values.length - 1].span.EndOffset() - start)
	End Function

	Function IfExpressionListSpan:TSourceSpan(values:TSyntaxToken[], index:Int)
		If values.length = 0 Then Return TSourceSpan.Create(0, 0)
		If index < values.length Then Return values[index].span
		Return TSourceSpan.Create(values[values.length - 1].span.EndOffset(), 0)
	End Function

	Function TerminatorText:String(node:TBlockTerminatorSyntax)
		If node.blockToken Then Return node.endToken.text + " " + node.blockToken.text
		Return node.endToken.text
	End Function

	Function Capitalize:String(text:String)
		If Not text Then Return text
		Return text[..1].ToUpper() + text[1..]
	End Function

	Function TokensFromList:TSyntaxToken[](list:TList)
		Local result:TSyntaxToken[] = New TSyntaxToken[list.Count()]
		Local index:Int
		For Local value:TSyntaxToken = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function NodesToArray:TSyntaxNode[](list:TList)
		Local result:TSyntaxNode[] = New TSyntaxNode[list.Count()]
		Local index:Int
		For Local value:TSyntaxNode = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function DeclaratorsToArray:TVariableDeclaratorSyntax[](list:TList)
		Local result:TVariableDeclaratorSyntax[] = New TVariableDeclaratorSyntax[list.Count()]
		Local index:Int
		For Local value:TVariableDeclaratorSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function ElseIfToArray:TElseIfClauseSyntax[](list:TList)
		Local result:TElseIfClauseSyntax[] = New TElseIfClauseSyntax[list.Count()]
		Local index:Int
		For Local value:TElseIfClauseSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function ExpressionsToArray:TExpressionSyntax[](list:TList)
		Local result:TExpressionSyntax[] = New TExpressionSyntax[list.Count()]
		Local index:Int
		For Local value:TExpressionSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function CasesToArray:TCaseClauseSyntax[](list:TList)
		Local result:TCaseClauseSyntax[] = New TCaseClauseSyntax[list.Count()]
		Local index:Int
		For Local value:TCaseClauseSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function DefaultsToArray:TDefaultClauseSyntax[](list:TList)
		Local result:TDefaultClauseSyntax[] = New TDefaultClauseSyntax[list.Count()]
		Local index:Int
		For Local value:TDefaultClauseSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function CatchesToArray:TCatchClauseSyntax[](list:TList)
		Local result:TCatchClauseSyntax[] = New TCatchClauseSyntax[list.Count()]
		Local index:Int
		For Local value:TCatchClauseSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function ResourceDeclarationsToArray:TVariableDeclarationStatementSyntax[](list:TList)
		Local result:TVariableDeclarationStatementSyntax[] = New TVariableDeclarationStatementSyntax[list.Count()]
		Local index:Int
		For Local value:TVariableDeclarationStatementSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function ConditionalBranchesToArray:TConditionalBranchSyntax[](list:TList)
		Local result:TConditionalBranchSyntax[] = New TConditionalBranchSyntax[list.Count()]
		Local index:Int
		For Local value:TConditionalBranchSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function EnumValuesToArray:TEnumValueSyntax[](list:TList)
		Local result:TEnumValueSyntax[] = New TEnumValueSyntax[list.Count()]
		Local index:Int
		For Local value:TEnumValueSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function DiagnosticsToArray:TDiagnostic[](list:TList)
		Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
		Local index:Int
		For Local value:TDiagnostic = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function
End Type
