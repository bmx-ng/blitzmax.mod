' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map

Import "conditional_evaluator.bmx"
Import "conversion_classification.bmx"
Import "generic_routine_inference.bmx"
Import "inheritance_validation.bmx"
Import "symbol_accessibility.bmx"

Type TApplicableRoutine
	Field routine:TSymbol
	Field binding:TGenericRoutineBinding
	Field rank:Int
	Field parameterTypes:TSemanticType[] = New TSemanticType[0]
	Field returnType:TSemanticType
End Type

Type TExpressionBinder
	Field model:TSemanticModel
	Field diagnostics:TList = New TList
	Field typeResolver:TTypeResolver
	Field conversions:TConversionClassifier
	Field inheritanceValidator:TInheritanceValidator
	Field currentDocument:TSourceDocumentModel
	Field inaccessibleMemberReports:TMap = New TMap
	Field initializerExcludedSymbol:TSymbol
	Field activeFunctionLiteralScope:TScope
	Field activeFunctionLiteralManaged:Int
	Field activeFunctionLiteralCaptures:TSymbol[] = New TSymbol[0]
	Field activeFunctionLiteralCapturesSelf:Int
	Field activeFunctionLiteralCapturedSelfType:TSemanticType
	Field captureReports:TMap = New TMap
	Field indexSetterTarget:TIndexExpressionSyntax
	Field genericTypeQualifierTypes:TMap = New TMap
	Field nextYieldFromLocal:Int
	Field nextDeconstructionLocal:Int
	Field eachInResolutions:TMap = New TMap

	Function Bind:TSemanticModel(model:TSemanticModel, typeResolutionOptions:TTypeResolutionOptions = Null)
		Local binder:TExpressionBinder = New TExpressionBinder
		binder.model = model
		binder.typeResolver = New TTypeResolver
		binder.typeResolver.model = model
		binder.typeResolver.options = typeResolutionOptions
		If Not binder.typeResolver.options Then binder.typeResolver.options = New TTypeResolutionOptions
		binder.inheritanceValidator = New TInheritanceValidator
		binder.inheritanceValidator.model = model
		binder.conversions = TConversionClassifier.Create(model)
		If model.snapshot Then binder.currentDocument = model.snapshot.rootDocument
		binder.BindSequence(model.syntaxTree.root.members, model.globalScope)
		If model.snapshot Then binder.currentDocument = model.snapshot.rootDocument
		binder.BuildBoundTrees()
		model.diagnostics = MergeDiagnostics(model.diagnostics, DiagnosticsToArray(binder.diagnostics))
		model.diagnostics = MergeDiagnostics(model.diagnostics, DiagnosticsToArray(binder.typeResolver.diagnostics))
		Return model
	End Function

	Method BindSequence(nodes:TSyntaxNode[], scope:TScope)
		For Local index:Int = 0 Until nodes.length
			BindNode(nodes[index], scope)
			ValidateConstructorDelegation(nodes[index], scope, index)
		Next
	End Method

	Method ValidateConstructorDelegation(node:TSyntaxNode, scope:TScope, statementIndex:Int)
		Local callStatement:TCallStatementSyntax = TCallStatementSyntax(node)
		If Not callStatement Then Return
		Local call:TCallExpressionSyntax = TCallExpressionSyntax(callStatement.expression)
		If Not call Then Return
		Local resolved:TResolvedCall = model.ResolvedCall(call)
		If Not resolved Then resolved = model.ResolvedCall(callStatement)
		If Not resolved Or Not resolved.routine Or resolved.routine.name.ToLower() <> "new" Then Return
		Local bareName:TNameExpressionSyntax = TNameExpressionSyntax(call.callee)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(call.callee)
		Local superName:TNameExpressionSyntax
		If member Then superName = TNameExpressionSyntax(member.expression)
		Local validForm:Int = bareName And bareName.nameToken.text.ToLower() = "new"
		If superName And superName.nameToken.text.ToLower() = "super" Then validForm = True
		If Not validForm Then
			AddDiagnostic("BMX3320", "A constructor can only be delegated with New(...) or Super.New(...).", call.span)
			Return
		End If
		Local enclosing:TSymbol = EnclosingRoutine(scope)
		If Not enclosing Or enclosing.name.ToLower() <> "new" Then
			AddDiagnostic("BMX3321", "Constructor delegation is only valid inside a New method.", call.span)
			Return
		End If
		If Not scope Or scope.kind <> SCOPE_ROUTINE Or statementIndex <> 0 Then
			AddDiagnostic("BMX3322", "Constructor delegation must be the first statement in a New method.", call.span)
			Return
		End If
		If resolved.routine = enclosing Then AddDiagnostic("BMX3323", "A constructor cannot delegate directly to itself.", call.span)
	End Method

	Method BuildBoundTrees()
		model.boundGlobalBody = BuildBoundBlock(model.syntaxTree.root.members, Null, model.syntaxTree.root)
	End Method

	Method BuildBoundBlock:TBoundBlockStatement(nodes:TSyntaxNode[], routine:TSymbol, syntax:TSyntaxNode)
		Local statements:TList = New TList
		For Local node:TSyntaxNode = EachIn nodes
			Local includeSyntax:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
			If includeSyntax And currentDocument Then
				Local included:TSourceDocumentModel = IncludedDocument(currentDocument, includeSyntax)
				If included Then
					Local previous:TSourceDocumentModel = currentDocument
					currentDocument = included
					Local includedBlock:TBoundBlockStatement = BuildBoundBlock(included.tree.root.members, routine, included.tree.root)
					For Local includedStatement:TBoundStatement = EachIn includedBlock.statements
						statements.AddLast(includedStatement)
					Next
					currentDocument = previous
					model.boundStatementMap.Insert(includeSyntax, includedBlock)
				End If
				Continue
			End If
			Local statement:TBoundStatement = BuildBoundStatement(node, routine)
			If statement Then statements.AddLast(statement)
		Next
		Local bound:TBoundBlockStatement = New TBoundBlockStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_BLOCK, syntax)
		bound.statements = BoundStatementsToArray(statements)
		If syntax Then model.boundStatementMap.Insert(syntax, bound)
		Return bound
	End Method

	Method BuildBoundStatement:TBoundStatement(node:TSyntaxNode, routine:TSymbol)
		If Not node Then Return Null
		If TSourceModeSyntax(node) Or TImportDirectiveSyntax(node) Or TIncludeDirectiveSyntax(node) Or TVisibilitySectionSyntax(node) Then Return Null
		Local rawDirective:TRawStatementSyntax = TRawStatementSyntax(node)
		If rawDirective And rawDirective.tokens.length And rawDirective.tokens[0].text.ToLower() = "incbin" Then Return Null
		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration Then
			BuildBoundBlock(typeDeclaration.body.statements, Null, typeDeclaration.body)
			Return Null
		End If
		Local routineDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routineDeclaration Then
			Local routineSymbol:TSymbol = model.DeclaredSymbol(routineDeclaration)
			Local body:TBoundBlockStatement = BuildBoundBlock(routineDeclaration.body.statements, routineSymbol, routineDeclaration.body)
			If routineSymbol Then model.boundRoutineBodyMap.Insert(routineSymbol, body)
			Return Null
		End If
		Local externBlock:TExternBlockSyntax = TExternBlockSyntax(node)
		If externBlock Then
			BuildBoundBlock(externBlock.body.statements, routine, externBlock.body)
			Return Null
		End If
		If TEnumDeclarationSyntax(node) Then Return Null

		Local variables:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
		If variables Then Return BuildBoundVariables(variables)

		Local assignment:TAssignmentStatementSyntax = TAssignmentStatementSyntax(node)
		If assignment Then
			Local bound:TBoundAssignmentStatement = New TBoundAssignmentStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_ASSIGNMENT, assignment)
			bound.target = model.BoundExpression(assignment.left)
			bound.value = model.BoundExpression(assignment.right)
			bound.operatorText = assignment.operatorToken.text
			bound.resolvedCall = model.ResolvedCall(assignment)
			bound.indexAccess = model.ResolvedIndex(assignment)
			If Not bound.indexAccess Then bound.indexAccess = model.ResolvedIndex(assignment.left)
			If bound.indexAccess And bound.indexAccess.accessKind = INDEX_ACCESS_OPERATOR Then
				Local indexedTargetSyntax:TIndexExpressionSyntax = TIndexExpressionSyntax(assignment.left)
				If indexedTargetSyntax Then
					Local indexedTarget:TBoundIndexExpression = TBoundIndexExpression(bound.target)
					If Not indexedTarget Then
						indexedTarget = New TBoundIndexExpression
						InitializeBound(indexedTarget, BOUND_EXPRESSION_INDEX, indexedTargetSyntax, bound.indexAccess.resultType)
						indexedTarget.receiver = model.BoundExpression(indexedTargetSyntax.expression)
						indexedTarget.indexes = BoundExpressions(indexedTargetSyntax.indexes)
						bound.target = indexedTarget
					End If
					indexedTarget.access = bound.indexAccess
				End If
			End If
			Local required:TSemanticType
			If bound.resolvedCall And bound.resolvedCall.parameterTypes.length Then
				required = bound.resolvedCall.parameterTypes[bound.resolvedCall.parameterTypes.length - 1]
			Else If assignment.operatorToken.text = "=" Then
				required = model.ExpressionType(assignment.left)
			End If
			If required Then bound.value = ApplyImplicitConversion(bound.value, assignment.right, required, bound.resolvedCall = Null)
			Return StoreBoundStatement(assignment, bound)
		End If

		Local callStatement:TCallStatementSyntax = TCallStatementSyntax(node)
		If callStatement Then
			Local bound:TBoundExpressionStatement = New TBoundExpressionStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_EXPRESSION, callStatement)
			bound.expression = model.BoundExpression(callStatement.expression)
			If Not callStatement.hasParentheses Then bound.expression = BuildStatementCall(callStatement)
			Return StoreBoundStatement(callStatement, bound)
		End If

		Local returnStatement:TReturnStatementSyntax = TReturnStatementSyntax(node)
		If returnStatement Then
			Local bound:TBoundReturnStatement = New TBoundReturnStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_RETURN, returnStatement)
			bound.expression = model.BoundExpression(returnStatement.expression)
			If returnStatement.expression And (Not routine Or Not routine.isIteratorRoutine) Then
				If routine And routine.declaredType Then
					bound.expression = ApplyImplicitConversion(bound.expression, returnStatement.expression, routine.declaredType, True)
				Else If Not routine Then
					bound.expression = ApplyImplicitConversion(bound.expression, returnStatement.expression, model.BuiltinType("Int"), True)
				End If
			End If
			Return StoreBoundStatement(returnStatement, bound)
		End If

		Local yieldStatement:TYieldStatementSyntax = TYieldStatementSyntax(node)
		If yieldStatement Then
			If yieldStatement.fromToken Then Return BuildBoundYieldFrom(yieldStatement, routine)
			Local bound:TBoundYieldStatement = New TBoundYieldStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_YIELD, yieldStatement)
			bound.expression = model.BoundExpression(yieldStatement.expression)
			If yieldStatement.expression And routine And routine.iteratorElementType Then bound.expression = ApplyImplicitConversion(bound.expression, yieldStatement.expression, routine.iteratorElementType, True)
			Return StoreBoundStatement(yieldStatement, bound)
		End If

		Local throwStatement:TThrowStatementSyntax = TThrowStatementSyntax(node)
		If throwStatement Then
			Local bound:TBoundThrowStatement = New TBoundThrowStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_THROW, throwStatement)
			bound.expression = model.BoundExpression(throwStatement.expression)
			Return StoreBoundStatement(throwStatement, bound)
		End If

		Local assertStatement:TAssertStatementSyntax = TAssertStatementSyntax(node)
		If assertStatement Then
			Local bound:TBoundAssertStatement = New TBoundAssertStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_ASSERT, assertStatement)
			bound.condition = model.BoundExpression(assertStatement.condition)
			bound.message = model.BoundExpression(assertStatement.message)
			Return StoreBoundStatement(assertStatement, bound)
		End If

		Local releaseStatement:TReleaseStatementSyntax = TReleaseStatementSyntax(node)
		If releaseStatement Then
			Local bound:TBoundReleaseStatement = New TBoundReleaseStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_RELEASE, releaseStatement)
			bound.expression = model.BoundExpression(releaseStatement.expression)
			Return StoreBoundStatement(releaseStatement, bound)
		End If

		Local block:TBlockSyntax = TBlockSyntax(node)
		If block Then Return BuildBoundBlock(block.statements, routine, block)

		Local ifStatement:TIfStatementSyntax = TIfStatementSyntax(node)
		If ifStatement Then
			Local bound:TBoundIfStatement = New TBoundIfStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_IF, ifStatement)
			bound.condition = model.BoundExpression(ifStatement.condition)
			bound.thenBody = BuildBoundBlock(ifStatement.thenBlock.statements, routine, ifStatement.thenBlock)
			bound.elseIfClauses = New TBoundConditionalClause[ifStatement.elseIfClauses.length]
			For Local index:Int = 0 Until ifStatement.elseIfClauses.length
				Local syntax:TElseIfClauseSyntax = ifStatement.elseIfClauses[index]
				Local clause:TBoundConditionalClause = New TBoundConditionalClause
				clause.syntax = syntax
				clause.condition = model.BoundExpression(syntax.condition)
				clause.body = BuildBoundBlock(syntax.block.statements, routine, syntax.block)
				bound.elseIfClauses[index] = clause
			Next
			If ifStatement.elseClause Then bound.elseBody = BuildBoundBlock(ifStatement.elseClause.block.statements, routine, ifStatement.elseClause.block)
			Return StoreBoundStatement(ifStatement, bound)
		End If

		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(node)
		If whileStatement Then
			Local bound:TBoundWhileStatement = New TBoundWhileStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_WHILE, whileStatement)
			bound.condition = model.BoundExpression(whileStatement.condition)
			bound.body = BuildBoundBlock(whileStatement.body.statements, routine, whileStatement.body)
			Return StoreBoundStatement(whileStatement, bound)
		End If

		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(node)
		If repeatStatement Then
			Local bound:TBoundRepeatStatement = New TBoundRepeatStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_REPEAT, repeatStatement)
			bound.body = BuildBoundBlock(repeatStatement.body.statements, routine, repeatStatement.body)
			bound.condition = model.BoundExpression(repeatStatement.condition)
			bound.isForever = repeatStatement.terminationToken And repeatStatement.terminationToken.text.ToLower() = "forever"
			Return StoreBoundStatement(repeatStatement, bound)
		End If

		Local forStatement:TForStatementSyntax = TForStatementSyntax(node)
		If forStatement Then
			Local bound:TBoundForStatement = New TBoundForStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_FOR, forStatement)
			If forStatement.header.declaration Then bound.loopVariable = model.DeclaredSymbol(forStatement.header.declaration)
			bound.target = model.BoundExpression(forStatement.header.target)
			bound.initialValue = model.BoundExpression(forStatement.header.initialValue)
			If bound.initialValue And bound.loopVariable And bound.loopVariable.declaredType Then bound.initialValue = ApplyImplicitConversion(bound.initialValue, forStatement.header.initialValue, bound.loopVariable.declaredType, True)
			bound.collection = model.BoundExpression(forStatement.header.collection)
			bound.limit = model.BoundExpression(forStatement.header.limit)
			bound.stepExpression = model.BoundExpression(forStatement.header.stepExpression)
			bound.isEachIn = forStatement.header.eachInToken <> Null
			If bound.isEachIn Then
				bound.iteration = TResolvedEachIn(eachInResolutions.ValueForKey(forStatement))
				If Not bound.iteration Then bound.iteration = ResolveEachIn(bound.collection, model.ScopeFor(forStatement), forStatement, forStatement.header.collection)
			End If
			bound.body = BuildBoundBlock(forStatement.body.statements, routine, forStatement.body)
			If bound.iteration And forStatement.header.declarations.length > 1 Then BuildBoundDeconstruction(bound, forStatement)
			Return StoreBoundStatement(forStatement, bound)
		End If

		Local selectStatement:TSelectStatementSyntax = TSelectStatementSyntax(node)
		If selectStatement Then Return BuildBoundSelect(selectStatement, routine)
		Local tryStatement:TTryStatementSyntax = TTryStatementSyntax(node)
		If tryStatement Then Return BuildBoundTry(tryStatement, routine)
		Local usingStatement:TUsingStatementSyntax = TUsingStatementSyntax(node)
		If usingStatement Then Return BuildBoundUsing(usingStatement, routine)
		Local conditional:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
		If conditional Then Return BuildBoundConditional(conditional, routine)

		Local dataDefinition:TDefDataStatementSyntax = TDefDataStatementSyntax(node)
		If dataDefinition Then Return BuildBoundData(dataDefinition, dataDefinition.values)
		Local dataRead:TReadDataStatementSyntax = TReadDataStatementSyntax(node)
		If dataRead Then Return BuildBoundData(dataRead, dataRead.targets)

		If TEndStatementSyntax(node) Or TExitStatementSyntax(node) Or TContinueStatementSyntax(node) Or TRestoreDataStatementSyntax(node) Then
			Local bound:TBoundFlowStatement = New TBoundFlowStatement
			InitializeBoundStatement(bound, BOUND_STATEMENT_FLOW, node)
			Return StoreBoundStatement(node, bound)
		End If

		Local errorStatement:TBoundErrorStatement = New TBoundErrorStatement
		InitializeBoundStatement(errorStatement, BOUND_STATEMENT_ERROR, node)
		Return StoreBoundStatement(node, errorStatement)
	End Method

	Method BuildBoundYieldFrom:TBoundStatement(syntax:TYieldStatementSyntax, routine:TSymbol)
		Local collection:TBoundExpression = model.BoundExpression(syntax.expression)
		Local iteration:TResolvedEachIn = ResolveEachIn(collection, model.ScopeFor(syntax), syntax, syntax.expression)
		If Not routine Or Not routine.iteratorElementType Or Not iteration Or Not iteration.elementType Then
			Local failed:TBoundYieldStatement = New TBoundYieldStatement
			InitializeBoundStatement(failed, BOUND_STATEMENT_YIELD, syntax)
			failed.expression = collection
			Return StoreBoundStatement(syntax, failed)
		End If

		Local loopVariable:TSymbol = New TSymbol
		loopVariable.kind = SYMBOL_LOCAL
		loopVariable.name = "$yieldFrom" + nextYieldFromLocal
		loopVariable.normalizedName = loopVariable.name.ToLower()
		loopVariable.declaration = syntax
		loopVariable.containingScope = model.ScopeFor(syntax)
		loopVariable.declaredType = routine.iteratorElementType
		nextYieldFromLocal :+ 1

		Local loopValue:TBoundSymbolExpression = New TBoundSymbolExpression
		loopValue.boundKind = BOUND_EXPRESSION_SYMBOL
		loopValue.syntax = syntax.expression
		loopValue.semanticType = routine.iteratorElementType
		loopValue.isSynthetic = True
		loopValue.symbol = loopVariable

		Local yielded:TBoundYieldStatement = New TBoundYieldStatement
		InitializeBoundStatement(yielded, BOUND_STATEMENT_YIELD, syntax)
		yielded.expression = loopValue

		Local body:TBoundBlockStatement = New TBoundBlockStatement
		InitializeBoundStatement(body, BOUND_STATEMENT_BLOCK, syntax)
		body.statements = [yielded]

		Local bound:TBoundForStatement = New TBoundForStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_FOR, syntax)
		bound.loopVariable = loopVariable
		bound.collection = collection
		bound.isEachIn = True
		bound.iteration = iteration
		bound.body = body
		Return StoreBoundStatement(syntax, bound)
	End Method

	Method ResolveEachIn:TResolvedEachIn(collection:TBoundExpression, scope:TScope, syntax:TSyntaxNode, collectionSyntax:TExpressionSyntax)
		If Not collection Or Not collection.semanticType Then Return Null
		Local operationName:String = "EachIn"
		If TYieldStatementSyntax(syntax) Then operationName = "Yield From"
		Local result:TResolvedEachIn = New TResolvedEachIn
		result.collectionType = collection.semanticType
		Local arrayType:TArraySemanticType = TArraySemanticType(collection.semanticType)
		If arrayType Then
			result.protocolKind = EACH_IN_PROTOCOL_ARRAY
			result.elementType = arrayType.elementType
			Return result
		End If
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(collection.semanticType)
		If builtin And builtin.name.ToLower() = "string" Then
			result.protocolKind = EACH_IN_PROTOCOL_STRING
			result.elementType = model.BuiltinType("Int")
			Return result
		End If
		Local fixedArray:TStaticArraySemanticType = TStaticArraySemanticType(collection.semanticType)
		If fixedArray Then
			result.protocolKind = EACH_IN_PROTOCOL_STATIC_ARRAY
			result.elementType = fixedArray.elementType
			Return result
		End If
		If TErrorSemanticType(collection.semanticType) Then Return Null
		Local iterableType:TNamedSemanticType = FindProtocolInterface(collection.semanticType, "iiterable")
		If iterableType Then
			result.protocolKind = EACH_IN_PROTOCOL_ITERABLE
			result.iteratorFactory = ResolveEachInMember(collection.semanticType, "GetIterator", scope)
			If result.iteratorFactory Then result.iteratorType = result.iteratorFactory.returnType
		Else
			Local iteratorType:TNamedSemanticType = FindProtocolInterface(collection.semanticType, "iiterator")
			If iteratorType Then
				result.protocolKind = EACH_IN_PROTOCOL_ITERATOR
				result.iteratorType = collection.semanticType
			Else
				result.iteratorFactory = ResolveEachInMember(collection.semanticType, "ObjectEnumerator", scope)
				If result.iteratorFactory Then
					result.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR
					result.iteratorType = result.iteratorFactory.returnType
				End If
			End If
		End If
		If result.protocolKind = 0 Then
			Local diagnosticSpan:TSourceSpan
			If collectionSyntax Then diagnosticSpan = collectionSyntax.span Else If syntax Then diagnosticSpan = syntax.span
			AddDiagnostic("BMX3330", operationName + " requires an Array, String, StaticArray, IIterable, IIterator, or suitable ObjectEnumerator method.", diagnosticSpan)
			Return Null
		End If
		If Not result.iteratorType Then
			Local diagnosticSpan:TSourceSpan
			If collectionSyntax Then diagnosticSpan = collectionSyntax.span Else If syntax Then diagnosticSpan = syntax.span
			AddDiagnostic("BMX3331", operationName + " iterator factory does not return a usable iterator type.", diagnosticSpan)
			Return Null
		End If
		If result.protocolKind = EACH_IN_PROTOCOL_ITERABLE Or result.protocolKind = EACH_IN_PROTOCOL_ITERATOR Then
			result.advance = ResolveEachInMember(result.iteratorType, "MoveNext", scope)
			result.current = ResolveEachInMember(result.iteratorType, "Current", scope)
		Else
			result.advance = ResolveEachInMember(result.iteratorType, "HasNext", scope)
			result.current = ResolveEachInMember(result.iteratorType, "NextObject", scope)
		End If
		If Not result.advance Or Not result.current Then
			Local diagnosticSpan:TSourceSpan
			If collectionSyntax Then diagnosticSpan = collectionSyntax.span Else If syntax Then diagnosticSpan = syntax.span
			AddDiagnostic("BMX3331", operationName + " iterator does not provide the required advance and current-value methods.", diagnosticSpan)
			Return Null
		End If
		If Not TConversionClassifier.IsIntegral(result.advance.returnType) Or IsBuiltin(result.current.returnType, "void") Then
			Local diagnosticSpan:TSourceSpan
			If collectionSyntax Then diagnosticSpan = collectionSyntax.span Else If syntax Then diagnosticSpan = syntax.span
			AddDiagnostic("BMX3331", operationName + " iterator advance must return an integral value and its current-value method must return a value.", diagnosticSpan)
			Return Null
		End If
		result.elementType = result.current.returnType
		Return result
	End Method

	Method ResolveEachInMember:TResolvedCall(receiver:TSemanticType, name:String, scope:TScope, argumentCount:Int = 0)
		Local candidates:TSymbol[] = AccessibleSymbols(RoutineMemberSymbols(receiver, name), scope)
		Local selected:TSymbol
		Local selectedArity:Int = 2147483647
		Local selectedCount:Int
		For Local candidate:TSymbol = EachIn candidates
			If Not AritySatisfied(candidate, argumentCount) Then Continue
			If candidate.parameterTypes.length < selectedArity Then
				selected = candidate
				selectedArity = candidate.parameterTypes.length
				selectedCount = 1
			Else If candidate.parameterTypes.length = selectedArity Then
				selectedCount :+ 1
			End If
		Next
		If Not selected Or selectedCount <> 1 Then Return Null
		Local substitutions:TMap = TypeSubstitutions(receiver)
		Local declaringReceiver:TSemanticType = MemberDeclaringType(receiver, selected)
		If declaringReceiver Then substitutions = TypeSubstitutions(declaringReceiver)
		Local result:TResolvedCall = New TResolvedCall
		result.routine = selected
		result.parameterTypes = SubstituteTypes(selected.parameterTypes, substitutions)
		result.returnType = TGenericRoutineInference.Substitute(selected.declaredType, substitutions)
		result.omittedArguments = New Int[selected.parameterTypes.length]
		For Local index:Int = 0 Until result.omittedArguments.length
			result.omittedArguments[index] = True
		Next
		Return result
	End Method

	Method ResolveEachInDeconstruction:Int(iteration:TResolvedEachIn, bindingCount:Int, scope:TScope, syntax:TForStatementSyntax)
		If Not iteration Or Not iteration.elementType Then Return False
		If bindingCount <> 2 Then
			AddDiagnostic("BMX3335", "EachIn deconstruction currently requires exactly two loop bindings for BRL.Blitz.IDeconstruct2<A, B>.", syntax.header.span)
			Return False
		End If
		Local contract:TNamedSemanticType = FindProtocolInterface(iteration.elementType, "ideconstruct2", "brl.blitz")
		If Not contract Or contract.typeArguments.length <> 2 Then
			AddDiagnostic("BMX3336", "EachIn element type '" + iteration.elementType.DisplayName() + "' must implement BRL.Blitz.IDeconstruct2<A, B> for two loop bindings.", syntax.header.span)
			Return False
		End If
		Local resolved:TResolvedCall = ResolveEachInMember(contract, "Deconstruct", scope, 2)
		Local valid:Int = resolved And resolved.routine And resolved.routine.parameters.length = 2 And IsBuiltin(resolved.returnType, "void")
		If valid Then
			For Local parameter:TSemanticParameter = EachIn resolved.routine.parameters
				If Not parameter Or parameter.passingMode <> PARAMETER_PASS_VAR Then valid = False; Exit
			Next
		End If
		If Not valid Then
			AddDiagnostic("BMX3337", "BRL.Blitz.IDeconstruct2<A, B> must provide Method Deconstruct(first:A Var, second:B Var).", syntax.header.span)
			Return False
		End If
		resolved.omittedArguments = New Int[2]
		iteration.deconstructionType = contract
		iteration.componentTypes = contract.typeArguments
		iteration.deconstruct = resolved
		Return True
	End Method

	Method BindEachInDeconstruction(iteration:TResolvedEachIn, header:TForHeaderSyntax, scope:TScope, syntax:TForStatementSyntax)
		If Not ResolveEachInDeconstruction(iteration, header.declarations.length, scope, syntax) Then Return
		For Local index:Int = 0 Until header.declarations.length
			Local declarator:TVariableDeclaratorSyntax = header.declarations[index]
			Local symbol:TSymbol = model.DeclaredSymbol(declarator)
			If Not symbol Then Continue
			Local componentType:TSemanticType = iteration.componentTypes[index]
			If symbol.isTypeInferred Then
				symbol.declaredType = componentType
			Else If symbol.declaredType And Not TGenericRoutineInference.SameType(symbol.declaredType, componentType) Then
				AddDiagnostic("BMX3338", "EachIn binding '" + symbol.name + "' has type '" + symbol.declaredType.DisplayName() + "', but IDeconstruct2 component " + (index + 1) + " has type '" + componentType.DisplayName() + "'.", declarator.span)
			End If
		Next
	End Method

	Method BindEachInTarget(iteration:TResolvedEachIn, header:TForHeaderSyntax)
		If Not iteration Or Not iteration.elementType Or Not header Then Return
		Local required:TSemanticType
		Local span:TSourceSpan = header.span
		Local name:String = "target"
		If header.declarations.length = 1 Then
			Local declarator:TVariableDeclaratorSyntax = header.declarations[0]
			Local symbol:TSymbol = model.DeclaredSymbol(declarator)
			If symbol Then
				required = symbol.declaredType
				name = "loop variable '" + symbol.name + "'"
			End If
			span = declarator.span
		Else If header.target Then
			required = model.ExpressionType(header.target)
			span = header.target.span
		End If
		If Not required Then Return
		If conversions.ClassifyExplicit(iteration.elementType, required).Exists() Then Return
		If IsLegacyEachInObjectConversion(iteration.elementType, required) Then Return
		AddDiagnostic("BMX3339", "EachIn element type '" + iteration.elementType.DisplayName() + "' cannot be converted to " + name + " of type '" + required.DisplayName() + "'.", span)
	End Method

	Function IsLegacyEachInObjectConversion:Int(actual:TSemanticType, required:TSemanticType)
		Local actualObject:Int
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(actual)
		If builtin And builtin.name.ToLower() = "object" Then actualObject = True
		Local named:TNamedSemanticType = TNamedSemanticType(actual)
		If named And named.symbol And (named.symbol.kind = SYMBOL_TYPE Or named.symbol.kind = SYMBOL_INTERFACE) Then actualObject = True
		If Not actualObject Then Return False
		If TConversionClassifier.IsString(required) Or TConversionClassifier.NumericRankOf(required) >= 0 Then Return True
		' A legacy Object result is dynamically filtered to any managed Type or
		' Interface target. More-specific source Types still require a real
		' upcast/downcast/interface relationship above.
		If builtin Then
			Local requiredNamed:TNamedSemanticType = TNamedSemanticType(required)
			If requiredNamed And requiredNamed.symbol Then Return requiredNamed.symbol.kind = SYMBOL_TYPE Or requiredNamed.symbol.kind = SYMBOL_INTERFACE
		End If
		Return False
	End Function

	Method BuildBoundDeconstruction(bound:TBoundForStatement, syntax:TForStatementSyntax)
		If Not bound Or Not bound.iteration Or Not bound.iteration.deconstruct Or Not bound.body Then Return
		Local loopScope:TScope = model.ScopeFor(syntax)
		Local element:TSymbol = New TSymbol
		element.kind = SYMBOL_LOCAL
		element.name = "$deconstruct" + nextDeconstructionLocal
		element.normalizedName = element.name.ToLower()
		element.declaration = syntax.header
		element.containingScope = loopScope
		element.declaredType = bound.iteration.elementType
		nextDeconstructionLocal :+ 1
		bound.loopVariable = element
		bound.deconstructionVariables = New TSymbol[syntax.header.declarations.length]

		Local prefix:TBoundStatement[] = New TBoundStatement[0]
		Local arguments:TBoundExpression[] = New TBoundExpression[syntax.header.declarations.length]
		For Local index:Int = 0 Until syntax.header.declarations.length
			Local declarator:TVariableDeclaratorSyntax = syntax.header.declarations[index]
			Local symbol:TSymbol = model.DeclaredSymbol(declarator)
			bound.deconstructionVariables[index] = symbol
			Local variable:TBoundVariable = New TBoundVariable
			variable.symbol = symbol
			Local declaration:TBoundVariableDeclarationStatement = New TBoundVariableDeclarationStatement
			InitializeBoundStatement(declaration, BOUND_STATEMENT_VARIABLE_DECLARATION, declarator)
			declaration.variables = [variable]
			prefix :+ [declaration]
			model.boundStatementMap.Insert(declarator, declaration)

			Local argument:TBoundSymbolExpression = New TBoundSymbolExpression
			argument.boundKind = BOUND_EXPRESSION_SYMBOL
			argument.syntax = syntax.header.collection
			argument.semanticType = symbol.declaredType
			argument.isSynthetic = True
			argument.symbol = symbol
			arguments[index] = argument
		Next

		Local receiver:TBoundSymbolExpression = New TBoundSymbolExpression
		receiver.boundKind = BOUND_EXPRESSION_SYMBOL
		receiver.syntax = syntax.header.collection
		receiver.semanticType = element.declaredType
		receiver.isSynthetic = True
		receiver.symbol = element
		Local contractReceiver:TBoundExpression = ApplyImplicitConversion(receiver, syntax.header.collection, bound.iteration.deconstructionType, True)
		Local call:TBoundCallExpression = New TBoundCallExpression
		call.boundKind = BOUND_EXPRESSION_CALL
		call.syntax = syntax.header.collection
		call.semanticType = bound.iteration.deconstruct.returnType
		call.isSynthetic = True
		call.resolvedCall = bound.iteration.deconstruct
		call.receiver = contractReceiver
		call.arguments = arguments
		Local callStatement:TBoundExpressionStatement = New TBoundExpressionStatement
		InitializeBoundStatement(callStatement, BOUND_STATEMENT_EXPRESSION, syntax.header)
		callStatement.expression = call
		prefix :+ [callStatement]
		bound.body.statements = prefix + bound.body.statements
	End Method

	Method FindProtocolInterface:TNamedSemanticType(receiver:TSemanticType, normalizedName:String, requiredOriginModule:String = "", depth:Int = 0)
		If depth > 64 Then Return Null
		Local named:TNamedSemanticType = TNamedSemanticType(receiver)
		If Not named Or Not named.symbol Then Return Null
		Local nameMatches:Int = named.symbol.normalizedName = normalizedName Or named.symbol.name.ToLower() = normalizedName
		Local moduleMatches:Int = Not requiredOriginModule.length Or named.symbol.originModule.ToLower() = requiredOriginModule.ToLower()
		If nameMatches And moduleMatches Then Return named
		Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not inheritance Then Return Null
		For Local edge:TInheritanceEdge = EachIn InheritanceEdges(inheritance)
			Local inherited:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, TypeSubstitutions(named))
			Local found:TNamedSemanticType = FindProtocolInterface(inherited, normalizedName, requiredOriginModule, depth + 1)
			If found Then Return found
		Next
		Return Null
	End Method

	Method BuildBoundVariables:TBoundVariableDeclarationStatement(syntax:TVariableDeclarationStatementSyntax)
		Local bound:TBoundVariableDeclarationStatement = New TBoundVariableDeclarationStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_VARIABLE_DECLARATION, syntax)
		bound.variables = New TBoundVariable[syntax.declarators.length]
		For Local index:Int = 0 Until syntax.declarators.length
			Local declarator:TVariableDeclaratorSyntax = syntax.declarators[index]
			Local variable:TBoundVariable = New TBoundVariable
			variable.symbol = model.DeclaredSymbol(declarator)
			variable.arrayDimensions = BoundExpressions(declarator.arrayDimensions)
			If declarator.initializer And (Not variable.symbol Or Not variable.symbol.isExternal) Then variable.initializer = model.BoundExpression(declarator.initializer)
			If declarator.initializer And variable.symbol And variable.symbol.declaredType Then
				variable.initializer = ApplyImplicitConversion(variable.initializer, declarator.initializer, variable.symbol.declaredType, True)
			End If
			bound.variables[index] = variable
		Next
		StoreBoundStatement(syntax, bound)
		Return bound
	End Method

	Method BuildStatementCall:TBoundExpression(callStatement:TCallStatementSyntax)
		Local resolved:TResolvedCall = model.ResolvedCall(callStatement)
		If Not resolved Then Return model.BoundExpression(callStatement.expression)
		Local bound:TBoundCallExpression = New TBoundCallExpression
		InitializeBound(bound, BOUND_EXPRESSION_CALL, callStatement.expression, resolved.returnType)
		bound.isSynthetic = True
		bound.resolvedCall = resolved
		bound.callee = model.BoundExpression(callStatement.expression)
		If Not bound.callee And resolved.routine Then bound.callee = MakeRoutineReference(callStatement.expression, resolved.routine, CallableFromRoutine(resolved.routine))
		bound.receiver = BoundCallReceiver(callStatement.expression, resolved, Null)
		bound.arguments = BoundArguments(callStatement.argumentExpressions, resolved)
		Return bound
	End Method

	Method BuildBoundSelect:TBoundSelectStatement(syntax:TSelectStatementSyntax, routine:TSymbol)
		Local bound:TBoundSelectStatement = New TBoundSelectStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_SELECT, syntax)
		bound.expression = model.BoundExpression(syntax.expression)
		Local cases:TList = New TList
		For Local caseSyntax:TCaseClauseSyntax = EachIn syntax.cases
			If model.snapshot And Not TConditionalEvaluator.IsActive(caseSyntax.conditionalExpression, model.snapshot.options.conditionalSymbols) Then Continue
			Local boundCase:TBoundSelectCase = New TBoundSelectCase
			boundCase.syntax = caseSyntax
			boundCase.values = BoundExpressions(caseSyntax.values)
			boundCase.body = BuildBoundBlock(caseSyntax.body.statements, routine, caseSyntax.body)
			cases.AddLast(boundCase)
		Next
		bound.cases = BoundSelectCasesToArray(cases)
		For Local defaultClause:TDefaultClauseSyntax = EachIn syntax.defaultClauses
			If model.snapshot And Not TConditionalEvaluator.IsActive(defaultClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then Continue
			If Not bound.defaultBody Then bound.defaultBody = BuildBoundBlock(defaultClause.body.statements, routine, defaultClause.body)
		Next
		StoreBoundStatement(syntax, bound)
		Return bound
	End Method

	Function BoundSelectCasesToArray:TBoundSelectCase[](values:TList)
		Local result:TBoundSelectCase[] = New TBoundSelectCase[values.Count()]
		Local index:Int
		For Local value:TBoundSelectCase = EachIn values
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Method BuildBoundTry:TBoundTryStatement(syntax:TTryStatementSyntax, routine:TSymbol)
		Local bound:TBoundTryStatement = New TBoundTryStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_TRY, syntax)
		bound.body = BuildBoundBlock(syntax.body.statements, routine, syntax.body)
		bound.catches = New TBoundCatchClause[syntax.catches.length]
		For Local index:Int = 0 Until syntax.catches.length
			Local catchSyntax:TCatchClauseSyntax = syntax.catches[index]
			Local boundCatch:TBoundCatchClause = New TBoundCatchClause
			boundCatch.syntax = catchSyntax
			boundCatch.parameter = model.DeclaredSymbol(catchSyntax)
			boundCatch.body = BuildBoundBlock(catchSyntax.body.statements, routine, catchSyntax.body)
			bound.catches[index] = boundCatch
		Next
		If syntax.finallyClause Then bound.finallyBody = BuildBoundBlock(syntax.finallyClause.body.statements, routine, syntax.finallyClause.body)
		StoreBoundStatement(syntax, bound)
		Return bound
	End Method

	Method BuildBoundUsing:TBoundUsingStatement(syntax:TUsingStatementSyntax, routine:TSymbol)
		Local bound:TBoundUsingStatement = New TBoundUsingStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_USING, syntax)
		bound.resources = New TBoundVariableDeclarationStatement[syntax.resources.length]
		For Local index:Int = 0 Until syntax.resources.length
			bound.resources[index] = BuildBoundVariables(syntax.resources[index])
		Next
		bound.body = BuildBoundBlock(syntax.body.statements, routine, syntax.body)
		StoreBoundStatement(syntax, bound)
		Return bound
	End Method

	Method BuildBoundConditional:TBoundConditionalStatement(syntax:TConditionalRegionSyntax, routine:TSymbol)
		Local bound:TBoundConditionalStatement = New TBoundConditionalStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_CONDITIONAL, syntax)
		bound.branches = New TBoundConditionalBranch[syntax.branches.length]
		For Local index:Int = 0 Until syntax.branches.length
			Local branchSyntax:TConditionalBranchSyntax = syntax.branches[index]
			Local branch:TBoundConditionalBranch = New TBoundConditionalBranch
			branch.syntax = branchSyntax
			branch.body = BuildBoundBlock(branchSyntax.body.statements, routine, branchSyntax.body)
			bound.branches[index] = branch
		Next
		StoreBoundStatement(syntax, bound)
		Return bound
	End Method

	Method BuildBoundData:TBoundDataStatement(syntax:TSyntaxNode, expressions:TExpressionSyntax[])
		Local bound:TBoundDataStatement = New TBoundDataStatement
		InitializeBoundStatement(bound, BOUND_STATEMENT_DATA, syntax)
		bound.expressions = BoundExpressions(expressions)
		StoreBoundStatement(syntax, bound)
		Return bound
	End Method

	Function InitializeBoundStatement(bound:TBoundStatement, boundKind:Int, syntax:TSyntaxNode)
		bound.boundKind = boundKind
		bound.syntax = syntax
	End Function

	Method StoreBoundStatement:TBoundStatement(syntax:TSyntaxNode, bound:TBoundStatement)
		If syntax And bound Then model.boundStatementMap.Insert(syntax, bound)
		Return bound
	End Method

	Function BoundStatementsToArray:TBoundStatement[](statements:TList)
		Local result:TBoundStatement[] = New TBoundStatement[statements.Count()]
		Local index:Int
		For Local statement:TBoundStatement = EachIn statements
			result[index] = statement
			index :+ 1
		Next
		Return result
	End Function

	Method BindNode(node:TSyntaxNode, scope:TScope)
		If Not node Then Return
		Local includeSyntax:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
		If includeSyntax And currentDocument Then
			Local included:TSourceDocumentModel = IncludedDocument(currentDocument, includeSyntax)
			If included Then
				Local previous:TSourceDocumentModel = currentDocument
				currentDocument = included
				BindSequence(included.tree.root.members, scope)
				currentDocument = previous
			End If
			Return
		End If
		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration Then
			BindSequence(typeDeclaration.body.statements, model.ScopeFor(typeDeclaration))
			Return
		End If
		Local externBlock:TExternBlockSyntax = TExternBlockSyntax(node)
		If externBlock Then
			BindSequence(externBlock.body.statements, scope)
			Return
		End If
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine Then
			Local routineScope:TScope = model.ScopeFor(routine)
			Local routineSymbol:TSymbol = model.DeclaredSymbol(routine)
			If routineSymbol And routineSymbol.isIteratorRoutine Then
				Local iteratorType:TNamedSemanticType = FindProtocolInterface(routineSymbol.declaredType, "iiterator")
				If iteratorType And iteratorType.typeArguments.length = 1 Then
					routineSymbol.iteratorElementType = iteratorType.typeArguments[0]
				Else
					AddDiagnostic("BMX3332", "A routine containing Yield must return IIterator<T>, ICloseableIterator<T>, or a compatible iterator Interface.", routine.signature.span)
				End If
			End If
			For Local parameter:TParameterSyntax = EachIn routine.signature.parameters
				If parameter.staticArrayBound Then BindExpression(parameter.staticArrayBound.lengthExpression, routineScope)
				If parameter.callableType Then BindCallableStaticArrayBounds(parameter.callableType, routineScope)
				If parameter.defaultValue Then
					Local defaultType:TSemanticType = BindExpression(parameter.defaultValue, routineScope)
					Local parameterSymbol:TSymbol = model.DeclaredSymbol(parameter)
					If parameterSymbol And parameterSymbol.declaredType Then CheckAssignmentConversion(defaultType, parameterSymbol.declaredType, parameter.defaultValue.span, "default value for parameter '" + parameterSymbol.name + "'", parameter.defaultValue)
				End If
			Next
			BindSequence(routine.body.statements, routineScope)
			Return
		End If
		Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(node)
		If enumDeclaration Then
			Local enumScope:TScope = model.ScopeFor(enumDeclaration)
			If Not enumScope Then enumScope = scope
			For Local value:TEnumValueSyntax = EachIn enumDeclaration.values
				BindExpression(value.value, enumScope)
			Next
			Return
		End If
		Local variables:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
		If variables Then
			For Local declarator:TVariableDeclaratorSyntax = EachIn variables.declarators
				Local variableSymbol:TSymbol = model.DeclaredSymbol(declarator)
				If declarator.staticArrayBound Then BindExpression(declarator.staticArrayBound.lengthExpression, scope)
				For Local dimension:TExpressionSyntax = EachIn declarator.arrayDimensions
					Local dimensionType:TSemanticType = BindExpression(dimension, scope)
					If dimensionType And Not TConversionClassifier.IsIntegral(dimensionType) Then
						AddDiagnostic("BMX3310", "Type '" + dimensionType.DisplayName() + "' is not valid for an array dimension; an integral type is required.", dimension.span)
					End If
				Next
				If declarator.callableType Then BindCallableStaticArrayBounds(declarator.callableType, scope)
				If declarator.initializer Then
					' Extern Globals use their initializer as a native linkage
					' name, but Extern Const declarations still carry ordinary
					' BlitzMax compile-time expressions and may reference one
					' another.
					If Not variableSymbol Or Not variableSymbol.isExternal Or variableSymbol.kind = SYMBOL_CONST Then
						Local previousExcludedSymbol:TSymbol = initializerExcludedSymbol
						initializerExcludedSymbol = variableSymbol
						Local requiredType:TSemanticType
						If Not declarator.inferenceToken And variableSymbol Then requiredType = variableSymbol.declaredType
						Local initializerType:TSemanticType = BindContextualExpression(declarator.initializer, scope, requiredType)
						initializerExcludedSymbol = previousExcludedSymbol
						If declarator.inferenceToken And variableSymbol And variableSymbol.isTypeInferred Then
							EstablishInferredLocalType(variableSymbol, initializerType, declarator)
						Else If variableSymbol And variableSymbol.declaredType Then
							CheckAssignmentConversion(initializerType, variableSymbol.declaredType, declarator.initializer.span, "initializer for '" + variableSymbol.name + "'", declarator.initializer)
						End If
					End If
				End If
			Next
			Return
		End If
		Local assignment:TAssignmentStatementSyntax = TAssignmentStatementSyntax(node)
		If assignment Then
			Local leftType:TSemanticType
			If assignment.operatorToken.text = "=" Then
				' An indexed assignment resolves Operator[]= with the assigned value
				' appended to its bracket arguments.  Binding the target first as a
				' getter is still useful for built-in indexing and value context, but a
				' setter-only Type must not receive a speculative missing-Operator[]
				' diagnostic when its Operator[]= overload is applicable.
				Local previousIndexSetterTarget:TIndexExpressionSyntax = indexSetterTarget
				indexSetterTarget = TIndexExpressionSyntax(assignment.left)
				leftType = BindExpression(assignment.left, scope)
				indexSetterTarget = previousIndexSetterTarget
			End If
			Local rightType:TSemanticType = BindContextualExpression(assignment.right, scope, leftType)
			Local indexedTarget:TIndexExpressionSyntax = TIndexExpressionSyntax(assignment.left)
			If indexedTarget And assignment.operatorToken.text = "=" Then
				Local receiverType:TSemanticType = BindExpression(indexedTarget.expression, scope)
				Local indexTypes:TSemanticType[] = BindExpressions(indexedTarget.indexes, scope)
				If TNamedSemanticType(receiverType) Then
					Local setterArguments:TExpressionSyntax[] = AppendExpression(indexedTarget.indexes, assignment.right)
					Local setterTypes:TSemanticType[] = AppendType(indexTypes, rightType)
					Local resolvedSetter:TResolvedCall = ResolveOperator(assignment, indexedTarget, "[]=", receiverType, setterArguments, setterTypes, scope)
					If resolvedSetter Then
						RecordIndex(assignment, INDEX_ACCESS_OPERATOR, receiverType, resolvedSetter.returnType, resolvedSetter)
						Return
					End If
				End If
			End If
			If Not leftType Then leftType = BindExpression(assignment.left, scope)
			Local assignedSymbol:TSymbol = AssignedSymbol(assignment.left)
			If assignedSymbol And assignedSymbol.isReadOnly And Not CanAssignReadOnlyField(assignedSymbol, scope) Then
				AddDiagnostic("BMX3315", "ReadOnly field '" + assignedSymbol.name + "' can only be assigned in a constructor.", assignment.left.span)
			End If
			If assignment.operatorToken.text = "=" And TNamedSemanticType(leftType) And Not TNewExpressionSyntax(assignment.right) Then
				Local resolvedAssignment:TResolvedCall = ResolveOperator(assignment, assignment.left, ":=", leftType, [assignment.right], [rightType], scope)
				If resolvedAssignment Then Return
			End If
			If assignment.operatorToken.text = "=" Then ValidateSelfAssignment(assignment, assignedSymbol, scope)
			If assignment.operatorToken.text = "=" Then CheckAssignmentConversion(rightType, leftType, assignment.right.span, "assignment", assignment.right)
			If assignment.operatorToken.text <> "=" And TNamedSemanticType(leftType) Then
				ResolveOperator(assignment, assignment.left, assignment.operatorToken.text, leftType, [assignment.right], [rightType], scope)
			End If
			Return
		End If
		Local callStatement:TCallStatementSyntax = TCallStatementSyntax(node)
		If callStatement Then
			If callStatement.hasParentheses Then
				BindExpression(callStatement.expression, scope)
			Else
				' A standalone construction such as `New TFactory` is an
				' expression statement, not a command-style invocation of the
				' newly created object.
				If TNewExpressionSyntax(callStatement.expression) And callStatement.argumentExpressions.length = 0 Then
					BindExpression(callStatement.expression, scope)
					Return
				End If
				Local argumentTypes:TSemanticType[] = BindCallArgumentTypes(callStatement.expression, callStatement.argumentExpressions, scope)
				Local resolvedCommand:TResolvedCall = ResolveCall(callStatement, callStatement.expression, callStatement.argumentExpressions, argumentTypes, New TTypeReferenceSyntax[0], scope)
				ValidateImplicitRoutineCapture(callStatement.expression, resolvedCommand)
			End If
			Return
		End If
		Local returnStatement:TReturnStatementSyntax = TReturnStatementSyntax(node)
		If returnStatement Then
			If returnStatement.expression Then
				Local routineSymbol:TSymbol = EnclosingRoutine(scope)
				If routineSymbol And routineSymbol.isIteratorRoutine Then
					BindExpression(returnStatement.expression, scope)
					AddDiagnostic("BMX3334", "A yielding routine can use only bare Return to complete the iterator.", returnStatement.expression.span)
					Return
				End If
				Local requiredReturn:TSemanticType
				If routineSymbol Then requiredReturn = routineSymbol.declaredType Else requiredReturn = model.BuiltinType("Int")
				Local returnedType:TSemanticType = BindContextualExpression(returnStatement.expression, scope, requiredReturn)
				If routineSymbol And routineSymbol.declaredType Then
					If IsBuiltin(routineSymbol.declaredType, "void") Then
						AddDiagnostic("BMX3310", ReturnRoutineKind(routineSymbol) + " '" + routineSymbol.name + "' does not return a value, so Return cannot include an expression.", returnStatement.expression.span)
					Else
						CheckAssignmentConversion(returnedType, routineSymbol.declaredType, returnStatement.expression.span, "return from '" + routineSymbol.name + "'", returnStatement.expression)
					End If
				Else If Not routineSymbol Then
					' Production BlitzMax treats the module body as an Int-returning
					' entry routine, so an explicit value follows Int conversion rules.
					CheckAssignmentConversion(returnedType, model.BuiltinType("Int"), returnStatement.expression.span, "return from the module entry", returnStatement.expression)
				End If
			Else If Not EnclosingRoutine(scope) And EffectiveSourceMode() = SOURCE_MODE_SUPERSTRICT Then
				AddDiagnostic("BMX3311", "The module entry returns Int, so Return requires a value in SuperStrict code.", returnStatement.returnToken.span)
			End If
			Return
		End If
		Local yieldStatement:TYieldStatementSyntax = TYieldStatementSyntax(node)
		If yieldStatement Then
			Local routineSymbol:TSymbol = EnclosingRoutine(scope)
			If Not routineSymbol Then
				If yieldStatement.expression Then BindExpression(yieldStatement.expression, scope)
				AddDiagnostic("BMX3333", "Yield is valid only inside a Function or Method.", yieldStatement.yieldToken.span)
			Else If yieldStatement.expression Then
				If yieldStatement.fromToken Then
					BindExpression(yieldStatement.expression, scope)
				Else If routineSymbol.iteratorElementType Then
					Local yieldedType:TSemanticType = BindContextualExpression(yieldStatement.expression, scope, routineSymbol.iteratorElementType)
					CheckAssignmentConversion(yieldedType, routineSymbol.iteratorElementType, yieldStatement.expression.span, "Yield from '" + routineSymbol.name + "'", yieldStatement.expression)
				Else
					BindExpression(yieldStatement.expression, scope)
				End If
			End If
			Return
		End If
		Local throwStatement:TThrowStatementSyntax = TThrowStatementSyntax(node)
		If throwStatement Then
			BindExpression(throwStatement.expression, scope)
			Return
		End If
		Local assertStatement:TAssertStatementSyntax = TAssertStatementSyntax(node)
		If assertStatement Then
			BindExpression(assertStatement.condition, scope)
			BindExpression(assertStatement.message, scope)
			Return
		End If
		Local releaseStatement:TReleaseStatementSyntax = TReleaseStatementSyntax(node)
		If releaseStatement Then
			Local releaseType:TSemanticType = BindExpression(releaseStatement.expression, scope)
			If releaseStatement.expression And Not IsAddressable(releaseStatement.expression) Then AddDiagnostic("BMX3311", "Release requires a writable integer variable.", releaseStatement.expression.span)
			If releaseType And Not TConversionClassifier.IsIntegral(releaseType) Then AddDiagnostic("BMX3310", "Release requires an integer variable, not '" + releaseType.DisplayName() + "'.", releaseStatement.expression.span)
			Return
		End If
		Local defDataStatement:TDefDataStatementSyntax = TDefDataStatementSyntax(node)
		If defDataStatement Then
			BindExpressions(defDataStatement.values, scope)
			Return
		End If
		Local readDataStatement:TReadDataStatementSyntax = TReadDataStatementSyntax(node)
		If readDataStatement Then
			BindExpressions(readDataStatement.targets, scope)
			Return
		End If
		' RestoreData names a data label, not a value symbol. Label binding belongs
		' to the later control/data-flow pass.
		If TRestoreDataStatementSyntax(node) Then Return
		Local block:TBlockSyntax = TBlockSyntax(node)
		If block Then
			Local blockScope:TScope = model.ScopeFor(block)
			If Not blockScope Then blockScope = scope
			BindSequence(block.statements, blockScope)
			Return
		End If
		Local ifStatement:TIfStatementSyntax = TIfStatementSyntax(node)
		If ifStatement Then
			BindExpression(ifStatement.condition, scope)
			BindNode(ifStatement.thenBlock, scope)
			For Local clause:TElseIfClauseSyntax = EachIn ifStatement.elseIfClauses
				BindExpression(clause.condition, scope)
				BindNode(clause.block, scope)
			Next
			If ifStatement.elseClause Then BindNode(ifStatement.elseClause.block, scope)
			Return
		End If
		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(node)
		If whileStatement Then
			BindExpression(whileStatement.condition, scope)
			BindNode(whileStatement.body, scope)
			Return
		End If
		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(node)
		If repeatStatement Then
			BindNode(repeatStatement.body, scope)
			BindExpression(repeatStatement.condition, scope)
			Return
		End If
		Local forStatement:TForStatementSyntax = TForStatementSyntax(node)
		If forStatement Then
			Local loopScope:TScope = model.ScopeFor(forStatement)
			If Not loopScope Then loopScope = scope
			Local initialType:TSemanticType = BindExpression(forStatement.header.initialValue, loopScope)
			If forStatement.header.declaration And initialType Then
				Local loopVariable:TSymbol = model.DeclaredSymbol(forStatement.header.declaration)
				If loopVariable And loopVariable.declaredType Then CheckAssignmentConversion(initialType, loopVariable.declaredType, forStatement.header.initialValue.span, "For initializer for '" + loopVariable.name + "'", forStatement.header.initialValue)
			End If
			BindExpression(forStatement.header.target, loopScope)
			Local collectionType:TSemanticType = BindExpression(forStatement.header.collection, loopScope)
			If forStatement.header.eachInToken And collectionType Then
				Local collection:TBoundExpression = New TBoundExpression
				collection.semanticType = collectionType
				Local iteration:TResolvedEachIn = ResolveEachIn(collection, loopScope, forStatement, forStatement.header.collection)
				If iteration Then eachInResolutions.Insert(forStatement, iteration)
				If iteration And forStatement.header.declarations.length > 1 Then
					BindEachInDeconstruction(iteration, forStatement.header, loopScope, forStatement)
				Else If iteration Then
					BindEachInTarget(iteration, forStatement.header)
				End If
			End If
			BindExpression(forStatement.header.limit, loopScope)
			BindExpression(forStatement.header.stepExpression, loopScope)
			BindNode(forStatement.body, loopScope)
			Return
		End If
		Local selectStatement:TSelectStatementSyntax = TSelectStatementSyntax(node)
		If selectStatement Then
			Local selectedType:TSemanticType = BindExpression(selectStatement.expression, scope)
			Local activeDefault:TDefaultClauseSyntax
			For Local defaultClause:TDefaultClauseSyntax = EachIn selectStatement.defaultClauses
				If model.snapshot And Not TConditionalEvaluator.IsActive(defaultClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then Continue
				If activeDefault And (model.snapshot Or (Not activeDefault.conditionalExpression And Not defaultClause.conditionalExpression)) Then AddDiagnostic("BMX2400", "A Select statement can contain only one active Default clause.", defaultClause.defaultToken.span)
				If Not activeDefault Then activeDefault = defaultClause
			Next
			For Local caseClause:TCaseClauseSyntax = EachIn selectStatement.cases
				If model.snapshot And Not TConditionalEvaluator.IsActive(caseClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then Continue
				If activeDefault And caseClause.span.start > activeDefault.span.start And (model.snapshot Or (Not activeDefault.conditionalExpression And Not caseClause.conditionalExpression)) Then AddDiagnostic("BMX2401", "An active Case clause cannot follow Default.", caseClause.caseToken.span)
				For Local caseValue:TExpressionSyntax = EachIn caseClause.values
					Local caseType:TSemanticType = BindExpression(caseValue, scope)
					If selectedType Then CheckConversion(caseType, selectedType, caseValue.span, "Select Case value", caseValue)
				Next
				BindNode(caseClause.body, scope)
			Next
			For Local defaultClause:TDefaultClauseSyntax = EachIn selectStatement.defaultClauses
				If Not model.snapshot Or TConditionalEvaluator.IsActive(defaultClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then BindNode(defaultClause.body, scope)
			Next
			Return
		End If
		Local tryStatement:TTryStatementSyntax = TTryStatementSyntax(node)
		If tryStatement Then
			BindNode(tryStatement.body, scope)
			For Local catchClause:TCatchClauseSyntax = EachIn tryStatement.catches
				BindNode(catchClause.body, scope)
			Next
			If tryStatement.finallyClause Then BindNode(tryStatement.finallyClause.body, scope)
			Return
		End If
		Local usingStatement:TUsingStatementSyntax = TUsingStatementSyntax(node)
		If usingStatement Then
			Local usingScope:TScope = model.ScopeFor(usingStatement.body)
			If Not usingScope Then usingScope = scope
			For Local resource:TVariableDeclarationStatementSyntax = EachIn usingStatement.resources
				BindNode(resource, usingScope)
			Next
			BindNode(usingStatement.body, usingScope)
			Return
		End If
		Local conditional:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
		If conditional Then
			If model.snapshot Then
				Local indexes:Int[] = TConditionalEvaluator.ActiveBranchIndexes(conditional, model.snapshot.options.conditionalSymbols)
				For Local index:Int = EachIn indexes
					BindNode(conditional.branches[index].body, scope)
				Next
			Else
				For Local branch:TConditionalBranchSyntax = EachIn conditional.branches
					BindNode(branch.body, scope)
				Next
			End If
			Return
		End If
	End Method

	Method BindCallableStaticArrayBounds(callableType:TCallableTypeSyntax, scope:TScope)
		If Not callableType Then Return
		For Local parameter:TParameterSyntax = EachIn callableType.parameters
			If parameter.staticArrayBound Then BindExpression(parameter.staticArrayBound.lengthExpression, scope)
			If parameter.callableType Then BindCallableStaticArrayBounds(parameter.callableType, scope)
		Next
	End Method

	Method EstablishInferredLocalType(symbol:TSymbol, initializerType:TSemanticType, declarator:TVariableDeclaratorSyntax)
		If Not symbol Or Not declarator Or Not declarator.inferenceToken Then Return
		If Not initializerType Then
			Local arrayLiteral:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(declarator.initializer)
			If arrayLiteral And Not arrayLiteral.elements.length Then
				AddDiagnostic("BMX3350", "The type of local '" + symbol.name + "' cannot be inferred from an empty array literal; write an explicit array type.", declarator.initializer.span)
			End If
			Return
		End If
		If TErrorSemanticType(initializerType) Then Return
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(initializerType)
		Local arrayType:TArraySemanticType = TArraySemanticType(initializerType)
		If arrayType And TErrorSemanticType(arrayType.elementType) Then Return
		If (builtin And builtin.name.ToLower() = "null") Or (arrayType And IsBuiltin(arrayType.elementType, "null")) Then
			AddDiagnostic("BMX3351", "The type of local '" + symbol.name + "' cannot be inferred from Null; write an explicit reference type.", declarator.initializer.span)
			Return
		End If
		If builtin And builtin.name.ToLower() = "void" Then
			AddDiagnostic("BMX3352", "The initializer for inferred local '" + symbol.name + "' does not produce a value.", declarator.initializer.span)
			Return
		End If
		symbol.declaredType = initializerType
	End Method

	Method BindExpression:TSemanticType(expression:TExpressionSyntax, scope:TScope)
		If Not expression Then Return Null
		If TOmittedArgumentExpressionSyntax(expression) Then Return Null
		Local existing:TSemanticType = model.ExpressionType(expression)
		If existing Then Return existing
		Local result:TSemanticType
		Local functionLiteral:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(expression)
		If functionLiteral Then
			AddDiagnostic("BMX3340", "A Function literal requires an explicit callable target type.", functionLiteral.functionToken.span)
			result = ErrorType("Function literal")
		End If
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If Not result And literal Then
			result = LiteralType(literal.literalToken)
		Else If Not result
			Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
			If name Then
				Local nameText:String = name.nameToken.text.ToLower()
				If nameText = "self" Then result = SelfType(scope)
				If nameText = "super" Then
					If name.qualifiedSuperType Then
						result = ResolveType(name.qualifiedSuperType, scope)
						Local qualifiedInterface:TNamedSemanticType = TNamedSemanticType(result)
						If Not qualifiedInterface Or Not qualifiedInterface.symbol Or qualifiedInterface.symbol.kind <> SYMBOL_INTERFACE Then
							AddDiagnostic("BMX3324", "Qualified Super requires an Interface type.", name.span)
						Else If Not inheritanceValidator.IsSubtype(SelfType(scope), result, 0) Then
							AddDiagnostic("BMX3325", "Interface '" + result.DisplayName() + "' is not inherited by the current type.", name.span)
						End If
					Else
						result = SuperType(scope)
					End If
				End If
				Local symbols:TSymbol[] = Lookup(scope, name.nameToken.text, name)
				If name.typeArguments.length Then
					Local candidates:TSymbol[] = RoutineCandidates(name, scope)
					result = BindSpecializedRoutineReference(name, name.nameToken.text, name.typeArguments, candidates, New TMap, SelfType(scope), scope)
				End If
				For Local symbol:TSymbol = EachIn symbols
					If result Then Exit
					If symbol.NamespaceKind() = SYMBOL_NAMESPACE_VALUE Then
						model.referencedSymbolMap.Insert(name, symbol)
						Local implicitReceiver:TSemanticType = SelfType(scope)
						Local declaringReceiver:TSemanticType = MemberDeclaringType(implicitReceiver, symbol)
						result = TGenericRoutineInference.Substitute(symbol.declaredType, TypeSubstitutions(declaringReceiver))
						Exit
					End If
				Next
				If Not result Then
					Local routines:TSymbol[] = FilterRoutines(symbols)
					If routines.length = 1 Then
						model.referencedSymbolMap.Insert(name, routines[0])
						Local callable:TCallableSemanticType = CallableFromRoutine(routines[0])
						If IsInstanceRoutine(routines[0]) Then
							If Not SupportsBoundMethodReceiver(SelfType(scope)) Then
								AddDiagnostic("BMX3348", "Bound Method references currently support Type and Interface receivers; Struct receiver capture semantics are not yet defined.", name.span)
								result = ErrorType(routines[0].name)
							Else
								result = ManagedRoutineClosure(callable, routines[0])
							End If
						Else
							result = callable
						End If
					End If
				End If
				If Not result Then
					Local declaredMembers:TSymbol[] = MemberSymbols(SelfType(scope), name.nameToken.text)
					If Not ReportInaccessibleName(name, declaredMembers, scope) Then AddDiagnostic("BMX3300", "Name '" + name.nameToken.text + "' could not be resolved as a value.", name.span)
				End If
			Else
				Local call:TCallExpressionSyntax = TCallExpressionSyntax(expression)
				If call Then
					Local argumentTypes:TSemanticType[] = BindCallArgumentTypes(call.callee, call.arguments, scope)
					Local namedCastTarget:TSemanticType = ResolveNamedCastTarget(call, scope)
					If namedCastTarget Then
						model.namedCastTargetMap.Insert(call, namedCastTarget)
						If call.arguments.length <> 1 Then
							AddDiagnostic("BMX3313", "A named type cast requires exactly one expression.", call.span)
						Else If argumentTypes[0] And Not conversions.ClassifyExplicit(argumentTypes[0], namedCastTarget).Exists() Then
							AddDiagnostic("BMX3312", "Type '" + argumentTypes[0].DisplayName() + "' cannot be explicitly converted to '" + namedCastTarget.DisplayName() + "'.", call.span)
						End If
						result = namedCastTarget
					Else
						Local resolved:TResolvedCall = ResolveCall(call, call.callee, call.arguments, argumentTypes, call.typeArguments, scope)
						If resolved Then
							ValidateImplicitRoutineCapture(call.callee, resolved)
							Local qualifiedSuper:TNameExpressionSyntax = QualifiedSuperReceiver(call.callee)
							If qualifiedSuper And resolved.routine And resolved.routine.interfaceMethodKind <> INTERFACE_METHOD_DEFAULT Then AddDiagnostic("BMX3326", "Qualified Super can call only a Default Interface method body.", call.span)
							result = resolved.returnType
						End If
					End If
				Else
					Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
					If parenthesized Then
						result = BindExpression(parenthesized.expression, scope)
					Else
						Local cast:TCastExpressionSyntax = TCastExpressionSyntax(expression)
						If cast Then
							result = BindCast(cast, scope)
						Else
							Local ascription:TTypeAscriptionExpressionSyntax = TTypeAscriptionExpressionSyntax(expression)
							If ascription Then
								BindExpression(ascription.expression, scope)
								result = ResolveType(ascription.targetType, scope)
							Else
								Local creation:TNewExpressionSyntax = TNewExpressionSyntax(expression)
								If creation Then
								Local constructorArgumentTypes:TSemanticType[] = BindExpressions(creation.arguments, scope)
								Local dimensionTypes:TSemanticType[] = BindExpressions(creation.dimensions, scope)
								For Local dimensionIndex:Int = 0 Until creation.dimensions.length
									If creation.dimensions[dimensionIndex] And dimensionTypes[dimensionIndex] And Not TConversionClassifier.IsIntegral(dimensionTypes[dimensionIndex]) Then
										AddDiagnostic("BMX3310", "Type '" + dimensionTypes[dimensionIndex].DisplayName() + "' is not valid for an array dimension; an integral type is required.", creation.dimensions[dimensionIndex].span)
									End If
								Next
								Local dynamicInstance:TSemanticType = BindDynamicNewInstance(creation, scope)
								If dynamicInstance Then
									result = dynamicInstance
								Else
									result = ResolveType(creation.createdType, scope)
								End If
								If creation.dimensionRanks.length = 0 Then
									Local createdNamed:TNamedSemanticType = TNamedSemanticType(result)
									If createdNamed And createdNamed.symbol And model.IsAbstractType(createdNamed.symbol) Then
										AddDiagnostic("BMX3316", "Cannot create an instance of abstract type '" + createdNamed.DisplayName() + "'.", creation.createdType.span)
									End If
									If createdNamed And createdNamed.symbol Then ResolveConstructor(creation, createdNamed, constructorArgumentTypes, scope)
								End If
								For Local rank:Int = EachIn creation.dimensionRanks
									Local arrayType:TArraySemanticType = New TArraySemanticType
									arrayType.kind = SEMANTIC_TYPE_ARRAY
									arrayType.elementType = result
									arrayType.rank = rank
									result = arrayType
								Next
							Else
								Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
								If member Then
									result = BindMember(member, scope)
								Else
					Local indexed:TIndexExpressionSyntax = TIndexExpressionSyntax(expression)
					If indexed Then
						Local indexedType:TSemanticType = BindExpression(indexed.expression, scope)
						Local indexTypes:TSemanticType[] = BindExpressions(indexed.indexes, scope)
						Local rangeIndex:Int = indexed.indexes.length = 1 And indexTypes.length = 1 And IsCanonicalRangeType(indexTypes[0])
						If rangeIndex And IsBuiltin(indexedType, "string") Then
							result = indexedType
							RecordRangeIndex(indexed, INDEX_ACCESS_RANGE_STRING, indexedType, result, indexTypes[0], scope)
						Else If IsBuiltin(indexedType, "string") And indexed.indexes.length = 1 Then
							result = model.BuiltinType("Int")
							RecordIndex(indexed, INDEX_ACCESS_STRING, indexedType, result)
						End If
						Local arrayType:TArraySemanticType = TArraySemanticType(indexedType)
						If arrayType Then
							If rangeIndex Then
								If arrayType.rank = 1 Then
									result = indexedType
									RecordRangeIndex(indexed, INDEX_ACCESS_RANGE_ARRAY, indexedType, result, indexTypes[0], scope)
								Else
									AddDiagnostic("BMX3310", "Range slicing requires a one-dimensional heap Array.", indexed.span)
									result = ErrorType("Range slice")
								End If
							Else
								result = arrayType.elementType
								RecordIndex(indexed, INDEX_ACCESS_ARRAY, indexedType, result)
							End If
						End If
						Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(indexedType)
						If staticArrayType Then
							If rangeIndex Then
								AddDiagnostic("BMX3310", "Range slicing requires a one-dimensional heap Array; StaticArray values are not supported.", indexed.span)
								result = ErrorType("Range slice")
							Else
								result = staticArrayType.elementType
								RecordIndex(indexed, INDEX_ACCESS_STATIC_ARRAY, indexedType, result)
							End If
						End If
						Local pointerType:TPointerSemanticType = TPointerSemanticType(indexedType)
						If pointerType Then
							result = pointerType.elementType
							RecordIndex(indexed, INDEX_ACCESS_POINTER, indexedType, result)
						End If
						If Not result And TNamedSemanticType(indexedType) Then
							Local resolvedIndex:TResolvedCall = ResolveOperator(indexed, indexed, "[]", indexedType, indexed.indexes, indexTypes, scope)
							If resolvedIndex Then
								result = resolvedIndex.returnType
								RecordIndex(indexed, INDEX_ACCESS_OPERATOR, indexedType, result, resolvedIndex)
							Else If indexed <> indexSetterTarget Then
								AddDiagnostic("BMX3304", "Type '" + indexedType.DisplayName() + "' does not provide an applicable indexing operator.", indexed.span)
							End If
						End If
						Local resolvedAccess:TResolvedIndexAccess = model.ResolvedIndex(indexed)
						If resolvedAccess And resolvedAccess.accessKind <> INDEX_ACCESS_OPERATOR And resolvedAccess.accessKind <> INDEX_ACCESS_RANGE_ARRAY And resolvedAccess.accessKind <> INDEX_ACCESS_RANGE_STRING Then
							Local indexType:TSemanticType = model.BuiltinType("UInt")
							For Local index:Int = 0 Until indexed.indexes.length
								If indexed.indexes[index] And indexTypes[index] And Not conversions.ClassifyAssignmentExpression(indexed.indexes[index], indexTypes[index], indexType).Exists() Then AddDiagnostic("BMX3310", "Type '" + indexTypes[index].DisplayName() + "' is not valid for an index expression; conversion to UInt is required.", indexed.indexes[index].span)
							Next
						End If
					Else
						Local slice:TSliceExpressionSyntax = TSliceExpressionSyntax(expression)
						If slice Then
							Local slicedType:TSemanticType = BindExpression(slice.expression, scope)
							Local lowerType:TSemanticType = BindExpression(slice.lowerBound, scope)
							Local upperType:TSemanticType = BindExpression(slice.upperBound, scope)
							Local sliceIndexType:TSemanticType = model.BuiltinType("Int")
							If slice.lowerBound And lowerType And Not conversions.ClassifyAssignmentExpression(slice.lowerBound, lowerType, sliceIndexType).Exists() Then AddDiagnostic("BMX3310", "Type '" + lowerType.DisplayName() + "' is not valid for a slice bound; conversion to Int is required.", slice.lowerBound.span)
							If slice.upperBound And upperType And Not conversions.ClassifyAssignmentExpression(slice.upperBound, upperType, sliceIndexType).Exists() Then AddDiagnostic("BMX3310", "Type '" + upperType.DisplayName() + "' is not valid for a slice bound; conversion to Int is required.", slice.upperBound.span)
							If IsBuiltin(slicedType, "string") Or TArraySemanticType(slicedType) Then result = slicedType
							If Not result And slicedType Then AddDiagnostic("BMX3304", "Type '" + slicedType.DisplayName() + "' does not support slicing.", slice.span)
						Else
							Local range:TRangeExpressionSyntax = TRangeExpressionSyntax(expression)
							If range Then result = BindRangeExpression(range, scope)
							Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(expression)
							If Not result And unary Then result = BindUnary(unary, scope)
							Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
							If Not result And binary Then result = BindBinary(binary, scope)
							Local arrayLiteral:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(expression)
							If Not result And arrayLiteral Then result = BindArrayLiteral(arrayLiteral, scope)
						End If
					End If
								End If
							End If
						End If
					End If
				End If
				End If
			End If
		End If
		If result Then
			ValidateActiveCapture(expression)
			model.expressionTypeMap.Insert(expression, result)
			If Not model.BoundExpression(expression) Then model.boundExpressionMap.Insert(expression, BuildBoundExpression(expression, result, scope))
		End If
		Return result
	End Method

	Method BindRangeExpression:TSemanticType(range:TRangeExpressionSyntax, scope:TScope)
		Local canonicalRange:TSemanticType
		For Local symbol:TSymbol = EachIn Lookup(scope, "Range", range)
			If symbol.NamespaceKind() = SYMBOL_NAMESPACE_TYPE And IsCanonicalRangeType(symbol.declaredType) Then canonicalRange = symbol.declaredType; Exit
		Next
		If Not canonicalRange Then
			BindRangeEndpointValue(range.lowerBound, scope)
			BindRangeEndpointValue(range.upperBound, scope)
			AddDiagnostic("BMX3350", "Range expression syntax requires Import BRL.Range.", range.rangeToken.span)
			Return ErrorType("Range expression")
		End If

		Local lower:TCallExpressionSyntax = SyntheticRangeEndpointCall(range, range.lowerBound, range.lowerFromEndToken)
		Local upper:TCallExpressionSyntax = SyntheticRangeEndpointCall(range, range.upperBound, range.upperFromEndToken)
		Local construction:TCallExpressionSyntax = SyntheticStaticCall("Range", "FromEndpoints", [lower, upper], range.span)
		Local result:TSemanticType = BindExpression(construction, scope)
		Local bound:TBoundExpression = model.BoundExpression(construction)
		If bound Then
			bound.syntax = range
			bound.isSynthetic = True
			model.boundExpressionMap.Insert(range, bound)
		End If
		Return result
	End Method

	Method BindRangeEndpointValue:TSemanticType(expression:TExpressionSyntax, scope:TScope)
		If Not expression Then Return Null
		Local result:TSemanticType = BindExpression(expression, scope)
		If result And Not TConversionClassifier.IsIntegral(result) Then AddDiagnostic("BMX3310", "Type '" + result.DisplayName() + "' is not valid for a Range endpoint; conversion to Int is required.", expression.span)
		Return result
	End Method

	Method SyntheticRangeEndpointCall:TCallExpressionSyntax(range:TRangeExpressionSyntax, value:TExpressionSyntax, fromEndToken:TSyntaxToken)
		If Not value Then Return SyntheticStaticCall("RangeEndpoint", "Open", New TExpressionSyntax[0], range.rangeToken.span)
		Local methodName:String = "FromStart"
		If fromEndToken Then methodName = "FromEnd"
		Return SyntheticStaticCall("RangeEndpoint", methodName, [value], value.span)
	End Method

	Function SyntheticStaticCall:TCallExpressionSyntax(typeName:String, methodName:String, arguments:TExpressionSyntax[], span:TSourceSpan)
		Local owner:TNameExpressionSyntax = New TNameExpressionSyntax
		owner.kind = SYNTAX_NAME_EXPRESSION
		owner.nameToken = TSyntaxToken.Create(TOKEN_IDENTIFIER, span, typeName)
		owner.span = span
		Local member:TMemberAccessExpressionSyntax = New TMemberAccessExpressionSyntax
		member.kind = SYNTAX_MEMBER_EXPRESSION
		member.expression = owner
		member.dotToken = TSyntaxToken.Create(TOKEN_SYMBOL, span, ".")
		member.nameToken = TSyntaxToken.Create(TOKEN_IDENTIFIER, span, methodName)
		member.span = span
		Local call:TCallExpressionSyntax = New TCallExpressionSyntax
		call.kind = SYNTAX_CALL_EXPRESSION
		call.callee = member
		call.arguments = arguments
		call.typeArguments = New TTypeReferenceSyntax[0]
		call.openToken = TSyntaxToken.Create(TOKEN_SYMBOL, span, "(")
		call.closeToken = TSyntaxToken.Create(TOKEN_SYMBOL, span, ")")
		call.span = span
		Return call
	End Function

	Method BindContextualExpression:TSemanticType(expression:TExpressionSyntax, scope:TScope, required:TSemanticType)
		Local literal:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(expression)
		If literal Then Return BindFunctionLiteral(literal, scope, required)
		If TClosureSemanticType(required) Then
			Local contextualMethod:TSemanticType = BindContextualBoundMethodReference(expression, scope, required)
			If contextualMethod Then Return contextualMethod
		End If
		Return BindExpression(expression, scope)
	End Method

	' A target Closure signature supplies the missing overload context for a
	' first-class instance Method. Calls already perform overload selection from
	' their arguments; a reference has no arguments, so use the target signature
	' and retain the uniquely compatible Method.
	Method BindContextualBoundMethodReference:TSemanticType(expression:TExpressionSyntax, scope:TScope, required:TSemanticType)
		If model.ExpressionType(expression) Then Return Null
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If (member And member.typeArguments.length) Or (name And name.typeArguments.length) Then Return Null
		If Not member And Not name Then Return Null

		Local receiverType:TSemanticType
		Local lookupType:TSemanticType
		Local staticReceiver:TSemanticType
		Local candidates:TSymbol[]
		If member Then
			Local selectedScope:TScope = StaticMemberScope(member.expression, scope)
			staticReceiver = GenericTypeQualifier(member.expression, scope)
			If selectedScope Then Return Null
			receiverType = BindExpression(member.expression, scope)
			lookupType = MemberLookupReceiver(receiverType)
			candidates = AccessibleSymbols(MemberSymbols(lookupType, member.nameToken.text), scope)
		Else
			receiverType = SelfType(scope)
			lookupType = receiverType
			candidates = Lookup(scope, name.nameToken.text, name)
		End If
		candidates = FilterRoutines(candidates)
		If candidates.length < 2 Then Return Null

		Local selected:TSymbol
		Local selectedType:TClosureSemanticType
		Local matches:Int
		For Local routine:TSymbol = EachIn candidates
			If Not IsInstanceRoutine(routine) Or routine.genericArity Then Continue
			Local declaringReceiver:TSemanticType = MemberDeclaringType(lookupType, routine)
			If Not declaringReceiver And staticReceiver Then declaringReceiver = staticReceiver
			Local callable:TCallableSemanticType = TCallableSemanticType(TGenericRoutineInference.Substitute(CallableFromRoutine(routine), TypeSubstitutions(declaringReceiver)))
			Local closure:TClosureSemanticType = ManagedRoutineClosure(callable, routine)
			If Not conversions.Classify(closure, required).Exists() Then Continue
			selected = routine
			selectedType = closure
			matches :+ 1
		Next
		If matches = 0 Then Return Null
		If matches > 1 Then
			AddDiagnostic("BMX3349", "Bound Method reference is ambiguous for target type '" + required.DisplayName() + "'.", expression.span)
			Local error:TErrorSemanticType = ErrorType("ambiguous bound Method")
			model.expressionTypeMap.Insert(expression, error)
			Return error
		End If
		If Not SupportsBoundMethodReceiver(receiverType) Then
			AddDiagnostic("BMX3348", "Bound Method references currently support Type and Interface receivers; Struct receiver capture semantics are not yet defined.", expression.span)
			Local error:TErrorSemanticType = ErrorType(selected.name)
			model.expressionTypeMap.Insert(expression, error)
			Return error
		End If

		model.referencedSymbolMap.Insert(expression, selected)
		If member Then
			Local access:TResolvedMemberAccess = New TResolvedMemberAccess
			access.member = selected
			access.receiverType = receiverType
			access.lookupType = lookupType
			access.implicitPointerDereference = lookupType <> receiverType
			model.resolvedMemberMap.Insert(member, access)
		End If
		ValidateActiveCapture(expression)
		model.expressionTypeMap.Insert(expression, selectedType)
		model.boundExpressionMap.Insert(expression, BuildBoundExpression(expression, selectedType, scope))
		Return selectedType
	End Method

	Method BindFunctionLiteral:TSemanticType(literal:TFunctionLiteralExpressionSyntax, scope:TScope, required:TSemanticType)
		Local existing:TSemanticType = model.ExpressionType(literal)
		If existing Then Return existing
		Local callable:TCallableSemanticType = TCallableSemanticType(required)
		Local closure:TClosureSemanticType = TClosureSemanticType(required)
		If closure Then callable = closure.signature
		If Not callable Then
			AddDiagnostic("BMX3340", "A Function literal requires an explicit callable target type.", literal.functionToken.span)
			Return ErrorType("Function literal")
		End If
		If EffectiveSourceMode() <> SOURCE_MODE_SUPERSTRICT Then AddDiagnostic("BMX3341", "Function literals require SuperStrict mode.", literal.functionToken.span)

		Local literalScope:TScope = model.ScopeFor(literal)
		Local routine:TSymbol = model.DeclaredSymbol(literal)
		If Not literalScope Or Not routine Then Return ErrorType("Function literal")
		routine.declaredType = callable.returnType
		routine.callingConvention = callable.callingConvention
		routine.parameterTypes = New TSemanticType[literal.parameters.length]
		routine.parameters = New TSemanticParameter[literal.parameters.length]
		If literal.parameters.length <> callable.parameterTypes.length Then
			AddDiagnostic("BMX3342", "Function literal has " + literal.parameters.length + " parameters but target type '" + callable.DisplayName() + "' requires " + callable.parameterTypes.length + ".", literal.span)
		End If
		For Local index:Int = 0 Until literal.parameters.length
			Local parameter:TParameterSyntax = literal.parameters[index]
			Local symbol:TSymbol = model.DeclaredSymbol(parameter)
			Local targetType:TSemanticType
			Local targetMode:Int = PARAMETER_PASS_VALUE
			If index < callable.parameterTypes.length Then targetType = callable.parameterTypes[index]
			If index < callable.parameterModes.length Then targetMode = callable.parameterModes[index]
			If symbol Then
				If symbol.declaredType And targetType And Not TGenericRoutineInference.SameType(symbol.declaredType, targetType) Then AddDiagnostic("BMX3343", "Function literal parameter '" + symbol.name + "' has type '" + symbol.declaredType.DisplayName() + "' but target requires '" + targetType.DisplayName() + "'.", parameter.span)
				If Not symbol.declaredType Then symbol.declaredType = targetType
				symbol.parameterMode = targetMode
			End If
			If parameter.varToken And targetMode <> PARAMETER_PASS_VAR Then AddDiagnostic("BMX3344", "Function literal parameter '" + parameter.nameToken.text + "' must match the target's Var passing mode.", parameter.span)
			If parameter.defaultValue Then AddDiagnostic("BMX3347", "Function literal parameters cannot declare default values.", parameter.defaultValue.span)
			routine.parameterTypes[index] = targetType
			Local semanticParameter:TSemanticParameter = New TSemanticParameter
			semanticParameter.symbol = symbol
			semanticParameter.semanticType = targetType
			semanticParameter.passingMode = targetMode
			routine.parameters[index] = semanticParameter
		Next
		If literal.returnType Then
			Local writtenReturn:TSemanticType = ResolveType(literal.returnType, literalScope)
			If writtenReturn And callable.returnType And Not TGenericRoutineInference.SameType(writtenReturn, callable.returnType) Then AddDiagnostic("BMX3345", "Function literal return type '" + writtenReturn.DisplayName() + "' does not match target return type '" + callable.returnType.DisplayName() + "'.", literal.returnType.span)
		End If

		Local previousScope:TScope = activeFunctionLiteralScope
		Local previousManaged:Int = activeFunctionLiteralManaged
		Local previousCaptures:TSymbol[] = activeFunctionLiteralCaptures
		Local previousCapturesSelf:Int = activeFunctionLiteralCapturesSelf
		Local previousCapturedSelfType:TSemanticType = activeFunctionLiteralCapturedSelfType
		activeFunctionLiteralScope = literalScope
		activeFunctionLiteralManaged = closure <> Null
		activeFunctionLiteralCaptures = New TSymbol[0]
		activeFunctionLiteralCapturesSelf = False
		activeFunctionLiteralCapturedSelfType = Null
		BindSequence(literal.body.statements, literalScope)
		Local literalCaptures:TSymbol[] = activeFunctionLiteralCaptures
		Local literalCapturesSelf:Int = activeFunctionLiteralCapturesSelf
		Local literalCapturedSelfType:TSemanticType = activeFunctionLiteralCapturedSelfType
		activeFunctionLiteralScope = previousScope
		activeFunctionLiteralManaged = previousManaged
		activeFunctionLiteralCaptures = previousCaptures
		activeFunctionLiteralCapturesSelf = previousCapturesSelf
		activeFunctionLiteralCapturedSelfType = previousCapturedSelfType
		If previousScope Then
			' An inner Closure may depend on storage owned outside the enclosing
			' literal. Propagate that dependency so every escaping level retains
			' the environment chain; values declared by the enclosing literal
			' remain owned by that literal and need no upward propagation.
			For Local captured:TSymbol = EachIn literalCaptures
				If ScopeIsWithin(captured.containingScope, previousScope) Then Continue
				Local alreadyCaptured:Int
				For Local previousCapture:TSymbol = EachIn activeFunctionLiteralCaptures
					If previousCapture = captured Then alreadyCaptured = True; Exit
				Next
				If Not alreadyCaptured Then activeFunctionLiteralCaptures :+ [captured]
			Next
			If literalCapturesSelf Then
				activeFunctionLiteralCapturesSelf = True
				activeFunctionLiteralCapturedSelfType = literalCapturedSelfType
			End If
		End If

		Local literalType:TSemanticType = callable
		If closure Then literalType = closure
		model.expressionTypeMap.Insert(literal, literalType)
		Local bound:TBoundFunctionLiteralExpression = New TBoundFunctionLiteralExpression
		InitializeBound(bound, BOUND_EXPRESSION_FUNCTION_LITERAL, literal, literalType)
		bound.routine = routine
		bound.body = BuildBoundBlock(literal.body.statements, routine, literal.body)
		bound.captures = literalCaptures
		bound.capturesSelf = literalCapturesSelf
		bound.capturedSelfType = literalCapturedSelfType
		model.boundRoutineBodyMap.Insert(routine, bound.body)
		model.boundExpressionMap.Insert(literal, bound)
		Return literalType
	End Method

	Method BindCallArgumentTypes:TSemanticType[](callee:TExpressionSyntax, arguments:TExpressionSyntax[], scope:TScope)
		Local result:TSemanticType[] = New TSemanticType[arguments.length]
		Local targets:TSemanticType[]
		Local candidates:TSymbol[] = RoutineCandidates(callee, scope)
		If candidates.length = 1 And candidates[0].genericArity = 0 And candidates[0].parameterTypes.length = arguments.length Then targets = candidates[0].parameterTypes
		For Local index:Int = 0 Until arguments.length
			Local target:TSemanticType
			If targets And index < targets.length Then target = targets[index]
			result[index] = BindContextualExpression(arguments[index], scope, target)
		Next
		Return result
	End Method

	Method ValidateActiveCapture(expression:TExpressionSyntax)
		If Not activeFunctionLiteralScope Then Return
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If Not name Then Return
		Local lower:String = name.nameToken.text.ToLower()
		If lower = "super" Then
			' Super has no independent runtime value. Retain the current Self in
			' the managed environment; the bound Self expression's isSuper flag
			' continues to select static base dispatch during lowering.
			RegisterActiveSelfCapture(expression, "Self")
			Return
		End If
		If lower = "self" Then
			RegisterActiveSelfCapture(expression, name.nameToken.text)
			Return
		End If
		Local symbol:TSymbol = model.ReferencedSymbol(name)
		If Not symbol Then Return
		If symbol.kind = SYMBOL_ROUTINE And ActiveRoutineRequiresImplicitReceiver(symbol) Then RegisterActiveSelfCapture(expression, "Self"); Return
		If symbol.kind <> SYMBOL_LOCAL And symbol.kind <> SYMBOL_PARAMETER And symbol.kind <> SYMBOL_CATCH_PARAMETER And symbol.kind <> SYMBOL_FIELD Then Return
		If symbol.kind <> SYMBOL_FIELD And ScopeIsWithin(symbol.containingScope, activeFunctionLiteralScope) Then Return
		If symbol.kind = SYMBOL_FIELD Then RegisterActiveSelfCapture(expression, "Self"); Return
		If Not activeFunctionLiteralManaged Then ReportCapture(expression, symbol.name); Return
		If symbol.kind = SYMBOL_PARAMETER And symbol.parameterMode = PARAMETER_PASS_VAR Then ReportUnsupportedCapture(expression, symbol.name, "Var parameters cannot safely escape through a Closure"); Return
		If TStaticArraySemanticType(symbol.declaredType) Then ReportUnsupportedCapture(expression, symbol.name, "StaticArray values cannot yet be stored in a Closure environment"); Return
		For Local captured:TSymbol = EachIn activeFunctionLiteralCaptures
			If captured = symbol Then Return
		Next
		activeFunctionLiteralCaptures :+ [symbol]
	End Method

	Method ValidateImplicitRoutineCapture(callee:TExpressionSyntax, resolved:TResolvedCall)
		If Not activeFunctionLiteralScope Or Not TNameExpressionSyntax(callee) Or Not resolved Or Not resolved.routine Then Return
		If ActiveRoutineRequiresImplicitReceiver(resolved.routine) Then RegisterActiveSelfCapture(callee, "Self")
	End Method

	Method RegisterActiveSelfCapture(expression:TExpressionSyntax, name:String)
		If Not activeFunctionLiteralManaged Then ReportCapture(expression, name); Return
		Local enclosingRoutine:TSymbol = EnclosingInstanceRoutineSymbol(activeFunctionLiteralScope)
		If Not enclosingRoutine Or Not IsInstanceRoutine(enclosingRoutine) Then ReportUnsupportedCapture(expression, name, "no enclosing instance receiver is available"); Return
		Local selfType:TSemanticType = SelfType(activeFunctionLiteralScope)
		Local namedSelf:TNamedSemanticType = TNamedSemanticType(selfType)
		If Not namedSelf Or Not namedSelf.symbol Then ReportUnsupportedCapture(expression, name, "no enclosing instance receiver is available"); Return
		If namedSelf.symbol.kind = SYMBOL_STRUCT Then ReportUnsupportedCapture(expression, name, "Struct Self is a borrowed value and cannot safely escape"); Return
		If namedSelf.symbol.kind = SYMBOL_INTERFACE Then ReportUnsupportedCapture(expression, name, "Interface default-method Self capture is not available in this phase"); Return
		activeFunctionLiteralCapturesSelf = True
		activeFunctionLiteralCapturedSelfType = selfType
	End Method

	Method ActiveRoutineRequiresImplicitReceiver:Int(routine:TSymbol)
		If Not routine Or routine.kind <> SYMBOL_ROUTINE Or Not routine.containingScope Then Return False
		If IsInstanceRoutine(routine) Then Return True
		Local enclosing:TSymbol = EnclosingRoutineSymbol(activeFunctionLiteralScope)
		Return enclosing And IsInstanceRoutine(enclosing) And enclosing.containingScope = routine.containingScope
	End Method

	Method ReportCapture(expression:TExpressionSyntax, name:String)
		If captureReports.Contains(expression) Then Return
		captureReports.Insert(expression, expression)
		AddDiagnostic("BMX3346", "Thin Function literal cannot capture '" + name + "'; captured lexical state requires managed Closure support.", expression.span)
	End Method

	Method ReportUnsupportedCapture(expression:TExpressionSyntax, name:String, reason:String)
		If captureReports.Contains(expression) Then Return
		captureReports.Insert(expression, expression)
		If Not activeFunctionLiteralManaged Then
			AddDiagnostic("BMX3346", "Thin Function literal cannot capture '" + name + "'; captured lexical state requires managed Closure support.", expression.span)
		Else
			AddDiagnostic("BMX3346", "Managed Closure cannot capture '" + name + "' in this phase: " + reason + ".", expression.span)
		End If
	End Method

	Function ScopeIsWithin:Int(scope:TScope, ancestor:TScope)
		While scope
			If scope = ancestor Then Return True
			scope = scope.parent
		Wend
		Return False
	End Function

	Function EnclosingRoutineSymbol:TSymbol(scope:TScope)
		If scope Then scope = scope.parent
		While scope
			If scope.owner And scope.owner.kind = SYMBOL_ROUTINE Then Return scope.owner
			scope = scope.parent
		Wend
		Return Null
	End Function

	Function EnclosingInstanceRoutineSymbol:TSymbol(scope:TScope)
		If scope Then scope = scope.parent
		While scope
			If scope.owner And scope.owner.kind = SYMBOL_ROUTINE And IsInstanceRoutine(scope.owner) Then Return scope.owner
			scope = scope.parent
		Wend
		Return Null
	End Function

	Function ErrorType:TErrorSemanticType(written:String)
		Local result:TErrorSemanticType = New TErrorSemanticType
		result.kind = SEMANTIC_TYPE_ERROR
		result.writtenName = written
		Return result
	End Function

	Function QualifiedSuperReceiver:TNameExpressionSyntax(callee:TExpressionSyntax)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(callee)
		If Not member Then Return Null
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(member.expression)
		If name And name.qualifiedSuperType Then Return name
		Return Null
	End Function

	Method BuildBoundExpression:TBoundExpression(expression:TExpressionSyntax, semanticType:TSemanticType, scope:TScope)
		Local functionLiteral:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(expression)
		If functionLiteral Then Return model.BoundExpression(functionLiteral)
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If literal Then
			Local bound:TBoundLiteralExpression = New TBoundLiteralExpression
			InitializeBound(bound, BOUND_EXPRESSION_LITERAL, expression, semanticType)
			bound.token = literal.literalToken
			Return bound
		End If
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then
			If name.nameToken.text.ToLower() = "self" Then Return MakeSelfReference(expression, semanticType, False)
			If name.nameToken.text.ToLower() = "super" Then
				Local superReference:TBoundSelfExpression = MakeSelfReference(expression, semanticType, False, True)
				If name.qualifiedSuperType Then superReference.qualifiedSuperType = semanticType
				Return superReference
			End If
			Local symbol:TSymbol = model.ReferencedSymbol(name)
			If symbol And symbol.kind = SYMBOL_ROUTINE Then
				Local implicitCall:TResolvedCall = model.ResolvedCall(expression)
				If implicitCall Then Return BoundImplicitZeroArgumentCall(expression, symbol, implicitCall, scope)
				Local routineReference:TBoundRoutineReferenceExpression = MakeRoutineReference(expression, symbol, semanticType)
				If IsInstanceRoutine(symbol) Then routineReference.receiver = MakeSelfReference(expression, SelfType(scope), True)
				Local genericBinding:TGenericRoutineBinding = TGenericRoutineBinding(model.routineReferenceBindingMap.ValueForKey(expression))
				If genericBinding Then routineReference.typeArguments = genericBinding.typeArguments
				Return routineReference
			End If
			Local bound:TBoundSymbolExpression = New TBoundSymbolExpression
			InitializeBound(bound, BOUND_EXPRESSION_SYMBOL, expression, semanticType)
			bound.symbol = symbol
			If symbol And symbol.kind = SYMBOL_FIELD Then bound.receiver = MakeSelfReference(expression, SelfType(scope), True)
			Return bound
		End If
		Local call:TCallExpressionSyntax = TCallExpressionSyntax(expression)
		If call Then
			Local namedCastTarget:TSemanticType = model.NamedCastTarget(call)
			If namedCastTarget Then
				Local operand:TBoundExpression
				Local conversionKind:Int = CONVERSION_NONE
				If call.arguments.length Then
					operand = model.BoundExpression(call.arguments[0])
					Local conversion:TConversion = conversions.ClassifyExplicit(model.ExpressionType(call.arguments[0]), namedCastTarget)
					conversionKind = conversion.kind
				End If
				Return MakeConversion(operand, expression, namedCastTarget, conversionKind, False)
			End If
			Local bound:TBoundCallExpression = New TBoundCallExpression
			InitializeBound(bound, BOUND_EXPRESSION_CALL, expression, semanticType)
			bound.resolvedCall = model.ResolvedCall(call)
			bound.callee = model.BoundExpression(call.callee)
			If Not bound.callee And bound.resolvedCall And bound.resolvedCall.routine Then
				bound.callee = MakeRoutineReference(call.callee, bound.resolvedCall.routine, CallableFromRoutine(bound.resolvedCall.routine))
				model.boundExpressionMap.Insert(call.callee, bound.callee)
			End If
			bound.receiver = BoundCallReceiver(call.callee, bound.resolvedCall, scope)
			Local memberCallee:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(call.callee)
			If memberCallee Then bound.staticReceiverType = GenericTypeQualifier(memberCallee.expression, scope)
			bound.arguments = BoundArguments(call.arguments, bound.resolvedCall)
			Return bound
		End If
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then
			Local memberSymbol:TSymbol = model.ReferencedSymbol(member)
			If memberSymbol And memberSymbol.kind = SYMBOL_ROUTINE Then
				Local implicitCall:TResolvedCall = model.ResolvedCall(expression)
				If implicitCall Then Return BoundImplicitZeroArgumentCall(expression, memberSymbol, implicitCall, scope)
				Local routineReference:TBoundRoutineReferenceExpression = MakeRoutineReference(expression, memberSymbol, semanticType)
				routineReference.staticReceiverType = GenericTypeQualifier(member.expression, scope)
				If IsInstanceRoutine(memberSymbol) Then routineReference.receiver = model.BoundExpression(member.expression)
				Local genericBinding:TGenericRoutineBinding = TGenericRoutineBinding(model.routineReferenceBindingMap.ValueForKey(expression))
				If genericBinding Then routineReference.typeArguments = genericBinding.typeArguments
				Return routineReference
			End If
			Local bound:TBoundMemberExpression = New TBoundMemberExpression
			InitializeBound(bound, BOUND_EXPRESSION_MEMBER, expression, semanticType)
			bound.receiver = model.BoundExpression(member.expression)
			bound.access = model.ResolvedMember(member)
			Return bound
		End If
		Local indexed:TIndexExpressionSyntax = TIndexExpressionSyntax(expression)
		If indexed Then
			Local bound:TBoundIndexExpression = New TBoundIndexExpression
			InitializeBound(bound, BOUND_EXPRESSION_INDEX, expression, semanticType)
			bound.receiver = model.BoundExpression(indexed.expression)
			bound.indexes = BoundExpressions(indexed.indexes)
			bound.access = model.ResolvedIndex(indexed)
			If bound.access And bound.access.accessKind <> INDEX_ACCESS_OPERATOR And bound.access.accessKind <> INDEX_ACCESS_RANGE_ARRAY And bound.access.accessKind <> INDEX_ACCESS_RANGE_STRING Then
				Local indexType:TSemanticType = model.BuiltinType("UInt")
				For Local index:Int = 0 Until Min(bound.indexes.length, indexed.indexes.length)
					If bound.indexes[index] And Not TConversionClassifier.IsIntegral(bound.indexes[index].semanticType) Then bound.indexes[index] = ApplyImplicitConversion(bound.indexes[index], indexed.indexes[index], indexType, True)
				Next
			End If
			Return bound
		End If
		Local slice:TSliceExpressionSyntax = TSliceExpressionSyntax(expression)
		If slice Then
			Local bound:TBoundSliceExpression = New TBoundSliceExpression
			InitializeBound(bound, BOUND_EXPRESSION_SLICE, expression, semanticType)
			bound.receiver = model.BoundExpression(slice.expression)
			bound.lowerBound = model.BoundExpression(slice.lowerBound)
			bound.upperBound = model.BoundExpression(slice.upperBound)
			bound.lowerFromEnd = slice.lowerFromEndToken <> Null
			bound.upperFromEnd = slice.upperFromEndToken <> Null
			Return bound
		End If
		Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(expression)
		If unary Then
			Local bound:TBoundUnaryExpression = New TBoundUnaryExpression
			InitializeBound(bound, BOUND_EXPRESSION_UNARY, expression, semanticType)
			bound.operatorText = unary.operatorToken.text
			bound.operand = model.BoundExpression(unary.operand)
			Local intrinsicOperand:TIntrinsicOperandBinding = model.IntrinsicOperand(unary)
			If intrinsicOperand Then
				bound.operandSemanticType = intrinsicOperand.semanticType
				bound.isTypeOperand = intrinsicOperand.isTypeOperand
			End If
			Local operation:String = unary.operatorToken.text.ToLower()
			Local conversion:TConversion
			If operation = "asc" Then conversion = conversions.ClassifyExpression(unary.operand, model.ExpressionType(unary.operand), model.BuiltinType("String"))
			If operation = "chr" Then conversion = conversions.ClassifyAssignmentExpression(unary.operand, model.ExpressionType(unary.operand), model.BuiltinType("Int"))
			If operation = "stackalloc" Then conversion = conversions.ClassifyAssignmentExpression(unary.operand, model.ExpressionType(unary.operand), model.BuiltinType("Size_T"))
			If conversion And conversion.Exists() And conversion.kind <> CONVERSION_IDENTITY And conversion.kind <> CONVERSION_ERROR Then
				Local target:TSemanticType = model.BuiltinType("String")
				If operation = "chr" Then target = model.BuiltinType("Int")
				If operation = "stackalloc" Then target = model.BuiltinType("Size_T")
				bound.operand = MakeConversion(bound.operand, unary.operand, target, conversion.kind, True)
			End If
			bound.resolvedCall = model.ResolvedCall(unary)
			Return bound
		End If
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
		If binary Then
			Local bound:TBoundBinaryExpression = New TBoundBinaryExpression
			InitializeBound(bound, BOUND_EXPRESSION_BINARY, expression, semanticType)
			bound.operatorText = binary.operatorToken.text
			bound.left = model.BoundExpression(binary.left)
			bound.right = model.BoundExpression(binary.right)
			bound.resolvedCall = model.ResolvedCall(binary)
			Return bound
		End If
		Local creation:TNewExpressionSyntax = TNewExpressionSyntax(expression)
		If creation Then
			Local bound:TBoundNewExpression = New TBoundNewExpression
			InitializeBound(bound, BOUND_EXPRESSION_NEW, expression, semanticType)
			bound.createdType = model.TypeOf(creation.createdType)
			If creation.instanceExpression Then bound.instanceExpression = model.BoundExpression(creation.instanceExpression)
			bound.resolvedConstructor = model.ResolvedCall(creation)
			bound.arguments = BoundArguments(creation.arguments, bound.resolvedConstructor)
			bound.dimensions = BoundExpressions(creation.dimensions)
			bound.dimensionRanks = creation.dimensionRanks
			Return bound
		End If
		Local arrayLiteral:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(expression)
		If arrayLiteral Then
			Local bound:TBoundArrayLiteralExpression = New TBoundArrayLiteralExpression
			InitializeBound(bound, BOUND_EXPRESSION_ARRAY_LITERAL, expression, semanticType)
			bound.elements = BoundExpressions(arrayLiteral.elements)
			Return bound
		End If
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parenthesized Then
			Local bound:TBoundPassthroughExpression = New TBoundPassthroughExpression
			InitializeBound(bound, BOUND_EXPRESSION_PASSTHROUGH, expression, semanticType)
			bound.operand = model.BoundExpression(parenthesized.expression)
			Return bound
		End If
		Local ascription:TTypeAscriptionExpressionSyntax = TTypeAscriptionExpressionSyntax(expression)
		If ascription Then
			Local conversion:TConversion = conversions.ClassifyExpression(ascription.expression, model.ExpressionType(ascription.expression), semanticType)
			Return MakeConversion(model.BoundExpression(ascription.expression), expression, semanticType, conversion.kind, False)
		End If
		Local cast:TCastExpressionSyntax = TCastExpressionSyntax(expression)
		If cast Then
			Local conversion:TConversion = conversions.ClassifyExplicit(model.ExpressionType(cast.expression), semanticType)
			Return MakeConversion(model.BoundExpression(cast.expression), expression, semanticType, conversion.kind, False)
		End If
		Local errorExpression:TBoundErrorExpression = New TBoundErrorExpression
		InitializeBound(errorExpression, BOUND_EXPRESSION_ERROR, expression, semanticType)
		Return errorExpression
	End Method

	Method BindDynamicNewInstance:TSemanticType(creation:TNewExpressionSyntax, scope:TScope)
		If Not creation Or Not creation.createdType Then Return Null
		Local reference:TTypeReferenceSyntax = creation.createdType
		If reference.markerToken Or reference.nameTokens.length <> 1 Or reference.genericArguments.length Or reference.pointerTokens.length Or reference.arrayRanks.length Then Return Null
		Local nameToken:TSyntaxToken = reference.nameTokens[0]
		Local symbols:TSymbol[] = Lookup(scope, nameToken.text, creation)
		For Local symbol:TSymbol = EachIn symbols
			If symbol.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then Return Null
		Next
		For Local symbol:TSymbol = EachIn symbols
			If symbol.NamespaceKind() <> SYMBOL_NAMESPACE_VALUE Or Not TInheritanceValidator.IsObjectReference(symbol.declaredType) Then Continue
			Local name:TNameExpressionSyntax = New TNameExpressionSyntax
			name.kind = SYNTAX_NAME_EXPRESSION
			name.nameToken = nameToken
			name.span = nameToken.span
			creation.instanceExpression = name
			Local instanceType:TSemanticType = BindExpression(name, scope)
			model.typeMap.Insert(reference, instanceType)
			diagnostics.AddLast(TDiagnostic.Create("BMX3410", "Use of New <Object instance> is deprecated, and support will be removed in a future update.", DIAGNOSTIC_WARNING, creation.span, CurrentSourcePath()))
			Return instanceType
		Next
		Return Null
	End Method

	Method BoundCallReceiver:TBoundExpression(callee:TExpressionSyntax, resolved:TResolvedCall, scope:TScope)
		If Not resolved Then Return Null
		' Indirect callable and managed Closure calls deliberately have no
		' resolved declaration routine and therefore no dispatch receiver.
		If Not resolved.routine Then Return Null
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(callee)
		If member Then
			Local receiver:TBoundExpression = model.BoundExpression(member.expression)
			If IsInstanceRoutine(resolved.routine) Then Return receiver
			' Within a Type Function, Self names the enclosing Type rather than a
			' runtime object. Keep Self-qualified Type Function calls static; an
			' instance Method still has an object-valued Self and may dispatch the
			' same call through that object's class table.
			If TBoundSelfExpression(receiver) And Not IsInstanceRoutine(EnclosingRoutine(scope)) Then Return Null
			' A Type name selects a Type Function statically. An object-valued
			' qualifier retains the receiver so the compiler can select the Type
			' Function from its dynamic class table, matching production bcc.
			Local symbolReceiver:TBoundSymbolExpression = TBoundSymbolExpression(receiver)
			If symbolReceiver And symbolReceiver.symbol And symbolReceiver.symbol.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then Return Null
			If receiver And TInheritanceValidator.IsObjectReference(receiver.semanticType) Then Return receiver
			Return Null
		End If
		If Not IsInstanceRoutine(resolved.routine) Then
			' Production bcc dispatches an unqualified Type Function through the
			' current object when it is called from a Method declared by the same
			' Type. This lets an inherited Method reach a derived replacement of
			' that Type Function while calls from Type Functions remain static.
			Local enclosing:TSymbol = EnclosingRoutine(scope)
			If enclosing And IsInstanceRoutine(enclosing) And enclosing.containingScope = resolved.routine.containingScope Then
				Local selfType:TSemanticType = SelfType(scope)
				If TInheritanceValidator.IsObjectReference(selfType) Then Return MakeSelfReference(callee, selfType, True)
			End If
			Return Null
		End If
		Local semanticType:TSemanticType
		If scope Then semanticType = SelfType(scope)
		If Not semanticType And resolved.routine.containingScope And resolved.routine.containingScope.owner Then semanticType = resolved.routine.containingScope.owner.declaredType
		Return MakeSelfReference(callee, semanticType, True)
	End Method

	Method BoundImplicitZeroArgumentCall:TBoundCallExpression(expression:TExpressionSyntax, symbol:TSymbol, resolved:TResolvedCall, scope:TScope)
		Local bound:TBoundCallExpression = New TBoundCallExpression
		InitializeBound(bound, BOUND_EXPRESSION_CALL, expression, resolved.returnType)
		bound.resolvedCall = resolved
		bound.callee = MakeRoutineReference(expression, symbol, CallableFromRoutine(symbol))
		bound.receiver = BoundCallReceiver(expression, resolved, scope)
		bound.arguments = New TBoundExpression[0]
		Return bound
	End Method

	Function MakeSelfReference:TBoundSelfExpression(syntax:TExpressionSyntax, semanticType:TSemanticType, implicitReceiver:Int, isSuper:Int = False)
		Local bound:TBoundSelfExpression = New TBoundSelfExpression
		InitializeBound(bound, BOUND_EXPRESSION_SELF, syntax, semanticType)
		bound.implicitReceiver = implicitReceiver
		bound.isSynthetic = implicitReceiver
		bound.isSuper = isSuper
		Return bound
	End Function

	Method ResolveNamedCastTarget:TSemanticType(call:TCallExpressionSyntax, scope:TScope)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(call.callee)
		If Not name Then Return Null
		For Local symbol:TSymbol = EachIn Lookup(scope, name.nameToken.text, name)
			If symbol.NamespaceKind() <> SYMBOL_NAMESPACE_TYPE Then Continue
			model.referencedSymbolMap.Insert(name, symbol)
			If Not call.typeArguments.length Then Return symbol.declaredType
			Local namedType:TNamedSemanticType = TNamedSemanticType(symbol.declaredType)
			If Not namedType Then Return symbol.declaredType
			Local result:TNamedSemanticType = New TNamedSemanticType
			result.kind = SEMANTIC_TYPE_NAMED
			result.symbol = symbol
			result.typeArguments = New TSemanticType[call.typeArguments.length]
			For Local index:Int = 0 Until call.typeArguments.length
				result.typeArguments[index] = ResolveType(call.typeArguments[index], scope)
			Next
			Return result
		Next
		Return Null
	End Method

	Function InitializeBound(bound:TBoundExpression, boundKind:Int, syntax:TExpressionSyntax, semanticType:TSemanticType)
		bound.boundKind = boundKind
		bound.syntax = syntax
		bound.semanticType = semanticType
	End Function

	Function MakeRoutineReference:TBoundRoutineReferenceExpression(syntax:TExpressionSyntax, routine:TSymbol, semanticType:TSemanticType)
		Local bound:TBoundRoutineReferenceExpression = New TBoundRoutineReferenceExpression
		InitializeBound(bound, BOUND_EXPRESSION_ROUTINE_REFERENCE, syntax, semanticType)
		bound.routine = routine
		Return bound
	End Function

	Function MakeConversion:TBoundConversionExpression(operand:TBoundExpression, syntax:TExpressionSyntax, semanticType:TSemanticType, conversionKind:Int, implicitConversion:Int)
		Local bound:TBoundConversionExpression = New TBoundConversionExpression
		InitializeBound(bound, BOUND_EXPRESSION_CONVERSION, syntax, semanticType)
		bound.operand = operand
		bound.conversionKind = conversionKind
		bound.implicitConversion = implicitConversion
		bound.isSynthetic = implicitConversion
		Return bound
	End Function

	Method BoundExpressions:TBoundExpression[](expressions:TExpressionSyntax[])
		Local result:TBoundExpression[] = New TBoundExpression[expressions.length]
		For Local index:Int = 0 Until expressions.length
			If expressions[index] Then result[index] = model.BoundExpression(expressions[index])
		Next
		Return result
	End Method

	Method BoundArguments:TBoundExpression[](arguments:TExpressionSyntax[], resolved:TResolvedCall)
		Local result:TBoundExpression[] = New TBoundExpression[arguments.length]
		For Local index:Int = 0 Until arguments.length
			If Not arguments[index] Then Continue
			If TOmittedArgumentExpressionSyntax(arguments[index]) Then
				Local omitted:TBoundOmittedArgumentExpression = New TBoundOmittedArgumentExpression
				Local parameterType:TSemanticType
				If resolved And index < resolved.parameterTypes.length Then parameterType = resolved.parameterTypes[index]
				InitializeBound(omitted, BOUND_EXPRESSION_OMITTED_ARGUMENT, arguments[index], parameterType)
				If resolved And resolved.routine And index < resolved.routine.parameters.length Then omitted.parameter = resolved.routine.parameters[index]
				result[index] = omitted
				Continue
			End If
			Local bound:TBoundExpression = model.BoundExpression(arguments[index])
			If resolved And index < resolved.parameterTypes.length Then
				Local isVar:Int = resolved.routine And index < resolved.routine.parameters.length And resolved.routine.parameters[index].passingMode = PARAMETER_PASS_VAR
				If isVar Then
					If PointerSuppliesVar(bound.semanticType, resolved.parameterTypes[index]) Then
						bound = MakeConversion(bound, arguments[index], resolved.parameterTypes[index], CONVERSION_POINTER_TO_VAR_REFERENCE, True)
					Else
						Local conversion:TConversion = conversions.ClassifyExpression(arguments[index], bound.semanticType, resolved.parameterTypes[index])
						If conversion.kind = CONVERSION_REFERENCE Then bound = MakeConversion(bound, arguments[index], resolved.parameterTypes[index], CONVERSION_VAR_REFERENCE, True)
					End If
				Else
					bound = ApplyImplicitConversion(bound, arguments[index], resolved.parameterTypes[index], False, True)
				End If
			End If
			result[index] = bound
		Next
		Return result
	End Method

	Method ApplyImplicitConversion:TBoundExpression(operand:TBoundExpression, syntax:TExpressionSyntax, required:TSemanticType, assignmentContext:Int = False, argumentContext:Int = False)
		If Not required Then Return operand
		If Not operand Then
			Local emptyArray:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(syntax)
			Local requiredArray:TArraySemanticType = TArraySemanticType(required)
			If emptyArray And Not emptyArray.elements.length And requiredArray And requiredArray.rank = 1 Then
				Local contextualArray:TBoundArrayLiteralExpression = New TBoundArrayLiteralExpression
				InitializeBound(contextualArray, BOUND_EXPRESSION_ARRAY_LITERAL, syntax, required)
				contextualArray.elements = New TBoundExpression[0]
				contextualArray.contextualElementType = requiredArray.elementType
				contextualArray.conversionKind = CONVERSION_ARRAY_LITERAL
				model.expressionTypeMap.Insert(syntax, required)
				model.boundExpressionMap.Insert(syntax, contextualArray)
				Return contextualArray
			End If
			Return operand
		End If
		Local conversion:TConversion
		If assignmentContext Then
			conversion = conversions.ClassifyAssignmentExpression(syntax, operand.semanticType, required)
		Else If argumentContext Then
			conversion = conversions.ClassifyArgumentExpression(syntax, operand.semanticType, required)
		Else
			conversion = conversions.ClassifyExpression(syntax, operand.semanticType, required)
		End If
		If Not conversion.Exists() Or conversion.kind = CONVERSION_ERROR Then Return operand
		Local boundArray:TBoundArrayLiteralExpression = TBoundArrayLiteralExpression(operand)
		Local arraySyntax:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(syntax)
		Local requiredArray:TArraySemanticType = TArraySemanticType(required)
		If boundArray And arraySyntax And requiredArray And (conversion.kind = CONVERSION_ARRAY_LITERAL Or conversion.kind = CONVERSION_IDENTITY Or conversion.kind = CONVERSION_REFERENCE) Then
			' Array literals need element context even when their inferred type already
			' matches the target or can be reference-converted to it. In particular, Null in a
			' callable or managed-reference literal must become the element type's
			' default, and a mixed [Derived, Object] literal passed to Object[] must
			' use Object cells rather than a Derived compound initializer.
			If boundArray.elements.length = arraySyntax.elements.length Then
				For Local index:Int = 0 Until Min(boundArray.elements.length, arraySyntax.elements.length)
					boundArray.elements[index] = ApplyImplicitConversion(boundArray.elements[index], arraySyntax.elements[index], requiredArray.elementType, assignmentContext, argumentContext)
				Next
				boundArray.semanticType = required
				boundArray.contextualElementType = requiredArray.elementType
				boundArray.conversionKind = conversion.kind
				Return boundArray
			End If
		End If
		If conversion.kind = CONVERSION_IDENTITY Then Return operand
		If conversion.kind = CONVERSION_CONTEXTUAL_NUMERIC_EXPRESSION Then
			Return ApplyContextualNumericConversion(operand, syntax, required)
		End If
		Return MakeConversion(operand, syntax, required, conversion.kind, True)
	End Method

	Method ApplyContextualNumericConversion:TBoundExpression(operand:TBoundExpression, syntax:TExpressionSyntax, required:TSemanticType)
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(syntax)
		Local passthrough:TBoundPassthroughExpression = TBoundPassthroughExpression(operand)
		If parenthesized And passthrough Then
			passthrough.operand = ApplyImplicitConversion(passthrough.operand, parenthesized.expression, required)
			passthrough.semanticType = required
			Return passthrough
		End If
		Local binary:TBoundBinaryExpression = TBoundBinaryExpression(operand)
		Local binarySyntax:TBinaryExpressionSyntax = TBinaryExpressionSyntax(syntax)
		If binary And binarySyntax Then
			binary.left = ApplyImplicitConversion(binary.left, binarySyntax.left, required)
			binary.right = ApplyImplicitConversion(binary.right, binarySyntax.right, required)
			binary.semanticType = required
			Return binary
		End If
		Return MakeConversion(operand, syntax, required, CONVERSION_CONTEXTUAL_NUMERIC_EXPRESSION, True)
	End Method

	Method BindMember:TSemanticType(member:TMemberAccessExpressionSyntax, scope:TScope)
		Local selectedScope:TScope = StaticMemberScope(member.expression, scope)
		Local staticReceiver:TSemanticType = GenericTypeQualifier(member.expression, scope)
		Local receiver:TSemanticType
		Local lookupReceiver:TSemanticType
		Local implicitPointerDereference:Int
		Local symbols:TSymbol[]
		If Not selectedScope Then
			receiver = BindExpression(member.expression, scope)
			lookupReceiver = MemberLookupReceiver(receiver)
			implicitPointerDereference = lookupReceiver <> receiver
			symbols = MemberSymbols(lookupReceiver, member.nameToken.text)
		Else
			symbols = StaticMemberSymbols(selectedScope, member.nameToken.text)
		End If
		Local declaredSymbols:TSymbol[] = symbols
		symbols = AccessibleSymbols(declaredSymbols, scope)
		If symbols.length = 0 And ReportInaccessibleMember(member, declaredSymbols, scope) Then Return Null
		If member.typeArguments.length Then
			Return BindSpecializedRoutineReference(member, member.nameToken.text, member.typeArguments, FilterRoutines(symbols), ReceiverSubstitutions(member, scope), receiver, scope)
		End If
		For Local symbol:TSymbol = EachIn symbols
			If symbol.NamespaceKind() = SYMBOL_NAMESPACE_VALUE Then
				model.referencedSymbolMap.Insert(member, symbol)
				Local declaringReceiver:TSemanticType = MemberDeclaringType(lookupReceiver, symbol)
				If Not declaringReceiver And staticReceiver Then declaringReceiver = staticReceiver
				Local resolvedMember:TResolvedMemberAccess = New TResolvedMemberAccess
				resolvedMember.member = symbol
				resolvedMember.receiverType = receiver
				resolvedMember.lookupType = lookupReceiver
				resolvedMember.implicitPointerDereference = implicitPointerDereference
				model.resolvedMemberMap.Insert(member, resolvedMember)
				Return TGenericRoutineInference.Substitute(symbol.declaredType, TypeSubstitutions(declaringReceiver))
			End If
		Next
		Local routines:TSymbol[] = FilterRoutines(symbols)
		If routines.length = 1 Then
			model.referencedSymbolMap.Insert(member, routines[0])
			Local declaringReceiver:TSemanticType = MemberDeclaringType(lookupReceiver, routines[0])
			If Not declaringReceiver And staticReceiver Then declaringReceiver = staticReceiver
			Local callable:TCallableSemanticType = TCallableSemanticType(TGenericRoutineInference.Substitute(CallableFromRoutine(routines[0]), TypeSubstitutions(declaringReceiver)))
			If IsInstanceRoutine(routines[0]) Then
				If Not SupportsBoundMethodReceiver(receiver) Then
					AddDiagnostic("BMX3348", "Bound Method references currently support Type and Interface receivers; Struct receiver capture semantics are not yet defined.", member.span)
					Return ErrorType(routines[0].name)
				End If
				Return ManagedRoutineClosure(callable, routines[0])
			End If
			Return callable
		End If
		AddDiagnostic("BMX3301", "Member '" + member.nameToken.text + "' could not be resolved.", member.nameToken.span)
		Return Null
	End Method

	Method BindSpecializedRoutineReference:TSemanticType(reference:TExpressionSyntax, referenceName:String, explicitSyntax:TTypeReferenceSyntax[], candidates:TSymbol[], containingSubstitutions:TMap, receiverType:TSemanticType, scope:TScope)
		Local explicitTypes:TSemanticType[] = New TSemanticType[explicitSyntax.length]
		For Local index:Int = 0 Until explicitSyntax.length
			explicitTypes[index] = ResolveType(explicitSyntax[index], scope)
		Next
		Local applicable:TList = New TList
		Local bestTier:Int = -1
		Local hasTypeMemberCandidate:Int
		If TNameExpressionSyntax(reference) Then
			For Local routine:TSymbol = EachIn candidates
				If RoutineOwnerType(routine) Then hasTypeMemberCandidate = True; Exit
			Next
		End If
		For Local routine:TSymbol = EachIn candidates
			If routine.genericArity <> explicitTypes.length Then Continue
			Local substitutions:TMap = containingSubstitutions
			Local declaringReceiver:TSemanticType = MemberDeclaringType(receiverType, routine)
			If declaringReceiver Then substitutions = TypeSubstitutions(declaringReceiver)
			Local parameterTypes:TSemanticType[] = SubstituteTypes(routine.parameterTypes, substitutions)
			Local returnType:TSemanticType = TGenericRoutineInference.Substitute(routine.declaredType, substitutions)
			Local binding:TGenericRoutineBinding = TGenericRoutineInference.Infer(routine, New TSemanticType[0], explicitTypes, parameterTypes, returnType)
			If binding.success And ConstraintsSatisfied(binding, substitutions) Then
				Local tier:Int = RoutineScopeTier(routine, hasTypeMemberCandidate)
				If bestTier < 0 Or tier < bestTier Then applicable = New TList; bestTier = tier
				If tier = bestTier Then applicable.AddLast(binding)
			End If
		Next
		If applicable.Count() = 0 Then
			AddDiagnostic("BMX3341", "Generic routine reference '" + referenceName + "' has no specialization applicable to the supplied type arguments.", reference.span)
			Return ErrorType(referenceName)
		End If
		If applicable.Count() > 1 Then
			AddDiagnostic("BMX3342", "Generic routine reference '" + referenceName + "' is ambiguous between matching overloads.", reference.span)
			Return ErrorType(referenceName)
		End If
		Local binding:TGenericRoutineBinding = TGenericRoutineBinding(applicable.First())
		model.referencedSymbolMap.Insert(reference, binding.routine)
		model.routineReferenceBindingMap.Insert(reference, binding)
		Local callable:TCallableSemanticType = CallableFromRoutine(binding.routine)
		callable.parameterTypes = binding.parameterTypes
		callable.returnType = binding.returnType
		If IsInstanceRoutine(binding.routine) Then
			If Not SupportsBoundMethodReceiver(receiverType) Then
				AddDiagnostic("BMX3348", "Bound Method references currently support Type and Interface receivers; Struct receiver capture semantics are not yet defined.", reference.span)
				Return ErrorType(binding.routine.name)
			End If
			Return ManagedRoutineClosure(callable, binding.routine)
		End If
		Return callable
	End Method

	Function SupportsBoundMethodReceiver:Int(receiver:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(receiver)
		Return named And named.symbol And (named.symbol.kind = SYMBOL_TYPE Or named.symbol.kind = SYMBOL_INTERFACE)
	End Function

	Function ManagedRoutineClosure:TClosureSemanticType(callable:TCallableSemanticType, routine:TSymbol)
		If Not callable Then Return Null
		Local closure:TClosureSemanticType = New TClosureSemanticType
		closure.kind = SEMANTIC_TYPE_CLOSURE
		closure.signature = callable
		closure.parameterNames = New String[callable.parameterTypes.length]
		For Local index:Int = 0 Until closure.parameterNames.length
			If routine And index < routine.parameters.length And routine.parameters[index] And routine.parameters[index].symbol Then
				closure.parameterNames[index] = routine.parameters[index].symbol.name
			Else
				closure.parameterNames[index] = "arg" + index
			End If
		Next
		Return closure
	End Function

	Method ResolveCall:TResolvedCall(callSyntax:TSyntaxNode, callee:TExpressionSyntax, arguments:TExpressionSyntax[], argumentTypes:TSemanticType[], explicitSyntax:TTypeReferenceSyntax[], scope:TScope)
		Local typedCallee:TTypeAscriptionExpressionSyntax = TTypeAscriptionExpressionSyntax(callee)
		If typedCallee Then
			' The parser has already diagnosed arbitrary postfix ':Type' syntax.
			' Retain the node for recovery, but do not reinterpret it as a call
			' target or add a second diagnostic for the same source construct.
			Return Null
		End If
		Local candidates:TSymbol[] = RoutineCandidates(callee, scope)
		If candidates.length = 0 And explicitSyntax.length = 0 Then
			Local calleeType:TSemanticType = BindExpression(callee, scope)
			Local callable:TCallableSemanticType = TCallableSemanticType(calleeType)
			Local closure:TClosureSemanticType = TClosureSemanticType(calleeType)
			If closure Then callable = closure.signature
			If callable Then RecordStructuralCallSignature(callSyntax, callable, closure, arguments, argumentTypes)
			If callable And callable.parameterTypes.length = argumentTypes.length And Not HasOmittedArguments(arguments) And ConversionScore(Null, callable.parameterTypes, argumentTypes, arguments) >= 0 And CallableArgumentsSatisfyVar(callable, arguments) Then
				Local indirect:TResolvedCall = New TResolvedCall
				indirect.routine = callable.routine
				indirect.parameterTypes = callable.parameterTypes
				indirect.omittedArguments = OmittedArgumentFlags(arguments)
				indirect.returnType = callable.returnType
				model.resolvedCallMap.Insert(callSyntax, indirect)
				Return indirect
			End If
		End If
		' Binding a member-shaped callable can discover that the declaration exists
		' but is inaccessible. Do not follow that useful diagnostic with the
		' misleading claim that no overload exists.
		If inaccessibleMemberReports.Contains(callee) Then Return Null
		Local explicitTypes:TSemanticType[]
		If explicitSyntax.length Then
			explicitTypes = New TSemanticType[explicitSyntax.length]
			For Local index:Int = 0 Until explicitSyntax.length
				explicitTypes[index] = ResolveType(explicitSyntax[index], scope)
			Next
		End If
		Return ResolveCandidates(callSyntax, callee, CalleeName(callee), arguments, argumentTypes, explicitSyntax, explicitTypes, candidates, ReceiverSubstitutions(callee, scope), ReceiverType(callee, scope), scope)
	End Method

	Method ResolveConstructor:TResolvedCall(creation:TNewExpressionSyntax, createdType:TNamedSemanticType, argumentTypes:TSemanticType[], scope:TScope)
		If Not creation Or Not createdType Or Not createdType.symbol Or Not createdType.symbol.memberScope Then Return Null
		Local constructors:TSymbol[] = FilterRoutines(createdType.symbol.memberScope.LookupLocal("New"))
		If creation.arguments.length Then constructors = RoutineMemberSymbols(createdType, "New")
		Local hasExplicitDefault:Int
		Local accessible:TSymbol[]
		Local accessibleDefault:Int
		For Local constructor:TSymbol = EachIn constructors
			Local isDefault:Int = AritySatisfied(constructor, 0)
			If isDefault Then hasExplicitDefault = True
			Local constructorOwner:TSymbol = createdType.symbol
			If constructor.containingScope And constructor.containingScope.owner Then constructorOwner = constructor.containingScope.owner
			If Not ConstructorAccessible(constructor, constructorOwner, scope) Then Continue
			accessible :+ [constructor]
			If isDefault Then accessibleDefault = True
		Next
		' Other overloads never suppress BlitzMax's implicit public New().
		If creation.arguments.length = 0 And Not hasExplicitDefault Then Return Null
		If creation.arguments.length = 0 And hasExplicitDefault And Not accessibleDefault Then
			Local blockedVisibility:String = "accessible"
			For Local constructor:TSymbol = EachIn constructors
				If AritySatisfied(constructor, 0) Then blockedVisibility = TSymbolAccessibility.VisibilityName(constructor.visibility); Exit
			Next
			AddDiagnostic("BMX3317", "The default constructor for '" + createdType.DisplayName() + "' is " + blockedVisibility + " and cannot be called from this scope.", creation.createdType.span)
			Return Null
		End If
		Return ResolveCandidates(creation, creation, createdType.DisplayName() + ".New", creation.arguments, argumentTypes, New TTypeReferenceSyntax[0], Null, accessible, TypeSubstitutions(createdType), createdType, scope)
	End Method

	Method ConstructorAccessible:Int(constructor:TSymbol, owner:TSymbol, scope:TScope)
		Return TSymbolAccessibility.IsAccessible(constructor, scope, model, owner)
	End Method

	Method ResolveOperator:TResolvedCall(callSyntax:TSyntaxNode, referenceSyntax:TSyntaxNode, operatorName:String, receiverType:TSemanticType, arguments:TExpressionSyntax[], argumentTypes:TSemanticType[], scope:TScope)
		Local candidates:TSymbol[] = AccessibleSymbols(RoutineMemberSymbols(receiverType, operatorName), scope)
		If candidates.length = 0 Then Return Null
		Return ResolveCandidates(callSyntax, referenceSyntax, operatorName, arguments, argumentTypes, New TTypeReferenceSyntax[0], Null, candidates, TypeSubstitutions(receiverType), receiverType, scope, referenceSyntax <> indexSetterTarget)
	End Method

	Method ResolveCandidates:TResolvedCall(callSyntax:TSyntaxNode, referenceSyntax:TSyntaxNode, callName:String, arguments:TExpressionSyntax[], argumentTypes:TSemanticType[], explicitSyntax:TTypeReferenceSyntax[], explicitTypes:TSemanticType[], candidates:TSymbol[], containingSubstitutions:TMap, receiverType:TSemanticType, scope:TScope, reportFailure:Int = True)
		Local applicable:TList = New TList
		Local signatures:TCallSignatureSet = New TCallSignatureSet
		Local hasTypeMemberCandidate:Int
		If TNameExpressionSyntax(referenceSyntax) Then
			For Local routine:TSymbol = EachIn candidates
				If RoutineOwnerType(routine) Then hasTypeMemberCandidate = True; Exit
			Next
		End If
		For Local routine:TSymbol = EachIn candidates
			Local candidateSubstitutions:TMap = containingSubstitutions
			Local declaringReceiver:TSemanticType = MemberDeclaringType(receiverType, routine)
			If declaringReceiver Then candidateSubstitutions = TypeSubstitutions(declaringReceiver)
			Local candidate:TApplicableRoutine = New TApplicableRoutine
			candidate.routine = routine
			candidate.parameterTypes = SubstituteTypes(routine.parameterTypes, candidateSubstitutions)
			candidate.returnType = TGenericRoutineInference.Substitute(routine.declaredType, candidateSubstitutions)
			Local signature:TCallSignatureCandidate = New TCallSignatureCandidate
			signature.routine = routine
			signature.containingSubstitutions = candidateSubstitutions
			signature.parameterTypes = candidate.parameterTypes
			signature.returnType = candidate.returnType
			signatures.candidates :+ [signature]
			If Not ArgumentSlotsSatisfied(routine, arguments) Or Not ArgumentsSatisfyVar(routine, arguments) Then Continue
			If routine.genericArity > 0 Then
				candidate.binding = TGenericRoutineInference.Infer(routine, argumentTypes, explicitTypes, candidate.parameterTypes, candidate.returnType, OmittedArgumentFlags(arguments))
				If candidate.binding.success And ConstraintsSatisfied(candidate.binding, candidateSubstitutions) Then
					signature.parameterTypes = candidate.binding.parameterTypes
					signature.returnType = candidate.binding.returnType
					Local conversionRank:Int = ConversionScore(routine, candidate.binding.parameterTypes, argumentTypes, arguments)
					If conversionRank >= 0 Then
						signature.compatible = True
						signature.score = conversionRank
						candidate.rank = conversionRank * 10 + 1 + RoutineScopeTier(routine, hasTypeMemberCandidate)
						applicable.AddLast(candidate)
					End If
				End If
			Else If Not explicitSyntax.length Then
				Local conversionRank:Int = ConversionScore(routine, candidate.parameterTypes, argumentTypes, arguments)
				If conversionRank >= 0 Then
					signature.compatible = True
					signature.score = conversionRank
					candidate.rank = conversionRank * 10 + RoutineScopeTier(routine, hasTypeMemberCandidate)
					applicable.AddLast(candidate)
				End If
			End If
		Next
		RecordIncompleteSignatureCompatibility(signatures, arguments, argumentTypes, explicitSyntax, explicitTypes)
		model.callSignatureMap.Insert(callSyntax, signatures)
		If applicable.Count() = 0 Then
			Local deferred:TResolvedCall = ResolveDeferredGenericCall(callSyntax, referenceSyntax, arguments, argumentTypes, explicitSyntax, candidates, containingSubstitutions, receiverType)
			If deferred Then Return deferred
			If reportFailure And Not ReportUncalledRoutineArguments(arguments, candidates, containingSubstitutions, receiverType) Then
				AddDiagnostic("BMX3302", InapplicableCallMessage(callName, arguments, argumentTypes, candidates, containingSubstitutions, receiverType), callSyntax.span)
			End If
			Return Null
		End If
		Local best:TApplicableRoutine = BestApplicableCandidate(applicable, arguments, argumentTypes, receiverType)
		If Not best Then
			If reportFailure Then AddDiagnostic("BMX3303", AmbiguousCallMessage(callName, applicable), callSyntax.span)
			Return Null
		End If
		Local resolved:TResolvedCall = New TResolvedCall
		resolved.routine = best.routine
		resolved.omittedArguments = OmittedArgumentFlags(arguments)
		If best.binding Then
			resolved.typeArguments = best.binding.typeArguments
			resolved.parameterTypes = best.binding.parameterTypes
			resolved.returnType = best.binding.returnType
		Else
			resolved.parameterTypes = best.parameterTypes
			resolved.returnType = best.returnType
		End If
		SelectCallSignature(signatures, resolved)
		model.resolvedCallMap.Insert(callSyntax, resolved)
		model.referencedSymbolMap.Insert(referenceSyntax, best.routine)
		Local dispatchReceiver:TBoundExpression
		Local referenceExpression:TExpressionSyntax = TExpressionSyntax(referenceSyntax)
		If referenceExpression Then dispatchReceiver = BoundCallReceiver(referenceExpression, resolved, scope)
		ReportAbstractTypeFunctionCall(best.routine, callSyntax.span, dispatchReceiver)
		Return resolved
	End Method

	Method RecordIncompleteSignatureCompatibility(signatures:TCallSignatureSet, arguments:TExpressionSyntax[], argumentTypes:TSemanticType[], explicitSyntax:TTypeReferenceSyntax[], explicitTypes:TSemanticType[])
		If Not signatures Then Return
		For Local signature:TCallSignatureCandidate = EachIn signatures.candidates
			If signature.compatible Or Not signature.routine Then Continue
			If arguments.length > signature.parameterTypes.length Or Not ArgumentsSatisfyVar(signature.routine, arguments) Then Continue
			If explicitSyntax.length And signature.routine.genericArity <> explicitSyntax.length Then Continue
			If signature.routine.genericArity > 0 Then
				Local binding:TGenericRoutineBinding = TGenericRoutineInference.Infer(signature.routine, argumentTypes, explicitTypes, signature.parameterTypes, signature.returnType, OmittedArgumentFlags(arguments))
				If binding.success And ConstraintsSatisfied(binding, signature.containingSubstitutions) Then
					signature.parameterTypes = binding.parameterTypes
					signature.returnType = binding.returnType
				Else If arguments.length Then
					' Partial generic inference may be unable to close a type parameter
					' supplied only by a later argument. Retain the open signature.
					Continue
				End If
			Else If explicitSyntax.length Then
				Continue
			End If
			Local score:Int = ConversionScore(signature.routine, signature.parameterTypes, argumentTypes, arguments)
			If score >= 0 Then
				signature.compatible = True
				signature.score = score
			End If
		Next
	End Method

	Method SelectCallSignature(signatures:TCallSignatureSet, resolved:TResolvedCall)
		If Not signatures Or Not resolved Or Not resolved.routine Then Return
		For Local signature:TCallSignatureCandidate = EachIn signatures.candidates
			If signature.routine <> resolved.routine Then Continue
			signature.selected = True
			signature.compatible = True
			signature.parameterTypes = resolved.parameterTypes
			signature.returnType = resolved.returnType
			Return
		Next
	End Method

	Method RecordStructuralCallSignature(callSyntax:TSyntaxNode, callable:TCallableSemanticType, closure:TClosureSemanticType, arguments:TExpressionSyntax[], argumentTypes:TSemanticType[])
		If Not callSyntax Or Not callable Then Return
		Local signature:TCallSignatureCandidate = New TCallSignatureCandidate
		signature.routine = callable.routine
		signature.callable = callable
		signature.closure = closure
		signature.parameterTypes = callable.parameterTypes
		signature.returnType = callable.returnType
		If arguments.length <= callable.parameterTypes.length Then
			Local score:Int = ConversionScore(Null, callable.parameterTypes, argumentTypes, arguments)
			If score >= 0 Then
				signature.compatible = True
				signature.score = score
			End If
		End If
		Local signatures:TCallSignatureSet = New TCallSignatureSet
		signatures.candidates = [signature]
		model.callSignatureMap.Insert(callSyntax, signatures)
	End Method

	Function AmbiguousCallMessage:String(callName:String, applicable:TList)
		Local message:String = "Call '" + callName + "' is ambiguous between applicable overloads."
		If applicable And applicable.Count() Then
			message :+ "~nCandidates:"
			For Local candidate:TApplicableRoutine = EachIn applicable
				message :+ "~n  " + candidate.routine.QualifiedName() + "("
				For Local index:Int = 0 Until candidate.parameterTypes.length
					If index Then message :+ ", "
					If candidate.parameterTypes[index] Then message :+ candidate.parameterTypes[index].DisplayName() Else message :+ "<unresolved>"
					If index < candidate.routine.parameters.length And candidate.routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then message :+ " Var"
				Next
				message :+ ")"
			Next
		End If
		Return message
	End Function

	Function RoutineScopeTier:Int(routine:TSymbol, hasTypeMemberCandidate:Int)
		' An unqualified member name shadows the outer/global routine tier whenever
		' one of its overloads applies. If no member overload applies, the large
		' tier penalty is irrelevant and an applicable outer routine can win.
		If hasTypeMemberCandidate And Not RoutineOwnerType(routine) Then Return 1000000
		Return 0
	End Function

	Method ResolveDeferredGenericCall:TResolvedCall(callSyntax:TSyntaxNode, referenceSyntax:TSyntaxNode, arguments:TExpressionSyntax[], argumentTypes:TSemanticType[], explicitSyntax:TTypeReferenceSyntax[], candidates:TSymbol[], containingSubstitutions:TMap, receiverType:TSemanticType)
		If explicitSyntax.length Or Not ContainsOpenTypeParameter(argumentTypes) Then Return Null
		Local viable:TList = New TList
		Local commonReturn:TSemanticType
		For Local routine:TSymbol = EachIn candidates
			' Generic routine inference has its own substitution lifecycle. This
			' deferred set represents overload selection for ordinary routines.
			If routine.genericArity > 0 Or Not ArgumentSlotsSatisfied(routine, arguments) Or Not ArgumentsSatisfyVar(routine, arguments) Then Continue
			Local substitutions:TMap = containingSubstitutions
			Local declaringReceiver:TSemanticType = MemberDeclaringType(receiverType, routine)
			If declaringReceiver Then substitutions = TypeSubstitutions(declaringReceiver)
			Local parameters:TSemanticType[] = SubstituteTypes(routine.parameterTypes, substitutions)
			If Not DeferredArgumentsCompatible(parameters, argumentTypes, arguments) Then Continue
			Local returnType:TSemanticType = TGenericRoutineInference.Substitute(routine.declaredType, substitutions)
			If Not commonReturn Then
				commonReturn = returnType
			Else If Not TGenericRoutineInference.SameType(commonReturn, returnType) Then
				Return Null
			End If
			viable.AddLast(routine)
		Next
		If viable.Count() = 0 Or Not commonReturn Then Return Null
		Local resolved:TResolvedCall = New TResolvedCall
		resolved.isDeferred = True
		resolved.candidates = SymbolsFromList(viable)
		resolved.argumentTypes = argumentTypes[..]
		resolved.omittedArguments = OmittedArgumentFlags(arguments)
		resolved.returnType = commonReturn
		model.resolvedCallMap.Insert(callSyntax, resolved)
		Return resolved
	End Method

	Method DeferredArgumentsCompatible:Int(parameters:TSemanticType[], arguments:TSemanticType[], expressions:TExpressionSyntax[])
		If arguments.length > parameters.length Then Return False
		For Local index:Int = 0 Until arguments.length
			If index < expressions.length And TOmittedArgumentExpressionSyntax(expressions[index]) Then Continue
			If ContainsOpenTypeParameterType(arguments[index]) Then Continue
			Local expression:TExpressionSyntax
			If index < expressions.length Then expression = expressions[index]
			If Not conversions.ClassifyArgumentExpression(expression, arguments[index], parameters[index]).Exists() Then Return False
		Next
		Return True
	End Method

	Function ContainsOpenTypeParameter:Int(values:TSemanticType[])
		For Local value:TSemanticType = EachIn values
			If ContainsOpenTypeParameterType(value) Then Return True
		Next
		Return False
	End Function

	Function ContainsOpenTypeParameterType:Int(value:TSemanticType)
		If Not value Then Return False
		If TTypeParameterSemanticType(value) Then Return True
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then Return ContainsOpenTypeParameter(named.typeArguments)
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then Return ContainsOpenTypeParameterType(arrayType.elementType)
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If staticArrayType Then Return ContainsOpenTypeParameterType(staticArrayType.elementType)
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If pointer Then Return ContainsOpenTypeParameterType(pointer.elementType)
		Local callable:TCallableSemanticType = TCallableSemanticType(value)
		If callable Then
			If ContainsOpenTypeParameterType(callable.returnType) Then Return True
			Return ContainsOpenTypeParameter(callable.parameterTypes)
		End If
		Return False
	End Function

	Function SymbolsFromList:TSymbol[](values:TList)
		Local result:TSymbol[] = New TSymbol[values.Count()]
		Local index:Int
		For Local value:TSymbol = EachIn values
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Method InapplicableCallMessage:String(callName:String, arguments:TExpressionSyntax[], argumentTypes:TSemanticType[], candidates:TSymbol[], containingSubstitutions:TMap, receiverType:TSemanticType)
		Local message:String = "No applicable overload was found for call '" + callName + "'.~nArgument types: ("
		For Local index:Int = 0 Until argumentTypes.length
			If index Then message :+ ", "
			If index < arguments.length And TOmittedArgumentExpressionSyntax(arguments[index]) Then message :+ "<omitted>" Else If argumentTypes[index] Then message :+ argumentTypes[index].DisplayName() Else message :+ "<unresolved>"
		Next
		message :+ ")"
		If candidates.length Then
			message :+ "~nCandidates:"
			For Local routine:TSymbol = EachIn candidates
				Local substitutions:TMap = containingSubstitutions
				Local declaringReceiver:TSemanticType = MemberDeclaringType(receiverType, routine)
				If declaringReceiver Then substitutions = TypeSubstitutions(declaringReceiver)
				Local parameterTypes:TSemanticType[] = SubstituteTypes(routine.parameterTypes, substitutions)
				message :+ "~n  " + routine.QualifiedName() + "("
				For Local index:Int = 0 Until parameterTypes.length
					If index Then message :+ ", "
					If parameterTypes[index] Then message :+ parameterTypes[index].DisplayName() Else message :+ "<unresolved>"
					If index < routine.parameters.length And routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then message :+ " Var"
				Next
				message :+ ")"
			Next
		End If
		Return message
	End Method

	Method AritySatisfied:Int(routine:TSymbol, count:Int)
		Local signature:TRoutineSignatureSyntax = RoutineSignature(routine)
		If Not signature Then Return count = routine.parameterTypes.length
		If count > signature.parameters.length Then Return False
		For Local index:Int = count Until signature.parameters.length
			If Not signature.parameters[index].defaultValue Then Return False
		Next
		Return True
	End Method

	Method ArgumentSlotsSatisfied:Int(routine:TSymbol, arguments:TExpressionSyntax[])
		If Not AritySatisfied(routine, arguments.length) Then Return False
		Local signature:TRoutineSignatureSyntax = RoutineSignature(routine)
		If Not signature Then Return Not HasOmittedArguments(arguments)
		For Local index:Int = 0 Until Min(arguments.length, signature.parameters.length)
			If TOmittedArgumentExpressionSyntax(arguments[index]) And Not signature.parameters[index].defaultValue Then Return False
		Next
		Return True
	End Method

	Method ArgumentsSatisfyVar:Int(routine:TSymbol, arguments:TExpressionSyntax[])
		If Not routine Then Return True
		For Local index:Int = 0 Until Min(routine.parameters.length, arguments.length)
			If TOmittedArgumentExpressionSyntax(arguments[index]) Then Continue
			If routine.parameters[index].passingMode = PARAMETER_PASS_VAR And Not IsAddressable(arguments[index]) Then
				If Not PointerSuppliesVar(model.ExpressionType(arguments[index]), routine.parameterTypes[index]) Then Return False
			End If
		Next
		Return True
	End Method

	Method CallableArgumentsSatisfyVar:Int(callable:TCallableSemanticType, arguments:TExpressionSyntax[])
		For Local index:Int = 0 Until Min(callable.parameterModes.length, arguments.length)
			If TOmittedArgumentExpressionSyntax(arguments[index]) Then Continue
			If callable.parameterModes[index] = PARAMETER_PASS_VAR And Not IsAddressable(arguments[index]) Then Return False
		Next
		Return True
	End Method

	Method BestApplicableCandidate:TApplicableRoutine(applicable:TList, expressions:TExpressionSyntax[], argumentTypes:TSemanticType[], receiverType:TSemanticType = Null)
		Local minimumRank:Int = -1
		For Local candidate:TApplicableRoutine = EachIn applicable
			If minimumRank < 0 Or candidate.rank < minimumRank Then minimumRank = candidate.rank
		Next
		Local tied:TList = New TList
		For Local candidate:TApplicableRoutine = EachIn applicable
			If candidate.rank = minimumRank Then tied.AddLast(candidate)
		Next
		If tied.Count() = 1 Then Return TApplicableRoutine(tied.First())
		Local winner:TApplicableRoutine
		For Local candidate:TApplicableRoutine = EachIn tied
			Local betterThanAll:Int = True
			For Local other:TApplicableRoutine = EachIn tied
				If candidate = other Then Continue
				If Not BetterCandidate(candidate, other, expressions, argumentTypes) Then
					betterThanAll = False
					Exit
				End If
			Next
			If betterThanAll Then
				If winner Then Return Null
				winner = candidate
			End If
		Next
		If Not winner And InterfaceReceiver(receiverType) And CompatibleInterfaceSelectorCandidates(tied) Then Return TApplicableRoutine(tied.First())
		If Not winner And CompatibleExternalRedeclarations(tied) Then Return TApplicableRoutine(tied.First())
		Return winner
	End Method

	Method CompatibleExternalRedeclarations:Int(candidates:TList)
		If Not candidates Or candidates.Count() < 2 Then Return False
		Local first:TApplicableRoutine = TApplicableRoutine(candidates.First())
		If Not first Or Not first.routine Or Not first.routine.isExternal Then Return False
		Local firstParameters:TSemanticType[] = ApplicableParameterTypes(first)
		For Local candidate:TApplicableRoutine = EachIn candidates
			If Not candidate Or Not candidate.routine Or Not candidate.routine.isExternal Then Return False
			If candidate.routine.normalizedName <> first.routine.normalizedName Or candidate.routine.genericArity <> first.routine.genericArity Then Return False
			Local candidateParameters:TSemanticType[] = ApplicableParameterTypes(candidate)
			If candidateParameters.length <> firstParameters.length Then Return False
			For Local index:Int = 0 Until firstParameters.length
				If Not TGenericRoutineInference.SameType(firstParameters[index], candidateParameters[index]) Then Return False
				If ParameterMode(first.routine, index) <> ParameterMode(candidate.routine, index) Then Return False
			Next
			If Not TGenericRoutineInference.SameType(first.returnType, candidate.returnType) Then Return False
		Next
		Return True
	End Method

	Function InterfaceReceiver:Int(receiverType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(receiverType)
		Return named And named.symbol And named.symbol.kind = SYMBOL_INTERFACE
	End Function

	Method CompatibleInterfaceSelectorCandidates:Int(candidates:TList)
		If Not candidates Or candidates.Count() < 2 Then Return False
		Local first:TApplicableRoutine = TApplicableRoutine(candidates.First())
		Local firstParameters:TSemanticType[] = ApplicableParameterTypes(first)
		For Local candidate:TApplicableRoutine = EachIn candidates
			Local candidateParameters:TSemanticType[] = ApplicableParameterTypes(candidate)
			If candidateParameters.length <> firstParameters.length Then Return False
			For Local index:Int = 0 Until firstParameters.length
				If Not TGenericRoutineInference.SameType(firstParameters[index], candidateParameters[index]) Then Return False
				If ParameterMode(first.routine, index) <> ParameterMode(candidate.routine, index) Then Return False
			Next
			If TGenericRoutineInference.SameType(first.returnType, candidate.returnType) Then Continue
			Local firstToCandidate:TConversion = conversions.Classify(first.returnType, candidate.returnType)
			Local candidateToFirst:TConversion = conversions.Classify(candidate.returnType, first.returnType)
			If Not firstToCandidate.Exists() And Not candidateToFirst.Exists() Then Return False
		Next
		Return True
	End Method

	Method BetterCandidate:Int(first:TApplicableRoutine, second:TApplicableRoutine, expressions:TExpressionSyntax[], argumentTypes:TSemanticType[])
		Local firstParameters:TSemanticType[] = ApplicableParameterTypes(first)
		Local secondParameters:TSemanticType[] = ApplicableParameterTypes(second)
		Local firstBetter:Int
		Local secondBetter:Int
		For Local index:Int = 0 Until argumentTypes.length
			If index < expressions.length And TOmittedArgumentExpressionSyntax(expressions[index]) Then Continue
			Local firstConversion:TConversion = conversions.ClassifyArgumentExpression(expressions[index], argumentTypes[index], firstParameters[index])
			Local secondConversion:TConversion = conversions.ClassifyArgumentExpression(expressions[index], argumentTypes[index], secondParameters[index])
			If firstConversion.score < secondConversion.score Then
				firstBetter = True
			Else If secondConversion.score < firstConversion.score Then
				secondBetter = True
			Else
				Local targetPreference:Int = BetterConversionTarget(firstParameters[index], secondParameters[index])
				If targetPreference > 0 Then firstBetter = True
				If targetPreference < 0 Then secondBetter = True
			End If
			If firstBetter And secondBetter Then Return False
		Next
		If firstBetter Or secondBetter Then Return firstBetter And Not secondBetter
		' An override and its inherited declaration have identical parameter
		' conversions. Prefer the routine declared closest to the receiver; this
		' also resolves zero-argument overrides where there are no conversions by
		' which the ordinary overload rules could distinguish the candidates.
		Local firstOwner:TSemanticType = RoutineOwnerType(first.routine)
		Local secondOwner:TSemanticType = RoutineOwnerType(second.routine)
		If firstOwner And secondOwner And Not TGenericRoutineInference.SameType(firstOwner, secondOwner) Then
			Local firstDerived:Int = inheritanceValidator.IsSubtype(firstOwner, secondOwner, 0)
			Local secondDerived:Int = inheritanceValidator.IsSubtype(secondOwner, firstOwner, 0)
			Return firstDerived And Not secondDerived
		End If
		Return False
	End Method

	Function RoutineOwnerType:TSemanticType(routine:TSymbol)
		If Not routine Or Not routine.containingScope Or routine.containingScope.kind <> SCOPE_TYPE Or Not routine.containingScope.owner Then Return Null
		Return routine.containingScope.owner.declaredType
	End Function

	Method BetterConversionTarget:Int(first:TSemanticType, second:TSemanticType)
		If TGenericRoutineInference.SameType(first, second) Then Return 0
		Local firstToSecond:TConversion = conversions.Classify(first, second)
		Local secondToFirst:TConversion = conversions.Classify(second, first)
		If firstToSecond.Exists() And Not secondToFirst.Exists() Then Return 1
		If secondToFirst.Exists() And Not firstToSecond.Exists() Then Return -1
		Return 0
	End Method

	Function ApplicableParameterTypes:TSemanticType[](candidate:TApplicableRoutine)
		If candidate.binding Then Return candidate.binding.parameterTypes
		Return candidate.parameterTypes
	End Function

	Method ConversionScore:Int(routine:TSymbol, parameters:TSemanticType[], arguments:TSemanticType[], expressions:TExpressionSyntax[])
		If arguments.length > parameters.length Then Return -1
		Local result:Int
		Local narrowingCount:Int
		For Local index:Int = 0 Until arguments.length
			Local expression:TExpressionSyntax
			If index < expressions.length Then expression = expressions[index]
			If TOmittedArgumentExpressionSyntax(expression) Then Continue
			Local isVar:Int = routine And index < routine.parameters.length And routine.parameters[index].passingMode = PARAMETER_PASS_VAR
			If isVar And PointerSuppliesVar(arguments[index], parameters[index]) Then Continue
			Local conversion:TConversion = conversions.ClassifyArgumentExpression(expression, arguments[index], parameters[index])
			If Not conversion.Exists() Then Return -1
			If isVar Then
				' BlitzMax permits addressable reference storage to be supplied to a
				' Var parameter of a base reference type, notably TSomeType -> Object
				' Var. Numeric, pointer, Struct, and value conversions remain invalid.
				If conversion.kind <> CONVERSION_IDENTITY And conversion.kind <> CONVERSION_ERROR And conversion.kind <> CONVERSION_REFERENCE Then Return -1
			End If
			If conversion.kind = CONVERSION_NUMERIC_NARROWING Then narrowingCount :+ 1
			result :+ conversion.score
		Next
		' Numeric narrowing is the last-resort compatibility path for an overload
		' candidate. Prefer a candidate whose whole argument list uses standard
		' conversions even when several widening distances would otherwise sum to
		' the same or a larger score than one narrowing conversion.
		Return narrowingCount * 100000 + result
	End Method

	Function PointerSuppliesVar:Int(actual:TSemanticType, required:TSemanticType)
		Local pointer:TPointerSemanticType = TPointerSemanticType(actual)
		Return pointer And TGenericRoutineInference.SameType(pointer.elementType, required)
	End Function

	Method CheckConversion:Int(actual:TSemanticType, required:TSemanticType, span:TSourceSpan, context:String, expression:TExpressionSyntax = Null)
		If Not actual Or Not required Then Return False
		If BindImplicitZeroArgumentCall(expression, required, False) Then Return True
		Local conversion:TConversion = conversions.ClassifyExpression(expression, actual, required)
		If conversion.Exists() Then Return True
		If ReportUncalledRoutineReference(expression, required) Then Return False
		AddDiagnostic("BMX3310", "Type '" + actual.DisplayName() + "' cannot be implicitly converted to '" + required.DisplayName() + "' in " + context + ".", span)
		Return False
	End Method

	Method CheckAssignmentConversion:Int(actual:TSemanticType, required:TSemanticType, span:TSourceSpan, context:String, expression:TExpressionSyntax = Null)
		If Not actual Or Not required Then Return False
		If BindImplicitZeroArgumentCall(expression, required, True) Then Return True
		Local conversion:TConversion = conversions.ClassifyAssignmentExpression(expression, actual, required)
		If conversion.Exists() Then Return True
		If ReportUncalledRoutineReference(expression, required) Then Return False
		AddDiagnostic("BMX3310", "Type '" + actual.DisplayName() + "' cannot be implicitly converted to '" + required.DisplayName() + "' in " + context + ".", span)
		Return False
	End Method

	Method BindImplicitZeroArgumentCall:Int(expression:TExpressionSyntax, required:TSemanticType, assignmentContext:Int)
		If Not expression Or TCallableSemanticType(required) Or TClosureSemanticType(required) Or TTypeParameterSemanticType(required) Then Return False
		Local symbol:TSymbol
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then symbol = model.ReferencedSymbol(name)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then symbol = model.ReferencedSymbol(member)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or symbol.genericArity Or symbol.parameters.length Then Return False
		Local returnType:TSemanticType = symbol.declaredType
		If member Then
			Local receiverType:TSemanticType = model.ExpressionType(member.expression)
			Local declaringReceiver:TSemanticType = MemberDeclaringType(receiverType, symbol)
			If declaringReceiver Then returnType = TGenericRoutineInference.Substitute(returnType, TypeSubstitutions(declaringReceiver))
		End If
		Local conversion:TConversion
		If assignmentContext Then conversion = conversions.ClassifyAssignmentExpression(expression, returnType, required) Else conversion = conversions.ClassifyExpression(expression, returnType, required)
		If Not conversion.Exists() Then Return False
		Local resolved:TResolvedCall = New TResolvedCall
		resolved.routine = symbol
		resolved.returnType = returnType
		resolved.parameterTypes = New TSemanticType[0]
		resolved.omittedArguments = New Int[0]
		model.resolvedCallMap.Insert(expression, resolved)
		Local boundCall:TBoundCallExpression = BoundImplicitZeroArgumentCall(expression, symbol, resolved, model.ScopeFor(expression))
		ReportAbstractTypeFunctionCall(symbol, expression.span, boundCall.receiver)
		model.expressionTypeMap.Insert(expression, returnType)
		' BindExpression may already have cached the routine-reference form before
		' its surrounding value context selected BlitzMax's implicit zero-argument
		' invocation.  Keep the typed tree in step with that contextual decision.
		model.boundExpressionMap.Insert(expression, boundCall)
		Return True
	End Method

	Method ReportAbstractTypeFunctionCall:Int(routine:TSymbol, span:TSourceSpan, dispatchReceiver:TBoundExpression = Null)
		If Not routine Or Not routine.isAbstract Or IsInstanceRoutine(routine) Or Not RoutineOwnerType(routine) Then Return False
		' An object-qualified Type Function call dispatches through the runtime
		' class table.  The statically selected slot may be abstract while the
		' concrete receiver supplies its implementation, just as production bcc
		' permits for MaxGUI's pluggable Type-Function drivers.  Only a fixed,
		' receiver-free call would invoke the abstract declaration itself.
		If dispatchReceiver Then Return False
		Local signature:String = routine.QualifiedName() + "("
		For Local index:Int = 0 Until routine.parameterTypes.length
			If index Then signature :+ ", "
			Local parameter:TSemanticParameter
			If index < routine.parameters.length Then parameter = routine.parameters[index]
			If parameter And parameter.symbol And parameter.symbol.name.length Then signature :+ parameter.symbol.name + ":"
			Local parameterType:TSemanticType = routine.parameterTypes[index]
			If parameterType Then signature :+ parameterType.DisplayName() Else signature :+ "<unresolved>"
		Next
		signature :+ ")"
		AddDiagnostic("BMX3319", "Cannot call abstract Function " + signature + ".", span)
		Return True
	End Method

	Method ReportUncalledRoutineArguments:Int(arguments:TExpressionSyntax[], candidates:TSymbol[], containingSubstitutions:TMap, receiverType:TSemanticType)
		If candidates.length = 0 Then Return False
		Local reported:Int
		For Local index:Int = 0 Until arguments.length
			If TOmittedArgumentExpressionSyntax(arguments[index]) Then Continue
			If CandidatesExpectCallable(index, candidates, containingSubstitutions, receiverType) Then Continue
			If ReportUncalledRoutineReference(arguments[index], Null) Then reported = True
		Next
		Return reported
	End Method

	Function HasOmittedArguments:Int(arguments:TExpressionSyntax[])
		For Local argument:TExpressionSyntax = EachIn arguments
			If TOmittedArgumentExpressionSyntax(argument) Then Return True
		Next
		Return False
	End Function

	Function OmittedArgumentFlags:Int[](arguments:TExpressionSyntax[])
		Local result:Int[] = New Int[arguments.length]
		For Local index:Int = 0 Until arguments.length
			result[index] = TOmittedArgumentExpressionSyntax(arguments[index]) <> Null
		Next
		Return result
	End Function

	Method CandidatesExpectCallable:Int(index:Int, candidates:TSymbol[], containingSubstitutions:TMap, receiverType:TSemanticType)
		For Local routine:TSymbol = EachIn candidates
			If index >= routine.parameterTypes.length Then Continue
			Local substitutions:TMap = containingSubstitutions
			Local declaringReceiver:TSemanticType = MemberDeclaringType(receiverType, routine)
			If declaringReceiver Then substitutions = TypeSubstitutions(declaringReceiver)
			Local required:TSemanticType = TGenericRoutineInference.Substitute(routine.parameterTypes[index], substitutions)
			If TCallableSemanticType(required) Or TTypeParameterSemanticType(required) Then Return True
		Next
		Return False
	End Method

	Method ReportUncalledRoutineReference:Int(expression:TExpressionSyntax, required:TSemanticType)
		If Not expression Or TCallableSemanticType(required) Or TTypeParameterSemanticType(required) Then Return False
		Local reference:TExpressionSyntax = expression
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(reference)
		While parenthesized And parenthesized.expression
			reference = parenthesized.expression
			parenthesized = TParenthesizedExpressionSyntax(reference)
		Wend
		Local symbol:TSymbol
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(reference)
		If name Then symbol = model.ReferencedSymbol(name)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(reference)
		If member Then symbol = model.ReferencedSymbol(member)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return False
		Local kind:String = "Function"
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If (declaration And declaration.isMethod) Or (Not declaration And symbol.containingScope And symbol.containingScope.kind = SCOPE_TYPE) Then kind = "Method"
		Local invocation:String = symbol.name
		If model.syntaxTree And model.syntaxTree.source And expression.span Then
			Local sourceText:String = model.syntaxTree.source.Slice(expression.span).Trim()
			If sourceText.length Then invocation = sourceText
		End If
		AddDiagnostic("BMX3314", kind + " '" + symbol.name + "' is being used as a value rather than called.~nAdd parentheses to call it: " + invocation + "()", expression.span)
		Return True
	End Method

	Function EnclosingRoutine:TSymbol(scope:TScope)
		While scope
			If scope.kind = SCOPE_ROUTINE Then Return scope.owner
			scope = scope.parent
		Wend
		Return Null
	End Function

	Method AssignedSymbol:TSymbol(expression:TExpressionSyntax)
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parenthesized Then Return AssignedSymbol(parenthesized.expression)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then Return model.ReferencedSymbol(name)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then Return model.ReferencedSymbol(member)
		Return Null
	End Method

	Method ValidateSelfAssignment(assignment:TAssignmentStatementSyntax, assignedSymbol:TSymbol, scope:TScope)
		If Not assignment Or Not assignedSymbol Then Return
		Select assignedSymbol.kind
			Case SYMBOL_LOCAL, SYMBOL_GLOBAL, SYMBOL_FIELD, SYMBOL_PARAMETER, SYMBOL_CATCH_PARAMETER
			Default
				Return
		End Select
		If Not SameStorageReference(assignment.left, assignment.right) Then Return
		Local message:String = "Variable '" + assignedSymbol.name + "' is assigned to itself."
		If assignedSymbol.kind = SYMBOL_PARAMETER Then
			Local field:TSymbol = EnclosingFieldNamed(scope, assignedSymbol.name)
			If field Then message :+ " Did you mean 'Self." + field.name + "'?"
		End If
		AddDiagnostic("BMX3411", message, assignment.span, DIAGNOSTIC_WARNING)
	End Method

	Method SameStorageReference:Int(left:TExpressionSyntax, right:TExpressionSyntax)
		Local leftParenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(left)
		If leftParenthesized Then Return SameStorageReference(leftParenthesized.expression, right)
		Local rightParenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(right)
		If rightParenthesized Then Return SameStorageReference(left, rightParenthesized.expression)

		Local leftName:TNameExpressionSyntax = TNameExpressionSyntax(left)
		Local rightName:TNameExpressionSyntax = TNameExpressionSyntax(right)
		If leftName And rightName Then
			If leftName.nameToken.text.ToLower() = "self" Or rightName.nameToken.text.ToLower() = "self" Then
				Return leftName.nameToken.text.ToLower() = "self" And rightName.nameToken.text.ToLower() = "self"
			End If
			Local leftSymbol:TSymbol = model.ReferencedSymbol(leftName)
			Return leftSymbol And leftSymbol = model.ReferencedSymbol(rightName)
		End If

		Local leftMember:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(left)
		Local rightMember:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(right)
		If leftMember And rightMember Then
			Local leftSymbol:TSymbol = model.ReferencedSymbol(leftMember)
			Return leftSymbol And leftSymbol = model.ReferencedSymbol(rightMember) And ..
				SameStorageReference(leftMember.expression, rightMember.expression)
		End If

		' An unqualified Field has the same implicit Self receiver as an explicitly
		' qualified access to that Field.
		If leftName And rightMember Then Return ImplicitAndExplicitSelfFieldMatch(leftName, rightMember)
		If leftMember And rightName Then Return ImplicitAndExplicitSelfFieldMatch(rightName, leftMember)
		Return False
	End Method

	Method ImplicitAndExplicitSelfFieldMatch:Int(name:TNameExpressionSyntax, member:TMemberAccessExpressionSyntax)
		Local nameSymbol:TSymbol = model.ReferencedSymbol(name)
		If Not nameSymbol Or nameSymbol.kind <> SYMBOL_FIELD Or nameSymbol <> model.ReferencedSymbol(member) Then Return False
		Local receiver:TNameExpressionSyntax = TNameExpressionSyntax(member.expression)
		Return receiver And receiver.nameToken.text.ToLower() = "self"
	End Method

	Method EnclosingFieldNamed:TSymbol(scope:TScope, name:String)
		Local selfType:TSemanticType = SelfType(scope)
		For Local symbol:TSymbol = EachIn MemberSymbols(selfType, name)
			If symbol.kind = SYMBOL_FIELD Then Return symbol
		Next
		Return Null
	End Method

	Method CanAssignReadOnlyField:Int(fieldSymbol:TSymbol, scope:TScope)
		If Not fieldSymbol Or fieldSymbol.kind <> SYMBOL_FIELD Then Return False
		Local routine:TSymbol = EnclosingRoutine(scope)
		If Not routine Or routine.name.ToLower() <> "new" Then Return False
		If routine.containingScope = fieldSymbol.containingScope Then Return True
		If Not routine.containingScope Or Not routine.containingScope.owner Or Not fieldSymbol.containingScope Or Not fieldSymbol.containingScope.owner Then Return False
		Local validator:TInheritanceValidator = New TInheritanceValidator
		validator.model = model
		Return validator.IsSubtype(routine.containingScope.owner.declaredType, fieldSymbol.containingScope.owner.declaredType, 0)
	End Method

	Function ReturnRoutineKind:String(routine:TSymbol)
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
		If declaration And declaration.isMethod Then Return "Method"
		Return "Function"
	End Function

	Method IncludedDocument:TSourceDocumentModel(document:TSourceDocumentModel, syntax:TIncludeDirectiveSyntax)
		For Local edge:TIncludeEdge = EachIn document.includes
			If edge.syntax = syntax Then Return edge.target
		Next
		Return Null
	End Method

	Method ConstraintsSatisfied:Int(binding:TGenericRoutineBinding, containingSubstitutions:TMap)
		If Not binding.routine.genericConstraints.length Then Return True
		Local substitutions:TMap = New TMap
		If containingSubstitutions Then
			For Local parameter:TSymbol = EachIn TypeParametersForOwner(binding.routine.containingScope.owner)
				Local argument:TSemanticType = TSemanticType(containingSubstitutions.ValueForKey(parameter))
				If argument Then substitutions.Insert(parameter, argument)
			Next
		End If
		For Local index:Int = 0 Until binding.typeParameters.length
			substitutions.Insert(binding.typeParameters[index], binding.typeArguments[index])
		Next
		Local validator:TInheritanceValidator = New TInheritanceValidator
		validator.model = model
		For Local constraint:TGenericConstraintInfo = EachIn binding.routine.genericConstraints
			Local parameterIndex:Int = SymbolIndex(binding.typeParameters, constraint.parameterSymbol)
			If parameterIndex < 0 Then Continue
			Local actual:TSemanticType = binding.typeArguments[parameterIndex]
			For Local bound:TSemanticType = EachIn constraint.bounds
				Local required:TSemanticType = TGenericRoutineInference.Substitute(bound, substitutions)
				If Not validator.IsSubtype(actual, required, 0) Then Return False
			Next
		Next
		Return True
	End Method

	Method ReceiverSubstitutions:TMap(callee:TExpressionSyntax, scope:TScope)
		Local substitutions:TMap = New TMap
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(callee)
		If Not member Then Return substitutions
		Local genericReceiver:TNamedSemanticType = GenericTypeQualifier(member.expression, scope)
		If genericReceiver Then Return TypeSubstitutions(genericReceiver)
		If StaticMemberScope(member.expression, scope) Then Return substitutions
		Local receiver:TNamedSemanticType = TNamedSemanticType(MemberLookupReceiver(BindExpression(member.expression, scope)))
		If Not receiver Then Return substitutions
		Local parameters:TSymbol[] = TypeParametersForOwner(receiver.symbol)
		For Local index:Int = 0 Until Min(parameters.length, receiver.typeArguments.length)
			substitutions.Insert(parameters[index], receiver.typeArguments[index])
		Next
		Return substitutions
	End Method

	Function SubstituteTypes:TSemanticType[](values:TSemanticType[], substitutions:TMap)
		Local result:TSemanticType[] = New TSemanticType[values.length]
		For Local index:Int = 0 Until values.length
			result[index] = TGenericRoutineInference.Substitute(values[index], substitutions)
		Next
		Return result
	End Function

	Function AppendExpression:TExpressionSyntax[](values:TExpressionSyntax[], value:TExpressionSyntax)
		Local result:TExpressionSyntax[] = New TExpressionSyntax[values.length + 1]
		For Local index:Int = 0 Until values.length
			result[index] = values[index]
		Next
		result[values.length] = value
		Return result
	End Function

	Function AppendType:TSemanticType[](values:TSemanticType[], value:TSemanticType)
		Local result:TSemanticType[] = New TSemanticType[values.length + 1]
		For Local index:Int = 0 Until values.length
			result[index] = values[index]
		Next
		result[values.length] = value
		Return result
	End Function

	Function TypeParametersForOwner:TSymbol[](owner:TSymbol)
		Local result:TSymbol[]
		If Not owner Or Not owner.memberScope Then Return result
		For Local symbol:TSymbol = EachIn owner.memberScope.declaredSymbols
			If symbol.kind = SYMBOL_TYPE_PARAMETER Then result :+ [symbol]
		Next
		Return result
	End Function

	Function RoutineSignature:TRoutineSignatureSyntax(routine:TSymbol)
		If routine.interfaceRecord Then Return routine.interfaceRecord.routineSignature
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
		If declaration Then Return declaration.signature
		Return Null
	End Function

	Method IsAddressable:Int(expression:TExpressionSyntax)
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parenthesized Then Return IsAddressable(parenthesized.expression)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then
			If name.nameToken.text.ToLower() = "self" Then
				Local selfType:TNamedSemanticType = TNamedSemanticType(model.ExpressionType(name))
				Return selfType And selfType.symbol And selfType.symbol.kind = SYMBOL_STRUCT
			End If
			Local symbol:TSymbol = model.ReferencedSymbol(name)
			If Not symbol Then Return False
			Return symbol.kind = SYMBOL_LOCAL Or symbol.kind = SYMBOL_GLOBAL Or symbol.kind = SYMBOL_FIELD Or symbol.kind = SYMBOL_PARAMETER Or symbol.kind = SYMBOL_CATCH_PARAMETER
		End If
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then
			Local resolved:TResolvedMemberAccess = model.ResolvedMember(member)
			Return resolved And (resolved.member.kind = SYMBOL_FIELD Or resolved.member.kind = SYMBOL_GLOBAL)
		End If
		If TIndexExpressionSyntax(expression) Then Return model.ResolvedIndex(expression) <> Null
		Return False
	End Method

	Function SymbolIndex:Int(symbols:TSymbol[], symbol:TSymbol)
		For Local index:Int = 0 Until symbols.length
			If symbols[index] = symbol Then Return index
		Next
		Return -1
	End Function

	Method RoutineCandidates:TSymbol[](callee:TExpressionSyntax, scope:TScope)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(callee)
		If name Then
			If initializerExcludedSymbol And initializerExcludedSymbol.normalizedName = name.nameToken.text.ToLower() Then
				' A variable is not visible within its own initializer. Apply
				' that rule to call candidates as well as value lookup so an
				' imported or outer same-named routine remains callable.
				Return FilterRoutines(Lookup(scope, name.nameToken.text, name))
			End If
			Local lexical:TSymbol[] = scope.Lookup(name.nameToken.text)
			If lexical.length Then
				Local routines:TSymbol[] = FilterRoutines(lexical)
				Local selfType:TNamedSemanticType = TNamedSemanticType(SelfType(scope))
				If selfType And selfType.symbol Then
					Local members:TSymbol[] = AccessibleSymbols(RoutineMemberSymbols(selfType, name.nameToken.text), scope)
					If members.length Then
						For Local outer:TSymbol = EachIn OuterRoutineSymbols(scope, selfType.symbol.memberScope, name.nameToken.text)
							If Not ContainsSymbol(members, outer) Then members :+ [outer]
						Next
						Return members
					End If
				End If
				Return routines
			End If
			Local inherited:TSymbol[] = AccessibleSymbols(RoutineMemberSymbols(SelfType(scope), name.nameToken.text), scope)
			If inherited.length Then
				' An inherited member does not hide an imported/global overload unless
				' that member is actually applicable. Keep both tiers available to the
				' overload resolver, just as we do for a directly declared member above.
				Local memberScope:TScope = MemberScope(SelfType(scope))
				For Local outer:TSymbol = EachIn OuterRoutineSymbols(scope, memberScope, name.nameToken.text)
					If Not ContainsSymbol(inherited, outer) Then inherited :+ [outer]
				Next
				Return inherited
			End If
			Return FilterRoutines(Lookup(scope, name.nameToken.text, name))
		End If
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(callee)
		If member Then
			Local selectedScope:TScope = StaticMemberScope(member.expression, scope)
			If selectedScope Then Return AccessibleSymbols(StaticRoutineSymbols(selectedScope, member.nameToken.text), scope)
			Return AccessibleSymbols(RoutineMemberSymbols(MemberLookupReceiver(BindExpression(member.expression, scope)), member.nameToken.text), scope)
		End If
		Return New TSymbol[0]
	End Method

	Method OuterRoutineSymbols:TSymbol[](scope:TScope, memberScope:TScope, name:String)
		Local current:TScope = scope
		While current
			If current <> memberScope Then
				Local routines:TSymbol[] = AccessibleSymbols(FilterRoutines(current.LookupLocal(name)), scope)
				If routines.length Then Return routines
			End If
			current = current.parent
		Wend
		For Local imported:TScope = EachIn model.directImportedScopes
			Local routines:TSymbol[] = AccessibleSymbols(FilterRoutines(imported.LookupLocal(name)), scope)
			If routines.length Then Return routines
		Next
		For Local imported:TScope = EachIn model.importedScopes
			If IsDirectImportedScope(imported) Then Continue
			Local routines:TSymbol[] = AccessibleSymbols(FilterRoutines(imported.LookupLocal(name)), scope)
			If routines.length Then Return routines
		Next
		Return New TSymbol[0]
	End Method

	Method RoutineMemberSymbols:TSymbol[](receiver:TSemanticType, name:String, depth:Int = 0)
		If depth > 64 Then Return New TSymbol[0]
		Local bounds:TSemanticType[] = TypeParameterBounds(receiver)
		If bounds.length Then
			Local constrained:TSymbol[]
			For Local bound:TSemanticType = EachIn bounds
				For Local member:TSymbol = EachIn RoutineMemberSymbols(bound, name, depth + 1)
					If Not ContainsSymbol(constrained, member) Then constrained :+ [member]
				Next
			Next
			Return constrained
		End If
		Local memberScope:TScope = MemberScope(receiver)
		If Not memberScope Then Return New TSymbol[0]
		Local direct:TSymbol[] = FilterRoutines(memberScope.LookupLocal(name))
		Local result:TSymbol[] = direct
		Local named:TNamedSemanticType = TNamedSemanticType(receiver)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(receiver)
		If Not named And builtin And builtin.runtimeSymbol Then named = TNamedSemanticType(builtin.runtimeSymbol.declaredType)
		If Not named And TArraySemanticType(receiver) Then
			named = New TNamedSemanticType
			named.kind = SEMANTIC_TYPE_NAMED
			named.symbol = model.ArrayIntrinsic()
		End If
		If Not named Or Not named.symbol Then Return result
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not info Then Return result
		For Local edge:TInheritanceEdge = EachIn InheritanceEdges(info)
			Local inheritedType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, TypeSubstitutions(named))
			For Local inherited:TSymbol = EachIn RoutineMemberSymbols(inheritedType, name, depth + 1)
				If RoutineIsShadowed(direct, inherited, named, inheritedType) Then Continue
				If Not ContainsSymbol(result, inherited) Then result :+ [inherited]
			Next
		Next
		Return result
	End Method

	Method RoutineIsShadowed:Int(direct:TSymbol[], inherited:TSymbol, directReceiver:TNamedSemanticType, inheritedReceiver:TSemanticType)
		Local declaringType:TNamedSemanticType = TNamedSemanticType(MemberDeclaringType(inheritedReceiver, inherited))
		' The core runtime Object may be represented by the canonical builtin
		' symbol while an imported edge retains its interface-local type identity.
		' The inherited receiver still supplies the correct substitutions.
		If Not declaringType Then declaringType = TNamedSemanticType(inheritedReceiver)
		If Not declaringType Then
			Local inheritedBuiltin:TBuiltinSemanticType = TBuiltinSemanticType(inheritedReceiver)
			If inheritedBuiltin And inheritedBuiltin.runtimeSymbol Then declaringType = TNamedSemanticType(inheritedBuiltin.runtimeSymbol.declaredType)
		End If
		If Not declaringType Then Return False
		For Local routine:TSymbol = EachIn direct
			If routine.genericArity = inherited.genericArity And routine.parameterTypes.length = inherited.parameterTypes.length Then
				Local directParameters:TSemanticType[] = SubstituteTypes(routine.parameterTypes, TypeSubstitutions(directReceiver))
				Local inheritedParameters:TSemanticType[] = SubstituteTypes(inherited.parameterTypes, TypeSubstitutions(declaringType))
				Local sameParameters:Int = True
				For Local index:Int = 0 Until directParameters.length
					If Not TGenericRoutineInference.SameType(directParameters[index], inheritedParameters[index]) Or ParameterMode(routine, index) <> ParameterMode(inherited, index) Then
						sameParameters = False
						Exit
					End If
				Next
				If sameParameters Then Return True
			End If
			' A return type is not part of the callable signature. Once the generic
			' arity, parameters, and Var modes match, the declaration on the derived
			' receiver hides the inherited method during overload collection.
			If inheritanceValidator.OverrideParametersMatch(routine, inherited, declaringType) Then Return True
		Next
		Return False
	End Method

	Function ParameterMode:Int(routine:TSymbol, index:Int)
		If routine And index < routine.parameters.length Then Return routine.parameters[index].passingMode
		Return PARAMETER_PASS_VALUE
	End Function

	Method AccessibleSymbols:TSymbol[](symbols:TSymbol[], scope:TScope)
		Local result:TSymbol[]
		For Local symbol:TSymbol = EachIn symbols
			If TSymbolAccessibility.IsAccessible(symbol, scope, model) Then result :+ [symbol]
		Next
		Return result
	End Method

	Method ReportInaccessibleMember:Int(member:TMemberAccessExpressionSyntax, symbols:TSymbol[], scope:TScope)
		If Not member Or symbols.length = 0 Then Return False
		For Local symbol:TSymbol = EachIn symbols
			If TSymbolAccessibility.IsAccessible(symbol, scope, model) Then Return False
		Next
		If inaccessibleMemberReports.Contains(member) Then Return True
		Local symbol:TSymbol = symbols[0]
		Local category:String = symbol.KindName()
		If symbol.kind = SYMBOL_ROUTINE Then
			If IsInstanceRoutine(symbol) Then category = "Method" Else category = "Function"
		End If
		Local visibility:String = TSymbolAccessibility.VisibilityName(symbol.visibility)
		' Accessibility affects whether the expression can bind successfully, but it
		' does not erase the declaration's identity. Editor features can still use
		' this reference for hover and navigation while diagnostics reject the call.
		model.referencedSymbolMap.Insert(member, symbol)
		AddDiagnostic("BMX3318", category + " '" + symbol.QualifiedName() + "' is " + visibility + " and cannot be accessed from this scope.", member.nameToken.span)
		inaccessibleMemberReports.Insert(member, symbol)
		Return True
	End Method

	Method ReportInaccessibleName:Int(name:TNameExpressionSyntax, symbols:TSymbol[], scope:TScope)
		If Not name Or symbols.length = 0 Then Return False
		For Local symbol:TSymbol = EachIn symbols
			If TSymbolAccessibility.IsAccessible(symbol, scope, model) Then Return False
		Next
		If inaccessibleMemberReports.Contains(name) Then Return True
		Local symbol:TSymbol = symbols[0]
		Local category:String = symbol.KindName()
		If symbol.kind = SYMBOL_ROUTINE Then
			If IsInstanceRoutine(symbol) Then category = "Method" Else category = "Function"
		End If
		Local visibility:String = TSymbolAccessibility.VisibilityName(symbol.visibility)
		model.referencedSymbolMap.Insert(name, symbol)
		AddDiagnostic("BMX3318", category + " '" + symbol.QualifiedName() + "' is " + visibility + " and cannot be accessed from this scope.", name.nameToken.span)
		inaccessibleMemberReports.Insert(name, symbol)
		Return True
	End Method

	Method StaticMemberSymbols:TSymbol[](selectedScope:TScope, name:String)
		If Not selectedScope Then Return New TSymbol[0]
		' A leading-dot selector uses the compilation-unit global scope, but that
		' scope includes imported module declarations just like an unqualified
		' global lookup.  It suppresses only an enclosing Type's members.
		If selectedScope = model.globalScope Then
			Local result:TSymbol[]
			For Local symbol:TSymbol = EachIn Lookup(selectedScope, name)
				If IsStaticMember(symbol) Then result :+ [symbol]
			Next
			Return result
		End If
		If selectedScope.kind <> SCOPE_TYPE Or Not selectedScope.owner Then Return selectedScope.LookupLocal(name)
		Local result:TSymbol[]
		For Local symbol:TSymbol = EachIn MemberSymbols(selectedScope.owner.declaredType, name)
			If IsStaticMember(symbol) Then result :+ [symbol]
		Next
		Return result
	End Method

	Method StaticRoutineSymbols:TSymbol[](selectedScope:TScope, name:String)
		If Not selectedScope Then Return New TSymbol[0]
		If selectedScope = model.globalScope Then Return FilterRoutines(Lookup(selectedScope, name))
		If selectedScope.kind <> SCOPE_TYPE Or Not selectedScope.owner Then Return FilterRoutines(selectedScope.LookupLocal(name))
		Local result:TSymbol[]
		For Local symbol:TSymbol = EachIn RoutineMemberSymbols(selectedScope.owner.declaredType, name)
			If Not IsInstanceRoutine(symbol) Then result :+ [symbol]
		Next
		Return result
	End Method

	Function IsStaticMember:Int(symbol:TSymbol)
		If Not symbol Then Return False
		Select symbol.kind
			Case SYMBOL_GLOBAL, SYMBOL_CONST, SYMBOL_ENUM_MEMBER Return True
			Case SYMBOL_ROUTINE Return Not IsInstanceRoutine(symbol)
		End Select
		Return False
	End Function

	Function IsInstanceRoutine:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return False
		If symbol.interfaceRecord Then Return symbol.interfaceRecord.kind = INTERFACE_RECORD_METHOD
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		Return declaration And declaration.isMethod
	End Function

	Method StaticMemberScope:TScope(expression:TExpressionSyntax, scope:TScope)
		' A leading dot explicitly escapes an enclosing Type and selects the
		' compilation unit's global declarations.
		If TScopeExpressionSyntax(expression) Then Return model.globalScope
		Local genericReceiver:TNamedSemanticType = GenericTypeQualifier(expression, scope)
		If genericReceiver And genericReceiver.symbol Then Return genericReceiver.symbol.memberScope
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then
			For Local symbol:TSymbol = EachIn Lookup(scope, name.nameToken.text, name)
				If symbol.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then
					model.referencedSymbolMap.Insert(name, symbol)
					Return symbol.memberScope
				End If
			Next
		End If
		Local qualifiedName:String = QualifiedExpressionName(expression)
		If qualifiedName.length Then
			Local moduleScope:TScope = model.ImportedScope(qualifiedName)
			If moduleScope Then Return moduleScope
		End If
		Return Null
	End Method

	Method GenericTypeQualifier:TNamedSemanticType(expression:TExpressionSyntax, scope:TScope)
		If Not expression Then Return Null
		Local typeArguments:TTypeReferenceSyntax[]
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then typeArguments = name.typeArguments
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then typeArguments = member.typeArguments
		If Not typeArguments.length Then Return Null
		Local cached:TNamedSemanticType = TNamedSemanticType(genericTypeQualifierTypes.ValueForKey(expression))
		If cached Then Return cached

		Local symbol:TSymbol
		If name Then
			' Type and value names occupy distinct namespaces. A local value with the
			' same spelling must not hide a generic Type used as a static qualifier.
			For Local candidate:TSymbol = EachIn typeResolver.LookupTypeCandidates(scope, name.nameToken.text)
				If candidate.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then symbol = candidate; Exit
			Next
		Else If member Then
			Local prefix:String = QualifiedExpressionName(member.expression)
			Local selectedScope:TScope = model.ImportedScope(prefix)
			If selectedScope Then
				For Local candidate:TSymbol = EachIn selectedScope.LookupLocal(member.nameToken.text)
					If candidate.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then symbol = candidate; Exit
				Next
			End If
		End If
		If Not symbol Then
			AddDiagnostic("BMX3300", "Generic type qualifier '" + QualifiedExpressionName(expression) + "' could not be resolved as a type.", expression.span)
			Return Null
		End If

		Local parameters:TSymbol[] = TypeParametersForOwner(symbol)
		If parameters.length <> typeArguments.length Then
			AddDiagnostic("BMX3306", "Generic type '" + symbol.name + "' expects " + parameters.length + " type argument(s), but " + typeArguments.length + " were supplied.", expression.span)
			Return Null
		End If
		Local result:TNamedSemanticType = New TNamedSemanticType
		result.kind = SEMANTIC_TYPE_NAMED
		result.symbol = symbol
		result.typeArguments = New TSemanticType[typeArguments.length]
		For Local index:Int = 0 Until typeArguments.length
			result.typeArguments[index] = ResolveType(typeArguments[index], scope)
		Next
		model.referencedSymbolMap.Insert(expression, symbol)
		genericTypeQualifierTypes.Insert(expression, result)
		Return result
	End Method

	Function QualifiedExpressionName:String(expression:TExpressionSyntax)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name And name.nameToken Then Return name.nameToken.text
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member And member.nameToken Then
			Local prefix:String = QualifiedExpressionName(member.expression)
			If prefix.length Then Return prefix + "." + member.nameToken.text
		End If
		Return ""
	End Function

	Method SelfType:TSemanticType(scope:TScope)
		While scope
			If scope.kind = SCOPE_TYPE And scope.owner Then
				Local result:TNamedSemanticType = New TNamedSemanticType
				result.kind = SEMANTIC_TYPE_NAMED
				result.symbol = scope.owner
				Local parameters:TSymbol[] = TypeParametersForOwner(scope.owner)
				result.typeArguments = New TSemanticType[parameters.length]
				For Local index:Int = 0 Until parameters.length
					result.typeArguments[index] = parameters[index].declaredType
				Next
				Return result
			End If
			scope = scope.parent
		Wend
		Return Null
	End Method

	Method SuperType:TSemanticType(scope:TScope)
		Local inRoutine:Int
		Local currentScope:TScope = scope
		While currentScope
			If currentScope.kind = SCOPE_ROUTINE Then inRoutine = True
			If currentScope.kind = SCOPE_TYPE Then
				If Not inRoutine Then Return Null
				Exit
			End If
			currentScope = currentScope.parent
		Wend
		If Not currentScope Then Return Null
		Local currentType:TNamedSemanticType = TNamedSemanticType(SelfType(scope))
		If Not currentType Then Return Null
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(currentType.symbol)
		If Not info Or Not info.baseEdges.length Then Return Null
		Return TGenericRoutineInference.Substitute(info.baseEdges[0].semanticType, TypeSubstitutions(currentType))
	End Method

	Function TypeSubstitutions:TMap(receiver:TSemanticType)
		Local substitutions:TMap = New TMap
		Local named:TNamedSemanticType = TNamedSemanticType(receiver)
		If Not named Then Return substitutions
		Local parameters:TSymbol[] = TypeParametersForOwner(named.symbol)
		For Local index:Int = 0 Until Min(parameters.length, named.typeArguments.length)
			substitutions.Insert(parameters[index], named.typeArguments[index])
		Next
		Return substitutions
	End Function

	Method BindUnary:TSemanticType(unary:TUnaryExpressionSyntax, scope:TScope)
		Local operation:String = unary.operatorToken.text.ToLower()
		If operation = "sizeof" Or operation = "alignof" Then
			Local intrinsicOperand:TIntrinsicOperandBinding = ResolveIntrinsicOperand(unary.operand, scope)
			model.intrinsicOperandMap.Insert(unary, intrinsicOperand)
			Return model.BuiltinType("Size_T")
		End If
		Local operand:TSemanticType = BindExpression(unary.operand, scope)
		If operation = "asc" Then
			If operand And Not conversions.ClassifyExpression(unary.operand, operand, model.BuiltinType("String")).Exists() Then AddDiagnostic("BMX3310", "Type '" + operand.DisplayName() + "' cannot be converted to 'String' for Asc.", unary.operand.span)
			Return model.BuiltinType("Int")
		End If
		If operation = "chr" Then
			If operand And Not conversions.ClassifyAssignmentExpression(unary.operand, operand, model.BuiltinType("Int")).Exists() Then AddDiagnostic("BMX3310", "Type '" + operand.DisplayName() + "' cannot be converted to 'Int' for Chr.", unary.operand.span)
			Return model.BuiltinType("String")
		End If
		If operation = "stackalloc" Then
			Local sizeType:TSemanticType = model.BuiltinType("Size_T")
			If operand And Not conversions.ClassifyAssignmentExpression(unary.operand, operand, sizeType).Exists() Then AddDiagnostic("BMX3310", "Type '" + operand.DisplayName() + "' cannot be converted to 'Size_T' for StackAlloc.", unary.operand.span)
			Local allocatedPointer:TPointerSemanticType = New TPointerSemanticType
			allocatedPointer.kind = SEMANTIC_TYPE_POINTER
			allocatedPointer.elementType = model.BuiltinType("Byte")
			Return allocatedPointer
		End If
		If TNamedSemanticType(operand) Then
			Local resolved:TResolvedCall = ResolveOperator(unary, unary.operand, unary.operatorToken.text, operand, New TExpressionSyntax[0], New TSemanticType[0], scope)
			If resolved Then Return resolved.returnType
		End If
		Select operation
			Case "not", "len" Return model.BuiltinType("Int")
			Case "varptr"
				If Not IsAddressable(unary.operand) Then AddDiagnostic("BMX3311", "VarPtr requires writable, addressable storage.", unary.operand.span)
				Local pointer:TPointerSemanticType = New TPointerSemanticType
				pointer.kind = SEMANTIC_TYPE_POINTER
				pointer.elementType = operand
				Return pointer
		End Select
		Return operand
	End Method

	Method ResolveIntrinsicOperand:TIntrinsicOperandBinding(expression:TExpressionSyntax, scope:TScope)
		Local result:TIntrinsicOperandBinding = New TIntrinsicOperandBinding
		Local candidate:TExpressionSyntax = expression
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(candidate)
		While parenthesized
			candidate = parenthesized.expression
			parenthesized = TParenthesizedExpressionSyntax(candidate)
		Wend
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(candidate)
		If name Then
			Local builtin:TSemanticType = model.BuiltinType(name.nameToken.text)
			If builtin Then
				result.semanticType = builtin
				result.isTypeOperand = True
				Return result
			End If
			For Local symbol:TSymbol = EachIn Lookup(scope, name.nameToken.text, name)
				If symbol.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then
					model.referencedSymbolMap.Insert(name, symbol)
					result.semanticType = symbol.declaredType
					result.isTypeOperand = True
					Return result
				End If
			Next
		End If
		result.semanticType = BindExpression(expression, scope)
		Return result
	End Method

	Method BindBinary:TSemanticType(binary:TBinaryExpressionSyntax, scope:TScope)
		Local left:TSemanticType = BindExpression(binary.left, scope)
		Local right:TSemanticType = BindExpression(binary.right, scope)
		Local operation:String = binary.operatorToken.text.ToLower()
		If TNamedSemanticType(left) Then
			Local resolved:TResolvedCall = ResolveOperator(binary, binary.left, binary.operatorToken.text, left, [binary.right], [right], scope)
			If resolved Then Return resolved.returnType
		End If
		Select operation
			Case "=", "<>", "<", ">", "<=", ">=", "and", "or" Return model.BuiltinType("Int")
			Case "+"
				If IsBuiltin(left, "string") Or IsBuiltin(right, "string") Then Return model.BuiltinType("String")
				If TPointerSemanticType(left) And TConversionClassifier.IsIntegral(right) Then Return left
				If TConversionClassifier.IsIntegral(left) And TPointerSemanticType(right) Then Return right
			Case "-"
				If TPointerSemanticType(left) And (TPointerSemanticType(right) Or TConversionClassifier.CanDecayArrayToPointer(right, left)) Then Return model.BuiltinType("Int")
				If TPointerSemanticType(right) And TConversionClassifier.CanDecayArrayToPointer(left, right) Then Return model.BuiltinType("Int")
				If TPointerSemanticType(left) And TConversionClassifier.IsIntegral(right) Then Return left
		End Select
		Return WiderNumericType(left, right)
	End Method

	Method BindCast:TSemanticType(cast:TCastExpressionSyntax, scope:TScope)
		Local actual:TSemanticType = BindExpression(cast.expression, scope)
		Local required:TSemanticType = ResolveType(cast.targetType, scope)
		If actual And required And Not conversions.ClassifyExplicit(actual, required).Exists() Then
			AddDiagnostic("BMX3312", "Type '" + actual.DisplayName() + "' cannot be explicitly converted to '" + required.DisplayName() + "'.", cast.span)
		End If
		Return required
	End Method

	Method BindArrayLiteral:TSemanticType(literal:TArrayLiteralExpressionSyntax, scope:TScope)
		Local elements:TSemanticType[] = BindExpressions(literal.elements, scope)
		If Not elements.length Then Return Null
		Local elementType:TSemanticType = elements[0]
		For Local index:Int = 1 Until elements.length
			elementType = WiderNumericType(elementType, elements[index])
		Next
		If Not elementType Then
			Local errorType:TErrorSemanticType = New TErrorSemanticType
			errorType.kind = SEMANTIC_TYPE_ERROR
			errorType.writtenName = "array element"
			elementType = errorType
		End If
		Local result:TArraySemanticType = New TArraySemanticType
		result.kind = SEMANTIC_TYPE_ARRAY
		result.elementType = elementType
		result.rank = 1
		Return result
	End Method

	Method WiderNumericType:TSemanticType(first:TSemanticType, second:TSemanticType)
		If Not first Then Return second
		If Not second Then Return first
		If TGenericRoutineInference.SameType(first, second) Then Return first
		Local firstRank:Int = NumericRank(first)
		Local secondRank:Int = NumericRank(second)
		If firstRank < 0 Or secondRank < 0 Then Return first
		If secondRank > firstRank Then Return second
		Return first
	End Method

	Function NumericRank:Int(value:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If Not builtin Then Return -1
		Select builtin.name.ToLower()
			Case "byte" Return 1
			Case "short" Return 2
			Case "int", "uint" Return 3
			Case "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam" Return 4
			Case "float" Return 5
			Case "double" Return 6
		End Select
		Return -1
	End Function

	Function IsBuiltin:Int(value:TSemanticType, name:String)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		Return builtin And builtin.name.ToLower() = name
	End Function

	Method Lookup:TSymbol[](scope:TScope, name:String, reference:TSyntaxNode = Null)
		Local values:TSymbol[]
		Local candidateScope:TScope = scope
		While candidateScope
			Local localValues:TSymbol[] = candidateScope.LookupLocal(name)
			Local retained:TSymbol[]
			For Local value:TSymbol = EachIn localValues
				If value = initializerExcludedSymbol Then Continue
				If reference And value.kind = SYMBOL_LOCAL And value.declaration And value.declaration.span.start > reference.span.start Then Continue
				retained :+ [value]
			Next
			If retained.length Then Return retained
			candidateScope = candidateScope.parent
		Wend
		values = MemberSymbols(SelfType(scope), name)
		If values.length Then Return AccessibleSymbols(values, scope)
		For Local imported:TScope = EachIn model.directImportedScopes
			values = imported.LookupLocal(name)
			If values.length Then Return AccessibleSymbols(values, scope)
		Next
		For Local imported:TScope = EachIn model.importedScopes
			If IsDirectImportedScope(imported) Then Continue
			values = imported.LookupLocal(name)
			If values.length Then Return AccessibleSymbols(values, scope)
		Next
		Return New TSymbol[0]
	End Method

	Method IsDirectImportedScope:Int(scope:TScope)
		For Local direct:TScope = EachIn model.directImportedScopes
			If direct = scope Then Return True
		Next
		Return False
	End Method

	Method MemberScope:TScope(value:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then Return named.symbol.memberScope
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If builtin And builtin.runtimeSymbol Then Return builtin.runtimeSymbol.memberScope
		If TArraySemanticType(value) Then Return model.ArrayIntrinsic().memberScope
		If TStaticArraySemanticType(value) Then Return model.StaticArrayIntrinsic().memberScope
		Return Null
	End Method

	Function MemberLookupReceiver:TSemanticType(value:TSemanticType)
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If Not pointer Then Return value
		Local named:TNamedSemanticType = TNamedSemanticType(pointer.elementType)
		If named And named.symbol.kind = SYMBOL_STRUCT Then Return pointer.elementType
		Return value
	End Function

	Method RecordIndex(syntax:TSyntaxNode, accessKind:Int, receiverType:TSemanticType, resultType:TSemanticType, resolvedCall:TResolvedCall = Null)
		Local access:TResolvedIndexAccess = New TResolvedIndexAccess
		access.accessKind = accessKind
		access.receiverType = receiverType
		access.resultType = resultType
		access.resolvedCall = resolvedCall
		model.resolvedIndexMap.Insert(syntax, access)
	End Method

	Method RecordRangeIndex(syntax:TSyntaxNode, accessKind:Int, receiverType:TSemanticType, resultType:TSemanticType, rangeType:TSemanticType, scope:TScope)
		Local access:TResolvedIndexAccess = New TResolvedIndexAccess
		access.accessKind = accessKind
		access.receiverType = receiverType
		access.resultType = resultType
		For Local routine:TSymbol = EachIn AccessibleSymbols(RoutineMemberSymbols(rangeType, "ResolveStart"), scope)
			If routine.parameterTypes.length = 1 And TConversionClassifier.IsIntegral(routine.parameterTypes[0]) Then access.rangeStartRoutine = routine; Exit
		Next
		For Local routine:TSymbol = EachIn AccessibleSymbols(RoutineMemberSymbols(rangeType, "ResolveEndExclusive"), scope)
			If routine.parameterTypes.length = 1 And TConversionClassifier.IsIntegral(routine.parameterTypes[0]) Then access.rangeEndRoutine = routine; Exit
		Next
		If Not access.rangeStartRoutine Or Not access.rangeEndRoutine Then
			AddDiagnostic("BMX3304", "The standard Range type does not provide its required bound-resolution methods.", syntax.span)
			Return
		End If
		model.resolvedIndexMap.Insert(syntax, access)
	End Method

	Method IsCanonicalRangeType:Int(value:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If Not named Or Not named.symbol Or named.typeArguments.length Then Return False
		If named.symbol.name.ToLower() <> "range" Then Return False
		Return named.symbol.originModule.ToLower() = "brl.range"
	End Method

	Method ReceiverType:TSemanticType(callee:TExpressionSyntax, scope:TScope)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(callee)
		If member Then
			Local genericReceiver:TNamedSemanticType = GenericTypeQualifier(member.expression, scope)
			If genericReceiver Then Return genericReceiver
			If StaticMemberScope(member.expression, scope) Then Return Null
			Return MemberLookupReceiver(BindExpression(member.expression, scope))
		End If
		If TNameExpressionSyntax(callee) Then Return SelfType(scope)
		Return Null
	End Method

	Method MemberSymbols:TSymbol[](receiver:TSemanticType, name:String, depth:Int = 0)
		If depth > 64 Then Return New TSymbol[0]
		Local bounds:TSemanticType[] = TypeParameterBounds(receiver)
		If bounds.length Then
			Local constrained:TSymbol[]
			For Local bound:TSemanticType = EachIn bounds
				For Local member:TSymbol = EachIn MemberSymbols(bound, name, depth + 1)
					If Not ContainsSymbol(constrained, member) Then constrained :+ [member]
				Next
			Next
			Return constrained
		End If
		Local memberScope:TScope = MemberScope(receiver)
		If Not memberScope Then Return New TSymbol[0]
		Local direct:TSymbol[] = memberScope.LookupLocal(name)
		If direct.length Then Return direct
		Local named:TNamedSemanticType = TNamedSemanticType(receiver)
		If Not named And TArraySemanticType(receiver) Then
			named = New TNamedSemanticType
			named.kind = SEMANTIC_TYPE_NAMED
			named.symbol = model.ArrayIntrinsic()
		End If
		If Not named Then Return New TSymbol[0]
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not info Then Return New TSymbol[0]
		Local result:TSymbol[]
		For Local edge:TInheritanceEdge = EachIn InheritanceEdges(info)
			Local inheritedType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, TypeSubstitutions(named))
			For Local symbol:TSymbol = EachIn MemberSymbols(inheritedType, name, depth + 1)
				If Not ContainsSymbol(result, symbol) Then result :+ [symbol]
			Next
		Next
		Return result
	End Method

	Method MemberDeclaringType:TSemanticType(receiver:TSemanticType, member:TSymbol)
		If Not receiver Or Not member Or Not member.containingScope Then Return Null
		Return FindConstructedAncestor(receiver, member.containingScope.owner, 0)
	End Method

	Method FindConstructedAncestor:TSemanticType(receiver:TSemanticType, target:TSymbol, depth:Int)
		If depth > 64 Or Not target Then Return Null
		For Local bound:TSemanticType = EachIn TypeParameterBounds(receiver)
			Local constrained:TSemanticType = FindConstructedAncestor(bound, target, depth + 1)
			If constrained Then Return constrained
		Next
		Local named:TNamedSemanticType = TNamedSemanticType(receiver)
		If Not named Then Return Null
		If named.symbol = target Then Return named
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not info Then Return Null
		For Local edge:TInheritanceEdge = EachIn InheritanceEdges(info)
			Local inheritedType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, TypeSubstitutions(named))
			Local found:TSemanticType = FindConstructedAncestor(inheritedType, target, depth + 1)
			If found Then Return found
		Next
		Return Null
	End Method

	Method TypeParameterBounds:TSemanticType[](receiver:TSemanticType)
		Local parameterType:TTypeParameterSemanticType = TTypeParameterSemanticType(receiver)
		If Not parameterType Or Not parameterType.symbol Or Not parameterType.symbol.containingScope Then Return New TSemanticType[0]
		Local owner:TSymbol = parameterType.symbol.containingScope.owner
		If Not owner Then Return New TSemanticType[0]
		Local constraints:TGenericConstraintInfo[]
		If owner.kind = SYMBOL_ROUTINE Then
			constraints = owner.genericConstraints
		Else
			Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(owner)
			If inheritance Then constraints = inheritance.constraints
		End If
		For Local constraint:TGenericConstraintInfo = EachIn constraints
			If constraint.parameterSymbol = parameterType.symbol Then Return constraint.bounds
		Next
		Return New TSemanticType[0]
	End Method

	Function InheritanceEdges:TInheritanceEdge[](info:TTypeInheritanceInfo)
		Local result:TInheritanceEdge[] = New TInheritanceEdge[info.baseEdges.length + info.interfaceEdges.length]
		For Local index:Int = 0 Until info.baseEdges.length
			result[index] = info.baseEdges[index]
		Next
		For Local index:Int = 0 Until info.interfaceEdges.length
			result[info.baseEdges.length + index] = info.interfaceEdges[index]
		Next
		Return result
	End Function

	Function ContainsSymbol:Int(values:TSymbol[], symbol:TSymbol)
		For Local value:TSymbol = EachIn values
			If value = symbol Then Return True
		Next
		Return False
	End Function

	Method BindExpressions:TSemanticType[](expressions:TExpressionSyntax[], scope:TScope)
		Local result:TSemanticType[] = New TSemanticType[expressions.length]
		For Local index:Int = 0 Until expressions.length
			result[index] = BindExpression(expressions[index], scope)
		Next
		Return result
	End Method

	Method LiteralType:TSemanticType(token:TSyntaxToken)
		Select token.kind
			Case TOKEN_STRING_LITERAL, TOKEN_MULTILINE_STRING_LITERAL Return model.BuiltinType("String")
			Case TOKEN_FLOAT_LITERAL Return model.BuiltinType("Double")
			Case TOKEN_INTEGER_LITERAL Return model.BuiltinType("Int")
		End Select
		Select token.text.ToLower()
			Case "true", "false" Return model.BuiltinType("Int")
			Case "null" Return model.BuiltinType("Null")
			Case "pi" Return model.BuiltinType("Double")
		End Select
		Return Null
	End Method

	Function FilterRoutines:TSymbol[](symbols:TSymbol[])
		Local result:TSymbol[]
		For Local symbol:TSymbol = EachIn symbols
			If symbol.kind = SYMBOL_ROUTINE Then result :+ [symbol]
		Next
		Return result
	End Function

	Function CallableFromRoutine:TCallableSemanticType(routine:TSymbol)
		If Not routine Then Return Null
		Local result:TCallableSemanticType = New TCallableSemanticType
		result.kind = SEMANTIC_TYPE_CALLABLE
		result.routine = routine
		result.callingConvention = routine.callingConvention
		result.parameterTypes = routine.parameterTypes
		result.parameterModes = New Int[routine.parameters.length]
		For Local index:Int = 0 Until routine.parameters.length
			result.parameterModes[index] = routine.parameters[index].passingMode
		Next
		result.returnType = routine.declaredType
		Return result
	End Function

	Function CalleeName:String(callee:TExpressionSyntax)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(callee)
		If name Then Return name.nameToken.text
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(callee)
		If member Then Return member.nameToken.text
		Return "<expression>"
	End Function

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan, severity:Int = DIAGNOSTIC_ERROR)
		diagnostics.AddLast(TDiagnostic.Create(code, message, severity, span, CurrentSourcePath()))
	End Method

	Method ResolveType:TSemanticType(syntax:TTypeReferenceSyntax, scope:TScope)
		typeResolver.currentPath = CurrentSourcePath()
		Return typeResolver.Resolve(syntax, scope)
	End Method

	Method CurrentSourcePath:String()
		If currentDocument Then Return currentDocument.path
		If model.syntaxTree Then Return model.syntaxTree.source.path
		Return ""
	End Method

	Method EffectiveSourceMode:Int()
		If currentDocument And currentDocument.effectiveSourceMode Then Return currentDocument.effectiveSourceMode
		If model.syntaxTree And model.syntaxTree.root Then Return model.syntaxTree.root.sourceMode
		Return SOURCE_MODE_STRICT
	End Method

	Function DiagnosticsToArray:TDiagnostic[](list:TList)
		Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
		Local index:Int
		For Local diagnostic:TDiagnostic = EachIn list
			result[index] = diagnostic
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
