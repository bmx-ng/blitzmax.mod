' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "declaration_collector.bmx"
Import "symbol_accessibility.bmx"

Type TTypeResolutionOptions
	Field reportUnresolvedTypes:Int
End Type

Type TTypeCandidateCacheEntry
	Field symbols:TSymbol[]
End Type

Type TTypeResolver
	Field model:TSemanticModel
	Field options:TTypeResolutionOptions
	Field diagnostics:TList = New TList
	Field currentPath:String
	Field directTypeCandidates:TMap = New TMap
	Field transitiveTypeCandidates:TMap = New TMap
	Field directImportedScopeSet:TMap = New TMap

	Function Bind:TSemanticModel(model:TSemanticModel, options:TTypeResolutionOptions = Null)
		Local resolver:TTypeResolver = New TTypeResolver
		resolver.model = model
		resolver.options = options
		If Not resolver.options Then resolver.options = New TTypeResolutionOptions
		resolver.InitializeBuiltins()
		resolver.InitializeImportedScopeSet()
		resolver.InitializeSymbolTypes(model.globalScope)
		resolver.LinkCoreRuntimeTypes()
		resolver.BindScope(model.globalScope)
		model.diagnostics = MergeDiagnostics(model.diagnostics, DiagnosticsToArray(resolver.diagnostics))
		Return model
	End Function

	Method InitializeImportedScopeSet()
		For Local scope:TScope = EachIn model.directImportedScopes
			directImportedScopeSet.Insert(scope, scope)
		Next
	End Method

	Method InitializeBuiltins()
		Local names:String[] = ["Void", "Null", "Byte", "Short", "Int", "UInt", "Long", "ULong", "LongInt", "ULongInt", "Size_T", "Float", "Double", "String", "Object", "Int128", "Float64", "Float128", "Double128", "WParam", "LParam"]
		For Local name:String = EachIn names
			Local semanticType:TBuiltinSemanticType = New TBuiltinSemanticType
			semanticType.kind = SEMANTIC_TYPE_BUILTIN
			semanticType.name = name
			model.builtinTypes.Insert(name.ToLower(), semanticType)
		Next
	End Method

	Method LinkCoreRuntimeTypes()
		Local coreScope:TScope = model.ImportedScope("brl.classes")
		If Not coreScope Then Return
		For Local symbol:TSymbol = EachIn coreScope.declaredSymbols
			Select symbol.name.ToLower()
				Case "object"
					model.BuiltinType("Object").runtimeSymbol = symbol
				Case "string"
					model.BuiltinType("String").runtimeSymbol = symbol
				Case "___array"
					model.arrayRuntimeSymbol = symbol
			End Select
		Next
	End Method

	Method InitializeSymbolTypes(scope:TScope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			Select symbol.kind
				Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE, SYMBOL_ENUM
					Local namedType:TNamedSemanticType = New TNamedSemanticType
					namedType.kind = SEMANTIC_TYPE_NAMED
					namedType.symbol = symbol
					symbol.declaredType = namedType
				Case SYMBOL_TYPE_PARAMETER
					Local parameterType:TTypeParameterSemanticType = New TTypeParameterSemanticType
					parameterType.kind = SEMANTIC_TYPE_TYPE_PARAMETER
					parameterType.symbol = symbol
					symbol.declaredType = parameterType
			End Select
		Next
		For Local child:TScope = EachIn scope.children
			InitializeSymbolTypes(child)
		Next
		If scope.kind = SCOPE_ENUM And scope.owner Then
			For Local symbol:TSymbol = EachIn scope.declaredSymbols
				If symbol.kind = SYMBOL_ENUM_MEMBER Then symbol.declaredType = scope.owner.declaredType
			Next
		End If
	End Method

	Method BindScope(scope:TScope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			BindSymbol(symbol)
		Next
		For Local child:TScope = EachIn scope.children
			BindScope(child)
		Next
	End Method

	Method BindSymbol(symbol:TSymbol)
		Local previousPath:String = currentPath
		currentPath = symbol.originPath
		BindSymbolWithOrigin(symbol)
		currentPath = previousPath
	End Method

	Method BindSymbolWithOrigin(symbol:TSymbol)
		If symbol.isImported Then
			If Not symbol.interfaceRecord Then
				BindImportedChildSymbol(symbol)
				Return
			End If
			BindImportedSymbol(symbol)
			Return
		End If
		Select symbol.kind
			Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE
				If symbol.declaration Then BindTypeDeclaration(TTypeDeclarationSyntax(symbol.declaration), model.ScopeFor(symbol.declaration))
			Case SYMBOL_ENUM
				Local declaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(symbol.declaration)
				Local underlyingType:TSemanticType = model.BuiltinType("Int")
				If declaration And declaration.underlyingType Then underlyingType = Resolve(declaration.underlyingType, model.ScopeFor(symbol.declaration))
				EnsureEnumBuiltins(symbol, underlyingType)
			Case SYMBOL_ROUTINE
				Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
				If routine And routine.signature Then BindRoutineDeclaration(symbol, routine, model.ScopeFor(routine))
			Case SYMBOL_FIELD, SYMBOL_GLOBAL, SYMBOL_CONST, SYMBOL_LOCAL
				Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(symbol.declaration)
				If declarator And symbol.isTypeInferred Then
					' The expression binder establishes an inferred Local's fixed type
					' from its initializer or, for a multi-binding EachIn header, from
					' the corresponding IDeconstruct2 type argument.
					symbol.declaredType = ErrorType("")
				Else If declarator And declarator.inferenceToken Then
					' Invalid non-Local uses retain Int only as recovery after the
					' parser's focused declaration diagnostic.
					symbol.declaredType = model.BuiltinType("Int")
				Else If declarator And declarator.callableType Then
					symbol.declaredType = ResolveCallable(declarator.callableType, symbol.containingScope)
				Else If declarator And declarator.declaredType Then
					symbol.declaredType = Resolve(declarator.declaredType, symbol.containingScope)
					If declarator.staticArrayBound Then symbol.declaredType = MakeStaticArray(symbol.declaredType, declarator.staticArrayBound)
					If HasImplicitBaseType(declarator.declaredType) Then ReportMissingSuperStrictType(symbol)
				Else If declarator Then
					DefaultUntypedSymbol(symbol)
				End If
			Case SYMBOL_PARAMETER
				If symbol.declaredType Then Return
				Local parameter:TParameterSyntax = TParameterSyntax(symbol.declaration)
				If parameter And parameter.callableType Then
					symbol.declaredType = ResolveCallableParameter(parameter, symbol.containingScope)
				Else If parameter And parameter.declaredType Then
					symbol.declaredType = Resolve(parameter.declaredType, symbol.containingScope)
					If parameter.staticArrayBound Then symbol.declaredType = MakeStaticArray(symbol.declaredType, parameter.staticArrayBound)
					If HasImplicitBaseType(parameter.declaredType) Then ReportMissingSuperStrictType(symbol)
				End If
			Case SYMBOL_CATCH_PARAMETER
				Local catchClause:TCatchClauseSyntax = TCatchClauseSyntax(symbol.declaration)
				If catchClause And catchClause.declaredType Then symbol.declaredType = Resolve(catchClause.declaredType, symbol.containingScope)
		End Select
	End Method

	Method BindRoutineDeclaration(symbol:TSymbol, routine:TRoutineDeclarationSyntax, scope:TScope)
		Local signature:TRoutineSignatureSyntax = routine.signature
		symbol.nativeStringReturnEncoding = NativeStringEncoding(signature.returnType)
		If routine.isMethod And symbol.name.ToLower() = "new" Then
			symbol.declaredType = model.BuiltinType("Void")
		Else If signature.callableReturnType Then
			symbol.declaredType = ResolveCallable(signature.callableReturnType, scope)
		Else If signature.returnType Then
			symbol.declaredType = Resolve(signature.returnType, scope)
			If HasImplicitBaseType(signature.returnType) Then ReportMissingSuperStrictType(symbol)
		Else If SourceModeForSymbol(symbol) = SOURCE_MODE_STRICT Then
			symbol.declaredType = model.BuiltinType("Int")
		Else
			symbol.declaredType = model.BuiltinType("Void")
		End If
		symbol.parameterTypes = New TSemanticType[signature.parameters.length]
		symbol.parameters = New TSemanticParameter[signature.parameters.length]
		For Local index:Int = 0 Until signature.parameters.length
			If signature.parameters[index].callableType Then
				symbol.parameterTypes[index] = ResolveCallableParameter(signature.parameters[index], scope)
			Else If signature.parameters[index].declaredType Then
				symbol.parameterTypes[index] = Resolve(signature.parameters[index].declaredType, scope)
				If signature.parameters[index].staticArrayBound Then symbol.parameterTypes[index] = MakeStaticArray(symbol.parameterTypes[index], signature.parameters[index].staticArrayBound)
				If HasImplicitBaseType(signature.parameters[index].declaredType) Then ReportMissingSuperStrictType(model.DeclaredSymbol(signature.parameters[index]))
			Else
				symbol.parameterTypes[index] = model.BuiltinType("Int")
				ReportMissingSuperStrictType(model.DeclaredSymbol(signature.parameters[index]))
			End If
			Local parameterSymbol:TSymbol = model.DeclaredSymbol(signature.parameters[index])
			If parameterSymbol Then
				parameterSymbol.declaredType = symbol.parameterTypes[index]
				parameterSymbol.parameterMode = ParameterMode(signature.parameters[index])
			End If
			Local parameterInfo:TSemanticParameter = New TSemanticParameter
			parameterInfo.symbol = parameterSymbol
			parameterInfo.semanticType = symbol.parameterTypes[index]
			parameterInfo.passingMode = ParameterMode(signature.parameters[index])
			parameterInfo.nativeStringEncoding = NativeStringEncoding(signature.parameters[index])
			parameterInfo.optional = signature.parameters[index].defaultValue <> Null
			symbol.parameters[index] = parameterInfo
		Next
		BindRoutineConstraints(symbol, signature, scope)
	End Method

	Method DefaultUntypedSymbol(symbol:TSymbol)
		If Not symbol Then Return
		' Strict retains the language's traditional implicit Int type. In
		' SuperStrict we report the omitted annotation but keep Int as a
		' recovery type so later binding does not produce cascading errors.
		symbol.declaredType = model.BuiltinType("Int")
		ReportMissingSuperStrictType(symbol)
	End Method

	Method ReportMissingSuperStrictType(symbol:TSymbol)
		If Not symbol Or symbol.isImported Or SourceModeForSymbol(symbol) <> SOURCE_MODE_SUPERSTRICT Then Return
		AddDiagnostic("BMX3103", symbol.KindName() + " '" + symbol.name + "' requires an explicit type in SuperStrict code.", symbol.nameToken.span)
	End Method

	Method SourceModeForSymbol:Int(symbol:TSymbol)
		If symbol Then Return SourceModeForPath(symbol.originPath)
		Return SourceModeForPath(currentPath)
	End Method

	Method SourceModeForPath:Int(path:String)
		If model.snapshot Then
			For Local document:TSourceDocumentModel = EachIn model.snapshot.documents
				If document And SamePath(document.path, path) Then Return document.effectiveSourceMode
			Next
		End If
		If model.syntaxTree And model.syntaxTree.root Then Return model.syntaxTree.root.sourceMode
		Return SOURCE_MODE_STRICT
	End Method

	Function SamePath:Int(left:String, right:String)
		Return left.Replace("\\", "/") = right.Replace("\\", "/")
	End Function

	Function MakeStaticArray:TStaticArraySemanticType(elementType:TSemanticType, bound:TStaticArrayBoundSyntax)
		Local result:TStaticArraySemanticType = New TStaticArraySemanticType
		result.kind = SEMANTIC_TYPE_STATIC_ARRAY
		result.elementType = elementType
		result.boundSyntax = bound
		Return result
	End Function

	Method ResolveCallable:TSemanticType(syntax:TCallableTypeSyntax, scope:TScope, reportMissingParameterTypes:Int = True)
		If Not syntax Then Return Null
		If Not TCallingConventionResolver.IsRecognized(syntax.callingConventionToken) Then
			AddDiagnostic("BMX3119", "Unrecognized calling convention '" + TCallingConventionResolver.WrittenName(syntax.callingConventionToken) + "'.", syntax.callingConventionToken.span)
		End If
		Local callable:TCallableSemanticType = New TCallableSemanticType
		callable.kind = SEMANTIC_TYPE_CALLABLE
		Local targetPlatform:String
		If model And model.snapshot And model.snapshot.options Then targetPlatform = model.snapshot.options.targetPlatform
		callable.callingConvention = TCallingConventionResolver.Resolve(syntax.callingConventionToken, targetPlatform)
		If syntax.returnType Then
			callable.returnType = Resolve(syntax.returnType, scope)
		Else If SourceModeForPath(currentPath) = SOURCE_MODE_STRICT Then
			' Traditional Strict callable declarations use the same implicit Int
			' return convention as routines. SuperStrict omission means Void.
			callable.returnType = model.BuiltinType("Int")
		Else
			callable.returnType = model.BuiltinType("Void")
		End If
		callable.parameterTypes = New TSemanticType[syntax.parameters.length]
		callable.parameterModes = New Int[syntax.parameters.length]
		For Local index:Int = 0 Until syntax.parameters.length
			If syntax.parameters[index].callableType Then
				callable.parameterTypes[index] = ResolveCallable(syntax.parameters[index].callableType, scope)
			Else If syntax.parameters[index].declaredType Then
				callable.parameterTypes[index] = Resolve(syntax.parameters[index].declaredType, scope)
				If syntax.parameters[index].staticArrayBound Then callable.parameterTypes[index] = MakeStaticArray(callable.parameterTypes[index], syntax.parameters[index].staticArrayBound)
			Else
				If SourceModeForPath(currentPath) = SOURCE_MODE_SUPERSTRICT Then
					Local parameterName:String = "<missing>"
					Local parameterSpan:TSourceSpan = syntax.parameters[index].span
					If syntax.parameters[index].nameToken Then
						parameterName = syntax.parameters[index].nameToken.text
						parameterSpan = syntax.parameters[index].nameToken.span
					End If
					callable.parameterTypes[index] = ErrorType(parameterName)
					If reportMissingParameterTypes Then AddDiagnostic("BMX3103", "Callable parameter '" + parameterName + "' requires an explicit type in SuperStrict code.", parameterSpan)
				Else
					callable.parameterTypes[index] = model.BuiltinType("Int")
				End If
			End If
			callable.parameterModes[index] = ParameterMode(syntax.parameters[index])
		Next
		Local result:TSemanticType = callable
		For Local suffix:TTypeSuffixSyntax = EachIn syntax.suffixes
			If suffix.suffixKind = TYPE_SUFFIX_POINTER Then
				Local pointerType:TPointerSemanticType = New TPointerSemanticType
				pointerType.kind = SEMANTIC_TYPE_POINTER
				pointerType.elementType = result
				result = pointerType
			Else If suffix.suffixKind = TYPE_SUFFIX_ARRAY Then
				Local arrayType:TArraySemanticType = New TArraySemanticType
				arrayType.kind = SEMANTIC_TYPE_ARRAY
				arrayType.elementType = result
				arrayType.rank = suffix.rank
				result = arrayType
			End If
		Next
		Return result
	End Method

	Method ResolveCallableParameter:TSemanticType(parameter:TParameterSyntax, scope:TScope)
		If Not parameter Then Return Null
		Local resolved:TSemanticType = ResolveCallable(parameter.callableType, scope)
		If Not parameter.callableType Or parameter.callableType.returnType Or Not parameter.defaultValue Then Return resolved
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(parameter.defaultValue)
		If Not name Or Not name.nameToken Then Return resolved
		Local inferred:TCallableSemanticType = TCallableSemanticType(resolved)
		If Not inferred Then Return resolved
		For Local candidate:TSymbol = EachIn scope.Lookup(name.nameToken.text)
			If candidate.kind <> SYMBOL_ROUTINE Then Continue
			BindSymbol(candidate)
			If candidate.parameterTypes.length <> inferred.parameterTypes.length Or Not candidate.declaredType Then Continue
			Local compatible:Int = True
			For Local index:Int = 0 Until inferred.parameterTypes.length
				If Not candidate.parameterTypes[index] Or Not inferred.parameterTypes[index] Or candidate.parameterTypes[index].DisplayName().ToLower() <> inferred.parameterTypes[index].DisplayName().ToLower() Then compatible = False; Exit
			Next
			If compatible Then
				inferred.returnType = candidate.declaredType
				Return inferred
			End If
		Next
		Return resolved
	End Method

	Method BindRoutineConstraints(symbol:TSymbol, signature:TRoutineSignatureSyntax, scope:TScope)
		Local constraints:TList = New TList
		For Local syntax:TGenericConstraintSyntax = EachIn signature.constraints
			Local info:TGenericConstraintInfo = New TGenericConstraintInfo
			info.syntax = syntax
			Local candidates:TSymbol[] = scope.LookupLocal(syntax.parameterNameToken.text)
			For Local candidate:TSymbol = EachIn candidates
				If candidate.kind = SYMBOL_TYPE_PARAMETER Then
					info.parameterSymbol = candidate
					Exit
				End If
			Next
			If Not info.parameterSymbol Then AddDiagnostic("BMX3110", "Generic constraint refers to undeclared routine type parameter '" + syntax.parameterNameToken.text + "'.", syntax.parameterNameToken.span)
			info.bounds = New TSemanticType[syntax.constraintTypes.length]
			For Local index:Int = 0 Until syntax.constraintTypes.length
				info.bounds[index] = Resolve(syntax.constraintTypes[index], scope)
			Next
			constraints.AddLast(info)
		Next
		symbol.genericConstraints = ConstraintsToArray(constraints)
	End Method

	Method BindImportedSymbol(symbol:TSymbol)
		Local record:TInterfaceRecord = symbol.interfaceRecord
		If Not record Then Return
		Select symbol.kind
			Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE
				Local typeScope:TScope = symbol.memberScope
				If Not typeScope Then typeScope = symbol.containingScope
				If record.baseTypeSyntax Then Resolve(record.baseTypeSyntax, typeScope)
				For Local syntax:TTypeReferenceSyntax = EachIn record.implementedTypeSyntax
					If syntax Then Resolve(syntax, typeScope)
				Next
				If record.typeHeaderSyntax Then
					For Local constraint:TGenericConstraintSyntax = EachIn record.typeHeaderSyntax.constraints
						For Local constraintType:TTypeReferenceSyntax = EachIn constraint.constraintTypes
							If constraintType Then Resolve(constraintType, typeScope)
						Next
					Next
				End If
			Case SYMBOL_ENUM
				Local underlyingType:TSemanticType = model.BuiltinType("Int")
				If record.baseTypeSyntax Then underlyingType = Resolve(record.baseTypeSyntax, symbol.containingScope)
				EnsureEnumBuiltins(symbol, underlyingType)
			Case SYMBOL_ROUTINE
				Local signature:TRoutineSignatureSyntax = record.routineSignature
				If Not signature Then Return
				symbol.nativeStringReturnEncoding = NativeStringEncoding(signature.returnType)
				Local routineScope:TScope = symbol.memberScope
				If Not routineScope Then routineScope = symbol.containingScope
				If signature.callableReturnType Then
					symbol.declaredType = ResolveCallable(signature.callableReturnType, routineScope)
				Else If signature.returnType Then
					symbol.declaredType = Resolve(signature.returnType, routineScope)
				Else
					symbol.declaredType = model.BuiltinType("Void")
				End If
				symbol.parameterTypes = New TSemanticType[signature.parameters.length]
				symbol.parameters = New TSemanticParameter[signature.parameters.length]
				For Local index:Int = 0 Until signature.parameters.length
					If signature.parameters[index].callableType Then
						symbol.parameterTypes[index] = ResolveCallable(signature.parameters[index].callableType, routineScope)
					Else If signature.parameters[index].declaredType Then
						symbol.parameterTypes[index] = Resolve(signature.parameters[index].declaredType, routineScope)
						If signature.parameters[index].staticArrayBound Then symbol.parameterTypes[index] = MakeStaticArray(symbol.parameterTypes[index], signature.parameters[index].staticArrayBound)
					Else
						symbol.parameterTypes[index] = model.BuiltinType("Int")
					End If
					Local parameterSymbol:TSymbol = model.DeclaredSymbol(signature.parameters[index])
					If parameterSymbol Then
						parameterSymbol.declaredType = symbol.parameterTypes[index]
						parameterSymbol.parameterMode = ParameterMode(signature.parameters[index])
					End If
					Local parameterInfo:TSemanticParameter = New TSemanticParameter
					parameterInfo.symbol = parameterSymbol
					parameterInfo.semanticType = symbol.parameterTypes[index]
					parameterInfo.passingMode = ParameterMode(signature.parameters[index])
					parameterInfo.nativeStringEncoding = NativeStringEncoding(signature.parameters[index])
					parameterInfo.optional = signature.parameters[index].defaultValue <> Null
					symbol.parameters[index] = parameterInfo
				Next
				BindRoutineConstraints(symbol, signature, routineScope)
			Case SYMBOL_FIELD, SYMBOL_GLOBAL, SYMBOL_CONST
				If record.callableTypeSyntax Then
					symbol.declaredType = ResolveCallable(record.callableTypeSyntax, symbol.containingScope)
				Else If record.declaredTypeSyntax Then
					symbol.declaredType = Resolve(record.declaredTypeSyntax, symbol.containingScope)
					If record.isStaticArray And record.staticArrayBound Then symbol.declaredType = MakeStaticArray(symbol.declaredType, record.staticArrayBound)
				Else
					symbol.declaredType = model.BuiltinType("Int")
				End If
		End Select
	End Method

	Method EnsureEnumBuiltins(enumSymbol:TSymbol, underlyingType:TSemanticType)
		If Not enumSymbol Or Not enumSymbol.memberScope Then Return
		Local enumArray:TArraySemanticType = New TArraySemanticType
		enumArray.kind = SEMANTIC_TYPE_ARRAY
		enumArray.elementType = enumSymbol.declaredType
		enumArray.rank = 1
		EnsureEnumRoutine(enumSymbol, "Ordinal", underlyingType, Null, Null, Null, True)
		EnsureEnumRoutine(enumSymbol, "ToString", model.BuiltinType("String"), Null, Null, Null, True)
		EnsureEnumRoutine(enumSymbol, "Values", enumArray)
		EnsureEnumRoutine(enumSymbol, "TryConvert", model.BuiltinType("Int"), [underlyingType, enumSymbol.declaredType], ["value", "result"], [PARAMETER_PASS_VALUE, PARAMETER_PASS_VAR])
		EnsureEnumRoutine(enumSymbol, "FromString", enumSymbol.declaredType, [model.BuiltinType("String")], ["name"])
	End Method

	Method EnsureEnumRoutine(enumSymbol:TSymbol, name:String, returnType:TSemanticType, parameterTypes:TSemanticType[] = Null, parameterNames:String[] = Null, parameterModes:Int[] = Null, isMethod:Int = False)
		If enumSymbol.memberScope.LookupLocal(name).length Then Return
		If Not parameterTypes Then parameterTypes = New TSemanticType[0]
		Local routineSymbol:TSymbol = New TSymbol
		routineSymbol.kind = SYMBOL_ROUTINE
		routineSymbol.name = name
		routineSymbol.normalizedName = name.ToLower()
		routineSymbol.containingScope = enumSymbol.memberScope
		routineSymbol.declaredType = returnType
		routineSymbol.parameterTypes = parameterTypes
		routineSymbol.parameters = New TSemanticParameter[parameterTypes.length]
		Local declaration:TRoutineDeclarationSyntax = New TRoutineDeclarationSyntax
		declaration.isMethod = isMethod
		routineSymbol.declaration = declaration
		For Local index:Int = 0 Until parameterTypes.length
			Local parameter:TSemanticParameter = New TSemanticParameter
			parameter.semanticType = parameterTypes[index]
			If parameterModes And index < parameterModes.length Then parameter.passingMode = parameterModes[index]
			Local parameterSymbol:TSymbol = New TSymbol
			parameterSymbol.kind = SYMBOL_PARAMETER
			If parameterNames And index < parameterNames.length Then parameterSymbol.name = parameterNames[index] Else parameterSymbol.name = "arg" + index
			parameterSymbol.normalizedName = parameterSymbol.name.ToLower()
			parameterSymbol.declaredType = parameterTypes[index]
			parameterSymbol.parameterMode = parameter.passingMode
			parameterSymbol.containingScope = enumSymbol.memberScope
			parameter.symbol = parameterSymbol
			routineSymbol.parameters[index] = parameter
		Next
		routineSymbol.isImported = enumSymbol.isImported
		routineSymbol.originModule = enumSymbol.originModule
		routineSymbol.originPath = enumSymbol.originPath
		routineSymbol.originLine = enumSymbol.originLine
		routineSymbol.originColumn = enumSymbol.originColumn
		enumSymbol.memberScope.AddSymbol(routineSymbol)
	End Method

	Method BindImportedChildSymbol(symbol:TSymbol)
		If symbol.declaredType Then Return
		Local parameter:TParameterSyntax = TParameterSyntax(symbol.declaration)
		If Not parameter Then Return
		If parameter.callableType Then
			symbol.declaredType = ResolveCallable(parameter.callableType, symbol.containingScope)
		Else If parameter.declaredType Then
			symbol.declaredType = Resolve(parameter.declaredType, symbol.containingScope)
			If parameter.staticArrayBound Then symbol.declaredType = MakeStaticArray(symbol.declaredType, parameter.staticArrayBound)
		Else
			symbol.declaredType = model.BuiltinType("Int")
		End If
		symbol.parameterMode = ParameterMode(parameter)
	End Method

	Function ParameterMode:Int(parameter:TParameterSyntax)
		If parameter And parameter.varToken Then Return PARAMETER_PASS_VAR
		Return PARAMETER_PASS_VALUE
	End Function

	Function NativeStringEncoding:Int(parameter:TParameterSyntax)
		If Not parameter Or parameter.callableType Or Not parameter.declaredType Then Return NATIVE_STRING_NONE
		Return NativeStringEncoding(parameter.declaredType)
	End Function

	Function NativeStringEncoding:Int(declaredType:TTypeReferenceSyntax)
		If Not declaredType Then Return NATIVE_STRING_NONE
		If Not declaredType.markerToken Then Return NATIVE_STRING_NONE
		Local marker:String = declaredType.markerToken.text.ToLower()
		If marker = "$z" Then Return NATIVE_STRING_UTF8
		If marker = "$w" Then Return NATIVE_STRING_UTF16
		If marker <> "$" Or declaredType.nameTokens.length <> 1 Then Return NATIVE_STRING_NONE
		Select declaredType.nameTokens[0].text.ToLower()
			Case "z" Return NATIVE_STRING_UTF8
			Case "w" Return NATIVE_STRING_UTF16
		End Select
		Return NATIVE_STRING_NONE
	End Function

	Method BindTypeDeclaration(declaration:TTypeDeclarationSyntax, scope:TScope)
		If Not declaration Or Not declaration.header Then Return
		For Local baseType:TTypeReferenceSyntax = EachIn declaration.header.extendsTypes
			Resolve(baseType, scope)
		Next
		For Local interfaceType:TTypeReferenceSyntax = EachIn declaration.header.implementedTypes
			Resolve(interfaceType, scope)
		Next
		For Local constraint:TGenericConstraintSyntax = EachIn declaration.header.constraints
			For Local constraintType:TTypeReferenceSyntax = EachIn constraint.constraintTypes
				Resolve(constraintType, scope)
			Next
		Next
	End Method

	Method Resolve:TSemanticType(syntax:TTypeReferenceSyntax, scope:TScope)
		If Not syntax Then Return Null
		Local existing:TSemanticType = model.TypeOf(syntax)
		If existing Then Return existing

		Local result:TSemanticType
		Local segments:String[] = NameSegments(syntax)
		If segments.length = 1 And segments[0].ToLower() = "closure" Then
			result = ResolveClosure(syntax, scope)
		End If
		' ':' is the source named-type introducer and '/' is bcc's compact
		' interface marker for an enum. Both retain the following type name.
		If Not result And syntax.markerToken And syntax.markerToken.text <> ":" And syntax.markerToken.text <> "/" Then
			result = MarkerType(syntax.markerToken.text)
		Else If Not result
			' Traditional Strict declarations may carry only a pointer/array
			' suffix after the identifier (for example, `values[]`).  The
			' omitted base type is Int; the suffix still determines the final
			' compound type.
			If Not segments.length And Not syntax.markerToken Then result = model.BuiltinType("Int")
			If segments.length = 1 Then result = model.BuiltinType(segments[0])
			If Not result Then result = ResolveNamedType(segments, syntax, scope)
		End If
		If Not result Then result = ErrorType(WrittenName(syntax))
		If TBuiltinSemanticType(result) And syntax.genericArguments.length Then
			For Local argument:TTypeReferenceSyntax = EachIn syntax.genericArguments
				Resolve(argument, scope)
			Next
			AddDiagnostic("BMX3102", "Type '" + result.DisplayName() + "' expects 0 type argument(s), but " + syntax.genericArguments.length + " were supplied.", syntax.span)
		End If

		If syntax.suffixes.length Then
			For Local suffix:TTypeSuffixSyntax = EachIn syntax.suffixes
				If suffix.suffixKind = TYPE_SUFFIX_POINTER Then
					Local pointerType:TPointerSemanticType = New TPointerSemanticType
					pointerType.kind = SEMANTIC_TYPE_POINTER
					pointerType.elementType = result
					result = pointerType
				Else If suffix.suffixKind = TYPE_SUFFIX_ARRAY Then
					Local arrayType:TArraySemanticType = New TArraySemanticType
					arrayType.kind = SEMANTIC_TYPE_ARRAY
					arrayType.elementType = result
					arrayType.rank = suffix.rank
					result = arrayType
				End If
			Next
		Else
			' Compatibility for syntax produced by clients predating ordered suffixes.
			For Local index:Int = 0 Until syntax.pointerTokens.length
				Local pointerType:TPointerSemanticType = New TPointerSemanticType
				pointerType.kind = SEMANTIC_TYPE_POINTER
				pointerType.elementType = result
				result = pointerType
			Next
			For Local rank:Int = EachIn syntax.arrayRanks
				Local arrayType:TArraySemanticType = New TArraySemanticType
				arrayType.kind = SEMANTIC_TYPE_ARRAY
				arrayType.elementType = result
				arrayType.rank = rank
				result = arrayType
			Next
		End If
		model.typeMap.Insert(syntax, result)
		Return result
	End Method

	Method ResolveClosure:TSemanticType(syntax:TTypeReferenceSyntax, scope:TScope)
		If SourceModeForPath(currentPath) <> SOURCE_MODE_SUPERSTRICT Then AddDiagnostic("BMX3120", "Closure types require SuperStrict mode.", syntax.span)
		If Not syntax.closureSignature Then
			AddDiagnostic("BMX3121", "The compiler-intrinsic Closure type requires an explicit signature, for example Closure<Int(value:Int)> or Closure<()>.", syntax.span)
			Return ErrorType("Closure")
		End If
		For Local parameter:TParameterSyntax = EachIn syntax.closureSignature.parameters
			If Not parameter.declaredType And Not parameter.callableType Then AddDiagnostic("BMX3122", "Closure parameters require an explicit name and type.", parameter.span)
			If parameter.defaultValue Then AddDiagnostic("BMX3123", "Closure signatures cannot declare default parameter values.", parameter.defaultValue.span)
		Next
		Local signature:TCallableSemanticType = TCallableSemanticType(ResolveCallable(syntax.closureSignature, scope, False))
		If Not signature Then Return ErrorType("Closure")
		If signature.callingConvention <> CALLING_CONVENTION_C Then AddDiagnostic("BMX3124", "Closure signatures cannot specify a native calling convention.", syntax.span)
		Local closure:TClosureSemanticType = New TClosureSemanticType
		closure.kind = SEMANTIC_TYPE_CLOSURE
		closure.signature = signature
		closure.parameterNames = New String[syntax.closureSignature.parameters.length]
		For Local index:Int = 0 Until syntax.closureSignature.parameters.length
			Local parameter:TParameterSyntax = syntax.closureSignature.parameters[index]
			If parameter And parameter.nameToken Then closure.parameterNames[index] = parameter.nameToken.text Else closure.parameterNames[index] = "arg" + index
		Next
		Return closure
	End Method

	Function HasImplicitBaseType:Int(syntax:TTypeReferenceSyntax)
		Return syntax And Not syntax.markerToken And Not syntax.nameTokens.length And syntax.suffixes.length
	End Function

	Method ResolveNamedType:TSemanticType(segments:String[], syntax:TTypeReferenceSyntax, scope:TScope)
		If segments.length = 0 Then
			ReportUnresolved(syntax, WrittenName(syntax))
			Return ErrorType(WrittenName(syntax))
		End If
		Local firstTypeIndex:Int
		Local candidates:TSymbol[]
		Local importedScope:TScope
		For Local count:Int = segments.length - 1 To 1 Step -1
			Local moduleName:String = JoinedSegments(segments, count)
			importedScope = model.ImportedScope(moduleName)
			If importedScope Then
				firstTypeIndex = count
				candidates = LocalTypeCandidates(importedScope, segments[firstTypeIndex])
				Exit
			End If
		Next
		If Not importedScope Then candidates = LookupTypeCandidates(scope, segments[0])
		If candidates.length = 0 Then
			ReportUnresolved(syntax, WrittenName(syntax))
			Return ErrorType(WrittenName(syntax))
		End If
		If candidates.length > 1 Then
			AddDiagnostic("BMX3101", AmbiguousTypeMessage(segments[0], candidates), syntax.span)
			Return ErrorType(WrittenName(syntax))
		End If
		Local symbol:TSymbol = candidates[0]
		For Local index:Int = firstTypeIndex + 1 Until segments.length
			Local memberScope:TScope = symbol.memberScope
			If Not memberScope And symbol.declaration Then memberScope = model.ScopeFor(symbol.declaration)
			If Not memberScope Then
				ReportUnresolved(syntax, WrittenName(syntax))
				Return ErrorType(WrittenName(syntax))
			End If
			candidates = LocalTypeCandidates(memberScope, segments[index])
			If candidates.length <> 1 Then
				If candidates.length > 1 Then AddDiagnostic("BMX3101", AmbiguousTypeMessage(WrittenName(syntax), candidates), syntax.span) Else ReportUnresolved(syntax, WrittenName(syntax))
				Return ErrorType(WrittenName(syntax))
			End If
			symbol = candidates[0]
		Next
		If symbol.kind = SYMBOL_TYPE_PARAMETER Then
			If syntax.genericArguments.length Then AddDiagnostic("BMX3102", "Type parameter '" + symbol.name + "' cannot have type arguments.", syntax.span)
			Return symbol.declaredType
		End If
		Local result:TNamedSemanticType = New TNamedSemanticType
		result.kind = SEMANTIC_TYPE_NAMED
		result.symbol = symbol
		result.typeArguments = New TSemanticType[syntax.genericArguments.length]
		For Local index:Int = 0 Until syntax.genericArguments.length
			result.typeArguments[index] = Resolve(syntax.genericArguments[index], scope)
		Next
		Local expectedArity:Int = GenericArity(symbol)
		If expectedArity >= 0 And syntax.genericArguments.length And syntax.genericArguments.length <> expectedArity Then
			AddDiagnostic("BMX3102", "Type '" + symbol.name + "' expects " + expectedArity + " type argument(s), but " + syntax.genericArguments.length + " were supplied.", syntax.span)
		End If
		Return result
	End Method

	Method MarkerType:TSemanticType(marker:String)
		Select marker
			Case "@" Return model.BuiltinType("Byte")
			Case "@@" Return model.BuiltinType("Short")
			Case "%" Return model.BuiltinType("Int")
			Case "%%" Return model.BuiltinType("Long")
			Case "|" Return model.BuiltinType("UInt")
			Case "||" Return model.BuiltinType("ULong")
			Case "#" Return model.BuiltinType("Float")
			Case "!" Return model.BuiltinType("Double")
			Case "$" Return model.BuiltinType("String")
			Case "%z" Return model.BuiltinType("Size_T")
			Case "%v" Return model.BuiltinType("LongInt")
			Case "%e" Return model.BuiltinType("ULongInt")
			Case "%w" Return model.BuiltinType("WParam")
			Case "%x" Return model.BuiltinType("LParam")
			Case "%j" Return model.BuiltinType("Int128")
			Case "!k" Return model.BuiltinType("Float128")
			Case "!m" Return model.BuiltinType("Double128")
			Case "!h" Return model.BuiltinType("Float64")
		End Select
		Return Null
	End Method

	Method LookupTypeCandidates:TSymbol[](scope:TScope, name:String)
		While scope
			Local candidates:TSymbol[] = LocalTypeCandidates(scope, name)
			If candidates.length Then Return candidates
			If scope = model.globalScope Then
				candidates = ImportedTypeCandidates(name, True)
				If candidates.length Then Return candidates
				candidates = ImportedTypeCandidates(name, False)
				If candidates.length Then Return candidates
			End If
			scope = scope.parent
		Wend
		Return New TSymbol[0]
	End Method

	Method ImportedTypeCandidates:TSymbol[](name:String, direct:Int)
		Local cache:TMap = transitiveTypeCandidates
		If direct Then cache = directTypeCandidates
		Local key:String = name.ToLower()
		Local cached:TTypeCandidateCacheEntry = TTypeCandidateCacheEntry(cache.ValueForKey(key))
		If cached Then Return cached.symbols

		Local result:TList = New TList
		If direct Then
			For Local importedScope:TScope = EachIn model.directImportedScopes
				For Local symbol:TSymbol = EachIn LocalTypeCandidates(importedScope, name)
					If Not TSymbolAccessibility.IsAccessible(symbol, model.globalScope, model) Then Continue
					result.AddLast(symbol)
				Next
			Next
		Else
			For Local importedScope:TScope = EachIn model.importedScopes
				If IsDirectImportedScope(importedScope) Then Continue
				For Local symbol:TSymbol = EachIn LocalTypeCandidates(importedScope, name)
					If Not TSymbolAccessibility.IsAccessible(symbol, model.globalScope, model) Then Continue
					result.AddLast(symbol)
				Next
			Next
		End If
		cached = New TTypeCandidateCacheEntry
		cached.symbols = SymbolsToArray(result)
		cache.Insert(key, cached)
		Return cached.symbols
	End Method

	Method IsDirectImportedScope:Int(scope:TScope)
		Return directImportedScopeSet.Contains(scope)
	End Method

	Method LocalTypeCandidates:TSymbol[](scope:TScope, name:String)
		Local symbols:TSymbol[] = scope.LookupLocal(name)
		Local count:Int
		For Local symbol:TSymbol = EachIn symbols
			If IsSourceTypeCandidate(symbol) Then count :+ 1
		Next
		If count = symbols.length Then Return symbols
		Local result:TSymbol[] = New TSymbol[count]
		Local index:Int
		For Local symbol:TSymbol = EachIn symbols
			If Not IsSourceTypeCandidate(symbol) Then Continue
			result[index] = symbol
			index :+ 1
		Next
		Return result
	End Method

	Function IsSourceTypeCandidate:Int(symbol:TSymbol)
		If Not symbol Or symbol.NamespaceKind() <> SYMBOL_NAMESPACE_TYPE Then Return False
		' Production bcc publishes private gimpl copies for linker/code-generation
		' purposes. They can share the canonical generic declaration's source name,
		' but must never become a distinct source-level type identity.
		Return Not (symbol.interfaceRecord And symbol.interfaceRecord.externalName.ToLower().Contains("|gimpl_"))
	End Function

	Function AmbiguousTypeMessage:String(name:String, candidates:TSymbol[])
		Local message:String = "Type name '" + name + "' is ambiguous. Candidates:"
		For Local symbol:TSymbol = EachIn candidates
			message :+ "~n  "
			If symbol.originModule.length Then message :+ symbol.originModule + "."
			message :+ symbol.name
			If symbol.originPath.length Then
				message :+ " (" + symbol.originPath
				If symbol.originLine >= 0 Then message :+ ":" + (symbol.originLine + 1)
				message :+ ")"
			End If
		Next
		Return message
	End Function

	Method ReportUnresolved(syntax:TTypeReferenceSyntax, name:String)
		If Not options.reportUnresolvedTypes Then Return
		Local diagnosticName:String = name
		If diagnosticName.StartsWith(":") Or diagnosticName.StartsWith("/") Then diagnosticName = diagnosticName[1..]
		Local diagnosticSpan:TSourceSpan = syntax.span
		If syntax.nameTokens.length Then
			Local first:TSyntaxToken = syntax.nameTokens[0]
			Local last:TSyntaxToken = syntax.nameTokens[syntax.nameTokens.length - 1]
			diagnosticSpan = TSourceSpan.Create(first.span.start, last.span.EndOffset() - first.span.start)
		End If
		AddDiagnostic("BMX3100", "Type '" + diagnosticName + "' could not be resolved in the available scopes.", diagnosticSpan)
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan)
		diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span, currentPath))
	End Method

	Function GenericArity:Int(symbol:TSymbol)
		If symbol.isImported Then Return symbol.genericArity
		If symbol.kind = SYMBOL_ROUTINE Then Return symbol.genericArity
		Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
		If declaration And declaration.header Then Return declaration.header.genericParameters.length
		Return 0
	End Function

	Function ConstraintsToArray:TGenericConstraintInfo[](list:TList)
		Local result:TGenericConstraintInfo[] = New TGenericConstraintInfo[list.Count()]
		Local index:Int
		For Local value:TGenericConstraintInfo = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function JoinedSegments:String(segments:String[], count:Int)
		Local result:String
		For Local index:Int = 0 Until count
			If index Then result :+ "."
			result :+ segments[index]
		Next
		Return result
	End Function

	Function NameSegments:String[](syntax:TTypeReferenceSyntax)
		Local result:String[]
		For Local token:TSyntaxToken = EachIn syntax.nameTokens
			If token.text <> "." Then result :+ [token.text]
		Next
		Return result
	End Function

	Function WrittenName:String(syntax:TTypeReferenceSyntax)
		Local result:String
		If syntax.markerToken Then result :+ syntax.markerToken.text
		For Local token:TSyntaxToken = EachIn syntax.nameTokens
			result :+ token.text
		Next
		Return result
	End Function

	Function ErrorType:TErrorSemanticType(name:String)
		Local result:TErrorSemanticType = New TErrorSemanticType
		result.kind = SEMANTIC_TYPE_ERROR
		result.writtenName = name
		Return result
	End Function

	Function SymbolsToArray:TSymbol[](list:TList)
		Local result:TSymbol[] = New TSymbol[list.Count()]
		Local index:Int
		For Local symbol:TSymbol = EachIn list
			result[index] = symbol
			index :+ 1
		Next
		Return result
	End Function

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
