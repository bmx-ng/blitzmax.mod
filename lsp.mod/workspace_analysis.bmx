' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import BRL.MaxUtil
Import BRL.Stream
Import BRL.TextStream
Import Text.Json
Import BlitzMax.Language
Import "protocol.bmx"
Import "documents.bmx"

Type TLspWorkspaceConfiguration
	Field sdkPath:String
	Field rootSourcePath:String
	Field buildMode:String = "release"
	Field targetPlatform:String = HostTargetPlatform()
	Field targetArchitecture:String = HostTargetArchitecture()
	Field conditionalSymbols:String[]
	Field requireCoreInterface:Int = True
	Field useDependencySnapshots:Int = True
	Field warnImplicitDefaultReturns:Int

	Function CreateDefault:TLspWorkspaceConfiguration()
		Local result:TLspWorkspaceConfiguration = New TLspWorkspaceConfiguration
		Try
			result.sdkPath = BlitzMaxPath()
		Catch exception:Object
			result.sdkPath = ""
		End Try
		result.conditionalSymbols = DefaultConditionalSymbols(result.targetPlatform, result.targetArchitecture)
		Return result
	End Function

	Method Copy:TLspWorkspaceConfiguration()
		Local result:TLspWorkspaceConfiguration = New TLspWorkspaceConfiguration
		result.sdkPath = sdkPath
		result.rootSourcePath = rootSourcePath
		result.buildMode = buildMode
		result.targetPlatform = targetPlatform
		result.targetArchitecture = targetArchitecture
		result.conditionalSymbols = conditionalSymbols[..]
		result.requireCoreInterface = requireCoreInterface
		result.useDependencySnapshots = useDependencySnapshots
		result.warnImplicitDefaultReturns = warnImplicitDefaultReturns
		Return result
	End Method

	Method ApplyJson(settings:TJSONObject)
		If Not settings Then Return
		If settings.Get("sdkPath") Then sdkPath = settings.GetString("sdkPath")
		If settings.Get("rootSourcePath") Then rootSourcePath = NormalizeWorkspacePath(settings.GetString("rootSourcePath"))
		If settings.Get("buildMode") Then buildMode = settings.GetString("buildMode").ToLower()
		If settings.Get("targetPlatform") Then targetPlatform = settings.GetString("targetPlatform").ToLower()
		If settings.Get("targetArchitecture") Then targetArchitecture = settings.GetString("targetArchitecture").ToLower()
		If settings.Get("requireCoreInterface") Then requireCoreInterface = settings.GetBool("requireCoreInterface")
		If settings.Get("useDependencySnapshots") Then useDependencySnapshots = settings.GetBool("useDependencySnapshots")
		If settings.Get("warnImplicitDefaultReturns") Then warnImplicitDefaultReturns = settings.GetBool("warnImplicitDefaultReturns")
		Local symbols:TJSONArray = TJSONArray(settings.Get("conditionalSymbols"))
		If symbols Then
			conditionalSymbols = New String[symbols.Size()]
			For Local index:Int = 0 Until symbols.Size()
				Local symbol:TJSONString = TJSONString(symbols.Get(index))
				If symbol Then conditionalSymbols[index] = symbol.Value().ToLower()
			Next
		Else If settings.Get("targetPlatform") Or settings.Get("targetArchitecture") Then
			conditionalSymbols = DefaultConditionalSymbols(targetPlatform, targetArchitecture)
		End If
	End Method

	Method InterfaceMung:String()
		Return buildMode + "." + targetPlatform + "." + targetArchitecture
	End Method

	Method SnapshotOptions:TCompilationSnapshotOptions()
		Local result:TCompilationSnapshotOptions = New TCompilationSnapshotOptions
		result.targetPlatform = targetPlatform
		result.conditionalSymbols = conditionalSymbols[..]
		result.EnsureConditionalSymbol("bmxng")
		result.EnsureConditionalSymbol("bmxng2")
		result.requireCoreInterface = requireCoreInterface
		Return result
	End Method

	Method AnalysisOptions:TLanguageAnalysisOptions()
		Local result:TLanguageAnalysisOptions = TLanguageAnalysisOptions.Create()
		result.typeResolution = New TTypeResolutionOptions
		result.typeResolution.reportUnresolvedTypes = True
		result.controlFlow = TControlFlowAnalysisOptions.Create()
		result.controlFlow.reportImplicitDefaultReturns = warnImplicitDefaultReturns
		result.controlFlow.implicitDefaultReturnSeverity = DIAGNOSTIC_WARNING
		Return result
	End Method
