' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import BlitzMax.Language

Import "workspace_analysis.bmx"

Type TLspDiscoveredModule
	Field name:String
	Field path:String
	Field isCore:Int
End Type

Type TLspInstalledModuleEntry
	Field name:String
	Field path:String
	Field isCore:Int
	Field snapshot:TSnapshotText
	Field interfaceFile:TInterfaceFile
End Type

' Lightweight module-name discovery for import completion. Unlike the symbol
' catalogue, this never loads or parses compiler interfaces.
Type TLspInstalledModuleNames
	Field configurationKey:String
	Field names:String[] = New String[0]

	Method Refresh(configuration:TLspWorkspaceConfiguration)
		configurationKey = TLspInstalledModuleCatalogue.ConfigurationKeyFor(configuration)
		names = New String[0]
		Local discovered:TMap = TLspInstalledModuleCatalogue.Discover(configuration)
		For Local value:Object = EachIn discovered.Values()
			Local item:TLspDiscoveredModule = TLspDiscoveredModule(value)
			If item And Not item.isCore Then names :+ [item.name]
		Next
	End Method
End Type

' One catalogue for a specific SDK/build/platform/architecture interface set.
Type TLspInstalledModuleCatalogue
	Field configurationKey:String
	Field entries:TMap = New TMap
	Field catalogue:TModuleSymbolCatalogue = New TModuleSymbolCatalogue
	Field generation:Int

	Method Refresh:Int(configuration:TLspWorkspaceConfiguration, dependencies:TLspDependencyCache)
		If Not configuration Or Not dependencies Or Not configuration.sdkPath.length Then Return False
		Local nextKey:String = ConfigurationKeyFor(configuration)
		Local changed:Int
		If configurationKey <> nextKey Then
			configurationKey = nextKey
			entries.Clear()
			changed = True
		End If

		Local discovered:TMap = Discover(configuration)
		Local removed:String[]
		For Local value:Object = EachIn entries.Keys()
			Local key:String = String(value)
			If Not discovered.Contains(key) Then removed :+ [key]
		Next
		For Local key:String = EachIn removed
			entries.Remove(key)
			changed = True
		Next

		For Local value:Object = EachIn discovered.Values()
			Local item:TLspDiscoveredModule = TLspDiscoveredModule(value)
			Local key:String = item.name.ToLower()
			Local snapshot:TSnapshotText = dependencies.Load(item.path)
			If Not snapshot Then Continue
			Local existing:TLspInstalledModuleEntry = TLspInstalledModuleEntry(entries.ValueForKey(key))
			If existing And existing.snapshot = snapshot Then Continue
			Local entry:TLspInstalledModuleEntry = New TLspInstalledModuleEntry
			entry.name = item.name
			entry.path = item.path
			entry.isCore = item.isCore
			entry.snapshot = snapshot
			entry.interfaceFile = TBlitzMaxParser.ParseInterfaceCatalogueText(snapshot.text, snapshot.path)
			entries.Insert(key, entry)
			changed = True
		Next

		If changed Then Rebuild()
		Return changed
	End Method

	Method Rebuild()
		catalogue = New TModuleSymbolCatalogue
		Local count:Int
		For Local entry:TLspInstalledModuleEntry = EachIn entries.Values()
			count :+ 1
		Next
		Local names:String[] = New String[count]
		Local paths:String[] = New String[count]
		Local interfaces:TInterfaceFile[] = New TInterfaceFile[count]
		Local coreFlags:Int[] = New Int[count]
		Local index:Int
		For Local entry:TLspInstalledModuleEntry = EachIn entries.Values()
			names[index] = entry.name
			paths[index] = entry.path
			interfaces[index] = entry.interfaceFile
			coreFlags[index] = entry.isCore
			index :+ 1
		Next
		catalogue.AddModules(names, paths, interfaces, coreFlags)
		generation :+ 1
	End Method

	Method ModuleCount:Int()
		Return catalogue.ModuleCount()
	End Method

	Method SymbolCount:Int()
		Return catalogue.SymbolCount()
	End Method

	Method TypeCount:Int()
		Return catalogue.TypeCount()
	End Method

	Function ConfigurationKeyFor:String(configuration:TLspWorkspaceConfiguration)
		If Not configuration Then Return ""
		Return SnapshotPathKey(configuration.sdkPath) + "|" + configuration.InterfaceMung() + "|" + configuration.targetPlatform
	End Function

	Function Discover:TMap(configuration:TLspWorkspaceConfiguration)
		Local result:TMap = New TMap
		Local moduleRoot:String = NormalizeWorkspacePath(configuration.sdkPath) + "/mod"
		If FileType(moduleRoot) <> FILETYPE_DIR Then Return result
		For Local item:TModuleDirectory = EachIn EnumModuleDirectories(moduleRoot)
			If FileType(item.SourcePath()) <> FILETYPE_FILE Then Continue
			Local interfacePath:String = item.path + "/" + item.identifier.ToLower() + "." + configuration.InterfaceMung() + ".i"
			If FileType(interfacePath) <> FILETYPE_FILE Then Continue
			AddDiscovered(result, item.name, interfacePath, False)
		Next

		Local coreDirectory:String = moduleRoot + "/brl.mod/blitz.mod"
		Local corePath:String = coreDirectory + "/blitz_classes." + configuration.targetPlatform + ".i"
		If FileType(corePath) <> FILETYPE_FILE Then corePath = coreDirectory + "/blitz_classes.i"
		If FileType(corePath) = FILETYPE_FILE Then AddDiscovered(result, "brl.classes", corePath, True)
		Return result
	End Function

	Function AddDiscovered(result:TMap, name:String, path:String, isCore:Int)
		Local item:TLspDiscoveredModule = New TLspDiscoveredModule
		item.name = name.ToLower()
		item.path = NormalizeWorkspacePath(path)
		item.isCore = isCore
		Local existing:TLspDiscoveredModule = TLspDiscoveredModule(result.ValueForKey(item.name))
		If existing And SnapshotPathKey(existing.path) <> SnapshotPathKey(item.path) Then
			Throw "Ambiguous module '" + item.name + "' maps to both '" + existing.path + "' and '" + item.path + "'"
		End If
		result.Insert(item.name, item)
	End Function
