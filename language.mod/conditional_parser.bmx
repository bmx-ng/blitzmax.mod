' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "syntax.bmx"

Type TConditionalExpressionParser
	Field tokens:TSyntaxToken[]
	Field position:Int
	Field diagnostics:TList
	Field endOffset:Int

	Function Parse:TConditionalExpressionSyntax(directiveToken:TSyntaxToken, diagnostics:TList)
		Local parser:TConditionalExpressionParser = New TConditionalExpressionParser
		parser.tokens = Tokenize(directiveToken)
		parser.diagnostics = diagnostics
		parser.endOffset = directiveToken.span.EndOffset()
		If parser.tokens.length = 0 Then
			diagnostics.AddLast(TDiagnostic.Create("BMX2440", "Expected a conditional-compilation expression.", DIAGNOSTIC_ERROR, TSourceSpan.Create(directiveToken.span.EndOffset(), 0)))
			Return parser.MissingName(directiveToken.span.EndOffset())
		End If
		Local result:TConditionalExpressionSyntax = parser.ParseOr()
		If parser.position < parser.tokens.length Then
			diagnostics.AddLast(TDiagnostic.Create("BMX2441", "Unexpected token '" + parser.Current().text + "' in conditional-compilation expression.", DIAGNOSTIC_ERROR, parser.Current().span))
		End If
		Return result
	End Function

	Method ParseOr:TConditionalExpressionSyntax()
		Local left:TConditionalExpressionSyntax = ParseAnd()
		While IsOperator("or")
			left = MakeBinary(left, Current(), AdvanceAndParseAnd())
		Wend
		Return left
	End Method

	Method ParseAnd:TConditionalExpressionSyntax()
		Local left:TConditionalExpressionSyntax = ParseNot()
		While IsOperator("and")
			Local operatorToken:TSyntaxToken = Current()
			Advance()
			left = MakeBinary(left, operatorToken, ParseNot())
		Wend
		Return left
	End Method

	Method AdvanceAndParseAnd:TConditionalExpressionSyntax()
		Advance()
		Return ParseAnd()
	End Method

	Method ParseNot:TConditionalExpressionSyntax()
		If IsOperator("not") Then
			Local node:TConditionalNotSyntax = New TConditionalNotSyntax
			node.kind = SYNTAX_CONDITIONAL_NOT
			node.notToken = Current()
			Advance()
			node.operand = ParseNot()
			node.span = Combine(node.notToken.span, node.operand.span)
			Return node
		End If
		Return ParsePrimary()
	End Method

	Method ParsePrimary:TConditionalExpressionSyntax()
		If position >= tokens.length Then
			AddExpectedCondition(TSourceSpan.Create(endOffset, 0))
			Return MissingName(endOffset)
		End If

		If Current().text = "(" Then
			Local node:TConditionalParenthesizedSyntax = New TConditionalParenthesizedSyntax
			node.kind = SYNTAX_CONDITIONAL_PARENTHESES
			node.openToken = Current()
			Advance()
			node.expression = ParseOr()
			If position < tokens.length And Current().text = ")" Then
				node.closeToken = Current()
				Advance()
			Else
				Local missingAt:Int = node.expression.span.EndOffset()
				node.closeToken = TSyntaxToken.Create(TOKEN_SYMBOL, TSourceSpan.Create(missingAt, 0), ")", Null, Null, True)
				diagnostics.AddLast(TDiagnostic.Create("BMX2443", "Expected ')' in conditional-compilation expression.", DIAGNOSTIC_ERROR, node.closeToken.span))
			End If
			node.span = Combine(node.openToken.span, node.closeToken.span)
			Return node
		End If

		If Current().text = ")" Or IsOperator("and") Or IsOperator("or") Then
			AddExpectedCondition(Current().span)
			Return MissingName(Current().span.start)
		End If

		Local name:TConditionalNameSyntax = New TConditionalNameSyntax
		name.kind = SYNTAX_CONDITIONAL_NAME
		name.nameToken = Current()
		name.span = Current().span
		Advance()
		Return name
	End Method

	Method MakeBinary:TConditionalBinarySyntax(left:TConditionalExpressionSyntax, operatorToken:TSyntaxToken, right:TConditionalExpressionSyntax)
		Local node:TConditionalBinarySyntax = New TConditionalBinarySyntax
		node.kind = SYNTAX_CONDITIONAL_BINARY
		node.left = left
		node.operatorToken = operatorToken
		node.right = right
		node.span = Combine(left.span, right.span)
		Return node
	End Method

	Method MissingName:TConditionalNameSyntax(offset:Int)
		Local node:TConditionalNameSyntax = New TConditionalNameSyntax
		node.kind = SYNTAX_CONDITIONAL_NAME
		node.nameToken = TSyntaxToken.Create(TOKEN_IDENTIFIER, TSourceSpan.Create(offset, 0), "", Null, Null, True)
		node.span = node.nameToken.span
		Return node
	End Method

	Method AddExpectedCondition(span:TSourceSpan)
		diagnostics.AddLast(TDiagnostic.Create("BMX2442", "Expected a target symbol, 'Not', or '('.", DIAGNOSTIC_ERROR, span))
	End Method

	Method IsOperator:Int(value:String)
		Return position < tokens.length And Current().text.ToLower() = value
	End Method

	Method Current:TSyntaxToken()
		Return tokens[position]
	End Method

	Method Advance()
		If position < tokens.length Then position :+ 1
	End Method

	Function Tokenize:TSyntaxToken[](directiveToken:TSyntaxToken)
		Local values:TList = New TList
		Local text:String = directiveToken.text
		Local index:Int = 1
		While index < text.length
			While index < text.length And IsWhitespace(text[index])
				index :+ 1
			Wend
			If index >= text.length Then Exit
			Local start:Int = index
			If text[index] = Asc("(") Or text[index] = Asc(")") Then
				index :+ 1
			Else
				While index < text.length And Not IsWhitespace(text[index]) And text[index] <> Asc("(") And text[index] <> Asc(")")
					index :+ 1
				Wend
			End If
			Local tokenText:String = text[start..index]
			Local kind:Int = TOKEN_IDENTIFIER
			If tokenText = "(" Or tokenText = ")" Then kind = TOKEN_SYMBOL
			values.AddLast(TSyntaxToken.Create(kind, TSourceSpan.Create(directiveToken.span.start + start, index - start), tokenText))
		Wend
		Local result:TSyntaxToken[] = New TSyntaxToken[values.Count()]
		Local resultIndex:Int
		For Local token:TSyntaxToken = EachIn values
			result[resultIndex] = token
			resultIndex :+ 1
		Next
		Return result
	End Function

	Function IsWhitespace:Int(character:Int)
		Return character = 32 Or character = 9
	End Function

	Function Combine:TSourceSpan(first:TSourceSpan, last:TSourceSpan)
		Return TSourceSpan.Create(first.start, last.EndOffset() - first.start)
	End Function
End Type
