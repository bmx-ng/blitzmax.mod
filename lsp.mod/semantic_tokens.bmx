' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

Const SEMANTIC_TOKEN_CLASS:Int = 0
Const SEMANTIC_TOKEN_STRUCT:Int = 1
Const SEMANTIC_TOKEN_INTERFACE:Int = 2
Const SEMANTIC_TOKEN_ENUM:Int = 3
Const SEMANTIC_TOKEN_TYPE_PARAMETER:Int = 4
Const SEMANTIC_TOKEN_PARAMETER:Int = 5
Const SEMANTIC_TOKEN_VARIABLE:Int = 6
Const SEMANTIC_TOKEN_PROPERTY:Int = 7
Const SEMANTIC_TOKEN_ENUM_MEMBER:Int = 8
Const SEMANTIC_TOKEN_FUNCTION:Int = 9
Const SEMANTIC_TOKEN_METHOD:Int = 10
Const SEMANTIC_TOKEN_TYPE:Int = 11

Const SEMANTIC_MODIFIER_DECLARATION:Int = 1
Const SEMANTIC_MODIFIER_READONLY:Int = 2
Const SEMANTIC_MODIFIER_STATIC:Int = 4

Type TSemanticTokenEntry
	Field span:TSourceSpan
	Field tokenType:Int
	Field modifiers:Int
End Type

