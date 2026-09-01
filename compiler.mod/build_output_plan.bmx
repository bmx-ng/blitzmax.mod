' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Base64
Import BRL.FileSystem
Import BlitzMax.Language
Import "compiler_diagnostic.bmx"
Import "generic_application_plan.bmx"
Import "ir_model.bmx"
Import "c_backend.bmx"
Import "interface_emitter.bmx"

Const COMPILER_BUILD_OUTPUT_VERSION:Int = 1

Extern
	Function bmx_compiler_temporary_output_path:String(publishedPath:String)
	Function bmx_compiler_atomic_replace:Int(temporaryPath:String, publishedPath:String)
End Extern

Type TCompilerBuildOutputFile
	Field role:String
	Field relativePath:String
	Field content:String
	Field contentDigest:String
	Field cacheKey:String
	Field semanticIdentity:String
End Type

Type TCompilerBuildOutputPlan
	Field files:TCompilerBuildOutputFile[] = New TCompilerBuildOutputFile[0]
	Field linkInputs:TCompilerGenericLinkInput[] = New TCompilerGenericLinkInput[0]
	Field manifest:String
	Field applicationMilliseconds:Int
	Field headerMilliseconds:Int
	Field interfaceMilliseconds:Int
	Field genericFilesMilliseconds:Int
	Field manifestMilliseconds:Int

	Method AddFile(file:TCompilerBuildOutputFile, diagnostics:TCompilerDiagnostic[] Var)
		If Not file Then Return
		If Not TCompilerBuildOutputPlanner.IsSafeRelativePath(file.relativePath) Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3060", "Generated output path must be a bounded relative path: '" + file.relativePath + "'")]
			Return
		End If
		For Local existing:TCompilerBuildOutputFile = EachIn files
			If existing.relativePath.ToLower() <> file.relativePath.ToLower() Then Continue
			If existing.contentDigest <> file.contentDigest Or existing.role <> file.role Then
				diagnostics :+ [TCompilerDiagnostic.Create("BMXC3061", "Generated output path collision for '" + file.relativePath + "'")]
			End If
			Return
		Next
		files :+ [file]
		SortFiles()
	End Method

	Method SortFiles()
		For Local index:Int = 1 Until files.length
			Local value:TCompilerBuildOutputFile = files[index]
			Local position:Int = index - 1
			While position >= 0 And files[position].relativePath.ToLower() > value.relativePath.ToLower()
				files[position + 1] = files[position]
				position :- 1
			Wend
			files[position + 1] = value
		Next
	End Method
End Type

Type TCompilerBuildMaterializationResult
	Field writtenPaths:String[] = New String[0]
	Field reusedPaths:String[] = New String[0]
	Field manifestPath:String
End Type

Type TCompilerBuildManifestFile
	Field role:String
	Field contentDigest:String
	Field cacheKey:String
	Field semanticIdentity:String
	Field relativePath:String
End Type

Type TCompilerBuildManifest
	Field files:TCompilerBuildManifestFile[] = New TCompilerBuildManifestFile[0]
	Field linkInputs:TCompilerGenericLinkInput[] = New TCompilerGenericLinkInput[0]
End Type

