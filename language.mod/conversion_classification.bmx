' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "generic_routine_inference.bmx"
Import "inheritance_validation.bmx"
Import "constant_evaluation.bmx"

Const CONVERSION_NONE:Int = 0
Const CONVERSION_IDENTITY:Int = 1
Const CONVERSION_NUMERIC_WIDENING:Int = 2
Const CONVERSION_REFERENCE:Int = 3
Const CONVERSION_NULL:Int = 4
Const CONVERSION_ERROR:Int = 5
Const CONVERSION_CONSTANT:Int = 6
Const CONVERSION_EXPLICIT:Int = 7
Const CONVERSION_NUMERIC_NARROWING:Int = 8
Const CONVERSION_NUMERIC_TO_STRING:Int = 9
Const CONVERSION_STRING_TO_NUMERIC:Int = 10
Const CONVERSION_ARRAY_TO_POINTER:Int = 11
Const CONVERSION_POINTER_TO_BYTE_POINTER:Int = 12
Const CONVERSION_BYTE_POINTER_TO_POINTER:Int = 13
Const CONVERSION_ARRAY_LITERAL:Int = 14
Const CONVERSION_STRING_TO_BYTE_POINTER:Int = 15
Const CONVERSION_CONTEXTUAL_NUMERIC_EXPRESSION:Int = 16
Const CONVERSION_DEFAULT_VALUE:Int = 17
Const CONVERSION_CALLABLE_VARIANCE:Int = 18
Const CONVERSION_VAR_REFERENCE:Int = 19
Const CONVERSION_ENUM_TO_STRING:Int = 20
Const CONVERSION_BYTE_POINTER_TO_CALLABLE:Int = 21
Const CONVERSION_CALLABLE_REFERENCE_TO_BYTE_POINTER:Int = 22
Const CONVERSION_OBJECT_TO_BYTE_POINTER:Int = 23
Const CONVERSION_POINTER_TO_VAR_REFERENCE:Int = 24
Const CONVERSION_ENUM_TO_UNDERLYING:Int = 25

Type TConversion
	Field kind:Int
	Field distance:Int
	Field score:Int

	Method Exists:Int()
		Return kind <> CONVERSION_NONE
	End Method
End Type

