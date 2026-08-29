' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Const GENERIC_TEMPLATE_FORMAT_VERSION:Int = 32
Const GENERIC_TEMPLATE_MIN_READ_VERSION:Int = 1

Const GENERIC_DECLARATION_TYPE:Int = 1
Const GENERIC_DECLARATION_ROUTINE:Int = 2

Const GENERIC_TYPE_DECLARATION_CLASS:Int = 1
Const GENERIC_TYPE_DECLARATION_INTERFACE:Int = 2
Const GENERIC_TYPE_DECLARATION_STRUCT:Int = 3

Const TEMPLATE_PARAMETER_OWNER_TYPE:Int = 1
Const TEMPLATE_PARAMETER_OWNER_ROUTINE:Int = 2
' Builder-only owner mode. Serialized references are always rewritten to one
' of the two semantic owners above.
Const TEMPLATE_PARAMETER_OWNER_MIXED:Int = 3

Const GENERIC_INSTANCE_DECLARED:Int = 1
Const GENERIC_INSTANCE_BINDING:Int = 2
Const GENERIC_INSTANCE_BOUND:Int = 3
Const GENERIC_INSTANCE_LOWERING:Int = 4
Const GENERIC_INSTANCE_COMPLETE:Int = 5
Const GENERIC_INSTANCE_FAILED:Int = 6

Const TEMPLATE_TYPE_BUILTIN:Int = 1
Const TEMPLATE_TYPE_NAMED:Int = 2
Const TEMPLATE_TYPE_PARAMETER:Int = 3
Const TEMPLATE_TYPE_POINTER:Int = 4
Const TEMPLATE_TYPE_ARRAY:Int = 5
Const TEMPLATE_TYPE_STATIC_ARRAY:Int = 6
Const TEMPLATE_TYPE_CALLABLE:Int = 7
Const TEMPLATE_TYPE_CLOSURE:Int = 8

' Target-independent runtime identity published for ordinary, non-generic
' nominal types referenced by a template body. The ABI name is the stable
' BlitzMax language-linkage base name; backend-specific suffixes are not stored.
Const TEMPLATE_RUNTIME_NONE:Int = 0
Const TEMPLATE_RUNTIME_CLASS:Int = 1
Const TEMPLATE_RUNTIME_INTERFACE:Int = 2
Const TEMPLATE_RUNTIME_STRUCT:Int = 3
Const TEMPLATE_RUNTIME_ENUM:Int = 4

Const TEMPLATE_DISPATCH_NONE:Int = 0
Const TEMPLATE_DISPATCH_ORDINARY_CLASS:Int = 1

Const TEMPLATE_NODE_BLOCK:Int = 1
Const TEMPLATE_NODE_DECLARATION:Int = 2
Const TEMPLATE_NODE_NAME:Int = 3
Const TEMPLATE_NODE_LITERAL:Int = 4
Const TEMPLATE_NODE_CALL:Int = 5
Const TEMPLATE_NODE_MEMBER:Int = 6
Const TEMPLATE_NODE_OPERATOR:Int = 7
Const TEMPLATE_NODE_CONVERSION:Int = 8
Const TEMPLATE_NODE_NEW:Int = 9
Const TEMPLATE_NODE_ASSIGNMENT:Int = 10
Const TEMPLATE_NODE_RETURN:Int = 11
Const TEMPLATE_NODE_BRANCH:Int = 12
Const TEMPLATE_NODE_LOOP:Int = 13
Const TEMPLATE_NODE_THROW:Int = 14
Const TEMPLATE_NODE_CONSTRUCTOR_DELEGATION:Int = 15
Const TEMPLATE_NODE_LOOP_CONTROL:Int = 16
Const TEMPLATE_NODE_SELF:Int = 17
Const TEMPLATE_NODE_ARRAY_LENGTH:Int = 18
Const TEMPLATE_NODE_ARRAY_ELEMENT:Int = 19
Const TEMPLATE_NODE_ARRAY_SLICE:Int = 20
Const TEMPLATE_NODE_EXPRESSION_STATEMENT:Int = 21
Const TEMPLATE_NODE_ASSERT:Int = 22
Const TEMPLATE_NODE_SELECT:Int = 23
Const TEMPLATE_NODE_ARRAY_LITERAL:Int = 24
Const TEMPLATE_NODE_TRY:Int = 25
Const TEMPLATE_NODE_USING:Int = 26
Const TEMPLATE_NODE_DATA:Int = 27
Const TEMPLATE_NODE_FUNCTION_LITERAL:Int = 28
Const TEMPLATE_NODE_RELEASE:Int = 29
Const TEMPLATE_NODE_YIELD:Int = 30

