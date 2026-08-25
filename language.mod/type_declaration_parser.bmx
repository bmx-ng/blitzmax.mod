' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "syntax.bmx"
Import "type_parser.bmx"

Type TTypeDeclarationHeaderParser
	Function Parse:TTypeDeclarationHeaderSyntax(tokens:TSyntaxToken[])
		Local node:TTypeDeclarationHeaderSyntax = New TTypeDeclarationHeaderSyntax
		node.kind = SYNTAX_TYPE_DECLARATION_HEADER
		node.tokens = tokens
		node.genericParameters = New TGenericParameterSyntax[0]
		node.extendsTypes = New TTypeReferenceSyntax[0]
		node.implementedTypes = New TTypeReferenceSyntax[0]
		node.modifierTokens = New TSyntaxToken[0]
		node.metadataTokens = New TSyntaxToken[0]
		node.whereTokens = New TSyntaxToken[0]
		node.constraints = New TGenericConstraintSyntax[0]
		node.trailingTokens = New TSyntaxToken[0]
		If tokens.length = 0 Then
			node.span = TSourceSpan.Create(0, 0)
			Return node
		End If
		node.nameToken = tokens[0]
		node.span = SpanOf(tokens)
		Local cursor:Int = 1

		If cursor < tokens.length And tokens[cursor].text = "<" Then
			node.genericOpenToken = tokens[cursor]
			Local closeIndex:Int = TBlitzMaxTypeParser.FindMatching(tokens, cursor, "<", ">")
			If closeIndex >= 0 Then
				node.genericCloseToken = tokens[closeIndex]
				node.genericParameters = ParseGenericParameters(tokens[cursor + 1..closeIndex])
				cursor = closeIndex + 1
			Else
				node.genericParameters = ParseGenericParameters(tokens[cursor + 1..])
				cursor = tokens.length
			End If
		End If

		If cursor < tokens.length And tokens[cursor].text.ToLower() = "where" Then
			node.whereToken = tokens[cursor]
			Local constraintTokenCount:Int
			node.constraints = ParseConstraints(tokens[cursor + 1..], constraintTokenCount)
			node.whereTokens = tokens[cursor + 1..cursor + 1 + constraintTokenCount]
			cursor :+ 1 + constraintTokenCount
		End If

		If cursor < tokens.length And tokens[cursor].text.ToLower() = "extends" Then
			node.extendsToken = tokens[cursor]
			Local clauseEnd:Int = FindClauseEnd(tokens, cursor + 1, True)
			node.extendsTypes = ParseTypeList(tokens[cursor + 1..clauseEnd])
			cursor = clauseEnd
		End If

		If cursor < tokens.length And tokens[cursor].text.ToLower() = "implements" Then
			node.implementsToken = tokens[cursor]
			Local clauseEnd:Int = FindClauseEnd(tokens, cursor + 1, False)
			node.implementedTypes = ParseTypeList(tokens[cursor + 1..clauseEnd])
			cursor = clauseEnd
		End If

		Local modifiers:TList = New TList
		While cursor < tokens.length
			Local lower:String = tokens[cursor].text.ToLower()
			If lower <> "abstract" And lower <> "final" Then Exit
			modifiers.AddLast(tokens[cursor])
			cursor :+ 1
		Wend
		node.modifierTokens = TokensToArray(modifiers)
		If cursor < tokens.length And tokens[cursor].text = "{" Then
			node.metadataTokens = tokens[cursor..]
			cursor = tokens.length
		End If
		If cursor < tokens.length Then node.trailingTokens = tokens[cursor..]
		Return node
	End Function

	Function ParseConstraints:TGenericConstraintSyntax[](tokens:TSyntaxToken[], consumed:Int Var)
		Local result:TList = New TList
		Local cursor:Int
		Local allFinished:Int
		While cursor < tokens.length
			Local node:TGenericConstraintSyntax = New TGenericConstraintSyntax
			node.kind = SYNTAX_GENERIC_CONSTRAINT
			node.parameterNameToken = tokens[cursor]
			Local start:Int = tokens[cursor].span.start
			cursor :+ 1
			If cursor < tokens.length And tokens[cursor].text.ToLower() = "extends" Then
				node.extendsToken = tokens[cursor]
				cursor :+ 1
			End If
			Local types:TList = New TList
			Local conjunctions:TList = New TList
			Local typeStart:Int = cursor
			Local angles:Int
			Local brackets:Int
			Local finished:Int
			While cursor <= tokens.length
				Local split:Int = cursor = tokens.length
				Local comma:Int
				Local conjunction:Int
				If Not split Then
					If angles = 0 And brackets = 0 Then
						Local lower:String = tokens[cursor].text.ToLower()
						comma = tokens[cursor].text = ","
						conjunction = lower = "and"
						If cursor > typeStart And (lower = "extends" Or lower = "implements" Or lower = "abstract" Or lower = "final" Or tokens[cursor].text = "{") Then
							allFinished = True
							finished = True
							split = True
						End If
						If comma Or conjunction Then split = True
					End If
				End If
				If split Then
					If cursor > typeStart Then types.AddLast(TBlitzMaxTypeParser.Parse(tokens[typeStart..cursor]))
					If cursor = tokens.length Then
						finished = True
					Else If conjunction Then
						conjunctions.AddLast(tokens[cursor])
						cursor :+ 1
						typeStart = cursor
						Continue
					Else If comma Then
						node.separatorToken = tokens[cursor]
						cursor :+ 1
						finished = True
					End If
					If finished Then Exit
				End If
				If cursor < tokens.length Then
					Select tokens[cursor].text
						Case "<" angles :+ 1
						Case ">" angles :- 1
						Case "[" brackets :+ 1
						Case "]" brackets :- 1
					End Select
					cursor :+ 1
				End If
			Wend
			node.constraintTypes = TypesToArray(types)
			node.andTokens = TokensToArray(conjunctions)
			Local endOffset:Int = node.parameterNameToken.span.EndOffset()
			If node.constraintTypes.length Then endOffset = node.constraintTypes[node.constraintTypes.length - 1].span.EndOffset()
			If node.separatorToken Then endOffset = node.separatorToken.span.EndOffset()
			node.span = TSourceSpan.Create(start, endOffset - start)
			result.AddLast(node)
			If allFinished Then Exit
		Wend
		consumed = cursor
		Local values:TGenericConstraintSyntax[] = New TGenericConstraintSyntax[result.Count()]
		Local index:Int
		For Local value:TGenericConstraintSyntax = EachIn result
			values[index] = value
			index :+ 1
		Next
		Return values
	End Function

	Function ParseGenericParameters:TGenericParameterSyntax[](tokens:TSyntaxToken[])
		Local result:TList = New TList
		Local start:Int
		For Local index:Int = 0 To tokens.length
			If index = tokens.length Or tokens[index].text = "," Then
				If index > start Then
					Local parameter:TGenericParameterSyntax = New TGenericParameterSyntax
					parameter.kind = SYNTAX_GENERIC_PARAMETER
					parameter.nameToken = tokens[start]
					parameter.span = TSourceSpan.Create(tokens[start].span.start, tokens[index - 1].span.EndOffset() - tokens[start].span.start)
					If index < tokens.length Then parameter.separatorToken = tokens[index]
					result.AddLast(parameter)
				End If
				start = index + 1
			End If
		Next
		Local values:TGenericParameterSyntax[] = New TGenericParameterSyntax[result.Count()]
		Local valueIndex:Int
		For Local value:TGenericParameterSyntax = EachIn result
			values[valueIndex] = value
			valueIndex :+ 1
		Next
		Return values
	End Function

	Function ParseTypeList:TTypeReferenceSyntax[](tokens:TSyntaxToken[])
		Local result:TList = New TList
		Local start:Int
		Local angles:Int
		Local brackets:Int
		For Local index:Int = 0 To tokens.length
			Local split:Int = index = tokens.length
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
				If index > start Then result.AddLast(TBlitzMaxTypeParser.Parse(tokens[start..index]))
				start = index + 1
			End If
		Next
		Local values:TTypeReferenceSyntax[] = New TTypeReferenceSyntax[result.Count()]
		Local valueIndex:Int
		For Local value:TTypeReferenceSyntax = EachIn result
			values[valueIndex] = value
			valueIndex :+ 1
		Next
		Return values
	End Function

	Function FindClauseEnd:Int(tokens:TSyntaxToken[], start:Int, stopAtImplements:Int)
		Local angles:Int
		Local brackets:Int
		For Local index:Int = start Until tokens.length
			If angles = 0 And brackets = 0 Then
				Local lower:String = tokens[index].text.ToLower()
				If lower = "abstract" Or lower = "final" Or tokens[index].text = "{" Then Return index
				If stopAtImplements And lower = "implements" Then Return index
			End If
			Select tokens[index].text
				Case "<" angles :+ 1
				Case ">" angles :- 1
				Case "[" brackets :+ 1
				Case "]" brackets :- 1
			End Select
		Next
		Return tokens.length
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

	Function SpanOf:TSourceSpan(tokens:TSyntaxToken[])
		Return TSourceSpan.Create(tokens[0].span.start, tokens[tokens.length - 1].span.EndOffset() - tokens[0].span.start)
	End Function
End Type
