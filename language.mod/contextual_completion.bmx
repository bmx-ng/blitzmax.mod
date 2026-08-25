' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "member_completion.bmx"
Import "semantic_model.bmx"
Import "syntax_navigation.bmx"

' A protocol-independent set of symbols visible at an ordinary expression
' position. Member access completion remains the responsibility of
' TMemberCompletion.
Type TContextualCompletionResult
	Field scope:TScope
	Field symbols:TSymbol[] = New TSymbol[0]
End Type

Type TContextualCompletion
	Function Query:TContextualCompletionResult(model:TSemanticModel, navigator:TSyntaxNavigator, offset:Int)
		If Not model Or Not navigator Or Not navigator.tree Or Not navigator.tree.source Then Return Null
		Local result:TContextualCompletionResult = New TContextualCompletionResult
		Local queryOffset:Int = Min(offset, navigator.tree.source.Length())
		If queryOffset > 0 Then queryOffset :- 1
		Local location:TSemanticLocation = TSemanticLocation.Query(model, navigator, queryOffset)
		If location Then result.scope = location.scope
		If Not result.scope Then result.scope = model.globalScope
		If Not result.scope Then Return result

		Local seenNames:TMap = New TMap
		Local staticTypeContext:Int = IsStaticTypeContext(result.scope)
		Local scope:TScope = result.scope
		While scope
			CollectScope(result.symbols, scope, offset, staticTypeContext, False, seenNames, model, result.scope)
			scope = scope.parent
		Wend

		' Direct imports have the same precedence used by semantic lookup. Public
		' transitive imports follow, with .i scopes remaining authoritative.
		For Local imported:TScope = EachIn model.directImportedScopes
			CollectScope(result.symbols, imported, offset, False, True, seenNames, model, result.scope)
		Next
		For Local imported:TScope = EachIn model.importedScopes
			If IsDirectImport(model, imported) Then Continue
			CollectScope(result.symbols, imported, offset, False, True, seenNames, model, result.scope)
		Next
		Return result
	End Function

	Function CollectScope(symbols:TSymbol[] Var, scope:TScope, offset:Int, staticTypeContext:Int, imported:Int, seenNames:TMap, model:TSemanticModel, accessScope:TScope)
		If Not scope Then Return
		Local namesInScope:TMap = New TMap
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not IsCandidate(symbol, scope, offset, staticTypeContext, imported, model, accessScope) Then Continue
			If seenNames.Contains(symbol.normalizedName) Then Continue
			symbols :+ [symbol]
			namesInScope.Insert(symbol.normalizedName, symbol)
		Next
		' Mark names only after collecting the complete scope so overloads survive.
		For Local name:Object = EachIn namesInScope.Keys()
			seenNames.Insert(name, namesInScope.ValueForKey(name))
		Next
	End Function

	Function IsCandidate:Int(symbol:TSymbol, scope:TScope, offset:Int, staticTypeContext:Int, imported:Int, model:TSemanticModel, accessScope:TScope)
		If Not symbol Then Return False
		Select symbol.kind
			Case SYMBOL_LOCAL, SYMBOL_PARAMETER, SYMBOL_CATCH_PARAMETER, SYMBOL_FIELD, SYMBOL_GLOBAL, SYMBOL_CONST, SYMBOL_ROUTINE
				' supported ordinary expression symbols
			Default
				Return False
		End Select
		If symbol.kind = SYMBOL_ROUTINE And symbol.normalizedName = "new" Then Return False
		If symbol.kind <> SYMBOL_LOCAL And symbol.kind <> SYMBOL_PARAMETER And symbol.kind <> SYMBOL_CATCH_PARAMETER Then
			If Not TSymbolAccessibility.IsAccessible(symbol, accessScope, model) Then Return False
		End If
		If symbol.kind = SYMBOL_LOCAL And symbol.nameToken And symbol.nameToken.span And symbol.nameToken.span.start >= offset Then Return False
		If staticTypeContext And scope.kind = SCOPE_TYPE Then
			If symbol.kind = SYMBOL_FIELD Then Return False
			If symbol.kind = SYMBOL_ROUTINE And TMemberCompletion.IsInstanceRoutine(symbol) Then Return False
		End If
		Return True
	End Function

	Function IsStaticTypeContext:Int(scope:TScope)
		Local routine:TSymbol
		Local typeScope:TScope
		Local current:TScope = scope
		While current
			If Not routine And current.kind = SCOPE_ROUTINE Then routine = current.owner
			If current.kind = SCOPE_TYPE Then typeScope = current; Exit
			current = current.parent
		Wend
		Return typeScope <> Null And routine <> Null And Not TMemberCompletion.IsInstanceRoutine(routine)
	End Function

	Function IsDirectImport:Int(model:TSemanticModel, scope:TScope)
		For Local direct:TScope = EachIn model.directImportedScopes
			If direct = scope Then Return True
		Next
		Return False
	End Function
End Type
