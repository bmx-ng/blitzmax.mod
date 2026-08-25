' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "interface_model.bmx"
Import "documentation_model.bmx"
Import "declaration_metadata.bmx"
Import "snapshot_model.bmx"
Import "syntax.bmx"

Const SYMBOL_TYPE:Int = 1
Const SYMBOL_STRUCT:Int = 2
Const SYMBOL_INTERFACE:Int = 3
Const SYMBOL_ENUM:Int = 4
Const SYMBOL_ROUTINE:Int = 5
Const SYMBOL_FIELD:Int = 6
Const SYMBOL_GLOBAL:Int = 7
Const SYMBOL_CONST:Int = 8
Const SYMBOL_LOCAL:Int = 9
Const SYMBOL_PARAMETER:Int = 10
Const SYMBOL_TYPE_PARAMETER:Int = 11
Const SYMBOL_ENUM_MEMBER:Int = 12
Const SYMBOL_CATCH_PARAMETER:Int = 13
Const SYMBOL_MODULE:Int = 14

Const SYMBOL_NAMESPACE_TYPE:Int = 1
Const SYMBOL_NAMESPACE_VALUE:Int = 2
Const SYMBOL_NAMESPACE_ROUTINE:Int = 3

Const SCOPE_COMPILATION_UNIT:Int = 1
Const SCOPE_TYPE:Int = 2
Const SCOPE_ENUM:Int = 3
Const SCOPE_ROUTINE:Int = 4
Const SCOPE_BLOCK:Int = 5
Const SCOPE_LOOP:Int = 6
Const SCOPE_CATCH:Int = 7
Const SCOPE_USING:Int = 8
Const SCOPE_CONDITIONAL_BRANCH:Int = 9
Const SCOPE_INTERFACE_MODULE:Int = 10

Const SEMANTIC_TYPE_BUILTIN:Int = 1
Const SEMANTIC_TYPE_NAMED:Int = 2
Const SEMANTIC_TYPE_TYPE_PARAMETER:Int = 3
Const SEMANTIC_TYPE_POINTER:Int = 4
Const SEMANTIC_TYPE_ARRAY:Int = 5
Const SEMANTIC_TYPE_ERROR:Int = 6
Const SEMANTIC_TYPE_CALLABLE:Int = 7
Const SEMANTIC_TYPE_STATIC_ARRAY:Int = 8
Const SEMANTIC_TYPE_CLOSURE:Int = 9

Const PARAMETER_PASS_VALUE:Int = 1
Const PARAMETER_PASS_VAR:Int = 2
Const INTERFACE_METHOD_NONE:Int = 0
Const INTERFACE_METHOD_ABSTRACT:Int = 1
Const INTERFACE_METHOD_DEFAULT:Int = 2
Const INTERFACE_METHOD_REABSTRACT:Int = 3
Const NATIVE_STRING_NONE:Int = 0
Const NATIVE_STRING_UTF8:Int = 1
Const NATIVE_STRING_UTF16:Int = 2

Const INDEX_ACCESS_ARRAY:Int = 1
Const INDEX_ACCESS_POINTER:Int = 2
Const INDEX_ACCESS_OPERATOR:Int = 3
Const INDEX_ACCESS_STATIC_ARRAY:Int = 4
Const INDEX_ACCESS_STRING:Int = 5
Const INDEX_ACCESS_RANGE_ARRAY:Int = 6
Const INDEX_ACCESS_RANGE_STRING:Int = 7

Const BOUND_EXPRESSION_ERROR:Int = 0
Const BOUND_EXPRESSION_LITERAL:Int = 1
Const BOUND_EXPRESSION_SYMBOL:Int = 2
Const BOUND_EXPRESSION_ROUTINE_REFERENCE:Int = 3
Const BOUND_EXPRESSION_CALL:Int = 4
Const BOUND_EXPRESSION_MEMBER:Int = 5
Const BOUND_EXPRESSION_INDEX:Int = 6
Const BOUND_EXPRESSION_UNARY:Int = 7
Const BOUND_EXPRESSION_BINARY:Int = 8
Const BOUND_EXPRESSION_NEW:Int = 9
Const BOUND_EXPRESSION_ARRAY_LITERAL:Int = 10
Const BOUND_EXPRESSION_CONVERSION:Int = 11
Const BOUND_EXPRESSION_PASSTHROUGH:Int = 12
Const BOUND_EXPRESSION_SLICE:Int = 13
Const BOUND_EXPRESSION_OMITTED_ARGUMENT:Int = 14
Const BOUND_EXPRESSION_SELF:Int = 15
Const BOUND_EXPRESSION_FUNCTION_LITERAL:Int = 16

Const BOUND_STATEMENT_ERROR:Int = 0
Const BOUND_STATEMENT_BLOCK:Int = 1
Const BOUND_STATEMENT_VARIABLE_DECLARATION:Int = 2
Const BOUND_STATEMENT_ASSIGNMENT:Int = 3
Const BOUND_STATEMENT_EXPRESSION:Int = 4
Const BOUND_STATEMENT_RETURN:Int = 5
Const BOUND_STATEMENT_THROW:Int = 6
Const BOUND_STATEMENT_ASSERT:Int = 7
Const BOUND_STATEMENT_IF:Int = 8
Const BOUND_STATEMENT_WHILE:Int = 9
Const BOUND_STATEMENT_REPEAT:Int = 10
Const BOUND_STATEMENT_FOR:Int = 11
Const BOUND_STATEMENT_SELECT:Int = 12
Const BOUND_STATEMENT_TRY:Int = 13
Const BOUND_STATEMENT_USING:Int = 14
Const BOUND_STATEMENT_CONDITIONAL:Int = 15
Const BOUND_STATEMENT_DATA:Int = 16
Const BOUND_STATEMENT_FLOW:Int = 17
Const BOUND_STATEMENT_RELEASE:Int = 18
Const BOUND_STATEMENT_YIELD:Int = 19

