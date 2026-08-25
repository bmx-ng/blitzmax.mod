' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map

Import "semantic_model.bmx"
Import "syntax.bmx"

Rem
bbdoc: Provides indexed navigation over an immutable syntax tree.
about: Parent relationships are kept outside syntax nodes, so constructing a
navigator does not mutate the tree or alter parser objects held by other consumers.
End Rem
Type TSyntaxNavigator
	Field tree:TSyntaxTree
	Field nodes:TList = New TList
	Field parents:TMap = New TMap
	Field indexed:TMap = New TMap

	Rem
	bbdoc: Creates and populates a navigator for a syntax tree.
	param: The syntax tree to index.
	returns: A new navigator, or #Null if the tree has no root.
	End Rem
	Function Create:TSyntaxNavigator(tree:TSyntaxTree)
		If Not tree Or Not tree.root Then Return Null
		Local result:TSyntaxNavigator = New TSyntaxNavigator
		result.tree = tree
		result.IndexNode(tree.root, Null)
		Return result
	End Function

	Rem
	bbdoc: Finds the token containing a source offset.
	param: The zero-based source offset.
	returns: The token at the offset, or #Null.
	End Rem
	Method TokenAt:TSyntaxToken(offset:Int)
		If Not tree Or Not tree.root Then Return Null
		Local tokens:TSyntaxToken[] = tree.root.tokens
		Local low:Int
		Local high:Int = tokens.length
		While low < high
			Local middle:Int = low + (high - low) / 2
			If tokens[middle].span.start <= offset Then low = middle + 1 Else high = middle
		Wend
		Local index:Int = low - 1
		If index >= 0 And TokenContains(tokens[index], offset) Then Return tokens[index]
		If low < tokens.length And TokenContains(tokens[low], offset) Then Return tokens[low]
		Return Null
	End Method

	Rem
	bbdoc: Finds the smallest syntax node containing a source offset.
	param: The zero-based source offset.
	returns: The innermost node at the offset, or #Null.
	End Rem
	Method NodeAt:TSyntaxNode(offset:Int)
		Local best:TSyntaxNode
		For Local node:TSyntaxNode = EachIn nodes
			If Not SpanContains(node.span, offset) Then Continue
			If Not best Or node.span.length < best.span.length Then best = node
		Next
		Return best
	End Method

	Rem
	bbdoc: Returns the indexed parent of a syntax node.
	param: A node belonging to this navigator's tree.
	returns: The parent node, or #Null for the root or an unknown node.
	End Rem
	Method Parent:TSyntaxNode(node:TSyntaxNode)
		If Not node Then Return Null
		Return TSyntaxNode(parents.ValueForKey(node))
	End Method

	Rem
	bbdoc: Tests whether a syntax node belongs to this navigator's tree.
	param: The node to test.
	End Rem
	Method ContainsNode:Int(node:TSyntaxNode)
		Return node <> Null And indexed.Contains(node)
	End Method

	Rem
	bbdoc: Returns the chain of ancestors from a node towards the syntax-tree root.
	param: A node belonging to this navigator's tree.
	param: Whether the returned array begins with the supplied node.
	returns: The ordered ancestor chain.
	End Rem
	Method Ancestors:TSyntaxNode[](node:TSyntaxNode, includeSelf:Int = True)
		Local result:TSyntaxNode[]
		Local current:TSyntaxNode = node
		If Not includeSelf Then current = Parent(current)
		While current
			result :+ [current]
			current = Parent(current)
		Wend
		Return result
	End Method

	Method IndexNode(node:TSyntaxNode, parent:TSyntaxNode)
		If Not node Then Return
		If indexed.Contains(node) Then Return
		indexed.Insert(node, node)
		nodes.AddLast(node)
		If parent Then parents.Insert(node, parent)

		Local unit:TCompilationUnitSyntax = TCompilationUnitSyntax(node)
		If unit Then
			IndexChild(node, unit.sourceModeDeclaration)
			For Local child:TSyntaxNode = EachIn unit.members; IndexChild(node, child); Next
			Return
		End If
		Local block:TBlockSyntax = TBlockSyntax(node)
		If block Then
			For Local child:TSyntaxNode = EachIn block.statements; IndexChild(node, child); Next
			Return
		End If
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine Then IndexChild(node, routine.signature); IndexChild(node, routine.body); IndexChild(node, routine.terminator); Return
		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration Then IndexChild(node, typeDeclaration.header); IndexChild(node, typeDeclaration.body); IndexChild(node, typeDeclaration.terminator); Return
		Local external:TExternBlockSyntax = TExternBlockSyntax(node)
		If external Then IndexChild(node, external.body); IndexChild(node, external.terminator); Return
		Local typeHeader:TTypeDeclarationHeaderSyntax = TTypeDeclarationHeaderSyntax(node)
		If typeHeader Then
			For Local child:TGenericParameterSyntax = EachIn typeHeader.genericParameters; IndexChild(node, child); Next
			For Local child:TGenericConstraintSyntax = EachIn typeHeader.constraints; IndexChild(node, child); Next
			For Local child:TTypeReferenceSyntax = EachIn typeHeader.extendsTypes; IndexChild(node, child); Next
			For Local child:TTypeReferenceSyntax = EachIn typeHeader.implementedTypes; IndexChild(node, child); Next
			Return
		End If
		Local constraint:TGenericConstraintSyntax = TGenericConstraintSyntax(node)
		If constraint Then For Local child:TTypeReferenceSyntax = EachIn constraint.constraintTypes; IndexChild(node, child); Next; Return
		Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(node)
		If enumDeclaration Then
			IndexChild(node, enumDeclaration.underlyingType)
			For Local child:TEnumValueSyntax = EachIn enumDeclaration.values; IndexChild(node, child); Next
			IndexChild(node, enumDeclaration.terminator)
			Return
		End If
		Local enumValue:TEnumValueSyntax = TEnumValueSyntax(node)
		If enumValue Then IndexChild(node, enumValue.value); Return
		Local returned:TReturnStatementSyntax = TReturnStatementSyntax(node)
		If returned Then IndexChild(node, returned.expression); Return
		Local yielded:TYieldStatementSyntax = TYieldStatementSyntax(node)
		If yielded Then IndexChild(node, yielded.expression); Return
		Local thrown:TThrowStatementSyntax = TThrowStatementSyntax(node)
		If thrown Then IndexChild(node, thrown.expression); Return
		Local exited:TExitStatementSyntax = TExitStatementSyntax(node)
		If exited Then IndexChild(node, exited.label); Return
		Local continued:TContinueStatementSyntax = TContinueStatementSyntax(node)
		If continued Then IndexChild(node, continued.label); Return
		Local asserted:TAssertStatementSyntax = TAssertStatementSyntax(node)
		If asserted Then IndexChild(node, asserted.condition); IndexChild(node, asserted.message); Return
		Local released:TReleaseStatementSyntax = TReleaseStatementSyntax(node)
		If released Then IndexChild(node, released.expression); Return
		Local data:TDefDataStatementSyntax = TDefDataStatementSyntax(node)
		If data Then IndexChild(node, data.label); For Local child:TExpressionSyntax = EachIn data.values; IndexChild(node, child); Next; Return
		Local readStatement:TReadDataStatementSyntax = TReadDataStatementSyntax(node)
		If readStatement Then For Local child:TExpressionSyntax = EachIn readStatement.targets; IndexChild(node, child); Next; Return
		Local restoreStatement:TRestoreDataStatementSyntax = TRestoreDataStatementSyntax(node)
		If restoreStatement Then IndexChild(node, restoreStatement.label); Return
		Local callStatement:TCallStatementSyntax = TCallStatementSyntax(node)
		If callStatement Then IndexChild(node, callStatement.expression); For Local child:TExpressionSyntax = EachIn callStatement.argumentExpressions; IndexChild(node, child); Next; Return
		Local assignment:TAssignmentStatementSyntax = TAssignmentStatementSyntax(node)
		If assignment Then IndexChild(node, assignment.left); IndexChild(node, assignment.right); Return
		Local variables:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
		If variables Then For Local child:TVariableDeclaratorSyntax = EachIn variables.declarators; IndexChild(node, child); Next; Return
		Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(node)
		If declarator Then IndexChild(node, declarator.declaredType); IndexChild(node, declarator.callableType); IndexChild(node, declarator.staticArrayBound); For Local child:TExpressionSyntax = EachIn declarator.arrayDimensions; IndexChild(node, child); Next; IndexChild(node, declarator.initializer); Return
		Local staticBound:TStaticArrayBoundSyntax = TStaticArrayBoundSyntax(node)
		If staticBound Then IndexChild(node, staticBound.lengthExpression); Return
		Local callable:TCallableTypeSyntax = TCallableTypeSyntax(node)
		If callable Then IndexChild(node, callable.returnType); For Local child:TParameterSyntax = EachIn callable.parameters; IndexChild(node, child); Next; For Local suffix:TTypeSuffixSyntax = EachIn callable.suffixes; IndexChild(node, suffix); Next; Return
		Local typeReference:TTypeReferenceSyntax = TTypeReferenceSyntax(node)
		If typeReference Then IndexChild(node, typeReference.closureSignature); For Local child:TTypeReferenceSyntax = EachIn typeReference.genericArguments; IndexChild(node, child); Next; For Local child:TTypeSuffixSyntax = EachIn typeReference.suffixes; IndexChild(node, child); Next; Return
		Local signature:TRoutineSignatureSyntax = TRoutineSignatureSyntax(node)
		If signature Then
			For Local child:TGenericParameterSyntax = EachIn signature.genericParameters; IndexChild(node, child); Next
			IndexChild(node, signature.returnType)
			IndexChild(node, signature.callableReturnType)
			For Local child:TParameterSyntax = EachIn signature.parameters; IndexChild(node, child); Next
			For Local child:TGenericConstraintSyntax = EachIn signature.constraints; IndexChild(node, child); Next
			Return
		End If
		Local parameter:TParameterSyntax = TParameterSyntax(node)
		If parameter Then IndexChild(node, parameter.staticArrayBound); IndexChild(node, parameter.declaredType); IndexChild(node, parameter.callableType); IndexChild(node, parameter.defaultValue); Return

		Local ifStatement:TIfStatementSyntax = TIfStatementSyntax(node)
		If ifStatement Then IndexChild(node, ifStatement.condition); IndexChild(node, ifStatement.thenBlock); For Local child:TElseIfClauseSyntax = EachIn ifStatement.elseIfClauses; IndexChild(node, child); Next; IndexChild(node, ifStatement.elseClause); IndexChild(node, ifStatement.terminator); Return
		Local elseIfClause:TElseIfClauseSyntax = TElseIfClauseSyntax(node)
		If elseIfClause Then IndexChild(node, elseIfClause.condition); IndexChild(node, elseIfClause.block); Return
		Local elseClause:TElseClauseSyntax = TElseClauseSyntax(node)
		If elseClause Then IndexChild(node, elseClause.block); Return
		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(node)
		If whileStatement Then IndexChild(node, whileStatement.label); IndexChild(node, whileStatement.condition); IndexChild(node, whileStatement.body); IndexChild(node, whileStatement.terminator); Return
		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(node)
		If repeatStatement Then IndexChild(node, repeatStatement.label); IndexChild(node, repeatStatement.body); IndexChild(node, repeatStatement.condition); Return
		Local forStatement:TForStatementSyntax = TForStatementSyntax(node)
		If forStatement Then IndexChild(node, forStatement.label); IndexChild(node, forStatement.header); IndexChild(node, forStatement.body); IndexChild(node, forStatement.terminator); Return
		Local forHeader:TForHeaderSyntax = TForHeaderSyntax(node)
		If forHeader Then For Local child:TVariableDeclaratorSyntax = EachIn forHeader.declarations; IndexChild(node, child); Next; IndexChild(node, forHeader.target); IndexChild(node, forHeader.initialValue); IndexChild(node, forHeader.collection); IndexChild(node, forHeader.limit); IndexChild(node, forHeader.stepExpression); Return
		Local selectStatement:TSelectStatementSyntax = TSelectStatementSyntax(node)
		If selectStatement Then IndexChild(node, selectStatement.expression); For Local child:TCaseClauseSyntax = EachIn selectStatement.cases; IndexChild(node, child); Next; For Local defaultChild:TDefaultClauseSyntax = EachIn selectStatement.defaultClauses; IndexChild(node, defaultChild); Next; IndexChild(node, selectStatement.terminator); Return
		Local caseClause:TCaseClauseSyntax = TCaseClauseSyntax(node)
		If caseClause Then IndexChild(node, caseClause.conditionalExpression); For Local child:TExpressionSyntax = EachIn caseClause.values; IndexChild(node, child); Next; IndexChild(node, caseClause.body); Return
		Local defaultClause:TDefaultClauseSyntax = TDefaultClauseSyntax(node)
		If defaultClause Then IndexChild(node, defaultClause.conditionalExpression); IndexChild(node, defaultClause.body); Return
		Local tryStatement:TTryStatementSyntax = TTryStatementSyntax(node)
		If tryStatement Then IndexChild(node, tryStatement.body); For Local child:TCatchClauseSyntax = EachIn tryStatement.catches; IndexChild(node, child); Next; IndexChild(node, tryStatement.finallyClause); IndexChild(node, tryStatement.terminator); Return
		Local catchClause:TCatchClauseSyntax = TCatchClauseSyntax(node)
		If catchClause Then IndexChild(node, catchClause.declaredType); IndexChild(node, catchClause.body); Return
		Local finallyClause:TFinallyClauseSyntax = TFinallyClauseSyntax(node)
		If finallyClause Then IndexChild(node, finallyClause.body); Return
		Local usingStatement:TUsingStatementSyntax = TUsingStatementSyntax(node)
		If usingStatement Then For Local child:TVariableDeclarationStatementSyntax = EachIn usingStatement.resources; IndexChild(node, child); Next; IndexChild(node, usingStatement.body); IndexChild(node, usingStatement.terminator); Return
		Local region:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
		If region Then For Local child:TConditionalBranchSyntax = EachIn region.branches; IndexChild(node, child); Next; IndexChild(node, region.sharedRoutineBody); IndexChild(node, region.sharedRoutineTerminator); Return
		Local branch:TConditionalBranchSyntax = TConditionalBranchSyntax(node)
		If branch Then IndexChild(node, branch.condition); IndexChild(node, branch.body); Return
		Local conditionalNot:TConditionalNotSyntax = TConditionalNotSyntax(node)
		If conditionalNot Then IndexChild(node, conditionalNot.operand); Return
		Local conditionalBinary:TConditionalBinarySyntax = TConditionalBinarySyntax(node)
		If conditionalBinary Then IndexChild(node, conditionalBinary.left); IndexChild(node, conditionalBinary.right); Return
		Local conditionalParentheses:TConditionalParenthesizedSyntax = TConditionalParenthesizedSyntax(node)
		If conditionalParentheses Then IndexChild(node, conditionalParentheses.expression); Return

		Local functionLiteral:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(node)
		If functionLiteral Then
			IndexChild(node, functionLiteral.returnType)
			For Local child:TParameterSyntax = EachIn functionLiteral.parameters; IndexChild(node, child); Next
			IndexChild(node, functionLiteral.body)
			IndexChild(node, functionLiteral.terminator)
			Return
		End If
		Local parentheses:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(node)
		If parentheses Then IndexChild(node, parentheses.expression); Return
		Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(node)
		If unary Then IndexChild(node, unary.operand); Return
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(node)
		If binary Then IndexChild(node, binary.left); IndexChild(node, binary.right); Return
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(node)
		If name Then For Local child:TTypeReferenceSyntax = EachIn name.typeArguments; IndexChild(node, child); Next; IndexChild(node, name.qualifiedSuperType); Return
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(node)
		If member Then IndexChild(node, member.expression); For Local child:TTypeReferenceSyntax = EachIn member.typeArguments; IndexChild(node, child); Next; Return
		Local call:TCallExpressionSyntax = TCallExpressionSyntax(node)
		If call Then IndexChild(node, call.callee); For Local child:TTypeReferenceSyntax = EachIn call.typeArguments; IndexChild(node, child); Next; For Local child:TExpressionSyntax = EachIn call.arguments; IndexChild(node, child); Next; Return
		Local indexed:TIndexExpressionSyntax = TIndexExpressionSyntax(node)
		If indexed Then IndexChild(node, indexed.expression); For Local child:TExpressionSyntax = EachIn indexed.indexes; IndexChild(node, child); Next; Return
		Local slice:TSliceExpressionSyntax = TSliceExpressionSyntax(node)
		If slice Then IndexChild(node, slice.expression); IndexChild(node, slice.lowerBound); IndexChild(node, slice.upperBound); Return
		Local range:TRangeExpressionSyntax = TRangeExpressionSyntax(node)
		If range Then IndexChild(node, range.lowerBound); IndexChild(node, range.upperBound); Return
		Local ascription:TTypeAscriptionExpressionSyntax = TTypeAscriptionExpressionSyntax(node)
		If ascription Then IndexChild(node, ascription.expression); IndexChild(node, ascription.targetType); Return
		Local created:TNewExpressionSyntax = TNewExpressionSyntax(node)
		If created Then IndexChild(node, created.createdType); For Local child:TExpressionSyntax = EachIn created.arguments; IndexChild(node, child); Next; For Local child:TExpressionSyntax = EachIn created.dimensions; IndexChild(node, child); Next; Return
		Local literal:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(node)
		If literal Then For Local child:TExpressionSyntax = EachIn literal.elements; IndexChild(node, child); Next; Return
		Local cast:TCastExpressionSyntax = TCastExpressionSyntax(node)
		If cast Then IndexChild(node, cast.targetType); IndexChild(node, cast.expression)
	End Method

	Method IndexChild(parent:TSyntaxNode, child:TSyntaxNode)
		If child Then IndexNode(child, parent)
	End Method

	Function SpanContains:Int(span:TSourceSpan, offset:Int)
		If Not span Then Return False
		If span.length = 0 Then Return offset = span.start
		Return span.Contains(offset)
	End Function

	Function TokenContains:Int(token:TSyntaxToken, offset:Int)
		If Not token Or Not token.span Then Return False
		If token.span.length = 0 Then Return offset = token.span.start
		Return token.span.Contains(offset)
	End Function
