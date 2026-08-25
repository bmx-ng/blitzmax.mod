' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "conversion_classification.bmx"

Type TBoundDumper
	Function Dump:String(expression:TBoundExpression)
		Return DumpExpression(expression, "")
	End Function

	Function DumpStatement:String(statement:TBoundStatement)
		Return DumpBoundStatement(statement, "")
	End Function

	Function DumpRoutine:String(model:TSemanticModel, routine:TSymbol)
		If Not model Then Return "<missing semantic model>~n"
		Return DumpBoundStatement(model.BoundRoutineBody(routine), "")
	End Function

	Function DumpGlobal:String(model:TSemanticModel)
		If Not model Then Return "<missing semantic model>~n"
		Return DumpBoundStatement(model.boundGlobalBody, "")
	End Function

	Function DumpBoundStatement:String(statement:TBoundStatement, indent:String)
		If Not statement Then Return indent + "<missing bound statement>~n"
		Local result:String = indent + StatementKindName(statement.boundKind)
		If statement.syntax Then result :+ " [" + statement.syntax.KindName() + "]"
		Local assignment:TBoundAssignmentStatement = TBoundAssignmentStatement(statement)
		If assignment And assignment.operatorText Then result :+ " " + assignment.operatorText
		Local loop:TBoundForStatement = TBoundForStatement(statement)
		If loop Then
			If loop.isEachIn Then
				result :+ " [EachIn"
				If loop.iteration Then result :+ " " + EachInProtocolName(loop.iteration.protocolKind) + " -> " + TypeName(loop.iteration.elementType)
				result :+ "]"
			Else
				result :+ " [range]"
			End If
		End If
		Local repeatStatement:TBoundRepeatStatement = TBoundRepeatStatement(statement)
		If repeatStatement And repeatStatement.isForever Then result :+ " [Forever]"
		result :+ "~n"

		Local childIndent:String = indent + "  "
		Local block:TBoundBlockStatement = TBoundBlockStatement(statement)
		If block Then
			For Local child:TBoundStatement = EachIn block.statements
				result :+ DumpBoundStatement(child, childIndent)
			Next
			Return result
		End If
		Local variables:TBoundVariableDeclarationStatement = TBoundVariableDeclarationStatement(statement)
		If variables Then
			For Local variable:TBoundVariable = EachIn variables.variables
				result :+ childIndent + "Variable"
				If variable.symbol Then result :+ " " + variable.symbol.name + " : " + TypeName(variable.symbol.declaredType)
				result :+ "~n"
				If variable.initializer Then result :+ DumpExpression(variable.initializer, childIndent + "  ")
			Next
			Return result
		End If
		If assignment Then
			result :+ DumpOptionalExpression(assignment.target, childIndent)
			result :+ DumpOptionalExpression(assignment.value, childIndent)
			Return result
		End If
		Local expressionStatement:TBoundExpressionStatement = TBoundExpressionStatement(statement)
		If expressionStatement Then Return result + DumpOptionalExpression(expressionStatement.expression, childIndent)
		Local returned:TBoundReturnStatement = TBoundReturnStatement(statement)
		If returned Then Return result + DumpOptionalExpression(returned.expression, childIndent)
		Local yielded:TBoundYieldStatement = TBoundYieldStatement(statement)
		If yielded Then Return result + DumpOptionalExpression(yielded.expression, childIndent)
		Local thrown:TBoundThrowStatement = TBoundThrowStatement(statement)
		If thrown Then Return result + DumpOptionalExpression(thrown.expression, childIndent)
		Local asserted:TBoundAssertStatement = TBoundAssertStatement(statement)
		If asserted Then
			result :+ DumpOptionalExpression(asserted.condition, childIndent)
			result :+ DumpOptionalExpression(asserted.message, childIndent)
			Return result
		End If
		Local released:TBoundReleaseStatement = TBoundReleaseStatement(statement)
		If released Then Return result + DumpOptionalExpression(released.expression, childIndent)
		Local conditionalIf:TBoundIfStatement = TBoundIfStatement(statement)
		If conditionalIf Then
			result :+ DumpOptionalExpression(conditionalIf.condition, childIndent)
			result :+ DumpBoundStatement(conditionalIf.thenBody, childIndent)
			For Local clause:TBoundConditionalClause = EachIn conditionalIf.elseIfClauses
				result :+ childIndent + "ElseIf~n"
				result :+ DumpOptionalExpression(clause.condition, childIndent + "  ")
				result :+ DumpBoundStatement(clause.body, childIndent + "  ")
			Next
			If conditionalIf.elseBody Then result :+ DumpBoundStatement(conditionalIf.elseBody, childIndent)
			Return result
		End If
		Local whileStatement:TBoundWhileStatement = TBoundWhileStatement(statement)
		If whileStatement Then
			result :+ DumpOptionalExpression(whileStatement.condition, childIndent)
			result :+ DumpBoundStatement(whileStatement.body, childIndent)
			Return result
		End If
		If repeatStatement Then
			result :+ DumpBoundStatement(repeatStatement.body, childIndent)
			result :+ DumpOptionalExpression(repeatStatement.condition, childIndent)
			Return result
		End If
		If loop Then
			result :+ DumpOptionalExpression(loop.target, childIndent)
			result :+ DumpOptionalExpression(loop.initialValue, childIndent)
			result :+ DumpOptionalExpression(loop.collection, childIndent)
			result :+ DumpOptionalExpression(loop.limit, childIndent)
			result :+ DumpOptionalExpression(loop.stepExpression, childIndent)
			result :+ DumpBoundStatement(loop.body, childIndent)
			Return result
		End If
		Local selected:TBoundSelectStatement = TBoundSelectStatement(statement)
		If selected Then
			result :+ DumpOptionalExpression(selected.expression, childIndent)
			For Local selectedCase:TBoundSelectCase = EachIn selected.cases
				result :+ childIndent + "Case~n"
				For Local value:TBoundExpression = EachIn selectedCase.values
					result :+ DumpExpression(value, childIndent + "  ")
				Next
				result :+ DumpBoundStatement(selectedCase.body, childIndent + "  ")
			Next
			If selected.defaultBody Then result :+ DumpBoundStatement(selected.defaultBody, childIndent)
			Return result
		End If
		Local guarded:TBoundTryStatement = TBoundTryStatement(statement)
		If guarded Then
			result :+ DumpBoundStatement(guarded.body, childIndent)
			For Local catchClause:TBoundCatchClause = EachIn guarded.catches
				result :+ childIndent + "Catch"
				If catchClause.parameter Then result :+ " " + catchClause.parameter.name + " : " + TypeName(catchClause.parameter.declaredType)
				result :+ "~n" + DumpBoundStatement(catchClause.body, childIndent + "  ")
			Next
			If guarded.finallyBody Then result :+ childIndent + "Finally~n" + DumpBoundStatement(guarded.finallyBody, childIndent + "  ")
			Return result
		End If
		Local usingStatement:TBoundUsingStatement = TBoundUsingStatement(statement)
		If usingStatement Then
			For Local resource:TBoundVariableDeclarationStatement = EachIn usingStatement.resources
				result :+ DumpBoundStatement(resource, childIndent)
			Next
			result :+ DumpBoundStatement(usingStatement.body, childIndent)
			Return result
		End If
		Local conditional:TBoundConditionalStatement = TBoundConditionalStatement(statement)
		If conditional Then
			For Local branch:TBoundConditionalBranch = EachIn conditional.branches
				result :+ childIndent + "Branch"
				If branch.syntax Then result :+ " " + branch.syntax.conditionText
				result :+ "~n" + DumpBoundStatement(branch.body, childIndent + "  ")
			Next
			Return result
		End If
		Local data:TBoundDataStatement = TBoundDataStatement(statement)
		If data Then
			For Local expression:TBoundExpression = EachIn data.expressions
				result :+ DumpExpression(expression, childIndent)
			Next
		End If
		Return result
	End Function

	Function EachInProtocolName:String(kind:Int)
		Select kind
			Case EACH_IN_PROTOCOL_ARRAY Return "Array"
			Case EACH_IN_PROTOCOL_STRING Return "String"
			Case EACH_IN_PROTOCOL_STATIC_ARRAY Return "StaticArray"
			Case EACH_IN_PROTOCOL_ITERABLE Return "IIterable"
			Case EACH_IN_PROTOCOL_ITERATOR Return "IIterator"
			Case EACH_IN_PROTOCOL_OBJECT_ENUMERATOR Return "ObjectEnumerator"
		End Select
		Return "Unknown"
	End Function

	Function DumpOptionalExpression:String(expression:TBoundExpression, indent:String)
		If Not expression Then Return ""
		Return DumpExpression(expression, indent)
	End Function

	Function TypeName:String(semanticType:TSemanticType)
		If semanticType Then Return semanticType.DisplayName()
		Return "?"
	End Function

	Function DumpExpression:String(expression:TBoundExpression, indent:String)
		If Not expression Then Return indent + "<missing bound expression>~n"
		Local result:String = indent + KindName(expression.boundKind)
		If expression.semanticType Then result :+ " : " + expression.semanticType.DisplayName()
		If expression.isSynthetic Then result :+ " [synthetic]"
		Local literal:TBoundLiteralExpression = TBoundLiteralExpression(expression)
		If literal And literal.token Then result :+ " " + literal.token.text
		Local symbol:TBoundSymbolExpression = TBoundSymbolExpression(expression)
		If symbol And symbol.symbol Then result :+ " " + symbol.symbol.QualifiedName()
		Local selfExpression:TBoundSelfExpression = TBoundSelfExpression(expression)
		If selfExpression And selfExpression.implicitReceiver Then result :+ " [implicit-receiver]"
		If selfExpression And selfExpression.isSuper Then result :+ " [super-receiver]"
		Local routine:TBoundRoutineReferenceExpression = TBoundRoutineReferenceExpression(expression)
		If routine And routine.routine Then result :+ " " + routine.routine.QualifiedName()
		Local functionLiteral:TBoundFunctionLiteralExpression = TBoundFunctionLiteralExpression(expression)
		If functionLiteral And functionLiteral.routine Then result :+ " " + functionLiteral.routine.QualifiedName()
		If functionLiteral And functionLiteral.capturesSelf Then result :+ " [captures-self]"
		Local call:TBoundCallExpression = TBoundCallExpression(expression)
		If call And call.resolvedCall And call.resolvedCall.routine Then result :+ " -> " + call.resolvedCall.routine.QualifiedName()
		If call And call.resolvedCall And call.resolvedCall.isDeferred Then result :+ " -> <deferred overload set>"
		Local member:TBoundMemberExpression = TBoundMemberExpression(expression)
		If member And member.access And member.access.member Then
			result :+ " ." + member.access.member.name
			If member.access.implicitPointerDereference Then result :+ " [implicit-deref]"
		End If
		Local indexed:TBoundIndexExpression = TBoundIndexExpression(expression)
		If indexed And indexed.access Then result :+ " [" + IndexKindName(indexed.access.accessKind) + "]"
		Local slice:TBoundSliceExpression = TBoundSliceExpression(expression)
		Local unary:TBoundUnaryExpression = TBoundUnaryExpression(expression)
		If unary Then
			result :+ " " + unary.operatorText
			If unary.isTypeOperand Then result :+ " [type " + TypeName(unary.operandSemanticType) + "]"
		End If
		Local binary:TBoundBinaryExpression = TBoundBinaryExpression(expression)
		If binary Then result :+ " " + binary.operatorText
		Local conversion:TBoundConversionExpression = TBoundConversionExpression(expression)
		If conversion Then
			If conversion.implicitConversion Then result :+ " [implicit " Else result :+ " [explicit "
			result :+ ConversionKindName(conversion.conversionKind) + "]"
		End If
		Local contextualArray:TBoundArrayLiteralExpression = TBoundArrayLiteralExpression(expression)
		If contextualArray And contextualArray.contextualElementType Then result :+ " [elements " + TypeName(contextualArray.contextualElementType) + "]"
		result :+ "~n"

		Local childIndent:String = indent + "  "
		If call Then
			If call.receiver Then result :+ DumpExpression(call.receiver, childIndent)
			result :+ DumpExpression(call.callee, childIndent)
			For Local argument:TBoundExpression = EachIn call.arguments
				result :+ DumpExpression(argument, childIndent)
			Next
		Else If routine And routine.receiver Then
			result :+ DumpExpression(routine.receiver, childIndent)
		Else If symbol And symbol.receiver Then
			result :+ DumpExpression(symbol.receiver, childIndent)
		Else If member Then
			result :+ DumpExpression(member.receiver, childIndent)
		Else If indexed Then
			result :+ DumpExpression(indexed.receiver, childIndent)
			For Local index:TBoundExpression = EachIn indexed.indexes
				result :+ DumpExpression(index, childIndent)
			Next
		Else If slice Then
			result :+ DumpExpression(slice.receiver, childIndent)
			result :+ DumpExpression(slice.lowerBound, childIndent)
			result :+ DumpExpression(slice.upperBound, childIndent)
		Else If unary Then
			result :+ DumpExpression(unary.operand, childIndent)
		Else If binary Then
			result :+ DumpExpression(binary.left, childIndent)
			result :+ DumpExpression(binary.right, childIndent)
		Else If conversion Then
			result :+ DumpExpression(conversion.operand, childIndent)
		Else If functionLiteral And functionLiteral.body Then
			result :+ DumpBoundStatement(functionLiteral.body, childIndent)
		Else
			Local creation:TBoundNewExpression = TBoundNewExpression(expression)
			If creation Then
				For Local argument:TBoundExpression = EachIn creation.arguments
					result :+ DumpExpression(argument, childIndent)
				Next
				For Local dimension:TBoundExpression = EachIn creation.dimensions
					result :+ DumpExpression(dimension, childIndent)
				Next
			Else
				Local arrayLiteral:TBoundArrayLiteralExpression = TBoundArrayLiteralExpression(expression)
				If arrayLiteral Then
					For Local element:TBoundExpression = EachIn arrayLiteral.elements
						result :+ DumpExpression(element, childIndent)
					Next
				Else
					Local passthrough:TBoundPassthroughExpression = TBoundPassthroughExpression(expression)
					If passthrough Then result :+ DumpExpression(passthrough.operand, childIndent)
				End If
			End If
		End If
		Return result
	End Function

	Function KindName:String(kind:Int)
		Select kind
			Case BOUND_EXPRESSION_ERROR Return "BoundError"
			Case BOUND_EXPRESSION_LITERAL Return "BoundLiteral"
			Case BOUND_EXPRESSION_SYMBOL Return "BoundSymbol"
			Case BOUND_EXPRESSION_ROUTINE_REFERENCE Return "BoundRoutineReference"
			Case BOUND_EXPRESSION_CALL Return "BoundCall"
			Case BOUND_EXPRESSION_MEMBER Return "BoundMember"
			Case BOUND_EXPRESSION_INDEX Return "BoundIndex"
			Case BOUND_EXPRESSION_UNARY Return "BoundUnary"
			Case BOUND_EXPRESSION_BINARY Return "BoundBinary"
			Case BOUND_EXPRESSION_NEW Return "BoundNew"
			Case BOUND_EXPRESSION_ARRAY_LITERAL Return "BoundArrayLiteral"
			Case BOUND_EXPRESSION_CONVERSION Return "BoundConversion"
			Case BOUND_EXPRESSION_PASSTHROUGH Return "BoundPassthrough"
			Case BOUND_EXPRESSION_SLICE Return "BoundSlice"
			Case BOUND_EXPRESSION_OMITTED_ARGUMENT Return "BoundOmittedArgument"
			Case BOUND_EXPRESSION_SELF Return "BoundSelf"
			Case BOUND_EXPRESSION_FUNCTION_LITERAL Return "BoundFunctionLiteral"
		End Select
		Return "BoundExpression"
	End Function

	Function StatementKindName:String(kind:Int)
		Select kind
			Case BOUND_STATEMENT_ERROR Return "BoundErrorStatement"
			Case BOUND_STATEMENT_BLOCK Return "BoundBlock"
			Case BOUND_STATEMENT_VARIABLE_DECLARATION Return "BoundVariableDeclaration"
			Case BOUND_STATEMENT_ASSIGNMENT Return "BoundAssignment"
			Case BOUND_STATEMENT_EXPRESSION Return "BoundExpressionStatement"
			Case BOUND_STATEMENT_RETURN Return "BoundReturn"
			Case BOUND_STATEMENT_THROW Return "BoundThrow"
			Case BOUND_STATEMENT_ASSERT Return "BoundAssert"
			Case BOUND_STATEMENT_IF Return "BoundIf"
			Case BOUND_STATEMENT_WHILE Return "BoundWhile"
			Case BOUND_STATEMENT_REPEAT Return "BoundRepeat"
			Case BOUND_STATEMENT_FOR Return "BoundFor"
			Case BOUND_STATEMENT_SELECT Return "BoundSelect"
			Case BOUND_STATEMENT_TRY Return "BoundTry"
			Case BOUND_STATEMENT_USING Return "BoundUsing"
			Case BOUND_STATEMENT_CONDITIONAL Return "BoundConditional"
			Case BOUND_STATEMENT_DATA Return "BoundData"
			Case BOUND_STATEMENT_FLOW Return "BoundFlow"
		End Select
		Return "BoundStatement"
	End Function

	Function IndexKindName:String(kind:Int)
		Select kind
			Case INDEX_ACCESS_ARRAY Return "array-index"
			Case INDEX_ACCESS_POINTER Return "pointer-index"
			Case INDEX_ACCESS_OPERATOR Return "operator-index"
			Case INDEX_ACCESS_STATIC_ARRAY Return "static-array-index"
			Case INDEX_ACCESS_STRING Return "string-index"
			Case INDEX_ACCESS_RANGE_ARRAY Return "array-range-slice"
			Case INDEX_ACCESS_RANGE_STRING Return "string-range-slice"
		End Select
		Return "unknown-index"
	End Function

	Function ConversionKindName:String(kind:Int)
		Select kind
			Case CONVERSION_NONE Return "unknown"
			Case CONVERSION_IDENTITY Return "identity"
			Case CONVERSION_NUMERIC_WIDENING Return "numeric-widening"
			Case CONVERSION_REFERENCE Return "reference"
			Case CONVERSION_NULL Return "null"
			Case CONVERSION_DEFAULT_VALUE Return "default"
			Case CONVERSION_ERROR Return "error"
			Case CONVERSION_CONSTANT Return "constant"
			Case CONVERSION_EXPLICIT Return "explicit"
			Case CONVERSION_NUMERIC_NARROWING Return "numeric-narrowing"
			Case CONVERSION_NUMERIC_TO_STRING Return "numeric-to-string"
			Case CONVERSION_ENUM_TO_STRING Return "enum-to-string"
			Case CONVERSION_ENUM_TO_UNDERLYING Return "enum-to-underlying"
			Case CONVERSION_STRING_TO_NUMERIC Return "string-to-numeric"
			Case CONVERSION_ARRAY_TO_POINTER Return "array-to-pointer"
			Case CONVERSION_POINTER_TO_BYTE_POINTER Return "pointer-to-byte-pointer"
			Case CONVERSION_BYTE_POINTER_TO_POINTER Return "byte-pointer-to-pointer"
			Case CONVERSION_ARRAY_LITERAL Return "contextual-array-literal"
			Case CONVERSION_STRING_TO_BYTE_POINTER Return "string-to-byte-pointer"
			Case CONVERSION_CONTEXTUAL_NUMERIC_EXPRESSION Return "contextual-numeric-expression"
			Case CONVERSION_CALLABLE_VARIANCE Return "callable-variance"
			Case CONVERSION_VAR_REFERENCE Return "var-reference"
		End Select
		Return "conversion"
	End Function
End Type
