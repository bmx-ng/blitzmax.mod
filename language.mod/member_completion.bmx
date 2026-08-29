' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.LinkedList

Import "lexer.bmx"
Import "expression_parser.bmx"
Import "generic_routine_inference.bmx"
Import "semantic_model.bmx"
Import "symbol_accessibility.bmx"
Import "syntax_navigation.bmx"
Import "type_resolution.bmx"

' A protocol-independent description of the member access being completed.
' The semantic symbols remain sourced from the analyzed model, including
' compiler-interface symbols loaded from dependency snapshots.
Type TMemberCompletionResult
	Field receiver:TExpressionSyntax
	Field receiverType:TSemanticType
	Field owner:TSymbol
	Field accessScope:TScope
	Field isStatic:Int
	Field symbols:TSymbol[] = New TSymbol[0]
End Type

Type TMemberCompletion
	Function EffectiveMemberType:TSemanticType(model:TSemanticModel, receiverType:TSemanticType, member:TSymbol, declaringType:TSemanticType = Null)
		If Not member Then Return Null
		If Not declaringType Then declaringType = ConstructedDeclaringType(model, receiverType, member)
		If Not declaringType Then Return member.declaredType
		Return TGenericRoutineInference.Substitute(member.declaredType, TypeSubstitutions(declaringType))
	End Function

	Function EffectiveRoutine:TResolvedCall(model:TSemanticModel, receiverType:TSemanticType, routine:TSymbol, declaringType:TSemanticType = Null)
		If Not routine Or routine.kind <> SYMBOL_ROUTINE Then Return Null
		If Not declaringType Then declaringType = ConstructedDeclaringType(model, receiverType, routine)
		If Not declaringType Then Return Null
		Local substitutions:TMap = TypeSubstitutions(declaringType)
		Local result:TResolvedCall = New TResolvedCall
		result.routine = routine
		result.returnType = TGenericRoutineInference.Substitute(routine.declaredType, substitutions)
		result.parameterTypes = New TSemanticType[routine.parameterTypes.length]
		For Local index:Int = 0 Until routine.parameterTypes.length
			result.parameterTypes[index] = TGenericRoutineInference.Substitute(routine.parameterTypes[index], substitutions)
		Next
		Return result
	End Function

	Function ConstructedDeclaringType:TSemanticType(model:TSemanticModel, receiverType:TSemanticType, member:TSymbol)
		If Not model Or Not receiverType Or Not member Or Not member.containingScope Then Return Null
		Return FindConstructedAncestor(model, receiverType, member.containingScope.owner, New TMap, 0)
	End Function

	Function FindConstructedAncestor:TSemanticType(model:TSemanticModel, receiverType:TSemanticType, target:TSymbol, visited:TMap, depth:Int)
		If Not model Or Not target Or depth > 64 Then Return Null
		Local named:TNamedSemanticType = TNamedSemanticType(receiverType)
		If Not named Or Not named.symbol Then Return Null
		If named.symbol = target Then Return named
		If visited.Contains(named.symbol) Then Return Null
		visited.Insert(named.symbol, named.symbol)
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not info Then
			visited.Remove(named.symbol)
			Return Null
		End If
		Local substitutions:TMap = TypeSubstitutions(named)
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			Local inheritedType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, substitutions)
			Local found:TSemanticType = FindConstructedAncestor(model, inheritedType, target, visited, depth + 1)
			If found Then Return found
		Next
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
			Local inheritedType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, substitutions)
			Local found:TSemanticType = FindConstructedAncestor(model, inheritedType, target, visited, depth + 1)
			If found Then Return found
		Next
		visited.Remove(named.symbol)
		Return Null
	End Function

	Function TypeSubstitutions:TMap(semanticType:TSemanticType)
		Local result:TMap = New TMap
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If Not named Or Not named.symbol Or Not named.symbol.memberScope Then Return result
		Local parameters:TSymbol[]
		For Local symbol:TSymbol = EachIn named.symbol.memberScope.declaredSymbols
			If symbol.kind = SYMBOL_TYPE_PARAMETER Then parameters :+ [symbol]
		Next
		For Local index:Int = 0 Until Min(parameters.length, named.typeArguments.length)
			result.Insert(parameters[index], named.typeArguments[index])
		Next
		Return result
	End Function

	Function Query:TMemberCompletionResult(model:TSemanticModel, navigator:TSyntaxNavigator, offset:Int)
		If Not model Or Not navigator Or Not navigator.tree Or Not navigator.tree.source Then Return Null
		Local dotOffset:Int = FindCompletionDot(navigator.tree.source, offset)
		If dotOffset < 0 Then Return Null
		Local receiverOffset:Int = dotOffset - 1
		While receiverOffset >= 0 And TBlitzMaxLexer.IsHorizontalWhitespace(navigator.tree.source.text[receiverOffset])
			receiverOffset :- 1
		Wend
		If receiverOffset < 0 Then Return Null
		Local node:TSyntaxNode = navigator.NodeAt(receiverOffset)
		Local receiver:TExpressionSyntax
		While node And Not receiver
			receiver = TExpressionSyntax(node)
			If Not receiver Then node = navigator.Parent(node)
		Wend
		If Not receiver Then receiver = TokenReceiver(navigator.TokenAt(receiverOffset))
		If Not receiver Then Return Null
		' An incomplete trailing member access can make the expression parser
		' preserve the entire expression as a recovery node. Reparse only the
		' valid prefix before the dot so completion can still identify a simple
		' receiver inside parenthesis-free call arguments such as Print value.
		Local raw:TRawExpressionSyntax = TRawExpressionSyntax(receiver)
		If raw Then
			' A literal or simple-name token immediately before the completion dot
			' is the unambiguous receiver, even when the surrounding unfinished call
			' can itself be parsed as a recovery expression.
			Local recovered:TExpressionSyntax = TokenReceiver(navigator.TokenAt(receiverOffset))
			If Not recovered Then recovered = ReceiverPrefix(raw, dotOffset)
			If recovered Then receiver = recovered
		End If

		Local result:TMemberCompletionResult = New TMemberCompletionResult
		result.receiver = receiver
		result.receiverType = model.ExpressionType(receiver)
		Local bound:TBoundExpression = model.BoundExpression(receiver)
		If Not result.receiverType And bound Then result.receiverType = bound.semanticType
		If Not result.receiverType Then result.receiverType = RecoveredExpressionType(model, receiver)
		Local location:TSemanticLocation = TSemanticLocation.Query(model, navigator, receiverOffset)
		If location Then result.accessScope = location.scope

		' Built-in type names are linked to compiler-provided runtime symbols but
		' are not ordinary declarations in the visible source scope. Resolve them
		' explicitly for static access such as String.FromInt(...).
		Local receiverName:TNameExpressionSyntax = TNameExpressionSyntax(receiver)
		If receiverName And receiverName.nameToken Then
			Local builtin:TBuiltinSemanticType = model.BuiltinType(receiverName.nameToken.text)
			If builtin And builtin.runtimeSymbol Then
				result.owner = builtin.runtimeSymbol
				result.isStatic = True
			End If
		End If

		' Imported type names are visible through type resolution rather than the
		' lexical scope chain. Use the same lookup as semantic binding so an
		' incomplete qualifier such as TPath. exposes its Type Functions.
		If receiverName And receiverName.nameToken And result.accessScope And Not result.owner Then
			Local typeResolver:TTypeResolver = New TTypeResolver
			typeResolver.model = model
			typeResolver.options = New TTypeResolutionOptions
			typeResolver.InitializeImportedScopeSet()
			Local typeCandidates:TSymbol[] = typeResolver.LookupTypeCandidates(result.accessScope, receiverName.nameToken.text)
			If typeCandidates.length = 1 Then
				result.owner = typeCandidates[0]
				result.isStatic = True
				If receiverName.typeArguments.length = 0 Then result.receiverType = typeCandidates[0].declaredType
			End If
		End If

		If Not result.receiverType Then
			If receiverName And result.accessScope And Not result.owner Then
				For Local symbol:TSymbol = EachIn result.accessScope.Lookup(receiverName.nameToken.text)
					If symbol.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then
						result.owner = symbol
						result.isStatic = True
						Exit
					End If
					If symbol.declaredType Then
						result.receiverType = symbol.declaredType
						Exit
					End If
				Next
			End If
		End If

		If Not result.owner Then result.owner = OwnerForType(model, result.receiverType)
		If Not result.owner Then Return Null
		Local seenSymbols:TMap = New TMap
		Local visitedTypes:TMap = New TMap
		CollectTypeMembers(result.symbols, model, result.owner, result.accessScope, result.isStatic, seenSymbols, visitedTypes)
		Return result
	End Function

	' A literal followed by an incomplete member access can be represented as a
	' raw statement rather than an expression node. Preserve its source token in
	' a lightweight recovery expression so intrinsic typing remains available.
	Function IntrinsicReceiver:TExpressionSyntax(token:TSyntaxToken)
		If Not token Then Return Null
		Select token.kind
			Case TOKEN_STRING_LITERAL, TOKEN_MULTILINE_STRING_LITERAL, TOKEN_FLOAT_LITERAL, TOKEN_INTEGER_LITERAL
				Local literal:TLiteralExpressionSyntax = New TLiteralExpressionSyntax
				literal.kind = SYNTAX_LITERAL_EXPRESSION
				literal.literalToken = token
				literal.span = token.span
				Return literal
		End Select
		Return Null
	End Function

	' A parenthesized unfinished call can collapse its entire argument list into
	' a raw recovery expression. Preserve a simple name immediately before the
	' completion dot so normal lexical/type lookup can recover its declared type.
	Function TokenReceiver:TExpressionSyntax(token:TSyntaxToken)
		Local intrinsic:TExpressionSyntax = IntrinsicReceiver(token)
		If intrinsic Then Return intrinsic
		If Not token Or token.kind <> TOKEN_IDENTIFIER Then Return Null
		Local name:TNameExpressionSyntax = New TNameExpressionSyntax
		name.kind = SYNTAX_NAME_EXPRESSION
		name.nameToken = token
		name.span = token.span
		Return name
	End Function

	' ReceiverPrefix creates recovery syntax that is intentionally not inserted
	' into the immutable semantic model. Primitive literals have an intrinsic
	' type, so recover it directly for incomplete accesses such as "text".
	Function RecoveredExpressionType:TSemanticType(model:TSemanticModel, expression:TExpressionSyntax)
		If Not model Or Not expression Then Return Null
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If literal And literal.literalToken Then
			Select literal.literalToken.kind
				Case TOKEN_STRING_LITERAL, TOKEN_MULTILINE_STRING_LITERAL Return model.BuiltinType("String")
				Case TOKEN_FLOAT_LITERAL Return model.BuiltinType("Double")
				Case TOKEN_INTEGER_LITERAL Return model.BuiltinType("Int")
			End Select
			Select literal.literalToken.text.ToLower()
				Case "true", "false" Return model.BuiltinType("Int")
				Case "null" Return model.BuiltinType("Null")
				Case "pi" Return model.BuiltinType("Double")
			End Select
		End If
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parenthesized Then Return RecoveredExpressionType(model, parenthesized.expression)
		Return Null
	End Function

	Function ReceiverPrefix:TExpressionSyntax(raw:TRawExpressionSyntax, dotOffset:Int)
		If Not raw Or raw.tokens.length = 0 Then Return Null
		For Local index:Int = 0 Until raw.tokens.length
			Local token:TSyntaxToken = raw.tokens[index]
			If Not token Or token.text <> "." Or token.span.start <> dotOffset Then Continue
			If index = 0 Then Return Null
			Local parsed:TExpressionParseResult = TBlitzMaxExpressionParser.ParsePrefix(raw.tokens[..index], New TList)
			If parsed And parsed.expression And parsed.consumed = index Then Return parsed.expression
			Return Null
		Next
		Return Null
	End Function

	Function FindCompletionDot:Int(source:TSourceText, offset:Int)
		If Not source Then Return -1
		Local cursor:Int = Min(offset, source.Length()) - 1
		While cursor >= 0 And TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor])
			cursor :- 1
		Wend
		While cursor >= 0 And TBlitzMaxLexer.IsIdentifierPart(source.text[cursor])
			cursor :- 1
		Wend
		While cursor >= 0 And TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor])
			cursor :- 1
		Wend
		If cursor >= 0 And source.text[cursor] = 46 Then Return cursor
		Return -1
	End Function

	Function OwnerForType:TSymbol(model:TSemanticModel, semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named Then Return named.symbol
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If builtin Then Return builtin.runtimeSymbol
		If TArraySemanticType(semanticType) Then Return model.ArrayIntrinsic()
		If TStaticArraySemanticType(semanticType) Then Return model.StaticArrayIntrinsic()
		Return Null
	End Function

	Function CollectTypeMembers(symbols:TSymbol[] Var, model:TSemanticModel, owner:TSymbol, accessScope:TScope, isStatic:Int, seenSymbols:TMap, visitedTypes:TMap)
		If Not owner Or visitedTypes.Contains(owner) Then Return
		visitedTypes.Insert(owner, owner)
		If owner.memberScope Then
			For Local symbol:TSymbol = EachIn owner.memberScope.declaredSymbols
				If Not IsCompletionMember(symbol, isStatic) Or Not TSymbolAccessibility.IsAccessible(symbol, accessScope, model, owner) Then Continue
				If seenSymbols.Contains(symbol) Then Continue
				seenSymbols.Insert(symbol, symbol)
				symbols :+ [symbol]
			Next
		End If
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(owner)
		If Not info Then Return
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			CollectTypeMembers(symbols, model, OwnerForType(model, edge.semanticType), accessScope, isStatic, seenSymbols, visitedTypes)
		Next
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
			CollectTypeMembers(symbols, model, OwnerForType(model, edge.semanticType), accessScope, isStatic, seenSymbols, visitedTypes)
		Next
	End Function

	Function IsCompletionMember:Int(symbol:TSymbol, isStatic:Int)
		If Not symbol Then Return False
		Select symbol.kind
			Case SYMBOL_FIELD
				Return Not isStatic
			Case SYMBOL_GLOBAL, SYMBOL_CONST, SYMBOL_ENUM_MEMBER
				Return isStatic
			Case SYMBOL_ROUTINE
				' Constructors are selected through New Type(...), never through
				' instance or type member access.
				If symbol.normalizedName = "new" Then Return False
				Return IsInstanceRoutine(symbol) <> isStatic
		End Select
		Return False
	End Function

	Function IsInstanceRoutine:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return False
		If symbol.interfaceRecord Then Return symbol.interfaceRecord.kind = INTERFACE_RECORD_METHOD
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		Return declaration And declaration.isMethod
	End Function

End Type
