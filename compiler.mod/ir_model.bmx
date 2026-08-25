' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BlitzMax.Language

Const IR_EXPRESSION_LITERAL:Int = 1
Const IR_EXPRESSION_SYMBOL:Int = 2
Const IR_EXPRESSION_CALL:Int = 3
Const IR_EXPRESSION_UNARY:Int = 4
Const IR_EXPRESSION_BINARY:Int = 5
Const IR_EXPRESSION_CONVERSION:Int = 6
Const IR_EXPRESSION_STRING_CONCAT:Int = 7
Const IR_EXPRESSION_STRING_COMPARE:Int = 8
Const IR_EXPRESSION_MANAGED_TRUTH:Int = 9
Const IR_EXPRESSION_MANAGED_DEFAULT:Int = 10
Const IR_EXPRESSION_MANAGED_IDENTITY:Int = 11
Const IR_EXPRESSION_ARRAY_NEW:Int = 12
Const IR_EXPRESSION_ARRAY_LENGTH:Int = 13
Const IR_EXPRESSION_ARRAY_ELEMENT:Int = 14
Const IR_EXPRESSION_ARRAY_CONCAT:Int = 15
Const IR_EXPRESSION_OBJECT_NEW:Int = 16
Const IR_EXPRESSION_FIELD:Int = 17
Const IR_EXPRESSION_MATERIALIZE:Int = 18
Const IR_EXPRESSION_INTERFACE_CAST:Int = 19
Const IR_EXPRESSION_OBJECT_CAST:Int = 20
Const IR_EXPRESSION_ARRAY_LITERAL:Int = 21
Const IR_EXPRESSION_CALLABLE_REFERENCE:Int = 22
Const IR_EXPRESSION_INDIRECT_CALL:Int = 23
Const IR_EXPRESSION_CALLABLE_DEFAULT:Int = 24
Const IR_EXPRESSION_CALLABLE_TRUTH:Int = 25
Const IR_EXPRESSION_ENUM_INTRINSIC:Int = 26
Const IR_EXPRESSION_ADDRESS_OF:Int = 26
Const IR_EXPRESSION_STRUCT_NEW:Int = 27
Const IR_EXPRESSION_POINTER_ELEMENT:Int = 28
Const IR_EXPRESSION_STRING_SLICE:Int = 29
Const IR_EXPRESSION_STRING_LENGTH:Int = 30
Const IR_EXPRESSION_ARRAY_SLICE:Int = 31
Const IR_EXPRESSION_POINTER_TRUTH:Int = 32
Const IR_EXPRESSION_POINTER_BINARY:Int = 33
Const IR_EXPRESSION_STRING_ELEMENT:Int = 34
Const IR_EXPRESSION_STRING_ASC:Int = 35
Const IR_EXPRESSION_STRING_CHR:Int = 36
Const IR_EXPRESSION_OBJECT_STRING_CAST:Int = 37
Const IR_EXPRESSION_CLOSURE_LITERAL:Int = 38
Const IR_EXPRESSION_CLOSURE_CALL:Int = 39

Const IR_STATEMENT_VARIABLE:Int = 1
Const IR_STATEMENT_ASSIGNMENT:Int = 2
Const IR_STATEMENT_EXPRESSION:Int = 3
Const IR_STATEMENT_RETURN:Int = 4
Const IR_STATEMENT_IF:Int = 5
Const IR_STATEMENT_WHILE:Int = 6
Const IR_STATEMENT_REPEAT:Int = 7
Const IR_STATEMENT_LOOP_CONTROL:Int = 8
Const IR_STATEMENT_FOR_RANGE:Int = 9
Const IR_STATEMENT_FOR_EACH_ARRAY:Int = 10
Const IR_STATEMENT_FOR_EACH_STRING:Int = 11
Const IR_STATEMENT_FOR_EACH_STATIC_ARRAY:Int = 12
Const IR_STATEMENT_FOR_EACH_OBJECT:Int = 13
Const IR_STATEMENT_ASSERT:Int = 14
Const IR_STATEMENT_SELECT:Int = 15
Const IR_STATEMENT_TRY:Int = 16
Const IR_STATEMENT_THROW:Int = 17
Const IR_STATEMENT_USING:Int = 18
Const IR_STATEMENT_DATA_READ:Int = 19
Const IR_STATEMENT_DATA_RESTORE:Int = 20
Const IR_STATEMENT_APPLICATION_END:Int = 21
Const IR_STATEMENT_RELEASE:Int = 22
Const IR_STATEMENT_YIELD:Int = 23

Const IR_CATCH_OBJECT:Int = 1
Const IR_CATCH_STRING:Int = 2
Const IR_CATCH_ARRAY:Int = 3
Const IR_CATCH_CLASS:Int = 4
Const IR_CATCH_INTERFACE:Int = 5

Const IR_LOOP_CONTROL_EXIT:Int = 1
Const IR_LOOP_CONTROL_CONTINUE:Int = 2

Const IR_UNIT_APPLICATION:Int = 1
Const IR_UNIT_MODULE:Int = 2

Const IR_INIT_REGISTER_DEPENDENCY:Int = 1
Const IR_INIT_INITIALIZE_STRINGS:Int = 2
Const IR_INIT_ADD_GC_ROOTS:Int = 3
Const IR_INIT_INITIALIZE_DEPENDENCY:Int = 4
Const IR_INIT_RUN_ATSTART:Int = 5
Const IR_INIT_EXECUTE_GLOBAL_BODY:Int = 6

Const IR_MANAGED_REFERENCE_STRING:Int = 1
Const IR_MANAGED_REFERENCE_ARRAY:Int = 2
Const IR_MANAGED_REFERENCE_OBJECT:Int = 3
Const IR_MANAGED_REFERENCE_CLOSURE:Int = 4

Const IR_LIFECYCLE_NONE:Int = 0
Const IR_LIFECYCLE_CONSTRUCTOR:Int = 1
Const IR_LIFECYCLE_DESTRUCTOR:Int = 2

Const IR_CONSTRUCTOR_CHAIN_NONE:Int = 0
Const IR_CONSTRUCTOR_CHAIN_BASE:Int = 1
Const IR_CONSTRUCTOR_CHAIN_SAME_TYPE:Int = 2

