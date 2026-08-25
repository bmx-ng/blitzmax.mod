' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "expression_parser.bmx"
Import "type_parser.bmx"
Import "type_declaration_parser.bmx"

Type TBlitzMaxSignatureParser
	Function Parse:TRoutineSignatureSyntax(tokens:TSyntaxToken[], diagnostics:TList)
		Local node:TRoutineSignatureSyntax = New TRoutineSignatureSyntax
		node.kind = SYNTAX_ROUTINE_SIGNATURE
		node.genericParameters = New TGenericParameterSyntax[0]
		node.parameters = New TParameterSyntax[0]
		node.whereTokens = New TSyntaxToken[0]
		node.constraints = New TGenericConstraintSyntax[0]
		node.modifierTokens = New TSyntaxToken[0]
		If tokens.length = 0 Then Return node
		node.span = SpanOf(tokens)
		node.nameToken = tokens[0]
		Local cursor:Int = 1
		node.operatorTokens = New TSyntaxToken[0]

		If node.nameToken.text.ToLower() = "operator" Then
			Local openOperatorIndex:Int = FindToken(tokens, "(", cursor)
			If openOperatorIndex < 0 Then openOperatorIndex = tokens.length
			Local returnStart:Int = openOperatorIndex
			For Local index:Int = cursor Until openOperatorIndex
				If TBlitzMaxTypeParser.IsTypeMarker(tokens[index].text) And index > cursor Then returnStart = index
			Next
			If returnStart > cursor Then
				node.operatorTokens = tokens[cursor..returnStart]
				For Local operatorToken:TSyntaxToken = EachIn node.operatorTokens
					node.operatorName = node.operatorName + operatorToken.text
				Next
				cursor = returnStart
			End If
		End If

		If cursor < tokens.length And tokens[cursor].text = "<" Then
			node.genericOpenToken = tokens[cursor]
			Local closeGenericIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, cursor, "<", ">")
			If closeGenericIndex >= 0 Then
				node.genericCloseToken = tokens[closeGenericIndex]
				node.genericParameters = TTypeDeclarationHeaderParser.ParseGenericParameters(tokens[cursor + 1..closeGenericIndex])
				cursor = closeGenericIndex + 1
			Else
				node.genericParameters = TTypeDeclarationHeaderParser.ParseGenericParameters(tokens[cursor + 1..])
				diagnostics.AddLast(TDiagnostic.Create("BMX2203", "Expected '>' after routine generic parameters.", DIAGNOSTIC_ERROR, node.span))
				cursor = tokens.length
			End If
		End If

		Local openIndex:Int = FindSignatureOpen(tokens, cursor)
		If openIndex < 0 Then
			diagnostics.AddLast(TDiagnostic.Create("BMX2200", "Expected '(' in routine declaration.", DIAGNOSTIC_ERROR, node.span))
			node.returnType = TBlitzMaxTypeParser.Parse(tokens[cursor..])
			Return node
		End If

		Local firstCloseIndex:Int = FindMatchingParen(tokens, openIndex)
		Local callableEndIndex:Int = firstCloseIndex + 1
		If firstCloseIndex >= 0 And callableEndIndex < tokens.length And (tokens[callableEndIndex].kind = TOKEN_STRING_LITERAL Or tokens[callableEndIndex].text = "W") Then callableEndIndex :+ 1
		If firstCloseIndex >= 0 And callableEndIndex < tokens.length And tokens[callableEndIndex].text = "(" Then
			node.callableReturnType = ParseCallableType(tokens[cursor..callableEndIndex], diagnostics)
			openIndex = callableEndIndex
		Else
			node.returnType = TBlitzMaxTypeParser.Parse(tokens[cursor..openIndex])
		End If
		node.openParenToken = tokens[openIndex]
		Local closeIndex:Int = FindMatchingParen(tokens, openIndex)
		If closeIndex < 0 Then
			closeIndex = tokens.length
			diagnostics.AddLast(TDiagnostic.Create("BMX2201", "Expected ')' in routine declaration.", DIAGNOSTIC_ERROR, TSourceSpan.Create(node.span.EndOffset(), 0)))
		Else
			node.closeParenToken = tokens[closeIndex]
		End If

		node.parameters = ParseParameters(tokens[openIndex + 1..closeIndex], diagnostics)
		cursor = closeIndex + 1
		If cursor < tokens.length And tokens[cursor].text.ToLower() = "where" Then
			node.whereToken = tokens[cursor]
			Local constraintEnd:Int = FindRoutineModifierStart(tokens, cursor + 1)
			Local consumed:Int
			node.constraints = TTypeDeclarationHeaderParser.ParseConstraints(tokens[cursor + 1..constraintEnd], consumed)
			node.whereTokens = tokens[cursor + 1..constraintEnd]
			cursor = constraintEnd
		End If
		If cursor < tokens.length Then node.modifierTokens = tokens[cursor..]
		Return node
	End Function

	Function FindRoutineModifierStart:Int(tokens:TSyntaxToken[], start:Int)
		Local angles:Int
		Local brackets:Int
		Local parens:Int
		For Local index:Int = start Until tokens.length
			If angles = 0 And brackets = 0 And parens = 0 Then
				Local lower:String = tokens[index].text.ToLower()
				If lower = "abstract" Or lower = "default" Or lower = "final" Or lower = "override" Or lower = "export" Or lower = "inline" Or lower = "nodebug" Or lower = "stdcall" Or tokens[index].text = "=" Or tokens[index].text = "{" Then Return index
			End If
			Select tokens[index].text
				Case "<" angles :+ 1
				Case ">" angles :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
				Case "(" parens :+ 1
				Case ")" parens :- 1
			End Select
		Next
		Return tokens.length
	End Function

	Function ParseParameters:TParameterSyntax[](tokens:TSyntaxToken[], diagnostics:TList)
		Local result:TList = New TList
		Local start:Int
		Local parens:Int
		Local brackets:Int
		Local angles:Int
		For Local index:Int = 0 To tokens.length
			Local split:Int = index = tokens.length
			If Not split Then
				Select tokens[index].text
					Case "(" parens :+ 1
					Case ")" parens :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
					Case "<" angles :+ 1
					Case ">" angles :- 1
					Case ">="
						If angles > 0 Then angles :- 1
					Case ","
						If parens = 0 And brackets = 0 And angles = 0 Then split = True
				End Select
			End If
			If split Then
				If index > start Then result.AddLast(ParseParameter(tokens[start..index], diagnostics))
				start = index + 1
			End If
		Next
		Return ParametersToArray(result)
	End Function

	Function ParseParameter:TParameterSyntax(tokens:TSyntaxToken[], diagnostics:TList)
		tokens = TBlitzMaxTypeParser.SplitGenericCloseAssignment(tokens)
		Local node:TParameterSyntax = New TParameterSyntax
		node.kind = SYNTAX_PARAMETER
		node.span = SpanOf(tokens)
		Local index:Int
		Local modifiers:TList = New TList
		While index < tokens.length And IsParameterModifier(tokens[index].text.ToLower())
			modifiers.AddLast(tokens[index])
			index :+ 1
		Wend
		node.modifierTokens = TokensToArray(modifiers)
		For Local modifier:TSyntaxToken = EachIn node.modifierTokens
			If modifier.text.ToLower() = "staticarray" Then node.staticArrayToken = modifier
		Next

		If index < tokens.length Then
			node.nameToken = tokens[index]
			index :+ 1
		Else
			diagnostics.AddLast(TDiagnostic.Create("BMX2202", "Expected a parameter name.", DIAGNOSTIC_ERROR, node.span))
			Return node
		End If

		Local assignmentIndex:Int = FindTopLevel(tokens, "=", index)
		Local typeEnd:Int = tokens.length
		If assignmentIndex >= 0 Then typeEnd = assignmentIndex
		If typeEnd > index And tokens[typeEnd - 1].text.ToLower() = "var" Then
			node.varToken = tokens[typeEnd - 1]
			typeEnd :- 1
		End If
		Local typeTokens:TSyntaxToken[] = tokens[index..typeEnd]
		If node.staticArrayToken Then typeTokens = ExtractStaticArrayBound(typeTokens, node, diagnostics)
		node.declaredType = TBlitzMaxTypeParser.Parse(typeTokens)
		Local callableOpen:Int = FindSignatureOpen(tokens, index)
		If callableOpen >= 0 And callableOpen < typeEnd Then
			node.callableType = ParseCallableType(tokens[index..typeEnd], diagnostics)
			node.declaredType = Null
		End If
		If assignmentIndex >= 0 Then
			node.assignmentToken = tokens[assignmentIndex]
			node.defaultValue = TBlitzMaxExpressionParser.Parse(tokens[assignmentIndex + 1..], diagnostics)
		End If
		Return node
	End Function

	Function ExtractStaticArrayBound:TSyntaxToken[](tokens:TSyntaxToken[], node:TParameterSyntax, diagnostics:TList)
		Local closeIndex:Int = tokens.length - 1
		If closeIndex < 2 Or tokens[closeIndex].text <> "]" Then
			diagnostics.AddLast(TDiagnostic.Create("BMX2210", "StaticArray parameter requires a fixed length in brackets.", DIAGNOSTIC_ERROR, node.span))
			Return tokens
		End If
		Local openIndex:Int = closeIndex - 1
		While openIndex >= 0 And tokens[openIndex].text <> "["
			openIndex :- 1
		Wend
		If openIndex < 0 Or openIndex + 1 = closeIndex Then
			diagnostics.AddLast(TDiagnostic.Create("BMX2210", "StaticArray parameter requires a fixed length expression.", DIAGNOSTIC_ERROR, node.span))
			Return tokens
		End If
		Local bound:TStaticArrayBoundSyntax = New TStaticArrayBoundSyntax
		bound.kind = SYNTAX_STATIC_ARRAY_BOUND
		bound.openToken = tokens[openIndex]
		bound.closeToken = tokens[closeIndex]
		bound.lengthExpression = TBlitzMaxExpressionParser.Parse(tokens[openIndex + 1..closeIndex], diagnostics)
		bound.span = TSourceSpan.Create(bound.openToken.span.start, bound.closeToken.span.EndOffset() - bound.openToken.span.start)
		node.staticArrayBound = bound
		Return tokens[..openIndex]
	End Function

	Function ParseCallableType:TCallableTypeSyntax(tokens:TSyntaxToken[], diagnostics:TList)
		If tokens.length = 0 Then Return Null
		Local openIndex:Int = FindSignatureOpen(tokens, 0)
		If openIndex < 0 Then Return Null
		Local node:TCallableTypeSyntax = New TCallableTypeSyntax
		node.kind = SYNTAX_CALLABLE_TYPE
		node.span = SpanOf(tokens)
		node.returnType = TBlitzMaxTypeParser.Parse(tokens[..openIndex])
		node.openParenToken = tokens[openIndex]
		Local closeIndex:Int = FindMatchingParen(tokens, openIndex)
		If closeIndex < 0 Then
			closeIndex = tokens.length
			diagnostics.AddLast(TDiagnostic.Create("BMX2204", "Expected ')' in callable type.", DIAGNOSTIC_ERROR, TSourceSpan.Create(node.span.EndOffset(), 0)))
		Else
			node.closeParenToken = tokens[closeIndex]
		End If
		node.parameters = ParseParameters(tokens[openIndex + 1..closeIndex], diagnostics)
		Local suffixStart:Int = closeIndex + 1
		If suffixStart < tokens.length And (tokens[suffixStart].kind = TOKEN_STRING_LITERAL Or tokens[suffixStart].text = "W") Then
			node.callingConventionToken = tokens[suffixStart]
			suffixStart :+ 1
		End If
		If suffixStart < tokens.length Then
			Local outerType:TTypeReferenceSyntax = TBlitzMaxTypeParser.Parse(tokens[suffixStart..])
			If outerType Then node.suffixes = outerType.suffixes
		End If
		Return node
	End Function

	Function IsParameterModifier:Int(text:String)
		Return text = "staticarray"
	End Function

	Function FindToken:Int(tokens:TSyntaxToken[], text:String, start:Int)
		For Local index:Int = start Until tokens.length
			If tokens[index].text = text Then Return index
		Next
		Return -1
	End Function

	Function FindSignatureOpen:Int(tokens:TSyntaxToken[], start:Int)
		Local angles:Int
		Local brackets:Int
		For Local index:Int = start Until tokens.length
			If tokens[index].text = "(" And angles = 0 And brackets = 0 Then Return index
			Select tokens[index].text
				Case "<" angles :+ 1
				Case ">" angles :- 1
				Case ">="; If angles > 0 Then angles :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
		Next
		Return -1
	End Function

	Function FindMatchingParen:Int(tokens:TSyntaxToken[], start:Int)
		Local depth:Int
		For Local index:Int = start Until tokens.length
			If tokens[index].text = "(" Then depth :+ 1
			If tokens[index].text = ")" Then
				depth :- 1
				If depth = 0 Then Return index
			End If
		Next
		Return -1
	End Function

	Function FindTopLevel:Int(tokens:TSyntaxToken[], text:String, start:Int)
		Local parens:Int
		Local brackets:Int
		Local angles:Int
		For Local index:Int = start Until tokens.length
			Select tokens[index].text
				Case "(" parens :+ 1
				Case ")" parens :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
				Case "<" angles :+ 1
				Case ">" If angles > 0 Then angles :- 1
			End Select
			If parens = 0 And brackets = 0 And angles = 0 And tokens[index].text = text Then Return index
		Next
		Return -1
	End Function

	Function SpanOf:TSourceSpan(tokens:TSyntaxToken[])
		Return TSourceSpan.Create(tokens[0].span.start, tokens[tokens.length - 1].span.EndOffset() - tokens[0].span.start)
	End Function

	Function TokensToArray:TSyntaxToken[](list:TList)
		Local result:TSyntaxToken[] = New TSyntaxToken[list.Count()]
		Local index:Int
		For Local value:TSyntaxToken = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function ParametersToArray:TParameterSyntax[](list:TList)
		Local result:TParameterSyntax[] = New TParameterSyntax[list.Count()]
		Local index:Int
		For Local value:TParameterSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function
End Type
