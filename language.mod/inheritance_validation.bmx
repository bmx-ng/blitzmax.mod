' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map

Import "type_resolution.bmx"

Type TInterfaceMethodCandidate
	Field routine:TSymbol
	Field ownerType:TNamedSemanticType
	Field selector:String
End Type

Type TInheritanceValidator
	Field model:TSemanticModel
	Field diagnostics:TList = New TList
	Field visitStates:TMap = New TMap
	Field reportedCycles:TMap = New TMap
	Field currentPath:String

	Function Validate:TSemanticModel(model:TSemanticModel)
		Local validator:TInheritanceValidator = New TInheritanceValidator
		validator.model = model
		validator.BuildInformation(model.globalScope)
		validator.ComputeAbstractTypes(model.globalScope)
		validator.ValidateDeclarations(model.globalScope)
		validator.ValidateOverrides(model.globalScope)
		validator.ValidateCycles(model.globalScope)
		validator.ValidateReferences(model.globalScope)
		validator.ValidatePublicContracts(model.globalScope)
		model.diagnostics = MergeDiagnostics(model.diagnostics, DiagnosticsToArray(validator.diagnostics))
		Return model
	End Function

	Method ValidatePublicContracts(scope:TScope)
		' Applications do not publish a module contract. Includes in a module share
		' the root module name and are deliberately covered by this traversal.
		If Not model.moduleName.length Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not IsPublishedContractSymbol(symbol) Then Continue
			Select symbol.kind
				Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE
					Local info:TTypeInheritanceInfo = model.InheritanceInfo(symbol)
					If info Then
						For Local edge:TInheritanceEdge = EachIn info.baseEdges
							ValidatePublicContractType(symbol, edge.semanticType, "base type")
						Next
						For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
							ValidatePublicContractType(symbol, edge.semanticType, "implemented Interface")
						Next
						For Local constraint:TGenericConstraintInfo = EachIn info.constraints
							For Local bound:TSemanticType = EachIn constraint.bounds
								ValidatePublicContractType(symbol, bound, "generic constraint")
							Next
						Next
					End If
				Case SYMBOL_ROUTINE
					ValidatePublicContractType(symbol, symbol.declaredType, "return type")
					For Local parameter:TSemanticParameter = EachIn symbol.parameters
						If parameter Then ValidatePublicContractType(symbol, parameter.semanticType, "parameter type")
					Next
				Case SYMBOL_FIELD, SYMBOL_GLOBAL, SYMBOL_CONST
					ValidatePublicContractType(symbol, symbol.declaredType, "declared type")
			End Select
			For Local constraint:TGenericConstraintInfo = EachIn symbol.genericConstraints
				For Local bound:TSemanticType = EachIn constraint.bounds
					ValidatePublicContractType(symbol, bound, "generic constraint")
				Next
			Next
		Next
		For Local child:TScope = EachIn scope.children
			ValidatePublicContracts(child)
		Next
	End Method

	Method IsPublishedContractSymbol:Int(symbol:TSymbol)
		If Not symbol Or symbol.isImported Or symbol.visibility <> VISIBILITY_PUBLIC Then Return False
		Select symbol.kind
			Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE, SYMBOL_ENUM, SYMBOL_ROUTINE, SYMBOL_FIELD, SYMBOL_GLOBAL, SYMBOL_CONST
			Default
				Return False
		End Select
		Local owner:TSymbol
		If symbol.containingScope Then owner = symbol.containingScope.owner
		While owner
			If owner.kind = SYMBOL_ROUTINE Then Return False
			If owner.visibility <> VISIBILITY_PUBLIC Or owner.isImported Then Return False
			If owner.containingScope Then owner = owner.containingScope.owner Else owner = Null
		Wend
		Return True
	End Method

	Method ValidatePublicContractType(symbol:TSymbol, semanticType:TSemanticType, role:String)
		Local hidden:TSymbol = HiddenContractType(semanticType)
		If Not hidden Then Return
		currentPath = symbol.originPath
		Local visibility:String = TSymbolAccessibility.VisibilityName(hidden.visibility)
		AddDiagnostic("BMX3217", "Public " + symbol.KindName() + " '" + symbol.QualifiedName() + "' exposes " + visibility + " " + hidden.KindName() + " '" + hidden.QualifiedName() + "' through its " + role + ".", symbol.nameToken.span)
	End Method

	Method HiddenContractType:TSymbol(semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named Then
			If named.symbol And Not named.symbol.isImported And named.symbol.visibility <> VISIBILITY_PUBLIC Then Return named.symbol
			For Local argument:TSemanticType = EachIn named.typeArguments
				Local hidden:TSymbol = HiddenContractType(argument)
				If hidden Then Return hidden
			Next
			Return Null
		End If
		Local pointer:TPointerSemanticType = TPointerSemanticType(semanticType)
		If pointer Then Return HiddenContractType(pointer.elementType)
		Local arrayType:TArraySemanticType = TArraySemanticType(semanticType)
		If arrayType Then Return HiddenContractType(arrayType.elementType)
		Local fixedArray:TStaticArraySemanticType = TStaticArraySemanticType(semanticType)
		If fixedArray Then Return HiddenContractType(fixedArray.elementType)
		Local callable:TCallableSemanticType = TCallableSemanticType(semanticType)
		If callable Then
			Local hidden:TSymbol = HiddenContractType(callable.returnType)
			If hidden Then Return hidden
			For Local parameterType:TSemanticType = EachIn callable.parameterTypes
				hidden = HiddenContractType(parameterType)
				If hidden Then Return hidden
			Next
		End If
		Return Null
	End Method

	Method BuildInformation(scope:TScope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_STRUCT Or symbol.kind = SYMBOL_INTERFACE Then
				currentPath = symbol.originPath
				BuildTypeInformation(symbol)
			End If
		Next
		For Local child:TScope = EachIn scope.children
			BuildInformation(child)
		Next
	End Method

	Method ValidateOverrides(scope:TScope)
		For Local routine:TSymbol = EachIn scope.declaredSymbols
			If routine.kind <> SYMBOL_ROUTINE Or routine.isImported Then Continue
			ValidateInterfaceRoutineKind(routine)
			Local overrideToken:TSyntaxToken = RoutineModifierToken(routine, "override")
			If Not overrideToken Then Continue
			currentPath = routine.originPath
			Local owner:TSymbol
			If routine.containingScope And routine.containingScope.kind = SCOPE_TYPE Then owner = routine.containingScope.owner
			Local overridden:TSymbol
			Local implicitStructObjectOverride:Int
			Local info:TTypeInheritanceInfo = model.InheritanceInfo(owner)
			If info Then
				For Local edge:TInheritanceEdge = EachIn CombinedEdges(info)
					overridden = OverriddenRoutine(routine, edge.semanticType, 0)
					If overridden Then
						Exit
					End If
				Next
			End If
			' Struct values are not Object-derived layouts, but production BlitzMax
			' permits their boxing hooks to override the corresponding Object
			' methods (notably ToString). Keep that compatibility relationship out
			' of the physical Struct inheritance graph.
			If Not overridden And owner And owner.kind = SYMBOL_STRUCT Then
				overridden = OverriddenRoutine(routine, model.BuiltinType("Object"), 0)
				If Not overridden Then implicitStructObjectOverride = IsImplicitStructObjectOverride(routine)
			End If
			If Not overridden And Not implicitStructObjectOverride Then
				AddDiagnostic("BMX3211", "Method '" + routine.name + "' is marked Override but does not override a method from a base type.", overrideToken.span)
			Else If overridden And Not VisibilityIncludes(routine.visibility, overridden.visibility) Then
				AddDiagnostic("BMX3212", "Method '" + routine.name + "' cannot reduce inherited visibility from '" + TSymbolAccessibility.VisibilityName(overridden.visibility) + "' to '" + TSymbolAccessibility.VisibilityName(routine.visibility) + "'.", overrideToken.span)
			End If
		Next
		For Local child:TScope = EachIn scope.children
			ValidateOverrides(child)
		Next
	End Method

	Method IsImplicitStructObjectOverride:Int(routine:TSymbol)
		If Not routine Or routine.name.ToLower() <> "tostring" Or routine.genericArity Or routine.parameterTypes.length Then Return False
		Return SameType(routine.declaredType, model.BuiltinType("String"))
	End Method

	Method ValidateInterfaceRoutineKind(routine:TSymbol)
		Local defaultToken:TSyntaxToken = RoutineModifierToken(routine, "default")
		If Not defaultToken Then Return
		currentPath = routine.originPath
		Local owner:TSymbol
		If routine.containingScope And routine.containingScope.kind = SCOPE_TYPE Then owner = routine.containingScope.owner
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
		If Not owner Or owner.kind <> SYMBOL_INTERFACE Or Not declaration Or Not declaration.isMethod Then
			AddDiagnostic("BMX3213", "Default is valid only on an instance Method declared by an Interface.", defaultToken.span)
			Return
		End If
		If RoutineModifierToken(routine, "abstract") Then
			AddDiagnostic("BMX3214", "Interface method '" + routine.name + "' cannot be both Default and Abstract.", defaultToken.span)
		End If
	End Method

	Method OverriddenRoutine:TSymbol(routine:TSymbol, inheritedType:TSemanticType, depth:Int)
		If depth > 64 Then Return Null
		Local inherited:TNamedSemanticType = RuntimeNamedType(inheritedType)
		If Not inherited Or Not inherited.symbol Or Not inherited.symbol.memberScope Then Return Null
		For Local candidate:TSymbol = EachIn inherited.symbol.memberScope.LookupLocal(routine.name)
			If candidate.kind = SYMBOL_ROUTINE And OverrideSignaturesMatch(routine, candidate, inherited) Then Return candidate
		Next
		Local inheritedInfo:TTypeInheritanceInfo = model.InheritanceInfo(inherited.symbol)
		If Not inheritedInfo Then Return Null
		Local ownerParameters:TSymbol[] = DeclaredTypeParameters(inherited.symbol)
		For Local edge:TInheritanceEdge = EachIn CombinedEdges(inheritedInfo)
			Local nextType:TSemanticType = Substitute(edge.semanticType, ownerParameters, inherited.typeArguments)
			Local candidate:TSymbol = OverriddenRoutine(routine, nextType, depth + 1)
			If candidate Then Return candidate
		Next
		Return Null
	End Method

	Function VisibilityIncludes:Int(candidate:Int, inherited:Int)
		Local candidateMask:Int = VisibilityMask(candidate)
		Local inheritedMask:Int = VisibilityMask(inherited)
		Return (candidateMask & inheritedMask) = inheritedMask
	End Function

	Function VisibilityMask:Int(visibility:Int)
		Select visibility
			Case VISIBILITY_PRIVATE Return %00001
			Case VISIBILITY_PRIVATE_INTERNAL Return %01011
			Case VISIBILITY_PROTECTED Return %00111
			Case VISIBILITY_INTERNAL Return %01011
			Case VISIBILITY_PROTECTED_INTERNAL Return %01111
		End Select
		Return %11111
	End Function

	Method ComputeAbstractTypes(scope:TScope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol.kind <> SYMBOL_TYPE And symbol.kind <> SYMBOL_INTERFACE Then Continue
			If symbol.kind = SYMBOL_INTERFACE Or symbol.isAbstract Or HasAbstractObligation(symbol.declaredType, symbol.declaredType, 0) Then
				model.abstractTypeMap.Insert(symbol, symbol)
			End If
		Next
		For Local child:TScope = EachIn scope.children
			ComputeAbstractTypes(child)
		Next
	End Method

	Method HasAbstractObligation:Int(targetType:TSemanticType, currentType:TSemanticType, depth:Int)
		If depth > 64 Then Return False
		Local current:TNamedSemanticType = RuntimeNamedType(currentType)
		If Not current Or Not current.symbol Or Not current.symbol.memberScope Then Return False
		For Local requirement:TSymbol = EachIn current.symbol.memberScope.declaredSymbols
			If requirement.kind = SYMBOL_ROUTINE And requirement.isAbstract Then
				If requirement.interfaceMethodKind = INTERFACE_METHOD_REABSTRACT Then
					If Not HasConcreteTypeImplementation(targetType, requirement, current, 0) Then Return True
				Else If Not HasConcreteImplementation(targetType, requirement, current, 0) Then
					Return True
				End If
			End If
		Next
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(current.symbol)
		If Not info Then Return False
		Local ownerParameters:TSymbol[] = DeclaredTypeParameters(current.symbol)
		For Local edge:TInheritanceEdge = EachIn CombinedEdges(info)
			Local nextType:TSemanticType = Substitute(edge.semanticType, ownerParameters, current.typeArguments)
			If HasAbstractObligation(targetType, nextType, depth + 1) Then Return True
		Next
		Return False
	End Method

	Method HasConcreteTypeImplementation:Int(searchType:TSemanticType, requirement:TSymbol, requirementOwner:TNamedSemanticType, depth:Int)
		If depth > 64 Then Return False
		Local current:TNamedSemanticType = RuntimeNamedType(searchType)
		If Not current Or Not current.symbol Or current.symbol.kind <> SYMBOL_TYPE Or Not current.symbol.memberScope Then Return False
		For Local candidate:TSymbol = EachIn current.symbol.memberScope.LookupLocal(requirement.name)
			If candidate.kind = SYMBOL_ROUTINE And Not candidate.isAbstract And OverrideSignaturesMatch(candidate, requirement, requirementOwner) Then Return True
		Next
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(current.symbol)
		If Not info Then Return False
		Local ownerParameters:TSymbol[] = DeclaredTypeParameters(current.symbol)
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			Local nextType:TSemanticType = Substitute(edge.semanticType, ownerParameters, current.typeArguments)
			If HasConcreteTypeImplementation(nextType, requirement, requirementOwner, depth + 1) Then Return True
		Next
		Return False
	End Method

	Method HasConcreteImplementation:Int(searchType:TSemanticType, requirement:TSymbol, requirementOwner:TNamedSemanticType, depth:Int)
		If depth > 64 Then Return False
		Local current:TNamedSemanticType = RuntimeNamedType(searchType)
		If Not current Or Not current.symbol Or Not current.symbol.memberScope Then Return False
		For Local candidate:TSymbol = EachIn current.symbol.memberScope.LookupLocal(requirement.name)
			If candidate.kind = SYMBOL_ROUTINE And Not candidate.isAbstract And OverrideSignaturesMatch(candidate, requirement, requirementOwner) Then Return True
		Next
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(current.symbol)
		If Not info Then Return False
		Local ownerParameters:TSymbol[] = DeclaredTypeParameters(current.symbol)
		For Local edge:TInheritanceEdge = EachIn CombinedEdges(info)
			Local nextType:TSemanticType = Substitute(edge.semanticType, ownerParameters, current.typeArguments)
			If HasConcreteImplementation(nextType, requirement, requirementOwner, depth + 1) Then Return True
		Next
		Return False
	End Method

	Method RuntimeNamedType:TNamedSemanticType(value:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then Return named
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If builtin And builtin.runtimeSymbol Then Return TNamedSemanticType(builtin.runtimeSymbol.declaredType)
		Return Null
	End Method

	Method OverrideSignaturesMatch:Int(routine:TSymbol, candidate:TSymbol, inherited:TNamedSemanticType)
		If routine.callingConvention <> candidate.callingConvention Then Return False
		If Not OverrideParametersMatch(routine, candidate, inherited) Then Return False
		Local ownerParameters:TSymbol[] = DeclaredTypeParameters(inherited.symbol)
		Local candidateRoutineParameters:TSymbol[] = DeclaredTypeParameters(candidate)
		Local routineTypeArguments:TSemanticType[] = TypeParameterTypes(DeclaredTypeParameters(routine))
		Local expectedReturn:TSemanticType = Substitute(candidate.declaredType, ownerParameters, inherited.typeArguments)
		expectedReturn = Substitute(expectedReturn, candidateRoutineParameters, routineTypeArguments)
		If SameType(routine.declaredType, expectedReturn) Then Return True
		' Covariant returns include the builtin Object boundary: a concrete
		' reference type, String, or array may refine an inherited Object
		' result even though Object itself is represented as a builtin type.
		Return IsSubtype(routine.declaredType, expectedReturn, 0)
	End Method

	Method OverrideParametersMatch:Int(routine:TSymbol, candidate:TSymbol, inherited:TNamedSemanticType)
		If routine.genericArity <> candidate.genericArity Or routine.parameterTypes.length <> candidate.parameterTypes.length Then Return False
		Local ownerParameters:TSymbol[] = DeclaredTypeParameters(inherited.symbol)
		Local candidateRoutineParameters:TSymbol[] = DeclaredTypeParameters(candidate)
		Local routineTypeArguments:TSemanticType[] = TypeParameterTypes(DeclaredTypeParameters(routine))
		For Local index:Int = 0 Until routine.parameterTypes.length
			Local expected:TSemanticType = Substitute(candidate.parameterTypes[index], ownerParameters, inherited.typeArguments)
			expected = Substitute(expected, candidateRoutineParameters, routineTypeArguments)
			If Not SameType(routine.parameterTypes[index], expected) Then Return False
			If ParameterModeAt(routine, index) <> ParameterModeAt(candidate, index) Then Return False
		Next
		Return True
	End Method

	Function RoutineModifierToken:TSyntaxToken(routine:TSymbol, name:String)
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
		If Not declaration Or Not declaration.signature Then Return Null
		For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
			If token.text.ToLower() = name Then Return token
		Next
		Return Null
	End Function

	Function DeclaredTypeParameters:TSymbol[](owner:TSymbol)
		Local result:TSymbol[]
		If Not owner Or Not owner.memberScope Then Return result
		For Local symbol:TSymbol = EachIn owner.memberScope.declaredSymbols
			If symbol.kind = SYMBOL_TYPE_PARAMETER Then result :+ [symbol]
		Next
		Return result
	End Function

	Function TypeParameterTypes:TSemanticType[](parameters:TSymbol[])
		Local result:TSemanticType[] = New TSemanticType[parameters.length]
		For Local index:Int = 0 Until parameters.length
			result[index] = parameters[index].declaredType
		Next
		Return result
	End Function

	Function ParameterModeAt:Int(routine:TSymbol, index:Int)
		If index < routine.parameters.length And routine.parameters[index] Then Return routine.parameters[index].passingMode
		Return PARAMETER_PASS_VALUE
	End Function

	Method BuildTypeInformation(symbol:TSymbol)
		Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
		Local info:TTypeInheritanceInfo = New TTypeInheritanceInfo
		info.symbol = symbol
		If symbol.isImported And symbol.interfaceRecord Then
			If symbol.interfaceRecord.baseTypeSyntax Then info.baseEdges = CreateEdges([symbol.interfaceRecord.baseTypeSyntax])
			info.interfaceEdges = CreateEdges(symbol.interfaceRecord.implementedTypeSyntax)
			If symbol.interfaceRecord.typeHeaderSyntax Then
				info.constraints = BuildConstraints(symbol.interfaceRecord.typeHeaderSyntax.constraints, symbol.memberScope)
			End If
		Else If declaration And declaration.header Then
			info.baseEdges = CreateEdges(declaration.header.extendsTypes)
			info.interfaceEdges = CreateEdges(declaration.header.implementedTypes)
			Local typeScope:TScope = model.ScopeFor(declaration)
			info.constraints = BuildConstraints(declaration.header.constraints, typeScope)
		End If
		AddImplicitObjectBase(info)
		model.inheritanceInfoMap.Insert(symbol, info)
	End Method

	Method BuildConstraints:TGenericConstraintInfo[](constraints:TGenericConstraintSyntax[], typeScope:TScope)
		Local constraintList:TList = New TList
		Local seen:TMap = New TMap
		For Local constraint:TGenericConstraintSyntax = EachIn constraints
			Local key:String = constraint.parameterNameToken.text.ToLower()
			Local parameter:TSymbol = FindTypeParameter(typeScope, constraint.parameterNameToken.text)
			If Not parameter Then
				AddDiagnostic("BMX3207", "Generic constraint refers to undeclared type parameter '" + constraint.parameterNameToken.text + "'.", constraint.parameterNameToken.span)
				Continue
			End If
			If seen.Contains(key) Then
				AddDiagnostic("BMX3208", "Type parameter '" + parameter.name + "' has more than one constraint clause.", constraint.parameterNameToken.span)
			Else
				seen.Insert(key, parameter)
			End If
			Local constraintInfo:TGenericConstraintInfo = New TGenericConstraintInfo
			constraintInfo.syntax = constraint
			constraintInfo.parameterSymbol = parameter
			constraintInfo.bounds = New TSemanticType[constraint.constraintTypes.length]
			For Local index:Int = 0 Until constraint.constraintTypes.length
				Local bound:TSemanticType = model.TypeOf(constraint.constraintTypes[index])
				constraintInfo.bounds[index] = bound
				Local builtinBound:TBuiltinSemanticType = TBuiltinSemanticType(bound)
				Local objectBound:Int = builtinBound And builtinBound.name.ToLower() = "object"
				If bound And Not objectBound And Not TNamedSemanticType(bound) And Not TTypeParameterSemanticType(bound) And Not TErrorSemanticType(bound) Then
					AddDiagnostic("BMX3210", "Generic constraint bound '" + bound.DisplayName() + "' is not a declared reference type or type parameter.", constraint.constraintTypes[index].span)
				End If
			Next
			constraintList.AddLast(constraintInfo)
		Next
		Return ConstraintsToArray(constraintList)
	End Method

	Method AddImplicitObjectBase(info:TTypeInheritanceInfo)
		If Not info Or info.symbol.kind <> SYMBOL_TYPE Then Return
		Local objectBuiltin:TBuiltinSemanticType = model.BuiltinType("Object")
		If Not objectBuiltin Or Not objectBuiltin.runtimeSymbol Or info.symbol = objectBuiltin.runtimeSymbol Then Return
		Local hasNoBase:Int = info.baseEdges.length = 0
		If info.baseEdges.length = 1 Then
			Local nullBase:TBuiltinSemanticType = TBuiltinSemanticType(info.baseEdges[0].semanticType)
			If nullBase And nullBase.name.ToLower() = "null" Then hasNoBase = True
		End If
		If Not hasNoBase Then Return
		Local edge:TInheritanceEdge = New TInheritanceEdge
		edge.semanticType = objectBuiltin.runtimeSymbol.declaredType
		edge.isImplicit = True
		info.baseEdges = [edge]
	End Method

	Method CreateEdges:TInheritanceEdge[](references:TTypeReferenceSyntax[])
		Local result:TInheritanceEdge[] = New TInheritanceEdge[references.length]
		For Local index:Int = 0 Until references.length
			Local edge:TInheritanceEdge = New TInheritanceEdge
			edge.syntax = references[index]
			edge.semanticType = model.TypeOf(references[index])
			result[index] = edge
		Next
		Return result
	End Method

	Method ValidateDeclarations(scope:TScope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			Local info:TTypeInheritanceInfo = model.InheritanceInfo(symbol)
			If info Then
				currentPath = symbol.originPath
				ValidateDeclaration(info)
			End If
		Next
		For Local child:TScope = EachIn scope.children
			ValidateDeclarations(child)
		Next
	End Method

	Method ValidateDeclaration(info:TTypeInheritanceInfo)
		Local symbol:TSymbol = info.symbol
		If symbol.isImported Then Return
		If symbol.kind = SYMBOL_STRUCT Then
			If info.baseEdges.length Or info.interfaceEdges.length Then
				Local span:TSourceSpan = symbol.nameToken.span
				If info.baseEdges.length Then span = info.baseEdges[0].syntax.span Else If info.interfaceEdges.length Then span = info.interfaceEdges[0].syntax.span
				AddDiagnostic("BMX3202", "Struct '" + symbol.name + "' cannot extend or implement another type.", span)
			End If
			Return
		End If

		If symbol.kind = SYMBOL_TYPE And info.baseEdges.length > 1 Then
			AddDiagnostic("BMX3200", "Type '" + symbol.name + "' can extend only one base type.", info.baseEdges[1].syntax.span)
		End If
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			Local target:TSymbol = NamedSymbol(edge.semanticType)
			If Not target Then Continue
			If symbol.kind = SYMBOL_INTERFACE Then
				If target.kind <> SYMBOL_INTERFACE Then
					AddDiagnostic("BMX3201", "Interface '" + symbol.name + "' can extend only interfaces.", edge.syntax.span)
				Else If symbol.isExternal <> target.isExternal Then
					AddDiagnostic("BMX3218", "External and managed interfaces cannot extend one another.", edge.syntax.span)
				End If
			Else If target.kind <> SYMBOL_TYPE Then
				AddDiagnostic("BMX3200", "Type '" + symbol.name + "' can extend only another reference type.", edge.syntax.span)
			Else If IsFinal(target) Then
				AddDiagnostic("BMX3205", "Type '" + target.name + "' is Final and cannot be extended.", edge.syntax.span)
			End If
		Next

		If symbol.kind = SYMBOL_INTERFACE And info.interfaceEdges.length Then
			AddDiagnostic("BMX3203", "Interface '" + symbol.name + "' cannot use Implements; extend interfaces instead.", info.interfaceEdges[0].syntax.span)
		End If
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
			Local target:TSymbol = NamedSymbol(edge.semanticType)
			If target And target.kind <> SYMBOL_INTERFACE Then AddDiagnostic("BMX3203", "'" + target.name + "' is not an interface.", edge.syntax.span)
		Next
		ValidateDuplicateInterfaces(info)
		ValidateInterfaceSlotCollisions(info)
		ValidateDefaultConflicts(info)
	End Method

	Method ValidateInterfaceSlotCollisions(info:TTypeInheritanceInfo)
		If Not info Or Not info.symbol Or (info.symbol.kind <> SYMBOL_TYPE And info.symbol.kind <> SYMBOL_INTERFACE) Then Return
		Local groups:TMap = New TMap
		Local seen:TMap = New TMap
		Local edges:TInheritanceEdge[] = info.interfaceEdges
		If info.symbol.kind = SYMBOL_INTERFACE Then edges = info.baseEdges
		For Local edge:TInheritanceEdge = EachIn edges
			CollectInterfaceMethodCandidates(TNamedSemanticType(edge.semanticType), groups, seen, 0)
		Next
		If info.symbol.kind = SYMBOL_INTERFACE Then
			Local selfType:TNamedSemanticType = TNamedSemanticType(info.symbol.declaredType)
			CollectDeclaredInterfaceMethodCandidates(selfType, groups, seen)
		End If
		For Local selector:String = EachIn groups.Keys()
			Local candidates:TList = TList(groups.ValueForKey(selector))
			Local checked:TList = New TList
			Local collision:Int
			For Local candidate:TInterfaceMethodCandidate = EachIn candidates
				For Local prior:TInterfaceMethodCandidate = EachIn checked
					Local priorReturn:TSemanticType = ClosedInterfaceReturn(prior)
					Local candidateReturn:TSemanticType = ClosedInterfaceReturn(candidate)
					' An open type parameter is specialization-dependent. The closed
					' generic Interface planner performs the same compatibility check
					' after canonical argument substitution.
					If ContainsOpenTypeParameter(priorReturn) Or ContainsOpenTypeParameter(candidateReturn) Then Continue
					If SameType(priorReturn, candidateReturn) Or IsSubtype(priorReturn, candidateReturn, 0) Or IsSubtype(candidateReturn, priorReturn, 0) Then Continue
					AddDiagnostic("BMX3216", "Type '" + info.symbol.name + "' inherits Interface method selector '" + candidate.routine.name + "' with incompatible return types '" + priorReturn.DisplayName() + "' and '" + candidateReturn.DisplayName() + "'.", info.symbol.nameToken.span)
					collision = True
					Exit
				Next
				If collision Then Exit
				checked.AddLast(candidate)
			Next
		Next
	End Method

	Function ClosedInterfaceReturn:TSemanticType(candidate:TInterfaceMethodCandidate)
		If Not candidate Or Not candidate.routine Or Not candidate.ownerType Then Return Null
		Return SubstituteStatic(candidate.routine.declaredType, TypeParametersStatic(candidate.ownerType.symbol), candidate.ownerType.typeArguments)
	End Function

	Function TypeParametersStatic:TSymbol[](symbol:TSymbol)
		Return DeclaredTypeParameters(symbol)
	End Function

	Function ContainsOpenTypeParameter:Int(value:TSemanticType)
		If Not value Then Return False
		If TTypeParameterSemanticType(value) Then Return True
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then
			For Local argument:TSemanticType = EachIn named.typeArguments
				If ContainsOpenTypeParameter(argument) Then Return True
			Next
			Return False
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then Return ContainsOpenTypeParameter(arrayType.elementType)
		Local fixedArray:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If fixedArray Then Return ContainsOpenTypeParameter(fixedArray.elementType)
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If pointer Then Return ContainsOpenTypeParameter(pointer.elementType)
		Local callable:TCallableSemanticType = TCallableSemanticType(value)
		If callable Then
			If ContainsOpenTypeParameter(callable.returnType) Then Return True
			For Local parameterType:TSemanticType = EachIn callable.parameterTypes
				If ContainsOpenTypeParameter(parameterType) Then Return True
			Next
		End If
		Return False
	End Function

	Method ValidateDefaultConflicts(info:TTypeInheritanceInfo)
		If Not info Or Not info.symbol Or (info.symbol.kind <> SYMBOL_TYPE And info.symbol.kind <> SYMBOL_INTERFACE) Then Return
		Local groups:TMap = New TMap
		Local seen:TMap = New TMap
		Local edges:TInheritanceEdge[] = info.interfaceEdges
		If info.symbol.kind = SYMBOL_INTERFACE Then edges = info.baseEdges
		For Local edge:TInheritanceEdge = EachIn edges
			CollectInterfaceMethodCandidates(TNamedSemanticType(edge.semanticType), groups, seen, 0)
		Next
		If info.symbol.kind = SYMBOL_INTERFACE Then
			Local selfType:TNamedSemanticType = TNamedSemanticType(info.symbol.declaredType)
			CollectDeclaredInterfaceMethodCandidates(selfType, groups, seen)
		End If
		For Local selector:String = EachIn groups.Keys()
			Local candidates:TList = TList(groups.ValueForKey(selector))
			Local effectiveDefaults:TInterfaceMethodCandidate[] = New TInterfaceMethodCandidate[0]
			For Local candidate:TInterfaceMethodCandidate = EachIn candidates
				If candidate.routine.interfaceMethodKind <> INTERFACE_METHOD_DEFAULT Then Continue
				Local shadowed:Int
				For Local other:TInterfaceMethodCandidate = EachIn candidates
					If other = candidate Then Continue
					If SameType(other.ownerType, candidate.ownerType) Then Continue
					If IsSubtype(other.ownerType, candidate.ownerType, 0) Then shadowed = True; Exit
				Next
				If Not shadowed Then effectiveDefaults :+ [candidate]
			Next
			If effectiveDefaults.length <= 1 Then Continue
			If info.symbol.kind = SYMBOL_TYPE And HasConcreteTypeMethod(info.symbol, selector, 0) Then Continue
			Local origins:String
			For Local index:Int = 0 Until effectiveDefaults.length
				If index Then origins :+ ", "
				origins :+ "'" + effectiveDefaults[index].ownerType.DisplayName() + "." + effectiveDefaults[index].routine.name + "'"
			Next
			AddDiagnostic("BMX3215", "Type '" + info.symbol.name + "' inherits unrelated default Interface methods " + origins + "; declare an overriding Method to resolve the conflict.", info.symbol.nameToken.span)
		Next
	End Method

	Method CollectInterfaceMethodCandidates(ownerType:TNamedSemanticType, groups:TMap, seen:TMap, depth:Int)
		If Not ownerType Or Not ownerType.symbol Or ownerType.symbol.kind <> SYMBOL_INTERFACE Or depth > 64 Then Return
		CollectDeclaredInterfaceMethodCandidates(ownerType, groups, seen)
		Local inheritedInfo:TTypeInheritanceInfo = model.InheritanceInfo(ownerType.symbol)
		If Not inheritedInfo Then Return
		Local parameters:TSymbol[] = TypeParameters(ownerType.symbol)
		For Local edge:TInheritanceEdge = EachIn CombinedEdges(inheritedInfo)
			CollectInterfaceMethodCandidates(TNamedSemanticType(Substitute(edge.semanticType, parameters, ownerType.typeArguments)), groups, seen, depth + 1)
		Next
	End Method

	Method CollectDeclaredInterfaceMethodCandidates(ownerType:TNamedSemanticType, groups:TMap, seen:TMap)
		If Not ownerType Or Not ownerType.symbol Or Not ownerType.symbol.memberScope Then Return
		Local parameters:TSymbol[] = TypeParameters(ownerType.symbol)
		For Local routine:TSymbol = EachIn ownerType.symbol.memberScope.declaredSymbols
			If routine.kind <> SYMBOL_ROUTINE Or routine.interfaceMethodKind = INTERFACE_METHOD_NONE Then Continue
			Local selector:String = InterfaceRoutineSelector(routine, parameters, ownerType.typeArguments)
			Local identity:String = ownerType.DisplayName().ToLower() + "::" + selector + "::" + routine.interfaceMethodKind
			If seen.Contains(identity) Then Continue
			seen.Insert(identity, identity)
			Local candidate:TInterfaceMethodCandidate = New TInterfaceMethodCandidate
			candidate.routine = routine
			candidate.ownerType = ownerType
			candidate.selector = selector
			Local values:TList = TList(groups.ValueForKey(selector))
			If Not values Then values = New TList; groups.Insert(selector, values)
			values.AddLast(candidate)
		Next
	End Method

	Method HasConcreteTypeMethod:Int(symbol:TSymbol, selector:String, depth:Int)
		If Not symbol Or depth > 64 Then Return False
		Local ownerType:TNamedSemanticType = TNamedSemanticType(symbol.declaredType)
		Local parameters:TSymbol[] = TypeParameters(symbol)
		If symbol.memberScope Then
			For Local routine:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If routine.kind = SYMBOL_ROUTINE And Not routine.isAbstract And InterfaceRoutineSelector(routine, parameters, ownerType.typeArguments) = selector Then Return True
			Next
		End If
		Local inheritedInfo:TTypeInheritanceInfo = model.InheritanceInfo(symbol)
		If Not inheritedInfo Then Return False
		For Local edge:TInheritanceEdge = EachIn inheritedInfo.baseEdges
			Local baseType:TNamedSemanticType = TNamedSemanticType(Substitute(edge.semanticType, parameters, ownerType.typeArguments))
			If baseType And baseType.symbol And baseType.symbol.kind = SYMBOL_TYPE And HasConcreteTypeMethod(baseType.symbol, selector, depth + 1) Then Return True
		Next
		Return False
	End Method

	Function InterfaceRoutineSelector:String(routine:TSymbol, ownerParameters:TSymbol[], ownerArguments:TSemanticType[])
		Local result:String = routine.name.ToLower() + "#" + routine.genericArity + "("
		For Local index:Int = 0 Until routine.parameterTypes.length
			If index Then result :+ ","
			Local parameterType:TSemanticType = routine.parameterTypes[index]
			If ownerParameters Then parameterType = SubstituteStatic(parameterType, ownerParameters, ownerArguments)
			If parameterType Then result :+ parameterType.DisplayName().ToLower()
			If ParameterModeAt(routine, index) = PARAMETER_PASS_VAR Then result :+ " var"
		Next
		Return result + ")"
	End Function

	Function SubstituteStatic:TSemanticType(value:TSemanticType, parameters:TSymbol[], arguments:TSemanticType[])
		Local parameter:TTypeParameterSemanticType = TTypeParameterSemanticType(value)
		If parameter Then
			Local index:Int = SymbolIndex(parameters, parameter.symbol)
			If index >= 0 And index < arguments.length Then Return arguments[index]
		End If
		Return value
	End Function

	Method ValidateDuplicateInterfaces(info:TTypeInheritanceInfo)
		Local edges:TInheritanceEdge[] = info.interfaceEdges
		If info.symbol.kind = SYMBOL_INTERFACE Then edges = info.baseEdges
		For Local index:Int = 0 Until edges.length
			For Local prior:Int = 0 Until index
				If SameType(edges[index].semanticType, edges[prior].semanticType) Then
					AddDiagnostic("BMX3206", "Interface '" + edges[index].semanticType.DisplayName() + "' is listed more than once.", edges[index].syntax.span)
					Exit
				End If
			Next
		Next
	End Method

	Method ValidateCycles(scope:TScope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If model.InheritanceInfo(symbol) Then VisitType(symbol)
		Next
		For Local child:TScope = EachIn scope.children
			ValidateCycles(child)
		Next
	End Method

	Method VisitType(symbol:TSymbol)
		currentPath = symbol.originPath
		Local state:Int = VisitState(symbol)
		If state = 2 Then Return
		If state = 1 Then Return
		visitStates.Insert(symbol, "1")
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(symbol)
		If info Then
			For Local edge:TInheritanceEdge = EachIn info.baseEdges
				Local target:TSymbol = NamedSymbol(edge.semanticType)
				If Not target Or Not model.InheritanceInfo(target) Then Continue
				If VisitState(target) = 1 Then
					If Not reportedCycles.Contains(symbol) Then
						AddDiagnostic("BMX3204", "Inheritance cycle involving '" + symbol.name + "' and '" + target.name + "'.", edge.syntax.span)
						reportedCycles.Insert(symbol, symbol)
					End If
				Else
					VisitType(target)
				End If
			Next
		End If
		visitStates.Insert(symbol, "2")
	End Method

	Method VisitState:Int(symbol:TSymbol)
		Local value:String = String(visitStates.ValueForKey(symbol))
		If value.length Then Return Int(value)
		Return 0
	End Method

	Method ValidateReferences(scope:TScope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			currentPath = symbol.originPath
			Select symbol.kind
				Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE
					Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
					If declaration And declaration.header Then
						For Local reference:TTypeReferenceSyntax = EachIn declaration.header.extendsTypes
							ValidateReference(reference)
						Next
						For Local reference:TTypeReferenceSyntax = EachIn declaration.header.implementedTypes
							ValidateReference(reference)
						Next
						For Local constraint:TGenericConstraintSyntax = EachIn declaration.header.constraints
							For Local reference:TTypeReferenceSyntax = EachIn constraint.constraintTypes
								ValidateReference(reference)
							Next
						Next
					End If
				Case SYMBOL_ENUM
					Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(symbol.declaration)
					If enumDeclaration And enumDeclaration.underlyingType Then ValidateReference(enumDeclaration.underlyingType)
				Case SYMBOL_ROUTINE
					Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
					If routine And routine.signature And routine.signature.returnType Then ValidateReference(routine.signature.returnType)
					If routine And routine.signature And routine.signature.callableReturnType Then ValidateCallableReference(routine.signature.callableReturnType)
				Case SYMBOL_FIELD, SYMBOL_GLOBAL, SYMBOL_CONST, SYMBOL_LOCAL
					Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(symbol.declaration)
					If declarator And declarator.declaredType Then ValidateReference(declarator.declaredType)
				Case SYMBOL_PARAMETER
					Local parameter:TParameterSyntax = TParameterSyntax(symbol.declaration)
					If parameter And parameter.declaredType Then ValidateReference(parameter.declaredType)
				Case SYMBOL_CATCH_PARAMETER
					Local catchClause:TCatchClauseSyntax = TCatchClauseSyntax(symbol.declaration)
					If catchClause And catchClause.declaredType Then ValidateReference(catchClause.declaredType)
			End Select
		Next
		For Local child:TScope = EachIn scope.children
			ValidateReferences(child)
		Next
	End Method

	Method ValidateCallableReference(callable:TCallableTypeSyntax)
		If Not callable Then Return
		If callable.returnType Then ValidateReference(callable.returnType)
		For Local parameter:TParameterSyntax = EachIn callable.parameters
			If parameter.callableType Then
				ValidateCallableReference(parameter.callableType)
			Else If parameter.declaredType Then
				ValidateReference(parameter.declaredType)
			End If
		Next
	End Method

	Method ValidateReference(syntax:TTypeReferenceSyntax)
		For Local argument:TTypeReferenceSyntax = EachIn syntax.genericArguments
			ValidateReference(argument)
		Next
		Local namedType:TNamedSemanticType = TNamedSemanticType(Unwrap(model.TypeOf(syntax)))
		If Not namedType Then Return
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(namedType.symbol)
		If Not info Or Not info.constraints.length Then Return
		Local parameters:TSymbol[] = TypeParameters(namedType.symbol)
		If namedType.typeArguments.length <> parameters.length Then Return
		For Local constraint:TGenericConstraintInfo = EachIn info.constraints
			Local parameterIndex:Int = SymbolIndex(parameters, constraint.parameterSymbol)
			If parameterIndex < 0 Then Continue
			Local argumentType:TSemanticType = namedType.typeArguments[parameterIndex]
			For Local bound:TSemanticType = EachIn constraint.bounds
				Local required:TSemanticType = Substitute(bound, parameters, namedType.typeArguments)
				If Not IsSubtype(argumentType, required, 0) Then
					Local span:TSourceSpan = syntax.span
					If parameterIndex < syntax.genericArguments.length Then span = syntax.genericArguments[parameterIndex].span
					AddDiagnostic("BMX3209", "Type argument '" + argumentType.DisplayName() + "' does not satisfy constraint '" + required.DisplayName() + "' for '" + constraint.parameterSymbol.name + "'.", span)
				End If
			Next
		Next
	End Method

	Method IsSubtype:Int(actual:TSemanticType, required:TSemanticType, depth:Int)
		If Not actual Or Not required Then Return False
		If TErrorSemanticType(actual) Or TErrorSemanticType(required) Then Return True
		If SameType(actual, required) Then Return True
		If depth > 64 Then Return False
		Local requiredBuiltin:TBuiltinSemanticType = TBuiltinSemanticType(required)
		If requiredBuiltin And requiredBuiltin.name.ToLower() = "object" And IsObjectReference(actual) Then Return True
		Local parameterType:TTypeParameterSemanticType = TTypeParameterSemanticType(actual)
		If parameterType Then
			Local owner:TSymbol
			If parameterType.symbol.containingScope Then owner = parameterType.symbol.containingScope.owner
			Local ownerInfo:TTypeInheritanceInfo = model.InheritanceInfo(owner)
			If ownerInfo Then
				For Local constraint:TGenericConstraintInfo = EachIn ownerInfo.constraints
					If constraint.parameterSymbol = parameterType.symbol Then
						For Local bound:TSemanticType = EachIn constraint.bounds
							If IsSubtype(bound, required, depth + 1) Then Return True
						Next
					End If
				Next
			End If
			Return False
		End If
		Local namedActual:TNamedSemanticType = TNamedSemanticType(actual)
		If Not namedActual Then Return False
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(namedActual.symbol)
		If Not info Then Return False
		Local parameters:TSymbol[] = TypeParameters(namedActual.symbol)
		For Local edge:TInheritanceEdge = EachIn CombinedEdges(info)
			Local inherited:TSemanticType = Substitute(edge.semanticType, parameters, namedActual.typeArguments)
			If IsSubtype(inherited, required, depth + 1) Then Return True
		Next
		Return False
	End Method

	Function IsObjectReference:Int(value:TSemanticType)
		If Not value Then Return False
		If TNamedSemanticType(value) Or TArraySemanticType(value) Then Return True
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If Not builtin Then Return False
		Return builtin.name.ToLower() = "string" Or builtin.name.ToLower() = "object"
	End Function

	Method Substitute:TSemanticType(value:TSemanticType, parameters:TSymbol[], arguments:TSemanticType[])
		Local parameter:TTypeParameterSemanticType = TTypeParameterSemanticType(value)
		If parameter Then
			Local index:Int = SymbolIndex(parameters, parameter.symbol)
			If index >= 0 And index < arguments.length Then Return arguments[index]
			Return value
		End If
		Local namedType:TNamedSemanticType = TNamedSemanticType(value)
		If namedType Then
			Local result:TNamedSemanticType = New TNamedSemanticType
			result.kind = SEMANTIC_TYPE_NAMED
			result.symbol = namedType.symbol
			result.typeArguments = New TSemanticType[namedType.typeArguments.length]
			For Local index:Int = 0 Until namedType.typeArguments.length
				result.typeArguments[index] = Substitute(namedType.typeArguments[index], parameters, arguments)
			Next
			Return result
		End If
		Local pointerType:TPointerSemanticType = TPointerSemanticType(value)
		If pointerType Then
			Local result:TPointerSemanticType = New TPointerSemanticType
			result.kind = SEMANTIC_TYPE_POINTER
			result.elementType = Substitute(pointerType.elementType, parameters, arguments)
			Return result
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then
			Local result:TArraySemanticType = New TArraySemanticType
			result.kind = SEMANTIC_TYPE_ARRAY
			result.rank = arrayType.rank
			result.elementType = Substitute(arrayType.elementType, parameters, arguments)
			Return result
		End If
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If staticArrayType Then
			Local result:TStaticArraySemanticType = New TStaticArraySemanticType
			result.kind = SEMANTIC_TYPE_STATIC_ARRAY
			result.length = staticArrayType.length
			result.boundSyntax = staticArrayType.boundSyntax
			result.elementType = Substitute(staticArrayType.elementType, parameters, arguments)
			Return result
		End If
		Local callableType:TCallableSemanticType = TCallableSemanticType(value)
		If callableType Then
			Local result:TCallableSemanticType = New TCallableSemanticType
			result.kind = SEMANTIC_TYPE_CALLABLE
			result.routine = callableType.routine
			result.callingConvention = callableType.callingConvention
			result.returnType = Substitute(callableType.returnType, parameters, arguments)
			result.parameterTypes = New TSemanticType[callableType.parameterTypes.length]
			result.parameterModes = callableType.parameterModes[..]
			For Local index:Int = 0 Until callableType.parameterTypes.length
				result.parameterTypes[index] = Substitute(callableType.parameterTypes[index], parameters, arguments)
			Next
			Return result
		End If
		Local closureType:TClosureSemanticType = TClosureSemanticType(value)
		If closureType Then
			Local result:TClosureSemanticType = New TClosureSemanticType
			result.kind = SEMANTIC_TYPE_CLOSURE
			result.signature = TCallableSemanticType(Substitute(closureType.signature, parameters, arguments))
			result.parameterNames = closureType.parameterNames[..]
			Return result
		End If
		Return value
	End Method

	Function SameType:Int(first:TSemanticType, second:TSemanticType)
		If first = second Then Return True
		If Not first Or Not second Or first.kind <> second.kind Then Return False
		Local firstBuiltin:TBuiltinSemanticType = TBuiltinSemanticType(first)
		If firstBuiltin Then Return firstBuiltin.name.ToLower() = TBuiltinSemanticType(second).name.ToLower()
		Local firstParameter:TTypeParameterSemanticType = TTypeParameterSemanticType(first)
		If firstParameter Then Return firstParameter.symbol = TTypeParameterSemanticType(second).symbol
		Local firstNamed:TNamedSemanticType = TNamedSemanticType(first)
		If firstNamed Then
			Local secondNamed:TNamedSemanticType = TNamedSemanticType(second)
			If firstNamed.symbol <> secondNamed.symbol Or firstNamed.typeArguments.length <> secondNamed.typeArguments.length Then Return False
			For Local index:Int = 0 Until firstNamed.typeArguments.length
				If Not SameType(firstNamed.typeArguments[index], secondNamed.typeArguments[index]) Then Return False
			Next
			Return True
		End If
		Local firstPointer:TPointerSemanticType = TPointerSemanticType(first)
		If firstPointer Then Return SameType(firstPointer.elementType, TPointerSemanticType(second).elementType)
		Local firstArray:TArraySemanticType = TArraySemanticType(first)
		If firstArray Then Return firstArray.rank = TArraySemanticType(second).rank And SameType(firstArray.elementType, TArraySemanticType(second).elementType)
		Local firstStatic:TStaticArraySemanticType = TStaticArraySemanticType(first)
		If firstStatic Then Return firstStatic.length = TStaticArraySemanticType(second).length And SameType(firstStatic.elementType, TStaticArraySemanticType(second).elementType)
		Local firstCallable:TCallableSemanticType = TCallableSemanticType(first)
		If firstCallable Then
			Local secondCallable:TCallableSemanticType = TCallableSemanticType(second)
			If Not secondCallable Or firstCallable.callingConvention <> secondCallable.callingConvention Or firstCallable.parameterTypes.length <> secondCallable.parameterTypes.length Or Not SameType(firstCallable.returnType, secondCallable.returnType) Then Return False
			For Local index:Int = 0 Until firstCallable.parameterTypes.length
				If index < firstCallable.parameterModes.length And index < secondCallable.parameterModes.length And firstCallable.parameterModes[index] <> secondCallable.parameterModes[index] Then Return False
				If Not SameType(firstCallable.parameterTypes[index], secondCallable.parameterTypes[index]) Then Return False
			Next
			Return True
		End If
		Local firstClosure:TClosureSemanticType = TClosureSemanticType(first)
		If firstClosure Then
			Local secondClosure:TClosureSemanticType = TClosureSemanticType(second)
			Return secondClosure And SameType(firstClosure.signature, secondClosure.signature)
		End If
		Local firstError:TErrorSemanticType = TErrorSemanticType(first)
		If firstError Then Return firstError.writtenName.ToLower() = TErrorSemanticType(second).writtenName.ToLower()
		Return False
	End Function

	Function Unwrap:TSemanticType(value:TSemanticType)
		Return value
	End Function

	Function NamedSymbol:TSymbol(value:TSemanticType)
		Local namedType:TNamedSemanticType = TNamedSemanticType(value)
		If namedType Then Return namedType.symbol
		Return Null
	End Function

	Function IsFinal:Int(symbol:TSymbol)
		Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
		If declaration And declaration.header Then
			For Local token:TSyntaxToken = EachIn declaration.header.modifierTokens
				If token.text.ToLower() = "final" Then Return True
			Next
		End If
		Return False
	End Function

	Function FindTypeParameter:TSymbol(scope:TScope, name:String)
		If Not scope Then Return Null
		For Local symbol:TSymbol = EachIn scope.LookupLocal(name)
			If symbol.kind = SYMBOL_TYPE_PARAMETER Then Return symbol
		Next
		Return Null
	End Function

	Method TypeParameters:TSymbol[](symbol:TSymbol)
		' The member scope is the canonical semantic home of a type's generic
		' parameters. In particular, parsed .i declarations have no source
		' declaration node, but the interface importer still creates these
		' symbols from the decoded/expanded type header.
		Return DeclaredTypeParameters(symbol)
	End Method

	Function SymbolIndex:Int(symbols:TSymbol[], symbol:TSymbol)
		For Local index:Int = 0 Until symbols.length
			If symbols[index] = symbol Then Return index
		Next
		Return -1
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

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan)
		diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span, currentPath))
	End Method

	Function ConstraintsToArray:TGenericConstraintInfo[](list:TList)
		Local result:TGenericConstraintInfo[] = New TGenericConstraintInfo[list.Count()]
		Local index:Int
		For Local value:TGenericConstraintInfo = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function

	Function DiagnosticsToArray:TDiagnostic[](list:TList)
		Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
		Local index:Int
		For Local value:TDiagnostic = EachIn list
			result[index] = value
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
