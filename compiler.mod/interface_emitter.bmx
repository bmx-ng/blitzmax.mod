' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.StringBuilder
Import BlitzMax.Language
Import "compiler_diagnostic.bmx"
Import "ir_model.bmx"
Import "generic_application_plan.bmx"

' Emits the compact compiler interface consumed by bmk snapshots. This first
' slice is intentionally closed: it publishes non-generic Interfaces, object
' Types, Structs and scalar/callable module declarations and diagnoses every
' other public declaration rather than omitting it.
Type TCompilerInterfaceEmitter
	Field analysis:TLanguageAnalysis
	Field irModule:TCompilerIrModule
	Field genericPlan:TCompilerGenericApplicationPlan
	Field diagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]

	Function Emit:String(analysis:TLanguageAnalysis, irModule:TCompilerIrModule, diagnostics:TCompilerDiagnostic[] Var, genericPlan:TCompilerGenericApplicationPlan = Null)
		Local emitter:TCompilerInterfaceEmitter = New TCompilerInterfaceEmitter
		emitter.analysis = analysis
		emitter.irModule = irModule
		emitter.genericPlan = genericPlan
		Local result:String = emitter.EmitModule()
		diagnostics = emitter.diagnostics
		If diagnostics.length Then Return ""
		Return result
	End Function

	Method EmitModule:String()
		If Not irModule Or Not irModule.initializationPlan Or irModule.initializationPlan.unitKind <> IR_UNIT_MODULE Then
			AddDiagnostic("BMXC2060", "Compact interface emission requires a module compilation", Null)
			Return ""
		End If

		Local body:TStringBuilder = New TStringBuilder(4096)
		Local emittedInterfaces:TMap = New TMap
		Local visitingInterfaces:TMap = New TMap
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If irInterface.isImported Or irInterface.visibility <> VISIBILITY_PUBLIC Then Continue
			Local interfaceText:String = EmitInterfaceTree(irInterface, emittedInterfaces, visitingInterfaces)
			If interfaceText.length Then body.Append(interfaceText)
		Next
		Local emittedStructs:TMap = New TMap
		Local visitingStructs:TMap = New TMap
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			' A private Struct embedded by value in a published Type still forms
			' part of that Type's physical ABI.  Publish the compiler-visible
			' layout with its original visibility so consumers can reconstruct
			' inherited object layouts without making the Struct source-accessible.
			If Not irStruct.isPublished And Not StructRequiredByPublishedLayout(irStruct) Then Continue
			Local structText:String = EmitStructTree(irStruct, emittedStructs, visitingStructs)
			If structText.length Then body.Append(structText)
		Next
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			' Imported Enums remain owned by their defining module. A public
			' signature may reference them because this interface also retains
			' the defining import; republishing the Enum creates a false duplicate
			' declaration when a consumer imports both modules.
			If irEnum.isPublished Or (Not irEnum.isImported And EnumRequiredByPublishedContract(irEnum)) Then body.Append(EmitEnum(irEnum))
		Next
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If Not irClass.isPublished Then Continue
			Local classText:String = EmitType(irClass)
			If classText.length Then body.Append(classText)
		Next
		body.Append(EmitGenericTemplates())
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.isGlobalEntry Or routine.ownerClassId.length Or routine.ownerStructId.length Or routine.ownerInterfaceId.length Or routine.visibility <> VISIBILITY_PUBLIC Then Continue
			Local routineText:String = EmitRoutine(routine)
			If routineText.length Then body.Append(routineText).Append("~n")
		Next
		For Local externalRoutine:TCompilerIrExternalFunction = EachIn irModule.externalFunctions
			If Not externalRoutine.isPublished Then Continue
			Local externalRoutineText:String = EmitExternalRoutine(externalRoutine)
			If externalRoutineText.length Then body.Append(externalRoutineText).Append("~n")
		Next
		For Local externalGlobal:TCompilerIrExternalGlobal = EachIn irModule.externalGlobals
			If Not externalGlobal.isPublished Then Continue
			Local externalGlobalText:String = EmitExternalGlobal(externalGlobal)
			If externalGlobalText.length Then body.Append(externalGlobalText).Append("~n")
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If Not routine.isGlobalEntry Or Not routine.body Then Continue
			For Local statement:TCompilerIrStatement = EachIn routine.body.statements
				Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
				If Not variable Or variable.visibility <> VISIBILITY_PUBLIC Then Continue
				If variable.ownerClassId.length Or variable.ownerStructId.length Then Continue
				If variable.storage = "constant" Then
					Local constantText:String = EmitConstant(variable)
					If constantText.length Then body.Append(constantText).Append("~n")
					Continue
				End If
				If Not variable.isPublished Then Continue
				If variable.isStaticArray Then
					AddDiagnostic("BMXC2065", "Public Global type '" + variable.semanticType + "' is outside the compact interface slice", variable.source)
					Continue
				End If
				If variable.arrayCallableReturnType.length Then
					If Not CallableArrayShapeSupported(variable.arrayCallableReturnType, variable.arrayCallableParameters, variable.arrayCallableRank) Then
						AddDiagnostic("BMXC2065", "Callable-array Global '" + variable.name + "' is outside the compact interface slice", variable.source)
						Continue
					End If
				Else If variable.callableReturnType.length Then
					If Not SupportsGlobalType(variable.callableReturnType) Then
						AddDiagnostic("BMXC2065", "Callable Global return type '" + variable.callableReturnType + "' is outside the compact interface slice", variable.source)
						Continue
					End If
					Local supportedParameters:Int = True
					For Local parameter:TCompilerIrParameter = EachIn variable.callableParameters
						If Not GlobalParameterSupported(parameter) Or Not ParameterModeSupported(parameter) Then supportedParameters = False
					Next
					If Not supportedParameters Then
						AddDiagnostic("BMXC2065", "Callable Global '" + variable.name + "' has parameters outside the compact interface slice", variable.source)
						Continue
					End If
				Else If Not SupportsGlobalType(variable.semanticType) Then
					AddDiagnostic("BMXC2065", "Public Global type '" + variable.semanticType + "' is outside the compact interface slice", variable.source)
					Continue
				End If
				body.Append(EmitGlobal(variable)).Append("~n")
			Next
		Next

		If diagnostics.length Then Return ""
		Local imports:TStringBuilder = New TStringBuilder(512)
		For Local dependency:TCompilerIrDependency = EachIn irModule.initializationPlan.dependencies
			If Not dependency.logicalName.length Then Continue
			If dependency.logicalName.ToLower().EndsWith(".bmx") Then
				imports.Append("import ").Append(Quoted(dependency.logicalName)).Append("~n")
			Else
				imports.Append("import ").Append(dependency.logicalName).Append("~n")
			End If
		Next
		Local result:TStringBuilder = New TStringBuilder(body.Length() + imports.Length() + 64)
		If IsPrimaryModuleSource() Then
			Local aggregate:String = EmitSourceAggregate()
			If diagnostics.length Then Return ""
			result.Append("superstrict~n'@source-aggregate 1~n").Append(imports).Append(aggregate).Append(body)
			Return result.ToString()
		End If
		result.Append("superstrict~n").Append(imports).Append(body)
		Return result.ToString()
	End Method

	' Production module interfaces are the public contract of the whole module,
	' even though each quoted .bmx source remains an independently compiled unit.
	' Publish the already validated compact records from those source interfaces
	' in dependency order, while retaining their import lines above.
	Method EmitSourceAggregate:String()
		If Not analysis Or Not analysis.snapshot Then Return ""
		Local result:TStringBuilder = New TStringBuilder(4096)
		Local visited:TMap = New TMap
		For Local document:TSourceDocumentModel = EachIn analysis.snapshot.documents
			If Not document Then Continue
			For Local edge:TImportEdge = EachIn document.imports
				If Not edge Or Not edge.target Or Not IsQuotedSourceDependency(edge.target) Then Continue
				result.Append(EmitSourceDependency(edge.target, visited))
			Next
		Next
		Return result.ToString()
	End Method

	Method EmitSourceDependency:String(dependency:TInterfaceDependency, visited:TMap)
		If Not dependency Or Not dependency.interfaceFile Then Return ""
		Local key:String = dependency.path.Replace(Chr(92), "/").ToLower()
		If visited.Contains(key) Then Return ""
		visited.Insert(key, dependency)
		Local result:TStringBuilder = New TStringBuilder(1024)
		For Local imported:TInterfaceDependency = EachIn dependency.imports
			If IsQuotedSourceDependency(imported) Then result.Append(EmitSourceDependency(imported, visited))
		Next
		result.Append(SourceDeclarationText(dependency))
		Return result.ToString()
	End Method

	Function IsQuotedSourceDependency:Int(dependency:TInterfaceDependency)
		Return dependency And dependency.logicalName.ToLower().EndsWith(".bmx")
	End Function

	Method IsPrimaryModuleSource:Int()
		If Not analysis Or Not analysis.model Or Not analysis.model.moduleName.length Or Not irModule Or Not irModule.path.length Then Return False
		Local moduleLeaf:String = analysis.model.moduleName
		Local dot:Int = moduleLeaf.FindLast(".")
		If dot >= 0 Then moduleLeaf = moduleLeaf[dot + 1..]
		Return StripExt(StripDir(irModule.path)).ToLower() = moduleLeaf.ToLower()
	End Method

	Method SourceDeclarationText:String(dependency:TInterfaceDependency)
		Local file:TInterfaceFile = dependency.interfaceFile
		If Not file Or Not file.declarations.length Then Return ""
		Local lines:String[] = file.sourceText.Split("~n")
		Local result:TStringBuilder = New TStringBuilder(file.sourceText.length)
		For Local declarationIndex:Int = 0 Until file.declarations.length
			Local first:Int = file.declarations[declarationIndex].line - 1
			Local finish:Int = lines.length
			If declarationIndex + 1 < file.declarations.length Then finish = file.declarations[declarationIndex + 1].line - 1
			If first < 0 Or first >= lines.length Or finish < first Then
				AddDiagnostic("BMXC2072", "Quoted-source interface '" + dependency.path + "' has invalid declaration boundaries", Null)
				Return ""
			End If
			For Local lineIndex:Int = first Until finish
				result.Append(RebaseGenericTemplateLine(lines[lineIndex], dependency.path)).Append("~n")
			Next
		Next
		Return result.ToString()
	End Method

	Method RebaseGenericTemplateLine:String(line:String, sourceInterfacePath:String)
		Local trimmed:String = line.Trim()
		If Not TInterfaceFileParser.StartsWithAsciiIgnoreCase(trimmed, "'@generic-template ") Then Return line
		Local quotePositions:Int[] = New Int[0]
		For Local index:Int = 0 Until line.length
			If line[index] = Asc("~q") Then quotePositions :+ [index]
		Next
		If quotePositions.length < 6 Then Return line
		Local referenceStart:Int = quotePositions[4] + 1
		Local referenceFinish:Int = quotePositions[5]
		Local reference:String = line[referenceStart..referenceFinish]
		Local targetPath:String = ExtractDir(sourceInterfacePath.Replace(Chr(92), "/")) + "/" + reference
		Local rebased:String = RelativeInterfacePath(irModule.path, targetPath)
		Return line[..referenceStart] + rebased + line[referenceFinish..]
	End Method

	Function RelativeInterfacePath:String(sourcePath:String, targetPath:String)
		Local sourceParts:String[] = sourcePath.Replace(Chr(92), "/").Split("/")
		Local targetParts:String[] = targetPath.Replace(Chr(92), "/").Split("/")
		Local sourceDirectoryCount:Int = sourceParts.length - 1
		Local common:Int
		While common < sourceDirectoryCount And common < targetParts.length - 1
			If sourceParts[common].ToLower() <> targetParts[common].ToLower() Then Exit
			common :+ 1
		Wend
		Local result:String
		For Local index:Int = common Until sourceDirectoryCount
			result :+ "../"
		Next
		For Local index:Int = common Until targetParts.length
			If result.length And Not result.EndsWith("/") Then result :+ "/"
			result :+ targetParts[index]
		Next
		If Not result.length Then result = StripDir(targetPath)
		Return result
	End Function

	Method StructRequiredByPublishedLayout:Int(irStruct:TCompilerIrStruct)
		If Not irStruct Then Return False
		For Local rootStruct:TCompilerIrStruct = EachIn irModule.structs
			If Not rootStruct.isPublished Then Continue
			If StructReachesStruct(rootStruct, irStruct, New TMap) Then Return True
		Next
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If Not irClass.isPublished Then Continue
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				If ClassFieldReachesStruct(irField, irStruct, New TMap) Then Return True
			Next
		Next
		Return False
	End Method

	Method StructReachesStruct:Int(source:TCompilerIrStruct, target:TCompilerIrStruct, visiting:TMap)
		If Not source Or Not target Then Return False
		If source = target Then Return True
		If visiting.Contains(source.structId) Then Return False
		visiting.Insert(source.structId, source)
		For Local irField:TCompilerIrStructField = EachIn source.fields
			If StructFieldReachesStruct(irField, target, visiting) Then Return True
		Next
		Return False
	End Method

	Method ClassFieldReachesStruct:Int(irField:TCompilerIrClassField, target:TCompilerIrStruct, visiting:TMap)
		If Not irField Or Not target Then Return False
		If TypeReachesStruct(irField.semanticType, target, visiting) Then Return True
		If irField.isStaticArray And TypeReachesStruct(irField.staticArrayElementType, target, visiting) Then Return True
		If TypeReachesStruct(irField.callableReturnType, target, visiting) Then Return True
		If TypeReachesStruct(irField.arrayCallableReturnType, target, visiting) Then Return True
		For Local parameter:TCompilerIrParameter = EachIn irField.callableParameters
			If ParameterReachesStruct(parameter, target, visiting) Then Return True
		Next
		For Local parameter:TCompilerIrParameter = EachIn irField.arrayCallableParameters
			If ParameterReachesStruct(parameter, target, visiting) Then Return True
		Next
		Return False
	End Method

	Method StructFieldReachesStruct:Int(irField:TCompilerIrStructField, target:TCompilerIrStruct, visiting:TMap)
		If Not irField Or Not target Then Return False
		If irField.structId.length And StructReachesStruct(StructById(irField.structId), target, visiting) Then Return True
		If irField.staticArrayStructId.length And StructReachesStruct(StructById(irField.staticArrayStructId), target, visiting) Then Return True
		If TypeReachesStruct(irField.semanticType, target, visiting) Then Return True
		If irField.isStaticArray And TypeReachesStruct(irField.staticArrayElementType, target, visiting) Then Return True
		If TypeReachesStruct(irField.callableReturnType, target, visiting) Then Return True
		If TypeReachesStruct(irField.arrayCallableReturnType, target, visiting) Then Return True
		For Local parameter:TCompilerIrParameter = EachIn irField.callableParameters
			If ParameterReachesStruct(parameter, target, visiting) Then Return True
		Next
		For Local parameter:TCompilerIrParameter = EachIn irField.arrayCallableParameters
			If ParameterReachesStruct(parameter, target, visiting) Then Return True
		Next
		Return False
	End Method

	Method ParameterReachesStruct:Int(parameter:TCompilerIrParameter, target:TCompilerIrStruct, visiting:TMap)
		If Not parameter Or Not target Then Return False
		If TypeReachesStruct(parameter.semanticType, target, visiting) Then Return True
		If parameter.isStaticArray And TypeReachesStruct(parameter.staticArrayElementType, target, visiting) Then Return True
		If TypeReachesStruct(parameter.callableReturnType, target, visiting) Then Return True
		For Local nested:TCompilerIrParameter = EachIn parameter.callableParameters
			If ParameterReachesStruct(nested, target, visiting) Then Return True
		Next
		Return False
	End Method

	Method TypeReachesStruct:Int(semanticType:String, target:TCompilerIrStruct, visiting:TMap)
		If Not semanticType.length Or Not target Then Return False
		Local value:String = semanticType
		Local arrayBracket:Int = ManagedArrayOpenBracket(value)
		While arrayBracket >= 0
			value = value[..arrayBracket]
			arrayBracket = ManagedArrayOpenBracket(value)
		Wend
		While value.EndsWith(" Ptr")
			value = value[..value.length - 4]
		Wend
		For Local candidate:TCompilerIrStruct = EachIn irModule.structs
			If Not SameTypeName(candidate.semanticType, value) And Not SameTypeName(candidate.name, value) Then Continue
			Return StructReachesStruct(candidate, target, visiting)
		Next
		Return False
	End Method

	Method EnumRequiredByPublishedContract:Int(irEnum:TCompilerIrEnum)
		If Not irEnum Then Return False
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If irInterface.isImported Or irInterface.visibility <> VISIBILITY_PUBLIC Then Continue
			For Local routine:TCompilerIrInterfaceMethod = EachIn irInterface.methods
				If TypeUsesEnum(routine.returnType, irEnum) Or TypeUsesEnum(routine.callableReturnType, irEnum) Then Return True
				For Local parameter:TCompilerIrParameter = EachIn routine.parameters
					If ParameterUsesEnum(parameter, irEnum) Then Return True
				Next
				For Local parameter:TCompilerIrParameter = EachIn routine.callableReturnParameters
					If ParameterUsesEnum(parameter, irEnum) Then Return True
				Next
			Next
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If Not irStruct.isPublished And Not StructRequiredByPublishedLayout(irStruct) Then Continue
			For Local irField:TCompilerIrStructField = EachIn irStruct.fields
				If StructFieldUsesEnum(irField, irEnum) Then Return True
			Next
		Next
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If Not irClass.isPublished Then Continue
			For Local irField:TCompilerIrClassField = EachIn irClass.fields
				If ClassFieldUsesEnum(irField, irEnum) Then Return True
			Next
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			Local contractRoutine:Int = routine.visibility = VISIBILITY_PUBLIC
			If routine.ownerClassId.length Then
				Local ownerClass:TCompilerIrClass = ClassById(routine.ownerClassId)
				contractRoutine = ownerClass And ownerClass.isPublished
			Else If routine.ownerStructId.length Then
				Local ownerStruct:TCompilerIrStruct = StructById(routine.ownerStructId)
				contractRoutine = ownerStruct And ownerStruct.isPublished
			End If
			If Not contractRoutine Then Continue
			If TypeUsesEnum(routine.returnType, irEnum) Or TypeUsesEnum(routine.callableReturnType, irEnum) Then Return True
			For Local parameter:TCompilerIrParameter = EachIn routine.parameters
				If ParameterUsesEnum(parameter, irEnum) Then Return True
			Next
			For Local parameter:TCompilerIrParameter = EachIn routine.callableReturnParameters
				If ParameterUsesEnum(parameter, irEnum) Then Return True
			Next
		Next
		Return False
	End Method

	Method StructFieldUsesEnum:Int(irField:TCompilerIrStructField, irEnum:TCompilerIrEnum)
		If Not irField Or Not irEnum Then Return False
		If TypeUsesEnum(irField.semanticType, irEnum) Or TypeUsesEnum(irField.staticArrayElementType, irEnum) Or TypeUsesEnum(irField.callableReturnType, irEnum) Or TypeUsesEnum(irField.arrayCallableReturnType, irEnum) Then Return True
		For Local parameter:TCompilerIrParameter = EachIn irField.callableParameters
			If ParameterUsesEnum(parameter, irEnum) Then Return True
		Next
		For Local parameter:TCompilerIrParameter = EachIn irField.arrayCallableParameters
			If ParameterUsesEnum(parameter, irEnum) Then Return True
		Next
		Return False
	End Method

	Method ClassFieldUsesEnum:Int(irField:TCompilerIrClassField, irEnum:TCompilerIrEnum)
		If Not irField Or Not irEnum Then Return False
		If TypeUsesEnum(irField.semanticType, irEnum) Or TypeUsesEnum(irField.staticArrayElementType, irEnum) Or TypeUsesEnum(irField.callableReturnType, irEnum) Or TypeUsesEnum(irField.arrayCallableReturnType, irEnum) Then Return True
		For Local parameter:TCompilerIrParameter = EachIn irField.callableParameters
			If ParameterUsesEnum(parameter, irEnum) Then Return True
		Next
		For Local parameter:TCompilerIrParameter = EachIn irField.arrayCallableParameters
			If ParameterUsesEnum(parameter, irEnum) Then Return True
		Next
		Return False
	End Method

	Method ParameterUsesEnum:Int(parameter:TCompilerIrParameter, irEnum:TCompilerIrEnum)
		If Not parameter Then Return False
		If TypeUsesEnum(parameter.semanticType, irEnum) Or TypeUsesEnum(parameter.staticArrayElementType, irEnum) Or TypeUsesEnum(parameter.callableReturnType, irEnum) Then Return True
		For Local nested:TCompilerIrParameter = EachIn parameter.callableParameters
			If ParameterUsesEnum(nested, irEnum) Then Return True
		Next
		Return False
	End Method

	Function TypeUsesEnum:Int(semanticType:String, irEnum:TCompilerIrEnum)
		If Not semanticType.length Or Not irEnum Then Return False
		Local value:String = semanticType
		Local arrayBracket:Int = ManagedArrayOpenBracket(value)
		While arrayBracket >= 0
			value = value[..arrayBracket]
			arrayBracket = ManagedArrayOpenBracket(value)
		Wend
		While value.EndsWith(" Ptr")
			value = value[..value.length - 4]
		Wend
		Return SameTypeName(value, irEnum.semanticType) Or SameTypeName(value, irEnum.name)
	End Function

	' Returns the opening bracket of the final managed-array rank suffix.  The
	' semantic display form uses [] for rank one and [,], [,,], ... for wider
	' ranks; sized StaticArray suffixes deliberately do not match.
	Function ManagedArrayOpenBracket:Int(semanticType:String)
		If Not semanticType.EndsWith("]") Then Return -1
		Local openBracket:Int = semanticType.FindLast("[")
		If openBracket < 0 Then Return -1
		For Local index:Int = openBracket + 1 Until semanticType.length - 1
			If semanticType[index] <> 44 Then Return -1
		Next
		Return openBracket
	End Function

	Function IsManagedArrayType:Int(semanticType:String)
		Return ManagedArrayOpenBracket(semanticType) >= 0
	End Function

	Method EmitGenericTemplates:String()
		If Not genericPlan Then Return ""
		Local result:String
		For Local output:TCompilerGenericTemplateOutput = EachIn genericPlan.templateOutputs
			If Not output Or Not output.isPublished Or Not output.artifact Or Not output.artifact.identity Then Continue
			Local artifact:TGenericTemplateArtifact = output.artifact
			Local declarationName:String = artifact.identity.qualifiedName
			Local dot:Int = declarationName.FindLast(".")
			If dot >= 0 Then declarationName = declarationName[dot + 1..]
			If artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then
				' Generic Methods and Type Functions belong inside their containing
				' compact Type record. Publishing a Type Function as a global routine
				' preserves its template but makes TFunctions.Identity<T> unresolvable.
				If artifact.isMethod Or GenericRoutineOwnerName(artifact).length Then Continue
				If artifact.members.length <> 1 Then
					AddDiagnostic("BMXC2070", "Generic routine template '" + declarationName + "' has an invalid canonical signature", Null)
					Continue
				End If
				Local routine:TGenericTemplateMember = artifact.members[0]
				result :+ declarationName + "<"
				For Local index:Int = 0 Until artifact.parameters.length
					If index Then result :+ ","
					result :+ artifact.parameters[index].name
				Next
				result :+ ">" + GenericInterfaceType(routine.semanticType, artifact) + "("
				For Local parameterIndex:Int = 0 Until routine.parameters.length
					If parameterIndex Then result :+ ","
					Local parameter:TGenericTemplateValueParameter = routine.parameters[parameterIndex]
					result :+ parameter.name + GenericInterfaceType(parameter.semanticType, artifact)
					If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
					If parameter.optional Then result :+ "=" + GenericDefaultSignature(parameter, artifact)
				Next
				result :+ ")" + GenericConstraints(artifact) + "~n"
				result :+ "'@generic-template " + artifact.formatVersion + "," + Quoted(artifact.identity.StableName()) + "," + Quoted(artifact.EffectiveContentRevision()) + "," + Quoted(output.artifactReference) + "," + Quoted(artifact.languageLinkageRevision) + "~n"
				Continue
			End If
			result :+ declarationName + "<"
			For Local index:Int = 0 Until artifact.parameters.length
				If index Then result :+ ","
				result :+ artifact.parameters[index].name
			Next
			Local inheritanceName:String = "Object"
			If artifact.baseType Then
				inheritanceName = GenericInheritanceName(artifact.baseType.semanticType, artifact)
				If Not inheritanceName.length Then
					AddDiagnostic("BMXC2070", "Generic template '" + declarationName + "' has a base outside canonical interface publication", Null)
					Continue
				End If
			End If
			If artifact.interfaces.length Then
				inheritanceName :+ "@"
				For Local interfaceIndex:Int = 0 Until artifact.interfaces.length
					If interfaceIndex Then inheritanceName :+ ","
					Local interfaceName:String = GenericInheritanceName(artifact.interfaces[interfaceIndex].semanticType, artifact)
					If Not interfaceName.length Then
						AddDiagnostic("BMXC2070", "Generic template '" + declarationName + "' has an Interface outside canonical interface publication", Null)
						Continue
					End If
					inheritanceName :+ interfaceName
				Next
			End If
			result :+ ">" + GenericConstraints(artifact) + "^" + inheritanceName + "{~n"
			For Local member:TGenericTemplateMember = EachIn artifact.members
				' Protected declarations are part of the externally consumable
				' inheritance contract even though ordinary consumers cannot call
				' them. Production bcc recovered these declarations by reparsing
				' the generic source blob. Publish their compact semantic
				' signatures instead; private/internal implementation details stay
				' solely in the companion artifact.
				If Not GenericMemberPublished(member.visibility) Then Continue
				Local memberType:String = GenericInterfaceType(member.semanticType, artifact)
				Local isVoidMethod:Int = member.kind = TEMPLATE_MEMBER_METHOD And member.semanticType And member.semanticType.kind = TEMPLATE_TYPE_BUILTIN And member.semanticType.symbolName.ToLower() = "void"
				If Not memberType.length And member.semanticType And Not isVoidMethod Then
					AddDiagnostic("BMXC2070", "Generic template member '" + member.name + "' has a type outside canonical interface publication", Null)
					Continue
				End If
				If member.kind = TEMPLATE_MEMBER_FIELD Then
					result :+ "." + member.name + memberType + "&" + VisibilityTicks(member.visibility) + "~n"
				Else If member.kind = TEMPLATE_MEMBER_METHOD Then
					If member.isTypeFunction Then
						result :+ "+"
					Else If Not member.isStatic Then
						result :+ "-"
					End If
					result :+ CallableName(member.name) + memberType + "("
					For Local parameterIndex:Int = 0 Until member.parameters.length
						If parameterIndex Then result :+ ","
						Local parameter:TGenericTemplateValueParameter = member.parameters[parameterIndex]
						Local parameterType:String = GenericInterfaceType(parameter.semanticType, artifact)
						If Not parameterType.length And parameter.semanticType Then
							AddDiagnostic("BMXC2070", "Generic template parameter '" + member.name + "." + parameter.name + "' has a type outside canonical interface publication", Null)
							Continue
						End If
						result :+ parameter.name + parameterType
						If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
						If parameter.optional Then result :+ "=" + GenericDefaultSignature(parameter, artifact)
					Next
					result :+ ")" + RoutineVisibilityFlags(member.visibility) + "~n"
				End If
			Next
			result :+ EmitGenericMethods(artifact.identity.qualifiedName)
			If artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then
				result :+ "}AIK~n"
			Else If artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then
				result :+ "}SK~n"
			Else
				result :+ "}K~n"
			End If
			result :+ "'@generic-template " + artifact.formatVersion + "," + Quoted(artifact.identity.StableName()) + "," + Quoted(artifact.EffectiveContentRevision()) + "," + Quoted(output.artifactReference) + "," + Quoted(artifact.languageLinkageRevision) + "~n"
		Next
		Return result
	End Method

	Function GenericMemberPublished:Int(visibility:Int)
		Return visibility = VISIBILITY_PUBLIC Or visibility = VISIBILITY_PROTECTED Or visibility = VISIBILITY_PROTECTED_INTERNAL
	End Function

	Method GenericDefaultSignature:String(parameter:TGenericTemplateValueParameter, artifact:TGenericTemplateArtifact)
		If Not parameter Or Not parameter.defaultValue Then Return ""
		Local value:TGenericTemplateNode = parameter.defaultValue
		' Null defaults are retained as an explicit conversion to the parameter
		' type. The compact interface spelling is only used for overload binding;
		' specialization consumes the canonical bound node from the artifact.
		If value.kind = TEMPLATE_NODE_CONVERSION And value.children.length = 1 Then
			Local literal:TGenericTemplateNode = value.children[0]
			If literal And literal.kind = TEMPLATE_NODE_LITERAL And literal.valueText.ToLower() = "null" Then Return "Null"
		End If
		If value.kind <> TEMPLATE_NODE_LITERAL Then Return ""
		If value.identity = "string-code-units" Then Return "$" + QuotedConstantString(GenericStringCodeUnits(value.valueText))
		If GenericEnumType(parameter.semanticType) Then Return value.valueText
		Return value.valueText + GenericInterfaceType(parameter.semanticType, artifact)
	End Method

	Function GenericStringCodeUnits:String(encoded:String)
		If Not encoded.length Then Return ""
		Local result:String
		For Local unit:String = EachIn encoded.Split(",")
			result :+ Chr(Int(unit))
		Next
		Return result
	End Function

	Method EmitGenericMethods:String(containingTypeName:String)
		If Not genericPlan Or Not containingTypeName.length Then Return ""
		Local result:String
		For Local output:TCompilerGenericTemplateOutput = EachIn genericPlan.templateOutputs
			If Not output Or Not output.isPublished Or Not output.artifact Then Continue
			Local artifact:TGenericTemplateArtifact = output.artifact
			Local isTypeFunction:Int = Not artifact.isMethod And GenericRoutineOwnerName(artifact).ToLower() = containingTypeName.ToLower()
			If artifact.isMethod Then
				If Not artifact.containingType Or artifact.containingType.symbolName.ToLower() <> containingTypeName.ToLower() Then Continue
			Else If Not isTypeFunction Then
				Continue
			End If
			If artifact.members.length <> 1 Then
				AddDiagnostic("BMXC2070", "Generic method template '" + artifact.identity.qualifiedName + "' has an invalid canonical signature", Null)
				Continue
			End If
			Local routine:TGenericTemplateMember = artifact.members[0]
			If isTypeFunction Then result :+ "+" Else result :+ "-"
			result :+ CallableName(routine.name) + "<"
			For Local index:Int = 0 Until artifact.parameters.length
				If index Then result :+ ","
				result :+ artifact.parameters[index].name
			Next
			result :+ ">" + GenericInterfaceType(routine.semanticType, artifact) + "("
			For Local parameterIndex:Int = 0 Until routine.parameters.length
				If parameterIndex Then result :+ ","
				Local parameter:TGenericTemplateValueParameter = routine.parameters[parameterIndex]
				result :+ parameter.name + GenericInterfaceType(parameter.semanticType, artifact)
				If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
				If parameter.optional Then result :+ "=" + GenericDefaultSignature(parameter, artifact)
			Next
			result :+ ")" + GenericConstraints(artifact) + "~n"
			result :+ "'@generic-template " + artifact.formatVersion + "," + Quoted(artifact.identity.StableName()) + "," + Quoted(artifact.EffectiveContentRevision()) + "," + Quoted(output.artifactReference) + "," + Quoted(artifact.languageLinkageRevision) + "~n"
		Next
		Return result
	End Method

	Function GenericRoutineOwnerName:String(artifact:TGenericTemplateArtifact)
		If Not artifact Or Not artifact.identity Or artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Return ""
		Local dot:Int = artifact.identity.qualifiedName.FindLast(".")
		If dot <= 0 Then Return ""
		Return artifact.identity.qualifiedName[..dot]
	End Function

	Method GenericConstraints:String(artifact:TGenericTemplateArtifact)
		If Not artifact Then Return ""
		Local result:String
		For Local parameter:TGenericTemplateParameter = EachIn artifact.parameters
			If Not parameter Or Not parameter.constraints.length Then Continue
			If Not result.length Then result = " Where " Else result :+ ", "
			result :+ parameter.name + " Extends "
			For Local index:Int = 0 Until parameter.constraints.length
				If index Then result :+ " And "
				result :+ GenericInheritanceName(parameter.constraints[index], artifact)
			Next
		Next
		Return result
	End Method

	Method GenericInheritanceName:String(value:TTemplateTypeReference, artifact:TGenericTemplateArtifact)
		Local result:String = GenericInterfaceType(value, artifact)
		If result.StartsWith(":") Then result = result[1..]
		Return result
	End Method

	Method GenericInterfaceType:String(value:TTemplateTypeReference, artifact:TGenericTemplateArtifact)
		If Not value Then Return ""
		Select value.kind
			Case TEMPLATE_TYPE_BUILTIN
				Select value.symbolName.ToLower()
					Case "void" Return ""
					Case "byte" Return "@"
					Case "short" Return "@@"
					Case "int" Return "%"
					Case "uint" Return "|"
					Case "long" Return "%%"
					Case "ulong" Return "||"
					Case "longint" Return "%v"
					Case "ulongint" Return "%e"
					Case "size_t" Return "%z"
					Case "float" Return "#"
					Case "double" Return "!"
					Case "string" Return "$"
					Case "object" Return ":Object"
				End Select
			Case TEMPLATE_TYPE_PARAMETER
				If value.parameterOwner = TEMPLATE_PARAMETER_OWNER_ROUTINE And value.parameterIndex >= 0 And value.parameterIndex < artifact.parameters.length Then Return ":" + artifact.parameters[value.parameterIndex].name
				If value.parameterOwner = TEMPLATE_PARAMETER_OWNER_TYPE Then
					If artifact.isMethod And value.parameterIndex >= 0 And value.parameterIndex < artifact.containingParameters.length Then Return ":" + artifact.containingParameters[value.parameterIndex].name
					If Not artifact.isMethod And value.parameterIndex >= 0 And value.parameterIndex < artifact.parameters.length Then Return ":" + artifact.parameters[value.parameterIndex].name
				End If
			Case TEMPLATE_TYPE_POINTER
				Local pointerElementType:String = GenericInterfaceType(value.elementType, artifact)
				If pointerElementType.length Then Return pointerElementType + "*"
			Case TEMPLATE_TYPE_ARRAY
				Local arrayElementType:String = GenericInterfaceType(value.elementType, artifact)
				If arrayElementType.length And value.rank > 0 Then
					Local arraySuffix:String = "&["
					For Local dimension:Int = 1 Until value.rank
						arraySuffix :+ ","
					Next
					Return arrayElementType + arraySuffix + "]"
				End If
			Case TEMPLATE_TYPE_STATIC_ARRAY
				Local staticArrayElementType:String = GenericInterfaceType(value.elementType, artifact)
				If staticArrayElementType.length And value.staticArrayLength > 0 Then Return staticArrayElementType + "&[" + value.staticArrayLength + "]"
			Case TEMPLATE_TYPE_CALLABLE
				Return GenericCallableInterfaceType(value, artifact)
			Case TEMPLATE_TYPE_CLOSURE
				Return ":" + GenericClosureTypeName(value, artifact)
			Case TEMPLATE_TYPE_NAMED
				Local result:String
				If GenericEnumType(value) Then result = "/" + value.symbolName Else result = ":" + value.symbolName
				If value.arguments.length Then
					result :+ "<"
					For Local index:Int = 0 Until value.arguments.length
						If index Then result :+ ","
						Local argument:String = GenericInterfaceType(value.arguments[index], artifact)
						If argument.StartsWith(":") Then argument = argument[1..]
						result :+ argument
					Next
					result :+ ">"
				End If
				Return result
		End Select
		Return ""
	End Method

	Method GenericCallableInterfaceType:String(value:TTemplateTypeReference, artifact:TGenericTemplateArtifact)
		If Not value Or value.kind <> TEMPLATE_TYPE_CALLABLE Or Not value.elementType Then Return ""
		Local result:String = GenericInterfaceType(value.elementType, artifact) + "("
		For Local index:Int = 0 Until value.arguments.length
			If index Then result :+ ","
			result :+ "arg" + index + GenericInterfaceType(value.arguments[index], artifact)
			If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then result :+ " Var"
		Next
		Return result + ")"
	End Method

	Method GenericClosureTypeName:String(value:TTemplateTypeReference, artifact:TGenericTemplateArtifact)
		If Not value Or value.kind <> TEMPLATE_TYPE_CLOSURE Or Not value.elementType Then Return ""
		Local result:String = "Closure<"
		Local returnType:String = GenericClosureComponentType(value.elementType, artifact)
		If returnType.ToLower() <> "void" Then result :+ returnType
		result :+ "("
		For Local index:Int = 0 Until value.arguments.length
			If index Then result :+ ","
			Local parameterName:String = "arg" + index
			If index < value.callableParameterNames.length And value.callableParameterNames[index].length Then parameterName = value.callableParameterNames[index]
			result :+ parameterName + ":" + GenericClosureComponentType(value.arguments[index], artifact)
			If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then result :+ " Var"
		Next
		Return result + ")>"
	End Method

	Method GenericClosureComponentType:String(value:TTemplateTypeReference, artifact:TGenericTemplateArtifact)
		If Not value Then Return ""
		If value.kind = TEMPLATE_TYPE_BUILTIN Then Return value.symbolName
		If value.kind = TEMPLATE_TYPE_PARAMETER Then
			If value.parameterOwner = TEMPLATE_PARAMETER_OWNER_ROUTINE And value.parameterIndex >= 0 And value.parameterIndex < artifact.parameters.length Then Return artifact.parameters[value.parameterIndex].name
			If value.parameterOwner = TEMPLATE_PARAMETER_OWNER_TYPE Then
				If artifact.isMethod And value.parameterIndex >= 0 And value.parameterIndex < artifact.containingParameters.length Then Return artifact.containingParameters[value.parameterIndex].name
				If Not artifact.isMethod And value.parameterIndex >= 0 And value.parameterIndex < artifact.parameters.length Then Return artifact.parameters[value.parameterIndex].name
			End If
		End If
		If value.kind = TEMPLATE_TYPE_CLOSURE Then Return GenericClosureTypeName(value, artifact)
		Local compact:String = GenericInterfaceType(value, artifact)
		If compact.StartsWith(":") Then Return compact[1..]
		Return compact
	End Method

	Method GenericEnumType:Int(value:TTemplateTypeReference)
		If Not value Or value.kind <> TEMPLATE_TYPE_NAMED Then Return False
		If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return True
		If Not irModule Then Return False
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			If irEnum.name.ToLower() <> value.symbolName.ToLower() And irEnum.semanticType.ToLower() <> value.symbolName.ToLower() Then Continue
			If value.moduleName.length And irEnum.originModule.length And irEnum.originModule.ToLower() <> value.moduleName.ToLower() Then Continue
			Return True
		Next
		Return False
	End Method

	Method EmitEnum:String(irEnum:TCompilerIrEnum)
		If Not irEnum Or Not irEnum.abiName.length Then
			AddDiagnostic("BMXC2075", "Public Enum has no canonical ABI identity", EnumSource(irEnum))
			Return ""
		End If
		Local underlyingMarker:String = EnumUnderlyingInterfaceType(irEnum.underlyingType)
		If Not underlyingMarker.length Then
			AddDiagnostic("BMXC2075", "Public Enum '" + irEnum.name + "' has unsupported underlying type '" + irEnum.underlyingType + "'", irEnum.source)
			Return ""
		End If
		Local result:String = irEnum.name + "\" + underlyingMarker + "{" + SourceSuffix(irEnum.source) + "~n"
		For Local value:TCompilerIrEnumValue = EachIn irEnum.values
			result :+ value.name + "=" + value.integerValue + SourceSuffix(value.source) + "~n"
		Next
		result :+ "}"
		If irEnum.isFlags Then result :+ "F"
		Return result + "=" + Quoted(irEnum.abiName) + "~n"
	End Method

	Function EnumUnderlyingInterfaceType:String(semanticType:String)
		Select semanticType
			Case "Byte" Return "@"
			Case "Short" Return "@@"
			Case "Int" Return "%"
			Case "UInt" Return "|"
			Case "Long" Return "%%"
			Case "ULong" Return "||"
			Case "Size_T" Return "%z"
			Case "LongInt" Return "%v"
			Case "ULongInt" Return "%e"
		End Select
		Return ""
	End Function

	Method EmitInterfaceTree:String(irInterface:TCompilerIrInterface, emitted:TMap, visiting:TMap)
		If Not irInterface Or emitted.Contains(irInterface.interfaceId) Then Return ""
		If visiting.Contains(irInterface.interfaceId) Then
			AddDiagnostic("BMXC2062", "Public Interface inheritance cycle reaches '" + irInterface.name + "'", irInterface.source)
			Return ""
		End If
		visiting.Insert(irInterface.interfaceId, irInterface.interfaceId)
		Local result:String
		For Local baseId:String = EachIn irInterface.baseInterfaceIds
			Local baseInterface:TCompilerIrInterface = InterfaceById(baseId)
			If Not baseInterface Then
				AddDiagnostic("BMXC2062", "Public Interface '" + irInterface.name + "' has no retained base Interface layout", irInterface.source)
				Continue
			End If
			If Not baseInterface.isImported Then
				If baseInterface.visibility <> VISIBILITY_PUBLIC Then
					AddDiagnostic("BMXC2062", "Public Interface '" + irInterface.name + "' has a non-public base Interface", irInterface.source)
					Continue
				End If
				result :+ EmitInterfaceTree(baseInterface, emitted, visiting)
			End If
		Next
		result :+ EmitInterface(irInterface)
		visiting.Remove(irInterface.interfaceId)
		emitted.Insert(irInterface.interfaceId, irInterface.interfaceId)
		Return result
	End Method

	Method EmitInterface:String(irInterface:TCompilerIrInterface)
		If Not irInterface Or Not irInterface.abiName.length Then
			AddDiagnostic("BMXC2062", "Public Interface has no canonical ABI identity", InterfaceSource(irInterface))
			Return ""
		End If
		Local baseName:String = "Object"
		If irInterface.isExternInterface Then baseName = "Null"
		If irInterface.baseInterfaceIds.length Then
			Local baseInterface:TCompilerIrInterface = InterfaceById(irInterface.baseInterfaceIds[0])
			If Not baseInterface Then
				AddDiagnostic("BMXC2062", "Public Interface '" + irInterface.name + "' has no retained base Interface identity", irInterface.source)
				Return ""
			End If
			baseName = baseInterface.name
		End If
		For Local index:Int = 1 Until irInterface.baseInterfaceIds.length
			Local additionalBase:TCompilerIrInterface = InterfaceById(irInterface.baseInterfaceIds[index])
			If Not additionalBase Then
				AddDiagnostic("BMXC2062", "Public Interface '" + irInterface.name + "' has no retained additional base Interface identity", irInterface.source)
				Return ""
			End If
			If index = 1 Then baseName :+ "@" Else baseName :+ ","
			baseName :+ additionalBase.name
		Next
		Local result:String = irInterface.name + "^" + baseName + "{" + SourceSuffix(irInterface.source) + "~n"
		For Local interfaceMethod:TCompilerIrInterfaceMethod = EachIn irInterface.methods
			If interfaceMethod.declaringInterfaceId <> irInterface.interfaceId Then Continue
			Local methodText:String = EmitInterfaceMethod(irInterface, interfaceMethod)
			If methodText.length Then result :+ methodText + "~n"
		Next
		result :+ EmitGenericMethods(irInterface.name)
		If irInterface.isExternInterface Then Return result + "}EI" + VisibilityTicks(irInterface.visibility) + "=0~n"
		Return result + "}AI" + VisibilityTicks(irInterface.visibility) + "=" + Quoted(irInterface.abiName) + "~n"
	End Method

	Method EmitInterfaceMethod:String(irInterface:TCompilerIrInterface, interfaceMethod:TCompilerIrInterfaceMethod)
		If interfaceMethod.callableReturnType.length Then
			If Not SupportsMemberType(interfaceMethod.callableReturnType) Then
				AddDiagnostic("BMXC2062", "Public Interface method callable return type '" + interfaceMethod.callableReturnType + "' is outside the compact interface slice", interfaceMethod.source)
				Return ""
			End If
			For Local callableParameter:TCompilerIrParameter = EachIn interfaceMethod.callableReturnParameters
				If Not ParameterModeSupported(callableParameter) Or Not MemberParameterSupported(callableParameter) Then
					AddDiagnostic("BMXC2062", "Public Interface method '" + irInterface.name + "." + interfaceMethod.name + "' has a callable return signature outside the compact interface slice", interfaceMethod.source)
					Return ""
				End If
			Next
		Else If Not SupportsMemberType(interfaceMethod.returnType) Then
			AddDiagnostic("BMXC2062", "Public Interface method return type '" + interfaceMethod.returnType + "' is outside the compact interface slice", interfaceMethod.source)
			Return ""
		End If
		If Not interfaceMethod.abiName.length Then
			AddDiagnostic("BMXC2062", "Public Interface method '" + irInterface.name + "." + interfaceMethod.name + "' has no canonical ABI identity", interfaceMethod.source)
			Return ""
		End If
		For Local parameter:TCompilerIrParameter = EachIn interfaceMethod.parameters
			If Not ParameterModeSupported(parameter) Or Not MemberParameterSupported(parameter) Then
				AddDiagnostic("BMXC2062", "Public Interface method '" + irInterface.name + "." + interfaceMethod.name + "' has parameters outside the compact interface slice", interfaceMethod.source)
				Return ""
			End If
		Next
		Local signature:String = "-" + CallableName(interfaceMethod.name)
		If interfaceMethod.callableReturnType.length Then
			signature :+ MemberInterfaceType(interfaceMethod.callableReturnType) + "("
			For Local index:Int = 0 Until interfaceMethod.callableReturnParameters.length
				If index Then signature :+ ","
				signature :+ MemberParameterSignature(interfaceMethod.callableReturnParameters[index])
			Next
			signature :+ ")" + CallingConventionFlag(interfaceMethod.callableReturnCallingConvention)
		Else
			signature :+ MemberInterfaceType(interfaceMethod.returnType)
		End If
		signature :+ "("
		For Local index:Int = 0 Until interfaceMethod.parameters.length
			If index Then signature :+ ","
			signature :+ MemberParameterSignature(interfaceMethod.parameters[index])
		Next
		Local implementationFlag:String = "A"
		If interfaceMethod.implementationKind = INTERFACE_METHOD_DEFAULT Then implementationFlag = "D"
		If interfaceMethod.implementationKind = INTERFACE_METHOD_REABSTRACT Then implementationFlag = "R"
		Return signature + ")" + CallingConventionFlag(interfaceMethod.callingConvention) + implementationFlag + "=" + Quoted(interfaceMethod.abiName) + SourceSuffix(interfaceMethod.source)
	End Method

	Method EmitStructTree:String(irStruct:TCompilerIrStruct, emitted:TMap, visiting:TMap)
		If Not irStruct Or emitted.Contains(irStruct.structId) Then Return ""
		If visiting.Contains(irStruct.structId) Then
			AddDiagnostic("BMXC2066", "Public Struct layout cycle reaches '" + irStruct.name + "'", irStruct.source)
			Return ""
		End If
		visiting.Insert(irStruct.structId, irStruct.structId)
		Local result:String
		For Local irField:TCompilerIrStructField = EachIn irStruct.fields
			Local nestedId:String = irField.structId
			If irField.staticArrayStructId.length Then nestedId = irField.staticArrayStructId
			If nestedId.length Then result :+ EmitStructTree(StructById(nestedId), emitted, visiting)
		Next
		result :+ EmitStruct(irStruct)
		visiting.Remove(irStruct.structId)
		emitted.Insert(irStruct.structId, irStruct.structId)
		Return result
	End Method

	Method EmitStruct:String(irStruct:TCompilerIrStruct)
		If Not irStruct Or Not irStruct.abiName.length Then
			AddDiagnostic("BMXC2066", "Public Struct has no canonical ABI identity", irStruct.source)
			Return ""
		End If
		Local result:String = irStruct.name + "^Null{" + SourceSuffix(irStruct.source) + "~n"
		For Local irField:TCompilerIrStructField = EachIn irStruct.fields
			If irField.isStaticArray Then
				If Not SupportsMemberType(irField.staticArrayElementType) Then
					AddDiagnostic("BMXC2066", "Public Struct StaticArray field element type '" + irField.staticArrayElementType + "' is outside the compact interface slice", irField.source)
					Continue
				End If
				result :+ "~~" + irField.name + MemberInterfaceType(irField.staticArrayElementType) + "&[" + irField.staticArrayLength + "]&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source) + "~n"
				Continue
			End If
			If irField.callableReturnType.length Then
				If Not ParameterShapeSupported(irField.semanticType, irField.callableReturnType, irField.callableParameters) Then
					AddDiagnostic("BMXC2066", "Public Struct callable field type '" + irField.semanticType + "' is outside the compact interface slice", irField.source)
					Continue
				End If
				Local callablePrefix:String = "."
				If irField.isReadOnly Then callablePrefix = "@"
				result :+ callablePrefix + irField.name + MemberInterfaceType(irField.callableReturnType) + "("
				For Local parameterIndex:Int = 0 Until irField.callableParameters.length
					If parameterIndex Then result :+ ","
					result :+ MemberParameterSignature(irField.callableParameters[parameterIndex])
				Next
				result :+ ")" + CallingConventionFlag(irField.callableCallingConvention) + "&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source) + "~n"
				Continue
			End If
			If irField.arrayCallableReturnType.length Then
				If Not CallableArrayShapeSupported(irField.arrayCallableReturnType, irField.arrayCallableParameters, irField.arrayCallableRank) Then
					AddDiagnostic("BMXC2066", "Public Struct callable-array field type '" + irField.semanticType + "' is outside the compact interface slice", irField.source)
					Continue
				End If
				Local callableArrayPrefix:String = "."
				If irField.isReadOnly Then callableArrayPrefix = "@"
				result :+ callableArrayPrefix + irField.name + CallableArrayInterfaceType(irField.arrayCallableReturnType, irField.arrayCallableParameters, irField.arrayCallableRank, irField.arrayCallableCallingConvention) + "&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source) + "~n"
				Continue
			End If
			If Not SupportsMemberType(irField.semanticType) Then
				AddDiagnostic("BMXC2066", "Public Struct field type '" + irField.semanticType + "' is outside the compact interface slice", irField.source)
				Continue
			End If
			Local prefix:String = "."
			If irField.isReadOnly Then prefix = "@"
			result :+ prefix + irField.name + MemberInterfaceType(irField.semanticType) + "&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source) + "~n"
		Next
		Local hasConstructor:Int
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.ownerStructId <> irStruct.structId Then Continue
			If routine.lifecycleKind = IR_LIFECYCLE_CONSTRUCTOR Then hasConstructor = True
			Local routineText:String = EmitTypeRoutine(routine)
			If routineText.length Then result :+ routineText + "~n"
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If Not routine.isGlobalEntry Or Not routine.body Then Continue
			For Local statement:TCompilerIrStatement = EachIn routine.body.statements
				Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
				If Not variable Or variable.ownerStructId <> irStruct.structId Or variable.visibility <> VISIBILITY_PUBLIC Then Continue
				If variable.storage = "constant" Then
					Local constantText:String = EmitConstant(variable)
					If constantText.length Then result :+ constantText + "~n"
				Else If variable.isPublished Then
					Local globalText:String = EmitGlobal(variable)
					If globalText.length Then result :+ globalText + "~n"
				End If
			Next
		Next
		result :+ EmitGenericMethods(irStruct.name)
		If Not hasConstructor Then result :+ "-New()=" + Quoted(irStruct.abiName + "_New") + SourceSuffix(irStruct.source) + "~n"
		' Type/Struct trailer visibility uses the same P/R/I flag alphabet as
		' routines. Backticks are only the compact field/Global suffix encoding.
		Return result + "}S" + RoutineVisibilityFlags(irStruct.visibility) + "=" + Quoted(irStruct.abiName) + "~n"
	End Method

	Method StructById:TCompilerIrStruct(structId:String)
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If irStruct.structId = structId Then Return irStruct
		Next
		Return Null
	End Method

	Method EmitType:String(irClass:TCompilerIrClass)
		If Not irClass Or Not irClass.abiName.length Then
			AddDiagnostic("BMXC2061", "Public Type has no canonical ABI identity", irClass.source)
			Return ""
		End If
		Local baseName:String = "Object"
		If irClass.baseClassId.length Then
			Local baseClass:TCompilerIrClass = ClassById(irClass.baseClassId)
			If Not baseClass Or Not baseClass.isPublished Then
				AddDiagnostic("BMXC2061", "Public Type '" + irClass.name + "' has a base outside the compact interface slice", irClass.source)
				Return ""
			End If
			baseName = baseClass.name
		Else If irClass.baseImportedClassId.length Then
			Local importedBase:TCompilerIrImportedClass = ImportedClassById(irClass.baseImportedClassId)
			If Not importedBase Then
				AddDiagnostic("BMXC2061", "Public Type '" + irClass.name + "' has no imported base ABI record", irClass.source)
				Return ""
			End If
			If importedBase.isGenericSpecialization And importedBase.semanticType.Contains("<") Then
				baseName = importedBase.semanticType
			Else
				baseName = importedBase.name
			End If
		End If
		Local implementedNames:String
		For Local interfaceId:String = EachIn irClass.declaredInterfaceIds
			Local implementedInterface:TCompilerIrInterface = InterfaceById(interfaceId)
			If Not implementedInterface Then
				AddDiagnostic("BMXC2061", "Public Type '" + irClass.name + "' has no retained implemented Interface identity", irClass.source)
				Continue
			End If
			If implementedNames.length Then implementedNames :+ ","
			If implementedInterface.isImported And implementedInterface.semanticType.Contains("<") Then
				implementedNames :+ implementedInterface.semanticType
			Else
				implementedNames :+ implementedInterface.name
			End If
		Next
		If implementedNames.length Then baseName :+ "@" + implementedNames
		Local result:String = irClass.name + "^" + baseName + "{" + SourceSuffix(irClass.source) + "~n"
		For Local index:Int = irClass.declaredFieldStart Until irClass.declaredFieldStart + irClass.declaredFieldCount
			Local irField:TCompilerIrClassField = irClass.fields[index]
			Local fieldText:String = EmitField(irField)
			If fieldText.length Then result :+ fieldText + "~n"
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If Not routine.isGlobalEntry Or Not routine.body Then Continue
			For Local statement:TCompilerIrStatement = EachIn routine.body.statements
				Local variable:TCompilerIrVariableDeclaration = TCompilerIrVariableDeclaration(statement)
				If Not variable Or variable.ownerClassId <> irClass.classId Or variable.visibility <> VISIBILITY_PUBLIC Then Continue
				If variable.storage = "constant" Then
					Local constantText:String = EmitConstant(variable)
					If constantText.length Then result :+ constantText + "~n"
				Else If variable.isPublished Then
					Local globalText:String = EmitGlobal(variable)
					If globalText.length Then result :+ globalText + "~n"
				End If
			Next
		Next
		For Local routine:TCompilerIrFunction = EachIn irModule.functions
			If routine.ownerClassId <> irClass.classId Then Continue
			Local routineText:String = EmitTypeRoutine(routine)
			If routineText.length Then result :+ routineText + "~n"
		Next
		result :+ EmitGenericMethods(irClass.name)
		Local typeFlags:String
		If irClass.isAbstract Then typeFlags = "A"
		Return result + "}" + typeFlags + "=" + Quoted(irClass.abiName) + "~n"
	End Method

	Method EmitField:String(irField:TCompilerIrClassField)
		If irField And irField.isStaticArray Then
			If Not SupportsMemberType(irField.staticArrayElementType) Then
				AddDiagnostic("BMXC2061", "Public Type StaticArray field element type '" + irField.staticArrayElementType + "' is outside the compact interface slice", FieldSource(irField))
				Return ""
			End If
			Return "~~" + irField.name + MemberInterfaceType(irField.staticArrayElementType) + "&[" + irField.staticArrayLength + "]&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source)
		End If
		Local erasedPrivateType:Int = irField And UnpublishedClassByType(irField.semanticType) <> Null
		If erasedPrivateType Then
			Local erasedPrefix:String = "."
			If irField.isReadOnly Then erasedPrefix = "@"
			Return erasedPrefix + irField.name + ":Object&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source)
		End If
		Local privateArrayOpen:Int = ManagedArrayOpenBracket(irField.semanticType)
		If privateArrayOpen >= 0 And UnpublishedClassByType(irField.semanticType[..privateArrayOpen]) Then
			Local erasedArrayPrefix:String = "."
			If irField.isReadOnly Then erasedArrayPrefix = "@"
			Return erasedArrayPrefix + irField.name + MemberInterfaceType("Object" + irField.semanticType[privateArrayOpen..]) + "&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source)
		End If
		Local fieldShapeSupported:Int = irField And ParameterShapeSupported(irField.semanticType, irField.callableReturnType, irField.callableParameters)
		If irField And irField.arrayCallableReturnType.length Then fieldShapeSupported = CallableArrayShapeSupported(irField.arrayCallableReturnType, irField.arrayCallableParameters, irField.arrayCallableRank)
		If Not fieldShapeSupported Then
			Local typeName:String
			If irField Then typeName = irField.semanticType
			AddDiagnostic("BMXC2061", "Public Type field type '" + typeName + "' is outside the compact interface slice", FieldSource(irField))
			Return ""
		End If
		Local prefix:String = "."
		If irField.isReadOnly Then prefix = "@"
		Local signature:String = prefix + irField.name
		If irField.arrayCallableReturnType.length Then
			signature :+ CallableArrayInterfaceType(irField.arrayCallableReturnType, irField.arrayCallableParameters, irField.arrayCallableRank, irField.arrayCallableCallingConvention)
		Else If irField.callableReturnType.length Then
			signature :+ MemberInterfaceType(irField.callableReturnType) + "("
			For Local index:Int = 0 Until irField.callableParameters.length
				If index Then signature :+ ","
				signature :+ MemberParameterSignature(irField.callableParameters[index])
			Next
			signature :+ ")" + CallingConventionFlag(irField.callableCallingConvention)
		Else
			signature :+ MemberInterfaceType(irField.semanticType)
		End If
		Return signature + "&" + VisibilityTicks(irField.visibility) + SourceSuffix(irField.source)
	End Method

	Method UnpublishedClassByType:TCompilerIrClass(semanticType:String)
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If Not irClass.isPublished And (irClass.semanticType = semanticType Or irClass.name = semanticType) Then Return irClass
		Next
		Return Null
	End Method

	Method EmitTypeRoutine:String(routine:TCompilerIrFunction)
		Local erasedPrivateReturnType:Int = Not routine.callableReturnType.length And UnpublishedClassByType(routine.returnType) <> Null
		If routine.callableReturnType.length Then
			If Not SupportsMemberType(routine.callableReturnType) Then
				AddDiagnostic("BMXC2061", "Public Type routine callable return type '" + routine.callableReturnType + "' is outside the compact interface slice", routine.source)
				Return ""
			End If
			For Local callableParameter:TCompilerIrParameter = EachIn routine.callableReturnParameters
				If Not ParameterModeSupported(callableParameter) Or Not MemberParameterSupported(callableParameter) Then
					AddDiagnostic("BMXC2061", "Type routine '" + routine.name + "' has a callable return signature outside the compact interface slice", routine.source)
					Return ""
				End If
			Next
		Else If Not erasedPrivateReturnType And Not SupportsMemberType(routine.returnType) Then
			AddDiagnostic("BMXC2061", "Public Type routine return type '" + routine.returnType + "' is outside the compact interface slice", routine.source)
			Return ""
		End If
		For Local parameter:TCompilerIrParameter = EachIn routine.parameters
			If parameter.isOptional And Not MemberDefaultSupported(parameter) Then
				AddDiagnostic("BMXC2061", "Type routine '" + routine.name + "' has a default argument outside the compact interface slice", routine.source)
				Return ""
			End If
			Local supportedMode:Int = ParameterModeSupported(parameter)
			If Not supportedMode Or Not MemberParameterSupported(parameter) Then
				AddDiagnostic("BMXC2061", "Type routine '" + routine.name + "' has parameters outside the compact interface slice", routine.source)
				Return ""
			End If
		Next
		Local prefix:String = "+"
		If routine.isMethod Then prefix = "-"
		Local signature:String = prefix + CallableName(routine.name)
		If routine.callableReturnType.length Then
			signature :+ MemberInterfaceType(routine.callableReturnType) + "("
			For Local index:Int = 0 Until routine.callableReturnParameters.length
				If index Then signature :+ ","
				signature :+ MemberParameterSignature(routine.callableReturnParameters[index])
			Next
			signature :+ ")" + CallingConventionFlag(routine.callableReturnCallingConvention)
		Else If erasedPrivateReturnType Then
			signature :+ ":Object"
		Else
			signature :+ MemberInterfaceType(routine.returnType)
		End If
		signature :+ "("
		For Local index:Int = 0 Until routine.parameters.length
			If index Then signature :+ ","
			signature :+ MemberParameterSignature(routine.parameters[index])
		Next
		Local routineFlags:String = RoutineVisibilityFlags(routine.visibility)
		routineFlags :+ CallingConventionFlag(routine.callingConvention)
		If routine.isAbstract Then routineFlags :+ "A"
		Return signature + ")" + routineFlags + "=" + Quoted(routine.abiName) + SourceSuffix(routine.source)
	End Method

	Method ClassById:TCompilerIrClass(classId:String)
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If irClass.classId = classId Then Return irClass
		Next
		Return Null
	End Method

	Method ImportedClassById:TCompilerIrImportedClass(importedClassId:String)
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If importedClass.importedClassId = importedClassId Then Return importedClass
		Next
		Return Null
	End Method

	Function FieldSource:TCompilerSourceLocation(irField:TCompilerIrClassField)
		If irField Then Return irField.source
		Return Null
	End Function

	Method ParameterShapeSupported:Int(semanticType:String, callableReturnType:String, parameters:TCompilerIrParameter[])
		If callableReturnType.length Then
			If Not SupportsMemberType(callableReturnType) Then Return False
			For Local parameter:TCompilerIrParameter = EachIn parameters
				If Not MemberParameterSupported(parameter) Or Not ParameterModeSupported(parameter) Then Return False
			Next
			Return True
		End If
		Return SupportsMemberType(semanticType)
	End Method

	Method CallableArrayShapeSupported:Int(returnType:String, parameters:TCompilerIrParameter[], rank:Int)
		If rank <= 0 Or Not SupportsMemberType(returnType) Then Return False
		For Local parameter:TCompilerIrParameter = EachIn parameters
			If Not MemberParameterSupported(parameter) Or Not ParameterModeSupported(parameter) Then Return False
		Next
		Return True
	End Method

	Method CallableArrayInterfaceType:String(returnType:String, parameters:TCompilerIrParameter[], rank:Int, callingConvention:String = "c")
		Local result:String = MemberInterfaceType(returnType) + "("
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ","
			result :+ MemberParameterSignature(parameters[index])
		Next
		result :+ ")" + CallingConventionFlag(callingConvention) + "&["
		For Local index:Int = 1 Until rank
			result :+ ","
		Next
		Return result + "]"
	End Method

	Method SupportsMemberType:Int(semanticType:String)
		If IsClosureType(semanticType) Then Return True
		If SupportsType(semanticType) Then Return True
		If semanticType.EndsWith(" Ptr") Then Return SupportsMemberType(semanticType[..semanticType.length - 4])
		If EnumByType(semanticType) Then Return True
		Local arrayBracket:Int = ManagedArrayOpenBracket(semanticType)
		If arrayBracket >= 0 Then Return SupportsMemberType(semanticType[..arrayBracket])
		If semanticType = "Object" Then Return True
		If InterfaceByType(semanticType) Then Return True
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If irClass.isPublished And (SameTypeName(irClass.semanticType, semanticType) Or SameTypeName(irClass.name, semanticType)) Then Return True
		Next
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If SameTypeName(importedClass.semanticType, semanticType) Or SameTypeName(importedClass.name, semanticType) Then Return True
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If SameTypeName(irStruct.semanticType, semanticType) Or SameTypeName(irStruct.name, semanticType) Then Return True
		Next
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If SameTypeName(importedStruct.semanticType, semanticType) Or SameTypeName(importedStruct.name, semanticType) Then Return True
		Next
		Return False
	End Method

	Method MemberInterfaceType:String(semanticType:String)
		If IsClosureType(semanticType) Then Return ":" + semanticType
		Local arrayBracket:Int = ManagedArrayOpenBracket(semanticType)
		If arrayBracket >= 0 Then Return MemberInterfaceType(semanticType[..arrayBracket]) + "&" + semanticType[arrayBracket..]
		If semanticType.EndsWith(" Ptr") Then Return MemberInterfaceType(semanticType[..semanticType.length - 4]) + "*"
		If semanticType = "Object" Then Return ":Object"
		Local irEnum:TCompilerIrEnum = EnumByType(semanticType)
		If irEnum Then Return "/" + irEnum.name
		Local irInterface:TCompilerIrInterface = InterfaceByType(semanticType)
		If irInterface Then
			If irInterface.isExternInterface Then Return "??" + irInterface.name
			If SameTypeName(irInterface.semanticType, semanticType) And irInterface.semanticType.Contains("<") Then Return ":" + irInterface.semanticType
			Return ":" + irInterface.name
		End If
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If irClass.isPublished And (SameTypeName(irClass.semanticType, semanticType) Or SameTypeName(irClass.name, semanticType)) Then
				If SameTypeName(irClass.semanticType, semanticType) And irClass.semanticType.Contains("<") Then Return ":" + irClass.semanticType
				Return ":" + irClass.name
			End If
		Next
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If SameTypeName(importedClass.semanticType, semanticType) Or SameTypeName(importedClass.name, semanticType) Then
				If SameTypeName(importedClass.semanticType, semanticType) And importedClass.semanticType.Contains("<") Then Return ":" + importedClass.semanticType
				Return ":" + importedClass.name
			End If
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If SameTypeName(irStruct.semanticType, semanticType) Or SameTypeName(irStruct.name, semanticType) Then Return ":" + irStruct.name
		Next
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If SameTypeName(importedStruct.semanticType, semanticType) Or SameTypeName(importedStruct.name, semanticType) Then
				If SameTypeName(importedStruct.semanticType, semanticType) And importedStruct.semanticType.Contains("<") Then Return ":" + importedStruct.semanticType
				Return ":" + importedStruct.name
			End If
		Next
		Return InterfaceType(semanticType)
	End Method

	Method MemberParameterSupported:Int(parameter:TCompilerIrParameter)
		If Not parameter Then Return False
		If parameter.isStaticArray Then Return parameter.staticArrayLength > 0 And SupportsMemberType(parameter.staticArrayElementType)
		If parameter.callableReturnType.length Then
			If Not SupportsMemberType(parameter.callableReturnType) Then Return False
			For Local nested:TCompilerIrParameter = EachIn parameter.callableParameters
				If Not ParameterModeSupported(nested) Or Not MemberParameterSupported(nested) Then Return False
			Next
			Return True
		End If
		Return SupportsMemberType(parameter.semanticType) Or UnpublishedClassByType(parameter.semanticType) <> Null
	End Method

	Method MemberParameterSignature:String(parameter:TCompilerIrParameter)
		Local result:String
		If parameter.isStaticArray Then
			result = parameter.name + MemberInterfaceType(parameter.staticArrayElementType) + "&[" + parameter.staticArrayLength + "]"
		Else If parameter.callableReturnType.length Then
			result = parameter.name + MemberInterfaceType(parameter.callableReturnType) + "("
			For Local index:Int = 0 Until parameter.callableParameters.length
				If index Then result :+ ","
				result :+ MemberParameterSignature(parameter.callableParameters[index])
			Next
			result :+ ")" + CallingConventionFlag(parameter.callableCallingConvention)
		Else
			If UnpublishedClassByType(parameter.semanticType) Then
				result = parameter.name + ":Object"
			Else
				result = parameter.name + MemberInterfaceType(parameter.semanticType)
			End If
		End If
		If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
		If parameter.isOptional Then result :+ "=" + MemberDefaultSignature(parameter)
		Return result
	End Method

	Method MemberDefaultSupported:Int(parameter:TCompilerIrParameter)
		If parameter.defaultKind = CONSTANT_VALUE_NULL Then
			Return parameter.callableReturnType.length Or IsClosureType(parameter.semanticType) Or ScalarNullDefaultSupported(parameter.semanticType) Or parameter.semanticType = "String" Or parameter.semanticType = "Object" Or IsManagedArrayType(parameter.semanticType) Or parameter.semanticType.EndsWith(" Ptr") Or SupportsNamedMemberType(parameter.semanticType) Or UnpublishedClassByType(parameter.semanticType) <> Null
		End If
		Return DefaultSupported(parameter)
	End Method

	Method ScalarNullDefaultSupported:Int(semanticType:String)
		Select semanticType
			Case "Byte", "Short", "Int", "UInt", "Long", "ULong", "LongInt", "ULongInt", "Size_T", "WParam", "LParam", "Float", "Double"
				Return True
		End Select
		Return EnumByType(semanticType) <> Null
	End Method

	Method MemberDefaultSignature:String(parameter:TCompilerIrParameter)
		' Pointer zero is already target-typed by compile-time analysis. Repeating
		' the compact pointer marker on the literal (0@*) is not source syntax and
		' makes a freshly published interface fail constant evaluation on import.
		If parameter.semanticType.EndsWith(" Ptr") And parameter.defaultKind = CONSTANT_VALUE_INTEGER Then Return "0"
		If parameter.defaultKind = CONSTANT_VALUE_NULL Then
			If parameter.callableReturnType.length Then Return "Null"
			If IsClosureType(parameter.semanticType) Then Return "Null"
			If parameter.semanticType = "String" Then Return "$" + Quoted("")
			If IsManagedArrayType(parameter.semanticType) Then Return Quoted("bbEmptyArray")
			If parameter.semanticType.EndsWith(" Ptr") Or ScalarNullDefaultSupported(parameter.semanticType) Then Return "0"
			Return Quoted("bbNullObject")
		End If
		Return DefaultSignature(parameter)
	End Method

	Method SupportsNamedMemberType:Int(semanticType:String)
		If semanticType = "Object" Then Return True
		If EnumByType(semanticType) Then Return True
		If InterfaceByType(semanticType) Then Return True
		For Local irClass:TCompilerIrClass = EachIn irModule.classes
			If irClass.isPublished And (SameTypeName(irClass.semanticType, semanticType) Or SameTypeName(irClass.name, semanticType)) Then Return True
		Next
		For Local importedClass:TCompilerIrImportedClass = EachIn irModule.importedClasses
			If SameTypeName(importedClass.semanticType, semanticType) Or SameTypeName(importedClass.name, semanticType) Then Return True
		Next
		For Local irStruct:TCompilerIrStruct = EachIn irModule.structs
			If SameTypeName(irStruct.semanticType, semanticType) Or SameTypeName(irStruct.name, semanticType) Then Return True
		Next
		For Local importedStruct:TCompilerIrImportedStruct = EachIn irModule.importedStructs
			If SameTypeName(importedStruct.semanticType, semanticType) Or SameTypeName(importedStruct.name, semanticType) Then Return True
		Next
		Return False
	End Method

	Function VisibilityTicks:String(visibility:Int)
		Select visibility
			Case VISIBILITY_PRIVATE Return "`"
			Case VISIBILITY_PROTECTED Return "``"
			Case VISIBILITY_INTERNAL Return "```"
			Case VISIBILITY_PRIVATE_INTERNAL Return "````"
			Case VISIBILITY_PROTECTED_INTERNAL Return "`````"
		End Select
		Return ""
	End Function

	Function RoutineVisibilityFlags:String(visibility:Int)
		Select visibility
			Case VISIBILITY_PRIVATE Return "P"
			Case VISIBILITY_PROTECTED Return "R"
			Case VISIBILITY_INTERNAL Return "I"
			Case VISIBILITY_PRIVATE_INTERNAL Return "PI"
			Case VISIBILITY_PROTECTED_INTERNAL Return "RI"
		End Select
		Return ""
	End Function

	Method EmitConstant:String(variable:TCompilerIrVariableDeclaration)
		If (Not SupportsType(variable.semanticType) And Not EnumByType(variable.semanticType)) Or variable.callableReturnType.length Or variable.isStaticArray Then
			AddDiagnostic("BMXC2064", "Public constant type '" + variable.semanticType + "' is outside the compact interface slice", variable.source)
			Return ""
		End If
		Local literal:TCompilerIrLiteral = TCompilerIrLiteral(variable.initializer)
		If Not literal Then
			AddDiagnostic("BMXC2064", "Public constant '" + variable.name + "' is not represented by a normalized literal", variable.source)
			Return ""
		End If
		Local valueText:String
		If variable.semanticType = "String" Then
			Local stringValue:String
			Local found:Int
			For Local stringLiteral:TCompilerIrStringLiteral = EachIn irModule.stringLiterals
				If stringLiteral.literalId = literal.stringLiteralId Then stringValue = stringLiteral.value; found = True; Exit
			Next
			If Not found Then
				AddDiagnostic("BMXC2064", "Public String constant '" + variable.name + "' has no retained literal value", variable.source)
				Return ""
			End If
			valueText = "$" + QuotedConstantString(stringValue)
		Else
			valueText = literal.text + InterfaceType(variable.semanticType)
		End If
		Return variable.name + GlobalInterfaceType(variable.semanticType) + "=" + valueText + SourceSuffix(variable.source)
	End Method

	Method EmitRoutine:String(routine:TCompilerIrFunction)
		If routine.callableReturnType.length Then
			If Not SupportsRoutineType(routine.callableReturnType) Then
				AddDiagnostic("BMXC2063", "Public routine callable return type '" + routine.callableReturnType + "' is outside the compact interface slice", routine.source)
				Return ""
			End If
			For Local callableParameter:TCompilerIrParameter = EachIn routine.callableReturnParameters
				If Not ParameterModeSupported(callableParameter) Or Not ParameterSupported(callableParameter) Then
					AddDiagnostic("BMXC2063", "Public routine '" + routine.name + "' has a callable return signature outside the compact interface slice", routine.source)
					Return ""
				End If
			Next
		Else If Not SupportsRoutineType(routine.returnType) Then
			AddDiagnostic("BMXC2063", "Public routine return type '" + routine.returnType + "' is outside the compact interface slice", routine.source)
			Return ""
		End If
		For Local parameter:TCompilerIrParameter = EachIn routine.parameters
			If parameter.isOptional And Not RoutineDefaultSupported(parameter) Then
				AddDiagnostic("BMXC2063", "Public routine '" + routine.name + "' has a default argument outside the compact interface slice", routine.source)
				Return ""
			End If
			Local supportedMode:Int = ParameterModeSupported(parameter)
			If Not supportedMode Or Not ParameterSupported(parameter) Then
				AddDiagnostic("BMXC2063", "Public routine '" + routine.name + "' has parameters outside the compact interface slice", routine.source)
				Return ""
			End If
		Next

		Local signature:String = routine.name
		If routine.callableReturnType.length Then
			signature :+ RoutineInterfaceType(routine.callableReturnType) + "("
			For Local index:Int = 0 Until routine.callableReturnParameters.length
				If index Then signature :+ ","
				signature :+ RoutineParameterSignature(routine.callableReturnParameters[index])
			Next
			signature :+ ")" + CallingConventionFlag(routine.callableReturnCallingConvention)
		Else
			signature :+ RoutineInterfaceType(routine.returnType)
		End If
		signature :+ "("
		For Local index:Int = 0 Until routine.parameters.length
			If index Then signature :+ ","
			signature :+ RoutineParameterSignature(routine.parameters[index])
		Next
		Return signature + ")" + CallingConventionFlag(routine.callingConvention) + "=" + Quoted(routine.abiName) + SourceSuffix(routine.source)
	End Method

	Method EmitExternalRoutine:String(externalRoutine:TCompilerIrExternalFunction)
		Local routine:TCompilerIrFunction = New TCompilerIrFunction
		routine.name = externalRoutine.sourceName
		routine.abiName = externalRoutine.abiName
		' A compact interface is the source contract for later compilation
		' units. Preserve complete native declarations here so typedef-rich
		' call-site casts are not reduced to the linker name at publication.
		If externalRoutine.nativeDeclaration.length Then
			routine.abiName = externalRoutine.nativeDeclaration
			If externalRoutine.nativeDeclarationSuppressesPrototype Then routine.abiName :+ "!"
		End If
		routine.returnType = externalRoutine.returnType
		routine.callableReturnType = externalRoutine.callableReturnType
		routine.callableReturnParameters = externalRoutine.callableReturnParameters
		routine.callableReturnCallingConvention = externalRoutine.callableReturnCallingConvention
		routine.callingConvention = externalRoutine.callingConvention
		routine.parameters = externalRoutine.parameters
		routine.visibility = VISIBILITY_PUBLIC
		routine.source = externalRoutine.source
		Return EmitRoutine(routine)
	End Method

	Method EmitExternalGlobal:String(externalGlobal:TCompilerIrExternalGlobal)
		Local variable:TCompilerIrVariableDeclaration = New TCompilerIrVariableDeclaration
		variable.name = externalGlobal.sourceName
		variable.abiName = externalGlobal.abiName
		variable.semanticType = externalGlobal.semanticType
		variable.callableReturnType = externalGlobal.callableReturnType
		variable.callableParameters = externalGlobal.callableParameters
		variable.callableCallingConvention = externalGlobal.callableCallingConvention
		variable.isThreadedGlobal = externalGlobal.isThreadedGlobal
		variable.source = externalGlobal.source
		Return EmitGlobal(variable)
	End Method

	Method DefaultSupported:Int(parameter:TCompilerIrParameter)
		Select parameter.defaultKind
			Case CONSTANT_VALUE_INTEGER, CONSTANT_VALUE_FLOAT
				Return parameter.defaultText.length > 0 And Not parameter.callableReturnType.length
			Case CONSTANT_VALUE_STRING
				Return parameter.semanticType = "String"
			Case CONSTANT_VALUE_CALLABLE
				Return parameter.callableReturnType.length > 0 And parameter.defaultCallableAbiName.length > 0
		End Select
		Return False
	End Method

	Method ParameterSupported:Int(parameter:TCompilerIrParameter)
		If Not parameter Then Return False
		If parameter.isStaticArray Then Return parameter.staticArrayLength > 0 And SupportsRoutineType(parameter.staticArrayElementType)
		If parameter.callableReturnType.length Then
			If Not SupportsRoutineType(parameter.callableReturnType) Then Return False
			For Local nested:TCompilerIrParameter = EachIn parameter.callableParameters
				If Not ParameterModeSupported(nested) Or Not ParameterSupported(nested) Then Return False
			Next
			Return True
		End If
		Return SupportsRoutineType(parameter.semanticType)
	End Method

	Method RoutineParameterSignature:String(parameter:TCompilerIrParameter)
		Local result:String
		If parameter.isStaticArray Then
			result = parameter.name + RoutineInterfaceType(parameter.staticArrayElementType) + "&[" + parameter.staticArrayLength + "]"
		Else If parameter.callableReturnType.length Then
			result = parameter.name + RoutineInterfaceType(parameter.callableReturnType) + "("
			For Local index:Int = 0 Until parameter.callableParameters.length
				If index Then result :+ ","
				result :+ RoutineParameterSignature(parameter.callableParameters[index])
			Next
			result :+ ")" + CallingConventionFlag(parameter.callableCallingConvention)
		Else
			result = parameter.name + RoutineInterfaceType(parameter.semanticType)
			If parameter.nativeStringEncoding = NATIVE_STRING_UTF8 Then result :+ "z"
			If parameter.nativeStringEncoding = NATIVE_STRING_UTF16 Then result :+ "w"
		End If
		If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
		If parameter.isOptional Then result :+ "=" + RoutineDefaultSignature(parameter)
		Return result
	End Method

	Method RoutineDefaultSupported:Int(parameter:TCompilerIrParameter)
		Return MemberDefaultSupported(parameter)
	End Method

	Method RoutineDefaultSignature:String(parameter:TCompilerIrParameter)
		Return MemberDefaultSignature(parameter)
	End Method

	Method SupportsRoutineType:Int(semanticType:String)
		Return SupportsMemberType(semanticType)
	End Method

	Method SupportsGlobalType:Int(semanticType:String)
		Return SupportsMemberType(semanticType)
	End Method

	Method GlobalParameterSupported:Int(parameter:TCompilerIrParameter)
		If Not parameter Then Return False
		If parameter.isStaticArray Then Return parameter.staticArrayLength > 0 And SupportsGlobalType(parameter.staticArrayElementType)
		If parameter.callableReturnType.length Then
			If Not SupportsGlobalType(parameter.callableReturnType) Then Return False
			For Local nested:TCompilerIrParameter = EachIn parameter.callableParameters
				If Not ParameterModeSupported(nested) Or Not GlobalParameterSupported(nested) Then Return False
			Next
			Return True
		End If
		Return SupportsGlobalType(parameter.semanticType)
	End Method

	Method RoutineInterfaceType:String(semanticType:String)
		If IsClosureType(semanticType) Then Return MemberInterfaceType(semanticType)
		If IsManagedArrayType(semanticType) Then Return MemberInterfaceType(semanticType)
		If semanticType.EndsWith(" Ptr") Then Return MemberInterfaceType(semanticType)
		Local irEnum:TCompilerIrEnum = EnumByType(semanticType)
		If irEnum Then Return "/" + irEnum.name
		Local irInterface:TCompilerIrInterface = InterfaceByType(semanticType)
		If irInterface Then
			If irInterface.isExternInterface Then Return "??" + irInterface.name
			If SameTypeName(irInterface.semanticType, semanticType) And irInterface.semanticType.Contains("<") Then Return ":" + irInterface.semanticType
			Return ":" + irInterface.name
		End If
		If SupportsNamedMemberType(semanticType) Then Return MemberInterfaceType(semanticType)
		Return InterfaceType(semanticType)
	End Method

	Method GlobalInterfaceType:String(semanticType:String)
		If IsClosureType(semanticType) Then Return MemberInterfaceType(semanticType)
		If IsManagedArrayType(semanticType) Then Return MemberInterfaceType(semanticType)
		If semanticType.EndsWith(" Ptr") Then Return MemberInterfaceType(semanticType)
		Local irEnum:TCompilerIrEnum = EnumByType(semanticType)
		If irEnum Then Return "/" + irEnum.name
		Local irInterface:TCompilerIrInterface = InterfaceByType(semanticType)
		If irInterface Then
			If irInterface.isExternInterface Then Return "??" + irInterface.name
			If SameTypeName(irInterface.semanticType, semanticType) And irInterface.semanticType.Contains("<") Then Return ":" + irInterface.semanticType
			Return ":" + irInterface.name
		End If
		If SupportsNamedMemberType(semanticType) Then Return MemberInterfaceType(semanticType)
		Return InterfaceType(semanticType)
	End Method

	Method InterfaceByType:TCompilerIrInterface(semanticType:String)
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If SameTypeName(irInterface.semanticType, semanticType) Or SameTypeName(irInterface.name, semanticType) Then Return irInterface
		Next
		Return Null
	End Method

	Function SameTypeName:Int(left:String, right:String)
		Return CompactTypeName(left) = CompactTypeName(right)
	End Function

	Function CompactTypeName:String(value:String)
		Return value.Replace(" ", "").Replace(Chr(9), "").ToLower()
	End Function

	Method EnumByType:TCompilerIrEnum(semanticType:String)
		For Local irEnum:TCompilerIrEnum = EachIn irModule.enums
			If irEnum.semanticType = semanticType Or irEnum.name = semanticType Then Return irEnum
		Next
		Return Null
	End Method

	Method InterfaceById:TCompilerIrInterface(interfaceId:String)
		For Local irInterface:TCompilerIrInterface = EachIn irModule.interfaces
			If irInterface.interfaceId = interfaceId Then Return irInterface
		Next
		Return Null
	End Method

	Function InterfaceSource:TCompilerSourceLocation(irInterface:TCompilerIrInterface)
		If irInterface Then Return irInterface.source
		Return Null
	End Function

	Function EnumSource:TCompilerSourceLocation(irEnum:TCompilerIrEnum)
		If irEnum Then Return irEnum.source
		Return Null
	End Function

	Method ParameterSignature:String(parameter:TCompilerIrParameter)
		Local result:String
		If parameter.isStaticArray Then
			result = parameter.name + InterfaceType(parameter.staticArrayElementType) + "&[" + parameter.staticArrayLength + "]"
		Else If parameter.callableReturnType.length Then
			result = parameter.name + InterfaceType(parameter.callableReturnType) + "("
			For Local index:Int = 0 Until parameter.callableParameters.length
				If index Then result :+ ","
				result :+ ParameterSignature(parameter.callableParameters[index])
			Next
			result :+ ")" + CallingConventionFlag(parameter.callableCallingConvention)
		Else
			result = parameter.name + InterfaceType(parameter.semanticType)
			If parameter.nativeStringEncoding = NATIVE_STRING_UTF8 Then result :+ "z"
			If parameter.nativeStringEncoding = NATIVE_STRING_UTF16 Then result :+ "w"
		End If
		If parameter.isOptional Then result :+ "=" + DefaultSignature(parameter)
		Return result
	End Method

	Method DefaultSignature:String(parameter:TCompilerIrParameter)
		Select parameter.defaultKind
			Case CONSTANT_VALUE_INTEGER, CONSTANT_VALUE_FLOAT
				Return parameter.defaultText + InterfaceType(parameter.semanticType)
			Case CONSTANT_VALUE_STRING
				Return "$" + QuotedConstantString(parameter.defaultStringValue)
			Case CONSTANT_VALUE_CALLABLE
				Return Quoted(parameter.defaultCallableAbiName)
		End Select
		Return ""
	End Method

	Method EmitGlobal:String(variable:TCompilerIrVariableDeclaration)
		Local signature:String = variable.name
		If variable.arrayCallableReturnType.length Then
			signature :+ GlobalCallableArrayInterfaceType(variable.arrayCallableReturnType, variable.arrayCallableParameters, variable.arrayCallableRank, variable.arrayCallableCallingConvention)
		Else If variable.callableReturnType.length Then
			signature :+ GlobalInterfaceType(variable.callableReturnType) + "("
			For Local index:Int = 0 Until variable.callableParameters.length
				If index Then signature :+ ","
				signature :+ GlobalParameterSignature(variable.callableParameters[index])
			Next
			signature :+ ")" + CallingConventionFlag(variable.callableCallingConvention)
		Else
			signature :+ GlobalInterfaceType(variable.semanticType)
		End If
		Return signature + "&=mem:p(" + Quoted(variable.abiName) + ")" + SourceSuffix(variable.source)
	End Method

	Method GlobalCallableArrayInterfaceType:String(returnType:String, parameters:TCompilerIrParameter[], rank:Int, callingConvention:String = "c")
		Local result:String = GlobalInterfaceType(returnType) + "("
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ","
			result :+ GlobalParameterSignature(parameters[index])
		Next
		result :+ ")" + CallingConventionFlag(callingConvention) + "&["
		For Local index:Int = 1 Until rank
			result :+ ","
		Next
		Return result + "]"
	End Method

	Method GlobalParameterSignature:String(parameter:TCompilerIrParameter)
		Local result:String
		If parameter.isStaticArray Then
			result = parameter.name + GlobalInterfaceType(parameter.staticArrayElementType) + "&[" + parameter.staticArrayLength + "]"
		Else If parameter.callableReturnType.length Then
			result = parameter.name + GlobalInterfaceType(parameter.callableReturnType) + "("
			For Local index:Int = 0 Until parameter.callableParameters.length
				If index Then result :+ ","
				result :+ GlobalParameterSignature(parameter.callableParameters[index])
			Next
			result :+ ")" + CallingConventionFlag(parameter.callableCallingConvention)
		Else
			result = parameter.name + GlobalInterfaceType(parameter.semanticType)
		End If
		If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
		Return result
	End Method

	Function ParameterModeSupported:Int(parameter:TCompilerIrParameter)
		If Not parameter Then Return False
		If parameter.passingMode = PARAMETER_PASS_VALUE Then Return True
		Return parameter.passingMode = PARAMETER_PASS_VAR And Not parameter.isStaticArray And Not parameter.callableReturnType.length
	End Function

	Function CallingConventionFlag:String(callingConvention:String)
		If callingConvention.ToLower() = "stdcall" Then Return "W"
		Return ""
	End Function

	Method SourceSuffix:String(source:TCompilerSourceLocation)
		If Not source Or Not source.path.length Or Not source.span Then Return ""
		Local text:TSourceText = SourceText(source.path)
		If Not text Then Return ""
		Local position:TSourcePosition = text.Position(source.span.start)
		Return " '@source " + Quoted(source.path.Replace(Chr(92), "/")) + "," + (position.line + 1) + "," + position.column
	End Method

	Method SourceText:TSourceText(path:String)
		If analysis And analysis.snapshot Then
			For Local document:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If document And document.path = path And document.tree Then Return document.tree.source
			Next
		End If
		If analysis And analysis.syntaxTree And analysis.syntaxTree.source.path = path Then Return analysis.syntaxTree.source
		Return Null
	End Method

	Method AddDiagnostic(code:String, message:String, source:TCompilerSourceLocation)
		If source Then
			diagnostics :+ [TCompilerDiagnostic.Create(code, message, source.path, source.span, source.line, source.column)]
		Else
			diagnostics :+ [TCompilerDiagnostic.Create(code, message)]
		End If
	End Method

	Function SupportsType:Int(semanticType:String)
		Select semanticType
			Case "Void", "Byte", "Short", "Int", "UInt", "Long", "ULong", "LongInt", "ULongInt", "Size_T", "WParam", "LParam", "Float", "Double", "Float64", "Int128", "Float128", "Double128", "String"
				Return True
		End Select
		If semanticType.EndsWith(" Ptr") Then Return SupportsType(semanticType[..semanticType.length - 4])
		Return False
	End Function

	Function IsClosureType:Int(semanticType:String)
		Local value:String = semanticType.Trim().ToLower()
		Return value.StartsWith("closure<") And value.EndsWith(">")
	End Function

	Function InterfaceType:String(semanticType:String)
		If semanticType.EndsWith(" Ptr") Then Return InterfaceType(semanticType[..semanticType.length - 4]) + "*"
		Select semanticType
			Case "Void" Return ""
			Case "Byte" Return "@"
			Case "Short" Return "@@"
			Case "Int" Return "%"
			Case "UInt" Return "|"
			Case "Long" Return "%%"
			Case "ULong" Return "||"
			Case "LongInt" Return "%v"
			Case "ULongInt" Return "%e"
			Case "Size_T" Return "%z"
			Case "WParam" Return "%w"
			Case "LParam" Return "%x"
			Case "Float" Return "#"
			Case "Double" Return "!"
			Case "Float64" Return "!h"
			Case "Int128" Return "%j"
			Case "Float128" Return "!k"
			Case "Double128" Return "!m"
			Case "String" Return "$"
		End Select
		Return ""
	End Function

	Function Quoted:String(value:String)
		Return Chr(34) + EscapeQuoted(value, False) + Chr(34)
	End Function

	Function QuotedConstantString:String(value:String)
		Return Chr(34) + EscapeQuoted(value, True) + Chr(34)
	End Function

	Function EscapeQuoted:String(value:String, escapeUnicode:Int)
		Local result:String
		For Local index:Int = 0 Until value.length
			Local code:Int = value[index]
			Select code
				Case 126
					result :+ "~~~~"
				Case 34
					result :+ "~~q"
				Case 10
					result :+ "~~n"
				Case 13
					result :+ "~~r"
				Case 9
					result :+ "~~t"
				Case 0
					result :+ "~~0"
				Default
					If escapeUnicode And code > 127 Then
						result :+ "~~" + code + "~~"
					Else
						result :+ Chr(code)
					End If
			End Select
		Next
		Return result
	End Function

	Function CallableName:String(value:String)
		If Not value.length Then Return Quoted(value)
		For Local index:Int = 0 Until value.length
			Local char:Int = value[index]
			If Not ((char >= Asc("a") And char <= Asc("z")) Or (char >= Asc("A") And char <= Asc("Z")) Or (char >= Asc("0") And char <= Asc("9")) Or char = Asc("_")) Then Return Quoted(value)
		Next
		Return value
	End Function
End Type
