' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BlitzMax.Compiler
Import BlitzMax.Locale

If AppArgs.length <> 2 Then Throw "Expected the compiled bcc.bmxcat path"

Local germanContext:TLocaleContext = New TLocaleContext("de-de")
germanContext.LoadCatalogue(AppArgs[1])

Local missing:TCompilerResult = TBlitzMaxCompiler.CompileFile("missing-localisation-test-source.bmx")
If missing.diagnostics.length <> 1 Then Throw "Expected one missing-source diagnostic"
AssertEqual("Die Quelldatei wurde nicht gefunden", missing.diagnostics[0].MessageFor(germanContext), "translated source diagnostic")
AssertIdentity(missing.diagnostics[0], BCC_MSG_SOURCE_FILE_NOT_FOUND, "source diagnostic")

Local emissionDiagnostics:TCompilerDiagnostic[]
TBlitzMaxCompiler.EmitC(Null, emissionDiagnostics)
If emissionDiagnostics.length <> 1 Then Throw "Expected one C-emission diagnostic"
AssertEqual("Successful compiler IR is required before C emission", emissionDiagnostics[0].MessageFor(germanContext), "untranslated emission fallback")
AssertIdentity(emissionDiagnostics[0], BCC_MSG_EMISSION_C_REQUIRES_SUCCESSFUL_IR, "C-emission diagnostic")

Local unsafeFile:TCompilerBuildOutputFile = New TCompilerBuildOutputFile
unsafeFile.relativePath = "../escaped.c"
Local plan:TCompilerBuildOutputPlan = New TCompilerBuildOutputPlan
Local planDiagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]
plan.AddFile(unsafeFile, planDiagnostics)
If planDiagnostics.length <> 1 Then Throw "Expected one unsafe-output diagnostic"
AssertEqual("Generated output path must be a bounded relative path: '../escaped.c'", planDiagnostics[0].MessageFor(germanContext), "build-output placeholder fallback")
AssertIdentity(planDiagnostics[0], BCC_MSG_BUILD_OUTPUT_PATH_MUST_BE_BOUNDED_RELATIVE, "build-output diagnostic")

Local manifestDiagnostics:TCompilerDiagnostic[]
TCompilerBuildOutputPlanner.DecodeManifest("BMXBUILD 99~n", manifestDiagnostics)
If manifestDiagnostics.length <> 1 Then Throw "Expected one manifest-version diagnostic"
AssertEqual("Unsupported or missing compiler build manifest version", manifestDiagnostics[0].MessageFor(germanContext), "manifest fallback")
AssertIdentity(manifestDiagnostics[0], BCC_MSG_BUILD_MANIFEST_VERSION_UNSUPPORTED_OR_MISSING, "manifest diagnostic")

Local materializationDiagnostics:TCompilerDiagnostic[]
TCompilerBuildOutputMaterializer.Materialize(Null, "", "", materializationDiagnostics)
If materializationDiagnostics.length <> 1 Then Throw "Expected one materialization diagnostic"
AssertEqual("A valid build-output plan is required before materialization", materializationDiagnostics[0].MessageFor(germanContext), "materialization fallback")
AssertIdentity(materializationDiagnostics[0], BCC_MSG_BUILD_MATERIALIZATION_PLAN_REQUIRED, "materialization diagnostic")

Local genericDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC3040", TBccMessages.GenericSpecializationArgumentIdentityUnsupported("TValue"))
AssertEqual("Generic specialization argument 'TValue' has no supported canonical value or published reference identity", genericDiagnostic.MessageFor(germanContext), "generic placeholder fallback")
AssertIdentity(genericDiagnostic, BCC_MSG_GENERIC_SPECIALIZATION_ARGUMENT_IDENTITY_UNSUPPORTED, "generic diagnostic")

Local interfaceDiagnostics:TCompilerDiagnostic[]
TCompilerInterfaceEmitter.Emit(Null, Null, interfaceDiagnostics)
If interfaceDiagnostics.length <> 1 Then Throw "Expected one interface-emission diagnostic"
AssertEqual("Compact interface emission requires a module compilation", interfaceDiagnostics[0].MessageFor(germanContext), "interface-emission fallback")
AssertIdentity(interfaceDiagnostics[0], BCC_MSG_INTERFACE_EMISSION_MODULE_COMPILATION_REQUIRED, "interface-emission diagnostic")

Local enumDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2075", TBccMessages.InterfaceEmissionEnumUnderlyingTypeUnsupported("EState", "String"))
AssertEqual("Public Enum 'EState' has unsupported underlying type 'String'", enumDiagnostic.MessageFor(germanContext), "interface placeholder fallback")
AssertIdentity(enumDiagnostic, BCC_MSG_INTERFACE_EMISSION_ENUM_UNDERLYING_TYPE_UNSUPPORTED, "interface placeholder diagnostic")

