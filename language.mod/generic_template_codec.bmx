' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Base64
Import BRL.StringBuilder
Import Crypto.SHA256Digest

Import "generic_template_model.bmx"

Const GENERIC_TEMPLATE_ARTIFACT_MAGIC:String = "BMXGT"
Const GENERIC_TEMPLATE_ARTIFACT_MAX_RECORDS:Int = 100000
Const GENERIC_TEMPLATE_ARTIFACT_MAX_DEPTH:Int = 128
Const GENERIC_TEMPLATE_PARAMETER_PASS_VALUE:Int = 1
Const GENERIC_TEMPLATE_PARAMETER_PASS_VAR:Int = 2

Type TGenericTemplateArtifactDecodeResult
	Field artifact:TGenericTemplateArtifact
	Field diagnostics:String[] = New String[0]

	Method Succeeded:Int()
		Return artifact <> Null And diagnostics.length = 0
	End Method
End Type

Type TGenericTemplateArtifactCodec
	Function IsEnumValueType:Int(value:String)
		Select value.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t"
				Return True
		End Select
		Return False
	End Function

	Function Encode:String(artifact:TGenericTemplateArtifact, diagnostics:String[] Var)
		Return EncodeCore(artifact, diagnostics, False)
	End Function

	' Source-built artifacts need their content revision before their companion
	' path and specialization keys can be finalized. Compute the canonical
	' payload once, assign that revision, and return the matching encoding.
	Function FinalizeAndEncode:String(artifact:TGenericTemplateArtifact, diagnostics:String[] Var)
		Return EncodeCore(artifact, diagnostics, True)
	End Function

	Function EncodeCore:String(artifact:TGenericTemplateArtifact, diagnostics:String[] Var, assignRevision:Int)
		diagnostics = New String[0]
		If Not artifact Or Not artifact.identity Then
			diagnostics :+ ["BMXGT100 generic template artifact identity is required"]
			Return ""
		End If
		If artifact.formatVersion <> GENERIC_TEMPLATE_FORMAT_VERSION Then
			diagnostics :+ ["BMXGT101 unsupported generic template artifact version " + artifact.formatVersion]
			Return ""
		End If
		Local payload:String = CanonicalPayload(artifact, diagnostics)
		If diagnostics.length Then Return ""
		Local revision:String = Digest(payload)
		If artifact.EffectiveContentRevision().length And artifact.EffectiveContentRevision().ToLower() <> revision Then
			diagnostics :+ ["BMXGT102 artifact content revision does not match its canonical payload"]
			Return ""
		End If
		If assignRevision Then artifact.contentRevision = revision
		Return GENERIC_TEMPLATE_ARTIFACT_MAGIC + " " + GENERIC_TEMPLATE_FORMAT_VERSION + "~nrevision " + revision + "~n" + payload
	End Function

	Function Decode:TGenericTemplateArtifactDecodeResult(text:String, expectedRevision:String = "")
		Local result:TGenericTemplateArtifactDecodeResult = New TGenericTemplateArtifactDecodeResult
		Local normalized:String = text.Replace(Chr(13), "")
		Local lines:String[] = normalized.Split(Chr(10))
		Local documentVersion:Int
		If lines.length >= 3 And lines[0].StartsWith(GENERIC_TEMPLATE_ARTIFACT_MAGIC + " ")
			Local versionText:String = lines[0][GENERIC_TEMPLATE_ARTIFACT_MAGIC.length + 1..]
			If TGenericTemplateRecordReader.IsInteger(versionText) Then documentVersion = Int(versionText)
		End If
		If lines.length < 3 Or documentVersion < GENERIC_TEMPLATE_MIN_READ_VERSION Or documentVersion > GENERIC_TEMPLATE_FORMAT_VERSION Then
			result.diagnostics :+ ["BMXGT103 missing or unsupported generic template artifact header"]
			Return result
		End If
		If Not lines[1].StartsWith("revision ") Then
			result.diagnostics :+ ["BMXGT104 generic template artifact revision header is missing"]
			Return result
		End If
		Local revision:String = lines[1][9..].ToLower()
		If revision.length <> 64 Then
			result.diagnostics :+ ["BMXGT104 generic template artifact revision is malformed"]
			Return result
		End If
		Local payloadBuilder:TStringBuilder = New TStringBuilder(Max(4096, text.length))
		For Local index:Int = 2 Until lines.length
			If index > 2 Then payloadBuilder.Append("~n")
			payloadBuilder.Append(lines[index])
		Next
		Local payload:String = payloadBuilder.ToString()
		If Digest(payload) <> revision Then
			result.diagnostics :+ ["BMXGT105 generic template artifact payload digest mismatch"]
			Return result
		End If
		If expectedRevision.length And expectedRevision.ToLower() <> revision Then
			result.diagnostics :+ ["BMXGT106 generic template artifact revision does not match the interface reference"]
			Return result
		End If
		Local reader:TGenericTemplateRecordReader = New TGenericTemplateRecordReader
		reader.lines = lines[2..]
		reader.documentVersion = documentVersion
		result.artifact = reader.ReadArtifact()
		result.diagnostics = reader.diagnostics
		If result.diagnostics.length Then result.artifact = Null; Return result
		result.artifact.contentRevision = revision
		Return result
	End Function

	Function ComputeContentRevision:String(artifact:TGenericTemplateArtifact, diagnostics:String[] Var)
		diagnostics = New String[0]
		Local payload:String = CanonicalPayload(artifact, diagnostics)
		If diagnostics.length Then Return ""
		Return Digest(payload)
	End Function

	Function CanonicalPayload:String(artifact:TGenericTemplateArtifact, diagnostics:String[] Var)
		Local writer:TGenericTemplateRecordWriter = New TGenericTemplateRecordWriter
		writer.WriteArtifact(artifact)
		diagnostics = writer.diagnostics
		Return writer.text.ToString()
	End Function

	Function Digest:String(value:String)
		Local digest:TSHA256 = New TSHA256
		Return digest.Digest(value).ToLower()
	End Function
End Type

