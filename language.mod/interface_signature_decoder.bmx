' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "interface_model.bmx"
Import "expression_parser.bmx"
Import "lexer.bmx"
Import "signature_parser.bmx"
Import "type_parser.bmx"

Type TInterfaceSignatureDecoder
	Function Decode(file:TInterfaceFile)
		For Local record:TInterfaceRecord = EachIn file.declarations
			DecodeRecord(record)
		Next
	End Function

	Function DecodeRecord(record:TInterfaceRecord)
		Select record.kind
			Case INTERFACE_RECORD_TYPE
				Local headerEnd:Int = record.signatureText.Find("^")
				If headerEnd < 0 Then headerEnd = record.signatureText.length
				Local headerText:String = record.signatureText[..headerEnd]
				If record.genericTemplateReference.length Then
					record.typeHeaderSyntax = TTypeDeclarationHeaderParser.Parse(LexTokens(headerText))
					If record.typeHeaderSyntax And record.typeHeaderSyntax.nameToken Then record.name = record.typeHeaderSyntax.nameToken.text
				End If
				record.baseTypeSyntax = DecodeType(record.baseTypeText)
				record.implementedTypeSyntax = New TTypeReferenceSyntax[record.implementedTypeTexts.length]
				For Local index:Int = 0 Until record.implementedTypeTexts.length
					record.implementedTypeSyntax[index] = DecodeType(record.implementedTypeTexts[index])
				Next
			Case INTERFACE_RECORD_ENUM
				record.baseTypeSyntax = DecodeType(record.baseTypeText)
			Case INTERFACE_RECORD_FUNCTION, INTERFACE_RECORD_METHOD, INTERFACE_RECORD_TYPE_FUNCTION
				record.routineSignature = DecodeRoutine(record)
			Case INTERFACE_RECORD_CONST, INTERFACE_RECORD_GLOBAL, INTERFACE_RECORD_FIELD
				DecodeVariable(record)
				If record.kind = INTERFACE_RECORD_CONST Then record.valueSyntax = DecodeExpression(record.valueText)
			Case INTERFACE_RECORD_ENUM_VALUE
				record.valueSyntax = DecodeExpression(record.valueText)
		End Select
		For Local member:TInterfaceRecord = EachIn record.members
			DecodeRecord(member)
		Next
	End Function

	Function DecodeVariable(record:TInterfaceRecord)
		Local text:String = record.signatureText
		If record.kind = INTERFACE_RECORD_FIELD And text.length Then text = text[1..]
		While text.EndsWith("`")
			text = text[..text.length - 1]
		Wend
		If text.EndsWith("&") Then text = text[..text.length - 1]
		Local tokens:TSyntaxToken[] = LexTokens(text)
		If tokens.length < 2 Then Return
		If record.isStaticArray Then
			Local separator:Int = FindTokenText(tokens, "&", 1)
			If separator > 1 Then record.declaredTypeSyntax = TBlitzMaxTypeParser.Parse(tokens[1..separator])
			If separator >= 0 And separator + 1 < tokens.length Then record.staticArrayBound = DecodeStaticArrayBound(tokens[separator + 1..])
			Return
		End If
		tokens = NormalizeDynamicArrayReferenceMarkers(tokens)
		Local callableOpenIndex:Int = FindTopLevelCallableOpen(tokens, 1)
		If callableOpenIndex >= 0 Then
			Local diagnostics:TList = New TList
			record.callableTypeSyntax = TBlitzMaxSignatureParser.ParseCallableType(tokens[1..], diagnostics)
			If record.callableTypeSyntax Then DecodeStaticArrayParameterList(record.callableTypeSyntax.parameters, tokens, callableOpenIndex)
			Return
		End If
		record.declaredTypeSyntax = TBlitzMaxTypeParser.Parse(tokens[1..])
	End Function

	Function FindTopLevelCallableOpen:Int(tokens:TSyntaxToken[], start:Int)
		Local angleDepth:Int
		Local bracketDepth:Int
		For Local index:Int = start Until tokens.length
			Select tokens[index].text
				Case "<"
					angleDepth :+ 1
				Case ">"
					If angleDepth > 0 Then angleDepth :- 1
				Case "["
					bracketDepth :+ 1
				Case "]"
					If bracketDepth > 0 Then bracketDepth :- 1
				Case "("
					If angleDepth = 0 And bracketDepth = 0 Then Return index
			End Select
		Next
		Return -1
	End Function

	Function DecodeStaticArrayBound:TStaticArrayBoundSyntax(tokens:TSyntaxToken[])
		If tokens.length < 3 Or tokens[0].text <> "[" Or tokens[tokens.length - 1].text <> "]" Then Return Null
		Local diagnostics:TList = New TList
		Local bound:TStaticArrayBoundSyntax = New TStaticArrayBoundSyntax
		bound.kind = SYNTAX_STATIC_ARRAY_BOUND
		bound.openToken = tokens[0]
		bound.closeToken = tokens[tokens.length - 1]
		bound.lengthExpression = TBlitzMaxExpressionParser.Parse(tokens[1..tokens.length - 1], diagnostics)
		bound.span = TSourceSpan.Create(bound.openToken.span.start, bound.closeToken.span.EndOffset() - bound.openToken.span.start)
		Return bound
	End Function

	Function FindTokenText:Int(tokens:TSyntaxToken[], text:String, start:Int)
		For Local index:Int = start Until tokens.length
			If tokens[index].text = text Then Return index
		Next
		Return -1
	End Function

	Function DecodeRoutine:TRoutineSignatureSyntax(record:TInterfaceRecord)
		Local text:String = record.signatureText
		If record.kind = INTERFACE_RECORD_METHOD Or record.kind = INTERFACE_RECORD_TYPE_FUNCTION Then text = text[1..]
		If record.flags.length And IsCompactFlags(record.flags) And text.EndsWith(record.flags) Then text = text[..text.length - record.flags.length]
		Local encodedTokens:TSyntaxToken[] = LexTokens(text)
		Local diagnostics:TList = New TList
		Local signatureTokens:TSyntaxToken[] = NormalizeDynamicArrayReferenceMarkers(encodedTokens)
		signatureTokens = NormalizeExternalInterfaceReferenceMarkers(signatureTokens)
		Local signature:TRoutineSignatureSyntax = TBlitzMaxSignatureParser.Parse(signatureTokens, diagnostics)
		If signature Then
			DecodeStaticArrayParameters(signature, encodedTokens)
			For Local parameter:TParameterSyntax = EachIn signature.parameters
				parameter.defaultValue = NormalizeEncodedDefault(parameter.defaultValue)
			Next
		End If
		Return signature
	End Function

	Function DecodeStaticArrayParameters(signature:TRoutineSignatureSyntax, tokens:TSyntaxToken[])
		If Not signature Or Not signature.parameters.length Then Return
		Local openIndex:Int = FindTokenText(tokens, "(", 0)
		If openIndex < 0 Then Return
		DecodeStaticArrayParameterList(signature.parameters, tokens, openIndex)
	End Function

	Function DecodeStaticArrayParameterList(parameters:TParameterSyntax[], tokens:TSyntaxToken[], openIndex:Int)
		If Not parameters.length Or openIndex < 0 Then Return
		Local parameterIndex:Int
		Local segmentStart:Int = openIndex + 1
		Local parenthesisDepth:Int = 1
		Local bracketDepth:Int
		For Local index:Int = segmentStart Until tokens.length
			Select tokens[index].text
				Case "("
					parenthesisDepth :+ 1
				Case ")"
					parenthesisDepth :- 1
					If parenthesisDepth = 0 Then
						If parameterIndex < parameters.length Then DecodeStaticArrayParameter(parameters[parameterIndex], tokens[segmentStart..index])
						Return
					End If
				Case "["
					bracketDepth :+ 1
				Case "]"
					bracketDepth :- 1
				Case ","
					If parenthesisDepth = 1 And bracketDepth = 0 Then
						If parameterIndex < parameters.length Then DecodeStaticArrayParameter(parameters[parameterIndex], tokens[segmentStart..index])
						parameterIndex :+ 1
						segmentStart = index + 1
					End If
			End Select
		Next
	End Function

	Function DecodeStaticArrayParameter(parameter:TParameterSyntax, tokens:TSyntaxToken[])
		If Not parameter Or tokens.length < 2 Then Return
		If parameter.callableType Then
			Local callableOpenIndex:Int = FindTokenText(tokens, "(", 0)
			If callableOpenIndex >= 0 Then DecodeStaticArrayParameterList(parameter.callableType.parameters, tokens, callableOpenIndex)
		End If
		If tokens.length < 5 Then Return
		Local separator:Int = -1
		Local closeIndex:Int = -1
		Local parenthesisDepth:Int
		For Local index:Int = 1 Until tokens.length - 2
			If tokens[index].text = "(" Then parenthesisDepth :+ 1; Continue
			If tokens[index].text = ")" Then parenthesisDepth :- 1; Continue
			If parenthesisDepth Then Continue
			If tokens[index].text <> "&" Or tokens[index + 1].text <> "[" Then Continue
			Local depth:Int
			For Local boundIndex:Int = index + 1 Until tokens.length
				If tokens[boundIndex].text = "[" Then depth :+ 1
				If tokens[boundIndex].text = "]" Then
					depth :- 1
					If depth = 0 Then closeIndex = boundIndex; Exit
				End If
			Next
			If closeIndex > index + 2 And HasStaticArrayBound(tokens, index + 1, closeIndex) Then separator = index
			Exit
		Next
		If separator < 0 Then Return
		parameter.declaredType = TBlitzMaxTypeParser.Parse(tokens[1..separator])
		parameter.staticArrayBound = DecodeStaticArrayBound(tokens[separator + 1..closeIndex + 1])
	End Function

	Function NormalizeEncodedDefault:TExpressionSyntax(expression:TExpressionSyntax)
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If literal And literal.literalToken And literal.literalToken.kind = TOKEN_STRING_LITERAL And IsManagedNullSentinel(literal.literalToken.text) Then
			Local diagnostics:TList = New TList
			Return TBlitzMaxExpressionParser.Parse(LexTokens("Null"), diagnostics)
		End If
		' Compact UInt/ULong defaults end in |/|| (for example r|=0|).
		' The ordinary expression parser can initially interpret that trailing
		' representation marker as a binary operator with no right operand.
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
		If binary And binary.operatorToken And TBlitzMaxTypeParser.IsTypeMarker(binary.operatorToken.text) Then
			Local missingRight:TRawExpressionSyntax = TRawExpressionSyntax(binary.right)
			If Not binary.right Or (missingRight And Not missingRight.tokens.length) Then Return binary.left
		End If
		Local raw:TRawExpressionSyntax = TRawExpressionSyntax(expression)
		If Not raw Or Not raw.tokens.length Then Return expression
		Local tokens:TSyntaxToken[] = raw.tokens
		Local normalized:TSyntaxToken[]
		If tokens.length = 1 And tokens[0].kind = TOKEN_STRING_LITERAL And IsManagedNullSentinel(tokens[0].text) Then
			normalized = LexTokens("Null")
		Else If tokens.length >= 2 And tokens[0].text = "$" And tokens[1].kind = TOKEN_STRING_LITERAL Then
			normalized = tokens[1..]
		Else If TBlitzMaxTypeParser.IsTypeMarker(tokens[tokens.length - 1].text) Then
			normalized = tokens[..tokens.length - 1]
		Else
			Return expression
		End If
		Local diagnostics:TList = New TList
		Return TBlitzMaxExpressionParser.Parse(normalized, diagnostics)
	End Function

	Function IsManagedNullSentinel:Int(text:String)
		Select text.ToLower()
			Case "~qbbnullobject~q", "~qbbemptyarray~q" Return True
		End Select
		Return False
	End Function

	Function IsCompactFlags:Int(text:String)
		If Not text.length Then Return False
		For Local index:Int = 0 Until text.length
			If Not "AFGOINPRSTVW".Contains(text[index..index + 1].ToUpper()) Then Return False
		Next
		Return True
	End Function

	Function DecodeType:TTypeReferenceSyntax(text:String)
		If Not text.length Then Return Null
		Local tokens:TSyntaxToken[] = NormalizeDynamicArrayReferenceMarkers(LexTokens(text))
		tokens = NormalizeExternalInterfaceReferenceMarkers(tokens)
		Return TBlitzMaxTypeParser.Parse(tokens)
	End Function

	Function NormalizeExternalInterfaceReferenceMarkers:TSyntaxToken[](tokens:TSyntaxToken[])
		' Production compact interfaces encode native external references as
		' ?Name and native external Interface references as ??Name.  These are
		' representation prefixes rather than BlitzMax semantic type markers;
		' discard them so the shared resolver binds the following named type.
		' They may occur at any nesting depth in a routine or callable signature.
		Local result:TList = New TList
		For Local index:Int = 0 Until tokens.length
			If tokens[index].text = "?" Then Continue
			result.AddLast(tokens[index])
		Next
		Return TokensToArray(result)
	End Function

	Function NormalizeDynamicArrayReferenceMarkers:TSyntaxToken[](tokens:TSyntaxToken[])
		' bcc writes a representation marker between an array element type and an
		' unbounded dynamic-array suffix (TObject&[], $&[,], %&[,,]). It is not
		' part of the BlitzMax source type name. Fixed arrays retain '&[length]'
		' and are decoded separately as StaticArray declarations.
		Local result:TList = New TList
		For Local index:Int = 0 Until tokens.length
			If tokens[index].text = "&" And index + 1 < tokens.length Then
				If tokens[index + 1].text = "[]" Then Continue
				If tokens[index + 1].text = "[" Then
					Local closeIndex:Int = index + 2
					While closeIndex < tokens.length And tokens[closeIndex].text <> "]"
						closeIndex :+ 1
					Wend
					If closeIndex < tokens.length And Not HasStaticArrayBound(tokens, index + 1, closeIndex) Then Continue
				End If
			End If
			result.AddLast(tokens[index])
		Next
		Return TokensToArray(result)
	End Function

	Function HasStaticArrayBound:Int(tokens:TSyntaxToken[], openIndex:Int, closeIndex:Int)
		For Local index:Int = openIndex + 1 Until closeIndex
			If tokens[index].text <> "," Then Return True
		Next
		Return False
	End Function

	Function DecodeExpression:TExpressionSyntax(text:String)
		If Not text.length Then Return Null
		' bcc's interface encoding repeats the compact declared-type marker on
		' constant values (42%, 1.0!, $"text"). It is serialization syntax,
		' not a source-level expression suffix, so remove it before using the
		' ordinary expression parser. The symbol still owns the decoded type.
		If text.StartsWith("$") And text.length > 1 And text[1] = 34 Then
			text = text[1..]
		Else
			Local markerLength:Int = CompactValueMarkerLength(text)
			If markerLength Then text = text[..text.length - markerLength]
		End If
		Local diagnostics:TList = New TList
		Return TBlitzMaxExpressionParser.Parse(LexTokens(text), diagnostics)
	End Function

	Function CompactValueMarkerLength:Int(text:String)
		Local twoCharacterMarkers:String[] = ["%%", "@@", "||", "%z", "%v", "%e", "%w", "%x", "%j", "!k", "!m", "!h"]
		For Local marker:String = EachIn twoCharacterMarkers
			If text.EndsWith(marker) Then Return 2
		Next
		Local oneCharacterMarkers:String[] = ["%", "|", "#", "!", "@"]
		For Local marker:String = EachIn oneCharacterMarkers
			If text.EndsWith(marker) Then Return 1
		Next
		Return 0
	End Function

	Function LexTokens:TSyntaxToken[](text:String)
		Local lexed:TLexResult = TBlitzMaxLexer.Lex(text, "<interface-signature>")
		Local count:Int = lexed.tokens.length
		If count And lexed.tokens[count - 1].kind = TOKEN_EOF Then count :- 1
		Local result:TSyntaxToken[] = New TSyntaxToken[count]
		For Local index:Int = 0 Until count
			result[index] = lexed.tokens[index]
		Next
		Return result
	End Function

	Function TokensToArray:TSyntaxToken[](list:TList)
		Local result:TSyntaxToken[] = New TSyntaxToken[list.Count()]
		Local index:Int
		For Local token:TSyntaxToken = EachIn list
			result[index] = token
			index :+ 1
		Next
		Return result
	End Function
End Type