Const IR_OBJECT_SLOT_NONE:Int = 0
Const IR_OBJECT_SLOT_TO_STRING:Int = 1
Const IR_OBJECT_SLOT_COMPARE:Int = 2
Const IR_OBJECT_SLOT_SEND_MESSAGE:Int = 3
Const IR_OBJECT_SLOT_HASH_CODE:Int = 4
Const IR_OBJECT_SLOT_EQUALS:Int = 5

Const IR_CALL_DISPATCH_DIRECT:Int = 0
Const IR_CALL_DISPATCH_VIRTUAL:Int = 1
Const IR_CALL_DISPATCH_SUPER:Int = 2
Const IR_CALL_DISPATCH_INTERFACE:Int = 3
Const IR_CALL_DISPATCH_IMPORTED_VIRTUAL:Int = 4
Const IR_CALL_DISPATCH_STRUCT:Int = 5
Const IR_CALL_DISPATCH_INTERFACE_SUPER:Int = 6
Const IR_CALL_DISPATCH_TYPE_FUNCTION:Int = 7

Const IR_ENUM_INTRINSIC_ORDINAL:Int = 1
Const IR_ENUM_INTRINSIC_VALUES:Int = 2
Const IR_ENUM_INTRINSIC_TO_STRING:Int = 3
Const IR_ENUM_INTRINSIC_TRY_CONVERT:Int = 4
Const IR_ENUM_INTRINSIC_FROM_STRING:Int = 5

Const IR_DEBUG_SCOPE_FUNCTION:Int = 1
Const IR_DEBUG_SCOPE_LOCAL_BLOCK:Int = 2
Const IR_DEBUG_DECL_LOCAL:Int = 1
Const IR_DEBUG_DECL_CONSTANT:Int = 2
Const IR_DEBUG_DECL_GLOBAL:Int = 3

Const IR_BOUNDS_CHECK_NONE:Int = 0
Const IR_BOUNDS_CHECK_DYNAMIC_ARRAY:Int = 1
Const IR_BOUNDS_CHECK_STATIC_ARRAY:Int = 2

Type TCompilerSourceLocation
	Field path:String
	Field span:TSourceSpan
	Field line:Int
	Field column:Int
	Field debugSourceId:ULong
End Type

Type TCompilerIrNode Abstract
	Field source:TCompilerSourceLocation
	Field metadata:TCompilerIrMetadataEntry[] = New TCompilerIrMetadataEntry[0]
End Type

Type TCompilerIrMetadataEntry
	Field key:String
	Field value:String
	Field writtenValue:String
	Field source:TCompilerSourceLocation
End Type

Type TCompilerIrExpression Extends TCompilerIrNode
	Field kind:Int
	Field semanticType:String
End Type

Type TCompilerIrLiteral Extends TCompilerIrExpression
	Field text:String
	Field stringLiteralId:String
End Type

Type TCompilerIrSymbolReference Extends TCompilerIrExpression
	Field symbolId:String
	Field name:String
	Field isExternal:Int
	Field isByReference:Int
	' An external callable Global has storage declared by an imported header.
	' If sequencing materializes its value, the temporary must derive its
	' complete type from this ABI symbol rather than reconstructing it from the
	' deliberately coarser BlitzMax callable signature. Compact-interface
	' consumers retain the ABI symbol without needing the producer source.
	Field nativeCallableAbiName:String
End Type

Type TCompilerIrAddressOf Extends TCompilerIrExpression
	Field operand:TCompilerIrExpression
	' Reference-compatible Var arguments cast the storage address to the
	' selected parameter's pointer ABI after taking the address.
	Field castStorageAddress:Int
End Type

Type TCompilerIrPointerTruth Extends TCompilerIrExpression
	Field operand:TCompilerIrExpression
	Field negate:Int
End Type

Type TCompilerIrPointerBinary Extends TCompilerIrExpression
	Field operatorText:String
	Field left:TCompilerIrExpression
	Field right:TCompilerIrExpression
End Type

Type TCompilerIrStructNew Extends TCompilerIrExpression
	Field structId:String
	Field importedStructId:String
	Field constructorFunctionId:String
	Field importedConstructorId:String
	Field arguments:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrCallableReference Extends TCompilerIrExpression
	Field functionId:String
	Field functionName:String
	Field abiName:String
	Field isExternal:Int
	Field returnType:String
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callingConvention:String = "c"
	Field isFunctionLiteral:Int
End Type

Type TCompilerIrCall Extends TCompilerIrExpression
	Field functionId:String
	Field functionAbiName:String
	Field functionName:String
	Field isExternal:Int
	Field dispatchKind:Int
	Field receiver:TCompilerIrExpression
	Field classId:String
	Field classSlotId:String
	Field interfaceId:String
	Field interfaceSlotId:String
	Field objectSlotKind:Int
	Field arguments:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrIndirectCall Extends TCompilerIrExpression
	Field callee:TCompilerIrExpression
	Field returnType:String
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callingConvention:String = "c"
	Field arguments:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrCallableDefault Extends TCompilerIrExpression
	Field returnType:String
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callingConvention:String = "c"
End Type

Type TCompilerIrCallableTruth Extends TCompilerIrExpression
	Field operand:TCompilerIrExpression
	Field returnType:String
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callingConvention:String = "c"
	Field negate:Int
End Type

Type TCompilerIrClosureLiteral Extends TCompilerIrExpression
	Field literalId:String
	Field functionId:String
	Field abiName:String
	Field returnType:String
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	' Null for the allocation-free singleton form. A capturing literal retains
	' the synthesized parent environment through this expression.
	Field environment:TCompilerIrExpression
End Type

Type TCompilerIrClosureCall Extends TCompilerIrExpression
	Field callee:TCompilerIrExpression
	Field returnType:String
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field arguments:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrEnumIntrinsic Extends TCompilerIrExpression
	Field intrinsicKind:Int
	Field enumId:String
	Field receiver:TCompilerIrExpression
	Field arguments:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrUnary Extends TCompilerIrExpression
	Field operatorText:String
	Field operand:TCompilerIrExpression
	Field measureType:String
End Type

Type TCompilerIrBinary Extends TCompilerIrExpression
	Field operatorText:String
	Field left:TCompilerIrExpression
	Field right:TCompilerIrExpression
End Type