Local constructorDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1201", TBccMessages.IrLoweringRecursiveStructConstructorDelegation("New"))
AssertEqual("Recursive Struct constructor delegation involving 'New'", constructorDiagnostic.MessageFor(germanContext), "IR constructor placeholder fallback")
AssertIdentity(constructorDiagnostic, BCC_MSG_IR_LOWERING_RECURSIVE_STRUCT_CONSTRUCTOR_DELEGATION, "IR constructor diagnostic")

Local throwDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1215", TBccMessages.IrLoweringThrowRequiresManagedExpression())
AssertEqual("Throw requires a managed Object, String, or Array expression", throwDiagnostic.MessageFor(germanContext), "IR Throw fallback")
AssertIdentity(throwDiagnostic, BCC_MSG_IR_LOWERING_THROW_REQUIRES_MANAGED_EXPRESSION, "IR Throw diagnostic")

Local enumLoweringDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1102", TBccMessages.IrLoweringImportedEnumHasNoResolvedSemanticType("Example.EState"))
AssertEqual("Imported Enum 'Example.EState' has no resolved semantic type", enumLoweringDiagnostic.MessageFor(germanContext), "IR Enum placeholder fallback")
AssertIdentity(enumLoweringDiagnostic, BCC_MSG_IR_LOWERING_IMPORTED_ENUM_HAS_NO_RESOLVED_SEMANTIC_TYPE, "IR Enum diagnostic")

Local structLoweringDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1192", TBccMessages.IrLoweringStructValueLayoutCycle("TNode"))
AssertEqual("Struct value layout cycle involving 'TNode'", structLoweringDiagnostic.MessageFor(germanContext), "IR Struct placeholder fallback")
AssertIdentity(structLoweringDiagnostic, BCC_MSG_IR_LOWERING_STRUCT_VALUE_LAYOUT_CYCLE, "IR Struct diagnostic")

Local interfaceLoweringDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1164", TBccMessages.IrLoweringInterfaceMethodImplementationMissing("IWriter", "Write"))
AssertEqual("Interface method 'IWriter.Write' has no lowered implementation", interfaceLoweringDiagnostic.MessageFor(germanContext), "IR Interface placeholder fallback")
AssertIdentity(interfaceLoweringDiagnostic, BCC_MSG_IR_LOWERING_INTERFACE_METHOD_IMPLEMENTATION_MISSING, "IR Interface diagnostic")

Local typeLoweringDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1144", TBccMessages.IrLoweringTypeFieldTypeOutsideObjectLayoutSlice("Unsupported"))
AssertEqual("Field type 'Unsupported' is outside the simple object layout slice", typeLoweringDiagnostic.MessageFor(germanContext), "IR Type placeholder fallback")
AssertIdentity(typeLoweringDiagnostic, BCC_MSG_IR_LOWERING_TYPE_FIELD_TYPE_OUTSIDE_OBJECT_LAYOUT_SLICE, "IR Type diagnostic")

Local captureDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1248", TBccMessages.IrLoweringCapturedValueEnvironmentTypeUnsupported("offset", "Function"))
AssertEqual("captured value 'offset' has unsupported environment type 'Function'", captureDiagnostic.MessageFor(germanContext), "Closure capture placeholder fallback")
AssertIdentity(captureDiagnostic, BCC_MSG_IR_LOWERING_CAPTURED_VALUE_ENVIRONMENT_TYPE_UNSUPPORTED, "Closure capture diagnostic")

Local usingDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1214", TBccMessages.IrLoweringUsingResourceDoesNotExposeCloseableContract("stream"))
AssertEqual("Using resource 'stream' does not expose an ICloseable Interface contract", usingDiagnostic.MessageFor(germanContext), "Using resource placeholder fallback")
AssertIdentity(usingDiagnostic, BCC_MSG_IR_LOWERING_USING_RESOURCE_DOES_NOT_EXPOSE_CLOSEABLE_CONTRACT, "Using resource diagnostic")

Local closureAbiDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1244", TBccMessages.IrLoweringClosureNativeAbiRepresentationMissing())
AssertEqual("Closure values have no native ABI representation", closureAbiDiagnostic.MessageFor(germanContext), "Closure ABI fallback")
AssertIdentity(closureAbiDiagnostic, BCC_MSG_IR_LOWERING_CLOSURE_NATIVE_ABI_REPRESENTATION_MISSING, "Closure ABI diagnostic")