Const TEMPLATE_MEMBER_FIELD:Int = 1
Const TEMPLATE_MEMBER_METHOD:Int = 2

Const TEMPLATE_INTERFACE_METHOD_NONE:Int = 0
Const TEMPLATE_INTERFACE_METHOD_ABSTRACT:Int = 1
Const TEMPLATE_INTERFACE_METHOD_DEFAULT:Int = 2
Const TEMPLATE_INTERFACE_METHOD_REABSTRACT:Int = 3

Const TEMPLATE_ARTIFACT_STORAGE_CANONICAL:Int = 1
Const TEMPLATE_ARTIFACT_STORAGE_LEGACY_BRIDGE:Int = 2

Type TGenericTemplateIdentity
	Field moduleName:String
	Field qualifiedName:String
	Field arity:Int
	Field contentRevision:String
	Field declarationKind:Int = GENERIC_DECLARATION_TYPE
	Field signatureKey:String

	Method StableName:String()
		Local kindName:String = "type"
		If declarationKind = GENERIC_DECLARATION_ROUTINE Then kindName = "routine"
		Local result:String = moduleName.ToLower() + "::" + qualifiedName.ToLower() + "#" + kindName + "/" + arity
		If signatureKey.length Then result :+ "/" + signatureKey.ToLower()
		Return result
	End Method

	Method VersionedName:String()
		Return StableName() + "@" + contentRevision
	End Method
End Type

Type TTemplateSourceLocation
	Field path:String
	Field start:Int
	Field length:Int
	Field line:Int
	Field column:Int
End Type

Type TGenericTemplateMetadataEntry
	Field key:String
	Field value:String
	Field source:TTemplateSourceLocation
End Type

Type TTemplateTypeReference
	Field kind:Int
	Field moduleName:String
	Field symbolName:String
	Field parameterIndex:Int = -1
	Field parameterOwner:Int = TEMPLATE_PARAMETER_OWNER_TYPE
	Field elementType:TTemplateTypeReference
	Field arguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
	' Callable types use elementType as their return type and arguments as their
	' ordered parameter types. Modes are stored separately so Var remains part
	' of the source-language ABI without introducing backend-specific C syntax.
	Field callableParameterModes:Int[] = New Int[0]
	' Managed Closure types retain their source parameter names for compact
	' interface publication. Names do not participate in callable identity.
	Field callableParameterNames:String[] = New String[0]
	Field rank:Int
	Field staticArrayLength:Long
	Field runtimeKind:Int
	Field runtimeAbiName:String
	' Optional ordinary Struct operator linkage selected when this closed type
	' is used as a specialization argument. It is not part of nominal identity.
	Field runtimeEqualityAbiName:String
	' Enum values have scalar storage rather than an object/Struct layout.
	' Retain the canonical builtin underlying type so specialization ABI does
	' not need the defining source or target-specific C lowering.
	Field runtimeValueType:String

	Method CanonicalName:String()
		Select kind
			Case TEMPLATE_TYPE_BUILTIN
				Return symbolName.ToLower()
			Case TEMPLATE_TYPE_PARAMETER
				If parameterOwner = TEMPLATE_PARAMETER_OWNER_ROUTINE Then Return "!routine:" + parameterIndex
				Return "!type:" + parameterIndex
			Case TEMPLATE_TYPE_POINTER
				Return elementType.CanonicalName() + " ptr"
			Case TEMPLATE_TYPE_ARRAY
				Return elementType.CanonicalName() + "[" + rank + "]"
			Case TEMPLATE_TYPE_STATIC_ARRAY
				Return "staticarray " + elementType.CanonicalName() + "[" + staticArrayLength + "]"
			Case TEMPLATE_TYPE_NAMED
				Local result:String = moduleName.ToLower() + "::" + symbolName.ToLower()
				If arguments.length Then
					result :+ "<"
					For Local index:Int = 0 Until arguments.length
						If index Then result :+ ","
						result :+ arguments[index].CanonicalName()
					Next
					result :+ ">"
				End If
				Return result
			Case TEMPLATE_TYPE_CALLABLE
				Local result:String = "callable "
				If elementType Then result :+ elementType.CanonicalName() Else result :+ "void"
				result :+ "("
				For Local index:Int = 0 Until arguments.length
					If index Then result :+ ","
					If index < callableParameterModes.length And callableParameterModes[index] = 2 Then result :+ "var:"
					result :+ arguments[index].CanonicalName()
				Next
				Return result + ")"
			Case TEMPLATE_TYPE_CLOSURE
				Local result:String = "closure "
				If elementType Then result :+ elementType.CanonicalName() Else result :+ "void"
				result :+ "("
				For Local index:Int = 0 Until arguments.length
					If index Then result :+ ","
					If index < callableParameterModes.length And callableParameterModes[index] = 2 Then result :+ "var:"
					result :+ arguments[index].CanonicalName()
				Next
				Return result + ")"
		End Select
		Return "<invalid-type>"
	End Method