Type TCompilerIrConversion Extends TCompilerIrExpression
	Field conversionKind:Int
	Field implicitConversion:Int
	' Explicit Object-to-Array and compatible managed reference-array casts must
	' pass through the runtime so Null becomes the canonical empty Array and the
	' target element category is checked before exposing BBARRAY storage.
	Field arrayCastElementEncoding:String
	' Heap Arrays carry a BBARRAY handle rather than a native C array value.
	' Retain this distinction for array-to-pointer conversion so the backend
	' can expose the contiguous element storage with BBARRAYDATA.
	Field arrayToPointerUsesHeapStorage:Int
	' Retained when the conversion target is a native callable. Its C spelling
	' cannot be reconstructed from the display name alone.
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	' Set only for an explicit integral-to-Enum boundary. Backends use the
	' retained Enum descriptor to provide checked debug conversions without
	' erasing the scalar release ABI.
	Field checkedEnumId:String
	Field operand:TCompilerIrExpression
End Type

Type TCompilerIrStringConcat Extends TCompilerIrExpression
	Field left:TCompilerIrExpression
	Field right:TCompilerIrExpression
End Type

Type TCompilerIrStringCompare Extends TCompilerIrExpression
	Field operatorText:String
	Field left:TCompilerIrExpression
	Field right:TCompilerIrExpression
End Type

Type TCompilerIrManagedTruth Extends TCompilerIrExpression
	Field operand:TCompilerIrExpression
	Field managedKind:Int
	Field negate:Int
End Type

Type TCompilerIrManagedDefault Extends TCompilerIrExpression
	Field managedKind:Int
End Type

Type TCompilerIrManagedIdentity Extends TCompilerIrExpression
	Field operatorText:String
	Field managedKind:Int
	Field left:TCompilerIrExpression
	Field right:TCompilerIrExpression
End Type

Type TCompilerIrArrayNew Extends TCompilerIrExpression
	Field elementType:String
	Field elementEncoding:String
	Field enumId:String
	Field structId:String
	Field importedStructId:String
	Field rank:Int
	Field dimensions:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrArrayLength Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
End Type

Type TCompilerIrStringSlice Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
	Field lowerBound:TCompilerIrExpression
	Field upperBound:TCompilerIrExpression
	Field upperBoundOmitted:Int
	Field lowerFromEnd:Int
	Field upperFromEnd:Int
End Type

Type TCompilerIrStringLength Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
End Type

Type TCompilerIrStringElement Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
	Field index:TCompilerIrExpression
	Field boundsCheck:Int
End Type

Type TCompilerIrStringAsc Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
End Type

Type TCompilerIrStringChr Extends TCompilerIrExpression
	Field codePoint:TCompilerIrExpression
End Type

Type TCompilerIrArraySlice Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
	Field lowerBound:TCompilerIrExpression
	Field upperBound:TCompilerIrExpression
	Field upperBoundOmitted:Int
	Field lowerFromEnd:Int
	Field upperFromEnd:Int
	Field elementType:String
	Field elementEncoding:String
	Field structId:String
	Field importedStructId:String
End Type

Type TCompilerIrArrayElement Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
	Field indexes:TCompilerIrExpression[] = New TCompilerIrExpression[0]
	Field elementType:String
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field structId:String
	Field importedStructId:String
	Field rank:Int
	Field isStaticArray:Int
	Field boundsCheckKind:Int
	Field boundsLength:Long
End Type

Type TCompilerIrPointerElement Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
	Field index:TCompilerIrExpression
	Field elementType:String
	Field structId:String
	Field importedStructId:String
	Field nullCheck:Int
End Type

Type TCompilerIrArrayConcat Extends TCompilerIrExpression
	Field elementType:String
	Field elementEncoding:String
	Field enumId:String
	Field structId:String
	Field importedStructId:String
	Field left:TCompilerIrExpression
	Field right:TCompilerIrExpression
End Type

Type TCompilerIrArrayLiteral Extends TCompilerIrExpression
	Field elementType:String
	Field elementEncoding:String
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field enumId:String
	Field structId:String
	Field importedStructId:String
	Field elements:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrObjectNew Extends TCompilerIrExpression
	Field classId:String
	Field importedClassId:String
	Field dynamicClassSource:TCompilerIrExpression
	Field constructorFunctionId:String
	Field importedConstructorId:String
	Field arguments:TCompilerIrExpression[] = New TCompilerIrExpression[0]
End Type

Type TCompilerIrFieldAccess Extends TCompilerIrExpression
	Field receiver:TCompilerIrExpression
	Field receiverIsPointer:Int
	Field classId:String
	Field structId:String
	Field fieldId:String
	Field importedFieldId:String
	Field importedStructId:String
End Type

' Evaluates value exactly once, stores it in a typed compiler temporary, then
' evaluates expression. This is an IR sequencing operation rather than a
' C-backend convenience so every future backend observes the same receiver
' evaluation semantics.
Type TCompilerIrMaterialize Extends TCompilerIrExpression
	Field temporaryId:String
	Field temporaryType:String
	' The materialized value is the address of temporaryType rather than a
	' temporaryType value. This keeps Var-argument sequencing pointer-typed.
	Field temporaryIsAddress:Int
	Field temporaryCallableReturnType:String
	Field temporaryCallableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field temporaryCallableCallingConvention:String = "c"
	' Header-owned callable storage can contain typedefs and calling-convention
	' attributes that are not expressible in semantic callable types.
	Field temporaryNativeCallableAbiName:String
	Field value:TCompilerIrExpression
	Field expression:TCompilerIrExpression
End Type

Type TCompilerIrInterfaceCast Extends TCompilerIrExpression
	Field interfaceId:String
	Field operand:TCompilerIrExpression
End Type

Type TCompilerIrObjectCast Extends TCompilerIrExpression
	Field classId:String
	Field importedClassId:String
	Field operand:TCompilerIrExpression
End Type

Type TCompilerIrObjectStringCast Extends TCompilerIrExpression
	Field operand:TCompilerIrExpression
End Type

Type TCompilerIrStatement Extends TCompilerIrNode
	Field kind:Int
	' Coverage eligibility is selected while lowering the bound source statement.
	' Synthetic cleanup, capture-environment and ABI statements retain source
	' provenance for diagnostics without becoming executable source lines.
	Field coveragePoint:Int
