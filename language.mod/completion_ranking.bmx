' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "conversion_classification.bmx"
Import "generic_routine_inference.bmx"
Import "lexer.bmx"
Import "semantic_model.bmx"
Import "syntax_navigation.bmx"

Const COMPLETION_EXPECTED_ASSIGNMENT:Int = 1
Const COMPLETION_EXPECTED_ARGUMENT:Int = 2

' Protocol-independent ranking context shared by editor integrations. It only
' prioritizes candidates: incomplete syntax can make contextual information
' uncertain, so no symbol is removed for being incompatible with an expected
' type or the currently written argument list.
Type TCompletionRankingContext
	Field prefix:String
	Field expectedType:TSemanticType
	Field expectedKind:Int
	Field callSignatures:TCallSignatureSet
	Field conversions:TConversionClassifier

	Function Query:TCompletionRankingContext(model:TSemanticModel, navigator:TSyntaxNavigator, offset:Int)
		If Not model Or Not navigator Or Not navigator.tree Or Not navigator.tree.source Then Return Null
		Local result:TCompletionRankingContext = New TCompletionRankingContext
		result.prefix = IdentifierPrefix(navigator.tree.source, offset)
		result.conversions = TConversionClassifier.Create(model)
		Local queryOffset:Int = Min(offset, navigator.tree.source.Length())
		If queryOffset > 0 Then queryOffset :- 1
		Local syntax:TSyntaxLocation = TSyntaxLocation.Locate(navigator, queryOffset)
		If Not syntax Then Return result
		For Local node:TSyntaxNode = EachIn syntax.parents
			Local call:TCallExpressionSyntax = TCallExpressionSyntax(node)
			If call And call.openToken Then
				Local signatures:TCallSignatureSet = model.CallSignatures(call)
				If signatures Then result.callSignatures = signatures
				If offset >= call.openToken.span.EndOffset() Then
					result.expectedType = ExpectedParameter(result.callSignatures, ActiveArgument(call.arguments, offset, navigator.tree.source))
					If result.expectedType Then result.expectedKind = COMPLETION_EXPECTED_ARGUMENT
					Return result
				End If
				Continue
			End If
			Local callStatement:TCallStatementSyntax = TCallStatementSyntax(node)
			If callStatement Then
				Local signatures:TCallSignatureSet = model.CallSignatures(callStatement)
				If signatures Then result.callSignatures = signatures
				If callStatement.argumentExpressions.length And (Not callStatement.expression Or offset > callStatement.expression.span.EndOffset()) Then
					result.expectedType = ExpectedParameter(result.callSignatures, ActiveArgument(callStatement.argumentExpressions, offset, navigator.tree.source))
					If result.expectedType Then result.expectedKind = COMPLETION_EXPECTED_ARGUMENT
					Return result
				End If
				Continue
			End If
			Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(node)
			If declarator And declarator.assignmentToken And offset >= declarator.assignmentToken.span.EndOffset() Then
				Local symbol:TSymbol = model.DeclaredSymbol(declarator)
				' An inferred initializer is deliberately bound without a target
				' type, so completion must not invent one from its recovery symbol.
				If symbol And Not declarator.inferenceToken Then result.expectedType = symbol.declaredType
				If result.expectedType Then result.expectedKind = COMPLETION_EXPECTED_ASSIGNMENT
				Return result
			End If
			Local assignment:TAssignmentStatementSyntax = TAssignmentStatementSyntax(node)
			If assignment And assignment.operatorToken And offset >= assignment.operatorToken.span.EndOffset() Then
				result.expectedType = ExpressionType(model, assignment.left)
				If result.expectedType Then result.expectedKind = COMPLETION_EXPECTED_ASSIGNMENT
				Return result
			End If
			Local returnStatement:TReturnStatementSyntax = TReturnStatementSyntax(node)
			If returnStatement And returnStatement.returnToken And offset >= returnStatement.returnToken.span.EndOffset() Then
				Local scope:TScope = model.ScopeFor(returnStatement)
				Local routine:TSymbol = EnclosingRoutine(scope)
				If routine Then result.expectedType = routine.declaredType
				If result.expectedType Then result.expectedKind = COMPLETION_EXPECTED_ASSIGNMENT
				Return result
			End If
		Next
		Return result
	End Function

	Method SortKey:String(symbol:TSymbol, useSiteType:TSemanticType, resolved:TResolvedCall, sourceOrder:Int)
		Local name:String
		If symbol Then name = symbol.name
		Local prefixRank:Int = PrefixRank(name, prefix)
		Local expectedRank:Int = ExpectedRank(symbol, useSiteType, resolved)
		Local overloadRank:Int = OverloadRank(symbol)
		Return prefixRank + "" + expectedRank + overloadRank + Padded(sourceOrder) + name.ToLower()
	End Method

	Method ExpectedRank:Int(symbol:TSymbol, useSiteType:TSemanticType, resolved:TResolvedCall)
		If Not expectedType Then Return 2
		Local actual:TSemanticType = useSiteType
		If symbol And symbol.kind = SYMBOL_ROUTINE Then
			If resolved And resolved.returnType Then actual = resolved.returnType Else actual = symbol.declaredType
		Else If Not actual And symbol Then
			actual = symbol.declaredType
		End If
		If Not actual Then Return 2
		Local conversion:TConversion
		If expectedKind = COMPLETION_EXPECTED_ARGUMENT Then
			conversion = conversions.ClassifyArgumentExpression(Null, actual, expectedType)
		Else
			conversion = conversions.ClassifyAssignmentExpression(Null, actual, expectedType)
		End If
		If Not conversion.Exists() Then Return 3
		If conversion.kind = CONVERSION_IDENTITY Then Return 0
		Return 1
	End Method

	Method OverloadRank:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or Not callSignatures Then Return 2
		Local found:Int
		Local compatible:Int
		For Local candidate:TCallSignatureCandidate = EachIn callSignatures.candidates
			If candidate.routine <> symbol Then Continue
			found = True
			If candidate.selected Then Return 0
			If candidate.compatible Then compatible = True
		Next
		If compatible Then Return 1
		If found Then Return 3
		Return 2
	End Method

	Function IdentifierPrefix:String(source:TSourceText, offset:Int)
		If Not source Then Return ""
		Local finish:Int = Min(offset, source.Length())
		Local start:Int = finish
		While start > 0 And TBlitzMaxLexer.IsIdentifierPart(source.text[start - 1]); start :- 1; Wend
		Return source.text[start..finish]
	End Function

	Function PrefixRank:Int(name:String, prefix:String)
		Local lowerName:String = name.ToLower()
		Local lowerPrefix:String = prefix.ToLower()
		If Not lowerPrefix.length Then Return 1
		If lowerName = lowerPrefix Then Return 0
		If lowerName.StartsWith(lowerPrefix) Then Return 1
		If lowerName.Contains(lowerPrefix) Then Return 2
		Return 3
	End Function

	Function ExpectedParameter:TSemanticType(signatures:TCallSignatureSet, index:Int)
		If Not signatures Or index < 0 Then Return Null
		For Local candidate:TCallSignatureCandidate = EachIn signatures.candidates
			If candidate.selected And index < candidate.parameterTypes.length Then Return candidate.parameterTypes[index]
		Next
		Local expected:TSemanticType
		Local hasCompatible:Int
		For Local candidate:TCallSignatureCandidate = EachIn signatures.candidates
			If Not candidate.compatible Or index >= candidate.parameterTypes.length Then Continue
			hasCompatible = True
			If Not expected Then
				expected = candidate.parameterTypes[index]
			Else If Not TGenericRoutineInference.SameType(expected, candidate.parameterTypes[index]) Then
				Return Null
			End If
		Next
		If hasCompatible Then Return expected
		For Local candidate:TCallSignatureCandidate = EachIn signatures.candidates
			If index >= candidate.parameterTypes.length Then Continue
			If Not expected Then
				expected = candidate.parameterTypes[index]
			Else If Not TGenericRoutineInference.SameType(expected, candidate.parameterTypes[index]) Then
				Return Null
			End If
		Next
		Return expected
	End Function

	Function ActiveArgument:Int(arguments:TExpressionSyntax[], offset:Int, source:TSourceText)
		If Not arguments.length Then Return 0
		For Local index:Int = 0 Until arguments.length
			Local argument:TExpressionSyntax = arguments[index]
			If argument And offset <= argument.span.EndOffset() Then Return index
			If index + 1 < arguments.length And arguments[index + 1] And offset < arguments[index + 1].span.start Then Return index + 1
		Next
		Local active:Int = arguments.length - 1
		Local last:TExpressionSyntax = arguments[arguments.length - 1]
		If last And offset > last.span.EndOffset() And source.Slice(TSourceSpan.Create(last.span.EndOffset(), offset - last.span.EndOffset())).Contains(",") Then active :+ 1
		Return active
	End Function

	Function ExpressionType:TSemanticType(model:TSemanticModel, expression:TExpressionSyntax)
		If Not model Or Not expression Then Return Null
		Local semanticType:TSemanticType = model.ExpressionType(expression)
		If semanticType Then Return semanticType
		Local bound:TBoundExpression = model.BoundExpression(expression)
		If bound Then Return bound.semanticType
		Return Null
	End Function

	Function EnclosingRoutine:TSymbol(scope:TScope)
		While scope
			If scope.kind = SCOPE_ROUTINE Then Return scope.owner
			scope = scope.parent
		Wend
		Return Null
	End Function

	Function Padded:String(value:Int)
		If value < 10 Then Return "00000" + value
		If value < 100 Then Return "0000" + value
		If value < 1000 Then Return "000" + value
		If value < 10000 Then Return "00" + value
		If value < 100000 Then Return "0" + value
		Return value
	End Function
End Type