Const CONTROL_FLOW_EDGE_FALLTHROUGH:Int = 1
Const CONTROL_FLOW_EDGE_TRUE:Int = 2
Const CONTROL_FLOW_EDGE_FALSE:Int = 3
Const CONTROL_FLOW_EDGE_CASE:Int = 4
Const CONTROL_FLOW_EDGE_LOOP_BACK:Int = 5
Const CONTROL_FLOW_EDGE_EXIT:Int = 6
Const CONTROL_FLOW_EDGE_CONTINUE:Int = 7
Const CONTROL_FLOW_EDGE_RETURN:Int = 8
Const CONTROL_FLOW_EDGE_THROW:Int = 9
Const CONTROL_FLOW_EDGE_APPLICATION_END:Int = 10
Const CONTROL_FLOW_EDGE_EXCEPTION:Int = 11
Const CONTROL_FLOW_EDGE_OUT_OF_DATA:Int = 12

Const DATA_READ_CONVERSION_NONE:Int = 0
Const DATA_READ_CONVERSION_INT:Int = 1
Const DATA_READ_CONVERSION_UINT:Int = 2
Const DATA_READ_CONVERSION_FLOAT:Int = 3
Const DATA_READ_CONVERSION_DOUBLE:Int = 4
Const DATA_READ_CONVERSION_LONG:Int = 5
Const DATA_READ_CONVERSION_ULONG:Int = 6
Const DATA_READ_CONVERSION_SIZET:Int = 7
Const DATA_READ_CONVERSION_LONGINT:Int = 8
Const DATA_READ_CONVERSION_ULONGINT:Int = 9
Const DATA_READ_CONVERSION_STRING:Int = 10

Const CONSTANT_VALUE_INTEGER:Int = 1
Const CONSTANT_VALUE_FLOAT:Int = 2
Const CONSTANT_VALUE_STRING:Int = 3
Const CONSTANT_VALUE_NULL:Int = 4
Const CONSTANT_VALUE_CALLABLE:Int = 5

Const CALLING_CONVENTION_C:String = "c"
Const CALLING_CONVENTION_STDCALL:String = "stdcall"

Type TCallingConventionResolver
	Function WrittenName:String(token:TSyntaxToken)
		If Not token Then Return ""
		Local written:String = token.text.Trim().ToLower()
		If written.length >= 2 And written[0] = 34 And written[written.length - 1] = 34 Then written = written[1..written.length - 1]
		Return written
	End Function

	Function IsRecognized:Int(token:TSyntaxToken)
		If Not token Then Return True
		Select WrittenName(token)
			Case "c", "blitz", "macos", "linux", "nx", "win32", "os", "w", "stdcall"
				Return True
		End Select
		Return False
	End Function

	Function Resolve:String(token:TSyntaxToken, targetPlatform:String)
		If Not token Then Return CALLING_CONVENTION_C
		Local written:String = WrittenName(token)
		If written = "w" Or written = "stdcall" Then Return CALLING_CONVENTION_STDCALL
		If written = "win32" Or written = "os" Then
			If targetPlatform.ToLower() = "win32" Then Return CALLING_CONVENTION_STDCALL
			Return CALLING_CONVENTION_C
		End If
		Return CALLING_CONVENTION_C
	End Function

	Function RoutineConvention:String(declaration:TRoutineDeclarationSyntax, inheritedConvention:String, targetPlatform:String)
		If declaration And declaration.signature Then
			Local afterAssignment:Int
			For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
				If token.text = "=" Then afterAssignment = True; Continue
				If afterAssignment Then Continue
				If token.text.ToLower() = "stdcall" Then Return CALLING_CONVENTION_STDCALL
				If token.kind = TOKEN_STRING_LITERAL Then Return Resolve(token, targetPlatform)
			Next
		End If
		If inheritedConvention.length Then Return inheritedConvention
		Return CALLING_CONVENTION_C
	End Function
End Type

Type TSemanticType Abstract
	Field kind:Int

	Method DisplayName:String() Abstract
End Type

Type TBuiltinSemanticType Extends TSemanticType
	Field name:String
	Field runtimeSymbol:TSymbol

	Method DisplayName:String()
		Return name
	End Method
End Type

Type TNamedSemanticType Extends TSemanticType
	Field symbol:TSymbol
	Field typeArguments:TSemanticType[] = New TSemanticType[0]

	Method DisplayName:String()
		Local result:String = "<unresolved type>"
		If symbol Then result = symbol.QualifiedName()
		If typeArguments.length Then
			result :+ "<"
			For Local index:Int = 0 Until typeArguments.length
				If index Then result :+ ", "
				If typeArguments[index] Then result :+ typeArguments[index].DisplayName() Else result :+ "<unresolved>"
			Next
			result :+ ">"
		End If
		Return result
	End Method
End Type

Type TTypeParameterSemanticType Extends TSemanticType
	Field symbol:TSymbol

	Method DisplayName:String()
		If symbol Then Return symbol.name
		Return "<unresolved type parameter>"
	End Method
End Type

Type TPointerSemanticType Extends TSemanticType
	Field elementType:TSemanticType

	Method DisplayName:String()
		If elementType Then Return elementType.DisplayName() + " Ptr"
		Return "<unresolved> Ptr"
	End Method
End Type

Type TArraySemanticType Extends TSemanticType
	Field elementType:TSemanticType
	Field rank:Int

	Method DisplayName:String()
		Local result:String = "<unresolved>["
		If elementType Then result = elementType.DisplayName() + "["
		For Local index:Int = 1 Until rank
			result :+ ","
		Next
		Return result + "]"
	End Method
End Type

Type TStaticArraySemanticType Extends TSemanticType
	Field elementType:TSemanticType
	Field length:Long
	Field boundSyntax:TStaticArrayBoundSyntax

	Method DisplayName:String()
		Local lengthText:String = "?"
		If length > 0 Then lengthText = length
		Local elementName:String = "<unresolved>"
		If elementType Then elementName = elementType.DisplayName()
		Return "StaticArray " + elementName + "[" + lengthText + "]"
	End Method
End Type

Type TErrorSemanticType Extends TSemanticType
	Field writtenName:String

	Method DisplayName:String()
		If writtenName.length Then Return "<unresolved " + writtenName + ">"
		Return "<error type>"
	End Method
End Type