Local routineDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1106", TBccMessages.IrLoweringRoutineReturnTypeOutsideScalarSlice("Tuple"))
AssertEqual("Routine return type 'Tuple' is outside the scalar IR slice", routineDiagnostic.MessageFor(germanContext), "routine type placeholder fallback")
AssertIdentity(routineDiagnostic, BCC_MSG_IR_LOWERING_ROUTINE_RETURN_TYPE_OUTSIDE_SCALAR_SLICE, "routine type diagnostic")

Local externDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1102", TBccMessages.IrLoweringExternRoutineRequiresNativeAbiBinding())
AssertEqual("Extern routines require a native ABI binding", externDiagnostic.MessageFor(germanContext), "Extern routine fallback")
AssertIdentity(externDiagnostic, BCC_MSG_IR_LOWERING_EXTERN_ROUTINE_REQUIRES_NATIVE_ABI_BINDING, "Extern routine diagnostic")

Local iteratorDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1253", TBccMessages.IrLoweringIteratorInterfaceMethodImplementationMissing("MoveNext"))
AssertEqual("iterator Interface method 'MoveNext' has no generated implementation", iteratorDiagnostic.MessageFor(germanContext), "iterator placeholder fallback")
AssertIdentity(iteratorDiagnostic, BCC_MSG_IR_LOWERING_ITERATOR_INTERFACE_METHOD_IMPLEMENTATION_MISSING, "iterator diagnostic")

Local eachInDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1017", TBccMessages.IrLoweringArrayEachInElementTypeMismatch("Object", "String"))
AssertEqual("Array EachIn element type 'Object' cannot be assigned to loop variable type 'String'", eachInDiagnostic.MessageFor(germanContext), "EachIn placeholder fallback")
AssertIdentity(eachInDiagnostic, BCC_MSG_IR_LOWERING_ARRAY_EACH_IN_ELEMENT_TYPE_MISMATCH, "EachIn diagnostic")

Local statementDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1006", TBccMessages.IrLoweringBoundStatementKindUnsupported(42))
AssertEqual("Bound statement kind '42' is not implemented", statementDiagnostic.MessageFor(germanContext), "statement kind placeholder fallback")
AssertIdentity(statementDiagnostic, BCC_MSG_IR_LOWERING_BOUND_STATEMENT_KIND_UNSUPPORTED, "statement kind diagnostic")

Local assertDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1205", TBccMessages.IrLoweringAssertMessageTypeNotConvertibleToString("Tuple"))
AssertEqual("Assert message type 'Tuple' cannot be converted to String by the current IR", assertDiagnostic.MessageFor(germanContext), "Assert placeholder fallback")
AssertIdentity(assertDiagnostic, BCC_MSG_IR_LOWERING_ASSERT_MESSAGE_TYPE_NOT_CONVERTIBLE_TO_STRING, "Assert diagnostic")

Local operatorDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1123", TBccMessages.IrLoweringStringBinaryOperationUnsupported("Shl"))
AssertEqual("String binary operation 'Shl' is not implemented", operatorDiagnostic.MessageFor(germanContext), "operator placeholder fallback")
AssertIdentity(operatorDiagnostic, BCC_MSG_IR_LOWERING_STRING_BINARY_OPERATION_UNSUPPORTED, "operator diagnostic")

Local expressionDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1015", TBccMessages.IrLoweringBoundExpressionKindUnsupported(17))
AssertEqual("Bound expression kind '17' is not implemented", expressionDiagnostic.MessageFor(germanContext), "expression kind placeholder fallback")
AssertIdentity(expressionDiagnostic, BCC_MSG_IR_LOWERING_BOUND_EXPRESSION_KIND_UNSUPPORTED, "expression kind diagnostic")

Local callDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1012", TBccMessages.IrLoweringCallTargetUnsupported("Example.Run", "Example.TValue"))
AssertEqual("Call target 'Example.Run' on receiver type 'Example.TValue' is not implemented", callDiagnostic.MessageFor(germanContext), "call target placeholder fallback")
AssertIdentity(callDiagnostic, BCC_MSG_IR_LOWERING_CALL_TARGET_UNSUPPORTED, "call target diagnostic")

Local inheritedSlotDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1173", TBccMessages.IrLoweringImportedMethodInheritedSlotMissing("Write", "TWriter", "IWriter", "TBase"))
AssertEqual("Imported method 'Write' has no inherited slot in source receiver type 'TWriter' (declaring imported class 'IWriter', source imported base 'TBase')", inheritedSlotDiagnostic.MessageFor(germanContext), "inherited slot placeholder fallback")
AssertIdentity(inheritedSlotDiagnostic, BCC_MSG_IR_LOWERING_IMPORTED_METHOD_INHERITED_SLOT_MISSING, "inherited slot diagnostic")