Type TBlitzMaxLspSemanticTokens
	Function TokenTypes:TJSONArray()
		Local result:TJSONArray = JsonArray()
		For Local name:String = EachIn ["class", "struct", "interface", "enum", "typeParameter", "parameter", "variable", "property", "enumMember", "function", "method", "type"]
			result.Append(New TJSONString.Create(name))
		Next
		Return result
	End Function

	Function TokenModifiers:TJSONArray()
		Local result:TJSONArray = JsonArray()
		For Local name:String = EachIn ["declaration", "readonly", "static"]
			result.Append(New TJSONString.Create(name))
		Next
		Return result
	End Function

	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext)
		Local result:TJSONObject = JsonObject()
		Local data:TJSONArray = JsonArray()
		result.Set("data", data)
		If Not document Or Not workspace Then Return result
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.model Or Not analysis.syntaxTree Then Return result
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not navigator Then navigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		If Not navigator Then Return result

		Local entries:TSemanticTokenEntry[]
		Local seen:TMap = New TMap
		For Local value:Object = EachIn analysis.model.declaredSymbolMap.Keys()
			Local node:TSyntaxNode = TSyntaxNode(value)
			If Not node Or Not navigator.ContainsNode(node) Then Continue
			Local symbol:TSymbol = analysis.model.DeclaredSymbol(node)
			AddEntry(entries, seen, NameToken(node), SymbolTokenType(symbol), SymbolModifiers(symbol, True))
		Next
		For Local value:Object = EachIn analysis.model.referencedSymbolMap.Keys()
			Local node:TSyntaxNode = TSyntaxNode(value)
			If Not node Or Not navigator.ContainsNode(node) Then Continue
			Local symbol:TSymbol = analysis.model.ReferencedSymbol(node)
			AddEntry(entries, seen, NameToken(node), SymbolTokenType(symbol), SymbolModifiers(symbol, False))
		Next
		For Local value:Object = EachIn analysis.model.typeMap.Keys()
			Local syntax:TTypeReferenceSyntax = TTypeReferenceSyntax(value)
			If Not syntax Or Not navigator.ContainsNode(syntax) Then Continue
			Local semanticType:TSemanticType = analysis.model.TypeOf(syntax)
			Local symbol:TSymbol = TypeSymbol(semanticType)
			Local tokenType:Int = SEMANTIC_TOKEN_TYPE
			If symbol Then tokenType = SymbolTokenType(symbol)
			For Local token:TSyntaxToken = EachIn syntax.nameTokens
				AddEntry(entries, seen, token, tokenType, SymbolModifiers(symbol, False))
			Next
		Next

		SortEntries(entries)
		Local previousLine:Int
		Local previousCharacter:Int
		Local first:Int = True
		For Local entry:TSemanticTokenEntry = EachIn entries
			Local start:TJSONObject = TLspPositions.Position(analysis.syntaxTree.source, entry.span.start)
			Local finish:TJSONObject = TLspPositions.Position(analysis.syntaxTree.source, entry.span.EndOffset())
			Local line:Int = Int(start.GetInteger("line"))
			Local character:Int = Int(start.GetInteger("character"))
			If Int(finish.GetInteger("line")) <> line Then Continue
			Local length:Int = Int(finish.GetInteger("character")) - character
			If length <= 0 Then Continue
			Local deltaLine:Int = line - previousLine
			Local deltaCharacter:Int = character
			If Not first And deltaLine = 0 Then deltaCharacter = character - previousCharacter
			data.Append(New TJSONInteger.Create(deltaLine))
			data.Append(New TJSONInteger.Create(deltaCharacter))
			data.Append(New TJSONInteger.Create(length))
			data.Append(New TJSONInteger.Create(entry.tokenType))
			data.Append(New TJSONInteger.Create(entry.modifiers))
			previousLine = line
			previousCharacter = character
			first = False
		Next
		Return result
	End Function

	Function AddEntry(entries:TSemanticTokenEntry[] Var, seen:TMap, token:TSyntaxToken, tokenType:Int, modifiers:Int)
		If Not token Or Not token.span Or token.span.length <= 0 Or tokenType < 0 Then Return
		Local key:String = token.span.start + ":" + token.span.length
		Local existing:TSemanticTokenEntry = TSemanticTokenEntry(seen.ValueForKey(key))
		If existing Then
			existing.modifiers :| modifiers
			Return
		End If
		Local entry:TSemanticTokenEntry = New TSemanticTokenEntry
		entry.span = token.span
		entry.tokenType = tokenType
		entry.modifiers = modifiers
		seen.Insert(key, entry)
		entries :+ [entry]
	End Function

	Function SortEntries(entries:TSemanticTokenEntry[] Var)
		For Local index:Int = 1 Until entries.length
			Local value:TSemanticTokenEntry = entries[index]
			Local cursor:Int = index - 1
			While cursor >= 0 And entries[cursor].span.start > value.span.start
				entries[cursor + 1] = entries[cursor]
				cursor :- 1
			Wend
			entries[cursor + 1] = value
		Next
	End Function

	Function NameToken:TSyntaxToken(node:TSyntaxNode)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(node)
		If name Then Return name.nameToken
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(node)
		If member Then Return member.nameToken
		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration Then Return typeDeclaration.nameToken
		Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(node)
		If enumDeclaration Then Return enumDeclaration.nameToken
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine Then Return routine.nameToken
		Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(node)
		If declarator Then Return declarator.nameToken
		Local parameter:TParameterSyntax = TParameterSyntax(node)
		If parameter Then Return parameter.nameToken
		Local genericParameter:TGenericParameterSyntax = TGenericParameterSyntax(node)
		If genericParameter Then Return genericParameter.nameToken
		Local enumValue:TEnumValueSyntax = TEnumValueSyntax(node)
		If enumValue Then Return enumValue.nameToken
		Local catchClause:TCatchClauseSyntax = TCatchClauseSyntax(node)
		If catchClause Then Return catchClause.nameToken
		Return Null
	End Function

	Function TypeSymbol:TSymbol(semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named Then Return named.symbol
		Local parameter:TTypeParameterSemanticType = TTypeParameterSemanticType(semanticType)
		If parameter Then Return parameter.symbol
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If builtin Then Return builtin.runtimeSymbol
		Return Null
	End Function

	Function SymbolTokenType:Int(symbol:TSymbol)
		If Not symbol Then Return -1
		Select symbol.kind
			Case SYMBOL_TYPE Return SEMANTIC_TOKEN_CLASS
			Case SYMBOL_STRUCT Return SEMANTIC_TOKEN_STRUCT
			Case SYMBOL_INTERFACE Return SEMANTIC_TOKEN_INTERFACE
			Case SYMBOL_ENUM Return SEMANTIC_TOKEN_ENUM
			Case SYMBOL_TYPE_PARAMETER Return SEMANTIC_TOKEN_TYPE_PARAMETER
			Case SYMBOL_PARAMETER, SYMBOL_CATCH_PARAMETER Return SEMANTIC_TOKEN_PARAMETER
			Case SYMBOL_FIELD Return SEMANTIC_TOKEN_PROPERTY
			Case SYMBOL_ENUM_MEMBER Return SEMANTIC_TOKEN_ENUM_MEMBER
			Case SYMBOL_ROUTINE
				If TMemberCompletion.IsInstanceRoutine(symbol) Then Return SEMANTIC_TOKEN_METHOD
				Return SEMANTIC_TOKEN_FUNCTION
			Case SYMBOL_GLOBAL, SYMBOL_CONST, SYMBOL_LOCAL Return SEMANTIC_TOKEN_VARIABLE
		End Select
		Return -1
	End Function

	Function SymbolModifiers:Int(symbol:TSymbol, declaration:Int)
		Local result:Int
		If declaration Then result :| SEMANTIC_MODIFIER_DECLARATION
		If Not symbol Then Return result
		If symbol.kind = SYMBOL_CONST Or symbol.kind = SYMBOL_ENUM_MEMBER Then result :| SEMANTIC_MODIFIER_READONLY
		If symbol.kind = SYMBOL_ENUM_MEMBER Then result :| SEMANTIC_MODIFIER_STATIC
		If symbol.containingScope And symbol.containingScope.owner Then
			If symbol.kind = SYMBOL_GLOBAL Or symbol.kind = SYMBOL_CONST Then result :| SEMANTIC_MODIFIER_STATIC
			If symbol.kind = SYMBOL_ROUTINE And Not TMemberCompletion.IsInstanceRoutine(symbol) Then result :| SEMANTIC_MODIFIER_STATIC
		End If
		Return result
	End Function
End Type
