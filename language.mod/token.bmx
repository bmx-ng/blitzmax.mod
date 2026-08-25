' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "source.bmx"

Const TOKEN_BAD:Int = 0
Const TOKEN_EOF:Int = 1
Const TOKEN_IDENTIFIER:Int = 2
Const TOKEN_KEYWORD:Int = 3
Const TOKEN_INTEGER_LITERAL:Int = 4
Const TOKEN_FLOAT_LITERAL:Int = 5
Const TOKEN_STRING_LITERAL:Int = 6
Const TOKEN_SYMBOL:Int = 7
Const TOKEN_NEWLINE:Int = 8
Const TOKEN_MULTILINE_STRING_LITERAL:Int = 9
Const TOKEN_NATIVE_LINE:Int = 10
Const TOKEN_PRAGMA:Int = 11
Const TOKEN_DIRECTIVE:Int = 12
Const TOKEN_EMBEDDED_EXPRESSION:Int = 13

Const TRIVIA_WHITESPACE:Int = 1
Const TRIVIA_LINE_COMMENT:Int = 2
Const TRIVIA_BLOCK_COMMENT:Int = 3

Type TSyntaxTrivia
	Field kind:Int
	Field span:TSourceSpan
	Field text:String

	Function Create:TSyntaxTrivia(kind:Int, span:TSourceSpan, text:String)
		Local trivia:TSyntaxTrivia = New TSyntaxTrivia
		trivia.kind = kind
		trivia.span = span
		trivia.text = text
		Return trivia
	End Function
End Type

Type TSyntaxToken
	Field kind:Int
	Field span:TSourceSpan
	Field text:String
	Field leadingTrivia:TSyntaxTrivia[]
	Field trailingTrivia:TSyntaxTrivia[]
	Field missing:Int
	' Parser-owned expression nodes with multiline structure are carried through
	' the ordinary expression parser as a single synthetic token.
	Field payload:Object

	Function Create:TSyntaxToken(kind:Int, span:TSourceSpan, text:String, leadingTrivia:TSyntaxTrivia[] = Null, trailingTrivia:TSyntaxTrivia[] = Null, missing:Int = False)
		Local token:TSyntaxToken = New TSyntaxToken
		token.kind = kind
		token.span = span
		token.text = text
		token.leadingTrivia = leadingTrivia
		token.trailingTrivia = trailingTrivia
		token.missing = missing
		Return token
	End Function

	Method KindName:String()
		Select kind
			Case TOKEN_BAD Return "BadToken"
			Case TOKEN_EOF Return "EndOfFileToken"
			Case TOKEN_IDENTIFIER Return "IdentifierToken"
			Case TOKEN_KEYWORD Return "KeywordToken"
			Case TOKEN_INTEGER_LITERAL Return "IntegerLiteralToken"
			Case TOKEN_FLOAT_LITERAL Return "FloatLiteralToken"
			Case TOKEN_STRING_LITERAL Return "StringLiteralToken"
			Case TOKEN_SYMBOL Return "SymbolToken"
			Case TOKEN_NEWLINE Return "NewlineToken"
			Case TOKEN_MULTILINE_STRING_LITERAL Return "MultilineStringLiteralToken"
			Case TOKEN_NATIVE_LINE Return "NativeLineToken"
			Case TOKEN_PRAGMA Return "PragmaToken"
			Case TOKEN_DIRECTIVE Return "DirectiveToken"
			Case TOKEN_EMBEDDED_EXPRESSION Return "EmbeddedExpressionToken"
		End Select
		Return "UnknownToken"
	End Method
End Type
