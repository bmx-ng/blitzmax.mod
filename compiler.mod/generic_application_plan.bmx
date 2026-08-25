' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.StringBuilder
Import Collections.StringMap
Import BlitzMax.Language
Import "compiler_diagnostic.bmx"
Import "compiler_options.bmx"
Import "generic_specialization.bmx"

Const COMPILER_GENERIC_LANGUAGE_LINKAGE_REVISION:String = "bmx-language-1"
Const COMPILER_GENERIC_IR_REVISION:String = "compiler-ir-1"
Const COMPILER_GENERIC_RUNTIME_ABI_REVISION:String = "blitzmax-ng-runtime-1"
Const COMPILER_GENERIC_BACKEND_REVISION:String = "bcc2-c-2"

Type TCompilerGenericUnit
	Field specialization:TGenericSpecializationNode
	Field ir:TCompilerGenericSpecializationIr
	Field declarations:String
	Field applicationDeclarations:String
	Field implementation:String
End Type

' Build-scoped immutable backend text. Keys are finalized only after the
' transitive specialization revision closure is known.
Type TCompilerGenericBackendUnitCacheEntry
	Field specializationIdentity:String
	Field declarations:String
	Field applicationDeclarations:String
	Field implementation:String
End Type

Type TCompilerGenericBackendUnitCache
	Field entries:TStringMap = New TStringMap
	Field hits:Long
	Field misses:Long

	Method Find:TCompilerGenericBackendUnitCacheEntry(cacheKey:String, specializationIdentity:String)
		Local entry:TCompilerGenericBackendUnitCacheEntry = TCompilerGenericBackendUnitCacheEntry(entries.ValueForKey(cacheKey))
		If entry And entry.specializationIdentity = specializationIdentity Then
			hits :+ 1
			Return entry
		End If
		misses :+ 1
		Return Null
	End Method

	Method Add(cacheKey:String, specializationIdentity:String, declarations:String, applicationDeclarations:String, implementation:String)
		Local entry:TCompilerGenericBackendUnitCacheEntry = New TCompilerGenericBackendUnitCacheEntry
		entry.specializationIdentity = specializationIdentity
		entry.declarations = declarations
		entry.applicationDeclarations = applicationDeclarations
		entry.implementation = implementation
		entries.Insert(cacheKey, entry)
	End Method
End Type

Type TCompilerGenericLinkInput
	Field specializationIdentity:String
	Field sourcePath:String
	Field objectPath:String
	Field cacheKey:String
End Type

Type TCompilerGenericTemplateOutput
	Field artifact:TGenericTemplateArtifact
	Field artifactReference:String
	Field content:String
	Field isPublished:Int
End Type

Type TCompilerGenericApplicationPlan
	Field registry:TGenericSpecializationRegistry
	Field units:TCompilerGenericUnit[] = New TCompilerGenericUnit[0]
	Field linkInputs:TCompilerGenericLinkInput[] = New TCompilerGenericLinkInput[0]
	Field templateOutputs:TCompilerGenericTemplateOutput[] = New TCompilerGenericTemplateOutput[0]
	Field specializedSourceSymbols:TMap = New TMap
	' Ordinary source Types used as closed generic arguments cross from the
	' application unit into a separate specialization unit. Retain the stable
	' runtime ABI selected while canonicalizing that argument so IR lowering
	' emits the owning descriptor with the same external identity.
	Field runtimeArgumentSymbols:TMap = New TMap
	' Physical generated-header owners for ordinary Struct arguments declared
	' in quoted application sources. Canonical type identity remains the
	' application identity; this map only guides C layout includes.
	Field runtimeStructSourceUnits:TStringMap = New TStringMap
	' Private Globals referenced by separately emitted source specializations
	' retain language privacy but require stable external C linkage between the
	' owning source unit and its specialization unit.
	Field specializationGlobalAbis:TMap = New TMap
	' Ordinary private routines referenced by a source-free specialization need
	' an externally visible, deterministic C identity even though they remain
	' private in the BlitzMax language.  The template records that identity and
	' IR lowering applies it only to the owning source routine.
	Field specializationRoutineAbis:TMap = New TMap
	Field declarations:String
	Field manifest:String
	Field publishMilliseconds:Int
	Field indexMilliseconds:Int
	Field discoveryMilliseconds:Int
	Field expansionMilliseconds:Int
	Field cycleValidationMilliseconds:Int
	Field unitLoweringMilliseconds:Int
	Field manifestMilliseconds:Int
	Field specializationIrMilliseconds:Int
	Field declarationEmissionMilliseconds:Int
	Field implementationEmissionMilliseconds:Int
	Field applicationDeclarationMilliseconds:Int
	Field nodeCount:Int
	Field edgeCount:Int
	Field requestCount:Int

	Method HasSpecializations:Int()
		Return registry And registry.nodes.length > 0
	End Method
End Type

Type TCompilerLegacyGenericInterfaceBridge
	Function Build:TGenericTemplateArtifact(model:TSemanticModel, symbol:TSymbol, languageLinkageRevision:String, diagnostics:String[] Var)
		If Not model Or Not symbol Or Not symbol.isImported Or symbol.kind <> SYMBOL_INTERFACE Or Not symbol.interfaceRecord Then
			diagnostics :+ ["BMXC3041 legacy generic Interface bridge requires an imported semantic Interface declaration"]
			Return Null
		End If
		' A legacy Interface has no implementation body. Its compact semantic
		' declaration and member table are therefore sufficient to construct a
		' body-free canonical contract without reading or retaining its G blob.
		Return TCompilerGenericTemplateBuilder.Build(model, symbol, symbol.originModule, languageLinkageRevision, diagnostics)
	End Function
End Type