Local indirectCallDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1184", TBccMessages.IrLoweringIndirectCallArgumentCountMismatch(2, 3))
AssertEqual("Indirect call requires 2 arguments but received 3", indirectCallDiagnostic.MessageFor(germanContext), "indirect call count fallback")
AssertIdentity(indirectCallDiagnostic, BCC_MSG_IR_LOWERING_INDIRECT_CALL_ARGUMENT_COUNT_MISMATCH, "indirect call diagnostic")

Local fieldLayoutDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1146", TBccMessages.IrLoweringFieldAccessOutsideObjectLayout("receiver 'TValue'"))
AssertEqual("Field access is outside the lowered object layout (receiver 'TValue')", fieldLayoutDiagnostic.MessageFor(germanContext), "field layout placeholder fallback")
AssertIdentity(fieldLayoutDiagnostic, BCC_MSG_IR_LOWERING_FIELD_ACCESS_OUTSIDE_OBJECT_LAYOUT, "field layout diagnostic")

Local importedRoutineDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1112", TBccMessages.IrLoweringImportedRoutineParameterOutsideOrdinaryCAbi("Example.Run", "Tuple"))
AssertEqual("Imported routine 'Example.Run' parameter type 'Tuple' is outside the supported ordinary-C ABI slice", importedRoutineDiagnostic.MessageFor(germanContext), "imported routine placeholder fallback")
AssertIdentity(importedRoutineDiagnostic, BCC_MSG_IR_LOWERING_IMPORTED_ROUTINE_PARAMETER_OUTSIDE_ORDINARY_C_ABI, "imported routine diagnostic")

Local importedMethodDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1172", TBccMessages.IrLoweringImportedMethodClassSlotAbiNameMissing("Example.Write", "_example_write"))
AssertEqual("Imported method 'Example.Write' has no class-slot ABI name derived from '_example_write'", importedMethodDiagnostic.MessageFor(germanContext), "imported method placeholder fallback")
AssertIdentity(importedMethodDiagnostic, BCC_MSG_IR_LOWERING_IMPORTED_METHOD_CLASS_SLOT_ABI_NAME_MISSING, "imported method diagnostic")

Local enumIntrinsicDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1103", TBccMessages.IrLoweringEnumInstanceIntrinsicReceiverMissing("Ordinal"))
AssertEqual("Enum instance intrinsic 'Ordinal' has no receiver", enumIntrinsicDiagnostic.MessageFor(germanContext), "Enum intrinsic placeholder fallback")
AssertIdentity(enumIntrinsicDiagnostic, BCC_MSG_IR_LOWERING_ENUM_INSTANCE_INTRINSIC_RECEIVER_MISSING, "Enum intrinsic diagnostic")

Local eachInProtocolDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC1020", TBccMessages.IrLoweringEachInProtocolMethodRequiresNonDefaultArgument("ObjectEnumerator"))
AssertEqual("EachIn protocol method 'ObjectEnumerator' requires a non-default argument", eachInProtocolDiagnostic.MessageFor(germanContext), "EachIn protocol placeholder fallback")
AssertIdentity(eachInProtocolDiagnostic, BCC_MSG_IR_LOWERING_EACH_IN_PROTOCOL_METHOD_REQUIRES_NON_DEFAULT_ARGUMENT, "EachIn protocol diagnostic")

Local cBackendDiagnostics:TCompilerDiagnostic[]
TCompilerCBackend.Emit(Null, cBackendDiagnostics)
If cBackendDiagnostics.length <> 1 Then Throw "Expected one missing-IR C-backend diagnostic"
AssertEqual("Compiler IR module was not available", cBackendDiagnostics[0].MessageFor(germanContext), "C-backend internal fallback")
AssertIdentity(cBackendDiagnostics[0], BCC_MSG_C_BACKEND_COMPILER_IR_MODULE_UNAVAILABLE, "C-backend internal diagnostic")

Local picoFieldDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2029", TBccMessages.CBackendPicoImportedTypeFieldUnsupported("TValue", "items"))
AssertEqual("Imported Type field 'TValue.items' is outside the current Pico object-layout slice", picoFieldDiagnostic.MessageFor(germanContext), "Pico field placeholder fallback")
AssertIdentity(picoFieldDiagnostic, BCC_MSG_C_BACKEND_PICO_IMPORTED_TYPE_FIELD_UNSUPPORTED, "Pico field diagnostic")