End Type

' Process-wide cache of immutable compiler interface text and its parsed
' baseline. Snapshot loading receives a request-owned clone because it enriches
' the compact record graph. Configuration changes replace the cache generation.
Type TLspDependencyCache
	Field entries:TMap = New TMap
	Field entryCount:Int
	Field parsedInterfaceCount:Int
	Field generation:Int

	Method Load:TSnapshotText(path:String)
		Local key:String = SnapshotPathKey(path)
		Local existing:TLspDependencyCacheEntry = TLspDependencyCacheEntry(entries.ValueForKey(key))
		If FileType(path) <> FILETYPE_FILE Then
			If existing Then
				entries.Remove(key)
				entryCount :- 1
				If existing.parsedInterface Then parsedInterfaceCount :- 1
				generation :+ 1
			End If
			Return Null
		End If
		Local modified:Long = FileTime(path)
		Local size:Long = FileSize(path)
		If existing And existing.modified = modified And existing.size = size Then Return existing.text
		Local entry:TLspDependencyCacheEntry = New TLspDependencyCacheEntry
		entry.modified = modified
		entry.size = size
		entry.text = TSnapshotText.Create(path, LoadText(path))
		If existing And existing.parsedInterface Then parsedInterfaceCount :- 1
		entries.Insert(key, entry)
		If Not existing Then entryCount :+ 1 Else generation :+ 1
		Return entry.text
	End Method

	Method LoadInterface:TSnapshotText(path:String)
		Local text:TSnapshotText = Load(path)
		If Not text Then Return Null
		Local entry:TLspDependencyCacheEntry = TLspDependencyCacheEntry(entries.ValueForKey(SnapshotPathKey(path)))
		If Not entry.parsedInterface Then
			entry.parsedInterface = TBlitzMaxParser.ParseInterfaceText(text.text, path)
			parsedInterfaceCount :+ 1
		End If
		Return TSnapshotText.CreateInterface(path, TInterfaceFileCloner.Clone(entry.parsedInterface))
	End Method

	Method Clear()
		entries.Clear()
		entryCount = 0
		parsedInterfaceCount = 0
		generation :+ 1
	End Method

	Method Count:Int()
		Return entryCount
	End Method

	Method ParsedInterfaceCount:Int()
		Return parsedInterfaceCount
	End Method
End Type

Type TLspDependencyCacheEntry
	Field text:TSnapshotText
	Field parsedInterface:TInterfaceFile
	Field modified:Long
	Field size:Long
End Type

Type TLspFileSnapshotResolver Extends TSnapshotResolver
	Field configuration:TLspWorkspaceConfiguration
	Field dependencies:TLspDependencyCache
	Field documents:TLspDocumentStore
	Field liveInterfaces:TMap
	Field sourceDependencies:TMap = New TMap
	Field includeDependencies:TMap = New TMap
	Field sourceImportDependencies:TMap = New TMap

	Function Create:TLspFileSnapshotResolver(configuration:TLspWorkspaceConfiguration, dependencies:TLspDependencyCache, documents:TLspDocumentStore = Null, liveInterfaces:TMap = Null)
		Local result:TLspFileSnapshotResolver = New TLspFileSnapshotResolver
		result.configuration = configuration
		result.dependencies = dependencies
		result.documents = documents
		result.liveInterfaces = liveInterfaces
		Return result
	End Function

	Method ResolveInclude:TSnapshotText(includingPath:String, includePath:String)
		Local path:String = ResolveRelativePath(includingPath, includePath)
		RecordSourceDependency(path)
		includeDependencies.Insert(SnapshotPathKey(path), path)
		Local document:TLspDocument = OpenDocument(path)
		If document Then Return TSnapshotText.Create(document.path, document.text)
		If FileType(path) <> FILETYPE_FILE Then Return Null
		Return TSnapshotText.Create(path, LoadText(path))
	End Method

	Method ResolveInterface:TSnapshotText(importingPath:String, target:String, isFileImport:Int, isFramework:Int)
		Local path:String
		If isFileImport Then
			Local sourcePath:String = ResolveRelativePath(importingPath, target)
			If sourcePath.ToLower().EndsWith(".bmx") Then
				RecordSourceDependency(sourcePath)
				sourceImportDependencies.Insert(SnapshotPathKey(sourcePath), sourcePath)
				If liveInterfaces Then
					Local live:TSnapshotText = TSnapshotText(liveInterfaces.ValueForKey(SnapshotPathKey(sourcePath)))
					If live Then Return live
				End If
				Local document:TLspDocument = OpenDocument(sourcePath)
				If document Then
					Local sourceInterface:TInterfaceFile = TBlitzMaxSourceInterfaceBuilder.Build(document.path, document.text, Self, configuration.SnapshotOptions())
					Return TSnapshotText.CreateInterface(document.path, sourceInterface)
				End If
				sourcePath = LocalSourceInterfacePath(sourcePath, configuration.InterfaceMung())
			End If
			path = sourcePath
		Else
			path = ModuleInterfacePath(configuration.sdkPath, target, configuration.InterfaceMung())
		End If
		Return dependencies.LoadInterface(path)
	End Method

	Method OpenDocument:TLspDocument(path:String)
		If Not documents Then Return Null
		Local document:TLspDocument = documents.GetByPath(path)
		If document And document.liveOverlay Then Return document
		Return Null
	End Method

	Method RecordSourceDependency(path:String)
		Local key:String = SnapshotPathKey(path)
		sourceDependencies.Insert(key, path)
	End Method

	Method ResolveCoreInterface:TSnapshotText(targetPlatform:String)
		Local directory:String = NormalizeWorkspacePath(configuration.sdkPath) + "/mod/brl.mod/blitz.mod"
		Local specialized:String = directory + "/blitz_classes." + targetPlatform + ".i"
		Local result:TSnapshotText = dependencies.LoadInterface(specialized)
		If result Then Return result
		Return dependencies.LoadInterface(directory + "/blitz_classes.i")
	End Method
