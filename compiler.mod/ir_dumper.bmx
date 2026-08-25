' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BlitzMax.Language
Import "ir_model.bmx"

Type TCompilerIrDumper
	Function Dump:String(irModule:TCompilerIrModule)
		If Not irModule Then Return "<missing compiler IR>~n"
		Local result:String = "module " + Quoted(irModule.path) + "~n"
		result :+ "target " + irModule.targetPlatform + "/" + irModule.targetArchitecture + " " + irModule.buildMode + "~n"
		For Local logicalName:String = EachIn irModule.headerOwnedModules
			result :+ "header-owner " + logicalName + "~n"
		Next
		result :+ DumpInitializationPlan(irModule.initializationPlan)
		For Local debugSource:TCompilerIrDebugSource = EachIn irModule.debugSources
			result :+ "debug-source " + debugSource.sourceId + " " + Quoted(debugSource.path) + "~n"
		Next
		For Local coverageFile:TCompilerIrCoverageFile = EachIn irModule.coverageFiles
			result :+ "coverage-file " + Quoted(coverageFile.path) + "~n"
			For Local line:Int = EachIn coverageFile.lines
				result :+ "  coverage-line " + line + "~n"
			Next
			For Local coverageFunction:TCompilerIrCoverageFunction = EachIn coverageFile.functions
				result :+ "  coverage-function " + coverageFunction.line + " " + Quoted(coverageFunction.name) + "~n"
			Next
		Next
		For Local stringLiteral:TCompilerIrStringLiteral = EachIn irModule.stringLiterals
			result :+ "string @" + stringLiteral.literalId + " " + Quoted(stringLiteral.value) + " " + Location(stringLiteral.source) + "~n"
		Next
		For Local index:Int = 0 Until irModule.dataItems.length
			Local item:TCompilerIrDataItem = irModule.dataItems[index]
			Local value:String = item.valueText
			If item.stringLiteralId.length Then value = "string @" + item.stringLiteralId
			result :+ "data " + index + " " + item.typeTag + " " + value + " " + Location(item.source) + "~n"
		Next
		For Local externalFunction:TCompilerIrExternalFunction = EachIn irModule.externalFunctions
			result :+ DumpExternalFunction(externalFunction)
		Next
		For Local externalGlobal:TCompilerIrExternalGlobal = EachIn irModule.externalGlobals
			result :+ DumpExternalGlobal(externalGlobal)
		Next
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			result :+ DumpEnum(irEnum)
		Next
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			result :+ DumpImportedStruct(importedStruct)
		Next
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			result :+ DumpImportedClass(importedClass)
		Next
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			result :+ DumpInterface(irInterface)
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			result :+ DumpStruct(irStruct)
		Next
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			result :+ DumpClass(irClass)
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			result :+ DumpFunction(routine)
		Next
		Return result
	End Function

	Function DumpEnum:String(irEnum:TCompilerIrEnum)
		Local result:String = "enum @" + irEnum.enumId + " " + irEnum.name + ":" + irEnum.semanticType + " underlying " + irEnum.underlyingType
		If irEnum.isFlags Then result :+ " [flags]"
		If irEnum.isPublished Then result :+ " [published abi " + irEnum.abiName + "]"
		If irEnum.isImported Then
			result :+ " [imported abi " + irEnum.abiName
			If irEnum.originModule.length Then result :+ " from " + irEnum.originModule
			result :+ "]"
		End If
		If irEnum.runtimeDescriptor Then
			result :+ " [runtime " + irEnum.runtimeDescriptor.numericTypeTag + " " + irEnum.runtimeDescriptor.arrayTypeEncoding + " descriptor " + irEnum.runtimeDescriptor.descriptorAbiName + "]"
		End If
		result :+ " " + Location(irEnum.source) + "~n"
		For Local value:TCompilerIrEnumValue = EachIn irEnum.values
			result :+ "  value " + value.name + " = " + value.integerValue + " " + Location(value.source) + "~n"
		Next
		Return result
	End Function

	Function DumpImportedStruct:String(importedStruct:TCompilerIrImportedStruct)
		Local result:String = "imported-struct @" + importedStruct.importedStructId + " " + importedStruct.name + ":" + importedStruct.semanticType + " abi " + importedStruct.abiName
		If importedStruct.originModule.length Then result :+ " from " + importedStruct.originModule
		If importedStruct.elementInitializerAbiName.length Then result :+ " [element-initializer " + importedStruct.elementInitializerAbiName + "]"
		If importedStruct.registerFunctionName.length Then result :+ " [register " + importedStruct.registerFunctionName + "]"
		If importedStruct.containsManagedReferences Then result :+ " [managed-references]" Else result :+ " [atomic-value]"
		result :+ " " + Location(importedStruct.source) + "~n"
		For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
			result :+ "  field %" + importedField.fieldId + " " + importedField.name + ":" + importedField.semanticType + " abi " + importedField.abiName
			If importedField.structId.length Then result :+ " [struct @" + importedField.structId + "]"
			If importedField.importedStructId.length Then result :+ " [imported-struct @" + importedField.importedStructId + "]"
			If importedField.isStaticArray Then
				result :+ " [static-array " + importedField.staticArrayElementType + " x " + importedField.staticArrayLength + "]"
				If importedField.staticArrayStructId.length Then result :+ " [element-layout struct @" + importedField.staticArrayStructId + "]"
				If importedField.staticArrayImportedStructId.length Then result :+ " [element-layout imported-struct @" + importedField.staticArrayImportedStructId + "]"
			End If
			If importedField.isReadOnly Then result :+ " [readonly]"
			result :+ " " + Location(importedField.source) + "~n"
		Next
		For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
			Local kind:String = "function"
			If routine.isConstructor Then
				kind = "constructor"
			Else If routine.isMethod Then
				kind = "method"
			End If
			result :+ "  " + kind + " %" + routine.routineId + " " + routine.name + "(" + ParameterTypes(routine.parameters) + ") -> " + routine.returnType + " abi " + routine.abiName
			If routine.implementationAbiName.length Then result :+ " implementation " + routine.implementationAbiName
			If routine.objectNewAbiName.length Then result :+ " object-new " + routine.objectNewAbiName
			result :+ " " + Location(routine.source) + "~n"
		Next
		Return result
	End Function

	Function DumpStruct:String(irStruct:TCompilerIrStruct)
		Local result:String = "struct @" + irStruct.structId + " " + irStruct.name + ":" + irStruct.semanticType
		If irStruct.isPublished Then result :+ " [published abi " + irStruct.abiName + "]"
		If irStruct.containsManagedReferences Then result :+ " [managed-references]" Else result :+ " [atomic-value]"
		result :+ " " + Location(irStruct.source) + "~n"
		result :+ DumpMetadata(irStruct.metadata, "  ")
		For Local irField:TCompilerIrStructField = EachIn irStruct.fields
			result :+ "  field %" + irField.fieldId + " " + irField.name + ":" + irField.semanticType
			If irField.callableReturnType.length Then result :+ " [callable " + irField.callableReturnType + "(" + ParameterTypes(irField.callableParameters) + ")]"
			If irField.abiName.length Then result :+ " [abi " + irField.abiName + "]"
			If irField.structId.length Then result :+ " [struct @" + irField.structId + "]"
			If irField.importedStructId.length Then result :+ " [imported-struct @" + irField.importedStructId + "]"
			If irField.isStaticArray Then
				result :+ " [static-array " + irField.staticArrayElementType + " x " + irField.staticArrayLength + "]"
				If irField.staticArrayStructId.length Then result :+ " [element-layout struct @" + irField.staticArrayStructId + "]"
				If irField.staticArrayImportedStructId.length Then result :+ " [element-layout imported-struct @" + irField.staticArrayImportedStructId + "]"
			End If
			If irField.isReadOnly Then result :+ " [readonly]"
			result :+ " " + Location(irField.source) + "~n"
			result :+ DumpMetadata(irField.metadata, "    ")
			If irField.initializer Then
				result :+ "    initializer~n"
				result :+ DumpExpression(irField.initializer, "      ")
			End If
		Next
		Return result
	End Function

	Function DumpImportedClass:String(importedClass:TCompilerIrImportedClass)
		Local result:String = "imported-class @" + importedClass.importedClassId + " " + importedClass.name + ":" + importedClass.semanticType + " abi " + importedClass.abiName
		If importedClass.baseImportedClassId.length Then result :+ " extends @" + importedClass.baseImportedClassId
		If importedClass.isAbstract Then result :+ " [abstract]"
		If importedClass.hasManagedFields Then result :+ " [managed-fields]" Else result :+ " [atomic-fields]"
		If importedClass.originModule.length Then result :+ " from " + importedClass.originModule
		result :+ " " + Location(importedClass.source) + "~n" + DumpMetadata(importedClass.metadata, "  ")
		For Local importedField:TCompilerIrImportedField = EachIn importedClass.fields
			result :+ "  field %" + importedField.fieldId + " " + importedField.name + ":" + importedField.semanticType + " abi " + importedField.abiName
			If importedField.structId.length Then result :+ " [struct @" + importedField.structId + "]"
			If importedField.importedStructId.length Then result :+ " [imported-struct @" + importedField.importedStructId + "]"
			If importedField.isStaticArray Then
				result :+ " [static-array " + importedField.staticArrayElementType + " x " + importedField.staticArrayLength + "]"
				If importedField.staticArrayStructId.length Then result :+ " [element-layout struct @" + importedField.staticArrayStructId + "]"
				If importedField.staticArrayImportedStructId.length Then result :+ " [element-layout imported-struct @" + importedField.staticArrayImportedStructId + "]"
			End If
			If importedField.callableReturnType.length Then result :+ " [callable " + importedField.callableReturnType + "(" + ParameterTypes(importedField.callableParameters) + ")]"
			If importedField.isReadOnly Then result :+ " [readonly]"
			result :+ " " + Location(importedField.source) + "~n"
		Next
		For Local importedMethod:TCompilerIrImportedMethod = EachIn importedClass.methods
			result :+ "  method %" + importedMethod.methodId + " " + importedMethod.name + "("
			For Local index:Int = 0 Until importedMethod.parameters.length
				If index Then result :+ ", "
				result :+ ParameterSignature(importedMethod.parameters[index])
			Next
			result :+ ") -> " + importedMethod.returnType + " slot " + importedMethod.slotName + " abi " + importedMethod.abiName
			If importedMethod.implementationAbiName.length Then result :+ " implementation " + importedMethod.implementationAbiName
			If importedMethod.isAbstract Then result :+ " [abstract]"
			result :+ " " + Location(importedMethod.source) + "~n"
		Next
		For Local constructor:TCompilerIrImportedConstructor = EachIn importedClass.constructors
			result :+ "  constructor %" + constructor.constructorId + "("
			For Local index:Int = 0 Until constructor.parameters.length
				If index Then result :+ ", "
				result :+ ParameterSignature(constructor.parameters[index])
			Next
			result :+ ") abi " + constructor.abiName
			If constructor.objectNewAbiName.length Then result :+ " object-new " + constructor.objectNewAbiName
			result :+ " " + Location(constructor.source) + "~n"
		Next
		If importedClass.destructorFunctionId.length Then result :+ "  destructor @" + importedClass.destructorFunctionId + "~n"
		result :+ DumpObjectSlot("ToString", importedClass.toStringFunctionId)
		result :+ DumpObjectSlot("Compare", importedClass.compareFunctionId)
		result :+ DumpObjectSlot("SendMessage", importedClass.sendMessageFunctionId)
		result :+ DumpObjectSlot("HashCode", importedClass.hashCodeFunctionId)
		result :+ DumpObjectSlot("Equals", importedClass.equalsFunctionId)
		Return result
	End Function

	Function DumpInterface:String(irInterface:TCompilerIrInterface)
		Local result:String = "interface @" + irInterface.interfaceId + " " + irInterface.name + ":" + irInterface.semanticType
		If irInterface.isExternInterface Then result :+ " [external-native abi " + irInterface.abiName + "]"
		If irInterface.baseInterfaceIds.length Then
			result :+ " extends "
			For Local index:Int = 0 Until irInterface.baseInterfaceIds.length
				If index Then result :+ ", "
				result :+ "@" + irInterface.baseInterfaceIds[index]
			Next
		End If
		If irInterface.isImported Then
			result :+ " [imported"
			If irInterface.abiName.length Then result :+ " abi " + irInterface.abiName
			If irInterface.originModule.length Then result :+ " from " + irInterface.originModule
			result :+ "]"
		End If
		result :+ " " + Location(irInterface.source) + "~n"
		result :+ DumpMetadata(irInterface.metadata, "  ")
		For Local interfaceMethod:TCompilerIrInterfaceMethod = EachIn irInterface.methods
			result :+ "  method %" + interfaceMethod.slotId + " " + interfaceMethod.name + "("
			For Local index:Int = 0 Until interfaceMethod.parameters.length
				If index Then result :+ ", "
				result :+ ParameterSignature(interfaceMethod.parameters[index])
			Next
			result :+ ") -> " + interfaceMethod.returnType
			If interfaceMethod.declaringInterfaceId <> irInterface.interfaceId Then result :+ " [inherited @" + interfaceMethod.declaringInterfaceId + "]"
			result :+ " " + Location(interfaceMethod.source) + "~n"
		Next
		Return result
	End Function

	Function DumpClass:String(irClass:TCompilerIrClass)
		Local result:String = "class @" + irClass.classId + " " + irClass.name + ":" + irClass.semanticType
		If irClass.baseClassId.length Then result :+ " extends @" + irClass.baseClassId
		If irClass.baseImportedClassId.length Then result :+ " extends imported @" + irClass.baseImportedClassId
		If irClass.isPublished Then result :+ " [published abi " + irClass.abiName + "]"
		If irClass.isAbstract Then result :+ " [abstract]"
		If irClass.hasManagedFields Then result :+ " [managed-fields]" Else result :+ " [atomic-fields]"
		result :+ " " + Location(irClass.source) + "~n"
		result :+ DumpMetadata(irClass.metadata, "  ")
		For Local irField:TCompilerIrClassField = EachIn irClass.fields
			result :+ "  field %" + irField.fieldId + " " + irField.name + ":" + irField.semanticType
			If irField.callableReturnType.length Then result :+ " [callable " + irField.callableReturnType + "(" + ParameterTypes(irField.callableParameters) + ")]"
			If irField.declaringClassId <> irClass.classId Then result :+ " [inherited @" + irField.declaringClassId + "]"
			If irField.declaringImportedClassId.length Then result :+ " [inherited imported @" + irField.declaringImportedClassId + "]"
			If irField.abiName.length Then result :+ " [abi " + irField.abiName + "]"
			If irField.isStaticArray Then
				result :+ " [static-array " + irField.staticArrayElementType + " x " + irField.staticArrayLength + "]"
				If irField.staticArrayStructId.length Then result :+ " [element-layout struct @" + irField.staticArrayStructId + "]"
				If irField.staticArrayImportedStructId.length Then result :+ " [element-layout imported-struct @" + irField.staticArrayImportedStructId + "]"
			End If
			If irField.isReadOnly Then result :+ " [readonly]"
			result :+ " " + Location(irField.source) + "~n"
			result :+ DumpMetadata(irField.metadata, "    ")
			If irField.initializer Then
				result :+ "    initializer~n"
				result :+ DumpExpression(irField.initializer, "      ")
			End If
		Next
		For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
			result :+ "  function-slot %" + slot.slotId + " @" + slot.functionId + " " + slot.name + "("
			For Local index:Int = 0 Until slot.parameters.length
				If index Then result :+ ", "
				result :+ ParameterType(slot.parameters[index])
			Next
			result :+ ") -> " + slot.returnType + " abi " + slot.abiName
			If slot.slotName.length Then result :+ " slot " + slot.slotName
			If slot.declaringClassId.length And slot.declaringClassId <> irClass.classId Then result :+ " [inherited-slot @" + slot.declaringClassId + "]"
			If slot.declaringImportedClassId.length Then result :+ " [inherited-slot imported @" + slot.declaringImportedClassId + "]"
			If slot.receiverClassId.length Then result :+ " [receiver @" + slot.receiverClassId + "]"
			If slot.receiverImportedClassId.length Then result :+ " [receiver imported @" + slot.receiverImportedClassId + "]"
			If slot.isAbstract Then result :+ " [abstract]"
			result :+ " " + Location(slot.source) + "~n"
		Next
		For Local implementation:TCompilerIrInterfaceImplementation = EachIn irClass.interfaceImplementations
			result :+ "  implements @" + implementation.interfaceId + "~n"
			For Local slot:TCompilerIrInterfaceImplementationSlot = EachIn implementation.slots
				If slot Then result :+ "    slot %" + slot.interfaceSlotId + " @" + slot.functionId + " receiver @" + slot.receiverClassId + "~n"
			Next
		Next
		result :+ DumpObjectSlot("ToString", irClass.toStringFunctionId)
		result :+ DumpObjectSlot("Compare", irClass.compareFunctionId)
		result :+ DumpObjectSlot("SendMessage", irClass.sendMessageFunctionId)
		result :+ DumpObjectSlot("HashCode", irClass.hashCodeFunctionId)
		result :+ DumpObjectSlot("Equals", irClass.equalsFunctionId)
		Return result
	End Function

	Function DumpObjectSlot:String(name:String, functionId:String)
		If Not functionId.length Then Return ""
		Return "  object-slot " + name + " @" + functionId + "~n"
	End Function

	Function DumpExternalGlobal:String(externalGlobal:TCompilerIrExternalGlobal)
		Local result:String = "external-global %" + externalGlobal.symbolId + " " + externalGlobal.sourceName + ":" + externalGlobal.semanticType + " abi " + externalGlobal.abiName
		If externalGlobal.callableReturnType.length Then result :+ " [callable " + externalGlobal.callableReturnType + "(" + ParameterTypes(externalGlobal.callableParameters) + ")]"
		If externalGlobal.callableCallingConvention = "stdcall" Then result :+ " [stdcall]"
		If externalGlobal.isReadOnly Then result :+ " [readonly]"
		If externalGlobal.isThreadedGlobal Then result :+ " [threaded]"
		If externalGlobal.originModule.length Then result :+ " from " + externalGlobal.originModule
		Return result + " " + Location(externalGlobal.source) + "~n"
	End Function

	Function DumpExternalFunction:String(externalFunction:TCompilerIrExternalFunction)
		Local result:String = "external @" + externalFunction.functionId + " " + externalFunction.sourceName + " abi " + externalFunction.abiName + "("
		For Local index:Int = 0 Until externalFunction.parameters.length
			If index Then result :+ ", "
			Local parameter:TCompilerIrParameter = externalFunction.parameters[index]
			result :+ parameter.name + ":" + ParameterSignature(parameter)
		Next
		result :+ ") -> " + externalFunction.returnType
		If externalFunction.callingConvention = "stdcall" Then result :+ " [stdcall]"
		If externalFunction.implementationAbiName.length And externalFunction.implementationAbiName <> externalFunction.abiName Then result :+ " [implementation " + externalFunction.implementationAbiName + "]"
		If externalFunction.isDirectMethod Then result :+ " [direct-method]"
		If externalFunction.suppressNativePrototype Then result :+ " [prototype-owned-externally]"
		If externalFunction.originModule.length Then result :+ " from " + externalFunction.originModule
		Return result + " " + Location(externalFunction.source) + "~n"
	End Function

	Function DumpFunction:String(routine:TCompilerIrFunction)
		Local result:String = "function @" + routine.functionId + " " + routine.name + "("
		For Local index:Int = 0 Until routine.parameters.length
			If index Then result :+ ", "
			Local parameter:TCompilerIrParameter = routine.parameters[index]
			result :+ "%" + parameter.symbolId + " " + parameter.name + ":" + ParameterSignature(parameter)
			If parameter.isOptional Then result :+ "=" + ParameterDefault(parameter)
		Next
		result :+ ") -> " + routine.returnType
		If routine.callingConvention = "stdcall" Then result :+ " [stdcall]"
		If routine.abiName.length Then result :+ " [abi " + routine.abiName + "]"
		If routine.implementationAbiName.length Then result :+ " [implementation " + routine.implementationAbiName + "]"
		If routine.noMangle Then result :+ " [nomangle]"
		If routine.isGlobalEntry Then result :+ " [global-entry]"
			If routine.ownerClassId.length Then
				result :+ " [class @" + routine.ownerClassId
			If routine.classSlotId.length Then result :+ " slot %" + routine.classSlotId
			If routine.objectSlotKind <> IR_OBJECT_SLOT_NONE Then result :+ " object-slot " + ObjectSlotName(routine.objectSlotKind)
				result :+ "]"
			End If
			If routine.ownerStructId.length Then result :+ " [struct @" + routine.ownerStructId + "]"
		If routine.isMethod Then result :+ " [method receiver " + routine.receiver.semanticType + "]"
		If routine.isAbstract Then result :+ " [abstract]"
		If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then result :+ " [constructor]"
		If routine.lifecycleKind = IR_LIFECYCLE_DESTRUCTOR Then result :+ " [destructor]"
		If routine.chainedConstructorFunctionId.length Then result :+ " [chains @" + routine.chainedConstructorFunctionId + "]"
		If routine.chainedImportedConstructorId.length Then result :+ " [chains imported @" + routine.chainedImportedConstructorId + "]"
		If routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_BASE Then result :+ " [base-chain]"
		If routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_SAME_TYPE Then result :+ " [same-type-chain]"
		If routine.debugInstrumentation Then result :+ " [debug]"
		If routine.suppressDebugInfo Then result :+ " [nodebug]"
		If routine.coverageInstrumentation Then result :+ " [coverage]"
		If routine.isIteratorFactory Then result :+ " [iterator-factory " + routine.iteratorElementType + "]"
		If routine.isIteratorMoveNext Then result :+ " [iterator-move-next " + routine.iteratorElementType + "]"
		result :+ " " + Location(routine.source) + "~n"
		result :+ DumpMetadata(routine.metadata, "  ")
		If routine.debugScope Then
			result :+ DumpDebugScope(routine.debugScope, "  ")
		End If
		result :+ DumpBlock(routine.body, "  ")
		Return result
	End Function

	Function ParameterDefault:String(parameter:TCompilerIrParameter)
		Select parameter.defaultKind
			Case CONSTANT_VALUE_INTEGER, CONSTANT_VALUE_FLOAT Return parameter.defaultText
			Case CONSTANT_VALUE_STRING Return Quoted(parameter.defaultStringValue)
			Case CONSTANT_VALUE_CALLABLE Return "callable(" + parameter.defaultCallableAbiName + ")"
			Case CONSTANT_VALUE_NULL Return "Null"
		End Select
		Return "<unsupported>"
	End Function

	Function ObjectSlotName:String(slotKind:Int)
		Select slotKind
			Case IR_OBJECT_SLOT_TO_STRING; Return "ToString"
			Case IR_OBJECT_SLOT_COMPARE; Return "Compare"
			Case IR_OBJECT_SLOT_SEND_MESSAGE; Return "SendMessage"
			Case IR_OBJECT_SLOT_HASH_CODE; Return "HashCode"
			Case IR_OBJECT_SLOT_EQUALS; Return "Equals"
		End Select
		Return "<none>"
	End Function

	Function DumpBlock:String(block:TCompilerIrBlock, indent:String)
		If Not block Then Return indent + "<missing block>~n"
		Local result:String = indent + "block " + Location(block.source) + "~n"
		If block.debugScope And block.debugScope.scopeKind = IR_DEBUG_SCOPE_LOCAL_BLOCK Then result :+ DumpDebugScope(block.debugScope, indent + "  ")
		For Local statement:TCompilerIrStatement = EachIn block.statements
			result :+ DumpStatement(statement, indent + "  ")
		Next
		Return result
	End Function

	Function DumpDebugScope:String(scope:TCompilerIrDebugScope, indent:String)
		If Not scope Then Return ""
		Local kind:String = "function"
		If scope.scopeKind = IR_DEBUG_SCOPE_LOCAL_BLOCK Then kind = "local-block"
		Local result:String = indent + "debug-scope " + kind + " " + scope.sourceId + " " + Quoted(scope.name) + "~n"
		For Local variable:TCompilerIrDebugVariable = EachIn scope.variables
			Local declarationName:String = "debug-variable"
			If variable.declarationKind = IR_DEBUG_DECL_CONSTANT Then declarationName = "debug-constant"
			If variable.declarationKind = IR_DEBUG_DECL_GLOBAL Then declarationName = "debug-global"
			result :+ indent + "  " + declarationName + " %" + variable.symbolId + " " + variable.name + ":" + variable.semanticType
			If variable.declarationKind = IR_DEBUG_DECL_CONSTANT Then result :+ " [value-string %" + variable.constantStringLiteralId + "]"
			If variable.isReceiver Then result :+ " [receiver]"
			If variable.passingMode = PARAMETER_PASS_VAR Then result :+ " [var]"
			result :+ "~n"
		Next
		Return result
	End Function

	Function DumpStatement:String(statement:TCompilerIrStatement, indent:String)
		Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
		If variable Then
			Local result:String = indent + "var " + variable.storage + " %" + variable.symbolId + " " + variable.name + ":" + variable.semanticType
			If variable.ownerClassId.length Then result :+ " [class @" + variable.ownerClassId + "]"
			If variable.ownerStructId.length Then result :+ " [struct @" + variable.ownerStructId + "]"
			If variable.isPublished Then result :+ " [published abi " + variable.abiName + "]"
			If variable.isReadOnly Then result :+ " [readonly]"
			If variable.isThreadedGlobal Then result :+ " [threaded]"
			If variable.callableReturnType.length Then result :+ " [callable " + variable.callableReturnType + "(" + ParameterTypes(variable.callableParameters) + ")]"
			If variable.callableCallingConvention = "stdcall" Then result :+ " [stdcall]"
			If variable.isStaticArray Then
				result :+ " [static-array " + variable.staticArrayElementType + " x " + variable.staticArrayLength + "]"
				If variable.staticArrayStructId.length Then result :+ " [element-layout struct @" + variable.staticArrayStructId + "]"
				If variable.staticArrayImportedStructId.length Then result :+ " [element-layout imported-struct @" + variable.staticArrayImportedStructId + "]"
			End If
			result :+ " " + Location(variable.source) + "~n"
			result :+ DumpMetadata(variable.metadata, indent + "  ")
			If variable.initializer Then result :+ DumpExpression(variable.initializer, indent + "  ")
			Return result
		End If
		Local assignment:TCompilerIrAssignment = TCompilerIrAssignment(statement)
		If assignment Then
			Return indent + "assign " + Location(assignment.source) + "~n" + DumpExpression(assignment.target, indent + "  ") + DumpExpression(assignment.value, indent + "  ")
		End If
		Local expressionStatement:TCompilerIrExpressionStatement = TCompilerIrExpressionStatement(statement)
		If expressionStatement Then Return indent + "evaluate " + Location(expressionStatement.source) + "~n" + DumpExpression(expressionStatement.expression, indent + "  ")
		Local returned:TCompilerIrReturn = TCompilerIrReturn(statement)
		If returned Then
			Local result:String = indent + "return " + Location(returned.source) + "~n"
			If returned.expression Then result :+ DumpExpression(returned.expression, indent + "  ")
			For Local cleanupStep:TCompilerIrCleanupStep = EachIn returned.cleanupSteps
				result :+ indent + "  leave-exception-frame"
				If cleanupStep And cleanupStep.finallyBody Then result :+ " finally"
				If cleanupStep And cleanupStep.usingResources.length Then result :+ " using " + cleanupStep.usingResources.length
				result :+ "~n"
				If cleanupStep And cleanupStep.finallyBody Then result :+ DumpBlock(cleanupStep.finallyBody, indent + "    ")
			Next
			Return result
		End If
		Local yielded:TCompilerIrYield = TCompilerIrYield(statement)
		If yielded Then Return indent + "yield state " + yielded.resumeState + " " + Location(yielded.source) + "~n" + DumpExpression(yielded.expression, indent + "  ")
		Local thrown:TCompilerIrThrow = TCompilerIrThrow(statement)
		If thrown Then Return indent + "throw " + Location(thrown.source) + "~n" + DumpExpression(thrown.expression, indent + "  ")
		Local applicationEnd:TCompilerIrApplicationEnd = TCompilerIrApplicationEnd(statement)
		If applicationEnd Then Return indent + "application-end " + Location(applicationEnd.source) + "~n"
		Local released:TCompilerIrRelease = TCompilerIrRelease(statement)
		If released Then Return indent + "release " + Location(released.source) + "~n" + DumpExpression(released.expression, indent + "  ")
		Local asserted:TCompilerIrAssert = TCompilerIrAssert(statement)
		If asserted Then
			Local result:String = indent + "assert " + Location(asserted.source) + "~n"
			result :+ indent + "  condition~n" + DumpExpression(asserted.condition, indent + "    ")
			result :+ indent + "  failure-message~n" + DumpExpression(asserted.message, indent + "    ")
			Return result
		End If
		Local conditionalIf:TCompilerIrIf = TCompilerIrIf(statement)
		If conditionalIf Then
			Local result:String = indent + "if " + Location(conditionalIf.source) + "~n"
			result :+ DumpExpression(conditionalIf.condition, indent + "  ")
			result :+ DumpBlock(conditionalIf.thenBody, indent + "  ")
			For Local clause:TCompilerIrConditionalClause = EachIn conditionalIf.elseIfClauses
				result :+ indent + "else-if " + Location(clause.source) + "~n"
				result :+ DumpExpression(clause.condition, indent + "  ")
				result :+ DumpBlock(clause.body, indent + "  ")
			Next
			If conditionalIf.elseBody Then result :+ indent + "else~n" + DumpBlock(conditionalIf.elseBody, indent + "  ")
			Return result
		End If
		Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
		If selected Then
			Local comparisonKind:String = "scalar"
			If selected.stringComparison Then comparisonKind = "string"
			If selected.managedIdentityComparison Then comparisonKind = "identity"
			Local result:String = indent + "select " + comparisonKind + " " + selected.selectorType + " [selector %" + selected.selectorTemporaryId + "] " + Location(selected.source) + "~n"
			result :+ indent + "  selector~n" + DumpExpression(selected.selector, indent + "    ")
			For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
				result :+ indent + "  case " + Location(selectedCase.source) + "~n"
				For Local value:TCompilerIrExpression = EachIn selectedCase.values
					result :+ indent + "    value~n" + DumpExpression(value, indent + "      ")
				Next
				result :+ DumpBlock(selectedCase.body, indent + "    ")
			Next
			If selected.defaultBody Then result :+ indent + "  default~n" + DumpBlock(selected.defaultBody, indent + "    ")
			Return result
		End If
		Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
		If guarded Then
			Local result:String = indent + "try " + Location(guarded.source) + "~n"
			result :+ DumpBlock(guarded.body, indent + "  ")
			For Local guardedCatch:TCompilerIrCatch = EachIn guarded.catches
				Local catchKind:String = "object"
				Select guardedCatch.catchKind
					Case IR_CATCH_STRING catchKind = "string"
					Case IR_CATCH_ARRAY catchKind = "array"
					Case IR_CATCH_CLASS catchKind = "class"
					Case IR_CATCH_INTERFACE catchKind = "interface"
				End Select
				result :+ indent + "  catch " + catchKind + " %" + guardedCatch.parameterSymbolId + " " + guardedCatch.parameterName + ":" + guardedCatch.parameterType
				If guardedCatch.classId.length Then result :+ " class @" + guardedCatch.classId
				If guardedCatch.importedClassId.length Then result :+ " imported-class @" + guardedCatch.importedClassId
				If guardedCatch.interfaceId.length Then result :+ " interface @" + guardedCatch.interfaceId
				result :+ " " + Location(guardedCatch.source) + "~n"
				result :+ DumpBlock(guardedCatch.body, indent + "    ")
			Next
			If guarded.finallyBody Then result :+ indent + "  finally~n" + DumpBlock(guarded.finallyBody, indent + "    ")
			Return result
		End If
		Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
		If usingStatement Then
			Local result:String = indent + "using @" + usingStatement.usingId + " " + Location(usingStatement.source) + "~n"
			For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
				result :+ indent + "  resource %" + resource.variable.symbolId + " " + resource.variable.name + ":" + resource.variable.semanticType + "~n"
				result :+ indent + "    initializer~n" + DumpExpression(resource.initializer, indent + "      ")
				result :+ indent + "    close~n" + DumpExpression(resource.closeCall, indent + "      ")
			Next
			Return result + DumpBlock(usingStatement.body, indent + "  ")
		End If
		Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
		If whileStatement Then
			Local label:String
			If whileStatement.sourceLabel.length Then label = " label " + whileStatement.sourceLabel
			Return indent + "while " + Location(whileStatement.source) + " [loop @" + whileStatement.loopId + "]" + label + "~n" + DumpExpression(whileStatement.condition, indent + "  ") + DumpBlock(whileStatement.body, indent + "  ")
		End If
		Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
		If repeatStatement Then
			Local mode:String = "until"
			If repeatStatement.isForever Then mode = "forever"
			Local label:String
			If repeatStatement.sourceLabel.length Then label = " label " + repeatStatement.sourceLabel
			Local result:String = indent + "repeat " + mode + " " + Location(repeatStatement.source) + " [loop @" + repeatStatement.loopId + "]" + label + "~n"
			result :+ DumpBlock(repeatStatement.body, indent + "  ")
			If repeatStatement.condition Then result :+ DumpExpression(repeatStatement.condition, indent + "  ")
			Return result
		End If
		Local forStatement:TCompilerIrForRange = TCompilerIrForRange(statement)
		If forStatement Then
			Local rangeKind:String = "until"
			If forStatement.inclusiveLimit Then rangeKind = "to"
			Local direction:String = "ascending"
			If forStatement.descending Then direction = "descending"
			Local declaration:String
			If forStatement.declaresVariable Then declaration = " declare %" + forStatement.variableSymbolId + " " + forStatement.variableName + ":" + forStatement.variableType
			Local label:String
			If forStatement.sourceLabel.length Then label = " label " + forStatement.sourceLabel
			Local result:String = indent + "for-range " + rangeKind + " " + direction + " " + Location(forStatement.source) + " [loop @" + forStatement.loopId + "]" + label + declaration + "~n"
			result :+ indent + "  target~n" + DumpExpression(forStatement.target, indent + "    ")
			result :+ indent + "  initial~n" + DumpExpression(forStatement.initialValue, indent + "    ")
			result :+ indent + "  limit~n" + DumpExpression(forStatement.limit, indent + "    ")
			result :+ indent + "  step~n" + DumpExpression(forStatement.stepExpression, indent + "    ")
			Return result + DumpBlock(forStatement.body, indent + "  ")
		End If
		Local eachStatement:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
		If eachStatement Then
			Local declaration:String
			If eachStatement.declaresVariable Then declaration = " declare %" + eachStatement.variableSymbolId + " " + eachStatement.variableName + ":" + eachStatement.variableType
			Local label:String
			If eachStatement.sourceLabel.length Then label = " label " + eachStatement.sourceLabel
			Local filter:String
			If eachStatement.filtersNullObjects Then filter = " [object-filter]"
			Local result:String = indent + "for-each-array " + eachStatement.elementType + " " + Location(eachStatement.source) + " [loop @" + eachStatement.loopId + "]" + label + declaration + " [collection %" + eachStatement.collectionTemporaryId + "] [index %" + eachStatement.indexTemporaryId + "] [element %" + eachStatement.elementTemporaryId + "]" + filter + "~n"
			result :+ indent + "  collection~n" + DumpExpression(eachStatement.collection, indent + "    ")
			result :+ indent + "  target~n" + DumpExpression(eachStatement.target, indent + "    ")
			result :+ indent + "  element-value~n" + DumpExpression(eachStatement.elementValue, indent + "    ")
			Return result + DumpBlock(eachStatement.body, indent + "  ")
		End If
		Local stringEachStatement:TCompilerIrForEachString = TCompilerIrForEachString(statement)
		If stringEachStatement Then
			Local declaration:String
			If stringEachStatement.declaresVariable Then declaration = " declare %" + stringEachStatement.variableSymbolId + " " + stringEachStatement.variableName + ":" + stringEachStatement.variableType
			Local label:String
			If stringEachStatement.sourceLabel.length Then label = " label " + stringEachStatement.sourceLabel
			Local result:String = indent + "for-each-string Int " + Location(stringEachStatement.source) + " [loop @" + stringEachStatement.loopId + "]" + label + declaration + " [collection %" + stringEachStatement.collectionTemporaryId + "] [index %" + stringEachStatement.indexTemporaryId + "] [element %" + stringEachStatement.elementTemporaryId + "]~n"
			result :+ indent + "  collection~n" + DumpExpression(stringEachStatement.collection, indent + "    ")
			result :+ indent + "  target~n" + DumpExpression(stringEachStatement.target, indent + "    ")
			Return result + DumpBlock(stringEachStatement.body, indent + "  ")
		End If
		Local staticEachStatement:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
		If staticEachStatement Then
			Local declaration:String
			If staticEachStatement.declaresVariable Then declaration = " declare %" + staticEachStatement.variableSymbolId + " " + staticEachStatement.variableName + ":" + staticEachStatement.variableType
			Local label:String
			If staticEachStatement.sourceLabel.length Then label = " label " + staticEachStatement.sourceLabel
			Local result:String = indent + "for-each-static-array " + staticEachStatement.elementType + " x " + staticEachStatement.length + " " + Location(staticEachStatement.source) + " [loop @" + staticEachStatement.loopId + "]" + label + declaration + " [collection %" + staticEachStatement.collectionTemporaryId + "] [index %" + staticEachStatement.indexTemporaryId + "] [element %" + staticEachStatement.elementTemporaryId + "]~n"
			If staticEachStatement.elementStructId.length Then result :+ indent + "  element-layout struct @" + staticEachStatement.elementStructId + "~n"
			If staticEachStatement.elementImportedStructId.length Then result :+ indent + "  element-layout imported-struct @" + staticEachStatement.elementImportedStructId + "~n"
			result :+ indent + "  collection~n" + DumpExpression(staticEachStatement.collection, indent + "    ")
			result :+ indent + "  target~n" + DumpExpression(staticEachStatement.target, indent + "    ")
			Return result + DumpBlock(staticEachStatement.body, indent + "  ")
		End If
		Local objectEachStatement:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
		If objectEachStatement Then
			Local declaration:String
			If objectEachStatement.declaresVariable Then declaration = " declare %" + objectEachStatement.variableSymbolId + " " + objectEachStatement.variableName + ":" + objectEachStatement.variableType
			Local label:String
			If objectEachStatement.sourceLabel.length Then label = " label " + objectEachStatement.sourceLabel
			Local protocol:String = "object-enumerator"
			If objectEachStatement.protocolKind = EACH_IN_PROTOCOL_ITERABLE Then protocol = "iterable" Else If objectEachStatement.protocolKind = EACH_IN_PROTOCOL_ITERATOR Then protocol = "iterator"
			Local filter:String
			If objectEachStatement.filtersNullObjects Then filter = " [object-filter]"
			If objectEachStatement.filtersStringObjects Then filter :+ " [string-filter]"
			Local result:String = indent + "for-each-object " + protocol + " " + objectEachStatement.elementType + " " + Location(objectEachStatement.source) + " [loop @" + objectEachStatement.loopId + "]" + label + declaration + " [collection %" + objectEachStatement.collectionTemporaryId + ":" + objectEachStatement.collectionType + "] [iterator %" + objectEachStatement.iteratorTemporaryId + ":" + objectEachStatement.iteratorType + "] [element %" + objectEachStatement.elementTemporaryId + "]" + filter + "~n"
			result :+ indent + "  collection~n" + DumpExpression(objectEachStatement.collection, indent + "    ")
			result :+ indent + "  iterator-initializer~n" + DumpExpression(objectEachStatement.iteratorInitializer, indent + "    ")
			If objectEachStatement.iteratorCleanup Then
				result :+ indent + "  iterator-cleanup %" + objectEachStatement.iteratorCleanup.variable.symbolId + ":" + objectEachStatement.iteratorCleanup.variable.semanticType + "~n"
				result :+ indent + "    initializer~n" + DumpExpression(objectEachStatement.iteratorCleanup.initializer, indent + "      ")
				result :+ indent + "    close~n" + DumpExpression(objectEachStatement.iteratorCleanup.closeCall, indent + "      ")
			End If
			result :+ indent + "  advance~n" + DumpExpression(objectEachStatement.advance, indent + "    ")
			result :+ indent + "  current~n" + DumpExpression(objectEachStatement.current, indent + "    ")
			result :+ indent + "  target~n" + DumpExpression(objectEachStatement.target, indent + "    ")
			result :+ indent + "  element-value~n" + DumpExpression(objectEachStatement.elementValue, indent + "    ")
			Return result + DumpBlock(objectEachStatement.body, indent + "  ")
		End If
		Local loopControl:TCompilerIrLoopControl = TCompilerIrLoopControl(statement)
		If loopControl Then
			Local operation:String = "exit"
			If loopControl.controlKind = IR_LOOP_CONTROL_CONTINUE Then operation = "continue"
			Local cleanup:String
			If loopControl.cleanupSteps.length Then cleanup = " [cleanup " + loopControl.cleanupSteps.length + "]"
			Return indent + operation + " @" + loopControl.targetLoopId + cleanup + " " + Location(loopControl.source) + "~n"
		End If
		Local dataRead:TCompilerIrDataRead = TCompilerIrDataRead(statement)
		If dataRead Then
			Local result:String = indent + "read-data " + dataRead.targets.length + " " + Location(dataRead.source) + "~n"
			For Local target:TCompilerIrDataReadTarget = EachIn dataRead.targets
				result :+ indent + "  target conversion " + target.conversionKind + "~n" + DumpExpression(target.target, indent + "    ")
			Next
			Return result
		End If
		Local dataRestore:TCompilerIrDataRestore = TCompilerIrDataRestore(statement)
		If dataRestore Then Return indent + "restore-data " + dataRestore.itemIndex + " " + Location(dataRestore.source) + "~n"
		Return indent + "<unknown statement>~n"
	End Function

	Function ParameterTypes:String(parameters:TCompilerIrParameter[])
		Local result:String
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ", "
			result :+ ParameterSignature(parameters[index])
		Next
		Return result
	End Function

	Function ParameterSignature:String(parameter:TCompilerIrParameter)
		Local result:String = ParameterType(parameter)
		If parameter And parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
		Return result
	End Function

	Function ParameterType:String(parameter:TCompilerIrParameter)
		If parameter And parameter.isStaticArray Then Return "StaticArray " + parameter.staticArrayElementType + "[" + parameter.staticArrayLength + "]"
		If parameter Then Return parameter.semanticType
		Return "<missing>"
	End Function

	Function DumpExpression:String(expression:TCompilerIrExpression, indent:String)
		If Not expression Then Return indent + "<missing expression>~n"
		Local suffix:String = " : " + expression.semanticType + " " + Location(expression.source) + "~n"
		Local literal:TCompilerIrLiteral = TCompilerIrLiteral(expression)
		If literal Then
			If literal.stringLiteralId.length Then Return indent + "string-literal @" + literal.stringLiteralId + suffix
			Return indent + "literal " + literal.text + suffix
		End If
		Local symbol:TCompilerIrSymbolReference = TCompilerIrSymbolReference(expression)
		If symbol Then
			Local symbolKind:String
			If symbol.isExternal Then symbolKind = " external"
			If symbol.isByReference Then symbolKind :+ " by-reference"
			Return indent + "symbol" + symbolKind + " %" + symbol.symbolId + " " + symbol.name + suffix
		End If
		Local address:TCompilerIrAddressOf = TCompilerIrAddressOf(expression)
		If address Then Return indent + "address-of" + suffix + DumpExpression(address.operand, indent + "  ")
		Local pointerTruth:TCompilerIrPointerTruth = TCompilerIrPointerTruth(expression)
		If pointerTruth Then
			Local operation:String = "truth"
			If pointerTruth.negate Then operation = "not"
			Return indent + "pointer-" + operation + suffix + DumpExpression(pointerTruth.operand, indent + "  ")
		End If
		Local structNew:TCompilerIrStructNew = TCompilerIrStructNew(expression)
		If structNew Then
			Local result:String = indent + "struct-new @" + structNew.structId
			If structNew.importedStructId.length Then result = indent + "struct-new imported @" + structNew.importedStructId
			If structNew.constructorFunctionId.length Then result :+ " constructor @" + structNew.constructorFunctionId
			If structNew.importedConstructorId.length Then result :+ " constructor %" + structNew.importedConstructorId
			result :+ suffix
			For Local argument:TCompilerIrExpression = EachIn structNew.arguments
				result :+ DumpExpression(argument, indent + "  ")
			Next
			Return result
		End If
		Local callableReference:TCompilerIrCallableReference = TCompilerIrCallableReference(expression)
		If callableReference Then
			Local callableKind:String = "source"
			If callableReference.isExternal Then callableKind = "external"
			If callableReference.isFunctionLiteral Then callableKind = "function-literal"
			Local abi:String
			If callableReference.abiName.length Then abi = " abi " + callableReference.abiName
			Return indent + "callable " + callableKind + " @" + callableReference.functionId + " " + callableReference.functionName + abi + suffix
		End If
		Local closureLiteral:TCompilerIrClosureLiteral = TCompilerIrClosureLiteral(expression)
		If closureLiteral Then
			Local result:String = indent + "closure-literal @" + closureLiteral.literalId + " invoke @" + closureLiteral.functionId + " " + closureLiteral.returnType + "(" + ParameterTypes(closureLiteral.parameters) + ")" + suffix
			If closureLiteral.environment Then result :+ DumpExpression(closureLiteral.environment, indent + "  ")
			Return result
		End If
		Local call:TCompilerIrCall = TCompilerIrCall(expression)
		If call Then
			Local callKind:String
			If call.isExternal Then callKind = " external"
			If call.dispatchKind = IR_CALL_DISPATCH_INTERFACE Then
				callKind = " interface @" + call.interfaceId + ".%" + call.interfaceSlotId
			Else If call.dispatchKind = IR_CALL_DISPATCH_STRUCT Then
				callKind = " struct-direct"
			Else If call.dispatchKind = IR_CALL_DISPATCH_TYPE_FUNCTION Then
				callKind = " type-function @" + call.classId + ".%" + call.classSlotId
			Else If call.dispatchKind = IR_CALL_DISPATCH_IMPORTED_VIRTUAL Then
				If call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
					callKind = " imported-virtual @" + call.classId + "." + ObjectSlotName(call.objectSlotKind)
				Else
					callKind = " imported-virtual @" + call.classId + ".%" + call.classSlotId
				End If
			Else If call.dispatchKind = IR_CALL_DISPATCH_SUPER Then
				If call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
					callKind = " super @" + call.classId + "." + ObjectSlotName(call.objectSlotKind)
				Else
					callKind = " super @" + call.classId + ".%" + call.classSlotId
				End If
			Else If call.dispatchKind = IR_CALL_DISPATCH_VIRTUAL Then
				If call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
					callKind = " virtual @" + call.classId + "." + ObjectSlotName(call.objectSlotKind)
				Else
					callKind = " virtual @" + call.classId + ".%" + call.classSlotId
				End If
			End If
			Local result:String = indent + "call" + callKind + " @" + call.functionId + " " + call.functionName + suffix
			If call.receiver Then result :+ DumpExpression(call.receiver, indent + "  ")
			For Local argument:TCompilerIrExpression = EachIn call.arguments
				result :+ DumpExpression(argument, indent + "  ")
			Next
			Return result
		End If
		Local indirect:TCompilerIrIndirectCall = TCompilerIrIndirectCall(expression)
		If indirect Then
			Local result:String = indent + "call-indirect (" + indirect.returnType + ")"
			If indirect.callingConvention = "stdcall" Then result :+ " [stdcall]"
			result :+ suffix
			result :+ indent + "  callee~n" + DumpExpression(indirect.callee, indent + "    ")
			For Local argument:TCompilerIrExpression = EachIn indirect.arguments
				result :+ DumpExpression(argument, indent + "  ")
			Next
			Return result
		End If
		Local closureCall:TCompilerIrClosureCall = TCompilerIrClosureCall(expression)
		If closureCall Then
			Local result:String = indent + "closure-call (" + closureCall.returnType + ")" + suffix
			result :+ indent + "  callee~n" + DumpExpression(closureCall.callee, indent + "    ")
			For Local argument:TCompilerIrExpression = EachIn closureCall.arguments
				result :+ DumpExpression(argument, indent + "  ")
			Next
			Return result
		End If
		Local callableDefault:TCompilerIrCallableDefault = TCompilerIrCallableDefault(expression)
		If callableDefault Then Return indent + "callable-default " + callableDefault.returnType + "(" + ParameterTypes(callableDefault.parameters) + ")" + suffix
		Local callableTruth:TCompilerIrCallableTruth = TCompilerIrCallableTruth(expression)
		If callableTruth Then
			Local operation:String = "truth"
			If callableTruth.negate Then operation = "not"
			Return indent + "callable-" + operation + " " + callableTruth.returnType + "(" + ParameterTypes(callableTruth.parameters) + ")" + suffix + DumpExpression(callableTruth.operand, indent + "  ")
		End If
		Local enumIntrinsic:TCompilerIrEnumIntrinsic = TCompilerIrEnumIntrinsic(expression)
		If enumIntrinsic Then
			Local intrinsicName:String
			Select enumIntrinsic.intrinsicKind
				Case IR_ENUM_INTRINSIC_ORDINAL intrinsicName = "ordinal"
				Case IR_ENUM_INTRINSIC_VALUES intrinsicName = "values"
				Case IR_ENUM_INTRINSIC_TO_STRING intrinsicName = "to-string"
				Case IR_ENUM_INTRINSIC_TRY_CONVERT intrinsicName = "try-convert"
				Case IR_ENUM_INTRINSIC_FROM_STRING intrinsicName = "from-string"
			End Select
			Local result:String = indent + "enum-" + intrinsicName + " @" + enumIntrinsic.enumId + suffix
			If enumIntrinsic.receiver Then result :+ DumpExpression(enumIntrinsic.receiver, indent + "  ")
			For Local argument:TCompilerIrExpression = EachIn enumIntrinsic.arguments
				result :+ DumpExpression(argument, indent + "  ")
			Next
			Return result
		End If
		Local unary:TCompilerIrUnary = TCompilerIrUnary(expression)
		If unary Then Return indent + "unary " + unary.operatorText + suffix + DumpExpression(unary.operand, indent + "  ")
		Local binary:TCompilerIrBinary = TCompilerIrBinary(expression)
		If binary Then Return indent + "binary " + binary.operatorText + suffix + DumpExpression(binary.left, indent + "  ") + DumpExpression(binary.right, indent + "  ")
		Local pointerBinary:TCompilerIrPointerBinary = TCompilerIrPointerBinary(expression)
		If pointerBinary Then Return indent + "pointer-binary " + pointerBinary.operatorText + suffix + DumpExpression(pointerBinary.left, indent + "  ") + DumpExpression(pointerBinary.right, indent + "  ")
		Local conversion:TCompilerIrConversion = TCompilerIrConversion(expression)
		If conversion Then
			Local mode:String = "explicit"
			If conversion.implicitConversion Then mode = "implicit"
			Local enumCheck:String
			If conversion.checkedEnumId.length Then enumCheck = " checked-enum @" + conversion.checkedEnumId
			Local arrayCast:String
			If conversion.arrayCastElementEncoding.length Then arrayCast = " array-cast encoding ~q" + conversion.arrayCastElementEncoding + "~q"
			Return indent + "convert " + mode + " " + ConversionName(conversion.conversionKind) + enumCheck + arrayCast + suffix + DumpExpression(conversion.operand, indent + "  ")
		End If
		Local concat:TCompilerIrStringConcat = TCompilerIrStringConcat(expression)
		If concat Then Return indent + "string-concat" + suffix + DumpExpression(concat.left, indent + "  ") + DumpExpression(concat.right, indent + "  ")
		Local comparison:TCompilerIrStringCompare = TCompilerIrStringCompare(expression)
		If comparison Then Return indent + "string-compare " + comparison.operatorText + suffix + DumpExpression(comparison.left, indent + "  ") + DumpExpression(comparison.right, indent + "  ")
		Local truth:TCompilerIrManagedTruth = TCompilerIrManagedTruth(expression)
		If truth Then
			Local mode:String = "truth"
			If truth.negate Then mode = "not"
			Return indent + "managed-" + mode + " " + ManagedReferenceKindName(truth.managedKind) + suffix + DumpExpression(truth.operand, indent + "  ")
		End If
		Local defaultValue:TCompilerIrManagedDefault = TCompilerIrManagedDefault(expression)
		If defaultValue Then Return indent + "managed-default " + ManagedReferenceKindName(defaultValue.managedKind) + suffix
		Local identity:TCompilerIrManagedIdentity = TCompilerIrManagedIdentity(expression)
		If identity Then Return indent + "managed-identity " + identity.operatorText + " " + ManagedReferenceKindName(identity.managedKind) + suffix + DumpExpression(identity.left, indent + "  ") + DumpExpression(identity.right, indent + "  ")
		Local arrayNew:TCompilerIrArrayNew = TCompilerIrArrayNew(expression)
		If arrayNew Then
			Local result:String = indent + "array-new " + arrayNew.elementType + " encoding " + Quoted(arrayNew.elementEncoding) + " rank " + arrayNew.rank + suffix
			If arrayNew.enumId.length Then result :+ indent + "  element-layout enum @" + arrayNew.enumId + "~n"
			If arrayNew.structId.length Then result :+ indent + "  element-layout struct @" + arrayNew.structId + "~n"
			If arrayNew.importedStructId.length Then result :+ indent + "  element-layout imported-struct @" + arrayNew.importedStructId + "~n"
			For Local dimension:TCompilerIrExpression = EachIn arrayNew.dimensions
				result :+ DumpExpression(dimension, indent + "  ")
			Next
			Return result
		End If
		Local arrayLength:TCompilerIrArrayLength = TCompilerIrArrayLength(expression)
		If arrayLength Then Return indent + "array-length" + suffix + DumpExpression(arrayLength.receiver, indent + "  ")
		Local stringSlice:TCompilerIrStringSlice = TCompilerIrStringSlice(expression)
		If stringSlice Then
			Local result:String = indent + "string-slice" + suffix
			result :+ indent + "  receiver~n" + DumpExpression(stringSlice.receiver, indent + "    ")
			Local lowerLabel:String = "lower"
			If stringSlice.lowerFromEnd Then lowerLabel :+ " from-end"
			result :+ indent + "  " + lowerLabel + "~n" + DumpExpression(stringSlice.lowerBound, indent + "    ")
			If stringSlice.upperBoundOmitted Then
				result :+ indent + "  upper receiver-length~n"
			Else
				Local upperLabel:String = "upper"
				If stringSlice.upperFromEnd Then upperLabel :+ " from-end"
				result :+ indent + "  " + upperLabel + "~n" + DumpExpression(stringSlice.upperBound, indent + "    ")
			End If
			Return result
		End If
		Local stringLength:TCompilerIrStringLength = TCompilerIrStringLength(expression)
		If stringLength Then Return indent + "string-length" + suffix + DumpExpression(stringLength.receiver, indent + "  ")
		Local stringElement:TCompilerIrStringElement = TCompilerIrStringElement(expression)
		If stringElement Then
			Local checked:String
			If stringElement.boundsCheck Then checked = " [bounds-check]"
			Return indent + "string-element" + checked + suffix + DumpExpression(stringElement.receiver, indent + "  ") + DumpExpression(stringElement.index, indent + "  ")
		End If
		Local stringAsc:TCompilerIrStringAsc = TCompilerIrStringAsc(expression)
		If stringAsc Then Return indent + "string-asc" + suffix + DumpExpression(stringAsc.receiver, indent + "  ")
		Local stringChr:TCompilerIrStringChr = TCompilerIrStringChr(expression)
		If stringChr Then Return indent + "string-chr" + suffix + DumpExpression(stringChr.codePoint, indent + "  ")
		Local arraySlice:TCompilerIrArraySlice = TCompilerIrArraySlice(expression)
		If arraySlice Then
			Local result:String = indent + "array-slice " + arraySlice.elementType + " encoding " + Quoted(arraySlice.elementEncoding) + suffix
			If arraySlice.structId.length Then result :+ indent + "  element-layout struct @" + arraySlice.structId + "~n"
			If arraySlice.importedStructId.length Then result :+ indent + "  element-layout imported-struct @" + arraySlice.importedStructId + "~n"
			result :+ indent + "  receiver~n" + DumpExpression(arraySlice.receiver, indent + "    ")
			Local lowerLabel:String = "lower"
			If arraySlice.lowerFromEnd Then lowerLabel :+ " from-end"
			result :+ indent + "  " + lowerLabel + "~n" + DumpExpression(arraySlice.lowerBound, indent + "    ")
			If arraySlice.upperBoundOmitted Then
				result :+ indent + "  upper receiver-length~n"
			Else
				Local upperLabel:String = "upper"
				If arraySlice.upperFromEnd Then upperLabel :+ " from-end"
				result :+ indent + "  " + upperLabel + "~n" + DumpExpression(arraySlice.upperBound, indent + "    ")
			End If
			Return result
		End If
		Local arrayElement:TCompilerIrArrayElement = TCompilerIrArrayElement(expression)
		If arrayElement Then
			Local arrayKind:String = "array-element "
			If arrayElement.isStaticArray Then arrayKind = "static-array-element "
			Local result:String = indent + arrayKind + arrayElement.elementType + " rank " + arrayElement.rank + suffix
			If arrayElement.boundsCheckKind = IR_BOUNDS_CHECK_DYNAMIC_ARRAY Then result :+ indent + "  bounds-check dynamic-array~n"
			If arrayElement.boundsCheckKind = IR_BOUNDS_CHECK_STATIC_ARRAY Then result :+ indent + "  bounds-check static-array length " + arrayElement.boundsLength + "~n"
			If arrayElement.structId.length Then result :+ indent + "  element-layout struct @" + arrayElement.structId + "~n"
			If arrayElement.importedStructId.length Then result :+ indent + "  element-layout imported-struct @" + arrayElement.importedStructId + "~n"
			result :+ DumpExpression(arrayElement.receiver, indent + "  ")
			For Local indexExpression:TCompilerIrExpression = EachIn arrayElement.indexes
				result :+ DumpExpression(indexExpression, indent + "  ")
			Next
			Return result
		End If
		Local pointerElement:TCompilerIrPointerElement = TCompilerIrPointerElement(expression)
		If pointerElement Then
			Local result:String = indent + "pointer-element " + pointerElement.elementType + suffix
			If pointerElement.nullCheck Then result :+ indent + "  null-check raw-pointer~n"
			If pointerElement.structId.length Then result :+ indent + "  element-layout struct @" + pointerElement.structId + "~n"
			If pointerElement.importedStructId.length Then result :+ indent + "  element-layout imported-struct @" + pointerElement.importedStructId + "~n"
			result :+ DumpExpression(pointerElement.receiver, indent + "  ")
			Return result + DumpExpression(pointerElement.index, indent + "  ")
		End If
		Local arrayConcat:TCompilerIrArrayConcat = TCompilerIrArrayConcat(expression)
		If arrayConcat Then
			Local result:String = indent + "array-concat " + arrayConcat.elementType + " encoding " + Quoted(arrayConcat.elementEncoding) + suffix
			If arrayConcat.enumId.length Then result :+ indent + "  element-layout enum @" + arrayConcat.enumId + "~n"
			If arrayConcat.structId.length Then result :+ indent + "  element-layout struct @" + arrayConcat.structId + "~n"
			If arrayConcat.importedStructId.length Then result :+ indent + "  element-layout imported-struct @" + arrayConcat.importedStructId + "~n"
			Return result + DumpExpression(arrayConcat.left, indent + "  ") + DumpExpression(arrayConcat.right, indent + "  ")
		End If
		Local arrayLiteral:TCompilerIrArrayLiteral = TCompilerIrArrayLiteral(expression)
		If arrayLiteral Then
			Local result:String = indent + "array-literal " + arrayLiteral.elementType + " encoding " + Quoted(arrayLiteral.elementEncoding) + " count " + arrayLiteral.elements.length + suffix
			If arrayLiteral.enumId.length Then result :+ indent + "  element-layout enum @" + arrayLiteral.enumId + "~n"
			If arrayLiteral.structId.length Then result :+ indent + "  element-layout struct @" + arrayLiteral.structId + "~n"
			If arrayLiteral.importedStructId.length Then result :+ indent + "  element-layout imported-struct @" + arrayLiteral.importedStructId + "~n"
			For Local element:TCompilerIrExpression = EachIn arrayLiteral.elements
				result :+ DumpExpression(element, indent + "  ")
			Next
			Return result
		End If
		Local objectNew:TCompilerIrObjectNew = TCompilerIrObjectNew(expression)
		If objectNew Then
			Local result:String = indent + "object-new @" + objectNew.classId
			If objectNew.importedClassId.length Then result = indent + "object-new imported @" + objectNew.importedClassId
			If objectNew.constructorFunctionId.length Then result :+ " constructor @" + objectNew.constructorFunctionId
			If objectNew.importedConstructorId.length Then result :+ " constructor %" + objectNew.importedConstructorId
			result :+ suffix
			If objectNew.dynamicClassSource Then result :+ indent + "  dynamic-class~n" + DumpExpression(objectNew.dynamicClassSource, indent + "    ")
			For Local argument:TCompilerIrExpression = EachIn objectNew.arguments
				result :+ DumpExpression(argument, indent + "  ")
			Next
			Return result
		End If
		Local fieldAccess:TCompilerIrFieldAccess = TCompilerIrFieldAccess(expression)
		If fieldAccess Then
			Local receiverMode:String
			If fieldAccess.receiverIsPointer Then receiverMode = " [pointer-receiver]"
			If fieldAccess.importedFieldId.length Then
				If fieldAccess.importedStructId.length Then Return indent + "field imported-struct @" + fieldAccess.importedStructId + ".%" + fieldAccess.importedFieldId + receiverMode + suffix + DumpExpression(fieldAccess.receiver, indent + "  ")
				Return indent + "field imported %" + fieldAccess.importedFieldId + receiverMode + suffix + DumpExpression(fieldAccess.receiver, indent + "  ")
			End If
			If fieldAccess.structId.length Then Return indent + "field struct @" + fieldAccess.structId + ".%" + fieldAccess.fieldId + receiverMode + suffix + DumpExpression(fieldAccess.receiver, indent + "  ")
			Return indent + "field @" + fieldAccess.classId + ".%" + fieldAccess.fieldId + receiverMode + suffix + DumpExpression(fieldAccess.receiver, indent + "  ")
		End If
		Local materialization:TCompilerIrMaterialize = TCompilerIrMaterialize(expression)
		If materialization Then
			Local addressMode:String
			If materialization.temporaryIsAddress Then addressMode = " [address]"
			If materialization.temporaryNativeCallableAbiName.length Then addressMode :+ " [native-callable " + materialization.temporaryNativeCallableAbiName + "]"
			Local result:String = indent + "materialize %" + materialization.temporaryId + ":" + materialization.temporaryType + addressMode + suffix
			result :+ indent + "  value~n" + DumpExpression(materialization.value, indent + "    ")
			result :+ indent + "  expression~n" + DumpExpression(materialization.expression, indent + "    ")
			Return result
		End If
		Local interfaceCast:TCompilerIrInterfaceCast = TCompilerIrInterfaceCast(expression)
		If interfaceCast Then Return indent + "interface-cast @" + interfaceCast.interfaceId + suffix + DumpExpression(interfaceCast.operand, indent + "  ")
		Local objectCast:TCompilerIrObjectCast = TCompilerIrObjectCast(expression)
		If objectCast Then
			Local classId:String = objectCast.classId
			If objectCast.importedClassId.length Then classId = objectCast.importedClassId
			Return indent + "object-cast @" + classId + suffix + DumpExpression(objectCast.operand, indent + "  ")
		End If
		Local objectStringCast:TCompilerIrObjectStringCast = TCompilerIrObjectStringCast(expression)
		If objectStringCast Then Return indent + "object-string-cast" + suffix + DumpExpression(objectStringCast.operand, indent + "  ")
		Return indent + "<unknown expression>" + suffix
	End Function

	Function DumpInitializationPlan:String(plan:TCompilerIrInitializationPlan)
		If Not plan Then Return "initialization <missing>~n"
		Local kindName:String = "application"
		If plan.unitKind = IR_UNIT_MODULE Then kindName = "module"
		Local result:String = "initialization " + kindName + " " + plan.unitName + " register " + plan.registerFunctionName + " init " + plan.initializeFunctionName + "~n"
		For Local dependency:TCompilerIrDependency = EachIn plan.dependencies
			result :+ "  dependency " + dependency.logicalName + " header " + Quoted(dependency.headerPath) + " register " + dependency.registerFunctionName + " init " + dependency.initializeFunctionName + " " + Location(dependency.source) + "~n"
		Next
		result :+ "  registration~n"
		For Local stepValue:TCompilerIrInitializationStep = EachIn plan.registrationSteps
			result :+ "    " + InitializationStepName(stepValue) + " " + Location(stepValue.source) + "~n"
		Next
		For Local registration:TCompilerIrGenericImplementationRegistration = EachIn plan.genericImplementationRegistrations
			result :+ "    register-generic-implementation " + registration.specializationIdentity + " " + registration.functionName + " " + Location(registration.source) + "~n"
		Next
		For Local registration:TCompilerIrGenericCoverageRegistration = EachIn plan.genericCoverageRegistrations
			result :+ "    register-generic-coverage " + registration.specializationIdentity + " " + registration.functionName + " " + Location(registration.source) + "~n"
		Next
		result :+ "  initialization~n"
		For Local stepValue:TCompilerIrInitializationStep = EachIn plan.initializationSteps
			result :+ "    " + InitializationStepName(stepValue) + " " + Location(stepValue.source) + "~n"
		Next
		Return result
	End Function

	Function InitializationStepName:String(stepValue:TCompilerIrInitializationStep)
		If Not stepValue Then Return "<missing-step>"
		Select stepValue.kind
			Case IR_INIT_REGISTER_DEPENDENCY
				Return "register-dependency " + stepValue.dependency.logicalName
			Case IR_INIT_INITIALIZE_STRINGS Return "initialize-strings"
			Case IR_INIT_ADD_GC_ROOTS Return "add-gc-roots"
			Case IR_INIT_INITIALIZE_DEPENDENCY
				Return "initialize-dependency " + stepValue.dependency.logicalName
			Case IR_INIT_RUN_ATSTART Return "run-atstart"
			Case IR_INIT_EXECUTE_GLOBAL_BODY Return "execute-global-body"
		End Select
		Return "unknown-step-" + stepValue.kind
	End Function

	Function DumpMetadata:String(values:TCompilerIrMetadataEntry[], indent:String)
		Local result:String
		For Local entry:TCompilerIrMetadataEntry = EachIn values
			result :+ indent + "metadata " + entry.key + "=" + Quoted(entry.value) + " written=" + Quoted(entry.writtenValue) + " " + Location(entry.source) + "~n"
		Next
		Return result
	End Function

	Function Location:String(source:TCompilerSourceLocation)
		If Not source Then Return "@<unknown>"
		Local result:String = "@" + source.path
		If source.span Then result :+ ":" + source.span.start + ":" + source.span.length
		Return result
	End Function

	Function Quoted:String(value:String)
		Return Chr(34) + value.Replace("\", "\\").Replace(Chr(34), "\" + Chr(34)).Replace("~r", "\r").Replace("~n", "\n").Replace("~t", "\t") + Chr(34)
	End Function

	Function ConversionName:String(kind:Int)
		Select kind
			Case CONVERSION_IDENTITY Return "identity"
			Case CONVERSION_NUMERIC_WIDENING Return "numeric-widening"
			Case CONVERSION_REFERENCE Return "reference"
			Case CONVERSION_CONSTANT Return "constant"
			Case CONVERSION_NULL Return "null"
			Case CONVERSION_NUMERIC_TO_STRING Return "numeric-to-string"
			Case CONVERSION_ENUM_TO_STRING Return "enum-to-string"
			Case CONVERSION_ENUM_TO_UNDERLYING Return "enum-to-underlying"
			Case CONVERSION_STRING_TO_NUMERIC Return "string-to-numeric"
			Case CONVERSION_EXPLICIT Return "explicit"
			Case CONVERSION_NUMERIC_NARROWING Return "numeric-narrowing"
			Case CONVERSION_CONTEXTUAL_NUMERIC_EXPRESSION Return "contextual-numeric"
			Case CONVERSION_DEFAULT_VALUE Return "default-value"
			Case CONVERSION_ARRAY_TO_POINTER Return "array-to-pointer"
			Case CONVERSION_POINTER_TO_BYTE_POINTER Return "pointer-to-byte-pointer"
			Case CONVERSION_BYTE_POINTER_TO_POINTER Return "byte-pointer-to-pointer"
			Case CONVERSION_STRING_TO_BYTE_POINTER Return "string-to-byte-pointer"
			Case CONVERSION_BYTE_POINTER_TO_CALLABLE Return "byte-pointer-to-callable"
			Case CONVERSION_CALLABLE_REFERENCE_TO_BYTE_POINTER Return "callable-reference-to-byte-pointer"
			Case CONVERSION_OBJECT_TO_BYTE_POINTER Return "object-to-byte-pointer"
			Case CONVERSION_POINTER_TO_VAR_REFERENCE Return "pointer-to-var-reference"
			Case CONVERSION_CALLABLE_VARIANCE Return "callable-variance"
			Case CONVERSION_VAR_REFERENCE Return "var-reference"
		End Select
		Return "kind-" + kind
	End Function

	Function ManagedReferenceKindName:String(kind:Int)
		Select kind
			Case IR_MANAGED_REFERENCE_STRING Return "String"
			Case IR_MANAGED_REFERENCE_ARRAY Return "Array"
			Case IR_MANAGED_REFERENCE_OBJECT Return "Object"
		End Select
		Return "kind-" + kind
	End Function
End Type