Type TCallableSemanticType Extends TSemanticType
	Field parameterTypes:TSemanticType[] = New TSemanticType[0]
	Field parameterModes:Int[] = New Int[0]
	Field returnType:TSemanticType
	Field routine:TSymbol
	Field callingConvention:String = CALLING_CONVENTION_C

	Method DisplayName:String()
		Local result:String
		If returnType And returnType.DisplayName().ToLower() <> "void" Then result = returnType.DisplayName()
		result :+ "("
		For Local index:Int = 0 Until parameterTypes.length
			If index Then result :+ ", "
			If parameterTypes[index] Then result :+ parameterTypes[index].DisplayName() Else result :+ "<unresolved>"
			If index < parameterModes.length And parameterModes[index] = PARAMETER_PASS_VAR Then result :+ " Var"
		Next
		Return result + ")"
	End Method
End Type

' A managed callable is deliberately distinct from BlitzMax's existing thin
' function-pointer type.  Its signature remains fully typed even though every
' managed closure shares one erased runtime representation.
Type TClosureSemanticType Extends TSemanticType
	Field signature:TCallableSemanticType
	Field parameterNames:String[] = New String[0]

	Method DisplayName:String()
		If signature Then
			Local result:String = "Closure<"
			If signature.returnType And signature.returnType.DisplayName().ToLower() <> "void" Then result :+ signature.returnType.DisplayName()
			result :+ "("
			For Local index:Int = 0 Until signature.parameterTypes.length
				If index Then result :+ ", "
				If index < parameterNames.length And parameterNames[index].length Then result :+ parameterNames[index] Else result :+ "arg" + index
				result :+ ":"
				If signature.parameterTypes[index] Then result :+ signature.parameterTypes[index].DisplayName() Else result :+ "<unresolved>"
				If index < signature.parameterModes.length And signature.parameterModes[index] = PARAMETER_PASS_VAR Then result :+ " Var"
			Next
			Return result + ")>"
		End If
		Return "Closure<<unresolved>()>"
	End Method
End Type

Type TSemanticParameter
	Field symbol:TSymbol
	Field semanticType:TSemanticType
	Field passingMode:Int = PARAMETER_PASS_VALUE
	Field nativeStringEncoding:Int
	Field optional:Int
	Field defaultValue:TConstantValue
End Type

Type TInheritanceEdge
	Field syntax:TTypeReferenceSyntax
	Field semanticType:TSemanticType
	Field isImplicit:Int
End Type

Type TGenericConstraintInfo
	Field syntax:TGenericConstraintSyntax
	Field parameterSymbol:TSymbol
	Field bounds:TSemanticType[] = New TSemanticType[0]
End Type

Type TTypeInheritanceInfo
	Field symbol:TSymbol
	Field baseEdges:TInheritanceEdge[] = New TInheritanceEdge[0]
	Field interfaceEdges:TInheritanceEdge[] = New TInheritanceEdge[0]
	Field constraints:TGenericConstraintInfo[] = New TGenericConstraintInfo[0]
End Type

Type TResolvedCall
	Field routine:TSymbol
	' Open generic bodies can retain an overload set until their type
	' parameters are substituted by a concrete instance.
	Field isDeferred:Int
	Field candidates:TSymbol[] = New TSymbol[0]
	Field argumentTypes:TSemanticType[] = New TSemanticType[0]
	Field typeArguments:TSemanticType[] = New TSemanticType[0]
	Field parameterTypes:TSemanticType[] = New TSemanticType[0]
	Field omittedArguments:Int[] = New Int[0]
	Field returnType:TSemanticType
End Type

' Editor-facing callable information captured while the expression binder has
' the exact overload set, constructed receiver, and argument types available.
' It remains separate from TResolvedCall: an incomplete or temporarily invalid
' call can have useful signatures without pretending that overload resolution
' succeeded for compilation.
Type TCallSignatureCandidate
	Field routine:TSymbol
	Field callable:TCallableSemanticType
	Field closure:TClosureSemanticType
	Field containingSubstitutions:TMap
	Field parameterTypes:TSemanticType[] = New TSemanticType[0]
	Field returnType:TSemanticType
	Field compatible:Int
	Field score:Int = -1
	Field selected:Int
End Type

Type TCallSignatureSet
	Field candidates:TCallSignatureCandidate[] = New TCallSignatureCandidate[0]
End Type

Const EACH_IN_PROTOCOL_ARRAY:Int = 1
Const EACH_IN_PROTOCOL_STRING:Int = 2
Const EACH_IN_PROTOCOL_STATIC_ARRAY:Int = 3
Const EACH_IN_PROTOCOL_ITERABLE:Int = 4
Const EACH_IN_PROTOCOL_ITERATOR:Int = 5
Const EACH_IN_PROTOCOL_OBJECT_ENUMERATOR:Int = 6

Type TResolvedEachIn
	Field protocolKind:Int
	Field collectionType:TSemanticType
	Field iteratorType:TSemanticType
	Field elementType:TSemanticType
	Field iteratorFactory:TResolvedCall
	Field advance:TResolvedCall
	Field current:TResolvedCall
	Field deconstructionType:TNamedSemanticType
	Field componentTypes:TSemanticType[] = New TSemanticType[0]
	Field deconstruct:TResolvedCall
End Type

Type TResolvedIndexAccess
	Field accessKind:Int
	Field receiverType:TSemanticType
	Field resultType:TSemanticType
	Field resolvedCall:TResolvedCall
	Field rangeStartRoutine:TSymbol
	Field rangeEndRoutine:TSymbol
End Type

Type TResolvedMemberAccess
	Field member:TSymbol
	Field receiverType:TSemanticType
	Field lookupType:TSemanticType
	Field implicitPointerDereference:Int
End Type

Type TBoundExpression
	Field boundKind:Int
	Field syntax:TExpressionSyntax
	Field semanticType:TSemanticType
	Field isSynthetic:Int
End Type

Type TBoundErrorExpression Extends TBoundExpression
End Type

Type TBoundLiteralExpression Extends TBoundExpression
	Field token:TSyntaxToken
End Type

Type TBoundSymbolExpression Extends TBoundExpression
	Field symbol:TSymbol
	' Non-null when an unqualified field reference is bound through implicit Self.
	Field receiver:TBoundExpression
End Type

Type TBoundSelfExpression Extends TBoundExpression
	Field implicitReceiver:Int
	Field isSuper:Int
	Field qualifiedSuperType:TSemanticType