End Type

Type TSyntaxLocation
	Field path:String
	Field offset:Int
	Field token:TSyntaxToken
	Field node:TSyntaxNode
	Field expression:TExpressionSyntax
	Field statement:TSyntaxNode
	Field declaration:TSyntaxNode
	Field parents:TSyntaxNode[]

	Function Locate:TSyntaxLocation(navigator:TSyntaxNavigator, offset:Int)
		If Not navigator Or Not navigator.tree Then Return Null
		Local result:TSyntaxLocation = New TSyntaxLocation
		result.path = navigator.tree.source.path
		result.offset = Max(0, Min(offset, navigator.tree.source.Length()))
		result.token = navigator.TokenAt(result.offset)
		result.node = navigator.NodeAt(result.offset)
		result.parents = navigator.Ancestors(result.node)
		For Local candidate:TSyntaxNode = EachIn result.parents
			If Not result.expression Then result.expression = TExpressionSyntax(candidate)
			If Not result.declaration And IsDeclaration(candidate) Then result.declaration = candidate
			If Not result.statement And IsStatement(candidate) Then result.statement = candidate
		Next
		Return result
	End Function

	Function IsDeclaration:Int(node:TSyntaxNode)
		Return TTypeDeclarationSyntax(node) <> Null Or TRoutineDeclarationSyntax(node) <> Null Or TEnumDeclarationSyntax(node) <> Null Or TEnumValueSyntax(node) <> Null Or TVariableDeclaratorSyntax(node) <> Null Or TParameterSyntax(node) <> Null Or TGenericParameterSyntax(node) <> Null Or TCatchClauseSyntax(node) <> Null
	End Function

	Function IsStatement:Int(node:TSyntaxNode)
		If Not node Or TExpressionSyntax(node) Or TBlockSyntax(node) Then Return False
		Return node.kind >= SYNTAX_END_STATEMENT And node.kind <= SYNTAX_VARIABLE_DECLARATOR Or (node.kind >= SYNTAX_IF_STATEMENT And node.kind <= SYNTAX_RESTOREDATA_STATEMENT)
	End Function
