' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "syntax.bmx"
Import "type_parser.bmx"

Type TExpressionParseResult
	Field expression:TExpressionSyntax
	Field consumed:Int
End Type

Type TExpressionSlot
	Field expression:TExpressionSyntax
End Type

Type TBlitzMaxExpressionParser
	Const MAX_EXPRESSION_DEPTH:Int = 512

	Field tokens:TSyntaxToken[]
	Field position:Int
	Field limit:Int
	Field diagnostics:TList
	Field expressionDepth:Int
	Field depthDiagnosticReported:Int

	Function Parse:TExpressionSyntax(tokens:TSyntaxToken[], diagnostics:TList)
		If tokens.length = 0 Then Return Null
		Local parsed:TExpressionParseResult = ParsePrefix(tokens, diagnostics)
		If parsed.consumed < tokens.length Then
			Local raw:TRawExpressionSyntax = New TRawExpressionSyntax
			raw.kind = SYNTAX_RAW_EXPRESSION
			raw.tokens = tokens
			raw.span = SpanOf(tokens)
			diagnostics.AddLast(TDiagnostic.Create("BMX2102", "Unexpected token '" + tokens[parsed.consumed].text + "' in expression.", DIAGNOSTIC_ERROR, tokens[parsed.consumed].span))
			Return raw
		End If
		Return parsed.expression
	End Function

	Function ParsePrefix:TExpressionParseResult(tokens:TSyntaxToken[], diagnostics:TList)
		Local parsed:TExpressionParseResult = New TExpressionParseResult
		If tokens.length = 0 Then Return parsed
		Local parser:TBlitzMaxExpressionParser = New TBlitzMaxExpressionParser
		parser.tokens = tokens
		parser.limit = tokens.length
		parser.diagnostics = diagnostics
		parsed.expression = parser.ParseRange()
		parsed.consumed = parser.position
		Return parsed
	End Function

	Method ParseRange:TExpressionSyntax()
		Local lowerBound:TExpressionSyntax
		Local lowerFromEndToken:TSyntaxToken
		If position < limit And Current().text = ".." Then Return ParseRangeLiteral(Null, Null)
		If position < limit And Current().text = "^" Then
			lowerFromEndToken = Current()
			Advance()
			lowerBound = ParseFromEndDistance()
			If position < limit And Current().text = "^" Then
				AddDiagnostic("BMX2115", "Parenthesize a calculated from-end Range endpoint as '^(expression)'.", Current().span)
				ConsumeUnparenthesizedFromEndPower()
			End If
		Else
			lowerBound = ParseBinary(1)
		End If
		If position < limit And Current().text = ".." Then Return ParseRangeLiteral(lowerBound, lowerFromEndToken)
		If lowerFromEndToken Then AddDiagnostic("BMX2114", "A from-end endpoint must be part of a Range expression.", lowerFromEndToken.span)
		Return lowerBound
	End Method

	Method ParseRangeLiteral:TRangeExpressionSyntax(lowerBound:TExpressionSyntax, lowerFromEndToken:TSyntaxToken)
		Local range:TRangeExpressionSyntax = New TRangeExpressionSyntax
		range.kind = SYNTAX_RANGE_EXPRESSION
		range.lowerBound = lowerBound
		range.lowerFromEndToken = lowerFromEndToken
		range.rangeToken = Current()
		Advance()
		If position < limit And Not IsRangeTerminator(Current()) Then
			If Current().text = "^" Then
				range.upperFromEndToken = Current()
				Advance()
				range.upperBound = ParseFromEndDistance()
				If position < limit And Current().text = "^" Then
					AddDiagnostic("BMX2115", "Parenthesize a calculated from-end Range endpoint as '^(expression)'.", Current().span)
					ConsumeUnparenthesizedFromEndPower()
				End If
			Else
				range.upperBound = ParseBinary(1)
			End If
		End If
		Local first:TSourceSpan = range.rangeToken.span
		If lowerFromEndToken Then first = lowerFromEndToken.span Else If lowerBound Then first = lowerBound.span
		Local last:TSourceSpan = range.rangeToken.span
		If range.upperBound Then last = range.upperBound.span
		range.span = Combine(first, last)
		Return range
	End Method

	Method ParseFromEndDistance:TExpressionSyntax()
		' Bind the endpoint marker more tightly than binary power. Calculated
		' distances therefore remain explicit: ^(base^exponent).
		Return ParseBinary(9)
	End Method

	Method ConsumeUnparenthesizedFromEndPower()
		While position < limit And Current().text = "^"
			Advance()
			If position < limit Then ParseBinary(9)
		Wend
	End Method

	Function IsRangeTerminator:Int(token:TSyntaxToken)
		If Not token Then Return True
		Select token.text
			Case ")", "]", ",", ";" Return True
		End Select
		Return token.kind = TOKEN_NEWLINE Or token.kind = TOKEN_EOF
	End Function

	Method ParseBinary:TExpressionSyntax(parentPrecedence:Int)
		If position >= limit Then Return CreateMissingExpression()
		If expressionDepth >= MAX_EXPRESSION_DEPTH Then
			Local raw:TRawExpressionSyntax = New TRawExpressionSyntax
			raw.kind = SYNTAX_RAW_EXPRESSION
			raw.tokens = [Current()]
			raw.span = Current().span
			If Not depthDiagnosticReported Then
				AddDiagnostic("BMX2103", "Expression nesting is too deep to parse safely.", raw.span)
				depthDiagnosticReported = True
			End If
			Advance()
			Return raw
		End If
		expressionDepth :+ 1
		Local left:TExpressionSyntax
		Local unaryPrecedence:Int = UnaryPrecedence(Current())
		If unaryPrecedence Then
			Local unary:TUnaryExpressionSyntax = New TUnaryExpressionSyntax
			unary.kind = SYNTAX_UNARY_EXPRESSION
			unary.operatorToken = Current()
			Advance()
			' Parenthesized language intrinsics use their parentheses as an
			' argument boundary.  A following member/index/call therefore applies
			' to the intrinsic result (`Chr(code).ToUpper()`), not to the value
			' inside the parentheses.
			If IntrinsicHasParenthesizedOperand(unary.operatorToken) And position < limit And Current().text = "(" Then
				unary.operand = ParsePrimary()
			Else
				unary.operand = ParseBinary(unaryPrecedence)
			End If
			unary.span = Combine(unary.operatorToken.span, unary.operand.span)
			left = ParsePostfixContinuation(unary)
		Else
			left = ParsePostfix()
		End If

		While position < limit
			Local precedence:Int = BinaryPrecedence(Current())
			If precedence = 0 Or precedence < parentPrecedence Then Exit
			Local op:TSyntaxToken = Current()
			Advance()
			Local right:TExpressionSyntax = ParseBinary(precedence + 1)
			Local binary:TBinaryExpressionSyntax = New TBinaryExpressionSyntax
			binary.kind = SYNTAX_BINARY_EXPRESSION
			binary.left = left
			binary.operatorToken = op
			binary.right = right
			binary.span = Combine(left.span, right.span)
			left = binary
		Wend
		expressionDepth :- 1
		Return left
	End Method

	Method CreateMissingExpression:TExpressionSyntax()
		Local missing:TRawExpressionSyntax = New TRawExpressionSyntax
		missing.kind = SYNTAX_RAW_EXPRESSION
		missing.tokens = New TSyntaxToken[0]
		Local offset:Int
		If limit > 0 Then offset = tokens[limit - 1].span.EndOffset()
		missing.span = TSourceSpan.Create(offset, 0)
		AddDiagnostic("BMX2101", "Expected an expression.", missing.span)
		Return missing
	End Method

	Method ParsePostfix:TExpressionSyntax()
		Local expression:TExpressionSyntax = ParsePrimary()
		Return ParsePostfixContinuation(expression)
	End Method

	Method ParsePostfixContinuation:TExpressionSyntax(expression:TExpressionSyntax)
		While position < limit
			If Current().text = "." And IsNameToken(Peek(1)) Then
				Local member:TMemberAccessExpressionSyntax = New TMemberAccessExpressionSyntax
				member.kind = SYNTAX_MEMBER_EXPRESSION
				member.expression = expression
				member.dotToken = Current()
				Advance()
				member.nameToken = Current()
				Advance()
				member.span = Combine(expression.span, member.nameToken.span)
				expression = member
			Else If IsExplicitGenericCallStart(expression) Then
				Local genericOpen:TSyntaxToken = Current()
				Local genericCloseIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, position, "<", ">")
				Local typeArguments:TTypeReferenceSyntax[] = TBlitzMaxTypeParser.ParseTypeList(tokens[position + 1..genericCloseIndex])
				Local genericClose:TSyntaxToken = tokens[genericCloseIndex]
				position = genericCloseIndex + 1
				Local genericCall:TCallExpressionSyntax = ParseCall(expression)
				genericCall.genericOpenToken = genericOpen
				genericCall.typeArguments = typeArguments
				genericCall.genericCloseToken = genericClose
				expression = genericCall
			Else If IsGenericTypeQualifierStart(expression) Then
				Local genericOpen:TSyntaxToken = Current()
				Local genericCloseIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, position, "<", ">")
				Local typeArguments:TTypeReferenceSyntax[] = TBlitzMaxTypeParser.ParseTypeList(tokens[position + 1..genericCloseIndex])
				Local genericClose:TSyntaxToken = tokens[genericCloseIndex]
				Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
				If name Then
					name.genericOpenToken = genericOpen
					name.typeArguments = typeArguments
					name.genericCloseToken = genericClose
				End If
				Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
				If member Then
					member.genericOpenToken = genericOpen
					member.typeArguments = typeArguments
					member.genericCloseToken = genericClose
				End If
				expression.span = Combine(expression.span, genericClose.span)
				position = genericCloseIndex + 1
			Else If IsExplicitGenericReferenceStart(expression) Then
				Local genericOpen:TSyntaxToken = Current()
				Local genericCloseIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, position, "<", ">")
				Local typeArguments:TTypeReferenceSyntax[] = TBlitzMaxTypeParser.ParseTypeList(tokens[position + 1..genericCloseIndex])
				Local genericClose:TSyntaxToken = tokens[genericCloseIndex]
				Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
				If name Then
					name.genericOpenToken = genericOpen
					name.typeArguments = typeArguments
					name.genericCloseToken = genericClose
				End If
				Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
				If member Then
					member.genericOpenToken = genericOpen
					member.typeArguments = typeArguments
					member.genericCloseToken = genericClose
				End If
				expression.span = Combine(expression.span, genericClose.span)
				position = genericCloseIndex + 1
			Else If Current().text = "(" Then
				expression = ParseCall(expression)
			Else If Current().text = "[" Then
				expression = ParseIndex(expression)
			Else If Current().text = ":" And IsNameToken(Peek(1)) Then
				expression = ParseTypeAscription(expression)
			Else If TLiteralExpressionSyntax(expression) And IsLiteralTypeTag(Current(), expression) Then
				expression = ParseLiteralTypeTag(expression)
			Else If IsLegacyNameTypeTag(Current(), expression) Then
				expression = ParseLegacyNameTypeTag(expression)
			Else
				Exit
			End If
		Wend
		Return expression
	End Method

	Function IntrinsicHasParenthesizedOperand:Int(token:TSyntaxToken)
		If Not token Then Return False
		Select token.text.ToLower()
			Case "len", "asc", "chr", "stackalloc", "sizeof", "alignof"
				Return True
		End Select
		Return False
	End Function

	Method IsLegacyNameTypeTag:Int(token:TSyntaxToken, expression:TExpressionSyntax)
		If token.span.start <> expression.span.EndOffset() Then Return False
		If Not TNameExpressionSyntax(expression) And Not TMemberAccessExpressionSyntax(expression) Then Return False
		Select token.text.ToLower()
			Case "%", "#", "!", "$"
				Return True
		End Select
		Return False
	End Method

	Method ParseLegacyNameTypeTag:TExpressionSyntax(expression:TExpressionSyntax)
		Local tag:TSyntaxToken = Current()
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then name.legacyTypeTagToken = tag
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then member.legacyTypeTagToken = tag
		expression.span = Combine(expression.span, tag.span)
		Advance()
		Return expression
	End Method

	Method IsLiteralTypeTag:Int(token:TSyntaxToken, expression:TExpressionSyntax)
		' Interface signatures have a much larger compact marker vocabulary.
		' BlitzMax source only supports the four documented legacy literal tags.
		' Keep them attached to the literal so spaced operators remain operators.
		If token.span.start <> expression.span.EndOffset() Then Return False
		Select token.text.ToLower()
			Case "%", "#", "!", "$"
				Return True
		End Select
		Return False
	End Method

	Method IsExplicitGenericCallStart:Int(expression:TExpressionSyntax)
		If position >= limit Or Current().text <> "<" Then Return False
		If Not TNameExpressionSyntax(expression) And Not TMemberAccessExpressionSyntax(expression) Then Return False
		Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, position, "<", ">")
		If closeIndex <= position + 1 Or closeIndex + 1 >= limit Or tokens[closeIndex + 1].text <> "(" Then Return False
		Local start:Int = position + 1
		Local angles:Int
		Local brackets:Int
		For Local index:Int = start To closeIndex
			Local split:Int = index = closeIndex
			If Not split Then
				Select tokens[index].text
					Case "<" angles :+ 1
					Case ">" angles :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
					Case ","
						If angles = 0 And brackets = 0 Then split = True
				End Select
			End If
			If split Then
				If index <= start Or Not IsPossibleTypeReference(tokens[start..index]) Then Return False
				start = index + 1
			End If
		Next
		Return True
	End Method

	Method IsGenericTypeQualifierStart:Int(expression:TExpressionSyntax)
		If position >= limit Or Current().text <> "<" Then Return False
		If Not TNameExpressionSyntax(expression) And Not TMemberAccessExpressionSyntax(expression) Then Return False
		Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, position, "<", ">")
		If closeIndex <= position + 1 Or closeIndex + 1 >= limit Or tokens[closeIndex + 1].text <> "." Then Return False
		Local start:Int = position + 1
		Local angles:Int
		Local brackets:Int
		For Local index:Int = start To closeIndex
			Local split:Int = index = closeIndex
			If Not split Then
				Select tokens[index].text
					Case "<" angles :+ 1
					Case ">" angles :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
					Case ","
						If angles = 0 And brackets = 0 Then split = True
				End Select
			End If
			If split Then
				If index <= start Or Not IsPossibleTypeReference(tokens[start..index]) Then Return False
				start = index + 1
			End If
		Next
		Return True
	End Method

	Method IsExplicitGenericReferenceStart:Int(expression:TExpressionSyntax)
		If position >= limit Or Current().text <> "<" Then Return False
		If Not TNameExpressionSyntax(expression) And Not TMemberAccessExpressionSyntax(expression) Then Return False
		Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, position, "<", ">")
		' Some callers slice away their delimiter while argument parsing retains it.
		' In either form, the specialization must finish the expression; this keeps
		' ordinary relational expressions such as a < b > c unambiguous.
		If closeIndex <= position + 1 Then Return False
		If closeIndex <> limit - 1 Then
			If closeIndex + 1 >= limit Then Return False
			Select tokens[closeIndex + 1].text
				Case ",", ")", "]"
				Default Return False
			End Select
		End If
		Local start:Int = position + 1
		Local angles:Int
		Local brackets:Int
		For Local index:Int = start To closeIndex
			Local split:Int = index = closeIndex
			If Not split Then
				Select tokens[index].text
					Case "<" angles :+ 1
					Case ">" angles :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
					Case ","
						If angles = 0 And brackets = 0 Then split = True
				End Select
			End If
			If split Then
				If index <= start Or Not IsPossibleTypeReference(tokens[start..index]) Then Return False
				start = index + 1
			End If
		Next
		Return True
	End Method

	Method IsPossibleTypeReference:Int(values:TSyntaxToken[])
		If values.length = 0 Then Return False
		If Not IsNameToken(values[0]) And Not TBlitzMaxTypeParser.IsTypeMarker(values[0].text) Then Return False
		For Local token:TSyntaxToken = EachIn values
			Local lower:String = token.text.ToLower()
			If IsNameToken(token) Or lower = "ptr" Then Continue
			Select token.text
				Case ".", "<", ">", "(", ")", "[", "]", "[]", ",", ":", "%", "%%", "#", "!", "$", "@", "@@", "?", "~~", "/"
					Continue
			End Select
			Return False
		Next
		Return True
	End Method

	Method ParsePrimary:TExpressionSyntax()
		If position >= limit Then Return CreateMissingExpression()

		Local token:TSyntaxToken = Current()
		If token.kind = TOKEN_EMBEDDED_EXPRESSION Then
			Local expression:TExpressionSyntax = TExpressionSyntax(token.payload)
			Advance()
			If expression Then Return expression
			Return CreateMissingExpression()
		End If
		If IsCastStart() Then Return ParseCastExpression()
		If IsPrefixCastStart() Then Return ParsePrefixCastExpression()
		If IsParenthesizedPrefixCastStart() Then Return ParseParenthesizedPrefixCastExpression()
		If token.text.ToLower() = "new" Then Return ParseNewExpression()
		If token.text = "[" Or token.text = "[]" Then Return ParseArrayLiteral()
		If token.text = "." Then
			Local scope:TScopeExpressionSyntax = New TScopeExpressionSyntax
			scope.kind = SYNTAX_SCOPE_EXPRESSION
			scope.dotToken = token
			scope.span = token.span
			Advance()
			If position < limit And IsNameToken(Current()) Then
				Local member:TMemberAccessExpressionSyntax = New TMemberAccessExpressionSyntax
				member.kind = SYNTAX_MEMBER_EXPRESSION
				member.expression = scope
				member.dotToken = token
				member.nameToken = Current()
				member.span = Combine(token.span, Current().span)
				Advance()
				Return member
			End If
			Return scope
		End If
		If token.text = "(" Then
			Local parenthesized:TParenthesizedExpressionSyntax = New TParenthesizedExpressionSyntax
			parenthesized.kind = SYNTAX_PARENTHESES_EXPRESSION
			parenthesized.openToken = token
			Advance()
			parenthesized.expression = ParseRange()
			If position < limit And Current().text = ")" Then
				parenthesized.closeToken = Current()
				Advance()
				parenthesized.span = Combine(token.span, parenthesized.closeToken.span)
			Else
				parenthesized.span = Combine(token.span, parenthesized.expression.span)
				AddDiagnostic("BMX2100", "Expected ')' to close expression.", TSourceSpan.Create(parenthesized.span.EndOffset(), 0))
			End If
			Return parenthesized
		End If

		If IsLiteralToken(token) Then
			Local literal:TLiteralExpressionSyntax = New TLiteralExpressionSyntax
			literal.kind = SYNTAX_LITERAL_EXPRESSION
			literal.literalToken = token
			literal.span = token.span
			Advance()
			Return literal
		End If

		If IsNameToken(token) Then
			Local name:TNameExpressionSyntax = New TNameExpressionSyntax
			name.kind = SYNTAX_NAME_EXPRESSION
			name.nameToken = token
			name.span = token.span
			Advance()
			If token.text.ToLower() = "super" And position < limit And Current().text = "<" Then
				Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, position, "<", ">")
				If closeIndex > position + 1 Then
					name.qualifiedSuperOpenToken = Current()
					name.qualifiedSuperType = TBlitzMaxTypeParser.Parse(tokens[position + 1..closeIndex])
					name.qualifiedSuperCloseToken = tokens[closeIndex]
					name.span = Combine(token.span, name.qualifiedSuperCloseToken.span)
					position = closeIndex + 1
				Else
					AddDiagnostic("BMX2104", "Expected an Interface type in qualified Super expression.", token.span)
				End If
			End If
			Return name
		End If

		Local raw:TRawExpressionSyntax = New TRawExpressionSyntax
		raw.kind = SYNTAX_RAW_EXPRESSION
		raw.tokens = [token]
		raw.span = token.span
		AddDiagnostic("BMX2101", "Expected an expression but found '" + token.text + "'.", token.span)
		Advance()
		Return raw
	End Method

	Method ParseCall:TCallExpressionSyntax(callee:TExpressionSyntax)
		Local call:TCallExpressionSyntax = New TCallExpressionSyntax
		call.kind = SYNTAX_CALL_EXPRESSION
		call.callee = callee
		call.typeArguments = New TTypeReferenceSyntax[0]
		call.openToken = Current()
		Advance()
		call.arguments = ParseExpressionList(")")
		If position < limit And Current().text = ")" Then
			call.closeToken = Current()
			Advance()
			call.span = Combine(callee.span, call.closeToken.span)
		Else
			call.span = Combine(callee.span, LastExpressionSpan(call.arguments, call.openToken.span))
			AddDiagnostic("BMX2100", "Expected ')' after argument list.", TSourceSpan.Create(call.span.EndOffset(), 0))
		End If
		Return call
	End Method

	Method ParseIndex:TExpressionSyntax(expression:TExpressionSyntax)
		Local openToken:TSyntaxToken = Current()
		Advance()
		If position < limit And Current().text = ".." Then Return ParseSlice(expression, openToken, Null)

		Local lowerFromEndToken:TSyntaxToken
		Local first:TExpressionSyntax
		If position < limit And Current().text = "^" Then
			lowerFromEndToken = Current()
			Advance()
			first = ParseFromEndDistance()
			If position < limit And Current().text = "^" Then
				AddDiagnostic("BMX2115", "Parenthesize a calculated from-end Range endpoint as '^(expression)'.", Current().span)
				ConsumeUnparenthesizedFromEndPower()
			End If
		Else
			first = ParseBinary(1)
		End If
		If position < limit And Current().text = ".." Then Return ParseSlice(expression, openToken, first, lowerFromEndToken)
		If lowerFromEndToken Then AddDiagnostic("BMX2114", "A from-end endpoint requires a Range slice.", lowerFromEndToken.span)

		Local index:TIndexExpressionSyntax = New TIndexExpressionSyntax
		index.kind = SYNTAX_INDEX_EXPRESSION
		index.expression = expression
		index.openToken = openToken
		Local values:TList = New TList
		values.AddLast(first)
		While position < limit And Current().text = ","
			Advance()
			values.AddLast(ParseBinary(1))
		Wend
		index.indexes = ExpressionsToArray(values)
		If position < limit And Current().text = "]" Then
			index.closeToken = Current()
			Advance()
			index.span = Combine(expression.span, index.closeToken.span)
		Else
			index.span = Combine(expression.span, LastExpressionSpan(index.indexes, index.openToken.span))
			AddDiagnostic("BMX2100", "Expected ']' after index list.", TSourceSpan.Create(index.span.EndOffset(), 0))
		End If
		Return index
	End Method

	Method ParseSlice:TSliceExpressionSyntax(expression:TExpressionSyntax, openToken:TSyntaxToken, lowerBound:TExpressionSyntax, lowerFromEndToken:TSyntaxToken = Null)
		Local slice:TSliceExpressionSyntax = New TSliceExpressionSyntax
		slice.kind = SYNTAX_SLICE_EXPRESSION
		slice.expression = expression
		slice.openToken = openToken
		slice.lowerBound = lowerBound
		slice.lowerFromEndToken = lowerFromEndToken
		slice.rangeToken = Current()
		Advance()
		If position < limit And Current().text <> "]" Then
			If Current().text = "^" Then
				slice.upperFromEndToken = Current()
				Advance()
				slice.upperBound = ParseFromEndDistance()
				If position < limit And Current().text = "^" Then
					AddDiagnostic("BMX2115", "Parenthesize a calculated from-end Range endpoint as '^(expression)'.", Current().span)
					ConsumeUnparenthesizedFromEndPower()
				End If
			Else
				slice.upperBound = ParseBinary(1)
			End If
		End If
		If position < limit And Current().text = "]" Then
			slice.closeToken = Current()
			Advance()
			slice.span = Combine(expression.span, slice.closeToken.span)
		Else
			Local last:TSourceSpan = slice.rangeToken.span
			If slice.upperBound Then last = slice.upperBound.span
			slice.span = Combine(expression.span, last)
			AddDiagnostic("BMX2100", "Expected ']' after slice.", TSourceSpan.Create(slice.span.EndOffset(), 0))
		End If
		Return slice
	End Method

	Method ParseTypeAscription:TTypeAscriptionExpressionSyntax(expression:TExpressionSyntax)
		Local node:TTypeAscriptionExpressionSyntax = New TTypeAscriptionExpressionSyntax
		node.kind = SYNTAX_TYPE_ASCRIPTION_EXPRESSION
		node.expression = expression
		node.colonToken = Current()
		Local start:Int = position
		Advance()
		Advance()
		While position < limit And Current().text.ToLower() = "ptr"
			Advance()
		Wend
		While position < limit And Current().text = "[]"
			Advance()
		Wend
		node.targetType = TBlitzMaxTypeParser.Parse(tokens[start..position])
		node.span = Combine(expression.span, node.targetType.span)
		If Not IsNamedNumericLiteralTypeTag(expression, node.targetType) Then
			AddDiagnostic("BMX2105", "A postfix ':Type' is valid only on a numeric literal; use Type(expression) for an explicit conversion.", node.targetType.span)
		End If
		Return node
	End Method

	Function IsNamedNumericLiteralTypeTag:Int(expression:TExpressionSyntax, targetType:TTypeReferenceSyntax)
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If Not literal Or Not literal.literalToken Or Not targetType Then Return False
		If literal.literalToken.kind <> TOKEN_INTEGER_LITERAL And literal.literalToken.kind <> TOKEN_FLOAT_LITERAL Then Return False
		' ParseTypeAscription includes the separating colon in the type token
		' slice, so it is retained as the ordinary named-type marker.
		If Not targetType.markerToken Or targetType.markerToken.text <> ":" Or targetType.nameTokens.length <> 1 Or targetType.genericArguments.length Or targetType.pointerTokens.length Or targetType.arrayRanks.length Then Return False
		Select targetType.nameTokens[0].text.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double", "float64", "int128", "float128", "double128", "wparam", "lparam"
				Return True
		End Select
		Return False
	End Function

	' Traditional BlitzMax literal tags are postfix type ascriptions: 0# is a
	' Float zero, 1! is Double, and 1% is Int. Keep the tag as its own
	' token for lossless syntax while using the ordinary type-resolution path.
	Method ParseLiteralTypeTag:TTypeAscriptionExpressionSyntax(expression:TExpressionSyntax)
		Local node:TTypeAscriptionExpressionSyntax = New TTypeAscriptionExpressionSyntax
		node.kind = SYNTAX_TYPE_ASCRIPTION_EXPRESSION
		node.expression = expression
		node.colonToken = Current()
		node.targetType = TBlitzMaxTypeParser.Parse([Current()])
		node.span = Combine(expression.span, Current().span)
		Advance()
		Return node
	End Method

	Method ParseNewExpression:TExpressionSyntax()
		If position + 1 < limit And tokens[position + 1].text = "(" Then Return ParseConstructorDelegationCall()
		Local node:TNewExpressionSyntax = New TNewExpressionSyntax
		node.kind = SYNTAX_NEW_EXPRESSION
		node.newToken = Current()
		Local start:Int = Current().span.start
		Advance()
		Local typeStart:Int = position
		If position < limit And IsNameToken(Current()) Then
			Advance()
			If position < limit And Current().text = "<" Then ConsumeBalanced("<", ">")
			While position < limit And (Current().text.ToLower() = "ptr" Or Current().text = "[]")
				Advance()
			Wend
		Else
			AddDiagnostic("BMX2110", "Expected a type after 'New'.", node.newToken.span)
		End If
		If position > typeStart Then node.createdType = TBlitzMaxTypeParser.Parse(tokens[typeStart..position])
		Local dimensions:TList = New TList
		Local dimensionRanks:Int[]
		Local suffixStart:Int = position
		If position < limit And Current().text = "(" Then
			node.openParenToken = Current()
			Advance()
			node.arguments = ParseExpressionList(")")
			If position < limit And Current().text = ")" Then
				node.closeParenToken = Current()
				Advance()
			Else
				AddDiagnostic("BMX2111", "Expected ')' after constructor arguments.", TSourceSpan.Create(Current().span.start, 0))
			End If
		Else
			node.arguments = New TExpressionSyntax[0]
			While position < limit And (Current().text = "[" Or Current().text = "[]")
				If Current().text = "[]" Then
					dimensionRanks :+ [1]
					Advance()
					Continue
				End If
				Advance()
				Local rank:Int = 1
				While position < limit And Current().text <> "]"
					If Current().text = "," Then
						rank :+ 1
						Advance()
					Else
						dimensions.AddLast(ParseBinary(1))
						If position < limit And Current().text = "," Then
							rank :+ 1
							Advance()
						End If
					End If
				Wend
				If position < limit And Current().text = "]" Then Advance() Else Exit
				dimensionRanks :+ [rank]
			Wend
		End If
		If position > suffixStart Then node.suffixTokens = tokens[suffixStart..position] Else node.suffixTokens = New TSyntaxToken[0]
		node.dimensions = ExpressionsToArray(dimensions)
		node.dimensionRanks = dimensionRanks
		Local endOffset:Int = node.newToken.span.EndOffset()
		If node.createdType Then endOffset = node.createdType.span.EndOffset()
		If position > 0 Then endOffset = tokens[position - 1].span.EndOffset()
		node.span = TSourceSpan.Create(start, endOffset - start)
		Return node
	End Method

	Method ParseConstructorDelegationCall:TCallExpressionSyntax()
		Local name:TNameExpressionSyntax = New TNameExpressionSyntax
		name.kind = SYNTAX_NAME_EXPRESSION
		name.nameToken = Current()
		name.span = Current().span
		Advance()

		Local call:TCallExpressionSyntax = New TCallExpressionSyntax
		call.kind = SYNTAX_CALL_EXPRESSION
		call.callee = name
		call.openToken = Current()
		Advance()
		call.arguments = ParseExpressionList(")")
		If position < limit And Current().text = ")" Then
			call.closeToken = Current()
			Advance()
			call.span = Combine(name.span, call.closeToken.span)
		Else
			call.span = Combine(name.span, LastExpressionSpan(call.arguments, call.openToken.span))
			AddDiagnostic("BMX2111", "Expected ')' after constructor arguments.", TSourceSpan.Create(call.span.EndOffset(), 0))
		End If
		Return call
	End Method

	Method ParseArrayLiteral:TArrayLiteralExpressionSyntax()
		Local node:TArrayLiteralExpressionSyntax = New TArrayLiteralExpressionSyntax
		node.kind = SYNTAX_ARRAY_LITERAL_EXPRESSION
		If Current().text = "[]" Then
			node.emptyToken = Current()
			node.elements = New TExpressionSyntax[0]
			node.span = Current().span
			Advance()
			Return node
		End If
		node.openToken = Current()
		Advance()
		node.elements = ParseExpressionList("]")
		If position < limit And Current().text = "]" Then
			node.closeToken = Current()
			Advance()
			node.span = Combine(node.openToken.span, node.closeToken.span)
		Else
			node.span = Combine(node.openToken.span, LastExpressionSpan(node.elements, node.openToken.span))
			AddDiagnostic("BMX2112", "Expected ']' after array literal.", TSourceSpan.Create(node.span.EndOffset(), 0))
		End If
		Return node
	End Method

	Method ConsumeBalanced(openText:String, closeText:String)
		Local depth:Int
		While position < limit
			If Current().text = openText Then depth :+ 1
			If Current().text = closeText Then
				depth :- 1
				Advance()
				If depth = 0 Then Return
				Continue
			End If
			Advance()
		Wend
	End Method

	Method ParseExpressionList:TExpressionSyntax[](closing:String)
		Local values:TList = New TList
		If position < limit And Current().text = closing Then Return New TExpressionSyntax[0]
		Local expectingValue:Int = True
		While position < limit And Current().text <> closing
			If Current().text = "," Then
				If expectingValue Then AddExpressionSlot(values, CreateOmittedArgument())
				Advance()
				expectingValue = True
			Else
				AddExpressionSlot(values, ParseRange())
				expectingValue = False
				If position >= limit Or Current().text <> "," Then Exit
				Advance()
				expectingValue = True
			End If
		Wend
		If expectingValue And values.Count() Then AddExpressionSlot(values, CreateOmittedArgument())
		Return ExpressionSlotsToArray(values)
	End Method

	Method CreateOmittedArgument:TOmittedArgumentExpressionSyntax()
		Local offset:Int
		If position < limit Then
			offset = Current().span.start
		Else If limit > 0 Then
			offset = tokens[limit - 1].span.EndOffset()
		End If
		Return OmittedArgumentAt(offset)
	End Method

	Function OmittedArgumentAt:TOmittedArgumentExpressionSyntax(offset:Int)
		Local omitted:TOmittedArgumentExpressionSyntax = New TOmittedArgumentExpressionSyntax
		omitted.kind = SYNTAX_OMITTED_ARGUMENT_EXPRESSION
		omitted.span = TSourceSpan.Create(offset, 0)
		Return omitted
	End Function

	Method AddExpressionSlot(values:TList, expression:TExpressionSyntax)
		Local slot:TExpressionSlot = New TExpressionSlot
		slot.expression = expression
		values.AddLast(slot)
	End Method

	Method IsCastStart:Int()
		If position >= limit Or Not IsNameToken(Current()) Then Return False
		Local index:Int = position + 1
		Local hasTypeSuffix:Int
		While index < limit And (tokens[index].text.ToLower() = "ptr" Or tokens[index].text = "[]")
			hasTypeSuffix = True
			index :+ 1
		Wend
		If index >= limit Or tokens[index].text <> "(" Then Return False
		Return hasTypeSuffix Or IsBuiltInType(Current().text.ToLower())
	End Method

	Method IsPrefixCastStart:Int()
		If position >= limit Or Not IsNameToken(Current()) Then Return False
		Local index:Int = position + 1
		Local hasTypeSuffix:Int
		While index < limit And (tokens[index].text.ToLower() = "ptr" Or tokens[index].text = "[]")
			hasTypeSuffix = True
			index :+ 1
		Wend
		If index >= limit Or tokens[index].text = "(" Then Return False
		If Not hasTypeSuffix And Not IsBuiltInType(Current().text.ToLower()) Then Return False
		Return CanStartPrefixCastOperand(tokens[index])
	End Method

	Function CanStartPrefixCastOperand:Int(token:TSyntaxToken)
		If Not token Then Return False
		If IsLiteralToken(token) Then Return True
		If IsNameToken(token) Then
			Select token.text.ToLower()
				Case "ptr", "and", "or", "mod", "shl", "shr", "sar", "then", "else", "until", "to", "step"
					Return False
			End Select
			Return True
		End If
		Select token.text
			Case "(", "[", "[]", "+", "-", "~~"
				Return True
		End Select
		Return False
	End Function

	Method ParsePrefixCastExpression:TCastExpressionSyntax()
		Local node:TCastExpressionSyntax = New TCastExpressionSyntax
		node.kind = SYNTAX_CAST_EXPRESSION
		Local start:Int = position
		Advance()
		While position < limit And (Current().text.ToLower() = "ptr" Or Current().text = "[]")
			Advance()
		Wend
		node.targetType = TBlitzMaxTypeParser.Parse(tokens[start..position])
		node.expression = ParseBinary(9)
		node.span = Combine(node.targetType.span, node.expression.span)
		Return node
	End Method

	Method IsParenthesizedPrefixCastStart:Int()
		If position + 3 >= limit Or Current().text <> "(" Then Return False
		If Not IsNameToken(tokens[position + 1]) Then Return False
		Local index:Int = position + 2
		Local hasPointer:Int
		While index < limit And (tokens[index].text.ToLower() = "ptr" Or tokens[index].text = "[]")
			If tokens[index].text.ToLower() = "ptr" Then hasPointer = True
			index :+ 1
		Wend
		If Not hasPointer Or index >= limit Or tokens[index].text = ")" Then Return False
		Return True
	End Method

	Method ParseParenthesizedPrefixCastExpression:TCastExpressionSyntax()
		Local node:TCastExpressionSyntax = New TCastExpressionSyntax
		node.kind = SYNTAX_CAST_EXPRESSION
		node.openToken = Current()
		Advance()
		Local typeStart:Int = position
		Advance()
		While position < limit And (Current().text.ToLower() = "ptr" Or Current().text = "[]")
			Advance()
		Wend
		node.targetType = TBlitzMaxTypeParser.Parse(tokens[typeStart..position])
		If position < limit And Current().text <> ")" Then node.expression = ParseRange()
		If position < limit And Current().text = ")" Then
			node.closeToken = Current()
			Advance()
			node.span = Combine(node.openToken.span, node.closeToken.span)
		Else
			Local last:TSourceSpan = node.targetType.span
			If node.expression Then last = node.expression.span
			node.span = Combine(node.openToken.span, last)
			AddDiagnostic("BMX2113", "Expected ')' after cast expression.", TSourceSpan.Create(node.span.EndOffset(), 0))
		End If
		Return node
	End Method

	Method ParseCastExpression:TCastExpressionSyntax()
		Local node:TCastExpressionSyntax = New TCastExpressionSyntax
		node.kind = SYNTAX_CAST_EXPRESSION
		Local start:Int = position
		Advance()
		While position < limit And (Current().text.ToLower() = "ptr" Or Current().text = "[]")
			Advance()
		Wend
		node.targetType = TBlitzMaxTypeParser.Parse(tokens[start..position])
		node.openToken = Current()
		Advance()
		If position < limit And Current().text <> ")" Then node.expression = ParseRange()
		If position < limit And Current().text = ")" Then
			node.closeToken = Current()
			Advance()
			node.span = Combine(node.targetType.span, node.closeToken.span)
		Else
			Local last:TSourceSpan = node.openToken.span
			If node.expression Then last = node.expression.span
			node.span = Combine(node.targetType.span, last)
			AddDiagnostic("BMX2113", "Expected ')' after cast expression.", TSourceSpan.Create(node.span.EndOffset(), 0))
		End If
		Return node
	End Method

	Method Current:TSyntaxToken()
		If position >= limit Then Return tokens[limit - 1]
		Return tokens[position]
	End Method

	Method Peek:TSyntaxToken(distance:Int)
		Return tokens[Min(limit - 1, position + distance)]
	End Method

	Method Advance()
		If position < limit Then position :+ 1
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan)
		diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span))
	End Method

	Function UnaryPrecedence:Int(token:TSyntaxToken)
		Select token.text.ToLower()
			Case "+", "-", "~~", "not", "varptr", "len", "asc", "chr", "stackalloc", "sizeof", "alignof" Return 9
		End Select
		Return 0
	End Function

	Function BinaryPrecedence:Int(token:TSyntaxToken)
		Select token.text.ToLower()
			Case "or" Return 1
			Case "and" Return 2
			Case "=", "<>", "<", ">", "<=", ">=" Return 3
			Case "|", "~~" Return 4
			Case "&" Return 5
			Case "+", "-" Return 6
			Case "*", "/", "mod", "shl", "shr", "sar" Return 7
			Case "^" Return 8
		End Select
		Return 0
	End Function

	Function IsLiteralToken:Int(token:TSyntaxToken)
		Select token.kind
			Case TOKEN_INTEGER_LITERAL, TOKEN_FLOAT_LITERAL, TOKEN_STRING_LITERAL, TOKEN_MULTILINE_STRING_LITERAL
				Return True
		End Select
		Local lower:String = token.text.ToLower()
		Return lower = "true" Or lower = "false" Or lower = "null" Or lower = "pi"
	End Function

	Function IsNameToken:Int(token:TSyntaxToken)
		Return token.kind = TOKEN_IDENTIFIER Or token.kind = TOKEN_KEYWORD
	End Function

	Function IsBuiltInType:Int(text:String)
		Select text
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam", "float", "double", "float64", "float128", "double128", "int128", "string", "object"
				Return True
		End Select
		Return False
	End Function

	Function Combine:TSourceSpan(first:TSourceSpan, last:TSourceSpan)
		Return TSourceSpan.Create(first.start, last.EndOffset() - first.start)
	End Function

	Function SpanOf:TSourceSpan(values:TSyntaxToken[])
		Return TSourceSpan.Create(values[0].span.start, values[values.length - 1].span.EndOffset() - values[0].span.start)
	End Function

	Function LastExpressionSpan:TSourceSpan(values:TExpressionSyntax[], fallback:TSourceSpan)
		For Local index:Int = values.length - 1 To 0 Step -1
			If values[index] Then Return values[index].span
		Next
		Return fallback
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

	Function ExpressionSlotsToArray:TExpressionSyntax[](list:TList)
		Local result:TExpressionSyntax[] = New TExpressionSyntax[list.Count()]
		Local index:Int
		For Local slot:TExpressionSlot = EachIn list
			result[index] = slot.expression
			index :+ 1
		Next
		Return result
	End Function
End Type