End Type

Type TCompilerIrVariableDeclaration Extends TCompilerIrStatement
	Field symbolId:String
	Field ownerClassId:String
	Field ownerStructId:String
	Field name:String
	Field abiName:String
	Field semanticType:String
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field arrayCallableReturnType:String
	Field arrayCallableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field arrayCallableCallingConvention:String = "c"
	Field arrayCallableRank:Int
	Field storage:String
	Field visibility:Int
	Field isPublished:Int
	Field isSpecializationLinked:Int
	Field isReadOnly:Int
	Field isVolatile:Int
	Field isThreadedGlobal:Int
	Field hasExplicitInitializer:Int
	Field initializer:TCompilerIrExpression
	Field debugConstantStringLiteralId:String
	Field isStaticArray:Int
	Field staticArrayElementType:String
	Field staticArrayStructId:String
	Field staticArrayImportedStructId:String
	Field staticArrayLength:Long
End Type

Type TCompilerIrAssignment Extends TCompilerIrStatement
	Field operatorText:String = "="
	Field target:TCompilerIrExpression
	Field value:TCompilerIrExpression
End Type

Type TCompilerIrExpressionStatement Extends TCompilerIrStatement
	Field expression:TCompilerIrExpression
End Type

Type TCompilerIrReturn Extends TCompilerIrStatement
	Field expression:TCompilerIrExpression
	Field cleanupSteps:TCompilerIrCleanupStep[] = New TCompilerIrCleanupStep[0]
End Type

Type TCompilerIrYield Extends TCompilerIrStatement
	Field expression:TCompilerIrExpression
	Field resumeState:Int
	Field exceptionFrameDepth:Int
	Field cleanupSteps:TCompilerIrCleanupStep[] = New TCompilerIrCleanupStep[0]
End Type

Type TCompilerIrCleanupStep
	Field finallyBody:TCompilerIrBlock
	Field usingResources:TCompilerIrUsingResource[] = New TCompilerIrUsingResource[0]
End Type

Type TCompilerIrAssert Extends TCompilerIrStatement
	Field condition:TCompilerIrExpression
	Field message:TCompilerIrExpression
End Type

Type TCompilerIrRelease Extends TCompilerIrStatement
	Field expression:TCompilerIrExpression
End Type

Type TCompilerIrConditionalClause
	Field source:TCompilerSourceLocation
	Field condition:TCompilerIrExpression
	Field body:TCompilerIrBlock
End Type

Type TCompilerIrIf Extends TCompilerIrStatement
	Field condition:TCompilerIrExpression
	Field thenBody:TCompilerIrBlock
	Field elseIfClauses:TCompilerIrConditionalClause[] = New TCompilerIrConditionalClause[0]
	Field elseBody:TCompilerIrBlock
End Type

Type TCompilerIrSelectCase Extends TCompilerIrNode
	Field values:TCompilerIrExpression[] = New TCompilerIrExpression[0]
	Field body:TCompilerIrBlock
End Type

Type TCompilerIrSelect Extends TCompilerIrStatement
	Field selector:TCompilerIrExpression
	Field selectorTemporaryId:String
	Field selectorType:String
	Field stringComparison:Int
	Field managedIdentityComparison:Int
	Field cases:TCompilerIrSelectCase[] = New TCompilerIrSelectCase[0]
	Field defaultBody:TCompilerIrBlock
End Type

Type TCompilerIrCatch Extends TCompilerIrNode
	Field parameterSymbolId:String
	Field parameterName:String
	Field parameterType:String
	Field catchKind:Int
	Field classId:String
	Field importedClassId:String
	Field interfaceId:String
	Field body:TCompilerIrBlock
End Type

Type TCompilerIrTry Extends TCompilerIrStatement
	Field tryId:String
	Field body:TCompilerIrBlock
	Field catches:TCompilerIrCatch[] = New TCompilerIrCatch[0]
	Field finallyBody:TCompilerIrBlock
	Field retainedInIterator:Int
	Field iteratorExceptionFieldId:String
	Field iteratorFailedFieldId:String
End Type

Type TCompilerIrUsingResource
	Field variable:TCompilerIrVariableDeclaration
	Field initializer:TCompilerIrExpression
	Field closeCall:TCompilerIrExpression
	Field truth:TCompilerIrExpression
End Type

Type TCompilerIrUsing Extends TCompilerIrStatement
	Field usingId:String
	Field resources:TCompilerIrUsingResource[] = New TCompilerIrUsingResource[0]
	Field body:TCompilerIrBlock
	Field retainedInIterator:Int
End Type

Type TCompilerIrDataReadTarget
	Field target:TCompilerIrExpression
	Field conversionKind:Int
	Field source:TCompilerSourceLocation
End Type

Type TCompilerIrDataRead Extends TCompilerIrStatement
	Field targets:TCompilerIrDataReadTarget[] = New TCompilerIrDataReadTarget[0]
End Type

Type TCompilerIrDataRestore Extends TCompilerIrStatement
	Field itemIndex:Int
End Type

Type TCompilerIrDataItem
	Field typeTag:String
	Field unionField:String
	Field valueText:String
	Field stringLiteralId:String
	Field source:TCompilerSourceLocation
End Type

Type TCompilerIrThrow Extends TCompilerIrStatement
	Field expression:TCompilerIrExpression
End Type

Type TCompilerIrApplicationEnd Extends TCompilerIrStatement
End Type

Type TCompilerIrWhile Extends TCompilerIrStatement
	Field loopId:String
	Field sourceLabel:String
	Field condition:TCompilerIrExpression
	Field body:TCompilerIrBlock
	Field hasExit:Int
	Field hasContinue:Int
End Type

Type TCompilerIrRepeat Extends TCompilerIrStatement
	Field loopId:String
	Field sourceLabel:String
	Field condition:TCompilerIrExpression
	Field isForever:Int
	Field body:TCompilerIrBlock
	Field hasExit:Int
	Field hasContinue:Int
End Type