End Type

Type TSemanticLocation
	Field syntax:TSyntaxLocation
	Field scope:TScope
	Field symbol:TSymbol
	Field semanticType:TSemanticType
	Field resolvedCall:TResolvedCall
	Field constantValue:TConstantValue

	Function Query:TSemanticLocation(model:TSemanticModel, navigator:TSyntaxNavigator, offset:Int)
		If Not model Or Not navigator Then Return Null
		Local result:TSemanticLocation = New TSemanticLocation
		result.syntax = TSyntaxLocation.Locate(navigator, offset)
		If Not result.syntax Then Return result
		Local targetsType:Int
		For Local candidate:TSyntaxNode = EachIn result.syntax.parents
			Local typeReference:TTypeReferenceSyntax = TTypeReferenceSyntax(candidate)
			If typeReference And typeReference.span.Contains(offset) And Not targetsType Then
				targetsType = True
				Local referencedType:TSemanticType = model.TypeOf(typeReference)
				If referencedType Then
					result.semanticType = referencedType
					' The semantic type retains array/pointer wrappers for consumers that
					' need the complete declaration type. When the cursor is on its written
					' name, navigation and hover should target the underlying named element.
					If TypeNameContains(typeReference, offset) Then result.symbol = ReferencedTypeSymbol(referencedType)
				End If
			End If
			If Not result.scope Then result.scope = model.ScopeFor(candidate)
			If Not targetsType And Not result.symbol And Not IndexArgumentContains(candidate, offset) Then result.symbol = model.ReferencedSymbol(candidate)
			If Not targetsType And Not result.symbol Then
				Local declared:TSymbol = model.DeclaredSymbol(candidate)
				If DeclarationNameContains(declared, offset) Then result.symbol = declared
			End If
			Local candidateCall:TResolvedCall = model.ResolvedCall(candidate)
			If Not result.resolvedCall Then result.resolvedCall = candidateCall
			Local creation:TNewExpressionSyntax = TNewExpressionSyntax(candidate)
			If creation And candidateCall And creation.createdType And creation.createdType.span.Contains(offset) Then result.symbol = candidateCall.routine
			If Not targetsType And Not result.symbol And candidateCall And CallTargetContains(candidate, offset) Then result.symbol = candidateCall.routine
			Local expression:TExpressionSyntax = TExpressionSyntax(candidate)
			If expression Then
				If Not result.semanticType Then result.semanticType = model.ExpressionType(expression)
				If Not result.constantValue Then result.constantValue = model.ConstantValue(expression)
			End If
			If typeReference And Not result.semanticType Then result.semanticType = model.TypeOf(typeReference)
		Next
		If Not result.symbol Then
			Local named:TNamedSemanticType = TNamedSemanticType(result.semanticType)
			If named Then result.symbol = named.symbol
			Local parameter:TTypeParameterSemanticType = TTypeParameterSemanticType(result.semanticType)
			If parameter Then result.symbol = parameter.symbol
			Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(result.semanticType)
			If builtin Then result.symbol = builtin.runtimeSymbol
		End If
		If result.symbol And Not result.semanticType Then result.semanticType = result.symbol.declaredType
		If result.symbol And Not result.constantValue Then result.constantValue = model.SymbolConstantValue(result.symbol)
		Return result
	End Function

	Function TypeNameContains:Int(reference:TTypeReferenceSyntax, offset:Int)
		If Not reference Or Not reference.nameTokens.length Then Return False
		Local first:TSourceSpan = reference.nameTokens[0].span
		Local last:TSourceSpan = reference.nameTokens[reference.nameTokens.length - 1].span
		Return offset >= first.start And offset < last.EndOffset()
	End Function

	Function ReferencedTypeSymbol:TSymbol(value:TSemanticType)
		Local current:TSemanticType = value
		For Local depth:Int = 0 Until 64
			Local named:TNamedSemanticType = TNamedSemanticType(current)
			If named Then Return named.symbol
			Local parameter:TTypeParameterSemanticType = TTypeParameterSemanticType(current)
			If parameter Then Return parameter.symbol
			Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(current)
			If builtin Then Return builtin.runtimeSymbol
			Local arrayType:TArraySemanticType = TArraySemanticType(current)
			If arrayType Then current = arrayType.elementType; Continue
			Local pointerType:TPointerSemanticType = TPointerSemanticType(current)
			If pointerType Then current = pointerType.elementType; Continue
			Local fixedArray:TStaticArraySemanticType = TStaticArraySemanticType(current)
			If fixedArray Then current = fixedArray.elementType; Continue
			Exit
		Next
		Return Null
	End Function

	Function DeclarationNameContains:Int(symbol:TSymbol, offset:Int)
		If Not symbol Or Not symbol.nameToken Or Not symbol.nameToken.span Then Return False
		If symbol.nameToken.span.length = 0 Then Return offset = symbol.nameToken.span.start
		Return symbol.nameToken.span.Contains(offset)
	End Function

	Function IndexArgumentContains:Int(node:TSyntaxNode, offset:Int)
		Local indexed:TIndexExpressionSyntax = TIndexExpressionSyntax(node)
		If Not indexed Then Return False
		For Local argument:TExpressionSyntax = EachIn indexed.indexes
			If argument And argument.span And argument.span.Contains(offset) Then Return True
		Next
		Return False
	End Function

	Function CallTargetContains:Int(node:TSyntaxNode, offset:Int)
		Local statement:TCallStatementSyntax = TCallStatementSyntax(node)
		If statement And statement.calleeTokens.length Then
			Local first:TSourceSpan = statement.calleeTokens[0].span
			Local last:TSourceSpan = statement.calleeTokens[statement.calleeTokens.length - 1].span
			Return offset >= first.start And offset < last.EndOffset()
		End If
		Local expression:TCallExpressionSyntax = TCallExpressionSyntax(node)
		If expression And expression.callee And expression.callee.span Then Return expression.callee.span.Contains(offset)
		Local creation:TNewExpressionSyntax = TNewExpressionSyntax(node)
		If creation And creation.createdType And creation.createdType.span Then Return creation.createdType.span.Contains(offset)
		Return False
	End Function
End Type
