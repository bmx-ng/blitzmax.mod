' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.StringBuilder
Import BlitzMax.Language
Import "abi_naming.bmx"
Import "compiler_diagnostic.bmx"
Import "ir_model.bmx"

Type TCompilerCNativeStringScope
	Field names:String[] = New String[0]
	Field values:String[] = New String[0]

	Method Add:String(name:String, value:String)
		names :+ [name]
		values :+ [value]
		Return name
	End Method
End Type

Type TCompilerCCapturedExpression
	Field expression:String
	Field nativeStrings:TCompilerCNativeStringScope
End Type

' Scalar C99 emitter with two validation modes: a standalone `main` for backend
' tests and the real BlitzMax application-unit boundary consumed by brl.blitz
' and brl.appstub. Runtime object/string/layout emission remains a later slice.
Type TCompilerCBackend
	Field diagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]
	Field currentModule:TCompilerIrModule
	Field functionNames:TMap = New TMap
	Field globalNames:TMap = New TMap
	Field externalFunctionsById:TMap = New TMap
	Field externalGlobalsById:TMap = New TMap
	Field localNames:TMap = New TMap
	Field stringNames:TMap = New TMap
	Field enumTypes:TMap = New TMap
	Field enumsById:TMap = New TMap
	Field structTypes:TMap = New TMap
	Field structsById:TMap = New TMap
	Field structNames:TMap = New TMap
	Field structFieldNames:TMap = New TMap
	Field importedStructTypes:TMap = New TMap
	Field importedStructsById:TMap = New TMap
	Field importedStructRoutinesById:TMap = New TMap
	Field classTypes:TMap = New TMap
	Field classesById:TMap = New TMap
	Field importedClassTypes:TMap = New TMap
	Field importedClassesById:TMap = New TMap
	Field importedFieldsById:TMap = New TMap
	Field importedMethodsById:TMap = New TMap
	Field importedConstructorsById:TMap = New TMap
	Field interfaceTypes:TMap = New TMap
	Field opaqueInterfaceTypes:TMap = New TMap
	Field interfacesById:TMap = New TMap
	Field classNames:TMap = New TMap
	Field objectNames:TMap = New TMap
	Field descriptorNames:TMap = New TMap
	Field constructorNames:TMap = New TMap
	Field fieldNames:TMap = New TMap
	Field currentIsMain:Int
	Field runtimeTypes:Int
	Field temporaryTypes:TMap = New TMap
	Field temporaryAddressValues:TMap = New TMap
	Field temporarySources:TMap = New TMap
	Field temporaryCallableReturns:TMap = New TMap
	Field temporaryCallableParameters:TMap = New TMap
	Field temporaryCallableConventions:TMap = New TMap
	Field temporaryNativeCallableAbiNames:TMap = New TMap
	Field temporaryOrder:String[] = New String[0]
	Field preparedTemporaryValues:TMap = New TMap
	Field currentDebugInstrumentation:Int
	Field currentCoverageInstrumentation:Int
	Field currentDebugScope:TCompilerIrDebugScope
	Field debugStatementIndex:Int
	Field debugScopeDepth:Int
	Field predeclaredDebugLocals:TMap = New TMap
	Field loopContinueDebugDepths:TMap = New TMap
	Field loopExitDebugDepths:TMap = New TMap
	Field cleanupResourceDebugDepths:TMap = New TMap
	Field cleanupFinallyDebugDepths:TMap = New TMap
	Field currentReturnType:String
	Field currentCallableReturnType:String
	Field currentCallableReturnParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field currentCallableReturnCallingConvention:String = "c"
	Field currentRoutine:TCompilerIrFunction
	Field currentIteratorFactory:TCompilerIrFunction
	Field currentIteratorStateClass:TCompilerIrClass
	Field currentIteratorReceiverName:String
	Field nextCleanupReturnId:Int
	Field nextTryFinallyId:Int
	Field nextNativeStringId:Int
	Field nativeStringScope:TCompilerCNativeStringScope
	Field allVariables:TCompilerIrVariableDeclaration[] = New TCompilerIrVariableDeclaration[0]
	Field picoRootLocals:TMap = New TMap
	Field picoRootLocalOrder:TCompilerIrVariableDeclaration[] = New TCompilerIrVariableDeclaration[0]
	Field gdbLocalNameCounts:TMap = New TMap
	Field currentPicoRootFrame:Int
	Field statementOutputBuilders:TStringBuilder[] = New TStringBuilder[0]
	Field statementOutputDepth:Int

	Function Emit:String(irModule:TCompilerIrModule, diagnostics:TCompilerDiagnostic[] Var)
		Local backend:TCompilerCBackend = New TCompilerCBackend
		Local result:String = backend.EmitModule(irModule)
		diagnostics = backend.diagnostics
		Return result
	End Function

	Function EmitRuntime:String(irModule:TCompilerIrModule, diagnostics:TCompilerDiagnostic[] Var)
		Local backend:TCompilerCBackend = New TCompilerCBackend
		backend.runtimeTypes = True
		Local result:String = backend.EmitRuntimeModule(irModule)
		diagnostics = backend.diagnostics
		Return result
	End Function

	Function EmitRuntimeHeader:String(irModule:TCompilerIrModule, diagnostics:TCompilerDiagnostic[] Var)
		Local backend:TCompilerCBackend = New TCompilerCBackend
		Local result:String
		If irModule And irModule.targetPlatform.ToLower() = "pico" Then
			result = backend.EmitPicoRuntimeHeaderModule(irModule)
		Else
			backend.runtimeTypes = True
			result = backend.EmitRuntimeHeaderModule(irModule)
		End If
		diagnostics = backend.diagnostics
		Return result
	End Function

	Method EmitPicoRuntimeHeaderModule:String(irModule:TCompilerIrModule)
		If Not irModule Or Not irModule.initializationPlan Then
			AddDiagnostic("BMXC2041", "Runtime header emission requires an initialization plan", Null)
			Return ""
		End If
		PrepareNames(irModule, False)
		Local plan:TCompilerIrInitializationPlan = irModule.initializationPlan
		Local guardName:String = "BCC2_PICO_" + SafeIdentifier(irModule.path + "." + irModule.buildMode + "." + irModule.targetArchitecture + ".h").ToUpper()
		Local result:TStringBuilder = New TStringBuilder(4096)
		result.Append("#ifndef " + guardName + "~n#define " + guardName + "~n~n")
		result.Append("#include <blitzmax/pico_runtime.h>~n")
		For Local dependency:TCompilerIrDependency = EachIn plan.dependencies
			If dependency.headerPath.length Then result.Append("#include <" + dependency.headerPath + ">~n")
		Next
		result.Append("~n#ifdef __cplusplus~nextern ~qC~q {~n#endif~n~n")
		result.Append("void " + plan.registerFunctionName + "(void);~n")
		result.Append("int " + plan.initializeFunctionName + "(void);~n")
		result.Append(EmitPicoClassForwards(irModule))
		result.Append(EmitStructs(irModule, True))
		result.Append(EmitPicoStructDescriptorPrototypes(irModule))
		result.Append(EmitStructNewHelperPrototypes(irModule, True))
		result.Append("~n#ifdef __cplusplus~n}~n#endif~n~n#endif~n")
		Return result.ToString()
	End Method

	Method EmitModule:String(irModule:TCompilerIrModule)
		If Not irModule Then
			AddDiagnostic("BMXC2000", "Compiler IR module was not available", Null)
			Return ""
		End If
		PrepareNames(irModule)
		Local result:TStringBuilder = New TStringBuilder(16384)
		result.Append("/* Generated by bcc 1.00 scalar C99 backend. */~n")
		result.Append("#include <stddef.h>~n#include <stdint.h>~n")
		If EmbeddedStringTypes() Then result.Append("#include <blitzmax/pico_runtime.h>~n")
		If EmbeddedStringTypes() And (Not irModule.initializationPlan Or irModule.initializationPlan.unitKind = IR_UNIT_APPLICATION) Then result.Append("void bmx_pico_modules_init(void);~n")
		result.Append("~n")
		result.Append(EmitPicoIncbinDeclarations(irModule))
		result.Append(EmitPicoClassForwards(irModule))
		If EmbeddedObjectTypes() Then result.Append(EmitImportedStructs(irModule))
		result.Append(EmitPicoImportedClassLayouts(irModule))
		result.Append(EmitPicoImportedConstructorPrototypes(irModule))
		result.Append(EmitPicoImportedMethodPrototypes(irModule))
		result.Append(EmitPicoFinalizerPrototypes(irModule))
		AppendGenericClassForwards(irModule, result)
		If Not EmbeddedObjectTypes() Then result.Append(EmitImportedStructs(irModule))
		result.Append(EmitStructs(irModule))
		result.Append(EmitPicoVirtualPrototypes(irModule))
		result.Append(EmitPicoStructDescriptors(irModule))
		result.Append(EmitPicoInterfaceDescriptors(irModule))
		If EmbeddedObjectTypes() Then result.Append(EmitExternalPrototypes(irModule))
		result.Append(EmitPicoClassLayouts(irModule))
		result.Append(EmitImportedStructPrototypes(irModule))
		If Not EmbeddedObjectTypes() Then result.Append(EmitExternalPrototypes(irModule))
		AppendEmbeddedStringLiterals(irModule, result)
		AppendPicoEnums(irModule, result)
		AppendGlobals(irModule, result)
		If runtimeTypes Then AppendDataSection(irModule, result)
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then Continue
			result.Append(EmitPrototype(routine)).Append(";~n")
		Next
		result.Append(EmitPicoObjectNewHelperPrototypes(irModule))
		result.Append(EmitStructNewHelperPrototypes(irModule))
		If irModule.functions.length > 1 Then result.Append("~n")
		result.Append(EmitStructNewHelpers(irModule))
		result.Append(EmitStructArrayInitializers(irModule))
		result.Append(EmitPicoImplicitConstructors(irModule))
		result.Append(EmitPicoBaseInitializers(irModule))
		result.Append(EmitPicoObjectNewHelpers(irModule))
		result.Append(EmitPicoFinalizers(irModule))
		result.Append(EmitPicoBaseFinalizers(irModule))
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then Continue
			result.Append(EmitFunction(routine)).Append("~n")
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then result.Append(EmitFunction(routine))
		Next
		Return result.ToString()
	End Method

	Method EmitPicoIncbinDeclarations:String(irModule:TCompilerIrModule)
		If Not EmbeddedStringTypes() Or Not irModule Or Not irModule.incbins.length Then Return ""
		Local result:String
		For Local resource:TCompilerIrIncbin = EachIn irModule.incbins
			result :+ "extern const unsigned char *" + resource.dataSymbol + ";~n"
			result :+ "extern const unsigned int " + resource.sizeSymbol + ";~n"
		Next
		Return result + "~n"
	End Method

	Method EmitPicoIncbinRegistration:String(indent:String)
		If Not EmbeddedStringTypes() Or Not currentModule Then Return ""
		Local result:String
		For Local resource:TCompilerIrIncbin = EachIn currentModule.incbins
			result :+ indent + "bbIncbinAdd(" + RuntimeStringPointer(resource.stringLiteralId) + ", &" + resource.dataSymbol + ", (int32_t)" + resource.sizeSymbol + ");~n"
		Next
		Return result
	End Method

	Method EmbeddedStringTypes:Int()
		Return Not runtimeTypes And currentModule And currentModule.targetPlatform.ToLower() = "pico"
	End Method

	Method EmbeddedArrayTypes:Int()
		Return EmbeddedStringTypes()
	End Method

	Method EmbeddedObjectTypes:Int()
		Return EmbeddedStringTypes()
	End Method

	Method PicoModuleUnit:Int()
		Return EmbeddedObjectTypes() And currentModule And currentModule.initializationPlan And currentModule.initializationPlan.unitKind = IR_UNIT_MODULE
	End Method

	Method PicoStringRuntimeFunctionName:String(externalFunction:TCompilerIrExternalFunction)
		If Not EmbeddedStringTypes() Or Not externalFunction Then Return ""
		Local abiName:String = externalFunction.implementationAbiName
		If Not abiName.length Then abiName = externalFunction.abiName
		Select abiName
			Case "bbStringCompare"; Return "bmx_pico_string_compare"
			Case "bbStringEquals"; Return "bmx_pico_string_equals"
			Case "bbStringHash"; Return "bmx_pico_string_hash"
			Case "bbStringCompareCase"; Return "bmx_pico_string_compare_case"
			Case "bbStringEqualsCase"; Return "bmx_pico_string_equals_case"
			Case "bbStringHashCase"; Return "bmx_pico_string_hash_case"
			Case "bbStringToString"; Return "bmx_pico_string_to_string"
			Case "bbStringFind"; Return "bmx_pico_string_find"
			Case "bbStringFindLast"; Return "bmx_pico_string_find_last"
			Case "bbStringTrim"; Return "bmx_pico_string_trim"
			Case "bbStringReplace"; Return "bmx_pico_string_replace"
			Case "bbStringToLower"; Return "bmx_pico_string_to_lower"
			Case "bbStringToUpper"; Return "bmx_pico_string_to_upper"
			Case "bbStringStartsWith"; Return "bmx_pico_string_starts_with"
			Case "bbStringEndsWith"; Return "bmx_pico_string_ends_with"
			Case "bbStringContains"; Return "bmx_pico_string_contains"
			Case "bbStringReplicate"; Return "bmx_pico_string_replicate"
			Case "bbStringSplit"; Return "bmx_pico_string_split"
			Case "bbStringJoin"; Return "bmx_pico_string_join"
			Case "bbStringSplitInts"; Return "bmx_pico_string_split_ints"
			Case "bbStringSplitBytes"; Return "bmx_pico_string_split_bytes"
			Case "bbStringSplitShorts"; Return "bmx_pico_string_split_shorts"
			Case "bbStringSplitUInts"; Return "bmx_pico_string_split_uints"
			Case "bbStringSplitLongs"; Return "bmx_pico_string_split_longs"
			Case "bbStringSplitULongs"; Return "bmx_pico_string_split_ulongs"
			Case "bbStringSplitSizets"; Return "bmx_pico_string_split_sizes"
			Case "bbStringSplitLongInts"; Return "bmx_pico_string_split_long_ints"
			Case "bbStringSplitULongInts"; Return "bmx_pico_string_split_ulong_ints"
			Case "bbStringSplitFloats"; Return "bmx_pico_string_split_floats"
			Case "bbStringSplitDoubles"; Return "bmx_pico_string_split_doubles"
			Case "bbStringJoinInts"; Return "bmx_pico_string_join_ints"
			Case "bbStringJoinBytes"; Return "bmx_pico_string_join_bytes"
			Case "bbStringJoinShorts"; Return "bmx_pico_string_join_shorts"
			Case "bbStringJoinUInts"; Return "bmx_pico_string_join_uints"
			Case "bbStringJoinLongs"; Return "bmx_pico_string_join_longs"
			Case "bbStringJoinULongs"; Return "bmx_pico_string_join_ulongs"
			Case "bbStringJoinSizets"; Return "bmx_pico_string_join_sizes"
			Case "bbStringJoinLongInts"; Return "bmx_pico_string_join_long_ints"
			Case "bbStringJoinULongInts"; Return "bmx_pico_string_join_ulong_ints"
			Case "bbStringJoinFloats"; Return "bmx_pico_string_join_floats"
			Case "bbStringJoinDoubles"; Return "bmx_pico_string_join_doubles"
			Case "bbStringFromBytes"; Return "bmx_pico_string_from_bytes"
			Case "bbStringFromShorts"; Return "bmx_pico_string_from_shorts"
			Case "bbStringFromCString"; Return "bmx_pico_string_from_c_string"
			Case "bbStringFromWString"; Return "bmx_pico_string_from_w_string"
			Case "bbStringFromUTF8String"; Return "bmx_pico_string_from_utf8_string"
			Case "bbStringFromUTF8Bytes"; Return "bmx_pico_string_from_utf8_bytes"
			Case "bbStringToCString"; Return "bmx_pico_string_to_c_string"
			Case "bbStringToWString"; Return "bmx_pico_string_to_w_string"
			Case "bbStringToWStringBuffer"; Return "bmx_pico_string_to_w_string_buffer"
			Case "bbStringToUTF8String"; Return "bmx_pico_string_to_utf8_string"
			Case "bbStringToUTF8StringLen"; Return "bmx_pico_string_to_utf8_string_len"
			Case "bbStringToUTF8StringBuffer"; Return "bmx_pico_string_to_utf8_string_buffer"
			Case "bbStringToUTF32String"; Return "bmx_pico_string_to_utf32_string"
			Case "bbStringFromUTF32String"; Return "bmx_pico_string_from_utf32_string"
			Case "bbStringFromUTF32Bytes"; Return "bmx_pico_string_from_utf32_bytes"
			Case "bbStringFromBytesAsHex"; Return "bmx_pico_string_from_bytes_as_hex"
			Case "bbStringToBytesFromHex"; Return "bmx_pico_string_to_bytes_from_hex"
			Case "bbStringToBytesFromHexEx"; Return "bmx_pico_string_to_bytes_from_hex_ex"
			Case "bbStringFromInt"; Return "bmx_pico_string_from_int32"
			Case "bbStringFromUInt"; Return "bmx_pico_string_from_uint32"
			Case "bbStringFromLong"; Return "bmx_pico_string_from_int64"
			Case "bbStringFromULong"; Return "bmx_pico_string_from_uint64"
			Case "bbStringFromSizet"; Return "bmx_pico_string_from_size"
			Case "bbStringFromLongInt"; Return "bmx_pico_string_from_long"
			Case "bbStringFromULongInt"; Return "bmx_pico_string_from_ulong"
			Case "bbStringFromFloat"; Return "bmx_pico_string_from_float"
			Case "bbStringFromDouble"; Return "bmx_pico_string_from_double"
			Case "bbStringToInt"; Return "bmx_pico_string_to_int32"
			Case "bbStringToUInt"; Return "bmx_pico_string_to_uint32"
			Case "bbStringToLong"; Return "bmx_pico_string_to_int64"
			Case "bbStringToULong"; Return "bmx_pico_string_to_uint64"
			Case "bbStringToSizet"; Return "bmx_pico_string_to_size"
			Case "bbStringToLongInt"; Return "bmx_pico_string_to_long"
			Case "bbStringToULongInt"; Return "bmx_pico_string_to_ulong"
			Case "bbStringToFloat"; Return "bmx_pico_string_to_float"
			Case "bbStringToDouble"; Return "bmx_pico_string_to_double"
		End Select
		Return ""
	End Method

	Method PicoScalarIntrinsicFunctionName:String(externalFunction:TCompilerIrExternalFunction)
		If Not EmbeddedStringTypes() Or Not externalFunction Then Return ""
		Local abiName:String = externalFunction.implementationAbiName
		If Not abiName.length Then abiName = externalFunction.abiName
		Select abiName
			Case "bbMilliSecs"; Return "bmx_pico_millisecs"
			Case "bbDelay"; Return "bmx_pico_delay"
			Case "bbUDelay"; Return "bmx_pico_udelay"
			Case "brl_blitz_Max"; Return "bmx_pico_max_i32"
			Case "brl_blitz_Max__Blong__Blong"; Return "bmx_pico_max_i64"
			Case "brl_blitz_Max__Bfloat__Bfloat"; Return "bmx_pico_max_f32"
			Case "brl_blitz_Max__Bdouble__Bdouble"; Return "bmx_pico_max_f64"
			Case "brl_blitz_Max__Bbyte__Bbyte"; Return "bmx_pico_max_u8"
			Case "brl_blitz_Max__Bshort__Bshort"; Return "bmx_pico_max_u16"
			Case "brl_blitz_Max__Buint__Buint"; Return "bmx_pico_max_u32"
			Case "brl_blitz_Max__Bulong__Bulong"; Return "bmx_pico_max_u64"
			Case "brl_blitz_Max__Bsize_t__Bsize_t"; Return "bmx_pico_max_size"
			Case "brl_blitz_Max__Blongint__Blongint"; Return "bmx_pico_max_long"
			Case "brl_blitz_Max__Bulongint__Bulongint"; Return "bmx_pico_max_ulong"
			Case "brl_blitz_Min__Bint__Bint"; Return "bmx_pico_min_i32"
			Case "brl_blitz_Min__Blong__Blong"; Return "bmx_pico_min_i64"
			Case "brl_blitz_Min__Bfloat__Bfloat"; Return "bmx_pico_min_f32"
			Case "brl_blitz_Min__Bdouble__Bdouble"; Return "bmx_pico_min_f64"
			Case "brl_blitz_Min__Bbyte__Bbyte"; Return "bmx_pico_min_u8"
			Case "brl_blitz_Min__Bshort__Bshort"; Return "bmx_pico_min_u16"
			Case "brl_blitz_Min__Buint__Buint"; Return "bmx_pico_min_u32"
			Case "brl_blitz_Min__Bulong__Bulong"; Return "bmx_pico_min_u64"
			Case "brl_blitz_Min__Bsize_t__Bsize_t"; Return "bmx_pico_min_size"
			Case "brl_blitz_Min__Blongint__Blongint"; Return "bmx_pico_min_long"
			Case "brl_blitz_Min__Bulongint__Bulongint"; Return "bmx_pico_min_ulong"
			Case "brl_blitz_Abs__Bint"; Return "bmx_pico_abs_i32"
			Case "brl_blitz_Abs__Blong"; Return "bmx_pico_abs_i64"
			Case "brl_blitz_Abs__Bfloat"; Return "bmx_pico_abs_f32"
			Case "brl_blitz_Abs__Bdouble"; Return "bmx_pico_abs_f64"
			Case "brl_blitz_Sgn__Bint"; Return "bmx_pico_sgn_i32"
			Case "brl_blitz_Sgn__Blong"; Return "bmx_pico_sgn_i64"
			Case "brl_blitz_Sgn__Bfloat"; Return "bmx_pico_sgn_f32"
			Case "brl_blitz_Sgn__Bdouble"; Return "bmx_pico_sgn_f64"
		End Select
		Return ""
	End Method

	Method PicoDesktopStringFunction:Int(externalFunction:TCompilerIrExternalFunction)
		If Not EmbeddedStringTypes() Or Not externalFunction Then Return False
		Local abiName:String = externalFunction.implementationAbiName
		If Not abiName.length Then abiName = externalFunction.abiName
		Return abiName.StartsWith("bbString")
	End Method

	Method PicoArrayElementSupported:Int(typeName:String)
		If typeName.Trim().ToLower().EndsWith(" ptr") Then Return True
		Select typeName.Trim().ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam", "float", "double", "float64"
				Return True
		End Select
		Local normalized:String = typeName.Trim().ToLower()
		Local irEnum:TCompilerIrEnum = TCompilerIrEnum(enumTypes.ValueForKey(normalized))
		If irEnum Then Return PicoArrayElementSupported(irEnum.underlyingType)
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(normalized))
		If irStruct Then Return PicoPlainStructSupported(irStruct)
		Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(normalized))
		If importedStruct Then Return PicoPlainImportedStructSupported(importedStruct)
		Return normalized = "string" Or PicoObjectStorageType(typeName)
	End Method

	Method PicoPlainStructSupported:Int(irStruct:TCompilerIrStruct)
		If Not irStruct Then Return False
		For Local irField:TCompilerIrStructField = EachIn irStruct.fields
			If irField.callableReturnType.length Then Return False
			If irField.isStaticArray Then
				If irField.staticArrayStructId.length Then
					If Not PicoPlainStructSupported(StructById(irField.staticArrayStructId)) Then Return False
			Else If irField.staticArrayImportedStructId.length Then
					Local importedStatic:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.staticArrayImportedStructId))
					If Not PicoPlainImportedStructSupported(importedStatic) Then Return False
				Else If Not PicoArrayElementSupported(irField.staticArrayElementType) Then
					Return False
				End If
			Else If irField.structId.length Then
				If Not PicoPlainStructSupported(StructById(irField.structId)) Then Return False
			Else If irField.importedStructId.length Then
				Local imported:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.importedStructId))
				If Not PicoPlainImportedStructSupported(imported) Then Return False
			Else If Not PicoArrayElementSupported(irField.semanticType) And Not PicoArrayStorageType(irField.semanticType) And Not irField.semanticType.Trim().ToLower().EndsWith(" ptr") Then
				Return False
			End If
		Next
		Return True
	End Method

	Method PicoPlainImportedStructSupported:Int(importedStruct:TCompilerIrImportedStruct)
		If Not importedStruct Then Return False
		For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
			If importedField.callableReturnType.length Then Return False
			If importedField.isStaticArray Then
				If importedField.staticArrayImportedStructId.length Then
					Local staticImported:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(importedField.staticArrayImportedStructId))
					If Not PicoPlainImportedStructSupported(staticImported) Then Return False
				Else If importedField.staticArrayStructId.length Then
					If Not PicoPlainStructSupported(StructById(importedField.staticArrayStructId)) Then Return False
				Else If Not PicoArrayElementSupported(importedField.staticArrayElementType) Then
					Return False
				End If
			Else If importedField.importedStructId.length Then
				Local nestedImported:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(importedField.importedStructId))
				If Not PicoPlainImportedStructSupported(nestedImported) Then Return False
			Else If importedField.structId.length Then
				If Not PicoPlainStructSupported(StructById(importedField.structId)) Then Return False
			Else If Not IsManagedCReferenceType(importedField.semanticType) And Not PicoArrayElementSupported(importedField.semanticType) And Not importedField.semanticType.Trim().ToLower().EndsWith(" ptr") Then
				Return False
			End If
		Next
		Return True
	End Method

	Method PicoArrayStorageType:Int(typeName:String)
		Return typeName.Trim().ToLower().EndsWith("]")
	End Method

	Method PicoArrayElementType:String(typeName:String)
		Local trimmed:String = typeName.Trim()
		Local openBracket:Int = trimmed.FindLast("[")
		If openBracket < 0 Then Return ""
		Return trimmed[..openBracket].Trim()
	End Method

	Method PicoArrayElementKind:String(typeName:String)
		Local normalized:String = typeName.Trim().ToLower()
		If normalized = "string" Then Return "BMX_PICO_ARRAY_ELEMENT_STRING"
		If PicoObjectStorageType(typeName) Then Return "BMX_PICO_ARRAY_ELEMENT_OBJECT"
		Return "BMX_PICO_ARRAY_ELEMENT_VALUE"
	End Method

	Method PicoObjectFieldSupported:Int(typeName:String)
		Local normalized:String = typeName.Trim().ToLower()
		If PicoArrayStorageType(typeName) Then Return PicoArrayElementSupported(PicoArrayElementType(typeName))
		If normalized = "string" Or PicoArrayElementSupported(typeName) Then Return True
		If typeName.Trim().ToLower().EndsWith(" ptr") Then Return True
		If PicoObjectStorageType(typeName) Then Return True
		Local irEnum:TCompilerIrEnum = TCompilerIrEnum(enumTypes.ValueForKey(typeName.Trim().ToLower()))
		If irEnum Then Return PicoArrayElementSupported(irEnum.underlyingType)
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(typeName.Trim().ToLower()))
		If irStruct Then Return PicoPlainStructSupported(irStruct)
		Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(typeName.Trim().ToLower()))
		If importedStruct Then Return PicoPlainImportedStructSupported(importedStruct)
		Return False
	End Method

	Method PicoObjectReferenceType:Int(typeName:String)
		Return classTypes.Contains(typeName.Trim().ToLower())
	End Method

	Method PicoObjectStorageType:Int(typeName:String)
		Local normalized:String = typeName.Trim().ToLower()
		If normalized.StartsWith("closure<") Or normalized = "object" Or classTypes.Contains(normalized) Or interfaceTypes.Contains(normalized) Then Return True
		Local importedClass:TCompilerIrImportedClass = TCompilerIrImportedClass(importedClassTypes.ValueForKey(normalized))
		Return importedClass And importedClass.abiName.length > 0
	End Method

	Method PicoGcRootStorageType:Int(typeName:String)
		Return typeName.Trim().ToLower() = "__pico_exception" Or typeName.Trim().ToLower() = "string" Or PicoObjectStorageType(typeName) Or PicoArrayStorageType(typeName) Or PicoManagedStructType(typeName)
	End Method

	Method PicoManagedStructType:Int(typeName:String)
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(typeName.Trim().ToLower()))
		If irStruct Then Return irStruct.containsManagedReferences And PicoPlainStructSupported(irStruct)
		Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(typeName.Trim().ToLower()))
		Return importedStruct And importedStruct.containsManagedReferences And PicoPlainImportedStructSupported(importedStruct)
	End Method

	Method PicoRootKind:String(typeName:String)
		If typeName.Trim().ToLower() = "__pico_exception" Then Return "BMX_PICO_ROOT_EXCEPTION"
		If typeName.Trim().ToLower() = "string" Then Return "BMX_PICO_ROOT_STRING"
		If PicoArrayStorageType(typeName) Then Return "BMX_PICO_ROOT_ARRAY"
		Return "BMX_PICO_ROOT_OBJECT"
	End Method

	Method StaticArrayIndexCType:String()
		If EmbeddedArrayTypes() Then Return "uint32_t"
		Return "BBUINT"
	End Method

	Method PicoRootSlotExpression:String(typeName:String, address:String)
		If PicoManagedStructType(typeName) Then
			Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(typeName.Trim().ToLower()))
			If irStruct Then Return "{ (void *)(" + address + "), BMX_PICO_ROOT_STRUCT, &" + PicoStructDescriptorName(irStruct) + " }"
			Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(typeName.Trim().ToLower()))
			Return "{ (void *)(" + address + "), BMX_PICO_ROOT_STRUCT, &" + PicoImportedStructDescriptorName(importedStruct) + " }"
		End If
		Return "{ (void *)(" + address + "), " + PicoRootKind(typeName) + ", 0 }"
	End Method

	Method PicoExpressionMaySafepoint:Int(expression:TCompilerIrExpression)
		If Not expression Then Return False
		If TCompilerIrLiteral(expression) Or TCompilerIrSymbolReference(expression) Or TCompilerIrCallableReference(expression) Or TCompilerIrCallableDefault(expression) Or TCompilerIrManagedDefault(expression) Then Return False
		Local addressOf:TCompilerIrAddressOf = TCompilerIrAddressOf(expression)
		If addressOf Then Return PicoExpressionMaySafepoint(addressOf.operand)
		Local pointerTruth:TCompilerIrPointerTruth = TCompilerIrPointerTruth(expression)
		If pointerTruth Then Return PicoExpressionMaySafepoint(pointerTruth.operand)
		Local pointerBinary:TCompilerIrPointerBinary = TCompilerIrPointerBinary(expression)
		If pointerBinary Then Return PicoExpressionMaySafepoint(pointerBinary.left) Or PicoExpressionMaySafepoint(pointerBinary.right)
		Local unary:TCompilerIrUnary = TCompilerIrUnary(expression)
		If unary Then Return PicoExpressionMaySafepoint(unary.operand)
		Local binary:TCompilerIrBinary = TCompilerIrBinary(expression)
		If binary Then Return PicoExpressionMaySafepoint(binary.left) Or PicoExpressionMaySafepoint(binary.right)
		Local conversion:TCompilerIrConversion = TCompilerIrConversion(expression)
		If conversion And PicoSafepointFreeScalarType(conversion.semanticType) And PicoSafepointFreeScalarType(conversion.operand.semanticType) Then Return PicoExpressionMaySafepoint(conversion.operand)
		Local fieldAccess:TCompilerIrFieldAccess = TCompilerIrFieldAccess(expression)
		If fieldAccess Then Return PicoExpressionMaySafepoint(fieldAccess.receiver)
		Local arrayLength:TCompilerIrArrayLength = TCompilerIrArrayLength(expression)
		If arrayLength Then Return PicoExpressionMaySafepoint(arrayLength.receiver)
		Local stringLength:TCompilerIrStringLength = TCompilerIrStringLength(expression)
		If stringLength Then Return PicoExpressionMaySafepoint(stringLength.receiver)
		Local arrayElement:TCompilerIrArrayElement = TCompilerIrArrayElement(expression)
		If arrayElement Then
			If PicoExpressionMaySafepoint(arrayElement.receiver) Then Return True
			For Local index:TCompilerIrExpression = EachIn arrayElement.indexes
				If PicoExpressionMaySafepoint(index) Then Return True
			Next
			Return False
		End If
		Local pointerElement:TCompilerIrPointerElement = TCompilerIrPointerElement(expression)
		If pointerElement Then Return PicoExpressionMaySafepoint(pointerElement.receiver) Or PicoExpressionMaySafepoint(pointerElement.index)
		Local materialize:TCompilerIrMaterialize = TCompilerIrMaterialize(expression)
		If materialize Then Return PicoExpressionMaySafepoint(materialize.value) Or PicoExpressionMaySafepoint(materialize.expression)
		' Calls, allocations, allocating conversions and any future expression
		' kind remain safepoints until their IR contract explicitly proves otherwise.
		Return True
	End Method

	Method PicoSafepointFreeScalarType:Int(typeName:String)
		Local normalized:String = typeName.Trim().ToLower()
		Select normalized
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double"
				Return True
		End Select
		Return enumTypes.Contains(normalized)
	End Method

	Method PicoBlockMaySafepoint:Int(block:TCompilerIrBlock)
		If Not block Then Return False
		For Local statement:TCompilerIrStatement = EachIn block.statements
			If PicoStatementMaySafepoint(statement) Then Return True
		Next
		Return False
	End Method

	Method PicoStatementMaySafepoint:Int(statement:TCompilerIrStatement)
		If Not statement Then Return False
		Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
		If variable Then Return PicoExpressionMaySafepoint(variable.initializer)
		Local assignment:TCompilerIrAssignment = TCompilerIrAssignment(statement)
		If assignment Then Return PicoExpressionMaySafepoint(assignment.target) Or PicoExpressionMaySafepoint(assignment.value)
		Local expressionStatement:TCompilerIrExpressionStatement = TCompilerIrExpressionStatement(statement)
		If expressionStatement Then Return PicoExpressionMaySafepoint(expressionStatement.expression)
		Local returnStatement:TCompilerIrReturn = TCompilerIrReturn(statement)
		If returnStatement Then Return returnStatement.cleanupSteps.length > 0 Or PicoExpressionMaySafepoint(returnStatement.expression)
		Local assertStatement:TCompilerIrAssert = TCompilerIrAssert(statement)
		If assertStatement Then Return PicoExpressionMaySafepoint(assertStatement.condition) Or PicoExpressionMaySafepoint(assertStatement.message)
		Local ifStatement:TCompilerIrIf = TCompilerIrIf(statement)
		If ifStatement Then
			If PicoExpressionMaySafepoint(ifStatement.condition) Or PicoBlockMaySafepoint(ifStatement.thenBody) Or PicoBlockMaySafepoint(ifStatement.elseBody) Then Return True
			For Local clause:TCompilerIrConditionalClause = EachIn ifStatement.elseIfClauses
				If PicoExpressionMaySafepoint(clause.condition) Or PicoBlockMaySafepoint(clause.body) Then Return True
			Next
			Return False
		End If
		Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
		If whileStatement Then Return PicoExpressionMaySafepoint(whileStatement.condition) Or PicoBlockMaySafepoint(whileStatement.body)
		Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
		If repeatStatement Then Return PicoExpressionMaySafepoint(repeatStatement.condition) Or PicoBlockMaySafepoint(repeatStatement.body)
		Local rangeStatement:TCompilerIrForRange = TCompilerIrForRange(statement)
		If rangeStatement Then
			Return PicoExpressionMaySafepoint(rangeStatement.target) Or PicoExpressionMaySafepoint(rangeStatement.initialValue) Or PicoExpressionMaySafepoint(rangeStatement.limit) Or PicoExpressionMaySafepoint(rangeStatement.stepExpression) Or PicoBlockMaySafepoint(rangeStatement.body)
		End If
		Local loopControl:TCompilerIrLoopControl = TCompilerIrLoopControl(statement)
		If loopControl Then Return loopControl.cleanupSteps.length > 0
		' Exceptions, Using, Yield, Release, object iteration, Data operations and
		' unfamiliar future statements retain their root frame conservatively.
		Return True
	End Method

	Method RegisterPicoRootLocal:Int(variable:TCompilerIrVariableDeclaration)
		If Not currentPicoRootFrame Or Not variable Or variable.storage <> "local" Or variable.callableReturnType.length Then Return False
		If variable.isStaticArray Then
			If Not PicoManagedStructType(variable.staticArrayElementType) Then Return False
		Else If Not PicoGcRootStorageType(variable.semanticType) Then
			Return False
		End If
		If Not picoRootLocals.Contains(variable.symbolId) Then
			picoRootLocals.Insert(variable.symbolId, variable)
			picoRootLocalOrder :+ [variable]
		End If
		Return True
	End Method

	Method RegisterPicoExceptionRoot:String(symbolId:String, name:String, semanticType:String, source:TCompilerSourceLocation)
		Local variable:TCompilerIrVariableDeclaration = New TCompilerIrVariableDeclaration
		variable.symbolId = symbolId
		variable.name = name
		variable.semanticType = semanticType
		variable.storage = "local"
		variable.source = source
		Local localName:String = LocalName(symbolId, name)
		localNames.Insert(symbolId, localName)
		RegisterPicoRootLocal(variable)
		Return localName
	End Method

	Method ExceptionLeaveStatement:String(indent:String)
		If EmbeddedObjectTypes() Then Return indent + "bmx_pico_exception_leave();~n"
		Return indent + "bbExLeave();~n"
	End Method

	Method EmitPicoRootLocalDeclarations:String(indent:String)
		Local result:String
		For Local variable:TCompilerIrVariableDeclaration = EachIn picoRootLocalOrder
			Local name:String = LocalName(variable.symbolId, variable.name)
			If variable.isStaticArray Then
				result :+ indent + CType(variable.staticArrayElementType, variable.source) + " " + name + "[" + variable.staticArrayLength + "] = {0};~n"
			Else
				result :+ indent + CVariableDeclaration(variable, name) + " = " + CDefaultValue(variable.semanticType) + ";~n"
			End If
		Next
		Return result
	End Method

	Method AppendPicoStaticArrayRootSlots(variable:TCompilerIrVariableDeclaration, name:String, slots:String[] Var)
		If Not variable Or Not variable.isStaticArray Or Not PicoManagedStructType(variable.staticArrayElementType) Then Return
		For Local index:Int = 0 Until variable.staticArrayLength
			slots :+ [PicoRootSlotExpression(variable.staticArrayElementType, "&" + name + "[" + index + "]")]
		Next
	End Method

	Method PicoRootSlotExpressions:String[](includeGlobals:Int = True)
		Local slots:String[] = New String[0]
		If currentRoutine And currentRoutine.receiver And PicoGcRootStorageType(currentRoutine.receiver.semanticType) Then
			Local receiverAddress:String = "&" + LocalName(currentRoutine.receiver.symbolId, currentRoutine.receiver.name)
			If PicoManagedStructType(currentRoutine.receiver.semanticType) Then receiverAddress = LocalName(currentRoutine.receiver.symbolId, currentRoutine.receiver.name)
			slots :+ [PicoRootSlotExpression(currentRoutine.receiver.semanticType, receiverAddress)]
		End If
		If currentRoutine Then
			For Local parameter:TCompilerIrParameter = EachIn currentRoutine.parameters
				If parameter.isStaticArray Then
					If PicoManagedStructType(parameter.staticArrayElementType) Then
						For Local index:Int = 0 Until parameter.staticArrayLength
							slots :+ [PicoRootSlotExpression(parameter.staticArrayElementType, "&" + LocalName(parameter.symbolId, parameter.name) + "[" + index + "]")]
						Next
					End If
					Continue
				End If
				If parameter.callableReturnType.length Or Not PicoGcRootStorageType(parameter.semanticType) Then Continue
				Local address:String = "&" + LocalName(parameter.symbolId, parameter.name)
				If parameter.passingMode = PARAMETER_PASS_VAR Then address = LocalName(parameter.symbolId, parameter.name)
				slots :+ [PicoRootSlotExpression(parameter.semanticType, address)]
			Next
		End If
		For Local variable:TCompilerIrVariableDeclaration = EachIn picoRootLocalOrder
			If variable.isStaticArray Then
				AppendPicoStaticArrayRootSlots(variable, LocalName(variable.symbolId, variable.name), slots)
			Else
				slots :+ [PicoRootSlotExpression(variable.semanticType, "&" + LocalName(variable.symbolId, variable.name))]
			End If
		Next
		For Local temporaryId:String = EachIn temporaryOrder
			Local temporaryType:String = String(temporaryTypes.ValueForKey(temporaryId))
			If temporaryAddressValues.Contains(temporaryId) Or String(temporaryCallableReturns.ValueForKey(temporaryId)).length Or Not PicoGcRootStorageType(temporaryType) Then Continue
			slots :+ [PicoRootSlotExpression(temporaryType, "&" + TemporaryName(temporaryId))]
		Next
		If currentIsMain And includeGlobals Then
			For Local variable:TCompilerIrVariableDeclaration = EachIn allVariables
				If Not variable Or variable.storage <> "global" Or variable.callableReturnType.length Then Continue
				If variable.isStaticArray Then
					AppendPicoStaticArrayRootSlots(variable, SymbolName(variable.symbolId, variable.name), slots)
				Else If PicoGcRootStorageType(variable.semanticType) Then
					slots :+ [PicoRootSlotExpression(variable.semanticType, "&" + SymbolName(variable.symbolId, variable.name))]
				End If
			Next
		End If
		Return slots
	End Method

	Method PicoGlobalRootSlotExpressions:String[]()
		Local slots:String[] = New String[0]
		For Local variable:TCompilerIrVariableDeclaration = EachIn allVariables
			If Not variable Or variable.storage <> "global" Or variable.callableReturnType.length Then Continue
			If variable.isStaticArray Then
				AppendPicoStaticArrayRootSlots(variable, SymbolName(variable.symbolId, variable.name), slots)
			Else If PicoGcRootStorageType(variable.semanticType) Then
				slots :+ [PicoRootSlotExpression(variable.semanticType, "&" + SymbolName(variable.symbolId, variable.name))]
			End If
		Next
		Return slots
	End Method

	Method EmitPicoRootFrameSetup:String(indent:String, includeGlobals:Int = True)
		If Not currentPicoRootFrame Then Return ""
		Local slots:String[] = PicoRootSlotExpressions(includeGlobals)
		Local result:String = indent + "BMXPicoRootFrame bmx_pico_root_frame;~n"
		If slots.length Then
			result :+ indent + "BMXPicoRootSlot bmx_pico_root_slots[" + slots.length + "] = { "
			For Local index:Int = 0 Until slots.length
				If index Then result :+ ", "
				result :+ slots[index]
			Next
			result :+ " };~n"
			result :+ indent + "bmx_pico_root_frame_enter(&bmx_pico_root_frame, bmx_pico_root_slots, " + slots.length + ");~n"
		Else
			result :+ indent + "bmx_pico_root_frame_enter(&bmx_pico_root_frame, 0, 0);~n"
		End If
		Return result
	End Method

	Method EmitPicoPersistentGlobalRootSetup:String(indent:String)
		Local slots:String[] = PicoGlobalRootSlotExpressions()
		If Not slots.length Then Return ""
		Local result:String = indent + "static BMXPicoRootFrame bmx_pico_global_root_frame;~n"
		result :+ indent + "static BMXPicoRootSlot bmx_pico_global_root_slots[" + slots.length + "] = { "
		For Local index:Int = 0 Until slots.length
			If index Then result :+ ", "
			result :+ slots[index]
		Next
		result :+ " };~n"
		Return result + indent + "bmx_pico_root_frame_enter(&bmx_pico_global_root_frame, bmx_pico_global_root_slots, " + slots.length + ");~n"
	End Method

	Method EmitPicoRootFrameLeave:String(indent:String)
		If currentPicoRootFrame Then Return indent + "bmx_pico_root_frame_leave(&bmx_pico_root_frame);~n"
		Return ""
	End Method

	Method PicoTypeDescriptorName:String(irClass:TCompilerIrClass)
		Return "bmx_pico_type_" + SafeIdentifier(irClass.classId + "_" + irClass.name)
	End Method

	Method PicoImportedTypeDescriptorName:String(importedClass:TCompilerIrImportedClass)
		Return "bmx_pico_imported_type_" + SafeIdentifier(importedClass.importedClassId + "_" + importedClass.name)
	End Method

	Method PicoEnumDescriptorName:String(irEnum:TCompilerIrEnum)
		Return "bmx_pico_enum_" + SafeIdentifier(irEnum.enumId + "_" + irEnum.name)
	End Method

	Method PicoStructDescriptorName:String(irStruct:TCompilerIrStruct)
		If Not irStruct Then Return ""
		Return PicoPublishedStructDescriptorName(StructName(irStruct.structId))
	End Method

	Method PicoPublishedStructDescriptorName:String(abiName:String)
		Return SafeIdentifier(abiName) + "_pico_value_descriptor"
	End Method

	Method PicoImportedStructDescriptorName:String(importedStruct:TCompilerIrImportedStruct)
		Return "bmx_pico_imported_value_" + SafeIdentifier(importedStruct.importedStructId + "_" + importedStruct.name)
	End Method

	Method PicoInterfaceDescriptorName:String(irInterface:TCompilerIrInterface)
		Return "bmx_pico_interface_" + SafeIdentifier(irInterface.interfaceId + "_" + irInterface.name)
	End Method

	Method PicoInterfaceDescriptorAvailable:Int(irInterface:TCompilerIrInterface)
		If Not irInterface Or irInterface.isExternInterface Then Return False
		Return Not irInterface.isImported Or irInterface.abiName.length > 0
	End Method

	Method PicoClassSlotIndex:Int(irClass:TCompilerIrClass, slotId:String)
		If Not irClass Then Return -1
		For Local index:Int = 0 Until irClass.functionSlots.length
			If irClass.functionSlots[index].slotId = slotId Then Return index
		Next
		Return -1
	End Method

	Method PicoImportedClassSlotIndex:Int(importedClass:TCompilerIrImportedClass, slotId:String)
		If Not importedClass Then Return -1
		Local importedMethod:TCompilerIrImportedMethod = ImportedMethodById(slotId)
		For Local index:Int = 0 Until importedClass.functionSlots.length
			Local slot:TCompilerIrClassFunctionSlot = importedClass.functionSlots[index]
			If slot.slotId = slotId Or slot.functionId = slotId Then Return index
			If importedMethod And slot.slotName.length And slot.slotName = importedMethod.slotName Then Return index
		Next
		Return -1
	End Method

	Method PicoSlotFunctionPointerType:String(slot:TCompilerIrClassFunctionSlot)
		If Not slot Then Return ""
		If slot.callableReturnType.length Then
			AddDiagnostic("BMXC2029", "Callable-return virtual methods are not available in the current Pico dispatch tier", slot.source)
			Return ""
		End If
		Local parameters:String
		If slot.isMethod Then
			Local receiverClass:TCompilerIrClass = ClassById(slot.receiverClassId)
			If Not receiverClass Then receiverClass = ClassById(slot.declaringClassId)
			If receiverClass Then
				parameters = "struct " + ObjectName(receiverClass.classId) + " *"
			Else
				Local importedReceiver:TCompilerIrImportedClass = ImportedClassById(slot.receiverImportedClassId)
				If Not importedReceiver Then importedReceiver = ImportedClassById(slot.declaringImportedClassId)
				If Not importedReceiver Then Return ""
				parameters = "struct " + importedReceiver.abiName + "_obj *"
			End If
		End If
		For Local parameter:TCompilerIrParameter = EachIn slot.parameters
			If parameters.length Then parameters :+ ", "
			parameters :+ CParameterType(parameter, slot.source)
		Next
		If Not parameters.length Then parameters = "void"
		Return CType(slot.returnType, slot.source) + " (*)(" + parameters + ")"
	End Method

	Method PicoInterfaceFunctionPointerType:String(method:TCompilerIrInterfaceMethod)
		If Not method Or method.callableReturnType.length Then Return ""
		Local parameters:String = "BMXPicoObject *"
		For Local parameter:TCompilerIrParameter = EachIn method.parameters
			parameters :+ ", " + CParameterType(parameter, method.source)
		Next
		Return CType(method.returnType, method.source) + " (*)(" + parameters + ")"
	End Method

	Method EmitRuntimeModule:String(irModule:TCompilerIrModule)
		If Not irModule Or Not irModule.initializationPlan Then
			AddDiagnostic("BMXC2040", "Runtime-compatible C emission requires an initialization plan", Null)
			Return ""
		End If
		PrepareNames(irModule)
		Local plan:TCompilerIrInitializationPlan = irModule.initializationPlan
		Local result:TStringBuilder = New TStringBuilder(65536)
		result.Append("/* Generated by bcc 1.00 BlitzMax runtime C backend. */~n")
		result.Append("#include <stddef.h>~n#include <stdint.h>~n")
		result.Append("#include <brl.mod/blitz.mod/blitz.h>~n")
		result.Append(EmitClosureRuntimeDeclaration())
		result.Append(EmitClosureAllocationSupport(irModule))
		For Local nativeHeader:String = EachIn irModule.nativeHeaders
			result.Append("#include ~q").Append(nativeHeader).Append("~q~n")
		Next
		result.Append("~n")
		For Local dependency:TCompilerIrDependency = EachIn plan.dependencies
			If dependency.headerPath.length Then result.Append("#include <").Append(dependency.headerPath).Append(">~n")
		Next
		If plan.dependencies.length Then result.Append("~n")
		result.Append(EmitDebugBoundsHelpers(irModule))
		result.Append(EmitDebugPointerHelpers(irModule))
		For Local resource:TCompilerIrIncbin = EachIn irModule.incbins
			result.Append("extern const unsigned char *").Append(resource.dataSymbol).Append(";~n")
			result.Append("extern const unsigned int ").Append(resource.sizeSymbol).Append(";~n")
		Next
		If irModule.incbins.length Then result.Append("~n")
		result.Append(EmitStructs(irModule))
		result.Append(EmitGenericStructs(irModule))
		result.Append(EmitRuntimeClassForwards(irModule))
		AppendGenericClassForwards(irModule, result)
		AppendRuntimeInterfaces(irModule, False, result)
		result.Append(EmitGenericStructPrototypes(irModule))
		For Local dependency:TCompilerIrDependency = EachIn plan.dependencies
			result.Append("extern void ").Append(dependency.registerFunctionName).Append("(void);~n")
			result.Append("extern int ").Append(dependency.initializeFunctionName).Append("(void);~n")
		Next
		For Local registration:TCompilerIrGenericImplementationRegistration = EachIn plan.genericImplementationRegistrations
			result.Append("extern void ").Append(registration.functionName).Append("(void);~n")
		Next
		For Local registration:TCompilerIrGenericCoverageRegistration = EachIn plan.genericCoverageRegistrations
			result.Append("extern void ").Append(registration.functionName).Append("(void);~n")
		Next
		If plan.dependencies.length Or plan.genericImplementationRegistrations.length Or plan.genericCoverageRegistrations.length Then result.Append("~n")
		result.Append(EmitExternalPrototypes(irModule, True))
		result.Append(EmitNativeStringWrappers(irModule))
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then Continue
			result.Append(EmitPrototype(routine)).Append(";~n")
			If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR And Not routine.ownerStructId.length And routine.parameters.length Then result.Append(EmitObjectNewHelperPrototype(routine)).Append(";~n")
		Next
		result.Append(EmitLegacyRoutineAliasPrototypes(irModule, False))
		result.Append(EmitStructNewHelperPrototypes(irModule))
		If irModule.functions.length > 1 Then result.Append("~n")
		result.Append(EmitClosureLiterals(irModule))
		AppendRuntimeStringLiterals(irModule, result)
		AppendRuntimeEnums(irModule, result)
		AppendGlobals(irModule, result)
		AppendDataSection(irModule, result)
		result.Append(EmitCoverageCatalog(irModule))
		AppendRuntimeClasses(irModule, False, result)
		result.Append(EmitRuntimeStructDebugScopes(irModule))
		result.Append(EmitStructNewHelpers(irModule))
		result.Append(EmitStructArrayInitializers(irModule))
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then Continue
			result.Append(EmitFunction(routine)).Append("~n")
			If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR And Not routine.ownerStructId.length And routine.parameters.length Then result.Append(EmitObjectNewHelper(routine)).Append("~n")
		Next
		result.Append(EmitLegacyRoutineAliases(irModule))
		AppendRuntimeStringInitialization(irModule, result)
		result.Append(EmitRuntimeRegistration(irModule, plan)).Append("~n")
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then result.Append(EmitRuntimeInitialization(routine, plan))
		Next
		Return result.ToString()
	End Method

	Method EmitDebugBoundsHelpers:String(irModule:TCompilerIrModule)
		If Not runtimeTypes Or Not irModule Or Not irModule.hasDebugBoundsChecks Then Return ""
		Local result:String = "static void *bmx_debug_array_element(BBARRAY array, BBINT index, size_t element_size) {~n"
		result :+ "    return (char *)bbArrayIndex(array, 1, index) + (size_t)index * element_size;~n"
		result :+ "}~n~n"
		result :+ "static void *bmx_debug_static_array_element(void *data, BBINT index, BBUINT length, size_t element_size) {~n"
		result :+ "    if (index < 0 || (BBUINT)index >= length) brl_blitz_ArrayBoundsError();~n"
		result :+ "    return (char *)data + (size_t)index * element_size;~n"
		result :+ "}~n~n"
		result :+ "static BBINT bmx_debug_string_element(BBSTRING string, BBINT index) {~n"
		result :+ "    if (index < 0 || index >= string->length) brl_blitz_ArrayBoundsError();~n"
		result :+ "    return string->buf[index];~n"
		result :+ "}~n~n"
		Return result
	End Method

	Method EmitCoverageCatalog:String(irModule:TCompilerIrModule)
		If Not runtimeTypes Or Not irModule Or Not irModule.coverageFiles.length Then Return ""
		Local result:TStringBuilder = New TStringBuilder(4096)
		For Local fileIndex:Int = 0 Until irModule.coverageFiles.length
			Local file:TCompilerIrCoverageFile = irModule.coverageFiles[fileIndex]
			If file.lines.length Then
				result.Append("static const int bmx_coverage_lines_").Append(fileIndex).Append("[] = {")
				For Local lineIndex:Int = 0 Until file.lines.length
					If lineIndex Then result.Append(", ")
					result.Append(file.lines[lineIndex])
				Next
				result.Append("};~n")
			End If
			If file.functions.length Then
				result.Append("static const BBCoverageFunctionInfo bmx_coverage_functions_").Append(fileIndex).Append("[] = {~n")
				For Local coverageFunction:TCompilerIrCoverageFunction = EachIn file.functions
					result.Append("    { ").Append(CQuoted(coverageFunction.name)).Append(", ").Append(coverageFunction.line).Append(" },~n")
				Next
				result.Append("};~n")
			End If
		Next
		result.Append("static BBCoverageFileInfo bmx_coverage_files[] = {~n")
		For Local fileIndex:Int = 0 Until irModule.coverageFiles.length
			Local file:TCompilerIrCoverageFile = irModule.coverageFiles[fileIndex]
			Local linesName:String = "NULL"
			Local functionsName:String = "NULL"
			If file.lines.length Then linesName = "bmx_coverage_lines_" + fileIndex
			If file.functions.length Then functionsName = "bmx_coverage_functions_" + fileIndex
			result.Append("    { ").Append(CQuoted(file.path)).Append(", ").Append(linesName).Append(", ").Append(file.lines.length).Append(", NULL, ").Append(functionsName).Append(", ").Append(file.functions.length).Append(", NULL },~n")
		Next
		result.Append("    { NULL, NULL, 0, NULL, NULL, 0, NULL }~n};~n~n")
		Return result.ToString()
	End Method

	Method EmitCoverageFunctionEntry:String(routine:TCompilerIrFunction, indent:String)
		If Not runtimeTypes Or Not currentCoverageInstrumentation Or Not routine Or Not routine.coverageFunction Or Not routine.source Or Not routine.source.path.length Or routine.source.line <= 0 Then Return ""
		Return indent + "bbCoverageUpdateFunctionLineInfo(" + CQuoted(routine.source.path.Replace("\", "/")) + ", " + CQuoted(routine.coverageName) + ", " + routine.source.line + ");~n"
	End Method

	Method EmitCoveragePoint:String(statement:TCompilerIrStatement, indent:String)
		If Not runtimeTypes Or Not currentCoverageInstrumentation Or Not statement Or Not statement.coveragePoint Or Not statement.source Or Not statement.source.path.length Or statement.source.line <= 0 Then Return ""
		Return indent + "bbCoverageUpdateLineInfo(" + CQuoted(statement.source.path.Replace("\", "/")) + ", " + statement.source.line + ");~n"
	End Method

	Method EmitClosureRuntimeDeclaration:String()
		If Not runtimeTypes Then Return ""
		Return "~n#ifndef BMX_BBCLOSURE_DEFINED~n#define BMX_BBCLOSURE_DEFINED~ntypedef struct BBClosure {~n    BBObject object;~n    BBFuncPtr invoke;~n    BBOBJECT environment;~n} BBClosure;~n#endif~n~n"
	End Method

	Method EmitClosureAllocationSupport:String(irModule:TCompilerIrModule)
		If Not runtimeTypes Or Not irModule Then Return ""
		Local required:Int
		For Local literal:TCompilerIrClosureLiteral = EachIn irModule.closureLiterals
			If literal And literal.environment Then required = True; Exit
		Next
		If Not required Then Return ""
		Local result:String = "static BBClass bmx_closure_capture_class = {~n"
		result :+ "    &bbObjectClass, bbObjectFree, 0, sizeof(BBClosure),~n"
		result :+ "    bbObjectCtor, bbObjectDtor, bbObjectToString, bbObjectCompare, bbObjectSendMessage, bbObjectHashCode, bbObjectEquals,~n"
		result :+ "    0, 0, sizeof(BBOBJECT), 0, offsetof(BBClosure, environment)~n};~n"
		result :+ "static BBClosure *bmx_closure_capture_new(BBFuncPtr invoke, BBOBJECT environment) {~n"
		result :+ "    BBClosure *closure = (BBClosure *)bbObjectNew(&bmx_closure_capture_class);~n"
		result :+ "    closure->invoke = invoke;~n    closure->environment = environment;~n    return closure;~n}~n~n"
		Return result
	End Method

	Method EmitClosureLiterals:String(irModule:TCompilerIrModule)
		If Not irModule Or Not irModule.closureLiterals.length Then Return ""
		If EmbeddedObjectTypes() Then Return ""
		Local emitted:TMap = New TMap
		Local result:String
		For Local literal:TCompilerIrClosureLiteral = EachIn irModule.closureLiterals
			If Not literal Or emitted.Contains(literal.literalId) Then Continue
			emitted.Insert(literal.literalId, literal)
			If literal.environment Then Continue
			Local targetName:String = literal.abiName
			If Not targetName.length Then targetName = FunctionName(literal.functionId)
			result :+ "static BBClosure " + ClosureLiteralName(literal.literalId) + " = { { &bbObjectClass }, (BBFuncPtr)&" + targetName + ", (BBOBJECT)&bbNullObject };~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Function ClosureLiteralName:String(literalId:String)
		Return "bmx_closure_" + SafeIdentifier(literalId)
	End Function

	Method EmitDebugPointerHelpers:String(irModule:TCompilerIrModule)
		If Not runtimeTypes Or Not irModule Or Not irModule.hasDebugPointerChecks Then Return ""
		Local result:String = "static void *bmx_debug_pointer_element(void *data, ptrdiff_t index, size_t element_size) {~n"
		result :+ "    if (!data) brl_blitz_RuntimeError(bbStringFromCString(~qAttempt to access null pointer~q));~n"
		result :+ "    return (char *)data + index * (ptrdiff_t)element_size;~n"
		result :+ "}~n~n"
		Return result
	End Method

	Method EmitRuntimeClassForwards:String(irModule:TCompilerIrModule)
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			result :+ "struct " + ObjectName(irClass.classId) + ";~n"
			result :+ "struct " + ClassName(irClass.classId) + ";~n"
			result :+ "extern struct " + ClassName(irClass.classId) + " " + DescriptorName(irClass.classId) + ";~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoClassForwards:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			result :+ "struct " + importedClass.abiName + "_obj;~n"
		Next
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			result :+ "struct " + ObjectName(irClass.classId) + ";~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoImportedClassLayouts:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If Not importedClass.abiName.length Then Continue
			result :+ "struct " + importedClass.abiName + "_obj {~n    BMXPicoObject object;~n"
			For Local importedField:TCompilerIrImportedField = EachIn importedClass.fields
				If importedField.isStaticArray Then
					Local staticSupported:Int
					If importedField.staticArrayImportedStructId.length Then
						staticSupported = PicoPlainImportedStructSupported(TCompilerIrImportedStruct(importedStructsById.ValueForKey(importedField.staticArrayImportedStructId)))
					Else If importedField.staticArrayStructId.length Then
						staticSupported = PicoPlainStructSupported(StructById(importedField.staticArrayStructId))
					Else
						staticSupported = PicoArrayElementSupported(importedField.staticArrayElementType)
					End If
					If staticSupported Then
						result :+ "    " + CType(importedField.staticArrayElementType, importedField.source) + " " + importedField.abiName + "[" + importedField.staticArrayLength + "];~n"
					Else
						AddDiagnostic("BMXC2029", "Imported Type field '" + importedClass.name + "." + importedField.name + "' is outside the current Pico object-layout slice", importedField.source)
						result :+ "    uint8_t " + importedField.abiName + ";~n"
					End If
				Else If Not importedField.callableReturnType.length And Not PicoObjectFieldSupported(importedField.semanticType) Then
					AddDiagnostic("BMXC2029", "Imported Type field '" + importedClass.name + "." + importedField.name + "' is outside the current Pico object-layout slice", importedField.source)
					result :+ "    uint8_t " + importedField.abiName + ";~n"
				Else If importedField.callableReturnType.length Then
					result :+ "    " + CCallableFieldDeclaration(importedField.callableReturnType, importedField.callableParameters, importedField.abiName, importedField.source, importedField.callableCallingConvention) + ";~n"
				Else
					result :+ "    " + CType(importedField.semanticType, importedField.source) + " " + importedField.abiName + ";~n"
				End If
			Next
			result :+ "};~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoVirtualPrototypes:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local emitted:TMap = New TMap
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
				If Not slot.functionId.length Or emitted.Contains(slot.functionId) Then Continue
				Local routine:TCompilerIrFunction = FunctionById(slot.functionId)
				If Not routine Then Continue
				result :+ EmitPrototype(routine) + ";~n"
				emitted.Insert(slot.functionId, routine)
			Next
			For Local implementation:TCompilerIrInterfaceImplementation = EachIn irClass.interfaceImplementations
				For Local implementationSlot:TCompilerIrInterfaceImplementationSlot = EachIn implementation.slots
					If Not implementationSlot Or Not implementationSlot.functionId.length Or emitted.Contains(implementationSlot.functionId) Then Continue
					Local implementationRoutine:TCompilerIrFunction = FunctionById(implementationSlot.functionId)
					If Not implementationRoutine Then Continue
					result :+ EmitPrototype(implementationRoutine) + ";~n"
					emitted.Insert(implementationSlot.functionId, implementationRoutine)
				Next
			Next
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method PicoValueKind:String(typeName:String)
		If typeName.Trim().ToLower() = "string" Then Return "BMX_PICO_VALUE_STRING"
		If PicoArrayStorageType(typeName) Then Return "BMX_PICO_VALUE_ARRAY"
		Return "BMX_PICO_VALUE_OBJECT"
	End Method

	Method EmitPicoInterfaceDescriptors:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If importedClass.abiName.length Then result :+ "static const BMXPicoTypeDescriptor " + PicoImportedTypeDescriptorName(importedClass) + ";~n"
		Next
		If irModule.importedClasses.length Then result :+ "~n"
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If Not importedClass.abiName.length Then
				AddDiagnostic("BMXC2029", "Imported Type '" + importedClass.name + "' has no Pico descriptor ABI", importedClass.source)
				Continue
			End If
			Local importedSuperDescriptor:String = "0"
			If importedClass.baseImportedClassId.length Then
				Local importedBase:TCompilerIrImportedClass = ImportedClassById(importedClass.baseImportedClassId)
				If importedBase Then importedSuperDescriptor = "&" + PicoImportedTypeDescriptorName(importedBase)
			End If
			result :+ "static const BMXPicoTypeDescriptor " + PicoImportedTypeDescriptorName(importedClass) + " = { .name = " + CQuoted(importedClass.name) + ", .abi_name = " + CQuoted(importedClass.abiName) + ", .instance_size = (uint32_t)sizeof(struct " + importedClass.abiName + "_obj), .super = " + importedSuperDescriptor + " };~n"
		Next
		If irModule.importedClasses.length Then result :+ "~n"
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If Not PicoInterfaceDescriptorAvailable(irInterface) Then
				AddDiagnostic("BMXC2029", "Imported or native Interface '" + irInterface.name + "' has no Pico descriptor ABI", irInterface.source)
				Continue
			End If
			result :+ "static const BMXPicoInterfaceDescriptor " + PicoInterfaceDescriptorName(irInterface) + " = { " + CQuoted(irInterface.name) + ", " + CQuoted(irInterface.abiName) + " };~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoStructDescriptors:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If importedStruct.containsManagedReferences And PicoPlainImportedStructSupported(importedStruct) Then result :+ "static const BMXPicoValueDescriptor " + PicoImportedStructDescriptorName(importedStruct) + ";~n"
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If PicoPlainStructSupported(irStruct) Then result :+ "extern const BMXPicoValueDescriptor " + PicoStructDescriptorName(irStruct) + ";~n"
		Next
		If result.length Then result :+ "~n"
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If Not PicoPlainStructSupported(irStruct) Then Continue
			Local descriptorName:String = PicoStructDescriptorName(irStruct)
			Local fields:String
			Local fieldCount:Int
			For Local irField:TCompilerIrStructField = EachIn irStruct.fields
				Local nested:TCompilerIrStruct
				Local nestedImported:TCompilerIrImportedStruct
				Local kind:String
				Local descriptor:String = "0"
				Local count:String = "1"
				Local stride:String = "0"
				Local fieldType:String = irField.semanticType
				If irField.isStaticArray Then
					count = String(irField.staticArrayLength)
					stride = "(uint32_t)sizeof(" + CType(irField.staticArrayElementType, irField.source) + ")"
					fieldType = irField.staticArrayElementType
					If irField.staticArrayStructId.length Then nested = StructById(irField.staticArrayStructId)
					If irField.staticArrayImportedStructId.length Then nestedImported = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.staticArrayImportedStructId))
				Else If irField.structId.length Then
					nested = StructById(irField.structId)
				Else If irField.importedStructId.length Then
					nestedImported = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.importedStructId))
				End If
				If nested And nested.containsManagedReferences Then
					kind = "BMX_PICO_VALUE_STRUCT"
					descriptor = "&" + PicoStructDescriptorName(nested)
				Else If nestedImported And nestedImported.containsManagedReferences Then
					kind = "BMX_PICO_VALUE_STRUCT"
					descriptor = "&" + PicoImportedStructDescriptorName(nestedImported)
				Else If IsManagedCReferenceType(fieldType) Then
					kind = PicoValueKind(fieldType)
				Else
					Continue
				End If
				fields :+ "    { (uint32_t)offsetof(struct " + StructName(irStruct.structId) + ", " + StructFieldName(irStruct.structId, irField.fieldId) + "), " + stride + ", " + count + ", " + kind + ", " + descriptor + " },~n"
				fieldCount :+ 1
			Next
			Local fieldPointer:String = "0"
			If fieldCount Then
				result :+ "static const BMXPicoValueField " + descriptorName + "_fields[" + fieldCount + "] = {~n" + fields + "};~n"
				fieldPointer = descriptorName + "_fields"
			End If
			result :+ "const BMXPicoValueDescriptor " + descriptorName + " = { " + CQuoted(irStruct.name) + ", (uint32_t)sizeof(struct " + StructName(irStruct.structId) + "), " + fieldPointer + ", " + fieldCount + " };~n~n"
		Next
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If Not importedStruct.containsManagedReferences Or Not PicoPlainImportedStructSupported(importedStruct) Then Continue
			Local descriptorName:String = PicoImportedStructDescriptorName(importedStruct)
			Local fields:String
			Local fieldCount:Int
			For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
				Local nested:TCompilerIrImportedStruct
				Local nestedLocal:TCompilerIrStruct
				Local fieldType:String = importedField.semanticType
				Local count:String = "1"
				Local stride:String = "0"
				If importedField.isStaticArray Then
					fieldType = importedField.staticArrayElementType
					count = String(importedField.staticArrayLength)
					stride = "(uint32_t)sizeof(" + CType(fieldType, importedField.source) + ")"
					If importedField.staticArrayImportedStructId.length Then nested = TCompilerIrImportedStruct(importedStructsById.ValueForKey(importedField.staticArrayImportedStructId))
					If importedField.staticArrayStructId.length Then nestedLocal = StructById(importedField.staticArrayStructId)
				Else If importedField.importedStructId.length Then
					nested = TCompilerIrImportedStruct(importedStructsById.ValueForKey(importedField.importedStructId))
				Else If importedField.structId.length Then
					nestedLocal = StructById(importedField.structId)
				End If
				Local kind:String
				Local descriptor:String = "0"
				If nested And nested.containsManagedReferences Then
					kind = "BMX_PICO_VALUE_STRUCT"
					descriptor = "&" + PicoImportedStructDescriptorName(nested)
				Else If nestedLocal And nestedLocal.containsManagedReferences Then
					kind = "BMX_PICO_VALUE_STRUCT"
					descriptor = "&" + PicoStructDescriptorName(nestedLocal)
				Else If IsManagedCReferenceType(fieldType) Then
					kind = PicoValueKind(fieldType)
				Else
					Continue
				End If
				fields :+ "    { (uint32_t)offsetof(struct " + importedStruct.abiName + ", " + importedField.abiName + "), " + stride + ", " + count + ", " + kind + ", " + descriptor + " },~n"
				fieldCount :+ 1
			Next
			result :+ "static const BMXPicoValueField " + descriptorName + "_fields[" + fieldCount + "] = {~n" + fields + "};~n"
			result :+ "static const BMXPicoValueDescriptor " + descriptorName + " = { " + CQuoted(importedStruct.name) + ", (uint32_t)sizeof(struct " + importedStruct.abiName + "), " + descriptorName + "_fields, " + fieldCount + " };~n~n"
		Next
		Return result
	End Method

	Method EmitPicoStructDescriptorPrototypes:String(irModule:TCompilerIrModule)
		If Not irModule Or irModule.targetPlatform.ToLower() <> "pico" Then Return ""
		Local result:String
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If (Not irStruct.isPublished And Not irStruct.hasStableLocalAbi) Or Not PicoPlainStructSupported(irStruct) Then Continue
			result :+ "extern const BMXPicoValueDescriptor " + PicoStructDescriptorName(irStruct) + ";~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoClassLayouts:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			result :+ "struct " + ObjectName(irClass.classId) + " {~n    BMXPicoObject object;~n"
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				If irField.isStaticArray Then
					Local staticSupported:Int
					If irField.staticArrayImportedStructId.length Then
						staticSupported = PicoPlainImportedStructSupported(TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.staticArrayImportedStructId)))
					Else If irField.staticArrayStructId.length Then
						staticSupported = PicoPlainStructSupported(StructById(irField.staticArrayStructId))
					Else
						staticSupported = PicoArrayElementSupported(irField.staticArrayElementType)
					End If
					If staticSupported Then
						result :+ "    " + CType(irField.staticArrayElementType, irField.source) + " " + FieldName(irField.declaringClassId, irField.fieldId) + "[" + irField.staticArrayLength + "];~n"
					Else
						AddDiagnostic("BMXC2029", "Type field '" + irClass.name + "." + irField.name + "' is not supported by the Pico StaticArray profile", irField.source)
						result :+ "    uint8_t " + FieldName(irField.declaringClassId, irField.fieldId) + ";~n"
					End If
				Else If Not irField.callableReturnType.length And Not PicoObjectFieldSupported(irField.semanticType) Then
					AddDiagnostic("BMXC2029", "Type field '" + irClass.name + "." + irField.name + "' is not a supported scalar in the initial Pico Object profile", irField.source)
					result :+ "    uint8_t " + FieldName(irField.declaringClassId, irField.fieldId) + ";~n"
				Else
					result :+ "    " + CFieldDeclaration(irField, FieldName(irField.declaringClassId, irField.fieldId)) + ";~n"
				End If
			Next
			result :+ "};~n"
			Local referenceCount:Int
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				If Not irField.isStaticArray And Not irField.callableReturnType.length And PicoObjectStorageType(irField.semanticType) Then referenceCount :+ 1
			Next
			Local referenceOffsets:String = "0"
			If referenceCount Then
				referenceOffsets = PicoTypeDescriptorName(irClass) + "_references"
				result :+ "static const uint32_t " + referenceOffsets + "[] = {~n"
				For Local irField:TCompilerIrClassField = EachIn irClass.fields
					If irField.isStaticArray Or irField.callableReturnType.length Or Not PicoObjectStorageType(irField.semanticType) Then Continue
					result :+ "    (uint32_t)offsetof(struct " + ObjectName(irClass.classId) + ", " + FieldName(irField.declaringClassId, irField.fieldId) + "),~n"
				Next
				result :+ "};~n"
			End If
			Local arrayCount:Int
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				If Not irField.isStaticArray And Not irField.callableReturnType.length And PicoArrayStorageType(irField.semanticType) Then arrayCount :+ 1
			Next
			Local arrayOffsets:String = "0"
			If arrayCount Then
				arrayOffsets = PicoTypeDescriptorName(irClass) + "_arrays"
				result :+ "static const uint32_t " + arrayOffsets + "[] = {~n"
				For Local irField:TCompilerIrClassField = EachIn irClass.fields
					If irField.isStaticArray Or irField.callableReturnType.length Or Not PicoArrayStorageType(irField.semanticType) Then Continue
					result :+ "    (uint32_t)offsetof(struct " + ObjectName(irClass.classId) + ", " + FieldName(irField.declaringClassId, irField.fieldId) + "),~n"
				Next
				result :+ "};~n"
			End If
			Local stringCount:Int
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				If Not irField.isStaticArray And Not irField.callableReturnType.length And irField.semanticType.Trim().ToLower() = "string" Then stringCount :+ 1
			Next
			Local stringOffsets:String = "0"
			If stringCount Then
				stringOffsets = PicoTypeDescriptorName(irClass) + "_strings"
				result :+ "static const uint32_t " + stringOffsets + "[] = {~n"
				For Local irField:TCompilerIrClassField = EachIn irClass.fields
					If irField.isStaticArray Or irField.callableReturnType.length Or irField.semanticType.Trim().ToLower() <> "string" Then Continue
					result :+ "    (uint32_t)offsetof(struct " + ObjectName(irClass.classId) + ", " + FieldName(irField.declaringClassId, irField.fieldId) + "),~n"
				Next
				result :+ "};~n"
			End If
			Local valueFieldCount:Int
			Local valueFields:String
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				If irField.callableReturnType.length Then Continue
				Local fieldStruct:TCompilerIrStruct
				Local importedFieldStruct:TCompilerIrImportedStruct
				Local count:String = "1"
				Local stride:String = "0"
				If irField.isStaticArray Then
					count = String(irField.staticArrayLength)
					stride = "(uint32_t)sizeof(" + CType(irField.staticArrayElementType, irField.source) + ")"
					If irField.staticArrayStructId.length Then fieldStruct = StructById(irField.staticArrayStructId)
					If irField.staticArrayImportedStructId.length Then importedFieldStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.staticArrayImportedStructId))
				Else
					fieldStruct = TCompilerIrStruct(structTypes.ValueForKey(irField.semanticType.Trim().ToLower()))
					importedFieldStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(irField.semanticType.Trim().ToLower()))
				End If
				Local fieldDescriptor:String
				If fieldStruct And fieldStruct.containsManagedReferences And PicoPlainStructSupported(fieldStruct) Then
					fieldDescriptor = PicoStructDescriptorName(fieldStruct)
				Else If importedFieldStruct And importedFieldStruct.containsManagedReferences And PicoPlainImportedStructSupported(importedFieldStruct) Then
					fieldDescriptor = PicoImportedStructDescriptorName(importedFieldStruct)
				Else
					Continue
				End If
				valueFields :+ "    { (uint32_t)offsetof(struct " + ObjectName(irClass.classId) + ", " + FieldName(irField.declaringClassId, irField.fieldId) + "), " + stride + ", " + count + ", BMX_PICO_VALUE_STRUCT, &" + fieldDescriptor + " },~n"
				valueFieldCount :+ 1
			Next
			Local valueFieldName:String = "0"
			If valueFieldCount Then
				valueFieldName = PicoTypeDescriptorName(irClass) + "_values"
				result :+ "static const BMXPicoValueField " + valueFieldName + "[" + valueFieldCount + "] = {~n" + valueFields + "};~n"
			End If
			Local interfaceEntries:String = "0"
			If irClass.interfaceImplementations.length Then
				interfaceEntries = PicoTypeDescriptorName(irClass) + "_interfaces"
				For Local implementationIndex:Int = 0 Until irClass.interfaceImplementations.length
					Local implementation:TCompilerIrInterfaceImplementation = irClass.interfaceImplementations[implementationIndex]
					Local irInterface:TCompilerIrInterface = InterfaceById(implementation.interfaceId)
					If Not PicoInterfaceDescriptorAvailable(irInterface) Then Continue
					Local interfaceMethods:String = interfaceEntries + "_" + implementationIndex
					Local methodCount:Int = implementation.slots.length
					If methodCount Then
						result :+ "static const BMXPicoMethod " + interfaceMethods + "[" + methodCount + "] = {~n"
						For Local implementationSlot:TCompilerIrInterfaceImplementationSlot = EachIn implementation.slots
							If implementationSlot And implementationSlot.functionId.length Then
								result :+ "    (BMXPicoMethod)" + FunctionName(implementationSlot.functionId) + ",~n"
							Else If implementationSlot And implementationSlot.functionAbiName.length Then
								result :+ "    (BMXPicoMethod)" + implementationSlot.functionAbiName + ",~n"
							Else
								result :+ "    0,~n"
							End If
						Next
						result :+ "};~n"
					Else
						interfaceMethods = "0"
					End If
				Next
				result :+ "static const BMXPicoInterfaceEntry " + interfaceEntries + "[" + irClass.interfaceImplementations.length + "] = {~n"
				For Local implementationIndex:Int = 0 Until irClass.interfaceImplementations.length
					Local implementation:TCompilerIrInterfaceImplementation = irClass.interfaceImplementations[implementationIndex]
					Local irInterface:TCompilerIrInterface = InterfaceById(implementation.interfaceId)
					Local interfaceMethods:String = interfaceEntries + "_" + implementationIndex
					If Not implementation.slots.length Then interfaceMethods = "0"
					If PicoInterfaceDescriptorAvailable(irInterface) Then
						result :+ "    { &" + PicoInterfaceDescriptorName(irInterface) + ", " + interfaceMethods + ", " + implementation.slots.length + " },~n"
					Else
						result :+ "    { 0, 0, 0 },~n"
					End If
				Next
				result :+ "};~n"
			End If
			Local methodTable:String = "0"
			If irClass.functionSlots.length Then
				methodTable = PicoTypeDescriptorName(irClass) + "_methods"
				result :+ "static const BMXPicoMethod " + methodTable + "[" + irClass.functionSlots.length + "] = {~n"
				For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
					If slot.functionId.length Then result :+ "    (BMXPicoMethod)" + FunctionName(slot.functionId) + ",~n" Else result :+ "    0,~n"
				Next
				result :+ "};~n"
			End If
			Local superDescriptor:String = "0"
			If irClass.baseClassId.length Then superDescriptor = "&" + PicoTypeDescriptorName(ClassById(irClass.baseClassId))
			If irClass.baseImportedClassId.length Then
				Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
				If importedBase Then superDescriptor = "&" + PicoImportedTypeDescriptorName(importedBase)
			End If
			result :+ "static const BMXPicoTypeDescriptor " + PicoTypeDescriptorName(irClass) + " = {~n"
			Local typeAbiName:String
			If (irClass.isPublished Or irClass.hasStableLocalAbi) And irClass.abiName.length Then typeAbiName = irClass.abiName
			result :+ "    .name = " + CQuoted(irClass.name) + ", .abi_name = " + CQuoted(typeAbiName) + ", .instance_size = (uint32_t)sizeof(struct " + ObjectName(irClass.classId) + "),~n"
			result :+ "    .super = " + superDescriptor + ", .methods = " + methodTable + ", .method_count = " + irClass.functionSlots.length + ",~n"
			result :+ "    .interfaces = " + interfaceEntries + ", .interface_count = " + irClass.interfaceImplementations.length + ",~n"
			result :+ "    .reference_offsets = " + referenceOffsets + ", .reference_count = " + referenceCount + ",~n"
			Local finalizerFlags:String = "0"
			Local finalizer:String = "0"
			If PicoClassHasFinalizer(irClass) Then
				finalizerFlags = "BMX_PICO_TYPE_FLAG_HAS_FINALIZER"
				finalizer = PicoFinalizerName(irClass)
			End If
			Local compareHook:String = "0"
			Local hashCodeHook:String = "0"
			Local equalsHook:String = "0"
			If irClass.compareFunctionId.length Then compareHook = PicoObjectCompareName(irClass)
			If irClass.hashCodeFunctionId.length Then hashCodeHook = PicoObjectHashCodeName(irClass)
			If irClass.equalsFunctionId.length Then equalsHook = PicoObjectEqualsName(irClass)
			result :+ "    .array_offsets = " + arrayOffsets + ", .array_count = " + arrayCount + ",~n"
			result :+ "    .string_offsets = " + stringOffsets + ", .string_count = " + stringCount + ",~n"
			result :+ "    .value_fields = " + valueFieldName + ", .value_field_count = " + valueFieldCount + ", .flags = " + finalizerFlags + ",~n"
			result :+ "    .trace = 0, .finalizer = " + finalizer + ",~n"
			result :+ "    .compare = " + compareHook + ", .hash_code = " + hashCodeHook + ", .equals = " + equalsHook + "~n};~n"
			If Not irClass.defaultConstructorFunctionId.length Then result :+ "static void " + ConstructorName(irClass.classId) + "(struct " + ObjectName(irClass.classId) + " *o);~n"
			result :+ "~n"
		Next
		Return result
	End Method

	Method PicoFinalizerName:String(irClass:TCompilerIrClass)
		Return "bmx_pico_finalize_" + SafeIdentifier(irClass.classId + "_" + irClass.name)
	End Method

	Function PicoBaseInitializerAbiName:String(abiName:String)
		Return "_" + abiName + "_PicoBaseInit"
	End Function

	Function PicoBaseFinalizerAbiName:String(abiName:String)
		Return "_" + abiName + "_PicoBaseFinalize"
	End Function

	Method PicoOwnDestructor:TCompilerIrFunction(irClass:TCompilerIrClass)
		If Not irClass Or Not irClass.destructorFunctionId.length Then Return Null
		Local destructor:TCompilerIrFunction = FunctionById(irClass.destructorFunctionId)
		If destructor And destructor.ownerClassId = irClass.classId Then Return destructor
		Return Null
	End Method

	Method PicoClassHasFinalizer:Int(irClass:TCompilerIrClass)
		If Not irClass Then Return False
		If PicoOwnDestructor(irClass) Then Return True
		If irClass.baseClassId.length Then Return PicoClassHasFinalizer(ClassById(irClass.baseClassId))
		If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			Return importedBase And importedBase.destructorFunctionId.length > 0
		End If
		Return False
	End Method

	Method PicoObjectCompareName:String(irClass:TCompilerIrClass)
		Return "bmx_pico_compare_" + SafeIdentifier(irClass.classId + "_" + irClass.name)
	End Method

	Method PicoObjectHashCodeName:String(irClass:TCompilerIrClass)
		Return "bmx_pico_hash_code_" + SafeIdentifier(irClass.classId + "_" + irClass.name)
	End Method

	Method PicoObjectEqualsName:String(irClass:TCompilerIrClass)
		Return "bmx_pico_equals_" + SafeIdentifier(irClass.classId + "_" + irClass.name)
	End Method

	Method PicoObjectHookReceiverType:String(irClass:TCompilerIrClass, functionId:String)
		Local routine:TCompilerIrFunction = FunctionById(functionId)
		If routine And routine.ownerClassId.length Then
			Local owner:TCompilerIrClass = ClassById(routine.ownerClassId)
			If owner Then Return "struct " + ObjectName(owner.classId) + " *"
		End If
		Local importedMethod:TCompilerIrImportedMethod = ImportedMethodById(functionId)
		If importedMethod Then
			Local importedOwner:TCompilerIrImportedClass = ImportedClassById(importedMethod.declaringImportedClassId)
			If importedOwner Then Return "struct " + importedOwner.abiName + "_obj *"
		End If
		Return "struct " + ObjectName(irClass.classId) + " *"
	End Method

	Method EmitPicoFinalizerPrototypes:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If PicoClassHasFinalizer(irClass) Then result :+ "static void " + PicoFinalizerName(irClass) + "(void *object);~n"
			If irClass.isPublished And irClass.abiName.length And PicoClassHasFinalizer(irClass) Then result :+ "void " + PicoBaseFinalizerAbiName(irClass.abiName) + "(void *object);~n"
			If irClass.compareFunctionId.length Then result :+ "static int32_t " + PicoObjectCompareName(irClass) + "(void *object, void *other);~n"
			If irClass.hashCodeFunctionId.length Then result :+ "static uint32_t " + PicoObjectHashCodeName(irClass) + "(void *object);~n"
			If irClass.equalsFunctionId.length Then result :+ "static int32_t " + PicoObjectEqualsName(irClass) + "(void *object, void *other);~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoFinalizers:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If PicoClassHasFinalizer(irClass) Then
				result :+ "static void " + PicoFinalizerName(irClass) + "(void *object) {~n"
				Local ownDestructor:TCompilerIrFunction = PicoOwnDestructor(irClass)
				If ownDestructor Then result :+ "    " + FunctionName(ownDestructor.functionId) + "((struct " + ObjectName(irClass.classId) + " *)object);~n"
				If irClass.baseClassId.length And PicoClassHasFinalizer(ClassById(irClass.baseClassId)) Then result :+ "    " + PicoFinalizerName(ClassById(irClass.baseClassId)) + "(object);~n"
				If irClass.baseImportedClassId.length Then
					Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
					If importedBase And importedBase.destructorFunctionId.length Then result :+ "    " + PicoBaseFinalizerAbiName(importedBase.abiName) + "(object);~n"
				End If
				result :+ "}~n~n"
			End If
			If irClass.compareFunctionId.length Then
				result :+ "static int32_t " + PicoObjectCompareName(irClass) + "(void *object, void *other) {~n"
				result :+ "    return " + FunctionName(irClass.compareFunctionId) + "((" + PicoObjectHookReceiverType(irClass, irClass.compareFunctionId) + ")object, (BMXPicoObject *)other);~n"
				result :+ "}~n~n"
			End If
			If irClass.hashCodeFunctionId.length Then
				result :+ "static uint32_t " + PicoObjectHashCodeName(irClass) + "(void *object) {~n"
				result :+ "    return " + FunctionName(irClass.hashCodeFunctionId) + "((" + PicoObjectHookReceiverType(irClass, irClass.hashCodeFunctionId) + ")object);~n"
				result :+ "}~n~n"
			End If
			If irClass.equalsFunctionId.length Then
				result :+ "static int32_t " + PicoObjectEqualsName(irClass) + "(void *object, void *other) {~n"
				result :+ "    return " + FunctionName(irClass.equalsFunctionId) + "((" + PicoObjectHookReceiverType(irClass, irClass.equalsFunctionId) + ")object, (BMXPicoObject *)other);~n"
				result :+ "}~n~n"
			End If
		Next
		Return result
	End Method

	Method EmitPicoBaseFinalizers:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If Not irClass.isPublished Or Not irClass.abiName.length Or Not PicoClassHasFinalizer(irClass) Then Continue
			result :+ "void " + PicoBaseFinalizerAbiName(irClass.abiName) + "(void *object) {~n"
			result :+ "    " + PicoFinalizerName(irClass) + "(object);~n}~n~n"
		Next
		Return result
	End Method

	Method PicoDefaultObjectNewName:String(irClass:TCompilerIrClass)
		If irClass And (irClass.isPublished Or irClass.hasStableLocalAbi) And irClass.abiName.length Then Return "_" + irClass.abiName + "_New_ObjectNew"
		Return "bmx_pico_new_" + SafeIdentifier(irClass.classId + "_" + irClass.name)
	End Method

	Method PicoObjectNewStorage:String(irClass:TCompilerIrClass)
		If irClass And (irClass.isPublished Or irClass.hasStableLocalAbi) Then Return ""
		Return "static "
	End Method

	Method EmitPicoObjectNewHelperPrototypes:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Or Not irModule.classes.length Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			result :+ PicoObjectNewStorage(irClass) + "struct " + ObjectName(irClass.classId) + " *" + PicoDefaultObjectNewName(irClass) + "(void);~n"
			If irClass.isPublished And irClass.abiName.length Then result :+ "void " + PicoBaseInitializerAbiName(irClass.abiName) + "(struct " + ObjectName(irClass.classId) + " *object);~n"
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR And routine.ownerClassId.length And routine.parameters.length Then result :+ EmitObjectNewHelperPrototype(routine) + ";~n"
		Next
		Return result + "~n"
	End Method

	Method EmitPicoImportedConstructorPrototypes:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If importedClass.abiName.length Then
				result :+ "extern void " + PicoBaseInitializerAbiName(importedClass.abiName) + "(struct " + importedClass.abiName + "_obj *object);~n"
				If importedClass.destructorFunctionId.length Then result :+ "extern void " + PicoBaseFinalizerAbiName(importedClass.abiName) + "(void *object);~n"
			End If
			For Local constructor:TCompilerIrImportedConstructor = EachIn importedClass.constructors
				If constructor.implementationAbiName.length Then
					result :+ "extern void " + constructor.implementationAbiName + "(struct " + importedClass.abiName + "_obj *object"
					For Local parameter:TCompilerIrParameter = EachIn constructor.parameters
						result :+ ", " + CParameterType(parameter, constructor.source)
					Next
					result :+ ");~n"
				End If
				If Not constructor.objectNewAbiName.length Then Continue
				result :+ "extern struct " + importedClass.abiName + "_obj *" + constructor.objectNewAbiName + "("
				For Local index:Int = 0 Until constructor.parameters.length
					If index Then result :+ ", "
					result :+ CParameterType(constructor.parameters[index], constructor.source)
				Next
				If Not constructor.parameters.length Then result :+ "void"
				result :+ ");~n"
			Next
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoImportedMethodPrototypes:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local emitted:TMap = New TMap
		Local result:String
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			For Local importedMethod:TCompilerIrImportedMethod = EachIn importedClass.methods
				If importedMethod.isAbstract Or Not importedMethod.implementationAbiName.length Or emitted.Contains(importedMethod.implementationAbiName) Then Continue
				Local declaringClass:TCompilerIrImportedClass = ImportedClassById(importedMethod.declaringImportedClassId)
				If Not declaringClass Then declaringClass = importedClass
				Local parameters:String = "struct " + declaringClass.abiName + "_obj *"
				For Local parameter:TCompilerIrParameter = EachIn importedMethod.parameters
					parameters :+ ", " + CParameterType(parameter, importedMethod.source)
				Next
				result :+ "extern " + CFunctionDeclaration(importedMethod.returnType, importedMethod.callableReturnType, importedMethod.callableReturnParameters, importedMethod.implementationAbiName, parameters, importedMethod.source, importedMethod.callingConvention, importedMethod.callableReturnCallingConvention) + ";~n"
				emitted.Insert(importedMethod.implementationAbiName, importedMethod)
			Next
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPicoImplicitConstructors:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If irClass.defaultConstructorFunctionId.length Then Continue
			localNames = New TMap
			ResetTemporaries()
			Local body:String = EmitPicoConstructorPrologue(irClass, "o", Null, "    ")
			result :+ "static void " + ConstructorName(irClass.classId) + "(struct " + ObjectName(irClass.classId) + " *o) {~n"
			result :+ EmitTemporaryDeclarations("    ") + body + "}~n~n"
		Next
		Return result
	End Method

	Method EmitPicoBaseInitializers:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If Not irClass.isPublished Or Not irClass.abiName.length Then Continue
			Local constructorName:String = ConstructorName(irClass.classId)
			If irClass.defaultConstructorFunctionId.length Then constructorName = FunctionName(irClass.defaultConstructorFunctionId)
			result :+ "void " + PicoBaseInitializerAbiName(irClass.abiName) + "(struct " + ObjectName(irClass.classId) + " *object) {~n"
			result :+ "    " + constructorName + "(object);~n}~n~n"
		Next
		Return result
	End Method

	Method EmitPicoObjectNewHelpers:String(irModule:TCompilerIrModule)
		If Not EmbeddedObjectTypes() Then Return ""
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			Local objectType:String = "struct " + ObjectName(irClass.classId) + " *"
			result :+ PicoObjectNewStorage(irClass) + objectType + PicoDefaultObjectNewName(irClass) + "(void) {~n"
			result :+ "    " + objectType + "o = (" + objectType + ")&bmx_pico_null_object;~n"
			result :+ "    BMXPicoRootFrame bmx_pico_new_root_frame;~n    BMXPicoRootSlot bmx_pico_new_root_slots[1] = { { (void *)&o, BMX_PICO_ROOT_OBJECT, 0 } };~n"
			result :+ "    bmx_pico_root_frame_enter(&bmx_pico_new_root_frame, bmx_pico_new_root_slots, 1);~n"
			result :+ "    o = (" + objectType + ")bmx_pico_object_allocate(&" + PicoTypeDescriptorName(irClass) + ");~n"
			result :+ "    if ((void *)o == (void *)&bmx_pico_null_object) { bmx_pico_root_frame_leave(&bmx_pico_new_root_frame); return o; }~n"
			Local constructorName:String = ConstructorName(irClass.classId)
			If irClass.defaultConstructorFunctionId.length Then constructorName = FunctionName(irClass.defaultConstructorFunctionId)
			result :+ "    " + constructorName + "(o);~n    bmx_pico_root_frame_leave(&bmx_pico_new_root_frame);~n    return o;~n}~n~n"
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.lifecycleKind <> IR_LIFECYCLE_CONSTRUCTOR Or Not routine.ownerClassId.length Or Not routine.parameters.length Then Continue
			Local irClass:TCompilerIrClass = ClassById(routine.ownerClassId)
			Local objectType:String = "struct " + ObjectName(irClass.classId) + " *"
			result :+ EmitObjectNewHelperPrototype(routine) + " {~n"
			result :+ "    " + objectType + "o = (" + objectType + ")&bmx_pico_null_object;~n"
			result :+ "    BMXPicoRootFrame bmx_pico_new_root_frame;~n    BMXPicoRootSlot bmx_pico_new_root_slots[1] = { { (void *)&o, BMX_PICO_ROOT_OBJECT, 0 } };~n"
			result :+ "    bmx_pico_root_frame_enter(&bmx_pico_new_root_frame, bmx_pico_new_root_slots, 1);~n"
			result :+ "    o = (" + objectType + ")bmx_pico_object_allocate(&" + PicoTypeDescriptorName(irClass) + ");~n"
			result :+ "    if ((void *)o == (void *)&bmx_pico_null_object) { bmx_pico_root_frame_leave(&bmx_pico_new_root_frame); return o; }~n"
			result :+ "    " + FunctionName(routine.functionId) + "(o"
			For Local parameter:TCompilerIrParameter = EachIn routine.parameters
				result :+ ", " + LocalName(parameter.symbolId, parameter.name)
			Next
			result :+ ");~n    bmx_pico_root_frame_leave(&bmx_pico_new_root_frame);~n    return o;~n}~n~n"
		Next
		Return result
	End Method

	Method EmitPublishedRuntimeClassTypeForwards:String(irModule:TCompilerIrModule)
		Local result:String
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If Not irClass.isPublished And Not irClass.hasStableLocalAbi And Not PrivateClassRequiredByPublishedRuntimeContract(irModule, irClass) Then Continue
			' A private Type can occur in a private virtual slot of a public Type.
			' The slot still occupies the published C class layout even though
			' neither declaration belongs in the compact language interface.  Give
			' each required local tag file scope before a published slot mentions it;
			' otherwise C gives an undeclared parameter-list tag prototype scope.
			' Stable application-local tags are also used by application-owned generic
			' method prototypes published in the generated application header.
			result :+ "struct " + ObjectName(irClass.classId) + ";~n"
			result :+ "struct " + ClassName(irClass.classId) + ";~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method PrivateClassRequiredByPublishedRuntimeContract:Int(irModule:TCompilerIrModule, candidate:TCompilerIrClass)
		If Not irModule Or Not candidate Then Return False
		For Local owner:TCompilerIrClass = EachIn irModule.classes
			If Not owner.isPublished Then Continue
			For Local irField:TCompilerIrClassField = EachIn owner.fields
				If RuntimeTypeUsesClass(irField.semanticType, candidate) Or RuntimeTypeUsesClass(irField.staticArrayElementType, candidate) Or RuntimeTypeUsesClass(irField.callableReturnType, candidate) Or RuntimeTypeUsesClass(irField.arrayCallableReturnType, candidate) Then Return True
				For Local parameter:TCompilerIrParameter = EachIn irField.callableParameters
					If RuntimeParameterUsesClass(parameter, candidate) Then Return True
				Next
				For Local parameter:TCompilerIrParameter = EachIn irField.arrayCallableParameters
					If RuntimeParameterUsesClass(parameter, candidate) Then Return True
				Next
			Next
			For Local slot:TCompilerIrClassFunctionSlot = EachIn owner.functionSlots
				If RuntimeTypeUsesClass(slot.returnType, candidate) Or RuntimeTypeUsesClass(slot.callableReturnType, candidate) Then Return True
				For Local parameter:TCompilerIrParameter = EachIn slot.callableReturnParameters
					If RuntimeParameterUsesClass(parameter, candidate) Then Return True
				Next
				For Local parameter:TCompilerIrParameter = EachIn slot.parameters
					If RuntimeParameterUsesClass(parameter, candidate) Then Return True
				Next
			Next
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then Continue
			Local publishedContract:Int = routine.visibility = VISIBILITY_PUBLIC
			If routine.ownerClassId.length Then
				Local owner:TCompilerIrClass = ClassById(routine.ownerClassId)
				publishedContract = owner And owner.isPublished
			Else If routine.ownerStructId.length Then
				Local ownerStruct:TCompilerIrStruct = StructById(routine.ownerStructId)
				publishedContract = ownerStruct And ownerStruct.isPublished
			End If
			If Not publishedContract Then Continue
			If RuntimeTypeUsesClass(routine.returnType, candidate) Or RuntimeTypeUsesClass(routine.callableReturnType, candidate) Then Return True
			For Local parameter:TCompilerIrParameter = EachIn routine.callableReturnParameters
				If RuntimeParameterUsesClass(parameter, candidate) Then Return True
			Next
			For Local parameter:TCompilerIrParameter = EachIn routine.parameters
				If RuntimeParameterUsesClass(parameter, candidate) Then Return True
			Next
		Next
		Return False
	End Method

	Method RuntimeParameterUsesClass:Int(parameter:TCompilerIrParameter, candidate:TCompilerIrClass)
		If Not parameter Then Return False
		If RuntimeTypeUsesClass(parameter.semanticType, candidate) Or RuntimeTypeUsesClass(parameter.staticArrayElementType, candidate) Or RuntimeTypeUsesClass(parameter.callableReturnType, candidate) Then Return True
		For Local nested:TCompilerIrParameter = EachIn parameter.callableParameters
			If RuntimeParameterUsesClass(nested, candidate) Then Return True
		Next
		Return False
	End Method

	Method RuntimeTypeUsesClass:Int(typeName:String, candidate:TCompilerIrClass)
		If Not candidate Or Not typeName.length Then Return False
		Local normalized:String = typeName.Trim().ToLower()
		While normalized.EndsWith(" ptr")
			normalized = normalized[..normalized.length - 4].Trim()
		Wend
		Return normalized = candidate.semanticType.ToLower() Or normalized = candidate.name.ToLower()
	End Method

	Method AppendGenericClassTypeForwards(irModule:TCompilerIrModule, result:TStringBuilder)
		Local startLength:Int = result.Length()
		' A C Struct tag first introduced inside a function parameter list has
		' prototype scope. Declare every imported generic Type tag before any
		' class-table layout can refer to a different specialization.
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If Not importedClass.isGenericSpecialization Then Continue
			result.Append("struct " + importedClass.abiName + "_obj;~n")
			result.Append("struct " + importedClass.abiName + "_class;~n")
		Next
		If result.Length() > startLength Then result.Append("~n")
	End Method

	Method AppendGenericClassForwards(irModule:TCompilerIrModule, result:TStringBuilder, appendTypeForwards:Int = True)
		' The embedded backend reconstructs every imported object with a
		' BMXPicoObject header in EmitPicoImportedClassLayouts.  The generic
		' declaration below is the desktop BBClass layout and must not emit a
		' second, incompatible definition for Pico specialization units.
		If EmbeddedObjectTypes() Then Return
		Local startLength:Int = result.Length()
		If appendTypeForwards Then AppendGenericClassTypeForwards(irModule, result)
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If Not importedClass.isGenericSpecialization Then Continue
			Local objectName:String = importedClass.abiName + "_obj"
			Local className:String = importedClass.abiName + "_class"
			Local declarationGuard:String = GenericDeclarationGuard("class", importedClass.abiName)
			result.Append("#ifndef " + declarationGuard + "~n#define " + declarationGuard + "~n")
			result.Append("struct " + className + " {~n")
			result.Append("    BBClass *super;~n    void (*free)(BBObject *o);~n    BBDebugScope *debug_scope;~n")
			result.Append("    unsigned int instance_size;~n    void (*ctor)(BBOBJECT o);~n    void (*dtor)(BBOBJECT o);~n")
			result.Append("    BBSTRING (*ToString)(BBOBJECT x);~n    int (*Compare)(BBOBJECT x, BBOBJECT y);~n")
			result.Append("    BBOBJECT (*SendMessage)(BBOBJECT o, BBOBJECT m, BBOBJECT s);~n")
			result.Append("    BBUINT (*HashCode)(BBOBJECT o);~n    BBINT (*Equals)(BBOBJECT o, BBOBJECT y);~n")
			result.Append("    BBINTERFACETABLE itable;~n    void *extra;~n    unsigned int obj_size;~n")
			result.Append("    unsigned int instance_count;~n    unsigned int fields_offset;~n")
			Local methodPrototypes:String
			For Local importedMethod:TCompilerIrImportedMethod = EachIn importedClass.methods
				If importedMethod.isDestructor Then Continue
				Local receiverObjectName:String = objectName
				If importedMethod.declaringImportedClassId.length Then
					Local declaringClass:TCompilerIrImportedClass = ImportedClassById(importedMethod.declaringImportedClassId)
					If declaringClass Then receiverObjectName = declaringClass.abiName + "_obj"
				End If
				Local parameters:String
				If Not importedMethod.isTypeFunction Then parameters = "struct " + receiverObjectName + " *"
				For Local parameter:TCompilerIrParameter = EachIn importedMethod.parameters
					If parameters.length Then parameters :+ ", "
					parameters :+ CParameterType(parameter, importedMethod.source)
				Next
				If Not parameters.length Then parameters = "void"
				result.Append("    " + CFunctionPointerDeclaration(importedMethod.returnType, importedMethod.callableReturnType, importedMethod.callableReturnParameters, importedMethod.slotName, parameters, importedMethod.source, importedMethod.callingConvention, importedMethod.callableReturnCallingConvention) + ";~n")
				' A non-generic source Type can inherit this slot and place the closed
				' generic implementation directly in its ordinary runtime class table.
				' Publish the implementation before those class initializers, not only
				' for Type functions that ordinary call lowering invokes directly.
				If importedMethod.abiName.length Then methodPrototypes :+ "extern " + CFunctionDeclaration(importedMethod.returnType, importedMethod.callableReturnType, importedMethod.callableReturnParameters, importedMethod.abiName, parameters, importedMethod.source, importedMethod.callingConvention, importedMethod.callableReturnCallingConvention) + ";~n"
			Next
			result.Append("};~n")
			result.Append(methodPrototypes)
			result.Append("struct " + objectName + " {~n    struct " + className + " *clas;~n")
			For Local importedField:TCompilerIrImportedField = EachIn importedClass.fields
				If importedField.isStaticArray Then
					result.Append("    " + CType(importedField.staticArrayElementType, importedField.source) + " " + importedField.abiName + "[" + importedField.staticArrayLength + "];~n")
				Else If importedField.callableReturnType.length Then
					result.Append("    " + CCallableFieldDeclaration(importedField.callableReturnType, importedField.callableParameters, importedField.abiName, importedField.source, importedField.callableCallingConvention) + ";~n")
				Else
					result.Append("    " + CType(importedField.semanticType, importedField.source) + " " + importedField.abiName + ";~n")
				End If
			Next
			result.Append("};~n")
			result.Append("extern struct " + className + " " + importedClass.abiName + ";~n")
			If importedClass.registerFunctionName.length Then result.Append("void " + importedClass.registerFunctionName + "(void);~n")
			For Local constructor:TCompilerIrImportedConstructor = EachIn importedClass.constructors
				If constructor.objectNewAbiName.length Then
					result.Append("struct " + objectName + " *" + constructor.objectNewAbiName + "(BBClass *clas")
					For Local parameter:TCompilerIrParameter = EachIn constructor.parameters
						result.Append(", " + CParameterType(parameter, constructor.source))
					Next
					result.Append(");~n")
				End If
			Next
			result.Append("#endif~n")
		Next
		If result.Length() > startLength Then result.Append("~n")
	End Method

	Method AppendRuntimeInterfaces(irModule:TCompilerIrModule, headerOnly:Int, result:TStringBuilder)
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If irInterface.isExternInterface And Not irInterface.isImported And irInterface.abiName.length Then result.Append("typedef struct " + irInterface.abiName + " " + irInterface.abiName + ";~n")
		Next
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If Not irInterface.isExternInterface Then Continue
			If irInterface.isImported Then Continue
			result.Append("struct " + irInterface.abiName + "Vtbl {~n")
			For Local interfaceMethod:TCompilerIrInterfaceMethod = EachIn irInterface.methods
				Local declaringInterface:TCompilerIrInterface = InterfaceById(interfaceMethod.declaringInterfaceId)
				Local parameters:String = NativeInterfaceReceiverType(declaringInterface)
				For Local parameter:TCompilerIrParameter = EachIn interfaceMethod.parameters
					parameters :+ ", " + CParameterType(parameter, interfaceMethod.source)
				Next
				result.Append("    " + CFunctionPointerDeclaration(interfaceMethod.returnType, interfaceMethod.callableReturnType, interfaceMethod.callableReturnParameters, InterfaceMethodName(interfaceMethod), parameters, interfaceMethod.source, interfaceMethod.callingConvention, interfaceMethod.callableReturnCallingConvention) + ";~n")
			Next
			result.Append("};~nstruct " + irInterface.abiName + " {~n    struct " + irInterface.abiName + "Vtbl *vtbl;~n};~n~n")
		Next
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If irInterface.isExternInterface Then Continue
			If irInterface.isImported Then
				If irInterface.methodsAbiName.length And Not irInterface.methodsLayoutOwnedExternally Then
					Local declarationGuard:String = GenericDeclarationGuard("interface", irInterface.methodsAbiName)
					result.Append("#ifndef " + declarationGuard + "~n#define " + declarationGuard + "~n")
					If irInterface.abiName.length Then result.Append("struct " + irInterface.abiName + "_obj;~n")
					result.Append("struct " + InterfaceMethodsName(irInterface.interfaceId) + " {~n")
					If Not irInterface.methods.length Then result.Append("    void *reserved;~n")
					For Local interfaceMethod:TCompilerIrInterfaceMethod = EachIn irInterface.methods
						Local parameters:String = InterfaceReceiverType(irInterface)
						For Local parameter:TCompilerIrParameter = EachIn interfaceMethod.parameters
							parameters :+ ", " + CParameterType(parameter, interfaceMethod.source)
						Next
						result.Append("    " + CFunctionPointerDeclaration(interfaceMethod.returnType, interfaceMethod.callableReturnType, interfaceMethod.callableReturnParameters, InterfaceMethodName(interfaceMethod), parameters, interfaceMethod.source, interfaceMethod.callingConvention, interfaceMethod.callableReturnCallingConvention) + ";~n")
					Next
					result.Append("};~n")
					result.Append("#endif~n")
				End If
				' Canonical generic Interface descriptors are owned by their
				' specialization units, not by the ordinary defining-module
				' runtime header. Consumers therefore always need the descriptor
				' declaration even when that module's header is authoritative.
				If Not headerOnly And ((irInterface.methodsAbiName.length And Not irInterface.methodsLayoutOwnedExternally) Or Not HeaderOwnsExternal(irModule, irInterface.originModule, irInterface.source.path)) Then result.Append("extern const struct BBInterface " + InterfaceDescriptorName(irInterface.interfaceId) + ";~n~n")
				Continue
			End If
			If irInterface.abiName.length Then result.Append("struct " + irInterface.abiName + "_obj;~n")
			result.Append("struct " + InterfaceMethodsName(irInterface.interfaceId) + " {~n")
			If Not irInterface.methods.length Then result.Append("    void *reserved;~n")
			For Local interfaceMethod:TCompilerIrInterfaceMethod = EachIn irInterface.methods
				Local parameters:String = InterfaceReceiverType(irInterface)
				For Local parameter:TCompilerIrParameter = EachIn interfaceMethod.parameters
					parameters :+ ", " + CParameterType(parameter, interfaceMethod.source)
				Next
				result.Append("    " + CFunctionPointerDeclaration(interfaceMethod.returnType, interfaceMethod.callableReturnType, interfaceMethod.callableReturnParameters, InterfaceMethodName(interfaceMethod), parameters, interfaceMethod.source, interfaceMethod.callingConvention, interfaceMethod.callableReturnCallingConvention) + ";~n")
			Next
			result.Append("};~n")
			result.Append("extern const struct BBInterface " + InterfaceDescriptorName(irInterface.interfaceId) + ";~n")
			If Not headerOnly And Not irInterface.isImported Then
				result.Append("static struct {~n")
				result.Append("    unsigned int kind;~n")
				result.Append("    const char *name;~n")
				result.Append("    BBDebugDecl decls[1];~n")
				result.Append("} " + InterfaceDebugScopeName(irInterface.interfaceId) + " = {~n")
				result.Append("    BBDEBUGSCOPE_USERTYPE, " + CQuoted(irInterface.name) + ",~n")
				result.Append("    {{ BBDEBUGDECL_END, 0, 0, .var_address = 0, .reflection_wrapper = 0 }}~n")
				result.Append("};~n")
				result.Append("static BBClass " + InterfaceClassName(irInterface.interfaceId) + " = {~n")
				result.Append("    .super = &bbObjectClass, .free = bbObjectFree, .debug_scope = (BBDebugScope *)&" + InterfaceDebugScopeName(irInterface.interfaceId) + ", .instance_size = sizeof(BBObject),~n")
				result.Append("    .ctor = bbObjectCtor, .dtor = bbObjectDtor, .ToString = bbObjectToString, .Compare = bbObjectCompare,~n")
				result.Append("    .SendMessage = bbObjectSendMessage, .HashCode = bbObjectHashCode, .Equals = bbObjectEquals, .fields_offset = sizeof(void *)~n};~n")
				result.Append("const struct BBInterface " + InterfaceDescriptorName(irInterface.interfaceId) + " = { &" + InterfaceClassName(irInterface.interfaceId) + ", " + CQuoted(irInterface.name) + " };~n")
			End If
			result.Append("~n")
		Next
	End Method

	Method EmitRuntimeHeaderModule:String(irModule:TCompilerIrModule)
		If Not irModule Or Not irModule.initializationPlan Then
			AddDiagnostic("BMXC2041", "Runtime header emission requires an initialization plan", Null)
			Return ""
		End If
		PrepareNames(irModule, False)
		Local plan:TCompilerIrInitializationPlan = irModule.initializationPlan
		Local guardName:String = "BCC2_" + SafeIdentifier(irModule.path + "." + irModule.buildMode + "." + irModule.targetPlatform + "." + irModule.targetArchitecture + ".h").ToUpper()
		Local result:TStringBuilder = New TStringBuilder(16384)
		result.Append("#ifndef " + guardName + "~n#define " + guardName + "~n~n")
		result.Append("#include <brl.mod/blitz.mod/blitz.h>~n")
		For Local nativeHeader:String = EachIn irModule.nativeHeaders
			result.Append("#include ~q" + nativeHeader + "~q~n")
		Next
		For Local dependency:TCompilerIrDependency = EachIn plan.dependencies
			If dependency.headerPath.length Then result.Append("#include <" + dependency.headerPath + ">~n")
		Next
		result.Append(EmitClosureRuntimeDeclaration())
		result.Append("~n#ifdef __cplusplus~nextern ~qC~q {~n#endif~n~n")
		result.Append("void " + plan.registerFunctionName + "(void);~n")
		result.Append("int " + plan.initializeFunctionName + "(void);~n")
		' An undeclared C Struct tag used in a function prototype has only
		' prototype scope. Publish all Type tags before any Struct layout,
		' helper prototype, or class slot can mention a Type declared later
		' in the BlitzMax module.
		result.Append(EmitPublishedRuntimeClassTypeForwards(irModule))
		result.Append(EmitRuntimeEnumPrototypes(irModule, True))
		result.Append(EmitStructs(irModule, True))
		result.Append(EmitGenericStructs(irModule))
		result.Append(EmitStructNewHelperPrototypes(irModule, True))
		result.Append(EmitPublishedStructArrayPrototypes(irModule))
		result.Append(EmitGenericStructPrototypes(irModule))
		' Published ordinary Types can inherit closed generic slots. Their class
		' layouts must see the generic receiver tags at file scope before a slot
		' signature mentions them.
		AppendGenericClassTypeForwards(irModule, result)
		AppendRuntimeClasses(irModule, True, result)
		AppendGenericClassForwards(irModule, result, False)
		AppendRuntimeInterfaces(irModule, True, result)
		result.Append(EmitExternalPrototypes(irModule, True))
		result.Append(EmitPublishedGlobals(irModule))
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Then Continue
			Local publishPrototype:Int = routine.visibility = VISIBILITY_PUBLIC
			If routine.ownerClassId.length Then
				Local ownerClass:TCompilerIrClass = ClassById(routine.ownerClassId)
				publishPrototype = ownerClass And ownerClass.isPublished
			End If
			If routine.ownerStructId.length Then
				Local ownerStruct:TCompilerIrStruct = StructById(routine.ownerStructId)
				publishPrototype = ownerStruct And ownerStruct.isPublished
			End If
			If Not publishPrototype Then Continue
			result.Append(EmitPrototype(routine) + ";~n")
			If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR And Not routine.ownerStructId.length And routine.parameters.length Then result.Append(EmitObjectNewHelperPrototype(routine) + ";~n")
		Next
		result.Append(EmitLegacyRoutineAliasPrototypes(irModule, True))
		result.Append("~n#ifdef __cplusplus~n}~n#endif~n~n#endif~n")
		Return result.ToString()
	End Method

	Method EmitRuntimeRegistration:String(irModule:TCompilerIrModule, plan:TCompilerIrInitializationPlan)
		Local guardName:String = SafeIdentifier(plan.unitName + "_reg_inited")
		Local result:String = "static int " + guardName + " = 0;~n"
		result :+ "void " + plan.registerFunctionName + "(void) {~n"
		result :+ "    if (!" + guardName + ") {~n"
		result :+ "        " + guardName + " = 1;~n"
		For Local stepValue:TCompilerIrInitializationStep = EachIn plan.registrationSteps
			If stepValue.kind = IR_INIT_REGISTER_DEPENDENCY And stepValue.dependency Then result :+ "        " + stepValue.dependency.registerFunctionName + "();~n"
		Next
		For Local registration:TCompilerIrGenericImplementationRegistration = EachIn plan.genericImplementationRegistrations
			result :+ "        " + registration.functionName + "();~n"
		Next
		For Local registration:TCompilerIrGenericCoverageRegistration = EachIn plan.genericCoverageRegistrations
			result :+ "        " + registration.functionName + "();~n"
		Next
		For Local debugSource:TCompilerIrDebugSource = EachIn irModule.debugSources
			result :+ "        bbRegisterSource(" + debugSource.sourceId + "ULL, " + CQuoted(debugSource.path) + ");~n"
		Next
		If irModule.coverageFiles.length Then result :+ "        bbCoverageRegisterFile(bmx_coverage_files);~n"
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			result :+ "        bbObjectRegisterType((BBCLASS)&" + DescriptorName(irClass.classId) + ");~n"
			Local reflectedVariables:TCompilerIrVariableDeclaration[] = ReflectedClassVariables(irClass)
			For Local variableIndex:Int = 0 Until reflectedVariables.length
				Local reflectedVariable:TCompilerIrVariableDeclaration = reflectedVariables[variableIndex]
				If reflectedVariable.isThreadedGlobal Then
					result :+ "        bmx_type_scope_" + SafeIdentifier(irClass.classId) + ".decls[" + variableIndex + "].var_address = (void *)&" + String(globalNames.ValueForKey(reflectedVariable.symbolId)) + ";~n"
				End If
			Next
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			result :+ "        bbObjectRegisterStruct((BBDebugScope *)&" + StructDebugScopeName(irStruct) + ");~n"
		Next
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If importedClass.isGenericSpecialization And importedClass.registerFunctionName.length Then result :+ "        " + importedClass.registerFunctionName + "();~n"
		Next
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If importedStruct.isGenericSpecialization And importedStruct.registerFunctionName.length Then result :+ "        " + importedStruct.registerFunctionName + "();~n"
		Next
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If irInterface.isImported Or irInterface.isExternInterface Then Continue
			result :+ "        bbObjectRegisterInterface((BBInterface *)&" + InterfaceDescriptorName(irInterface.interfaceId) + ");~n"
		Next
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			If irEnum.isImported Or Not irEnum.runtimeDescriptor Then Continue
			Local enumDescriptor:TCompilerIrEnumRuntimeDescriptor = irEnum.runtimeDescriptor
			result :+ "        " + enumDescriptor.descriptorAbiName + " = (BBEnum *)&" + enumDescriptor.descriptorStorageAbiName + ";~n"
			result :+ "        bbEnumRegister(" + enumDescriptor.descriptorAbiName + ", (BBDebugScope *)&" + enumDescriptor.debugScopeAbiName + ");~n"
		Next
		result :+ "    }~n"
		Return result + "}~n"
	End Method

	Method EmitRuntimeInitialization:String(routine:TCompilerIrFunction, plan:TCompilerIrInitializationPlan)
		localNames = New TMap
		ResetTemporaries()
		currentIsMain = True
		currentDebugInstrumentation = routine.debugInstrumentation
		currentCoverageInstrumentation = routine.coverageInstrumentation
		currentDebugScope = routine.debugScope
		currentReturnType = routine.returnType
		currentCallableReturnType = routine.callableReturnType
		currentCallableReturnParameters = routine.callableReturnParameters
		currentCallableReturnCallingConvention = routine.callableReturnCallingConvention
		nextCleanupReturnId = 0
		nextTryFinallyId = 0
		debugStatementIndex = 0
		ResetDebugControlFlow()
		Local guardName:String = SafeIdentifier(plan.unitName + "_inited")
		Local body:String = "        " + guardName + " = 1;~n"
		If plan.unitKind = IR_UNIT_APPLICATION Then body :+ "        " + plan.registerFunctionName + "();~n"
		For Local stepValue:TCompilerIrInitializationStep = EachIn plan.initializationSteps
			Select stepValue.kind
				Case IR_INIT_INITIALIZE_STRINGS
					body :+ "        bb_init_strings();~n"
					For Local resource:TCompilerIrIncbin = EachIn currentModule.incbins
						body :+ "        bbIncbinAdd((BBString*)" + RuntimeStringPointer(resource.stringLiteralId) + ", &" + resource.dataSymbol + ", " + resource.sizeSymbol + ");~n"
					Next
				Case IR_INIT_ADD_GC_ROOTS
					body :+ EmitRuntimeGcRoots(routine, "        ")
				Case IR_INIT_INITIALIZE_DEPENDENCY
					If stepValue.dependency Then body :+ "        " + stepValue.dependency.initializeFunctionName + "();~n"
				Case IR_INIT_RUN_ATSTART
					body :+ "        bbRunAtstart();~n"
				Case IR_INIT_EXECUTE_GLOBAL_BODY
					body :+ EmitDebugLocalDeclarations(routine.body, "        ")
					If DebugEnabled() Then
						debugScopeDepth = 1
						body :+ EmitDebugScope(currentDebugScope, "        ")
					End If
					body :+ EmitCoverageFunctionEntry(routine, "        ")
					body :+ EmitRuntimeGlobalBody(routine, "        ")
					body :+ EmitGdbGeneratedLineReset("        ")
					If DebugEnabled() Then
						body :+ "        bbOnDebugLeaveScope();~n"
						debugScopeDepth = 0
					End If
			End Select
		Next
		Local result:String = "static int " + guardName + " = 0;~n"
		result :+ "int " + plan.initializeFunctionName + "(void) {~n"
		result :+ "    if (!" + guardName + ") {~n"
		result :+ EmitTemporaryDeclarations("        ")
		result :+ body
		result :+ "    }~n"
		result :+ "    return 0;~n"
		Return result + "}~n"
	End Method

	Method EmitRuntimeGcRoots:String(routine:TCompilerIrFunction, indent:String)
		Local result:String
		If Not currentModule Then Return result
		For Local variable:TCompilerIrVariableDeclaration = EachIn allVariables
			If Not variable Or variable.storage <> "global" Then Continue
			Local name:String = SymbolName(variable.symbolId, variable.name)
			result :+ indent + "GC_add_roots(&" + name + ", &" + name + " + 1);~n"
		Next
		Return result
	End Method

	Method EmitRuntimeGlobalBody:String(routine:TCompilerIrFunction, indent:String)
		Local result:String
		If Not routine Or Not routine.body Then Return result
		For Local statement:TCompilerIrStatement = EachIn routine.body.statements
			result :+ EmitStatement(statement, indent)
		Next
		Return result
	End Method

	Method PrepareNames(irModule:TCompilerIrModule, validateInstrumentation:Int = True)
		currentModule = irModule
		allVariables = New TCompilerIrVariableDeclaration[0]
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine And routine.body Then CollectVariables(routine.body)
		Next
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			enumTypes.Insert(irEnum.semanticType.ToLower(), irEnum)
			If irEnum.abiName.length Then enumTypes.Insert(("@runtime-enum:" + irEnum.abiName).ToLower(), irEnum)
			enumsById.Insert(irEnum.enumId, irEnum)
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			Local suffix:String = SafeIdentifier(irStruct.structId + "_" + irStruct.name)
			Local structName:String = "bmx_struct_" + suffix
			If (irStruct.isPublished Or irStruct.hasStableLocalAbi) And irStruct.abiName.length Then structName = irStruct.abiName
			structTypes.Insert(irStruct.semanticType.ToLower(), irStruct)
			If irStruct.abiName.length Then structTypes.Insert(("@runtime-struct:" + irStruct.abiName).ToLower(), irStruct)
			structsById.Insert(irStruct.structId, irStruct)
			structNames.Insert(irStruct.structId, structName)
			For Local irField:TCompilerIrStructField = EachIn irStruct.fields
				Local fieldName:String = irField.abiName
				If Not fieldName.length Then fieldName = "bmx_field_" + SafeIdentifier(irField.fieldId + "_" + irField.name)
				structFieldNames.Insert(irStruct.structId + "." + irField.fieldId, fieldName)
			Next
		Next
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			importedStructTypes.Insert(importedStruct.semanticType.ToLower(), importedStruct)
			If importedStruct.abiName.length Then importedStructTypes.Insert(("@runtime-struct:" + importedStruct.abiName).ToLower(), importedStruct)
			importedStructsById.Insert(importedStruct.importedStructId, importedStruct)
			For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
				importedFieldsById.Insert(importedField.fieldId, importedField)
			Next
			For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
				importedStructRoutinesById.Insert(routine.routineId, routine)
				Local routineName:String = routine.implementationAbiName
				If Not routineName.length Then routineName = routine.abiName
				functionNames.Insert(routine.routineId, routineName)
			Next
		Next
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			interfaceTypes.Insert(irInterface.semanticType.ToLower(), irInterface)
			If irInterface.abiName.length Then interfaceTypes.Insert(("@runtime-interface:" + irInterface.abiName).ToLower(), irInterface)
			interfacesById.Insert(irInterface.interfaceId, irInterface)
		Next
		For Local opaqueInterfaceType:String = EachIn irModule.opaqueInterfaceTypes
			opaqueInterfaceTypes.Insert(opaqueInterfaceType.ToLower(), opaqueInterfaceType)
		Next
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			importedClassTypes.Insert(importedClass.semanticType.ToLower(), importedClass)
			If importedClass.abiName.length Then importedClassTypes.Insert(("@runtime-class:" + importedClass.abiName).ToLower(), importedClass)
			importedClassesById.Insert(importedClass.importedClassId, importedClass)
			For Local importedField:TCompilerIrImportedField = EachIn importedClass.fields
				importedFieldsById.Insert(importedField.fieldId, importedField)
			Next
			For Local importedMethod:TCompilerIrImportedMethod = EachIn importedClass.methods
				importedMethodsById.Insert(importedMethod.methodId, importedMethod)
				Local methodName:String = importedMethod.implementationAbiName
				If Not methodName.length Then methodName = importedMethod.abiName
				functionNames.Insert(importedMethod.methodId, methodName)
			Next
			For Local constructor:TCompilerIrImportedConstructor = EachIn importedClass.constructors
				importedConstructorsById.Insert(constructor.constructorId, constructor)
			Next
		Next
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			Local suffix:String = SafeIdentifier(irClass.classId + "_" + irClass.name)
			classTypes.Insert(irClass.semanticType.ToLower(), irClass)
			If irClass.abiName.length Then classTypes.Insert(("@runtime-class:" + irClass.abiName).ToLower(), irClass)
			classesById.Insert(irClass.classId, irClass)
			If (irClass.isPublished Or irClass.hasStableLocalAbi) And irClass.abiName.length Then
				classNames.Insert(irClass.classId, "BBClass_" + SafeIdentifier(irClass.abiName))
				objectNames.Insert(irClass.classId, irClass.abiName + "_obj")
				descriptorNames.Insert(irClass.classId, irClass.abiName)
			Else
				classNames.Insert(irClass.classId, "BCC2_BBClass_" + suffix)
				objectNames.Insert(irClass.classId, "bmx_" + suffix + "_obj")
				descriptorNames.Insert(irClass.classId, "bmx_class_" + suffix)
			End If
			constructorNames.Insert(irClass.classId, "bmx_ctor_" + suffix)
			Local usedFieldNames:TMap = New TMap
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				Local fieldKey:String = irField.declaringClassId + "." + irField.fieldId
				Local fieldName:String = String(fieldNames.ValueForKey(fieldKey))
				If Not fieldName.length Then
					fieldName = irField.abiName
					If Not fieldName.length Then
						fieldName = "bmx_field_" + SafeIdentifier(irField.fieldId + "_" + irField.name)
						' Field ids are local to their declaring Type.  A legal
						' redeclaration such as Field prop in both a base and a
						' derived Type therefore has the same short fallback name.
						' Keep established short names where they are unambiguous,
						' but owner-qualify the shadowing field in the flattened C
						' object layout.
						If usedFieldNames.Contains(fieldName.ToLower()) Then
							fieldName = "bmx_field_" + SafeIdentifier(irField.declaringClassId + "_" + irField.fieldId + "_" + irField.name)
						End If
					End If
					fieldNames.Insert(fieldKey, fieldName)
				End If
				usedFieldNames.Insert(fieldName.ToLower(), irField)
			Next
		Next
		For Local stringLiteral:TCompilerIrStringLiteral = EachIn irModule.stringLiterals
			If EmbeddedStringTypes() And stringLiteral.value.length Then
				stringNames.Insert(stringLiteral.literalId, "&bmx_pico_string_" + SafeIdentifier(stringLiteral.literalId))
			Else If EmbeddedStringTypes() Then
				stringNames.Insert(stringLiteral.literalId, "&bmx_pico_empty_string")
			Else If stringLiteral.value.length Then
				stringNames.Insert(stringLiteral.literalId, "(BBString*)&bmx_string_" + SafeIdentifier(stringLiteral.literalId))
			Else
				stringNames.Insert(stringLiteral.literalId, "&bbEmptyString")
			End If
		Next
		For Local externalFunction:TCompilerIrExternalFunction = EachIn irModule.externalFunctions
			Local functionName:String = externalFunction.abiName
			If externalFunction.implementationAbiName.length Then functionName = externalFunction.implementationAbiName
			Local picoStringFunction:String = PicoStringRuntimeFunctionName(externalFunction)
			If picoStringFunction.length Then functionName = picoStringFunction
			Local picoScalarIntrinsic:String = PicoScalarIntrinsicFunctionName(externalFunction)
			If picoScalarIntrinsic.length Then functionName = picoScalarIntrinsic
			If NeedsNativeStringWrapper(externalFunction) Then functionName = NativeStringWrapperName(externalFunction)
			functionNames.Insert(externalFunction.functionId, functionName)
			externalFunctionsById.Insert(externalFunction.functionId, externalFunction)
		Next
		For Local externalGlobal:TCompilerIrExternalGlobal = EachIn irModule.externalGlobals
			globalNames.Insert(externalGlobal.symbolId, externalGlobal.abiName)
			externalGlobalsById.Insert(externalGlobal.symbolId, externalGlobal)
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If Not routine.isGlobalEntry Then
				Local abiName:String = routine.implementationAbiName
				If Not abiName.length Then abiName = routine.abiName
				If Not abiName.length Then abiName = "bmx_" + SafeIdentifier(routine.functionId + "_" + routine.name)
				functionNames.Insert(routine.functionId, abiName)
			End If
			If validateInstrumentation And routine.debugInstrumentation And Not runtimeTypes Then AddDiagnostic("BMXC2030", "Debug instrumentation requires the BlitzMax runtime C backend", routine.source)
			If validateInstrumentation And routine.coverageInstrumentation And Not runtimeTypes Then AddDiagnostic("BMXC2031", "Coverage instrumentation requires the BlitzMax runtime C backend", routine.source)
		Next
		For Local variable:TCompilerIrVariableDeclaration = EachIn allVariables
			If variable And (variable.storage = "global" Or variable.storage = "constant") Then
				Local abiName:String = variable.abiName
				If Not abiName.length Then abiName = "bmx_global_" + SafeIdentifier(variable.symbolId + "_" + variable.name)
				globalNames.Insert(variable.symbolId, abiName)
			End If
		Next
	End Method

	Method AppendEmbeddedStringLiterals(irModule:TCompilerIrModule, result:TStringBuilder)
		If Not EmbeddedStringTypes() Then Return
		Local emitted:Int
		For Local literal:TCompilerIrStringLiteral = EachIn irModule.stringLiterals
			If Not literal.value.length Then Continue
			emitted = True
			Local suffix:String = SafeIdentifier(literal.literalId)
			result.Append("static const uint16_t bmx_pico_string_data_" + suffix + "[] = {")
			For Local index:Int = 0 Until literal.value.length
				If index Then result.Append(",")
				result.Append(String.FromInt(literal.value[index]))
			Next
			result.Append("};~n")
			result.Append("static const BMXPicoString bmx_pico_string_" + suffix + " = { " + literal.value.length + ", bmx_pico_string_data_" + suffix + " };~n")
		Next
		If emitted Then result.Append("~n")
	End Method

	Method AppendPicoEnums(irModule:TCompilerIrModule, result:TStringBuilder)
		If Not EmbeddedStringTypes() Then Return
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			If irEnum.isImported Then Continue
			Local count:Int = irEnum.values.length
			Local storageCount:Int = count
			If storageCount < 1 Then storageCount = 1
			Local descriptorName:String = PicoEnumDescriptorName(irEnum)
			result.Append("static const uint64_t " + descriptorName + "_values[" + storageCount + "] = {")
			If Not count Then
				result.Append("0")
			Else
				For Local index:Int = 0 Until count
					If index Then result.Append(",")
					result.Append("(uint64_t)(int64_t)(" + String(irEnum.values[index].integerValue) + ")")
				Next
			End If
			result.Append("};~n")
			result.Append("static const BMXPicoString *const " + descriptorName + "_names[" + storageCount + "] = {")
			If Not count Then
				result.Append("&bmx_pico_empty_string")
			Else
				For Local index:Int = 0 Until count
					If index Then result.Append(",")
					Local namePointer:String = String(stringNames.ValueForKey(irEnum.values[index].nameStringLiteralId))
					If Not namePointer.length Then namePointer = "&bmx_pico_empty_string"
					result.Append(namePointer)
				Next
			End If
			result.Append("};~n")
			Local flags:String = "0"
			If irEnum.isFlags Then flags = "BMX_PICO_ENUM_FLAG_FLAGS"
			result.Append("static const BMXPicoEnumDescriptor " + descriptorName + " = { " + CQuoted(irEnum.name) + ", " + descriptorName + "_values, " + descriptorName + "_names, " + count + ", (uint16_t)sizeof(" + CType(irEnum.underlyingType, irEnum.source) + "), " + flags + " };~n~n")
		Next
	End Method

	Method CollectVariables(block:TCompilerIrBlock)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
			If variable Then
				allVariables :+ [variable]
				Continue
			End If
			Local conditional:TCompilerIrIf = TCompilerIrIf(statement)
			If conditional Then
				CollectVariables(conditional.thenBody)
				For Local clause:TCompilerIrConditionalClause = EachIn conditional.elseIfClauses
					CollectVariables(clause.body)
				Next
				CollectVariables(conditional.elseBody)
				Continue
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					CollectVariables(selectedCase.body)
				Next
				CollectVariables(selected.defaultBody)
				Continue
			End If
			Local attempted:TCompilerIrTry = TCompilerIrTry(statement)
			If attempted Then
				CollectVariables(attempted.body)
				For Local caught:TCompilerIrCatch = EachIn attempted.catches
					CollectVariables(caught.body)
				Next
				CollectVariables(attempted.finallyBody)
				Continue
			End If
			Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
			If usingStatement Then
				For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
					If resource.variable Then allVariables :+ [resource.variable]
				Next
				CollectVariables(usingStatement.body)
				Continue
			End If
			Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
			If whileStatement Then CollectVariables(whileStatement.body); Continue
			Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
			If repeatStatement Then CollectVariables(repeatStatement.body); Continue
			Local rangeLoop:TCompilerIrForRange = TCompilerIrForRange(statement)
			If rangeLoop Then CollectVariables(rangeLoop.body); Continue
			Local arrayLoop:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
			If arrayLoop Then CollectVariables(arrayLoop.body); Continue
			Local stringLoop:TCompilerIrForEachString = TCompilerIrForEachString(statement)
			If stringLoop Then CollectVariables(stringLoop.body); Continue
			Local staticArrayLoop:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
			If staticArrayLoop Then CollectVariables(staticArrayLoop.body); Continue
			Local objectLoop:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
			If objectLoop Then
				If objectLoop.iteratorCleanup And objectLoop.iteratorCleanup.variable Then allVariables :+ [objectLoop.iteratorCleanup.variable]
				CollectVariables(objectLoop.body)
			End If
		Next
	End Method

	Method CountGdbLocalName(sourceName:String)
		If Not sourceName.length Then Return
		Local key:String = sourceName.ToLower()
		Local count:Int = Int(String(gdbLocalNameCounts.ValueForKey(key)))
		gdbLocalNameCounts.Insert(key, String(count + 1))
	End Method

	Method CollectGdbLocalNames(block:TCompilerIrBlock)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
			If variable Then CountGdbLocalName(variable.name); Continue
			Local conditional:TCompilerIrIf = TCompilerIrIf(statement)
			If conditional Then
				CollectGdbLocalNames(conditional.thenBody)
				For Local clause:TCompilerIrConditionalClause = EachIn conditional.elseIfClauses
					CollectGdbLocalNames(clause.body)
				Next
				CollectGdbLocalNames(conditional.elseBody)
				Continue
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					CollectGdbLocalNames(selectedCase.body)
				Next
				CollectGdbLocalNames(selected.defaultBody)
				Continue
			End If
			Local attempted:TCompilerIrTry = TCompilerIrTry(statement)
			If attempted Then
				CollectGdbLocalNames(attempted.body)
				For Local caught:TCompilerIrCatch = EachIn attempted.catches
					CountGdbLocalName(caught.parameterName)
					CollectGdbLocalNames(caught.body)
				Next
				CollectGdbLocalNames(attempted.finallyBody)
				Continue
			End If
			Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
			If usingStatement Then
				For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
					If resource.variable Then CountGdbLocalName(resource.variable.name)
				Next
				CollectGdbLocalNames(usingStatement.body)
				Continue
			End If
			Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
			If whileStatement Then CollectGdbLocalNames(whileStatement.body); Continue
			Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
			If repeatStatement Then CollectGdbLocalNames(repeatStatement.body); Continue
			Local rangeLoop:TCompilerIrForRange = TCompilerIrForRange(statement)
			If rangeLoop Then CountGdbLocalName(rangeLoop.variableName); CollectGdbLocalNames(rangeLoop.body); Continue
			Local arrayLoop:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
			If arrayLoop Then CountGdbLocalName(arrayLoop.variableName); CollectGdbLocalNames(arrayLoop.body); Continue
			Local stringLoop:TCompilerIrForEachString = TCompilerIrForEachString(statement)
			If stringLoop Then CountGdbLocalName(stringLoop.variableName); CollectGdbLocalNames(stringLoop.body); Continue
			Local staticArrayLoop:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
			If staticArrayLoop Then CountGdbLocalName(staticArrayLoop.variableName); CollectGdbLocalNames(staticArrayLoop.body); Continue
			Local objectLoop:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
			If objectLoop Then CountGdbLocalName(objectLoop.variableName); CollectGdbLocalNames(objectLoop.body)
		Next
	End Method

	Method PrepareGdbLocalNames(routine:TCompilerIrFunction)
		gdbLocalNameCounts = New TMap
		If Not currentModule Or Not currentModule.gdbDebug Or Not routine Then Return
		If routine.receiver Then CountGdbLocalName(routine.receiver.name)
		For Local parameter:TCompilerIrParameter = EachIn routine.parameters
			CountGdbLocalName(parameter.name)
		Next
		CollectGdbLocalNames(routine.body)
	End Method

	Method EmitStructs:String(irModule:TCompilerIrModule, publishedOnly:Int = False)
		Local result:String
		Local emitted:TMap = New TMap
		Local visiting:TMap = New TMap
		Local emittedGeneric:TMap = New TMap
		Local visitingGeneric:TMap = New TMap
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If publishedOnly And Not irStruct.isPublished And Not irStruct.hasStableLocalAbi Then Continue
			result :+ EmitStructLayout(irStruct, emitted, visiting, emittedGeneric, visitingGeneric)
		Next
		Return result
	End Method

	Method EmitStructLayout:String(irStruct:TCompilerIrStruct, emitted:TMap, visiting:TMap, emittedGeneric:TMap, visitingGeneric:TMap)
		If Not irStruct Or emitted.Contains(irStruct.structId) Then Return ""
		If EmbeddedObjectTypes() And Not PicoPlainStructSupported(irStruct) Then
			AddDiagnostic("BMXC2091", "Struct '" + irStruct.name + "' contains callable, imported-managed, or otherwise unsupported Pico fields", irStruct.source)
		End If
		If visiting.Contains(irStruct.structId) Then
			AddDiagnostic("BMXC2067", "Struct layout cycle reaches '" + irStruct.name + "'", irStruct.source)
			Return ""
		End If
		visiting.Insert(irStruct.structId, irStruct.structId)
		Local result:String
		For Local irField:TCompilerIrStructField = EachIn irStruct.fields
			Local nestedId:String = irField.structId
			If irField.staticArrayStructId.length Then nestedId = irField.staticArrayStructId
			If nestedId.length Then result :+ EmitStructLayout(StructById(nestedId), emitted, visiting, emittedGeneric, visitingGeneric)
			Local nestedImportedId:String = irField.importedStructId
			If irField.staticArrayImportedStructId.length Then nestedImportedId = irField.staticArrayImportedStructId
			If nestedImportedId.length Then
				Local dependency:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(nestedImportedId))
				' Ordinary imported Struct layouts arrive through their module header.
				' Canonical generic Structs are application-owned declarations and
				' must precede any local Struct which embeds them by value.
				If dependency And dependency.isGenericSpecialization Then result :+ EmitImportedStructLayout(dependency, emittedGeneric, visitingGeneric)
			End If
		Next
		result :+ "struct " + StructName(irStruct.structId) + " {~n"
		If Not irStruct.fields.length Then
			result :+ "    unsigned char bmx_empty;~n"
		Else
			For Local irField:TCompilerIrStructField = EachIn irStruct.fields
				If irField.isStaticArray Then
					result :+ "    " + CType(irField.staticArrayElementType, irField.source) + " " + StructFieldName(irStruct.structId, irField.fieldId) + "[" + irField.staticArrayLength + "];~n"
				Else If irField.callableReturnType.length Then
					result :+ "    " + CCallableFieldDeclaration(irField.callableReturnType, irField.callableParameters, StructFieldName(irStruct.structId, irField.fieldId), irField.source, irField.callableCallingConvention) + ";~n"
				Else
					result :+ "    " + CType(irField.semanticType, irField.source) + " " + StructFieldName(irStruct.structId, irField.fieldId) + ";~n"
				End If
			Next
		End If
		result :+ "};~n~n"
		visiting.Remove(irStruct.structId)
		emitted.Insert(irStruct.structId, irStruct.structId)
		Return result
	End Method

	Method StructDebugScopeName:String(irStruct:TCompilerIrStruct)
		If Not irStruct Then Return "bmx_struct_scope_missing"
		Return "bmx_struct_scope_" + SafeIdentifier(irStruct.structId)
	End Method

	Method EmitRuntimeStructDebugScopes:String(irModule:TCompilerIrModule)
		If Not runtimeTypes Or Not irModule Then Return ""
		Local result:TStringBuilder = New TStringBuilder(2048)
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			Local reflectedFieldCount:Int
			For Local irField:TCompilerIrStructField = EachIn irStruct.fields
				If CanReflectStructField(irField) Then
					reflectedFieldCount :+ 1
					If irField.callableReturnType.length Then
						result.Append(EmitCallableValueReflectionWrapper(irField.callableReturnType, irField.callableParameters, irField.callableCallingConvention, StructFieldReflectionWrapperName(irStruct, irField), irField.source))
					End If
				End If
			Next
			Local reflectedRoutineCount:Int
			For Local routine:TCompilerIrFunction = EachIn irModule.functions
				If Not ReflectedStructRoutine(irStruct, routine) Then Continue
				If CanEmitReflectionWrapper(routine) Then result.Append(EmitStructReflectionWrapper(irStruct, routine))
				reflectedRoutineCount :+ 1
			Next
			Local needsImplicitConstructor:Int = Not StructHasZeroArgumentConstructor(irStruct)
			If needsImplicitConstructor Then
				result.Append(EmitImplicitStructConstructorReflectionWrapper(irStruct))
				reflectedRoutineCount :+ 1
			End If
			Local debugName:String = irStruct.name
			If irStruct.visibility = VISIBILITY_PRIVATE Then debugName :+ "'P"
			If irStruct.visibility = VISIBILITY_PROTECTED Then debugName :+ "'Q"
			result.Append("static struct { unsigned int kind; const char *name; BBDebugDecl decls[" + (reflectedFieldCount + reflectedRoutineCount + 1) + "]; } " + StructDebugScopeName(irStruct) + " = {~n")
			result.Append("    BBDEBUGSCOPE_USERSTRUCT, " + CQuoted(debugName) + ", {~n")
			For Local irField:TCompilerIrStructField = EachIn irStruct.fields
				If Not CanReflectStructField(irField) Then Continue
				Local fieldWrapperName:String = "0"
				If irField.callableReturnType.length Then fieldWrapperName = StructFieldReflectionWrapperName(irStruct, irField)
				result.Append("        { BBDEBUGDECL_FIELD, " + CQuoted(irField.name) + ", " + CQuoted(ReflectedMemberType(StructFieldDebugTypeTag(irField), irField.visibility, irField.metadata)) + ", .field_offset = offsetof(struct " + StructName(irStruct.structId) + ", " + StructFieldName(irStruct.structId, irField.fieldId) + "), .reflection_wrapper = " + fieldWrapperName + " },~n")
			Next
			For Local routine:TCompilerIrFunction = EachIn irModule.functions
				If Not ReflectedStructRoutine(irStruct, routine) Then Continue
				Local wrapperName:String = "0"
				If CanEmitReflectionWrapper(routine) Then wrapperName = StructReflectionWrapperName(routine)
				Local declarationKind:String = "BBDEBUGDECL_TYPEFUNCTION"
				If routine.isMethod Or routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then declarationKind = "BBDEBUGDECL_TYPEMETHOD"
				result.Append("        { " + declarationKind + ", " + CQuoted(routine.name) + ", " + CQuoted(ReflectedMemberType(ReflectedRoutineType(routine), routine.visibility, routine.metadata)) + ", .func_ptr = (BBFuncPtr)&" + FunctionName(routine.functionId) + ", .reflection_wrapper = " + wrapperName + " },~n")
			Next
			If needsImplicitConstructor Then
				result.Append("        { BBDEBUGDECL_TYPEMETHOD, ~qNew~q, ~q()~q, .func_ptr = (BBFuncPtr)&" + StructNewHelperName(irStruct.structId, "") + ", .reflection_wrapper = " + ImplicitStructConstructorReflectionWrapperName(irStruct) + " },~n")
			End If
			' Reflection reads a Struct's byte size from the terminal declaration.
			result.Append("        { BBDEBUGDECL_END, 0, 0, .struct_size = sizeof(struct " + StructName(irStruct.structId) + "), .reflection_wrapper = 0 }~n")
			result.Append("    }~n};~n")
		Next
		If result.Length() Then result.Append("~n")
		Return result.ToString()
	End Method

	Method ReflectedStructRoutine:Int(irStruct:TCompilerIrStruct, routine:TCompilerIrFunction)
		If Not irStruct Or Not routine Or routine.ownerStructId <> irStruct.structId Or routine.isAbstract Then Return False
		If routine.returnType.ToLower() <> "void" And RoutineReturnDebugTypeTag(routine) = "?" Then Return False
		For Local parameter:TCompilerIrParameter = EachIn routine.parameters
			If ParameterDebugTypeTag(parameter) = "?" Then Return False
		Next
		Return True
	End Method

	Method StructReflectionWrapperName:String(routine:TCompilerIrFunction)
		Return FunctionName(routine.functionId) + "_ReflectionWrapper"
	End Method

	Method StructFieldReflectionWrapperName:String(irStruct:TCompilerIrStruct, irField:TCompilerIrStructField)
		Return "bmx_struct_field_" + SafeIdentifier(irStruct.structId) + "_" + SafeIdentifier(irField.fieldId) + "_ReflectionWrapper"
	End Method

	Method ImplicitStructConstructorReflectionWrapperName:String(irStruct:TCompilerIrStruct)
		Return StructNewHelperName(irStruct.structId, "") + "_ReflectionWrapper"
	End Method

	Method EmitImplicitStructConstructorReflectionWrapper:String(irStruct:TCompilerIrStruct)
		Local receiverType:String = "struct " + StructName(irStruct.structId) + " *"
		Return "static void " + ImplicitStructConstructorReflectionWrapperName(irStruct) + "(void **buf) {~n    *" + ReflectionBufferValue(receiverType, "") + " = " + StructNewHelperName(irStruct.structId, "") + "();~n}~n"
	End Method

	Method EmitStructReflectionWrapper:String(irStruct:TCompilerIrStruct, routine:TCompilerIrFunction)
		If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then
			Local receiverType:String = "struct " + StructName(irStruct.structId) + " *"
			Local result:String = "static void " + StructReflectionWrapperName(routine) + "(void **buf) {~n"
			result :+ "    *" + ReflectionBufferValue(receiverType, "") + " = " + StructNewHelperName(irStruct.structId, routine.functionId) + "("
			Local offset:String = ReflectionBufferSlotCount(receiverType)
			For Local index:Int = 0 Until routine.parameters.length
				If index Then result :+ ", "
				Local parameter:TCompilerIrParameter = routine.parameters[index]
				Local parameterType:String = CParameterType(parameter, routine.source)
				result :+ ReflectionBufferParameterValue(parameter, routine.source, offset)
				If offset.length Then offset :+ " + "
				offset :+ ReflectionBufferSlotCount(parameterType)
			Next
			Return result + ");~n}~n"
		End If
		Local result:String = "static void " + StructReflectionWrapperName(routine) + "(void **buf) {~n"
		Local offset:String
		Local call:String
		If routine.callableReturnType.length Then
			Local returnValueType:String = CCallablePointerType(routine.callableReturnType, routine.callableReturnParameters, 1, routine.source, routine.callableReturnCallingConvention)
			Local returnStorageType:String = CCallablePointerType(routine.callableReturnType, routine.callableReturnParameters, 2, routine.source, routine.callableReturnCallingConvention)
			call = "    *((" + returnStorageType + ")buf) = " + FunctionName(routine.functionId) + "("
			offset = ReflectionBufferSlotCount(returnValueType)
		Else If routine.returnType.ToLower() = "void" Then
			call = "    " + FunctionName(routine.functionId) + "("
		Else
			Local returnCType:String = CType(routine.returnType, routine.source)
			call = "    *((" + returnCType + " *)buf) = " + FunctionName(routine.functionId) + "("
			offset = ReflectionBufferSlotCount(returnCType)
		End If
		If routine.isMethod Then
			Local receiverType:String = "struct " + StructName(irStruct.structId) + " *"
			call :+ ReflectionBufferValue(receiverType, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(receiverType)
		End If
		For Local index:Int = 0 Until routine.parameters.length
			If routine.isMethod Or index Then call :+ ", "
			Local parameter:TCompilerIrParameter = routine.parameters[index]
			Local parameterType:String = CParameterType(parameter, routine.source)
			call :+ ReflectionBufferParameterValue(parameter, routine.source, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(parameterType)
		Next
		Return result + call + ");~n}~n"
	End Method

	Method ReflectionBufferValue:String(cType:String, offset:String)
		Local address:String = "buf"
		If offset.length Then address = "(buf + (" + offset + "))"
		Return "*((" + cType + " *)" + address + ")"
	End Method

	Method ReflectionBufferParameterValue:String(parameter:TCompilerIrParameter, source:TCompilerSourceLocation, offset:String)
		If Not parameter.callableReturnType.length Then Return ReflectionBufferValue(CParameterType(parameter, source), offset)
		Local pointerDepth:Int = 2
		If parameter.passingMode = PARAMETER_PASS_VAR Then pointerDepth = 3
		Local storageType:String = CCallablePointerType(parameter.callableReturnType, parameter.callableParameters, pointerDepth, source, parameter.callableCallingConvention)
		Local address:String = "buf"
		If offset.length Then address = "(buf + (" + offset + "))"
		Return "*((" + storageType + ")" + address + ")"
	End Method

	Method EmitImportedStructs:String(irModule:TCompilerIrModule)
		Local result:String
		Local emitted:TMap = New TMap
		Local visiting:TMap = New TMap
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			result :+ EmitImportedStructLayout(importedStruct, emitted, visiting)
		Next
		Return result
	End Method

	Method EmitGenericStructs:String(irModule:TCompilerIrModule)
		Local result:String
		Local emitted:TMap = New TMap
		Local visiting:TMap = New TMap
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If importedStruct.isGenericSpecialization Then result :+ EmitImportedStructLayout(importedStruct, emitted, visiting)
		Next
		Return result
	End Method

	Method EmitImportedStructLayout:String(importedStruct:TCompilerIrImportedStruct, emitted:TMap, visiting:TMap)
		If Not importedStruct Or emitted.Contains(importedStruct.importedStructId) Then Return ""
		If visiting.Contains(importedStruct.importedStructId) Then
			AddDiagnostic("BMXC2067", "Imported Struct layout cycle reaches '" + importedStruct.name + "'", importedStruct.source)
			Return ""
		End If
		visiting.Insert(importedStruct.importedStructId, importedStruct.importedStructId)
		Local result:String
		For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
			Local nestedImportedId:String = importedField.importedStructId
			If importedField.staticArrayImportedStructId.length Then nestedImportedId = importedField.staticArrayImportedStructId
			If nestedImportedId.length Then
				Local dependency:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(nestedImportedId))
				result :+ EmitImportedStructLayout(dependency, emitted, visiting)
			End If
		Next
		Local declarationGuard:String
		If importedStruct.isGenericSpecialization Then
			declarationGuard = GenericDeclarationGuard("struct", importedStruct.abiName)
			result :+ "#ifndef " + declarationGuard + "~n#define " + declarationGuard + "~n"
		End If
		result :+ "struct " + importedStruct.abiName + " {~n"
		If Not importedStruct.fields.length Then
			result :+ "    unsigned char bmx_empty;~n"
		Else
			For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
				If importedField.isStaticArray Then
					result :+ "    " + CType(importedField.staticArrayElementType, importedField.source) + " " + importedField.abiName + "[" + importedField.staticArrayLength + "];~n"
				Else If importedField.callableReturnType.length Then
					result :+ "    " + CCallableFieldDeclaration(importedField.callableReturnType, importedField.callableParameters, importedField.abiName, importedField.source, importedField.callableCallingConvention) + ";~n"
				Else
					result :+ "    " + CType(importedField.semanticType, importedField.source) + " " + importedField.abiName + ";~n"
				End If
			Next
		End If
		result :+ "};~n"
		If declarationGuard.length Then result :+ "#endif~n"
		result :+ "~n"
		visiting.Remove(importedStruct.importedStructId)
		emitted.Insert(importedStruct.importedStructId, importedStruct.importedStructId)
		Return result
	End Method

	Method GenericDeclarationGuard:String(kind:String, abiName:String)
		Return "BMX_GENERIC_" + SafeIdentifier(kind + "_" + abiName).ToUpper()
	End Method

	Method EmitImportedStructPrototypes:String(irModule:TCompilerIrModule)
		Local result:String
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If EmbeddedArrayTypes() And importedStruct.elementInitializerAbiName.length Then
				result :+ "extern void " + importedStruct.elementInitializerAbiName + "(void *bmx_value);~n"
			End If
			For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
				Local parameters:String
				If routine.isMethod Then parameters :+ "struct " + importedStruct.abiName + " *bmx_self"
				For Local index:Int = 0 Until routine.parameters.length
					If index Or routine.isMethod Then parameters :+ ", "
					parameters :+ CParameterDeclaration(routine.parameters[index], LocalName(routine.parameters[index].symbolId, routine.parameters[index].name), routine.source)
				Next
				If Not parameters.length Then parameters = "void"
				Local routineName:String = routine.abiName
				If EmbeddedObjectTypes() And routine.implementationAbiName.length Then routineName = routine.implementationAbiName
				If routineName.length Then result :+ "extern " + CFunctionDeclaration(routine.returnType, routine.callableReturnType, routine.callableReturnParameters, routineName, parameters, routine.source, routine.callingConvention, routine.callableReturnCallingConvention) + ";~n"
				If routine.isConstructor Then
					result :+ "extern struct " + importedStruct.abiName + " " + routine.objectNewAbiName + "("
					If Not routine.parameters.length Then
						result :+ "void"
					Else
						For Local index:Int = 0 Until routine.parameters.length
							If index Then result :+ ", "
							result :+ CParameterDeclaration(routine.parameters[index], LocalName(routine.parameters[index].symbolId, routine.parameters[index].name), routine.source)
						Next
					End If
					result :+ ");~n"
				End If
			Next
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitGenericStructPrototypes:String(irModule:TCompilerIrModule)
		Local filtered:TCompilerIrModule = New TCompilerIrModule
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If importedStruct.isGenericSpecialization Then
				filtered.importedStructs :+ [importedStruct]
			End If
		Next
		Local result:String = EmitImportedStructPrototypes(filtered)
		For Local importedStruct:TCompilerIrImportedStruct = EachIn filtered.importedStructs
			If importedStruct.registerFunctionName.length Then result :+ "void " + importedStruct.registerFunctionName + "(void);~n"
			If importedStruct.elementInitializerAbiName.length Then
				result :+ "void " + importedStruct.elementInitializerAbiName + "(void *bmx_value);~n"
				If Not EmbeddedArrayTypes() Then
					result :+ "BBArray *" + PublishedStructArrayNewName(importedStruct.abiName) + "(int length);~n"
					result :+ "BBArray *" + PublishedStructArraySliceName(importedStruct.abiName) + "(BBArray *inarr, int beg, int end);~n"
				End If
			End If
		Next
		If result.length And Not result.EndsWith("~n~n") Then result :+ "~n"
		Return result
	End Method

	Method EmitStructNewHelperPrototypes:String(irModule:TCompilerIrModule, publishedOnly:Int = False)
		Local result:String
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If publishedOnly And Not irStruct.isPublished And Not irStruct.hasStableLocalAbi Then Continue
			If Not irStruct.constructorFunctionIds.length And irStruct.isPublished Then result :+ "void " + StructImplicitConstructorName(irStruct) + "(struct " + StructName(irStruct.structId) + " *bmx_self);~n"
			' An explicit zero-argument New owns the default helper ABI. Otherwise
			' retain the language's implicit value-default helper, including when
			' only parameterized New overloads are declared.
			If Not StructHasZeroArgumentConstructor(irStruct) Then result :+ EmitStructNewHelperPrototype(irStruct, Null) + ";~n"
			For Local functionId:String = EachIn irStruct.constructorFunctionIds
				result :+ EmitStructNewHelperPrototype(irStruct, FunctionById(functionId)) + ";~n"
			Next
		Next
		Return result
	End Method

	Method EmitStructNewHelperPrototype:String(irStruct:TCompilerIrStruct, constructor:TCompilerIrFunction)
		Local result:String = "struct " + StructName(irStruct.structId) + " " + StructNewHelperName(irStruct.structId, ConstructorFunctionId(constructor)) + "("
		If Not constructor Or Not constructor.parameters.length Then Return result + "void)"
		For Local index:Int = 0 Until constructor.parameters.length
			If index Then result :+ ", "
			Local parameter:TCompilerIrParameter = constructor.parameters[index]
			result :+ CParameterDeclaration(parameter, LocalName(parameter.symbolId, parameter.name), constructor.source)
		Next
		Return result + ")"
	End Method

	Method EmitStructNewHelpers:String(irModule:TCompilerIrModule)
		Local result:String
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If Not irStruct.constructorFunctionIds.length And irStruct.isPublished Then result :+ "void " + StructImplicitConstructorName(irStruct) + "(struct " + StructName(irStruct.structId) + " *bmx_self) { (void)bmx_self; }~n"
			If Not StructHasZeroArgumentConstructor(irStruct) Then result :+ EmitStructNewHelper(irStruct, Null) + "~n"
			For Local functionId:String = EachIn irStruct.constructorFunctionIds
				result :+ EmitStructNewHelper(irStruct, FunctionById(functionId)) + "~n"
			Next
		Next
		Return result
	End Method

	Method StructHasZeroArgumentConstructor:Int(irStruct:TCompilerIrStruct)
		If Not irStruct Then Return False
		For Local functionId:String = EachIn irStruct.constructorFunctionIds
			Local constructor:TCompilerIrFunction = FunctionById(functionId)
			If constructor And Not constructor.parameters.length Then Return True
		Next
		Return False
	End Method

	Method EmitStructNewHelper:String(irStruct:TCompilerIrStruct, constructor:TCompilerIrFunction)
		localNames = New TMap
		ResetTemporaries()
		currentIsMain = False
		Local selfName:String = "bmx_struct_value_" + SafeIdentifier(irStruct.structId)
		' Initializer IR observes the same pointer receiver as a Struct method.
		localNames.Insert("self", "(&" + selfName + ")")
		If constructor Then
			For Local parameter:TCompilerIrParameter = EachIn constructor.parameters
				localNames.Insert(parameter.symbolId, LocalName(parameter.symbolId, parameter.name))
			Next
		End If
		Local body:String = "    struct " + StructName(irStruct.structId) + " " + selfName + " = {0};~n"
		If EmbeddedObjectTypes() And irStruct.containsManagedReferences And PicoPlainStructSupported(irStruct) Then
			body :+ "    BMXPicoRootFrame bmx_pico_struct_root_frame;~n"
			body :+ "    BMXPicoRootSlot bmx_pico_struct_root_slot = { (void *)&" + selfName + ", BMX_PICO_ROOT_STRUCT, &" + PicoStructDescriptorName(irStruct) + " };~n"
			body :+ "    bmx_pico_root_frame_enter(&bmx_pico_struct_root_frame, &bmx_pico_struct_root_slot, 1);~n"
		End If
		For Local irField:TCompilerIrStructField = EachIn irStruct.fields
			If irField.isStaticArray Then
				If irField.staticArrayStructId.length Or irField.staticArrayImportedStructId.length Then
					Local staticHelper:String = StructFieldStaticArrayDefaultHelperName(irField)
					If staticHelper.length Then
						Local staticIndex:String = "bmx_static_field_init_" + SafeIdentifier(irField.fieldId)
						body :+ "    for (" + StaticArrayIndexCType() + " " + staticIndex + " = 0; " + staticIndex + " < (" + StaticArrayIndexCType() + ")" + irField.staticArrayLength + "; " + staticIndex + " = " + staticIndex + " + 1) {~n"
						body :+ "        " + selfName + "." + StructFieldName(irStruct.structId, irField.fieldId) + "[" + staticIndex + "] = " + staticHelper + "();~n"
						body :+ "    }~n"
					Else
						AddDiagnostic("BMXC2073", "StaticArray Struct field '" + irField.name + "' has no element default construction helper", irField.source)
					End If
				Else
					Local elementDefault:String = CDefaultValue(irField.staticArrayElementType)
					If elementDefault <> "0" Then
						Local staticIndex:String = "bmx_static_field_init_" + SafeIdentifier(irField.fieldId)
						body :+ "    for (" + StaticArrayIndexCType() + " " + staticIndex + " = 0; " + staticIndex + " < (" + StaticArrayIndexCType() + ")" + irField.staticArrayLength + "; " + staticIndex + " = " + staticIndex + " + 1) {~n"
						body :+ "        " + selfName + "." + StructFieldName(irStruct.structId, irField.fieldId) + "[" + staticIndex + "] = " + elementDefault + ";~n"
						body :+ "    }~n"
					End If
				End If
			Else If irField.initializer Then
				body :+ "    " + selfName + "." + StructFieldName(irStruct.structId, irField.fieldId) + " = " + EmitExpression(irField.initializer) + ";~n"
			Else If irField.structId.length Or irField.importedStructId.length Then
				Local nestedHelper:String = NestedStructDefaultHelperName(irField)
				If nestedHelper.length Then
					body :+ "    " + selfName + "." + StructFieldName(irStruct.structId, irField.fieldId) + " = " + nestedHelper + "();~n"
				Else
					AddDiagnostic("BMXC2068", "Nested Struct field '" + irField.name + "' has no default construction helper", irField.source)
				End If
			Else If IsManagedCReferenceType(irField.semanticType) Then
				body :+ "    " + selfName + "." + StructFieldName(irStruct.structId, irField.fieldId) + " = " + CDefaultValue(irField.semanticType) + ";~n"
			End If
		Next
		If constructor Then
			body :+ "    " + FunctionName(constructor.functionId) + "(&" + selfName
			For Local parameter:TCompilerIrParameter = EachIn constructor.parameters
				body :+ ", " + SymbolName(parameter.symbolId, parameter.name)
			Next
			body :+ ");~n"
		Else If irStruct.isPublished And Not irStruct.constructorFunctionIds.length Then
			body :+ "    " + StructImplicitConstructorName(irStruct) + "(&" + selfName + ");~n"
		End If
		If EmbeddedObjectTypes() And irStruct.containsManagedReferences And PicoPlainStructSupported(irStruct) Then body :+ "    bmx_pico_root_frame_leave(&bmx_pico_struct_root_frame);~n"
		body :+ "    return " + selfName + ";~n"
		Local result:String = EmitStructNewHelperPrototype(irStruct, constructor) + " {~n"
		result :+ EmitTemporaryDeclarations("    ")
		result :+ body
		Return result + "}~n"
	End Method

	Method EmitStructArrayInitializers:String(irModule:TCompilerIrModule)
		Local result:String
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If Not irStruct.arrayInitializerRequired And (Not irStruct.isPublished Or (Not runtimeTypes And Not EmbeddedArrayTypes())) Then Continue
			Local helperName:String = StructNewHelperName(irStruct.structId, "")
			For Local functionId:String = EachIn irStruct.constructorFunctionIds
				Local constructor:TCompilerIrFunction = FunctionById(functionId)
				If constructor And Not constructor.parameters.length Then
					helperName = StructNewHelperName(irStruct.structId, functionId)
					Exit
				End If
			Next
			result :+ "static inline void " + StructArrayInitializerName(irStruct.structId, "") + "(void *bmx_value) {~n"
			result :+ "    *((struct " + StructName(irStruct.structId) + " *)bmx_value) = " + helperName + "();~n"
			result :+ "}~n"
			If irStruct.isPublished And runtimeTypes Then
				result :+ "void " + PublishedStructElementInitializerName(irStruct.abiName) + "(void *bmx_value) {~n"
				result :+ "    " + StructArrayInitializerName(irStruct.structId, "") + "(bmx_value);~n"
				result :+ "}~n"
				result :+ "BBArray *" + PublishedStructArrayNewName(irStruct.abiName) + "(int length) {~n"
				result :+ "    return bbArrayNew1DStruct(" + CQuoted("@" + irStruct.name) + ", length, sizeof(struct " + StructName(irStruct.structId) + "), " + StructArrayInitializerName(irStruct.structId, "") + ");~n"
				result :+ "}~n"
				result :+ "BBArray *" + PublishedStructArraySliceName(irStruct.abiName) + "(BBArray *inarr, int beg, int end) {~n"
				result :+ "    return bbArraySliceStruct(" + CQuoted("@" + irStruct.name) + ", inarr, beg, end, sizeof(struct " + StructName(irStruct.structId) + "), " + StructArrayInitializerName(irStruct.structId, "") + ");~n"
				result :+ "}~n"
			Else If irStruct.isPublished And EmbeddedArrayTypes() Then
				result :+ "void " + PublishedStructElementInitializerName(irStruct.abiName) + "(void *bmx_value) {~n"
				result :+ "    " + StructArrayInitializerName(irStruct.structId, "") + "(bmx_value);~n"
				result :+ "}~n"
			End If
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPublishedStructArrayPrototypes:String(irModule:TCompilerIrModule)
		Local result:String
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If irStruct.isPublished Then
				result :+ "void " + PublishedStructElementInitializerName(irStruct.abiName) + "(void *bmx_value);~n"
				result :+ "BBArray *" + PublishedStructArrayNewName(irStruct.abiName) + "(int length);~n"
				result :+ "BBArray *" + PublishedStructArraySliceName(irStruct.abiName) + "(BBArray *inarr, int beg, int end);~n"
			End If
		Next
		Return result
	End Method

	Method PublishedStructArrayNewName:String(abiName:String)
		Return "bbArrayNew1DStruct_" + abiName
	End Method

	Method PublishedStructElementInitializerName:String(abiName:String)
		Return "bbStructElementInit_" + abiName
	End Method

	Method PublishedStructArraySliceName:String(abiName:String)
		Return "bbArraySliceStruct_" + abiName
	End Method

	Method StructArrayInitializerName:String(structId:String, importedStructId:String)
		If importedStructId.length Then Return "bmx_imported_struct_array_init_" + SafeIdentifier(importedStructId)
		Return "bmx_struct_array_init_" + SafeIdentifier(structId)
	End Method

	Method NestedStructDefaultHelperName:String(irField:TCompilerIrStructField)
		If irField.structId.length Then
			Local nestedStruct:TCompilerIrStruct = StructById(irField.structId)
			If Not nestedStruct Then Return ""
			For Local functionId:String = EachIn nestedStruct.constructorFunctionIds
				Local constructor:TCompilerIrFunction = FunctionById(functionId)
				If constructor And Not constructor.parameters.length Then Return StructNewHelperName(nestedStruct.structId, constructor.functionId)
			Next
			' A Struct that only declares parameterized New overloads still has the
			' language-defined implicit value-default helper.
			Return StructNewHelperName(nestedStruct.structId, "")
		End If
		If irField.importedStructId.length Then
			Local nestedImported:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.importedStructId))
			Return ImportedStructDefaultHelperName(nestedImported)
		End If
		Return ""
	End Method

	Method StructFieldStaticArrayDefaultHelperName:String(irField:TCompilerIrStructField)
		If irField.staticArrayStructId.length Then
			Local nestedStruct:TCompilerIrStruct = StructById(irField.staticArrayStructId)
			If Not nestedStruct Then Return ""
			Local helperName:String = StructNewHelperName(nestedStruct.structId, "")
			For Local functionId:String = EachIn nestedStruct.constructorFunctionIds
				Local constructor:TCompilerIrFunction = FunctionById(functionId)
				If constructor And Not constructor.parameters.length Then
					helperName = StructNewHelperName(nestedStruct.structId, constructor.functionId)
					Exit
				End If
			Next
			Return helperName
		End If
		If irField.staticArrayImportedStructId.length Then
			Local nestedImported:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.staticArrayImportedStructId))
			Return ImportedStructDefaultHelperName(nestedImported)
		End If
		Return ""
	End Method

	Method StructDefaultHelperName:String(typeName:String)
		Local normalized:String = typeName.ToLower()
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(normalized))
		If irStruct Then
			If Not irStruct.constructorFunctionIds.length Then Return StructNewHelperName(irStruct.structId, "")
			For Local functionId:String = EachIn irStruct.constructorFunctionIds
				Local constructor:TCompilerIrFunction = FunctionById(functionId)
				If constructor And Not constructor.parameters.length Then Return StructNewHelperName(irStruct.structId, functionId)
			Next
			Return StructNewHelperName(irStruct.structId, "")
		End If
		Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(normalized))
		If importedStruct Then Return ImportedStructDefaultHelperName(importedStruct)
		Return ""
	End Method

	Method StaticStructArrayDefaultHelperName:String(variable:TCompilerIrVariableDeclaration)
		If variable.staticArrayStructId.length Then
			Local irStruct:TCompilerIrStruct = StructById(variable.staticArrayStructId)
			If Not irStruct Then Return ""
			Local helperName:String = StructNewHelperName(irStruct.structId, "")
			For Local functionId:String = EachIn irStruct.constructorFunctionIds
				Local constructor:TCompilerIrFunction = FunctionById(functionId)
				If constructor And Not constructor.parameters.length Then
					helperName = StructNewHelperName(irStruct.structId, functionId)
					Exit
				End If
			Next
			Return helperName
		End If
		If variable.staticArrayImportedStructId.length Then
			Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(variable.staticArrayImportedStructId))
			Return ImportedStructDefaultHelperName(importedStruct)
		End If
		Return ""
	End Method

	Method ImportedStructDefaultHelperName:String(importedStruct:TCompilerIrImportedStruct)
		If Not importedStruct Then Return ""
		For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
			If routine.isConstructor And Not routine.parameters.length And routine.objectNewAbiName.length Then Return routine.objectNewAbiName
		Next
		If importedStruct.abiName.length Then Return importedStruct.abiName + "_New_ObjectNew"
		Return ""
	End Method

	Method EmitStaticArrayInitialization:String(variable:TCompilerIrVariableDeclaration, name:String, indent:String)
		Local elementInitializer:String = CDefaultValue(variable.staticArrayElementType)
		If variable.staticArrayStructId.length Or variable.staticArrayImportedStructId.length Then
			Local helperName:String = StaticStructArrayDefaultHelperName(variable)
			If Not helperName.length Then
				AddDiagnostic("BMXC2072", "StaticArray Struct element type '" + variable.staticArrayElementType + "' has no default construction helper", variable.source)
				Return ""
			End If
			elementInitializer = helperName + "()"
		Else If elementInitializer = "0" Then
			Return ""
		End If
		Local indexName:String = "bmx_static_init_" + SafeIdentifier(variable.symbolId)
		Local result:String = indent + "for (" + StaticArrayIndexCType() + " " + indexName + " = 0; " + indexName + " < (" + StaticArrayIndexCType() + ")" + variable.staticArrayLength + "; " + indexName + " = " + indexName + " + 1) {~n"
		result :+ indent + "    " + name + "[" + indexName + "] = " + elementInitializer + ";~n"
		Return result + indent + "}~n"
	End Method

	Method IsManagedCReferenceType:Int(typeName:String)
		Local normalized:String = typeName.ToLower()
		If normalized.StartsWith("closure<") Then Return True
		If normalized = "string" Or normalized = "object" Or normalized.EndsWith("]") Then Return True
		If interfaceTypes.Contains(normalized) Or opaqueInterfaceTypes.Contains(normalized) Or classTypes.Contains(normalized) Or importedClassTypes.Contains(normalized) Then Return True
		Return False
	End Method

	Method AppendRuntimeClasses(irModule:TCompilerIrModule, headerOnly:Int, result:TStringBuilder)
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If headerOnly And Not irClass.isPublished Then Continue
			Local className:String = ClassName(irClass.classId)
			Local objectName:String = ObjectName(irClass.classId)
			Local descriptorName:String = DescriptorName(irClass.classId)
			Local constructorName:String = ConstructorName(irClass.classId)
			result.Append("struct " + objectName + ";~n")
			result.Append("struct " + className + " {~n")
			result.Append("    BBClass *super;~n    void (*free)(BBObject *o);~n    BBDebugScope *debug_scope;~n")
			result.Append("    unsigned int instance_size;~n    void (*ctor)(BBOBJECT o);~n    void (*dtor)(BBOBJECT o);~n")
			result.Append("    BBSTRING (*ToString)(BBOBJECT x);~n    int (*Compare)(BBOBJECT x, BBOBJECT y);~n")
			result.Append("    BBOBJECT (*SendMessage)(BBOBJECT o, BBOBJECT m, BBOBJECT s);~n")
			result.Append("    BBUINT (*HashCode)(BBOBJECT o);~n    BBINT (*Equals)(BBOBJECT o, BBOBJECT y);~n")
			result.Append("    BBINTERFACETABLE itable;~n    void *extra;~n    unsigned int obj_size;~n")
			result.Append("    unsigned int instance_count;~n    unsigned int fields_offset;~n")
			For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
				Local parameters:String
				If Not slot.isMethod And Not slot.parameters.length Then
					parameters = "void"
				Else
					If slot.isMethod Then
						Local receiverObjectName:String = objectName
						If slot.receiverClassId.length Then receiverObjectName = String(objectNames.ValueForKey(slot.receiverClassId))
						If slot.receiverImportedClassId.length Then
							Local importedReceiver:TCompilerIrImportedClass = ImportedClassById(slot.receiverImportedClassId)
							If importedReceiver Then receiverObjectName = importedReceiver.abiName + "_obj"
						End If
						parameters :+ "struct " + receiverObjectName + " *"
					End If
					For Local index:Int = 0 Until slot.parameters.length
						If index Or slot.isMethod Then parameters :+ ", "
						parameters :+ CParameterType(slot.parameters[index], slot.source)
					Next
				End If
				Local canonicalSlotName:String = ClassFunctionSlotName(slot)
				Local canonicalDeclaration:String = CFunctionPointerDeclaration(slot.returnType, slot.callableReturnType, slot.callableReturnParameters, canonicalSlotName, parameters, slot.source, slot.callingConvention, slot.callableReturnCallingConvention)
				Local legacySlotName:String
				If headerOnly Then legacySlotName = LegacyClassSlotName(slot)
				If legacySlotName.length And legacySlotName <> canonicalSlotName Then
					' Compatibility member names must share the same class slot
					' without becoming translation-unit macros. A global macro
					' such as m_Contains_TObject can rewrite an unrelated class
					' member after two dependency headers are included.
					result.Append("    union {~n")
					result.Append("        " + canonicalDeclaration + ";~n")
					result.Append("        " + CFunctionPointerDeclaration(slot.returnType, slot.callableReturnType, slot.callableReturnParameters, legacySlotName, parameters, slot.source, slot.callingConvention, slot.callableReturnCallingConvention) + ";~n")
					result.Append("    };~n")
				Else
					result.Append("    " + canonicalDeclaration + ";~n")
				End If
			Next
			result.Append("};~n")
			result.Append("struct " + objectName + " {~n    struct " + className + " *clas;~n")
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				result.Append("    " + CFieldDeclaration(irField, FieldName(irField.declaringClassId, irField.fieldId)) + ";~n")
			Next
			result.Append("};~n")
			result.Append("extern struct " + className + " " + descriptorName + ";~n")
			If Not irClass.defaultConstructorFunctionId.length Then result.Append("void " + constructorName + "(struct " + objectName + " *o);~n")
			If headerOnly And irClass.isPublished And Not irClass.defaultConstructorFunctionId.length Then result.Append("void _" + irClass.abiName + "_New(struct " + objectName + " *o);~n")
			If headerOnly And irClass.isPublished And Not irClass.destructorFunctionId.length Then result.Append("void _" + irClass.abiName + "_Delete(struct " + objectName + " *o);~n")
			If headerOnly Then result.Append(EmitLegacyClassSlotCompatibility(irClass))
			If Not headerOnly Then
				result.Append(EmitClassInterfaceTables(irClass))
				If Not irClass.defaultConstructorFunctionId.length Then
					localNames = New TMap
					ResetTemporaries()
					Local constructorBody:String = EmitConstructorPrologue(irClass, "o", Null, "    ")
					result.Append("void " + constructorName + "(struct " + objectName + " *o) {~n")
					result.Append(EmitTemporaryDeclarations("    "))
					result.Append(constructorBody)
					result.Append("}~n")
				End If
				If irClass.isPublished And Not irClass.defaultConstructorFunctionId.length Then
					result.Append("void _" + irClass.abiName + "_New(struct " + objectName + " *o) { " + constructorName + "(o); }~n")
				End If
				If irClass.isPublished And Not irClass.destructorFunctionId.length Then
					result.Append("void _" + irClass.abiName + "_Delete(struct " + objectName + " *o) { " + EffectiveDestructorName(irClass) + "((" + EffectiveDestructorReceiverType(irClass) + ")o); }~n")
				End If
				Local typeDebugScopeName:String = "bmx_type_scope_" + SafeIdentifier(irClass.classId)
				Local typeDebugName:String = irClass.name
				Local typeDebugFlags:String
				If irClass.visibility = VISIBILITY_PRIVATE Then typeDebugFlags :+ "P"
				If irClass.visibility = VISIBILITY_PROTECTED Then typeDebugFlags :+ "Q"
				If irClass.isAbstract Then typeDebugFlags :+ "A"
				If typeDebugFlags.length Then typeDebugName :+ "'" + typeDebugFlags
				For Local routine:TCompilerIrFunction = EachIn currentModule.functions
					If ReflectedClassRoutine(irClass, routine) And CanEmitReflectionWrapper(routine) Then
						result.Append(EmitReflectionWrapper(irClass, routine))
					End If
				Next
				For Local classVariable:TCompilerIrVariableDeclaration = EachIn ReflectedClassVariables(irClass)
					If classVariable.callableReturnType.length Then
						result.Append(EmitCallableValueReflectionWrapper(classVariable.callableReturnType, classVariable.callableParameters, classVariable.callableCallingConvention, GlobalReflectionWrapperName(classVariable), classVariable.source))
					End If
				Next
				For Local fieldIndex:Int = 0 Until irClass.declaredFieldCount
					Local reflectionField:TCompilerIrClassField = irClass.fields[irClass.declaredFieldStart + fieldIndex]
					If CanReflectClassField(reflectionField) And reflectionField.callableReturnType.length Then
						result.Append(EmitCallableValueReflectionWrapper(reflectionField.callableReturnType, reflectionField.callableParameters, reflectionField.callableCallingConvention, ClassFieldReflectionWrapperName(irClass, reflectionField), reflectionField.source))
					End If
				Next
				Local debugDeclarationCount:Int = ReflectedClassFieldCount(irClass) + ReflectedClassVariableCount(irClass) + ReflectedClassRoutineCount(irClass) + 1
				result.Append("static struct { unsigned int kind; const char *name; BBDebugDecl decls[" + debugDeclarationCount + "]; } " + typeDebugScopeName + " = {~n")
				result.Append("    BBDEBUGSCOPE_USERTYPE, " + CQuoted(typeDebugName) + ", {~n")
				For Local classVariable:TCompilerIrVariableDeclaration = EachIn ReflectedClassVariables(irClass)
					Local variableType:String = ReflectedMemberType(ClassVariableDebugTypeTag(classVariable), classVariable.visibility, classVariable.metadata)
					Local variableWrapperName:String = "0"
					If classVariable.callableReturnType.length Then variableWrapperName = GlobalReflectionWrapperName(classVariable)
					If classVariable.storage = "constant" Then
						result.Append("        { BBDEBUGDECL_CONST, " + CQuoted(classVariable.name) + ", " + CQuoted(variableType) + ", .const_value = " + RuntimeStringPointer(classVariable.debugConstantStringLiteralId) + ", .reflection_wrapper = 0 },~n")
					Else If classVariable.isThreadedGlobal Then
						' A TLS address is resolved for the current thread at
						' module registration time; it is not a C constant and
						' therefore cannot appear in this static initializer.
						result.Append("        { BBDEBUGDECL_GLOBAL, " + CQuoted(classVariable.name) + ", " + CQuoted(variableType) + ", .var_address = 0, .reflection_wrapper = " + variableWrapperName + " },~n")
					Else
						result.Append("        { BBDEBUGDECL_GLOBAL, " + CQuoted(classVariable.name) + ", " + CQuoted(variableType) + ", .var_address = (void *)&" + String(globalNames.ValueForKey(classVariable.symbolId)) + ", .reflection_wrapper = " + variableWrapperName + " },~n")
					End If
				Next
				For Local fieldIndex:Int = 0 Until irClass.declaredFieldCount
					Local debugField:TCompilerIrClassField = irClass.fields[irClass.declaredFieldStart + fieldIndex]
					If Not CanReflectClassField(debugField) Then Continue
					Local fieldWrapperName:String = "0"
					If debugField.callableReturnType.length Then fieldWrapperName = ClassFieldReflectionWrapperName(irClass, debugField)
					result.Append("        { BBDEBUGDECL_FIELD, " + CQuoted(debugField.name) + ", " + CQuoted(ReflectedMemberType(ClassFieldDebugTypeTag(debugField), debugField.visibility, debugField.metadata)) + ", .field_offset = offsetof(struct " + objectName + ", " + FieldName(debugField.declaringClassId, debugField.fieldId) + "), .reflection_wrapper = " + fieldWrapperName + " },~n")
				Next
				For Local routine:TCompilerIrFunction = EachIn currentModule.functions
					If Not ReflectedClassRoutine(irClass, routine) Then Continue
					Local wrapperName:String = "0"
					If CanEmitReflectionWrapper(routine) Then wrapperName = ReflectionWrapperName(routine)
					Local declarationKind:String = "BBDEBUGDECL_TYPEFUNCTION"
					If routine.isMethod Then declarationKind = "BBDEBUGDECL_TYPEMETHOD"
					result.Append("        { " + declarationKind + ", " + CQuoted(routine.name) + ", " + CQuoted(ReflectedMemberType(ReflectedRoutineType(routine), routine.visibility, routine.metadata)) + ", .func_ptr = (BBFuncPtr)&" + FunctionName(routine.functionId) + ", .reflection_wrapper = " + wrapperName + " },~n")
				Next
				result.Append("        { BBDEBUGDECL_END, 0, 0, .var_address = 0, .reflection_wrapper = 0 }~n")
				result.Append("    }~n};~n")
				Local objectSize:String = "0"
				Local fieldsOffset:String = "sizeof(void *)"
				' The runtime's field range describes the complete object layout
				' for GC scanning, including managed fields inherited from a base
				' class.  Restricting it to locally declared fields lets reflected
				' method objects stored in a base (for example MaxUnit setup and
				' teardown hooks) be collected while a derived instance is alive.
				If irClass.fields.length Then
					Local firstField:TCompilerIrClassField = irClass.fields[0]
					Local lastField:TCompilerIrClassField = irClass.fields[irClass.fields.length - 1]
					Local firstName:String = FieldName(firstField.declaringClassId, firstField.fieldId)
					Local lastName:String = FieldName(lastField.declaringClassId, lastField.fieldId)
					fieldsOffset = "offsetof(struct " + objectName + ", " + firstName + ")"
					objectSize = "offsetof(struct " + objectName + ", " + lastName + ") - " + fieldsOffset + " + sizeof(((struct " + objectName + " *)0)->" + lastName + ")"
				End If
				result.Append("struct " + className + " " + descriptorName + " = {~n")
				Local superDescriptor:String = "&bbObjectClass"
				If irClass.baseClassId.length Then superDescriptor = "(BBClass *)&" + String(descriptorNames.ValueForKey(irClass.baseClassId))
				If irClass.baseImportedClassId.length Then
					Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
					If importedBase Then superDescriptor = "(BBClass *)&" + importedBase.abiName
				End If
				result.Append("    " + superDescriptor + ", bbObjectFree, (BBDebugScope *)&" + typeDebugScopeName + ", sizeof(struct " + objectName + "),~n")
				Local defaultConstructorName:String = constructorName
				If irClass.defaultConstructorFunctionId.length Then defaultConstructorName = FunctionName(irClass.defaultConstructorFunctionId)
				Local destructorName:String = EffectiveDestructorName(irClass)
				result.Append("    (void (*)(BBOBJECT))" + defaultConstructorName + ", (void (*)(BBOBJECT))" + destructorName + ", " + ObjectSlotFunction(irClass.toStringFunctionId, "bbObjectToString", "BBSTRING (*)(BBOBJECT)") + ", " + ObjectSlotFunction(irClass.compareFunctionId, "bbObjectCompare", "int (*)(BBOBJECT, BBOBJECT)") + ",~n")
				Local interfaceTable:String = "0"
				If irClass.interfaceImplementations.length Then interfaceTable = "&" + ClassInterfaceTableName(irClass.classId)
				result.Append("    " + ObjectSlotFunction(irClass.sendMessageFunctionId, "bbObjectSendMessage", "BBOBJECT (*)(BBOBJECT, BBOBJECT, BBOBJECT)") + ", " + ObjectSlotFunction(irClass.hashCodeFunctionId, "bbObjectHashCode", "BBUINT (*)(BBOBJECT)") + ", " + ObjectSlotFunction(irClass.equalsFunctionId, "bbObjectEquals", "BBINT (*)(BBOBJECT, BBOBJECT)") + ", " + interfaceTable + ", 0, " + objectSize + ", 0, " + fieldsOffset)
				For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
					result.Append(",~n    (" + ClassFunctionPointerType(slot, irClass) + ")" + FunctionName(slot.functionId))
				Next
				result.Append("~n};~n")
			End If
			result.Append("~n")
		Next
	End Method

	Method ReflectedClassRoutine:Int(irClass:TCompilerIrClass, routine:TCompilerIrFunction)
		If Not irClass Or Not routine Then Return False
		If routine.ownerClassId <> irClass.classId Or routine.isAbstract Then Return False
		If routine.lifecycleKind <> IR_LIFECYCLE_NONE Then Return False
		If routine.returnType.ToLower() <> "void" And RoutineReturnDebugTypeTag(routine) = "?" Then Return False
		For Local parameter:TCompilerIrParameter = EachIn routine.parameters
			If ParameterDebugTypeTag(parameter) = "?" Then Return False
		Next
		Return True
	End Method

	Method ReflectedClassFieldCount:Int(irClass:TCompilerIrClass)
		Local result:Int
		For Local index:Int = 0 Until irClass.declaredFieldCount
			If CanReflectClassField(irClass.fields[irClass.declaredFieldStart + index]) Then result :+ 1
		Next
		Return result
	End Method

	Method CanReflectClassField:Int(irField:TCompilerIrClassField)
		Return irField And ClassFieldDebugTypeTag(irField) <> "?"
	End Method

	Method ClassFieldReflectionWrapperName:String(irClass:TCompilerIrClass, irField:TCompilerIrClassField)
		Return "bmx_class_field_" + SafeIdentifier(irClass.classId) + "_" + SafeIdentifier(irField.fieldId) + "_ReflectionWrapper"
	End Method

	Method GlobalReflectionWrapperName:String(variable:TCompilerIrVariableDeclaration)
		Return "bmx_global_" + SafeIdentifier(variable.symbolId) + "_ReflectionWrapper"
	End Method

	Method CanReflectStructField:Int(irField:TCompilerIrStructField)
		Return irField And StructFieldDebugTypeTag(irField) <> "?"
	End Method

	Method ClassFieldDebugTypeTag:String(irField:TCompilerIrClassField)
		If Not irField Then Return "?"
		If irField.arrayCallableReturnType.length Then Return ArrayCallableDebugTypeTag(irField.arrayCallableReturnType, irField.arrayCallableParameters, irField.arrayCallableRank, irField.arrayCallableCallingConvention)
		If irField.callableReturnType.length Then Return CallableDebugTypeTag(irField.callableReturnType, irField.callableParameters, irField.callableCallingConvention)
		Return DebugTypeTag(irField.semanticType)
	End Method

	Method StructFieldDebugTypeTag:String(irField:TCompilerIrStructField)
		If Not irField Then Return "?"
		If irField.arrayCallableReturnType.length Then Return ArrayCallableDebugTypeTag(irField.arrayCallableReturnType, irField.arrayCallableParameters, irField.arrayCallableRank, irField.arrayCallableCallingConvention)
		If irField.callableReturnType.length Then Return CallableDebugTypeTag(irField.callableReturnType, irField.callableParameters, irField.callableCallingConvention)
		Return DebugTypeTag(irField.semanticType)
	End Method

	Method ClassVariableDebugTypeTag:String(variable:TCompilerIrVariableDeclaration)
		If Not variable Then Return "?"
		If variable.arrayCallableReturnType.length Then Return ArrayCallableDebugTypeTag(variable.arrayCallableReturnType, variable.arrayCallableParameters, variable.arrayCallableRank, variable.arrayCallableCallingConvention)
		If variable.callableReturnType.length Then Return CallableDebugTypeTag(variable.callableReturnType, variable.callableParameters, variable.callableCallingConvention)
		Return DebugTypeTag(variable.semanticType)
	End Method

	Method ArrayCallableDebugTypeTag:String(returnType:String, parameters:TCompilerIrParameter[], rank:Int, callingConvention:String = "c")
		If rank < 1 Then Return "?"
		Local result:String = "["
		For Local dimension:Int = 1 Until rank
			result :+ ","
		Next
		Local callableTag:String = CallableDebugTypeTag(returnType, parameters, callingConvention)
		If callableTag = "?" Then Return "?"
		Return result + "]" + callableTag
	End Method

	Method CallableDebugTypeTag:String(returnType:String, parameters:TCompilerIrParameter[], callingConvention:String = "c")
		Local result:String = "("
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ","
			Local parameterTag:String = ParameterDebugTypeTag(parameters[index])
			If parameterTag = "?" Then Return "?"
			result :+ parameterTag
		Next
		result :+ ")"
		If returnType.Trim().ToLower() <> "void" Then
			Local returnTag:String = DebugTypeTag(returnType)
			If returnTag = "?" Then Return "?"
			result :+ returnTag
		End If
		If callingConvention.ToLower() = "stdcall" Then result :+ "W"
		Return result
	End Method

	Method ParameterDebugTypeTag:String(parameter:TCompilerIrParameter)
		If Not parameter Then Return "?"
		Local result:String
		If parameter.callableReturnType.length Then result = CallableDebugTypeTag(parameter.callableReturnType, parameter.callableParameters, parameter.callableCallingConvention) Else result = DebugTypeTag(parameter.semanticType)
		If result <> "?" And parameter.passingMode = PARAMETER_PASS_VAR Then result = "&" + result
		Return result
	End Method

	Method ReflectedClassVariables:TCompilerIrVariableDeclaration[](irClass:TCompilerIrClass)
		Local result:TCompilerIrVariableDeclaration[] = New TCompilerIrVariableDeclaration[0]
		If Not irClass Or Not currentModule Then Return result
		For Local routine:TCompilerIrFunction = EachIn currentModule.functions
			If Not routine.isGlobalEntry Or Not routine.body Then Continue
			For Local statement:TCompilerIrStatement = EachIn routine.body.statements
				Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
				If Not variable Or variable.ownerClassId <> irClass.classId Then Continue
				If variable.storage <> "global" And variable.storage <> "constant" Then Continue
				If ClassVariableDebugTypeTag(variable) = "?" Then Continue
				If variable.storage = "constant" And Not variable.debugConstantStringLiteralId.length Then Continue
				result :+ [variable]
			Next
		Next
		Return result
	End Method

	Method ReflectedClassVariableCount:Int(irClass:TCompilerIrClass)
		Return ReflectedClassVariables(irClass).length
	End Method

	Method CanReflectType:Int(typeName:String)
		Return DebugTypeTag(typeName) <> "?"
	End Method

	Method ReflectedClassRoutineCount:Int(irClass:TCompilerIrClass)
		Local result:Int
		For Local routine:TCompilerIrFunction = EachIn currentModule.functions
			If ReflectedClassRoutine(irClass, routine) Then result :+ 1
		Next
		Return result
	End Method

	Method CanEmitReflectionWrapper:Int(routine:TCompilerIrFunction)
		If Not routine Then Return False
		If routine.isMethod And Not routine.receiver Then Return False
		Return True
	End Method

	Method EmitCallableValueReflectionWrapper:String(returnType:String, parameters:TCompilerIrParameter[], callingConvention:String, wrapperName:String, source:TCompilerSourceLocation)
		Local result:String = "static void " + wrapperName + "(void **buf) {~n"
		Local offset:String
		Local call:String
		Local returnCType:String = CType(returnType, source)
		If returnType.Trim().ToLower() = "void" Then
			call = "    "
		Else
			call = "    *((" + returnCType + " *)(buf)) = "
			offset = ReflectionBufferSlotCount(returnCType)
		End If
		Local callablePointerType:String = CCallablePointerType(returnType, parameters, 1, source, callingConvention)
		Local callablePointerStorageType:String = CCallablePointerType(returnType, parameters, 2, source, callingConvention)
		call :+ "(*((" + callablePointerStorageType + ")"
		If offset.length Then call :+ "(buf + (" + offset + "))" Else call :+ "(buf)"
		call :+ "))("
		If offset.length Then offset :+ " + "
		offset :+ ReflectionBufferSlotCount(callablePointerType)
		For Local parameterIndex:Int = 0 Until parameters.length
			Local parameter:TCompilerIrParameter = parameters[parameterIndex]
			If parameterIndex Then call :+ ", "
			Local parameterCType:String = CParameterType(parameter, source)
			call :+ ReflectionBufferParameterValue(parameter, source, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(parameterCType)
		Next
		Return result + call + ");~n}~n"
	End Method

	Method EmitReflectionWrapper:String(irClass:TCompilerIrClass, routine:TCompilerIrFunction)
		Local result:String = "static void " + ReflectionWrapperName(routine) + "(void **buf) {~n"
		Local offset:String
		Local call:String
		Local returnType:String = routine.returnType.Trim()
		If routine.callableReturnType.length Then
			Local returnValueType:String = CCallablePointerType(routine.callableReturnType, routine.callableReturnParameters, 1, routine.source, routine.callableReturnCallingConvention)
			Local returnStorageType:String = CCallablePointerType(routine.callableReturnType, routine.callableReturnParameters, 2, routine.source, routine.callableReturnCallingConvention)
			call = "    *((" + returnStorageType + ")(buf)) = " + FunctionName(routine.functionId) + "("
			offset = ReflectionBufferSlotCount(returnValueType)
		Else If returnType.ToLower() = "void" Then
			call = "    " + FunctionName(routine.functionId) + "("
		Else
			Local returnCType:String = CType(returnType, routine.source)
			call = "    *((" + returnCType + " *)(buf)) = " + FunctionName(routine.functionId) + "("
			offset = ReflectionBufferSlotCount(returnCType)
		End If

		If routine.isMethod Then
			Local receiverCType:String = CType(irClass.semanticType, routine.source)
			call :+ "*((" + receiverCType + " *)"
			If offset.length Then
				call :+ "(buf + (" + offset + "))"
				offset :+ " + "
			Else
				call :+ "(buf)"
			End If
			call :+ ")"
			offset :+ ReflectionBufferSlotCount(receiverCType)
		End If

		For Local parameterIndex:Int = 0 Until routine.parameters.length
			Local parameter:TCompilerIrParameter = routine.parameters[parameterIndex]
			Local parameterCType:String = CParameterType(parameter, routine.source)
			If routine.isMethod Or parameterIndex Then call :+ ", "
			call :+ ReflectionBufferParameterValue(parameter, routine.source, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(parameterCType)
		Next
		Return result + call + ");~n}~n"
	End Method

	Method ReflectionBufferSlotCount:String(cType:String)
		' BRL.Reflection stores the return, receiver and arguments in one
		' pointer-aligned buffer. Keep this expression target-independent so
		' the generated unit follows the runtime word size at C compilation.
		Return "((sizeof(" + cType + ") + sizeof(void *) - 1) / sizeof(void *))"
	End Method

	Method ReflectionWrapperName:String(routine:TCompilerIrFunction)
		Return FunctionName(routine.functionId) + "_ReflectionWrapper"
	End Method

	Method ReflectedRoutineType:String(routine:TCompilerIrFunction)
		Local result:String = "("
		For Local index:Int = 0 Until routine.parameters.length
			If index Then result :+ ","
			result :+ ParameterDebugTypeTag(routine.parameters[index])
		Next
		result :+ ")"
		If routine.returnType.ToLower() <> "void" Then result :+ RoutineReturnDebugTypeTag(routine)
		If routine.callingConvention.ToLower() = "stdcall" Then result :+ "W"
		Return result
	End Method

	Method RoutineReturnDebugTypeTag:String(routine:TCompilerIrFunction)
		If Not routine Then Return "?"
		If routine.callableReturnType.length Then Return CallableDebugTypeTag(routine.callableReturnType, routine.callableReturnParameters, routine.callableReturnCallingConvention)
		Return DebugTypeTag(routine.returnType)
	End Method

	Method ReflectedMemberType:String(typeTag:String, visibility:Int, metadata:TCompilerIrMetadataEntry[])
		Select visibility
			Case VISIBILITY_PRIVATE
				typeTag :+ "'P"
			Case VISIBILITY_PROTECTED
				typeTag :+ "'Q"
		End Select
		If metadata.length Then
			typeTag :+ "{"
			For Local index:Int = 0 Until metadata.length
				If index Then typeTag :+ " "
				typeTag :+ metadata[index].key + "=" + metadata[index].value
			Next
			typeTag :+ "}"
		End If
		Return typeTag
	End Method

	Method EmitLegacyClassSlotCompatibility:String(irClass:TCompilerIrClass)
		Local result:String
		For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
			Local legacySuffix:String
			Local supported:Int = True
			For Local parameter:TCompilerIrParameter = EachIn slot.parameters
				Local code:String = LegacySlotParameterCode(parameter)
				If Not code.length Then supported = False; Exit
				legacySuffix :+ code
			Next
			Local parameters:String
			If slot.isMethod Then parameters = "struct " + ObjectName(irClass.classId) + " *"
			For Local index:Int = 0 Until slot.parameters.length
				If index Or slot.isMethod Then parameters :+ ", "
				parameters :+ CParameterType(slot.parameters[index], slot.source)
			Next
			If Not parameters.length Then parameters = "void"
			Local canonicalSlotName:String = ClassFunctionSlotName(slot)
			Local canonicalTypedefName:String = irClass.abiName + "_" + canonicalSlotName[2..] + "_m"
			result :+ "typedef " + CFunctionPointerDeclaration(slot.returnType, slot.callableReturnType, slot.callableReturnParameters, canonicalTypedefName, parameters, slot.source, slot.callingConvention, slot.callableReturnCallingConvention) + ";~n"
			If Not supported Then Continue
			Local legacyName:String = TCompilerCBackend.LegacySlotName(slot.name)
			Local legacySlotName:String = "m_" + legacyName
			If legacySuffix.length Then legacySlotName :+ "_" + legacySuffix
			Local typedefName:String = irClass.abiName + "_" + legacyName
			If legacySuffix.length Then typedefName :+ "_" + legacySuffix
			typedefName :+ "_m"
			If typedefName <> canonicalTypedefName Then result :+ "typedef " + CFunctionPointerDeclaration(slot.returnType, slot.callableReturnType, slot.callableReturnParameters, typedefName, parameters, slot.source, slot.callingConvention, slot.callableReturnCallingConvention) + ";~n"
		Next
		Return result
	End Method

	Method LegacyClassSlotName:String(slot:TCompilerIrClassFunctionSlot)
		If Not slot Then Return ""
		Local legacySuffix:String
		For Local parameter:TCompilerIrParameter = EachIn slot.parameters
			Local code:String = LegacySlotParameterCode(parameter)
			If Not code.length Then Return ""
			legacySuffix :+ code
		Next
		Local result:String = "m_" + TCompilerCBackend.LegacySlotName(slot.name)
		If legacySuffix.length Then result :+ "_" + legacySuffix
		Return result
	End Method

	Function LegacySlotName:String(name:String)
		Select name.ToLower()
			Case "*" Return "_mul"
			Case "/" Return "_div"
			Case "+" Return "_add"
			Case "-" Return "_sub"
			Case "&" Return "_and"
			Case "|" Return "_or"
			Case "~~", "~~~~" Return "_xor"
			Case "^" Return "_pow"
			Case ":*" Return "_muleq"
			Case ":/" Return "_diveq"
			Case ":+" Return "_addeq"
			Case ":-" Return "_subeq"
			Case ":&" Return "_andeq"
			Case ":|" Return "_oreq"
			Case ":~~", ":~~~~" Return "_xoreq"
			Case ":^" Return "_poweq"
			Case ":=" Return "_assign"
			Case "<" Return "_lt"
			Case "<=" Return "_le"
			Case ">" Return "_gt"
			Case ">=" Return "_ge"
			Case "=" Return "_eq"
			Case "<>" Return "_ne"
			Case "mod" Return "_mod"
			Case "shl" Return "_shl"
			Case "shr" Return "_shr"
			Case ":mod" Return "_modeq"
			Case ":shl" Return "_shleq"
			Case ":shr" Return "_shreq"
			Case "[]" Return "_iget"
			Case "[]=" Return "_iset"
		End Select
		Return SafeIdentifier(name)
	End Function

	Method LegacySlotParameterCode:String(parameter:TCompilerIrParameter)
		If Not parameter Or parameter.isStaticArray Or parameter.callableReturnType.length Then Return ""
		Local typeName:String = parameter.semanticType
		Local pointerSuffix:String = " Ptr"
		If typeName.EndsWith(pointerSuffix) Then
			Local elementCode:String = LegacySlotTypeCode(typeName[..typeName.length - pointerSuffix.length])
			If elementCode.length Then Return "p" + elementCode
			Return ""
		End If
		Return LegacySlotTypeCode(typeName)
	End Method

	Function LegacySlotTypeCode:String(typeName:String)
		Select typeName.ToLower()
			Case "byte" Return "b"
			Case "short" Return "s"
			Case "int" Return "i"
			Case "uint" Return "u"
			Case "long" Return "l"
			Case "ulong" Return "y"
			Case "longint" Return "g"
			Case "ulongint" Return "G"
			Case "size_t" Return "z"
			Case "float" Return "f"
			Case "double" Return "d"
			Case "float64" Return "h"
			Case "int128" Return "j"
			Case "float128" Return "k"
			Case "double128" Return "m"
			Case "string" Return "S"
			Case "object" Return "TObject"
		End Select
		Return ""
	End Function

	Method EmitClassInterfaceTables:String(irClass:TCompilerIrClass)
		If Not irClass Or Not irClass.interfaceImplementations.length Then Return ""
		Local result:String = "struct " + ClassInterfaceVdefName(irClass.classId) + " {~n"
		For Local implementation:TCompilerIrInterfaceImplementation = EachIn irClass.interfaceImplementations
			result :+ "    struct " + InterfaceMethodsName(implementation.interfaceId) + " interface_" + SafeIdentifier(implementation.interfaceId) + ";~n"
		Next
		result :+ "};~n"
		result :+ "static struct BBInterfaceOffsets " + ClassInterfaceOffsetsName(irClass.classId) + "[] = {~n"
		For Local implementation:TCompilerIrInterfaceImplementation = EachIn irClass.interfaceImplementations
			result :+ "    { (BBINTERFACE)&" + InterfaceDescriptorName(implementation.interfaceId) + ", offsetof(struct " + ClassInterfaceVdefName(irClass.classId) + ", interface_" + SafeIdentifier(implementation.interfaceId) + ") },~n"
		Next
		result :+ "};~n"
		result :+ "static struct " + ClassInterfaceVdefName(irClass.classId) + " " + ClassInterfaceVtableName(irClass.classId) + " = {~n"
		For Local implementation:TCompilerIrInterfaceImplementation = EachIn irClass.interfaceImplementations
			Local irInterface:TCompilerIrInterface = InterfaceById(implementation.interfaceId)
			result :+ "    { "
			If Not implementation.slots.length Then result :+ "0"
			For Local index:Int = 0 Until implementation.slots.length
				If index Then result :+ ", "
				Local slot:TCompilerIrInterfaceImplementationSlot = implementation.slots[index]
				If slot And irInterface And index < irInterface.methods.length Then
					Local targetName:String = slot.functionAbiName
					If Not targetName.length Then targetName = FunctionName(slot.functionId)
					result :+ "(" + InterfaceFunctionPointerType(irInterface.methods[index]) + ")" + targetName
				Else
					result :+ "0"
				End If
			Next
			result :+ " },~n"
		Next
		result :+ "};~n"
		result :+ "static struct BBInterfaceTable " + ClassInterfaceTableName(irClass.classId) + " = { " + ClassInterfaceOffsetsName(irClass.classId) + ", &" + ClassInterfaceVtableName(irClass.classId) + ", " + irClass.interfaceImplementations.length + " };~n"
		Return result
	End Method

	Method ObjectSlotFunction:String(functionId:String, fallback:String, functionPointerType:String)
		If Not functionId.length Then Return fallback
		Return "(" + functionPointerType + ")" + FunctionName(functionId)
	End Method

	Method ClassFunctionSlotName:String(slot:TCompilerIrClassFunctionSlot)
		If slot.slotName.length Then Return slot.slotName
		Local prefix:String = "f_"
		If slot.isMethod Then prefix = "m_"
		Return prefix + SafeIdentifier(slot.slotId + "_" + LegacySlotName(slot.name))
	End Method

	Method InterfaceFunctionPointerType:String(interfaceMethod:TCompilerIrInterfaceMethod)
		Local irInterface:TCompilerIrInterface = InterfaceById(interfaceMethod.declaringInterfaceId)
		Local parameters:String = InterfaceReceiverType(irInterface)
		For Local parameter:TCompilerIrParameter = EachIn interfaceMethod.parameters
			parameters :+ ", " + CParameterType(parameter, interfaceMethod.source)
		Next
		Return CFunctionPointerDeclaration(interfaceMethod.returnType, interfaceMethod.callableReturnType, interfaceMethod.callableReturnParameters, "", parameters, interfaceMethod.source, interfaceMethod.callingConvention, interfaceMethod.callableReturnCallingConvention)
	End Method

	Method ClassFunctionPointerType:String(slot:TCompilerIrClassFunctionSlot, irClass:TCompilerIrClass)
		Local parameters:String
		If slot.isMethod Then
			Local receiverObjectName:String = ObjectName(irClass.classId)
			If slot.receiverClassId.length Then receiverObjectName = String(objectNames.ValueForKey(slot.receiverClassId))
			If slot.receiverImportedClassId.length Then
				Local importedReceiver:TCompilerIrImportedClass = ImportedClassById(slot.receiverImportedClassId)
				If importedReceiver Then receiverObjectName = importedReceiver.abiName + "_obj"
			End If
			parameters = "struct " + receiverObjectName + " *"
		End If
		For Local parameter:TCompilerIrParameter = EachIn slot.parameters
			If parameters.length Then parameters :+ ", "
			parameters :+ CParameterType(parameter, slot.source)
		Next
		If Not parameters.length Then parameters = "void"
		Return CFunctionPointerDeclaration(slot.returnType, slot.callableReturnType, slot.callableReturnParameters, "", parameters, slot.source, slot.callingConvention, slot.callableReturnCallingConvention)
	End Method

	Method InterfaceReceiverType:String(irInterface:TCompilerIrInterface)
		If irInterface And irInterface.isExternInterface Then Return NativeInterfaceReceiverType(irInterface)
		' Imported canonical generic Interface layouts are owned by their
		' specialization units.  Their slots use the erased object receiver so
		' unrelated implementing specializations share one callable ABI.
		If irInterface And irInterface.isImported And Not irInterface.methodsLayoutOwnedExternally Then Return "BBOBJECT"
		If irInterface And irInterface.abiName.length And irInterface.methodsAbiName = irInterface.abiName + "_methods" Then Return "struct " + irInterface.abiName + "_obj *"
		Return "BBOBJECT"
	End Method

	Method NativeInterfaceReceiverType:String(irInterface:TCompilerIrInterface)
		If irInterface And irInterface.abiName.length Then Return "struct " + irInterface.abiName + " *"
		Return "void *"
	End Method

	Method InterfaceMethodName:String(interfaceMethod:TCompilerIrInterfaceMethod)
		If Not interfaceMethod Then Return "bmx_missing_interface_method"
		Local irInterface:TCompilerIrInterface = InterfaceById(interfaceMethod.declaringInterfaceId)
		If irInterface And irInterface.isExternInterface Then
			If interfaceMethod.abiName.length Then Return interfaceMethod.abiName
			Return interfaceMethod.name
		End If
		If interfaceMethod And interfaceMethod.slotAbiName.length Then Return interfaceMethod.slotAbiName
		If irInterface And irInterface.methodsAbiName.length Then Return interfaceMethod.slotId
		Return "m_" + SafeIdentifier(interfaceMethod.slotId + "_" + interfaceMethod.name)
	End Method

	Method InterfaceMethodsName:String(interfaceId:String)
		Local irInterface:TCompilerIrInterface = InterfaceById(interfaceId)
		If irInterface And irInterface.methodsAbiName.length Then Return irInterface.methodsAbiName
		Local suffix:String = interfaceId
		If irInterface Then suffix :+ "_" + irInterface.name
		Return "BCC2_InterfaceMethods_" + SafeIdentifier(suffix)
	End Method

	Method InterfaceDescriptorName:String(interfaceId:String)
		Local irInterface:TCompilerIrInterface = InterfaceById(interfaceId)
		If irInterface And irInterface.abiName.length Then Return irInterface.abiName + "_ifc"
		Local suffix:String = interfaceId
		If irInterface Then suffix :+ "_" + irInterface.name
		Return "bmx_interface_" + SafeIdentifier(suffix)
	End Method

	Method InterfaceClassName:String(interfaceId:String)
		Return InterfaceDescriptorName(interfaceId) + "_class"
	End Method

	Method InterfaceDebugScopeName:String(interfaceId:String)
		Return InterfaceDescriptorName(interfaceId) + "_debug_scope"
	End Method

	Method ClassInterfaceVdefName:String(classId:String)
		Return "BCC2_InterfaceVdef_" + SafeIdentifier(classId)
	End Method

	Method ClassInterfaceOffsetsName:String(classId:String)
		Return "bmx_interface_offsets_" + SafeIdentifier(classId)
	End Method

	Method ClassInterfaceVtableName:String(classId:String)
		Return "bmx_interface_vtable_" + SafeIdentifier(classId)
	End Method

	Method ClassInterfaceTableName:String(classId:String)
		Return "bmx_interface_table_" + SafeIdentifier(classId)
	End Method

	Method CDefaultValue:String(typeName:String)
		Local normalized:String = typeName.ToLower()
		If normalized = "__pico_exception" Then Return "((BMXPicoException){ 0, BMX_PICO_EXCEPTION_NONE, 0 })"
		If normalized.EndsWith("]") And EmbeddedArrayTypes() Then Return "&bmx_pico_empty_array"
		If normalized.EndsWith("]") Then Return "&bbEmptyArray"
		If normalized.StartsWith("closure<") And EmbeddedObjectTypes() Then Return "((BMXPicoClosure *)&bmx_pico_null_object)"
		If normalized.StartsWith("closure<") Then Return "((BBClosure *)&bbNullObject)"
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(normalized))
		If irStruct Then Return "((struct " + StructName(irStruct.structId) + "){0})"
		Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(normalized))
		If importedStruct Then Return "((struct " + importedStruct.abiName + "){0})"
		If normalized = "string" And EmbeddedStringTypes() Then Return "&bmx_pico_empty_string"
		If normalized = "string" Then Return "&bbEmptyString"
		Local irInterface:TCompilerIrInterface = TCompilerIrInterface(interfaceTypes.ValueForKey(normalized))
		If irInterface And irInterface.isExternInterface Then Return "0"
		If (irInterface Or opaqueInterfaceTypes.Contains(normalized)) And EmbeddedObjectTypes() Then Return "((BMXPicoObject *)&bmx_pico_null_object)"
		If irInterface Or opaqueInterfaceTypes.Contains(normalized) Then Return "((BBOBJECT)&bbNullObject)"
		Local irClass:TCompilerIrClass = TCompilerIrClass(classTypes.ValueForKey(normalized))
		If irClass And EmbeddedObjectTypes() Then Return "((struct " + ObjectName(irClass.classId) + " *)&bmx_pico_null_object)"
		If irClass Then Return "((struct " + ObjectName(irClass.classId) + " *)&bbNullObject)"
		Local importedClass:TCompilerIrImportedClass = TCompilerIrImportedClass(importedClassTypes.ValueForKey(normalized))
		If importedClass And importedClass.abiName = "bbObjectClass" And EmbeddedObjectTypes() Then Return "(&bmx_pico_null_object)"
		If importedClass And importedClass.abiName = "bbObjectClass" Then Return "((BBOBJECT)&bbNullObject)"
		If importedClass And EmbeddedObjectTypes() Then Return "((struct " + importedClass.abiName + "_obj *)&bmx_pico_null_object)"
		If importedClass Then Return "((struct " + importedClass.abiName + "_obj *)&bbNullObject)"
		If normalized = "object" And EmbeddedObjectTypes() Then Return "(&bmx_pico_null_object)"
		If normalized = "object" Then Return "((BBOBJECT)&bbNullObject)"
		Return "0"
	End Method

	Method AppendRuntimeStringLiterals(irModule:TCompilerIrModule, result:TStringBuilder)
		Local declaredLengths:TMap = New TMap
		Local emitted:Int
		For Local literal:TCompilerIrStringLiteral = EachIn irModule.stringLiterals
			If Not literal.value.length Then Continue
			emitted = True
			Local typeName:String = "BCC2_BBString_" + literal.value.length
			Local name:String = "bmx_string_" + SafeIdentifier(literal.literalId)
			Local lengthKey:String = String(literal.value.length)
			If Not declaredLengths.Contains(lengthKey) Then
				declaredLengths.Insert(lengthKey, lengthKey)
				result.Append("struct " + typeName + " { BBClass_String *clas; BBUINT hash; int length; BBChar buf[" + literal.value.length + "]; };~n")
			End If
			result.Append("static struct " + typeName + " " + name + " = { &bbStringClass, 0, " + literal.value.length + ", {")
			For Local index:Int = 0 Until literal.value.length
				If index Then result.Append(",")
				result.Append(String.FromInt(literal.value[index]))
			Next
			result.Append("} };~n")
		Next
		If emitted Then result.Append("~n")
	End Method

	Method AppendRuntimeEnums(irModule:TCompilerIrModule, result:TStringBuilder)
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			If irEnum.isImported Or Not irEnum.runtimeDescriptor Then Continue
			Local enumDescriptor:TCompilerIrEnumRuntimeDescriptor = irEnum.runtimeDescriptor
			Local count:Int = irEnum.values.length
			Local storageCount:Int = count
			If storageCount < 1 Then storageCount = 1
			Local enumType:String = CType(irEnum.underlyingType, irEnum.source)
			Local enumStructName:String = "BCC2_BBEnum_" + SafeIdentifier(irEnum.enumId + "_" + irEnum.name)
			Local scopeStructName:String = "BCC2_BBDebugEnumScope_" + SafeIdentifier(irEnum.enumId + "_" + irEnum.name)
			result.Append("struct " + enumStructName + " { const char *name; char *type; char *atype; int flags; int length; void *values; BBString *names[" + storageCount + "]; };~n")
			If irEnum.isFlags Then
				result.Append("const " + enumType + " " + enumDescriptor.maskAbiName + " = ")
				If Not count Then
					result.Append("0")
				Else
					For Local index:Int = 0 Until count
						If index Then result.Append("|")
						result.Append(String.FromLong(irEnum.values[index].integerValue))
					Next
				End If
				result.Append(";~n")
			End If
			result.Append("struct " + scopeStructName + " { unsigned int kind; const char *name; BBDebugDecl decls[" + (count + 1) + "]; };~n")
			result.Append("static struct " + scopeStructName + " " + enumDescriptor.debugScopeAbiName + " = { BBDEBUGSCOPE_USERENUM, " + CQuoted(enumDescriptor.runtimeName) + ", {~n")
			For Local value:TCompilerIrEnumValue = EachIn irEnum.values
				result.Append("    { BBDEBUGDECL_CONST, " + CQuoted(value.name) + ", " + CQuoted(enumDescriptor.arrayTypeEncoding) + ", .const_value = " + RuntimeStringPointer(value.ordinalStringLiteralId) + ", .reflection_wrapper = 0 },~n")
			Next
			result.Append("    { BBDEBUGDECL_END, 0, " + CQuoted(enumDescriptor.numericTypeTag) + ", .is_flags_enum = " + irEnum.isFlags + ", .reflection_wrapper = 0 }~n")
			result.Append("} };~n")
			result.Append("static " + enumType + " " + enumDescriptor.valuesAbiName + "[" + storageCount + "] = {")
			If Not count Then
				result.Append("0")
			Else
				For Local index:Int = 0 Until count
					If index Then result.Append(",")
					result.Append(String.FromLong(irEnum.values[index].integerValue))
				Next
			End If
			result.Append("};~n")
			result.Append("static struct " + enumStructName + " " + enumDescriptor.descriptorStorageAbiName + " = { " + CQuoted(enumDescriptor.runtimeName) + ", " + CQuoted(enumDescriptor.numericTypeTag) + ", " + CQuoted(enumDescriptor.arrayTypeEncoding) + ", " + irEnum.isFlags + ", " + count + ", &" + enumDescriptor.valuesAbiName + ", {")
			If Not count Then
				result.Append("0")
			Else
				For Local index:Int = 0 Until count
					If index Then result.Append(",")
					result.Append(RuntimeStringPointer(irEnum.values[index].nameStringLiteralId))
				Next
			End If
			result.Append("} };~n")
			result.Append("BBEnum *" + enumDescriptor.descriptorAbiName + ";~n")
			result.Append("BBSTRING " + enumDescriptor.toStringAbiName + "(" + enumType + " ordinal) { return bbEnumToString_" + enumDescriptor.numericTypeTag + "(" + enumDescriptor.descriptorAbiName + ", ordinal); }~n")
			result.Append("BBINT " + enumDescriptor.tryConvertAbiName + "(" + enumType + " ordinalValue, " + enumType + " *ordinalResult) { return bbEnumTryConvert_" + enumDescriptor.numericTypeTag + "(" + enumDescriptor.descriptorAbiName + ", ordinalValue, ordinalResult); }~n")
			result.Append(enumType + " " + enumDescriptor.fromStringAbiName + "(BBSTRING name) { return bbEnumFromString_" + enumDescriptor.numericTypeTag + "(" + enumDescriptor.descriptorAbiName + ", name); }~n~n")
		Next
	End Method

	Method EmitRuntimeEnumPrototypes:String(irModule:TCompilerIrModule, publishedOnly:Int)
		Local result:String
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			If irEnum.isImported Or Not irEnum.runtimeDescriptor Then Continue
			If publishedOnly And Not irEnum.isPublished Then Continue
			Local enumDescriptor:TCompilerIrEnumRuntimeDescriptor = irEnum.runtimeDescriptor
			Local enumType:String = CType(irEnum.underlyingType, irEnum.source)
			result :+ "extern BBEnum *" + enumDescriptor.descriptorAbiName + ";~n"
			If irEnum.isFlags Then result :+ "extern const " + enumType + " " + enumDescriptor.maskAbiName + ";~n"
			result :+ "BBSTRING " + enumDescriptor.toStringAbiName + "(" + enumType + " ordinal);~n"
			result :+ "BBINT " + enumDescriptor.tryConvertAbiName + "(" + enumType + " ordinalValue, " + enumType + " *ordinalResult);~n"
			result :+ enumType + " " + enumDescriptor.fromStringAbiName + "(BBSTRING name);~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method RuntimeStringPointer:String(literalId:String)
		Local result:String = String(stringNames.ValueForKey(literalId))
		If result.length Then Return result
		Return "&bbEmptyString"
	End Method

	Method AppendRuntimeStringInitialization(irModule:TCompilerIrModule, result:TStringBuilder)
		result.Append("static void bb_init_strings(void) {~n")
		For Local literal:TCompilerIrStringLiteral = EachIn irModule.stringLiterals
			If literal.value.length Then result.Append("    bbStringHash((BBString*)&bmx_string_" + SafeIdentifier(literal.literalId) + ");~n")
		Next
		result.Append("}~n~n")
	End Method

	Method EmitExternalPrototypes:String(irModule:TCompilerIrModule, dependencyHeadersAuthoritative:Int = False)
		Local result:String
		For Local externalGlobal:TCompilerIrExternalGlobal = EachIn irModule.externalGlobals
			If dependencyHeadersAuthoritative And HeaderOwnsExternal(irModule, externalGlobal.originModule, externalGlobal.source.path) Then Continue
			If externalGlobal.suppressNativePrototype Then Continue
			' ReadOnly is a source access rule, not a promise that native storage was
			' declared const. Keep the C declaration ABI-compatible with bcc headers.
			Local threadedPrefix:String
			If externalGlobal.isThreadedGlobal Then threadedPrefix = "BBThreadLocal "
			If externalGlobal.callableReturnType.length Then
				result :+ "extern " + threadedPrefix + CCallableFieldDeclaration(externalGlobal.callableReturnType, externalGlobal.callableParameters, externalGlobal.abiName, externalGlobal.source, externalGlobal.callableCallingConvention) + ";~n"
			Else
				result :+ "extern " + threadedPrefix + CType(externalGlobal.semanticType, externalGlobal.source) + " " + externalGlobal.abiName + ";~n"
			End If
		Next
		For Local externalFunction:TCompilerIrExternalFunction = EachIn irModule.externalFunctions
			If PicoStringRuntimeFunctionName(externalFunction).length Then Continue
			If PicoScalarIntrinsicFunctionName(externalFunction).length Then Continue
			' Imported module headers own ordinary declarations. Closed generic
			' routines are different: the consuming application may own a newly
			' specialized unit, so always declare the exact ABI used by its call.
			If dependencyHeadersAuthoritative And Not externalFunction.isGenericSpecialization And HeaderOwnsExternal(irModule, externalFunction.originModule, externalFunction.source.path) Then Continue
			If externalFunction.suppressNativePrototype Then Continue
			If externalFunction.nativeDeclaration.length Then
				result :+ "extern " + externalFunction.nativeDeclaration + ";~n"
				Continue
			End If
			Local parameters:String
			If Not externalFunction.parameters.length Then
				parameters = "void"
			Else
				For Local index:Int = 0 Until externalFunction.parameters.length
					If index Then parameters :+ ", "
					Local parameter:TCompilerIrParameter = externalFunction.parameters[index]
					parameters :+ CNativeParameterDeclaration(parameter, LocalName(parameter.symbolId, parameter.name), externalFunction.source)
				Next
			End If
			Local declarationName:String = externalFunction.implementationAbiName
			If Not declarationName.length Then declarationName = externalFunction.abiName
			result :+ "extern " + CNativeFunctionDeclaration(externalFunction, declarationName, parameters) + ";~n"
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitNativeStringWrappers:String(irModule:TCompilerIrModule)
		Local result:String
		For Local externalFunction:TCompilerIrExternalFunction = EachIn irModule.externalFunctions
			If Not NeedsNativeStringWrapper(externalFunction) Then Continue
			Local parameters:String
			For Local index:Int = 0 Until externalFunction.parameters.length
				If index Then parameters :+ ", "
				Local parameter:TCompilerIrParameter = externalFunction.parameters[index]
				parameters :+ CParameterDeclaration(parameter, LocalName(parameter.symbolId, parameter.name), externalFunction.source)
			Next
			If Not parameters.length Then parameters = "void"
			result :+ "static " + CFunctionDeclaration(externalFunction.returnType, externalFunction.callableReturnType, externalFunction.callableReturnParameters, NativeStringWrapperName(externalFunction), parameters, externalFunction.source, "c", externalFunction.callableReturnCallingConvention) + " {~n"
			For Local index:Int = 0 Until externalFunction.parameters.length
				Local parameter:TCompilerIrParameter = externalFunction.parameters[index]
				If parameter.nativeStringEncoding = NATIVE_STRING_NONE Then Continue
				Local sourceName:String = LocalName(parameter.symbolId, parameter.name)
				Local nativeName:String = sourceName + "_native"
				If parameter.nativeStringEncoding = NATIVE_STRING_UTF8 Then
					result :+ "    BBBYTE *" + nativeName + " = bbStringToCString(" + sourceName + ");~n"
				Else
					result :+ "    BBChar *" + nativeName + " = bbStringToWString(" + sourceName + ");~n"
				End If
			Next
			Local invocation:String = externalFunction.abiName + "("
			For Local index:Int = 0 Until externalFunction.parameters.length
				If index Then invocation :+ ", "
				Local parameter:TCompilerIrParameter = externalFunction.parameters[index]
				Local argumentName:String = LocalName(parameter.symbolId, parameter.name)
				If parameter.nativeStringEncoding <> NATIVE_STRING_NONE Then argumentName :+ "_native"
				If index < externalFunction.nativeParameterTypes.length And externalFunction.nativeParameterTypes[index].length Then
					argumentName = "((" + externalFunction.nativeParameterTypes[index] + ")" + argumentName + ")"
				End If
				invocation :+ argumentName
			Next
			invocation :+ ")"
			Local returnsValue:Int = externalFunction.returnType.ToLower() <> "void"
			If externalFunction.callableReturnType.length Then returnsValue = True
			If returnsValue Then
				Local nativeResultType:String = CType(externalFunction.returnType, externalFunction.source)
				If externalFunction.nativeStringReturnEncoding = NATIVE_STRING_UTF8 Then nativeResultType = "BBBYTE *"
				If externalFunction.nativeStringReturnEncoding = NATIVE_STRING_UTF16 Then nativeResultType = "BBChar *"
				If externalFunction.nativeStringReturnEncoding = NATIVE_STRING_NONE And externalFunction.nativeReturnType.length And (IsManagedCReferenceType(externalFunction.returnType) Or IsPointerSemanticType(externalFunction.returnType)) Then
					invocation = "((" + nativeResultType + ")(" + invocation + "))"
				End If
				result :+ "    " + nativeResultType + " bmx_native_result = " + invocation + ";~n"
			Else
				result :+ "    " + invocation + ";~n"
			End If
			For Local parameter:TCompilerIrParameter = EachIn externalFunction.parameters
				If parameter.nativeStringEncoding <> NATIVE_STRING_NONE Then result :+ "    bbMemFree(" + LocalName(parameter.symbolId, parameter.name) + "_native);~n"
			Next
			If returnsValue Then
				If externalFunction.nativeStringReturnEncoding = NATIVE_STRING_UTF8 Then
					result :+ "    return bbStringFromCString((const char *)bmx_native_result);~n"
				Else If externalFunction.nativeStringReturnEncoding = NATIVE_STRING_UTF16 Then
					result :+ "    return bbStringFromWString(bmx_native_result);~n"
				Else
					result :+ "    return bmx_native_result;~n"
				End If
			End If
			result :+ "}~n~n"
		Next
		Return result
	End Method

	Function HasNativeStringParameters:Int(externalFunction:TCompilerIrExternalFunction)
		If Not externalFunction Then Return False
		For Local parameter:TCompilerIrParameter = EachIn externalFunction.parameters
			If parameter.nativeStringEncoding <> NATIVE_STRING_NONE Then Return True
		Next
		Return False
	End Function

	Function NeedsNativeStringWrapper:Int(externalFunction:TCompilerIrExternalFunction)
		Return externalFunction And (HasNativeStringParameters(externalFunction) Or externalFunction.nativeStringReturnEncoding <> NATIVE_STRING_NONE)
	End Function

	Method CNativeFunctionDeclaration:String(externalFunction:TCompilerIrExternalFunction, name:String, parameters:String)
		If externalFunction.nativeStringReturnEncoding = NATIVE_STRING_UTF8 Then
			Return "BBBYTE * " + CCallingConvention(externalFunction.callingConvention) + name + "(" + parameters + ")"
		End If
		If externalFunction.nativeStringReturnEncoding = NATIVE_STRING_UTF16 Then
			Return "BBChar * " + CCallingConvention(externalFunction.callingConvention) + name + "(" + parameters + ")"
		End If
		Return CFunctionDeclaration(externalFunction.returnType, externalFunction.callableReturnType, externalFunction.callableReturnParameters, name, parameters, externalFunction.source, externalFunction.callingConvention, externalFunction.callableReturnCallingConvention)
	End Method

	Function NativeStringWrapperName:String(externalFunction:TCompilerIrExternalFunction)
		Return "bmx_native_string_" + SafeIdentifier(externalFunction.functionId + "_" + externalFunction.sourceName)
	End Function

	Method HeaderOwnsExternal:Int(irModule:TCompilerIrModule, originModule:String, originPath:String = "")
		If Not irModule Then Return False
		Local normalized:String = originModule.ToLower()
		' brl.classes is loaded from blitz_classes.i, but every runtime unit
		' already includes blitz.h, which is authoritative for these C pointer
		' spellings and static String helpers.
		If runtimeTypes And normalized = "brl.classes" Then Return True
		For Local logicalName:String = EachIn irModule.headerOwnedModules
			If logicalName = normalized Then Return True
		Next
		' A quoted companion source is not a nominal module and therefore does
		' not belong in headerOwnedModules. Its generated header is nevertheless
		' included directly by this runtime unit and is authoritative for native
		' declarations published by that companion interface.
		If irModule.initializationPlan Then
			For Local dependency:TCompilerIrDependency = EachIn irModule.initializationPlan.dependencies
				If dependency.logicalName.ToLower() = normalized And dependency.headerPath.length Then Return True
				If originPath.length And dependency.headerPath.length Then
					Local normalizedOriginPath:String = originPath.Replace("\", "/").ToLower()
					Local normalizedInterfacePath:String = dependency.interfacePath.Replace("\", "/").ToLower()
					If normalizedOriginPath = normalizedInterfacePath Or normalizedOriginPath = InterfaceSourcePath(normalizedInterfacePath) Then Return True
				End If
			Next
		End If
		Return False
	End Method

	' A generated interface for a quoted source lives under .bmx while its
	' declaration provenance points back to the physical source beside that
	' directory. Header authority follows either spelling; semantic module
	' ownership deliberately does not encode this physical distinction.
	Function InterfaceSourcePath:String(interfacePath:String)
		Local normalized:String = interfacePath.Replace("\", "/")
		Local interfaceDirectory:String = ExtractDir(normalized)
		If StripDir(interfaceDirectory).ToLower() <> ".bmx" Then Return normalized
		Local fileName:String = StripDir(normalized)
		Local marker:Int = fileName.ToLower().Find(".bmx.")
		If marker < 0 Then Return normalized
		Return ExtractDir(interfaceDirectory) + "/" + fileName[..marker + 4]
	End Function

	Method AppendGlobals(irModule:TCompilerIrModule, result:TStringBuilder)
		Local emitted:Int
		For Local variable:TCompilerIrVariableDeclaration = EachIn allVariables
			If Not variable Or (variable.storage <> "global" And variable.storage <> "constant") Then Continue
			' Constants are compile-time values. Symbol references lower to
			' literals, so emitting storage only creates unused C objects.
			If variable.storage = "constant" Then Continue
			Local name:String = String(globalNames.ValueForKey(variable.symbolId))
			Local storagePrefix:String = "static "
			If variable.isPublished Or variable.isSpecializationLinked Then storagePrefix = ""
			If variable.isThreadedGlobal Then storagePrefix :+ "BBThreadLocal "
			If variable.isStaticArray Then
				result.Append(storagePrefix + CType(variable.staticArrayElementType, variable.source) + " " + name + "[" + variable.staticArrayLength + "];~n")
			Else
				result.Append(storagePrefix + CVariableDeclaration(variable, name) + ";~n")
			End If
			emitted = True
		Next
		If emitted Then result.Append("~n")
	End Method

	Method AppendDataSection(irModule:TCompilerIrModule, result:TStringBuilder)
		If Not irModule Or Not ModuleUsesData(irModule) Then Return
		If Not irModule.dataItems.length Then
			result.Append("static struct bbDataDef bmx_data[1];~nstatic struct bbDataDef *bmx_data_offset = bmx_data;~nstatic const BBSIZET bmx_data_count = 0;~n~n")
			Return
		End If
		result.Append("static struct bbDataDef bmx_data[" + irModule.dataItems.length + "] = {~n")
		For Local item:TCompilerIrDataItem = EachIn irModule.dataItems
			Local value:String = item.valueText
			If item.stringLiteralId.length Then value = String(stringNames.ValueForKey(item.stringLiteralId))
			result.Append("    { ~q" + item.typeTag + "~q, { ." + item.unionField + " = " + value + " } },~n")
		Next
		result.Append("};~nstatic struct bbDataDef *bmx_data_offset = bmx_data;~n")
		result.Append("static const BBSIZET bmx_data_count = " + irModule.dataItems.length + ";~n~n")
	End Method

	Method ModuleUsesData:Int(irModule:TCompilerIrModule)
		If irModule.dataItems.length Then Return True
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If BlockUsesData(routine.body) Then Return True
		Next
		Return False
	End Method

	Method BlockUsesData:Int(block:TCompilerIrBlock)
		If Not block Then Return False
		For Local statement:TCompilerIrStatement = EachIn block.statements
			If TCompilerIrDataRead(statement) Or TCompilerIrDataRestore(statement) Then Return True
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				If BlockUsesData(guarded.body) Or BlockUsesData(guarded.finallyBody) Then Return True
				For Local catchClause:TCompilerIrCatch = EachIn guarded.catches
					If BlockUsesData(catchClause.body) Then Return True
				Next
			End If
			Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
			If usingStatement And BlockUsesData(usingStatement.body) Then Return True
			Local conditional:TCompilerIrIf = TCompilerIrIf(statement)
			If conditional Then
				If BlockUsesData(conditional.thenBody) Or BlockUsesData(conditional.elseBody) Then Return True
				For Local clause:TCompilerIrConditionalClause = EachIn conditional.elseIfClauses
					If BlockUsesData(clause.body) Then Return True
				Next
			End If
			Local loopBody:TCompilerIrBlock
			If TCompilerIrWhile(statement) Then loopBody = TCompilerIrWhile(statement).body
			If TCompilerIrRepeat(statement) Then loopBody = TCompilerIrRepeat(statement).body
			If TCompilerIrForRange(statement) Then loopBody = TCompilerIrForRange(statement).body
			If TCompilerIrForEachArray(statement) Then loopBody = TCompilerIrForEachArray(statement).body
			If TCompilerIrForEachString(statement) Then loopBody = TCompilerIrForEachString(statement).body
			If TCompilerIrForEachStaticArray(statement) Then loopBody = TCompilerIrForEachStaticArray(statement).body
			If TCompilerIrForEachObject(statement) Then loopBody = TCompilerIrForEachObject(statement).body
			If loopBody And BlockUsesData(loopBody) Then Return True
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					If BlockUsesData(selectedCase.body) Then Return True
				Next
				If BlockUsesData(selected.defaultBody) Then Return True
			End If
		Next
		Return False
	End Method

	Method EmitPublishedGlobals:String(irModule:TCompilerIrModule)
		Local result:String
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If Not routine.isGlobalEntry Or Not routine.body Then Continue
			For Local statement:TCompilerIrStatement = EachIn routine.body.statements
				Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
				If Not variable Or Not variable.isPublished Or Not variable.abiName.length Then Continue
				Local threadedPrefix:String
				If variable.isThreadedGlobal Then threadedPrefix = "BBThreadLocal "
				If variable.isStaticArray Then
					result :+ "extern " + threadedPrefix + CType(variable.staticArrayElementType, variable.source) + " " + variable.abiName + "[" + variable.staticArrayLength + "];~n"
				Else
					result :+ "extern " + threadedPrefix + CVariableDeclaration(variable, variable.abiName) + ";~n"
				End If
			Next
		Next
		If result.length Then result :+ "~n"
		Return result
	End Method

	Method EmitPrototype:String(routine:TCompilerIrFunction)
		Local parameters:String
		If routine.receiver Then parameters :+ CParameterDeclaration(routine.receiver, LocalName(routine.receiver.symbolId, routine.receiver.name), routine.source)
		For Local index:Int = 0 Until routine.parameters.length
			If index Or routine.receiver Then parameters :+ ", "
			Local parameter:TCompilerIrParameter = routine.parameters[index]
			parameters :+ CParameterDeclaration(parameter, LocalName(parameter.symbolId, parameter.name), routine.source)
		Next
		If Not parameters.length Then parameters = "void"
		Return CFunctionDeclaration(routine.returnType, routine.callableReturnType, routine.callableReturnParameters, FunctionName(routine.functionId), parameters, routine.source, routine.callingConvention, routine.callableReturnCallingConvention)
	End Method

	Method LegacyRoutineAliasName:String(routine:TCompilerIrFunction)
		If Not routine Or routine.isGlobalEntry Or routine.ownerClassId.length Or routine.ownerStructId.length Or routine.ownerInterfaceId.length Or routine.lifecycleKind Or routine.callableReturnType.length Then Return ""
		If routine.suppressLegacyAlias Then Return ""
		Local canonical:String = FunctionName(routine.functionId)
		If routine.legacyAliasName.length And routine.legacyAliasName <> canonical Then Return routine.legacyAliasName
		Local marker:String = "_" + TCompilerAbiNamer.RoutineSourceName(routine.name)
		Local markerIndex:Int = canonical.FindLast(marker)
		If markerIndex < 0 Then Return ""
		Local result:String = canonical[..markerIndex + marker.length]
		If result = canonical Then Return ""
		Return result
	End Method

	Method HasUniqueTopLevelRoutineName:Int(irModule:TCompilerIrModule, routine:TCompilerIrFunction)
		Local matches:Int
		For Local candidate:TCompilerIrFunction = EachIn irModule.functions
			If candidate.isGlobalEntry Or candidate.ownerClassId.length Or candidate.ownerStructId.length Or candidate.ownerInterfaceId.length Or candidate.lifecycleKind Then Continue
			If candidate.name.ToLower() = routine.name.ToLower() Then matches :+ 1
		Next
		Return matches = 1
	End Method

	Method EmitLegacyRoutineAliasPrototype:String(routine:TCompilerIrFunction, aliasName:String)
		Local parameters:String
		For Local index:Int = 0 Until routine.parameters.length
			If index Then parameters :+ ", "
			Local parameter:TCompilerIrParameter = routine.parameters[index]
			parameters :+ CParameterDeclaration(parameter, LocalName(parameter.symbolId, parameter.name), routine.source)
		Next
		If Not parameters.length Then parameters = "void"
		Return CFunctionDeclaration(routine.returnType, "", New TCompilerIrParameter[0], aliasName, parameters, routine.source, routine.callingConvention)
	End Method

	Method EmitLegacyRoutineAliasPrototypes:String(irModule:TCompilerIrModule, publishedOnly:Int)
		Local result:String
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If publishedOnly And routine.visibility <> VISIBILITY_PUBLIC Then Continue
			If Not HasUniqueTopLevelRoutineName(irModule, routine) Then Continue
			Local aliasName:String = LegacyRoutineAliasName(routine)
			If aliasName.length Then result :+ EmitLegacyRoutineAliasPrototype(routine, aliasName) + ";~n"
		Next
		Return result
	End Method

	Method EmitLegacyRoutineAliases:String(irModule:TCompilerIrModule)
		Local result:String
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If Not HasUniqueTopLevelRoutineName(irModule, routine) Then Continue
			Local aliasName:String = LegacyRoutineAliasName(routine)
			If Not aliasName.length Then Continue
			localNames = New TMap
			For Local parameter:TCompilerIrParameter = EachIn routine.parameters
				localNames.Insert(parameter.symbolId, LocalName(parameter.symbolId, parameter.name))
			Next
			result :+ EmitLegacyRoutineAliasPrototype(routine, aliasName) + " { "
			If routine.returnType.ToLower() <> "void" Then result :+ "return "
			result :+ FunctionName(routine.functionId) + "("
			For Local index:Int = 0 Until routine.parameters.length
				If index Then result :+ ", "
				Local parameter:TCompilerIrParameter = routine.parameters[index]
				result :+ LocalName(parameter.symbolId, parameter.name)
			Next
			result :+ "); }~n"
		Next
		Return result
	End Method

	Method EmitFunction:String(routine:TCompilerIrFunction)
		localNames = New TMap
		ResetTemporaries()
		picoRootLocals = New TMap
		picoRootLocalOrder = New TCompilerIrVariableDeclaration[0]
		currentPicoRootFrame = EmbeddedObjectTypes() And (routine.debugInstrumentation Or (currentModule And currentModule.gdbDebug) Or routine.isIteratorFactory Or routine.isIteratorMoveNext Or routine.isIteratorCurrent Or routine.isIteratorClose Or PicoBlockMaySafepoint(routine.body))
		currentIsMain = routine.isGlobalEntry
		Local picoModuleInitializer:Int = currentIsMain And PicoModuleUnit()
		currentDebugInstrumentation = routine.debugInstrumentation
		currentCoverageInstrumentation = routine.coverageInstrumentation
		currentDebugScope = routine.debugScope
		currentReturnType = routine.returnType
		currentCallableReturnType = routine.callableReturnType
		currentCallableReturnParameters = routine.callableReturnParameters
		currentCallableReturnCallingConvention = routine.callableReturnCallingConvention
		currentRoutine = routine
		PrepareGdbLocalNames(routine)
		currentIteratorFactory = Null
		currentIteratorStateClass = Null
		currentIteratorReceiverName = ""
		nextCleanupReturnId = 0
		nextTryFinallyId = 0
		debugStatementIndex = 0
		ResetDebugControlFlow()
		If Not currentIsMain Then
			If routine.receiver Then localNames.Insert(routine.receiver.symbolId, LocalName(routine.receiver.symbolId, routine.receiver.name))
			For Local parameter:TCompilerIrParameter = EachIn routine.parameters
				localNames.Insert(parameter.symbolId, LocalName(parameter.symbolId, parameter.name))
			Next
		End If
		If routine.isIteratorMoveNext Or routine.isIteratorClose Then ConfigureIteratorStorage(routine)
		Local debugDeclarations:String = EmitDebugLocalDeclarations(routine.body, "    ")
		If DebugEnabled() Then debugScopeDepth = 1
		Local body:String
		Local iteratorSpecial:Int = routine.isIteratorFactory Or routine.isIteratorMoveNext Or routine.isIteratorCurrent Or routine.isIteratorClose
		If routine.isAbstract Then
			body :+ "    brl_blitz_NullMethodError();~n"
			If routine.returnType.ToLower() <> "void" Then body :+ "    return " + CurrentReturnDefault(routine.source) + ";~n"
		Else If routine.isIteratorFactory Then
			body :+ EmitIteratorFactoryBody(routine, "    ")
		Else If routine.isIteratorMoveNext Then
			body :+ EmitIteratorMoveNextBody(routine, "    ")
		Else If routine.isIteratorCurrent Then
			body :+ EmitIteratorCurrentBody(routine, "    ")
		Else If routine.isIteratorClose Then
			body :+ EmitIteratorCloseBody(routine, "    ")
		Else If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then
			If routine.ownerStructId.length Then
				body :+ EmitStructConstructorPrologue(routine, LocalName(routine.receiver.symbolId, routine.receiver.name), "    ")
			Else
				Local owner:TCompilerIrClass = ClassById(routine.ownerClassId)
				body :+ EmitConstructorPrologue(owner, LocalName(routine.receiver.symbolId, routine.receiver.name), routine, "    ")
			End If
		End If
		If Not routine.isAbstract And Not iteratorSpecial Then body :+ EmitBlockContents(routine.body, "    ", False)
		body :+ EmitGdbGeneratedLineReset("    ")
		If routine.lifecycleKind = IR_LIFECYCLE_DESTRUCTOR Then
			Local owner:TCompilerIrClass = ClassById(routine.ownerClassId)
			Local receiverName:String = LocalName(routine.receiver.symbolId, routine.receiver.name)
			If EmbeddedObjectTypes() Then
				' The Pico heap owns physical reclamation. Inheritance is rejected
				' for this profile, so there is no runtime base destructor to call.
			Else If owner And owner.baseClassId.length Then
				Local baseClass:TCompilerIrClass = ClassById(owner.baseClassId)
				body :+ "    " + EffectiveDestructorName(baseClass) + "((" + EffectiveDestructorReceiverType(baseClass) + ")" + receiverName + ");~n"
			Else If owner And owner.baseImportedClassId.length Then
				Local importedBase:TCompilerIrImportedClass = ImportedClassById(owner.baseImportedClassId)
				If importedBase And importedBase.destructorFunctionId.length Then
					body :+ "    " + FunctionName(importedBase.destructorFunctionId) + "((" + ImportedDestructorReceiverType(importedBase) + ")" + receiverName + ");~n"
				Else
					body :+ "    bbObjectDtor((BBOBJECT)" + receiverName + ");~n"
				End If
			Else
				body :+ "    bbObjectDtor((BBOBJECT)" + receiverName + ");~n"
			End If
		End If
		If DebugEnabled() Then body :+ "    bbOnDebugLeaveScope();~n"
		body :+ EmitPicoRootFrameLeave("    ")
		If currentIsMain Then body :+ "    return 0;~n"
		If Not currentIsMain And Not routine.isAbstract And Not iteratorSpecial And routine.returnType.ToLower() <> "void" Then
			body :+ "    return " + CurrentReturnDefault(routine.source) + ";~n"
		End If
		Local result:String = EmitGdbLineDirective(routine.source, "")
		If picoModuleInitializer Then
			result :+ "int " + currentModule.initializationPlan.initializeFunctionName + "(void)"
		Else If currentIsMain Then
			result :+ "int main(void)"
		Else
			result :+ EmitPrototype(routine)
		End If
		result :+ " {~n"
		If picoModuleInitializer Then
			Local moduleGuard:String = SafeIdentifier(currentModule.initializationPlan.initializeFunctionName + "_inited")
			result :+ "    static int " + moduleGuard + " = 0;~n    if (" + moduleGuard + ") return 0;~n    " + moduleGuard + " = 1;~n"
		End If
		result :+ EmitTemporaryDeclarations("    ")
		result :+ EmitPicoRootLocalDeclarations("    ")
		If picoModuleInitializer Then
			result :+ EmitPicoIncbinRegistration("    ")
			result :+ EmitPicoPersistentGlobalRootSetup("    ")
		Else If currentIsMain And EmbeddedObjectTypes() Then
			result :+ "    bmx_pico_modules_init();~n"
			result :+ EmitPicoIncbinRegistration("    ")
		End If
		result :+ EmitPicoRootFrameSetup("    ", Not picoModuleInitializer)
		result :+ debugDeclarations
		result :+ EmitCoverageFunctionEntry(routine, "    ")
		result :+ EmitDebugScope(currentDebugScope, "    ")
		result :+ body
		Return result + "}~n" + EmitGdbGeneratedLineReset()
	End Method

	Method ConfigureIteratorStorage(routine:TCompilerIrFunction)
		currentIteratorFactory = FunctionById(routine.iteratorFactoryFunctionId)
		currentIteratorStateClass = ClassById(routine.iteratorStateClassId)
		If Not currentIteratorFactory Or Not currentIteratorStateClass Or Not routine.receiver Then Return
		currentIteratorReceiverName = LocalName(routine.receiver.symbolId, routine.receiver.name)
		For Local stateField:TCompilerIrClassField = EachIn currentIteratorStateClass.fields
			localNames.Insert(stateField.fieldId, currentIteratorReceiverName + "->" + FieldName(stateField.declaringClassId, stateField.fieldId))
		Next
		If currentIteratorFactory.receiver And currentIteratorFactory.iteratorSelfFieldId.length Then
			localNames.Insert(currentIteratorFactory.receiver.symbolId, IteratorFieldExpression(currentIteratorFactory.iteratorSelfFieldId))
		End If
	End Method

	Method IteratorFieldExpression:String(fieldId:String)
		If Not currentIteratorStateClass Or Not currentIteratorReceiverName.length Then Return "0"
		Return currentIteratorReceiverName + "->" + FieldName(currentIteratorStateClass.classId, fieldId)
	End Method

	Method EmitIteratorFactoryBody:String(factory:TCompilerIrFunction, indent:String)
		Local stateClass:TCompilerIrClass = ClassById(factory.iteratorStateClassId)
		If Not stateClass Then
			AddDiagnostic("BMXC2095", "iterator factory has no generated state class", factory.source)
			Return indent + "return " + CurrentReturnDefault(factory.source) + ";~n"
		End If
		Local objectType:String = "struct " + ObjectName(stateClass.classId) + " *"
		Local stateName:String = "bmx_iterator_state_" + SafeIdentifier(factory.functionId)
		Local result:String = indent + objectType + stateName + " = (" + objectType + ")bbObjectNew((BBClass *)&" + DescriptorName(stateClass.classId) + ");~n"
		result :+ indent + stateName + "->" + FieldName(stateClass.classId, factory.iteratorStateFieldId) + " = 0;~n"
		If factory.receiver And factory.iteratorSelfFieldId.length Then
			result :+ indent + stateName + "->" + FieldName(stateClass.classId, factory.iteratorSelfFieldId) + " = " + LocalName(factory.receiver.symbolId, factory.receiver.name) + ";~n"
		End If
		For Local parameter:TCompilerIrParameter = EachIn factory.parameters
			result :+ indent + stateName + "->" + FieldName(stateClass.classId, parameter.symbolId) + " = " + LocalName(parameter.symbolId, parameter.name) + ";~n"
		Next
		Return result + indent + "return (" + CType(factory.returnType, factory.source) + ")" + stateName + ";~n"
	End Method

	Method EmitIteratorMoveNextBody:String(routine:TCompilerIrFunction, indent:String)
		If Not currentIteratorFactory Or Not currentIteratorStateClass Then
			AddDiagnostic("BMXC2095", "iterator MoveNext has no generated factory state", routine.source)
			Return indent + "return 0;~n"
		End If
		Local stateExpression:String = IteratorFieldExpression(currentIteratorFactory.iteratorStateFieldId)
		Local ownsResources:Int = currentIteratorFactory.iteratorOwnedResources.length > 0
		Local states:Int[]
		CollectIteratorResumeStates(routine.body, states)
		Local bodyIndent:String = indent
		Local result:String
		Local exceptionName:String = "bmx_iterator_" + SafeIdentifier(routine.functionId) + "_exception"
		Local failedName:String = "bmx_iterator_" + SafeIdentifier(routine.functionId) + "_failed"
		If ownsResources Then
			result :+ indent + "BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
			result :+ indent + "BBINT " + failedName + " = 0;~n"
			result :+ indent + "bbExTry {~n"
			result :+ indent + "case 0: {~n"
			If DebugEnabled() Then result :+ indent + "    bbOnDebugPushExState();~n"
			bodyIndent :+ "    "
		End If
		result :+ bodyIndent + "switch (" + stateExpression + ") {~n"
		result :+ bodyIndent + "    case 0: " + stateExpression + " = -1; break;~n"
		For Local resumeState:Int = EachIn states
			Local resumeTarget:String = IteratorResumeTarget(routine.body, resumeState)
			result :+ bodyIndent + "    case " + resumeState + ": "
			If resumeTarget = "bmx_iterator_resume_" + resumeState Then result :+ stateExpression + " = -1; "
			result :+ "goto " + resumeTarget + ";~n"
		Next
		result :+ bodyIndent + "    default:"
		If ownsResources Then
			result :+ " bbExLeave();"
			If DebugEnabled() Then result :+ " bbOnDebugPopExState();"
		End If
		result :+ " return 0;~n"
		result :+ bodyIndent + "}~n"
		result :+ EmitBlockContents(routine.body, bodyIndent, False)
		result :+ bodyIndent + stateExpression + " = -1;~n"
		If Not ownsResources Then Return result + bodyIndent + "return 0;~n"
		result :+ bodyIndent + "bbExLeave();~n"
		If DebugEnabled() Then result :+ bodyIndent + "bbOnDebugPopExState();~n"
		result :+ bodyIndent + "return 0;~n"
		result :+ indent + "} break;~n"
		result :+ indent + "case 1: {~n"
		If DebugEnabled() Then result :+ indent + "    bbOnDebugPopExState();~n"
		result :+ indent + "    " + exceptionName + " = bbExCatch();~n"
		result :+ indent + "    " + failedName + " = 1;~n"
		result :+ indent + "} break;~n"
		result :+ indent + "}~n"
		result :+ EmitIteratorOwnedCleanup(currentIteratorFactory, indent)
		result :+ indent + "if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
		Return result + indent + "return 0;~n"
	End Method

	Method EmitIteratorCurrentBody:String(routine:TCompilerIrFunction, indent:String)
		Local factory:TCompilerIrFunction = FunctionById(routine.iteratorFactoryFunctionId)
		Local stateClass:TCompilerIrClass = ClassById(routine.iteratorStateClassId)
		If Not factory Or Not stateClass Or Not routine.receiver Then Return indent + "return " + CurrentReturnDefault(routine.source) + ";~n"
		Local receiverName:String = LocalName(routine.receiver.symbolId, routine.receiver.name)
		Return indent + "return " + receiverName + "->" + FieldName(stateClass.classId, factory.iteratorCurrentFieldId) + ";~n"
	End Method

	Method EmitIteratorCloseBody:String(routine:TCompilerIrFunction, indent:String)
		Local factory:TCompilerIrFunction = FunctionById(routine.iteratorFactoryFunctionId)
		Local stateClass:TCompilerIrClass = ClassById(routine.iteratorStateClassId)
		If Not factory Or Not stateClass Or Not routine.receiver Then Return indent + "return;~n"
		Local receiverName:String = LocalName(routine.receiver.symbolId, routine.receiver.name)
		Local stateExpression:String = receiverName + "->" + FieldName(stateClass.classId, factory.iteratorStateFieldId)
		Local yields:TCompilerIrYield[]
		' The original yielding body is transferred to MoveNext when the iterator
		' state machine is built; the factory body is then replaced by the state
		' object constructor. Close must inspect the transferred body so it can
		' run the cleanup chain belonging to the current suspension point.
		Local moveNext:TCompilerIrFunction = FunctionById(factory.iteratorMoveNextFunctionId)
		If moveNext Then CollectIteratorYields(moveNext.body, yields)
		Local result:String
		If yields.length Then
			result :+ indent + "switch (" + stateExpression + ") {~n"
			For Local yielded:TCompilerIrYield = EachIn yields
				result :+ indent + "    case " + yielded.resumeState + ":~n"
				result :+ indent + "        " + stateExpression + " = -1;~n"
				result :+ EmitIteratorCloseCleanupSteps(yielded.cleanupSteps, 0, indent + "        ")
				result :+ indent + "        break;~n"
			Next
			result :+ indent + "    default: " + stateExpression + " = -1; break;~n"
			result :+ indent + "}~n"
		Else
			result :+ indent + stateExpression + " = -1;~n"
		End If
		result :+ EmitIteratorOwnedCleanup(factory, indent)
		Return result + indent + "return;~n"
	End Method

	Method CollectIteratorYields(block:TCompilerIrBlock, yields:TCompilerIrYield[] Var)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local yielded:TCompilerIrYield = TCompilerIrYield(statement)
			If yielded Then yields :+ [yielded]
			Local conditional:TCompilerIrIf = TCompilerIrIf(statement)
			If conditional Then
				CollectIteratorYields(conditional.thenBody, yields)
				For Local clause:TCompilerIrConditionalClause = EachIn conditional.elseIfClauses
					CollectIteratorYields(clause.body, yields)
				Next
				CollectIteratorYields(conditional.elseBody, yields)
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					CollectIteratorYields(selectedCase.body, yields)
				Next
				CollectIteratorYields(selected.defaultBody, yields)
			End If
			Local nested:TCompilerIrBlock
			If TCompilerIrWhile(statement) Then nested = TCompilerIrWhile(statement).body
			If TCompilerIrRepeat(statement) Then nested = TCompilerIrRepeat(statement).body
			If TCompilerIrForRange(statement) Then nested = TCompilerIrForRange(statement).body
			If TCompilerIrForEachArray(statement) Then nested = TCompilerIrForEachArray(statement).body
			If TCompilerIrForEachString(statement) Then nested = TCompilerIrForEachString(statement).body
			If TCompilerIrForEachStaticArray(statement) Then nested = TCompilerIrForEachStaticArray(statement).body
			If TCompilerIrForEachObject(statement) Then nested = TCompilerIrForEachObject(statement).body
			If TCompilerIrUsing(statement) Then nested = TCompilerIrUsing(statement).body
			If nested Then CollectIteratorYields(nested, yields)
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				CollectIteratorYields(guarded.body, yields)
				For Local handler:TCompilerIrCatch = EachIn guarded.catches
					CollectIteratorYields(handler.body, yields)
				Next
				CollectIteratorYields(guarded.finallyBody, yields)
			End If
		Next
	End Method

	Method EmitIteratorCloseCleanupSteps:String(steps:TCompilerIrCleanupStep[], index:Int, indent:String)
		While index < steps.length And (Not steps[index] Or (Not steps[index].usingResources.length And Not steps[index].finallyBody))
			index :+ 1
		Wend
		If index >= steps.length Then Return ""
		Local cleanupStep:TCompilerIrCleanupStep = steps[index]
		Local cleanupId:Int = nextTryFinallyId
		nextTryFinallyId :+ 1
		Local exceptionName:String = "bmx_iterator_close_exception_" + cleanupId
		Local failedName:String = "bmx_iterator_close_failed_" + cleanupId
		' bbExTry declares its jump buffer with a fixed macro-local name. Give
		' every cleanup step a C scope so multiple pending Finally/Using steps
		' can be emitted sequentially without redeclaring that name.
		Local result:String = indent + "{~n"
		Local stepIndent:String = indent + "    "
		result :+ stepIndent + "BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
		result :+ stepIndent + "BBINT " + failedName + " = 0;~n"
		result :+ stepIndent + "bbExTry {~n"
		result :+ stepIndent + "case 0: {~n"
		If DebugEnabled() Then result :+ stepIndent + "    bbOnDebugPushExState();~n"
		If cleanupStep.usingResources.length Then result :+ EmitUsingCleanup(cleanupStep.usingResources, stepIndent + "    ", True)
		If cleanupStep.finallyBody Then result :+ EmitBlockContents(cleanupStep.finallyBody, stepIndent + "    ")
		result :+ stepIndent + "    bbExLeave();~n"
		If DebugEnabled() Then result :+ stepIndent + "    bbOnDebugPopExState();~n"
		result :+ stepIndent + "} break;~n"
		result :+ stepIndent + "case 1: {~n"
		If DebugEnabled() Then result :+ stepIndent + "    bbOnDebugPopExState();~n"
		result :+ stepIndent + "    " + exceptionName + " = bbExCatch(); " + failedName + " = 1;~n"
		result :+ stepIndent + "} break;~n"
		result :+ stepIndent + "}~n"
		result :+ EmitIteratorCloseCleanupSteps(steps, index + 1, stepIndent)
		result :+ stepIndent + "if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
		result :+ indent + "}~n"
		Return result
	End Method

	Method EmitIteratorOwnedCleanup:String(factory:TCompilerIrFunction, indent:String)
		If Not factory Then Return ""
		Local result:String
		For Local index:Int = factory.iteratorOwnedResources.length - 1 To 0 Step -1
			result :+ EmitUsingCleanup([factory.iteratorOwnedResources[index]], indent, True)
		Next
		Return result
	End Method

	Method CollectIteratorResumeStates(block:TCompilerIrBlock, states:Int[] Var)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local yielded:TCompilerIrYield = TCompilerIrYield(statement)
			If yielded Then states :+ [yielded.resumeState]
			Local conditionalIf:TCompilerIrIf = TCompilerIrIf(statement)
			If conditionalIf Then
				CollectIteratorResumeStates(conditionalIf.thenBody, states)
				For Local clause:TCompilerIrConditionalClause = EachIn conditionalIf.elseIfClauses
					CollectIteratorResumeStates(clause.body, states)
				Next
				CollectIteratorResumeStates(conditionalIf.elseBody, states)
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					CollectIteratorResumeStates(selectedCase.body, states)
				Next
				CollectIteratorResumeStates(selected.defaultBody, states)
			End If
			Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
			If whileStatement Then CollectIteratorResumeStates(whileStatement.body, states)
			Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
			If repeatStatement Then CollectIteratorResumeStates(repeatStatement.body, states)
			Local rangeStatement:TCompilerIrForRange = TCompilerIrForRange(statement)
			If rangeStatement Then CollectIteratorResumeStates(rangeStatement.body, states)
			Local eachArray:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
			If eachArray Then CollectIteratorResumeStates(eachArray.body, states)
			Local eachString:TCompilerIrForEachString = TCompilerIrForEachString(statement)
			If eachString Then CollectIteratorResumeStates(eachString.body, states)
			Local eachStatic:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
			If eachStatic Then CollectIteratorResumeStates(eachStatic.body, states)
			Local eachObject:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
			If eachObject Then CollectIteratorResumeStates(eachObject.body, states)
			Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
			If usingStatement Then CollectIteratorResumeStates(usingStatement.body, states)
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				CollectIteratorResumeStates(guarded.body, states)
				For Local handler:TCompilerIrCatch = EachIn guarded.catches
					CollectIteratorResumeStates(handler.body, states)
				Next
				CollectIteratorResumeStates(guarded.finallyBody, states)
			End If
		Next
	End Method

	Method IteratorTryEntryLabel:String(guarded:TCompilerIrTry)
		Return "bmx_iterator_" + SafeIdentifier(guarded.tryId) + "_entry"
	End Method

	Method IteratorTryCatchEntryLabel:String(guarded:TCompilerIrTry)
		Return "bmx_iterator_" + SafeIdentifier(guarded.tryId) + "_catch_entry"
	End Method

	Method IteratorBlockHasResumeState:Int(block:TCompilerIrBlock, resumeState:Int)
		If Not block Then Return False
		Local states:Int[]
		CollectIteratorResumeStates(block, states)
		For Local candidate:Int = EachIn states
			If candidate = resumeState Then Return True
		Next
		Return False
	End Method

	Method IteratorResumeTarget:String(block:TCompilerIrBlock, resumeState:Int)
		If Not block Then Return "bmx_iterator_resume_" + resumeState
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local yielded:TCompilerIrYield = TCompilerIrYield(statement)
			If yielded And yielded.resumeState = resumeState Then Return "bmx_iterator_resume_" + resumeState
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				If IteratorBlockHasResumeState(guarded.body, resumeState) Then
					If guarded.retainedInIterator Then
						If guarded.finallyBody Then Return IteratorTryEntryLabel(guarded)
						Return IteratorTryCatchEntryLabel(guarded)
					End If
					Return IteratorResumeTarget(guarded.body, resumeState)
				End If
				For Local handler:TCompilerIrCatch = EachIn guarded.catches
					If IteratorBlockHasResumeState(handler.body, resumeState) Then
						If guarded.retainedInIterator And guarded.finallyBody Then Return IteratorTryEntryLabel(guarded)
						Return IteratorResumeTarget(handler.body, resumeState)
					End If
				Next
				If IteratorBlockHasResumeState(guarded.finallyBody, resumeState) Then Return IteratorResumeTarget(guarded.finallyBody, resumeState)
			End If
			Local nestedBlock:TCompilerIrBlock
			If TCompilerIrWhile(statement) Then nestedBlock = TCompilerIrWhile(statement).body
			If TCompilerIrRepeat(statement) Then nestedBlock = TCompilerIrRepeat(statement).body
			If TCompilerIrForRange(statement) Then nestedBlock = TCompilerIrForRange(statement).body
			If TCompilerIrForEachArray(statement) Then nestedBlock = TCompilerIrForEachArray(statement).body
			If TCompilerIrForEachString(statement) Then nestedBlock = TCompilerIrForEachString(statement).body
			If TCompilerIrForEachStaticArray(statement) Then nestedBlock = TCompilerIrForEachStaticArray(statement).body
			If TCompilerIrForEachObject(statement) Then nestedBlock = TCompilerIrForEachObject(statement).body
			If TCompilerIrUsing(statement) Then nestedBlock = TCompilerIrUsing(statement).body
			If nestedBlock And IteratorBlockHasResumeState(nestedBlock, resumeState) Then Return IteratorResumeTarget(nestedBlock, resumeState)
			Local conditional:TCompilerIrIf = TCompilerIrIf(statement)
			If conditional Then
				If IteratorBlockHasResumeState(conditional.thenBody, resumeState) Then Return IteratorResumeTarget(conditional.thenBody, resumeState)
				For Local clause:TCompilerIrConditionalClause = EachIn conditional.elseIfClauses
					If IteratorBlockHasResumeState(clause.body, resumeState) Then Return IteratorResumeTarget(clause.body, resumeState)
				Next
				If IteratorBlockHasResumeState(conditional.elseBody, resumeState) Then Return IteratorResumeTarget(conditional.elseBody, resumeState)
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					If IteratorBlockHasResumeState(selectedCase.body, resumeState) Then Return IteratorResumeTarget(selectedCase.body, resumeState)
				Next
				If IteratorBlockHasResumeState(selected.defaultBody, resumeState) Then Return IteratorResumeTarget(selected.defaultBody, resumeState)
			End If
		Next
		Return "bmx_iterator_resume_" + resumeState
	End Method

	Method DebugEnabled:Int()
		Return runtimeTypes And currentDebugInstrumentation And currentDebugScope
	End Method

	Method DebugSafetyEnabled:Int()
		Return runtimeTypes And currentDebugInstrumentation
	End Method

	Method ResetDebugControlFlow()
		debugScopeDepth = 0
		predeclaredDebugLocals = New TMap
		loopContinueDebugDepths = New TMap
		loopExitDebugDepths = New TMap
		cleanupResourceDebugDepths = New TMap
		cleanupFinallyDebugDepths = New TMap
	End Method

	Method EmitDebugScope:String(scope:TCompilerIrDebugScope, indent:String)
		If Not DebugEnabled() Or Not scope Then Return ""
		Local count:Int = scope.variables.length
		Local storageCount:Int = count + 1
		Local result:String = indent + "struct { unsigned int kind; const char *name; BBDebugDecl decls[" + storageCount + "]; } bmx_debug_scope = {~n"
		Local scopeKind:String = "BBDEBUGSCOPE_FUNCTION"
		Local scopeName:String = CQuoted(scope.name)
		If scope.scopeKind = IR_DEBUG_SCOPE_LOCAL_BLOCK Then
			scopeKind = "BBDEBUGSCOPE_LOCALBLOCK"
			scopeName = "0"
		End If
		result :+ indent + "    " + scopeKind + ", " + scopeName + ", {~n"
		For Local variable:TCompilerIrDebugVariable = EachIn scope.variables
			Local typeTag:String = DebugVariableTypeTag(variable)
			If typeTag = "?" Then
				AddDiagnostic("BMXC2084", "Debug variable '" + variable.name + "' has no complete typetag for semantic type '" + variable.semanticType + "'", Null)
				Continue
			End If
			If variable.declarationKind = IR_DEBUG_DECL_CONSTANT Then
				result :+ indent + "        { BBDEBUGDECL_CONST, " + CQuoted(variable.name) + ", " + CQuoted(typeTag) + ", .const_value = " + RuntimeStringPointer(variable.constantStringLiteralId) + ", .reflection_wrapper = 0 },~n"
				Continue
			End If
			If variable.declarationKind = IR_DEBUG_DECL_GLOBAL Then
				Local globalAddress:String = SymbolName(variable.symbolId, variable.name)
				result :+ indent + "        { BBDEBUGDECL_GLOBAL, " + CQuoted(variable.name) + ", " + CQuoted(typeTag) + ", .var_address = (void *)&" + globalAddress + ", .reflection_wrapper = 0 },~n"
				Continue
			End If
			Local kind:String = "BBDEBUGDECL_LOCAL"
			If variable.passingMode = PARAMETER_PASS_VAR Then kind = "BBDEBUGDECL_VARPARAM"
			Local address:String = LocalName(variable.symbolId, variable.name)
			If variable.isReceiver Then address = LocalName(variable.symbolId, "self")
			Local addressExpression:String = "&" + address
			If variable.address Then addressExpression = "&(" + EmitExpression(variable.address) + ")"
			Local normalizedType:String = variable.semanticType.Trim().ToLower()
			If Not variable.address And variable.isReceiver And (structTypes.Contains(normalizedType) Or importedStructTypes.Contains(normalizedType)) Then addressExpression = address
			If variable.passingMode = PARAMETER_PASS_VAR Then typeTag = "&" + typeTag
			result :+ indent + "        { " + kind + ", " + CQuoted(variable.name) + ", " + CQuoted(typeTag) + ", .var_address = " + addressExpression + ", .reflection_wrapper = 0 },~n"
		Next
		result :+ indent + "        { BBDEBUGDECL_END, 0, 0, .var_address = 0, .reflection_wrapper = 0 }~n"
		result :+ indent + "    }~n" + indent + "};~n"
		result :+ indent + "bbOnDebugEnterScope((BBDebugScope *)&bmx_debug_scope);~n"
		Return result
	End Method

	Method DebugVariableTypeTag:String(variable:TCompilerIrDebugVariable)
		If Not variable Then Return "?"
		If variable.arrayCallableReturnType.length Then
			Return ArrayCallableDebugTypeTag(variable.arrayCallableReturnType, variable.arrayCallableParameters, variable.arrayCallableRank, variable.arrayCallableCallingConvention)
		End If
		If variable.callableReturnType.length Then
			Return CallableDebugTypeTag(variable.callableReturnType, variable.callableParameters, variable.callableCallingConvention)
		End If
		Return DebugTypeTag(variable.semanticType)
	End Method

	Method EmitDebugLocalDeclarations:String(block:TCompilerIrBlock, indent:String)
		If Not DebugEnabled() Or Not block Then Return ""
		Local result:String
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
			If Not variable Or variable.storage <> "local" Then Continue
			Local name:String = LocalName(variable.symbolId, variable.name)
			localNames.Insert(variable.symbolId, name)
			predeclaredDebugLocals.Insert(variable.symbolId, variable)
			If variable.isStaticArray Then
				result :+ indent + CType(variable.staticArrayElementType, variable.source) + " " + name + "[" + variable.staticArrayLength + "] = {0};~n"
				result :+ EmitStaticArrayInitialization(variable, name, indent)
			Else
				result :+ indent + CVariableDeclaration(variable, name) + " = " + DebugLocalDefault(variable) + ";~n"
			End If
		Next
		Return result
	End Method

	Method DebugLocalDefault:String(variable:TCompilerIrVariableDeclaration)
		If Not variable Then Return "0"
		If Not variable.hasExplicitInitializer And variable.initializer Then Return EmitExpression(variable.initializer)
		If variable.callableReturnType.length Then Return CallableSentinel(variable.callableReturnType, variable.callableParameters, variable.source, variable.callableCallingConvention)
		Local normalized:String = variable.semanticType.Trim().ToLower()
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(normalized))
		Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(normalized))
		If irStruct Or importedStruct Then
			Local helperName:String = StructDefaultHelperName(variable.semanticType)
			If helperName.length Then Return helperName + "()"
		End If
		Local irEnum:TCompilerIrEnum = TCompilerIrEnum(enumTypes.ValueForKey(normalized))
		If irEnum Then
			If irEnum.isFlags Then Return "0"
			If irEnum.values.length Then Return String(irEnum.values[0].integerValue)
		End If
		Return CDefaultValue(variable.semanticType)
	End Method

	Method EmitDebugLeaves:String(count:Int, indent:String)
		If Not DebugEnabled() Or count <= 0 Then Return ""
		Local result:String
		For Local index:Int = 0 Until count
			result :+ indent + "bbOnDebugLeaveScope();~n"
		Next
		Return result
	End Method

	Method EmitDebugStatement:String(source:TCompilerSourceLocation, indent:String)
		If Not DebugEnabled() Or Not source Or source.debugSourceId = 0 Then Return ""
		Local name:String = "bmx_debug_stm_" + debugStatementIndex
		debugStatementIndex :+ 1
		Local result:String = indent + "BBDebugStm " + name + " = { " + source.debugSourceId + "ULL, " + source.line + ", " + source.column + " };~n"
		Return result + indent + "bbOnDebugEnterStm(&" + name + ");~n"
	End Method

	Method DebugTypeTag:String(typeName:String)
		typeName = typeName.Trim()
		Local normalized:String = typeName.ToLower()
		Local irEnum:TCompilerIrEnum = TCompilerIrEnum(enumTypes.ValueForKey(normalized))
		If irEnum Then Return "/" + irEnum.name
		If normalized.EndsWith("]") Then
			Local openBracket:Int = typeName.FindLast("[")
			If openBracket >= 0 Then
				Local elementType:String = typeName[..openBracket].Trim()
				If elementType.ToLower().StartsWith("staticarray ") Then elementType = elementType[12..].Trim()
				Local elementTag:String = DebugTypeTag(elementType)
				If elementTag = "?" Then Return "?"
				Return typeName[openBracket..] + elementTag
			End If
		End If
		If normalized.StartsWith("closure<") Then Return ClosureDebugTypeTag(typeName)
		If normalized.EndsWith(" ptr") Then
			Local elementType:String = typeName[..typeName.length - 4].Trim()
			Local elementTag:String = DebugTypeTag(elementType)
			If elementTag = "?" Then Return "?"
			Return "*" + elementTag
		End If
		' Runtime reflection resolves class tags nominally, regardless of
		' whether the class descriptor is owned by this C unit or an imported
		' module.  "#" is the old unsupported extern-type marker and causes
		' Reflection to discard fields such as MaxUnit's imported TMethod slots.
		If importedClassTypes.Contains(normalized) Then Return ":" + typeName
		If interfaceTypes.Contains(normalized) Then
			Local irInterface:TCompilerIrInterface = TCompilerIrInterface(interfaceTypes.ValueForKey(normalized))
			If irInterface And irInterface.isExternInterface Then Return "*#" + typeName
			If irInterface And irInterface.isImported Then Return "*#" + typeName
			Return ":" + typeName
		End If
		If opaqueInterfaceTypes.Contains(normalized) Then Return "*#" + typeName
		If classTypes.Contains(normalized) Then Return ":" + typeName
		If structTypes.Contains(normalized) Or importedStructTypes.Contains(normalized) Then Return "@" + typeName
		Select normalized
			Case "byte" Return "b"
			Case "short" Return "s"
			Case "int" Return "i"
			Case "uint" Return "u"
			Case "long" Return "l"
			Case "ulong" Return "y"
			Case "longint" Return "v"
			Case "ulongint" Return "e"
			Case "size_t" Return "t"
			Case "wparam" Return "W"
			Case "lparam" Return "X"
			Case "float" Return "f"
			Case "double" Return "d"
			Case "float64" Return "h"
			Case "int128" Return "j"
			Case "float128" Return "k"
			Case "double128" Return "m"
			Case "string" Return "$"
			Case "object" Return ":Object"
		End Select
		Return "?"
	End Method

	Method ClosureDebugTypeTag:String(typeName:String)
		Local text:String = typeName.Trim()
		If Not text.ToLower().StartsWith("closure<") Or Not text.EndsWith(">") Then Return "?"
		Local signature:String = text[8..text.length - 1].Trim()
		Local openParen:Int = TopLevelCallableOpen(signature)
		If openParen < 0 Or Not signature.EndsWith(")") Then Return "?"
		Local returnText:String = signature[..openParen].Trim()
		Local result:String = "!("
		Local parameters:String[] = SplitTopLevelTypes(signature[openParen + 1..signature.length - 1])
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ","
			Local parameterText:String = parameters[index].Trim()
			Local colon:Int = TopLevelTypeColon(parameterText)
			If colon >= 0 Then parameterText = parameterText[colon + 1..].Trim()
			Local isVar:Int = parameterText.ToLower().EndsWith(" var")
			If isVar Then parameterText = parameterText[..parameterText.length - 4].Trim()
			Local parameterTag:String = DebugTypeTag(parameterText)
			If parameterTag = "?" Then Return "?"
			If isVar Then result :+ "&"
			result :+ parameterTag
		Next
		result :+ ")"
		If returnText.length Then
			Local returnTag:String = DebugTypeTag(returnText)
			If returnTag = "?" Then Return "?"
			result :+ returnTag
		End If
		Return result
	End Method

	Function TopLevelCallableOpen:Int(text:String)
		Local angleDepth:Int
		Local bracketDepth:Int
		For Local index:Int = 0 Until text.length
			Select text[index]
				Case Asc("<") angleDepth :+ 1
				Case Asc(">") angleDepth :- 1
				Case Asc("[") bracketDepth :+ 1
				Case Asc("]") bracketDepth :- 1
				Case Asc("(")
					If angleDepth = 0 And bracketDepth = 0 Then Return index
			End Select
		Next
		Return -1
	End Function

	Function TopLevelTypeColon:Int(text:String)
		Local angleDepth:Int
		Local parenDepth:Int
		Local bracketDepth:Int
		For Local index:Int = 0 Until text.length
			Select text[index]
				Case Asc("<") angleDepth :+ 1
				Case Asc(">") angleDepth :- 1
				Case Asc("(") parenDepth :+ 1
				Case Asc(")") parenDepth :- 1
				Case Asc("[") bracketDepth :+ 1
				Case Asc("]") bracketDepth :- 1
				Case Asc(":")
					If angleDepth = 0 And parenDepth = 0 And bracketDepth = 0 Then Return index
			End Select
		Next
		Return -1
	End Function

	Function SplitTopLevelTypes:String[](text:String)
		Local result:String[]
		If Not text.Trim().length Then Return result
		Local start:Int
		Local angleDepth:Int
		Local parenDepth:Int
		Local bracketDepth:Int
		For Local index:Int = 0 To text.length
			Local separator:Int = index = text.length
			If Not separator Then
				Select text[index]
					Case Asc("<") angleDepth :+ 1
					Case Asc(">") angleDepth :- 1
					Case Asc("(") parenDepth :+ 1
					Case Asc(")") parenDepth :- 1
					Case Asc("[") bracketDepth :+ 1
					Case Asc("]") bracketDepth :- 1
					Case Asc(",") separator = angleDepth = 0 And parenDepth = 0 And bracketDepth = 0
				End Select
			End If
			If separator Then
				result :+ [text[start..index].Trim()]
				start = index + 1
			End If
		Next
		Return result
	End Function

	Method DebugObjectReceiver:String(receiver:String, semanticType:String, source:TCompilerSourceLocation)
		If EmbeddedObjectTypes() Then
			If currentDebugInstrumentation Or (currentModule And currentModule.gdbDebug) Then Return "((" + CType(semanticType, source) + ")bmx_pico_object_assert((void *)" + receiver + "))"
			If currentRoutine And currentRoutine.receiver And receiver = LocalName(currentRoutine.receiver.symbolId, currentRoutine.receiver.name) Then Return receiver
			Return "((" + CType(semanticType, source) + ")bmx_pico_object_not_null((void *)" + receiver + "))"
		End If
		If Not DebugSafetyEnabled() Then Return receiver
		Return "((" + CType(semanticType, source) + ")bbNullObjectTest((BBObject *)" + receiver + "))"
	End Method

	Method DebugManagedValue:String(value:String, managedKind:Int, semanticType:String, source:TCompilerSourceLocation)
		If Not DebugSafetyEnabled() Then Return value
		Select managedKind
			Case IR_MANAGED_REFERENCE_STRING
				Return "bbManagedStringAssert((BBSTRING)" + value + ")"
			Case IR_MANAGED_REFERENCE_ARRAY
				Return "bbManagedArrayAssert((BBARRAY)" + value + ")"
			Case IR_MANAGED_REFERENCE_OBJECT, IR_MANAGED_REFERENCE_CLOSURE
				Return "((" + CType(semanticType, source) + ")bbManagedObjectAssert((BBOBJECT)" + value + "))"
		End Select
		Return value
	End Method

	Method EmitStructConstructorPrologue:String(routine:TCompilerIrFunction, receiverName:String, indent:String)
		If Not routine Or Not routine.chainedConstructorFunctionId.length Then Return ""
		Local chained:TCompilerIrFunction = FunctionById(routine.chainedConstructorFunctionId)
		If Not chained Or chained.ownerStructId <> routine.ownerStructId Then
			AddDiagnostic("BMXC2069", "Struct constructor chain target is outside the receiver layout", routine.source)
			Return ""
		End If
		Local irStruct:TCompilerIrStruct = StructById(routine.ownerStructId)
		Local result:String = indent + FunctionName(chained.functionId) + "((struct " + StructName(irStruct.structId) + " *)" + receiverName
		For Local argument:TCompilerIrExpression = EachIn routine.chainedConstructorArguments
			result :+ ", " + EmitExpression(argument)
		Next
		Return result + ");~n"
	End Method

	Method EmitConstructorPrologue:String(irClass:TCompilerIrClass, receiverName:String, routine:TCompilerIrFunction, indent:String)
		If Not irClass Then Return ""
		If EmbeddedObjectTypes() Then Return EmitPicoConstructorPrologue(irClass, receiverName, routine, indent)
		localNames.Insert("self", receiverName)
		Local result:String
		If routine And routine.chainedImportedConstructorId.length Then
			Local importedConstructor:TCompilerIrImportedConstructor = ImportedConstructorById(routine.chainedImportedConstructorId)
			Local importedOwner:TCompilerIrImportedClass
			If importedConstructor Then importedOwner = ImportedClassById(importedConstructor.declaringImportedClassId)
			If Not importedConstructor Or Not importedOwner Or Not importedConstructor.implementationAbiName.length Then
				AddDiagnostic("BMXC2069", "Imported constructor chain has no direct implementation ABI", routine.source)
			Else
				result :+ indent + importedConstructor.implementationAbiName + "((struct " + importedOwner.abiName + "_obj *)" + receiverName
				For Local argument:TCompilerIrExpression = EachIn routine.chainedConstructorArguments
					result :+ ", " + EmitExpression(argument)
				Next
				result :+ ");~n"
			End If
		Else If routine And routine.chainedConstructorFunctionId.length Then
			Local chained:TCompilerIrFunction = FunctionById(routine.chainedConstructorFunctionId)
			Local chainedOwner:TCompilerIrClass
			If chained Then chainedOwner = ClassById(chained.ownerClassId)
			result :+ indent + FunctionName(routine.chainedConstructorFunctionId) + "((struct " + ObjectName(chainedOwner.classId) + " *)" + receiverName
			For Local argument:TCompilerIrExpression = EachIn routine.chainedConstructorArguments
				result :+ ", " + EmitExpression(argument)
			Next
			result :+ ");~n"
			If routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_SAME_TYPE Then
				result :+ indent + receiverName + "->clas = &" + DescriptorName(irClass.classId) + ";~n"
				Return result
			End If
		Else If irClass.baseClassId.length Then
			Local baseClass:TCompilerIrClass = ClassById(irClass.baseClassId)
			Local baseConstructorName:String = ConstructorName(baseClass.classId)
			If baseClass.defaultConstructorFunctionId.length Then baseConstructorName = FunctionName(baseClass.defaultConstructorFunctionId)
			result :+ indent + baseConstructorName + "((struct " + ObjectName(baseClass.classId) + " *)" + receiverName + ");~n"
		Else If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			If importedBase Then result :+ indent + importedBase.abiName + ".ctor((BBOBJECT)" + receiverName + ");~n"
		Else
			result :+ indent + "bbObjectCtor((BBOBJECT)" + receiverName + ");~n"
		End If
		result :+ indent + receiverName + "->clas = &" + DescriptorName(irClass.classId) + ";~n"
		For Local index:Int = irClass.declaredFieldStart Until irClass.declaredFieldStart + irClass.declaredFieldCount
			Local irField:TCompilerIrClassField = irClass.fields[index]
			If irField.isStaticArray Then
				Local elementInitializer:String = CDefaultValue(irField.staticArrayElementType)
				If irField.staticArrayStructId.length Or irField.staticArrayImportedStructId.length Then
					Local helperName:String = ClassFieldStaticArrayDefaultHelperName(irField)
					If helperName.length Then
						elementInitializer = helperName + "()"
					Else
						AddDiagnostic("BMXC2074", "StaticArray Type field '" + irField.name + "' has no element default construction helper", irField.source)
					End If
				End If
				Local staticIndex:String = "bmx_static_field_init_" + SafeIdentifier(irField.fieldId)
				result :+ indent + "for (BBUINT " + staticIndex + " = 0; " + staticIndex + " < (BBUINT)" + irField.staticArrayLength + "; " + staticIndex + " = " + staticIndex + " + 1) {~n"
				result :+ indent + "    " + receiverName + "->" + FieldName(irField.declaringClassId, irField.fieldId) + "[" + staticIndex + "] = " + elementInitializer + ";~n"
				result :+ indent + "}~n"
				Continue
			End If
			Local initializer:String = CDefaultValue(irField.semanticType)
			If irField.initializer Then
				initializer = EmitExpression(irField.initializer)
			Else If structTypes.Contains(irField.semanticType.ToLower()) Or importedStructTypes.Contains(irField.semanticType.ToLower()) Then
				Local helperName:String = StructDefaultHelperName(irField.semanticType)
				If helperName.length Then
					initializer = helperName + "()"
				Else
					AddDiagnostic("BMXC2070", "Struct field '" + irField.name + "' has no default construction helper", irField.source)
				End If
			End If
			result :+ indent + receiverName + "->" + FieldName(irField.declaringClassId, irField.fieldId) + " = " + initializer + ";~n"
		Next
		Return result
	End Method

	Method EmitPicoConstructorPrologue:String(irClass:TCompilerIrClass, receiverName:String, routine:TCompilerIrFunction, indent:String)
		If Not irClass Then Return ""
		localNames.Insert("self", receiverName)
		Local result:String
		If routine And routine.chainedConstructorFunctionId.length Then
			Local chained:TCompilerIrFunction = FunctionById(routine.chainedConstructorFunctionId)
			If Not chained Or (chained.ownerClassId <> irClass.classId And chained.ownerClassId <> irClass.baseClassId) Then
				AddDiagnostic("BMXC2029", "Pico Object constructor chain target is outside the local Type hierarchy", routine.source)
				Return result
			End If
			Local chainedReceiver:String = receiverName
			Local chainedOwner:TCompilerIrClass = ClassById(chained.ownerClassId)
			If chainedOwner Then chainedReceiver = "(struct " + ObjectName(chainedOwner.classId) + " *)" + receiverName
			result :+ indent + FunctionName(chained.functionId) + "(" + chainedReceiver
			For Local argument:TCompilerIrExpression = EachIn routine.chainedConstructorArguments
				result :+ ", " + EmitExpression(argument)
			Next
			result :+ ");~n"
			If routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_SAME_TYPE Then Return result
		End If
		If routine And routine.chainedImportedConstructorId.length Then
			Local importedConstructor:TCompilerIrImportedConstructor = ImportedConstructorById(routine.chainedImportedConstructorId)
			Local importedOwner:TCompilerIrImportedClass
			If importedConstructor Then importedOwner = ImportedClassById(importedConstructor.declaringImportedClassId)
			If Not importedConstructor Or Not importedOwner Or Not importedConstructor.implementationAbiName.length Then
				AddDiagnostic("BMXC2029", "Imported Pico constructor chain has no direct implementation ABI", routine.source)
				Return result
			End If
			result :+ indent + importedConstructor.implementationAbiName + "((struct " + importedOwner.abiName + "_obj *)" + receiverName
			For Local argument:TCompilerIrExpression = EachIn routine.chainedConstructorArguments
				result :+ ", " + EmitExpression(argument)
			Next
			result :+ ");~n"
		End If
		If (Not routine Or Not routine.chainedConstructorFunctionId.length) And irClass.baseClassId.length Then
			Local baseClass:TCompilerIrClass = ClassById(irClass.baseClassId)
			Local baseConstructor:String = ConstructorName(baseClass.classId)
			If baseClass.defaultConstructorFunctionId.length Then baseConstructor = FunctionName(baseClass.defaultConstructorFunctionId)
			result :+ indent + baseConstructor + "((struct " + ObjectName(baseClass.classId) + " *)" + receiverName + ");~n"
		End If
		If (Not routine Or (Not routine.chainedConstructorFunctionId.length And Not routine.chainedImportedConstructorId.length)) And irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			If importedBase Then result :+ indent + PicoBaseInitializerAbiName(importedBase.abiName) + "((struct " + importedBase.abiName + "_obj *)" + receiverName + ");~n"
		End If
		For Local index:Int = irClass.declaredFieldStart Until irClass.declaredFieldStart + irClass.declaredFieldCount
			Local irField:TCompilerIrClassField = irClass.fields[index]
			If irField.isStaticArray Then
				Local elementInitializer:String = CDefaultValue(irField.staticArrayElementType)
				If irField.staticArrayStructId.length Or irField.staticArrayImportedStructId.length Then
					Local staticHelper:String = ClassFieldStaticArrayDefaultHelperName(irField)
					If Not staticHelper.length Then
						AddDiagnostic("BMXC2074", "StaticArray Type field '" + irField.name + "' has no element default construction helper", irField.source)
						Continue
					End If
					elementInitializer = staticHelper + "()"
				End If
				Local staticIndex:String = "bmx_pico_static_field_init_" + SafeIdentifier(irField.fieldId)
				result :+ indent + "for (uint32_t " + staticIndex + " = 0; " + staticIndex + " < (uint32_t)" + irField.staticArrayLength + "; " + staticIndex + " = " + staticIndex + " + 1) {~n"
				result :+ indent + "    " + receiverName + "->" + FieldName(irField.declaringClassId, irField.fieldId) + "[" + staticIndex + "] = " + elementInitializer + ";~n"
				result :+ indent + "}~n"
				Continue
			End If
			If Not irField.callableReturnType.length And Not PicoObjectFieldSupported(irField.semanticType) Then Continue
			Local initializer:String = CDefaultValue(irField.semanticType)
			If irField.initializer Then initializer = EmitExpression(irField.initializer)
			If Not irField.initializer And structTypes.Contains(irField.semanticType.ToLower()) Then
				Local helperName:String = StructDefaultHelperName(irField.semanticType)
				If helperName.length Then initializer = helperName + "()"
			End If
			result :+ indent + receiverName + "->" + FieldName(irField.declaringClassId, irField.fieldId) + " = " + initializer + ";~n"
		Next
		Return result
	End Method

	Method ClassFieldStaticArrayDefaultHelperName:String(irField:TCompilerIrClassField)
		If irField.staticArrayStructId.length Then
			Local elementStruct:TCompilerIrStruct = StructById(irField.staticArrayStructId)
			If Not elementStruct Then Return ""
			Local helperName:String = StructNewHelperName(elementStruct.structId, "")
			For Local functionId:String = EachIn elementStruct.constructorFunctionIds
				Local constructor:TCompilerIrFunction = FunctionById(functionId)
				If constructor And Not constructor.parameters.length Then
					helperName = StructNewHelperName(elementStruct.structId, constructor.functionId)
					Exit
				End If
			Next
			Return helperName
		End If
		If irField.staticArrayImportedStructId.length Then
			Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(irField.staticArrayImportedStructId))
			Return ImportedStructDefaultHelperName(importedStruct)
		End If
		Return ""
	End Method

	Method EffectiveDestructorName:String(irClass:TCompilerIrClass)
		If Not irClass Then Return "bbObjectDtor"
		If irClass.destructorFunctionId.length Then Return FunctionName(irClass.destructorFunctionId)
		If irClass.baseClassId.length Then Return EffectiveDestructorName(ClassById(irClass.baseClassId))
		If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			If importedBase And importedBase.destructorFunctionId.length Then Return FunctionName(importedBase.destructorFunctionId)
		End If
		Return "bbObjectDtor"
	End Method

	Method EffectiveDestructorReceiverType:String(irClass:TCompilerIrClass)
		If Not irClass Then Return "BBOBJECT"
		If irClass.destructorFunctionId.length Then Return "struct " + ObjectName(irClass.classId) + " *"
		If irClass.baseClassId.length Then Return EffectiveDestructorReceiverType(ClassById(irClass.baseClassId))
		If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			If importedBase And importedBase.destructorFunctionId.length Then Return ImportedDestructorReceiverType(importedBase)
		End If
		Return "BBOBJECT"
	End Method

	Method ImportedDestructorReceiverType:String(importedClass:TCompilerIrImportedClass)
		If Not importedClass Then Return "BBOBJECT"
		If importedClass.destructorFunctionId.length Then
			Local importedDestructor:TCompilerIrImportedMethod = ImportedMethodById(importedClass.destructorFunctionId)
			If importedDestructor And importedDestructor.declaringImportedClassId.length Then
				Local declaringClass:TCompilerIrImportedClass = ImportedClassById(importedDestructor.declaringImportedClassId)
				If declaringClass Then Return "struct " + declaringClass.abiName + "_obj *"
			End If
		End If
		Return "struct " + importedClass.abiName + "_obj *"
	End Method

	Method EmitObjectNewHelper:String(routine:TCompilerIrFunction)
		Local irClass:TCompilerIrClass = ClassById(routine.ownerClassId)
		If Not irClass Then Return ""
		Local objectType:String = "struct " + ObjectName(irClass.classId) + " *"
		Local result:String = EmitObjectNewHelperPrototype(routine)
		result :+ " {~n"
		Local allocator:String = "bbObjectAtomicNewNC"
		If irClass.hasManagedFields Then allocator = "bbObjectNewNC"
		result :+ "    " + objectType + "o = (" + objectType + ")" + allocator + "(clas);~n"
		result :+ "    " + FunctionName(routine.functionId) + "(o"
		For Local parameter:TCompilerIrParameter = EachIn routine.parameters
			result :+ ", " + LocalName(parameter.symbolId, parameter.name)
		Next
		result :+ ");~n    return o;~n}~n"
		Return result
	End Method

	Method EmitObjectNewHelperPrototype:String(routine:TCompilerIrFunction)
		Local irClass:TCompilerIrClass = ClassById(routine.ownerClassId)
		If Not irClass Then Return ""
		Local result:String = "struct " + ObjectName(irClass.classId) + " * " + ObjectNewHelperName(routine.functionId) + "("
		If Not EmbeddedObjectTypes() Then result :+ "BBClass *clas"
		For Local parameter:TCompilerIrParameter = EachIn routine.parameters
			If result[result.length - 1] <> Asc("(") Then result :+ ", "
			result :+ CParameterDeclaration(parameter, LocalName(parameter.symbolId, parameter.name), routine.source)
		Next
		Return result + ")"
	End Method

	Method EmitBlockContents:String(block:TCompilerIrBlock, indent:String, includeDebugScope:Int = True)
		If Not block Then
			AddDiagnostic("BMXC2001", "IR function body was not available", Null)
			Return ""
		End If
		Local result:String
		Local hasDebugScope:Int = DebugEnabled() And includeDebugScope And block.debugScope
		If hasDebugScope Then
			result :+ EmitDebugLocalDeclarations(block, indent)
			debugScopeDepth :+ 1
			result :+ EmitDebugScope(block.debugScope, indent)
		End If
		For Local statement:TCompilerIrStatement = EachIn block.statements
			result :+ EmitStatement(statement, indent)
		Next
		If hasDebugScope Then
			result :+ indent + "bbOnDebugLeaveScope();~n"
			debugScopeDepth :- 1
		End If
		Return result
	End Method

	Method EmitStatement:String(statement:TCompilerIrStatement, indent:String)
		Local lineDirective:String = EmitGdbLineDirective(statement.source, indent)
		Local debugStatement:String = EmitDebugStatement(statement.source, indent)
		Local coverageStatement:String = EmitCoveragePoint(statement, indent)
		If TCompilerIrVariableDeclaration(statement) Or TCompilerIrAssignment(statement) Or TCompilerIrExpressionStatement(statement) Then
			Local previousScope:TCompilerCNativeStringScope = nativeStringScope
			nativeStringScope = New TCompilerCNativeStringScope
			Local body:String = EmitStatementBody(statement, indent)
			Local statementScope:TCompilerCNativeStringScope = nativeStringScope
			nativeStringScope = previousScope
			Return lineDirective + debugStatement + coverageStatement + EmitNativeStringPrelude(statementScope, indent) + body + EmitNativeStringCleanup(statementScope, indent)
		End If
		Return lineDirective + debugStatement + coverageStatement + EmitStatementBody(statement, indent)
	End Method

	Method EmitGdbLineDirective:String(source:TCompilerSourceLocation, indent:String)
		If Not currentModule Or Not currentModule.gdbDebug Or Not source Or Not source.path.length Or source.line <= 0 Then Return ""
		Return indent + "#line " + source.line + " " + CQuoted(source.path.Replace("\", "/")) + "~n"
	End Method

	Method EmitGdbGeneratedLineReset:String(indent:String = "")
		If Not currentModule Or Not currentModule.gdbDebug Then Return ""
		Return indent + "#line 1 ~q<bcc-generated>~q~n"
	End Method

	Method AcquireStatementOutput:TStringBuilder()
		If statementOutputDepth = statementOutputBuilders.length Then
			statementOutputBuilders :+ [New TStringBuilder(1024)]
		End If
		Local result:TStringBuilder = statementOutputBuilders[statementOutputDepth]
		statementOutputDepth :+ 1
		result.SetLength(0)
		Return result
	End Method

	Method CompleteStatementOutput:String(result:TStringBuilder, suffix:String = "")
		If suffix.length Then result.Append(suffix)
		Local value:String = result.ToString()
		statementOutputDepth :- 1
		Return value
	End Method

	Method EmitStatementBody:String(statement:TCompilerIrStatement, indent:String)
		Local result:TStringBuilder = AcquireStatementOutput()
		Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
		If variable Then
			If variable.storage = "constant" And currentIsMain Then Return CompleteStatementOutput(result, "")
			If variable.storage = "global" And currentIsMain Then
				If variable.isStaticArray Then Return CompleteStatementOutput(result, EmitStaticArrayInitialization(variable, SymbolName(variable.symbolId, variable.name), indent))
				If variable.initializer Then Return CompleteStatementOutput(result, indent + SymbolName(variable.symbolId, variable.name) + " = " + EmitExpression(variable.initializer) + ";~n")
				Return CompleteStatementOutput(result, "")
			End If
			If variable.storage = "global" Then
				If Not variable.initializer Then Return CompleteStatementOutput(result, "")
				Local globalName:String = SymbolName(variable.symbolId, variable.name)
				Local guardName:String = SafeIdentifier(globalName + "_inited")
				result.Append(indent + "static int " + guardName + " = 0;~n")
				result.Append(indent + "if (!" + guardName + ") {~n")
				result.Append(indent + "    " + guardName + " = 1;~n")
				result.Append(indent + "    " + globalName + " = " + EmitExpression(variable.initializer) + ";~n")
				result.Append(indent + "}~n")
				Return CompleteStatementOutput(result)
			End If
			Local iteratorStorage:String = String(localNames.ValueForKey(variable.symbolId))
			If currentRoutine And currentRoutine.isIteratorMoveNext And iteratorStorage.length Then
				If variable.isStaticArray Then Return CompleteStatementOutput(result, EmitStaticArrayInitialization(variable, iteratorStorage, indent))
				If variable.initializer Then Return CompleteStatementOutput(result, indent + iteratorStorage + " = " + EmitExpression(variable.initializer) + ";~n")
				Return CompleteStatementOutput(result, indent + iteratorStorage + " = " + CDefaultValue(variable.semanticType) + ";~n")
			End If
			Local name:String = LocalName(variable.symbolId, variable.name)
			localNames.Insert(variable.symbolId, name)
			If RegisterPicoRootLocal(variable) Then
				If variable.isStaticArray Then Return CompleteStatementOutput(result, EmitStaticArrayInitialization(variable, name, indent))
				If variable.initializer Then Return CompleteStatementOutput(result, indent + name + " = " + EmitExpression(variable.initializer) + ";~n")
				Return CompleteStatementOutput(result, indent + name + " = " + CDefaultValue(variable.semanticType) + ";~n")
			End If
			If DebugEnabled() And predeclaredDebugLocals.Contains(variable.symbolId) Then
				If variable.isStaticArray Then Return CompleteStatementOutput(result, "")
				If Not variable.hasExplicitInitializer Then Return CompleteStatementOutput(result, "")
				If variable.initializer Then Return CompleteStatementOutput(result, indent + name + " = " + EmitExpression(variable.initializer) + ";~n")
				Return CompleteStatementOutput(result, "")
			End If
			If variable.isStaticArray Then
				Local storagePrefix:String
				If variable.storage = "global" Then storagePrefix = "static "
				result.Append(indent + storagePrefix + CType(variable.staticArrayElementType, variable.source) + " " + name + "[" + variable.staticArrayLength + "] = {0};~n")
				result.Append(EmitStaticArrayInitialization(variable, name, indent))
				Return CompleteStatementOutput(result)
			End If
			Local storagePrefix:String
			If variable.storage = "global" Then storagePrefix = "static "
			result.Append(indent + storagePrefix + CVariableDeclaration(variable, name))
			If variable.initializer Then result.Append(" = " + EmitExpression(variable.initializer))
			Return CompleteStatementOutput(result, ";~n")
		End If
		Local assignment:TCompilerIrAssignment = TCompilerIrAssignment(statement)
		If assignment Then Return CompleteStatementOutput(result, EmitAssignment(assignment, indent))
		Local expressionStatement:TCompilerIrExpressionStatement = TCompilerIrExpressionStatement(statement)
		If expressionStatement Then Return CompleteStatementOutput(result, indent + "(void)" + EmitExpression(expressionStatement.expression) + ";~n")
		Local returned:TCompilerIrReturn = TCompilerIrReturn(statement)
		If returned Then
			If currentRoutine And currentRoutine.isIteratorMoveNext Then
				If returned.cleanupSteps.length Then result.Append(EmitCleanupSteps(returned.cleanupSteps, indent))
				result.Append(indent + IteratorFieldExpression(currentIteratorFactory.iteratorStateFieldId) + " = -1;~n")
				If currentIteratorFactory.iteratorOwnedResources.length Then
					result.Append(indent + "bbExLeave();~n")
					If DebugEnabled() Then result.Append(indent + "bbOnDebugPopExState();~n")
				End If
				Return CompleteStatementOutput(result, indent + "return 0;~n")
			End If
			If returned.cleanupSteps.length Then Return CompleteStatementOutput(result, EmitCleanupReturn(returned, indent))
			Local leaveScope:String = EmitDebugLeaves(debugScopeDepth, indent)
			If currentIsMain And Not returned.expression Then Return CompleteStatementOutput(result, leaveScope + EmitPicoRootFrameLeave(indent) + indent + "return 0;~n")
			If returned.expression Then
				Local capturedReturn:TCompilerCCapturedExpression = CaptureExpression(returned.expression)
				If currentPicoRootFrame Then
					Local picoReturnName:String = "bmx_pico_return_" + nextCleanupReturnId
					nextCleanupReturnId :+ 1
					result.Append(EmitNativeStringPrelude(capturedReturn.nativeStrings, indent))
					result.Append(indent + ReturnDeclaration(picoReturnName, returned.source) + " = " + capturedReturn.expression + ";~n")
					result.Append(EmitNativeStringCleanup(capturedReturn.nativeStrings, indent))
					Return CompleteStatementOutput(result, leaveScope + EmitPicoRootFrameLeave(indent) + indent + "return " + picoReturnName + ";~n")
				End If
				If capturedReturn.nativeStrings.names.length Then
					Local returnName:String = "bmx_native_return_" + nextCleanupReturnId
					nextCleanupReturnId :+ 1
					result.Append(EmitNativeStringPrelude(capturedReturn.nativeStrings, indent))
					result.Append(indent + ReturnDeclaration(returnName, returned.source) + " = " + capturedReturn.expression + ";~n")
					result.Append(EmitNativeStringCleanup(capturedReturn.nativeStrings, indent))
					Return CompleteStatementOutput(result, leaveScope + EmitPicoRootFrameLeave(indent) + indent + "return " + returnName + ";~n")
				End If
				Return CompleteStatementOutput(result, leaveScope + EmitPicoRootFrameLeave(indent) + indent + "return " + capturedReturn.expression + ";~n")
			End If
			If currentReturnType.ToLower() <> "void" Then Return CompleteStatementOutput(result, leaveScope + EmitPicoRootFrameLeave(indent) + indent + "return " + CurrentReturnDefault(returned.source) + ";~n")
			Return CompleteStatementOutput(result, leaveScope + EmitPicoRootFrameLeave(indent) + indent + "return;~n")
		End If
		Local yielded:TCompilerIrYield = TCompilerIrYield(statement)
		If yielded Then
			If Not currentRoutine Or Not currentRoutine.isIteratorMoveNext Or Not currentIteratorFactory Then
				AddDiagnostic("BMXC2095", "Yield reached C emission outside a generated iterator MoveNext", yielded.source)
				Return CompleteStatementOutput(result, "")
			End If
			Local stateExpression:String = IteratorFieldExpression(currentIteratorFactory.iteratorStateFieldId)
			Local currentExpression:String = IteratorFieldExpression(currentIteratorFactory.iteratorCurrentFieldId)
			result.Append(indent + currentExpression + " = " + EmitExpression(yielded.expression) + ";~n")
			result.Append(indent + stateExpression + " = " + yielded.resumeState + ";~n")
			For Local frameIndex:Int = 0 Until yielded.exceptionFrameDepth
				result.Append(indent + "bbExLeave();~n")
				If DebugEnabled() Then result.Append(indent + "bbOnDebugPopExState();~n")
			Next
			If currentIteratorFactory.iteratorOwnedResources.length Then
				result.Append(indent + "bbExLeave();~n")
				If DebugEnabled() Then result.Append(indent + "bbOnDebugPopExState();~n")
			End If
			result.Append(indent + "return 1;~n")
			Return CompleteStatementOutput(result, indent + "bmx_iterator_resume_" + yielded.resumeState + ": ;~n")
		End If
		Local thrown:TCompilerIrThrow = TCompilerIrThrow(statement)
		If thrown Then
			If EmbeddedObjectTypes() Then
				Local throwType:String = thrown.expression.semanticType.Trim().ToLower()
				If throwType = "string" Then
					Return CompleteStatementOutput(result, indent + "bmx_pico_exception_throw(bmx_pico_exception_string(" + EmitExpression(thrown.expression) + "));~n")
				End If
				If PicoArrayStorageType(throwType) Then
					Return CompleteStatementOutput(result, indent + "bmx_pico_exception_throw(bmx_pico_exception_array(" + EmitExpression(thrown.expression) + "));~n")
				End If
				If Not PicoObjectStorageType(throwType) Then
					AddDiagnostic("BMXC2100", "Pico Throw requires an Object, String, Array, class, interface, or closure value; '" + thrown.expression.semanticType + "' is not supported", thrown.source)
					Return CompleteStatementOutput(result, "")
				End If
				Return CompleteStatementOutput(result, indent + "bmx_pico_exception_throw(bmx_pico_exception_object((BMXPicoObject *)" + EmitExpression(thrown.expression) + "));~n")
			End If
			Local capturedThrow:TCompilerCCapturedExpression = CaptureExpression(thrown.expression)
			If capturedThrow.nativeStrings.names.length Then
				Local throwName:String = "bmx_native_throw_" + nextNativeStringId
				nextNativeStringId :+ 1
				result.Append(EmitNativeStringPrelude(capturedThrow.nativeStrings, indent))
				result.Append(indent + "BBOBJECT " + throwName + " = (BBOBJECT)" + capturedThrow.expression + ";~n")
				result.Append(EmitNativeStringCleanup(capturedThrow.nativeStrings, indent))
				Return CompleteStatementOutput(result, indent + "bbExThrow((BBObject *)" + throwName + ");~n")
			End If
			Return CompleteStatementOutput(result, indent + "bbExThrow((BBObject *)" + capturedThrow.expression + ");~n")
		End If
		Local applicationEnd:TCompilerIrApplicationEnd = TCompilerIrApplicationEnd(statement)
		If applicationEnd Then Return CompleteStatementOutput(result, indent + "bbEnd();~n")
		Local released:TCompilerIrRelease = TCompilerIrRelease(statement)
		If released Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2079", "Release requires the BlitzMax runtime C backend", released.source)
				Return CompleteStatementOutput(result, "")
			End If
			Return CompleteStatementOutput(result, indent + "bbHandleRelease((size_t)(" + EmitExpression(released.expression) + "));~n")
		End If
		Local asserted:TCompilerIrAssert = TCompilerIrAssert(statement)
		If asserted Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2078", "Assert requires the BlitzMax runtime C backend", asserted.source)
				Return CompleteStatementOutput(result, "")
			End If
			Local capturedAssert:TCompilerCCapturedExpression = CaptureExpression(asserted.condition, True)
			result.Append(EmitNativeStringPrelude(capturedAssert.nativeStrings, indent))
			Local assertCondition:String = capturedAssert.expression
			If capturedAssert.nativeStrings.names.length Then
				Local assertName:String = "bmx_native_condition_" + nextNativeStringId
				nextNativeStringId :+ 1
				result.Append(indent + "BBINT " + assertName + " = (BBINT)(" + assertCondition + ");~n")
				result.Append(EmitNativeStringCleanup(capturedAssert.nativeStrings, indent))
				assertCondition = assertName
			End If
			result.Append(indent + "if (!(" + assertCondition + ")) {~n")
			Local capturedMessage:TCompilerCCapturedExpression = CaptureExpression(asserted.message)
			result.Append(EmitNativeStringPrelude(capturedMessage.nativeStrings, indent + "    "))
			If capturedMessage.nativeStrings.names.length Then
				Local messageName:String = "bmx_native_assert_message_" + nextNativeStringId
				nextNativeStringId :+ 1
				result.Append(indent + "    BBSTRING " + messageName + " = " + capturedMessage.expression + ";~n")
				result.Append(EmitNativeStringCleanup(capturedMessage.nativeStrings, indent + "    "))
				result.Append(indent + "    brl_blitz_RuntimeError(" + messageName + ");~n")
			Else
				result.Append(indent + "    brl_blitz_RuntimeError(" + capturedMessage.expression + ");~n")
			End If
			Return CompleteStatementOutput(result, indent + "}~n")
		End If
		Local conditionalIf:TCompilerIrIf = TCompilerIrIf(statement)
		If conditionalIf Then Return CompleteStatementOutput(result, EmitConditionalChain(conditionalIf, -1, indent))
		Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
		If selected Then
			Local selectorName:String = TemporaryName(selected.selectorTemporaryId)
			localNames.Insert(selected.selectorTemporaryId, selectorName)
			result.Append(indent + "{~n")
			Local capturedSelector:TCompilerCCapturedExpression = CaptureExpression(selected.selector)
			result.Append(EmitNativeStringPrelude(capturedSelector.nativeStrings, indent + "    "))
			result.Append(indent + "    " + CType(selected.selectorType, selected.source) + " " + selectorName + " = " + capturedSelector.expression + ";~n")
			result.Append(EmitNativeStringCleanup(capturedSelector.nativeStrings, indent + "    "))
			For Local caseIndex:Int = 0 Until selected.cases.length
				Local selectedCase:TCompilerIrSelectCase = selected.cases[caseIndex]
				If caseIndex Then result.Append(" else ") Else result.Append(indent + "    ")
				result.Append("if (")
				For Local valueIndex:Int = 0 Until selectedCase.values.length
					If valueIndex Then result.Append(" || ")
					If selected.stringComparison Then
						If EmbeddedStringTypes() Then
							result.Append("bmx_pico_string_equals(" + selectorName + ", " + EmitExpression(selectedCase.values[valueIndex]) + ") != 0")
						Else
							result.Append("bbStringEquals(" + selectorName + ", " + EmitExpression(selectedCase.values[valueIndex]) + ") == 1")
						End If
					Else If selected.managedIdentityComparison Then
						result.Append("(BBOBJECT)" + selectorName + " == (BBOBJECT)" + EmitExpression(selectedCase.values[valueIndex]))
					Else
						result.Append(selectorName + " == " + EmitExpression(selectedCase.values[valueIndex]))
					End If
				Next
				If Not selectedCase.values.length Then result.Append("0")
				result.Append(") {~n")
				result.Append(EmitBlockContents(selectedCase.body, indent + "        "))
				result.Append(indent + "    }")
			Next
			If selected.defaultBody Then
				If selected.cases.length Then result.Append(" else {~n") Else result.Append(indent + "    {~n")
				result.Append(EmitBlockContents(selected.defaultBody, indent + "        "))
				result.Append(indent + "    }")
			End If
			If selected.cases.length Or selected.defaultBody Then result.Append("~n")
			Return CompleteStatementOutput(result, indent + "}~n")
		End If
		Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
		If guarded Then
			If Not runtimeTypes And Not EmbeddedObjectTypes() Then
				AddDiagnostic("BMXC2081", "Try/Catch requires the BlitzMax runtime exception backend", guarded.source)
				Return CompleteStatementOutput(result, "")
			End If
			If EmbeddedObjectTypes() And currentRoutine And currentRoutine.isIteratorMoveNext And guarded.retainedInIterator Then
				AddDiagnostic("BMXC2102", "Pico exceptions do not yet support a Try block retained across Yield", guarded.source)
				Return CompleteStatementOutput(result, "")
			End If
			If guarded.finallyBody Then Return CompleteStatementOutput(result, EmitTryFinally(guarded, indent))
			Return CompleteStatementOutput(result, EmitTryCatch(guarded, indent))
		End If
		Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
		If usingStatement Then
			If EmbeddedObjectTypes() Then Return CompleteStatementOutput(result, EmitPicoUsing(usingStatement, indent))
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2082", "Using requires the BlitzMax runtime exception backend", usingStatement.source)
				Return CompleteStatementOutput(result, "")
			End If
			Local exceptionName:String = "bmx_" + SafeIdentifier(usingStatement.usingId) + "_exception"
			Local failedName:String = "bmx_" + SafeIdentifier(usingStatement.usingId) + "_failed"
			Local persistentUsing:Int = currentRoutine And currentRoutine.isIteratorMoveNext And usingStatement.retainedInIterator
			result.Append(indent + "{~n")
			For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
				If Not persistentUsing Then result.Append(EmitStatementBody(resource.variable, indent + "    "))
			Next
			RegisterCleanupDebugDepth(usingStatement.resources)
			If Not persistentUsing Then
				result.Append(indent + "    BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n")
				result.Append(indent + "    BBINT " + failedName + " = 0;~n")
				result.Append(indent + "    bbExTry {~n")
				result.Append(indent + "    case 0: {~n")
				If DebugEnabled() Then result.Append(indent + "        bbOnDebugPushExState();~n")
			End If
			Local bodyIndent:String = indent + "        "
			If persistentUsing Then bodyIndent = indent + "    "
			For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
				Local resourceName:String = LocalName(resource.variable.symbolId, resource.variable.name)
				If persistentUsing Then resourceName = SymbolName(resource.variable.symbolId, resource.variable.name)
				result.Append(bodyIndent + resourceName + " = " + EmitExpression(resource.initializer) + ";~n")
			Next
			result.Append(EmitBlockContents(usingStatement.body, bodyIndent))
			If persistentUsing Then
				result.Append(EmitUsingCleanup(usingStatement.resources, indent + "    ", True))
			Else
				result.Append(indent + "        bbExLeave();~n")
				If DebugEnabled() Then result.Append(indent + "        bbOnDebugPopExState();~n")
				result.Append(indent + "    } break;~n")
				result.Append(indent + "    case 1: {~n")
				If DebugEnabled() Then result.Append(indent + "        bbOnDebugPopExState();~n")
				result.Append(indent + "        " + exceptionName + " = bbExCatch();~n")
				result.Append(indent + "        " + failedName + " = 1;~n")
				result.Append(indent + "    } break;~n")
				result.Append(indent + "    }~n")
				result.Append(EmitUsingCleanup(usingStatement.resources, indent + "    "))
				result.Append(indent + "    if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n")
			End If
			Return CompleteStatementOutput(result, indent + "}~n")
		End If
		Local dataRead:TCompilerIrDataRead = TCompilerIrDataRead(statement)
		If dataRead Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2083", "ReadData requires the BlitzMax runtime C backend", dataRead.source)
				Return CompleteStatementOutput(result, "")
			End If
			For Local target:TCompilerIrDataReadTarget = EachIn dataRead.targets
				result.Append(indent + "if ((BBSIZET)(bmx_data_offset - bmx_data) >= bmx_data_count) brl_blitz_OutOfDataError();~n")
				result.Append(indent + EmitExpression(target.target) + " = " + DataReadConversionName(target.conversionKind, target.source) + "(bmx_data_offset++);~n")
			Next
			Return CompleteStatementOutput(result, "")
		End If
		Local dataRestore:TCompilerIrDataRestore = TCompilerIrDataRestore(statement)
		If dataRestore Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2083", "RestoreData requires the BlitzMax runtime C backend", dataRestore.source)
				Return CompleteStatementOutput(result, "")
			End If
			Return CompleteStatementOutput(result, indent + "bmx_data_offset = &bmx_data[" + dataRestore.itemIndex + "];~n")
		End If
		Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
		If whileStatement Then
			RegisterLoopDebugDepth(whileStatement.loopId)
			Local capturedWhile:TCompilerCCapturedExpression = CaptureExpression(whileStatement.condition, True)
			If capturedWhile.nativeStrings.names.length Then
				Local conditionName:String = "bmx_native_condition_" + nextNativeStringId
				nextNativeStringId :+ 1
				result.Append(indent + "for (;;) {~n")
				result.Append(EmitNativeStringPrelude(capturedWhile.nativeStrings, indent + "    "))
				result.Append(indent + "    BBINT " + conditionName + " = (BBINT)(" + capturedWhile.expression + ");~n")
				result.Append(EmitNativeStringCleanup(capturedWhile.nativeStrings, indent + "    "))
				result.Append(indent + "    if (!(" + conditionName + ")) break;~n")
			Else
				result.Append(indent + "while (" + capturedWhile.expression + ") {~n")
			End If
			result.Append(EmitBlockContents(whileStatement.body, indent + "    "))
			If whileStatement.hasContinue Then result.Append(indent + "    " + LoopContinueLabel(whileStatement.loopId) + ": ;~n")
			result.Append(indent + "}~n")
			If whileStatement.hasExit Then result.Append(indent + LoopExitLabel(whileStatement.loopId) + ": ;~n")
			Return CompleteStatementOutput(result)
		End If
		Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
		If repeatStatement Then
			RegisterLoopDebugDepth(repeatStatement.loopId)
			Local capturedRepeat:TCompilerCCapturedExpression
			If Not repeatStatement.isForever Then capturedRepeat = CaptureExpression(repeatStatement.condition, True)
			If repeatStatement.isForever Or (capturedRepeat And capturedRepeat.nativeStrings.names.length) Then result.Append(indent + "for (;;) {~n") Else result.Append(indent + "do {~n")
			result.Append(EmitBlockContents(repeatStatement.body, indent + "    "))
			If repeatStatement.hasContinue Then result.Append(indent + "    " + LoopContinueLabel(repeatStatement.loopId) + ": ;~n")
			If repeatStatement.isForever Then
				result.Append(indent + "}~n")
			Else If capturedRepeat.nativeStrings.names.length Then
				Local conditionName:String = "bmx_native_condition_" + nextNativeStringId
				nextNativeStringId :+ 1
				result.Append(EmitNativeStringPrelude(capturedRepeat.nativeStrings, indent + "    "))
				result.Append(indent + "    BBINT " + conditionName + " = (BBINT)(" + capturedRepeat.expression + ");~n")
				result.Append(EmitNativeStringCleanup(capturedRepeat.nativeStrings, indent + "    "))
				result.Append(indent + "    if (" + conditionName + ") break;~n")
				result.Append(indent + "}~n")
			Else
				result.Append(indent + "} while (!(" + capturedRepeat.expression + "));~n")
			End If
			If repeatStatement.hasExit Then result.Append(indent + LoopExitLabel(repeatStatement.loopId) + ": ;~n")
			Return CompleteStatementOutput(result)
		End If
		Local forStatement:TCompilerIrForRange = TCompilerIrForRange(statement)
		If forStatement Then
			RegisterLoopDebugDepth(forStatement.loopId)
			Local target:String
			Local initialization:String
			If forStatement.declaresVariable Then
				Local name:String = String(localNames.ValueForKey(forStatement.variableSymbolId))
				If Not name.length Then
					name = LocalName(forStatement.variableSymbolId, forStatement.variableName)
					localNames.Insert(forStatement.variableSymbolId, name)
				End If
				target = name
				If currentRoutine And currentRoutine.isIteratorMoveNext Then
					initialization = name + " = " + EmitForRangeValue(forStatement.initialValue, forStatement.variableType, forStatement.source)
				Else
					initialization = CType(forStatement.variableType, forStatement.source) + " " + name + " = " + EmitForRangeValue(forStatement.initialValue, forStatement.variableType, forStatement.source)
				End If
			Else
				target = EmitExpression(forStatement.target)
				initialization = target + " = " + EmitForRangeValue(forStatement.initialValue, forStatement.variableType, forStatement.source)
			End If
			Local comparison:String = "<"
			If forStatement.inclusiveLimit Then comparison = "<="
			If forStatement.descending Then
				comparison = ">"
				If forStatement.inclusiveLimit Then comparison = ">="
			End If
			result.Append(indent + "for (" + initialization + "; " + target + " " + comparison + " " + EmitForRangeValue(forStatement.limit, forStatement.variableType, forStatement.source) + "; " + target + " = " + target + " + " + EmitForRangeValue(forStatement.stepExpression, forStatement.variableType, forStatement.source) + ") {~n")
			result.Append(EmitBlockContents(forStatement.body, indent + "    "))
			If forStatement.hasContinue Then result.Append(indent + "    " + LoopContinueLabel(forStatement.loopId) + ": ;~n")
			If forStatement.iterationCopyBack Then result.Append(EmitStatement(forStatement.iterationCopyBack, indent + "    "))
			result.Append(indent + "}~n")
			If forStatement.hasExit Then result.Append(indent + LoopExitLabel(forStatement.loopId) + ": ;~n")
			Return CompleteStatementOutput(result)
		End If
		Local eachStatement:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
		If eachStatement Then
			RegisterLoopDebugDepth(eachStatement.loopId)
			Local collectionName:String = TemporaryName(eachStatement.collectionTemporaryId)
			Local indexName:String = TemporaryName(eachStatement.indexTemporaryId)
			Local elementName:String = TemporaryName(eachStatement.elementTemporaryId)
			Local persistentEach:Int = currentRoutine And currentRoutine.isIteratorMoveNext And localNames.Contains(eachStatement.collectionTemporaryId)
			If persistentEach Then
				collectionName = String(localNames.ValueForKey(eachStatement.collectionTemporaryId))
				indexName = String(localNames.ValueForKey(eachStatement.indexTemporaryId))
				elementName = String(localNames.ValueForKey(eachStatement.elementTemporaryId))
			Else
				localNames.Insert(eachStatement.collectionTemporaryId, collectionName)
				localNames.Insert(eachStatement.indexTemporaryId, indexName)
			End If
			localNames.Insert(eachStatement.elementTemporaryId, elementName)
			Local element:String
			If EmbeddedArrayTypes() Then
				If Not PicoArrayElementSupported(eachStatement.elementType) Then
					AddDiagnostic("BMXC2028", "EachIn Array element type '" + eachStatement.elementType + "' is not available in the Pico managed-container profile", eachStatement.source)
					Return ""
				End If
				Local eachElementType:String = CType(eachStatement.elementType, eachStatement.source)
				element = "(*((" + eachElementType + " *)bmx_pico_array_element(" + collectionName + ", (int32_t)" + indexName + ", (uint32_t)sizeof(" + eachElementType + "))))"
			Else
				element = "((" + CType(eachStatement.elementType, eachStatement.source) + "*)BBARRAYDATA(" + collectionName + ", 1))[" + indexName + "]"
			End If
			result.Append(indent + "{~n")
			If persistentEach Then
				result.Append(indent + "    " + collectionName + " = " + DebugManagedValue(EmitExpression(eachStatement.collection), IR_MANAGED_REFERENCE_ARRAY, eachStatement.collection.semanticType, eachStatement.source) + ";~n")
				result.Append(indent + "    " + indexName + " = 0;~n")
			Else
				Local collectionType:String = "BBARRAY"
				Local indexType:String = "BBUINT"
				If EmbeddedArrayTypes() Then
					collectionType = "BMXPicoArray *"
					indexType = "uint32_t"
				End If
				result.Append(indent + "    " + collectionType + " " + collectionName + " = " + DebugManagedValue(EmitExpression(eachStatement.collection), IR_MANAGED_REFERENCE_ARRAY, eachStatement.collection.semanticType, eachStatement.source) + ";~n")
				result.Append(indent + "    " + indexType + " " + indexName + " = 0;~n")
			End If
			If EmbeddedArrayTypes() Then
				result.Append(indent + "    for (; " + indexName + " < (uint32_t)" + collectionName + "->length; " + indexName + " = " + indexName + " + 1) {~n")
			Else
				result.Append(indent + "    for (; " + indexName + " < (BBUINT)" + collectionName + "->scales[0]; " + indexName + " = " + indexName + " + 1) {~n")
			End If
			If persistentEach Then result.Append(indent + "        " + elementName + " = " + element + ";~n") Else result.Append(indent + "        " + CType(eachStatement.elementType, eachStatement.source) + " " + elementName + " = " + element + ";~n")
			If eachStatement.filtersStringObjects Then result.Append(indent + "        if (bbObjectIsString((BBOBJECT)" + elementName + ") == 0) { continue; }~n")
			Local target:String
			If eachStatement.declaresVariable Then
				Local name:String = LocalName(eachStatement.variableSymbolId, eachStatement.variableName)
				If persistentEach Then name = String(localNames.ValueForKey(eachStatement.variableSymbolId))
				localNames.Insert(eachStatement.variableSymbolId, name)
				target = name
				If persistentEach Then result.Append(indent + "        " + name + " = " + EmitExpression(eachStatement.elementValue) + ";~n") Else result.Append(indent + "        " + CType(eachStatement.variableType, eachStatement.source) + " " + name + " = " + EmitExpression(eachStatement.elementValue) + ";~n")
			Else
				target = EmitExpression(eachStatement.target)
				result.Append(indent + "        " + target + " = " + EmitExpression(eachStatement.elementValue) + ";~n")
			End If
			If eachStatement.filtersNullObjects Then result.Append(indent + "        if ((BBOBJECT)" + target + " == (BBOBJECT)&bbNullObject) { continue; }~n")
			result.Append(EmitBlockContents(eachStatement.body, indent + "        "))
			If eachStatement.hasContinue Then result.Append(indent + "        " + LoopContinueLabel(eachStatement.loopId) + ": ;~n")
			result.Append(indent + "    }~n")
			If eachStatement.hasExit Then result.Append(indent + "    " + LoopExitLabel(eachStatement.loopId) + ": ;~n")
			Return CompleteStatementOutput(result, indent + "}~n")
		End If
		Local stringEachStatement:TCompilerIrForEachString = TCompilerIrForEachString(statement)
		If stringEachStatement Then
			RegisterLoopDebugDepth(stringEachStatement.loopId)
			Local collectionName:String = TemporaryName(stringEachStatement.collectionTemporaryId)
			Local indexName:String = TemporaryName(stringEachStatement.indexTemporaryId)
			Local elementName:String = TemporaryName(stringEachStatement.elementTemporaryId)
			Local persistentEach:Int = currentRoutine And currentRoutine.isIteratorMoveNext And localNames.Contains(stringEachStatement.collectionTemporaryId)
			If persistentEach Then
				collectionName = String(localNames.ValueForKey(stringEachStatement.collectionTemporaryId))
				indexName = String(localNames.ValueForKey(stringEachStatement.indexTemporaryId))
				elementName = String(localNames.ValueForKey(stringEachStatement.elementTemporaryId))
			Else
				localNames.Insert(stringEachStatement.collectionTemporaryId, collectionName)
				localNames.Insert(stringEachStatement.indexTemporaryId, indexName)
				localNames.Insert(stringEachStatement.elementTemporaryId, elementName)
			End If
			result.Append(indent + "{~n")
			If persistentEach Then
				result.Append(indent + "    " + collectionName + " = " + DebugManagedValue(EmitExpression(stringEachStatement.collection), IR_MANAGED_REFERENCE_STRING, stringEachStatement.collection.semanticType, stringEachStatement.source) + ";~n")
				result.Append(indent + "    " + indexName + " = 0;~n")
			Else
				result.Append(indent + "    BBSTRING " + collectionName + " = " + DebugManagedValue(EmitExpression(stringEachStatement.collection), IR_MANAGED_REFERENCE_STRING, stringEachStatement.collection.semanticType, stringEachStatement.source) + ";~n")
				result.Append(indent + "    BBUINT " + indexName + " = 0;~n")
			End If
			result.Append(indent + "    for (; " + indexName + " < (BBUINT)" + collectionName + "->length; " + indexName + " = " + indexName + " + 1) {~n")
			If persistentEach Then result.Append(indent + "        " + elementName + " = (BBINT)" + collectionName + "->buf[" + indexName + "];~n") Else result.Append(indent + "        BBINT " + elementName + " = (BBINT)" + collectionName + "->buf[" + indexName + "];~n")
			Local convertedElement:String = "((" + CType(stringEachStatement.variableType, stringEachStatement.source) + ")(" + elementName + "))"
			If stringEachStatement.declaresVariable Then
				Local name:String = LocalName(stringEachStatement.variableSymbolId, stringEachStatement.variableName)
				If persistentEach Then name = String(localNames.ValueForKey(stringEachStatement.variableSymbolId))
				localNames.Insert(stringEachStatement.variableSymbolId, name)
				If persistentEach Then result.Append(indent + "        " + name + " = " + convertedElement + ";~n") Else result.Append(indent + "        " + CType(stringEachStatement.variableType, stringEachStatement.source) + " " + name + " = " + convertedElement + ";~n")
			Else
				result.Append(indent + "        " + EmitExpression(stringEachStatement.target) + " = " + convertedElement + ";~n")
			End If
			result.Append(EmitBlockContents(stringEachStatement.body, indent + "        "))
			If stringEachStatement.hasContinue Then result.Append(indent + "        " + LoopContinueLabel(stringEachStatement.loopId) + ": ;~n")
			result.Append(indent + "    }~n")
			If stringEachStatement.hasExit Then result.Append(indent + "    " + LoopExitLabel(stringEachStatement.loopId) + ": ;~n")
			Return CompleteStatementOutput(result, indent + "}~n")
		End If
		Local staticEachStatement:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
		If staticEachStatement Then
			RegisterLoopDebugDepth(staticEachStatement.loopId)
			Local collectionName:String = TemporaryName(staticEachStatement.collectionTemporaryId)
			Local indexName:String = TemporaryName(staticEachStatement.indexTemporaryId)
			Local elementName:String = TemporaryName(staticEachStatement.elementTemporaryId)
			Local elementCType:String = CType(staticEachStatement.elementType, staticEachStatement.source)
			Local persistentEach:Int = currentRoutine And currentRoutine.isIteratorMoveNext And localNames.Contains(staticEachStatement.collectionTemporaryId)
			If persistentEach Then
				collectionName = String(localNames.ValueForKey(staticEachStatement.collectionTemporaryId))
				indexName = String(localNames.ValueForKey(staticEachStatement.indexTemporaryId))
				elementName = String(localNames.ValueForKey(staticEachStatement.elementTemporaryId))
			Else
				localNames.Insert(staticEachStatement.collectionTemporaryId, collectionName)
				localNames.Insert(staticEachStatement.indexTemporaryId, indexName)
				localNames.Insert(staticEachStatement.elementTemporaryId, elementName)
			End If
			result.Append(indent + "{~n")
			If persistentEach Then
				result.Append(indent + "    " + collectionName + " = " + EmitExpression(staticEachStatement.collection) + ";~n")
				result.Append(indent + "    " + indexName + " = 0;~n")
			Else
				result.Append(indent + "    " + elementCType + " *" + collectionName + " = " + EmitExpression(staticEachStatement.collection) + ";~n")
				result.Append(indent + "    " + StaticArrayIndexCType() + " " + indexName + " = 0;~n")
			End If
			result.Append(indent + "    for (; " + indexName + " < (" + StaticArrayIndexCType() + ")" + staticEachStatement.length + "; " + indexName + " = " + indexName + " + 1) {~n")
			If persistentEach Then result.Append(indent + "        " + elementName + " = " + collectionName + "[" + indexName + "];~n") Else result.Append(indent + "        " + elementCType + " " + elementName + " = " + collectionName + "[" + indexName + "];~n")
			Local convertedElement:String = elementName
			If Not staticEachStatement.elementStructId.length And Not staticEachStatement.elementImportedStructId.length Then convertedElement = "((" + CType(staticEachStatement.variableType, staticEachStatement.source) + ")(" + elementName + "))"
			If staticEachStatement.declaresVariable Then
				Local name:String = LocalName(staticEachStatement.variableSymbolId, staticEachStatement.variableName)
				If persistentEach Then name = String(localNames.ValueForKey(staticEachStatement.variableSymbolId))
				localNames.Insert(staticEachStatement.variableSymbolId, name)
				If persistentEach Then result.Append(indent + "        " + name + " = " + convertedElement + ";~n") Else result.Append(indent + "        " + CType(staticEachStatement.variableType, staticEachStatement.source) + " " + name + " = " + convertedElement + ";~n")
			Else
				result.Append(indent + "        " + EmitExpression(staticEachStatement.target) + " = " + convertedElement + ";~n")
			End If
			result.Append(EmitBlockContents(staticEachStatement.body, indent + "        "))
			If staticEachStatement.hasContinue Then result.Append(indent + "        " + LoopContinueLabel(staticEachStatement.loopId) + ": ;~n")
			result.Append(indent + "    }~n")
			If staticEachStatement.hasExit Then result.Append(indent + "    " + LoopExitLabel(staticEachStatement.loopId) + ": ;~n")
			Return CompleteStatementOutput(result, indent + "}~n")
		End If
		Local objectEachStatement:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
		If objectEachStatement Then
			RegisterLoopDebugDepth(objectEachStatement.loopId)
			Local collectionName:String = String(localNames.ValueForKey(objectEachStatement.collectionTemporaryId))
			Local iteratorName:String = String(localNames.ValueForKey(objectEachStatement.iteratorTemporaryId))
			Local elementName:String = String(localNames.ValueForKey(objectEachStatement.elementTemporaryId))
			Local persistentEach:Int = currentRoutine And currentRoutine.isIteratorMoveNext And collectionName.length And iteratorName.length And elementName.length
			If Not collectionName.length Then collectionName = TemporaryName(objectEachStatement.collectionTemporaryId)
			If Not iteratorName.length Then iteratorName = TemporaryName(objectEachStatement.iteratorTemporaryId)
			If Not elementName.length Then elementName = TemporaryName(objectEachStatement.elementTemporaryId)
			localNames.Insert(objectEachStatement.collectionTemporaryId, collectionName)
			localNames.Insert(objectEachStatement.iteratorTemporaryId, iteratorName)
			localNames.Insert(objectEachStatement.elementTemporaryId, elementName)
			result.Append(indent + "{~n")
			If persistentEach Then
				result.Append(indent + "    " + collectionName + " = " + EmitExpression(objectEachStatement.collection) + ";~n")
				result.Append(indent + "    " + iteratorName + " = " + EmitExpression(objectEachStatement.iteratorInitializer) + ";~n")
			Else
				result.Append(indent + "    " + CType(objectEachStatement.collectionType, objectEachStatement.source) + " " + collectionName + " = " + EmitExpression(objectEachStatement.collection) + ";~n")
				result.Append(indent + "    " + CType(objectEachStatement.iteratorType, objectEachStatement.source) + " " + iteratorName + " = " + EmitExpression(objectEachStatement.iteratorInitializer) + ";~n")
			End If
			Local cleanup:TCompilerIrUsingResource = objectEachStatement.iteratorCleanup
			Local exceptionName:String
			Local failedName:String
			If cleanup Then
				If persistentEach Then
					result.Append(indent + "    " + SymbolName(cleanup.variable.symbolId, cleanup.variable.name) + " = " + CDefaultValue(cleanup.variable.semanticType) + ";~n")
				Else
					result.Append(EmitStatementBody(cleanup.variable, indent + "    "))
				End If
				RegisterCleanupDebugDepth([cleanup])
				Local cleanupName:String = LocalName(cleanup.variable.symbolId, cleanup.variable.name)
				If persistentEach Then cleanupName = SymbolName(cleanup.variable.symbolId, cleanup.variable.name)
				result.Append(indent + "    " + cleanupName + " = " + EmitExpression(cleanup.initializer) + ";~n")
				If Not persistentEach Then
					exceptionName = "bmx_each_" + SafeIdentifier(objectEachStatement.loopId) + "_exception"
					failedName = "bmx_each_" + SafeIdentifier(objectEachStatement.loopId) + "_failed"
					If EmbeddedObjectTypes() Then
						exceptionName = RegisterPicoExceptionRoot("pico.each.exception." + objectEachStatement.loopId, exceptionName, "__pico_exception", objectEachStatement.source)
						Local picoFrameName:String = "bmx_pico_each_" + SafeIdentifier(objectEachStatement.loopId) + "_frame"
						result.Append(indent + "    BMXPicoExceptionFrame " + picoFrameName + ";~n")
						result.Append(indent + "    int32_t " + failedName + " = 0;~n")
						result.Append(indent + "    bmx_pico_exception_enter(&" + picoFrameName + ");~n")
						result.Append(indent + "    switch (setjmp(" + picoFrameName + ".buffer)) {~n")
						result.Append(indent + "    case 0: {~n")
					Else
						result.Append(indent + "    BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n")
						result.Append(indent + "    BBINT " + failedName + " = 0;~n")
						result.Append(indent + "    bbExTry {~n")
						result.Append(indent + "    case 0: {~n")
						If DebugEnabled() Then result.Append(indent + "        bbOnDebugPushExState();~n")
					End If
				End If
			End If
			Local loopIndent:String = indent + "    "
			If cleanup And Not persistentEach Then loopIndent :+ "    "
			result.Append(loopIndent + "while (" + EmitExpression(objectEachStatement.advance) + ") {~n")
			If persistentEach Then result.Append(loopIndent + "    " + elementName + " = " + EmitExpression(objectEachStatement.current) + ";~n") Else result.Append(loopIndent + "    " + CType(objectEachStatement.elementType, objectEachStatement.source) + " " + elementName + " = " + EmitExpression(objectEachStatement.current) + ";~n")
			If objectEachStatement.filtersStringObjects Then result.Append(loopIndent + "    if (bbObjectIsString((BBOBJECT)" + elementName + ") == 0) { continue; }~n")
			Local convertedElement:String = EmitExpression(objectEachStatement.elementValue)
			Local target:String
			If objectEachStatement.declaresVariable Then
				Local name:String = LocalName(objectEachStatement.variableSymbolId, objectEachStatement.variableName)
				If persistentEach Then name = SymbolName(objectEachStatement.variableSymbolId, objectEachStatement.variableName)
				localNames.Insert(objectEachStatement.variableSymbolId, name)
				target = name
				If persistentEach Then result.Append(loopIndent + "    " + name + " = " + convertedElement + ";~n") Else result.Append(loopIndent + "    " + CType(objectEachStatement.variableType, objectEachStatement.source) + " " + name + " = " + convertedElement + ";~n")
			Else
				target = EmitExpression(objectEachStatement.target)
				result.Append(loopIndent + "    " + target + " = " + convertedElement + ";~n")
			End If
			If objectEachStatement.filtersNullObjects Then result.Append(loopIndent + "    if ((BBOBJECT)" + target + " == (BBOBJECT)&bbNullObject) { continue; }~n")
			result.Append(EmitBlockContents(objectEachStatement.body, loopIndent + "    "))
			If objectEachStatement.hasContinue Then result.Append(loopIndent + "    " + LoopContinueLabel(objectEachStatement.loopId) + ": ;~n")
			result.Append(loopIndent + "}~n")
			If cleanup And Not persistentEach Then
				If EmbeddedObjectTypes() Then result.Append(indent + "        bmx_pico_exception_leave();~n") Else result.Append(indent + "        bbExLeave();~n")
				If DebugEnabled() And Not EmbeddedObjectTypes() Then result.Append(indent + "        bbOnDebugPopExState();~n")
				result.Append(indent + "    } break;~n")
				result.Append(indent + "    case 1: {~n")
				If DebugEnabled() And Not EmbeddedObjectTypes() Then result.Append(indent + "        bbOnDebugPopExState();~n")
				If EmbeddedObjectTypes() Then result.Append(indent + "        " + exceptionName + " = bmx_pico_exception_catch();~n") Else result.Append(indent + "        " + exceptionName + " = bbExCatch();~n")
				result.Append(indent + "        " + failedName + " = 1;~n")
				result.Append(indent + "    } break;~n")
				result.Append(indent + "    }~n")
				result.Append(EmitUsingCleanup([cleanup], indent + "    "))
				If EmbeddedObjectTypes() Then result.Append(indent + "    if (" + failedName + ") bmx_pico_exception_throw(" + exceptionName + ");~n") Else result.Append(indent + "    if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n")
			Else If cleanup Then
				result.Append(EmitUsingCleanup([cleanup], indent + "    ", True))
			End If
			If objectEachStatement.hasExit Then result.Append(indent + "    " + LoopExitLabel(objectEachStatement.loopId) + ": ;~n")
			Return CompleteStatementOutput(result, indent + "}~n")
		End If
		Local loopControl:TCompilerIrLoopControl = TCompilerIrLoopControl(statement)
		If loopControl Then
			Local cleanup:String = EmitCleanupSteps(loopControl.cleanupSteps, indent)
			Local restoredDebugDepth:Int = CleanupRestoredDebugDepth(loopControl.cleanupSteps)
			If loopControl.controlKind = IR_LOOP_CONTROL_CONTINUE Then
				Return CompleteStatementOutput(result, cleanup + EmitLoopDebugLeaves(loopContinueDebugDepths, loopControl.targetLoopId, indent, restoredDebugDepth) + indent + "goto " + LoopContinueLabel(loopControl.targetLoopId) + ";~n")
			End If
			Return CompleteStatementOutput(result, cleanup + EmitLoopDebugLeaves(loopExitDebugDepths, loopControl.targetLoopId, indent, restoredDebugDepth) + indent + "goto " + LoopExitLabel(loopControl.targetLoopId) + ";~n")
		End If
		AddDiagnostic("BMXC2002", "IR statement is not supported by the scalar C backend", statement.source)
		Return CompleteStatementOutput(result, "")
	End Method

	Method EmitCleanupReturn:String(returned:TCompilerIrReturn, indent:String)
		Local result:String
		Local returnName:String
		If returned.expression Then
			Local capturedReturn:TCompilerCCapturedExpression = CaptureExpression(returned.expression)
			result :+ EmitNativeStringPrelude(capturedReturn.nativeStrings, indent)
			returnName = "bmx_cleanup_return_" + nextCleanupReturnId
			nextCleanupReturnId :+ 1
			result :+ indent + ReturnDeclaration(returnName, returned.source) + " = " + capturedReturn.expression + ";~n"
			result :+ EmitNativeStringCleanup(capturedReturn.nativeStrings, indent)
		End If
		Local restoredDebugDepth:Int = CleanupRestoredDebugDepth(returned.cleanupSteps)
		result :+ EmitCleanupSteps(returned.cleanupSteps, indent)
		result :+ EmitDebugLeaves(restoredDebugDepth, indent)
		result :+ EmitPicoRootFrameLeave(indent)
		If currentIsMain And Not returned.expression Then Return result + indent + "return 0;~n"
		If returned.expression Then Return result + indent + "return " + returnName + ";~n"
		If currentReturnType.ToLower() <> "void" Then Return result + indent + "return " + CurrentReturnDefault(returned.source) + ";~n"
		Return result + indent + "return;~n"
	End Method

	Method EmitCleanupSteps:String(cleanupSteps:TCompilerIrCleanupStep[], indent:String)
		Local result:String
		For Local cleanupStep:TCompilerIrCleanupStep = EachIn cleanupSteps
			Local retainedIteratorCleanup:Int = IsRetainedIteratorCleanup(cleanupStep)
			If Not retainedIteratorCleanup Then
				result :+ ExceptionLeaveStatement(indent)
				If DebugEnabled() Then result :+ indent + "bbOnDebugPopExState();~n"
			End If
			If cleanupStep And cleanupStep.usingResources.length Then result :+ EmitUsingCleanup(cleanupStep.usingResources, indent, retainedIteratorCleanup)
			If cleanupStep And cleanupStep.finallyBody Then result :+ EmitBlockContents(cleanupStep.finallyBody, indent)
		Next
		Return result
	End Method

	Method IsRetainedIteratorCleanup:Int(cleanupStep:TCompilerIrCleanupStep)
		If Not cleanupStep Or Not currentRoutine Or Not currentRoutine.isIteratorMoveNext Or Not currentIteratorFactory Then Return False
		If Not cleanupStep.usingResources.length Then Return False
		For Local cleanupResource:TCompilerIrUsingResource = EachIn cleanupStep.usingResources
			If Not cleanupResource Or Not cleanupResource.variable Then Return False
			Local retained:Int
			For Local resource:TCompilerIrUsingResource = EachIn currentIteratorFactory.iteratorOwnedResources
				If resource And resource.variable And resource.variable.symbolId = cleanupResource.variable.symbolId Then retained = True; Exit
			Next
			If Not retained Then Return False
		Next
		Return True
	End Method

	Method ReturnDeclaration:String(name:String, source:TCompilerSourceLocation)
		If currentCallableReturnType.length Then
			Return CCallableFieldDeclaration(currentCallableReturnType, currentCallableReturnParameters, name, source, currentCallableReturnCallingConvention)
		End If
		Return CType(currentReturnType, source) + " " + name
	End Method

	Method EmitConditionalChain:String(conditional:TCompilerIrIf, clauseIndex:Int, indent:String)
		Local condition:TCompilerIrExpression
		Local body:TCompilerIrBlock
		If clauseIndex < 0 Then
			condition = conditional.condition
			body = conditional.thenBody
		Else
			condition = conditional.elseIfClauses[clauseIndex].condition
			body = conditional.elseIfClauses[clauseIndex].body
		End If

		Local captured:TCompilerCCapturedExpression = CaptureExpression(condition, True)
		Local result:String
		Local conditionText:String = captured.expression
		Local wrapped:Int = captured.nativeStrings.names.length > 0
		If wrapped Then
			Local conditionName:String = "bmx_native_condition_" + nextNativeStringId
			nextNativeStringId :+ 1
			result :+ indent + "{~n"
			result :+ EmitNativeStringPrelude(captured.nativeStrings, indent + "    ")
			result :+ indent + "    BBINT " + conditionName + " = (BBINT)(" + conditionText + ");~n"
			result :+ EmitNativeStringCleanup(captured.nativeStrings, indent + "    ")
			conditionText = conditionName
			indent :+ "    "
		End If

		result :+ indent + "if (" + conditionText + ") {~n"
		result :+ EmitBlockContents(body, indent + "    ")
		result :+ indent + "}"
		Local nextClause:Int = clauseIndex + 1
		If nextClause < conditional.elseIfClauses.length Then
			result :+ " else {~n"
			result :+ EmitConditionalChain(conditional, nextClause, indent + "    ")
			result :+ indent + "}"
		Else If conditional.elseBody Then
			result :+ " else {~n"
			result :+ EmitBlockContents(conditional.elseBody, indent + "    ")
			result :+ indent + "}"
		End If
		result :+ "~n"
		If wrapped Then
			indent = indent[..indent.length - 4]
			result :+ indent + "}~n"
		End If
		Return result
	End Method

	Method EmitUsingCleanup:String(resources:TCompilerIrUsingResource[], indent:String, clearResources:Int = False)
		If EmbeddedObjectTypes() Then Return EmitPicoUsingCleanup(resources, indent, clearResources)
		Local result:String
		For Local resourceIndex:Int = resources.length - 1 To 0 Step -1
			Local resource:TCompilerIrUsingResource = resources[resourceIndex]
			result :+ indent + "if (" + EmitCondition(resource.truth) + ") {~n"
			result :+ indent + "    bbExTry {~n"
			result :+ indent + "    case 0: {~n"
			If DebugEnabled() Then result :+ indent + "        bbOnDebugPushExState();~n"
			result :+ indent + "        " + EmitExpression(resource.closeCall) + ";~n"
			result :+ indent + "        bbExLeave();~n"
			If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
			result :+ indent + "    } break;~n"
			result :+ indent + "    case 1: {"
			If DebugEnabled() Then result :+ " bbOnDebugPopExState();"
			result :+ " (void)bbExCatch(); } break;~n"
			result :+ indent + "    }~n"
			result :+ indent + "}~n"
			If clearResources And resource.variable Then result :+ indent + SymbolName(resource.variable.symbolId, resource.variable.name) + " = " + CDefaultValue(resource.variable.semanticType) + ";~n"
		Next
		Return result
	End Method

	Method EmitPicoUsing:String(usingStatement:TCompilerIrUsing, indent:String)
		If currentRoutine And currentRoutine.isIteratorMoveNext And usingStatement.retainedInIterator Then
			AddDiagnostic("BMXC2103", "Pico Using does not yet support a resource retained across Yield", usingStatement.source)
			Return ""
		End If
		Local usingId:String = SafeIdentifier(usingStatement.usingId)
		Local frameName:String = "bmx_pico_" + usingId + "_frame"
		Local failedName:String = "bmx_pico_" + usingId + "_failed"
		Local exceptionName:String = RegisterPicoExceptionRoot("pico.using.exception." + usingId, "bmx_pico_" + usingId + "_exception", "__pico_exception", usingStatement.source)
		Local result:String = indent + "{~n"
		For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
			result :+ EmitStatementBody(resource.variable, indent + "    ")
		Next
		RegisterCleanupDebugDepth(usingStatement.resources)
		result :+ indent + "    BMXPicoExceptionFrame " + frameName + ";~n"
		result :+ indent + "    int32_t " + failedName + " = 0;~n"
		result :+ indent + "    bmx_pico_exception_enter(&" + frameName + ");~n"
		result :+ indent + "    switch (setjmp(" + frameName + ".buffer)) {~n"
		result :+ indent + "    case 0: {~n"
		For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
			Local resourceName:String = LocalName(resource.variable.symbolId, resource.variable.name)
			result :+ indent + "        " + resourceName + " = " + EmitExpression(resource.initializer) + ";~n"
		Next
		result :+ EmitBlockContents(usingStatement.body, indent + "        ")
		result :+ indent + "        bmx_pico_exception_leave();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		result :+ indent + "        " + exceptionName + " = bmx_pico_exception_catch();~n"
		result :+ indent + "        " + failedName + " = 1;~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		result :+ EmitPicoUsingCleanup(usingStatement.resources, indent + "    ")
		result :+ indent + "    if (" + failedName + ") bmx_pico_exception_throw(" + exceptionName + ");~n"
		Return result + indent + "}~n"
	End Method

	Method EmitPicoUsingCleanup:String(resources:TCompilerIrUsingResource[], indent:String, clearResources:Int = False)
		Local result:String
		For Local resourceIndex:Int = resources.length - 1 To 0 Step -1
			Local resource:TCompilerIrUsingResource = resources[resourceIndex]
			Local cleanupId:Int = nextTryFinallyId
			nextTryFinallyId :+ 1
			Local frameName:String = "bmx_pico_using_close_" + cleanupId + "_frame"
			result :+ indent + "if (" + EmitCondition(resource.truth) + ") {~n"
			result :+ indent + "    BMXPicoExceptionFrame " + frameName + ";~n"
			result :+ indent + "    bmx_pico_exception_enter(&" + frameName + ");~n"
			result :+ indent + "    switch (setjmp(" + frameName + ".buffer)) {~n"
			result :+ indent + "    case 0: {~n"
			result :+ indent + "        " + EmitExpression(resource.closeCall) + ";~n"
			result :+ indent + "        bmx_pico_exception_leave();~n"
			result :+ indent + "    } break;~n"
			result :+ indent + "    case 1: { (void)bmx_pico_exception_catch(); } break;~n"
			result :+ indent + "    }~n"
			result :+ indent + "}~n"
			If clearResources And resource.variable Then result :+ indent + SymbolName(resource.variable.symbolId, resource.variable.name) + " = " + CDefaultValue(resource.variable.semanticType) + ";~n"
		Next
		Return result
	End Method

	Method DataReadConversionName:String(kind:Int, source:TCompilerSourceLocation)
		Select kind
			Case DATA_READ_CONVERSION_INT Return "bbConvertToInt"
			Case DATA_READ_CONVERSION_UINT Return "bbConvertToUInt"
			Case DATA_READ_CONVERSION_FLOAT Return "bbConvertToFloat"
			Case DATA_READ_CONVERSION_DOUBLE Return "bbConvertToDouble"
			Case DATA_READ_CONVERSION_LONG Return "bbConvertToLong"
			Case DATA_READ_CONVERSION_ULONG Return "bbConvertToULong"
			Case DATA_READ_CONVERSION_SIZET Return "bbConvertToSizet"
			Case DATA_READ_CONVERSION_LONGINT Return "bbConvertToLongInt"
			Case DATA_READ_CONVERSION_ULONGINT Return "bbConvertToULongInt"
			Case DATA_READ_CONVERSION_STRING Return "bbConvertToString"
		End Select
		AddDiagnostic("BMXC2083", "ReadData conversion kind is not supported", source)
		Return "bbConvertToInt"
	End Method

	Method CurrentReturnDefault:String(source:TCompilerSourceLocation)
		If currentCallableReturnType.length Then Return CallableSentinel(currentCallableReturnType, currentCallableReturnParameters, source, currentCallableReturnCallingConvention)
		Return CDefaultValue(currentReturnType)
	End Method

	Method EmitTryFinally:String(guarded:TCompilerIrTry, indent:String)
		If EmbeddedObjectTypes() Then Return EmitPicoTryFinally(guarded, indent)
		If currentRoutine And currentRoutine.isIteratorMoveNext And guarded.retainedInIterator Then Return EmitIteratorTryFinally(guarded, indent)
		If DebugEnabled() And guarded.finallyBody Then cleanupFinallyDebugDepths.Insert(guarded.finallyBody, String(debugScopeDepth))
		Local tryId:Int = nextTryFinallyId
		nextTryFinallyId :+ 1
		Local exceptionName:String = "bmx_try" + tryId + "_exception"
		Local failedName:String = "bmx_try" + tryId + "_failed"
		Local result:String = indent + "{~n"
		result :+ indent + "    BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
		result :+ indent + "    BBINT " + failedName + " = 0;~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPushExState();~n"
		If guarded.catches.length Then
			Local catchOnly:TCompilerIrTry = New TCompilerIrTry
			catchOnly.body = guarded.body
			catchOnly.catches = guarded.catches
			result :+ EmitTryCatch(catchOnly, indent + "        ")
		Else
			result :+ EmitBlockContents(guarded.body, indent + "        ")
		End If
		result :+ indent + "        bbExLeave();~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
		result :+ indent + "        " + failedName + " = 1;~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		result :+ EmitBlockContents(guarded.finallyBody, indent + "    ")
		result :+ indent + "    if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
		Return result + indent + "}~n"
	End Method

	Method EmitTryCatch:String(guarded:TCompilerIrTry, indent:String)
		If EmbeddedObjectTypes() Then Return EmitPicoTryCatch(guarded, indent)
		If currentRoutine And currentRoutine.isIteratorMoveNext And guarded.retainedInIterator Then Return EmitIteratorTryCatch(guarded, indent)
		Local exceptionName:String = "bmx_exception_" + nextTryFinallyId
		nextTryFinallyId :+ 1
		Local result:String = indent + "{~n"
		result :+ indent + "    BBOBJECT " + exceptionName + ";~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPushExState();~n"
		result :+ EmitBlockContents(guarded.body, indent + "        ")
		result :+ indent + "        bbExLeave();~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
		For Local catchIndex:Int = 0 Until guarded.catches.length
			Local guardedCatch:TCompilerIrCatch = guarded.catches[catchIndex]
			If catchIndex Then result :+ " else " Else result :+ indent + "        "
			result :+ "if (" + CatchCondition(guardedCatch, exceptionName) + ") {~n"
			Local catchName:String = LocalName(guardedCatch.parameterSymbolId, guardedCatch.parameterName)
			localNames.Insert(guardedCatch.parameterSymbolId, catchName)
			result :+ indent + "            " + CType(guardedCatch.parameterType, guardedCatch.source) + " " + catchName + " = (" + CType(guardedCatch.parameterType, guardedCatch.source) + ")" + exceptionName + ";~n"
			result :+ indent + "            (void)" + catchName + ";~n"
			result :+ EmitBlockContents(guardedCatch.body, indent + "            ")
			result :+ indent + "        }"
		Next
		result :+ " else {~n"
		result :+ indent + "            bbExThrow((BBObject *)" + exceptionName + ");~n"
		result :+ indent + "        }~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		Return result + indent + "}~n"
	End Method

	Method EmitPicoTryFinally:String(guarded:TCompilerIrTry, indent:String)
		Local tryId:Int = nextTryFinallyId
		nextTryFinallyId :+ 1
		Local frameName:String = "bmx_pico_try" + tryId + "_frame"
		Local failedName:String = "bmx_pico_try" + tryId + "_failed"
		Local exceptionName:String = RegisterPicoExceptionRoot("pico.try.exception." + tryId, "bmx_pico_try" + tryId + "_exception", "__pico_exception", guarded.source)
		Local result:String = indent + "{~n"
		result :+ indent + "    BMXPicoExceptionFrame " + frameName + ";~n"
		result :+ indent + "    int32_t " + failedName + " = 0;~n"
		result :+ indent + "    bmx_pico_exception_enter(&" + frameName + ");~n"
		result :+ indent + "    switch (setjmp(" + frameName + ".buffer)) {~n"
		result :+ indent + "    case 0: {~n"
		If guarded.catches.length Then
			Local catchOnly:TCompilerIrTry = New TCompilerIrTry
			catchOnly.body = guarded.body
			catchOnly.catches = guarded.catches
			catchOnly.source = guarded.source
			result :+ EmitPicoTryCatch(catchOnly, indent + "        ")
		Else
			result :+ EmitBlockContents(guarded.body, indent + "        ")
		End If
		result :+ indent + "        bmx_pico_exception_leave();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		result :+ indent + "        " + exceptionName + " = bmx_pico_exception_catch();~n"
		result :+ indent + "        " + failedName + " = 1;~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		result :+ EmitBlockContents(guarded.finallyBody, indent + "    ")
		result :+ indent + "    if (" + failedName + ") bmx_pico_exception_throw(" + exceptionName + ");~n"
		Return result + indent + "}~n"
	End Method

	Method EmitPicoTryCatch:String(guarded:TCompilerIrTry, indent:String)
		Local tryId:Int = nextTryFinallyId
		nextTryFinallyId :+ 1
		Local frameName:String = "bmx_pico_catch" + tryId + "_frame"
		Local exceptionName:String = RegisterPicoExceptionRoot("pico.catch.exception." + tryId, "bmx_pico_exception_" + tryId, "__pico_exception", guarded.source)
		Local result:String = indent + "{~n"
		result :+ indent + "    BMXPicoExceptionFrame " + frameName + ";~n"
		result :+ indent + "    bmx_pico_exception_enter(&" + frameName + ");~n"
		result :+ indent + "    switch (setjmp(" + frameName + ".buffer)) {~n"
		result :+ indent + "    case 0: {~n"
		result :+ EmitBlockContents(guarded.body, indent + "        ")
		result :+ indent + "        bmx_pico_exception_leave();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		result :+ indent + "        " + exceptionName + " = bmx_pico_exception_catch();~n"
		For Local catchIndex:Int = 0 Until guarded.catches.length
			Local guardedCatch:TCompilerIrCatch = guarded.catches[catchIndex]
			If catchIndex Then result :+ " else " Else result :+ indent + "        "
			result :+ "if (" + CatchCondition(guardedCatch, exceptionName) + ") {~n"
			Local catchName:String = RegisterPicoExceptionRoot(guardedCatch.parameterSymbolId, guardedCatch.parameterName, guardedCatch.parameterType, guardedCatch.source)
			result :+ indent + "            " + catchName + " = (" + CType(guardedCatch.parameterType, guardedCatch.source) + ")" + exceptionName + ".value;~n"
			result :+ indent + "            (void)" + catchName + ";~n"
			result :+ EmitBlockContents(guardedCatch.body, indent + "            ")
			result :+ indent + "        }"
		Next
		result :+ " else {~n"
		result :+ indent + "            bmx_pico_exception_throw(" + exceptionName + ");~n"
		result :+ indent + "        }~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		Return result + indent + "}~n"
	End Method

	Method EmitIteratorResumeDispatch:String(block:TCompilerIrBlock, stateExpression:String, indent:String, forcedTarget:String = "")
		Local states:Int[]
		CollectIteratorResumeStates(block, states)
		If Not states.length Then Return ""
		Local result:String = indent + "switch (" + stateExpression + ") {~n"
		For Local resumeState:Int = EachIn states
			Local target:String = forcedTarget
			If Not target.length Then target = IteratorResumeTarget(block, resumeState)
			result :+ indent + "    case " + resumeState + ": "
			If target = "bmx_iterator_resume_" + resumeState Then result :+ stateExpression + " = -1; "
			result :+ "goto " + target + ";~n"
		Next
		Return result + indent + "    default: break;~n" + indent + "}~n"
	End Method

	Method EmitIteratorTryFinally:String(guarded:TCompilerIrTry, indent:String)
		If DebugEnabled() And guarded.finallyBody Then cleanupFinallyDebugDepths.Insert(guarded.finallyBody, String(debugScopeDepth))
		Local stateExpression:String = IteratorFieldExpression(currentIteratorFactory.iteratorStateFieldId)
		Local exceptionExpression:String = IteratorFieldExpression(guarded.iteratorExceptionFieldId)
		Local failedExpression:String = IteratorFieldExpression(guarded.iteratorFailedFieldId)
		Local pendingName:String = "bmx_" + SafeIdentifier(guarded.tryId) + "_pending"
		Local result:String = indent + IteratorTryEntryLabel(guarded) + ": ;~n"
		result :+ indent + "{~n"
		result :+ indent + "    if (" + stateExpression + " < 0) { " + exceptionExpression + " = (BBOBJECT)&bbNullObject; " + failedExpression + " = 0; }~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPushExState();~n"
		For Local handler:TCompilerIrCatch = EachIn guarded.catches
			result :+ EmitIteratorResumeDispatch(handler.body, stateExpression, indent + "        ")
		Next
		If guarded.catches.length Then
			result :+ EmitIteratorResumeDispatch(guarded.body, stateExpression, indent + "        ", IteratorTryCatchEntryLabel(guarded))
			result :+ EmitIteratorTryCatch(guarded, indent + "        ")
		Else
			result :+ EmitIteratorResumeDispatch(guarded.body, stateExpression, indent + "        ")
			result :+ EmitBlockContents(guarded.body, indent + "        ")
		End If
		result :+ indent + "        bbExLeave();~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionExpression + " = bbExCatch();~n"
		result :+ indent + "        " + failedExpression + " = 1;~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		result :+ EmitBlockContents(guarded.finallyBody, indent + "    ")
		result :+ indent + "    if (" + failedExpression + ") {~n"
		result :+ indent + "        BBOBJECT " + pendingName + " = " + exceptionExpression + ";~n"
		result :+ indent + "        " + exceptionExpression + " = (BBOBJECT)&bbNullObject; " + failedExpression + " = 0;~n"
		result :+ indent + "        bbExThrow((BBObject *)" + pendingName + ");~n"
		result :+ indent + "    }~n"
		result :+ indent + "    " + exceptionExpression + " = (BBOBJECT)&bbNullObject; " + failedExpression + " = 0;~n"
		Return result + indent + "}~n"
	End Method

	Method EmitIteratorTryCatch:String(guarded:TCompilerIrTry, indent:String)
		Local stateExpression:String = IteratorFieldExpression(currentIteratorFactory.iteratorStateFieldId)
		Local exceptionName:String = "bmx_" + SafeIdentifier(guarded.tryId) + "_exception"
		Local result:String = indent + IteratorTryCatchEntryLabel(guarded) + ": ;~n"
		result :+ indent + "{~n"
		result :+ indent + "    BBOBJECT " + exceptionName + ";~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPushExState();~n"
		result :+ EmitIteratorResumeDispatch(guarded.body, stateExpression, indent + "        ")
		result :+ EmitBlockContents(guarded.body, indent + "        ")
		result :+ indent + "        bbExLeave();~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If DebugEnabled() Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
		For Local catchIndex:Int = 0 Until guarded.catches.length
			Local guardedCatch:TCompilerIrCatch = guarded.catches[catchIndex]
			If catchIndex Then result :+ " else " Else result :+ indent + "        "
			result :+ "if (" + CatchCondition(guardedCatch, exceptionName) + ") {~n"
			Local catchName:String = LocalName(guardedCatch.parameterSymbolId, guardedCatch.parameterName)
			Local retainedCatch:Int = IteratorBlockContainsResumeState(guardedCatch.body)
			If retainedCatch Then catchName = SymbolName(guardedCatch.parameterSymbolId, guardedCatch.parameterName)
			localNames.Insert(guardedCatch.parameterSymbolId, catchName)
			If retainedCatch Then
				result :+ indent + "            " + catchName + " = (" + CType(guardedCatch.parameterType, guardedCatch.source) + ")" + exceptionName + ";~n"
			Else
				result :+ indent + "            " + CType(guardedCatch.parameterType, guardedCatch.source) + " " + catchName + " = (" + CType(guardedCatch.parameterType, guardedCatch.source) + ")" + exceptionName + ";~n"
			End If
			result :+ indent + "            (void)" + catchName + ";~n"
			result :+ EmitBlockContents(guardedCatch.body, indent + "            ")
			result :+ indent + "        }"
		Next
		result :+ " else {~n"
		result :+ indent + "            bbExThrow((BBObject *)" + exceptionName + ");~n"
		result :+ indent + "        }~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		Return result + indent + "}~n"
	End Method

	Method IteratorBlockContainsResumeState:Int(block:TCompilerIrBlock)
		Local states:Int[]
		CollectIteratorResumeStates(block, states)
		Return states.length > 0
	End Method

	Method EmitForRangeValue:String(expression:TCompilerIrExpression, variableType:String, source:TCompilerSourceLocation)
		Return "((" + CType(variableType, source) + ")(" + EmitExpression(expression) + "))"
	End Method

	Method RegisterLoopDebugDepth(loopId:String)
		If Not DebugEnabled() Then Return
		Local depth:String = String(debugScopeDepth)
		loopContinueDebugDepths.Insert(loopId, depth)
		loopExitDebugDepths.Insert(loopId, depth)
	End Method

	Method EmitLoopDebugLeaves:String(depths:TMap, loopId:String, indent:String, currentDepth:Int = -1)
		If Not DebugEnabled() Or Not depths Then Return ""
		Local targetValue:String = String(depths.ValueForKey(loopId))
		If Not targetValue Then Return ""
		Local targetDepth:Int = Int(targetValue)
		If currentDepth < 0 Then currentDepth = debugScopeDepth
		Return EmitDebugLeaves(currentDepth - targetDepth, indent)
	End Method

	Method RegisterCleanupDebugDepth(resources:TCompilerIrUsingResource[])
		If Not DebugEnabled() Then Return
		For Local resource:TCompilerIrUsingResource = EachIn resources
			If resource And resource.variable Then cleanupResourceDebugDepths.Insert(resource.variable.symbolId, String(debugScopeDepth))
		Next
	End Method

	Method CleanupRestoredDebugDepth:Int(cleanupSteps:TCompilerIrCleanupStep[])
		Local depth:Int = debugScopeDepth
		If Not DebugEnabled() Then Return depth
		For Local cleanupStep:TCompilerIrCleanupStep = EachIn cleanupSteps
			If Not cleanupStep Then Continue
			If cleanupStep.usingResources.length And cleanupStep.usingResources[0] And cleanupStep.usingResources[0].variable Then
				Local resourceDepth:String = String(cleanupResourceDebugDepths.ValueForKey(cleanupStep.usingResources[0].variable.symbolId))
				If resourceDepth Then depth = Int(resourceDepth)
			End If
			If cleanupStep.finallyBody Then
				Local finallyDepth:String = String(cleanupFinallyDebugDepths.ValueForKey(cleanupStep.finallyBody))
				If finallyDepth Then depth = Int(finallyDepth)
			End If
		Next
		Return depth
	End Method

	Function LoopContinueLabel:String(loopId:String)
		Return "bmx_" + loopId + "_continue"
	End Function

	Function LoopExitLabel:String(loopId:String)
		Return "bmx_" + loopId + "_exit"
	End Function

	Method EmitCondition:String(expression:TCompilerIrExpression)
		Local emitted:String = EmitExpression(expression)
		If HasEnclosingParentheses(emitted) Then Return emitted[1..emitted.length - 1]
		Return emitted
	End Method

	Function HasEnclosingParentheses:Int(value:String)
		If value.length < 2 Or value[0] <> Asc("(") Or value[value.length - 1] <> Asc(")") Then Return False
		Local depth:Int
		For Local index:Int = 0 Until value.length
			Select value[index]
				Case Asc("(")
					depth :+ 1
				Case Asc(")")
					depth :- 1
					If depth < 0 Or (depth = 0 And index < value.length - 1) Then Return False
			End Select
		Next
		Return depth = 0
	End Function

	Method CaptureExpression:TCompilerCCapturedExpression(expression:TCompilerIrExpression, condition:Int = False)
		Local previousScope:TCompilerCNativeStringScope = nativeStringScope
		Local captured:TCompilerCCapturedExpression = New TCompilerCCapturedExpression
		captured.nativeStrings = New TCompilerCNativeStringScope
		nativeStringScope = captured.nativeStrings
		If condition Then captured.expression = EmitCondition(expression) Else captured.expression = EmitExpression(expression)
		nativeStringScope = previousScope
		Return captured
	End Method

	Method EmitNativeStringPrelude:String(scope:TCompilerCNativeStringScope, indent:String)
		If Not scope Then Return ""
		Local result:String
		For Local index:Int = 0 Until scope.names.length
			result :+ indent + "BBBYTE *" + scope.names[index] + " = (BBBYTE *)bbStringToCString(" + scope.values[index] + ");~n"
		Next
		Return result
	End Method

	Method EmitNativeStringCleanup:String(scope:TCompilerCNativeStringScope, indent:String)
		If Not scope Then Return ""
		Local result:String
		For Local index:Int = scope.names.length - 1 To 0 Step -1
			result :+ indent + "bbMemFree(" + scope.names[index] + ");~n"
		Next
		Return result
	End Method

	Method EmitExpression:String(expression:TCompilerIrExpression)
		If Not expression Then
			AddDiagnostic("BMXC2010", "IR expression was not available", Null)
			Return "0"
		End If
		Local materialization:TCompilerIrMaterialize = TCompilerIrMaterialize(expression)
		If materialization Then
			RegisterTemporary(materialization)
			If preparedTemporaryValues.Contains(materialization.temporaryId) Then Return EmitExpression(materialization.expression)
			Return "((" + TemporaryName(materialization.temporaryId) + " = " + EmitExpression(materialization.value) + "), " + EmitExpression(materialization.expression) + ")"
		End If
		Local literal:TCompilerIrLiteral = TCompilerIrLiteral(expression)
		If literal Then
			If literal.stringLiteralId.length Then
				Local stringName:String = String(stringNames.ValueForKey(literal.stringLiteralId))
				If stringName.length And (runtimeTypes Or EmbeddedStringTypes()) Then Return stringName
				AddDiagnostic("BMXC2025", "Managed String literals require the BlitzMax runtime C backend", literal.source)
				Return "0"
			End If
			Local literalStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(literal.semanticType.ToLower()))
			If literalStruct And literal.text.Trim() = "0" Then Return "((struct " + StructName(literalStruct.structId) + "){0})"
			Local literalImportedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(literal.semanticType.ToLower()))
			If literalImportedStruct And literal.text.Trim() = "0" Then Return "((struct " + literalImportedStruct.abiName + "){0})"
			Local emittedLiteral:String = CLiteral(literal.text, literal.source)
			If literal.semanticType.Trim().ToLower() = "ulong" Then emittedLiteral :+ "ULL"
			Return emittedLiteral
		End If
		Local symbol:TCompilerIrSymbolReference = TCompilerIrSymbolReference(expression)
		If symbol Then
			Local symbolName:String = SymbolName(symbol.symbolId, symbol.name)
			If symbol.isByReference Then Return "(*" + symbolName + ")"
			Return symbolName
		End If
		Local address:TCompilerIrAddressOf = TCompilerIrAddressOf(expression)
		If address Then
			Local operandAddress:String = "(&" + EmitExpression(address.operand) + ")"
			If address.castStorageAddress Then
				Return "((" + CType(address.semanticType, address.source) + " *)" + operandAddress + ")"
			End If
			Return operandAddress
		End If
		Local pointerTruth:TCompilerIrPointerTruth = TCompilerIrPointerTruth(expression)
		If pointerTruth Then
			If pointerTruth.negate Then Return "(" + EmitExpression(pointerTruth.operand) + " == 0)"
			Return "(" + EmitExpression(pointerTruth.operand) + " != 0)"
		End If
		Local pointerBinary:TCompilerIrPointerBinary = TCompilerIrPointerBinary(expression)
		If pointerBinary Then Return "(" + EmitExpression(pointerBinary.left) + " " + CBinaryOperator(pointerBinary.operatorText, pointerBinary.source) + " " + EmitExpression(pointerBinary.right) + ")"
		Local structNew:TCompilerIrStructNew = TCompilerIrStructNew(expression)
		If structNew Then
			Local helperName:String
			If structNew.importedStructId.length Then
				If Not structNew.importedConstructorId.length Then Return CDefaultValue(structNew.semanticType)
				Local importedConstructor:TCompilerIrImportedStructRoutine = ImportedStructRoutineById(structNew.importedConstructorId)
				If importedConstructor Then helperName = importedConstructor.objectNewAbiName
				If Not helperName.length Then
					AddDiagnostic("BMXC2062", "Imported Struct constructor '" + structNew.importedConstructorId + "' has no value helper ABI", structNew.source)
					Return CDefaultValue(structNew.semanticType)
				End If
			Else
				helperName = StructNewHelperName(structNew.structId, structNew.constructorFunctionId)
			End If
			Local result:String = helperName + "("
			For Local index:Int = 0 Until structNew.arguments.length
				If index Then result :+ ", "
				result :+ EmitExpression(structNew.arguments[index])
			Next
			Return result + ")"
		End If
		Local callableReference:TCompilerIrCallableReference = TCompilerIrCallableReference(expression)
		If callableReference Then
			If callableReference.abiName.length Then Return callableReference.abiName
			Return FunctionName(callableReference.functionId)
		End If
		Local closureLiteral:TCompilerIrClosureLiteral = TCompilerIrClosureLiteral(expression)
		If closureLiteral Then
			If EmbeddedObjectTypes() Then
				Local picoTargetName:String = closureLiteral.abiName
				If Not picoTargetName.length Then picoTargetName = FunctionName(closureLiteral.functionId)
				Local picoEnvironment:String = "(BMXPicoObject *)&bmx_pico_null_object"
				If closureLiteral.environment Then picoEnvironment = "(BMXPicoObject *)" + EmitExpression(closureLiteral.environment)
				Return "bmx_pico_closure_allocate((BMXPicoMethod)&" + picoTargetName + ", " + picoEnvironment + ")"
			End If
			If closureLiteral.environment Then
				Local targetName:String = closureLiteral.abiName
				If Not targetName.length Then targetName = FunctionName(closureLiteral.functionId)
				Return "bmx_closure_capture_new((BBFuncPtr)&" + targetName + ", (BBOBJECT)" + EmitExpression(closureLiteral.environment) + ")"
			End If
			Return "(&" + ClosureLiteralName(closureLiteral.literalId) + ")"
		End If
		Local call:TCompilerIrCall = TCompilerIrCall(expression)
		If call Then
			If EmbeddedStringTypes() And call.isExternal Then
				Local picoStringExternal:TCompilerIrExternalFunction = TCompilerIrExternalFunction(externalFunctionsById.ValueForKey(call.functionId))
				If PicoDesktopStringFunction(picoStringExternal) And Not PicoStringRuntimeFunctionName(picoStringExternal).length Then
					AddDiagnostic("BMXC2025", "String method '" + call.functionName + "' is not available in the current Pico embedded String profile", call.source)
					Return CDefaultValue(call.semanticType)
				End If
			End If
			Local result:String
			If call.dispatchKind = IR_CALL_DISPATCH_INTERFACE Then
				Return EmitInterfaceCall(call)
			Else If call.dispatchKind = IR_CALL_DISPATCH_INTERFACE_SUPER Then
				Local targetName:String = call.functionAbiName
				If Not targetName.length Then targetName = FunctionName(call.functionId)
				result = targetName + "(" + EmitExpression(call.receiver)
				If call.arguments.length Then result :+ ", "
				For Local index:Int = 0 Until call.arguments.length
					If index Then result :+ ", "
					result :+ EmitExpression(call.arguments[index])
				Next
				Return result + ")"
			Else If call.dispatchKind = IR_CALL_DISPATCH_IMPORTED_VIRTUAL Then
				Return EmitImportedVirtualCall(call)
			Else If call.dispatchKind = IR_CALL_DISPATCH_SUPER Then
				Return EmitSuperCall(call)
			Else If call.dispatchKind = IR_CALL_DISPATCH_STRUCT Then
				result = FunctionName(call.functionId) + "(" + EmitExpression(call.receiver)
				If call.arguments.length Then result :+ ", "
			Else If call.dispatchKind = IR_CALL_DISPATCH_TYPE_FUNCTION Then
				If EmbeddedObjectTypes() Then
					result = FunctionName(call.functionId) + "("
				Else
					Return EmitTypeFunctionCall(call)
				End If
			Else If call.dispatchKind = IR_CALL_DISPATCH_EXACT Then
				Local exactTarget:TCompilerIrFunction = FunctionById(call.functionId)
				Local exactReceiver:String = EmitExpression(call.receiver)
				exactReceiver = DebugObjectReceiver(exactReceiver, call.receiver.semanticType, call.source)
				If Not exactTarget Or Not exactTarget.receiver Then
					AddDiagnostic("BMXC2053", "Exact method call target '" + call.functionId + "' was not emitted", call.source)
					Return "0"
				End If
				result = FunctionName(call.functionId) + "((" + CType(exactTarget.receiver.semanticType, call.source) + ")" + exactReceiver
				If call.arguments.length Then result :+ ", "
			Else If call.dispatchKind = IR_CALL_DISPATCH_VIRTUAL Then
				Local receiver:String = EmitExpression(call.receiver)
				If EmbeddedObjectTypes() Then
					If call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
						Select call.objectSlotKind
							Case IR_OBJECT_SLOT_COMPARE
								Return "bmx_pico_object_compare((void *)" + receiver + ", (void *)" + EmitExpression(call.arguments[0]) + ")"
							Case IR_OBJECT_SLOT_HASH_CODE
								Return "bmx_pico_object_hash_code((void *)" + receiver + ")"
							Case IR_OBJECT_SLOT_EQUALS
								Return "bmx_pico_object_equals((void *)" + receiver + ", (void *)" + EmitExpression(call.arguments[0]) + ")"
							Case IR_OBJECT_SLOT_TO_STRING
								AddDiagnostic("BMXC2029", "Object ToString requires dynamic Pico String support", call.source)
							Case IR_OBJECT_SLOT_SEND_MESSAGE
								AddDiagnostic("BMXC2029", "Object SendMessage is not available in the current Pico Object profile", call.source)
						End Select
						Return CDefaultValue(call.semanticType)
					End If
					Local dispatchClass:TCompilerIrClass = ClassById(call.classId)
					Local dispatchSlot:TCompilerIrClassFunctionSlot = ClassSlot(call.classId, call.classSlotId)
					Local dispatchIndex:Int = PicoClassSlotIndex(dispatchClass, call.classSlotId)
					Local pointerType:String = PicoSlotFunctionPointerType(dispatchSlot)
					If Not dispatchClass Or dispatchIndex < 0 Or Not pointerType.length Then
						AddDiagnostic("BMXC2029", "Virtual dispatch slot is not available in the current Pico Type descriptor", call.source)
						Return "0"
					End If
					Local checkedReceiver:String = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
					Local receiverArgument:String = receiver
					Local receiverClass:TCompilerIrClass = ClassById(dispatchSlot.receiverClassId)
					If Not receiverClass Then receiverClass = ClassById(dispatchSlot.declaringClassId)
					If receiverClass Then receiverArgument = "(struct " + ObjectName(receiverClass.classId) + " *)" + receiver
					result = "((" + pointerType + ")((BMXPicoObject *)" + checkedReceiver + ")->type->methods[" + dispatchIndex + "])(" + receiverArgument
					If call.arguments.length Then result :+ ", "
				Else
					receiver = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
					If call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
						result = receiver + "->clas->" + ObjectSlotName(call.objectSlotKind) + "((BBOBJECT)" + receiver
						If call.arguments.length Then result :+ ", "
						For Local index:Int = 0 Until call.arguments.length
							If index Then result :+ ", "
							result :+ "(BBOBJECT)" + EmitExpression(call.arguments[index])
						Next
						Return result + ")"
					End If
					Local slot:TCompilerIrClassFunctionSlot = ClassSlot(call.classId, call.classSlotId)
					If Not slot Then
						AddDiagnostic("BMXC2053", "Virtual call slot '" + call.classId + "." + call.classSlotId + "' was not emitted", call.source)
						Return "0"
					End If
					Local receiverArgument:String = receiver
					If slot.receiverClassId.length Then receiverArgument = "(struct " + ObjectName(slot.receiverClassId) + " *)" + receiver
					If slot.receiverImportedClassId.length Then
						Local importedReceiver:TCompilerIrImportedClass = ImportedClassById(slot.receiverImportedClassId)
						If importedReceiver Then receiverArgument = "(struct " + importedReceiver.abiName + "_obj *)" + receiver
					End If
					result = receiver + "->clas->" + ClassFunctionSlotName(slot) + "(" + receiverArgument
					If call.arguments.length Then result :+ ", "
				End If
			Else
				result = FunctionName(call.functionId) + "("
			End If
			For Local index:Int = 0 Until call.arguments.length
				If index Then result :+ ", "
				Local argument:String = EmitExpression(call.arguments[index])
				If call.isExternal Then
					Local externalFunction:TCompilerIrExternalFunction = TCompilerIrExternalFunction(externalFunctionsById.ValueForKey(call.functionId))
					If externalFunction And Not NeedsNativeStringWrapper(externalFunction) And index < externalFunction.nativeParameterTypes.length And externalFunction.nativeParameterTypes[index].length Then
						argument = "((" + externalFunction.nativeParameterTypes[index] + ")" + argument + ")"
					Else If externalFunction And index < externalFunction.parameters.length And externalFunction.isDirectMethod And index = 0 And externalFunction.parameters[index].semanticType.ToLower() = "object" Then
						' A Super Object receiver keeps concrete C storage even though
						' its IR type is Object. C requires the runtime ABI upcast.
						argument = "((" + CParameterType(externalFunction.parameters[index], call.source) + ")" + argument + ")"
					End If
				End If
				result :+ argument
			Next
			result :+ ")"
			If call.isExternal Then
				Local externalFunction:TCompilerIrExternalFunction = TCompilerIrExternalFunction(externalFunctionsById.ValueForKey(call.functionId))
				If externalFunction And Not NeedsNativeStringWrapper(externalFunction) And externalFunction.nativeReturnType.length And (IsManagedCReferenceType(call.semanticType) Or IsPointerSemanticType(call.semanticType)) Then
					' Native pointer typedefs such as HMODULE/HHOOK and specific
					' managed pointers need an explicit conversion to BlitzMax storage.
					result = "((" + CType(call.semanticType, call.source) + ")(" + result + "))"
				End If
			End If
			Return result
		End If
		Local indirect:TCompilerIrIndirectCall = TCompilerIrIndirectCall(expression)
		If indirect Then
			Local result:String = "((" + EmitExpression(indirect.callee)
			result :+ ")("
			For Local index:Int = 0 Until indirect.arguments.length
				If index Then result :+ ", "
				result :+ EmitExpression(indirect.arguments[index])
			Next
			Return result + "))"
		End If
		Local closureCall:TCompilerIrClosureCall = TCompilerIrClosureCall(expression)
		If closureCall Then Return EmitClosureCall(closureCall)
		Local callableDefault:TCompilerIrCallableDefault = TCompilerIrCallableDefault(expression)
		If callableDefault Then Return CallableSentinel(callableDefault.returnType, callableDefault.parameters, callableDefault.source, callableDefault.callingConvention)
		Local callableTruth:TCompilerIrCallableTruth = TCompilerIrCallableTruth(expression)
		If callableTruth Then
			Local operand:String = EmitExpression(callableTruth.operand)
			Local sentinel:String = CallableSentinel(callableTruth.returnType, callableTruth.parameters, callableTruth.source, callableTruth.callingConvention)
			If callableTruth.negate Then Return "((" + operand + " == 0) || (" + operand + " == " + sentinel + "))"
			Return "((" + operand + " != 0) && (" + operand + " != " + sentinel + "))"
		End If
		Local enumIntrinsic:TCompilerIrEnumIntrinsic = TCompilerIrEnumIntrinsic(expression)
		If enumIntrinsic Then Return EmitEnumIntrinsic(enumIntrinsic)
		Local unary:TCompilerIrUnary = TCompilerIrUnary(expression)
		If unary Then
			If unary.operatorText.ToLower() = "stackalloc" Then Return "bbStackAlloc(" + EmitExpression(unary.operand) + ")"
			If unary.measureType.length Then
				If unary.operatorText.ToLower() = "sizeof" Then Return "(sizeof(" + CType(unary.measureType, unary.source) + "))"
				If unary.operatorText.ToLower() = "alignof" Then Return "(__alignof__(" + CType(unary.measureType, unary.source) + "))"
			End If
			Return "(" + CUnaryOperator(unary.operatorText, unary.source) + EmitExpression(unary.operand) + ")"
		End If
		Local binary:TCompilerIrBinary = TCompilerIrBinary(expression)
		If binary Then
			If binary.operatorText = "^" Then
				Return "((" + CType(binary.semanticType, binary.source) + ")bbFloatPow((BBDOUBLE)(" + EmitExpression(binary.left) + "), (BBDOUBLE)(" + EmitExpression(binary.right) + ")))"
			End If
			If binary.operatorText.ToLower() = "mod" Then
				Select binary.semanticType.ToLower()
					Case "float", "double", "float64"
						Return "((" + CType(binary.semanticType, binary.source) + ")bbFloatMod((BBDOUBLE)(" + EmitExpression(binary.left) + "), (BBDOUBLE)(" + EmitExpression(binary.right) + ")))"
				End Select
			End If
			Return "(" + EmitExpression(binary.left) + " " + CBinaryOperator(binary.operatorText, binary.source) + " " + EmitExpression(binary.right) + ")"
		End If
		Local conversion:TCompilerIrConversion = TCompilerIrConversion(expression)
		If conversion Then Return EmitConversion(conversion)
		Local concat:TCompilerIrStringConcat = TCompilerIrStringConcat(expression)
		If concat Then
			If EmbeddedStringTypes() Then
				Return "bmx_pico_string_concat(" + EmitExpression(concat.left) + ", " + EmitExpression(concat.right) + ")"
			End If
			Return "bbStringConcat(" + EmitExpression(concat.left) + ", " + EmitExpression(concat.right) + ")"
		End If
		Local comparison:TCompilerIrStringCompare = TCompilerIrStringCompare(expression)
		If comparison Then
			Local comparisonCall:String
			If EmbeddedStringTypes() Then
				If comparison.operatorText = "=" Or comparison.operatorText = "<>" Then
					comparisonCall = "bmx_pico_string_equals(" + EmitExpression(comparison.left) + ", " + EmitExpression(comparison.right) + ")"
					If comparison.operatorText = "=" Then Return "(" + comparisonCall + " != 0)"
					Return "(" + comparisonCall + " == 0)"
				End If
				comparisonCall = "bmx_pico_string_compare(" + EmitExpression(comparison.left) + ", " + EmitExpression(comparison.right) + ")"
				Return "(" + comparisonCall + " " + CBinaryOperator(comparison.operatorText, comparison.source) + " 0)"
			End If
			If comparison.operatorText = "=" Or comparison.operatorText = "<>" Then
				comparisonCall = "bbStringEquals(" + EmitExpression(comparison.left) + ", " + EmitExpression(comparison.right) + ")"
				If comparison.operatorText = "=" Then Return "(" + comparisonCall + " == 1)"
				Return "(" + comparisonCall + " != 1)"
			End If
			comparisonCall = "bbStringCompare(" + EmitExpression(comparison.left) + ", " + EmitExpression(comparison.right) + ")"
			Return "(" + comparisonCall + " " + CBinaryOperator(comparison.operatorText, comparison.source) + " 0)"
		End If
		Local truth:TCompilerIrManagedTruth = TCompilerIrManagedTruth(expression)
		If truth Then
			If truth.managedKind = IR_MANAGED_REFERENCE_STRING Or truth.managedKind = IR_MANAGED_REFERENCE_ARRAY Or truth.managedKind = IR_MANAGED_REFERENCE_OBJECT Or truth.managedKind = IR_MANAGED_REFERENCE_CLOSURE Then
				Local truthOperator:String = "!="
				If truth.negate Then truthOperator = "=="
				Local sentinel:String = "&bbEmptyString"
				If truth.managedKind = IR_MANAGED_REFERENCE_STRING And EmbeddedStringTypes() Then sentinel = "&bmx_pico_empty_string"
				If truth.managedKind = IR_MANAGED_REFERENCE_ARRAY Then
					If EmbeddedArrayTypes() Then sentinel = "&bmx_pico_empty_array" Else sentinel = "&bbEmptyArray"
				End If
				If truth.managedKind = IR_MANAGED_REFERENCE_OBJECT Then
					If EmbeddedObjectTypes() Then sentinel = "((" + CType(truth.operand.semanticType, truth.source) + ")&bmx_pico_null_object)" Else sentinel = "((" + CType(truth.operand.semanticType, truth.source) + ")&bbNullObject)"
				End If
				If truth.managedKind = IR_MANAGED_REFERENCE_CLOSURE Then
					If EmbeddedObjectTypes() Then sentinel = "((BMXPicoClosure *)&bmx_pico_null_object)" Else sentinel = "((BBClosure *)&bbNullObject)"
				End If
				Local truthOperand:String = DebugManagedValue(EmitExpression(truth.operand), truth.managedKind, truth.operand.semanticType, truth.source)
				Return "(" + truthOperand + " " + truthOperator + " " + sentinel + ")"
			End If
			AddDiagnostic("BMXC2014", "Managed truth kind '" + truth.managedKind + "' has no runtime sentinel mapping", truth.source)
			Return "0"
		End If
		Local defaultValue:TCompilerIrManagedDefault = TCompilerIrManagedDefault(expression)
		If defaultValue Then
			Select defaultValue.managedKind
				Case IR_MANAGED_REFERENCE_STRING
					If EmbeddedStringTypes() Then Return "&bmx_pico_empty_string"
					Return "&bbEmptyString"
				Case IR_MANAGED_REFERENCE_ARRAY
					If EmbeddedArrayTypes() Then Return "&bmx_pico_empty_array"
					Return "&bbEmptyArray"
				Case IR_MANAGED_REFERENCE_OBJECT
					If EmbeddedObjectTypes() Then Return "((" + CType(defaultValue.semanticType, defaultValue.source) + ")&bmx_pico_null_object)"
					Return "((" + CType(defaultValue.semanticType, defaultValue.source) + ")&bbNullObject)"
				Case IR_MANAGED_REFERENCE_CLOSURE
					If EmbeddedObjectTypes() Then Return "((BMXPicoClosure *)&bmx_pico_null_object)"
					Return "((BBClosure *)&bbNullObject)"
			End Select
			AddDiagnostic("BMXC2014", "Managed default kind '" + defaultValue.managedKind + "' has no runtime sentinel mapping", defaultValue.source)
			Return "0"
		End If
		Local identity:TCompilerIrManagedIdentity = TCompilerIrManagedIdentity(expression)
		If identity Then
			Local identityOperator:String = "=="
			If identity.operatorText = "<>" Then identityOperator = "!="
			Local leftIdentity:String = DebugManagedValue(EmitExpression(identity.left), identity.managedKind, identity.left.semanticType, identity.source)
			Local rightIdentity:String = DebugManagedValue(EmitExpression(identity.right), identity.managedKind, identity.right.semanticType, identity.source)
			If identity.managedKind = IR_MANAGED_REFERENCE_OBJECT And EmbeddedObjectTypes() Then
				leftIdentity = "(void *)" + leftIdentity
				rightIdentity = "(void *)" + rightIdentity
			Else If identity.managedKind = IR_MANAGED_REFERENCE_OBJECT Or identity.managedKind = IR_MANAGED_REFERENCE_CLOSURE Then
				leftIdentity = "(BBOBJECT)" + leftIdentity
				rightIdentity = "(BBOBJECT)" + rightIdentity
			End If
			Return "(" + leftIdentity + " " + identityOperator + " " + rightIdentity + ")"
		End If
		Local arrayNew:TCompilerIrArrayNew = TCompilerIrArrayNew(expression)
		If arrayNew Then
			If EmbeddedArrayTypes() Then
				If arrayNew.rank <> 1 Or arrayNew.dimensions.length <> 1 Then
					AddDiagnostic("BMXC2028", "Only one-dimensional Arrays are available in the initial Pico embedded profile", arrayNew.source)
					Return "&bmx_pico_empty_array"
				End If
				If Not PicoArrayElementSupported(arrayNew.elementType) Then
					AddDiagnostic("BMXC2028", "Array element type '" + arrayNew.elementType + "' is not available in the Pico managed-container profile", arrayNew.source)
					Return "&bmx_pico_empty_array"
				End If
				Local initializer:String = "0"
				If arrayNew.structId.length Then
					Local elementStruct:TCompilerIrStruct = StructById(arrayNew.structId)
					If Not PicoPlainStructSupported(elementStruct) Then
						AddDiagnostic("BMXC2091", "Array element Struct '" + arrayNew.elementType + "' is not supported by the Pico value-descriptor tier", arrayNew.source)
						Return "&bmx_pico_empty_array"
					End If
					initializer = StructArrayInitializerName(arrayNew.structId, "")
				Else If arrayNew.importedStructId.length Then
					Local importedElementStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arrayNew.importedStructId))
					If Not PicoPlainImportedStructSupported(importedElementStruct) Or Not importedElementStruct.elementInitializerAbiName.length Then
						AddDiagnostic("BMXC2091", "Imported array element Struct '" + arrayNew.elementType + "' has no supported Pico element initializer ABI", arrayNew.source)
						Return "&bmx_pico_empty_array"
					End If
					initializer = importedElementStruct.elementInitializerAbiName
				End If
				Local valueDescriptor:String = "0"
				If arrayNew.structId.length Then
					Local descriptorStruct:TCompilerIrStruct = StructById(arrayNew.structId)
					If descriptorStruct And descriptorStruct.containsManagedReferences Then valueDescriptor = "&" + PicoStructDescriptorName(descriptorStruct)
				Else If arrayNew.importedStructId.length Then
					Local importedDescriptorStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arrayNew.importedStructId))
					If importedDescriptorStruct And importedDescriptorStruct.containsManagedReferences Then valueDescriptor = "&" + PicoImportedStructDescriptorName(importedDescriptorStruct)
				End If
				Return "bmx_pico_array_new_1d((int32_t)(" + EmitExpression(arrayNew.dimensions[0]) + "), (uint32_t)sizeof(" + CType(arrayNew.elementType, arrayNew.source) + "), " + PicoArrayElementKind(arrayNew.elementType) + ", " + initializer + ", " + valueDescriptor + ")"
			End If
			If arrayNew.rank = 1 And arrayNew.dimensions.length = 1 Then
				If arrayNew.enumId.length Then
					Local arrayEnum:TCompilerIrEnum = EnumById(arrayNew.enumId)
					If Not arrayEnum Or Not arrayEnum.runtimeDescriptor Then
						AddDiagnostic("BMXC2076", "Enum array element type '" + arrayNew.elementType + "' has no runtime descriptor", arrayNew.source)
						Return "&bbEmptyArray"
					End If
					Return "bbArrayNew1DEnum(" + CQuoted(arrayNew.elementEncoding) + ", " + EmitExpression(arrayNew.dimensions[0]) + ", " + arrayEnum.runtimeDescriptor.descriptorAbiName + ")"
				End If
				If arrayNew.structId.length Or arrayNew.importedStructId.length Then
					If arrayNew.importedStructId.length Then
						Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arrayNew.importedStructId))
						If Not importedStruct Then
							AddDiagnostic("BMXC2071", "Imported Struct array element type '" + arrayNew.elementType + "' has no published layout", arrayNew.source)
							Return "&bbEmptyArray"
						End If
						Return PublishedStructArrayNewName(importedStruct.abiName) + "(" + EmitExpression(arrayNew.dimensions[0]) + ")"
					End If
					Local initializerName:String = StructArrayInitializerName(arrayNew.structId, arrayNew.importedStructId)
					Return "bbArrayNew1DStruct(" + CQuoted(arrayNew.elementEncoding) + ", " + EmitExpression(arrayNew.dimensions[0]) + ", sizeof(" + CType(arrayNew.elementType, arrayNew.source) + "), " + initializerName + ")"
				End If
				Return "bbArrayNew1D(" + CQuoted(arrayNew.elementEncoding) + ", " + EmitExpression(arrayNew.dimensions[0]) + ")"
			End If
			If arrayNew.rank > 1 And arrayNew.dimensions.length = arrayNew.rank Then
				Local dimensions:String
				For Local dimension:TCompilerIrExpression = EachIn arrayNew.dimensions
					dimensions :+ ", " + EmitExpression(dimension)
				Next
				If arrayNew.enumId.length Then
					Local arrayEnum:TCompilerIrEnum = EnumById(arrayNew.enumId)
					If Not arrayEnum Or Not arrayEnum.runtimeDescriptor Then
						AddDiagnostic("BMXC2076", "Enum array element type '" + arrayNew.elementType + "' has no runtime descriptor", arrayNew.source)
						Return "&bbEmptyArray"
					End If
					Return "bbArrayNewEnum(" + CQuoted(arrayNew.elementEncoding) + ", " + arrayEnum.runtimeDescriptor.descriptorAbiName + ", " + arrayNew.rank + dimensions + ")"
				End If
				If arrayNew.structId.length Then
					Return "bbArrayNewStruct(" + CQuoted(arrayNew.elementEncoding) + ", sizeof(" + CType(arrayNew.elementType, arrayNew.source) + "), " + StructArrayInitializerName(arrayNew.structId, "") + ", " + arrayNew.rank + dimensions + ")"
				End If
				If arrayNew.importedStructId.length Then
					Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arrayNew.importedStructId))
					If Not importedStruct Or Not importedStruct.elementInitializerAbiName.length Then
						AddDiagnostic("BMXC2050", "Multidimensional imported Struct array allocation requires a published element initializer ABI", arrayNew.source)
						Return "&bbEmptyArray"
					End If
					Return "bbArrayNewStruct(" + CQuoted(arrayNew.elementEncoding) + ", sizeof(" + CType(arrayNew.elementType, arrayNew.source) + "), " + importedStruct.elementInitializerAbiName + ", " + arrayNew.rank + dimensions + ")"
				End If
				Return "bbArrayNew(" + CQuoted(arrayNew.elementEncoding) + ", " + arrayNew.rank + dimensions + ")"
			End If
			AddDiagnostic("BMXC2050", "Array allocation rank and dimension count do not match", arrayNew.source)
			Return "&bbEmptyArray"
		End If
		Local arrayLength:TCompilerIrArrayLength = TCompilerIrArrayLength(expression)
		If arrayLength Then
			If EmbeddedArrayTypes() Then Return "((" + EmitExpression(arrayLength.receiver) + ")->length)"
			Return "((" + DebugManagedValue(EmitExpression(arrayLength.receiver), IR_MANAGED_REFERENCE_ARRAY, arrayLength.receiver.semanticType, arrayLength.source) + ")->scales[0])"
		End If
		Local stringSlice:TCompilerIrStringSlice = TCompilerIrStringSlice(expression)
		If stringSlice Then
			Local receiver:String = DebugManagedValue(EmitExpression(stringSlice.receiver), IR_MANAGED_REFERENCE_STRING, stringSlice.receiver.semanticType, stringSlice.source)
			Local lowerBound:String = EmitExpression(stringSlice.lowerBound)
			If stringSlice.lowerFromEnd Then lowerBound = "((" + receiver + ")->length - (" + lowerBound + "))"
			Local upperBound:String
			If stringSlice.upperBoundOmitted Then
				upperBound = "((" + receiver + ")->length)"
			Else
				upperBound = EmitExpression(stringSlice.upperBound)
				If stringSlice.upperFromEnd Then upperBound = "((" + receiver + ")->length - (" + upperBound + "))"
			End If
			If EmbeddedStringTypes() Then Return "bmx_pico_string_slice(" + receiver + ", " + lowerBound + ", " + upperBound + ")"
			Return "bbStringSlice(" + receiver + ", " + lowerBound + ", " + upperBound + ")"
		End If
		Local stringLength:TCompilerIrStringLength = TCompilerIrStringLength(expression)
		If stringLength Then Return "((" + DebugManagedValue(EmitExpression(stringLength.receiver), IR_MANAGED_REFERENCE_STRING, stringLength.receiver.semanticType, stringLength.source) + ")->length)"
		Local stringElement:TCompilerIrStringElement = TCompilerIrStringElement(expression)
		If stringElement Then
			If runtimeTypes And stringElement.boundsCheck Then Return "bmx_debug_string_element(" + DebugManagedValue(EmitExpression(stringElement.receiver), IR_MANAGED_REFERENCE_STRING, stringElement.receiver.semanticType, stringElement.source) + ", " + EmitExpression(stringElement.index) + ")"
			Local indexType:String = "BBUINT"
			If EmbeddedStringTypes() Then indexType = "uint32_t"
			Return "((" + EmitExpression(stringElement.receiver) + ")->buf[(" + indexType + ")" + EmitExpression(stringElement.index) + "])"
		End If
		Local stringAsc:TCompilerIrStringAsc = TCompilerIrStringAsc(expression)
		If stringAsc Then
			If EmbeddedStringTypes() Then Return "bmx_pico_string_asc(" + EmitExpression(stringAsc.receiver) + ")"
			Return "bbStringAsc(" + EmitExpression(stringAsc.receiver) + ")"
		End If
		Local stringChr:TCompilerIrStringChr = TCompilerIrStringChr(expression)
		If stringChr Then
			If EmbeddedStringTypes() Then Return "bmx_pico_string_from_char(" + EmitExpression(stringChr.codePoint) + ")"
			Return "bbStringFromChar(" + EmitExpression(stringChr.codePoint) + ")"
		End If
		Local arraySlice:TCompilerIrArraySlice = TCompilerIrArraySlice(expression)
		If arraySlice Then
			If EmbeddedArrayTypes() Then
				If Not PicoArrayElementSupported(arraySlice.elementType) Then
					AddDiagnostic("BMXC2028", "Array element type '" + arraySlice.elementType + "' is not available in the Pico managed-container profile", arraySlice.source)
					Return "&bmx_pico_empty_array"
				End If
				Local receiver:String = EmitExpression(arraySlice.receiver)
				Local lowerBound:String = EmitExpression(arraySlice.lowerBound)
				If arraySlice.lowerFromEnd Then lowerBound = "((" + receiver + ")->length - (" + lowerBound + "))"
				Local upperBound:String
				If arraySlice.upperBoundOmitted Then
					upperBound = "((" + receiver + ")->length)"
				Else
					upperBound = EmitExpression(arraySlice.upperBound)
					If arraySlice.upperFromEnd Then upperBound = "((" + receiver + ")->length - (" + upperBound + "))"
				End If
				Local initializer:String = "0"
				If arraySlice.structId.length Then
					initializer = StructArrayInitializerName(arraySlice.structId, "")
				Else If arraySlice.importedStructId.length Then
					Local importedElementStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arraySlice.importedStructId))
					If Not importedElementStruct Or Not importedElementStruct.elementInitializerAbiName.length Then
						AddDiagnostic("BMXC2091", "Imported array element Struct '" + arraySlice.elementType + "' has no supported Pico element initializer ABI", arraySlice.source)
						Return "&bmx_pico_empty_array"
					End If
					initializer = importedElementStruct.elementInitializerAbiName
				End If
				Local valueDescriptor:String = "0"
				If arraySlice.structId.length Then
					Local descriptorStruct:TCompilerIrStruct = StructById(arraySlice.structId)
					If descriptorStruct And descriptorStruct.containsManagedReferences Then valueDescriptor = "&" + PicoStructDescriptorName(descriptorStruct)
				Else If arraySlice.importedStructId.length Then
					Local importedDescriptorStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arraySlice.importedStructId))
					If importedDescriptorStruct And importedDescriptorStruct.containsManagedReferences Then valueDescriptor = "&" + PicoImportedStructDescriptorName(importedDescriptorStruct)
				End If
				Return "bmx_pico_array_slice(" + receiver + ", " + lowerBound + ", " + upperBound + ", (uint32_t)sizeof(" + CType(arraySlice.elementType, arraySlice.source) + "), " + PicoArrayElementKind(arraySlice.elementType) + ", " + initializer + ", " + valueDescriptor + ")"
			End If
			Local receiver:String = DebugManagedValue(EmitExpression(arraySlice.receiver), IR_MANAGED_REFERENCE_ARRAY, arraySlice.receiver.semanticType, arraySlice.source)
			Local lowerBound:String = EmitExpression(arraySlice.lowerBound)
			If arraySlice.lowerFromEnd Then lowerBound = "((" + receiver + ")->scales[0] - (" + lowerBound + "))"
			Local upperBound:String
			If arraySlice.upperBoundOmitted Then
				upperBound = "((" + receiver + ")->scales[0])"
			Else
				upperBound = EmitExpression(arraySlice.upperBound)
				If arraySlice.upperFromEnd Then upperBound = "((" + receiver + ")->scales[0] - (" + upperBound + "))"
			End If
			If arraySlice.structId.length Then
				Return "bbArraySliceStruct(" + CQuoted(arraySlice.elementEncoding) + ", " + receiver + ", " + lowerBound + ", " + upperBound + ", sizeof(struct " + StructName(arraySlice.structId) + "), " + StructArrayInitializerName(arraySlice.structId, "") + ")"
			End If
			If arraySlice.importedStructId.length Then
				Local sliceImportedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arraySlice.importedStructId))
				If sliceImportedStruct Then Return PublishedStructArraySliceName(sliceImportedStruct.abiName) + "(" + receiver + ", " + lowerBound + ", " + upperBound + ")"
			End If
			Return "bbArraySlice(" + CQuoted(arraySlice.elementEncoding) + ", " + receiver + ", " + lowerBound + ", " + upperBound + ")"
		End If
		Local arrayElement:TCompilerIrArrayElement = TCompilerIrArrayElement(expression)
		If arrayElement Then
			If EmbeddedArrayTypes() And Not arrayElement.isStaticArray Then
				If arrayElement.rank <> 1 Or arrayElement.indexes.length <> 1 Then
					AddDiagnostic("BMXC2028", "Only one-dimensional Array indexing is available in the initial Pico embedded profile", arrayElement.source)
					Return "0"
				End If
				If Not PicoArrayElementSupported(arrayElement.elementType) Or arrayElement.callableReturnType.length Then
					AddDiagnostic("BMXC2028", "Array element type '" + arrayElement.elementType + "' is not available in the Pico managed-container profile", arrayElement.source)
					Return "0"
				End If
				If arrayElement.structId.length And Not PicoPlainStructSupported(StructById(arrayElement.structId)) Then
					AddDiagnostic("BMXC2091", "Array element Struct '" + arrayElement.elementType + "' is not supported by the Pico value-descriptor tier", arrayElement.source)
					Return "0"
				End If
				If arrayElement.importedStructId.length And Not PicoPlainImportedStructSupported(TCompilerIrImportedStruct(importedStructsById.ValueForKey(arrayElement.importedStructId))) Then
					AddDiagnostic("BMXC2091", "Imported array element Struct '" + arrayElement.elementType + "' is not supported by the Pico value-descriptor tier", arrayElement.source)
					Return "0"
				End If
				Local picoElementType:String = CType(arrayElement.elementType, arrayElement.source)
				Return "(*((" + picoElementType + " *)bmx_pico_array_element(" + EmitExpression(arrayElement.receiver) + ", (int32_t)(" + EmitExpression(arrayElement.indexes[0]) + "), (uint32_t)sizeof(" + picoElementType + "))))"
			End If
			Local arrayElementType:String
			Local arrayElementPointerType:String
			Local arrayElementDataPointerType:String
			If arrayElement.callableReturnType.length Then
				arrayElementType = CCallablePointerType(arrayElement.callableReturnType, arrayElement.callableParameters, 1, arrayElement.source, arrayElement.callableCallingConvention)
				arrayElementPointerType = CCallablePointerType(arrayElement.callableReturnType, arrayElement.callableParameters, 2, arrayElement.source, arrayElement.callableCallingConvention)
				arrayElementDataPointerType = arrayElementPointerType
			Else
				arrayElementType = CType(arrayElement.elementType, arrayElement.source)
				arrayElementPointerType = arrayElementType + " *"
				arrayElementDataPointerType = arrayElementType + "*"
			End If
			If arrayElement.isStaticArray And arrayElement.indexes.length = 1 Then
				If runtimeTypes And arrayElement.boundsCheckKind = IR_BOUNDS_CHECK_STATIC_ARRAY Then
					Return "(*((" + arrayElementPointerType + ")bmx_debug_static_array_element((void *)" + EmitExpression(arrayElement.receiver) + ", (BBINT)" + EmitExpression(arrayElement.indexes[0]) + ", (BBUINT)" + arrayElement.boundsLength + ", sizeof(" + arrayElementType + "))))"
				End If
				Return EmitExpression(arrayElement.receiver) + "[" + EmitExpression(arrayElement.indexes[0]) + "]"
			End If
			If arrayElement.rank = 1 And arrayElement.indexes.length = 1 Then
				If runtimeTypes And arrayElement.boundsCheckKind = IR_BOUNDS_CHECK_DYNAMIC_ARRAY Then
					Return "(*((" + arrayElementPointerType + ")bmx_debug_array_element((BBARRAY)" + EmitExpression(arrayElement.receiver) + ", (BBINT)" + EmitExpression(arrayElement.indexes[0]) + ", sizeof(" + arrayElementType + "))))"
				End If
				Return "((" + arrayElementDataPointerType + ")BBARRAYDATA(" + EmitExpression(arrayElement.receiver) + ", 1))[" + EmitExpression(arrayElement.indexes[0]) + "]"
			End If
			If arrayElement.rank > 1 And arrayElement.indexes.length = arrayElement.rank Then
				Local receiver:String = EmitExpression(arrayElement.receiver)
				Local linearIndex:String
				For Local index:Int = 0 Until arrayElement.indexes.length
					If linearIndex.length Then linearIndex :+ " + "
					Local indexValue:String = EmitExpression(arrayElement.indexes[index])
					If index < arrayElement.indexes.length - 1 Then linearIndex :+ "((" + indexValue + ") * " + receiver + "->scales[" + (index + 1) + "])" Else linearIndex :+ "(" + indexValue + ")"
				Next
				If runtimeTypes And arrayElement.boundsCheckKind = IR_BOUNDS_CHECK_DYNAMIC_ARRAY Then
					Return "(*((" + arrayElementPointerType + ")bmx_debug_array_element(" + receiver + ", (BBINT)(" + linearIndex + "), sizeof(" + arrayElementType + "))))"
				End If
				Local dataExpression:String = "BBARRAYDATA(" + receiver + ", 1)"
				Return "((" + arrayElementDataPointerType + ")" + dataExpression + ")[" + linearIndex + "]"
			End If
			AddDiagnostic("BMXC2051", "Array element rank and index count do not match", arrayElement.source)
			Return "0"
		End If
		Local pointerElement:TCompilerIrPointerElement = TCompilerIrPointerElement(expression)
		If pointerElement Then
			Local elementType:String = CType(pointerElement.elementType, pointerElement.source)
			If runtimeTypes And pointerElement.nullCheck Then
				Return "(*((" + elementType + " *)bmx_debug_pointer_element((void *)" + EmitExpression(pointerElement.receiver) + ", (ptrdiff_t)" + EmitExpression(pointerElement.index) + ", sizeof(" + elementType + "))))"
			End If
			Return "(((" + elementType + " *)" + EmitExpression(pointerElement.receiver) + ")[" + EmitExpression(pointerElement.index) + "])"
		End If
		Local arrayConcat:TCompilerIrArrayConcat = TCompilerIrArrayConcat(expression)
		If arrayConcat Then
			If EmbeddedArrayTypes() Then
				Return "bmx_pico_array_concat(" + EmitExpression(arrayConcat.left) + ", " + EmitExpression(arrayConcat.right) + ")"
			End If
			Return "bbArrayConcat(" + CQuoted(arrayConcat.elementEncoding) + ", " + EmitExpression(arrayConcat.left) + ", " + EmitExpression(arrayConcat.right) + ")"
		End If
		Local arrayLiteral:TCompilerIrArrayLiteral = TCompilerIrArrayLiteral(expression)
		If arrayLiteral Then
			If EmbeddedArrayTypes() Then
				If Not arrayLiteral.elements.length Then Return "&bmx_pico_empty_array"
				If Not PicoArrayElementSupported(arrayLiteral.elementType) Or arrayLiteral.callableReturnType.length Then
					AddDiagnostic("BMXC2028", "Array literal element type '" + arrayLiteral.elementType + "' is not available in the Pico managed-container profile", arrayLiteral.source)
					Return "&bmx_pico_empty_array"
				End If
				Local initializer:String = "0"
				If arrayLiteral.structId.length Then
					Local elementStruct:TCompilerIrStruct = StructById(arrayLiteral.structId)
					If Not PicoPlainStructSupported(elementStruct) Then
						AddDiagnostic("BMXC2091", "Array literal element Struct '" + arrayLiteral.elementType + "' is not supported by the Pico value-descriptor tier", arrayLiteral.source)
						Return "&bmx_pico_empty_array"
					End If
					initializer = StructArrayInitializerName(arrayLiteral.structId, "")
				Else If arrayLiteral.importedStructId.length Then
					Local importedElementStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arrayLiteral.importedStructId))
					If Not PicoPlainImportedStructSupported(importedElementStruct) Or Not importedElementStruct.elementInitializerAbiName.length Then
						AddDiagnostic("BMXC2091", "Imported array literal element Struct '" + arrayLiteral.elementType + "' has no supported Pico element initializer ABI", arrayLiteral.source)
						Return "&bmx_pico_empty_array"
					End If
					initializer = importedElementStruct.elementInitializerAbiName
				End If
				Local valueDescriptor:String = "0"
				If arrayLiteral.structId.length Then
					Local descriptorStruct:TCompilerIrStruct = StructById(arrayLiteral.structId)
					If descriptorStruct And descriptorStruct.containsManagedReferences Then valueDescriptor = "&" + PicoStructDescriptorName(descriptorStruct)
				Else If arrayLiteral.importedStructId.length Then
					Local importedDescriptorStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsById.ValueForKey(arrayLiteral.importedStructId))
					If importedDescriptorStruct And importedDescriptorStruct.containsManagedReferences Then valueDescriptor = "&" + PicoImportedStructDescriptorName(importedDescriptorStruct)
				End If
				Local elementDataType:String = CType(arrayLiteral.elementType, arrayLiteral.source) + "[]"
				Local picoResult:TStringBuilder = New TStringBuilder(256)
				picoResult.Append("bmx_pico_array_from_data(" + arrayLiteral.elements.length + ", (uint32_t)sizeof(" + CType(arrayLiteral.elementType, arrayLiteral.source) + "), " + PicoArrayElementKind(arrayLiteral.elementType) + ", " + initializer + ", " + valueDescriptor + ", (" + elementDataType + "){")
				For Local picoIndex:Int = 0 Until arrayLiteral.elements.length
					If picoIndex Then picoResult.Append(", ")
					picoResult.Append(EmitExpression(arrayLiteral.elements[picoIndex]))
				Next
				picoResult.Append("})")
				Return picoResult.ToString()
			End If
			If Not arrayLiteral.elements.length Then Return "&bbEmptyArray"
			Local arrayFromDataName:String = "bbArrayFromData"
			If arrayLiteral.enumId.length Then arrayFromDataName = "bbArrayFromDataSize"
			If arrayLiteral.structId.length Or arrayLiteral.importedStructId.length Then arrayFromDataName = "bbArrayFromDataStruct"
			Local elementDataType:String
			If arrayLiteral.callableReturnType.length Then
				elementDataType = CCallableFieldDeclaration(arrayLiteral.callableReturnType, arrayLiteral.callableParameters, "[]", arrayLiteral.source, arrayLiteral.callableCallingConvention)
			Else
				elementDataType = CType(arrayLiteral.elementType, arrayLiteral.source) + "[]"
			End If
			Local result:TStringBuilder = New TStringBuilder(256)
			result.Append(arrayFromDataName + "(" + CQuoted(arrayLiteral.elementEncoding) + ", " + arrayLiteral.elements.length + ", (" + elementDataType + "){")
			For Local index:Int = 0 Until arrayLiteral.elements.length
				If index Then result.Append(", ")
				result.Append(EmitExpression(arrayLiteral.elements[index]))
			Next
			result.Append("}")
			If arrayLiteral.enumId.length Or arrayLiteral.structId.length Or arrayLiteral.importedStructId.length Then result.Append(", sizeof(" + CType(arrayLiteral.elementType, arrayLiteral.source) + ")")
			result.Append(")")
			Return result.ToString()
		End If
		Local objectNew:TCompilerIrObjectNew = TCompilerIrObjectNew(expression)
		If objectNew Then
			If objectNew.importedClassId.length Then Return EmitImportedObjectNew(objectNew)
			Local irClass:TCompilerIrClass = ClassById(objectNew.classId)
			If irClass Then
				If EmbeddedObjectTypes() Then
					If objectNew.dynamicClassSource Then
						AddDiagnostic("BMXC2029", "Dynamic Object allocation is not available in the initial Pico Object profile", objectNew.source)
						Return "((struct " + ObjectName(irClass.classId) + " *)&bmx_pico_null_object)"
					End If
					If objectNew.constructorFunctionId.length Then
						Local picoNewResult:String = ObjectNewHelperName(objectNew.constructorFunctionId) + "("
						For Local index:Int = 0 Until objectNew.arguments.length
							If index Then picoNewResult :+ ", "
							picoNewResult :+ EmitExpression(objectNew.arguments[index])
						Next
						Return picoNewResult + ")"
					End If
					Return PicoDefaultObjectNewName(irClass) + "()"
				End If
				Local classExpression:String = "(BBClass *)&" + DescriptorName(irClass.classId)
				If objectNew.dynamicClassSource Then classExpression = "((BBOBJECT)" + EmitExpression(objectNew.dynamicClassSource) + ")->clas"
				If objectNew.constructorFunctionId.length Then
					Local result:String = ObjectNewHelperName(objectNew.constructorFunctionId) + "(" + classExpression
					For Local argument:TCompilerIrExpression = EachIn objectNew.arguments
						result :+ ", " + EmitExpression(argument)
					Next
					Return result + ")"
				End If
				Local allocator:String = "bbObjectAtomicNew"
				If irClass.hasManagedFields Or objectNew.dynamicClassSource Then allocator = "bbObjectNew"
				Return "((struct " + ObjectName(irClass.classId) + " *)" + allocator + "(" + classExpression + "))"
			End If
			If objectNew.dynamicClassSource Then Return "((" + CType(objectNew.semanticType, objectNew.source) + ")bbObjectNew(((BBOBJECT)" + EmitExpression(objectNew.dynamicClassSource) + ")->clas))"
			AddDiagnostic("BMXC2052", "Object allocation class '" + objectNew.classId + "' has no emitted layout", objectNew.source)
			Return "&bbNullObject"
		End If
		Local fieldAccess:TCompilerIrFieldAccess = TCompilerIrFieldAccess(expression)
		If fieldAccess Then
			If fieldAccess.importedFieldId.length Then
				Local importedField:TCompilerIrImportedField = TCompilerIrImportedField(importedFieldsById.ValueForKey(fieldAccess.importedFieldId))
				If importedField Then
					If fieldAccess.importedStructId.length Then
						Local importedOperator:String = "."
						If fieldAccess.receiverIsPointer Then importedOperator = "->"
						Return "(" + EmitExpression(fieldAccess.receiver) + importedOperator + importedField.abiName + ")"
					End If
					Local importedReceiver:String = EmitExpression(fieldAccess.receiver)
					importedReceiver = DebugObjectReceiver(importedReceiver, fieldAccess.receiver.semanticType, fieldAccess.source)
					Return "(" + importedReceiver + "->" + importedField.abiName + ")"
				End If
				AddDiagnostic("BMXC2059", "Imported field '" + fieldAccess.importedFieldId + "' has no ABI record", fieldAccess.source)
				Return "0"
			End If
			If fieldAccess.structId.length Then
				Local structOperator:String = "."
				If fieldAccess.receiverIsPointer Then structOperator = "->"
				Return "(" + EmitExpression(fieldAccess.receiver) + structOperator + StructFieldName(fieldAccess.structId, fieldAccess.fieldId) + ")"
			End If
			Local receiver:String = EmitExpression(fieldAccess.receiver)
			receiver = DebugObjectReceiver(receiver, fieldAccess.receiver.semanticType, fieldAccess.source)
			Return "(" + receiver + "->" + FieldName(fieldAccess.classId, fieldAccess.fieldId) + ")"
		End If
		Local interfaceCast:TCompilerIrInterfaceCast = TCompilerIrInterfaceCast(expression)
		If interfaceCast Then
			If EmbeddedObjectTypes() Then
				Local picoInterface:TCompilerIrInterface = InterfaceById(interfaceCast.interfaceId)
				If PicoInterfaceDescriptorAvailable(picoInterface) Then Return "((BMXPicoObject *)bmx_pico_interface_cast((void *)" + EmitExpression(interfaceCast.operand) + ", &" + PicoInterfaceDescriptorName(picoInterface) + "))"
				AddDiagnostic("BMXC2029", "Interface cast target has no local Pico descriptor", interfaceCast.source)
				Return "((BMXPicoObject *)&bmx_pico_null_object)"
			End If
			Return "((BBOBJECT)bbInterfaceDowncast((BBOBJECT)" + EmitExpression(interfaceCast.operand) + ", (BBINTERFACE)&" + InterfaceDescriptorName(interfaceCast.interfaceId) + "))"
		End If
		Local objectCast:TCompilerIrObjectCast = TCompilerIrObjectCast(expression)
		If objectCast Then
			If EmbeddedObjectTypes() Then
				If objectCast.classId.length Then
					Local picoClass:TCompilerIrClass = ClassById(objectCast.classId)
					If picoClass Then Return "((struct " + ObjectName(picoClass.classId) + " *)bmx_pico_object_cast((void *)" + EmitExpression(objectCast.operand) + ", &" + PicoTypeDescriptorName(picoClass) + "))"
				End If
				If objectCast.importedClassId.length Then
					Local importedPicoClass:TCompilerIrImportedClass = ImportedClassById(objectCast.importedClassId)
					If importedPicoClass And importedPicoClass.abiName.length Then Return "((struct " + importedPicoClass.abiName + "_obj *)bmx_pico_object_cast((void *)" + EmitExpression(objectCast.operand) + ", &" + PicoImportedTypeDescriptorName(importedPicoClass) + "))"
				End If
				AddDiagnostic("BMXC2029", "Object cast target has no local Pico Type descriptor", objectCast.source)
				Return "((BMXPicoObject *)&bmx_pico_null_object)"
			End If
			If objectCast.classId.length Then
				Local irClass:TCompilerIrClass = ClassById(objectCast.classId)
				If irClass Then Return "((struct " + ObjectName(irClass.classId) + " *)bbObjectDowncast((BBOBJECT)" + EmitExpression(objectCast.operand) + ", (BBClass *)&" + DescriptorName(irClass.classId) + "))"
				AddDiagnostic("BMXC2056", "Object cast class '" + objectCast.classId + "' has no emitted layout", objectCast.source)
				Return "&bbNullObject"
			End If
			Local importedClass:TCompilerIrImportedClass = ImportedClassById(objectCast.importedClassId)
			If importedClass Then Return "((struct " + importedClass.abiName + "_obj *)bbObjectDowncast((BBOBJECT)" + EmitExpression(objectCast.operand) + ", (BBClass *)&" + importedClass.abiName + "))"
			AddDiagnostic("BMXC2056", "Imported object cast class '" + objectCast.importedClassId + "' has no ABI record", objectCast.source)
			Return "&bbNullObject"
		End If
		Local objectStringCast:TCompilerIrObjectStringCast = TCompilerIrObjectStringCast(expression)
		If objectStringCast Then
			If EmbeddedObjectTypes() Then
				AddDiagnostic("BMXC2029", "Object-to-String conversion is not available in the initial Pico Object profile", objectStringCast.source)
				Return "&bmx_pico_empty_string"
			End If
			Return "((BBSTRING)bbObjectStringcast((BBOBJECT)" + EmitExpression(objectStringCast.operand) + "))"
		End If
		AddDiagnostic("BMXC2011", "IR expression is not supported by the scalar C backend", expression.source)
		Return "0"
	End Method

	Method EmitTypeFunctionCall:String(call:TCompilerIrCall)
		Local slot:TCompilerIrClassFunctionSlot
		Local slotName:String
		Local irClass:TCompilerIrClass = ClassById(call.classId)
		If irClass Then
			slot = ClassSlot(irClass.classId, call.classSlotId)
			If slot Then slotName = ClassFunctionSlotName(slot)
		Else
			Local importedClass:TCompilerIrImportedClass = ImportedClassById(call.classId)
			If importedClass Then
				For Local candidate:TCompilerIrClassFunctionSlot = EachIn importedClass.functionSlots
					If candidate.slotId = call.classSlotId Then slot = candidate; Exit
				Next
			End If
			If slot Then slotName = slot.slotName
		End If
		If Not slot Or slot.isMethod Or Not slotName.length Then
			AddDiagnostic("BMXC2053", "Type Function call slot '" + call.classId + "." + call.classSlotId + "' was not emitted", call.source)
			Return "0"
		End If
		Local receiver:String = EmitExpression(call.receiver)
		receiver = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
		Local result:String = receiver + "->clas->" + slotName + "("
		For Local index:Int = 0 Until call.arguments.length
			If index Then result :+ ", "
			result :+ EmitExpression(call.arguments[index])
		Next
		Return result + ")"
	End Method

	Method EmitImportedObjectNew:String(objectNew:TCompilerIrObjectNew)
		Local importedClass:TCompilerIrImportedClass = ImportedClassById(objectNew.importedClassId)
		Local constructor:TCompilerIrImportedConstructor = ImportedConstructorById(objectNew.importedConstructorId)
		If Not importedClass Or Not constructor Then
			AddDiagnostic("BMXC2058", "Imported object construction has no class or constructor ABI record", objectNew.source)
			Return "&bbNullObject"
		End If
		If EmbeddedObjectTypes() Then
			If objectNew.dynamicClassSource Then
				AddDiagnostic("BMXC2029", "Dynamic imported Object allocation is not available in the current Pico module ABI", objectNew.source)
				Return "((struct " + importedClass.abiName + "_obj *)&bmx_pico_null_object)"
			End If
			If Not constructor.objectNewAbiName.length Then
				AddDiagnostic("BMXC2029", "Imported constructor has no Pico allocation-helper ABI", objectNew.source)
				Return "((struct " + importedClass.abiName + "_obj *)&bmx_pico_null_object)"
			End If
			Local picoResult:String = "((struct " + importedClass.abiName + "_obj *)" + constructor.objectNewAbiName + "("
			For Local index:Int = 0 Until objectNew.arguments.length
				If index Then picoResult :+ ", "
				picoResult :+ EmitExpression(objectNew.arguments[index])
			Next
			Return picoResult + "))"
		End If
		If Not runtimeTypes Then
			AddDiagnostic("BMXC2029", "Imported Object allocation requires the BlitzMax runtime C backend", objectNew.source)
			Return "0"
		End If
		Local classExpression:String = "(BBClass *)&" + importedClass.abiName
		If objectNew.dynamicClassSource Then classExpression = "((BBOBJECT)" + EmitExpression(objectNew.dynamicClassSource) + ")->clas"
		If constructor.objectNewAbiName.length Then
			Local result:String = "((struct " + importedClass.abiName + "_obj *)" + constructor.objectNewAbiName + "(" + classExpression
			For Local argument:TCompilerIrExpression = EachIn objectNew.arguments
				result :+ ", " + EmitExpression(argument)
			Next
			Return result + "))"
		End If
		Local allocator:String = "bbObjectAtomicNew"
		If importedClass.hasManagedFields Or objectNew.dynamicClassSource Then allocator = "bbObjectNew"
		Return "((struct " + importedClass.abiName + "_obj *)" + allocator + "(" + classExpression + "))"
	End Method

	Method EmitInterfaceCall:String(call:TCompilerIrCall)
		Local irInterface:TCompilerIrInterface = InterfaceById(call.interfaceId)
		Local interfaceMethod:TCompilerIrInterfaceMethod
		Local interfaceMethodIndex:Int = -1
		If irInterface Then
			For Local candidateIndex:Int = 0 Until irInterface.methods.length
				Local candidate:TCompilerIrInterfaceMethod = irInterface.methods[candidateIndex]
				If candidate.slotId = call.interfaceSlotId Then interfaceMethod = candidate; interfaceMethodIndex = candidateIndex; Exit
			Next
		End If
		If Not irInterface Or Not interfaceMethod Then
			AddDiagnostic("BMXC2055", "Interface call slot '" + call.interfaceId + "." + call.interfaceSlotId + "' was not emitted", call.source)
			Return "0"
		End If
		Local receiver:String = EmitExpression(call.receiver)
		If EmbeddedObjectTypes() Then
			If Not PicoInterfaceDescriptorAvailable(irInterface) Then
				AddDiagnostic("BMXC2029", "Imported or native Interface dispatch is not available in the current Pico descriptor tier", call.source)
				Return "0"
			End If
			Local pointerType:String = PicoInterfaceFunctionPointerType(interfaceMethod)
			If Not pointerType.length Or interfaceMethodIndex < 0 Then
				AddDiagnostic("BMXC2029", "Interface method signature is not available in the current Pico dispatch tier", call.source)
				Return "0"
			End If
			receiver = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
			Local picoResult:String = "((" + pointerType + ")bmx_pico_interface_methods((void *)" + receiver + ", &" + PicoInterfaceDescriptorName(irInterface) + ", " + irInterface.methods.length + ")[" + interfaceMethodIndex + "])((BMXPicoObject *)" + receiver
			For Local argument:TCompilerIrExpression = EachIn call.arguments
				picoResult :+ ", " + EmitExpression(argument)
			Next
			Return picoResult + ")"
		End If
		If irInterface.isExternInterface Then
			Local nativeResult:String = "(" + receiver + ")->vtbl->" + InterfaceMethodName(interfaceMethod) + "((" + NativeInterfaceReceiverType(InterfaceById(interfaceMethod.declaringInterfaceId)) + ")" + receiver
			For Local argument:TCompilerIrExpression = EachIn call.arguments
				nativeResult :+ ", " + EmitExpression(argument)
			Next
			Return nativeResult + ")"
		End If
		receiver = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
		Local result:String = "((struct " + InterfaceMethodsName(irInterface.interfaceId) + " *)bbObjectInterface((BBOBJECT)" + receiver + ", (BBINTERFACE)&" + InterfaceDescriptorName(irInterface.interfaceId) + "))->" + InterfaceMethodName(interfaceMethod) + "((" + InterfaceReceiverType(irInterface) + ")" + receiver
		For Local argument:TCompilerIrExpression = EachIn call.arguments
			result :+ ", " + EmitExpression(argument)
		Next
		Return result + ")"
	End Method

	Method EmitImportedVirtualCall:String(call:TCompilerIrCall)
		Local receiverClass:TCompilerIrImportedClass = ImportedClassById(call.classId)
		If EmbeddedObjectTypes() And receiverClass And call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
			Local picoReceiver:String = EmitExpression(call.receiver)
			picoReceiver = DebugObjectReceiver(picoReceiver, call.receiver.semanticType, call.source)
			Select call.objectSlotKind
				Case IR_OBJECT_SLOT_COMPARE
					Return "bmx_pico_object_compare((void *)" + picoReceiver + ", (void *)" + EmitExpression(call.arguments[0]) + ")"
				Case IR_OBJECT_SLOT_HASH_CODE
					Return "bmx_pico_object_hash_code((void *)" + picoReceiver + ")"
				Case IR_OBJECT_SLOT_EQUALS
					Return "bmx_pico_object_equals((void *)" + picoReceiver + ", (void *)" + EmitExpression(call.arguments[0]) + ")"
				Case IR_OBJECT_SLOT_TO_STRING
					AddDiagnostic("BMXC2029", "Object ToString requires dynamic Pico String support", call.source)
				Case IR_OBJECT_SLOT_SEND_MESSAGE
					AddDiagnostic("BMXC2029", "Object SendMessage is not available in the current Pico Object profile", call.source)
			End Select
			Return CDefaultValue(call.semanticType)
		End If
		If EmbeddedObjectTypes() And receiverClass Then
			Local dispatchIndex:Int = PicoImportedClassSlotIndex(receiverClass, call.classSlotId)
			Local dispatchSlot:TCompilerIrClassFunctionSlot
			If dispatchIndex >= 0 Then dispatchSlot = receiverClass.functionSlots[dispatchIndex]
			Local pointerType:String = PicoSlotFunctionPointerType(dispatchSlot)
			If dispatchIndex < 0 Or Not pointerType.length Or Not receiverClass.abiName.length Then
				AddDiagnostic("BMXC2029", "Imported virtual dispatch slot is not available in the current Pico Type descriptor ABI", call.source)
				Return "0"
			End If
			Local receiver:String = EmitExpression(call.receiver)
			receiver = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
			Local declaringClass:TCompilerIrImportedClass = ImportedClassById(dispatchSlot.receiverImportedClassId)
			If Not declaringClass Then declaringClass = ImportedClassById(dispatchSlot.declaringImportedClassId)
			If Not declaringClass Then declaringClass = receiverClass
			Local result:String = "((" + pointerType + ")bmx_pico_type_methods((void *)" + receiver + ", &" + PicoImportedTypeDescriptorName(receiverClass) + ", " + receiverClass.functionSlots.length + ")[" + dispatchIndex + "])((struct " + declaringClass.abiName + "_obj *)" + receiver
			For Local argument:TCompilerIrExpression = EachIn call.arguments
				result :+ ", " + EmitExpression(argument)
			Next
			Return result + ")"
		End If
		If receiverClass And call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
			Local receiver:String = EmitExpression(call.receiver)
			receiver = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
			Local result:String = receiver + "->clas->" + ObjectSlotName(call.objectSlotKind) + "((BBOBJECT)" + receiver
			For Local argument:TCompilerIrExpression = EachIn call.arguments
				result :+ ", (BBOBJECT)" + EmitExpression(argument)
			Next
			Return result + ")"
		End If
		Local importedMethod:TCompilerIrImportedMethod = ImportedMethodById(call.classSlotId)
		Local declaringClass:TCompilerIrImportedClass
		If importedMethod Then declaringClass = ImportedClassById(importedMethod.declaringImportedClassId)
		If Not receiverClass Or Not importedMethod Or Not declaringClass Then
			AddDiagnostic("BMXC2057", "Imported virtual call slot '" + call.classId + "." + call.classSlotId + "' has no ABI record", call.source)
			Return "0"
		End If
		Local receiver:String = EmitExpression(call.receiver)
		receiver = DebugObjectReceiver(receiver, call.receiver.semanticType, call.source)
		Local result:String = receiver + "->clas->" + importedMethod.slotName + "((struct " + declaringClass.abiName + "_obj *)" + receiver
		For Local argument:TCompilerIrExpression = EachIn call.arguments
			result :+ ", " + EmitExpression(argument)
		Next
		Return result + ")"
	End Method

	Method EmitSuperCall:String(call:TCompilerIrCall)
		Local importedDispatchClass:TCompilerIrImportedClass = ImportedClassById(call.classId)
		If importedDispatchClass Then
			Local importedMethod:TCompilerIrImportedMethod = ImportedMethodById(call.classSlotId)
			Local declaringClass:TCompilerIrImportedClass
			If importedMethod Then declaringClass = ImportedClassById(importedMethod.declaringImportedClassId)
			If Not importedMethod Or Not declaringClass Or Not importedMethod.implementationAbiName.length Then
				AddDiagnostic("BMXC2054", "Imported Super call slot '" + call.classId + "." + call.classSlotId + "' has no direct implementation ABI", call.source)
				Return "0"
			End If
			Local receiver:String = EmitExpression(call.receiver)
			Local result:String = importedMethod.implementationAbiName + "((struct " + declaringClass.abiName + "_obj *)" + receiver
			For Local argument:TCompilerIrExpression = EachIn call.arguments
				result :+ ", " + EmitExpression(argument)
			Next
			Return result + ")"
		End If
		Local dispatchClass:TCompilerIrClass = ClassById(call.classId)
		Local baseClass:TCompilerIrClass
		If dispatchClass Then baseClass = ClassById(dispatchClass.baseClassId)
		If Not dispatchClass Or Not baseClass Then
			AddDiagnostic("BMXC2054", "Super call dispatch class '" + call.classId + "' has no emitted base descriptor", call.source)
			Return "0"
		End If
		Local receiver:String = EmitExpression(call.receiver)
		Local result:String
		If EmbeddedObjectTypes() And call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
			AddDiagnostic("BMXC2029", "Super dispatch for built-in Object slots is not available in the current Pico inheritance tier", call.source)
			Return CDefaultValue(call.semanticType)
		End If
		If call.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
			result = DescriptorName(dispatchClass.classId) + ".super->" + ObjectSlotName(call.objectSlotKind) + "((BBOBJECT)" + receiver
			If call.arguments.length Then result :+ ", "
			For Local index:Int = 0 Until call.arguments.length
				If index Then result :+ ", "
				result :+ "(BBOBJECT)" + EmitExpression(call.arguments[index])
			Next
			Return result + ")"
		End If
		Local slot:TCompilerIrClassFunctionSlot = ClassSlot(baseClass.classId, call.classSlotId)
		If Not slot Then
			AddDiagnostic("BMXC2054", "Super call slot '" + baseClass.classId + "." + call.classSlotId + "' was not emitted", call.source)
			Return "0"
		End If
		If EmbeddedObjectTypes() Then
			Local picoReceiver:String = receiver
			Local picoReceiverClass:TCompilerIrClass = ClassById(slot.receiverClassId)
			If Not picoReceiverClass Then picoReceiverClass = ClassById(slot.declaringClassId)
			If picoReceiverClass Then picoReceiver = "(struct " + ObjectName(picoReceiverClass.classId) + " *)" + receiver
			Local picoResult:String = FunctionName(slot.functionId) + "(" + picoReceiver
			For Local argument:TCompilerIrExpression = EachIn call.arguments
				picoResult :+ ", " + EmitExpression(argument)
			Next
			Return picoResult + ")"
		End If
		Local receiverArgument:String = receiver
		If slot.receiverClassId.length Then receiverArgument = "(struct " + ObjectName(slot.receiverClassId) + " *)" + receiver
		If slot.receiverImportedClassId.length Then
			Local importedReceiver:TCompilerIrImportedClass = ImportedClassById(slot.receiverImportedClassId)
			If importedReceiver Then receiverArgument = "(struct " + importedReceiver.abiName + "_obj *)" + receiver
		End If
		result = "((struct " + ClassName(baseClass.classId) + " *)" + DescriptorName(dispatchClass.classId) + ".super)->" + ClassFunctionSlotName(slot) + "(" + receiverArgument
		If call.arguments.length Then result :+ ", "
		For Local index:Int = 0 Until call.arguments.length
			If index Then result :+ ", "
			result :+ EmitExpression(call.arguments[index])
		Next
		Return result + ")"
	End Method

	Method CatchCondition:String(guardedCatch:TCompilerIrCatch, exceptionName:String)
		If EmbeddedObjectTypes() Then
			Select guardedCatch.catchKind
				Case IR_CATCH_OBJECT
					Return exceptionName + ".kind == BMX_PICO_EXCEPTION_OBJECT"
				Case IR_CATCH_STRING
					Return exceptionName + ".kind == BMX_PICO_EXCEPTION_STRING"
				Case IR_CATCH_ARRAY
					Return exceptionName + ".kind == BMX_PICO_EXCEPTION_ARRAY"
				Case IR_CATCH_INTERFACE
					If guardedCatch.interfaceId.length Then
						Local picoInterface:TCompilerIrInterface = InterfaceById(guardedCatch.interfaceId)
						If PicoInterfaceDescriptorAvailable(picoInterface) Then Return exceptionName + ".kind == BMX_PICO_EXCEPTION_OBJECT && bmx_pico_interface_cast(" + exceptionName + ".value, &" + PicoInterfaceDescriptorName(picoInterface) + ") != &bmx_pico_null_object"
					End If
				Case IR_CATCH_CLASS
					If guardedCatch.classId.length Then
						Local picoClass:TCompilerIrClass = ClassById(guardedCatch.classId)
						If picoClass Then Return exceptionName + ".kind == BMX_PICO_EXCEPTION_OBJECT && bmx_pico_object_cast(" + exceptionName + ".value, &" + PicoTypeDescriptorName(picoClass) + ") != &bmx_pico_null_object"
					End If
					If guardedCatch.importedClassId.length Then
						Local importedPicoClass:TCompilerIrImportedClass = ImportedClassById(guardedCatch.importedClassId)
						If importedPicoClass And importedPicoClass.abiName.length Then Return exceptionName + ".kind == BMX_PICO_EXCEPTION_OBJECT && bmx_pico_object_cast(" + exceptionName + ".value, &" + PicoImportedTypeDescriptorName(importedPicoClass) + ") != &bmx_pico_null_object"
					End If
			End Select
			AddDiagnostic("BMXC2101", "Pico Catch supports Object, String, Array, and class/interface types with a compact descriptor ABI; '" + guardedCatch.parameterType + "' is not supported", guardedCatch.source)
			Return "0"
		End If
		Select guardedCatch.catchKind
			Case IR_CATCH_OBJECT
				Return "1"
			Case IR_CATCH_STRING
				Return "bbObjectStringcast((BBOBJECT)" + exceptionName + ") != (BBOBJECT)&bbEmptyString"
			Case IR_CATCH_ARRAY
				Return "bbObjectArraycast((BBOBJECT)" + exceptionName + ") != &bbEmptyArray"
			Case IR_CATCH_INTERFACE
				Return "bbInterfaceDowncast((BBObject *)" + exceptionName + ", (BBInterface *)&" + InterfaceDescriptorName(guardedCatch.interfaceId) + ") != &bbNullObject"
			Case IR_CATCH_CLASS
				Local descriptor:String
				If guardedCatch.classId.length Then descriptor = DescriptorName(guardedCatch.classId)
				If guardedCatch.importedClassId.length Then
					Local importedClass:TCompilerIrImportedClass = ImportedClassById(guardedCatch.importedClassId)
					If importedClass Then descriptor = importedClass.abiName
				End If
				If descriptor.length Then Return "bbObjectDowncast((BBOBJECT)" + exceptionName + ", (BBClass *)&" + descriptor + ") != &bbNullObject"
		End Select
		AddDiagnostic("BMXC2082", "Catch type '" + guardedCatch.parameterType + "' has no runtime matcher", guardedCatch.source)
		Return "0"
	End Method

	Method EmitAssignment:String(assignment:TCompilerIrAssignment, indent:String)
		Local result:String
		Local target:TCompilerIrExpression = assignment.target
		Local materialization:TCompilerIrMaterialize = TCompilerIrMaterialize(target)
		While materialization
			RegisterTemporary(materialization)
			result :+ indent + TemporaryName(materialization.temporaryId) + " = " + EmitExpression(materialization.value) + ";~n"
			preparedTemporaryValues.Insert(materialization.temporaryId, materialization)
			target = materialization.expression
			materialization = TCompilerIrMaterialize(target)
		Wend
		Local valueExpression:TCompilerIrExpression = assignment.value
		materialization = TCompilerIrMaterialize(valueExpression)
		While materialization
			RegisterTemporary(materialization)
			result :+ indent + TemporaryName(materialization.temporaryId) + " = " + EmitExpression(materialization.value) + ";~n"
			preparedTemporaryValues.Insert(materialization.temporaryId, materialization)
			valueExpression = materialization.expression
			materialization = TCompilerIrMaterialize(valueExpression)
		Wend
		Local value:String = EmitExpression(valueExpression)
		Local targetSymbol:TCompilerIrSymbolReference = TCompilerIrSymbolReference(target)
		If assignment.operatorText = "=" And targetSymbol And targetSymbol.isExternal Then
			Local externalGlobal:TCompilerIrExternalGlobal = TCompilerIrExternalGlobal(externalGlobalsById.ValueForKey(targetSymbol.symbolId))
			If externalGlobal And externalGlobal.nativeCallableCast.length Then value = "(" + externalGlobal.nativeCallableCast + ")" + value
		End If
		Local emittedTarget:String = EmitExpression(target)
		If assignment.operatorText.ToLower() = ":mod" And IsFloatingSemanticType(target.semanticType) Then
			Return result + indent + emittedTarget + " = (" + CType(target.semanticType, assignment.source) + ")bbFloatMod((BBDOUBLE)(" + emittedTarget + "), (BBDOUBLE)(" + value + "));~n"
		End If
		Return result + indent + emittedTarget + " " + CAssignmentOperator(assignment.operatorText, assignment.source) + " " + value + ";~n"
	End Method

	Function IsFloatingSemanticType:Int(typeName:String)
		Local normalized:String = typeName.Trim().ToLower()
		Return normalized = "float" Or normalized = "double" Or normalized = "float64"
	End Function

	Function IsPointerSemanticType:Int(typeName:String)
		Return typeName.Trim().ToLower().EndsWith(" ptr")
	End Function

	Method CAssignmentOperator:String(operatorText:String, source:TCompilerSourceLocation)
		Select operatorText.ToLower()
			Case "=" Return "="
			Case ":+" Return "+="
			Case ":-" Return "-="
			Case ":*" Return "*="
			Case ":/" Return "/="
			Case ":&" Return "&="
			Case ":|" Return "|="
			Case ":~~" Return "^="
			Case ":shl" Return "<<="
			Case ":shr", ":sar" Return ">>="
			Case ":mod" Return "%="
		End Select
		AddDiagnostic("BMXC2024", "Assignment operator '" + operatorText + "' has no scalar C99 lowering", source)
		Return "="
	End Method

	Method ResetTemporaries()
		temporaryTypes = New TMap
		temporaryAddressValues = New TMap
		temporarySources = New TMap
		temporaryCallableReturns = New TMap
		temporaryCallableParameters = New TMap
		temporaryCallableConventions = New TMap
		temporaryNativeCallableAbiNames = New TMap
		temporaryOrder = New String[0]
		preparedTemporaryValues = New TMap
	End Method

	Method RegisterTemporary(materialization:TCompilerIrMaterialize)
		If Not materialization Or temporaryTypes.Contains(materialization.temporaryId) Then Return
		temporaryTypes.Insert(materialization.temporaryId, materialization.temporaryType)
		If materialization.temporaryIsAddress Then temporaryAddressValues.Insert(materialization.temporaryId, materialization)
		temporarySources.Insert(materialization.temporaryId, materialization.source)
		If materialization.temporaryCallableReturnType.length Then
			temporaryCallableReturns.Insert(materialization.temporaryId, materialization.temporaryCallableReturnType)
			temporaryCallableParameters.Insert(materialization.temporaryId, materialization.temporaryCallableParameters)
			temporaryCallableConventions.Insert(materialization.temporaryId, materialization.temporaryCallableCallingConvention)
		End If
		If materialization.temporaryNativeCallableAbiName.length Then temporaryNativeCallableAbiNames.Insert(materialization.temporaryId, materialization.temporaryNativeCallableAbiName)
		localNames.Insert(materialization.temporaryId, TemporaryName(materialization.temporaryId))
		temporaryOrder :+ [materialization.temporaryId]
	End Method

	Method EmitTemporaryDeclarations:String(indent:String)
		Local result:String
		For Local temporaryId:String = EachIn temporaryOrder
			Local semanticType:String = String(temporaryTypes.ValueForKey(temporaryId))
			Local source:TCompilerSourceLocation = TCompilerSourceLocation(temporarySources.ValueForKey(temporaryId))
			Local callableReturnType:String = String(temporaryCallableReturns.ValueForKey(temporaryId))
			Local nativeCallableAbiName:String = String(temporaryNativeCallableAbiNames.ValueForKey(temporaryId))
			If nativeCallableAbiName.length Then
				result :+ indent + "__typeof__(" + nativeCallableAbiName + ") " + TemporaryName(temporaryId) + ";~n"
			Else If callableReturnType.length Then
				Local callableParameters:TCompilerIrParameter[] = TCompilerIrParameter[](temporaryCallableParameters.ValueForKey(temporaryId))
				Local callingConvention:String = String(temporaryCallableConventions.ValueForKey(temporaryId))
				result :+ indent + CCallableFieldDeclaration(callableReturnType, callableParameters, TemporaryName(temporaryId), source, callingConvention) + ";~n"
			Else
				Local pointerSuffix:String
				If temporaryAddressValues.Contains(temporaryId) Then pointerSuffix = " *"
				result :+ indent + CType(semanticType, source) + pointerSuffix + " " + TemporaryName(temporaryId)
				If EmbeddedObjectTypes() And Not pointerSuffix.length And PicoGcRootStorageType(semanticType) Then result :+ " = " + CDefaultValue(semanticType)
				result :+ ";~n"
			End If
		Next
		Return result
	End Method

	Method TemporaryName:String(temporaryId:String)
		Return "bmx_tmp_" + SafeIdentifier(temporaryId)
	End Method

	Method ObjectSlotName:String(slotKind:Int)
		Select slotKind
			Case IR_OBJECT_SLOT_TO_STRING; Return "ToString"
			Case IR_OBJECT_SLOT_COMPARE; Return "Compare"
			Case IR_OBJECT_SLOT_SEND_MESSAGE; Return "SendMessage"
			Case IR_OBJECT_SLOT_HASH_CODE; Return "HashCode"
			Case IR_OBJECT_SLOT_EQUALS; Return "Equals"
		End Select
		Return ""
	End Method

	Method ClassSlot:TCompilerIrClassFunctionSlot(classId:String, slotId:String)
		Local irClass:TCompilerIrClass = ClassById(classId)
		If Not irClass Then Return Null
		For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
			If slot.slotId = slotId Then Return slot
		Next
		Return Null
	End Method

	Method EmitConversion:String(conversion:TCompilerIrConversion)
		Local operand:String = EmitExpression(conversion.operand)
		If conversion.conversionKind = CONVERSION_POINTER_TO_VAR_REFERENCE Then Return "(*(" + operand + "))"
		If conversion.arrayCastElementEncoding.length Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2028", "Explicit managed Array conversion requires the BlitzMax runtime C backend", conversion.source)
				Return "0"
			End If
			Return "bbArrayCastFromObject((BBOBJECT)" + operand + ", " + CQuoted(conversion.arrayCastElementEncoding) + ")"
		End If
		If conversion.conversionKind = CONVERSION_STRING_TO_BYTE_POINTER Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2083", "Implicit String-to-Byte Ptr conversion requires the BlitzMax runtime C backend", conversion.source)
				Return "0"
			End If
			If Not nativeStringScope Then
				AddDiagnostic("BMXC2083", "Implicit String-to-Byte Ptr conversion escaped its statement cleanup scope", conversion.source)
				Return "0"
			End If
			Local name:String = "bmx_native_string_" + nextNativeStringId
			nextNativeStringId :+ 1
			Return nativeStringScope.Add(name, operand)
		End If
		If conversion.conversionKind = CONVERSION_OBJECT_TO_BYTE_POINTER Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2029", "Managed Type field-storage conversion requires the BlitzMax runtime C backend", conversion.source)
				Return "0"
			End If
			Return "((BBBYTE *)bbObjectToFieldOffset((BBObject *)" + operand + "))"
		End If
		If conversion.conversionKind = CONVERSION_ARRAY_TO_POINTER And conversion.arrayToPointerUsesHeapStorage Then
			If EmbeddedArrayTypes() Then
				Return "((" + CType(conversion.semanticType, conversion.source) + ")bmx_pico_array_data(" + operand + "))"
			End If
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2028", "Managed Array storage conversion requires the BlitzMax runtime C backend", conversion.source)
				Return "0"
			End If
			Return "((" + CType(conversion.semanticType, conversion.source) + ")BBARRAYDATA(" + operand + ", 1))"
		End If
		If conversion.callableReturnType.length Then
			Return "((" + CCallablePointerType(conversion.callableReturnType, conversion.callableParameters, 1, conversion.source, conversion.callableCallingConvention) + ")(" + operand + "))"
		End If
		If conversion.checkedEnumId.length And currentModule And currentModule.buildMode.ToLower() = "debug" Then
			If Not runtimeTypes Then
				AddDiagnostic("BMXC2077", "Checked Enum conversion requires the BlitzMax runtime C backend", conversion.source)
				Return "0"
			End If
			Local checkedEnum:TCompilerIrEnum = EnumById(conversion.checkedEnumId)
			If Not checkedEnum Or Not checkedEnum.runtimeDescriptor Then
				AddDiagnostic("BMXC2077", "Checked Enum conversion has no retained runtime descriptor", conversion.source)
				Return "0"
			End If
			Return "bbEnumCast_" + checkedEnum.runtimeDescriptor.numericTypeTag + "(" + checkedEnum.runtimeDescriptor.descriptorAbiName + ", " + operand + ")"
		End If
		If conversion.conversionKind = CONVERSION_NUMERIC_TO_STRING Then
			If EmbeddedStringTypes() Then
				Select conversion.operand.semanticType.ToLower()
					Case "byte", "short", "int" Return "bmx_pico_string_from_int32(" + operand + ")"
					Case "uint" Return "bmx_pico_string_from_uint32(" + operand + ")"
					Case "long" Return "bmx_pico_string_from_int64(" + operand + ")"
					Case "ulong" Return "bmx_pico_string_from_uint64(" + operand + ")"
					Case "size_t" Return "bmx_pico_string_from_size(" + operand + ")"
					Case "longint" Return "bmx_pico_string_from_long(" + operand + ")"
					Case "ulongint" Return "bmx_pico_string_from_ulong(" + operand + ")"
					Case "wparam" Return "bmx_pico_string_from_ulong(" + operand + ")"
					Case "lparam" Return "bmx_pico_string_from_long(" + operand + ")"
					Case "float" Return "bmx_pico_string_from_float_default(" + operand + ")"
					Case "double", "float64" Return "bmx_pico_string_from_double_default(" + operand + ")"
				End Select
			Else If Not runtimeTypes Then
				AddDiagnostic("BMXC2025", "Numeric-to-String conversion requires the BlitzMax runtime C backend", conversion.source)
				Return "0"
			End If
			Select conversion.operand.semanticType.ToLower()
				Case "byte", "short", "int" Return "bbStringFromInt(" + operand + ")"
				Case "uint" Return "bbStringFromUInt(" + operand + ")"
				Case "long" Return "bbStringFromLong(" + operand + ")"
				Case "ulong" Return "bbStringFromULong(" + operand + ")"
				Case "size_t" Return "bbStringFromSizet(" + operand + ")"
				Case "longint" Return "bbStringFromLongInt(" + operand + ")"
				Case "ulongint" Return "bbStringFromULongInt(" + operand + ")"
				Case "wparam" Return "bbStringFromWParam(" + operand + ")"
				Case "lparam" Return "bbStringFromLParam(" + operand + ")"
				Case "float" Return "bbStringFromFloat(" + operand + ", 0)"
				Case "double", "float64" Return "bbStringFromDouble(" + operand + ", 0)"
			End Select
			AddDiagnostic("BMXC2026", "Numeric type '" + conversion.operand.semanticType + "' has no String conversion runtime mapping", conversion.source)
			Return "&bbEmptyString"
		End If
		If conversion.conversionKind = CONVERSION_STRING_TO_NUMERIC Then
			If EmbeddedStringTypes() Then
				Select conversion.semanticType.ToLower()
					Case "byte" Return "((uint8_t)bmx_pico_string_to_int32(" + operand + "))"
					Case "short" Return "((uint16_t)bmx_pico_string_to_int32(" + operand + "))"
					Case "int" Return "bmx_pico_string_to_int32(" + operand + ")"
					Case "uint" Return "bmx_pico_string_to_uint32(" + operand + ")"
					Case "long" Return "bmx_pico_string_to_int64(" + operand + ")"
					Case "ulong" Return "bmx_pico_string_to_uint64(" + operand + ")"
					Case "size_t" Return "bmx_pico_string_to_size(" + operand + ")"
					Case "longint" Return "bmx_pico_string_to_long(" + operand + ")"
					Case "ulongint" Return "bmx_pico_string_to_ulong(" + operand + ")"
					Case "wparam" Return "bmx_pico_string_to_ulong(" + operand + ")"
					Case "lparam" Return "bmx_pico_string_to_long(" + operand + ")"
					Case "float" Return "bmx_pico_string_to_float(" + operand + ")"
					Case "double", "float64" Return "bmx_pico_string_to_double(" + operand + ")"
				End Select
			Else If Not runtimeTypes Then
				AddDiagnostic("BMXC2025", "String-to-numeric conversion requires the BlitzMax runtime C backend", conversion.source)
				Return "0"
			End If
			Select conversion.semanticType.ToLower()
				Case "byte" Return "((BBBYTE)bbStringToInt(" + operand + "))"
				Case "short" Return "((BBSHORT)bbStringToInt(" + operand + "))"
				Case "int" Return "bbStringToInt(" + operand + ")"
				Case "uint" Return "bbStringToUInt(" + operand + ")"
				Case "long" Return "bbStringToLong(" + operand + ")"
				Case "ulong" Return "bbStringToULong(" + operand + ")"
				Case "size_t" Return "bbStringToSizet(" + operand + ")"
				Case "longint" Return "bbStringToLongInt(" + operand + ")"
				Case "ulongint" Return "bbStringToULongInt(" + operand + ")"
				Case "wparam" Return "bbStringToWParam(" + operand + ")"
				Case "lparam" Return "bbStringToLParam(" + operand + ")"
				Case "float" Return "bbStringToFloat(" + operand + ")"
				Case "double", "float64" Return "bbStringToDouble(" + operand + ")"
			End Select
			AddDiagnostic("BMXC2027", "String conversion target '" + conversion.semanticType + "' has no numeric runtime mapping", conversion.source)
			Return "0"
		End If
		If conversion.operand And Not conversion.implicitConversion And IsManagedCReferenceType(conversion.operand.semanticType) And IsManagedCReferenceType(conversion.semanticType) Then
			Local sourceType:String = conversion.operand.semanticType.Trim().ToLower()
			Local targetType:String = conversion.semanticType.Trim().ToLower()
			If targetType <> "object" And sourceType <> targetType Then
				AddDiagnostic("BMXC2090", "Managed narrowing conversion from '" + conversion.operand.semanticType + "' to '" + conversion.semanticType + "' reached the raw C cast fallback", conversion.source)
				Return CDefaultValue(conversion.semanticType)
			End If
		End If
		Return "((" + CType(conversion.semanticType, conversion.source) + ")(" + operand + "))"
	End Method

	Method SymbolName:String(symbolId:String, sourceName:String)
		Local localName:String = String(localNames.ValueForKey(symbolId))
		If localName.length Then Return localName
		Local globalName:String = String(globalNames.ValueForKey(symbolId))
		If globalName.length Then Return globalName
		AddDiagnostic("BMXC2012", "IR symbol '" + sourceName + "' has no C storage", Null)
		Return "bmx_missing_" + SafeIdentifier(symbolId + "_" + sourceName)
	End Method

	Method FunctionName:String(functionId:String)
		Local result:String = String(functionNames.ValueForKey(functionId))
		If result.length Then Return result
		AddDiagnostic("BMXC2013", "IR function '" + functionId + "' has no C name", Null)
		Return "bmx_missing_function"
	End Method

	Method CType:String(typeName:String, source:TCompilerSourceLocation)
		Local normalized:String = typeName.Trim().ToLower()
		If normalized = "__pico_exception" Then Return "BMXPicoException"
		If normalized.EndsWith("]") Then
			If EmbeddedArrayTypes() Then Return "BMXPicoArray *"
			If runtimeTypes Then Return "BBARRAY"
			AddDiagnostic("BMXC2028", "Managed Array values require the BlitzMax runtime C backend", source)
			Return "void *"
		End If
		If normalized.StartsWith("closure<") Then
			If EmbeddedObjectTypes() Then Return "BMXPicoClosure *"
			If runtimeTypes Then Return "BBClosure *"
			AddDiagnostic("BMXC2080", "Managed Closure values require the BlitzMax runtime C backend", source)
			Return "void *"
		End If
		Local irEnum:TCompilerIrEnum = TCompilerIrEnum(enumTypes.ValueForKey(normalized))
		If irEnum Then Return CType(irEnum.underlyingType, source)
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structTypes.ValueForKey(normalized))
		If irStruct Then Return "struct " + StructName(irStruct.structId)
		Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructTypes.ValueForKey(normalized))
		If importedStruct Then Return "struct " + importedStruct.abiName
		Local irInterface:TCompilerIrInterface = TCompilerIrInterface(interfaceTypes.ValueForKey(normalized))
		If irInterface Then
			If irInterface.isExternInterface Then Return NativeInterfaceReceiverType(irInterface)
			If EmbeddedObjectTypes() Then Return "BMXPicoObject *"
			If runtimeTypes Then Return "BBOBJECT"
			AddDiagnostic("BMXC2029", "Managed Interface values require the BlitzMax runtime C backend", source)
			Return "void *"
		End If
		If opaqueInterfaceTypes.Contains(normalized) Then
			If EmbeddedObjectTypes() Then Return "BMXPicoObject *"
			If runtimeTypes Then Return "BBOBJECT"
			AddDiagnostic("BMXC2029", "Managed Interface values require the BlitzMax runtime C backend", source)
			Return "void *"
		End If
		Local irClass:TCompilerIrClass = TCompilerIrClass(classTypes.ValueForKey(normalized))
		If irClass Then
			If EmbeddedObjectTypes() Then Return "struct " + ObjectName(irClass.classId) + " *"
			If runtimeTypes Then Return "struct " + ObjectName(irClass.classId) + " *"
			AddDiagnostic("BMXC2029", "Managed Object values require the BlitzMax runtime C backend", source)
			Return "void *"
		End If
		Local importedClass:TCompilerIrImportedClass = TCompilerIrImportedClass(importedClassTypes.ValueForKey(normalized))
		If importedClass Then
			If EmbeddedObjectTypes() And importedClass.abiName = "bbObjectClass" Then Return "BMXPicoObject *"
			If EmbeddedObjectTypes() Then Return "struct " + importedClass.abiName + "_obj *"
			If runtimeTypes And importedClass.abiName = "bbObjectClass" Then Return "BBOBJECT"
			If runtimeTypes Then Return "struct " + importedClass.abiName + "_obj *"
			AddDiagnostic("BMXC2029", "Managed imported Object values require the BlitzMax runtime C backend", source)
			Return "void *"
		End If
		If normalized = "object" And EmbeddedObjectTypes() Then Return "BMXPicoObject *"
		If normalized.EndsWith(" ptr") Then
			Local elementName:String = typeName.Trim()[..typeName.Trim().length - 4].Trim()
			If elementName.ToLower() = "byte" Then
				If runtimeTypes Then Return "BBBYTE *"
				Return "void *"
			End If
			If elementName.ToLower() = "void" Then Return "void *"
			Return CType(elementName, source) + " *"
		End If
		If runtimeTypes Then
			Select typeName.ToLower()
				Case "void" Return "void"
				Case "byte" Return "BBBYTE"
				Case "short" Return "BBSHORT"
				Case "int" Return "BBINT"
				Case "uint" Return "BBUINT"
				Case "long" Return "BBLONG"
				Case "ulong" Return "BBULONG"
				Case "longint" Return "BBLONGINT"
				Case "ulongint" Return "BBULONGINT"
				Case "size_t" Return "BBSIZET"
				Case "wparam" Return "uintptr_t"
				Case "lparam" Return "intptr_t"
				Case "float" Return "BBFLOAT"
				Case "double" Return "BBDOUBLE"
				Case "float64" Return "BBFLOAT64"
				Case "int128" Return "BBINT128"
				Case "float128" Return "BBFLOAT128"
				Case "double128" Return "BBDOUBLE128"
				Case "string" Return "BBSTRING"
				Case "object" Return "BBOBJECT"
			End Select
		End If
		If normalized = "string" And EmbeddedStringTypes() Then Return "const BMXPicoString *"
		If normalized = "string" Then
			AddDiagnostic("BMXC2025", "Managed String values require the BlitzMax runtime C backend", source)
			Return "void *"
		End If
		Select typeName.ToLower()
			Case "void" Return "void"
			Case "byte" Return "uint8_t"
			Case "short" Return "uint16_t"
			Case "int" Return "int32_t"
			Case "uint" Return "uint32_t"
			Case "long" Return "int64_t"
			Case "ulong" Return "uint64_t"
			Case "longint" Return "long"
			Case "ulongint" Return "unsigned long"
			Case "size_t" Return "size_t"
			Case "wparam" Return "uintptr_t"
			Case "lparam" Return "intptr_t"
			Case "float" Return "float"
			Case "double", "float64" Return "double"
		End Select
		AddDiagnostic("BMXC2020", "Semantic type '" + typeName + "' has no scalar C99 ABI mapping", source)
		Return "int32_t"
	End Method

	Method CParameterDeclaration:String(parameter:TCompilerIrParameter, name:String, source:TCompilerSourceLocation)
		If parameter.callableReturnType.length Then
			Local pointerPrefix:String = "*"
			If parameter.passingMode = PARAMETER_PASS_VAR Then pointerPrefix :+ "*"
			Return CType(parameter.callableReturnType, source) + " (" + CCallingConvention(parameter.callableCallingConvention) + pointerPrefix + name + ")(" + CCallableParameterList(parameter.callableParameters, source) + ")"
		End If
		If parameter.isStaticArray Then Return CType(parameter.staticArrayElementType, source) + " " + name + "[" + parameter.staticArrayLength + "]"
		Local result:String = CType(parameter.semanticType, source)
		If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " *"
		Return result + " " + name
	End Method

	Method CNativeParameterDeclaration:String(parameter:TCompilerIrParameter, name:String, source:TCompilerSourceLocation)
		If parameter.nativeStringEncoding = NATIVE_STRING_UTF8 Then Return "BBBYTE * " + name
		If parameter.nativeStringEncoding = NATIVE_STRING_UTF16 Then Return "BBChar * " + name
		Return CParameterDeclaration(parameter, name, source)
	End Method

	Method CParameterType:String(parameter:TCompilerIrParameter, source:TCompilerSourceLocation)
		If parameter.callableReturnType.length Then
			Local pointerPrefix:String = "*"
			If parameter.passingMode = PARAMETER_PASS_VAR Then pointerPrefix :+ "*"
			Return CType(parameter.callableReturnType, source) + " (" + CCallingConvention(parameter.callableCallingConvention) + pointerPrefix + ")(" + CCallableParameterList(parameter.callableParameters, source) + ")"
		End If
		If parameter.isStaticArray Then Return CType(parameter.staticArrayElementType, source) + " *"
		Local result:String = CType(parameter.semanticType, source)
		If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " *"
		Return result
	End Method

	Method CCallablePointerType:String(returnType:String, parameters:TCompilerIrParameter[], pointerDepth:Int, source:TCompilerSourceLocation, callingConvention:String = "c")
		Local pointers:String
		For Local index:Int = 0 Until pointerDepth
			pointers :+ "*"
		Next
		Return CType(returnType, source) + " (" + CCallingConvention(callingConvention) + pointers + ")(" + CCallableParameterList(parameters, source) + ")"
	End Method

	Method CFunctionDeclaration:String(returnType:String, callableReturnType:String, callableReturnParameters:TCompilerIrParameter[], name:String, parameters:String, source:TCompilerSourceLocation, callingConvention:String = "c", callableReturnCallingConvention:String = "c")
		If callableReturnType.length Then
			Return CType(callableReturnType, source) + " (" + CCallingConvention(callableReturnCallingConvention) + "*" + CCallingConvention(callingConvention) + name + "(" + parameters + "))(" + CCallableParameterList(callableReturnParameters, source) + ")"
		End If
		Return CType(returnType, source) + " " + CCallingConvention(callingConvention) + name + "(" + parameters + ")"
	End Method

	Method CFunctionPointerDeclaration:String(returnType:String, callableReturnType:String, callableReturnParameters:TCompilerIrParameter[], name:String, parameters:String, source:TCompilerSourceLocation, callingConvention:String = "c", callableReturnCallingConvention:String = "c")
		If callableReturnType.length Then
			Return CType(callableReturnType, source) + " (" + CCallingConvention(callableReturnCallingConvention) + "*(" + CCallingConvention(callingConvention) + "*" + name + ")(" + parameters + "))(" + CCallableParameterList(callableReturnParameters, source) + ")"
		End If
		Return CType(returnType, source) + " (" + CCallingConvention(callingConvention) + "*" + name + ")(" + parameters + ")"
	End Method

	Method CVariableDeclaration:String(variable:TCompilerIrVariableDeclaration, name:String)
		If variable.callableReturnType.length Then
			Local pointerPrefix:String = "*"
			If variable.isVolatile Then pointerPrefix = "* volatile "
			Return CType(variable.callableReturnType, variable.source) + " (" + CCallingConvention(variable.callableCallingConvention) + pointerPrefix + name + ")(" + CCallableParameterList(variable.callableParameters, variable.source) + ")"
		End If
		Local qualifier:String
		If variable.isVolatile Then qualifier = " volatile"
		Return CType(variable.semanticType, variable.source) + qualifier + " " + name
	End Method

	Method CFieldDeclaration:String(irField:TCompilerIrClassField, name:String)
		If irField.isStaticArray Then Return CType(irField.staticArrayElementType, irField.source) + " " + name + "[" + irField.staticArrayLength + "]"
		If irField.callableReturnType.length Then
			Return CCallableFieldDeclaration(irField.callableReturnType, irField.callableParameters, name, irField.source, irField.callableCallingConvention)
		End If
		Return CType(irField.semanticType, irField.source) + " " + name
	End Method

	Method CCallableFieldDeclaration:String(returnType:String, parameters:TCompilerIrParameter[], name:String, source:TCompilerSourceLocation, callingConvention:String = "c")
		Return CType(returnType, source) + " (" + CCallingConvention(callingConvention) + "*" + name + ")(" + CCallableParameterList(parameters, source) + ")"
	End Method

	Method CallableSentinel:String(returnType:String, parameters:TCompilerIrParameter[], source:TCompilerSourceLocation, callingConvention:String = "c")
		If EmbeddedObjectTypes() Then Return "0"
		If Not runtimeTypes Then
			AddDiagnostic("BMXC2062", "Unset callable values require the BlitzMax runtime C backend", source)
			Return "0"
		End If
		Return "((union { BBFuncPtr source; " + CType(returnType, source) + " (" + CCallingConvention(callingConvention) + "*target)(" + CCallableParameterList(parameters, source) + "); }){ .source = &brl_blitz_NullFunctionError }.target)"
	End Method

	Method EmitClosureCall:String(call:TCompilerIrClosureCall)
		If EmbeddedObjectTypes() Then
			Local picoCallee:String = EmitExpression(call.callee)
			Local picoParameterTypes:String = "BMXPicoObject *"
			For Local picoParameter:TCompilerIrParameter = EachIn call.parameters
				picoParameterTypes :+ ", " + CParameterType(picoParameter, call.source)
			Next
			Local picoInvoke:String = "((" + CType(call.returnType, call.source) + " (*)(" + picoParameterTypes + "))bmx_pico_closure_assert((void *)" + picoCallee + ")->invoke)(bmx_pico_closure_assert((void *)" + picoCallee + ")->environment"
			For Local picoArgument:TCompilerIrExpression = EachIn call.arguments
				picoInvoke :+ ", " + EmitExpression(picoArgument)
			Next
			Return picoInvoke + ")"
		End If
		If Not runtimeTypes Then
			AddDiagnostic("BMXC2080", "Managed Closure invocation requires the BlitzMax runtime C backend", call.source)
			Return CDefaultValue(call.returnType)
		End If
		Local callee:String = EmitExpression(call.callee)
		Local parameterTypes:String = "BBOBJECT"
		For Local parameter:TCompilerIrParameter = EachIn call.parameters
			parameterTypes :+ ", " + CParameterType(parameter, call.source)
		Next
		Local invoke:String = "((union { BBFuncPtr source; " + CType(call.returnType, call.source) + " (*target)(" + parameterTypes + "); }){ .source = " + callee + "->invoke }.target)(" + callee + "->environment"
		For Local argument:TCompilerIrExpression = EachIn call.arguments
			invoke :+ ", " + EmitExpression(argument)
		Next
		invoke :+ ")"
		Local nullTest:String = "((BBOBJECT)" + callee + " == (BBOBJECT)&bbNullObject)"
		If call.returnType.ToLower() = "void" Then Return "(" + nullTest + " ? brl_blitz_NullFunctionError() : " + invoke + ")"
		Return "(" + nullTest + " ? (brl_blitz_NullFunctionError(), " + CDefaultValue(call.returnType) + ") : " + invoke + ")"
	End Method

	Function CCallingConvention:String(callingConvention:String)
		If callingConvention.ToLower() = "stdcall" Then Return "__stdcall "
		Return ""
	End Function

	Method CCallableParameterList:String(parameters:TCompilerIrParameter[], source:TCompilerSourceLocation)
		If Not parameters.length Then Return "void"
		Local result:String
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ", "
			result :+ CParameterType(parameters[index], source)
		Next
		Return result
	End Method

	Method EmitEnumIntrinsic:String(intrinsic:TCompilerIrEnumIntrinsic)
		If intrinsic.intrinsicKind = IR_ENUM_INTRINSIC_ORDINAL And intrinsic.receiver Then Return EmitExpression(intrinsic.receiver)
		If EmbeddedStringTypes() Then
			Local picoEnum:TCompilerIrEnum = EnumById(intrinsic.enumId)
			If Not picoEnum Or picoEnum.isImported Then
				AddDiagnostic("BMXC2076", "Imported Enum runtime intrinsics are not available in the current Pico descriptor tier", intrinsic.source)
				Return "0"
			End If
			Local descriptor:String = "&" + PicoEnumDescriptorName(picoEnum)
			Select intrinsic.intrinsicKind
				Case IR_ENUM_INTRINSIC_VALUES
					Return "bmx_pico_enum_values(" + descriptor + ")"
				Case IR_ENUM_INTRINSIC_TO_STRING
					If intrinsic.receiver Then Return "bmx_pico_enum_to_string(" + descriptor + ", (uint64_t)(" + EmitExpression(intrinsic.receiver) + "))"
				Case IR_ENUM_INTRINSIC_TRY_CONVERT
					If intrinsic.arguments.length = 2 Then Return "bmx_pico_enum_try_convert(" + descriptor + ", (uint64_t)(" + EmitExpression(intrinsic.arguments[0]) + "), (void *)(" + EmitExpression(intrinsic.arguments[1]) + "))"
				Case IR_ENUM_INTRINSIC_FROM_STRING
					If intrinsic.arguments.length = 1 Then Return "((" + CType(picoEnum.underlyingType, intrinsic.source) + ")bmx_pico_enum_from_string(" + descriptor + ", " + EmitExpression(intrinsic.arguments[0]) + "))"
			End Select
			AddDiagnostic("BMXC2076", "Pico Enum intrinsic has an invalid receiver or argument shape", intrinsic.source)
			Return "0"
		End If
		If Not runtimeTypes Then
			AddDiagnostic("BMXC2076", "Enum runtime intrinsic requires the BlitzMax runtime C backend", intrinsic.source)
			Return "0"
		End If
		Local irEnum:TCompilerIrEnum = EnumById(intrinsic.enumId)
		If Not irEnum Or Not irEnum.runtimeDescriptor Then
			AddDiagnostic("BMXC2076", "Enum intrinsic has no retained runtime descriptor", intrinsic.source)
			Return "0"
		End If
		Local enumDescriptor:TCompilerIrEnumRuntimeDescriptor = irEnum.runtimeDescriptor
		Select intrinsic.intrinsicKind
			Case IR_ENUM_INTRINSIC_ORDINAL
				If intrinsic.receiver Then Return EmitExpression(intrinsic.receiver)
			Case IR_ENUM_INTRINSIC_VALUES
				Return "bbEnumValues(" + enumDescriptor.descriptorAbiName + ")"
			Case IR_ENUM_INTRINSIC_TO_STRING
				If intrinsic.receiver Then Return enumDescriptor.toStringAbiName + "(" + EmitExpression(intrinsic.receiver) + ")"
			Case IR_ENUM_INTRINSIC_TRY_CONVERT
				If intrinsic.arguments.length = 2 Then Return enumDescriptor.tryConvertAbiName + "(" + EmitExpression(intrinsic.arguments[0]) + ", " + EmitExpression(intrinsic.arguments[1]) + ")"
			Case IR_ENUM_INTRINSIC_FROM_STRING
				If intrinsic.arguments.length = 1 Then Return enumDescriptor.fromStringAbiName + "(" + EmitExpression(intrinsic.arguments[0]) + ")"
		End Select
		AddDiagnostic("BMXC2076", "Enum intrinsic has an invalid receiver or argument shape", intrinsic.source)
		Return "0"
	End Method

	Method ClassById:TCompilerIrClass(classId:String)
		Return TCompilerIrClass(classesById.ValueForKey(classId))
	End Method

	Method EnumById:TCompilerIrEnum(enumId:String)
		Return TCompilerIrEnum(enumsById.ValueForKey(enumId))
	End Method

	Method ImportedClassById:TCompilerIrImportedClass(importedClassId:String)
		Return TCompilerIrImportedClass(importedClassesById.ValueForKey(importedClassId))
	End Method

	Method StructById:TCompilerIrStruct(structId:String)
		Return TCompilerIrStruct(structsById.ValueForKey(structId))
	End Method

	Method ImportedStructRoutineById:TCompilerIrImportedStructRoutine(routineId:String)
		Return TCompilerIrImportedStructRoutine(importedStructRoutinesById.ValueForKey(routineId))
	End Method

	Method ImportedMethodById:TCompilerIrImportedMethod(methodId:String)
		Return TCompilerIrImportedMethod(importedMethodsById.ValueForKey(methodId))
	End Method

	Method ImportedConstructorById:TCompilerIrImportedConstructor(constructorId:String)
		Return TCompilerIrImportedConstructor(importedConstructorsById.ValueForKey(constructorId))
	End Method

	Method InterfaceById:TCompilerIrInterface(interfaceId:String)
		Return TCompilerIrInterface(interfacesById.ValueForKey(interfaceId))
	End Method

	Method FunctionById:TCompilerIrFunction(functionId:String)
		For Local routine:TCompilerIrFunction = EachIn currentModule.functions
			If routine.functionId = functionId Then Return routine
		Next
		Return Null
	End Method

	Method ClassName:String(classId:String)
		Return String(classNames.ValueForKey(classId))
	End Method

	Method ObjectName:String(classId:String)
		Return String(objectNames.ValueForKey(classId))
	End Method

	Method DescriptorName:String(classId:String)
		Return String(descriptorNames.ValueForKey(classId))
	End Method

	Method ConstructorName:String(classId:String)
		Return String(constructorNames.ValueForKey(classId))
	End Method

	Method ObjectNewHelperName:String(functionId:String)
		Local name:String = FunctionName(functionId) + "_ObjectNew"
		Local routine:TCompilerIrFunction = FunctionById(functionId)
		If routine And routine.ownerClassId.length Then
			Local irClass:TCompilerIrClass = ClassById(routine.ownerClassId)
			If irClass And irClass.isPublished And Not name.StartsWith("_") Then name = "_" + name
		End If
		Return name
	End Method

	Method FieldName:String(classId:String, fieldId:String)
		Return String(fieldNames.ValueForKey(classId + "." + fieldId))
	End Method

	Method StructName:String(structId:String)
		Return String(structNames.ValueForKey(structId))
	End Method

	Method StructFieldName:String(structId:String, fieldId:String)
		Return String(structFieldNames.ValueForKey(structId + "." + fieldId))
	End Method

	Method StructNewHelperName:String(structId:String, constructorFunctionId:String)
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structsById.ValueForKey(structId))
		If irStruct And (irStruct.isPublished Or irStruct.hasStableLocalAbi) Then
			If constructorFunctionId.length Then
				Local constructor:TCompilerIrFunction = FunctionById(constructorFunctionId)
				If constructor And constructor.abiName.length Then Return constructor.abiName + "_ObjectNew"
			End If
			Return irStruct.abiName + "_New_ObjectNew"
		End If
		Local ownerIdentity:String = structId
		If irStruct And irStruct.abiName.length Then ownerIdentity = irStruct.abiName
		Local suffix:String = ownerIdentity + "_default"
		If constructorFunctionId.length Then suffix = ownerIdentity + "_" + constructorFunctionId
		Return "bmx_struct_new_" + SafeIdentifier(suffix)
	End Method

	Method StructImplicitConstructorName:String(irStruct:TCompilerIrStruct)
		If irStruct.isPublished Then Return "_" + irStruct.abiName + "_New"
		Return irStruct.abiName + "_New"
	End Method

	Function ConstructorFunctionId:String(constructor:TCompilerIrFunction)
		If constructor Then Return constructor.functionId
		Return ""
	End Function

	Function CQuoted:String(value:String)
		Return Chr(34) + value.Replace("\", "\\").Replace(Chr(34), "\" + Chr(34)) + Chr(34)
	End Function

	Method CLiteral:String(text:String, source:TCompilerSourceLocation)
		Local value:String = text.Trim()
		Select value.ToLower()
			Case "true" Return "1"
			Case "false" Return "0"
		End Select
		Local colon:Int = value.Find(":")
		If colon >= 0 Then value = value[..colon]
		If value.StartsWith("$") Then Return "0x" + value[1..]
		If value.StartsWith("%") Then
			AddDiagnostic("BMXC2024", "Binary literals require canonical constant lowering before strict C99 emission", source)
			Return "0"
		End If
		If value.EndsWith("!") Or value.EndsWith("#") Then value = value[..value.length - 1]
		Local digitStart:Int
		If value.StartsWith("+") Or value.StartsWith("-") Then digitStart = 1
		Local decimalInteger:Int = digitStart < value.length
		For Local index:Int = digitStart Until value.length
			If value[index] < 48 Or value[index] > 57 Then
				decimalInteger = False
				Exit
			End If
		Next
		If decimalInteger Then
			Local firstDigit:Int = digitStart
			While firstDigit + 1 < value.length And value[firstDigit] = 48
				firstDigit :+ 1
			Wend
			If firstDigit > digitStart Then value = value[..digitStart] + value[firstDigit..]
		End If
		For Local index:Int = 0 Until value.length
			Local character:Int = value[index]
			If (character >= 48 And character <= 57) Or character = 43 Or character = 45 Or character = 46 Or character = 69 Or character = 101 Then Continue
			AddDiagnostic("BMXC2021", "Literal '" + text + "' is not supported by the scalar C99 backend", source)
			Return "0"
		Next
		Return value
	End Method

	Method CUnaryOperator:String(operatorText:String, source:TCompilerSourceLocation)
		Select operatorText.ToLower()
			Case "+", "-" Return operatorText
			Case "not" Return "!"
			Case "~~" Return "~~"
			Case "sizeof" Return "sizeof "
			Case "alignof" Return "__alignof__ "
		End Select
		AddDiagnostic("BMXC2022", "Unary operator '" + operatorText + "' has no scalar C99 lowering", source)
		Return ""
	End Method

	Method CBinaryOperator:String(operatorText:String, source:TCompilerSourceLocation)
		Select operatorText.ToLower()
			Case "+", "-", "*", "/", "<", "<=", ">", ">=", "|", "&" Return operatorText
			Case "~~" Return "^"
			Case "=" Return "=="
			Case "<>" Return "!="
			Case "mod" Return "%"
			Case "shl" Return "<<"
			Case "shr", "sar" Return ">>"
			Case "and" Return "&&"
			Case "or" Return "||"
			Case "xor" Return "^"
		End Select
		AddDiagnostic("BMXC2023", "Binary operator '" + operatorText + "' has no scalar C99 lowering", source)
		Return "+"
	End Method

	Method LocalName:String(symbolId:String, sourceName:String)
		If currentModule And currentModule.gdbDebug And sourceName.length And Not CReservedIdentifier(sourceName) Then
			Local debugName:String = SafeIdentifier(sourceName)
			Local count:Int = Int(String(gdbLocalNameCounts.ValueForKey(sourceName.ToLower())))
			If count = 1 And debugName.length And Not debugName.ToLower().StartsWith("bmx_") Then Return debugName
		End If
		Return "bmx_" + SafeIdentifier(symbolId + "_" + sourceName)
	End Method

	Function CReservedIdentifier:Int(value:String)
		Select value.ToLower()
			Case "alignas", "alignof", "auto", "bool", "break", "case", "char", "complex", "const", "continue", "default", "do", "double", "else", "enum", "extern", "false", "float", "for", "goto", "if", "imaginary", "inline", "int", "long", "null", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "true", "typedef", "union", "unsigned", "void", "volatile", "while"
				Return True
		End Select
		Return False
	End Function

	Function SafeIdentifier:String(value:String)
		Local result:String
		For Local index:Int = 0 Until value.length
			Local character:Int = value[index]
			If (character >= 48 And character <= 57) Or (character >= 65 And character <= 90) Or (character >= 97 And character <= 122) Or character = 95 Then
				result :+ Chr(character)
			Else
				result :+ "_"
			End If
		Next
		If Not result.length Then result = "unnamed"
		If result[0] >= 48 And result[0] <= 57 Then result = "_" + result
		Return result
	End Function

	Method AddDiagnostic(code:String, message:String, source:TCompilerSourceLocation)
		If source Then
			diagnostics :+ [TCompilerDiagnostic.Create(code, message, source.path, source.span, source.line, source.column)]
		Else
			diagnostics :+ [TCompilerDiagnostic.Create(code, message)]
		End If
	End Method
End Type