Type TCompilerIrForRange Extends TCompilerIrStatement
	Field loopId:String
	Field sourceLabel:String
	Field declaresVariable:Int
	Field variableSymbolId:String
	Field variableName:String
	Field variableType:String
	Field target:TCompilerIrExpression
	Field initialValue:TCompilerIrExpression
	Field limit:TCompilerIrExpression
	Field stepExpression:TCompilerIrExpression
	Field inclusiveLimit:Int
	Field descending:Int
	Field body:TCompilerIrBlock
	' When the declared control variable is captured, the loop body uses a
	' fresh managed iteration cell. Copy its final value back before the normal
	' increment so existing mutation semantics are retained across Continue.
	Field iterationCopyBack:TCompilerIrAssignment
	Field hasExit:Int
	Field hasContinue:Int
End Type

Type TCompilerIrForEachArray Extends TCompilerIrStatement
	Field loopId:String
	Field sourceLabel:String
	Field declaresVariable:Int
	Field variableSymbolId:String
	Field variableName:String
	Field variableType:String
	Field target:TCompilerIrExpression
	Field collection:TCompilerIrExpression
	Field collectionTemporaryId:String
	Field indexTemporaryId:String
	Field elementTemporaryId:String
	Field elementType:String
	Field elementValue:TCompilerIrExpression
	Field filtersNullObjects:Int
	Field filtersStringObjects:Int
	Field body:TCompilerIrBlock
	Field hasExit:Int
	Field hasContinue:Int
End Type

Type TCompilerIrForEachString Extends TCompilerIrStatement
	Field loopId:String
	Field sourceLabel:String
	Field declaresVariable:Int
	Field variableSymbolId:String
	Field variableName:String
	Field variableType:String
	Field target:TCompilerIrExpression
	Field collection:TCompilerIrExpression
	Field collectionTemporaryId:String
	Field indexTemporaryId:String
	Field elementTemporaryId:String
	Field body:TCompilerIrBlock
	Field hasExit:Int
	Field hasContinue:Int
End Type

Type TCompilerIrForEachStaticArray Extends TCompilerIrStatement
	Field loopId:String
	Field sourceLabel:String
	Field declaresVariable:Int
	Field variableSymbolId:String
	Field variableName:String
	Field variableType:String
	Field target:TCompilerIrExpression
	Field collection:TCompilerIrExpression
	Field collectionTemporaryId:String
	Field indexTemporaryId:String
	Field elementTemporaryId:String
	Field elementType:String
	Field elementStructId:String
	Field elementImportedStructId:String
	Field length:Long
	Field body:TCompilerIrBlock
	Field hasExit:Int
	Field hasContinue:Int
End Type

Type TCompilerIrForEachObject Extends TCompilerIrStatement
	Field loopId:String
	Field sourceLabel:String
	Field protocolKind:Int
	Field declaresVariable:Int
	Field variableSymbolId:String
	Field variableName:String
	Field variableType:String
	Field target:TCompilerIrExpression
	Field collection:TCompilerIrExpression
	Field collectionType:String
	Field collectionTemporaryId:String
	Field iteratorType:String
	Field iteratorTemporaryId:String
	Field elementType:String
	Field elementTemporaryId:String
	Field elementValue:TCompilerIrExpression
	Field filtersNullObjects:Int
	Field filtersStringObjects:Int
	Field iteratorInitializer:TCompilerIrExpression
	Field iteratorCleanup:TCompilerIrUsingResource
	Field advance:TCompilerIrExpression
	Field current:TCompilerIrExpression
	Field body:TCompilerIrBlock
	Field hasExit:Int
	Field hasContinue:Int
End Type

Type TCompilerIrLoopControl Extends TCompilerIrStatement
	Field controlKind:Int
	Field targetLoopId:String
	Field cleanupSteps:TCompilerIrCleanupStep[] = New TCompilerIrCleanupStep[0]
End Type

Type TCompilerIrBlock Extends TCompilerIrNode
	Field statements:TCompilerIrStatement[] = New TCompilerIrStatement[0]
	Field debugScope:TCompilerIrDebugScope
End Type

Type TCompilerIrParameter
	Field symbolId:String
	Field name:String
	Field semanticType:String
	Field passingMode:Int
	Field nativeStringEncoding:Int
	Field isStaticArray:Int
	Field staticArrayElementType:String
	Field staticArrayStructId:String
	Field staticArrayImportedStructId:String
	Field staticArrayLength:Int
	Field isOptional:Int
	Field defaultKind:Int
	Field defaultText:String
	Field defaultStringValue:String
	Field defaultCallableAbiName:String
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
End Type

Type TCompilerIrEnumValue Extends TCompilerIrNode
	Field name:String
	Field integerValue:Long
	Field nameStringLiteralId:String
	Field ordinalStringLiteralId:String
End Type

Type TCompilerIrEnumRuntimeDescriptor
	Field runtimeName:String
	Field numericTypeTag:String
	Field arrayTypeEncoding:String
	Field descriptorAbiName:String
	Field descriptorStorageAbiName:String
	Field valuesAbiName:String
	Field debugScopeAbiName:String
	Field maskAbiName:String
	Field toStringAbiName:String
	Field tryConvertAbiName:String
	Field fromStringAbiName:String
End Type

Type TCompilerIrEnum Extends TCompilerIrNode
	Field enumId:String
	Field name:String
	Field semanticType:String
	Field underlyingType:String
	Field abiName:String
	Field visibility:Int
	Field isFlags:Int
	Field isPublished:Int
	Field isImported:Int
	Field originModule:String
	Field runtimeDescriptor:TCompilerIrEnumRuntimeDescriptor
	Field values:TCompilerIrEnumValue[] = New TCompilerIrEnumValue[0]
End Type

' Debugging is retained as typed compiler data rather than reconstructed from
' generated C. Declaration kinds distinguish addressable locals/Globals from
' constants whose folded textual value is published through a runtime String.
Type TCompilerIrDebugSource
	Field sourceId:ULong
	Field path:String
End Type

Type TCompilerIrCoverageFunction
	Field name:String
	Field line:Int
End Type

Type TCompilerIrCoverageFile
	Field path:String
	Field lines:Int[] = New Int[0]
	Field functions:TCompilerIrCoverageFunction[] = New TCompilerIrCoverageFunction[0]
End Type

