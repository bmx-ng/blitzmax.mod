' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "syntax.bmx"

Type TBlitzMaxTypeParser
	' In declarations, a generic close immediately followed by an initializer
	' is lexed as the ordinary >= operator. Split it only while a type argument
	' list is open; expression uses of >= remain untouched.
	Function SplitGenericCloseAssignment:TSyntaxToken[](tokens:TSyntaxToken[])
		Local result:TList = New TList
		Local angles:Int
		Local seenAssignment:Int
		For Local token:TSyntaxToken = EachIn tokens
			If Not seenAssignment And token.text = "<" Then
				angles :+ 1
				result.AddLast(token)
			Else If Not seenAssignment And token.text = ">" And angles > 0 Then
				angles :- 1
				result.AddLast(token)
			Else If Not seenAssignment And token.text = ">=" And angles > 0 Then
				Local closeToken:TSyntaxToken = TSyntaxToken.Create(token.kind, TSourceSpan.Create(token.span.start, 1), ">", token.leadingTrivia, Null, token.missing)
				Local assignmentToken:TSyntaxToken = TSyntaxToken.Create(token.kind, TSourceSpan.Create(token.span.start + 1, 1), "=", Null, token.trailingTrivia, token.missing)
				result.AddLast(closeToken)
				result.AddLast(assignmentToken)
				angles :- 1
				If angles = 0 Then seenAssignment = True
			Else
				If token.text = "=" And angles = 0 Then seenAssignment = True
				result.AddLast(token)
			End If
		Next
		Return TokensToArray(result)
	End Function

	Function Parse:TTypeReferenceSyntax(tokens:TSyntaxToken[])
		If tokens.length = 0 Then Return Null
		Local node:TTypeReferenceSyntax = New TTypeReferenceSyntax
		node.kind = SYNTAX_TYPE_REFERENCE
		node.tokens = tokens
		node.span = SpanOf(tokens)
		Local index:Int

		If IsTypeMarker(tokens[0].text) Then
			node.markerToken = tokens[0]
			index = 1
		End If

		Local nameList:TList = New TList
		While index < tokens.length
			Local lower:String = tokens[index].text.ToLower()
			If tokens[index].text = "<" Or tokens[index].text = "[" Or tokens[index].text = "[]" Or tokens[index].text = "*" Or lower = "ptr" Then Exit
			nameList.AddLast(tokens[index])
			index :+ 1
		Wend
		node.nameTokens = TokensToArray(nameList)

		If index < tokens.length And tokens[index].text = "<" Then
			Local genericEnd:Int = FindMatching(tokens, index, "<", ">")
			If genericEnd > index Then
				If IsClosureName(node.nameTokens) Then
					node.closureSignature = ParseClosureSignature(tokens[index + 1..genericEnd])
				Else
					node.genericArguments = ParseTypeList(tokens[index + 1..genericEnd])
				End If
				index = genericEnd + 1
			End If
		End If

		Local pointers:TList = New TList
		Local ranks:Int[]
		Local suffixes:TList = New TList
		While index < tokens.length
			If tokens[index].text.ToLower() = "ptr" Or tokens[index].text = "*" Then
				pointers.AddLast(tokens[index])
				Local suffix:TTypeSuffixSyntax = New TTypeSuffixSyntax
				suffix.kind = SYNTAX_TYPE_SUFFIX
				suffix.suffixKind = TYPE_SUFFIX_POINTER
				suffix.tokens = [tokens[index]]
				suffix.span = tokens[index].span
				suffixes.AddLast(suffix)
				index :+ 1
			Else If tokens[index].text = "[]" Then
				ranks :+ [1]
				Local suffix:TTypeSuffixSyntax = New TTypeSuffixSyntax
				suffix.kind = SYNTAX_TYPE_SUFFIX
				suffix.suffixKind = TYPE_SUFFIX_ARRAY
				suffix.tokens = [tokens[index]]
				suffix.rank = 1
				suffix.span = tokens[index].span
				suffixes.AddLast(suffix)
				index :+ 1
			Else If tokens[index].text = "[" Then
				Local close:Int = FindMatching(tokens, index, "[", "]")
				If close < 0 Then Exit
				Local rank:Int = 1
				For Local part:Int = index + 1 Until close
					If tokens[part].text = "," Then rank :+ 1
				Next
				ranks :+ [rank]
				Local suffix:TTypeSuffixSyntax = New TTypeSuffixSyntax
				suffix.kind = SYNTAX_TYPE_SUFFIX
				suffix.suffixKind = TYPE_SUFFIX_ARRAY
				suffix.tokens = tokens[index..close + 1]
				suffix.rank = rank
				suffix.span = SpanOf(suffix.tokens)
				suffixes.AddLast(suffix)
				index = close + 1
			Else
				index :+ 1
			End If
		Wend
		node.pointerTokens = TokensToArray(pointers)
		node.arrayRanks = ranks
		node.suffixes = SuffixesToArray(suffixes)
		Return node
	End Function

	Function IsClosureName:Int(tokens:TSyntaxToken[])
		Return tokens.length = 1 And tokens[0].text.ToLower() = "closure"
	End Function

	Function ParseClosureSignature:TCallableTypeSyntax(tokens:TSyntaxToken[])
		Local callable:TCallableTypeSyntax = New TCallableTypeSyntax
		callable.kind = SYNTAX_CALLABLE_TYPE
		callable.parameters = New TParameterSyntax[0]
		callable.suffixes = New TTypeSuffixSyntax[0]
		If Not tokens.length Then Return callable
		callable.span = SpanOf(tokens)
		Local openIndex:Int = FindClosureSignatureOpen(tokens)
		If openIndex < 0 Then Return callable
		callable.openParenToken = tokens[openIndex]
		If openIndex > 0 Then callable.returnType = Parse(tokens[..openIndex])
		Local closeIndex:Int = FindMatching(tokens, openIndex, "(", ")")
		If closeIndex < 0 Then closeIndex = tokens.length Else callable.closeParenToken = tokens[closeIndex]
		callable.parameters = ParseClosureParameters(tokens[openIndex + 1..closeIndex])
		Return callable
	End Function

	Function FindClosureSignatureOpen:Int(tokens:TSyntaxToken[])
		Local angles:Int
		Local brackets:Int
		For Local index:Int = 0 Until tokens.length
			Select tokens[index].text
				Case "<"
					angles :+ 1
				Case ">"
					If angles > 0 Then angles :- 1
				Case "["
					brackets :+ 1
				Case "]"
					If brackets > 0 Then brackets :- 1
				Case "("
					If angles = 0 And brackets = 0 Then Return index
			End Select
		Next
		Return -1
	End Function

	Function ParseClosureParameters:TParameterSyntax[](tokens:TSyntaxToken[])
		Local result:TList = New TList
		Local start:Int
		Local parens:Int
		Local angles:Int
		Local brackets:Int
		For Local index:Int = 0 To tokens.length
			Local split:Int = index = tokens.length
			If Not split Then
				Select tokens[index].text
					Case "(" parens :+ 1
					Case ")" parens :- 1
					Case "<" angles :+ 1
					Case ">" angles :- 1
					Case "[" brackets :+ 1
					Case "]" brackets :- 1
					Case ","; If parens = 0 And angles = 0 And brackets = 0 Then split = True
				End Select
			End If
			If split Then
				If index > start Then result.AddLast(ParseClosureParameter(tokens[start..index]))
				start = index + 1
			End If
		Next
		Local parameters:TParameterSyntax[] = New TParameterSyntax[result.Count()]
		Local index:Int
		For Local parameter:TParameterSyntax = EachIn result; parameters[index] = parameter; index :+ 1; Next
		Return parameters
	End Function

	Function ParseClosureParameter:TParameterSyntax(tokens:TSyntaxToken[])
		Local parameter:TParameterSyntax = New TParameterSyntax
		parameter.kind = SYNTAX_PARAMETER
		parameter.span = SpanOf(tokens)
		parameter.modifierTokens = New TSyntaxToken[0]
		parameter.nameToken = tokens[0]
		Local typeEnd:Int = tokens.length
		If typeEnd > 1 And tokens[typeEnd - 1].text.ToLower() = "var" Then parameter.varToken = tokens[typeEnd - 1]; typeEnd :- 1
		If typeEnd > 1 Then parameter.declaredType = Parse(tokens[1..typeEnd])
		Return parameter
	End Function

	Function ParseTypeList:TTypeReferenceSyntax[](tokens:TSyntaxToken[])
		Local result:TList = New TList
		Local start:Int
		Local angle:Int
		Local bracket:Int
		For Local index:Int = 0 To tokens.length
			Local split:Int = index = tokens.length
			If Not split Then
				Select tokens[index].text
					Case "<" angle :+ 1
					Case ">" angle :- 1
					Case "[" bracket :+ 1
					Case "]" bracket :- 1
					Case ","
						If angle = 0 And bracket = 0 Then split = True
				End Select
			End If
			If split Then
				If index > start Then result.AddLast(Parse(tokens[start..index]))
				start = index + 1
			End If
		Next
		Return TypesToArray(result)
	End Function

	Function IsTypeMarker:Int(text:String)
		Select text
			Case ":", "%", "%%", "|", "||", "#", "!", "$", "@", "@@", "?", "~~", "/", "%z", "%v", "%e", "%w", "%x", "%j", "!k", "!m", "!h"
				Return True
		End Select
		Return False
	End Function

	Function FindMatching:Int(tokens:TSyntaxToken[], start:Int, openText:String, closeText:String)
		Local depth:Int
		For Local index:Int = start Until tokens.length
			If tokens[index].text = openText Then depth :+ 1
			If tokens[index].text = closeText Then
				depth :- 1
				If depth = 0 Then Return index
			End If
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

	Function TypesToArray:TTypeReferenceSyntax[](list:TList)
		Local result:TTypeReferenceSyntax[] = New TTypeReferenceSyntax[list.Count()]
		Local index:Int
		For Local value:TTypeReferenceSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function SuffixesToArray:TTypeSuffixSyntax[](list:TList)
		Local result:TTypeSuffixSyntax[] = New TTypeSuffixSyntax[list.Count()]
		Local index:Int
		For Local value:TTypeSuffixSyntax = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function
End Type
