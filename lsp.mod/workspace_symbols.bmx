' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "navigation_features.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

Const LSP_WORKSPACE_SYMBOL_LIMIT:Int = 256

Type TWorkspaceSymbolEntry
	Field score:Int
	Field normalizedName:String
	Field container:String
	Field normalizedContainer:String
	Field item:TJSONObject
	Field catalogueSymbol:TModuleCatalogueSymbol
End Type

' Declaration search over live semantic models and the installed interface
' catalogue. Usage sites are deliberately outside this index; this implements
' workspace/symbol, not workspace-wide references.
Type TBlitzMaxLspWorkspaceSymbols
	Function Query:TJSON(query:String, workspaces:TLspWorkspaceStore, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		If Not workspaces Then Return result
		Local normalizedQuery:String = query.Trim().ToLower()
		Local entries:TWorkspaceSymbolEntry[]
		Local seenCatalogues:TMap = New TMap
		AppendContext(entries, seenCatalogues, normalizedQuery, workspaces.adHoc, documents)
		For Local context:TLspWorkspaceContext = EachIn workspaces.contexts.Values()
			AppendContext(entries, seenCatalogues, normalizedQuery, context, documents)
		Next
		SortEntries(entries)
		Local sourceCache:TMap = New TMap
		Local resultSeen:TMap = New TMap
		For Local entry:TWorkspaceSymbolEntry = EachIn entries
			If result.Size() >= LSP_WORKSPACE_SYMBOL_LIMIT Then Exit
			Local item:TJSONObject = Materialize(entry, documents, sourceCache)
			If Not item Then Continue
			Local key:String = ItemIdentity(item)
			If resultSeen.Contains(key) Then Continue
			resultSeen.Insert(key, item)
			result.Append(item)
		Next
		Return result
	End Function

	Function AppendContext(entries:TWorkspaceSymbolEntry[] Var, seenCatalogues:TMap, query:String, context:TLspWorkspaceContext, documents:TLspDocumentStore)
		If Not context Then Return
		For Local value:Object = EachIn context.analyses.Keys()
			Local analysis:TLanguageAnalysis = context.LatestAnalysis(String(value))
			If analysis And analysis.model Then AppendLiveScope(entries, query, analysis.model.globalScope, analysis, documents)
		Next
		Local installed:TLspInstalledModuleCatalogue = context.InstalledCatalogue()
		If Not installed Or Not installed.catalogue Or seenCatalogues.Contains(installed.catalogue) Then Return
		seenCatalogues.Insert(installed.catalogue, installed.catalogue)
		AppendCatalogue(entries, query, installed.catalogue)
	End Function

	Function AppendLiveScope(entries:TWorkspaceSymbolEntry[] Var, query:String, scope:TScope, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not SearchableLiveSymbol(symbol, scope) Then Continue
			Local container:String = LiveContainer(symbol)
			Local score:Int = MatchScore(symbol.name, container, query)
			If score < 0 Then Continue
			Local location:TJSONObject = TJSONObject(TBlitzMaxLspNavigation.LocationForSymbol(symbol, analysis.syntaxTree.source.path, analysis, documents))
			If Not location Then Continue
			AppendEntry(entries, score, symbol.name, container, TBlitzMaxLspNavigation.SymbolKind(symbol), location)
		Next
		For Local child:TScope = EachIn scope.children
			AppendLiveScope(entries, query, child, analysis, documents)
		Next
	End Function

	Function SearchableLiveSymbol:Int(symbol:TSymbol, scope:TScope)
		If Not symbol Or symbol.isImported Or Not symbol.name.length Then Return False
		Select symbol.kind
			Case SYMBOL_TYPE, SYMBOL_STRUCT, SYMBOL_INTERFACE, SYMBOL_ENUM, SYMBOL_ENUM_MEMBER
				Return True
			Case SYMBOL_FIELD, SYMBOL_GLOBAL, SYMBOL_CONST, SYMBOL_ROUTINE
				Return True
			Case SYMBOL_LOCAL
				Return scope <> Null And scope.kind = SCOPE_COMPILATION_UNIT
		End Select
		Return False
	End Function

	Function LiveContainer:String(symbol:TSymbol)
		If Not symbol Or Not symbol.containingScope Then Return ""
		Local owner:TSymbol = symbol.containingScope.owner
		If owner Then Return owner.name
		Return ""
	End Function

	Function AppendCatalogue(entries:TWorkspaceSymbolEntry[] Var, query:String, catalogue:TModuleSymbolCatalogue)
		For Local symbol:TModuleCatalogueSymbol = EachIn catalogue.symbols
			If Not symbol Or Not symbol.isPublic Or Not symbol.name.length Then Continue
			If Not symbol.originPath.ToLower().EndsWith(".bmx") Or symbol.originLine <= 0 Then Continue
			Local container:String = symbol.moduleEntry.name
			If symbol.parent Then container = symbol.parent.qualifiedName
			Local score:Int = MatchScore(symbol.name, container, query)
			If score < 0 Then Continue
			Local entry:TWorkspaceSymbolEntry = New TWorkspaceSymbolEntry
			entry.score = score
			entry.normalizedName = symbol.normalizedName
			entry.container = container
			entry.normalizedContainer = container.ToLower()
			entry.catalogueSymbol = symbol
			entries :+ [entry]
		Next
	End Function

	Function Materialize:TJSONObject(entry:TWorkspaceSymbolEntry, documents:TLspDocumentStore, sourceCache:TMap)
		If Not entry Then Return Null
		If entry.item Then Return entry.item
		Local symbol:TModuleCatalogueSymbol = entry.catalogueSymbol
		If Not symbol Then Return Null
		Local pathKey:String = SnapshotPathKey(symbol.originPath)
		Local source:TSourceText = TSourceText(sourceCache.ValueForKey(pathKey))
		If Not source Then
			source = TBlitzMaxLspNavigation.SourceForPath(symbol.originPath, Null, documents)
			If source Then sourceCache.Insert(pathKey, source)
		End If
		If Not source Then Return Null
		Local span:TSourceSpan = CatalogueSpan(source, symbol)
		If Not span Then Return Null
		Local location:TJSONObject = JsonObject()
		location.Set("uri", TBlitzMaxLspNavigation.UriForPath(symbol.originPath, documents))
		location.Set("range", TLspPositions.Range(source, span))
		Return WorkspaceSymbolItem(symbol.name, CatalogueSymbolKind(symbol), entry.container, location)
	End Function

	Function CatalogueSpan:TSourceSpan(source:TSourceText, symbol:TModuleCatalogueSymbol)
		If Not source Or Not symbol Or symbol.originLine <= 0 Then Return Null
		Local line:Int = symbol.originLine - 1
		If line < 0 Or line >= source.LineCount() Then Return Null
		Local start:Int = source.Offset(line, Max(0, symbol.originColumn))
		Local lineEnd:Int = source.Offset(line, 2147483647)
		Local relative:Int = source.text[start..lineEnd].ToLower().Find(symbol.normalizedName)
		If relative >= 0 Then start :+ relative
		Return TSourceSpan.Create(start, symbol.name.length)
	End Function

	Function CatalogueSymbolKind:Int(symbol:TModuleCatalogueSymbol)
		If Not symbol Then Return 13
		Select symbol.kind
			Case SYMBOL_TYPE Return 5
			Case SYMBOL_STRUCT Return 23
			Case SYMBOL_INTERFACE Return 11
			Case SYMBOL_ENUM Return 10
			Case SYMBOL_ENUM_MEMBER Return 22
			Case SYMBOL_FIELD Return 8
			Case SYMBOL_CONST Return 14
			Case SYMBOL_ROUTINE
				If symbol.parent Then Return 6
				Return 12
		End Select
		Return 13
	End Function

	Function MatchScore:Int(name:String, container:String, query:String)
		If Not query.length Then Return 100
		Local normalizedName:String = name.ToLower()
		Local normalizedContainer:String = container.ToLower()
		If normalizedName = query Then Return 0
		If normalizedName.StartsWith(query) Then Return 10
		If normalizedName.Contains(query) Then Return 20
		Local qualified:String = normalizedContainer
		If qualified.length Then qualified :+ "."
		qualified :+ normalizedName
		If qualified.StartsWith(query) Then Return 30
		If qualified.Contains(query) Then Return 40
		Return -1
	End Function

	Function AppendEntry(entries:TWorkspaceSymbolEntry[] Var, score:Int, name:String, container:String, kind:Int, location:TJSONObject)
		If Not location Then Return
		Local entry:TWorkspaceSymbolEntry = New TWorkspaceSymbolEntry
		entry.score = score
		entry.normalizedName = name.ToLower()
		entry.normalizedContainer = container.ToLower()
		entry.item = WorkspaceSymbolItem(name, kind, container, location)
		entries :+ [entry]
	End Function

	Function WorkspaceSymbolItem:TJSONObject(name:String, kind:Int, container:String, location:TJSONObject)
		Local item:TJSONObject = JsonObject()
		item.Set("name", name)
		item.Set("kind", kind)
		item.Set("location", location)
		If container.length Then item.Set("containerName", container)
		Return item
	End Function

	Function ItemIdentity:String(item:TJSONObject)
		If Not item Then Return ""
		Local location:TJSONObject = TJSONObject(item.Get("location"))
		Local range:TJSONObject
		Local start:TJSONObject
		If location Then range = TJSONObject(location.Get("range"))
		If range Then start = TJSONObject(range.Get("start"))
		If Not location Or Not start Then Return item.GetString("name").ToLower()
		Return location.GetString("uri").ToLower() + "|" + start.GetInteger("line") + "|" + start.GetInteger("character") + "|" + item.GetString("name").ToLower() + "|" + item.GetInteger("kind")
	End Function

	Function SortEntries(entries:TWorkspaceSymbolEntry[] Var)
		If entries.length > 1 Then SortRange(entries, 0, entries.length - 1)
	End Function

	Function SortRange(entries:TWorkspaceSymbolEntry[] Var, first:Int, last:Int)
		Local left:Int = first
		Local right:Int = last
		Local pivot:TWorkspaceSymbolEntry = entries[first + (last - first) / 2]
		While left <= right
			While ComesBefore(entries[left], pivot)
				left :+ 1
			Wend
			While ComesBefore(pivot, entries[right])
				right :- 1
			Wend
			If left <= right Then
				Local swap:TWorkspaceSymbolEntry = entries[left]
				entries[left] = entries[right]
				entries[right] = swap
				left :+ 1
				right :- 1
			End If
		Wend
		If first < right Then SortRange(entries, first, right)
		If left < last Then SortRange(entries, left, last)
	End Function

	Function ComesBefore:Int(left:TWorkspaceSymbolEntry, right:TWorkspaceSymbolEntry)
		If left.score <> right.score Then Return left.score < right.score
		If left.normalizedName <> right.normalizedName Then Return left.normalizedName < right.normalizedName
		Return left.normalizedContainer < right.normalizedContainer
	End Function
End Type
