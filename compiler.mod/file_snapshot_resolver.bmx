' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.MaxUtil
Import BRL.Stream
Import BlitzMax.Language
Import "compiler_options.bmx"

' Build-scoped catalogue for immutable file contents and decoded input models.
' Parsed interfaces are cloned on read because snapshot loading mutates their
' record graph. Decoded generic template artifacts are immutable and shared.
Type TCompilerSnapshotTextCacheEntry
	Field modifiedTime:Long
	Field size:Long
	Field text:String
	Field parsedInterface:TInterfaceFile
	Field genericTemplateArtifact:TGenericTemplateArtifact
	Field genericTemplateDiagnostics:String[] = New String[0]
	Field genericTemplateDecoded:Int
End Type

Type TCompilerSnapshotTextCache
	Field entriesByPath:TMap = New TMap
	Field hits:Long
	Field misses:Long
	Field interfaceParseHits:Long
	Field interfaceParseMisses:Long
	Field interfaceResolutionHits:Long
	Field genericTemplateDecodeHits:Long
	Field genericTemplateDecodeMisses:Long

	Method Load:TSnapshotText(path:String)
		Local entry:TCompilerSnapshotTextCacheEntry = EntryFor(path)
		If Not entry Then Return Null
		Return TSnapshotText.Create(path, entry.text)
	End Method

	Method LoadInterface:TSnapshotText(path:String)
		Local entry:TCompilerSnapshotTextCacheEntry = EntryFor(path, True)
		If Not entry Then Return Null
		If entry.parsedInterface Then
			interfaceParseHits :+ 1
		Else
			entry.parsedInterface = TBlitzMaxParser.ParseInterfaceText(entry.text, path)
			interfaceParseMisses :+ 1
		End If
		Return TSnapshotText.CreateInterface(path, TInterfaceFileCloner.Clone(entry.parsedInterface))
	End Method

	Method LoadGenericTemplate:TSnapshotText(path:String)
		Local entry:TCompilerSnapshotTextCacheEntry = EntryFor(path)
		If Not entry Then Return Null
		If entry.genericTemplateDecoded Then
			genericTemplateDecodeHits :+ 1
		Else
			Local decoded:TGenericTemplateArtifactDecodeResult = TGenericTemplateArtifactCodec.Decode(entry.text)
			entry.genericTemplateArtifact = decoded.artifact
			entry.genericTemplateDiagnostics = decoded.diagnostics[..]
			entry.genericTemplateDecoded = True
			genericTemplateDecodeMisses :+ 1
		End If
		Return TSnapshotText.CreateGenericTemplate(path, entry.genericTemplateArtifact, entry.genericTemplateDiagnostics)
	End Method

	Method EntryFor:TCompilerSnapshotTextCacheEntry(path:String, materializedText:Int = False)
		Local normalizedPath:String = CompilerNormalizePath(path)
		Local info:SFileStat
		If Not FileStat(normalizedPath, info) Or info.fileType <> FILETYPE_FILE Then Return Null
		Local key:String = normalizedPath.ToLower()
		If materializedText Then key :+ "|materialized"
		Local existing:TCompilerSnapshotTextCacheEntry = TCompilerSnapshotTextCacheEntry(entriesByPath.ValueForKey(key))
		If existing And existing.modifiedTime = info.modifiedTime And existing.size = info.size Then
			hits :+ 1
			Return existing
		End If
		Local entry:TCompilerSnapshotTextCacheEntry = New TCompilerSnapshotTextCacheEntry
		entry.modifiedTime = info.modifiedTime
		entry.size = info.size
		If materializedText Then
			entry.text = CompilerLoadMaterializedText(normalizedPath)
		Else
			entry.text = LoadText(normalizedPath)
		End If
		entriesByPath.Insert(key, entry)
		misses :+ 1
		Return entry
	End Method

	Method Invalidate(path:String)
		If Not path.length Then Return
		Local key:String = CompilerNormalizePath(path).ToLower()
		entriesByPath.Remove(key)
		entriesByPath.Remove(key + "|materialized")
	End Method

	Method Clear()
		entriesByPath.Clear()
		hits = 0
		misses = 0
		interfaceParseHits = 0
		interfaceParseMisses = 0
		interfaceResolutionHits = 0
		genericTemplateDecodeHits = 0
		genericTemplateDecodeMisses = 0
	End Method
End Type

' Retained for source compatibility. Reusable interface cloning now belongs to
' BlitzMax.Language so non-compiler consumers can share parsed baselines safely.
Type TCompilerInterfaceFileCloner
	Function Clone:TInterfaceFile(source:TInterfaceFile)
		Return TInterfaceFileCloner.Clone(source)
	End Function
End Type

