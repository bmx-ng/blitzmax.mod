' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BlitzMax.Language
Import "compiler_diagnostic.bmx"
Import "compiler_options.bmx"
Import "abi_naming.bmx"
Import "ir_model.bmx"
Import "generic_application_plan.bmx"

Type TCompilerIrLoweringProfile
	Field initializationMilliseconds:Int
	Field inputMilliseconds:Int
	Field genericReferenceMilliseconds:Int
	Field typeShellMilliseconds:Int
	Field functionShellMilliseconds:Int
	Field closureMilliseconds:Int
	Field interfaceMilliseconds:Int
	Field bodyMilliseconds:Int
	Field finalizationMilliseconds:Int
	Field documentCount:Int
	Field interfaceCount:Int
End Type

Type TCompilerLoopLoweringContext
	Field parent:TCompilerLoopLoweringContext
	Field loopId:String
	Field sourceLabel:String
	Field owner:TCompilerIrStatement
	Field usingDepth:Int
	Field tryDepth:Int
	Field cleanupDepth:Int
	Field continueCleanupDepth:Int
End Type

Type TCompilerClosureCapturePlan
	Field ownerSymbol:TSymbol
	Field storageScope:TScope
	Field activationScoped:Int
	Field iterationScoped:Int
	Field catchScoped:Int
	Field parentPlan:TCompilerClosureCapturePlan
	Field parentField:TCompilerIrClassField
	Field needsParent:Int
	Field environmentClass:TCompilerIrClass
	Field environmentSymbolId:String
	Field captures:TSymbol[] = New TSymbol[0]
	Field fieldsBySymbol:TMap = New TMap
	Field capturesSelf:Int
	Field selfType:TSemanticType
	Field selfField:TCompilerIrClassField
End Type

Const SEQUENCE_FUSION_FILTER:Int = 1
Const SEQUENCE_FUSION_MAP:Int = 2
Const SEQUENCE_FUSION_TAKE:Int = 3
Const SEQUENCE_FUSION_SKIP:Int = 4
Const SEQUENCE_FUSION_TAKE_WHILE:Int = 5
Const SEQUENCE_FUSION_SKIP_WHILE:Int = 6

Const SEQUENCE_FUSION_FOLD:Int = 1
Const SEQUENCE_FUSION_COUNT:Int = 2
Const SEQUENCE_FUSION_ANY:Int = 3
Const SEQUENCE_FUSION_ALL:Int = 4
Const SEQUENCE_FUSION_FIRST_OR_NONE:Int = 5
Const SEQUENCE_FUSION_FOR_EACH:Int = 6
Const SEQUENCE_FUSION_TO_ARRAY:Int = 7
Const SEQUENCE_FUSION_LAST_OR_NONE:Int = 8

' A conservative, typed description of a directly visible BRL.Sequence query.
' It is discarded unless the complete source/operator/terminal chain is known.
Type TCompilerSequenceFusionStage
	Field kind:Int
	Field argument:TBoundExpression
	Field inputType:TSemanticType
	Field outputType:TSemanticType
	Field parameter:TCompilerIrParameter
	Field counterSymbolId:String
	Field stateSymbolId:String
End Type

Type TCompilerSequenceFusionPlan
	Field source:TBoundExpression
	Field sourceElementType:TSemanticType
	Field stages:TCompilerSequenceFusionStage[] = New TCompilerSequenceFusionStage[0]
	Field terminalKind:Int
	Field terminalArguments:TBoundExpression[] = New TBoundExpression[0]
	Field terminalParameters:TCompilerIrParameter[] = New TCompilerIrParameter[0]
	Field resultType:TSemanticType
End Type

Type TCompilerIrLowerer
	Field analysis:TLanguageAnalysis
	Field options:TCompilerOptions
	Field genericPlan:TCompilerGenericApplicationPlan
	Field result:TCompilerIrModule
	Field diagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]
	Field functionsBySymbol:TMap = New TMap
	Field externalFunctionsBySymbol:TMap = New TMap
	Field genericFunctionsBySpecialization:TMap = New TMap
	Field externalGlobalsBySymbol:TMap = New TMap
	Field genericStaticGlobalsByKey:TMap = New TMap
	Field stringLiteralsByValue:TMap = New TMap
	Field enumsBySymbol:TMap = New TMap
	Field structsBySymbol:TMap = New TMap
	Field structFieldsBySymbol:TMap = New TMap
	Field completedStructLayouts:TMap = New TMap
	Field visitingStructLayouts:TMap = New TMap
	Field structSymbols:TSymbol[] = New TSymbol[0]
	Field importedStructsBySymbol:TMap = New TMap
	Field importedStructsByAbiName:TMap = New TMap
	Field genericStructsByTypeName:TMap = New TMap
	Field importedStructFieldsBySymbol:TMap = New TMap
	Field importedStructRoutinesBySymbol:TMap = New TMap
	Field completedImportedStructLayouts:TMap = New TMap
	Field visitingImportedStructLayouts:TMap = New TMap
	Field classesBySymbol:TMap = New TMap
	Field directMethodLayoutSymbols:TMap = New TMap
	Field importedClassesBySymbol:TMap = New TMap
	Field importedClassesByAbiName:TMap = New TMap
	Field genericClassesByTypeName:TMap = New TMap
	Field importedFieldsBySymbol:TMap = New TMap
	Field importedMethodsBySymbol:TMap = New TMap
	Field importedConstructorsBySymbol:TMap = New TMap
	Field inheritedConstructorsByClass:TMap = New TMap
	Field classSymbols:TSymbol[] = New TSymbol[0]
	Field interfacesBySymbol:TMap = New TMap
	Field interfacesByAbiName:TMap = New TMap
	Field genericInterfacesByTypeName:TMap = New TMap
	Field importedBySpecialization:TMap = New TMap
	Field sourceRuntimeLayoutSymbolsByAbi:TMap = New TMap
	Field interfaceSymbols:TSymbol[] = New TSymbol[0]
	Field interfaceMethodsByInterface:TMap = New TMap
	Field interfaceMethodSymbols:TMap = New TMap
	Field abstractInterfaceFunctionsByMethod:TMap = New TMap
	Field completedInterfaceLayouts:TMap = New TMap
	Field fieldsBySymbol:TMap = New TMap
	Field slotsByRoutineSymbol:TMap = New TMap
	Field completedClassLayouts:TMap = New TMap
	Field completedClassRoutines:TMap = New TMap
	Field symbolsById:TMap = New TMap
	Field byReferenceSymbols:TMap = New TMap
	Field closureCapturePlans:TCompilerClosureCapturePlan[] = New TCompilerClosureCapturePlan[0]
	Field closureCapturePlansByOwner:TMap = New TMap
	Field closureCapturePlansByLiteral:TMap = New TMap
	Field closureCapturePlansByScope:TMap = New TMap
	Field closureCapturePlansBySymbol:TMap = New TMap
	Field moduleClosureCapturePlan:TCompilerClosureCapturePlan
	Field nextFunctionId:Int
	Field nextExternalFunctionId:Int
	Field nextExternalGlobalId:Int
	Field nextStringLiteralId:Int
	Field nextEnumId:Int
	Field nextStructId:Int
	Field nextImportedStructId:Int
	Field nextImportedStructFieldId:Int
	Field nextImportedStructRoutineId:Int
	Field nextClassId:Int
	Field nextImportedClassId:Int
	Field nextImportedFieldId:Int
	Field nextImportedMethodId:Int
	Field nextImportedConstructorId:Int
	Field nextInterfaceId:Int
	Field nextSymbolId:Int
	Field nextGlobalSymbolId:Int
	Field nextTemporaryId:Int
	Field nextLoopId:Int
	Field nextUsingId:Int
	Field routineSymbols:TSymbol[] = New TSymbol[0]
	Field currentReceiver:TCompilerIrParameter
	Field currentRoutine:TCompilerIrFunction
	Field currentRoutineSymbol:TSymbol
	Field currentIncomingClosureCapturePlan:TCompilerClosureCapturePlan
	Field currentOwnedClosureCapturePlan:TCompilerClosureCapturePlan
	Field currentClass:TCompilerIrClass
	Field currentStruct:TCompilerIrStruct
	Field currentLoop:TCompilerLoopLoweringContext
	Field preserveStructLValue:Int
	Field activeTryBodyDepth:Int
	Field activeYieldExceptionFrameDepth:Int
	Field activeTryFinallyBlocks:TCompilerIrBlock[] = New TCompilerIrBlock[0]
	Field activeReturnCleanupSteps:TCompilerIrCleanupStep[] = New TCompilerIrCleanupStep[0]
	Field activeUsingBodyDepth:Int
	Field documents:TSourceDocumentModel[] = New TSourceDocumentModel[0]
	Field navigators:TSyntaxNavigator[] = New TSyntaxNavigator[0]
	Field debugSourcesByPath:TMap = New TMap
	Field compilationNoDebug:Int

	Function Lower:TCompilerIrModule(analysis:TLanguageAnalysis, options:TCompilerOptions, diagnostics:TCompilerDiagnostic[] Var, genericPlan:TCompilerGenericApplicationPlan = Null)
		Local profile:TCompilerIrLoweringProfile
		Return LowerProfiled(analysis, options, diagnostics, genericPlan, profile)
	End Function

	Function LowerProfiled:TCompilerIrModule(analysis:TLanguageAnalysis, options:TCompilerOptions, diagnostics:TCompilerDiagnostic[] Var, genericPlan:TCompilerGenericApplicationPlan, profile:TCompilerIrLoweringProfile Var)
		Local lowerer:TCompilerIrLowerer = New TCompilerIrLowerer
		lowerer.analysis = analysis
		lowerer.options = options
		lowerer.genericPlan = genericPlan
		profile = New TCompilerIrLoweringProfile
		Local started:Int = MilliSecs()
		lowerer.InitializeDocuments()
		profile.initializationMilliseconds = MilliSecs() - started
		profile.documentCount = lowerer.documents.length
		If analysis And analysis.snapshot Then profile.interfaceCount = analysis.snapshot.interfaces.length
		lowerer.result = New TCompilerIrModule
		If analysis And analysis.syntaxTree Then lowerer.result.path = analysis.syntaxTree.source.path
		started = MilliSecs()
		If Not lowerer.ValidateConfiguredSyntaxInvariant() Then
			profile.inputMilliseconds = MilliSecs() - started
			diagnostics = lowerer.diagnostics
			Return lowerer.result
		End If
		If options Then
			lowerer.result.targetPlatform = options.targetPlatform
			lowerer.result.targetArchitecture = options.targetArchitecture
			lowerer.result.buildMode = options.buildMode
			lowerer.result.gdbDebug = options.gdbDebug
		End If
		lowerer.compilationNoDebug = lowerer.CompilationHasNoDebug()
		lowerer.CollectNativeHeaders()
		lowerer.CollectIncbinRequests()
		profile.inputMilliseconds = MilliSecs() - started
		started = MilliSecs()
		lowerer.BuildGenericSpecializationReferences()
		profile.genericReferenceMilliseconds = MilliSecs() - started
		started = MilliSecs()
		lowerer.PrepareDirectMethodLayoutAbis()
		lowerer.BuildEnumShells()
		lowerer.BuildImportedEnumShells()
		lowerer.BuildStructShells()
		lowerer.ResolveGenericStructRuntimeLayouts()
		lowerer.BuildInterfaceShells()
		lowerer.ResolveGenericInterfaceRuntimeParents()
		lowerer.BuildClassShells()
		profile.typeShellMilliseconds = MilliSecs() - started
		started = MilliSecs()
		lowerer.BuildFunctionShells()
		profile.functionShellMilliseconds = MilliSecs() - started
		started = MilliSecs()
		lowerer.BuildClosureCapturePlans()
		profile.closureMilliseconds = MilliSecs() - started
		started = MilliSecs()
		lowerer.BuildInterfaceImplementations()
		lowerer.ValidateTopLevelDeclarations()
		lowerer.BuildDataSection()
		profile.interfaceMilliseconds = MilliSecs() - started
		started = MilliSecs()
		lowerer.LowerFunctionBodies()
		profile.bodyMilliseconds = MilliSecs() - started
		started = MilliSecs()
		lowerer.BuildCoverageCatalog()
		If lowerer.compilationNoDebug Then lowerer.result.debugSources = New TCompilerIrDebugSource[0]
		lowerer.ValidateStructConstructorChains()
		lowerer.BuildInitializationPlan()
		profile.finalizationMilliseconds = MilliSecs() - started
		diagnostics = lowerer.diagnostics
		Return lowerer.result
	End Function

	Method ValidateConfiguredSyntaxInvariant:Int()
		For Local document:TSourceDocumentModel = EachIn documents
			If Not document Or Not document.tree Then Continue
			For Local token:TSyntaxToken = EachIn document.tree.root.tokens
				If token.kind <> TOKEN_DIRECTIVE Then Continue
				diagnostics :+ [TCompilerDiagnostic.Create("BMXC0002", "Conditional directives remained after source configuration was applied", document.path, token.span)]
				Return False
			Next
		Next
		Return True
	End Method

	Method BuildDataSection()
		If Not analysis Or Not analysis.model Or Not analysis.model.dataSection Then Return
		For Local item:TDataItem = EachIn analysis.model.dataSection.items
			If Not item Or Not item.constantValue Then Continue
			' Generic declarations carry their own source-free Data records and
			' emit a specialization-owned table. Do not duplicate those values
			' in the ordinary source unit's cursor.
			If GenericTemplateOwnsDataItem(item, analysis.model.globalScope) Then Continue
			Local irItem:TCompilerIrDataItem = New TCompilerIrDataItem
			irItem.source = SourceOf(item.syntax)
			Local dataTypeName:String
			Local dataEnum:TCompilerIrEnum = EnumForType(item.semanticType)
			If dataEnum Then
				dataTypeName = dataEnum.underlyingType.ToLower()
			Else If item.semanticType Then
				dataTypeName = TypeName(item.semanticType).ToLower()
			End If
			Select dataTypeName
				Case "byte"; irItem.typeTag = "b"; irItem.unionField = "b"
				Case "short"; irItem.typeTag = "s"; irItem.unionField = "s"
				Case "int"; irItem.typeTag = "i"; irItem.unionField = "i"
				Case "uint"; irItem.typeTag = "u"; irItem.unionField = "u"
				Case "long"; irItem.typeTag = "l"; irItem.unionField = "l"
				Case "ulong"; irItem.typeTag = "y"; irItem.unionField = "y"
				Case "size_t"; irItem.typeTag = "z"; irItem.unionField = "z"
				Case "longint"; irItem.typeTag = "v"; irItem.unionField = "v"
				Case "ulongint"; irItem.typeTag = "e"; irItem.unionField = "e"
				Case "float"; irItem.typeTag = "f"; irItem.unionField = "f"
				Case "double"; irItem.typeTag = "d"; irItem.unionField = "d"
				Case "string"
					irItem.typeTag = "$"
					irItem.unionField = "t"
					irItem.stringLiteralId = RegisterStringValue(item.constantValue.stringValue, irItem.source).literalId
			End Select
			If Not irItem.typeTag.length Then
				AddUnsupported("BMXC1221", "Data item type '" + dataTypeName + "' has no runtime representation", item.syntax)
				Continue
			End If
			If Not irItem.stringLiteralId.length Then irItem.valueText = item.constantValue.DisplayValue()
			result.dataItems :+ [irItem]
		Next
	End Method

	Method ResolveGenericInterfaceRuntimeParents()
		If Not genericPlan Then Return
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.ir Or Not unit.ir.isInterface Then Continue
			Local genericInterface:TCompilerIrInterface = TCompilerIrInterface(importedBySpecialization.ValueForKey(unit.specialization))
			If Not genericInterface Then Continue
			For Local parentReference:TTemplateTypeReference = EachIn unit.ir.inheritedRuntimeInterfaces
				If Not parentReference Or Not parentReference.runtimeAbiName.length Then Continue
				Local parentInterface:TCompilerIrInterface = EnsureImportedRuntimeInterface(parentReference.runtimeAbiName)
				If Not parentInterface Then
					AddUnsupported("BMXC1161", "Generic Interface inheritance requires ordinary Interface ABI '" + parentReference.runtimeAbiName + "'", Null)
					Continue
				End If
				Local duplicate:Int
				For Local parentId:String = EachIn genericInterface.baseInterfaceIds
					If parentId = parentInterface.interfaceId Then duplicate = True; Exit
				Next
				If Not duplicate Then genericInterface.baseInterfaceIds :+ [parentInterface.interfaceId]
			Next
		Next
	End Method

	Method GenericTemplateOwnsDataItem:Int(item:TDataItem, scope:TScope)
		If Not item Or Not item.syntax Or Not scope Then Return False
		Local itemStart:Int = item.syntax.span.start
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Then Continue
			If symbol.genericArity And symbol.declaration Then
				Local declarationStart:Int = symbol.declaration.span.start
				Local declarationEnd:Int = declarationStart + symbol.declaration.span.length
				If itemStart >= declarationStart And itemStart < declarationEnd Then Return True
			End If
			If symbol.memberScope And GenericTemplateOwnsDataItem(item, symbol.memberScope) Then Return True
		Next
		Return False
	End Method

	Method CollectNativeHeaders()
		If Not result Or Not result.path.length Then Return
		Local rootDirectory:String = ExtractDir(result.path.Replace("\", "/"))
		For Local document:TSourceDocumentModel = EachIn documents
			If Not document Or Not document.tree Or Not document.tree.root Then Continue
			Local documentDirectory:String = ExtractDir(document.path.Replace("\", "/"))
			Local prefix:String = "../"
			If documentDirectory.StartsWith(rootDirectory + "/") Then
				prefix :+ documentDirectory[rootDirectory.length + 1..] + "/"
			End If
			CollectNativeHeadersFromNodes(document.tree.root.members, prefix)
		Next
	End Method

	Method CollectNativeHeadersFromNodes(nodes:TSyntaxNode[], prefix:String)
		For Local node:TSyntaxNode = EachIn nodes
			Local importSyntax:TImportDirectiveSyntax = TImportDirectiveSyntax(node)
			If importSyntax And importSyntax.isNativeImport Then
				Local lowerTarget:String = importSyntax.targetText.ToLower()
				' Wildcard imports tell bmk which native files participate in
				' the build; they are not valid C preprocessor include names.
				Local isConcreteHeader:Int = importSyntax.targetText.Find("*") < 0 And importSyntax.targetText.Find("?") < 0
				If isConcreteHeader And (lowerTarget.EndsWith(".h") Or lowerTarget.EndsWith(".hpp") Or lowerTarget.EndsWith(".hh") Or lowerTarget.EndsWith(".hxx")) Then
					Local headerPath:String = prefix + importSyntax.targetText.Replace("\", "/")
					Local found:Int
					For Local existing:String = EachIn result.nativeHeaders
						If existing = headerPath Then
							found = True
							Exit
						End If
					Next
					If Not found Then result.nativeHeaders :+ [headerPath]
				End If
				Continue
			End If
		Next
	End Method

	Method CollectIncbinRequests()
		If Not analysis Or Not analysis.syntaxTree Or Not analysis.syntaxTree.root Then Return
		Local ordinal:Int
		Local sourceUnitName:String = StripExt(StripDir(result.path))
		If options And options.sourceUnitPath.length Then sourceUnitName = SourceUnitIdentity(StripExt(options.sourceUnitPath))
		Local unitName:String = "_bb_main"
		If analysis.model And analysis.model.moduleName.length Then unitName = ModuleSourceUnitName(analysis.model.moduleName, sourceUnitName)
		If unitName.StartsWith("__") Then unitName = unitName[1..]
		CollectIncbinRequestsFromNodes(analysis.syntaxTree.root.members, unitName, ordinal)
	End Method

	Method CollectIncbinRequestsFromNodes(nodes:TSyntaxNode[], unitName:String, ordinal:Int Var)
		For Local node:TSyntaxNode = EachIn nodes
			Local raw:TRawStatementSyntax = TRawStatementSyntax(node)
			If raw And raw.tokens.length >= 1 And raw.tokens[0].text.ToLower() = "incbin" Then
				If raw.tokens.length < 2 Or raw.tokens[1].kind <> TOKEN_STRING_LITERAL Then
					AddUnsupported("BMXC1220", "Incbin requires a quoted resource path", raw)
					Continue
				End If
				ordinal :+ 1
				Local request:TCompilerIrIncbin = New TCompilerIrIncbin
				request.path = TConstantEvaluator.DecodeString(raw.tokens[1].text, False)
				request.dataSymbol = "_ib" + unitName + "_" + ordinal + "_data"
				request.sizeSymbol = "_ib" + unitName + "_" + ordinal + "_size"
				request.source = SourceOf(raw)
				request.stringLiteralId = RegisterStringValue(request.path, request.source).literalId
				result.incbins :+ [request]
				Continue
			End If
		Next
	End Method

	Method BuildGenericSpecializationReferences()
		If Not genericPlan Then Return
		Local nextGenericId:Int
		Local nextGenericStructId:Int
		importedBySpecialization = New TMap
		' A class specialization referenced only by another specialization's ABI
		' has no implementation unit, but the application IR can still contain its
		' semantic type in the enclosing method signature.  Preserve the closed
		' type-to-ABI mapping without inventing fields, methods, constructors or a
		' runtime-registration dependency for that declaration-only reference.
		If genericPlan.registry Then
			For Local specialization:TGenericSpecializationNode = EachIn genericPlan.registry.nodes
				If Not specialization Or Not specialization.IsAbiReferenceOnly() Then Continue
				If Not specialization.artifact Or specialization.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_CLASS Then Continue
				Local importedClass:TCompilerIrImportedClass = New TCompilerIrImportedClass
				importedClass.importedClassId = "generic" + nextGenericId
				nextGenericId :+ 1
				importedClass.name = specialization.artifact.identity.qualifiedName
				importedClass.semanticType = GenericSemanticTypeName(specialization)
				importedClass.abiName = specialization.readableAbiName
				importedClass.originModule = specialization.artifact.identity.moduleName
				importedClass.isGenericSpecialization = True
				importedClass.specializationIdentity = specialization.identityDigest
				importedBySpecialization.Insert(specialization, importedClass)
				IndexGenericTypeName(genericClassesByTypeName, importedClass.semanticType, importedClass)
				importedClassesByAbiName.Insert(importedClass.abiName.ToLower(), importedClass)
				result.importedClasses :+ [importedClass]
			Next
		End If
		' Publish every executable generic class shell before completing any
		' specialization. Parameter and field-shape construction may import an
		' ordinary class whose virtual slots mention a later specialization.
		' A single create-and-complete pass made that valid ABI depend on unit
		' ordering and fell back to the open generic declaration.
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.specialization Or Not unit.ir Then Continue
			If unit.ir.isRoutine Or unit.ir.isInterface Or unit.ir.isStruct Then Continue
			Local importedClass:TCompilerIrImportedClass = New TCompilerIrImportedClass
			importedClass.importedClassId = "generic" + nextGenericId
			nextGenericId :+ 1
			importedClass.name = unit.specialization.artifact.identity.qualifiedName
			importedClass.semanticType = GenericSemanticTypeName(unit.specialization)
			importedClass.abiName = unit.specialization.readableAbiName
			importedClass.originModule = unit.specialization.artifact.identity.moduleName
			importedClass.isGenericSpecialization = True
			importedClass.specializationIdentity = unit.specialization.identityDigest
			importedClass.generatedUnit = unit.specialization.generatedUnit
			importedClass.registerFunctionName = unit.specialization.readableAbiName + "_register"
			importedBySpecialization.Insert(unit.specialization, importedClass)
			IndexGenericTypeName(genericClassesByTypeName, importedClass.semanticType, importedClass)
			importedClassesByAbiName.Insert(importedClass.abiName.ToLower(), importedClass)
			result.importedClasses :+ [importedClass]
		Next
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.specialization Then Continue
			If unit.ir And unit.ir.isRoutine Then
				Local genericRoutine:TCompilerGenericMethodIr = unit.ir.routine
				Local externalFunction:TCompilerIrExternalFunction = New TCompilerIrExternalFunction
				externalFunction.functionId = "ext" + nextExternalFunctionId
				nextExternalFunctionId :+ 1
				externalFunction.sourceName = genericRoutine.name
				externalFunction.abiName = genericRoutine.abiName
				externalFunction.originModule = unit.specialization.artifact.identity.moduleName
				Local returnShape:TCompilerIrParameter = New TCompilerIrParameter
				returnShape.symbolId = externalFunction.functionId + "_return"
				ConfigureGenericIrParameter(returnShape, genericRoutine.returnType)
				externalFunction.returnType = returnShape.semanticType
				externalFunction.callableReturnType = returnShape.callableReturnType
				externalFunction.callableReturnParameters = returnShape.callableParameters
				externalFunction.source = GenericIrSource(genericRoutine.source)
				externalFunction.isGenericSpecialization = True
				externalFunction.isGenericMethod = unit.specialization.artifact.isMethod
				externalFunction.isGenericStructMethod = externalFunction.isGenericMethod And genericRoutine.receiverIsStruct
				Local receiverParameterOffset:Int
				If externalFunction.isGenericMethod Then receiverParameterOffset = 1
				externalFunction.parameters = New TCompilerIrParameter[genericRoutine.parameters.length + receiverParameterOffset]
				If externalFunction.isGenericMethod Then
					Local receiverParameter:TCompilerIrParameter = New TCompilerIrParameter
					receiverParameter.symbolId = externalFunction.functionId + "_receiver"
					receiverParameter.name = "self"
					receiverParameter.semanticType = GenericIrTypeName(genericRoutine.receiverType)
					If externalFunction.isGenericStructMethod Then receiverParameter.passingMode = PARAMETER_PASS_VAR
					externalFunction.parameters[0] = receiverParameter
				End If
				For Local parameterIndex:Int = 0 Until genericRoutine.parameters.length
					Local sourceParameter:TGenericTemplateValueParameter = genericRoutine.parameters[parameterIndex]
					Local parameter:TCompilerIrParameter = New TCompilerIrParameter
					parameter.symbolId = externalFunction.functionId + "_parameter_" + parameterIndex
					parameter.name = sourceParameter.name
					parameter.passingMode = sourceParameter.passingMode
					ConfigureGenericIrParameter(parameter, sourceParameter.semanticType)
					externalFunction.parameters[parameterIndex + receiverParameterOffset] = parameter
				Next
				genericFunctionsBySpecialization.Insert(unit.specialization, externalFunction)
				result.externalFunctions :+ [externalFunction]
				result.genericInstances :+ [unit.specialization.identityDigest]
				Continue
			End If
			If unit.ir And unit.ir.isInterface Then
				Local irInterface:TCompilerIrInterface = New TCompilerIrInterface
				irInterface.interfaceId = "genericif" + nextInterfaceId
				nextInterfaceId :+ 1
				irInterface.name = unit.specialization.artifact.identity.qualifiedName
				irInterface.semanticType = GenericSemanticTypeName(unit.specialization)
				irInterface.abiName = unit.specialization.readableAbiName
				irInterface.methodsAbiName = unit.specialization.readableAbiName + "_methods"
				irInterface.originModule = unit.specialization.artifact.identity.moduleName
				irInterface.isImported = True
				interfaceMethodsByInterface.Insert(irInterface, New TMap)
				For Local genericMethod:TCompilerGenericMethodIr = EachIn unit.ir.methods
					Local interfaceMethod:TCompilerIrInterfaceMethod = New TCompilerIrInterfaceMethod
					interfaceMethod.slotId = genericMethod.slotName
					interfaceMethod.name = genericMethod.name
					interfaceMethod.declaringInterfaceId = irInterface.interfaceId
					interfaceMethod.abiName = genericMethod.abiName
					Local returnShape:TCompilerIrParameter = New TCompilerIrParameter
					returnShape.symbolId = irInterface.interfaceId + "_" + interfaceMethod.slotId + "_return"
					ConfigureGenericIrParameter(returnShape, genericMethod.returnType)
					interfaceMethod.returnType = returnShape.semanticType
					interfaceMethod.callableReturnType = returnShape.callableReturnType
					interfaceMethod.callableReturnParameters = returnShape.callableParameters
					interfaceMethod.source = GenericIrSource(genericMethod.source)
					interfaceMethod.parameters = New TCompilerIrParameter[genericMethod.parameters.length]
					For Local parameterIndex:Int = 0 Until genericMethod.parameters.length
						Local sourceParameter:TGenericTemplateValueParameter = genericMethod.parameters[parameterIndex]
						Local parameter:TCompilerIrParameter = New TCompilerIrParameter
						parameter.name = sourceParameter.name
						parameter.passingMode = sourceParameter.passingMode
						ConfigureGenericIrParameter(parameter, sourceParameter.semanticType)
						interfaceMethod.parameters[parameterIndex] = parameter
					Next
					irInterface.methods :+ [interfaceMethod]
				Next
				IndexGenericTypeName(genericInterfacesByTypeName, irInterface.semanticType, irInterface)
				interfacesByAbiName.Insert(irInterface.abiName.ToLower(), irInterface)
				importedBySpecialization.Insert(unit.specialization, irInterface)
				result.interfaces :+ [irInterface]
				result.genericInstances :+ [unit.specialization.identityDigest]
				Continue
			End If
			If unit.ir And unit.ir.isStruct Then
				Local importedStruct:TCompilerIrImportedStruct = New TCompilerIrImportedStruct
				importedStruct.importedStructId = "genericst" + nextGenericStructId
				nextGenericStructId :+ 1
				importedStruct.name = unit.specialization.artifact.identity.qualifiedName
				importedStruct.semanticType = GenericSemanticTypeName(unit.specialization)
				importedStruct.abiName = unit.specialization.readableAbiName
				importedStruct.elementInitializerAbiName = PublishedStructElementInitializerName(importedStruct.abiName)
				importedStruct.originModule = unit.specialization.artifact.identity.moduleName
				importedStruct.isGenericSpecialization = True
				importedStruct.specializationIdentity = unit.specialization.identityDigest
				importedStruct.generatedUnit = unit.specialization.generatedUnit
				importedStruct.registerFunctionName = unit.specialization.readableAbiName + "_register"
				importedBySpecialization.Insert(unit.specialization, importedStruct)
				BuildGenericStaticGlobals(unit, importedStruct.semanticType)
				For Local genericField:TCompilerGenericFieldIr = EachIn unit.ir.fields
					Local importedField:TCompilerIrImportedField = New TCompilerIrImportedField
					importedField.fieldId = importedStruct.importedStructId + "_field_" + importedStruct.fields.length
					importedField.declaringImportedStructId = importedStruct.importedStructId
					importedField.name = genericField.name
					importedField.abiName = genericField.abiName
					ConfigureGenericIrField(importedField, genericField.semanticType)
					importedField.source = GenericIrSource(genericField.source)
					importedStruct.fields :+ [importedField]
					If GenericTypeContainsDirectManagedReference(genericField.semanticType, unit.ir) Then importedStruct.containsManagedReferences = True
				Next
				For Local genericMethod:TCompilerGenericMethodIr = EachIn unit.ir.methods
					Local importedRoutine:TCompilerIrImportedStructRoutine = New TCompilerIrImportedStructRoutine
					importedRoutine.routineId = importedStruct.importedStructId + "_method_" + importedStruct.routines.length
					importedRoutine.name = genericMethod.name
					importedRoutine.abiName = genericMethod.abiName
					Local returnShape:TCompilerIrParameter = New TCompilerIrParameter
					returnShape.symbolId = importedRoutine.routineId + "_return"
					ConfigureGenericIrParameter(returnShape, genericMethod.returnType)
					importedRoutine.returnType = returnShape.semanticType
					importedRoutine.callableReturnType = returnShape.callableReturnType
					importedRoutine.callableReturnParameters = returnShape.callableParameters
					importedRoutine.isMethod = Not genericMethod.isStatic
					importedRoutine.source = GenericIrSource(genericMethod.source)
					importedRoutine.parameters = New TCompilerIrParameter[genericMethod.parameters.length]
					For Local parameterIndex:Int = 0 Until genericMethod.parameters.length
						Local sourceParameter:TGenericTemplateValueParameter = genericMethod.parameters[parameterIndex]
						Local parameter:TCompilerIrParameter = New TCompilerIrParameter
						parameter.symbolId = importedRoutine.routineId + "_parameter_" + parameterIndex
						parameter.name = sourceParameter.name
						parameter.passingMode = sourceParameter.passingMode
						ConfigureGenericIrParameter(parameter, sourceParameter.semanticType)
						importedRoutine.parameters[parameterIndex] = parameter
					Next
					importedStruct.routines :+ [importedRoutine]
				Next
				Local hasZeroArgumentStructConstructor:Int
				If unit.ir.constructors.length Then
					For Local genericConstructor:TCompilerGenericMethodIr = EachIn unit.ir.constructors
						Local importedConstructor:TCompilerIrImportedStructRoutine = New TCompilerIrImportedStructRoutine
						importedConstructor.routineId = importedStruct.importedStructId + "_new_" + TCompilerStableDigest.Sha256(genericConstructor.signatureKey)[..16]
						importedConstructor.name = "New"
						importedConstructor.objectNewAbiName = genericConstructor.abiName
						importedConstructor.returnType = importedStruct.semanticType
						importedConstructor.isConstructor = True
						importedConstructor.source = GenericIrSource(genericConstructor.source)
						importedConstructor.parameters = New TCompilerIrParameter[genericConstructor.parameters.length]
						For Local parameterIndex:Int = 0 Until genericConstructor.parameters.length
							Local sourceParameter:TGenericTemplateValueParameter = genericConstructor.parameters[parameterIndex]
							Local parameter:TCompilerIrParameter = New TCompilerIrParameter
							parameter.symbolId = importedConstructor.routineId + "_parameter_" + parameterIndex
							parameter.name = sourceParameter.name
							parameter.passingMode = sourceParameter.passingMode
							ConfigureGenericIrParameter(parameter, sourceParameter.semanticType)
							parameter.isOptional = sourceParameter.optional
							importedConstructor.parameters[parameterIndex] = parameter
						Next
						importedStruct.routines :+ [importedConstructor]
						If Not genericConstructor.parameters.length Then hasZeroArgumentStructConstructor = True
					Next
				End If
				If Not hasZeroArgumentStructConstructor Then
					Local defaultConstructor:TCompilerIrImportedStructRoutine = New TCompilerIrImportedStructRoutine
					defaultConstructor.routineId = importedStruct.importedStructId + "_default_new"
					defaultConstructor.name = "New"
					defaultConstructor.objectNewAbiName = unit.specialization.readableAbiName + "_New_ObjectNew"
					defaultConstructor.returnType = importedStruct.semanticType
					defaultConstructor.isConstructor = True
					importedStruct.routines :+ [defaultConstructor]
				End If
				IndexGenericTypeName(genericStructsByTypeName, importedStruct.semanticType, importedStruct)
				importedStructsByAbiName.Insert(importedStruct.abiName.ToLower(), importedStruct)
				result.importedStructs :+ [importedStruct]
				result.genericInstances :+ [unit.specialization.identityDigest]
				Continue
			End If
			Local importedClass:TCompilerIrImportedClass = TCompilerIrImportedClass(importedBySpecialization.ValueForKey(unit.specialization))
			If Not importedClass Then Continue
			BuildGenericStaticGlobals(unit, importedClass.semanticType)
			For Local irField:TCompilerGenericFieldIr = EachIn unit.ir.fields
				If irField.semanticType And (irField.semanticType.kind = TEMPLATE_TYPE_NAMED Or irField.semanticType.CanonicalName() = "string" Or irField.semanticType.CanonicalName() = "object") Then importedClass.hasManagedFields = True
				Local importedField:TCompilerIrImportedField = New TCompilerIrImportedField
				importedField.fieldId = importedClass.importedClassId + "_field_" + importedClass.fields.length
				importedField.declaringImportedClassId = importedClass.importedClassId
				importedField.name = irField.name
				importedField.abiName = irField.abiName
				ConfigureGenericIrField(importedField, irField.semanticType)
				importedField.source = GenericIrSource(irField.source)
				importedClass.fields :+ [importedField]
			Next
			For Local irMethod:TCompilerGenericMethodIr = EachIn unit.ir.methods
				Local importedMethod:TCompilerIrImportedMethod = New TCompilerIrImportedMethod
				importedMethod.methodId = importedClass.importedClassId + "_method_" + importedClass.methods.length
				importedMethod.declaringImportedClassId = importedClass.importedClassId
				importedMethod.name = irMethod.name
				importedMethod.abiName = irMethod.abiName
				importedMethod.slotName = irMethod.slotName
				importedMethod.isDestructor = irMethod.isDestructor
				importedMethod.isTypeFunction = irMethod.isTypeFunction
				Local returnShape:TCompilerIrParameter = New TCompilerIrParameter
				returnShape.symbolId = importedMethod.methodId + "_return"
				ConfigureGenericIrParameter(returnShape, irMethod.returnType)
				importedMethod.returnType = returnShape.semanticType
				importedMethod.callableReturnType = returnShape.callableReturnType
				importedMethod.callableReturnParameters = returnShape.callableParameters
				importedMethod.source = GenericIrSource(irMethod.source)
				importedMethod.parameters = New TCompilerIrParameter[irMethod.parameters.length]
				For Local parameterIndex:Int = 0 Until irMethod.parameters.length
					Local sourceParameter:TGenericTemplateValueParameter = irMethod.parameters[parameterIndex]
					Local parameter:TCompilerIrParameter = New TCompilerIrParameter
					parameter.symbolId = importedMethod.methodId + "_parameter_" + parameterIndex
					parameter.name = sourceParameter.name
					parameter.passingMode = sourceParameter.passingMode
					ConfigureGenericIrParameter(parameter, sourceParameter.semanticType)
					importedMethod.parameters[parameterIndex] = parameter
				Next
				importedClass.methods :+ [importedMethod]
				If irMethod.isDestructor Then Continue
				Local functionSlot:TCompilerIrClassFunctionSlot = New TCompilerIrClassFunctionSlot
				functionSlot.slotId = irMethod.slotName
				functionSlot.dispatchKey = irMethod.slotName
				functionSlot.declaringImportedClassId = importedClass.importedClassId
				functionSlot.receiverImportedClassId = importedClass.importedClassId
				functionSlot.functionId = importedMethod.methodId
				functionSlot.name = importedMethod.name
				functionSlot.abiName = importedMethod.abiName
				functionSlot.slotName = importedMethod.slotName
				functionSlot.returnType = importedMethod.returnType
				functionSlot.callableReturnType = importedMethod.callableReturnType
				functionSlot.callableReturnParameters = importedMethod.callableReturnParameters
				functionSlot.parameters = importedMethod.parameters
				functionSlot.isMethod = Not irMethod.isTypeFunction
				functionSlot.source = importedMethod.source
				importedClass.functionSlots :+ [functionSlot]
			Next
			Local hasZeroArgumentConstructor:Int
			If unit.ir.constructors.length Then
				For Local genericConstructor:TCompilerGenericMethodIr = EachIn unit.ir.constructors
					Local constructor:TCompilerIrImportedConstructor = New TCompilerIrImportedConstructor
					constructor.constructorId = importedClass.importedClassId + "_new_" + TCompilerStableDigest.Sha256(genericConstructor.signatureKey)[..16]
					constructor.declaringImportedClassId = importedClass.importedClassId
					constructor.abiName = unit.specialization.readableAbiName + "_ctor"
					constructor.objectNewAbiName = genericConstructor.abiName
					constructor.parameters = New TCompilerIrParameter[genericConstructor.parameters.length]
					For Local parameterIndex:Int = 0 Until genericConstructor.parameters.length
						Local sourceParameter:TGenericTemplateValueParameter = genericConstructor.parameters[parameterIndex]
						Local parameter:TCompilerIrParameter = New TCompilerIrParameter
						parameter.name = sourceParameter.name
						parameter.passingMode = sourceParameter.passingMode
						ConfigureGenericIrParameter(parameter, sourceParameter.semanticType)
						parameter.isOptional = sourceParameter.optional
						constructor.parameters[parameterIndex] = parameter
					Next
					importedClass.constructors :+ [constructor]
					If Not genericConstructor.parameters.length Then hasZeroArgumentConstructor = True
				Next
			End If
			If Not hasZeroArgumentConstructor Then
				Local constructor:TCompilerIrImportedConstructor = New TCompilerIrImportedConstructor
				constructor.constructorId = importedClass.importedClassId + "_default_new"
				constructor.declaringImportedClassId = importedClass.importedClassId
				constructor.abiName = unit.specialization.readableAbiName + "_ctor"
				constructor.objectNewAbiName = unit.specialization.readableAbiName + "_New"
				importedClass.constructors :+ [constructor]
			End If
			result.genericInstances :+ [unit.specialization.identityDigest]
		Next
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.specialization Or Not unit.ir Then Continue
			If unit.ir.isInterface Then
				Local genericInterface:TCompilerIrInterface = TCompilerIrInterface(importedBySpecialization.ValueForKey(unit.specialization))
				If Not genericInterface Then Continue
				For Local inheritedInterfaceNode:TGenericSpecializationNode = EachIn unit.ir.inheritedInterfaces
					Local inheritedInterface:TCompilerIrInterface = TCompilerIrInterface(importedBySpecialization.ValueForKey(inheritedInterfaceNode))
					If inheritedInterface Then genericInterface.baseInterfaceIds :+ [inheritedInterface.interfaceId]
				Next
				Continue
			End If
			If unit.ir.isStruct Then
				Local importedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedBySpecialization.ValueForKey(unit.specialization))
				If Not importedStruct Then Continue
				For Local fieldIndex:Int = 0 Until unit.ir.fields.length
					Local genericField:TCompilerGenericFieldIr = unit.ir.fields[fieldIndex]
					Local fieldType:TTemplateTypeReference = genericField.semanticType
					If fieldType And fieldType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then fieldType = fieldType.elementType
					Local target:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(fieldType, unit.ir)
					If Not target Or target.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Continue
					Local nestedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedBySpecialization.ValueForKey(target))
					If nestedStruct Then
						If genericField.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
							importedStruct.fields[fieldIndex].staticArrayImportedStructId = nestedStruct.importedStructId
						Else
							importedStruct.fields[fieldIndex].importedStructId = nestedStruct.importedStructId
						End If
					End If
				Next
				Continue
			End If
			Local importedClass:TCompilerIrImportedClass = TCompilerIrImportedClass(importedBySpecialization.ValueForKey(unit.specialization))
			If Not importedClass Then Continue
			If unit.ir.baseSpecialization Then
				Local importedBase:TCompilerIrImportedClass = TCompilerIrImportedClass(importedBySpecialization.ValueForKey(unit.ir.baseSpecialization))
				If importedBase Then importedClass.baseImportedClassId = importedBase.importedClassId
			End If
			For Local implementedInterfaceNode:TGenericSpecializationNode = EachIn unit.ir.implementedInterfaces
				Local implementedInterface:TCompilerIrInterface = TCompilerIrInterface(importedBySpecialization.ValueForKey(implementedInterfaceNode))
				If implementedInterface Then importedClass.implementedInterfaceIds :+ [implementedInterface.interfaceId]
			Next
			For Local fieldIndex:Int = 0 Until unit.ir.fields.length
				Local owner:TCompilerIrImportedClass = TCompilerIrImportedClass(importedBySpecialization.ValueForKey(unit.ir.fields[fieldIndex].declaringSpecialization))
				If owner Then importedClass.fields[fieldIndex].declaringImportedClassId = owner.importedClassId
			Next
			Local functionSlotIndex:Int
			For Local methodIndex:Int = 0 Until unit.ir.methods.length
				Local genericMethod:TCompilerGenericMethodIr = unit.ir.methods[methodIndex]
				Local owner:TCompilerIrImportedClass = TCompilerIrImportedClass(importedBySpecialization.ValueForKey(genericMethod.declaringSpecialization))
				If owner Then
					importedClass.methods[methodIndex].declaringImportedClassId = owner.importedClassId
					If Not genericMethod.isDestructor Then
						importedClass.functionSlots[functionSlotIndex].declaringImportedClassId = owner.importedClassId
						importedClass.functionSlots[functionSlotIndex].receiverImportedClassId = owner.importedClassId
					End If
				End If
				If Not genericMethod.isDestructor Then functionSlotIndex :+ 1
			Next
		Next
		Local managedChanged:Int = True
		While managedChanged
			managedChanged = False
			For Local importedStruct:TCompilerIrImportedStruct = EachIn result.importedStructs
				If importedStruct.containsManagedReferences Then Continue
				For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
					Local nestedImportedStructId:String = importedField.importedStructId
					If importedField.staticArrayImportedStructId.length Then nestedImportedStructId = importedField.staticArrayImportedStructId
					If Not nestedImportedStructId.length Then Continue
					Local nestedStruct:TCompilerIrImportedStruct = ImportedStructByIrId(nestedImportedStructId)
					If nestedStruct And nestedStruct.containsManagedReferences Then
						importedStruct.containsManagedReferences = True
						managedChanged = True
						Exit
					End If
				Next
			Next
		Wend
	End Method

	Method BuildGenericStaticGlobals(unit:TCompilerGenericUnit, semanticType:String)
		If Not unit Or Not unit.ir Or Not unit.specialization Then Return
		For Local staticField:TCompilerGenericFieldIr = EachIn unit.ir.staticFields
			Local externalGlobal:TCompilerIrExternalGlobal = New TCompilerIrExternalGlobal
			externalGlobal.symbolId = "extg" + nextExternalGlobalId
			nextExternalGlobalId :+ 1
			externalGlobal.sourceName = staticField.name
			externalGlobal.abiName = staticField.abiName
			externalGlobal.originModule = unit.specialization.artifact.identity.moduleName
			externalGlobal.source = GenericIrSource(staticField.source)
			externalGlobal.isPublished = True
			Local shape:TCompilerIrParameter = New TCompilerIrParameter
			ConfigureGenericIrParameter(shape, staticField.semanticType)
			externalGlobal.semanticType = shape.semanticType
			externalGlobal.callableReturnType = shape.callableReturnType
			externalGlobal.callableParameters = shape.callableParameters
			externalGlobal.isThreadedGlobal = staticField.isThreadedGlobal
			genericStaticGlobalsByKey.Insert(GenericStaticGlobalKey(semanticType, staticField.name), externalGlobal)
			result.externalGlobals :+ [externalGlobal]
		Next
	End Method

	Function GenericStaticGlobalKey:String(semanticType:String, memberName:String)
		Return semanticType.ToLower() + "::" + memberName.ToLower()
	End Function

	Method ResolveGenericStructRuntimeLayouts()
		' Application-local Struct arguments cross into separately compiled generic
		' specialization units. Expose their stable layout and Array support ABI in
		' the owning source header just as for a public field layout.
		If genericPlan Then
			For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
				If Not unit Or Not unit.specialization Then Continue
				For Local argument:TTemplateTypeReference = EachIn unit.specialization.key.typeArguments
					ExposeGenericRuntimeStructArgument(argument)
				Next
				For Local argument:TTemplateTypeReference = EachIn unit.specialization.key.containingTypeArguments
					ExposeGenericRuntimeStructArgument(argument)
				Next
			Next
		End If
		For Local importedStruct:TCompilerIrImportedStruct = EachIn result.importedStructs
			If Not importedStruct.isGenericSpecialization Then Continue
			For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
				Local runtimeTypeName:String = importedField.semanticType
				Local isStaticArray:Int = importedField.isStaticArray
				If isStaticArray Then runtimeTypeName = importedField.staticArrayElementType
				If Not runtimeTypeName.ToLower().StartsWith("@runtime-struct:") Then Continue
				Local runtimeAbiName:String = runtimeTypeName[16..]
				For Local sourceStruct:TCompilerIrStruct = EachIn result.structs
					If sourceStruct.abiName.ToLower() <> runtimeAbiName.ToLower() Then Continue
					If isStaticArray Then
						importedField.staticArrayStructId = sourceStruct.structId
					Else
						importedField.structId = sourceStruct.structId
					End If
					If sourceStruct.containsManagedReferences Then importedStruct.containsManagedReferences = True
					Exit
				Next
			Next
		Next
		Local managedChanged:Int = True
		While managedChanged
			managedChanged = False
			For Local importedStruct:TCompilerIrImportedStruct = EachIn result.importedStructs
				If Not importedStruct.isGenericSpecialization Or importedStruct.containsManagedReferences Then Continue
				For Local importedField:TCompilerIrImportedField = EachIn importedStruct.fields
					Local sourceStructId:String = importedField.structId
					If importedField.staticArrayStructId.length Then sourceStructId = importedField.staticArrayStructId
					If sourceStructId.length Then
						Local sourceStruct:TCompilerIrStruct
						For Local candidate:TCompilerIrStruct = EachIn result.structs
							If candidate.structId = sourceStructId Then sourceStruct = candidate; Exit
						Next
						If sourceStruct And sourceStruct.containsManagedReferences Then
							importedStruct.containsManagedReferences = True
							managedChanged = True
							Exit
						End If
					End If
					Local nestedImportedId:String = importedField.importedStructId
					If importedField.staticArrayImportedStructId.length Then nestedImportedId = importedField.staticArrayImportedStructId
					If nestedImportedId.length Then
						Local nestedImported:TCompilerIrImportedStruct = ImportedStructByIrId(nestedImportedId)
						If nestedImported And nestedImported.containsManagedReferences Then
							importedStruct.containsManagedReferences = True
							managedChanged = True
							Exit
						End If
					End If
				Next
			Next
		Wend
	End Method

	Method ExposeGenericRuntimeStructArgument(value:TTemplateTypeReference)
		If Not value Then Return
		If value.elementType Then ExposeGenericRuntimeStructArgument(value.elementType)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			ExposeGenericRuntimeStructArgument(argument)
		Next
		If value.runtimeKind <> TEMPLATE_RUNTIME_STRUCT Or Not value.runtimeAbiName.length Then Return
		For Local sourceStruct:TCompilerIrStruct = EachIn result.structs
			If sourceStruct.abiName.ToLower() <> value.runtimeAbiName.ToLower() Then Continue
			ExposeStructLayout(sourceStruct)
			Return
		Next
	End Method

	Function GenericSemanticTypeName:String(node:TGenericSpecializationNode)
		Local result:String = node.artifact.identity.qualifiedName + "<"
		For Local index:Int = 0 Until node.key.typeArguments.length
			If index Then result :+ ", "
			Local argument:TTemplateTypeReference = node.key.typeArguments[index]
			result :+ GenericArgumentDisplayName(argument)
		Next
		Return result + ">"
	End Function

	Function IndexGenericTypeName(index:TMap, semanticType:String, value:Object)
		If Not index Or Not semanticType.length Or Not value Then Return
		index.Insert(semanticType.ToLower(), value)
		Local argumentStart:Int = semanticType.Find("<")
		If argumentStart < 0 Then Return
		Local ownerName:String = semanticType[..argumentStart]
		Local separator:Int = ownerName.FindLast(".")
		If separator >= 0 Then index.Insert((ownerName[separator + 1..] + semanticType[argumentStart..]).ToLower(), value)
	End Function

	Function GenericArgumentDisplayName:String(value:TTemplateTypeReference)
		If Not value Then Return "?"
		If value.kind = TEMPLATE_TYPE_BUILTIN Then Return CanonicalBuiltinDisplayName(value.symbolName)
		If value.kind = TEMPLATE_TYPE_POINTER Then Return GenericArgumentDisplayName(value.elementType) + " Ptr"
		If value.kind = TEMPLATE_TYPE_ARRAY Then
			Local suffix:String = "["
			For Local rankIndex:Int = 1 Until value.rank
				suffix :+ ","
			Next
			Return GenericArgumentDisplayName(value.elementType) + suffix + "]"
		End If
		If value.kind = TEMPLATE_TYPE_CLOSURE Then
			Local result:String = "Closure<"
			If value.elementType And value.elementType.CanonicalName() <> "void" Then result :+ GenericArgumentDisplayName(value.elementType)
			result :+ "("
			For Local index:Int = 0 Until value.arguments.length
				If index Then result :+ ", "
				Local parameterName:String = "arg" + index
				If index < value.callableParameterNames.length And value.callableParameterNames[index].length Then parameterName = value.callableParameterNames[index]
				result :+ parameterName + ":" + GenericArgumentDisplayName(value.arguments[index])
				If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then result :+ " Var"
			Next
			Return result + ")>"
		End If
		If value.kind <> TEMPLATE_TYPE_NAMED Then Return value.CanonicalName()
		Local result:String = value.symbolName
		If value.arguments.length Then
			result :+ "<"
			For Local index:Int = 0 Until value.arguments.length
				If index Then result :+ ", "
				result :+ GenericArgumentDisplayName(value.arguments[index])
			Next
			result :+ ">"
		End If
		Return result
	End Function

	Method CanonicalSemanticTypeName:String(value:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If builtin Then Return builtin.name.ToLower()
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If pointer Then Return CanonicalSemanticTypeName(pointer.elementType) + " ptr"
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then Return CanonicalSemanticTypeName(arrayType.elementType) + "[" + arrayType.rank + "]"
		Local fixedArrayType:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If fixedArrayType Then Return "staticarray " + CanonicalSemanticTypeName(fixedArrayType.elementType) + "[" + fixedArrayType.length + "]"
		Local callable:TCallableSemanticType = TCallableSemanticType(value)
		If callable Then
			Local callableName:String = "callable " + callable.callingConvention + " "
			If callable.returnType Then callableName :+ CanonicalSemanticTypeName(callable.returnType) Else callableName :+ "void"
			callableName :+ "("
			For Local index:Int = 0 Until callable.parameterTypes.length
				If index Then callableName :+ ","
				If index < callable.parameterModes.length And callable.parameterModes[index] = PARAMETER_PASS_VAR Then callableName :+ "var:"
				callableName :+ CanonicalSemanticTypeName(callable.parameterTypes[index])
			Next
			Return callableName + ")"
		End If
		Local closure:TClosureSemanticType = TClosureSemanticType(value)
		If closure And closure.signature Then
			Local closureName:String = "closure "
			If closure.signature.returnType Then closureName :+ CanonicalSemanticTypeName(closure.signature.returnType) Else closureName :+ "void"
			closureName :+ "("
			For Local index:Int = 0 Until closure.signature.parameterTypes.length
				If index Then closureName :+ ","
				If index < closure.signature.parameterModes.length And closure.signature.parameterModes[index] = PARAMETER_PASS_VAR Then closureName :+ "var:"
				closureName :+ CanonicalSemanticTypeName(closure.signature.parameterTypes[index])
			Next
			Return closureName + ")"
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If Not named Or Not named.symbol Then Return TypeName(value).ToLower()
		Local moduleName:String = named.symbol.originModule
		' Quoted imported generic declarations may retain the relative import token
		' as semantic provenance. Their attached canonical artifact owns the stable
		' source identity used by specialization keys and generic routine matching.
		If named.symbol.genericTemplateArtifact And named.symbol.genericTemplateArtifact.identity Then moduleName = named.symbol.genericTemplateArtifact.identity.moduleName
		If Not moduleName.length And named.symbol.isImported And named.symbol.originPath.length Then moduleName = "source:" + named.symbol.originPath.Replace("\", "/")
		If Not moduleName.length And analysis And analysis.model Then moduleName = analysis.model.moduleName
		If Not moduleName.length And analysis And analysis.syntaxTree And analysis.syntaxTree.source Then moduleName = "source:" + analysis.syntaxTree.source.path.Replace("\", "/")
		If Not moduleName.length And named.symbol.originPath.length Then moduleName = "source:" + named.symbol.originPath.Replace("\", "/")
		Local result:String = moduleName.ToLower() + "::" + named.symbol.QualifiedName().ToLower()
		If named.typeArguments.length Then
			result :+ "<"
			For Local index:Int = 0 Until named.typeArguments.length
				If index Then result :+ ","
				result :+ CanonicalSemanticTypeName(named.typeArguments[index])
			Next
			result :+ ">"
		End If
		Return result
	End Method

	Method GenericIrTypeName:String(value:TTemplateTypeReference)
		If Not value Then Return ""
		If value.kind = TEMPLATE_TYPE_BUILTIN Then Return CanonicalBuiltinDisplayName(value.symbolName)
		If value.kind = TEMPLATE_TYPE_ARRAY And value.elementType Then
			Local suffix:String = "["
			For Local rankIndex:Int = 1 Until value.rank
				suffix :+ ","
			Next
			Return GenericIrTypeName(value.elementType) + suffix + "]"
		End If
		If value.kind = TEMPLATE_TYPE_CLOSURE Then
			Local result:String = "Closure<"
			If value.elementType And value.elementType.CanonicalName() <> "void" Then result :+ GenericIrTypeName(value.elementType)
			result :+ "("
			For Local index:Int = 0 Until value.arguments.length
				If index Then result :+ ","
				Local parameterName:String = "arg" + index
				If index < value.callableParameterNames.length And value.callableParameterNames[index].length Then parameterName = value.callableParameterNames[index]
				result :+ parameterName + ":" + GenericIrTypeName(value.arguments[index])
				If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then result :+ " Var"
			Next
			Return result + ")>"
		End If
		If value.kind = TEMPLATE_TYPE_NAMED Then
			Local specialization:TGenericSpecializationNode = NamedGenericSpecialization(value)
			If specialization Then Return GenericSemanticTypeName(specialization)
			If value.runtimeKind = TEMPLATE_RUNTIME_CLASS And value.runtimeAbiName.length Then
				EnsureImportedRuntimeClass(value.runtimeAbiName)
				Return "@runtime-class:" + value.runtimeAbiName
			End If
			If value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE And value.runtimeAbiName.length Then Return "@runtime-interface:" + value.runtimeAbiName
			If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT And value.runtimeAbiName.length Then
				EnsureImportedRuntimeStruct(value.runtimeAbiName)
				Return "@runtime-struct:" + value.runtimeAbiName
			End If
			If value.runtimeKind = TEMPLATE_RUNTIME_ENUM And value.runtimeAbiName.length Then Return "@runtime-enum:" + value.runtimeAbiName
		End If
		Return value.CanonicalName()
	End Method

	Method ConfigureGenericIrParameter(parameter:TCompilerIrParameter, value:TTemplateTypeReference)
		If Not parameter Or Not value Then Return
		parameter.semanticType = GenericIrTypeName(value)
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY And value.elementType Then
			parameter.isStaticArray = True
			parameter.staticArrayElementType = GenericIrTypeName(value.elementType)
			parameter.staticArrayLength = Int(value.staticArrayLength)
			If value.elementType.kind = TEMPLATE_TYPE_NAMED And value.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
				Local staticStruct:TCompilerIrImportedStruct = EnsureImportedRuntimeStruct(value.elementType.runtimeAbiName)
				If staticStruct Then parameter.staticArrayImportedStructId = staticStruct.importedStructId
			End If
			Return
		End If
		If value.kind <> TEMPLATE_TYPE_CALLABLE Or Not value.elementType Then Return
		parameter.callableReturnType = GenericIrTypeName(value.elementType)
		parameter.callableParameters = New TCompilerIrParameter[value.arguments.length]
		For Local index:Int = 0 Until value.arguments.length
			Local callableParameter:TCompilerIrParameter = New TCompilerIrParameter
			callableParameter.symbolId = parameter.symbolId + "_callable_" + index
			callableParameter.name = "p" + index
			callableParameter.passingMode = PARAMETER_PASS_VALUE
			If index < value.callableParameterModes.length Then callableParameter.passingMode = value.callableParameterModes[index]
			ConfigureGenericIrParameter(callableParameter, value.arguments[index])
			parameter.callableParameters[index] = callableParameter
		Next
	End Method

	Method ConfigureGenericIrField(fieldRecord:TCompilerIrImportedField, value:TTemplateTypeReference)
		If Not fieldRecord Or Not value Then Return
		fieldRecord.semanticType = GenericIrTypeName(value)
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY And value.elementType Then
			fieldRecord.isStaticArray = True
			fieldRecord.staticArrayElementType = GenericIrTypeName(value.elementType)
			fieldRecord.staticArrayLength = value.staticArrayLength
			If value.elementType.kind = TEMPLATE_TYPE_NAMED And value.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
				Local staticStruct:TCompilerIrImportedStruct = EnsureImportedRuntimeStruct(value.elementType.runtimeAbiName)
				If staticStruct Then fieldRecord.staticArrayImportedStructId = staticStruct.importedStructId
			End If
			Return
		End If
		If value.kind = TEMPLATE_TYPE_CALLABLE Then
			Local callableShape:TCompilerIrParameter = New TCompilerIrParameter
			callableShape.symbolId = fieldRecord.fieldId + "_callable"
			ConfigureGenericIrParameter(callableShape, value)
			fieldRecord.callableReturnType = callableShape.callableReturnType
			fieldRecord.callableParameters = callableShape.callableParameters
			Return
		End If
		If value.kind = TEMPLATE_TYPE_NAMED And value.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
			Local nestedStruct:TCompilerIrImportedStruct = EnsureImportedRuntimeStruct(value.runtimeAbiName)
			If nestedStruct Then fieldRecord.importedStructId = nestedStruct.importedStructId
		End If
	End Method

	Method GenericTypeContainsDirectManagedReference:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not value Then Return False
		If value.kind = TEMPLATE_TYPE_ARRAY Then Return True
		If value.kind = TEMPLATE_TYPE_CLOSURE Then Return True
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY Then Return GenericTypeContainsDirectManagedReference(value.elementType, ir)
		If value.kind = TEMPLATE_TYPE_BUILTIN Then
			Local builtinName:String = value.symbolName.ToLower()
			Return builtinName = "string" Or builtinName = "object"
		End If
		If value.kind <> TEMPLATE_TYPE_NAMED Then Return False
		If value.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then Return True
		Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
		Return referenced And referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT
	End Method

	Method EnsureImportedRuntimeClass:TCompilerIrImportedClass(abiName:String)
		If Not abiName.length Then Return Null
		Local existing:TCompilerIrImportedClass = TCompilerIrImportedClass(importedClassesByAbiName.ValueForKey(abiName.ToLower()))
		If existing Then Return existing
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return Null
		Return EnsureImportedRuntimeClassInScope(analysis.model.globalScope, abiName)
	End Method

	Method EnsureImportedRuntimeInterface:TCompilerIrInterface(abiName:String)
		If Not abiName.length Then Return Null
		Local existing:TCompilerIrInterface = TCompilerIrInterface(interfacesByAbiName.ValueForKey(abiName.ToLower()))
		If existing Then Return existing
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return Null
		Return EnsureImportedRuntimeInterfaceInScope(analysis.model.globalScope, abiName)
	End Method

	Method EnsureImportedRuntimeInterfaceInScope:TCompilerIrInterface(scope:TScope, abiName:String)
		If Not scope Then Return Null
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Or symbol.kind <> SYMBOL_INTERFACE Or Not symbol.isImported Then Continue
			If symbol.externalName.ToLower() = abiName.ToLower() Then Return EnsureInterfaceShell(symbol)
		Next
		For Local child:TScope = EachIn scope.children
			Local found:TCompilerIrInterface = EnsureImportedRuntimeInterfaceInScope(child, abiName)
			If found Then Return found
		Next
		Return Null
	End Method

	Method EnsureImportedRuntimeClassInScope:TCompilerIrImportedClass(scope:TScope, abiName:String)
		If Not scope Then Return Null
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Or symbol.kind <> SYMBOL_TYPE Or Not symbol.isImported Then Continue
			If symbol.externalName.ToLower() = abiName.ToLower() Then Return EnsureImportedClass(symbol)
		Next
		For Local child:TScope = EachIn scope.children
			Local found:TCompilerIrImportedClass = EnsureImportedRuntimeClassInScope(child, abiName)
			If found Then Return found
		Next
		Return Null
	End Method

	Method EnsureImportedRuntimeStruct:TCompilerIrImportedStruct(abiName:String)
		If Not abiName.length Then Return Null
		Local existing:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsByAbiName.ValueForKey(abiName.ToLower()))
		If existing Then Return existing
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return Null
		Return EnsureImportedRuntimeStructInScope(analysis.model.globalScope, abiName)
	End Method

	Method EnsureImportedRuntimeStructInScope:TCompilerIrImportedStruct(scope:TScope, abiName:String)
		If Not scope Then Return Null
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Or symbol.kind <> SYMBOL_STRUCT Or Not symbol.isImported Then Continue
			If symbol.externalName.ToLower() = abiName.ToLower() Then Return EnsureImportedStruct(symbol)
		Next
		For Local child:TScope = EachIn scope.children
			Local found:TCompilerIrImportedStruct = EnsureImportedRuntimeStructInScope(child, abiName)
			If found Then Return found
		Next
		Return Null
	End Method

	Method NamedGenericSpecialization:TGenericSpecializationNode(value:TTemplateTypeReference)
		If Not value Or Not genericPlan Or value.kind <> TEMPLATE_TYPE_NAMED Then Return Null
		If Not genericPlan.registry Then Return Null
		For Local candidate:TGenericSpecializationNode = EachIn genericPlan.registry.nodes
			If Not candidate Then Continue
			If candidate.artifact.identity.qualifiedName.ToLower() <> value.symbolName.ToLower() Then Continue
			If candidate.key.typeArguments.length <> value.arguments.length Then Continue
			Local matches:Int = True
			For Local index:Int = 0 Until value.arguments.length
				If candidate.key.typeArguments[index].CanonicalName() <> value.arguments[index].CanonicalName() Then matches = False; Exit
			Next
			If matches Then Return candidate
		Next
		Return Null
	End Method

	' A specialization rejected by generic lowering or C-unit emission remains
	' in the registry but deliberately has no executable unit. Application IR
	' must not reinterpret a reference to that missing unit as an unsupported
	' ordinary expression and produce a secondary diagnostic.
	Method MissingExecutableGenericSpecialization:Int(value:TSemanticType)
		If Not value Or Not genericPlan Or Not genericPlan.registry Then Return False
		Local semanticName:String = TypeName(value).ToLower()
		For Local candidate:TGenericSpecializationNode = EachIn genericPlan.registry.nodes
			If Not candidate Or candidate.IsAbiReferenceOnly() Then Continue
			If GenericSemanticTypeName(candidate).ToLower() <> semanticName Then Continue
			For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
				If unit And unit.specialization = candidate Then Return False
			Next
			Return True
		Next
		Return False
	End Method

	Method GenericIrSource:TCompilerSourceLocation(value:TTemplateSourceLocation)
		If Not value Then Return Null
		Local result:TCompilerSourceLocation = New TCompilerSourceLocation
		result.path = value.path
		result.span = TSourceSpan.Create(value.start, value.length)
		result.line = value.line
		result.column = value.column
		result.debugSourceId = RegisterDebugSource(value.path)
		Return result
	End Method

	Function CanonicalBuiltinDisplayName:String(name:String)
		Select name.ToLower()
			Case "byte" Return "Byte"
			Case "short" Return "Short"
			Case "int" Return "Int"
			Case "uint" Return "UInt"
			Case "long" Return "Long"
			Case "ulong" Return "ULong"
			Case "longint" Return "LongInt"
			Case "ulongint" Return "ULongInt"
			Case "size_t" Return "Size_T"
			Case "float" Return "Float"
			Case "double" Return "Double"
			Case "string" Return "String"
			Case "object" Return "Object"
			Case "void" Return "Void"
		End Select
		Return name
	End Function

	Method BuildEnumShells()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			If Not symbol Or symbol.kind <> SYMBOL_ENUM Or symbol.isImported Then Continue
			Local declaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(symbol.declaration)
			If Not declaration Then Continue
			Local underlyingType:TSemanticType = analysis.model.BuiltinType("Int")
			If declaration.underlyingType Then underlyingType = analysis.model.TypeOf(declaration.underlyingType)
			If Not IsSupportedEnumUnderlyingType(underlyingType) Then
				AddUnsupported("BMXC1101", "Enum underlying type '" + TypeName(underlyingType) + "' is outside the integral scalar slice", declaration)
				Continue
			End If
			Local irEnum:TCompilerIrEnum = New TCompilerIrEnum
			irEnum.enumId = "en" + nextEnumId
			nextEnumId :+ 1
			irEnum.name = symbol.name
			irEnum.semanticType = TypeName(symbol.declaredType)
			irEnum.underlyingType = TypeName(underlyingType)
			irEnum.abiName = TCompilerDirectMethodAbi.OwnerAbiName(analysis.model, symbol)
			irEnum.visibility = symbol.visibility
			irEnum.isFlags = declaration.flagsToken <> Null
			irEnum.isPublished = analysis.model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC
			irEnum.source = SourceOf(declaration)
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If Not member Or member.kind <> SYMBOL_ENUM_MEMBER Then Continue
				Local constant:TConstantValue = analysis.model.SymbolConstantValue(member)
				If Not constant Or constant.kind <> CONSTANT_VALUE_INTEGER Then
					AddUnsupported("BMXC1101", "Enum member '" + member.name + "' has no integral constant value", member.declaration)
					Continue
				End If
				Local value:TCompilerIrEnumValue = New TCompilerIrEnumValue
				value.name = member.name
				value.integerValue = constant.integerValue
				value.source = SourceOf(member.declaration)
				irEnum.values :+ [value]
			Next
			ConfigureEnumRuntime(irEnum, True)
			enumsBySymbol.Insert(symbol, irEnum)
			result.enums :+ [irEnum]
		Next
	End Method

	Method BuildFunctionLiteralShells(scope:TScope)
		If Not scope Then Return
		For Local child:TScope = EachIn scope.children
			If child And child.owner And TFunctionLiteralExpressionSyntax(child.owner.declaration) Then
				If Not HasOpenGenericOwner(child.parent) Then
					BuildRoutineShell(child.owner, Null)
				End If
			End If
			BuildFunctionLiteralShells(child)
		Next
	End Method

	Function HasOpenGenericOwner:Int(scope:TScope)
		While scope
			If scope.owner Then
				If scope.owner.genericArity > 0 Then Return True
				' Generic Type ownership is represented by the declaration header;
				' member routines themselves can have arity zero.
				Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(scope.owner.declaration)
				If typeDeclaration And typeDeclaration.header And typeDeclaration.header.genericParameters.length Then Return True
			End If
			scope = scope.parent
		Wend
		Return False
	End Function

	Method BuildImportedEnumShells()
		If Not analysis Or Not analysis.model Then Return
		For Local scope:TScope = EachIn analysis.model.importedScopes
			If Not scope Then Continue
			For Local symbol:TSymbol = EachIn scope.declaredSymbols
				If symbol And symbol.kind = SYMBOL_ENUM And symbol.isImported Then EnsureImportedEnum(symbol)
			Next
		Next
	End Method

	Method EnsureImportedEnum:TCompilerIrEnum(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ENUM Or Not symbol.isImported Then Return Null
		Local existing:TCompilerIrEnum = TCompilerIrEnum(enumsBySymbol.ValueForKey(symbol))
		If existing Then Return existing
		Local named:TNamedSemanticType = TNamedSemanticType(symbol.declaredType)
		If Not named Then
			AddUnsupported("BMXC1102", "Imported Enum '" + symbol.QualifiedName() + "' has no resolved semantic type", symbol.declaration)
			Return Null
		End If
		Local record:TInterfaceRecord = symbol.interfaceRecord
		Local underlyingType:TSemanticType
		If record And record.baseTypeSyntax Then underlyingType = analysis.model.TypeOf(record.baseTypeSyntax)
		If Not IsSupportedEnumUnderlyingType(underlyingType) Then
			AddUnsupported("BMXC1102", "Imported Enum '" + symbol.QualifiedName() + "' has an unsupported underlying type", symbol.declaration)
			Return Null
		End If
		If Not symbol.externalName.length Then
			AddUnsupported("BMXC1102", "Imported Enum '" + symbol.QualifiedName() + "' has no interface ABI identity", symbol.declaration)
			Return Null
		End If
		Local irEnum:TCompilerIrEnum = New TCompilerIrEnum
		irEnum.enumId = "en" + nextEnumId
		nextEnumId :+ 1
		irEnum.name = symbol.name
		irEnum.semanticType = TypeName(symbol.declaredType)
		irEnum.underlyingType = TypeName(underlyingType)
		irEnum.abiName = symbol.externalName
		irEnum.visibility = symbol.visibility
		irEnum.isFlags = record And record.flags.Contains("F")
		irEnum.isImported = True
		irEnum.originModule = symbol.originModule
		irEnum.source = SourceForSymbol(symbol)
		For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
			If Not member Or member.kind <> SYMBOL_ENUM_MEMBER Then Continue
			Local constant:TConstantValue = analysis.model.SymbolConstantValue(member)
			If Not constant Or constant.kind <> CONSTANT_VALUE_INTEGER Then
				AddUnsupported("BMXC1102", "Imported Enum member '" + member.name + "' has no integral constant value", member.declaration)
				Continue
			End If
			Local value:TCompilerIrEnumValue = New TCompilerIrEnumValue
			value.name = member.name
			value.integerValue = constant.integerValue
			value.source = SourceForSymbol(member)
			irEnum.values :+ [value]
		Next
		ConfigureEnumRuntime(irEnum, False)
		enumsBySymbol.Insert(symbol, irEnum)
		result.enums :+ [irEnum]
		Return irEnum
	End Method

	Method ConfigureEnumRuntime(irEnum:TCompilerIrEnum, ownsRuntimeData:Int)
		If Not irEnum Then Return
		Local descriptor:TCompilerIrEnumRuntimeDescriptor = New TCompilerIrEnumRuntimeDescriptor
		descriptor.runtimeName = irEnum.name
		descriptor.numericTypeTag = EnumRuntimeTypeTag(irEnum.underlyingType)
		descriptor.arrayTypeEncoding = "/" + irEnum.name
		descriptor.descriptorAbiName = irEnum.abiName + "_BBEnum_impl"
		descriptor.descriptorStorageAbiName = irEnum.abiName + "_BBEnum"
		descriptor.valuesAbiName = irEnum.abiName + "_values"
		descriptor.debugScopeAbiName = irEnum.abiName + "_scope"
		If irEnum.isFlags Then descriptor.maskAbiName = "bbEnum" + irEnum.abiName + "_Mask"
		descriptor.toStringAbiName = irEnum.abiName + "_ToString"
		descriptor.tryConvertAbiName = irEnum.abiName + "_TryConvert"
		descriptor.fromStringAbiName = irEnum.abiName + "_FromString"
		irEnum.runtimeDescriptor = descriptor
		If Not ownsRuntimeData Then Return
		For Local value:TCompilerIrEnumValue = EachIn irEnum.values
			value.nameStringLiteralId = RegisterStringValue(value.name, value.source).literalId
			value.ordinalStringLiteralId = RegisterStringValue(String(value.integerValue), value.source).literalId
		Next
	End Method

	Function EnumRuntimeTypeTag:String(underlyingType:String)
		Select underlyingType.ToLower()
			Case "byte" Return "b"
			Case "short" Return "s"
			Case "int" Return "i"
			Case "uint" Return "u"
			Case "long" Return "l"
			Case "ulong" Return "y"
			Case "size_t" Return "t"
			Case "longint" Return "v"
			Case "ulongint" Return "e"
		End Select
		Return ""
	End Function

	Method BuildInterfaceShells()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			If symbol And symbol.kind = SYMBOL_INTERFACE And Not symbol.isImported Then AddInterfaceShell(symbol)
		Next
		For Local symbol:TSymbol = EachIn interfaceSymbols
			CompleteInterfaceLayout(symbol)
		Next
	End Method

	Method PrepareDirectMethodLayoutAbis()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		Local visiting:TMap = New TMap
		IndexSourceRuntimeLayoutSymbols(analysis.model.globalScope)
		PrepareDirectMethodLayoutAbisInScope(analysis.model.globalScope, visiting)
		If genericPlan Then
			For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
				If Not unit Or Not unit.ir Then Continue
				For Local fieldRecord:TCompilerGenericFieldIr = EachIn unit.ir.fields
					If fieldRecord Then
						MarkTemplateRuntimeLayouts(fieldRecord.semanticType, visiting)
						MarkTemplateNodeRuntimeLayouts(fieldRecord.initializer, visiting)
					End If
				Next
				For Local fieldRecord:TCompilerGenericFieldIr = EachIn unit.ir.staticFields
					If fieldRecord Then
						MarkTemplateRuntimeLayouts(fieldRecord.semanticType, visiting)
						MarkTemplateNodeRuntimeLayouts(fieldRecord.initializer, visiting)
					End If
				Next
				For Local methodRecord:TCompilerGenericMethodIr = EachIn unit.ir.methods
					MarkTemplateRoutineRuntimeLayouts(methodRecord, visiting)
				Next
				For Local constructorRecord:TCompilerGenericMethodIr = EachIn unit.ir.constructors
					MarkTemplateRoutineRuntimeLayouts(constructorRecord, visiting)
				Next
				MarkTemplateRoutineRuntimeLayouts(unit.ir.routine, visiting)
			Next
		End If
	End Method

	Method IndexSourceRuntimeLayoutSymbols(scope:TScope)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Or symbol.isImported Or symbol.genericArity Then Continue
			If symbol.kind <> SYMBOL_TYPE And symbol.kind <> SYMBOL_STRUCT And symbol.kind <> SYMBOL_INTERFACE Then Continue
			Local abiName:String = TCompilerDirectMethodAbi.OwnerAbiName(analysis.model, symbol).ToLower()
			If abiName.length And Not sourceRuntimeLayoutSymbolsByAbi.Contains(abiName) Then sourceRuntimeLayoutSymbolsByAbi.Insert(abiName, symbol)
		Next
		For Local child:TScope = EachIn scope.children
			IndexSourceRuntimeLayoutSymbols(child)
		Next
	End Method

	Method PrepareDirectMethodLayoutAbisInScope(scope:TScope, visiting:TMap)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Or symbol.isImported Then Continue
			If TCompilerDirectMethodAbi.HasGenericMethod(symbol) Then MarkDirectMethodLayout(symbol, visiting)
			If (symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_STRUCT) And symbol.memberScope Then
				PrepareDirectMethodLayoutAbisInScope(symbol.memberScope, visiting)
			End If
		Next
	End Method

	Method MarkDirectMethodLayout(symbol:TSymbol, visiting:TMap)
		If Not symbol Or symbol.isImported Or symbol.genericArity Or directMethodLayoutSymbols.Contains(symbol) Or visiting.Contains(symbol) Then Return
		If symbol.kind <> SYMBOL_TYPE And symbol.kind <> SYMBOL_STRUCT And symbol.kind <> SYMBOL_INTERFACE Then Return
		visiting.Insert(symbol, symbol)
		directMethodLayoutSymbols.Insert(symbol, symbol)
		If symbol.kind = SYMBOL_TYPE Then
			Local baseType:TNamedSemanticType = TNamedSemanticType(ExplicitBaseType(symbol))
			If baseType And baseType.symbol Then MarkDirectMethodLayout(baseType.symbol, visiting)
		End If
		visiting.Remove(symbol)
	End Method

	Method MarkTemplateRoutineRuntimeLayouts(routine:TCompilerGenericMethodIr, visiting:TMap)
		If Not routine Then Return
		MarkTemplateRuntimeLayouts(routine.returnType, visiting)
		MarkTemplateRuntimeLayouts(routine.receiverType, visiting)
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			If parameter Then
				MarkTemplateRuntimeLayouts(parameter.semanticType, visiting)
				MarkTemplateNodeRuntimeLayouts(parameter.defaultValue, visiting)
			End If
		Next
		MarkTemplateNodeRuntimeLayouts(routine.body, visiting)
		For Local argument:TGenericTemplateNode = EachIn routine.delegationArguments
			MarkTemplateNodeRuntimeLayouts(argument, visiting)
		Next
	End Method

	Method MarkTemplateNodeRuntimeLayouts(node:TGenericTemplateNode, visiting:TMap)
		If Not node Then Return
		MarkTemplateRuntimeLayouts(node.semanticType, visiting)
		For Local child:TGenericTemplateNode = EachIn node.children
			MarkTemplateNodeRuntimeLayouts(child, visiting)
		Next
	End Method

	Method MarkTemplateRuntimeLayouts(value:TTemplateTypeReference, visiting:TMap)
		If Not value Then Return
		If value.runtimeAbiName.length And value.runtimeKind <> TEMPLATE_RUNTIME_NONE Then
			Local symbol:TSymbol = FindSourceRuntimeLayoutSymbol(value.runtimeAbiName)
			If symbol Then MarkDirectMethodLayout(symbol, visiting)
		End If
		MarkTemplateRuntimeLayouts(value.elementType, visiting)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			MarkTemplateRuntimeLayouts(argument, visiting)
		Next
	End Method

	Method FindSourceRuntimeLayoutSymbol:TSymbol(abiName:String)
		If Not abiName.length Then Return Null
		Return TSymbol(sourceRuntimeLayoutSymbolsByAbi.ValueForKey(abiName.ToLower()))
	End Method

	Method BuildStructShells()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			If Not symbol Or symbol.kind <> SYMBOL_STRUCT Or symbol.isImported Then Continue
			Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
			If Not declaration Then Continue
			If declaration.header And declaration.header.genericParameters.length Then
				If GenericStructTemplatePlanned(symbol) Then Continue
				AddUnsupported("BMXC1190", "Generic Structs require canonical specialization lowering", declaration)
				Continue
			End If
			Local irStruct:TCompilerIrStruct = New TCompilerIrStruct
			irStruct.structId = "st" + nextStructId
			nextStructId :+ 1
			irStruct.name = symbol.name
			Local isExternStruct:Int = IsExternStructDeclaration(declaration)
			irStruct.hasStableLocalAbi = isExternStruct Or (directMethodLayoutSymbols.Contains(symbol) And Not (analysis.model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC))
			If isExternStruct Then
				' A Struct declared inside Extern names a native C layout. Its
				' source name is the struct tag ABI; module qualification would
				' make the BlitzMax declaration incompatible with the native
				' routine that fills or consumes it.
				irStruct.abiName = symbol.name
			Else If irStruct.hasStableLocalAbi Then
				irStruct.abiName = TCompilerDirectMethodAbi.OwnerAbiName(analysis.model, symbol)
			Else
				irStruct.abiName = TCompilerAbiNamer.ClassName(analysis.model, symbol, irStruct.structId)
			End If
			irStruct.semanticType = TypeName(symbol.declaredType)
			irStruct.visibility = symbol.visibility
			irStruct.isPublished = analysis.model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC
			irStruct.source = SourceOf(declaration)
			irStruct.metadata = MetadataOf(symbol)
			structsBySymbol.Insert(symbol, irStruct)
			result.structs :+ [irStruct]
			structSymbols :+ [symbol]
		Next
		For Local symbol:TSymbol = EachIn structSymbols
			CompleteStructLayout(symbol)
		Next
		For Local symbol:TSymbol = EachIn structSymbols
			Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structsBySymbol.ValueForKey(symbol))
			If irStruct And irStruct.isPublished Then ExposeStructLayout(irStruct)
		Next
	End Method

	Method IsExternStructDeclaration:Int(declaration:TTypeDeclarationSyntax)
		If Not declaration Then Return False
		For Local document:TSourceDocumentModel = EachIn documents
			If Not document Or Not document.tree Or Not document.tree.root Then Continue
			For Local node:TSyntaxNode = EachIn document.tree.root.members
				Local external:TExternBlockSyntax = TExternBlockSyntax(node)
				If external And external.body And ExternStatementsContain(external.body.statements, declaration) Then Return True
			Next
		Next
		Return False
	End Method

	Method ExternStatementsContain:Int(nodes:TSyntaxNode[], declaration:TTypeDeclarationSyntax)
		For Local node:TSyntaxNode = EachIn nodes
			If node = declaration Then Return True
		Next
		Return False
	End Method

	Method GenericStructTemplatePlanned:Int(symbol:TSymbol)
		If Not symbol Or Not genericPlan Then Return False
		If genericPlan.specializedSourceSymbols.Contains(symbol) Then Return True
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.ir Or Not unit.ir.isStruct Then Continue
			If unit.specialization.artifact.identity.qualifiedName.ToLower() = symbol.QualifiedName().ToLower() Then Return True
			If unit.specialization.artifact.identity.qualifiedName.ToLower() = symbol.name.ToLower() Then Return True
		Next
		Return False
	End Method

	Method ExposeStructLayout(irStruct:TCompilerIrStruct)
		If Not irStruct Then Return
		If Not irStruct.isPublished And analysis And analysis.model And analysis.model.moduleName.length Then
			For Local symbol:TSymbol = EachIn structSymbols
				If TCompilerIrStruct(structsBySymbol.ValueForKey(symbol)) <> irStruct Then Continue
				' A non-public Struct embedded in a public value/object layout is a
				' compiler-visible ABI dependency. Give it a module-stable C identity
				' while retaining its source visibility in the compact interface.
				irStruct.abiName = TCompilerAbiNamer.PublishedLayoutTypeName(analysis.model, symbol)
				irStruct.hasStableLocalAbi = True
				For Local irField:TCompilerIrStructField = EachIn irStruct.fields
					irField.abiName = TCompilerAbiNamer.FieldName(irStruct.abiName, irField.name)
				Next
				Exit
			Next
		End If
		irStruct.isPublished = True
		For Local irField:TCompilerIrStructField = EachIn irStruct.fields
			Local nestedId:String = irField.structId
			If irField.staticArrayStructId.length Then nestedId = irField.staticArrayStructId
			If Not nestedId.length Then Continue
			Local nested:TCompilerIrStruct = StructById(nestedId)
			If nested And Not nested.isPublished Then ExposeStructLayout(nested)
		Next
	End Method

	Method CompleteStructLayout(symbol:TSymbol)
		If Not symbol Or completedStructLayouts.Contains(symbol) Then Return
		If visitingStructLayouts.Contains(symbol) Then
			AddUnsupported("BMXC1192", "Struct value layout cycle involving '" + symbol.name + "'", symbol.declaration)
			Return
		End If
		Local irStruct:TCompilerIrStruct = TCompilerIrStruct(structsBySymbol.ValueForKey(symbol))
		If Not irStruct Then Return
		visitingStructLayouts.Insert(symbol, symbol)
		If symbol.memberScope Then
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If Not member Or member.kind <> SYMBOL_FIELD Then Continue
				Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(member.declaredType)
				Local fieldElementType:TSemanticType = member.declaredType
				If staticArrayType Then fieldElementType = staticArrayType.elementType
				Local nestedStruct:TCompilerIrStruct
				Local nestedImportedStruct:TCompilerIrImportedStruct
				Local named:TNamedSemanticType = TNamedSemanticType(fieldElementType)
				If named And named.symbol And named.symbol.kind = SYMBOL_STRUCT Then
					If named.symbol.isImported Then
						' Preserve the closed semantic type here. Passing only the imported
						' declaration symbol loses its type arguments and incorrectly asks
						' the ordinary imported-Struct path to lay out an open generic.
						nestedImportedStruct = ImportedStructForType(fieldElementType)
					Else
						CompleteStructLayout(named.symbol)
						nestedStruct = TCompilerIrStruct(structsBySymbol.ValueForKey(named.symbol))
					End If
				End If
				Local supportedField:Int
				If staticArrayType Then
					supportedField = IsSupportedStaticArrayType(staticArrayType)
				Else
					supportedField = nestedStruct <> Null Or nestedImportedStruct <> Null
					If Not supportedField Then supportedField = IsSupportedStructFieldType(member.declaredType)
				End If
				If Not supportedField Then
					AddUnsupported("BMXC1193", "Struct field type '" + TypeName(member.declaredType) + "' is outside the scalar, StaticArray, and nested-Struct layout slice", member.declaration)
					Continue
				End If
				If staticArrayType And nestedImportedStruct And Not ImportedStructHasDefaultHelper(nestedImportedStruct) Then
					AddUnsupported("BMXC1021", "Imported Struct StaticArray field element type '" + TypeName(fieldElementType) + "' has no published zero-argument value helper", member.declaration)
					Continue
				End If
				Local irField:TCompilerIrStructField = New TCompilerIrStructField
				irField.fieldId = "sf" + irStruct.fields.length
				irField.name = member.name
				irField.abiName = TCompilerAbiNamer.FieldName(irStruct.abiName, member.name)
				irField.semanticType = TypeName(member.declaredType)
				Local callableType:TCallableSemanticType = TCallableSemanticType(member.declaredType)
				If callableType Then
					irField.callableReturnType = TypeName(callableType.returnType)
					irField.callableParameters = CallableParameters(callableType)
					irField.callableCallingConvention = callableType.callingConvention
				End If
				Local fieldArrayType:TArraySemanticType = TArraySemanticType(member.declaredType)
				Local fieldArrayCallable:TCallableSemanticType
				If fieldArrayType Then fieldArrayCallable = TCallableSemanticType(fieldArrayType.elementType)
				If fieldArrayCallable Then
					irField.arrayCallableReturnType = TypeName(fieldArrayCallable.returnType)
					irField.arrayCallableParameters = CallableParameters(fieldArrayCallable)
					irField.arrayCallableCallingConvention = fieldArrayCallable.callingConvention
					irField.arrayCallableRank = fieldArrayType.rank
				End If
				Local fieldDeclarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(member.declaration)
				If fieldDeclarator And fieldDeclarator.callableType Then
					If callableType Then ApplyCallableParameterNames(irField.callableParameters, fieldDeclarator.callableType)
					If fieldArrayCallable Then ApplyCallableParameterNames(irField.arrayCallableParameters, fieldDeclarator.callableType)
				End If
				If staticArrayType Then
					irField.isStaticArray = True
					irField.staticArrayElementType = TypeName(fieldElementType)
					irField.staticArrayLength = staticArrayType.length
					If nestedStruct Then irField.staticArrayStructId = nestedStruct.structId
					If nestedImportedStruct Then irField.staticArrayImportedStructId = nestedImportedStruct.importedStructId
				Else
					If nestedStruct Then irField.structId = nestedStruct.structId
					If nestedImportedStruct Then irField.importedStructId = nestedImportedStruct.importedStructId
				End If
				irField.visibility = member.visibility
				irField.isReadOnly = member.isReadOnly
				irField.source = SourceOf(member.declaration)
				irField.metadata = MetadataOf(member)
				If Not staticArrayType And IsManagedReferenceType(member.declaredType) Then irStruct.containsManagedReferences = True
				If staticArrayType And IsManagedReferenceType(fieldElementType) Then irStruct.containsManagedReferences = True
				If nestedStruct And nestedStruct.containsManagedReferences Then irStruct.containsManagedReferences = True
				If nestedImportedStruct And nestedImportedStruct.containsManagedReferences Then irStruct.containsManagedReferences = True
				structFieldsBySymbol.Insert(member, irField)
				irStruct.fields :+ [irField]
			Next
		End If
		visitingStructLayouts.Remove(symbol)
		completedStructLayouts.Insert(symbol, symbol)
	End Method

	Method AddInterfaceShell:TCompilerIrInterface(symbol:TSymbol)
		If Not symbol Then Return Null
		Local known:TCompilerIrInterface = TCompilerIrInterface(interfacesBySymbol.ValueForKey(symbol))
		If known Then Return known
		Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
		Local isGeneric:Int = symbol.genericArity <> 0
		If Not symbol.isImported And declaration And declaration.header Then isGeneric = declaration.header.genericParameters.length > 0
		If isGeneric Then
			If GenericInterfaceTemplatePlanned(symbol) Then Return Null
			AddUnsupported("BMXC1160", "Generic Interfaces require canonical specialization lowering", declaration)
			Return Null
		End If
		If Not symbol.isImported And (Not declaration Or Not declaration.header) Then Return Null
		If symbol.isImported And symbol.externalName.length Then
			Local existing:TCompilerIrInterface = TCompilerIrInterface(interfacesByAbiName.ValueForKey(symbol.externalName.ToLower()))
			If existing Then
				interfacesBySymbol.Insert(symbol, existing)
				Return existing
			End If
		End If
		Local irInterface:TCompilerIrInterface = New TCompilerIrInterface
		irInterface.interfaceId = "if" + nextInterfaceId
		nextInterfaceId :+ 1
		irInterface.name = symbol.name
		irInterface.semanticType = TypeName(symbol.declaredType)
		irInterface.visibility = symbol.visibility
		irInterface.isImported = symbol.isImported
		irInterface.isExternInterface = symbol.isExternal
		irInterface.abiName = symbol.externalName
		If irInterface.isExternInterface And Not irInterface.abiName.length Then irInterface.abiName = symbol.name
		If Not irInterface.isExternInterface And Not irInterface.isImported And analysis.model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC Then irInterface.abiName = TCompilerAbiNamer.ClassName(analysis.model, symbol, irInterface.interfaceId)
		If Not irInterface.isImported And Not irInterface.abiName.length And directMethodLayoutSymbols.Contains(symbol) Then irInterface.abiName = TCompilerDirectMethodAbi.OwnerAbiName(analysis.model, symbol)
		If irInterface.abiName.length And Not irInterface.isExternInterface Then irInterface.methodsAbiName = irInterface.abiName + "_methods"
		If irInterface.isImported And irInterface.methodsAbiName.length Then irInterface.methodsLayoutOwnedExternally = True
		If irInterface.isImported And irInterface.isExternInterface Then irInterface.methodsLayoutOwnedExternally = True
		irInterface.originModule = symbol.originModule
		irInterface.source = SourceForSymbol(symbol)
		irInterface.metadata = MetadataOf(symbol)
		interfacesBySymbol.Insert(symbol, irInterface)
		If irInterface.abiName.length Then interfacesByAbiName.Insert(irInterface.abiName.ToLower(), irInterface)
		interfaceSymbols :+ [symbol]
		result.interfaces :+ [irInterface]
		If symbol.isImported And Not irInterface.abiName.length Then AddUnsupported("BMXC1166", "Imported Interface '" + symbol.QualifiedName() + "' has no interface ABI name", symbol.declaration)
		If symbol.isImported And irInterface.abiName.length And TCompilerAbiNamer.Sanitize(irInterface.abiName) <> irInterface.abiName Then AddUnsupported("BMXC1167", "Imported Interface ABI name '" + irInterface.abiName + "' requires an explicit linker-name representation", symbol.declaration)
		Return irInterface
	End Method

	Method GenericInterfaceTemplatePlanned:Int(symbol:TSymbol)
		If Not symbol Or Not genericPlan Then Return False
		If genericPlan.specializedSourceSymbols.Contains(symbol) Then Return True
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.ir Or Not unit.ir.isInterface Then Continue
			If unit.specialization.artifact.identity.qualifiedName.ToLower() = symbol.QualifiedName().ToLower() Then Return True
			If unit.specialization.artifact.identity.qualifiedName.ToLower() = symbol.name.ToLower() Then Return True
		Next
		Return False
	End Method

	Method EnsureInterfaceShell:TCompilerIrInterface(symbol:TSymbol)
		Local existing:TCompilerIrInterface = TCompilerIrInterface(interfacesBySymbol.ValueForKey(symbol))
		If existing Then Return existing
		Local irInterface:TCompilerIrInterface = AddInterfaceShell(symbol)
		If irInterface Then CompleteInterfaceLayout(symbol)
		Return irInterface
	End Method

	Method CompleteInterfaceLayout(symbol:TSymbol)
		If Not symbol Or completedInterfaceLayouts.Contains(symbol) Then Return
		Local irInterface:TCompilerIrInterface = TCompilerIrInterface(interfacesBySymbol.ValueForKey(symbol))
		If Not irInterface Then Return
		Local methodMap:TMap = New TMap
		interfaceMethodsByInterface.Insert(irInterface, methodMap)
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(symbol)
		If info Then
			' Compact snapshots encode the first Interface parent after "^" and
			' any additional parents after "@". Source declarations retain all
			' Extends parents as base edges, so flatten both groups here.
			Local interfaceEdges:TInheritanceEdge[] = info.baseEdges + info.interfaceEdges
			For Local edge:TInheritanceEdge = EachIn interfaceEdges
				If IsInterfaceRootType(edge.semanticType) Then Continue
				Local namedBase:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
				Local baseInterface:TCompilerIrInterface
				If namedBase And namedBase.symbol Then baseInterface = EnsureInterfaceShell(namedBase.symbol)
				If Not baseInterface Then
					AddUnsupported("BMXC1161", "Interface inheritance requires a non-generic source or imported Interface with a published ABI", edge.syntax)
					Continue
				End If
				CompleteInterfaceLayout(namedBase.symbol)
				irInterface.baseInterfaceIds :+ [baseInterface.interfaceId]
				For Local baseMethod:TCompilerIrInterfaceMethod = EachIn baseInterface.methods
					Local requirement:TSymbol = TSymbol(interfaceMethodSymbols.ValueForKey(baseMethod))
					If Not requirement Or methodMap.Contains(requirement) Then Continue
					Local inheritedMethod:TCompilerIrInterfaceMethod = CopyInterfaceMethod(baseMethod, "im" + irInterface.methods.length)
					methodMap.Insert(requirement, inheritedMethod)
					interfaceMethodSymbols.Insert(inheritedMethod, requirement)
					irInterface.methods :+ [inheritedMethod]
				Next
			Next
		End If
		If symbol.memberScope Then
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If Not member Or member.kind <> SYMBOL_ROUTINE Then Continue
				If member.genericArity Then
					' Closed generic Interface methods are application-owned typed
					' dispatch units. They deliberately consume no fixed Interface slot.
					Continue
				End If
				If Not IsSupportedReturnType(member.declaredType) Then
					AddUnsupported("BMXC1163", "Interface method return type '" + TypeName(member.declaredType) + "' is outside the current ABI slice", member.declaration)
					Continue
				End If
				Local interfaceMethod:TCompilerIrInterfaceMethod = New TCompilerIrInterfaceMethod
				interfaceMethod.slotId = "im" + irInterface.methods.length
				interfaceMethod.name = member.name
				interfaceMethod.declaringInterfaceId = irInterface.interfaceId
				interfaceMethod.abiName = member.externalName
				If Not irInterface.isExternInterface And Not member.isImported And irInterface.abiName.length Then interfaceMethod.abiName = TCompilerAbiNamer.RoutineName(analysis.model, member, interfaceMethod.slotId)
				interfaceMethod.slotAbiName = PublishedInterfaceSlotName(irInterface, interfaceMethod)
				interfaceMethod.returnType = TypeName(member.declaredType)
				interfaceMethod.implementationKind = member.interfaceMethodKind
				If member.isImported And member.interfaceMethodKind = INTERFACE_METHOD_DEFAULT Then interfaceMethod.defaultImplementationAbiName = member.externalName
				Local interfaceDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(member.declaration)
				Local callableReturn:TCallableSemanticType = TCallableSemanticType(member.declaredType)
				If callableReturn Then
					interfaceMethod.callableReturnType = TypeName(callableReturn.returnType)
					interfaceMethod.callableReturnParameters = CallableParameters(callableReturn)
					interfaceMethod.callableReturnCallingConvention = callableReturn.callingConvention
					If interfaceDeclaration And interfaceDeclaration.signature And interfaceDeclaration.signature.callableReturnType Then ApplyCallableParameterNames(interfaceMethod.callableReturnParameters, interfaceDeclaration.signature.callableReturnType)
				End If
				interfaceMethod.callingConvention = member.callingConvention
				interfaceMethod.source = SourceForSymbol(member)
				interfaceMethod.metadata = MetadataOf(member)
				interfaceMethod.parameters = New TCompilerIrParameter[member.parameters.length]
				Local supportedParameters:Int = True
				For Local index:Int = 0 Until member.parameters.length
					Local sourceParameter:TSemanticParameter = member.parameters[index]
					If Not sourceParameter Or Not IsSupportedAbiParameterType(sourceParameter.semanticType) Or Not IsSupportedParameterMode(sourceParameter) Then
						AddUnsupported("BMXC1163", "Interface method parameters require supported ordinary-C ABI value types", member.declaration)
						supportedParameters = False
						Exit
					End If
					Local parameter:TCompilerIrParameter = New TCompilerIrParameter
					parameter.symbolId = "ip" + index
					If sourceParameter.symbol Then parameter.name = sourceParameter.symbol.name Else parameter.name = "arg" + index
					parameter.semanticType = TypeName(sourceParameter.semanticType)
					parameter.passingMode = sourceParameter.passingMode
					PopulateParameterShape(parameter, sourceParameter.semanticType)
					If interfaceDeclaration And interfaceDeclaration.signature And index < interfaceDeclaration.signature.parameters.length Then ApplyCallableParameterNames(parameter.callableParameters, interfaceDeclaration.signature.parameters[index].callableType)
					interfaceMethod.parameters[index] = parameter
				Next
				If Not supportedParameters Then Continue
				methodMap.Insert(member, interfaceMethod)
				interfaceMethodSymbols.Insert(interfaceMethod, member)
				irInterface.methods :+ [interfaceMethod]
			Next
		End If
		completedInterfaceLayouts.Insert(symbol, symbol)
	End Method

	Method CopyInterfaceMethod:TCompilerIrInterfaceMethod(sourceMethod:TCompilerIrInterfaceMethod, slotId:String)
		Local copied:TCompilerIrInterfaceMethod = New TCompilerIrInterfaceMethod
		copied.slotId = slotId
		copied.slotAbiName = sourceMethod.slotAbiName
		copied.name = sourceMethod.name
		copied.declaringInterfaceId = sourceMethod.declaringInterfaceId
		copied.abiName = sourceMethod.abiName
		copied.returnType = sourceMethod.returnType
		copied.callableReturnType = sourceMethod.callableReturnType
		copied.callableReturnParameters = sourceMethod.callableReturnParameters
		copied.callableReturnCallingConvention = sourceMethod.callableReturnCallingConvention
		copied.callingConvention = sourceMethod.callingConvention
		copied.parameters = sourceMethod.parameters
		copied.implementationKind = sourceMethod.implementationKind
		copied.defaultFunctionId = sourceMethod.defaultFunctionId
		copied.defaultImplementationAbiName = sourceMethod.defaultImplementationAbiName
		copied.source = sourceMethod.source
		copied.metadata = sourceMethod.metadata
		Return copied
	End Method

	Method PublishedInterfaceSlotName:String(irInterface:TCompilerIrInterface, interfaceMethod:TCompilerIrInterfaceMethod)
		If irInterface And irInterface.isExternInterface And interfaceMethod Then
			If interfaceMethod.abiName.length Then Return interfaceMethod.abiName
			Return interfaceMethod.name
		End If
		If Not irInterface Or Not interfaceMethod Or Not irInterface.abiName.length Or Not interfaceMethod.abiName.length Then Return ""
		Local prefix:String = irInterface.abiName + "_"
		If interfaceMethod.abiName.length <= prefix.length Or interfaceMethod.abiName[..prefix.length] <> prefix Then Return ""
		Return "m_" + interfaceMethod.abiName[prefix.length..]
	End Method

	Method BuildClassShells()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		classSymbols = New TSymbol[0]
		CollectSourceClassSymbols(analysis.model.globalScope)
		For Local symbol:TSymbol = EachIn classSymbols
			If Not symbol Or symbol.kind <> SYMBOL_TYPE Or symbol.isImported Then Continue
			Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
			If Not declaration Then Continue
			If Not IsSimpleObjectType(symbol, declaration) Then Continue
			Local irClass:TCompilerIrClass = New TCompilerIrClass
			irClass.classId = "cls" + nextClassId
			nextClassId :+ 1
			irClass.name = symbol.name
			Local genericArgumentAbi:String
			If genericPlan Then genericArgumentAbi = String(genericPlan.runtimeArgumentSymbols.ValueForKey(symbol))
			irClass.hasStableLocalAbi = (directMethodLayoutSymbols.Contains(symbol) Or genericArgumentAbi.length) And Not (analysis.model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC)
			If irClass.hasStableLocalAbi Then
				If genericArgumentAbi.length Then irClass.abiName = genericArgumentAbi Else irClass.abiName = TCompilerDirectMethodAbi.OwnerAbiName(analysis.model, symbol)
			Else
				irClass.abiName = TCompilerAbiNamer.ClassName(analysis.model, symbol, irClass.classId)
			End If
			irClass.semanticType = TypeName(symbol.declaredType)
			irClass.visibility = symbol.visibility
			irClass.isPublished = analysis.model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC
			irClass.isAbstract = analysis.model.IsAbstractType(symbol)
			irClass.isFinal = TypeDeclarationIsFinal(declaration)
			irClass.source = SourceOf(declaration)
			irClass.metadata = MetadataOf(symbol)
			If declaration.header Then
				For Local implementedType:TTypeReferenceSyntax = EachIn declaration.header.implementedTypes
					Local implementedInterface:TCompilerIrInterface = InterfaceForType(analysis.model.TypeOf(implementedType))
					If implementedInterface Then irClass.declaredInterfaceIds :+ [implementedInterface.interfaceId]
				Next
			End If
			classesBySymbol.Insert(symbol, irClass)
			result.classes :+ [irClass]
		Next
		For Local symbol:TSymbol = EachIn classSymbols
			Local irClass:TCompilerIrClass = TCompilerIrClass(classesBySymbol.ValueForKey(symbol))
			If Not irClass Then Continue
			Local baseType:TSemanticType = ExplicitBaseType(symbol)
			Local namedBase:TNamedSemanticType = TNamedSemanticType(baseType)
			Local baseSymbol:TSymbol
			If namedBase Then baseSymbol = namedBase.symbol
			Local baseClass:TCompilerIrClass
			If baseSymbol Then baseClass = TCompilerIrClass(classesBySymbol.ValueForKey(baseSymbol))
			If baseClass Then
				irClass.baseClassId = baseClass.classId
			Else If baseType Then
				Local importedBase:TCompilerIrImportedClass = ImportedClassForType(baseType)
				If importedBase Then irClass.baseImportedClassId = importedBase.importedClassId
			End If
		Next
		NormalizeImportedClassInheritance()
		' Complete layouts only after every class identity exists. Recursive
		' completion makes inheritance independent of declaration order.
		For Local symbol:TSymbol = EachIn classSymbols
			If classesBySymbol.Contains(symbol) Then CompleteClassLayout(symbol)
		Next
		OrderClassesBaseFirst()
	End Method

	Method NormalizeImportedClassInheritance()
		Local completed:TMap = New TMap
		Local visiting:TMap = New TMap
		For Local importedClass:TCompilerIrImportedClass = EachIn result.importedClasses
			NormalizeImportedClassInheritanceFor(importedClass, completed, visiting)
		Next
	End Method

	Method NormalizeImportedClassInheritanceFor(importedClass:TCompilerIrImportedClass, completed:TMap, visiting:TMap)
		If Not importedClass Or completed.Contains(importedClass.importedClassId) Then Return
		If visiting.Contains(importedClass.importedClassId) Then Return
		visiting.Insert(importedClass.importedClassId, importedClass)
		Local importedBase:TCompilerIrImportedClass = ImportedClassById(importedClass.baseImportedClassId)
		If importedBase Then NormalizeImportedClassInheritanceFor(importedBase, completed, visiting)
		If importedBase Then
			Local normalizedFields:TCompilerIrImportedField[] = New TCompilerIrImportedField[0]
			For Local inheritedField:TCompilerIrImportedField = EachIn importedBase.fields
				normalizedFields :+ [inheritedField]
			Next
			For Local declaredField:TCompilerIrImportedField = EachIn importedClass.fields
				If declaredField.declaringImportedClassId = importedClass.importedClassId Then normalizedFields :+ [declaredField]
			Next
			importedClass.fields = normalizedFields

			Local normalizedSlots:TCompilerIrClassFunctionSlot[] = New TCompilerIrClassFunctionSlot[0]
			For Local inheritedSlot:TCompilerIrClassFunctionSlot = EachIn importedBase.functionSlots
				normalizedSlots :+ [CloneClassSlot(inheritedSlot)]
			Next
			For Local declaredSlot:TCompilerIrClassFunctionSlot = EachIn importedClass.functionSlots
				' An overriding method keeps the original declaring slot identity but
				' changes the receiver class to the derived imported layout.
				If declaredSlot.declaringImportedClassId <> importedClass.importedClassId And declaredSlot.receiverImportedClassId <> importedClass.importedClassId Then Continue
				Local replaced:Int
				For Local slotIndex:Int = 0 Until normalizedSlots.length
					If normalizedSlots[slotIndex].dispatchKey = declaredSlot.dispatchKey Then
						normalizedSlots[slotIndex] = declaredSlot
						replaced = True
						Exit
					End If
				Next
				If Not replaced Then normalizedSlots :+ [declaredSlot]
			Next
			importedClass.functionSlots = normalizedSlots
			If importedBase.hasManagedFields Then importedClass.hasManagedFields = True
			If Not importedClass.destructorFunctionId.length Then importedClass.destructorFunctionId = importedBase.destructorFunctionId
			If Not importedClass.toStringFunctionId.length Then importedClass.toStringFunctionId = importedBase.toStringFunctionId
			If Not importedClass.compareFunctionId.length Then importedClass.compareFunctionId = importedBase.compareFunctionId
			If Not importedClass.sendMessageFunctionId.length Then importedClass.sendMessageFunctionId = importedBase.sendMessageFunctionId
			If Not importedClass.hashCodeFunctionId.length Then importedClass.hashCodeFunctionId = importedBase.hashCodeFunctionId
			If Not importedClass.equalsFunctionId.length Then importedClass.equalsFunctionId = importedBase.equalsFunctionId
		End If
		visiting.Remove(importedClass.importedClassId)
		completed.Insert(importedClass.importedClassId, importedClass)
	End Method

	Method CollectSourceClassSymbols(scope:TScope)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Or symbol.isImported Then Continue
			If symbol.kind = SYMBOL_TYPE Then classSymbols :+ [symbol]
			' Nested declarations live in the owning Type/Struct member scope.
			' Do not descend through routine scopes: local routines are handled
			' separately and BlitzMax nested Types are owner declarations.
			If (symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_STRUCT) And symbol.memberScope Then
				CollectSourceClassSymbols(symbol.memberScope)
			End If
		Next
	End Method

	Method OrderClassesBaseFirst()
		Local ordered:TCompilerIrClass[] = New TCompilerIrClass[0]
		Local added:TMap = New TMap
		For Local irClass:TCompilerIrClass = EachIn result.classes
			AppendClassBaseFirst(irClass, ordered, added)
		Next
		result.classes = ordered
	End Method

	Method AppendClassBaseFirst(irClass:TCompilerIrClass, ordered:TCompilerIrClass[] Var, added:TMap)
		If Not irClass Or added.Contains(irClass.classId) Then Return
		If irClass.baseClassId.length Then AppendClassBaseFirst(ClassById(irClass.baseClassId), ordered, added)
		added.Insert(irClass.classId, irClass)
		ordered :+ [irClass]
	End Method

	Method CompleteClassLayout(symbol:TSymbol)
		If completedClassLayouts.Contains(symbol) Then Return
		Local irClass:TCompilerIrClass = TCompilerIrClass(classesBySymbol.ValueForKey(symbol))
		If Not irClass Then Return
		Local baseSymbol:TSymbol = ExplicitBaseSymbol(symbol)
		Local baseClass:TCompilerIrClass
		If baseSymbol Then baseClass = TCompilerIrClass(classesBySymbol.ValueForKey(baseSymbol))
		If baseClass Then
			CompleteClassLayout(baseSymbol)
			For Local inherited:TCompilerIrClassField = EachIn baseClass.fields
				irClass.fields :+ [inherited]
			Next
			irClass.hasManagedFields = baseClass.hasManagedFields
		Else If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			If importedBase Then
				For Local importedField:TCompilerIrImportedField = EachIn importedBase.fields
					Local inheritedField:TCompilerIrClassField = New TCompilerIrClassField
					inheritedField.fieldId = "base_" + importedField.fieldId
					inheritedField.declaringClassId = irClass.classId
					inheritedField.declaringImportedClassId = importedField.declaringImportedClassId
					inheritedField.name = importedField.name
					inheritedField.abiName = importedField.abiName
					inheritedField.semanticType = importedField.semanticType
					inheritedField.isStaticArray = importedField.isStaticArray
					inheritedField.staticArrayElementType = importedField.staticArrayElementType
					inheritedField.staticArrayStructId = importedField.staticArrayStructId
					inheritedField.staticArrayImportedStructId = importedField.staticArrayImportedStructId
					inheritedField.staticArrayLength = importedField.staticArrayLength
					inheritedField.callableReturnType = importedField.callableReturnType
					inheritedField.callableParameters = importedField.callableParameters
					inheritedField.callableCallingConvention = importedField.callableCallingConvention
					inheritedField.visibility = importedField.visibility
					inheritedField.isReadOnly = importedField.isReadOnly
					inheritedField.source = importedField.source
					inheritedField.metadata = importedField.metadata
					irClass.fields :+ [inheritedField]
				Next
				irClass.hasManagedFields = importedBase.hasManagedFields
			End If
		End If
		irClass.declaredFieldStart = irClass.fields.length
		If symbol.memberScope Then
				For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
					If Not member Or member.kind <> SYMBOL_FIELD Then Continue
					Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(member.declaredType)
					If Not IsSupportedClassFieldType(member.declaredType) And Not IsSupportedStaticArrayType(staticArrayType) Then
						AddUnsupported("BMXC1144", "Field type '" + TypeName(member.declaredType) + "' is outside the simple object layout slice", member.declaration)
						Continue
					End If
					Local staticElementStruct:TCompilerIrStruct
					Local staticElementImportedStruct:TCompilerIrImportedStruct
					Local fieldStruct:TCompilerIrStruct = StructForType(member.declaredType)
					If irClass.isPublished And fieldStruct Then ExposeStructLayout(fieldStruct)
					If staticArrayType Then
						staticElementStruct = StructForType(staticArrayType.elementType)
						staticElementImportedStruct = ImportedStructForType(staticArrayType.elementType)
						If irClass.isPublished And staticElementStruct Then ExposeStructLayout(staticElementStruct)
						If staticElementImportedStruct And Not ImportedStructHasDefaultHelper(staticElementImportedStruct) Then
							AddUnsupported("BMXC1021", "Imported Struct StaticArray Type field element type '" + TypeName(staticArrayType.elementType) + "' has no published zero-argument value helper", member.declaration)
							Continue
						End If
					End If
					Local irField:TCompilerIrClassField = New TCompilerIrClassField
					irField.fieldId = "f" + irClass.declaredFieldCount
					irField.declaringClassId = irClass.classId
					irField.name = member.name
					If irClass.isPublished Or irClass.hasStableLocalAbi Then irField.abiName = TCompilerAbiNamer.FieldName(irClass.abiName, member.name)
					irField.semanticType = TypeName(member.declaredType)
					If staticArrayType Then
						irField.isStaticArray = True
						irField.staticArrayElementType = TypeName(staticArrayType.elementType)
						irField.staticArrayLength = staticArrayType.length
						If staticElementStruct Then irField.staticArrayStructId = staticElementStruct.structId
						If staticElementImportedStruct Then irField.staticArrayImportedStructId = staticElementImportedStruct.importedStructId
					End If
					Local callableType:TCallableSemanticType = TCallableSemanticType(member.declaredType)
					If callableType Then
						irField.callableReturnType = TypeName(callableType.returnType)
						irField.callableParameters = CallableParameters(callableType)
						irField.callableCallingConvention = callableType.callingConvention
					End If
					Local fieldArrayType:TArraySemanticType = TArraySemanticType(member.declaredType)
					Local fieldArrayCallable:TCallableSemanticType
					If fieldArrayType Then fieldArrayCallable = TCallableSemanticType(fieldArrayType.elementType)
					If fieldArrayCallable Then
						irField.arrayCallableReturnType = TypeName(fieldArrayCallable.returnType)
						irField.arrayCallableParameters = CallableParameters(fieldArrayCallable)
						irField.arrayCallableCallingConvention = fieldArrayCallable.callingConvention
						irField.arrayCallableRank = fieldArrayType.rank
					End If
					Local fieldDeclarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(member.declaration)
					If fieldDeclarator And fieldDeclarator.callableType Then
						If callableType Then ApplyCallableParameterNames(irField.callableParameters, fieldDeclarator.callableType)
						If fieldArrayCallable Then ApplyCallableParameterNames(irField.arrayCallableParameters, fieldDeclarator.callableType)
					End If
					irField.visibility = member.visibility
					irField.isReadOnly = member.isReadOnly
					irField.source = SourceOf(member.declaration)
					irField.metadata = MetadataOf(member)
					If IsManagedValueType(member.declaredType) Then irClass.hasManagedFields = True
					If staticArrayType And IsManagedReferenceType(staticArrayType.elementType) Then irClass.hasManagedFields = True
					If staticElementStruct And staticElementStruct.containsManagedReferences Then irClass.hasManagedFields = True
					If staticElementImportedStruct And staticElementImportedStruct.containsManagedReferences Then irClass.hasManagedFields = True
					fieldsBySymbol.Insert(member, irField)
					irClass.fields :+ [irField]
					irClass.declaredFieldCount :+ 1
				Next
		End If
		completedClassLayouts.Insert(symbol, symbol)
	End Method

	Method IsSimpleObjectType:Int(symbol:TSymbol, declaration:TTypeDeclarationSyntax)
		If Not declaration.header Then Return True
		If declaration.header.genericParameters.length Then
			If genericPlan And genericPlan.specializedSourceSymbols.Contains(symbol) Then Return False
			AddUnsupported("BMXC1140", "Generic Types require canonical specialization lowering", declaration)
			Return False
		End If
		For Local implementedType:TTypeReferenceSyntax = EachIn declaration.header.implementedTypes
			Local named:TNamedSemanticType = TNamedSemanticType(analysis.model.TypeOf(implementedType))
			If Not named Or Not named.symbol Or Not InterfaceForType(named) Then
				AddUnsupported("BMXC1141", "Interface implementation requires a source or canonical imported Interface with a published ABI", implementedType)
				Return False
			End If
		Next
		If declaration.header.extendsTypes.length Then
			Local baseType:TSemanticType = ExplicitBaseType(symbol)
			Local namedBase:TNamedSemanticType = TNamedSemanticType(baseType)
			Local baseSymbol:TSymbol
			If namedBase Then baseSymbol = namedBase.symbol
			If Not baseSymbol Or baseSymbol.kind <> SYMBOL_TYPE Then
				AddUnsupported("BMXC1141", "Type inheritance requires a resolved Type base", declaration.header.extendsTypes[0])
				Return False
			End If
			If baseSymbol.isImported Or baseSymbol.genericArity > 0 Then
				Local importedBase:TCompilerIrImportedClass = ImportedClassForType(baseType)
				If Not importedBase Then
					AddUnsupported("BMXC1141", "Imported Type inheritance requires a complete published ABI record", declaration.header.extendsTypes[0])
					Return False
				End If
			End If
		End If
		' A Type that inherits an abstract obligation remains abstract even when
		' its own declaration does not repeat the Abstract modifier. BlitzMax
		' permits such intermediate Types; construction is rejected by the
		' semantic model until a derived Type completes every obligation.
		Return True
	End Method

	Method InitializeDocuments()
		If Not analysis Then Return
		If analysis.snapshot Then
			documents = analysis.snapshot.documents
		Else If analysis.syntaxTree Then
			Local document:TSourceDocumentModel = New TSourceDocumentModel
			document.path = analysis.syntaxTree.source.path
			document.tree = analysis.syntaxTree
			document.isRoot = True
			documents = [document]
		End If
		navigators = New TSyntaxNavigator[documents.length]
		For Local index:Int = 0 Until documents.length
			If documents[index] And documents[index].tree Then navigators[index] = TSyntaxNavigator.Create(documents[index].tree)
		Next
	End Method

	Method BuildFunctionShells()
		Local globalFunction:TCompilerIrFunction = New TCompilerIrFunction
		globalFunction.functionId = "main"
		globalFunction.name = "$main"
		' The module body is the production-compatible Int entry routine. This
		' permits top-level Return and gives Strict's bare Return its zero value.
		globalFunction.returnType = "Int"
		globalFunction.isGlobalEntry = True
		If analysis And analysis.syntaxTree Then globalFunction.source = SourceOf(analysis.syntaxTree.root)
		ApplyInstrumentation(globalFunction, Null)
		result.functions :+ [globalFunction]

		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			If symbol.kind = SYMBOL_ROUTINE Then
				If GenericRoutineTemplatePlanned(symbol) Then Continue
				BuildRoutineShell(symbol, Null)
			End If
		Next
		For Local symbol:TSymbol = EachIn classSymbols
			If classesBySymbol.Contains(symbol) Then CompleteClassRoutines(symbol)
		Next
		For Local symbol:TSymbol = EachIn interfaceSymbols
			BuildInterfaceDefaultRoutineShells(symbol)
		Next
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			Local ownerStruct:TCompilerIrStruct = TCompilerIrStruct(structsBySymbol.ValueForKey(symbol))
			If Not ownerStruct Or Not symbol.memberScope Then Continue
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If member.kind = SYMBOL_ROUTINE Then BuildRoutineShell(member, Null, Null, ownerStruct)
			Next
		Next
		BuildFunctionLiteralShells(analysis.model.globalScope)
	End Method

	Method BuildClosureCapturePlans()
		For Local literalSymbol:TSymbol = EachIn routineSymbols
			Local literalSyntax:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(literalSymbol.declaration)
			If Not literalSyntax Then Continue
			Local boundLiteral:TBoundFunctionLiteralExpression = TBoundFunctionLiteralExpression(analysis.model.BoundExpression(literalSyntax))
			If Not boundLiteral Or (Not boundLiteral.captures.length And Not boundLiteral.capturesSelf) Then Continue
			Local ownerSymbol:TSymbol = ContainingRoutineSymbol(literalSymbol)
			If ownerSymbol And ownerSymbol.genericArity Then
				AddUnsupported("BMXC1247", "capturing Closure literals in generic routines require canonical environment specialization support", literalSyntax)
				Continue
			End If
			Local ownerPlan:TCompilerClosureCapturePlan = CaptureOwnerPlan(ownerSymbol)
			Local literalPlan:TCompilerClosureCapturePlan = ownerPlan
			If boundLiteral.capturesSelf Then
				If IsInstanceMethodSymbol(ownerSymbol) Then
					If ownerPlan.capturesSelf And ownerPlan.selfType And boundLiteral.capturedSelfType And TypeName(ownerPlan.selfType) <> TypeName(boundLiteral.capturedSelfType) Then
						AddUnsupported("BMXC1248", "sibling Closure literals disagree about their captured Self type", literalSyntax)
					Else
						ownerPlan.capturesSelf = True
						ownerPlan.selfType = boundLiteral.capturedSelfType
					End If
				Else
					ownerPlan.needsParent = True
				End If
			End If
			For Local captured:TSymbol = EachIn boundLiteral.captures
				If Not captured Then Continue
				If ContainingRoutineSymbol(captured) <> ownerSymbol Then
					ownerPlan.needsParent = True
					Continue
				End If
				Local plan:TCompilerClosureCapturePlan = CaptureStoragePlan(ownerSymbol, captured.containingScope)
				If plan.activationScoped And (Not literalPlan.activationScoped Or ScopeIsWithin(plan.storageScope, literalPlan.storageScope)) Then literalPlan = plan
				If plan.fieldsBySymbol.Contains(captured) Then Continue
				If Not IsSupportedClassFieldType(captured.declaredType) Then
					AddUnsupported("BMXC1248", "captured value '" + captured.name + "' has unsupported environment type '" + TypeName(captured.declaredType) + "'", captured.declaration)
					Continue
				End If
				plan.captures :+ [captured]
				' A temporary marker reserves deterministic first-use order until
				' the environment layout is synthesized below.
				plan.fieldsBySymbol.Insert(captured, captured)
				closureCapturePlansBySymbol.Insert(captured, plan)
			Next
			closureCapturePlansByLiteral.Insert(literalSymbol, literalPlan)
		Next

		For Local plan:TCompilerClosureCapturePlan = EachIn closureCapturePlans
			If plan.activationScoped Then
				Local parentScope:TScope = plan.storageScope.parent
				While parentScope
					Local parentPlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(parentScope))
					If parentPlan Then plan.parentPlan = parentPlan; Exit
					If parentScope.kind = SCOPE_ROUTINE Then Exit
					parentScope = parentScope.parent
				Wend
				If Not plan.parentPlan Then
					Local routinePlan:TCompilerClosureCapturePlan = CaptureOwnerPlan(plan.ownerSymbol)
					If PlanRequiresEnvironment(routinePlan) Then plan.parentPlan = routinePlan
				End If
			Else If plan.needsParent Then
				plan.parentPlan = TCompilerClosureCapturePlan(closureCapturePlansByLiteral.ValueForKey(plan.ownerSymbol))
				If Not plan.parentPlan Then AddUnsupported("BMXC1248", "nested Closure capture has no enclosing environment plan", plan.ownerSymbol.declaration)
			End If
		Next

		' Publish every environment identity before laying out parent fields so
		' nested plans may refer to their enclosing managed environment regardless
		' of source traversal order.
		For Local plan:TCompilerClosureCapturePlan = EachIn closureCapturePlans
			Local ownerRoutine:TCompilerIrFunction = CaptureOwnerRoutine(plan)
			If Not ownerRoutine Or Not PlanRequiresEnvironment(plan) Then Continue
			Local environmentSuffix:String
			If plan.activationScoped And plan.storageScope And plan.storageScope.syntax Then
				If plan.catchScoped Then environmentSuffix = "_catch_" + plan.storageScope.syntax.span.start Else environmentSuffix = "_loop_" + plan.storageScope.syntax.span.start
			End If
			Local environmentClass:TCompilerIrClass = New TCompilerIrClass
			environmentClass.classId = "cls" + nextClassId
			nextClassId :+ 1
			environmentClass.name = "$ClosureEnvironment_" + ownerRoutine.functionId + environmentSuffix
			environmentClass.semanticType = environmentClass.name
			environmentClass.visibility = VISIBILITY_PRIVATE
			environmentClass.source = ownerRoutine.source
			environmentClass.declaredFieldCount = plan.captures.length + plan.capturesSelf + (plan.parentPlan <> Null)
			plan.environmentClass = environmentClass
			plan.environmentSymbolId = ownerRoutine.functionId + "_closure_environment" + environmentSuffix
			result.classes :+ [environmentClass]
		Next

		For Local plan:TCompilerClosureCapturePlan = EachIn closureCapturePlans
			Local ownerRoutine:TCompilerIrFunction = CaptureOwnerRoutine(plan)
			Local environmentClass:TCompilerIrClass = plan.environmentClass
			If Not ownerRoutine Or Not environmentClass Then Continue
			plan.fieldsBySymbol = New TMap
			Local captureIndex:Int
			If plan.parentPlan Then
				If Not plan.parentPlan.environmentClass Then
					AddUnsupported("BMXC1248", "nested Closure parent environment has no lowered layout", plan.ownerSymbol.declaration)
					Continue
				End If
				plan.parentField = New TCompilerIrClassField
				plan.parentField.fieldId = "capture" + captureIndex
				plan.parentField.declaringClassId = environmentClass.classId
				plan.parentField.name = "$Parent"
				plan.parentField.semanticType = plan.parentPlan.environmentClass.semanticType
				plan.parentField.visibility = VISIBILITY_PRIVATE
				plan.parentField.source = ownerRoutine.source
				environmentClass.hasManagedFields = True
				environmentClass.fields :+ [plan.parentField]
				captureIndex :+ 1
			End If
			If plan.capturesSelf Then
				If Not plan.selfType Or Not IsSupportedClassFieldType(plan.selfType) Then
					AddUnsupported("BMXC1248", "captured Self has an unsupported environment type", plan.ownerSymbol.declaration)
					Continue
				End If
				plan.selfField = New TCompilerIrClassField
				plan.selfField.fieldId = "capture" + captureIndex
				plan.selfField.declaringClassId = environmentClass.classId
				plan.selfField.name = "Self"
				plan.selfField.semanticType = TypeName(plan.selfType)
				plan.selfField.visibility = VISIBILITY_PRIVATE
				plan.selfField.source = ownerRoutine.source
				environmentClass.hasManagedFields = True
				environmentClass.fields :+ [plan.selfField]
				captureIndex :+ 1
			End If
			For Local index:Int = 0 Until plan.captures.length
				Local captured:TSymbol = plan.captures[index]
				Local captureField:TCompilerIrClassField = New TCompilerIrClassField
				captureField.fieldId = "capture" + captureIndex
				captureField.declaringClassId = environmentClass.classId
				captureField.name = captured.name
				captureField.semanticType = TypeName(captured.declaredType)
				captureField.visibility = VISIBILITY_PRIVATE
				captureField.source = SourceOf(captured.declaration)
				If IsManagedValueType(captured.declaredType) Then environmentClass.hasManagedFields = True
				environmentClass.fields :+ [captureField]
				plan.fieldsBySymbol.Insert(captured, captureField)
				captureIndex :+ 1
			Next
		Next
	End Method

	Method CaptureOwnerPlan:TCompilerClosureCapturePlan(ownerSymbol:TSymbol)
		If Not ownerSymbol Then
			If moduleClosureCapturePlan Then Return moduleClosureCapturePlan
			moduleClosureCapturePlan = New TCompilerClosureCapturePlan
			closureCapturePlans :+ [moduleClosureCapturePlan]
			Return moduleClosureCapturePlan
		End If
		Local plan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByOwner.ValueForKey(ownerSymbol))
		If plan Then Return plan
		plan = New TCompilerClosureCapturePlan
		plan.ownerSymbol = ownerSymbol
		closureCapturePlansByOwner.Insert(ownerSymbol, plan)
		closureCapturePlans :+ [plan]
		Return plan
	End Method

	Method CaptureOwnerRoutine:TCompilerIrFunction(plan:TCompilerClosureCapturePlan)
		If Not plan Then Return Null
		If plan.ownerSymbol Then Return TCompilerIrFunction(functionsBySymbol.ValueForKey(plan.ownerSymbol))
		If result And result.functions.length Then Return result.functions[0]
		Return Null
	End Method

	Method CaptureStoragePlan:TCompilerClosureCapturePlan(ownerSymbol:TSymbol, scope:TScope)
		Local activationScope:TScope = scope
		While activationScope And activationScope.kind <> SCOPE_ROUTINE
			If activationScope.kind = SCOPE_LOOP Or activationScope.kind = SCOPE_CATCH Then Exit
			activationScope = activationScope.parent
		Wend
		If Not activationScope Or (activationScope.kind <> SCOPE_LOOP And activationScope.kind <> SCOPE_CATCH) Then Return CaptureOwnerPlan(ownerSymbol)
		Local plan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(activationScope))
		If plan Then Return plan
		plan = New TCompilerClosureCapturePlan
		plan.ownerSymbol = ownerSymbol
		plan.storageScope = activationScope
		plan.activationScoped = True
		plan.iterationScoped = activationScope.kind = SCOPE_LOOP
		plan.catchScoped = activationScope.kind = SCOPE_CATCH
		closureCapturePlansByScope.Insert(activationScope, plan)
		closureCapturePlans :+ [plan]
		Return plan
	End Method

	Function PlanRequiresEnvironment:Int(plan:TCompilerClosureCapturePlan)
		Return plan And (plan.captures.length Or plan.capturesSelf Or plan.parentPlan)
	End Function

	Function ScopeIsWithin:Int(scope:TScope, ancestor:TScope)
		While scope
			If scope = ancestor Then Return True
			scope = scope.parent
		Wend
		Return False
	End Function

	Function ContainingRoutineSymbol:TSymbol(symbol:TSymbol)
		If Not symbol Then Return Null
		Local scope:TScope = symbol.containingScope
		While scope
			If scope.owner And scope.owner <> symbol And scope.owner.kind = SYMBOL_ROUTINE Then Return scope.owner
			scope = scope.parent
		Wend
		Return Null
	End Function

	Method BuildInterfaceDefaultRoutineShells(symbol:TSymbol)
		If Not symbol Or symbol.isImported Or Not symbol.memberScope Then Return
		Local irInterface:TCompilerIrInterface = TCompilerIrInterface(interfacesBySymbol.ValueForKey(symbol))
		Local methodMap:TMap
		If irInterface Then methodMap = TMap(interfaceMethodsByInterface.ValueForKey(irInterface))
		For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
			If member.kind <> SYMBOL_ROUTINE Or member.interfaceMethodKind <> INTERFACE_METHOD_DEFAULT Then Continue
			BuildRoutineShell(member, Null)
			Local routine:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(member))
			If Not routine Then Continue
			If irInterface Then routine.ownerInterfaceId = irInterface.interfaceId
			Local interfaceMethod:TCompilerIrInterfaceMethod
			If methodMap Then interfaceMethod = TCompilerIrInterfaceMethod(methodMap.ValueForKey(member))
			If interfaceMethod Then interfaceMethod.defaultFunctionId = routine.functionId
		Next
	End Method

	Method GenericRoutineTemplatePlanned:Int(symbol:TSymbol)
		If Not symbol Or Not genericPlan Or symbol.genericArity <= 0 Then Return False
		If genericPlan.specializedSourceSymbols.Contains(symbol) Then Return True
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.ir Or Not unit.ir.isRoutine Then Continue
			If unit.specialization.artifact.identity.qualifiedName.ToLower() = symbol.QualifiedName().ToLower() Or unit.specialization.artifact.identity.qualifiedName.ToLower() = symbol.name.ToLower() Then Return True
		Next
		Return False
	End Method

	Method BuildInterfaceImplementations()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		For Local symbol:TSymbol = EachIn classSymbols
			Local irClass:TCompilerIrClass = TCompilerIrClass(classesBySymbol.ValueForKey(symbol))
			If Not irClass Then Continue
			Local implementedInterfaces:TCompilerIrInterface[] = New TCompilerIrInterface[0]
			CollectImplementedInterfaceRecords(symbol, implementedInterfaces, New TMap)
			For Local irInterface:TCompilerIrInterface = EachIn implementedInterfaces
				Local implementation:TCompilerIrInterfaceImplementation = New TCompilerIrInterfaceImplementation
				implementation.interfaceId = irInterface.interfaceId
				implementation.slots = New TCompilerIrInterfaceImplementationSlot[irInterface.methods.length]
				For Local index:Int = 0 Until irInterface.methods.length
					Local requirement:TSymbol = TSymbol(interfaceMethodSymbols.ValueForKey(irInterface.methods[index]))
					Local routine:TSymbol
					If requirement Then
						Local namedInterface:TNamedSemanticType = InterfaceSemanticTypeForSymbol(symbol, irInterface)
						If namedInterface Then routine = FindInterfaceImplementation(symbol, requirement, namedInterface)
					End If
					If Not routine Then routine = FindConcreteInterfaceImplementation(symbol, irInterface.methods[index])
					Local target:TCompilerIrFunction
					If routine Then target = TCompilerIrFunction(functionsBySymbol.ValueForKey(routine))
					Local targetAbiName:String
					If routine And Not target And routine.isImported Then
						Local importedTarget:TCompilerIrImportedMethod = ImportedMethod(routine, symbol.declaration)
						If importedTarget Then targetAbiName = importedTarget.implementationAbiName
					End If
					If Not target And requirement And requirement.interfaceMethodKind = INTERFACE_METHOD_DEFAULT Then target = TCompilerIrFunction(functionsBySymbol.ValueForKey(requirement))
					If Not target And irInterface.methods[index].defaultFunctionId.length Then target = FunctionById(irInterface.methods[index].defaultFunctionId)
					If Not target And irClass.isAbstract Then
						Local abstractSlot:TCompilerIrClassFunctionSlot = ClassRequirementSlot(irClass, requirement)
						If abstractSlot Then target = FunctionById(abstractSlot.functionId)
					End If
					If Not target And Not targetAbiName.length And Not irInterface.methods[index].defaultImplementationAbiName.length Then
						AddUnsupported("BMXC1164", "Interface method '" + irInterface.name + "." + irInterface.methods[index].name + "' has no lowered implementation", symbol.declaration)
						Continue
					End If
					Local slot:TCompilerIrInterfaceImplementationSlot = New TCompilerIrInterfaceImplementationSlot
					slot.interfaceSlotId = irInterface.methods[index].slotId
					If target Then
						slot.functionId = target.functionId
						slot.receiverClassId = target.ownerClassId
					Else If targetAbiName.length Then
						slot.functionAbiName = targetAbiName
					Else
						slot.functionAbiName = irInterface.methods[index].defaultImplementationAbiName
					End If
					implementation.slots[index] = slot
				Next
				irClass.interfaceImplementations :+ [implementation]
			Next
		Next
	End Method

	Method CollectImplementedInterfaceRecords(typeSymbol:TSymbol, interfaces:TCompilerIrInterface[] Var, seen:TMap)
		If Not typeSymbol Then Return
		Local irClass:TCompilerIrClass = TCompilerIrClass(classesBySymbol.ValueForKey(typeSymbol))
		If irClass And irClass.baseImportedClassId.length Then
			CollectImportedClassInterfaceRecords(ImportedClassById(irClass.baseImportedClassId), interfaces, seen, New TMap)
		End If
		Local baseSymbol:TSymbol = ExplicitBaseSymbol(typeSymbol)
		' An imported base can own the Interface contract while this source unit
		' supplies an override. The derived class still needs its own rebuilt
		' Interface table so dispatch reaches that local override.
		If baseSymbol Then CollectImplementedInterfaceRecords(baseSymbol, interfaces, seen)
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(typeSymbol)
		If Not info Then Return
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
			AppendImplementedInterfaceRecord(InterfaceForType(edge.semanticType), interfaces, seen)
		Next
	End Method

	Method CollectImportedClassInterfaceRecords(importedClass:TCompilerIrImportedClass, interfaces:TCompilerIrInterface[] Var, seen:TMap, visitedClasses:TMap)
		If Not importedClass Or visitedClasses.Contains(importedClass.importedClassId) Then Return
		visitedClasses.Insert(importedClass.importedClassId, importedClass)
		If importedClass.baseImportedClassId.length Then CollectImportedClassInterfaceRecords(ImportedClassById(importedClass.baseImportedClassId), interfaces, seen, visitedClasses)
		For Local interfaceId:String = EachIn importedClass.implementedInterfaceIds
			AppendImplementedInterfaceRecord(InterfaceById(interfaceId), interfaces, seen)
		Next
	End Method

	Method AppendImplementedInterfaceRecord(irInterface:TCompilerIrInterface, interfaces:TCompilerIrInterface[] Var, seen:TMap)
		If Not irInterface Or seen.Contains(irInterface.interfaceId) Then Return
		For Local baseInterfaceId:String = EachIn irInterface.baseInterfaceIds
			AppendImplementedInterfaceRecord(InterfaceById(baseInterfaceId), interfaces, seen)
		Next
		seen.Insert(irInterface.interfaceId, irInterface)
		interfaces :+ [irInterface]
	End Method

	Method InterfaceSemanticTypeForSymbol:TNamedSemanticType(typeSymbol:TSymbol, irInterface:TCompilerIrInterface)
		If Not typeSymbol Or Not irInterface Then Return Null
		Return InterfaceSemanticTypeForNamed(TNamedSemanticType(typeSymbol.declaredType), irInterface, 0)
	End Method

	Method InterfaceSemanticTypeForNamed:TNamedSemanticType(namedType:TNamedSemanticType, irInterface:TCompilerIrInterface, depth:Int)
		If Not namedType Or Not namedType.symbol Or Not irInterface Or depth > 64 Then Return Null
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(namedType.symbol)
		If Not info Then Return Null
		Local substitutions:TMap = TCompilerGenericInheritance.TypeSubstitutions(namedType)
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
			Local interfaceType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, substitutions)
			Local candidate:TCompilerIrInterface = InterfaceForType(interfaceType)
			If candidate = irInterface Then Return TNamedSemanticType(interfaceType)
		Next
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			Local baseType:TNamedSemanticType = TNamedSemanticType(TGenericRoutineInference.Substitute(edge.semanticType, substitutions))
			Local inherited:TNamedSemanticType = InterfaceSemanticTypeForNamed(baseType, irInterface, depth + 1)
			If inherited Then Return inherited
		Next
		Return Null
	End Method

	Method ClassRequirementSlot:TCompilerIrClassFunctionSlot(irClass:TCompilerIrClass, requirement:TSymbol)
		If Not irClass Or Not requirement Then Return Null
		Local dispatchKey:String = TCompilerAbiNamer.ClassMethodSlotName(requirement)
		For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
			If slot.isMethod And slot.dispatchKey = dispatchKey Then Return slot
		Next
		Return Null
	End Method

	Method FindConcreteInterfaceImplementation:TSymbol(typeSymbol:TSymbol, requirement:TCompilerIrInterfaceMethod)
		If Not typeSymbol Or Not requirement Then Return Null
		If typeSymbol.memberScope Then
			For Local candidate:TSymbol = EachIn typeSymbol.memberScope.LookupLocal(requirement.name)
				If ConcreteInterfaceSignaturesMatch(candidate, requirement) Then Return candidate
			Next
		End If
		Local baseSymbol:TSymbol = ExplicitBaseSymbol(typeSymbol)
		If baseSymbol Then Return FindConcreteInterfaceImplementation(baseSymbol, requirement)
		Return Null
	End Method

	Method BuildUsingCloseCall:TCompilerIrExpression(resourceSymbol:TSymbol, variable:TCompilerIrVariableDeclaration, syntax:TSyntaxNode)
		If Not resourceSymbol Or Not variable Then Return Null
		Local named:TNamedSemanticType = TNamedSemanticType(resourceSymbol.declaredType)
		Local closeInterface:TCompilerIrInterface = InterfaceForType(resourceSymbol.declaredType)
		Local interfaces:TNamedSemanticType[]
		If named And named.symbol And named.symbol.kind = SYMBOL_TYPE Then CollectImplementedInterfaces(named.symbol, interfaces, New TMap)
		For Local candidateType:TNamedSemanticType = EachIn interfaces
			Local candidate:TCompilerIrInterface = InterfaceForType(candidateType)
			If candidate And candidate.name.ToLower() = "icloseable" Then closeInterface = candidate; Exit
		Next
		If Not closeInterface Then
			AddUnsupported("BMXC1214", "Using resource '" + resourceSymbol.name + "' does not expose an ICloseable Interface contract", syntax)
			Return Null
		End If
		Local closeMethod:TCompilerIrInterfaceMethod
		For Local candidateMethod:TCompilerIrInterfaceMethod = EachIn closeInterface.methods
			If candidateMethod.name.ToLower() = "close" And candidateMethod.parameters.length = 0 Then closeMethod = candidateMethod; Exit
		Next
		If Not closeMethod Then
			AddUnsupported("BMXC1214", "Using resource Interface has no parameterless Close method", syntax)
			Return Null
		End If
		Local reference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		reference.kind = IR_EXPRESSION_SYMBOL
		reference.semanticType = variable.semanticType
		reference.source = variable.source
		reference.symbolId = variable.symbolId
		reference.name = variable.name
		Local cast:TCompilerIrInterfaceCast = New TCompilerIrInterfaceCast
		cast.kind = IR_EXPRESSION_INTERFACE_CAST
		cast.semanticType = closeInterface.semanticType
		cast.source = variable.source
		cast.interfaceId = closeInterface.interfaceId
		cast.operand = reference
		Local call:TCompilerIrCall = New TCompilerIrCall
		call.kind = IR_EXPRESSION_CALL
		call.semanticType = closeMethod.returnType
		call.source = variable.source
		call.functionName = closeMethod.name
		call.dispatchKind = IR_CALL_DISPATCH_INTERFACE
		call.receiver = cast
		call.interfaceId = closeInterface.interfaceId
		call.interfaceSlotId = closeMethod.slotId
		Return call
	End Method

	Method BuildIteratorCleanup:TCompilerIrUsingResource(iterator:TCompilerIrExpression, syntax:TSyntaxNode)
		If Not iterator Then Return Null
		Local closeInterface:TCompilerIrInterface = EnsureImportedRuntimeInterface("brl_blitz_ICloseable")
		If Not closeInterface Then Return Null
		Local closeMethod:TCompilerIrInterfaceMethod
		For Local candidate:TCompilerIrInterfaceMethod = EachIn closeInterface.methods
			If candidate.name.ToLower() = "close" And candidate.parameters.length = 0 Then closeMethod = candidate; Exit
		Next
		If Not closeMethod Then Return Null

		Local resource:TCompilerIrUsingResource = New TCompilerIrUsingResource
		resource.variable = New TCompilerIrVariableDeclaration
		resource.variable.kind = IR_STATEMENT_VARIABLE
		resource.variable.source = SourceOf(syntax)
		resource.variable.symbolId = NewTemporaryId()
		resource.variable.name = "closeableIterator"
		resource.variable.semanticType = closeInterface.semanticType
		resource.variable.initializer = ManagedDefault(closeInterface.semanticType, IR_MANAGED_REFERENCE_OBJECT, resource.variable.source)
		resource.variable.isVolatile = True

		Local cast:TCompilerIrInterfaceCast = New TCompilerIrInterfaceCast
		cast.kind = IR_EXPRESSION_INTERFACE_CAST
		cast.semanticType = closeInterface.semanticType
		cast.source = resource.variable.source
		cast.interfaceId = closeInterface.interfaceId
		cast.operand = iterator
		resource.initializer = cast

		Local reference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		reference.kind = IR_EXPRESSION_SYMBOL
		reference.semanticType = closeInterface.semanticType
		reference.source = resource.variable.source
		reference.symbolId = resource.variable.symbolId
		reference.name = resource.variable.name
		Local call:TCompilerIrCall = New TCompilerIrCall
		call.kind = IR_EXPRESSION_CALL
		call.semanticType = closeMethod.returnType
		call.source = resource.variable.source
		call.functionName = closeMethod.name
		call.dispatchKind = IR_CALL_DISPATCH_INTERFACE
		call.receiver = reference
		call.interfaceId = closeInterface.interfaceId
		call.interfaceSlotId = closeMethod.slotId
		resource.closeCall = call

		resource.truth = New TCompilerIrManagedTruth
		TCompilerIrManagedTruth(resource.truth).kind = IR_EXPRESSION_MANAGED_TRUTH
		TCompilerIrManagedTruth(resource.truth).semanticType = "Int"
		TCompilerIrManagedTruth(resource.truth).source = resource.variable.source
		TCompilerIrManagedTruth(resource.truth).operand = reference
		TCompilerIrManagedTruth(resource.truth).managedKind = IR_MANAGED_REFERENCE_OBJECT
		Return resource
	End Method

	Method ConcreteInterfaceSignaturesMatch:Int(candidate:TSymbol, requirement:TCompilerIrInterfaceMethod)
		If Not candidate Or candidate.kind <> SYMBOL_ROUTINE Or candidate.isAbstract Or Not requirement Then Return False
		If candidate.name.ToLower() <> requirement.name.ToLower() Then Return False
		If Not ConcreteInterfaceTypeMatches(candidate.declaredType, requirement.returnType) Then Return False
		If candidate.parameters.length <> requirement.parameters.length Then Return False
		For Local index:Int = 0 Until candidate.parameters.length
			If Not ConcreteInterfaceTypeMatches(candidate.parameters[index].semanticType, requirement.parameters[index].semanticType) Then Return False
			If candidate.parameters[index].passingMode <> requirement.parameters[index].passingMode Then Return False
		Next
		Return True
	End Method

	Method ConcreteInterfaceTypeMatches:Int(candidate:TSemanticType, requirementType:String)
		If TypeName(candidate).ToLower() = requirementType.ToLower() Then Return True
		' Specialized generic Interface records use canonical rank-bearing Array
		' names (for example int[1]), while source-facing semantic names retain
		' BlitzMax spelling (Int[]). Compare the canonical closed type before
		' falling through to runtime ABI identities.
		If CanonicalSemanticTypeName(candidate) = requirementType.ToLower() Then Return True
		Local separator:Int = requirementType.Find(":")
		If separator < 0 Then Return False
		Local runtimeKind:String = requirementType[..separator].ToLower()
		Local runtimeAbiName:String = requirementType[separator + 1..]
		Select runtimeKind
			Case "@runtime-class"
				Local irClass:TCompilerIrClass = ClassForType(candidate)
				Return irClass And irClass.abiName.ToLower() = runtimeAbiName.ToLower()
			Case "@runtime-interface"
				Local irInterface:TCompilerIrInterface = InterfaceForType(candidate)
				Return irInterface And irInterface.abiName.ToLower() = runtimeAbiName.ToLower()
			Case "@runtime-struct"
				Local irStruct:TCompilerIrStruct = StructForType(candidate)
				Return irStruct And irStruct.abiName.ToLower() = runtimeAbiName.ToLower()
			Case "@runtime-enum"
				Local irEnum:TCompilerIrEnum = EnumForType(candidate)
				Return irEnum And irEnum.abiName.ToLower() = runtimeAbiName.ToLower()
		End Select
		Return False
	End Method

	Method CollectImplementedInterfaces(typeSymbol:TSymbol, interfaces:TNamedSemanticType[] Var, seen:TMap)
		If Not typeSymbol Then Return
		Local baseSymbol:TSymbol = ExplicitBaseSymbol(typeSymbol)
		If baseSymbol Then CollectImplementedInterfaces(baseSymbol, interfaces, seen)
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(typeSymbol)
		If Not info Then Return
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
			Local namedInterface:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
			CollectInterfaceClosure(namedInterface, interfaces, seen)
		Next
	End Method

	Method CollectInterfaceClosure(namedInterface:TNamedSemanticType, interfaces:TNamedSemanticType[] Var, seen:TMap)
		If Not namedInterface Or Not namedInterface.symbol Or seen.Contains(namedInterface.symbol) Then Return
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(namedInterface.symbol)
		If info Then
			Local interfaceEdges:TInheritanceEdge[] = info.baseEdges + info.interfaceEdges
			For Local edge:TInheritanceEdge = EachIn interfaceEdges
				CollectInterfaceClosure(TNamedSemanticType(edge.semanticType), interfaces, seen)
			Next
		End If
		If Not seen.Contains(namedInterface.symbol) Then
			seen.Insert(namedInterface.symbol, namedInterface.symbol)
			interfaces :+ [namedInterface]
		End If
	End Method

	Method FindInterfaceImplementation:TSymbol(typeSymbol:TSymbol, requirement:TSymbol, interfaceType:TNamedSemanticType)
		If Not typeSymbol Or Not requirement Then Return Null
		If typeSymbol.memberScope Then
			Local validator:TInheritanceValidator = New TInheritanceValidator
			validator.model = analysis.model
			For Local candidate:TSymbol = EachIn typeSymbol.memberScope.LookupLocal(requirement.name)
				If candidate.kind = SYMBOL_ROUTINE And Not candidate.isAbstract And validator.OverrideSignaturesMatch(candidate, requirement, interfaceType) Then Return candidate
			Next
		End If
		Local baseSymbol:TSymbol = ExplicitBaseSymbol(typeSymbol)
		If baseSymbol Then Return FindInterfaceImplementation(baseSymbol, requirement, interfaceType)
		Return Null
	End Method

	Method CompleteClassRoutines(symbol:TSymbol)
		If completedClassRoutines.Contains(symbol) Then Return
		Local owner:TCompilerIrClass = TCompilerIrClass(classesBySymbol.ValueForKey(symbol))
		If Not owner Then Return
		Local baseType:TSemanticType = ExplicitBaseType(symbol)
		Local namedBase:TNamedSemanticType = TNamedSemanticType(baseType)
		Local baseSymbol:TSymbol
		If namedBase Then baseSymbol = namedBase.symbol
		Local baseClass:TCompilerIrClass
		If baseSymbol Then baseClass = TCompilerIrClass(classesBySymbol.ValueForKey(baseSymbol))
		If baseClass Then
			CompleteClassRoutines(baseSymbol)
			For Local inherited:TCompilerIrClassFunctionSlot = EachIn baseClass.functionSlots
				owner.functionSlots :+ [CloneClassSlot(inherited)]
			Next
			owner.toStringFunctionId = baseClass.toStringFunctionId
			owner.compareFunctionId = baseClass.compareFunctionId
			owner.sendMessageFunctionId = baseClass.sendMessageFunctionId
			owner.hashCodeFunctionId = baseClass.hashCodeFunctionId
			owner.equalsFunctionId = baseClass.equalsFunctionId
		Else If owner.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(owner.baseImportedClassId)
			If importedBase Then
				For Local inherited:TCompilerIrClassFunctionSlot = EachIn importedBase.functionSlots
					owner.functionSlots :+ [CloneClassSlot(inherited)]
				Next
				owner.toStringFunctionId = importedBase.toStringFunctionId
				owner.compareFunctionId = importedBase.compareFunctionId
				owner.sendMessageFunctionId = importedBase.sendMessageFunctionId
				owner.hashCodeFunctionId = importedBase.hashCodeFunctionId
				owner.equalsFunctionId = importedBase.equalsFunctionId
			End If
		End If
		If symbol.memberScope Then
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If member.kind = SYMBOL_ROUTINE Then BuildRoutineShell(member, owner, baseSymbol, Null, baseType)
			Next
		End If
		If owner.isAbstract Then CompleteAbstractInterfaceSlots(symbol, owner)
		completedClassRoutines.Insert(symbol, symbol)
	End Method

	Method BuildRoutineShell(symbol:TSymbol, owner:TCompilerIrClass, baseSymbol:TSymbol = Null, ownerStruct:TCompilerIrStruct = Null, baseType:TSemanticType = Null)
		If functionsBySymbol.Contains(symbol) Then Return
		If GenericRoutineTemplatePlanned(symbol) Then Return
		If Not IsLowerableRoutine(symbol) Then Return
		Local routine:TCompilerIrFunction = New TCompilerIrFunction
		routine.functionId = "fn" + nextFunctionId
		nextFunctionId :+ 1
		Local functionLiteral:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(symbol.declaration)
		routine.name = symbol.name
		routine.debugName = routine.name
		routine.noMangle = symbol.metadata And symbol.metadata.Has("nomangle")
		routine.abiName = TCompilerAbiNamer.RoutineName(analysis.model, symbol, routine.functionId)
		Local legacySourceUnit:String = SourceOf(symbol.declaration).path
		If options And options.sourceUnitPath.length Then legacySourceUnit = options.sourceUnitPath
		If options And options.applicationSourceUnit And routine.noMangle Then
			routine.legacyAliasName = TCompilerAbiNamer.LegacyApplicationSourceRoutineName(symbol, legacySourceUnit)
		Else If (analysis.model And analysis.model.moduleName.length) Or routine.noMangle Then
			routine.legacyAliasName = TCompilerAbiNamer.LegacySourceRoutineName(analysis.model, symbol, legacySourceUnit)
		End If
		If functionLiteral Then routine.legacyAliasName = ""
		If genericPlan And genericPlan.specializationRoutineAbis.Contains(symbol) Then routine.abiName = String(genericPlan.specializationRoutineAbis.ValueForKey(symbol))
		routine.returnType = TypeName(symbol.declaredType)
		routine.isIteratorFactory = symbol.isIteratorRoutine
		If symbol.iteratorElementType Then routine.iteratorElementType = TypeName(symbol.iteratorElementType)
		Local callableReturn:TCallableSemanticType = TCallableSemanticType(symbol.declaredType)
		If callableReturn Then
			routine.callableReturnType = TypeName(callableReturn.returnType)
			routine.callableReturnParameters = CallableParameters(callableReturn)
			routine.callableReturnCallingConvention = callableReturn.callingConvention
		End If
		routine.callingConvention = symbol.callingConvention
		routine.visibility = symbol.visibility
		routine.source = SourceForSymbol(symbol)
		If functionLiteral Then
			routine.isFunctionLiteral = True
			routine.debugName = FunctionLiteralDebugName(symbol, functionLiteral, routine.source)
		End If
		If routine.noMangle Then
			routine.abiName = routine.legacyAliasName
		End If
		routine.metadata = MetadataOf(symbol)
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If callableReturn And declaration And declaration.signature And declaration.signature.callableReturnType Then ApplyCallableParameterNames(routine.callableReturnParameters, declaration.signature.callableReturnType)
		routine.isMethod = declaration And declaration.isMethod
		' Production bcc assigns the next numeric linkage suffix when a source
		' unit declares a top-level routine whose natural ABI name is already
		' owned by an imported source unit.  This is distinct from overload
		' mangling: the declarations may have identical parameters and differ
		' only by a covariant result, as in replaceable application services.
		' Retain that source-unit shadowing ABI so both public headers can be
		' included together without conflicting C prototypes, and do not
		' recreate the occupied unsuffixed alias.
		If Not owner And Not ownerStruct And Not routine.isMethod And Not routine.noMangle And routine.visibility = VISIBILITY_PUBLIC Then
			Local shadowSuffix:Int = ImportedRoutineShadowSuffix(routine.abiName)
			If shadowSuffix Then
				routine.abiName :+ String(shadowSuffix)
				routine.suppressLegacyAlias = True
			End If
		End If
		routine.isAbstract = symbol.isAbstract
		routine.isFinal = RoutineDeclarationIsFinal(declaration)
		If routine.isMethod And symbol.name.ToLower() = "new" Then routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR
		If routine.isMethod And symbol.name.ToLower() = "delete" Then routine.lifecycleKind = IR_LIFECYCLE_DESTRUCTOR
		If ownerStruct And routine.lifecycleKind = IR_LIFECYCLE_DESTRUCTOR Then
			AddUnsupported("BMXC1195", "Structs have C value lifetime and cannot declare a Delete method", declaration)
			Return
		End If
		If routine.isMethod Then routine.objectSlotKind = ObjectSlotKind(symbol)
		If owner Then
			routine.ownerClassId = owner.classId
		End If
		If ownerStruct Then routine.ownerStructId = ownerStruct.structId
		If owner And owner.isPublished And routine.isMethod Then
			routine.implementationAbiName = routine.abiName
			If Not routine.implementationAbiName.StartsWith("_") Then routine.implementationAbiName = "_" + routine.implementationAbiName
			' Production compact interfaces publish Type constructors by their
			' actual pointer-receiver implementation identity. Ordinary methods
			' retain their unprefixed linkage identity.
			If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then routine.abiName = routine.implementationAbiName
		End If
		If ownerStruct And ownerStruct.isPublished And routine.isMethod Then routine.implementationAbiName = "_" + routine.abiName
		ApplyInstrumentation(routine, declaration)
		functionsBySymbol.Insert(symbol, routine)
		routineSymbols :+ [symbol]
		result.functions :+ [routine]
		If ownerStruct And routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then ownerStruct.constructorFunctionIds :+ [routine.functionId]
		If owner And routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then
			If symbol.parameters.length = 0 Then owner.defaultConstructorFunctionId = routine.functionId
		Else If owner And routine.lifecycleKind = IR_LIFECYCLE_DESTRUCTOR Then
			owner.destructorFunctionId = routine.functionId
		Else If owner And routine.objectSlotKind <> IR_OBJECT_SLOT_NONE Then
			SetObjectSlotFunction(owner, routine.objectSlotKind, routine.functionId)
		Else If owner Then
			Local slot:TCompilerIrClassFunctionSlot
			Local overridden:TSymbol
			Local dispatchKey:String = TCompilerAbiNamer.ClassSlotName(symbol)
			If routine.isMethod And baseSymbol Then
				Local validator:TInheritanceValidator = New TInheritanceValidator
				validator.model = analysis.model
				Local overriddenBaseType:TSemanticType = baseType
				If Not overriddenBaseType Then overriddenBaseType = baseSymbol.declaredType
				overridden = validator.OverriddenRoutine(symbol, overriddenBaseType, 0)
				If overridden Then slot = TCompilerIrClassFunctionSlot(slotsByRoutineSymbol.ValueForKey(overridden))
				If overridden And Not slot And owner.baseImportedClassId.length Then
					Local importedBase:TCompilerIrImportedClass = ImportedClassById(owner.baseImportedClassId)
					Local importedOverride:TCompilerIrImportedMethod = GenericImportedMethod(importedBase, overridden)
					If importedOverride Then
						For Local importedSlot:TCompilerIrClassFunctionSlot = EachIn importedBase.functionSlots
							If importedSlot.slotName = importedOverride.slotName Then slot = importedSlot; Exit
						Next
					End If
				End If
				If Not slot Then
					For Local inheritedIndex:Int = 0 Until owner.functionSlots.length
						Local inheritedSlot:TCompilerIrClassFunctionSlot = owner.functionSlots[inheritedIndex]
						If inheritedSlot.isMethod And inheritedSlot.isAbstract And inheritedSlot.dispatchKey = dispatchKey Then
							slot = inheritedSlot
							Exit
						End If
					Next
				End If
			Else If Not routine.isMethod Then
				' Type functions are statically selected rather than virtual,
				' but their class-table entry still occupies ABI layout. A
				' same-signature declaration hides the inherited entry in
				' place, even when its return type is more specific.
				For Local inheritedIndex:Int = 0 Until owner.functionSlots.length
					Local inheritedSlot:TCompilerIrClassFunctionSlot = owner.functionSlots[inheritedIndex]
					If Not inheritedSlot.isMethod And inheritedSlot.dispatchKey = dispatchKey Then
						slot = CloneClassSlot(inheritedSlot)
						owner.functionSlots[inheritedIndex] = slot
						Exit
					End If
				Next
			End If
			If slot Then
				If routine.isMethod Then
					slot = CloneClassSlot(slot)
					For Local index:Int = 0 Until owner.functionSlots.length
						If owner.functionSlots[index].slotId = slot.slotId Then owner.functionSlots[index] = slot; Exit
					Next
				End If
			Else
				slot = New TCompilerIrClassFunctionSlot
				slot.slotId = "cf" + owner.functionSlots.length
				slot.dispatchKey = dispatchKey
				slot.declaringClassId = owner.classId
				If owner.isPublished Then slot.slotName = TCompilerAbiNamer.ClassSlotName(symbol)
				owner.functionSlots :+ [slot]
			End If
			If Not slot.dispatchKey.length Then slot.dispatchKey = dispatchKey
			routine.classSlotId = slot.slotId
			slot.functionId = routine.functionId
			slot.name = routine.name
			slot.abiName = routine.abiName
			slot.returnType = routine.returnType
			slot.callableReturnType = routine.callableReturnType
			slot.callableReturnParameters = routine.callableReturnParameters
			slot.callableReturnCallingConvention = routine.callableReturnCallingConvention
			slot.callingConvention = routine.callingConvention
			slot.source = routine.source
			slot.metadata = routine.metadata
			slot.isMethod = routine.isMethod
			slot.isAbstract = routine.isAbstract
			If routine.isMethod Then slot.receiverClassId = owner.classId
			If routine.isMethod Then slot.receiverImportedClassId = ""
			slotsByRoutineSymbol.Insert(symbol, slot)
		End If
		BuildNestedRoutineShells(symbol.memberScope)
	End Method

	Method FunctionLiteralDebugName:String(symbol:TSymbol, literal:TFunctionLiteralExpressionSyntax, source:TCompilerSourceLocation)
		Local kind:String = "Function"
		If literal And TClosureSemanticType(analysis.model.ExpressionType(literal)) Then kind = "Closure"
		Local owner:TSymbol = ContainingRoutineSymbol(symbol)
		While owner And TFunctionLiteralExpressionSyntax(owner.declaration)
			owner = ContainingRoutineSymbol(owner)
		Wend
		Local ownerName:String = "module initialization"
		If owner Then ownerName = owner.name
		Local result:String = kind + " in " + ownerName
		If source And source.line > 0 Then result :+ " at line " + source.line
		Return result
	End Method

	Method ImportedRoutineShadowSuffix:Int(baseAbiName:String)
		If Not analysis Or Not analysis.model Or Not baseAbiName.length Then Return 0
		If Not ImportedRoutineAbiInUse(baseAbiName) Then Return 0
		Local suffix:Int = 2
		While ImportedRoutineAbiInUse(baseAbiName + suffix)
			suffix :+ 1
		Wend
		Return suffix
	End Method

	Method ImportedRoutineAbiInUse:Int(abiName:String)
		For Local importedScope:TScope = EachIn analysis.model.importedScopes
			For Local importedSymbol:TSymbol = EachIn importedScope.declaredSymbols
				If importedSymbol.kind <> SYMBOL_ROUTINE Or Not importedSymbol.externalName.length Then Continue
				If importedSymbol.externalName.ToLower() = abiName.ToLower() Then Return True
			Next
		Next
		Return False
	End Method

	Method CompleteAbstractInterfaceSlots(symbol:TSymbol, owner:TCompilerIrClass)
		If Not symbol Or Not owner Then Return
		Local implementedInterfaces:TCompilerIrInterface[] = New TCompilerIrInterface[0]
		CollectImplementedInterfaceRecords(symbol, implementedInterfaces, New TMap)
		For Local irInterface:TCompilerIrInterface = EachIn implementedInterfaces
			For Local interfaceMethod:TCompilerIrInterfaceMethod = EachIn irInterface.methods
				Local requirement:TSymbol = TSymbol(interfaceMethodSymbols.ValueForKey(interfaceMethod))
				If Not requirement Then Continue
				If requirement.interfaceMethodKind = INTERFACE_METHOD_DEFAULT Then Continue
				Local namedInterface:TNamedSemanticType = InterfaceSemanticTypeForSymbol(symbol, irInterface)
				If namedInterface And FindInterfaceImplementation(symbol, requirement, namedInterface) Then Continue
				Local dispatchKey:String = TCompilerAbiNamer.ClassMethodSlotName(requirement)
				Local existingSlot:TCompilerIrClassFunctionSlot
				For Local candidate:TCompilerIrClassFunctionSlot = EachIn owner.functionSlots
					If candidate.isMethod And candidate.dispatchKey = dispatchKey Then existingSlot = candidate; Exit
				Next
				If existingSlot Then Continue

				Local abstractRoutine:TCompilerIrFunction = EnsureAbstractInterfaceFunction(requirement, irInterface, interfaceMethod)
				If Not abstractRoutine Then Continue
				Local slot:TCompilerIrClassFunctionSlot = New TCompilerIrClassFunctionSlot
				slot.slotId = "cf" + owner.functionSlots.length
				slot.dispatchKey = dispatchKey
				slot.declaringClassId = owner.classId
				slot.receiverClassId = owner.classId
				slot.functionId = abstractRoutine.functionId
				slot.name = interfaceMethod.name
				slot.abiName = abstractRoutine.abiName
				If owner.isPublished Then slot.slotName = dispatchKey
				slot.returnType = interfaceMethod.returnType
				slot.callableReturnType = interfaceMethod.callableReturnType
				slot.callableReturnParameters = interfaceMethod.callableReturnParameters
				slot.callableReturnCallingConvention = interfaceMethod.callableReturnCallingConvention
				slot.callingConvention = interfaceMethod.callingConvention
				slot.parameters = interfaceMethod.parameters
				slot.isMethod = True
				slot.isAbstract = True
				slot.source = interfaceMethod.source
				owner.functionSlots :+ [slot]
			Next
		Next
	End Method

	Method EnsureAbstractInterfaceFunction:TCompilerIrFunction(requirement:TSymbol, irInterface:TCompilerIrInterface, interfaceMethod:TCompilerIrInterfaceMethod)
		Local existing:TCompilerIrFunction = TCompilerIrFunction(abstractInterfaceFunctionsByMethod.ValueForKey(requirement))
		If existing Then Return existing
		Local routine:TCompilerIrFunction = New TCompilerIrFunction
		routine.functionId = "fn" + nextFunctionId
		nextFunctionId :+ 1
		routine.name = interfaceMethod.name
		routine.abiName = interfaceMethod.abiName
		If routine.abiName.length Then routine.implementationAbiName = "_" + routine.abiName
		routine.returnType = interfaceMethod.returnType
		routine.callableReturnType = interfaceMethod.callableReturnType
		routine.callableReturnParameters = interfaceMethod.callableReturnParameters
		routine.callableReturnCallingConvention = interfaceMethod.callableReturnCallingConvention
		routine.callingConvention = interfaceMethod.callingConvention
		routine.parameters = interfaceMethod.parameters
		routine.isMethod = True
		routine.isAbstract = True
		routine.ownerInterfaceId = irInterface.interfaceId
		routine.source = interfaceMethod.source
		Local receiver:TCompilerIrParameter = New TCompilerIrParameter
		receiver.symbolId = "abstract_receiver_" + routine.functionId
		receiver.name = "self"
		receiver.semanticType = irInterface.semanticType
		routine.receiver = receiver
		result.functions :+ [routine]
		abstractInterfaceFunctionsByMethod.Insert(requirement, routine)
		Return routine
	End Method

	Method BuildNestedRoutineShells(scope:TScope)
		If Not scope Then Return
		For Local nested:TSymbol = EachIn scope.declaredSymbols
			If nested.kind = SYMBOL_ROUTINE Then BuildRoutineShell(nested, Null)
		Next
		For Local child:TScope = EachIn scope.children
			' A nested routine owns its own subtree and BuildRoutineShell has
			' already traversed it. Descend through lexical control-flow scopes,
			' where BlitzMax also permits local Function declarations.
			If child And child.kind <> SCOPE_ROUTINE Then BuildNestedRoutineShells(child)
		Next
	End Method

	Function ObjectSlotKind:Int(symbol:TSymbol)
		If Not symbol Then Return IR_OBJECT_SLOT_NONE
		Local returnType:String = TypeName(symbol.declaredType).ToLower()
		Select symbol.name.ToLower()
			Case "tostring"
				If symbol.parameters.length = 0 And returnType = "string" Then Return IR_OBJECT_SLOT_TO_STRING
			Case "compare"
				If symbol.parameters.length = 1 And returnType = "int" And TypeName(symbol.parameters[0].semanticType).ToLower() = "object" Then Return IR_OBJECT_SLOT_COMPARE
			Case "sendmessage"
				If symbol.parameters.length = 2 And returnType = "object" And TypeName(symbol.parameters[0].semanticType).ToLower() = "object" And TypeName(symbol.parameters[1].semanticType).ToLower() = "object" Then Return IR_OBJECT_SLOT_SEND_MESSAGE
			Case "hashcode"
				If symbol.parameters.length = 0 And returnType = "uint" Then Return IR_OBJECT_SLOT_HASH_CODE
			Case "equals"
				If symbol.parameters.length = 1 And returnType = "int" And TypeName(symbol.parameters[0].semanticType).ToLower() = "object" Then Return IR_OBJECT_SLOT_EQUALS
		End Select
		Return IR_OBJECT_SLOT_NONE
	End Function

	Function SetObjectSlotFunction(irClass:TCompilerIrClass, slotKind:Int, functionId:String)
		Select slotKind
			Case IR_OBJECT_SLOT_TO_STRING
				irClass.toStringFunctionId = functionId
			Case IR_OBJECT_SLOT_COMPARE
				irClass.compareFunctionId = functionId
			Case IR_OBJECT_SLOT_SEND_MESSAGE
				irClass.sendMessageFunctionId = functionId
			Case IR_OBJECT_SLOT_HASH_CODE
				irClass.hashCodeFunctionId = functionId
			Case IR_OBJECT_SLOT_EQUALS
				irClass.equalsFunctionId = functionId
		End Select
	End Function

	Function CloneClassSlot:TCompilerIrClassFunctionSlot(source:TCompilerIrClassFunctionSlot)
		Local slot:TCompilerIrClassFunctionSlot = New TCompilerIrClassFunctionSlot
		slot.slotId = source.slotId
		slot.dispatchKey = source.dispatchKey
		slot.declaringClassId = source.declaringClassId
		slot.declaringImportedClassId = source.declaringImportedClassId
		slot.receiverClassId = source.receiverClassId
		slot.receiverImportedClassId = source.receiverImportedClassId
		slot.functionId = source.functionId
		slot.name = source.name
		slot.abiName = source.abiName
		slot.slotName = source.slotName
		slot.returnType = source.returnType
		slot.callableReturnType = source.callableReturnType
		slot.callableReturnParameters = source.callableReturnParameters
		slot.callableReturnCallingConvention = source.callableReturnCallingConvention
		slot.callingConvention = source.callingConvention
		slot.parameters = source.parameters
		slot.isMethod = source.isMethod
		slot.isAbstract = source.isAbstract
		slot.source = source.source
		slot.metadata = source.metadata
		Return slot
	End Function

	Method LowerFunctionBodies()
		If Not analysis Or Not analysis.model Or result.functions.length = 0 Then Return
		nextSymbolId = 0
		currentRoutine = result.functions[0]
		currentRoutineSymbol = Null
		currentIncomingClosureCapturePlan = Null
		currentOwnedClosureCapturePlan = moduleClosureCapturePlan
		' Module statements may directly read or assign Type/Struct-owned
		' Globals. Publish all of those storage identities before lowering the
		' module body, just as routine bodies require them to be available
		' independently of source traversal order.
		RegisterAllTypeStaticSymbols()
		result.functions[0].body = LowerBlock(analysis.model.boundGlobalBody)
		If moduleClosureCapturePlan Then PrependCaptureEnvironment(result.functions[0], moduleClosureCapturePlan)
		LowerExternalConstants(result.functions[0].body)
		LowerTypeStaticDeclarations(result.functions[0].body)
		BuildDebugScope(result.functions[0])
		LowerFieldInitializers()
		For Local symbol:TSymbol = EachIn routineSymbols
			Local routine:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(symbol))
			If Not routine Then Continue
			nextSymbolId = 0
			currentRoutine = routine
			currentRoutineSymbol = symbol
			currentOwnedClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByOwner.ValueForKey(symbol))
			currentIncomingClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByLiteral.ValueForKey(symbol))
			currentReceiver = Null
			currentClass = Null
			currentStruct = Null
			If routine.isMethod Then
				currentReceiver = New TCompilerIrParameter
				currentReceiver.symbolId = "self"
				currentReceiver.name = "self"
				Local owner:TCompilerIrClass = ClassById(routine.ownerClassId)
				If owner Then
					currentClass = owner
					currentReceiver.semanticType = owner.semanticType
				Else If routine.ownerStructId.length Then
					currentStruct = StructById(routine.ownerStructId)
					If currentStruct Then
						currentReceiver.semanticType = currentStruct.semanticType
						currentReceiver.passingMode = PARAMETER_PASS_VAR
					End If
				Else If routine.ownerInterfaceId.length Then
					Local ownerInterface:TCompilerIrInterface = InterfaceById(routine.ownerInterfaceId)
					If ownerInterface Then currentReceiver.semanticType = ownerInterface.semanticType
				End If
				routine.receiver = currentReceiver
			End If
			Local parameterOffset:Int
			Local functionLiteralSyntax:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(symbol.declaration)
			If functionLiteralSyntax And TClosureSemanticType(analysis.model.ExpressionType(functionLiteralSyntax)) Then
				routine.isClosureInvoke = True
				parameterOffset = 1
			End If
			routine.parameters = New TCompilerIrParameter[symbol.parameters.length + parameterOffset]
			If parameterOffset Then
				Local environmentParameter:TCompilerIrParameter = New TCompilerIrParameter
				environmentParameter.symbolId = routine.functionId + "_environment"
				environmentParameter.name = "environment"
				environmentParameter.semanticType = "Object"
				routine.parameters[0] = environmentParameter
			End If
			Local routineDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
			For Local index:Int = 0 Until symbol.parameters.length
				Local parameter:TSemanticParameter = symbol.parameters[index]
				Local irParameter:TCompilerIrParameter = New TCompilerIrParameter
				If parameter And parameter.symbol Then
					irParameter.symbolId = RegisterSymbol(parameter.symbol, "p")
					irParameter.name = parameter.symbol.name
					irParameter.semanticType = TypeName(parameter.semanticType)
					irParameter.passingMode = parameter.passingMode
					If parameter.passingMode = PARAMETER_PASS_VAR Then byReferenceSymbols.Insert(parameter.symbol, parameter.symbol)
					irParameter.isOptional = parameter.optional
					PopulateParameterDefault(irParameter, parameter)
					PopulateParameterShape(irParameter, parameter.semanticType)
					If routineDeclaration And routineDeclaration.signature And index < routineDeclaration.signature.parameters.length Then
						ApplyCallableParameterNames(irParameter.callableParameters, routineDeclaration.signature.parameters[index].callableType)
					End If
				End If
				routine.parameters[index + parameterOffset] = irParameter
			Next
			' Class layouts are cloned before routine bodies populate their exact
			' parameter IR. Update every effective slot that targets this routine,
			' including copies inherited by already-completed derived classes.
			For Local irClass:TCompilerIrClass = EachIn result.classes
				For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
					If slot.functionId = routine.functionId Then slot.parameters = routine.parameters
				Next
			Next
			Local boundBody:TBoundBlockStatement = analysis.model.BoundRoutineBody(symbol)
			Local firstStatement:Int
			If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then firstStatement = CaptureConstructorChain(routine, boundBody)
			If Not routine.isAbstract Then
				routine.body = LowerBlock(boundBody, firstStatement)
				Local ownerCapturePlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByOwner.ValueForKey(symbol))
				If ownerCapturePlan Then PrependCaptureEnvironment(routine, ownerCapturePlan)
			End If
			If routine.isIteratorFactory And Not routine.isAbstract Then BuildIteratorStateMachine(symbol, routine)
			BuildDebugScope(routine)
			currentReceiver = Null
			currentRoutine = Null
			currentRoutineSymbol = Null
			currentIncomingClosureCapturePlan = Null
			currentOwnedClosureCapturePlan = Null
			currentClass = Null
			currentStruct = Null
		Next
	End Method

	Method BuildIteratorStateMachine(symbol:TSymbol, factory:TCompilerIrFunction)
		If Not symbol Or Not factory Or Not factory.body Or Not symbol.iteratorElementType Then Return
		Local stateClass:TCompilerIrClass = New TCompilerIrClass
		stateClass.classId = "cls" + nextClassId
		nextClassId :+ 1
		stateClass.name = "$IteratorState_" + factory.functionId
		stateClass.semanticType = stateClass.name
		stateClass.visibility = VISIBILITY_PRIVATE
		stateClass.source = factory.source
		stateClass.hasManagedFields = True
		result.classes :+ [stateClass]

		factory.iteratorStateClassId = stateClass.classId
		factory.iteratorStateFieldId = factory.functionId + "_iterator_state"
		factory.iteratorCurrentFieldId = factory.functionId + "_iterator_current"
		AppendIteratorField(stateClass, factory.iteratorStateFieldId, "$State", "Int", factory.source)
		AppendIteratorField(stateClass, factory.iteratorCurrentFieldId, "$Current", factory.iteratorElementType, factory.source)
		If factory.receiver Then
			factory.iteratorSelfFieldId = factory.functionId + "_iterator_self"
			AppendIteratorField(stateClass, factory.iteratorSelfFieldId, "Self", factory.receiver.semanticType, factory.source)
		End If
		For Local parameter:TCompilerIrParameter = EachIn factory.parameters
			If parameter.passingMode = PARAMETER_PASS_VAR Then
				AddUnsupported("BMXC1250", "yielding routines cannot retain Var parameters beyond the creating call", symbol.declaration)
				Continue
			End If
			Local retainedParameterType:String = parameter.semanticType
			If parameter.isStaticArray Then retainedParameterType = parameter.staticArrayElementType + " Ptr"
			AppendIteratorField(stateClass, parameter.symbolId, parameter.name, retainedParameterType, factory.source)
		Next
		CollectIteratorStateFields(factory.body, stateClass, factory)
		Local nextState:Int = 1
		AssignIteratorResumeStates(factory.body, nextState)

		Local moveNext:TCompilerIrFunction = NewIteratorMethod(stateClass, "MoveNext", "Int", factory)
		moveNext.isIteratorMoveNext = True
		moveNext.iteratorElementType = factory.iteratorElementType
		moveNext.iteratorFactoryFunctionId = factory.functionId
		moveNext.body = factory.body
		factory.iteratorMoveNextFunctionId = moveNext.functionId

		Local current:TCompilerIrFunction = NewIteratorMethod(stateClass, "Current", factory.iteratorElementType, factory)
		current.isIteratorCurrent = True
		current.iteratorElementType = factory.iteratorElementType
		current.iteratorFactoryFunctionId = factory.functionId
		factory.iteratorCurrentFunctionId = current.functionId

		Local closeMethod:TCompilerIrFunction = NewIteratorMethod(stateClass, "Close", "Void", factory)
		closeMethod.isIteratorClose = True
		closeMethod.iteratorElementType = factory.iteratorElementType
		closeMethod.iteratorFactoryFunctionId = factory.functionId
		factory.iteratorCloseFunctionId = closeMethod.functionId

		factory.body = New TCompilerIrBlock
		factory.body.source = factory.source
		BuildIteratorInterfaceTables(symbol, stateClass, factory, moveNext, current, closeMethod)
	End Method

	Method AppendIteratorField(stateClass:TCompilerIrClass, iteratorFieldId:String, iteratorFieldName:String, iteratorFieldType:String, iteratorFieldSource:TCompilerSourceLocation)
		If Not stateClass Then Return
		If Not iteratorFieldId.length Then Return
		For Local existing:TCompilerIrClassField = EachIn stateClass.fields
			If existing.fieldId = iteratorFieldId Then Return
		Next
		Local stateField:TCompilerIrClassField = New TCompilerIrClassField
		stateField.fieldId = iteratorFieldId
		stateField.declaringClassId = stateClass.classId
		stateField.name = iteratorFieldName
		stateField.semanticType = iteratorFieldType
		stateField.visibility = VISIBILITY_PRIVATE
		stateField.source = iteratorFieldSource
		stateClass.fields :+ [stateField]
		stateClass.declaredFieldCount :+ 1
	End Method

	Method AppendIteratorStaticArrayField(stateClass:TCompilerIrClass, variable:TCompilerIrVariableDeclaration)
		If Not stateClass Or Not variable Or Not variable.isStaticArray Or Not variable.symbolId.length Then Return
		For Local existing:TCompilerIrClassField = EachIn stateClass.fields
			If existing.fieldId = variable.symbolId Then Return
		Next
		Local stateField:TCompilerIrClassField = New TCompilerIrClassField
		stateField.fieldId = variable.symbolId
		stateField.declaringClassId = stateClass.classId
		stateField.name = variable.name
		stateField.semanticType = variable.semanticType
		stateField.visibility = VISIBILITY_PRIVATE
		stateField.source = variable.source
		stateField.isStaticArray = True
		stateField.staticArrayElementType = variable.staticArrayElementType
		stateField.staticArrayStructId = variable.staticArrayStructId
		stateField.staticArrayImportedStructId = variable.staticArrayImportedStructId
		stateField.staticArrayLength = variable.staticArrayLength
		stateClass.fields :+ [stateField]
		stateClass.declaredFieldCount :+ 1
	End Method

	Method CollectIteratorStateFields(block:TCompilerIrBlock, stateClass:TCompilerIrClass, factory:TCompilerIrFunction)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
			If variable And variable.storage <> "global" And variable.storage <> "constant" Then
				If variable.isStaticArray Then
					AppendIteratorStaticArrayField(stateClass, variable)
				Else
					AppendIteratorField(stateClass, variable.symbolId, variable.name, variable.semanticType, variable.source)
				End If
			End If
			Local conditionalIf:TCompilerIrIf = TCompilerIrIf(statement)
			If conditionalIf Then
				CollectIteratorStateFields(conditionalIf.thenBody, stateClass, factory)
				For Local clause:TCompilerIrConditionalClause = EachIn conditionalIf.elseIfClauses
					CollectIteratorStateFields(clause.body, stateClass, factory)
				Next
				CollectIteratorStateFields(conditionalIf.elseBody, stateClass, factory)
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					CollectIteratorStateFields(selectedCase.body, stateClass, factory)
				Next
				CollectIteratorStateFields(selected.defaultBody, stateClass, factory)
			End If
			Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
			If whileStatement Then CollectIteratorStateFields(whileStatement.body, stateClass, factory)
			Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
			If repeatStatement Then CollectIteratorStateFields(repeatStatement.body, stateClass, factory)
			Local rangeStatement:TCompilerIrForRange = TCompilerIrForRange(statement)
			If rangeStatement Then
				If rangeStatement.declaresVariable Then AppendIteratorField(stateClass, rangeStatement.variableSymbolId, rangeStatement.variableName, rangeStatement.variableType, rangeStatement.source)
				CollectIteratorStateFields(rangeStatement.body, stateClass, factory)
			End If
			Local eachArray:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
			If eachArray Then
				If IteratorBlockContainsYield(eachArray.body) Then
					AppendIteratorField(stateClass, eachArray.collectionTemporaryId, "$EachCollection", eachArray.collection.semanticType, eachArray.source)
					AppendIteratorField(stateClass, eachArray.indexTemporaryId, "$EachIndex", "UInt", eachArray.source)
					AppendIteratorField(stateClass, eachArray.elementTemporaryId, "$EachElement", eachArray.elementType, eachArray.source)
					If eachArray.declaresVariable Then AppendIteratorField(stateClass, eachArray.variableSymbolId, eachArray.variableName, eachArray.variableType, eachArray.source)
				End If
				CollectIteratorStateFields(eachArray.body, stateClass, factory)
			End If
			Local eachString:TCompilerIrForEachString = TCompilerIrForEachString(statement)
			If eachString Then
				If IteratorBlockContainsYield(eachString.body) Then
					AppendIteratorField(stateClass, eachString.collectionTemporaryId, "$EachString", "String", eachString.source)
					AppendIteratorField(stateClass, eachString.indexTemporaryId, "$EachIndex", "UInt", eachString.source)
					AppendIteratorField(stateClass, eachString.elementTemporaryId, "$EachElement", "Int", eachString.source)
					If eachString.declaresVariable Then AppendIteratorField(stateClass, eachString.variableSymbolId, eachString.variableName, eachString.variableType, eachString.source)
				End If
				CollectIteratorStateFields(eachString.body, stateClass, factory)
			End If
			Local eachStatic:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
			If eachStatic Then
				If IteratorBlockContainsYield(eachStatic.body) Then
					AppendIteratorField(stateClass, eachStatic.collectionTemporaryId, "$EachStaticArray", eachStatic.elementType + " Ptr", eachStatic.source)
					AppendIteratorField(stateClass, eachStatic.indexTemporaryId, "$EachIndex", "UInt", eachStatic.source)
					AppendIteratorField(stateClass, eachStatic.elementTemporaryId, "$EachElement", eachStatic.elementType, eachStatic.source)
					If eachStatic.declaresVariable Then AppendIteratorField(stateClass, eachStatic.variableSymbolId, eachStatic.variableName, eachStatic.variableType, eachStatic.source)
				End If
				CollectIteratorStateFields(eachStatic.body, stateClass, factory)
			End If
			Local eachObject:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
			If eachObject Then
				If IteratorBlockContainsYield(eachObject.body) Then
					AppendIteratorField(stateClass, eachObject.collectionTemporaryId, "$EachCollection", eachObject.collectionType, eachObject.source)
					AppendIteratorField(stateClass, eachObject.iteratorTemporaryId, "$EachIterator", eachObject.iteratorType, eachObject.source)
					AppendIteratorField(stateClass, eachObject.elementTemporaryId, "$EachElement", eachObject.elementType, eachObject.source)
					If eachObject.declaresVariable Then AppendIteratorField(stateClass, eachObject.variableSymbolId, eachObject.variableName, eachObject.variableType, eachObject.source)
					If eachObject.iteratorCleanup And eachObject.iteratorCleanup.variable Then
						AppendIteratorField(stateClass, eachObject.iteratorCleanup.variable.symbolId, "$EachCloseable", eachObject.iteratorCleanup.variable.semanticType, eachObject.source)
						factory.iteratorOwnedResources :+ [eachObject.iteratorCleanup]
					End If
				End If
				CollectIteratorStateFields(eachObject.body, stateClass, factory)
			End If
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				Local guardedYield:Int = IteratorBlockContainsYield(guarded.body)
				For Local handler:TCompilerIrCatch = EachIn guarded.catches
					If IteratorBlockContainsYield(handler.body) Then guardedYield = True
				Next
				If IteratorBlockContainsYield(guarded.finallyBody) Then AddUnsupported("BMXC1252", "Yield inside Finally is not supported; Yield from the protected Try or Catch body instead", Null)
				If guardedYield Then
					guarded.retainedInIterator = True
					If guarded.finallyBody Then
						guarded.iteratorExceptionFieldId = NewTemporaryId()
						guarded.iteratorFailedFieldId = NewTemporaryId()
						AppendIteratorField(stateClass, guarded.iteratorExceptionFieldId, "$TryException", "Object", guarded.source)
						AppendIteratorField(stateClass, guarded.iteratorFailedFieldId, "$TryFailed", "Int", guarded.source)
					End If
					For Local handler:TCompilerIrCatch = EachIn guarded.catches
						If IteratorBlockContainsYield(handler.body) Then AppendIteratorField(stateClass, handler.parameterSymbolId, handler.parameterName, handler.parameterType, handler.source)
					Next
				End If
				CollectIteratorStateFields(guarded.body, stateClass, factory)
				For Local handler:TCompilerIrCatch = EachIn guarded.catches
					CollectIteratorStateFields(handler.body, stateClass, factory)
				Next
				CollectIteratorStateFields(guarded.finallyBody, stateClass, factory)
			End If
			Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
			If usingStatement Then
				If IteratorBlockContainsYield(usingStatement.body) Then
					usingStatement.retainedInIterator = True
					For Local resource:TCompilerIrUsingResource = EachIn usingStatement.resources
						If Not resource Or Not resource.variable Then Continue
						AppendIteratorField(stateClass, resource.variable.symbolId, resource.variable.name, resource.variable.semanticType, resource.variable.source)
						factory.iteratorOwnedResources :+ [resource]
					Next
				End If
				CollectIteratorStateFields(usingStatement.body, stateClass, factory)
			End If
		Next
	End Method

	Function IteratorBlockContainsYield:Int(block:TCompilerIrBlock)
		If Not block Then Return False
		For Local statement:TCompilerIrStatement = EachIn block.statements
			If TCompilerIrYield(statement) Then Return True
			Local conditionalIf:TCompilerIrIf = TCompilerIrIf(statement)
			If conditionalIf Then
				If IteratorBlockContainsYield(conditionalIf.thenBody) Or IteratorBlockContainsYield(conditionalIf.elseBody) Then Return True
				For Local clause:TCompilerIrConditionalClause = EachIn conditionalIf.elseIfClauses
					If IteratorBlockContainsYield(clause.body) Then Return True
				Next
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					If IteratorBlockContainsYield(selectedCase.body) Then Return True
				Next
				If IteratorBlockContainsYield(selected.defaultBody) Then Return True
			End If
			If TCompilerIrWhile(statement) And IteratorBlockContainsYield(TCompilerIrWhile(statement).body) Then Return True
			If TCompilerIrRepeat(statement) And IteratorBlockContainsYield(TCompilerIrRepeat(statement).body) Then Return True
			If TCompilerIrForRange(statement) And IteratorBlockContainsYield(TCompilerIrForRange(statement).body) Then Return True
			If TCompilerIrForEachArray(statement) And IteratorBlockContainsYield(TCompilerIrForEachArray(statement).body) Then Return True
			If TCompilerIrForEachString(statement) And IteratorBlockContainsYield(TCompilerIrForEachString(statement).body) Then Return True
			If TCompilerIrForEachStaticArray(statement) And IteratorBlockContainsYield(TCompilerIrForEachStaticArray(statement).body) Then Return True
			If TCompilerIrForEachObject(statement) And IteratorBlockContainsYield(TCompilerIrForEachObject(statement).body) Then Return True
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				If IteratorBlockContainsYield(guarded.body) Or IteratorBlockContainsYield(guarded.finallyBody) Then Return True
				For Local handler:TCompilerIrCatch = EachIn guarded.catches
					If IteratorBlockContainsYield(handler.body) Then Return True
				Next
			End If
			If TCompilerIrUsing(statement) And IteratorBlockContainsYield(TCompilerIrUsing(statement).body) Then Return True
		Next
		Return False
	End Function

	Method AssignIteratorResumeStates(block:TCompilerIrBlock, nextState:Int Var)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local yielded:TCompilerIrYield = TCompilerIrYield(statement)
			If yielded Then
				yielded.resumeState = nextState
				nextState :+ 1
			End If
			Local conditionalIf:TCompilerIrIf = TCompilerIrIf(statement)
			If conditionalIf Then
				AssignIteratorResumeStates(conditionalIf.thenBody, nextState)
				For Local clause:TCompilerIrConditionalClause = EachIn conditionalIf.elseIfClauses
					AssignIteratorResumeStates(clause.body, nextState)
				Next
				AssignIteratorResumeStates(conditionalIf.elseBody, nextState)
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					AssignIteratorResumeStates(selectedCase.body, nextState)
				Next
				AssignIteratorResumeStates(selected.defaultBody, nextState)
			End If
			If TCompilerIrWhile(statement) Then AssignIteratorResumeStates(TCompilerIrWhile(statement).body, nextState)
			If TCompilerIrRepeat(statement) Then AssignIteratorResumeStates(TCompilerIrRepeat(statement).body, nextState)
			If TCompilerIrForRange(statement) Then AssignIteratorResumeStates(TCompilerIrForRange(statement).body, nextState)
			If TCompilerIrForEachArray(statement) Then AssignIteratorResumeStates(TCompilerIrForEachArray(statement).body, nextState)
			If TCompilerIrForEachString(statement) Then AssignIteratorResumeStates(TCompilerIrForEachString(statement).body, nextState)
			If TCompilerIrForEachStaticArray(statement) Then AssignIteratorResumeStates(TCompilerIrForEachStaticArray(statement).body, nextState)
			If TCompilerIrForEachObject(statement) Then AssignIteratorResumeStates(TCompilerIrForEachObject(statement).body, nextState)
			If TCompilerIrUsing(statement) Then AssignIteratorResumeStates(TCompilerIrUsing(statement).body, nextState)
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				AssignIteratorResumeStates(guarded.body, nextState)
				For Local handler:TCompilerIrCatch = EachIn guarded.catches
					AssignIteratorResumeStates(handler.body, nextState)
				Next
				AssignIteratorResumeStates(guarded.finallyBody, nextState)
			End If
		Next
	End Method

	Method NewIteratorMethod:TCompilerIrFunction(stateClass:TCompilerIrClass, name:String, returnType:String, factory:TCompilerIrFunction)
		Local routine:TCompilerIrFunction = New TCompilerIrFunction
		routine.functionId = "fn" + nextFunctionId
		nextFunctionId :+ 1
		routine.name = name
		routine.debugName = factory.debugName + "." + name
		routine.abiName = "bmx_iterator_" + routine.functionId + "_" + name.ToLower()
		routine.returnType = returnType
		routine.isMethod = True
		routine.ownerClassId = stateClass.classId
		routine.visibility = VISIBILITY_PRIVATE
		routine.source = factory.source
		routine.iteratorStateClassId = stateClass.classId
		routine.receiver = New TCompilerIrParameter
		routine.receiver.symbolId = routine.functionId + "_self"
		routine.receiver.name = "self"
		routine.receiver.semanticType = stateClass.semanticType
		result.functions :+ [routine]
		Return routine
	End Method

	Method BuildIteratorInterfaceTables(symbol:TSymbol, stateClass:TCompilerIrClass, factory:TCompilerIrFunction, moveNext:TCompilerIrFunction, current:TCompilerIrFunction, closeMethod:TCompilerIrFunction)
		Local interfaces:TCompilerIrInterface[]
		Local seen:TMap = New TMap
		Local direct:TCompilerIrInterface = InterfaceForType(symbol.declaredType)
		AppendIteratorInterfaceClosure(direct, interfaces, seen)
		Local closeInterface:TCompilerIrInterface = EnsureImportedRuntimeInterface("brl_blitz_ICloseable")
		AppendIteratorInterfaceClosure(closeInterface, interfaces, seen)
		For Local irInterface:TCompilerIrInterface = EachIn interfaces
			stateClass.declaredInterfaceIds :+ [irInterface.interfaceId]
			Local implementation:TCompilerIrInterfaceImplementation = New TCompilerIrInterfaceImplementation
			implementation.interfaceId = irInterface.interfaceId
			implementation.slots = New TCompilerIrInterfaceImplementationSlot[irInterface.methods.length]
			For Local index:Int = 0 Until irInterface.methods.length
				Local target:TCompilerIrFunction
				Select irInterface.methods[index].name.ToLower()
					Case "movenext"
						target = moveNext
					Case "current"
						target = current
					Case "close"
						target = closeMethod
				End Select
				If Not target Then
					AddUnsupported("BMXC1253", "iterator Interface method '" + irInterface.methods[index].name + "' has no generated implementation", symbol.declaration)
					Continue
				End If
				Local slot:TCompilerIrInterfaceImplementationSlot = New TCompilerIrInterfaceImplementationSlot
				slot.interfaceSlotId = irInterface.methods[index].slotId
				slot.functionId = target.functionId
				slot.receiverClassId = stateClass.classId
				implementation.slots[index] = slot
			Next
			stateClass.interfaceImplementations :+ [implementation]
		Next
	End Method

	Method AppendIteratorInterfaceClosure(irInterface:TCompilerIrInterface, interfaces:TCompilerIrInterface[] Var, seen:TMap)
		If Not irInterface Or seen.Contains(irInterface.interfaceId) Then Return
		For Local parentId:String = EachIn irInterface.baseInterfaceIds
			AppendIteratorInterfaceClosure(InterfaceById(parentId), interfaces, seen)
		Next
		seen.Insert(irInterface.interfaceId, irInterface)
		interfaces :+ [irInterface]
	End Method

	Method ActiveSuperDispatchClass:TCompilerIrClass()
		If currentClass Then Return currentClass
		Local selfPlan:TCompilerClosureCapturePlan = CaptureSelfPlan(currentIncomingClosureCapturePlan)
		If selfPlan And selfPlan.selfType Then
			Return ClassForType(selfPlan.selfType)
		End If
		Return Null
	End Method

	Method PrependCaptureEnvironment(routine:TCompilerIrFunction, plan:TCompilerClosureCapturePlan)
		If Not routine Or Not routine.body Or Not plan Or Not plan.environmentClass Then Return
		Local environmentVariable:TCompilerIrVariableDeclaration = New TCompilerIrVariableDeclaration
		environmentVariable.kind = IR_STATEMENT_VARIABLE
		environmentVariable.source = routine.source
		environmentVariable.symbolId = plan.environmentSymbolId
		environmentVariable.name = "$closureEnvironment"
		environmentVariable.semanticType = plan.environmentClass.semanticType
		environmentVariable.storage = "capture-environment"
		environmentVariable.hasExplicitInitializer = True
		Local allocation:TCompilerIrObjectNew = New TCompilerIrObjectNew
		allocation.kind = IR_EXPRESSION_OBJECT_NEW
		allocation.semanticType = plan.environmentClass.semanticType
		allocation.source = routine.source
		allocation.classId = plan.environmentClass.classId
		environmentVariable.initializer = allocation
		Local prefix:TCompilerIrStatement[] = [environmentVariable]
		If plan.parentPlan Then
			If Not plan.parentField Or Not currentIncomingClosureCapturePlan Then
				AddUnsupported("BMXC1249", "nested Closure environment has no active parent environment", plan.ownerSymbol.declaration)
			Else
				Local parentAssignment:TCompilerIrAssignment = New TCompilerIrAssignment
				parentAssignment.kind = IR_STATEMENT_ASSIGNMENT
				parentAssignment.source = routine.source
				parentAssignment.target = CaptureParentFieldAccess(plan, CaptureEnvironmentReference(plan, parentAssignment.source), parentAssignment.source)
				parentAssignment.value = CaptureEnvironmentReference(plan.parentPlan, parentAssignment.source)
				prefix :+ [parentAssignment]
			End If
		End If
		If plan.capturesSelf Then
			If Not currentReceiver Or Not plan.selfField Then
				AddUnsupported("BMXC1249", "capturing Closure has no active instance receiver", plan.ownerSymbol.declaration)
			Else
				Local selfAssignment:TCompilerIrAssignment = New TCompilerIrAssignment
				selfAssignment.kind = IR_STATEMENT_ASSIGNMENT
				selfAssignment.source = routine.source
				selfAssignment.target = CaptureSelfFieldAccess(plan, selfAssignment.source)
				Local selfReference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
				selfReference.kind = IR_EXPRESSION_SYMBOL
				selfReference.semanticType = TypeName(plan.selfType)
				selfReference.source = routine.source
				selfReference.symbolId = currentReceiver.symbolId
				selfReference.name = currentReceiver.name
				selfAssignment.value = selfReference
				prefix :+ [selfAssignment]
			End If
		End If

		For Local captured:TSymbol = EachIn plan.captures
			Local assignment:TCompilerIrAssignment = New TCompilerIrAssignment
			assignment.kind = IR_STATEMENT_ASSIGNMENT
			assignment.source = SourceOf(captured.declaration)
			assignment.target = CaptureFieldAccess(plan, captured, captured.declaredType, assignment.source)
			If captured.kind = SYMBOL_PARAMETER Then
				Local parameterReference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
				parameterReference.kind = IR_EXPRESSION_SYMBOL
				parameterReference.semanticType = TypeName(captured.declaredType)
				parameterReference.source = assignment.source
				parameterReference.symbolId = SymbolId(captured)
				parameterReference.name = captured.name
				assignment.value = parameterReference
			Else
				assignment.value = CaptureDefaultValue(captured.declaredType, assignment.source, captured.declaration)
			End If
			prefix :+ [assignment]
		Next
		routine.body.statements = prefix + routine.body.statements
	End Method

	Method PrependIterationCaptureEnvironment(body:TCompilerIrBlock, plan:TCompilerClosureCapturePlan, headerSymbol:TSymbol = Null, headerValue:TCompilerIrExpression = Null)
		If Not body Or Not plan Or Not plan.iterationScoped Or Not plan.environmentClass Then Return
		PrependActivationCaptureEnvironment(body, plan, headerSymbol, headerValue, "capture-environment-iteration", "loop")
	End Method

	Method PrependCatchCaptureEnvironment(body:TCompilerIrBlock, plan:TCompilerClosureCapturePlan, parameterSymbol:TSymbol, parameterValue:TCompilerIrExpression)
		If Not body Or Not plan Or Not plan.catchScoped Or Not plan.environmentClass Then Return
		PrependActivationCaptureEnvironment(body, plan, parameterSymbol, parameterValue, "capture-environment-catch", "Catch")
	End Method

	Method PrependActivationCaptureEnvironment(body:TCompilerIrBlock, plan:TCompilerClosureCapturePlan, headerSymbol:TSymbol, headerValue:TCompilerIrExpression, storage:String, activationName:String)
		If Not body Or Not plan Or Not plan.activationScoped Or Not plan.environmentClass Then Return
		Local source:TCompilerSourceLocation = SourceOf(plan.storageScope.syntax)
		Local environmentVariable:TCompilerIrVariableDeclaration = New TCompilerIrVariableDeclaration
		environmentVariable.kind = IR_STATEMENT_VARIABLE
		environmentVariable.source = source
		environmentVariable.symbolId = plan.environmentSymbolId
		environmentVariable.name = "$closureEnvironment"
		environmentVariable.semanticType = plan.environmentClass.semanticType
		environmentVariable.storage = storage
		environmentVariable.hasExplicitInitializer = True
		Local allocation:TCompilerIrObjectNew = New TCompilerIrObjectNew
		allocation.kind = IR_EXPRESSION_OBJECT_NEW
		allocation.semanticType = plan.environmentClass.semanticType
		allocation.source = source
		allocation.classId = plan.environmentClass.classId
		environmentVariable.initializer = allocation
		Local prefix:TCompilerIrStatement[] = [environmentVariable]
		If plan.parentPlan Then
			Local environmentReference:TCompilerIrExpression = CaptureEnvironmentReference(plan, source)
			Local parentReference:TCompilerIrExpression = CaptureEnvironmentReference(plan.parentPlan, source)
			If Not plan.parentField Or Not environmentReference Or Not parentReference Then
				AddUnsupported("BMXC1249", activationName + " Closure environment has no active parent environment", plan.storageScope.syntax)
			Else
				Local parentAssignment:TCompilerIrAssignment = New TCompilerIrAssignment
				parentAssignment.kind = IR_STATEMENT_ASSIGNMENT
				parentAssignment.source = source
				parentAssignment.target = CaptureParentFieldAccess(plan, environmentReference, source)
				parentAssignment.value = parentReference
				prefix :+ [parentAssignment]
			End If
		End If
		For Local captured:TSymbol = EachIn plan.captures
			Local assignment:TCompilerIrAssignment = New TCompilerIrAssignment
			assignment.kind = IR_STATEMENT_ASSIGNMENT
			assignment.source = SourceOf(captured.declaration)
			assignment.target = CaptureFieldAccess(plan, captured, captured.declaredType, assignment.source)
			If captured = headerSymbol And headerValue Then assignment.value = headerValue Else assignment.value = CaptureDefaultValue(captured.declaredType, assignment.source, captured.declaration)
			prefix :+ [assignment]
		Next
		body.statements = prefix + body.statements
	End Method

	Method DirectSymbolReference:TCompilerIrSymbolReference(symbol:TSymbol, source:TCompilerSourceLocation)
		If Not symbol Then Return Null
		Local reference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		reference.kind = IR_EXPRESSION_SYMBOL
		reference.source = source
		reference.semanticType = TypeName(symbol.declaredType)
		reference.symbolId = SymbolId(symbol)
		reference.name = symbol.name
		Return reference
	End Method

	Method CaptureDefaultValue:TCompilerIrExpression(semanticType:TSemanticType, source:TCompilerSourceLocation, syntax:TSyntaxNode)
		Local callableType:TCallableSemanticType = TCallableSemanticType(semanticType)
		If callableType Then Return CallableDefault(callableType, source)
		If TClosureSemanticType(semanticType) Then Return ManagedDefault(TypeName(semanticType), IR_MANAGED_REFERENCE_CLOSURE, source)
		If StructForType(semanticType) Or ImportedStructForType(semanticType) Then Return StructDefault(semanticType, source, syntax)
		If IsStringType(semanticType) Then Return ManagedDefault("String", IR_MANAGED_REFERENCE_STRING, source)
		If IsArrayType(semanticType) Then Return ManagedDefault(TypeName(semanticType), IR_MANAGED_REFERENCE_ARRAY, source)
		If IsObjectReferenceType(semanticType) Then Return ManagedDefault(TypeName(semanticType), IR_MANAGED_REFERENCE_OBJECT, source)
		If EnumForType(semanticType) Then Return EnumDefault(semanticType, source)
		Return ScalarDefault(TypeName(semanticType), source)
	End Method

	Method RegisterAllTypeStaticSymbols()
		Local ownerSymbols:TSymbol[] = classSymbols + structSymbols
		For Local symbol:TSymbol = EachIn ownerSymbols
			If Not symbol Then Continue
			Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
			If Not declaration Or Not declaration.body Then Continue
			Local body:TBoundBlockStatement = TBoundBlockStatement(analysis.model.BoundStatement(declaration.body))
			If body Then RegisterTypeStaticSymbols(body)
		Next
	End Method

	Method LowerExternalConstants(body:TCompilerIrBlock)
		If Not body Or Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			If Not symbol Or symbol.kind <> SYMBOL_CONST Or Not symbol.isExternal Then Continue
			Local constantValue:TConstantValue = analysis.model.SymbolConstantValue(symbol)
			If Not constantValue Then
				AddUnsupported("BMXC1102", "Extern Const '" + symbol.name + "' has no compile-time value", symbol.declaration)
				Continue
			End If
			Local declaration:TCompilerIrVariableDeclaration = New TCompilerIrVariableDeclaration
			declaration.kind = IR_STATEMENT_VARIABLE
			declaration.source = SourceOf(symbol.declaration)
			declaration.symbolId = RegisterSymbol(symbol, "g")
			declaration.name = symbol.name
			declaration.semanticType = TypeName(symbol.declaredType)
			declaration.storage = "constant"
			declaration.visibility = symbol.visibility
			declaration.isReadOnly = True
			declaration.metadata = MetadataOf(symbol)
			declaration.initializer = LowerConstantDefault(constantValue, symbol.declaredType, symbol, symbol.declaration)
			If options And options.debugInstrumentation Then declaration.debugConstantStringLiteralId = RegisterStringValue(DebugConstantText(constantValue), declaration.source).literalId
			body.statements :+ [declaration]
		Next
	End Method

	Method LowerTypeStaticDeclarations(globalBody:TCompilerIrBlock)
		If Not globalBody Or Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		Local bodies:TBoundBlockStatement[] = New TBoundBlockStatement[0]
		Local ownerSymbols:TSymbol[] = classSymbols + structSymbols
		For Local symbol:TSymbol = EachIn ownerSymbols
			If Not symbol Then Continue
			Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
			If Not declaration Or Not declaration.body Then Continue
			Local body:TBoundBlockStatement = TBoundBlockStatement(analysis.model.BoundStatement(declaration.body))
			If body Then bodies :+ [body]
		Next
		' Register the complete owner-static set before lowering any initializer,
		' so deterministic forward and sibling references never depend on source
		' traversal having already emitted storage.
		For Local body:TBoundBlockStatement = EachIn bodies
			RegisterTypeStaticSymbols(body)
		Next
		Local typeStaticStatements:TCompilerIrStatement[] = New TCompilerIrStatement[0]
		For Local body:TBoundBlockStatement = EachIn bodies
			typeStaticStatements :+ LowerTypeStaticStatements(body)
		Next
		' Production initialization establishes Type/Struct-owned static state
		' before evaluating module Globals. Module initializers may call Type
		' methods whose implementation depends on that static state (Reflection's
		' intrinsic TTypeId construction is the canonical example).
		globalBody.statements = typeStaticStatements + globalBody.statements
	End Method

	Method RegisterTypeStaticSymbols(body:TBoundBlockStatement)
		If Not body Then Return
		For Local statement:TBoundStatement = EachIn body.statements
			Local variables:TBoundVariableDeclarationStatement = TBoundVariableDeclarationStatement(statement)
			If Not variables Then Continue
			For Local variable:TBoundVariable = EachIn variables.variables
				If variable And variable.symbol And (variable.symbol.kind = SYMBOL_GLOBAL Or variable.symbol.kind = SYMBOL_CONST) And Not GenericStaticMemberSymbol(variable.symbol) Then RegisterSymbol(variable.symbol, "g")
			Next
		Next
	End Method

	Method LowerTypeStaticStatements:TCompilerIrStatement[](body:TBoundBlockStatement)
		Local lowered:TCompilerIrStatement[] = New TCompilerIrStatement[0]
		If Not body Then Return lowered
		For Local statement:TBoundStatement = EachIn body.statements
			Local variables:TBoundVariableDeclarationStatement = TBoundVariableDeclarationStatement(statement)
			If Not variables Then Continue
			Local coverageMarked:Int
			For Local variable:TBoundVariable = EachIn variables.variables
				If Not variable Or Not variable.symbol Or (variable.symbol.kind <> SYMBOL_GLOBAL And variable.symbol.kind <> SYMBOL_CONST) Then Continue
				If GenericStaticMemberSymbol(variable.symbol) Then Continue
				Local single:TBoundVariableDeclarationStatement = New TBoundVariableDeclarationStatement
				single.boundKind = BOUND_STATEMENT_VARIABLE_DECLARATION
				single.syntax = variables.syntax
				single.variables = [variable]
				Local irStatement:TCompilerIrStatement = LowerStatement(single)
				If irStatement Then
					If Not coverageMarked Then
						MarkCoveragePoint(irStatement, variables.syntax)
						coverageMarked = irStatement.coveragePoint
					End If
					lowered :+ [irStatement]
				End If
			Next
		Next
		Return lowered
	End Method

	Function GenericStaticMemberSymbol:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_GLOBAL Then Return False
		Local scope:TScope = symbol.containingScope
		While scope
			Local owner:TSymbol = scope.owner
			If owner And (owner.kind = SYMBOL_TYPE Or owner.kind = SYMBOL_STRUCT) Then
				If owner.genericArity > 0 Then Return True
				Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(owner.declaration)
				If declaration And declaration.header And declaration.header.genericParameters.length Then Return True
			End If
			scope = scope.parent
		Wend
		Return False
	End Function

	Method BuildDebugScope(routine:TCompilerIrFunction)
		If Not routine Or Not routine.debugInstrumentation Or routine.suppressDebugInfo Then Return
		Local scope:TCompilerIrDebugScope = New TCompilerIrDebugScope
		scope.scopeKind = IR_DEBUG_SCOPE_FUNCTION
		scope.name = routine.debugName
		If Not scope.name.length Then scope.name = routine.name
		If routine.isGlobalEntry Then scope.name = StripDirAndExtension(result.path)
		If routine.source Then scope.sourceId = routine.source.debugSourceId
		If routine.receiver Then scope.variables :+ [DebugVariable(routine.receiver, True)]
		For Local index:Int = 0 Until routine.parameters.length
			' The erased environment is an implementation parameter. Captured
			' source variables are published separately with their true addresses.
			If routine.isClosureInvoke And index = 0 Then Continue
			scope.variables :+ [DebugVariable(routine.parameters[index], False)]
		Next
		AppendBlockDebugVariables(scope, routine.body)
		AppendClosureDebugVariables(scope, routine)
		routine.debugScope = scope
		If routine.body Then routine.body.debugScope = scope
		BuildNestedDebugScopes(routine.body)
	End Method

	Method AppendClosureDebugVariables(scope:TCompilerIrDebugScope, routine:TCompilerIrFunction)
		If Not scope Or Not routine Or Not routine.isClosureInvoke Or Not currentRoutineSymbol Then Return
		Local literal:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(currentRoutineSymbol.declaration)
		Local bound:TBoundFunctionLiteralExpression
		If literal Then bound = TBoundFunctionLiteralExpression(analysis.model.BoundExpression(literal))
		If Not bound Then Return
		If bound.capturesSelf Then
			Local selfPlan:TCompilerClosureCapturePlan = CaptureSelfPlan(currentIncomingClosureCapturePlan)
			Local selfAddress:TCompilerIrExpression = CaptureSelfFieldAccess(selfPlan, routine.source)
			If selfAddress Then
				Local selfVariable:TCompilerIrDebugVariable = New TCompilerIrDebugVariable
				selfVariable.name = "Self"
				selfVariable.semanticType = TypeName(bound.capturedSelfType)
				PopulateDebugVariableShape(selfVariable, bound.capturedSelfType)
				selfVariable.isReceiver = True
				selfVariable.address = selfAddress
				scope.variables :+ [selfVariable]
			End If
		End If
		For Local captured:TSymbol = EachIn bound.captures
			Local plan:TCompilerClosureCapturePlan = CaptureSymbolPlan(currentIncomingClosureCapturePlan, captured)
			Local captureAddress:TCompilerIrExpression = CaptureFieldAccess(plan, captured, captured.declaredType, SourceOf(captured.declaration))
			If Not captureAddress Then Continue
			Local variable:TCompilerIrDebugVariable = New TCompilerIrDebugVariable
			variable.symbolId = SymbolId(captured)
			variable.name = captured.name
			variable.semanticType = TypeName(captured.declaredType)
			PopulateDebugVariableShape(variable, captured.declaredType)
			variable.address = captureAddress
			scope.variables :+ [variable]
		Next
	End Method

	Method BuildNestedDebugScopes(block:TCompilerIrBlock)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local conditionalIf:TCompilerIrIf = TCompilerIrIf(statement)
			If conditionalIf Then
				BuildLocalDebugScope(conditionalIf.thenBody)
				For Local clause:TCompilerIrConditionalClause = EachIn conditionalIf.elseIfClauses
					If clause Then BuildLocalDebugScope(clause.body)
				Next
				BuildLocalDebugScope(conditionalIf.elseBody)
				Continue
			End If
			Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
			If whileStatement Then
				BuildLocalDebugScope(whileStatement.body)
				Continue
			End If
			Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
			If repeatStatement Then
				BuildLocalDebugScope(repeatStatement.body)
				Continue
			End If
			Local forStatement:TCompilerIrForRange = TCompilerIrForRange(statement)
			If forStatement Then
				Local loopVariable:TCompilerIrDebugVariable
				If forStatement.declaresVariable Then loopVariable = LoopDebugVariable(forStatement.variableSymbolId, forStatement.variableName, forStatement.variableType)
				BuildLocalDebugScope(forStatement.body, loopVariable)
				Continue
			End If
			Local arrayEach:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
			If arrayEach Then
				Local loopVariable:TCompilerIrDebugVariable
				If arrayEach.declaresVariable And Not arrayEach.variableName.StartsWith("$deconstruct") Then loopVariable = LoopDebugVariable(arrayEach.variableSymbolId, arrayEach.variableName, arrayEach.variableType)
				BuildLocalDebugScope(arrayEach.body, loopVariable)
				Continue
			End If
			Local stringEach:TCompilerIrForEachString = TCompilerIrForEachString(statement)
			If stringEach Then
				Local loopVariable:TCompilerIrDebugVariable
				If stringEach.declaresVariable And Not stringEach.variableName.StartsWith("$deconstruct") Then loopVariable = LoopDebugVariable(stringEach.variableSymbolId, stringEach.variableName, stringEach.variableType)
				BuildLocalDebugScope(stringEach.body, loopVariable)
				Continue
			End If
			Local staticEach:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
			If staticEach Then
				Local loopVariable:TCompilerIrDebugVariable
				If staticEach.declaresVariable And Not staticEach.variableName.StartsWith("$deconstruct") Then loopVariable = LoopDebugVariable(staticEach.variableSymbolId, staticEach.variableName, staticEach.variableType)
				BuildLocalDebugScope(staticEach.body, loopVariable)
				Continue
			End If
			Local objectEach:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
			If objectEach Then
				Local loopVariable:TCompilerIrDebugVariable
				If objectEach.declaresVariable And Not objectEach.variableName.StartsWith("$deconstruct") Then loopVariable = LoopDebugVariable(objectEach.variableSymbolId, objectEach.variableName, objectEach.variableType)
				BuildLocalDebugScope(objectEach.body, loopVariable)
			End If
		Next
	End Method

	Method BuildLocalDebugScope(block:TCompilerIrBlock, leadingVariable:TCompilerIrDebugVariable = Null)
		If Not block Then Return
		Local scope:TCompilerIrDebugScope = New TCompilerIrDebugScope
		scope.scopeKind = IR_DEBUG_SCOPE_LOCAL_BLOCK
		If block.source Then scope.sourceId = block.source.debugSourceId
		If leadingVariable Then scope.variables :+ [leadingVariable]
		AppendBlockDebugVariables(scope, block)
		block.debugScope = scope
		BuildNestedDebugScopes(block)
	End Method

	Method AppendBlockDebugVariables(scope:TCompilerIrDebugScope, block:TCompilerIrBlock)
		If Not scope Or Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local declaration:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
			If declaration And declaration.storage = "constant" Then scope.variables :+ [ConstantDebugVariable(declaration)]
		Next
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local declaration:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
			If declaration And declaration.storage = "global" Then scope.variables :+ [GlobalDebugVariable(declaration)]
		Next
		For Local statement:TCompilerIrStatement = EachIn block.statements
			Local declaration:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
			If declaration And declaration.storage = "local" Then scope.variables :+ [LocalDebugVariable(declaration)]
		Next
	End Method

	Method ConstantDebugVariable:TCompilerIrDebugVariable(declaration:TCompilerIrVariableDeclaration)
		Local variable:TCompilerIrDebugVariable = LocalDebugVariable(declaration)
		variable.declarationKind = IR_DEBUG_DECL_CONSTANT
		variable.constantStringLiteralId = declaration.debugConstantStringLiteralId
		Return variable
	End Method

	Method GlobalDebugVariable:TCompilerIrDebugVariable(declaration:TCompilerIrVariableDeclaration)
		Local variable:TCompilerIrDebugVariable = LocalDebugVariable(declaration)
		variable.declarationKind = IR_DEBUG_DECL_GLOBAL
		Return variable
	End Method

	Method LocalDebugVariable:TCompilerIrDebugVariable(declaration:TCompilerIrVariableDeclaration)
		Local variable:TCompilerIrDebugVariable = New TCompilerIrDebugVariable
		variable.symbolId = declaration.symbolId
		variable.name = declaration.name
		variable.semanticType = declaration.semanticType
		variable.callableReturnType = declaration.callableReturnType
		variable.callableParameters = declaration.callableParameters
		variable.callableCallingConvention = declaration.callableCallingConvention
		variable.arrayCallableReturnType = declaration.arrayCallableReturnType
		variable.arrayCallableParameters = declaration.arrayCallableParameters
		variable.arrayCallableCallingConvention = declaration.arrayCallableCallingConvention
		variable.arrayCallableRank = declaration.arrayCallableRank
		Return variable
	End Method

	Method LoopDebugVariable:TCompilerIrDebugVariable(symbolId:String, name:String, semanticType:String)
		Local variable:TCompilerIrDebugVariable = New TCompilerIrDebugVariable
		variable.symbolId = symbolId
		variable.name = name
		variable.semanticType = semanticType
		Return variable
	End Method

	Method DebugVariable:TCompilerIrDebugVariable(parameter:TCompilerIrParameter, isReceiver:Int)
		Local variable:TCompilerIrDebugVariable = New TCompilerIrDebugVariable
		variable.symbolId = parameter.symbolId
		variable.name = parameter.name
		If isReceiver Then variable.name = "Self"
		variable.semanticType = parameter.semanticType
		variable.callableReturnType = parameter.callableReturnType
		variable.callableParameters = parameter.callableParameters
		variable.callableCallingConvention = parameter.callableCallingConvention
		variable.passingMode = parameter.passingMode
		' Struct receivers use a pointer in the C calling convention, but the
		' debugger declaration describes the pointed-to value as Self.
		If isReceiver Then variable.passingMode = PARAMETER_PASS_VALUE
		variable.isReceiver = isReceiver
		Return variable
	End Method

	Method PopulateDebugVariableShape(variable:TCompilerIrDebugVariable, semanticType:TSemanticType)
		If Not variable Or Not semanticType Then Return
		Local callable:TCallableSemanticType = TCallableSemanticType(semanticType)
		If callable Then
			variable.callableReturnType = TypeName(callable.returnType)
			variable.callableParameters = CallableParameters(callable)
			variable.callableCallingConvention = callable.callingConvention
			Return
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(semanticType)
		If Not arrayType Then Return
		Local elementCallable:TCallableSemanticType = TCallableSemanticType(arrayType.elementType)
		If Not elementCallable Then Return
		variable.arrayCallableReturnType = TypeName(elementCallable.returnType)
		variable.arrayCallableParameters = CallableParameters(elementCallable)
		variable.arrayCallableCallingConvention = elementCallable.callingConvention
		variable.arrayCallableRank = arrayType.rank
	End Method

	Function StripDirAndExtension:String(path:String)
		path = path.Replace("\", "/")
		Local slash:Int = path.FindLast("/")
		If slash >= 0 Then path = path[slash + 1..]
		Local dot:Int = path.FindLast(".")
		If dot > 0 Then path = path[..dot]
		Return path
	End Function

	Method LowerFieldInitializers()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		For Local symbol:TSymbol = EachIn classSymbols
			Local owner:TCompilerIrClass = TCompilerIrClass(classesBySymbol.ValueForKey(symbol))
			If Not owner Or Not symbol.memberScope Then Continue
			currentReceiver = New TCompilerIrParameter
			currentReceiver.symbolId = "self"
			currentReceiver.name = "self"
			currentReceiver.semanticType = owner.semanticType
			currentClass = owner
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If Not member Or member.kind <> SYMBOL_FIELD Then Continue
				Local irField:TCompilerIrClassField = TCompilerIrClassField(fieldsBySymbol.ValueForKey(member))
				Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(member.declaration)
				If irField And declarator And declarator.initializer Then
					If irField.isStaticArray Then
						AddUnsupported("BMXC1019", "StaticArray Type fields currently require default initialization", declarator.initializer)
						Continue
					End If
					Local boundVariable:TBoundVariable = BoundVariableForSymbol(member)
					Local boundInitializer:TBoundExpression
					If boundVariable Then boundInitializer = boundVariable.initializer Else boundInitializer = analysis.model.BoundExpression(declarator.initializer)
					If boundInitializer Then
						irField.initializer = LowerExpression(boundInitializer)
					Else
						AddUnsupported("BMXC1145", "Field initializer did not have a bound expression", declarator.initializer)
					End If
				Else If irField And declarator And declarator.arrayDimensions.length Then
					irField.initializer = LowerFieldArrayAllocation(member, declarator)
				Else If irField And TCallableSemanticType(member.declaredType) Then
					irField.initializer = CallableDefault(TCallableSemanticType(member.declaredType), irField.source)
				End If
			Next
			currentReceiver = Null
			currentClass = Null
		Next
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			Local ownerStruct:TCompilerIrStruct = TCompilerIrStruct(structsBySymbol.ValueForKey(symbol))
			If Not ownerStruct Or Not symbol.memberScope Then Continue
			currentReceiver = New TCompilerIrParameter
			currentReceiver.symbolId = "self"
			currentReceiver.name = "self"
			currentReceiver.semanticType = ownerStruct.semanticType
			currentReceiver.passingMode = PARAMETER_PASS_VAR
			currentStruct = ownerStruct
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If Not member Or member.kind <> SYMBOL_FIELD Then Continue
				Local irField:TCompilerIrStructField = TCompilerIrStructField(structFieldsBySymbol.ValueForKey(member))
				Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(member.declaration)
				If irField And declarator And declarator.initializer Then
					If irField.isStaticArray Then
						AddUnsupported("BMXC1019", "StaticArray Struct fields currently require default initialization", declarator.initializer)
						Continue
					End If
					Local boundVariable:TBoundVariable = BoundVariableForSymbol(member)
					Local boundInitializer:TBoundExpression
					If boundVariable Then boundInitializer = boundVariable.initializer Else boundInitializer = analysis.model.BoundExpression(declarator.initializer)
					If boundInitializer Then
						irField.initializer = LowerExpression(boundInitializer)
					Else
						AddUnsupported("BMXC1194", "Struct field initializer did not have a bound expression", declarator.initializer)
					End If
				Else If irField And declarator And declarator.arrayDimensions.length Then
					irField.initializer = LowerFieldArrayAllocation(member, declarator)
				End If
			Next
			currentReceiver = Null
			currentStruct = Null
		Next
	End Method

	Method BoundVariableForSymbol:TBoundVariable(symbol:TSymbol)
		If Not symbol Or Not symbol.containingScope Or Not symbol.containingScope.owner Then Return Null
		Local ownerDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.containingScope.owner.declaration)
		If Not ownerDeclaration Or Not ownerDeclaration.body Then Return Null
		Local body:TBoundBlockStatement = TBoundBlockStatement(analysis.model.BoundStatement(ownerDeclaration.body))
		Return FindBoundVariable(body, symbol)
	End Method

	Method FindBoundVariable:TBoundVariable(body:TBoundBlockStatement, symbol:TSymbol)
		If Not body Or Not symbol Then Return Null
		For Local statement:TBoundStatement = EachIn body.statements
			Local variables:TBoundVariableDeclarationStatement = TBoundVariableDeclarationStatement(statement)
			If variables Then
				For Local variable:TBoundVariable = EachIn variables.variables
					If variable And variable.symbol = symbol Then Return variable
				Next
			End If
		Next
		Return Null
	End Method

	Method LowerFieldArrayAllocation:TCompilerIrExpression(symbol:TSymbol, declarator:TVariableDeclaratorSyntax)
		Local variable:TBoundVariable = New TBoundVariable
		variable.symbol = symbol
		variable.arrayDimensions = New TBoundExpression[declarator.arrayDimensions.length]
		For Local index:Int = 0 Until declarator.arrayDimensions.length
			variable.arrayDimensions[index] = analysis.model.BoundExpression(declarator.arrayDimensions[index])
		Next
		Return LowerDeclaredArrayAllocation(variable, declarator)
	End Method

	Method CaptureConstructorChain:Int(routine:TCompilerIrFunction, boundBody:TBoundBlockStatement)
		If Not routine Or Not boundBody Or Not boundBody.statements.length Then Return 0
		Local expressionStatement:TBoundExpressionStatement = TBoundExpressionStatement(boundBody.statements[0])
		If Not expressionStatement Then Return 0
		Local call:TBoundCallExpression = TBoundCallExpression(expressionStatement.expression)
		Local chainReceiver:TBoundSelfExpression
		If call Then chainReceiver = TBoundSelfExpression(call.receiver)
		If Not call Or Not chainReceiver Or Not call.resolvedCall Or Not call.resolvedCall.routine Then Return 0
		Local target:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(call.resolvedCall.routine))
		Local importedTarget:TCompilerIrImportedConstructor
		If Not target Then importedTarget = ImportedConstructor(call.resolvedCall.routine, call.syntax)
		If (Not target Or target.lifecycleKind <> IR_LIFECYCLE_CONSTRUCTOR) And Not importedTarget Then Return 0
		If routine.ownerStructId.length Then
			If importedTarget Then
				AddUnsupported("BMXC1200", "Struct constructors cannot delegate to an imported Type constructor", call.syntax)
				Return 0
			End If
			If target.ownerStructId <> routine.ownerStructId Then
				AddUnsupported("BMXC1200", "Struct constructors may only delegate to another constructor on the same Struct", call.syntax)
				Return 0
			End If
			routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_SAME_TYPE
		Else If target And target.ownerClassId = routine.ownerClassId Then
			routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_SAME_TYPE
		Else
			routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_BASE
		End If
		If target Then routine.chainedConstructorFunctionId = target.functionId
		If importedTarget Then routine.chainedImportedConstructorId = importedTarget.constructorId
		Local argumentsSucceeded:Int
		routine.chainedConstructorArguments = LowerResolvedArguments(call.arguments, call.resolvedCall.routine, call.syntax, argumentsSucceeded, call.resolvedCall)
		If Not argumentsSucceeded Then Return 0
		Return 1
	End Method

	Method ValidateStructConstructorChains()
		Local completed:TMap = New TMap
		Local visiting:TMap = New TMap
		For Local routine:TCompilerIrFunction = EachIn result.functions
			If routine.ownerStructId.length And routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then ValidateStructConstructorChain(routine, completed, visiting)
		Next
	End Method

	Method ValidateStructConstructorChain(routine:TCompilerIrFunction, completed:TMap, visiting:TMap)
		If Not routine Or completed.Contains(routine.functionId) Then Return
		If visiting.Contains(routine.functionId) Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC1201", "Recursive Struct constructor delegation involving '" + routine.name + "'", routine.source.path, routine.source.span)]
			Return
		End If
		visiting.Insert(routine.functionId, routine.functionId)
		If routine.chainedConstructorFunctionId.length Then ValidateStructConstructorChain(FunctionById(routine.chainedConstructorFunctionId), completed, visiting)
		visiting.Remove(routine.functionId)
		completed.Insert(routine.functionId, routine.functionId)
	End Method

	Method ClassById:TCompilerIrClass(classId:String)
		For Local irClass:TCompilerIrClass = EachIn result.classes
			If irClass.classId = classId Then Return irClass
		Next
		Return Null
	End Method

	Method StructById:TCompilerIrStruct(structId:String)
		For Local irStruct:TCompilerIrStruct = EachIn result.structs
			If irStruct.structId = structId Then Return irStruct
		Next
		Return Null
	End Method

	Method ImportedStructByIrId:TCompilerIrImportedStruct(importedStructId:String)
		For Local importedStruct:TCompilerIrImportedStruct = EachIn result.importedStructs
			If importedStruct.importedStructId = importedStructId Then Return importedStruct
		Next
		Return Null
	End Method

	Method FunctionById:TCompilerIrFunction(functionId:String)
		For Local routine:TCompilerIrFunction = EachIn result.functions
			If routine.functionId = functionId Then Return routine
		Next
		Return Null
	End Method

	Method ValidateTopLevelDeclarations()
		For Local document:TSourceDocumentModel = EachIn documents
			If Not document Or Not document.tree Or Not document.tree.root Then Continue
			ValidateTopLevelNodes(document.tree.root.members)
		Next
	End Method

	Method ValidateTopLevelNodes(nodes:TSyntaxNode[])
		For Local node:TSyntaxNode = EachIn nodes
			If TTypeDeclarationSyntax(node) Then
			Else If TEnumDeclarationSyntax(node) Then
				Local enumSymbol:TSymbol = analysis.model.DeclaredSymbol(node)
				If Not enumSymbol Or Not enumsBySymbol.Contains(enumSymbol) Then AddUnsupported("BMXC1101", "Enum declaration could not be lowered", node)
			Else If TExternBlockSyntax(node) Then
				ValidateExternBlock(TExternBlockSyntax(node))
			End If
		Next
	End Method

	Method IsLowerableRoutine:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or symbol.isImported Then Return False
		' A non-generic method or literal can still be open because its containing
		' Type is generic. Its canonical specialization unit is the sole code owner;
		' ordinary IR must not attempt to lower unresolved Type parameters.
		If HasOpenGenericOwner(symbol.containingScope) Then Return False
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		Local functionLiteral:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(symbol.declaration)
		If Not declaration And Not functionLiteral Then Return False
		If symbol.isExternal Then Return False
		If symbol.genericArity Then
			AddUnsupported("BMXC1105", "Generic routines require canonical specialization lowering", declaration)
			Return False
		End If
		If Not IsSupportedReturnType(symbol.declaredType) Then
			AddUnsupported("BMXC1106", "Routine return type '" + TypeName(symbol.declaredType) + "' is outside the scalar IR slice", declaration)
			Return False
		End If
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			Local callableType:TCallableSemanticType
			If parameter Then callableType = TCallableSemanticType(parameter.semanticType)
			If callableType And parameter.passingMode <> PARAMETER_PASS_VALUE Then
				AddUnsupported("BMXC1107", "Callable parameters require value passing in the ordinary-C ABI IR slice", declaration)
				Return False
			End If
			If callableType And declaration And declaration.isMethod And symbol.name.ToLower() = "delete" Then
				AddUnsupported("BMXC1107", "Callable destructor parameters are outside the lifecycle ABI", declaration)
				Return False
			End If
			If parameter And Not IsSupportedAbiParameterType(parameter.semanticType) Then
				AddUnsupported("BMXC1107", "Parameter type '" + TypeName(parameter.semanticType) + "' is outside the ordinary-C ABI IR slice", declaration)
				Return False
			End If
			If Not IsSupportedParameterMode(parameter) Then
				AddUnsupported("BMXC1107", "Var parameters require a directly addressable value ABI type", declaration)
				Return False
			End If
		Next
		Return True
	End Method

	Method ValidateExternBlock(external:TExternBlockSyntax)
		If Not external Or Not external.body Then Return
		ValidateExternStatements(external.body.statements)
	End Method

	Method ValidateExternStatements(nodes:TSyntaxNode[])
		For Local node:TSyntaxNode = EachIn nodes
			Local routineDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
			If routineDeclaration Then
				Local routineSymbol:TSymbol = SymbolForDeclaration(routineDeclaration)
				If Not ExternalFunction(routineSymbol, routineDeclaration) Then
					If Not routineSymbol Or Not routineSymbol.isExternal Or routineSymbol.kind <> SYMBOL_ROUTINE Then AddUnsupported("BMXC1102", "Extern routines require a native ABI binding", routineDeclaration)
				End If
				Continue
			End If
			Local variables:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
			If variables Then
				For Local declarator:TVariableDeclaratorSyntax = EachIn variables.declarators
					Local symbol:TSymbol = SymbolForDeclaration(declarator)
					' Extern Const declarations are compile-time BlitzMax
					' values. They publish no native storage and therefore need
					' no external-Global IR record.
					If symbol And symbol.kind = SYMBOL_CONST Then Continue
					If Not ResolveExternalGlobal(symbol, declarator) Then
						If Not symbol Or Not symbol.isExternal Or symbol.kind <> SYMBOL_GLOBAL Then AddUnsupported("BMXC1102", "Extern variables must be Global declarations with a native ABI binding", declarator)
					End If
				Next
				Continue
			End If
			Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
			If typeDeclaration Then
				Local symbol:TSymbol = SymbolForDeclaration(typeDeclaration)
				If symbol And symbol.kind = SYMBOL_INTERFACE And symbol.isExternal Then Continue
				Local irStruct:TCompilerIrStruct
				If symbol And symbol.kind = SYMBOL_STRUCT Then irStruct = TCompilerIrStruct(structsBySymbol.ValueForKey(symbol))
				If irStruct Then Continue
				AddUnsupported("BMXC1102", "Only Struct ABI declarations are implemented as Extern types", typeDeclaration)
				Continue
			End If
			AddUnsupported("BMXC1102", "Only routine and Global declarations are implemented in Extern blocks", node)
		Next
	End Method

	Method LowerBlock:TCompilerIrBlock(bound:TBoundBlockStatement, firstStatement:Int = 0)
		Local block:TCompilerIrBlock = New TCompilerIrBlock
		If bound Then block.source = SourceOf(bound.syntax)
		If Not bound Then
			Local message:String = "A bound statement body was not available"
			Local syntax:TSyntaxNode
			If currentRoutineSymbol Then
				message :+ " for routine '" + currentRoutineSymbol.QualifiedName() + "'"
				syntax = currentRoutineSymbol.declaration
			End If
			AddUnsupported("BMXC1000", message, syntax)
			Return block
		End If
		For Local index:Int = firstStatement Until bound.statements.length
			Local variables:TBoundVariableDeclarationStatement = TBoundVariableDeclarationStatement(bound.statements[index])
			If variables And variables.variables.length > 1 Then
				' Binding already assigned a distinct semantic symbol and
				' initializer to every declarator. Expand the statement into
				' ordered IR declarations without reconstructing or reparsing it.
				Local coverageMarked:Int
				For Local variable:TBoundVariable = EachIn variables.variables
					Local single:TBoundVariableDeclarationStatement = New TBoundVariableDeclarationStatement
					single.boundKind = BOUND_STATEMENT_VARIABLE_DECLARATION
					single.syntax = variables.syntax
					single.variables = [variable]
					Local loweredVariable:TCompilerIrStatement = LowerStatement(single)
					If loweredVariable Then
						If Not coverageMarked Then
							MarkCoveragePoint(loweredVariable, variables.syntax)
							coverageMarked = loweredVariable.coveragePoint
						End If
						block.statements :+ [loweredVariable]
					End If
				Next
				Continue
			End If
			Local lowered:TCompilerIrStatement = LowerStatement(bound.statements[index])
			If lowered Then
				MarkCoveragePoint(lowered, bound.statements[index].syntax)
				block.statements :+ [lowered]
			End If
		Next
		Return block
	End Method

	Method LowerStatement:TCompilerIrStatement(bound:TBoundStatement)
		If Not bound Then Return Null
		If bound.boundKind = BOUND_STATEMENT_ERROR And IsCompilationDirective(bound.syntax) Then Return Null
		Local variables:TBoundVariableDeclarationStatement = TBoundVariableDeclarationStatement(bound)
		If variables Then
			Local declarationSyntax:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(bound.syntax)
			Local isThreadedGlobal:Int = declarationSyntax And declarationSyntax.declarationToken And declarationSyntax.declarationToken.text.ToLower() = "threadedglobal"
			If variables.variables.length <> 1 Then
				AddUnsupported("BMXC1001", "Multiple declarators in one statement are not yet lowered", bound.syntax)
				Return Null
			End If
			Local variable:TBoundVariable = variables.variables[0]
			If Not variable Or Not variable.symbol Then
				AddUnsupported("BMXC1002", "Variable declaration has no semantic symbol", bound.syntax)
				Return Null
			End If
			' Open generic static storage, including ThreadedGlobal, is owned by
			' the canonical specialization unit and represented in the ordinary
			' application IR as an external specialization global.
			If GenericStaticMemberSymbol(variable.symbol) Then Return Null
			Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(variable.symbol.declaredType)
			Local callableType:TCallableSemanticType = TCallableSemanticType(variable.symbol.declaredType)
			If callableType And ((variable.symbol.kind <> SYMBOL_LOCAL And variable.symbol.kind <> SYMBOL_GLOBAL) Or Not IsSupportedCallableType(callableType)) Then
				AddUnsupported("BMXC1185", "Callable storage currently requires an ordinary-C-compatible Local or Global declaration", bound.syntax)
				Return Null
			End If
			If Not IsSupportedValueType(variable.symbol.declaredType) And Not IsSupportedStaticArrayType(staticArrayType) And Not callableType Then
				AddUnsupported("BMXC1003", "Variable type '" + TypeName(variable.symbol.declaredType) + "' is outside the scalar IR slice", bound.syntax)
				Return Null
			End If
			If staticArrayType And variable.initializer Then
				AddUnsupported("BMXC1019", "StaticArray declarations currently require default initialization", bound.syntax)
				Return Null
			End If
			If staticArrayType Then
				Local importedStaticArrayStruct:TCompilerIrImportedStruct = ImportedStructForType(staticArrayType.elementType)
				If importedStaticArrayStruct And Not ImportedStructHasDefaultHelper(importedStaticArrayStruct) Then
					AddUnsupported("BMXC1021", "Imported Struct StaticArray element type '" + TypeName(staticArrayType.elementType) + "' has no published zero-argument value helper", bound.syntax)
					Return Null
				End If
			End If
			Local resultVariable:TCompilerIrVariableDeclaration = New TCompilerIrVariableDeclaration
			resultVariable.kind = IR_STATEMENT_VARIABLE
			resultVariable.source = SourceOf(bound.syntax)
			Local symbolPrefix:String = "v"
			If variable.symbol.kind = SYMBOL_GLOBAL Or variable.symbol.kind = SYMBOL_CONST Then symbolPrefix = "g"
			resultVariable.symbolId = RegisterSymbol(variable.symbol, symbolPrefix)
			If variable.symbol.containingScope And variable.symbol.containingScope.owner Then
				Local variableOwner:TCompilerIrClass = TCompilerIrClass(classesBySymbol.ValueForKey(variable.symbol.containingScope.owner))
				If variableOwner Then resultVariable.ownerClassId = variableOwner.classId
				Local variableStructOwner:TCompilerIrStruct = TCompilerIrStruct(structsBySymbol.ValueForKey(variable.symbol.containingScope.owner))
				If variableStructOwner Then resultVariable.ownerStructId = variableStructOwner.structId
			End If
			resultVariable.name = variable.symbol.name
			resultVariable.semanticType = TypeName(variable.symbol.declaredType)
			If callableType Then
				resultVariable.callableReturnType = TypeName(callableType.returnType)
				resultVariable.callableParameters = CallableParameters(callableType)
				resultVariable.callableCallingConvention = callableType.callingConvention
				Local callableDeclarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(variable.symbol.declaration)
				If callableDeclarator And callableDeclarator.callableType Then ApplyCallableParameterNames(resultVariable.callableParameters, callableDeclarator.callableType)
			End If
			Local variableArrayType:TArraySemanticType = TArraySemanticType(variable.symbol.declaredType)
			Local variableArrayCallable:TCallableSemanticType
			If variableArrayType Then variableArrayCallable = TCallableSemanticType(variableArrayType.elementType)
			If variableArrayCallable Then
				resultVariable.arrayCallableReturnType = TypeName(variableArrayCallable.returnType)
				resultVariable.arrayCallableParameters = CallableParameters(variableArrayCallable)
				resultVariable.arrayCallableCallingConvention = variableArrayCallable.callingConvention
				resultVariable.arrayCallableRank = variableArrayType.rank
				Local callableDeclarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(variable.symbol.declaration)
				If callableDeclarator And callableDeclarator.callableType Then ApplyCallableParameterNames(resultVariable.arrayCallableParameters, callableDeclarator.callableType)
			End If
			resultVariable.storage = StorageName(variable.symbol)
			' A declared dynamic-array extent is an executable initializer even
			' though the bound model represents it separately from an `=` value.
			' Debug builds predeclare locals for stable debugger addresses, so this
			' must be assigned at its source position rather than evaluated at entry.
			resultVariable.hasExplicitInitializer = variable.initializer <> Null Or variable.arrayDimensions.length > 0
			resultVariable.visibility = variable.symbol.visibility
			resultVariable.isPublished = variable.symbol.kind = SYMBOL_GLOBAL And currentRoutine And currentRoutine.isGlobalEntry And analysis.model.moduleName.length > 0 And variable.symbol.visibility = VISIBILITY_PUBLIC
			If variable.symbol.kind = SYMBOL_GLOBAL And currentRoutine And currentRoutine.isGlobalEntry Then resultVariable.abiName = TCompilerAbiNamer.GlobalName(analysis.model, variable.symbol, resultVariable.symbolId)
			If variable.symbol.kind = SYMBOL_GLOBAL And genericPlan And genericPlan.specializationGlobalAbis.Contains(variable.symbol) Then
				resultVariable.abiName = String(genericPlan.specializationGlobalAbis.ValueForKey(variable.symbol))
				resultVariable.isSpecializationLinked = True
			End If
			resultVariable.isReadOnly = variable.symbol.isReadOnly Or variable.symbol.kind = SYMBOL_CONST
			resultVariable.isThreadedGlobal = isThreadedGlobal
			resultVariable.metadata = MetadataOf(variable.symbol)
			If staticArrayType Then
				resultVariable.isStaticArray = True
				resultVariable.staticArrayElementType = TypeName(staticArrayType.elementType)
				Local staticArrayStruct:TCompilerIrStruct = StructForType(staticArrayType.elementType)
				Local staticArrayImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(staticArrayType.elementType)
				If staticArrayStruct Then resultVariable.staticArrayStructId = staticArrayStruct.structId
				If staticArrayImportedStruct Then resultVariable.staticArrayImportedStructId = staticArrayImportedStruct.importedStructId
				resultVariable.staticArrayLength = staticArrayType.length
			Else If variable.symbol.kind = SYMBOL_CONST Then
				Local constantValue:TConstantValue = analysis.model.SymbolConstantValue(variable.symbol)
				If constantValue Then
					resultVariable.initializer = LowerConstantDefault(constantValue, variable.symbol.declaredType, variable.symbol, bound.syntax)
					If resultVariable.ownerClassId.length Or (options And options.debugInstrumentation) Then
						resultVariable.debugConstantStringLiteralId = RegisterStringValue(DebugConstantText(constantValue), resultVariable.source).literalId
					End If
				End If
			Else If variable.initializer Then
				resultVariable.initializer = LowerExpression(variable.initializer)
			Else If variable.arrayDimensions.length Then
				resultVariable.initializer = LowerDeclaredArrayAllocation(variable, bound.syntax)
			Else If callableType Then
				resultVariable.initializer = CallableDefault(callableType, resultVariable.source)
			Else If TClosureSemanticType(variable.symbol.declaredType) Then
				resultVariable.initializer = ManagedDefault(TypeName(variable.symbol.declaredType), IR_MANAGED_REFERENCE_CLOSURE, resultVariable.source)
			Else If StructForType(variable.symbol.declaredType) Or ImportedStructForType(variable.symbol.declaredType) Then
				resultVariable.initializer = StructDefault(variable.symbol.declaredType, resultVariable.source, bound.syntax)
			Else If IsStringType(variable.symbol.declaredType) Then
				resultVariable.initializer = ManagedDefault("String", IR_MANAGED_REFERENCE_STRING, resultVariable.source)
			Else If IsArrayType(variable.symbol.declaredType) Then
				resultVariable.initializer = ManagedDefault(TypeName(variable.symbol.declaredType), IR_MANAGED_REFERENCE_ARRAY, resultVariable.source)
			Else If IsObjectReferenceType(variable.symbol.declaredType) Then
				resultVariable.initializer = ManagedDefault(TypeName(variable.symbol.declaredType), IR_MANAGED_REFERENCE_OBJECT, resultVariable.source)
			Else If EnumForType(variable.symbol.declaredType) Then
				resultVariable.initializer = EnumDefault(variable.symbol.declaredType, resultVariable.source)
			Else
				resultVariable.initializer = ScalarDefault(TypeName(variable.symbol.declaredType), resultVariable.source)
			End If
			Local variableCapturePlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansBySymbol.ValueForKey(variable.symbol))
			If variable.symbol.kind = SYMBOL_LOCAL And variableCapturePlan Then
				Local capturedInitialization:TCompilerIrAssignment = New TCompilerIrAssignment
				capturedInitialization.kind = IR_STATEMENT_ASSIGNMENT
				capturedInitialization.source = resultVariable.source
				capturedInitialization.target = CaptureFieldAccess(variableCapturePlan, variable.symbol, variable.symbol.declaredType, resultVariable.source)
				capturedInitialization.value = resultVariable.initializer
				Return capturedInitialization
			End If
			Return resultVariable
		End If

		Local assignment:TBoundAssignmentStatement = TBoundAssignmentStatement(bound)
		If assignment Then
			Local assignmentTarget:TBoundExpression = assignment.target
			Local ascribedTarget:TBoundConversionExpression = TBoundConversionExpression(assignmentTarget)
			If ascribedTarget And ascribedTarget.conversionKind = CONVERSION_IDENTITY Then assignmentTarget = ascribedTarget.operand
			Local arrayTarget:TBoundIndexExpression = TBoundIndexExpression(assignmentTarget)
			If assignment.operatorText = "=" And assignment.indexAccess And assignment.indexAccess.accessKind = INDEX_ACCESS_OPERATOR And assignment.indexAccess.resolvedCall And arrayTarget Then
				Local setterCall:TBoundCallExpression = New TBoundCallExpression
				setterCall.boundKind = BOUND_EXPRESSION_CALL
				setterCall.syntax = arrayTarget.syntax
				setterCall.semanticType = assignment.indexAccess.resultType
				setterCall.isSynthetic = True
				setterCall.resolvedCall = assignment.indexAccess.resolvedCall
				setterCall.receiver = arrayTarget.receiver
				setterCall.arguments = arrayTarget.indexes + [assignment.value]
				Local setterStatement:TCompilerIrExpressionStatement = New TCompilerIrExpressionStatement
				setterStatement.kind = IR_STATEMENT_EXPRESSION
				setterStatement.source = SourceOf(bound.syntax)
				setterStatement.expression = LowerExpression(setterCall)
				Return setterStatement
			End If
			If assignment.resolvedCall And assignment.resolvedCall.routine Then
				Local operatorStatement:TCompilerIrExpressionStatement = New TCompilerIrExpressionStatement
				operatorStatement.kind = IR_STATEMENT_EXPRESSION
				operatorStatement.source = SourceOf(bound.syntax)
				operatorStatement.expression = LowerResolvedOperatorCall(assignment.resolvedCall, assignmentTarget, [assignment.value], assignment.target)
				Return operatorStatement
			End If
			Local supportedArrayTarget:Int = arrayTarget And arrayTarget.access And (arrayTarget.access.accessKind = INDEX_ACCESS_ARRAY Or arrayTarget.access.accessKind = INDEX_ACCESS_STATIC_ARRAY Or arrayTarget.access.accessKind = INDEX_ACCESS_POINTER)
			Local memberTarget:TBoundMemberExpression = TBoundMemberExpression(assignmentTarget)
			Local supportedFieldTarget:Int = memberTarget And memberTarget.access And memberTarget.access.member And (fieldsBySymbol.Contains(memberTarget.access.member) Or structFieldsBySymbol.Contains(memberTarget.access.member) Or IsImportedFieldSymbol(memberTarget.access.member) Or IsImportedStructFieldSymbol(memberTarget.access.member))
			Local supportedStaticGlobalTarget:Int = memberTarget And memberTarget.access And memberTarget.access.member And memberTarget.access.member.kind = SYMBOL_GLOBAL
			If Not supportedFieldTarget And memberTarget And memberTarget.receiver And memberTarget.access And memberTarget.access.member Then
				Local genericFieldOwner:TCompilerIrImportedClass = ImportedClassForType(memberTarget.receiver.semanticType)
				If Not genericFieldOwner Or Not genericFieldOwner.isGenericSpecialization Then genericFieldOwner = GenericImportedBaseForType(memberTarget.receiver.semanticType, memberTarget.access.member.containingScope.owner)
				supportedFieldTarget = GenericImportedField(genericFieldOwner, memberTarget.access.member) <> Null
				If Not supportedFieldTarget Then
					Local genericStructFieldOwner:TCompilerIrImportedStruct = ImportedStructForType(memberTarget.receiver.semanticType)
					supportedFieldTarget = GenericImportedStructField(genericStructFieldOwner, memberTarget.access.member) <> Null
				End If
			End If
			If Not TBoundSymbolExpression(assignmentTarget) And Not supportedArrayTarget And Not supportedFieldTarget And Not supportedStaticGlobalTarget Then
				AddUnsupported("BMXC1005", "Only symbol, field, heap-array and StaticArray element assignment is implemented", bound.syntax)
				Return Null
			End If
			Local stableManagedConcatTarget:Int = TBoundSymbolExpression(assignmentTarget) <> Null Or supportedStaticGlobalTarget
			If supportedFieldTarget And memberTarget Then stableManagedConcatTarget = Not memberTarget.receiver Or IsStableBoundReceiver(memberTarget.receiver)
			If supportedArrayTarget And arrayTarget And arrayTarget.access.accessKind = INDEX_ACCESS_ARRAY Then stableManagedConcatTarget = IsStableBoundIndexTarget(arrayTarget)
			Local stringConcatAssignment:Int = assignment.operatorText = ":+" And IsStringType(assignment.target.semanticType) And stableManagedConcatTarget
			Local arrayConcatAssignment:Int = assignment.operatorText = ":+" And IsArrayType(assignment.target.semanticType) And stableManagedConcatTarget
			Local pointerArithmeticAssignment:Int = IsPointerType(assignment.target.semanticType) And (assignment.operatorText = ":+" Or assignment.operatorText = ":-")
			Local enumCompoundAssignment:Int = EnumForType(assignment.target.semanticType) <> Null And SupportedCompoundAssignmentOperator(assignment.operatorText)
			If assignment.operatorText <> "=" And Not stringConcatAssignment And Not arrayConcatAssignment And Not pointerArithmeticAssignment And Not enumCompoundAssignment And (Not IsNumericType(assignment.target.semanticType) Or Not SupportedCompoundAssignmentOperator(assignment.operatorText)) Then
				AddUnsupported("BMXC1005", "Compound assignment requires a supported scalar or Enum target, or a stable String/heap-array target with :+", bound.syntax)
				Return Null
			End If
			Local resultAssignment:TCompilerIrAssignment = New TCompilerIrAssignment
			resultAssignment.kind = IR_STATEMENT_ASSIGNMENT
			resultAssignment.operatorText = assignment.operatorText
			resultAssignment.source = SourceOf(bound.syntax)
			Local previousPreserveStructLValue:Int = preserveStructLValue
			preserveStructLValue = True
			resultAssignment.target = LowerExpression(assignmentTarget)
			preserveStructLValue = previousPreserveStructLValue
			If assignment.operatorText = "=" Then
				resultAssignment.value = LowerContextualExpression(assignment.value, assignment.target.semanticType)
			Else If stringConcatAssignment Then
				' A String :+ assignment has the same operand coercion as ordinary
				' String +. Keep the conversion explicit in typed IR before the C
				' backend maps the concatenation to bbStringConcat.
				resultAssignment.value = LowerStringOperand(assignment.value)
			Else
				resultAssignment.value = LowerExpression(assignment.value)
			End If
			If stringConcatAssignment And resultAssignment.target And resultAssignment.value Then
				Local concat:TCompilerIrStringConcat = New TCompilerIrStringConcat
				concat.kind = IR_EXPRESSION_STRING_CONCAT
				concat.semanticType = TypeName(assignment.target.semanticType)
				concat.source = SourceOf(bound.syntax)
				concat.left = resultAssignment.target
				concat.right = resultAssignment.value
				resultAssignment.operatorText = "="
				resultAssignment.value = SequenceStringConcat(concat, bound.syntax)
			End If
			If arrayConcatAssignment And resultAssignment.target And resultAssignment.value Then
				Local arrayType:TArraySemanticType = TArraySemanticType(assignment.target.semanticType)
				Local arrayConcat:TCompilerIrArrayConcat = New TCompilerIrArrayConcat
				arrayConcat.kind = IR_EXPRESSION_ARRAY_CONCAT
				arrayConcat.semanticType = TypeName(assignment.target.semanticType)
				arrayConcat.source = SourceOf(bound.syntax)
				arrayConcat.elementType = TypeName(arrayType.elementType)
				arrayConcat.elementEncoding = ArrayElementEncoding(arrayType.elementType)
				Local concatEnum:TCompilerIrEnum = EnumForType(arrayType.elementType)
				If concatEnum Then arrayConcat.enumId = concatEnum.enumId
				Local concatStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
				Local concatImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
				If concatStruct Then arrayConcat.structId = concatStruct.structId
				If concatImportedStruct Then arrayConcat.importedStructId = concatImportedStruct.importedStructId
				arrayConcat.left = resultAssignment.target
				arrayConcat.right = resultAssignment.value
				resultAssignment.operatorText = "="
				resultAssignment.value = arrayConcat
			End If
			Return resultAssignment
		End If

		Local expressionStatement:TBoundExpressionStatement = TBoundExpressionStatement(bound)
		If expressionStatement Then
			Local resultExpression:TCompilerIrExpressionStatement = New TCompilerIrExpressionStatement
			resultExpression.kind = IR_STATEMENT_EXPRESSION
			resultExpression.source = SourceOf(bound.syntax)
			resultExpression.expression = LowerExpression(expressionStatement.expression)
			Return resultExpression
		End If

		Local returned:TBoundReturnStatement = TBoundReturnStatement(bound)
		If returned Then
			Local resultReturn:TCompilerIrReturn = New TCompilerIrReturn
			resultReturn.kind = IR_STATEMENT_RETURN
			resultReturn.source = SourceOf(bound.syntax)
			If returned.expression Then resultReturn.expression = LowerExpression(returned.expression)
			resultReturn.cleanupSteps = CopyActiveReturnCleanupSteps()
			Return resultReturn
		End If

		Local yielded:TBoundYieldStatement = TBoundYieldStatement(bound)
		If yielded Then
			Local resultYield:TCompilerIrYield = New TCompilerIrYield
			resultYield.kind = IR_STATEMENT_YIELD
			resultYield.source = SourceOf(bound.syntax)
			resultYield.expression = LowerExpression(yielded.expression)
			resultYield.exceptionFrameDepth = activeYieldExceptionFrameDepth
			resultYield.cleanupSteps = CopyActiveReturnCleanupSteps()
			Return resultYield
		End If

		Local thrown:TBoundThrowStatement = TBoundThrowStatement(bound)
		If thrown Then
			If Not thrown.expression Or Not IsManagedReferenceType(thrown.expression.semanticType) Then
				AddUnsupported("BMXC1215", "Throw requires a managed Object, String, or Array expression", bound.syntax)
				Return Null
			End If
			Local resultThrow:TCompilerIrThrow = New TCompilerIrThrow
			resultThrow.kind = IR_STATEMENT_THROW
			resultThrow.source = SourceOf(bound.syntax)
			resultThrow.expression = LowerExpression(thrown.expression)
			Return resultThrow
		End If

		Local asserted:TBoundAssertStatement = TBoundAssertStatement(bound)
		If asserted Then
			If Not IsAssertConditionType(asserted.condition.semanticType) Then
				AddUnsupported("BMXC1204", "Assert condition type '" + TypeName(asserted.condition.semanticType) + "' cannot be converted to BlitzMax truth", bound.syntax)
				Return Null
			End If
			If asserted.message And Not IsAssertMessageType(asserted.message.semanticType) Then
				AddUnsupported("BMXC1205", "Assert message type '" + TypeName(asserted.message.semanticType) + "' cannot be converted to String by the current IR", bound.syntax)
				Return Null
			End If
			' Production assertions are debug instrumentation: release builds
			' neither evaluate the condition nor the lazy failure message.
			If Not options Or Not options.debugInstrumentation Then Return Null
			Local resultAssert:TCompilerIrAssert = New TCompilerIrAssert
			resultAssert.kind = IR_STATEMENT_ASSERT
			resultAssert.source = SourceOf(bound.syntax)
			resultAssert.condition = LowerCondition(asserted.condition)
			If asserted.message Then
				resultAssert.message = LowerAssertMessage(asserted.message, bound.syntax)
			Else
				resultAssert.message = StringValueExpression("Assert failed", resultAssert.source)
			End If
			Return resultAssert
		End If

		Local released:TBoundReleaseStatement = TBoundReleaseStatement(bound)
		If released Then
			If Not released.expression Or Not TConversionClassifier.IsIntegral(released.expression.semanticType) Then
				AddUnsupported("BMXC1216", "Release requires an integer handle expression", bound.syntax)
				Return Null
			End If
			Local resultRelease:TCompilerIrRelease = New TCompilerIrRelease
			resultRelease.kind = IR_STATEMENT_RELEASE
			resultRelease.source = SourceOf(bound.syntax)
			resultRelease.expression = LowerExpression(released.expression)
			Return resultRelease
		End If

		Local selected:TBoundSelectStatement = TBoundSelectStatement(bound)
		If selected Then
			Local selectorEnum:TCompilerIrEnum = EnumForType(selected.expression.semanticType)
			Local selectorIsString:Int = IsStringType(selected.expression.semanticType)
			Local selectorUsesManagedIdentity:Int = IsObjectReferenceType(selected.expression.semanticType) Or TArraySemanticType(selected.expression.semanticType) <> Null
			If Not selectorIsString And Not selectorEnum And Not IsNumericType(selected.expression.semanticType) And Not IsPointerType(selected.expression.semanticType) And Not selectorUsesManagedIdentity Then
				AddUnsupported("BMXC1212", "Select selector type '" + TypeName(selected.expression.semanticType) + "' requires String, managed Object/Array identity, Enum, pointer, or scalar numeric comparison IR", bound.syntax)
				Return Null
			End If
			Local resultSelect:TCompilerIrSelect = New TCompilerIrSelect
			resultSelect.kind = IR_STATEMENT_SELECT
			resultSelect.source = SourceOf(bound.syntax)
			resultSelect.selector = LowerExpression(selected.expression)
			If Not resultSelect.selector Then Return Null
			resultSelect.selectorTemporaryId = NewTemporaryId()
			resultSelect.selectorType = TypeName(selected.expression.semanticType)
			resultSelect.stringComparison = selectorIsString
			resultSelect.managedIdentityComparison = selectorUsesManagedIdentity
			resultSelect.cases = New TCompilerIrSelectCase[selected.cases.length]
			For Local caseIndex:Int = 0 Until selected.cases.length
				Local selectedCase:TBoundSelectCase = selected.cases[caseIndex]
				Local resultCase:TCompilerIrSelectCase = New TCompilerIrSelectCase
				resultCase.source = SourceOf(selectedCase.syntax)
				resultCase.values = New TCompilerIrExpression[selectedCase.values.length]
				For Local valueIndex:Int = 0 Until selectedCase.values.length
					resultCase.values[valueIndex] = LowerExpression(selectedCase.values[valueIndex])
					If Not resultCase.values[valueIndex] Then Return Null
				Next
				resultCase.body = LowerBlock(selectedCase.body)
				resultSelect.cases[caseIndex] = resultCase
			Next
			If selected.defaultBody Then resultSelect.defaultBody = LowerBlock(selected.defaultBody)
			Return resultSelect
		End If

		Local guarded:TBoundTryStatement = TBoundTryStatement(bound)
		If guarded Then
			If Not guarded.catches.length And Not guarded.finallyBody Then
				AddUnsupported("BMXC1213", "Try requires Catch or Finally", bound.syntax)
				Return Null
			End If
			Local resultTry:TCompilerIrTry = New TCompilerIrTry
			resultTry.kind = IR_STATEMENT_TRY
			resultTry.source = SourceOf(bound.syntax)
			resultTry.tryId = "try" + nextUsingId
			nextUsingId :+ 1
			If guarded.finallyBody Then resultTry.finallyBody = LowerBlock(guarded.finallyBody)
			Local tryCleanupStep:TCompilerIrCleanupStep = New TCompilerIrCleanupStep
			tryCleanupStep.finallyBody = resultTry.finallyBody
			activeTryFinallyBlocks :+ [resultTry.finallyBody]
			activeReturnCleanupSteps :+ [tryCleanupStep]
			If guarded.finallyBody And guarded.catches.length Then
				' Combined routing is an outer Try/Finally containing an inner
				' Try/Catch. A transfer from the protected body leaves both
				' exception frames; a transfer from Catch leaves only Finally.
				Local catchFrameCleanup:TCompilerIrCleanupStep = New TCompilerIrCleanupStep
				activeReturnCleanupSteps :+ [catchFrameCleanup]
			End If
			activeTryBodyDepth :+ 1
			activeYieldExceptionFrameDepth :+ (guarded.catches.length > 0) + (guarded.finallyBody <> Null)
			resultTry.body = LowerBlock(guarded.body)
			activeYieldExceptionFrameDepth :- (guarded.catches.length > 0) + (guarded.finallyBody <> Null)
			activeTryBodyDepth :- 1
			If guarded.finallyBody And guarded.catches.length Then activeReturnCleanupSteps = activeReturnCleanupSteps[..activeReturnCleanupSteps.length - 1]
			If guarded.catches.length And Not guarded.finallyBody Then activeReturnCleanupSteps = activeReturnCleanupSteps[..activeReturnCleanupSteps.length - 1]
			activeTryFinallyBlocks = activeTryFinallyBlocks[..activeTryFinallyBlocks.length - 1]
			resultTry.catches = New TCompilerIrCatch[guarded.catches.length]
			For Local catchIndex:Int = 0 Until guarded.catches.length
				Local guardedCatch:TBoundCatchClause = guarded.catches[catchIndex]
				Local resultCatch:TCompilerIrCatch = New TCompilerIrCatch
				resultCatch.source = SourceOf(guardedCatch.syntax)
				resultCatch.parameterSymbolId = RegisterSymbol(guardedCatch.parameter, "catch")
				resultCatch.parameterName = guardedCatch.parameter.name
				resultCatch.parameterType = TypeName(guardedCatch.parameter.declaredType)
				If IsStringType(guardedCatch.parameter.declaredType) Then
					resultCatch.catchKind = IR_CATCH_STRING
				Else If IsArrayType(guardedCatch.parameter.declaredType) Then
					resultCatch.catchKind = IR_CATCH_ARRAY
				Else If IsBuiltinObjectType(guardedCatch.parameter.declaredType) Then
					resultCatch.catchKind = IR_CATCH_OBJECT
				Else
					Local catchInterface:TCompilerIrInterface = InterfaceForType(guardedCatch.parameter.declaredType)
					Local catchClass:TCompilerIrClass = ClassForType(guardedCatch.parameter.declaredType)
					Local catchImportedClass:TCompilerIrImportedClass = ImportedClassForType(guardedCatch.parameter.declaredType)
					If catchInterface Then
						resultCatch.catchKind = IR_CATCH_INTERFACE
						resultCatch.interfaceId = catchInterface.interfaceId
					Else If catchClass Then
						resultCatch.catchKind = IR_CATCH_CLASS
						resultCatch.classId = catchClass.classId
					Else If catchImportedClass Then
						resultCatch.catchKind = IR_CATCH_CLASS
						resultCatch.importedClassId = catchImportedClass.importedClassId
					Else
						AddUnsupported("BMXC1213", "Catch type '" + resultCatch.parameterType + "' has no runtime downcast identity", guardedCatch.syntax)
						Return Null
					End If
				End If
				If guarded.finallyBody Then activeYieldExceptionFrameDepth :+ 1
				resultCatch.body = LowerBlock(guardedCatch.body)
				If guarded.finallyBody Then activeYieldExceptionFrameDepth :- 1
				Local catchCapturePlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(guardedCatch.parameter.containingScope))
				If catchCapturePlan Then
					Local catchValue:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
					catchValue.kind = IR_EXPRESSION_SYMBOL
					catchValue.semanticType = TypeName(guardedCatch.parameter.declaredType)
					catchValue.source = resultCatch.source
					catchValue.symbolId = resultCatch.parameterSymbolId
					catchValue.name = resultCatch.parameterName
					PrependCatchCaptureEnvironment(resultCatch.body, catchCapturePlan, guardedCatch.parameter, catchValue)
				End If
				resultTry.catches[catchIndex] = resultCatch
			Next
			If guarded.finallyBody Then activeReturnCleanupSteps = activeReturnCleanupSteps[..activeReturnCleanupSteps.length - 1]
			Return resultTry
		End If

		Local usingStatement:TBoundUsingStatement = TBoundUsingStatement(bound)
		If usingStatement Then
			Local resultUsing:TCompilerIrUsing = New TCompilerIrUsing
			resultUsing.kind = IR_STATEMENT_USING
			resultUsing.source = SourceOf(bound.syntax)
			resultUsing.usingId = "using" + nextUsingId
			nextUsingId :+ 1
			resultUsing.resources = New TCompilerIrUsingResource[usingStatement.resources.length]
			For Local resourceIndex:Int = 0 Until usingStatement.resources.length
				Local boundResource:TBoundVariableDeclarationStatement = usingStatement.resources[resourceIndex]
				Local resourceVariable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(LowerStatement(boundResource))
				If Not resourceVariable Or boundResource.variables.length <> 1 Then
					AddUnsupported("BMXC1214", "Using requires one lowered managed resource per declaration", boundResource.syntax)
					Return Null
				End If
				Local resource:TCompilerIrUsingResource = New TCompilerIrUsingResource
				resource.variable = resourceVariable
				resource.initializer = resourceVariable.initializer
				resourceVariable.initializer = ManagedDefault(resourceVariable.semanticType, IR_MANAGED_REFERENCE_OBJECT, resourceVariable.source)
				resourceVariable.hasExplicitInitializer = False
				' A resource is assigned after setjmp and read on the longjmp
				' cleanup path. C requires it to be volatile for that value to
				' remain defined.
				resourceVariable.isVolatile = True
				Local resourceSymbol:TSymbol = boundResource.variables[0].symbol
				resource.closeCall = BuildUsingCloseCall(resourceSymbol, resourceVariable, bound.syntax)
				If Not resource.closeCall Then Return Null
				Local resourceReference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
				resourceReference.kind = IR_EXPRESSION_SYMBOL
				resourceReference.semanticType = resourceVariable.semanticType
				resourceReference.source = resourceVariable.source
				resourceReference.symbolId = resourceVariable.symbolId
				resourceReference.name = resourceVariable.name
				resource.truth = New TCompilerIrManagedTruth
				TCompilerIrManagedTruth(resource.truth).kind = IR_EXPRESSION_MANAGED_TRUTH
				TCompilerIrManagedTruth(resource.truth).semanticType = "Int"
				TCompilerIrManagedTruth(resource.truth).source = resourceVariable.source
				TCompilerIrManagedTruth(resource.truth).operand = resourceReference
				TCompilerIrManagedTruth(resource.truth).managedKind = IR_MANAGED_REFERENCE_OBJECT
				resultUsing.resources[resourceIndex] = resource
			Next
			Local usingCleanupStep:TCompilerIrCleanupStep = New TCompilerIrCleanupStep
			usingCleanupStep.usingResources = resultUsing.resources
			activeReturnCleanupSteps :+ [usingCleanupStep]
			activeUsingBodyDepth :+ 1
			resultUsing.body = LowerBlock(usingStatement.body)
			activeUsingBodyDepth :- 1
			activeReturnCleanupSteps = activeReturnCleanupSteps[..activeReturnCleanupSteps.length - 1]
			Return resultUsing
		End If

		Local dataStatement:TBoundDataStatement = TBoundDataStatement(bound)
		If dataStatement Then
			If TDefDataStatementSyntax(bound.syntax) Then Return Null
			Local readSyntax:TReadDataStatementSyntax = TReadDataStatementSyntax(bound.syntax)
			If readSyntax Then
				Local operation:TDataReadOperation = analysis.model.DataReadOperation(readSyntax)
				If Not operation Then
					AddUnsupported("BMXC1222", "ReadData has no analyzed data operation", bound.syntax)
					Return Null
				End If
				Local resultRead:TCompilerIrDataRead = New TCompilerIrDataRead
				resultRead.kind = IR_STATEMENT_DATA_READ
				resultRead.source = SourceOf(bound.syntax)
				resultRead.targets = New TCompilerIrDataReadTarget[operation.targets.length]
				For Local index:Int = 0 Until operation.targets.length
					Local target:TDataReadTarget = operation.targets[index]
					Local irTarget:TCompilerIrDataReadTarget = New TCompilerIrDataReadTarget
					irTarget.source = SourceOf(target.syntax)
					irTarget.conversionKind = target.conversionKind
					irTarget.target = LowerExpression(target.expression)
					If Not irTarget.target Or Not IsAddressableExpression(irTarget.target) Then
						AddUnsupported("BMXC1222", "ReadData target is not addressable in typed IR", target.syntax)
						Return Null
					End If
					resultRead.targets[index] = irTarget
				Next
				Return resultRead
			End If
		End If

		Local conditionalIf:TBoundIfStatement = TBoundIfStatement(bound)
		If conditionalIf Then
			Local resultIf:TCompilerIrIf = New TCompilerIrIf
			resultIf.kind = IR_STATEMENT_IF
			resultIf.source = SourceOf(bound.syntax)
			resultIf.condition = LowerCondition(conditionalIf.condition)
			resultIf.thenBody = LowerBlock(conditionalIf.thenBody)
			resultIf.elseIfClauses = New TCompilerIrConditionalClause[conditionalIf.elseIfClauses.length]
			For Local index:Int = 0 Until conditionalIf.elseIfClauses.length
				Local boundClause:TBoundConditionalClause = conditionalIf.elseIfClauses[index]
				Local clause:TCompilerIrConditionalClause = New TCompilerIrConditionalClause
				If boundClause Then
					clause.source = SourceOf(boundClause.syntax)
					clause.condition = LowerCondition(boundClause.condition)
					clause.body = LowerBlock(boundClause.body)
				End If
				resultIf.elseIfClauses[index] = clause
			Next
			If conditionalIf.elseBody Then resultIf.elseBody = LowerBlock(conditionalIf.elseBody)
			Return resultIf
		End If

		Local whileStatement:TBoundWhileStatement = TBoundWhileStatement(bound)
		If whileStatement Then
			Local resultWhile:TCompilerIrWhile = New TCompilerIrWhile
			resultWhile.kind = IR_STATEMENT_WHILE
			resultWhile.source = SourceOf(bound.syntax)
			resultWhile.loopId = NewLoopId()
			resultWhile.sourceLabel = LoopLabel(bound.syntax)
			resultWhile.condition = LowerCondition(whileStatement.condition)
			Local previousLoop:TCompilerLoopLoweringContext = currentLoop
			currentLoop = BeginLoopContext(previousLoop, resultWhile.loopId, resultWhile.sourceLabel, resultWhile)
			resultWhile.body = LowerBlock(whileStatement.body)
			currentLoop = previousLoop
			PrependIterationCaptureEnvironment(resultWhile.body, TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(analysis.model.ScopeFor(bound.syntax))))
			Return resultWhile
		End If

		Local repeatStatement:TBoundRepeatStatement = TBoundRepeatStatement(bound)
		If repeatStatement Then
			Local resultRepeat:TCompilerIrRepeat = New TCompilerIrRepeat
			resultRepeat.kind = IR_STATEMENT_REPEAT
			resultRepeat.source = SourceOf(bound.syntax)
			resultRepeat.loopId = NewLoopId()
			resultRepeat.sourceLabel = LoopLabel(bound.syntax)
			resultRepeat.isForever = repeatStatement.isForever
			Local previousLoop:TCompilerLoopLoweringContext = currentLoop
			currentLoop = BeginLoopContext(previousLoop, resultRepeat.loopId, resultRepeat.sourceLabel, resultRepeat)
			resultRepeat.body = LowerBlock(repeatStatement.body)
			currentLoop = previousLoop
			PrependIterationCaptureEnvironment(resultRepeat.body, TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(analysis.model.ScopeFor(bound.syntax))))
			If Not resultRepeat.isForever Then resultRepeat.condition = LowerCondition(repeatStatement.condition)
			Return resultRepeat
		End If

		Local forStatement:TBoundForStatement = TBoundForStatement(bound)
		If forStatement Then
			If forStatement.isEachIn Then
				If forStatement.iteration And (forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERABLE Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERATOR) Then
					Local objectVariableType:TSemanticType
					If forStatement.loopVariable Then objectVariableType = forStatement.loopVariable.declaredType Else If forStatement.target Then objectVariableType = forStatement.target.semanticType
					Local legacyObjectElements:Int = forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR And IsBuiltinObjectType(forStatement.iteration.elementType)
					If Not IsSupportedValueType(forStatement.iteration.elementType) Or Not objectVariableType Or (legacyObjectElements And Not IsObjectReferenceType(objectVariableType) And Not IsStringType(objectVariableType) And Not IsNumericType(objectVariableType)) Or (Not legacyObjectElements And TypeName(objectVariableType).ToLower() <> TypeName(forStatement.iteration.elementType).ToLower()) Then
						AddUnsupported("BMXC1020", "Object iterator EachIn requires a matching supported loop variable, or an object-reference target for a legacy Object result", bound.syntax)
						Return Null
					End If
					If Not IsLoweredEachInReceiver(forStatement.collection.semanticType) Or Not IsLoweredEachInReceiver(forStatement.iteration.iteratorType) Then
						AddUnsupported("BMXC1020", "Object iterator EachIn currently requires source or imported Type, or non-generic Interface receivers", bound.syntax)
						Return Null
					End If
					Local resultObjectEach:TCompilerIrForEachObject = New TCompilerIrForEachObject
					resultObjectEach.kind = IR_STATEMENT_FOR_EACH_OBJECT
					resultObjectEach.source = SourceOf(bound.syntax)
					resultObjectEach.loopId = NewLoopId()
					resultObjectEach.sourceLabel = LoopLabel(bound.syntax)
					resultObjectEach.protocolKind = forStatement.iteration.protocolKind
					resultObjectEach.variableType = TypeName(objectVariableType)
					resultObjectEach.collectionType = TypeName(forStatement.collection.semanticType)
					resultObjectEach.iteratorType = TypeName(forStatement.iteration.iteratorType)
					resultObjectEach.elementType = TypeName(forStatement.iteration.elementType)
					If forStatement.loopVariable Then
						resultObjectEach.declaresVariable = True
						resultObjectEach.variableSymbolId = RegisterSymbol(forStatement.loopVariable, "v")
						resultObjectEach.variableName = forStatement.loopVariable.name
						Local objectTarget:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
						objectTarget.kind = IR_EXPRESSION_SYMBOL
						objectTarget.source = SourceOf(bound.syntax)
						objectTarget.semanticType = resultObjectEach.variableType
						objectTarget.symbolId = resultObjectEach.variableSymbolId
						objectTarget.name = resultObjectEach.variableName
						resultObjectEach.target = objectTarget
					Else
						resultObjectEach.target = LowerAddressableExpression(forStatement.target)
						If Not resultObjectEach.target Or Not IsAddressableExpression(resultObjectEach.target) Then
							AddUnsupported("BMXC1020", "Object iterator EachIn requires an addressable Local, Var parameter, Field, Global, or array element target", bound.syntax)
							Return Null
						End If
					End If
					resultObjectEach.collection = LowerExpression(forStatement.collection)
					resultObjectEach.collectionTemporaryId = NewTemporaryId()
					resultObjectEach.iteratorTemporaryId = NewTemporaryId()
					resultObjectEach.elementTemporaryId = NewTemporaryId()
					Local collectionReference:TCompilerIrSymbolReference = TemporaryIrReference(resultObjectEach.collectionTemporaryId, resultObjectEach.collectionType, "collection", bound.syntax)
					Local iteratorReference:TCompilerIrSymbolReference = TemporaryIrReference(resultObjectEach.iteratorTemporaryId, resultObjectEach.iteratorType, "iterator", bound.syntax)
					If forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERATOR Then
						resultObjectEach.iteratorInitializer = collectionReference
					Else
						resultObjectEach.iteratorInitializer = LowerEachInMethodCall(forStatement.iteration.iteratorFactory, collectionReference, forStatement.collection.semanticType, bound.syntax)
					End If
					resultObjectEach.advance = LowerEachInMethodCall(forStatement.iteration.advance, iteratorReference, forStatement.iteration.iteratorType, bound.syntax)
					resultObjectEach.current = LowerEachInMethodCall(forStatement.iteration.current, iteratorReference, forStatement.iteration.iteratorType, bound.syntax)
					If Not resultObjectEach.iteratorInitializer Or Not resultObjectEach.advance Or Not resultObjectEach.current Then Return Null
					resultObjectEach.iteratorCleanup = BuildIteratorCleanup(iteratorReference, bound.syntax)
					Local elementReference:TCompilerIrSymbolReference = TemporaryIrReference(resultObjectEach.elementTemporaryId, resultObjectEach.elementType, "element", bound.syntax)
					resultObjectEach.elementValue = elementReference
					If legacyObjectElements Then
						If IsStringType(objectVariableType) Then
							resultObjectEach.filtersStringObjects = True
							Local stringCast:TCompilerIrObjectStringCast = New TCompilerIrObjectStringCast
							stringCast.kind = IR_EXPRESSION_OBJECT_STRING_CAST
							stringCast.source = SourceOf(bound.syntax)
							stringCast.semanticType = resultObjectEach.variableType
							stringCast.operand = elementReference
							resultObjectEach.elementValue = stringCast
						Else If Not IsNumericType(objectVariableType) Then
							resultObjectEach.filtersNullObjects = True
						End If
						If IsNumericType(objectVariableType) Then
							Local objectStorage:TCompilerIrConversion = New TCompilerIrConversion
							objectStorage.kind = IR_EXPRESSION_CONVERSION
							objectStorage.source = SourceOf(bound.syntax)
							objectStorage.semanticType = "Byte Ptr"
							objectStorage.conversionKind = CONVERSION_OBJECT_TO_BYTE_POINTER
							objectStorage.operand = elementReference
							Local numericElement:TCompilerIrPointerElement = New TCompilerIrPointerElement
							numericElement.kind = IR_EXPRESSION_POINTER_ELEMENT
							numericElement.source = SourceOf(bound.syntax)
							numericElement.semanticType = resultObjectEach.variableType
							numericElement.elementType = resultObjectEach.variableType
							numericElement.receiver = objectStorage
							numericElement.index = ScalarDefault("Int", SourceOf(bound.syntax))
							resultObjectEach.elementValue = numericElement
						Else If Not IsBuiltinObjectType(objectVariableType) And Not IsStringType(objectVariableType) Then
							Local targetInterface:TCompilerIrInterface = InterfaceForType(objectVariableType)
							If targetInterface Then
								Local interfaceCast:TCompilerIrInterfaceCast = New TCompilerIrInterfaceCast
								interfaceCast.kind = IR_EXPRESSION_INTERFACE_CAST
								interfaceCast.source = SourceOf(bound.syntax)
								interfaceCast.semanticType = resultObjectEach.variableType
								interfaceCast.interfaceId = targetInterface.interfaceId
								interfaceCast.operand = elementReference
								resultObjectEach.elementValue = interfaceCast
							Else
								Local sourceClass:TCompilerIrClass = ClassForType(objectVariableType)
								Local importedClass:TCompilerIrImportedClass = ImportedClassForType(objectVariableType)
								If Not sourceClass And Not importedClass Then
									AddUnsupported("BMXC1020", "Legacy ObjectEnumerator target has no runtime cast identity", bound.syntax)
									Return Null
								End If
								Local objectCast:TCompilerIrObjectCast = New TCompilerIrObjectCast
								objectCast.kind = IR_EXPRESSION_OBJECT_CAST
								objectCast.source = SourceOf(bound.syntax)
								objectCast.semanticType = resultObjectEach.variableType
								If sourceClass Then objectCast.classId = sourceClass.classId Else objectCast.importedClassId = importedClass.importedClassId
								objectCast.operand = elementReference
								resultObjectEach.elementValue = objectCast
							End If
						End If
					End If
					Local previousObjectLoop:TCompilerLoopLoweringContext = currentLoop
					currentLoop = BeginLoopContext(previousObjectLoop, resultObjectEach.loopId, resultObjectEach.sourceLabel, resultObjectEach)
					If resultObjectEach.iteratorCleanup Then
						Local iteratorCleanupStep:TCompilerIrCleanupStep = New TCompilerIrCleanupStep
						iteratorCleanupStep.usingResources = [resultObjectEach.iteratorCleanup]
						activeReturnCleanupSteps :+ [iteratorCleanupStep]
						currentLoop.continueCleanupDepth = activeReturnCleanupSteps.length
					End If
					resultObjectEach.body = LowerBlock(forStatement.body)
					If resultObjectEach.iteratorCleanup Then activeReturnCleanupSteps = activeReturnCleanupSteps[..activeReturnCleanupSteps.length - 1]
					currentLoop = previousObjectLoop
					Local objectIterationPlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(analysis.model.ScopeFor(bound.syntax)))
					Local objectHeaderValue:TCompilerIrExpression
					If forStatement.loopVariable Then objectHeaderValue = DirectSymbolReference(forStatement.loopVariable, resultObjectEach.source)
					PrependIterationCaptureEnvironment(resultObjectEach.body, objectIterationPlan, forStatement.loopVariable, objectHeaderValue)
					Return resultObjectEach
				End If
				Local staticCollectionType:TStaticArraySemanticType
				If forStatement.collection Then staticCollectionType = StaticArrayTypeOf(forStatement.collection)
				If staticCollectionType Then
					If Not IsSupportedStaticArrayType(staticCollectionType) Then
						AddUnsupported("BMXC1019", "StaticArray EachIn element type is not implemented", bound.syntax)
						Return Null
					End If
					Local staticVariableType:TSemanticType
					If forStatement.loopVariable Then staticVariableType = forStatement.loopVariable.declaredType Else If forStatement.target Then staticVariableType = forStatement.target.semanticType
					If Not IsSupportedStaticArrayEachInConversion(staticCollectionType.elementType, staticVariableType) Then
						AddUnsupported("BMXC1019", "StaticArray EachIn loop variable type is not implemented for this element type", bound.syntax)
						Return Null
					End If
					Local resultStaticEach:TCompilerIrForEachStaticArray = New TCompilerIrForEachStaticArray
					resultStaticEach.kind = IR_STATEMENT_FOR_EACH_STATIC_ARRAY
					resultStaticEach.source = SourceOf(bound.syntax)
					resultStaticEach.loopId = NewLoopId()
					resultStaticEach.sourceLabel = LoopLabel(bound.syntax)
					resultStaticEach.variableType = TypeName(staticVariableType)
					resultStaticEach.elementType = TypeName(staticCollectionType.elementType)
					Local staticEachStruct:TCompilerIrStruct = StructForType(staticCollectionType.elementType)
					Local staticEachImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(staticCollectionType.elementType)
					If staticEachStruct Then resultStaticEach.elementStructId = staticEachStruct.structId
					If staticEachImportedStruct Then resultStaticEach.elementImportedStructId = staticEachImportedStruct.importedStructId
					resultStaticEach.length = staticCollectionType.length
					If forStatement.loopVariable Then
						resultStaticEach.declaresVariable = True
						resultStaticEach.variableSymbolId = RegisterSymbol(forStatement.loopVariable, "v")
						resultStaticEach.variableName = forStatement.loopVariable.name
						Local staticTarget:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
						staticTarget.kind = IR_EXPRESSION_SYMBOL
						staticTarget.source = SourceOf(bound.syntax)
						staticTarget.semanticType = resultStaticEach.variableType
						staticTarget.symbolId = resultStaticEach.variableSymbolId
						staticTarget.name = resultStaticEach.variableName
						resultStaticEach.target = staticTarget
					Else
						resultStaticEach.target = LowerAddressableExpression(forStatement.target)
						If Not resultStaticEach.target Or Not IsAddressableExpression(resultStaticEach.target) Then
							AddUnsupported("BMXC1019", "StaticArray EachIn requires an addressable Local, Var parameter, Field, Global, or array element target", bound.syntax)
							Return Null
						End If
					End If
					resultStaticEach.collection = LowerExpression(forStatement.collection)
					resultStaticEach.collectionTemporaryId = NewTemporaryId()
					resultStaticEach.indexTemporaryId = NewTemporaryId()
					resultStaticEach.elementTemporaryId = NewTemporaryId()
					Local previousStaticLoop:TCompilerLoopLoweringContext = currentLoop
					currentLoop = BeginLoopContext(previousStaticLoop, resultStaticEach.loopId, resultStaticEach.sourceLabel, resultStaticEach)
					resultStaticEach.body = LowerBlock(forStatement.body)
					currentLoop = previousStaticLoop
					Local staticIterationPlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(analysis.model.ScopeFor(bound.syntax)))
					Local staticHeaderValue:TCompilerIrExpression
					If forStatement.loopVariable Then staticHeaderValue = DirectSymbolReference(forStatement.loopVariable, resultStaticEach.source)
					PrependIterationCaptureEnvironment(resultStaticEach.body, staticIterationPlan, forStatement.loopVariable, staticHeaderValue)
					Return resultStaticEach
				End If
				If forStatement.collection And IsStringType(forStatement.collection.semanticType) Then
					Local stringVariableType:TSemanticType
					If forStatement.loopVariable Then stringVariableType = forStatement.loopVariable.declaredType Else If forStatement.target Then stringVariableType = forStatement.target.semanticType
					If Not IsNumericType(stringVariableType) Then
						AddUnsupported("BMXC1018", "String EachIn requires a numeric loop variable for UTF-16 code units", bound.syntax)
						Return Null
					End If
					Local resultStringEach:TCompilerIrForEachString = New TCompilerIrForEachString
					resultStringEach.kind = IR_STATEMENT_FOR_EACH_STRING
					resultStringEach.source = SourceOf(bound.syntax)
					resultStringEach.loopId = NewLoopId()
					resultStringEach.sourceLabel = LoopLabel(bound.syntax)
					resultStringEach.variableType = TypeName(stringVariableType)
					If forStatement.loopVariable Then
						resultStringEach.declaresVariable = True
						resultStringEach.variableSymbolId = RegisterSymbol(forStatement.loopVariable, "v")
						resultStringEach.variableName = forStatement.loopVariable.name
						Local stringTarget:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
						stringTarget.kind = IR_EXPRESSION_SYMBOL
						stringTarget.source = SourceOf(bound.syntax)
						stringTarget.semanticType = resultStringEach.variableType
						stringTarget.symbolId = resultStringEach.variableSymbolId
						stringTarget.name = resultStringEach.variableName
						resultStringEach.target = stringTarget
					Else
						resultStringEach.target = LowerAddressableExpression(forStatement.target)
						If Not resultStringEach.target Or Not IsAddressableExpression(resultStringEach.target) Then
							AddUnsupported("BMXC1018", "String EachIn requires an addressable Local, Var parameter, Field, Global, or array element target", bound.syntax)
							Return Null
						End If
					End If
					resultStringEach.collection = LowerExpression(forStatement.collection)
					resultStringEach.collectionTemporaryId = NewTemporaryId()
					resultStringEach.indexTemporaryId = NewTemporaryId()
					resultStringEach.elementTemporaryId = NewTemporaryId()
					Local previousStringLoop:TCompilerLoopLoweringContext = currentLoop
					currentLoop = BeginLoopContext(previousStringLoop, resultStringEach.loopId, resultStringEach.sourceLabel, resultStringEach)
					resultStringEach.body = LowerBlock(forStatement.body)
					currentLoop = previousStringLoop
					Local stringIterationPlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(analysis.model.ScopeFor(bound.syntax)))
					Local stringHeaderValue:TCompilerIrExpression
					If forStatement.loopVariable Then stringHeaderValue = DirectSymbolReference(forStatement.loopVariable, resultStringEach.source)
					PrependIterationCaptureEnvironment(resultStringEach.body, stringIterationPlan, forStatement.loopVariable, stringHeaderValue)
					Return resultStringEach
				End If
				Local collectionType:TArraySemanticType
				If forStatement.collection Then collectionType = TArraySemanticType(forStatement.collection.semanticType)
				If Not collectionType Or collectionType.rank <= 0 Or Not IsSupportedArrayElementType(collectionType.elementType) Then
					AddUnsupported("BMXC1008", "EachIn requires a supported managed Array", bound.syntax)
					Return Null
				End If
				Local variableType:TSemanticType
				If forStatement.loopVariable Then variableType = forStatement.loopVariable.declaredType Else If forStatement.target Then variableType = forStatement.target.semanticType
				Local objectElements:Int = IsObjectReferenceType(collectionType.elementType)
				Local legacyObjectAdaptation:Int = objectElements And (IsObjectReferenceType(variableType) Or IsStringType(variableType) Or IsNumericType(variableType))
				Local elementAssignment:TConversion
				If variableType And Not objectElements Then elementAssignment = TConversionClassifier.Create(analysis.model).ClassifyAssignmentExpression(Null, collectionType.elementType, variableType)
				If Not variableType Or (objectElements And Not legacyObjectAdaptation) Or (Not objectElements And (Not elementAssignment Or Not elementAssignment.Exists())) Then
					AddUnsupported("BMXC1017", "Array EachIn element type '" + TypeName(collectionType.elementType) + "' cannot be assigned to loop variable type '" + TypeName(variableType) + "'", bound.syntax)
					Return Null
				End If
				Local resultEach:TCompilerIrForEachArray = New TCompilerIrForEachArray
				resultEach.kind = IR_STATEMENT_FOR_EACH_ARRAY
				resultEach.source = SourceOf(bound.syntax)
				resultEach.loopId = NewLoopId()
				resultEach.sourceLabel = LoopLabel(bound.syntax)
				resultEach.variableType = TypeName(variableType)
				resultEach.elementType = TypeName(collectionType.elementType)
				If forStatement.loopVariable Then
					resultEach.declaresVariable = True
					resultEach.variableSymbolId = RegisterSymbol(forStatement.loopVariable, "v")
					resultEach.variableName = forStatement.loopVariable.name
					Local target:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
					target.kind = IR_EXPRESSION_SYMBOL
					target.source = SourceOf(bound.syntax)
					target.semanticType = resultEach.variableType
					target.symbolId = resultEach.variableSymbolId
					target.name = resultEach.variableName
					resultEach.target = target
				Else
					resultEach.target = LowerAddressableExpression(forStatement.target)
					If Not resultEach.target Or Not IsAddressableExpression(resultEach.target) Then
						AddUnsupported("BMXC1017", "Array EachIn requires an addressable Local, Var parameter, Field, Global, or array element target", bound.syntax)
						Return Null
					End If
				End If
				resultEach.collection = LowerExpression(forStatement.collection)
				resultEach.collectionTemporaryId = NewTemporaryId()
				resultEach.indexTemporaryId = NewTemporaryId()
				resultEach.elementTemporaryId = NewTemporaryId()
				Local elementReference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
				elementReference.kind = IR_EXPRESSION_SYMBOL
				elementReference.source = SourceOf(bound.syntax)
				elementReference.semanticType = resultEach.elementType
				elementReference.symbolId = resultEach.elementTemporaryId
				elementReference.name = "element"
				resultEach.elementValue = elementReference
				If objectElements Then
					resultEach.filtersNullObjects = Not IsNumericType(variableType) And Not IsStringType(variableType)
					If IsStringType(variableType) Then
						resultEach.filtersStringObjects = True
						Local stringCast:TCompilerIrObjectStringCast = New TCompilerIrObjectStringCast
						stringCast.kind = IR_EXPRESSION_OBJECT_STRING_CAST
						stringCast.source = SourceOf(bound.syntax)
						stringCast.semanticType = resultEach.variableType
						stringCast.operand = elementReference
						resultEach.elementValue = stringCast
					Else If IsNumericType(variableType) Then
						Local objectStorage:TCompilerIrConversion = New TCompilerIrConversion
						objectStorage.kind = IR_EXPRESSION_CONVERSION
						objectStorage.source = SourceOf(bound.syntax)
						objectStorage.semanticType = "Byte Ptr"
						objectStorage.conversionKind = CONVERSION_OBJECT_TO_BYTE_POINTER
						objectStorage.operand = elementReference
						Local numericElement:TCompilerIrPointerElement = New TCompilerIrPointerElement
						numericElement.kind = IR_EXPRESSION_POINTER_ELEMENT
						numericElement.source = SourceOf(bound.syntax)
						numericElement.semanticType = resultEach.variableType
						numericElement.elementType = resultEach.variableType
						numericElement.receiver = objectStorage
						numericElement.index = ScalarDefault("Int", SourceOf(bound.syntax))
						resultEach.elementValue = numericElement
					Else If IsBuiltinObjectType(variableType) And Not TGenericRoutineInference.SameType(collectionType.elementType, variableType) Then
						' A typed managed array retains concrete pointer storage in C. Iterating
						' it through Object is a semantic reference conversion, not a C pointer
						' identity, so keep the upcast explicit in typed IR.
						Local objectUpcast:TCompilerIrConversion = New TCompilerIrConversion
						objectUpcast.kind = IR_EXPRESSION_CONVERSION
						objectUpcast.source = SourceOf(bound.syntax)
						objectUpcast.semanticType = resultEach.variableType
						objectUpcast.conversionKind = CONVERSION_REFERENCE
						objectUpcast.implicitConversion = True
						objectUpcast.operand = elementReference
						resultEach.elementValue = objectUpcast
					Else If Not IsBuiltinObjectType(variableType) Then
						Local targetInterface:TCompilerIrInterface = InterfaceForType(variableType)
						If targetInterface Then
							Local interfaceCast:TCompilerIrInterfaceCast = New TCompilerIrInterfaceCast
							interfaceCast.kind = IR_EXPRESSION_INTERFACE_CAST
							interfaceCast.source = SourceOf(bound.syntax)
							interfaceCast.semanticType = resultEach.variableType
							interfaceCast.interfaceId = targetInterface.interfaceId
							interfaceCast.operand = elementReference
							resultEach.elementValue = interfaceCast
						Else
							Local sourceClass:TCompilerIrClass = ClassForType(variableType)
							Local importedClass:TCompilerIrImportedClass = ImportedClassForType(variableType)
							If Not sourceClass And Not importedClass Then
								AddUnsupported("BMXC1016", "Object Array EachIn target has no runtime cast identity", bound.syntax)
								Return Null
							End If
							Local objectCast:TCompilerIrObjectCast = New TCompilerIrObjectCast
							objectCast.kind = IR_EXPRESSION_OBJECT_CAST
							objectCast.source = SourceOf(bound.syntax)
							objectCast.semanticType = resultEach.variableType
							If sourceClass Then objectCast.classId = sourceClass.classId Else objectCast.importedClassId = importedClass.importedClassId
							objectCast.operand = elementReference
							resultEach.elementValue = objectCast
						End If
					End If
				Else If elementAssignment And elementAssignment.kind <> CONVERSION_IDENTITY Then
					Local convertedElement:TCompilerIrConversion = New TCompilerIrConversion
					convertedElement.kind = IR_EXPRESSION_CONVERSION
					convertedElement.source = SourceOf(bound.syntax)
					convertedElement.semanticType = resultEach.variableType
					convertedElement.conversionKind = elementAssignment.kind
					convertedElement.implicitConversion = True
					convertedElement.operand = elementReference
					resultEach.elementValue = convertedElement
				End If
				Local previousLoop:TCompilerLoopLoweringContext = currentLoop
				currentLoop = BeginLoopContext(previousLoop, resultEach.loopId, resultEach.sourceLabel, resultEach)
				resultEach.body = LowerBlock(forStatement.body)
				currentLoop = previousLoop
				Local arrayIterationPlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(analysis.model.ScopeFor(bound.syntax)))
				Local arrayHeaderValue:TCompilerIrExpression
				If forStatement.loopVariable Then arrayHeaderValue = DirectSymbolReference(forStatement.loopVariable, resultEach.source)
				PrependIterationCaptureEnvironment(resultEach.body, arrayIterationPlan, forStatement.loopVariable, arrayHeaderValue)
				Return resultEach
			End If
			Local syntax:TForStatementSyntax = TForStatementSyntax(bound.syntax)
			Local variableType:TSemanticType
			If forStatement.loopVariable Then variableType = forStatement.loopVariable.declaredType Else If forStatement.target Then variableType = forStatement.target.semanticType
			If Not IsNumericType(variableType) Or Not forStatement.initialValue Or Not IsNumericType(forStatement.initialValue.semanticType) Or Not forStatement.limit Or Not IsNumericType(forStatement.limit.semanticType) Or (forStatement.stepExpression And Not IsNumericType(forStatement.stepExpression.semanticType)) Then
				AddUnsupported("BMXC1009", "Range For loops require numeric variable, initializer, limit, and step types", bound.syntax)
				Return Null
			End If
			Local resultFor:TCompilerIrForRange = New TCompilerIrForRange
			resultFor.kind = IR_STATEMENT_FOR_RANGE
			resultFor.source = SourceOf(bound.syntax)
			resultFor.loopId = NewLoopId()
			resultFor.sourceLabel = LoopLabel(bound.syntax)
			resultFor.variableType = TypeName(variableType)
			If forStatement.loopVariable Then
				resultFor.declaresVariable = True
				resultFor.variableSymbolId = RegisterSymbol(forStatement.loopVariable, "v")
				resultFor.variableName = forStatement.loopVariable.name
				Local target:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
				target.kind = IR_EXPRESSION_SYMBOL
				target.source = SourceOf(bound.syntax)
				target.semanticType = resultFor.variableType
				target.symbolId = resultFor.variableSymbolId
				target.name = resultFor.variableName
				resultFor.target = target
			Else
				resultFor.target = LowerAddressableExpression(forStatement.target)
				If Not resultFor.target Or Not IsAddressableExpression(resultFor.target) Then
					AddUnsupported("BMXC1009", "Range For requires an addressable Local, Var parameter, Field, Global, or array element target", bound.syntax)
					Return Null
				End If
			End If
			resultFor.initialValue = LowerExpression(forStatement.initialValue)
			resultFor.limit = LowerExpression(forStatement.limit)
			If forStatement.stepExpression Then
				resultFor.stepExpression = LowerExpression(forStatement.stepExpression)
				Local unaryStep:TBoundUnaryExpression = TBoundUnaryExpression(forStatement.stepExpression)
				resultFor.descending = unaryStep And unaryStep.operatorText = "-"
			Else
				Local defaultStep:TCompilerIrLiteral = New TCompilerIrLiteral
				defaultStep.kind = IR_EXPRESSION_LITERAL
				defaultStep.source = SourceOf(bound.syntax)
				defaultStep.semanticType = resultFor.variableType
				defaultStep.text = "1"
				resultFor.stepExpression = defaultStep
			End If
			If syntax And syntax.header And syntax.header.rangeToken Then resultFor.inclusiveLimit = syntax.header.rangeToken.text.ToLower() = "to"
			Local previousLoop:TCompilerLoopLoweringContext = currentLoop
			currentLoop = BeginLoopContext(previousLoop, resultFor.loopId, resultFor.sourceLabel, resultFor)
			resultFor.body = LowerBlock(forStatement.body)
			currentLoop = previousLoop
			Local rangeIterationPlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByScope.ValueForKey(analysis.model.ScopeFor(bound.syntax)))
			Local rangeHeaderValue:TCompilerIrExpression
			If forStatement.loopVariable Then rangeHeaderValue = DirectSymbolReference(forStatement.loopVariable, resultFor.source)
			PrependIterationCaptureEnvironment(resultFor.body, rangeIterationPlan, forStatement.loopVariable, rangeHeaderValue)
			If forStatement.loopVariable And rangeIterationPlan And rangeIterationPlan.fieldsBySymbol.Contains(forStatement.loopVariable) Then
				resultFor.iterationCopyBack = New TCompilerIrAssignment
				resultFor.iterationCopyBack.kind = IR_STATEMENT_ASSIGNMENT
				resultFor.iterationCopyBack.source = resultFor.source
				resultFor.iterationCopyBack.target = rangeHeaderValue
				resultFor.iterationCopyBack.value = CaptureFieldAccess(rangeIterationPlan, forStatement.loopVariable, forStatement.loopVariable.declaredType, resultFor.source)
			End If
			Return resultFor
		End If

		Local flow:TBoundFlowStatement = TBoundFlowStatement(bound)
		If flow Then
			If TEndStatementSyntax(bound.syntax) Then
				Local resultEnd:TCompilerIrApplicationEnd = New TCompilerIrApplicationEnd
				resultEnd.kind = IR_STATEMENT_APPLICATION_END
				resultEnd.source = SourceOf(bound.syntax)
				Return resultEnd
			End If
			Local restoreSyntax:TRestoreDataStatementSyntax = TRestoreDataStatementSyntax(bound.syntax)
			If restoreSyntax Then
				Local binding:TDataRestoreBinding = analysis.model.ResolvedDataRestore(restoreSyntax)
				If Not binding Then
					AddUnsupported("BMXC1223", "RestoreData has no resolved data label", bound.syntax)
					Return Null
				End If
				Local resultRestore:TCompilerIrDataRestore = New TCompilerIrDataRestore
				resultRestore.kind = IR_STATEMENT_DATA_RESTORE
				resultRestore.source = SourceOf(bound.syntax)
				resultRestore.itemIndex = binding.itemIndex
				Return resultRestore
			End If
			Local controlKind:Int
			Local labelExpression:TExpressionSyntax
			Local exited:TExitStatementSyntax = TExitStatementSyntax(bound.syntax)
			If exited Then
				controlKind = IR_LOOP_CONTROL_EXIT
				labelExpression = exited.label
			Else
				Local continued:TContinueStatementSyntax = TContinueStatementSyntax(bound.syntax)
				If continued Then
					controlKind = IR_LOOP_CONTROL_CONTINUE
					labelExpression = continued.label
				End If
			End If
			If controlKind Then
				Local target:TCompilerLoopLoweringContext = ResolveLoopContext(labelExpression)
				If Not target Then
					AddUnsupported("BMXC1007", "Loop control target was not retained by semantic analysis", bound.syntax)
					Return Null
				End If
				MarkLoopControl(target, controlKind)
				Local resultControl:TCompilerIrLoopControl = New TCompilerIrLoopControl
				resultControl.kind = IR_STATEMENT_LOOP_CONTROL
				resultControl.source = SourceOf(bound.syntax)
				resultControl.controlKind = controlKind
				resultControl.targetLoopId = target.loopId
				Local targetCleanupDepth:Int = target.cleanupDepth
				If controlKind = IR_LOOP_CONTROL_CONTINUE Then targetCleanupDepth = target.continueCleanupDepth
				resultControl.cleanupSteps = CopyActiveCleanupStepsUntil(targetCleanupDepth)
				Return resultControl
			End If
		End If

		AddUnsupported("BMXC1006", "Bound statement kind '" + bound.boundKind + "' is not implemented", bound.syntax)
		Return Null
	End Method

	Method LowerDeclaredArrayAllocation:TCompilerIrExpression(variable:TBoundVariable, syntax:TSyntaxNode)
		Local arrayType:TArraySemanticType = TArraySemanticType(variable.symbol.declaredType)
		If Not arrayType Or arrayType.rank <= 0 Or variable.arrayDimensions.length <> arrayType.rank Then
			AddUnsupported("BMXC1134", "Heap-array declaration allocation requires one dimension per declared rank", syntax)
			Return Null
		End If
		If Not IsSupportedArrayElementType(arrayType.elementType) Then
			AddUnsupported("BMXC1132", "Array element type '" + TypeName(arrayType.elementType) + "' is not implemented", syntax)
			Return Null
		End If
		Local arrayNew:TCompilerIrArrayNew = New TCompilerIrArrayNew
		arrayNew.kind = IR_EXPRESSION_ARRAY_NEW
		arrayNew.semanticType = TypeName(arrayType)
		arrayNew.source = SourceOf(syntax)
		arrayNew.elementType = TypeName(arrayType.elementType)
		arrayNew.elementEncoding = ArrayElementEncoding(arrayType.elementType)
		Local arrayEnum:TCompilerIrEnum = EnumForType(arrayType.elementType)
		If arrayEnum Then arrayNew.enumId = arrayEnum.enumId
		Local arrayStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
		Local arrayImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
		If arrayStruct Then
			arrayNew.structId = arrayStruct.structId
			arrayStruct.arrayInitializerRequired = True
		End If
		If arrayImportedStruct Then arrayNew.importedStructId = arrayImportedStruct.importedStructId
		arrayNew.rank = arrayType.rank
		arrayNew.dimensions = New TCompilerIrExpression[variable.arrayDimensions.length]
		For Local dimensionIndex:Int = 0 Until variable.arrayDimensions.length
			arrayNew.dimensions[dimensionIndex] = LowerExpression(variable.arrayDimensions[dimensionIndex])
			If Not arrayNew.dimensions[dimensionIndex] Then Return Null
		Next
		Return arrayNew
	End Method

	Function SupportedCompoundAssignmentOperator:Int(operatorText:String)
		Select operatorText.ToLower()
			Case ":+", ":-", ":*", ":/", ":&", ":|", ":~~", ":shl", ":shr", ":sar", ":mod"
				Return True
		End Select
		Return False
	End Function

	Method NewLoopId:String()
		Local result:String = "loop" + nextLoopId
		nextLoopId :+ 1
		Return result
	End Method

	Method NewTemporaryId:String()
		Local result:String = "t" + nextTemporaryId
		nextTemporaryId :+ 1
		Return result
	End Method

	Function LoopLabel:String(syntax:TSyntaxNode)
		Local label:TLabelSyntax
		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(syntax)
		If whileStatement Then label = whileStatement.label
		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(syntax)
		If repeatStatement Then label = repeatStatement.label
		Local forStatement:TForStatementSyntax = TForStatementSyntax(syntax)
		If forStatement Then label = forStatement.label
		If label And label.nameToken Then Return label.nameToken.text.ToLower()
		Return ""
	End Function

	Method BeginLoopContext:TCompilerLoopLoweringContext(parent:TCompilerLoopLoweringContext, loopId:String, sourceLabel:String, owner:TCompilerIrStatement)
		Local context:TCompilerLoopLoweringContext = New TCompilerLoopLoweringContext
		context.parent = parent
		context.loopId = loopId
		context.sourceLabel = sourceLabel
		context.owner = owner
		context.usingDepth = activeUsingBodyDepth
		context.tryDepth = activeTryBodyDepth
		context.cleanupDepth = activeReturnCleanupSteps.length
		context.continueCleanupDepth = context.cleanupDepth
		Return context
	End Method

	Method CopyActiveReturnCleanupSteps:TCompilerIrCleanupStep[]()
		Local steps:TCompilerIrCleanupStep[] = New TCompilerIrCleanupStep[activeReturnCleanupSteps.length]
		Local outputIndex:Int
		For Local index:Int = activeReturnCleanupSteps.length - 1 To 0 Step -1
			steps[outputIndex] = activeReturnCleanupSteps[index]
			outputIndex :+ 1
		Next
		Return steps
	End Method

	Method CopyActiveCleanupStepsUntil:TCompilerIrCleanupStep[](cleanupDepth:Int)
		If cleanupDepth < 0 Then cleanupDepth = 0
		If cleanupDepth > activeReturnCleanupSteps.length Then cleanupDepth = activeReturnCleanupSteps.length
		Local steps:TCompilerIrCleanupStep[] = New TCompilerIrCleanupStep[activeReturnCleanupSteps.length - cleanupDepth]
		Local outputIndex:Int
		For Local index:Int = activeReturnCleanupSteps.length - 1 To cleanupDepth Step -1
			steps[outputIndex] = activeReturnCleanupSteps[index]
			outputIndex :+ 1
		Next
		Return steps
	End Method

	Method ResolveLoopContext:TCompilerLoopLoweringContext(labelExpression:TExpressionSyntax)
		If Not labelExpression Then Return currentLoop
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(labelExpression)
		If Not name Or Not name.nameToken Then Return Null
		Local normalized:String = name.nameToken.text.ToLower()
		Local context:TCompilerLoopLoweringContext = currentLoop
		While context
			If context.sourceLabel = normalized Then Return context
			context = context.parent
		Wend
		Return Null
	End Method

	Function MarkLoopControl(context:TCompilerLoopLoweringContext, controlKind:Int)
		If Not context Then Return
		Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(context.owner)
		If whileStatement Then
			If controlKind = IR_LOOP_CONTROL_EXIT Then whileStatement.hasExit = True Else whileStatement.hasContinue = True
			Return
		End If
		Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(context.owner)
		If repeatStatement Then
			If controlKind = IR_LOOP_CONTROL_EXIT Then repeatStatement.hasExit = True Else repeatStatement.hasContinue = True
			Return
		End If
		Local forStatement:TCompilerIrForRange = TCompilerIrForRange(context.owner)
		If forStatement Then
			If controlKind = IR_LOOP_CONTROL_EXIT Then forStatement.hasExit = True Else forStatement.hasContinue = True
			Return
		End If
		Local eachStatement:TCompilerIrForEachArray = TCompilerIrForEachArray(context.owner)
		If eachStatement Then
			If controlKind = IR_LOOP_CONTROL_EXIT Then eachStatement.hasExit = True Else eachStatement.hasContinue = True
			Return
		End If
		Local stringEachStatement:TCompilerIrForEachString = TCompilerIrForEachString(context.owner)
		If stringEachStatement Then
			If controlKind = IR_LOOP_CONTROL_EXIT Then stringEachStatement.hasExit = True Else stringEachStatement.hasContinue = True
			Return
		End If
		Local staticEachStatement:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(context.owner)
		If staticEachStatement Then
			If controlKind = IR_LOOP_CONTROL_EXIT Then staticEachStatement.hasExit = True Else staticEachStatement.hasContinue = True
			Return
		End If
		Local objectEachStatement:TCompilerIrForEachObject = TCompilerIrForEachObject(context.owner)
		If objectEachStatement Then
			If controlKind = IR_LOOP_CONTROL_EXIT Then objectEachStatement.hasExit = True Else objectEachStatement.hasContinue = True
		End If
	End Function

	Function IsCompilationDirective:Int(syntax:TSyntaxNode)
		Local raw:TRawStatementSyntax = TRawStatementSyntax(syntax)
		If Not raw Or Not raw.tokens.length Then Return False
		Select raw.tokens[0].text.ToLower()
			Case "module", "moduleinfo", "nodebug"
				Return True
		End Select
		Return False
	End Function

	Method TryLowerSequenceTerminal:TCompilerIrExpression(call:TBoundCallExpression, bound:TBoundExpression)
		Local plan:TCompilerSequenceFusionPlan = RecognizeSequenceFusion(call)
		If Not plan Then Return Null

		Local inputs:TBoundExpression[] = [plan.source]
		For Local stage:TCompilerSequenceFusionStage = EachIn plan.stages
			inputs :+ [stage.argument]
		Next
		inputs :+ plan.terminalArguments

		Local helper:TCompilerIrFunction = BuildSequenceFusionHelper(plan, bound)
		If Not helper Then Return Null
		result.functions :+ [helper]

		Local loweredInputs:TCompilerIrExpression[] = New TCompilerIrExpression[inputs.length]
		Local materializations:TCompilerIrMaterialize[] = New TCompilerIrMaterialize[inputs.length]
		Local arguments:TCompilerIrExpression[] = New TCompilerIrExpression[inputs.length]
		For Local index:Int = 0 Until inputs.length
			loweredInputs[index] = LowerExpression(inputs[index])
			If Not loweredInputs[index] Then Return Null
			materializations[index] = BeginMaterialization(loweredInputs[index], inputs[index].syntax)
			Local callable:TCallableSemanticType = TCallableSemanticType(inputs[index].semanticType)
			If callable Then
				materializations[index].temporaryCallableReturnType = TypeName(callable.returnType)
				materializations[index].temporaryCallableParameters = CallableParameters(callable)
				materializations[index].temporaryCallableCallingConvention = callable.callingConvention
			End If
			arguments[index] = TemporaryReference(materializations[index], inputs[index], inputs[index].syntax, "sequence")
		Next

		Local fusedCall:TCompilerIrCall = New TCompilerIrCall
		InitializeExpression(fusedCall, IR_EXPRESSION_CALL, bound)
		fusedCall.functionId = helper.functionId
		fusedCall.functionName = helper.name
		fusedCall.dispatchKind = IR_CALL_DISPATCH_DIRECT
		fusedCall.arguments = arguments
		Local fused:TCompilerIrExpression = fusedCall
		For Local index:Int = materializations.length - 1 To 0 Step -1
			materializations[index].expression = fused
			materializations[index].semanticType = fusedCall.semanticType
			fused = materializations[index]
		Next
		Return fused
	End Method

	Method RecognizeSequenceFusion:TCompilerSequenceFusionPlan(call:TBoundCallExpression)
		If Not call Or Not call.resolvedCall Or Not call.resolvedCall.routine Or Not IsSequenceRoutine(call.resolvedCall.routine) Then Return Null
		Local plan:TCompilerSequenceFusionPlan = New TCompilerSequenceFusionPlan
		Select call.resolvedCall.routine.name.ToLower()
			Case "fold"
				If call.arguments.length <> 2 Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_FOLD
			Case "count"
				If call.arguments.length > 1 Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_COUNT
			Case "any"
				If call.arguments.length > 1 Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_ANY
			Case "all"
				If call.arguments.length <> 1 Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_ALL
			Case "firstornone"
				If call.arguments.length > 1 Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_FIRST_OR_NONE
			Case "lastornone"
				If call.arguments.length Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_LAST_OR_NONE
			Case "foreach"
				If call.arguments.length <> 1 Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_FOR_EACH
			Case "toarray"
				If call.arguments.length Then Return Null
				plan.terminalKind = SEQUENCE_FUSION_TO_ARRAY
			Default
				Return Null
		End Select
		If Not call.receiver Or Not RecognizeSequenceSource(call.receiver, plan) Then Return Null
		plan.terminalArguments = call.arguments
		plan.resultType = call.semanticType
		If Not IsVoidType(plan.resultType) And Not IsSupportedValueType(plan.resultType) Then Return Null
		Local elementType:TSemanticType = SequenceElementType(call.receiver.semanticType)
		If Not elementType Then Return Null
		Select plan.terminalKind
			Case SEQUENCE_FUSION_FOLD
				If TypeName(call.arguments[0].semanticType).ToLower() <> TypeName(plan.resultType).ToLower() Or Not IsFoldSequenceClosure(call.arguments[1], plan.resultType, elementType) Then Return Null
			Case SEQUENCE_FUSION_COUNT
				If call.arguments.length And Not IsUnarySequenceClosure(call.arguments[0], elementType, "Int") Then Return Null
			Case SEQUENCE_FUSION_ANY
				If call.arguments.length And Not IsUnarySequenceClosure(call.arguments[0], elementType, "Int") Then Return Null
			Case SEQUENCE_FUSION_ALL
				If Not IsUnarySequenceClosure(call.arguments[0], elementType, "Int") Then Return Null
			Case SEQUENCE_FUSION_FIRST_OR_NONE, SEQUENCE_FUSION_LAST_OR_NONE
				Local optionalType:TNamedSemanticType = TNamedSemanticType(plan.resultType)
				If Not optionalType Or Not optionalType.symbol Or optionalType.symbol.originModule.ToLower() <> "brl.optional" Or optionalType.symbol.name.ToLower() <> "optional" Or optionalType.typeArguments.length <> 1 Then Return Null
				If TypeName(optionalType.typeArguments[0]).ToLower() <> TypeName(elementType).ToLower() Then Return Null
				If plan.terminalKind = SEQUENCE_FUSION_FIRST_OR_NONE And call.arguments.length And Not IsUnarySequenceClosure(call.arguments[0], elementType, "Int") Then Return Null
			Case SEQUENCE_FUSION_FOR_EACH
				If Not IsUnarySequenceClosure(call.arguments[0], elementType, "Void") Then Return Null
			Case SEQUENCE_FUSION_TO_ARRAY
				Local resultArray:TArraySemanticType = TArraySemanticType(plan.resultType)
				If Not resultArray Or resultArray.rank <> 1 Or TypeName(resultArray.elementType).ToLower() <> TypeName(elementType).ToLower() Then Return Null
		End Select
		Return plan
	End Method

	Method RecognizeSequenceSource:Int(expression:TBoundExpression, plan:TCompilerSequenceFusionPlan)
		Local call:TBoundCallExpression = TBoundCallExpression(expression)
		If Not call Or Not call.resolvedCall Or Not call.resolvedCall.routine Or Not IsSequenceRoutine(call.resolvedCall.routine) Then Return False
		Local name:String = call.resolvedCall.routine.name.ToLower()
		If name = "fromarray" Then
			If call.arguments.length <> 1 Or call.receiver Or Not SequenceElementType(call.staticReceiverType) Then Return False
			Local arrayType:TArraySemanticType = TArraySemanticType(call.arguments[0].semanticType)
			If Not arrayType Or arrayType.rank <> 1 Or Not IsSupportedArrayElementType(arrayType.elementType) Then Return False
			plan.source = call.arguments[0]
			plan.sourceElementType = arrayType.elementType
			Return True
		End If
		If Not call.receiver Or call.arguments.length <> 1 Or Not RecognizeSequenceSource(call.receiver, plan) Then Return False
		Local stage:TCompilerSequenceFusionStage = New TCompilerSequenceFusionStage
		stage.argument = call.arguments[0]
		stage.inputType = SequenceElementType(call.receiver.semanticType)
		stage.outputType = SequenceElementType(call.semanticType)
		If Not stage.inputType Or Not stage.outputType Then Return False
		Select name
			Case "filter"
				stage.kind = SEQUENCE_FUSION_FILTER
				If Not IsUnarySequenceClosure(stage.argument, stage.inputType, "Int") Then Return False
			Case "map"
				stage.kind = SEQUENCE_FUSION_MAP
				If Not IsUnarySequenceClosure(stage.argument, stage.inputType, TypeName(stage.outputType)) Then Return False
			Case "take"
				stage.kind = SEQUENCE_FUSION_TAKE
				If TypeName(stage.argument.semanticType).ToLower() <> "int" Then Return False
			Case "skip"
				stage.kind = SEQUENCE_FUSION_SKIP
				If TypeName(stage.argument.semanticType).ToLower() <> "int" Then Return False
			Case "takewhile"
				stage.kind = SEQUENCE_FUSION_TAKE_WHILE
				If Not IsUnarySequenceClosure(stage.argument, stage.inputType, "Int") Then Return False
			Case "skipwhile"
				stage.kind = SEQUENCE_FUSION_SKIP_WHILE
				If Not IsUnarySequenceClosure(stage.argument, stage.inputType, "Int") Then Return False
			Default
				Return False
		End Select
		plan.stages :+ [stage]
		Return True
	End Method

	Function IsSequenceRoutine:Int(routine:TSymbol)
		If Not routine Or routine.kind <> SYMBOL_ROUTINE Or routine.originModule.ToLower() <> "brl.sequence" Then Return False
		If Not routine.containingScope Or Not routine.containingScope.owner Then Return False
		Local owner:TSymbol = routine.containingScope.owner
		Return owner.name.ToLower() = "sequence" And owner.genericArity = 1
	End Function

	Function SequenceElementType:TSemanticType(value:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named And named.symbol And named.symbol.name.ToLower() = "sequence" And named.symbol.originModule.ToLower() = "brl.sequence" And named.typeArguments.length = 1 Then Return named.typeArguments[0]
		Return Null
	End Function

	Method IsUnarySequenceClosure:Int(argument:TBoundExpression, inputType:TSemanticType, outputType:String)
		If Not argument Then Return False
		Local closure:TClosureSemanticType = TClosureSemanticType(argument.semanticType)
		Local callable:TCallableSemanticType = TCallableSemanticType(argument.semanticType)
		If closure Then callable = closure.signature
		If Not callable Or callable.parameterTypes.length <> 1 Then Return False
		If callable.parameterModes.length And callable.parameterModes[0] <> PARAMETER_PASS_VALUE Then Return False
		Return TypeName(callable.parameterTypes[0]).ToLower() = TypeName(inputType).ToLower() And TypeName(callable.returnType).ToLower() = outputType.ToLower()
	End Method

	Method IsFoldSequenceClosure:Int(argument:TBoundExpression, resultType:TSemanticType, elementType:TSemanticType)
		If Not argument Then Return False
		Local closure:TClosureSemanticType = TClosureSemanticType(argument.semanticType)
		Local callable:TCallableSemanticType = TCallableSemanticType(argument.semanticType)
		If closure Then callable = closure.signature
		If Not callable Or callable.parameterTypes.length <> 2 Then Return False
		For Local mode:Int = EachIn callable.parameterModes
			If mode <> PARAMETER_PASS_VALUE Then Return False
		Next
		Return TypeName(callable.parameterTypes[0]).ToLower() = TypeName(resultType).ToLower() And ..
			TypeName(callable.parameterTypes[1]).ToLower() = TypeName(elementType).ToLower() And ..
			TypeName(callable.returnType).ToLower() = TypeName(resultType).ToLower()
	End Method

	Method BuildSequenceFusionHelper:TCompilerIrFunction(plan:TCompilerSequenceFusionPlan, bound:TBoundExpression)
		Local optionalFactory:TCompilerIrImportedStructRoutine
		If plan.terminalKind = SEQUENCE_FUSION_FIRST_OR_NONE Or plan.terminalKind = SEQUENCE_FUSION_LAST_OR_NONE Then
			optionalFactory = FusionImportedStructTypeFunction(plan.resultType, "FromValue", TypeName(FusionFinalElementType(plan)))
			If Not optionalFactory Then Return Null
		End If
		Local helper:TCompilerIrFunction = New TCompilerIrFunction
		helper.functionId = "fn" + nextFunctionId
		nextFunctionId :+ 1
		helper.name = "$sequence_fused_" + helper.functionId
		helper.debugName = helper.name
		helper.returnType = TypeName(plan.resultType)
		helper.source = SourceOf(bound.syntax)
		helper.suppressDebugInfo = True
		helper.body = New TCompilerIrBlock
		helper.body.source = helper.source

		Local sourceParameter:TCompilerIrParameter = FusionParameter(plan.source, helper.functionId + "_source", "source")
		helper.parameters = [sourceParameter]
		Local parameterIndex:Int = 1
		For Local stage:TCompilerSequenceFusionStage = EachIn plan.stages
			stage.parameter = FusionParameter(stage.argument, helper.functionId + "_p" + parameterIndex, "operator" + parameterIndex)
			helper.parameters :+ [stage.parameter]
			parameterIndex :+ 1
		Next
		plan.terminalParameters = New TCompilerIrParameter[plan.terminalArguments.length]
		For Local index:Int = 0 Until plan.terminalArguments.length
			Local parameter:TCompilerIrParameter = FusionParameter(plan.terminalArguments[index], helper.functionId + "_p" + parameterIndex, "terminal" + index)
			plan.terminalParameters[index] = parameter
			helper.parameters :+ [parameter]
			parameterIndex :+ 1
		Next

		Local accumulator:TCompilerIrSymbolReference
		If plan.terminalKind = SEQUENCE_FUSION_FOLD Or plan.terminalKind = SEQUENCE_FUSION_COUNT Or plan.terminalKind = SEQUENCE_FUSION_TO_ARRAY Or plan.terminalKind = SEQUENCE_FUSION_LAST_OR_NONE Then
			Local accumulatorType:String = helper.returnType
			If plan.terminalKind = SEQUENCE_FUSION_TO_ARRAY Then accumulatorType = "Int"
			accumulator = FusionSymbol(helper.functionId + "_result", "result", accumulatorType, helper.source)
			Local initial:TCompilerIrExpression = ScalarDefault("Int", helper.source)
			If plan.terminalKind = SEQUENCE_FUSION_FOLD Then initial = FusionSymbolForParameter(plan.terminalParameters[0], helper.source)
			If plan.terminalKind = SEQUENCE_FUSION_LAST_OR_NONE Then initial = StructDefault(plan.resultType, helper.source, plan.source.syntax)
			helper.body.statements :+ [FusionVariable(accumulator, initial, helper.source)]
		End If

		For Local stage:TCompilerSequenceFusionStage = EachIn plan.stages
			If stage.kind = SEQUENCE_FUSION_TAKE Or stage.kind = SEQUENCE_FUSION_SKIP Then
				stage.counterSymbolId = helper.functionId + "_counter" + helper.body.statements.length
				Local counter:TCompilerIrSymbolReference = FusionSymbol(stage.counterSymbolId, "remaining", "Int", helper.source)
				helper.body.statements :+ [FusionVariable(counter, FusionSymbolForParameter(stage.parameter, helper.source), helper.source)]
			Else If stage.kind = SEQUENCE_FUSION_SKIP_WHILE Then
				stage.stateSymbolId = helper.functionId + "_state" + helper.body.statements.length
				Local state:TCompilerIrSymbolReference = FusionState(stage, helper.source)
				helper.body.statements :+ [FusionVariable(state, FusionIntLiteral(1, helper.source), helper.source)]
			End If
		Next

		Local outputArray:TCompilerIrSymbolReference
		Local outputCapacity:TCompilerIrSymbolReference
		If plan.terminalKind = SEQUENCE_FUSION_TO_ARRAY Then
			Local arrayType:TArraySemanticType = TArraySemanticType(plan.resultType)
			If Not arrayType Then Return Null
			outputCapacity = FusionSymbol(helper.functionId + "_capacity", "capacity", "Int", helper.source)
			Local sourceLength:TCompilerIrExpression = FusionArrayLength(FusionSymbolForParameter(sourceParameter, helper.source), helper.source)
			helper.body.statements :+ [FusionVariable(outputCapacity, sourceLength, helper.source)]
			For Local stage:TCompilerSequenceFusionStage = EachIn plan.stages
				If stage.kind <> SEQUENCE_FUSION_TAKE Then Continue
				Local takeCounter:TCompilerIrSymbolReference = FusionCounter(stage, helper.source)
				Local nonPositive:TCompilerIrExpression = FusionBinary("<=", takeCounter, FusionIntLiteral(0, helper.source), helper.source)
				Local tighter:TCompilerIrExpression = FusionBinary("<", takeCounter, outputCapacity, helper.source)
				Local useTake:TCompilerIrStatement = FusionAssignment(outputCapacity, "=", takeCounter, helper.source)
				Local clamp:TCompilerIrStatement = FusionIf(nonPositive, [FusionAssignment(outputCapacity, "=", FusionIntLiteral(0, helper.source), helper.source)], [FusionIf(tighter, [useTake], Null, helper.source)], helper.source)
				helper.body.statements :+ [clamp]
			Next
			outputArray = FusionSymbol(helper.functionId + "_values", "values", helper.returnType, helper.source)
			Local allocation:TCompilerIrArrayNew = FusionArrayNew(arrayType, outputCapacity, helper.source)
			If Not allocation Then Return Null
			helper.body.statements :+ [FusionVariable(outputArray, allocation, helper.source)]
		End If

		Local terminalDefault:TCompilerIrExpression = FusionTerminalDefault(plan, accumulator, outputArray, helper.source)
		For Local stage:TCompilerSequenceFusionStage = EachIn plan.stages
			If stage.kind <> SEQUENCE_FUSION_TAKE Then Continue
			Local exhausted:TCompilerIrExpression = FusionBinary("<=", FusionCounter(stage, helper.source), ScalarDefault("Int", helper.source), helper.source)
			Local emptyResult:TCompilerIrExpression = terminalDefault
			If plan.terminalKind = SEQUENCE_FUSION_TO_ARRAY Then emptyResult = outputArray
			helper.body.statements :+ [FusionIf(exhausted, [FusionReturn(emptyResult, helper.source)], Null, helper.source)]
		Next

		Local loop:TCompilerIrForEachArray = New TCompilerIrForEachArray
		loop.kind = IR_STATEMENT_FOR_EACH_ARRAY
		loop.source = helper.source
		loop.loopId = "sequence_" + helper.functionId
		loop.variableType = TypeName(plan.sourceElementType)
		loop.elementType = loop.variableType
		loop.declaresVariable = True
		loop.variableSymbolId = helper.functionId + "_value0"
		loop.variableName = "value"
		loop.target = FusionSymbol(loop.variableSymbolId, loop.variableName, loop.variableType, helper.source)
		loop.collection = FusionSymbolForParameter(sourceParameter, helper.source)
		loop.collectionTemporaryId = helper.functionId + "_array"
		loop.indexTemporaryId = helper.functionId + "_index"
		loop.elementTemporaryId = helper.functionId + "_element"
		loop.elementValue = FusionSymbol(loop.elementTemporaryId, "element", loop.elementType, helper.source)
		loop.body = New TCompilerIrBlock
		loop.body.source = helper.source

		Local value:TCompilerIrExpression = loop.target
		Local activeTakes:TCompilerIrSymbolReference[] = New TCompilerIrSymbolReference[0]
		Local mapIndex:Int
		For Local stage:TCompilerSequenceFusionStage = EachIn plan.stages
			Select stage.kind
				Case SEQUENCE_FUSION_FILTER
					Local predicate:TCompilerIrExpression = FusionCallableCall(stage.argument, stage.parameter, [value], helper.source)
					Local rejected:TCompilerIrUnary = FusionNot(predicate, helper.source)
					loop.body.statements :+ [FusionIf(rejected, FusionStopOrContinue(activeTakes, loop, helper.source), Null, helper.source)]
				Case SEQUENCE_FUSION_MAP
					Local mapped:TCompilerIrExpression = FusionCallableCall(stage.argument, stage.parameter, [value], helper.source)
					Local mappedSymbol:TCompilerIrSymbolReference = FusionSymbol(helper.functionId + "_mapped" + mapIndex, "mapped" + mapIndex, TypeName(stage.outputType), helper.source)
					mapIndex :+ 1
					loop.body.statements :+ [FusionVariable(mappedSymbol, mapped, helper.source)]
					value = mappedSymbol
				Case SEQUENCE_FUSION_TAKE
					Local takeCounter:TCompilerIrSymbolReference = FusionCounter(stage, helper.source)
					Local takeExhausted:TCompilerIrExpression = FusionBinary("<=", takeCounter, ScalarDefault("Int", helper.source), helper.source)
					loop.body.statements :+ [FusionIf(takeExhausted, [FusionLoopControl(IR_LOOP_CONTROL_EXIT, loop.loopId, helper.source)], Null, helper.source)]
					loop.hasExit = True
					loop.body.statements :+ [FusionAssignment(takeCounter, ":-", FusionIntLiteral(1, helper.source), helper.source)]
					activeTakes :+ [takeCounter]
				Case SEQUENCE_FUSION_SKIP
					Local skipCounter:TCompilerIrSymbolReference = FusionCounter(stage, helper.source)
					Local skipping:TCompilerIrExpression = FusionBinary(">", skipCounter, ScalarDefault("Int", helper.source), helper.source)
					Local skipBody:TCompilerIrStatement[] = [FusionAssignment(skipCounter, ":-", FusionIntLiteral(1, helper.source), helper.source)] + FusionStopOrContinue(activeTakes, loop, helper.source)
					loop.body.statements :+ [FusionIf(skipping, skipBody, Null, helper.source)]
				Case SEQUENCE_FUSION_TAKE_WHILE
					Local takeWhilePredicate:TCompilerIrExpression = FusionCallableCall(stage.argument, stage.parameter, [value], helper.source)
					Local takeWhileRejected:TCompilerIrUnary = FusionNot(takeWhilePredicate, helper.source)
					loop.body.statements :+ [FusionIf(takeWhileRejected, [FusionLoopControl(IR_LOOP_CONTROL_EXIT, loop.loopId, helper.source)], Null, helper.source)]
					loop.hasExit = True
				Case SEQUENCE_FUSION_SKIP_WHILE
					Local skipWhileState:TCompilerIrSymbolReference = FusionState(stage, helper.source)
					Local skipWhilePredicate:TCompilerIrExpression = FusionCallableCall(stage.argument, stage.parameter, [value], helper.source)
					Local keepSkipping:TCompilerIrStatement[] = FusionStopOrContinue(activeTakes, loop, helper.source)
					Local stopSkipping:TCompilerIrStatement = FusionAssignment(skipWhileState, "=", FusionIntLiteral(0, helper.source), helper.source)
					Local testPrefix:TCompilerIrStatement = FusionIf(skipWhilePredicate, keepSkipping, [stopSkipping], helper.source)
					loop.body.statements :+ [FusionIf(skipWhileState, [testPrefix], Null, helper.source)]
			End Select
		Next

		Select plan.terminalKind
			Case SEQUENCE_FUSION_FOLD
				Local folded:TCompilerIrExpression = FusionCallableCall(plan.terminalArguments[1], plan.terminalParameters[1], [accumulator, value], helper.source)
				loop.body.statements :+ [FusionAssignment(accumulator, "=", folded, helper.source)]
			Case SEQUENCE_FUSION_COUNT
				Local increment:TCompilerIrStatement = FusionAssignment(accumulator, ":+", FusionIntLiteral(1, helper.source), helper.source)
				If plan.terminalArguments.length Then
					Local countMatch:TCompilerIrExpression = FusionCallableCall(plan.terminalArguments[0], plan.terminalParameters[0], [value], helper.source)
					loop.body.statements :+ [FusionIf(countMatch, [increment], Null, helper.source)]
				Else
					loop.body.statements :+ [increment]
				End If
			Case SEQUENCE_FUSION_ANY
				If plan.terminalArguments.length Then
					Local anyMatch:TCompilerIrExpression = FusionCallableCall(plan.terminalArguments[0], plan.terminalParameters[0], [value], helper.source)
					loop.body.statements :+ [FusionIf(anyMatch, [FusionReturn(FusionIntLiteral(1, helper.source), helper.source)], Null, helper.source)]
				Else
					loop.body.statements :+ [FusionReturn(FusionIntLiteral(1, helper.source), helper.source)]
				End If
			Case SEQUENCE_FUSION_ALL
				Local allMatch:TCompilerIrExpression = FusionCallableCall(plan.terminalArguments[0], plan.terminalParameters[0], [value], helper.source)
				loop.body.statements :+ [FusionIf(FusionNot(allMatch, helper.source), [FusionReturn(ScalarDefault("Int", helper.source), helper.source)], Null, helper.source)]
			Case SEQUENCE_FUSION_FIRST_OR_NONE
				Local firstResult:TCompilerIrStatement = FusionReturn(FusionImportedStructTypeFunctionCall(optionalFactory, plan.resultType, [value], helper.source), helper.source)
				If plan.terminalArguments.length Then
					Local firstMatch:TCompilerIrExpression = FusionCallableCall(plan.terminalArguments[0], plan.terminalParameters[0], [value], helper.source)
					loop.body.statements :+ [FusionIf(firstMatch, [firstResult], Null, helper.source)]
				Else
					loop.body.statements :+ [firstResult]
				End If
			Case SEQUENCE_FUSION_LAST_OR_NONE
				Local lastValue:TCompilerIrExpression = FusionImportedStructTypeFunctionCall(optionalFactory, plan.resultType, [value], helper.source)
				loop.body.statements :+ [FusionAssignment(accumulator, "=", lastValue, helper.source)]
			Case SEQUENCE_FUSION_FOR_EACH
				Local invoked:TCompilerIrExpression = FusionCallableCall(plan.terminalArguments[0], plan.terminalParameters[0], [value], helper.source)
				loop.body.statements :+ [FusionExpressionStatement(invoked, helper.source)]
			Case SEQUENCE_FUSION_TO_ARRAY
				Local outputElement:TCompilerIrArrayElement = FusionArrayElement(outputArray, accumulator, TArraySemanticType(plan.resultType), helper.source)
				If Not outputElement Then Return Null
				loop.body.statements :+ [FusionAssignment(outputElement, "=", value, helper.source)]
				loop.body.statements :+ [FusionAssignment(accumulator, ":+", FusionIntLiteral(1, helper.source), helper.source)]
		End Select

		If activeTakes.length Then
			Local finalExhausted:TCompilerIrExpression = FusionAnyTakeExhausted(activeTakes, helper.source)
			loop.body.statements :+ [FusionIf(finalExhausted, [FusionLoopControl(IR_LOOP_CONTROL_EXIT, loop.loopId, helper.source)], Null, helper.source)]
			loop.hasExit = True
		End If
		helper.body.statements :+ [loop]
		If plan.terminalKind = SEQUENCE_FUSION_TO_ARRAY Then
			Local exact:TCompilerIrExpression = FusionBinary("=", accumulator, outputCapacity, helper.source)
			helper.body.statements :+ [FusionIf(exact, [FusionReturn(outputArray, helper.source)], Null, helper.source)]
		End If
		helper.body.statements :+ [FusionReturn(FusionTerminalDefault(plan, accumulator, outputArray, helper.source), helper.source)]
		Return helper
	End Method

	Method FusionParameter:TCompilerIrParameter(bound:TBoundExpression, symbolId:String, name:String)
		Local parameter:TCompilerIrParameter = New TCompilerIrParameter
		parameter.symbolId = symbolId
		parameter.name = name
		parameter.semanticType = TypeName(bound.semanticType)
		PopulateParameterShape(parameter, bound.semanticType)
		Return parameter
	End Method

	Function FusionSymbolForParameter:TCompilerIrSymbolReference(parameter:TCompilerIrParameter, source:TCompilerSourceLocation)
		Return FusionSymbol(parameter.symbolId, parameter.name, parameter.semanticType, source)
	End Function

	Function FusionSymbol:TCompilerIrSymbolReference(symbolId:String, name:String, semanticType:String, source:TCompilerSourceLocation)
		Local symbol:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		symbol.kind = IR_EXPRESSION_SYMBOL
		symbol.symbolId = symbolId
		symbol.name = name
		symbol.semanticType = semanticType
		symbol.source = source
		Return symbol
	End Function

	Function FusionVariable:TCompilerIrVariableDeclaration(symbol:TCompilerIrSymbolReference, initializer:TCompilerIrExpression, source:TCompilerSourceLocation)
		Local variable:TCompilerIrVariableDeclaration = New TCompilerIrVariableDeclaration
		variable.kind = IR_STATEMENT_VARIABLE
		variable.symbolId = symbol.symbolId
		variable.name = symbol.name
		variable.semanticType = symbol.semanticType
		variable.storage = "local"
		variable.hasExplicitInitializer = True
		variable.initializer = initializer
		variable.source = source
		Return variable
	End Function

	Function FusionAssignment:TCompilerIrAssignment(target:TCompilerIrExpression, operatorText:String, value:TCompilerIrExpression, source:TCompilerSourceLocation)
		Local assignment:TCompilerIrAssignment = New TCompilerIrAssignment
		assignment.kind = IR_STATEMENT_ASSIGNMENT
		assignment.target = target
		assignment.operatorText = operatorText
		assignment.value = value
		assignment.source = source
		Return assignment
	End Function

	Function FusionIf:TCompilerIrIf(condition:TCompilerIrExpression, thenStatements:TCompilerIrStatement[], elseStatements:TCompilerIrStatement[], source:TCompilerSourceLocation)
		Local conditional:TCompilerIrIf = New TCompilerIrIf
		conditional.kind = IR_STATEMENT_IF
		conditional.condition = condition
		conditional.source = source
		conditional.thenBody = New TCompilerIrBlock
		conditional.thenBody.source = source
		conditional.thenBody.statements = thenStatements
		If elseStatements Then
			conditional.elseBody = New TCompilerIrBlock
			conditional.elseBody.source = source
			conditional.elseBody.statements = elseStatements
		End If
		Return conditional
	End Function

	Function FusionReturn:TCompilerIrReturn(value:TCompilerIrExpression, source:TCompilerSourceLocation)
		Local returned:TCompilerIrReturn = New TCompilerIrReturn
		returned.kind = IR_STATEMENT_RETURN
		returned.expression = value
		returned.source = source
		Return returned
	End Function

	Function FusionExpressionStatement:TCompilerIrExpressionStatement(expression:TCompilerIrExpression, source:TCompilerSourceLocation)
		Local statement:TCompilerIrExpressionStatement = New TCompilerIrExpressionStatement
		statement.kind = IR_STATEMENT_EXPRESSION
		statement.expression = expression
		statement.source = source
		Return statement
	End Function

	Function FusionLoopControl:TCompilerIrLoopControl(kind:Int, loopId:String, source:TCompilerSourceLocation)
		Local control:TCompilerIrLoopControl = New TCompilerIrLoopControl
		control.kind = IR_STATEMENT_LOOP_CONTROL
		control.controlKind = kind
		control.targetLoopId = loopId
		control.source = source
		Return control
	End Function

	Function FusionIntLiteral:TCompilerIrLiteral(value:Int, source:TCompilerSourceLocation)
		Local literal:TCompilerIrLiteral = New TCompilerIrLiteral
		literal.kind = IR_EXPRESSION_LITERAL
		literal.semanticType = "Int"
		literal.text = String(value)
		literal.source = source
		Return literal
	End Function

	Function FusionArrayLength:TCompilerIrArrayLength(receiver:TCompilerIrExpression, source:TCompilerSourceLocation)
		Local length:TCompilerIrArrayLength = New TCompilerIrArrayLength
		length.kind = IR_EXPRESSION_ARRAY_LENGTH
		length.semanticType = "Int"
		length.receiver = receiver
		length.source = source
		Return length
	End Function

	Method FusionArrayNew:TCompilerIrArrayNew(arrayType:TArraySemanticType, length:TCompilerIrExpression, source:TCompilerSourceLocation)
		If Not arrayType Or arrayType.rank <> 1 Or Not IsSupportedArrayElementType(arrayType.elementType) Then Return Null
		Local allocation:TCompilerIrArrayNew = New TCompilerIrArrayNew
		allocation.kind = IR_EXPRESSION_ARRAY_NEW
		allocation.semanticType = TypeName(arrayType)
		allocation.source = source
		allocation.elementType = TypeName(arrayType.elementType)
		allocation.elementEncoding = ArrayElementEncoding(arrayType.elementType)
		Local arrayEnum:TCompilerIrEnum = EnumForType(arrayType.elementType)
		If arrayEnum Then allocation.enumId = arrayEnum.enumId
		Local arrayStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
		Local arrayImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
		If arrayStruct Then
			allocation.structId = arrayStruct.structId
			arrayStruct.arrayInitializerRequired = True
		End If
		If arrayImportedStruct Then allocation.importedStructId = arrayImportedStruct.importedStructId
		allocation.rank = 1
		allocation.dimensions = [length]
		Return allocation
	End Method

	Method FusionArrayElement:TCompilerIrArrayElement(receiver:TCompilerIrExpression, index:TCompilerIrExpression, arrayType:TArraySemanticType, source:TCompilerSourceLocation)
		If Not arrayType Or arrayType.rank <> 1 Or Not IsSupportedArrayElementType(arrayType.elementType) Then Return Null
		Local element:TCompilerIrArrayElement = New TCompilerIrArrayElement
		element.kind = IR_EXPRESSION_ARRAY_ELEMENT
		element.semanticType = TypeName(arrayType.elementType)
		element.source = source
		element.receiver = receiver
		element.indexes = [index]
		element.elementType = element.semanticType
		Local callable:TCallableSemanticType = TCallableSemanticType(arrayType.elementType)
		If callable Then
			element.callableReturnType = TypeName(callable.returnType)
			element.callableParameters = CallableParameters(callable)
			element.callableCallingConvention = callable.callingConvention
		End If
		Local elementStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
		Local elementImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
		If elementStruct Then element.structId = elementStruct.structId
		If elementImportedStruct Then element.importedStructId = elementImportedStruct.importedStructId
		element.rank = 1
		Return element
	End Method

	Method FusionArraySlice:TCompilerIrArraySlice(receiver:TCompilerIrExpression, upperBound:TCompilerIrExpression, arrayType:TArraySemanticType, source:TCompilerSourceLocation)
		If Not arrayType Or arrayType.rank <> 1 Or Not IsSupportedArrayElementType(arrayType.elementType) Then Return Null
		Local slice:TCompilerIrArraySlice = New TCompilerIrArraySlice
		slice.kind = IR_EXPRESSION_ARRAY_SLICE
		slice.semanticType = TypeName(arrayType)
		slice.source = source
		slice.receiver = receiver
		slice.lowerBound = FusionIntLiteral(0, source)
		slice.upperBound = upperBound
		slice.elementType = TypeName(arrayType.elementType)
		slice.elementEncoding = ArrayElementEncoding(arrayType.elementType)
		Local elementStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
		Local elementImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
		If elementStruct Then
			slice.structId = elementStruct.structId
			elementStruct.arrayInitializerRequired = True
		End If
		If elementImportedStruct Then slice.importedStructId = elementImportedStruct.importedStructId
		Return slice
	End Method

	Function FusionBinary:TCompilerIrBinary(operatorText:String, left:TCompilerIrExpression, right:TCompilerIrExpression, source:TCompilerSourceLocation)
		Local binary:TCompilerIrBinary = New TCompilerIrBinary
		binary.kind = IR_EXPRESSION_BINARY
		binary.semanticType = "Int"
		binary.operatorText = operatorText
		binary.left = left
		binary.right = right
		binary.source = source
		Return binary
	End Function

	Function FusionNot:TCompilerIrUnary(operand:TCompilerIrExpression, source:TCompilerSourceLocation)
		Local unary:TCompilerIrUnary = New TCompilerIrUnary
		unary.kind = IR_EXPRESSION_UNARY
		unary.semanticType = "Int"
		unary.operatorText = "not"
		unary.operand = operand
		unary.source = source
		Return unary
	End Function

	Method FusionCallableCall:TCompilerIrExpression(boundClosure:TBoundExpression, parameter:TCompilerIrParameter, arguments:TCompilerIrExpression[], source:TCompilerSourceLocation)
		Local closure:TClosureSemanticType = TClosureSemanticType(boundClosure.semanticType)
		Local callable:TCallableSemanticType = TCallableSemanticType(boundClosure.semanticType)
		If closure Then callable = closure.signature
		If Not callable Then Return Null
		Local literal:TBoundFunctionLiteralExpression = TBoundFunctionLiteralExpression(boundClosure)
		If literal And Not literal.captures.length And Not literal.capturesSelf Then
			Local target:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(literal.routine))
			If target Then
				Local direct:TCompilerIrCall = New TCompilerIrCall
				direct.kind = IR_EXPRESSION_CALL
				direct.semanticType = TypeName(callable.returnType)
				direct.source = source
				direct.functionId = target.functionId
				direct.functionName = target.name
				direct.dispatchKind = IR_CALL_DISPATCH_DIRECT
				direct.arguments = arguments
				If target.isClosureInvoke Then direct.arguments = [ManagedDefault("Object", IR_MANAGED_REFERENCE_OBJECT, source)] + arguments
				Return direct
			End If
		End If
		Local routineReference:TBoundRoutineReferenceExpression = TBoundRoutineReferenceExpression(boundClosure)
		If routineReference Then
			Local reference:TCompilerIrCallableReference = CallableReferenceForSymbol(routineReference.routine, callable, source, boundClosure.syntax, routineReference.staticReceiverType, routineReference.typeArguments)
			If reference Then
				Local direct:TCompilerIrCall = New TCompilerIrCall
				direct.kind = IR_EXPRESSION_CALL
				direct.semanticType = TypeName(callable.returnType)
				direct.source = source
				direct.functionId = reference.functionId
				direct.functionAbiName = reference.abiName
				direct.functionName = reference.functionName
				direct.isExternal = reference.isExternal
				direct.dispatchKind = IR_CALL_DISPATCH_DIRECT
				direct.arguments = arguments
				Return direct
			End If
		End If
		If Not closure Then
			Local indirect:TCompilerIrIndirectCall = New TCompilerIrIndirectCall
			indirect.kind = IR_EXPRESSION_INDIRECT_CALL
			indirect.semanticType = TypeName(callable.returnType)
			indirect.source = source
			indirect.callee = FusionSymbolForParameter(parameter, source)
			indirect.returnType = indirect.semanticType
			indirect.parameters = CallableParameters(callable)
			indirect.callingConvention = callable.callingConvention
			indirect.arguments = arguments
			Return indirect
		End If
		Local call:TCompilerIrClosureCall = New TCompilerIrClosureCall
		call.kind = IR_EXPRESSION_CLOSURE_CALL
		call.semanticType = TypeName(callable.returnType)
		call.returnType = call.semanticType
		call.parameters = CallableParameters(callable)
		call.callee = FusionSymbolForParameter(parameter, source)
		call.arguments = arguments
		call.source = source
		Return call
	End Method

	Function FusionCounter:TCompilerIrSymbolReference(stage:TCompilerSequenceFusionStage, source:TCompilerSourceLocation)
		Return FusionSymbol(stage.counterSymbolId, "remaining", "Int", source)
	End Function

	Function FusionState:TCompilerIrSymbolReference(stage:TCompilerSequenceFusionStage, source:TCompilerSourceLocation)
		Return FusionSymbol(stage.stateSymbolId, "skipping", "Int", source)
	End Function

	Function FusionAnyTakeExhausted:TCompilerIrExpression(takes:TCompilerIrSymbolReference[], source:TCompilerSourceLocation)
		Local result:TCompilerIrExpression
		For Local take:TCompilerIrSymbolReference = EachIn takes
			Local exhausted:TCompilerIrExpression = FusionBinary("<=", take, FusionIntLiteral(0, source), source)
			If result Then result = FusionBinary("or", result, exhausted, source) Else result = exhausted
		Next
		Return result
	End Function

	Function FusionStopOrContinue:TCompilerIrStatement[](takes:TCompilerIrSymbolReference[], loop:TCompilerIrForEachArray, source:TCompilerSourceLocation)
		loop.hasContinue = True
		Local continued:TCompilerIrStatement = FusionLoopControl(IR_LOOP_CONTROL_CONTINUE, loop.loopId, source)
		If Not takes.length Then Return [continued]
		loop.hasExit = True
		Local stopped:TCompilerIrStatement = FusionLoopControl(IR_LOOP_CONTROL_EXIT, loop.loopId, source)
		Return [FusionIf(FusionAnyTakeExhausted(takes, source), [stopped], [continued], source)]
	End Function

	Method FusionTerminalDefault:TCompilerIrExpression(plan:TCompilerSequenceFusionPlan, accumulator:TCompilerIrSymbolReference, outputArray:TCompilerIrSymbolReference, source:TCompilerSourceLocation)
		Select plan.terminalKind
			Case SEQUENCE_FUSION_FOLD, SEQUENCE_FUSION_COUNT, SEQUENCE_FUSION_LAST_OR_NONE
				Return accumulator
			Case SEQUENCE_FUSION_ALL
				Return FusionIntLiteral(1, source)
			Case SEQUENCE_FUSION_FIRST_OR_NONE
				Return StructDefault(plan.resultType, source, plan.source.syntax)
			Case SEQUENCE_FUSION_FOR_EACH
				Return Null
			Case SEQUENCE_FUSION_TO_ARRAY
				Return FusionArraySlice(outputArray, accumulator, TArraySemanticType(plan.resultType), source)
			Default
				Return FusionIntLiteral(0, source)
		End Select
	End Method

	Function FusionFinalElementType:TSemanticType(plan:TCompilerSequenceFusionPlan)
		If Not plan Then Return Null
		If plan.stages.length Then Return plan.stages[plan.stages.length - 1].outputType
		Return plan.sourceElementType
	End Function

	Method FusionImportedStructTypeFunction:TCompilerIrImportedStructRoutine(semanticType:TSemanticType, name:String, parameterType:String)
		Local importedStruct:TCompilerIrImportedStruct = ImportedStructForType(semanticType)
		If Not importedStruct Then Return Null
		Local match:TCompilerIrImportedStructRoutine
		For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
			If routine.isMethod Or routine.isConstructor Or routine.name.ToLower() <> name.ToLower() Or routine.parameters.length <> 1 Then Continue
			If routine.returnType.ToLower() <> TypeName(semanticType).ToLower() Or routine.parameters[0].semanticType.ToLower() <> parameterType.ToLower() Then Continue
			If match Then Return Null
			match = routine
		Next
		Return match
	End Method

	Function FusionImportedStructTypeFunctionCall:TCompilerIrCall(routine:TCompilerIrImportedStructRoutine, semanticType:TSemanticType, arguments:TCompilerIrExpression[], source:TCompilerSourceLocation)
		If Not routine Then Return Null
		Local call:TCompilerIrCall = New TCompilerIrCall
		call.kind = IR_EXPRESSION_CALL
		call.semanticType = TypeName(semanticType)
		call.source = source
		call.functionId = routine.routineId
		call.functionName = routine.name
		call.isExternal = True
		call.dispatchKind = IR_CALL_DISPATCH_DIRECT
		call.arguments = arguments
		Return call
	End Function

	Method LowerExpression:TCompilerIrExpression(bound:TBoundExpression)
		If Not bound Then Return Null
		Local supportedStaticStorage:Int = StaticArrayTypeOf(bound) And (TBoundSymbolExpression(bound) Or TBoundMemberExpression(bound))
		Local routineReference:TBoundRoutineReferenceExpression = TBoundRoutineReferenceExpression(bound)
		Local functionLiteral:TBoundFunctionLiteralExpression = TBoundFunctionLiteralExpression(bound)
		Local callableStorageReference:Int = IsCallableStorageReference(bound)
		Local addressUnary:TBoundUnaryExpression = TBoundUnaryExpression(bound)
		Local callableStorageAddress:Int = addressUnary And addressUnary.operatorText.ToLower() = "varptr" And IsCallableStorageReference(addressUnary.operand)
		Local callableDefaultConversion:TBoundConversionExpression = TBoundConversionExpression(bound)
		If callableDefaultConversion And (callableDefaultConversion.conversionKind <> CONVERSION_DEFAULT_VALUE Or Not TCallableSemanticType(bound.semanticType)) Then callableDefaultConversion = Null
		Local supportedCallableValue:Int = TCallableSemanticType(bound.semanticType) And IsSupportedCallableType(TCallableSemanticType(bound.semanticType))
		Local supportedClosureValue:Int = IsSupportedClosureType(TClosureSemanticType(bound.semanticType))
		If Not IsSupportedValueType(bound.semanticType) And Not supportedCallableValue And Not supportedClosureValue And Not supportedStaticStorage And Not routineReference And Not functionLiteral And Not callableStorageReference And Not callableStorageAddress And Not callableDefaultConversion And Not (IsVoidType(bound.semanticType) And TBoundCallExpression(bound)) Then
			AddUnsupported("BMXC1010", "Expression type '" + TypeName(bound.semanticType) + "' is outside the scalar IR slice", bound.syntax)
			Return Null
		End If

		If routineReference Then Return LowerCallableReference(routineReference)
		If functionLiteral Then Return LowerFunctionLiteral(functionLiteral)
		If callableDefaultConversion Then Return CallableDefault(TCallableSemanticType(bound.semanticType), SourceOf(bound.syntax))

		Local literal:TBoundLiteralExpression = TBoundLiteralExpression(bound)
		If literal Then
			Local canonicalConstant:Int = literal.token And (literal.token.text.ToLower() = "pi" Or (literal.token.kind = TOKEN_INTEGER_LITERAL And literal.token.text.StartsWith("%")))
			If canonicalConstant Then
				Local literalSyntax:TExpressionSyntax = TExpressionSyntax(bound.syntax)
				Local constantValue:TConstantValue
				If literalSyntax Then constantValue = TConstantEvaluator.EvaluateExpressionValue(analysis.model, literalSyntax)
				If constantValue Then
					TConstantEvaluator.NormalizeRadixOperand(constantValue)
					Return LowerConstantDefault(constantValue, bound.semanticType, Null, bound.syntax)
				End If
			End If
			Local resultLiteral:TCompilerIrLiteral = New TCompilerIrLiteral
			InitializeExpression(resultLiteral, IR_EXPRESSION_LITERAL, bound)
			If literal.token Then
				resultLiteral.text = literal.token.text
				If IsStringType(bound.semanticType) Then resultLiteral.stringLiteralId = RegisterStringLiteral(literal.token, bound.syntax).literalId
			End If
			Return resultLiteral
		End If

		Local arrayLiteral:TBoundArrayLiteralExpression = TBoundArrayLiteralExpression(bound)
		If arrayLiteral Then
			Local arrayType:TArraySemanticType = TArraySemanticType(bound.semanticType)
			If Not arrayType Or arrayType.rank <> 1 Then
				AddUnsupported("BMXC1135", "Only one-dimensional array literals are implemented", bound.syntax)
				Return Null
			End If
			If Not IsSupportedArrayElementType(arrayType.elementType) Then
				AddUnsupported("BMXC1132", "Array element type '" + TypeName(arrayType.elementType) + "' is not implemented", bound.syntax)
				Return Null
			End If
			If Not arrayLiteral.elements.length Then Return ManagedDefault(TypeName(bound.semanticType), IR_MANAGED_REFERENCE_ARRAY, SourceOf(bound.syntax))
			Local resultLiteral:TCompilerIrArrayLiteral = New TCompilerIrArrayLiteral
			InitializeExpression(resultLiteral, IR_EXPRESSION_ARRAY_LITERAL, bound)
			resultLiteral.elementType = TypeName(arrayType.elementType)
			resultLiteral.elementEncoding = ArrayElementEncoding(arrayType.elementType)
			Local literalCallable:TCallableSemanticType = TCallableSemanticType(arrayType.elementType)
			If literalCallable Then
				resultLiteral.callableReturnType = TypeName(literalCallable.returnType)
				resultLiteral.callableParameters = CallableParameters(literalCallable)
				resultLiteral.callableCallingConvention = literalCallable.callingConvention
			End If
			Local literalEnum:TCompilerIrEnum = EnumForType(arrayType.elementType)
			If literalEnum Then resultLiteral.enumId = literalEnum.enumId
			Local literalStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
			Local literalImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
			If literalStruct Then resultLiteral.structId = literalStruct.structId
			If literalImportedStruct Then resultLiteral.importedStructId = literalImportedStruct.importedStructId
			resultLiteral.elements = New TCompilerIrExpression[arrayLiteral.elements.length]
			For Local index:Int = 0 Until arrayLiteral.elements.length
				resultLiteral.elements[index] = LowerExpression(arrayLiteral.elements[index])
				If Not resultLiteral.elements[index] Then Return Null
			Next
			Local result:TCompilerIrExpression = resultLiteral
			' C does not define initializer-expression order. Make the language's
			' left-to-right evaluation order explicit in shared IR before the backend.
			Local materializations:TCompilerIrMaterialize[] = New TCompilerIrMaterialize[resultLiteral.elements.length]
			For Local index:Int = 0 Until resultLiteral.elements.length
				materializations[index] = BeginMaterialization(resultLiteral.elements[index], arrayLiteral.elements[index].syntax)
				If literalCallable Then
					materializations[index].temporaryCallableReturnType = resultLiteral.callableReturnType
					materializations[index].temporaryCallableParameters = resultLiteral.callableParameters
					materializations[index].temporaryCallableCallingConvention = resultLiteral.callableCallingConvention
				End If
				resultLiteral.elements[index] = TemporaryReference(materializations[index], arrayLiteral.elements[index], arrayLiteral.elements[index].syntax, "element")
			Next
			For Local index:Int = resultLiteral.elements.length - 1 To 0 Step -1
				Local materialization:TCompilerIrMaterialize = materializations[index]
				materialization.expression = result
				materialization.semanticType = TypeName(bound.semanticType)
				result = materialization
			Next
			Return result
		End If

		Local selfExpression:TBoundSelfExpression = TBoundSelfExpression(bound)
		If selfExpression Then
			If currentRoutine And currentRoutine.isClosureInvoke Then
				Local selfPlan:TCompilerClosureCapturePlan = CaptureSelfPlan(currentIncomingClosureCapturePlan)
				If selfPlan Then Return CaptureSelfFieldAccess(selfPlan, SourceOf(bound.syntax))
			End If
			If Not currentReceiver Then
				AddUnsupported("BMXC1151", "Self is only available while lowering an instance method", bound.syntax)
				Return Null
			End If
			Local selfReference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
			InitializeExpression(selfReference, IR_EXPRESSION_SYMBOL, bound)
			selfReference.symbolId = currentReceiver.symbolId
			selfReference.name = currentReceiver.name
			selfReference.isByReference = currentReceiver.passingMode = PARAMETER_PASS_VAR
			Return selfReference
		End If

		Local symbol:TBoundSymbolExpression = TBoundSymbolExpression(bound)
		If symbol Then
			If symbol.symbol And symbol.symbol.kind = SYMBOL_FIELD And symbol.receiver Then Return LowerFieldAccess(symbol.receiver, symbol.symbol, bound)
			Return LowerStorageSymbol(symbol.symbol, bound)
		End If

		Local member:TBoundMemberExpression = TBoundMemberExpression(bound)
		If member And member.access And member.access.member And member.access.member.kind = SYMBOL_ENUM_MEMBER Then
			Local enumConstant:TConstantValue = analysis.model.SymbolConstantValue(member.access.member)
			If enumConstant Then Return LowerConstantDefault(enumConstant, member.access.member.declaredType, member.access.member, bound.syntax)
		End If
		If member And member.access And member.access.member And (member.access.member.kind = SYMBOL_GLOBAL Or member.access.member.kind = SYMBOL_CONST) Then
			Local specializationStatic:TCompilerIrExpression = LowerGenericStaticGlobal(member.access, bound)
			Local staticValue:TCompilerIrExpression = specializationStatic
			If Not staticValue Then staticValue = LowerStorageSymbol(member.access.member, bound)
			If Not staticValue Or Not member.receiver Or IsStaticMemberQualifier(member.receiver) Then Return staticValue
			Local loweredQualifier:TCompilerIrExpression = LowerExpression(member.receiver)
			If Not loweredQualifier Then Return Null
			Local qualifierMaterialization:TCompilerIrMaterialize = BeginMaterialization(loweredQualifier, member.receiver.syntax)
			qualifierMaterialization.expression = staticValue
			qualifierMaterialization.semanticType = staticValue.semanticType
			Return qualifierMaterialization
		End If
		If member And StaticArrayTypeOf(member.receiver) Then
			Local staticMemberType:TStaticArraySemanticType = StaticArrayTypeOf(member.receiver)
			If member.access And member.access.member And member.access.member.name.ToLower() = "length" Then
				Local staticLength:TCompilerIrLiteral = New TCompilerIrLiteral
				InitializeExpression(staticLength, IR_EXPRESSION_LITERAL, bound)
				staticLength.text = String(staticMemberType.length)
				Return staticLength
			End If
			AddUnsupported("BMXC1134", "StaticArray member lowering currently supports only length", bound.syntax)
			Return Null
		End If
		If member And IsStringType(member.receiver.semanticType) Then
			If member.access And member.access.member And member.access.member.name.ToLower() = "length" Then
				Local stringLength:TCompilerIrStringLength = New TCompilerIrStringLength
				InitializeExpression(stringLength, IR_EXPRESSION_STRING_LENGTH, bound)
				stringLength.receiver = LowerExpression(member.receiver)
				Return stringLength
			End If
		End If
		If member And Not IsArrayType(member.receiver.semanticType) And member.access And member.access.member And member.access.member.kind = SYMBOL_FIELD Then
			Return LowerFieldAccess(member.receiver, member.access.member, bound)
		End If
		If member And IsArrayType(member.receiver.semanticType) Then
			If member.access And member.access.member And member.access.member.name.ToLower() = "length" Then
				Local arrayLength:TCompilerIrArrayLength = New TCompilerIrArrayLength
				InitializeExpression(arrayLength, IR_EXPRESSION_ARRAY_LENGTH, bound)
				arrayLength.receiver = LowerExpression(member.receiver)
				Return arrayLength
			End If
			AddUnsupported("BMXC1130", "Array member lowering currently supports only length", bound.syntax)
			Return Null
		End If

		Local indexed:TBoundIndexExpression = TBoundIndexExpression(bound)
		If indexed And indexed.access And indexed.access.accessKind = INDEX_ACCESS_OPERATOR And indexed.access.resolvedCall Then
			Local indexCall:TBoundCallExpression = New TBoundCallExpression
			indexCall.boundKind = BOUND_EXPRESSION_CALL
			indexCall.syntax = indexed.syntax
			indexCall.semanticType = indexed.access.resultType
			indexCall.isSynthetic = True
			indexCall.resolvedCall = indexed.access.resolvedCall
			indexCall.receiver = indexed.receiver
			indexCall.arguments = indexed.indexes
			Return LowerExpression(indexCall)
		End If
		If indexed And indexed.access And (indexed.access.accessKind = INDEX_ACCESS_RANGE_STRING Or indexed.access.accessKind = INDEX_ACCESS_RANGE_ARRAY) Then
			Return LowerRangeIndexSlice(indexed, bound)
		End If
		If indexed And indexed.access And indexed.access.accessKind = INDEX_ACCESS_STRING Then
			If indexed.indexes.length <> 1 Then
				AddUnsupported("BMXC1123", "String indexing requires one integral index", bound.syntax)
				Return Null
			End If
			Local stringElement:TCompilerIrStringElement = New TCompilerIrStringElement
			InitializeExpression(stringElement, IR_EXPRESSION_STRING_ELEMENT, bound)
			stringElement.receiver = LowerExpression(indexed.receiver)
			stringElement.index = LowerExpression(indexed.indexes[0])
			If options And options.debugInstrumentation Then
				stringElement.boundsCheck = True
				result.hasDebugBoundsChecks = True
			End If
			Return stringElement
		End If
		If indexed And indexed.access And indexed.access.accessKind = INDEX_ACCESS_POINTER Then
			Local pointerType:TPointerSemanticType = TPointerSemanticType(indexed.receiver.semanticType)
			If Not pointerType Or indexed.indexes.length <> 1 Or IsVoidType(pointerType.elementType) Or Not IsSupportedPointerElementType(pointerType.elementType) Then
				AddUnsupported("BMXC1206", "Raw pointer indexing requires one integral index and a supported non-Void element type", bound.syntax)
				Return Null
			End If
			Local pointerElement:TCompilerIrPointerElement = New TCompilerIrPointerElement
			InitializeExpression(pointerElement, IR_EXPRESSION_POINTER_ELEMENT, bound)
			pointerElement.receiver = LowerExpression(indexed.receiver)
			pointerElement.index = LowerExpression(indexed.indexes[0])
			pointerElement.elementType = TypeName(pointerType.elementType)
			Local pointerStruct:TCompilerIrStruct = StructForType(pointerType.elementType)
			Local pointerImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(pointerType.elementType)
			If pointerStruct Then pointerElement.structId = pointerStruct.structId
			If pointerImportedStruct Then pointerElement.importedStructId = pointerImportedStruct.importedStructId
			If options And options.debugInstrumentation Then
				pointerElement.nullCheck = True
				result.hasDebugPointerChecks = True
			End If
			Return pointerElement
		End If
		If indexed And indexed.access And indexed.access.accessKind = INDEX_ACCESS_STATIC_ARRAY Then
			Local staticIndexedType:TStaticArraySemanticType = StaticArrayTypeOf(indexed.receiver)
			If Not IsSupportedStaticArrayType(staticIndexedType) Or indexed.indexes.length <> 1 Then
				AddUnsupported("BMXC1135", "Only one-dimensional supported StaticArray indexing is implemented", bound.syntax)
				Return Null
			End If
			Local staticElement:TCompilerIrArrayElement = New TCompilerIrArrayElement
			InitializeExpression(staticElement, IR_EXPRESSION_ARRAY_ELEMENT, bound)
			staticElement.receiver = LowerExpression(indexed.receiver)
			staticElement.indexes = [LowerExpression(indexed.indexes[0])]
			staticElement.elementType = TypeName(staticIndexedType.elementType)
			Local staticElementStruct:TCompilerIrStruct = StructForType(staticIndexedType.elementType)
			Local staticElementImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(staticIndexedType.elementType)
			If staticElementStruct Then staticElement.structId = staticElementStruct.structId
			If staticElementImportedStruct Then staticElement.importedStructId = staticElementImportedStruct.importedStructId
			staticElement.rank = 1
			staticElement.isStaticArray = True
			If options And options.debugInstrumentation Then
				staticElement.boundsCheckKind = IR_BOUNDS_CHECK_STATIC_ARRAY
				staticElement.boundsLength = staticIndexedType.length
				result.hasDebugBoundsChecks = True
			End If
			Return staticElement
		End If
		If indexed And indexed.access And indexed.access.accessKind = INDEX_ACCESS_ARRAY Then
			Local arrayType:TArraySemanticType = TArraySemanticType(indexed.receiver.semanticType)
			If Not arrayType Or arrayType.rank <= 0 Or indexed.indexes.length <> arrayType.rank Then
				AddUnsupported("BMXC1131", "Heap-array indexing requires one index per declared rank", bound.syntax)
				Return Null
			End If
			If Not IsSupportedArrayElementType(arrayType.elementType) Then
				AddUnsupported("BMXC1132", "Array element type '" + TypeName(arrayType.elementType) + "' is not implemented", bound.syntax)
				Return Null
			End If
			Local element:TCompilerIrArrayElement = New TCompilerIrArrayElement
			InitializeExpression(element, IR_EXPRESSION_ARRAY_ELEMENT, bound)
			element.receiver = LowerExpression(indexed.receiver)
			element.indexes = New TCompilerIrExpression[indexed.indexes.length]
			For Local arrayIndex:Int = 0 Until indexed.indexes.length
				element.indexes[arrayIndex] = LowerExpression(indexed.indexes[arrayIndex])
				If Not element.indexes[arrayIndex] Then Return Null
			Next
			element.elementType = TypeName(arrayType.elementType)
			Local elementCallable:TCallableSemanticType = TCallableSemanticType(arrayType.elementType)
			If elementCallable Then
				element.callableReturnType = TypeName(elementCallable.returnType)
				element.callableParameters = CallableParameters(elementCallable)
				element.callableCallingConvention = elementCallable.callingConvention
			End If
			Local elementStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
			Local elementImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
			If elementStruct Then element.structId = elementStruct.structId
			If elementImportedStruct Then element.importedStructId = elementImportedStruct.importedStructId
			element.rank = arrayType.rank
			If options And options.debugInstrumentation Then
				element.boundsCheckKind = IR_BOUNDS_CHECK_DYNAMIC_ARRAY
				result.hasDebugBoundsChecks = True
			End If
			If arrayType.rank > 1 And Not IsStableReceiver(element.receiver) Then
				Local arrayReceiver:TCompilerIrMaterialize = BeginMaterialization(element.receiver, indexed.receiver.syntax)
				element.receiver = TemporaryReference(arrayReceiver, indexed.receiver, indexed.receiver.syntax)
				arrayReceiver.expression = element
				arrayReceiver.semanticType = TypeName(bound.semanticType)
				Return arrayReceiver
			End If
			Return element
		End If

		Local slice:TBoundSliceExpression = TBoundSliceExpression(bound)
		If slice Then
			Local sliceArrayType:TArraySemanticType = TArraySemanticType(slice.receiver.semanticType)
			Local sliceStruct:TCompilerIrStruct
			Local sliceImportedStruct:TCompilerIrImportedStruct
			If sliceArrayType Then
				sliceStruct = StructForType(sliceArrayType.elementType)
				sliceImportedStruct = ImportedStructForType(sliceArrayType.elementType)
			End If
			If sliceArrayType And sliceArrayType.rank = 1 And IsSupportedArrayElementType(sliceArrayType.elementType) Then
				Local arraySlice:TCompilerIrArraySlice = New TCompilerIrArraySlice
				InitializeExpression(arraySlice, IR_EXPRESSION_ARRAY_SLICE, bound)
				arraySlice.elementType = TypeName(sliceArrayType.elementType)
				arraySlice.elementEncoding = ArrayElementEncoding(sliceArrayType.elementType)
				If sliceStruct Then
					arraySlice.structId = sliceStruct.structId
					sliceStruct.arrayInitializerRequired = True
				End If
				If sliceImportedStruct Then arraySlice.importedStructId = sliceImportedStruct.importedStructId
				Local loweredArrayReceiver:TCompilerIrExpression = LowerExpression(slice.receiver)
				If Not loweredArrayReceiver Then Return Null
				arraySlice.receiver = loweredArrayReceiver
				If slice.lowerBound Then arraySlice.lowerBound = LowerExpression(slice.lowerBound) Else arraySlice.lowerBound = ScalarDefault("Int", SourceOf(bound.syntax))
				If Not arraySlice.lowerBound Then Return Null
				If slice.upperBound Then
					arraySlice.upperBound = LowerExpression(slice.upperBound)
					If Not arraySlice.upperBound Then Return Null
				Else
					arraySlice.upperBoundOmitted = True
				End If
				arraySlice.lowerFromEnd = slice.lowerFromEnd
				arraySlice.upperFromEnd = slice.upperFromEnd
				If IsStableReceiver(loweredArrayReceiver) Then Return arraySlice
				Local arrayReceiver:TCompilerIrMaterialize = BeginMaterialization(loweredArrayReceiver, slice.receiver.syntax)
				arraySlice.receiver = TemporaryReference(arrayReceiver, slice.receiver, slice.receiver.syntax)
				arrayReceiver.expression = arraySlice
				arrayReceiver.semanticType = TypeName(bound.semanticType)
				Return arrayReceiver
			End If
			If Not IsStringType(slice.receiver.semanticType) Then
				AddUnsupported("BMXC1210", "Slice receiver type '" + TypeName(slice.receiver.semanticType) + "' is outside the String and one-dimensional heap Array slice", bound.syntax)
				Return Null
			End If
			Local stringSlice:TCompilerIrStringSlice = New TCompilerIrStringSlice
			InitializeExpression(stringSlice, IR_EXPRESSION_STRING_SLICE, bound)
			Local loweredReceiver:TCompilerIrExpression = LowerExpression(slice.receiver)
			If Not loweredReceiver Then Return Null
			stringSlice.receiver = loweredReceiver
			If slice.lowerBound Then
				stringSlice.lowerBound = LowerExpression(slice.lowerBound)
			Else
				stringSlice.lowerBound = ScalarDefault("Int", SourceOf(bound.syntax))
			End If
			If Not stringSlice.lowerBound Then Return Null
			If slice.upperBound Then
				stringSlice.upperBound = LowerExpression(slice.upperBound)
				If Not stringSlice.upperBound Then Return Null
			Else
				stringSlice.upperBoundOmitted = True
			End If
			stringSlice.lowerFromEnd = slice.lowerFromEnd
			stringSlice.upperFromEnd = slice.upperFromEnd
			If IsStableReceiver(loweredReceiver) Then Return stringSlice

			' An omitted or from-end bound reads the receiver length as well as passing
			' the receiver to bbStringSlice. Preserve BlitzMax's single evaluation
			' rule explicitly in IR rather than relying on backend expression text.
			Local sliceReceiver:TCompilerIrMaterialize = BeginMaterialization(loweredReceiver, slice.receiver.syntax)
			stringSlice.receiver = TemporaryReference(sliceReceiver, slice.receiver, slice.receiver.syntax)
			sliceReceiver.expression = stringSlice
			sliceReceiver.semanticType = TypeName(bound.semanticType)
			Return sliceReceiver
		End If

		Local call:TBoundCallExpression = TBoundCallExpression(bound)
		If call Then
			Local fusedSequence:TCompilerIrExpression = TryLowerSequenceTerminal(call, bound)
			If fusedSequence Then Return fusedSequence
			If call.resolvedCall And Not call.resolvedCall.routine And (TCallableSemanticType(call.callee.semanticType) Or TClosureSemanticType(call.callee.semanticType)) Then Return LowerIndirectCall(call, bound)
			Local enumIntrinsic:TCompilerIrExpression = LowerEnumIntrinsicCall(call, bound)
			If enumIntrinsic Then Return enumIntrinsic
			Local superReceiver:TBoundSelfExpression = TBoundSelfExpression(call.receiver)
			Local isSuperCall:Int = superReceiver And superReceiver.isSuper
			Local receiverInterface:TCompilerIrInterface
			If call.receiver Then receiverInterface = InterfaceForType(call.receiver.semanticType)
			Local interfaceMethod:TCompilerIrInterfaceMethod
			If call.resolvedCall And receiverInterface Then
				Local methodMap:TMap = TMap(interfaceMethodsByInterface.ValueForKey(receiverInterface))
				If methodMap Then interfaceMethod = TCompilerIrInterfaceMethod(methodMap.ValueForKey(call.resolvedCall.routine))
				If Not interfaceMethod And call.resolvedCall.routine Then
					For Local candidate:TCompilerIrInterfaceMethod = EachIn receiverInterface.methods
						If candidate.name.ToLower() = call.resolvedCall.routine.name.ToLower() Then interfaceMethod = candidate; Exit
					Next
				End If
				' A closed generic Interface can inherit an ordinary Interface whose
				' method table remains independently owned. Dispatch an inherited
				' selector through that declaring Interface rather than requiring the
				' generic specialization to republish the ordinary table layout.
				If Not interfaceMethod And call.resolvedCall.routine And call.resolvedCall.routine.containingScope Then
					Local declaringInterfaceSymbol:TSymbol = call.resolvedCall.routine.containingScope.owner
					If declaringInterfaceSymbol And declaringInterfaceSymbol.kind = SYMBOL_INTERFACE And Not declaringInterfaceSymbol.genericArity Then
						Local declaringInterface:TCompilerIrInterface = EnsureInterfaceShell(declaringInterfaceSymbol)
						If declaringInterface Then
							Local declaringMethodMap:TMap = TMap(interfaceMethodsByInterface.ValueForKey(declaringInterface))
							If declaringMethodMap Then interfaceMethod = TCompilerIrInterfaceMethod(declaringMethodMap.ValueForKey(call.resolvedCall.routine))
							If Not interfaceMethod Then
								For Local candidate:TCompilerIrInterfaceMethod = EachIn declaringInterface.methods
									If candidate.name.ToLower() = call.resolvedCall.routine.name.ToLower() Then interfaceMethod = candidate; Exit
								Next
							End If
							If interfaceMethod Then receiverInterface = declaringInterface
						End If
					End If
				End If
			End If
			If interfaceMethod Then
				If isSuperCall And superReceiver.qualifiedSuperType Then Return LowerInterfaceSuperCall(call, receiverInterface, interfaceMethod, bound)
				Return LowerInterfaceCall(call, receiverInterface, interfaceMethod, bound)
			End If
			Local target:TCompilerIrFunction
			Local externalTarget:TCompilerIrExternalFunction
			Local importedTarget:TCompilerIrImportedMethod
			Local importedStructTarget:TCompilerIrImportedStructRoutine
			Local importedObjectSlotKind:Int
			Local sourceRequirementSlot:TCompilerIrClassFunctionSlot
			If call.resolvedCall Then
				target = TCompilerIrFunction(functionsBySymbol.ValueForKey(call.resolvedCall.routine))
				If Not target And call.receiver Then
					Local sourceRequirementClass:TCompilerIrClass = ClassForType(call.receiver.semanticType)
					If sourceRequirementClass Then
						sourceRequirementSlot = ClassRequirementSlot(sourceRequirementClass, call.resolvedCall.routine)
						If sourceRequirementSlot Then target = FunctionById(sourceRequirementSlot.functionId)
					End If
				End If
				If Not target Then externalTarget = GenericRoutineFunction(call)
				Local resolvedOwner:TSymbol
				If call.resolvedCall.routine And call.resolvedCall.routine.containingScope Then resolvedOwner = call.resolvedCall.routine.containingScope.owner
				If Not target And Not externalTarget And call.receiver And (IsStringType(call.receiver.semanticType) Or IsArrayType(call.receiver.semanticType)) Then externalTarget = ImportedDirectMethod(call.resolvedCall.routine, call.receiver.semanticType, bound.syntax)
				If Not target And Not externalTarget And resolvedOwner And resolvedOwner.kind = SYMBOL_STRUCT Then
					Local genericReceiverStruct:TCompilerIrImportedStruct
					If call.receiver Then genericReceiverStruct = TCompilerIrImportedStruct(genericStructsByTypeName.ValueForKey(TypeName(call.receiver.semanticType).ToLower()))
					If Not genericReceiverStruct And call.staticReceiverType Then genericReceiverStruct = TCompilerIrImportedStruct(genericStructsByTypeName.ValueForKey(TypeName(call.staticReceiverType).ToLower()))
					If genericReceiverStruct Then
						importedStructTarget = GenericImportedStructRoutine(genericReceiverStruct, call.resolvedCall.routine)
					Else If resolvedOwner.isImported Then
						importedStructTarget = ImportedStructRoutine(call.resolvedCall.routine, bound.syntax)
					End If
				End If
				If Not target And Not externalTarget And call.receiver And IsObjectReferenceType(call.receiver.semanticType) Then importedObjectSlotKind = ObjectSlotKind(call.resolvedCall.routine)
				If Not target And Not externalTarget And isSuperCall And importedObjectSlotKind <> IR_OBJECT_SLOT_NONE Then
					' Reserved Object slots are virtual for ordinary receiver
					' calls, but Super selects the bound base implementation.
					externalTarget = ImportedDirectMethod(call.resolvedCall.routine, call.receiver.semanticType, bound.syntax, True)
					If externalTarget Then importedObjectSlotKind = IR_OBJECT_SLOT_NONE
				End If
				If Not target And Not externalTarget And Not importedStructTarget And importedObjectSlotKind = IR_OBJECT_SLOT_NONE And call.receiver Then
					Local genericReceiverClass:TCompilerIrImportedClass = ImportedClassForType(call.receiver.semanticType)
					If Not genericReceiverClass Or Not genericReceiverClass.isGenericSpecialization Then genericReceiverClass = GenericImportedBaseForType(call.receiver.semanticType, resolvedOwner)
					If genericReceiverClass And genericReceiverClass.isGenericSpecialization Then
						importedTarget = GenericImportedMethodForCall(genericReceiverClass, call.resolvedCall)
					Else
						importedTarget = ImportedMethod(call.resolvedCall.routine, bound.syntax)
					End If
				End If
				If Not target And Not externalTarget And Not importedStructTarget And importedObjectSlotKind = IR_OBJECT_SLOT_NONE And Not importedTarget And call.staticReceiverType Then
					Local genericStaticClass:TCompilerIrImportedClass = ImportedClassForType(call.staticReceiverType)
					If genericStaticClass And genericStaticClass.isGenericSpecialization Then importedTarget = GenericImportedMethodForCall(genericStaticClass, call.resolvedCall)
				End If
				If Not target And Not importedStructTarget And importedObjectSlotKind = IR_OBJECT_SLOT_NONE And Not importedTarget And Not externalTarget Then externalTarget = ExternalFunction(call.resolvedCall.routine, bound.syntax)
			End If
			If Not target And Not importedStructTarget And importedObjectSlotKind = IR_OBJECT_SLOT_NONE And Not importedTarget And Not externalTarget Then
				If isSuperCall Then
					AddUnsupported("BMXC1152", "Super method dispatch currently requires a lowered source base implementation", bound.syntax)
					Return Null
				End If
				Local unresolvedCallName:String = "<unresolved>"
				If call.resolvedCall And call.resolvedCall.routine Then unresolvedCallName = call.resolvedCall.routine.QualifiedName()
				Local unresolvedReceiverType:String = "<none>"
				If call.receiver And call.receiver.semanticType Then unresolvedReceiverType = TypeName(call.receiver.semanticType)
				AddUnsupported("BMXC1012", "Call target '" + unresolvedCallName + "' on receiver type '" + unresolvedReceiverType + "' is not implemented", bound.syntax)
				Return Null
			End If
			If target And target.lifecycleKind <> IR_LIFECYCLE_NONE Then
				AddUnsupported("BMXC1153", "Constructor delegation and direct destructor calls require dedicated lifecycle operations", bound.syntax)
				Return Null
			End If
			Local resultCall:TCompilerIrCall = New TCompilerIrCall
			InitializeExpression(resultCall, IR_EXPRESSION_CALL, bound)
			Local receiverMaterialization:TCompilerIrMaterialize
			If target Then
				resultCall.functionId = target.functionId
				resultCall.functionName = target.name
				If call.receiver And Not target.isMethod And target.ownerClassId.length Then
					Local receiverClass:TCompilerIrClass = ClassForType(call.receiver.semanticType)
					If Not receiverClass Or Not target.classSlotId.length Then
						AddUnsupported("BMXC1150", "Object-qualified Type Function call has no source class-table slot", bound.syntax)
						Return Null
					End If
					resultCall.dispatchKind = IR_CALL_DISPATCH_TYPE_FUNCTION
					resultCall.classId = receiverClass.classId
					resultCall.classSlotId = target.classSlotId
					Local loweredTypeFunctionReceiver:TCompilerIrExpression = LowerExpression(call.receiver)
					If Not loweredTypeFunctionReceiver Then Return Null
					If IsStableReceiver(loweredTypeFunctionReceiver) Then
						resultCall.receiver = loweredTypeFunctionReceiver
					Else
						receiverMaterialization = BeginMaterialization(loweredTypeFunctionReceiver, bound.syntax)
						resultCall.receiver = TemporaryReference(receiverMaterialization, call.receiver, bound.syntax)
					End If
				Else If isSuperCall Then
					If Not target.isMethod Then
						AddUnsupported("BMXC1152", "Super dispatch requires an instance method", bound.syntax)
						Return Null
					End If
					Local dispatchClass:TCompilerIrClass = ActiveSuperDispatchClass()
					If Not dispatchClass Or Not dispatchClass.baseClassId.length Then
						AddUnsupported("BMXC1152", "Super dispatch class does not have a lowered source base layout", bound.syntax)
						Return Null
					End If
					resultCall.dispatchKind = IR_CALL_DISPATCH_SUPER
					resultCall.receiver = LowerExpression(call.receiver)
					If Not resultCall.receiver Then Return Null
					resultCall.classId = dispatchClass.classId
					resultCall.classSlotId = target.classSlotId
					resultCall.objectSlotKind = target.objectSlotKind
				Else If target.isMethod Then
					If Not call.receiver Then
						AddUnsupported("BMXC1150", "Method call did not retain its bound receiver", bound.syntax)
						Return Null
					End If
					Local previousPreserveStructReceiver:Int = preserveStructLValue
					If target.ownerStructId.length Then preserveStructLValue = True
					Local loweredReceiver:TCompilerIrExpression = LowerExpression(call.receiver)
					preserveStructLValue = previousPreserveStructReceiver
					If Not loweredReceiver Then Return Null
					If target.ownerStructId.length Then
						resultCall.dispatchKind = IR_CALL_DISPATCH_STRUCT
						Local address:TCompilerIrAddressOf = New TCompilerIrAddressOf
						address.kind = IR_EXPRESSION_ADDRESS_OF
						address.semanticType = loweredReceiver.semanticType
						address.source = loweredReceiver.source
						If IsAddressableExpression(loweredReceiver) Then
							address.operand = loweredReceiver
							resultCall.receiver = address
						Else
							receiverMaterialization = BeginMaterialization(loweredReceiver, bound.syntax)
							address.operand = TemporaryReference(receiverMaterialization, call.receiver, bound.syntax)
							resultCall.receiver = address
						End If
					Else
						Local receiverClass:TCompilerIrClass = ClassForType(call.receiver.semanticType)
						If options And options.targetPlatform.ToLower() = "pico" And (target.isFinal Or (receiverClass And receiverClass.isFinal)) Then
							resultCall.dispatchKind = IR_CALL_DISPATCH_EXACT
						Else
							resultCall.dispatchKind = IR_CALL_DISPATCH_VIRTUAL
						End If
						If IsStableReceiver(loweredReceiver) Then
							resultCall.receiver = loweredReceiver
						Else
							receiverMaterialization = BeginMaterialization(loweredReceiver, bound.syntax)
							resultCall.receiver = TemporaryReference(receiverMaterialization, call.receiver, bound.syntax)
						End If
						If receiverClass Then resultCall.classId = receiverClass.classId Else resultCall.classId = target.ownerClassId
						If sourceRequirementSlot Then resultCall.classSlotId = sourceRequirementSlot.slotId Else resultCall.classSlotId = target.classSlotId
						resultCall.objectSlotKind = target.objectSlotKind
					End If
				End If
			Else If importedStructTarget Then
				If importedStructTarget.isConstructor Then
					AddUnsupported("BMXC1153", "Imported Struct constructors require a struct-new operation", bound.syntax)
					Return Null
				End If
				resultCall.functionId = importedStructTarget.routineId
				resultCall.functionName = importedStructTarget.name
				resultCall.isExternal = True
				If importedStructTarget.isMethod Then
					If Not call.receiver Then
						AddUnsupported("BMXC1150", "Imported Struct method call did not retain its receiver", bound.syntax)
						Return Null
					End If
					resultCall.dispatchKind = IR_CALL_DISPATCH_STRUCT
					Local previousPreserveImportedStructReceiver:Int = preserveStructLValue
					preserveStructLValue = True
					Local loweredImportedReceiver:TCompilerIrExpression = LowerExpression(call.receiver)
					preserveStructLValue = previousPreserveImportedStructReceiver
					If Not loweredImportedReceiver Then Return Null
					Local importedAddress:TCompilerIrAddressOf = New TCompilerIrAddressOf
					importedAddress.kind = IR_EXPRESSION_ADDRESS_OF
					importedAddress.semanticType = loweredImportedReceiver.semanticType
					importedAddress.source = loweredImportedReceiver.source
					If IsAddressableExpression(loweredImportedReceiver) Then
						importedAddress.operand = loweredImportedReceiver
						resultCall.receiver = importedAddress
					Else
						receiverMaterialization = BeginMaterialization(loweredImportedReceiver, bound.syntax)
						importedAddress.operand = TemporaryReference(receiverMaterialization, call.receiver, bound.syntax)
						resultCall.receiver = importedAddress
					End If
				End If
			Else If importedTarget Or importedObjectSlotKind <> IR_OBJECT_SLOT_NONE Then
				If importedTarget And importedTarget.isTypeFunction And Not call.receiver Then
					resultCall.functionId = importedTarget.methodId
					resultCall.functionName = importedTarget.name
					resultCall.isExternal = True
				Else If Not call.receiver Then
					AddUnsupported("BMXC1173", "Imported virtual method call did not retain its bound receiver", bound.syntax)
					Return Null
				Else
				Local sourceReceiverClass:TCompilerIrClass = ClassForType(call.receiver.semanticType)
				Local receiverClass:TCompilerIrImportedClass
				If Not sourceReceiverClass Then receiverClass = ImportedClassForType(call.receiver.semanticType)
				If Not sourceReceiverClass And Not receiverClass And IsBuiltinObjectType(call.receiver.semanticType) Then
					Local objectOwner:TSymbol
					If call.resolvedCall.routine.containingScope Then objectOwner = call.resolvedCall.routine.containingScope.owner
					receiverClass = EnsureImportedClass(objectOwner)
				End If
				If Not sourceReceiverClass And Not receiverClass Then
					AddUnsupported("BMXC1173", "Imported virtual method receiver type has no published class ABI", bound.syntax)
					Return Null
				End If
				If importedTarget Then
					resultCall.functionId = importedTarget.methodId
					resultCall.functionName = importedTarget.name
					If importedTarget.isTypeFunction Then
						resultCall.dispatchKind = IR_CALL_DISPATCH_TYPE_FUNCTION
						If sourceReceiverClass Then resultCall.classId = sourceReceiverClass.classId Else resultCall.classId = receiverClass.importedClassId
						resultCall.classSlotId = importedTarget.slotName
					Else If sourceReceiverClass Then
						Local inheritedSlot:TCompilerIrClassFunctionSlot = SourceClassImportedSlot(sourceReceiverClass, importedTarget)
						If Not inheritedSlot Then
							AddUnsupported("BMXC1173", "Imported method '" + importedTarget.name + "' has no inherited slot in source receiver type '" + sourceReceiverClass.semanticType + "' (declaring imported class '" + importedTarget.declaringImportedClassId + "', source imported base '" + sourceReceiverClass.baseImportedClassId + "')", bound.syntax)
							Return Null
						End If
						resultCall.classSlotId = inheritedSlot.slotId
					Else
						resultCall.classSlotId = importedTarget.methodId
					End If
				Else
					resultCall.functionName = call.resolvedCall.routine.name
					resultCall.objectSlotKind = importedObjectSlotKind
				End If
				If importedTarget And importedTarget.isTypeFunction Then
					' The class and Type Function slot were selected above.
				Else If isSuperCall Then
					If Not importedTarget Then
						AddUnsupported("BMXC1152", "Imported Super dispatch requires an exact imported base implementation", bound.syntax)
						Return Null
					End If
					resultCall.dispatchKind = IR_CALL_DISPATCH_SUPER
					resultCall.classId = importedTarget.declaringImportedClassId
					resultCall.classSlotId = importedTarget.methodId
				Else If sourceReceiverClass Then
					resultCall.dispatchKind = IR_CALL_DISPATCH_VIRTUAL
					resultCall.classId = sourceReceiverClass.classId
				Else
					resultCall.dispatchKind = IR_CALL_DISPATCH_IMPORTED_VIRTUAL
					resultCall.classId = receiverClass.importedClassId
				End If
				Local loweredReceiver:TCompilerIrExpression = LowerExpression(call.receiver)
				If Not loweredReceiver Then Return Null
				If IsStableReceiver(loweredReceiver) Then
					resultCall.receiver = loweredReceiver
				Else
					receiverMaterialization = BeginMaterialization(loweredReceiver, bound.syntax)
					resultCall.receiver = TemporaryReference(receiverMaterialization, call.receiver, bound.syntax)
				End If
				End If
			Else
				resultCall.functionId = externalTarget.functionId
				resultCall.functionName = externalTarget.sourceName
				resultCall.isExternal = True
				If call.receiver And call.resolvedCall And call.resolvedCall.routine And Not IsInstanceMethodSymbol(call.resolvedCall.routine) And call.resolvedCall.routine.containingScope And call.resolvedCall.routine.containingScope.owner And call.resolvedCall.routine.containingScope.owner.kind = SYMBOL_TYPE Then
					Local sourceTypeFunctionClass:TCompilerIrClass = ClassForType(call.receiver.semanticType)
					Local importedTypeFunctionClass:TCompilerIrImportedClass
					If Not sourceTypeFunctionClass Then importedTypeFunctionClass = ImportedClassForType(call.receiver.semanticType)
					Local typeFunctionSlot:TCompilerIrClassFunctionSlot = TCompilerIrClassFunctionSlot(slotsByRoutineSymbol.ValueForKey(call.resolvedCall.routine))
					If Not typeFunctionSlot Or typeFunctionSlot.isMethod Or (Not sourceTypeFunctionClass And Not importedTypeFunctionClass) Then
						AddUnsupported("BMXC1150", "Object-qualified imported Type Function call has no class-table slot", bound.syntax)
						Return Null
					End If
					resultCall.dispatchKind = IR_CALL_DISPATCH_TYPE_FUNCTION
					If sourceTypeFunctionClass Then resultCall.classId = sourceTypeFunctionClass.classId Else resultCall.classId = importedTypeFunctionClass.importedClassId
					resultCall.classSlotId = typeFunctionSlot.slotId
					Local loweredImportedTypeFunctionReceiver:TCompilerIrExpression = LowerExpression(call.receiver)
					If Not loweredImportedTypeFunctionReceiver Then Return Null
					If IsStableReceiver(loweredImportedTypeFunctionReceiver) Then
						resultCall.receiver = loweredImportedTypeFunctionReceiver
					Else
						receiverMaterialization = BeginMaterialization(loweredImportedTypeFunctionReceiver, bound.syntax)
						resultCall.receiver = TemporaryReference(receiverMaterialization, call.receiver, bound.syntax)
					End If
				End If
			End If
			Local argumentsSucceeded:Int
			resultCall.arguments = LowerResolvedArguments(call.arguments, call.resolvedCall.routine, bound.syntax, argumentsSucceeded, call.resolvedCall)
			If Not argumentsSucceeded Then Return Null
			If externalTarget And (externalTarget.isGenericMethod Or externalTarget.isDirectMethod) Then
				If Not call.receiver Then
					AddUnsupported("BMXC1150", "Direct or generic method call did not retain its bound receiver", bound.syntax)
					Return Null
				End If
				Local previousPreserveGenericStructReceiver:Int = preserveStructLValue
				If externalTarget.isGenericStructMethod Then preserveStructLValue = True
				Local receiverArgument:TCompilerIrExpression = LowerExpression(call.receiver)
				preserveStructLValue = previousPreserveGenericStructReceiver
				If Not receiverArgument Then Return Null
				If externalTarget.isGenericStructMethod Then
					Local receiverAddress:TCompilerIrAddressOf = New TCompilerIrAddressOf
					receiverAddress.kind = IR_EXPRESSION_ADDRESS_OF
					receiverAddress.semanticType = receiverArgument.semanticType
					receiverAddress.source = receiverArgument.source
					If IsAddressableExpression(receiverArgument) Then
						receiverAddress.operand = receiverArgument
						receiverArgument = receiverAddress
					Else
						Local genericStructMaterialization:TCompilerIrMaterialize = BeginMaterialization(receiverArgument, bound.syntax)
						receiverAddress.operand = TemporaryReference(genericStructMaterialization, call.receiver, bound.syntax)
						genericStructMaterialization.expression = resultCall
						genericStructMaterialization.semanticType = resultCall.semanticType
						receiverArgument = receiverAddress
						receiverMaterialization = genericStructMaterialization
					End If
				Else If externalTarget.parameters.length And externalTarget.parameters[0].semanticType.length And receiverArgument.semanticType.ToLower() <> externalTarget.parameters[0].semanticType.ToLower() Then
					Local genericReceiverUpcast:TCompilerIrConversion = New TCompilerIrConversion
					genericReceiverUpcast.kind = IR_EXPRESSION_CONVERSION
					genericReceiverUpcast.semanticType = externalTarget.parameters[0].semanticType
					genericReceiverUpcast.source = receiverArgument.source
					genericReceiverUpcast.conversionKind = CONVERSION_REFERENCE
					genericReceiverUpcast.implicitConversion = True
					genericReceiverUpcast.operand = receiverArgument
					receiverArgument = genericReceiverUpcast
				End If
				resultCall.arguments = [receiverArgument] + resultCall.arguments
			End If
			Local resolvedParameters:TCompilerIrParameter[]
			If externalTarget Then resolvedParameters = externalTarget.parameters
			Local sequencedCall:TCompilerIrExpression = SequenceResolvedArguments(resultCall, resultCall.arguments, call.resolvedCall.routine, bound.syntax, resolvedParameters)
			If receiverMaterialization Then
				receiverMaterialization.expression = sequencedCall
				receiverMaterialization.semanticType = resultCall.semanticType
				Return receiverMaterialization
			End If
			Return sequencedCall
		End If

		Local unary:TBoundUnaryExpression = TBoundUnaryExpression(bound)
		If unary Then
			If unary.resolvedCall Then Return LowerResolvedOperatorCall(unary.resolvedCall, unary.operand, New TBoundExpression[0], bound)
			Local foldedStringIntrinsic:TCompilerIrExpression = LowerFoldedStringIntrinsic(unary, bound)
			If foldedStringIntrinsic Then Return foldedStringIntrinsic
			If unary.operatorText.ToLower() = "sizeof" Or unary.operatorText.ToLower() = "alignof" Then
				Local typeMeasure:TCompilerIrUnary = New TCompilerIrUnary
				InitializeExpression(typeMeasure, IR_EXPRESSION_UNARY, bound)
				typeMeasure.operatorText = unary.operatorText
				Local measuredType:TSemanticType = unary.operandSemanticType
				If Not measuredType And unary.operand Then measuredType = unary.operand.semanticType
				If Not measuredType Then
					AddUnsupported("BMXC1210", unary.operatorText + " has no resolved operand type", bound.syntax)
					Return Null
				End If
				typeMeasure.measureType = TypeName(measuredType)
				Return typeMeasure
			End If
			If unary.operatorText.ToLower() = "varptr" Then
				Local addressed:TCompilerIrExpression = LowerExpression(unary.operand)
				If Not addressed Then Return Null
				If Not IsAddressableExpression(addressed) Then
					AddUnsupported("BMXC1120", "VarPtr operand is not addressable in typed compiler IR", bound.syntax)
					Return Null
				End If
				Local address:TCompilerIrAddressOf = New TCompilerIrAddressOf
				InitializeExpression(address, IR_EXPRESSION_ADDRESS_OF, bound)
				address.operand = addressed
				Return address
			End If
			If unary.operatorText.ToLower() = "stackalloc" Then
				Local stackAllocation:TCompilerIrUnary = New TCompilerIrUnary
				InitializeExpression(stackAllocation, IR_EXPRESSION_UNARY, bound)
				stackAllocation.operatorText = unary.operatorText
				stackAllocation.operand = LowerExpression(unary.operand)
				Return stackAllocation
			End If
			If TCallableSemanticType(unary.operand.semanticType) Then
				If unary.operatorText.ToLower() = "not" Then Return CallableTruth(unary.operand, True, bound.syntax)
				AddUnsupported("BMXC1186", "Callable unary operation '" + unary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If TClosureSemanticType(unary.operand.semanticType) Then
				If unary.operatorText.ToLower() = "not" Then Return ManagedTruth(unary.operand, True, bound.syntax, IR_MANAGED_REFERENCE_CLOSURE)
				AddUnsupported("BMXC1243", "Closure unary operation '" + unary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsObjectReferenceType(unary.operand.semanticType) Or IsObjectReferenceType(bound.semanticType) Then
				If unary.operatorText.ToLower() = "not" Then Return ManagedTruth(unary.operand, True, bound.syntax, IR_MANAGED_REFERENCE_OBJECT)
				AddUnsupported("BMXC1147", "Object unary operation '" + unary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsArrayType(unary.operand.semanticType) Or IsArrayType(bound.semanticType) Then
				If unary.operatorText.ToLower() = "not" Then Return ManagedTruth(unary.operand, True, bound.syntax, IR_MANAGED_REFERENCE_ARRAY)
				If unary.operatorText.ToLower() = "len" Then
					Local unaryArrayLength:TCompilerIrArrayLength = New TCompilerIrArrayLength
					InitializeExpression(unaryArrayLength, IR_EXPRESSION_ARRAY_LENGTH, bound)
					unaryArrayLength.receiver = LowerExpression(unary.operand)
					If Not unaryArrayLength.receiver Then Return Null
					Return unaryArrayLength
				End If
				AddUnsupported("BMXC1133", "Array unary operation '" + unary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsStringType(unary.operand.semanticType) Or IsStringType(bound.semanticType) Then
				If unary.operatorText.ToLower() = "not" Then Return ManagedTruth(unary.operand, True, bound.syntax)
				If unary.operatorText.ToLower() = "len" Then
					Local unaryStringLength:TCompilerIrStringLength = New TCompilerIrStringLength
					InitializeExpression(unaryStringLength, IR_EXPRESSION_STRING_LENGTH, bound)
					unaryStringLength.receiver = LowerExpression(unary.operand)
					Return unaryStringLength
				End If
				If unary.operatorText.ToLower() = "asc" Then
					Local stringAsc:TCompilerIrStringAsc = New TCompilerIrStringAsc
					InitializeExpression(stringAsc, IR_EXPRESSION_STRING_ASC, bound)
					stringAsc.receiver = LowerExpression(unary.operand)
					Return stringAsc
				End If
				If unary.operatorText.ToLower() = "chr" Then
					Local stringChr:TCompilerIrStringChr = New TCompilerIrStringChr
					InitializeExpression(stringChr, IR_EXPRESSION_STRING_CHR, bound)
					stringChr.codePoint = LowerExpression(unary.operand)
					Return stringChr
				End If
				AddUnsupported("BMXC1123", "String unary operation '" + unary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsPointerType(unary.operand.semanticType) Or IsPointerType(bound.semanticType) Then
				If unary.operatorText.ToLower() = "not" Then
					Local pointerTruth:TCompilerIrPointerTruth = New TCompilerIrPointerTruth
					InitializeExpression(pointerTruth, IR_EXPRESSION_POINTER_TRUTH, bound)
					pointerTruth.operand = LowerExpression(unary.operand)
					pointerTruth.negate = True
					Return pointerTruth
				End If
				AddUnsupported("BMXC1120", "Pointer unary operations require explicit pointer IR operations", bound.syntax)
				Return Null
			End If
			If StructForType(unary.operand.semanticType) Or ImportedStructForType(unary.operand.semanticType) Then
				If unary.operatorText.ToLower() = "not" Then Return StructTruth(True, bound.syntax)
				AddUnsupported("BMXC1217", "Struct unary operation '" + unary.operatorText + "' requires a resolved operator", bound.syntax)
				Return Null
			End If
			Local resultUnary:TCompilerIrUnary = New TCompilerIrUnary
			InitializeExpression(resultUnary, IR_EXPRESSION_UNARY, bound)
			resultUnary.operatorText = unary.operatorText
			resultUnary.operand = LowerExpression(unary.operand)
			Return resultUnary
		End If

		Local binary:TBoundBinaryExpression = TBoundBinaryExpression(bound)
		If binary Then
			If binary.resolvedCall Then Return LowerResolvedOperatorCall(binary.resolvedCall, binary.left, [binary.right], bound)
			If TCallableSemanticType(binary.left.semanticType) Or TCallableSemanticType(binary.right.semanticType) Then
				Local callableOperation:String = binary.operatorText.ToLower()
				If callableOperation = "and" Or callableOperation = "or" Then
					Local callableTruthBinary:TCompilerIrBinary = New TCompilerIrBinary
					InitializeExpression(callableTruthBinary, IR_EXPRESSION_BINARY, bound)
					callableTruthBinary.semanticType = "Int"
					callableTruthBinary.operatorText = binary.operatorText
					callableTruthBinary.left = LowerCondition(binary.left)
					callableTruthBinary.right = LowerCondition(binary.right)
					Return callableTruthBinary
				End If
			End If
			If TClosureSemanticType(binary.left.semanticType) Or TClosureSemanticType(binary.right.semanticType) Then
				Local closureOperation:String = binary.operatorText.ToLower()
				If closureOperation = "and" Or closureOperation = "or" Then
					Local closureTruthBinary:TCompilerIrBinary = New TCompilerIrBinary
					InitializeExpression(closureTruthBinary, IR_EXPRESSION_BINARY, bound)
					closureTruthBinary.semanticType = "Int"
					closureTruthBinary.operatorText = binary.operatorText
					closureTruthBinary.left = LowerCondition(binary.left)
					closureTruthBinary.right = LowerCondition(binary.right)
					Return closureTruthBinary
				End If
				If binary.operatorText = "=" Or binary.operatorText = "<>" Then
					Local closureIdentity:TCompilerIrManagedIdentity = New TCompilerIrManagedIdentity
					InitializeExpression(closureIdentity, IR_EXPRESSION_MANAGED_IDENTITY, bound)
					closureIdentity.operatorText = binary.operatorText
					closureIdentity.managedKind = IR_MANAGED_REFERENCE_CLOSURE
					closureIdentity.left = LowerContextualExpression(binary.left, binary.right.semanticType)
					closureIdentity.right = LowerContextualExpression(binary.right, binary.left.semanticType)
					Return closureIdentity
				End If
				AddUnsupported("BMXC1243", "Closure operation '" + binary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsObjectReferenceType(binary.left.semanticType) Or IsObjectReferenceType(binary.right.semanticType) Then
				Local objectOperation:String = binary.operatorText.ToLower()
				If objectOperation = "and" Or objectOperation = "or" Then
					Local objectTruthBinary:TCompilerIrBinary = New TCompilerIrBinary
					objectTruthBinary.kind = IR_EXPRESSION_BINARY
					objectTruthBinary.semanticType = "Int"
					objectTruthBinary.source = SourceOf(bound.syntax)
					objectTruthBinary.operatorText = binary.operatorText
					objectTruthBinary.left = LowerCondition(binary.left)
					objectTruthBinary.right = LowerCondition(binary.right)
					Return objectTruthBinary
				End If
				If binary.operatorText = "=" Or binary.operatorText = "<>" Then
					Local objectIdentity:TCompilerIrManagedIdentity = New TCompilerIrManagedIdentity
					InitializeExpression(objectIdentity, IR_EXPRESSION_MANAGED_IDENTITY, bound)
					objectIdentity.operatorText = binary.operatorText
					objectIdentity.managedKind = IR_MANAGED_REFERENCE_OBJECT
					objectIdentity.left = LowerContextualExpression(binary.left, binary.right.semanticType)
					objectIdentity.right = LowerContextualExpression(binary.right, binary.left.semanticType)
					Return objectIdentity
				End If
				AddUnsupported("BMXC1147", "Object operation '" + binary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsArrayType(binary.left.semanticType) Or IsArrayType(binary.right.semanticType) Or IsArrayType(bound.semanticType) Then
				Local arrayOperation:String = binary.operatorText.ToLower()
				If arrayOperation = "-" And TConversionClassifier.IsIntegral(bound.semanticType) And (IsPointerType(binary.left.semanticType) Or IsPointerType(binary.right.semanticType)) Then
					Local arrayPointerDifference:TCompilerIrPointerBinary = New TCompilerIrPointerBinary
					InitializeExpression(arrayPointerDifference, IR_EXPRESSION_POINTER_BINARY, bound)
					arrayPointerDifference.operatorText = binary.operatorText
					If IsPointerType(binary.left.semanticType) Then
						arrayPointerDifference.left = LowerExpression(binary.left)
						arrayPointerDifference.right = LowerArrayToPointer(binary.right, binary.left.semanticType)
					Else
						arrayPointerDifference.left = LowerArrayToPointer(binary.left, binary.right.semanticType)
						arrayPointerDifference.right = LowerExpression(binary.right)
					End If
					Return arrayPointerDifference
				End If
				If arrayOperation = "and" Or arrayOperation = "or" Then
					Local arrayTruthBinary:TCompilerIrBinary = New TCompilerIrBinary
					arrayTruthBinary.kind = IR_EXPRESSION_BINARY
					arrayTruthBinary.semanticType = "Int"
					arrayTruthBinary.source = SourceOf(bound.syntax)
					arrayTruthBinary.operatorText = binary.operatorText
					arrayTruthBinary.left = LowerCondition(binary.left)
					arrayTruthBinary.right = LowerCondition(binary.right)
					Return arrayTruthBinary
				End If
				Local arrayType:TArraySemanticType = TArraySemanticType(bound.semanticType)
				If Not arrayType Then arrayType = TArraySemanticType(binary.left.semanticType)
				If binary.operatorText = "+" And arrayType And IsSupportedArrayElementType(arrayType.elementType) Then
					Local concat:TCompilerIrArrayConcat = New TCompilerIrArrayConcat
					InitializeExpression(concat, IR_EXPRESSION_ARRAY_CONCAT, bound)
					concat.elementType = TypeName(arrayType.elementType)
					concat.elementEncoding = ArrayElementEncoding(arrayType.elementType)
					Local concatEnum:TCompilerIrEnum = EnumForType(arrayType.elementType)
					If concatEnum Then concat.enumId = concatEnum.enumId
					Local concatStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
					Local concatImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
					If concatStruct Then concat.structId = concatStruct.structId
					If concatImportedStruct Then concat.importedStructId = concatImportedStruct.importedStructId
					concat.left = LowerExpression(binary.left)
					concat.right = LowerExpression(binary.right)
					Return concat
				End If
				If binary.operatorText = "=" Or binary.operatorText = "<>" Then
					Local identity:TCompilerIrManagedIdentity = New TCompilerIrManagedIdentity
					InitializeExpression(identity, IR_EXPRESSION_MANAGED_IDENTITY, bound)
					identity.operatorText = binary.operatorText
					identity.managedKind = IR_MANAGED_REFERENCE_ARRAY
					identity.left = LowerContextualExpression(binary.left, binary.right.semanticType)
					identity.right = LowerContextualExpression(binary.right, binary.left.semanticType)
					Return identity
				End If
				AddUnsupported("BMXC1133", "Array operation '" + binary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsStringType(binary.left.semanticType) Or IsStringType(binary.right.semanticType) Or IsStringType(bound.semanticType) Then
				Local stringOperation:String = binary.operatorText.ToLower()
				If stringOperation = "and" Or stringOperation = "or" Then
					Local truthBinary:TCompilerIrBinary = New TCompilerIrBinary
					truthBinary.kind = IR_EXPRESSION_BINARY
					truthBinary.semanticType = "Int"
					truthBinary.source = SourceOf(bound.syntax)
					truthBinary.operatorText = binary.operatorText
					truthBinary.left = LowerCondition(binary.left)
					truthBinary.right = LowerCondition(binary.right)
					Return truthBinary
				End If
				If stringOperation = "+" Then
					Local concat:TCompilerIrStringConcat = New TCompilerIrStringConcat
					InitializeExpression(concat, IR_EXPRESSION_STRING_CONCAT, bound)
					concat.left = LowerStringOperand(binary.left)
					concat.right = LowerStringOperand(binary.right)
					Return SequenceStringConcat(concat, bound.syntax)
				End If
				If IsComparisonOperator(stringOperation) Then
					Local comparison:TCompilerIrStringCompare = New TCompilerIrStringCompare
					InitializeExpression(comparison, IR_EXPRESSION_STRING_COMPARE, bound)
					comparison.operatorText = binary.operatorText
					comparison.left = LowerStringOperand(binary.left)
					comparison.right = LowerStringOperand(binary.right)
					Return comparison
				End If
				AddUnsupported("BMXC1123", "String binary operation '" + binary.operatorText + "' is not implemented", bound.syntax)
				Return Null
			End If
			If IsPointerType(binary.left.semanticType) Or IsPointerType(binary.right.semanticType) Or IsPointerType(bound.semanticType) Then
				Local pointerOperation:String = binary.operatorText.ToLower()
				If pointerOperation = "and" Or pointerOperation = "or" Then
					Local pointerTruthBinary:TCompilerIrBinary = New TCompilerIrBinary
					pointerTruthBinary.kind = IR_EXPRESSION_BINARY
					pointerTruthBinary.semanticType = "Int"
					pointerTruthBinary.source = SourceOf(bound.syntax)
					pointerTruthBinary.operatorText = binary.operatorText
					pointerTruthBinary.left = LowerCondition(binary.left)
					pointerTruthBinary.right = LowerCondition(binary.right)
					Return pointerTruthBinary
				End If
				If pointerOperation <> "+" And pointerOperation <> "-" And Not IsComparisonOperator(pointerOperation) Then
					AddUnsupported("BMXC1120", "Pointer operation '" + binary.operatorText + "' is not implemented", bound.syntax)
					Return Null
				End If
				Local pointerBinary:TCompilerIrPointerBinary = New TCompilerIrPointerBinary
				InitializeExpression(pointerBinary, IR_EXPRESSION_POINTER_BINARY, bound)
				pointerBinary.operatorText = binary.operatorText
				If pointerOperation = "-" And TConversionClassifier.IsIntegral(bound.semanticType) Then
					If IsPointerType(binary.left.semanticType) Then
						pointerBinary.left = LowerExpression(binary.left)
						pointerBinary.right = LowerContextualExpression(binary.right, binary.left.semanticType)
					Else
						pointerBinary.left = LowerContextualExpression(binary.left, binary.right.semanticType)
						pointerBinary.right = LowerExpression(binary.right)
					End If
				Else
					pointerBinary.left = LowerContextualExpression(binary.left, binary.right.semanticType)
					pointerBinary.right = LowerContextualExpression(binary.right, binary.left.semanticType)
				End If
				Return pointerBinary
			End If
			Local resultBinary:TCompilerIrBinary = New TCompilerIrBinary
			InitializeExpression(resultBinary, IR_EXPRESSION_BINARY, bound)
			resultBinary.operatorText = binary.operatorText
			resultBinary.left = LowerContextualExpression(binary.left, binary.right.semanticType)
			resultBinary.right = LowerContextualExpression(binary.right, binary.left.semanticType)
			Return resultBinary
		End If

		Local conversion:TBoundConversionExpression = TBoundConversionExpression(bound)
		If conversion Then
			If conversion.conversionKind = CONVERSION_DEFAULT_VALUE Then
				If TClosureSemanticType(bound.semanticType) Then Return ManagedDefault(TypeName(bound.semanticType), IR_MANAGED_REFERENCE_CLOSURE, SourceOf(bound.syntax))
				If IsStringType(bound.semanticType) Then Return ManagedDefault(TypeName(bound.semanticType), IR_MANAGED_REFERENCE_STRING, SourceOf(bound.syntax))
				If IsArrayType(bound.semanticType) Then Return ManagedDefault(TypeName(bound.semanticType), IR_MANAGED_REFERENCE_ARRAY, SourceOf(bound.syntax))
				If IsExternInterfaceType(bound.semanticType) Then Return ScalarDefault(TypeName(bound.semanticType), SourceOf(bound.syntax))
				If IsObjectReferenceType(bound.semanticType) Then Return ManagedDefault(TypeName(bound.semanticType), IR_MANAGED_REFERENCE_OBJECT, SourceOf(bound.syntax))
				If StructForType(bound.semanticType) Or ImportedStructForType(bound.semanticType) Then Return StructDefault(bound.semanticType, SourceOf(bound.syntax), bound.syntax)
				If IsPointerType(bound.semanticType) Then Return ScalarDefault(TypeName(bound.semanticType), SourceOf(bound.syntax))
				If IsNumericType(bound.semanticType) Or EnumForType(bound.semanticType) Then Return ScalarDefault(TypeName(bound.semanticType), SourceOf(bound.syntax))
				AddUnsupported("BMXC1216", "Null default conversion to '" + TypeName(bound.semanticType) + "' has no typed IR representation", bound.syntax)
				Return Null
			End If
			If conversion.conversionKind = CONVERSION_ENUM_TO_STRING Then
				Local stringEnum:TCompilerIrEnum = EnumForType(conversion.operand.semanticType)
				If Not stringEnum Then
					AddUnsupported("BMXC1103", "Enum-to-String conversion requires a retained Enum descriptor", bound.syntax)
					Return Null
				End If
				Local enumToString:TCompilerIrEnumIntrinsic = New TCompilerIrEnumIntrinsic
				InitializeExpression(enumToString, IR_EXPRESSION_ENUM_INTRINSIC, bound)
				enumToString.intrinsicKind = IR_ENUM_INTRINSIC_TO_STRING
				enumToString.enumId = stringEnum.enumId
				enumToString.receiver = LowerExpression(conversion.operand)
				Return enumToString
			End If
			' BlitzMax String values use the canonical empty String for Null.
			' An explicit String(Object) cast therefore needs the runtime
			' downcast helper rather than a raw C pointer cast: the latter leaks
			' bbNullObject into BBSTRING and makes an absent reflected metadata
			' value truthy.
			If IsStringType(bound.semanticType) And IsObjectReferenceType(conversion.operand.semanticType) Then
				Local objectStringCast:TCompilerIrObjectStringCast = New TCompilerIrObjectStringCast
				InitializeExpression(objectStringCast, IR_EXPRESSION_OBJECT_STRING_CAST, bound)
				objectStringCast.operand = LowerExpression(conversion.operand)
				Return objectStringCast
			End If
			Local targetInterface:TCompilerIrInterface = InterfaceForType(bound.semanticType)
			If targetInterface And Not targetInterface.isExternInterface Then
				Local interfaceCast:TCompilerIrInterfaceCast = New TCompilerIrInterfaceCast
				InitializeExpression(interfaceCast, IR_EXPRESSION_INTERFACE_CAST, bound)
				interfaceCast.interfaceId = targetInterface.interfaceId
				interfaceCast.operand = LowerExpression(conversion.operand)
				Return interfaceCast
			End If
			Local targetClass:TCompilerIrClass = ClassForType(bound.semanticType)
			If targetClass And Not conversion.implicitConversion Then
				Local objectCast:TCompilerIrObjectCast = New TCompilerIrObjectCast
				InitializeExpression(objectCast, IR_EXPRESSION_OBJECT_CAST, bound)
				objectCast.classId = targetClass.classId
				objectCast.operand = LowerExpression(conversion.operand)
				Return objectCast
			End If
			Local targetImportedClass:TCompilerIrImportedClass = ImportedClassForType(bound.semanticType)
			If targetImportedClass And Not conversion.implicitConversion Then
				Local objectCast:TCompilerIrObjectCast = New TCompilerIrObjectCast
				InitializeExpression(objectCast, IR_EXPRESSION_OBJECT_CAST, bound)
				objectCast.importedClassId = targetImportedClass.importedClassId
				objectCast.operand = LowerExpression(conversion.operand)
				Return objectCast
			End If
			Local resultConversion:TCompilerIrConversion = New TCompilerIrConversion
			InitializeExpression(resultConversion, IR_EXPRESSION_CONVERSION, bound)
			resultConversion.conversionKind = conversion.conversionKind
			resultConversion.implicitConversion = conversion.implicitConversion
			Local conversionArray:TArraySemanticType = TArraySemanticType(bound.semanticType)
			If conversionArray And Not conversion.implicitConversion Then
				resultConversion.arrayCastElementEncoding = ArrayElementEncoding(conversionArray.elementType)
			End If
			If conversion.conversionKind = CONVERSION_ARRAY_TO_POINTER And TArraySemanticType(conversion.operand.semanticType) Then
				resultConversion.arrayToPointerUsesHeapStorage = True
			End If
			Local conversionCallable:TCallableSemanticType = TCallableSemanticType(bound.semanticType)
			If conversionCallable Then
				resultConversion.callableReturnType = TypeName(conversionCallable.returnType)
				resultConversion.callableParameters = CallableParameters(conversionCallable)
				resultConversion.callableCallingConvention = conversionCallable.callingConvention
			End If
			If Not conversion.implicitConversion And TConversionClassifier.IsIntegral(conversion.operand.semanticType) Then
				Local conversionEnum:TCompilerIrEnum = EnumForType(bound.semanticType)
				If conversionEnum Then resultConversion.checkedEnumId = conversionEnum.enumId
			End If
			resultConversion.operand = LowerExpression(conversion.operand)
			Return resultConversion
		End If

		Local creation:TBoundNewExpression = TBoundNewExpression(bound)
		If creation And Not IsArrayType(bound.semanticType) And ImportedStructForType(creation.createdType) Then
			Local importedStruct:TCompilerIrImportedStruct = ImportedStructForType(creation.createdType)
			Local importedConstructor:TCompilerIrImportedStructRoutine
			Local genericImportedStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(genericStructsByTypeName.ValueForKey(TypeName(creation.createdType).ToLower()))
			If genericImportedStruct Then
				For Local candidate:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
					If GenericStructConstructorMatches(candidate, creation) Then importedConstructor = candidate; Exit
				Next
			Else If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
				importedConstructor = ImportedStructRoutine(creation.resolvedConstructor.routine, bound.syntax)
			End If
			Local importedStructNew:TCompilerIrStructNew = New TCompilerIrStructNew
			InitializeExpression(importedStructNew, IR_EXPRESSION_STRUCT_NEW, bound)
			importedStructNew.importedStructId = importedStruct.importedStructId
			If importedConstructor And importedConstructor.isConstructor Then
				importedStructNew.importedConstructorId = importedConstructor.routineId
			Else If creation.arguments.length Then
				AddUnsupported("BMXC1196", "Imported Struct construction arguments require a published constructor helper", bound.syntax)
				Return Null
			End If
			If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
				Local importedArgumentsSucceeded:Int
				importedStructNew.arguments = LowerResolvedArguments(creation.arguments, creation.resolvedConstructor.routine, bound.syntax, importedArgumentsSucceeded, creation.resolvedConstructor)
				If Not importedArgumentsSucceeded Then Return Null
			End If
			If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
				Return SequenceResolvedArguments(importedStructNew, importedStructNew.arguments, creation.resolvedConstructor.routine, bound.syntax)
			End If
			Return importedStructNew
		End If
		If creation And Not IsArrayType(bound.semanticType) And StructForType(creation.createdType) Then
			Local irStruct:TCompilerIrStruct = StructForType(creation.createdType)
			Local constructor:TCompilerIrFunction
			If creation.resolvedConstructor And creation.resolvedConstructor.routine Then constructor = TCompilerIrFunction(functionsBySymbol.ValueForKey(creation.resolvedConstructor.routine))
			If creation.arguments.length And Not constructor Then
				AddUnsupported("BMXC1196", "Struct construction arguments require a lowered constructor", bound.syntax)
				Return Null
			End If
			Local structNew:TCompilerIrStructNew = New TCompilerIrStructNew
			InitializeExpression(structNew, IR_EXPRESSION_STRUCT_NEW, bound)
			structNew.structId = irStruct.structId
			If constructor Then structNew.constructorFunctionId = constructor.functionId
			If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
				Local argumentsSucceeded:Int
				structNew.arguments = LowerResolvedArguments(creation.arguments, creation.resolvedConstructor.routine, bound.syntax, argumentsSucceeded, creation.resolvedConstructor)
				If Not argumentsSucceeded Then Return Null
			End If
			If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
				Return SequenceResolvedArguments(structNew, structNew.arguments, creation.resolvedConstructor.routine, bound.syntax)
			End If
			Return structNew
		End If
		If creation And Not IsArrayType(bound.semanticType) And IsObjectReferenceType(creation.createdType) Then
			Local importedClass:TCompilerIrImportedClass = ImportedClassForType(creation.createdType)
			If importedClass Then
				Local selectedConstructor:TCompilerIrImportedConstructor
				If importedClass.isGenericSpecialization Then
					If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
						For Local candidate:TCompilerIrImportedConstructor = EachIn importedClass.constructors
							If GenericTypeConstructorMatches(candidate, creation) Then selectedConstructor = candidate; Exit
						Next
					Else If Not creation.arguments.length Then
						' An inherited constructor with optional parameters does not
						' replace BlitzMax's implicit derived New().
						selectedConstructor = ImplicitImportedConstructor(importedClass, bound.syntax)
					End If
				Else If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
					selectedConstructor = ImportedConstructor(creation.resolvedConstructor.routine, bound.syntax)
				Else If Not creation.arguments.length Then
					selectedConstructor = ImplicitImportedConstructor(importedClass, bound.syntax)
				End If
				If Not selectedConstructor Then
					AddUnsupported("BMXC1171", "Imported Type allocation requires a selected constructor with a published object-construction ABI", bound.syntax)
					Return Null
				End If
				Local importedObjectNew:TCompilerIrObjectNew = New TCompilerIrObjectNew
				InitializeExpression(importedObjectNew, IR_EXPRESSION_OBJECT_NEW, bound)
				importedObjectNew.importedClassId = importedClass.importedClassId
				If creation.instanceExpression Then importedObjectNew.dynamicClassSource = LowerExpression(creation.instanceExpression)
				importedObjectNew.importedConstructorId = selectedConstructor.constructorId
				If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
					Local argumentsSucceeded:Int
					importedObjectNew.arguments = LowerResolvedArguments(creation.arguments, creation.resolvedConstructor.routine, bound.syntax, argumentsSucceeded, creation.resolvedConstructor)
					If Not argumentsSucceeded Then Return Null
					NormalizeGenericManagedConstructorDefaults(importedObjectNew.arguments, selectedConstructor.parameters)
				Else
					importedObjectNew.arguments = New TCompilerIrExpression[0]
				End If
				If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
					Return SequenceResolvedArguments(importedObjectNew, importedObjectNew.arguments, creation.resolvedConstructor.routine, bound.syntax)
				End If
				Return importedObjectNew
			End If
			Local irClass:TCompilerIrClass = ClassForType(creation.createdType)
			Local constructor:TCompilerIrFunction
			If creation.resolvedConstructor And creation.resolvedConstructor.routine Then constructor = TCompilerIrFunction(functionsBySymbol.ValueForKey(creation.resolvedConstructor.routine))
			If irClass And creation.resolvedConstructor And creation.resolvedConstructor.routine And (Not constructor Or constructor.ownerClassId <> irClass.classId) Then
				constructor = InheritedConstructor(irClass, creation.resolvedConstructor.routine, bound.syntax)
			End If
			If irClass And (Not creation.arguments.length Or constructor) Then
				Local objectNew:TCompilerIrObjectNew = New TCompilerIrObjectNew
				InitializeExpression(objectNew, IR_EXPRESSION_OBJECT_NEW, bound)
				objectNew.classId = irClass.classId
				If creation.instanceExpression Then objectNew.dynamicClassSource = LowerExpression(creation.instanceExpression)
				If constructor And creation.resolvedConstructor.routine.parameters.length Then objectNew.constructorFunctionId = constructor.functionId
				If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
					Local argumentsSucceeded:Int
					objectNew.arguments = LowerResolvedArguments(creation.arguments, creation.resolvedConstructor.routine, bound.syntax, argumentsSucceeded, creation.resolvedConstructor)
					If Not argumentsSucceeded Then Return Null
				Else
					objectNew.arguments = New TCompilerIrExpression[0]
				End If
				If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
					Return SequenceResolvedArguments(objectNew, objectNew.arguments, creation.resolvedConstructor.routine, bound.syntax)
				End If
				Return objectNew
			End If
			If creation.instanceExpression And Not creation.arguments.length Then
				' The root Object type has no ordinary source/imported class record,
				' but production's deprecated `New value` form allocates through the
				' runtime class carried by that value.
				Local dynamicObjectNew:TCompilerIrObjectNew = New TCompilerIrObjectNew
				InitializeExpression(dynamicObjectNew, IR_EXPRESSION_OBJECT_NEW, bound)
				dynamicObjectNew.dynamicClassSource = LowerExpression(creation.instanceExpression)
				Return dynamicObjectNew
			End If
			AddUnsupported("BMXC1148", "Object allocation requires an implicit default or lowered source constructor", bound.syntax)
			Return Null
		End If
		If creation And IsArrayType(bound.semanticType) Then
			Local createdArray:TArraySemanticType = TArraySemanticType(bound.semanticType)
			If Not createdArray Or createdArray.rank <= 0 Or creation.dimensions.length <> createdArray.rank Then
				AddUnsupported("BMXC1134", "Heap-array allocation requires one dimension per declared rank", bound.syntax)
				Return Null
			End If
			If Not IsSupportedArrayElementType(createdArray.elementType) Then
				AddUnsupported("BMXC1132", "Array element type '" + TypeName(createdArray.elementType) + "' is not implemented", bound.syntax)
				Return Null
			End If
			Local arrayNew:TCompilerIrArrayNew = New TCompilerIrArrayNew
			InitializeExpression(arrayNew, IR_EXPRESSION_ARRAY_NEW, bound)
			arrayNew.elementType = TypeName(createdArray.elementType)
			arrayNew.elementEncoding = ArrayElementEncoding(createdArray.elementType)
			Local arrayEnum:TCompilerIrEnum = EnumForType(createdArray.elementType)
			If arrayEnum Then arrayNew.enumId = arrayEnum.enumId
			Local arrayStruct:TCompilerIrStruct = StructForType(createdArray.elementType)
			Local arrayImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(createdArray.elementType)
			If arrayStruct Then
				arrayNew.structId = arrayStruct.structId
				arrayStruct.arrayInitializerRequired = True
			End If
			If arrayImportedStruct Then
				arrayNew.importedStructId = arrayImportedStruct.importedStructId
			End If
			arrayNew.rank = createdArray.rank
			arrayNew.dimensions = New TCompilerIrExpression[creation.dimensions.length]
			For Local dimensionIndex:Int = 0 Until creation.dimensions.length
				arrayNew.dimensions[dimensionIndex] = LowerExpression(creation.dimensions[dimensionIndex])
				If Not arrayNew.dimensions[dimensionIndex] Then Return Null
			Next
			Return arrayNew
		End If

		Local passthrough:TBoundPassthroughExpression = TBoundPassthroughExpression(bound)
		If passthrough Then Return LowerExpression(passthrough.operand)
		If creation And MissingExecutableGenericSpecialization(creation.createdType) Then Return Null

		AddUnsupported("BMXC1015", "Bound expression kind '" + bound.boundKind + "' is not implemented", bound.syntax)
		Return Null
	End Method

	Method LowerRangeIndexSlice:TCompilerIrExpression(indexed:TBoundIndexExpression, bound:TBoundExpression)
		If Not indexed Or indexed.indexes.length <> 1 Or Not indexed.access Then Return Null
		Local rangeType:TSemanticType = indexed.indexes[0].semanticType
		Local rangeStruct:TCompilerIrImportedStruct = ImportedStructForType(rangeType)
		If Not rangeStruct Then
			AddUnsupported("BMXC1211", "The standard Range value has no published Struct ABI", bound.syntax)
			Return Null
		End If
		Local startRoutine:TCompilerIrImportedStructRoutine = GenericImportedStructRoutine(rangeStruct, indexed.access.rangeStartRoutine)
		Local endRoutine:TCompilerIrImportedStructRoutine = GenericImportedStructRoutine(rangeStruct, indexed.access.rangeEndRoutine)
		If Not startRoutine Or Not endRoutine Then
			AddUnsupported("BMXC1211", "The standard Range value has no published bound-resolution ABI", bound.syntax)
			Return Null
		End If

		Local loweredReceiver:TCompilerIrExpression = LowerExpression(indexed.receiver)
		Local loweredRange:TCompilerIrExpression = LowerExpression(indexed.indexes[0])
		If Not loweredReceiver Or Not loweredRange Then Return Null
		Local receiverMaterialization:TCompilerIrMaterialize = BeginMaterialization(loweredReceiver, indexed.receiver.syntax)
		Local rangeMaterialization:TCompilerIrMaterialize = BeginMaterialization(loweredRange, indexed.indexes[0].syntax)
		Local receiverReference:TCompilerIrSymbolReference = TemporaryReference(receiverMaterialization, indexed.receiver, indexed.receiver.syntax, "range_receiver")

		Local length:TCompilerIrExpression
		If indexed.access.accessKind = INDEX_ACCESS_RANGE_STRING Then
			Local stringLength:TCompilerIrStringLength = New TCompilerIrStringLength
			stringLength.kind = IR_EXPRESSION_STRING_LENGTH
			stringLength.semanticType = "Int"
			stringLength.source = SourceOf(bound.syntax)
			stringLength.receiver = receiverReference
			length = stringLength
		Else
			Local arrayLength:TCompilerIrArrayLength = New TCompilerIrArrayLength
			arrayLength.kind = IR_EXPRESSION_ARRAY_LENGTH
			arrayLength.semanticType = "Int"
			arrayLength.source = SourceOf(bound.syntax)
			arrayLength.receiver = receiverReference
			length = arrayLength
		End If

		Local lowerBound:TCompilerIrCall = RangeBoundCall(startRoutine, rangeMaterialization, indexed.indexes[0], length, bound.syntax)
		Local upperBound:TCompilerIrCall = RangeBoundCall(endRoutine, rangeMaterialization, indexed.indexes[0], length, bound.syntax)
		Local sliceExpression:TCompilerIrExpression
		If indexed.access.accessKind = INDEX_ACCESS_RANGE_STRING Then
			Local stringSlice:TCompilerIrStringSlice = New TCompilerIrStringSlice
			InitializeExpression(stringSlice, IR_EXPRESSION_STRING_SLICE, bound)
			stringSlice.receiver = receiverReference
			stringSlice.lowerBound = lowerBound
			stringSlice.upperBound = upperBound
			sliceExpression = stringSlice
		Else
			Local arrayType:TArraySemanticType = TArraySemanticType(indexed.receiver.semanticType)
			If Not arrayType Or arrayType.rank <> 1 Or Not IsSupportedArrayElementType(arrayType.elementType) Then
				AddUnsupported("BMXC1210", "Range slicing supports String and one-dimensional heap Array values", bound.syntax)
				Return Null
			End If
			Local arraySlice:TCompilerIrArraySlice = New TCompilerIrArraySlice
			InitializeExpression(arraySlice, IR_EXPRESSION_ARRAY_SLICE, bound)
			arraySlice.receiver = receiverReference
			arraySlice.lowerBound = lowerBound
			arraySlice.upperBound = upperBound
			arraySlice.elementType = TypeName(arrayType.elementType)
			arraySlice.elementEncoding = ArrayElementEncoding(arrayType.elementType)
			Local elementStruct:TCompilerIrStruct = StructForType(arrayType.elementType)
			Local elementImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(arrayType.elementType)
			If elementStruct Then
				arraySlice.structId = elementStruct.structId
				elementStruct.arrayInitializerRequired = True
			End If
			If elementImportedStruct Then arraySlice.importedStructId = elementImportedStruct.importedStructId
			sliceExpression = arraySlice
		End If
		rangeMaterialization.expression = sliceExpression
		rangeMaterialization.semanticType = TypeName(bound.semanticType)
		receiverMaterialization.expression = rangeMaterialization
		receiverMaterialization.semanticType = TypeName(bound.semanticType)
		Return receiverMaterialization
	End Method

	Method RangeBoundCall:TCompilerIrCall(routine:TCompilerIrImportedStructRoutine, materialization:TCompilerIrMaterialize, boundRange:TBoundExpression, length:TCompilerIrExpression, syntax:TSyntaxNode)
		Local call:TCompilerIrCall = New TCompilerIrCall
		call.kind = IR_EXPRESSION_CALL
		call.semanticType = "Int"
		call.source = SourceOf(syntax)
		call.functionId = routine.routineId
		call.functionName = routine.name
		call.isExternal = True
		call.dispatchKind = IR_CALL_DISPATCH_STRUCT
		Local address:TCompilerIrAddressOf = New TCompilerIrAddressOf
		address.kind = IR_EXPRESSION_ADDRESS_OF
		address.semanticType = materialization.temporaryType
		address.source = SourceOf(syntax)
		address.operand = TemporaryReference(materialization, boundRange, syntax, "range")
		call.receiver = address
		If routine.parameters.length Then call.arguments = [length]
		Return call
	End Method

	Method LowerGenericStaticGlobal:TCompilerIrExpression(access:TResolvedMemberAccess, bound:TBoundExpression)
		If Not access Or Not access.member Or access.member.kind <> SYMBOL_GLOBAL Or Not access.member.containingScope Or Not access.member.containingScope.owner Then Return Null
		Local owner:TSymbol = access.member.containingScope.owner
		If (owner.kind <> SYMBOL_TYPE And owner.kind <> SYMBOL_STRUCT) Or owner.genericArity <= 0 Then Return Null
		Local externalGlobal:TCompilerIrExternalGlobal
		If access.lookupType Then externalGlobal = TCompilerIrExternalGlobal(genericStaticGlobalsByKey.ValueForKey(GenericStaticGlobalKey(TypeName(access.lookupType), access.member.name)))
		If Not externalGlobal And access.receiverType Then externalGlobal = TCompilerIrExternalGlobal(genericStaticGlobalsByKey.ValueForKey(GenericStaticGlobalKey(TypeName(access.receiverType), access.member.name)))
		If Not externalGlobal Then
			AddUnsupported("BMXC1230", "Generic static member '" + access.member.QualifiedName() + "' has no requested canonical specialization owner", bound.syntax)
			Return Null
		End If
		Local resultSymbol:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		InitializeExpression(resultSymbol, IR_EXPRESSION_SYMBOL, bound)
		resultSymbol.symbolId = externalGlobal.symbolId
		resultSymbol.name = access.member.name
		resultSymbol.isExternal = True
		Return resultSymbol
	End Method

	Method LowerResolvedOperatorCall:TCompilerIrExpression(resolved:TResolvedCall, receiver:TBoundExpression, arguments:TBoundExpression[], source:TBoundExpression)
		If Not resolved Or Not resolved.routine Or Not receiver Then Return Null
		Local call:TBoundCallExpression = New TBoundCallExpression
		call.boundKind = BOUND_EXPRESSION_CALL
		call.syntax = source.syntax
		call.semanticType = source.semanticType
		call.resolvedCall = resolved
		call.receiver = receiver
		call.arguments = arguments
		Return LowerExpression(call)
	End Method

	Method InheritedConstructor:TCompilerIrFunction(owner:TCompilerIrClass, symbol:TSymbol, useSyntax:TSyntaxNode)
		If Not owner Or Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or symbol.name.ToLower() <> "new" Then Return Null
		Local constructors:TMap = TMap(inheritedConstructorsByClass.ValueForKey(owner))
		If Not constructors Then
			constructors = New TMap
			inheritedConstructorsByClass.Insert(owner, constructors)
		End If
		Local known:TCompilerIrFunction = TCompilerIrFunction(constructors.ValueForKey(symbol))
		If known Then Return known
		Local chained:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(symbol))
		Local chainedImported:TCompilerIrImportedConstructor
		If Not chained Then chainedImported = ImportedConstructor(symbol, useSyntax)
		If Not chained And Not chainedImported Then Return Null
		Local routine:TCompilerIrFunction = New TCompilerIrFunction
		routine.functionId = "fn" + nextFunctionId
		nextFunctionId :+ 1
		routine.name = "New"
		routine.returnType = "Void"
		routine.source = SourceOf(useSyntax)
		routine.isMethod = True
		routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR
		routine.constructorChainKind = IR_CONSTRUCTOR_CHAIN_BASE
		routine.ownerClassId = owner.classId
		routine.receiver = New TCompilerIrParameter
		routine.receiver.symbolId = "self"
		routine.receiver.name = "self"
		routine.receiver.semanticType = owner.semanticType
		routine.parameters = New TCompilerIrParameter[symbol.parameters.length]
		routine.chainedConstructorArguments = New TCompilerIrExpression[symbol.parameters.length]
		For Local index:Int = 0 Until symbol.parameters.length
			Local sourceParameter:TSemanticParameter = symbol.parameters[index]
			Local parameter:TCompilerIrParameter = New TCompilerIrParameter
			parameter.symbolId = "p" + index
			If sourceParameter And sourceParameter.symbol Then parameter.name = sourceParameter.symbol.name Else parameter.name = "arg" + index
			If sourceParameter Then
				parameter.semanticType = TypeName(sourceParameter.semanticType)
				parameter.passingMode = sourceParameter.passingMode
				parameter.isOptional = sourceParameter.optional
				PopulateParameterShape(parameter, sourceParameter.semanticType)
			End If
			routine.parameters[index] = parameter
			Local argument:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
			argument.kind = IR_EXPRESSION_SYMBOL
			argument.semanticType = parameter.semanticType
			argument.source = routine.source
			argument.symbolId = parameter.symbolId
			argument.name = parameter.name
			argument.isByReference = parameter.passingMode = PARAMETER_PASS_VAR
			routine.chainedConstructorArguments[index] = argument
		Next
		If chained Then routine.chainedConstructorFunctionId = chained.functionId
		If chainedImported Then routine.chainedImportedConstructorId = chainedImported.constructorId
		routine.body = New TCompilerIrBlock
		routine.body.source = routine.source
		If Not routine.parameters.length Then owner.defaultConstructorFunctionId = routine.functionId
		constructors.Insert(symbol, routine)
		result.functions :+ [routine]
		Return routine
	End Method

	Method LowerFoldedStringIntrinsic:TCompilerIrExpression(unary:TBoundUnaryExpression, bound:TBoundExpression)
		If Not unary Or Not bound Then Return Null
		Local operation:String = unary.operatorText.ToLower()
		If operation <> "asc" And operation <> "chr" Then Return Null
		Local syntax:TExpressionSyntax = TExpressionSyntax(bound.syntax)
		If Not syntax Then Return Null
		Local constantValue:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(analysis.model, syntax)
		If Not constantValue Then Return Null
		Local literal:TCompilerIrLiteral = New TCompilerIrLiteral
		InitializeExpression(literal, IR_EXPRESSION_LITERAL, bound)
		Select constantValue.kind
			Case CONSTANT_VALUE_INTEGER
				literal.text = String(constantValue.integerValue)
			Case CONSTANT_VALUE_STRING
				literal.text = "~q" + constantValue.stringValue + "~q"
				literal.stringLiteralId = RegisterStringValue(constantValue.stringValue, SourceOf(bound.syntax)).literalId
			Default
				Return Null
		End Select
		Return literal
	End Method

	Method LowerStorageSymbol:TCompilerIrExpression(symbol:TSymbol, bound:TBoundExpression)
		If symbol And (symbol.kind = SYMBOL_CONST Or symbol.kind = SYMBOL_ENUM_MEMBER) Then
			Local constantValue:TConstantValue = analysis.model.SymbolConstantValue(symbol)
			If constantValue Then Return LowerConstantDefault(constantValue, symbol.declaredType, symbol, bound.syntax)
		End If
		Local ownedCapturePlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansBySymbol.ValueForKey(symbol))
		If ownedCapturePlan And ownedCapturePlan.ownerSymbol = currentRoutineSymbol Then Return CaptureFieldAccess(ownedCapturePlan, symbol, bound.semanticType, SourceOf(bound.syntax))
		Local incomingCapturePlan:TCompilerClosureCapturePlan = CaptureSymbolPlan(currentIncomingClosureCapturePlan, symbol)
		If incomingCapturePlan Then Return CaptureFieldAccess(incomingCapturePlan, symbol, bound.semanticType, SourceOf(bound.syntax))
		Local symbolId:String = SymbolId(symbol)
		Local externalGlobal:TCompilerIrExternalGlobal
		If Not symbolId.length Then
			externalGlobal = ResolveExternalGlobal(symbol, bound.syntax)
			If externalGlobal Then symbolId = externalGlobal.symbolId
		End If
		If Not symbolId.length Then
			Local symbolName:String = "<unresolved>"
			If symbol Then symbolName = symbol.QualifiedName()
			AddUnsupported("BMXC1011", "Symbol '" + symbolName + "' is not owned by the lowered unit", bound.syntax)
			Return Null
		End If
		Local resultSymbol:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		InitializeExpression(resultSymbol, IR_EXPRESSION_SYMBOL, bound)
		resultSymbol.symbolId = symbolId
		resultSymbol.name = symbol.name
		resultSymbol.isExternal = externalGlobal <> Null
		' Imported compact interfaces retain the callable ABI symbol even when
		' their original bang-marked declaration text is intentionally absent.
		' The visible C declaration remains the exact authority in both cases.
		If externalGlobal And TCallableSemanticType(symbol.declaredType) Then resultSymbol.nativeCallableAbiName = externalGlobal.abiName
		resultSymbol.isByReference = byReferenceSymbols.Contains(symbol)
		Return resultSymbol
	End Method

	Method CaptureEnvironmentReference:TCompilerIrExpression(plan:TCompilerClosureCapturePlan, source:TCompilerSourceLocation)
		If Not plan Or Not plan.environmentClass Or Not currentRoutine Then Return Null
		Local reference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		reference.kind = IR_EXPRESSION_SYMBOL
		reference.source = source
		If currentRoutineSymbol = plan.ownerSymbol Then
			reference.semanticType = plan.environmentClass.semanticType
			reference.symbolId = plan.environmentSymbolId
			reference.name = "$closureEnvironment"
			Return reference
		End If
		If Not currentIncomingClosureCapturePlan Or Not currentRoutine.parameters.length Or Not currentRoutine.isClosureInvoke Then Return Null
		Local environmentParameter:TCompilerIrParameter = currentRoutine.parameters[0]
		reference.semanticType = environmentParameter.semanticType
		reference.symbolId = environmentParameter.symbolId
		reference.name = environmentParameter.name
		Local cast:TCompilerIrObjectCast = New TCompilerIrObjectCast
		cast.kind = IR_EXPRESSION_OBJECT_CAST
		cast.semanticType = currentIncomingClosureCapturePlan.environmentClass.semanticType
		cast.source = source
		cast.classId = currentIncomingClosureCapturePlan.environmentClass.classId
		cast.operand = reference
		Return CaptureEnvironmentFromRoot(currentIncomingClosureCapturePlan, plan, cast, source)
	End Method

	Method CaptureEnvironmentFromRoot:TCompilerIrExpression(root:TCompilerClosureCapturePlan, target:TCompilerClosureCapturePlan, expression:TCompilerIrExpression, source:TCompilerSourceLocation)
		If Not root Or Not target Or Not expression Then Return Null
		If root = target Then Return expression
		If Not root.parentPlan Or Not root.parentField Then Return Null
		Local parentExpression:TCompilerIrExpression = CaptureParentFieldAccess(root, expression, source)
		Return CaptureEnvironmentFromRoot(root.parentPlan, target, parentExpression, source)
	End Method

	Method CaptureParentFieldAccess:TCompilerIrFieldAccess(plan:TCompilerClosureCapturePlan, receiver:TCompilerIrExpression, source:TCompilerSourceLocation)
		If Not plan Or Not plan.parentPlan Or Not plan.parentField Or Not receiver Then Return Null
		Local access:TCompilerIrFieldAccess = New TCompilerIrFieldAccess
		access.kind = IR_EXPRESSION_FIELD
		access.semanticType = plan.parentPlan.environmentClass.semanticType
		access.source = source
		access.receiver = receiver
		access.classId = plan.environmentClass.classId
		access.fieldId = plan.parentField.fieldId
		Return access
	End Method

	Function CaptureSymbolPlan:TCompilerClosureCapturePlan(plan:TCompilerClosureCapturePlan, symbol:TSymbol)
		While plan
			If plan.fieldsBySymbol.Contains(symbol) Then Return plan
			plan = plan.parentPlan
		Wend
		Return Null
	End Function

	Function CaptureSelfPlan:TCompilerClosureCapturePlan(plan:TCompilerClosureCapturePlan)
		While plan
			If plan.selfField Then Return plan
			plan = plan.parentPlan
		Wend
		Return Null
	End Function

	Method CaptureFieldAccess:TCompilerIrFieldAccess(plan:TCompilerClosureCapturePlan, symbol:TSymbol, semanticType:TSemanticType, source:TCompilerSourceLocation)
		If Not plan Or Not symbol Then Return Null
		Local captureField:TCompilerIrClassField = TCompilerIrClassField(plan.fieldsBySymbol.ValueForKey(symbol))
		If Not captureField Then Return Null
		Local receiver:TCompilerIrExpression = CaptureEnvironmentReference(plan, source)
		If Not receiver Then Return Null
		Local access:TCompilerIrFieldAccess = New TCompilerIrFieldAccess
		access.kind = IR_EXPRESSION_FIELD
		access.semanticType = TypeName(semanticType)
		access.source = source
		access.receiver = receiver
		access.classId = plan.environmentClass.classId
		access.fieldId = captureField.fieldId
		Return access
	End Method

	Method CaptureSelfFieldAccess:TCompilerIrFieldAccess(plan:TCompilerClosureCapturePlan, source:TCompilerSourceLocation)
		If Not plan Or Not plan.selfField Then Return Null
		Local receiver:TCompilerIrExpression = CaptureEnvironmentReference(plan, source)
		If Not receiver Then Return Null
		Local access:TCompilerIrFieldAccess = New TCompilerIrFieldAccess
		access.kind = IR_EXPRESSION_FIELD
		access.semanticType = TypeName(plan.selfType)
		access.source = source
		access.receiver = receiver
		access.classId = plan.environmentClass.classId
		access.fieldId = plan.selfField.fieldId
		Return access
	End Method

	Method GenericStructConstructorMatches:Int(candidate:TCompilerIrImportedStructRoutine, creation:TBoundNewExpression)
		If Not candidate Or Not candidate.isConstructor Or Not creation Then Return False
		If candidate.parameters.length < creation.arguments.length Then Return False
		If Not creation.resolvedConstructor Then
			For Local index:Int = creation.arguments.length Until candidate.parameters.length
				If Not candidate.parameters[index].isOptional Then Return False
			Next
			Return True
		End If
		If creation.resolvedConstructor.parameterTypes.length <> candidate.parameters.length Then Return False
		For Local index:Int = 0 Until candidate.parameters.length
			Local resolvedType:TSemanticType = creation.resolvedConstructor.parameterTypes[index]
			If Not GenericIrSemanticTypeMatches(candidate.parameters[index].semanticType, resolvedType) Then Return False
		Next
		For Local index:Int = creation.arguments.length Until candidate.parameters.length
			If Not candidate.parameters[index].isOptional Then Return False
		Next
		Return True
	End Method

	Method GenericTypeConstructorMatches:Int(candidate:TCompilerIrImportedConstructor, creation:TBoundNewExpression)
		If Not candidate Or Not creation Then Return False
		If candidate.parameters.length < creation.arguments.length Then Return False
		If Not creation.resolvedConstructor Then
			For Local index:Int = creation.arguments.length Until candidate.parameters.length
				If Not candidate.parameters[index].isOptional Then Return False
			Next
			Return True
		End If
		If creation.resolvedConstructor.parameterTypes.length <> candidate.parameters.length Then Return False
		For Local index:Int = 0 Until candidate.parameters.length
			If Not GenericIrSemanticTypeMatches(candidate.parameters[index].semanticType, creation.resolvedConstructor.parameterTypes[index]) Then Return False
		Next
		For Local index:Int = creation.arguments.length Until candidate.parameters.length
			If Not candidate.parameters[index].isOptional Then Return False
		Next
		Return True
	End Method

	Method GenericIrSemanticTypeMatches:Int(genericTypeName:String, semanticType:TSemanticType)
		If genericTypeName.ToLower() = TypeName(semanticType).ToLower() Then Return True
		Local arrayType:TArraySemanticType = TArraySemanticType(semanticType)
		If arrayType Then
			Local canonicalElement:String = CanonicalSemanticTypeName(arrayType.elementType)
			Return genericTypeName.ToLower() = canonicalElement + "[" + arrayType.rank + "]"
		End If
		Local pointerType:TPointerSemanticType = TPointerSemanticType(semanticType)
		If pointerType Then Return genericTypeName.ToLower() = CanonicalSemanticTypeName(pointerType.elementType) + " ptr"
		Local fixedArray:TStaticArraySemanticType = TStaticArraySemanticType(semanticType)
		If fixedArray Then Return genericTypeName.ToLower() = "staticarray " + CanonicalSemanticTypeName(fixedArray.elementType) + "[" + fixedArray.length + "]"
		Local irClass:TCompilerIrClass = ClassForType(semanticType)
		If irClass And genericTypeName.ToLower() = "@runtime-class:" + irClass.abiName.ToLower() Then Return True
		Local importedClass:TCompilerIrImportedClass = ImportedClassForType(semanticType)
		If importedClass And genericTypeName.ToLower() = "@runtime-class:" + importedClass.abiName.ToLower() Then Return True
		Local irInterface:TCompilerIrInterface = InterfaceForType(semanticType)
		If irInterface And genericTypeName.ToLower() = "@runtime-interface:" + irInterface.abiName.ToLower() Then Return True
		Local irStruct:TCompilerIrStruct = StructForType(semanticType)
		If irStruct And genericTypeName.ToLower() = "@runtime-struct:" + irStruct.abiName.ToLower() Then Return True
		Local importedStruct:TCompilerIrImportedStruct = ImportedStructForType(semanticType)
		If importedStruct And genericTypeName.ToLower() = "@runtime-struct:" + importedStruct.abiName.ToLower() Then Return True
		Local irEnum:TCompilerIrEnum = EnumForType(semanticType)
		If irEnum And genericTypeName.ToLower() = "@runtime-enum:" + irEnum.abiName.ToLower() Then Return True
		Return genericTypeName.ToLower() = CanonicalSemanticTypeName(semanticType)
	End Method

	Method LowerEnumIntrinsicCall:TCompilerIrExpression(call:TBoundCallExpression, bound:TBoundExpression)
		If Not call Or Not call.resolvedCall Or Not call.resolvedCall.routine Then Return Null
		Local routine:TSymbol = call.resolvedCall.routine
		If Not routine.containingScope Or Not routine.containingScope.owner Or routine.containingScope.owner.kind <> SYMBOL_ENUM Then Return Null
		Local irEnum:TCompilerIrEnum = EnumForType(routine.containingScope.owner.declaredType)
		If Not irEnum Or Not irEnum.runtimeDescriptor Then Return Null
		Local intrinsicKind:Int
		Select routine.name.ToLower()
			Case "ordinal" intrinsicKind = IR_ENUM_INTRINSIC_ORDINAL
			Case "values" intrinsicKind = IR_ENUM_INTRINSIC_VALUES
			Case "tostring" intrinsicKind = IR_ENUM_INTRINSIC_TO_STRING
			Case "tryconvert" intrinsicKind = IR_ENUM_INTRINSIC_TRY_CONVERT
			Case "fromstring" intrinsicKind = IR_ENUM_INTRINSIC_FROM_STRING
			Default Return Null
		End Select
		Local intrinsic:TCompilerIrEnumIntrinsic = New TCompilerIrEnumIntrinsic
		InitializeExpression(intrinsic, IR_EXPRESSION_ENUM_INTRINSIC, bound)
		intrinsic.intrinsicKind = intrinsicKind
		intrinsic.enumId = irEnum.enumId
		If intrinsicKind = IR_ENUM_INTRINSIC_ORDINAL Or intrinsicKind = IR_ENUM_INTRINSIC_TO_STRING Then
			If Not call.receiver Then
				AddUnsupported("BMXC1103", "Enum instance intrinsic '" + routine.name + "' has no receiver", bound.syntax)
				Return Null
			End If
			intrinsic.receiver = LowerExpression(call.receiver)
			If Not intrinsic.receiver Then Return Null
		End If
		Local argumentsSucceeded:Int = True
		If call.arguments.length Then intrinsic.arguments = LowerResolvedArguments(call.arguments, routine, bound.syntax, argumentsSucceeded)
		If Not argumentsSucceeded Then Return Null
		Return intrinsic
	End Method

	Method LowerIndirectCall:TCompilerIrExpression(call:TBoundCallExpression, bound:TBoundExpression)
		Local callableType:TCallableSemanticType
		Local closureType:TClosureSemanticType
		If call And call.callee Then
			callableType = CallableTypeOf(call.callee)
			closureType = ClosureTypeOf(call.callee)
			If closureType Then callableType = closureType.signature
		End If
		If Not call Or Not call.resolvedCall Then
			AddUnsupported("BMXC1184", "Indirect call is missing its resolved callable signature", bound.syntax)
			Return Null
		End If
		If Not callableType Or Not IsSupportedCallableType(callableType) Then
			Local callableName:String = "<unresolved>"
			If callableType Then callableName = TypeName(callableType)
			AddUnsupported("BMXC1184", "Indirect call target type '" + callableName + "' is not supported by the runtime ABI", bound.syntax)
			Return Null
		End If
		If call.arguments.length <> callableType.parameterTypes.length Then
			AddUnsupported("BMXC1184", "Indirect call requires " + callableType.parameterTypes.length + " arguments but received " + call.arguments.length, bound.syntax)
			Return Null
		End If
		Local indirect:TCompilerIrIndirectCall
		Local closureCall:TCompilerIrClosureCall
		Local loweredArguments:TCompilerIrExpression[] = New TCompilerIrExpression[call.arguments.length]
		If closureType Then
			closureCall = New TCompilerIrClosureCall
			InitializeExpression(closureCall, IR_EXPRESSION_CLOSURE_CALL, bound)
			closureCall.callee = LowerExpression(call.callee)
			If Not closureCall.callee Then Return Null
			closureCall.returnType = TypeName(callableType.returnType)
			closureCall.parameters = CallableParameters(callableType)
			closureCall.arguments = loweredArguments
		Else
			indirect = New TCompilerIrIndirectCall
			InitializeExpression(indirect, IR_EXPRESSION_INDIRECT_CALL, bound)
			indirect.callee = LowerExpression(call.callee)
			If Not indirect.callee Then Return Null
			indirect.returnType = TypeName(callableType.returnType)
			indirect.parameters = CallableParameters(callableType)
			indirect.callingConvention = callableType.callingConvention
			indirect.arguments = loweredArguments
		End If
		For Local index:Int = 0 Until call.arguments.length
			If TBoundOmittedArgumentExpression(call.arguments[index]) Then
				AddUnsupported("BMXC1184", "Indirect callable invocation does not accept omitted arguments", bound.syntax)
				Return Null
			End If
			Local requiredStaticArray:TStaticArraySemanticType = TStaticArraySemanticType(callableType.parameterTypes[index])
			If requiredStaticArray Then
				Local actualStaticArray:TStaticArraySemanticType = StaticArrayTypeOf(call.arguments[index])
				If Not actualStaticArray Or Not TGenericRoutineInference.SameType(actualStaticArray, requiredStaticArray) Then
					AddUnsupported("BMXC1022", "StaticArray argument " + index + " does not match callable parameter extent and element type '" + TypeName(requiredStaticArray) + "'", call.arguments[index].syntax)
					Return Null
				End If
			End If
			Local previousPreserveArgument:Int = preserveStructLValue
			If index < callableType.parameterModes.length And callableType.parameterModes[index] = PARAMETER_PASS_VAR Then preserveStructLValue = True
			loweredArguments[index] = LowerExpression(call.arguments[index])
			preserveStructLValue = previousPreserveArgument
			If Not loweredArguments[index] Then Return Null
			If index < callableType.parameterModes.length And callableType.parameterModes[index] = PARAMETER_PASS_VAR Then
				loweredArguments[index] = AddressOfExpression(loweredArguments[index], TypeName(callableType.parameterTypes[index]), SourceOf(call.arguments[index].syntax))
			End If
		Next
		If closureCall Then Return SequenceClosureCall(closureCall, bound.syntax)
		Return SequenceIndirectCall(indirect, bound.syntax)
	End Method

	Method SequenceClosureCall:TCompilerIrExpression(call:TCompilerIrClosureCall, syntax:TSyntaxNode)
		If Not call Then Return Null
		' Invoke and environment are read separately from the erased object, so
		' materialize even a zero-argument callee to guarantee one evaluation.
		Local calleeMaterialization:TCompilerIrMaterialize = BeginMaterialization(call.callee, syntax)
		call.callee = TemporaryReference(calleeMaterialization, Null, syntax, "closure")
		Local materializations:TCompilerIrMaterialize[] = New TCompilerIrMaterialize[call.arguments.length]
		For Local index:Int = 0 Until call.arguments.length
			If TCompilerIrAddressOf(call.arguments[index]) Then Continue
			If Not CallArgumentHasEvaluationEffect(call.arguments[index]) Then Continue
			Local materialization:TCompilerIrMaterialize = BeginMaterialization(call.arguments[index], syntax)
			materializations[index] = materialization
			call.arguments[index] = TemporaryReference(materialization, Null, syntax, "argument")
		Next
		Local result:TCompilerIrExpression = call
		For Local index:Int = materializations.length - 1 To 0 Step -1
			Local materialization:TCompilerIrMaterialize = materializations[index]
			If Not materialization Then Continue
			materialization.expression = result
			materialization.semanticType = call.semanticType
			result = materialization
		Next
		calleeMaterialization.expression = result
		calleeMaterialization.semanticType = call.semanticType
		Return calleeMaterialization
	End Method

	Method CallableDefault:TCompilerIrCallableDefault(callableType:TCallableSemanticType, source:TCompilerSourceLocation)
		Local value:TCompilerIrCallableDefault = New TCompilerIrCallableDefault
		value.kind = IR_EXPRESSION_CALLABLE_DEFAULT
		value.semanticType = TypeName(callableType)
		value.source = source
		value.returnType = TypeName(callableType.returnType)
		value.parameters = CallableParameters(callableType)
		value.callingConvention = callableType.callingConvention
		Return value
	End Method

	Method CallableTruth:TCompilerIrExpression(bound:TBoundExpression, negate:Int, syntax:TSyntaxNode)
		Local callableType:TCallableSemanticType = TCallableSemanticType(bound.semanticType)
		If Not IsSupportedCallableType(callableType) Then
			AddUnsupported("BMXC1186", "Callable truth test requires an ordinary-C-compatible signature", syntax)
			Return Null
		End If
		Local truth:TCompilerIrCallableTruth = New TCompilerIrCallableTruth
		truth.kind = IR_EXPRESSION_CALLABLE_TRUTH
		truth.semanticType = "Int"
		truth.source = SourceOf(syntax)
		Local loweredOperand:TCompilerIrExpression = LowerExpression(bound)
		If Not loweredOperand Then Return Null
		Local materialization:TCompilerIrMaterialize = TCompilerIrMaterialize(loweredOperand)
		If materialization Then
			truth.operand = materialization.expression
			materialization.expression = truth
			materialization.semanticType = "Int"
		Else
			truth.operand = loweredOperand
		End If
		truth.returnType = TypeName(callableType.returnType)
		truth.parameters = CallableParameters(callableType)
		truth.callingConvention = callableType.callingConvention
		truth.negate = negate
		If materialization Then Return materialization
		Return truth
	End Method

	Method IsCallableStorageReference:Int(bound:TBoundExpression)
		Local symbol:TBoundSymbolExpression = TBoundSymbolExpression(bound)
		If symbol And symbol.symbol And TCallableSemanticType(bound.semanticType) Then
			If symbol.symbol.kind = SYMBOL_PARAMETER Or symbol.symbol.kind = SYMBOL_LOCAL Or symbol.symbol.kind = SYMBOL_GLOBAL Then Return True
			If symbol.symbol.kind = SYMBOL_FIELD And (fieldsBySymbol.Contains(symbol.symbol) Or IsImportedFieldSymbol(symbol.symbol)) Then Return True
		End If
		Local member:TBoundMemberExpression = TBoundMemberExpression(bound)
		Return member And member.access And member.access.member And TCallableSemanticType(bound.semanticType) And (fieldsBySymbol.Contains(member.access.member) Or IsImportedFieldSymbol(member.access.member))
	End Method

	Method LowerInterfaceCall:TCompilerIrExpression(call:TBoundCallExpression, irInterface:TCompilerIrInterface, interfaceMethod:TCompilerIrInterfaceMethod, bound:TBoundExpression)
		If Not call.receiver Or Not irInterface Then
			AddUnsupported("BMXC1165", "Interface call did not retain a source Interface receiver", bound.syntax)
			Return Null
		End If
		Local resultCall:TCompilerIrCall = New TCompilerIrCall
		InitializeExpression(resultCall, IR_EXPRESSION_CALL, bound)
		resultCall.functionId = irInterface.interfaceId + "." + interfaceMethod.slotId
		resultCall.functionName = interfaceMethod.name
		resultCall.dispatchKind = IR_CALL_DISPATCH_INTERFACE
		resultCall.interfaceId = irInterface.interfaceId
		resultCall.interfaceSlotId = interfaceMethod.slotId
		Local loweredReceiver:TCompilerIrExpression = LowerExpression(call.receiver)
		If Not loweredReceiver Then Return Null
		Local materialization:TCompilerIrMaterialize
		If IsStableReceiver(loweredReceiver) Then
			resultCall.receiver = loweredReceiver
		Else
			materialization = BeginMaterialization(loweredReceiver, bound.syntax)
			resultCall.receiver = TemporaryReference(materialization, call.receiver, bound.syntax)
		End If
		Local argumentsSucceeded:Int
		resultCall.arguments = LowerResolvedArguments(call.arguments, call.resolvedCall.routine, bound.syntax, argumentsSucceeded, call.resolvedCall)
		If Not argumentsSucceeded Then Return Null
		If materialization Then
			materialization.expression = resultCall
			materialization.semanticType = resultCall.semanticType
			Return materialization
		End If
		Return resultCall
	End Method

	Method LowerInterfaceSuperCall:TCompilerIrExpression(call:TBoundCallExpression, irInterface:TCompilerIrInterface, interfaceMethod:TCompilerIrInterfaceMethod, bound:TBoundExpression)
		If Not call.resolvedCall Or Not call.resolvedCall.routine Or call.resolvedCall.routine.interfaceMethodKind <> INTERFACE_METHOD_DEFAULT Then
			AddUnsupported("BMXC1168", "Qualified Interface Super call must select a Default method body", bound.syntax)
			Return Null
		End If
		Local target:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(call.resolvedCall.routine))
		Local targetAbiName:String
		If Not target Then targetAbiName = call.resolvedCall.routine.externalName
		If Not target And Not targetAbiName.length Then
			AddUnsupported("BMXC1168", "Qualified Interface Super call has no published default implementation", bound.syntax)
			Return Null
		End If
		Local resultCall:TCompilerIrCall = New TCompilerIrCall
		InitializeExpression(resultCall, IR_EXPRESSION_CALL, bound)
		resultCall.dispatchKind = IR_CALL_DISPATCH_INTERFACE_SUPER
		If target Then resultCall.functionId = target.functionId Else resultCall.functionAbiName = targetAbiName
		resultCall.functionName = interfaceMethod.name
		resultCall.receiver = LowerExpression(call.receiver)
		If Not resultCall.receiver Then Return Null
		Local argumentsSucceeded:Int
		resultCall.arguments = LowerResolvedArguments(call.arguments, call.resolvedCall.routine, bound.syntax, argumentsSucceeded, call.resolvedCall)
		If Not argumentsSucceeded Then Return Null
		Return resultCall
	End Method

	Method LowerFieldAccess:TCompilerIrExpression(receiver:TBoundExpression, symbol:TSymbol, bound:TBoundExpression)
		Local receiverLayoutType:TSemanticType = receiver.semanticType
		Local receiverPointer:TPointerSemanticType = TPointerSemanticType(receiver.semanticType)
		If receiverPointer Then receiverLayoutType = receiverPointer.elementType
		Local irField:TCompilerIrClassField = TCompilerIrClassField(fieldsBySymbol.ValueForKey(symbol))
		Local structField:TCompilerIrStructField = TCompilerIrStructField(structFieldsBySymbol.ValueForKey(symbol))
		Local importedStructField:TCompilerIrImportedField
		If IsImportedStructFieldSymbol(symbol) Then
			Local importedStructOwner:TCompilerIrImportedStruct = ImportedStructForType(receiverLayoutType)
			If importedStructOwner And importedStructOwner.isGenericSpecialization Then
				importedStructField = GenericImportedStructField(importedStructOwner, symbol)
			Else
				importedStructOwner = EnsureImportedStruct(symbol.containingScope.owner)
				If importedStructOwner Then importedStructField = TCompilerIrImportedField(importedStructFieldsBySymbol.ValueForKey(symbol))
			End If
		End If
		If Not structField Then
			If Not importedStructField Then
				Local genericStructOwner:TCompilerIrImportedStruct = TCompilerIrImportedStruct(genericStructsByTypeName.ValueForKey(TypeName(receiver.semanticType).ToLower()))
				If genericStructOwner Then importedStructField = GenericImportedStructField(genericStructOwner, symbol)
			End If
		End If
		Local importedFieldRecord:TCompilerIrImportedField
		If Not irField And Not structField And Not importedStructField And IsImportedFieldSymbol(symbol) Then
			Local genericOwner:TCompilerIrImportedClass = ImportedClassForType(receiver.semanticType)
			If Not genericOwner Or Not genericOwner.isGenericSpecialization Then genericOwner = GenericImportedBaseForType(receiver.semanticType, symbol.containingScope.owner)
			If genericOwner And genericOwner.isGenericSpecialization Then
				importedFieldRecord = GenericImportedField(genericOwner, symbol)
			Else
				importedFieldRecord = ImportedField(symbol, bound.syntax)
			End If
			If Not importedFieldRecord Then Return Null
		End If
		If Not irField And Not structField And Not importedStructField And Not importedFieldRecord Then
			Local genericOwner:TCompilerIrImportedClass = ImportedClassForType(receiver.semanticType)
			If Not genericOwner Or Not genericOwner.isGenericSpecialization Then genericOwner = GenericImportedBaseForType(receiver.semanticType, symbol.containingScope.owner)
			If genericOwner And genericOwner.isGenericSpecialization Then importedFieldRecord = GenericImportedField(genericOwner, symbol)
		End If
		Local owner:TCompilerIrClass
		Local ownerStruct:TCompilerIrStruct
		Local importedOwnerStruct:TCompilerIrImportedStruct
		Local importedOwner:TCompilerIrImportedClass
		If irField Then owner = ClassForType(receiver.semanticType)
		If structField Then ownerStruct = StructForType(receiverLayoutType)
		If importedStructField Then importedOwnerStruct = ImportedStructForType(receiverLayoutType)
		If importedFieldRecord Then importedOwner = ImportedClassForType(receiver.semanticType)
		If importedFieldRecord And Not importedOwner Then
			owner = ClassForType(receiver.semanticType)
			If owner And Not ClassDerivesFromImported(owner, importedFieldRecord.declaringImportedClassId) Then owner = Null
		End If
		If (irField And Not owner) Or (structField And Not ownerStruct) Or (importedStructField And Not importedOwnerStruct) Or (importedFieldRecord And Not importedOwner And Not owner) Then
			Local layoutDetail:String = "receiver '" + TypeName(receiverLayoutType) + "'"
			If importedFieldRecord Then
				layoutDetail :+ ", declaring imported class '" + importedFieldRecord.declaringImportedClassId + "'"
				Local declaringLayout:TCompilerIrImportedClass = ImportedClassById(importedFieldRecord.declaringImportedClassId)
				If declaringLayout Then layoutDetail :+ " (" + declaringLayout.name + ", " + declaringLayout.abiName + ")"
			End If
			Local sourceLayout:TCompilerIrClass = ClassForType(receiverLayoutType)
			If sourceLayout Then
				layoutDetail :+ ", source imported base '" + sourceLayout.baseImportedClassId + "'"
				Local sourceBaseLayout:TCompilerIrImportedClass = ImportedClassById(sourceLayout.baseImportedClassId)
				If sourceBaseLayout Then layoutDetail :+ " (" + sourceBaseLayout.name + ", " + sourceBaseLayout.abiName + ")"
			End If
			AddUnsupported("BMXC1146", "Field access is outside the lowered object layout (" + layoutDetail + ")", bound.syntax)
			Return Null
		End If
		Local access:TCompilerIrFieldAccess = New TCompilerIrFieldAccess
		InitializeExpression(access, IR_EXPRESSION_FIELD, bound)
		access.receiverIsPointer = receiverPointer <> Null
		Local loweredReceiver:TCompilerIrExpression = LowerExpression(receiver)
		If Not loweredReceiver Then Return Null
		Local materialization:TCompilerIrMaterialize = TCompilerIrMaterialize(loweredReceiver)
		If materialization Then
			' A C comma expression is not an lvalue. Keep sequencing outside
			' nested field access so assignments and Var arguments remain
			' addressable after materializing their object receiver.
			access.receiver = materialization.expression
		Else If IsStableReceiver(loweredReceiver) Or (preserveStructLValue And (structField Or importedStructField)) Then
			access.receiver = loweredReceiver
		Else
			materialization = BeginMaterialization(loweredReceiver, bound.syntax)
			access.receiver = TemporaryReference(materialization, receiver, bound.syntax)
		End If
		If importedFieldRecord Then
			access.importedFieldId = importedFieldRecord.fieldId
		Else If importedStructField Then
			access.importedFieldId = importedStructField.fieldId
			access.importedStructId = importedOwnerStruct.importedStructId
		Else If structField Then
			access.structId = ownerStruct.structId
			access.fieldId = structField.fieldId
		Else
			access.classId = irField.declaringClassId
			access.fieldId = irField.fieldId
		End If
		If materialization Then
			materialization.expression = access
			materialization.semanticType = access.semanticType
			Return materialization
		End If
		Return access
	End Method

	Method GenericImportedStructField:TCompilerIrImportedField(importedStruct:TCompilerIrImportedStruct, symbol:TSymbol)
		If Not importedStruct Then Return Null
		If Not symbol Then Return Null
		For Local fieldRecord:TCompilerIrImportedField = EachIn importedStruct.fields
			If fieldRecord.name.ToLower() = symbol.name.ToLower() Then Return fieldRecord
		Next
		Return Null
	End Method

	Method GenericImportedField:TCompilerIrImportedField(importedClass:TCompilerIrImportedClass, symbol:TSymbol)
		If Not importedClass Or Not symbol Then Return Null
		Local declaringClass:TCompilerIrImportedClass = GenericDeclaringClass(importedClass, symbol)
		For Local fieldRecord:TCompilerIrImportedField = EachIn importedClass.fields
			If fieldRecord.name.ToLower() <> symbol.name.ToLower() Then Continue
			If declaringClass And fieldRecord.declaringImportedClassId <> declaringClass.importedClassId Then Continue
			Return fieldRecord
		Next
		Return Null
	End Method

	Method GenericDeclaringClass:TCompilerIrImportedClass(importedClass:TCompilerIrImportedClass, symbol:TSymbol)
		If Not importedClass Or Not symbol Or Not symbol.containingScope Or Not symbol.containingScope.owner Then Return Null
		Local ownerName:String = symbol.containingScope.owner.QualifiedName().ToLower()
		Local current:TCompilerIrImportedClass = importedClass
		While current
			If current.name.ToLower() = ownerName Then Return current
			If Not current.baseImportedClassId.length Then Exit
			current = ImportedClassById(current.baseImportedClassId)
		Wend
		Return Null
	End Method

	Method ClassDerivesFromImported:Int(irClass:TCompilerIrClass, importedClassId:String)
		If Not irClass Or Not importedClassId.length Then Return False
		If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			If ImportedClassDerivesFrom(importedBase, importedClassId) Then Return True
		End If
		If irClass.baseClassId.length Then Return ClassDerivesFromImported(ClassById(irClass.baseClassId), importedClassId)
		Return False
	End Method

	Method ImportedClassDerivesFrom:Int(importedClass:TCompilerIrImportedClass, importedClassId:String)
		If Not importedClass Or Not importedClassId.length Then Return False
		If importedClass.importedClassId = importedClassId Then Return True
		If importedClass.baseImportedClassId.length Then Return ImportedClassDerivesFrom(ImportedClassById(importedClass.baseImportedClassId), importedClassId)
		Return False
	End Method

	Method ImportedField:TCompilerIrImportedField(symbol:TSymbol, useSyntax:TSyntaxNode)
		If Not IsImportedFieldSymbol(symbol) Then Return Null
		Local known:TCompilerIrImportedField = TCompilerIrImportedField(importedFieldsBySymbol.ValueForKey(symbol))
		If known Then Return known
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(symbol.declaredType)
		If Not IsSupportedAbiParameterType(symbol.declaredType) And Not IsSupportedStaticArrayType(staticArrayType) Then
			AddUnsupported("BMXC1182", "Imported field type '" + TypeName(symbol.declaredType) + "' is outside the current value ABI slice", useSyntax)
			Return Null
		End If
		Local owner:TSymbol = symbol.containingScope.owner
		Local importedClass:TCompilerIrImportedClass = EnsureImportedClass(owner)
		If Not importedClass Then Return Null
		Local fieldRecord:TCompilerIrImportedField = New TCompilerIrImportedField
		fieldRecord.fieldId = "icf" + nextImportedFieldId
		nextImportedFieldId :+ 1
		fieldRecord.declaringImportedClassId = importedClass.importedClassId
		fieldRecord.name = symbol.name
		fieldRecord.abiName = TCompilerAbiNamer.Sanitize("_" + owner.externalName.ToLower() + "_" + symbol.name.ToLower())
		fieldRecord.semanticType = TypeName(symbol.declaredType)
		If staticArrayType Then
			fieldRecord.isStaticArray = True
			fieldRecord.staticArrayElementType = TypeName(staticArrayType.elementType)
			fieldRecord.staticArrayLength = staticArrayType.length
			Local staticElementStruct:TCompilerIrStruct = StructForType(staticArrayType.elementType)
			Local staticElementImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(staticArrayType.elementType)
			If staticElementStruct Then fieldRecord.staticArrayStructId = staticElementStruct.structId
			If staticElementImportedStruct Then fieldRecord.staticArrayImportedStructId = staticElementImportedStruct.importedStructId
			If IsManagedReferenceType(staticArrayType.elementType) Then importedClass.hasManagedFields = True
			If staticElementStruct And staticElementStruct.containsManagedReferences Then importedClass.hasManagedFields = True
			If staticElementImportedStruct And staticElementImportedStruct.containsManagedReferences Then importedClass.hasManagedFields = True
		End If
		Local callableType:TCallableSemanticType = TCallableSemanticType(symbol.declaredType)
		If callableType Then
			fieldRecord.callableReturnType = TypeName(callableType.returnType)
			fieldRecord.callableParameters = CallableParameters(callableType)
			fieldRecord.callableCallingConvention = callableType.callingConvention
		End If
		fieldRecord.visibility = symbol.visibility
		fieldRecord.isReadOnly = symbol.isReadOnly
		fieldRecord.source = SourceForSymbol(symbol)
		If symbol.originPath.length Then fieldRecord.source.path = symbol.originPath
		fieldRecord.metadata = MetadataOf(symbol)
		importedFieldsBySymbol.Insert(symbol, fieldRecord)
		importedClass.fields :+ [fieldRecord]
		Return fieldRecord
	End Method

	Function IsImportedFieldSymbol:Int(symbol:TSymbol)
		Return symbol And symbol.kind = SYMBOL_FIELD And symbol.isImported And symbol.containingScope And symbol.containingScope.owner And symbol.containingScope.owner.kind = SYMBOL_TYPE And symbol.containingScope.owner.isImported
	End Function

	Function IsImportedStructFieldSymbol:Int(symbol:TSymbol)
		Return symbol And symbol.kind = SYMBOL_FIELD And symbol.isImported And symbol.containingScope And symbol.containingScope.owner And symbol.containingScope.owner.kind = SYMBOL_STRUCT And symbol.containingScope.owner.isImported
	End Function

	Method IsStableReceiver:Int(expression:TCompilerIrExpression)
		Return TCompilerIrSymbolReference(expression) <> Null
	End Method

	Method IsStableBoundReceiver:Int(expression:TBoundExpression)
		If TBoundSelfExpression(expression) Then Return True
		If TBoundSymbolExpression(expression) Then Return True
		Local conversion:TBoundConversionExpression = TBoundConversionExpression(expression)
		If conversion And conversion.operand Then Return IsStableBoundReceiver(conversion.operand)
		Local passthrough:TBoundPassthroughExpression = TBoundPassthroughExpression(expression)
		If passthrough And passthrough.operand Then Return IsStableBoundReceiver(passthrough.operand)
		Local member:TBoundMemberExpression = TBoundMemberExpression(expression)
		Return member And member.receiver And member.access And member.access.member And member.access.member.kind = SYMBOL_FIELD And IsStableBoundReceiver(member.receiver)
	End Method

	Method IsStableBoundIndexTarget:Int(indexed:TBoundIndexExpression)
		If Not indexed Or Not indexed.receiver Or Not IsStableBoundReceiver(indexed.receiver) Then Return False
		For Local index:TBoundExpression = EachIn indexed.indexes
			If Not TBoundLiteralExpression(index) And Not IsStableBoundReceiver(index) Then Return False
		Next
		Return True
	End Method

	Function IsStaticMemberQualifier:Int(expression:TBoundExpression)
		If TBoundSelfExpression(expression) Then Return True
		Local symbol:TBoundSymbolExpression = TBoundSymbolExpression(expression)
		If Not symbol Or Not symbol.symbol Then Return False
		Return symbol.symbol.kind = SYMBOL_TYPE Or symbol.symbol.kind = SYMBOL_STRUCT Or symbol.symbol.kind = SYMBOL_INTERFACE Or symbol.symbol.kind = SYMBOL_MODULE
	End Function

	Method IsAddressableExpression:Int(expression:TCompilerIrExpression)
		Return TCompilerIrSymbolReference(expression) <> Null Or TCompilerIrFieldAccess(expression) <> Null Or TCompilerIrArrayElement(expression) <> Null
	End Method

	Method LowerAddressableExpression:TCompilerIrExpression(expression:TBoundExpression)
		' Existing loop variables may retain an identity type ascription from
		' legacy headers such as `For index:Int = ...`. The ascription describes
		' the target but does not turn its storage into a converted temporary.
		Local value:TBoundExpression = expression
		Local conversion:TBoundConversionExpression = TBoundConversionExpression(value)
		While conversion And conversion.conversionKind = CONVERSION_IDENTITY
			value = conversion.operand
			conversion = TBoundConversionExpression(value)
		Wend
		Return LowerExpression(value)
	End Method

	Method BeginMaterialization:TCompilerIrMaterialize(value:TCompilerIrExpression, syntax:TSyntaxNode)
		Local materialization:TCompilerIrMaterialize = New TCompilerIrMaterialize
		materialization.kind = IR_EXPRESSION_MATERIALIZE
		materialization.source = SourceOf(syntax)
		materialization.temporaryId = NewTemporaryId()
		materialization.temporaryType = value.semanticType
		materialization.value = value
		Return materialization
	End Method

	Method SequenceStringConcat:TCompilerIrExpression(concat:TCompilerIrStringConcat, syntax:TSyntaxNode)
		If Not concat Or Not concat.left Then Return concat
		' A concatenation allocates. Materialize its left operand before evaluating
		' the right so managed backends can root the value across a second nested
		' concatenation or allocation-capable call.
		Local materialization:TCompilerIrMaterialize = BeginMaterialization(concat.left, syntax)
		concat.left = TemporaryReference(materialization, Null, syntax, "string_left")
		materialization.expression = concat
		materialization.semanticType = concat.semanticType
		Return materialization
	End Method

	Method SequenceResolvedArguments:TCompilerIrExpression(owner:TCompilerIrExpression, arguments:TCompilerIrExpression[], routine:TSymbol, syntax:TSyntaxNode, resolvedParameters:TCompilerIrParameter[] = Null)
		If Not owner Or Not routine Or arguments.length < 2 Then Return owner
		Local requiresSequencing:Int
		For Local argument:TCompilerIrExpression = EachIn arguments
			If CallArgumentHasEvaluationEffect(argument) Then
				requiresSequencing = True
				Exit
			End If
		Next
		If Not requiresSequencing Then Return owner
		' C leaves function-argument evaluation order unspecified. Preserve the
		' language's left-to-right rule in shared IR whenever an argument is a
		' computed expression. Var arguments remain address expressions until the
		' IR has a distinct pointer-temporary type.
		Local materializations:TCompilerIrMaterialize[] = New TCompilerIrMaterialize[arguments.length]
		Local parameterCount:Int = routine.parameters.length
		If resolvedParameters Then parameterCount = resolvedParameters.length
		Local parameterOffset:Int = arguments.length - parameterCount
		For Local index:Int = 0 Until arguments.length
			If TCompilerIrAddressOf(arguments[index]) Then Continue
			Local addressValue:TCompilerIrAddressOf = MaterializedAddressExpression(arguments[index])
			Local parameterIndex:Int = index - parameterOffset
			Local callableType:TCallableSemanticType
			Local resolvedParameter:TCompilerIrParameter
			If resolvedParameters And parameterIndex >= 0 And parameterIndex < resolvedParameters.length Then resolvedParameter = resolvedParameters[parameterIndex]
			If Not resolvedParameter And parameterIndex >= 0 And parameterIndex < routine.parameters.length Then callableType = TCallableSemanticType(routine.parameters[parameterIndex].semanticType)
			' Callable Var values still need a declarator-aware pointer temporary.
			' Preserve their address expression until that representation exists.
			If addressValue And (callableType Or (resolvedParameter And resolvedParameter.callableReturnType.length)) Then Continue
			Local materialization:TCompilerIrMaterialize = BeginMaterialization(arguments[index], syntax)
			If addressValue Then materialization.temporaryIsAddress = True
			If resolvedParameter And resolvedParameter.callableReturnType.length Then
				materialization.temporaryCallableReturnType = resolvedParameter.callableReturnType
				materialization.temporaryCallableParameters = resolvedParameter.callableParameters
				materialization.temporaryCallableCallingConvention = resolvedParameter.callableCallingConvention
			Else If parameterIndex >= 0 And parameterIndex < routine.parameters.length Then
				If callableType Then
					materialization.temporaryCallableReturnType = TypeName(callableType.returnType)
					materialization.temporaryCallableParameters = CallableParameters(callableType)
					materialization.temporaryCallableCallingConvention = callableType.callingConvention
				End If
			End If
			materializations[index] = materialization
			arguments[index] = TemporaryReference(materialization, Null, syntax, "argument")
		Next
		Local result:TCompilerIrExpression = owner
		For Local index:Int = materializations.length - 1 To 0 Step -1
			Local materialization:TCompilerIrMaterialize = materializations[index]
			If Not materialization Then Continue
			materialization.expression = result
			materialization.semanticType = owner.semanticType
			result = materialization
		Next
		Return result
	End Method

	Method SequenceIndirectCall:TCompilerIrExpression(call:TCompilerIrIndirectCall, syntax:TSyntaxNode)
		If Not call Or call.arguments.length = 0 Then Return call
		Local requiresSequencing:Int = CallArgumentHasEvaluationEffect(call.callee)
		For Local argument:TCompilerIrExpression = EachIn call.arguments
			If CallArgumentHasEvaluationEffect(argument) Then
				requiresSequencing = True
				Exit
			End If
		Next
		If Not requiresSequencing Then Return call

		' The callable expression is evaluated before its arguments in BlitzMax,
		' but C does not order the callee and argument subexpressions either.
		Local calleeMaterialization:TCompilerIrMaterialize = BeginMaterialization(call.callee, syntax)
		Local externalCallee:TCompilerIrSymbolReference = TCompilerIrSymbolReference(call.callee)
		If externalCallee And externalCallee.nativeCallableAbiName.length Then
			calleeMaterialization.temporaryNativeCallableAbiName = externalCallee.nativeCallableAbiName
		Else
			calleeMaterialization.temporaryCallableReturnType = call.returnType
			calleeMaterialization.temporaryCallableParameters = call.parameters
			calleeMaterialization.temporaryCallableCallingConvention = call.callingConvention
		End If
		call.callee = TemporaryReference(calleeMaterialization, Null, syntax, "callable")

		Local materializations:TCompilerIrMaterialize[] = New TCompilerIrMaterialize[call.arguments.length]
		For Local index:Int = 0 Until call.arguments.length
			If TCompilerIrAddressOf(call.arguments[index]) Then Continue
			Local addressValue:TCompilerIrAddressOf = MaterializedAddressExpression(call.arguments[index])
			If addressValue And index < call.parameters.length And call.parameters[index].callableReturnType.length Then Continue
			Local materialization:TCompilerIrMaterialize = BeginMaterialization(call.arguments[index], syntax)
			If addressValue Then materialization.temporaryIsAddress = True
			If index < call.parameters.length And call.parameters[index].callableReturnType.length Then
				materialization.temporaryCallableReturnType = call.parameters[index].callableReturnType
				materialization.temporaryCallableParameters = call.parameters[index].callableParameters
				materialization.temporaryCallableCallingConvention = call.parameters[index].callableCallingConvention
			End If
			materializations[index] = materialization
			call.arguments[index] = TemporaryReference(materialization, Null, syntax, "argument")
		Next

		Local result:TCompilerIrExpression = call
		For Local index:Int = materializations.length - 1 To 0 Step -1
			Local materialization:TCompilerIrMaterialize = materializations[index]
			If Not materialization Then Continue
			materialization.expression = result
			materialization.semanticType = call.semanticType
			result = materialization
		Next
		calleeMaterialization.expression = result
		calleeMaterialization.semanticType = call.semanticType
		Return calleeMaterialization
	End Method

	Function MaterializedAddressExpression:TCompilerIrAddressOf(expression:TCompilerIrExpression)
		Local current:TCompilerIrExpression = expression
		Local materialization:TCompilerIrMaterialize = TCompilerIrMaterialize(current)
		While materialization
			current = materialization.expression
			materialization = TCompilerIrMaterialize(current)
		Wend
		Return TCompilerIrAddressOf(current)
	End Function

	Function CallArgumentHasEvaluationEffect:Int(argument:TCompilerIrExpression)
		If TCompilerIrCall(argument) Or TCompilerIrIndirectCall(argument) Or TCompilerIrClosureCall(argument) Or TCompilerIrMaterialize(argument) Or TCompilerIrObjectNew(argument) Or TCompilerIrStructNew(argument) Then Return True
		Local closureLiteral:TCompilerIrClosureLiteral = TCompilerIrClosureLiteral(argument)
		If closureLiteral Then Return closureLiteral.environment <> Null
		Local binary:TCompilerIrBinary = TCompilerIrBinary(argument)
		If binary Then Return CallArgumentHasEvaluationEffect(binary.left) Or CallArgumentHasEvaluationEffect(binary.right)
		Local pointerBinary:TCompilerIrPointerBinary = TCompilerIrPointerBinary(argument)
		If pointerBinary Then Return CallArgumentHasEvaluationEffect(pointerBinary.left) Or CallArgumentHasEvaluationEffect(pointerBinary.right)
		Local concat:TCompilerIrStringConcat = TCompilerIrStringConcat(argument)
		If concat Then Return CallArgumentHasEvaluationEffect(concat.left) Or CallArgumentHasEvaluationEffect(concat.right)
		Local comparison:TCompilerIrStringCompare = TCompilerIrStringCompare(argument)
		If comparison Then Return CallArgumentHasEvaluationEffect(comparison.left) Or CallArgumentHasEvaluationEffect(comparison.right)
		Local conversion:TCompilerIrConversion = TCompilerIrConversion(argument)
		If conversion Then Return CallArgumentHasEvaluationEffect(conversion.operand)
		Local fieldAccess:TCompilerIrFieldAccess = TCompilerIrFieldAccess(argument)
		If fieldAccess Then Return CallArgumentHasEvaluationEffect(fieldAccess.receiver)
		Local address:TCompilerIrAddressOf = TCompilerIrAddressOf(argument)
		If address Then Return CallArgumentHasEvaluationEffect(address.operand)
		Return False
	End Function

	Method AddressOfExpression:TCompilerIrExpression(operand:TCompilerIrExpression, semanticType:String, source:TCompilerSourceLocation)
		Local address:TCompilerIrAddressOf = New TCompilerIrAddressOf
		address.kind = IR_EXPRESSION_ADDRESS_OF
		address.semanticType = semanticType
		address.source = source
		' A reference-compatible Var argument describes a pointer conversion on
		' the address of the original storage, not a value conversion whose
		' temporary result can be addressed.
		Local referenceConversion:TCompilerIrConversion = TCompilerIrConversion(operand)
		If referenceConversion And referenceConversion.conversionKind = CONVERSION_VAR_REFERENCE Then
			operand = referenceConversion.operand
			address.castStorageAddress = True
		End If
		Local materialization:TCompilerIrMaterialize = TCompilerIrMaterialize(operand)
		If materialization Then
			address.operand = materialization.expression
			materialization.expression = address
			materialization.semanticType = semanticType
			Return materialization
		End If
		address.operand = operand
		Return address
	End Method

	Method TemporaryReference:TCompilerIrSymbolReference(materialization:TCompilerIrMaterialize, bound:TBoundExpression, syntax:TSyntaxNode, name:String = "receiver")
		Local reference:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		reference.kind = IR_EXPRESSION_SYMBOL
		reference.semanticType = materialization.temporaryType
		reference.source = SourceOf(syntax)
		reference.symbolId = materialization.temporaryId
		reference.name = name
		Return reference
	End Method

	Method LowerCondition:TCompilerIrExpression(bound:TBoundExpression)
		If TCallableSemanticType(bound.semanticType) Then Return CallableTruth(bound, False, bound.syntax)
		If TClosureSemanticType(bound.semanticType) Then Return ManagedTruth(bound, False, bound.syntax, IR_MANAGED_REFERENCE_CLOSURE)
		If IsStringType(bound.semanticType) Then Return ManagedTruth(bound, False, bound.syntax)
		If IsArrayType(bound.semanticType) Then Return ManagedTruth(bound, False, bound.syntax, IR_MANAGED_REFERENCE_ARRAY)
		If IsObjectReferenceType(bound.semanticType) Then Return ManagedTruth(bound, False, bound.syntax, IR_MANAGED_REFERENCE_OBJECT)
		If StructForType(bound.semanticType) Or ImportedStructForType(bound.semanticType) Then Return StructTruth(False, bound.syntax)
		Return LowerExpression(bound)
	End Method

	Method LowerContextualExpression:TCompilerIrExpression(bound:TBoundExpression, targetType:TSemanticType)
		If Not bound Or Not IsNullType(bound.semanticType) Then Return LowerExpression(bound)
		If IsStringType(targetType) Then Return ManagedDefault(TypeName(targetType), IR_MANAGED_REFERENCE_STRING, SourceOf(bound.syntax))
		If IsArrayType(targetType) Then Return ManagedDefault(TypeName(targetType), IR_MANAGED_REFERENCE_ARRAY, SourceOf(bound.syntax))
		If TClosureSemanticType(targetType) Then Return ManagedDefault(TypeName(targetType), IR_MANAGED_REFERENCE_CLOSURE, SourceOf(bound.syntax))
		If IsExternInterfaceType(targetType) Then Return ScalarDefault(TypeName(targetType), SourceOf(bound.syntax))
		' Null conversion depends on the semantic managed-value category, not on
		' whether an imported class layout happened to be materialized already.
		' Every nominal Type and Interface uses the object sentinel invariant.
		If IsManagedReferenceType(targetType) Then Return ManagedDefault(TypeName(targetType), IR_MANAGED_REFERENCE_OBJECT, SourceOf(bound.syntax))
		If IsPointerType(targetType) Or TCallableSemanticType(targetType) Then Return ScalarDefault(TypeName(targetType), SourceOf(bound.syntax))
		If IsNumericType(targetType) Or EnumForType(targetType) Then Return ScalarDefault(TypeName(targetType), SourceOf(bound.syntax))
		Return LowerExpression(bound)
	End Method

	Method LowerAssertMessage:TCompilerIrExpression(bound:TBoundExpression, syntax:TSyntaxNode)
		If IsStringType(bound.semanticType) Then Return LowerExpression(bound)
		Local messageEnum:TCompilerIrEnum = EnumForType(bound.semanticType)
		If messageEnum Then
			Local enumToString:TCompilerIrEnumIntrinsic = New TCompilerIrEnumIntrinsic
			enumToString.kind = IR_EXPRESSION_ENUM_INTRINSIC
			enumToString.semanticType = "String"
			enumToString.source = SourceOf(bound.syntax)
			enumToString.intrinsicKind = IR_ENUM_INTRINSIC_TO_STRING
			enumToString.enumId = messageEnum.enumId
			enumToString.receiver = LowerExpression(bound)
			Return enumToString
		End If
		If IsNumericType(bound.semanticType) Then Return LowerStringOperand(bound)
		AddUnsupported("BMXC1205", "Assert message type '" + TypeName(bound.semanticType) + "' cannot be converted to String by the current IR", syntax)
		Return Null
	End Method

	Method StringValueExpression:TCompilerIrLiteral(value:String, source:TCompilerSourceLocation)
		Local literal:TCompilerIrLiteral = New TCompilerIrLiteral
		literal.kind = IR_EXPRESSION_LITERAL
		literal.semanticType = "String"
		literal.source = source
		literal.stringLiteralId = RegisterStringValue(value, source).literalId
		Return literal
	End Method

	Method IsAssertConditionType:Int(semanticType:TSemanticType)
		If Not semanticType Then Return False
		If StructForType(semanticType) Or ImportedStructForType(semanticType) Or TStaticArraySemanticType(semanticType) Then Return False
		If TCallableSemanticType(semanticType) Then Return IsSupportedCallableType(TCallableSemanticType(semanticType))
		If TClosureSemanticType(semanticType) Then Return IsSupportedClosureType(TClosureSemanticType(semanticType))
		Return IsSupportedValueType(semanticType)
	End Method

	Method IsAssertMessageType:Int(semanticType:TSemanticType)
		Return IsStringType(semanticType) Or IsNumericType(semanticType) Or EnumForType(semanticType) <> Null
	End Method

	Method LowerResolvedArguments:TCompilerIrExpression[](arguments:TBoundExpression[], routine:TSymbol, useSyntax:TSyntaxNode, succeeded:Int Var, resolvedCall:TResolvedCall = Null)
		succeeded = False
		If Not routine Then
			AddUnsupported("BMXC1180", "Resolved call did not retain its selected routine while lowering arguments", useSyntax)
			Return New TCompilerIrExpression[0]
		End If
		Local resultArguments:TCompilerIrExpression[] = New TCompilerIrExpression[routine.parameters.length]
		For Local index:Int = 0 Until routine.parameters.length
			Local boundArgument:TBoundExpression
			If index < arguments.length Then boundArgument = arguments[index]
			If boundArgument And Not TBoundOmittedArgumentExpression(boundArgument) Then
				Local requiredParameterType:TSemanticType = routine.parameters[index].semanticType
				If routine.parameters[index].symbol And routine.parameters[index].symbol.declaredType Then requiredParameterType = routine.parameters[index].symbol.declaredType
				Local requiredStaticArray:TStaticArraySemanticType = TStaticArraySemanticType(requiredParameterType)
				If requiredStaticArray Then
					Local actualStaticArray:TStaticArraySemanticType = StaticArrayTypeOf(boundArgument)
					If Not actualStaticArray Or Not TGenericRoutineInference.SameType(actualStaticArray, requiredStaticArray) Then
						AddUnsupported("BMXC1022", "StaticArray argument " + index + " does not match parameter extent and element type '" + TypeName(requiredStaticArray) + "'", boundArgument.syntax)
						Return resultArguments
					End If
				End If
				Local previousPreserveArgument:Int = preserveStructLValue
				If routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then preserveStructLValue = True
				If routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then
					resultArguments[index] = LowerExpression(boundArgument)
				Else
					' The binder may retain an unconverted Null operand for a selected
					' overload. Lower it using the chosen parameter type so managed
					' sentinels and scalar defaults remain explicit in typed IR.
					resultArguments[index] = LowerContextualExpression(boundArgument, requiredParameterType)
				End If
				preserveStructLValue = previousPreserveArgument
				If routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then
					' A generic Interface method retains open parameter symbols on its
					' declaration. Calls through a closed receiver must use the selected
					' substituted parameter type for the Var-address IR identity.
					Local addressParameterType:TSemanticType = requiredParameterType
					If resolvedCall And index < resolvedCall.parameterTypes.length And resolvedCall.parameterTypes[index] Then addressParameterType = resolvedCall.parameterTypes[index]
					resultArguments[index] = AddressOfExpression(resultArguments[index], TypeName(addressParameterType), SourceOf(boundArgument.syntax))
				End If
			Else
				Local parameter:TSemanticParameter = routine.parameters[index]
				If Not parameter Or Not parameter.optional Or Not parameter.defaultValue Then
					AddUnsupported("BMXC1180", "Omitted argument for parameter " + index + " has no semantic default", useSyntax)
					Return resultArguments
				End If
				Local defaultType:TSemanticType = parameter.semanticType
				If resolvedCall And index < resolvedCall.parameterTypes.length And resolvedCall.parameterTypes[index] Then defaultType = resolvedCall.parameterTypes[index]
				resultArguments[index] = LowerConstantDefault(parameter.defaultValue, defaultType, parameter.symbol, useSyntax)
			End If
			If Not resultArguments[index] Then Return resultArguments
		Next
		succeeded = True
		Return resultArguments
	End Method

	Method NormalizeGenericManagedConstructorDefaults(arguments:TCompilerIrExpression[], parameters:TCompilerIrParameter[])
		For Local index:Int = 0 Until Min(arguments.length, parameters.length)
			Local literal:TCompilerIrLiteral = TCompilerIrLiteral(arguments[index])
			If Not literal Or literal.text <> "0" Or Not parameters[index].isOptional Then Continue
			Local parameterType:String = parameters[index].semanticType.ToLower()
			If genericInterfacesByTypeName.Contains(parameterType) Or genericClassesByTypeName.Contains(parameterType) Then
				arguments[index] = ManagedDefault(parameters[index].semanticType, IR_MANAGED_REFERENCE_OBJECT, literal.source)
			End If
		Next
	End Method

	Method LowerConstantDefault:TCompilerIrExpression(value:TConstantValue, semanticType:TSemanticType, parameterSymbol:TSymbol, useSyntax:TSyntaxNode)
		Local source:TCompilerSourceLocation = SourceForSymbol(parameterSymbol)
		If parameterSymbol And parameterSymbol.originPath.length Then source.path = parameterSymbol.originPath
		If Not source.path.length Then source = SourceOf(useSyntax)
		Select value.kind
			Case CONSTANT_VALUE_INTEGER, CONSTANT_VALUE_FLOAT
				Local literal:TCompilerIrLiteral = New TCompilerIrLiteral
				literal.kind = IR_EXPRESSION_LITERAL
				literal.semanticType = TypeName(semanticType)
				literal.source = source
				literal.text = value.DisplayValue()
				Return literal
			Case CONSTANT_VALUE_STRING
				Local literal:TCompilerIrLiteral = New TCompilerIrLiteral
				literal.kind = IR_EXPRESSION_LITERAL
				literal.semanticType = TypeName(semanticType)
				literal.source = source
				literal.text = value.DisplayValue()
				literal.stringLiteralId = RegisterStringValue(value.stringValue, source).literalId
				Return literal
			Case CONSTANT_VALUE_NULL
				Local callableType:TCallableSemanticType = TCallableSemanticType(semanticType)
				If callableType Then Return CallableDefault(callableType, source)
				If TClosureSemanticType(semanticType) Then Return ManagedDefault(TypeName(semanticType), IR_MANAGED_REFERENCE_CLOSURE, source)
				If IsStringType(semanticType) Then Return ManagedDefault(TypeName(semanticType), IR_MANAGED_REFERENCE_STRING, source)
				If IsArrayType(semanticType) Then Return ManagedDefault(TypeName(semanticType), IR_MANAGED_REFERENCE_ARRAY, source)
				If IsExternInterfaceType(semanticType) Then Return ScalarDefault(TypeName(semanticType), source)
				If IsObjectReferenceType(semanticType) Then Return ManagedDefault(TypeName(semanticType), IR_MANAGED_REFERENCE_OBJECT, source)
				Return ScalarDefault(TypeName(semanticType), source)
			Case CONSTANT_VALUE_CALLABLE
				Local callableType:TCallableSemanticType = TCallableSemanticType(semanticType)
				If Not callableType Or Not IsSupportedCallableType(callableType) Or Not value.callableSymbol Then
					AddUnsupported("BMXC1181", "Callable default argument is outside the ordinary-C function-pointer IR slice", useSyntax)
					Return Null
				End If
				Local callableReference:TCompilerIrCallableReference = CallableReferenceForSymbol(value.callableSymbol, callableType, source, useSyntax)
				If callableReference Then Return callableReference
				AddUnsupported("BMXC1181", "Callable default target must be a lowered source or imported ordinary-C free routine", useSyntax)
				Return Null
		End Select
		Return Null
	End Method

	Function DebugConstantText:String(value:TConstantValue)
		If Not value Then Return ""
		If value.kind = CONSTANT_VALUE_STRING Then Return value.stringValue
		Return value.DisplayValue()
	End Function

	Method LowerCallableReference:TCompilerIrExpression(bound:TBoundRoutineReferenceExpression)
		If Not bound Or Not bound.routine Then
			AddUnsupported("BMXC1183", "Callable reference has no resolved routine", bound.syntax)
			Return Null
		End If
		Local closureType:TClosureSemanticType = TClosureSemanticType(bound.semanticType)
		If bound.receiver Or closureType Then Return LowerBoundMethodReference(bound, closureType)
		Local callableType:TCallableSemanticType = TCallableSemanticType(bound.semanticType)
		If Not IsSupportedCallableType(callableType) Or IsInstanceMethodSymbol(bound.routine) Then
			AddUnsupported("BMXC1183", "Callable reference requires an ordinary-C-compatible free routine", bound.syntax)
			Return Null
		End If
		Local resultReference:TCompilerIrCallableReference = CallableReferenceForSymbol(bound.routine, callableType, SourceOf(bound.syntax), bound.syntax, bound.staticReceiverType, bound.typeArguments)
		If resultReference Then Return resultReference
		AddUnsupported("BMXC1183", "Callable reference target has no lowered source or imported ABI identity", bound.syntax)
		Return Null
	End Method

	Method LowerBoundMethodReference:TCompilerIrExpression(bound:TBoundRoutineReferenceExpression, closureType:TClosureSemanticType)
		If Not bound Or Not bound.routine Or Not bound.receiver Or Not closureType Or Not IsSupportedClosureType(closureType) Then
			AddUnsupported("BMXC1250", "Bound Method reference requires a supported managed Closure signature and object receiver", bound.syntax)
			Return Null
		End If
		Local receiverType:TNamedSemanticType = TNamedSemanticType(bound.receiver.semanticType)
		If Not receiverType Or Not receiverType.symbol Or (receiverType.symbol.kind <> SYMBOL_TYPE And receiverType.symbol.kind <> SYMBOL_INTERFACE) Then
			AddUnsupported("BMXC1250", "Bound Method references currently support Type and Interface receivers; Struct receiver capture semantics are not yet defined", bound.syntax)
			Return Null
		End If
		If bound.routine.genericArity Then
			AddUnsupported("BMXC1250", "Bound generic Method references require specialization-owned adapter support", bound.syntax)
			Return Null
		End If

		Local callableType:TCallableSemanticType = closureType.signature
		Local source:TCompilerSourceLocation = SourceOf(bound.syntax)
		Local environment:TCompilerIrExpression = LowerExpression(bound.receiver)
		If Not environment Then Return Null

		Local adapter:TCompilerIrFunction = New TCompilerIrFunction
		adapter.functionId = "fn" + nextFunctionId
		nextFunctionId :+ 1
		adapter.name = "$bound_method_" + bound.routine.name + "_" + adapter.functionId
		adapter.debugName = adapter.name
		adapter.returnType = TypeName(callableType.returnType)
		adapter.source = source
		' The adapter is hidden from source-level stepping, but debug builds must
		' retain the ordinary receiver Null check before reading its virtual slot.
		If options Then adapter.debugInstrumentation = options.debugInstrumentation
		adapter.suppressDebugInfo = True
		adapter.isClosureInvoke = True
		adapter.body = New TCompilerIrBlock
		adapter.body.source = source

		Local environmentParameter:TCompilerIrParameter = New TCompilerIrParameter
		environmentParameter.symbolId = adapter.functionId + "_environment"
		environmentParameter.name = "environment"
		environmentParameter.semanticType = "Object"
		adapter.parameters = [environmentParameter]
		Local callableParameters:TCompilerIrParameter[] = CallableParameters(callableType)
		Local arguments:TCompilerIrExpression[] = New TCompilerIrExpression[callableParameters.length]
		For Local index:Int = 0 Until callableParameters.length
			Local parameter:TCompilerIrParameter = callableParameters[index]
			parameter.symbolId = adapter.functionId + "_p" + index
			adapter.parameters :+ [parameter]
			arguments[index] = FusionSymbol(parameter.symbolId, parameter.name, parameter.semanticType, source)
		Next

		Local erasedReceiver:TCompilerIrSymbolReference = FusionSymbol(environmentParameter.symbolId, environmentParameter.name, "Object", source)
		Local receiver:TCompilerIrConversion = New TCompilerIrConversion
		receiver.kind = IR_EXPRESSION_CONVERSION
		receiver.semanticType = TypeName(bound.receiver.semanticType)
		receiver.source = source
		receiver.conversionKind = CONVERSION_REFERENCE
		receiver.implicitConversion = True
		receiver.operand = erasedReceiver
		Local resolved:TResolvedCall = New TResolvedCall
		resolved.routine = bound.routine
		resolved.parameterTypes = callableType.parameterTypes
		resolved.returnType = callableType.returnType
		resolved.omittedArguments = New Int[callableType.parameterTypes.length]
		Local invocation:TCompilerIrExpression = LowerReceiverMethodCall(resolved, receiver, bound.receiver.semanticType, arguments, bound.syntax)
		If Not invocation Then Return Null
		If IsVoidType(callableType.returnType) Then
			adapter.body.statements = [FusionExpressionStatement(invocation, source)]
		Else
			adapter.body.statements = [FusionReturn(invocation, source)]
		End If
		result.functions :+ [adapter]

		Local literal:TCompilerIrClosureLiteral = New TCompilerIrClosureLiteral
		literal.kind = IR_EXPRESSION_CLOSURE_LITERAL
		literal.semanticType = TypeName(closureType)
		literal.source = source
		literal.literalId = adapter.functionId
		literal.functionId = adapter.functionId
		literal.returnType = adapter.returnType
		literal.parameters = callableParameters
		literal.environment = environment
		result.closureLiterals :+ [literal]
		Return literal
	End Method

	Method LowerFunctionLiteral:TCompilerIrExpression(bound:TBoundFunctionLiteralExpression)
		If Not bound Or Not bound.routine Then
			AddUnsupported("BMXC1241", "Function literal has no synthesized routine", bound.syntax)
			Return Null
		End If
		Local callableType:TCallableSemanticType = TCallableSemanticType(bound.semanticType)
		Local closureType:TClosureSemanticType = TClosureSemanticType(bound.semanticType)
		If closureType Then callableType = closureType.signature
		If Not IsSupportedCallableType(callableType) Then
			AddUnsupported("BMXC1242", "Function literal target is not an ordinary-C-compatible thin callable", bound.syntax)
			Return Null
		End If
		Local reference:TCompilerIrCallableReference = CallableReferenceForSymbol(bound.routine, callableType, SourceOf(bound.syntax), bound.syntax)
		If Not reference Then
			AddUnsupported("BMXC1241", "Function literal synthesized routine has no lowered ABI identity", bound.syntax)
			Return Null
		End If
		If closureType Then
			Local literal:TCompilerIrClosureLiteral = New TCompilerIrClosureLiteral
			literal.kind = IR_EXPRESSION_CLOSURE_LITERAL
			literal.semanticType = TypeName(closureType)
			literal.source = SourceOf(bound.syntax)
			literal.literalId = reference.functionId
			literal.functionId = reference.functionId
			literal.abiName = reference.abiName
			literal.returnType = reference.returnType
			literal.parameters = reference.parameters
			Local capturePlan:TCompilerClosureCapturePlan = TCompilerClosureCapturePlan(closureCapturePlansByLiteral.ValueForKey(bound.routine))
			If capturePlan Then
				literal.environment = CaptureEnvironmentReference(capturePlan, literal.source)
				If Not literal.environment Then
					AddUnsupported("BMXC1249", "capturing Closure literal has no active synthesized environment", bound.syntax)
					Return Null
				End If
			End If
			result.closureLiterals :+ [literal]
			Local closureRoutine:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(bound.routine))
			If closureRoutine Then closureRoutine.isClosureInvoke = True
			Return literal
		End If
		reference.isFunctionLiteral = True
		Return reference
	End Method

	Method CallableReferenceForSymbol:TCompilerIrCallableReference(routine:TSymbol, callableType:TCallableSemanticType, source:TCompilerSourceLocation, useSyntax:TSyntaxNode, staticReceiverType:TSemanticType = Null, typeArguments:TSemanticType[] = Null)
		If Not routine Or Not IsSupportedCallableType(callableType) Or IsInstanceMethodSymbol(routine) Then Return Null
		Local resultReference:TCompilerIrCallableReference = New TCompilerIrCallableReference
		resultReference.kind = IR_EXPRESSION_CALLABLE_REFERENCE
		resultReference.semanticType = TypeName(callableType)
		resultReference.source = source
		resultReference.functionName = routine.name
		resultReference.returnType = TypeName(callableType.returnType)
		resultReference.parameters = CallableParameters(callableType)
		resultReference.callingConvention = callableType.callingConvention
		Local sourceFunction:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(routine))
		If sourceFunction And Not sourceFunction.isMethod Then
			resultReference.functionId = sourceFunction.functionId
			resultReference.abiName = sourceFunction.abiName
			Return resultReference
		End If
		If routine.genericArity > 0 And typeArguments And typeArguments.length = routine.genericArity Then
			Local genericFunction:TCompilerIrExternalFunction = GenericRoutineFunctionForBinding(routine, typeArguments, staticReceiverType)
			If genericFunction Then
				resultReference.functionId = genericFunction.functionId
				resultReference.functionName = genericFunction.sourceName
				resultReference.abiName = genericFunction.abiName
				resultReference.isExternal = True
				Return resultReference
			End If
		End If
		If staticReceiverType Then
			Local importedClass:TCompilerIrImportedClass = ImportedClassForType(staticReceiverType)
			If importedClass And importedClass.isGenericSpecialization Then
				Local importedMethod:TCompilerIrImportedMethod = GenericImportedTypeFunctionForCallable(importedClass, routine, callableType)
				If importedMethod Then
					resultReference.functionId = importedMethod.methodId
					resultReference.functionName = importedMethod.name
					resultReference.abiName = importedMethod.abiName
					resultReference.isExternal = True
					Return resultReference
				End If
			End If
		End If
		Local externalFunction:TCompilerIrExternalFunction = ExternalFunction(routine, useSyntax)
		If externalFunction Then
			resultReference.functionId = externalFunction.functionId
			resultReference.functionName = externalFunction.sourceName
			resultReference.abiName = externalFunction.abiName
			resultReference.isExternal = True
			Return resultReference
		End If
		Return Null
	End Method

	Method GenericImportedTypeFunctionForCallable:TCompilerIrImportedMethod(importedClass:TCompilerIrImportedClass, routine:TSymbol, callableType:TCallableSemanticType)
		If Not importedClass Or Not routine Or Not callableType Then Return Null
		Local match:TCompilerIrImportedMethod
		Local matchCount:Int
		For Local importedMethod:TCompilerIrImportedMethod = EachIn importedClass.methods
			If Not importedMethod.isTypeFunction Or importedMethod.name.ToLower() <> routine.name.ToLower() Then Continue
			If importedMethod.returnType.ToLower() <> TypeName(callableType.returnType).ToLower() Or importedMethod.parameters.length <> callableType.parameterTypes.length Then Continue
			Local matches:Int = True
			For Local index:Int = 0 Until importedMethod.parameters.length
				If Not GenericImportedParameterShapeMatches(importedMethod.parameters[index], callableType.parameterTypes[index]) Then matches = False; Exit
				Local mode:Int = PARAMETER_PASS_VALUE
				If index < callableType.parameterModes.length Then mode = callableType.parameterModes[index]
				If importedMethod.parameters[index].passingMode <> mode Then matches = False; Exit
			Next
			If matches Then match = importedMethod; matchCount :+ 1
		Next
		If matchCount = 1 Then Return match
		Return Null
	End Method

	Method GenericImportedStructRoutine:TCompilerIrImportedStructRoutine(importedStruct:TCompilerIrImportedStruct, symbol:TSymbol)
		If Not importedStruct Then Return Null
		If Not symbol Then Return Null
		For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
			If routine.name.ToLower() <> symbol.name.ToLower() Then Continue
			If routine.isMethod <> IsInstanceMethodSymbol(symbol) Then Continue
			If routine.parameters.length = symbol.parameters.length Then Return routine
		Next
		Return Null
	End Method

	Function IsInstanceMethodSymbol:Int(routine:TSymbol)
		If Not routine Then Return False
		If routine.interfaceRecord Then Return routine.interfaceRecord.kind = INTERFACE_RECORD_METHOD
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
		Return declaration And declaration.isMethod
	End Function

	Method ManagedTruth:TCompilerIrManagedTruth(bound:TBoundExpression, negate:Int, syntax:TSyntaxNode, managedKind:Int = IR_MANAGED_REFERENCE_STRING)
		Local truth:TCompilerIrManagedTruth = New TCompilerIrManagedTruth
		truth.kind = IR_EXPRESSION_MANAGED_TRUTH
		truth.semanticType = "Int"
		truth.source = SourceOf(syntax)
		truth.operand = LowerExpression(bound)
		truth.managedKind = managedKind
		truth.negate = negate
		Return truth
	End Method

	Method ManagedDefault:TCompilerIrManagedDefault(semanticType:String, managedKind:Int, source:TCompilerSourceLocation)
		Local value:TCompilerIrManagedDefault = New TCompilerIrManagedDefault
		value.kind = IR_EXPRESSION_MANAGED_DEFAULT
		value.semanticType = semanticType
		value.source = source
		value.managedKind = managedKind
		Return value
	End Method

	Method ScalarDefault:TCompilerIrLiteral(semanticType:String, source:TCompilerSourceLocation)
		Local value:TCompilerIrLiteral = New TCompilerIrLiteral
		value.kind = IR_EXPRESSION_LITERAL
		value.semanticType = semanticType
		value.source = source
		value.text = "0"
		Return value
	End Method

	Method StructTruth:TCompilerIrLiteral(negate:Int, syntax:TSyntaxNode)
		Local value:TCompilerIrLiteral = ScalarDefault("Int", SourceOf(syntax))
		If Not negate Then value.text = "1"
		Return value
	End Method

	Method EnumDefault:TCompilerIrLiteral(semanticType:TSemanticType, source:TCompilerSourceLocation)
		Local irEnum:TCompilerIrEnum = EnumForType(semanticType)
		Local value:TCompilerIrLiteral = ScalarDefault(TypeName(semanticType), source)
		If irEnum And Not irEnum.isFlags And irEnum.values.length Then value.text = irEnum.values[0].integerValue
		Return value
	End Method

	Method StructDefault:TCompilerIrStructNew(semanticType:TSemanticType, source:TCompilerSourceLocation, syntax:TSyntaxNode)
		Local value:TCompilerIrStructNew = New TCompilerIrStructNew
		value.kind = IR_EXPRESSION_STRUCT_NEW
		value.semanticType = TypeName(semanticType)
		value.source = source
		Local irStruct:TCompilerIrStruct = StructForType(semanticType)
		If irStruct Then
			value.structId = irStruct.structId
			If Not irStruct.constructorFunctionIds.length Then Return value
			For Local functionId:String = EachIn irStruct.constructorFunctionIds
				Local constructor:TCompilerIrFunction = FunctionById(functionId)
				If constructor And FunctionHasNoParameters(constructor) Then
					value.constructorFunctionId = functionId
					Return value
				End If
			Next
			' Structs always retain their implicit value-default construction,
			' independently of user-declared parameterized New overloads.
			Return value
		End If
		Local importedStruct:TCompilerIrImportedStruct = ImportedStructForType(semanticType)
		If importedStruct Then
			value.importedStructId = importedStruct.importedStructId
			For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
				If routine.isConstructor And Not routine.parameters.length Then
					value.importedConstructorId = routine.routineId
					Return value
				End If
			Next
			AddUnsupported("BMXC1202", "Imported Struct type '" + value.semanticType + "' has no published zero-argument constructor for default initialization", syntax)
		End If
		Return Null
	End Method

	Method FunctionHasNoParameters:Int(routine:TCompilerIrFunction)
		If Not routine Then Return False
		' Global initialization is lowered before routine parameter IR is
		' populated. Consult the bound symbol shape so a parameterized Struct
		' constructor is not mistaken for a zero-argument default constructor.
		For Local symbol:TSymbol = EachIn routineSymbols
			If TCompilerIrFunction(functionsBySymbol.ValueForKey(symbol)) = routine Then Return symbol.parameters.length = 0
		Next
		Return routine.parameters.length = 0
	End Method

	Method LowerStringOperand:TCompilerIrExpression(bound:TBoundExpression)
		If IsNullType(bound.semanticType) Then Return ManagedDefault("String", IR_MANAGED_REFERENCE_STRING, SourceOf(bound.syntax))
		Local operand:TCompilerIrExpression = LowerExpression(bound)
		If IsStringType(bound.semanticType) Then Return operand
		Local stringEnum:TCompilerIrEnum = EnumForType(bound.semanticType)
		If stringEnum Then
			Local enumToString:TCompilerIrEnumIntrinsic = New TCompilerIrEnumIntrinsic
			enumToString.kind = IR_EXPRESSION_ENUM_INTRINSIC
			enumToString.semanticType = "String"
			enumToString.source = SourceOf(bound.syntax)
			enumToString.intrinsicKind = IR_ENUM_INTRINSIC_TO_STRING
			enumToString.enumId = stringEnum.enumId
			enumToString.receiver = operand
			Return enumToString
		End If
		Local conversion:TCompilerIrConversion = New TCompilerIrConversion
		conversion.kind = IR_EXPRESSION_CONVERSION
		conversion.semanticType = "String"
		conversion.source = SourceOf(bound.syntax)
		conversion.conversionKind = CONVERSION_NUMERIC_TO_STRING
		conversion.implicitConversion = True
		conversion.operand = operand
		Return conversion
	End Method

	Method LowerArrayToPointer:TCompilerIrExpression(bound:TBoundExpression, pointerType:TSemanticType)
		Local conversion:TCompilerIrConversion = New TCompilerIrConversion
		conversion.kind = IR_EXPRESSION_CONVERSION
		conversion.semanticType = TypeName(pointerType)
		conversion.source = SourceOf(bound.syntax)
		conversion.conversionKind = CONVERSION_ARRAY_TO_POINTER
		conversion.implicitConversion = True
		conversion.arrayToPointerUsesHeapStorage = TArraySemanticType(bound.semanticType) <> Null
		conversion.operand = LowerExpression(bound)
		Return conversion
	End Method

	Function IsComparisonOperator:Int(operatorText:String)
		Select operatorText
			Case "=", "<>", "<", "<=", ">", ">=" Return True
		End Select
		Return False
	End Function

	Method InitializeExpression(expression:TCompilerIrExpression, kind:Int, bound:TBoundExpression)
		expression.kind = kind
		expression.semanticType = TypeName(bound.semanticType)
		expression.source = SourceOf(bound.syntax)
	End Method

	Method BuildInitializationPlan()
		Local plan:TCompilerIrInitializationPlan = New TCompilerIrInitializationPlan
		plan.unitKind = IR_UNIT_APPLICATION
		plan.unitName = "_bb_main"
		If analysis And analysis.model And analysis.model.moduleName.length And (Not options Or Not options.applicationBuild Or options.applicationSourceUnit) Then
			plan.unitKind = IR_UNIT_MODULE
			Local sourceUnitName:String
			If analysis.snapshot And analysis.snapshot.rootDocument Then
				sourceUnitName = StripExt(StripDir(analysis.snapshot.rootDocument.path))
			End If
			If options And options.sourceUnitPath.length Then sourceUnitName = StripExt(options.sourceUnitPath)
			plan.unitName = ModuleSourceUnitName(analysis.model.moduleName, SourceUnitIdentity(sourceUnitName))
		End If
		plan.registerFunctionName = plan.unitName + "_register"
		plan.initializeFunctionName = plan.unitName
		result.initializationPlan = plan
		If genericPlan Then
			For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
				If Not unit Or Not unit.specialization Or Not unit.ir Then Continue
				If options And options.coverageInstrumentation Then
					Local coverageRegistration:TCompilerIrGenericCoverageRegistration = New TCompilerIrGenericCoverageRegistration
					coverageRegistration.specializationIdentity = unit.specialization.identityDigest
					coverageRegistration.functionName = TCompilerGenericCUnitEmitter.GenericCoverageRegistrationName(unit.ir)
					If unit.ir.isRoutine And unit.ir.routine Then coverageRegistration.source = GenericIrSource(unit.ir.routine.source)
					plan.genericCoverageRegistrations :+ [coverageRegistration]
				End If
				If unit.ir.isRoutine And unit.ir.dynamicDispatchers.length Then
					Local registration:TCompilerIrGenericImplementationRegistration = New TCompilerIrGenericImplementationRegistration
					registration.specializationIdentity = unit.specialization.identityDigest
					registration.functionName = TCompilerGenericCUnitEmitter.DynamicImplementationRegistrationName(unit.ir)
					registration.source = GenericIrSource(unit.ir.routine.source)
					plan.genericImplementationRegistrations :+ [registration]
				End If
			Next
		End If

		If analysis And analysis.snapshot And analysis.snapshot.rootDocument Then
			Local seen:TMap = New TMap
			Local headerOwnershipSeen:TMap = New TMap
			' Include files are part of the same semantic/runtime unit. Their
			' module imports therefore contribute dependency initialization and
			' authoritative headers just as imports written in the root do.
			For Local document:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If Not document Then Continue
				For Local edge:TImportEdge = EachIn document.imports
					If Not edge Or Not edge.target Then Continue
					Local writtenLogicalName:String = edge.target.logicalName
					' An interface dependency can be interned first through a
					' transitive import with different relative spelling.  Publication
					' must retain the spelling at this source edge, not whichever route
					' happened to load the shared dependency first.
					If edge.syntax And edge.syntax.targetText.length Then writtenLogicalName = edge.syntax.targetText
					Local logicalName:String = writtenLogicalName.ToLower()
					Local sourceUnitPath:String
					Local dependencyIdentity:String = logicalName
					If logicalName.EndsWith(".bmx") Then
						sourceUnitPath = ResolveQuotedSourceUnitPath(writtenLogicalName, edge.target)
						If Not sourceUnitPath.length Then
							AddUnsupported("BMXC1110", "Quoted source path escapes its module or application source root", edge.syntax)
							Continue
						End If
						dependencyIdentity = sourceUnitPath
					End If
					If seen.Contains(dependencyIdentity) Then Continue
					seen.Insert(dependencyIdentity, dependencyIdentity)
					Local dependency:TCompilerIrDependency = New TCompilerIrDependency
					dependency.logicalName = logicalName
					dependency.interfacePath = edge.target.path
					If logicalName.EndsWith(".bmx") Then
						dependency.logicalName = writtenLogicalName
						Local sourceDirectory:String = ExtractDir(sourceUnitPath)
						If sourceDirectory.length Then sourceDirectory :+ "/"
						dependency.headerPath = sourceDirectory + ".bmx/" + StripExt(StripDir(edge.target.path)) + ".h"
						' Public module headers may themselves be included from any
						' downstream module directory. Qualify an owned secondary
						' header from the SDK module include root in that case.
						If analysis.model.moduleName.length And (Not options Or Not options.applicationBuild) Then
							dependency.headerPath = analysis.model.moduleName.ToLower().Replace(".", ".mod/") + ".mod/" + dependency.headerPath
						End If
						Local sourceOwnerIdentity:String = analysis.model.moduleName
						If options And options.applicationBuild And options.applicationIdentity.length Then sourceOwnerIdentity = options.applicationIdentity
						dependency.initializeFunctionName = ModuleSourceUnitName(sourceOwnerIdentity, SourceUnitIdentity(StripExt(sourceUnitPath)))
					Else
						dependency.headerPath = ModuleHeaderPath(logicalName)
						dependency.initializeFunctionName = ModuleUnitName(logicalName)
					End If
					dependency.registerFunctionName = dependency.initializeFunctionName + "_register"
					dependency.source = SourceOf(edge.syntax)
					plan.dependencies :+ [dependency]
					plan.registrationSteps :+ [InitializationStep(IR_INIT_REGISTER_DEPENDENCY, dependency, dependency.source)]
					RegisterHeaderOwnership(edge.target, headerOwnershipSeen)
				Next
			Next
		End If

		plan.initializationSteps :+ [InitializationStep(IR_INIT_INITIALIZE_STRINGS, Null, result.functions[0].source)]
		If HasGlobalStorage() Then plan.initializationSteps :+ [InitializationStep(IR_INIT_ADD_GC_ROOTS, Null, result.functions[0].source)]
		For Local dependency:TCompilerIrDependency = EachIn plan.dependencies
			plan.initializationSteps :+ [InitializationStep(IR_INIT_INITIALIZE_DEPENDENCY, dependency, dependency.source)]
		Next
		If plan.unitKind = IR_UNIT_APPLICATION Then plan.initializationSteps :+ [InitializationStep(IR_INIT_RUN_ATSTART, Null, result.functions[0].source)]
		plan.initializationSteps :+ [InitializationStep(IR_INIT_EXECUTE_GLOBAL_BODY, Null, result.functions[0].source)]
	End Method

	Method RegisterHeaderOwnership(dependency:TInterfaceDependency, seen:TMap)
		If Not dependency Or Not dependency.logicalName.length Then Return
		Local logicalName:String = dependency.logicalName.ToLower()
		' Quoted companion-source headers form part of the including module's
		' public header chain. They are not module owners themselves, but their
		' imports still contribute authoritative declarations downstream.
		Local traversalKey:String = "dependency:" + dependency.path.ToLower()
		If Not dependency.path.length Then traversalKey = "dependency:" + logicalName
		If seen.Contains(traversalKey) Then Return
		seen.Insert(traversalKey, traversalKey)
		If logicalName.Find("/") < 0 And Not logicalName.EndsWith(".bmx") Then
			Local moduleKey:String = "module:" + logicalName
			If Not seen.Contains(moduleKey) Then
				seen.Insert(moduleKey, moduleKey)
				result.headerOwnedModules :+ [logicalName]
			End If
		End If
		For Local imported:TInterfaceDependency = EachIn dependency.imports
			RegisterHeaderOwnership(imported, seen)
		Next
	End Method

	Method GenericRoutineFunction:TCompilerIrExternalFunction(call:TBoundCallExpression)
		If Not call Or Not call.resolvedCall Or Not call.resolvedCall.routine Or Not genericPlan Then Return Null
		Local resolved:TResolvedCall = call.resolvedCall
		Local receiverType:TSemanticType = call.staticReceiverType
		If call.receiver Then receiverType = call.receiver.semanticType
		Return GenericRoutineFunctionForBinding(resolved.routine, resolved.typeArguments, receiverType)
	End Method

	Method GenericRoutineFunctionForBinding:TCompilerIrExternalFunction(routine:TSymbol, typeArguments:TSemanticType[], receiverType:TSemanticType)
		If Not routine Or Not genericPlan Then Return Null
		Local signatureKey:String = TCompilerGenericTemplateBuilder.SymbolRoutineSignatureKey(analysis.model, routine)
		If routine.genericTemplateArtifact And routine.genericTemplateArtifact.identity Then signatureKey = routine.genericTemplateArtifact.identity.signatureKey
		For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
			If Not unit Or Not unit.ir Or Not unit.ir.isRoutine Then Continue
			Local identity:TGenericTemplateIdentity = unit.specialization.artifact.identity
			If routine.genericTemplateArtifact Then
				If unit.specialization.artifact <> routine.genericTemplateArtifact Then Continue
			Else If identity.qualifiedName.ToLower() <> routine.QualifiedName().ToLower() And identity.qualifiedName.ToLower() <> routine.name.ToLower() Then
				Continue
			End If
			If identity.moduleName.length And routine.originModule.length And identity.moduleName.ToLower() <> routine.originModule.ToLower() Then
				' Quoted application source units retain their source-unit spelling as
				' symbol provenance, while their canonical template identity belongs to
				' the synthetic application module. The attached artifact is the
				' authoritative bridge between those two names.
				If Not routine.genericTemplateArtifact Or unit.specialization.artifact <> routine.genericTemplateArtifact Then Continue
			End If
			If signatureKey.length And identity.signatureKey.ToLower() <> signatureKey.ToLower() Then Continue
			If unit.specialization.key.typeArguments.length <> typeArguments.length Then Continue
			Local matches:Int = True
			For Local index:Int = 0 Until typeArguments.length
				If unit.specialization.key.typeArguments[index].CanonicalName().ToLower() <> CanonicalSemanticTypeName(typeArguments[index]) Then matches = False; Exit
			Next
			If matches And unit.specialization.artifact.isMethod Then
				Local receiver:TNamedSemanticType
				Local methodOwner:TSymbol
				If routine.containingScope Then methodOwner = routine.containingScope.owner
				If receiverType Then receiver = TCompilerGenericInheritance.ConstructedOwnerType(receiverType, methodOwner, analysis.model)
				If Not receiver Or receiver.typeArguments.length <> unit.specialization.key.containingTypeArguments.length Then matches = False
				If matches Then
					For Local index:Int = 0 Until receiver.typeArguments.length
						If unit.specialization.key.containingTypeArguments[index].CanonicalName().ToLower() <> CanonicalSemanticTypeName(receiver.typeArguments[index]) Then matches = False; Exit
					Next
				End If
			End If
			If matches Then Return TCompilerIrExternalFunction(genericFunctionsBySpecialization.ValueForKey(unit.specialization))
		Next
		Return Null
	End Method

	Method ExternalFunction:TCompilerIrExternalFunction(symbol:TSymbol, callSyntax:TSyntaxNode)
		If Not symbol Or (Not symbol.isImported And Not symbol.isExternal) Or symbol.kind <> SYMBOL_ROUTINE Then Return Null
		If symbol.genericArity <> 0 Then Return Null
		If symbol.interfaceRecord And symbol.interfaceRecord.kind <> INTERFACE_RECORD_FUNCTION And symbol.interfaceRecord.kind <> INTERFACE_RECORD_TYPE_FUNCTION Then Return Null
		Local sourceDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If sourceDeclaration And sourceDeclaration.isMethod Then Return Null
		If symbol.isExternal And Not symbol.isImported And TClosureSemanticType(symbol.declaredType) Then
			AddUnsupported("BMXC1244", "Closure values have no native ABI representation", callSyntax)
			Return Null
		End If
		If symbol.isExternal And Not symbol.isImported Then
			For Local parameter:TSemanticParameter = EachIn symbol.parameters
				If parameter And TClosureSemanticType(parameter.semanticType) Then
					AddUnsupported("BMXC1244", "Closure values have no native ABI representation", callSyntax)
					Return Null
				End If
			Next
		End If
		If TCallableSemanticType(symbol.declaredType) And symbol.containingScope And symbol.containingScope.owner Then
			Local owner:TSymbol = symbol.containingScope.owner
			If owner.kind <> SYMBOL_TYPE Or Not symbol.interfaceRecord Or symbol.interfaceRecord.kind <> INTERFACE_RECORD_TYPE_FUNCTION Then
				AddUnsupported("BMXC1112", "Imported member callable returns require a supported Type-function slot ABI", callSyntax)
				Return Null
			End If
		End If
		If Not symbol.externalName.length Then
			AddUnsupported("BMXC1111", "Imported routine '" + symbol.QualifiedName() + "' has no interface ABI name", callSyntax)
			Return Null
		End If
		Local linkerName:String = ExternalRoutineLinkerName(symbol.externalName)
		If Not linkerName.length Then
			AddUnsupported("BMXC1115", "Imported/native ABI name '" + symbol.externalName + "' requires an explicit linker-name representation", callSyntax)
			Return Null
		End If
		If Not IsSupportedReturnType(symbol.declaredType) Then
			AddUnsupported("BMXC1112", "Imported routine return type '" + TypeName(symbol.declaredType) + "' is outside the scalar ABI slice", callSyntax)
			Return Null
		End If
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			If Not parameter Or Not IsSupportedAbiParameterType(parameter.semanticType) Then
				Local parameterType:String = "?"
				If parameter Then parameterType = TypeName(parameter.semanticType)
				AddUnsupported("BMXC1112", "Imported routine '" + symbol.QualifiedName() + "' parameter type '" + parameterType + "' is outside the supported ordinary-C ABI slice", callSyntax)
				Return Null
			End If
			If Not IsSupportedParameterMode(parameter) Then
				AddUnsupported("BMXC1112", "Imported routine Var parameters require a directly addressable value ABI type", callSyntax)
				Return Null
			End If
		Next
		Local existing:TCompilerIrExternalFunction = TCompilerIrExternalFunction(externalFunctionsBySymbol.ValueForKey(symbol))
		If existing Then Return existing
		Local externalFunction:TCompilerIrExternalFunction = New TCompilerIrExternalFunction
		externalFunction.functionId = "ext" + nextExternalFunctionId
		nextExternalFunctionId :+ 1
		externalFunction.sourceName = symbol.name
		externalFunction.callingConvention = symbol.callingConvention
		externalFunction.abiName = linkerName
		externalFunction.nativeDeclaration = ExternalRoutineNativeDeclaration(symbol.externalName)
		externalFunction.nativeReturnType = ExternalRoutineNativeReturnType(symbol.externalName)
		externalFunction.nativeParameterTypes = ExternalRoutineNativeParameterTypes(symbol.externalName)
		externalFunction.nativeDeclarationSuppressesPrototype = symbol.externalName.Trim().EndsWith("!")
		externalFunction.suppressNativePrototype = externalFunction.nativeDeclarationSuppressesPrototype Or IsStandardNativeFunction(linkerName)
		externalFunction.originModule = symbol.originModule
		externalFunction.isPublished = Not symbol.isImported And symbol.visibility = VISIBILITY_PUBLIC And analysis And analysis.model And analysis.model.moduleName.length > 0
		externalFunction.returnType = TypeName(symbol.declaredType)
		externalFunction.nativeStringReturnEncoding = symbol.nativeStringReturnEncoding
		Local callableReturn:TCallableSemanticType = TCallableSemanticType(symbol.declaredType)
		If callableReturn Then
			externalFunction.callableReturnType = TypeName(callableReturn.returnType)
			externalFunction.callableReturnParameters = CallableParameters(callableReturn)
			externalFunction.callableReturnCallingConvention = callableReturn.callingConvention
		End If
		externalFunction.source = SourceForSymbol(symbol)
		externalFunction.parameters = New TCompilerIrParameter[symbol.parameters.length]
		For Local index:Int = 0 Until symbol.parameters.length
			Local sourceParameter:TSemanticParameter = symbol.parameters[index]
			Local parameter:TCompilerIrParameter = New TCompilerIrParameter
			parameter.symbolId = "ep" + index
			If sourceParameter.symbol Then parameter.name = sourceParameter.symbol.name Else parameter.name = "arg" + index
			parameter.semanticType = TypeName(sourceParameter.semanticType)
			parameter.passingMode = sourceParameter.passingMode
			parameter.nativeStringEncoding = sourceParameter.nativeStringEncoding
			parameter.isOptional = sourceParameter.optional
			PopulateParameterDefault(parameter, sourceParameter)
			PopulateParameterShape(parameter, sourceParameter.semanticType)
			externalFunction.parameters[index] = parameter
		Next
		externalFunctionsBySymbol.Insert(symbol, externalFunction)
		result.externalFunctions :+ [externalFunction]
		Return externalFunction
	End Method

	' Legacy native declarations may carry a complete C prototype as their
	' external-name string. Validate and split that declaration at ingestion so
	' semantic identity remains the linker identifier while the C backend can
	' preserve typedef-rich ABI spellings such as BBClass* and BBArray*.
	Function ExternalRoutineLinkerName:String(externalName:String)
		Return TCompilerNativeDeclaration.LinkerName(externalName)
	End Function

	Function ExternalRoutineNativeDeclaration:String(externalName:String)
		Return TCompilerNativeDeclaration.Declaration(externalName)
	End Function

	Function ExternalRoutineNativeReturnType:String(externalName:String)
		Return TCompilerNativeDeclaration.ReturnType(externalName)
	End Function

	Function ExternalRoutineNativeParameterTypes:String[](externalName:String)
		Return TCompilerNativeDeclaration.ParameterTypes(externalName)
	End Function

	Function ExternalRoutineNativeCallableCast:String(externalName:String)
		Local linkerName:String = ExternalRoutineLinkerName(externalName)
		If Not linkerName.length Then Return ""
		Local declaration:String = externalName.Trim()
		If declaration.EndsWith("!") Then declaration = declaration[..declaration.length - 1].Trim()
		Local openParen:Int = declaration.Find("(")
		Local closeParen:Int = declaration.FindLast(")")
		If openParen <= 0 Or closeParen <= openParen Then Return ""
		Local linkerStart:Int = declaration[..openParen].FindLast(linkerName)
		If linkerStart <= 0 Then Return ""
		Local returnType:String = declaration[..linkerStart].Trim()
		If Not returnType.length Then Return ""
		Return returnType + " (*)" + declaration[openParen..closeParen + 1]
	End Function

	Function IsStandardNativeFunction:Int(linkerName:String)
		Local lower:String = linkerName.ToLower()
		Local standardNames:String = ";isalnum;isalpha;isascii;isblank;iscntrl;isdigit;isgraph;islower;isprint;ispunct;isspace;isupper;isxdigit;strlen;_wgetenv;_wputenv;"
		Return standardNames.Find(";" + lower + ";") >= 0
	End Function

	Method ImportedDirectMethod:TCompilerIrExternalFunction(symbol:TSymbol, receiverType:TSemanticType, callSyntax:TSyntaxNode, useDeclaringReceiver:Int = False)
		If Not symbol Or Not symbol.isImported Or symbol.kind <> SYMBOL_ROUTINE Or Not symbol.interfaceRecord Or symbol.interfaceRecord.kind <> INTERFACE_RECORD_METHOD Then Return Null
		Local existing:TCompilerIrExternalFunction = TCompilerIrExternalFunction(externalFunctionsBySymbol.ValueForKey(symbol))
		If existing Then Return existing
		' A direct Super call invokes the declaring implementation, even when
		' the expression receiver is an intermediate or concrete derived Type.
		' Its C prototype therefore belongs to the method's declaring owner.
		' Using the expression type here gives the same ABI symbol a different
		' receiver prototype in every consuming source header.
		Local abiReceiverType:TSemanticType = receiverType
		Local declaringOwner:TSymbol
		If useDeclaringReceiver Then
			If symbol.containingScope Then declaringOwner = symbol.containingScope.owner
			If declaringOwner And declaringOwner.declaredType Then abiReceiverType = declaringOwner.declaredType
		End If
		If symbol.genericArity Or Not symbol.externalName.length Or TCompilerAbiNamer.Sanitize(symbol.externalName) <> symbol.externalName Then
			AddUnsupported("BMXC1172", "Direct imported method '" + symbol.QualifiedName() + "' has no usable function ABI identity", callSyntax)
			Return Null
		End If
		If Not IsSupportedValueType(abiReceiverType) Or Not IsSupportedReturnType(symbol.declaredType) Then
			AddUnsupported("BMXC1175", "Direct imported method '" + symbol.QualifiedName() + "' has an unsupported receiver or return type", callSyntax)
			Return Null
		End If
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			If Not parameter Or Not IsSupportedAbiParameterType(parameter.semanticType) Or Not IsSupportedParameterMode(parameter) Then
				AddUnsupported("BMXC1175", "Direct imported method parameters require supported ordinary-C ABI value types", callSyntax)
				Return Null
			End If
		Next
		Local externalFunction:TCompilerIrExternalFunction = New TCompilerIrExternalFunction
		externalFunction.functionId = "ext" + nextExternalFunctionId
		nextExternalFunctionId :+ 1
		externalFunction.sourceName = symbol.name
		externalFunction.abiName = symbol.externalName
		externalFunction.implementationAbiName = externalFunction.abiName
		If useDeclaringReceiver And declaringOwner And declaringOwner.externalName <> "bbObjectClass" And Not externalFunction.implementationAbiName.StartsWith("_") Then
			externalFunction.implementationAbiName = "_" + externalFunction.implementationAbiName
		End If
		externalFunction.originModule = symbol.originModule
		externalFunction.returnType = TypeName(symbol.declaredType)
		externalFunction.isDirectMethod = True
		externalFunction.source = SourceForSymbol(symbol)
		externalFunction.parameters = New TCompilerIrParameter[symbol.parameters.length + 1]
		Local receiverParameter:TCompilerIrParameter = New TCompilerIrParameter
		receiverParameter.symbolId = externalFunction.functionId + "_receiver"
		receiverParameter.name = "self"
		receiverParameter.semanticType = TypeName(abiReceiverType)
		externalFunction.parameters[0] = receiverParameter
		For Local index:Int = 0 Until symbol.parameters.length
			Local sourceParameter:TSemanticParameter = symbol.parameters[index]
			Local parameter:TCompilerIrParameter = New TCompilerIrParameter
			parameter.symbolId = "ep" + index
			If sourceParameter.symbol Then parameter.name = sourceParameter.symbol.name Else parameter.name = "arg" + index
			parameter.semanticType = TypeName(sourceParameter.semanticType)
			parameter.passingMode = sourceParameter.passingMode
			PopulateParameterShape(parameter, sourceParameter.semanticType)
			externalFunction.parameters[index + 1] = parameter
		Next
		externalFunctionsBySymbol.Insert(symbol, externalFunction)
		result.externalFunctions :+ [externalFunction]
		Return externalFunction
	End Method

	Method ImportedMethod:TCompilerIrImportedMethod(symbol:TSymbol, callSyntax:TSyntaxNode)
		If Not symbol Or Not symbol.isImported Or symbol.kind <> SYMBOL_ROUTINE Then Return Null
		If Not symbol.interfaceRecord Or symbol.interfaceRecord.kind <> INTERFACE_RECORD_METHOD Then Return Null
		Local known:TCompilerIrImportedMethod = TCompilerIrImportedMethod(importedMethodsBySymbol.ValueForKey(symbol))
		If known Then Return known
		Local owner:TSymbol
		If symbol.containingScope Then owner = symbol.containingScope.owner
		Local importedClass:TCompilerIrImportedClass = EnsureImportedClass(owner)
		If Not importedClass Then Return Null
		If symbol.genericArity <> 0 Then
			AddUnsupported("BMXC1174", "Generic imported method '" + symbol.QualifiedName() + "' requires canonical specialization lowering", callSyntax)
			Return Null
		End If
		If Not IsSupportedReturnType(symbol.declaredType) Then
			AddUnsupported("BMXC1175", "Imported method return type '" + TypeName(symbol.declaredType) + "' is outside the current value ABI slice", callSyntax)
			Return Null
		End If
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			If Not parameter Or Not IsSupportedAbiParameterType(parameter.semanticType) Or Not IsSupportedParameterMode(parameter) Then
				AddUnsupported("BMXC1175", "Imported method parameters require supported ordinary-C ABI value types", callSyntax)
				Return Null
			End If
		Next
		Local slotName:String = ImportedMethodSlotName(symbol, owner)
		If Not slotName.length Then
			Local objectSlotKind:Int = ObjectSlotKind(symbol)
			If objectSlotKind <> IR_OBJECT_SLOT_NONE Then
				slotName = symbol.name
			Else If symbol.name.ToLower() = "delete" And owner.externalName = "bbObjectClass" Then
				slotName = "dtor"
			End If
		End If
		If Not slotName.length Then
			AddUnsupported("BMXC1172", "Imported method '" + symbol.QualifiedName() + "' has no class-slot ABI name derived from '" + symbol.externalName + "'", callSyntax)
			Return Null
		End If
		Local importedMethod:TCompilerIrImportedMethod = New TCompilerIrImportedMethod
		importedMethod.methodId = "icm" + nextImportedMethodId
		nextImportedMethodId :+ 1
		importedMethod.declaringImportedClassId = importedClass.importedClassId
		importedMethod.name = symbol.name
		importedMethod.abiName = symbol.externalName
		importedMethod.implementationAbiName = importedMethod.abiName
		If importedClass.abiName <> "bbObjectClass" And Not importedMethod.implementationAbiName.StartsWith("_") Then importedMethod.implementationAbiName = "_" + importedMethod.implementationAbiName
		importedMethod.slotName = slotName
		importedMethod.returnType = TypeName(symbol.declaredType)
		Local callableReturn:TCallableSemanticType = TCallableSemanticType(symbol.declaredType)
		If callableReturn Then
			importedMethod.callableReturnType = TypeName(callableReturn.returnType)
			importedMethod.callableReturnParameters = CallableParameters(callableReturn)
			importedMethod.callableReturnCallingConvention = callableReturn.callingConvention
		End If
		importedMethod.callingConvention = symbol.callingConvention
		importedMethod.isAbstract = symbol.isAbstract
		importedMethod.source = SourceForSymbol(symbol)
		importedMethod.metadata = MetadataOf(symbol)
		importedMethod.parameters = New TCompilerIrParameter[symbol.parameters.length]
		For Local index:Int = 0 Until symbol.parameters.length
			Local sourceParameter:TSemanticParameter = symbol.parameters[index]
			Local irParameter:TCompilerIrParameter = New TCompilerIrParameter
			irParameter.symbolId = "imp" + index
			If sourceParameter.symbol Then irParameter.name = sourceParameter.symbol.name Else irParameter.name = "arg" + index
			irParameter.semanticType = TypeName(sourceParameter.semanticType)
			irParameter.passingMode = sourceParameter.passingMode
			PopulateParameterShape(irParameter, sourceParameter.semanticType)
			importedMethod.parameters[index] = irParameter
		Next
		importedMethodsBySymbol.Insert(symbol, importedMethod)
		importedClass.methods :+ [importedMethod]
		Return importedMethod
	End Method

	Method GenericImportedMethod:TCompilerIrImportedMethod(importedClass:TCompilerIrImportedClass, symbol:TSymbol)
		If Not importedClass Or Not symbol Then Return Null
		For Local importedMethod:TCompilerIrImportedMethod = EachIn importedClass.methods
			If importedMethod.name.ToLower() <> symbol.name.ToLower() Then Continue
			If importedMethod.parameters.length <> symbol.parameters.length Then Continue
			Return importedMethod
		Next
		Return Null
	End Method

	Method GenericImportedMethodForCall:TCompilerIrImportedMethod(importedClass:TCompilerIrImportedClass, resolvedCall:TResolvedCall)
		If Not importedClass Or Not resolvedCall Or Not resolvedCall.routine Then Return Null
		Local arityMatch:TCompilerIrImportedMethod
		Local arityMatchCount:Int
		Local categoryMatch:TCompilerIrImportedMethod
		Local categoryMatchCount:Int
		For Local importedMethod:TCompilerIrImportedMethod = EachIn importedClass.methods
			If importedMethod.name.ToLower() <> resolvedCall.routine.name.ToLower() Then Continue
			If importedMethod.parameters.length <> resolvedCall.parameterTypes.length Then Continue
			arityMatch = importedMethod
			arityMatchCount :+ 1
			Local matches:Int = True
			Local categoriesMatch:Int = True
			For Local index:Int = 0 Until importedMethod.parameters.length
				If Not GenericImportedParameterShapeMatches(importedMethod.parameters[index], resolvedCall.parameterTypes[index]) Then matches = False
				If Not GenericImportedParameterCategoryMatches(importedMethod.parameters[index], resolvedCall.parameterTypes[index]) Then categoriesMatch = False
				If index < resolvedCall.routine.parameters.length And importedMethod.parameters[index].passingMode <> resolvedCall.routine.parameters[index].passingMode Then
					matches = False
					categoriesMatch = False
				End If
			Next
			If matches Then Return importedMethod
			If categoriesMatch Then categoryMatch = importedMethod; categoryMatchCount :+ 1
		Next
		' Imported generic symbols retain their defining Type parameters. The
		' canonical specialization IR has already substituted those parameters,
		' so a direct textual comparison can fail even though overload
		' resolution selected the only method of this name and arity.
		If categoryMatchCount = 1 Then Return categoryMatch
		If arityMatchCount = 1 Then Return arityMatch
		Return Null
	End Method

	Method GenericImportedParameterShapeMatches:Int(parameter:TCompilerIrParameter, semanticType:TSemanticType)
		If Not parameter Or Not semanticType Then Return False
		Local callable:TCallableSemanticType = TCallableSemanticType(semanticType)
		If callable Then
			If Not parameter.callableReturnType.length Or parameter.callableReturnType.ToLower() <> TypeName(callable.returnType).ToLower() Or parameter.callableParameters.length <> callable.parameterTypes.length Then Return False
			For Local index:Int = 0 Until callable.parameterTypes.length
				If parameter.callableParameters[index].semanticType.ToLower() <> TypeName(callable.parameterTypes[index]).ToLower() Then Return False
				Local mode:Int = PARAMETER_PASS_VALUE
				If index < callable.parameterModes.length Then mode = callable.parameterModes[index]
				If parameter.callableParameters[index].passingMode <> mode Then Return False
			Next
			Return parameter.callableCallingConvention.ToLower() = callable.callingConvention.ToLower()
		End If
		Return parameter.semanticType.ToLower() = TypeName(semanticType).ToLower()
	End Method

	Function GenericImportedParameterCategoryMatches:Int(parameter:TCompilerIrParameter, semanticType:TSemanticType)
		If Not parameter Or Not semanticType Then Return False
		If TCallableSemanticType(semanticType) Then Return parameter.callableReturnType.length > 0
		If TClosureSemanticType(semanticType) Then Return Not parameter.callableReturnType.length And parameter.semanticType.ToLower().StartsWith("closure<")
		Return parameter.semanticType.ToLower() = TypeName(semanticType).ToLower()
	End Function

	Method ImplicitImportedConstructor:TCompilerIrImportedConstructor(importedClass:TCompilerIrImportedClass, useSyntax:TSyntaxNode)
		If Not importedClass Then Return Null
		For Local known:TCompilerIrImportedConstructor = EachIn importedClass.constructors
			If Not known.parameters.length Then Return known
		Next
		Local constructor:TCompilerIrImportedConstructor = New TCompilerIrImportedConstructor
		constructor.constructorId = "icn" + nextImportedConstructorId
		nextImportedConstructorId :+ 1
		constructor.declaringImportedClassId = importedClass.importedClassId
		constructor.source = SourceOf(useSyntax)
		constructor.parameters = New TCompilerIrParameter[0]
		If options And options.targetPlatform.ToLower() = "pico" And importedClass.abiName.length Then
			constructor.objectNewAbiName = "_" + importedClass.abiName + "_New_ObjectNew"
		End If
		importedClass.constructors :+ [constructor]
		Return constructor
	End Method

	Method ImportedConstructor:TCompilerIrImportedConstructor(symbol:TSymbol, useSyntax:TSyntaxNode)
		If Not symbol Or Not symbol.isImported Or symbol.kind <> SYMBOL_ROUTINE Or symbol.name.ToLower() <> "new" Then Return Null
		If Not symbol.interfaceRecord Or symbol.interfaceRecord.kind <> INTERFACE_RECORD_METHOD Then Return Null
		Local known:TCompilerIrImportedConstructor = TCompilerIrImportedConstructor(importedConstructorsBySymbol.ValueForKey(symbol))
		If known Then Return known
		Local owner:TSymbol
		If symbol.containingScope Then owner = symbol.containingScope.owner
		Local importedClass:TCompilerIrImportedClass = EnsureImportedClass(owner)
		If Not importedClass Then Return Null
		If symbol.genericArity <> 0 Then
			AddUnsupported("BMXC1177", "Generic imported constructor requires canonical specialization lowering", useSyntax)
			Return Null
		End If
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			If Not parameter Or Not IsSupportedAbiParameterType(parameter.semanticType) Or parameter.passingMode <> PARAMETER_PASS_VALUE Then
				AddUnsupported("BMXC1178", "Imported constructor parameters require supported value ABI types", useSyntax)
				Return Null
			End If
		Next
		If Not symbol.externalName.length Then
			AddUnsupported("BMXC1179", "Imported constructor has no published ABI name", useSyntax)
			Return Null
		End If
		Local constructor:TCompilerIrImportedConstructor = New TCompilerIrImportedConstructor
		constructor.constructorId = "icn" + nextImportedConstructorId
		nextImportedConstructorId :+ 1
		constructor.declaringImportedClassId = importedClass.importedClassId
		constructor.abiName = symbol.externalName
		constructor.implementationAbiName = constructor.abiName
		If Not constructor.implementationAbiName.StartsWith("_") Then constructor.implementationAbiName = "_" + constructor.implementationAbiName
		If symbol.parameters.length Then
			constructor.objectNewAbiName = constructor.implementationAbiName + "_ObjectNew"
			If TCompilerAbiNamer.Sanitize(constructor.objectNewAbiName) <> constructor.objectNewAbiName Then
				AddUnsupported("BMXC1179", "Imported constructor object-allocation ABI name requires an explicit linker-name representation", useSyntax)
				Return Null
			End If
		End If
		constructor.source = SourceForSymbol(symbol)
		constructor.metadata = MetadataOf(symbol)
		constructor.parameters = New TCompilerIrParameter[symbol.parameters.length]
		For Local index:Int = 0 Until symbol.parameters.length
			Local sourceParameter:TSemanticParameter = symbol.parameters[index]
			Local irParameter:TCompilerIrParameter = New TCompilerIrParameter
			irParameter.symbolId = "icnp" + index
			If sourceParameter.symbol Then irParameter.name = sourceParameter.symbol.name Else irParameter.name = "arg" + index
			irParameter.semanticType = TypeName(sourceParameter.semanticType)
			irParameter.passingMode = sourceParameter.passingMode
			PopulateParameterShape(irParameter, sourceParameter.semanticType)
			constructor.parameters[index] = irParameter
		Next
		importedConstructorsBySymbol.Insert(symbol, constructor)
		importedClass.constructors :+ [constructor]
		Return constructor
	End Method

	Function ImportedMethodSlotName:String(symbol:TSymbol, owner:TSymbol)
		If Not symbol Or Not owner Or Not symbol.externalName.length Or Not owner.externalName.length Then Return ""
		Local prefix:String = owner.externalName + "_"
		Local suffix:String
		If symbol.externalName.StartsWith(prefix) Then
			suffix = symbol.externalName[prefix.length..]
		Else
			prefix = "_" + owner.externalName + "_"
			If symbol.externalName.StartsWith(prefix) Then suffix = symbol.externalName[prefix.length..]
		End If
		If Not suffix.length Then Return ""
		Local slotName:String = "m_" + suffix
		If TCompilerAbiNamer.Sanitize(slotName) <> slotName Then Return ""
		Return slotName
	End Function

	Method ResolveExternalGlobal:TCompilerIrExternalGlobal(symbol:TSymbol, useSyntax:TSyntaxNode)
		If Not symbol Or (Not symbol.isImported And Not symbol.isExternal) Or symbol.kind <> SYMBOL_GLOBAL Then Return Null
		If symbol.isExternal And Not symbol.isImported And TClosureSemanticType(symbol.declaredType) Then
			AddUnsupported("BMXC1244", "Closure values have no native ABI representation", useSyntax)
			Return Null
		End If
		If Not symbol.externalName.length Then
			AddUnsupported("BMXC1121", "Imported/native Global '" + symbol.QualifiedName() + "' has no ABI name", useSyntax)
			Return Null
		End If
		Local linkerName:String = symbol.externalName
		Local suppressNativePrototype:Int
		If TCompilerAbiNamer.Sanitize(linkerName) <> linkerName Then
			If symbol.externalName.Trim().EndsWith("!") Then
				linkerName = ExternalRoutineLinkerName(symbol.externalName)
				suppressNativePrototype = linkerName.length > 0
			Else
				linkerName = ""
			End If
		End If
		If Not linkerName.length Then
			AddUnsupported("BMXC1115", "Imported/native ABI name '" + symbol.externalName + "' requires an explicit linker-name representation", useSyntax)
			Return Null
		End If
		If Not IsSupportedAbiParameterType(symbol.declaredType) Then
			AddUnsupported("BMXC1122", "Imported/native Global type '" + TypeName(symbol.declaredType) + "' is outside the scalar, pointer, and callable ABI slice", useSyntax)
			Return Null
		End If
		Local existing:TCompilerIrExternalGlobal = TCompilerIrExternalGlobal(externalGlobalsBySymbol.ValueForKey(symbol))
		If existing Then Return existing
		Local externalGlobal:TCompilerIrExternalGlobal = New TCompilerIrExternalGlobal
		externalGlobal.symbolId = "extg" + nextExternalGlobalId
		nextExternalGlobalId :+ 1
		externalGlobal.sourceName = symbol.name
		externalGlobal.abiName = linkerName
		externalGlobal.suppressNativePrototype = suppressNativePrototype
		If suppressNativePrototype And TCallableSemanticType(symbol.declaredType) Then externalGlobal.nativeCallableCast = ExternalRoutineNativeCallableCast(symbol.externalName)
		externalGlobal.originModule = symbol.originModule
		externalGlobal.isPublished = Not symbol.isImported And symbol.visibility = VISIBILITY_PUBLIC And analysis And analysis.model And analysis.model.moduleName.length > 0
		externalGlobal.semanticType = TypeName(symbol.declaredType)
		Local callableType:TCallableSemanticType = TCallableSemanticType(symbol.declaredType)
		If callableType Then
			externalGlobal.callableReturnType = TypeName(callableType.returnType)
			externalGlobal.callableParameters = CallableParameters(callableType)
			externalGlobal.callableCallingConvention = callableType.callingConvention
		End If
		externalGlobal.isReadOnly = symbol.isReadOnly
		If symbol.declaration Then
			externalGlobal.source = SourceOf(symbol.declaration)
		Else
			externalGlobal.source = New TCompilerSourceLocation
			externalGlobal.source.path = symbol.originPath
		End If
		externalGlobalsBySymbol.Insert(symbol, externalGlobal)
		result.externalGlobals :+ [externalGlobal]
		Return externalGlobal
	End Method

	Method RegisterStringLiteral:TCompilerIrStringLiteral(token:TSyntaxToken, syntax:TSyntaxNode)
		Local value:String = TConstantEvaluator.DecodeString(token.text, token.kind = TOKEN_MULTILINE_STRING_LITERAL)
		Return RegisterStringValue(value, SourceOf(syntax))
	End Method

	Method RegisterStringValue:TCompilerIrStringLiteral(value:String, source:TCompilerSourceLocation)
		Local existing:TCompilerIrStringLiteral = TCompilerIrStringLiteral(stringLiteralsByValue.ValueForKey(value))
		If existing Then Return existing
		Local literal:TCompilerIrStringLiteral = New TCompilerIrStringLiteral
		literal.literalId = "str" + nextStringLiteralId
		nextStringLiteralId :+ 1
		literal.value = value
		literal.source = source
		stringLiteralsByValue.Insert(value, literal)
		result.stringLiterals :+ [literal]
		Return literal
	End Method

	Method SymbolForDeclaration:TSymbol(declaration:TSyntaxNode)
		If Not declaration Or Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return Null
		For Local symbol:TSymbol = EachIn analysis.model.globalScope.declaredSymbols
			If symbol.declaration = declaration Then Return symbol
		Next
		Return Null
	End Method

	Method HasGlobalStorage:Int()
		If Not result Then Return False
		For Local routine:TCompilerIrFunction = EachIn result.functions
			If Not routine Or Not routine.body Then Continue
			For Local statement:TCompilerIrStatement = EachIn routine.body.statements
				Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
				If variable And variable.storage = "global" Then Return True
			Next
		Next
		Return False
	End Method

	Method MetadataOf:TCompilerIrMetadataEntry[](symbol:TSymbol)
		Local values:TCompilerIrMetadataEntry[] = New TCompilerIrMetadataEntry[0]
		If Not symbol Or Not symbol.metadata Then Return values
		For Local sourceEntry:TDeclarationMetadataEntry = EachIn symbol.metadata.entries
			Local entry:TCompilerIrMetadataEntry = New TCompilerIrMetadataEntry
			entry.key = sourceEntry.key
			entry.value = sourceEntry.value
			entry.writtenValue = sourceEntry.writtenValue
			entry.source = New TCompilerSourceLocation
			entry.source.path = symbol.originPath
			entry.source.span = sourceEntry.span
			values :+ [entry]
		Next
		Return values
	End Method

	Function InitializationStep:TCompilerIrInitializationStep(kind:Int, dependency:TCompilerIrDependency, source:TCompilerSourceLocation)
		Local stepValue:TCompilerIrInitializationStep = New TCompilerIrInitializationStep
		stepValue.kind = kind
		stepValue.dependency = dependency
		stepValue.source = source
		Return stepValue
	End Function

	Function ModuleUnitName:String(moduleName:String)
		Local normalized:String = moduleName.ToLower()
		Local dot:Int = normalized.FindLast(".")
		Local suffix:String = normalized
		If dot >= 0 Then suffix = normalized[dot + 1..]
		Return ModuleSourceUnitName(normalized, suffix)
	End Function

	Function ModuleSourceUnitName:String(moduleName:String, sourceUnitName:String)
		Local normalized:String = moduleName.ToLower()
		If Not sourceUnitName.length Then
			Local dot:Int = normalized.FindLast(".")
			sourceUnitName = normalized
			If dot >= 0 Then sourceUnitName = normalized[dot + 1..]
		End If
		Return TCompilerAbiNamer.Sanitize("__bb_" + normalized + "_" + sourceUnitName.ToLower())
	End Function

	' Preserve a readable path component while supplementing nested paths with
	' a digest. Sanitization alone would make a/b.bmx and a_b.bmx identical.
	Function SourceUnitIdentity:String(sourceUnitPath:String)
		Local normalized:String = sourceUnitPath.Replace("\\", "/").ToLower()
		While normalized.StartsWith("./")
			normalized = normalized[2..]
		Wend
		If normalized.Find("/") < 0 Then Return normalized
		Return normalized + "_" + SourceUnitPathHash(normalized)
	End Function

	Function SourceUnitPathHash:String(value:String)
		' FNV-1a provides the same small, dependency-free stable suffix in bmk
		' and compiler.mod. It is identity reinforcement, not a security hash.
		Local hash:ULong = $CBF29CE484222325:ULong
		For Local index:Int = 0 Until value.length
			hash :~ ULong(value[index])
			hash :* $100000001B3:ULong
		Next
		Return String(hash)
	End Function

	Method ResolveQuotedSourceUnitPath:String(logicalName:String, dependency:TInterfaceDependency = Null)
		' Prefer the resolved interface identity.  It remains correct for
		' imports written inside included files and for dependencies interned
		' first through another relative route.
		If dependency And dependency.path.length And analysis And analysis.snapshot And analysis.snapshot.rootDocument And options And options.sourceUnitPath.length Then
			Local rootPath:String = analysis.snapshot.rootDocument.path.Replace("\\", "/")
			Local rootUnitPath:String = options.sourceUnitPath.Replace("\\", "/")
			While rootUnitPath.StartsWith("./")
				rootUnitPath = rootUnitPath[2..]
			Wend
			If rootPath.ToLower().EndsWith(rootUnitPath.ToLower()) Then
				Local sourceRoot:String = rootPath[..rootPath.length - rootUnitPath.length]
				Local targetSource:String = TCompilationSnapshotBuilder.InterfaceSourcePath(dependency.path).Replace("\\", "/")
				Local declaredSource:String = InterfaceDeclaredSourceSpelling(dependency.interfaceFile, targetSource)
				If declaredSource.length Then targetSource = declaredSource
				If targetSource.ToLower().StartsWith(sourceRoot.ToLower()) Then
					Local resolvedUnitPath:String = targetSource[sourceRoot.length..]
					While resolvedUnitPath.StartsWith("/")
						resolvedUnitPath = resolvedUnitPath[1..]
					Wend
					' Header paths are filesystem paths, not case-insensitive source
					' identities. Preserve the spelling supplied by the resolved
					' interface so case-sensitive hosts can open generated headers.
					If resolvedUnitPath.length Then Return resolvedUnitPath
				End If
			End If
		End If
		Local basePath:String
		If options Then basePath = options.sourceUnitPath.Replace("\\", "/")
		Local baseDirectory:String = ExtractDir(basePath)
		Local candidate:String = logicalName.Replace("\\", "/")
		If baseDirectory.length Then candidate = baseDirectory + "/" + candidate
		Local parts:String[] = candidate.Split("/")
		Local normalized:String[] = New String[0]
		For Local part:String = EachIn parts
			If Not part.length Or part = "." Then Continue
			If part = ".." Then
				If Not normalized.length Then Return ""
				normalized = normalized[..normalized.length - 1]
			Else
				normalized :+ [part]
			End If
		Next
		Local resultPath:String
		For Local index:Int = 0 Until normalized.length
			If index Then resultPath :+ "/"
			resultPath :+ normalized[index]
		Next
		Return resultPath
	End Method

	Function InterfaceDeclaredSourceSpelling:String(interfaceFile:TInterfaceFile, targetSource:String)
		If Not interfaceFile Or Not targetSource.length Then Return ""
		Return RecordDeclaredSourceSpelling(interfaceFile.declarations, targetSource.Replace("\\", "/").ToLower())
	End Function

	Function RecordDeclaredSourceSpelling:String(records:TInterfaceRecord[], normalizedTarget:String)
		For Local record:TInterfaceRecord = EachIn records
			If Not record Then Continue
			If record.originPath.length Then
				Local originPath:String = record.originPath.Replace("\\", "/")
				If originPath.ToLower() = normalizedTarget Then Return originPath
			End If
			Local nested:String = RecordDeclaredSourceSpelling(record.members, normalizedTarget)
			If nested.length Then Return nested
		Next
		Return ""
	End Function

	Method ModuleHeaderPath:String(moduleName:String)
		Local normalized:String = moduleName.ToLower()
		Local dot:Int = normalized.FindLast(".")
		If dot < 0 Then Return ""
		Local leaf:String = normalized[dot + 1..]
		Local mung:String
		If options Then mung = options.InterfaceMung()
		Return normalized.Replace(".", ".mod/") + ".mod/.bmx/" + leaf + ".bmx." + mung + ".h"
	End Method

	Method RegisterSymbol:String(symbol:TSymbol, prefix:String)
		If Not symbol Then Return ""
		Local existing:String = String(symbolsById.ValueForKey(symbol))
		If existing.length Then Return existing
		Local identifier:String
		If prefix = "g" Then
			' Local/parameter numbering restarts for readable per-routine IR,
			' but Globals can be referenced from any routine and therefore need
			' module-wide identity. This includes function-scope Globals.
			identifier = prefix + nextGlobalSymbolId
			nextGlobalSymbolId :+ 1
		Else
			identifier = prefix + nextSymbolId
		End If
		nextSymbolId :+ 1
		symbolsById.Insert(symbol, identifier)
		Return identifier
	End Method

	Method SymbolId:String(symbol:TSymbol)
		If Not symbol Then Return ""
		Return String(symbolsById.ValueForKey(symbol))
	End Method

	Method SourceOf:TCompilerSourceLocation(syntax:TSyntaxNode)
		Local source:TCompilerSourceLocation = New TCompilerSourceLocation
		If syntax Then source.span = syntax.span
		For Local index:Int = 0 Until navigators.length
			If navigators[index] And navigators[index].ContainsNode(syntax) Then
				source.path = documents[index].path
				PopulateSourcePosition(source, documents[index])
				Return source
			End If
		Next
		If analysis And analysis.syntaxTree Then
			source.path = analysis.syntaxTree.source.path
			If documents.length Then PopulateSourcePosition(source, documents[0])
		End If
		Return source
	End Method

	Method SourceForSymbol:TCompilerSourceLocation(symbol:TSymbol)
		If symbol And symbol.declaration Then
			Local declaredSource:TCompilerSourceLocation = SourceOf(symbol.declaration)
			If declaredSource.span Then Return declaredSource
			' Some Extern declarations have catalogue provenance but no aggregate
			' declaration span. Preserve that line rather than reporting only the file.
			If symbol.originPath.length Then declaredSource.path = symbol.originPath
			declaredSource.line = symbol.originLine
			declaredSource.column = symbol.originColumn
			declaredSource.debugSourceId = RegisterDebugSource(declaredSource.path)
			Return declaredSource
		End If
		Local source:TCompilerSourceLocation = New TCompilerSourceLocation
		If symbol Then
			source.path = symbol.originPath
			source.line = symbol.originLine
			source.column = symbol.originColumn
			source.debugSourceId = RegisterDebugSource(source.path)
		End If
		Return source
	End Method

	Method PopulateSourcePosition(source:TCompilerSourceLocation, document:TSourceDocumentModel)
		If Not source Or Not document Or Not document.tree Then Return
		If source.span Then
			Local position:TSourcePosition = document.tree.source.Position(source.span.start)
			source.line = position.line + 1
			source.column = position.column
		End If
		source.debugSourceId = RegisterDebugSource(source.path)
	End Method

	Method RegisterDebugSource:ULong(path:String)
		If Not options Or Not options.debugInstrumentation Or Not path.length Then Return 0
		Local normalized:String = path.Replace("\", "/")
		Local existing:TCompilerIrDebugSource = TCompilerIrDebugSource(debugSourcesByPath.ValueForKey(normalized))
		If existing Then Return existing.sourceId
		Local debugSource:TCompilerIrDebugSource = New TCompilerIrDebugSource
		debugSource.path = normalized
		debugSource.sourceId = DebugSourceHash(normalized)
		debugSourcesByPath.Insert(normalized, debugSource)
		result.debugSources :+ [debugSource]
		Return debugSource.sourceId
	End Method

	Function DebugSourceHash:ULong(path:String)
		Local hash:ULong = $cbf29ce484222325:ULong
		For Local index:Int = 0 Until path.length
			hash :~ ULong(path[index])
			hash :* 1099511628211:ULong
		Next
		If hash = 0 Then hash = 1
		Return hash
	End Function

	Method MarkCoveragePoint(statement:TCompilerIrStatement, syntax:TSyntaxNode)
		If Not statement Or Not currentRoutine Or Not currentRoutine.coverageInstrumentation Then Return
		Local source:TCompilerSourceLocation = SourceOf(syntax)
		If Not source Or Not source.path.length Or source.line <= 0 Then Return
		statement.coveragePoint = True
	End Method

	Method BuildCoverageCatalog()
		If Not options Or Not options.coverageInstrumentation Or Not result Then Return
		For Local routine:TCompilerIrFunction = EachIn result.functions
			If Not routine Then Continue
			If routine.coverageFunction And routine.source And routine.source.path.length And routine.source.line > 0 Then
				Local file:TCompilerIrCoverageFile = CoverageFile(routine.source.path)
				AddCoverageFunction(file, routine.coverageName, routine.source.line)
			End If
			CollectCoverageBlock(routine.body)
		Next
	End Method

	Method CollectCoverageBlock(block:TCompilerIrBlock)
		If Not block Then Return
		For Local statement:TCompilerIrStatement = EachIn block.statements
			If Not statement Then Continue
			If statement.coveragePoint And statement.source And statement.source.path.length And statement.source.line > 0 Then
				AddCoverageLine(CoverageFile(statement.source.path), statement.source.line)
			End If
			Local conditional:TCompilerIrIf = TCompilerIrIf(statement)
			If conditional Then
				CollectCoverageBlock(conditional.thenBody)
				For Local clause:TCompilerIrConditionalClause = EachIn conditional.elseIfClauses
					If clause Then CollectCoverageBlock(clause.body)
				Next
				CollectCoverageBlock(conditional.elseBody)
				Continue
			End If
			Local selected:TCompilerIrSelect = TCompilerIrSelect(statement)
			If selected Then
				For Local selectedCase:TCompilerIrSelectCase = EachIn selected.cases
					If selectedCase Then CollectCoverageBlock(selectedCase.body)
				Next
				CollectCoverageBlock(selected.defaultBody)
				Continue
			End If
			Local guarded:TCompilerIrTry = TCompilerIrTry(statement)
			If guarded Then
				CollectCoverageBlock(guarded.body)
				For Local guardedCatch:TCompilerIrCatch = EachIn guarded.catches
					If guardedCatch Then CollectCoverageBlock(guardedCatch.body)
				Next
				CollectCoverageBlock(guarded.finallyBody)
				Continue
			End If
			Local usingStatement:TCompilerIrUsing = TCompilerIrUsing(statement)
			If usingStatement Then CollectCoverageBlock(usingStatement.body); Continue
			Local whileStatement:TCompilerIrWhile = TCompilerIrWhile(statement)
			If whileStatement Then CollectCoverageBlock(whileStatement.body); Continue
			Local repeatStatement:TCompilerIrRepeat = TCompilerIrRepeat(statement)
			If repeatStatement Then CollectCoverageBlock(repeatStatement.body); Continue
			Local rangeStatement:TCompilerIrForRange = TCompilerIrForRange(statement)
			If rangeStatement Then CollectCoverageBlock(rangeStatement.body); Continue
			Local arrayEach:TCompilerIrForEachArray = TCompilerIrForEachArray(statement)
			If arrayEach Then CollectCoverageBlock(arrayEach.body); Continue
			Local stringEach:TCompilerIrForEachString = TCompilerIrForEachString(statement)
			If stringEach Then CollectCoverageBlock(stringEach.body); Continue
			Local staticEach:TCompilerIrForEachStaticArray = TCompilerIrForEachStaticArray(statement)
			If staticEach Then CollectCoverageBlock(staticEach.body); Continue
			Local objectEach:TCompilerIrForEachObject = TCompilerIrForEachObject(statement)
			If objectEach Then CollectCoverageBlock(objectEach.body)
		Next
	End Method

	Method CoverageFile:TCompilerIrCoverageFile(path:String)
		Local normalized:String = path.Replace("\", "/")
		For Local file:TCompilerIrCoverageFile = EachIn result.coverageFiles
			If file.path = normalized Then Return file
		Next
		Local file:TCompilerIrCoverageFile = New TCompilerIrCoverageFile
		file.path = normalized
		result.coverageFiles :+ [file]
		Return file
	End Method

	Function AddCoverageLine(file:TCompilerIrCoverageFile, line:Int)
		If Not file Or line <= 0 Then Return
		For Local known:Int = EachIn file.lines
			If known = line Then Return
		Next
		file.lines :+ [line]
	End Function

	Function AddCoverageFunction(file:TCompilerIrCoverageFile, name:String, line:Int)
		If Not file Or Not name.length Or line <= 0 Then Return
		For Local known:TCompilerIrCoverageFunction = EachIn file.functions
			If known.name = name And known.line = line Then Return
		Next
		Local value:TCompilerIrCoverageFunction = New TCompilerIrCoverageFunction
		value.name = name
		value.line = line
		file.functions :+ [value]
	End Function

	Method AddUnsupported(code:String, message:String, syntax:TSyntaxNode)
		Local source:TCompilerSourceLocation = SourceOf(syntax)
		diagnostics :+ [TCompilerDiagnostic.Create(code, message, source.path, source.span, source.line, source.column)]
	End Method

	Method ApplyInstrumentation(routine:TCompilerIrFunction, declaration:TRoutineDeclarationSyntax)
		If Not options Then Return
		routine.debugInstrumentation = options.debugInstrumentation
		routine.coverageInstrumentation = options.coverageInstrumentation
		If routine.coverageInstrumentation And Not routine.isAbstract Then
			routine.coverageFunction = True
			If routine.isFunctionLiteral Then
				routine.coverageName = routine.debugName
				' A physical source line may contain more than one literal. Keep
				' the readable debugger identity while making the LCOV function
				' key deterministic and collision-free at source granularity.
				If routine.source And routine.source.column > 0 Then routine.coverageName :+ " column " + routine.source.column
			Else If declaration Then
				routine.coverageName = routine.name
			Else
				routine.coverageName = "__LocalMain"
			End If
		End If
		routine.suppressDebugInfo = compilationNoDebug Or RoutineIsNoDebug(declaration)
	End Method

	Method CompilationHasNoDebug:Int()
		If Not analysis Or Not analysis.syntaxTree Or Not analysis.syntaxTree.root Then Return False
		For Local member:TSyntaxNode = EachIn analysis.syntaxTree.root.members
			Local raw:TRawStatementSyntax = TRawStatementSyntax(member)
			If raw And raw.tokens.length And raw.tokens[0].text.ToLower() = "nodebug" Then Return True
		Next
		Return False
	End Method

	Function RoutineIsNoDebug:Int(declaration:TRoutineDeclarationSyntax)
		If Not declaration Or Not declaration.signature Then Return False
		For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
			If token.text.ToLower() = "nodebug" Then Return True
		Next
		Return False
	End Function

	Function RoutineDeclarationIsFinal:Int(declaration:TRoutineDeclarationSyntax)
		If Not declaration Or Not declaration.signature Then Return False
		For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
			If token.text.ToLower() = "final" Then Return True
		Next
		Return False
	End Function

	Function TypeDeclarationIsFinal:Int(declaration:TTypeDeclarationSyntax)
		If Not declaration Or Not declaration.header Then Return False
		For Local token:TSyntaxToken = EachIn declaration.header.modifierTokens
			If token.text.ToLower() = "final" Then Return True
		Next
		Return False
	End Function

	Function TypeName:String(semanticType:TSemanticType)
		If semanticType Then Return semanticType.DisplayName()
		Return "?"
	End Function

	Method IsSupportedReturnType:Int(returnType:TSemanticType)
		If IsVoidType(returnType) Then Return True
		If TCallableSemanticType(returnType) Then Return IsSupportedCallableType(TCallableSemanticType(returnType))
		If TClosureSemanticType(returnType) Then Return IsSupportedClosureType(TClosureSemanticType(returnType))
		Return IsSupportedValueType(returnType)
	End Method

	Function IsVoidType:Int(semanticType:TSemanticType)
		Return TBuiltinSemanticType(semanticType) And semanticType.DisplayName().ToLower() = "void"
	End Function

	Function IsNullType:Int(semanticType:TSemanticType)
		Return TBuiltinSemanticType(semanticType) And semanticType.DisplayName().ToLower() = "null"
	End Function

	Method IsSupportedValueType:Int(semanticType:TSemanticType)
		If TClosureSemanticType(semanticType) Then Return IsSupportedClosureType(TClosureSemanticType(semanticType))
		If EnumForType(semanticType) Then Return True
		If StructForType(semanticType) Then Return True
		If ImportedStructForType(semanticType) Then Return True
		' Interface layouts are completed before source class shells are built.
		' Accept an ordinary nominal managed reference from its semantic identity
		' so an Interface may mention a source Type declared in the same module.
		Local namedReference:TNamedSemanticType = TNamedSemanticType(semanticType)
		If namedReference And namedReference.symbol And namedReference.symbol.kind = SYMBOL_INTERFACE And namedReference.symbol.isExternal Then Return EnsureInterfaceShell(namedReference.symbol) <> Null
		If namedReference And namedReference.symbol And Not namedReference.symbol.isImported And namedReference.symbol.genericArity = 0 Then
			If namedReference.symbol.kind = SYMBOL_TYPE Or namedReference.symbol.kind = SYMBOL_INTERFACE Then Return True
		End If
		If IsObjectReferenceType(semanticType) Then Return True
		If namedReference And namedReference.symbol And namedReference.symbol.kind = SYMBOL_INTERFACE And namedReference.typeArguments.length Then
			RegisterOpaqueInterfaceType(TypeName(semanticType))
			Return True
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(semanticType)
		If arrayType Then Return arrayType.rank > 0 And IsSupportedArrayElementType(arrayType.elementType)
		Local pointer:TPointerSemanticType = TPointerSemanticType(semanticType)
		If pointer Then Return IsSupportedPointerElementType(pointer.elementType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam", "float", "double", "float64", "int128", "float128", "double128", "string"
				Return True
		End Select
		Return False
	End Method

	Method RegisterOpaqueInterfaceType(typeName:String)
		If Not result Or Not typeName.length Then Return
		For Local existing:String = EachIn result.opaqueInterfaceTypes
			If existing.ToLower() = typeName.ToLower() Then Return
		Next
		result.opaqueInterfaceTypes :+ [typeName]
	End Method

	Function IsSupportedEnumUnderlyingType:Int(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t"
				Return True
		End Select
		Return False
	End Function

	Method IsSupportedAbiParameterType:Int(semanticType:TSemanticType)
		If IsSupportedValueType(semanticType) Then Return True
		If IsSupportedStaticArrayType(TStaticArraySemanticType(semanticType)) Then Return True
		Return IsSupportedCallableType(TCallableSemanticType(semanticType))
	End Method

	Method IsSupportedCallableType:Int(callable:TCallableSemanticType)
		If Not callable Or TCallableSemanticType(callable.returnType) Or Not IsSupportedReturnType(callable.returnType) Then Return False
		For Local index:Int = 0 Until callable.parameterTypes.length
			Local nestedCallable:TCallableSemanticType = TCallableSemanticType(callable.parameterTypes[index])
			If nestedCallable Then
				If Not IsSupportedCallableType(nestedCallable) Then Return False
			Else If Not IsSupportedValueType(callable.parameterTypes[index]) And Not IsSupportedStaticArrayType(TStaticArraySemanticType(callable.parameterTypes[index])) Then
				Return False
			End If
			If index < callable.parameterModes.length Then
				If callable.parameterModes[index] <> PARAMETER_PASS_VALUE And callable.parameterModes[index] <> PARAMETER_PASS_VAR Then Return False
				If callable.parameterModes[index] = PARAMETER_PASS_VAR And (nestedCallable Or Not IsSupportedValueType(callable.parameterTypes[index])) Then Return False
			End If
		Next
		Return True
	End Method

	Method IsSupportedClosureType:Int(closure:TClosureSemanticType)
		Return closure And closure.signature And closure.signature.callingConvention = CALLING_CONVENTION_C And IsSupportedCallableType(closure.signature)
	End Method

	Method IsSupportedParameterMode:Int(parameter:TSemanticParameter)
		If Not parameter Then Return False
		If parameter.passingMode = PARAMETER_PASS_VALUE Then Return True
		Return parameter.passingMode = PARAMETER_PASS_VAR And IsSupportedValueType(parameter.semanticType)
	End Method

	Method PopulateParameterShape(parameter:TCompilerIrParameter, semanticType:TSemanticType)
		If Not parameter Then Return
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(semanticType)
		If staticArrayType Then
			parameter.isStaticArray = True
			parameter.staticArrayElementType = TypeName(staticArrayType.elementType)
			parameter.staticArrayLength = staticArrayType.length
			Local staticArrayStruct:TCompilerIrStruct = StructForType(staticArrayType.elementType)
			Local staticArrayImportedStruct:TCompilerIrImportedStruct = ImportedStructForType(staticArrayType.elementType)
			If staticArrayStruct Then parameter.staticArrayStructId = staticArrayStruct.structId
			If staticArrayImportedStruct Then parameter.staticArrayImportedStructId = staticArrayImportedStruct.importedStructId
			Return
		End If
		PopulateCallableShape(parameter, semanticType)
	End Method

	Method PopulateCallableShape(parameter:TCompilerIrParameter, semanticType:TSemanticType)
		Local callable:TCallableSemanticType = TCallableSemanticType(semanticType)
		If Not callable Then Return
		parameter.callableReturnType = TypeName(callable.returnType)
		parameter.callableParameters = CallableParameters(callable)
		parameter.callableCallingConvention = callable.callingConvention
	End Method

	Method PopulateParameterDefault(irParameter:TCompilerIrParameter, parameter:TSemanticParameter)
		If Not irParameter Or Not parameter Or Not parameter.optional Or Not parameter.defaultValue Then Return
		irParameter.defaultKind = parameter.defaultValue.kind
		Select parameter.defaultValue.kind
			Case CONSTANT_VALUE_INTEGER, CONSTANT_VALUE_FLOAT
				irParameter.defaultText = parameter.defaultValue.DisplayValue()
			Case CONSTANT_VALUE_STRING
				irParameter.defaultStringValue = parameter.defaultValue.stringValue
			Case CONSTANT_VALUE_CALLABLE
				Local callableSymbol:TSymbol = parameter.defaultValue.callableSymbol
				If callableSymbol Then
					Local sourceRoutine:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(callableSymbol))
					If sourceRoutine Then
						irParameter.defaultCallableAbiName = sourceRoutine.abiName
					Else
						irParameter.defaultCallableAbiName = callableSymbol.externalName
					End If
				End If
		End Select
	End Method

	Method CallableParameters:TCompilerIrParameter[](callable:TCallableSemanticType)
		If Not callable Then Return New TCompilerIrParameter[0]
		Local result:TCompilerIrParameter[] = New TCompilerIrParameter[callable.parameterTypes.length]
		For Local index:Int = 0 Until callable.parameterTypes.length
			Local parameter:TCompilerIrParameter = New TCompilerIrParameter
			parameter.symbolId = "cp" + index
			parameter.name = "arg" + index
			parameter.semanticType = TypeName(callable.parameterTypes[index])
			If index < callable.parameterModes.length Then parameter.passingMode = callable.parameterModes[index]
			PopulateParameterShape(parameter, callable.parameterTypes[index])
			result[index] = parameter
		Next
		Return result
	End Method

	Method ApplyCallableParameterNames(parameters:TCompilerIrParameter[], syntax:TCallableTypeSyntax)
		If Not syntax Then Return
		For Local index:Int = 0 Until parameters.length
			If index >= syntax.parameters.length Or Not syntax.parameters[index].nameToken Then Continue
			parameters[index].name = syntax.parameters[index].nameToken.text
		Next
	End Method

	Function IsNumericType:Int(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam", "float", "double", "float64" Return True
		End Select
		Return False
	End Function

	Method IsSupportedStaticArrayType:Int(staticArrayType:TStaticArraySemanticType)
		' Callable signatures can retain their own StaticArray type instance.
		' Resolve a named constant extent here as a defensive finalization step;
		' the compile-time pass has already bound and validated the expression.
		If staticArrayType And staticArrayType.length <= 0 And staticArrayType.boundSyntax And staticArrayType.boundSyntax.lengthExpression Then
			Local extent:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(analysis.model, staticArrayType.boundSyntax.lengthExpression)
			If extent And extent.kind = CONSTANT_VALUE_INTEGER Then staticArrayType.length = extent.integerValue
		End If
		Return staticArrayType And staticArrayType.length > 0 And (IsNumericType(staticArrayType.elementType) Or EnumForType(staticArrayType.elementType) Or (IsPointerType(staticArrayType.elementType) And IsSupportedPointerElementType(staticArrayType.elementType)) Or IsManagedReferenceType(staticArrayType.elementType) Or StructForType(staticArrayType.elementType) Or ImportedStructForType(staticArrayType.elementType))
	End Method

	Method IsSupportedStaticArrayEachInConversion:Int(elementType:TSemanticType, variableType:TSemanticType)
		If IsNumericType(elementType) Then Return IsNumericType(variableType)
		If TGenericRoutineInference.SameType(elementType, variableType) Then Return True
		Local elementStruct:TCompilerIrStruct = StructForType(elementType)
		Local variableStruct:TCompilerIrStruct = StructForType(variableType)
		If elementStruct Or variableStruct Then Return elementStruct And variableStruct And elementStruct.structId = variableStruct.structId
		Local elementImported:TCompilerIrImportedStruct = ImportedStructForType(elementType)
		Local variableImported:TCompilerIrImportedStruct = ImportedStructForType(variableType)
		Return elementImported And variableImported And elementImported.importedStructId = variableImported.importedStructId
	End Method

	Function ImportedStructHasDefaultHelper:Int(importedStruct:TCompilerIrImportedStruct)
		If Not importedStruct Then Return False
		For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
			If routine.isConstructor And Not routine.parameters.length And routine.objectNewAbiName.length Then Return True
		Next
		Return False
	End Function

	Function PublishedStructElementInitializerName:String(abiName:String)
		If Not abiName.length Then Return ""
		Return "bbStructElementInit_" + abiName
	End Function

	Function StaticArrayTypeOf:TStaticArraySemanticType(expression:TBoundExpression)
		If Not expression Then Return Null
		Local result:TStaticArraySemanticType = TStaticArraySemanticType(expression.semanticType)
		Local symbolExpression:TBoundSymbolExpression = TBoundSymbolExpression(expression)
		If symbolExpression And symbolExpression.symbol Then
			Local declared:TStaticArraySemanticType = TStaticArraySemanticType(symbolExpression.symbol.declaredType)
			If declared And (Not result Or declared.length > result.length) Then result = declared
		End If
		Local memberExpression:TBoundMemberExpression = TBoundMemberExpression(expression)
		If memberExpression And memberExpression.access And memberExpression.access.member Then
			Local declared:TStaticArraySemanticType = TStaticArraySemanticType(memberExpression.access.member.declaredType)
			If declared And (Not result Or declared.length > result.length) Then result = declared
		End If
		Return result
	End Function

	Function CallableTypeOf:TCallableSemanticType(expression:TBoundExpression)
		If Not expression Then Return Null
		Local result:TCallableSemanticType = TCallableSemanticType(expression.semanticType)
		Local symbolExpression:TBoundSymbolExpression = TBoundSymbolExpression(expression)
		If Not result And symbolExpression And symbolExpression.symbol Then
			Local declared:TCallableSemanticType = TCallableSemanticType(symbolExpression.symbol.declaredType)
			If declared Then result = declared
		End If
		Local memberExpression:TBoundMemberExpression = TBoundMemberExpression(expression)
		If Not result And memberExpression And memberExpression.access And memberExpression.access.member Then
			Local declared:TCallableSemanticType = TCallableSemanticType(memberExpression.access.member.declaredType)
			If declared Then result = declared
		End If
		Return result
	End Function

	Function ClosureTypeOf:TClosureSemanticType(expression:TBoundExpression)
		If Not expression Then Return Null
		Local result:TClosureSemanticType = TClosureSemanticType(expression.semanticType)
		Local symbolExpression:TBoundSymbolExpression = TBoundSymbolExpression(expression)
		If Not result And symbolExpression And symbolExpression.symbol Then
			Local declared:TClosureSemanticType = TClosureSemanticType(symbolExpression.symbol.declaredType)
			If declared Then result = declared
		End If
		Local memberExpression:TBoundMemberExpression = TBoundMemberExpression(expression)
		If Not result And memberExpression And memberExpression.access And memberExpression.access.member Then
			Local declared:TClosureSemanticType = TClosureSemanticType(memberExpression.access.member.declaredType)
			If declared Then result = declared
		End If
		Return result
	End Function

	Method TemporaryIrReference:TCompilerIrSymbolReference(identifier:String, semanticType:String, name:String, syntax:TSyntaxNode)
		Local result:TCompilerIrSymbolReference = New TCompilerIrSymbolReference
		result.kind = IR_EXPRESSION_SYMBOL
		result.source = SourceOf(syntax)
		result.semanticType = semanticType
		result.symbolId = identifier
		result.name = name
		Return result
	End Method

	Method LowerEachInMethodCall:TCompilerIrExpression(resolved:TResolvedCall, receiver:TCompilerIrExpression, receiverType:TSemanticType, syntax:TSyntaxNode)
		If Not resolved Or Not resolved.routine Then
			AddUnsupported("BMXC1020", "ObjectEnumerator EachIn is missing a resolved protocol operation", syntax)
			Return Null
		End If
		Local protocolArguments:TCompilerIrExpression[] = New TCompilerIrExpression[resolved.routine.parameters.length]
		For Local parameterIndex:Int = 0 Until resolved.routine.parameters.length
			Local protocolParameter:TSemanticParameter = resolved.routine.parameters[parameterIndex]
			If Not protocolParameter.optional Or Not protocolParameter.defaultValue Then
				AddUnsupported("BMXC1020", "EachIn protocol method '" + resolved.routine.name + "' requires a non-default argument", syntax)
				Return Null
			End If
			Local protocolParameterType:TSemanticType = protocolParameter.semanticType
			If parameterIndex < resolved.parameterTypes.length And resolved.parameterTypes[parameterIndex] Then protocolParameterType = resolved.parameterTypes[parameterIndex]
			protocolArguments[parameterIndex] = LowerConstantDefault(protocolParameter.defaultValue, protocolParameterType, protocolParameter.symbol, syntax)
			If Not protocolArguments[parameterIndex] Then Return Null
		Next
		Return LowerReceiverMethodCall(resolved, receiver, receiverType, protocolArguments, syntax)
	End Method

	Method LowerReceiverMethodCall:TCompilerIrExpression(resolved:TResolvedCall, receiver:TCompilerIrExpression, receiverType:TSemanticType, arguments:TCompilerIrExpression[], syntax:TSyntaxNode)
		Local receiverInterface:TCompilerIrInterface = InterfaceForType(receiverType)
		If receiverInterface Then
			Local methodMap:TMap = TMap(interfaceMethodsByInterface.ValueForKey(receiverInterface))
			Local interfaceMethod:TCompilerIrInterfaceMethod
			If methodMap Then interfaceMethod = TCompilerIrInterfaceMethod(methodMap.ValueForKey(resolved.routine))
			If Not interfaceMethod Then
				For Local candidate:TCompilerIrInterfaceMethod = EachIn receiverInterface.methods
					If candidate.name.ToLower() = resolved.routine.name.ToLower() And candidate.parameters.length = resolved.routine.parameters.length Then
						interfaceMethod = candidate
						Exit
					End If
				Next
			End If
			If Not interfaceMethod Then
				AddUnsupported("BMXC1020", "Interface instance method has no emitted dispatch slot", syntax)
				Return Null
			End If
			Local interfaceCall:TCompilerIrCall = New TCompilerIrCall
			interfaceCall.kind = IR_EXPRESSION_CALL
			interfaceCall.source = SourceOf(syntax)
			interfaceCall.semanticType = TypeName(resolved.returnType)
			interfaceCall.functionId = receiverInterface.interfaceId + "." + interfaceMethod.slotId
			interfaceCall.functionName = interfaceMethod.name
			interfaceCall.dispatchKind = IR_CALL_DISPATCH_INTERFACE
			interfaceCall.receiver = receiver
			interfaceCall.interfaceId = receiverInterface.interfaceId
			interfaceCall.interfaceSlotId = interfaceMethod.slotId
			interfaceCall.arguments = arguments
			Return interfaceCall
		End If
		Local importedReceiver:TCompilerIrImportedClass = ImportedClassForType(receiverType)
		If importedReceiver Then
			Local protocolMethod:TCompilerIrImportedMethod
			If importedReceiver.isGenericSpecialization Then
				protocolMethod = GenericImportedMethod(importedReceiver, resolved.routine)
			Else
				protocolMethod = ImportedMethod(resolved.routine, syntax)
			End If
			If Not protocolMethod Then
				AddUnsupported("BMXC1020", "Imported Type instance method has no published class-slot ABI", syntax)
				Return Null
			End If
			Local importedCall:TCompilerIrCall = New TCompilerIrCall
			importedCall.kind = IR_EXPRESSION_CALL
			importedCall.source = SourceOf(syntax)
			importedCall.semanticType = TypeName(resolved.returnType)
			importedCall.functionId = protocolMethod.methodId
			importedCall.functionName = protocolMethod.name
			importedCall.dispatchKind = IR_CALL_DISPATCH_IMPORTED_VIRTUAL
			importedCall.receiver = receiver
			importedCall.classId = importedReceiver.importedClassId
			importedCall.classSlotId = protocolMethod.methodId
			importedCall.arguments = arguments
			Return importedCall
		End If
		Local sourceReceiver:TCompilerIrClass = ClassForType(receiverType)
		Local inheritedImportedMethod:TCompilerIrImportedMethod = ImportedMethod(resolved.routine, syntax)
		If sourceReceiver And inheritedImportedMethod Then
			Local inheritedSlot:TCompilerIrClassFunctionSlot = SourceClassImportedSlot(sourceReceiver, inheritedImportedMethod)
			If Not inheritedSlot Then
				AddUnsupported("BMXC1020", "Inherited imported instance method has no source-class slot", syntax)
				Return Null
			End If
			Local inheritedCall:TCompilerIrCall = New TCompilerIrCall
			inheritedCall.kind = IR_EXPRESSION_CALL
			inheritedCall.source = SourceOf(syntax)
			inheritedCall.semanticType = TypeName(resolved.returnType)
			inheritedCall.functionId = inheritedImportedMethod.methodId
			inheritedCall.functionName = inheritedImportedMethod.name
			inheritedCall.dispatchKind = IR_CALL_DISPATCH_VIRTUAL
			inheritedCall.receiver = receiver
			inheritedCall.classId = sourceReceiver.classId
			inheritedCall.classSlotId = inheritedSlot.slotId
			inheritedCall.arguments = arguments
			Return inheritedCall
		End If
		Local target:TCompilerIrFunction = TCompilerIrFunction(functionsBySymbol.ValueForKey(resolved.routine))
		If Not target Or Not target.isMethod Then
			AddUnsupported("BMXC1020", "Instance operation must resolve to a lowered source method", syntax)
			Return Null
		End If
		Local receiverClass:TCompilerIrClass = ClassForType(receiverType)
		If Not receiverClass Then
			AddUnsupported("BMXC1020", "Instance method receiver has no lowered source class", syntax)
			Return Null
		End If
		Local result:TCompilerIrCall = New TCompilerIrCall
		result.kind = IR_EXPRESSION_CALL
		result.source = SourceOf(syntax)
		result.semanticType = TypeName(resolved.returnType)
		result.functionId = target.functionId
		result.functionName = target.name
		result.dispatchKind = IR_CALL_DISPATCH_VIRTUAL
		result.receiver = receiver
		result.classId = receiverClass.classId
		result.classSlotId = target.classSlotId
		result.objectSlotKind = target.objectSlotKind
		result.arguments = arguments
		Return result
	End Method

	Method IsLoweredEachInReceiver:Int(semanticType:TSemanticType)
		If ClassForType(semanticType) Then Return True
		If ImportedClassForType(semanticType) Then Return True
		Return InterfaceForType(semanticType) <> Null
	End Method

	Method IsSupportedClassFieldType:Int(semanticType:TSemanticType)
		If IsSupportedValueType(semanticType) Then Return True
		Return IsSupportedCallableType(TCallableSemanticType(semanticType))
	End Method

	Method IsSupportedStructFieldType:Int(semanticType:TSemanticType)
		If TPointerSemanticType(semanticType) Then Return IsSupportedPointerElementType(TPointerSemanticType(semanticType).elementType)
		If IsSupportedCallableType(TCallableSemanticType(semanticType)) Then Return True
		If EnumForType(semanticType) Then Return True
		If StructForType(semanticType) Then Return True
		If ImportedStructForType(semanticType) Then Return True
		Return IsNumericType(semanticType) Or IsManagedReferenceType(semanticType)
	End Method

	Method StructForType:TCompilerIrStruct(semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol And named.symbol.kind = SYMBOL_STRUCT Then Return TCompilerIrStruct(structsBySymbol.ValueForKey(named.symbol))
		Return Null
	End Method

	Method ImportedStructForType:TCompilerIrImportedStruct(semanticType:TSemanticType)
		Local genericStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(genericStructsByTypeName.ValueForKey(TypeName(semanticType).ToLower()))
		If genericStruct Then Return genericStruct
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol And named.symbol.kind = SYMBOL_STRUCT And named.symbol.isImported Then Return EnsureImportedStruct(named.symbol)
		Return Null
	End Method

	Method EnsureImportedStruct:TCompilerIrImportedStruct(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_STRUCT Or Not symbol.isImported Then Return Null
		Local known:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsBySymbol.ValueForKey(symbol))
		If known And completedImportedStructLayouts.Contains(symbol) Then Return known
		If known And visitingImportedStructLayouts.Contains(symbol) Then
			AddUnsupported("BMXC1192", "Imported Struct value layout cycle involving '" + symbol.name + "'", symbol.declaration)
			Return known
		End If
		If symbol.genericArity <> 0 Then
			AddUnsupported("BMXC1197", "Generic imported Struct '" + symbol.QualifiedName() + "' requires canonical specialization lowering", symbol.declaration)
			Return Null
		End If
		If Not symbol.externalName.length Or TCompilerAbiNamer.Sanitize(symbol.externalName) <> symbol.externalName Then
			AddUnsupported("BMXC1198", "Imported Struct '" + symbol.QualifiedName() + "' has no usable C ABI name", symbol.declaration)
			Return Null
		End If
		Local existing:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsByAbiName.ValueForKey(symbol.externalName.ToLower()))
		If existing Then
			importedStructsBySymbol.Insert(symbol, existing)
			Return existing
		End If
		Local importedStruct:TCompilerIrImportedStruct = New TCompilerIrImportedStruct
		importedStruct.importedStructId = "ist" + nextImportedStructId
		nextImportedStructId :+ 1
		importedStruct.name = symbol.name
		importedStruct.abiName = symbol.externalName
		importedStruct.elementInitializerAbiName = PublishedStructElementInitializerName(symbol.externalName)
		importedStruct.semanticType = TypeName(symbol.declaredType)
		importedStruct.originModule = symbol.originModule
		importedStruct.source = SourceForSymbol(symbol)
		importedStruct.metadata = MetadataOf(symbol)
		importedStructsBySymbol.Insert(symbol, importedStruct)
		importedStructsByAbiName.Insert(symbol.externalName.ToLower(), importedStruct)
		result.importedStructs :+ [importedStruct]
		visitingImportedStructLayouts.Insert(symbol, symbol)
		If symbol.memberScope Then
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If Not member Then Continue
				If member.kind = SYMBOL_FIELD Then
					Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(member.declaredType)
					Local fieldElementType:TSemanticType = member.declaredType
					If staticArrayType Then fieldElementType = staticArrayType.elementType
					Local nestedStruct:TCompilerIrStruct
					Local nestedImportedStruct:TCompilerIrImportedStruct
					Local named:TNamedSemanticType = TNamedSemanticType(fieldElementType)
					If named And named.symbol And named.symbol.kind = SYMBOL_STRUCT Then
						nestedStruct = StructForType(fieldElementType)
						nestedImportedStruct = ImportedStructForType(fieldElementType)
					End If
					Local supportedField:Int
					If staticArrayType Then
						supportedField = IsSupportedStaticArrayType(staticArrayType)
					Else
						supportedField = nestedStruct <> Null Or nestedImportedStruct <> Null
						If Not supportedField Then supportedField = IsSupportedStructFieldType(member.declaredType)
					End If
					If Not supportedField Then
						AddUnsupported("BMXC1199", "Imported Struct field type '" + TypeName(member.declaredType) + "' is outside the current layout slice", member.declaration)
						Continue
					End If
					Local fieldRecord:TCompilerIrImportedField = New TCompilerIrImportedField
					fieldRecord.fieldId = "isf" + nextImportedStructFieldId
					nextImportedStructFieldId :+ 1
					fieldRecord.declaringImportedStructId = importedStruct.importedStructId
					fieldRecord.name = member.name
					fieldRecord.abiName = TCompilerAbiNamer.Sanitize("_" + symbol.externalName.ToLower() + "_" + member.name.ToLower())
					fieldRecord.semanticType = TypeName(member.declaredType)
					Local callableType:TCallableSemanticType = TCallableSemanticType(member.declaredType)
					If callableType Then
						fieldRecord.callableReturnType = TypeName(callableType.returnType)
						fieldRecord.callableParameters = CallableParameters(callableType)
						fieldRecord.callableCallingConvention = callableType.callingConvention
					End If
					If staticArrayType Then
						fieldRecord.isStaticArray = True
						fieldRecord.staticArrayElementType = TypeName(fieldElementType)
						fieldRecord.staticArrayLength = staticArrayType.length
						If nestedStruct Then fieldRecord.staticArrayStructId = nestedStruct.structId
						If nestedImportedStruct Then fieldRecord.staticArrayImportedStructId = nestedImportedStruct.importedStructId
					Else
						If nestedStruct Then fieldRecord.structId = nestedStruct.structId
						If nestedImportedStruct Then fieldRecord.importedStructId = nestedImportedStruct.importedStructId
					End If
					fieldRecord.visibility = member.visibility
					fieldRecord.isReadOnly = member.isReadOnly
					fieldRecord.source = SourceForSymbol(member)
					fieldRecord.metadata = MetadataOf(member)
					If Not staticArrayType And IsManagedReferenceType(member.declaredType) Then importedStruct.containsManagedReferences = True
					If nestedStruct And nestedStruct.containsManagedReferences Then importedStruct.containsManagedReferences = True
					If nestedImportedStruct And nestedImportedStruct.containsManagedReferences Then importedStruct.containsManagedReferences = True
					importedStructFieldsBySymbol.Insert(member, fieldRecord)
					importedStruct.fields :+ [fieldRecord]
				End If
			Next
		End If
		visitingImportedStructLayouts.Remove(symbol)
		completedImportedStructLayouts.Insert(symbol, symbol)
		If symbol.memberScope Then
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If member And member.kind = SYMBOL_ROUTINE And member.genericArity = 0 Then ImportedStructRoutine(member, member.declaration)
			Next
		End If
		' Struct storage always has a value-default construction path, even when
		' the source declares only parameterized New overloads.  Production
		' snapshots do not publish that helper as a separate New() record, but
		' their ABI still owns <struct>_New_ObjectNew.  Reconstruct the implicit
		' helper here instead of treating a missing interface record as a missing
		' language capability.
		Local hasZeroArgumentConstructor:Int
		For Local routine:TCompilerIrImportedStructRoutine = EachIn importedStruct.routines
			If routine.isConstructor And Not routine.parameters.length Then hasZeroArgumentConstructor = True; Exit
		Next
		If Not hasZeroArgumentConstructor Then
			Local defaultConstructor:TCompilerIrImportedStructRoutine = New TCompilerIrImportedStructRoutine
			defaultConstructor.routineId = importedStruct.importedStructId + "_default_new"
			defaultConstructor.name = "New"
			defaultConstructor.objectNewAbiName = importedStruct.abiName + "_New_ObjectNew"
			defaultConstructor.returnType = importedStruct.semanticType
			defaultConstructor.isConstructor = True
			defaultConstructor.source = importedStruct.source
			importedStruct.routines :+ [defaultConstructor]
		End If
		Return importedStruct
	End Method

	Method ImportedStructRoutine:TCompilerIrImportedStructRoutine(symbol:TSymbol, useSyntax:TSyntaxNode)
		If Not symbol Or Not symbol.isImported Or symbol.kind <> SYMBOL_ROUTINE Or Not symbol.containingScope Or Not symbol.containingScope.owner Then Return Null
		Local known:TCompilerIrImportedStructRoutine = TCompilerIrImportedStructRoutine(importedStructRoutinesBySymbol.ValueForKey(symbol))
		If known Then Return known
		Local owner:TCompilerIrImportedStruct = TCompilerIrImportedStruct(importedStructsBySymbol.ValueForKey(symbol.containingScope.owner))
		If Not owner Then owner = EnsureImportedStruct(symbol.containingScope.owner)
		If Not owner Then Return Null
		If symbol.genericArity <> 0 Or Not symbol.externalName.length Then
			AddUnsupported("BMXC1199", "Imported Struct routine '" + symbol.QualifiedName() + "' has no supported ABI identity", useSyntax)
			Return Null
		End If
		If Not IsSupportedReturnType(symbol.declaredType) Then
			AddUnsupported("BMXC1199", "Imported Struct routine return type '" + TypeName(symbol.declaredType) + "' is outside the current value slice", useSyntax)
			Return Null
		End If
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			If Not parameter Or Not IsSupportedAbiParameterType(parameter.semanticType) Then
				AddUnsupported("BMXC1199", "Imported Struct routine parameters require supported value ABI types", useSyntax)
				Return Null
			End If
			If Not IsSupportedParameterMode(parameter) Then
				AddUnsupported("BMXC1199", "Imported Struct routine parameters require supported value or Var ABI modes", useSyntax)
				Return Null
			End If
		Next
		Local routine:TCompilerIrImportedStructRoutine = New TCompilerIrImportedStructRoutine
		routine.routineId = "isr" + nextImportedStructRoutineId
		nextImportedStructRoutineId :+ 1
		routine.name = symbol.name
		routine.abiName = symbol.externalName
		routine.returnType = TypeName(symbol.declaredType)
		Local callableReturn:TCallableSemanticType = TCallableSemanticType(symbol.declaredType)
		If callableReturn Then
			routine.callableReturnType = TypeName(callableReturn.returnType)
			routine.callableReturnParameters = CallableParameters(callableReturn)
			routine.callableReturnCallingConvention = callableReturn.callingConvention
		End If
		routine.callingConvention = symbol.callingConvention
		routine.isMethod = symbol.interfaceRecord And symbol.interfaceRecord.kind = INTERFACE_RECORD_METHOD
		routine.isConstructor = routine.isMethod And symbol.name.ToLower() = "new"
		If routine.isMethod Then routine.implementationAbiName = "_" + routine.abiName
		If routine.isConstructor Then routine.objectNewAbiName = routine.abiName + "_ObjectNew"
		routine.source = SourceForSymbol(symbol)
		routine.metadata = MetadataOf(symbol)
		routine.parameters = New TCompilerIrParameter[symbol.parameters.length]
		For Local index:Int = 0 Until symbol.parameters.length
			Local sourceParameter:TSemanticParameter = symbol.parameters[index]
			Local parameter:TCompilerIrParameter = New TCompilerIrParameter
			parameter.symbolId = "isp" + index
			If sourceParameter.symbol Then parameter.name = sourceParameter.symbol.name Else parameter.name = "arg" + index
			parameter.semanticType = TypeName(sourceParameter.semanticType)
			parameter.passingMode = sourceParameter.passingMode
			PopulateParameterDefault(parameter, sourceParameter)
			PopulateParameterShape(parameter, sourceParameter.semanticType)
			routine.parameters[index] = parameter
		Next
		importedStructRoutinesBySymbol.Insert(symbol, routine)
		owner.routines :+ [routine]
		Return routine
	End Method

	Method IsManagedReferenceType:Int(semanticType:TSemanticType)
		If TClosureSemanticType(semanticType) Then Return True
		If IsStringType(semanticType) Or IsArrayType(semanticType) Then Return True
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol And named.symbol.kind = SYMBOL_INTERFACE And named.symbol.isExternal Then Return False
		If named And named.symbol Then Return named.symbol.kind = SYMBOL_TYPE Or named.symbol.kind = SYMBOL_INTERFACE
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		Return builtin And builtin.name.ToLower() = "object"
	End Method

	Method IsExternInterfaceType:Int(semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol And named.symbol.kind = SYMBOL_INTERFACE Then Return named.symbol.isExternal
		Local irInterface:TCompilerIrInterface = InterfaceForType(semanticType)
		Return irInterface And irInterface.isExternInterface
	End Method

	Method IsManagedValueType:Int(semanticType:TSemanticType)
		If IsManagedReferenceType(semanticType) Then Return True
		Local irStruct:TCompilerIrStruct = StructForType(semanticType)
		If irStruct Then Return irStruct.containsManagedReferences
		Local importedStruct:TCompilerIrImportedStruct = ImportedStructForType(semanticType)
		Return importedStruct And importedStruct.containsManagedReferences
	End Method

	Method IsObjectReferenceType:Int(semanticType:TSemanticType)
		' String and arrays have dedicated runtime representations and typed IR.
		' Their interface symbols are nominal Types in the core snapshot, but
		' asking for an imported object layout here would incorrectly construct
		' virtual slots for their direct runtime-function methods.
		If IsStringType(semanticType) Or IsArrayType(semanticType) Then Return False
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol And named.symbol.kind = SYMBOL_INTERFACE And named.symbol.isExternal Then Return False
		If ImportedClassForType(semanticType) Then Return True
		If InterfaceForType(semanticType) Then Return True
		If named And named.symbol Then
			If classesBySymbol.Contains(named.symbol) Then Return True
			If named.symbol.kind = SYMBOL_INTERFACE Then Return EnsureInterfaceShell(named.symbol) <> Null
		End If
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		Return builtin And builtin.name.ToLower() = "object"
	End Method

	Function IsBuiltinObjectType:Int(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		Return builtin And builtin.name.ToLower() = "object"
	End Function

	Method InterfaceForType:TCompilerIrInterface(semanticType:TSemanticType)
		Local genericInterface:TCompilerIrInterface = TCompilerIrInterface(genericInterfacesByTypeName.ValueForKey(TypeName(semanticType).ToLower()))
		If genericInterface Then Return genericInterface
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol And named.symbol.kind = SYMBOL_INTERFACE Then Return EnsureInterfaceShell(named.symbol)
		Return Null
	End Method

	Method ImportedClassForType:TCompilerIrImportedClass(semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named Then
			Local genericClass:TCompilerIrImportedClass = TCompilerIrImportedClass(genericClassesByTypeName.ValueForKey(TypeName(semanticType).ToLower()))
			If genericClass Then Return genericClass
		End If
		If named And named.symbol And named.symbol.kind = SYMBOL_TYPE And named.symbol.isImported Then Return EnsureImportedClass(named.symbol)
		Return Null
	End Method

	Method SourceClassImportedSlot:TCompilerIrClassFunctionSlot(irClass:TCompilerIrClass, importedMethod:TCompilerIrImportedMethod)
		If Not irClass Or Not importedMethod Then Return Null
		For Local slot:TCompilerIrClassFunctionSlot = EachIn irClass.functionSlots
			If slot.slotName = importedMethod.slotName Then Return slot
		Next
		Return Null
	End Method

	Method GenericImportedBaseForType:TCompilerIrImportedClass(semanticType:TSemanticType, methodOwner:TSymbol)
		If Not methodOwner Then Return Null
		Local sourceBase:TCompilerIrImportedClass = GenericImportedBaseForClass(ClassForType(semanticType), methodOwner)
		If sourceBase Then Return sourceBase
		Return GenericImportedBaseForImportedClass(ImportedClassForType(semanticType), methodOwner)
	End Method

	Method GenericImportedBaseForClass:TCompilerIrImportedClass(irClass:TCompilerIrClass, methodOwner:TSymbol)
		If Not irClass Or Not methodOwner Then Return Null
		If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			While importedBase
				If ImportedSpecializationMatchesOwner(importedBase, methodOwner) Then Return importedBase
				If Not importedBase.baseImportedClassId.length Then Exit
				importedBase = ImportedClassById(importedBase.baseImportedClassId)
			Wend
		End If
		If irClass.baseClassId.length Then Return GenericImportedBaseForClass(ClassById(irClass.baseClassId), methodOwner)
		Return Null
	End Method

	Method GenericImportedBaseForImportedClass:TCompilerIrImportedClass(importedClass:TCompilerIrImportedClass, methodOwner:TSymbol)
		If Not importedClass Or Not methodOwner Then Return Null
		While importedClass
			If ImportedSpecializationMatchesOwner(importedClass, methodOwner) Then Return importedClass
			If Not importedClass.baseImportedClassId.length Then Exit
			importedClass = ImportedClassById(importedClass.baseImportedClassId)
		Wend
		Return Null
	End Method

	Function ImportedSpecializationMatchesOwner:Int(importedClass:TCompilerIrImportedClass, owner:TSymbol)
		If Not importedClass Or Not importedClass.isGenericSpecialization Or Not owner Then Return False
		If importedClass.name.ToLower() <> owner.name.ToLower() Then Return False
		If importedClass.originModule.length And owner.originModule.length Then Return importedClass.originModule.ToLower() = owner.originModule.ToLower()
		Return True
	End Function

	Method EnsureImportedClass:TCompilerIrImportedClass(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_TYPE Or Not symbol.isImported Then Return Null
		Local known:TCompilerIrImportedClass = TCompilerIrImportedClass(importedClassesBySymbol.ValueForKey(symbol))
		If known Then Return known
		If symbol.genericArity <> 0 Then
			AddUnsupported("BMXC1168", "Generic imported Type '" + symbol.QualifiedName() + "' requires canonical specialization lowering", symbol.declaration)
			Return Null
		End If
		If Not symbol.externalName.length Then
			AddUnsupported("BMXC1169", "Imported Type '" + symbol.QualifiedName() + "' has no class ABI name", symbol.declaration)
			Return Null
		End If
		If TCompilerAbiNamer.Sanitize(symbol.externalName) <> symbol.externalName Then
			AddUnsupported("BMXC1170", "Imported Type ABI name '" + symbol.externalName + "' requires an explicit linker-name representation", symbol.declaration)
			Return Null
		End If
		Local existing:TCompilerIrImportedClass = TCompilerIrImportedClass(importedClassesByAbiName.ValueForKey(symbol.externalName.ToLower()))
		If existing Then
			importedClassesBySymbol.Insert(symbol, existing)
			Return existing
		End If
		' Publish the nominal shell before traversing its base and member types.
		' Imported layouts can refer back to the class being completed through a
		' base member or routine signature; delaying interning until afterwards
		' creates two class ids for one ABI identity.
		Local importedClass:TCompilerIrImportedClass = New TCompilerIrImportedClass
		importedClass.importedClassId = "icls" + nextImportedClassId
		nextImportedClassId :+ 1
		importedClass.name = symbol.name
		importedClass.semanticType = TypeName(symbol.declaredType)
		importedClass.abiName = symbol.externalName
		importedClass.originModule = symbol.originModule
		importedClass.isAbstract = analysis.model.IsAbstractType(symbol)
		importedClass.source = SourceForSymbol(symbol)
		importedClass.metadata = MetadataOf(symbol)
		importedClassesBySymbol.Insert(symbol, importedClass)
		importedClassesByAbiName.Insert(symbol.externalName.ToLower(), importedClass)
		result.importedClasses :+ [importedClass]
		Local importedBaseClass:TCompilerIrImportedClass
		Local importedBaseType:TSemanticType = ExplicitBaseType(symbol)
		If importedBaseType Then
			Local namedBase:TNamedSemanticType = TNamedSemanticType(importedBaseType)
			If namedBase And namedBase.symbol And namedBase.symbol.kind = SYMBOL_TYPE And namedBase.symbol.isImported Then
				importedBaseClass = ImportedClassForType(importedBaseType)
			End If
		End If
		If importedBaseClass Then importedClass.baseImportedClassId = importedBaseClass.importedClassId
		If importedBaseClass Then importedClass.hasManagedFields = importedBaseClass.hasManagedFields
		If importedBaseClass Then
			For Local inheritedField:TCompilerIrImportedField = EachIn importedBaseClass.fields
				importedClass.fields :+ [inheritedField]
			Next
			For Local inheritedSlot:TCompilerIrClassFunctionSlot = EachIn importedBaseClass.functionSlots
				importedClass.functionSlots :+ [CloneClassSlot(inheritedSlot)]
			Next
			importedClass.destructorFunctionId = importedBaseClass.destructorFunctionId
			importedClass.toStringFunctionId = importedBaseClass.toStringFunctionId
			importedClass.compareFunctionId = importedBaseClass.compareFunctionId
			importedClass.sendMessageFunctionId = importedBaseClass.sendMessageFunctionId
			importedClass.hashCodeFunctionId = importedBaseClass.hashCodeFunctionId
			importedClass.equalsFunctionId = importedBaseClass.equalsFunctionId
		End If
		If symbol.memberScope Then
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If member And member.kind = SYMBOL_FIELD Then
					' The field can be omitted from consumer-owned IR when its generic
					' specialization is not otherwise needed, but it still determines
					' whether the dependency-owned object must use traced allocation.
					If IsManagedValueType(member.declaredType) Then importedClass.hasManagedFields = True
					' An ordinary imported Type's header already owns its complete C
					' layout.  Do not make every consumer recreate specializations
					' mentioned only by unused fields; a real member access causes the
					' planner to add the canonical specialization before ImportedField
					' is reached.
					Local namedFieldType:TNamedSemanticType = TNamedSemanticType(member.declaredType)
					If namedFieldType And namedFieldType.symbol And namedFieldType.symbol.genericArity And namedFieldType.typeArguments.length Then
						Local plannedGenericFieldClass:TCompilerIrImportedClass = TCompilerIrImportedClass(genericClassesByTypeName.ValueForKey(TypeName(member.declaredType).ToLower()))
						Local plannedGenericFieldStruct:TCompilerIrImportedStruct = TCompilerIrImportedStruct(genericStructsByTypeName.ValueForKey(TypeName(member.declaredType).ToLower()))
						Local plannedGenericFieldInterface:TCompilerIrInterface = TCompilerIrInterface(genericInterfacesByTypeName.ValueForKey(TypeName(member.declaredType).ToLower()))
						If Not plannedGenericFieldClass And Not plannedGenericFieldStruct And Not plannedGenericFieldInterface Then Continue
					End If
					ImportedField(member, member.declaration)
				Else If member And member.kind = SYMBOL_ROUTINE Then
					' Private Type functions are not part of the consumer-facing
					' class or vtable ABI. Import them lazily only if a legal use
					' site ever reaches one.
					If member.visibility = VISIBILITY_PRIVATE And member.interfaceRecord And member.interfaceRecord.kind = INTERFACE_RECORD_TYPE_FUNCTION Then Continue
					EnsureImportedClassRoutineSlot(symbol, importedClass, member)
				End If
			Next
		End If
		Return importedClass
	End Method

	Method EnsureImportedClassRoutineSlot(ownerSymbol:TSymbol, importedClass:TCompilerIrImportedClass, symbol:TSymbol)
		If Not ownerSymbol Or Not importedClass Or Not symbol Or Not symbol.interfaceRecord Then Return
		' Canonical generic methods are direct specialization functions and do
		' not occupy the ordinary virtual table.
		If symbol.genericArity Then Return
		Local recordKind:Int = symbol.interfaceRecord.kind
		If recordKind <> INTERFACE_RECORD_METHOD And recordKind <> INTERFACE_RECORD_TYPE_FUNCTION Then Return
		Local lowerName:String = symbol.name.ToLower()
		If lowerName = "new" Then Return
		Local objectSlotKind:Int = ObjectSlotKind(symbol)
		If lowerName = "delete" Or objectSlotKind <> IR_OBJECT_SLOT_NONE Then
			Local fixedMethod:TCompilerIrImportedMethod = ImportedMethod(symbol, symbol.declaration)
			If Not fixedMethod Then Return
			If lowerName = "delete" Then
				importedClass.destructorFunctionId = fixedMethod.methodId
			Else
				SetImportedObjectSlotFunction(importedClass, objectSlotKind, fixedMethod.methodId)
			End If
			Return
		End If
		Local functionId:String
		Local abiName:String
		Local isMethod:Int = recordKind = INTERFACE_RECORD_METHOD
		Local parameters:TCompilerIrParameter[]
		Local importedMethodRecord:TCompilerIrImportedMethod
		If isMethod Then
			importedMethodRecord = ImportedMethod(symbol, symbol.declaration)
			If Not importedMethodRecord Then Return
			functionId = importedMethodRecord.methodId
			abiName = importedMethodRecord.abiName
			parameters = importedMethodRecord.parameters
		Else
			Local externalFunction:TCompilerIrExternalFunction = ExternalFunction(symbol, symbol.declaration)
			If Not externalFunction Then Return
			functionId = externalFunction.functionId
			abiName = externalFunction.abiName
			parameters = externalFunction.parameters
		End If
		Local slot:TCompilerIrClassFunctionSlot
		Local dispatchKey:String = ImportedRoutineSlotName(symbol, ownerSymbol, isMethod)
		If isMethod And importedClass.baseImportedClassId.length Then
			Local inheritance:TTypeInheritanceInfo = analysis.model.InheritanceInfo(ownerSymbol)
			Local baseSymbol:TSymbol
			Local baseType:TSemanticType
			If inheritance Then
				For Local edge:TInheritanceEdge = EachIn inheritance.baseEdges
					Local namedBase:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
					If namedBase And namedBase.symbol And namedBase.symbol.kind = SYMBOL_TYPE Then baseSymbol = namedBase.symbol; baseType = edge.semanticType; Exit
				Next
			End If
			If baseSymbol Then
				Local validator:TInheritanceValidator = New TInheritanceValidator
				validator.model = analysis.model
				Local overridden:TSymbol = validator.OverriddenRoutine(symbol, baseType, 0)
				If overridden Then slot = TCompilerIrClassFunctionSlot(slotsByRoutineSymbol.ValueForKey(overridden))
				If overridden And Not slot Then
					Local importedBase:TCompilerIrImportedClass = ImportedClassById(importedClass.baseImportedClassId)
					Local importedOverride:TCompilerIrImportedMethod = GenericImportedMethod(importedBase, overridden)
					If importedOverride Then
						For Local importedSlot:TCompilerIrClassFunctionSlot = EachIn importedBase.functionSlots
							If importedSlot.slotName = importedOverride.slotName Then slot = importedSlot; Exit
						Next
					End If
				End If
			End If
		Else If Not isMethod Then
			For Local inheritedIndex:Int = 0 Until importedClass.functionSlots.length
				Local inheritedSlot:TCompilerIrClassFunctionSlot = importedClass.functionSlots[inheritedIndex]
				If Not inheritedSlot.isMethod And inheritedSlot.dispatchKey = dispatchKey Then
					slot = CloneClassSlot(inheritedSlot)
					importedClass.functionSlots[inheritedIndex] = slot
					Exit
				End If
			Next
		End If
		If slot Then
			If isMethod Then
				slot = CloneClassSlot(slot)
				For Local index:Int = 0 Until importedClass.functionSlots.length
					If importedClass.functionSlots[index].slotId = slot.slotId Then importedClass.functionSlots[index] = slot; Exit
				Next
			End If
		Else
			slot = New TCompilerIrClassFunctionSlot
			slot.slotId = "icfs" + importedClass.functionSlots.length
			slot.dispatchKey = dispatchKey
			slot.declaringImportedClassId = importedClass.importedClassId
			slot.slotName = dispatchKey
			importedClass.functionSlots :+ [slot]
		End If
		If Not slot.dispatchKey.length Then slot.dispatchKey = dispatchKey
		slot.functionId = functionId
		slot.name = symbol.name
		slot.abiName = abiName
		slot.returnType = TypeName(symbol.declaredType)
		Local callableReturn:TCallableSemanticType = TCallableSemanticType(symbol.declaredType)
		If callableReturn Then
			slot.callableReturnType = TypeName(callableReturn.returnType)
			slot.callableReturnParameters = CallableParameters(callableReturn)
			slot.callableReturnCallingConvention = callableReturn.callingConvention
		End If
		slot.callingConvention = symbol.callingConvention
		slot.parameters = parameters
		slot.isMethod = isMethod
		slot.isAbstract = symbol.isAbstract
		If importedMethodRecord Then importedMethodRecord.slotName = slot.slotName
		If isMethod Then
			slot.receiverClassId = ""
			slot.receiverImportedClassId = importedClass.importedClassId
		End If
		slotsByRoutineSymbol.Insert(symbol, slot)
	End Method

	Function SetImportedObjectSlotFunction(importedClass:TCompilerIrImportedClass, slotKind:Int, functionId:String)
		If Not importedClass Then Return
		Select slotKind
			Case IR_OBJECT_SLOT_TO_STRING
				importedClass.toStringFunctionId = functionId
			Case IR_OBJECT_SLOT_COMPARE
				importedClass.compareFunctionId = functionId
			Case IR_OBJECT_SLOT_SEND_MESSAGE
				importedClass.sendMessageFunctionId = functionId
			Case IR_OBJECT_SLOT_HASH_CODE
				importedClass.hashCodeFunctionId = functionId
			Case IR_OBJECT_SLOT_EQUALS
				importedClass.equalsFunctionId = functionId
		End Select
	End Function

	Function ImportedRoutineSlotName:String(symbol:TSymbol, owner:TSymbol, isMethod:Int)
		If isMethod Then Return ImportedMethodSlotName(symbol, owner)
		If Not symbol Or Not owner Or Not symbol.externalName.length Or Not owner.externalName.length Then Return ""
		Local prefix:String = owner.externalName + "_"
		Local suffix:String
		If symbol.externalName.StartsWith(prefix) Then suffix = symbol.externalName[prefix.length..]
		If Not suffix.length Then Return ""
		Local slotName:String = "f_" + suffix
		If TCompilerAbiNamer.Sanitize(slotName) <> slotName Then Return ""
		Return slotName
	End Function

	Method ImportedClassById:TCompilerIrImportedClass(importedClassId:String)
		For Local importedClass:TCompilerIrImportedClass = EachIn result.importedClasses
			If importedClass.importedClassId = importedClassId Then Return importedClass
		Next
		Return Null
	End Method

	Method InterfaceById:TCompilerIrInterface(interfaceId:String)
		For Local irInterface:TCompilerIrInterface = EachIn result.interfaces
			If irInterface.interfaceId = interfaceId Then Return irInterface
		Next
		Return Null
	End Method

	Function IsInterfaceRootType:Int(semanticType:TSemanticType)
		Local name:String = TypeName(semanticType).ToLower()
		Return name = "object" Or name = "null"
	End Function

	Method ClassForType:TCompilerIrClass(semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol Then Return TCompilerIrClass(classesBySymbol.ValueForKey(named.symbol))
		Return Null
	End Method

	Method EnumForType:TCompilerIrEnum(semanticType:TSemanticType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol Then
			Local irEnum:TCompilerIrEnum = TCompilerIrEnum(enumsBySymbol.ValueForKey(named.symbol))
			If Not irEnum And named.symbol.isImported Then irEnum = EnsureImportedEnum(named.symbol)
			Return irEnum
		End If
		Return Null
	End Method

	Method ExplicitBaseSymbol:TSymbol(symbol:TSymbol)
		Local named:TNamedSemanticType = TNamedSemanticType(ExplicitBaseType(symbol))
		If named Then Return named.symbol
		Return Null
	End Method

	Method ExplicitBaseType:TSemanticType(symbol:TSymbol)
		If Not symbol Then Return Null
		Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
		' Source Types distinguish an omitted Extends clause from an explicit
		' base. The inheritance model also contains their implicit Object edge,
		' which is runtime background rather than an ordinary imported layout.
		If Not symbol.isImported Then
			If Not declaration Or Not declaration.header Or Not declaration.header.extendsTypes.length Then Return Null
		Else If declaration And declaration.header And Not declaration.header.extendsTypes.length Then
			Return Null
		End If
		' Imported interface declarations normally retain their compact Extends
		' syntax. Prefer its resolved type directly: a consumer may not have built
		' a full inheritance-info entry for every transitive imported Type, while
		' the published declaration still carries the authoritative base.
		If declaration And declaration.header And declaration.header.extendsTypes.length Then
			Local declaredBase:TSemanticType = analysis.model.TypeOf(declaration.header.extendsTypes[0])
			If declaredBase Then Return declaredBase
		End If
		' Compact imported records do not always retain a declaration header.
		' Their validated inheritance edge remains the authoritative explicit
		' base relationship.
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(symbol)
		If Not info Or Not info.baseEdges.length Then Return Null
		Return info.baseEdges[0].semanticType
	End Method

	Method IsSupportedArrayElementType:Int(semanticType:TSemanticType)
		Local callable:TCallableSemanticType = TCallableSemanticType(semanticType)
		If callable Then Return IsSupportedCallableType(callable)
		Local closure:TClosureSemanticType = TClosureSemanticType(semanticType)
		If closure Then Return IsSupportedClosureType(closure)
		If TPointerSemanticType(semanticType) Then Return IsSupportedPointerElementType(TPointerSemanticType(semanticType).elementType)
		If TArraySemanticType(semanticType) Then Return TArraySemanticType(semanticType).rank > 0 And IsSupportedArrayElementType(TArraySemanticType(semanticType).elementType)
		If EnumForType(semanticType) Then Return True
		If StructForType(semanticType) Or ImportedStructForType(semanticType) Then Return True
		If IsObjectReferenceType(semanticType) Then Return True
		If IsStringType(semanticType) Then Return True
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam", "float", "double", "float64" Return True
		End Select
		Return False
	End Method

	Method ArrayElementEncoding:String(semanticType:TSemanticType)
		If TCallableSemanticType(semanticType) Then Return "("
		Local closure:TClosureSemanticType = TClosureSemanticType(semanticType)
		If closure And closure.signature Then
			Local result:String = "!("
			For Local index:Int = 0 Until closure.signature.parameterTypes.length
				If index Then result :+ ","
				If index < closure.signature.parameterModes.length And closure.signature.parameterModes[index] = PARAMETER_PASS_VAR Then result :+ "&"
				Local parameterEncoding:String = ArrayElementEncoding(closure.signature.parameterTypes[index])
				If Not parameterEncoding.length Then Return ""
				result :+ parameterEncoding
			Next
			result :+ ")"
			If closure.signature.returnType And Not IsVoidType(closure.signature.returnType) Then
				Local returnEncoding:String = ArrayElementEncoding(closure.signature.returnType)
				If Not returnEncoding.length Then Return ""
				result :+ returnEncoding
			End If
			Return result
		End If
		Local pointerType:TPointerSemanticType = TPointerSemanticType(semanticType)
		If pointerType Then Return "*" + ArrayElementEncoding(pointerType.elementType)
		Local arrayType:TArraySemanticType = TArraySemanticType(semanticType)
		If arrayType Then
			Local brackets:String = "["
			For Local index:Int = 1 Until arrayType.rank
				brackets :+ ","
			Next
			Return brackets + "]" + ArrayElementEncoding(arrayType.elementType)
		End If
		Local irEnum:TCompilerIrEnum = EnumForType(semanticType)
		If irEnum Then Return "/" + irEnum.name
		Local irStruct:TCompilerIrStruct = StructForType(semanticType)
		If irStruct Then Return "@" + irStruct.name
		Local importedStruct:TCompilerIrImportedStruct = ImportedStructForType(semanticType)
		If importedStruct Then Return "@" + importedStruct.name
		If IsObjectReferenceType(semanticType) Then
			Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
			If named And named.symbol Then Return ":" + named.symbol.name
			Return ":Object"
		End If
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return ""
		Select builtin.name.ToLower()
			Case "byte" Return "b"
			Case "short" Return "s"
			Case "int" Return "i"
			Case "uint" Return "u"
			Case "long" Return "l"
			Case "ulong" Return "y"
			Case "longint" Return "v"
			Case "ulongint" Return "e"
			Case "size_t" Return "t"
			Case "wparam" Return "w"
			Case "lparam" Return "x"
			Case "float" Return "f"
			Case "double" Return "d"
			Case "float64" Return "h"
			Case "string" Return "$"
		End Select
		Return ""
	End Method

	Method IsSupportedPointerElementType:Int(semanticType:TSemanticType)
		If TPointerSemanticType(semanticType) Then Return IsSupportedPointerElementType(TPointerSemanticType(semanticType).elementType)
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named And named.symbol And named.symbol.kind = SYMBOL_INTERFACE Then
			Local nativeInterface:TCompilerIrInterface = EnsureInterfaceShell(named.symbol)
			Return nativeInterface And nativeInterface.isExternInterface
		End If
		If named And named.symbol And named.symbol.kind = SYMBOL_STRUCT Then
			If Not named.symbol.isImported Then Return StructForType(semanticType) <> Null
			' A pointer needs the imported Struct identity, not its completed value
			' layout. During a self- or mutually-pointer-recursive layout the record
			' is already registered, so do not re-enter EnsureImportedStruct and
			' mistake the indirection for a forbidden by-value cycle.
			If importedStructsBySymbol.Contains(named.symbol) Then Return True
			Return EnsureImportedStruct(named.symbol) <> Null
		End If
		If EnumForType(semanticType) Then Return True
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		If builtin.name.ToLower() = "void" Then Return True
		Return IsSupportedValueType(semanticType)
	End Method

	Function IsPointerType:Int(semanticType:TSemanticType)
		Return TPointerSemanticType(semanticType) <> Null
	End Function

	Function IsStringType:Int(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		Return builtin And builtin.name.ToLower() = "string"
	End Function

	Function IsArrayType:Int(semanticType:TSemanticType)
		Return TArraySemanticType(semanticType) <> Null
	End Function

	Function StorageName:String(symbol:TSymbol)
		If Not symbol Then Return "unknown"
		Select symbol.kind
			Case SYMBOL_GLOBAL Return "global"
			Case SYMBOL_CONST Return "constant"
			Case SYMBOL_PARAMETER Return "parameter"
		End Select
		Return "local"
	End Function
End Type