Type TCompilerBuildOutputPlanner
	Function Build:TCompilerBuildOutputPlan(analysis:TLanguageAnalysis, ir:TCompilerIrModule, genericPlan:TCompilerGenericApplicationPlan, applicationCPath:String, headerPath:String, interfacePath:String, diagnostics:TCompilerDiagnostic[] Var)
		Local plan:TCompilerBuildOutputPlan = New TCompilerBuildOutputPlan
		diagnostics = New TCompilerDiagnostic[0]
		If Not analysis Or Not analysis.Succeeded() Or Not ir Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3062", "Successful compiler IR is required before build-output planning")]
			Return plan
		End If
		' Application-owned ordinary Struct layouts can cross into a separate
		' specialization unit just like module-owned layouts.  Materialize a
		' companion runtime header on demand even when the caller did not request
		' one explicitly; otherwise the specialization would see only an
		' incomplete forward declaration for a by-value Struct.
		If Not headerPath.length And genericPlan Then
			For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
				If RequiresOwningRuntimeHeader(unit, analysis.model.moduleName) Then
					headerPath = StripExt(applicationCPath) + ".h"
					Exit
				End If
			Next
		End If

		Local backendDiagnostics:TCompilerDiagnostic[]
		Local runtimeHeaderContent:String
		Local runtimeHeaderDigest:String
		Local started:Int = MilliSecs()
		Local applicationContent:String
		If ir.targetPlatform.ToLower() = "pico" Then
			applicationContent = TCompilerCBackend.Emit(ir, backendDiagnostics)
		Else
			applicationContent = TCompilerCBackend.EmitRuntime(ir, backendDiagnostics)
		End If
		diagnostics :+ backendDiagnostics
		If Not backendDiagnostics.length Then
			plan.AddFile(CreateFile("application-c", applicationCPath, applicationContent), diagnostics)
		End If
		plan.applicationMilliseconds = MilliSecs() - started

		If headerPath.length Then
			started = MilliSecs()
			Local headerDiagnostics:TCompilerDiagnostic[]
			Local headerContent:String = TCompilerCBackend.EmitRuntimeHeader(ir, headerDiagnostics)
			diagnostics :+ headerDiagnostics
			If Not headerDiagnostics.length Then
				runtimeHeaderContent = headerContent
				runtimeHeaderDigest = TCompilerStableDigest.Sha256(headerContent)
				plan.AddFile(CreateFile("runtime-header", headerPath, headerContent), diagnostics)
			End If
			plan.headerMilliseconds = MilliSecs() - started
		End If

		If interfacePath.length Then
			started = MilliSecs()
			Local interfaceDiagnostics:TCompilerDiagnostic[]
			Local interfaceContent:String = TCompilerInterfaceEmitter.Emit(analysis, ir, interfaceDiagnostics, genericPlan)
			diagnostics :+ interfaceDiagnostics
			If Not interfaceDiagnostics.length Then
				plan.AddFile(CreateFile("interface", interfacePath, interfaceContent), diagnostics)
			End If
			plan.interfaceMilliseconds = MilliSecs() - started
		End If

		If genericPlan Then
			started = MilliSecs()
			Local coupledKeysByIdentity:TMap = New TMap
			For Local output:TCompilerGenericTemplateOutput = EachIn genericPlan.templateOutputs
				If Not output Or Not output.isPublished Then Continue
				Local artifactPath:String = output.artifactReference
				Local interfaceDirectory:String = ExtractDir(interfacePath.Replace("\", "/"))
				If interfaceDirectory.length Then artifactPath = interfaceDirectory + "/" + artifactPath
				Local file:TCompilerBuildOutputFile = CreateFile("generic-template", artifactPath, output.content)
				file.cacheKey = output.artifact.EffectiveContentRevision()
				file.semanticIdentity = output.artifact.identity.StableName()
				plan.AddFile(file, diagnostics)
			Next
			For Local unit:TCompilerGenericUnit = EachIn genericPlan.units
				If Not unit Or Not unit.specialization Then Continue
				Local implementation:String = unit.implementation
				Local cacheKey:String = unit.specialization.cacheKey
				If runtimeHeaderContent.length And headerPath.length And RequiresOwningRuntimeHeader(unit, analysis.model.moduleName) Then
					' The generated runtime header is the layout authority for
					' ordinary source Structs referenced by value from this
					' separate specialization translation unit.
					implementation = "#include ~q" + RelativeIncludePath(unit.specialization.generatedUnit, headerPath) + "~q~n" + implementation
					cacheKey = TCompilerStableDigest.Sha256(cacheKey + "|runtime-header=" + runtimeHeaderDigest)
				End If
				Local file:TCompilerBuildOutputFile = CreateFile("generic-specialization-c", unit.specialization.generatedUnit, implementation)
				file.cacheKey = cacheKey
				file.semanticIdentity = unit.specialization.identityDigest
				plan.AddFile(file, diagnostics)
				coupledKeysByIdentity.Insert(unit.specialization.identityDigest, cacheKey)
			Next
			For Local input:TCompilerGenericLinkInput = EachIn genericPlan.linkInputs
				If Not IsSafeRelativePath(input.sourcePath) Or Not IsSafeRelativePath(input.objectPath) Then
					diagnostics :+ [TCompilerDiagnostic.Create("BMXC3063", "Generic link input contains an unsafe generated path")]
					Continue
				End If
				Local plannedInput:TCompilerGenericLinkInput = New TCompilerGenericLinkInput
				plannedInput.specializationIdentity = input.specializationIdentity
				plannedInput.sourcePath = input.sourcePath
				plannedInput.objectPath = input.objectPath
				plannedInput.cacheKey = String(coupledKeysByIdentity.ValueForKey(input.specializationIdentity))
				If Not plannedInput.cacheKey.length Then plannedInput.cacheKey = input.cacheKey
				plan.linkInputs :+ [plannedInput]
			Next
			plan.genericFilesMilliseconds = MilliSecs() - started
		End If
		If Not diagnostics.length Then
			started = MilliSecs()
			plan.manifest = Manifest(plan)
			plan.manifestMilliseconds = MilliSecs() - started
		End If
		Return plan
	End Function

	Function RequiresOwningRuntimeHeader:Int(unit:TCompilerGenericUnit, currentModule:String)
		If Not unit Or Not unit.ir Then Return False
		' A direct generic routine declared on an ordinary Struct emits the
		' complete owner layout in its own unit.  Do not import the application
		' header merely for that receiver: doing so would give the same C struct
		' tag two definitions.  Other application-owned Structs used by the
		' routine still require the shared layout authority below.
		Local ownedRuntimeAbiName:String
		If unit.ir.isStruct And unit.ir.specialization Then
			' A generic Struct specialization emits its own complete closed layout.
			' Its method receiver must not be mistaken for a separate ordinary
			' application Struct requiring the desktop runtime-header authority.
			ownedRuntimeAbiName = unit.ir.specialization.readableAbiName
		End If
		If unit.ir.routine And unit.ir.routine.receiverIsStruct And unit.ir.routine.receiverType Then
			ownedRuntimeAbiName = unit.ir.routine.receiverType.runtimeAbiName
		End If
		For Local fieldRecord:TCompilerGenericFieldIr = EachIn unit.ir.fields
			If fieldRecord And RequiresOwningRuntimeLayout(fieldRecord.semanticType, currentModule, ownedRuntimeAbiName) Then Return True
		Next
		For Local fieldRecord:TCompilerGenericFieldIr = EachIn unit.ir.staticFields
			If fieldRecord And RequiresOwningRuntimeLayout(fieldRecord.semanticType, currentModule, ownedRuntimeAbiName) Then Return True
		Next
		For Local methodRecord:TCompilerGenericMethodIr = EachIn unit.ir.methods
			If RequiresOwningRuntimeHeaderForRoutine(methodRecord, currentModule, ownedRuntimeAbiName) Then Return True
		Next
		For Local constructorRecord:TCompilerGenericMethodIr = EachIn unit.ir.constructors
			If RequiresOwningRuntimeHeaderForRoutine(constructorRecord, currentModule, ownedRuntimeAbiName) Then Return True
		Next
		If RequiresOwningRuntimeHeaderForRoutine(unit.ir.routine, currentModule, ownedRuntimeAbiName) Then Return True
		For Local value:TTemplateTypeReference = EachIn unit.ir.referencedTypesByCanonicalName.Values()
			If RequiresOwningRuntimeLayout(value, currentModule, ownedRuntimeAbiName) Then Return True
		Next
		Return False
	End Function

	Function RequiresOwningRuntimeHeaderForRoutine:Int(routine:TCompilerGenericMethodIr, currentModule:String, excludedRuntimeAbiName:String = "")
		If Not routine Then Return False
		If RequiresOwningRuntimeLayout(routine.returnType, currentModule, excludedRuntimeAbiName) Then Return True
		If RequiresOwningRuntimeLayout(routine.receiverType, currentModule, excludedRuntimeAbiName) Then Return True
		For Local parameter:TGenericTemplateValueParameter = EachIn routine.parameters
			If parameter And RequiresOwningRuntimeLayout(parameter.semanticType, currentModule, excludedRuntimeAbiName) Then Return True
		Next
		Return False
	End Function

	Function RequiresOwningRuntimeLayout:Int(value:TTemplateTypeReference, currentModule:String, excludedRuntimeAbiName:String = "")
		If Not value Then Return False
		If value.kind = TEMPLATE_TYPE_POINTER Then Return False
		If value.kind = TEMPLATE_TYPE_NAMED And value.runtimeKind = TEMPLATE_RUNTIME_STRUCT Then
			If excludedRuntimeAbiName.length And value.runtimeAbiName = excludedRuntimeAbiName Then Return False
			If Not value.moduleName.length Or value.moduleName.ToLower().StartsWith("source:") Then Return True
			If currentModule.length And value.moduleName.ToLower() = currentModule.ToLower() Then Return True
		End If
		If RequiresOwningRuntimeLayout(value.elementType, currentModule, excludedRuntimeAbiName) Then Return True
		For Local argument:TTemplateTypeReference = EachIn value.arguments
			If RequiresOwningRuntimeLayout(argument, currentModule, excludedRuntimeAbiName) Then Return True
		Next
		Return False
	End Function

	Function RelativeIncludePath:String(sourcePath:String, targetPath:String)
		Local sourceParts:String[] = sourcePath.Replace("\", "/").Split("/")
		Local targetParts:String[] = targetPath.Replace("\", "/").Split("/")
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

	Function CreateFile:TCompilerBuildOutputFile(role:String, relativePath:String, content:String)
		Local file:TCompilerBuildOutputFile = New TCompilerBuildOutputFile
		file.role = role
		file.relativePath = relativePath.Replace("\", "/")
		file.content = content
		file.contentDigest = TCompilerStableDigest.Sha256MaterializedText(content)
		Return file
	End Function

	Function Manifest:String(plan:TCompilerBuildOutputPlan)
		Local result:String = "BMXBUILD " + COMPILER_BUILD_OUTPUT_VERSION + "~n"
		For Local file:TCompilerBuildOutputFile = EachIn plan.files
			Local cacheKey:String = file.cacheKey
			If Not cacheKey.length Then cacheKey = "-"
			result :+ "file " + file.role + " " + file.contentDigest + " " + cacheKey + " " + Enc(file.semanticIdentity) + " " + Enc(file.relativePath) + "~n"
		Next
		For Local input:TCompilerGenericLinkInput = EachIn plan.linkInputs
			result :+ "link " + input.cacheKey + " " + input.specializationIdentity + " " + Enc(input.sourcePath) + " " + Enc(input.objectPath) + "~n"
		Next
		Return result
	End Function

	Function Enc:String(value:String)
		If Not value.length Then Return "-"
		Return TBase64.Encode(value, EBase64Options.DontBreakLines)
	End Function

	Function DecodeManifest:TCompilerBuildManifest(content:String, diagnostics:TCompilerDiagnostic[] Var)
		Local result:TCompilerBuildManifest = New TCompilerBuildManifest
		diagnostics = New TCompilerDiagnostic[0]
		Local lines:String[] = content.Replace("~r~n", "~n").Replace("~r", "~n").Split("~n")
		If Not lines.length Or lines[0] <> "BMXBUILD " + COMPILER_BUILD_OUTPUT_VERSION Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3072", "Unsupported or missing compiler build manifest version")]
			Return result
		End If
		For Local index:Int = 1 Until lines.length
			Local line:String = lines[index]
			If Not line.length And index = lines.length - 1 Then Continue
			Local parts:String[] = line.Split(" ")
			If parts.length = 6 And parts[0] = "file" Then
				If Not ValidRole(parts[1]) Or Not IsHexDigest(parts[2]) Or (parts[3] <> "-" And Not IsHexDigest(parts[3])) Then
					diagnostics :+ [TCompilerDiagnostic.Create("BMXC3073", "Malformed file record in compiler build manifest")]
					Return result
				End If
				Local record:TCompilerBuildManifestFile = New TCompilerBuildManifestFile
				record.role = parts[1]
				record.contentDigest = parts[2]
				If parts[3] <> "-" Then record.cacheKey = parts[3]
				record.semanticIdentity = Dec(parts[4], diagnostics)
				record.relativePath = Dec(parts[5], diagnostics)
				If diagnostics.length Then Return result
				If Not IsSafeRelativePath(record.relativePath) Then
					diagnostics :+ [TCompilerDiagnostic.Create("BMXC3074", "Unsafe file path in compiler build manifest")]
					Return result
				End If
				For Local existing:TCompilerBuildManifestFile = EachIn result.files
					If existing.relativePath.ToLower() = record.relativePath.ToLower() Then
						diagnostics :+ [TCompilerDiagnostic.Create("BMXC3075", "Duplicate file path in compiler build manifest")]
						Return result
					End If
				Next
				result.files :+ [record]
			Else If parts.length = 5 And parts[0] = "link" Then
				If Not IsHexDigest(parts[1]) Or Not IsHexDigest(parts[2]) Then
					diagnostics :+ [TCompilerDiagnostic.Create("BMXC3076", "Malformed link identity in compiler build manifest")]
					Return result
				End If
				Local input:TCompilerGenericLinkInput = New TCompilerGenericLinkInput
				input.cacheKey = parts[1]
				input.specializationIdentity = parts[2]
				input.sourcePath = Dec(parts[3], diagnostics)
				input.objectPath = Dec(parts[4], diagnostics)
				If diagnostics.length Then Return result
				If Not IsSafeRelativePath(input.sourcePath) Or Not IsSafeRelativePath(input.objectPath) Then
					diagnostics :+ [TCompilerDiagnostic.Create("BMXC3077", "Unsafe link path in compiler build manifest")]
					Return result
				End If
				For Local existing:TCompilerGenericLinkInput = EachIn result.linkInputs
					If existing.specializationIdentity = input.specializationIdentity Or existing.objectPath.ToLower() = input.objectPath.ToLower() Then
						diagnostics :+ [TCompilerDiagnostic.Create("BMXC3078", "Duplicate specialization link input in compiler build manifest")]
						Return result
					End If
				Next
				result.linkInputs :+ [input]
			Else
				diagnostics :+ [TCompilerDiagnostic.Create("BMXC3079", "Unknown or malformed compiler build manifest record")]
				Return result
			End If
		Next
		Return result
	End Function

	Function Dec:String(value:String, diagnostics:TCompilerDiagnostic[] Var)
		If value = "-" Then Return ""
		Try
			Local bytes:Byte[] = TBase64.Decode(value)
			Return String.FromUTF8Bytes(bytes, bytes.length)
		Catch exception:Object
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3080", "Malformed encoded field in compiler build manifest")]
			Return ""
		End Try
	End Function

	Function ValidRole:Int(role:String)
		Select role
			Case "application-c", "runtime-header", "interface", "generic-template", "generic-specialization-c"
				Return True
		End Select
		Return False
	End Function

	Function IsHexDigest:Int(value:String)
		If value.length <> 64 Then Return False
		For Local character:Int = EachIn value.ToLower()
			If Not (character >= 48 And character <= 57) And Not (character >= 97 And character <= 102) Then Return False
		Next
		Return True
	End Function

	Function IsSafeRelativePath:Int(path:String)
		Local normalized:String = path.Replace("\", "/")
		If Not normalized.length Or normalized.StartsWith("/") Or normalized.Contains(":") Then Return False
		For Local component:String = EachIn normalized.Split("/")
			If Not component.length Or component = "." Or component = ".." Then Return False
		Next
		Return True
	End Function
End Type

Type TCompilerBuildOutputMaterializer
	Function Materialize:TCompilerBuildMaterializationResult(plan:TCompilerBuildOutputPlan, rootPath:String, manifestRelativePath:String, diagnostics:TCompilerDiagnostic[] Var, referenceRootPath:String = "")
		Local result:TCompilerBuildMaterializationResult = New TCompilerBuildMaterializationResult
		diagnostics = New TCompilerDiagnostic[0]
		If Not plan Or Not plan.manifest.length Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3064", "A valid build-output plan is required before materialization")]
			Return result
		End If
		If Not rootPath.length Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3065", "Build-output root must not be empty")]
			Return result
		End If
		If Not TCompilerBuildOutputPlanner.IsSafeRelativePath(manifestRelativePath) Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3066", "Build manifest path must be a bounded relative path")]
			Return result
		End If
		If FileType(rootPath) = FILETYPE_NONE And Not CreateDir(rootPath, True) Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3067", "Unable to create build-output root '" + rootPath + "'")]
			Return result
		End If
		If FileType(rootPath) <> FILETYPE_DIR Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3068", "Build-output root is not a directory: '" + rootPath + "'")]
			Return result
		End If

		For Local file:TCompilerBuildOutputFile = EachIn plan.files
			WriteIfChanged(rootPath, file.relativePath, file.content, result, diagnostics, referenceRootPath)
			If diagnostics.length Then Return result
		Next
		result.manifestPath = manifestRelativePath
		WriteIfChanged(rootPath, manifestRelativePath, plan.manifest, result, diagnostics)
		Return result
	End Function

	Function WriteIfChanged(rootPath:String, relativePath:String, content:String, result:TCompilerBuildMaterializationResult, diagnostics:TCompilerDiagnostic[] Var, referenceRootPath:String = "")
		If Not TCompilerBuildOutputPlanner.IsSafeRelativePath(relativePath) Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3069", "Refusing to materialize unsafe output path '" + relativePath + "'")]
			Return
		End If
		Local fullPath:String = rootPath.Replace("\", "/") + "/" + relativePath
		If FileType(fullPath) = FILETYPE_FILE And LoadText(fullPath) = content Then
			result.reusedPaths :+ [relativePath]
			Return
		End If
		If referenceRootPath.length Then
			Local referencePath:String = referenceRootPath.Replace("\", "/") + "/" + relativePath
			If FileType(referencePath) = FILETYPE_FILE And LoadText(referencePath) = content Then
				result.reusedPaths :+ [relativePath]
				Return
			End If
		End If
		Local directory:String = ExtractDir(fullPath)
		If FileType(directory) = FILETYPE_NONE And Not CreateDir(directory, True) Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3070", "Unable to create generated-output directory '" + directory + "'")]
			Return
		End If
		Local temporaryPath:String = bmx_compiler_temporary_output_path(fullPath)
		DeleteFile temporaryPath
		If Not SaveText(content, temporaryPath) Then
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3071", "Unable to write generated output '" + fullPath + "'")]
			Return
		End If
		If Not bmx_compiler_atomic_replace(temporaryPath, fullPath) Then
			DeleteFile temporaryPath
			diagnostics :+ [TCompilerDiagnostic.Create("BMXC3072", "Unable to publish generated output '" + fullPath + "'")]
			Return
		End If
		result.writtenPaths :+ [relativePath]
	End Function
End Type
