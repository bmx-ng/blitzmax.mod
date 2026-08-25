' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.StringBuilder
Import Collections.StringMap
Import Crypto.SHA256Digest
Import BlitzMax.Language
Import "abi_naming.bmx"

Const GENERIC_SPECIALIZATION_MANIFEST_VERSION:Int = 1
Const GENERIC_SPECIALIZATION_UNIT_POLICY_VERSION:Int = 107
Const GENERIC_SPECIALIZATION_OUTPUT_DIRECTORY:String = ".generics"

Const GENERIC_REQUEST_TYPE_USE:Int = 1
Const GENERIC_REQUEST_ALLOCATION:Int = 2
Const GENERIC_REQUEST_MEMBER_CALL:Int = 3
Const GENERIC_REQUEST_SIGNATURE:Int = 4
Const GENERIC_REQUEST_TRANSITIVE:Int = 5
Const GENERIC_REQUEST_INHERITANCE:Int = 6
Const GENERIC_REQUEST_INTERFACE:Int = 7
Const GENERIC_REQUEST_ROUTINE_CALL:Int = 8
Const GENERIC_REQUEST_LAYOUT:Int = 9
Const GENERIC_REQUEST_INTERFACE_METHOD_IMPLEMENTATION:Int = 10
Const GENERIC_REQUEST_ABSTRACT_METHOD_IMPLEMENTATION:Int = 11
Const GENERIC_REQUEST_ABI_REFERENCE:Int = 12
Const GENERIC_REQUEST_INITIALIZATION:Int = 13

' A malformed executable specialization graph must fail deterministically
' instead of creating an unbounded family of ever-more-nested instances.
Const GENERIC_SPECIALIZATION_MAX_EXPANSION_DEPTH:Int = 64

Const GENERIC_SPECIALIZATION_DECLARED:Int = 1
Const GENERIC_SPECIALIZATION_EXPANDING:Int = 2
Const GENERIC_SPECIALIZATION_BOUND:Int = 3
Const GENERIC_SPECIALIZATION_LOWERING:Int = 4
Const GENERIC_SPECIALIZATION_COMPLETE:Int = 5
Const GENERIC_SPECIALIZATION_FAILED:Int = 6

Type TCompilerGenericConfiguration
	Field languageLinkageRevision:String
	Field compilerIrRevision:String
	Field runtimeAbiRevision:String
	Field compilerBackendRevision:String
	Field targetPlatform:String
	Field targetArchitecture:String
	Field pointerWidth:Int
	Field buildMode:String
	Field applicationIdentity:String
	Field applicationType:String
	Field frameworkModule:String
	Field debugInstrumentation:Int
	Field gdbDebug:Int
	Field coverageInstrumentation:Int
	Field threadingMode:String
	Field exceptionMode:String
	Field garbageCollectorMode:String
	Field cpuMode:String
	Field fpuMode:String
	Field simdMode:String
	Field conditionalEnvironmentRevision:String
	' The planner fully populates configurations before registry construction.
	Field cachedSemanticIdentityConfiguration:String
	Field cachedCodeGenerationConfiguration:String

	Method SemanticIdentityConfiguration:String()
		If Not cachedSemanticIdentityConfiguration.length Then cachedSemanticIdentityConfiguration = "language=" + languageLinkageRevision.ToLower()
		Return cachedSemanticIdentityConfiguration
	End Method

	Method CodeGenerationConfiguration:String()
		If cachedCodeGenerationConfiguration.length Then Return cachedCodeGenerationConfiguration
		Local result:String = SemanticIdentityConfiguration()
		result :+ "|ir=" + compilerIrRevision.ToLower()
		result :+ "|runtime=" + runtimeAbiRevision.ToLower()
		result :+ "|backend=" + compilerBackendRevision.ToLower()
		result :+ "|target=" + targetPlatform.ToLower()
		result :+ "|arch=" + targetArchitecture.ToLower()
		result :+ "|ptr=" + pointerWidth
		result :+ "|mode=" + buildMode.ToLower()
		result :+ "|application-identity=" + applicationIdentity.ToLower()
		result :+ "|application=" + applicationType.ToLower()
		result :+ "|framework=" + frameworkModule.ToLower()
		result :+ "|debug=" + debugInstrumentation
		result :+ "|gdb=" + gdbDebug
		result :+ "|coverage=" + coverageInstrumentation
		result :+ "|threads=" + threadingMode.ToLower()
		result :+ "|exceptions=" + exceptionMode.ToLower()
		result :+ "|gc=" + garbageCollectorMode.ToLower()
		result :+ "|cpu=" + cpuMode.ToLower()
		result :+ "|fpu=" + fpuMode.ToLower()
		result :+ "|simd=" + simdMode.ToLower()
		result :+ "|conditions=" + conditionalEnvironmentRevision.ToLower()
		result :+ "|unit-policy=" + GENERIC_SPECIALIZATION_UNIT_POLICY_VERSION
		cachedCodeGenerationConfiguration = result
		Return cachedCodeGenerationConfiguration
	End Method
End Type

Type TCompilerDirectMethodAbi
	Function HasGenericMethod:Int(symbol:TSymbol)
		If Not symbol Or (symbol.kind <> SYMBOL_TYPE And symbol.kind <> SYMBOL_STRUCT) Or symbol.genericArity Or Not symbol.memberScope Then Return False
		For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
			If member.kind <> SYMBOL_ROUTINE Or member.genericArity <= 0 Then Continue
			Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(member.declaration)
			If declaration And declaration.isMethod Then Return True
		Next
		Return False
	End Function

	Function OwnerAbiName:String(model:TSemanticModel, symbol:TSymbol)
		If Not symbol Then Return ""
		If symbol.isImported Then Return symbol.externalName
		If model And model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC Then Return TCompilerAbiNamer.ClassName(model, symbol, "")
		Local compilationIdentity:String = symbol.originModule
		If Not compilationIdentity.length And model Then compilationIdentity = model.moduleName
		If Not compilationIdentity.length Then compilationIdentity = "source:" + symbol.originPath
		Local semanticIdentity:String = compilationIdentity.ToLower() + "::" + symbol.QualifiedName().ToLower()
		Local digest:String = TCompilerStableDigest.Sha256(semanticIdentity)
		Return "bmx_direct_" + TCompilerAbiNamer.Sanitize(symbol.QualifiedName().ToLower()) + "_" + digest[..16]
	End Function
End Type

Type TCompilerGenericInheritance
	Function ConstructedOwnerType:TNamedSemanticType(receiver:TSemanticType, owner:TSymbol, model:TSemanticModel, depth:Int = 0)
		If depth > 64 Or Not receiver Or Not owner Or Not model Then Return Null
		Local named:TNamedSemanticType = TNamedSemanticType(receiver)
		If Not named Or Not named.symbol Then Return Null
		If named.symbol = owner Then Return named
		Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not inheritance Then Return Null
		Local substitutions:TMap = TypeSubstitutions(named)
		For Local edge:TInheritanceEdge = EachIn inheritance.baseEdges + inheritance.interfaceEdges
			If Not edge Then Continue
			Local inheritedType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, substitutions)
			Local found:TNamedSemanticType = ConstructedOwnerType(inheritedType, owner, model, depth + 1)
			If found Then Return found
		Next
		Return Null
	End Function

	Function TypeSubstitutions:TMap(named:TNamedSemanticType)
		Local result:TMap = New TMap
		If Not named Or Not named.symbol Or Not named.symbol.memberScope Then Return result
		Local typeParameters:TSymbol[]
		For Local candidate:TSymbol = EachIn named.symbol.memberScope.declaredSymbols
			If candidate.kind = SYMBOL_TYPE_PARAMETER Then typeParameters :+ [candidate]
		Next
		For Local index:Int = 0 Until Min(typeParameters.length, named.typeArguments.length)
			result.Insert(typeParameters[index], named.typeArguments[index])
		Next
		Return result
	End Function
End Type

Type TCanonicalSpecializationKey
	Field templateIdentity:TGenericTemplateIdentity
	Field containingTypeArguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
	Field typeArguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
	Field languageIdentityConfiguration:String
	' Keys are fully populated before registry insertion and immutable after it.
	Field cachedCanonicalName:String

	Method CanonicalName:String()
		If cachedCanonicalName.length Then Return cachedCanonicalName
		Local result:String = templateIdentity.StableName()
		If containingTypeArguments.length Then
			result :+ "{"
			For Local index:Int = 0 Until containingTypeArguments.length
				If index Then result :+ ","
				result :+ containingTypeArguments[index].CanonicalName()
			Next
			result :+ "}"
		End If
		result :+ "<"
		For Local index:Int = 0 Until typeArguments.length
			If index Then result :+ ","
			result :+ typeArguments[index].CanonicalName()
		Next
		cachedCanonicalName = result + ">[" + languageIdentityConfiguration.ToLower() + "]"
		Return cachedCanonicalName
	End Method
End Type

Type TGenericSpecializationRequestSite
	Field requestingUnit:String
	Field reason:Int
	Field source:TTemplateSourceLocation
	' Request sites are populated before AddRequest and immutable thereafter.
	Field cachedCanonicalName:String

	Method CanonicalName:String()
		If cachedCanonicalName.length Then Return cachedCanonicalName
		Local result:String = requestingUnit.ToLower() + "|" + ReasonName()
		If source Then result :+ "|" + source.path + ":" + source.start + ":" + source.length
		cachedCanonicalName = result
		Return cachedCanonicalName
	End Method

	Method ReasonName:String()
		Select reason
			Case GENERIC_REQUEST_TYPE_USE Return "type-use"
			Case GENERIC_REQUEST_ALLOCATION Return "allocation"
			Case GENERIC_REQUEST_MEMBER_CALL Return "member-call"
			Case GENERIC_REQUEST_SIGNATURE Return "signature"
			Case GENERIC_REQUEST_TRANSITIVE Return "transitive-template"
			Case GENERIC_REQUEST_INHERITANCE Return "inheritance"
			Case GENERIC_REQUEST_INTERFACE Return "interface"
			Case GENERIC_REQUEST_ROUTINE_CALL Return "routine-call"
			Case GENERIC_REQUEST_LAYOUT Return "layout"
			Case GENERIC_REQUEST_INTERFACE_METHOD_IMPLEMENTATION Return "interface-method-implementation"
			Case GENERIC_REQUEST_ABSTRACT_METHOD_IMPLEMENTATION Return "abstract-method-implementation"
			Case GENERIC_REQUEST_ABI_REFERENCE Return "abi-reference"
			Case GENERIC_REQUEST_INITIALIZATION Return "initialization"
		End Select
		Return "unknown"
	End Method
End Type

Type TGenericSpecializationEdge
	Field source:TGenericSpecializationNode
	Field target:TGenericSpecializationNode
	Field request:TGenericSpecializationRequestSite
	' Edges are populated before AddEdge and immutable thereafter.
	Field cachedCanonicalName:String

	Method CanonicalName:String()
		If Not cachedCanonicalName.length Then cachedCanonicalName = source.key.CanonicalName() + "->" + target.key.CanonicalName() + "|" + request.CanonicalName()
		Return cachedCanonicalName
	End Method
End Type

Type TGenericSpecializationNode
	Field artifact:TGenericTemplateArtifact
	Field configuration:TCompilerGenericConfiguration
	Field key:TCanonicalSpecializationKey
	Field identityDigest:String
	Field readableAbiName:String
	Field state:Int = GENERIC_SPECIALIZATION_DECLARED
	Field requests:TGenericSpecializationRequestSite[] = New TGenericSpecializationRequestSite[0]
	Field outgoing:TGenericSpecializationEdge[] = New TGenericSpecializationEdge[0]
	Field incoming:TGenericSpecializationEdge[] = New TGenericSpecializationEdge[0]
	Field requestsByName:TStringMap = New TStringMap
	Field outgoingByName:TStringMap = New TStringMap
	Field incomingByName:TStringMap = New TStringMap
	Field declarationOwner:String = "application-generics"
	Field implementationOwner:String = "application-generics"
	Field generatedUnit:String
	Field generatedObject:String
	Field cacheKey:String
	Field applicationSourceOwned:Int
	' Application-owned quoted sources are not nominal modules. Their ordinary
	' declarations live in the quoted source header rather than a synthetic
	' application.mod hierarchy. The primary application source has no separate
	' header and therefore leaves this path empty.
	Field definingSourceUnitPath:String
	' Ordinary Struct arguments declared by quoted application sources retain
	' their physical layout owner separately from their canonical nominal
	' identity. This is application-plan metadata and is never serialized into
	' a published generic template.
	Field runtimeStructSourceUnits:TStringMap
	Field referenceScc:String
	Field debugInstrumentation:Int
	Field expansionDepth:Int = -1
	' Most generic Type methods remain eagerly specialized.  A method proven to
	' allocate a strictly larger closed form of its own Type is deferred until a
	' concrete call requests that exact closed body, preventing infinite
	' polymorphic-recursive specialization while preserving complete class slots.
	Field deferredMethodSignatures:TStringMap = New TStringMap
	Field requiredMethodSignatures:TStringMap = New TStringMap
	' Expansion revisits a node only when a newly required deferred method can
	' expose additional references. Avoid rebuilding and sorting a textual
	' processing identity on every registry scan.
	Field requiredMethodRevision:Int
	Field processedRequiredMethodRevision:Int = -1

	Method DeferMethod(signatureKey:String)
		If signatureKey.length Then deferredMethodSignatures.Insert(signatureKey, signatureKey)
	End Method

	Method RequireMethod(signatureKey:String)
		If Not signatureKey.length Or requiredMethodSignatures.Contains(signatureKey) Then Return
		requiredMethodSignatures.Insert(signatureKey, signatureKey)
		requiredMethodRevision :+ 1
	End Method

	Method IsMethodDeferred:Int(signatureKey:String)
		Return signatureKey.length And deferredMethodSignatures.Contains(signatureKey)
	End Method

	Method IsMethodRequired:Int(signatureKey:String)
		Return signatureKey.length And requiredMethodSignatures.Contains(signatureKey)
	End Method

	Method IsAbiReferenceOnly:Int()
		If Not requests.length Then Return False
		For Local request:TGenericSpecializationRequestSite = EachIn requests
			If Not request Or request.reason <> GENERIC_REQUEST_ABI_REFERENCE Then Return False
		Next
		Return True
	End Method

	Method AddRequest(request:TGenericSpecializationRequestSite)
		If Not request Then Return
		Local name:String = request.CanonicalName()
		If requestsByName.Contains(name) Then Return
		requestsByName.Insert(name, request)
		requests :+ [request]
	End Method

	Method AddEdge(edge:TGenericSpecializationEdge)
		If Not edge Then Return
		Local name:String = edge.CanonicalName()
		If outgoingByName.Contains(name) Then Return
		outgoingByName.Insert(name, edge)
		outgoing :+ [edge]
	End Method

	Method AddIncomingEdge(edge:TGenericSpecializationEdge)
		If Not edge Then Return
		Local name:String = edge.CanonicalName()
		If incomingByName.Contains(name) Then Return
		incomingByName.Insert(name, edge)
		incoming :+ [edge]
	End Method

	Method SortIncomingEdges()
		For Local index:Int = 1 Until incoming.length
			Local value:TGenericSpecializationEdge = incoming[index]
			Local position:Int = index - 1
			While position >= 0 And incoming[position].CanonicalName() > value.CanonicalName()
				incoming[position + 1] = incoming[position]
				position :- 1
			Wend
			incoming[position + 1] = value
		Next
	End Method

	Method SortRequests()
		For Local index:Int = 1 Until requests.length
			Local value:TGenericSpecializationRequestSite = requests[index]
			Local position:Int = index - 1
			While position >= 0 And requests[position].CanonicalName() > value.CanonicalName()
				requests[position + 1] = requests[position]
				position :- 1
			Wend
			requests[position + 1] = value
		Next
	End Method

	Method SortEdges()
		For Local index:Int = 1 Until outgoing.length
			Local value:TGenericSpecializationEdge = outgoing[index]
			Local position:Int = index - 1
			While position >= 0 And outgoing[position].CanonicalName() > value.CanonicalName()
				outgoing[position + 1] = outgoing[position]
				position :- 1
			Wend
			outgoing[position + 1] = value
		Next
	End Method
End Type

Type TGenericSpecializationRegistry
	Field configuration:TCompilerGenericConfiguration
	Field nodesByKey:TStringMap = New TStringMap
	Field nodes:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
	Field diagnostics:String[] = New String[0]
	Field cycleIndexes:TMap
	Field cycleLowLinks:TMap
	Field cycleOnStack:TMap
	Field cycleStack:TGenericSpecializationNode[]
	Field cycleNextIndex:Int
	Field cycleValid:Int

	Function Create:TGenericSpecializationRegistry(configuration:TCompilerGenericConfiguration)
		Local result:TGenericSpecializationRegistry = New TGenericSpecializationRegistry
		result.configuration = configuration
		Return result
	End Function

	Method Request:TGenericSpecializationNode(artifact:TGenericTemplateArtifact, typeArguments:TTemplateTypeReference[], request:TGenericSpecializationRequestSite, containingTypeArguments:TTemplateTypeReference[] = Null)
		If Not artifact Or Not artifact.identity Then
			AddDiagnostic("BMXC3001 generic specialization request has no template artifact")
			Return Null
		End If
		If artifact.formatVersion < GENERIC_TEMPLATE_MIN_READ_VERSION Or artifact.formatVersion > GENERIC_TEMPLATE_FORMAT_VERSION Then
			AddDiagnostic("BMXC3002 template '" + artifact.identity.StableName() + "' uses unsupported artifact version " + artifact.formatVersion)
			Return Null
		End If
		If typeArguments.length <> artifact.parameters.length Then
			AddDiagnostic("BMXC3003 template '" + artifact.identity.StableName() + "' expects " + artifact.parameters.length + " type arguments but received " + typeArguments.length)
			Return Null
		End If
		If containingTypeArguments.length <> artifact.containingParameters.length Then
			AddDiagnostic("BMXC3003 template '" + artifact.identity.StableName() + "' expects " + artifact.containingParameters.length + " containing-Type arguments but received " + containingTypeArguments.length)
			Return Null
		End If
		For Local argument:TTemplateTypeReference = EachIn typeArguments
			If Not argument Then
				AddDiagnostic("BMXC3003 template '" + artifact.identity.StableName() + "' received an unresolved type argument")
				Return Null
			End If
		Next
		Local key:TCanonicalSpecializationKey = New TCanonicalSpecializationKey
		key.templateIdentity = artifact.identity
		key.containingTypeArguments = containingTypeArguments
		key.typeArguments = typeArguments
		If configuration Then key.languageIdentityConfiguration = configuration.SemanticIdentityConfiguration()
		Local canonicalName:String = key.CanonicalName()
		Local existing:TGenericSpecializationNode = TGenericSpecializationNode(nodesByKey.ValueForKey(canonicalName))
		If existing Then
			If existing.artifact.EffectiveContentRevision() <> artifact.EffectiveContentRevision() Then
				AddDiagnostic("BMXC3004 specialization '" + canonicalName + "' was requested with conflicting template content revisions '" + existing.artifact.EffectiveContentRevision() + "' and '" + artifact.EffectiveContentRevision() + "'")
				existing.state = GENERIC_SPECIALIZATION_FAILED
			End If
			existing.AddRequest(request)
			Return existing
		End If
		Local result:TGenericSpecializationNode = New TGenericSpecializationNode
		result.artifact = artifact
		result.configuration = configuration
		result.key = key
		result.identityDigest = TCompilerStableDigest.Sha256(canonicalName)
		result.readableAbiName = ReadableAbiName(result)
		result.cacheKey = CacheKey(result)
		result.generatedUnit = GeneratedUnitPath(result)
		result.generatedObject = GENERIC_SPECIALIZATION_OUTPUT_DIRECTORY + "/objects/" + result.cacheKey + ".o"
		If configuration Then result.debugInstrumentation = configuration.debugInstrumentation
		result.AddRequest(request)
		nodesByKey.Insert(canonicalName, result)
		InsertNode(result, canonicalName)
		Return result
	End Method

	Method AddEdge:TGenericSpecializationEdge(source:TGenericSpecializationNode, target:TGenericSpecializationNode, request:TGenericSpecializationRequestSite)
		If Not source Or Not target Then Return Null
		Local edge:TGenericSpecializationEdge = New TGenericSpecializationEdge
		edge.source = source
		edge.target = target
		edge.request = request
		source.AddEdge(edge)
		target.AddIncomingEdge(edge)
		If source = target Then
			If Not request Or request.reason <> GENERIC_REQUEST_LAYOUT Then
				source.referenceScc = TCompilerStableDigest.Sha256(source.key.CanonicalName())
			End If
		End If
		Return edge
	End Method

	Method FinalizeOrdering()
		For Local node:TGenericSpecializationNode = EachIn nodes
			node.SortRequests()
			node.SortEdges()
			node.SortIncomingEdges()
		Next
	End Method

	Method ValidateCycles:Int()
		cycleIndexes = New TMap
		cycleLowLinks = New TMap
		cycleOnStack = New TMap
		cycleStack = New TGenericSpecializationNode[0]
		cycleNextIndex = 0
		cycleValid = True
		For Local node:TGenericSpecializationNode = EachIn nodes
			If Not cycleIndexes.Contains(node) Then StrongConnect(node)
		Next
		Local result:Int = cycleValid
		cycleIndexes = Null
		cycleLowLinks = Null
		cycleOnStack = Null
		cycleStack = New TGenericSpecializationNode[0]
		Return result
	End Method

	Method StrongConnect(node:TGenericSpecializationNode)
		Local nodeIndex:Int = cycleNextIndex
		cycleNextIndex :+ 1
		cycleIndexes.Insert(node, String(nodeIndex))
		cycleLowLinks.Insert(node, String(nodeIndex))
		cycleStack :+ [node]
		cycleOnStack.Insert(node, node)

		For Local edge:TGenericSpecializationEdge = EachIn node.outgoing
			If Not edge Or Not edge.target Then Continue
			Local target:TGenericSpecializationNode = edge.target
			If Not cycleIndexes.Contains(target) Then
				StrongConnect(target)
				Local targetLowLink:Int = Int(String(cycleLowLinks.ValueForKey(target)))
				Local nodeLowLink:Int = Int(String(cycleLowLinks.ValueForKey(node)))
				If targetLowLink < nodeLowLink Then cycleLowLinks.Insert(node, String(targetLowLink))
			Else If cycleOnStack.Contains(target) Then
				Local targetIndex:Int = Int(String(cycleIndexes.ValueForKey(target)))
				Local nodeLowLink:Int = Int(String(cycleLowLinks.ValueForKey(node)))
				If targetIndex < nodeLowLink Then cycleLowLinks.Insert(node, String(targetIndex))
			End If
		Next

		If Int(String(cycleLowLinks.ValueForKey(node))) <> nodeIndex Then Return
		Local members:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
		While cycleStack.length
			Local lastIndex:Int = cycleStack.length - 1
			Local member:TGenericSpecializationNode = cycleStack[lastIndex]
			cycleStack = cycleStack[..lastIndex]
			cycleOnStack.Remove(member)
			members :+ [member]
			If member = node Then Exit
		Wend
		ValidateCycleComponent(members)
	End Method

	Method ValidateCycleComponent(members:TGenericSpecializationNode[])
		If Not members.length Then Return
		Local selfCycle:Int
		If members.length = 1 Then
			For Local edge:TGenericSpecializationEdge = EachIn members[0].outgoing
				If edge.target = members[0] Then selfCycle = True; Exit
			Next
			If Not selfCycle Then Return
		End If
		Local identities:String[] = New String[members.length]
		For Local index:Int = 0 Until members.length
			identities[index] = members[index].key.CanonicalName()
		Next
		SortDependencyIdentities(identities)
		Local identity:String
		For Local value:String = EachIn identities
			If identity.length Then identity :+ "|"
			identity :+ value
		Next
		Local sccIdentity:String = TCompilerStableDigest.Sha256(identity)
		If CycleRequiresLayout(members) Then
			AddDiagnostic("BMXC3008 recursive by-value specialization layout is unsupported: " + identity)
			For Local member:TGenericSpecializationNode = EachIn members
				member.state = GENERIC_SPECIALIZATION_FAILED
			Next
			cycleValid = False
		Else If CycleRequiresInitialization(members) Then
			AddDiagnostic("BMXC3091 cyclic generic static initialization is unsupported: " + identity)
			For Local member:TGenericSpecializationNode = EachIn members
				member.state = GENERIC_SPECIALIZATION_FAILED
			Next
			cycleValid = False
		Else
			For Local member:TGenericSpecializationNode = EachIn members
				member.referenceScc = sccIdentity
			Next
		End If
	End Method

	Method CycleRequiresInitialization:Int(members:TGenericSpecializationNode[])
		Local memberKeys:TMap = New TMap
		For Local member:TGenericSpecializationNode = EachIn members
			memberKeys.Insert(member.key.CanonicalName(), member)
		Next
		For Local member:TGenericSpecializationNode = EachIn members
			For Local edge:TGenericSpecializationEdge = EachIn member.outgoing
				If edge And edge.request And edge.request.reason = GENERIC_REQUEST_INITIALIZATION And memberKeys.Contains(edge.target.key.CanonicalName()) Then Return True
			Next
		Next
		Return False
	End Method

	Method CycleRequiresLayout:Int(members:TGenericSpecializationNode[])
		Local memberKeys:TMap = New TMap
		For Local member:TGenericSpecializationNode = EachIn members
			memberKeys.Insert(member.key.CanonicalName(), member)
		Next
		For Local member:TGenericSpecializationNode = EachIn members
			For Local edge:TGenericSpecializationEdge = EachIn member.outgoing
				If edge And edge.request And edge.request.reason = GENERIC_REQUEST_LAYOUT And memberKeys.Contains(edge.target.key.CanonicalName()) Then Return True
			Next
		Next
		Return False
	End Method

	Method Reachable:Int(source:TGenericSpecializationNode, target:TGenericSpecializationNode, visited:TMap)
		If Not source Or Not target Then Return False
		If visited.Contains(source.key.CanonicalName()) Then Return False
		visited.Insert(source.key.CanonicalName(), source)
		For Local edge:TGenericSpecializationEdge = EachIn source.outgoing
			If edge.target = target Then Return True
			If Reachable(edge.target, target, visited) Then Return True
		Next
		Return False
	End Method

	Method Manifest:String()
		FinalizeOrdering()
		Local result:TStringBuilder = New TStringBuilder(4096)
		result.Append("generic-specializations ").Append(GENERIC_SPECIALIZATION_MANIFEST_VERSION).Append("~n")
		For Local node:TGenericSpecializationNode = EachIn nodes
			result.Append("specialization ").Append(node.identityDigest).Append("~n")
			result.Append("  key ").Append(node.key.CanonicalName()).Append("~n")
			result.Append("  template ").Append(node.artifact.identity.StableName()).Append("~n")
			result.Append("  content-revision ").Append(node.artifact.EffectiveContentRevision()).Append("~n")
			result.Append("  containing-arguments")
			For Local argument:TTemplateTypeReference = EachIn node.key.containingTypeArguments
				result.Append(" ").Append(argument.CanonicalName())
			Next
			result.Append("~n")
			result.Append("  arguments")
			For Local argument:TTemplateTypeReference = EachIn node.key.typeArguments
				result.Append(" ").Append(argument.CanonicalName())
			Next
			result.Append("~n")
			result.Append("  declaration-owner ").Append(node.declarationOwner).Append("~n")
			result.Append("  implementation-owner ").Append(node.implementationOwner).Append("~n")
			result.Append("  generated-unit ").Append(node.generatedUnit).Append("~n")
			result.Append("  generated-object ").Append(node.generatedObject).Append("~n")
			result.Append("  cache-key ").Append(node.cacheKey).Append("~n")
			If node.referenceScc.length Then result.Append("  reference-scc ").Append(node.referenceScc).Append("~n")
			For Local signatureKey:String = EachIn RequiredDeferredMethods(node)
				result.Append("  required-method ").Append(signatureKey).Append("~n")
			Next
			For Local request:TGenericSpecializationRequestSite = EachIn node.requests
				result.Append("  request ").Append(request.CanonicalName()).Append("~n")
			Next
			For Local edge:TGenericSpecializationEdge = EachIn node.outgoing
				result.Append("  edge ").Append(edge.target.identityDigest).Append(" ").Append(edge.request.CanonicalName()).Append("~n")
			Next
		Next
		Return result.ToString()
	End Method

	Method CacheKey:String(node:TGenericSpecializationNode)
		Local value:TStringBuilder = New TStringBuilder(256)
		value.Append("cache-format=2|template=").Append(node.artifact.EffectiveContentRevision())
		value.Append("|specialization=").Append(node.key.CanonicalName())
		If node.applicationSourceOwned Then value.Append("|application-source-owned=1")
		If node.definingSourceUnitPath.length Then value.Append("|defining-source-unit=").Append(node.definingSourceUnitPath.ToLower())
		For Local sourceUnit:String = EachIn RuntimeStructSourceUnitIdentities(node)
			value.Append("|runtime-struct-source-unit=").Append(sourceUnit)
		Next
		If configuration Then value.Append("|").Append(configuration.CodeGenerationConfiguration())
		Return TCompilerStableDigest.Sha256(value.ToString())
	End Method

	Function GeneratedUnitPath:String(node:TGenericSpecializationNode)
		If Not node Then Return ""
		' The canonical identity controls the public ABI, but the C text also
		' varies with target, build mode, instrumentation and transitive layout.
		' The finalized code-generation key already hashes the canonical
		' specialization name together with every code-generation input. Keep the
		' full semantic identity in the manifest and ABI model, while addressing
		' physical sources by the same single key already used for their objects.
		Return GENERIC_SPECIALIZATION_OUTPUT_DIRECTORY + "/units/" + node.cacheKey + ".c"
	End Function

	' Final implementation identity includes every transitive specialization
	' whose ABI/layout can affect the generated unit. Initial request keys are
	' useful placeholders; only these closed keys may address object or backend
	' caches.
	Method FinalizeCacheKeys()
		Local finalizedUnits:TMap = New TMap
		For Local node:TGenericSpecializationNode = EachIn nodes
			Local previousUnit:String = node.generatedUnit
			Local dependencies:String[] = New String[0]
			Local visited:TMap = New TMap
			visited.Insert(DependencyIdentity(node), node)
			CollectDependencies(node, visited, dependencies)
			SortDependencyIdentities(dependencies)
			Local value:TStringBuilder = New TStringBuilder(512)
			value.Append("cache-format=2|template=").Append(node.artifact.EffectiveContentRevision())
			value.Append("|specialization=").Append(node.key.CanonicalName())
			If node.applicationSourceOwned Then value.Append("|application-source-owned=1")
			If node.definingSourceUnitPath.length Then value.Append("|defining-source-unit=").Append(node.definingSourceUnitPath.ToLower())
			For Local sourceUnit:String = EachIn RuntimeStructSourceUnitIdentities(node)
				value.Append("|runtime-struct-source-unit=").Append(sourceUnit)
			Next
			If configuration Then value.Append("|").Append(configuration.CodeGenerationConfiguration())
			For Local signatureKey:String = EachIn RequiredDeferredMethods(node)
				value.Append("|required-method=").Append(signatureKey)
			Next
			For Local dependency:String = EachIn dependencies
				value.Append("|dependency=").Append(dependency)
			Next
			node.cacheKey = TCompilerStableDigest.Sha256(value.ToString())
			node.generatedUnit = GeneratedUnitPath(node)
			node.generatedObject = GENERIC_SPECIALIZATION_OUTPUT_DIRECTORY + "/objects/" + node.cacheKey + ".o"
			If previousUnit <> node.generatedUnit Then finalizedUnits.Insert(previousUnit, node.generatedUnit)
		Next
		' Transitive request provenance is recorded while the graph is being
		' expanded, before dependency closure can produce the final cache key.
		' Retarget those request records to the finalized physical owner unit.
		For Local node:TGenericSpecializationNode = EachIn nodes
			For Local request:TGenericSpecializationRequestSite = EachIn node.requests
				Local finalizedUnit:String = String(finalizedUnits.ValueForKey(request.requestingUnit))
				If finalizedUnit.length Then request.requestingUnit = finalizedUnit
			Next
		Next
	End Method

	Function RequiredDeferredMethods:String[](node:TGenericSpecializationNode)
		Local result:String[] = New String[0]
		If Not node Then Return result
		For Local signatureKey:String = EachIn node.requiredMethodSignatures.Keys()
			If node.deferredMethodSignatures.Contains(signatureKey) Then result :+ [signatureKey]
		Next
		SortDependencyIdentities(result)
		Return result
	End Function

	Function RuntimeStructSourceUnitIdentities:String[](node:TGenericSpecializationNode)
		Local result:String[] = New String[0]
		If Not node Or Not node.runtimeStructSourceUnits Then Return result
		For Local key:String = EachIn node.runtimeStructSourceUnits.Keys()
			result :+ [key.ToLower() + "=" + String(node.runtimeStructSourceUnits.ValueForKey(key)).ToLower()]
		Next
		SortDependencyIdentities(result)
		Return result
	End Function

	Method CollectDependencies(source:TGenericSpecializationNode, visited:TMap, dependencies:String[] Var)
		For Local edge:TGenericSpecializationEdge = EachIn source.outgoing
			Local identity:String = DependencyIdentity(edge.target)
			If visited.Contains(identity) Then Continue
			visited.Insert(identity, edge.target)
			dependencies :+ [identity]
			CollectDependencies(edge.target, visited, dependencies)
		Next
	End Method

	Function DependencyIdentity:String(node:TGenericSpecializationNode)
		Return node.key.CanonicalName() + "@" + node.artifact.EffectiveContentRevision()
	End Function

	Function SortDependencyIdentities(values:String[])
		For Local index:Int = 1 Until values.length
			Local value:String = values[index]
			Local position:Int = index - 1
			While position >= 0 And values[position] > value
				values[position + 1] = values[position]
				position :- 1
			Wend
			values[position + 1] = value
		Next
	End Function

	Method ReadableAbiName:String(node:TGenericSpecializationNode)
		Return ReadableAbiNameFor(node.artifact, node.key, node.identityDigest)
	End Method

	Function ReadableAbiNameFor:String(artifact:TGenericTemplateArtifact, key:TCanonicalSpecializationKey, identityDigest:String)
		If Not artifact Or Not artifact.identity Or Not key Then Return ""
		' Module names are case-insensitive language identities.  Imported .i
		' snapshots normalize them, while a source request may retain display
		' casing; never let that presentation difference change C ownership.
		Local readable:String = artifact.identity.moduleName.ToLower() + "_" + artifact.identity.qualifiedName
		For Local argument:TTemplateTypeReference = EachIn key.containingTypeArguments
			readable :+ "_owner_" + argument.CanonicalName()
		Next
		For Local argument:TTemplateTypeReference = EachIn key.typeArguments
			readable :+ "_" + argument.CanonicalName()
		Next
		Return "bmx_gen_" + TCompilerAbiNamer.Sanitize(readable) + "_" + identityDigest[..32]
	End Function

	Method InsertNode(value:TGenericSpecializationNode, canonicalName:String)
		nodes :+ [value]
		Local position:Int = nodes.length - 2
		While position >= 0 And nodes[position].key.CanonicalName() > canonicalName
			nodes[position + 1] = nodes[position]
			position :- 1
		Wend
		nodes[position + 1] = value
	End Method

	Method AddDiagnostic(message:String)
		For Local existing:String = EachIn diagnostics
			If existing = message Then Return
		Next
		diagnostics :+ [message]
	End Method
End Type

Type TCompilerStableDigest
	Function Sha256:String(value:String)
		Local digest:TSHA256 = New TSHA256
		Return digest.Digest(value).ToLower()
	End Function

	Function Sha256MaterializedText:String(value:String)
		' Compiler outputs are written by SaveText's default LATIN1 path. Hash
		' those exact bytes rather than Digest(String), which hashes UTF-8 and
		' diverges as soon as an emitted interface contains a non-ASCII byte.
		Local bytes:Byte[] = New Byte[value.length]
		For Local index:Int = 0 Until value.length
			bytes[index] = Byte(value[index])
		Next
		Local digest:TSHA256 = New TSHA256
		If bytes.length Then digest.Update(bytes, bytes.length)
		Local result:Byte[] = New Byte[digest.OutBytes()]
		digest.Finish(result)
		Local hex:String = "0123456789abcdef"
		Local output:String
		For Local value:Byte = EachIn result
			output :+ Chr(hex[(Int(value) Shr 4) & 15]) + Chr(hex[Int(value) & 15])
		Next
		Return output
	End Function
End Type

Type TCompilerGenericFieldIr
	Field name:String
	Field abiName:String
	Field visibility:Int
	Field metadata:TGenericTemplateMetadataEntry[] = New TGenericTemplateMetadataEntry[0]
	Field isThreadedGlobal:Int
	Field semanticType:TTemplateTypeReference
	Field initializer:TGenericTemplateNode
	Field source:TTemplateSourceLocation
	Field declaringSpecialization:TGenericSpecializationNode
End Type

Type TCompilerGenericClosureCaptureIr
	Field name:String
	Field abiName:String
	Field semanticType:TTemplateTypeReference
	Field isParameter:Int
	Field isSelf:Int
	Field activationIdentity:String
	Field source:TTemplateSourceLocation
End Type

Type TCompilerGenericClosureEnvironmentIr
	Field abiName:String
	Field localName:String
	Field parent:TCompilerGenericClosureEnvironmentIr
	Field parentFieldName:String
	Field activationIdentity:String
	Field captures:TCompilerGenericClosureCaptureIr[] = New TCompilerGenericClosureCaptureIr[0]
	Field capturesByName:TStringMap = New TStringMap
End Type

Type TCompilerGenericCoverageFunction
	Field name:String
	Field source:TTemplateSourceLocation
End Type

Type TCompilerGenericCoverageFile
	Field path:String
	Field lines:Int[] = New Int[0]
	Field functions:TCompilerGenericCoverageFunction[] = New TCompilerGenericCoverageFunction[0]
End Type

Type TCompilerGenericMethodIr
	Field name:String
	Field debugName:String
	Field coverageName:String
	Field closureDebugOwnerName:String
	Field abiName:String
	Field signatureKey:String
	Field slotName:String
	Field visibility:Int
	Field metadata:TGenericTemplateMetadataEntry[] = New TGenericTemplateMetadataEntry[0]
	Field returnType:TTemplateTypeReference
	Field receiverType:TTemplateTypeReference
	Field receiverIsStruct:Int
	Field isStatic:Int
	Field isTypeFunction:Int
	Field parameters:TGenericTemplateValueParameter[] = New TGenericTemplateValueParameter[0]
	Field body:TGenericTemplateNode
	Field source:TTemplateSourceLocation
	Field declaringSpecialization:TGenericSpecializationNode
	Field delegatedConstructor:TCompilerGenericMethodIr
	Field delegatedConstructorSpecialization:TGenericSpecializationNode
	Field delegationArguments:TGenericTemplateNode[] = New TGenericTemplateNode[0]
	' A parameterized constructor inherited without a derived declaration needs
	' a derived allocation helper whose initializer forwards the same closed
	' arguments into the selected base initializer.
	Field isInheritedConstructorForwarder:Int
	Field localRoutineOwnerAbiName:String
	Field interfaceMethodKind:Int
	Field incomingClosureEnvironment:TCompilerGenericClosureEnvironmentIr
	Field closureEnvironment:TCompilerGenericClosureEnvironmentIr
	Field activationClosureEnvironments:TStringMap = New TStringMap
	Field closureEnvironments:TCompilerGenericClosureEnvironmentIr[] = New TCompilerGenericClosureEnvironmentIr[0]
	Field closureCaptures:TCompilerGenericClosureCaptureIr[] = New TCompilerGenericClosureCaptureIr[0]
	Field isClosureInvoke:Int
	Field isDeferredStub:Int
	Field isDestructor:Int
	Field isIteratorRoutine:Int
	Field iteratorOwnsResources:Int
	Field iteratorRetainedCleanupIdentities:TMap = New TMap
	Field iteratorStateAbiName:String
	Field iteratorStateExpression:String
	Field iteratorSelfExpression:String
End Type

Type TCompilerGenericSpecializationIr
	Field specialization:TGenericSpecializationNode
	Field isRoutine:Int
	Field isInterface:Int
	Field isStruct:Int
	Field routine:TCompilerGenericMethodIr
	Field baseSpecialization:TGenericSpecializationNode
	Field inheritedInterfaces:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
	' Closed ordinary Interface parents have published runtime ABIs but no
	' specialization graph node. Retain them separately so typed IR can link the
	' mixed generic/ordinary inheritance graph without changing template identity.
	Field inheritedRuntimeInterfaces:TTemplateTypeReference[] = New TTemplateTypeReference[0]
	Field fields:TCompilerGenericFieldIr[] = New TCompilerGenericFieldIr[0]
	Field staticFields:TCompilerGenericFieldIr[] = New TCompilerGenericFieldIr[0]
	Field methods:TCompilerGenericMethodIr[] = New TCompilerGenericMethodIr[0]
	Field constructor:TCompilerGenericMethodIr
	Field constructors:TCompilerGenericMethodIr[] = New TCompilerGenericMethodIr[0]
	Field declaredFieldStart:Int
	Field declaredFieldCount:Int
	Field implementedInterfaces:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
	Field implementedRuntimeInterfaces:TTemplateTypeReference[] = New TTemplateTypeReference[0]
	Field referencedSpecializations:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
	' Closed direct method bodies selected by an Interface-owned routine
	' dispatcher. They are also ordinary referenced specializations, but this
	' narrower list retains the semantic ownership of the dispatch edges.
	Field dispatcherImplementations:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
	' Closed dispatchers which select this routine as an implementation.  The
	' implementation unit owns the adapters and module-registration hook.
	Field dynamicDispatchers:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
	Field referencedTypesByCanonicalName:TStringMap = New TStringMap
	Field coverageFiles:TCompilerGenericCoverageFile[] = New TCompilerGenericCoverageFile[0]

	Method Dump:String()
		Local result:String = "generic-specialization " + specialization.identityDigest + " " + specialization.key.CanonicalName() + "~n"
		result :+ "  class " + specialization.readableAbiName + "~n"
		For Local referenced:TGenericSpecializationNode = EachIn referencedSpecializations
			result :+ "  reference " + referenced.identityDigest + " " + referenced.readableAbiName + "~n"
		Next
		For Local irField:TCompilerGenericFieldIr = EachIn fields
			result :+ "  field " + irField.name + ":" + irField.semanticType.CanonicalName() + " [" + irField.abiName + "]~n"
		Next
		For Local irField:TCompilerGenericFieldIr = EachIn staticFields
			result :+ "  static " + irField.name + ":" + irField.semanticType.CanonicalName() + " [" + irField.abiName + "]"
			If irField.isThreadedGlobal Then result :+ " [threaded]"
			result :+ "~n"
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn methods
			result :+ "  method " + irMethod.name + ":" + irMethod.returnType.CanonicalName() + " [" + irMethod.abiName + "]~n"
			If irMethod.closureEnvironment Then result :+ "    closure-environment " + irMethod.closureEnvironment.abiName + " captures " + irMethod.closureEnvironment.captures.length + "~n"
		Next
		If routine And routine.closureEnvironment Then result :+ "  closure-environment " + routine.closureEnvironment.abiName + " captures " + routine.closureEnvironment.captures.length + "~n"
		If routine And specialization And specialization.artifact And (specialization.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Or (specialization.artifact.isMethod And Not routine.body)) Then
			result :+ "  dynamic-registration " + routine.abiName + "_register_dynamic~n"
		End If
		For Local dispatcher:TGenericSpecializationNode = EachIn dynamicDispatchers
			result :+ "  dynamic-implementation " + dispatcher.identityDigest + " owner " + specialization.implementationOwner + " hook " + TCompilerGenericCUnitEmitter.DynamicImplementationRegistrationName(Self) + "~n"
		Next
		For Local coverageFile:TCompilerGenericCoverageFile = EachIn coverageFiles
			result :+ "  coverage-file " + coverageFile.path + "~n"
			For Local line:Int = EachIn coverageFile.lines
				result :+ "    coverage-line " + line + "~n"
			Next
			For Local coverageFunction:TCompilerGenericCoverageFunction = EachIn coverageFile.functions
				result :+ "    coverage-function " + coverageFunction.source.line + " " + coverageFunction.name + "~n"
			Next
		Next
		Return result
	End Method
End Type

Type TCompilerGenericSpecializationLowerer
	Function ReceiverTypeForSpecialization:TTemplateTypeReference(node:TGenericSpecializationNode)
		If Not node Or Not node.artifact Or Not node.artifact.identity Then Return Null
		Local result:TTemplateTypeReference = New TTemplateTypeReference
		result.kind = TEMPLATE_TYPE_NAMED
		result.moduleName = node.artifact.identity.moduleName
		result.symbolName = node.artifact.identity.qualifiedName
		result.arguments = node.key.typeArguments
		result.runtimeAbiName = node.readableAbiName
		Select node.artifact.typeDeclarationKind
			Case GENERIC_TYPE_DECLARATION_STRUCT
				result.runtimeKind = TEMPLATE_RUNTIME_STRUCT
			Case GENERIC_TYPE_DECLARATION_INTERFACE
				result.runtimeKind = TEMPLATE_RUNTIME_INTERFACE
			Default
				result.runtimeKind = TEMPLATE_RUNTIME_CLASS
		End Select
		Return result
	End Function

	Function Lower:TCompilerGenericSpecializationIr(node:TGenericSpecializationNode, diagnostics:String[] Var)
		If Not node Or Not node.artifact Then
			diagnostics :+ ["BMXC3010 canonical specialization node is required for lowering"]
			Return Null
		End If
		Local result:TCompilerGenericSpecializationIr = New TCompilerGenericSpecializationIr
		result.specialization = node
		result.isRoutine = node.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE
		result.isInterface = node.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE
		result.isStruct = node.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT
		IndexReferencedSpecializations(result)
		For Local edge:TGenericSpecializationEdge = EachIn node.outgoing
			If edge And edge.target And edge.request And (edge.request.reason = GENERIC_REQUEST_INTERFACE_METHOD_IMPLEMENTATION Or edge.request.reason = GENERIC_REQUEST_ABSTRACT_METHOD_IMPLEMENTATION) Then result.dispatcherImplementations :+ [edge.target]
		Next
		For Local edge:TGenericSpecializationEdge = EachIn node.incoming
			If edge And edge.source And edge.request And (edge.request.reason = GENERIC_REQUEST_INTERFACE_METHOD_IMPLEMENTATION Or edge.request.reason = GENERIC_REQUEST_ABSTRACT_METHOD_IMPLEMENTATION) Then result.dynamicDispatchers :+ [edge.source]
		Next
		node.state = GENERIC_SPECIALIZATION_LOWERING
		If result.isRoutine Then
			LowerRoutine(result, diagnostics)
			BuildClosureEnvironment(result.routine, result, diagnostics)
		Else If result.isInterface Then
			result.inheritedInterfaces = DirectInterfaceParents(node)
			result.inheritedRuntimeInterfaces = DirectRuntimeInterfaceParents(node, result)
			Local expectedParentCount:Int = node.artifact.interfaces.length
			If node.artifact.baseType Then expectedParentCount :+ 1
			If result.inheritedInterfaces.length + result.inheritedRuntimeInterfaces.length <> expectedParentCount Then
				diagnostics :+ ["BMXC3017 generic Interface inheritance has no canonical specialization graph target"]
				node.state = GENERIC_SPECIALIZATION_FAILED
			End If
			result.methods = EffectiveInterfaceMethods(node, result, diagnostics)
		Else If result.isStruct Then
			If node.artifact.baseType Or node.artifact.interfaces.length Then
				diagnostics :+ ["BMXC3019 generic Struct specialization cannot inherit or implement Interfaces"]
				node.state = GENERIC_SPECIALIZATION_FAILED
			End If
		Else If node.artifact.interfaces.length Then
			Local directInterfaces:TGenericSpecializationNode[] = InterfaceTargets(node)
			result.implementedRuntimeInterfaces = DirectRuntimeInterfaceParents(node, result)
			If directInterfaces.length + result.implementedRuntimeInterfaces.length <> node.artifact.interfaces.length Then
				diagnostics :+ ["BMXC3017 generic Interface implementation has no canonical specialization graph target"]
				node.state = GENERIC_SPECIALIZATION_FAILED
			End If
			result.implementedInterfaces = InterfaceClosure(directInterfaces, diagnostics)
			AppendInheritedRuntimeInterfaces(result, result.implementedInterfaces)
			For Local interfaceNode:TGenericSpecializationNode = EachIn result.implementedInterfaces
				AddReferencedSpecialization(result, interfaceNode)
			Next
		End If
		If Not result.isRoutine And Not result.isInterface And node.artifact.baseType Then
			result.baseSpecialization = InheritanceTarget(node)
			If Not result.baseSpecialization Then
				diagnostics :+ ["BMXC3018 generic base Type has no canonical specialization graph target"]
				node.state = GENERIC_SPECIALIZATION_FAILED
			End If
			If result.baseSpecialization Then
				Local inheritedClassInterfaces:TGenericSpecializationNode[] = ClassInterfaceTargets(result.baseSpecialization)
				result.implementedInterfaces = InterfaceClosure(result.implementedInterfaces + inheritedClassInterfaces, diagnostics)
				AppendInheritedRuntimeInterfaces(result, result.implementedInterfaces)
				For Local interfaceNode:TGenericSpecializationNode = EachIn result.implementedInterfaces
					AddReferencedSpecialization(result, interfaceNode)
				Next
			End If
		End If
		If Not result.isRoutine And Not result.isInterface Then AppendMembers(result, node, New TMap, diagnostics)
		If Not result.isRoutine And Not result.isInterface And Not result.isStruct Then InheritTypeConstructors(result, diagnostics)
		If Not result.isRoutine And Not result.isInterface Then FinalizeMethodAbiNames(result)
		If result.isStruct Then
			FinalizeStructConstructors(result, diagnostics)
		Else If Not result.isRoutine And Not result.isInterface And result.constructors.length Then
			FinalizeTypeConstructor(result, diagnostics)
		End If
		If Not result.isRoutine And Not result.isInterface Then
			For Local constructor:TCompilerGenericMethodIr = EachIn result.constructors
				BuildClosureEnvironment(constructor, result, diagnostics)
			Next
			For Local method:TCompilerGenericMethodIr = EachIn result.methods
				BuildClosureEnvironment(method, result, diagnostics)
			Next
		End If
		If Not result.isRoutine And Not result.isInterface Then ValidateInterfaceImplementations(result, diagnostics)
		If node.state <> GENERIC_SPECIALIZATION_FAILED Then node.state = GENERIC_SPECIALIZATION_COMPLETE
		Return result
	End Function

	Function AppendInheritedRuntimeInterfaces(ir:TCompilerGenericSpecializationIr, interfaces:TGenericSpecializationNode[])
		If Not ir Then Return
		For Local interfaceNode:TGenericSpecializationNode = EachIn interfaces
			For Local runtimeInterface:TTemplateTypeReference = EachIn DirectRuntimeInterfaceParents(interfaceNode, ir)
				AppendRuntimeInterface(ir.implementedRuntimeInterfaces, runtimeInterface)
			Next
		Next
	End Function

	Function AppendRuntimeInterface(values:TTemplateTypeReference[] Var, candidate:TTemplateTypeReference)
		If Not candidate Or Not candidate.runtimeAbiName.length Then Return
		For Local existing:TTemplateTypeReference = EachIn values
			If existing.runtimeAbiName.ToLower() = candidate.runtimeAbiName.ToLower() Then Return
		Next
		values :+ [candidate]
	End Function

	Function CollectClosureCaptureNodes(node:TGenericTemplateNode, captures:TGenericTemplateNode[] Var)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL And node.children.length = 3 Then
			Local captureBlock:TGenericTemplateNode = node.children[1]
			If captureBlock And captureBlock.kind = TEMPLATE_NODE_BLOCK And captureBlock.valueText = "closure-literal-captures" Then captures :+ captureBlock.children
			Return
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectClosureCaptureNodes(child, captures)
		Next
	End Function

	Function BuildClosureEnvironment(routine:TCompilerGenericMethodIr, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not routine Or Not routine.body Or routine.closureEnvironment Then Return
		Local captureNodes:TGenericTemplateNode[]
		CollectClosureCaptureNodes(routine.body, captureNodes)
		If Not captureNodes.length Then Return
		Local environment:TCompilerGenericClosureEnvironmentIr = New TCompilerGenericClosureEnvironmentIr
		Local ownerName:String = routine.localRoutineOwnerAbiName
		If Not ownerName.length Then ownerName = routine.abiName
		environment.abiName = TCompilerAbiNamer.Sanitize(ownerName + "_closure_environment")
		environment.localName = "bmx_closure_environment"
		For Local captureNode:TGenericTemplateNode = EachIn captureNodes
			If Not captureNode Or captureNode.kind <> TEMPLATE_NODE_DECLARATION Or (captureNode.identity <> "closure-capture-local" And captureNode.identity <> "closure-capture-parameter" And captureNode.identity <> "closure-capture-self") Or Not captureNode.valueText.length Or Not captureNode.semanticType Then
				diagnostics :+ ["BMXC1243 generic Closure literal has an invalid canonical capture record"]
				Continue
			End If
			Local key:String = captureNode.valueText.ToLower()
			Local existing:TCompilerGenericClosureCaptureIr = TCompilerGenericClosureCaptureIr(environment.capturesByName.ValueForKey(key))
			If existing Then
				Local sameDeclaration:Int = existing.isSelf And captureNode.identity = "closure-capture-self"
				If Not sameDeclaration Then sameDeclaration = existing.source And captureNode.source And existing.source.start = captureNode.source.start
				If Not sameDeclaration Or existing.semanticType.CanonicalName() <> captureNode.semanticType.CanonicalName() Or existing.isParameter <> (captureNode.identity = "closure-capture-parameter") Or existing.isSelf <> (captureNode.identity = "closure-capture-self") Then diagnostics :+ ["BMXC1243 generic Closure capture '" + captureNode.valueText + "' is ambiguous across distinct lexical declarations"]
				Continue
			End If
			' Loop- and Catch-owned cells are planned by the C-unit closure hierarchy,
			' where the environment can be allocated for each executed activation.
			If TCompilerGenericCUnitEmitter.InnermostActivationContainingSource(routine.body, captureNode.source) Then Continue
			If captureNode.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Or Not SupportedType(captureNode.semanticType, ir) Then
				diagnostics :+ ["BMXC1243 generic Closure capture '" + captureNode.valueText + "' has no supported managed-environment ABI"]
				Continue
			End If
			Local capture:TCompilerGenericClosureCaptureIr = New TCompilerGenericClosureCaptureIr
			capture.name = captureNode.valueText
			capture.abiName = TCompilerAbiNamer.Sanitize("capture_" + capture.name + "_" + TCompilerStableDigest.Sha256(key + ":" + captureNode.semanticType.CanonicalName())[..12])
			capture.semanticType = captureNode.semanticType
			capture.isParameter = captureNode.identity = "closure-capture-parameter"
			capture.isSelf = captureNode.identity = "closure-capture-self"
			capture.source = captureNode.source
			environment.captures :+ [capture]
			environment.capturesByName.Insert(key, capture)
		Next
		If environment.captures.length Then routine.closureEnvironment = environment
	End Function

	Function FinalizeMethodAbiNames(ir:TCompilerGenericSpecializationIr)
		If Not ir Then Return
		Local overloadCounts:TMap = New TMap
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If Not irMethod Or Not irMethod.declaringSpecialization Then Continue
			Local baseName:String = TCompilerAbiNamer.Sanitize(irMethod.declaringSpecialization.readableAbiName + "_" + irMethod.name)
			Local key:String = baseName.ToLower()
			Local count:Int = Int(String(overloadCounts.ValueForKey(key)))
			overloadCounts.Insert(key, String(count + 1))
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If Not irMethod Or Not irMethod.declaringSpecialization Then Continue
			Local baseName:String = TCompilerAbiNamer.Sanitize(irMethod.declaringSpecialization.readableAbiName + "_" + irMethod.name)
			Local count:Int = Int(String(overloadCounts.ValueForKey(baseName.ToLower())))
			irMethod.abiName = baseName
			If count > 1 Then irMethod.abiName = irMethod.abiName + "__" + TCompilerStableDigest.Sha256(irMethod.signatureKey)[..12]
		Next
	End Function

	Function LowerRoutine(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.specialization Or ir.specialization.artifact.members.length <> 1 Then
			diagnostics :+ ["BMXC3010 canonical generic routine artifact must contain exactly one routine record"]
			If ir And ir.specialization Then ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
			Return
		End If
		Local member:TGenericTemplateMember = ir.specialization.artifact.members[0]
		If member.kind <> TEMPLATE_MEMBER_METHOD Then
			diagnostics :+ ["BMXC3010 canonical generic routine artifact contains an invalid member record"]
			ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
			Return
		End If
		Local routine:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
		routine.name = member.name
		routine.visibility = member.visibility
		routine.metadata = member.metadata
		routine.abiName = ir.specialization.readableAbiName
		routine.receiverType = TTemplateTypeSubstitution.Apply(ir.specialization.artifact.containingType, ir.specialization.key.containingTypeArguments, ir.specialization.key.typeArguments)
		routine.receiverIsStruct = ir.specialization.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT
		routine.returnType = TTemplateTypeSubstitution.Apply(member.semanticType, ir.specialization.key.containingTypeArguments, ir.specialization.key.typeArguments)
		routine.parameters = SubstituteRoutineParameters(member.parameters, ir.specialization.key.containingTypeArguments, ir.specialization.key.typeArguments)
		routine.body = SubstituteRoutineNode(member.body, ir.specialization.key.containingTypeArguments, ir.specialization.key.typeArguments)
		routine.source = member.source
		routine.declaringSpecialization = ir.specialization
		If ir.specialization.artifact.isMethod And Not SupportedType(routine.receiverType, ir) Then
			diagnostics :+ ["BMXC3016 generic method '" + member.name + "' has an unsupported containing-Type receiver ABI"]
			ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
		End If
		If Not SupportedType(routine.returnType, ir) Then
			diagnostics :+ ["BMXC3012 generic routine '" + member.name + "' specializes to unsupported return type '" + routine.returnType.CanonicalName() + "'"]
			ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
		End If
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			If Not SupportedCallableParameter(parameter, ir) Then
				diagnostics :+ ["BMXC3016 generic routine '" + member.name + "' parameters must specialize to supported value ABI types or supported Var ABI types; parameter '" + parameter.name + "' does not"]
				ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
			End If
		Next
		ir.routine = routine
	End Function

	Function SubstituteRoutineParameters:TGenericTemplateValueParameter[](parameters:TGenericTemplateValueParameter[], containingArguments:TTemplateTypeReference[], arguments:TTemplateTypeReference[])
		Local result:TGenericTemplateValueParameter[] = New TGenericTemplateValueParameter[parameters.length]
		For Local index:Int = 0 Until parameters.length
			Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
			parameter.name = parameters[index].name
			parameter.ordinal = parameters[index].ordinal
			parameter.semanticType = TTemplateTypeSubstitution.Apply(parameters[index].semanticType, containingArguments, arguments)
			parameter.passingMode = parameters[index].passingMode
			parameter.optional = parameters[index].optional
			parameter.defaultValue = SubstituteRoutineNode(parameters[index].defaultValue, containingArguments, arguments)
			parameter.source = parameters[index].source
			result[index] = parameter
		Next
		Return result
	End Function

	Function SubstituteRoutineNode:TGenericTemplateNode(node:TGenericTemplateNode, containingArguments:TTemplateTypeReference[], arguments:TTemplateTypeReference[])
		If Not node Then Return Null
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = node.kind
		result.identity = node.identity
		result.semanticType = TTemplateTypeSubstitution.Apply(node.semanticType, containingArguments, arguments)
		result.referencedSymbol = node.referencedSymbol
		result.source = node.source
		result.valueText = node.valueText
		result.runtimeDispatchKind = node.runtimeDispatchKind
		result.runtimeDispatchIndex = node.runtimeDispatchIndex
		result.children = New TGenericTemplateNode[node.children.length]
		For Local index:Int = 0 Until node.children.length
			result.children[index] = SubstituteRoutineNode(node.children[index], containingArguments, arguments)
		Next
		If result.kind = TEMPLATE_NODE_CALL And result.children.length And result.children[0] And result.children[0].kind = TEMPLATE_NODE_BLOCK And result.children[0].valueText = "deferred-routine-candidates" Then
			ResolveDeferredRoutineCall(result)
		End If
		Return result
	End Function

	Function ResolveDeferredRoutineCall(call:TGenericTemplateNode)
		If Not call Or Not call.children.length Then Return
		Local candidates:TGenericTemplateNode = call.children[0]
		Local selected:TGenericTemplateNode
		Local selectedCost:Int = 1000000
		Local ambiguous:Int
		For Local candidate:TGenericTemplateNode = EachIn candidates.children
			If Not candidate Or candidate.children.length <> call.children.length - 1 Then Continue
			Local matches:Int = True
			Local cost:Int
			For Local index:Int = 0 Until candidate.children.length
				Local parameter:TGenericTemplateNode = candidate.children[index]
				Local argument:TGenericTemplateNode = call.children[index + 1]
				Local conversionCost:Int = DeferredRoutineConversionCost(parameter, argument)
				If conversionCost < 0 Then
					matches = False
					Exit
				End If
				cost :+ conversionCost
			Next
			If Not matches Then Continue
			If cost < selectedCost Then
				selected = candidate
				selectedCost = cost
				ambiguous = False
			Else If cost = selectedCost Then
				ambiguous = True
			End If
		Next
		If Not selected Or ambiguous Then
			If call.children.length = 3 And call.children[1] And call.children[2] And call.children[1].semanticType And call.children[2].semanticType Then
				Local leftType:TTemplateTypeReference = call.children[1].semanticType
				Local rightType:TTemplateTypeReference = call.children[2].semanticType
				If leftType.runtimeKind = TEMPLATE_RUNTIME_STRUCT And leftType.runtimeEqualityAbiName.length And leftType.CanonicalName() = rightType.CanonicalName() Then
					Local signature:TGenericTemplateNode = New TGenericTemplateNode
					signature.kind = TEMPLATE_NODE_BLOCK
					signature.valueText = "ordinary-routine-signature"
					signature.source = call.source
					Local receiver:TGenericTemplateNode = New TGenericTemplateNode
					receiver.kind = TEMPLATE_NODE_DECLARATION
					receiver.valueText = "ordinary-struct-receiver"
					receiver.semanticType = leftType
					receiver.source = call.source
					Local parameter:TGenericTemplateNode = New TGenericTemplateNode
					parameter.kind = TEMPLATE_NODE_DECLARATION
					parameter.valueText = PARAMETER_PASS_VALUE
					parameter.semanticType = rightType
					parameter.source = call.source
					signature.children = [receiver, parameter]
					call.children[0] = signature
					call.referencedSymbol = New TTemplateSymbolReference
					call.referencedSymbol.moduleName = leftType.moduleName
					call.referencedSymbol.qualifiedName = leftType.symbolName + ".="
					call.referencedSymbol.overloadKey = leftType.runtimeEqualityAbiName
					call.valueText = call.referencedSymbol.qualifiedName
					Return
				End If
			End If
			call.valueText = "unresolved-deferred-overload"
			For Local index:Int = 1 Until call.children.length
				If call.children[index] And call.children[index].semanticType Then call.valueText = call.valueText + ":" + call.children[index].semanticType.CanonicalName()
			Next
			Return
		End If
		Local signature:TGenericTemplateNode = New TGenericTemplateNode
		signature.kind = TEMPLATE_NODE_BLOCK
		signature.valueText = "ordinary-routine-signature"
		signature.source = selected.source
		signature.children = selected.children
		call.children[0] = signature
		call.referencedSymbol = selected.referencedSymbol
		call.semanticType = selected.semanticType
		call.valueText = selected.referencedSymbol.qualifiedName
	End Function

	Function DeferredRoutineConversionCost:Int(parameter:TGenericTemplateNode, argument:TGenericTemplateNode)
		If Not parameter Or Not argument Or Not parameter.semanticType Or Not argument.semanticType Then Return -1
		If parameter.semanticType.CanonicalName() = argument.semanticType.CanonicalName() Then Return 0
		If argument.semanticType.kind = TEMPLATE_TYPE_NAMED And argument.semanticType.runtimeKind = TEMPLATE_RUNTIME_ENUM And parameter.semanticType.kind = TEMPLATE_TYPE_BUILTIN Then
			If parameter.semanticType.symbolName.ToLower() = argument.semanticType.runtimeValueType.ToLower() Then Return 1
		End If
		If parameter.semanticType.kind <> TEMPLATE_TYPE_BUILTIN Or parameter.semanticType.symbolName.ToLower() <> "object" Then Return -1
		If argument.semanticType.kind = TEMPLATE_TYPE_ARRAY Then Return 1
		If argument.semanticType.kind = TEMPLATE_TYPE_BUILTIN Then
			Local builtinName:String = argument.semanticType.symbolName.ToLower()
			If builtinName = "string" Or builtinName = "object" Then Return 1
			Return -1
		End If
		If argument.semanticType.kind = TEMPLATE_TYPE_NAMED And (argument.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS Or argument.semanticType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE) Then Return 1
		Return -1
	End Function

	Function InterfaceTargets:TGenericSpecializationNode[](node:TGenericSpecializationNode)
		Local result:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
		For Local edge:TGenericSpecializationEdge = EachIn node.outgoing
			If edge And edge.request And edge.request.reason = GENERIC_REQUEST_INTERFACE And edge.target Then result :+ [edge.target]
		Next
		Return result
	End Function

	Function ClassInterfaceTargets:TGenericSpecializationNode[](node:TGenericSpecializationNode, visiting:TMap = Null)
		If Not node Then Return New TGenericSpecializationNode[0]
		If Not visiting Then visiting = New TMap
		If visiting.Contains(node.key.CanonicalName()) Then Return New TGenericSpecializationNode[0]
		visiting.Insert(node.key.CanonicalName(), node)
		Local result:TGenericSpecializationNode[] = InterfaceTargets(node)
		Local baseNode:TGenericSpecializationNode = InheritanceTarget(node)
		If baseNode And baseNode.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_INTERFACE Then
			result :+ ClassInterfaceTargets(baseNode, visiting)
		End If
		visiting.Remove(node.key.CanonicalName())
		Return result
	End Function

	Function DirectInterfaceParents:TGenericSpecializationNode[](node:TGenericSpecializationNode)
		Local result:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
		Local primary:TGenericSpecializationNode = InheritanceTarget(node)
		If primary And primary.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then result :+ [primary]
		For Local target:TGenericSpecializationNode = EachIn InterfaceTargets(node)
			If target And target.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then result :+ [target]
		Next
		Return result
	End Function

	Function DirectRuntimeInterfaceParents:TTemplateTypeReference[](node:TGenericSpecializationNode, ir:TCompilerGenericSpecializationIr)
		Local result:TTemplateTypeReference[] = New TTemplateTypeReference[0]
		If Not node Or Not node.artifact Then Return result
		If node.artifact.baseType Then AppendRuntimeInterfaceParent(node.artifact.baseType.semanticType, node, ir, result)
		For Local parent:TGenericTemplateInheritanceReference = EachIn node.artifact.interfaces
			If parent Then AppendRuntimeInterfaceParent(parent.semanticType, node, ir, result)
		Next
		Return result
	End Function

	Function AppendRuntimeInterfaceParent(value:TTemplateTypeReference, node:TGenericSpecializationNode, ir:TCompilerGenericSpecializationIr, result:TTemplateTypeReference[] Var)
		If Not value Or Not node Then Return
		Local closed:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(value, node.key.containingTypeArguments, node.key.typeArguments)
		If Not closed Or closed.runtimeKind <> TEMPLATE_RUNTIME_INTERFACE Or Not closed.runtimeAbiName.length Then Return
		If ReferencedSpecialization(closed, ir) Then Return
		For Local existing:TTemplateTypeReference = EachIn result
			If existing.runtimeAbiName.ToLower() = closed.runtimeAbiName.ToLower() Then Return
		Next
		result :+ [closed]
	End Function

	Function InterfaceClosure:TGenericSpecializationNode[](directInterfaces:TGenericSpecializationNode[], diagnostics:String[] Var)
		Local result:TGenericSpecializationNode[] = New TGenericSpecializationNode[0]
		Local seen:TMap = New TMap
		Local visiting:TMap = New TMap
		For Local interfaceNode:TGenericSpecializationNode = EachIn directInterfaces
			AppendInterfaceClosure(interfaceNode, result, seen, visiting, diagnostics)
		Next
		Return result
	End Function

	Function AppendInterfaceClosure(node:TGenericSpecializationNode, result:TGenericSpecializationNode[] Var, seen:TMap, visiting:TMap, diagnostics:String[] Var)
		If Not node Then Return
		If seen.Contains(node.key.CanonicalName()) Then Return
		If visiting.Contains(node.key.CanonicalName()) Then
			diagnostics :+ ["BMXC3017 recursive generic Interface inheritance reached specialization '" + node.key.CanonicalName() + "'"]
			Return
		End If
		visiting.Insert(node.key.CanonicalName(), node)
		For Local parent:TGenericSpecializationNode = EachIn DirectInterfaceParents(node)
			AppendInterfaceClosure(parent, result, seen, visiting, diagnostics)
		Next
		visiting.Remove(node.key.CanonicalName())
		If Not seen.Contains(node.key.CanonicalName()) Then
			seen.Insert(node.key.CanonicalName(), node)
			result :+ [node]
		End If
	End Function

	Function EffectiveInterfaceMethods:TCompilerGenericMethodIr[](node:TGenericSpecializationNode, ownerIr:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local result:TCompilerGenericMethodIr[] = New TCompilerGenericMethodIr[0]
		Local seen:TMap = New TMap
		Local visiting:TMap = New TMap
		AppendEffectiveInterfaceMethods(node, ownerIr, result, seen, visiting, diagnostics)
		Return result
	End Function

	Function AppendEffectiveInterfaceMethods(node:TGenericSpecializationNode, ownerIr:TCompilerGenericSpecializationIr, result:TCompilerGenericMethodIr[] Var, seen:TMap, visiting:TMap, diagnostics:String[] Var)
		If Not node Then Return
		If seen.Contains(node.key.CanonicalName()) Then Return
		If visiting.Contains(node.key.CanonicalName()) Then
			diagnostics :+ ["BMXC3017 recursive generic Interface method layout reached specialization '" + node.key.CanonicalName() + "'"]
			If ownerIr And ownerIr.specialization Then ownerIr.specialization.state = GENERIC_SPECIALIZATION_FAILED
			Return
		End If
		visiting.Insert(node.key.CanonicalName(), node)
		For Local parent:TGenericSpecializationNode = EachIn DirectInterfaceParents(node)
			AppendEffectiveInterfaceMethods(parent, ownerIr, result, seen, visiting, diagnostics)
		Next
		For Local member:TGenericTemplateMember = EachIn node.artifact.members
			If member.kind <> TEMPLATE_MEMBER_METHOD Then
				diagnostics :+ ["BMXC3017 generic Interface member '" + member.name + "' is not a method"]
				If ownerIr And ownerIr.specialization Then ownerIr.specialization.state = GENERIC_SPECIALIZATION_FAILED
				Continue
			End If
			Local irMethod:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
			irMethod.name = member.name
			irMethod.visibility = member.visibility
			irMethod.metadata = member.metadata
			irMethod.abiName = TCompilerAbiNamer.Sanitize(node.readableAbiName + "_" + member.name)
			irMethod.returnType = TTemplateTypeSubstitution.Apply(member.semanticType, node.key.typeArguments)
			irMethod.receiverType = ReceiverTypeForSpecialization(node)
			irMethod.receiverIsStruct = node.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT
			irMethod.parameters = SubstituteParameters(member.parameters, node.key.typeArguments)
			irMethod.signatureKey = MethodSignatureKey(irMethod)
			irMethod.body = SubstituteNode(member.body, node.key.typeArguments)
			irMethod.interfaceMethodKind = member.interfaceMethodKind
			irMethod.source = member.source
			irMethod.declaringSpecialization = node
			If Not SupportedType(irMethod.returnType, ownerIr) Then
				diagnostics :+ ["BMXC3012 generic Interface method '" + member.name + "' specializes to unsupported return type '" + irMethod.returnType.CanonicalName() + "'"]
				If ownerIr And ownerIr.specialization Then ownerIr.specialization.state = GENERIC_SPECIALIZATION_FAILED
				Continue
			End If
			Local supportedParameters:Int = True
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				If Not SupportedParameterType(parameter.semanticType, ownerIr) Then supportedParameters = False
			Next
			If Not supportedParameters Then Continue
			Local selectorIndex:Int = -1
			For Local index:Int = 0 Until result.length
				If MethodSelectorsMatch(result[index], irMethod) Then selectorIndex = index; Exit
			Next
			If selectorIndex >= 0 Then
				Local inheritedMethod:TCompilerGenericMethodIr = result[selectorIndex]
				If irMethod.returnType.CanonicalName() = inheritedMethod.returnType.CanonicalName() Then
					' An explicit declaration on the derived Interface owns the
					' inherited selector without changing its stable slot.
					If ownerIr And node = ownerIr.specialization And inheritedMethod.declaringSpecialization <> node Then
						irMethod.slotName = inheritedMethod.slotName
						result[selectorIndex] = irMethod
					End If
					Continue
				End If
				If InterfaceReturnConforms(irMethod.returnType, inheritedMethod.returnType, ownerIr) Then
					' Parent order is semantically observable when the inherited
					' receiver binds the wider return. Only an explicit declaration
					' on this Interface refines ownership and the closed result.
					If ownerIr And node = ownerIr.specialization Then
						irMethod.slotName = inheritedMethod.slotName
						result[selectorIndex] = irMethod
					End If
					Continue
				End If
				If InterfaceReturnConforms(inheritedMethod.returnType, irMethod.returnType, ownerIr) Then Continue
				diagnostics :+ ["BMXC3081 inherited generic Interface selector '" + irMethod.name + "' has incompatible return types '" + inheritedMethod.returnType.CanonicalName() + "' and '" + irMethod.returnType.CanonicalName() + "'"]
				If ownerIr And ownerIr.specialization Then ownerIr.specialization.state = GENERIC_SPECIALIZATION_FAILED
				Continue
			End If
			irMethod.slotName = TCompilerAbiNamer.Sanitize("m_" + member.name.ToLower() + "_" + result.length)
			result :+ [irMethod]
		Next
		visiting.Remove(node.key.CanonicalName())
		seen.Insert(node.key.CanonicalName(), node)
	End Function

	Function ValidateInterfaceImplementations(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		For Local interfaceNode:TGenericSpecializationNode = EachIn ir.implementedInterfaces
			Local requirements:TCompilerGenericMethodIr[] = EffectiveInterfaceMethods(interfaceNode, ir, diagnostics)
			For Local requirement:TCompilerGenericMethodIr = EachIn requirements
				Local found:Int = requirement.interfaceMethodKind = TEMPLATE_INTERFACE_METHOD_DEFAULT
				For Local implementation:TCompilerGenericMethodIr = EachIn ir.methods
					If ImplementationMatchesRequirement(implementation, requirement, ir) Then found = True; Exit
				Next
				If Not found Then
					diagnostics :+ ["BMXC3017 generic Type '" + ir.specialization.artifact.identity.qualifiedName + "' does not implement Interface method '" + requirement.name + "'"]
					ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
				End If
			Next
		Next
	End Function

	Function MethodSignaturesMatch:Int(implementation:TCompilerGenericMethodIr, requirement:TCompilerGenericMethodIr)
		If Not implementation Then Return False
		If Not requirement Then Return False
		If Not MethodSelectorsMatch(implementation, requirement) Then Return False
		Return implementation.returnType.CanonicalName() = requirement.returnType.CanonicalName()
	End Function

	Function MethodSelectorsMatch:Int(implementation:TCompilerGenericMethodIr, requirement:TCompilerGenericMethodIr)
		If Not implementation Then Return False
		If Not requirement Then Return False
		If implementation.name.ToLower() <> requirement.name.ToLower() Then Return False
		If implementation.parameters.length <> requirement.parameters.length Then Return False
		For Local index:Int = 0 Until implementation.parameters.length
			If implementation.parameters[index].passingMode <> requirement.parameters[index].passingMode Then Return False
			If implementation.parameters[index].semanticType.CanonicalName() <> requirement.parameters[index].semanticType.CanonicalName() Then Return False
		Next
		Return True
	End Function

	Function InterfaceReturnConforms:Int(candidate:TTemplateTypeReference, requirement:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not candidate Or Not requirement Then Return False
		If candidate.CanonicalName() = requirement.CanonicalName() Then Return True
		If requirement.kind = TEMPLATE_TYPE_BUILTIN And requirement.symbolName.ToLower() = "object" Then
			If candidate.kind = TEMPLATE_TYPE_ARRAY Then Return True
			If candidate.kind = TEMPLATE_TYPE_BUILTIN And candidate.symbolName.ToLower() = "string" Then Return True
			If candidate.kind = TEMPLATE_TYPE_NAMED And (candidate.runtimeKind = TEMPLATE_RUNTIME_CLASS Or candidate.runtimeKind = TEMPLATE_RUNTIME_INTERFACE) Then Return True
			Local managedCandidate:TGenericSpecializationNode = ReferencedSpecialization(candidate, ir)
			If managedCandidate And managedCandidate.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Return True
		End If
		Local candidateSpecialization:TGenericSpecializationNode = ReferencedSpecialization(candidate, ir)
		Local requirementSpecialization:TGenericSpecializationNode = ReferencedSpecialization(requirement, ir)
		If Not candidateSpecialization Or Not requirementSpecialization Then Return False
		Return SpecializationConformsTo(candidateSpecialization, requirementSpecialization, New TMap)
	End Function

	Function ImplementationMatchesRequirement:Int(implementation:TCompilerGenericMethodIr, requirement:TCompilerGenericMethodIr, ir:TCompilerGenericSpecializationIr)
		If Not implementation Or Not requirement Then Return False
		If implementation.name.ToLower() <> requirement.name.ToLower() Or implementation.parameters.length <> requirement.parameters.length Then Return False
		For Local index:Int = 0 Until implementation.parameters.length
			If implementation.parameters[index].passingMode <> requirement.parameters[index].passingMode Then Return False
			If implementation.parameters[index].semanticType.CanonicalName() <> requirement.parameters[index].semanticType.CanonicalName() Then Return False
		Next
		Return InterfaceReturnConforms(implementation.returnType, requirement.returnType, ir)
	End Function

	Function SpecializationConformsTo:Int(candidate:TGenericSpecializationNode, requirement:TGenericSpecializationNode, visiting:TMap)
		If Not candidate Or Not requirement Then Return False
		If candidate.key.CanonicalName() = requirement.key.CanonicalName() Then Return True
		If visiting.Contains(candidate.key.CanonicalName()) Then Return False
		visiting.Insert(candidate.key.CanonicalName(), candidate)
		For Local edge:TGenericSpecializationEdge = EachIn candidate.outgoing
			If Not edge Or Not edge.target Or Not edge.request Then Continue
			If edge.request.reason <> GENERIC_REQUEST_INTERFACE And edge.request.reason <> GENERIC_REQUEST_INHERITANCE Then Continue
			If SpecializationConformsTo(edge.target, requirement, visiting) Then
				visiting.Remove(candidate.key.CanonicalName())
				Return True
			End If
		Next
		visiting.Remove(candidate.key.CanonicalName())
		Return False
	End Function

	Function InheritanceTarget:TGenericSpecializationNode(node:TGenericSpecializationNode)
		For Local edge:TGenericSpecializationEdge = EachIn node.outgoing
			If edge And edge.request And edge.request.reason = GENERIC_REQUEST_INHERITANCE Then Return edge.target
		Next
		Return Null
	End Function

	Function AppendMembers(ir:TCompilerGenericSpecializationIr, memberNode:TGenericSpecializationNode, inheritancePath:TMap, diagnostics:String[] Var)
		If inheritancePath.Contains(memberNode.key.CanonicalName()) Then
			diagnostics :+ ["BMXC3018 recursive generic base layout reached specialization '" + memberNode.key.CanonicalName() + "'"]
			ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
			Return
		End If
		inheritancePath.Insert(memberNode.key.CanonicalName(), memberNode)
		Local inheritedBase:TGenericSpecializationNode = InheritanceTarget(memberNode)
		If inheritedBase Then AppendMembers(ir, inheritedBase, inheritancePath, diagnostics)
		For Local memberEdge:TGenericSpecializationEdge = EachIn memberNode.outgoing
			If memberEdge And memberEdge.target Then AddReferencedSpecialization(ir, memberEdge.target)
		Next
		Local fieldStart:Int = ir.fields.length
		For Local member:TGenericTemplateMember = EachIn memberNode.artifact.members
			Select member.kind
				Case TEMPLATE_MEMBER_FIELD
					Local existingFields:TCompilerGenericFieldIr[] = ir.fields
					If member.isStatic Then existingFields = ir.staticFields
					For Local existingField:TCompilerGenericFieldIr = EachIn existingFields
						If existingField.declaringSpecialization = memberNode And existingField.name.ToLower() = member.name.ToLower() Then
							diagnostics :+ ["BMXC3018 duplicate generic member '" + member.name + "' in specialization '" + memberNode.key.CanonicalName() + "'"]
							ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
							Exit
						End If
					Next
					If ir.specialization.state = GENERIC_SPECIALIZATION_FAILED Then Continue
					Local irField:TCompilerGenericFieldIr = New TCompilerGenericFieldIr
					irField.name = member.name
					If member.isStatic Then
						irField.abiName = StaticFieldAbiName(memberNode, member.name)
					Else
						irField.abiName = TCompilerAbiNamer.Sanitize("_" + memberNode.readableAbiName.ToLower() + "_" + member.name.ToLower())
					End If
					irField.visibility = member.visibility
					irField.metadata = member.metadata
					irField.isThreadedGlobal = member.identity.StartsWith("threaded-static:")
					irField.semanticType = TTemplateTypeSubstitution.Apply(member.semanticType, memberNode.key.typeArguments)
					irField.initializer = SubstituteNode(member.body, memberNode.key.typeArguments)
					irField.source = member.source
					irField.declaringSpecialization = memberNode
					If (Not SupportedType(irField.semanticType, ir) And Not SupportedStaticArrayType(irField.semanticType, ir)) Or (ir.isStruct And Not SupportedStructType(irField.semanticType, False, ir)) Then
						If ir.isStruct Then
							diagnostics :+ ["BMXC3011 generic Struct field '" + member.name + "' has no supported closed value ABI: '" + irField.semanticType.CanonicalName() + "'"]
						Else
							diagnostics :+ ["BMXC3011 generic field '" + member.name + "' specializes to unsupported type '" + irField.semanticType.CanonicalName() + "'"]
						End If
						ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
					Else
						Local nestedStruct:TGenericSpecializationNode = ReferencedSpecialization(irField.semanticType, ir)
						If ir.isStruct And nestedStruct And Not HasZeroArgumentStructConstruction(nestedStruct.artifact) Then
							diagnostics :+ ["BMXC3015 generic Struct field '" + member.name + "' requires a zero-argument construction path for nested specialization '" + nestedStruct.key.CanonicalName() + "'"]
							ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
							Continue
						End If
						If member.isStatic Then ir.staticFields :+ [irField] Else ir.fields :+ [irField]
					End If
					If irField.initializer And Not SupportedFieldInitializer(irField.initializer, ir) Then
						diagnostics :+ ["BMXC3033 generic field initializer on '" + member.name + "' requires a closed supported literal or numeric operator expression"]
						ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
					End If
				Case TEMPLATE_MEMBER_METHOD
					If member.name.ToLower() = "new" Then
						' Do not flatten a base constructor as though its body were
						' declared on the derived Type. Explicit derived New bodies
						' retain canonical delegation edges; inherited overloads are
						' added later as derived allocation forwarders.
						If memberNode <> ir.specialization Then Continue
						Local constructor:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
						constructor.name = member.name
						constructor.visibility = member.visibility
						constructor.metadata = member.metadata
						constructor.returnType = TTemplateTypeSubstitution.Apply(member.semanticType, memberNode.key.typeArguments)
						constructor.receiverType = ReceiverTypeForSpecialization(ir.specialization)
						constructor.receiverIsStruct = ir.isStruct
						constructor.parameters = SubstituteParameters(member.parameters, memberNode.key.typeArguments)
						constructor.signatureKey = ConstructorSignatureKey(constructor.parameters)
						constructor.body = SubstituteNode(member.body, memberNode.key.typeArguments)
						constructor.source = member.source
						constructor.declaringSpecialization = memberNode
						Local supportedConstructorParameters:Int = True
						For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
							Local supportedParameter:Int
							If ir.isStruct Then supportedParameter = SupportedStructConstructorParameter(parameter, ir) Else supportedParameter = SupportedCallableParameter(parameter, ir)
							If Not supportedParameter Then
								diagnostics :+ ["BMXC3016 generic constructor parameter '" + parameter.name + "' specializes outside the supported value/Var ABI"]
								ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
								supportedConstructorParameters = False
							End If
						Next
						If supportedConstructorParameters Then
							Local duplicateConstructorSignature:Int
							For Local existingConstructor:TCompilerGenericMethodIr = EachIn ir.constructors
								If existingConstructor.signatureKey = constructor.signatureKey Then
									duplicateConstructorSignature = True
									Exit
								End If
							Next
							If duplicateConstructorSignature Then
								diagnostics :+ ["BMXC3015 generic constructor overloads collapse to canonical signature '" + constructor.signatureKey + "' after specialization"]
								ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
							Else
								ir.constructors :+ [constructor]
							End If
						End If
						Continue
					End If
					Local irMethod:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
					irMethod.name = member.name
					irMethod.isDestructor = member.name.ToLower() = "delete"
					If irMethod.isDestructor And ir.isStruct Then
						diagnostics :+ ["BMXC3016 generic Struct destructor has no supported value-lifetime ABI"]
						ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
						Continue
					End If
					irMethod.abiName = TCompilerAbiNamer.Sanitize(memberNode.readableAbiName + "_" + member.name)
					If Not irMethod.isDestructor Then
						Local slotOrdinal:Int
						For Local existingSlot:TCompilerGenericMethodIr = EachIn ir.methods
							If Not existingSlot.isDestructor Then slotOrdinal :+ 1
						Next
						irMethod.slotName = TCompilerAbiNamer.Sanitize("m_" + member.name.ToLower() + "_" + slotOrdinal)
					End If
					irMethod.visibility = member.visibility
					irMethod.metadata = member.metadata
					irMethod.returnType = TTemplateTypeSubstitution.Apply(member.semanticType, memberNode.key.typeArguments)
					irMethod.receiverType = ReceiverTypeForSpecialization(ir.specialization)
					irMethod.receiverIsStruct = ir.isStruct
					irMethod.isStatic = member.isStatic
					irMethod.isTypeFunction = member.isTypeFunction
					irMethod.parameters = SubstituteParameters(member.parameters, memberNode.key.typeArguments)
					irMethod.signatureKey = MethodSignatureKey(irMethod)
					irMethod.body = SubstituteNode(member.body, memberNode.key.typeArguments)
					If Not ir.isStruct And memberNode.IsMethodDeferred(irMethod.signatureKey) And Not memberNode.IsMethodRequired(irMethod.signatureKey) Then
						irMethod.body = Null
						irMethod.isDeferredStub = True
					End If
					irMethod.source = member.source
					irMethod.declaringSpecialization = memberNode
					Local replacementIndex:Int = -1
					Local methodCollision:Int
					For Local methodIndex:Int = 0 Until ir.methods.length
						Local existingMethod:TCompilerGenericMethodIr = ir.methods[methodIndex]
						If existingMethod.name.ToLower() <> member.name.ToLower() Then Continue
						If existingMethod.declaringSpecialization <> memberNode And MethodSignaturesMatch(irMethod, existingMethod) Then
							replacementIndex = methodIndex
							irMethod.slotName = existingMethod.slotName
							Exit
						Else If existingMethod.declaringSpecialization = memberNode And MethodSignaturesMatch(irMethod, existingMethod) Then
							diagnostics :+ ["BMXC3014 generic method overloads collapse to canonical signature '" + irMethod.signatureKey + "'"]
							ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
							methodCollision = True
							Exit
						Else If existingMethod.declaringSpecialization = memberNode Then
							Local overloadSuffix:String = "__" + TCompilerStableDigest.Sha256(irMethod.signatureKey)[..12]
							If Not irMethod.abiName.EndsWith(overloadSuffix) Then irMethod.abiName = irMethod.abiName + overloadSuffix
						End If
					Next
					If methodCollision Then Continue
					If Not SupportedReturnType(irMethod.returnType, ir) Or (ir.isStruct And Not SupportedStructType(irMethod.returnType, True, ir)) Then
						diagnostics :+ ["BMXC3012 generic method '" + member.name + "' specializes to unsupported return type '" + irMethod.returnType.CanonicalName() + "'"]
						ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
					Else
						Local supportedParameters:Int = True
						For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
							If Not SupportedParameterType(parameter.semanticType, ir) Or (ir.isStruct And Not SupportedStructType(parameter.semanticType, False, ir)) Then
								diagnostics :+ ["BMXC3016 generic method '" + member.name + "' parameter '" + parameter.name + "' specializes to unsupported type '" + parameter.semanticType.CanonicalName() + "'"]
								ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
								supportedParameters = False
							End If
						Next
						If supportedParameters Then
							If replacementIndex >= 0 Then ir.methods[replacementIndex] = irMethod Else ir.methods :+ [irMethod]
						End If
					End If
				Default
					diagnostics :+ ["BMXC3013 generic member '" + member.name + "' has unsupported template member kind " + member.kind]
					ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
			End Select
		Next
		If memberNode = ir.specialization Then
			ir.declaredFieldStart = fieldStart
			ir.declaredFieldCount = ir.fields.length - fieldStart
		End If
		inheritancePath.Remove(memberNode.key.CanonicalName())
	End Function

	Function StaticFieldAbiName:String(node:TGenericSpecializationNode, name:String)
		If Not node Then Return ""
		Return TCompilerAbiNamer.Sanitize(node.readableAbiName + "_global_" + name.ToLower())
	End Function

	Function SupportedFieldInitializer:Int(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr)
		If Not node Then Return False
		' A canonical static name can omit a standalone semantic type in the
		' source-free tree. Resolve it against storage flattened so far before
		' applying the ordinary typed-expression checks below.
		If node.kind = TEMPLATE_NODE_NAME And SpecializationStaticField(node, ir) Then Return True
		If node.kind = TEMPLATE_NODE_MEMBER And node.children.length = 0 And SpecializationStaticField(node, ir) Then Return True
		If Not node.semanticType Then Return False
		Select node.kind
			Case TEMPLATE_NODE_LITERAL
				If TCompilerGenericCUnitEmitter.ScalarNumericType(node.semanticType) Then Return True
				If node.semanticType.kind = TEMPLATE_TYPE_BUILTIN Then
					Return node.semanticType.symbolName.ToLower() = "string" Or node.semanticType.symbolName.ToLower() = "object"
				End If
				Return node.semanticType.kind = TEMPLATE_TYPE_POINTER Or node.semanticType.kind = TEMPLATE_TYPE_NAMED
			Case TEMPLATE_NODE_OPERATOR
				If Not TCompilerGenericCUnitEmitter.ScalarNumericType(node.semanticType) Then Return False
				If node.children.length < 1 Or node.children.length > 2 Then Return False
			Case TEMPLATE_NODE_CONVERSION
				If Not TCompilerGenericCUnitEmitter.ScalarNumericType(node.semanticType) Then Return False
				If node.children.length <> 1 Then Return False
			Case TEMPLATE_NODE_NEW, TEMPLATE_NODE_CALL
				' Closed constructor and routine calls are validated by the same
				' specialization emitter used for method bodies. They are also valid
				' instance-field initialization expressions.
				Return True
			Case TEMPLATE_NODE_NAME, TEMPLATE_NODE_MEMBER
				Return False
			Default
				Return False
		End Select
		For Local child:TGenericTemplateNode = EachIn node.children
			If Not SupportedFieldInitializer(child, ir) Then Return False
		Next
		Return True
	End Function

	Function SpecializationStaticField:TCompilerGenericFieldIr(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr)
		If Not node Or Not ir Then Return Null
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.name.ToLower() = node.valueText.ToLower() Then Return staticField
		Next
		Return Null
	End Function

	Function SubstituteParameters:TGenericTemplateValueParameter[](parameters:TGenericTemplateValueParameter[], arguments:TTemplateTypeReference[])
		Local result:TGenericTemplateValueParameter[] = New TGenericTemplateValueParameter[parameters.length]
		For Local index:Int = 0 Until parameters.length
			Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
			parameter.name = parameters[index].name
			parameter.ordinal = parameters[index].ordinal
			parameter.semanticType = TTemplateTypeSubstitution.Apply(parameters[index].semanticType, arguments)
			parameter.passingMode = parameters[index].passingMode
			parameter.optional = parameters[index].optional
			parameter.defaultValue = SubstituteNode(parameters[index].defaultValue, arguments)
			parameter.source = parameters[index].source
			result[index] = parameter
		Next
		Return result
	End Function

	Function SubstituteNode:TGenericTemplateNode(node:TGenericTemplateNode, arguments:TTemplateTypeReference[])
		If Not node Then Return Null
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = node.kind
		result.identity = node.identity
		result.semanticType = TTemplateTypeSubstitution.Apply(node.semanticType, arguments)
		result.referencedSymbol = node.referencedSymbol
		result.source = node.source
		result.valueText = node.valueText
		result.runtimeDispatchKind = node.runtimeDispatchKind
		result.runtimeDispatchIndex = node.runtimeDispatchIndex
		result.children = New TGenericTemplateNode[node.children.length]
		For Local index:Int = 0 Until node.children.length
			result.children[index] = SubstituteNode(node.children[index], arguments)
		Next
		If result.kind = TEMPLATE_NODE_CALL And result.children.length And result.children[0] And result.children[0].kind = TEMPLATE_NODE_BLOCK And result.children[0].valueText = "deferred-routine-candidates" Then
			ResolveDeferredRoutineCall(result)
		End If
		Return result
	End Function

	Function IndexReferencedSpecializations(ir:TCompilerGenericSpecializationIr)
		For Local edge:TGenericSpecializationEdge = EachIn ir.specialization.outgoing
			If Not edge Or Not edge.target Then Continue
			AddReferencedSpecialization(ir, edge.target)
		Next
	End Function

	Function AddReferencedSpecialization(ir:TCompilerGenericSpecializationIr, node:TGenericSpecializationNode)
		If Not ir Then Return
		If Not node Then Return
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If referenced = node Then Return
		Next
		ir.referencedSpecializations :+ [node]
		If Not node.artifact.identity Or node.artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then
			ir.referencedTypesByCanonicalName.Insert(ClosedNamedTypeCanonicalName(node), node)
		End If
		For Local edge:TGenericSpecializationEdge = EachIn node.outgoing
			If edge And edge.target Then AddReferencedSpecialization(ir, edge.target)
		Next
	End Function

	Function ClosedNamedTypeCanonicalName:String(node:TGenericSpecializationNode)
		Local result:String = node.artifact.identity.moduleName.ToLower() + "::" + node.artifact.identity.qualifiedName.ToLower() + "<"
		For Local index:Int = 0 Until node.key.typeArguments.length
			If index Then result :+ ","
			result :+ node.key.typeArguments[index].CanonicalName()
		Next
		Return result + ">"
	End Function

	Function ReferencedSpecialization:TGenericSpecializationNode(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not value Or Not ir Or value.kind <> TEMPLATE_TYPE_NAMED Then Return Null
		If SpecializationMatchesType(ir.specialization, value) Then Return ir.specialization
		Local direct:TGenericSpecializationNode = TGenericSpecializationNode(ir.referencedTypesByCanonicalName.ValueForKey(value.CanonicalName().ToLower()))
		If direct Then Return direct
		For Local candidate:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If SpecializationMatchesType(candidate, value) Then Return candidate
		Next
		Return Null
	End Function

	Function SpecializationMatchesType:Int(candidate:TGenericSpecializationNode, value:TTemplateTypeReference)
		If Not candidate Or Not candidate.artifact Or Not candidate.artifact.identity Or Not value Then Return False
		If candidate.artifact.identity.qualifiedName.ToLower() <> value.symbolName.ToLower() Then Return False
		If value.moduleName.length And candidate.artifact.identity.moduleName.ToLower() <> value.moduleName.ToLower() Then Return False
		If candidate.key.typeArguments.length <> value.arguments.length Then Return False
		For Local index:Int = 0 Until value.arguments.length
			If candidate.key.typeArguments[index].CanonicalName() <> value.arguments[index].CanonicalName() Then Return False
		Next
		Return True
	End Function

	Function SupportedType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Then Return False
		If value.kind = TEMPLATE_TYPE_CALLABLE Then Return SupportedCallableType(value, ir)
		If value.kind = TEMPLATE_TYPE_CLOSURE Then Return SupportedClosureType(value, ir)
		If value.kind = TEMPLATE_TYPE_POINTER Then Return SupportedPointerType(value)
		If value.kind = TEMPLATE_TYPE_NAMED Then
			If value.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Or value.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
				If value.runtimeAbiName.length Then Return True
				Return ReferencedSpecialization(value, ir) <> Null
			End If
			If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return EnumValueTypeSupported(value.runtimeValueType)
			Return ReferencedSpecialization(value, ir) <> Null
		End If
		If value.kind = TEMPLATE_TYPE_ARRAY Then Return SupportedManagedArrayType(value, ir)
		If value.kind <> TEMPLATE_TYPE_BUILTIN Then Return False
		Select value.symbolName.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double", "string", "object", "void"
				Return True
		End Select
		Return False
	End Function

	Function SupportedClosureType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Or value.kind <> TEMPLATE_TYPE_CLOSURE Or Not value.elementType Then Return False
		If value.arguments.length <> value.callableParameterModes.length Or value.arguments.length <> value.callableParameterNames.length Then Return False
		If Not SupportedReturnType(value.elementType, ir) Then Return False
		For Local index:Int = 0 Until value.arguments.length
			If Not SupportedParameterType(value.arguments[index], ir) Then Return False
			If value.callableParameterModes[index] <> PARAMETER_PASS_VALUE And value.callableParameterModes[index] <> PARAMETER_PASS_VAR Then Return False
		Next
		Return True
	End Function

	Function SupportedCallableType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Or value.kind <> TEMPLATE_TYPE_CALLABLE Or Not value.elementType Then Return False
		If value.elementType.kind = TEMPLATE_TYPE_CALLABLE Or Not SupportedReturnType(value.elementType, ir) Then Return False
		If value.arguments.length <> value.callableParameterModes.length Then Return False
		For Local index:Int = 0 Until value.arguments.length
			If value.arguments[index].kind = TEMPLATE_TYPE_CALLABLE Or Not SupportedParameterType(value.arguments[index], ir) Then Return False
			If value.callableParameterModes[index] <> PARAMETER_PASS_VALUE And value.callableParameterModes[index] <> PARAMETER_PASS_VAR Then Return False
		Next
		Return True
	End Function

	Function SupportedPointerType:Int(value:TTemplateTypeReference)
		If Not value Or value.kind <> TEMPLATE_TYPE_POINTER Or Not value.elementType Then Return False
		If value.elementType.kind = TEMPLATE_TYPE_POINTER Then Return SupportedPointerType(value.elementType)
		If value.elementType.kind = TEMPLATE_TYPE_BUILTIN Then
			Select value.elementType.symbolName.ToLower()
				Case "void", "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double"
					Return True
			End Select
		End If
		If value.elementType.kind = TEMPLATE_TYPE_NAMED Then
			Return value.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT And value.elementType.runtimeAbiName.length > 0
		End If
		Return False
	End Function

	Function SupportedManagedArrayType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Or value.kind <> TEMPLATE_TYPE_ARRAY Or value.rank <= 0 Or Not value.elementType Then Return False
		If value.elementType.kind = TEMPLATE_TYPE_CLOSURE Then Return SupportedClosureType(value.elementType, ir)
		If value.elementType.kind = TEMPLATE_TYPE_POINTER Then Return SupportedPointerType(value.elementType)
		If value.elementType.kind = TEMPLATE_TYPE_BUILTIN Then
			Select value.elementType.symbolName.ToLower()
				Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double", "string", "object"
					Return True
			End Select
		End If
		If value.elementType.kind = TEMPLATE_TYPE_ARRAY Then Return SupportedManagedArrayType(value.elementType, ir)
		If value.elementType.kind = TEMPLATE_TYPE_NAMED Then
			If value.elementType.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return EnumValueTypeSupported(value.elementType.runtimeValueType)
			Local referenced:TGenericSpecializationNode = ReferencedSpecialization(value.elementType, ir)
				If value.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then Return value.elementType.runtimeAbiName.length > 0 Or (referenced And referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT)
				If value.elementType.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.elementType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then Return value.elementType.runtimeAbiName.length > 0 Or (referenced And referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT)
			Return referenced And referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT
		End If
		Return False
	End Function

	Function SupportedStaticArrayType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Or value.kind <> TEMPLATE_TYPE_STATIC_ARRAY Or value.staticArrayLength <= 0 Or Not value.elementType Then Return False
		If value.elementType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then Return False
		Return SupportedType(value.elementType, ir)
	End Function

	Function SupportedParameterType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		Return SupportedType(value, ir) Or SupportedStaticArrayType(value, ir) Or (value And value.kind = TEMPLATE_TYPE_NAMED And (value.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE))
	End Function

	Function SupportedCallableParameter:Int(parameter:TGenericTemplateValueParameter, ir:TCompilerGenericSpecializationIr = Null)
		If Not parameter Or Not SupportedParameterType(parameter.semanticType, ir) Then Return False
		If parameter.passingMode <> PARAMETER_PASS_VALUE And parameter.passingMode <> PARAMETER_PASS_VAR Then Return False
		' A StaticArray value already lowers as an address-shaped ABI value.
		' Production BlitzMax explicitly rejects Var on a StaticArray parameter:
		' the ordinary StaticArray parameter already exposes its mutable cells.
		' Keep that language rule rather than inventing a pointer-to-array ABI.
		If parameter.passingMode = PARAMETER_PASS_VAR And parameter.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then Return False
		If parameter.passingMode = PARAMETER_PASS_VAR And parameter.optional Then Return False
		Return True
	End Function

	Function SupportedReturnType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		Return SupportedType(value, ir) Or (value And value.kind = TEMPLATE_TYPE_NAMED And (value.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE))
	End Function

	Function ScalarNumericTemplateType:Int(value:TTemplateTypeReference)
		If Not value Or value.kind <> TEMPLATE_TYPE_BUILTIN Then Return False
		Select value.symbolName.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double"
				Return True
		End Select
		Return False
	End Function

	Function EnumValueTypeSupported:Int(value:String)
		Select value.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t"
				Return True
		End Select
		Return False
	End Function

	Function SupportedStructType:Int(value:TTemplateTypeReference, allowVoid:Int, ir:TCompilerGenericSpecializationIr)
		If Not value Then Return False
		If value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "void" Then Return allowVoid
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY Then Return SupportedStaticArrayType(value, ir)
		Return SupportedType(value, ir)
	End Function

	Function SupportedStructConstructorParameter:Int(parameter:TGenericTemplateValueParameter, ir:TCompilerGenericSpecializationIr)
		Return SupportedCallableParameter(parameter, ir) And SupportedStructType(parameter.semanticType, False, ir)
	End Function

	Function FinalizeStructConstructors(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Then Return
		ir.constructor = Null
		If ir.constructors.length = 1 Then
			ir.constructor = ir.constructors[0]
			ir.constructors[0].abiName = ir.specialization.readableAbiName + "_New"
		Else
			For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
				Local sameArityCount:Int
				For Local candidate:TCompilerGenericMethodIr = EachIn ir.constructors
					If candidate.parameters.length = constructor.parameters.length Then sameArityCount :+ 1
				Next
				constructor.abiName = ir.specialization.readableAbiName + "_New__A" + constructor.parameters.length
				If sameArityCount > 1 Then
					constructor.abiName = constructor.abiName + "_" + ConstructorSignatureReadable(constructor.parameters) + "_" + TCompilerStableDigest.Sha256(constructor.signatureKey)[..12]
				End If
			Next
		End If
		LinkConstructorDelegations(ir, "Struct", diagnostics)
	End Function

	Function FinalizeTypeConstructor(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Then Return
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			constructor.abiName = ir.specialization.readableAbiName + "_New__A" + constructor.parameters.length + "_" + ConstructorSignatureReadable(constructor.parameters) + "_" + TCompilerStableDigest.Sha256(constructor.signatureKey)[..12]
			If constructor.parameters.length = 0 Then ir.constructor = constructor
		Next
		If Not ir.constructor And ir.constructors.length = 1 Then ir.constructor = ir.constructors[0]
		LinkConstructorDelegations(ir, "Type", diagnostics)
	End Function

	Function InheritTypeConstructors(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.baseSpecialization Then Return
		Local baseIr:TCompilerGenericSpecializationIr = Lower(ir.baseSpecialization, diagnostics)
		If Not baseIr Or ir.baseSpecialization.state = GENERIC_SPECIALIZATION_FAILED Then
			ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
			Return
		End If
		For Local baseConstructor:TCompilerGenericMethodIr = EachIn baseIr.constructors
			' Explicit parameterless constructors participate in inheritance just like
			' parameterized overloads. When the base declares no such constructor the
			' derived specialization still retains its implicit default construction path.
			If Not baseConstructor Then Continue
			Local shadowed:Int
			For Local ownConstructor:TCompilerGenericMethodIr = EachIn ir.constructors
				If ownConstructor.signatureKey = baseConstructor.signatureKey Then shadowed = True; Exit
			Next
			If shadowed Then Continue
			Local constructor:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
			constructor.name = "New"
			constructor.visibility = baseConstructor.visibility
			constructor.metadata = baseConstructor.metadata
			constructor.returnType = baseConstructor.returnType
			constructor.receiverType = ReceiverTypeForSpecialization(ir.specialization)
			constructor.parameters = SubstituteParameters(baseConstructor.parameters, New TTemplateTypeReference[0])
			constructor.signatureKey = ConstructorSignatureKey(constructor.parameters)
			constructor.body = New TGenericTemplateNode
			constructor.body.kind = TEMPLATE_NODE_BLOCK
			constructor.source = baseConstructor.source
			constructor.declaringSpecialization = ir.specialization
			constructor.delegatedConstructor = baseConstructor
			constructor.delegatedConstructorSpecialization = baseIr.specialization
			constructor.isInheritedConstructorForwarder = True
			ir.constructors :+ [constructor]
		Next
	End Function

	Function LinkConstructorDelegations(ir:TCompilerGenericSpecializationIr, declarationName:String, diagnostics:String[] Var)
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			If Not constructor.body Or constructor.body.kind <> TEMPLATE_NODE_BLOCK Or Not constructor.body.children.length Then Continue
			Local delegation:TGenericTemplateNode = constructor.body.children[0]
			If delegation.kind <> TEMPLATE_NODE_CONSTRUCTOR_DELEGATION Then Continue
			If delegation.children.length <> 2 Or delegation.children[0].kind <> TEMPLATE_NODE_BLOCK Or delegation.children[0].valueText <> "signature" Or delegation.children[1].kind <> TEMPLATE_NODE_BLOCK Or delegation.children[1].valueText <> "arguments" Then
				diagnostics :+ ["BMXC3015 generic " + declarationName + " constructor delegation has an invalid canonical template shape"]
				ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
				Continue
			End If
			Local signatureParameters:TGenericTemplateValueParameter[] = New TGenericTemplateValueParameter[delegation.children[0].children.length]
			For Local index:Int = 0 Until signatureParameters.length
				Local signatureNode:TGenericTemplateNode = delegation.children[0].children[index]
				Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
				parameter.ordinal = index
				parameter.semanticType = signatureNode.semanticType
				parameter.passingMode = Int(signatureNode.valueText)
				signatureParameters[index] = parameter
			Next
			Local targetSignature:String = ConstructorSignatureKey(signatureParameters)
			Local targetIr:TCompilerGenericSpecializationIr = ir
			Local delegatesToBase:Int = delegation.valueText = "super"
			If Not delegatesToBase And ir.baseSpecialization And delegation.referencedSymbol Then
				Local selectedOwner:String = delegation.referencedSymbol.qualifiedName.ToLower()
				Local baseOwner:String = ir.baseSpecialization.artifact.identity.qualifiedName.ToLower()
				If selectedOwner = baseOwner + ".new" Then delegatesToBase = True
			End If
			If delegatesToBase Then
				If ir.isStruct Or Not ir.baseSpecialization Then
					diagnostics :+ ["BMXC3015 generic " + declarationName + " Super.New delegation has no canonical base specialization"]
					ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
					Continue
				End If
				targetIr = Lower(ir.baseSpecialization, diagnostics)
				If Not targetIr Then
					ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
					Continue
				End If
			End If
			For Local candidate:TCompilerGenericMethodIr = EachIn targetIr.constructors
				If candidate.signatureKey = targetSignature Then constructor.delegatedConstructor = candidate; Exit
			Next
			If Not constructor.delegatedConstructor Then
				Local retainedSignatures:String
				For Local candidate:TCompilerGenericMethodIr = EachIn targetIr.constructors
					If retainedSignatures.length Then retainedSignatures :+ ", "
					retainedSignatures :+ candidate.signatureKey
				Next
				If Not retainedSignatures.length Then retainedSignatures = "<none>"
				diagnostics :+ ["BMXC3015 generic " + declarationName + " constructor delegation target '" + targetSignature + "' was not retained by specialization; retained constructors: " + retainedSignatures]
				ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
				Continue
			End If
			constructor.delegatedConstructorSpecialization = targetIr.specialization
			constructor.delegationArguments = delegation.children[1].children
			If constructor.delegationArguments.length <> constructor.delegatedConstructor.parameters.length Then
				diagnostics :+ ["BMXC3015 generic " + declarationName + " constructor delegation to '" + targetSignature + "' has " + constructor.delegationArguments.length + " arguments but requires " + constructor.delegatedConstructor.parameters.length]
				ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
				constructor.delegatedConstructor = Null
				constructor.delegationArguments = New TGenericTemplateNode[0]
			End If
		Next
		Local completed:TMap = New TMap
		Local visiting:TMap = New TMap
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			ValidateConstructorDelegation(constructor, ir, declarationName, completed, visiting, diagnostics)
		Next
	End Function

	Function ValidateConstructorDelegation(constructor:TCompilerGenericMethodIr, ir:TCompilerGenericSpecializationIr, declarationName:String, completed:TMap, visiting:TMap, diagnostics:String[] Var)
		If Not constructor Or completed.Contains(constructor.signatureKey) Then Return
		If visiting.Contains(constructor.signatureKey) Then
			diagnostics :+ ["BMXC3015 recursive generic " + declarationName + " constructor delegation involving canonical signature '" + constructor.signatureKey + "'"]
			ir.specialization.state = GENERIC_SPECIALIZATION_FAILED
			Return
		End If
		visiting.Insert(constructor.signatureKey, constructor)
		If constructor.delegatedConstructor And constructor.delegatedConstructorSpecialization = ir.specialization Then ValidateConstructorDelegation(constructor.delegatedConstructor, ir, declarationName, completed, visiting, diagnostics)
		visiting.Remove(constructor.signatureKey)
		completed.Insert(constructor.signatureKey, constructor)
	End Function

	Function MethodSignatureKey:String(routine:TCompilerGenericMethodIr)
		If Not routine Then Return ""
		Local result:String = routine.name.ToLower() + "("
		For Local index:Int = 0 Until routine.parameters.length
			If index Then result :+ ","
			If routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then result :+ "var:" Else result :+ "value:"
			If routine.parameters[index].semanticType Then result :+ routine.parameters[index].semanticType.CanonicalName() Else result :+ "?"
		Next
		result :+ "):"
		If routine.returnType Then result :+ routine.returnType.CanonicalName() Else result :+ "?"
		Return result
	End Function

	Function ConstructorSignatureKey:String(parameters:TGenericTemplateValueParameter[])
		Local result:String = "new("
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ","
			If parameters[index].passingMode = PARAMETER_PASS_VAR Then result :+ "var:" Else result :+ "value:"
			If parameters[index].semanticType Then result :+ parameters[index].semanticType.CanonicalName() Else result :+ "?"
		Next
		Return result + ")"
	End Function

	Function ConstructorSignatureReadable:String(parameters:TGenericTemplateValueParameter[])
		Local result:String
		For Local parameter:TGenericTemplateValueParameter = EachIn parameters
			If result.length Then result :+ "_"
			If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ "var_"
			If parameter.semanticType Then result :+ TCompilerAbiNamer.Sanitize(parameter.semanticType.CanonicalName()) Else result :+ "unknown"
		Next
		If Not result.length Then Return "void"
		Return result
	End Function

	Function HasZeroArgumentStructConstruction:Int(artifact:TGenericTemplateArtifact)
		If Not artifact Then Return False
		Local hasExplicitConstructor:Int
		For Local member:TGenericTemplateMember = EachIn artifact.members
			If member.kind <> TEMPLATE_MEMBER_METHOD Or member.name.ToLower() <> "new" Then Continue
			hasExplicitConstructor = True
			If member.parameters.length = 0 Then Return True
		Next
		Return Not hasExplicitConstructor
	End Function
End Type

Type TCompilerGenericCUnitEmitter
	Function IsRoutineSpecialization:Int(node:TGenericSpecializationNode)
		Return node And node.artifact And node.artifact.identity And node.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE
	End Function

	Function DeclarationGuard:String(kind:String, abiName:String)
		Return "BMX_GENERIC_" + TCompilerAbiNamer.Sanitize(kind + "_" + abiName).ToUpper()
	End Function

	Function DefiningModuleHeaderInclude:String(ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.specialization Or Not ir.specialization.artifact Or Not ir.specialization.artifact.identity Then Return ""
		If ir.specialization.definingSourceUnitPath.length Then Return SourceUnitHeaderInclude(ir.specialization.definingSourceUnitPath, ir.specialization.configuration)
		If ir.specialization.applicationSourceOwned Then Return ""
		Return ModuleHeaderInclude(ir.specialization.artifact.identity.moduleName, ir.specialization.configuration)
	End Function

	Function SourceUnitHeaderInclude:String(sourceUnitPath:String, configuration:TCompilerGenericConfiguration)
		Local normalized:String = sourceUnitPath.Replace("\", "/")
		If Not normalized.length Or Not configuration Or Not configuration.buildMode.length Or Not configuration.targetPlatform.length Or Not configuration.targetArchitecture.length Then Return ""
		Local sourceDirectory:String = ExtractDir(normalized)
		If sourceDirectory.length Then sourceDirectory :+ "/"
		Local mung:String = configuration.buildMode.ToLower() + "." + configuration.targetPlatform.ToLower() + "." + configuration.targetArchitecture.ToLower()
		Return "#include <" + sourceDirectory + ".bmx/" + StripDir(normalized) + "." + mung + ".h>~n"
	End Function

	Function ModuleHeaderInclude:String(moduleIdentity:String, configuration:TCompilerGenericConfiguration)
		Local moduleName:String = moduleIdentity.ToLower()
		If Not moduleName.length Or moduleName.StartsWith("source:") Then Return ""
		Local dot:Int = moduleName.FindLast(".")
		If dot < 0 Or dot = moduleName.length - 1 Then Return ""
		If Not configuration Or Not configuration.buildMode.length Or Not configuration.targetPlatform.length Or Not configuration.targetArchitecture.length Then Return ""
		Local moduleLeaf:String = moduleName[dot + 1..]
		Local modulePath:String = moduleName.Replace(".", ".mod/") + ".mod"
		Local mung:String = configuration.buildMode.ToLower() + "." + configuration.targetPlatform.ToLower() + "." + configuration.targetArchitecture.ToLower()
		' C99 inline definitions in the runtime headers have matching external
		' definitions in the runtime library. Include the authoritative module
		' header normally; compiler-owned standard macros must not be rewritten.
		Return "#include <" + modulePath + "/.bmx/" + moduleLeaf + ".bmx." + mung + ".h>~n"
	End Function

	Function RuntimeArgumentHeaderIncludes:String(ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.specialization Then Return ""
		Local emitted:TMap = New TMap
		Local result:String
		For Local argument:TTemplateTypeReference = EachIn ir.specialization.key.typeArguments
			result :+ RuntimeTypeHeaderIncludesForSpecialization(argument, ir.specialization, emitted)
		Next
		For Local argument:TTemplateTypeReference = EachIn ir.specialization.key.containingTypeArguments
			result :+ RuntimeTypeHeaderIncludesForSpecialization(argument, ir.specialization, emitted)
		Next
		If ir.routine Then result :+ RuntimeMethodHeaderIncludes(ir.routine, ir.specialization, emitted)
		For Local method:TCompilerGenericMethodIr = EachIn ir.methods
			result :+ RuntimeMethodHeaderIncludes(method, ir.specialization, emitted)
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			result :+ RuntimeMethodHeaderIncludes(constructor, ir.specialization, emitted)
		Next
		Return result
	End Function

	Function RuntimeMethodHeaderIncludes:String(method:TCompilerGenericMethodIr, specialization:TGenericSpecializationNode, emitted:TMap)
		If Not method Then Return ""
		Local result:String = RuntimeTypeHeaderIncludesForSpecialization(method.returnType, specialization, emitted)
		result :+ RuntimeTypeHeaderIncludesForSpecialization(method.receiverType, specialization, emitted)
		For Local parameter:TGenericTemplateValueParameter = EachIn method.parameters
			If parameter Then result :+ RuntimeTypeHeaderIncludesForSpecialization(parameter.semanticType, specialization, emitted)
		Next
		Return result
	End Function

	' Compatibility entry point used by focused emitter tests and callers which
	' only have a target configuration rather than an application plan.
	Function RuntimeTypeHeaderIncludes:String(value:TTemplateTypeReference, configuration:TCompilerGenericConfiguration, emitted:TMap)
		Local specialization:TGenericSpecializationNode = New TGenericSpecializationNode
		specialization.configuration = configuration
		Return RuntimeTypeHeaderIncludesForSpecialization(value, specialization, emitted)
	End Function

	Function RuntimeTypeHeaderIncludesForSpecialization:String(value:TTemplateTypeReference, specialization:TGenericSpecializationNode, emitted:TMap)
		If Not value Then Return ""
		Local result:String
		If value.elementType Then result :+ RuntimeTypeHeaderIncludesForSpecialization(value.elementType, specialization, emitted)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			result :+ RuntimeTypeHeaderIncludesForSpecialization(argument, specialization, emitted)
		Next
		If value.runtimeKind <> TEMPLATE_RUNTIME_STRUCT Or Not value.moduleName.length Then Return result
		Local sourceUnitPath:String
		If specialization And specialization.runtimeStructSourceUnits And value.runtimeAbiName.length Then sourceUnitPath = String(specialization.runtimeStructSourceUnits.ValueForKey(value.runtimeAbiName.ToLower()))
		Local key:String = value.moduleName.ToLower()
		If sourceUnitPath.length Then key = "source:" + sourceUnitPath.ToLower()
		If emitted.Contains(key) Then Return result
		emitted.Insert(key, value)
		If sourceUnitPath.length Then Return result + SourceUnitHeaderInclude(sourceUnitPath, specialization.configuration)
		' Source-local layouts are already coupled through the owning runtime
		' header selected by the build-output planner.
		If key.StartsWith("source:") Then Return result
		' Quoted application sources use their physical .bmx path as semantic
		' ownership.  Treating that spelling as a dotted module identity creates
		' synthetic paths such as left.mod/bmx.mod; its sibling runtime header is
		' the actual layout authority for an ordinary Struct type argument.
		If value.moduleName.ToLower().EndsWith(".bmx") Then Return result + SourceUnitHeaderInclude(value.moduleName, specialization.configuration)
		Return result + ModuleHeaderInclude(value.moduleName, specialization.configuration)
	End Function

	Function AppendClassTableDeclaration(result:TStringBuilder, classIr:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not result Or Not classIr Or Not classIr.specialization Then Return
		Local abiName:String = classIr.specialization.readableAbiName
		result.Append("struct " + abiName + "_class {~n")
		result.Append("    BBClass *super;~n    void (*free)(BBObject *o);~n    BBDebugScope *debug_scope;~n")
		result.Append("    unsigned int instance_size;~n    void (*ctor)(BBOBJECT o);~n    void (*dtor)(BBOBJECT o);~n")
		result.Append("    BBSTRING (*ToString)(BBOBJECT x);~n    int (*Compare)(BBOBJECT x, BBOBJECT y);~n")
		result.Append("    BBOBJECT (*SendMessage)(BBOBJECT o, BBOBJECT m, BBOBJECT s);~n")
		result.Append("    BBUINT (*HashCode)(BBOBJECT o);~n    BBINT (*Equals)(BBOBJECT o, BBOBJECT y);~n")
		result.Append("    BBINTERFACETABLE itable;~n    void *extra;~n    unsigned int obj_size;~n")
		result.Append("    unsigned int instance_count;~n    unsigned int fields_offset;~n")
		For Local irMethod:TCompilerGenericMethodIr = EachIn classIr.methods
			If irMethod.isDestructor Then Continue
			Local methodOwnerName:String = abiName
			If irMethod.declaringSpecialization Then methodOwnerName = irMethod.declaringSpecialization.readableAbiName
			result.Append("    " + MethodPointerDeclaration(irMethod, methodOwnerName, classIr, diagnostics) + ";~n")
		Next
		result.Append("};~n")
	End Function

	Function EmitDeclarations:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, includeReferencedInterfaces:Int = True, includeReferencedStructs:Int = True, emittedClassLayouts:TMap = Null)
		If Not ir Or Not ir.specialization Then
			diagnostics :+ ["BMXC3020 typed generic specialization IR is required for declaration emission"]
			Return ""
		End If
		Local abiName:String = ir.specialization.readableAbiName
		If ir.isRoutine Then Return EmitRoutineDeclarations(ir, diagnostics)
		If ir.isInterface Then Return EmitInterfaceDeclarations(ir, diagnostics)
		If ir.isStruct Then Return EmitStructDeclarations(ir, diagnostics, includeReferencedStructs)
		If Not emittedClassLayouts Then emittedClassLayouts = New TMap
		Local result:TStringBuilder = New TStringBuilder(4096)
		result.Append("struct " + abiName + "_obj;~n")
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If IsRoutineSpecialization(referenced) Then Continue
			If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_CLASS Then result.Append("struct " + referenced.readableAbiName + "_obj;~n")
		Next
		Local referencedStructEmitted:TMap = New TMap
		Local referencedStructVisiting:TMap = New TMap
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If IsRoutineSpecialization(referenced) Then Continue
			If referenced.IsAbiReferenceOnly() Then Continue
			If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then
				If includeReferencedInterfaces Then result.Append(EmitReferencedInterfaceDeclarations(referenced, ir, diagnostics))
				Continue
			End If
			If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then
				If includeReferencedStructs Then
					Local referencedStructIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
					If referencedStructIr Then result.Append(EmitStructDeclarationTree(referencedStructIr, referencedStructEmitted, referencedStructVisiting, diagnostics))
				End If
				Continue
			End If
			result.Append("struct " + referenced.readableAbiName + "_obj;~n")
			result.Append("struct " + referenced.readableAbiName + "_class;~n")
			result.Append("extern struct " + referenced.readableAbiName + "_class " + referenced.readableAbiName + ";~n")
			result.Append("void " + referenced.readableAbiName + "_register(void);~n")
			result.Append("struct " + referenced.readableAbiName + "_obj *" + referenced.readableAbiName + "_New(BBClass *clas);~n")
			Local referencedClassIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
			If referencedClassIr Then
				result.Append(EmitStaticFieldDeclarations(referencedClassIr, diagnostics))
				For Local constructor:TCompilerGenericMethodIr = EachIn referencedClassIr.constructors
					result.Append("struct " + referenced.readableAbiName + "_obj *" + constructor.abiName + "(BBClass *clas" + TypeConstructorParameters(constructor, referencedClassIr, True) + ");~n")
					result.Append("void " + constructor.abiName + "_init(struct " + referenced.readableAbiName + "_obj *self" + TypeConstructorParameters(constructor, referencedClassIr, True) + ");~n")
				Next
			End If
		Next
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If IsRoutineSpecialization(referenced) Then Continue
			If referenced.IsAbiReferenceOnly() Then Continue
			If referenced = ir.specialization Or referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_CLASS Or emittedClassLayouts.Contains(referenced.key.CanonicalName()) Then Continue
			Local referencedClassIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
			If Not referencedClassIr Then Continue
			Local referencedGuard:String = TCompilerGenericCUnitEmitter.DeclarationGuard("class", referenced.readableAbiName)
			result.Append("#ifndef " + referencedGuard + "~n#define " + referencedGuard + "~n")
			AppendClassTableDeclaration(result, referencedClassIr, diagnostics)
			result.Append("struct " + referenced.readableAbiName + "_obj {~n    struct " + referenced.readableAbiName + "_class *clas;~n")
			For Local referencedField:TCompilerGenericFieldIr = EachIn referencedClassIr.fields
				Local referencedFieldType:String = CType(referencedField.semanticType, referencedClassIr)
				If Not referencedFieldType.length Then
					diagnostics :+ ["BMXC3022 referenced field '" + referencedField.name + "' has no C ABI type"]
					Continue
				End If
				result.Append("    " + referencedFieldType + " " + referencedField.abiName + ";~n")
			Next
			result.Append("};~n#endif~n")
			emittedClassLayouts.Insert(referenced.key.CanonicalName(), referenced)
		Next
		For Local referencedRoutine:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If Not IsRoutineSpecialization(referencedRoutine) Then Continue
			Local referencedRoutineIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referencedRoutine, diagnostics)
			If referencedRoutineIr Then result.Append(EmitRoutineDeclarations(referencedRoutineIr, diagnostics))
		Next
		Local referencedCallDeclarations:TMap = New TMap
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			result.Append(EmitReferencedCallDeclarations(staticField.initializer, ir, referencedCallDeclarations, diagnostics))
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			result.Append(EmitReferencedCallDeclarations(constructor.body, ir, referencedCallDeclarations, diagnostics))
		Next
		For Local ownerMethod:TCompilerGenericMethodIr = EachIn ir.methods
			result.Append(EmitReferencedCallDeclarations(ownerMethod.body, ir, referencedCallDeclarations, diagnostics))
		Next
		Local declarationGuard:String = TCompilerGenericCUnitEmitter.DeclarationGuard("class", abiName)
		result.Append("#ifndef " + declarationGuard + "~n#define " + declarationGuard + "~n")
		result.Append("struct " + abiName + "_obj;~n")
		AppendClassTableDeclaration(result, ir, diagnostics)
		If Not emittedClassLayouts.Contains(ir.specialization.key.CanonicalName()) Then
			result.Append("struct " + abiName + "_obj {~n    struct " + abiName + "_class *clas;~n")
			For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
				Local cFieldType:String = CType(irField.semanticType, ir)
				If Not cFieldType.length Then
					diagnostics :+ ["BMXC3022 field '" + irField.name + "' has no C ABI type"]
					Continue
				End If
				result.Append("    " + CStorageDeclaration(irField.semanticType, irField.abiName, ir) + ";~n")
			Next
			result.Append("};~n")
			emittedClassLayouts.Insert(ir.specialization.key.CanonicalName(), ir.specialization)
		End If
		result.Append("#endif~n")
		result.Append(EmitStaticFieldDeclarations(ir, diagnostics))
		result.Append("extern struct " + abiName + "_class " + abiName + ";~n")
		result.Append("void " + abiName + "_register(void);~n")
		If HasThreadedStaticFields(ir) Then result.Append("void " + ThreadInitializationName(ir) + "(void);~n")
		result.Append("struct " + abiName + "_obj *" + abiName + "_New(BBClass *clas);~n")
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			result.Append("struct " + abiName + "_obj *" + constructor.abiName + "(BBClass *clas" + TypeConstructorParameters(constructor, ir, True) + ");~n")
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			Local cReturnType:String = CType(irMethod.returnType, ir)
			If Not cReturnType.length Then
				diagnostics :+ ["BMXC3021 method '" + irMethod.name + "' has no C ABI type"]
				Continue
			End If
			Local methodOwnerName:String = abiName
			If irMethod.declaringSpecialization Then methodOwnerName = irMethod.declaringSpecialization.readableAbiName
			Local methodParameters:String
			If Not irMethod.isTypeFunction Then methodParameters = "struct " + methodOwnerName + "_obj *self"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				If methodParameters.length Then methodParameters :+ ", "
				methodParameters :+ CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
			If Not methodParameters.length Then methodParameters = "void"
			result.Append(CFunctionDeclaration(irMethod.returnType, irMethod.abiName, methodParameters, ir) + ";~n")
		Next
		Return result.ToString()
	End Function

	Function EmitRoutineDeclarations:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.routine Then
			diagnostics :+ ["BMXC3020 typed generic routine IR is required for declaration emission"]
			Return ""
		End If
		Local parameters:String
		If ir.routine.receiverType Then
			parameters :+ RoutineReceiverCType(ir.routine, ir) + " self"
			If ir.routine.parameters.length Then parameters :+ ", "
		Else If Not ir.routine.parameters.length Then
			parameters :+ "void"
		End If
		If ir.routine.parameters.length Then
			For Local index:Int = 0 Until ir.routine.parameters.length
				If index Then parameters :+ ", "
				Local parameter:TGenericTemplateValueParameter = ir.routine.parameters[index]
				parameters :+ CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
		End If
		Local result:String = CFunctionDeclaration(ir.routine.returnType, ir.routine.abiName, parameters, ir) + ";~n"
		If DynamicMethodDispatcher(ir) Then
			Local callbackParameters:String = "BBOBJECT self"
			For Local parameter:TGenericTemplateValueParameter = EachIn ir.routine.parameters
				callbackParameters :+ ", " + CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
			result :+ "typedef " + CFunctionPointerDeclaration(ir.routine.returnType, DynamicDispatcherCallbackName(ir), callbackParameters, ir) + ";~n"
			result :+ "void " + DynamicDispatcherRegisterName(ir) + "(BBClass *owner, " + DynamicDispatcherCallbackName(ir) + " implementation);~n"
		End If
		Return result
	End Function

	Function EmitStructDeclarations:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, includeReferencedStructs:Int = True)
		Local emitted:TMap = New TMap
		Local visiting:TMap = New TMap
		If Not includeReferencedStructs Then
			emitted.Insert(ir.specialization.key.CanonicalName(), ir.specialization)
			Return EmitStructDeclarationOwn(ir, diagnostics)
		End If
		Return EmitStructDeclarationTree(ir, emitted, visiting, diagnostics)
	End Function

	Function EmitStructDeclarationTree:String(ir:TCompilerGenericSpecializationIr, emitted:TMap, visiting:TMap, diagnostics:String[] Var)
		If Not ir Or Not ir.specialization Then Return ""
		Local key:String = ir.specialization.key.CanonicalName()
		If emitted.Contains(key) Then Return ""
		If visiting.Contains(key) Then
			diagnostics :+ ["BMXC3028 recursive generic Struct declaration layout reached '" + key + "'"]
			Return ""
		End If
		visiting.Insert(key, ir.specialization)
		Local result:String
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Continue
			Local referencedIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
			If referencedIr Then result :+ EmitStructDeclarationTree(referencedIr, emitted, visiting, diagnostics)
		Next
		visiting.Remove(key)
		emitted.Insert(key, ir.specialization)
		Return result + EmitStructDeclarationOwn(ir, diagnostics)
	End Function

	Function EmitStructDeclarationOwn:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local abiName:String = ir.specialization.readableAbiName
		Local declarationGuard:String = TCompilerGenericCUnitEmitter.DeclarationGuard("struct", abiName)
		Local result:String = "#ifndef " + declarationGuard + "~n#define " + declarationGuard + "~n"
		result :+ "struct " + abiName + " {~n"
		If Not ir.fields.length Then result :+ "    unsigned char bmx_empty;~n"
		For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
			Local cFieldType:String = CType(irField.semanticType, ir)
			If Not cFieldType.length Then
				diagnostics :+ ["BMXC3022 generic Struct field '" + irField.name + "' has no C ABI type"]
				Continue
			End If
			result :+ "    " + CStorageDeclaration(irField.semanticType, irField.abiName, ir) + ";~n"
		Next
		result :+ "};~n#endif~n"
		result :+ EmitStaticFieldDeclarations(ir, diagnostics)
		If ir.constructors.length Then
			For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
				result :+ "struct " + abiName + " " + constructor.abiName + "(" + StructConstructorParameters(constructor, ir, True) + ");~n"
			Next
		Else
			result :+ "struct " + abiName + " " + abiName + "_New(void);~n"
		End If
		result :+ "struct " + abiName + " " + abiName + "_New_ObjectNew(void);~n"
		' Referencing specialization units allocate and slice Arrays of this
		' Struct through helpers owned by the Struct specialization unit. Publish
		' that support ABI alongside the retained layout and constructors so every
		' standalone C99 unit has declarations before use.
		result :+ "void " + abiName + "_register(void);~n"
		If HasThreadedStaticFields(ir) Then result :+ "void " + ThreadInitializationName(ir) + "(void);~n"
		result :+ "void bbStructElementInit_" + abiName + "(void *bmx_value);~n"
		result :+ "BBArray *bbArrayNew1DStruct_" + abiName + "(int length);~n"
		result :+ "BBArray *bbArraySliceStruct_" + abiName + "(BBArray *inarr, int beg, int end);~n"
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			Local cReturnType:String = CType(irMethod.returnType, ir)
			If Not cReturnType.length Then
				diagnostics :+ ["BMXC3021 generic Struct method '" + irMethod.name + "' has no C ABI type"]
				Continue
			End If
			Local methodParameters:String
			If Not irMethod.isStatic Then methodParameters = "struct " + abiName + " *self"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				If methodParameters.length Then methodParameters :+ ", "
				methodParameters :+ CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
			If Not methodParameters.length Then methodParameters = "void"
			result :+ CFunctionDeclaration(irMethod.returnType, irMethod.abiName, methodParameters, ir) + ";~n"
		Next
		Return result
	End Function

	Function EmitStaticFieldDeclarations:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Then Return ""
		Local result:String
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			Local declaration:String = CStorageDeclaration(staticField.semanticType, staticField.abiName, ir)
			If Not declaration.length Then
				diagnostics :+ ["BMXC3022 generic static member '" + staticField.name + "' has no C ABI type"]
				Continue
			End If
			Local threadedPrefix:String
			If staticField.isThreadedGlobal Then threadedPrefix = "BBThreadLocal "
			result :+ "extern " + threadedPrefix + declaration + ";~n"
		Next
		Return result
	End Function

	Function StructConstructorParameters:String(constructor:TCompilerGenericMethodIr, ir:TCompilerGenericSpecializationIr, includeNames:Int)
		If Not constructor Or Not constructor.parameters.length Then Return "void"
		Local result:String
		For Local index:Int = 0 Until constructor.parameters.length
			If index Then result :+ ", "
			Local parameter:TGenericTemplateValueParameter = constructor.parameters[index]
			Local parameterName:String
			If includeNames Then parameterName = StructConstructorParameterName(parameter.name)
			result :+ CValueDeclaration(parameter.semanticType, parameterName, ir, parameter.passingMode)
		Next
		Return result
	End Function

	Function EmitReferencedInterfaceDeclarations:String(node:TGenericSpecializationNode, ownerIr:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local result:String
		Local interfaceIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(node, diagnostics)
		If interfaceIr Then
			Local emittedStructs:TMap = New TMap
			Local visitingStructs:TMap = New TMap
			For Local referenced:TGenericSpecializationNode = EachIn interfaceIr.referencedSpecializations
				If referenced.IsAbiReferenceOnly() Or referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Continue
				Local referencedIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
				If referencedIr Then result :+ EmitStructDeclarationTree(referencedIr, emittedStructs, visitingStructs, diagnostics)
			Next
		End If
		Local declarationGuard:String = TCompilerGenericCUnitEmitter.DeclarationGuard("interface", node.readableAbiName + "_methods")
		result :+ "#ifndef " + declarationGuard + "~n#define " + declarationGuard + "~n"
		result :+ "struct " + node.readableAbiName + "_methods {~n"
		Local methods:TCompilerGenericMethodIr[] = TCompilerGenericSpecializationLowerer.EffectiveInterfaceMethods(node, ownerIr, diagnostics)
		For Local interfaceMethod:TCompilerGenericMethodIr = EachIn methods
			Local cReturnType:String = CType(interfaceMethod.returnType, ownerIr)
			If Not cReturnType.length Then diagnostics :+ ["BMXC3021 generic Interface method '" + interfaceMethod.name + "' has no C ABI type"]; Continue
			Local parameters:String = "BBOBJECT"
			For Local parameter:TGenericTemplateValueParameter = EachIn interfaceMethod.parameters
				parameters :+ ", " + CValueDeclaration(parameter.semanticType, "", ownerIr, parameter.passingMode)
			Next
			result :+ "    " + CFunctionPointerDeclaration(interfaceMethod.returnType, interfaceMethod.slotName, parameters, ownerIr) + ";~n"
		Next
		If Not methods.length Then result :+ "    void *reserved;~n"
		result :+ "};~n#endif~nextern const struct BBInterface " + node.readableAbiName + "_ifc;~n"
		result :+ "void " + node.readableAbiName + "_register(void);~n"
		For Local interfaceMethod:TCompilerGenericMethodIr = EachIn methods
			If interfaceMethod.interfaceMethodKind <> TEMPLATE_INTERFACE_METHOD_DEFAULT Then Continue
			Local cReturnType:String = CType(interfaceMethod.returnType, ownerIr)
			If Not cReturnType.length Then Continue
			Local parameters:String = "BBOBJECT"
			For Local parameter:TGenericTemplateValueParameter = EachIn interfaceMethod.parameters
				parameters :+ ", " + CValueDeclaration(parameter.semanticType, "", ownerIr, parameter.passingMode)
			Next
			result :+ CFunctionDeclaration(interfaceMethod.returnType, interfaceMethod.abiName, parameters, ownerIr, "extern ") + ";~n"
		Next
		For Local interfaceMethod:TCompilerGenericMethodIr = EachIn methods
			Local cReturnType:String = CType(interfaceMethod.returnType, ownerIr)
			If Not cReturnType.length Then Continue
			Local helperName:String = InterfaceCallHelperName(node, interfaceMethod)
			Local parameters:String = "BBOBJECT receiver"
			For Local parameterIndex:Int = 0 Until interfaceMethod.parameters.length
				Local parameter:TGenericTemplateValueParameter = interfaceMethod.parameters[parameterIndex]
				parameters :+ ", " + CValueDeclaration(parameter.semanticType, "bmx_arg" + parameterIndex, ownerIr, parameter.passingMode)
			Next
			result :+ CFunctionDeclaration(interfaceMethod.returnType, helperName, parameters, ownerIr, "static inline ") + " {~n    "
			If cReturnType <> "void" Then result :+ "return "
			result :+ "((struct " + node.readableAbiName + "_methods *)bbObjectInterface(receiver, (BBInterface *)&" + node.readableAbiName + "_ifc))->" + interfaceMethod.slotName + "(receiver"
			For Local parameterIndex:Int = 0 Until interfaceMethod.parameters.length
				result :+ ", bmx_arg" + parameterIndex
			Next
			result :+ ");~n}~n"
		Next
		Return result
	End Function

	Function InterfaceCallHelperName:String(interfaceNode:TGenericSpecializationNode, interfaceMethod:TCompilerGenericMethodIr)
		Return TCompilerAbiNamer.Sanitize(interfaceNode.readableAbiName + "_call_" + interfaceMethod.slotName)
	End Function

	Function EmitInterfaceDeclarations:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local abiName:String = ir.specialization.readableAbiName
		Local declarationGuard:String = TCompilerGenericCUnitEmitter.DeclarationGuard("interface", abiName + "_methods")
		Local result:String
		' Interface method tables and inline call helpers use Struct results and
		' parameters by value. C99 requires those generic Struct layouts to be
		' complete before the function-pointer declarations, not merely forward
		' declared later in another specialization unit.
		Local emittedStructs:TMap = New TMap
		Local visitingStructs:TMap = New TMap
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If referenced.IsAbiReferenceOnly() Or referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Continue
			Local referencedIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
			If referencedIr Then result :+ EmitStructDeclarationTree(referencedIr, emittedStructs, visitingStructs, diagnostics)
		Next
		result :+ "#ifndef " + declarationGuard + "~n#define " + declarationGuard + "~n"
		result :+ "struct " + abiName + "_methods {~n"
		If Not ir.methods.length Then result :+ "    void *reserved;~n"
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			Local returnType:String = CType(irMethod.returnType, ir)
			If Not returnType.length Then diagnostics :+ ["BMXC3021 generic Interface method '" + irMethod.name + "' has no C ABI type"]; Continue
			Local parameters:String = "BBOBJECT"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				parameters :+ ", " + CValueDeclaration(parameter.semanticType, "", ir, parameter.passingMode)
			Next
			result :+ "    " + CFunctionPointerDeclaration(irMethod.returnType, irMethod.slotName, parameters, ir) + ";~n"
		Next
		result :+ "};~n#endif~n"
		result :+ "extern const struct BBInterface " + abiName + "_ifc;~n"
		result :+ "void " + abiName + "_register(void);~n"
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If irMethod.interfaceMethodKind <> TEMPLATE_INTERFACE_METHOD_DEFAULT Then Continue
			Local returnType:String = CType(irMethod.returnType, ir)
			If Not returnType.length Then Continue
			Local parameters:String = "BBOBJECT"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				parameters :+ ", " + CValueDeclaration(parameter.semanticType, "", ir, parameter.passingMode)
			Next
			result :+ CFunctionDeclaration(irMethod.returnType, irMethod.abiName, parameters, ir, "extern ") + ";~n"
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			Local returnType:String = CType(irMethod.returnType, ir)
			If Not returnType.length Then Continue
			Local helperName:String = InterfaceCallHelperName(ir.specialization, irMethod)
			Local parameters:String = "BBOBJECT receiver"
			For Local parameterIndex:Int = 0 Until irMethod.parameters.length
				Local parameter:TGenericTemplateValueParameter = irMethod.parameters[parameterIndex]
				parameters :+ ", " + CValueDeclaration(parameter.semanticType, "bmx_arg" + parameterIndex, ir, parameter.passingMode)
			Next
			result :+ CFunctionDeclaration(irMethod.returnType, helperName, parameters, ir, "static inline ") + " {~n    "
			If returnType <> "void" Then result :+ "return "
			result :+ "((struct " + abiName + "_methods *)bbObjectInterface(receiver, (BBInterface *)&" + abiName + "_ifc))->" + irMethod.slotName + "(receiver"
			For Local parameterIndex:Int = 0 Until irMethod.parameters.length
				result :+ ", bmx_arg" + parameterIndex
			Next
			result :+ ");~n}~n"
		Next
		Return result
	End Function

	Function EmitReferencedCallDeclarations:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, emitted:TMap, diagnostics:String[] Var)
		If Not node Then Return ""
		Local result:String
		If node.kind = TEMPLATE_NODE_NAME And node.identity = "ordinary-callable-reference" Then
			If Not node.referencedSymbol Or Not node.referencedSymbol.overloadKey.length Or Not node.semanticType Or node.semanticType.kind <> TEMPLATE_TYPE_CALLABLE Then
				diagnostics :+ ["BMXC3075 ordinary callable reference has no stable signature/linkage record"]
			Else If Not emitted.Contains(node.referencedSymbol.overloadKey) Then
				result :+ "extern " + CType(node.semanticType.elementType, ir) + " " + node.referencedSymbol.overloadKey + "(" + CallableCParameterList(node.semanticType, ir) + ");~n"
				emitted.Insert(node.referencedSymbol.overloadKey, node)
			End If
		End If
		If node.kind = TEMPLATE_NODE_DECLARATION And node.identity = "catch-parameter" And node.semanticType And node.semanticType.kind = TEMPLATE_TYPE_NAMED And node.semanticType.runtimeAbiName.length Then
			Local descriptorName:String = node.semanticType.runtimeAbiName
			If node.semanticType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then descriptorName :+ "_ifc"
			If Not emitted.Contains(descriptorName) Then
				If node.semanticType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then
					result :+ "extern const struct BBInterface " + descriptorName + ";~n"
				Else If node.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS Then
					result :+ "extern BBClass " + descriptorName + ";~n"
				End If
				emitted.Insert(descriptorName, node)
			End If
		End If
		If node.kind = TEMPLATE_NODE_NAME And node.identity = "ordinary-global" Then
			' ThreadedGlobal declarations inside a source generic currently bind
			' through the language model's Global namespace.  Their unqualified
			' symbol reference is nevertheless owned by the closed specialization;
			' do not publish an extern for the transient private-global ABI.
			Local specializationStatic:TCompilerGenericFieldIr = StaticFieldForUnqualifiedOrdinaryGlobal(node, ir)
			If specializationStatic Then
				' The specialization declaration emitted above is authoritative.
			Else If Not node.referencedSymbol Or Not node.referencedSymbol.overloadKey.length Then
				diagnostics :+ ["BMXC3048 ordinary Global dependency '" + node.valueText + "' has no stable linkage identity"]
			Else If Not emitted.Contains(node.referencedSymbol.overloadKey) Then
				Local globalType:String = CValueDeclaration(node.semanticType, node.referencedSymbol.overloadKey, ir)
				If Not globalType.length Then
					diagnostics :+ ["BMXC3048 ordinary Global dependency '" + node.valueText + "' has no supported value ABI"]
				Else
					result :+ "extern " + globalType + ";~n"
					emitted.Insert(node.referencedSymbol.overloadKey, node)
				End If
			End If
		End If
		If node.kind = TEMPLATE_NODE_CALL And node.children.length Then
			If node.identity = "closure-call" Then
				Local closureType:TTemplateTypeReference = node.children[0].semanticType
				If Not TCompilerGenericSpecializationLowerer.SupportedClosureType(closureType, ir) Then
					diagnostics :+ ["BMXC3076 managed Closure call has no supported retained signature"]
				Else
					Local helperName:String = ClosureCallHelperName(closureType)
					If Not emitted.Contains(helperName) Then
						Local helperGuard:String = DeclarationGuard("closure-call", helperName)
						Local parameters:String = "BBClosure *closure"
						Local signatureParameters:String = "BBOBJECT environment"
						For Local index:Int = 0 Until closureType.arguments.length
							Local mode:Int = closureType.callableParameterModes[index]
							parameters :+ ", " + CValueDeclaration(closureType.arguments[index], "bmx_arg" + index, ir, mode)
							signatureParameters :+ ", " + CValueDeclaration(closureType.arguments[index], "bmx_arg" + index, ir, mode)
						Next
						Local declaration:String = CFunctionDeclaration(closureType.elementType, helperName, parameters, ir, "static inline ") + " {~n"
						declaration :+ "    union { BBFuncPtr source; " + CFunctionPointerDeclaration(closureType.elementType, "target", signatureParameters, ir) + "; } invoke;~n"
						declaration :+ "    if ((BBOBJECT)closure == (BBOBJECT)&bbNullObject) brl_blitz_NullFunctionError();~n"
						declaration :+ "    invoke.source = closure->invoke;~n    "
						If Not VoidType(closureType.elementType) Then declaration :+ "return "
						declaration :+ "invoke.target(closure->environment"
						For Local index:Int = 0 Until closureType.arguments.length
							declaration :+ ", bmx_arg" + index
						Next
						result :+ "#ifndef " + helperGuard + "~n#define " + helperGuard + "~n"
						result :+ declaration + ");~n}~n#endif~n"
						emitted.Insert(helperName, node)
					End If
				End If
			End If
			If node.identity = "ordinary-interface-call" And node.referencedSymbol And node.referencedSymbol.overloadKey.length Then
				Local descriptorName:String = node.referencedSymbol.overloadKey + "_ifc"
				If Not emitted.Contains(descriptorName) Then
					result :+ "extern const struct BBInterface " + descriptorName + ";~n"
					emitted.Insert(descriptorName, node)
				End If
				Local helperName:String = OrdinaryInterfaceHelperName(node)
				If helperName.length And Not emitted.Contains(helperName) Then
					Local returnType:String = CType(node.semanticType, ir)
					If Not returnType.length Then
						diagnostics :+ ["BMXC3057 ordinary Interface operation '" + node.valueText + "' has no supported closed return ABI"]
					Else
						Local declarationParameters:String = "BBOBJECT receiver"
						Local signatureParameters:String = "BBOBJECT"
						Local supportedArguments:Int = True
						For Local index:Int = 1 Until node.children.length
							Local passingMode:Int = PARAMETER_PASS_VALUE
							If node.children[index].kind = TEMPLATE_NODE_CONVERSION And (node.children[index].valueText = CONVERSION_VAR_REFERENCE Or node.children[index].valueText = CONVERSION_POINTER_TO_VAR_REFERENCE) Then passingMode = PARAMETER_PASS_VAR
							Local argumentType:String = CValueDeclaration(node.children[index].semanticType, "", ir, passingMode)
							If Not argumentType.length Then
								diagnostics :+ ["BMXC3057 ordinary Interface operation '" + node.valueText + "' argument " + index + " has no supported closed ABI type"]
								supportedArguments = False
								Exit
							End If
							declarationParameters :+ ", " + CValueDeclaration(node.children[index].semanticType, "bmx_arg" + index, ir, passingMode)
							signatureParameters :+ ", " + argumentType
						Next
						If supportedArguments Then
							Local declaration:String = CFunctionDeclaration(node.semanticType, helperName, declarationParameters, ir, "static inline ") + " {~n    "
							If Not VoidType(node.semanticType) Then declaration :+ "return "
							declaration :+ "((" + CFunctionPointerDeclaration(node.semanticType, "", signatureParameters, ir) + ")((void **)bbObjectInterface(receiver, (BBINTERFACE)&" + descriptorName + "))[" + node.runtimeDispatchIndex + "])(receiver"
							For Local index:Int = 1 Until node.children.length
								declaration :+ ", bmx_arg" + index
							Next
							result :+ declaration + ");~n}~n"
							emitted.Insert(helperName, node)
						End If
					End If
				End If
			Else If node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].valueText = "ordinary-routine-signature" Then
				If Not node.referencedSymbol Or Not node.referencedSymbol.overloadKey.length Then
					diagnostics :+ ["BMXC3048 ordinary routine dependency '" + node.valueText + "' has no stable linkage identity"]
				Else If Not emitted.Contains(node.referencedSymbol.overloadKey) Then
					Local signature:TGenericTemplateNode = node.children[0]
					If signature.identity.length Then
						Local nativeDeclaration:String = TCompilerNativeDeclaration.Declaration(signature.identity)
						If Not nativeDeclaration.length Then
							diagnostics :+ ["BMXC3048 native routine dependency '" + node.valueText + "' has no valid retained C declaration"]
						Else If Not signature.identity.Trim().EndsWith("!") Then
							result :+ nativeDeclaration + ";~n"
						End If
						emitted.Insert(node.referencedSymbol.overloadKey, node)
					Else
						Local returnType:String = CType(node.semanticType, ir)
						If Not returnType.length Then
							diagnostics :+ ["BMXC3048 ordinary routine dependency '" + node.valueText + "' has no supported return ABI"]
						Else
							Local parameters:String
							If Not signature.children.length Then
								parameters :+ "void"
							Else
								Local supportedParameters:Int = True
								For Local index:Int = 0 Until signature.children.length
									If index Then parameters :+ ", "
									Local parameter:TGenericTemplateNode = signature.children[index]
									Local parameterType:String = CValueDeclaration(parameter.semanticType, "", ir, Int(parameter.valueText))
									If parameter.valueText = "ordinary-struct-receiver" And parameter.semanticType And parameter.semanticType.runtimeKind = TEMPLATE_RUNTIME_STRUCT And parameterType.length Then
										parameters :+ parameterType + " *"
									Else If Not parameterType.length Or (Int(parameter.valueText) <> PARAMETER_PASS_VALUE And Int(parameter.valueText) <> PARAMETER_PASS_VAR) Then
										diagnostics :+ ["BMXC3048 ordinary routine dependency '" + node.valueText + "' parameter " + index + " has no supported value/Var ABI"]
										supportedParameters = False
									Else
										parameters :+ parameterType
									End If
								Next
								If Not supportedParameters Then parameters = ""
							End If
							If parameters.length Then
								result :+ CFunctionDeclaration(node.semanticType, node.referencedSymbol.overloadKey, parameters, ir) + ";~n"
								emitted.Insert(node.referencedSymbol.overloadKey, node)
							End If
						End If
					End If
				End If
			Else If node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].valueText = "runtime-header-routine" Then
				' The authoritative prototype is already supplied by blitz.h.
			End If
			Local receiver:TGenericTemplateNode = node.children[0]
			Local target:TGenericSpecializationNode
			Local localRoutineMarker:Int = receiver And receiver.kind = TEMPLATE_NODE_BLOCK And (receiver.valueText = "local-routine-signature" Or receiver.valueText = "local-routine-reference")
			If receiver And Not localRoutineMarker Then target = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(receiver.semanticType, ir)
			If target And target.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_INTERFACE And Not (receiver.kind = TEMPLATE_NODE_SELF And receiver.valueText = "self") And receiver.valueText <> "eachin-protocol-receiver" Then
				Local targetMethod:TCompilerGenericMethodIr = TypeOperation(target, node, ir, diagnostics)
				Local functionName:String
				If targetMethod Then functionName = targetMethod.abiName
				If Not emitted.Contains(functionName) Then
					Local returnType:String = CType(node.semanticType, ir)
					If Not targetMethod Then
						' TypeOperation supplied the precise diagnostic.
					Else If Not returnType.length Then
						diagnostics :+ ["BMXC3027 referenced generic call '" + node.valueText + "' has no supported return ABI"]
					Else
						Local methodOwner:TGenericSpecializationNode = targetMethod.declaringSpecialization
						If Not methodOwner Then methodOwner = target
						Local parameters:String
						If Not targetMethod.isStatic And Not targetMethod.isTypeFunction Then
							If targetMethod.receiverIsStruct Then parameters = "struct " + methodOwner.readableAbiName + " *" Else parameters = "struct " + methodOwner.readableAbiName + "_obj *"
						End If
						Local supportedArguments:Int = True
						For Local index:Int = 0 Until targetMethod.parameters.length
							Local argumentType:String = CValueDeclaration(targetMethod.parameters[index].semanticType, "", ir, targetMethod.parameters[index].passingMode)
							If Not argumentType.length Then
								diagnostics :+ ["BMXC3027 referenced generic call '" + node.valueText + "' argument " + (index + 1) + " has no supported ABI"]
								supportedArguments = False
							Else
								If parameters.length Then parameters :+ ", "
								parameters :+ argumentType
							End If
						Next
						If supportedArguments Then
							If Not parameters.length Then parameters = "void"
							result :+ CFunctionDeclaration(targetMethod.returnType, functionName, parameters, ir) + ";~n"
							emitted.Insert(functionName, node)
						End If
					End If
				End If
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			result :+ EmitReferencedCallDeclarations(child, ir, emitted, diagnostics)
		Next
		Return result
	End Function

	Function ClosureCallHelperName:String(value:TTemplateTypeReference)
		If Not value Then Return "bmx_closure_call_invalid"
		Return "bmx_closure_call_" + TCompilerStableDigest.Sha256(value.CanonicalName())[..16]
	End Function

	Function ClosureRuntimeDeclaration:String()
		Return "#ifndef BMX_BBCLOSURE_DEFINED~n#define BMX_BBCLOSURE_DEFINED~ntypedef struct BBClosure {~n    BBObject object;~n    BBFuncPtr invoke;~n    BBOBJECT environment;~n} BBClosure;~n#endif~n~n#ifndef BMX_BCC2_GENERIC_CLOSEABLE_ITERATOR_DEFINED~n#define BMX_BCC2_GENERIC_CLOSEABLE_ITERATOR_DEFINED~nextern const struct BBInterface brl_blitz_ICloseable_ifc;~nstruct BCC2_GenericCloseableIteratorMethods { void (*m_Close)(BBOBJECT); };~n#endif~n~n"
	End Function

	Function LocalRoutineAbiName:String(ownerMethod:TCompilerGenericMethodIr, signature:TGenericTemplateNode, fallbackName:String)
		Local ownerName:String
		If ownerMethod Then
			ownerName = ownerMethod.localRoutineOwnerAbiName
			If Not ownerName.length Then ownerName = ownerMethod.abiName
		End If
		Local routineName:String = fallbackName
		If signature And signature.referencedSymbol And signature.referencedSymbol.qualifiedName.length Then routineName = signature.referencedSymbol.qualifiedName
		Local identity:String
		If signature Then identity = signature.identity
		Local digest:String = TCompilerStableDigest.Sha256(identity)
		Return TCompilerAbiNamer.Sanitize(ownerName + "_local_" + routineName + "_" + digest[..12])
	End Function

	Function CollectLocalRoutineSignatures(node:TGenericTemplateNode, seen:TMap, signatures:TGenericTemplateNode[] Var)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_CALL And node.children.length And node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].valueText = "local-routine-signature" Then
			Local signature:TGenericTemplateNode = node.children[0]
			If signature.identity.length And Not seen.Contains(signature.identity) Then
				seen.Insert(signature.identity, signature)
				signatures :+ [signature]
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectLocalRoutineSignatures(child, seen, signatures)
		Next
	End Function

	Function LocalRoutineIr:TCompilerGenericMethodIr(ownerMethod:TCompilerGenericMethodIr, signature:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ownerMethod Or Not signature Or signature.valueText <> "local-routine-signature" Or Not signature.identity.length Or signature.children.length < 1 Then
			diagnostics :+ ["BMXC3068 local routine has an invalid canonical helper record"]
			Return Null
		End If
		Local result:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
		If signature.referencedSymbol Then result.name = signature.referencedSymbol.qualifiedName
		If Not result.name.length Then result.name = "local"
		result.abiName = LocalRoutineAbiName(ownerMethod, signature, result.name)
		result.localRoutineOwnerAbiName = ownerMethod.localRoutineOwnerAbiName
		If Not result.localRoutineOwnerAbiName.length Then result.localRoutineOwnerAbiName = ownerMethod.abiName
		result.returnType = signature.semanticType
		result.source = signature.source
		result.body = signature.children[signature.children.length - 1]
		result.coverageName = "Local Function " + result.name + " in " + GenericCoverageFunctionName(ownerMethod, ir)
		If result.source And result.source.line > 0 Then result.coverageName :+ " at line " + result.source.line
		If result.source And result.source.column > 0 Then result.coverageName :+ " column " + result.source.column
		If Not TCompilerGenericSpecializationLowerer.SupportedType(result.returnType, ir) Then
			diagnostics :+ ["BMXC3068 local routine '" + result.name + "' has no supported closed result ABI"]
			Return Null
		End If
		For Local index:Int = 0 Until signature.children.length - 1
			Local parameterNode:TGenericTemplateNode = signature.children[index]
			If Not parameterNode Or parameterNode.kind <> TEMPLATE_NODE_DECLARATION Or Not parameterNode.valueText.length Then
				diagnostics :+ ["BMXC3068 local routine '" + result.name + "' has an invalid canonical parameter record"]
				Return Null
			End If
			If parameterNode.valueText = "capture:self" Then
				result.receiverType = ownerMethod.receiverType
				result.receiverIsStruct = ownerMethod.receiverIsStruct Or ir.isStruct
				If Not result.receiverType And ir.specialization And ir.specialization.artifact And ir.specialization.artifact.identity Then
					result.receiverType = New TTemplateTypeReference
					result.receiverType.kind = TEMPLATE_TYPE_NAMED
					result.receiverType.moduleName = ir.specialization.artifact.identity.moduleName
					result.receiverType.symbolName = ir.specialization.artifact.identity.qualifiedName
					result.receiverType.runtimeAbiName = ir.specialization.readableAbiName
					If ir.isStruct Then result.receiverType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Else result.receiverType.runtimeKind = TEMPLATE_RUNTIME_CLASS
				End If
				Continue
			End If
			Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
			parameter.name = parameterNode.valueText
			If parameter.name.StartsWith("capture:outer:") Then parameter.name = parameter.name[14..]
			If parameterNode.valueText.StartsWith("capture:outer:") Then parameter.passingMode = PARAMETER_PASS_VAR Else parameter.passingMode = Int(parameterNode.identity)
			If Not parameter.passingMode Then parameter.passingMode = PARAMETER_PASS_VALUE
			parameter.semanticType = parameterNode.semanticType
			parameter.source = parameterNode.source
			parameter.optional = parameterNode.children.length > 0
			If parameter.optional Then parameter.defaultValue = parameterNode.children[0]
			If Not TCompilerGenericSpecializationLowerer.SupportedCallableParameter(parameter, ir) Then
				diagnostics :+ ["BMXC3068 local routine '" + result.name + "' parameter '" + parameter.name + "' has no supported closed value/Var ABI"]
				Return Null
			End If
			result.parameters :+ [parameter]
		Next
		Local localNames:TMap = New TMap
		For Local parameter:TGenericTemplateValueParameter = EachIn result.parameters
			localNames.Insert(parameter.name.ToLower(), parameter)
		Next
		CollectDeclaredLocalNames(result.body, localNames)
		Local capturedName:String = FirstUnknownLocalRoutineName(result.body, localNames)
		If capturedName.length Then
			diagnostics :+ ["BMXC3068 local routine '" + result.name + "' captures outer value '" + capturedName + "'; canonical local-routine environments are not yet supported"]
			Return Null
		End If
		Return result
	End Function

	Function ContainsTemplateNodeKind:Int(node:TGenericTemplateNode, kind:Int)
		If Not node Then Return False
		If node.kind = kind Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If ContainsTemplateNodeKind(child, kind) Then Return True
		Next
		Return False
	End Function

	Function ContainsImplicitSelfMember:Int(node:TGenericTemplateNode)
		If Not node Then Return False
		If node.kind = TEMPLATE_NODE_MEMBER And Not node.children.length Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If ContainsImplicitSelfMember(child) Then Return True
		Next
		Return False
	End Function

	Function ContainsTemplateSelf:Int(node:TGenericTemplateNode, valueText:String = "")
		If Not node Then Return False
		If node.kind = TEMPLATE_NODE_SELF And (Not valueText.length Or node.valueText = valueText) Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If ContainsTemplateSelf(child, valueText) Then Return True
		Next
		Return False
	End Function

	Function CollectDeclaredLocalNames(node:TGenericTemplateNode, names:TMap)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_DECLARATION And node.valueText.length Then names.Insert(node.valueText.ToLower(), node)
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectDeclaredLocalNames(child, names)
		Next
	End Function

	Function FirstUnknownLocalRoutineName:String(node:TGenericTemplateNode, names:TMap)
		If Not node Then Return ""
		If node.kind = TEMPLATE_NODE_NAME And Not node.identity.length And Not names.Contains(node.valueText.ToLower()) Then Return node.valueText
		For Local child:TGenericTemplateNode = EachIn node.children
			Local result:String = FirstUnknownLocalRoutineName(child, names)
			If result.length Then Return result
		Next
		Return ""
	End Function

	Function CollectClosureLiterals(node:TGenericTemplateNode, seen:TMap, literals:TGenericTemplateNode[] Var)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL And node.identity.length And Not seen.Contains(node.identity) Then
			seen.Insert(node.identity, node)
			literals :+ [node]
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectClosureLiterals(child, seen, literals)
		Next
	End Function

	Function CollectClosureLiteralHierarchy(node:TGenericTemplateNode, parentLiteral:TGenericTemplateNode, seen:TMap, literals:TGenericTemplateNode[] Var, parents:TMap)
		If Not node Then Return
		Local activeParent:TGenericTemplateNode = parentLiteral
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL And node.identity.length Then
			If Not seen.Contains(node.identity) Then
				seen.Insert(node.identity, node)
				literals :+ [node]
				If parentLiteral Then parents.Insert(node, parentLiteral)
			End If
			activeParent = node
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectClosureLiteralHierarchy(child, activeParent, seen, literals, parents)
		Next
	End Function

	Function ClosureLiteralAbiName:String(ownerMethod:TCompilerGenericMethodIr, literal:TGenericTemplateNode)
		Local ownerName:String = "generic"
		If ownerMethod Then
			ownerName = ownerMethod.localRoutineOwnerAbiName
			If Not ownerName.length Then ownerName = ownerMethod.abiName
		End If
		Local literalKind:String = "_closure_"
		If literal And literal.semanticType And literal.semanticType.kind = TEMPLATE_TYPE_CALLABLE Then literalKind = "_function_"
		Return TCompilerAbiNamer.Sanitize(ownerName + literalKind + TCompilerStableDigest.Sha256(literal.identity)[..12])
	End Function

	Function ClosureLiteralIr:TCompilerGenericMethodIr(ownerMethod:TCompilerGenericMethodIr, literal:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local managed:Int = literal And literal.semanticType And literal.semanticType.kind = TEMPLATE_TYPE_CLOSURE
		Local thin:Int = literal And literal.semanticType And literal.semanticType.kind = TEMPLATE_TYPE_CALLABLE
		If Not literal Or literal.kind <> TEMPLATE_NODE_FUNCTION_LITERAL Or (Not managed And Not thin) Or (literal.children.length <> 2 And literal.children.length <> 3) Then
			diagnostics :+ ["BMXC1243 generic Function literal has an invalid canonical record"]
			Return Null
		End If
		Local signature:TGenericTemplateNode = literal.children[0]
		Local bodyIndex:Int = literal.children.length - 1
		Local captureBlock:TGenericTemplateNode
		If literal.children.length = 3 Then captureBlock = literal.children[1]
		Local expectedSignature:String = "function-literal-signature"
		If managed Then expectedSignature = "closure-literal-signature"
		If Not signature Or signature.kind <> TEMPLATE_NODE_BLOCK Or signature.valueText <> expectedSignature Or (captureBlock And (captureBlock.kind <> TEMPLATE_NODE_BLOCK Or captureBlock.valueText <> "closure-literal-captures")) Or Not literal.children[bodyIndex] Or literal.children[bodyIndex].kind <> TEMPLATE_NODE_BLOCK Then
			diagnostics :+ ["BMXC1243 generic Function literal has an invalid signature or body"]
			Return Null
		End If
		If (managed And Not TCompilerGenericSpecializationLowerer.SupportedClosureType(literal.semanticType, ir)) Or (thin And Not TCompilerGenericSpecializationLowerer.SupportedCallableType(literal.semanticType, ir)) Then
			diagnostics :+ ["BMXC1243 generic Function literal has no supported closed ABI"]
			Return Null
		End If
		If thin And captureBlock Then
			diagnostics :+ ["BMXC1240 thin Function literal cannot retain a canonical capture environment"]
			Return Null
		End If
		Local result:TCompilerGenericMethodIr = New TCompilerGenericMethodIr
		If managed Then result.name = "Closure" Else result.name = "<Function>"
		If ownerMethod Then
			result.closureDebugOwnerName = ownerMethod.closureDebugOwnerName
			If Not result.closureDebugOwnerName.length Then result.closureDebugOwnerName = ownerMethod.name
		End If
		If Not result.closureDebugOwnerName.length Then result.closureDebugOwnerName = "generic specialization"
		Local debugKind:String = "Function"
		If managed Then debugKind = "Closure"
		result.debugName = debugKind + " in " + result.closureDebugOwnerName
		If literal.source And literal.source.line > 0 Then result.debugName :+ " at line " + literal.source.line
		Local coverageOwnerName:String = GenericCoverageFunctionName(ownerMethod, ir)
		If Not coverageOwnerName.length Then coverageOwnerName = result.closureDebugOwnerName
		result.coverageName = debugKind + " in " + coverageOwnerName
		If literal.source And literal.source.line > 0 Then result.coverageName :+ " at line " + literal.source.line
		If literal.source And literal.source.column > 0 Then result.coverageName :+ " column " + literal.source.column
		result.abiName = ClosureLiteralAbiName(ownerMethod, literal)
		result.localRoutineOwnerAbiName = result.abiName
		result.returnType = literal.semanticType.elementType
		result.source = literal.source
		result.body = literal.children[bodyIndex]
		result.isClosureInvoke = managed
		For Local parameterNode:TGenericTemplateNode = EachIn signature.children
			If Not parameterNode Or parameterNode.kind <> TEMPLATE_NODE_DECLARATION Then
				diagnostics :+ ["BMXC1243 generic Function literal has an invalid parameter record"]
				Return Null
			End If
			Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
			parameter.name = parameterNode.valueText
			parameter.semanticType = parameterNode.semanticType
			parameter.passingMode = Int(parameterNode.identity)
			parameter.source = parameterNode.source
			If Not TCompilerGenericSpecializationLowerer.SupportedCallableParameter(parameter, ir) Then
				diagnostics :+ ["BMXC1243 generic Function literal parameter '" + parameter.name + "' has no supported closed ABI"]
				Return Null
			End If
			result.parameters :+ [parameter]
		Next
		Local capturesSelf:Int
		If captureBlock Then
			For Local captureNode:TGenericTemplateNode = EachIn captureBlock.children
				If Not captureNode Or captureNode.kind <> TEMPLATE_NODE_DECLARATION Or (captureNode.identity <> "closure-capture-local" And captureNode.identity <> "closure-capture-parameter" And captureNode.identity <> "closure-capture-self") Or Not captureNode.valueText.length Or Not captureNode.semanticType Then
					diagnostics :+ ["BMXC1243 generic Closure literal has an invalid capture record"]
					Return Null
				End If
				If captureNode.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Or Not TCompilerGenericSpecializationLowerer.SupportedType(captureNode.semanticType, ir) Then
					diagnostics :+ ["BMXC1243 generic Closure capture '" + captureNode.valueText + "' has no supported managed-environment ABI"]
					Return Null
				End If
				Local capture:TCompilerGenericClosureCaptureIr = New TCompilerGenericClosureCaptureIr
				capture.name = captureNode.valueText
				capture.semanticType = captureNode.semanticType
				capture.isParameter = captureNode.identity = "closure-capture-parameter"
				capture.isSelf = captureNode.identity = "closure-capture-self"
				capture.source = captureNode.source
				Local captureActivation:TGenericTemplateNode = InnermostActivationContainingSource(ownerMethod.body, capture.source)
				If captureActivation Then capture.activationIdentity = ClosureActivationIdentity(captureActivation)
				result.closureCaptures :+ [capture]
				If capture.isSelf Then capturesSelf = True
			Next
		End If
		If (ContainsTemplateSelf(result.body, "self") Or ContainsImplicitSelfMember(result.body)) And Not capturesSelf Then
			If thin Then diagnostics :+ ["BMXC1240 thin Function literal cannot capture Self"] Else diagnostics :+ ["BMXC1243 generic Closure literal uses Self without a canonical capture record"]
			Return Null
		End If
		Local localNames:TMap = New TMap
		For Local parameter:TGenericTemplateValueParameter = EachIn result.parameters
			localNames.Insert(parameter.name.ToLower(), parameter)
		Next
		CollectDeclaredLocalNames(result.body, localNames)
		For Local capture:TCompilerGenericClosureCaptureIr = EachIn result.closureCaptures
			localNames.Insert(capture.name.ToLower(), capture)
		Next
		Local capturedName:String = FirstUnknownLocalRoutineName(result.body, localNames)
		If capturedName.length Then
			If thin Then diagnostics :+ ["BMXC1240 thin Function literal refers to outer value '" + capturedName + "'"] Else diagnostics :+ ["BMXC1243 generic Closure literal refers to outer value '" + capturedName + "' without a canonical capture record"]
			Return Null
		End If
		Return result
	End Function

	Function InnermostActivationContainingSource:TGenericTemplateNode(node:TGenericTemplateNode, source:TTemplateSourceLocation)
		If Not node Or Not source Or node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return Null
		Local result:TGenericTemplateNode
		If IsClosureActivationNode(node) And SourceContains(node.source, source) Then result = node
		For Local child:TGenericTemplateNode = EachIn node.children
			Local nested:TGenericTemplateNode = InnermostActivationContainingSource(child, source)
			If nested Then result = nested
		Next
		Return result
	End Function

	Function IsClosureActivationNode:Int(node:TGenericTemplateNode)
		Return node And (node.kind = TEMPLATE_NODE_LOOP Or (node.kind = TEMPLATE_NODE_BLOCK And node.valueText = "catch-clause"))
	End Function

	Function ClosureActivationIdentity:String(node:TGenericTemplateNode)
		If Not node Then Return ""
		If node.kind = TEMPLATE_NODE_LOOP Then Return node.identity
		If node.kind = TEMPLATE_NODE_BLOCK And node.valueText = "catch-clause" Then Return "catch_" + SourceIdentity(node)
		Return ""
	End Function

	Function BuildClosureEnvironment:TCompilerGenericClosureEnvironmentIr(ownerMethod:TCompilerGenericMethodIr, routines:TCompilerGenericMethodIr[], ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ownerMethod Then Return Null
		Local result:TCompilerGenericClosureEnvironmentIr = ownerMethod.closureEnvironment
		If result Then
			Local retainedResult:Int
			For Local retainedEnvironment:TCompilerGenericClosureEnvironmentIr = EachIn ownerMethod.closureEnvironments
				If retainedEnvironment = result Then retainedResult = True; Exit
			Next
			If Not retainedResult Then ownerMethod.closureEnvironments :+ [result]
		End If
		Local needsParent:Int
		For Local routine:TCompilerGenericMethodIr = EachIn routines
			If Not routine Then Continue
			For Local capture:TCompilerGenericClosureCaptureIr = EachIn routine.closureCaptures
				If MethodOwnsClosureCapture(ownerMethod, capture) Then
					Local environment:TCompilerGenericClosureEnvironmentIr
					If capture.activationIdentity.length Then
						environment = TCompilerGenericClosureEnvironmentIr(ownerMethod.activationClosureEnvironments.ValueForKey(capture.activationIdentity))
						If Not environment Then
							environment = NewClosureEnvironment(ownerMethod, "_" + capture.activationIdentity)
							environment.activationIdentity = capture.activationIdentity
							environment.localName = "bmx_closure_environment_" + TCompilerAbiNamer.Sanitize(capture.activationIdentity)
							ownerMethod.activationClosureEnvironments.Insert(capture.activationIdentity, environment)
							ownerMethod.closureEnvironments :+ [environment]
						End If
					Else
						If Not result Then
							result = NewClosureEnvironment(ownerMethod, "")
							ownerMethod.closureEnvironments :+ [result]
						End If
						environment = result
					End If
					Local key:String = capture.name.ToLower()
					If Not environment.capturesByName.Contains(key) Then
						capture.abiName = TCompilerAbiNamer.Sanitize("capture_" + capture.name + "_" + TCompilerStableDigest.Sha256(key + ":" + capture.semanticType.CanonicalName() + ":" + capture.activationIdentity)[..12])
						environment.captures :+ [capture]
						environment.capturesByName.Insert(key, capture)
					End If
				Else
					needsParent = True
				End If
			Next
		Next
		If needsParent Then
			If Not ownerMethod.incomingClosureEnvironment Then
				diagnostics :+ ["BMXC1243 nested generic Closure capture has no enclosing specialization environment"]
				Return Null
			End If
			If Not result Then
				result = NewClosureEnvironment(ownerMethod, "")
				ownerMethod.closureEnvironments :+ [result]
			End If
			result.parent = ownerMethod.incomingClosureEnvironment
			result.parentFieldName = "capture_parent_" + TCompilerStableDigest.Sha256(result.parent.abiName)[..12]
		End If
		ownerMethod.closureEnvironment = result
		For Local environment:TCompilerGenericClosureEnvironmentIr = EachIn ownerMethod.closureEnvironments
			If Not environment.activationIdentity.length Then Continue
			Local parentIdentity:String = ParentActivationIdentity(ownerMethod.body, environment.activationIdentity)
			If parentIdentity.length Then environment.parent = TCompilerGenericClosureEnvironmentIr(ownerMethod.activationClosureEnvironments.ValueForKey(parentIdentity))
			If Not environment.parent Then environment.parent = result
			If environment.parent Then environment.parentFieldName = "capture_parent_" + TCompilerStableDigest.Sha256(environment.parent.abiName)[..12]
		Next
		For Local routine:TCompilerGenericMethodIr = EachIn routines
			If Not routine Or Not routine.closureCaptures.length Then Continue
			Local incoming:TCompilerGenericClosureEnvironmentIr = result
			For Local capture:TCompilerGenericClosureCaptureIr = EachIn routine.closureCaptures
				If Not capture.activationIdentity.length Then Continue
				Local candidate:TCompilerGenericClosureEnvironmentIr = TCompilerGenericClosureEnvironmentIr(ownerMethod.activationClosureEnvironments.ValueForKey(capture.activationIdentity))
				If candidate And (Not incoming Or EnvironmentDescendsFrom(candidate, incoming)) Then incoming = candidate
			Next
			routine.incomingClosureEnvironment = incoming
		Next
		Return result
	End Function

	Function NewClosureEnvironment:TCompilerGenericClosureEnvironmentIr(ownerMethod:TCompilerGenericMethodIr, suffix:String)
		Local environment:TCompilerGenericClosureEnvironmentIr = New TCompilerGenericClosureEnvironmentIr
		Local ownerName:String = ownerMethod.localRoutineOwnerAbiName
		If Not ownerName.length Then ownerName = ownerMethod.abiName
		environment.abiName = TCompilerAbiNamer.Sanitize(ownerName + "_closure_environment" + suffix)
		environment.localName = "bmx_closure_environment"
		Return environment
	End Function

	Function ParentActivationIdentity:String(node:TGenericTemplateNode, targetIdentity:String, parentIdentity:String = "")
		If Not node Or node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return ""
		Local activeParent:String = parentIdentity
		If IsClosureActivationNode(node) Then
			Local identity:String = ClosureActivationIdentity(node)
			If identity = targetIdentity Then Return parentIdentity
			activeParent = identity
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			Local found:String = ParentActivationIdentity(child, targetIdentity, activeParent)
			If found.length Then Return found
		Next
		Return ""
	End Function

	Function EnvironmentDescendsFrom:Int(environment:TCompilerGenericClosureEnvironmentIr, ancestor:TCompilerGenericClosureEnvironmentIr)
		While environment
			If environment = ancestor Then Return True
			environment = environment.parent
		Wend
		Return False
	End Function

	Function MethodOwnsClosureCapture:Int(ownerMethod:TCompilerGenericMethodIr, capture:TCompilerGenericClosureCaptureIr)
		If Not ownerMethod Or Not capture Then Return False
		If Not ownerMethod.isClosureInvoke Then Return True
		If capture.isSelf Then Return False
		For Local parameter:TGenericTemplateValueParameter = EachIn ownerMethod.parameters
			If parameter.name.ToLower() = capture.name.ToLower() Then Return True
		Next
		Return BodyDeclaresClosureCapture(ownerMethod.body, capture)
	End Function

	Function BodyDeclaresClosureCapture:Int(node:TGenericTemplateNode, capture:TCompilerGenericClosureCaptureIr)
		If Not node Or Not capture Then Return False
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return False
		If node.kind = TEMPLATE_NODE_DECLARATION And node.valueText.ToLower() = capture.name.ToLower() And SourceContains(node.source, capture.source) Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If BodyDeclaresClosureCapture(child, capture) Then Return True
		Next
		Return False
	End Function

	Function SourceContains:Int(container:TTemplateSourceLocation, value:TTemplateSourceLocation)
		If Not container Or Not value Then Return False
		If container.path.length And value.path.length And container.path.ToLower() <> value.path.ToLower() Then Return False
		Return value.start >= container.start And value.start < container.start + container.length
	End Function

	Function ClosureCaptureForName:TCompilerGenericClosureCaptureIr(ownerMethod:TCompilerGenericMethodIr, name:String)
		If Not ownerMethod Then Return Null
		If ownerMethod.closureEnvironment Then
			Local ownedCapture:TCompilerGenericClosureCaptureIr = TCompilerGenericClosureCaptureIr(ownerMethod.closureEnvironment.capturesByName.ValueForKey(name.ToLower()))
			If ownedCapture Then Return ownedCapture
		End If
		If ownerMethod.isClosureInvoke Then
			Local capturedByRoutine:Int
			For Local routineCapture:TCompilerGenericClosureCaptureIr = EachIn ownerMethod.closureCaptures
				If routineCapture.name.ToLower() = name.ToLower() Then
					capturedByRoutine = True
					Exit
				End If
			Next
			If Not capturedByRoutine Then Return Null
		End If
		Local environment:TCompilerGenericClosureEnvironmentIr = ownerMethod.closureEnvironment
		If ownerMethod.isClosureInvoke Then environment = ownerMethod.incomingClosureEnvironment
		While environment
			Local capture:TCompilerGenericClosureCaptureIr = TCompilerGenericClosureCaptureIr(environment.capturesByName.ValueForKey(name.ToLower()))
			If capture Then Return capture
			environment = environment.parent
		Wend
		Return Null
	End Function

	Function ClosureEnvironmentField:String(environment:TCompilerGenericClosureEnvironmentIr, capture:TCompilerGenericClosureCaptureIr, castEnvironment:Int = False)
		If Not environment Or Not capture Then Return ""
		If castEnvironment Then Return "((struct " + environment.abiName + "_obj *)environment)->" + capture.abiName
		Return environment.localName + "->" + capture.abiName
	End Function

	Function ClosureCaptureExpression:String(ownerMethod:TCompilerGenericMethodIr, capture:TCompilerGenericClosureCaptureIr)
		If Not ownerMethod Or Not capture Then Return ""
		Local root:TCompilerGenericClosureEnvironmentIr = ownerMethod.closureEnvironment
		Local expression:String
		Local captureIsOwned:Int = root And root.capturesByName.ValueForKey(capture.name.ToLower()) = capture
		If ownerMethod.isClosureInvoke And Not captureIsOwned Then
			root = ownerMethod.incomingClosureEnvironment
			If root Then expression = "((struct " + root.abiName + "_obj *)environment)"
		Else If root Then
			expression = root.localName
		End If
		Local environment:TCompilerGenericClosureEnvironmentIr = root
		While environment
			If environment.capturesByName.ValueForKey(capture.name.ToLower()) = capture Then Return expression + "->" + capture.abiName
			If Not environment.parent Then Exit
			expression = "((struct " + environment.parent.abiName + "_obj *)" + expression + "->" + environment.parentFieldName + ")"
			environment = environment.parent
		Wend
		Return ""
	End Function

	Function ClosureSelfExpression:String(ownerMethod:TCompilerGenericMethodIr)
		If ownerMethod And ownerMethod.isIteratorRoutine And ownerMethod.iteratorSelfExpression.length Then Return ownerMethod.iteratorSelfExpression
		Local capture:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(ownerMethod, "Self")
		If capture Then Return ClosureCaptureExpression(ownerMethod, capture)
		Return "self"
	End Function

	Function EmitClosureEnvironmentSupport:String(environment:TCompilerGenericClosureEnvironmentIr, ir:TCompilerGenericSpecializationIr)
		If Not environment Or (Not environment.captures.length And Not environment.parent) Then Return ""
		Local result:String = "struct " + environment.abiName + "_obj {~n    BBObject object;~n"
		If environment.parent Then result :+ "    BBOBJECT " + environment.parentFieldName + ";~n"
		For Local capture:TCompilerGenericClosureCaptureIr = EachIn environment.captures
			result :+ "    " + CValueDeclaration(capture.semanticType, capture.abiName, ir) + ";~n"
		Next
		result :+ "};~n"
		Local firstFieldName:String = environment.parentFieldName
		If Not firstFieldName.length Then firstFieldName = environment.captures[0].abiName
		Local lastFieldName:String = environment.parentFieldName
		If environment.captures.length Then lastFieldName = environment.captures[environment.captures.length - 1].abiName
		Local fieldsOffset:String = "offsetof(struct " + environment.abiName + "_obj, " + firstFieldName + ")"
		Local objectSize:String = "offsetof(struct " + environment.abiName + "_obj, " + lastFieldName + ") - " + fieldsOffset + " + sizeof(((struct " + environment.abiName + "_obj *)0)->" + lastFieldName + ")"
		result :+ "static BBClass " + environment.abiName + "_class = {~n"
		result :+ "    &bbObjectClass, bbObjectFree, 0, sizeof(struct " + environment.abiName + "_obj),~n"
		result :+ "    bbObjectCtor, bbObjectDtor, bbObjectToString, bbObjectCompare, bbObjectSendMessage, bbObjectHashCode, bbObjectEquals,~n"
		result :+ "    0, 0, " + objectSize + ", 0, " + fieldsOffset + "~n};~n"
		result :+ "static struct " + environment.abiName + "_obj *" + environment.abiName + "_new(void) {~n"
		result :+ "    struct " + environment.abiName + "_obj *environment = (struct " + environment.abiName + "_obj *)bbObjectNew(&" + environment.abiName + "_class);~n"
		If environment.parent Then result :+ "    environment->" + environment.parentFieldName + " = (BBOBJECT)&bbNullObject;~n"
		For Local capture:TCompilerGenericClosureCaptureIr = EachIn environment.captures
			result :+ "    environment->" + capture.abiName + " = " + DefaultValue(capture.semanticType, ir) + ";~n"
		Next
		result :+ "    return environment;~n}~n"
		result :+ "static BBClass " + environment.abiName + "_closure_class = {~n"
		result :+ "    &bbObjectClass, bbObjectFree, 0, sizeof(BBClosure),~n"
		result :+ "    bbObjectCtor, bbObjectDtor, bbObjectToString, bbObjectCompare, bbObjectSendMessage, bbObjectHashCode, bbObjectEquals,~n"
		result :+ "    0, 0, sizeof(BBOBJECT), 0, offsetof(BBClosure, environment)~n};~n"
		result :+ "static BBClosure *" + environment.abiName + "_closure_new(BBFuncPtr invoke, BBOBJECT environment) {~n"
		result :+ "    BBClosure *closure = (BBClosure *)bbObjectNew(&" + environment.abiName + "_closure_class);~n"
		result :+ "    closure->invoke = invoke;~n    closure->environment = environment;~n    return closure;~n}~n~n"
		Return result
	End Function

	Function EmitClosureLiteralSupport:String(ownerMethod:TCompilerGenericMethodIr, body:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local literals:TGenericTemplateNode[]
		Local literalParents:TMap = New TMap
		CollectClosureLiteralHierarchy(body, Null, New TMap, literals, literalParents)
		If Not literals.length Then Return ""
		Local routines:TCompilerGenericMethodIr[] = New TCompilerGenericMethodIr[literals.length]
		Local routinesByLiteral:TMap = New TMap
		Local result:String
		For Local index:Int = 0 Until literals.length
			Local lexicalOwner:TCompilerGenericMethodIr = ownerMethod
			Local parentLiteral:TGenericTemplateNode = TGenericTemplateNode(literalParents.ValueForKey(literals[index]))
			If parentLiteral Then lexicalOwner = TCompilerGenericMethodIr(routinesByLiteral.ValueForKey(parentLiteral))
			routines[index] = ClosureLiteralIr(lexicalOwner, literals[index], ir, diagnostics)
			If Not routines[index] Then Continue
			routinesByLiteral.Insert(literals[index], routines[index])
			Local parameters:String
			If routines[index].isClosureInvoke Then parameters = "BBOBJECT environment"
			For Local parameter:TGenericTemplateValueParameter = EachIn routines[index].parameters
				If parameters.length Then parameters :+ ", "
				parameters :+ CValueDeclaration(parameter.semanticType, "", ir, parameter.passingMode)
			Next
			If Not parameters.length Then parameters = "void"
			result :+ CFunctionDeclaration(routines[index].returnType, routines[index].abiName, parameters, ir, "static ") + ";~n"
		Next
		Local environments:TCompilerGenericClosureEnvironmentIr[]
		Local directRoutines:TCompilerGenericMethodIr[]
		For Local index:Int = 0 Until literals.length
			If Not literalParents.Contains(literals[index]) And routines[index] Then directRoutines :+ [routines[index]]
		Next
		BuildClosureEnvironment(ownerMethod, directRoutines, ir, diagnostics)
		For Local environment:TCompilerGenericClosureEnvironmentIr = EachIn ownerMethod.closureEnvironments
			environments :+ [environment]
		Next
		For Local ownerIndex:Int = 0 Until literals.length
			If Not routines[ownerIndex] Then Continue
			directRoutines = New TCompilerGenericMethodIr[0]
			For Local childIndex:Int = 0 Until literals.length
				If literalParents.ValueForKey(literals[childIndex]) = literals[ownerIndex] And routines[childIndex] Then directRoutines :+ [routines[childIndex]]
			Next
			If directRoutines.length Then
				BuildClosureEnvironment(routines[ownerIndex], directRoutines, ir, diagnostics)
				For Local nestedEnvironment:TCompilerGenericClosureEnvironmentIr = EachIn routines[ownerIndex].closureEnvironments
					environments :+ [nestedEnvironment]
				Next
			End If
		Next
		For Local environment:TCompilerGenericClosureEnvironmentIr = EachIn environments
			result = EmitClosureEnvironmentSupport(environment, ir) + result
		Next
		For Local index:Int = 0 Until literals.length
			If Not routines[index] Then Continue
			If routines[index].isClosureInvoke And Not routines[index].closureCaptures.length Then result :+ "static BBClosure " + routines[index].abiName + "_value = { { &bbObjectClass }, (BBFuncPtr)&" + routines[index].abiName + ", (BBOBJECT)&bbNullObject };~n"
		Next
		result :+ "~n"
		For Local routine:TCompilerGenericMethodIr = EachIn routines
			If Not routine Then Continue
			Local parameters:String
			If routine.isClosureInvoke Then parameters = "BBOBJECT environment"
			For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
				If parameters.length Then parameters :+ ", "
				parameters :+ CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
			If Not parameters.length Then parameters = "void"
			If GenericNodeContainsYield(routine.body) Then
				result :+ EmitGenericIteratorRoutineImplementation(ir, routine, parameters, diagnostics, "static ") + "~n"
				Continue
			End If
			result :+ EmitGenericGdbLineDirective(routine.source, ir, "") + CFunctionDeclaration(routine.returnType, routine.abiName, parameters, ir, "static ") + " {~n"
			If routine.isClosureInvoke And Not routine.closureCaptures.length Then result :+ "    (void)environment;~n"
			For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
				result :+ "    (void)" + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n"
			Next
			result :+ EmitBody(routine.body, ir, routine, diagnostics) + "}~n~n"
		Next
		Return result
	End Function

	Function CollectLocalRoutineCaptureNodes(node:TGenericTemplateNode, localNames:TMap, captures:TGenericTemplateNode[] Var, seen:TMap)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_NAME And Not node.identity.length And Not localNames.Contains(node.valueText.ToLower()) And Not seen.Contains(node.valueText.ToLower()) Then
			seen.Insert(node.valueText.ToLower(), node)
			Local capture:TGenericTemplateNode = New TGenericTemplateNode
			capture.kind = TEMPLATE_NODE_DECLARATION
			capture.identity = PARAMETER_PASS_VAR
			capture.valueText = "capture:outer:" + node.valueText
			capture.semanticType = node.semanticType
			capture.source = node.source
			captures :+ [capture]
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectLocalRoutineCaptureNodes(child, localNames, captures, seen)
		Next
	End Function

	Function AppendLocalRoutineCaptureArguments(node:TGenericTemplateNode, routineIdentity:String, captures:TGenericTemplateNode[])
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_CALL And node.children.length And node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].identity = routineIdentity Then
			Local reference:TGenericTemplateNode = node.children[0]
			For Local capture:TGenericTemplateNode = EachIn captures
				reference.children :+ [capture]
				Local argument:TGenericTemplateNode = New TGenericTemplateNode
				argument.semanticType = capture.semanticType
				argument.source = node.source
				If capture.valueText = "capture:self" Then
					argument.kind = TEMPLATE_NODE_SELF
					argument.valueText = "self"
				Else
					argument.kind = TEMPLATE_NODE_NAME
					argument.valueText = capture.valueText[14..]
				End If
				node.children :+ [argument]
			Next
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			AppendLocalRoutineCaptureArguments(child, routineIdentity, captures)
		Next
	End Function

	Function EmitLocalRoutineSupport:String(ownerMethod:TCompilerGenericMethodIr, body:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local signatures:TGenericTemplateNode[]
		CollectLocalRoutineSignatures(body, New TMap, signatures)
		Local routines:TCompilerGenericMethodIr[] = New TCompilerGenericMethodIr[signatures.length]
		Local result:String
		For Local index:Int = 0 Until signatures.length
			routines[index] = LocalRoutineIr(ownerMethod, signatures[index], ir, diagnostics)
			If Not routines[index] Then Continue
			Local parameters:String
			If routines[index].receiverType Then
				parameters :+ RoutineReceiverCType(routines[index], ir)
			Else If Not routines[index].parameters.length Then
				parameters :+ "void"
			End If
			If routines[index].parameters.length Then
				For Local parameterIndex:Int = 0 Until routines[index].parameters.length
					If parameterIndex Or routines[index].receiverType Then parameters :+ ", "
					parameters :+ CValueDeclaration(routines[index].parameters[parameterIndex].semanticType, "", ir, routines[index].parameters[parameterIndex].passingMode)
				Next
			End If
			result :+ CFunctionDeclaration(routines[index].returnType, routines[index].abiName, parameters, ir, "static ") + ";~n"
		Next
		result :+ "~n"
		For Local routine:TCompilerGenericMethodIr = EachIn routines
			If Not routine Then Continue
			Local parameters:String
			If routine.receiverType Then
				parameters :+ RoutineReceiverCType(routine, ir) + " self"
			Else If Not routine.parameters.length Then
				parameters :+ "void"
			End If
			If routine.parameters.length Then
				For Local index:Int = 0 Until routine.parameters.length
					If index Or routine.receiverType Then parameters :+ ", "
					parameters :+ CValueDeclaration(routine.parameters[index].semanticType, TCompilerAbiNamer.Sanitize(routine.parameters[index].name), ir, routine.parameters[index].passingMode)
				Next
			End If
			result :+ EmitGenericGdbLineDirective(routine.source, ir, "") + CFunctionDeclaration(routine.returnType, routine.abiName, parameters, ir, "static ") + " {~n"
			If routine.receiverType Then result :+ "    (void)self;~n"
			For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
				result :+ "    (void)" + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n"
			Next
			result :+ EmitBody(routine.body, ir, routine, diagnostics)
			result :+ "}~n~n"
		Next
		Return result + EmitClosureLiteralSupport(ownerMethod, body, ir, diagnostics)
	End Function

	Function MethodPointerDeclaration:String(irMethod:TCompilerGenericMethodIr, ownerName:String, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local cReturnType:String = CType(irMethod.returnType, ir)
		If Not cReturnType.length Then
			diagnostics :+ ["BMXC3021 method '" + irMethod.name + "' has no C ABI type"]
			cReturnType = "void"
		End If
		Local parameters:String
		If Not irMethod.isTypeFunction Then parameters = "struct " + ownerName + "_obj *"
		For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
			If parameters.length Then parameters :+ ", "
			parameters :+ CValueDeclaration(parameter.semanticType, "", ir, parameter.passingMode)
		Next
		If Not parameters.length Then parameters = "void"
		Return CFunctionPointerDeclaration(irMethod.returnType, irMethod.slotName, parameters, ir)
	End Function

	Function EmitImplementationUnit:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, declarationText:String = "")
		If Not ir Or Not ir.specialization Then
			diagnostics :+ ["BMXC3020 typed generic specialization IR is required for implementation emission"]
			Return ""
		End If
		ResetGenericCoverage(ir)
		If ir.isRoutine Then Return EmitRoutineImplementationUnit(ir, diagnostics, declarationText)
		If ir.isInterface Then Return EmitInterfaceImplementationUnit(ir, diagnostics, declarationText)
		If ir.isStruct Then Return EmitStructImplementationUnit(ir, diagnostics, declarationText)
		Local abiName:String = ir.specialization.readableAbiName
		Local result:TStringBuilder = New TStringBuilder(8192)
		result.Append("#include <stddef.h>~n#include <brl.mod/blitz.mod/blitz.h>~n" + DefiningModuleHeaderInclude(ir) + RuntimeArgumentHeaderIncludes(ir) + "~n" + ClosureRuntimeDeclaration())
		Local runtimeDeclarationText:String = EmitOrdinaryRuntimeTypeDeclarationsForMembers(ir, diagnostics)
		If runtimeDeclarationText.length Then result.Append(runtimeDeclarationText + "~n")
		If Not declarationText.length Then declarationText = EmitDeclarations(ir, diagnostics)
		result.Append(declarationText + "~n")
		result.Append(EmitStaticFieldDefinitions(ir, diagnostics))
		result.Append(EmitGenericDataSupport(ir, diagnostics))
		result.Append("static void " + abiName + "_ctor(struct " + abiName + "_obj *self) {~n")
		If HasThreadedStaticFields(ir) Then result.Append("    " + ThreadInitializationName(ir) + "();~n")
		result.Append("    self->clas = &" + abiName + ";~n")
		For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
			If irField.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
				Local fieldIndex:String = "bmx_" + TCompilerAbiNamer.Sanitize(irField.abiName) + "_index"
				Local elementDefault:String = DefaultValue(irField.semanticType.elementType, ir)
				Local fieldStruct:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(irField.semanticType.elementType, ir)
				If fieldStruct And fieldStruct.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then elementDefault = fieldStruct.readableAbiName + "_New_ObjectNew()"
				result.Append("    for (BBUINT " + fieldIndex + " = 0; " + fieldIndex + " < (BBUINT)" + irField.semanticType.staticArrayLength + "; ++" + fieldIndex + ") self->" + irField.abiName + "[" + fieldIndex + "] = " + elementDefault + ";~n")
			Else
				result.Append("    self->" + irField.abiName + " = " + FieldInitializerValue(irField, ir, diagnostics) + ";~n")
			End If
		Next
		result.Append("}~n~n")
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If irMethod.declaringSpecialization And irMethod.declaringSpecialization <> ir.specialization Then Continue
			result.Append(EmitLocalRoutineSupport(irMethod, irMethod.body, ir, diagnostics))
			Local parameters:String
			If Not irMethod.isTypeFunction Then parameters = "struct " + abiName + "_obj *self"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				If parameters.length Then parameters :+ ", "
				parameters :+ CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
			If Not parameters.length Then parameters = "void"
			If GenericNodeContainsYield(irMethod.body) Then
				result.Append(EmitGenericIteratorRoutineImplementation(ir, irMethod, parameters, diagnostics))
				Continue
			End If
			Local implementationName:String = irMethod.abiName
			If irMethod.isDestructor Then implementationName :+ "_body"
			result.Append(EmitGenericGdbLineDirective(irMethod.source, ir, "") + CFunctionDeclaration(irMethod.returnType, implementationName, parameters, ir) + " {~n")
			If HasThreadedStaticFields(ir) Then result.Append("    " + ThreadInitializationName(ir) + "();~n")
			If Not irMethod.isTypeFunction Then result.Append("    (void)self;~n")
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				result.Append("    (void)" + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n")
			Next
			If irMethod.isDeferredStub Then
				result.Append("    brl_blitz_RuntimeError(bbStringFromCString(" + CQuoted("Compiler reached an unplanned polymorphic-recursive generic method body: " + SpecializationDisplayName(ir.specialization) + "." + irMethod.name) + "));~n")
				If VoidType(irMethod.returnType) Then result.Append("    return;~n") Else result.Append("    return " + DefaultValue(irMethod.returnType, ir) + ";~n")
			Else
				result.Append(EmitBody(irMethod.body, ir, irMethod, diagnostics))
			End If
			result.Append("}~n~n")
			If irMethod.isDestructor Then
				result.Append(CFunctionDeclaration(irMethod.returnType, irMethod.abiName, parameters, ir) + " {~n")
				result.Append("    " + implementationName + "(self);~n")
				If ir.baseSpecialization Then
					result.Append("    ((BBClass *)&" + ir.baseSpecialization.readableAbiName + ")->dtor((BBOBJECT)self);~n")
				Else
					result.Append("    bbObjectDtor((BBOBJECT)self);~n")
				End If
				result.Append("}~n~n")
			End If
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			result.Append(EmitLocalRoutineSupport(constructor, constructor.body, ir, diagnostics))
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			result.Append("void " + constructor.abiName + "_init(struct " + abiName + "_obj *self" + TypeConstructorParameters(constructor, ir, True) + ");~n")
		Next
		If ir.constructors.length Then result.Append("~n")
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			result.Append(EmitTypeConstructorInitializer(ir, constructor, diagnostics))
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			result.Append(EmitTypeConstructorHelper(ir, constructor, diagnostics))
		Next
		Local interfaceTableName:String = "0"
		If ir.implementedInterfaces.length Or ir.implementedRuntimeInterfaces.length Then
			result.Append(EmitOwnedInterfaceTable(ir, diagnostics))
			interfaceTableName = "&" + abiName + "_itable"
		End If
		result.Append(EmitGenericCoverageCatalog(ir))
		result.Append(EmitGenericCoverageRegistration(ir))
		Local debugScopeName:String = abiName + "_debug_scope"
		result.Append(EmitTypeReflectionSupport(ir, diagnostics))
		result.Append(EmitThreadedStaticInitialization(ir, diagnostics, debugScopeName))
		Local objectSize:String = "0"
		Local fieldsOffset:String = "sizeof(void *)"
		If ir.fields.length Then
			Local firstField:TCompilerGenericFieldIr = ir.fields[0]
			Local lastField:TCompilerGenericFieldIr = ir.fields[ir.fields.length - 1]
			fieldsOffset = "offsetof(struct " + abiName + "_obj, " + firstField.abiName + ")"
			objectSize = "offsetof(struct " + abiName + "_obj, " + lastField.abiName + ") - " + fieldsOffset + " + sizeof(((struct " + abiName + "_obj *)0)->" + lastField.abiName + ")"
		End If
		result.Append("struct " + abiName + "_class " + abiName + " = {~n")
		Local superDescriptor:String = "&bbObjectClass"
		If ir.baseSpecialization Then superDescriptor = "(BBClass *)&" + ir.baseSpecialization.readableAbiName
		result.Append("    " + superDescriptor + ", bbObjectFree, (BBDebugScope *)&" + debugScopeName + ", sizeof(struct " + abiName + "_obj),~n")
		Local destructorName:String = "bbObjectDtor"
		For Local lifecycleMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If lifecycleMethod.isDestructor Then destructorName = lifecycleMethod.abiName; Exit
		Next
		result.Append("    (void (*)(BBOBJECT))" + abiName + "_ctor, (void (*)(BBOBJECT))" + destructorName + ",~n")
		result.Append("    bbObjectToString, bbObjectCompare, bbObjectSendMessage, bbObjectHashCode, bbObjectEquals,~n")
		result.Append("    " + interfaceTableName + ", 0, " + objectSize + ", 0, " + fieldsOffset)
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If irMethod.isDestructor Then Continue
			result.Append(",~n    " + irMethod.abiName)
		Next
		result.Append("~n};~n~n")
		Local allocator:String = "bbObjectAtomicNew"
		If HasManagedFields(ir) Then allocator = "bbObjectNew"
		result.Append("struct " + abiName + "_obj *" + abiName + "_New(BBClass *clas) {~n")
		result.Append("    return (struct " + abiName + "_obj *)" + allocator + "(clas);~n")
		result.Append("}~n~n")
		result.Append("void " + abiName + "_register(void) {~n")
		result.Append("    static int registered = 0;~n")
		result.Append("    if (!registered) {~n")
		result.Append("        registered = 1;~n")
		Local registrationIndent:String = "        "
		If HasThreadedStaticFields(ir) Then
			result.Append("        BBOBJECT bmx_initialization_exception = (BBOBJECT)&bbNullObject;~n")
			result.Append("        bbExTry {~n")
			result.Append("        case 0: {~n")
			If ir.specialization.debugInstrumentation Then result.Append("            bbOnDebugPushExState();~n")
			result.Append("            " + ThreadInitializationFlagName(ir) + " = 1;~n")
			registrationIndent = "            "
		End If
		If ir.baseSpecialization Then result.Append(registrationIndent + ir.baseSpecialization.readableAbiName + "_register();~n")
		For Local interfaceNode:TGenericSpecializationNode = EachIn ir.implementedInterfaces
			result.Append(registrationIndent + interfaceNode.readableAbiName + "_register();~n")
		Next
		result.Append(EmitReferencedTypeRegistrations(ir, registrationIndent))
		result.Append(EmitStaticFieldInitializers(ir, diagnostics, registrationIndent))
		If HasThreadedStaticFields(ir) Then result.Append(registrationIndent + ThreadInitializationFlagName(ir) + " = 2;~n")
		Local reflectionDeclarationIndex:Int
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.declaringSpecialization <> ir.specialization Or Not TemplateDebugTypeTag(staticField.semanticType, ir).length Then Continue
			If staticField.isThreadedGlobal Then result.Append(registrationIndent + debugScopeName + ".decls[" + reflectionDeclarationIndex + "].var_address = (void *)&" + staticField.abiName + ";~n")
			reflectionDeclarationIndex :+ 1
		Next
		result.Append(registrationIndent + "bbObjectRegisterType((BBClass *)&" + abiName + ");~n")
		If HasThreadedStaticFields(ir) Then
			result.Append("            bbExLeave();~n")
			If ir.specialization.debugInstrumentation Then result.Append("            bbOnDebugPopExState();~n")
			result.Append("        } break;~n")
			result.Append("        case 1: {~n")
			If ir.specialization.debugInstrumentation Then result.Append("            bbOnDebugPopExState();~n")
			result.Append("            bmx_initialization_exception = bbExCatch();~n")
			result.Append("            registered = 0;~n")
			result.Append("            " + ThreadInitializationFlagName(ir) + " = 0;~n")
			result.Append("            bbExThrow((BBObject *)bmx_initialization_exception);~n")
			result.Append("        } break;~n")
			result.Append("        }~n")
		End If
		result.Append("    }~n")
		If HasThreadedStaticFields(ir) Then result.Append("    " + ThreadInitializationName(ir) + "();~n")
		result.Append("}~n")
		Return result.ToString()
	End Function

	Function SpecializationDisplayName:String(node:TGenericSpecializationNode)
		If Not node Or Not node.artifact Or Not node.artifact.identity Then Return ""
		Local result:String = node.artifact.identity.qualifiedName + "<"
		For Local index:Int = 0 Until node.key.typeArguments.length
			If index Then result :+ ","
			result :+ node.key.typeArguments[index].CanonicalName()
		Next
		Return result + ">"
	End Function

	Function TypeConstructorParameters:String(constructor:TCompilerGenericMethodIr, ir:TCompilerGenericSpecializationIr, includeNames:Int)
		Local result:String
		For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
			Local parameterName:String
			If includeNames Then parameterName = TCompilerAbiNamer.Sanitize(parameter.name)
			result :+ ", " + CValueDeclaration(parameter.semanticType, parameterName, ir, parameter.passingMode)
		Next
		Return result
	End Function

	Function EmitTypeConstructorHelper:String(ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr, diagnostics:String[] Var)
		Local abiName:String = ir.specialization.readableAbiName
		Local allocator:String = "bbObjectAtomicNew"
		If HasManagedFields(ir) Then allocator = "bbObjectNew"
		Local result:String = "struct " + abiName + "_obj *" + constructor.abiName + "(BBClass *clas" + TypeConstructorParameters(constructor, ir, True) + ") {~n"
		result :+ "    struct " + abiName + "_obj *self = (struct " + abiName + "_obj *)" + allocator + "(clas);~n"
		result :+ "    " + constructor.abiName + "_init(self"
		For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
			result :+ ", " + TCompilerAbiNamer.Sanitize(parameter.name)
		Next
		result :+ ");~n"
		result :+ "    return self;~n}~n~n"
		Return result
	End Function

	Function EmitTypeConstructorInitializer:String(ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr, diagnostics:String[] Var)
		Local abiName:String = ir.specialization.readableAbiName
		Local result:String = EmitGenericGdbLineDirective(constructor.source, ir, "") + "void " + constructor.abiName + "_init(struct " + abiName + "_obj *self" + TypeConstructorParameters(constructor, ir, True) + ") {~n"
		For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
			result :+ "    (void)" + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n"
		Next
		If constructor.delegatedConstructor Then
			Local delegatedOwner:TGenericSpecializationNode = constructor.delegatedConstructorSpecialization
			If Not delegatedOwner Then delegatedOwner = ir.specialization
			result :+ "    " + constructor.delegatedConstructor.abiName + "_init((struct " + delegatedOwner.readableAbiName + "_obj *)self"
			If constructor.isInheritedConstructorForwarder Then
				For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
					result :+ ", " + TCompilerAbiNamer.Sanitize(parameter.name)
				Next
			Else
				For Local index:Int = 0 Until constructor.delegationArguments.length
					result :+ ", " + EmitCallArgument(constructor.delegationArguments[index], constructor.delegatedConstructor.parameters[index], ir, constructor, diagnostics, New TMap)
				Next
			End If
			result :+ ");~n"
		End If
		result :+ EmitTypeConstructorBody(constructor.body, ir, constructor, diagnostics)
		result :+ "}~n~n"
		Return result
	End Function

	Function EmitTypeConstructorBody:String(body:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr, diagnostics:String[] Var)
		If Not body Or body.kind <> TEMPLATE_NODE_BLOCK Then
			diagnostics :+ ["BMXC3023 generic Type constructor body is not a bound template block"]
			Return ""
		End If
		Local filtered:TGenericTemplateNode = New TGenericTemplateNode
		filtered.kind = TEMPLATE_NODE_BLOCK
		For Local child:TGenericTemplateNode = EachIn body.children
			If child.kind <> TEMPLATE_NODE_CONSTRUCTOR_DELEGATION Then filtered.children :+ [child]
		Next
		' Constructor initializers use the same debug-local ownership as ordinary
		' methods. In debug mode loop declarations are hoisted into the function
		' scope so their debugger records have stable addresses; bypassing
		' EmitBody left those names assigned but undeclared.
		Return EmitBody(filtered, ir, constructor, diagnostics)
	End Function

	Function EmitRoutineImplementationUnit:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, declarationText:String = "")
		Local result:TStringBuilder = New TStringBuilder(4096)
		result.Append("#include <brl.mod/blitz.mod/blitz.h>~n" + DefiningModuleHeaderInclude(ir) + RuntimeArgumentHeaderIncludes(ir) + "~n" + ClosureRuntimeDeclaration())
		Local emittedRuntimeTypes:TMap = New TMap
		Local runtimeDeclarationText:String = EmitOrdinaryRuntimeTypeDeclarations(ir.routine.body, emittedRuntimeTypes, diagnostics)
		' Direct generic method calls can target a method declared by an
		' ordinary base Type even when the body receiver is the derived Type.
		' Forward-declare every referenced routine receiver before any
		' prototypes so repeated C declarations share one tag identity.
		For Local referencedRoutine:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If Not referencedRoutine.artifact.identity Or referencedRoutine.artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Continue
			Local referencedRoutineIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referencedRoutine, diagnostics)
			If referencedRoutineIr And referencedRoutineIr.routine Then
				Local referencedOwner:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(referencedRoutineIr.routine.receiverType, referencedRoutineIr)
				If referencedOwner Then runtimeDeclarationText :+ "struct " + referencedOwner.readableAbiName + "_obj;~n"
				runtimeDeclarationText :+ EmitOrdinaryRuntimeTypeDeclaration(referencedRoutineIr.routine.receiverType, emittedRuntimeTypes, diagnostics)
			End If
		Next
		If runtimeDeclarationText.length Then result.Append(runtimeDeclarationText + "~n")
		Local ownerDeclarationText:String = EmitRoutineOwnerDeclaration(ir, diagnostics)
		If ownerDeclarationText.length Then result.Append(ownerDeclarationText + "~n")
		Local emittedTypes:TMap = New TMap
		Local emittedClassLayouts:TMap = New TMap
		' A referenced Struct used by value in a routine local, StaticArray, or
		' expression must be complete in this translation unit. Its separately
		' owned implementation unit remains the sole owner of constructor bodies.
		Local emittedStructs:TMap = New TMap
		Local visitingStructs:TMap = New TMap
		For Local referencedStruct:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If referencedStruct.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Continue
			Local referencedStructIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referencedStruct, diagnostics)
			If referencedStructIr Then result.Append(EmitStructDeclarationTree(referencedStructIr, emittedStructs, visitingStructs, diagnostics) + "~n")
		Next
		For Local referencedType:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If IsRoutineSpecialization(referencedType) Then Continue
			If referencedType.IsAbiReferenceOnly() Then Continue
			If referencedType.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_CLASS Or emittedTypes.Contains(referencedType.key.CanonicalName()) Then Continue
			Local referencedTypeIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referencedType, diagnostics)
			If referencedTypeIr Then result.Append(EmitDeclarations(referencedTypeIr, diagnostics, False, False, emittedClassLayouts) + "~n")
			emittedTypes.Insert(referencedType.key.CanonicalName(), referencedType)
		Next
		Local emittedInterfaces:TMap = New TMap
		Local emittedAnyInterface:Int
		For Local referencedInterface:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If referencedInterface.IsAbiReferenceOnly() Then Continue
			If referencedInterface.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_INTERFACE Or emittedInterfaces.Contains(referencedInterface.key.CanonicalName()) Then Continue
			result.Append(EmitReferencedInterfaceDeclarations(referencedInterface, ir, diagnostics))
			emittedInterfaces.Insert(referencedInterface.key.CanonicalName(), referencedInterface)
			emittedAnyInterface = True
		Next
		If emittedAnyInterface Then result.Append("~n")
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If Not referenced.artifact.identity Or referenced.artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Continue
			Local referencedIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
			If referencedIr Then result.Append(EmitRoutineDeclarations(referencedIr, diagnostics))
		Next
		If ir.referencedSpecializations.length Then result.Append("~n")
		Local ordinaryDeclarations:TMap = New TMap
		Local ordinaryDeclarationText:String = EmitReferencedCallDeclarations(ir.routine.body, ir, ordinaryDeclarations, diagnostics)
		If ordinaryDeclarationText.length Then result.Append(ordinaryDeclarationText + "~n")
		If Not declarationText.length Then declarationText = EmitRoutineDeclarations(ir, diagnostics)
		result.Append(declarationText + "~n")
		result.Append(EmitGenericDataSupport(ir, diagnostics))
		Local routine:TCompilerGenericMethodIr = ir.routine
		If ir.specialization.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Or Not routine.body Then
			result.Append(EmitLocalRoutineSupport(routine, routine.body, ir, diagnostics))
			result.Append(EmitMethodDispatcher(ir, diagnostics))
			result.Append(EmitGenericCoverageCatalog(ir))
			result.Append(EmitGenericCoverageRegistration(ir))
			Return result.ToString()
		End If
		result.Append(EmitLocalRoutineSupport(routine, routine.body, ir, diagnostics))
		Local routineParameters:String
		If routine.receiverType Then
			routineParameters :+ RoutineReceiverCType(routine, ir) + " self"
			If routine.parameters.length Then routineParameters :+ ", "
		Else If Not routine.parameters.length Then
			routineParameters :+ "void"
		End If
		If routine.parameters.length Then
			For Local index:Int = 0 Until routine.parameters.length
				If index Then routineParameters :+ ", "
				Local parameter:TGenericTemplateValueParameter = routine.parameters[index]
				routineParameters :+ CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
		End If
		If GenericNodeContainsYield(routine.body) Then
			result.Append(EmitGenericIteratorRoutineImplementation(ir, routine, routineParameters, diagnostics))
			result.Append(EmitGenericCoverageCatalog(ir))
			result.Append(EmitGenericCoverageRegistration(ir))
			result.Append(EmitDynamicImplementationRegistrations(ir, diagnostics))
			Return result.ToString()
		End If
		result.Append(EmitGenericGdbLineDirective(routine.source, ir, "") + CFunctionDeclaration(routine.returnType, routine.abiName, routineParameters, ir) + " {~n")
		If routine.receiverType Then result.Append("    (void)self;~n")
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			result.Append("    (void)" + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n")
		Next
		result.Append(EmitBody(routine.body, ir, routine, diagnostics))
		result.Append("}~n")
		result.Append(EmitGenericCoverageCatalog(ir))
		result.Append(EmitGenericCoverageRegistration(ir))
		result.Append(EmitDynamicImplementationRegistrations(ir, diagnostics))
		Return result.ToString()
	End Function

	Function GenericNodeContainsYield:Int(node:TGenericTemplateNode)
		If Not node Then Return False
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return False
		If node.kind = TEMPLATE_NODE_YIELD Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If GenericNodeContainsYield(child) Then Return True
		Next
		Return False
	End Function

	Function AssignGenericIteratorResumeStates(node:TGenericTemplateNode, nextState:Int Var, states:Int[] Var)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		If node.kind = TEMPLATE_NODE_YIELD Then
			node.valueText = String(nextState)
			states :+ [nextState]
			nextState :+ 1
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			AssignGenericIteratorResumeStates(child, nextState, states)
		Next
	End Function

	Function GenericNodeHasResumeState:Int(node:TGenericTemplateNode, resumeState:Int)
		If Not node Then Return False
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return False
		If node.kind = TEMPLATE_NODE_YIELD And Int(node.valueText) = resumeState Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If GenericNodeHasResumeState(child, resumeState) Then Return True
		Next
		Return False
	End Function

	Function GenericIteratorTryEntryLabel:String(node:TGenericTemplateNode)
		Return "bmx_iterator_" + GenericIteratorTryPrefix(node) + "_entry"
	End Function

	Function GenericIteratorTryCatchEntryLabel:String(node:TGenericTemplateNode)
		Return "bmx_iterator_" + GenericIteratorTryPrefix(node) + "_catch_entry"
	End Function

	Function GenericIteratorResumeTarget:String(node:TGenericTemplateNode, resumeState:Int)
		If Not node Then Return "bmx_iterator_resume_" + resumeState
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return "bmx_iterator_resume_" + resumeState
		If node.kind = TEMPLATE_NODE_YIELD And Int(node.valueText) = resumeState Then Return "bmx_iterator_resume_" + resumeState
		If node.kind = TEMPLATE_NODE_TRY Then
			Local body:TGenericTemplateNode = GenericTryProtectedBody(node)
			If GenericNodeHasResumeState(body, resumeState) Then
				If GenericTryRetained(node) Then
					If GenericTryFinallyBody(node) Then Return GenericIteratorTryEntryLabel(node)
					Return GenericIteratorTryCatchEntryLabel(node)
				End If
				Return GenericIteratorResumeTarget(body, resumeState)
			End If
			For Local child:TGenericTemplateNode = EachIn node.children
				If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "catch-clause" And child.children.length = 2 And GenericNodeHasResumeState(child.children[1], resumeState) Then
					If GenericTryRetained(node) And GenericTryFinallyBody(node) Then Return GenericIteratorTryEntryLabel(node)
					Return GenericIteratorResumeTarget(child.children[1], resumeState)
				End If
			Next
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			If GenericNodeHasResumeState(child, resumeState) Then Return GenericIteratorResumeTarget(child, resumeState)
		Next
		Return "bmx_iterator_resume_" + resumeState
	End Function

	Function EmitGenericIteratorResumeDispatch:String(node:TGenericTemplateNode, stateExpression:String, indent:String, forcedTarget:String = "")
		Local states:Int[]
		AssignGenericIteratorResumeStatesCopy(node, states)
		If Not states.length Then Return ""
		Local result:String = indent + "switch (" + stateExpression + ") {~n"
		For Local resumeState:Int = EachIn states
			Local target:String = forcedTarget
			If Not target.length Then target = GenericIteratorResumeTarget(node, resumeState)
			result :+ indent + "    case " + resumeState + ": "
			If target = "bmx_iterator_resume_" + resumeState Then result :+ stateExpression + " = -1; "
			result :+ "goto " + target + ";~n"
		Next
		Return result + indent + "    default: break;~n" + indent + "}~n"
	End Function

	Function AssignGenericIteratorResumeStatesCopy(node:TGenericTemplateNode, states:Int[] Var)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		If node.kind = TEMPLATE_NODE_YIELD Then states :+ [Int(node.valueText)]
		For Local child:TGenericTemplateNode = EachIn node.children
			AssignGenericIteratorResumeStatesCopy(child, states)
		Next
	End Function

	Function CollectGenericIteratorYields(node:TGenericTemplateNode, yields:TGenericTemplateNode[] Var)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		If node.kind = TEMPLATE_NODE_YIELD Then yields :+ [node]
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectGenericIteratorYields(child, yields)
		Next
	End Function

	Function CollectGenericIteratorLocals(node:TGenericTemplateNode, declarations:TGenericTemplateNode[] Var, seen:TMap)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		If node.kind = TEMPLATE_NODE_DECLARATION Then
			Local key:String = GenericIteratorLocalFieldName(node)
			If Not seen.Contains(key) Then
				seen.Insert(key, node)
				declarations :+ [node]
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectGenericIteratorLocals(child, declarations, seen)
		Next
	End Function

	Function CollectGenericIteratorLoops(node:TGenericTemplateNode, loops:TGenericTemplateNode[] Var, seen:TMap)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		If node.kind = TEMPLATE_NODE_LOOP And GenericNodeContainsYield(node) Then
			If node.valueText = "eachin-array" Or node.valueText = "eachin-string" Or node.valueText = "eachin-static-array" Or node.valueText = "eachin-iterable" Or node.valueText = "eachin-iterator" Or node.valueText = "eachin-object-enumerator" Then
				Local key:String = node.identity
				If Not key.length Then key = SourceIdentity(node)
				If Not seen.Contains(key) Then
					seen.Insert(key, node)
					loops :+ [node]
				End If
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectGenericIteratorLoops(child, loops, seen)
		Next
	End Function

	Function CollectGenericIteratorOwnedCleanups(node:TGenericTemplateNode, cleanups:TGenericTemplateNode[] Var, seen:TMap)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		Local retained:Int
		If node.kind = TEMPLATE_NODE_LOOP And GenericNodeContainsYield(node) Then
			retained = node.valueText = "eachin-iterable" Or node.valueText = "eachin-iterator" Or node.valueText = "eachin-object-enumerator"
		Else If node.kind = TEMPLATE_NODE_USING And node.children.length Then
			retained = GenericNodeContainsYield(node.children[node.children.length - 1])
		End If
		If retained Then
			Local key:String = node.kind + ":" + node.identity
			If Not seen.Contains(key) Then
				seen.Insert(key, node)
				cleanups :+ [node]
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectGenericIteratorOwnedCleanups(child, cleanups, seen)
		Next
	End Function

	Function GenericTryProtectedBody:TGenericTemplateNode(node:TGenericTemplateNode)
		If node And node.kind = TEMPLATE_NODE_TRY And node.children.length Then Return node.children[0]
		Return Null
	End Function

	Function GenericTryFinallyBody:TGenericTemplateNode(node:TGenericTemplateNode)
		If Not node Or node.kind <> TEMPLATE_NODE_TRY Then Return Null
		For Local child:TGenericTemplateNode = EachIn node.children
			If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "finally-body" And child.children.length = 1 Then Return child.children[0]
		Next
		Return Null
	End Function

	Function GenericTryRetained:Int(node:TGenericTemplateNode)
		If Not node Or node.kind <> TEMPLATE_NODE_TRY Then Return False
		If GenericNodeContainsYield(GenericTryProtectedBody(node)) Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "catch-clause" And child.children.length = 2 And GenericNodeContainsYield(child.children[1]) Then Return True
		Next
		Return False
	End Function

	Function CollectGenericIteratorRetainedTries(node:TGenericTemplateNode, tries:TGenericTemplateNode[] Var, seen:TMap)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		If node.kind = TEMPLATE_NODE_TRY And GenericTryRetained(node) Then
			Local key:String = node.identity
			If Not key.length Then key = SourceIdentity(node)
			If Not seen.Contains(key) Then
				seen.Insert(key, node)
				tries :+ [node]
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectGenericIteratorRetainedTries(child, tries, seen)
		Next
	End Function

	Function GenericIteratorTryPrefix:String(node:TGenericTemplateNode)
		Local identity:String = node.identity
		If Not identity.length Then identity = SourceIdentity(node)
		Return "try_" + TCompilerAbiNamer.Sanitize(identity)
	End Function

	Function GenericIteratorLoopFieldPrefix:String(node:TGenericTemplateNode)
		Local identity:String = node.identity
		If Not identity.length Then identity = SourceIdentity(node)
		Return "loop_" + TCompilerAbiNamer.Sanitize(identity)
	End Function

	Function CollectGenericIteratorInterfaces(node:TGenericSpecializationNode, ownerIr:TCompilerGenericSpecializationIr, interfaces:TGenericSpecializationNode[] Var, seen:TMap, hasClose:Int Var, diagnostics:String[] Var)
		If Not node Or seen.Contains(node.key.CanonicalName()) Then Return
		Local interfaceIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(node, diagnostics)
		If Not interfaceIr Or Not interfaceIr.isInterface Then Return
		For Local parent:TGenericSpecializationNode = EachIn interfaceIr.inheritedInterfaces
			CollectGenericIteratorInterfaces(parent, ownerIr, interfaces, seen, hasClose, diagnostics)
		Next
		For Local runtimeInterface:TTemplateTypeReference = EachIn interfaceIr.inheritedRuntimeInterfaces
			If runtimeInterface.runtimeAbiName.ToLower() = "brl_blitz_icloseable" Then hasClose = True
		Next
		seen.Insert(node.key.CanonicalName(), node)
		interfaces :+ [node]
	End Function

	Function EmitGenericIteratorRoutineImplementation:String(ir:TCompilerGenericSpecializationIr, routine:TCompilerGenericMethodIr, routineParameters:String, diagnostics:String[] Var, factoryPrefix:String = "")
		Local iteratorInterface:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(routine.returnType, ir)
		If Not iteratorInterface Or iteratorInterface.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_INTERFACE Then
			diagnostics :+ ["BMXC3085 generic yielding routine requires a closed generic iterator Interface return type"]
			Return ""
		End If
		Local iteratorMethods:TCompilerGenericMethodIr[] = TCompilerGenericSpecializationLowerer.EffectiveInterfaceMethods(iteratorInterface, ir, diagnostics)
		Local currentMethod:TCompilerGenericMethodIr
		For Local requirement:TCompilerGenericMethodIr = EachIn iteratorMethods
			If requirement.name.ToLower() = "current" Then currentMethod = requirement
		Next
		If Not currentMethod Or Not currentMethod.returnType Then
			diagnostics :+ ["BMXC3085 generic iterator Interface has no Current value contract"]
			Return ""
		End If
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			If parameter.passingMode = PARAMETER_PASS_VAR Then
				diagnostics :+ ["BMXC3085 generic yielding routines cannot retain Var parameters"]
				Return ""
			End If
		Next

		Local stateAbi:String = routine.abiName + "_iterator"
		Local moveNextName:String = stateAbi + "_MoveNext"
		Local currentName:String = stateAbi + "_Current"
		Local closeName:String = stateAbi + "_Close"
		Local declarations:TGenericTemplateNode[]
		CollectGenericIteratorLocals(routine.body, declarations, New TMap)
		Local iteratorLoops:TGenericTemplateNode[]
		CollectGenericIteratorLoops(routine.body, iteratorLoops, New TMap)
		Local ownedCleanups:TGenericTemplateNode[]
		CollectGenericIteratorOwnedCleanups(routine.body, ownedCleanups, New TMap)
		Local retainedTries:TGenericTemplateNode[]
		CollectGenericIteratorRetainedTries(routine.body, retainedTries, New TMap)
		Local states:Int[]
		Local nextState:Int = 1
		AssignGenericIteratorResumeStates(routine.body, nextState, states)

		Local interfaces:TGenericSpecializationNode[]
		Local hasClose:Int
		CollectGenericIteratorInterfaces(iteratorInterface, ir, interfaces, New TMap, hasClose, diagnostics)
		If iteratorInterface.readableAbiName.ToLower().Contains("icloseableiterator") Then hasClose = True
		Local result:TStringBuilder = New TStringBuilder(8192)
		result.Append("struct " + stateAbi + "_obj {~n    BBObject object;~n    BBINT state;~n    " + CValueDeclaration(currentMethod.returnType, "current", ir) + ";~n")
		If routine.isClosureInvoke Then result.Append("    BBOBJECT incoming_closure_environment;~n")
		For Local environment:TCompilerGenericClosureEnvironmentIr = EachIn routine.closureEnvironments
			result.Append("    BBOBJECT " + GenericIteratorClosureEnvironmentFieldName(environment) + ";~n")
		Next
		If routine.receiverType Then result.Append("    " + CValueDeclaration(routine.receiverType, "receiver", ir) + ";~n")
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			result.Append("    " + CValueDeclaration(parameter.semanticType, "parameter_" + TCompilerAbiNamer.Sanitize(parameter.name), ir) + ";~n")
		Next
		For Local declaration:TGenericTemplateNode = EachIn declarations
			If declaration.semanticType And declaration.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
				result.Append("    " + CStorageDeclaration(declaration.semanticType, GenericIteratorLocalFieldName(declaration), ir) + ";~n")
			Else
				result.Append("    " + CValueDeclaration(declaration.semanticType, GenericIteratorLocalFieldName(declaration), ir) + ";~n")
			End If
		Next
		For Local iteratorLoop:TGenericTemplateNode = EachIn iteratorLoops
			Local prefix:String = GenericIteratorLoopFieldPrefix(iteratorLoop)
			If iteratorLoop.valueText = "eachin-array" Then
				result.Append("    " + CValueDeclaration(iteratorLoop.children[1].semanticType, prefix + "_collection", ir) + ";~n")
				result.Append("    BBUINT " + prefix + "_index;~n")
				result.Append("    " + CValueDeclaration(iteratorLoop.children[1].semanticType.elementType, prefix + "_element", ir) + ";~n")
			Else If iteratorLoop.valueText = "eachin-static-array" Then
				result.Append("    " + CValueDeclaration(iteratorLoop.children[1].semanticType, prefix + "_collection", ir) + ";~n")
				result.Append("    BBUINT " + prefix + "_index;~n")
				result.Append("    " + CValueDeclaration(iteratorLoop.children[1].semanticType.elementType, prefix + "_element", ir) + ";~n")
			Else If iteratorLoop.valueText = "eachin-string" Then
				result.Append("    BBSTRING " + prefix + "_collection;~n")
				result.Append("    BBUINT " + prefix + "_index;~n")
				result.Append("    BBINT " + prefix + "_element;~n")
			Else If iteratorLoop.valueText = "eachin-iterable" Or iteratorLoop.valueText = "eachin-iterator" Then
				result.Append("    BBOBJECT " + prefix + "_collection;~n")
				result.Append("    BBOBJECT " + prefix + "_iterator;~n")
				result.Append("    BBOBJECT " + prefix + "_closeable;~n")
			Else If iteratorLoop.valueText = "eachin-object-enumerator" Then
				result.Append("    " + CValueDeclaration(iteratorLoop.children[1].semanticType, prefix + "_collection", ir) + ";~n")
				result.Append("    " + CValueDeclaration(iteratorLoop.children[2].semanticType, prefix + "_iterator", ir) + ";~n")
				result.Append("    BBOBJECT " + prefix + "_closeable;~n")
			End If
		Next
		For Local retainedTry:TGenericTemplateNode = EachIn retainedTries
			If GenericTryFinallyBody(retainedTry) Then
				Local prefix:String = GenericIteratorTryPrefix(retainedTry)
				result.Append("    BBOBJECT " + prefix + "_exception;~n")
				result.Append("    BBINT " + prefix + "_failed;~n")
			End If
		Next
		result.Append("};~n")
		result.Append("static BBINT " + moveNextName + "(BBOBJECT receiver);~n")
		result.Append("static " + CFunctionDeclaration(currentMethod.returnType, currentName, "BBOBJECT receiver", ir) + ";~n")
		result.Append("static void " + closeName + "(BBOBJECT receiver);~n")
		Local vdefName:String = stateAbi + "_interface_vdef"
		If hasClose Then result.Append("struct " + vdefName + "_close_methods { void (*m_Close)(BBOBJECT); };~n")
		result.Append("struct " + vdefName + " {~n")
		For Local index:Int = 0 Until interfaces.length
			result.Append("    struct " + interfaces[index].readableAbiName + "_methods interface_" + index + ";~n")
		Next
		If hasClose Then result.Append("    struct " + vdefName + "_close_methods close_interface;~n")
		result.Append("};~nstatic struct BBInterfaceOffsets " + stateAbi + "_interface_offsets[] = {~n")
		For Local index:Int = 0 Until interfaces.length
			result.Append("    { (BBINTERFACE)&" + interfaces[index].readableAbiName + "_ifc, offsetof(struct " + vdefName + ", interface_" + index + ") },~n")
		Next
		If hasClose Then result.Append("    { (BBINTERFACE)&brl_blitz_ICloseable_ifc, offsetof(struct " + vdefName + ", close_interface) },~n")
		result.Append("};~nstatic struct " + vdefName + " " + stateAbi + "_interface_vtable = {~n")
		For Local interfaceNode:TGenericSpecializationNode = EachIn interfaces
			Local requirements:TCompilerGenericMethodIr[] = TCompilerGenericSpecializationLowerer.EffectiveInterfaceMethods(interfaceNode, ir, diagnostics)
			result.Append("    { ")
			If Not requirements.length Then result.Append("0")
			For Local index:Int = 0 Until requirements.length
				If index Then result.Append(", ")
				Local requirement:TCompilerGenericMethodIr = requirements[index]
				Local targetName:String
				Select requirement.name.ToLower()
					Case "movenext"; targetName = moveNextName
					Case "current"; targetName = currentName
				End Select
				Local parameters:String = "BBOBJECT"
				For Local parameter:TGenericTemplateValueParameter = EachIn requirement.parameters
					parameters :+ ", " + CValueDeclaration(parameter.semanticType, "", ir, parameter.passingMode)
				Next
				If targetName.length Then result.Append("(" + CFunctionPointerDeclaration(requirement.returnType, "", parameters, ir) + ")" + targetName) Else result.Append("0")
			Next
			result.Append(" },~n")
		Next
		If hasClose Then result.Append("    { (void (*)(BBOBJECT))" + closeName + " },~n")
		result.Append("};~nstatic struct BBInterfaceTable " + stateAbi + "_itable = { " + stateAbi + "_interface_offsets, &" + stateAbi + "_interface_vtable, " + (interfaces.length + hasClose) + " };~n")
		Local lastFieldName:String = "current"
		If routine.isClosureInvoke Then lastFieldName = "incoming_closure_environment"
		If routine.closureEnvironments.length Then lastFieldName = GenericIteratorClosureEnvironmentFieldName(routine.closureEnvironments[routine.closureEnvironments.length - 1])
		If routine.receiverType Then lastFieldName = "receiver"
		If routine.parameters.length Then lastFieldName = "parameter_" + TCompilerAbiNamer.Sanitize(routine.parameters[routine.parameters.length - 1].name)
		If declarations.length Then lastFieldName = GenericIteratorLocalFieldName(declarations[declarations.length - 1])
		If iteratorLoops.length Then
			Local lastLoop:TGenericTemplateNode = iteratorLoops[iteratorLoops.length - 1]
			If lastLoop.valueText = "eachin-array" Or lastLoop.valueText = "eachin-string" Or lastLoop.valueText = "eachin-static-array" Then lastFieldName = GenericIteratorLoopFieldPrefix(lastLoop) + "_element" Else lastFieldName = GenericIteratorLoopFieldPrefix(lastLoop) + "_closeable"
		End If
		For Local retainedTryIndex:Int = retainedTries.length - 1 To 0 Step -1
			If GenericTryFinallyBody(retainedTries[retainedTryIndex]) Then
				lastFieldName = GenericIteratorTryPrefix(retainedTries[retainedTryIndex]) + "_failed"
				Exit
			End If
		Next
		Local objectSize:String = "offsetof(struct " + stateAbi + "_obj, " + lastFieldName + ") - offsetof(struct " + stateAbi + "_obj, state) + sizeof(((struct " + stateAbi + "_obj *)0)->" + lastFieldName + ")"
		result.Append("static BBClass " + stateAbi + "_class;~n")
		result.Append("static void " + stateAbi + "_ctor(BBOBJECT receiver) {~n    struct " + stateAbi + "_obj *state = (struct " + stateAbi + "_obj *)receiver;~n    receiver->clas = &" + stateAbi + "_class;~n    state->state = 0;~n    state->current = " + DefaultValue(currentMethod.returnType, ir) + ";~n")
		If routine.isClosureInvoke Then result.Append("    state->incoming_closure_environment = (BBOBJECT)&bbNullObject;~n")
		For Local environment:TCompilerGenericClosureEnvironmentIr = EachIn routine.closureEnvironments
			result.Append("    state->" + GenericIteratorClosureEnvironmentFieldName(environment) + " = (BBOBJECT)&bbNullObject;~n")
		Next
		If routine.receiverType Then result.Append("    state->receiver = " + DefaultValue(routine.receiverType, ir) + ";~n")
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			result.Append("    state->parameter_" + TCompilerAbiNamer.Sanitize(parameter.name) + " = " + DefaultValue(parameter.semanticType, ir) + ";~n")
		Next
		For Local declaration:TGenericTemplateNode = EachIn declarations
			If declaration.semanticType And declaration.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
				result.Append(EmitGenericStaticArrayInitialization(declaration.semanticType, "state->" + GenericIteratorLocalFieldName(declaration), ir, "    "))
			Else
				result.Append("    state->" + GenericIteratorLocalFieldName(declaration) + " = " + DefaultValue(declaration.semanticType, ir) + ";~n")
			End If
		Next
		For Local iteratorLoop:TGenericTemplateNode = EachIn iteratorLoops
			Local prefix:String = GenericIteratorLoopFieldPrefix(iteratorLoop)
			result.Append("    state->" + prefix + "_collection = " + DefaultValue(iteratorLoop.children[1].semanticType, ir) + ";~n")
			If iteratorLoop.valueText = "eachin-array" Or iteratorLoop.valueText = "eachin-string" Or iteratorLoop.valueText = "eachin-static-array" Then
				result.Append("    state->" + prefix + "_index = 0;~n")
				If iteratorLoop.valueText = "eachin-string" Then result.Append("    state->" + prefix + "_element = 0;~n") Else result.Append("    state->" + prefix + "_element = " + DefaultValue(iteratorLoop.children[1].semanticType.elementType, ir) + ";~n")
			Else
				If iteratorLoop.valueText = "eachin-iterable" Or iteratorLoop.valueText = "eachin-iterator" Then
					result.Append("    state->" + prefix + "_collection = (BBOBJECT)&bbNullObject;~n")
					result.Append("    state->" + prefix + "_iterator = (BBOBJECT)&bbNullObject;~n")
				Else
					result.Append("    state->" + prefix + "_iterator = " + DefaultValue(iteratorLoop.children[2].semanticType, ir) + ";~n")
				End If
				result.Append("    state->" + prefix + "_closeable = (BBOBJECT)&bbNullObject;~n")
			End If
		Next
		For Local retainedTry:TGenericTemplateNode = EachIn retainedTries
			If GenericTryFinallyBody(retainedTry) Then
				Local prefix:String = GenericIteratorTryPrefix(retainedTry)
				result.Append("    state->" + prefix + "_exception = (BBOBJECT)&bbNullObject;~n")
				result.Append("    state->" + prefix + "_failed = 0;~n")
			End If
		Next
		result.Append("}~n")
		result.Append("static BBClass " + stateAbi + "_class = {~n    &bbObjectClass, bbObjectFree, 0, sizeof(struct " + stateAbi + "_obj),~n    " + stateAbi + "_ctor, bbObjectDtor, bbObjectToString, bbObjectCompare, bbObjectSendMessage, bbObjectHashCode, bbObjectEquals,~n    &" + stateAbi + "_itable, 0, " + objectSize + ", 0, offsetof(struct " + stateAbi + "_obj, state)~n};~n")

		routine.isIteratorRoutine = True
		routine.iteratorStateAbiName = stateAbi
		routine.iteratorStateExpression = "state"
		If routine.receiverType Then routine.iteratorSelfExpression = "state->receiver"
		Local locals:TMap = New TMap
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			locals.Insert(parameter.name.ToLower(), "state->parameter_" + TCompilerAbiNamer.Sanitize(parameter.name))
		Next
		For Local ownedCleanup:TGenericTemplateNode = EachIn ownedCleanups
			routine.iteratorRetainedCleanupIdentities.Insert(ownedCleanup.identity, ownedCleanup)
		Next
		Local ownsResources:Int = ownedCleanups.length > 0
		routine.iteratorOwnsResources = ownsResources
		result.Append("static BBINT " + moveNextName + "(BBOBJECT receiver) {~n    struct " + stateAbi + "_obj *state = (struct " + stateAbi + "_obj *)receiver;~n")
		If routine.isClosureInvoke Then
			result.Append("    BBOBJECT environment = state->incoming_closure_environment;~n")
			For Local routineCapture:TCompilerGenericClosureCaptureIr = EachIn routine.closureCaptures
				Local capture:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(routine, routineCapture.name)
				If capture Then locals.Insert(capture.name.ToLower(), ClosureCaptureExpression(routine, capture))
			Next
		End If
		For Local environment:TCompilerGenericClosureEnvironmentIr = EachIn routine.closureEnvironments
			result.Append("    struct " + environment.abiName + "_obj *" + environment.localName + " = (struct " + environment.abiName + "_obj *)state->" + GenericIteratorClosureEnvironmentFieldName(environment) + ";~n")
		Next
		If routine.closureEnvironment Then
			For Local capture:TCompilerGenericClosureCaptureIr = EachIn routine.closureEnvironment.captures
				locals.Insert(capture.name.ToLower(), ClosureEnvironmentField(routine.closureEnvironment, capture))
			Next
		End If
		If ownsResources Then
			result.Append("    BBOBJECT bmx_iterator_exception = (BBOBJECT)&bbNullObject;~n    BBINT bmx_iterator_failed = 0;~n    bbExTry {~n    case 0: {~n")
			If ir.specialization.debugInstrumentation Then result.Append("        bbOnDebugPushExState();~n")
		End If
		Local moveIndent:String = "    "
		If ownsResources Then moveIndent = "        "
		result.Append(moveIndent + "switch (state->state) {~n" + moveIndent + "    case 0: state->state = -1; break;~n")
		For Local resumeState:Int = EachIn states
			Local resumeTarget:String = GenericIteratorResumeTarget(routine.body, resumeState)
			result.Append(moveIndent + "    case " + resumeState + ": ")
			If resumeTarget = "bmx_iterator_resume_" + resumeState Then result.Append("state->state = -1; ")
			result.Append("goto " + resumeTarget + ";~n")
		Next
		result.Append(moveIndent + "    default:")
		If ownsResources Then
			result.Append(" bbExLeave();")
			If ir.specialization.debugInstrumentation Then result.Append(" bbOnDebugPopExState();")
		End If
		result.Append(" return 0;~n" + moveIndent + "}~n")
		result.Append(EmitSequentialBlock(routine.body, ir, routine, diagnostics, locals, moveIndent))
		result.Append(moveIndent + "state->state = -1;~n")
		If ownsResources Then
			result.Append(moveIndent + "bbExLeave();~n")
			If ir.specialization.debugInstrumentation Then result.Append(moveIndent + "bbOnDebugPopExState();~n")
			result.Append(moveIndent + "return 0;~n    } break;~n    case 1: {~n")
			If ir.specialization.debugInstrumentation Then result.Append("        bbOnDebugPopExState();~n")
			result.Append("        bmx_iterator_exception = bbExCatch();~n        bmx_iterator_failed = 1;~n    } break;~n    }~n")
			result.Append(EmitGenericIteratorOwnedCleanup(ownedCleanups, ir, routine, diagnostics, locals, "    "))
			result.Append("    if (bmx_iterator_failed) bbExThrow((BBObject *)bmx_iterator_exception);~n    return 0;~n}~n")
		Else
			result.Append(moveIndent + "return 0;~n}~n")
		End If
		result.Append("static " + CFunctionDeclaration(currentMethod.returnType, currentName, "BBOBJECT receiver", ir) + " { return ((struct " + stateAbi + "_obj *)receiver)->current; }~n")
		result.Append("static void " + closeName + "(BBOBJECT receiver) { struct " + stateAbi + "_obj *state = (struct " + stateAbi + "_obj *)receiver;~n")
		Local iteratorYields:TGenericTemplateNode[]
		CollectGenericIteratorYields(routine.body, iteratorYields)
		If iteratorYields.length Then
			result.Append("    switch (state->state) {~n")
			For Local yielded:TGenericTemplateNode = EachIn iteratorYields
				result.Append("        case " + yielded.valueText + ":~n            state->state = -1;~n")
				If yielded.children.length = 2 Then result.Append(EmitGenericIteratorCloseCleanupEdges(yielded.children[1], 0, ir, routine, diagnostics, locals, "            "))
				result.Append("            break;~n")
			Next
			result.Append("        default: state->state = -1; break;~n    }~n")
		Else
			result.Append("    state->state = -1;~n")
		End If
		result.Append(EmitGenericIteratorOwnedCleanup(ownedCleanups, ir, routine, diagnostics, locals, "    "))
		result.Append("}~n")
		result.Append(EmitGenericGdbLineDirective(routine.source, ir, "") + CFunctionDeclaration(routine.returnType, routine.abiName, routineParameters, ir, factoryPrefix) + " {~n")
		If HasThreadedStaticFields(ir) Then result.Append("    " + ThreadInitializationName(ir) + "();~n")
		result.Append("    struct " + stateAbi + "_obj *state = (struct " + stateAbi + "_obj *)bbObjectNew(&" + stateAbi + "_class);~n    state->state = 0;~n")
		If routine.isClosureInvoke Then result.Append("    state->incoming_closure_environment = environment;~n")
		For Local environment:TCompilerGenericClosureEnvironmentIr = EachIn routine.closureEnvironments
			If environment = routine.closureEnvironment Then
				result.Append("    struct " + environment.abiName + "_obj *" + environment.localName + " = " + environment.abiName + "_new();~n")
				result.Append("    state->" + GenericIteratorClosureEnvironmentFieldName(environment) + " = (BBOBJECT)" + environment.localName + ";~n")
				If environment.parent Then result.Append("    " + environment.localName + "->" + environment.parentFieldName + " = environment;~n")
			End If
		Next
		If routine.receiverType Then result.Append("    state->receiver = self;~n")
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			result.Append("    state->parameter_" + TCompilerAbiNamer.Sanitize(parameter.name) + " = " + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n")
		Next
		If routine.closureEnvironment Then
			For Local capture:TCompilerGenericClosureCaptureIr = EachIn routine.closureEnvironment.captures
				Local fieldExpression:String = ClosureEnvironmentField(routine.closureEnvironment, capture)
				If capture.isSelf Then
					If routine.receiverType Then result.Append("    " + fieldExpression + " = self;~n")
				Else If capture.isParameter Then
					result.Append("    " + fieldExpression + " = " + TCompilerAbiNamer.Sanitize(capture.name) + ";~n")
				End If
			Next
		End If
		result.Append("    return (" + CType(routine.returnType, ir) + ")state;~n}~n")
		Return result.ToString()
	End Function

	Function GenericIteratorClosureEnvironmentFieldName:String(environment:TCompilerGenericClosureEnvironmentIr)
		If Not environment Then Return "closure_environment"
		Return "closure_environment_" + TCompilerStableDigest.Sha256(environment.abiName)[..12]
	End Function

	Function DynamicImplementationRegistrationName:String(ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.routine Then Return ""
		Return ir.routine.abiName + "_register_implementation"
	End Function

	Function DynamicImplementationAdapterName:String(ir:TCompilerGenericSpecializationIr, dispatcher:TGenericSpecializationNode)
		If Not ir Or Not ir.routine Or Not dispatcher Then Return ""
		Return ir.routine.abiName + "_dynamic_adapter_" + dispatcher.identityDigest[..16]
	End Function

	Function EmitDynamicImplementationRegistrations:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.routine Or Not ir.dynamicDispatchers.length Then Return ""
		Local ownerAbi:String = RoutineReceiverOwnerAbiName(ir)
		If Not ownerAbi.length Or Not ir.routine.receiverType Then
			diagnostics :+ ["BMXC3084 generic method implementation '" + ir.specialization.artifact.identity.StableName() + "' has no stable runtime class identity"]
			Return ""
		End If
		Local result:TStringBuilder = New TStringBuilder(2048)
		Local genericOwner:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(ir.routine.receiverType, ir)
		If genericOwner Then
			result.Append("struct " + ownerAbi + "_class;~n")
			result.Append("extern struct " + ownerAbi + "_class " + ownerAbi + ";~n")
		Else
			result.Append("struct BBClass_" + TCompilerAbiNamer.Sanitize(ownerAbi) + ";~n")
			result.Append("extern struct BBClass_" + TCompilerAbiNamer.Sanitize(ownerAbi) + " " + ownerAbi + ";~n")
		End If
		For Local dispatcher:TGenericSpecializationNode = EachIn ir.dynamicDispatchers
			Local dispatcherIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(dispatcher, diagnostics)
			If Not dispatcherIr Or Not dispatcherIr.routine Or Not DynamicMethodDispatcher(dispatcherIr) Then
				diagnostics :+ ["BMXC3085 generic method implementation registration has no closed dispatcher ABI"]
				Continue
			End If
			Local callbackName:String = DynamicDispatcherCallbackName(dispatcherIr)
			Local adapterName:String = DynamicImplementationAdapterName(ir, dispatcher)
			Local callbackParameters:String = "BBOBJECT self"
			For Local parameter:TGenericTemplateValueParameter = EachIn dispatcherIr.routine.parameters
				callbackParameters :+ ", " + CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), dispatcherIr, parameter.passingMode)
			Next
			result.Append("typedef " + CFunctionPointerDeclaration(dispatcherIr.routine.returnType, callbackName, callbackParameters, dispatcherIr) + ";~n")
			result.Append("extern void " + DynamicDispatcherRegisterName(dispatcherIr) + "(BBClass *owner, " + callbackName + " implementation);~n")
			Local adapterParameters:String = "BBOBJECT self"
			For Local parameter:TGenericTemplateValueParameter = EachIn dispatcherIr.routine.parameters
				adapterParameters :+ ", " + CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), dispatcherIr, parameter.passingMode)
			Next
			result.Append(CFunctionDeclaration(dispatcherIr.routine.returnType, adapterName, adapterParameters, dispatcherIr, "static ") + " {~n    ")
			If CType(dispatcherIr.routine.returnType, dispatcherIr) <> "void" Then result.Append("return ")
			result.Append(ir.routine.abiName + "((" + RoutineReceiverCType(ir.routine, ir) + ")self")
			For Local parameter:TGenericTemplateValueParameter = EachIn dispatcherIr.routine.parameters
				result.Append(", " + TCompilerAbiNamer.Sanitize(parameter.name))
			Next
			result.Append(");~n}~n")
		Next
		result.Append("void " + DynamicImplementationRegistrationName(ir) + "(void) {~n")
		For Local dispatcher:TGenericSpecializationNode = EachIn ir.dynamicDispatchers
			Local dispatcherIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(dispatcher, diagnostics)
			If Not dispatcherIr Or Not dispatcherIr.routine Or Not DynamicMethodDispatcher(dispatcherIr) Then Continue
			result.Append("    " + DynamicDispatcherRegisterName(dispatcherIr) + "((BBClass *)&" + ownerAbi + ", " + DynamicImplementationAdapterName(ir, dispatcher) + ");~n")
		Next
		result.Append("}~n")
		Return result.ToString()
	End Function

	Function EmitMethodDispatcher:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.routine Or (Not ir.dispatcherImplementations.length And Not ir.routine.body) Then
			diagnostics :+ ["BMXC3083 generic method dispatcher has no concrete implementation target"]
			Return ""
		End If
		Local result:TStringBuilder = New TStringBuilder(2048)
		Local declaredClasses:TMap = New TMap
		For Local target:TGenericSpecializationNode = EachIn ir.dispatcherImplementations
			Local targetIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(target, diagnostics)
			If Not targetIr Or Not targetIr.routine Or Not targetIr.routine.receiverType Then Continue
			Local ownerAbi:String = RoutineReceiverOwnerAbiName(targetIr)
			If Not ownerAbi.length Or declaredClasses.Contains(ownerAbi.ToLower()) Then Continue
			declaredClasses.Insert(ownerAbi.ToLower(), ownerAbi)
			Local genericOwner:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(targetIr.routine.receiverType, targetIr)
			If genericOwner Then
				result.Append("struct " + ownerAbi + "_class;~n")
				result.Append("extern struct " + ownerAbi + "_class " + ownerAbi + ";~n")
			Else
				result.Append("struct BBClass_" + TCompilerAbiNamer.Sanitize(ownerAbi) + ";~n")
				result.Append("extern struct BBClass_" + TCompilerAbiNamer.Sanitize(ownerAbi) + " " + ownerAbi + ";~n")
			End If
		Next
		result.Append(EmitDynamicDispatcherSupport(ir))
		Local dispatcherParameters:String
		If ir.specialization.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then dispatcherParameters = "BBOBJECT self" Else dispatcherParameters = RoutineReceiverCType(ir.routine, ir) + " self"
		For Local parameter:TGenericTemplateValueParameter = EachIn ir.routine.parameters
			dispatcherParameters :+ ", " + CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
		Next
		result.Append("~n" + EmitGenericGdbLineDirective(ir.routine.source, ir, "") + CFunctionDeclaration(ir.routine.returnType, ir.routine.abiName, dispatcherParameters, ir) + " {~n")
		result.Append("    BBClass *clas;~n")
		result.Append("    struct " + DynamicDispatcherEntryName(ir) + " *dynamic_entry;~n")
		result.Append("    " + DynamicDispatcherCallbackName(ir) + " dynamic_implementation;~n")
		result.Append("    if (!self || self == &bbNullObject) { brl_blitz_NullMethodError();")
		If CType(ir.routine.returnType, ir) <> "void" Then result.Append(" return " + DefaultValue(ir.routine.returnType, ir) + ";") Else result.Append(" return;")
		result.Append(" }~n")
		result.Append("    clas = ((BBObject *)self)->clas;~n")
		result.Append("    while (clas) {~n")
		result.Append("        dynamic_implementation = 0;~n")
		result.Append("        BB_LOCK~n")
		result.Append("        dynamic_entry = " + DynamicDispatcherHeadName(ir) + ";~n")
		result.Append("        while (dynamic_entry) {~n")
		result.Append("            if (dynamic_entry->owner == clas) { dynamic_implementation = dynamic_entry->implementation; break; }~n")
		result.Append("            dynamic_entry = dynamic_entry->next;~n")
		result.Append("        }~n")
		result.Append("        BB_UNLOCK~n")
		result.Append("        if (dynamic_implementation) { ")
		If CType(ir.routine.returnType, ir) <> "void" Then result.Append("return ")
		result.Append("dynamic_implementation((BBOBJECT)self")
		For Local parameter:TGenericTemplateValueParameter = EachIn ir.routine.parameters
			result.Append(", " + TCompilerAbiNamer.Sanitize(parameter.name))
		Next
		result.Append(");")
		If CType(ir.routine.returnType, ir) = "void" Then result.Append(" return;")
		result.Append(" }~n")
		For Local target:TGenericSpecializationNode = EachIn ir.dispatcherImplementations
			Local targetIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(target, diagnostics)
			If Not targetIr Or Not targetIr.routine Or Not targetIr.routine.receiverType Then Continue
			Local targetRoutine:TCompilerGenericMethodIr = targetIr.routine
			Local ownerAbi:String = RoutineReceiverOwnerAbiName(targetIr)
			If Not ownerAbi.length Then
				diagnostics :+ ["BMXC3084 generic method implementation '" + target.artifact.identity.StableName() + "' has no stable runtime class identity"]
				Continue
			End If
			result.Append("        if (clas == (BBClass *)&" + ownerAbi + ") { ")
			If CType(ir.routine.returnType, ir) <> "void" Then result.Append("return ")
			result.Append(targetRoutine.abiName + "((struct " + ownerAbi + "_obj *)self")
			For Local parameter:TGenericTemplateValueParameter = EachIn ir.routine.parameters
				result.Append(", " + TCompilerAbiNamer.Sanitize(parameter.name))
			Next
			result.Append(");")
			If CType(ir.routine.returnType, ir) = "void" Then result.Append(" return;")
			result.Append(" }~n")
		Next
		result.Append("        clas = clas->super;~n")
		result.Append("    }~n")
		If ir.routine.body Then
			result.Append(EmitBody(ir.routine.body, ir, ir.routine, diagnostics))
		Else
			result.Append("    brl_blitz_NullMethodError();~n")
			If CType(ir.routine.returnType, ir) <> "void" Then result.Append("    return " + DefaultValue(ir.routine.returnType, ir) + ";~n")
		End If
		result.Append("}~n")
		Return result.ToString()
	End Function

	Function DynamicMethodDispatcher:Int(ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.routine Or Not ir.specialization Or Not ir.specialization.artifact Then Return False
		If ir.specialization.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then Return True
		Return ir.specialization.artifact.isMethod And Not ir.routine.body
	End Function

	Function DynamicDispatcherCallbackName:String(ir:TCompilerGenericSpecializationIr)
		Return ir.routine.abiName + "_dynamic_implementation"
	End Function

	Function DynamicDispatcherRegisterName:String(ir:TCompilerGenericSpecializationIr)
		Return ir.routine.abiName + "_register_dynamic"
	End Function

	Function DynamicDispatcherEntryName:String(ir:TCompilerGenericSpecializationIr)
		Return ir.routine.abiName + "_dynamic_entry"
	End Function

	Function DynamicDispatcherHeadName:String(ir:TCompilerGenericSpecializationIr)
		Return ir.routine.abiName + "_dynamic_head"
	End Function

	Function EmitDynamicDispatcherSupport:String(ir:TCompilerGenericSpecializationIr)
		Local entryName:String = DynamicDispatcherEntryName(ir)
		Local headName:String = DynamicDispatcherHeadName(ir)
		Local callbackName:String = DynamicDispatcherCallbackName(ir)
		Local registerName:String = DynamicDispatcherRegisterName(ir)
		Local result:TStringBuilder = New TStringBuilder(1024)
		result.Append("struct " + entryName + " { BBClass *owner; " + callbackName + " implementation; struct " + entryName + " *next; };~n")
		result.Append("static struct " + entryName + " *" + headName + ";~n")
		result.Append("void " + registerName + "(BBClass *owner, " + callbackName + " implementation) {~n")
		result.Append("    struct " + entryName + " *entry;~n")
		result.Append("    if (!owner || !implementation) return;~n")
		result.Append("    BB_LOCK~n")
		result.Append("    entry = " + headName + ";~n")
		result.Append("    while (entry) {~n")
		result.Append("        if (entry->owner == owner) { entry->implementation = implementation; BB_UNLOCK return; }~n")
		result.Append("        entry = entry->next;~n")
		result.Append("    }~n")
		result.Append("    entry = (struct " + entryName + " *)bbMemAlloc(sizeof(struct " + entryName + "));~n")
		result.Append("    entry->owner = owner;~n")
		result.Append("    entry->implementation = implementation;~n")
		result.Append("    entry->next = " + headName + ";~n")
		result.Append("    " + headName + " = entry;~n")
		result.Append("    BB_UNLOCK~n")
		result.Append("}~n")
		Return result.ToString()
	End Function

	Function RoutineReceiverOwnerAbiName:String(routineIr:TCompilerGenericSpecializationIr)
		If Not routineIr Or Not routineIr.routine Or Not routineIr.routine.receiverType Then Return ""
		If routineIr.routine.receiverType.runtimeAbiName.length Then Return routineIr.routine.receiverType.runtimeAbiName
		Local ownerNode:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(routineIr.routine.receiverType, routineIr)
		If ownerNode Then Return ownerNode.readableAbiName
		Return ""
	End Function

	Function RoutineReceiverCType:String(routine:TCompilerGenericMethodIr, ir:TCompilerGenericSpecializationIr)
		Local result:String = CType(routine.receiverType, ir)
		If routine.receiverIsStruct And result.length Then result :+ " *"
		Return result
	End Function

	Function EmitRoutineOwnerDeclaration:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.routine Or Not ir.routine.receiverType Or ir.routine.receiverType.runtimeKind = TEMPLATE_RUNTIME_NONE Then Return ""
		Local artifact:TGenericTemplateArtifact = ir.specialization.artifact
		Local abiName:String = ir.routine.receiverType.runtimeAbiName
		If Not abiName.length Then Return ""
		Local result:String = "struct " + abiName
		If Not ir.routine.receiverIsStruct Then result :+ "_obj"
		result :+ " {~n"
		If Not ir.routine.receiverIsStruct Then result :+ "    BBClass *clas;~n"
		For Local ownerField:TGenericTemplateMember = EachIn artifact.containingFields
			Local fieldType:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(ownerField.semanticType, ir.specialization.key.containingTypeArguments, ir.specialization.key.typeArguments)
			Local cFieldType:String = CType(fieldType, ir)
			If Not cFieldType.length Then
				diagnostics :+ ["BMXC3065 generic method owner field '" + ownerField.name + "' has no supported canonical ABI"]
				Continue
			End If
			Local fieldLinkageName:String = ownerField.linkageName
			If Not fieldLinkageName.length Then fieldLinkageName = TCompilerAbiNamer.FieldName(abiName, ownerField.name)
			result :+ "    " + CStorageDeclaration(fieldType, fieldLinkageName, ir) + ";~n"
		Next
		Return result + "};~n"
	End Function

	Function EmitOrdinaryRuntimeTypeDeclarations:String(node:TGenericTemplateNode, emitted:TMap, diagnostics:String[] Var)
		If Not node Then Return ""
		Local result:String = EmitOrdinaryRuntimeTypeDeclaration(node.semanticType, emitted, diagnostics)
		If node.kind = TEMPLATE_NODE_NEW Then result :+ EmitOrdinaryObjectNewDeclaration(node, emitted, diagnostics)
		For Local child:TGenericTemplateNode = EachIn node.children
			result :+ EmitOrdinaryRuntimeTypeDeclarations(child, emitted, diagnostics)
		Next
		Return result
	End Function

	Function EmitOrdinaryObjectNewDeclaration:String(node:TGenericTemplateNode, emitted:TMap, diagnostics:String[] Var)
		If Not node Or Not node.semanticType Or node.semanticType.runtimeKind <> TEMPLATE_RUNTIME_CLASS Or Not node.semanticType.runtimeAbiName.length Or Not node.referencedSymbol Then Return ""
		If Not node.referencedSymbol Or Not node.referencedSymbol.overloadKey.length Or TCompilerAbiNamer.Sanitize(node.referencedSymbol.overloadKey) <> node.referencedSymbol.overloadKey Then
			diagnostics :+ ["BMXC3062 parameterized ordinary Type construction has no stable published allocation ABI"]
			Return ""
		End If
		Local key:String = "object-new:" + node.referencedSymbol.overloadKey.ToLower()
		If emitted.Contains(key) Then Return ""
		Local signature:TGenericTemplateNode
		If node.identity = "ordinary-constructor-signature" And node.children.length Then signature = node.children[0]
		If Not signature Then Return ""
		Local result:String = "struct " + node.semanticType.runtimeAbiName + "_obj *" + node.referencedSymbol.overloadKey + "(BBClass *clas"
		For Local index:Int = 0 Until signature.children.length
			Local parameter:TGenericTemplateNode = signature.children[index]
			Local parameterType:String = CValueDeclaration(parameter.semanticType, "", Null, Int(parameter.valueText))
			If Not parameterType.length Then
				diagnostics :+ ["BMXC3062 parameterized ordinary Type constructor argument " + index + " has no supported value ABI"]
				Return ""
			End If
			result :+ ", " + parameterType
		Next
		emitted.Insert(key, node)
		Return result + ");~n"
	End Function

	Function EmitOrdinaryRuntimeTypeDeclarationsForMembers:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local emitted:TMap = New TMap
		Local result:String
		For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
			result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(irField.semanticType, ir, emitted, diagnostics)
		Next
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(staticField.semanticType, ir, emitted, diagnostics)
			result :+ EmitOrdinaryRuntimeTypeDeclarations(staticField.initializer, emitted, diagnostics)
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
				result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(parameter.semanticType, ir, emitted, diagnostics)
			Next
			result :+ EmitOrdinaryRuntimeTypeDeclarations(constructor.body, emitted, diagnostics)
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(irMethod.returnType, ir, emitted, diagnostics)
			result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(irMethod.receiverType, ir, emitted, diagnostics)
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(parameter.semanticType, ir, emitted, diagnostics)
			Next
			result :+ EmitOrdinaryRuntimeTypeDeclarations(irMethod.body, emitted, diagnostics)
		Next
		Return result
	End Function

	Function EmitOrdinaryRuntimeSignatureTypeDeclarations:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr, emitted:TMap, diagnostics:String[] Var)
		If Not value Then Return ""
		Local result:String
		If value.elementType Then result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(value.elementType, ir, emitted, diagnostics)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			result :+ EmitOrdinaryRuntimeSignatureTypeDeclarations(argument, ir, emitted, diagnostics)
		Next
		' Canonical generic layouts and descriptors are declared by their owning
		' specialization declarations. Only their ordinary nested arguments need
		' independent file-scope declarations here.
		If TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir) Then Return result
		Return result + EmitOrdinaryRuntimeTypeDeclaration(value, emitted, diagnostics)
	End Function

	Function EmitOrdinaryRuntimeTypeDeclaration:String(value:TTemplateTypeReference, emitted:TMap, diagnostics:String[] Var)
		If Not value Then Return ""
		Local result:String
		If value.elementType Then result :+ EmitOrdinaryRuntimeTypeDeclaration(value.elementType, emitted, diagnostics)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			result :+ EmitOrdinaryRuntimeTypeDeclaration(argument, emitted, diagnostics)
		Next
		If value.runtimeKind = TEMPLATE_RUNTIME_NONE Then Return result
		Local abiName:String = value.runtimeAbiName
		' A constructed generic carries its runtime category in artifact format
		' 28, but its concrete declaration is owned by the canonical
		' specialization header rather than an ordinary language-linkage symbol.
		If Not abiName.length And value.arguments.length Then Return result
		If Not abiName.length Or TCompilerAbiNamer.Sanitize(abiName) <> abiName Then
			diagnostics :+ ["BMXC3060 ordinary runtime identity for '" + value.CanonicalName() + "' has an unsupported language-linkage name '" + abiName + "'"]
			Return result
		End If
		Local key:String = value.runtimeKind + ":" + abiName.ToLower()
		If emitted.Contains(key) Then Return result
		emitted.Insert(key, value)
		Select value.runtimeKind
			Case TEMPLATE_RUNTIME_CLASS
				result :+ "struct " + abiName + "_obj;~n"
				result :+ "struct BBClass_" + abiName + ";~n"
				result :+ "extern struct BBClass_" + abiName + " " + abiName + ";~n"
			Case TEMPLATE_RUNTIME_INTERFACE
				result :+ "extern const struct BBInterface " + abiName + "_ifc;~n"
			Case TEMPLATE_RUNTIME_STRUCT
				result :+ "struct " + abiName + ";~n"
			Case TEMPLATE_RUNTIME_ENUM
				' Enum values use their retained integral storage ABI, while Enum
				' Arrays also retain the defining Enum's runtime descriptor.
				result :+ "extern BBEnum *" + abiName + "_BBEnum_impl;~n"
			Default
				diagnostics :+ ["BMXC3060 ordinary runtime identity for '" + value.CanonicalName() + "' has unknown kind " + value.runtimeKind]
		End Select
		Return result
	End Function

	Function EmitStructImplementationUnit:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, declarationText:String = "")
		Local abiName:String = ir.specialization.readableAbiName
		Local result:String = "#include <stddef.h>~n#include <brl.mod/blitz.mod/blitz.h>~n" + DefiningModuleHeaderInclude(ir) + RuntimeArgumentHeaderIncludes(ir) + "~n" + ClosureRuntimeDeclaration()
		Local runtimeDeclarationText:String = EmitOrdinaryRuntimeTypeDeclarationsForMembers(ir, diagnostics)
		If runtimeDeclarationText.length Then result :+ runtimeDeclarationText + "~n"
		If Not declarationText.length Then declarationText = EmitStructDeclarations(ir, diagnostics)
		result :+ declarationText + "~n"
		' Registration walks every closed type reference. Publish Interface
		' registration and method-table declarations before those generated calls.
		For Local referencedInterface:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If referencedInterface.IsAbiReferenceOnly() Or referencedInterface.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_INTERFACE Then Continue
			result :+ EmitReferencedInterfaceDeclarations(referencedInterface, ir, diagnostics) + "~n"
		Next
		result :+ EmitStaticFieldDefinitions(ir, diagnostics)
		Local ordinaryDeclarations:TMap = New TMap
		Local ordinaryDeclarationText:String
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			ordinaryDeclarationText :+ EmitReferencedCallDeclarations(staticField.initializer, ir, ordinaryDeclarations, diagnostics)
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			ordinaryDeclarationText :+ EmitReferencedCallDeclarations(constructor.body, ir, ordinaryDeclarations, diagnostics)
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			ordinaryDeclarationText :+ EmitReferencedCallDeclarations(irMethod.body, ir, ordinaryDeclarations, diagnostics)
		Next
		If ordinaryDeclarationText.length Then result :+ ordinaryDeclarationText + "~n"
		result :+ EmitGenericDataSupport(ir, diagnostics)
		result :+ EmitStructConstructorHelper(ir, Null, diagnostics, abiName + "_New_ObjectNew")
		If ir.constructors.length Then
			For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
				result :+ EmitLocalRoutineSupport(constructor, constructor.body, ir, diagnostics)
				result :+ EmitStructConstructorHelper(ir, constructor, diagnostics)
			Next
		Else
			result :+ "struct " + abiName + " " + abiName + "_New(void) { return " + abiName + "_New_ObjectNew(); }~n~n"
		End If
		result :+ "void bbStructElementInit_" + abiName + "(void *bmx_value) {~n"
		result :+ "    *((struct " + abiName + " *)bmx_value) = " + abiName + "_New_ObjectNew();~n"
		result :+ "}~n~n"
		result :+ "BBArray *bbArrayNew1DStruct_" + abiName + "(int length) {~n"
		result :+ "    return bbArrayNew1DStruct(~q@" + SpecializationDisplayName(ir.specialization) + "~q, length, sizeof(struct " + abiName + "), bbStructElementInit_" + abiName + ");~n"
		result :+ "}~n~n"
		result :+ "BBArray *bbArraySliceStruct_" + abiName + "(BBArray *inarr, int beg, int end) {~n"
		result :+ "    return bbArraySliceStruct(~q@" + SpecializationDisplayName(ir.specialization) + "~q, inarr, beg, end, sizeof(struct " + abiName + "), bbStructElementInit_" + abiName + ");~n"
		result :+ "}~n~n"
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			result :+ EmitLocalRoutineSupport(irMethod, irMethod.body, ir, diagnostics)
			Local parameters:String
			If Not irMethod.isStatic Then parameters = "struct " + abiName + " *self"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				If parameters.length Then parameters :+ ", "
				parameters :+ CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
			If Not parameters.length Then parameters = "void"
			result :+ EmitGenericGdbLineDirective(irMethod.source, ir, "") + CFunctionDeclaration(irMethod.returnType, irMethod.abiName, parameters, ir) + " {~n"
			If HasThreadedStaticFields(ir) Then result :+ "    " + ThreadInitializationName(ir) + "();~n"
			If Not irMethod.isStatic Then result :+ "    (void)self;~n"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				result :+ "    (void)" + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n"
			Next
			result :+ EmitBody(irMethod.body, ir, irMethod, diagnostics)
			result :+ "}~n~n"
		Next
		result :+ EmitGenericCoverageCatalog(ir)
		result :+ EmitGenericCoverageRegistration(ir)
		result :+ EmitStructReflectionSupport(ir, diagnostics)
		Return result
	End Function

	Function EmitTypeReflectionSupport:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.specialization Then Return ""
		Local abiName:String = ir.specialization.readableAbiName
		Local result:String
		Local declarationCount:Int = 1
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.declaringSpecialization = ir.specialization And TemplateDebugTypeTag(staticField.semanticType, ir).length Then declarationCount :+ 1
		Next
		For Local fieldIndex:Int = 0 Until ir.declaredFieldCount
			Local irField:TCompilerGenericFieldIr = ir.fields[ir.declaredFieldStart + fieldIndex]
			If TemplateDebugTypeTag(irField.semanticType, ir).length Then declarationCount :+ 1
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			If Not ReflectionRoutineDiscoverable(constructor.parameters, Null, ir) Then Continue
			If ReflectionCallableSupported(constructor.parameters, Null, ir) Then result :+ EmitTypeConstructorReflectionWrapper(ir, constructor)
			declarationCount :+ 1
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If irMethod.declaringSpecialization <> ir.specialization Then Continue
			If Not ReflectionRoutineDiscoverable(irMethod.parameters, irMethod.returnType, ir) Then Continue
			If ReflectionCallableSupported(irMethod.parameters, irMethod.returnType, ir) Then result :+ EmitTypeMethodReflectionWrapper(ir, irMethod)
			declarationCount :+ 1
		Next
		Local debugName:String = SpecializationDisplayName(ir.specialization)
		Local typeFlags:String
		If ir.specialization.artifact.visibility = VISIBILITY_PRIVATE Then typeFlags :+ "P"
		If ir.specialization.artifact.visibility = VISIBILITY_PROTECTED Then typeFlags :+ "Q"
		If ir.specialization.artifact.isAbstract Then typeFlags :+ "A"
		If typeFlags.length Then debugName :+ "'" + typeFlags
		debugName = AppendTemplateMetadata(debugName, ir.specialization.artifact.metadata)
		Local debugScopeName:String = abiName + "_debug_scope"
		result :+ "static struct { unsigned int kind; const char *name; BBDebugDecl decls[" + declarationCount + "]; } " + debugScopeName + " = {~n"
		result :+ "    BBDEBUGSCOPE_USERTYPE, " + CQuoted(debugName) + ", {~n"
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.declaringSpecialization <> ir.specialization Then Continue
			Local staticTag:String = TemplateDebugTypeTag(staticField.semanticType, ir)
			If Not staticTag.length Then Continue
			Local address:String = "(void *)&" + staticField.abiName
			If staticField.isThreadedGlobal Then address = "0"
			result :+ "        { BBDEBUGDECL_GLOBAL, " + CQuoted(staticField.name) + ", " + CQuoted(ReflectedTemplateMemberType(staticTag, staticField.visibility, staticField.metadata)) + ", .var_address = " + address + ", .reflection_wrapper = 0 },~n"
		Next
		For Local fieldIndex:Int = 0 Until ir.declaredFieldCount
			Local irField:TCompilerGenericFieldIr = ir.fields[ir.declaredFieldStart + fieldIndex]
			Local fieldTag:String = TemplateDebugTypeTag(irField.semanticType, ir)
			If Not fieldTag.length Then Continue
			result :+ "        { BBDEBUGDECL_FIELD, " + CQuoted(irField.name) + ", " + CQuoted(ReflectedTemplateMemberType(fieldTag, irField.visibility, irField.metadata)) + ", .field_offset = offsetof(struct " + abiName + "_obj, " + irField.abiName + "), .reflection_wrapper = 0 },~n"
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			If Not ReflectionRoutineDiscoverable(constructor.parameters, Null, ir) Then Continue
			Local wrapperName:String = "0"
			If ReflectionCallableSupported(constructor.parameters, Null, ir) Then wrapperName = TypeConstructorReflectionWrapperName(constructor)
			result :+ "        { BBDEBUGDECL_TYPEMETHOD, " + CQuoted("New") + ", " + CQuoted(ReflectedTemplateMemberType(ReflectedTemplateRoutineType(constructor.parameters, Null, ir), constructor.visibility, constructor.metadata)) + ", .func_ptr = (BBFuncPtr)&" + constructor.abiName + "_init, .reflection_wrapper = " + wrapperName + " },~n"
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If irMethod.declaringSpecialization <> ir.specialization Then Continue
			If Not ReflectionRoutineDiscoverable(irMethod.parameters, irMethod.returnType, ir) Then Continue
			Local wrapperName:String = "0"
			If ReflectionCallableSupported(irMethod.parameters, irMethod.returnType, ir) Then wrapperName = TypeMethodReflectionWrapperName(irMethod)
			Local declarationKind:String = "BBDEBUGDECL_TYPEMETHOD"
			If irMethod.isTypeFunction Then declarationKind = "BBDEBUGDECL_TYPEFUNCTION"
			result :+ "        { " + declarationKind + ", " + CQuoted(irMethod.name) + ", " + CQuoted(ReflectedTemplateMemberType(ReflectedTemplateRoutineType(irMethod.parameters, irMethod.returnType, ir), irMethod.visibility, irMethod.metadata)) + ", .func_ptr = (BBFuncPtr)&" + irMethod.abiName + ", .reflection_wrapper = " + wrapperName + " },~n"
		Next
		result :+ "        { BBDEBUGDECL_END, 0, 0, .var_address = 0, .reflection_wrapper = 0 }~n"
		result :+ "    }~n};~n~n"
		Return result
	End Function

	Function EmitTypeMethodReflectionWrapper:String(ir:TCompilerGenericSpecializationIr, irMethod:TCompilerGenericMethodIr)
		Local result:String = "static void " + TypeMethodReflectionWrapperName(irMethod) + "(void **buf) {~n"
		Local offset:String
		Local call:String
		If VoidType(irMethod.returnType) Then
			call = "    " + irMethod.abiName + "("
		Else
			Local returnType:String = CValueDeclaration(irMethod.returnType, "", ir)
			Local returnStorageType:String = CValueDeclaration(irMethod.returnType, "*", ir)
			call = "    *((" + returnStorageType + ")buf) = " + irMethod.abiName + "("
			offset = ReflectionBufferSlotCount(returnType)
		End If
		If Not irMethod.isTypeFunction Then
			Local receiverType:String = "struct " + ir.specialization.readableAbiName + "_obj *"
			call :+ ReflectionBufferValue(receiverType, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(receiverType)
		End If
		For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
			If Not irMethod.isTypeFunction Or parameter <> irMethod.parameters[0] Then call :+ ", "
			call :+ ReflectionBufferParameterValue(parameter, ir, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(ReflectionParameterCType(parameter, ir))
		Next
		Return result + call + ");~n}~n"
	End Function

	Function EmitTypeConstructorReflectionWrapper:String(ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr)
		Local receiverType:String = "struct " + ir.specialization.readableAbiName + "_obj *"
		Local result:String = "static void " + TypeConstructorReflectionWrapperName(constructor) + "(void **buf) {~n"
		result :+ "    " + constructor.abiName + "_init(" + ReflectionBufferValue(receiverType, "")
		Local offset:String = ReflectionBufferSlotCount(receiverType)
		For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
			result :+ ", " + ReflectionBufferParameterValue(parameter, ir, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(ReflectionParameterCType(parameter, ir))
		Next
		Return result + ");~n}~n"
	End Function

	Function TypeMethodReflectionWrapperName:String(irMethod:TCompilerGenericMethodIr)
		Return irMethod.abiName + "_ReflectionWrapper"
	End Function

	Function TypeConstructorReflectionWrapperName:String(constructor:TCompilerGenericMethodIr)
		Return constructor.abiName + "_init_ReflectionWrapper"
	End Function

	Function EmitStructReflectionSupport:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Or Not ir.specialization Then Return ""
		Local abiName:String = ir.specialization.readableAbiName
		Local result:String
		Local declarationCount:Int = 1
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If TemplateDebugTypeTag(staticField.semanticType, ir).length Then declarationCount :+ 1
		Next
		For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
			If TemplateDebugTypeTag(irField.semanticType, ir).length Then declarationCount :+ 1
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			If Not ReflectionRoutineDiscoverable(constructor.parameters, Null, ir) Then Continue
			If ReflectionCallableSupported(constructor.parameters, Null, ir) Then result :+ EmitStructConstructorReflectionWrapper(ir, constructor)
			declarationCount :+ 1
		Next
		If Not ir.constructors.length Then
			result :+ EmitStructConstructorReflectionWrapper(ir, Null)
			declarationCount :+ 1
		End If
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If Not ReflectionRoutineDiscoverable(irMethod.parameters, irMethod.returnType, ir) Then Continue
			If ReflectionCallableSupported(irMethod.parameters, irMethod.returnType, ir) Then result :+ EmitStructMethodReflectionWrapper(ir, irMethod)
			declarationCount :+ 1
		Next
		Local debugScopeName:String = abiName + "_debug_scope"
		Local debugName:String = ReflectedTemplateMemberType(SpecializationDisplayName(ir.specialization), ir.specialization.artifact.visibility, ir.specialization.artifact.metadata)
		result :+ "static struct { unsigned int kind; const char *name; BBDebugDecl decls[" + declarationCount + "]; } " + debugScopeName + " = {~n"
		result :+ "    BBDEBUGSCOPE_USERSTRUCT, " + CQuoted(debugName) + ", {~n"
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			Local staticTag:String = TemplateDebugTypeTag(staticField.semanticType, ir)
			If Not staticTag.length Then Continue
			Local address:String = "(void *)&" + staticField.abiName
			If staticField.isThreadedGlobal Then address = "0"
			result :+ "        { BBDEBUGDECL_GLOBAL, " + CQuoted(staticField.name) + ", " + CQuoted(ReflectedTemplateMemberType(staticTag, staticField.visibility, staticField.metadata)) + ", .var_address = " + address + ", .reflection_wrapper = 0 },~n"
		Next
		For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
			Local fieldTag:String = TemplateDebugTypeTag(irField.semanticType, ir)
			If Not fieldTag.length Then Continue
			result :+ "        { BBDEBUGDECL_FIELD, " + CQuoted(irField.name) + ", " + CQuoted(ReflectedTemplateMemberType(fieldTag, irField.visibility, irField.metadata)) + ", .field_offset = offsetof(struct " + abiName + ", " + irField.abiName + "), .reflection_wrapper = 0 },~n"
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			If Not ReflectionRoutineDiscoverable(constructor.parameters, Null, ir) Then Continue
			Local constructorWrapperName:String = "0"
			If ReflectionCallableSupported(constructor.parameters, Null, ir) Then constructorWrapperName = StructConstructorReflectionWrapperName(ir, constructor)
			result :+ "        { BBDEBUGDECL_TYPEMETHOD, ~qNew~q, " + CQuoted(ReflectedTemplateMemberType(ReflectedTemplateRoutineType(constructor.parameters, Null, ir), constructor.visibility, constructor.metadata)) + ", .func_ptr = (BBFuncPtr)&" + constructor.abiName + ", .reflection_wrapper = " + constructorWrapperName + " },~n"
		Next
		If Not ir.constructors.length Then
			result :+ "        { BBDEBUGDECL_TYPEMETHOD, ~qNew~q, ~q()~q, .func_ptr = (BBFuncPtr)&" + abiName + "_New, .reflection_wrapper = " + StructConstructorReflectionWrapperName(ir, Null) + " },~n"
		End If
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If Not ReflectionRoutineDiscoverable(irMethod.parameters, irMethod.returnType, ir) Then Continue
			Local methodWrapperName:String = "0"
			If ReflectionCallableSupported(irMethod.parameters, irMethod.returnType, ir) Then methodWrapperName = StructMethodReflectionWrapperName(irMethod)
			Local declarationKind:String = "BBDEBUGDECL_TYPEMETHOD"
			If irMethod.isStatic Then declarationKind = "BBDEBUGDECL_TYPEFUNCTION"
			result :+ "        { " + declarationKind + ", " + CQuoted(irMethod.name) + ", " + CQuoted(ReflectedTemplateMemberType(ReflectedTemplateRoutineType(irMethod.parameters, irMethod.returnType, ir), irMethod.visibility, irMethod.metadata)) + ", .func_ptr = (BBFuncPtr)&" + irMethod.abiName + ", .reflection_wrapper = " + methodWrapperName + " },~n"
		Next
		result :+ "        { BBDEBUGDECL_END, 0, 0, .struct_size = sizeof(struct " + abiName + "), .reflection_wrapper = 0 }~n"
		result :+ "    }~n};~n~n"
		result :+ EmitThreadedStaticInitialization(ir, diagnostics, debugScopeName)
		result :+ "void " + abiName + "_register(void) {~n"
		result :+ "    static int registered = 0;~n"
		result :+ "    if (!registered) {~n"
		result :+ "        registered = 1;~n"
		Local registrationIndent:String = "        "
		If HasThreadedStaticFields(ir) Then
			result :+ "        BBOBJECT bmx_initialization_exception = (BBOBJECT)&bbNullObject;~n"
			result :+ "        bbExTry {~n"
			result :+ "        case 0: {~n"
			If ir.specialization.debugInstrumentation Then result :+ "            bbOnDebugPushExState();~n"
			result :+ "            " + ThreadInitializationFlagName(ir) + " = 1;~n"
			registrationIndent = "            "
		End If
		result :+ EmitReferencedTypeRegistrations(ir, registrationIndent)
		result :+ EmitStaticFieldInitializers(ir, diagnostics, registrationIndent)
		If HasThreadedStaticFields(ir) Then result :+ registrationIndent + ThreadInitializationFlagName(ir) + " = 2;~n"
		Local reflectionDeclarationIndex:Int
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If Not TemplateDebugTypeTag(staticField.semanticType, ir).length Then Continue
			If staticField.isThreadedGlobal Then result :+ registrationIndent + debugScopeName + ".decls[" + reflectionDeclarationIndex + "].var_address = (void *)&" + staticField.abiName + ";~n"
			reflectionDeclarationIndex :+ 1
		Next
		result :+ registrationIndent + "bbObjectRegisterStruct((BBDebugScope *)&" + debugScopeName + ");~n"
		If HasThreadedStaticFields(ir) Then
			result :+ "            bbExLeave();~n"
			If ir.specialization.debugInstrumentation Then result :+ "            bbOnDebugPopExState();~n"
			result :+ "        } break;~n"
			result :+ "        case 1: {~n"
			If ir.specialization.debugInstrumentation Then result :+ "            bbOnDebugPopExState();~n"
			result :+ "            bmx_initialization_exception = bbExCatch();~n"
			result :+ "            registered = 0;~n"
			result :+ "            " + ThreadInitializationFlagName(ir) + " = 0;~n"
			result :+ "            bbExThrow((BBObject *)bmx_initialization_exception);~n"
			result :+ "        } break;~n"
			result :+ "        }~n"
		End If
		result :+ "    }~n"
		If HasThreadedStaticFields(ir) Then result :+ "    " + ThreadInitializationName(ir) + "();~n"
		result :+ "}~n"
		Return result
	End Function

	Function EmitStructMethodReflectionWrapper:String(ir:TCompilerGenericSpecializationIr, irMethod:TCompilerGenericMethodIr)
		Local wrapperName:String = StructMethodReflectionWrapperName(irMethod)
		Local result:String = "static void " + wrapperName + "(void **buf) {~n"
		Local offset:String
		Local call:String
		If VoidType(irMethod.returnType) Then
			call = "    " + irMethod.abiName + "("
		Else
			Local returnType:String = CValueDeclaration(irMethod.returnType, "", ir)
			Local returnStorageType:String = CValueDeclaration(irMethod.returnType, "*", ir)
			call = "    *((" + returnStorageType + ")buf) = " + irMethod.abiName + "("
			offset = ReflectionBufferSlotCount(returnType)
		End If
		If Not irMethod.isStatic Then
			Local receiverType:String = "struct " + ir.specialization.readableAbiName + " *"
			call :+ ReflectionBufferValue(receiverType, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(receiverType)
		End If
		For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
			If Not irMethod.isStatic Or parameter <> irMethod.parameters[0] Then call :+ ", "
			call :+ ReflectionBufferParameterValue(parameter, ir, offset)
			If offset.length Then offset :+ " + "
			offset :+ ReflectionBufferSlotCount(ReflectionParameterCType(parameter, ir))
		Next
		Return result + call + ");~n}~n"
	End Function

	Function EmitStructConstructorReflectionWrapper:String(ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr)
		Local abiName:String = ir.specialization.readableAbiName
		Local helperName:String = abiName + "_New"
		If constructor Then helperName = constructor.abiName
		Local result:String = "static void " + StructConstructorReflectionWrapperName(ir, constructor) + "(void **buf) {~n"
		Local receiverType:String = "struct " + abiName + " *"
		' Reflection supplies the address of the boxed Struct value in the
		' first pointer-sized slot. The canonical constructor helper returns
		' the new value by value, so assign through that supplied address.
		result :+ "    *" + ReflectionBufferValue(receiverType, "") + " = " + helperName + "("
		Local offset:String = ReflectionBufferSlotCount(receiverType)
		If constructor Then
			For Local index:Int = 0 Until constructor.parameters.length
				If index Then result :+ ", "
				Local parameter:TGenericTemplateValueParameter = constructor.parameters[index]
				Local parameterType:String = ReflectionParameterCType(parameter, ir)
				result :+ ReflectionBufferParameterValue(parameter, ir, offset)
				If offset.length Then offset :+ " + "
				offset :+ ReflectionBufferSlotCount(parameterType)
			Next
		End If
		Return result + ");~n}~n"
	End Function

	Function ReflectionBufferValue:String(cType:String, offset:String)
		Local address:String = "buf"
		If offset.length Then address = "(buf + (" + offset + "))"
		Return "*((" + cType + " *)" + address + ")"
	End Function

	Function ReflectionBufferSlotCount:String(cType:String)
		Return "((sizeof(" + cType + ") + sizeof(void *) - 1) / sizeof(void *))"
	End Function

	Function ReflectionParameterCType:String(parameter:TGenericTemplateValueParameter, ir:TCompilerGenericSpecializationIr)
		Local result:String = CType(parameter.semanticType, ir)
		If parameter.passingMode = PARAMETER_PASS_VAR Then result :+ " *"
		Return result
	End Function

	Function ReflectionBufferParameterValue:String(parameter:TGenericTemplateValueParameter, ir:TCompilerGenericSpecializationIr, offset:String)
		If Not parameter.semanticType Or parameter.semanticType.kind <> TEMPLATE_TYPE_CALLABLE Then
			Return ReflectionBufferValue(ReflectionParameterCType(parameter, ir), offset)
		End If
		' A supported value-mode callable occupies one pointer-sized buffer slot.
		' Cast that slot's address to a pointer to the exact closed function-pointer
		' type before dereferencing it; BBFuncPtr would discard the prototype.
		Local storageType:String = CValueDeclaration(parameter.semanticType, "*", ir)
		Local address:String = "buf"
		If offset.length Then address = "(buf + (" + offset + "))"
		Return "*((" + storageType + ")" + address + ")"
	End Function

	Function ReflectionCallableSupported:Int(parameters:TGenericTemplateValueParameter[], returnType:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not ReflectionRoutineDiscoverable(parameters, returnType, ir) Then Return False
		If returnType And returnType.kind = TEMPLATE_TYPE_CALLABLE And Not TCompilerGenericSpecializationLowerer.SupportedCallableType(returnType, ir) Then Return False
		If returnType And Not VoidType(returnType) And Not TemplateDebugTypeTag(returnType, ir).length Then Return False
		For Local parameter:TGenericTemplateValueParameter = EachIn parameters
			If parameter.semanticType And parameter.semanticType.kind = TEMPLATE_TYPE_CALLABLE Then
				If parameter.passingMode <> PARAMETER_PASS_VALUE Then Return False
				If Not TCompilerGenericSpecializationLowerer.SupportedCallableType(parameter.semanticType, ir) Then Return False
			End If
			If Not TemplateDebugTypeTag(parameter.semanticType, ir).length Then Return False
		Next
		Return True
	End Function

	Function ReflectionRoutineDiscoverable:Int(parameters:TGenericTemplateValueParameter[], returnType:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If returnType And Not VoidType(returnType) And ReflectionTagHasGenericSeparator(TemplateDebugTypeTag(returnType, ir)) Then Return False
		For Local parameter:TGenericTemplateValueParameter = EachIn parameters
			If ReflectionTagHasGenericSeparator(TemplateDebugTypeTag(parameter.semanticType, ir)) Then Return False
		Next
		Return True
	End Function

	Function ReflectionTagHasGenericSeparator:Int(tag:String)
		Local depth:Int
		For Local index:Int = 0 Until tag.length
			Select tag[index]
				Case Asc("<") depth :+ 1
				Case Asc(">") If depth Then depth :- 1
				Case Asc(",") If depth Then Return True
			End Select
		Next
		Return False
	End Function

	Function StructMethodReflectionWrapperName:String(irMethod:TCompilerGenericMethodIr)
		Return irMethod.abiName + "_ReflectionWrapper"
	End Function

	Function StructConstructorReflectionWrapperName:String(ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr)
		If constructor Then Return constructor.abiName + "_ReflectionWrapper"
		Return ir.specialization.readableAbiName + "_New_ReflectionWrapper"
	End Function

	Function ReflectedTemplateRoutineType:String(parameters:TGenericTemplateValueParameter[], returnType:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		Local result:String = "("
		For Local index:Int = 0 Until parameters.length
			If index Then result :+ ","
			If parameters[index].passingMode = PARAMETER_PASS_VAR Then result :+ "&"
			result :+ TemplateDebugTypeTag(parameters[index].semanticType, ir)
		Next
		result :+ ")"
		If returnType And Not VoidType(returnType) Then result :+ TemplateDebugTypeTag(returnType, ir)
		Return result
	End Function

	Function ReflectedTemplateMemberType:String(typeTag:String, visibility:Int, metadata:TGenericTemplateMetadataEntry[] = Null)
		If visibility = VISIBILITY_PRIVATE Then typeTag :+ "'P"
		If visibility = VISIBILITY_PROTECTED Then typeTag :+ "'Q"
		Return AppendTemplateMetadata(typeTag, metadata)
	End Function

	Function AppendTemplateMetadata:String(typeTag:String, metadata:TGenericTemplateMetadataEntry[])
		If metadata.length Then
			typeTag :+ "{"
			For Local index:Int = 0 Until metadata.length
				If index Then typeTag :+ " "
				typeTag :+ metadata[index].key + "=~q" + metadata[index].value + "~q"
			Next
			typeTag :+ "}"
		End If
		Return typeTag
	End Function

	Function CQuoted:String(value:String)
		Return Chr(34) + value.Replace("\", "\\").Replace(Chr(34), "\" + Chr(34)) + Chr(34)
	End Function

	Function TemplateDebugTypeTag:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not value Then Return ""
		If value.kind = TEMPLATE_TYPE_POINTER Then
			Local elementTag:String = TemplateDebugTypeTag(value.elementType, ir)
			If Not elementTag.length Then Return ""
			Return "*" + elementTag
		End If
		If value.kind = TEMPLATE_TYPE_ARRAY Then
			Local elementTag:String = TemplateDebugTypeTag(value.elementType, ir)
			If Not elementTag.length Then Return ""
			Local rankTag:String = "["
			For Local index:Int = 1 Until value.rank
				rankTag :+ ","
			Next
			Return rankTag + "]" + elementTag
		End If
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
			Local elementTag:String = TemplateDebugTypeTag(value.elementType, ir)
			If Not elementTag.length Then Return ""
			Return "[" + value.staticArrayLength + "]" + elementTag
		End If
		If value.kind = TEMPLATE_TYPE_CALLABLE Then
			Local callableTag:String = "("
			For Local index:Int = 0 Until value.arguments.length
				If index Then callableTag :+ ","
				If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then callableTag :+ "&"
				Local parameterTag:String = TemplateDebugTypeTag(value.arguments[index], ir)
				If Not parameterTag.length Then Return ""
				callableTag :+ parameterTag
			Next
			callableTag :+ ")"
			If value.elementType And Not VoidType(value.elementType) Then
				Local returnTag:String = TemplateDebugTypeTag(value.elementType, ir)
				If Not returnTag.length Then Return ""
				callableTag :+ returnTag
			End If
			Return callableTag
		End If
		If value.kind = TEMPLATE_TYPE_CLOSURE Then
			Local closureTag:String = "!("
			For Local index:Int = 0 Until value.arguments.length
				If index Then closureTag :+ ","
				If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then closureTag :+ "&"
				Local parameterTag:String = TemplateDebugTypeTag(value.arguments[index], ir)
				If Not parameterTag.length Then Return ""
				closureTag :+ parameterTag
			Next
			closureTag :+ ")"
			If value.elementType And Not VoidType(value.elementType) Then
				Local returnTag:String = TemplateDebugTypeTag(value.elementType, ir)
				If Not returnTag.length Then Return ""
				closureTag :+ returnTag
			End If
			Return closureTag
		End If
		If value.kind = TEMPLATE_TYPE_NAMED Then
			Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
			Local displayName:String = value.symbolName
			If referenced Then displayName = SpecializationDisplayName(referenced)
			If referenced Then
				If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then Return "@" + displayName
				Return ":" + displayName
			End If
			If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then Return "@" + displayName
			If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return "/" + displayName
			If value.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then Return ":" + displayName
			Return ""
		End If
		If value.kind <> TEMPLATE_TYPE_BUILTIN Then Return ""
		Select value.symbolName.ToLower()
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
		Return ""
	End Function

	Function EmitStructConstructorHelper:String(ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr, diagnostics:String[] Var, helperNameOverride:String = "")
		Local abiName:String = ir.specialization.readableAbiName
		Local helperName:String = abiName + "_New"
		If constructor Then helperName = constructor.abiName
		If helperNameOverride.length Then helperName = helperNameOverride
		Local result:String = "struct " + abiName + " " + helperName + "(" + StructConstructorParameters(constructor, ir, True) + ") {~n"
		If HasThreadedStaticFields(ir) Then result :+ "    " + ThreadInitializationName(ir) + "();~n"
		If constructor And constructor.delegatedConstructor Then
			result :+ "    struct " + abiName + " bmx_value = " + constructor.delegatedConstructor.abiName + "("
			For Local index:Int = 0 Until constructor.delegationArguments.length
				If index Then result :+ ", "
				result :+ EmitStructConstructorCallArgument(constructor.delegationArguments[index], constructor.delegatedConstructor.parameters[index], ir, constructor, diagnostics)
			Next
			result :+ ");~n"
		Else
			result :+ "    struct " + abiName + " bmx_value = {0};~n"
			For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
				If irField.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
					Local fieldStruct:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(irField.semanticType.elementType, ir)
					Local fieldInitializer:String
					If fieldStruct And fieldStruct.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then
						fieldInitializer = fieldStruct.readableAbiName + "_New_ObjectNew()"
					Else If irField.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT And irField.semanticType.elementType.runtimeAbiName.length Then
						fieldInitializer = irField.semanticType.elementType.runtimeAbiName + "_New_ObjectNew()"
					Else If ManagedReferenceType(irField.semanticType.elementType, ir) Then
						fieldInitializer = DefaultValue(irField.semanticType.elementType, ir)
					End If
					If fieldInitializer.length Then
						Local fieldIndex:String = "bmx_" + TCompilerAbiNamer.Sanitize(irField.abiName) + "_index"
						result :+ "    for (BBUINT " + fieldIndex + " = 0; " + fieldIndex + " < (BBUINT)" + irField.semanticType.staticArrayLength + "; ++" + fieldIndex + ") bmx_value." + irField.abiName + "[" + fieldIndex + "] = " + fieldInitializer + ";~n"
					End If
				Else
					result :+ "    bmx_value." + irField.abiName + " = " + FieldInitializerValue(irField, ir, diagnostics) + ";~n"
				End If
			Next
		End If
		If constructor Then
			For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
				result :+ "    (void)" + StructConstructorParameterName(parameter.name) + ";~n"
			Next
			result :+ EmitConstructorBody(constructor.body, ir, constructor, diagnostics)
		End If
		result :+ "    return bmx_value;~n"
		result :+ "}~n~n"
		Return result
	End Function

	Function FieldInitializerValue:String(irField:TCompilerGenericFieldIr, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not irField Or Not irField.initializer Then Return DefaultValue(irField.semanticType, ir)
		Return EmitExpression(irField.initializer, ir, Null, diagnostics)
	End Function

	Function EmitStaticFieldDefinitions:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not ir Then Return ""
		Local result:String
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.declaringSpecialization And staticField.declaringSpecialization <> ir.specialization Then Continue
			Local declaration:String = CStorageDeclaration(staticField.semanticType, staticField.abiName, ir)
			If Not declaration.length Then
				diagnostics :+ ["BMXC3022 generic static member '" + staticField.name + "' has no C ABI storage declaration"]
				Continue
			End If
			Local threadedPrefix:String
			If staticField.isThreadedGlobal Then threadedPrefix = "BBThreadLocal "
			result :+ threadedPrefix + declaration + ";~n"
		Next
		If HasThreadedStaticFields(ir) Then result :+ "static BBThreadLocal BBINT " + ThreadInitializationFlagName(ir) + ";~n"
		If result.length Then result :+ "~n"
		Return result
	End Function

	Function HasThreadedStaticFields:Int(ir:TCompilerGenericSpecializationIr)
		If Not ir Then Return False
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.isThreadedGlobal Then Return True
		Next
		Return False
	End Function

	Function ThreadInitializationName:String(ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.specialization Then Return ""
		Return ir.specialization.readableAbiName + "_thread_init"
	End Function

	Function ThreadInitializationFlagName:String(ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.specialization Then Return ""
		Return ir.specialization.readableAbiName + "_thread_initialized"
	End Function

	Function EmitThreadedStaticInitialization:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, debugScopeName:String)
		If Not HasThreadedStaticFields(ir) Then Return ""
		Local result:String
		If ir.baseSpecialization Then result :+ "void " + ir.baseSpecialization.readableAbiName + "_thread_init(void);~n"
		result :+ "void " + ThreadInitializationName(ir) + "(void) {~n"
		If ir.baseSpecialization Then result :+ "    " + ir.baseSpecialization.readableAbiName + "_thread_init();~n"
		result :+ "    if (" + ThreadInitializationFlagName(ir) + " == 0) {~n"
		result :+ "        " + ThreadInitializationFlagName(ir) + " = 1;~n"
		result :+ "        BBOBJECT bmx_initialization_exception = (BBOBJECT)&bbNullObject;~n"
		result :+ "        bbExTry {~n"
		result :+ "        case 0: {~n"
		If ir.specialization.debugInstrumentation Then result :+ "            bbOnDebugPushExState();~n"
		result :+ EmitStaticFieldInitializers(ir, diagnostics, "            ", True)
		result :+ "            " + ThreadInitializationFlagName(ir) + " = 2;~n"
		result :+ "            bbExLeave();~n"
		If ir.specialization.debugInstrumentation Then result :+ "            bbOnDebugPopExState();~n"
		result :+ "        } break;~n"
		result :+ "        case 1: {~n"
		If ir.specialization.debugInstrumentation Then result :+ "            bbOnDebugPopExState();~n"
		result :+ "            bmx_initialization_exception = bbExCatch();~n"
		result :+ "            " + ThreadInitializationFlagName(ir) + " = 0;~n"
		result :+ "            bbExThrow((BBObject *)bmx_initialization_exception);~n"
		result :+ "        } break;~n"
		result :+ "        }~n"
		result :+ "    }~n"
		Local reflectionDeclarationIndex:Int
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.declaringSpecialization <> ir.specialization Or Not TemplateDebugTypeTag(staticField.semanticType, ir).length Then Continue
			If staticField.isThreadedGlobal Then result :+ "    " + debugScopeName + ".decls[" + reflectionDeclarationIndex + "].var_address = (void *)&" + staticField.abiName + ";~n"
			reflectionDeclarationIndex :+ 1
		Next
		result :+ "}~n~n"
		Return result
	End Function

	Function EmitReferencedTypeRegistrations:String(ir:TCompilerGenericSpecializationIr, indent:String)
		If Not ir Or Not ir.specialization Then Return ""
		Local result:String
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If Not referenced Or referenced = ir.specialization Or referenced.IsAbiReferenceOnly() Then Continue
			If Not referenced.artifact Or Not referenced.artifact.identity Or referenced.artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE Then Continue
			result :+ indent + referenced.readableAbiName + "_register();~n"
		Next
		Return result
	End Function

	Function EmitStaticFieldInitializers:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, indent:String, threadedOnly:Int = False)
		If Not ir Then Return ""
		Local result:String
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.declaringSpecialization And staticField.declaringSpecialization <> ir.specialization Then Continue
			If threadedOnly And Not staticField.isThreadedGlobal Then Continue
			If staticField.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
				Local elementDefault:String = DefaultValue(staticField.semanticType.elementType, ir)
				Local fieldStruct:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(staticField.semanticType.elementType, ir)
				If fieldStruct And fieldStruct.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then
					elementDefault = fieldStruct.readableAbiName + "_New_ObjectNew()"
				Else If staticField.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT And staticField.semanticType.elementType.runtimeAbiName.length Then
					elementDefault = staticField.semanticType.elementType.runtimeAbiName + "_New_ObjectNew()"
				End If
				Local indexName:String = "bmx_static_" + TCompilerAbiNamer.Sanitize(staticField.name.ToLower()) + "_index"
				result :+ indent + "for (BBUINT " + indexName + " = 0; " + indexName + " < (BBUINT)" + staticField.semanticType.staticArrayLength + "; ++" + indexName + ") " + staticField.abiName + "[" + indexName + "] = " + elementDefault + ";~n"
			Else
				result :+ indent + staticField.abiName + " = " + FieldInitializerValue(staticField, ir, diagnostics) + ";~n"
			End If
		Next
		Return result
	End Function

	Function EmitConstructorBody:String(body:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr, diagnostics:String[] Var)
		If Not body Or body.kind <> TEMPLATE_NODE_BLOCK Then
			diagnostics :+ ["BMXC3023 generic Struct constructor body is not a bound template block"]
			Return ""
		End If
		Local temporaries:TMap = New TMap
		Local result:String = EmitArrayLiteralTemporaryDeclarations(body, temporaries, ir, "    ")
		For Local child:TGenericTemplateNode = EachIn body.children
			If child.kind = TEMPLATE_NODE_CONSTRUCTOR_DELEGATION Then Continue
			If child.kind = TEMPLATE_NODE_ASSIGNMENT And child.children.length = 2 And child.valueText = "=" Then
				If child.children[0].kind <> TEMPLATE_NODE_MEMBER Then
					diagnostics :+ ["BMXC3029 generic Struct constructor assignment target must be a direct field"]
					Continue
				End If
				result :+ "    " + EmitConstructorExpression(child.children[0], ir, constructor, diagnostics) + " = " + EmitConstructorExpression(child.children[1], ir, constructor, diagnostics) + ";~n"
			Else
				diagnostics :+ ["BMXC3029 generic Struct constructor contains unsupported bound node kind " + child.kind]
			End If
		Next
		Return result
	End Function

	Function EmitConstructorExpression:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr, diagnostics:String[] Var)
		If Not node Then Return "0"
		If node.kind = TEMPLATE_NODE_NAME Then
			For Local parameter:TGenericTemplateValueParameter = EachIn constructor.parameters
				If parameter.name.ToLower() = node.valueText.ToLower() Then
					Local result:String = StructConstructorParameterName(parameter.name)
					If parameter.passingMode = PARAMETER_PASS_VAR Then Return "(*" + result + ")"
					Return result
				End If
			Next
		End If
		If node.kind = TEMPLATE_NODE_MEMBER Then
			For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
				If irField.name.ToLower() = node.valueText.ToLower() Then Return "bmx_value." + irField.abiName
			Next
			diagnostics :+ ["BMXC3025 generic Struct constructor refers to unknown field '" + node.valueText + "'"]
			Return "0"
		End If
		Return EmitExpression(node, ir, constructor, diagnostics)
	End Function

	Function EmitStructConstructorCallArgument:String(argument:TGenericTemplateNode, parameter:TGenericTemplateValueParameter, ir:TCompilerGenericSpecializationIr, constructor:TCompilerGenericMethodIr, diagnostics:String[] Var)
		If Not parameter Or parameter.passingMode = PARAMETER_PASS_VALUE Then Return EmitConstructorExpression(argument, ir, constructor, diagnostics)
		If parameter.passingMode <> PARAMETER_PASS_VAR Then
			diagnostics :+ ["BMXC3070 generic Struct constructor call parameter has an unknown passing mode"]
			Return "0"
		End If
		If argument And argument.kind = TEMPLATE_NODE_CONVERSION And argument.children.length = 1 Then
			Local operand:TGenericTemplateNode = argument.children[0]
			If argument.valueText = CONVERSION_POINTER_TO_VAR_REFERENCE And operand.kind = TEMPLATE_NODE_NAME Then
				Return StructConstructorParameterName(operand.valueText)
			End If
			If argument.valueText = CONVERSION_VAR_REFERENCE Then Return "(&(" + EmitConstructorExpression(operand, ir, constructor, diagnostics) + "))"
		End If
		diagnostics :+ ["BMXC3070 generic Struct constructor Var argument requires a retained addressable reference conversion"]
		Return "0"
	End Function

	Function StructConstructorParameterName:String(name:String)
		Return "bmx_ctor_" + TCompilerAbiNamer.Sanitize(name)
	End Function

	Function EmitOwnedInterfaceTable:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local abiName:String = ir.specialization.readableAbiName
		Local vdefName:String = abiName + "_interface_vdef"
		Local result:String
		For Local runtimeInterface:TTemplateTypeReference = EachIn ir.implementedRuntimeInterfaces
			If runtimeInterface.runtimeAbiName.ToLower() = "brl_blitz_icloseable" Then
				result :+ "extern const struct BBInterface brl_blitz_ICloseable_ifc;~n"
			End If
		Next
		For Local index:Int = 0 Until ir.implementedRuntimeInterfaces.length
			result :+ "struct " + vdefName + "_runtime_methods_" + index + " { void (*m_Close)(BBOBJECT); };~n"
		Next
		result :+ "struct " + vdefName + " {~n"
		For Local index:Int = 0 Until ir.implementedInterfaces.length
			Local interfaceNode:TGenericSpecializationNode = ir.implementedInterfaces[index]
			result :+ "    struct " + interfaceNode.readableAbiName + "_methods interface_" + index + ";~n"
		Next
		For Local index:Int = 0 Until ir.implementedRuntimeInterfaces.length
			Local runtimeInterface:TTemplateTypeReference = ir.implementedRuntimeInterfaces[index]
			result :+ "    struct " + vdefName + "_runtime_methods_" + index + " runtime_interface_" + index + ";~n"
		Next
		result :+ "};~n"
		result :+ "static struct BBInterfaceOffsets " + abiName + "_interface_offsets[] = {~n"
		For Local index:Int = 0 Until ir.implementedInterfaces.length
			Local interfaceNode:TGenericSpecializationNode = ir.implementedInterfaces[index]
			result :+ "    { (BBINTERFACE)&" + interfaceNode.readableAbiName + "_ifc, offsetof(struct " + vdefName + ", interface_" + index + ") },~n"
		Next
		For Local index:Int = 0 Until ir.implementedRuntimeInterfaces.length
			Local runtimeInterface:TTemplateTypeReference = ir.implementedRuntimeInterfaces[index]
			result :+ "    { (BBINTERFACE)&" + runtimeInterface.runtimeAbiName + "_ifc, offsetof(struct " + vdefName + ", runtime_interface_" + index + ") },~n"
		Next
		result :+ "};~n"
		result :+ "static struct " + vdefName + " " + abiName + "_interface_vtable = {~n"
		For Local interfaceNode:TGenericSpecializationNode = EachIn ir.implementedInterfaces
			Local requirements:TCompilerGenericMethodIr[] = TCompilerGenericSpecializationLowerer.EffectiveInterfaceMethods(interfaceNode, ir, diagnostics)
			result :+ "    { "
			If Not requirements.length Then result :+ "0"
			For Local index:Int = 0 Until requirements.length
				If index Then result :+ ", "
				Local requirement:TCompilerGenericMethodIr = requirements[index]
				Local implementation:TCompilerGenericMethodIr
				For Local candidate:TCompilerGenericMethodIr = EachIn ir.methods
					If TCompilerGenericSpecializationLowerer.ImplementationMatchesRequirement(candidate, requirement, ir) Then implementation = candidate; Exit
				Next
				If implementation Then
					Local parameters:String = "BBOBJECT"
					For Local parameter:TGenericTemplateValueParameter = EachIn requirement.parameters
						parameters :+ ", " + CValueDeclaration(parameter.semanticType, "", ir, parameter.passingMode)
					Next
					result :+ "(" + CFunctionPointerDeclaration(requirement.returnType, "", parameters, ir) + ")" + implementation.abiName
				Else If requirement.interfaceMethodKind = TEMPLATE_INTERFACE_METHOD_DEFAULT Then
					Local parameters:String = "BBOBJECT"
					For Local parameter:TGenericTemplateValueParameter = EachIn requirement.parameters
						parameters :+ ", " + CValueDeclaration(parameter.semanticType, "", ir, parameter.passingMode)
					Next
					result :+ "(" + CFunctionPointerDeclaration(requirement.returnType, "", parameters, ir) + ")" + requirement.abiName
				Else
					result :+ "0"
				End If
			Next
			result :+ " },~n"
		Next
		For Local runtimeInterface:TTemplateTypeReference = EachIn ir.implementedRuntimeInterfaces
			If runtimeInterface.runtimeAbiName.ToLower() = "brl_blitz_icloseable" Then
				Local implementation:TCompilerGenericMethodIr
				For Local candidate:TCompilerGenericMethodIr = EachIn ir.methods
					If candidate.name.ToLower() = "close" And candidate.parameters.length = 0 Then implementation = candidate; Exit
				Next
				If implementation Then
					result :+ "    { (void (*)(BBOBJECT))" + implementation.abiName + " },~n"
				Else
					diagnostics :+ ["BMXC3017 generic Type '" + ir.specialization.artifact.identity.qualifiedName + "' does not implement ICloseable.Close"]
					result :+ "    { 0 },~n"
				End If
			Else
				diagnostics :+ ["BMXC3017 generic Type runtime Interface table emission is not implemented for '" + runtimeInterface.runtimeAbiName + "'"]
				result :+ "    { 0 },~n"
			End If
		Next
		result :+ "};~n"
		result :+ "static struct BBInterfaceTable " + abiName + "_itable = { " + abiName + "_interface_offsets, &" + abiName + "_interface_vtable, " + (ir.implementedInterfaces.length + ir.implementedRuntimeInterfaces.length) + " };~n~n"
		Return result
	End Function

	Function EmitInterfaceImplementationUnit:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, declarationText:String = "")
		Local abiName:String = ir.specialization.readableAbiName
		Local result:String = "#include <brl.mod/blitz.mod/blitz.h>~n" + DefiningModuleHeaderInclude(ir) + RuntimeArgumentHeaderIncludes(ir) + "~n" + ClosureRuntimeDeclaration()
		' Closed Interface signatures can mention application-local ordinary Types.
		' Give those tags file scope before the method table and inline call helpers;
		' otherwise C gives a tag first seen in a parameter list prototype scope.
		Local runtimeDeclarationText:String = EmitOrdinaryRuntimeTypeDeclarationsForMembers(ir, diagnostics)
		If runtimeDeclarationText.length Then result :+ runtimeDeclarationText + "~n"
		If Not declarationText.length Then declarationText = EmitInterfaceDeclarations(ir, diagnostics)
		result :+ declarationText + "~n"
		For Local parent:TGenericSpecializationNode = EachIn ir.inheritedInterfaces
			result :+ EmitReferencedInterfaceDeclarations(parent, ir, diagnostics) + "~n"
		Next
		Local ordinaryDeclarations:TMap = New TMap
		Local ordinaryDeclarationText:String
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If irMethod.interfaceMethodKind = TEMPLATE_INTERFACE_METHOD_DEFAULT And irMethod.declaringSpecialization = ir.specialization Then ordinaryDeclarationText :+ EmitReferencedCallDeclarations(irMethod.body, ir, ordinaryDeclarations, diagnostics)
		Next
		If ordinaryDeclarationText.length Then result :+ ordinaryDeclarationText + "~n"
		result :+ EmitGenericDataSupport(ir, diagnostics)
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If irMethod.interfaceMethodKind <> TEMPLATE_INTERFACE_METHOD_DEFAULT Or irMethod.declaringSpecialization <> ir.specialization Then Continue
			result :+ EmitLocalRoutineSupport(irMethod, irMethod.body, ir, diagnostics)
			Local parameters:String = "BBOBJECT self"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				parameters :+ ", " + CValueDeclaration(parameter.semanticType, TCompilerAbiNamer.Sanitize(parameter.name), ir, parameter.passingMode)
			Next
			result :+ EmitGenericGdbLineDirective(irMethod.source, ir, "") + CFunctionDeclaration(irMethod.returnType, irMethod.abiName, parameters, ir) + " {~n    (void)self;~n"
			For Local parameter:TGenericTemplateValueParameter = EachIn irMethod.parameters
				result :+ "    (void)" + TCompilerAbiNamer.Sanitize(parameter.name) + ";~n"
			Next
			result :+ EmitBody(irMethod.body, ir, irMethod, diagnostics)
			result :+ "}~n~n"
		Next
		For Local parent:TGenericSpecializationNode = EachIn ir.inheritedInterfaces
			result :+ "void " + parent.readableAbiName + "_register(void);~n"
		Next
		If ir.inheritedInterfaces.length Then result :+ "~n"
		result :+ EmitGenericCoverageCatalog(ir)
		result :+ EmitGenericCoverageRegistration(ir)
		result :+ "static struct {~n"
		result :+ "    unsigned int kind;~n"
		result :+ "    const char *name;~n"
		result :+ "    BBDebugDecl decls[1];~n"
		result :+ "} " + abiName + "_ifc_debug_scope = {~n"
		result :+ "    BBDEBUGSCOPE_USERTYPE, ~q" + SpecializationDisplayName(ir.specialization) + "~q,~n"
		result :+ "    {{ BBDEBUGDECL_END, 0, 0, .var_address = 0, .reflection_wrapper = 0 }}~n"
		result :+ "};~n"
		result :+ "static BBClass " + abiName + "_ifc_class = {~n"
		result :+ "    .super = &bbObjectClass, .free = bbObjectFree, .debug_scope = (BBDebugScope *)&" + abiName + "_ifc_debug_scope, .instance_size = sizeof(BBObject),~n"
		result :+ "    .ctor = bbObjectCtor, .dtor = bbObjectDtor, .ToString = bbObjectToString, .Compare = bbObjectCompare,~n"
		result :+ "    .SendMessage = bbObjectSendMessage, .HashCode = bbObjectHashCode, .Equals = bbObjectEquals, .fields_offset = sizeof(void *)~n};~n"
		result :+ "const struct BBInterface " + abiName + "_ifc = { &" + abiName + "_ifc_class, ~q" + ir.specialization.artifact.identity.qualifiedName + "~q };~n~n"
		result :+ "void " + abiName + "_register(void) {~n"
		result :+ "    static int registered = 0;~n"
		result :+ "    if (!registered) {~n"
		result :+ "        registered = 1;~n"
		For Local parent:TGenericSpecializationNode = EachIn ir.inheritedInterfaces
			result :+ "        " + parent.readableAbiName + "_register();~n"
		Next
		result :+ "        bbObjectRegisterInterface((BBInterface *)&" + abiName + "_ifc);~n"
		result :+ "    }~n"
		result :+ "}~n"
		Return result
	End Function

	Function HasManagedFields:Int(ir:TCompilerGenericSpecializationIr)
		For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
			If irField.semanticType And irField.semanticType.kind = TEMPLATE_TYPE_ARRAY Then Return True
			If irField.semanticType And irField.semanticType.kind = TEMPLATE_TYPE_NAMED Then
				If irField.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS Or irField.semanticType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Or TCompilerGenericSpecializationLowerer.ReferencedSpecialization(irField.semanticType, ir) Then Return True
			End If
			If irField.semanticType And irField.semanticType.kind = TEMPLATE_TYPE_BUILTIN Then
				Local name:String = irField.semanticType.symbolName.ToLower()
				If name = "string" Or name = "object" Then Return True
			End If
		Next
		Return False
	End Function

	Function GenericDataDefinitions:TGenericTemplateNode[](ir:TCompilerGenericSpecializationIr)
		Local result:TGenericTemplateNode[]
		Local seen:TMap = New TMap
		If ir.routine Then CollectGenericDataDefinitions(ir.routine.body, result, seen)
		For Local constructor:TCompilerGenericMethodIr = EachIn ir.constructors
			If Not constructor.declaringSpecialization Or constructor.declaringSpecialization = ir.specialization Then CollectGenericDataDefinitions(constructor.body, result, seen)
		Next
		For Local irMethod:TCompilerGenericMethodIr = EachIn ir.methods
			If Not irMethod.declaringSpecialization Or irMethod.declaringSpecialization = ir.specialization Then CollectGenericDataDefinitions(irMethod.body, result, seen)
		Next
		For Local index:Int = 1 Until result.length
			Local value:TGenericTemplateNode = result[index]
			Local position:Int = index - 1
			While position >= 0 And GenericDataSourceKey(result[position]) > GenericDataSourceKey(value)
				result[position + 1] = result[position]
				position :- 1
			Wend
			result[position + 1] = value
		Next
		Return result
	End Function

	Function CollectGenericDataDefinitions(node:TGenericTemplateNode, result:TGenericTemplateNode[] Var, seen:TMap)
		If Not node Then Return
		If node.kind = TEMPLATE_NODE_DATA And node.identity = "define" Then
			Local key:String = GenericDataSourceKey(node)
			If Not seen.Contains(key) Then result :+ [node]; seen.Insert(key, node)
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectGenericDataDefinitions(child, result, seen)
		Next
	End Function

	Function GenericDataSourceKey:String(node:TGenericTemplateNode)
		If Not node Or Not node.source Then Return node.valueText
		Local offset:String = String(node.source.start)
		While offset.length < 16
			offset = "0" + offset
		Wend
		Return node.source.path.ToLower() + ":" + offset
	End Function

	Function GenericDataDefinitionIndex:Int(ir:TCompilerGenericSpecializationIr, identity:String)
		Local itemIndex:Int
		For Local definition:TGenericTemplateNode = EachIn GenericDataDefinitions(ir)
			If definition.valueText = identity Then Return itemIndex
			itemIndex :+ definition.children.length
		Next
		Return -1
	End Function

	Function EmitGenericDataSupport:String(ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		Local definitions:TGenericTemplateNode[] = GenericDataDefinitions(ir)
		If Not definitions.length Then Return ""
		Local itemCount:Int
		For Local definition:TGenericTemplateNode = EachIn definitions
			itemCount :+ definition.children.length
		Next
		Local prefix:String = ir.specialization.readableAbiName + "_data"
		Local storageCount:Int = itemCount
		If storageCount < 1 Then storageCount = 1
		Local result:String = "static struct bbDataDef " + prefix + "_items[" + storageCount + "];~n"
		result :+ "static struct bbDataDef *" + prefix + "_offset = " + prefix + "_items;~n"
		result :+ "static const BBSIZET " + prefix + "_count = " + itemCount + ";~n"
		result :+ "static void " + prefix + "_ensure(void) {~n"
		result :+ "    static volatile int initialization_state = 0;~n"
		result :+ "    if (!bbAtomicCAS(&initialization_state, 0, 1)) {~n"
		result :+ "        while (!bbAtomicCAS(&initialization_state, 2, 2)) {}~n"
		result :+ "        return;~n"
		result :+ "    }~n"
		result :+ "    GC_add_roots(" + prefix + "_items, " + prefix + "_items + " + storageCount + ");~n"
		Local itemIndex:Int
		For Local definition:TGenericTemplateNode = EachIn definitions
			For Local value:TGenericTemplateNode = EachIn definition.children
				Local typeName:String = GenericDataValueTypeName(value.semanticType)
				Local tag:String = GenericDataTypeTag(typeName)
				Local unionField:String = GenericDataUnionField(typeName)
				If Not tag.length Or Not unionField.length Then
					diagnostics :+ ["BMXC3075 generic DefData value type '" + typeName + "' has no runtime representation"]
					Continue
				End If
				result :+ "    " + prefix + "_items[" + itemIndex + "].type = (char *)~q" + tag + "~q;~n"
				result :+ "    " + prefix + "_items[" + itemIndex + "]." + unionField + " = " + EmitExpression(value, ir, Null, diagnostics, New TMap) + ";~n"
				itemIndex :+ 1
			Next
		Next
		result :+ "    bbAtomicCAS(&initialization_state, 1, 2);~n"
		result :+ "}~n~n"
		Return result
	End Function

	Function GenericDataValueTypeName:String(value:TTemplateTypeReference)
		If Not value Then Return ""
		If value.kind = TEMPLATE_TYPE_BUILTIN Then Return value.symbolName.ToLower()
		If value.kind = TEMPLATE_TYPE_NAMED And value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return value.runtimeValueType.ToLower()
		Return ""
	End Function

	Function GenericDataTypeTag:String(value:String)
		Select value
			Case "byte" Return "b"
			Case "short" Return "s"
			Case "int" Return "i"
			Case "uint" Return "u"
			Case "long" Return "l"
			Case "ulong" Return "y"
			Case "size_t" Return "z"
			Case "longint" Return "v"
			Case "ulongint" Return "e"
			Case "float" Return "f"
			Case "double" Return "d"
			Case "string" Return "$"
		End Select
		Return ""
	End Function

	Function GenericDataUnionField:String(value:String)
		Select value
			Case "byte" Return "b"
			Case "short" Return "s"
			Case "int" Return "i"
			Case "uint" Return "u"
			Case "long" Return "l"
			Case "ulong" Return "y"
			Case "size_t" Return "z"
			Case "longint" Return "v"
			Case "ulongint" Return "e"
			Case "float" Return "f"
			Case "double" Return "d"
			Case "string" Return "t"
		End Select
		Return ""
	End Function

	Function CollectGenericDebugLocals(node:TGenericTemplateNode, declarations:TGenericTemplateNode[] Var, seen:TMap)
		If Not node Then Return
		' A nested literal owns a separate debugger frame and lexical scope.
		If node.kind = TEMPLATE_NODE_FUNCTION_LITERAL Then Return
		If node.kind = TEMPLATE_NODE_DECLARATION Then
			Local key:String = node.valueText.ToLower() + ":" + SourceIdentity(node)
			If Not seen.Contains(key) Then
				seen.Insert(key, node)
				declarations :+ [node]
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			CollectGenericDebugLocals(child, declarations, seen)
		Next
	End Function

	Function GenericDebugTypeTag:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not value Then Return "?"
		Select value.kind
			Case TEMPLATE_TYPE_POINTER
				Local pointerElementTag:String = GenericDebugTypeTag(value.elementType, ir)
				If pointerElementTag = "?" Then Return "?"
				Return "*" + pointerElementTag
			Case TEMPLATE_TYPE_ARRAY
				Local elementTag:String = GenericDebugTypeTag(value.elementType, ir)
				If elementTag = "?" Then Return "?"
				Local rankTag:String = "["
				For Local rankIndex:Int = 1 Until value.rank
					rankTag :+ ","
				Next
				Return rankTag + "]" + elementTag
			Case TEMPLATE_TYPE_STATIC_ARRAY
				Local elementTag:String = GenericDebugTypeTag(value.elementType, ir)
				If elementTag = "?" Then Return "?"
				Return "[" + value.staticArrayLength + "]" + elementTag
			Case TEMPLATE_TYPE_CALLABLE
				Local callableTag:String = "("
				For Local callableIndex:Int = 0 Until value.arguments.length
					If callableIndex Then callableTag :+ ","
					If callableIndex < value.callableParameterModes.length And value.callableParameterModes[callableIndex] = PARAMETER_PASS_VAR Then callableTag :+ "&"
					Local callableParameterTag:String = GenericDebugTypeTag(value.arguments[callableIndex], ir)
					If callableParameterTag = "?" Then Return "?"
					callableTag :+ callableParameterTag
				Next
				callableTag :+ ")"
				If value.elementType And Not VoidType(value.elementType) Then
					Local callableReturnTag:String = GenericDebugTypeTag(value.elementType, ir)
					If callableReturnTag = "?" Then Return "?"
					callableTag :+ callableReturnTag
				End If
				Return callableTag
			Case TEMPLATE_TYPE_CLOSURE
				Local result:String = "!("
				For Local index:Int = 0 Until value.arguments.length
					If index Then result :+ ","
					If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then result :+ "&"
					Local parameterTag:String = GenericDebugTypeTag(value.arguments[index], ir)
					If parameterTag = "?" Then Return "?"
					result :+ parameterTag
				Next
				result :+ ")"
				If value.elementType And Not VoidType(value.elementType) Then
					Local returnTag:String = GenericDebugTypeTag(value.elementType, ir)
					If returnTag = "?" Then Return "?"
					result :+ returnTag
				End If
				Return result
			Case TEMPLATE_TYPE_NAMED
				If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then Return "@" + value.CanonicalName()
				If value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then Return "*#" + value.CanonicalName()
				If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return "/" + value.CanonicalName()
				Return ":" + value.CanonicalName()
		End Select
		If value.kind = TEMPLATE_TYPE_BUILTIN Then
			Select value.symbolName.ToLower()
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
		End If
		Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
		If referenced Then
			If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then Return "@" + referenced.artifact.identity.qualifiedName
			If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then Return "*#" + referenced.artifact.identity.qualifiedName
			Return ":" + referenced.artifact.identity.qualifiedName
		End If
		Return "?"
	End Function

	Function CheckedGenericDebugTypeTag:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr, variableName:String, diagnostics:String[] Var)
		Local tag:String = GenericDebugTypeTag(value, ir)
		If tag <> "?" Then Return tag
		diagnostics :+ ["BMXC2084 Debug variable '" + variableName + "' has no complete typetag in generic specialization '" + ir.specialization.key.CanonicalName() + "'"]
		Return ""
	End Function

	Function EmitGenericDebugFunctionScope:String(body:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, declarations:TGenericTemplateNode[] Var, indent:String, diagnostics:String[] Var)
		If Not ir Or Not ir.specialization Or Not ir.specialization.debugInstrumentation Or Not ownerMethod Then Return ""
		CollectGenericDebugLocals(body, declarations, New TMap)
		Local debugNames:TMap = New TMap
		Local additionalCaptures:TCompilerGenericClosureCaptureIr[]
		For Local parameter:TGenericTemplateValueParameter = EachIn ownerMethod.parameters
			debugNames.Insert(parameter.name.ToLower(), parameter)
		Next
		For Local declaration:TGenericTemplateNode = EachIn declarations
			debugNames.Insert(declaration.valueText.ToLower(), declaration)
		Next
		If ownerMethod.receiverType And Not ownerMethod.isStatic And Not ownerMethod.isTypeFunction Then debugNames.Insert("self", ownerMethod)
		For Local capture:TCompilerGenericClosureCaptureIr = EachIn ownerMethod.closureCaptures
			Local debugCapture:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(ownerMethod, capture.name)
			If Not debugCapture Or debugNames.Contains(debugCapture.name.ToLower()) Then Continue
			If Not ClosureCaptureExpression(ownerMethod, debugCapture).length Then Continue
			debugNames.Insert(debugCapture.name.ToLower(), debugCapture)
			additionalCaptures :+ [debugCapture]
		Next
		Local declarationCount:Int = declarations.length + ownerMethod.parameters.length + additionalCaptures.length
		If ownerMethod.receiverType And Not ownerMethod.isStatic And Not ownerMethod.isTypeFunction Then declarationCount :+ 1
		Local result:TStringBuilder = New TStringBuilder(2048)
		For Local declaration:TGenericTemplateNode = EachIn declarations
			If ClosureCaptureForName(ownerMethod, declaration.valueText) Then Continue
			Local name:String = GenericLocalName(declaration, ir)
			If declaration.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
				result.Append(indent + CStorageDeclaration(declaration.semanticType, name, ir) + " = {0};~n")
			Else
				result.Append(indent + CValueDeclaration(declaration.semanticType, name, ir) + " = " + DefaultValue(declaration.semanticType, ir) + ";~n")
			End If
		Next
		result.Append(indent + "struct { unsigned int kind; const char *name; BBDebugDecl decls[" + (declarationCount + 1) + "]; } bmx_generic_debug_scope = {~n")
		Local scopeName:String = ownerMethod.debugName
		If Not scopeName.length Then scopeName = ownerMethod.name
		result.Append(indent + "    BBDEBUGSCOPE_FUNCTION, " + CQuoted(scopeName) + ", {~n")
		If ownerMethod.receiverType And Not ownerMethod.isStatic And Not ownerMethod.isTypeFunction Then
			Local receiverAddress:String = "&self"
			If ownerMethod.receiverIsStruct Then receiverAddress = "self"
			Local receiverTag:String = CheckedGenericDebugTypeTag(ownerMethod.receiverType, ir, "Self", diagnostics)
			If receiverTag.length Then result.Append(indent + "        { BBDEBUGDECL_LOCAL, ~qSelf~q, ~q" + receiverTag + "~q, .var_address = " + receiverAddress + ", .reflection_wrapper = 0 },~n")
		End If
		For Local parameter:TGenericTemplateValueParameter = EachIn ownerMethod.parameters
			Local kind:String = "BBDEBUGDECL_LOCAL"
			Local tag:String = CheckedGenericDebugTypeTag(parameter.semanticType, ir, parameter.name, diagnostics)
			If Not tag.length Then Continue
			If parameter.passingMode = PARAMETER_PASS_VAR Then kind = "BBDEBUGDECL_VARPARAM"; tag = "&" + tag
			Local parameterAddress:String = "&" + TCompilerAbiNamer.Sanitize(parameter.name)
			Local capture:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(ownerMethod, parameter.name)
			If capture Then parameterAddress = "&" + ClosureCaptureExpression(ownerMethod, capture)
			result.Append(indent + "        { " + kind + ", " + CQuoted(parameter.name) + ", " + CQuoted(tag) + ", .var_address = " + parameterAddress + ", .reflection_wrapper = 0 },~n")
		Next
		For Local declaration:TGenericTemplateNode = EachIn declarations
			Local localAddress:String = "&" + GenericLocalName(declaration, ir)
			Local capture:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(ownerMethod, declaration.valueText)
			If capture Then localAddress = "&" + ClosureCaptureExpression(ownerMethod, capture)
			Local tag:String = CheckedGenericDebugTypeTag(declaration.semanticType, ir, declaration.valueText, diagnostics)
			If tag.length Then result.Append(indent + "        { BBDEBUGDECL_LOCAL, " + CQuoted(declaration.valueText) + ", " + CQuoted(tag) + ", .var_address = " + localAddress + ", .reflection_wrapper = 0 },~n")
		Next
		For Local capture:TCompilerGenericClosureCaptureIr = EachIn additionalCaptures
			Local tag:String = CheckedGenericDebugTypeTag(capture.semanticType, ir, capture.name, diagnostics)
			If tag.length Then result.Append(indent + "        { BBDEBUGDECL_LOCAL, " + CQuoted(capture.name) + ", " + CQuoted(tag) + ", .var_address = &" + ClosureCaptureExpression(ownerMethod, capture) + ", .reflection_wrapper = 0 },~n")
		Next
		result.Append(indent + "        { BBDEBUGDECL_END, 0, 0, .var_address = 0, .reflection_wrapper = 0 }~n")
		result.Append(indent + "    }~n" + indent + "};~n")
		result.Append(indent + "bbOnDebugEnterScope((BBDebugScope *)&bmx_generic_debug_scope);~n")
		Return result.ToString()
	End Function

	Function EmitGenericDebugLeave:String(ir:TCompilerGenericSpecializationIr, indent:String)
		If ir And ir.specialization And ir.specialization.debugInstrumentation Then Return indent + "bbOnDebugLeaveScope();~n"
		Return ""
	End Function

	Function EmitBody:String(body:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var)
		If Not body Or body.kind <> TEMPLATE_NODE_BLOCK Then
			diagnostics :+ ["BMXC3023 specialization method body is not a bound template block"]
			If VoidType(ownerMethod.returnType) Then Return "    return;~n"
			Return "    return " + DefaultValue(ownerMethod.returnType, ir) + ";~n"
		End If
		Local locals:TMap = New TMap
		Local arrayTemporaries:TMap = New TMap
		Local debugLocals:TGenericTemplateNode[]
		Local result:String = EmitGenericGdbLineDirective(ownerMethod.source, ir, "    ") + EmitArrayLiteralTemporaryDeclarations(body, arrayTemporaries, ir, "    ")
		result :+ EmitGenericCoverageFunctionEntry(ir, ownerMethod, "    ")
		If ownerMethod.isClosureInvoke And ownerMethod.incomingClosureEnvironment Then
			For Local routineCapture:TCompilerGenericClosureCaptureIr = EachIn ownerMethod.closureCaptures
				Local capture:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(ownerMethod, routineCapture.name)
				If capture Then locals.Insert(capture.name.ToLower(), ClosureCaptureExpression(ownerMethod, capture))
			Next
		End If
		If ownerMethod.closureEnvironment Then
			Local environment:TCompilerGenericClosureEnvironmentIr = ownerMethod.closureEnvironment
			result :+ "    struct " + environment.abiName + "_obj *" + environment.localName + " = " + environment.abiName + "_new();~n"
			If environment.parent Then result :+ "    " + environment.localName + "->" + environment.parentFieldName + " = environment;~n"
			For Local capture:TCompilerGenericClosureCaptureIr = EachIn environment.captures
				Local fieldExpression:String = ClosureEnvironmentField(environment, capture)
				locals.Insert(capture.name.ToLower(), fieldExpression)
				If capture.isSelf Then
					If Not ownerMethod.receiverType Then diagnostics :+ ["BMXC1243 generic Closure Self capture requires an instance method receiver"] Else result :+ "    " + fieldExpression + " = self;~n"
				Else If capture.isParameter Then
					result :+ "    " + fieldExpression + " = " + TCompilerAbiNamer.Sanitize(capture.name) + ";~n"
				End If
			Next
		End If
		result :+ EmitGenericDebugFunctionScope(body, ir, ownerMethod, debugLocals, "    ", diagnostics)
		result :+ EmitSequentialBlock(body, ir, ownerMethod, diagnostics, locals, "    ")
		result :+ EmitGenericGdbGeneratedLineReset(ir, "    ")
		' BlitzMax value routines return the declared type's default when
		' control reaches End Method/Function. Retain that boundary when the
		' top-level body can fall through; relying on C fallthrough leaves a
		' managed value as undefined state. A final explicit Return/Throw needs
		' no redundant epilogue.
		If Not VoidType(ownerMethod.returnType) And BodyRequiresImplicitReturn(body) Then
			result :+ EmitGenericDebugLeave(ir, "    ") + "    return " + DefaultValue(ownerMethod.returnType, ir) + ";~n"
		Else If VoidType(ownerMethod.returnType) And BodyRequiresImplicitReturn(body) Then
			result :+ EmitGenericDebugLeave(ir, "    ") + "    return;~n"
		Else If Not result.length Then
			result = "    return;~n"
		End If
		Return result
	End Function

	Function EmitArrayLiteralTemporaryDeclarations:String(node:TGenericTemplateNode, emitted:TMap, ir:TCompilerGenericSpecializationIr, indent:String)
		If Not node Then Return ""
		Local result:String
		If node.kind = TEMPLATE_NODE_ARRAY_LITERAL Then
			Local name:String = ArrayLiteralTemporaryName(node)
			If Not emitted.Contains(name) Then
				result :+ indent + "BBARRAY " + name + " = &bbEmptyArray;~n"
				emitted.Insert(name, node)
			End If
		End If
		If (node.kind = TEMPLATE_NODE_ARRAY_SLICE Or node.kind = TEMPLATE_NODE_ARRAY_ELEMENT) And node.identity.StartsWith("materialized-receiver") Then
			Local receiverName:String = ArrayReceiverTemporaryName(node)
			If Not emitted.Contains(receiverName) Then
				result :+ indent + "BBARRAY " + receiverName + " = &bbEmptyArray;~n"
				emitted.Insert(receiverName, node)
			End If
		End If
		If node.kind = TEMPLATE_NODE_CALL And node.identity.Contains("materialized-receiver:") And node.children.length And node.children[0].semanticType Then
			Local callReceiverName:String = CallReceiverTemporaryName(node)
			If Not emitted.Contains(callReceiverName) Then
				Local callReceiverType:String = CType(node.children[0].semanticType, ir)
				If callReceiverType.length Then
					result :+ indent + callReceiverType + " " + callReceiverName + " = " + DefaultValue(node.children[0].semanticType, ir) + ";~n"
					emitted.Insert(callReceiverName, node)
				End If
			End If
		End If
		For Local child:TGenericTemplateNode = EachIn node.children
			result :+ EmitArrayLiteralTemporaryDeclarations(child, emitted, ir, indent)
		Next
		Return result
	End Function

	Function ArrayLiteralTemporaryName:String(node:TGenericTemplateNode)
		Local identity:String = node.identity
		If Not identity.length Then identity = SourceIdentity(node)
		Return "bmx_array_" + TCompilerAbiNamer.Sanitize(identity)
	End Function

	Function ArrayReceiverTemporaryName:String(node:TGenericTemplateNode)
		Local identity:String = node.identity
		If Not identity.length Then identity = SourceIdentity(node)
		Return "bmx_array_receiver_" + TCompilerAbiNamer.Sanitize(identity)
	End Function

	Function CallReceiverTemporaryName:String(node:TGenericTemplateNode)
		Local identity:String = node.identity
		If Not identity.length Then identity = SourceIdentity(node)
		Return "bmx_call_receiver_" + TCompilerAbiNamer.Sanitize(identity)
	End Function

	Function BodyRequiresImplicitReturn:Int(body:TGenericTemplateNode)
		If Not body Or Not body.children.length Then Return True
		Local last:TGenericTemplateNode = body.children[body.children.length - 1]
		Return last.kind <> TEMPLATE_NODE_RETURN And last.kind <> TEMPLATE_NODE_THROW
	End Function

	Function VoidType:Int(value:TTemplateTypeReference)
		Return value And value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "void"
	End Function

	Function EmitSequentialBlock:String(body:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not body Or body.kind <> TEMPLATE_NODE_BLOCK Then
			diagnostics :+ ["BMXC3050 generic branch body is not a bound template block"]
			Return ""
		End If
		Local result:String
		Local coverageMarked:Int
		For Local child:TGenericTemplateNode = EachIn body.children
			If child.kind <> TEMPLATE_NODE_BLOCK Then
				result :+ EmitGenericGdbLineDirective(child.source, ir, indent) + EmitGenericDebugStatement(child, ir, indent)
				If body.valueText <> "local-declarations" Or Not coverageMarked Then
					Local coverageProbe:String = EmitGenericCoverageStatement(ir, child, indent)
					result :+ coverageProbe
					If coverageProbe.length Then coverageMarked = True
				End If
			End If
			Select child.kind
				Case TEMPLATE_NODE_BLOCK
					If child.valueText <> "local-declarations" And child.valueText <> "conditional-active" Then
						diagnostics :+ ["BMXC3049 generic sequential body contains an unexpected nested block"]
						Continue
					End If
					' Multiple declarators share their surrounding lexical scope and
					' are emitted in source order, so a later initializer can use an
					' earlier declarator without introducing a synthetic C scope.
					result :+ EmitSequentialBlock(child, ir, ownerMethod, diagnostics, locals, indent)
				Case TEMPLATE_NODE_DECLARATION
					Local localType:String = CType(child.semanticType, ir)
					Local localKey:String = child.valueText.ToLower()
					If Not localType.length Or (Not TCompilerGenericSpecializationLowerer.SupportedType(child.semanticType, ir) And Not TCompilerGenericSpecializationLowerer.SupportedStaticArrayType(child.semanticType, ir)) Then
						diagnostics :+ ["BMXC3049 generic local '" + child.valueText + "' has no supported closed value ABI"]
						Continue
					End If
					Local activeLocal:String
					If locals.Contains(localKey) Then activeLocal = String(locals.ValueForKey(localKey))
					If ownerMethod.isIteratorRoutine Then
						If Not activeLocal.length Then activeLocal = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(child)
						If child.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
							If child.children.length Then
								diagnostics :+ ["BMXC3049 generic StaticArray local '" + child.valueText + "' cannot have an aggregate initializer"]
								Continue
							End If
							result :+ EmitGenericStaticArrayInitialization(child.semanticType, activeLocal, ir, indent)
							locals.Insert(localKey, activeLocal)
							Continue
						End If
						Local iteratorInitializer:String = DefaultValue(child.semanticType, ir)
						If child.children.length = 1 Then iteratorInitializer = EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals)
						result :+ indent + activeLocal + " = " + iteratorInitializer + ";~n"
						locals.Insert(localKey, activeLocal)
						Continue
					End If
					If activeLocal.StartsWith("bmx_closure_environment_") Then
						Local loopInitializer:String = DefaultValue(child.semanticType, ir)
						If child.children.length = 1 Then loopInitializer = EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals)
						result :+ indent + activeLocal + " = " + loopInitializer + ";~n"
						Continue
					End If
					Local capture:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(ownerMethod, child.valueText)
					If capture And ownerMethod.closureEnvironment And ownerMethod.closureEnvironment.capturesByName.ValueForKey(child.valueText.ToLower()) = capture And Not capture.isParameter Then
						Local initializer:String = DefaultValue(child.semanticType, ir)
						If child.children.length = 1 Then initializer = EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals)
						result :+ indent + ClosureCaptureExpression(ownerMethod, capture) + " = " + initializer + ";~n"
						Continue
					End If
					If locals.Contains(localKey) Then
						diagnostics :+ ["BMXC3049 generic local '" + child.valueText + "' is declared more than once in one specialization scope"]
						Continue
					End If
					Local localName:String = GenericLocalName(child, ir)
					If child.semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
						If child.children.length Then
							diagnostics :+ ["BMXC3049 generic StaticArray local '" + child.valueText + "' cannot have an aggregate initializer"]
							Continue
						End If
						If Not ir.specialization.debugInstrumentation Then result :+ indent + CStorageDeclaration(child.semanticType, localName, ir) + " = {0};~n"
						Local staticStruct:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(child.semanticType.elementType, ir)
						Local staticInitializer:String
						If staticStruct And staticStruct.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then
							staticInitializer = staticStruct.readableAbiName + "_New_ObjectNew()"
						Else If ManagedReferenceType(child.semanticType.elementType, ir) Then
							staticInitializer = DefaultValue(child.semanticType.elementType, ir)
						End If
						If staticInitializer.length Then
							Local staticIndex:String = localName + "_index"
							result :+ indent + "for (BBUINT " + staticIndex + " = 0; " + staticIndex + " < (BBUINT)" + child.semanticType.staticArrayLength + "; ++" + staticIndex + ") " + localName + "[" + staticIndex + "] = " + staticInitializer + ";~n"
						End If
						result :+ indent + "(void)" + localName + ";~n"
						locals.Insert(localKey, localName)
						Continue
					End If
					Local initializer:String = DefaultValue(child.semanticType, ir)
					If child.children.length = 1 Then initializer = EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals)
					If ir.specialization.debugInstrumentation Then
						If child.children.length = 1 Then result :+ indent + localName + " = " + initializer + ";~n"
					Else
						result :+ indent + CValueDeclaration(child.semanticType, localName, ir) + " = " + initializer + ";~n"
					End If
					result :+ indent + "(void)" + localName + ";~n"
					locals.Insert(localKey, localName)
				Case TEMPLATE_NODE_ASSIGNMENT
					If child.children.length <> 2 Then
						diagnostics :+ ["BMXC3049 generic sequential assignment must contain one target and one value"]
						Continue
					End If
					Local assignmentOperator:String = CAssignmentOperator(child.valueText)
					If Not assignmentOperator.length Then
						diagnostics :+ ["BMXC3049 generic sequential assignment operator '" + child.valueText + "' has no C lowering"]
						Continue
					End If
					If child.valueText = ":+" And child.children[0].semanticType And child.children[1].semanticType And child.children[0].semanticType.kind = TEMPLATE_TYPE_ARRAY And child.children[1].semanticType.kind = TEMPLATE_TYPE_ARRAY Then
						Local targetType:TTemplateTypeReference = child.children[0].semanticType
						Local valueType:TTemplateTypeReference = child.children[1].semanticType
						If targetType.rank <> 1 Or targetType.CanonicalName() <> valueType.CanonicalName() Or Not TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(targetType, ir) Then
							diagnostics :+ ["BMXC3049 generic Array compound assignment requires matching closed one-dimensional managed Array operands"]
							Continue
						End If
						If Not StableArrayCompoundTarget(child.children[0]) Then
							diagnostics :+ ["BMXC3049 generic Array compound assignment currently requires a stable Local, field, or Self field target"]
							Continue
						End If
						Local elementEncoding:String = ArrayElementEncoding(targetType.elementType, ir)
						If Not elementEncoding.length Then
							diagnostics :+ ["BMXC3049 generic Array compound assignment element type has no runtime encoding"]
							Continue
						End If
						Local targetExpression:String = EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals)
						Local valueExpression:String = EmitExpression(child.children[1], ir, ownerMethod, diagnostics, locals)
						result :+ indent + targetExpression + " = bbArrayConcat(~q" + elementEncoding + "~q, " + targetExpression + ", " + valueExpression + ");~n"
						Continue
					End If
					If child.valueText <> "=" And (Not ScalarNumericType(child.children[0].semanticType) Or Not ScalarNumericType(child.children[1].semanticType)) Then
						diagnostics :+ ["BMXC3049 generic compound assignment operator '" + child.valueText + "' requires closed scalar numeric operands"]
						Continue
					End If
					result :+ indent + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + " " + assignmentOperator + " " + EmitExpression(child.children[1], ir, ownerMethod, diagnostics, locals) + ";~n"
				Case TEMPLATE_NODE_EXPRESSION_STATEMENT
					If child.children.length <> 1 Then
						diagnostics :+ ["BMXC3065 generic expression statement requires one retained expression"]
						Continue
					End If
					result :+ indent + "(void)" + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + ";~n"
				Case TEMPLATE_NODE_RETURN
					If ownerMethod.isIteratorRoutine Then
						Local iteratorCleanupEdges:TGenericTemplateNode
						If child.children.length And child.children[child.children.length - 1].kind = TEMPLATE_NODE_BLOCK And child.children[child.children.length - 1].valueText = "cleanup-edges" Then iteratorCleanupEdges = child.children[child.children.length - 1]
						If iteratorCleanupEdges Then result :+ EmitTemplateCleanupEdges(iteratorCleanupEdges, ir, ownerMethod, diagnostics, locals, indent)
						result :+ indent + ownerMethod.iteratorStateExpression + "->state = -1;~n"
						If ownerMethod.iteratorOwnsResources Then
							result :+ indent + "bbExLeave();~n"
							If ir.specialization.debugInstrumentation Then result :+ indent + "bbOnDebugPopExState();~n"
						End If
						result :+ indent + "return 0;~n"
						Continue
					End If
					Local cleanupEdges:TGenericTemplateNode
					If child.children.length And child.children[child.children.length - 1].kind = TEMPLATE_NODE_BLOCK And child.children[child.children.length - 1].valueText = "cleanup-edges" Then cleanupEdges = child.children[child.children.length - 1]
					Local hasReturnExpression:Int = child.children.length And child.children[0] <> cleanupEdges
					If cleanupEdges And hasReturnExpression Then
						Local returnName:String = "bmx_cleanup_return_" + SourceIdentity(child)
						result :+ indent + CValueDeclaration(ownerMethod.returnType, returnName, ir) + " = " + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + ";~n"
						result :+ EmitTemplateCleanupEdges(cleanupEdges, ir, ownerMethod, diagnostics, locals, indent)
						result :+ EmitGenericDebugLeave(ir, indent)
						result :+ indent + "return " + returnName + ";~n"
					Else If cleanupEdges Then
						result :+ EmitTemplateCleanupEdges(cleanupEdges, ir, ownerMethod, diagnostics, locals, indent)
						result :+ EmitGenericDebugLeave(ir, indent)
						If VoidType(ownerMethod.returnType) Then result :+ indent + "return;~n" Else result :+ indent + "return " + DefaultValue(ownerMethod.returnType, ir) + ";~n"
					Else If hasReturnExpression Then
						If ir.specialization.debugInstrumentation Then
							Local returnName:String = "bmx_debug_return_" + SourceIdentity(child)
							result :+ indent + CValueDeclaration(ownerMethod.returnType, returnName, ir) + " = " + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + ";~n"
							result :+ EmitGenericDebugLeave(ir, indent)
							result :+ indent + "return " + returnName + ";~n"
						Else
							result :+ indent + "return " + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + ";~n"
						End If
					Else If VoidType(ownerMethod.returnType) Then
						result :+ EmitGenericDebugLeave(ir, indent) + indent + "return;~n"
					Else
						result :+ EmitGenericDebugLeave(ir, indent) + indent + "return " + DefaultValue(ownerMethod.returnType, ir) + ";~n"
					End If
				Case TEMPLATE_NODE_THROW
					If child.children.length <> 1 Or Not ManagedReferenceType(child.children[0].semanticType, ir) Then
						diagnostics :+ ["BMXC3066 generic Throw requires one closed managed object expression"]
						Continue
					End If
					result :+ indent + "bbExThrow((BBObject *)" + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + ");~n"
				Case TEMPLATE_NODE_YIELD
					If Not ownerMethod.isIteratorRoutine Or child.children.length < 1 Or child.children.length > 2 Then
						diagnostics :+ ["BMXC3085 generic Yield reached ordinary specialization emission"]
						Continue
					End If
					result :+ indent + ownerMethod.iteratorStateExpression + "->current = " + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + ";~n"
					result :+ indent + ownerMethod.iteratorStateExpression + "->state = " + child.valueText + ";~n"
					For Local frameIndex:Int = 0 Until Int(child.identity)
						result :+ indent + "bbExLeave();~n"
						If ir.specialization.debugInstrumentation Then result :+ indent + "bbOnDebugPopExState();~n"
					Next
					If ownerMethod.iteratorOwnsResources Then
						result :+ indent + "bbExLeave();~n"
						If ir.specialization.debugInstrumentation Then result :+ indent + "bbOnDebugPopExState();~n"
					End If
					result :+ indent + "return 1;~n"
					result :+ indent + "bmx_iterator_resume_" + child.valueText + ": ;~n"
				Case TEMPLATE_NODE_ASSERT
					If child.children.length < 1 Or child.children.length > 2 Or Not TruthTypeSupported(child.children[0].semanticType, ir) Then
						diagnostics :+ ["BMXC3067 generic Assert requires a closed truth-compatible condition and optional String message"]
						Continue
					End If
					If ir.specialization.debugInstrumentation Then
						Local assertMessage:String = "bbStringFromCString(~qAssert failed~q)"
						If child.children.length = 2 Then
							If Not child.children[1].semanticType Or child.children[1].semanticType.kind <> TEMPLATE_TYPE_BUILTIN Or child.children[1].semanticType.symbolName.ToLower() <> "string" Then
								diagnostics :+ ["BMXC3067 generic Assert message requires a closed String expression"]
								Continue
							End If
							If child.children[1].kind = TEMPLATE_NODE_LITERAL Then
								assertMessage = "bbStringFromCString(" + child.children[1].valueText + ")"
							Else
								assertMessage = EmitExpression(child.children[1], ir, ownerMethod, diagnostics, locals)
							End If
						End If
						result :+ indent + "if (!" + EmitConditionExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + ") {~n"
						result :+ indent + "    brl_blitz_RuntimeError(" + assertMessage + ");~n"
						result :+ indent + "}~n"
					End If
				Case TEMPLATE_NODE_RELEASE
					If child.children.length <> 1 Or Not ScalarIntegralType(child.children[0].semanticType) Or (child.children[0].kind <> TEMPLATE_NODE_NAME And child.children[0].kind <> TEMPLATE_NODE_MEMBER And child.children[0].kind <> TEMPLATE_NODE_ARRAY_ELEMENT) Then
						diagnostics :+ ["BMXC3077 generic Release requires one retained addressable integer expression"]
						Continue
					End If
					result :+ indent + "bbHandleRelease((size_t)(" + EmitExpression(child.children[0], ir, ownerMethod, diagnostics, locals) + "));~n"
				Case TEMPLATE_NODE_BRANCH
					result :+ EmitBranch(child, ir, ownerMethod, diagnostics, locals, indent)
				Case TEMPLATE_NODE_LOOP
					result :+ EmitLoop(child, ir, ownerMethod, diagnostics, locals, indent)
				Case TEMPLATE_NODE_SELECT
					result :+ EmitSelect(child, ir, ownerMethod, diagnostics, locals, indent)
				Case TEMPLATE_NODE_TRY
					result :+ EmitTemplateTryFinally(child, ir, ownerMethod, diagnostics, locals, indent)
				Case TEMPLATE_NODE_USING
					result :+ EmitTemplateUsing(child, ir, ownerMethod, diagnostics, locals, indent)
				Case TEMPLATE_NODE_DATA
					result :+ EmitTemplateDataStatement(child, ir, ownerMethod, diagnostics, locals, indent)
				Case TEMPLATE_NODE_LOOP_CONTROL
					If child.valueText <> "exit" And child.valueText <> "continue" Then
						diagnostics :+ ["BMXC3053 generic loop control kind '" + child.valueText + "' is unsupported"]
					Else If Not child.identity.length Then
						diagnostics :+ ["BMXC3053 generic " + child.valueText + " has no canonical loop target"]
					Else
						If child.children.length = 1 Then result :+ EmitTemplateCleanupEdges(child.children[0], ir, ownerMethod, diagnostics, locals, indent)
						result :+ indent + "goto " + LoopControlLabel(child.identity, child.valueText) + ";~n"
					End If
				Default
					diagnostics :+ ["BMXC3024 specialization method contains unsupported bound node kind " + child.kind]
			End Select
		Next
		Return result
	End Function

	Function EmitTemplateDataStatement:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not node Then Return ""
		Local prefix:String = ir.specialization.readableAbiName + "_data"
		Select node.identity
			Case "define"
				Return ""
			Case "restore"
				Local itemIndex:Int = GenericDataDefinitionIndex(ir, node.valueText)
				If itemIndex < 0 Then
					diagnostics :+ ["BMXC3075 generic RestoreData target is outside its canonical specialization data section"]
					Return ""
				End If
				Return indent + prefix + "_ensure();~n" + indent + prefix + "_offset = &" + prefix + "_items[" + itemIndex + "];~n"
			Case "read"
				Local result:String = indent + prefix + "_ensure();~n"
				For Local target:TGenericTemplateNode = EachIn node.children
					If Not target Or target.kind <> TEMPLATE_NODE_BLOCK Or target.children.length <> 1 Then
						diagnostics :+ ["BMXC3075 generic ReadData target has an invalid canonical record"]
						Continue
					End If
					Local conversionName:String = TemplateDataReadConversion(Int(target.valueText))
					If Not conversionName.length Then
						diagnostics :+ ["BMXC3075 generic ReadData target has an unsupported conversion"]
						Continue
					End If
					result :+ indent + "if ((BBSIZET)(" + prefix + "_offset - " + prefix + "_items) >= " + prefix + "_count) brl_blitz_OutOfDataError();~n"
					result :+ indent + EmitExpression(target.children[0], ir, ownerMethod, diagnostics, locals) + " = " + conversionName + "(" + prefix + "_offset++);~n"
				Next
				Return result
		End Select
		diagnostics :+ ["BMXC3075 generic Data node has unknown operation '" + node.identity + "'"]
		Return ""
	End Function

	Function TemplateDataReadConversion:String(kind:Int)
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
		Return ""
	End Function

	Function SourceIdentity:String(node:TGenericTemplateNode)
		If node And node.source Then Return String(node.source.start)
		Return "0"
	End Function

	Function GenericCoverageEnabled:Int(ir:TCompilerGenericSpecializationIr)
		Return ir And ir.specialization And ir.specialization.configuration And ir.specialization.configuration.coverageInstrumentation
	End Function

	Function ResetGenericCoverage(ir:TCompilerGenericSpecializationIr)
		If ir Then ir.coverageFiles = New TCompilerGenericCoverageFile[0]
	End Function

	Function GenericCoverageFile:TCompilerGenericCoverageFile(ir:TCompilerGenericSpecializationIr, path:String)
		If Not ir Or Not path.length Then Return Null
		Local normalized:String = path.Replace("\", "/")
		For Local file:TCompilerGenericCoverageFile = EachIn ir.coverageFiles
			If file.path = normalized Then Return file
		Next
		Local file:TCompilerGenericCoverageFile = New TCompilerGenericCoverageFile
		file.path = normalized
		ir.coverageFiles :+ [file]
		Return file
	End Function

	Function AddGenericCoverageLine(ir:TCompilerGenericSpecializationIr, source:TTemplateSourceLocation)
		If Not GenericCoverageEnabled(ir) Or Not source Or Not source.path.length Or source.line <= 0 Then Return
		Local file:TCompilerGenericCoverageFile = GenericCoverageFile(ir, source.path)
		For Local line:Int = EachIn file.lines
			If line = source.line Then Return
		Next
		file.lines :+ [source.line]
	End Function

	Function AddGenericCoverageFunction(ir:TCompilerGenericSpecializationIr, name:String, source:TTemplateSourceLocation)
		If Not GenericCoverageEnabled(ir) Or Not name.length Or Not source Or Not source.path.length Or source.line <= 0 Then Return
		Local file:TCompilerGenericCoverageFile = GenericCoverageFile(ir, source.path)
		For Local known:TCompilerGenericCoverageFunction = EachIn file.functions
			If known.name = name And known.source.line = source.line Then Return
		Next
		Local coverageFunction:TCompilerGenericCoverageFunction = New TCompilerGenericCoverageFunction
		coverageFunction.name = name
		coverageFunction.source = source
		file.functions :+ [coverageFunction]
	End Function

	Function GenericCoverageFunctionName:String(ownerMethod:TCompilerGenericMethodIr, ir:TCompilerGenericSpecializationIr)
		If Not ownerMethod Then Return ""
		If ownerMethod.coverageName.length Then Return ownerMethod.coverageName
		If ownerMethod.debugName.length Then
			ownerMethod.coverageName = ownerMethod.debugName
			If ownerMethod.source And ownerMethod.source.column > 0 Then ownerMethod.coverageName :+ " column " + ownerMethod.source.column
			Return ownerMethod.coverageName
		End If
		Local owner:TGenericSpecializationNode = ownerMethod.declaringSpecialization
		If Not owner And ir Then owner = ir.specialization
		Local ownerName:String = SpecializationDisplayName(owner)
		If ir And ir.isRoutine And ownerMethod = ir.routine Then
			ownerMethod.coverageName = ownerName
		Else If ownerMethod.name.ToLower() = "new" Then
			ownerMethod.coverageName = ownerName + ".New"
		Else If ownerName.length Then
			ownerMethod.coverageName = ownerName + "." + ownerMethod.name
		Else
			ownerMethod.coverageName = ownerMethod.name
		End If
		Return ownerMethod.coverageName
	End Function

	Function EmitGenericCoverageFunctionEntry:String(ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, indent:String)
		If Not GenericCoverageEnabled(ir) Or Not ownerMethod Or Not ownerMethod.source Or Not ownerMethod.source.path.length Or ownerMethod.source.line <= 0 Then Return ""
		Local name:String = GenericCoverageFunctionName(ownerMethod, ir)
		If Not name.length Then Return ""
		AddGenericCoverageFunction(ir, name, ownerMethod.source)
		Return indent + "bbCoverageUpdateFunctionLineInfo(" + CQuoted(ownerMethod.source.path.Replace("\", "/")) + ", " + CQuoted(name) + ", " + ownerMethod.source.line + ");~n"
	End Function

	Function EmitGenericCoverageStatement:String(ir:TCompilerGenericSpecializationIr, node:TGenericTemplateNode, indent:String)
		If Not GenericCoverageEnabled(ir) Or Not node Or Not node.source Or Not node.source.path.length Or node.source.line <= 0 Then Return ""
		AddGenericCoverageLine(ir, node.source)
		Return indent + "bbCoverageUpdateLineInfo(" + CQuoted(node.source.path.Replace("\", "/")) + ", " + node.source.line + ");~n"
	End Function

	Function EmitGenericCoverageCatalog:String(ir:TCompilerGenericSpecializationIr)
		If Not GenericCoverageEnabled(ir) Or Not ir.coverageFiles.length Then Return ""
		Local prefix:String = "bmx_generic_coverage_" + ir.specialization.identityDigest[..16]
		Local result:TStringBuilder = New TStringBuilder(2048)
		For Local fileIndex:Int = 0 Until ir.coverageFiles.length
			Local file:TCompilerGenericCoverageFile = ir.coverageFiles[fileIndex]
			If file.lines.length Then
				result.Append("static const int " + prefix + "_lines_" + fileIndex + "[] = {")
				For Local lineIndex:Int = 0 Until file.lines.length
					If lineIndex Then result.Append(", ")
					result.Append(file.lines[lineIndex])
				Next
				result.Append("};~n")
			End If
			If file.functions.length Then
				result.Append("static const BBCoverageFunctionInfo " + prefix + "_functions_" + fileIndex + "[] = {~n")
				For Local coverageFunction:TCompilerGenericCoverageFunction = EachIn file.functions
					result.Append("    { " + CQuoted(coverageFunction.name) + ", " + coverageFunction.source.line + " },~n")
				Next
				result.Append("};~n")
			End If
		Next
		result.Append("static BBCoverageFileInfo " + prefix + "_files[] = {~n")
		For Local fileIndex:Int = 0 Until ir.coverageFiles.length
			Local file:TCompilerGenericCoverageFile = ir.coverageFiles[fileIndex]
			Local linesName:String = "NULL"
			Local functionsName:String = "NULL"
			If file.lines.length Then linesName = prefix + "_lines_" + fileIndex
			If file.functions.length Then functionsName = prefix + "_functions_" + fileIndex
			result.Append("    { " + CQuoted(file.path) + ", " + linesName + ", " + file.lines.length + ", NULL, " + functionsName + ", " + file.functions.length + ", NULL },~n")
		Next
		result.Append("    { NULL, NULL, 0, NULL, NULL, 0, NULL }~n};~n~n")
		Return result.ToString()
	End Function

	Function GenericCoverageRegistrationName:String(ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.specialization Then Return ""
		Return ir.specialization.readableAbiName + "_register_coverage"
	End Function

	Function EmitGenericCoverageRegistration:String(ir:TCompilerGenericSpecializationIr)
		If Not GenericCoverageEnabled(ir) Then Return ""
		Local name:String = GenericCoverageRegistrationName(ir)
		Local registerCall:String
		If ir.coverageFiles.length Then
			Local prefix:String = "bmx_generic_coverage_" + ir.specialization.identityDigest[..16]
			registerCall = "        bbCoverageRegisterFile(" + prefix + "_files);~n"
		End If
		Return "void " + name + "(void) {~n    static int registered = 0;~n    if (!registered) {~n        registered = 1;~n" + registerCall + "    }~n}~n"
	End Function

	Function GenericLocalName:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr)
		If Not node Then Return "bmx_local_missing"
		Local result:String = "bmx_local_" + TCompilerAbiNamer.Sanitize(node.valueText)
		If Not ir Or Not ir.specialization Or Not ir.specialization.debugInstrumentation Then Return result
		Local identity:String = node.valueText.ToLower() + ":" + SourceIdentity(node)
		Return result + "_" + TCompilerStableDigest.Sha256(identity)[..12]
	End Function

	Function GenericIteratorLocalFieldName:String(node:TGenericTemplateNode)
		If Not node Then Return "local_missing"
		Return "local_" + TCompilerAbiNamer.Sanitize(node.valueText) + "_" + SourceIdentity(node)
	End Function

	Function EmitGenericStaticArrayInitialization:String(value:TTemplateTypeReference, target:String, ir:TCompilerGenericSpecializationIr, indent:String)
		If Not value Or value.kind <> TEMPLATE_TYPE_STATIC_ARRAY Or Not value.elementType Or value.staticArrayLength <= 0 Then Return ""
		Local initializer:String = DefaultValue(value.elementType, ir)
		Local staticStruct:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value.elementType, ir)
		If staticStruct And staticStruct.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then initializer = staticStruct.readableAbiName + "_New_ObjectNew()"
		Local indexName:String = "bmx_static_array_index_" + TCompilerStableDigest.Sha256(target)[..12]
		Return indent + "for (BBUINT " + indexName + " = 0; " + indexName + " < (BBUINT)" + value.staticArrayLength + "; ++" + indexName + ") " + target + "[" + indexName + "] = " + initializer + ";~n"
	End Function

	Function EmitGenericDebugStatement:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, indent:String)
		If Not ir Or Not ir.specialization Or Not ir.specialization.debugInstrumentation Or Not node Or Not node.source Then Return ""
		Local source:TTemplateSourceLocation = node.source
		If Not source.path.length Or source.line <= 0 Then Return ""
		Local normalizedPath:String = source.path.Replace("\", "/")
		Local sourceId:ULong = GenericDebugSourceHash(normalizedPath)
		Local identity:String = normalizedPath.ToLower() + ":" + source.start + ":" + source.length + ":" + source.line + ":" + source.column + ":" + node.kind + ":" + node.identity
		Local name:String = "bmx_generic_debug_stm_" + TCompilerStableDigest.Sha256(identity)[..16]
		Return indent + "BBDebugStm " + name + " = { " + sourceId + "ULL, " + source.line + ", " + source.column + " };~n" + indent + "bbOnDebugEnterStm(&" + name + ");~n"
	End Function

	Function EmitGenericGdbLineDirective:String(source:TTemplateSourceLocation, ir:TCompilerGenericSpecializationIr, indent:String)
		If Not ir Or Not ir.specialization Or Not ir.specialization.configuration Or Not ir.specialization.configuration.gdbDebug Or Not source Or Not source.path.length Or source.line <= 0 Then Return ""
		Return indent + "#line " + source.line + " " + CQuoted(source.path.Replace("\", "/")) + "~n"
	End Function

	Function EmitGenericGdbGeneratedLineReset:String(ir:TCompilerGenericSpecializationIr, indent:String = "")
		If Not ir Or Not ir.specialization Or Not ir.specialization.configuration Or Not ir.specialization.configuration.gdbDebug Then Return ""
		Return indent + "#line 1 ~q<bcc-generated>~q~n"
	End Function

	Function GenericDebugSourceHash:ULong(path:String)
		Local hash:ULong = $cbf29ce484222325:ULong
		For Local index:Int = 0 Until path.length
			hash :~ ULong(path[index])
			hash :* 1099511628211:ULong
		Next
		If hash = 0 Then hash = 1
		Return hash
	End Function

	Function EmitTemplateCleanupEdges:String(edges:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not edges Or edges.kind <> TEMPLATE_NODE_BLOCK Or edges.valueText <> "cleanup-edges" Then
			diagnostics :+ ["BMXC3072 generic cleanup transfer has no canonical cleanup-edge record"]
			Return ""
		End If
		Local result:String
		For Local cleanupStep:TGenericTemplateNode = EachIn edges.children
			Local retainedIteratorCleanup:Int = ownerMethod And ownerMethod.isIteratorRoutine And cleanupStep And cleanupStep.kind = TEMPLATE_NODE_BLOCK And ownerMethod.iteratorRetainedCleanupIdentities.Contains(cleanupStep.identity)
			If Not retainedIteratorCleanup Then
				result :+ indent + "bbExLeave();~n"
				If ir.specialization.debugInstrumentation Then result :+ indent + "bbOnDebugPopExState();~n"
			End If
			If cleanupStep And cleanupStep.kind = TEMPLATE_NODE_BLOCK And cleanupStep.valueText = "cleanup-finally" And cleanupStep.children.length = 1 Then
				result :+ EmitSequentialBlock(cleanupStep.children[0], ir, ownerMethod, diagnostics, CloneLocals(locals), indent)
			Else If cleanupStep And cleanupStep.kind = TEMPLATE_NODE_BLOCK And cleanupStep.valueText = "cleanup-try" Then
				' The exception frame has no language-level body, but it must be
				' left before a Return/Exit/Continue crosses the protected region.
			Else If cleanupStep And cleanupStep.kind = TEMPLATE_NODE_BLOCK And cleanupStep.valueText = "cleanup-using" Then
				result :+ EmitTemplateUsingCleanup(cleanupStep.children, ir, ownerMethod, diagnostics, locals, indent, retainedIteratorCleanup)
			Else If cleanupStep And cleanupStep.kind = TEMPLATE_NODE_BLOCK And cleanupStep.valueText = "cleanup-iterator" And cleanupStep.identity.length Then
				Local closeableName:String = "bmx_" + TCompilerAbiNamer.Sanitize(cleanupStep.identity) + "_closeable"
				If retainedIteratorCleanup Then closeableName = ownerMethod.iteratorStateExpression + "->loop_" + TCompilerAbiNamer.Sanitize(cleanupStep.identity) + "_closeable"
				result :+ EmitGenericIteratorCleanup(closeableName, ir, indent, retainedIteratorCleanup)
			Else
				diagnostics :+ ["BMXC3072 generic cleanup transfer contains an unsupported cleanup record"]
			End If
		Next
		Return result
	End Function

	Function EmitGenericIteratorCloseCleanupEdges:String(edges:TGenericTemplateNode, index:Int, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not edges Or edges.kind <> TEMPLATE_NODE_BLOCK Or edges.valueText <> "cleanup-edges" Then Return ""
		While index < edges.children.length
			Local candidate:TGenericTemplateNode = edges.children[index]
			If candidate And candidate.kind = TEMPLATE_NODE_BLOCK And candidate.valueText <> "cleanup-try" Then Exit
			index :+ 1
		Wend
		If index >= edges.children.length Then Return ""
		Local cleanupStep:TGenericTemplateNode = edges.children[index]
		Local cleanupId:String = TCompilerAbiNamer.Sanitize(SourceIdentity(cleanupStep) + "_" + index)
		Local exceptionName:String = "bmx_iterator_close_exception_" + cleanupId
		Local failedName:String = "bmx_iterator_close_failed_" + cleanupId
		Local result:String = indent + "{~n"
		Local stepIndent:String = indent + "    "
		result :+ stepIndent + "BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
		result :+ stepIndent + "BBINT " + failedName + " = 0;~n"
		result :+ stepIndent + "bbExTry {~n"
		result :+ stepIndent + "case 0: {~n"
		If ir.specialization.debugInstrumentation Then result :+ stepIndent + "    bbOnDebugPushExState();~n"
		If cleanupStep.valueText = "cleanup-finally" And cleanupStep.children.length = 1 Then
			result :+ EmitSequentialBlock(cleanupStep.children[0], ir, ownerMethod, diagnostics, CloneLocals(locals), stepIndent + "    ")
		Else If cleanupStep.valueText = "cleanup-using" Then
			Local cleanupLocals:TMap = CloneLocals(locals)
			For Local resource:TGenericTemplateNode = EachIn cleanupStep.children
				If resource And resource.children.length Then
					Local declaration:TGenericTemplateNode = resource.children[0]
					cleanupLocals.Insert(declaration.valueText.ToLower(), ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(declaration))
				End If
			Next
			result :+ EmitTemplateUsingCleanup(cleanupStep.children, ir, ownerMethod, diagnostics, cleanupLocals, stepIndent + "    ", True)
		Else If cleanupStep.valueText = "cleanup-iterator" And cleanupStep.identity.length Then
			result :+ EmitGenericIteratorCleanup(ownerMethod.iteratorStateExpression + "->loop_" + TCompilerAbiNamer.Sanitize(cleanupStep.identity) + "_closeable", ir, stepIndent + "    ", True)
		End If
		result :+ stepIndent + "    bbExLeave();~n"
		If ir.specialization.debugInstrumentation Then result :+ stepIndent + "    bbOnDebugPopExState();~n"
		result :+ stepIndent + "} break;~n"
		result :+ stepIndent + "case 1: {~n"
		If ir.specialization.debugInstrumentation Then result :+ stepIndent + "    bbOnDebugPopExState();~n"
		result :+ stepIndent + "    " + exceptionName + " = bbExCatch(); " + failedName + " = 1;~n"
		result :+ stepIndent + "} break;~n"
		result :+ stepIndent + "}~n"
		result :+ EmitGenericIteratorCloseCleanupEdges(edges, index + 1, ir, ownerMethod, diagnostics, locals, stepIndent)
		result :+ stepIndent + "if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
		Return result + indent + "}~n"
	End Function

	Function EmitGenericIteratorOwnedCleanup:String(cleanups:TGenericTemplateNode[], ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		Local result:String
		For Local index:Int = cleanups.length - 1 To 0 Step -1
			Local cleanup:TGenericTemplateNode = cleanups[index]
			If cleanup.kind = TEMPLATE_NODE_LOOP Then
				result :+ EmitGenericIteratorCleanup(ownerMethod.iteratorStateExpression + "->" + GenericIteratorLoopFieldPrefix(cleanup) + "_closeable", ir, indent, True)
			Else If cleanup.kind = TEMPLATE_NODE_USING And cleanup.children.length Then
				Local resources:TGenericTemplateNode[] = cleanup.children[..cleanup.children.length - 1]
				Local cleanupLocals:TMap = CloneLocals(locals)
				For Local resource:TGenericTemplateNode = EachIn resources
					If Not resource Or resource.children.length < 1 Then Continue
					Local declaration:TGenericTemplateNode = resource.children[0]
					cleanupLocals.Insert(declaration.valueText.ToLower(), ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(declaration))
				Next
				result :+ EmitTemplateUsingCleanup(resources, ir, ownerMethod, diagnostics, cleanupLocals, indent, True)
			End If
		Next
		Return result
	End Function

	Function EmitGenericIteratorCleanup:String(closeableName:String, ir:TCompilerGenericSpecializationIr, indent:String, clearResource:Int = False)
		Local result:String = indent + "if ((BBOBJECT)" + closeableName + " != (BBOBJECT)&bbNullObject) {~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
		result :+ indent + "        ((struct BCC2_GenericCloseableIteratorMethods *)bbObjectInterface((BBOBJECT)" + closeableName + ", (BBInterface *)&brl_blitz_ICloseable_ifc))->m_Close((BBOBJECT)" + closeableName + ");~n"
		result :+ indent + "        bbExLeave();~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {"
		If ir.specialization.debugInstrumentation Then result :+ " bbOnDebugPopExState();"
		result :+ " (void)bbExCatch(); } break;~n"
		result :+ indent + "    }~n"
		result :+ indent + "}~n"
		If clearResource Then result :+ indent + closeableName + " = (BBOBJECT)&bbNullObject;~n"
		Return result
	End Function

	Function EmitTemplateTryFinally:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not node Or Not node.children.length Then
			diagnostics :+ ["BMXC3072 generic Try requires a protected body"]
			Return ""
		End If
		Local catches:TGenericTemplateNode[]
		Local finallyBody:TGenericTemplateNode
		For Local index:Int = 1 Until node.children.length
			Local child:TGenericTemplateNode = node.children[index]
			If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "catch-clause" Then catches :+ [child]
			If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "finally-body" And child.children.length = 1 Then finallyBody = child.children[0]
		Next
		' Format 20 represented Try/Finally as [protected, finally] before
		' Catch routing introduced the explicit wrapper record in format 21.
		If node.valueText = "finally" And Not finallyBody And node.children.length = 2 Then finallyBody = node.children[1]
		If GenericNodeContainsYield(finallyBody) Then
			diagnostics :+ ["BMXC1252 Yield inside Finally is not supported; Yield from the protected Try or Catch body instead"]
			Return ""
		End If
		If node.valueText = "catch" Then Return EmitTemplateTryCatch(node.children[0], catches, ir, ownerMethod, diagnostics, locals, indent, SourceIdentity(node), node)
		If node.valueText <> "finally" And node.valueText <> "catch-finally" Then
			diagnostics :+ ["BMXC3072 generic Try has unknown routing identity '" + node.valueText + "'"]
			Return ""
		End If
		If Not finallyBody Then
			diagnostics :+ ["BMXC3072 generic Try/Finally has no Finally body record"]
			Return ""
		End If
		If ownerMethod And ownerMethod.isIteratorRoutine And GenericTryRetained(node) Then Return EmitGenericIteratorTryFinally(node, catches, finallyBody, ir, ownerMethod, diagnostics, locals, indent)
		Local tryName:String = "bmx_try_" + SourceIdentity(node)
		Local exceptionName:String = tryName + "_exception"
		Local failedName:String = tryName + "_failed"
		Local result:String = indent + "{~n"
		result :+ indent + "    BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
		result :+ indent + "    BBINT " + failedName + " = 0;~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
		If catches.length Then
			result :+ EmitTemplateTryCatch(node.children[0], catches, ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ", SourceIdentity(node) + "_catch", node)
		Else
			result :+ EmitSequentialBlock(node.children[0], ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ")
		End If
		result :+ indent + "        bbExLeave();~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
		result :+ indent + "        " + failedName + " = 1;~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		result :+ EmitSequentialBlock(finallyBody, ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "    ")
		result :+ indent + "    if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
		Return result + indent + "}~n"
	End Function

	Function EmitTemplateTryCatch:String(body:TGenericTemplateNode, catches:TGenericTemplateNode[], ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String, identity:String, tryNode:TGenericTemplateNode = Null)
		If Not body Or Not catches.length Then
			diagnostics :+ ["BMXC3072 generic Try/Catch requires a protected body and Catch clauses"]
			Return ""
		End If
		If ownerMethod And ownerMethod.isIteratorRoutine And tryNode And GenericTryRetained(tryNode) Then Return EmitGenericIteratorTryCatch(body, catches, ir, ownerMethod, diagnostics, locals, indent, identity, tryNode)
		Local exceptionName:String = "bmx_try_" + TCompilerAbiNamer.Sanitize(identity) + "_exception"
		Local result:String = indent + "{~n"
		result :+ indent + "    BBOBJECT " + exceptionName + ";~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
		result :+ EmitSequentialBlock(body, ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ")
		result :+ indent + "        bbExLeave();~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
		For Local index:Int = 0 Until catches.length
			Local catchNode:TGenericTemplateNode = catches[index]
			If Not catchNode Or catchNode.children.length <> 2 Or catchNode.children[0].kind <> TEMPLATE_NODE_DECLARATION Then
				diagnostics :+ ["BMXC3072 generic Catch clause has an invalid canonical record"]
				Continue
			End If
			Local declaration:TGenericTemplateNode = catchNode.children[0]
			If index Then result :+ " else " Else result :+ indent + "        "
			result :+ "if (" + TemplateCatchCondition(declaration.semanticType, exceptionName, ir, diagnostics) + ") {~n"
			Local catchLocals:TMap = CloneLocals(locals)
			Local catchName:String = GenericLocalName(declaration, ir)
			If ir.specialization.debugInstrumentation Then
				result :+ indent + "            " + catchName + " = (" + CType(declaration.semanticType, ir) + ")" + exceptionName + ";~n"
			Else
				result :+ indent + "            " + CValueDeclaration(declaration.semanticType, catchName, ir) + " = (" + CType(declaration.semanticType, ir) + ")" + exceptionName + ";~n"
			End If
			result :+ indent + "            (void)" + catchName + ";~n"
			catchLocals.Insert(declaration.valueText.ToLower(), catchName)
			result :+ PrepareActivationClosureEnvironment(ClosureActivationIdentity(catchNode), ownerMethod, catchLocals, declaration, catchName, indent + "            ")
			result :+ EmitSequentialBlock(catchNode.children[1], ir, ownerMethod, diagnostics, catchLocals, indent + "            ")
			result :+ indent + "        }"
		Next
		result :+ " else {~n"
		result :+ indent + "            bbExThrow((BBObject *)" + exceptionName + ");~n"
		result :+ indent + "        }~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		Return result + indent + "}~n"
	End Function

	Function EmitGenericIteratorTryFinally:String(node:TGenericTemplateNode, catches:TGenericTemplateNode[], finallyBody:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		Local prefix:String = GenericIteratorTryPrefix(node)
		Local stateExpression:String = ownerMethod.iteratorStateExpression + "->state"
		Local exceptionExpression:String = ownerMethod.iteratorStateExpression + "->" + prefix + "_exception"
		Local failedExpression:String = ownerMethod.iteratorStateExpression + "->" + prefix + "_failed"
		Local pendingName:String = "bmx_" + prefix + "_pending"
		Local result:String = indent + GenericIteratorTryEntryLabel(node) + ": ;~n"
		result :+ indent + "{~n"
		result :+ indent + "    if (" + stateExpression + " < 0) { " + exceptionExpression + " = (BBOBJECT)&bbNullObject; " + failedExpression + " = 0; }~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
		For Local catchNode:TGenericTemplateNode = EachIn catches
			If catchNode And catchNode.children.length = 2 Then result :+ EmitGenericIteratorResumeDispatch(catchNode.children[1], stateExpression, indent + "        ")
		Next
		If catches.length Then
			result :+ EmitGenericIteratorResumeDispatch(node.children[0], stateExpression, indent + "        ", GenericIteratorTryCatchEntryLabel(node))
			result :+ EmitGenericIteratorTryCatch(node.children[0], catches, ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ", SourceIdentity(node) + "_catch", node)
		Else
			result :+ EmitGenericIteratorResumeDispatch(node.children[0], stateExpression, indent + "        ")
			result :+ EmitSequentialBlock(node.children[0], ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ")
		End If
		result :+ indent + "        bbExLeave();~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionExpression + " = bbExCatch();~n"
		result :+ indent + "        " + failedExpression + " = 1;~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		result :+ EmitSequentialBlock(finallyBody, ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "    ")
		result :+ indent + "    if (" + failedExpression + ") {~n"
		result :+ indent + "        BBOBJECT " + pendingName + " = " + exceptionExpression + ";~n"
		result :+ indent + "        " + exceptionExpression + " = (BBOBJECT)&bbNullObject; " + failedExpression + " = 0;~n"
		result :+ indent + "        bbExThrow((BBObject *)" + pendingName + ");~n"
		result :+ indent + "    }~n"
		result :+ indent + "    " + exceptionExpression + " = (BBOBJECT)&bbNullObject; " + failedExpression + " = 0;~n"
		Return result + indent + "}~n"
	End Function

	Function EmitGenericIteratorTryCatch:String(body:TGenericTemplateNode, catches:TGenericTemplateNode[], ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String, identity:String, tryNode:TGenericTemplateNode)
		Local stateExpression:String = ownerMethod.iteratorStateExpression + "->state"
		Local exceptionName:String = "bmx_try_" + TCompilerAbiNamer.Sanitize(identity) + "_exception"
		Local result:String = indent + GenericIteratorTryCatchEntryLabel(tryNode) + ": ;~n"
		result :+ indent + "{~n"
		result :+ indent + "    BBOBJECT " + exceptionName + ";~n"
		result :+ indent + "    bbExTry {~n"
		result :+ indent + "    case 0: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
		result :+ EmitGenericIteratorResumeDispatch(body, stateExpression, indent + "        ")
		result :+ EmitSequentialBlock(body, ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ")
		result :+ indent + "        bbExLeave();~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    case 1: {~n"
		If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
		result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
		For Local index:Int = 0 Until catches.length
			Local catchNode:TGenericTemplateNode = catches[index]
			If Not catchNode Or catchNode.children.length <> 2 Or catchNode.children[0].kind <> TEMPLATE_NODE_DECLARATION Then Continue
			Local declaration:TGenericTemplateNode = catchNode.children[0]
			If index Then result :+ " else " Else result :+ indent + "        "
			result :+ "if (" + TemplateCatchCondition(declaration.semanticType, exceptionName, ir, diagnostics) + ") {~n"
			Local catchLocals:TMap = CloneLocals(locals)
			Local catchName:String = GenericLocalName(declaration, ir)
			Local retainedCatch:Int = GenericNodeContainsYield(catchNode.children[1])
			If retainedCatch Then catchName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(declaration)
			If retainedCatch Or ir.specialization.debugInstrumentation Then
				result :+ indent + "            " + catchName + " = (" + CType(declaration.semanticType, ir) + ")" + exceptionName + ";~n"
			Else
				result :+ indent + "            " + CValueDeclaration(declaration.semanticType, catchName, ir) + " = (" + CType(declaration.semanticType, ir) + ")" + exceptionName + ";~n"
			End If
			result :+ indent + "            (void)" + catchName + ";~n"
			catchLocals.Insert(declaration.valueText.ToLower(), catchName)
			result :+ PrepareActivationClosureEnvironment(ClosureActivationIdentity(catchNode), ownerMethod, catchLocals, declaration, catchName, indent + "            ")
			result :+ EmitSequentialBlock(catchNode.children[1], ir, ownerMethod, diagnostics, catchLocals, indent + "            ")
			result :+ indent + "        }"
		Next
		result :+ " else {~n"
		result :+ indent + "            bbExThrow((BBObject *)" + exceptionName + ");~n"
		result :+ indent + "        }~n"
		result :+ indent + "    } break;~n"
		result :+ indent + "    }~n"
		Return result + indent + "}~n"
	End Function

	Function TemplateCatchCondition:String(value:TTemplateTypeReference, exceptionName:String, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not value Then Return "0"
		If value.kind = TEMPLATE_TYPE_BUILTIN Then
			Select value.symbolName.ToLower()
				Case "object" Return "1"
				Case "string" Return "bbObjectStringcast((BBOBJECT)" + exceptionName + ") != (BBOBJECT)&bbEmptyString"
			End Select
		End If
		If value.kind = TEMPLATE_TYPE_ARRAY Then Return "bbObjectArraycast((BBOBJECT)" + exceptionName + ") != &bbEmptyArray"
		Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
		If referenced Then
			If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then Return "bbInterfaceDowncast((BBObject *)" + exceptionName + ", (BBInterface *)&" + referenced.readableAbiName + "_ifc) != &bbNullObject"
			If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_CLASS Then Return "bbObjectDowncast((BBOBJECT)" + exceptionName + ", (BBClass *)&" + referenced.readableAbiName + ") != &bbNullObject"
		End If
		If value.kind = TEMPLATE_TYPE_NAMED And value.runtimeAbiName.length Then
			If value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then Return "bbInterfaceDowncast((BBObject *)" + exceptionName + ", (BBInterface *)&" + value.runtimeAbiName + "_ifc) != &bbNullObject"
			If value.runtimeKind = TEMPLATE_RUNTIME_CLASS Then Return "bbObjectDowncast((BBOBJECT)" + exceptionName + ", (BBClass *)&" + value.runtimeAbiName + ") != &bbNullObject"
		End If
		diagnostics :+ ["BMXC3072 generic Catch type '" + value.CanonicalName() + "' has no runtime matcher"]
		Return "0"
	End Function

	Function EmitTemplateUsingCleanup:String(resources:TGenericTemplateNode[], ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String, clearResources:Int = False)
		Local result:String
		For Local index:Int = resources.length - 1 To 0 Step -1
			Local resource:TGenericTemplateNode = resources[index]
			If Not resource Or resource.kind <> TEMPLATE_NODE_BLOCK Or resource.valueText <> "using-resource" Or resource.children.length <> 2 Then
				diagnostics :+ ["BMXC3073 generic Using cleanup contains an invalid resource record"]
				Continue
			End If
			Local declaration:TGenericTemplateNode = resource.children[0]
			Local reference:TGenericTemplateNode = New TGenericTemplateNode
			reference.kind = TEMPLATE_NODE_NAME
			reference.valueText = declaration.valueText
			reference.semanticType = declaration.semanticType
			reference.source = declaration.source
			result :+ indent + "if (" + EmitConditionExpression(reference, ir, ownerMethod, diagnostics, locals) + ") {~n"
			result :+ indent + "    bbExTry {~n"
			result :+ indent + "    case 0: {~n"
			If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
			result :+ indent + "        (void)" + EmitExpression(resource.children[1], ir, ownerMethod, diagnostics, locals) + ";~n"
			result :+ indent + "        bbExLeave();~n"
			If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
			result :+ indent + "    } break;~n"
			result :+ indent + "    case 1: {"
			If ir.specialization.debugInstrumentation Then result :+ " bbOnDebugPopExState();"
			result :+ " (void)bbExCatch(); } break;~n"
			result :+ indent + "    }~n"
			result :+ indent + "}~n"
			If clearResources Then
				Local resourceName:String = String(locals.ValueForKey(declaration.valueText.ToLower()))
				If Not resourceName.length Then resourceName = GenericLocalName(declaration, ir)
				result :+ indent + resourceName + " = " + DefaultValue(declaration.semanticType, ir) + ";~n"
			End If
		Next
		Return result
	End Function

	Function EmitTemplateUsing:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not node Or node.children.length < 2 Then
			diagnostics :+ ["BMXC3073 generic Using requires resource records and a body"]
			Return ""
		End If
		Local usingLocals:TMap = CloneLocals(locals)
		Local body:TGenericTemplateNode = node.children[node.children.length - 1]
		Local resources:TGenericTemplateNode[] = node.children[..node.children.length - 1]
		Local usingName:String = "bmx_" + TCompilerAbiNamer.Sanitize(node.identity)
		Local exceptionName:String = usingName + "_exception"
		Local failedName:String = usingName + "_failed"
		Local persistentUsing:Int = ownerMethod.isIteratorRoutine And GenericNodeContainsYield(body)
		Local result:String = indent + "{~n"
		For Local resource:TGenericTemplateNode = EachIn resources
			If Not resource Or resource.kind <> TEMPLATE_NODE_BLOCK Or resource.valueText <> "using-resource" Or resource.children.length <> 2 Then
				diagnostics :+ ["BMXC3073 generic Using contains an invalid resource record"]
				Continue
			End If
			Local declaration:TGenericTemplateNode = resource.children[0]
			If Not ManagedReferenceType(declaration.semanticType, ir) Then
				diagnostics :+ ["BMXC3073 generic Using resource '" + declaration.valueText + "' requires a closed managed ICloseable reference"]
				Continue
			End If
			Local resourceType:String = CType(declaration.semanticType, ir)
			Local resourceName:String = GenericLocalName(declaration, ir)
			If ownerMethod.isIteratorRoutine Then resourceName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(declaration)
			If Not ownerMethod.isIteratorRoutine And Not ir.specialization.debugInstrumentation Then result :+ indent + "    " + resourceType + " volatile " + resourceName + " = " + DefaultValue(declaration.semanticType, ir) + ";~n"
			result :+ indent + "    (void)" + resourceName + ";~n"
			usingLocals.Insert(declaration.valueText.ToLower(), resourceName)
		Next
		If Not persistentUsing Then
			result :+ indent + "    BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
			result :+ indent + "    BBINT " + failedName + " = 0;~n"
			result :+ indent + "    bbExTry {~n"
			result :+ indent + "    case 0: {~n"
			If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
		End If
		Local bodyIndent:String = indent + "        "
		If persistentUsing Then bodyIndent = indent + "    "
		For Local resource:TGenericTemplateNode = EachIn resources
			If Not resource Or resource.children.length <> 2 Then Continue
			Local declaration:TGenericTemplateNode = resource.children[0]
			If declaration.children.length = 1 Then
				result :+ bodyIndent + String(usingLocals.ValueForKey(declaration.valueText.ToLower())) + " = " + EmitExpression(declaration.children[0], ir, ownerMethod, diagnostics, usingLocals) + ";~n"
			End If
		Next
		result :+ EmitSequentialBlock(body, ir, ownerMethod, diagnostics, usingLocals, bodyIndent)
		If persistentUsing Then
			result :+ EmitTemplateUsingCleanup(resources, ir, ownerMethod, diagnostics, usingLocals, indent + "    ", True)
		Else
			result :+ indent + "        bbExLeave();~n"
			If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
			result :+ indent + "    } break;~n"
			result :+ indent + "    case 1: {~n"
			If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
			result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
			result :+ indent + "        " + failedName + " = 1;~n"
			result :+ indent + "    } break;~n"
			result :+ indent + "    }~n"
			result :+ EmitTemplateUsingCleanup(resources, ir, ownerMethod, diagnostics, usingLocals, indent + "    ")
			result :+ indent + "    if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
		End If
		Return result + indent + "}~n"
	End Function

	Function EmitBranch:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not node Or node.children.length < 2 Then
			diagnostics :+ ["BMXC3050 generic If node requires at least one condition and body"]
			Return ""
		End If
		Local conditionedChildren:Int = node.children.length
		If conditionedChildren Mod 2 Then conditionedChildren :- 1
		Local result:String
		For Local index:Int = 0 Until conditionedChildren Step 2
			If Not TruthTypeSupported(node.children[index].semanticType, ir) Then
				diagnostics :+ ["BMXC3050 generic If condition requires a closed scalar truth value"]
				Return ""
			End If
			If index Then
				result :+ " else if "
			Else
				result :+ indent + "if "
			End If
			result :+ EmitConditionExpression(node.children[index], ir, ownerMethod, diagnostics, locals) + " {~n"
			result :+ EmitSequentialBlock(node.children[index + 1], ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "    ")
			result :+ indent + "}"
		Next
		If conditionedChildren <> node.children.length Then
			result :+ " else {~n"
			result :+ EmitSequentialBlock(node.children[node.children.length - 1], ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "    ")
			result :+ indent + "}"
		End If
		Return result + "~n"
	End Function

	Function EmitSelectComparison:String(selectorName:String, selectorType:TTemplateTypeReference, value:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap)
		Local valueExpression:String = EmitExpression(value, ir, ownerMethod, diagnostics, locals)
		If StringTemplateType(selectorType) Then Return "bbStringEquals(" + selectorName + ", " + valueExpression + ") == 1"
		If ScalarNumericType(selectorType) Or (selectorType And selectorType.kind = TEMPLATE_TYPE_NAMED And selectorType.runtimeKind = TEMPLATE_RUNTIME_ENUM) Then Return selectorName + " == " + valueExpression
		If ManagedReferenceType(selectorType, ir) Then Return "(BBOBJECT)" + selectorName + " == (BBOBJECT)" + valueExpression
		diagnostics :+ ["BMXC3071 generic Select selector '" + selectorType.CanonicalName() + "' has no supported closed equality ABI"]
		Return "0"
	End Function

	Function EmitSelect:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not node Or Not node.children.length Or Not node.semanticType Then
			diagnostics :+ ["BMXC3071 generic Select requires a retained selector and closed selector type"]
			Return ""
		End If
		Local selectorType:String = CType(node.semanticType, ir)
		If Not selectorType.length Then
			diagnostics :+ ["BMXC3071 generic Select selector has no closed C ABI"]
			Return ""
		End If
		Local selectorName:String = "bmx_" + TCompilerAbiNamer.Sanitize(node.identity) + "_value"
		Local result:String = indent + "{~n"
		result :+ indent + "    " + selectorType + " " + selectorName + " = " + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ";~n"
		Local emittedCase:Int
		Local defaultNode:TGenericTemplateNode
		For Local index:Int = 1 Until node.children.length
			Local caseNode:TGenericTemplateNode = node.children[index]
			If caseNode.kind <> TEMPLATE_NODE_BLOCK Then
				diagnostics :+ ["BMXC3071 generic Select contains an invalid case record"]
				Continue
			End If
			If caseNode.valueText = "select-default" Then
				defaultNode = caseNode
				Continue
			End If
			If caseNode.valueText <> "select-case" Or caseNode.children.length < 2 Then
				diagnostics :+ ["BMXC3071 generic Select case requires one or more values and a body"]
				Continue
			End If
			If emittedCase Then result :+ " else " Else result :+ indent + "    "
			result :+ "if ("
			For Local valueIndex:Int = 0 Until caseNode.children.length - 1
				If valueIndex Then result :+ " || "
				result :+ EmitSelectComparison(selectorName, node.semanticType, caseNode.children[valueIndex], ir, ownerMethod, diagnostics, locals)
			Next
			result :+ ") {~n"
			result :+ EmitSequentialBlock(caseNode.children[caseNode.children.length - 1], ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ")
			result :+ indent + "    }"
			emittedCase = True
		Next
		If defaultNode And defaultNode.children.length = 1 Then
			If emittedCase Then result :+ " else {~n" Else result :+ indent + "    {~n"
			result :+ EmitSequentialBlock(defaultNode.children[0], ir, ownerMethod, diagnostics, CloneLocals(locals), indent + "        ")
			result :+ indent + "    }"
		End If
		If emittedCase Or defaultNode Then result :+ "~n"
		Return result + indent + "}~n"
	End Function

	Function LoopTargetNode:Int(node:TGenericTemplateNode)
		Return node And (node.kind = TEMPLATE_NODE_DECLARATION Or node.kind = TEMPLATE_NODE_NAME Or node.kind = TEMPLATE_NODE_MEMBER Or node.kind = TEMPLATE_NODE_ARRAY_ELEMENT)
	End Function

	Function PrepareLoopClosureEnvironment:String(node:TGenericTemplateNode, ownerMethod:TCompilerGenericMethodIr, bodyLocals:TMap, headerNode:TGenericTemplateNode, headerExpression:String, indent:String)
		If Not node Or Not ownerMethod Then Return ""
		Return PrepareActivationClosureEnvironment(node.identity, ownerMethod, bodyLocals, headerNode, headerExpression, indent)
	End Function

	Function PrepareActivationClosureEnvironment:String(identity:String, ownerMethod:TCompilerGenericMethodIr, bodyLocals:TMap, headerNode:TGenericTemplateNode, headerExpression:String, indent:String)
		If Not identity.length Or Not ownerMethod Then Return ""
		Local environment:TCompilerGenericClosureEnvironmentIr = TCompilerGenericClosureEnvironmentIr(ownerMethod.activationClosureEnvironments.ValueForKey(identity))
		If Not environment Then Return ""
		Local result:String
		If ownerMethod.isIteratorRoutine Then
			result = indent + environment.localName + " = " + environment.abiName + "_new();~n"
			result :+ indent + ownerMethod.iteratorStateExpression + "->" + GenericIteratorClosureEnvironmentFieldName(environment) + " = (BBOBJECT)" + environment.localName + ";~n"
		Else
			result = indent + "struct " + environment.abiName + "_obj *" + environment.localName + " = " + environment.abiName + "_new();~n"
		End If
		If environment.parent Then result :+ indent + environment.localName + "->" + environment.parentFieldName + " = (BBOBJECT)" + environment.parent.localName + ";~n"
		For Local capture:TCompilerGenericClosureCaptureIr = EachIn environment.captures
			Local fieldExpression:String = ClosureEnvironmentField(environment, capture)
			bodyLocals.Insert(capture.name.ToLower(), fieldExpression)
			If headerNode And headerNode.kind = TEMPLATE_NODE_DECLARATION And capture.name.ToLower() = headerNode.valueText.ToLower() Then result :+ indent + fieldExpression + " = " + headerExpression + ";~n"
		Next
		Return result
	End Function

	Function EmitLoop:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap, indent:String)
		If Not node Then
			diagnostics :+ ["BMXC3051 generic loop node is missing"]
			Return ""
		End If
		If Not node.identity.length Then
			diagnostics :+ ["BMXC3053 generic loop has no canonical identity"]
			Return ""
		End If
		Local hasContinue:Int = HasLoopControl(node, node.identity, "continue")
		Local hasExit:Int = HasLoopControl(node, node.identity, "exit")
		If node.valueText = "while" Then
			If node.children.length <> 2 Then
				diagnostics :+ ["BMXC3051 generic While node requires one condition and body"]
				Return ""
			End If
			If Not TruthTypeSupported(node.children[0].semanticType, ir) Then
				diagnostics :+ ["BMXC3051 generic While condition requires a closed scalar truth value"]
				Return ""
			End If
			Local bodyLocals:TMap = CloneLocals(locals)
			Local result:String = indent + "while " + EmitConditionExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + " {~n"
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, Null, "", indent + "    ")
			result :+ EmitSequentialBlock(node.children[1], ir, ownerMethod, diagnostics, bodyLocals, indent + "    ")
			If hasContinue Then result :+ indent + "    " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ indent + "}~n"
			If hasExit Then result :+ indent + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result
		End If
		If node.valueText = "repeat-forever" Then
			If node.children.length <> 1 Then
				diagnostics :+ ["BMXC3051 generic Repeat Forever node requires one body"]
				Return ""
			End If
			Local bodyLocals:TMap = CloneLocals(locals)
			Local result:String = indent + "for (;;) {~n"
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, Null, "", indent + "    ")
			result :+ EmitSequentialBlock(node.children[0], ir, ownerMethod, diagnostics, bodyLocals, indent + "    ")
			If hasContinue Then result :+ indent + "    " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ indent + "}~n"
			If hasExit Then result :+ indent + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result
		End If
		If node.valueText = "repeat-until" Then
			If node.children.length <> 2 Then
				diagnostics :+ ["BMXC3051 generic Repeat Until node requires one body and condition"]
				Return ""
			End If
			If Not TruthTypeSupported(node.children[1].semanticType, ir) Then
				diagnostics :+ ["BMXC3051 generic Repeat Until condition requires a closed scalar truth value"]
				Return ""
			End If
			Local bodyLocals:TMap = CloneLocals(locals)
			Local result:String = indent + "do {~n"
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, Null, "", indent + "    ")
			result :+ EmitSequentialBlock(node.children[0], ir, ownerMethod, diagnostics, bodyLocals, indent + "    ")
			If hasContinue Then result :+ indent + "    " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ indent + "} while (!(" + EmitConditionExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + "));~n"
			If hasExit Then result :+ indent + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result
		End If
		If node.valueText = "eachin-string" Then
			If node.children.length <> 3 Or Not LoopTargetNode(node.children[0]) Then
				diagnostics :+ ["BMXC3054 generic String EachIn node requires a loop declaration or target, collection, and body"]
				Return ""
			End If
			Local targetNode:TGenericTemplateNode = node.children[0]
			Local collectionNode:TGenericTemplateNode = node.children[1]
			If Not ScalarNumericType(targetNode.semanticType) Then
				diagnostics :+ ["BMXC3054 generic String EachIn requires a closed scalar numeric loop variable"]
				Return ""
			End If
			If Not collectionNode.semanticType Or collectionNode.semanticType.kind <> TEMPLATE_TYPE_BUILTIN Or collectionNode.semanticType.symbolName.ToLower() <> "string" Then
				diagnostics :+ ["BMXC3054 generic String EachIn requires a closed String collection"]
				Return ""
			End If
			Local localType:String = CType(targetNode.semanticType, ir)
			Local targetName:String
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				targetName = GenericLocalName(targetNode, ir)
				If ownerMethod.isIteratorRoutine Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			Else
				targetName = EmitExpression(targetNode, ir, ownerMethod, diagnostics, locals)
			End If
			Local loopName:String = TCompilerAbiNamer.Sanitize(node.identity)
			Local collectionName:String = "bmx_" + loopName + "_collection"
			Local indexName:String = "bmx_" + loopName + "_index"
			Local elementName:String = "bmx_" + loopName + "_element"
			Local persistentEach:Int = ownerMethod.isIteratorRoutine And GenericNodeContainsYield(node.children[2])
			If persistentEach Then
				Local statePrefix:String = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLoopFieldPrefix(node)
				collectionName = statePrefix + "_collection"
				indexName = statePrefix + "_index"
				elementName = statePrefix + "_element"
				If targetNode.kind = TEMPLATE_NODE_DECLARATION Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			End If
			Local result:String = indent + "{~n"
			If persistentEach Then
				result :+ indent + "    " + collectionName + " = " + DebugManagedValue(EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals), collectionNode.semanticType, ir) + ";~n"
				result :+ indent + "    " + indexName + " = 0;~n"
			Else
				result :+ indent + "    BBSTRING " + collectionName + " = " + DebugManagedValue(EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals), collectionNode.semanticType, ir) + ";~n"
				result :+ indent + "    BBUINT " + indexName + " = 0;~n"
			End If
			result :+ indent + "    for (; " + indexName + " < (BBUINT)" + collectionName + "->length; " + indexName + " = " + indexName + " + 1) {~n"
			If persistentEach Then result :+ indent + "        " + elementName + " = (BBINT)" + collectionName + "->buf[" + indexName + "];~n" Else result :+ indent + "        BBINT " + elementName + " = (BBINT)" + collectionName + "->buf[" + indexName + "];~n"
			Local convertedElement:String = "((" + localType + ")(" + elementName + "))"
			Local bodyLocals:TMap = CloneLocals(locals)
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				If ownerMethod.isIteratorRoutine Or ir.specialization.debugInstrumentation Then result :+ indent + "        " + targetName + " = " + convertedElement + ";~n" Else result :+ indent + "        " + localType + " " + targetName + " = " + convertedElement + ";~n"
				bodyLocals.Insert(targetNode.valueText.ToLower(), targetName)
			Else
				result :+ indent + "        " + targetName + " = " + convertedElement + ";~n"
			End If
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, targetNode, targetName, indent + "        ")
			result :+ EmitSequentialBlock(node.children[2], ir, ownerMethod, diagnostics, bodyLocals, indent + "        ")
			If hasContinue Then result :+ indent + "        " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ indent + "    }~n"
			If hasExit Then result :+ indent + "    " + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result + indent + "}~n"
		End If
		If node.valueText = "eachin-array" Then
			If node.children.length <> 3 Or Not LoopTargetNode(node.children[0]) Then
				diagnostics :+ ["BMXC3055 generic managed Array EachIn node requires a loop declaration or target, collection, and body"]
				Return ""
			End If
			Local targetNode:TGenericTemplateNode = node.children[0]
			Local collectionNode:TGenericTemplateNode = node.children[1]
			If Not TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(collectionNode.semanticType, ir) Then
				diagnostics :+ ["BMXC3055 generic managed Array EachIn requires a closed supported element ABI"]
				Return ""
			End If
			If Not targetNode.semanticType Or Not TCompilerGenericSpecializationLowerer.SupportedType(targetNode.semanticType, ir) Then
				diagnostics :+ ["BMXC3055 generic managed Array EachIn target has no closed supported ABI"]
				Return ""
			End If
			Local elementType:String = CType(collectionNode.semanticType.elementType, ir)
			Local targetType:String = CType(targetNode.semanticType, ir)
			Local targetName:String
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				targetName = GenericLocalName(targetNode, ir)
				If ownerMethod.isIteratorRoutine Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			Else
				targetName = EmitExpression(targetNode, ir, ownerMethod, diagnostics, locals)
			End If
			Local loopName:String = TCompilerAbiNamer.Sanitize(node.identity)
			Local collectionName:String = "bmx_" + loopName + "_collection"
			Local indexName:String = "bmx_" + loopName + "_index"
			Local elementName:String = "bmx_" + loopName + "_element"
			Local persistentEach:Int = ownerMethod.isIteratorRoutine And GenericNodeContainsYield(node.children[2])
			If persistentEach Then
				Local statePrefix:String = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLoopFieldPrefix(node)
				collectionName = statePrefix + "_collection"
				indexName = statePrefix + "_index"
				elementName = statePrefix + "_element"
				If targetNode.kind = TEMPLATE_NODE_DECLARATION Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			End If
			Local result:String = indent + "{~n"
			If persistentEach Then
				result :+ indent + "    " + collectionName + " = " + DebugManagedValue(EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals), collectionNode.semanticType, ir) + ";~n"
				result :+ indent + "    " + indexName + " = 0;~n"
			Else
				result :+ indent + "    BBARRAY " + collectionName + " = " + DebugManagedValue(EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals), collectionNode.semanticType, ir) + ";~n"
				result :+ indent + "    BBUINT " + indexName + " = 0;~n"
			End If
			result :+ indent + "    for (; " + indexName + " < (BBUINT)" + collectionName + "->scales[0]; " + indexName + " = " + indexName + " + 1) {~n"
			If persistentEach Then result :+ indent + "        " + elementName + " = ((" + elementType + "*)BBARRAYDATA(" + collectionName + ", 1))[" + indexName + "];~n" Else result :+ indent + "        " + elementType + " " + elementName + " = ((" + elementType + "*)BBARRAYDATA(" + collectionName + ", 1))[" + indexName + "];~n"
			Local convertedElement:String = elementName
			Local objectElement:Int = IsObjectType(collectionNode.semanticType.elementType)
			If objectElement And StringTemplateType(targetNode.semanticType) Then
				result :+ indent + "        if (!bbObjectIsString((BBOBJECT)" + elementName + ")) continue;~n"
				convertedElement = "((BBSTRING)bbObjectStringcast((BBOBJECT)" + elementName + "))"
			Else If objectElement And ScalarNumericType(targetNode.semanticType) Then
				convertedElement = "(*((" + targetType + "*)bbObjectToFieldOffset((BBOBJECT)" + elementName + ")))"
			Else If objectElement And targetNode.semanticType.kind = TEMPLATE_TYPE_ARRAY Then
				Local targetEncoding:String = ArrayElementEncoding(targetNode.semanticType, ir)
				convertedElement = "bbArrayCastFromObject((BBOBJECT)" + elementName + ", ~q" + targetEncoding + "~q)"
			Else If collectionNode.semanticType.elementType.CanonicalName() <> targetNode.semanticType.CanonicalName() Then
				If targetNode.semanticType.kind = TEMPLATE_TYPE_BUILTIN And targetNode.semanticType.symbolName.ToLower() = "object" And (collectionNode.semanticType.elementType.kind = TEMPLATE_TYPE_ARRAY Or ManagedReferenceType(collectionNode.semanticType.elementType, ir)) Then
					convertedElement = "((BBOBJECT)" + elementName + ")"
				Else
					diagnostics :+ ["BMXC3055 generic managed Array EachIn cannot adapt element '" + collectionNode.semanticType.elementType.CanonicalName() + "' to target '" + targetNode.semanticType.CanonicalName() + "'"]
					Return ""
				End If
			End If
			Local bodyLocals:TMap = CloneLocals(locals)
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				If ownerMethod.isIteratorRoutine Or ir.specialization.debugInstrumentation Then result :+ indent + "        " + targetName + " = " + convertedElement + ";~n" Else result :+ indent + "        " + targetType + " " + targetName + " = " + convertedElement + ";~n"
				bodyLocals.Insert(targetNode.valueText.ToLower(), targetName)
			Else
				result :+ indent + "        " + targetName + " = " + convertedElement + ";~n"
			End If
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, targetNode, targetName, indent + "        ")
			result :+ EmitSequentialBlock(node.children[2], ir, ownerMethod, diagnostics, bodyLocals, indent + "        ")
			If hasContinue Then result :+ indent + "        " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ indent + "    }~n"
			If hasExit Then result :+ indent + "    " + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result + indent + "}~n"
		End If
		If node.valueText = "eachin-static-array" Then
			If node.children.length <> 3 Or Not LoopTargetNode(node.children[0]) Then
				diagnostics :+ ["BMXC3056 generic StaticArray EachIn node requires a loop declaration or target, collection, and body"]
				Return ""
			End If
			Local targetNode:TGenericTemplateNode = node.children[0]
			Local collectionNode:TGenericTemplateNode = node.children[1]
			If Not TCompilerGenericSpecializationLowerer.SupportedStaticArrayType(collectionNode.semanticType, ir) Then
				diagnostics :+ ["BMXC3056 generic StaticArray EachIn requires a positive fixed extent and closed supported element ABI"]
				Return ""
			End If
			Local numericStaticConversion:Int = ScalarNumericType(collectionNode.semanticType.elementType) And ScalarNumericType(targetNode.semanticType)
			Local exactStaticConversion:Int = targetNode.semanticType And targetNode.semanticType.CanonicalName() = collectionNode.semanticType.elementType.CanonicalName()
			If Not numericStaticConversion And Not exactStaticConversion Then
				diagnostics :+ ["BMXC3056 generic StaticArray EachIn requires an exact element target or numeric conversion"]
				Return ""
			End If
			Local elementType:String = CType(collectionNode.semanticType.elementType, ir)
			Local targetType:String = CType(targetNode.semanticType, ir)
			Local targetName:String
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				targetName = GenericLocalName(targetNode, ir)
				If ownerMethod.isIteratorRoutine Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			Else
				targetName = EmitExpression(targetNode, ir, ownerMethod, diagnostics, locals)
			End If
			Local loopName:String = TCompilerAbiNamer.Sanitize(node.identity)
			Local collectionName:String = "bmx_" + loopName + "_collection"
			Local indexName:String = "bmx_" + loopName + "_index"
			Local elementName:String = "bmx_" + loopName + "_element"
			Local persistentEach:Int = ownerMethod.isIteratorRoutine And GenericNodeContainsYield(node.children[2])
			If persistentEach Then
				Local prefix:String = GenericIteratorLoopFieldPrefix(node)
				collectionName = ownerMethod.iteratorStateExpression + "->" + prefix + "_collection"
				indexName = ownerMethod.iteratorStateExpression + "->" + prefix + "_index"
				elementName = ownerMethod.iteratorStateExpression + "->" + prefix + "_element"
			End If
			Local result:String = indent + "{~n"
			If persistentEach Then
				result :+ indent + "    " + collectionName + " = " + EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals) + ";~n"
				result :+ indent + "    " + indexName + " = 0;~n"
			Else
				result :+ indent + "    " + elementType + " *" + collectionName + " = " + EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals) + ";~n"
				result :+ indent + "    BBUINT " + indexName + " = 0;~n"
			End If
			result :+ indent + "    for (; " + indexName + " < (BBUINT)" + collectionNode.semanticType.staticArrayLength + "; " + indexName + " = " + indexName + " + 1) {~n"
			If persistentEach Then result :+ indent + "        " + elementName + " = " + collectionName + "[" + indexName + "];~n" Else result :+ indent + "        " + elementType + " " + elementName + " = " + collectionName + "[" + indexName + "];~n"
			Local convertedElement:String = elementName
			If numericStaticConversion Then convertedElement = "((" + targetType + ")(" + elementName + "))"
			Local bodyLocals:TMap = CloneLocals(locals)
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				If ownerMethod.isIteratorRoutine Or ir.specialization.debugInstrumentation Then result :+ indent + "        " + targetName + " = " + convertedElement + ";~n" Else result :+ indent + "        " + targetType + " " + targetName + " = " + convertedElement + ";~n"
				bodyLocals.Insert(targetNode.valueText.ToLower(), targetName)
			Else
				result :+ indent + "        " + targetName + " = " + convertedElement + ";~n"
			End If
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, targetNode, targetName, indent + "        ")
			result :+ EmitSequentialBlock(node.children[2], ir, ownerMethod, diagnostics, bodyLocals, indent + "        ")
			If hasContinue Then result :+ indent + "        " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ indent + "    }~n"
			If hasExit Then result :+ indent + "    " + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result + indent + "}~n"
		End If
		If node.valueText = "eachin-iterable" Or node.valueText = "eachin-iterator" Then
			If node.children.length <> 7 Or Not LoopTargetNode(node.children[0]) Then
				diagnostics :+ ["BMXC3057 generic Interface EachIn node requires a loop target, collection, iterator type, factory marker, advance/current operations, and body"]
				Return ""
			End If
			Local targetNode:TGenericTemplateNode = node.children[0]
			Local collectionNode:TGenericTemplateNode = node.children[1]
			Local iteratorTypeNode:TGenericTemplateNode = node.children[2]
			Local factoryNode:TGenericTemplateNode = node.children[3]
			Local advanceNode:TGenericTemplateNode = node.children[4]
			Local currentNode:TGenericTemplateNode = node.children[5]
			Local collectionInterface:TGenericSpecializationNode = InterfaceSpecialization(collectionNode.semanticType, ir)
			Local iteratorInterface:TGenericSpecializationNode = InterfaceSpecialization(iteratorTypeNode.semanticType, ir)
			If Not collectionInterface Then
				Local collectionType:TGenericSpecializationNode = TypeSpecialization(collectionNode.semanticType, ir)
				If collectionType Then
					If node.valueText = "eachin-iterable" Then collectionInterface = ImplementedInterfaceForOperation(collectionType, factoryNode, ir, diagnostics) Else collectionInterface = ImplementedInterfaceForOperation(collectionType, advanceNode, ir, diagnostics)
				End If
			End If
			If Not iteratorInterface Then
				Local iteratorType:TGenericSpecializationNode = TypeSpecialization(iteratorTypeNode.semanticType, ir)
				If iteratorType Then iteratorInterface = ImplementedInterfaceForOperation(iteratorType, advanceNode, ir, diagnostics)
			End If
			If Not collectionInterface Or Not iteratorInterface Then
				diagnostics :+ ["BMXC3057 generic IIterable/IIterator EachIn currently requires canonical generic Interface receiver types"]
				Return ""
			End If
			If Not IteratorElementTypeSupported(currentNode.semanticType, ir) Or Not targetNode.semanticType Or targetNode.semanticType.CanonicalName() <> currentNode.semanticType.CanonicalName() Then
				diagnostics :+ ["BMXC3057 generic IIterable/IIterator EachIn requires an exactly matching closed supported value or managed-reference element target"]
				Return ""
			End If
			Local advanceMethod:TCompilerGenericMethodIr = InterfaceOperation(iteratorInterface, advanceNode, ir, diagnostics)
			Local currentMethod:TCompilerGenericMethodIr = InterfaceOperation(iteratorInterface, currentNode, ir, diagnostics)
			Local factoryMethod:TCompilerGenericMethodIr
			If node.valueText = "eachin-iterable" Then factoryMethod = InterfaceOperation(collectionInterface, factoryNode, ir, diagnostics)
			If Not advanceMethod Or Not currentMethod Or (node.valueText = "eachin-iterable" And Not factoryMethod) Then Return ""
			Local targetType:String = CType(targetNode.semanticType, ir)
			Local targetName:String
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				targetName = GenericLocalName(targetNode, ir)
				If ownerMethod.isIteratorRoutine Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			Else
				targetName = EmitExpression(targetNode, ir, ownerMethod, diagnostics, locals)
			End If
			Local loopName:String = TCompilerAbiNamer.Sanitize(node.identity)
			Local collectionName:String = "bmx_" + loopName + "_collection"
			Local iteratorName:String = "bmx_" + loopName + "_iterator"
			Local elementName:String = "bmx_" + loopName + "_element"
			Local closeableName:String = "bmx_" + loopName + "_closeable"
			Local persistentEach:Int = ownerMethod.isIteratorRoutine And GenericNodeContainsYield(node.children[6])
			If persistentEach Then
				Local statePrefix:String = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLoopFieldPrefix(node)
				collectionName = statePrefix + "_collection"
				iteratorName = statePrefix + "_iterator"
				closeableName = statePrefix + "_closeable"
				If targetNode.kind = TEMPLATE_NODE_DECLARATION Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			End If
			Local exceptionName:String = "bmx_" + loopName + "_exception"
			Local failedName:String = "bmx_" + loopName + "_failed"
			Local loopIndent:String = indent + "        "
			If persistentEach Then loopIndent = indent + "    "
			Local result:String = indent + "{~n"
			' Canonical Type expressions have their closed struct-pointer ABI, while
			' Interface dispatch intentionally stores the evaluate-once receiver as
			' the runtime object base. C does not implicitly convert between those
			' two struct-pointer types, so make the managed upcast explicit.
			If persistentEach Then result :+ indent + "    " + collectionName + " = (BBOBJECT)(" + EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals) + ");~n" Else result :+ indent + "    BBOBJECT " + collectionName + " = (BBOBJECT)(" + EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals) + ");~n"
			If node.valueText = "eachin-iterable" Then
				If persistentEach Then result :+ indent + "    " + iteratorName + " = " + EmitInterfaceOperation(collectionInterface, factoryNode, factoryMethod, collectionName, ir, ownerMethod, diagnostics, locals) + ";~n" Else result :+ indent + "    BBOBJECT " + iteratorName + " = " + EmitInterfaceOperation(collectionInterface, factoryNode, factoryMethod, collectionName, ir, ownerMethod, diagnostics, locals) + ";~n"
			Else
				If persistentEach Then result :+ indent + "    " + iteratorName + " = " + collectionName + ";~n" Else result :+ indent + "    BBOBJECT " + iteratorName + " = " + collectionName + ";~n"
			End If
			If persistentEach Then
				result :+ indent + "    " + closeableName + " = (BBOBJECT)bbInterfaceDowncast((BBObject *)" + iteratorName + ", (BBInterface *)&brl_blitz_ICloseable_ifc);~n"
			Else
				result :+ indent + "    BBOBJECT " + closeableName + " = (BBOBJECT)bbInterfaceDowncast((BBObject *)" + iteratorName + ", (BBInterface *)&brl_blitz_ICloseable_ifc);~n"
				result :+ indent + "    BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
				result :+ indent + "    BBINT " + failedName + " = 0;~n"
				result :+ indent + "    bbExTry {~n"
				result :+ indent + "    case 0: {~n"
				If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
			End If
			result :+ loopIndent + "while (" + EmitInterfaceOperation(iteratorInterface, advanceNode, advanceMethod, iteratorName, ir, ownerMethod, diagnostics, locals) + ") {~n"
			result :+ loopIndent + "    " + targetType + " " + elementName + " = " + EmitInterfaceOperation(iteratorInterface, currentNode, currentMethod, iteratorName, ir, ownerMethod, diagnostics, locals) + ";~n"
			Local bodyLocals:TMap = CloneLocals(locals)
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				If ownerMethod.isIteratorRoutine Or ir.specialization.debugInstrumentation Then result :+ loopIndent + "    " + targetName + " = " + elementName + ";~n" Else result :+ loopIndent + "    " + targetType + " " + targetName + " = " + elementName + ";~n"
				bodyLocals.Insert(targetNode.valueText.ToLower(), targetName)
			Else
				result :+ loopIndent + "    " + targetName + " = " + elementName + ";~n"
			End If
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, targetNode, targetName, loopIndent + "    ")
			result :+ EmitSequentialBlock(node.children[6], ir, ownerMethod, diagnostics, bodyLocals, loopIndent + "    ")
			If hasContinue Then result :+ loopIndent + "    " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ loopIndent + "}~n"
			If persistentEach Then
				result :+ EmitGenericIteratorCleanup(closeableName, ir, indent + "    ", True)
			Else
				result :+ indent + "        bbExLeave();~n"
				If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
				result :+ indent + "    } break;~n"
				result :+ indent + "    case 1: {~n"
				If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
				result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
				result :+ indent + "        " + failedName + " = 1;~n"
				result :+ indent + "    } break;~n"
				result :+ indent + "    }~n"
				result :+ EmitGenericIteratorCleanup(closeableName, ir, indent + "    ")
				result :+ indent + "    if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
			End If
			If hasExit Then result :+ indent + "    " + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result + indent + "}~n"
		End If
		If node.valueText = "eachin-object-enumerator" Then
			If node.children.length <> 8 Or Not LoopTargetNode(node.children[0]) Then
				diagnostics :+ ["BMXC3058 generic ObjectEnumerator EachIn node requires a loop target, collection, iterator type, factory, advance/current operations, adaptation, and body"]
				Return ""
			End If
			Local targetNode:TGenericTemplateNode = node.children[0]
			Local collectionNode:TGenericTemplateNode = node.children[1]
			Local iteratorTypeNode:TGenericTemplateNode = node.children[2]
			Local factoryNode:TGenericTemplateNode = node.children[3]
			Local advanceNode:TGenericTemplateNode = node.children[4]
			Local currentNode:TGenericTemplateNode = node.children[5]
			Local adaptationNode:TGenericTemplateNode = node.children[6]
			Local collectionType:TGenericSpecializationNode = TypeSpecialization(collectionNode.semanticType, ir)
			Local iteratorType:TGenericSpecializationNode = TypeSpecialization(iteratorTypeNode.semanticType, ir)
			Local ordinaryCollection:Int = collectionNode.semanticType And collectionNode.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And collectionNode.semanticType.runtimeAbiName.length > 0
			Local ordinaryIterator:Int = iteratorTypeNode.semanticType And iteratorTypeNode.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And iteratorTypeNode.semanticType.runtimeAbiName.length > 0
			If (Not collectionType And Not ordinaryCollection) Or (Not iteratorType And Not ordinaryIterator) Then
				diagnostics :+ ["BMXC3058 generic ObjectEnumerator EachIn requires canonical generic or published ordinary Type collection and iterator receivers"]
				Return ""
			End If
			If Not IsObjectType(currentNode.semanticType) Then
				diagnostics :+ ["BMXC3058 generic ObjectEnumerator NextObject operation must retain its Object result"]
				Return ""
			End If
			If Not adaptationNode.semanticType Or Not targetNode.semanticType Or adaptationNode.semanticType.CanonicalName() <> targetNode.semanticType.CanonicalName() Then
				diagnostics :+ ["BMXC3058 generic ObjectEnumerator adaptation does not match its closed loop-target type"]
				Return ""
			End If
			Local targetClass:TGenericSpecializationNode
			Local targetInterface:TGenericSpecializationNode
			Local ordinaryTargetKind:Int
			Local ordinaryTargetAbiName:String
			Select adaptationNode.valueText
				Case "object-direct"
					If Not IsObjectType(targetNode.semanticType) Then
						diagnostics :+ ["BMXC3058 generic ObjectEnumerator direct adaptation requires an Object loop target"]
						Return ""
					End If
				Case "object-string"
					If Not StringTemplateType(targetNode.semanticType) Then
						diagnostics :+ ["BMXC3058 generic ObjectEnumerator String adaptation requires a String loop target"]
						Return ""
					End If
				Case "object-numeric"
					If Not ScalarNumericType(targetNode.semanticType) Then
						diagnostics :+ ["BMXC3058 generic ObjectEnumerator numeric adaptation requires a scalar numeric loop target"]
						Return ""
					End If
				Case "object-checked-cast"
					targetClass = TypeSpecialization(adaptationNode.semanticType, ir)
					targetInterface = InterfaceSpecialization(adaptationNode.semanticType, ir)
					If Not targetClass And Not targetInterface Then
						ordinaryTargetKind = adaptationNode.semanticType.runtimeKind
						ordinaryTargetAbiName = adaptationNode.semanticType.runtimeAbiName
						If ordinaryTargetKind = TEMPLATE_RUNTIME_NONE Or Not ordinaryTargetAbiName.length Then
							diagnostics :+ ["BMXC3058 generic ObjectEnumerator target '" + adaptationNode.semanticType.CanonicalName() + "' has no canonical generic or published ordinary Type/Interface runtime cast identity"]
							Return ""
						End If
					End If
				Default
					diagnostics :+ ["BMXC3058 generic ObjectEnumerator has unknown adaptation record '" + adaptationNode.valueText + "'"]
					Return ""
			End Select
			Local factoryMethod:TCompilerGenericMethodIr
			Local advanceMethod:TCompilerGenericMethodIr
			Local currentMethod:TCompilerGenericMethodIr
			If collectionType Then factoryMethod = TypeOperation(collectionType, factoryNode, ir, diagnostics)
			If iteratorType Then
				advanceMethod = TypeOperation(iteratorType, advanceNode, ir, diagnostics)
				currentMethod = TypeOperation(iteratorType, currentNode, ir, diagnostics)
			End If
			If (collectionType And Not factoryMethod) Or (iteratorType And (Not advanceMethod Or Not currentMethod)) Then Return ""
			If ordinaryCollection And factoryNode.runtimeDispatchKind <> TEMPLATE_DISPATCH_ORDINARY_CLASS Then
				diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator factory operation has no published virtual-slot ordinal"]
				Return ""
			End If
			If ordinaryIterator And (advanceNode.runtimeDispatchKind <> TEMPLATE_DISPATCH_ORDINARY_CLASS Or currentNode.runtimeDispatchKind <> TEMPLATE_DISPATCH_ORDINARY_CLASS) Then
				diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator iterator operations have no published virtual-slot ordinals"]
				Return ""
			End If
			Local targetName:String
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				targetName = GenericLocalName(targetNode, ir)
				If ownerMethod.isIteratorRoutine Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			Else
				targetName = EmitExpression(targetNode, ir, ownerMethod, diagnostics, locals)
			End If
			Local loopName:String = TCompilerAbiNamer.Sanitize(node.identity)
			Local collectionName:String = "bmx_" + loopName + "_collection"
			Local iteratorName:String = "bmx_" + loopName + "_iterator"
			Local elementName:String = "bmx_" + loopName + "_element"
			Local closeableName:String = "bmx_" + loopName + "_closeable"
			Local persistentEach:Int = ownerMethod.isIteratorRoutine And GenericNodeContainsYield(node.children[7])
			If persistentEach Then
				Local statePrefix:String = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLoopFieldPrefix(node)
				collectionName = statePrefix + "_collection"
				iteratorName = statePrefix + "_iterator"
				closeableName = statePrefix + "_closeable"
				If targetNode.kind = TEMPLATE_NODE_DECLARATION Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode)
			End If
			Local exceptionName:String = "bmx_" + loopName + "_exception"
			Local failedName:String = "bmx_" + loopName + "_failed"
			Local loopIndent:String = indent + "        "
			If persistentEach Then loopIndent = indent + "    "
			Local collectionCType:String = CType(collectionNode.semanticType, ir)
			Local iteratorCType:String = CType(iteratorTypeNode.semanticType, ir)
			If Not collectionCType.length Or Not iteratorCType.length Then
				diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator receiver has no closed C ABI reference type"]
				Return ""
			End If
			Local factoryExpression:String
			If collectionType Then factoryExpression = EmitTypeOperation(collectionType, factoryNode, factoryMethod, collectionName, ir, ownerMethod, diagnostics, locals) Else factoryExpression = EmitOrdinaryClassOperation(factoryNode, collectionName, ir, diagnostics, ownerMethod, locals)
			Local advanceExpression:String
			Local currentExpression:String
			If iteratorType Then
				advanceExpression = EmitTypeOperation(iteratorType, advanceNode, advanceMethod, iteratorName, ir, ownerMethod, diagnostics, locals)
				currentExpression = EmitTypeOperation(iteratorType, currentNode, currentMethod, iteratorName, ir, ownerMethod, diagnostics, locals)
			Else
				advanceExpression = EmitOrdinaryClassOperation(advanceNode, iteratorName, ir, diagnostics, ownerMethod, locals)
				currentExpression = EmitOrdinaryClassOperation(currentNode, iteratorName, ir, diagnostics, ownerMethod, locals)
			End If
			If Not factoryExpression.length Or Not advanceExpression.length Or Not currentExpression.length Then Return ""
			Local result:String = indent + "{~n"
			If persistentEach Then
				result :+ indent + "    " + collectionName + " = " + EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals) + ";~n"
				result :+ indent + "    " + iteratorName + " = " + factoryExpression + ";~n"
				result :+ indent + "    " + closeableName + " = (BBOBJECT)bbInterfaceDowncast((BBObject *)" + iteratorName + ", (BBInterface *)&brl_blitz_ICloseable_ifc);~n"
			Else
				result :+ indent + "    " + collectionCType + " " + collectionName + " = " + EmitExpression(collectionNode, ir, ownerMethod, diagnostics, locals) + ";~n"
				result :+ indent + "    " + iteratorCType + " " + iteratorName + " = " + factoryExpression + ";~n"
				result :+ indent + "    BBOBJECT " + closeableName + " = (BBOBJECT)bbInterfaceDowncast((BBObject *)" + iteratorName + ", (BBInterface *)&brl_blitz_ICloseable_ifc);~n"
				result :+ indent + "    BBOBJECT " + exceptionName + " = (BBOBJECT)&bbNullObject;~n"
				result :+ indent + "    BBINT " + failedName + " = 0;~n"
				result :+ indent + "    bbExTry {~n"
				result :+ indent + "    case 0: {~n"
				If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPushExState();~n"
			End If
			result :+ loopIndent + "while (" + advanceExpression + ") {~n"
			result :+ loopIndent + "    BBOBJECT " + elementName + "_object = " + currentExpression + ";~n"
			Local targetType:String = CType(targetNode.semanticType, ir)
			Local convertedElement:String = elementName + "_object"
			Local filterNull:Int = True
			If adaptationNode.valueText = "object-string" Then
				result :+ loopIndent + "    if (!bbObjectIsString((BBOBJECT)" + elementName + "_object)) { continue; }~n"
				convertedElement = "((BBSTRING)bbObjectStringcast((BBOBJECT)" + elementName + "_object))"
				filterNull = False
			Else If adaptationNode.valueText = "object-numeric" Then
				convertedElement = "(*((" + targetType + "*)bbObjectToFieldOffset((BBOBJECT)" + elementName + "_object)))"
				filterNull = False
			Else If targetClass Then
				convertedElement = "((struct " + targetClass.readableAbiName + "_obj *)bbObjectDowncast((BBOBJECT)" + elementName + "_object, (BBClass *)&" + targetClass.readableAbiName + "))"
			Else If targetInterface Then
				convertedElement = "((BBOBJECT)bbInterfaceDowncast((BBOBJECT)" + elementName + "_object, (BBINTERFACE)&" + targetInterface.readableAbiName + "_ifc))"
			Else If ordinaryTargetKind = TEMPLATE_RUNTIME_CLASS Then
				convertedElement = "((struct " + ordinaryTargetAbiName + "_obj *)bbObjectDowncast((BBOBJECT)" + elementName + "_object, (BBClass *)&" + ordinaryTargetAbiName + "))"
			Else If ordinaryTargetKind = TEMPLATE_RUNTIME_INTERFACE Then
				convertedElement = "((BBOBJECT)bbInterfaceDowncast((BBOBJECT)" + elementName + "_object, (BBINTERFACE)&" + ordinaryTargetAbiName + "_ifc))"
			Else If adaptationNode.valueText = "object-checked-cast"
				diagnostics :+ ["BMXC3058 generic ObjectEnumerator target '" + adaptationNode.semanticType.CanonicalName() + "' has unknown ordinary runtime cast kind " + ordinaryTargetKind]
				Return ""
			End If
			result :+ loopIndent + "    " + targetType + " " + elementName + " = " + convertedElement + ";~n"
			If filterNull Then result :+ loopIndent + "    if ((BBOBJECT)" + elementName + " == (BBOBJECT)&bbNullObject) { continue; }~n"
			Local bodyLocals:TMap = CloneLocals(locals)
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				If ownerMethod.isIteratorRoutine Or ir.specialization.debugInstrumentation Then result :+ loopIndent + "    " + targetName + " = " + elementName + ";~n" Else result :+ loopIndent + "    " + targetType + " " + targetName + " = " + elementName + ";~n"
				result :+ loopIndent + "    (void)" + targetName + ";~n"
				bodyLocals.Insert(targetNode.valueText.ToLower(), targetName)
			Else
				result :+ loopIndent + "    " + targetName + " = " + elementName + ";~n"
			End If
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, targetNode, targetName, loopIndent + "    ")
			result :+ EmitSequentialBlock(node.children[7], ir, ownerMethod, diagnostics, bodyLocals, loopIndent + "    ")
			If hasContinue Then result :+ loopIndent + "    " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			result :+ loopIndent + "}~n"
			If persistentEach Then
				result :+ EmitGenericIteratorCleanup(closeableName, ir, indent + "    ", True)
			Else
				result :+ indent + "        bbExLeave();~n"
				If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
				result :+ indent + "    } break;~n"
				result :+ indent + "    case 1: {~n"
				If ir.specialization.debugInstrumentation Then result :+ indent + "        bbOnDebugPopExState();~n"
				result :+ indent + "        " + exceptionName + " = bbExCatch();~n"
				result :+ indent + "        " + failedName + " = 1;~n"
				result :+ indent + "    } break;~n"
				result :+ indent + "    }~n"
				result :+ EmitGenericIteratorCleanup(closeableName, ir, indent + "    ")
				result :+ indent + "    if (" + failedName + ") bbExThrow((BBObject *)" + exceptionName + ");~n"
			End If
			If hasExit Then result :+ indent + "    " + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result + indent + "}~n"
		End If
		If node.valueText.StartsWith("for-") Then
			If node.valueText <> "for-to" And node.valueText <> "for-to-down" And node.valueText <> "for-until" And node.valueText <> "for-until-down" Then
				diagnostics :+ ["BMXC3052 generic range For has unknown range identity '" + node.valueText + "'"]
				Return ""
			End If
			If node.children.length <> 5 Or Not LoopTargetNode(node.children[0]) Then
				diagnostics :+ ["BMXC3052 generic range For node requires a loop declaration or target, initializer, limit, step, and body"]
				Return ""
			End If
			Local targetNode:TGenericTemplateNode = node.children[0]
			If Not ScalarNumericType(targetNode.semanticType) Or Not ScalarNumericType(node.children[1].semanticType) Or Not ScalarNumericType(node.children[2].semanticType) Or Not ScalarNumericType(node.children[3].semanticType) Then
				diagnostics :+ ["BMXC3052 generic range For requires closed scalar numeric variable, initializer, limit, and step types"]
				Return ""
			End If
			Local localType:String = CType(targetNode.semanticType, ir)
			Local targetName:String
			Local initialization:String
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then
				If ownerMethod.isIteratorRoutine Then targetName = ownerMethod.iteratorStateExpression + "->" + GenericIteratorLocalFieldName(targetNode) Else targetName = GenericLocalName(targetNode, ir)
			Else
				targetName = EmitExpression(targetNode, ir, ownerMethod, diagnostics, locals)
			End If
			Local comparison:String = "<"
			If node.valueText.Contains("-to") Then comparison = "<="
			If node.valueText.EndsWith("-down") Then
				comparison = ">"
				If node.valueText.Contains("-to") Then comparison = ">="
			End If
			Local initialValue:String = "((" + localType + ")(" + EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + "))"
			Local limitValue:String = "((" + localType + ")(" + EmitExpression(node.children[2], ir, ownerMethod, diagnostics, locals) + "))"
			Local stepValue:String = "((" + localType + ")(" + EmitExpression(node.children[3], ir, ownerMethod, diagnostics, locals) + "))"
			If targetNode.kind = TEMPLATE_NODE_DECLARATION And Not ir.specialization.debugInstrumentation And Not ownerMethod.isIteratorRoutine Then initialization = localType + " " + targetName + " = " + initialValue Else initialization = targetName + " = " + initialValue
			Local result:String = indent + "for (" + initialization + "; " + targetName + " " + comparison + " " + limitValue + "; " + targetName + " = " + targetName + " + " + stepValue + ") {~n"
			Local bodyLocals:TMap = CloneLocals(locals)
			If targetNode.kind = TEMPLATE_NODE_DECLARATION Then bodyLocals.Insert(targetNode.valueText.ToLower(), targetName)
			result :+ PrepareLoopClosureEnvironment(node, ownerMethod, bodyLocals, targetNode, targetName, indent + "    ")
			result :+ EmitSequentialBlock(node.children[4], ir, ownerMethod, diagnostics, bodyLocals, indent + "    ")
			If hasContinue Then result :+ indent + "    " + LoopControlLabel(node.identity, "continue") + ": ;~n"
			Local rangeEnvironment:TCompilerGenericClosureEnvironmentIr = TCompilerGenericClosureEnvironmentIr(ownerMethod.activationClosureEnvironments.ValueForKey(node.identity))
			If targetNode.kind = TEMPLATE_NODE_DECLARATION And rangeEnvironment And rangeEnvironment.capturesByName.Contains(targetNode.valueText.ToLower()) Then result :+ indent + "    " + targetName + " = " + String(bodyLocals.ValueForKey(targetNode.valueText.ToLower())) + ";~n"
			result :+ indent + "}~n"
			If hasExit Then result :+ indent + LoopControlLabel(node.identity, "exit") + ": ;~n"
			Return result
		End If
		diagnostics :+ ["BMXC3051 generic loop kind '" + node.valueText + "' is unsupported"]
		Return ""
	End Function

	Function HasLoopControl:Int(node:TGenericTemplateNode, identity:String, controlKind:String)
		If Not node Then Return False
		If node.kind = TEMPLATE_NODE_LOOP_CONTROL And node.identity = identity And node.valueText = controlKind Then Return True
		For Local child:TGenericTemplateNode = EachIn node.children
			If HasLoopControl(child, identity, controlKind) Then Return True
		Next
		Return False
	End Function

	Function LoopControlLabel:String(identity:String, controlKind:String)
		Return "bmx_" + TCompilerAbiNamer.Sanitize(identity) + "_" + controlKind
	End Function

	Function InterfaceSpecialization:TGenericSpecializationNode(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		Local result:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
		If result And result.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then Return result
		Return Null
	End Function

	Function StructAbiName:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not value Then Return ""
		Local specialized:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
		If specialized And specialized.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then Return specialized.readableAbiName
		Return value.runtimeAbiName
	End Function

	Function InterfaceOperation:TCompilerGenericMethodIr(interfaceNode:TGenericSpecializationNode, operation:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not interfaceNode Or Not operation Or Not operation.referencedSymbol Then
			diagnostics :+ ["BMXC3057 generic Interface operation has no canonical symbolic identity"]
			Return Null
		End If
		Local methods:TCompilerGenericMethodIr[] = TCompilerGenericSpecializationLowerer.EffectiveInterfaceMethods(interfaceNode, ir, diagnostics)
		Local result:TCompilerGenericMethodIr
		For Local candidateMethod:TCompilerGenericMethodIr = EachIn methods
			If candidateMethod.name.ToLower() <> operation.valueText.ToLower() Then Continue
			If candidateMethod.parameters.length <> operation.children.length - 1 Or Not operation.semanticType Or candidateMethod.returnType.CanonicalName() <> operation.semanticType.CanonicalName() Then Continue
			Local signatureMatches:Int = True
			For Local parameterIndex:Int = 0 Until candidateMethod.parameters.length
				If Not operation.children[parameterIndex + 1].semanticType Or candidateMethod.parameters[parameterIndex].semanticType.CanonicalName() <> operation.children[parameterIndex + 1].semanticType.CanonicalName() Then
					signatureMatches = False
					Exit
				End If
			Next
			If Not signatureMatches Then Continue
			If result Then
				diagnostics :+ ["BMXC3057 generic Interface operation '" + operation.valueText + "' is ambiguous after specialization"]
				Return Null
			End If
			result = candidateMethod
		Next
		If Not result Then diagnostics :+ ["BMXC3057 generic Interface operation '" + operation.valueText + "' has no emitted canonical slot"]
		Return result
	End Function

	Function ImplementedInterfaceForOperation:TGenericSpecializationNode(typeNode:TGenericSpecializationNode, operation:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not typeNode Or Not operation Then Return Null
		Local result:TGenericSpecializationNode
		Local current:TGenericSpecializationNode = typeNode
		While current
			Local typeIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(current, diagnostics)
			If Not typeIr Then Return Null
			For Local candidate:TGenericSpecializationNode = EachIn typeIr.implementedInterfaces
				Local candidateDiagnostics:String[]
				Local candidateMethod:TCompilerGenericMethodIr = InterfaceOperation(candidate, operation, ir, candidateDiagnostics)
				If Not candidateMethod Then Continue
				Local declaringInterface:TGenericSpecializationNode = candidateMethod.declaringSpecialization
				If Not declaringInterface Then declaringInterface = candidate
				If result And result.key.CanonicalName() = declaringInterface.key.CanonicalName() Then Continue
				If result Then
					diagnostics :+ ["BMXC3057 generic Type EachIn operation '" + operation.valueText + "' is supplied by more than one implemented Interface"]
					Return Null
				End If
				result = declaringInterface
			Next
			current = typeIr.baseSpecialization
		Wend
		If Not result Then diagnostics :+ ["BMXC3057 generic Type EachIn operation '" + operation.valueText + "' has no canonical implemented Interface"]
		Return result
	End Function

	Function EmitInterfaceOperation:String(interfaceNode:TGenericSpecializationNode, operation:TGenericTemplateNode, operationMethod:TCompilerGenericMethodIr, receiver:String, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap)
		Local receiverPrefix:String
		receiver = StabilizeCallReceiver(operation, receiver, receiverPrefix)
		Local result:String = "((struct " + interfaceNode.readableAbiName + "_methods *)bbObjectInterface((BBOBJECT)" + receiver + ", (BBInterface *)&" + interfaceNode.readableAbiName + "_ifc))->" + operationMethod.slotName + "((BBOBJECT)" + receiver
		For Local index:Int = 1 Until operation.children.length
			result :+ ", " + EmitCallArgument(operation.children[index], operationMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
		Next
		Return WrapStabilizedCall(result + ")", receiverPrefix)
	End Function

	Function EmitInterfaceCall:String(interfaceNode:TGenericSpecializationNode, operation:TGenericTemplateNode, operationMethod:TCompilerGenericMethodIr, receiver:String, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap)
		Local receiverPrefix:String
		receiver = StabilizeCallReceiver(operation, receiver, receiverPrefix)
		Local result:String = InterfaceCallHelperName(interfaceNode, operationMethod) + "((BBOBJECT)" + receiver
		For Local index:Int = 1 Until operation.children.length
			result :+ ", " + EmitCallArgument(operation.children[index], operationMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
		Next
		Return WrapStabilizedCall(result + ")", receiverPrefix)
	End Function

	Function TypeSpecialization:TGenericSpecializationNode(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		Local result:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
		If result And result.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_CLASS Then Return result
		Return Null
	End Function

	Function TypeOperation:TCompilerGenericMethodIr(typeNode:TGenericSpecializationNode, operation:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not typeNode Or Not operation Or Not operation.referencedSymbol Then
			diagnostics :+ ["BMXC3058 generic Type operation has no canonical symbolic identity"]
			Return Null
		End If
		Local typeIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(typeNode, diagnostics)
		If Not typeIr Then Return Null
		Local result:TCompilerGenericMethodIr
		Local staticOperation:Int = operation.children.length And operation.children[0].kind = TEMPLATE_NODE_BLOCK And operation.children[0].valueText = "static-type-receiver"
		For Local candidateMethod:TCompilerGenericMethodIr = EachIn typeIr.methods
			If candidateMethod.name.ToLower() <> operation.valueText.ToLower() Then Continue
			If candidateMethod.isTypeFunction Then
				' A Type Function accepts either a Type qualifier or an object
				' qualifier. The latter retains virtual class-slot selection.
			Else If candidateMethod.isStatic <> staticOperation Then
				Continue
			End If
			If candidateMethod.parameters.length <> operation.children.length - 1 Or Not operation.semanticType Or candidateMethod.returnType.CanonicalName() <> operation.semanticType.CanonicalName() Then Continue
			Local signatureMatches:Int = True
			For Local parameterIndex:Int = 0 Until candidateMethod.parameters.length
				If Not operation.children[parameterIndex + 1].semanticType Or candidateMethod.parameters[parameterIndex].semanticType.CanonicalName() <> operation.children[parameterIndex + 1].semanticType.CanonicalName() Then
					signatureMatches = False
					Exit
				End If
			Next
			If Not signatureMatches Then Continue
			If result Then
				diagnostics :+ ["BMXC3058 generic Type operation '" + operation.valueText + "' is ambiguous after specialization"]
				Return Null
			End If
			result = candidateMethod
		Next
		If Not result Then diagnostics :+ ["BMXC3058 generic Type operation '" + operation.valueText + "' has no emitted canonical class slot"]
		Return result
	End Function

	Function StabilizeCallReceiver:String(operation:TGenericTemplateNode, receiver:String, prefix:String Var)
		If Not operation Or Not operation.identity.Contains("materialized-receiver:") Then Return receiver
		Local temporaryName:String = CallReceiverTemporaryName(operation)
		prefix = temporaryName + " = " + receiver + ", "
		Return temporaryName
	End Function

	Function WrapStabilizedCall:String(callExpression:String, prefix:String)
		If prefix.length Then Return "(" + prefix + callExpression + ")"
		Return callExpression
	End Function

	Function EmitTypeOperation:String(typeNode:TGenericSpecializationNode, operation:TGenericTemplateNode, operationMethod:TCompilerGenericMethodIr, receiver:String, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap)
		Local ownerNode:TGenericSpecializationNode = typeNode
		If operationMethod And operationMethod.declaringSpecialization Then ownerNode = operationMethod.declaringSpecialization
		Local staticOperation:Int = operation.children.length And operation.children[0].kind = TEMPLATE_NODE_BLOCK And operation.children[0].valueText = "static-type-receiver"
		If operationMethod.isStatic Or (operationMethod.isTypeFunction And staticOperation) Then
			Local staticResult:String = operationMethod.abiName + "("
			For Local index:Int = 1 Until operation.children.length
				If index > 1 Then staticResult :+ ", "
				staticResult :+ EmitCallArgument(operation.children[index], operationMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
			Next
			Return staticResult + ")"
		End If
		Local receiverPrefix:String
		receiver = StabilizeCallReceiver(operation, receiver, receiverPrefix)
		Local result:String = receiver + "->clas->" + operationMethod.slotName + "("
		If Not operationMethod.isTypeFunction Then result :+ "(struct " + ownerNode.readableAbiName + "_obj *)" + receiver
		For Local index:Int = 1 Until operation.children.length
			If index > 1 Or Not operationMethod.isTypeFunction Then result :+ ", "
			result :+ EmitCallArgument(operation.children[index], operationMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
		Next
		Return WrapStabilizedCall(result + ")", receiverPrefix)
	End Function

	Function EmitOrdinaryClassOperation:String(operation:TGenericTemplateNode, receiver:String, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, ownerMethod:TCompilerGenericMethodIr = Null, locals:TMap = Null)
		If Not operation Or operation.runtimeDispatchKind <> TEMPLATE_DISPATCH_ORDINARY_CLASS Or operation.runtimeDispatchIndex < 0 Or operation.runtimeDispatchIndex >= 40 Or Not operation.children.length Then
			diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator operation has no valid runtime virtual-slot ordinal"]
			Return ""
		End If
		Local returnType:String = CType(operation.semanticType, ir)
		Local receiverType:String = CType(operation.children[0].semanticType, ir)
		If Not returnType.length Or Not receiverType.length Then
			diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator operation '" + operation.valueText + "' has no supported closed ABI signature"]
			Return ""
		End If
		Local signatureParameters:String = receiverType
		For Local index:Int = 1 Until operation.children.length
			Local passingMode:Int = PARAMETER_PASS_VALUE
			If operation.children[index].kind = TEMPLATE_NODE_CONVERSION And (operation.children[index].valueText = CONVERSION_VAR_REFERENCE Or operation.children[index].valueText = CONVERSION_POINTER_TO_VAR_REFERENCE) Then passingMode = PARAMETER_PASS_VAR
			Local argumentType:String = CValueDeclaration(operation.children[index].semanticType, "", ir, passingMode)
			If Not argumentType.length Then
				diagnostics :+ ["BMXC3059 ordinary Type operation '" + operation.valueText + "' argument " + index + " has no supported closed ABI type"]
				Return ""
			End If
			signatureParameters :+ ", " + argumentType
		Next
		Local receiverPrefix:String
		receiver = StabilizeCallReceiver(operation, receiver, receiverPrefix)
		Local result:String = "((" + CFunctionPointerDeclaration(operation.semanticType, "", signatureParameters, ir) + ")((BBObject *)" + receiver + ")->clas->vfns[" + operation.runtimeDispatchIndex + "])((" + receiverType + ")" + receiver
		For Local index:Int = 1 Until operation.children.length
			If operation.children[index].kind = TEMPLATE_NODE_CONVERSION And (operation.children[index].valueText = CONVERSION_VAR_REFERENCE Or operation.children[index].valueText = CONVERSION_POINTER_TO_VAR_REFERENCE) Then
				Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
				parameter.semanticType = operation.children[index].semanticType
				parameter.passingMode = PARAMETER_PASS_VAR
				result :+ ", " + EmitCallArgument(operation.children[index], parameter, ir, ownerMethod, diagnostics, locals)
			Else
				result :+ ", " + EmitExpression(operation.children[index], ir, ownerMethod, diagnostics, locals)
			End If
		Next
		Return WrapStabilizedCall(result + ")", receiverPrefix)
	End Function

	Function EmitOrdinaryInterfaceOperation:String(operation:TGenericTemplateNode, receiver:String, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var, ownerMethod:TCompilerGenericMethodIr = Null, locals:TMap = Null)
		If Not operation Or operation.runtimeDispatchKind <> TEMPLATE_DISPATCH_ORDINARY_CLASS Or operation.runtimeDispatchIndex < 0 Or Not operation.children.length Or Not operation.referencedSymbol Or Not operation.referencedSymbol.overloadKey.length Then
			diagnostics :+ ["BMXC3057 ordinary Interface operation has no stable descriptor and slot identity"]
			Return ""
		End If
		Local returnType:String = CType(operation.semanticType, ir)
		If Not returnType.length Then
			diagnostics :+ ["BMXC3057 ordinary Interface operation '" + operation.valueText + "' has no supported closed return ABI"]
			Return ""
		End If
		For Local index:Int = 1 Until operation.children.length
			Local argumentType:String = CType(operation.children[index].semanticType, ir)
			If Not argumentType.length Then
				diagnostics :+ ["BMXC3057 ordinary Interface operation '" + operation.valueText + "' argument " + index + " has no supported closed ABI type"]
				Return ""
			End If
		Next
		Local helperName:String = OrdinaryInterfaceHelperName(operation)
		If Not helperName.length Then
			diagnostics :+ ["BMXC3057 ordinary Interface operation '" + operation.valueText + "' has no deterministic call helper identity"]
			Return ""
		End If
		Local receiverPrefix:String
		receiver = StabilizeCallReceiver(operation, receiver, receiverPrefix)
		Local result:String = helperName + "((BBOBJECT)" + receiver
		For Local index:Int = 1 Until operation.children.length
			If operation.children[index].kind = TEMPLATE_NODE_CONVERSION And (operation.children[index].valueText = CONVERSION_VAR_REFERENCE Or operation.children[index].valueText = CONVERSION_POINTER_TO_VAR_REFERENCE) Then
				Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
				parameter.semanticType = operation.children[index].semanticType
				parameter.passingMode = PARAMETER_PASS_VAR
				result :+ ", " + EmitCallArgument(operation.children[index], parameter, ir, ownerMethod, diagnostics, locals)
			Else
				result :+ ", " + EmitExpression(operation.children[index], ir, ownerMethod, diagnostics, locals)
			End If
		Next
		Return WrapStabilizedCall(result + ")", receiverPrefix)
	End Function

	Function OrdinaryInterfaceHelperName:String(operation:TGenericTemplateNode)
		If Not operation Or Not operation.referencedSymbol Or Not operation.referencedSymbol.overloadKey.length Or operation.runtimeDispatchIndex < 0 Then Return ""
		Return "bmx_ord_ifc_" + TCompilerAbiNamer.Sanitize(operation.referencedSymbol.overloadKey + "_" + operation.runtimeDispatchIndex + "_" + operation.valueText)
	End Function

	Function IsObjectType:Int(value:TTemplateTypeReference)
		Return value And value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "object"
	End Function

	Function IsNullType:Int(value:TTemplateTypeReference)
		Return value And value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "null"
	End Function

	Function NullValueForType:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If value And value.kind = TEMPLATE_TYPE_ARRAY Then Return "&bbEmptyArray"
		If value And value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "string" Then Return "&bbEmptyString"
		If ManagedReferenceType(value, ir) Then Return "((" + CType(value, ir) + ")&bbNullObject)"
		Return DefaultValue(value, ir)
	End Function

	Function ManagedReferenceType:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not value Then Return False
		If IsObjectType(value) Then Return True
		If value.kind = TEMPLATE_TYPE_ARRAY Then Return True
		If value.kind = TEMPLATE_TYPE_CLOSURE Then Return True
		If value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "string" Then Return True
		If value.kind <> TEMPLATE_TYPE_NAMED Then Return False
		If value.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then Return True
		Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
		Return referenced And referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT
	End Function

	Function DebugManagedValue:String(result:String, value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		If Not ir Or Not ir.specialization Or Not ir.specialization.debugInstrumentation Or Not value Then Return result
		If value.kind = TEMPLATE_TYPE_ARRAY Then Return "bbManagedArrayAssert((BBARRAY)" + result + ")"
		If value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "string" Then Return "bbManagedStringAssert((BBSTRING)" + result + ")"
		If ManagedReferenceType(value, ir) Then Return "((" + CType(value, ir) + ")bbManagedObjectAssert((BBOBJECT)" + result + "))"
		Return result
	End Function

	Function TruthTypeSupported:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		Return ScalarNumericType(value) Or (value And value.kind = TEMPLATE_TYPE_POINTER) Or ManagedReferenceType(value, ir)
	End Function

	Function IteratorElementTypeSupported:Int(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		Return TCompilerGenericSpecializationLowerer.SupportedType(value, ir)
	End Function

	Function EmitConditionExpression:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap)
		Local result:String = EmitExpression(node, ir, ownerMethod, diagnostics, locals)
		If node And node.semanticType Then
			result = DebugManagedValue(result, node.semanticType, ir)
			If node.semanticType.kind = TEMPLATE_TYPE_ARRAY Then Return "(" + result + " != &bbEmptyArray)"
			If node.semanticType.kind = TEMPLATE_TYPE_BUILTIN And node.semanticType.symbolName.ToLower() = "string" Then Return "(" + result + " != &bbEmptyString)"
			If ManagedReferenceType(node.semanticType, ir) And Not ScalarNumericType(node.semanticType) Then Return "((BBOBJECT)" + result + " != (BBOBJECT)&bbNullObject)"
		End If
		If result.StartsWith("(") And result.EndsWith(")") Then Return result
		Return "(" + result + ")"
	End Function

	Function CloneLocals:TMap(source:TMap)
		Local result:TMap = New TMap
		If Not source Then Return result
		For Local key:Object = EachIn source.Keys()
			result.Insert(key, source.ValueForKey(key))
		Next
		Return result
	End Function

	Function EmitExpression:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap = Null)
		If Not node Then Return "0"
		Select node.kind
			Case TEMPLATE_NODE_FUNCTION_LITERAL
				Local literalRoutine:TCompilerGenericMethodIr = ClosureLiteralIr(ownerMethod, node, ir, diagnostics)
				If Not literalRoutine Then Return DefaultValue(node.semanticType, ir)
				If Not literalRoutine.isClosureInvoke Then Return "(&" + literalRoutine.abiName + ")"
				If literalRoutine.closureCaptures.length Then
					Local literalEnvironment:TCompilerGenericClosureEnvironmentIr = ClosureEnvironmentForCaptures(ownerMethod, literalRoutine.closureCaptures)
					If Not literalEnvironment Then
						diagnostics :+ ["BMXC1243 generic capturing Closure literal has no specialization-owned environment"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Return literalEnvironment.abiName + "_closure_new((BBFuncPtr)&" + literalRoutine.abiName + ", (BBOBJECT)" + literalEnvironment.localName + ")"
				End If
				Return "(&" + literalRoutine.abiName + "_value)"
			Case TEMPLATE_NODE_NAME
				If node.identity = "generic-routine-callable-reference" Then
					Local routineTarget:TGenericSpecializationNode = ReferencedRoutineCall(node, ir)
					If routineTarget Then Return routineTarget.readableAbiName
					diagnostics :+ ["BMXC3027 generic routine reference '" + node.valueText + "' has no canonical referenced specialization"]
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.identity = "specialization-static" Then
					Local staticField:TCompilerGenericFieldIr = StaticFieldForNode(node, ir, diagnostics)
					If staticField Then Return staticField.abiName
					diagnostics :+ ["BMXC3025 specialization body refers to unknown static member '" + node.valueText + "'"]
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.identity = "ordinary-global" Then
					Local specializationStatic:TCompilerGenericFieldIr = StaticFieldForUnqualifiedOrdinaryGlobal(node, ir)
					If specializationStatic Then Return specializationStatic.abiName
					If node.referencedSymbol And node.referencedSymbol.overloadKey.length Then Return node.referencedSymbol.overloadKey
				End If
				If node.identity = "ordinary-callable-reference" And node.referencedSymbol And node.referencedSymbol.overloadKey.length Then Return node.referencedSymbol.overloadKey
				If locals And locals.Contains(node.valueText.ToLower()) Then Return String(locals.ValueForKey(node.valueText.ToLower()))
				For Local parameter:TGenericTemplateValueParameter = EachIn ownerMethod.parameters
					If parameter.name.ToLower() = node.valueText.ToLower() Then
						Local parameterName:String = TCompilerAbiNamer.Sanitize(parameter.name)
						If parameter.passingMode = PARAMETER_PASS_VAR Then Return "(*" + parameterName + ")"
						Return parameterName
					End If
				Next
				diagnostics :+ ["BMXC3025 specialization body refers to unknown parameter or local '" + node.valueText + "'"]
			Case TEMPLATE_NODE_SELF
				Local receiverType:String = CType(node.semanticType, ir)
				If ownerMethod And ownerMethod.isIteratorRoutine And ownerMethod.iteratorSelfExpression.length Then Return "((" + receiverType + ")" + ownerMethod.iteratorSelfExpression + ")"
				Local capturedSelf:TCompilerGenericClosureCaptureIr = ClosureCaptureForName(ownerMethod, "Self")
				If capturedSelf Then Return "((" + receiverType + ")" + ClosureCaptureExpression(ownerMethod, capturedSelf) + ")"
				If Not receiverType.length Then
					diagnostics :+ ["BMXC3061 generic " + node.valueText + " receiver has no canonical ABI"]
					Return DefaultValue(node.semanticType, ir)
				End If
				If ownerMethod And ownerMethod.receiverIsStruct Then Return "(*((" + receiverType + " *)self))"
				Return "((" + receiverType + ")self)"
			Case TEMPLATE_NODE_MEMBER
				If node.children.length = 1 Then
					Local memberReceiver:TGenericTemplateNode = node.children[0]
					Local receiverExpression:String = EmitExpression(memberReceiver, ir, ownerMethod, diagnostics, locals)
					Local receiverNode:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(memberReceiver.semanticType, ir)
					Local receiverFieldName:String
					Local receiverIsStruct:Int
					If receiverNode Then
						Local memberReceiverIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(receiverNode, diagnostics)
						If memberReceiverIr Then
							receiverIsStruct = receiverNode.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT
							For Local receiverField:TCompilerGenericFieldIr = EachIn memberReceiverIr.fields
								If FieldMatchesNode(receiverField, node) Then
									receiverFieldName = receiverField.abiName
									Exit
								End If
							Next
						End If
					Else If memberReceiver.semanticType And memberReceiver.semanticType.runtimeAbiName.length Then
						receiverIsStruct = memberReceiver.semanticType.runtimeKind = TEMPLATE_RUNTIME_STRUCT
						receiverFieldName = TCompilerAbiNamer.FieldName(memberReceiver.semanticType.runtimeAbiName, node.valueText)
					End If
					If receiverFieldName.length Then
						If receiverIsStruct Then Return "(" + receiverExpression + ")." + receiverFieldName
						Return "(" + receiverExpression + ")->" + receiverFieldName
					End If
				End If
				For Local irField:TCompilerGenericFieldIr = EachIn ir.fields
					If FieldMatchesNode(irField, node) Then Return ClosureSelfExpression(ownerMethod) + "->" + irField.abiName
				Next
				For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
					If staticField.name.ToLower() = node.valueText.ToLower() Then Return staticField.abiName
				Next
				If ir.isRoutine And ownerMethod And ownerMethod.receiverType Then
					Local receiverNode:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(ownerMethod.receiverType, ir)
					Local receiverIr:TCompilerGenericSpecializationIr
					If receiverNode Then receiverIr = TCompilerGenericSpecializationLowerer.Lower(receiverNode, diagnostics)
					If receiverIr Then
						For Local receiverField:TCompilerGenericFieldIr = EachIn receiverIr.fields
							If FieldMatchesNode(receiverField, node) Then Return ClosureSelfExpression(ownerMethod) + "->" + receiverField.abiName
						Next
					End If
					If ownerMethod.receiverType.runtimeKind <> TEMPLATE_RUNTIME_NONE Then
						For Local ownerField:TGenericTemplateMember = EachIn ir.specialization.artifact.containingFields
							Local matchesField:Int
							If node.referencedSymbol Then
								matchesField = ownerField.identity = "field:" + node.referencedSymbol.StableName()
							Else
								matchesField = ownerField.name.ToLower() = node.valueText.ToLower()
							End If
							If matchesField Then
								Local fieldLinkageName:String = ownerField.linkageName
								If Not fieldLinkageName.length Then fieldLinkageName = TCompilerAbiNamer.FieldName(ownerMethod.receiverType.runtimeAbiName, ownerField.name)
								Return ClosureSelfExpression(ownerMethod) + "->" + fieldLinkageName
							End If
						Next
					End If
				End If
				diagnostics :+ ["BMXC3025 specialization body refers to unknown field '" + node.valueText + "'"]
			Case TEMPLATE_NODE_ARRAY_LENGTH
				If node.children.length <> 1 Or Not TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(node.children[0].semanticType, ir) Then
					diagnostics :+ ["BMXC3063 generic managed Array length requires one closed one-dimensional Array receiver"]
					Return "0"
				End If
				Return "(" + DebugManagedValue(EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals), node.children[0].semanticType, ir) + "->scales[0])"
			Case TEMPLATE_NODE_ARRAY_ELEMENT
				If node.children.length < 2 Or Not node.children[0].semanticType Then
					diagnostics :+ ["BMXC3063 generic Array element access requires a closed receiver and integral indexes"]
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.children[0].semanticType.kind = TEMPLATE_TYPE_STATIC_ARRAY Then
					If node.children.length <> 2 Or Not TCompilerGenericSpecializationLowerer.SupportedStaticArrayType(node.children[0].semanticType, ir) Or Not ScalarIntegralType(node.children[1].semanticType) Then
						diagnostics :+ ["BMXC3063 generic StaticArray element access requires one integral index"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Return EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + "[" + EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + "]"
				End If
				If Not TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(node.children[0].semanticType, ir) Or node.children.length <> node.children[0].semanticType.rank + 1 Then
					diagnostics :+ ["BMXC3063 generic managed Array element access index count does not match its closed rank"]
					Return DefaultValue(node.semanticType, ir)
				End If
				For Local indexNodeIndex:Int = 1 Until node.children.length
					If Not ScalarIntegralType(node.children[indexNodeIndex].semanticType) Then
						diagnostics :+ ["BMXC3063 generic managed Array element access requires integral indexes"]
						Return DefaultValue(node.semanticType, ir)
					End If
				Next
				Local arrayElementType:String = CType(node.semanticType, ir)
				If Not arrayElementType.length Then
					diagnostics :+ ["BMXC3063 generic managed Array element has no closed C ABI"]
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.children[0].semanticType.rank = 1 And Not node.identity.StartsWith("materialized-receiver") Then
					Return "((" + arrayElementType + "*)BBARRAYDATA(" + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ", 1))[" + EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + "]"
				End If
				Local arrayReceiver:String = EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals)
				Local receiverPrefix:String
				If node.identity.StartsWith("materialized-receiver") Then
					Local receiverTemporary:String = ArrayReceiverTemporaryName(node)
					receiverPrefix = receiverTemporary + " = " + arrayReceiver + ", "
					arrayReceiver = receiverTemporary
				End If
				Local linearIndex:String
				For Local dimensionIndex:Int = 1 Until node.children.length
					If linearIndex.length Then linearIndex :+ " + "
					Local indexValue:String = EmitExpression(node.children[dimensionIndex], ir, ownerMethod, diagnostics, locals)
					If dimensionIndex < node.children.length - 1 Then linearIndex :+ "((" + indexValue + ") * " + arrayReceiver + "->scales[" + dimensionIndex + "])" Else linearIndex :+ "(" + indexValue + ")"
				Next
				Return "(" + receiverPrefix + "((" + arrayElementType + "*)BBARRAYDATA(" + arrayReceiver + ", 1))[" + linearIndex + "])"
			Case TEMPLATE_NODE_ARRAY_SLICE
				If node.children.length <> 3 Or Not TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(node.children[0].semanticType, ir) Or Not ScalarIntegralType(node.children[1].semanticType) Or Not ScalarIntegralType(node.children[2].semanticType) Then
					diagnostics :+ ["BMXC3064 generic managed Array slice requires one closed one-dimensional Array receiver and integral lower and upper bounds"]
					Return "&bbEmptyArray"
				End If
				Local sliceReceiver:String = DebugManagedValue(EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals), node.children[0].semanticType, ir)
				Local slicePrefix:String
				If node.identity.StartsWith("materialized-receiver") Then
					Local sliceTemporary:String = ArrayReceiverTemporaryName(node)
					slicePrefix = sliceTemporary + " = " + sliceReceiver + ", "
					sliceReceiver = sliceTemporary
				End If
				Local sliceUpper:String
				If node.children[2].kind = TEMPLATE_NODE_ARRAY_LENGTH Then sliceUpper = "(" + sliceReceiver + "->scales[0])" Else sliceUpper = EmitExpression(node.children[2], ir, ownerMethod, diagnostics, locals)
				If node.children[0].semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
					Local structSlice:String = "bbArraySliceStruct_" + StructAbiName(node.children[0].semanticType.elementType, ir) + "(" + sliceReceiver + ", " + EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + ", " + sliceUpper + ")"
					If slicePrefix.length Then Return "(" + slicePrefix + structSlice + ")"
					Return structSlice
				End If
				Local sliceEncoding:String = ArrayElementEncoding(node.children[0].semanticType.elementType, ir)
				If Not sliceEncoding.length Then
					diagnostics :+ ["BMXC3064 generic managed Array slice element has no runtime encoding"]
					Return "&bbEmptyArray"
				End If
				Local ordinarySlice:String = "bbArraySlice(~q" + sliceEncoding + "~q, " + sliceReceiver + ", " + EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + ", " + sliceUpper + ")"
				If slicePrefix.length Then Return "(" + slicePrefix + ordinarySlice + ")"
				Return ordinarySlice
			Case TEMPLATE_NODE_ARRAY_LITERAL
				If Not TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(node.semanticType, ir) Then
					diagnostics :+ ["BMXC3070 generic managed Array literal requires a closed supported one-dimensional element ABI"]
					Return "&bbEmptyArray"
				End If
				If Not node.children.length Then Return "&bbEmptyArray"
				Local elementEncoding:String = ArrayElementEncoding(node.semanticType.elementType, ir)
				Local elementType:String = CType(node.semanticType.elementType, ir)
				If Not elementEncoding.length Or Not elementType.length Then
					diagnostics :+ ["BMXC3070 generic managed Array literal element has no runtime encoding"]
					Return "&bbEmptyArray"
				End If
				Local temporaryName:String = ArrayLiteralTemporaryName(node)
				Local allocation:String
				If node.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
					allocation = "bbArrayNew1DStruct_" + StructAbiName(node.semanticType.elementType, ir) + "(" + node.children.length + ")"
				Else If node.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_ENUM Then
					allocation = "bbArrayNew1DEnum(~q" + elementEncoding + "~q, " + node.children.length + ", " + node.semanticType.elementType.runtimeAbiName + "_BBEnum_impl)"
				Else
					allocation = "bbArrayNew1D(~q" + elementEncoding + "~q, " + node.children.length + ")"
				End If
				Local arrayLiteral:String = "(" + temporaryName + " = " + allocation
				For Local index:Int = 0 Until node.children.length
					arrayLiteral :+ ", ((" + elementType + "*)BBARRAYDATA(" + temporaryName + ", 1))[" + index + "] = " + EmitExpression(node.children[index], ir, ownerMethod, diagnostics, locals)
				Next
				Return arrayLiteral + ", " + temporaryName + ")"
			Case TEMPLATE_NODE_LITERAL
				If node.valueText.ToLower() = "true" Then Return "1"
				If node.valueText.ToLower() = "false" Then Return "0"
				If node.valueText.ToLower() = "null" Then Return "(BBOBJECT)&bbNullObject"
				If node.identity = "string-code-units" Then Return EmitStringCodeUnits(node.valueText)
				If node.valueText.StartsWith("$") Then Return "0x" + node.valueText[1..]
				Return node.valueText
			Case TEMPLATE_NODE_OPERATOR
				If node.children.length = 1 Then
					If Not UnaryOperandsSupported(node.valueText, node.children[0].semanticType) And Not (node.valueText.ToLower() = "not" And TruthTypeSupported(node.children[0].semanticType, ir)) Then
						diagnostics :+ ["BMXC3047 generic unary operator '" + node.valueText + "' requires a closed scalar numeric operand"]
						Return DefaultValue(node.semanticType, ir)
					End If
					If node.valueText.ToLower() = "not" And TruthTypeSupported(node.children[0].semanticType, ir) Then Return "(!" + EmitConditionExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ")"
					Local unaryOperator:String = CUnaryOperator(node.valueText)
					If unaryOperator.length Then Return "(" + unaryOperator + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ")"
				Else If node.children.length = 2 Then
					Local stringConcatenation:Int = node.valueText = "+" And StringTemplateType(node.semanticType) And StringConcatOperandSupported(node.children[0].semanticType) And StringConcatOperandSupported(node.children[1].semanticType)
					Local arrayConcatenation:Int = node.valueText = "+" And node.semanticType And node.children[0].semanticType And node.children[1].semanticType And node.semanticType.kind = TEMPLATE_TYPE_ARRAY And node.semanticType.rank = 1 And node.semanticType.CanonicalName() = node.children[0].semanticType.CanonicalName() And node.semanticType.CanonicalName() = node.children[1].semanticType.CanonicalName() And TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(node.semanticType, ir)
					Local logicalTruthOperands:Int = (node.valueText.ToLower() = "and" Or node.valueText.ToLower() = "or") And TruthTypeSupported(node.children[0].semanticType, ir) And TruthTypeSupported(node.children[1].semanticType, ir)
					Local ordinaryStructEquality:Int = (node.valueText = "=" Or node.valueText = "<>") And node.children[0].semanticType And node.children[1].semanticType And node.children[0].semanticType.runtimeKind = TEMPLATE_RUNTIME_STRUCT And node.children[0].semanticType.runtimeEqualityAbiName.length And node.children[0].semanticType.CanonicalName() = node.children[1].semanticType.CanonicalName()
					If Not BinaryOperandsSupported(node.valueText, node.children[0].semanticType, node.children[1].semanticType, ir) And Not logicalTruthOperands And Not stringConcatenation And Not arrayConcatenation And Not ordinaryStructEquality Then
						Local leftName:String = "<unknown>"
						Local rightName:String = "<unknown>"
						If node.children[0].semanticType Then leftName = node.children[0].semanticType.CanonicalName()
						If node.children[1].semanticType Then rightName = node.children[1].semanticType.CanonicalName()
						diagnostics :+ ["BMXC3047 generic binary operator '" + node.valueText + "' requires supported closed operands; received '" + leftName + "' and '" + rightName + "'"]
						Return DefaultValue(node.semanticType, ir)
					End If
					If stringConcatenation Then Return "bbStringConcat(" + EmitStringConcatOperand(node.children[0], ir, ownerMethod, diagnostics, locals) + ", " + EmitStringConcatOperand(node.children[1], ir, ownerMethod, diagnostics, locals) + ")"
					If arrayConcatenation Then
						Local elementEncoding:String = ArrayElementEncoding(node.semanticType.elementType, ir)
						If Not elementEncoding.length Then
							diagnostics :+ ["BMXC3047 generic Array concatenation element type has no runtime encoding"]
							Return DefaultValue(node.semanticType, ir)
						End If
						Return "bbArrayConcat(~q" + elementEncoding + "~q, " + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ", " + EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + ")"
					End If
					If ordinaryStructEquality Then
						Local structEquality:String = node.children[0].semanticType.runtimeEqualityAbiName + "(&(" + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + "), " + EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + ")"
						If node.valueText = "<>" Then Return "(!" + structEquality + ")"
						Return structEquality
					End If
					Local binaryOperator:String = CBinaryOperator(node.valueText)
					If binaryOperator.length Then
						If logicalTruthOperands Then Return "(" + EmitConditionExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + " " + binaryOperator + " " + EmitConditionExpression(node.children[1], ir, ownerMethod, diagnostics, locals) + ")"
						Local leftExpression:String = EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals)
						Local rightExpression:String = EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals)
						If IsNullType(node.children[0].semanticType) And ManagedReferenceType(node.children[1].semanticType, ir) Then leftExpression = NullValueForType(node.children[1].semanticType, ir)
						If IsNullType(node.children[1].semanticType) And ManagedReferenceType(node.children[0].semanticType, ir) Then rightExpression = NullValueForType(node.children[0].semanticType, ir)
						Local leftString:Int = node.children[0].semanticType.kind = TEMPLATE_TYPE_BUILTIN And node.children[0].semanticType.symbolName.ToLower() = "string"
						Local rightString:Int = node.children[1].semanticType.kind = TEMPLATE_TYPE_BUILTIN And node.children[1].semanticType.symbolName.ToLower() = "string"
						If leftString Or rightString Then
							If node.valueText = "=" Then Return "(bbStringEquals(" + leftExpression + ", " + rightExpression + ") == 1)"
							If node.valueText = "<>" Then Return "(bbStringEquals(" + leftExpression + ", " + rightExpression + ") != 1)"
							Return "(bbStringCompare(" + leftExpression + ", " + rightExpression + ") " + binaryOperator + " 0)"
						End If
						Return "(" + leftExpression + " " + binaryOperator + " " + rightExpression + ")"
					End If
				End If
				diagnostics :+ ["BMXC3047 generic intrinsic operator '" + node.valueText + "' has no scalar C99 lowering"]
			Case TEMPLATE_NODE_CONVERSION
				If node.children.length = 1 And StringTemplateType(node.semanticType) And ScalarNumericType(node.children[0].semanticType) Then
					Return NumericToString(EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals), node.children[0].semanticType, diagnostics)
				End If
				If node.children.length = 1 And ScalarNumericType(node.semanticType) And ScalarNumericType(node.children[0].semanticType) Then
					Return "((" + CType(node.semanticType, ir) + ")" + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ")"
				End If
				If node.children.length = 1 And IsNullType(node.children[0].semanticType) And ScalarNumericType(node.semanticType) Then
					Return "((" + CType(node.semanticType, ir) + ")0)"
				End If
				If node.children.length = 1 And IsNullType(node.children[0].semanticType) And node.semanticType And node.semanticType.kind = TEMPLATE_TYPE_POINTER Then
					Return "((" + CType(node.semanticType, ir) + ")0)"
				End If
				If node.children.length = 1 And IsNullType(node.children[0].semanticType) And node.semanticType And node.semanticType.kind = TEMPLATE_TYPE_CALLABLE Then
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.children.length = 1 And IsNullType(node.children[0].semanticType) And ManagedReferenceType(node.semanticType, ir) Then
					Return NullValueForType(node.semanticType, ir)
				End If
				If node.children.length = 1 And IsNullType(node.children[0].semanticType) And node.semanticType And node.semanticType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.children.length = 1 And IsNullType(node.children[0].semanticType) And node.semanticType And node.semanticType.runtimeKind = TEMPLATE_RUNTIME_ENUM Then
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.children.length = 1 And ManagedReferenceType(node.children[0].semanticType, ir) And node.semanticType And node.semanticType.kind = TEMPLATE_TYPE_ARRAY Then
					Local targetEncoding:String = ArrayElementEncoding(node.semanticType.elementType, ir)
					If Not targetEncoding.length Then
						diagnostics :+ ["BMXC3047 generic Object-to-Array conversion target has no runtime element encoding"]
						Return "&bbEmptyArray"
					End If
					Return "bbArrayCastFromObject((BBOBJECT)" + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ", ~q" + targetEncoding + "~q)"
				End If
				If node.children.length = 1 And ManagedReferenceType(node.children[0].semanticType, ir) And ManagedReferenceType(node.semanticType, ir) Then
					Local managedOperand:String = EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals)
					If node.valueText = CONVERSION_EXPLICIT Then
						If StringTemplateType(node.semanticType) Then Return "((BBSTRING)bbObjectStringcast((BBOBJECT)" + managedOperand + "))"
						Local managedClass:TGenericSpecializationNode = TypeSpecialization(node.semanticType, ir)
						If managedClass Then Return "((struct " + managedClass.readableAbiName + "_obj *)bbObjectDowncast((BBOBJECT)" + managedOperand + ", (BBClass *)&" + managedClass.readableAbiName + "))"
						Local managedInterface:TGenericSpecializationNode = InterfaceSpecialization(node.semanticType, ir)
						If managedInterface Then Return "((BBOBJECT)bbInterfaceDowncast((BBOBJECT)" + managedOperand + ", (BBINTERFACE)&" + managedInterface.readableAbiName + "_ifc))"
						If node.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And node.semanticType.runtimeAbiName.length Then Return "((struct " + node.semanticType.runtimeAbiName + "_obj *)bbObjectDowncast((BBOBJECT)" + managedOperand + ", (BBClass *)&" + node.semanticType.runtimeAbiName + "))"
						If node.semanticType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE And node.semanticType.runtimeAbiName.length Then Return "((BBOBJECT)bbInterfaceDowncast((BBOBJECT)" + managedOperand + ", (BBINTERFACE)&" + node.semanticType.runtimeAbiName + "_ifc))"
						If Not IsObjectType(node.semanticType) And node.children[0].semanticType.CanonicalName() <> node.semanticType.CanonicalName() Then
							diagnostics :+ ["BMXC3047 managed narrowing conversion from '" + node.children[0].semanticType.CanonicalName() + "' to '" + node.semanticType.CanonicalName() + "' reached the generic raw C cast fallback"]
							Return DefaultValue(node.semanticType, ir)
						End If
					End If
					Return "((" + CType(node.semanticType, ir) + ")" + managedOperand + ")"
				End If
				Local conversionSourceName:String = "<unknown>"
				Local conversionTargetName:String = "<unknown>"
				If node.children.length And node.children[0].semanticType Then conversionSourceName = node.children[0].semanticType.CanonicalName()
				If node.semanticType Then conversionTargetName = node.semanticType.CanonicalName()
				diagnostics :+ ["BMXC3047 generic conversion from '" + conversionSourceName + "' to '" + conversionTargetName + "' requires supported closed ABI types"]
			Case TEMPLATE_NODE_NEW
				If node.semanticType And node.semanticType.kind = TEMPLATE_TYPE_ARRAY Then
					If Not TCompilerGenericSpecializationLowerer.SupportedManagedArrayType(node.semanticType, ir) Or node.children.length <> node.semanticType.rank Then
						diagnostics :+ ["BMXC3063 generic managed Array allocation requires one integral length for each closed rank"]
						Return "&bbEmptyArray"
					End If
					For Local dimensionNode:TGenericTemplateNode = EachIn node.children
						If Not ScalarIntegralType(dimensionNode.semanticType) Then
							diagnostics :+ ["BMXC3063 generic managed Array allocation dimensions must be integral"]
							Return "&bbEmptyArray"
						End If
					Next
					If node.semanticType.rank = 1 And node.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
						Return "bbArrayNew1DStruct_" + StructAbiName(node.semanticType.elementType, ir) + "(" + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ")"
					End If
					Local elementEncoding:String = ArrayElementEncoding(node.semanticType.elementType, ir)
					If Not elementEncoding.length Then
						diagnostics :+ ["BMXC3063 generic managed Array element has no runtime encoding"]
						Return "&bbEmptyArray"
					End If
					If node.semanticType.rank = 1 Then
						If node.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_ENUM Then
							Return "bbArrayNew1DEnum(~q" + elementEncoding + "~q, " + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ", " + node.semanticType.elementType.runtimeAbiName + "_BBEnum_impl)"
						End If
						Return "bbArrayNew1D(~q" + elementEncoding + "~q, " + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals) + ")"
					End If
					If node.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
						Local structDimensions:String
						For Local structDimension:TGenericTemplateNode = EachIn node.children
							structDimensions :+ ", " + EmitExpression(structDimension, ir, ownerMethod, diagnostics, locals)
						Next
						Return "bbArrayNewStruct(~q" + elementEncoding + "~q, sizeof(" + CType(node.semanticType.elementType, ir) + "), bbStructElementInit_" + StructAbiName(node.semanticType.elementType, ir) + ", " + node.semanticType.rank + structDimensions + ")"
					End If
					Local dimensions:String
					For Local dimension:TGenericTemplateNode = EachIn node.children
						dimensions :+ ", " + EmitExpression(dimension, ir, ownerMethod, diagnostics, locals)
					Next
					If node.semanticType.elementType.runtimeKind = TEMPLATE_RUNTIME_ENUM Then
						Return "bbArrayNewEnum(~q" + elementEncoding + "~q, " + node.semanticType.elementType.runtimeAbiName + "_BBEnum_impl, " + node.semanticType.rank + dimensions + ")"
					End If
					Return "bbArrayNew(~q" + elementEncoding + "~q, " + node.semanticType.rank + dimensions + ")"
				End If
				Local allocated:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(node.semanticType, ir)
				If allocated And allocated.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_CLASS Then
					Local allocationIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(allocated, diagnostics)
					If Not allocationIr Then Return DefaultValue(node.semanticType, ir)
					Local constructor:TCompilerGenericMethodIr = SelectConstructedConstructor(node, allocationIr)
					Local helperName:String = allocated.readableAbiName + "_New"
					If constructor Then
						helperName = constructor.abiName
					Else If node.children.length Then
						diagnostics :+ ["BMXC3039 generic construction of '" + node.semanticType.CanonicalName() + "' has no retained constructor matching the closed argument signature"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local allocation:String = "((struct " + allocated.readableAbiName + "_obj *)" + helperName + "((BBClass *)&" + allocated.readableAbiName
					For Local index:Int = 0 Until node.children.length
						allocation :+ ", " + EmitCallArgument(node.children[index], constructor.parameters[index], ir, ownerMethod, diagnostics, locals)
					Next
					If constructor Then
						For Local index:Int = node.children.length Until constructor.parameters.length
							allocation :+ ", " + EmitCallArgument(constructor.parameters[index].defaultValue, constructor.parameters[index], ir, ownerMethod, diagnostics, locals)
						Next
					End If
					Return allocation + "))"
				End If
				If allocated And allocated.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then
					Local allocationIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(allocated, diagnostics)
					If Not allocationIr Then Return DefaultValue(node.semanticType, ir)
					Local constructor:TCompilerGenericMethodIr = SelectConstructedConstructor(node, allocationIr)
					Local helperName:String = allocated.readableAbiName + "_New"
					If constructor Then
						helperName = constructor.abiName
					Else If node.children.length Or allocationIr.constructors.length Then
						diagnostics :+ ["BMXC3039 generic Struct construction of '" + node.semanticType.CanonicalName() + "' has no retained constructor matching the closed argument signature"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local construction:String = helperName + "("
					For Local index:Int = 0 Until node.children.length
						If index Then construction :+ ", "
						construction :+ EmitCallArgument(node.children[index], constructor.parameters[index], ir, ownerMethod, diagnostics, locals)
					Next
					If constructor Then
						For Local index:Int = node.children.length Until constructor.parameters.length
							If index Then construction :+ ", "
							construction :+ EmitCallArgument(constructor.parameters[index].defaultValue, constructor.parameters[index], ir, ownerMethod, diagnostics, locals)
						Next
					End If
					Return construction + ")"
				End If
				If allocated Then
					diagnostics :+ ["BMXC3039 construction inside a generic body requires a canonical generic Type or Struct target"]
					Return DefaultValue(node.semanticType, ir)
				End If
				If node.semanticType And node.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And Not node.children.length Then
					Return "((struct " + node.semanticType.runtimeAbiName + "_obj *)bbObjectNew((BBClass *)&" + node.semanticType.runtimeAbiName + "))"
				End If
				If node.semanticType And node.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And node.identity = "ordinary-constructor-signature" Then
					If Not node.referencedSymbol Or Not node.referencedSymbol.overloadKey.length Or TCompilerAbiNamer.Sanitize(node.referencedSymbol.overloadKey) <> node.referencedSymbol.overloadKey Then
						diagnostics :+ ["BMXC3062 parameterized ordinary Type construction has no stable published allocation ABI"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local signature:TGenericTemplateNode = node.children[0]
					Local ordinaryAllocation:String = "((struct " + node.semanticType.runtimeAbiName + "_obj *)" + node.referencedSymbol.overloadKey + "((BBClass *)&" + node.semanticType.runtimeAbiName
					For Local index:Int = 1 Until node.children.length
						Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
						parameter.semanticType = signature.children[index - 1].semanticType
						parameter.passingMode = Int(signature.children[index - 1].valueText)
						ordinaryAllocation :+ ", " + EmitCallArgument(node.children[index], parameter, ir, ownerMethod, diagnostics, locals)
					Next
					Return ordinaryAllocation + "))"
				End If
				diagnostics :+ ["BMXC3026 generic construction has no canonical referenced specialization"]
			Case TEMPLATE_NODE_CALL
				If node.identity = "closure-call" Then
					If Not node.children.length Or Not node.children[0].semanticType Or node.children[0].semanticType.kind <> TEMPLATE_TYPE_CLOSURE Then
						diagnostics :+ ["BMXC3076 generic managed Closure call has no retained signature"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local closureType:TTemplateTypeReference = node.children[0].semanticType
					If node.children.length - 1 <> closureType.arguments.length Then
						diagnostics :+ ["BMXC3076 generic managed Closure call argument count does not match its signature"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local invocation:String = ClosureCallHelperName(closureType) + "(" + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals)
					For Local index:Int = 0 Until closureType.arguments.length
						Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
						parameter.semanticType = closureType.arguments[index]
						parameter.passingMode = closureType.callableParameterModes[index]
						invocation :+ ", " + EmitCallArgument(node.children[index + 1], parameter, ir, ownerMethod, diagnostics, locals)
					Next
					Return invocation + ")"
				End If
				If node.identity = "indirect-call" Then
					If Not node.children.length Or Not node.children[0].semanticType Or node.children[0].semanticType.kind <> TEMPLATE_TYPE_CALLABLE Then
						diagnostics :+ ["BMXC3075 generic indirect call has no retained callable signature"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local callableType:TTemplateTypeReference = node.children[0].semanticType
					If node.children.length - 1 <> callableType.arguments.length Then
						diagnostics :+ ["BMXC3075 generic indirect call argument count does not match its callable signature"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local indirect:String = "((" + EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals)
					indirect :+ ")("
					For Local index:Int = 0 Until callableType.arguments.length
						If index Then indirect :+ ", "
						If callableType.callableParameterModes[index] = PARAMETER_PASS_VAR Then
							Local callableParameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
							callableParameter.semanticType = callableType.arguments[index]
							callableParameter.passingMode = PARAMETER_PASS_VAR
							indirect :+ EmitCallArgument(node.children[index + 1], callableParameter, ir, ownerMethod, diagnostics, locals)
						Else
							indirect :+ EmitExpression(node.children[index + 1], ir, ownerMethod, diagnostics, locals)
						End If
					Next
					Return indirect + "))"
				End If
				If node.children.length Then
					If node.identity.StartsWith("ordinary-interface-call") Then
						Local ordinaryInterfaceReceiver:String = EmitExpression(node.children[0], ir, ownerMethod, diagnostics, locals)
						Local ordinaryInterfaceCall:String = EmitOrdinaryInterfaceOperation(node, ordinaryInterfaceReceiver, ir, diagnostics, ownerMethod, locals)
						If ordinaryInterfaceCall.length Then Return ordinaryInterfaceCall
						Return DefaultValue(node.semanticType, ir)
					End If
					If node.children[0].kind = TEMPLATE_NODE_BLOCK And (node.children[0].valueText = "local-routine-signature" Or node.children[0].valueText = "local-routine-reference") Then
						Local inlineSignature:TGenericTemplateNode = node.children[0]
						Local parameterCount:Int = inlineSignature.children.length
						If inlineSignature.valueText = "local-routine-signature" Then parameterCount :- 1
						If parameterCount < 0 Or node.children.length <> parameterCount + 1 Then
							diagnostics :+ ["BMXC3068 inline local routine '" + node.valueText + "' has an invalid canonical signature"]
							Return DefaultValue(node.semanticType, ir)
						End If
						Local helperCall:String = LocalRoutineAbiName(ownerMethod, inlineSignature, node.valueText) + "("
						Local emittedArgumentCount:Int
						For Local signatureIndex:Int = 0 Until parameterCount
							If inlineSignature.children[signatureIndex].valueText <> "capture:self" Then Continue
							helperCall :+ "self"
							emittedArgumentCount :+ 1
						Next
						For Local signatureIndex:Int = 0 Until parameterCount
							If inlineSignature.children[signatureIndex].valueText = "capture:self" Then Continue
							If emittedArgumentCount Then helperCall :+ ", "
							Local localParameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
							localParameter.semanticType = inlineSignature.children[signatureIndex].semanticType
							If inlineSignature.children[signatureIndex].valueText.StartsWith("capture:outer:") Then localParameter.passingMode = PARAMETER_PASS_VAR Else localParameter.passingMode = Int(inlineSignature.children[signatureIndex].identity)
							If Not localParameter.passingMode Then localParameter.passingMode = PARAMETER_PASS_VALUE
							If inlineSignature.children[signatureIndex].valueText.StartsWith("capture:outer:") Then
								Local captureExpression:String = EmitExpression(node.children[signatureIndex + 1], ir, ownerMethod, diagnostics, locals)
								Local outerParameter:TGenericTemplateValueParameter
								For Local candidate:TGenericTemplateValueParameter = EachIn ownerMethod.parameters
									If candidate.name.ToLower() = inlineSignature.children[signatureIndex].valueText[14..].ToLower() Then outerParameter = candidate; Exit
								Next
								If outerParameter And outerParameter.passingMode = PARAMETER_PASS_VAR Then
									helperCall :+ TCompilerAbiNamer.Sanitize(outerParameter.name)
								Else
									helperCall :+ "(&(" + captureExpression + "))"
								End If
							Else
								helperCall :+ EmitCallArgument(node.children[signatureIndex + 1], localParameter, ir, ownerMethod, diagnostics, locals)
							End If
							emittedArgumentCount :+ 1
						Next
						Return helperCall + ")"
					End If
					If node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].valueText = "ordinary-routine-signature" Then
						If node.referencedSymbol And node.referencedSymbol.overloadKey.length Then
							Local ordinaryCall:String = node.referencedSymbol.overloadKey + "("
							Local ordinarySignature:TGenericTemplateNode = node.children[0]
							Local ordinaryNativeParameterTypes:String[] = TCompilerNativeDeclaration.ParameterTypes(ordinarySignature.identity)
							For Local index:Int = 1 Until node.children.length
								If index > 1 Then ordinaryCall :+ ", "
								Local ordinaryArgument:String = EmitExpression(node.children[index], ir, ownerMethod, diagnostics, locals)
								If index - 1 < ordinarySignature.children.length Then
									Local ordinaryParameter:TGenericTemplateNode = ordinarySignature.children[index - 1]
									Local ordinaryParameterType:String = CType(ordinaryParameter.semanticType, ir)
									If ordinaryParameter.valueText = "ordinary-struct-receiver" Then
										ordinaryArgument = "(&(" + ordinaryArgument + "))"
									Else If Int(ordinaryParameter.valueText) = PARAMETER_PASS_VAR Then
										Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
										parameter.semanticType = ordinaryParameter.semanticType
										parameter.passingMode = PARAMETER_PASS_VAR
										ordinaryArgument = EmitCallArgument(node.children[index], parameter, ir, ownerMethod, diagnostics, locals)
									Else If ordinaryParameterType.length Then
										ordinaryArgument = "((" + ordinaryParameterType + ")" + ordinaryArgument + ")"
									End If
								End If
								If index - 1 < ordinaryNativeParameterTypes.length Then ordinaryArgument = "((" + ordinaryNativeParameterTypes[index - 1] + ")" + ordinaryArgument + ")"
								ordinaryCall :+ ordinaryArgument
							Next
							ordinaryCall :+ ")"
							If ordinarySignature.identity.length And CType(node.semanticType, ir) <> "void" Then ordinaryCall = "((" + CType(node.semanticType, ir) + ")(" + ordinaryCall + "))"
							Return ordinaryCall
						End If
						diagnostics :+ ["BMXC3048 ordinary routine dependency '" + node.valueText + "' has no stable linkage identity"]
						Return DefaultValue(node.semanticType, ir)
					End If
					If node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].valueText = "runtime-header-routine" Then
						If node.referencedSymbol And node.referencedSymbol.overloadKey.length Then
							Local runtimeCall:String = node.referencedSymbol.overloadKey + "("
							Local runtimeSignature:TGenericTemplateNode = node.children[0]
							Local runtimeNativeParameterTypes:String[] = TCompilerNativeDeclaration.ParameterTypes(runtimeSignature.identity)
							For Local index:Int = 1 Until node.children.length
								If index > 1 Then runtimeCall :+ ", "
								Local runtimeArgument:String
								If index - 1 < runtimeSignature.children.length And Int(runtimeSignature.children[index - 1].valueText) = PARAMETER_PASS_VAR Then
									Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
									parameter.semanticType = runtimeSignature.children[index - 1].semanticType
									parameter.passingMode = PARAMETER_PASS_VAR
									runtimeArgument = EmitCallArgument(node.children[index], parameter, ir, ownerMethod, diagnostics, locals)
								Else
									runtimeArgument = EmitExpression(node.children[index], ir, ownerMethod, diagnostics, locals)
								End If
								If index - 1 < runtimeNativeParameterTypes.length Then runtimeArgument = "((" + runtimeNativeParameterTypes[index - 1] + ")" + runtimeArgument + ")"
								runtimeCall :+ runtimeArgument
							Next
							runtimeCall :+ ")"
							If runtimeSignature.identity.length And CType(node.semanticType, ir) <> "void" Then runtimeCall = "((" + CType(node.semanticType, ir) + ")(" + runtimeCall + "))"
							Return runtimeCall
						End If
						diagnostics :+ ["BMXC3048 runtime-header routine dependency '" + node.valueText + "' has no stable linkage identity"]
						Return DefaultValue(node.semanticType, ir)
					End If
					If node.children[0].kind = TEMPLATE_NODE_BLOCK And node.children[0].valueText = "routine-type-arguments" Then
						Local routineTarget:TGenericSpecializationNode = ReferencedRoutineCall(node, ir)
						If routineTarget Then
							Local routineTargetIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(routineTarget, diagnostics)
							If Not routineTargetIr Or Not routineTargetIr.routine Then Return DefaultValue(node.semanticType, ir)
							Local routineCall:String = routineTarget.readableAbiName + "("
							Local argumentStart:Int = 1
							If routineTarget.artifact.isMethod And node.children.length > 1 Then
								Local targetReceiver:TTemplateTypeReference = TTemplateTypeSubstitution.Apply(routineTarget.artifact.containingType, routineTarget.key.containingTypeArguments, routineTarget.key.typeArguments)
								Local targetReceiverCType:String = CType(targetReceiver, ir)
								Local receiverExpression:String = EmitExpression(node.children[1], ir, ownerMethod, diagnostics, locals)
								If targetReceiverCType.length Then receiverExpression = "((" + targetReceiverCType + ")" + receiverExpression + ")"
								routineCall :+ receiverExpression
								argumentStart = 2
							End If
							For Local index:Int = argumentStart Until node.children.length
								If index > argumentStart Or argumentStart > 1 Then routineCall :+ ", "
								routineCall :+ EmitCallArgument(node.children[index], routineTargetIr.routine.parameters[index - argumentStart], ir, ownerMethod, diagnostics, locals)
							Next
							Return routineCall + ")"
						End If
						diagnostics :+ ["BMXC3027 generic routine call '" + node.valueText + "' has no canonical referenced specialization"]
						Return DefaultValue(node.semanticType, ir)
					End If
					Local receiverNode:TGenericTemplateNode = node.children[0]
					If receiverNode.kind = TEMPLATE_NODE_SELF And receiverNode.valueText = "self" Then
						Local selfExpression:String = ClosureSelfExpression(ownerMethod)
						If ir.isInterface Then
							Local interfaceMethod:TCompilerGenericMethodIr = InterfaceOperation(ir.specialization, node, ir, diagnostics)
							If interfaceMethod Then Return EmitInterfaceCall(ir.specialization, node, interfaceMethod, selfExpression, ir, ownerMethod, diagnostics, locals)
							Return DefaultValue(node.semanticType, ir)
						End If
						Local selfMethod:TCompilerGenericMethodIr = VirtualSelfMethod(node, ir, diagnostics)
						If selfMethod Then
							If ir.isStruct Then
								Local directStructCall:String = selfMethod.abiName + "(" + selfExpression
								For Local index:Int = 1 Until node.children.length
									directStructCall :+ ", " + EmitCallArgument(node.children[index], selfMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
								Next
								Return directStructCall + ")"
							End If
							Local selfOwner:TGenericSpecializationNode = selfMethod.declaringSpecialization
							If Not selfOwner Then selfOwner = ir.specialization
							Local selfCall:String = selfExpression + "->clas->" + selfMethod.slotName + "("
							If Not selfMethod.isTypeFunction Then selfCall :+ "(struct " + selfOwner.readableAbiName + "_obj *)" + selfExpression
							For Local index:Int = 1 Until node.children.length
								If index > 1 Or Not selfMethod.isTypeFunction Then selfCall :+ ", "
								selfCall :+ EmitCallArgument(node.children[index], selfMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
							Next
							Return selfCall + ")"
						End If
						Return DefaultValue(node.semanticType, ir)
					End If
					Local target:TGenericSpecializationNode
					If receiverNode Then target = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(receiverNode.semanticType, ir)
					If target Then
						If target.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then
							Local interfaceMethod:TCompilerGenericMethodIr = InterfaceOperation(target, node, ir, diagnostics)
							If interfaceMethod And receiverNode.kind = TEMPLATE_NODE_SELF And receiverNode.valueText = "super" Then
								Local directCall:String = interfaceMethod.abiName + "((BBOBJECT)" + EmitExpression(receiverNode, ir, ownerMethod, diagnostics, locals)
								For Local index:Int = 1 Until node.children.length
									directCall :+ ", " + EmitCallArgument(node.children[index], interfaceMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
								Next
								Return directCall + ")"
							End If
							If interfaceMethod Then Return EmitInterfaceCall(target, node, interfaceMethod, EmitExpression(receiverNode, ir, ownerMethod, diagnostics, locals), ir, ownerMethod, diagnostics, locals)
							Return DefaultValue(node.semanticType, ir)
						End If
						Local targetMethod:TCompilerGenericMethodIr = TypeOperation(target, node, ir, diagnostics)
						If Not targetMethod Then Return DefaultValue(node.semanticType, ir)
						Local receiverExpression:String = EmitExpression(receiverNode, ir, ownerMethod, diagnostics, locals)
						Local methodOwner:TGenericSpecializationNode = targetMethod.declaringSpecialization
						If Not methodOwner Then methodOwner = target
						If receiverNode.kind <> TEMPLATE_NODE_SELF Or receiverNode.valueText <> "super" Then
							Return EmitTypeOperation(target, node, targetMethod, receiverExpression, ir, ownerMethod, diagnostics, locals)
						End If
						Local result:String = targetMethod.abiName + "((struct " + methodOwner.readableAbiName + "_obj *)" + receiverExpression
						For Local index:Int = 1 Until node.children.length
							result :+ ", " + EmitCallArgument(node.children[index], targetMethod.parameters[index - 1], ir, ownerMethod, diagnostics, locals)
						Next
						Return result + ")"
					End If
					If receiverNode And receiverNode.semanticType And receiverNode.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And node.runtimeDispatchKind = TEMPLATE_DISPATCH_ORDINARY_CLASS Then
						Return EmitOrdinaryClassOperation(node, EmitExpression(receiverNode, ir, ownerMethod, diagnostics, locals), ir, diagnostics, ownerMethod, locals)
					End If
				End If
				diagnostics :+ ["BMXC3027 generic receiver call '" + node.valueText + "' has no canonical referenced specialization"]
		End Select
		Return DefaultValue(node.semanticType, ir)
	End Function

	Function ClosureEnvironmentForCaptures:TCompilerGenericClosureEnvironmentIr(ownerMethod:TCompilerGenericMethodIr, captures:TCompilerGenericClosureCaptureIr[])
		If Not ownerMethod Then Return Null
		Local result:TCompilerGenericClosureEnvironmentIr = ownerMethod.closureEnvironment
		For Local capture:TCompilerGenericClosureCaptureIr = EachIn captures
			If Not capture.activationIdentity.length Then Continue
			Local candidate:TCompilerGenericClosureEnvironmentIr = TCompilerGenericClosureEnvironmentIr(ownerMethod.activationClosureEnvironments.ValueForKey(capture.activationIdentity))
			If candidate And (Not result Or EnvironmentDescendsFrom(candidate, result)) Then result = candidate
		Next
		Return result
	End Function

	Function FieldMatchesNode:Int(irField:TCompilerGenericFieldIr, node:TGenericTemplateNode)
		If Not irField Or Not node Or irField.name.ToLower() <> node.valueText.ToLower() Then Return False
		If Not node.referencedSymbol Or Not node.referencedSymbol.qualifiedName.length Or Not irField.declaringSpecialization Or Not irField.declaringSpecialization.artifact Or Not irField.declaringSpecialization.artifact.identity Then Return True
		Local expectedQualifiedName:String = irField.declaringSpecialization.artifact.identity.qualifiedName + "." + irField.name
		If node.referencedSymbol.qualifiedName.ToLower() <> expectedQualifiedName.ToLower() Then Return False
		Local expectedModule:String = irField.declaringSpecialization.artifact.identity.moduleName
		Return Not expectedModule.length Or Not node.referencedSymbol.moduleName.length Or expectedModule.ToLower() = node.referencedSymbol.moduleName.ToLower()
	End Function

	Function StaticFieldForNode:TCompilerGenericFieldIr(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not node Or Not ir Then Return Null
		Local ownerName:String
		If node.referencedSymbol Then
			ownerName = node.referencedSymbol.qualifiedName
			Local dot:Int = ownerName.FindLast(".")
			If dot >= 0 Then ownerName = ownerName[..dot] Else ownerName = ""
		End If
		If Not ownerName.length Or (ir.specialization.artifact.identity And ir.specialization.artifact.identity.qualifiedName.ToLower() = ownerName.ToLower()) Then
			For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
				If staticField.name.ToLower() = node.valueText.ToLower() Then Return staticField
			Next
		End If
		For Local referenced:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If referenced.IsAbiReferenceOnly() Then Continue
			If ownerName.length And referenced.artifact.identity.qualifiedName.ToLower() <> ownerName.ToLower() Then Continue
			Local referencedIr:TCompilerGenericSpecializationIr = TCompilerGenericSpecializationLowerer.Lower(referenced, diagnostics)
			If Not referencedIr Then Continue
			For Local staticField:TCompilerGenericFieldIr = EachIn referencedIr.staticFields
				If staticField.name.ToLower() = node.valueText.ToLower() Then Return staticField
			Next
		Next
		Return Null
	End Function

	Function StaticFieldForUnqualifiedOrdinaryGlobal:TCompilerGenericFieldIr(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr)
		If Not node Or node.identity <> "ordinary-global" Or Not ir Then Return Null
		If node.referencedSymbol And node.referencedSymbol.qualifiedName.Contains(".") Then Return Null
		For Local staticField:TCompilerGenericFieldIr = EachIn ir.staticFields
			If staticField.name.ToLower() = node.valueText.ToLower() Then Return staticField
		Next
		Return Null
	End Function

	Function SelectConstructedConstructor:TCompilerGenericMethodIr(node:TGenericTemplateNode, allocationIr:TCompilerGenericSpecializationIr)
		If Not node Or Not allocationIr Then Return Null
		For Local constructor:TCompilerGenericMethodIr = EachIn allocationIr.constructors
			If node.referencedSymbol And node.referencedSymbol.overloadKey <> "new/" + constructor.parameters.length Then Continue
			If ConstructedConstructorMatches(node, constructor) Then Return constructor
		Next
		For Local constructor:TCompilerGenericMethodIr = EachIn allocationIr.constructors
			If ConstructedConstructorMatches(node, constructor) Then Return constructor
		Next
		Return Null
	End Function

	Function ConstructedConstructorMatches:Int(node:TGenericTemplateNode, constructor:TCompilerGenericMethodIr)
		If Not node Or Not constructor Or node.children.length > constructor.parameters.length Then Return False
		For Local index:Int = 0 Until node.children.length
			If Not constructor.parameters[index].semanticType Or Not node.children[index] Or Not node.children[index].semanticType Or constructor.parameters[index].semanticType.CanonicalName() <> node.children[index].semanticType.CanonicalName() Then Return False
		Next
		For Local index:Int = node.children.length Until constructor.parameters.length
			If Not constructor.parameters[index].optional Or Not constructor.parameters[index].defaultValue Then Return False
		Next
		Return True
	End Function

	Function VirtualSelfMethod:TCompilerGenericMethodIr(call:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, diagnostics:String[] Var)
		If Not call Or Not call.referencedSymbol Or Not ir Then
			diagnostics :+ ["BMXC3061 generic Self call has no canonical symbolic method identity"]
			Return Null
		End If
		Local result:TCompilerGenericMethodIr
		For Local candidate:TCompilerGenericMethodIr = EachIn ir.methods
			If candidate.name.ToLower() <> call.valueText.ToLower() Then Continue
			If candidate.parameters.length <> call.children.length - 1 Then Continue
			If Not call.semanticType Or candidate.returnType.CanonicalName() <> call.semanticType.CanonicalName() Then Continue
			Local matches:Int = True
			For Local index:Int = 0 Until candidate.parameters.length
				If Not call.children[index + 1] Or Not call.children[index + 1].semanticType Or candidate.parameters[index].semanticType.CanonicalName() <> call.children[index + 1].semanticType.CanonicalName() Then
					matches = False
					Exit
				End If
			Next
			If Not matches Then Continue
			If result Then
				diagnostics :+ ["BMXC3061 generic Self call '" + call.valueText + "' is ambiguous after specialization"]
				Return Null
			End If
			result = candidate
		Next
		If Not result Then diagnostics :+ ["BMXC3061 generic Self call '" + call.valueText + "' has no exact canonical virtual slot"]
		Return result
	End Function

	Function EmitCallArgument:String(argument:TGenericTemplateNode, parameter:TGenericTemplateValueParameter, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap)
		If Not parameter Or parameter.passingMode = PARAMETER_PASS_VALUE Then Return EmitExpression(argument, ir, ownerMethod, diagnostics, locals)
		If parameter.passingMode <> PARAMETER_PASS_VAR Then
			diagnostics :+ ["BMXC3070 generic call parameter has an unknown passing mode"]
			Return "0"
		End If
		If argument And argument.kind = TEMPLATE_NODE_CONVERSION And argument.valueText = CONVERSION_POINTER_TO_VAR_REFERENCE And argument.children.length = 1 Then
			Return EmitExpression(argument.children[0], ir, ownerMethod, diagnostics, locals)
		End If
		If argument And argument.kind = TEMPLATE_NODE_CONVERSION And argument.valueText = CONVERSION_VAR_REFERENCE And argument.children.length = 1 Then
			Local operandExpression:String = EmitExpression(argument.children[0], ir, ownerMethod, diagnostics, locals)
			If ownerMethod Then
				For Local ownerParameter:TGenericTemplateValueParameter = EachIn ownerMethod.parameters
					Local parameterName:String = TCompilerAbiNamer.Sanitize(ownerParameter.name)
					If ownerParameter.passingMode = PARAMETER_PASS_VAR And operandExpression = "(*" + parameterName + ")" Then Return parameterName
				Next
			End If
			Return "(&(" + operandExpression + "))"
		End If
		If Not argument Or (argument.kind <> TEMPLATE_NODE_NAME And argument.kind <> TEMPLATE_NODE_MEMBER And argument.kind <> TEMPLATE_NODE_ARRAY_ELEMENT) Then
			diagnostics :+ ["BMXC3070 generic Var argument requires a retained addressable reference conversion"]
			Return "0"
		End If
		Return "(&(" + EmitExpression(argument, ir, ownerMethod, diagnostics, locals) + "))"
	End Function

	Function ScalarNumericType:Int(value:TTemplateTypeReference)
		If Not value Or value.kind <> TEMPLATE_TYPE_BUILTIN Then Return False
		Select value.symbolName.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double"
				Return True
		End Select
		Return False
	End Function

	Function ScalarIntegralType:Int(value:TTemplateTypeReference)
		If Not value Or value.kind <> TEMPLATE_TYPE_BUILTIN Then Return False
		Select value.symbolName.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t"
				Return True
		End Select
		Return False
	End Function

	Function UnaryOperandsSupported:Int(operatorText:String, operand:TTemplateTypeReference)
		If Not ScalarNumericType(operand) Then Return False
		If operatorText = "~~" Then Return ScalarIntegralType(operand)
		Return operatorText = "+" Or operatorText = "-" Or operatorText.ToLower() = "not"
	End Function

	Function BinaryOperandsSupported:Int(operatorText:String, left:TTemplateTypeReference, right:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr)
		Local comparison:String = operatorText.ToLower()
		If comparison = "=" Or comparison = "<>" Then
			If left And right And left.kind = TEMPLATE_TYPE_NAMED And right.kind = TEMPLATE_TYPE_NAMED And left.runtimeKind = TEMPLATE_RUNTIME_ENUM And right.runtimeKind = TEMPLATE_RUNTIME_ENUM Then
				If left.CanonicalName() = right.CanonicalName() And TCompilerGenericSpecializationLowerer.EnumValueTypeSupported(left.runtimeValueType) Then Return True
			End If
			Local leftString:Int = left And left.kind = TEMPLATE_TYPE_BUILTIN And left.symbolName.ToLower() = "string"
			Local rightString:Int = right And right.kind = TEMPLATE_TYPE_BUILTIN And right.symbolName.ToLower() = "string"
			If leftString And rightString Then Return True
			If ManagedReferenceType(left, ir) And ManagedReferenceType(right, ir) Then Return True
			If IsNullType(left) And ManagedReferenceType(right, ir) Then Return True
			If IsNullType(right) And ManagedReferenceType(left, ir) Then Return True
			If left And right And left.kind = TEMPLATE_TYPE_POINTER And right.kind = TEMPLATE_TYPE_POINTER Then Return left.CanonicalName() = right.CanonicalName()
			If IsNullType(left) And right And right.kind = TEMPLATE_TYPE_POINTER Then Return True
			If IsNullType(right) And left And left.kind = TEMPLATE_TYPE_POINTER Then Return True
		End If
		If Not ScalarNumericType(left) Or Not ScalarNumericType(right) Then Return False
		Select operatorText.ToLower()
			Case "mod", "shl", "shr", "sar", "|", "&", "^", "and", "or", "xor"
				Return ScalarIntegralType(left) And ScalarIntegralType(right)
			Case "+", "-", "*", "/", "<", "<=", ">", ">=", "=", "<>"
				Return True
		End Select
		Return False
	End Function

	Function CUnaryOperator:String(operatorText:String)
		Select operatorText.ToLower()
			Case "+", "-"
				Return operatorText
			Case "not"
				Return "!"
			Case "~~"
				Return "~~"
		End Select
		Return ""
	End Function

	Function CBinaryOperator:String(operatorText:String)
		Select operatorText.ToLower()
			Case "+", "-", "*", "/", "<", "<=", ">", ">=", "|", "&", "^"
				Return operatorText
			Case "="
				Return "=="
			Case "<>"
				Return "!="
			Case "mod"
				Return "%"
			Case "shl"
				Return "<<"
			Case "shr", "sar"
				Return ">>"
			Case "and"
				Return "&&"
			Case "or"
				Return "||"
			Case "xor"
				Return "^"
		End Select
		Return ""
	End Function

	Function CAssignmentOperator:String(operatorText:String)
		Select operatorText.ToLower()
			Case "=" Return "="
			Case ":+" Return "+="
			Case ":-" Return "-="
			Case ":*" Return "*="
			Case ":/" Return "/="
		End Select
		Return ""
	End Function

	Function StableArrayCompoundTarget:Int(node:TGenericTemplateNode)
		If Not node Then Return False
		If node.kind = TEMPLATE_NODE_NAME Or node.kind = TEMPLATE_NODE_SELF Then Return True
		If node.kind <> TEMPLATE_NODE_MEMBER Then Return False
		If Not node.children.length Then Return True
		Return node.children.length = 1 And StableArrayCompoundTarget(node.children[0])
	End Function

	Function ArrayElementEncoding:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Then Return ""
		If value.kind = TEMPLATE_TYPE_CLOSURE Then
			Local result:String = "!("
			For Local index:Int = 0 Until value.arguments.length
				If index Then result :+ ","
				If index < value.callableParameterModes.length And value.callableParameterModes[index] = PARAMETER_PASS_VAR Then result :+ "&"
				Local parameterEncoding:String = ArrayElementEncoding(value.arguments[index], ir)
				If Not parameterEncoding.length Then Return ""
				result :+ parameterEncoding
			Next
			result :+ ")"
			If value.elementType And Not VoidType(value.elementType) Then
				Local returnEncoding:String = ArrayElementEncoding(value.elementType, ir)
				If Not returnEncoding.length Then Return ""
				result :+ returnEncoding
			End If
			Return result
		End If
		If value.kind = TEMPLATE_TYPE_POINTER Then Return "*" + ArrayElementEncoding(value.elementType, ir)
		If value.kind = TEMPLATE_TYPE_ARRAY Then
			Local brackets:String = "["
			For Local index:Int = 1 Until value.rank
				brackets :+ ","
			Next
			Return brackets + "]" + ArrayElementEncoding(value.elementType, ir)
		End If
		If value.kind = TEMPLATE_TYPE_NAMED Then
			Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
			If referenced And referenced.artifact.typeDeclarationKind <> GENERIC_TYPE_DECLARATION_STRUCT Then Return ":" + referenced.readableAbiName
			If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return "/" + value.symbolName
			If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then Return "@" + value.symbolName
			If value.runtimeKind = TEMPLATE_RUNTIME_CLASS Or value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE Then Return ":" + value.symbolName
			Return ""
		End If
		If value.kind <> TEMPLATE_TYPE_BUILTIN Then Return ""
		Select value.symbolName.ToLower()
			Case "byte" Return "b"
			Case "short" Return "s"
			Case "int" Return "i"
			Case "uint" Return "u"
			Case "long" Return "l"
			Case "ulong" Return "y"
			Case "longint" Return "v"
			Case "ulongint" Return "e"
			Case "size_t" Return "t"
			Case "float" Return "f"
			Case "double" Return "d"
			Case "string" Return "$"
			Case "object" Return ":Object"
		End Select
		Return ""
	End Function

	Function ReferencedRoutineCall:TGenericSpecializationNode(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr)
		If Not node Or Not ir Or Not node.referencedSymbol Or Not node.children.length Then Return Null
		Local arguments:TGenericTemplateNode = node.children[0]
		For Local candidate:TGenericSpecializationNode = EachIn ir.referencedSpecializations
			If Not candidate.artifact.identity Or candidate.artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Continue
			If candidate.artifact.identity.qualifiedName.ToLower() <> node.referencedSymbol.qualifiedName.ToLower() Then Continue
			If candidate.artifact.identity.moduleName.length And node.referencedSymbol.moduleName.length And candidate.artifact.identity.moduleName.ToLower() <> node.referencedSymbol.moduleName.ToLower() Then Continue
			If node.referencedSymbol.overloadKey.length And candidate.artifact.identity.signatureKey.ToLower() <> node.referencedSymbol.overloadKey.ToLower() Then Continue
			If candidate.key.typeArguments.length <> arguments.children.length Then Continue
			Local matches:Int = True
			For Local index:Int = 0 Until candidate.key.typeArguments.length
				If Not arguments.children[index].semanticType Or candidate.key.typeArguments[index].CanonicalName() <> arguments.children[index].semanticType.CanonicalName() Then matches = False; Exit
			Next
			If matches And candidate.artifact.isMethod Then
				If node.children.length < 2 Or Not node.children[1].semanticType Or node.children[1].semanticType.arguments.length <> candidate.key.containingTypeArguments.length Then
					matches = False
				Else
					For Local index:Int = 0 Until candidate.key.containingTypeArguments.length
						If candidate.key.containingTypeArguments[index].CanonicalName() <> node.children[1].semanticType.arguments[index].CanonicalName() Then matches = False; Exit
					Next
				End If
			End If
			If matches Then Return candidate
		Next
		Return Null
	End Function

	Function CType:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Then Return ""
		If value.kind = TEMPLATE_TYPE_POINTER Then
			Local elementCType:String = CType(value.elementType, ir)
			If elementCType.length Then Return elementCType + " *"
			Return ""
		End If
		If value.kind = TEMPLATE_TYPE_ARRAY Then Return "BBARRAY"
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY Then Return CType(value.elementType, ir) + " *"
		If value.kind = TEMPLATE_TYPE_CALLABLE Then Return "BBFuncPtr"
		If value.kind = TEMPLATE_TYPE_CLOSURE Then Return "BBClosure *"
		If value.kind = TEMPLATE_TYPE_NAMED Then
			Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
			If referenced Then
				If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then Return "BBOBJECT"
				If referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then Return "struct " + referenced.readableAbiName
				Return "struct " + referenced.readableAbiName + "_obj *"
			End If
			If value.runtimeKind = TEMPLATE_RUNTIME_CLASS And value.runtimeAbiName.length Then Return "struct " + value.runtimeAbiName + "_obj *"
			If value.runtimeKind = TEMPLATE_RUNTIME_INTERFACE And value.runtimeAbiName.length Then Return "BBOBJECT"
			If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT And value.runtimeAbiName.length Then Return "struct " + value.runtimeAbiName
			If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return BuiltinCType(value.runtimeValueType)
			Return ""
		End If
		If value.kind <> TEMPLATE_TYPE_BUILTIN Then Return ""
		Select value.symbolName.ToLower()
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
			Case "float" Return "BBFLOAT"
			Case "double" Return "BBDOUBLE"
			Case "string" Return "BBSTRING"
			Case "object" Return "BBOBJECT"
		End Select
		Return ""
	End Function

	Function CValueDeclaration:String(value:TTemplateTypeReference, name:String, ir:TCompilerGenericSpecializationIr = Null, passingMode:Int = PARAMETER_PASS_VALUE)
		If value And value.kind = TEMPLATE_TYPE_CALLABLE Then
			Local result:String = CType(value.elementType, ir) + " (*"
			If passingMode = PARAMETER_PASS_VAR Then result :+ "*"
			result :+ name + ")(" + CallableCParameterList(value, ir) + ")"
			Return result
		End If
		Local result:String = CType(value, ir)
		If passingMode = PARAMETER_PASS_VAR Then result :+ " *"
		If name.length Then result :+ " " + name
		Return result
	End Function

	Function CFunctionDeclaration:String(returnType:TTemplateTypeReference, name:String, parameters:String, ir:TCompilerGenericSpecializationIr = Null, prefix:String = "")
		If returnType And returnType.kind = TEMPLATE_TYPE_CALLABLE Then
			Return prefix + CType(returnType.elementType, ir) + " (*" + name + "(" + parameters + "))(" + CallableCParameterList(returnType, ir) + ")"
		End If
		Return prefix + CType(returnType, ir) + " " + name + "(" + parameters + ")"
	End Function

	Function CFunctionPointerDeclaration:String(returnType:TTemplateTypeReference, name:String, parameters:String, ir:TCompilerGenericSpecializationIr = Null)
		If returnType And returnType.kind = TEMPLATE_TYPE_CALLABLE Then
			Return CType(returnType.elementType, ir) + " (*(*" + name + ")(" + parameters + "))(" + CallableCParameterList(returnType, ir) + ")"
		End If
		Return CType(returnType, ir) + " (*" + name + ")(" + parameters + ")"
	End Function

	Function CStorageDeclaration:String(value:TTemplateTypeReference, name:String, ir:TCompilerGenericSpecializationIr = Null)
		If value And value.kind = TEMPLATE_TYPE_STATIC_ARRAY Then Return CType(value.elementType, ir) + " " + name + "[" + value.staticArrayLength + "]"
		Return CValueDeclaration(value, name, ir)
	End Function

	Function CallableCParameterList:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If Not value Or value.kind <> TEMPLATE_TYPE_CALLABLE Or Not value.arguments.length Then Return "void"
		Local result:String
		For Local index:Int = 0 Until value.arguments.length
			If index Then result :+ ", "
			Local parameterName:String = "p" + index
			Local mode:Int = PARAMETER_PASS_VALUE
			If index < value.callableParameterModes.length Then mode = value.callableParameterModes[index]
			result :+ CValueDeclaration(value.arguments[index], parameterName, ir, mode)
		Next
		Return result
	End Function

	Function BuiltinCType:String(value:String)
		Select value.ToLower()
			Case "byte" Return "BBBYTE"
			Case "short" Return "BBSHORT"
			Case "int" Return "BBINT"
			Case "uint" Return "BBUINT"
			Case "long" Return "BBLONG"
			Case "ulong" Return "BBULONG"
			Case "longint" Return "BBLONGINT"
			Case "ulongint" Return "BBULONGINT"
			Case "size_t" Return "BBSIZET"
		End Select
		Return ""
	End Function

	Function DefaultValue:String(value:TTemplateTypeReference, ir:TCompilerGenericSpecializationIr = Null)
		If value And value.kind = TEMPLATE_TYPE_POINTER Then Return "((" + CType(value, ir) + ")0)"
		If value And value.kind = TEMPLATE_TYPE_CALLABLE Then
			Return "((union { BBFuncPtr source; " + CValueDeclaration(value, "target", ir) + "; }){ .source = &brl_blitz_NullFunctionError }.target)"
		End If
		If value And value.kind = TEMPLATE_TYPE_CLOSURE Then Return "((BBClosure *)&bbNullObject)"
		If value And value.kind = TEMPLATE_TYPE_ARRAY Then Return "&bbEmptyArray"
		If value And value.kind = TEMPLATE_TYPE_NAMED Then
			If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT And value.runtimeAbiName.length Then Return value.runtimeAbiName + "_New_ObjectNew()"
			If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Then Return "0"
			Local referenced:TGenericSpecializationNode = TCompilerGenericSpecializationLowerer.ReferencedSpecialization(value, ir)
			If referenced And referenced.artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT Then Return referenced.readableAbiName + "_New_ObjectNew()"
			Return "((void *)&bbNullObject)"
		End If
		If value And value.kind = TEMPLATE_TYPE_BUILTIN Then
			If value.symbolName.ToLower() = "string" Then Return "&bbEmptyString"
			If value.symbolName.ToLower() = "object" Then Return "((BBOBJECT)&bbNullObject)"
		End If
		Return "0"
	End Function

	Function StringTemplateType:Int(value:TTemplateTypeReference)
		Return value And value.kind = TEMPLATE_TYPE_BUILTIN And value.symbolName.ToLower() = "string"
	End Function

	Function StringConcatOperandSupported:Int(value:TTemplateTypeReference)
		Return StringTemplateType(value) Or ScalarNumericType(value)
	End Function

	Function EmitStringConcatOperand:String(node:TGenericTemplateNode, ir:TCompilerGenericSpecializationIr, ownerMethod:TCompilerGenericMethodIr, diagnostics:String[] Var, locals:TMap)
		Local expression:String = EmitExpression(node, ir, ownerMethod, diagnostics, locals)
		If StringTemplateType(node.semanticType) Then Return expression
		Return NumericToString(expression, node.semanticType, diagnostics)
	End Function

	Function NumericToString:String(expression:String, value:TTemplateTypeReference, diagnostics:String[] Var)
		If Not value Or value.kind <> TEMPLATE_TYPE_BUILTIN Then Return "&bbEmptyString"
		Select value.symbolName.ToLower()
			Case "byte", "short", "int" Return "bbStringFromInt(" + expression + ")"
			Case "uint" Return "bbStringFromUInt(" + expression + ")"
			Case "long" Return "bbStringFromLong(" + expression + ")"
			Case "ulong" Return "bbStringFromULong(" + expression + ")"
			Case "size_t" Return "bbStringFromSizet(" + expression + ")"
			Case "longint" Return "bbStringFromLongInt(" + expression + ")"
			Case "ulongint" Return "bbStringFromULongInt(" + expression + ")"
			Case "float" Return "bbStringFromFloat(" + expression + ", 0)"
			Case "double" Return "bbStringFromDouble(" + expression + ", 0)"
		End Select
		diagnostics :+ ["BMXC3047 numeric-to-String conversion has no runtime mapping for '" + value.CanonicalName() + "'"]
		Return "&bbEmptyString"
	End Function

	Function EmitStringCodeUnits:String(encoded:String)
		If Not encoded.length Then Return "&bbEmptyString"
		Local units:String[] = encoded.Split(",")
		Local result:String = "bbStringFromShorts((const unsigned short[]){"
		For Local index:Int = 0 Until units.length
			If index Then result :+ ", "
			result :+ units[index]
		Next
		Return result + "}, " + units.length + ")"
	End Function
End Type

Type TCompilerGenericTemplateLoopContext
	Field parent:TCompilerGenericTemplateLoopContext
	Field identity:String
	Field sourceLabel:String
	Field cleanupDepth:Int
	Field continueCleanupDepth:Int
End Type

Type TCompilerGenericTemplateBodyContext
	Field nextLoopId:Int
	Field nextSelectId:Int
	Field activeYieldExceptionFrameDepth:Int
	Field currentLoop:TCompilerGenericTemplateLoopContext
	Field localRoutineContext:TCompilerGenericLocalRoutineContext
	Field activeCleanupSteps:TGenericTemplateNode[] = New TGenericTemplateNode[0]

	Method BeginLoop:TCompilerGenericTemplateLoopContext(sourceLabel:String)
		Local result:TCompilerGenericTemplateLoopContext = New TCompilerGenericTemplateLoopContext
		result.parent = currentLoop
		result.identity = "loop" + nextLoopId
		result.sourceLabel = sourceLabel.ToLower()
		result.cleanupDepth = activeCleanupSteps.length
		result.continueCleanupDepth = result.cleanupDepth
		nextLoopId :+ 1
		currentLoop = result
		Return result
	End Method

	Method EndLoop(loop:TCompilerGenericTemplateLoopContext)
		If loop Then currentLoop = loop.parent
	End Method

	Method NewSelectIdentity:String()
		Local result:String = "select" + nextSelectId
		nextSelectId :+ 1
		Return result
	End Method

	Method PushCleanup(cleanupStep:TGenericTemplateNode)
		activeCleanupSteps :+ [cleanupStep]
	End Method

	Method PopCleanup()
		If activeCleanupSteps.length Then activeCleanupSteps = activeCleanupSteps[..activeCleanupSteps.length - 1]
	End Method

	Method CleanupEdges:TGenericTemplateNode(cleanupDepth:Int = 0)
		If cleanupDepth < 0 Then cleanupDepth = 0
		If cleanupDepth > activeCleanupSteps.length Then cleanupDepth = activeCleanupSteps.length
		If cleanupDepth = activeCleanupSteps.length Then Return Null
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_BLOCK
		result.valueText = "cleanup-edges"
		For Local index:Int = activeCleanupSteps.length - 1 To cleanupDepth Step -1
			result.children :+ [activeCleanupSteps[index]]
		Next
		Return result
	End Method

	Method ResolveLoop:TCompilerGenericTemplateLoopContext(labelExpression:TExpressionSyntax)
		If Not labelExpression Then Return currentLoop
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(labelExpression)
		If Not name Or Not name.nameToken Then Return Null
		Local normalized:String = name.nameToken.text.ToLower()
		Local candidate:TCompilerGenericTemplateLoopContext = currentLoop
		While candidate
			If candidate.sourceLabel = normalized Then Return candidate
			candidate = candidate.parent
		Wend
		Return Null
	End Method
End Type

Type TCompilerGenericLocalRoutineContext
	Field visiting:TMap = New TMap
	Field completed:TMap = New TMap
End Type

Type TCompilerOrdinaryClassSlotLayoutEntry
	Field ordinal:Int
	Field implementation:TSymbol
End Type

Type TCompilerGenericTemplateSourceLocator
	Field model:TSemanticModel
	Field documents:TSourceDocumentModel[] = New TSourceDocumentModel[0]
	Field navigators:TSyntaxNavigator[] = New TSyntaxNavigator[0]

	Function Create:TCompilerGenericTemplateSourceLocator(model:TSemanticModel)
		Local result:TCompilerGenericTemplateSourceLocator = New TCompilerGenericTemplateSourceLocator
		result.model = model
		If model And model.snapshot Then result.documents = model.snapshot.documents
		result.navigators = New TSyntaxNavigator[result.documents.length]
		Return result
	End Function

	Method DocumentForSyntax:TSourceDocumentModel(syntax:TSyntaxNode)
		If Not syntax Then Return Null
		For Local index:Int = 0 Until documents.length
			Local document:TSourceDocumentModel = documents[index]
			If Not document Or Not document.tree Then Continue
			Local navigator:TSyntaxNavigator = navigators[index]
			If Not navigator Then
				navigator = TSyntaxNavigator.Create(document.tree)
				navigators[index] = navigator
			End If
			If navigator And navigator.ContainsNode(syntax) Then Return document
		Next
		Return Null
	End Method
End Type

Type TCompilerGenericTemplateBuilder
	' Template publication asks for hundreds of source locations from the same
	' immutable syntax trees. Keep the navigators scoped to one artifact build
	' so those trees are indexed once without retaining compiler state afterward.
	Global activeSourceLocator:TCompilerGenericTemplateSourceLocator

	Function Build:TGenericTemplateArtifact(model:TSemanticModel, symbol:TSymbol, definingModuleIdentity:String, languageLinkageRevision:String, diagnostics:String[] Var, deferContentRevision:Int = False)
		Local previousSourceLocator:TCompilerGenericTemplateSourceLocator = activeSourceLocator
		activeSourceLocator = TCompilerGenericTemplateSourceLocator.Create(model)
		Local artifact:TGenericTemplateArtifact
		Try
			artifact = BuildArtifact(model, symbol, definingModuleIdentity, languageLinkageRevision, diagnostics, deferContentRevision)
		Catch exception:Object
			activeSourceLocator = previousSourceLocator
			Throw exception
		End Try
		activeSourceLocator = previousSourceLocator
		Return artifact
	End Function

	Function BuildArtifact:TGenericTemplateArtifact(model:TSemanticModel, symbol:TSymbol, definingModuleIdentity:String, languageLinkageRevision:String, diagnostics:String[] Var, deferContentRevision:Int = False)
		If symbol And symbol.kind = SYMBOL_ROUTINE Then Return BuildRoutine(model, symbol, definingModuleIdentity, languageLinkageRevision, diagnostics, deferContentRevision)
		Local initialDiagnosticCount:Int = diagnostics.length
		If Not model Or Not symbol Or (symbol.kind <> SYMBOL_TYPE And symbol.kind <> SYMBOL_INTERFACE And symbol.kind <> SYMBOL_STRUCT) Then
			diagnostics :+ ["BMXC3030 source generic Type, Interface, or Struct symbol is required to build a template artifact"]
			Return Null
		End If
		Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(symbol.declaration)
		Local header:TTypeDeclarationHeaderSyntax
		If declaration Then header = declaration.header
		If Not header And symbol.interfaceRecord Then header = symbol.interfaceRecord.typeHeaderSyntax
		If Not header Or Not header.genericParameters.length Then
			diagnostics :+ ["BMXC3030 Type '" + symbol.name + "' is not a source generic declaration"]
			Return Null
		End If
		If Not definingModuleIdentity.length Then definingModuleIdentity = model.moduleName
		If Not definingModuleIdentity.length And model.syntaxTree And model.syntaxTree.source Then definingModuleIdentity = "source:" + model.syntaxTree.source.path

		Local artifact:TGenericTemplateArtifact = New TGenericTemplateArtifact
		artifact.identity = New TGenericTemplateIdentity
		artifact.identity.moduleName = definingModuleIdentity
		artifact.identity.qualifiedName = symbol.QualifiedName()
		artifact.identity.arity = header.genericParameters.length
		artifact.identity.declarationKind = GENERIC_DECLARATION_TYPE
		artifact.languageLinkageRevision = languageLinkageRevision
		artifact.visibility = symbol.visibility
		artifact.isAbstract = symbol.isAbstract
		artifact.metadata = TemplateMetadata(symbol, model)
		Select symbol.kind
			Case SYMBOL_INTERFACE artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE
			Case SYMBOL_STRUCT artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT
			Default artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_CLASS
		End Select

		Local parameterSymbols:TSymbol[] = New TSymbol[header.genericParameters.length]
		artifact.parameters = New TGenericTemplateParameter[header.genericParameters.length]
		For Local index:Int = 0 Until header.genericParameters.length
			Local parameterSyntax:TGenericParameterSyntax = header.genericParameters[index]
			Local parameter:TGenericTemplateParameter = New TGenericTemplateParameter
			parameter.name = parameterSyntax.nameToken.text
			parameter.ordinal = index
			If symbol.memberScope Then
				For Local candidate:TSymbol = EachIn symbol.memberScope.LookupLocal(parameter.name)
					If candidate.kind = SYMBOL_TYPE_PARAMETER Then parameterSymbols[index] = candidate; Exit
				Next
			End If
			artifact.parameters[index] = parameter
		Next
		Local inheritanceInfo:TTypeInheritanceInfo = model.InheritanceInfo(symbol)
		If inheritanceInfo Then
			For Local constraint:TGenericConstraintInfo = EachIn inheritanceInfo.constraints
				For Local parameterIndex:Int = 0 Until parameterSymbols.length
					If parameterSymbols[parameterIndex] <> constraint.parameterSymbol Then Continue
					artifact.parameters[parameterIndex].constraints = New TTemplateTypeReference[constraint.bounds.length]
					For Local boundIndex:Int = 0 Until constraint.bounds.length
						artifact.parameters[parameterIndex].constraints[boundIndex] = TemplateType(constraint.bounds[boundIndex], model, parameterSymbols, diagnostics)
					Next
					Exit
				Next
			Next
		End If

		Local additionalInterfaceStart:Int
		If header.extendsTypes.length Then
			artifact.baseType = New TGenericTemplateInheritanceReference
			artifact.baseType.semanticType = TemplateType(model.TypeOf(header.extendsTypes[0]), model, parameterSymbols, diagnostics)
			artifact.baseType.source = SourceLocation(header.extendsTypes[0], model)
			If symbol.kind = SYMBOL_INTERFACE Then additionalInterfaceStart = 1
		End If
		Local interfaceCount:Int = header.implementedTypes.length
		If symbol.kind = SYMBOL_INTERFACE Then interfaceCount = header.extendsTypes.length - additionalInterfaceStart
		artifact.interfaces = New TGenericTemplateInheritanceReference[interfaceCount]
		For Local index:Int = 0 Until interfaceCount
			Local sourceType:TTypeReferenceSyntax
			If symbol.kind = SYMBOL_INTERFACE Then
				sourceType = header.extendsTypes[index + additionalInterfaceStart]
			Else
				sourceType = header.implementedTypes[index]
			End If
			Local reference:TGenericTemplateInheritanceReference = New TGenericTemplateInheritanceReference
			reference.semanticType = TemplateType(model.TypeOf(sourceType), model, parameterSymbols, diagnostics)
			reference.source = SourceLocation(sourceType, model)
			artifact.interfaces[index] = reference
		Next

		If symbol.memberScope Then
			For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
				If member.kind = SYMBOL_TYPE_PARAMETER Then Continue
				If member.kind = SYMBOL_FIELD Then
					Local fieldDeclaration:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(member.declaration)
					Local templateField:TGenericTemplateMember = New TGenericTemplateMember
					templateField.kind = TEMPLATE_MEMBER_FIELD
					templateField.identity = "field:" + member.name.ToLower()
					templateField.name = member.name
					templateField.visibility = member.visibility
					templateField.metadata = TemplateMetadata(member, model)
					templateField.semanticType = TemplateType(member.declaredType, model, parameterSymbols, diagnostics)
					If fieldDeclaration And fieldDeclaration.initializer Then
						templateField.body = TemplateExpression(model.BoundExpression(fieldDeclaration.initializer), model, parameterSymbols, diagnostics)
					End If
					templateField.source = SourceLocation(member.declaration, model)
					artifact.members :+ [templateField]
				Else If member.kind = SYMBOL_GLOBAL Then
					Local isThreadedGlobal:Int = IsThreadedGlobalMember(member, model)
					Local globalDeclaration:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(member.declaration)
					Local templateGlobal:TGenericTemplateMember = New TGenericTemplateMember
					templateGlobal.kind = TEMPLATE_MEMBER_FIELD
					If isThreadedGlobal Then templateGlobal.identity = "threaded-static:" + member.name.ToLower() Else templateGlobal.identity = "static:" + member.name.ToLower()
					templateGlobal.name = member.name
					templateGlobal.isStatic = True
					templateGlobal.visibility = member.visibility
					templateGlobal.metadata = TemplateMetadata(member, model)
					templateGlobal.semanticType = TemplateType(member.declaredType, model, parameterSymbols, diagnostics)
					If globalDeclaration And globalDeclaration.initializer Then
						templateGlobal.body = TemplateExpression(model.BoundExpression(globalDeclaration.initializer), model, parameterSymbols, diagnostics)
					End If
					templateGlobal.source = SourceLocation(member.declaration, model)
					artifact.members :+ [templateGlobal]
				Else If member.kind = SYMBOL_ROUTINE Then
					If member.genericArity Then
						' Method-owned generic routines are published and
						' specialized as independently owned routine artifacts.
						Continue
					End If
					Local templateMethod:TGenericTemplateMember = New TGenericTemplateMember
					templateMethod.kind = TEMPLATE_MEMBER_METHOD
					Local routineDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(member.declaration)
					' Static generic member lowering is currently established for
					' Struct values. Generic Type functions still participate in the
					' existing class-slot model until that ABI is designed separately.
					templateMethod.isStatic = routineDeclaration And Not routineDeclaration.isMethod And symbol.kind = SYMBOL_STRUCT
					templateMethod.isTypeFunction = routineDeclaration And Not routineDeclaration.isMethod And symbol.kind = SYMBOL_TYPE
					If symbol.kind = SYMBOL_INTERFACE Then templateMethod.interfaceMethodKind = member.interfaceMethodKind
					templateMethod.identity = "method:" + member.name.ToLower() + "/" + member.parameters.length
					templateMethod.name = member.name
					templateMethod.visibility = member.visibility
					templateMethod.metadata = TemplateMetadata(member, model)
					templateMethod.semanticType = TemplateType(member.declaredType, model, parameterSymbols, diagnostics)
					templateMethod.parameters = New TGenericTemplateValueParameter[member.parameters.length]
					For Local index:Int = 0 Until member.parameters.length
						Local sourceParameter:TSemanticParameter = member.parameters[index]
						Local templateParameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
						If sourceParameter.symbol Then templateParameter.name = sourceParameter.symbol.name Else templateParameter.name = "arg" + index
						templateParameter.ordinal = index
						templateParameter.semanticType = TemplateType(sourceParameter.semanticType, model, parameterSymbols, diagnostics)
						templateParameter.passingMode = sourceParameter.passingMode
						templateParameter.optional = sourceParameter.optional
						If sourceParameter.symbol Then templateParameter.source = SourceLocation(sourceParameter.symbol.declaration, model)
						If sourceParameter.optional Then templateParameter.defaultValue = TemplateDefaultValue(sourceParameter, templateParameter.semanticType, model, parameterSymbols, diagnostics)
						templateMethod.parameters[index] = templateParameter
					Next
					If member.name.ToLower() = "new" Then
						templateMethod.identity = "constructor:" + TCompilerGenericSpecializationLowerer.ConstructorSignatureKey(templateMethod.parameters)
					End If
					templateMethod.body = TemplateBlock(model.BoundRoutineBody(member), model, parameterSymbols, diagnostics)
					templateMethod.source = SourceLocation(member.declaration, model)
					artifact.members :+ [templateMethod]
				Else If member.kind = SYMBOL_CONST Then
					' Const members have no specialization storage or ownership.
					' Fold their already-evaluated scalar value into every bound
					' body use; the resulting literals participate in the
					' artifact revision while the compact .i retains the public
					' Const declaration.
					Local constant:TConstantValue = model.SymbolConstantValue(member)
					If Not constant Or (constant.kind <> CONSTANT_VALUE_INTEGER And constant.kind <> CONSTANT_VALUE_FLOAT) Then
						diagnostics :+ ["BMXC3033 generic Type Const '" + member.name + "' requires a scalar numeric compile-time value"]
					End If
				Else If member.kind = SYMBOL_TYPE Or member.kind = SYMBOL_STRUCT Or member.kind = SYMBOL_INTERFACE Or member.kind = SYMBOL_ENUM Then
					' Nested declarations own independent nominal/template
					' identities. They are indexed and published from their own
					' member scopes rather than copied into the outer artifact.
					Continue
				Else
					diagnostics :+ ["BMXC3033 generic Type member '" + member.name + "' has unsupported declaration kind " + member.KindName()]
				End If
			Next
		End If
		If diagnostics.length > initialDiagnosticCount Then Return artifact
		If deferContentRevision Then Return artifact
		Local revisionDiagnostics:String[]
		artifact.contentRevision = TGenericTemplateArtifactCodec.ComputeContentRevision(artifact, revisionDiagnostics)
		diagnostics :+ revisionDiagnostics
		Return artifact
	End Function

	Function IsThreadedGlobalMember:Int(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Or Not symbol.declaration Or Not symbol.declaration.span Or Not model Or Not model.syntaxTree Or Not model.syntaxTree.source Then Return False
		Local source:TSourceText = model.syntaxTree.source
		Local start:Int = symbol.declaration.span.start
		While start > 0 And source.text[start - 1] <> 10 And source.text[start - 1] <> 13
			start :- 1
		Wend
		Local prefix:String = source.text[start..symbol.declaration.span.start].ToLower()
		Return prefix.Contains("threadedglobal")
	End Function

	Function TemplateDefaultValue:TGenericTemplateNode(sourceParameter:TSemanticParameter, targetType:TTemplateTypeReference, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int = TEMPLATE_PARAMETER_OWNER_TYPE)
		Local parameterName:String = "<unnamed>"
		If sourceParameter And sourceParameter.symbol Then parameterName = sourceParameter.symbol.name
		If Not sourceParameter Or Not sourceParameter.defaultValue Then
			diagnostics :+ ["BMXC3069 optional generic parameter '" + parameterName + "' has no evaluated constant default"]
			Return Null
		End If
		Local constant:TConstantValue = sourceParameter.defaultValue
		If constant.kind = CONSTANT_VALUE_CALLABLE Then
			diagnostics :+ ["BMXC3069 optional generic parameter '" + parameterName + "' requires a numeric, String, enum, or Null constant default in the current canonical template format"]
			Return Null
		End If
		If constant.kind <> CONSTANT_VALUE_INTEGER And constant.kind <> CONSTANT_VALUE_FLOAT And constant.kind <> CONSTANT_VALUE_STRING And constant.kind <> CONSTANT_VALUE_NULL Then
			diagnostics :+ ["BMXC3069 optional generic parameter '" + parameterName + "' has an unsupported constant default"]
			Return Null
		End If
		Local literal:TGenericTemplateNode = New TGenericTemplateNode
		literal.kind = TEMPLATE_NODE_LITERAL
		If constant.kind = CONSTANT_VALUE_STRING Then
			literal.identity = "string-code-units"
			literal.valueText = EncodeStringCodeUnits(constant.stringValue)
		Else
			literal.valueText = constant.DisplayValue()
		End If
		If sourceParameter.symbol Then literal.source = SourceLocation(sourceParameter.symbol.declaration, model)
		If constant.kind <> CONSTANT_VALUE_NULL Then
			literal.semanticType = targetType
			Return literal
		End If
		literal.semanticType = TemplateType(constant.semanticType, model, parameters, diagnostics, parameterOwner)
		Local conversion:TGenericTemplateNode = New TGenericTemplateNode
		conversion.kind = TEMPLATE_NODE_CONVERSION
		conversion.semanticType = targetType
		conversion.source = literal.source
		conversion.children = [literal]
		Return conversion
	End Function

	Function TemplateResolvedCallArgument:TGenericTemplateNode(argument:TBoundExpression, index:Int, resolved:TResolvedCall, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, localRoutineContext:TCompilerGenericLocalRoutineContext)
		If argument And Not TBoundOmittedArgumentExpression(argument) Then
			Return TemplateExpression(argument, model, parameters, diagnostics, parameterOwner, localRoutineContext)
		End If
		If Not resolved Or Not resolved.routine Or index < 0 Or index >= resolved.routine.parameters.length Then
			diagnostics :+ ["BMXC3069 omitted generic-template call argument has no resolved parameter"]
			Return Null
		End If
		Local sourceParameter:TSemanticParameter = resolved.routine.parameters[index]
		If Not sourceParameter.optional Then
			diagnostics :+ ["BMXC3069 omitted generic-template call argument " + index + " is not optional"]
			Return Null
		End If
		Local targetSemanticType:TSemanticType = sourceParameter.semanticType
		If index < resolved.parameterTypes.length And resolved.parameterTypes[index] Then targetSemanticType = resolved.parameterTypes[index]
		Local targetType:TTemplateTypeReference = TemplateType(targetSemanticType, model, parameters, diagnostics, parameterOwner)
		Return TemplateDefaultValue(sourceParameter, targetType, model, parameters, diagnostics, parameterOwner)
	End Function

	Function BuildRoutine:TGenericTemplateArtifact(model:TSemanticModel, symbol:TSymbol, definingModuleIdentity:String, languageLinkageRevision:String, diagnostics:String[] Var, deferContentRevision:Int = False)
		Local initialDiagnosticCount:Int = diagnostics.length
		Local declaration:TRoutineDeclarationSyntax
		If symbol Then declaration = TRoutineDeclarationSyntax(symbol.declaration)
		If Not model Or Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or Not declaration Or symbol.genericArity <= 0 Then
			diagnostics :+ ["BMXC3030 source generic routine symbol is required to build a template artifact"]
			Return Null
		End If
		Local owner:TSymbol
		If declaration.isMethod And symbol.containingScope Then owner = symbol.containingScope.owner
		Local ownerDeclaration:TTypeDeclarationSyntax
		Local ownerArity:Int
		If owner Then ownerDeclaration = TTypeDeclarationSyntax(owner.declaration)
		If ownerDeclaration And ownerDeclaration.header Then ownerArity = ownerDeclaration.header.genericParameters.length
		If declaration.isMethod And (Not owner Or (owner.kind <> SYMBOL_TYPE And owner.kind <> SYMBOL_STRUCT And owner.kind <> SYMBOL_INTERFACE)) Then
			diagnostics :+ ["BMXC3032 generic methods require a containing Type, Struct, or Interface"]
			Return Null
		End If
		If Not definingModuleIdentity.length Then definingModuleIdentity = model.moduleName
		If Not definingModuleIdentity.length And model.syntaxTree And model.syntaxTree.source Then definingModuleIdentity = "source:" + model.syntaxTree.source.path

		Local artifact:TGenericTemplateArtifact = New TGenericTemplateArtifact
		artifact.identity = New TGenericTemplateIdentity
		artifact.identity.moduleName = definingModuleIdentity
		artifact.identity.qualifiedName = symbol.QualifiedName()
		artifact.identity.arity = symbol.genericArity
		artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE
		artifact.languageLinkageRevision = languageLinkageRevision
		artifact.visibility = symbol.visibility
		artifact.isMethod = declaration.isMethod
		If owner And owner.kind = SYMBOL_STRUCT Then artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_STRUCT
		If owner And owner.kind = SYMBOL_INTERFACE Then artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE
		If owner Then
			artifact.containingParameters = New TGenericTemplateParameter[ownerArity]
			For Local ownerIndex:Int = 0 Until artifact.containingParameters.length
				Local ownerParameter:TGenericTemplateParameter = New TGenericTemplateParameter
				ownerParameter.name = ownerDeclaration.header.genericParameters[ownerIndex].nameToken.text
				ownerParameter.ordinal = ownerIndex
				artifact.containingParameters[ownerIndex] = ownerParameter
			Next
		End If

		Local containingParameterSymbols:TSymbol[] = New TSymbol[artifact.containingParameters.length]
		For Local ownerIndex:Int = 0 Until artifact.containingParameters.length
			For Local candidate:TSymbol = EachIn owner.memberScope.LookupLocal(artifact.containingParameters[ownerIndex].name)
				If candidate.kind = SYMBOL_TYPE_PARAMETER Then containingParameterSymbols[ownerIndex] = candidate; Exit
			Next
		Next
		Local routineParameterSymbols:TSymbol[] = New TSymbol[symbol.genericArity]
		artifact.parameters = New TGenericTemplateParameter[symbol.genericArity]
		For Local parameterIndex:Int = 0 Until declaration.signature.genericParameters.length
			Local parameterSyntax:TGenericParameterSyntax = declaration.signature.genericParameters[parameterIndex]
			Local parameter:TGenericTemplateParameter = New TGenericTemplateParameter
			parameter.name = parameterSyntax.nameToken.text
			parameter.ordinal = parameterIndex
			artifact.parameters[parameterIndex] = parameter
			If symbol.memberScope Then
				For Local candidate:TSymbol = EachIn symbol.memberScope.LookupLocal(parameter.name)
					If candidate.kind = SYMBOL_TYPE_PARAMETER Then routineParameterSymbols[parameterIndex] = candidate; Exit
				Next
			End If
		Next
		Local parameterSymbols:TSymbol[] = containingParameterSymbols + routineParameterSymbols
		Local templateParameterOwner:Int = TEMPLATE_PARAMETER_OWNER_ROUTINE
		If artifact.isMethod Then templateParameterOwner = TEMPLATE_PARAMETER_OWNER_MIXED
		If owner Then
			Local ownerInheritance:TTypeInheritanceInfo = model.InheritanceInfo(owner)
			If ownerInheritance Then
				For Local constraint:TGenericConstraintInfo = EachIn ownerInheritance.constraints
					For Local ownerIndex:Int = 0 Until containingParameterSymbols.length
						If containingParameterSymbols[ownerIndex] <> constraint.parameterSymbol Then Continue
						artifact.containingParameters[ownerIndex].constraints = New TTemplateTypeReference[constraint.bounds.length]
						For Local boundIndex:Int = 0 Until constraint.bounds.length
							artifact.containingParameters[ownerIndex].constraints[boundIndex] = TemplateType(constraint.bounds[boundIndex], model, parameterSymbols, diagnostics, templateParameterOwner)
						Next
						Exit
					Next
				Next
			End If
			If Not owner.memberScope Then
				diagnostics :+ ["BMXC3065 generic method containing owner has no bound member layout"]
			Else If ownerArity Then
				' Constructed generic owners receive their concrete field ABI
				' from the canonical owner specialization. Their open template
				' fields deliberately do not claim one ordinary linkage name.
				For Local ownerMember:TSymbol = EachIn owner.memberScope.declaredSymbols
					If ownerMember.kind <> SYMBOL_FIELD Then Continue
					Local containingField:TGenericTemplateMember = New TGenericTemplateMember
					containingField.kind = TEMPLATE_MEMBER_FIELD
					Local fieldReference:TTemplateSymbolReference = SymbolReference(ownerMember, model)
					containingField.identity = "field:" + fieldReference.StableName()
					containingField.name = ownerMember.name
					containingField.visibility = ownerMember.visibility
					containingField.metadata = TemplateMetadata(ownerMember, model)
					containingField.semanticType = TemplateType(ownerMember.declaredType, model, parameterSymbols, diagnostics, templateParameterOwner)
					containingField.source = SourceLocation(ownerMember.declaration, model)
					artifact.containingFields :+ [containingField]
				Next
			Else If owner.kind <> SYMBOL_INTERFACE
				AppendContainingFields(owner.declaredType, model, parameterSymbols, diagnostics, templateParameterOwner, definingModuleIdentity, languageLinkageRevision, artifact.containingFields, New TMap, 0)
			End If
		End If
		If owner Then
			If ownerArity = 0 Then
				artifact.containingType = TemplateType(owner.declaredType, model, parameterSymbols, diagnostics, templateParameterOwner)
				If artifact.containingType And Not artifact.containingType.runtimeAbiName.length Then
					artifact.containingType.runtimeAbiName = TCompilerDirectMethodAbi.OwnerAbiName(model, owner)
					If owner.kind = SYMBOL_STRUCT Then
						artifact.containingType.runtimeKind = TEMPLATE_RUNTIME_STRUCT
					Else If owner.kind = SYMBOL_INTERFACE Then
						artifact.containingType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE
					Else
						artifact.containingType.runtimeKind = TEMPLATE_RUNTIME_CLASS
					End If
				End If
			Else
				artifact.containingType = New TTemplateTypeReference
				artifact.containingType.kind = TEMPLATE_TYPE_NAMED
				artifact.containingType.moduleName = owner.originModule
				If Not artifact.containingType.moduleName.length Then artifact.containingType.moduleName = model.moduleName
				artifact.containingType.symbolName = owner.QualifiedName()
				artifact.containingType.arguments = New TTemplateTypeReference[artifact.containingParameters.length]
				For Local ownerIndex:Int = 0 Until artifact.containingType.arguments.length
					Local ownerArgument:TTemplateTypeReference = New TTemplateTypeReference
					ownerArgument.kind = TEMPLATE_TYPE_PARAMETER
					ownerArgument.parameterOwner = TEMPLATE_PARAMETER_OWNER_TYPE
					ownerArgument.parameterIndex = ownerIndex
					artifact.containingType.arguments[ownerIndex] = ownerArgument
				Next
			End If
		End If
		For Local constraint:TGenericConstraintInfo = EachIn symbol.genericConstraints
			For Local parameterIndex:Int = 0 Until routineParameterSymbols.length
				If routineParameterSymbols[parameterIndex] <> constraint.parameterSymbol Then Continue
				artifact.parameters[parameterIndex].constraints = New TTemplateTypeReference[constraint.bounds.length]
				For Local boundIndex:Int = 0 Until constraint.bounds.length
					artifact.parameters[parameterIndex].constraints[boundIndex] = TemplateType(constraint.bounds[boundIndex], model, parameterSymbols, diagnostics, templateParameterOwner)
				Next
				Exit
			Next
		Next

		Local member:TGenericTemplateMember = New TGenericTemplateMember
		member.kind = TEMPLATE_MEMBER_METHOD
		member.identity = "routine:" + symbol.name.ToLower() + "/" + symbol.parameters.length
		member.name = symbol.name
		member.visibility = symbol.visibility
		member.metadata = TemplateMetadata(symbol, model)
		member.semanticType = TemplateType(symbol.declaredType, model, parameterSymbols, diagnostics, templateParameterOwner)
		member.parameters = New TGenericTemplateValueParameter[symbol.parameters.length]
		For Local index:Int = 0 Until symbol.parameters.length
			Local sourceParameter:TSemanticParameter = symbol.parameters[index]
			Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
			If sourceParameter.symbol Then parameter.name = sourceParameter.symbol.name Else parameter.name = "arg" + index
			parameter.ordinal = index
			parameter.semanticType = TemplateType(sourceParameter.semanticType, model, parameterSymbols, diagnostics, templateParameterOwner)
			parameter.passingMode = sourceParameter.passingMode
			parameter.optional = sourceParameter.optional
			If sourceParameter.symbol Then parameter.source = SourceLocation(sourceParameter.symbol.declaration, model)
			If sourceParameter.optional Then parameter.defaultValue = TemplateDefaultValue(sourceParameter, parameter.semanticType, model, parameterSymbols, diagnostics, templateParameterOwner)
			member.parameters[index] = parameter
		Next
		If Not symbol.isAbstract Then member.body = TemplateBlock(model.BoundRoutineBody(symbol), model, parameterSymbols, diagnostics, templateParameterOwner)
		member.source = SourceLocation(symbol.declaration, model)
		artifact.members = [member]
		artifact.identity.signatureKey = RoutineSignatureKey(member)
		If diagnostics.length > initialDiagnosticCount Then Return artifact
		If deferContentRevision Then Return artifact
		Local revisionDiagnostics:String[]
		artifact.contentRevision = TGenericTemplateArtifactCodec.ComputeContentRevision(artifact, revisionDiagnostics)
		diagnostics :+ revisionDiagnostics
		Return artifact
	End Function

	Function AppendContainingFields(ownerType:TSemanticType, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, definingModuleIdentity:String, languageLinkageRevision:String, fields:TGenericTemplateMember[] Var, visited:TMap, depth:Int)
		If depth > 64 Then
			diagnostics :+ ["BMXC3065 generic method owner inheritance exceeds the supported depth"]
			Return
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(ownerType)
		If Not named Or Not named.symbol Then
			diagnostics :+ ["BMXC3065 generic method owner inheritance requires a resolved ordinary Type"]
			Return
		End If
		If named.symbol.kind = SYMBOL_STRUCT Then
			If depth Then diagnostics :+ ["BMXC3065 Struct generic method owners cannot have a base Type"]
		Else If named.symbol.kind <> SYMBOL_TYPE Then
			diagnostics :+ ["BMXC3065 generic method owner inheritance requires a Type prefix layout"]
			Return
		End If
		Local key:String = named.symbol.originModule.ToLower() + "::" + named.symbol.QualifiedName().ToLower()
		If visited.Contains(key) Then
			diagnostics :+ ["BMXC3065 generic method owner inheritance contains a recursive layout"]
			Return
		End If
		visited.Insert(key, named.symbol)

		Local substitutions:TMap = TCompilerGenericInheritance.TypeSubstitutions(named)
		Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If inheritance Then
			For Local edge:TInheritanceEdge = EachIn inheritance.baseEdges
				If Not edge Or edge.isImplicit Then Continue
				Local baseType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, substitutions)
				AppendContainingFields(baseType, model, parameters, diagnostics, parameterOwner, definingModuleIdentity, languageLinkageRevision, fields, visited, depth + 1)
			Next
		End If

		Local ownerAbiName:String
		If named.symbol.genericArity Or named.typeArguments.length Then
			ownerAbiName = ClosedGenericOwnerAbiName(named, model, parameters, diagnostics, parameterOwner, definingModuleIdentity, languageLinkageRevision)
		Else
			ownerAbiName = TCompilerDirectMethodAbi.OwnerAbiName(model, named.symbol)
		End If
		If named.symbol.memberScope Then
			For Local ownerMember:TSymbol = EachIn named.symbol.memberScope.declaredSymbols
				If ownerMember.kind <> SYMBOL_FIELD Then Continue
				Local containingField:TGenericTemplateMember = New TGenericTemplateMember
				containingField.kind = TEMPLATE_MEMBER_FIELD
				Local fieldReference:TTemplateSymbolReference = SymbolReference(ownerMember, model)
				containingField.identity = "field:" + fieldReference.StableName()
				containingField.name = ownerMember.name
				containingField.linkageName = ContainingFieldLinkageName(named.symbol, ownerMember, model, ownerAbiName)
				If Not containingField.linkageName.length Then
					diagnostics :+ ["BMXC3065 generic method owner field '" + ownerMember.name + "' has no stable language-linkage identity"]
				End If
				containingField.visibility = ownerMember.visibility
				containingField.metadata = TemplateMetadata(ownerMember, model)
				Local fieldType:TSemanticType = TGenericRoutineInference.Substitute(ownerMember.declaredType, substitutions)
				containingField.semanticType = TemplateType(fieldType, model, parameters, diagnostics, parameterOwner)
				containingField.source = SourceLocation(ownerMember.declaration, model)
				fields :+ [containingField]
			Next
		End If
		visited.Remove(key)
	End Function

	Function ClosedGenericOwnerAbiName:String(named:TNamedSemanticType, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, definingModuleIdentity:String, languageLinkageRevision:String)
		If Not named Or Not named.symbol Then Return ""
		Local templateArtifact:TGenericTemplateArtifact = named.symbol.genericTemplateArtifact
		If Not templateArtifact And Not named.symbol.isImported Then
			Local artifactDiagnostics:String[]
			templateArtifact = Build(model, named.symbol, definingModuleIdentity, languageLinkageRevision, artifactDiagnostics)
			diagnostics :+ artifactDiagnostics
			If templateArtifact Then named.symbol.genericTemplateArtifact = templateArtifact
		End If
		If Not templateArtifact Or Not templateArtifact.identity Then
			diagnostics :+ ["BMXC3065 constructed generic method-owner base '" + named.DisplayName() + "' has no canonical template artifact"]
			Return ""
		End If
		If named.typeArguments.length <> templateArtifact.parameters.length Then
			diagnostics :+ ["BMXC3065 constructed generic method-owner base '" + named.DisplayName() + "' has incompatible canonical arguments"]
			Return ""
		End If
		Local arguments:TTemplateTypeReference[] = New TTemplateTypeReference[named.typeArguments.length]
		For Local index:Int = 0 Until arguments.length
			arguments[index] = TemplateType(named.typeArguments[index], model, parameters, diagnostics, parameterOwner)
			If Not arguments[index] Then Return ""
		Next
		Local specializationKey:TCanonicalSpecializationKey = New TCanonicalSpecializationKey
		specializationKey.templateIdentity = templateArtifact.identity
		specializationKey.typeArguments = arguments
		specializationKey.languageIdentityConfiguration = "language=" + languageLinkageRevision.ToLower()
		Local identityDigest:String = TCompilerStableDigest.Sha256(specializationKey.CanonicalName())
		Return TGenericSpecializationRegistry.ReadableAbiNameFor(templateArtifact, specializationKey, identityDigest)
	End Function

	Function ContainingFieldLinkageName:String(owner:TSymbol, memberSymbol:TSymbol, model:TSemanticModel, ownerAbiName:String = "")
		If Not owner Or Not memberSymbol Then Return ""
		If memberSymbol.externalName.length Then Return memberSymbol.externalName
		If Not ownerAbiName.length Then
			If owner.isImported Then
				ownerAbiName = owner.externalName
			Else If owner.visibility = VISIBILITY_PUBLIC Then
				ownerAbiName = TCompilerAbiNamer.ClassName(model, owner, "")
			End If
		End If
		If Not ownerAbiName.length Then Return ""
		Return TCompilerAbiNamer.FieldName(ownerAbiName, memberSymbol.name)
	End Function

	Function RoutineSignatureKey:String(member:TGenericTemplateMember)
		If Not member Then Return ""
		Local result:String = "result=" + TemplateSignatureType(member.semanticType) + ";parameters="
		For Local index:Int = 0 Until member.parameters.length
			If index Then result :+ ","
			result :+ member.parameters[index].passingMode + ":" + TemplateSignatureType(member.parameters[index].semanticType)
		Next
		Return result
	End Function

	Function SymbolRoutineSignatureKey:String(model:TSemanticModel, symbol:TSymbol)
		If Not model Or Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or symbol.genericArity <= 0 Then Return ""
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If Not declaration Then Return ""
		Local containingSymbols:TSymbol[] = New TSymbol[0]
		If declaration.isMethod And symbol.containingScope And symbol.containingScope.owner Then
			Local owner:TSymbol = symbol.containingScope.owner
			Local ownerDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(owner.declaration)
			If ownerDeclaration And ownerDeclaration.header Then
				containingSymbols = New TSymbol[ownerDeclaration.header.genericParameters.length]
				For Local ownerIndex:Int = 0 Until containingSymbols.length
					Local ownerName:String = ownerDeclaration.header.genericParameters[ownerIndex].nameToken.text
					For Local candidate:TSymbol = EachIn owner.memberScope.LookupLocal(ownerName)
						If candidate.kind = SYMBOL_TYPE_PARAMETER Then containingSymbols[ownerIndex] = candidate; Exit
					Next
				Next
			End If
		End If
		Local routineSymbols:TSymbol[] = New TSymbol[symbol.genericArity]
		For Local index:Int = 0 Until declaration.signature.genericParameters.length
			Local name:String = declaration.signature.genericParameters[index].nameToken.text
			If symbol.memberScope Then
				For Local candidate:TSymbol = EachIn symbol.memberScope.LookupLocal(name)
					If candidate.kind = SYMBOL_TYPE_PARAMETER Then routineSymbols[index] = candidate; Exit
				Next
			End If
		Next
		Local parameterSymbols:TSymbol[] = containingSymbols + routineSymbols
		Local parameterOwner:Int = TEMPLATE_PARAMETER_OWNER_ROUTINE
		If declaration.isMethod Then parameterOwner = TEMPLATE_PARAMETER_OWNER_MIXED
		Local ignored:String[]
		Local member:TGenericTemplateMember = New TGenericTemplateMember
		member.semanticType = TemplateType(symbol.declaredType, model, parameterSymbols, ignored, parameterOwner)
		member.parameters = New TGenericTemplateValueParameter[symbol.parameters.length]
		For Local index:Int = 0 Until symbol.parameters.length
			Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
			parameter.passingMode = symbol.parameters[index].passingMode
			parameter.semanticType = TemplateType(symbol.parameters[index].semanticType, model, parameterSymbols, ignored, parameterOwner)
			member.parameters[index] = parameter
		Next
		If ignored.length Then Return ""
		Return RoutineSignatureKey(member)
	End Function

	Function TemplateSignatureType:String(value:TTemplateTypeReference)
		If Not value Then Return "void"
		Return value.CanonicalName()
	End Function

	Function TemplateType:TTemplateTypeReference(value:TSemanticType, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int = TEMPLATE_PARAMETER_OWNER_TYPE)
		If Not value Then Return Null
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If builtin Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_BUILTIN
			result.symbolName = builtin.name
			Return result
		End If
		Local typeParameter:TTypeParameterSemanticType = TTypeParameterSemanticType(value)
		If typeParameter Then
			Local fallbackIndex:Int = -1
			Local fallbackCount:Int
			For Local index:Int = 0 Until parameters.length
				If Not parameters[index] Or Not typeParameter.symbol Or parameters[index].name.ToLower() <> typeParameter.symbol.name.ToLower() Then Continue
				If parameters[index].originModule.length And typeParameter.symbol.originModule.length And parameters[index].originModule.ToLower() <> typeParameter.symbol.originModule.ToLower() Then Continue
				If parameters[index].originPath.length And typeParameter.symbol.originPath.length And parameters[index].originPath.Replace("\", "/").ToLower() <> typeParameter.symbol.originPath.Replace("\", "/").ToLower() Then Continue
				fallbackIndex = index
				fallbackCount :+ 1
			Next
			For Local index:Int = 0 Until parameters.length
				Local ownsParameter:Int = parameters[index] = typeParameter.symbol
				' Reconstructed inherited/closed semantic types can carry a fresh
				' symbol object for the same declared parameter. Its qualified source
				' identity is authoritative when pointer identity is unavailable.
				If Not ownsParameter And parameters[index] And typeParameter.symbol And parameters[index].QualifiedName().ToLower() = typeParameter.symbol.QualifiedName().ToLower() Then
					ownsParameter = True
					If parameters[index].originModule.length And typeParameter.symbol.originModule.length And parameters[index].originModule.ToLower() <> typeParameter.symbol.originModule.ToLower() Then ownsParameter = False
					If parameters[index].originPath.length And typeParameter.symbol.originPath.length And parameters[index].originPath.Replace("\", "/").ToLower() <> typeParameter.symbol.originPath.Replace("\", "/").ToLower() Then ownsParameter = False
				End If
				If Not ownsParameter And fallbackCount = 1 And fallbackIndex = index Then ownsParameter = True
				If ownsParameter Then
					Local result:TTemplateTypeReference = New TTemplateTypeReference
					result.kind = TEMPLATE_TYPE_PARAMETER
					If parameterOwner = TEMPLATE_PARAMETER_OWNER_MIXED Then
						Local owner:TSymbol
						If parameters[index].containingScope Then owner = parameters[index].containingScope.owner
						If owner And owner.kind = SYMBOL_ROUTINE Then result.parameterOwner = TEMPLATE_PARAMETER_OWNER_ROUTINE Else result.parameterOwner = TEMPLATE_PARAMETER_OWNER_TYPE
						result.parameterIndex = 0
						For Local earlier:Int = 0 Until index
							Local earlierOwner:TSymbol
							If parameters[earlier] And parameters[earlier].containingScope Then earlierOwner = parameters[earlier].containingScope.owner
							Local earlierParameterOwner:Int = TEMPLATE_PARAMETER_OWNER_TYPE
							If earlierOwner And earlierOwner.kind = SYMBOL_ROUTINE Then earlierParameterOwner = TEMPLATE_PARAMETER_OWNER_ROUTINE
							If earlierParameterOwner = result.parameterOwner Then result.parameterIndex :+ 1
						Next
					Else
						result.parameterIndex = index
						result.parameterOwner = parameterOwner
					End If
					Return result
				End If
			Next
			diagnostics :+ ["BMXC3034 unowned type parameter '" + typeParameter.DisplayName() + "' in generic template"]
			Return Null
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If named Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_NAMED
			If named.symbol Then
				result.moduleName = named.symbol.originModule
				' Prefer the generic artifact's canonical declaration owner.  Quoted
				' source imports can otherwise acquire a second identity from their
				' relative import path when nested closed types are reconstructed.
				If named.symbol.genericTemplateArtifact And named.symbol.genericTemplateArtifact.identity Then result.moduleName = named.symbol.genericTemplateArtifact.identity.moduleName
				If Not result.moduleName.length And named.symbol.isImported And named.symbol.originPath.length Then result.moduleName = "source:" + named.symbol.originPath.Replace("\", "/")
				If Not result.moduleName.length Then result.moduleName = model.moduleName
				' Include files contribute declarations to this model; their originPath
				' remains source provenance, not a distinct canonical code owner.
				If Not result.moduleName.length And model.syntaxTree And model.syntaxTree.source Then result.moduleName = "source:" + model.syntaxTree.source.path.Replace("\", "/")
				If Not result.moduleName.length And named.symbol.originPath.length Then result.moduleName = "source:" + named.symbol.originPath.Replace("\", "/")
				result.symbolName = named.symbol.QualifiedName()
				' Generic named values still have a concrete runtime category even
				' though their specialization ABI is assigned later. Preserve that
				' category so deferred overload selection can apply Object widening
				' to closed generic classes and interfaces without mistaking Structs
				' for managed references.
				If named.symbol.kind = SYMBOL_INTERFACE Then
					result.runtimeKind = TEMPLATE_RUNTIME_INTERFACE
				Else If named.symbol.kind = SYMBOL_STRUCT Then
					result.runtimeKind = TEMPLATE_RUNTIME_STRUCT
				Else If named.symbol.kind = SYMBOL_TYPE Then
					result.runtimeKind = TEMPLATE_RUNTIME_CLASS
				End If
				If named.symbol.kind = SYMBOL_ENUM Then
					result.runtimeKind = TEMPLATE_RUNTIME_ENUM
					If named.symbol.isImported And named.symbol.externalName.length Then
						result.runtimeAbiName = named.symbol.externalName
					Else
						result.runtimeAbiName = TCompilerDirectMethodAbi.OwnerAbiName(model, named.symbol)
					End If
					result.runtimeValueType = EnumUnderlyingTypeName(named.symbol, model)
					If Not result.runtimeValueType.length Then diagnostics :+ ["BMXC3034 Enum type '" + named.symbol.QualifiedName() + "' has an unsupported integral value type"]
				Else If named.symbol.genericArity = 0 And named.typeArguments.length = 0 And (named.symbol.kind = SYMBOL_TYPE Or named.symbol.kind = SYMBOL_INTERFACE Or named.symbol.kind = SYMBOL_STRUCT) Then
					If named.symbol.isImported And named.symbol.externalName.length Then
						result.runtimeAbiName = named.symbol.externalName
					Else If Not named.symbol.isImported Then
						' A template implementation is emitted in a separate C
						' unit even when its ordinary runtime type is private to
						' the current source. Publish the same deterministic ABI
						' identity into the template type reference that the
						' owning application/module IR will select below.
						result.runtimeAbiName = TCompilerDirectMethodAbi.OwnerAbiName(model, named.symbol)
					End If
					If result.runtimeAbiName.length Then
						If named.symbol.kind = SYMBOL_INTERFACE Then
							result.runtimeKind = TEMPLATE_RUNTIME_INTERFACE
						Else If named.symbol.kind = SYMBOL_STRUCT Then
							result.runtimeKind = TEMPLATE_RUNTIME_STRUCT
						Else
							result.runtimeKind = TEMPLATE_RUNTIME_CLASS
						End If
					End If
				End If
			End If
			result.arguments = New TTemplateTypeReference[named.typeArguments.length]
			For Local index:Int = 0 Until named.typeArguments.length
				result.arguments[index] = TemplateType(named.typeArguments[index], model, parameters, diagnostics, parameterOwner)
			Next
			Return result
		End If
		Local pointer:TPointerSemanticType = TPointerSemanticType(value)
		If pointer Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_POINTER
			result.elementType = TemplateType(pointer.elementType, model, parameters, diagnostics, parameterOwner)
			Return result
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_ARRAY
			result.rank = arrayType.rank
			result.elementType = TemplateType(arrayType.elementType, model, parameters, diagnostics, parameterOwner)
			Return result
		End If
		Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(value)
		If staticArrayType Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_STATIC_ARRAY
			result.staticArrayLength = staticArrayType.length
			If result.staticArrayLength <= 0 And staticArrayType.boundSyntax And staticArrayType.boundSyntax.lengthExpression Then
				Local lengthValue:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(model, staticArrayType.boundSyntax.lengthExpression)
				If lengthValue And lengthValue.kind = CONSTANT_VALUE_INTEGER Then result.staticArrayLength = lengthValue.integerValue
			End If
			result.elementType = TemplateType(staticArrayType.elementType, model, parameters, diagnostics, parameterOwner)
			Return result
		End If
		Local closureType:TClosureSemanticType = TClosureSemanticType(value)
		If closureType And closureType.signature Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_CLOSURE
			result.elementType = TemplateType(closureType.signature.returnType, model, parameters, diagnostics, parameterOwner)
			result.arguments = New TTemplateTypeReference[closureType.signature.parameterTypes.length]
			result.callableParameterModes = closureType.signature.parameterModes[..]
			result.callableParameterNames = closureType.parameterNames[..]
			For Local index:Int = 0 Until closureType.signature.parameterTypes.length
				result.arguments[index] = TemplateType(closureType.signature.parameterTypes[index], model, parameters, diagnostics, parameterOwner)
			Next
			Return result
		End If
		Local callableType:TCallableSemanticType = TCallableSemanticType(value)
		If callableType Then
			Local result:TTemplateTypeReference = New TTemplateTypeReference
			result.kind = TEMPLATE_TYPE_CALLABLE
			result.elementType = TemplateType(callableType.returnType, model, parameters, diagnostics, parameterOwner)
			result.arguments = New TTemplateTypeReference[callableType.parameterTypes.length]
			result.callableParameterModes = callableType.parameterModes[..]
			For Local index:Int = 0 Until callableType.parameterTypes.length
				result.arguments[index] = TemplateType(callableType.parameterTypes[index], model, parameters, diagnostics, parameterOwner)
			Next
			Return result
		End If
		diagnostics :+ ["BMXC3035 semantic type '" + value.DisplayName() + "' cannot be represented by template artifact version " + GENERIC_TEMPLATE_FORMAT_VERSION]
		Return Null
	End Function

	Function EnumUnderlyingTypeName:String(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Or symbol.kind <> SYMBOL_ENUM Or Not model Then Return ""
		Local underlying:TSemanticType = model.BuiltinType("Int")
		If symbol.isImported And symbol.interfaceRecord And symbol.interfaceRecord.baseTypeSyntax Then
			underlying = model.TypeOf(symbol.interfaceRecord.baseTypeSyntax)
		Else
			Local declaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(symbol.declaration)
			If declaration And declaration.underlyingType Then underlying = model.TypeOf(declaration.underlyingType)
		End If
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(underlying)
		If Not builtin Then Return ""
		If Not TCompilerGenericSpecializationLowerer.EnumValueTypeSupported(builtin.name) Then Return ""
		Return builtin.name.ToLower()
	End Function

	Function TemplateEachInOperation:TGenericTemplateNode(resolved:TResolvedCall, receiverType:TSemanticType, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, source:TTemplateSourceLocation)
		If Not resolved Or Not resolved.routine Then
			diagnostics :+ ["BMXC3057 generic Interface EachIn is missing a bound protocol operation"]
			Return Null
		End If
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_CALL
		result.valueText = resolved.routine.name
		result.referencedSymbol = SymbolReference(resolved.routine, model)
		result.semanticType = TemplateType(resolved.returnType, model, parameters, diagnostics, parameterOwner)
		result.source = source
		Local receiver:TGenericTemplateNode = New TGenericTemplateNode
		receiver.kind = TEMPLATE_NODE_DECLARATION
		receiver.valueText = "eachin-protocol-receiver"
		receiver.semanticType = TemplateType(receiverType, model, parameters, diagnostics, parameterOwner)
		receiver.source = source
		result.children = [receiver]
		For Local parameterIndex:Int = 0 Until resolved.routine.parameters.length
			Local parameter:TSemanticParameter = resolved.routine.parameters[parameterIndex]
			If Not parameter.optional Then
				diagnostics :+ ["BMXC3057 EachIn protocol operation '" + resolved.routine.name + "' requires a non-default argument"]
				Return Null
			End If
			Local parameterType:TSemanticType = parameter.semanticType
			If parameterIndex < resolved.parameterTypes.length And resolved.parameterTypes[parameterIndex] Then parameterType = resolved.parameterTypes[parameterIndex]
			Local templateParameterType:TTemplateTypeReference = TemplateType(parameterType, model, parameters, diagnostics, parameterOwner)
			Local defaultArgument:TGenericTemplateNode = TemplateDefaultValue(parameter, templateParameterType, model, parameters, diagnostics, parameterOwner)
			If Not defaultArgument Then Return Null
			result.children :+ [defaultArgument]
		Next
		If receiver.semanticType And receiver.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And receiver.semanticType.runtimeAbiName.length > 0 Then
			result.runtimeDispatchIndex = OrdinaryClassDispatchIndex(resolved.routine, receiverType, model, diagnostics)
			If result.runtimeDispatchIndex >= 0 Then result.runtimeDispatchKind = TEMPLATE_DISPATCH_ORDINARY_CLASS
		End If
		Return result
	End Function

	Function OrdinaryClassDispatchIndex:Int(routine:TSymbol, receiverType:TSemanticType, model:TSemanticModel, diagnostics:String[] Var)
		Local receiver:TNamedSemanticType = TNamedSemanticType(receiverType)
		If Not routine Or Not receiver Or Not receiver.symbol Or receiver.symbol.kind <> SYMBOL_TYPE Or Not receiver.symbol.memberScope Then
			diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator operation has no bound class layout identity"]
			Return -1
		End If
		Local slots:TCompilerOrdinaryClassSlotLayoutEntry[]
		Local slotsByRoutine:TMap = New TMap
		Local visiting:TMap = New TMap
		If Not BuildOrdinaryClassSlotLayout(receiver.symbol, model, slots, slotsByRoutine, visiting, diagnostics) Then Return -1
		Local entry:TCompilerOrdinaryClassSlotLayoutEntry = TCompilerOrdinaryClassSlotLayoutEntry(slotsByRoutine.ValueForKey(routine))
		If Not entry Then
			diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator operation '" + routine.name + "' has no stable inherited or declared virtual-slot ordinal"]
			Return -1
		End If
		If entry.ordinal >= 40 Then
			diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator operation '" + routine.name + "' exceeds the runtime virtual-slot ABI range"]
			Return -1
		End If
		Return entry.ordinal
	End Function

	Function OrdinaryInterfaceDispatchIndex:Int(routine:TSymbol, receiverType:TSemanticType, model:TSemanticModel, diagnostics:String[] Var)
		Local receiver:TNamedSemanticType = TNamedSemanticType(receiverType)
		If Not routine Or Not receiver Or Not receiver.symbol Or receiver.symbol.kind <> SYMBOL_INTERFACE Or Not receiver.symbol.memberScope Then
			diagnostics :+ ["BMXC3057 ordinary Interface operation has no bound Interface layout identity"]
			Return -1
		End If
		Local slots:TCompilerOrdinaryClassSlotLayoutEntry[]
		Local slotsByRoutine:TMap = New TMap
		Local visiting:TMap = New TMap
		If Not BuildOrdinaryInterfaceSlotLayout(receiver.symbol, model, slots, slotsByRoutine, visiting, diagnostics) Then Return -1
		Local entry:TCompilerOrdinaryClassSlotLayoutEntry = TCompilerOrdinaryClassSlotLayoutEntry(slotsByRoutine.ValueForKey(routine))
		If Not entry Then
			diagnostics :+ ["BMXC3057 ordinary Interface operation '" + routine.name + "' has no stable inherited or declared slot ordinal"]
			Return -1
		End If
		Return entry.ordinal
	End Function

	Function BuildOrdinaryInterfaceSlotLayout:Int(symbol:TSymbol, model:TSemanticModel, slots:TCompilerOrdinaryClassSlotLayoutEntry[] Var, slotsByRoutine:TMap, visiting:TMap, diagnostics:String[] Var)
		If Not symbol Or Not symbol.memberScope Or Not model Then Return False
		If visiting.Contains(symbol) Then
			diagnostics :+ ["BMXC3057 ordinary Interface '" + symbol.QualifiedName() + "' has a recursive layout"]
			Return False
		End If
		visiting.Insert(symbol, symbol)
		Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(symbol)
		If inheritance Then
			Local edges:TInheritanceEdge[] = inheritance.baseEdges + inheritance.interfaceEdges
			For Local edge:TInheritanceEdge = EachIn edges
				Local parent:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
				If Not parent Or Not parent.symbol Or parent.symbol.kind <> SYMBOL_INTERFACE Then Continue
				If Not BuildOrdinaryInterfaceSlotLayout(parent.symbol, model, slots, slotsByRoutine, visiting, diagnostics) Then
					visiting.Remove(symbol)
					Return False
				End If
			Next
		End If
		For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
			If Not member Or member.kind <> SYMBOL_ROUTINE Or member.genericArity Then Continue
			If slotsByRoutine.Contains(member) Then Continue
			Local entry:TCompilerOrdinaryClassSlotLayoutEntry = New TCompilerOrdinaryClassSlotLayoutEntry
			entry.ordinal = slots.length
			entry.implementation = member
			slots :+ [entry]
			slotsByRoutine.Insert(member, entry)
		Next
		visiting.Remove(symbol)
		Return True
	End Function

	Function BuildOrdinaryClassSlotLayout:Int(symbol:TSymbol, model:TSemanticModel, slots:TCompilerOrdinaryClassSlotLayoutEntry[] Var, slotsByRoutine:TMap, visiting:TMap, diagnostics:String[] Var)
		If Not symbol Or Not symbol.memberScope Or Not model Then Return False
		If visiting.Contains(symbol) Then
			diagnostics :+ ["BMXC3059 ordinary ObjectEnumerator receiver '" + symbol.QualifiedName() + "' has a recursive class layout"]
			Return False
		End If
		visiting.Insert(symbol, symbol)
		Local baseSymbol:TSymbol
		Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(symbol)
		If inheritance Then
			For Local edge:TInheritanceEdge = EachIn inheritance.baseEdges
				Local baseType:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
				If baseType And baseType.symbol And baseType.symbol.kind = SYMBOL_TYPE Then
					baseSymbol = baseType.symbol
					Exit
				End If
			Next
		End If
		If baseSymbol And baseSymbol.name.ToLower() <> "object" Then
			If Not BuildOrdinaryClassSlotLayout(baseSymbol, model, slots, slotsByRoutine, visiting, diagnostics) Then
				visiting.Remove(symbol)
				Return False
			End If
		End If
		For Local member:TSymbol = EachIn symbol.memberScope.declaredSymbols
			If Not OrdinaryClassSlotMember(member) Then Continue
			Local entry:TCompilerOrdinaryClassSlotLayoutEntry
			Local memberDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(member.declaration)
			If memberDeclaration And memberDeclaration.isMethod And baseSymbol Then
				Local validator:TInheritanceValidator = New TInheritanceValidator
				validator.model = model
				Local overridden:TSymbol = validator.OverriddenRoutine(member, baseSymbol.declaredType, 0)
				If overridden Then entry = TCompilerOrdinaryClassSlotLayoutEntry(slotsByRoutine.ValueForKey(overridden))
			End If
			If entry Then
				entry.implementation = member
				slots[entry.ordinal] = entry
			Else
				entry = New TCompilerOrdinaryClassSlotLayoutEntry
				entry.ordinal = slots.length
				entry.implementation = member
				slots :+ [entry]
			End If
			slotsByRoutine.Insert(member, entry)
		Next
		visiting.Remove(symbol)
		Return True
	End Function

	Function OrdinaryClassSlotMember:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or symbol.genericArity <> 0 Then Return False
		Local name:String = symbol.name.ToLower()
		If name = "new" Or name = "delete" Then Return False
		If OrdinaryObjectSlotKind(symbol) Then Return False
		Return True
	End Function

	Function OrdinaryObjectSlotKind:Int(symbol:TSymbol)
		If Not symbol Then Return False
		Local returnType:TBuiltinSemanticType = TBuiltinSemanticType(symbol.declaredType)
		Local returnName:String
		If returnType Then returnName = returnType.name.ToLower()
		Select symbol.name.ToLower()
			Case "tostring"
				Return symbol.parameters.length = 0 And returnName = "string"
			Case "compare"
				Return symbol.parameters.length = 1 And returnName = "int" And IsBuiltinSemanticType(symbol.parameters[0].semanticType, "object")
			Case "sendmessage"
				Return symbol.parameters.length = 2 And returnName = "object" And IsBuiltinSemanticType(symbol.parameters[0].semanticType, "object") And IsBuiltinSemanticType(symbol.parameters[1].semanticType, "object")
			Case "hashcode"
				Return symbol.parameters.length = 0 And returnName = "uint"
			Case "equals"
				Return symbol.parameters.length = 1 And returnName = "int" And IsBuiltinSemanticType(symbol.parameters[0].semanticType, "object")
		End Select
		Return False
	End Function

	Function IsBuiltinSemanticType:Int(value:TSemanticType, name:String)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		Return builtin And builtin.name.ToLower() = name
	End Function

	Function TemplateLoopLabel:String(syntax:TSyntaxNode)
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

	Function TemplateBlock:TGenericTemplateNode(block:TBoundBlockStatement, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int = TEMPLATE_PARAMETER_OWNER_TYPE, context:TCompilerGenericTemplateBodyContext = Null)
		If Not block Then Return Null
		If Not context Then context = New TCompilerGenericTemplateBodyContext
		If Not context.localRoutineContext Then context.localRoutineContext = New TCompilerGenericLocalRoutineContext
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_BLOCK
		result.source = SourceLocation(block.syntax, model)
		For Local statement:TBoundStatement = EachIn block.statements
			Local templateStatement:TGenericTemplateNode = TemplateStatement(statement, model, parameters, diagnostics, parameterOwner, context)
			If templateStatement Then result.children :+ [templateStatement]
		Next
		Return result
	End Function

	Function TemplateLocalDeclaration:TGenericTemplateNode(variable:TBoundVariable, statement:TBoundStatement, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, context:TCompilerGenericTemplateBodyContext)
		If Not variable Or Not variable.symbol Or (variable.symbol.kind <> SYMBOL_LOCAL And variable.symbol.kind <> SYMBOL_CONST) Then
			diagnostics :+ ["BMXC3049 generic sequential bodies require semantic Local or local Const declarations"]
			Return Null
		End If
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_DECLARATION
		result.valueText = variable.symbol.name
		If variable.symbol.isReadOnly Or variable.symbol.kind = SYMBOL_CONST Then result.identity = "readonly"
		result.semanticType = TemplateType(variable.symbol.declaredType, model, parameters, diagnostics, parameterOwner)
		result.source = SourceLocation(statement.syntax, model)
		If variable.initializer Then
			Local initializer:TGenericTemplateNode = TemplateExpression(variable.initializer, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If initializer Then result.children = [initializer]
		Else If variable.arrayDimensions.length Then
			Local declaredArray:TArraySemanticType = TArraySemanticType(variable.symbol.declaredType)
			If Not declaredArray Or variable.arrayDimensions.length <> declaredArray.rank Then
				diagnostics :+ ["BMXC3063 generic managed Array declaration allocation requires one dimension per declared rank"]
				Return Null
			End If
			Local allocation:TGenericTemplateNode = New TGenericTemplateNode
			allocation.kind = TEMPLATE_NODE_NEW
			allocation.semanticType = result.semanticType
			allocation.source = result.source
			For Local dimensionExpression:TBoundExpression = EachIn variable.arrayDimensions
				Local dimension:TGenericTemplateNode = TemplateExpression(dimensionExpression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				If dimension Then allocation.children :+ [dimension]
			Next
			result.children = [allocation]
		End If
		Return result
	End Function

	Function SupportedLoopTarget:Int(expression:TBoundExpression)
		Local symbolExpression:TBoundSymbolExpression = TBoundSymbolExpression(expression)
		If symbolExpression And symbolExpression.symbol Then
			Select symbolExpression.symbol.kind
				Case SYMBOL_LOCAL, SYMBOL_PARAMETER, SYMBOL_FIELD, SYMBOL_GLOBAL
					Return True
			End Select
		End If
		Local memberExpression:TBoundMemberExpression = TBoundMemberExpression(expression)
		If memberExpression And memberExpression.access And memberExpression.access.member Then
			Return memberExpression.access.member.kind = SYMBOL_FIELD Or memberExpression.access.member.kind = SYMBOL_GLOBAL
		End If
		Local indexExpression:TBoundIndexExpression = TBoundIndexExpression(expression)
		If indexExpression And indexExpression.access And indexExpression.access.accessKind = INDEX_ACCESS_ARRAY And indexExpression.indexes.length = 1 Then Return True
		Return False
	End Function

	Function CloseableInterfaceType:TNamedSemanticType(value:TSemanticType, model:TSemanticModel, depth:Int = 0)
		If depth > 64 Or Not value Or Not model Then Return Null
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		If Not named Or Not named.symbol Then Return Null
		If named.symbol.kind = SYMBOL_INTERFACE And named.symbol.name.ToLower() = "icloseable" Then Return named
		Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(named.symbol)
		If Not inheritance Then Return Null
		Local substitutions:TMap = TCompilerGenericInheritance.TypeSubstitutions(named)
		For Local edge:TInheritanceEdge = EachIn inheritance.baseEdges + inheritance.interfaceEdges
			If Not edge Then Continue
			Local inheritedType:TSemanticType = TGenericRoutineInference.Substitute(edge.semanticType, substitutions)
			Local found:TNamedSemanticType = CloseableInterfaceType(inheritedType, model, depth + 1)
			If found Then Return found
		Next
		Return Null
	End Function

	Function TemplateUsingCloseCall:TGenericTemplateNode(variable:TBoundVariable, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, context:TCompilerGenericTemplateBodyContext)
		If Not variable Or Not variable.symbol Then Return Null
		Local closeable:TNamedSemanticType = CloseableInterfaceType(variable.symbol.declaredType, model)
		If Not closeable Or Not closeable.symbol Or Not closeable.symbol.memberScope Then
			diagnostics :+ ["BMXC3073 generic Using resource '" + variable.symbol.name + "' does not expose an ICloseable Interface contract"]
			Return Null
		End If
		Local closeRoutine:TSymbol
		For Local candidate:TSymbol = EachIn closeable.symbol.memberScope.LookupLocal("close")
			If candidate And candidate.kind = SYMBOL_ROUTINE And Not candidate.parameters.length Then closeRoutine = candidate; Exit
		Next
		Local interfaceCloseRoutine:TSymbol = closeRoutine
		Local resourceType:TNamedSemanticType = TNamedSemanticType(variable.symbol.declaredType)
		If resourceType And resourceType.symbol And resourceType.symbol.memberScope Then
			For Local candidate:TSymbol = EachIn resourceType.symbol.memberScope.LookupLocal("close")
				If candidate And candidate.kind = SYMBOL_ROUTINE And Not candidate.parameters.length Then closeRoutine = candidate; Exit
			Next
		End If
		If Not closeRoutine Then
			diagnostics :+ ["BMXC3073 generic Using ICloseable contract has no parameterless Close method"]
			Return Null
		End If
		Local receiver:TBoundSymbolExpression = New TBoundSymbolExpression
		receiver.boundKind = BOUND_EXPRESSION_SYMBOL
		receiver.semanticType = variable.symbol.declaredType
		receiver.symbol = variable.symbol
		If resourceType And resourceType.symbol Then
			Local interfaceType:TTemplateTypeReference = TemplateType(closeable, model, parameters, diagnostics, parameterOwner)
			If Not interfaceType Or interfaceType.runtimeKind <> TEMPLATE_RUNTIME_INTERFACE Or Not interfaceType.runtimeAbiName.length Then
				diagnostics :+ ["BMXC3073 generic Using ICloseable contract has no published ordinary Interface ABI"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_CALL
			result.identity = "ordinary-interface-call"
			result.valueText = "Close"
			result.semanticType = TemplateType(closeRoutine.declaredType, model, parameters, diagnostics, parameterOwner)
			result.referencedSymbol = SymbolReference(interfaceCloseRoutine, model)
			result.referencedSymbol.overloadKey = interfaceType.runtimeAbiName
			result.runtimeDispatchIndex = OrdinaryInterfaceDispatchIndex(interfaceCloseRoutine, closeable, model, diagnostics)
			If result.runtimeDispatchIndex >= 0 Then result.runtimeDispatchKind = TEMPLATE_DISPATCH_ORDINARY_CLASS
			Local receiverNode:TGenericTemplateNode = TemplateExpression(receiver, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If receiverNode Then result.children = [receiverNode]
			Return result
		End If
		Local resolved:TResolvedCall = New TResolvedCall
		resolved.routine = closeRoutine
		resolved.returnType = closeRoutine.declaredType
		resolved.parameterTypes = New TSemanticType[0]
		Local call:TBoundCallExpression = New TBoundCallExpression
		call.boundKind = BOUND_EXPRESSION_CALL
		call.semanticType = resolved.returnType
		call.isSynthetic = True
		call.resolvedCall = resolved
		call.receiver = receiver
		Return TemplateExpression(call, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
	End Function

	Function TemplateStatement:TGenericTemplateNode(statement:TBoundStatement, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int = TEMPLATE_PARAMETER_OWNER_TYPE, context:TCompilerGenericTemplateBodyContext = Null)
		If Not context Then context = New TCompilerGenericTemplateBodyContext
		Local variables:TBoundVariableDeclarationStatement = TBoundVariableDeclarationStatement(statement)
		If variables Then
			If Not variables.variables.length Then Return Null
			Local declarations:TGenericTemplateNode = New TGenericTemplateNode
			declarations.kind = TEMPLATE_NODE_BLOCK
			declarations.valueText = "local-declarations"
			declarations.source = SourceLocation(statement.syntax, model)
			For Local variable:TBoundVariable = EachIn variables.variables
				Local declaration:TGenericTemplateNode = TemplateLocalDeclaration(variable, statement, model, parameters, diagnostics, parameterOwner, context)
				If declaration Then declarations.children :+ [declaration]
			Next
			If declarations.children.length = 1 Then Return declarations.children[0]
			Return declarations
		End If
		Local conditional:TBoundIfStatement = TBoundIfStatement(statement)
		If conditional Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_BRANCH
			result.valueText = "if"
			result.semanticType = TemplateType(conditional.condition.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(statement.syntax, model)
			Local condition:TGenericTemplateNode = TemplateExpression(conditional.condition, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			Local thenBody:TGenericTemplateNode = TemplateBlock(conditional.thenBody, model, parameters, diagnostics, parameterOwner, context)
			If condition And thenBody Then result.children = [condition, thenBody]
			For Local clause:TBoundConditionalClause = EachIn conditional.elseIfClauses
				If Not clause Then Continue
				Local clauseCondition:TGenericTemplateNode = TemplateExpression(clause.condition, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				Local clauseBody:TGenericTemplateNode = TemplateBlock(clause.body, model, parameters, diagnostics, parameterOwner, context)
				If clauseCondition And clauseBody Then result.children :+ [clauseCondition, clauseBody]
			Next
			If conditional.elseBody Then
				Local elseBody:TGenericTemplateNode = TemplateBlock(conditional.elseBody, model, parameters, diagnostics, parameterOwner, context)
				If elseBody Then result.children :+ [elseBody]
			End If
			Return result
		End If
		Local whileStatement:TBoundWhileStatement = TBoundWhileStatement(statement)
		If whileStatement Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_LOOP
			result.valueText = "while"
			Local loop:TCompilerGenericTemplateLoopContext = context.BeginLoop(TemplateLoopLabel(statement.syntax))
			result.identity = loop.identity
			result.semanticType = TemplateType(whileStatement.condition.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(statement.syntax, model)
			Local condition:TGenericTemplateNode = TemplateExpression(whileStatement.condition, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			Local body:TGenericTemplateNode = TemplateBlock(whileStatement.body, model, parameters, diagnostics, parameterOwner, context)
			context.EndLoop(loop)
			If condition And body Then result.children = [condition, body]
			Return result
		End If
		Local repeatStatement:TBoundRepeatStatement = TBoundRepeatStatement(statement)
		If repeatStatement Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_LOOP
			result.valueText = "repeat-until"
			If repeatStatement.isForever Then result.valueText = "repeat-forever"
			Local loop:TCompilerGenericTemplateLoopContext = context.BeginLoop(TemplateLoopLabel(statement.syntax))
			result.identity = loop.identity
			result.source = SourceLocation(statement.syntax, model)
			Local body:TGenericTemplateNode = TemplateBlock(repeatStatement.body, model, parameters, diagnostics, parameterOwner, context)
			context.EndLoop(loop)
			If body Then result.children = [body]
			If Not repeatStatement.isForever Then
				result.semanticType = TemplateType(repeatStatement.condition.semanticType, model, parameters, diagnostics, parameterOwner)
				Local condition:TGenericTemplateNode = TemplateExpression(repeatStatement.condition, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				If condition Then result.children :+ [condition]
			End If
			Return result
		End If
		Local forStatement:TBoundForStatement = TBoundForStatement(statement)
		If forStatement Then
			If forStatement.isEachIn Then
				If Not forStatement.iteration Then
					diagnostics :+ ["BMXC3054 generic EachIn has no resolved iteration protocol"]
					Return Null
				End If
				If forStatement.iteration.protocolKind <> EACH_IN_PROTOCOL_STRING And forStatement.iteration.protocolKind <> EACH_IN_PROTOCOL_ARRAY And forStatement.iteration.protocolKind <> EACH_IN_PROTOCOL_STATIC_ARRAY And forStatement.iteration.protocolKind <> EACH_IN_PROTOCOL_ITERABLE And forStatement.iteration.protocolKind <> EACH_IN_PROTOCOL_ITERATOR And forStatement.iteration.protocolKind <> EACH_IN_PROTOCOL_OBJECT_ENUMERATOR Then
					diagnostics :+ ["BMXC3054 generic EachIn protocol " + forStatement.iteration.protocolKind + " is unsupported"]
					Return Null
				End If
				If Not forStatement.loopVariable And Not SupportedLoopTarget(forStatement.target) Then
					diagnostics :+ ["BMXC3054 generic EachIn target must be a declared loop Local or an assignable Local, Var parameter, Field, or published Global"]
					Return Null
				End If
				If (forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERABLE Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERATOR Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR) And (Not forStatement.iteration.advance Or Not forStatement.iteration.current Or ((forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERABLE Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR) And Not forStatement.iteration.iteratorFactory)) Then
					diagnostics :+ ["BMXC3057 generic EachIn has incomplete bound protocol operations"]
					Return Null
				End If
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_LOOP
				Select forStatement.iteration.protocolKind
					Case EACH_IN_PROTOCOL_STRING
						result.valueText = "eachin-string"
					Case EACH_IN_PROTOCOL_ARRAY
						result.valueText = "eachin-array"
					Case EACH_IN_PROTOCOL_STATIC_ARRAY
						result.valueText = "eachin-static-array"
					Case EACH_IN_PROTOCOL_ITERABLE
						result.valueText = "eachin-iterable"
					Case EACH_IN_PROTOCOL_ITERATOR
						result.valueText = "eachin-iterator"
					Case EACH_IN_PROTOCOL_OBJECT_ENUMERATOR
						result.valueText = "eachin-object-enumerator"
				End Select
				Local loop:TCompilerGenericTemplateLoopContext = context.BeginLoop(TemplateLoopLabel(statement.syntax))
				result.identity = loop.identity
				result.source = SourceLocation(statement.syntax, model)
				Local target:TGenericTemplateNode
				If forStatement.loopVariable Then
					target = New TGenericTemplateNode
					target.kind = TEMPLATE_NODE_DECLARATION
					target.valueText = forStatement.loopVariable.name
					target.semanticType = TemplateType(forStatement.loopVariable.declaredType, model, parameters, diagnostics, parameterOwner)
					target.source = result.source
				Else
					target = TemplateExpression(forStatement.target, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				End If
				Local collection:TGenericTemplateNode = TemplateExpression(forStatement.collection, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				If forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERABLE Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERATOR Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR Then
					Local iteratorType:TGenericTemplateNode = New TGenericTemplateNode
					iteratorType.kind = TEMPLATE_NODE_DECLARATION
					iteratorType.valueText = "iterator"
					iteratorType.semanticType = TemplateType(forStatement.iteration.iteratorType, model, parameters, diagnostics, parameterOwner)
					iteratorType.source = result.source
					Local factory:TGenericTemplateNode = New TGenericTemplateNode
					factory.kind = TEMPLATE_NODE_LITERAL
					factory.valueText = "direct"
					factory.source = result.source
					If forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_ITERABLE Or forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR Then factory = TemplateEachInOperation(forStatement.iteration.iteratorFactory, forStatement.collection.semanticType, model, parameters, diagnostics, parameterOwner, result.source)
					Local advance:TGenericTemplateNode = TemplateEachInOperation(forStatement.iteration.advance, forStatement.iteration.iteratorType, model, parameters, diagnostics, parameterOwner, result.source)
					Local current:TGenericTemplateNode = TemplateEachInOperation(forStatement.iteration.current, forStatement.iteration.iteratorType, model, parameters, diagnostics, parameterOwner, result.source)
					Local cleanupStep:TGenericTemplateNode = New TGenericTemplateNode
					cleanupStep.kind = TEMPLATE_NODE_BLOCK
					cleanupStep.valueText = "cleanup-iterator"
					cleanupStep.identity = loop.identity
					cleanupStep.source = result.source
					context.PushCleanup(cleanupStep)
					loop.continueCleanupDepth = context.activeCleanupSteps.length
					Local body:TGenericTemplateNode = TemplateBlock(forStatement.body, model, parameters, diagnostics, parameterOwner, context)
					context.PopCleanup()
					context.EndLoop(loop)
					If forStatement.iteration.protocolKind = EACH_IN_PROTOCOL_OBJECT_ENUMERATOR Then
						Local adaptation:TGenericTemplateNode = New TGenericTemplateNode
						adaptation.kind = TEMPLATE_NODE_CONVERSION
						adaptation.identity = "legacy-object-adaptation"
						adaptation.valueText = "object-checked-cast"
						If target Then adaptation.semanticType = target.semanticType
						adaptation.source = result.source
						If target And target.semanticType And target.semanticType.kind = TEMPLATE_TYPE_BUILTIN And target.semanticType.symbolName.ToLower() = "object" Then adaptation.valueText = "object-direct"
						If target And target.semanticType And target.semanticType.kind = TEMPLATE_TYPE_BUILTIN And target.semanticType.symbolName.ToLower() = "string" Then adaptation.valueText = "object-string"
						If target And TCompilerGenericSpecializationLowerer.ScalarNumericTemplateType(target.semanticType) Then adaptation.valueText = "object-numeric"
						If target And collection And iteratorType And factory And advance And current And adaptation And body Then result.children = [target, collection, iteratorType, factory, advance, current, adaptation, body]
						Return result
					End If
					If target And collection And iteratorType And factory And advance And current And body Then result.children = [target, collection, iteratorType, factory, advance, current, body]
					Return result
				End If
				Local body:TGenericTemplateNode = TemplateBlock(forStatement.body, model, parameters, diagnostics, parameterOwner, context)
				context.EndLoop(loop)
				If target And collection And body Then result.children = [target, collection, body]
				Return result
			End If
			If Not forStatement.loopVariable And Not SupportedLoopTarget(forStatement.target) Then
				diagnostics :+ ["BMXC3052 generic range For target must be a declared loop Local or an assignable Local, Var parameter, Field, or published Global"]
				Return Null
			End If
			Local syntax:TForStatementSyntax = TForStatementSyntax(statement.syntax)
			If Not syntax Or Not syntax.header Or Not syntax.header.rangeToken Then
				diagnostics :+ ["BMXC3052 generic range For has no bound To/Until identity"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_LOOP
			result.valueText = "for-" + syntax.header.rangeToken.text.ToLower()
			Local unaryStep:TBoundUnaryExpression = TBoundUnaryExpression(forStatement.stepExpression)
			If unaryStep And unaryStep.operatorText = "-" Then result.valueText = result.valueText + "-down"
			Local loop:TCompilerGenericTemplateLoopContext = context.BeginLoop(TemplateLoopLabel(statement.syntax))
			result.identity = loop.identity
			result.source = SourceLocation(statement.syntax, model)
			Local target:TGenericTemplateNode
			If forStatement.loopVariable Then
				target = New TGenericTemplateNode
				target.kind = TEMPLATE_NODE_DECLARATION
				target.valueText = forStatement.loopVariable.name
				target.semanticType = TemplateType(forStatement.loopVariable.declaredType, model, parameters, diagnostics, parameterOwner)
				target.source = result.source
			Else
				target = TemplateExpression(forStatement.target, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			End If
			Local initialValue:TGenericTemplateNode = TemplateExpression(forStatement.initialValue, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			Local limitValue:TGenericTemplateNode = TemplateExpression(forStatement.limit, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			Local stepValue:TGenericTemplateNode
			If forStatement.stepExpression Then
				stepValue = TemplateExpression(forStatement.stepExpression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			Else
				stepValue = New TGenericTemplateNode
				stepValue.kind = TEMPLATE_NODE_LITERAL
				stepValue.valueText = "1"
				If target Then stepValue.semanticType = target.semanticType
				stepValue.source = result.source
			End If
			Local body:TGenericTemplateNode = TemplateBlock(forStatement.body, model, parameters, diagnostics, parameterOwner, context)
			context.EndLoop(loop)
			If target And initialValue And limitValue And stepValue And body Then result.children = [target, initialValue, limitValue, stepValue, body]
			Return result
		End If
		Local selected:TBoundSelectStatement = TBoundSelectStatement(statement)
		If selected Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_SELECT
			result.identity = context.NewSelectIdentity()
			result.semanticType = TemplateType(selected.expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(statement.syntax, model)
			Local selector:TGenericTemplateNode = TemplateExpression(selected.expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If selector Then result.children = [selector]
			For Local selectedCase:TBoundSelectCase = EachIn selected.cases
				If Not selectedCase Then Continue
				Local caseNode:TGenericTemplateNode = New TGenericTemplateNode
				caseNode.kind = TEMPLATE_NODE_BLOCK
				caseNode.valueText = "select-case"
				caseNode.source = SourceLocation(selectedCase.syntax, model)
				For Local caseValue:TBoundExpression = EachIn selectedCase.values
					Local valueNode:TGenericTemplateNode = TemplateExpression(caseValue, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
					If valueNode Then caseNode.children :+ [valueNode]
				Next
				Local caseBody:TGenericTemplateNode = TemplateBlock(selectedCase.body, model, parameters, diagnostics, parameterOwner, context)
				If caseBody Then caseNode.children :+ [caseBody]
				result.children :+ [caseNode]
			Next
			If selected.defaultBody Then
				Local defaultNode:TGenericTemplateNode = New TGenericTemplateNode
				defaultNode.kind = TEMPLATE_NODE_BLOCK
				defaultNode.valueText = "select-default"
				defaultNode.source = result.source
				Local defaultBody:TGenericTemplateNode = TemplateBlock(selected.defaultBody, model, parameters, diagnostics, parameterOwner, context)
				If defaultBody Then defaultNode.children = [defaultBody]
				result.children :+ [defaultNode]
			End If
			Return result
		End If
		Local guarded:TBoundTryStatement = TBoundTryStatement(statement)
		If guarded Then
			If Not guarded.catches.length And Not guarded.finallyBody Then
				diagnostics :+ ["BMXC3072 generic Try requires Catch or Finally routing"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_TRY
			If guarded.catches.length And guarded.finallyBody Then
				result.valueText = "catch-finally"
			Else If guarded.catches.length Then
				result.valueText = "catch"
			Else
				result.valueText = "finally"
			End If
			result.source = SourceLocation(statement.syntax, model)
			result.identity = "try" + result.source.start
			' Build the Finally body outside its own cleanup edge: a transfer
			' originating in Finally runs only enclosing cleanups.
			Local finallyBody:TGenericTemplateNode
			If guarded.finallyBody Then
				finallyBody = TemplateBlock(guarded.finallyBody, model, parameters, diagnostics, parameterOwner, context)
				Local cleanupStep:TGenericTemplateNode = New TGenericTemplateNode
				cleanupStep.kind = TEMPLATE_NODE_BLOCK
				cleanupStep.valueText = "cleanup-finally"
				cleanupStep.source = result.source
				If finallyBody Then cleanupStep.children = [finallyBody]
				context.PushCleanup(cleanupStep)
			End If
			If guarded.catches.length Then
				Local catchFrameCleanup:TGenericTemplateNode = New TGenericTemplateNode
				catchFrameCleanup.kind = TEMPLATE_NODE_BLOCK
				catchFrameCleanup.valueText = "cleanup-try"
				catchFrameCleanup.source = result.source
				context.PushCleanup(catchFrameCleanup)
			End If
			context.activeYieldExceptionFrameDepth :+ (guarded.catches.length > 0) + (guarded.finallyBody <> Null)
			Local body:TGenericTemplateNode = TemplateBlock(guarded.body, model, parameters, diagnostics, parameterOwner, context)
			context.activeYieldExceptionFrameDepth :- (guarded.catches.length > 0) + (guarded.finallyBody <> Null)
			If guarded.catches.length Then context.PopCleanup()
			If body Then result.children = [body]
			For Local guardedCatch:TBoundCatchClause = EachIn guarded.catches
				If Not guardedCatch Or Not guardedCatch.parameter Then Continue
				Local catchNode:TGenericTemplateNode = New TGenericTemplateNode
				catchNode.kind = TEMPLATE_NODE_BLOCK
				catchNode.valueText = "catch-clause"
				catchNode.source = SourceLocation(guardedCatch.syntax, model)
				Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
				parameterNode.kind = TEMPLATE_NODE_DECLARATION
				parameterNode.identity = "catch-parameter"
				parameterNode.valueText = guardedCatch.parameter.name
				parameterNode.semanticType = TemplateType(guardedCatch.parameter.declaredType, model, parameters, diagnostics, parameterOwner)
				parameterNode.source = catchNode.source
				If guarded.finallyBody Then context.activeYieldExceptionFrameDepth :+ 1
				Local catchBody:TGenericTemplateNode = TemplateBlock(guardedCatch.body, model, parameters, diagnostics, parameterOwner, context)
				If guarded.finallyBody Then context.activeYieldExceptionFrameDepth :- 1
				If parameterNode.semanticType And catchBody Then catchNode.children = [parameterNode, catchBody]
				result.children :+ [catchNode]
			Next
			If guarded.finallyBody Then
				context.PopCleanup()
				If finallyBody Then
					Local finallyNode:TGenericTemplateNode = New TGenericTemplateNode
					finallyNode.kind = TEMPLATE_NODE_BLOCK
					finallyNode.valueText = "finally-body"
					finallyNode.source = result.source
					finallyNode.children = [finallyBody]
					result.children :+ [finallyNode]
				End If
			End If
			Return result
		End If
		Local usingStatement:TBoundUsingStatement = TBoundUsingStatement(statement)
		If usingStatement Then
			If Not usingStatement.resources.length Then
				diagnostics :+ ["BMXC3073 generic Using requires at least one bound resource"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_USING
			result.identity = "using" + SourceLocation(statement.syntax, model).start
			result.source = SourceLocation(statement.syntax, model)
			Local cleanupStep:TGenericTemplateNode = New TGenericTemplateNode
			cleanupStep.kind = TEMPLATE_NODE_BLOCK
			cleanupStep.valueText = "cleanup-using"
			cleanupStep.identity = result.identity
			cleanupStep.source = result.source
			For Local boundResource:TBoundVariableDeclarationStatement = EachIn usingStatement.resources
				If Not boundResource Or boundResource.variables.length <> 1 Then
					diagnostics :+ ["BMXC3073 generic Using requires one resource per declaration"]
					Return Null
				End If
				Local variable:TBoundVariable = boundResource.variables[0]
				Local declaration:TGenericTemplateNode = TemplateLocalDeclaration(variable, boundResource, model, parameters, diagnostics, parameterOwner, context)
				Local closeCall:TGenericTemplateNode = TemplateUsingCloseCall(variable, model, parameters, diagnostics, parameterOwner, context)
				If Not declaration Or Not closeCall Then Return Null
				Local resource:TGenericTemplateNode = New TGenericTemplateNode
				resource.kind = TEMPLATE_NODE_BLOCK
				resource.valueText = "using-resource"
				resource.source = SourceLocation(boundResource.syntax, model)
				resource.children = [declaration, closeCall]
				result.children :+ [resource]
				cleanupStep.children :+ [resource]
			Next
			context.PushCleanup(cleanupStep)
			Local body:TGenericTemplateNode = TemplateBlock(usingStatement.body, model, parameters, diagnostics, parameterOwner, context)
			context.PopCleanup()
			If body Then result.children :+ [body]
			Return result
		End If
		Local flow:TBoundFlowStatement = TBoundFlowStatement(statement)
		If flow Then
			Local restoreSyntax:TRestoreDataStatementSyntax = TRestoreDataStatementSyntax(statement.syntax)
			If restoreSyntax Then
				Local restoreBinding:TDataRestoreBinding = model.ResolvedDataRestore(restoreSyntax)
				If Not restoreBinding Or Not restoreBinding.definition Or Not restoreBinding.definition.syntax Then
					diagnostics :+ ["BMXC3075 generic RestoreData has no resolved data definition"]
					Return Null
				End If
				Local restoreNode:TGenericTemplateNode = New TGenericTemplateNode
				restoreNode.kind = TEMPLATE_NODE_DATA
				restoreNode.identity = "restore"
				restoreNode.valueText = DataDefinitionIdentity(restoreBinding.definition.syntax, model)
				restoreNode.source = SourceLocation(statement.syntax, model)
				Return restoreNode
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_LOOP_CONTROL
			result.source = SourceLocation(statement.syntax, model)
			Local target:TCompilerGenericTemplateLoopContext
			Local exited:TExitStatementSyntax = TExitStatementSyntax(statement.syntax)
			If exited Then
				result.valueText = "exit"
				target = context.ResolveLoop(exited.label)
			Else
				Local continued:TContinueStatementSyntax = TContinueStatementSyntax(statement.syntax)
				If continued Then
					result.valueText = "continue"
					target = context.ResolveLoop(continued.label)
				End If
			End If
			If Not result.valueText.length Then
				diagnostics :+ ["BMXC3053 generic flow statement is not supported by canonical template bodies"]
				Return Null
			End If
			If Not target Then
				diagnostics :+ ["BMXC3053 generic " + result.valueText + " has no resolved canonical loop target"]
				Return Null
			End If
			result.identity = target.identity
			Local cleanupDepth:Int = target.cleanupDepth
			If result.valueText = "continue" Then cleanupDepth = target.continueCleanupDepth
			Local cleanupEdges:TGenericTemplateNode = context.CleanupEdges(cleanupDepth)
			If cleanupEdges Then result.children = [cleanupEdges]
			Return result
		End If
		Local assignment:TBoundAssignmentStatement = TBoundAssignmentStatement(statement)
		If assignment Then
			Local assignmentSyntax:TAssignmentStatementSyntax = TAssignmentStatementSyntax(statement.syntax)
			Local indexedTargetSyntax:TIndexExpressionSyntax
			If assignmentSyntax Then indexedTargetSyntax = TIndexExpressionSyntax(assignmentSyntax.left)
			Local setter:TResolvedCall
			If assignment.indexAccess Then setter = assignment.indexAccess.resolvedCall
			If Not setter Then setter = assignment.resolvedCall
			If assignment.operatorText = "=" And indexedTargetSyntax And assignment.indexAccess And assignment.indexAccess.accessKind = INDEX_ACCESS_OPERATOR And setter And setter.routine Then
				Local call:TGenericTemplateNode = New TGenericTemplateNode
				call.kind = TEMPLATE_NODE_CALL
				call.valueText = setter.routine.name
				call.referencedSymbol = SymbolReference(setter.routine, model)
				' Index setters are retained only for their side effect. Unlike a
				' value-producing index expression, their type comes from the
				' selected routine declaration rather than the unbound left side.
				call.semanticType = TemplateType(setter.routine.declaredType, model, parameters, diagnostics, parameterOwner)
				call.source = SourceLocation(statement.syntax, model)
				call.children = New TGenericTemplateNode[indexedTargetSyntax.indexes.length + 2]
				call.children[0] = TemplateExpression(model.BoundExpression(indexedTargetSyntax.expression), model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				For Local index:Int = 0 Until indexedTargetSyntax.indexes.length
					call.children[index + 1] = TemplateExpression(model.BoundExpression(indexedTargetSyntax.indexes[index]), model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				Next
				call.children[call.children.length - 1] = TemplateExpression(assignment.value, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT
				result.source = call.source
				result.children = [call]
				Return result
			End If
			If assignment.resolvedCall And assignment.resolvedCall.routine Then
				Local operatorCall:TBoundCallExpression = New TBoundCallExpression
				operatorCall.boundKind = BOUND_EXPRESSION_CALL
				operatorCall.syntax = assignment.target.syntax
				operatorCall.semanticType = assignment.resolvedCall.returnType
				operatorCall.isSynthetic = True
				operatorCall.resolvedCall = assignment.resolvedCall
				operatorCall.receiver = assignment.target
				operatorCall.arguments = [assignment.value]
				Local call:TGenericTemplateNode = TemplateExpression(operatorCall, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				If Not call Then Return Null
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT
				result.source = SourceLocation(statement.syntax, model)
				result.children = [call]
				Return result
			End If
			If assignment.operatorText <> "=" And assignment.operatorText <> ":+" And assignment.operatorText <> ":-" And assignment.operatorText <> ":*" And assignment.operatorText <> ":/" Then
				diagnostics :+ ["BMXC3049 generic sequential assignment operator '" + assignment.operatorText + "' is outside the first local-body slice"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_ASSIGNMENT
			result.valueText = assignment.operatorText
			result.source = SourceLocation(statement.syntax, model)
			result.semanticType = TemplateType(assignment.target.semanticType, model, parameters, diagnostics, parameterOwner)
			Local target:TGenericTemplateNode = TemplateExpression(assignment.target, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			Local value:TGenericTemplateNode = TemplateExpression(assignment.value, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If target And value Then result.children = [target, value]
			Return result
		End If
		Local expressionStatement:TBoundExpressionStatement = TBoundExpressionStatement(statement)
		If expressionStatement Then
			Local call:TBoundCallExpression = TBoundCallExpression(expressionStatement.expression)
			Local receiver:TBoundSelfExpression
			If call Then receiver = TBoundSelfExpression(call.receiver)
			If call And receiver And call.resolvedCall And call.resolvedCall.routine And call.resolvedCall.routine.name.ToLower() = "new" Then
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_CONSTRUCTOR_DELEGATION
				If receiver.isSuper Then result.valueText = "super" Else result.valueText = "self"
				result.source = SourceLocation(statement.syntax, model)
				result.referencedSymbol = SymbolReference(call.resolvedCall.routine, model)
				Local signature:TGenericTemplateNode = New TGenericTemplateNode
				signature.kind = TEMPLATE_NODE_BLOCK
				signature.valueText = "signature"
				signature.source = result.source
				For Local index:Int = 0 Until call.resolvedCall.parameterTypes.length
					Local parameter:TGenericTemplateNode = New TGenericTemplateNode
					parameter.kind = TEMPLATE_NODE_DECLARATION
					parameter.semanticType = TemplateType(call.resolvedCall.parameterTypes[index], model, parameters, diagnostics, parameterOwner)
					If index < call.resolvedCall.routine.parameters.length Then parameter.valueText = call.resolvedCall.routine.parameters[index].passingMode
					signature.children :+ [parameter]
				Next
				Local arguments:TGenericTemplateNode = New TGenericTemplateNode
				arguments.kind = TEMPLATE_NODE_BLOCK
				arguments.valueText = "arguments"
				arguments.source = result.source
				For Local argument:TBoundExpression = EachIn call.arguments
					Local templateArgument:TGenericTemplateNode = TemplateExpression(argument, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
					If templateArgument Then arguments.children :+ [templateArgument]
				Next
				result.children = [signature, arguments]
				Return result
			End If
			Local expression:TGenericTemplateNode = TemplateExpression(expressionStatement.expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If Not expression Then Return Null
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT
			result.source = SourceLocation(statement.syntax, model)
			result.semanticType = TemplateType(expressionStatement.expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.children = [expression]
			Return result
		End If
		Local returnStatement:TBoundReturnStatement = TBoundReturnStatement(statement)
		If returnStatement Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_RETURN
			result.source = SourceLocation(statement.syntax, model)
			If returnStatement.expression Then
				result.semanticType = TemplateType(returnStatement.expression.semanticType, model, parameters, diagnostics, parameterOwner)
				Local expression:TGenericTemplateNode = TemplateExpression(returnStatement.expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				If expression Then result.children = [expression]
			End If
			Local cleanupEdges:TGenericTemplateNode = context.CleanupEdges()
			If cleanupEdges Then result.children :+ [cleanupEdges]
			Return result
		End If
		Local yieldStatement:TBoundYieldStatement = TBoundYieldStatement(statement)
		If yieldStatement Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_YIELD
			result.source = SourceLocation(statement.syntax, model)
			result.semanticType = TemplateType(yieldStatement.expression.semanticType, model, parameters, diagnostics, parameterOwner)
			Local expression:TGenericTemplateNode = TemplateExpression(yieldStatement.expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If expression Then result.children = [expression]
			result.identity = String(context.activeYieldExceptionFrameDepth)
			Local cleanupEdges:TGenericTemplateNode = context.CleanupEdges()
			If cleanupEdges Then result.children :+ [cleanupEdges]
			Return result
		End If
		Local throwStatement:TBoundThrowStatement = TBoundThrowStatement(statement)
		If throwStatement Then
			If Not throwStatement.expression Then
				diagnostics :+ ["BMXC3066 generic Throw requires a bound expression"]
				Return Null
			End If
			Local expression:TGenericTemplateNode = TemplateExpression(throwStatement.expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If Not expression Then Return Null
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_THROW
			result.source = SourceLocation(statement.syntax, model)
			result.semanticType = TemplateType(throwStatement.expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.children = [expression]
			Return result
		End If
		Local assertStatement:TBoundAssertStatement = TBoundAssertStatement(statement)
		If assertStatement Then
			If Not assertStatement.condition Then
				diagnostics :+ ["BMXC3067 generic Assert requires a bound condition"]
				Return Null
			End If
			Local condition:TGenericTemplateNode = TemplateExpression(assertStatement.condition, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If Not condition Then Return Null
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_ASSERT
			result.source = SourceLocation(statement.syntax, model)
			result.semanticType = TemplateType(assertStatement.condition.semanticType, model, parameters, diagnostics, parameterOwner)
			result.children = [condition]
			If assertStatement.message Then
				Local message:TGenericTemplateNode = TemplateExpression(assertStatement.message, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
				If Not message Then Return Null
				result.children :+ [message]
			End If
			Return result
		End If
		Local releaseStatement:TBoundReleaseStatement = TBoundReleaseStatement(statement)
		If releaseStatement Then
			If Not releaseStatement.expression Then
				diagnostics :+ ["BMXC3077 generic Release requires a bound integer expression"]
				Return Null
			End If
			Local expression:TGenericTemplateNode = TemplateExpression(releaseStatement.expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
			If Not expression Then Return Null
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_RELEASE
			result.source = SourceLocation(statement.syntax, model)
			result.semanticType = TemplateType(releaseStatement.expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.children = [expression]
			Return result
		End If
		Local conditionalRegion:TBoundConditionalStatement = TBoundConditionalStatement(statement)
		If conditionalRegion Then
			diagnostics :+ ["BMXC3074 conditional directives remained after source configuration was applied"]
			Return Null
		End If
		Local dataStatement:TBoundDataStatement = TBoundDataStatement(statement)
		If dataStatement Then
			Local definitionSyntax:TDefDataStatementSyntax = TDefDataStatementSyntax(statement.syntax)
			If definitionSyntax Then
				Local definition:TDataDefinition = model.DataDefinition(definitionSyntax)
				Local definitionNode:TGenericTemplateNode = New TGenericTemplateNode
				definitionNode.kind = TEMPLATE_NODE_DATA
				definitionNode.identity = "define"
				definitionNode.valueText = DataDefinitionIdentity(definitionSyntax, model)
				definitionNode.source = SourceLocation(statement.syntax, model)
				For Local expression:TBoundExpression = EachIn dataStatement.expressions
					Local valueNode:TGenericTemplateNode = TemplateExpression(expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
					If valueNode Then definitionNode.children :+ [valueNode]
				Next
				If definition And definition.labelName.length Then definitionNode.referencedSymbol = DataLabelReference(definition.labelName)
				Return definitionNode
			End If
			Local readSyntax:TReadDataStatementSyntax = TReadDataStatementSyntax(statement.syntax)
			If readSyntax Then
				Local operation:TDataReadOperation = model.DataReadOperation(readSyntax)
				If Not operation Then
					diagnostics :+ ["BMXC3075 generic ReadData has no analyzed target operation"]
					Return Null
				End If
				Local readNode:TGenericTemplateNode = New TGenericTemplateNode
				readNode.kind = TEMPLATE_NODE_DATA
				readNode.identity = "read"
				readNode.source = SourceLocation(statement.syntax, model)
				For Local target:TDataReadTarget = EachIn operation.targets
					Local targetNode:TGenericTemplateNode = New TGenericTemplateNode
					targetNode.kind = TEMPLATE_NODE_BLOCK
					targetNode.valueText = String(target.conversionKind)
					targetNode.semanticType = TemplateType(target.targetType, model, parameters, diagnostics, parameterOwner)
					targetNode.source = SourceLocation(target.syntax, model)
					Local expressionNode:TGenericTemplateNode = TemplateExpression(target.expression, model, parameters, diagnostics, parameterOwner, context.localRoutineContext)
					If expressionNode Then targetNode.children = [expressionNode]
					readNode.children :+ [targetNode]
				Next
				Return readNode
			End If
		End If
		If statement.boundKind = BOUND_STATEMENT_ERROR Then
			diagnostics :+ ["BMXC3075 erroneous or unbound statement cannot be retained in a canonical generic template"]
			Return Null
		End If
		Local unsupportedLocation:String
		If statement.syntax And statement.syntax.span Then unsupportedLocation = " at source offset " + statement.syntax.span.start
		diagnostics :+ ["BMXC3036 bound statement kind " + statement.boundKind + unsupportedLocation + " is outside the first generic template body slice"]
		Return Null
	End Function

	Function TemplateExpression:TGenericTemplateNode(expression:TBoundExpression, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int = TEMPLATE_PARAMETER_OWNER_TYPE, localRoutineContext:TCompilerGenericLocalRoutineContext = Null)
		If Not localRoutineContext Then localRoutineContext = New TCompilerGenericLocalRoutineContext
		Local passthrough:TBoundPassthroughExpression = TBoundPassthroughExpression(expression)
		If passthrough Then Return TemplateExpression(passthrough.operand, model, parameters, diagnostics, parameterOwner, localRoutineContext)
		Local unary:TBoundUnaryExpression = TBoundUnaryExpression(expression)
		If unary Then
			If unary.resolvedCall And unary.resolvedCall.routine Then
				Local operatorCall:TBoundCallExpression = New TBoundCallExpression
				operatorCall.boundKind = BOUND_EXPRESSION_CALL
				operatorCall.syntax = expression.syntax
				operatorCall.semanticType = unary.resolvedCall.returnType
				operatorCall.isSynthetic = True
				operatorCall.resolvedCall = unary.resolvedCall
				operatorCall.receiver = unary.operand
				Return TemplateExpression(operatorCall, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_OPERATOR
			result.valueText = unary.operatorText
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Local operand:TGenericTemplateNode = TemplateExpression(unary.operand, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			If operand Then result.children = [operand]
			Return result
		End If
		Local binary:TBoundBinaryExpression = TBoundBinaryExpression(expression)
		If binary Then
			If binary.resolvedCall And binary.resolvedCall.routine Then
				Local operatorCall:TBoundCallExpression = New TBoundCallExpression
				operatorCall.boundKind = BOUND_EXPRESSION_CALL
				operatorCall.syntax = expression.syntax
				operatorCall.semanticType = binary.resolvedCall.returnType
				operatorCall.isSynthetic = True
				operatorCall.resolvedCall = binary.resolvedCall
				operatorCall.receiver = binary.left
				operatorCall.arguments = [binary.right]
				Return TemplateExpression(operatorCall, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_OPERATOR
			result.valueText = binary.operatorText
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Local left:TGenericTemplateNode = TemplateExpression(binary.left, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			Local right:TGenericTemplateNode = TemplateExpression(binary.right, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			If left And right Then result.children = [left, right]
			Return result
		End If
		Local arrayLiteral:TBoundArrayLiteralExpression = TBoundArrayLiteralExpression(expression)
		If arrayLiteral Then
			Local arrayType:TArraySemanticType = TArraySemanticType(expression.semanticType)
			If Not arrayType Or arrayType.rank <> 1 Then
				diagnostics :+ ["BMXC3070 generic managed Array literals require a one-dimensional contextual Array type"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_ARRAY_LITERAL
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			result.identity = "literal" + result.source.start
			For Local element:TBoundExpression = EachIn arrayLiteral.elements
				Local elementNode:TGenericTemplateNode = TemplateExpression(element, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				If elementNode Then result.children :+ [elementNode]
			Next
			Return result
		End If
		Local functionLiteral:TBoundFunctionLiteralExpression = TBoundFunctionLiteralExpression(expression)
		If functionLiteral Then
			Local closureType:TClosureSemanticType = TClosureSemanticType(expression.semanticType)
			Local callableType:TCallableSemanticType = TCallableSemanticType(expression.semanticType)
			If (Not closureType Or Not closureType.signature) And Not callableType Then
				diagnostics :+ ["BMXC1240 Function literal has no canonical callable target in a source-free generic body"]
				Return Null
			End If
			If Not closureType And callableType And (functionLiteral.captures.length Or functionLiteral.capturesSelf) Then
				diagnostics :+ ["BMXC1240 thin Function literal cannot capture lexical state in a source-free generic body"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_FUNCTION_LITERAL
			If closureType Then result.identity = "closure-literal:" + SourceLocation(expression.syntax, model).start Else result.identity = "function-literal:" + SourceLocation(expression.syntax, model).start
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Local signature:TGenericTemplateNode = New TGenericTemplateNode
			signature.kind = TEMPLATE_NODE_BLOCK
			If closureType Then signature.valueText = "closure-literal-signature" Else signature.valueText = "function-literal-signature"
			signature.source = result.source
			Local literalParameterTypes:TSemanticType[]
			Local literalParameterModes:Int[]
			If closureType Then
				literalParameterTypes = closureType.signature.parameterTypes
				literalParameterModes = closureType.signature.parameterModes
			Else
				literalParameterTypes = callableType.parameterTypes
				literalParameterModes = callableType.parameterModes
			End If
			For Local index:Int = 0 Until literalParameterTypes.length
				Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
				parameterNode.kind = TEMPLATE_NODE_DECLARATION
				parameterNode.valueText = "arg" + index
				If closureType And index < closureType.parameterNames.length And closureType.parameterNames[index].length Then parameterNode.valueText = closureType.parameterNames[index]
				If functionLiteral.routine And index < functionLiteral.routine.parameters.length And functionLiteral.routine.parameters[index] And functionLiteral.routine.parameters[index].symbol Then parameterNode.valueText = functionLiteral.routine.parameters[index].symbol.name
				parameterNode.identity = PARAMETER_PASS_VALUE
				If index < literalParameterModes.length Then parameterNode.identity = literalParameterModes[index]
				parameterNode.semanticType = TemplateType(literalParameterTypes[index], model, parameters, diagnostics, parameterOwner)
				parameterNode.source = result.source
				signature.children :+ [parameterNode]
			Next
			Local bodyContext:TCompilerGenericTemplateBodyContext = New TCompilerGenericTemplateBodyContext
			Local literalBody:TGenericTemplateNode = TemplateBlock(functionLiteral.body, model, parameters, diagnostics, parameterOwner, bodyContext)
			If functionLiteral.captures.length Or functionLiteral.capturesSelf Then
				Local captureBlock:TGenericTemplateNode = New TGenericTemplateNode
				captureBlock.kind = TEMPLATE_NODE_BLOCK
				captureBlock.valueText = "closure-literal-captures"
				captureBlock.source = result.source
				If functionLiteral.capturesSelf Then
					Local selfCapture:TGenericTemplateNode = New TGenericTemplateNode
					selfCapture.kind = TEMPLATE_NODE_DECLARATION
					selfCapture.valueText = "Self"
					selfCapture.identity = "closure-capture-self"
					selfCapture.semanticType = TemplateType(functionLiteral.capturedSelfType, model, parameters, diagnostics, parameterOwner)
					selfCapture.source = result.source
					captureBlock.children :+ [selfCapture]
				End If
				For Local captured:TSymbol = EachIn functionLiteral.captures
					Local captureNode:TGenericTemplateNode = New TGenericTemplateNode
					captureNode.kind = TEMPLATE_NODE_DECLARATION
					captureNode.valueText = captured.name
					If captured.kind = SYMBOL_PARAMETER Then captureNode.identity = "closure-capture-parameter" Else captureNode.identity = "closure-capture-local"
					captureNode.semanticType = TemplateType(captured.declaredType, model, parameters, diagnostics, parameterOwner)
					captureNode.source = SourceLocation(captured.declaration, model)
					captureBlock.children :+ [captureNode]
				Next
				result.children = [signature, captureBlock, literalBody]
			Else
				result.children = [signature, literalBody]
			End If
			Return result
		End If
		Local conversion:TBoundConversionExpression = TBoundConversionExpression(expression)
		If conversion Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_CONVERSION
			result.valueText = conversion.conversionKind
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Local operand:TGenericTemplateNode = TemplateExpression(conversion.operand, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			If operand Then result.children = [operand]
			Return result
		End If
		Local creation:TBoundNewExpression = TBoundNewExpression(expression)
		If creation Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_NEW
			' For New T[n], createdType is the element type while the bound
			' expression carries the constructed Array type.
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			If TArraySemanticType(expression.semanticType) Then
				Local createdArray:TArraySemanticType = TArraySemanticType(expression.semanticType)
				If creation.dimensions.length <> createdArray.rank Then
					diagnostics :+ ["BMXC3063 generic managed Array allocation requires one dimension per closed rank"]
					Return Null
				End If
				For Local dimensionExpression:TBoundExpression = EachIn creation.dimensions
					Local dimension:TGenericTemplateNode = TemplateExpression(dimensionExpression, model, parameters, diagnostics, parameterOwner, localRoutineContext)
					If dimension Then result.children :+ [dimension]
				Next
				Return result
			End If
			If creation.resolvedConstructor And creation.resolvedConstructor.routine Then
				result.referencedSymbol = SymbolReference(creation.resolvedConstructor.routine, model)
				If result.semanticType And result.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And result.semanticType.runtimeAbiName.length And creation.resolvedConstructor.routine.parameters.length Then
					Local objectNewAbiName:String = OrdinaryConstructorObjectNewAbiName(creation.resolvedConstructor.routine, model)
					If Not objectNewAbiName.length Then
						diagnostics :+ ["BMXC3062 parameterized ordinary Type construction in a generic template requires a stable value/Var-parameter allocation ABI"]
						Return Null
					End If
					result.referencedSymbol.overloadKey = objectNewAbiName
					result.identity = "ordinary-constructor-signature"
					Local signature:TGenericTemplateNode = New TGenericTemplateNode
					signature.kind = TEMPLATE_NODE_BLOCK
					signature.valueText = "ordinary-constructor-signature"
					signature.source = result.source
					For Local parameter:TSemanticParameter = EachIn creation.resolvedConstructor.routine.parameters
						Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
						parameterNode.kind = TEMPLATE_NODE_DECLARATION
						parameterNode.semanticType = TemplateType(parameter.semanticType, model, parameters, diagnostics, parameterOwner)
						parameterNode.valueText = parameter.passingMode
						parameterNode.source = result.source
						signature.children :+ [parameterNode]
					Next
					result.children = [signature]
				End If
			End If
			Local constructorParameterCount:Int = creation.arguments.length
			If result.identity = "ordinary-constructor-signature" Then constructorParameterCount = creation.resolvedConstructor.routine.parameters.length
			For Local argumentIndex:Int = 0 Until constructorParameterCount
				Local argument:TBoundExpression
				If argumentIndex < creation.arguments.length Then argument = creation.arguments[argumentIndex]
				Local templateArgument:TGenericTemplateNode
				If result.identity = "ordinary-constructor-signature" Then
					templateArgument = TemplateResolvedCallArgument(argument, argumentIndex, creation.resolvedConstructor, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				Else
					templateArgument = TemplateExpression(argument, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				End If
				If templateArgument Then result.children :+ [templateArgument]
			Next
			Return result
		End If
		Local call:TBoundCallExpression = TBoundCallExpression(expression)
		If call Then
			Local callableCallee:TCallableSemanticType
			Local closureCallee:TClosureSemanticType
			If call.callee Then callableCallee = TCallableSemanticType(call.callee.semanticType)
			If call.callee Then closureCallee = TClosureSemanticType(call.callee.semanticType)
			If (callableCallee Or closureCallee) And (Not call.resolvedCall Or Not call.resolvedCall.routine) Then
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_CALL
				If closureCallee Then
					result.identity = "closure-call"
					result.valueText = "closure"
				Else
					result.identity = "indirect-call"
					result.valueText = "callable"
				End If
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Local callee:TGenericTemplateNode = TemplateExpression(call.callee, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				If callee Then result.children = [callee]
				For Local argument:TBoundExpression = EachIn call.arguments
					Local argumentNode:TGenericTemplateNode = TemplateExpression(argument, model, parameters, diagnostics, parameterOwner, localRoutineContext)
					If argumentNode Then result.children :+ [argumentNode]
				Next
				Return result
			End If
			If call.resolvedCall And call.resolvedCall.isDeferred Then
				If call.receiver Then
					diagnostics :+ ["BMXC3048 deferred generic overload calls currently require an ordinary free routine"]
					Return Null
				End If
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_CALL
				result.valueText = "deferred-overload"
				result.semanticType = TemplateType(call.resolvedCall.returnType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Local candidates:TGenericTemplateNode = New TGenericTemplateNode
				candidates.kind = TEMPLATE_NODE_BLOCK
				candidates.valueText = "deferred-routine-candidates"
				candidates.source = result.source
				For Local routine:TSymbol = EachIn call.resolvedCall.candidates
					If Not routine Or routine.genericArity > 0 Or OrdinaryRoutineHasUnsupportedCallingConvention(routine) Then
						diagnostics :+ ["BMXC3048 deferred generic overload candidate requires an ordinary value-call ABI"]
						Continue
					End If
					Local stableAbiName:String = OrdinaryRoutineAbiName(routine, model)
					If Not stableAbiName.length Then
						diagnostics :+ ["BMXC3048 deferred generic overload candidate '" + routine.QualifiedName() + "' has no stable linkage identity"]
						Continue
					End If
					Local candidate:TGenericTemplateNode = New TGenericTemplateNode
					candidate.kind = TEMPLATE_NODE_DECLARATION
					candidate.valueText = "deferred-routine-candidate"
					candidate.referencedSymbol = SymbolReference(routine, model)
					candidate.referencedSymbol.overloadKey = stableAbiName
					candidate.semanticType = TemplateType(routine.declaredType, model, parameters, diagnostics, parameterOwner)
					candidate.source = result.source
					Local routineDeclaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
					Local routineOwner:TSymbol
					If routine.containingScope Then routineOwner = routine.containingScope.owner
					If routineDeclaration And routineDeclaration.isMethod And routineOwner And routineOwner.kind = SYMBOL_STRUCT Then
						Local receiverNode:TGenericTemplateNode = New TGenericTemplateNode
						receiverNode.kind = TEMPLATE_NODE_DECLARATION
						receiverNode.valueText = "ordinary-struct-receiver"
						receiverNode.semanticType = TemplateType(routineOwner.declaredType, model, parameters, diagnostics, parameterOwner)
						receiverNode.source = result.source
						candidate.children :+ [receiverNode]
					End If
					For Local parameter:TSemanticParameter = EachIn routine.parameters
						If parameter.optional Or parameter.passingMode <> PARAMETER_PASS_VALUE Then
							diagnostics :+ ["BMXC3048 deferred generic overload candidate '" + routine.QualifiedName() + "' requires non-optional value parameters"]
							Continue
						End If
						Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
						parameterNode.kind = TEMPLATE_NODE_DECLARATION
						parameterNode.valueText = parameter.passingMode
						parameterNode.semanticType = TemplateType(parameter.semanticType, model, parameters, diagnostics, parameterOwner)
						parameterNode.source = result.source
						candidate.children :+ [parameterNode]
					Next
					candidates.children :+ [candidate]
				Next
				result.children = [candidates]
				For Local argument:TBoundExpression = EachIn call.arguments
					Local templateArgument:TGenericTemplateNode = TemplateExpression(argument, model, parameters, diagnostics, parameterOwner, localRoutineContext)
					If templateArgument Then result.children :+ [templateArgument]
				Next
				Return result
			End If
			If call.resolvedCall And call.resolvedCall.routine And call.resolvedCall.routine.genericArity > 0 Then
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_CALL
				result.valueText = call.resolvedCall.routine.name
				result.referencedSymbol = SymbolReference(call.resolvedCall.routine, model)
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Local typeArguments:TGenericTemplateNode = New TGenericTemplateNode
				typeArguments.kind = TEMPLATE_NODE_BLOCK
				typeArguments.valueText = "routine-type-arguments"
				typeArguments.source = result.source
				For Local typeArgument:TSemanticType = EachIn call.resolvedCall.typeArguments
					Local argumentNode:TGenericTemplateNode = New TGenericTemplateNode
					argumentNode.kind = TEMPLATE_NODE_DECLARATION
					argumentNode.semanticType = TemplateType(typeArgument, model, parameters, diagnostics, parameterOwner)
					typeArguments.children :+ [argumentNode]
				Next
				result.children = [typeArguments]
				If call.receiver Then
					Local receiver:TGenericTemplateNode = TemplateExpression(call.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
					Local methodOwner:TSymbol
					If call.resolvedCall.routine.containingScope Then methodOwner = call.resolvedCall.routine.containingScope.owner
					Local declaringReceiver:TNamedSemanticType = TCompilerGenericInheritance.ConstructedOwnerType(call.receiver.semanticType, methodOwner, model)
					If receiver And declaringReceiver Then
						receiver.semanticType = TemplateType(declaringReceiver, model, parameters, diagnostics, parameterOwner)
						If receiver.semanticType And Not receiver.semanticType.runtimeAbiName.length And declaringReceiver.symbol And Not declaringReceiver.symbol.genericArity Then
							receiver.semanticType.runtimeAbiName = TCompilerDirectMethodAbi.OwnerAbiName(model, declaringReceiver.symbol)
							If declaringReceiver.symbol.kind = SYMBOL_STRUCT Then receiver.semanticType.runtimeKind = TEMPLATE_RUNTIME_STRUCT Else receiver.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS
						End If
					End If
					If receiver Then result.children :+ [receiver]
				End If
				For Local argumentIndex:Int = 0 Until call.resolvedCall.routine.parameters.length
					Local argument:TBoundExpression
					If argumentIndex < call.arguments.length Then argument = call.arguments[argumentIndex]
					Local templateArgument:TGenericTemplateNode = TemplateResolvedCallArgument(argument, argumentIndex, call.resolvedCall, model, parameters, diagnostics, parameterOwner, localRoutineContext)
					If templateArgument Then result.children :+ [templateArgument]
				Next
				Return result
			End If
			If Not call.receiver And call.staticReceiverType And call.resolvedCall And call.resolvedCall.routine Then
				Local staticOwner:TSymbol
				If call.resolvedCall.routine.containingScope Then staticOwner = call.resolvedCall.routine.containingScope.owner
				Local staticReceiver:TNamedSemanticType = TNamedSemanticType(call.staticReceiverType)
				If staticOwner And staticReceiver And staticReceiver.typeArguments.length Then
					Local result:TGenericTemplateNode = New TGenericTemplateNode
					result.kind = TEMPLATE_NODE_CALL
					result.valueText = call.resolvedCall.routine.name
					result.referencedSymbol = SymbolReference(call.resolvedCall.routine, model)
					result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
					result.source = SourceLocation(expression.syntax, model)
					Local receiver:TGenericTemplateNode = New TGenericTemplateNode
					receiver.kind = TEMPLATE_NODE_BLOCK
					receiver.valueText = "static-type-receiver"
					receiver.semanticType = TemplateType(call.staticReceiverType, model, parameters, diagnostics, parameterOwner)
					receiver.source = result.source
					result.children = [receiver]
					For Local argumentIndex:Int = 0 Until call.resolvedCall.routine.parameters.length
						Local argument:TBoundExpression
						If argumentIndex < call.arguments.length Then argument = call.arguments[argumentIndex]
						Local templateArgument:TGenericTemplateNode = TemplateResolvedCallArgument(argument, argumentIndex, call.resolvedCall, model, parameters, diagnostics, parameterOwner, localRoutineContext)
						If templateArgument Then result.children :+ [templateArgument]
					Next
					Return result
				End If
			End If
			If Not call.receiver And call.resolvedCall And call.resolvedCall.routine Then
				Local routine:TSymbol = call.resolvedCall.routine
				If LocalRoutine(routine) Then Return TemplateLocalRoutineCall(expression, call, routine, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				If OrdinaryRoutineHasUnsupportedCallingConvention(routine) Then
					diagnostics :+ ["BMXC3048 ordinary routine '" + routine.QualifiedName() + "' called from a generic template requires the ordinary C calling convention"]
					Return Null
				End If
				Local stableAbiName:String = OrdinaryRoutineAbiName(routine, model)
				If Not stableAbiName.length Then
					diagnostics :+ ["BMXC3048 ordinary routine '" + routine.QualifiedName() + "' called from a generic template requires published, imported, external, or NoMangle linkage"]
					Return Null
				End If
				For Local parameter:TSemanticParameter = EachIn routine.parameters
					If parameter.passingMode <> PARAMETER_PASS_VALUE And parameter.passingMode <> PARAMETER_PASS_VAR Then
						diagnostics :+ ["BMXC3048 ordinary routine '" + routine.QualifiedName() + "' called from a generic template has an unsupported parameter mode"]
						Return Null
					End If
				Next
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_CALL
				result.valueText = routine.name
				result.referencedSymbol = SymbolReference(routine, model)
				result.referencedSymbol.overloadKey = stableAbiName
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Local signature:TGenericTemplateNode = New TGenericTemplateNode
				signature.kind = TEMPLATE_NODE_BLOCK
				signature.valueText = "ordinary-routine-signature"
				If routine.externalName.length And routine.externalName <> stableAbiName Then signature.identity = routine.externalName
				If routine.originModule.ToLower() = "brl.blitz" And stableAbiName.StartsWith("bb") Then signature.valueText = "runtime-header-routine"
				signature.source = result.source
				For Local parameter:TSemanticParameter = EachIn routine.parameters
					Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
					parameterNode.kind = TEMPLATE_NODE_DECLARATION
					parameterNode.semanticType = TemplateType(parameter.semanticType, model, parameters, diagnostics, parameterOwner)
					parameterNode.valueText = parameter.passingMode
					parameterNode.source = result.source
					signature.children :+ [parameterNode]
				Next
				result.children = [signature]
				For Local argumentIndex:Int = 0 Until routine.parameters.length
					Local argument:TBoundExpression
					If argumentIndex < call.arguments.length Then argument = call.arguments[argumentIndex]
					Local templateArgument:TGenericTemplateNode = TemplateResolvedCallArgument(argument, argumentIndex, call.resolvedCall, model, parameters, diagnostics, parameterOwner, localRoutineContext)
					If templateArgument Then result.children :+ [templateArgument]
				Next
				Return result
			End If
			If Not call.receiver Or Not call.resolvedCall Or Not call.resolvedCall.routine Then
				Local unsupportedLocation:String
				If expression.syntax And expression.syntax.span Then unsupportedLocation = " at source offset " + expression.syntax.span.start
				diagnostics :+ ["BMXC3037 generic template calls currently require a bound instance receiver" + unsupportedLocation]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_CALL
			result.valueText = call.resolvedCall.routine.name
			result.referencedSymbol = SymbolReference(call.resolvedCall.routine, model)
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			result.children = New TGenericTemplateNode[call.resolvedCall.routine.parameters.length + 1]
			result.children[0] = TemplateExpression(call.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			For Local index:Int = 0 Until call.resolvedCall.routine.parameters.length
				Local argument:TBoundExpression
				If index < call.arguments.length Then argument = call.arguments[index]
				result.children[index + 1] = TemplateResolvedCallArgument(argument, index, call.resolvedCall, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			Next
			Local ordinaryReceiver:TNamedSemanticType = TNamedSemanticType(call.receiver.semanticType)
			If result.children[0] And result.children[0].semanticType And result.children[0].semanticType.runtimeKind = TEMPLATE_RUNTIME_STRUCT And result.children[0].semanticType.runtimeAbiName.length And ordinaryReceiver And ordinaryReceiver.symbol And Not ordinaryReceiver.symbol.genericArity Then
				Local stableStructAbiName:String = OrdinaryStructRoutineAbiName(call.resolvedCall.routine, model)
				If Not stableStructAbiName.length Then
					diagnostics :+ ["BMXC3048 ordinary Struct operation '" + result.valueText + "' has no stable direct-call linkage identity"]
					Return Null
				End If
				Local signature:TGenericTemplateNode = New TGenericTemplateNode
				signature.kind = TEMPLATE_NODE_BLOCK
				signature.valueText = "ordinary-routine-signature"
				signature.source = result.source
				Local receiverParameter:TGenericTemplateNode = New TGenericTemplateNode
				receiverParameter.kind = TEMPLATE_NODE_DECLARATION
				receiverParameter.valueText = "ordinary-struct-receiver"
				receiverParameter.semanticType = result.children[0].semanticType
				receiverParameter.source = result.source
				signature.children = [receiverParameter]
				For Local parameter:TSemanticParameter = EachIn call.resolvedCall.routine.parameters
					If parameter.passingMode <> PARAMETER_PASS_VALUE And parameter.passingMode <> PARAMETER_PASS_VAR Then
						diagnostics :+ ["BMXC3048 ordinary Struct operation '" + result.valueText + "' has an unsupported parameter mode"]
						Return Null
					End If
					Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
					parameterNode.kind = TEMPLATE_NODE_DECLARATION
					parameterNode.valueText = parameter.passingMode
					parameterNode.semanticType = TemplateType(parameter.semanticType, model, parameters, diagnostics, parameterOwner)
					parameterNode.source = result.source
					signature.children :+ [parameterNode]
				Next
				result.children = [signature] + result.children
				result.referencedSymbol.overloadKey = stableStructAbiName
				Return result
			End If
			If result.children[0] And result.children[0].semanticType And result.children[0].semanticType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE And result.children[0].semanticType.runtimeAbiName.length And ordinaryReceiver And ordinaryReceiver.symbol And ordinaryReceiver.symbol.kind = SYMBOL_INTERFACE And Not ordinaryReceiver.symbol.genericArity Then
				Local ordinaryValueAbi:Int = True
				For Local parameter:TSemanticParameter = EachIn call.resolvedCall.routine.parameters
					If parameter.passingMode <> PARAMETER_PASS_VALUE And parameter.passingMode <> PARAMETER_PASS_VAR Then ordinaryValueAbi = False; Exit
				Next
				If Not ordinaryValueAbi Then
					diagnostics :+ ["BMXC3057 ordinary Interface operation '" + result.valueText + "' called from a generic template has an unsupported parameter mode"]
				Else If Not result.children[0].semanticType.runtimeAbiName.length Then
					diagnostics :+ ["BMXC3057 ordinary Interface operation '" + result.valueText + "' has no published descriptor identity"]
				Else
					result.identity = "ordinary-interface-call"
					result.referencedSymbol.overloadKey = result.children[0].semanticType.runtimeAbiName
					result.runtimeDispatchIndex = OrdinaryInterfaceDispatchIndex(call.resolvedCall.routine, call.receiver.semanticType, model, diagnostics)
					If result.runtimeDispatchIndex >= 0 Then result.runtimeDispatchKind = TEMPLATE_DISPATCH_ORDINARY_CLASS
				End If
			End If
			If result.children[0] And result.children[0].semanticType And result.children[0].semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS And result.children[0].semanticType.runtimeAbiName.length And ordinaryReceiver And ordinaryReceiver.symbol And Not ordinaryReceiver.symbol.genericArity Then
				Local ordinaryValueAbi:Int = True
				For Local parameter:TSemanticParameter = EachIn call.resolvedCall.routine.parameters
					If parameter.passingMode <> PARAMETER_PASS_VALUE And parameter.passingMode <> PARAMETER_PASS_VAR Then ordinaryValueAbi = False; Exit
				Next
				If Not ordinaryValueAbi Then
					diagnostics :+ ["BMXC3059 ordinary Type operation '" + result.valueText + "' called from a generic template has an unsupported parameter mode"]
				Else
					result.runtimeDispatchIndex = OrdinaryClassDispatchIndex(call.resolvedCall.routine, call.receiver.semanticType, model, diagnostics)
					If result.runtimeDispatchIndex >= 0 Then result.runtimeDispatchKind = TEMPLATE_DISPATCH_ORDINARY_CLASS
				End If
			End If
			If result.children[0] And result.children[0].semanticType And result.children[0].semanticType.runtimeKind <> TEMPLATE_RUNTIME_INTERFACE And Not StableSliceReceiver(call.receiver) Then
				If result.identity.length Then result.identity :+ ";"
				result.identity :+ "materialized-receiver:" + result.source.start
			End If
			Return result
		End If
		Local selfExpression:TBoundSelfExpression = TBoundSelfExpression(expression)
		If selfExpression Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_SELF
			If selfExpression.isSuper Then result.valueText = "super" Else result.valueText = "self"
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			Local selfType:TNamedSemanticType = TNamedSemanticType(expression.semanticType)
			If result.semanticType And Not result.semanticType.runtimeAbiName.length And selfType And selfType.symbol And selfType.symbol.genericArity = 0 And selfType.typeArguments.length = 0 Then
				result.semanticType.runtimeAbiName = TCompilerDirectMethodAbi.OwnerAbiName(model, selfType.symbol)
				If selfType.symbol.kind = SYMBOL_INTERFACE Then
					result.semanticType.runtimeKind = TEMPLATE_RUNTIME_INTERFACE
				Else If selfType.symbol.kind = SYMBOL_STRUCT Then
					result.semanticType.runtimeKind = TEMPLATE_RUNTIME_STRUCT
				Else
					result.semanticType.runtimeKind = TEMPLATE_RUNTIME_CLASS
				End If
			End If
			result.source = SourceLocation(expression.syntax, model)
			Return result
		End If
		Local symbolExpression:TBoundSymbolExpression = TBoundSymbolExpression(expression)
		If symbolExpression Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			If symbolExpression.symbol And symbolExpression.symbol.kind = SYMBOL_CONST Then
				Local constant:TConstantValue = model.SymbolConstantValue(symbolExpression.symbol)
				If Not constant Or (constant.kind <> CONSTANT_VALUE_INTEGER And constant.kind <> CONSTANT_VALUE_FLOAT) Then
					diagnostics :+ ["BMXC3037 generic Const reference '" + symbolExpression.symbol.QualifiedName() + "' requires a scalar numeric compile-time value"]
					Return Null
				End If
				result.kind = TEMPLATE_NODE_LITERAL
				result.valueText = constant.DisplayValue()
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Return result
			End If
			If symbolExpression.symbol And symbolExpression.symbol.kind = SYMBOL_GLOBAL Then
				If GenericStaticOwner(symbolExpression.symbol) Then
					result.kind = TEMPLATE_NODE_NAME
					result.identity = "specialization-static"
					result.valueText = symbolExpression.symbol.name
					result.referencedSymbol = SymbolReference(symbolExpression.symbol, model)
					result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
					result.source = SourceLocation(expression.syntax, model)
					Return result
				End If
				Local globalAbiName:String = OrdinaryGlobalAbiName(symbolExpression.symbol, model)
				If Not globalAbiName.length Then
					diagnostics :+ ["BMXC3048 generic Global reference '" + symbolExpression.symbol.QualifiedName() + "' requires an imported, external, or published module ABI"]
					Return Null
				End If
				result.kind = TEMPLATE_NODE_NAME
				result.identity = "ordinary-global"
				result.valueText = symbolExpression.symbol.name
				result.referencedSymbol = SymbolReference(symbolExpression.symbol, model)
				result.referencedSymbol.overloadKey = globalAbiName
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Return result
			End If
			result.kind = TEMPLATE_NODE_NAME
			If symbolExpression.symbol And symbolExpression.symbol.kind = SYMBOL_FIELD Then result.kind = TEMPLATE_NODE_MEMBER
			If symbolExpression.symbol Then result.valueText = symbolExpression.symbol.name
			If symbolExpression.symbol And symbolExpression.symbol.kind = SYMBOL_FIELD Then result.referencedSymbol = SymbolReference(symbolExpression.symbol, model)
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Return result
		End If
		Local memberExpression:TBoundMemberExpression = TBoundMemberExpression(expression)
		If memberExpression Then
			If memberExpression.access And memberExpression.access.member And memberExpression.access.member.kind = SYMBOL_ENUM_MEMBER Then
				Local constant:TConstantValue = model.SymbolConstantValue(memberExpression.access.member)
				If Not constant Or constant.kind <> CONSTANT_VALUE_INTEGER Then
					diagnostics :+ ["BMXC3037 generic Enum member reference '" + memberExpression.access.member.QualifiedName() + "' requires an integral compile-time value"]
					Return Null
				End If
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_LITERAL
				result.valueText = constant.DisplayValue()
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Return result
			End If
			If memberExpression.access And memberExpression.access.member And memberExpression.access.member.kind = SYMBOL_GLOBAL Then
				If GenericStaticOwner(memberExpression.access.member) Then
					Local result:TGenericTemplateNode = New TGenericTemplateNode
					result.kind = TEMPLATE_NODE_NAME
					result.identity = "specialization-static"
					result.valueText = memberExpression.access.member.name
					result.referencedSymbol = SymbolReference(memberExpression.access.member, model)
					result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
					result.source = SourceLocation(expression.syntax, model)
					Return result
				End If
				Local globalAbiName:String = OrdinaryGlobalAbiName(memberExpression.access.member, model)
				If Not globalAbiName.length Then
					diagnostics :+ ["BMXC3048 generic Global reference '" + memberExpression.access.member.QualifiedName() + "' requires an imported, external, or published module ABI"]
					Return Null
				End If
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_NAME
				result.identity = "ordinary-global"
				result.valueText = memberExpression.access.member.name
				result.referencedSymbol = SymbolReference(memberExpression.access.member, model)
				result.referencedSymbol.overloadKey = globalAbiName
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Return result
			End If
			If TArraySemanticType(memberExpression.receiver.semanticType) And memberExpression.access And memberExpression.access.member And memberExpression.access.member.name.ToLower() = "length" Then
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_ARRAY_LENGTH
				result.valueText = "length"
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Local receiver:TGenericTemplateNode = TemplateExpression(memberExpression.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				If receiver Then result.children = [receiver]
				Return result
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_MEMBER
			If memberExpression.access And memberExpression.access.member Then
				result.valueText = memberExpression.access.member.name
				If memberExpression.access.member.kind = SYMBOL_FIELD Then result.referencedSymbol = SymbolReference(memberExpression.access.member, model)
			End If
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Local receiver:TGenericTemplateNode = TemplateExpression(memberExpression.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			If receiver Then result.children = [receiver]
			Return result
		End If
		Local indexExpression:TBoundIndexExpression = TBoundIndexExpression(expression)
		If indexExpression Then
			If indexExpression.access And indexExpression.access.accessKind = INDEX_ACCESS_OPERATOR And indexExpression.access.resolvedCall And indexExpression.access.resolvedCall.routine Then
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_CALL
				result.valueText = indexExpression.access.resolvedCall.routine.name
				result.referencedSymbol = SymbolReference(indexExpression.access.resolvedCall.routine, model)
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				result.children = New TGenericTemplateNode[indexExpression.indexes.length + 1]
				result.children[0] = TemplateExpression(indexExpression.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				For Local index:Int = 0 Until indexExpression.indexes.length
					result.children[index + 1] = TemplateExpression(indexExpression.indexes[index], model, parameters, diagnostics, parameterOwner, localRoutineContext)
				Next
				Return result
			End If
			If indexExpression.access And indexExpression.access.accessKind = INDEX_ACCESS_RANGE_ARRAY Then
				Local indexedRangeArray:TArraySemanticType = TArraySemanticType(indexExpression.receiver.semanticType)
				If Not indexedRangeArray Or indexedRangeArray.rank <> 1 Or indexExpression.indexes.length <> 1 Then
					diagnostics :+ ["BMXC3064 generic Range slicing requires one closed one-dimensional managed Array receiver and one Range value"]
					Return Null
				End If
				' Format-29 represents this operation with the existing Array-slice node.
				' Its Range value therefore appears in both bound calls. Permit only
				' stable expressions so specialization never duplicates side effects.
				If Not StableSliceReceiver(indexExpression.receiver) Or Not StableSliceReceiver(indexExpression.indexes[0]) Then
					diagnostics :+ ["BMXC3064 generic Range slicing currently requires stable Array and Range value expressions"]
					Return Null
				End If
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_ARRAY_SLICE
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Local receiver:TGenericTemplateNode = TemplateExpression(indexExpression.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				Local rangeValue:TGenericTemplateNode = TemplateExpression(indexExpression.indexes[0], model, parameters, diagnostics, parameterOwner, localRoutineContext)
				Local length:TGenericTemplateNode = New TGenericTemplateNode
				length.kind = TEMPLATE_NODE_ARRAY_LENGTH
				length.valueText = "length"
				length.semanticType = TemplateType(model.BuiltinType("Int"), model, parameters, diagnostics, parameterOwner)
				length.source = result.source
				If receiver Then length.children = [receiver]
				Local lowerBound:TGenericTemplateNode = TemplateRangeBoundCall(indexExpression.access.rangeStartRoutine, rangeValue, [length], model, parameters, diagnostics, parameterOwner, result.source)
				Local upperBound:TGenericTemplateNode = TemplateRangeBoundCall(indexExpression.access.rangeEndRoutine, rangeValue, [length], model, parameters, diagnostics, parameterOwner, result.source)
				If receiver And lowerBound And upperBound Then result.children = [receiver, lowerBound, upperBound]
				Return result
			End If
			If Not indexExpression.access Or (indexExpression.access.accessKind <> INDEX_ACCESS_ARRAY And indexExpression.access.accessKind <> INDEX_ACCESS_STATIC_ARRAY) Then
				diagnostics :+ ["BMXC3063 generic Array element access requires a bound managed or StaticArray index"]
				Return Null
			End If
			Local indexedArray:TArraySemanticType = TArraySemanticType(indexExpression.receiver.semanticType)
			If indexedArray And indexExpression.indexes.length <> indexedArray.rank Then
				diagnostics :+ ["BMXC3063 generic managed Array element access index count does not match its rank"]
				Return Null
			End If
			If indexExpression.access.accessKind = INDEX_ACCESS_STATIC_ARRAY And indexExpression.indexes.length <> 1 Then
				diagnostics :+ ["BMXC3063 generic StaticArray element access requires one index"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_ARRAY_ELEMENT
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Local receiver:TGenericTemplateNode = TemplateExpression(indexExpression.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			If receiver Then result.children = [receiver]
			For Local boundIndex:TBoundExpression = EachIn indexExpression.indexes
				Local index:TGenericTemplateNode = TemplateExpression(boundIndex, model, parameters, diagnostics, parameterOwner, localRoutineContext)
				If index Then result.children :+ [index]
			Next
			If indexedArray And indexedArray.rank > 1 And Not StableSliceReceiver(indexExpression.receiver) Then result.identity = "materialized-receiver:" + result.source.start
			Return result
		End If
		Local sliceExpression:TBoundSliceExpression = TBoundSliceExpression(expression)
		If sliceExpression Then
			If Not TArraySemanticType(sliceExpression.receiver.semanticType) Then
				diagnostics :+ ["BMXC3064 generic slicing currently requires a managed Array receiver"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_ARRAY_SLICE
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			If Not StableSliceReceiver(sliceExpression.receiver) Then result.identity = "materialized-receiver:" + result.source.start
			Local receiver:TGenericTemplateNode = TemplateExpression(sliceExpression.receiver, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			Local lowerBound:TGenericTemplateNode
			If sliceExpression.lowerBound Then
				lowerBound = TemplateExpression(sliceExpression.lowerBound, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			Else
				lowerBound = New TGenericTemplateNode
				lowerBound.kind = TEMPLATE_NODE_LITERAL
				lowerBound.valueText = "0"
				lowerBound.semanticType = TemplateType(model.BuiltinType("Int"), model, parameters, diagnostics, parameterOwner)
				lowerBound.source = result.source
			End If
			If sliceExpression.lowerFromEnd And lowerBound Then lowerBound = TemplateFromEndBound(receiver, lowerBound, model, parameters, diagnostics, parameterOwner, result.source)
			Local upperBound:TGenericTemplateNode
			If sliceExpression.upperBound Then
				upperBound = TemplateExpression(sliceExpression.upperBound, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			Else
				upperBound = New TGenericTemplateNode
				upperBound.kind = TEMPLATE_NODE_ARRAY_LENGTH
				upperBound.valueText = "length"
				upperBound.semanticType = TemplateType(model.BuiltinType("Int"), model, parameters, diagnostics, parameterOwner)
				upperBound.source = result.source
				If receiver Then upperBound.children = [receiver]
			End If
			If sliceExpression.upperFromEnd And upperBound Then upperBound = TemplateFromEndBound(receiver, upperBound, model, parameters, diagnostics, parameterOwner, result.source)
			If receiver And lowerBound And upperBound Then result.children = [receiver, lowerBound, upperBound]
			Return result
		End If
		Local literal:TBoundLiteralExpression = TBoundLiteralExpression(expression)
		If literal Then
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_LITERAL
			Local constant:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(model, TExpressionSyntax(expression.syntax))
			If constant And constant.kind = CONSTANT_VALUE_STRING Then
				result.identity = "string-code-units"
				result.valueText = EncodeStringCodeUnits(constant.stringValue)
			Else If literal.token Then
				result.valueText = literal.token.text
			End If
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Return result
		End If
		Local routineReference:TBoundRoutineReferenceExpression = TBoundRoutineReferenceExpression(expression)
		If routineReference Then
			If routineReference.receiver Then
				Return TemplateBoundMethodReference(routineReference, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			End If
			If Not routineReference.routine Or OrdinaryRoutineHasUnsupportedCallingConvention(routineReference.routine) Then
				diagnostics :+ ["BMXC3075 generic callable reference requires an ordinary-C-compatible free routine"]
				Return Null
			End If
			If routineReference.routine.genericArity > 0 Then
				If routineReference.typeArguments.length <> routineReference.routine.genericArity Then
					diagnostics :+ ["BMXC3075 generic callable reference requires a complete explicit type-argument binding"]
					Return Null
				End If
				Local result:TGenericTemplateNode = New TGenericTemplateNode
				result.kind = TEMPLATE_NODE_NAME
				result.identity = "generic-routine-callable-reference"
				result.valueText = routineReference.routine.name
				result.referencedSymbol = SymbolReference(routineReference.routine, model)
				result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
				result.source = SourceLocation(expression.syntax, model)
				Local typeArguments:TGenericTemplateNode = New TGenericTemplateNode
				typeArguments.kind = TEMPLATE_NODE_BLOCK
				typeArguments.valueText = "routine-type-arguments"
				typeArguments.source = result.source
				For Local typeArgument:TSemanticType = EachIn routineReference.typeArguments
					Local argumentNode:TGenericTemplateNode = New TGenericTemplateNode
					argumentNode.kind = TEMPLATE_NODE_DECLARATION
					argumentNode.semanticType = TemplateType(typeArgument, model, parameters, diagnostics, parameterOwner)
					typeArguments.children :+ [argumentNode]
				Next
				result.children = [typeArguments]
				If routineReference.staticReceiverType Then
					Local receiver:TGenericTemplateNode = New TGenericTemplateNode
					receiver.kind = TEMPLATE_NODE_DECLARATION
					receiver.valueText = "static-routine-owner"
					receiver.semanticType = TemplateType(routineReference.staticReceiverType, model, parameters, diagnostics, parameterOwner)
					receiver.source = result.source
					result.children :+ [receiver]
				End If
				Return result
			End If
			Local stableAbiName:String = OrdinaryRoutineAbiName(routineReference.routine, model)
			If Not stableAbiName.length Then
				diagnostics :+ ["BMXC3075 generic callable reference '" + routineReference.routine.QualifiedName() + "' requires published, imported, external, or NoMangle linkage"]
				Return Null
			End If
			Local result:TGenericTemplateNode = New TGenericTemplateNode
			result.kind = TEMPLATE_NODE_NAME
			result.identity = "ordinary-callable-reference"
			result.valueText = routineReference.routine.name
			result.referencedSymbol = SymbolReference(routineReference.routine, model)
			result.referencedSymbol.overloadKey = stableAbiName
			result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
			result.source = SourceLocation(expression.syntax, model)
			Return result
		End If
		If expression.boundKind = BOUND_EXPRESSION_OMITTED_ARGUMENT Then
			diagnostics :+ ["BMXC3075 omitted generic arguments must be resolved against their optional parameter before artifact publication"]
			Return Null
		End If
		If expression.boundKind = BOUND_EXPRESSION_ERROR Then
			diagnostics :+ ["BMXC3075 erroneous or unbound expression cannot be retained in a canonical generic template"]
			Return Null
		End If
		diagnostics :+ ["BMXC3037 bound expression kind " + expression.boundKind + " is outside the first generic template body slice"]
		Return Null
	End Function

	' A bound Method reference is a managed Function literal whose sole lexical
	' capture is the receiver. Representing it in the canonical generic template
	' this way reuses the established specialization closure environment and the
	' normal instance-call dispatcher. In particular, generic owner substitution,
	' virtual/interface dispatch, Var parameters and managed returns do not acquire
	' a second ABI merely because the Method was first-class.
	Function TemplateBoundMethodReference:TGenericTemplateNode(reference:TBoundRoutineReferenceExpression, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, localRoutineContext:TCompilerGenericLocalRoutineContext)
		Local closureType:TClosureSemanticType = TClosureSemanticType(reference.semanticType)
		If Not reference.routine Or Not closureType Or Not closureType.signature Then
			diagnostics :+ ["BMXC3075 bound Method reference requires a complete managed Closure signature"]
			Return Null
		End If
		If reference.routine.genericArity Then
			diagnostics :+ ["BMXC3075 explicitly specialized generic Method references are not yet supported"]
			Return Null
		End If

		Local receiverSymbol:TBoundSymbolExpression = TBoundSymbolExpression(reference.receiver)
		Local receiverSelf:TBoundSelfExpression = TBoundSelfExpression(reference.receiver)
		If receiverSymbol And (Not receiverSymbol.symbol Or (receiverSymbol.symbol.kind <> SYMBOL_PARAMETER And receiverSymbol.symbol.kind <> SYMBOL_LOCAL And receiverSymbol.symbol.kind <> SYMBOL_CATCH_PARAMETER)) Then receiverSymbol = Null
		If Not receiverSymbol And Not receiverSelf Then
			diagnostics :+ ["BMXC3075 a bound Method receiver created inside a generic routine must currently be Self, a parameter, or a Local"]
			Return Null
		End If

		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_FUNCTION_LITERAL
		result.identity = "bound-method-reference:" + SourceLocation(reference.syntax, model).start
		result.semanticType = TemplateType(reference.semanticType, model, parameters, diagnostics, parameterOwner)
		result.source = SourceLocation(reference.syntax, model)

		Local signature:TGenericTemplateNode = New TGenericTemplateNode
		signature.kind = TEMPLATE_NODE_BLOCK
		signature.valueText = "closure-literal-signature"
		signature.source = result.source
		For Local index:Int = 0 Until closureType.signature.parameterTypes.length
			Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
			parameterNode.kind = TEMPLATE_NODE_DECLARATION
			parameterNode.valueText = "arg" + index
			If index < closureType.parameterNames.length And closureType.parameterNames[index].length Then parameterNode.valueText = closureType.parameterNames[index]
			parameterNode.identity = PARAMETER_PASS_VALUE
			If index < closureType.signature.parameterModes.length Then parameterNode.identity = closureType.signature.parameterModes[index]
			parameterNode.semanticType = TemplateType(closureType.signature.parameterTypes[index], model, parameters, diagnostics, parameterOwner)
			parameterNode.source = result.source
			signature.children :+ [parameterNode]
		Next

		Local captureBlock:TGenericTemplateNode = New TGenericTemplateNode
		captureBlock.kind = TEMPLATE_NODE_BLOCK
		captureBlock.valueText = "closure-literal-captures"
		captureBlock.source = result.source
		Local capture:TGenericTemplateNode = New TGenericTemplateNode
		capture.kind = TEMPLATE_NODE_DECLARATION
		capture.semanticType = TemplateType(reference.receiver.semanticType, model, parameters, diagnostics, parameterOwner)
		capture.source = result.source
		If receiverSelf Then
			capture.valueText = "Self"
			capture.identity = "closure-capture-self"
		Else
			capture.valueText = receiverSymbol.symbol.name
			If receiverSymbol.symbol.kind = SYMBOL_PARAMETER Or receiverSymbol.symbol.kind = SYMBOL_CATCH_PARAMETER Then capture.identity = "closure-capture-parameter" Else capture.identity = "closure-capture-local"
		End If
		captureBlock.children = [capture]

		Local resolved:TResolvedCall = New TResolvedCall
		resolved.routine = reference.routine
		resolved.returnType = closureType.signature.returnType
		resolved.parameterTypes = closureType.signature.parameterTypes
		resolved.argumentTypes = closureType.signature.parameterTypes
		Local call:TBoundCallExpression = New TBoundCallExpression
		call.boundKind = BOUND_EXPRESSION_CALL
		call.syntax = reference.syntax
		call.semanticType = closureType.signature.returnType
		call.isSynthetic = True
		call.resolvedCall = resolved
		call.receiver = reference.receiver
		For Local index:Int = 0 Until closureType.signature.parameterTypes.length
			Local argument:TBoundSymbolExpression = New TBoundSymbolExpression
			argument.boundKind = BOUND_EXPRESSION_SYMBOL
			argument.syntax = reference.syntax
			argument.semanticType = closureType.signature.parameterTypes[index]
			If index < reference.routine.parameters.length Then argument.symbol = reference.routine.parameters[index].symbol
			call.arguments :+ [argument]
		Next
		Local invocation:TGenericTemplateNode = TemplateExpression(call, model, parameters, diagnostics, parameterOwner, localRoutineContext)
		If Not invocation Then Return Null

		Local statement:TGenericTemplateNode = New TGenericTemplateNode
		statement.source = result.source
		If closureType.signature.returnType = model.BuiltinType("Void") Then
			statement.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT
		Else
			statement.kind = TEMPLATE_NODE_RETURN
			statement.semanticType = TemplateType(closureType.signature.returnType, model, parameters, diagnostics, parameterOwner)
		End If
		statement.children = [invocation]
		Local body:TGenericTemplateNode = New TGenericTemplateNode
		body.kind = TEMPLATE_NODE_BLOCK
		body.valueText = "routine-body"
		body.source = result.source
		body.children = [statement]
		result.children = [signature, captureBlock, body]
		Return result
	End Function

	Function TemplateFromEndBound:TGenericTemplateNode(receiver:TGenericTemplateNode, distance:TGenericTemplateNode, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, source:TTemplateSourceLocation)
		Local length:TGenericTemplateNode = New TGenericTemplateNode
		length.kind = TEMPLATE_NODE_ARRAY_LENGTH
		length.valueText = "length"
		length.semanticType = TemplateType(model.BuiltinType("Int"), model, parameters, diagnostics, parameterOwner)
		length.source = source
		If receiver Then length.children = [receiver]
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_OPERATOR
		result.valueText = "-"
		result.semanticType = TemplateType(model.BuiltinType("Int"), model, parameters, diagnostics, parameterOwner)
		result.source = source
		result.children = [length, distance]
		Return result
	End Function

	Function GenericStaticOwner:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_GLOBAL Then Return False
		Local scope:TScope = symbol.containingScope
		While scope
			Local owner:TSymbol = scope.owner
			If owner And (owner.kind = SYMBOL_TYPE Or owner.kind = SYMBOL_STRUCT) Then
				If owner.genericArity > 0 Then Return True
				' During source-template publication the member scope can be bound
				' before the nominal symbol's cached arity is populated.  The
				' declaration remains authoritative in that phase.
				Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(owner.declaration)
				If declaration And declaration.header And declaration.header.genericParameters.length Then Return True
			End If
			scope = scope.parent
		Wend
		Return False
	End Function

	Function TemplateRangeBoundCall:TGenericTemplateNode(routine:TSymbol, receiver:TGenericTemplateNode, arguments:TGenericTemplateNode[], model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, source:TTemplateSourceLocation)
		If Not routine Or Not receiver Then Return Null
		Local stableAbiName:String = OrdinaryStructRoutineAbiName(routine, model)
		If Not stableAbiName.length Then
			diagnostics :+ ["BMXC3064 standard Range bound resolver '" + routine.name + "' has no stable Struct ABI"]
			Return Null
		End If
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_CALL
		result.valueText = routine.name
		result.referencedSymbol = SymbolReference(routine, model)
		result.referencedSymbol.overloadKey = stableAbiName
		result.semanticType = TemplateType(routine.declaredType, model, parameters, diagnostics, parameterOwner)
		result.source = source
		Local signature:TGenericTemplateNode = New TGenericTemplateNode
		signature.kind = TEMPLATE_NODE_BLOCK
		signature.valueText = "ordinary-routine-signature"
		signature.source = source
		Local receiverParameter:TGenericTemplateNode = New TGenericTemplateNode
		receiverParameter.kind = TEMPLATE_NODE_DECLARATION
		receiverParameter.valueText = "ordinary-struct-receiver"
		receiverParameter.semanticType = receiver.semanticType
		receiverParameter.source = source
		signature.children = [receiverParameter]
		For Local parameter:TSemanticParameter = EachIn routine.parameters
			Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
			parameterNode.kind = TEMPLATE_NODE_DECLARATION
			parameterNode.valueText = parameter.passingMode
			parameterNode.semanticType = TemplateType(parameter.semanticType, model, parameters, diagnostics, parameterOwner)
			parameterNode.source = source
			signature.children :+ [parameterNode]
		Next
		result.children = [signature, receiver]
		For Local argument:TGenericTemplateNode = EachIn arguments
			result.children :+ [argument]
		Next
		Return result
	End Function

	Function EncodeStringCodeUnits:String(value:String)
		Local result:String
		For Local index:Int = 0 Until value.length
			If index Then result :+ ","
			result :+ String.FromInt(value[index])
		Next
		Return result
	End Function

	Function StableSliceReceiver:Int(expression:TBoundExpression)
		Local passthrough:TBoundPassthroughExpression = TBoundPassthroughExpression(expression)
		If passthrough Then Return StableSliceReceiver(passthrough.operand)
		If TBoundSymbolExpression(expression) Then Return True
		Local member:TBoundMemberExpression = TBoundMemberExpression(expression)
		If member Then Return TBoundSelfExpression(member.receiver) <> Null
		Return False
	End Function

	Function OrdinaryRoutineAbiName:String(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return ""
		' Imported Type functions are lowered as ordinary C routines and already
		' carry their authoritative linkage name in the compact interface. They
		' have no receiver and are therefore just as safe to retain as imported
		' module functions in a source-free template.
		If symbol.externalName.length Then Return TCompilerNativeDeclaration.LinkerName(symbol.externalName)
		If Not IsTopLevelRoutine(symbol) Then
			Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
			If Not declaration Or declaration.isMethod Then Return ""
		End If
		If symbol.isImported Then Return ""
		If symbol.metadata And symbol.metadata.Has("nomangle") Then Return TCompilerAbiNamer.RoutineName(model, symbol, "")
		If model And model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC Then Return TCompilerAbiNamer.RoutineName(model, symbol, "")
		Return OrdinaryPrivateRoutineDependencyAbiName(symbol, model)
	End Function

	Function OrdinaryPrivateRoutineDependencyAbiName:String(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Then Return ""
		Local ownerIdentity:String = symbol.originModule
		If Not ownerIdentity.length And model Then ownerIdentity = model.moduleName
		If Not ownerIdentity.length Then ownerIdentity = "source:" + symbol.originPath
		If Not ownerIdentity.length And model And model.syntaxTree And model.syntaxTree.source Then ownerIdentity = "source:" + model.syntaxTree.source.path
		If Not ownerIdentity.length Then Return ""
		Local semanticIdentity:String = ownerIdentity.ToLower() + "::" + symbol.QualifiedName().ToLower() + "/result="
		If symbol.declaredType Then semanticIdentity :+ symbol.declaredType.DisplayName().ToLower()
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			semanticIdentity :+ ";" + parameter.passingMode + ":"
			If parameter.semanticType Then semanticIdentity :+ parameter.semanticType.DisplayName().ToLower()
		Next
		Local digest:String = TCompilerStableDigest.Sha256(semanticIdentity)
		Local readableName:String
		For Local ownerName:String = EachIn TCompilerAbiNamer.ContainingTypeNames(symbol)
			If readableName.length Then readableName :+ "_"
			readableName :+ ownerName.ToLower()
		Next
		If readableName.length Then readableName :+ "_"
		readableName :+ TCompilerAbiNamer.RoutineSourceName(symbol.name).ToLower()
		Return "bmx_generic_dependency_" + TCompilerAbiNamer.Sanitize(readableName) + "_" + digest[..16]
	End Function

	Function OrdinaryStructRoutineAbiName:String(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return ""
		If symbol.externalName.length Then
			Local importedName:String = symbol.externalName
			' Compact interfaces publish generated Struct method identities without
			' their implementation-only leading underscore. Direct method calls use
			' the concrete implementation ABI, matching ordinary IR lowering.
			If symbol.isImported And Not importedName.StartsWith("_") Then importedName = "_" + importedName
			Return importedName
		End If
		If symbol.isImported Then Return ""
		Local owner:TSymbol
		If symbol.containingScope Then owner = symbol.containingScope.owner
		If Not owner Or owner.kind <> SYMBOL_STRUCT Then Return ""
		If model And model.moduleName.length And owner.visibility = VISIBILITY_PUBLIC Then
			Local result:String = TCompilerAbiNamer.RoutineName(model, symbol, "")
			If Not result.StartsWith("_") Then result = "_" + result
			Return result
		End If
		Return OrdinaryPrivateRoutineDependencyAbiName(symbol, model)
	End Function

	Function OrdinaryGlobalAbiName:String(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Or symbol.kind <> SYMBOL_GLOBAL Then Return ""
		If symbol.externalName.length Then Return symbol.externalName
		If symbol.isImported Then Return ""
		If model And model.moduleName.length And symbol.visibility = VISIBILITY_PUBLIC Then Return TCompilerAbiNamer.GlobalName(model, symbol, "")
		If Not model Then Return ""
		Local ownerIdentity:String = model.moduleName
		If Not ownerIdentity.length And model.syntaxTree And model.syntaxTree.source Then ownerIdentity = "source:" + model.syntaxTree.source.path
		If Not ownerIdentity.length Then Return ""
		Local sourceIdentity:String = ownerIdentity + "::" + symbol.QualifiedName()
		If symbol.declaration And symbol.declaration.span Then sourceIdentity :+ "@" + symbol.declaration.span.start
		Return "bmx_private_global_" + TCompilerAbiNamer.Sanitize(symbol.name) + "_" + TCompilerStableDigest.Sha256(sourceIdentity)[..20]
	End Function

	Function LocalRoutine:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or symbol.genericArity Or Not symbol.containingScope Or Not symbol.containingScope.owner Or symbol.containingScope.owner.kind <> SYMBOL_ROUTINE Then Return False
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		Return declaration And Not declaration.isMethod And declaration.signature
	End Function

	Function LocalRoutineIdentity:String(routine:TSymbol, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int)
		Local returnType:TTemplateTypeReference = TemplateType(routine.declaredType, model, parameters, diagnostics, parameterOwner)
		If Not returnType Then Return ""
		Local result:String = routine.name.ToLower() + "/result=" + returnType.CanonicalName() + ";parameters="
		For Local index:Int = 0 Until routine.parameters.length
			If index Then result :+ ","
			Local parameterType:TTemplateTypeReference = TemplateType(routine.parameters[index].semanticType, model, parameters, diagnostics, parameterOwner)
			If Not parameterType Then Return ""
			result :+ routine.parameters[index].passingMode + ":" + parameterType.CanonicalName()
		Next
		Return result
	End Function

	Function TemplateLocalRoutineCall:TGenericTemplateNode(expression:TBoundExpression, call:TBoundCallExpression, routine:TSymbol, model:TSemanticModel, parameters:TSymbol[], diagnostics:String[] Var, parameterOwner:Int, localRoutineContext:TCompilerGenericLocalRoutineContext)
		If Not localRoutineContext Then localRoutineContext = New TCompilerGenericLocalRoutineContext
		If call.arguments.length > routine.parameters.length Then
			diagnostics :+ ["BMXC3068 local routine '" + routine.name + "' has an inconsistent bound argument list"]
			Return Null
		End If
		For Local parameter:TSemanticParameter = EachIn routine.parameters
			If parameter.passingMode <> PARAMETER_PASS_VALUE And parameter.passingMode <> PARAMETER_PASS_VAR Then
				diagnostics :+ ["BMXC3068 local routine '" + routine.name + "' requires value/Var parameters"]
				Return Null
			End If
		Next
		Local identity:String = LocalRoutineIdentity(routine, model, parameters, diagnostics, parameterOwner)
		If Not identity.length Then
			diagnostics :+ ["BMXC3068 local routine '" + routine.name + "' has no closed canonical signature"]
			Return Null
		End If
		Local result:TGenericTemplateNode = New TGenericTemplateNode
		result.kind = TEMPLATE_NODE_CALL
		result.valueText = routine.name
		result.referencedSymbol = SymbolReference(routine, model)
		result.semanticType = TemplateType(expression.semanticType, model, parameters, diagnostics, parameterOwner)
		result.source = SourceLocation(expression.syntax, model)
		Local signature:TGenericTemplateNode = New TGenericTemplateNode
		signature.kind = TEMPLATE_NODE_BLOCK
		signature.valueText = "local-routine-reference"
		signature.identity = identity
		signature.referencedSymbol = result.referencedSymbol
		signature.semanticType = TemplateType(routine.declaredType, model, parameters, diagnostics, parameterOwner)
		signature.source = SourceLocation(routine.declaration, model)
		For Local parameter:TSemanticParameter = EachIn routine.parameters
			Local parameterNode:TGenericTemplateNode = New TGenericTemplateNode
			parameterNode.kind = TEMPLATE_NODE_DECLARATION
			If parameter.symbol Then parameterNode.valueText = parameter.symbol.name
			parameterNode.identity = parameter.passingMode
			parameterNode.semanticType = TemplateType(parameter.semanticType, model, parameters, diagnostics, parameterOwner)
			parameterNode.source = signature.source
			If parameter.optional Then
				Local defaultValue:TGenericTemplateNode = TemplateDefaultValue(parameter, parameterNode.semanticType, model, parameters, diagnostics, parameterOwner)
				If defaultValue Then parameterNode.children = [defaultValue]
			End If
			signature.children :+ [parameterNode]
		Next
		If Not localRoutineContext.visiting.Contains(routine) And Not localRoutineContext.completed.Contains(routine) Then
			Local localBody:TBoundBlockStatement = model.BoundRoutineBody(routine)
			If Not localBody Then
				diagnostics :+ ["BMXC3068 local routine '" + routine.name + "' has no bound semantic body"]
				Return Null
			End If
			localRoutineContext.visiting.Insert(routine, routine)
			Local bodyContext:TCompilerGenericTemplateBodyContext = New TCompilerGenericTemplateBodyContext
			bodyContext.localRoutineContext = localRoutineContext
			Local templateBody:TGenericTemplateNode = TemplateBlock(localBody, model, parameters, diagnostics, parameterOwner, bodyContext)
			localRoutineContext.visiting.Remove(routine)
			If Not templateBody Then Return Null
			Local localNames:TMap = New TMap
			For Local parameter:TSemanticParameter = EachIn routine.parameters
				If parameter.symbol Then localNames.Insert(parameter.symbol.name.ToLower(), parameter)
			Next
			TCompilerGenericCUnitEmitter.CollectDeclaredLocalNames(templateBody, localNames)
			Local captures:TGenericTemplateNode[]
			If TCompilerGenericCUnitEmitter.ContainsTemplateNodeKind(templateBody, TEMPLATE_NODE_SELF) Or TCompilerGenericCUnitEmitter.ContainsImplicitSelfMember(templateBody) Then
				Local selfCapture:TGenericTemplateNode = New TGenericTemplateNode
				selfCapture.kind = TEMPLATE_NODE_DECLARATION
				selfCapture.identity = PARAMETER_PASS_VALUE
				selfCapture.valueText = "capture:self"
				selfCapture.source = signature.source
				If routine.containingScope And routine.containingScope.owner And routine.containingScope.owner.containingScope Then
					Local containingRoutine:TSymbol = routine.containingScope.owner
					Local containingOwner:TSymbol = containingRoutine.containingScope.owner
					If containingOwner Then selfCapture.semanticType = TemplateType(containingOwner.declaredType, model, parameters, diagnostics, parameterOwner)
				End If
				captures :+ [selfCapture]
			End If
			TCompilerGenericCUnitEmitter.CollectLocalRoutineCaptureNodes(templateBody, localNames, captures, New TMap)
			TCompilerGenericCUnitEmitter.AppendLocalRoutineCaptureArguments(templateBody, identity, captures)
			For Local capture:TGenericTemplateNode = EachIn captures
				signature.children :+ [capture]
			Next
			signature.valueText = "local-routine-signature"
			signature.children :+ [templateBody]
			localRoutineContext.completed.Insert(routine, signature)
		Else If localRoutineContext.completed.Contains(routine) Then
			Local completedSignature:TGenericTemplateNode = TGenericTemplateNode(localRoutineContext.completed.ValueForKey(routine))
			If completedSignature Then
				For Local completedChild:TGenericTemplateNode = EachIn completedSignature.children
					If completedChild.valueText = "capture:self" Or completedChild.valueText.StartsWith("capture:outer:") Then signature.children :+ [completedChild]
				Next
			End If
		End If
		result.children = [signature]
		For Local index:Int = 0 Until routine.parameters.length
			Local boundArgument:TBoundExpression
			If index < call.arguments.length Then boundArgument = call.arguments[index]
			Local templateArgument:TGenericTemplateNode = TemplateResolvedCallArgument(boundArgument, index, call.resolvedCall, model, parameters, diagnostics, parameterOwner, localRoutineContext)
			If Not templateArgument Then Return Null
			result.children :+ [templateArgument]
		Next
		For Local signatureChild:TGenericTemplateNode = EachIn signature.children
			If signatureChild.valueText <> "capture:self" And Not signatureChild.valueText.StartsWith("capture:outer:") Then Continue
			Local captureArgument:TGenericTemplateNode = New TGenericTemplateNode
			captureArgument.semanticType = signatureChild.semanticType
			captureArgument.source = result.source
			If signatureChild.valueText = "capture:self" Then
				captureArgument.kind = TEMPLATE_NODE_SELF
				captureArgument.valueText = "self"
			Else
				captureArgument.kind = TEMPLATE_NODE_NAME
				captureArgument.valueText = signatureChild.valueText[14..]
			End If
			result.children :+ [captureArgument]
		Next
		Return result
	End Function

	Function OrdinaryConstructorObjectNewAbiName:String(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or symbol.name.ToLower() <> "new" Or Not symbol.parameters.length Then Return ""
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			If Not parameter Or (parameter.passingMode <> PARAMETER_PASS_VALUE And parameter.passingMode <> PARAMETER_PASS_VAR) Then Return ""
		Next
		Local implementationName:String = symbol.externalName
		If Not implementationName.length And Not symbol.isImported Then
			If model And model.moduleName.length And TCompilerAbiNamer.HasPublishedContainingType(symbol) Then
				implementationName = TCompilerAbiNamer.RoutineName(model, symbol, "")
				If Not implementationName.StartsWith("_") Then implementationName = "_" + implementationName
			Else
				implementationName = OrdinaryPrivateRoutineDependencyAbiName(symbol, model)
			End If
		End If
		If Not implementationName.length Then Return ""
		Local result:String = implementationName + "_ObjectNew"
		If TCompilerAbiNamer.Sanitize(result) <> result Then Return ""
		Return result
	End Function

	Function OrdinaryRoutineHasUnsupportedCallingConvention:Int(symbol:TSymbol)
		If Not symbol Then Return False
		If symbol.interfaceRecord And symbol.interfaceRecord.flags.Contains("W") Then Return True
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If Not declaration Or Not declaration.signature Then Return False
		For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
			If token.text.ToLower() = "stdcall" Then Return True
		Next
		Return False
	End Function

	Function IsTopLevelRoutine:Int(symbol:TSymbol)
		If Not symbol Then Return False
		Local scope:TScope = symbol.containingScope
		While scope
			If scope.owner And (scope.owner.kind = SYMBOL_TYPE Or scope.owner.kind = SYMBOL_STRUCT Or scope.owner.kind = SYMBOL_INTERFACE) Then Return False
			scope = scope.parent
		Wend
		Return True
	End Function

	Function SymbolReference:TTemplateSymbolReference(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Then Return Null
		Local result:TTemplateSymbolReference = New TTemplateSymbolReference
		result.moduleName = symbol.originModule
		If Not result.moduleName.length And model Then result.moduleName = model.moduleName
		result.qualifiedName = symbol.QualifiedName()
		result.namespaceKind = symbol.NamespaceKind()
		If symbol.genericTemplateArtifact And symbol.genericTemplateArtifact.identity Then result.overloadKey = symbol.genericTemplateArtifact.identity.signatureKey
		If symbol.genericArity > 0 And Not result.overloadKey.length Then result.overloadKey = SymbolRoutineSignatureKey(model, symbol)
		If Not result.overloadKey.length Then result.overloadKey = symbol.externalName
		If Not result.overloadKey.length Then result.overloadKey = symbol.name.ToLower() + "/" + symbol.parameters.length
		Return result
	End Function

	Function DataLabelReference:TTemplateSymbolReference(labelName:String)
		Local result:TTemplateSymbolReference = New TTemplateSymbolReference
		result.qualifiedName = labelName
		result.namespaceKind = SYMBOL_NAMESPACE_VALUE
		Return result
	End Function

	Function DataDefinitionIdentity:String(syntax:TDefDataStatementSyntax, model:TSemanticModel)
		If Not syntax Then Return ""
		Local source:TTemplateSourceLocation = SourceLocation(syntax, model)
		If Not source Then Return String(syntax.span.start)
		Return source.path.ToLower() + ":" + source.start
	End Function

	Function SourceLocation:TTemplateSourceLocation(syntax:TSyntaxNode, model:TSemanticModel)
		If Not syntax Then Return Null
		Local result:TTemplateSourceLocation = New TTemplateSourceLocation
		Local document:TSourceDocumentModel = SourceDocumentForSyntax(syntax, model)
		If document Then
			result.path = document.path
		Else If model And model.syntaxTree And model.syntaxTree.source Then
			result.path = model.syntaxTree.source.path
		End If
		If syntax.span Then
			result.start = syntax.span.start
			result.length = syntax.span.length
			Local source:TSourceText
			If document And document.tree Then source = document.tree.source Else If model And model.syntaxTree Then source = model.syntaxTree.source
			If source Then
				Local position:TSourcePosition = source.Position(syntax.span.start)
				result.line = position.line + 1
				result.column = position.column
			End If
		End If
		Return result
	End Function

	Function TemplateMetadata:TGenericTemplateMetadataEntry[](symbol:TSymbol, model:TSemanticModel)
		Local result:TGenericTemplateMetadataEntry[] = New TGenericTemplateMetadataEntry[0]
		If Not symbol Or Not symbol.metadata Then Return result
		Local declarationSource:TTemplateSourceLocation = SourceLocation(symbol.declaration, model)
		Local sourceText:TSourceText = SourceTextForSyntax(symbol.declaration, model)
		For Local sourceEntry:TDeclarationMetadataEntry = EachIn symbol.metadata.entries
			Local entry:TGenericTemplateMetadataEntry = New TGenericTemplateMetadataEntry
			entry.key = sourceEntry.key
			entry.value = sourceEntry.value
			entry.source = New TTemplateSourceLocation
			If declarationSource Then entry.source.path = declarationSource.path
			If sourceEntry.span Then
				entry.source.start = sourceEntry.span.start
				entry.source.length = sourceEntry.span.length
				If sourceText Then
					Local position:TSourcePosition = sourceText.Position(sourceEntry.span.start)
					entry.source.line = position.line + 1
					entry.source.column = position.column
				End If
			End If
			result :+ [entry]
		Next
		Return result
	End Function

	Function SourceTextForSyntax:TSourceText(syntax:TSyntaxNode, model:TSemanticModel)
		If Not syntax Or Not model Then Return Null
		Local document:TSourceDocumentModel = SourceDocumentForSyntax(syntax, model)
		If document And document.tree Then Return document.tree.source
		If model.syntaxTree Then Return model.syntaxTree.source
		Return Null
	End Function

	Function SourceDocumentForSyntax:TSourceDocumentModel(syntax:TSyntaxNode, model:TSemanticModel)
		If Not syntax Or Not model Then Return Null
		If activeSourceLocator And activeSourceLocator.model = model Then Return activeSourceLocator.DocumentForSyntax(syntax)
		If model.snapshot Then
			For Local document:TSourceDocumentModel = EachIn model.snapshot.documents
				If Not document Or Not document.tree Then Continue
				Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(document.tree)
				If navigator And navigator.ContainsNode(syntax) Then Return document
			Next
		End If
		Return Null
	End Function

End Type