End Type

Function ModuleInterfacePath:String(sdkPath:String, moduleName:String, mung:String)
	moduleName = moduleName.ToLower()
	Local slash:Int = moduleName.FindLast(".")
	Local identifier:String = moduleName
	If slash >= 0 Then identifier = moduleName[slash + 1..]
	Local moduleRoot:String = NormalizeWorkspacePath(sdkPath) + "/mod"
	Return ModulePathAtRoot(moduleRoot, moduleName) + "/" + identifier + "." + mung + ".i"
End Function

' bmk writes the interface for a quoted source import into the hidden build
' directory beside that source. Module interfaces use ModuleInterfacePath and
' remain directly in the module directory.
Function LocalSourceInterfacePath:String(sourcePath:String, mung:String)
	Local normalized:String = NormalizeWorkspacePath(sourcePath)
	Return ExtractDir(normalized) + "/.bmx/" + StripDir(normalized) + "." + mung + ".i"
End Function

Function ResolveRelativePath:String(basePath:String, relativePath:String)
	Local candidate:String = relativePath.Replace("\", "/")
	If candidate.StartsWith("/") Then Return RealPath(candidate)
	?win32
	If candidate.length > 1 And candidate[1] = 58 Then Return RealPath(candidate)
	?
	Return RealPath(ExtractDir(basePath) + "/" + candidate)
End Function

Function SnapshotPathKey:String(path:String)
	Local result:String = NormalizeWorkspacePath(path)
	?win32
	result = result.ToLower()
	?
	Return result
End Function

Function DefaultConditionalSymbols:String[](platform:String, architecture:String)
	' bcc builds threaded programs by default, so source snapshots must expose
	' imports and declarations guarded by ?Threaded unless explicitly configured
	' otherwise in a future build-profile option.
	Local result:String[] = [platform, architecture, platform + architecture, "threaded", "bmxng", "bmxng2"]
	If architecture = "x64" Or architecture = "arm64" Or architecture = "ppc64" Then result :+ ["ptr64"]
	Return result
End Function

Function HostTargetPlatform:String()
	?win32
	Return "win32"
	?macos
	Return "macos"
	?linux
	Return "linux"
	?haiku
	Return "haiku"
	?android
	Return "android"
	?Not win32 And Not macos And Not linux And Not haiku And Not android
	Return ""
	?
End Function

Function HostTargetArchitecture:String()
	?arm64
	Return "arm64"
	?x64
	Return "x64"
	?x86
	Return "x86"
	?arm
	Return "arm"
	?ppc64
	Return "ppc64"
	?Not arm64 And Not x64 And Not x86 And Not arm And Not ppc64
	Return ""
	?
End Function