' Read-only resolver for the interface layout produced by bmk. Dependency
' freshness remains bmk's responsibility; the compiler never builds imports.
Type TCompilerFileSnapshotResolver Extends TSnapshotResolver
	Field options:TCompilerOptions
	Field cache:TCompilerSnapshotTextCache
	' One resolver serves one compilation request. Snapshot loading may resolve
	' the same transitive interface through many import edges before its own
	' path catalogue rejects the duplicate. Reuse the request-owned clone here;
	' no mutable interface graph crosses into another request.
	Field resolvedInterfacesByPath:TMap = New TMap

	Function Create:TCompilerFileSnapshotResolver(options:TCompilerOptions, cache:TCompilerSnapshotTextCache = Null)
		Local result:TCompilerFileSnapshotResolver = New TCompilerFileSnapshotResolver
		result.options = options
		result.cache = cache
		Return result
	End Function

	Method ResolveInclude:TSnapshotText(includingPath:String, includePath:String)
		Return LoadSnapshot(CompilerResolveRelativePath(includingPath, includePath))
	End Method

	Method ResolveInterface:TSnapshotText(importingPath:String, target:String, isFileImport:Int, isFramework:Int)
		Local path:String
		If isFileImport Then
			path = CompilerResolveRelativePath(importingPath, target)
			If path.ToLower().EndsWith(".bmx") Then path = CompilerLocalSourceInterfacePath(path, options.InterfaceMung())
		Else
			path = CompilerModuleInterfacePath(options.sdkPath, target, options.InterfaceMung())
		End If
		Return LoadInterfaceSnapshot(path)
	End Method

	Method ResolveCoreInterface:TSnapshotText(targetPlatform:String)
		Local directory:String = CompilerNormalizePath(options.sdkPath) + "/mod/brl.mod/blitz.mod"
		Local specialized:String = directory + "/blitz_classes." + targetPlatform.ToLower() + ".i"
		Local result:TSnapshotText = LoadInterfaceSnapshot(specialized)
		If result Then Return result
		Return LoadInterfaceSnapshot(directory + "/blitz_classes.i")
	End Method

	Method ResolveGenericTemplate:TSnapshotText(interfacePath:String, artifactReference:String)
		Local path:String = CompilerResolveRelativePath(interfacePath, artifactReference)
		If cache Then Return cache.LoadGenericTemplate(path)
		Return LoadSnapshot(path)
	End Method

	Method LoadInterfaceSnapshot:TSnapshotText(path:String)
		Local normalizedPath:String = CompilerNormalizePath(path)
		Local key:String = normalizedPath.ToLower()
		Local existing:TSnapshotText = TSnapshotText(resolvedInterfacesByPath.ValueForKey(key))
		If existing Then
			If cache Then cache.interfaceResolutionHits :+ 1
			Return existing
		End If
		Local result:TSnapshotText
		If cache Then
			result = cache.LoadInterface(normalizedPath)
		Else If FileType(normalizedPath) = FILETYPE_FILE Then
			result = TSnapshotText.Create(normalizedPath, CompilerLoadMaterializedText(normalizedPath))
		End If
		If result Then resolvedInterfacesByPath.Insert(key, result)
		Return result
	End Method

	Method LoadSnapshot:TSnapshotText(path:String)
		If cache Then Return cache.Load(path)
		If FileType(path) <> FILETYPE_FILE Then Return Null
		Return TSnapshotText.Create(path, LoadText(path))
	End Method
End Type

' Compact interfaces are written through SaveText's byte-materialized format.
' Reading them as UTF-8 can collapse a perfectly valid sequence of source
' code units (notably Chr(239)+Chr(187)+Chr(191)) into one Unicode character.
Function CompilerLoadMaterializedText:String(path:String)
	Local bytes:Byte[] = LoadByteArray(path)
	If Not bytes Then Return ""
	Return String.FromBytes(bytes, bytes.length)
End Function

Function CompilerModuleInterfacePath:String(sdkPath:String, moduleName:String, mung:String)
	moduleName = moduleName.ToLower()
	Local dot:Int = moduleName.FindLast(".")
	Local identifier:String = moduleName
	If dot >= 0 Then identifier = moduleName[dot + 1..]
	Local moduleRoot:String = CompilerNormalizePath(sdkPath) + "/mod"
	Return ModulePathAtRoot(moduleRoot, moduleName) + "/" + identifier + "." + mung + ".i"
End Function

Function CompilerLocalSourceInterfacePath:String(sourcePath:String, mung:String)
	Local normalized:String = CompilerNormalizePath(sourcePath)
	Return ExtractDir(normalized) + "/.bmx/" + StripDir(normalized) + "." + mung + ".i"
End Function

Function CompilerResolveRelativePath:String(basePath:String, relativePath:String)
	Local candidate:String = relativePath.Replace("\", "/")
	If candidate.StartsWith("/") Then Return RealPath(candidate)
	?win32
	If candidate.length > 1 And candidate[1] = 58 Then Return RealPath(candidate)
	?
	Return RealPath(ExtractDir(basePath) + "/" + candidate)
End Function

Function CompilerNormalizePath:String(path:String)
	If Not path.length Then Return ""
	Local resolved:String = RealPath(path)
	If resolved.length Then Return resolved.Replace("\", "/")
	Return path.Replace("\", "/")
End Function