Type TCompilerIrDebugVariable
	Field symbolId:String
	Field name:String
	Field semanticType:String
	' Callable storage needs its structured signature here. The display type
	' alone is not sufficient to reconstruct nested parameters, Var modes or
	' the calling convention when publishing a debugger typetag.
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field arrayCallableReturnType:String
	Field arrayCallableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field arrayCallableCallingConvention:String = "c"
	Field arrayCallableRank:Int
	' Captured values are not C locals. Their debugger address remains a typed
	' IR expression so nested environment traversal is planned before emission.
	Field address:TCompilerIrExpression
	Field declarationKind:Int = IR_DEBUG_DECL_LOCAL
	Field constantStringLiteralId:String
	Field passingMode:Int
	Field isReceiver:Int
End Type

Type TCompilerIrDebugScope
	Field scopeKind:Int
	Field sourceId:ULong
	Field name:String
	Field variables:TCompilerIrDebugVariable[] = New TCompilerIrDebugVariable[0]
End Type

Type TCompilerIrFunction Extends TCompilerIrNode
	Field functionId:String
	Field name:String
	Field debugName:String
	Field abiName:String
	Field implementationAbiName:String
	' Production-compatible unsuffixed linkage is scoped to the physical source
	' unit even though overload resolution and publication are module-wide.
	Field legacyAliasName:String
	Field noMangle:Int
	Field returnType:String
	Field callableReturnType:String
	Field callableReturnParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableReturnCallingConvention:String = "c"
	Field callingConvention:String = "c"
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field body:TCompilerIrBlock
	Field isGlobalEntry:Int
	Field debugInstrumentation:Int
	Field suppressDebugInfo:Int
	Field debugScope:TCompilerIrDebugScope
	Field coverageInstrumentation:Int
	Field coverageFunction:Int
	Field coverageName:String
	Field visibility:Int
	Field ownerClassId:String
	Field ownerStructId:String
	Field ownerInterfaceId:String
	Field classSlotId:String
	Field objectSlotKind:Int
	Field isMethod:Int
	Field isAbstract:Int
	Field receiver:TCompilerIrParameter
	Field lifecycleKind:Int
	Field constructorChainKind:Int
	Field chainedConstructorFunctionId:String
	Field chainedImportedConstructorId:String
	Field chainedConstructorArguments:TCompilerIrExpression[] = New TCompilerIrExpression[0]
	Field suppressLegacyAlias:Int
	Field isClosureInvoke:Int
	Field isFunctionLiteral:Int
	Field isIteratorFactory:Int
	Field isIteratorMoveNext:Int
	Field iteratorElementType:String
	Field iteratorStateClassId:String
	Field iteratorMoveNextFunctionId:String
	Field iteratorCurrentFunctionId:String
	Field iteratorCloseFunctionId:String
	Field iteratorStateFieldId:String
	Field iteratorCurrentFieldId:String
	Field iteratorSelfFieldId:String
	Field iteratorFactoryFunctionId:String
	' Iterator-backed EachIn loops and resumable Using blocks retain their
	' closeable resources in state.
	' The factory owns this lexical list so MoveNext exception handling and the
	' generated Close method can release every currently active resource.
	Field iteratorOwnedResources:TCompilerIrUsingResource[] = New TCompilerIrUsingResource[0]
	Field isIteratorCurrent:Int
	Field isIteratorClose:Int
End Type

Type TCompilerIrExternalFunction Extends TCompilerIrNode
	Field functionId:String
	Field sourceName:String
	Field abiName:String
	' Explicit native C declarations are an interop boundary, not generic
	' template payload. Retaining the validated declaration here lets the C
	' backend respect typedef-rich runtime/header signatures.
	Field nativeDeclaration:String
	' Complete native declarations may use a more specific managed pointer
	' result than the BlitzMax signature (for example BBArray* for Object).
	' Retain that spelling so the backend can make the C conversion explicit.
	Field nativeReturnType:String
	' Complete native declaration parameter spellings are call-site ABI casts,
	' including when a trailing ! leaves prototype ownership to native code.
	Field nativeParameterTypes:String[] = New String[0]
	' A trailing ! on a complete native declaration suppresses the generated
	' prototype while retaining the declaration's call-site casts.
	Field nativeDeclarationSuppressesPrototype:Int
	Field suppressNativePrototype:Int
	Field originModule:String
	Field returnType:String
	Field nativeStringReturnEncoding:Int
	Field callableReturnType:String
	Field callableReturnParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableReturnCallingConvention:String = "c"
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callingConvention:String = "c"
	Field isPublished:Int
	' A canonical specialization may be owned by the application even when its
	' source declaration belongs to an imported module. Its module header cannot
	' therefore be assumed to publish this closed routine prototype.
	Field isGenericSpecialization:Int
	Field isGenericMethod:Int
	Field isGenericStructMethod:Int
	Field isDirectMethod:Int
	' Compact interfaces name the public class slot ABI, while a direct call
	' to a published method may require its distinct implementation symbol.
	Field implementationAbiName:String
End Type

Type TCompilerIrExternalGlobal Extends TCompilerIrNode
	Field symbolId:String
	Field sourceName:String
	Field abiName:String
	' A complete native declaration ending in ! names callable storage whose
	' declaration is owned by an imported C header.
	Field suppressNativePrototype:Int
	' Header-owned callable storage can use typedef-rich parameter spellings
	' that are deliberately opaque to BlitzMax. Retain the declaration's exact
	' function-pointer cast so callback assignment remains C ABI-compatible.
	Field nativeCallableCast:String
	Field originModule:String
	Field semanticType:String
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field isReadOnly:Int
	Field isPublished:Int
	Field isThreadedGlobal:Int
End Type

Type TCompilerIrStringLiteral Extends TCompilerIrNode
	Field literalId:String
	Field value:String
End Type

Type TCompilerIrClassField Extends TCompilerIrNode
	Field fieldId:String
	Field declaringClassId:String
	Field declaringImportedClassId:String
	Field name:String
	Field abiName:String
	Field semanticType:String
	Field isStaticArray:Int
	Field staticArrayElementType:String
	Field staticArrayStructId:String
	Field staticArrayImportedStructId:String
	Field staticArrayLength:Long
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field arrayCallableReturnType:String
	Field arrayCallableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field arrayCallableCallingConvention:String = "c"
	Field arrayCallableRank:Int
	Field visibility:Int
	Field isReadOnly:Int
	Field initializer:TCompilerIrExpression
End Type