End Type

' Process-wide set of catalogues. Workspace roots with the same active SDK and
' target configuration share one parsed symbol index.
Type TLspInstalledModuleCatalogueStore
	Field catalogues:TMap = New TMap
	Field nameCatalogues:TMap = New TMap
	Field catalogueCount:Int

	Method Ensure:TLspInstalledModuleCatalogue(configuration:TLspWorkspaceConfiguration, dependencies:TLspDependencyCache)
		Local key:String = TLspInstalledModuleCatalogue.ConfigurationKeyFor(configuration)
		Local result:TLspInstalledModuleCatalogue = TLspInstalledModuleCatalogue(catalogues.ValueForKey(key))
		If Not result Then
			result = New TLspInstalledModuleCatalogue
			result.configurationKey = key
			catalogues.Insert(key, result)
			catalogueCount :+ 1
			result.Refresh(configuration, dependencies)
		End If
		Return result
	End Method

	Method Names:String[](configuration:TLspWorkspaceConfiguration)
		Local key:String = TLspInstalledModuleCatalogue.ConfigurationKeyFor(configuration)
		Local result:TLspInstalledModuleNames = TLspInstalledModuleNames(nameCatalogues.ValueForKey(key))
		If Not result Then
			result = New TLspInstalledModuleNames
			result.Refresh(configuration)
			nameCatalogues.Insert(key, result)
		End If
		Return result.names
	End Method

	Method RefreshNames(configuration:TLspWorkspaceConfiguration)
		Local key:String = TLspInstalledModuleCatalogue.ConfigurationKeyFor(configuration)
		Local result:TLspInstalledModuleNames = New TLspInstalledModuleNames
		result.Refresh(configuration)
		nameCatalogues.Insert(key, result)
	End Method

	Method Refresh:TLspInstalledModuleCatalogue(configuration:TLspWorkspaceConfiguration, dependencies:TLspDependencyCache)
		Local key:String = TLspInstalledModuleCatalogue.ConfigurationKeyFor(configuration)
		Local existing:TLspInstalledModuleCatalogue = TLspInstalledModuleCatalogue(catalogues.ValueForKey(key))
		Local result:TLspInstalledModuleCatalogue = Ensure(configuration, dependencies)
		If existing Then result.Refresh(configuration, dependencies)
		Return result
	End Method

	Method Clear()
		catalogues.Clear()
		nameCatalogues.Clear()
		catalogueCount = 0
	End Method

	Method Count:Int()
		Return catalogueCount
	End Method
End Type