End Type

Type TBoundRoutineReferenceExpression Extends TBoundExpression
	Field routine:TSymbol
	' Object captured by an instance Method reference. Null for free routines and
	' Type Functions, whose callable representation remains a thin entry point.
	Field receiver:TBoundExpression
	' Closed routine type arguments for an explicit specialization such as
	' Identity<Int>. These select a concrete generic routine entry point.
	Field typeArguments:TSemanticType[] = New TSemanticType[0]
	' Closed owner type for a Function selected through a generic Type
	' qualifier, such as TFunctions<Int>.Transform.
	Field staticReceiverType:TSemanticType
End Type

Type TBoundFunctionLiteralExpression Extends TBoundExpression
	Field routine:TSymbol
	Field body:TBoundBlockStatement
	' Lexical locals and value parameters lifted into the managed Closure
	' environment. Their source symbols remain the language-level identities;
	' storage selection belongs to typed IR lowering.
	Field captures:TSymbol[] = New TSymbol[0]
	' Instance closures capture the managed receiver as a distinct lexical
	' value. Self has no source TSymbol, so retain its closed semantic type
	' separately from ordinary Local and parameter captures.
	Field capturesSelf:Int
	Field capturedSelfType:TSemanticType
End Type

Type TBoundOmittedArgumentExpression Extends TBoundExpression
	Field parameter:TSemanticParameter
End Type

Type TBoundCallExpression Extends TBoundExpression
	Field resolvedCall:TResolvedCall
	Field callee:TBoundExpression
	' Object receiver retained independently from the callable reference.
	' Besides Methods, BlitzMax permits a Type Function to be selected through
	' an object so its class-table slot can provide the most-derived function.
	' Null for free routines and type-qualified Type Function calls.
	Field receiver:TBoundExpression
	' Constructed owner selected by syntax such as TBox<Int>.Create(). This is
	' type information only: a Type Function remains receiver-free at runtime.
	Field staticReceiverType:TSemanticType
	Field arguments:TBoundExpression[] = New TBoundExpression[0]
End Type

Type TBoundMemberExpression Extends TBoundExpression
	Field receiver:TBoundExpression
	Field access:TResolvedMemberAccess
End Type

Type TBoundIndexExpression Extends TBoundExpression
	Field receiver:TBoundExpression
	Field indexes:TBoundExpression[] = New TBoundExpression[0]
	Field access:TResolvedIndexAccess
End Type

Type TBoundSliceExpression Extends TBoundExpression
	Field receiver:TBoundExpression
	Field lowerBound:TBoundExpression
	Field upperBound:TBoundExpression
	Field lowerFromEnd:Int
	Field upperFromEnd:Int
End Type

Type TBoundUnaryExpression Extends TBoundExpression
	Field operatorText:String
	Field operand:TBoundExpression
	Field operandSemanticType:TSemanticType
	Field isTypeOperand:Int
	Field resolvedCall:TResolvedCall
End Type

Type TIntrinsicOperandBinding
	Field semanticType:TSemanticType
	Field isTypeOperand:Int
End Type

Type TBoundBinaryExpression Extends TBoundExpression
	Field operatorText:String
	Field left:TBoundExpression
	Field right:TBoundExpression
	Field resolvedCall:TResolvedCall
End Type

Type TBoundNewExpression Extends TBoundExpression
	Field createdType:TSemanticType
	Field instanceExpression:TBoundExpression
	Field arguments:TBoundExpression[] = New TBoundExpression[0]
	Field dimensions:TBoundExpression[] = New TBoundExpression[0]
	Field dimensionRanks:Int[] = New Int[0]
	Field resolvedConstructor:TResolvedCall
End Type

Type TBoundArrayLiteralExpression Extends TBoundExpression
	Field elements:TBoundExpression[] = New TBoundExpression[0]
	Field contextualElementType:TSemanticType
	Field conversionKind:Int
End Type

Type TBoundConversionExpression Extends TBoundExpression
	Field operand:TBoundExpression
	Field conversionKind:Int
	Field implicitConversion:Int
End Type

Type TBoundPassthroughExpression Extends TBoundExpression
	Field operand:TBoundExpression
End Type

Type TBoundStatement
	Field boundKind:Int
	Field syntax:TSyntaxNode
End Type

Type TBoundErrorStatement Extends TBoundStatement
End Type

Type TBoundBlockStatement Extends TBoundStatement
	Field statements:TBoundStatement[] = New TBoundStatement[0]
End Type

Type TBoundVariable
	Field symbol:TSymbol
	Field initializer:TBoundExpression
	Field arrayDimensions:TBoundExpression[] = New TBoundExpression[0]
End Type

Type TBoundVariableDeclarationStatement Extends TBoundStatement
	Field variables:TBoundVariable[] = New TBoundVariable[0]
End Type

Type TBoundAssignmentStatement Extends TBoundStatement
	Field target:TBoundExpression
	Field value:TBoundExpression
	Field operatorText:String
	Field resolvedCall:TResolvedCall
	Field indexAccess:TResolvedIndexAccess
End Type

Type TBoundExpressionStatement Extends TBoundStatement
	Field expression:TBoundExpression
End Type

Type TBoundReturnStatement Extends TBoundStatement
	Field expression:TBoundExpression
End Type

Type TBoundYieldStatement Extends TBoundStatement
	Field expression:TBoundExpression
End Type

Type TBoundThrowStatement Extends TBoundStatement
	Field expression:TBoundExpression
End Type

Type TBoundAssertStatement Extends TBoundStatement
	Field condition:TBoundExpression
	Field message:TBoundExpression
End Type

Type TBoundReleaseStatement Extends TBoundStatement
	Field expression:TBoundExpression
End Type

Type TBoundConditionalClause
	Field syntax:TSyntaxNode
	Field condition:TBoundExpression
	Field body:TBoundBlockStatement
End Type

Type TBoundIfStatement Extends TBoundStatement
	Field condition:TBoundExpression
	Field thenBody:TBoundBlockStatement
	Field elseIfClauses:TBoundConditionalClause[] = New TBoundConditionalClause[0]
	Field elseBody:TBoundBlockStatement