Type TCompilerIrStructField Extends TCompilerIrNode
	Field fieldId:String
	Field name:String
	Field abiName:String
	Field semanticType:String
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field arrayCallableReturnType:String
	Field arrayCallableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field arrayCallableCallingConvention:String = "c"
	Field arrayCallableRank:Int
	Field structId:String
	Field importedStructId:String
	Field isStaticArray:Int
	Field staticArrayElementType:String
	Field staticArrayStructId:String
	Field staticArrayImportedStructId:String
	Field staticArrayLength:Long
	Field visibility:Int
	Field isReadOnly:Int
	Field initializer:TCompilerIrExpression
End Type

Type TCompilerIrStruct Extends TCompilerIrNode
	Field structId:String
	Field name:String
	Field abiName:String
	Field semanticType:String
	Field visibility:Int
	Field isPublished:Int
	Field hasStableLocalAbi:Int
	Field containsManagedReferences:Int
	Field arrayInitializerRequired:Int
	Field constructorFunctionIds:String[] = New String[0]
	Field fields:TCompilerIrStructField[] = New TCompilerIrStructField[0]
End Type

Type TCompilerIrClass Extends TCompilerIrNode
	Field classId:String
	Field baseClassId:String
	Field baseImportedClassId:String
	Field name:String
	Field abiName:String
	Field semanticType:String
	Field visibility:Int
	Field isPublished:Int
	Field hasStableLocalAbi:Int
	Field isAbstract:Int
	Field fields:TCompilerIrClassField[] = New TCompilerIrClassField[0]
	Field declaredFieldStart:Int
	Field declaredFieldCount:Int
	Field functionSlots:TCompilerIrClassFunctionSlot[] = New TCompilerIrClassFunctionSlot[0]
	Field declaredInterfaceIds:String[] = New String[0]
	Field interfaceImplementations:TCompilerIrInterfaceImplementation[] = New TCompilerIrInterfaceImplementation[0]
	Field hasManagedFields:Int
	Field defaultConstructorFunctionId:String
	Field destructorFunctionId:String
	Field toStringFunctionId:String
	Field compareFunctionId:String
	Field sendMessageFunctionId:String
	Field hashCodeFunctionId:String
	Field equalsFunctionId:String
End Type

' An imported class is an ABI reference, not an emitted layout. Its defining
' module owns the object struct, BBClass descriptor and runtime registration.
Type TCompilerIrImportedClass Extends TCompilerIrNode
	Field importedClassId:String
	Field baseImportedClassId:String
	Field name:String
	Field semanticType:String
	Field abiName:String
	Field originModule:String
	Field isGenericSpecialization:Int
	Field specializationIdentity:String
	Field generatedUnit:String
	Field registerFunctionName:String
	Field isAbstract:Int
	Field hasManagedFields:Int
	Field destructorFunctionId:String
	Field toStringFunctionId:String
	Field compareFunctionId:String
	Field sendMessageFunctionId:String
	Field hashCodeFunctionId:String
	Field equalsFunctionId:String
	Field fields:TCompilerIrImportedField[] = New TCompilerIrImportedField[0]
	Field methods:TCompilerIrImportedMethod[] = New TCompilerIrImportedMethod[0]
	Field constructors:TCompilerIrImportedConstructor[] = New TCompilerIrImportedConstructor[0]
	Field functionSlots:TCompilerIrClassFunctionSlot[] = New TCompilerIrClassFunctionSlot[0]
	Field implementedInterfaceIds:String[] = New String[0]
End Type

Type TCompilerIrImportedStruct Extends TCompilerIrNode
	Field importedStructId:String
	Field name:String
	Field abiName:String
	Field elementInitializerAbiName:String
	Field semanticType:String
	Field originModule:String
	Field isGenericSpecialization:Int
	Field specializationIdentity:String
	Field generatedUnit:String
	Field registerFunctionName:String
	Field containsManagedReferences:Int
	Field fields:TCompilerIrImportedField[] = New TCompilerIrImportedField[0]
	Field routines:TCompilerIrImportedStructRoutine[] = New TCompilerIrImportedStructRoutine[0]
End Type

Type TCompilerIrImportedStructRoutine Extends TCompilerIrNode
	Field routineId:String
	Field name:String
	Field abiName:String
	Field implementationAbiName:String
	Field objectNewAbiName:String
	Field returnType:String
	Field callableReturnType:String
	Field callableReturnParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableReturnCallingConvention:String = "c"
	Field callingConvention:String = "c"
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field isMethod:Int
	Field isConstructor:Int
End Type

Type TCompilerIrImportedField Extends TCompilerIrNode
	Field fieldId:String
	Field declaringImportedClassId:String
	Field declaringImportedStructId:String
	Field name:String
	Field abiName:String
	Field semanticType:String
	Field structId:String
	Field importedStructId:String
	Field isStaticArray:Int
	Field staticArrayElementType:String
	Field staticArrayStructId:String
	Field staticArrayImportedStructId:String
	Field staticArrayLength:Long
	Field callableReturnType:String
	Field callableParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableCallingConvention:String = "c"
	Field visibility:Int
	Field isReadOnly:Int
End Type

Type TCompilerIrImportedMethod Extends TCompilerIrNode
	Field methodId:String
	Field declaringImportedClassId:String
	Field name:String
	Field abiName:String
	Field implementationAbiName:String
	Field slotName:String
	Field returnType:String
	Field callableReturnType:String
	Field callableReturnParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableReturnCallingConvention:String = "c"
	Field callingConvention:String = "c"
	Field isAbstract:Int
	Field isDestructor:Int
	Field isTypeFunction:Int
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
End Type

Type TCompilerIrImportedConstructor Extends TCompilerIrNode
	Field constructorId:String
	Field declaringImportedClassId:String
	Field abiName:String
	Field implementationAbiName:String
	Field objectNewAbiName:String
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
End Type

Type TCompilerIrInterfaceMethod Extends TCompilerIrNode
	Field slotId:String
	Field slotAbiName:String
	Field name:String
	Field declaringInterfaceId:String
	Field abiName:String
	Field returnType:String
	Field callableReturnType:String
	Field callableReturnParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableReturnCallingConvention:String = "c"
	Field callingConvention:String = "c"
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field implementationKind:Int = INTERFACE_METHOD_ABSTRACT
	Field defaultFunctionId:String
	Field defaultImplementationAbiName:String
