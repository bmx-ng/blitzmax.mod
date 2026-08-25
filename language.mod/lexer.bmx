' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map

Import "diagnostic.bmx"
Import "token.bmx"

Type TLexResult
	Field source:TSourceText
	Field tokens:TSyntaxToken[]
	Field diagnostics:TDiagnostic[]

	Method ReconstructSource:String()
		Local result:String
		For Local token:TSyntaxToken = EachIn tokens
			For Local trivia:TSyntaxTrivia = EachIn token.leadingTrivia
				result :+ trivia.text
			Next
			result :+ token.text
			For Local trivia:TSyntaxTrivia = EachIn token.trailingTrivia
				result :+ trivia.text
			Next
		Next
		Return result
	End Method
End Type

Type TBlitzMaxLexer
	Const KEYWORDS:String = "strict,superstrict,public,private,protected,internal,byte,short,int,float,double,long,string,object,ptr,var,varptr," + ..
		"mod,continue,exit,include,import,module,moduleinfo,extern,framework,new,self,super,eachin,true,false," + ..
		"null,not,extends,abstract,final,select,case,default,const,local,global,field,method,function,type," + ..
		"and,or,shl,shr,sar,end,if,then,else,elseif,endif,while,wend,repeat,until,forever,for,to,step,goto," + ..
		"next,return,alias,rem,endrem,throw,assert,try,catch,finally,nodebug,incbin,endselect,endmethod," + ..
		"endfunction,endtype,endextern,endtry,endwhile,pi,release,defdata,readdata,restoredata,interface," + ..
		"endinterface,implements,size_t,uint,ulong,struct,endstruct,operator,where,readonly,export,override," + ..
		"enum,endenum,stackalloc,sizeof,alignof,inline,fieldoffset,staticarray,threadedglobal,longint,ulongint,using,endusing,do"

	Field source:TSourceText
	Field offset:Int
	Field atLineStart:Int = True
	Field tokenList:TList = New TList
	Field diagnosticList:TList = New TList
	Field keywordMap:TMap

	Function Lex:TLexResult(text:String, path:String = "")
		Return LexSource(TSourceText.Create(text, path))
	End Function

	Function LexSource:TLexResult(source:TSourceText)
		Local lexer:TBlitzMaxLexer = New TBlitzMaxLexer
		lexer.source = source
		lexer.keywordMap = New TMap
		For Local keyword:String = EachIn KEYWORDS.Split(",")
			lexer.keywordMap.Insert(keyword, keyword)
		Next
		Return lexer.Run()
	End Function

	Method Run:TLexResult()
		While True
			Local leadingTrivia:TSyntaxTrivia[] = LexLeadingTrivia()
			If offset >= source.Length() Then
				tokenList.AddLast(TSyntaxToken.Create(TOKEN_EOF, TSourceSpan.Create(offset, 0), "", leadingTrivia))
				Exit
			End If

			tokenList.AddLast(LexToken(leadingTrivia))
		Wend

		Local result:TLexResult = New TLexResult
		result.source = source
		result.tokens = TokensToArray(tokenList)
		result.diagnostics = DiagnosticsToArray(diagnosticList)
		Return result
	End Method

	Method LexLeadingTrivia:TSyntaxTrivia[]()
		Local triviaList:TList = New TList

		While offset < source.Length()
			Local start:Int = offset
			Local char:Int = CurrentChar()

			If IsHorizontalWhitespace(char) Then
				While IsHorizontalWhitespace(CurrentChar())
					offset :+ 1
				Wend
				triviaList.AddLast(NewTrivia(TRIVIA_WHITESPACE, start))
				Continue
			End If

			If char = 39 And PeekChar(1) <> 33 Then
				While offset < source.Length() And Not IsNewline(CurrentChar())
					offset :+ 1
				Wend
				Local text:String = source.text[start..offset]
				Local body:String = text[1..].Trim().ToLower()
				If body.StartsWith("@bmk") Then
					' Pragmas are significant tokens, not comments.
					offset = start
					Exit
				End If
				triviaList.AddLast(TSyntaxTrivia.Create(TRIVIA_LINE_COMMENT, TSourceSpan.Create(start, offset - start), text))
				Continue
			End If

			If IsRemStart() Then
				LexRemComment(triviaList)
				Continue
			End If

			Exit
		Wend

		Return TriviaToArray(triviaList)
	End Method

	Method LexToken:TSyntaxToken(leadingTrivia:TSyntaxTrivia[])
		Local start:Int = offset
		Local kind:Int = TOKEN_BAD
		Local char:Int = CurrentChar()

		If IsNewline(char) Then
			kind = TOKEN_NEWLINE
			If char = 13 And PeekChar(1) = 10 Then offset :+ 1
			offset :+ 1
			atLineStart = True
		Else If atLineStart And char = 63 Then
			kind = TOKEN_DIRECTIVE
			While offset < source.Length() And Not IsNewline(CurrentChar())
				offset :+ 1
			Wend
			atLineStart = False
		Else If char = 39 And PeekChar(1) = 33 Then
			kind = TOKEN_NATIVE_LINE
			While offset < source.Length() And Not IsNewline(CurrentChar())
				offset :+ 1
			Wend
			atLineStart = False
		Else If char = 39 Then
			kind = TOKEN_PRAGMA
			While offset < source.Length() And Not IsNewline(CurrentChar())
				offset :+ 1
			Wend
			atLineStart = False
		Else If IsIdentifierStart(char) Then
			offset :+ 1
			While IsIdentifierPart(CurrentChar())
				offset :+ 1
			Wend
			If IsKeyword(source.text[start..offset]) Then
				kind = TOKEN_KEYWORD
			Else
				kind = TOKEN_IDENTIFIER
			End If
			atLineStart = False
		Else If IsDigit(char) Or (char = 46 And IsDigit(PeekChar(1))) Then
			kind = LexNumber()
			atLineStart = False
		Else If char = 37 And IsBinaryDigit(PeekChar(1)) Then
			offset :+ 2
			While IsBinaryDigit(CurrentChar())
				offset :+ 1
			Wend
			kind = TOKEN_INTEGER_LITERAL
			atLineStart = False
		Else If char = 36 And IsHexDigit(PeekChar(1)) Then
			offset :+ 2
			While IsHexDigit(CurrentChar())
				offset :+ 1
			Wend
			kind = TOKEN_INTEGER_LITERAL
			atLineStart = False
		Else If char = 34 Then
			kind = LexString(start)
			atLineStart = False
		Else
			kind = TOKEN_SYMBOL
			offset :+ SymbolLength()
			atLineStart = False
		End If

		Return TSyntaxToken.Create(kind, TSourceSpan.Create(start, offset - start), source.text[start..offset], leadingTrivia)
	End Method

	Method LexNumber:Int()
		Local kind:Int = TOKEN_INTEGER_LITERAL

		If CurrentChar() = 46 Then
			kind = TOKEN_FLOAT_LITERAL
			offset :+ 1
		End If

		While IsDigit(CurrentChar())
			offset :+ 1
		Wend

		If kind = TOKEN_INTEGER_LITERAL And CurrentChar() = 46 And IsDigit(PeekChar(1)) Then
			kind = TOKEN_FLOAT_LITERAL
			offset :+ 1
			While IsDigit(CurrentChar())
				offset :+ 1
			Wend
		End If

		If CurrentChar() = 69 Or CurrentChar() = 101 Then
			kind = TOKEN_FLOAT_LITERAL
			offset :+ 1
			If CurrentChar() = 43 Or CurrentChar() = 45 Then offset :+ 1
			Local exponentStart:Int = offset
			While IsDigit(CurrentChar())
				offset :+ 1
			Wend
			If exponentStart = offset Then
				AddDiagnostic("BMX1003", "A numeric exponent requires at least one digit.", TSourceSpan.Create(exponentStart, 0))
			End If
		End If

		Return kind
	End Method

	Method LexString:Int(start:Int)
		If PeekChar(1) = 34 And PeekChar(2) = 34 Then
			offset :+ 3
			While offset < source.Length()
				If CurrentChar() = 34 And PeekChar(1) = 34 And PeekChar(2) = 34 Then
					ValidateStringEscapes(start + 3, offset)
					offset :+ 3
					Return TOKEN_MULTILINE_STRING_LITERAL
				End If
				offset :+ 1
			Wend
			AddDiagnostic("BMX1001", "Unterminated multiline string literal.", TSourceSpan.Create(start, offset - start))
			Return TOKEN_MULTILINE_STRING_LITERAL
		End If

		offset :+ 1
		While offset < source.Length() And Not IsNewline(CurrentChar())
			If CurrentChar() = 34 Then
				ValidateStringEscapes(start + 1, offset)
				offset :+ 1
				Return TOKEN_STRING_LITERAL
			End If
			offset :+ 1
		Wend

		AddDiagnostic("BMX1000", "Unterminated string literal.", TSourceSpan.Create(start, offset - start))
		Return TOKEN_STRING_LITERAL
	End Method

	Method ValidateStringEscapes(start:Int, finish:Int)
		Local index:Int = start
		While index < finish
			If source.text[index] <> 126 Then
				index :+ 1
				Continue
			End If

			Local escapeStart:Int = index
			index :+ 1
			If index >= finish Then
				AddInvalidStringEscape(escapeStart, index)
				Return
			End If

			Local selector:Int = source.text[index]
			Select selector
				Case 48, 84, 116, 82, 114, 78, 110, 81, 113, 126
					index :+ 1
				Case 36
					index :+ 1
					While index < finish And IsHexDigit(source.text[index])
						index :+ 1
					Wend
					If index >= finish Or source.text[index] <> 126 Then
						AddInvalidStringEscape(escapeStart, index)
						Return
					End If
					index :+ 1
				Case 37
					index :+ 1
					While index < finish And IsBinaryDigit(source.text[index])
						index :+ 1
					Wend
					If index >= finish Or source.text[index] <> 126 Then
						AddInvalidStringEscape(escapeStart, index)
						Return
					End If
					index :+ 1
				Default
					If selector < 49 Or selector > 57 Then
						AddInvalidStringEscape(escapeStart, index + 1)
						Return
					End If
					While index < finish And IsDigit(source.text[index])
						index :+ 1
					Wend
					If index >= finish Or source.text[index] <> 126 Then
						AddInvalidStringEscape(escapeStart, index)
						Return
					End If
					index :+ 1
			End Select
		Wend
	End Method

	Method AddInvalidStringEscape(start:Int, finish:Int)
		Local length:Int = finish - start
		If length < 1 Then length = 1
		AddDiagnostic("BMX1004", "Bad escape sequence in string literal.", TSourceSpan.Create(start, length))
	End Method

	Method LexRemComment(triviaList:TList)
		Local start:Int = offset
		Local foundTerminator:Int

		While offset < source.Length()
			While offset < source.Length() And Not IsNewline(CurrentChar())
				offset :+ 1
			Wend

			If offset >= source.Length() Then Exit
			If CurrentChar() = 13 And PeekChar(1) = 10 Then offset :+ 1
			offset :+ 1

			Local lineStart:Int = offset
			While offset < source.Length() And Not IsNewline(CurrentChar())
				offset :+ 1
			Wend
			Local line:String = source.text[lineStart..offset].Trim().ToLower()
			If line.StartsWith("endrem") Or line.StartsWith("end rem") Then
				foundTerminator = True
				Exit
			End If
		Wend

		If Not foundTerminator Then
			AddDiagnostic("BMX1002", "Unterminated Rem comment.", TSourceSpan.Create(start, offset - start))
		End If

		triviaList.AddLast(TSyntaxTrivia.Create(TRIVIA_BLOCK_COMMENT, TSourceSpan.Create(start, offset - start), source.text[start..offset]))
		atLineStart = False
	End Method

	Method IsRemStart:Int()
		If offset + 3 > source.Length() Then Return False
		If source.text[offset..offset + 3].ToLower() <> "rem" Then Return False
		If offset > 0 And IsIdentifierPart(source.text[offset - 1]) Then Return False
		Return Not IsIdentifierPart(PeekChar(3))
	End Method

	Method IsKeyword:Int(text:String)
		Return keywordMap.Contains(text.ToLower())
	End Method

	Method SymbolLength:Int()
		Local remaining:String = source.text[offset..Min(source.Length(), offset + 5)].ToLower()
		Local symbols:String[] = [":shr", ":shl", ":sar", ":mod", ":~~", "..", "[]", "<=", ">=", "<>", "~~", "%%", "@@", "||", "%z", "%v", "%e", "%w", "%x", "%j", "!k", "!m", "!h", ":*", ":/", ":+", ":-", ":|", ":&", ":="]
		For Local symbol:String = EachIn symbols
			If Not remaining.StartsWith(symbol) Then Continue
			' Alphabetic compound assignments are keyword operators. Require the
			' same trailing word boundary as their standalone forms so a named
			' type such as `:Mode` is not split into `:Mod` and `e`.
			If symbol.length > 1 And IsIdentifierStart(symbol[1]) And IsIdentifierPart(PeekChar(symbol.length)) Then Continue
			Return symbol.length
		Next
		Return 1
	End Method

	Method NewTrivia:TSyntaxTrivia(kind:Int, start:Int)
		Return TSyntaxTrivia.Create(kind, TSourceSpan.Create(start, offset - start), source.text[start..offset])
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan)
		diagnosticList.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span))
	End Method

	Method CurrentChar:Int()
		Return PeekChar(0)
	End Method

	Method PeekChar:Int(distance:Int)
		Local index:Int = offset + distance
		If index < 0 Or index >= source.Length() Then Return 0
		Return source.text[index]
	End Method

	Function IsNewline:Int(char:Int)
		Return char = 10 Or char = 13
	End Function

	Function IsHorizontalWhitespace:Int(char:Int)
		Return char = 9 Or char = 11 Or char = 12 Or char = 32
	End Function

	Function IsDigit:Int(char:Int)
		Return char >= 48 And char <= 57
	End Function

	Function IsBinaryDigit:Int(char:Int)
		Return char = 48 Or char = 49
	End Function

	Function IsHexDigit:Int(char:Int)
		Return IsDigit(char) Or (char >= 65 And char <= 70) Or (char >= 97 And char <= 102)
	End Function

	Function IsIdentifierStart:Int(char:Int)
		Return char = 95 Or (char >= 65 And char <= 90) Or (char >= 97 And char <= 122) Or char > 127
	End Function

	Function IsIdentifierPart:Int(char:Int)
		Return IsIdentifierStart(char) Or IsDigit(char)
	End Function

	Function TriviaToArray:TSyntaxTrivia[](list:TList)
		Local result:TSyntaxTrivia[] = New TSyntaxTrivia[list.Count()]
		Local index:Int
		For Local value:TSyntaxTrivia = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
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