Type TConversionClassifier
	Field model:TSemanticModel
	Field inheritance:TInheritanceValidator
	Field constantVisiting:TMap = New TMap

	Function Create:TConversionClassifier(model:TSemanticModel)
		Local result:TConversionClassifier = New TConversionClassifier
		result.model = model
		result.inheritance = New TInheritanceValidator
		result.inheritance.model = model
		Return result
	End Function

	Method Classify:TConversion(actual:TSemanticType, required:TSemanticType)
		If Not actual Or Not required Then Return NoConversion()
		If TErrorSemanticType(actual) Or TErrorSemanticType(required) Then Return MakeConversion(CONVERSION_ERROR, 0, 0)
		If TGenericRoutineInference.SameType(actual, required) Then Return MakeConversion(CONVERSION_IDENTITY, 0, 0)
		If CanConvertCallable(actual, required) Then Return MakeConversion(CONVERSION_CALLABLE_VARIANCE, 1, 205)

		If IsNull(actual) And AcceptsDefaultValue(required) Then Return MakeConversion(CONVERSION_DEFAULT_VALUE, 0, 300)

		Local numericDistance:Int = NumericWideningDistance(actual, required)
		If numericDistance >= 0 Then Return MakeConversion(CONVERSION_NUMERIC_WIDENING, numericDistance, 100 + numericDistance)
		Local enumUnderlying:TSemanticType = EnumUnderlyingType(actual)
		If enumUnderlying And TGenericRoutineInference.SameType(enumUnderlying, required) Then
			Return MakeConversion(CONVERSION_ENUM_TO_UNDERLYING, 0, 50)
		End If
		If IsEnum(actual) And IsString(required) Then Return MakeConversion(CONVERSION_ENUM_TO_STRING, 0, 260)
		' Production BlitzMax permits numeric values to flow into String contexts.
		' The reverse direction is an explicit parse operation such as Int(text),
		' and must not participate in assignment or overload resolution.
		If NumericRankOf(actual) >= 0 And IsString(required) Then Return MakeConversion(CONVERSION_NUMERIC_TO_STRING, 0, 260)
		If IsString(actual) And IsBytePointer(required) Then Return MakeConversion(CONVERSION_STRING_TO_BYTE_POINTER, 0, 250)
		' Legacy byte-stream APIs may address the contiguous field region of a
		' managed Type instance. The runtime conversion deliberately skips the
		' object header; it is not a cast of the BBObject pointer itself.
		If IsManagedTypeReference(actual) And IsBytePointer(required) Then Return MakeConversion(CONVERSION_OBJECT_TO_BYTE_POINTER, 0, 275)
		If CanDecayArrayToPointer(actual, required) Then Return MakeConversion(CONVERSION_ARRAY_TO_POINTER, 0, 160)
		If CanUseAsBytePointer(actual, required) Then Return MakeConversion(CONVERSION_POINTER_TO_BYTE_POINTER, 0, 170)
		If CanUseBytePointerAsPointer(actual, required) Then Return MakeConversion(CONVERSION_BYTE_POINTER_TO_POINTER, 0, 170)
		' Reflection metadata stores native wrapper addresses as Byte Ptr and
		' materializes their callable signature at the use site. Production bcc
		' accepts this one-way bridge; callable-to-data-pointer remains explicit.
		If IsBytePointer(actual) And TCallableSemanticType(required) Then Return MakeConversion(CONVERSION_BYTE_POINTER_TO_CALLABLE, 0, 175)
		If CanConvertRuntimeObjectArray(actual, required) Then Return MakeConversion(CONVERSION_REFERENCE, 1, 201)

		If inheritance.IsSubtype(actual, required, 0) Then
			Local referenceDistance:Int = ReferenceDistance(actual, required, 0)
			If referenceDistance < 1 Then referenceDistance = 1
			Return MakeConversion(CONVERSION_REFERENCE, referenceDistance, 200 + referenceDistance)
		End If
		Return NoConversion()
	End Method

	Method CanConvertCallable:Int(actual:TSemanticType, required:TSemanticType)
		Local actualCallable:TCallableSemanticType = TCallableSemanticType(actual)
		Local requiredCallable:TCallableSemanticType = TCallableSemanticType(required)
		If Not actualCallable Or Not requiredCallable Or actualCallable.callingConvention <> requiredCallable.callingConvention Or actualCallable.parameterTypes.length <> requiredCallable.parameterTypes.length Then Return False
		For Local index:Int = 0 Until actualCallable.parameterTypes.length
			If Not TGenericRoutineInference.SameType(actualCallable.parameterTypes[index], requiredCallable.parameterTypes[index]) Then Return False
			Local actualMode:Int = PARAMETER_PASS_VALUE
			Local requiredMode:Int = PARAMETER_PASS_VALUE
			If index < actualCallable.parameterModes.length Then actualMode = actualCallable.parameterModes[index]
			If index < requiredCallable.parameterModes.length Then requiredMode = requiredCallable.parameterModes[index]
			If actualMode <> requiredMode Then Return False
		Next
		If TGenericRoutineInference.SameType(actualCallable.returnType, requiredCallable.returnType) Then Return True
		' Object-returning callbacks may use a more-derived return type. Their
		' native representation is compatible and callers only observe the base.
		If TNamedSemanticType(actualCallable.returnType) And TNamedSemanticType(requiredCallable.returnType) Then Return inheritance.IsSubtype(actualCallable.returnType, requiredCallable.returnType, 0)
		Return False
	End Method

	Method ClassifyExpression:TConversion(expression:TExpressionSyntax, actual:TSemanticType, required:TSemanticType)
		Local standard:TConversion = Classify(actual, required)
		If standard.Exists() Then Return standard
		' Callable values are native entry-point addresses. Production modules
		' pass both direct routine references and callable parameters/storage to
		' legacy Extern declarations typed as Byte Ptr.
		If TCallableSemanticType(actual) And IsBytePointer(required) Then
			Return MakeConversion(CONVERSION_CALLABLE_REFERENCE_TO_BYTE_POINTER, 0, 175)
		End If
		Local integerValue:Long
		If TPointerSemanticType(required) And TryIntegerConstant(expression, integerValue) And integerValue = 0 Then Return MakeConversion(CONVERSION_NULL, 0, 300)
		If IntegerConstantFits(expression, required) Then Return MakeConversion(CONVERSION_CONSTANT, 0, 100)
		If FloatingConstantFits(expression, required) Then Return MakeConversion(CONVERSION_CONSTANT, 0, 100)
		If CanContextuallyConvertNumericExpression(expression, actual, required) Then Return MakeConversion(CONVERSION_CONTEXTUAL_NUMERIC_EXPRESSION, 0, 110)
		If CanConvertArrayLiteral(expression, actual, required) Then Return MakeConversion(CONVERSION_ARRAY_LITERAL, 0, 100)
		Return NoConversion()
	End Method

	Method IsDirectRoutineReference:Int(expression:TExpressionSyntax)
		If Not expression Or Not model Then Return False
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
		' Instance Methods require a receiver-bearing closure and therefore are
		' not ordinary C function-pointer values.
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If declaration Then Return Not declaration.isMethod
		Return Not symbol.containingScope Or symbol.containingScope.kind <> SCOPE_TYPE
	End Method

	Method ClassifyExplicit:TConversion(actual:TSemanticType, required:TSemanticType)
		Local standard:TConversion = Classify(actual, required)
		If standard.Exists() Then Return standard
		If Not actual Or Not required Then Return NoConversion()
		' Enums retain a distinct semantic identity even though their runtime
		' representation is integral. Crossing that boundary is therefore always
		' explicit; the compiler may attach a debug-time value check when the
		' destination is an Enum.
		If IsEnum(actual) And IsIntegral(required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If IsIntegral(actual) And IsEnum(required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If CanExplicitlyCastRuntimeObjectArrays(actual, required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If CanExplicitlyCastArrayToPointer(actual, required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If IsString(actual) And NumericRankOf(required) >= 0 Then Return MakeConversion(CONVERSION_STRING_TO_NUMERIC, 0, 0)
		If NumericRankOf(actual) >= 0 And NumericRankOf(required) >= 0 Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If TPointerSemanticType(actual) And TPointerSemanticType(required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If TPointerSemanticType(actual) And IsIntegral(required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If IsIntegral(actual) And TPointerSemanticType(required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		' Native callable values may be round-tripped through Byte Ptr. Keep this
		' explicit: ordinary assignments and overload selection must not erase the
		' distinction between a data pointer and a function pointer.
		If TCallableSemanticType(actual) And IsBytePointer(required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If IsBytePointer(actual) And TCallableSemanticType(required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		' A value whose static Type does not implement an Interface may still be
		' an instance of a derived Type that does. BlitzMax Interface casts are
		' checked against the runtime object, so retain that possibility in both
		' Type-to-Interface and cross-Interface directions.
		If CanExplicitlyCastManagedInterface(actual, required) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		If inheritance.IsSubtype(required, actual, 0) Then Return MakeConversion(CONVERSION_EXPLICIT, 0, 0)
		Return NoConversion()
	End Method

	Function CanExplicitlyCastManagedInterface:Int(actual:TSemanticType, required:TSemanticType)
		Local actualNamed:TNamedSemanticType = TNamedSemanticType(actual)
		Local requiredNamed:TNamedSemanticType = TNamedSemanticType(required)
		If Not actualNamed Or Not actualNamed.symbol Or Not requiredNamed Or Not requiredNamed.symbol Then Return False
		Local actualKind:Int = actualNamed.symbol.kind
		Local requiredKind:Int = requiredNamed.symbol.kind
		If actualKind <> SYMBOL_TYPE And actualKind <> SYMBOL_INTERFACE Then Return False
		If requiredKind <> SYMBOL_TYPE And requiredKind <> SYMBOL_INTERFACE Then Return False
		Return actualKind = SYMBOL_INTERFACE Or requiredKind = SYMBOL_INTERFACE
	End Function

	Function CanExplicitlyCastRuntimeObjectArrays:Int(actual:TSemanticType, required:TSemanticType)
		Local actualArray:TArraySemanticType = TArraySemanticType(actual)
		Local requiredArray:TArraySemanticType = TArraySemanticType(required)
		If Not actualArray Or Not requiredArray Or actualArray.rank <> requiredArray.rank Then Return False
		' The BlitzMax runtime represents arrays of ordinary Type references with
		' the same ':' element category. bbArrayCastFromObject accepts casts within
		' that category without checking each element. Preserve that legacy,
		' unchecked behaviour for explicit casts only.
		Return IsRuntimeObjectArrayElement(actualArray.elementType) And IsRuntimeObjectArrayElement(requiredArray.elementType)
	End Function

	Function IsRuntimeObjectArrayElement:Int(elementType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(elementType)
		If builtin Then Return builtin.name.ToLower() = "object" Or builtin.name.ToLower() = "string"
		If TArraySemanticType(elementType) Then Return True
		Local named:TNamedSemanticType = TNamedSemanticType(elementType)
		Return named And named.symbol And named.symbol.kind = SYMBOL_TYPE
	End Function

	Method ClassifyAssignmentExpression:TConversion(expression:TExpressionSyntax, actual:TSemanticType, required:TSemanticType)
		Local standard:TConversion = ClassifyExpression(expression, actual, required)
		If standard.Exists() Then Return standard
		If NumericRankOf(actual) >= 0 And NumericRankOf(required) >= 0 Then Return MakeConversion(CONVERSION_NUMERIC_NARROWING, 0, 0)
		Return NoConversion()
	End Method

	Method ClassifyArgumentExpression:TConversion(expression:TExpressionSyntax, actual:TSemanticType, required:TSemanticType)
		Local standard:TConversion = ClassifyExpression(expression, actual, required)
		If standard.Exists() Then Return standard
		' BlitzMax permits numeric narrowing at ordinary value-parameter
		' boundaries just as it does for assignment and Return. Keep it worse
		' than a widening conversion during overload ranking, so an exact or
		' lossless overload remains preferred.
		If NumericRankOf(actual) >= 0 And NumericRankOf(required) >= 0 Then
			' A context-free integer literal still has to fit its target. This
			' preserves the established rejection of 256 -> Byte and -1 -> UInt;
			' genuine typed numeric values retain ordinary narrowing semantics.
			Local integerValue:Long
			If IsIntegral(required) And TryIntegerConstant(expression, integerValue) Then Return NoConversion()
			Return MakeConversion(CONVERSION_NUMERIC_NARROWING, 0, 150)
		End If
		Return NoConversion()
	End Method

	Function NumericRankOf:Int(value:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If Not builtin Then Return -1
		Return NumericRank(builtin.name.ToLower())
	End Function

	Function IsIntegral:Int(value:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam", "int128" Return True
		End Select
		Return False
	End Function

	Function IsEnum:Int(value:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		Return named And named.symbol And named.symbol.kind = SYMBOL_ENUM
	End Function

	Function EnumUnderlyingType:TSemanticType(value:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If Not named Or Not named.symbol Or named.symbol.kind <> SYMBOL_ENUM Or Not named.symbol.memberScope Then Return Null
		For Local ordinal:TSymbol = EachIn named.symbol.memberScope.LookupLocal("Ordinal")
			If ordinal.kind = SYMBOL_ROUTINE Then Return ordinal.declaredType
		Next
		Return Null
	End Function

	Function IsString:Int(value:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		Return builtin And builtin.name.ToLower() = "string"
	End Function

	Function IsManagedTypeReference:Int(value:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		Return named And named.symbol And named.symbol.kind = SYMBOL_TYPE
	End Function

	Function CanDecayArrayToPointer:Int(actual:TSemanticType, required:TSemanticType)
		Local pointerType:TPointerSemanticType = TPointerSemanticType(required)
		Local elementType:TSemanticType = StorageArrayElementType(actual)
		If Not elementType Or Not pointerType Then Return False
		If Not IsArrayStorageElement(elementType) Then Return False
		If TGenericRoutineInference.SameType(elementType, pointerType.elementType) Then Return True
		' Production BlitzMax permits contiguous numeric/Struct/pointer Array
		' storage to cross a differently typed native pointer boundary. This is
		' used by APIs whose public C view groups scalar cells into a Struct (for
		' example Float[] passed as SVec2F Ptr). The backend spells the requested
		' pointer type around BBARRAYDATA; managed-reference element Arrays remain
		' excluded from this raw-storage conversion.
		Return IsRawStoragePointer(pointerType)
	End Function

	Function StorageArrayElementType:TSemanticType(actual:TSemanticType)
		Local arrayType:TArraySemanticType = TArraySemanticType(actual)
		If arrayType And arrayType.rank = 1 Then Return arrayType.elementType
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(actual)
		If staticArrayType Then Return staticArrayType.elementType
		Return Null
	End Function

	Function IsArrayStorageElement:Int(elementType:TSemanticType)
		If NumericRankOf(elementType) >= 0 Then Return True
		' Arrays of native pointers are contiguous pointer-value storage too.
		' Production code uses this for C APIs that receive tables such as
		' libpng's row-pointer array through a raw Byte Ptr boundary.
		If TPointerSemanticType(elementType) Then Return True
		Local namedElement:TNamedSemanticType = TNamedSemanticType(elementType)
		Return namedElement And namedElement.symbol And namedElement.symbol.kind = SYMBOL_STRUCT
	End Function

	Function IsByteType:Int(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		Return builtin And builtin.name.ToLower() = "byte"
	End Function

	Function IsBytePointer:Int(semanticType:TSemanticType)
		Local pointer:TPointerSemanticType = TPointerSemanticType(semanticType)
		Return pointer And IsByteType(pointer.elementType)
	End Function

	Function CanUseAsBytePointer:Int(actual:TSemanticType, required:TSemanticType)
		Local actualPointer:TPointerSemanticType = TPointerSemanticType(actual)
		Local requiredPointer:TPointerSemanticType = TPointerSemanticType(required)
		If Not actualPointer Or Not requiredPointer Then Return False
		If IsByteType(requiredPointer.elementType) Then Return IsRawStoragePointer(actualPointer)
		If TPointerSemanticType(actualPointer.elementType) And TPointerSemanticType(requiredPointer.elementType) Then Return CanUseAsBytePointer(actualPointer.elementType, requiredPointer.elementType)
		Return False
	End Function

	Function CanUseBytePointerAsPointer:Int(actual:TSemanticType, required:TSemanticType)
		Local actualPointer:TPointerSemanticType = TPointerSemanticType(actual)
		Local requiredPointer:TPointerSemanticType = TPointerSemanticType(required)
		If Not actualPointer Or Not requiredPointer Then Return False
		If IsByteType(actualPointer.elementType) Then Return IsRawStoragePointer(requiredPointer)
		If TPointerSemanticType(actualPointer.elementType) And TPointerSemanticType(requiredPointer.elementType) Then Return CanUseBytePointerAsPointer(actualPointer.elementType, requiredPointer.elementType)
		Return False
	End Function

	Function IsRawStoragePointer:Int(value:TPointerSemanticType)
		If Not value Then Return False
		Local elementPointer:TPointerSemanticType = TPointerSemanticType(value.elementType)
		If elementPointer Then Return IsRawStoragePointer(elementPointer)
		' Varptr of a callable Local addresses the function-pointer storage cell;
		' it is not a callable value converted to a data pointer.
		If TCallableSemanticType(value.elementType) Then Return True
		Return IsArrayStorageElement(value.elementType)
	End Function

	Method CanConvertRuntimeObjectArray:Int(actual:TSemanticType, required:TSemanticType)
		Local actualArray:TArraySemanticType = TArraySemanticType(actual)
		Local requiredArray:TArraySemanticType = TArraySemanticType(required)
		If Not actualArray Or Not requiredArray Or actualArray.rank <> requiredArray.rank Then Return False
		If Not IsRuntimeObjectArrayElement(actualArray.elementType) Or Not IsRuntimeObjectArrayElement(requiredArray.elementType) Then Return False
		Return inheritance.IsSubtype(actualArray.elementType, requiredArray.elementType, 0)
	End Method

	Function CanExplicitlyCastArrayToPointer:Int(actual:TSemanticType, required:TSemanticType)
		Local pointerType:TPointerSemanticType = TPointerSemanticType(required)
		Local elementType:TSemanticType = StorageArrayElementType(actual)
		If Not elementType Or Not pointerType Then Return False
		If TGenericRoutineInference.SameType(elementType, pointerType.elementType) Then Return True
		If NumericRankOf(elementType) >= 0 And NumericRankOf(pointerType.elementType) >= 0 Then Return True
		Local namedElement:TNamedSemanticType = TNamedSemanticType(elementType)
		If namedElement And namedElement.symbol And namedElement.symbol.kind = SYMBOL_STRUCT And NumericRankOf(pointerType.elementType) >= 0 Then Return True
		Return False
	End Function

	Method IntegerConstantFits:Int(expression:TExpressionSyntax, required:TSemanticType)
		Local target:TBuiltinSemanticType = TBuiltinSemanticType(required)
		If Not target Then Return False
		Local value:Long
		If Not TryIntegerConstant(expression, value) Then Return False
		Select target.name.ToLower()
			Case "byte" Return value >= 0 And value <= 255
			Case "short" Return value >= 0 And value <= 65535
			Case "int" Return value >= -2147483648:Long And value <= 2147483647:Long
			Case "uint" Return value >= 0 And value <= 4294967295:Long
			Case "ulong", "ulongint", "size_t", "wparam", "lparam" Return value >= 0
		End Select
		Return False
	End Method

	Method FloatingConstantFits:Int(expression:TExpressionSyntax, required:TSemanticType)
		Local target:TBuiltinSemanticType = TBuiltinSemanticType(required)
		If Not target Or target.name.ToLower() <> "float" Then Return False
		Local value:Double
		If Not TryFloatingConstant(expression, value) Then Return False
		Return value >= -3.4028234663852886e38 And value <= 3.4028234663852886e38
	End Method

	Method TryFloatingConstant:Int(expression:TExpressionSyntax, value:Double Var)
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parenthesized Then Return TryFloatingConstant(parenthesized.expression, value)
		If TTypeAscriptionExpressionSyntax(expression) Then Return False
		Local integerValue:Long
		If TryIntegerConstant(expression, integerValue) Then
			value = integerValue
			Return True
		End If
		Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(expression)
		If unary Then
			Local operation:String = unary.operatorToken.text.ToLower()
			If operation <> "+" And operation <> "-" Then Return False
			If Not TryFloatingConstant(unary.operand, value) Then Return False
			If operation = "-" Then value = -value
			Return True
		End If
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
		If binary Then
			Local left:Double
			Local right:Double
			If Not TryFloatingConstant(binary.left, left) Or Not TryFloatingConstant(binary.right, right) Then Return False
			Select binary.operatorToken.text.ToLower()
				Case "+" value = left + right
				Case "-" value = left - right
				Case "*" value = left * right
				Case "/"
					If right = 0.0 Then Return False
					value = left / right
				Case "^" value = left ^ right
				Default Return False
			End Select
			Return True
		End If
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If Not literal Or literal.literalToken.kind <> TOKEN_FLOAT_LITERAL Then Return False
		value = literal.literalToken.text.ToDouble()
		Return True
	End Method

	Method CanConvertArrayLiteral:Int(expression:TExpressionSyntax, actual:TSemanticType, required:TSemanticType)
		Local literal:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(expression)
		Local actualArray:TArraySemanticType = TArraySemanticType(actual)
		Local requiredArray:TArraySemanticType = TArraySemanticType(required)
		If Not literal Or Not actualArray Or Not requiredArray Or actualArray.rank <> requiredArray.rank Or requiredArray.rank <> 1 Then Return False
		For Local element:TExpressionSyntax = EachIn literal.elements
			If Not element Then Continue
			Local elementType:TSemanticType = model.ExpressionType(element)
			If Not ClassifyExpression(element, elementType, requiredArray.elementType).Exists() Then Return False
		Next
		Return True
	End Method

	Method CanContextuallyConvertNumericExpression:Int(expression:TExpressionSyntax, actual:TSemanticType, required:TSemanticType)
		Local target:TBuiltinSemanticType = TBuiltinSemanticType(required)
		If Not target Or target.name.ToLower() <> "float" Or NumericRankOf(actual) < 0 Then Return False
		' Parentheses do not make an otherwise contextually typed arithmetic
		' expression into a genuine Double value. Peel them here so Float context
		' can reach literals in expressions such as s * (1.0 + percentage).
		Local candidate:TExpressionSyntax = expression
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(candidate)
		While parenthesized And parenthesized.expression
			candidate = parenthesized.expression
			parenthesized = TParenthesizedExpressionSyntax(candidate)
		Wend
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(candidate)
		If Not binary Or model.ResolvedCall(binary) Then Return False
		Select binary.operatorToken.text.ToLower()
			Case "+", "-", "*", "/", "^"
			Default Return False
		End Select
		Local leftType:TSemanticType = model.ExpressionType(binary.left)
		Local rightType:TSemanticType = model.ExpressionType(binary.right)
		If Not leftType Or Not rightType Then Return False
		Return ClassifyExpression(binary.left, leftType, required).Exists() And ClassifyExpression(binary.right, rightType, required).Exists()
	End Method

	Method TryIntegerConstant:Int(expression:TExpressionSyntax, value:Long Var)
		Local parenthesized:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parenthesized Then Return TryIntegerConstant(parenthesized.expression, value)
		' A type ascription makes the literal type-specific, so it must use the
		' ordinary conversion rules rather than value-based compatibility.
		If TTypeAscriptionExpressionSyntax(expression) Then Return False
		Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(expression)
		If unary Then
			Local operation:String = unary.operatorToken.text.ToLower()
			If operation = "asc" Then
				Local constant:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(model, unary)
				If constant And constant.kind = CONSTANT_VALUE_INTEGER Then
					value = constant.integerValue
					Return True
				End If
				Return False
			End If
			If operation <> "+" And operation <> "-" Then Return False
			If Not TryIntegerConstant(unary.operand, value) Then Return False
			If operation = "-" Then value = -value
			Return True
		End If
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
		If binary Then
			Local left:Long
			Local right:Long
			If Not TryIntegerConstant(binary.left, left) Or Not TryIntegerConstant(binary.right, right) Then Return False
			Select binary.operatorToken.text.ToLower()
				Case "+" value = left + right
				Case "-" value = left - right
				Case "*" value = left * right
				Case "/"
					If right = 0 Then Return False
					value = left / right
				Case "mod"
					If right = 0 Then Return False
					value = left Mod right
				Case "shl" value = left Shl Int(right)
				Case "shr" value = left Shr Int(right)
				Case "sar" value = left Sar Int(right)
				Case "&" value = left & right
				Case "|" value = left | right
				Case "~~" value = left ~ right
				Default Return False
			End Select
			Return True
		End If
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If literal Then
			Select literal.literalToken.text.ToLower()
				Case "true"
					value = 1
					Return True
				Case "false"
					value = 0
					Return True
			End Select
		End If
		If Not literal Or literal.literalToken.kind <> TOKEN_INTEGER_LITERAL Then Return TryNamedIntegerConstant(expression, value)
		Return TryParseIntegerMagnitude(literal.literalToken.text, value)
	End Method

	Method TryNamedIntegerConstant:Int(expression:TExpressionSyntax, value:Long Var)
		Local symbol:TSymbol
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then symbol = model.ReferencedSymbol(name)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then symbol = model.ReferencedSymbol(member)
		If Not symbol Or (symbol.kind <> SYMBOL_CONST And symbol.kind <> SYMBOL_ENUM_MEMBER) Then Return False
		Local existing:TConstantValue = model.SymbolConstantValue(symbol)
		If existing And existing.kind = CONSTANT_VALUE_INTEGER Then
			value = existing.integerValue
			Return True
		End If
		If constantVisiting.Contains(symbol) Then Return False
		constantVisiting.Insert(symbol, symbol)
		Local initializer:TExpressionSyntax
		If symbol.interfaceRecord Then initializer = symbol.interfaceRecord.valueSyntax
		If Not initializer Then
			Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(symbol.declaration)
			If declarator Then initializer = declarator.initializer
		End If
		Local result:Int = TryIntegerConstant(initializer, value)
		constantVisiting.Remove(symbol)
		Return result
	End Method

	Function TryParseIntegerMagnitude:Int(text:String, value:Long Var)
		If Not text.length Then Return False
		Local radix:Int = 10
		Local start:Int
		If text.length > 1 And text[0] = 36 Then
			radix = 16
			start = 1
		Else If text.length > 1 And text[0] = 37 Then
			radix = 2
			start = 1
		End If
		Local accumulator:ULong
		Local maximum:ULong = $ffffffffffffffff:ULong
		If radix = 10 Then maximum = 9223372036854775807:ULong
		For Local index:Int = start Until text.length
			Local char:Int = text[index]
			Local digit:Int
			If char >= 48 And char <= 57 Then
				digit = char - 48
			Else If char >= 65 And char <= 70 Then
				digit = char - 55
			Else If char >= 97 And char <= 102 Then
				digit = char - 87
			Else
				Return False
			End If
			If digit >= radix Or accumulator > (maximum - ULong(digit)) / ULong(radix) Then Return False
			accumulator = accumulator * ULong(radix) + ULong(digit)
		Next
		value = Long(accumulator)
		Return start < text.length
	End Function

	Method ReferenceDistance:Int(actual:TSemanticType, required:TSemanticType, depth:Int)
		If depth > 64 Then Return -1
		If TGenericRoutineInference.SameType(actual, required) Then Return depth
		Local requiredBuiltin:TBuiltinSemanticType = TBuiltinSemanticType(required)
		If requiredBuiltin And requiredBuiltin.name.ToLower() = "object" And TInheritanceValidator.IsObjectReference(actual) Then
			If TBuiltinSemanticType(actual) Or TArraySemanticType(actual) Then Return depth + 1
			Local namedActual:TNamedSemanticType = TNamedSemanticType(actual)
			Local info:TTypeInheritanceInfo = model.InheritanceInfo(namedActual.symbol)
			If Not info Or (info.baseEdges.length = 0 And info.interfaceEdges.length = 0) Then Return depth + 32
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(actual)
		If Not named Then Return -1
		Local inheritanceInfo:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not inheritanceInfo Then Return -1
		Local best:Int = -1
		For Local edge:TInheritanceEdge = EachIn CombinedEdges(inheritanceInfo)
			Local inherited:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, Substitutions(named))
			Local candidate:Int = ReferenceDistance(inherited, required, depth + 1)
			If candidate >= 0 And (best < 0 Or candidate < best) Then best = candidate
		Next
		Return best
	End Method

	Function NumericWideningDistance:Int(actual:TSemanticType, required:TSemanticType)
		Local source:TBuiltinSemanticType = TBuiltinSemanticType(actual)
		Local target:TBuiltinSemanticType = TBuiltinSemanticType(required)
		If Not source Or Not target Then Return -1
		Local fromName:String = source.name.ToLower()
		Local toName:String = target.name.ToLower()
		Local fromRank:Int = NumericRank(fromName)
		Local toRank:Int = NumericRank(toName)
		If fromRank < 0 Or toRank < 0 Then Return -1
		If Not CanWidenNumeric(fromName, toName) Then Return -1
		Return Max(1, toRank - fromRank)
	End Function

	Function CanWidenNumeric:Int(source:String, target:String)
		Select source
			Case "byte" Return InNames(target, ["short", "int", "uint", "long", "ulong", "longint", "ulongint", "int128", "float", "double", "float64", "float128", "double128"])
			Case "short" Return InNames(target, ["int", "long", "longint", "int128", "float", "double", "float64", "float128", "double128"])
			Case "int" Return InNames(target, ["long", "longint", "int128", "float", "double", "float64", "float128", "double128"])
			Case "uint" Return InNames(target, ["int", "long", "ulong", "longint", "ulongint", "int128", "float", "double", "float64", "float128", "double128"])
			Case "long" Return InNames(target, ["int128", "float", "double", "float64", "float128", "double128"])
			Case "longint" Return InNames(target, ["long", "int128", "float", "double", "float64", "float128", "double128"])
			Case "ulong" Return InNames(target, ["int128", "float", "double", "float64", "float128", "double128"])
			' ULongInt is the legacy unsigned wide-integer spelling. Production
			' accepts it where the native-width ULong overload is the available
			' unsigned 64-bit entry point, while retaining distinct ABI tags.
			Case "ulongint" Return InNames(target, ["ulong", "int128", "float", "double", "float64", "float128", "double128"])
			' Native buffer sizes are routinely passed to BlitzMax APIs whose count
			' parameter is Long. This is lossless on 32-bit targets and preserves the
			' established runtime/API convention on 64-bit targets.
			Case "size_t" Return target = "long"
			Case "float" Return InNames(target, ["double", "float64", "float128", "double128"])
			Case "double", "float64" Return InNames(target, ["float128", "double128"])
			Case "float128" Return target = "double128"
		End Select
		Return False
	End Function

	Function NumericRank:Int(name:String)
		Select name
			Case "byte" Return 1
			Case "short" Return 2
			Case "int", "uint" Return 3
			Case "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam" Return 4
			Case "int128" Return 5
			Case "float" Return 6
			Case "double", "float64" Return 7
			Case "float128" Return 8
			Case "double128" Return 9
		End Select
		Return -1
	End Function

	Function IsNull:Int(value:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		Return builtin And builtin.name.ToLower() = "null"
	End Function

	Function AcceptsDefaultValue:Int(value:TSemanticType)
		If Not value Then Return False
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If builtin Then Return builtin.name.ToLower() <> "void"
		' Null is BlitzMax's contextual default-value expression. Named types
		' (including enums and structs), type parameters, arrays, pointers,
		' callable values, and StaticArrays all have a default representation.
		Return True
	End Function

	Function Substitutions:TMap(named:TNamedSemanticType)
		Local result:TMap = New TMap
		If Not named Or Not named.symbol.memberScope Then Return result
		Local parameters:TSymbol[]
		For Local symbol:TSymbol = EachIn named.symbol.memberScope.declaredSymbols
			If symbol.kind = SYMBOL_TYPE_PARAMETER Then parameters :+ [symbol]
		Next
		For Local index:Int = 0 Until Min(parameters.length, named.typeArguments.length)
			result.Insert(parameters[index], named.typeArguments[index])
		Next
		Return result
	End Function

	Function CombinedEdges:TInheritanceEdge[](info:TTypeInheritanceInfo)
		Local result:TInheritanceEdge[] = New TInheritanceEdge[info.baseEdges.length + info.interfaceEdges.length]
		For Local index:Int = 0 Until info.baseEdges.length
			result[index] = info.baseEdges[index]
		Next
		For Local index:Int = 0 Until info.interfaceEdges.length
			result[info.baseEdges.length + index] = info.interfaceEdges[index]
		Next
		Return result
	End Function

	Function InNames:Int(value:String, values:String[])
		For Local candidate:String = EachIn values
			If value = candidate Then Return True
		Next
		Return False
	End Function

	Function MakeConversion:TConversion(kind:Int, distance:Int, score:Int)
		Local result:TConversion = New TConversion
		result.kind = kind
		result.distance = distance
		result.score = score
		Return result
	End Function

	Function NoConversion:TConversion()
		Return New TConversion
	End Function
End Type