End Type

Type TCompilerIrInterface Extends TCompilerIrNode
	Field interfaceId:String
	Field name:String
	Field semanticType:String
	Field visibility:Int
	Field isImported:Int
	Field isExternInterface:Int
	Field abiName:String
	Field methodsAbiName:String
	Field methodsLayoutOwnedExternally:Int
	Field originModule:String
	Field baseInterfaceIds:String[] = New String[0]
	Field methods:TCompilerIrInterfaceMethod[] = New TCompilerIrInterfaceMethod[0]
End Type

Type TCompilerIrInterfaceImplementationSlot
	Field interfaceSlotId:String
	Field functionId:String
	Field functionAbiName:String
	Field receiverClassId:String
End Type

Type TCompilerIrInterfaceImplementation
	Field interfaceId:String
	Field slots:TCompilerIrInterfaceImplementationSlot[] = New TCompilerIrInterfaceImplementationSlot[0]
End Type

Type TCompilerIrClassFunctionSlot Extends TCompilerIrNode
	Field slotId:String
	Field dispatchKey:String
	Field declaringClassId:String
	Field declaringImportedClassId:String
	Field receiverClassId:String
	Field receiverImportedClassId:String
	Field functionId:String
	Field name:String
	Field abiName:String
	Field slotName:String
	Field returnType:String
	Field callableReturnType:String
	Field callableReturnParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field callableReturnCallingConvention:String = "c"
	Field callingConvention:String = "c"
	Field parameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field isMethod:Int
	Field isAbstract:Int
End Type

Type TCompilerIrDependency
	Field logicalName:String
	Field interfacePath:String
	Field headerPath:String
	Field registerFunctionName:String
	Field initializeFunctionName:String
	Field source:TCompilerSourceLocation
End Type

Type TCompilerIrIncbin
	Field path:String
	Field dataSymbol:String
	Field sizeSymbol:String
	Field stringLiteralId:String
	Field source:TCompilerSourceLocation
End Type

Type TCompilerIrInitializationStep
	Field kind:Int
	Field dependency:TCompilerIrDependency
	Field source:TCompilerSourceLocation
End Type

' A specialization-owned hook that must run when this source unit is
' registered.  The hook is emitted in its separate generic C unit; ordinary
' module initialization owns only the deterministic call edge.
Type TCompilerIrGenericImplementationRegistration
	Field specializationIdentity:String
	Field functionName:String
	Field source:TCompilerSourceLocation
End Type

Type TCompilerIrGenericCoverageRegistration
	Field specializationIdentity:String
	Field functionName:String
	Field source:TCompilerSourceLocation
End Type

Type TCompilerIrInitializationPlan
	Field unitKind:Int
	Field unitName:String
	Field registerFunctionName:String
	Field initializeFunctionName:String
	Field dependencies:TCompilerIrDependency[] = New TCompilerIrDependency[0]
	Field registrationSteps:TCompilerIrInitializationStep[] = New TCompilerIrInitializationStep[0]
	Field initializationSteps:TCompilerIrInitializationStep[] = New TCompilerIrInitializationStep[0]
	Field genericImplementationRegistrations:TCompilerIrGenericImplementationRegistration[] = New TCompilerIrGenericImplementationRegistration[0]
	Field genericCoverageRegistrations:TCompilerIrGenericCoverageRegistration[] = New TCompilerIrGenericCoverageRegistration[0]
End Type

Type TCompilerIrModule
	Field path:String
	Field targetPlatform:String
	Field targetArchitecture:String
	Field buildMode:String
	Field gdbDebug:Int
	' Native headers imported by this compilation unit. The generated public
	' header republishes these includes so bang-marked native declarations keep
	' their typedef-rich C authority without reconstructed prototypes.
	Field nativeHeaders:String[] = New String[0]
	' Modules whose generated headers are reachable from the direct dependency
	' includes. Runtime backends treat declarations from these modules as
	' header-owned instead of reconstructing their ABI from semantic types.
	Field headerOwnedModules:String[] = New String[0]
	Field functions:TCompilerIrFunction[] = New TCompilerIrFunction[0]
	Field externalFunctions:TCompilerIrExternalFunction[] = New TCompilerIrExternalFunction[0]
	Field externalGlobals:TCompilerIrExternalGlobal[] = New TCompilerIrExternalGlobal[0]
	Field stringLiterals:TCompilerIrStringLiteral[] = New TCompilerIrStringLiteral[0]
	Field closureLiterals:TCompilerIrClosureLiteral[] = New TCompilerIrClosureLiteral[0]
	Field dataItems:TCompilerIrDataItem[] = New TCompilerIrDataItem[0]
	Field incbins:TCompilerIrIncbin[] = New TCompilerIrIncbin[0]
	Field enums:TCompilerIrEnum[] = New TCompilerIrEnum[0]
	Field structs:TCompilerIrStruct[] = New TCompilerIrStruct[0]
	Field importedStructs:TCompilerIrImportedStruct[] = New TCompilerIrImportedStruct[0]
	Field classes:TCompilerIrClass[] = New TCompilerIrClass[0]
	Field importedClasses:TCompilerIrImportedClass[] = New TCompilerIrImportedClass[0]
	Field interfaces:TCompilerIrInterface[] = New TCompilerIrInterface[0]
	' Constructed Interface types required only as managed ABI carriers by an
	' imported class layout/signature. Method dispatch still requires a
	' canonical specialization in interfaces[].
	Field opaqueInterfaceTypes:String[] = New String[0]
	Field initializationPlan:TCompilerIrInitializationPlan
	Field debugSources:TCompilerIrDebugSource[] = New TCompilerIrDebugSource[0]
	Field coverageFiles:TCompilerIrCoverageFile[] = New TCompilerIrCoverageFile[0]
	Field hasDebugBoundsChecks:Int
	Field hasDebugPointerChecks:Int
	' Reserved for later canonical generic-instance, reflection and metadata
	' records. These are module-level contracts, not C-backend side effects.
	Field genericInstances:String[] = New String[0]
	Field reflectionRecords:String[] = New String[0]
	Field metadataRecords:String[] = New String[0]
End Type
