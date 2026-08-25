' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "lexer.bmx"
Import "conditional_evaluator.bmx"
Import "interface_parser.bmx"
Import "parser.bmx"
Import "syntax.bmx"

Rem
bbdoc: Parses BlitzMax source and compact module interface text.
about: Parsing produces a recoverable syntax tree and diagnostics. It does not bind
names or resolve types; use #TBlitzMaxLanguage for semantic analysis.
End Rem
Type TBlitzMaxParser
	Rem
	bbdoc: Parses a compact BlitzMax module interface.
	param: The interface text.
	param: The interface path used for diagnostics and source provenance.
	returns: The decoded interface model and any interface diagnostics.
	End Rem
	Function ParseInterfaceText:TInterfaceFile(text:String, path:String = "")
		Return TInterfaceFileParser.Parse(text, path)
	End Function

	Rem
	bbdoc: Parses the lightweight catalogue view of a compact module interface.
	param: The interface text.
	param: The interface path used for diagnostics and source provenance.
	returns: An interface model containing declaration and module catalogue information.
	about: This variant reads declaration names, module relationships, compact signatures,
	and source provenance without constructing signature syntax trees or inflating
	embedded generic source. It is intended for whole-environment symbol catalogues.
	End Rem
	Function ParseInterfaceCatalogueText:TInterfaceFile(text:String, path:String = "")
		Return TInterfaceFileParser.Parse(text, path, False, False)
	End Function

	Rem
	bbdoc: Parses BlitzMax source text without selecting conditional-compilation branches.
	param: The source text to parse.
	param: The source path used for diagnostics and identity.
	returns: A syntax tree and its lexical and parse diagnostics.
	End Rem
	Function ParseText:TParseResult(text:String, path:String = "")
		Local source:TSourceText = TSourceText.Create(text, path)
		Local lexResult:TLexResult = TBlitzMaxLexer.LexSource(source)
		Return ParseLexResult(lexResult, source, Null)
	End Function

	Rem
	bbdoc: Parses the active conditional-compilation view of BlitzMax source text.
	param: The source text to parse.
	param: The source path used for diagnostics and identity.
	param: The case-insensitive symbols considered defined by conditional expressions.
	returns: A syntax tree and its lexical, conditional-selection, and parse diagnostics.
	about: Directive lines and inactive source lines are omitted. Every surviving token
	retains its original source span.
	End Rem
	Function ParseConfiguredText:TParseResult(text:String, path:String, conditionalSymbols:String[])
		Local source:TSourceText = TSourceText.Create(text, path)
		Local lexResult:TLexResult = TBlitzMaxLexer.LexSource(source)
		Local selectionDiagnostics:TDiagnostic[]
		lexResult = SelectConditionalTokens(lexResult, conditionalSymbols, selectionDiagnostics)
		Return ParseLexResult(lexResult, source, selectionDiagnostics)
	End Function

	Function ParseLexResult:TParseResult(lexResult:TLexResult, source:TSourceText, selectionDiagnostics:TDiagnostic[])
		Local parseResult:TSyntaxParseResult = TBlitzMaxSyntaxParser.Parse(lexResult)

		Local tree:TSyntaxTree = New TSyntaxTree
		tree.source = source
		tree.root = parseResult.root
		tree.diagnostics = MergeDiagnostics(MergeDiagnostics(lexResult.diagnostics, selectionDiagnostics), parseResult.diagnostics)
		For Local diagnostic:TDiagnostic = EachIn tree.diagnostics
			If Not diagnostic.path.length Then diagnostic.path = source.path
		Next

		Local result:TParseResult = New TParseResult
		result.syntaxTree = tree
		Return result
	End Function

	Function SelectConditionalTokens:TLexResult(lexResult:TLexResult, conditionalSymbols:String[], selectionDiagnostics:TDiagnostic[] Var)
		Local selected:TList = New TList
		Local diagnostics:TList = New TList
		Local active:Int = True
		Local directiveLine:Int
		For Local token:TSyntaxToken = EachIn lexResult.tokens
			If token.kind = TOKEN_DIRECTIVE Then
				directiveLine = True
				If token.text.Trim() = "?" Then
					active = True
				Else
					Local condition:TConditionalExpressionSyntax = TConditionalExpressionParser.Parse(token, diagnostics)
					active = TConditionalEvaluator.Evaluate(condition, conditionalSymbols)
				End If
				Continue
			End If
			If token.kind = TOKEN_NEWLINE Then
				If directiveLine Then
					directiveLine = False
				Else If active Then
					selected.AddLast(token)
				End If
				Continue
			End If
			If token.kind = TOKEN_EOF Or active Then selected.AddLast(token)
		Next

		Local result:TLexResult = New TLexResult
		result.source = lexResult.source
		result.tokens = TokenArray(selected)
		result.diagnostics = lexResult.diagnostics
		selectionDiagnostics = DiagnosticArray(diagnostics)
		Return result
	End Function

	Function TokenArray:TSyntaxToken[](values:TList)
		Local result:TSyntaxToken[] = New TSyntaxToken[values.Count()]
		Local index:Int
		For Local value:TSyntaxToken = EachIn values
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function DiagnosticArray:TDiagnostic[](values:TList)
		Local result:TDiagnostic[] = New TDiagnostic[values.Count()]
		Local index:Int
		For Local value:TDiagnostic = EachIn values
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function MergeDiagnostics:TDiagnostic[](first:TDiagnostic[], second:TDiagnostic[])
		Local result:TDiagnostic[] = New TDiagnostic[first.length + second.length]
		For Local index:Int = 0 Until first.length
			result[index] = first[index]
		Next
		For Local index:Int = 0 Until second.length
			result[first.length + index] = second[index]
		Next
		Return result
	End Function
End Type