End Type

Type TGenericTemplateParameter
	Field name:String
	Field ordinal:Int
	Field constraints:TTemplateTypeReference[] = New TTemplateTypeReference[0]
End Type

Type TGenericTemplateInheritanceReference
	Field semanticType:TTemplateTypeReference
	Field source:TTemplateSourceLocation
End Type

Type TTemplateSymbolReference
	Field moduleName:String
	Field qualifiedName:String
	Field namespaceKind:Int
	Field overloadKey:String

	Method StableName:String()
		Local result:String = moduleName.ToLower() + "::" + qualifiedName.ToLower() + "/" + namespaceKind
		If overloadKey.length Then result :+ "/" + overloadKey
		Return result
	End Method
End Type

Type TGenericTemplateNode
	Field kind:Int
	Field identity:String
	Field semanticType:TTemplateTypeReference
	Field referencedSymbol:TTemplateSymbolReference
	Field source:TTemplateSourceLocation
	Field valueText:String
	Field runtimeDispatchKind:Int
	Field runtimeDispatchIndex:Int = -1
	Field children:TGenericTemplateNode[] = New TGenericTemplateNode[0]

	Method AddChild(child:TGenericTemplateNode)
		children :+ [child]
	End Method
End Type

Type TGenericTemplateArtifact
	Field formatVersion:Int = GENERIC_TEMPLATE_FORMAT_VERSION
	Field identity:TGenericTemplateIdentity
	' Declaration provenance is used while publishing the compact Interface.
	' It is diagnostic/editor metadata rather than canonical specialization
	' content, so it is deliberately excluded from the artifact codec/revision.
	Field source:TTemplateSourceLocation
	' The revision is artifact content identity, not language type identity.
	' identity.contentRevision remains readable for version-1 callers during
	' migration, but new producers populate this field explicitly.
	Field contentRevision:String
	Field languageLinkageRevision:String
	Field storageKind:Int = TEMPLATE_ARTIFACT_STORAGE_CANONICAL
	Field cacheable:Int = True
	Field typeDeclarationKind:Int = GENERIC_TYPE_DECLARATION_CLASS
	Field visibility:Int
	Field isAbstract:Int
	Field metadata:TGenericTemplateMetadataEntry[] = New TGenericTemplateMetadataEntry[0]
	Field isMethod:Int
	Field containingParameters:TGenericTemplateParameter[] = New TGenericTemplateParameter[0]
	Field containingType:TTemplateTypeReference
	' A generic method implementation is emitted outside its defining ordinary
	' Type/Struct unit. Preserve the target-independent owner field layout needed
	' to bind unqualified field access without copying or reparsing source.
	Field containingFields:TGenericTemplateMember[] = New TGenericTemplateMember[0]
	Field parameters:TGenericTemplateParameter[] = New TGenericTemplateParameter[0]
	Field baseType:TGenericTemplateInheritanceReference
	Field interfaces:TGenericTemplateInheritanceReference[] = New TGenericTemplateInheritanceReference[0]
	Field referencedApis:TTemplateSymbolReference[] = New TTemplateSymbolReference[0]
	Field members:TGenericTemplateMember[] = New TGenericTemplateMember[0]
	Field body:TGenericTemplateNode

	Method EffectiveContentRevision:String()
		If contentRevision.length Then Return contentRevision
		If identity Then Return identity.contentRevision
		Return ""
	End Method

	Method InstanceKey:String(arguments:TTemplateTypeReference[])
		Local result:String = identity.StableName() + "@" + EffectiveContentRevision() + "<"
		For Local index:Int = 0 Until arguments.length
			If index Then result :+ ","
			result :+ arguments[index].CanonicalName()
		Next
		Return result + ">"
	End Method
End Type

Type TGenericTemplateValueParameter
	Field name:String
	Field ordinal:Int
	Field semanticType:TTemplateTypeReference
	Field passingMode:Int
	' Optional-call semantics are part of the target-independent template ABI.
	' The retained default is a bound template expression, never source text.
	Field optional:Int
	Field defaultValue:TGenericTemplateNode
	Field source:TTemplateSourceLocation
End Type