Type TCompilerGenericApplicationPlanner
	Field analysis:TLanguageAnalysis
	Field options:TCompilerOptions
	Field plan:TCompilerGenericApplicationPlan
	Field artifactsBySymbol:TMap = New TMap
	Field symbolsByArtifact:TMap = New TMap
	Field artifactsByReference:TStringMap = New TStringMap
	Field backendUnitCache:TCompilerGenericBackendUnitCache
	Field diagnostics:TCompilerDiagnostic[] = New TCompilerDiagnostic[0]
	Field expansionLimitExceeded:Int
	Field discoveredScopes:TMap = New TMap
	Field sourceSyntaxNodes:TMap = New TMap

	Function Build:TCompilerGenericApplicationPlan(analysis:TLanguageAnalysis, options:TCompilerOptions, diagnostics:TCompilerDiagnostic[] Var, backendUnitCache:TCompilerGenericBackendUnitCache = Null)
		Local planner:TCompilerGenericApplicationPlanner = New TCompilerGenericApplicationPlanner
		planner.analysis = analysis
		planner.options = options
		planner.backendUnitCache = backendUnitCache
		planner.plan = New TCompilerGenericApplicationPlan
		planner.plan.registry = TGenericSpecializationRegistry.Create(planner.Configuration())
		If analysis And analysis.model Then
			Local started:Int = MilliSecs()
			planner.PublishSourceTemplates()
			planner.plan.publishMilliseconds = MilliSecs() - started
			started = MilliSecs()
			planner.IndexTemplateArtifacts(analysis.model.globalScope)
			planner.plan.indexMilliseconds = MilliSecs() - started
			started = MilliSecs()
			planner.IndexSourceSyntaxNodes()
			planner.DiscoverScope(analysis.model.globalScope)
			planner.DiscoverTypeMap()
			planner.DiscoverExpressionMap()
			planner.DiscoverRoutineCalls()
			planner.plan.discoveryMilliseconds = MilliSecs() - started
		End If
		If planner.plan.registry.nodes.length Then
			Local started:Int = MilliSecs()
			planner.ExpandTransitiveRequests()
			planner.plan.expansionMilliseconds = MilliSecs() - started
			planner.plan.registry.FinalizeOrdering()
			started = MilliSecs()
			planner.plan.registry.ValidateCycles()
			planner.plan.cycleValidationMilliseconds = MilliSecs() - started
			planner.AssignApplicationSourceUnitOwnership()
			planner.plan.registry.FinalizeCacheKeys()
			planner.TranslateRegistryDiagnostics()
			started = MilliSecs()
			planner.LowerUnits()
			planner.plan.unitLoweringMilliseconds = MilliSecs() - started
			started = MilliSecs()
			planner.plan.manifest = planner.plan.registry.Manifest()
			planner.plan.manifestMilliseconds = MilliSecs() - started
		Else
			planner.plan.manifest = "generic-specializations " + GENERIC_SPECIALIZATION_MANIFEST_VERSION + "~n"
		End If
		planner.RecordGraphCounts()
		diagnostics = planner.diagnostics
		Return planner.plan
	End Function

	Method IndexSourceSyntaxNodes()
		If Not analysis Or Not analysis.snapshot Then Return
		For Local document:TSourceDocumentModel = EachIn analysis.snapshot.documents
			If Not document Or Not document.tree Then Continue
			Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(document.tree)
			If Not navigator Then Continue
			For Local node:TSyntaxNode = EachIn navigator.nodes
				sourceSyntaxNodes.Insert(node, node)
			Next
		Next
	End Method

	Method RecordGraphCounts()
		If Not plan Or Not plan.registry Then Return
		plan.nodeCount = plan.registry.nodes.length
		For Local node:TGenericSpecializationNode = EachIn plan.registry.nodes
			If Not node Then Continue
			plan.edgeCount :+ node.outgoing.length
			plan.requestCount :+ node.requests.length
		Next
	End Method

	Method AssignApplicationSourceUnitOwnership()
		If Not options Or Not options.applicationBuild Or Not options.applicationIdentity.length Then Return
		For Local node:TGenericSpecializationNode = EachIn plan.registry.nodes
			If Not node Or Not node.artifact Or Not node.artifact.identity Then Continue
			node.runtimeStructSourceUnits = plan.runtimeStructSourceUnits
			If node.artifact.identity.moduleName.ToLower() <> options.applicationIdentity.ToLower() Then Continue
			node.applicationSourceOwned = True
			Local symbol:TSymbol = TSymbol(symbolsByArtifact.ValueForKey(node.artifact))
			If Not symbol Or Not symbol.originPath.length Then Continue
			' Imported declarations from a quoted source retain the generated .i
			' path as provenance. Map that spelling back to its physical .bmx unit
			' before deriving the sibling generated-header path.
			Local sourceUnitPath:String = ApplicationSourceUnitPath(TCompilationSnapshotBuilder.InterfaceSourcePath(symbol.originPath))
			If sourceUnitPath.length And sourceUnitPath.ToLower() <> PrimaryApplicationSourceUnitPath().ToLower() Then node.definingSourceUnitPath = sourceUnitPath
		Next
	End Method

	Method PrimaryApplicationSourceUnitPath:String()
		If options And options.sourceUnitPath.length Then Return options.sourceUnitPath.Replace("\", "/")
		If analysis And analysis.snapshot And analysis.snapshot.rootDocument Then Return StripDir(analysis.snapshot.rootDocument.path.Replace("\", "/"))
		Return ""
	End Method

	Method ApplicationSourceUnitPath:String(sourcePath:String)
		If Not sourcePath.length Or Not analysis Or Not analysis.snapshot Or Not analysis.snapshot.rootDocument Then Return ""
		Local rootPath:String = analysis.snapshot.rootDocument.path.Replace("\", "/")
		Local rootUnitPath:String = PrimaryApplicationSourceUnitPath()
		If Not rootUnitPath.length Then Return ""
		While rootUnitPath.StartsWith("./")
			rootUnitPath = rootUnitPath[2..]
		Wend
		If Not rootPath.ToLower().EndsWith(rootUnitPath.ToLower()) Then Return ""
		Local sourceRoot:String = rootPath[..rootPath.length - rootUnitPath.length]
		Local normalizedSourcePath:String = sourcePath.Replace("\", "/")
		If Not normalizedSourcePath.ToLower().StartsWith(sourceRoot.ToLower()) Then Return ""
		Local result:String = normalizedSourcePath[sourceRoot.length..]
		While result.StartsWith("/")
			result = result[1..]
		Wend
		Return result
	End Method

	Method PublishSourceTemplates()
		If Not analysis Or Not analysis.model Or Not analysis.model.globalScope Then Return
		PublishSourceTemplateScope(analysis.model.globalScope)
	End Method

	Method PublishSourceTemplateScope(scope:TScope)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not IsTemplateSymbol(symbol) Or symbol.isImported Then Continue
			Local artifact:TGenericTemplateArtifact = ArtifactFor(symbol)
			If Not artifact Then Continue
			Local encodeDiagnostics:String[]
			Local content:String = TGenericTemplateArtifactCodec.FinalizeAndEncode(artifact, encodeDiagnostics)
			For Local message:String = EachIn encodeDiagnostics
				AddMessageDiagnostic(message, symbol.declaration)
			Next
			If encodeDiagnostics.length Then Continue
			Local output:TCompilerGenericTemplateOutput = New TCompilerGenericTemplateOutput
			output.artifact = artifact
			output.artifactReference = GENERIC_SPECIALIZATION_OUTPUT_DIRECTORY + "/templates/" + artifact.EffectiveContentRevision() + ".bmxgt"
			output.content = content
			output.isPublished = symbol.visibility = VISIBILITY_PUBLIC And analysis.model.moduleName.length > 0
			plan.templateOutputs :+ [output]
		Next
		For Local child:TScope = EachIn scope.children
			PublishSourceTemplateScope(child)
		Next
	End Method

	Method IndexTemplateArtifacts(scope:TScope)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not IsTemplateSymbol(symbol) Then Continue
			' Legacy SDK snapshots may expose unrelated open generic
			' declarations without canonical companions. Index only supplied
			' imported artifacts; a request for a missing one is diagnosed
			' lazily by ArtifactFor.
			If symbol.isImported And Not symbol.genericTemplateArtifact And symbol.kind <> SYMBOL_INTERFACE Then Continue
			Local artifact:TGenericTemplateArtifact = ArtifactFor(symbol)
			If Not artifact Or Not artifact.identity Then Continue
			artifactsByReference.Insert(ArtifactReferenceKey(artifact.identity.moduleName, artifact.identity.qualifiedName, artifact.identity.signatureKey), artifact)
			' A quoted source import may expose its relative import token as the
			' semantic origin module while its canonical artifact is owned by the
			' normalized source path. Index both spellings, then canonicalize any
			' resolved reference before it enters a specialization key.
			If symbol.isImported And symbol.originModule.length Then artifactsByReference.Insert(ArtifactReferenceKey(symbol.originModule, artifact.identity.qualifiedName, artifact.identity.signatureKey), artifact)
			If symbol.isImported And symbol.originPath.length Then artifactsByReference.Insert(ArtifactReferenceKey("source:" + symbol.originPath.Replace("\", "/"), artifact.identity.qualifiedName, artifact.identity.signatureKey), artifact)
			' Source-local named references do not carry a module name. The
			' qualified fallback is safe inside one analyzed semantic universe.
			' Imported templates must retain their defining module here: an SDK
			' contract such as IIterator<T> may coexist with an unrelated local
			' declaration of the same qualified name.
			If Not symbol.isImported Then artifactsByReference.Insert(ArtifactReferenceKey("", artifact.identity.qualifiedName, artifact.identity.signatureKey), artifact)
		Next
		For Local child:TScope = EachIn scope.children
			IndexTemplateArtifacts(child)
		Next
	End Method

	Function IsTemplateSymbol:Int(symbol:TSymbol)
		If Not symbol Then Return False
		If symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_INTERFACE Or symbol.kind = SYMBOL_STRUCT Then Return GenericTypeArity(symbol) > 0
		If symbol.kind = SYMBOL_ROUTINE Then
			If symbol.genericArity <= 0 Then Return False
			If symbol.isImported Then Return symbol.interfaceRecord And (symbol.interfaceRecord.kind = INTERFACE_RECORD_FUNCTION Or symbol.interfaceRecord.kind = INTERFACE_RECORD_METHOD Or symbol.interfaceRecord.kind = INTERFACE_RECORD_TYPE_FUNCTION)
			Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
			If Not declaration Then Return False
			If Not declaration.isMethod Then Return True
			If Not symbol.containingScope Or Not symbol.containingScope.owner Then Return False
			Local owner:TSymbol = symbol.containingScope.owner
			Return owner.kind = SYMBOL_TYPE Or owner.kind = SYMBOL_STRUCT Or owner.kind = SYMBOL_INTERFACE
		End If
		Return False
	End Function

	Method ExpandTransitiveRequests()
		While True
			While True
				Local sourceNode:TGenericSpecializationNode
				For Local candidate:TGenericSpecializationNode = EachIn plan.registry.nodes
					If candidate.processedRequiredMethodRevision <> candidate.requiredMethodRevision Then sourceNode = candidate; Exit
				Next
				If Not sourceNode Then Exit
				sourceNode.processedRequiredMethodRevision = sourceNode.requiredMethodRevision
				If Not sourceNode Or sourceNode.state = GENERIC_SPECIALIZATION_FAILED Then Continue
				If sourceNode.IsAbiReferenceOnly() Then Continue
				If sourceNode.artifact.containingType Then ExpandTypeReference(sourceNode, sourceNode.artifact.containingType, Null, GENERIC_REQUEST_TRANSITIVE)
				If sourceNode.artifact.baseType Then
					ExpandTypeReference(sourceNode, sourceNode.artifact.baseType.semanticType, sourceNode.artifact.baseType.source, GENERIC_REQUEST_INHERITANCE)
				End If
				For Local interfaceReference:TGenericTemplateInheritanceReference = EachIn sourceNode.artifact.interfaces
					If interfaceReference Then ExpandTypeReference(sourceNode, interfaceReference.semanticType, interfaceReference.source, GENERIC_REQUEST_INTERFACE)
				Next
				ClassifyDeferredMethods(sourceNode)
				For Local member:TGenericTemplateMember = EachIn sourceNode.artifact.members
					Local memberTypeReason:Int = GENERIC_REQUEST_ABI_REFERENCE
					If member.kind = TEMPLATE_MEMBER_FIELD Then
						memberTypeReason = GENERIC_REQUEST_LAYOUT
						' A managed field pointing at a strictly larger form of its own
						' class is pointer-shaped recursive storage. It needs the target
						' declaration, but eagerly materializing that target repeats the
						' field forever. Unrelated generic fields retain ordinary transitive
						' materialization. Struct fields remain by-value layout requests.
						If sourceNode.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_CLASS And TypeReferenceExpandsOwningType(sourceNode, member.semanticType) Then memberTypeReason = GENERIC_REQUEST_ABI_REFERENCE
					End If
					ExpandTypeReference(sourceNode, member.semanticType, member.source, memberTypeReason)
					For Local parameter:TGenericTemplateValueParameter = EachIn member.parameters
						ExpandTypeReference(sourceNode, parameter.semanticType, parameter.source, memberTypeReason)
					Next
					Local expandBody:Int = True
					If member.kind = TEMPLATE_MEMBER_METHOD And member.name.ToLower() <> "new" Then
						Local methodSignature:String = ClosedMemberMethodSignature(sourceNode, member)
						If sourceNode.IsMethodDeferred(methodSignature) And Not sourceNode.IsMethodRequired(methodSignature) Then expandBody = False
					End If
					If expandBody Then ExpandNodeReferences(sourceNode, member.body, member.kind = TEMPLATE_MEMBER_FIELD And member.isStatic)
				Next
				ExpandNodeReferences(sourceNode, sourceNode.artifact.body)
			Wend
			Local nodeCount:Int = plan.registry.nodes.length
			For Local dispatcher:TGenericSpecializationNode = EachIn plan.registry.nodes
				If dispatcher.artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Continue
				If dispatcher.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then
					ExpandInterfaceMethodImplementations(dispatcher)
				Else If dispatcher.artifact.isMethod And Not dispatcher.artifact.members[0].body Then
					ExpandAbstractMethodImplementations(dispatcher)
				End If
			Next
			If plan.registry.nodes.length = nodeCount Then Exit
		Wend
		For Local dispatcher:TGenericSpecializationNode = EachIn plan.registry.nodes
			If dispatcher.artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Continue
			If dispatcher.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Or (dispatcher.artifact.isMethod And Not dispatcher.artifact.members[0].body) Then DiagnoseMissingInterfaceMethodImplementation(dispatcher)
		Next
	End Method

	Method ClosedMemberMethodSignature:String(sourceNode:TGenericSpecializationNode, member:TGenericTemplateMember)
		If Not sourceNode Or Not member Then Return ""
		Local routine:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
		routine.name = member.name
		routine.returnType = TTemplateTypeSubstitution.Apply(member.semanticType, sourceNode.key.typeArguments)
		routine.parameters = TCompilerGenericSpecializationLowerer.SubstituteParameters(member.parameters, sourceNode.key.typeArguments)
		Return TCompilerGenericSpecializationLowerer.MethodSignatureKey(routine)
	End Method

	Method ClassifyDeferredMethods(sourceNode:TGenericSpecializationNode)
		If Not sourceNode Or Not sourceNode.artifact Or sourceNode.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then Return
		For Local member:TGenericTemplateMember = EachIn sourceNode.artifact.members
			If member.kind = TEMPLATE_MEMBER_METHOD And member.name.ToLower() <> "new" And MethodBodyExpandsOwningType(sourceNode, member.body) Then sourceNode.DeferMethod(ClosedMemberMethodSignature(sourceNode, member))
		Next
		Local changed:Int = True
		While changed
			changed = False
			For Local member:TGenericTemplateMember = EachIn sourceNode.artifact.members
				If member.kind <> TEMPLATE_MEMBER_METHOD Or member.name.ToLower() = "new" Then Continue
				Local signatureKey:String = ClosedMemberMethodSignature(sourceNode, member)
				If sourceNode.IsMethodDeferred(signatureKey) Then Continue
				If NodeCallsDeferredOwnerMethod(sourceNode, member.body) Then
					sourceNode.DeferMethod(signatureKey)
					changed = True
				End If
			Next
		Wend
	End Method

	Method NodeCallsDeferredOwnerMethod:Int(sourceNode:TGenericSpecializationNode, node:TGenericTemplateNode)
		If Not sourceNode Or Not node Then Return False
		If node.kind = TEMPLATE_NODE_CALL And node.children.length And node.children[0].kind <> TEMPLATE_NODE_BLOCK Then
			Local receiver:TTemplateTypeReference = ClosedForSource(sourceNode, node.children[0].semanticType)
			QualifyClosedTypeReference(receiver)
			If receiver And TCompilerGenericSpecializationLowerer.SpecializationMatchesType(sourceNode, receiver) Then
				For Local member:TGenericTemplateMember = EachIn sourceNode.artifact.members
					If member.kind <> TEMPLATE_MEMBER_METHOD Or member.name.ToLower() <> node.valueText.ToLower() Then Continue
					Local signatureKey:String = ClosedMemberMethodSignature(sourceNode, member)
					If sourceNode.IsMethodDeferred(signatureKey) And TemplateCallMatchesMember(sourceNode, node, sourceNode, member) Then Return True
				Next
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			If NodeCallsDeferredOwnerMethod(sourceNode, child) Then Return True
		Next
		Return False
	End Method

	Method MethodBodyExpandsOwningType:Int(sourceNode:TGenericSpecializationNode, body:TGenericTemplateNode)
		If Not sourceNode Or Not body Or sourceNode.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then Return False
		Return NodeExpandsLargerOwningType(sourceNode, body)
	End Method

	Method NodeExpandsLargerOwningType:Int(sourceNode:TGenericSpecializationNode, node:TGenericTemplateNode)
		If Not node Then Return False
		Local expandsNodeType:Int = node.kind <> TEMPLATE_NODE_SELF And node.kind <> TEMPLATE_NODE_RETURN
		If node.kind = TEMPLATE_NODE_LITERAL And node.valueText.ToLower() = "null" Then expandsNodeType = False
		If node.kind = TEMPLATE_NODE_CONVERSION And node.children.length = 1 And node.children[0].kind = TEMPLATE_NODE_LITERAL And node.children[0].valueText.ToLower() = "null" Then expandsNodeType = False
		If expandsNodeType And TypeReferenceExpandsOwningType(sourceNode, node.semanticType) Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If NodeExpandsLargerOwningType(sourceNode, child) Then Return True
		Next
		Return False
	End Method

	Method TypeReferenceExpandsOwningType:Int(sourceNode:TGenericSpecializationNode, value:TTemplateTypeReference)
		If Not sourceNode Or Not value Then Return False
		Local closed:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(value, sourceNode.key.typeArguments)
		QualifyClosedTypeReference(closed)
		Return ClosedTypeReferenceExpandsOwningType(sourceNode, closed)
	End Method

	Method ClosedTypeReferenceExpandsOwningType:Int(sourceNode:TGenericSpecializationNode, value:TTemplateTypeReference)
		If Not sourceNode Or Not value Then Return False
		If value.kind = TEMPLATE_TYPE_NAMED And value.arguments.length Then
			Local artifact:TGenericTemplateArtifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey(value.moduleName, value.symbolName)))
			If Not artifact Then artifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey("", value.symbolName)))
			If artifact And artifact.identity.StableName() = sourceNode.artifact.identity.StableName() And TypeArgumentsStrictlyGrow(sourceNode.key.typeArguments, value.arguments) Then Return True
		End If
		If ClosedTypeReferenceExpandsOwningType(sourceNode, value.elementType) Then Return True
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			If ClosedTypeReferenceExpandsOwningType(sourceNode, argument) Then Return True
		Next
		Return False
	End Method

	Function TypeArgumentsStrictlyGrow:Int(current:TTemplateTypeReference[], expanded:TTemplateTypeReference[])
		If TypeReferencesComplexity(expanded) <= TypeReferencesComplexity(current) Then Return False
		For Local expandedArgument:TTemplateTypeReference = EachIn expanded
			For Local currentArgument:TTemplateTypeReference = EachIn current
				If currentArgument And TypeReferenceContainsCanonical(expandedArgument, currentArgument.CanonicalName()) Then Return True
			Next
		Next
		Return False
	End Function

	Function TypeReferencesComplexity:Int(values:TTemplateTypeReference[])
		Local result:Int
		For Local value:TTemplateTypeReference = EachIn values
			result :+ TypeReferenceComplexity(value)
		Next
		Return result
	End Function

	Function TypeReferenceComplexity:Int(value:TTemplateTypeReference)
		If Not value Then Return 0
		Local result:Int = 1 + TypeReferenceComplexity(value.elementType)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			result :+ TypeReferenceComplexity(argument)
		Next
		Return result
	End Function

	Function TypeReferenceContainsCanonical:Int(value:TTemplateTypeReference, canonicalName:String)
		If Not value Then Return False
		If value.CanonicalName() = canonicalName Then Return True
		If TypeReferenceContainsCanonical(value.elementType, canonicalName) Then Return True
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			If TypeReferenceContainsCanonical(argument, canonicalName) Then Return True
		Next
		Return False
	End Function

	Method ExpandAbstractMethodImplementations(sourceNode:TGenericSpecializationNode)
		If Not sourceNode Or Not sourceNode.artifact Then Return
		Local requirement:TSymbol = TSymbol(symbolsByArtifact.ValueForKey(sourceNode.artifact))
		If Not requirement Or Not requirement.containingScope Or Not requirement.containingScope.owner Then
			AddTemplateDiagnostic("BMXC3082", "closed abstract generic method has no semantic requirement symbol", sourceNode.artifact.members[0].source)
			Return
		End If
		CollectAbstractMethodImplementations(analysis.model.globalScope, sourceNode, requirement, requirement.containingScope.owner)
	End Method

	Method CollectAbstractMethodImplementations(scope:TScope, sourceNode:TGenericSpecializationNode, requirement:TSymbol, abstractOwner:TSymbol)
		If Not scope Then Return
		For Local typeSymbol:TSymbol = EachIn scope.declaredSymbols
			If Not typeSymbol Or typeSymbol.kind <> SYMBOL_TYPE Or typeSymbol.isAbstract Then Continue
			Local inheritedOwner:TNamedSemanticType = InheritedOwnerType(TNamedSemanticType(typeSymbol.declaredType), abstractOwner, 0)
			If Not inheritedOwner Then Continue
			Local implementation:TSymbol = ConcreteGenericInterfaceMethod(typeSymbol, requirement, inheritedOwner, 0)
			If Not implementation Then Continue
			Local artifact:TGenericTemplateArtifact = ArtifactFor(implementation)
			If Not artifact Then Continue
			Local ignoredCount:Int
			If GenericTypeArity(typeSymbol) Then
				For Local ownerNode:TGenericSpecializationNode = EachIn plan.registry.nodes
					If SpecializationOwnsType(ownerNode, typeSymbol) Then AddMethodImplementation(sourceNode, artifact, ownerNode.key.typeArguments, ignoredCount, GENERIC_REQUEST_ABSTRACT_METHOD_IMPLEMENTATION)
				Next
			Else
				AddMethodImplementation(sourceNode, artifact, New TTemplateTypeReference[0], ignoredCount, GENERIC_REQUEST_ABSTRACT_METHOD_IMPLEMENTATION)
			End If
		Next
		For Local child:TScope = EachIn scope.children
			CollectAbstractMethodImplementations(child, sourceNode, requirement, abstractOwner)
		Next
	End Method

	Method InheritedOwnerType:TNamedSemanticType(current:TNamedSemanticType, ownerSymbol:TSymbol, depth:Int)
		If depth > 64 Or Not current Or Not current.symbol Then Return Null
		If current.symbol = ownerSymbol Then Return current
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(current.symbol)
		If Not info Then Return Null
		Local substitutions:TMap = TCompilerGenericInheritance.TypeSubstitutions(current)
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			Local inherited:TNamedSemanticType = TNamedSemanticType(TGenericRoutineInference.Substitute(edge.semanticType, substitutions))
			Local found:TNamedSemanticType = InheritedOwnerType(inherited, ownerSymbol, depth + 1)
			If found Then Return found
		Next
		Return Null
	End Method

	Method ExpandInterfaceMethodImplementations(sourceNode:TGenericSpecializationNode)
		If Not sourceNode Or Not sourceNode.artifact Then Return
		Local requirement:TSymbol = TSymbol(symbolsByArtifact.ValueForKey(sourceNode.artifact))
		If Not requirement Or Not requirement.containingScope Or Not requirement.containingScope.owner Then
			AddTemplateDiagnostic("BMXC3082", "closed generic Interface method has no semantic requirement symbol", sourceNode.artifact.members[0].source)
			Return
		End If
		Local interfaceSymbol:TSymbol = requirement.containingScope.owner
		Local implementationCount:Int
		CollectInterfaceMethodImplementations(analysis.model.globalScope, sourceNode, requirement, interfaceSymbol, implementationCount)
	End Method

	Method DiagnoseMissingInterfaceMethodImplementation(sourceNode:TGenericSpecializationNode)
		If Not sourceNode Or Not sourceNode.artifact Or sourceNode.artifact.members[0].body Then Return
		For Local edge:TGenericSpecializationEdge = EachIn sourceNode.outgoing
			If edge And edge.request And (edge.request.reason = GENERIC_REQUEST_INTERFACE_METHOD_IMPLEMENTATION Or edge.request.reason = GENERIC_REQUEST_ABSTRACT_METHOD_IMPLEMENTATION) Then Return
		Next
		Local requirement:TSymbol = TSymbol(symbolsByArtifact.ValueForKey(sourceNode.artifact))
		Local requirementName:String = sourceNode.artifact.identity.qualifiedName
		If requirement Then requirementName = requirement.QualifiedName()
		Local ownerKind:String = "Interface"
		If sourceNode.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_INTERFACE Then ownerKind = "abstract Type"
		AddTemplateDiagnostic("BMXC3083", "generic " + ownerKind + " method '" + requirementName + "' has no application-visible concrete implementation or default body", sourceNode.artifact.members[0].source)
	End Method

	Method CollectInterfaceMethodImplementations(scope:TScope, sourceNode:TGenericSpecializationNode, requirement:TSymbol, interfaceSymbol:TSymbol, implementationCount:Int Var)
		If Not scope Then Return
		For Local typeSymbol:TSymbol = EachIn scope.declaredSymbols
			If Not typeSymbol Or typeSymbol.kind <> SYMBOL_TYPE Then Continue
			Local interfaceType:TNamedSemanticType = ImplementedInterfaceType(TNamedSemanticType(typeSymbol.declaredType), interfaceSymbol, 0)
			If Not interfaceType Then Continue
			Local implementation:TSymbol = ConcreteGenericInterfaceMethod(typeSymbol, requirement, interfaceType, 0)
			If Not implementation Then Continue
			Local artifact:TGenericTemplateArtifact = ArtifactFor(implementation)
			If Not artifact Then Continue
			If GenericTypeArity(typeSymbol) Then
				Local ownerNodes:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
				For Local ownerNode:TGenericSpecializationNode = EachIn plan.registry.nodes
					If SpecializationOwnsType(ownerNode, typeSymbol) Then ownerNodes :+ [ownerNode]
				Next
				For Local ownerNode:TGenericSpecializationNode = EachIn ownerNodes
					AddMethodImplementation(sourceNode, artifact, ownerNode.key.typeArguments, implementationCount, GENERIC_REQUEST_INTERFACE_METHOD_IMPLEMENTATION)
				Next
			Else
				AddMethodImplementation(sourceNode, artifact, New TTemplateTypeReference[0], implementationCount, GENERIC_REQUEST_INTERFACE_METHOD_IMPLEMENTATION)
			End If
		Next
		For Local child:TScope = EachIn scope.children
			CollectInterfaceMethodImplementations(child, sourceNode, requirement, interfaceSymbol, implementationCount)
		Next
	End Method

	Method AddMethodImplementation(sourceNode:TGenericSpecializationNode, artifact:TGenericTemplateArtifact, containingArguments:TTemplateTypeReference[], implementationCount:Int Var, reason:Int)
		Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
		request.requestingUnit = sourceNode.generatedUnit
		request.reason = reason
		request.source = sourceNode.artifact.members[0].source
		Local target:TGenericSpecializationNode = RequestExpansion(sourceNode, artifact, sourceNode.key.typeArguments, request, containingArguments)
		If target Then
			plan.registry.AddEdge(sourceNode, target, request)
			implementationCount :+ 1
		End If
	End Method

	Method SpecializationOwnsType:Int(node:TGenericSpecializationNode, symbol:TSymbol)
		If Not node Or Not node.artifact Or Not node.artifact.identity Or Not symbol Then Return False
		If node.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then Return False
		If node.artifact.identity.qualifiedName.ToLower() <> symbol.QualifiedName().ToLower() Then Return False
		If node.artifact.identity.moduleName.length And symbol.originModule.length And node.artifact.identity.moduleName.ToLower() <> symbol.originModule.ToLower() Then Return False
		Return True
	End Method

	Method ImplementedInterfaceType:TNamedSemanticType(current:TNamedSemanticType, interfaceSymbol:TSymbol, depth:Int)
		If depth > 64 Or Not current Or Not current.symbol Then Return Null
		If current.symbol = interfaceSymbol Then Return current
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(current.symbol)
		If Not info Then Return Null
		Local substitutions:TMap = TCompilerGenericInheritance.TypeSubstitutions(current)
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges + info.baseEdges
			Local inherited:TNamedSemanticType = TNamedSemanticType(TGenericRoutineInference.Substitute(edge.semanticType, substitutions))
			Local found:TNamedSemanticType = ImplementedInterfaceType(inherited, interfaceSymbol, depth + 1)
			If found Then Return found
		Next
		Return Null
	End Method

	Method ConcreteGenericInterfaceMethod:TSymbol(typeSymbol:TSymbol, requirement:TSymbol, interfaceType:TNamedSemanticType, depth:Int)
		If depth > 64 Or Not typeSymbol Then Return Null
		If typeSymbol.memberScope Then
			Local validator:TInheritanceValidator = New TInheritanceValidator
			validator.model = analysis.model
			For Local candidate:TSymbol = EachIn typeSymbol.memberScope.LookupLocal(requirement.name)
				If candidate.kind = SYMBOL_ROUTINE And candidate.genericArity = requirement.genericArity And Not candidate.isAbstract And validator.OverrideSignaturesMatch(candidate, requirement, interfaceType) Then Return candidate
			Next
		End If
		Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(typeSymbol)
		If info Then
			For Local edge:TInheritanceEdge = EachIn info.baseEdges
				Local base:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
				If base And base.symbol Then
					Local found:TSymbol = ConcreteGenericInterfaceMethod(base.symbol, requirement, interfaceType, depth + 1)
					If found Then Return found
				End If
			Next
		End If
		Return Null
	End Method

	Method ExpandNodeReferences(sourceNode:TGenericSpecializationNode, node:TGenericTemplateNode, initializationContext:Int = False)
		If Not node Then Return
		If node.children.length And node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].valueText = "routine-type-arguments" And (node.kind = TEMPLATE_NODE_CALL Or (node.kind = TEMPLATE_NODE_NAME And node.identity = "generic-routine-callable-reference")) Then ExpandRoutineCall(sourceNode, node, initializationContext)
		If node.kind = TEMPLATE_NODE_CALL Then DemandTemplateMethodCall(sourceNode, node, initializationContext)
		' Self normally denotes the current specialization and is not a recursive
		' layout request. A bound inherited generic-method receiver can instead
		' carry its declaring constructed ancestor; that distinct type is a real
		' transitive dependency.
		Local expandNodeType:Int = node.kind <> TEMPLATE_NODE_SELF
		If node.kind = TEMPLATE_NODE_SELF And sourceNode.artifact.isMethod And sourceNode.artifact.containingType Then
			Local currentReceiver:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(sourceNode.artifact.containingType, sourceNode.key.containingTypeArguments, sourceNode.key.typeArguments)
			Local boundReceiver:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(node.semanticType, sourceNode.key.containingTypeArguments, sourceNode.key.typeArguments)
			If currentReceiver And boundReceiver And currentReceiver.CanonicalName().ToLower() <> boundReceiver.CanonicalName().ToLower() Then expandNodeType = True
		End If
		Local nodeTypeReason:Int = GENERIC_REQUEST_TRANSITIVE
		' Return nodes and managed Null conversions repeat a routine's declared ABI
		' type but do not instantiate that class. Their executable children still
		' contribute allocation/call dependencies independently below.
		If node.kind = TEMPLATE_NODE_RETURN Then nodeTypeReason = GENERIC_REQUEST_ABI_REFERENCE
		If node.kind = TEMPLATE_NODE_LITERAL And node.valueText.ToLower() = "null" Then nodeTypeReason = GENERIC_REQUEST_ABI_REFERENCE
		If node.kind = TEMPLATE_NODE_CONVERSION And node.children.length = 1 And node.children[0].kind = TEMPLATE_NODE_LITERAL And node.children[0].valueText.ToLower() = "null" Then nodeTypeReason = GENERIC_REQUEST_ABI_REFERENCE
		If expandNodeType Then ExpandTypeReference(sourceNode, node.semanticType, node.source, nodeTypeReason)
		For Local child:TGenericTemplateNode = EachIn node.children
			ExpandNodeReferences(sourceNode, child, initializationContext)
		Next
	End Method

	Method DemandTemplateMethodCall(sourceNode:TGenericSpecializationNode, node:TGenericTemplateNode, initializationContext:Int = False)
		If Not sourceNode Or Not node Or Not node.referencedSymbol Or Not node.children.length Or node.children[0].kind = TEMPLATE_NODE_BLOCK Then Return
		Local receiver:TTemplateTypeReference = ClosedForSource(sourceNode, node.children[0].semanticType)
		QualifyClosedTypeReference(receiver)
		If Not receiver Or receiver.kind <> TEMPLATE_TYPE_NAMED Or Not receiver.arguments.length Then Return
		Local artifact:TGenericTemplateArtifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey(receiver.moduleName, receiver.symbolName)))
		If Not artifact Then artifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey("", receiver.symbolName)))
		If Not artifact Or artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then Return
		Local target:TGenericSpecializationNode
		If TCompilerGenericSpecializationLowerer.SpecializationMatchesType(sourceNode, receiver) Then
			target = sourceNode
		Else
			Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
			request.requestingUnit = sourceNode.generatedUnit
			If initializationContext Then request.reason = GENERIC_REQUEST_INITIALIZATION Else request.reason = GENERIC_REQUEST_MEMBER_CALL
			request.source = node.source
			target = RequestExpansion(sourceNode, artifact, receiver.arguments, request)
			If target Then plan.registry.AddEdge(sourceNode, target, request)
		End If
		If Not target Then Return
		For Local member:TGenericTemplateMember = EachIn artifact.members
			If member.kind <> TEMPLATE_MEMBER_METHOD Or member.name.ToLower() <> node.valueText.ToLower() Then Continue
			If TemplateCallMatchesMember(sourceNode, node, target, member) Then target.RequireMethod(ClosedMemberMethodSignature(target, member))
		Next
	End Method

	Method TemplateCallMatchesMember:Int(sourceNode:TGenericSpecializationNode, node:TGenericTemplateNode, target:TGenericSpecializationNode, member:TGenericTemplateMember)
		If Not sourceNode Or Not node Or Not target Or Not member Or node.children.length - 1 > member.parameters.length Then Return False
		Local callReturn:TTemplateTypeReference = ClosedForSource(sourceNode, node.semanticType)
		Local memberReturn:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(member.semanticType, target.key.typeArguments)
		If Not callReturn Or Not memberReturn Or callReturn.CanonicalName() <> memberReturn.CanonicalName() Then Return False
		For Local index:Int = 0 Until node.children.length - 1
			If Not node.children[index + 1] Or Not node.children[index + 1].semanticType Then Return False
			Local argument:TTemplateTypeReference = ClosedForSource(sourceNode, node.children[index + 1].semanticType)
			Local parameter:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(member.parameters[index].semanticType, target.key.typeArguments)
			If Not argument Or Not parameter Or argument.CanonicalName() <> parameter.CanonicalName() Then Return False
		Next
		For Local index:Int = node.children.length - 1 Until member.parameters.length
			If Not member.parameters[index].optional Then Return False
		Next
		Return True
	End Method

	Method ClosedForSource:TTemplateTypeReference(sourceNode:TGenericSpecializationNode, value:TTemplateTypeReference)
		If Not sourceNode Or Not value Then Return Null
		If sourceNode.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then Return TTemplateTypeSubstitution.Apply(value, sourceNode.key.containingTypeArguments, sourceNode.key.typeArguments)
		Return TTemplateTypeSubstitution.Apply(value, sourceNode.key.typeArguments)
	End Method

	Method ExpandRoutineCall(sourceNode:TGenericSpecializationNode, node:TGenericTemplateNode, initializationContext:Int = False)
		If Not sourceNode Or Not node Or Not node.referencedSymbol Then Return
		Local artifact:TGenericTemplateArtifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey(node.referencedSymbol.moduleName, node.referencedSymbol.qualifiedName, node.referencedSymbol.overloadKey)))
		If Not artifact Then artifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey("", node.referencedSymbol.qualifiedName, node.referencedSymbol.overloadKey)))
		If Not artifact Or Not artifact.identity Or artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then
			AddTemplateDiagnostic("BMXC3045", "transitive generic routine call '" + node.referencedSymbol.StableName() + "' has no canonical template artifact", node.source)
			Return
		End If
		Local encodedArguments:TGenericTemplateNode = node.children[0]
		If encodedArguments.children.length <> artifact.parameters.length Then
			AddTemplateDiagnostic("BMXC3046", "transitive generic routine call '" + node.valueText + "' has an incomplete canonical type-argument binding", node.source)
			Return
		End If
		Local arguments:TTemplateTypeReference[] = New TTemplateTypeReference[encodedArguments.children.length]
		For Local index:Int = 0 Until arguments.length
			Local value:TTemplateTypeReference = encodedArguments.children[index].semanticType
			If sourceNode.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then
				arguments[index] = TTemplateTypeSubstitution.Apply(value, sourceNode.key.containingTypeArguments, sourceNode.key.typeArguments)
			Else
				arguments[index] = TTemplateTypeSubstitution.Apply(value, sourceNode.key.typeArguments)
			End If
			If Not arguments[index] Or arguments[index].kind = TEMPLATE_TYPE_PARAMETER Then
				AddTemplateDiagnostic("BMXC3046", "transitive generic routine call '" + node.valueText + "' retains an open type argument after substitution", node.source)
				Return
			End If
		Next
		Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
		request.requestingUnit = sourceNode.generatedUnit
		If initializationContext Then request.reason = GENERIC_REQUEST_INITIALIZATION Else request.reason = GENERIC_REQUEST_ROUTINE_CALL
		request.source = node.source
		Local containingArguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
		If artifact.isMethod Then
			If node.children.length < 2 Then
				AddTemplateDiagnostic("BMXC3046", "transitive generic method call '" + node.valueText + "' has no canonical receiver binding", node.source)
				Return
			End If
			Local closedReceiver:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(node.children[1].semanticType, sourceNode.key.containingTypeArguments, sourceNode.key.typeArguments)
			If Not closedReceiver Or closedReceiver.kind <> TEMPLATE_TYPE_NAMED Or closedReceiver.arguments.length <> artifact.containingParameters.length Then
				AddTemplateDiagnostic("BMXC3046", "transitive generic method call '" + node.valueText + "' has an incomplete containing-Type binding", node.source)
				Return
			End If
			containingArguments = closedReceiver.arguments
		End If
		Local target:TGenericSpecializationNode = RequestExpansion(sourceNode, artifact, arguments, request, containingArguments)
		If target Then plan.registry.AddEdge(sourceNode, target, request)
	End Method

	Method RequestExpansion:TGenericSpecializationNode(sourceNode:TGenericSpecializationNode, artifact:TGenericTemplateArtifact, arguments:TTemplateTypeReference[], request:TGenericSpecializationRequestSite, containingArguments:TTemplateTypeReference[] = Null)
		If Not sourceNode Then Return Null
		Local sourceDepth:Int = sourceNode.expansionDepth
		If sourceDepth < 0 Then sourceDepth = 0
		If sourceDepth >= GENERIC_SPECIALIZATION_MAX_EXPANSION_DEPTH Then
			If Not expansionLimitExceeded Then AddTemplateDiagnostic("BMXC3090", "generic specialization expansion exceeded the maximum transitive depth of " + GENERIC_SPECIALIZATION_MAX_EXPANSION_DEPTH + " at '" + sourceNode.key.CanonicalName() + "'", request.source)
			expansionLimitExceeded = True
			Return Null
		End If
		Local target:TGenericSpecializationNode = plan.registry.Request(artifact, arguments, request, containingArguments)
		Local targetArguments:TTemplateTypeReference[] = containingArguments + arguments
		' Deferred generic-Type methods intentionally materialize one explicitly
		' demanded transformed depth. If expansion reaches a second, previously
		' undiscovered larger form of the same artifact, the graph cannot converge.
		' Fail here rather than constructing an enormous family before the ordinary
		' depth limit notices it. Explicit application requests already carry depth
		' zero and remain able to demand each concrete level deliberately. Interface
		' dispatcher edges can connect independent applications of the same Interface;
		' only their concrete implementors can own executable or layout recursion, so
		' Interface artifacts remain under the ordinary depth guard.
		If target And target.expansionDepth < 0 And sourceDepth > 0 And request.reason <> GENERIC_REQUEST_ABI_REFERENCE And artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_INTERFACE And HasGrowingArtifactAncestor(sourceNode, artifact.identity.StableName(), targetArguments, New TMap) Then
			If Not expansionLimitExceeded Then AddTemplateDiagnostic("BMXC3090", "non-convergent transformed generic recursion reached '" + target.key.CanonicalName() + "'", request.source)
			expansionLimitExceeded = True
			target.state = GENERIC_SPECIALIZATION_FAILED
			Return Null
		End If
		If target And (target.expansionDepth < 0 Or target.expansionDepth > sourceDepth + 1) Then target.expansionDepth = sourceDepth + 1
		Return target
	End Method

	Method HasGrowingArtifactAncestor:Int(node:TGenericSpecializationNode, stableName:String, targetArguments:TTemplateTypeReference[], visited:TMap)
		If Not node Or Not visited Or visited.Contains(node.key.CanonicalName()) Then Return False
		visited.Insert(node.key.CanonicalName(), node)
		For Local edge:TGenericSpecializationEdge = EachIn node.incoming
			If Not edge Or Not edge.source Then Continue
			Local ancestor:TGenericSpecializationNode = edge.source
			If ancestor.artifact And ancestor.artifact.identity And ancestor.artifact.identity.StableName() = stableName Then
				Local ancestorArguments:TTemplateTypeReference[] = ancestor.key.containingTypeArguments + ancestor.key.typeArguments
				If TypeArgumentsStrictlyGrow(ancestorArguments, targetArguments) Then Return True
			End If
			If HasGrowingArtifactAncestor(ancestor, stableName, targetArguments, visited) Then Return True
		Next
		Return False
	End Method

	Method ExpandTypeReference(sourceNode:TGenericSpecializationNode, value:TTemplateTypeReference, source:TTemplateSourceLocation, reason:Int = GENERIC_REQUEST_TRANSITIVE)
		If Not sourceNode Or Not value Then Return
		Local substituted:TTemplateTypeReference
		If sourceNode.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then
			substituted = TTemplateTypeSubstitution.Apply(value, sourceNode.key.containingTypeArguments, sourceNode.key.typeArguments)
		Else
			substituted = TTemplateTypeSubstitution.Apply(value, sourceNode.key.typeArguments)
		End If
		QualifyClosedTypeReference(substituted)
		Local managedClassAbiReference:Int
		If substituted.kind = TEMPLATE_TYPE_NAMED And substituted.arguments.length Then
			Local artifact:TGenericTemplateArtifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey(substituted.moduleName, substituted.symbolName)))
			If Not artifact Then artifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey("", substituted.symbolName)))
			If Not artifact Then
				AddTemplateDiagnostic("BMXC3045", "transitive generic reference '" + substituted.CanonicalName() + "' has no canonical template artifact", source)
			Else
				Local edgeReason:Int = reason
				If edgeReason = GENERIC_REQUEST_LAYOUT And artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then edgeReason = GENERIC_REQUEST_TRANSITIVE
				If edgeReason = GENERIC_REQUEST_ABI_REFERENCE Then
					If artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_CLASS Then
						managedClassAbiReference = True
					Else If artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then
						edgeReason = GENERIC_REQUEST_LAYOUT
					Else
						edgeReason = GENERIC_REQUEST_TRANSITIVE
					End If
				End If
				If (reason = GENERIC_REQUEST_ABI_REFERENCE Or edgeReason <> GENERIC_REQUEST_LAYOUT) And sourceNode.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT And TCompilerGenericSpecializationLowerer.SpecializationMatchesType(sourceNode, substituted) Then
				' Method signatures and executable expressions may refer back to
				' their owning Struct by value. That is a declaration/reference
				' relationship, not recursive storage. The current specialization
				' already owns the identity, so no graph edge is required.
				Else
					Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
					request.requestingUnit = sourceNode.generatedUnit
					request.reason = edgeReason
					request.source = source
					Local target:TGenericSpecializationNode = RequestExpansion(sourceNode, artifact, substituted.arguments, request)
					If target Then plan.registry.AddEdge(sourceNode, target, request)
				End If
			End If
		End If
		' A managed class Type in a routine signature needs a stable C ABI identity
		' and forward declaration, but the signature alone does not make that
		' closed type executable. Explicit use sites request materialization.
		If managedClassAbiReference Then Return
		' The request reason describes the outer relationship only. Nested shapes
		' are ordinarily transitive dependencies rather than additional inheritance
		' or Interface edges of the source specialization.
		Local nestedReason:Int = GENERIC_REQUEST_TRANSITIVE
		' Declaration-only signatures remain declaration-only through arrays,
		' pointers and callable/Closure shapes. Named Struct references promote
		' themselves back to layout requests above when their value ABI is needed.
		If reason = GENERIC_REQUEST_ABI_REFERENCE Then nestedReason = GENERIC_REQUEST_ABI_REFERENCE
		If substituted.elementType Then ExpandTypeReference(sourceNode, substituted.elementType, source, nestedReason)
		For Local argument:TTemplateTypeReference = EachIn substituted.arguments
			ExpandTypeReference(sourceNode, argument, source, nestedReason)
		Next
	End Method

	Method QualifyClosedTypeReference(value:TTemplateTypeReference)
		If Not value Then Return
		If value.kind = TEMPLATE_TYPE_NAMED And value.arguments.length Then
			Local artifact:TGenericTemplateArtifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey(value.moduleName, value.symbolName)))
			If Not artifact Then artifact = TGenericTemplateArtifact(artifactsByReference.ValueForKey(ArtifactReferenceKey("", value.symbolName)))
			If artifact Then value.moduleName = artifact.identity.moduleName
		End If
		QualifyClosedTypeReference(value.elementType)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			QualifyClosedTypeReference(argument)
		Next
	End Method

	Function ArtifactReferenceKey:String(moduleName:String, qualifiedName:String, signatureKey:String = "")
		Local result:String = moduleName.ToLower() + "::" + qualifiedName.ToLower()
		If signatureKey.length Then result :+ "/" + signatureKey.ToLower()
		Return result
	End Function

	Method DiscoverScope(scope:TScope)
		If Not scope Or discoveredScopes.Contains(scope) Then Return
		discoveredScopes.Insert(scope, scope)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol Then
				Local reason:Int = GENERIC_REQUEST_SIGNATURE
				' A Struct-valued field contributes physical layout, while Local and
				' Global storage require a concrete value implementation. Treating
				' every declaration as a signature left imported generic Structs as
				' declaration-only references until IR layout failed.
				If symbol.kind = SYMBOL_FIELD Then reason = GENERIC_REQUEST_LAYOUT
				If symbol.kind = SYMBOL_LOCAL Or symbol.kind = SYMBOL_GLOBAL Or symbol.kind = SYMBOL_CATCH_PARAMETER Then reason = GENERIC_REQUEST_TYPE_USE
				DiscoverType(symbol.declaredType, symbol.declaration, reason)
			End If
			If symbol Then
				For Local parameter:TSemanticParameter = EachIn symbol.parameters
					If parameter Then DiscoverType(parameter.semanticType, symbol.declaration, GENERIC_REQUEST_SIGNATURE)
				Next
			End If
			If symbol And symbol.memberScope Then DiscoverScope(symbol.memberScope)
		Next
		For Local child:TScope = EachIn scope.children
			' A source interface owned by an imported module also has a hidden
			' path-addressable scope. Its declarations are merged into the visible
			' nominal module scope, so discovering both would create a second
			' specialization identity named after the physical .bmx file.
			If scope = analysis.model.globalScope And child.kind = SCOPE_INTERFACE_MODULE And Not IsVisibleImportedScope(child) Then Continue
			DiscoverScope(child)
		Next
	End Method

	Method IsVisibleImportedScope:Int(scope:TScope)
		If Not scope Or Not analysis Or Not analysis.model Then Return False
		For Local importedScope:TScope = EachIn analysis.model.importedScopes
			If importedScope = scope Then Return True
		Next
		Return False
	End Method

	Method DiscoverTypeMap()
		If Not analysis Or Not analysis.model Then Return
		For Local value:Object = EachIn analysis.model.typeMap.Keys()
			Local syntax:TTypeReferenceSyntax = TTypeReferenceSyntax(value)
			If syntax And sourceSyntaxNodes.Contains(syntax) Then DiscoverType(analysis.model.TypeOf(syntax), syntax, GENERIC_REQUEST_TYPE_USE)
		Next
	End Method

	Method DiscoverExpressionMap()
		If Not analysis Or Not analysis.model Then Return
		For Local value:Object = EachIn analysis.model.expressionTypeMap.Keys()
			Local syntax:TExpressionSyntax = TExpressionSyntax(value)
			If Not syntax Or Not sourceSyntaxNodes.Contains(syntax) Then Continue
			Local reason:Int = GENERIC_REQUEST_TYPE_USE
			If TNewExpressionSyntax(syntax) Then reason = GENERIC_REQUEST_ALLOCATION
			If TCallExpressionSyntax(syntax) Or TMemberAccessExpressionSyntax(syntax) Then reason = GENERIC_REQUEST_MEMBER_CALL
			DiscoverType(analysis.model.ExpressionType(syntax), syntax, reason)
			Local routineReference:TBoundRoutineReferenceExpression = TBoundRoutineReferenceExpression(analysis.model.BoundExpression(syntax))
			If routineReference Then
				DemandClosedGenericOwnerRoutineReference(syntax, routineReference)
				DemandClosedGenericRoutineReference(syntax, routineReference)
			End If
		Next
	End Method

	Method DemandClosedGenericRoutineReference(syntax:TSyntaxNode, routineReference:TBoundRoutineReferenceExpression)
		If Not syntax Or Not routineReference Or Not routineReference.routine Or routineReference.routine.genericArity <= 0 Then Return
		If routineReference.typeArguments.length <> routineReference.routine.genericArity Then
			AddDiagnostic("BMXC3046", "Generic routine reference has no complete canonical type-argument binding", syntax)
			Return
		End If
		For Local argument:TSemanticType = EachIn routineReference.typeArguments
			If ContainsOpenType(argument) Then Return
		Next
		Local artifact:TGenericTemplateArtifact = ArtifactFor(routineReference.routine)
		If Not artifact Then Return
		Local arguments:TTemplateTypeReference[] = New TTemplateTypeReference[routineReference.typeArguments.length]
		For Local index:Int = 0 Until arguments.length
			arguments[index] = ClosedArgument(routineReference.typeArguments[index])
			If Not arguments[index] Then
				AddDiagnostic("BMXC3040", "Generic routine-reference specialization arguments are outside the supported canonical value/reference slice", syntax)
				Return
			End If
		Next
		Local containingArguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
		If artifact.isMethod Then
			Local owner:TSymbol
			If routineReference.routine.containingScope Then owner = routineReference.routine.containingScope.owner
			Local receiver:TNamedSemanticType = TCompilerGenericInheritance.ConstructedOwnerType(routineReference.staticReceiverType, owner, analysis.model)
			If Not receiver Or receiver.typeArguments.length <> artifact.containingParameters.length Then
				AddDiagnostic("BMXC3046", "Generic routine reference has no complete containing-Type argument binding", syntax)
				Return
			End If
			containingArguments = New TTemplateTypeReference[receiver.typeArguments.length]
			For Local index:Int = 0 Until containingArguments.length
				containingArguments[index] = ClosedArgument(receiver.typeArguments[index])
				If Not containingArguments[index] Then
					AddDiagnostic("BMXC3040", "Generic routine-reference containing-Type arguments are outside the supported canonical value/reference slice", syntax)
					Return
				End If
			Next
		End If
		Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
		request.reason = GENERIC_REQUEST_ROUTINE_CALL
		request.source = TemplateSource(syntax)
		If request.source Then request.requestingUnit = request.source.path
		Local target:TGenericSpecializationNode = plan.registry.Request(artifact, arguments, request, containingArguments)
		If target And target.expansionDepth < 0 Then target.expansionDepth = 0
	End Method

	Method DiscoverRoutineCalls()
		If Not analysis Or Not analysis.model Then Return
		For Local value:Object = EachIn analysis.model.resolvedCallMap.Keys()
			Local syntax:TSyntaxNode = TSyntaxNode(value)
			If Not syntax Or Not sourceSyntaxNodes.Contains(syntax) Then Continue
			Local resolved:TResolvedCall = TResolvedCall(analysis.model.resolvedCallMap.ValueForKey(value))
			If resolved And resolved.routine Then DemandClosedGenericOwnerMethod(syntax, resolved)
			If Not resolved Or Not IsTemplateSymbol(resolved.routine) Or resolved.routine.kind <> SYMBOL_ROUTINE Then Continue
			If resolved.typeArguments.length <> resolved.routine.genericArity Then
				AddDiagnostic("BMXC3046", "Generic routine call has no complete canonical type-argument binding", syntax)
				Continue
			End If
			Local containsOpenArgument:Int
			For Local typeArgument:TSemanticType = EachIn resolved.typeArguments
				If ContainsOpenType(typeArgument) Then containsOpenArgument = True; Exit
			Next
			If containsOpenArgument Then Continue
			Local artifact:TGenericTemplateArtifact = ArtifactFor(resolved.routine)
			If Not artifact Then Continue
			Local arguments:TTemplateTypeReference[] = New TTemplateTypeReference[resolved.typeArguments.length]
			Local supported:Int = True
			For Local index:Int = 0 Until resolved.typeArguments.length
				arguments[index] = ClosedArgument(resolved.typeArguments[index])
				If Not arguments[index] Then supported = False
			Next
			If Not supported Then
				AddDiagnostic("BMXC3040", "Generic routine specialization arguments are outside the supported canonical value/reference slice", syntax)
				Continue
			End If
			Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
			request.reason = GENERIC_REQUEST_ROUTINE_CALL
			request.source = TemplateSource(syntax)
			If request.source Then request.requestingUnit = request.source.path
			Local containingArguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
			If artifact.isMethod Then
				Local callExpression:TExpressionSyntax = TExpressionSyntax(syntax)
				Local boundCall:TBoundCallExpression
				If callExpression Then boundCall = TBoundCallExpression(analysis.model.BoundExpression(callExpression))
				Local receiverType:TNamedSemanticType
				Local methodOwner:TSymbol
				If resolved.routine.containingScope Then methodOwner = resolved.routine.containingScope.owner
				If boundCall And boundCall.receiver Then receiverType = TCompilerGenericInheritance.ConstructedOwnerType(boundCall.receiver.semanticType, methodOwner, analysis.model)
				If Not receiverType Or receiverType.typeArguments.length <> artifact.containingParameters.length Then
					AddDiagnostic("BMXC3046", "Generic method call has no complete containing-Type argument binding", syntax)
					Continue
				End If
				containingArguments = New TTemplateTypeReference[receiverType.typeArguments.length]
				For Local index:Int = 0 Until containingArguments.length
					containingArguments[index] = ClosedArgument(receiverType.typeArguments[index])
					If Not containingArguments[index] Then supported = False
				Next
				If Not supported Then
					AddDiagnostic("BMXC3040", "Generic method containing-Type arguments are outside the supported canonical value/reference slice", syntax)
					Continue
				End If
			End If
			Local target:TGenericSpecializationNode = plan.registry.Request(artifact, arguments, request, containingArguments)
			If target And target.expansionDepth < 0 Then target.expansionDepth = 0
		Next
	End Method

	Method DemandClosedGenericOwnerMethod(syntax:TSyntaxNode, resolved:TResolvedCall)
		If Not syntax Or Not resolved Or Not resolved.routine Or resolved.routine.genericArity Then Return
		' Both Methods and Type Functions are members of a generic owner and may
		' have deferred bodies. The earlier Method-only check left a directly called
		' Type Function behind the polymorphic-recursion runtime guard.
		If Not resolved.routine.containingScope Then Return
		Local owner:TSymbol = resolved.routine.containingScope.owner
		If Not owner Or GenericTypeArity(owner) <= 0 Then Return
		Local expression:TExpressionSyntax = TExpressionSyntax(syntax)
		If Not expression Then Return
		Local call:TBoundCallExpression = TBoundCallExpression(analysis.model.BoundExpression(expression))
		If Not call Then Return
		Local receiverSource:TSemanticType = call.staticReceiverType
		If call.receiver Then receiverSource = call.receiver.semanticType
		If Not receiverSource Then Return
		Local receiver:TNamedSemanticType = TCompilerGenericInheritance.ConstructedOwnerType(receiverSource, owner, analysis.model)
		If Not receiver Or receiver.typeArguments.length <> GenericTypeArity(owner) Then Return
		Local arguments:TTemplateTypeReference[] = New TTemplateTypeReference[receiver.typeArguments.length]
		For Local index:Int = 0 Until arguments.length
			arguments[index] = ClosedArgument(receiver.typeArguments[index])
			If Not arguments[index] Then Return
		Next
		' Open calls inside a generic declaration are handled when that body is
		' specialized. Do not ask ArtifactFor to materialize a reconstructed or
		' inherited owner before proving that this application call is closed.
		Local artifact:TGenericTemplateArtifact = ArtifactFor(owner)
		If Not artifact Then Return
		Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
		request.reason = GENERIC_REQUEST_MEMBER_CALL
		request.source = TemplateSource(syntax)
		If request.source Then request.requestingUnit = request.source.path
		Local target:TGenericSpecializationNode = plan.registry.Request(artifact, arguments, request)
		If Not target Then Return
		If target.expansionDepth < 0 Then target.expansionDepth = 0
		target.RequireMethod(ClosedResolvedMethodSignature(resolved))
	End Method

	Method DemandClosedGenericOwnerRoutineReference(syntax:TSyntaxNode, routineReference:TBoundRoutineReferenceExpression)
		If Not syntax Or Not routineReference Or Not routineReference.routine Or Not routineReference.staticReceiverType Then Return
		Local owner:TSymbol
		If routineReference.routine.containingScope Then owner = routineReference.routine.containingScope.owner
		If Not owner Or GenericTypeArity(owner) <= 0 Then Return
		Local receiver:TNamedSemanticType = TCompilerGenericInheritance.ConstructedOwnerType(routineReference.staticReceiverType, owner, analysis.model)
		If Not receiver Or receiver.typeArguments.length <> GenericTypeArity(owner) Then Return
		Local arguments:TTemplateTypeReference[] = New TTemplateTypeReference[receiver.typeArguments.length]
		For Local index:Int = 0 Until arguments.length
			arguments[index] = ClosedArgument(receiver.typeArguments[index])
			If Not arguments[index] Then Return
		Next
		Local artifact:TGenericTemplateArtifact = ArtifactFor(owner)
		If Not artifact Then Return
		Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
		request.reason = GENERIC_REQUEST_MEMBER_CALL
		request.source = TemplateSource(syntax)
		If request.source Then request.requestingUnit = request.source.path
		Local target:TGenericSpecializationNode = plan.registry.Request(artifact, arguments, request)
		If Not target Then Return
		If target.expansionDepth < 0 Then target.expansionDepth = 0
		Local signature:String = ClosedCallableMethodSignature(routineReference.routine, TCallableSemanticType(routineReference.semanticType))
		If signature.length Then target.RequireMethod(signature)
	End Method

	Method ClosedResolvedMethodSignature:String(resolved:TResolvedCall)
		If Not resolved Or Not resolved.routine Then Return ""
		Local result:String = resolved.routine.name.ToLower() + "("
		For Local index:Int = 0 Until resolved.parameterTypes.length
			If index Then result :+ ","
			If index < resolved.routine.parameters.length And resolved.routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then result :+ "var:" Else result :+ "value:"
			Local parameter:TTemplateTypeReference = ClosedArgument(resolved.parameterTypes[index])
			If parameter Then result :+ parameter.CanonicalName() Else result :+ "?"
		Next
		result :+ "):"
		Local returnType:TTemplateTypeReference = ClosedArgument(resolved.returnType)
		If returnType Then result :+ returnType.CanonicalName() Else result :+ "?"
		Return result
	End Method

	Method ClosedCallableMethodSignature:String(routine:TSymbol, callable:TCallableSemanticType)
		If Not routine Or Not callable Then Return ""
		Local result:String = routine.name.ToLower() + "("
		For Local index:Int = 0 Until callable.parameterTypes.length
			If index Then result :+ ","
			If index < callable.parameterModes.length And callable.parameterModes[index] = PARAMETER_PASS_VAR Then result :+ "var:" Else result :+ "value:"
			Local parameter:TTemplateTypeReference = ClosedArgument(callable.parameterTypes[index])
			If parameter Then result :+ parameter.CanonicalName() Else result :+ "?"
		Next
		result :+ "):"
		Local returnType:TTemplateTypeReference = ClosedArgument(callable.returnType)
		If returnType Then result :+ returnType.CanonicalName() Else result :+ "?"
		Return result
	End Method

	Method DiscoverType(value:TSemanticType, syntax:TSyntaxNode, reason:Int)
		If Not value Then Return
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then
			For Local argument:TSemanticType = EachIn named.typeArguments
				DiscoverType(argument, syntax, reason)
			Next
			If Not named.symbol Then Return
			Local genericArity:Int = GenericTypeArity(named.symbol)
			' Imported member signatures can resolve through a reconstructed
			' Interface symbol whose declaration header is not the owning
			' generic declaration. Closed type arguments are nevertheless an
			' unambiguous canonical specialization request, and ArtifactFor
			' validates the published companion identity below.
			If genericArity <= 0 And Not (named.symbol.isImported And named.typeArguments.length And (named.symbol.kind = SYMBOL_TYPE Or named.symbol.kind = SYMBOL_INTERFACE Or named.symbol.kind = SYMBOL_STRUCT)) Then Return
			If named.symbol.kind <> SYMBOL_TYPE And named.symbol.kind <> SYMBOL_INTERFACE And named.symbol.kind <> SYMBOL_STRUCT Then Return
			If Not named.typeArguments.length Or ContainsOpenParameter(named.typeArguments) Then Return
			Local artifact:TGenericTemplateArtifact = ArtifactFor(named.symbol)
			If Not artifact Then Return
			Local templateArguments:TTemplateTypeReference[] = New TTemplateTypeReference[named.typeArguments.length]
			For Local index:Int = 0 Until named.typeArguments.length
				templateArguments[index] = ClosedArgument(named.typeArguments[index])
				If Not templateArguments[index] Then
					AddDiagnostic("BMXC3040", "Generic specialization argument '" + named.typeArguments[index].DisplayName() + "' has no supported canonical value or published reference identity", syntax)
					Return
				End If
			Next
			Local request:TGenericSpecializationRequestSite = New TGenericSpecializationRequestSite
			request.reason = reason
			request.source = TemplateSource(syntax)
			If request.source Then request.requestingUnit = request.source.path
			If Not request.requestingUnit.length And analysis.syntaxTree And analysis.syntaxTree.source Then request.requestingUnit = analysis.syntaxTree.source.path
			Local target:TGenericSpecializationNode = plan.registry.Request(artifact, templateArguments, request)
			If target And target.expansionDepth < 0 Then target.expansionDepth = 0
			Return
		End If
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If pointer Then DiscoverType(pointer.elementType, syntax, reason)
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then DiscoverType(arrayType.elementType, syntax, reason)
		Local fixedArray:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If fixedArray Then DiscoverType(fixedArray.elementType, syntax, reason)
		Local callable:TCallableSemanticType = TCallableSemanticType(value)
		If callable Then
			DiscoverType(callable.returnType, syntax, reason)
			For Local parameterType:TSemanticType = EachIn callable.parameterTypes
				DiscoverType(parameterType, syntax, reason)
			Next
		End If
		Local closure:TClosureSemanticType = TClosureSemanticType(value)
		If closure And closure.signature Then
			DiscoverType(closure.signature.returnType, syntax, reason)
			For Local parameterType:TSemanticType = EachIn closure.signature.parameterTypes
				DiscoverType(parameterType, syntax, reason)
			Next
		End If
	End Method

	Method ArtifactFor:TGenericTemplateArtifact(symbol:TSymbol)
		Local existing:TGenericTemplateArtifact = TGenericTemplateArtifact(artifactsBySymbol.ValueForKey(symbol))
		If existing Then
			symbolsByArtifact.Insert(existing, symbol)
			Return existing
		End If
		If symbol And symbol.isImported Then
			If Not symbol.genericTemplateArtifact Then
				' Bootstrap bridge for legacy generic Interface records. Their
				' complete semantic contract is already present in the compact
				' declaration/member table, so a body-free canonical artifact
				' can be derived without treating the legacy source payload as
				' an implementation template. Generic Types, Structs, and
				' routines still require a published canonical companion.
				If symbol.kind = SYMBOL_INTERFACE Then
					Local bridgeDiagnostics:String[]
					Local bridgeArtifact:TGenericTemplateArtifact = TCompilerLegacyGenericInterfaceBridge.Build(analysis.model, symbol, COMPILER_GENERIC_LANGUAGE_LINKAGE_REVISION, bridgeDiagnostics)
					For Local message:String = EachIn bridgeDiagnostics
						AddMessageDiagnostic(message, symbol.declaration)
					Next
					If Not bridgeDiagnostics.length And bridgeArtifact Then
						symbol.genericTemplateArtifact = bridgeArtifact
					End If
				End If
				If Not symbol.genericTemplateArtifact Then
					AddDiagnostic("BMXC3041", "Imported generic Type '" + symbol.QualifiedName() + "' has no canonical template artifact; rebuild its defining module", symbol.declaration)
					Return Null
				End If
			End If
			If symbol.genericTemplateArtifact.languageLinkageRevision.ToLower() <> COMPILER_GENERIC_LANGUAGE_LINKAGE_REVISION.ToLower() Then
				AddDiagnostic("BMXC3042", "Imported generic Type '" + symbol.QualifiedName() + "' uses incompatible language/linkage revision '" + symbol.genericTemplateArtifact.languageLinkageRevision + "'", symbol.declaration)
				Return Null
			End If
			artifactsBySymbol.Insert(symbol, symbol.genericTemplateArtifact)
			symbolsByArtifact.Insert(symbol.genericTemplateArtifact, symbol)
			Return symbol.genericTemplateArtifact
		End If
		Local builderDiagnostics:String[]
		Local moduleIdentity:String
		If analysis And analysis.model Then moduleIdentity = analysis.model.moduleName
		If Not moduleIdentity.length And analysis And analysis.syntaxTree And analysis.syntaxTree.source Then moduleIdentity = "source:" + analysis.syntaxTree.source.path
		' Publication immediately finalizes and serializes every source
		' template, so avoid constructing its large canonical payload twice.
		Local artifact:TGenericTemplateArtifact = TCompilerGenericTemplateBuilder.Build(analysis.model, symbol, moduleIdentity, COMPILER_GENERIC_LANGUAGE_LINKAGE_REVISION, builderDiagnostics, True)
		For Local message:String = EachIn builderDiagnostics
			AddMessageDiagnostic(message, symbol.declaration)
		Next
		If builderDiagnostics.length Then Return Null
		artifactsBySymbol.Insert(symbol, artifact)
		symbolsByArtifact.Insert(artifact, symbol)
		symbol.genericTemplateArtifact = artifact
		plan.specializedSourceSymbols.Insert(symbol, artifact.identity.StableName())
		RegisterSpecializationGlobalDependencies(artifact)
		RegisterSpecializationRoutineDependencies(artifact)
		Return artifact
	End Method

	Method RegisterSpecializationGlobalDependencies(artifact:TGenericTemplateArtifact)
		If Not artifact Or Not analysis Or Not analysis.model Then Return
		RegisterSpecializationGlobalsInNode(artifact.body)
		For Local member:TGenericTemplateMember = EachIn artifact.members
			RegisterSpecializationGlobalsInNode(member.body)
			For Local parameter:TGenericTemplateValueParameter = EachIn member.parameters
				RegisterSpecializationGlobalsInNode(parameter.defaultValue)
			Next
		Next
	End Method

	Method RegisterSpecializationGlobalsInNode(node:TGenericTemplateNode)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_NAME And node.identity = "ordinary-global" And node.referencedSymbol And node.referencedSymbol.overloadKey.length Then
			For Local candidate:TSymbol = EachIn analysis.model.globalScope.LookupLocal(node.valueText)
				If candidate And candidate.kind = SYMBOL_GLOBAL And Not candidate.isImported And node.referencedSymbol.overloadKey.StartsWith("bmx_private_global_") Then
					plan.specializationGlobalAbis.Insert(candidate, node.referencedSymbol.overloadKey)
				End If
			Next
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			RegisterSpecializationGlobalsInNode(child)
		Next
	End Method

	Method RegisterSpecializationRoutineDependencies(artifact:TGenericTemplateArtifact)
		If Not artifact Or Not analysis Or Not analysis.model Then Return
		RegisterSpecializationRoutinesInNode(artifact.body)
		For Local member:TGenericTemplateMember = EachIn artifact.members
			RegisterSpecializationRoutinesInNode(member.body)
			For Local parameter:TGenericTemplateValueParameter = EachIn member.parameters
				RegisterSpecializationRoutinesInNode(parameter.defaultValue)
			Next
		Next
	End Method

	Method RegisterSpecializationRoutinesInNode(node:TGenericTemplateNode)
		If Not node Then Return
		If node.referencedSymbol And node.referencedSymbol.overloadKey.StartsWith("bmx_generic_dependency_") Then
			Local abiName:String = node.referencedSymbol.overloadKey
			If node.kind = TEMPLATE_NODE_NEW And abiName.EndsWith("_ObjectNew") Then abiName = abiName[..abiName.length - 10]
			Local symbol:TSymbol = FindSourceRoutine(analysis.model.globalScope, node.referencedSymbol.qualifiedName, abiName)
			If symbol Then
				plan.specializationRoutineAbis.Insert(symbol, abiName)
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			RegisterSpecializationRoutinesInNode(child)
		Next
	End Method

	Method FindSourceRoutine:TSymbol(scope:TScope, qualifiedName:String, abiName:String)
		If Not scope Then Return Null
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol And symbol.kind = SYMBOL_ROUTINE And Not symbol.isImported And symbol.QualifiedName().ToLower() = qualifiedName.ToLower() And TCompilerGenericTemplateBuilder.OrdinaryPrivateRoutineDependencyAbiName(symbol, analysis.model) = abiName Then Return symbol
		Next
		For Local child:TScope = EachIn scope.children
			Local found:TSymbol = FindSourceRoutine(child, qualifiedName, abiName)
			If found Then Return found
		Next
		Return Null
	End Method

	Method LowerUnits()
		' The bounded graph is retained for diagnostics, but none of its partial
		' executable specializations are safe to publish after a depth failure.
		If expansionLimitExceeded Then Return
		For Local node:TGenericSpecializationNode = EachIn plan.registry.nodes
			If node.state = GENERIC_SPECIALIZATION_FAILED Then Continue
			If node.IsAbiReferenceOnly() Then Continue
			Local loweringDiagnostics:String[]
			Local started:Int = MilliSecs()
			Local ir:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(node, loweringDiagnostics)
			plan.specializationIrMilliseconds :+ MilliSecs() - started
			For Local message:String = EachIn loweringDiagnostics
				AddMessageDiagnostic(message, node.artifact.identity)
			Next
			If loweringDiagnostics.length Or Not ir Then Continue
			Local unit:TCompilerGenericUnit = New TCompilerGenericUnit
			unit.specialization = node
			unit.ir = ir
			Local cached:TCompilerGenericBackendUnitCacheEntry
			If backendUnitCache Then cached = backendUnitCache.Find(node.cacheKey, node.identityDigest)
			If cached Then
				unit.declarations = cached.declarations
				unit.applicationDeclarations = cached.applicationDeclarations
				unit.implementation = cached.implementation
				plan.units :+ [unit]
				AddLinkInput(unit)
				Continue
			End If
			Local declarationDiagnostics:String[]
			started = MilliSecs()
			unit.declarations = TCompilerGenericCUnitEmitter.EmitDeclarations(ir, declarationDiagnostics)
			plan.declarationEmissionMilliseconds :+ MilliSecs() - started
			For Local message:String = EachIn declarationDiagnostics
				AddMessageDiagnostic(message, node.artifact.identity)
			Next
			Local implementationDiagnostics:String[]
			started = MilliSecs()
			unit.implementation = TCompilerGenericCUnitEmitter.EmitImplementationUnit(ir, implementationDiagnostics, unit.declarations)
			plan.implementationEmissionMilliseconds :+ MilliSecs() - started
			For Local message:String = EachIn implementationDiagnostics
				AddMessageDiagnostic(message, node.artifact.identity)
			Next
			Local applicationDeclarationDiagnostics:String[]
			started = MilliSecs()
			If ir.isInterface Then
				unit.applicationDeclarations = unit.declarations
			Else
				unit.applicationDeclarations = TCompilerGenericCUnitEmitter.EmitDeclarations(ir, applicationDeclarationDiagnostics, False, False)
			End If
			plan.applicationDeclarationMilliseconds :+ MilliSecs() - started
			For Local message:String = EachIn applicationDeclarationDiagnostics
				AddMessageDiagnostic(message, node.artifact.identity)
			Next
			If declarationDiagnostics.length Or implementationDiagnostics.length Or applicationDeclarationDiagnostics.length Then Continue
			If backendUnitCache Then backendUnitCache.Add(node.cacheKey, node.identityDigest, unit.declarations, unit.applicationDeclarations, unit.implementation)
			plan.units :+ [unit]
			AddLinkInput(unit)
		Next
		Local applicationDeclarationStarted:Int = MilliSecs()
		BuildApplicationDeclarations()
		plan.applicationDeclarationMilliseconds :+ MilliSecs() - applicationDeclarationStarted
	End Method

	Method AddLinkInput(unit:TCompilerGenericUnit)
		Local linkInput:TCompilerGenericLinkInput = New TCompilerGenericLinkInput
		linkInput.specializationIdentity = unit.specialization.identityDigest
		linkInput.sourcePath = unit.specialization.generatedUnit
		linkInput.objectPath = unit.specialization.generatedObject
		linkInput.cacheKey = unit.specialization.cacheKey
		plan.linkInputs :+ [linkInput]
	End Method

	Method BuildApplicationDeclarations()
		Local emitted:TMap = New TMap
		Local visiting:TMap = New TMap
		Local declarations:TStringBuilder = New TStringBuilder(4096)
		For Local unit:TCompilerGenericUnit = EachIn plan.units
			AppendApplicationDeclaration(unit, emitted, visiting, declarations)
		Next
		plan.declarations = declarations.ToString()
	End Method

	Method AppendApplicationDeclaration(unit:TCompilerGenericUnit, emitted:TMap, visiting:TMap, declarations:TStringBuilder)
		If Not unit Or Not unit.specialization Or Not unit.ir Then Return
		Local key:String = unit.specialization.key.CanonicalName()
		If emitted.Contains(key) Then Return
		If visiting.Contains(key) Then
			AddMessageDiagnostic("BMXC3028 recursive generic declaration ownership reached '" + key + "'", unit.specialization.artifact.identity)
			Return
		End If
		visiting.Insert(key, unit)
		For Local referenced:TGenericSpecializationNode = EachIn unit.ir.referencedSpecializations
			If referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Continue
			Local dependency:TCompilerGenericUnit = UnitForSpecialization(referenced)
			If dependency Then AppendApplicationDeclaration(dependency, emitted, visiting, declarations)
		Next
		visiting.Remove(key)
		declarations.Append(unit.applicationDeclarations)
		emitted.Insert(key, unit)
	End Method

	Method UnitForSpecialization:TCompilerGenericUnit(specialization:TGenericSpecializationNode)
		For Local unit:TCompilerGenericUnit = EachIn plan.units
			If unit.specialization = specialization Then Return unit
		Next
		Return Null
	End Method

	Method TranslateRegistryDiagnostics()
		For Local message:String = EachIn plan.registry.diagnostics
			AddMessageDiagnostic(message, Null)
		Next
	End Method

	Method Configuration:TCompilerGenericConfiguration()
		Local result:TCompilerGenericConfiguration = New TCompilerGenericConfiguration
		result.languageLinkageRevision = COMPILER_GENERIC_LANGUAGE_LINKAGE_REVISION
		result.compilerIrRevision = COMPILER_GENERIC_IR_REVISION
		result.runtimeAbiRevision = COMPILER_GENERIC_RUNTIME_ABI_REVISION
		result.compilerBackendRevision = COMPILER_GENERIC_BACKEND_REVISION
		If options Then
			result.targetPlatform = options.targetPlatform
			result.targetArchitecture = options.targetArchitecture
			result.buildMode = options.buildMode
			result.applicationIdentity = options.applicationIdentity
			result.applicationType = options.applicationType
			result.frameworkModule = options.frameworkModule
			result.debugInstrumentation = options.debugInstrumentation
			result.gdbDebug = options.gdbDebug
			result.coverageInstrumentation = options.coverageInstrumentation
			result.conditionalEnvironmentRevision = ConditionalRevision(options.conditionalSymbols)
			If HasConditionalSymbol(options.conditionalSymbols, "threaded") Then result.threadingMode = "threaded" Else result.threadingMode = "single"
		End If
		If result.targetArchitecture = "x64" Or result.targetArchitecture = "arm64" Or result.targetArchitecture = "ppc64" Then result.pointerWidth = 64 Else result.pointerWidth = 32
		result.exceptionMode = "default"
		result.garbageCollectorMode = "default"
		result.cpuMode = "generic"
		result.fpuMode = "default"
		result.simdMode = "default"
		Return result
	End Method

	Function ContainsOpenParameter:Int(arguments:TSemanticType[])
		For Local argument:TSemanticType = EachIn arguments
			If TTypeParameterSemanticType(argument) Then Return True
			Local named:TNamedSemanticType = TNamedSemanticType(argument)
			If named And ContainsOpenParameter(named.typeArguments) Then Return True
			Local pointer:TPointerSemanticType = TPointerSemanticType(argument)
			If pointer And ContainsOpenType(pointer.elementType) Then Return True
			Local arrayType:TArraySemanticType = TArraySemanticType(argument)
			If arrayType And ContainsOpenType(arrayType.elementType) Then Return True
			Local closure:TClosureSemanticType = TClosureSemanticType(argument)
			If closure And closure.signature Then
				If ContainsOpenType(closure.signature.returnType) Or ContainsOpenParameter(closure.signature.parameterTypes) Then Return True
			End If
		Next
		Return False
	End Function

	Function ContainsOpenType:Int(value:TSemanticType)
		If TTypeParameterSemanticType(value) Then Return True
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then Return ContainsOpenParameter(named.typeArguments)
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If pointer Then Return ContainsOpenType(pointer.elementType)
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then Return ContainsOpenType(arrayType.elementType)
		Local closure:TClosureSemanticType = TClosureSemanticType(value)
		If closure And closure.signature Then Return ContainsOpenType(closure.signature.returnType) Or ContainsOpenParameter(closure.signature.parameterTypes)
		Return False
	End Function

	Method ClosedArgument:TTemplateTypeReference(value:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If builtin Then
			Select builtin.name.ToLower()
				Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam", "float", "double", "float64", "string", "object", "void"
					Local result:TTemplateTypeReference = New TTemplateTypeReference
					result.kind = TEMPLATE_TYPE_BUILTIN
					result.symbolName = builtin.name
					Return result
			End Select
			Return Null
		End If
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If pointer Then
			Local pointerElement:TTemplateTypeReference = ClosedArgument(pointer.elementType)
			If Not pointerElement Then Return Null
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_POINTER
			result.elementType = pointerElement
			Return result
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then
			Local arrayElement:TTemplateTypeReference = ClosedArgument(arrayType.elementType)
			If Not arrayElement Then Return Null
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_ARRAY
			result.elementType = arrayElement
			result.rank = arrayType.rank
			Return result
		End If
		Local fixedArrayArgument:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If fixedArrayArgument Then
			Local staticElement:TTemplateTypeReference = ClosedArgument(fixedArrayArgument.elementType)
			If Not staticElement Then Return Null
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_STATIC_ARRAY
			result.elementType = staticElement
			result.staticArrayLength = fixedArrayArgument.length
			Return result
		End If
		Local closureArgument:TClosureSemanticType = TClosureSemanticType(value)
		If closureArgument And closureArgument.signature Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_CLOSURE
			result.elementType = ClosedArgument(closureArgument.signature.returnType)
			If Not result.elementType Then Return Null
			result.arguments = New TTemplateTypeReference[closureArgument.signature.parameterTypes.length]
			result.callableParameterModes = closureArgument.signature.parameterModes[..]
			result.callableParameterNames = closureArgument.parameterNames[..]
			For Local index:Int = 0 Until closureArgument.signature.parameterTypes.length
				result.arguments[index] = ClosedArgument(closureArgument.signature.parameterTypes[index])
				If Not result.arguments[index] Then Return Null
			Next
			Return result
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named And named.symbol Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_NAMED
			result.moduleName = named.symbol.originModule
			' A quoted source import is rebound into the consuming model, so its
			' originPath may be only relative provenance.  The attached template
			' artifact retains the canonical owner used by every specialization.
			Local canonicalArtifact:TGenericTemplateArtifact = named.symbol.genericTemplateArtifact
			If canonicalArtifact And canonicalArtifact.identity Then result.moduleName = canonicalArtifact.identity.moduleName
			If Not result.moduleName.length And named.symbol.isImported And named.symbol.originPath.length Then result.moduleName = "source:" + named.symbol.originPath.Replace("\", "/")
			If Not result.moduleName.length And analysis And analysis.model Then result.moduleName = analysis.model.moduleName
			' Included declarations belong to the surrounding compilation unit even
			' though their diagnostic provenance retains the included file path.
			If Not result.moduleName.length And analysis And analysis.syntaxTree And analysis.syntaxTree.source Then result.moduleName = "source:" + analysis.syntaxTree.source.path.Replace("\", "/")
			If Not result.moduleName.length And named.symbol.originPath.length Then result.moduleName = "source:" + named.symbol.originPath.Replace("\", "/")
			result.symbolName = named.symbol.QualifiedName()
			If named.symbol.kind = SYMBOL_INTERFACE Then
				result.runtimeKind = TEMPLATE_RUNTIME_INTERFACE
			Else If named.symbol.kind = SYMBOL_STRUCT Then
				result.runtimeKind = TEMPLATE_RUNTIME_STRUCT
			Else If named.symbol.kind = SYMBOL_TYPE Then
				result.runtimeKind = TEMPLATE_RUNTIME_CLASS
			End If
			result.arguments = New TTemplateTypeReference[named.typeArguments.length]
			For Local index:Int = 0 Until named.typeArguments.length
				result.arguments[index] = ClosedArgument(named.typeArguments[index])
				If Not result.arguments[index] Then Return Null
			Next
			If named.symbol.kind = SYMBOL_ENUM And named.symbol.genericArity = 0 And named.typeArguments.length = 0 Then
				result.runtimeKind = TEMPLATE_RUNTIME_ENUM
				result.runtimeAbiName = named.symbol.externalName
				If Not result.runtimeAbiName.length And Not named.symbol.isImported Then
					result.runtimeAbiName = TCompilerDirectMethodAbi.OwnerAbiName(analysis.model, named.symbol)
				End If
				result.runtimeValueType = TCompilerGenericTemplateBuilder.EnumUnderlyingTypeName(named.symbol, analysis.model)
			End If
			If named.symbol.genericArity = 0 And named.typeArguments.length = 0 And (named.symbol.kind = SYMBOL_TYPE Or named.symbol.kind = SYMBOL_INTERFACE Or named.symbol.kind = SYMBOL_STRUCT) Then
				result.runtimeAbiName = named.symbol.externalName
				If Not result.runtimeAbiName.length And Not named.symbol.isImported Then
					result.runtimeAbiName = TCompilerDirectMethodAbi.OwnerAbiName(analysis.model, named.symbol)
				End If
				If named.symbol.kind = SYMBOL_INTERFACE Then
					result.runtimeKind = TEMPLATE_RUNTIME_INTERFACE
				Else If named.symbol.kind = SYMBOL_STRUCT Then
					result.runtimeKind = TEMPLATE_RUNTIME_STRUCT
					If options And options.applicationBuild And options.applicationIdentity.length And result.moduleName.ToLower() = options.applicationIdentity.ToLower() Then
						Local structOriginPath:String = named.symbol.originPath
						' A declaration owned by the source currently being compiled has no
						' imported originPath. Its syntax tree is the physical layout owner.
						If Not structOriginPath.length And analysis And analysis.syntaxTree And analysis.syntaxTree.source Then structOriginPath = analysis.syntaxTree.source.path
						Local sourceUnitPath:String = ApplicationSourceUnitPath(TCompilationSnapshotBuilder.InterfaceSourcePath(structOriginPath))
						If sourceUnitPath.length And result.runtimeAbiName.length Then plan.runtimeStructSourceUnits.Insert(result.runtimeAbiName.ToLower(), sourceUnitPath)
					End If
					If named.symbol.memberScope Then
						For Local member:TSymbol = EachIn named.symbol.memberScope.LookupLocal("=")
							If member.kind <> SYMBOL_ROUTINE Or member.parameters.length <> 1 Then Continue
							result.runtimeEqualityAbiName = member.externalName
							If Not result.runtimeEqualityAbiName.length And Not member.isImported Then result.runtimeEqualityAbiName = TCompilerAbiNamer.RoutineName(analysis.model, member, "")
							If result.runtimeEqualityAbiName.length And Not result.runtimeEqualityAbiName.StartsWith("_") Then result.runtimeEqualityAbiName = "_" + result.runtimeEqualityAbiName
							If result.runtimeEqualityAbiName.length Then Exit
						Next
					End If
				Else
					result.runtimeKind = TEMPLATE_RUNTIME_CLASS
					plan.runtimeArgumentSymbols.Insert(named.symbol, result.runtimeAbiName)
				End If
			End If
			' Reconstructed and nested constructed symbols do not always retain the
			' declaration's direct genericArity field. Closed type arguments still
			' provide an unambiguous canonical generic identity.
			If result.moduleName.length And (GenericTypeArity(named.symbol) > 0 Or named.typeArguments.length Or result.runtimeAbiName.length) Then Return result
		End If
		Return Null
	End Method

	Function GenericTypeArity:Int(symbol:TSymbol)
		If Not symbol Then Return 0
		Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
		If declaration And declaration.header Then Return declaration.header.genericParameters.length
		Return symbol.genericArity
	End Function

	Method TemplateSource:TTemplateSourceLocation(syntax:TSyntaxNode)
		If Not analysis Or Not analysis.model Then Return Null
		Return TCompilerGenericTemplateBuilder.SourceLocation(syntax, analysis.model)
	End Method

	Method AddDiagnostic(code:String, message:String, syntax:TSyntaxNode)
		Local source:TTemplateSourceLocation = TemplateSource(syntax)
		Local path:String
		Local span:TSourceSpan
		If source Then path = source.path
		If Not path.length And analysis And analysis.syntaxTree And analysis.syntaxTree.source Then path = analysis.syntaxTree.source.path
		If syntax Then span = syntax.span
		diagnostics :+ [TCompilerDiagnostic.Create(code, message, path, span)]
	End Method

	Method AddMessageDiagnostic(message:String, source:Object)
		Local separator:Int = message.Find(" ")
		Local code:String = "BMXC3049"
		Local text:String = message
		If separator > 0 Then
			code = message[..separator]
			text = message[separator + 1..]
		End If
		Local syntax:TSyntaxNode = TSyntaxNode(source)
		AddDiagnostic(code, text, syntax)
	End Method

	Method AddTemplateDiagnostic(code:String, message:String, source:TTemplateSourceLocation)
		Local path:String
		Local span:TSourceSpan
		If source Then
			path = source.path
			span = TSourceSpan.Create(source.start, source.length)
		End If
		diagnostics :+ [TCompilerDiagnostic.Create(code, message, path, span)]
	End Method

	Function ConditionalRevision:String(values:String[])
		Local sorted:String[] = values[..]
		For Local index:Int = 1 Until sorted.length
			Local value:String = sorted[index].ToLower()
			Local position:Int = index - 1
			While position >= 0 And sorted[position].ToLower() > value
				sorted[position + 1] = sorted[position]
				position :- 1
			Wend
			sorted[position + 1] = value
		Next
		Local canonical:String
		For Local value:String = EachIn sorted
			If canonical.length Then canonical :+ ","
			canonical :+ value.ToLower()
		Next
		Return TCompilerStableDigest.Sha256(canonical)
	End Function

	Function HasConditionalSymbol:Int(values:String[], name:String)
		For Local value:String = EachIn values
			If value.ToLower() = name.ToLower() Then Return True
		Next
		Return False
	End Function
End Type