End Type

Type TBoundWhileStatement Extends TBoundStatement
	Field condition:TBoundExpression
	Field body:TBoundBlockStatement
End Type

Type TBoundRepeatStatement Extends TBoundStatement
	Field body:TBoundBlockStatement
	Field condition:TBoundExpression
	Field isForever:Int
End Type

Type TBoundForStatement Extends TBoundStatement
	Field loopVariable:TSymbol
	Field deconstructionVariables:TSymbol[] = New TSymbol[0]
	Field target:TBoundExpression
	Field initialValue:TBoundExpression
	Field collection:TBoundExpression
	Field limit:TBoundExpression
	Field stepExpression:TBoundExpression
	Field isEachIn:Int
	Field iteration:TResolvedEachIn
	Field body:TBoundBlockStatement
End Type

Type TBoundSelectCase
	Field syntax:TSyntaxNode
	Field values:TBoundExpression[] = New TBoundExpression[0]
	Field constantValues:TConstantValue[] = New TConstantValue[0]
	Field body:TBoundBlockStatement
End Type

Type TBoundSelectStatement Extends TBoundStatement
	Field expression:TBoundExpression
	Field cases:TBoundSelectCase[] = New TBoundSelectCase[0]
	Field defaultBody:TBoundBlockStatement
End Type

Type TBoundCatchClause
	Field syntax:TCatchClauseSyntax
	Field parameter:TSymbol
	Field body:TBoundBlockStatement
End Type

Type TBoundTryStatement Extends TBoundStatement
	Field body:TBoundBlockStatement
	Field catches:TBoundCatchClause[] = New TBoundCatchClause[0]
	Field finallyBody:TBoundBlockStatement
End Type

Type TBoundUsingStatement Extends TBoundStatement
	Field resources:TBoundVariableDeclarationStatement[] = New TBoundVariableDeclarationStatement[0]
	Field body:TBoundBlockStatement
End Type

Type TBoundConditionalBranch
	Field syntax:TConditionalBranchSyntax
	Field body:TBoundBlockStatement
End Type

Type TBoundConditionalStatement Extends TBoundStatement
	Field branches:TBoundConditionalBranch[] = New TBoundConditionalBranch[0]
End Type

Type TBoundDataStatement Extends TBoundStatement
	Field expressions:TBoundExpression[] = New TBoundExpression[0]
End Type

Type TBoundFlowStatement Extends TBoundStatement
	Field expression:TBoundExpression
End Type

Type TControlFlowBlock
	Field id:Int
	Field statement:TBoundStatement
	Field isEntry:Int
	Field isExit:Int
	Field isReachable:Int
	Field incoming:TControlFlowEdge[] = New TControlFlowEdge[0]
	Field outgoing:TControlFlowEdge[] = New TControlFlowEdge[0]
End Type

Type TControlFlowEdge
	Field source:TControlFlowBlock
	Field target:TControlFlowBlock
	Field kind:Int
	Field condition:TBoundExpression
End Type

Type TControlFlowGraph
	Field routine:TSymbol
	Field entryBlock:TControlFlowBlock
	Field exitBlock:TControlFlowBlock
	Field blocks:TControlFlowBlock[] = New TControlFlowBlock[0]
	Field edges:TControlFlowEdge[] = New TControlFlowEdge[0]
	Field canFallThrough:Int
	Field allPathsTerminate:Int
End Type

Type TDataItem
	Field index:Int
	Field definition:TDataDefinition
	Field syntax:TExpressionSyntax
	Field expression:TBoundExpression
	Field semanticType:TSemanticType
	Field constantValue:TConstantValue
End Type

Type TDataDefinition
	Field syntax:TDefDataStatementSyntax
	Field labelName:String
	Field normalizedLabel:String
	Field labelToken:TSyntaxToken
	Field startIndex:Int
	Field items:TDataItem[] = New TDataItem[0]
End Type

Type TDataRestoreBinding
	Field syntax:TRestoreDataStatementSyntax
	Field definition:TDataDefinition
	Field itemIndex:Int
End Type

Type TDataReadTarget
	Field syntax:TExpressionSyntax
	Field expression:TBoundExpression
	Field targetType:TSemanticType
	Field conversionKind:Int
	Field cursorOffset:Int
End Type

Type TDataReadOperation
	Field syntax:TReadDataStatementSyntax
	Field targets:TDataReadTarget[] = New TDataReadTarget[0]
	Field cursorAdvance:Int
	Field mayRaiseOutOfData:Int = True
End Type

Type TDataSection
	Field definitions:TDataDefinition[] = New TDataDefinition[0]
	Field items:TDataItem[] = New TDataItem[0]
	Field labels:TMap = New TMap
	Field reads:TDataReadOperation[] = New TDataReadOperation[0]
	Field restores:TDataRestoreBinding[] = New TDataRestoreBinding[0]
	Field initialCursorIndex:Int
End Type

