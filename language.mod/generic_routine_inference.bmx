' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "semantic_model.bmx"

Type TGenericRoutineBinding
	Field routine:TSymbol
	Field typeParameters:TSymbol[] = New TSymbol[0]
	Field typeArguments:TSemanticType[] = New TSemanticType[0]
	Field parameterTypes:TSemanticType[] = New TSemanticType[0]
	Field returnType:TSemanticType
	Field success:Int
	Field message:String
End Type

Type TGenericRoutineInference
	Function Infer:TGenericRoutineBinding(routine:TSymbol, argumentTypes:TSemanticType[], explicitTypeArguments:TSemanticType[] = Null, effectiveParameterTypes:TSemanticType[] = Null, effectiveReturnType:TSemanticType = Null, omittedArguments:Int[] = Null)
		Local result:TGenericRoutineBinding = New TGenericRoutineBinding
		result.routine = routine
		If Not routine Or routine.kind <> SYMBOL_ROUTINE Then Return Fail(result, "A routine symbol is required.")
		result.typeParameters = RoutineTypeParameters(routine)
		Local parameterPatterns:TSemanticType[] = routine.parameterTypes
		If effectiveParameterTypes Then parameterPatterns = effectiveParameterTypes
		Local returnPattern:TSemanticType = routine.declaredType
		If effectiveReturnType Then returnPattern = effectiveReturnType
		If argumentTypes.length > parameterPatterns.length Then Return Fail(result, "Routine '" + routine.name + "' accepts at most " + parameterPatterns.length + " argument(s), but " + argumentTypes.length + " were supplied.")

		Local substitutions:TMap = New TMap
		If explicitTypeArguments Then
			If explicitTypeArguments.length <> result.typeParameters.length Then Return Fail(result, "Routine '" + routine.name + "' expects " + result.typeParameters.length + " type argument(s), but " + explicitTypeArguments.length + " were supplied.")
			For Local index:Int = 0 Until result.typeParameters.length
				substitutions.Insert(result.typeParameters[index], explicitTypeArguments[index])
			Next
		End If

		' A complete explicit type-argument list determines every routine type
		' parameter. Argument compatibility is checked afterwards by normal
		' overload conversion classification; attempting structural inference here
		' would incorrectly reject valid conversions such as Concrete ->
		' Interface<T> and Int -> Long before applicability is considered.
		If Not explicitTypeArguments Then
			For Local index:Int = 0 Until argumentTypes.length
				If omittedArguments And index < omittedArguments.length And omittedArguments[index] Then Continue
				If Not Unify(parameterPatterns[index], argumentTypes[index], result.typeParameters, substitutions) Then Return Fail(result, "Argument " + (index + 1) + " does not match parameter type '" + parameterPatterns[index].DisplayName() + "'.")
			Next
		End If

		result.typeArguments = New TSemanticType[result.typeParameters.length]
		For Local index:Int = 0 Until result.typeParameters.length
			result.typeArguments[index] = TSemanticType(substitutions.ValueForKey(result.typeParameters[index]))
			If Not result.typeArguments[index] Then Return Fail(result, "Type argument '" + result.typeParameters[index].name + "' cannot be inferred from the routine arguments.")
		Next
		result.parameterTypes = New TSemanticType[parameterPatterns.length]
		For Local index:Int = 0 Until parameterPatterns.length
			result.parameterTypes[index] = Substitute(parameterPatterns[index], substitutions)
		Next
		result.returnType = Substitute(returnPattern, substitutions)
		result.success = True
		Return result
	End Function

	Function Unify:Int(pattern:TSemanticType, actual:TSemanticType, parameters:TSymbol[], substitutions:TMap)
		If Not pattern Or Not actual Then Return False
		Local parameterType:TTypeParameterSemanticType = TTypeParameterSemanticType(pattern)
		If parameterType And ContainsParameter(parameters, parameterType.symbol) Then
			Local existing:TSemanticType = TSemanticType(substitutions.ValueForKey(parameterType.symbol))
			If existing Then Return SameType(existing, actual)
			substitutions.Insert(parameterType.symbol, actual)
			Return True
		End If
		If Not ContainsAnyParameter(pattern, parameters) Then Return True
		Local patternNamed:TNamedSemanticType = TNamedSemanticType(pattern)
		Local actualNamed:TNamedSemanticType = TNamedSemanticType(actual)
		If patternNamed Then
			If Not actualNamed Or patternNamed.symbol <> actualNamed.symbol Or patternNamed.typeArguments.length <> actualNamed.typeArguments.length Then Return False
			For Local index:Int = 0 Until patternNamed.typeArguments.length
				If Not Unify(patternNamed.typeArguments[index], actualNamed.typeArguments[index], parameters, substitutions) Then Return False
			Next
			Return True
		End If
		Local patternArray:TArraySemanticType = TArraySemanticType(pattern)
		Local actualArray:TArraySemanticType = TArraySemanticType(actual)
		If patternArray Then Return actualArray And patternArray.rank = actualArray.rank And Unify(patternArray.elementType, actualArray.elementType, parameters, substitutions)
		Local patternStatic:TStaticArraySemanticType = TStaticArraySemanticType(pattern)
		Local actualStatic:TStaticArraySemanticType = TStaticArraySemanticType(actual)
		If patternStatic Then Return actualStatic And patternStatic.length = actualStatic.length And Unify(patternStatic.elementType, actualStatic.elementType, parameters, substitutions)
		Local patternPointer:TPointerSemanticType = TPointerSemanticType(pattern)
		Local actualPointer:TPointerSemanticType = TPointerSemanticType(actual)
		If patternPointer Then Return actualPointer And Unify(patternPointer.elementType, actualPointer.elementType, parameters, substitutions)
		Local patternCallable:TCallableSemanticType = TCallableSemanticType(pattern)
		Local actualCallable:TCallableSemanticType = TCallableSemanticType(actual)
		If patternCallable Then
			If Not actualCallable Or patternCallable.callingConvention <> actualCallable.callingConvention Or patternCallable.parameterTypes.length <> actualCallable.parameterTypes.length Then Return False
			For Local index:Int = 0 Until patternCallable.parameterTypes.length
				If index < patternCallable.parameterModes.length And index < actualCallable.parameterModes.length And patternCallable.parameterModes[index] <> actualCallable.parameterModes[index] Then Return False
				If Not Unify(patternCallable.parameterTypes[index], actualCallable.parameterTypes[index], parameters, substitutions) Then Return False
			Next
			Return Unify(patternCallable.returnType, actualCallable.returnType, parameters, substitutions)
		End If
		Local patternClosure:TClosureSemanticType = TClosureSemanticType(pattern)
		Local actualClosure:TClosureSemanticType = TClosureSemanticType(actual)
		If patternClosure Then Return actualClosure And Unify(patternClosure.signature, actualClosure.signature, parameters, substitutions)
		Return SameType(pattern, actual)
	End Function

	Function ContainsAnyParameter:Int(value:TSemanticType, parameters:TSymbol[])
		Local parameter:TTypeParameterSemanticType = TTypeParameterSemanticType(value)
		If parameter Then Return ContainsParameter(parameters, parameter.symbol)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then
			For Local argument:TSemanticType = EachIn named.typeArguments
				If ContainsAnyParameter(argument, parameters) Then Return True
			Next
			Return False
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then Return ContainsAnyParameter(arrayType.elementType, parameters)
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If staticArrayType Then Return ContainsAnyParameter(staticArrayType.elementType, parameters)
		Local pointerType:TPointerSemanticType = TPointerSemanticType(value)
		If pointerType Then Return ContainsAnyParameter(pointerType.elementType, parameters)
		Local callableType:TCallableSemanticType = TCallableSemanticType(value)
		If callableType Then
			If ContainsAnyParameter(callableType.returnType, parameters) Then Return True
			For Local parameterType:TSemanticType = EachIn callableType.parameterTypes
				If ContainsAnyParameter(parameterType, parameters) Then Return True
			Next
		End If
		Local closureType:TClosureSemanticType = TClosureSemanticType(value)
		If closureType Then Return ContainsAnyParameter(closureType.signature, parameters)
		Return False
	End Function

	Function Substitute:TSemanticType(value:TSemanticType, substitutions:TMap)
		If Not value Then Return Null
		Local parameterType:TTypeParameterSemanticType = TTypeParameterSemanticType(value)
		If parameterType Then
			Local replacement:TSemanticType = TSemanticType(substitutions.ValueForKey(parameterType.symbol))
			If replacement Then Return replacement
			Return value
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named And named.typeArguments.length Then
			Local replacement:TNamedSemanticType = New TNamedSemanticType
			replacement.kind = SEMANTIC_TYPE_NAMED
			replacement.symbol = named.symbol
			replacement.typeArguments = New TSemanticType[named.typeArguments.length]
			For Local index:Int = 0 Until named.typeArguments.length
				replacement.typeArguments[index] = Substitute(named.typeArguments[index], substitutions)
			Next
			Return replacement
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then
			Local replacement:TArraySemanticType = New TArraySemanticType
			replacement.kind = SEMANTIC_TYPE_ARRAY
			replacement.rank = arrayType.rank
			replacement.elementType = Substitute(arrayType.elementType, substitutions)
			Return replacement
		End If
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If staticArrayType Then
			Local replacement:TStaticArraySemanticType = New TStaticArraySemanticType
			replacement.kind = SEMANTIC_TYPE_STATIC_ARRAY
			replacement.length = staticArrayType.length
			replacement.boundSyntax = staticArrayType.boundSyntax
			replacement.elementType = Substitute(staticArrayType.elementType, substitutions)
			Return replacement
		End If
		Local pointerType:TPointerSemanticType = TPointerSemanticType(value)
		If pointerType Then
			Local replacement:TPointerSemanticType = New TPointerSemanticType
			replacement.kind = SEMANTIC_TYPE_POINTER
			replacement.elementType = Substitute(pointerType.elementType, substitutions)
			Return replacement
		End If
		Local callableType:TCallableSemanticType = TCallableSemanticType(value)
		If callableType Then
			Local replacement:TCallableSemanticType = New TCallableSemanticType
			replacement.kind = SEMANTIC_TYPE_CALLABLE
			replacement.routine = callableType.routine
			replacement.callingConvention = callableType.callingConvention
			replacement.returnType = Substitute(callableType.returnType, substitutions)
			replacement.parameterTypes = New TSemanticType[callableType.parameterTypes.length]
			replacement.parameterModes = callableType.parameterModes[..]
			For Local index:Int = 0 Until callableType.parameterTypes.length
				replacement.parameterTypes[index] = Substitute(callableType.parameterTypes[index], substitutions)
			Next
			Return replacement
		End If
		Local closureType:TClosureSemanticType = TClosureSemanticType(value)
		If closureType Then
			Local replacement:TClosureSemanticType = New TClosureSemanticType
			replacement.kind = SEMANTIC_TYPE_CLOSURE
			replacement.signature = TCallableSemanticType(Substitute(closureType.signature, substitutions))
			replacement.parameterNames = closureType.parameterNames[..]
			Return replacement
		End If
		Return value
	End Function

	Function SameType:Int(first:TSemanticType, second:TSemanticType)
		If first = second Then Return True
		If Not first Or Not second Or first.kind <> second.kind Then Return False
		Local firstNamed:TNamedSemanticType = TNamedSemanticType(first)
		Local secondNamed:TNamedSemanticType = TNamedSemanticType(second)
		If firstNamed Then
			If Not secondNamed Or firstNamed.symbol <> secondNamed.symbol Or firstNamed.typeArguments.length <> secondNamed.typeArguments.length Then Return False
			For Local index:Int = 0 Until firstNamed.typeArguments.length
				If Not SameType(firstNamed.typeArguments[index], secondNamed.typeArguments[index]) Then Return False
			Next
			Return True
		End If
		Local firstArray:TArraySemanticType = TArraySemanticType(first)
		Local secondArray:TArraySemanticType = TArraySemanticType(second)
		If firstArray Then Return secondArray And firstArray.rank = secondArray.rank And SameType(firstArray.elementType, secondArray.elementType)
		Local firstStatic:TStaticArraySemanticType = TStaticArraySemanticType(first)
		Local secondStatic:TStaticArraySemanticType = TStaticArraySemanticType(second)
		If firstStatic Then Return secondStatic And firstStatic.length = secondStatic.length And SameType(firstStatic.elementType, secondStatic.elementType)
		Local firstPointer:TPointerSemanticType = TPointerSemanticType(first)
		Local secondPointer:TPointerSemanticType = TPointerSemanticType(second)
		If firstPointer Then Return secondPointer And SameType(firstPointer.elementType, secondPointer.elementType)
		Local firstCallable:TCallableSemanticType = TCallableSemanticType(first)
		Local secondCallable:TCallableSemanticType = TCallableSemanticType(second)
		If firstCallable Then
			If Not secondCallable Or firstCallable.callingConvention <> secondCallable.callingConvention Or firstCallable.parameterTypes.length <> secondCallable.parameterTypes.length Or Not SameType(firstCallable.returnType, secondCallable.returnType) Then Return False
			For Local index:Int = 0 Until firstCallable.parameterTypes.length
				If index < firstCallable.parameterModes.length And index < secondCallable.parameterModes.length And firstCallable.parameterModes[index] <> secondCallable.parameterModes[index] Then Return False
				If Not SameType(firstCallable.parameterTypes[index], secondCallable.parameterTypes[index]) Then Return False
			Next
			Return True
		End If
		Local firstClosure:TClosureSemanticType = TClosureSemanticType(first)
		Local secondClosure:TClosureSemanticType = TClosureSemanticType(second)
		If firstClosure Then Return secondClosure And SameType(firstClosure.signature, secondClosure.signature)
		Local firstParameter:TTypeParameterSemanticType = TTypeParameterSemanticType(first)
		Local secondParameter:TTypeParameterSemanticType = TTypeParameterSemanticType(second)
		If firstParameter Then Return secondParameter And firstParameter.symbol = secondParameter.symbol
		Return first.DisplayName().ToLower() = second.DisplayName().ToLower()
	End Function

	Function RoutineTypeParameters:TSymbol[](routine:TSymbol)
		Local result:TSymbol[]
		If Not routine.memberScope Then Return result
		For Local symbol:TSymbol = EachIn routine.memberScope.declaredSymbols
			If symbol.kind = SYMBOL_TYPE_PARAMETER Then result :+ [symbol]
		Next
		Return result
	End Function

	Function ContainsParameter:Int(parameters:TSymbol[], symbol:TSymbol)
		For Local candidate:TSymbol = EachIn parameters
			If candidate = symbol Then Return True
		Next
		Return False
	End Function

	Function Fail:TGenericRoutineBinding(result:TGenericRoutineBinding, message:String)
		result.message = message
		Return result
	End Function
End Type