Type TGenericTemplateRecordWriter
	Field text:TStringBuilder = New TStringBuilder(4096)
	Field diagnostics:String[] = New String[0]
	Field recordCount:Int
	Field documentVersion:Int

	Method Line(value:String)
		If recordCount >= GENERIC_TEMPLATE_ARTIFACT_MAX_RECORDS Then
			If Not diagnostics.length Then diagnostics :+ ["BMXGT107 generic template artifact exceeds the record limit"]
			Return
		End If
		If text.Length() Then text.Append("~n")
		text.Append(value)
		recordCount :+ 1
	End Method

	Method StringValue(value:String)
		Line("s " + TBase64.Encode(value, EBase64Options.DontBreakLines))
	End Method

	Method IntValue(value:Int)
		Line("i " + value)
	End Method

	Method LongValue(value:Long)
		Line("l " + value)
	End Method

	Method WriteArtifact(artifact:TGenericTemplateArtifact)
		If Not artifact Or Not artifact.identity Then
			diagnostics :+ ["BMXGT100 generic template artifact identity is required"]
			Return
		End If
		documentVersion = artifact.formatVersion
		If documentVersion >= 13 Then
			If artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE And Not artifact.identity.signatureKey.length Then
				diagnostics :+ ["BMXGT137 generic routine artifact requires an open signature identity"]
				Return
			End If
			If artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE And artifact.identity.signatureKey.length Then
				diagnostics :+ ["BMXGT137 non-routine template carries an open signature identity"]
				Return
			End If
			If artifact.isMethod And artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then
				diagnostics :+ ["BMXGT137 generic method flag requires a routine artifact"]
				Return
			End If
		End If
		If documentVersion < 14 And artifact.containingFields.length Then
			diagnostics :+ ["BMXGT138 containing-owner field layout requires generic template artifact format 14"]
			Return
		End If
		If documentVersion < 15 And MembersCarryLinkage(artifact.containingFields + artifact.members) Then
			diagnostics :+ ["BMXGT139 member language-linkage identity requires generic template artifact format 15"]
			Return
		End If
		If documentVersion < 18 And MembersCarryOptionalDefaults(artifact.containingFields + artifact.members) Then
			diagnostics :+ ["BMXGT140 optional value-parameter defaults require generic template artifact format 18"]
			Return
		End If
		If documentVersion < 23 And MembersCarryStaticStorage(artifact.containingFields + artifact.members) Then
			diagnostics :+ ["BMXGT143 specialization-owned static storage requires generic template artifact format 23"]
			Return
		End If
		If documentVersion < 24 And MembersCarryInterfaceMethodKinds(artifact.containingFields + artifact.members) Then
			diagnostics :+ ["BMXGT144 Interface method implementation kinds require generic template artifact format 24"]
			Return
		End If
		If documentVersion < 26 And (artifact.visibility Or artifact.isAbstract Or artifact.metadata.length Or MembersCarryMetadata(artifact.containingFields + artifact.members)) Then
			diagnostics :+ ["BMXGT145 generic reflection metadata requires generic template artifact format 26"]
			Return
		End If
		If documentVersion < 30 And MembersCarryTypeFunctions(artifact.containingFields + artifact.members) Then
			diagnostics :+ ["BMXGT146 generic Type Function identity requires generic template artifact format 30"]
			Return
		End If
		Line("artifact")
		IntValue(artifact.formatVersion)
		StringValue(artifact.identity.moduleName)
		StringValue(artifact.identity.qualifiedName)
		IntValue(artifact.identity.arity)
		IntValue(artifact.identity.declarationKind)
		If documentVersion >= 13 Then StringValue(artifact.identity.signatureKey)
		StringValue(artifact.languageLinkageRevision)
		IntValue(artifact.storageKind)
		IntValue(artifact.cacheable)
		IntValue(artifact.typeDeclarationKind)
		If documentVersion >= 26 Then
			IntValue(artifact.visibility)
			IntValue(artifact.isAbstract)
			WriteMetadata("artifact-metadata", artifact.metadata)
		End If
		If documentVersion >= 13 Then
			IntValue(artifact.isMethod)
			Line("containing-parameters " + artifact.containingParameters.length)
			For Local parameter:TGenericTemplateParameter = EachIn artifact.containingParameters
				WriteParameter(parameter)
			Next
			WriteOptionalType(artifact.containingType, 0)
			If documentVersion >= 14 Then WriteMembers("containing-members", artifact.containingFields)
		End If
		Line("parameters " + artifact.parameters.length)
		For Local parameter:TGenericTemplateParameter = EachIn artifact.parameters
			WriteParameter(parameter)
		Next
		WriteOptionalInheritance(artifact.baseType, 0)
		Line("interfaces " + artifact.interfaces.length)
		For Local reference:TGenericTemplateInheritanceReference = EachIn artifact.interfaces
			WriteInheritance(reference, 0)
		Next
		Line("apis " + artifact.referencedApis.length)
		For Local reference:TTemplateSymbolReference = EachIn artifact.referencedApis
			WriteSymbol(reference)
		Next
		WriteMembers("members", artifact.members)
		WriteOptionalNode(artifact.body, 0)
		Line("end-artifact")
	End Method

	Method WriteMembers(label:String, members:TGenericTemplateMember[])
		Line(label + " " + members.length)
		For Local member:TGenericTemplateMember = EachIn members
			If Not member Or (member.kind <> TEMPLATE_MEMBER_FIELD And member.kind <> TEMPLATE_MEMBER_METHOD) Then
				diagnostics :+ ["BMXGT121 unknown or missing generic template member kind"]
				Continue
			End If
			If member.isStatic <> 0 And member.isStatic <> 1 Then
				diagnostics :+ ["BMXGT143 invalid static template-member flag"]
				Continue
			End If
			If member.isStatic And member.kind <> TEMPLATE_MEMBER_FIELD And member.kind <> TEMPLATE_MEMBER_METHOD Then
				diagnostics :+ ["BMXGT143 only field- or routine-shaped template members may be static"]
				Continue
			End If
			If member.isTypeFunction <> 0 And member.isTypeFunction <> 1 Then
				diagnostics :+ ["BMXGT146 invalid Type Function template-member flag"]
				Continue
			End If
			If member.isTypeFunction And member.kind <> TEMPLATE_MEMBER_METHOD Then
				diagnostics :+ ["BMXGT146 only method-shaped template members may be Type Functions"]
				Continue
			End If
			Line("member")
			IntValue(member.kind)
			If member.interfaceMethodKind < TEMPLATE_INTERFACE_METHOD_NONE Or member.interfaceMethodKind > TEMPLATE_INTERFACE_METHOD_REABSTRACT Then
				diagnostics :+ ["BMXGT144 invalid Interface method implementation kind"]
				Continue
			End If
			If member.interfaceMethodKind And member.kind <> TEMPLATE_MEMBER_METHOD Then
				diagnostics :+ ["BMXGT144 only method-shaped template members may carry an Interface implementation kind"]
				Continue
			End If
			StringValue(member.identity)
			StringValue(member.name)
			If documentVersion >= 24 Then IntValue(member.interfaceMethodKind)
			If documentVersion >= 23 Then IntValue(member.isStatic)
			If documentVersion >= 30 Then IntValue(member.isTypeFunction)
			If documentVersion >= 15 Then StringValue(member.linkageName)
			IntValue(member.visibility)
			If documentVersion >= 26 Then WriteMetadata("member-metadata", member.metadata)
			WriteOptionalType(member.semanticType, 0)
			Line("value-parameters " + member.parameters.length)
			For Local parameter:TGenericTemplateValueParameter = EachIn member.parameters
				Line("value-parameter")
				StringValue(parameter.name)
				IntValue(parameter.ordinal)
				WriteOptionalType(parameter.semanticType, 0)
				IntValue(parameter.passingMode)
				If documentVersion >= 18 Then
					IntValue(parameter.optional)
					WriteOptionalNode(parameter.defaultValue, 0)
					If parameter.optional And Not parameter.defaultValue Then diagnostics :+ ["BMXGT140 optional value parameter '" + parameter.name + "' requires a retained default expression"]
					If Not parameter.optional And parameter.defaultValue Then diagnostics :+ ["BMXGT140 non-optional value parameter '" + parameter.name + "' carries a default expression"]
				End If
				WriteSource(parameter.source)
			Next
			WriteOptionalNode(member.body, 0)
			WriteSource(member.source)
		Next
	End Method

	Method WriteMetadata(label:String, entries:TGenericTemplateMetadataEntry[])
		Line(label + " " + entries.length)
		For Local entry:TGenericTemplateMetadataEntry = EachIn entries
			If Not entry Or Not entry.key.length Then diagnostics :+ ["BMXGT145 invalid generic reflection metadata entry"]; Continue
			Line("metadata")
			StringValue(entry.key)
			StringValue(entry.value)
			WriteSource(entry.source)
		Next
	End Method

	Function MembersCarryLinkage:Int(members:TGenericTemplateMember[])
		For Local member:TGenericTemplateMember = EachIn members
			If member And member.linkageName.length Then Return True
		Next
		Return False
	End Function

	Function MembersCarryOptionalDefaults:Int(members:TGenericTemplateMember[])
		For Local member:TGenericTemplateMember = EachIn members
			If Not member Then Continue
			For Local parameter:TGenericTemplateValueParameter = EachIn member.parameters
				If parameter And (parameter.optional Or parameter.defaultValue) Then Return True
			Next
		Next
		Return False
	End Function

	Function MembersCarryStaticStorage:Int(members:TGenericTemplateMember[])
		For Local member:TGenericTemplateMember = EachIn members
			If member And member.isStatic Then Return True
		Next
		Return False
	End Function

	Function MembersCarryInterfaceMethodKinds:Int(members:TGenericTemplateMember[])
		For Local member:TGenericTemplateMember = EachIn members
			If member And member.interfaceMethodKind Then Return True
		Next
		Return False
	End Function

	Function MembersCarryMetadata:Int(members:TGenericTemplateMember[])
		For Local member:TGenericTemplateMember = EachIn members
			If member And member.metadata.length Then Return True
		Next
		Return False
	End Function

	Function MembersCarryTypeFunctions:Int(members:TGenericTemplateMember[])
		For Local member:TGenericTemplateMember = EachIn members
			If member And member.isTypeFunction Then Return True
		Next
		Return False
	End Function

	Method WriteParameter(parameter:TGenericTemplateParameter)
		Line("parameter")
		StringValue(parameter.name)
		IntValue(parameter.ordinal)
		Line("constraints " + parameter.constraints.length)
		For Local constraint:TTemplateTypeReference = EachIn parameter.constraints
			WriteType(constraint, 0)
		Next
	End Method

	Method WriteOptionalInheritance(value:TGenericTemplateInheritanceReference, depth:Int)
		If value Then IntValue(1); WriteInheritance(value, depth) Else IntValue(0)
	End Method

	Method WriteInheritance(value:TGenericTemplateInheritanceReference, depth:Int)
		If Not value Or Not value.semanticType Then diagnostics :+ ["BMXGT126 invalid generic template inheritance reference"]; Return
		Line("inheritance")
		WriteType(value.semanticType, depth)
		WriteSource(value.source)
	End Method

	Method WriteOptionalType(value:TTemplateTypeReference, depth:Int)
		If value Then IntValue(1); WriteType(value, depth) Else IntValue(0)
	End Method

	Method WriteType(value:TTemplateTypeReference, depth:Int)
		If depth > GENERIC_TEMPLATE_ARTIFACT_MAX_DEPTH Or Not value Then
			diagnostics :+ ["BMXGT108 invalid or excessively nested template type reference"]
			Return
		End If
		If value.kind < TEMPLATE_TYPE_BUILTIN Or value.kind > TEMPLATE_TYPE_CLOSURE Then
			diagnostics :+ ["BMXGT122 unknown generic template type kind " + value.kind]
			Return
		End If
		If value.kind = TEMPLATE_TYPE_CALLABLE And documentVersion < 21 Then
			diagnostics :+ ["BMXGT141 callable template types require generic template artifact format 21"]
			Return
		End If
		If value.kind = TEMPLATE_TYPE_CLOSURE And documentVersion < 27 Then
			diagnostics :+ ["BMXGT142 Closure template types require generic template artifact format 27"]
			Return
		End If
		If value.kind = TEMPLATE_TYPE_CLOSURE And value.callableParameterNames.length <> value.arguments.length Then
			diagnostics :+ ["BMXGT142 Closure template type parameter names do not match its parameter types"]
			Return
		End If
		If value.kind <> TEMPLATE_TYPE_CLOSURE And value.callableParameterNames.length Then
			diagnostics :+ ["BMXGT142 non-Closure template type carries Closure parameter names"]
			Return
		End If
		If value.kind = TEMPLATE_TYPE_CALLABLE Or value.kind = TEMPLATE_TYPE_CLOSURE Then
			If Not value.elementType Then
				diagnostics :+ ["BMXGT141 callable template type requires a return type"]
				Return
			End If
			If value.callableParameterModes.length <> value.arguments.length Then
				diagnostics :+ ["BMXGT141 callable template type parameter modes do not match its parameter types"]
				Return
			End If
			For Local mode:Int = EachIn value.callableParameterModes
				If mode <> GENERIC_TEMPLATE_PARAMETER_PASS_VALUE And mode <> GENERIC_TEMPLATE_PARAMETER_PASS_VAR Then
					diagnostics :+ ["BMXGT141 callable template type has an unknown parameter mode"]
					Return
				End If
			Next
		Else If value.callableParameterModes.length Or value.callableParameterNames.length Then
			diagnostics :+ ["BMXGT141 non-callable template type carries callable parameter modes"]
			Return
		End If
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY And documentVersion < 6 Then
			diagnostics :+ ["BMXGT129 StaticArray template type requires generic template artifact format 6"]
			Return
		End If
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY And value.staticArrayLength <= 0 Then
			diagnostics :+ ["BMXGT129 StaticArray template type requires a positive fixed extent"]
			Return
		End If
		If value.kind <> TEMPLATE_TYPE_STATIC_ARRAY And value.staticArrayLength <> 0 Then
			diagnostics :+ ["BMXGT129 non-StaticArray template type carries a fixed extent"]
			Return
		End If
		If value.runtimeKind < TEMPLATE_RUNTIME_NONE Or value.runtimeKind > TEMPLATE_RUNTIME_ENUM Then
			diagnostics :+ ["BMXGT130 unknown ordinary runtime type identity kind " + value.runtimeKind]
			Return
		End If
		If value.runtimeKind <> TEMPLATE_RUNTIME_NONE And value.kind <> TEMPLATE_TYPE_NAMED Then
			diagnostics :+ ["BMXGT130 ordinary runtime identity requires a named template type"]
			Return
		End If
		If value.runtimeKind <> TEMPLATE_RUNTIME_NONE And Not value.runtimeAbiName.length And (documentVersion < 28 Or Not value.arguments.length) Then
			diagnostics :+ ["BMXGT130 ordinary runtime identity requires a stable language-linkage name; only constructed generic runtime categories may defer their specialization ABI"]
			Return
		End If
		If value.runtimeKind = TEMPLATE_RUNTIME_NONE And value.runtimeAbiName.length Then
			diagnostics :+ ["BMXGT130 ordinary runtime linkage name requires a runtime identity kind"]
			Return
		End If
		If value.runtimeKind <> TEMPLATE_RUNTIME_NONE And documentVersion < 7 Then
			diagnostics :+ ["BMXGT130 ordinary runtime type identity requires generic template artifact format 7"]
			Return
		End If
		If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT And documentVersion < 14 Then
			diagnostics :+ ["BMXGT138 ordinary Struct runtime identity requires generic template artifact format 14"]
			Return
		End If
		If documentVersion >= 18 Then
			If value.runtimeKind = TEMPLATE_RUNTIME_ENUM And Not TGenericTemplateArtifactCodec.IsEnumValueType(value.runtimeValueType) Then
				diagnostics :+ ["BMXGT140 ordinary Enum runtime identity requires a supported integral value type"]
				Return
			End If
			If value.runtimeKind <> TEMPLATE_RUNTIME_ENUM And value.runtimeValueType.length Then
				diagnostics :+ ["BMXGT140 non-Enum runtime identity carries an Enum value type"]
				Return
			End If
		Else If value.runtimeKind = TEMPLATE_RUNTIME_ENUM Or value.runtimeValueType.length Then
			diagnostics :+ ["BMXGT140 ordinary Enum runtime identity requires generic template artifact format 18"]
			Return
		End If
		Line("type")
		IntValue(value.kind)
		StringValue(value.moduleName)
		StringValue(value.symbolName)
		IntValue(value.parameterIndex)
		IntValue(value.parameterOwner)
		IntValue(value.rank)
		If documentVersion >= 6 Then LongValue(value.staticArrayLength)
		If documentVersion >= 7 Then
			IntValue(value.runtimeKind)
			StringValue(value.runtimeAbiName)
		End If
		If documentVersion >= 18 Then StringValue(value.runtimeValueType)
		WriteOptionalType(value.elementType, depth + 1)
		Line("arguments " + value.arguments.length)
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			WriteType(argument, depth + 1)
		Next
		If documentVersion >= 21 Then
			Line("callable-modes " + value.callableParameterModes.length)
			For Local mode:Int = EachIn value.callableParameterModes
				IntValue(mode)
			Next
		End If
		If documentVersion >= 27 Then
			Line("callable-names " + value.callableParameterNames.length)
			For Local parameterName:String = EachIn value.callableParameterNames
				StringValue(parameterName)
			Next
		End If
	End Method

	Method WriteSymbol(value:TTemplateSymbolReference)
		If Not value Then diagnostics :+ ["BMXGT109 null symbolic dependency reference"]; Return
		Line("symbol")
		StringValue(value.moduleName)
		StringValue(value.qualifiedName)
		IntValue(value.namespaceKind)
		StringValue(value.overloadKey)
	End Method

	Method WriteSource(value:TTemplateSourceLocation)
		If Not value Then IntValue(0); Return
		IntValue(1)
		Line("source")
		StringValue(value.path)
		IntValue(value.start)
		IntValue(value.length)
		If documentVersion >= 26 Then
			IntValue(value.line)
			IntValue(value.column)
		End If
	End Method

	Method WriteOptionalNode(value:TGenericTemplateNode, depth:Int)
		If value Then IntValue(1); WriteNode(value, depth) Else IntValue(0)
	End Method

	Method WriteNode(value:TGenericTemplateNode, depth:Int)
		If depth > GENERIC_TEMPLATE_ARTIFACT_MAX_DEPTH Or Not value Then
			diagnostics :+ ["BMXGT110 invalid or excessively nested template body node"]
			Return
		End If
		If value.kind < TEMPLATE_NODE_BLOCK Or value.kind > TEMPLATE_NODE_YIELD Then
			diagnostics :+ ["BMXGT124 unknown generic template body node kind " + value.kind]
			Return
		End If
		If value.kind = TEMPLATE_NODE_LOOP_CONTROL And documentVersion < 5 Then
			diagnostics :+ ["BMXGT124 loop control requires generic template artifact format 5"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_SELF And documentVersion < 9 Then
			diagnostics :+ ["BMXGT132 Self/Super receiver identity requires generic template artifact format 9"]
			Return
		End If
		If (value.kind = TEMPLATE_NODE_ARRAY_LENGTH Or value.kind = TEMPLATE_NODE_ARRAY_ELEMENT) And documentVersion < 10 Then
			diagnostics :+ ["BMXGT133 managed array operations require generic template artifact format 10"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_ARRAY_SLICE And documentVersion < 11 Then
			diagnostics :+ ["BMXGT134 managed array slicing requires generic template artifact format 11"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT And documentVersion < 12 Then
			diagnostics :+ ["BMXGT135 expression statements require generic template artifact format 12"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_ASSERT And documentVersion < 16 Then
			diagnostics :+ ["BMXGT137 Assert statements require generic template artifact format 16"]
			Return
		End If
		If (value.kind = TEMPLATE_NODE_SELECT Or value.kind = TEMPLATE_NODE_ARRAY_LITERAL Or value.kind = TEMPLATE_NODE_TRY Or value.kind = TEMPLATE_NODE_USING) And documentVersion < 20 Then
			diagnostics :+ ["BMXGT139 Select, managed Array literal, Try, and Using nodes require generic template artifact format 20"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_DATA And documentVersion < 21 Then
			diagnostics :+ ["BMXGT141 Data nodes require generic template artifact format 21"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_FUNCTION_LITERAL And documentVersion < 27 Then
			diagnostics :+ ["BMXGT142 Function literals require generic template artifact format 27"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_RELEASE And documentVersion < 29 Then
			diagnostics :+ ["BMXGT143 Release statements require generic template artifact format 29"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_YIELD And documentVersion < 31 Then
			diagnostics :+ ["BMXGT144 Yield statements require generic template artifact format 31"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_TRY And value.valueText <> "finally" And documentVersion < 21 Then
			diagnostics :+ ["BMXGT141 Try/Catch routing requires generic template artifact format 21"]
			Return
		End If
		Local localRoutineRecord:Int = value.kind = TEMPLATE_NODE_BLOCK And (value.valueText = "local-routine-signature" Or value.valueText = "local-routine-reference")
		If localRoutineRecord And documentVersion < 17 Then
			diagnostics :+ ["BMXGT138 local routine records require generic template artifact format 17"]
			Return
		End If
		If localRoutineRecord And Not value.identity.length Then
			diagnostics :+ ["BMXGT138 local routine records require a stable semantic identity"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_BLOCK And value.valueText = "local-routine-signature" And (Not value.children.length Or value.children[value.children.length - 1].kind <> TEMPLATE_NODE_BLOCK) Then
			diagnostics :+ ["BMXGT138 local routine signatures require a semantic body block"]
			Return
		End If
		If localRoutineRecord And documentVersion >= 19 Then
			Local parameterCount:Int = value.children.length
			If value.valueText = "local-routine-signature" Then parameterCount :- 1
			For Local index:Int = 0 Until parameterCount
				Local mode:Int = Int(value.children[index].identity)
				If mode <> GENERIC_TEMPLATE_PARAMETER_PASS_VALUE And mode <> GENERIC_TEMPLATE_PARAMETER_PASS_VAR Then
					diagnostics :+ ["BMXGT141 local routine parameter modes require generic template artifact format 19"]
					Return
				End If
			Next
		End If
		If value.kind = TEMPLATE_NODE_ARRAY_LENGTH And value.children.length <> 1 Then
			diagnostics :+ ["BMXGT133 managed array length requires one receiver child"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_ARRAY_ELEMENT Then
			If documentVersion < 22 And value.children.length <> 2 Then
				diagnostics :+ ["BMXGT133 managed array element access requires receiver and index children"]
				Return
			End If
			If documentVersion >= 22 And value.children.length < 2 Then
				diagnostics :+ ["BMXGT142 managed or StaticArray element access requires a receiver and at least one index"]
				Return
			End If
		End If
		If value.kind = TEMPLATE_NODE_ARRAY_SLICE And value.children.length <> 3 Then
			diagnostics :+ ["BMXGT134 managed array slicing requires receiver, lower-bound, and upper-bound children"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT And value.children.length <> 1 Then
			diagnostics :+ ["BMXGT135 expression statement requires one expression child"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_THROW And value.children.length <> 1 Then
			diagnostics :+ ["BMXGT136 Throw statement requires one expression child"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_ASSERT And (value.children.length < 1 Or value.children.length > 2) Then
			diagnostics :+ ["BMXGT137 Assert statement requires a condition and optional message"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_RELEASE And value.children.length <> 1 Then
			diagnostics :+ ["BMXGT143 Release statement requires one addressable integer expression"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_YIELD And ((documentVersion < 32 And value.children.length <> 1) Or (documentVersion >= 32 And (value.children.length < 1 Or value.children.length > 2))) Then
			diagnostics :+ ["BMXGT144 Yield statement requires one expression and an optional cleanup-edge record"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_YIELD And value.children.length = 2 And (value.children[1].kind <> TEMPLATE_NODE_BLOCK Or value.children[1].valueText <> "cleanup-edges") Then
			diagnostics :+ ["BMXGT144 Yield cleanup metadata requires a cleanup-edge block"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_SELECT And Not value.children.length Then
			diagnostics :+ ["BMXGT139 Select statement requires a selector child"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_ARRAY_LITERAL And (Not value.semanticType Or value.semanticType.kind <> TEMPLATE_TYPE_ARRAY) Then
			diagnostics :+ ["BMXGT139 managed Array literal requires its bound Array type"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_TRY Then
			If value.valueText <> "finally" And value.valueText <> "catch" And value.valueText <> "catch-finally" Then
				diagnostics :+ ["BMXGT139 Try node has an invalid routing identity"]
				Return
			End If
			If value.children.length < 2 Or value.children[0].kind <> TEMPLATE_NODE_BLOCK Then
				diagnostics :+ ["BMXGT139 Try node requires a protected body and routing records"]
				Return
			End If
			Local catchCount:Int
			Local finallyCount:Int
			For Local childIndex:Int = 1 Until value.children.length
				Local child:TGenericTemplateNode = value.children[childIndex]
				If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "catch-clause" And child.children.length = 2 And child.children[0].kind = TEMPLATE_NODE_DECLARATION And child.children[0].identity = "catch-parameter" And child.children[1].kind = TEMPLATE_NODE_BLOCK Then
					catchCount :+ 1
				Else If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "finally-body" And child.children.length = 1 And child.children[0].kind = TEMPLATE_NODE_BLOCK Then
					finallyCount :+ 1
				Else If value.valueText = "finally" And value.children.length = 2 And child And child.kind = TEMPLATE_NODE_BLOCK Then
					' Format 20's protected/finally pair remains a valid
					' read-only shape in current artifacts.
					finallyCount :+ 1
				Else
					diagnostics :+ ["BMXGT139 Try node contains an invalid Catch or Finally record"]
					Return
				End If
			Next
			If (value.valueText = "catch" And (Not catchCount Or finallyCount)) Or (value.valueText = "finally" And (catchCount Or finallyCount <> 1)) Or (value.valueText = "catch-finally" And (Not catchCount Or finallyCount <> 1)) Then
				diagnostics :+ ["BMXGT139 Try routing identity does not match its Catch and Finally records"]
				Return
			End If
		End If
		If value.kind = TEMPLATE_NODE_DATA Then
			If value.identity <> "define" And value.identity <> "read" And value.identity <> "restore" Then
				diagnostics :+ ["BMXGT141 Data node has an invalid operation identity"]
				Return
			End If
			If (value.identity = "define" Or value.identity = "restore") And Not value.valueText.length Then
				diagnostics :+ ["BMXGT141 Data definition or restore requires a stable definition identity"]
				Return
			End If
			If value.identity = "restore" And value.children.length Then
				diagnostics :+ ["BMXGT141 RestoreData cannot carry value children"]
				Return
			End If
			If value.identity = "read" Then
				For Local target:TGenericTemplateNode = EachIn value.children
					If Not target Or target.kind <> TEMPLATE_NODE_BLOCK Or target.children.length <> 1 Then
						diagnostics :+ ["BMXGT141 ReadData target has an invalid conversion/address record"]
						Return
					End If
				Next
			End If
		End If
		If value.kind = TEMPLATE_NODE_USING And (value.children.length < 2 Or value.children[value.children.length - 1].kind <> TEMPLATE_NODE_BLOCK) Then
			diagnostics :+ ["BMXGT139 Using requires resource records and a body"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_SELF And value.valueText <> "self" And value.valueText <> "super" Then
			diagnostics :+ ["BMXGT132 Self/Super receiver node has invalid identity '" + value.valueText + "'"]
			Return
		End If
		If value.kind = TEMPLATE_NODE_SELF And Not value.semanticType Then
			diagnostics :+ ["BMXGT132 Self/Super receiver node requires its bound semantic type"]
			Return
		End If
		If documentVersion >= 5 And (value.kind = TEMPLATE_NODE_LOOP Or value.kind = TEMPLATE_NODE_LOOP_CONTROL) And Not value.identity.length Then
			diagnostics :+ ["BMXGT124 generic loop and loop-control nodes require semantic identity"]
			Return
		End If
		If value.runtimeDispatchKind < TEMPLATE_DISPATCH_NONE Or value.runtimeDispatchKind > TEMPLATE_DISPATCH_ORDINARY_CLASS Then
			diagnostics :+ ["BMXGT131 unknown template runtime dispatch kind " + value.runtimeDispatchKind]
			Return
		End If
		If value.runtimeDispatchKind = TEMPLATE_DISPATCH_NONE And value.runtimeDispatchIndex <> -1 Then
			diagnostics :+ ["BMXGT131 absent template runtime dispatch carries a slot ordinal"]
			Return
		End If
		If value.runtimeDispatchKind <> TEMPLATE_DISPATCH_NONE And (value.kind <> TEMPLATE_NODE_CALL Or value.runtimeDispatchIndex < 0) Then
			diagnostics :+ ["BMXGT131 ordinary class dispatch requires a call node and non-negative runtime slot ordinal"]
			Return
		End If
		If value.runtimeDispatchKind <> TEMPLATE_DISPATCH_NONE And documentVersion < 8 Then
			diagnostics :+ ["BMXGT131 ordinary class dispatch requires generic template artifact format 8"]
			Return
		End If
		Line("node")
		IntValue(value.kind)
		WriteOptionalType(value.semanticType, depth + 1)
		If value.referencedSymbol Then IntValue(1); WriteSymbol(value.referencedSymbol) Else IntValue(0)
		WriteSource(value.source)
		StringValue(value.valueText)
		If documentVersion >= 5 Then StringValue(value.identity)
		If documentVersion >= 8 Then
			IntValue(value.runtimeDispatchKind)
			IntValue(value.runtimeDispatchIndex)
		End If
		Line("children " + value.children.length)
		For Local child:TGenericTemplateNode = EachIn value.children
			WriteNode(child, depth + 1)
		Next
	End Method
End Type

Type TGenericTemplateRecordReader
	Field lines:String[]
	Field index:Int
	Field documentVersion:Int
	Field diagnostics:String[] = New String[0]

	Method Fail(message:String)
		If Not diagnostics.length Then diagnostics :+ [message]
	End Method

	Method ReadLine:String(expected:String = "")
		If diagnostics.length Then Return ""
		If index >= lines.length Then Fail("BMXGT111 unexpected end of generic template artifact"); Return ""
		Local value:String = lines[index]
		index :+ 1
		If expected.length And value <> expected Then Fail("BMXGT112 expected '" + expected + "' but found '" + value + "'")
		Return value
	End Method

	Method ReadString:String()
		Local line:String = ReadLine()
		If diagnostics.length Then Return ""
		If Not line.StartsWith("s ") Then Fail("BMXGT113 expected encoded string record"); Return ""
		Try
			Local bytes:Byte[] = TBase64.Decode(line[2..])
			Return String.FromUTF8Bytes(bytes, bytes.length)
		Catch exception:Object
			Fail("BMXGT113 malformed encoded string record")
			Return ""
		End Try
	End Method

	Method ReadInt:Int()
		Local line:String = ReadLine()
		If diagnostics.length Then Return 0
		If Not line.StartsWith("i ") Or Not IsInteger(line[2..]) Then Fail("BMXGT114 expected integer record"); Return 0
		Return Int(line[2..])
	End Method

	Method ReadLong:Long()
		Local line:String = ReadLine()
		If diagnostics.length Then Return 0
		If Not line.StartsWith("l ") Or Not IsInteger(line[2..]) Then Fail("BMXGT128 expected long integer record"); Return 0
		Return Long(line[2..])
	End Method

	Method ReadCount:Int(tag:String)
		Local line:String = ReadLine()
		If diagnostics.length Then Return 0
		Local prefix:String = tag + " "
		If Not line.StartsWith(prefix) Or Not IsInteger(line[prefix.length..]) Then Fail("BMXGT115 expected '" + tag + "' count"); Return 0
		Local result:Int = Int(line[prefix.length..])
		If result < 0 Or result > GENERIC_TEMPLATE_ARTIFACT_MAX_RECORDS Then Fail("BMXGT116 '" + tag + "' count is outside artifact bounds"); Return 0
		Return result
	End Method

	Method ReadArtifact:TGenericTemplateArtifact()
		ReadLine("artifact")
		Local artifact:TGenericTemplateArtifact = New TGenericTemplateArtifact
		artifact.formatVersion = ReadInt()
		If artifact.formatVersion <> documentVersion Or artifact.formatVersion < GENERIC_TEMPLATE_MIN_READ_VERSION Or artifact.formatVersion > GENERIC_TEMPLATE_FORMAT_VERSION Then Fail("BMXGT101 unsupported generic template artifact version " + artifact.formatVersion)
		artifact.identity = New TGenericTemplateIdentity
		artifact.identity.moduleName = ReadString()
		artifact.identity.qualifiedName = ReadString()
		artifact.identity.arity = ReadInt()
		artifact.identity.declarationKind = ReadInt()
		If artifact.identity.declarationKind <> GENERIC_DECLARATION_TYPE And artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Fail("BMXGT118 unknown generic template declaration kind " + artifact.identity.declarationKind)
		If documentVersion >= 13 Then artifact.identity.signatureKey = ReadString()
		If documentVersion >= 13 And artifact.identity.declarationKind = GENERIC_DECLARATION_ROUTINE And Not artifact.identity.signatureKey.length Then Fail("BMXGT137 generic routine artifact requires an open signature identity")
		If documentVersion >= 13 And artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE And artifact.identity.signatureKey.length Then Fail("BMXGT137 non-routine template carries an open signature identity")
		artifact.languageLinkageRevision = ReadString()
		artifact.storageKind = ReadInt()
		If artifact.storageKind <> TEMPLATE_ARTIFACT_STORAGE_CANONICAL And artifact.storageKind <> TEMPLATE_ARTIFACT_STORAGE_LEGACY_BRIDGE Then Fail("BMXGT119 unknown generic template storage kind " + artifact.storageKind)
		artifact.cacheable = ReadInt()
		If artifact.cacheable <> 0 And artifact.cacheable <> 1 Then Fail("BMXGT120 invalid generic template cacheable flag")
		If documentVersion >= 3 Then artifact.typeDeclarationKind = ReadInt()
		If artifact.typeDeclarationKind < GENERIC_TYPE_DECLARATION_CLASS Or artifact.typeDeclarationKind > GENERIC_TYPE_DECLARATION_STRUCT Then Fail("BMXGT127 unknown generic template Type declaration kind " + artifact.typeDeclarationKind)
		If documentVersion >= 26 Then
			artifact.visibility = ReadInt()
			If artifact.visibility < 0 Or artifact.visibility > 6 Then Fail("BMXGT145 invalid generic Type visibility")
			artifact.isAbstract = ReadInt()
			If artifact.isAbstract <> 0 And artifact.isAbstract <> 1 Then Fail("BMXGT145 invalid generic abstract-Type flag")
			artifact.metadata = ReadMetadata("artifact-metadata")
		End If
		If documentVersion >= 13 Then
			artifact.isMethod = ReadInt()
			If artifact.isMethod <> 0 And artifact.isMethod <> 1 Then Fail("BMXGT137 invalid generic method flag")
			If artifact.isMethod And artifact.identity.declarationKind <> GENERIC_DECLARATION_ROUTINE Then Fail("BMXGT137 generic method flag requires a routine artifact")
			Local containingParameterCount:Int = ReadCount("containing-parameters")
			artifact.containingParameters = New TGenericTemplateParameter[containingParameterCount]
			For Local containingParameterIndex:Int = 0 Until containingParameterCount
				artifact.containingParameters[containingParameterIndex] = ReadParameter()
			Next
			artifact.containingType = ReadOptionalType(0)
			If artifact.isMethod And Not artifact.containingType Then Fail("BMXGT137 generic method artifact requires a containing Type")
			If Not artifact.isMethod And (artifact.containingParameters.length Or artifact.containingType) Then Fail("BMXGT137 non-method routine carries containing-Type identity")
			If documentVersion >= 14 Then artifact.containingFields = ReadMembers("containing-members")
		End If
		Local parameterCount:Int = ReadCount("parameters")
		artifact.parameters = New TGenericTemplateParameter[parameterCount]
		For Local parameterIndex:Int = 0 Until parameterCount
			artifact.parameters[parameterIndex] = ReadParameter()
		Next
		If documentVersion >= 2 Then
			artifact.baseType = ReadOptionalInheritance(0)
			Local interfaceCount:Int = ReadCount("interfaces")
			artifact.interfaces = New TGenericTemplateInheritanceReference[interfaceCount]
			For Local interfaceIndex:Int = 0 Until interfaceCount
				artifact.interfaces[interfaceIndex] = ReadInheritance(0)
			Next
		End If
		Local apiCount:Int = ReadCount("apis")
		artifact.referencedApis = New TTemplateSymbolReference[apiCount]
		For Local apiIndex:Int = 0 Until apiCount
			artifact.referencedApis[apiIndex] = ReadSymbol()
		Next
		artifact.members = ReadMembers("members")
		If documentVersion < 24 And artifact.typeDeclarationKind = GENERIC_TYPE_DECLARATION_INTERFACE Then
			For Local member:TGenericTemplateMember = EachIn artifact.members
				If member And member.kind = TEMPLATE_MEMBER_METHOD Then member.interfaceMethodKind = TEMPLATE_INTERFACE_METHOD_ABSTRACT
			Next
		End If
		artifact.body = ReadOptionalNode(0)
		ReadLine("end-artifact")
		If index < lines.length
			For Local trailingIndex:Int = index Until lines.length
				If lines[trailingIndex].length Then Fail("BMXGT117 trailing records follow the generic template artifact")
			Next
		End If
		If diagnostics.length Then Return Null
		Return artifact
	End Method

	Method ReadMembers:TGenericTemplateMember[](label:String)
		Local memberCount:Int = ReadCount(label)
		Local members:TGenericTemplateMember[] = New TGenericTemplateMember[memberCount]
		For Local memberIndex:Int = 0 Until memberCount
			ReadLine("member")
			Local member:TGenericTemplateMember = New TGenericTemplateMember
			member.kind = ReadInt()
			If member.kind <> TEMPLATE_MEMBER_FIELD And member.kind <> TEMPLATE_MEMBER_METHOD Then Fail("BMXGT121 unknown generic template member kind " + member.kind)
			member.identity = ReadString()
			member.name = ReadString()
			If documentVersion >= 24 Then
				member.interfaceMethodKind = ReadInt()
				If member.interfaceMethodKind < TEMPLATE_INTERFACE_METHOD_NONE Or member.interfaceMethodKind > TEMPLATE_INTERFACE_METHOD_REABSTRACT Then Fail("BMXGT144 invalid Interface method implementation kind")
				If member.interfaceMethodKind And member.kind <> TEMPLATE_MEMBER_METHOD Then Fail("BMXGT144 only method-shaped template members may carry an Interface implementation kind")
			End If
			If documentVersion >= 23 Then
				member.isStatic = ReadInt()
				If member.isStatic <> 0 And member.isStatic <> 1 Then Fail("BMXGT143 invalid static template-member flag")
				If member.isStatic And member.kind <> TEMPLATE_MEMBER_FIELD And member.kind <> TEMPLATE_MEMBER_METHOD Then Fail("BMXGT143 only field- or routine-shaped template members may be static")
			End If
			If documentVersion >= 30 Then
				member.isTypeFunction = ReadInt()
				If member.isTypeFunction <> 0 And member.isTypeFunction <> 1 Then Fail("BMXGT146 invalid Type Function template-member flag")
				If member.isTypeFunction And member.kind <> TEMPLATE_MEMBER_METHOD Then Fail("BMXGT146 only method-shaped template members may be Type Functions")
			End If
			If documentVersion >= 15 Then member.linkageName = ReadString()
			member.visibility = ReadInt()
			If documentVersion >= 26 Then member.metadata = ReadMetadata("member-metadata")
			member.semanticType = ReadOptionalType(0)
			Local valueParameterCount:Int = ReadCount("value-parameters")
			member.parameters = New TGenericTemplateValueParameter[valueParameterCount]
			For Local parameterIndex:Int = 0 Until valueParameterCount
				ReadLine("value-parameter")
				Local parameter:TGenericTemplateValueParameter = New TGenericTemplateValueParameter
				parameter.name = ReadString()
				parameter.ordinal = ReadInt()
				parameter.semanticType = ReadOptionalType(0)
				parameter.passingMode = ReadInt()
				If documentVersion >= 18 Then
					parameter.optional = ReadInt()
					If parameter.optional <> 0 And parameter.optional <> 1 Then Fail("BMXGT140 invalid optional value-parameter flag")
					parameter.defaultValue = ReadOptionalNode(0)
					If parameter.optional And Not parameter.defaultValue Then Fail("BMXGT140 optional value parameter '" + parameter.name + "' requires a retained default expression")
					If Not parameter.optional And parameter.defaultValue Then Fail("BMXGT140 non-optional value parameter '" + parameter.name + "' carries a default expression")
				End If
				parameter.source = ReadSource()
				member.parameters[parameterIndex] = parameter
			Next
			member.body = ReadOptionalNode(0)
			member.source = ReadSource()
			members[memberIndex] = member
		Next
		Return members
	End Method

	Method ReadMetadata:TGenericTemplateMetadataEntry[](label:String)
		Local count:Int = ReadCount(label)
		Local result:TGenericTemplateMetadataEntry[] = New TGenericTemplateMetadataEntry[count]
		For Local index:Int = 0 Until count
			ReadLine("metadata")
			Local entry:TGenericTemplateMetadataEntry = New TGenericTemplateMetadataEntry
			entry.key = ReadString()
			entry.value = ReadString()
			entry.source = ReadSource()
			If Not entry.key.length Then Fail("BMXGT145 invalid generic reflection metadata entry")
			result[index] = entry
		Next
		Return result
	End Method

	Method ReadParameter:TGenericTemplateParameter()
		ReadLine("parameter")
		Local parameter:TGenericTemplateParameter = New TGenericTemplateParameter
		parameter.name = ReadString()
		parameter.ordinal = ReadInt()
		Local constraintCount:Int = ReadCount("constraints")
		parameter.constraints = New TTemplateTypeReference[constraintCount]
		For Local constraintIndex:Int = 0 Until constraintCount
			parameter.constraints[constraintIndex] = ReadType(0)
		Next
		Return parameter
	End Method

	Method ReadOptionalInheritance:TGenericTemplateInheritanceReference(depth:Int)
		If ReadPresence() Then Return ReadInheritance(depth)
		Return Null
	End Method

	Method ReadInheritance:TGenericTemplateInheritanceReference(depth:Int)
		ReadLine("inheritance")
		Local result:TGenericTemplateInheritanceReference = New TGenericTemplateInheritanceReference
		result.semanticType = ReadType(depth)
		result.source = ReadSource()
		If Not result.semanticType Then Fail("BMXGT126 invalid generic template inheritance reference")
		Return result
	End Method

	Method ReadOptionalType:TTemplateTypeReference(depth:Int)
		If ReadPresence() Then Return ReadType(depth)
		Return Null
	End Method

	Method ReadType:TTemplateTypeReference(depth:Int)
		If depth > GENERIC_TEMPLATE_ARTIFACT_MAX_DEPTH Then Fail("BMXGT108 excessively nested template type reference"); Return Null
		ReadLine("type")
		Local value:TTemplateTypeReference = New TTemplateTypeReference
		value.kind = ReadInt()
		Local maximumKind:Int = TEMPLATE_TYPE_ARRAY
		If documentVersion >= 6 Then maximumKind = TEMPLATE_TYPE_STATIC_ARRAY
		If documentVersion >= 21 Then maximumKind = TEMPLATE_TYPE_CALLABLE
		If documentVersion >= 27 Then maximumKind = TEMPLATE_TYPE_CLOSURE
		If value.kind < TEMPLATE_TYPE_BUILTIN Or value.kind > maximumKind Then Fail("BMXGT122 unknown generic template type kind " + value.kind)
		value.moduleName = ReadString()
		value.symbolName = ReadString()
		value.parameterIndex = ReadInt()
		value.parameterOwner = ReadInt()
		value.rank = ReadInt()
		If documentVersion >= 6 Then value.staticArrayLength = ReadLong()
		If documentVersion >= 7 Then
			value.runtimeKind = ReadInt()
			value.runtimeAbiName = ReadString()
		End If
		If value.kind = TEMPLATE_TYPE_STATIC_ARRAY And value.staticArrayLength <= 0 Then Fail("BMXGT129 StaticArray template type requires a positive fixed extent")
		If value.kind <> TEMPLATE_TYPE_STATIC_ARRAY And value.staticArrayLength <> 0 Then Fail("BMXGT129 non-StaticArray template type carries a fixed extent")
		If documentVersion >= 18 Then value.runtimeValueType = ReadString()
		If value.runtimeKind < TEMPLATE_RUNTIME_NONE Or value.runtimeKind > TEMPLATE_RUNTIME_ENUM Then Fail("BMXGT130 unknown ordinary runtime type identity kind " + value.runtimeKind)
		If value.runtimeKind <> TEMPLATE_RUNTIME_NONE And value.kind <> TEMPLATE_TYPE_NAMED Then Fail("BMXGT130 ordinary runtime identity requires a named template type")
		If value.runtimeKind = TEMPLATE_RUNTIME_NONE And value.runtimeAbiName.length Then Fail("BMXGT130 ordinary runtime linkage name requires a runtime identity kind")
		If value.runtimeKind = TEMPLATE_RUNTIME_STRUCT And documentVersion < 14 Then Fail("BMXGT138 ordinary Struct runtime identity requires generic template artifact format 14")
		If value.runtimeKind = TEMPLATE_RUNTIME_ENUM And (documentVersion < 18 Or Not TGenericTemplateArtifactCodec.IsEnumValueType(value.runtimeValueType)) Then Fail("BMXGT140 ordinary Enum runtime identity requires a supported integral value type in artifact format 18")
		If value.runtimeKind <> TEMPLATE_RUNTIME_ENUM And value.runtimeValueType.length Then Fail("BMXGT140 non-Enum runtime identity carries an Enum value type")
		value.elementType = ReadOptionalType(depth + 1)
		Local argumentCount:Int = ReadCount("arguments")
		value.arguments = New TTemplateTypeReference[argumentCount]
		For Local argumentIndex:Int = 0 Until argumentCount
			value.arguments[argumentIndex] = ReadType(depth + 1)
		Next
		If value.runtimeKind <> TEMPLATE_RUNTIME_NONE And Not value.runtimeAbiName.length And (documentVersion < 28 Or Not value.arguments.length) Then Fail("BMXGT130 ordinary runtime identity requires a stable language-linkage name; only constructed generic runtime categories may defer their specialization ABI")
		If documentVersion >= 21 Then
			Local modeCount:Int = ReadCount("callable-modes")
			value.callableParameterModes = New Int[modeCount]
			For Local modeIndex:Int = 0 Until modeCount
				value.callableParameterModes[modeIndex] = ReadInt()
				If value.callableParameterModes[modeIndex] <> GENERIC_TEMPLATE_PARAMETER_PASS_VALUE And value.callableParameterModes[modeIndex] <> GENERIC_TEMPLATE_PARAMETER_PASS_VAR Then Fail("BMXGT141 callable template type has an unknown parameter mode")
			Next
			If (value.kind = TEMPLATE_TYPE_CALLABLE Or value.kind = TEMPLATE_TYPE_CLOSURE) And modeCount <> argumentCount Then Fail("BMXGT141 callable template type parameter modes do not match its parameter types")
			If value.kind <> TEMPLATE_TYPE_CALLABLE And value.kind <> TEMPLATE_TYPE_CLOSURE And modeCount Then Fail("BMXGT141 non-callable template type carries callable parameter modes")
			If (value.kind = TEMPLATE_TYPE_CALLABLE Or value.kind = TEMPLATE_TYPE_CLOSURE) And Not value.elementType Then Fail("BMXGT141 callable template type requires a return type")
		End If
		If documentVersion >= 27 Then
			Local nameCount:Int = ReadCount("callable-names")
			value.callableParameterNames = New String[nameCount]
			For Local nameIndex:Int = 0 Until nameCount
				value.callableParameterNames[nameIndex] = ReadString()
			Next
			If value.kind = TEMPLATE_TYPE_CLOSURE And nameCount <> argumentCount Then Fail("BMXGT142 Closure template type parameter names do not match its parameter types")
			If value.kind <> TEMPLATE_TYPE_CLOSURE And nameCount Then Fail("BMXGT142 non-Closure template type carries Closure parameter names")
		End If
		Return value
	End Method

	Method ReadSymbol:TTemplateSymbolReference()
		ReadLine("symbol")
		Local value:TTemplateSymbolReference = New TTemplateSymbolReference
		value.moduleName = ReadString()
		value.qualifiedName = ReadString()
		value.namespaceKind = ReadInt()
		value.overloadKey = ReadString()
		Return value
	End Method

	Method ReadSource:TTemplateSourceLocation()
		If Not ReadPresence() Then Return Null
		ReadLine("source")
		Local value:TTemplateSourceLocation = New TTemplateSourceLocation
		value.path = ReadString()
		value.start = ReadInt()
		value.length = ReadInt()
		If documentVersion >= 26 Then
			value.line = ReadInt()
			value.column = ReadInt()
		End If
		If value.start < 0 Or value.length < 0 Then Fail("BMXGT123 invalid generic template source span")
		If value.line < 0 Or value.column < 0 Then Fail("BMXGT123 invalid generic template source position")
		Return value
	End Method

	Method ReadOptionalNode:TGenericTemplateNode(depth:Int)
		If ReadPresence() Then Return ReadNode(depth)
		Return Null
	End Method

	Method ReadNode:TGenericTemplateNode(depth:Int)
		If depth > GENERIC_TEMPLATE_ARTIFACT_MAX_DEPTH Then Fail("BMXGT110 excessively nested template body node"); Return Null
		ReadLine("node")
		Local value:TGenericTemplateNode = New TGenericTemplateNode
		value.kind = ReadInt()
		Local maximumNodeKind:Int = TEMPLATE_NODE_DATA
		If documentVersion >= 27 Then maximumNodeKind = TEMPLATE_NODE_FUNCTION_LITERAL
		If documentVersion >= 29 Then maximumNodeKind = TEMPLATE_NODE_RELEASE
		If documentVersion >= 31 Then maximumNodeKind = TEMPLATE_NODE_YIELD
		If value.kind < TEMPLATE_NODE_BLOCK Or value.kind > maximumNodeKind Then Fail("BMXGT124 unknown generic template body node kind " + value.kind)
		If value.kind = TEMPLATE_NODE_CONSTRUCTOR_DELEGATION And documentVersion < 4 Then Fail("BMXGT124 constructor delegation requires generic template artifact format 4")
		If value.kind = TEMPLATE_NODE_LOOP_CONTROL And documentVersion < 5 Then Fail("BMXGT124 loop control requires generic template artifact format 5")
		If value.kind = TEMPLATE_NODE_SELF And documentVersion < 9 Then Fail("BMXGT132 Self/Super receiver identity requires generic template artifact format 9")
		If (value.kind = TEMPLATE_NODE_ARRAY_LENGTH Or value.kind = TEMPLATE_NODE_ARRAY_ELEMENT) And documentVersion < 10 Then Fail("BMXGT133 managed array operations require generic template artifact format 10")
		If value.kind = TEMPLATE_NODE_ARRAY_SLICE And documentVersion < 11 Then Fail("BMXGT134 managed array slicing requires generic template artifact format 11")
		If value.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT And documentVersion < 12 Then Fail("BMXGT135 expression statements require generic template artifact format 12")
		If value.kind = TEMPLATE_NODE_ASSERT And documentVersion < 16 Then Fail("BMXGT137 Assert statements require generic template artifact format 16")
		If (value.kind = TEMPLATE_NODE_SELECT Or value.kind = TEMPLATE_NODE_ARRAY_LITERAL Or value.kind = TEMPLATE_NODE_TRY Or value.kind = TEMPLATE_NODE_USING) And documentVersion < 20 Then Fail("BMXGT139 Select, managed Array literal, Try, and Using nodes require generic template artifact format 20")
		If value.kind = TEMPLATE_NODE_DATA And documentVersion < 21 Then Fail("BMXGT141 Data nodes require generic template artifact format 21")
		If value.kind = TEMPLATE_NODE_FUNCTION_LITERAL And documentVersion < 27 Then Fail("BMXGT142 Function literals require generic template artifact format 27")
		If value.kind = TEMPLATE_NODE_RELEASE And documentVersion < 29 Then Fail("BMXGT143 Release statements require generic template artifact format 29")
		If value.kind = TEMPLATE_NODE_YIELD And documentVersion < 31 Then Fail("BMXGT144 Yield statements require generic template artifact format 31")
		If value.kind = TEMPLATE_NODE_TRY And value.valueText <> "finally" And documentVersion < 21 Then Fail("BMXGT141 Try/Catch routing requires generic template artifact format 21")
		value.semanticType = ReadOptionalType(depth + 1)
		If ReadPresence() Then value.referencedSymbol = ReadSymbol()
		value.source = ReadSource()
		value.valueText = ReadString()
		If documentVersion >= 5 Then value.identity = ReadString()
		If documentVersion >= 8 Then
			value.runtimeDispatchKind = ReadInt()
			value.runtimeDispatchIndex = ReadInt()
		End If
		If documentVersion >= 5 And (value.kind = TEMPLATE_NODE_LOOP Or value.kind = TEMPLATE_NODE_LOOP_CONTROL) And Not value.identity.length Then Fail("BMXGT124 generic loop and loop-control nodes require semantic identity")
		Local localRoutineRecord:Int = value.kind = TEMPLATE_NODE_BLOCK And (value.valueText = "local-routine-signature" Or value.valueText = "local-routine-reference")
		If localRoutineRecord And documentVersion < 17 Then Fail("BMXGT138 local routine records require generic template artifact format 17")
		If localRoutineRecord And Not value.identity.length Then Fail("BMXGT138 local routine records require a stable semantic identity")
		If value.kind = TEMPLATE_NODE_SELF And value.valueText <> "self" And value.valueText <> "super" Then Fail("BMXGT132 Self/Super receiver node has invalid identity '" + value.valueText + "'")
		If value.kind = TEMPLATE_NODE_SELF And Not value.semanticType Then Fail("BMXGT132 Self/Super receiver node requires its bound semantic type")
		If value.runtimeDispatchKind < TEMPLATE_DISPATCH_NONE Or value.runtimeDispatchKind > TEMPLATE_DISPATCH_ORDINARY_CLASS Then Fail("BMXGT131 unknown template runtime dispatch kind " + value.runtimeDispatchKind)
		If value.runtimeDispatchKind = TEMPLATE_DISPATCH_NONE And value.runtimeDispatchIndex <> -1 Then Fail("BMXGT131 absent template runtime dispatch carries a slot ordinal")
		If value.runtimeDispatchKind <> TEMPLATE_DISPATCH_NONE And (value.kind <> TEMPLATE_NODE_CALL Or value.runtimeDispatchIndex < 0) Then Fail("BMXGT131 ordinary class dispatch requires a call node and non-negative runtime slot ordinal")
		Local childCount:Int = ReadCount("children")
		value.children = New TGenericTemplateNode[childCount]
		For Local childIndex:Int = 0 Until childCount
			value.children[childIndex] = ReadNode(depth + 1)
		Next
		If value.kind = TEMPLATE_NODE_ARRAY_LENGTH And value.children.length <> 1 Then Fail("BMXGT133 managed array length requires one receiver child")
		If value.kind = TEMPLATE_NODE_ARRAY_ELEMENT Then
			If documentVersion < 22 And value.children.length <> 2 Then Fail("BMXGT133 managed array element access requires receiver and index children")
			If documentVersion >= 22 And value.children.length < 2 Then Fail("BMXGT142 managed or StaticArray element access requires a receiver and at least one index")
		End If
		If value.kind = TEMPLATE_NODE_ARRAY_SLICE And value.children.length <> 3 Then Fail("BMXGT134 managed array slicing requires receiver, lower-bound, and upper-bound children")
		If value.kind = TEMPLATE_NODE_EXPRESSION_STATEMENT And value.children.length <> 1 Then Fail("BMXGT135 expression statement requires one expression child")
		If value.kind = TEMPLATE_NODE_THROW And value.children.length <> 1 Then Fail("BMXGT136 Throw statement requires one expression child")
		If value.kind = TEMPLATE_NODE_ASSERT And (value.children.length < 1 Or value.children.length > 2) Then Fail("BMXGT137 Assert statement requires a condition and optional message")
		If value.kind = TEMPLATE_NODE_RELEASE And value.children.length <> 1 Then Fail("BMXGT143 Release statement requires one addressable integer expression")
		If value.kind = TEMPLATE_NODE_YIELD And ((documentVersion < 32 And value.children.length <> 1) Or (documentVersion >= 32 And (value.children.length < 1 Or value.children.length > 2))) Then Fail("BMXGT144 Yield statement requires one expression and an optional cleanup-edge record")
		If value.kind = TEMPLATE_NODE_YIELD And value.children.length = 2 And (value.children[1].kind <> TEMPLATE_NODE_BLOCK Or value.children[1].valueText <> "cleanup-edges") Then Fail("BMXGT144 Yield cleanup metadata requires a cleanup-edge block")
		If value.kind = TEMPLATE_NODE_SELECT And Not value.children.length Then Fail("BMXGT139 Select statement requires a selector child")
		If value.kind = TEMPLATE_NODE_ARRAY_LITERAL And (Not value.semanticType Or value.semanticType.kind <> TEMPLATE_TYPE_ARRAY) Then Fail("BMXGT139 managed Array literal requires its bound Array type")
		If value.kind = TEMPLATE_NODE_TRY Then
			If value.valueText <> "finally" And value.valueText <> "catch" And value.valueText <> "catch-finally" Then Fail("BMXGT139 Try node has an invalid routing identity")
			If value.children.length < 2 Or value.children[0].kind <> TEMPLATE_NODE_BLOCK Then Fail("BMXGT139 Try node requires a protected body and routing records")
			Local catchCount:Int
			Local finallyCount:Int
			For Local childIndex:Int = 1 Until value.children.length
				Local child:TGenericTemplateNode = value.children[childIndex]
				If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "catch-clause" And child.children.length = 2 And child.children[0].kind = TEMPLATE_NODE_DECLARATION And child.children[0].identity = "catch-parameter" And child.children[1].kind = TEMPLATE_NODE_BLOCK Then
					catchCount :+ 1
				Else If child And child.kind = TEMPLATE_NODE_BLOCK And child.valueText = "finally-body" And child.children.length = 1 And child.children[0].kind = TEMPLATE_NODE_BLOCK Then
					finallyCount :+ 1
				Else If value.valueText = "finally" And value.children.length = 2 And child And child.kind = TEMPLATE_NODE_BLOCK Then
					finallyCount :+ 1
				Else
					Fail("BMXGT139 Try node contains an invalid Catch or Finally record")
				End If
			Next
			If (value.valueText = "catch" And (Not catchCount Or finallyCount)) Or (value.valueText = "finally" And (catchCount Or finallyCount <> 1)) Or (value.valueText = "catch-finally" And (Not catchCount Or finallyCount <> 1)) Then Fail("BMXGT139 Try routing identity does not match its Catch and Finally records")
		End If
		If value.kind = TEMPLATE_NODE_DATA Then
			If value.identity <> "define" And value.identity <> "read" And value.identity <> "restore" Then Fail("BMXGT141 Data node has an invalid operation identity")
			If (value.identity = "define" Or value.identity = "restore") And Not value.valueText.length Then Fail("BMXGT141 Data definition or restore requires a stable definition identity")
			If value.identity = "restore" And value.children.length Then Fail("BMXGT141 RestoreData cannot carry value children")
			If value.identity = "read" Then
				For Local target:TGenericTemplateNode = EachIn value.children
					If Not target Or target.kind <> TEMPLATE_NODE_BLOCK Or target.children.length <> 1 Then Fail("BMXGT141 ReadData target has an invalid conversion/address record")
				Next
			End If
		End If
		If value.kind = TEMPLATE_NODE_USING And (value.children.length < 2 Or value.children[value.children.length - 1].kind <> TEMPLATE_NODE_BLOCK) Then Fail("BMXGT139 Using requires resource records and a body")
		If value.kind = TEMPLATE_NODE_BLOCK And value.valueText = "local-routine-signature" And (Not value.children.length Or value.children[value.children.length - 1].kind <> TEMPLATE_NODE_BLOCK) Then Fail("BMXGT138 local routine signatures require a semantic body block")
		If localRoutineRecord And documentVersion >= 19 Then
			Local parameterCount:Int = value.children.length
			If value.valueText = "local-routine-signature" Then parameterCount :- 1
			For Local index:Int = 0 Until parameterCount
				Local mode:Int = Int(value.children[index].identity)
				If mode <> GENERIC_TEMPLATE_PARAMETER_PASS_VALUE And mode <> GENERIC_TEMPLATE_PARAMETER_PASS_VAR Then Fail("BMXGT141 local routine parameter modes require generic template artifact format 19")
			Next
		End If
		Return value
	End Method

	Method ReadPresence:Int()
		Local value:Int = ReadInt()
		If value <> 0 And value <> 1 Then Fail("BMXGT125 invalid optional-record presence flag"); Return False
		Return value
	End Method

	Function IsInteger:Int(value:String)
		If Not value.length Then Return False
		Local start:Int
		If value[0] = Asc("-") Then start = 1
		If start = value.length Then Return False
		For Local index:Int = start Until value.length
			If value[index] < Asc("0") Or value[index] > Asc("9") Then Return False
		Next
		Return True
	End Function
End Type