Type TConstantValue
	Field kind:Int
	Field semanticType:TSemanticType
	Field integerValue:Long
	Field isRadixLiteral:Int
	Field floatValue:Double
	Field stringValue:String
	Field callableSymbol:TSymbol

	Method DisplayValue:String()
		Select kind
			Case CONSTANT_VALUE_INTEGER
				If IsUnsignedIntegerType(semanticType) Then Return String(ULong(integerValue))
				Return integerValue
			Case CONSTANT_VALUE_FLOAT Return floatValue
			Case CONSTANT_VALUE_STRING Return "~q" + stringValue + "~q"
			Case CONSTANT_VALUE_NULL Return "Null"
			Case CONSTANT_VALUE_CALLABLE
				If callableSymbol Then Return callableSymbol.QualifiedName()
		End Select
		Return "<invalid constant>"
	End Method

	Function IsUnsignedIntegerType:Int(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte", "short", "uint", "ulong", "ulongint", "size_t", "wparam" Return True
		End Select
		Return False
	End Function
End Type

Rem
bbdoc: Describes a declared or imported program symbol.
about: A symbol records its kind, name, declaration, type, accessibility, ownership,
generic information, source provenance, and documentation where applicable.
End Rem
Type TSymbol
	Field kind:Int
	Field name:String
	Field normalizedName:String
	Field nameToken:TSyntaxToken
	Field declaration:TSyntaxNode
	Field containingScope:TScope
	Field visibility:Int = VISIBILITY_PUBLIC
	Field declaredType:TSemanticType
	' True only for a Local declared with ':='. Its declaredType is recovery
	' until expression binding fixes it to the initializer's semantic type.
	Field isTypeInferred:Int
	Field isImported:Int
	Field isExternal:Int
	Field isReadOnly:Int
	Field isAbstract:Int
	' Explicit semantic kind for Interface routines.  This is independent of
	' the C slot name and survives publication/template serialization.
	Field interfaceMethodKind:Int = INTERFACE_METHOD_NONE
	Field interfaceRecord:TInterfaceRecord
	Field externalName:String
	Field nativeStringReturnEncoding:Int
	Field callingConvention:String = CALLING_CONVENTION_C
	Field originModule:String
	Field originPath:String
	Field originLine:Int
	Field originColumn:Int
	Field documentation:TDocumentationComment
	Field metadata:TDeclarationMetadata
	Field documentationPath:String
	Field documentationLine:Int
	Field documentationColumn:Int
	Field memberScope:TScope
	Field genericArity:Int
	Field genericConstraints:TGenericConstraintInfo[] = New TGenericConstraintInfo[0]
	Field genericTemplateArtifact:TGenericTemplateArtifact
	Field parameterTypes:TSemanticType[] = New TSemanticType[0]
	Field parameters:TSemanticParameter[] = New TSemanticParameter[0]
	Field parameterMode:Int = PARAMETER_PASS_VALUE
	Field isIteratorRoutine:Int
	Field iteratorElementType:TSemanticType

	Rem
	bbdoc: Returns a readable name for this symbol's declaration kind.
	End Rem
	Method KindName:String()
		Select kind
			Case SYMBOL_TYPE Return "Type"
			Case SYMBOL_STRUCT Return "Struct"
			Case SYMBOL_INTERFACE Return "Interface"
			Case SYMBOL_ENUM Return "Enum"
			Case SYMBOL_ROUTINE Return "Routine"
			Case SYMBOL_FIELD Return "Field"
			Case SYMBOL_GLOBAL Return "Global"
			Case SYMBOL_CONST Return "Const"
			Case SYMBOL_LOCAL Return "Local"
			Case SYMBOL_PARAMETER Return "Parameter"
			Case SYMBOL_TYPE_PARAMETER Return "TypeParameter"
			Case SYMBOL_ENUM_MEMBER Return "EnumMember"
			Case SYMBOL_CATCH_PARAMETER Return "CatchParameter"
			Case SYMBOL_MODULE Return "Module"
		End Select
		Return "UnknownSymbol"
	End Method

	Method NamespaceKind:Int()
		Select kind
			Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE, SYMBOL_ENUM, SYMBOL_TYPE_PARAMETER
				Return SYMBOL_NAMESPACE_TYPE
			Case SYMBOL_ROUTINE
				Return SYMBOL_NAMESPACE_ROUTINE
		End Select
		Return SYMBOL_NAMESPACE_VALUE
	End Method

	Rem
	bbdoc: Returns this symbol's qualified name within its containing type.
	End Rem
	Method QualifiedName:String()
		If containingScope And containingScope.owner And containingScope.owner.NamespaceKind() = SYMBOL_NAMESPACE_TYPE Then
			Return containingScope.owner.QualifiedName() + "." + name
		End If
		Return name
	End Method
End Type

Type TSymbolGroup
	Field normalizedName:String
	Field symbols:TSymbol[] = New TSymbol[0]

	Method Add(symbol:TSymbol)
		Local values:TSymbol[] = New TSymbol[symbols.length + 1]
		For Local index:Int = 0 Until symbols.length
			values[index] = symbols[index]
		Next
		values[symbols.length] = symbol
		symbols = values
	End Method
End Type

Rem
bbdoc: Represents a lexical or imported declaration scope.
End Rem
Type TScope
	Field kind:Int
	Field parent:TScope
	Field owner:TSymbol
	Field syntax:TSyntaxNode
	Field groups:TMap = New TMap
	Field declaredSymbols:TSymbol[] = New TSymbol[0]
	Field children:TScope[] = New TScope[0]

	Method KindName:String()
		Select kind
			Case SCOPE_COMPILATION_UNIT Return "CompilationUnit"
			Case SCOPE_TYPE Return "Type"
			Case SCOPE_ENUM Return "Enum"
			Case SCOPE_ROUTINE Return "Routine"
			Case SCOPE_BLOCK Return "Block"
			Case SCOPE_LOOP Return "Loop"
			Case SCOPE_CATCH Return "Catch"
			Case SCOPE_USING Return "Using"
			Case SCOPE_CONDITIONAL_BRANCH Return "ConditionalBranch"
			Case SCOPE_INTERFACE_MODULE Return "InterfaceModule"
		End Select
		Return "UnknownScope"
	End Method

	Method AddSymbol(symbol:TSymbol)
		Local group:TSymbolGroup = TSymbolGroup(groups.ValueForKey(symbol.normalizedName))
		If Not group Then
			group = New TSymbolGroup
			group.normalizedName = symbol.normalizedName
			groups.Insert(symbol.normalizedName, group)
		End If
		group.Add(symbol)
		Local values:TSymbol[] = New TSymbol[declaredSymbols.length + 1]
		For Local index:Int = 0 Until declaredSymbols.length
			values[index] = declaredSymbols[index]
		Next
		values[declaredSymbols.length] = symbol
		declaredSymbols = values
	End Method

	Method AddChild(scope:TScope)
		Local values:TScope[] = New TScope[children.length + 1]
		For Local index:Int = 0 Until children.length
			values[index] = children[index]
		Next
		values[children.length] = scope
		children = values
	End Method

	Rem
	bbdoc: Returns symbols declared directly in this scope with a given name.
	param: The case-insensitive symbol name.
	returns: All local declarations in the matching symbol group.
	End Rem
	Method LookupLocal:TSymbol[](name:String)
		Local group:TSymbolGroup = TSymbolGroup(groups.ValueForKey(name.ToLower()))
		If group Then Return group.symbols
		Return New TSymbol[0]
	End Method

	Rem
	bbdoc: Finds the nearest symbols with a given name in this scope or its parents.
	param: The case-insensitive symbol name.
	returns: The declarations from the first matching scope, or an empty array.
	End Rem
	Method Lookup:TSymbol[](name:String)
		Local scope:TScope = Self
		While scope
			Local symbols:TSymbol[] = scope.LookupLocal(name)
			If symbols.length Then Return symbols
			scope = scope.parent
		Wend
		Return New TSymbol[0]
	End Method
End Type

Rem
bbdoc: Contains the resolved symbols, types, bindings, diagnostics, and analysis products for a compilation unit.
about: Query methods map immutable syntax nodes to semantic information. A query may
return #Null when its corresponding optional analysis stage was disabled or when the
syntax could not be resolved.
End Rem
Type TSemanticModel
	Field moduleName:String
	Field syntaxTree:TSyntaxTree
	Field snapshot:TCompilationSnapshot
	Field globalScope:TScope
	Field diagnostics:TDiagnostic[] = New TDiagnostic[0]
	Field declaredSymbolMap:TMap = New TMap
	Field syntaxScopeMap:TMap = New TMap
	Field typeMap:TMap = New TMap
	Field expressionTypeMap:TMap = New TMap
	Field referencedSymbolMap:TMap = New TMap
	Field resolvedCallMap:TMap = New TMap
	Field callSignatureMap:TMap = New TMap
	Field routineReferenceBindingMap:TMap = New TMap
	Field resolvedIndexMap:TMap = New TMap
	Field resolvedMemberMap:TMap = New TMap
	Field namedCastTargetMap:TMap = New TMap
	Field intrinsicOperandMap:TMap = New TMap
	Field boundExpressionMap:TMap = New TMap
	Field boundStatementMap:TMap = New TMap
	Field boundRoutineBodyMap:TMap = New TMap
	Field boundGlobalBody:TBoundBlockStatement
	Field controlFlowGraphMap:TMap = New TMap
	Field globalControlFlowGraph:TControlFlowGraph
	Field dataSection:TDataSection
	Field dataDefinitionMap:TMap = New TMap
	Field dataRestoreMap:TMap = New TMap
	Field dataReadMap:TMap = New TMap
	Field constantExpressionMap:TMap = New TMap
	Field constantSymbolMap:TMap = New TMap
	Field constantsEvaluated:Int
	Field compileTimeAnalyzed:Int
	Field builtinTypes:TMap = New TMap
	Field inheritanceInfoMap:TMap = New TMap
	Field abstractTypeMap:TMap = New TMap
	Field importedModuleScopes:TMap = New TMap
	Field importedInterfaceScopes:TMap = New TMap
	Field importedScopes:TScope[] = New TScope[0]
	Field directImportedScopes:TScope[] = New TScope[0]
	Field arrayRuntimeSymbol:TSymbol
	Field arrayIntrinsicSymbol:TSymbol
	Field staticArrayIntrinsicSymbol:TSymbol

	' Array normally receives its full runtime surface from BRL.Classes. Keep
	' the language-defined length property available in isolated semantic
	' compilations too; an imported runtime symbol remains authoritative.
	Method ArrayIntrinsic:TSymbol()
		If arrayRuntimeSymbol Then Return arrayRuntimeSymbol
		If arrayIntrinsicSymbol Then Return arrayIntrinsicSymbol
		Local owner:TSymbol = New TSymbol
		owner.kind = SYMBOL_TYPE
		owner.name = "___Array"
		owner.normalizedName = "___array"
		owner.visibility = VISIBILITY_PUBLIC
		Local memberScope:TScope = New TScope
		memberScope.kind = SCOPE_TYPE
		memberScope.owner = owner
		owner.memberScope = memberScope
		Local lengthMember:TSymbol = New TSymbol
		lengthMember.kind = SYMBOL_FIELD
		lengthMember.name = "length"
		lengthMember.normalizedName = "length"
		lengthMember.visibility = VISIBILITY_PUBLIC
		lengthMember.isReadOnly = True
		lengthMember.declaredType = BuiltinType("Int")
		lengthMember.containingScope = memberScope
		memberScope.AddSymbol(lengthMember)
		arrayIntrinsicSymbol = owner
		Return owner
	End Method

	' StaticArray has no heap object or runtime class, but BlitzMax exposes its
	' compile-time extent through the same member syntax as Array.length. Model
	' that language intrinsic as a synthetic read-only member so binding,
	' completion, hover, and later compiler stages share one symbol.
	Method StaticArrayIntrinsic:TSymbol()
		If staticArrayIntrinsicSymbol Then Return staticArrayIntrinsicSymbol
		Local owner:TSymbol = New TSymbol
		owner.kind = SYMBOL_STRUCT
		owner.name = "StaticArray"
		owner.normalizedName = "staticarray"
		owner.visibility = VISIBILITY_PUBLIC
		Local memberScope:TScope = New TScope
		memberScope.kind = SCOPE_TYPE
		memberScope.owner = owner
		owner.memberScope = memberScope
		Local lengthMember:TSymbol = New TSymbol
		lengthMember.kind = SYMBOL_FIELD
		lengthMember.name = "length"
		lengthMember.normalizedName = "length"
		lengthMember.visibility = VISIBILITY_PUBLIC
		lengthMember.isReadOnly = True
		lengthMember.declaredType = BuiltinType("Int")
		lengthMember.containingScope = memberScope
		memberScope.AddSymbol(lengthMember)
		staticArrayIntrinsicSymbol = owner
		Return owner
	End Method

	Rem
	bbdoc: Returns the symbol declared by a syntax node.
	param: A declaration syntax node from this model's snapshot.
	returns: The declared symbol, or #Null.
	End Rem
	Method DeclaredSymbol:TSymbol(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TSymbol(declaredSymbolMap.ValueForKey(syntax))
	End Method

	Rem
	bbdoc: Returns the semantic scope associated with a syntax node.
	param: A syntax node from this model's snapshot.
	returns: The associated scope, or #Null.
	End Rem
	Method ScopeFor:TScope(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TScope(syntaxScopeMap.ValueForKey(syntax))
	End Method

	Rem
	bbdoc: Returns the semantic type resolved for a type-reference syntax node.
	param: The type-reference syntax to query.
	returns: The resolved type, or #Null.
	End Rem
	Method TypeOf:TSemanticType(syntax:TTypeReferenceSyntax)
		If Not syntax Then Return Null
		Return TSemanticType(typeMap.ValueForKey(syntax))
	End Method

	Rem
	bbdoc: Returns the semantic type inferred or resolved for an expression.
	param: The expression syntax to query.
	returns: The expression type, or #Null.
	End Rem
	Method ExpressionType:TSemanticType(syntax:TExpressionSyntax)
		If Not syntax Then Return Null
		Return TSemanticType(expressionTypeMap.ValueForKey(syntax))
	End Method

	Method ResolvedIndex:TResolvedIndexAccess(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TResolvedIndexAccess(resolvedIndexMap.ValueForKey(syntax))
	End Method

	Method ResolvedMember:TResolvedMemberAccess(syntax:TMemberAccessExpressionSyntax)
		If Not syntax Then Return Null
		Return TResolvedMemberAccess(resolvedMemberMap.ValueForKey(syntax))
	End Method

	Method NamedCastTarget:TSemanticType(syntax:TCallExpressionSyntax)
		If Not syntax Then Return Null
		Return TSemanticType(namedCastTargetMap.ValueForKey(syntax))
	End Method

	Method IntrinsicOperand:TIntrinsicOperandBinding(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TIntrinsicOperandBinding(intrinsicOperandMap.ValueForKey(syntax))
	End Method

	Method BoundExpression:TBoundExpression(syntax:TExpressionSyntax)
		If Not syntax Then Return Null
		Return TBoundExpression(boundExpressionMap.ValueForKey(syntax))
	End Method

	Method BoundStatement:TBoundStatement(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TBoundStatement(boundStatementMap.ValueForKey(syntax))
	End Method

	Method BoundRoutineBody:TBoundBlockStatement(routine:TSymbol)
		If Not routine Then Return Null
		Return TBoundBlockStatement(boundRoutineBodyMap.ValueForKey(routine))
	End Method

	Method ControlFlowGraph:TControlFlowGraph(routine:TSymbol)
		If Not routine Then Return Null
		Return TControlFlowGraph(controlFlowGraphMap.ValueForKey(routine))
	End Method

	Method DataDefinition:TDataDefinition(syntax:TDefDataStatementSyntax)
		If Not syntax Then Return Null
		Return TDataDefinition(dataDefinitionMap.ValueForKey(syntax))
	End Method

	Method ResolvedDataRestore:TDataRestoreBinding(syntax:TRestoreDataStatementSyntax)
		If Not syntax Then Return Null
		Return TDataRestoreBinding(dataRestoreMap.ValueForKey(syntax))
	End Method

	Method DataReadOperation:TDataReadOperation(syntax:TReadDataStatementSyntax)
		If Not syntax Then Return Null
		Return TDataReadOperation(dataReadMap.ValueForKey(syntax))
	End Method

	Method ConstantValue:TConstantValue(syntax:TExpressionSyntax)
		If Not syntax Then Return Null
		Return TConstantValue(constantExpressionMap.ValueForKey(syntax))
	End Method

	Method SymbolConstantValue:TConstantValue(symbol:TSymbol)
		If Not symbol Then Return Null
		Return TConstantValue(constantSymbolMap.ValueForKey(symbol))
	End Method

	Rem
	bbdoc: Returns the symbol referenced by a name or member syntax node.
	param: The syntax node to query.
	returns: The referenced symbol, or #Null.
	End Rem
	Method ReferencedSymbol:TSymbol(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TSymbol(referencedSymbolMap.ValueForKey(syntax))
	End Method

	Rem
	bbdoc: Returns overload resolution information for a call syntax node.
	param: The call or invocation syntax to query.
	returns: The resolved call, or #Null.
	End Rem
	Method ResolvedCall:TResolvedCall(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TResolvedCall(resolvedCallMap.ValueForKey(syntax))
	End Method

	Rem
	bbdoc: Returns callable candidates captured for signature help.
	about: Unlike #ResolvedCall, this query remains available when a call is incomplete
	or its current arguments do not select a valid overload.
	End Rem
	Method CallSignatures:TCallSignatureSet(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		Return TCallSignatureSet(callSignatureMap.ValueForKey(syntax))
	End Method

	Rem
	bbdoc: Finds a built-in semantic type by language name.
	param: The case-insensitive built-in type name.
	returns: The built-in type, or #Null.
	End Rem
	Method BuiltinType:TBuiltinSemanticType(name:String)
		Return TBuiltinSemanticType(builtinTypes.ValueForKey(name.ToLower()))
	End Method

	Method InheritanceInfo:TTypeInheritanceInfo(symbol:TSymbol)
		If Not symbol Then Return Null
		Return TTypeInheritanceInfo(inheritanceInfoMap.ValueForKey(symbol))
	End Method

	Method IsAbstractType:Int(symbol:TSymbol)
		Return symbol And abstractTypeMap.Contains(symbol)
	End Method

	Method AddImportedScope(name:String, scope:TScope, interfacePath:String = "", visible:Int = True)
		If Not importedModuleScopes.Contains(name.ToLower()) Then importedModuleScopes.Insert(name.ToLower(), scope)
		If interfacePath.length Then importedInterfaceScopes.Insert(interfacePath.Replace("\", "/").ToLower(), scope)
		If visible Then importedScopes :+ [scope]
	End Method

	Rem
	bbdoc: Finds the imported module scope with a logical module name.
	param: The case-insensitive module name.
	returns: The imported scope, or #Null.
	End Rem
	Method ImportedScope:TScope(name:String)
		Return TScope(importedModuleScopes.ValueForKey(name.ToLower()))
	End Method

	Method ImportedInterfaceScope:TScope(interfacePath:String)
		Return TScope(importedInterfaceScopes.ValueForKey(interfacePath.Replace("\", "/").ToLower()))
	End Method

	Method AddDirectImportedScope(scope:TScope)
		If Not scope Then Return
		For Local existing:TScope = EachIn directImportedScopes
			If existing = scope Then Return
		Next
		directImportedScopes :+ [scope]
	End Method
End Type