Type TGenericTemplateMember
	Field kind:Int
	' Interface methods retain whether they are abstract, default, or an
	' explicit reabstraction. Zero remains valid for non-Interface members.
	Field interfaceMethodKind:Int
	Field identity:String
	Field name:String
	' Type/Struct-owned Global declarations are specialization-owned static
	' storage. They are distinct from instance fields even though both retain
	' the same closed value type and optional bound initializer.
	Field isStatic:Int
	' A Type Function has no instance receiver for a statically qualified call,
	' but remains in a Type class table so an object-qualified call can select a
	' derived replacement. Keep that language distinction separate from Struct
	' Functions and specialization-owned static storage.
	Field isTypeFunction:Int
	' Stable language-linkage identity when a member participates in a
	' separately emitted ABI layout. This is semantic ownership, not a
	' backend-specific declaration.
	Field linkageName:String
	Field visibility:Int
	Field metadata:TGenericTemplateMetadataEntry[] = New TGenericTemplateMetadataEntry[0]
	Field semanticType:TTemplateTypeReference
	Field parameters:TGenericTemplateValueParameter[] = New TGenericTemplateValueParameter[0]
	Field body:TGenericTemplateNode
	Field source:TTemplateSourceLocation
End Type

Type TGenericTemplateCatalog
	Field artifacts:TMap = New TMap

	Method Add:Int(artifact:TGenericTemplateArtifact)
		If Not artifact Or Not artifact.identity Then Return False
		Local key:String = artifact.identity.StableName() + "@" + artifact.EffectiveContentRevision()
		If artifacts.Contains(key) Then Return False
		artifacts.Insert(key, artifact)
		Return True
	End Method

	Method Find:TGenericTemplateArtifact(identity:TGenericTemplateIdentity, contentRevision:String = "")
		If Not identity Then Return Null
		If Not contentRevision.length Then contentRevision = identity.contentRevision
		Return TGenericTemplateArtifact(artifacts.ValueForKey(identity.StableName() + "@" + contentRevision))
	End Method
End Type

Type TTemplateTypeSubstitution
	Function Apply:TTemplateTypeReference(value:TTemplateTypeReference, typeArguments:TTemplateTypeReference[], routineArguments:TTemplateTypeReference[] = Null)
		If Not value Then Return Null
		If value.kind = TEMPLATE_TYPE_PARAMETER Then
			If value.parameterOwner = TEMPLATE_PARAMETER_OWNER_ROUTINE Then
				If value.parameterIndex >= 0 And value.parameterIndex < routineArguments.length Then Return routineArguments[value.parameterIndex]
			Else If value.parameterIndex >= 0 And value.parameterIndex < typeArguments.length Then
				Return typeArguments[value.parameterIndex]
			End If
			Return value
		End If
		Local result:TTemplateTypeReference = New TTemplateTypeReference
		result.kind = value.kind
		result.moduleName = value.moduleName
		result.symbolName = value.symbolName
		result.parameterIndex = value.parameterIndex
		result.parameterOwner = value.parameterOwner
		result.rank = value.rank
		result.staticArrayLength = value.staticArrayLength
		result.runtimeKind = value.runtimeKind
		result.runtimeAbiName = value.runtimeAbiName
		result.runtimeEqualityAbiName = value.runtimeEqualityAbiName
		result.runtimeValueType = value.runtimeValueType
		result.callableParameterModes = value.callableParameterModes[..]
		result.callableParameterNames = value.callableParameterNames[..]
		result.elementType = Apply(value.elementType, typeArguments, routineArguments)
		result.arguments = New TTemplateTypeReference[value.arguments.length]
		For Local index:Int = 0 Until value.arguments.length
			result.arguments[index] = Apply(value.arguments[index], typeArguments, routineArguments)
		Next
		Return result
	End Function
End Type

Type TGenericInstanceRecord
	Field artifact:TGenericTemplateArtifact
	Field typeArguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
	Field routineArguments:TTemplateTypeReference[] = New TTemplateTypeReference[0]
	Field key:String
	Field state:Int = GENERIC_INSTANCE_DECLARED
End Type

Type TGenericInstanceCatalog
	Field instances:TMap = New TMap

	Method GetOrDeclare:TGenericInstanceRecord(artifact:TGenericTemplateArtifact, typeArguments:TTemplateTypeReference[], routineArguments:TTemplateTypeReference[] = Null)
		Local key:String = artifact.InstanceKey(typeArguments)
		If routineArguments.length Then
			key :+ "::routine<"
			For Local index:Int = 0 Until routineArguments.length
				If index Then key :+ ","
				key :+ routineArguments[index].CanonicalName()
			Next
			key :+ ">"
		End If
		Local existing:TGenericInstanceRecord = TGenericInstanceRecord(instances.ValueForKey(key))
		If existing Then Return existing
		Local result:TGenericInstanceRecord = New TGenericInstanceRecord
		result.artifact = artifact
		result.typeArguments = typeArguments
		result.routineArguments = routineArguments
		result.key = key
		instances.Insert(key, result)
		Return result
	End Method
End Type
