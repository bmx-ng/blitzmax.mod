' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "lexer.bmx"
Import "inheritance_validation.bmx"
Import "member_completion.bmx"
Import "contextual_completion.bmx"
Import "semantic_model.bmx"
Import "symbol_accessibility.bmx"
Import "syntax_navigation.bmx"

Type TTypeCompletionCandidate
	Field name:String
	Field symbol:TSymbol
	Field builtinType:TBuiltinSemanticType
	Field priority:Int
	' 0 is valid/neutral and 1 is known incompatible with the active bound.
	' LSP adapters can rank without hiding recovery candidates.
	Field constraintPriority:Int
End Type

Type TTypeCompletionResult
	Field scope:TScope
	Field isNewExpression:Int
	Field prefix:String
	Field genericOwner:TSymbol
	Field genericParameter:TSymbol
	Field genericArgumentIndex:Int = -1
	Field candidates:TTypeCompletionCandidate[] = New TTypeCompletionCandidate[0]
End Type

Type TTypeCompletion
	Function Query:TTypeCompletionResult(model:TSemanticModel, navigator:TSyntaxNavigator, offset:Int)
		If Not model Or Not navigator Or Not navigator.tree Or Not navigator.tree.source Then Return Null
		Local queryOffset:Int = Min(offset, navigator.tree.source.Length())
		If queryOffset > 0 Then queryOffset :- 1
		Local syntax:TSyntaxLocation = TSyntaxLocation.Locate(navigator, queryOffset)
		Local genericOpenOffset:Int = GenericArgumentOpen(navigator.tree.source, offset)
		Local inTypePosition:Int = genericOpenOffset >= 0
		Local ordinaryTypePosition:Int
		Local isNewExpression:Int
		If syntax Then
			For Local node:TSyntaxNode = EachIn syntax.parents
				If TTypeReferenceSyntax(node) Then inTypePosition = True; ordinaryTypePosition = True
				If TNewExpressionSyntax(node) Then isNewExpression = True
			Next
		End If
		If Not ordinaryTypePosition Then ordinaryTypePosition = LexicalTypePosition(navigator.tree.source, offset, isNewExpression)
		If ordinaryTypePosition Then inTypePosition = True
		If Not inTypePosition Then Return Null

		Local result:TTypeCompletionResult = New TTypeCompletionResult
		result.isNewExpression = isNewExpression
		result.prefix = IdentifierPrefix(navigator.tree.source, offset)
		Local location:TSemanticLocation = TSemanticLocation.Query(model, navigator, queryOffset)
		If location Then result.scope = location.scope
		If Not result.scope Then result.scope = model.globalScope
		Local seen:TMap = New TMap

		For Local value:Object = EachIn model.builtinTypes.Values()
			Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
			If Not builtin Or builtin.name.ToLower() = "null" Then Continue
			If isNewExpression And builtin.name.ToLower() = "void" Then Continue
			AddBuiltin(result.candidates, builtin, seen)
		Next

		Local scope:TScope = result.scope
		While scope
			CollectScope(result.candidates, scope, isNewExpression, False, seen, model, result.scope)
			scope = scope.parent
		Wend
		CollectImports(result.candidates, model.directImportedScopes, model, result.scope, isNewExpression, False, 2, seen)
		CollectImports(result.candidates, model.importedScopes, model, result.scope, isNewExpression, True, 3, seen)
		If genericOpenOffset >= 0 Then
			ApplyGenericArgumentContext(result, model, navigator, genericOpenOffset, offset)
			' A comparison such as `value < partial` is not a type position.
			If Not result.genericOwner And Not ordinaryTypePosition Then Return Null
		End If
		Return result
	End Function

	' Finds the nearest unmatched generic '<'. The semantic owner check performed
	' later rejects comparison operators while this remains tolerant of missing
	' closing brackets and nested, partially written arguments.
	Function GenericArgumentOpen:Int(source:TSourceText, offset:Int)
		If Not source Then Return -1
		Local cursor:Int = Min(offset, source.Length()) - 1
		Local depth:Int
		While cursor >= 0
			Local value:Int = source.text[cursor]
			If value = Asc(">") Then
				depth :+ 1
			Else If value = Asc("<") Then
				If depth = 0 Then Return cursor
				depth :- 1
			Else If depth = 0 And (value = 10 Or value = 13) Then
				Return -1
			End If
			cursor :- 1
		Wend
		Return -1
	End Function

	Function ApplyGenericArgumentContext(result:TTypeCompletionResult, model:TSemanticModel, navigator:TSyntaxNavigator, openOffset:Int, offset:Int)
		Local ownerEnd:Int = openOffset
		Local ownerStart:Int = ownerEnd
		While ownerStart > 0 And TBlitzMaxLexer.IsHorizontalWhitespace(navigator.tree.source.text[ownerStart - 1]); ownerStart :- 1; ownerEnd :- 1; Wend
		While ownerStart > 0 And TBlitzMaxLexer.IsIdentifierPart(navigator.tree.source.text[ownerStart - 1]); ownerStart :- 1; Wend
		If ownerStart = ownerEnd Then Return
		Local ownerName:String = navigator.tree.source.text[ownerStart..ownerEnd]
		Local owner:TSymbol

		' Member routine specializations need the constructed receiver lookup used
		' by ordinary member completion, including inherited/imported members.
		Local member:TMemberCompletionResult = TMemberCompletion.Query(model, navigator, openOffset)
		If member Then owner = GenericRoutineNamed(member.symbols, ownerName)
		If Not owner Then
			For Local symbol:TSymbol = EachIn result.scope.Lookup(ownerName)
				If IsGenericOwner(symbol) Then owner = symbol; Exit
			Next
		End If
		If Not owner Then
			For Local candidate:TTypeCompletionCandidate = EachIn result.candidates
				If candidate.symbol And candidate.symbol.normalizedName = ownerName.ToLower() And IsGenericOwner(candidate.symbol) Then owner = candidate.symbol; Exit
			Next
		End If
		If Not owner Then
			Local contextual:TContextualCompletionResult = TContextualCompletion.Query(model, navigator, openOffset)
			If contextual Then owner = GenericRoutineNamed(contextual.symbols, ownerName)
		End If
		If Not owner Then Return

		Local argumentIndex:Int = GenericArgumentIndex(navigator.tree.source, openOffset, offset)
		Local parameters:TSymbol[] = GenericParameters(owner)
		If argumentIndex < 0 Or argumentIndex >= parameters.length Then Return
		result.genericOwner = owner
		result.genericParameter = parameters[argumentIndex]
		result.genericArgumentIndex = argumentIndex
		Local bounds:TSemanticType[] = ConstraintBounds(model, owner, result.genericParameter)
		If Not bounds.length Then Return
		Local substitutions:TMap = New TMap
		If member And owner.kind = SYMBOL_ROUTINE And owner.containingScope Then
			Local declaringType:TSemanticType = TMemberCompletion.ConstructedDeclaringType(model, member.receiverType, owner)
			If declaringType Then substitutions = TMemberCompletion.TypeSubstitutions(declaringType)
		End If
		AddEarlierArgumentSubstitutions(substitutions, result, navigator.tree.source, openOffset, offset, parameters, argumentIndex)
		Local validator:TInheritanceValidator = New TInheritanceValidator
		validator.model = model
		For Local candidate:TTypeCompletionCandidate = EachIn result.candidates
			Local candidateType:TSemanticType = CandidateType(candidate)
			If Not candidateType Then Continue
			candidate.constraintPriority = 0
			For Local bound:TSemanticType = EachIn bounds
				Local required:TSemanticType = TGenericRoutineInference.Substitute(bound, substitutions)
				If Not validator.IsSubtype(candidateType, required, 0) Then
					' An open type parameter can later be specialized compatibly; keep it
					' neutral unless the semantic model proves that it satisfies the bound.
					If candidate.symbol And candidate.symbol.kind = SYMBOL_TYPE_PARAMETER Then Exit
					candidate.constraintPriority = 1
					Exit
				End If
			Next
		Next
	End Function

	Function AddEarlierArgumentSubstitutions(substitutions:TMap, result:TTypeCompletionResult, source:TSourceText, openOffset:Int, offset:Int, parameters:TSymbol[], activeIndex:Int)
		If activeIndex <= 0 Then Return
		Local segmentStart:Int = openOffset + 1
		Local argumentIndex:Int
		Local depth:Int
		For Local cursor:Int = segmentStart Until Min(offset, source.Length())
			Select source.text[cursor]
				Case Asc("<") depth :+ 1
				Case Asc(">") If depth > 0 Then depth :- 1
				Case Asc(",")
					If depth = 0 Then
						If argumentIndex < activeIndex And argumentIndex < parameters.length Then
							Local semanticType:TSemanticType = CandidateTypeNamed(result.candidates, source.text[segmentStart..cursor].Trim())
							If semanticType Then substitutions.Insert(parameters[argumentIndex], semanticType)
						End If
						argumentIndex :+ 1
						segmentStart = cursor + 1
					End If
			End Select
		Next
	End Function

	Function CandidateTypeNamed:TSemanticType(candidates:TTypeCompletionCandidate[], name:String)
		If Not name.length Then Return Null
		For Local candidate:TTypeCompletionCandidate = EachIn candidates
			If candidate.name.ToLower() = name.ToLower() Then Return CandidateType(candidate)
		Next
		Return Null
	End Function

	Function GenericArgumentIndex:Int(source:TSourceText, openOffset:Int, offset:Int)
		Local result:Int
		Local depth:Int
		For Local cursor:Int = openOffset + 1 Until Min(offset, source.Length())
			Select source.text[cursor]
				Case Asc("<") depth :+ 1
				Case Asc(">") If depth > 0 Then depth :- 1
				Case Asc(",") If depth = 0 Then result :+ 1
			End Select
		Next
		Return result
	End Function

	Function IsGenericOwner:Int(symbol:TSymbol)
		If Not symbol Or symbol.genericArity <= 0 Then Return False
		Return symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_STRUCT Or symbol.kind = SYMBOL_INTERFACE Or symbol.kind = SYMBOL_ROUTINE
	End Function

	Function GenericRoutineNamed:TSymbol(symbols:TSymbol[], name:String)
		For Local symbol:TSymbol = EachIn symbols
			If symbol.kind = SYMBOL_ROUTINE And symbol.genericArity > 0 And symbol.normalizedName = name.ToLower() Then Return symbol
		Next
		Return Null
	End Function

	Function GenericParameters:TSymbol[](owner:TSymbol)
		Local result:TSymbol[]
		If Not owner Or Not owner.memberScope Then Return result
		For Local symbol:TSymbol = EachIn owner.memberScope.declaredSymbols
			If symbol.kind = SYMBOL_TYPE_PARAMETER Then result :+ [symbol]
		Next
		Return result
	End Function

	Function ConstraintBounds:TSemanticType[](model:TSemanticModel, owner:TSymbol, parameter:TSymbol)
		Local constraints:TGenericConstraintInfo[]
		If owner.kind = SYMBOL_ROUTINE Then
			constraints = owner.genericConstraints
		Else
			Local info:TTypeInheritanceInfo = model.InheritanceInfo(owner)
			If info Then constraints = info.constraints
		End If
		For Local constraint:TGenericConstraintInfo = EachIn constraints
			If constraint.parameterSymbol = parameter Then Return constraint.bounds
		Next
		Return New TSemanticType[0]
	End Function

	Function CandidateType:TSemanticType(candidate:TTypeCompletionCandidate)
		If candidate.builtinType Then Return candidate.builtinType
		If Not candidate.symbol Then Return Null
		If candidate.symbol.declaredType Then Return candidate.symbol.declaredType
		Select candidate.symbol.kind
			Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE, SYMBOL_ENUM
				Local named:TNamedSemanticType = New TNamedSemanticType
				named.kind = SEMANTIC_TYPE_NAMED
				named.symbol = candidate.symbol
				Return named
		End Select
		Return Null
	End Function

	Function IdentifierPrefix:String(source:TSourceText, offset:Int)
		Local finish:Int = Min(offset, source.Length())
		Local start:Int = finish
		While start > 0 And TBlitzMaxLexer.IsIdentifierPart(source.text[start - 1]); start :- 1; Wend
		Return source.text[start..finish]
	End Function

	Function LexicalTypePosition:Int(source:TSourceText, offset:Int, isNewExpression:Int Var)
		Local cursor:Int = Min(offset, source.Length()) - 1
		While cursor >= 0 And TBlitzMaxLexer.IsIdentifierPart(source.text[cursor]); cursor :- 1; Wend
		While cursor >= 0 And TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor]); cursor :- 1; Wend
		If cursor >= 0 And source.text[cursor] = Asc(":") Then Return True
		Local wordEnd:Int = cursor + 1
		While cursor >= 0 And TBlitzMaxLexer.IsIdentifierPart(source.text[cursor]); cursor :- 1; Wend
		Local word:String = source.text[cursor + 1..wordEnd].ToLower()
		If word = "new" Then isNewExpression = True; Return True
		Return word = "extends" Or word = "implements"
	End Function

	Function AddBuiltin(candidates:TTypeCompletionCandidate[] Var, builtin:TBuiltinSemanticType, seen:TMap)
		Local name:String = builtin.name.ToLower()
		If seen.Contains(name) Then Return
		Local candidate:TTypeCompletionCandidate = New TTypeCompletionCandidate
		candidate.name = builtin.name
		candidate.builtinType = builtin
		candidate.priority = 1
		candidates :+ [candidate]
		seen.Insert(name, candidate)
	End Function

	Function CollectScope(candidates:TTypeCompletionCandidate[] Var, scope:TScope, isNewExpression:Int, imported:Int, seen:TMap, model:TSemanticModel, accessScope:TScope)
		If Not scope Then Return
		Local names:TMap = New TMap
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not IsCandidate(symbol, isNewExpression, imported, model, accessScope) Or seen.Contains(symbol.normalizedName) Then Continue
			AddSymbol(candidates, symbol, 0)
			names.Insert(symbol.normalizedName, symbol)
		Next
		For Local name:Object = EachIn names.Keys()
			seen.Insert(name, names.ValueForKey(name))
		Next
	End Function

	Function CollectImports(candidates:TTypeCompletionCandidate[] Var, scopes:TScope[], model:TSemanticModel, accessScope:TScope, isNewExpression:Int, skipDirect:Int, priority:Int, seen:TMap)
		Local names:TMap = New TMap
		For Local scope:TScope = EachIn scopes
			If skipDirect And IsDirectImport(model, scope) Then Continue
			For Local symbol:TSymbol = EachIn scope.declaredSymbols
				If Not IsCandidate(symbol, isNewExpression, True, model, accessScope) Or seen.Contains(symbol.normalizedName) Then Continue
				AddSymbol(candidates, symbol, priority)
				names.Insert(symbol.normalizedName, symbol)
			Next
		Next
		For Local name:Object = EachIn names.Keys()
			seen.Insert(name, names.ValueForKey(name))
		Next
	End Function

	Function AddSymbol(candidates:TTypeCompletionCandidate[] Var, symbol:TSymbol, priority:Int)
		Local candidate:TTypeCompletionCandidate = New TTypeCompletionCandidate
		candidate.name = symbol.name
		candidate.symbol = symbol
		candidate.priority = priority
		candidates :+ [candidate]
	End Function

	Function IsCandidate:Int(symbol:TSymbol, isNewExpression:Int, imported:Int, model:TSemanticModel, accessScope:TScope)
		If Not symbol Then Return False
		Select symbol.kind
			Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE, SYMBOL_ENUM, SYMBOL_TYPE_PARAMETER
			Default Return False
		End Select
		If symbol.kind <> SYMBOL_TYPE_PARAMETER And Not TSymbolAccessibility.IsAccessible(symbol, accessScope, model) Then Return False
		If isNewExpression And (symbol.kind = SYMBOL_INTERFACE Or symbol.kind = SYMBOL_ENUM) Then Return False
		Return True
	End Function

	Function IsDirectImport:Int(model:TSemanticModel, scope:TScope)
		For Local direct:TScope = EachIn model.directImportedScopes
			If direct = scope Then Return True
		Next
		Return False
	End Function
End Type