Local backendLayoutDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2084", TBccMessages.CBackendDebugVariableTypetagIncomplete("item", "Tuple"))
AssertEqual("Debug variable 'item' has no complete typetag for semantic type 'Tuple'", backendLayoutDiagnostic.MessageFor(germanContext), "backend layout placeholder fallback")
AssertIdentity(backendLayoutDiagnostic, BCC_MSG_C_BACKEND_DEBUG_VARIABLE_TYPETAG_INCOMPLETE, "backend layout diagnostic")

Local picoThrowDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2100", TBccMessages.CBackendPicoThrowTypeUnsupported("Int"))
AssertEqual("Pico Throw requires an Object, String, Array, class, interface, or closure value; 'Int' is not supported", picoThrowDiagnostic.MessageFor(germanContext), "Pico Throw placeholder fallback")
AssertIdentity(picoThrowDiagnostic, BCC_MSG_C_BACKEND_PICO_THROW_TYPE_UNSUPPORTED, "Pico Throw diagnostic")

Local backendSlotDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2053", TBccMessages.CBackendVirtualCallSlotNotEmitted("TWidget", "Draw"))
AssertEqual("Virtual call slot 'TWidget.Draw' was not emitted", backendSlotDiagnostic.MessageFor(germanContext), "backend slot placeholder fallback")
AssertIdentity(backendSlotDiagnostic, BCC_MSG_C_BACKEND_VIRTUAL_CALL_SLOT_NOT_EMITTED, "backend slot diagnostic")

Local backendArrayDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2028", TBccMessages.CBackendPicoArrayElementTypeUnsupported("Function"))
AssertEqual("Array element type 'Function' is not available in the Pico managed-container profile", backendArrayDiagnostic.MessageFor(germanContext), "backend Array placeholder fallback")
AssertIdentity(backendArrayDiagnostic, BCC_MSG_C_BACKEND_PICO_ARRAY_ELEMENT_TYPE_UNSUPPORTED, "backend Array diagnostic")

Local interfaceSlotDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2055", TBccMessages.CBackendInterfaceCallSlotNotEmitted("IWriter", "Write"))
AssertEqual("Interface call slot 'IWriter.Write' was not emitted", interfaceSlotDiagnostic.MessageFor(germanContext), "Interface slot placeholder fallback")
AssertIdentity(interfaceSlotDiagnostic, BCC_MSG_C_BACKEND_INTERFACE_CALL_SLOT_NOT_EMITTED, "Interface slot diagnostic")

Local catchDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2101", TBccMessages.CBackendPicoCatchTypeUnsupported("Int"))
AssertEqual("Pico Catch supports Object, String, Array, and class/interface types with a compact descriptor ABI; 'Int' is not supported", catchDiagnostic.MessageFor(germanContext), "Pico Catch placeholder fallback")
AssertIdentity(catchDiagnostic, BCC_MSG_C_BACKEND_PICO_CATCH_TYPE_UNSUPPORTED, "Pico Catch diagnostic")

Local conversionDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2090", TBccMessages.CBackendManagedNarrowingConversionReachedRawCast("Object", "TWidget"))
AssertEqual("Managed narrowing conversion from 'Object' to 'TWidget' reached the raw C cast fallback", conversionDiagnostic.MessageFor(germanContext), "conversion placeholder fallback")
AssertIdentity(conversionDiagnostic, BCC_MSG_C_BACKEND_MANAGED_NARROWING_CONVERSION_REACHED_RAW_CAST, "conversion diagnostic")

Local scalarOperatorDiagnostic:TCompilerDiagnostic = TCompilerDiagnostic.Create("BMXC2023", TBccMessages.CBackendBinaryOperatorUnsupported("Rotl"))
AssertEqual("Binary operator 'Rotl' has no scalar C99 lowering", scalarOperatorDiagnostic.MessageFor(germanContext), "scalar operator placeholder fallback")
AssertIdentity(scalarOperatorDiagnostic, BCC_MSG_C_BACKEND_BINARY_OPERATOR_UNSUPPORTED, "scalar operator diagnostic")

Print "PASS: compiler diagnostics retain bcc message identities and locale fallbacks"

Function AssertIdentity(diagnostic:TCompilerDiagnostic, expectedId:Int, label:String)
	If Not diagnostic.localisedMessage Then Throw label + " did not retain its localised message"
	If diagnostic.localisedMessage.domain <> "bcc" Then Throw label + " has unexpected domain"
	If diagnostic.localisedMessage.id <> expectedId Then Throw label + " has unexpected message ID"
End Function

Function AssertEqual(expected:String, actual:String, label:String)
	If expected <> actual Then Throw label + ": expected '" + expected + "', got '" + actual + "'"
End Function
