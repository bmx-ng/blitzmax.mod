' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import BRL.TextStream
Import BlitzMax.Language
Import "documents.bmx"
Import "documentation.bmx"
Import "workspace_analysis.bmx"
Import "installed_modules.bmx"

Type TLspCompilationOwners
	Field roots:String[] = New String[0]

	Method Add(rootPath:String)
		Local key:String = SnapshotPathKey(rootPath)
		For Local existing:String = EachIn roots
			If SnapshotPathKey(existing) = key Then Return
		Next
		roots :+ [rootPath]
	End Method

	Method Remove(rootPath:String)
		Local key:String = SnapshotPathKey(rootPath)
		Local remaining:String[]
		For Local existing:String = EachIn roots
			If SnapshotPathKey(existing) <> key Then remaining :+ [existing]
		Next
		roots = remaining
	End Method

	Method Preferred:String()
		If roots.length Then Return roots[roots.length - 1]
		Return ""
	End Method
End Type

' A logical BlitzMax analysis environment. This is deliberately distinct from
' both the LSP process and the editor's workspace-folder object.
Type TLspWorkspaceContext
	Field uri:String
	Field path:String
	Field name:String
	Field configuration:TLspWorkspaceConfiguration
	Field dependencyCache:TLspDependencyCache
	Field documents:TLspDocumentStore
	Field analyses:TMap = New TMap
	Field navigators:TMap = New TMap
	Field sourceDependencies:TMap = New TMap
	Field includeOwners:TMap = New TMap
	Field compilationDocuments:TMap = New TMap
	Field liveInterfaces:TMap = New TMap
	Field projectRoots:TMap = New TMap
	Field projectUnitSources:TMap = New TMap
	Field projectImports:TMap = New TMap
	Field projectAnalyses:TMap = New TMap
	Field projectDependencies:TMap = New TMap
	Field projectOwners:TMap = New TMap
	Field projectGraphDirty:Int = True
	Field documentationCache:TLspDocumentationCache = New TLspDocumentationCache
	Field installedCatalogues:TLspInstalledModuleCatalogueStore

	Function Create:TLspWorkspaceContext(uri:String, name:String, configuration:TLspWorkspaceConfiguration = Null, dependencyCache:TLspDependencyCache = Null, documents:TLspDocumentStore = Null, installedCatalogues:TLspInstalledModuleCatalogueStore = Null)
		Local context:TLspWorkspaceContext = New TLspWorkspaceContext
		context.uri = uri
		context.path = NormalizeWorkspacePath(FileUriToPath(uri))
		context.name = name
		If configuration Then context.configuration = configuration Else context.configuration = TLspWorkspaceConfiguration.CreateDefault()
		If dependencyCache Then context.dependencyCache = dependencyCache Else context.dependencyCache = New TLspDependencyCache
		context.documents = documents
		If installedCatalogues Then context.installedCatalogues = installedCatalogues Else context.installedCatalogues = New TLspInstalledModuleCatalogueStore
		Return context
	End Function

	Method ContainsPath:Int(documentPath:String)
		If path.length = 0 Then Return False
		Local candidate:String = NormalizeWorkspacePath(documentPath)
		If candidate = path Then Return True
		If path = "/" Then Return candidate.StartsWith(path)
		Return candidate.StartsWith(path + "/")
	End Method

	Method Analyze:TLanguageAnalysis(document:TLspDocument, cancellationToken:TLanguageCancellationToken = Null)
		EnsureProjectGraph(cancellationToken)
		Local projectRoot:String = ProjectRootForPath(document.path)
		If projectRoot.length Then
			Local projectAnalysis:TLanguageAnalysis = EnsureProjectAnalysis(projectRoot, cancellationToken)
			If projectAnalysis Then
				Local projectView:TLanguageAnalysis = projectAnalysis.ViewForDocument(document.path)
				If Not projectView Then projectView = projectAnalysis
				CacheView(document, projectView, TMap(projectDependencies.ValueForKey(SnapshotPathKey(projectRoot))))
				Return projectView
			End If
		End If
		Local rootPath:String = CompilationRootForPath(document.path)
		Local rootDocument:TLspDocument = document
		Local rootText:String = document.text
		If rootPath.length And SnapshotPathKey(rootPath) <> SnapshotPathKey(document.path) Then
			rootDocument = documents.GetByPath(rootPath)
			If rootDocument Then
				rootText = rootDocument.text
			Else If FileType(rootPath) = FILETYPE_FILE Then
				rootText = LoadText(rootPath)
			Else
				RemoveIncludeOwner(document.path, rootPath)
				rootPath = ""
				rootDocument = document
				rootText = document.text
			End If
		End If
		If Not rootPath.length Then rootPath = rootDocument.path

		Local result:TLanguageAnalysis
		Local unitDependencies:TMap = New TMap
		Local analysisOptions:TLanguageAnalysisOptions = configuration.AnalysisOptions()
		analysisOptions.cancellationToken = cancellationToken
		If configuration.useDependencySnapshots And configuration.sdkPath.length Then
			Local resolver:TLspFileSnapshotResolver = TLspFileSnapshotResolver.Create(configuration, dependencyCache, documents, liveInterfaces)
			result = TBlitzMaxLanguage.BuildAndAnalyze(rootPath, rootText, resolver, configuration.SnapshotOptions(), analysisOptions)
			unitDependencies = resolver.sourceDependencies
			If Not result.cancelled Then
				RegisterCompilationUnit(rootPath, result, unitDependencies)
				RefreshLiveInterface(rootPath, rootText, result, resolver)
			End If
		Else
			result = TBlitzMaxLanguage.AnalyzeText(rootText, rootPath, analysisOptions)
		End If
		If Not result.cancelled Then
			Local view:TLanguageAnalysis = result.ViewForDocument(document.path)
			If Not view And SnapshotPathKey(rootPath) <> SnapshotPathKey(document.path) Then Return Analyze(document, cancellationToken)
			If Not view Then view = result
			CacheView(document, view, unitDependencies)
			Return view
		End If
		Return result
	End Method

	Method EnsureProjectGraph(cancellationToken:TLanguageCancellationToken = Null)
		If Not projectGraphDirty Then Return
		ClearProjectGraph()
		projectGraphDirty = False
		Local rootPath:String = configuration.rootSourcePath
		If Not rootPath.length Or Not rootPath.ToLower().EndsWith(".bmx") Or FileType(rootPath) <> FILETYPE_FILE Then Return
		If Not DiscoverProjectRoot(rootPath, New TMap, cancellationToken) Then
			projectGraphDirty = True
			Return
		End If
		EnsureProjectAnalysis(rootPath, cancellationToken)
	End Method

	Method DiscoverProjectRoot:Int(rootPath:String, states:TMap, cancellationToken:TLanguageCancellationToken = Null)
		If LanguageCancellationRequested(cancellationToken) Then Return False
		Local rootKey:String = SnapshotPathKey(rootPath)
		If states.Contains(rootKey) Then Return True
		states.Insert(rootKey, "visiting")
		Local rootText:String = SourceTextForPath(rootPath)
		If rootText = Null Then Return True
		Local resolver:TLspFileSnapshotResolver = TLspFileSnapshotResolver.Create(configuration, dependencyCache, documents, liveInterfaces)
		Local sourceInterface:TInterfaceFile = TBlitzMaxSourceInterfaceBuilder.Build(rootPath, rootText, resolver, configuration.SnapshotOptions())
		Local unitSources:TMap = New TMap
		unitSources.Insert(rootKey, rootPath)
		projectOwners.Insert(rootKey, rootPath)
		For Local value:Object = EachIn resolver.includeDependencies.Values()
			Local includePath:String = String(value)
			unitSources.Insert(SnapshotPathKey(includePath), includePath)
			projectOwners.Insert(SnapshotPathKey(includePath), rootPath)
		Next
		projectRoots.Insert(rootKey, rootPath)
		projectUnitSources.Insert(rootKey, unitSources)
		projectDependencies.Insert(rootKey, resolver.sourceDependencies)
		Local imports:TMap = New TMap
		For Local item:TInterfaceImport = EachIn sourceInterface.imports
			If Not item.isFileImport Or Not item.name.ToLower().EndsWith(".bmx") Then Continue
			Local importingPath:String = rootPath
			If item.originPath.length Then importingPath = item.originPath
			Local dependencyPath:String = ResolveRelativePath(importingPath, item.name)
			resolver.RecordSourceDependency(dependencyPath)
			imports.Insert(SnapshotPathKey(dependencyPath), dependencyPath)
			If SnapshotPathKey(dependencyPath) <> rootKey And Not DiscoverProjectRoot(dependencyPath, states, cancellationToken) Then Return False
		Next
		projectImports.Insert(rootKey, imports)
		states.Insert(rootKey, "loaded")
		Return True
	End Method

	Method EnsureProjectAnalysis:TLanguageAnalysis(rootPath:String, cancellationToken:TLanguageCancellationToken = Null)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local existing:TLanguageAnalysis = TLanguageAnalysis(projectAnalyses.ValueForKey(rootKey))
		If existing Then Return existing
		Return BuildProjectAnalysis(rootPath, True, cancellationToken)
	End Method

	Method ProjectFeatureAnalysis:TLanguageAnalysis(rootPath:String, cancellationToken:TLanguageCancellationToken = Null)
		Local existing:TLanguageAnalysis = TLanguageAnalysis(projectAnalyses.ValueForKey(SnapshotPathKey(rootPath)))
		If existing Then Return existing
		Return BuildProjectAnalysis(rootPath, False, cancellationToken)
	End Method

	Method BuildProjectAnalysis:TLanguageAnalysis(rootPath:String, retain:Int, cancellationToken:TLanguageCancellationToken = Null)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local rootText:String = SourceTextForPath(rootPath)
		If rootText = Null Then Return Null
		Local resolver:TLspFileSnapshotResolver = TLspFileSnapshotResolver.Create(configuration, dependencyCache, documents, liveInterfaces)
		Local analysis:TLanguageAnalysis = TBlitzMaxLanguage.BuildAndAnalyze(rootPath, rootText, resolver, configuration.SnapshotOptions(), ProjectAnalysisOptions(cancellationToken))
		If Not analysis.cancelled And retain Then
			RegisterCompilationUnit(rootPath, analysis, resolver.sourceDependencies)
			projectAnalyses.Insert(rootKey, analysis)
			projectDependencies.Insert(rootKey, resolver.sourceDependencies)
		End If
		Return analysis
	End Method

	Method ProjectCandidateRoots:String[](identifier:String, targetOriginPath:String = "", cancellationToken:TLanguageCancellationToken = Null)
		EnsureProjectGraph(cancellationToken)
		Local normalized:String = identifier.Trim().ToLower()
		If Not normalized.length Then Return []
		Local targetRoot:String = ProjectRootForPath(targetOriginPath)
		Local result:String[]
		For Local value:Object = EachIn projectRoots.Values()
			Local rootPath:String = String(value)
			If targetRoot.length And Not ProjectRootReaches(rootPath, targetRoot, New TMap) Then Continue
			Local sources:TMap = TMap(projectUnitSources.ValueForKey(SnapshotPathKey(rootPath)))
			If ProjectSourcesContain(sources, normalized) Then result :+ [rootPath]
		Next
		Return result
	End Method

	Method ProjectRootReaches:Int(rootPath:String, targetRoot:String, visited:TMap)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local targetKey:String = SnapshotPathKey(targetRoot)
		If rootKey = targetKey Then Return True
		If visited.Contains(rootKey) Then Return False
		visited.Insert(rootKey, rootPath)
		Local imports:TMap = TMap(projectImports.ValueForKey(rootKey))
		If Not imports Then Return False
		For Local value:Object = EachIn imports.Values()
			If ProjectRootReaches(String(value), targetRoot, visited) Then Return True
		Next
		Return False
	End Method

	Method ProjectSourcesContain:Int(sources:TMap, normalizedIdentifier:String)
		If Not sources Then Return False
		For Local value:Object = EachIn sources.Values()
			Local text:String = SourceTextForPath(String(value))
			If text <> Null And text.ToLower().Find(normalizedIdentifier) >= 0 Then Return True
		Next
		Return False
	End Method

	Method ProjectAnalysisOptions:TLanguageAnalysisOptions(cancellationToken:TLanguageCancellationToken)
		Local result:TLanguageAnalysisOptions = configuration.AnalysisOptions()
		result.cancellationToken = cancellationToken
		Return result
	End Method

	Method SourceTextForPath:String(sourcePath:String)
		If documents Then
			Local document:TLspDocument = documents.GetByPath(sourcePath)
			If document Then Return document.text
		End If
		If FileType(sourcePath) = FILETYPE_FILE Then Return LoadText(sourcePath)
		Return Null
	End Method

	Method ProjectRootForPath:String(documentPath:String)
		Return String(projectOwners.ValueForKey(SnapshotPathKey(documentPath)))
	End Method

	Method ProjectAnalysisCount:Int()
		Local count:Int
		For Local value:Object = EachIn projectAnalyses.Values()
			count :+ 1
		Next
		Return count
	End Method

	Method ProjectRootCount:Int()
		Local count:Int
		For Local value:Object = EachIn projectRoots.Values()
			count :+ 1
		Next
		Return count
	End Method

	Method MarkProjectGraphDirty(changedPath:String = "")
		If Not configuration.rootSourcePath.length Or projectGraphDirty Then Return
		If Not changedPath.length Or SnapshotPathKey(changedPath) = SnapshotPathKey(configuration.rootSourcePath) Or projectOwners.Contains(SnapshotPathKey(changedPath)) Then
			projectGraphDirty = True
			Return
		End If
		For Local value:Object = EachIn projectDependencies.Values()
			Local dependencies:TMap = TMap(value)
			If dependencies And dependencies.Contains(SnapshotPathKey(changedPath)) Then projectGraphDirty = True; Return
		Next
	End Method

	Method ClearProjectGraph()
		For Local value:Object = EachIn projectRoots.Values()
			Local rootPath:String = String(value)
			ClearCompilationUnit(rootPath)
			liveInterfaces.Remove(SnapshotPathKey(rootPath))
		Next
		projectRoots.Clear()
		projectUnitSources.Clear()
		projectImports.Clear()
		projectAnalyses.Clear()
		projectDependencies.Clear()
		projectOwners.Clear()
	End Method

	Method RefreshLiveInterface(rootPath:String, rootText:String, analysis:TLanguageAnalysis, resolver:TLspFileSnapshotResolver)
		If Not analysis Or Not analysis.Succeeded() Or Not analysis.snapshot Then Return
		Local hasLiveOverlay:Int
		If documents Then
			For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
				Local openDocument:TLspDocument = documents.GetByPath(sourceDocument.path)
				If openDocument And openDocument.liveOverlay Then hasLiveOverlay = True; Exit
			Next
		End If
		Local key:String = SnapshotPathKey(rootPath)
		If Not hasLiveOverlay Then
			liveInterfaces.Remove(key)
			Return
		End If
		Local sourceInterface:TInterfaceFile = TBlitzMaxSourceInterfaceBuilder.Build(rootPath, rootText, resolver, configuration.SnapshotOptions())
		liveInterfaces.Insert(key, TSnapshotText.CreateInterface(rootPath, sourceInterface))
	End Method

	Method CacheView(document:TLspDocument, analysis:TLanguageAnalysis, dependencies:TMap)
		If Not document Or Not analysis Then Return
		analyses.Insert(document.uri, analysis)
		If analysis.syntaxTree Then navigators.Insert(document.uri, TSyntaxNavigator.Create(analysis.syntaxTree)) Else navigators.Remove(document.uri)
		If dependencies Then sourceDependencies.Insert(document.uri, dependencies) Else sourceDependencies.Insert(document.uri, New TMap)
	End Method

	Method RegisterCompilationUnit(rootPath:String, analysis:TLanguageAnalysis, dependencies:TMap)
		ClearCompilationUnit(rootPath)
		If Not analysis Or Not analysis.snapshot Then Return
		Local members:TMap = New TMap
		For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
			If Not sourceDocument Then Continue
			members.Insert(SnapshotPathKey(sourceDocument.path), sourceDocument.path)
			If SnapshotPathKey(sourceDocument.path) <> SnapshotPathKey(rootPath) Then AddIncludeOwner(sourceDocument.path, rootPath)
			If documents Then
				Local openDocument:TLspDocument = documents.GetByPath(sourceDocument.path)
				If openDocument Then
					Local view:TLanguageAnalysis = analysis.ViewForDocument(sourceDocument.path)
					If view Then CacheView(openDocument, view, dependencies)
				End If
			End If
		Next
		compilationDocuments.Insert(SnapshotPathKey(rootPath), members)
	End Method

	Method ClearCompilationUnit(rootPath:String)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local members:TMap = TMap(compilationDocuments.ValueForKey(rootKey))
		If members Then
			For Local value:Object = EachIn members.Values()
				RemoveIncludeOwner(String(value), rootPath)
			Next
		End If
		compilationDocuments.Remove(rootKey)
	End Method

	Method AddIncludeOwner(documentPath:String, rootPath:String)
		Local key:String = SnapshotPathKey(documentPath)
		Local owners:TLspCompilationOwners = TLspCompilationOwners(includeOwners.ValueForKey(key))
		If Not owners Then
			owners = New TLspCompilationOwners
			includeOwners.Insert(key, owners)
		End If
		owners.Add(rootPath)
	End Method

	Method RemoveIncludeOwner(documentPath:String, rootPath:String)
		Local key:String = SnapshotPathKey(documentPath)
		Local owners:TLspCompilationOwners = TLspCompilationOwners(includeOwners.ValueForKey(key))
		If Not owners Then Return
		owners.Remove(rootPath)
		If owners.roots.length = 0 Then includeOwners.Remove(key)
	End Method

	Method CompilationRootForPath:String(documentPath:String)
		Local owners:TLspCompilationOwners = TLspCompilationOwners(includeOwners.ValueForKey(SnapshotPathKey(documentPath)))
		If owners Then Return owners.Preferred()
		Return ""
	End Method

	Method IsDocumentInCompilationUnit:Int(documentPath:String, rootPath:String)
		Local members:TMap = TMap(compilationDocuments.ValueForKey(SnapshotPathKey(rootPath)))
		Return members And members.Contains(SnapshotPathKey(documentPath))
	End Method

	Method InvalidateLiveInterfaceForPath(documentPath:String)
		Local rootPath:String = CompilationRootForPath(documentPath)
		If Not rootPath.length Then rootPath = documentPath
		liveInterfaces.Remove(SnapshotPathKey(rootPath))
	End Method

	Method LatestAnalysis:TLanguageAnalysis(uri:String)
		Return TLanguageAnalysis(analyses.ValueForKey(uri))
	End Method

	Method LatestNavigator:TSyntaxNavigator(uri:String)
		Return TSyntaxNavigator(navigators.ValueForKey(uri))
	End Method

	Method Documentation:TDocumentationComment(symbol:TSymbol)
		Return documentationCache.Resolve(PreferredSourceSymbol(symbol), documents)
	End Method

	Method PreferredSourceSymbol:TSymbol(symbol:TSymbol)
		If Not symbol Or Not symbol.isImported Then Return symbol
		Local expectedRoot:String = SourcePathForInterface(symbol.originPath)
		For Local value:Object = EachIn analyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			If Not analysis Or Not analysis.model Or Not analysis.snapshot Or Not analysis.snapshot.rootDocument Then Continue
			If expectedRoot.length And Not AnalysisContainsSourcePath(analysis, expectedRoot) Then Continue
			Local candidate:TSymbol = MatchingSourceSymbol(analysis.model.globalScope, symbol)
			If candidate Then Return candidate
		Next
		Return symbol
	End Method

	Function AnalysisContainsSourcePath:Int(analysis:TLanguageAnalysis, path:String)
		If Not analysis Or Not analysis.snapshot Then Return False
		Local key:String = SnapshotPathKey(path)
		For Local document:TSourceDocumentModel = EachIn analysis.snapshot.documents
			If document And SnapshotPathKey(document.path) = key Then Return True
		Next
		Return False
	End Function

	Method MatchingSourceSymbol:TSymbol(scope:TScope, imported:TSymbol)
		If Not scope Then Return Null
		For Local candidate:TSymbol = EachIn scope.declaredSymbols
			If Not candidate.isImported And SourceSymbolsMatch(candidate, imported) Then Return candidate
			If candidate.memberScope Then
				Local nested:TSymbol = MatchingSourceSymbol(candidate.memberScope, imported)
				If nested Then Return nested
			End If
		Next
		Return Null
	End Method

	Function SourceSymbolsMatch:Int(candidate:TSymbol, imported:TSymbol)
		If Not candidate Or Not imported Or candidate.kind <> imported.kind Then Return False
		If candidate.QualifiedName().ToLower() <> imported.QualifiedName().ToLower() Then Return False
		If candidate.kind <> SYMBOL_ROUTINE Then Return True
		If candidate.parameterTypes.length <> imported.parameterTypes.length Then Return False
		For Local index:Int = 0 Until candidate.parameterTypes.length
			If Not candidate.parameterTypes[index] Or Not imported.parameterTypes[index] Then Return False
			If candidate.parameterTypes[index].DisplayName().ToLower() <> imported.parameterTypes[index].DisplayName().ToLower() Then Return False
		Next
		Return True
	End Function

	Function SourcePathForInterface:String(path:String)
		Local normalized:String = path.Replace(Chr(92), "/")
		If normalized.ToLower().EndsWith(".bmx") Then Return normalized
		Local directory:String = ExtractDir(normalized)
		If StripDir(directory).ToLower() <> ".bmx" Then Return ""
		Local fileName:String = StripDir(normalized)
		Local marker:Int = fileName.ToLower().Find(".bmx.")
		If marker < 0 Then Return ""
		Return ExtractDir(directory) + "/" + fileName[..marker + 4]
	End Function

	Method InstalledCatalogue:TLspInstalledModuleCatalogue()
		Return installedCatalogues.Ensure(configuration, dependencyCache)
	End Method

	Method InstalledModuleNames:String[]()
		Return installedCatalogues.Names(configuration)
	End Method

	Method Forget(uri:String)
		analyses.Remove(uri)
		navigators.Remove(uri)
		sourceDependencies.Remove(uri)
	End Method

	Method DependsOnPath:Int(uri:String, path:String)
		Local dependencies:TMap = TMap(sourceDependencies.ValueForKey(uri))
		If Not dependencies Then Return False
		Return dependencies.Contains(SnapshotPathKey(path))
	End Method

	Method ClearAnalyses()
		analyses.Clear()
		navigators.Clear()
		sourceDependencies.Clear()
		includeOwners.Clear()
		compilationDocuments.Clear()
		liveInterfaces.Clear()
		projectRoots.Clear()
		projectUnitSources.Clear()
		projectImports.Clear()
		projectAnalyses.Clear()
		projectDependencies.Clear()
		projectOwners.Clear()
		projectGraphDirty = True
		documentationCache.Clear()
	End Method
End Type

Type TLspWorkspaceStore
	Field contexts:TMap = New TMap
	Field contextCount:Int
	Field defaultConfiguration:TLspWorkspaceConfiguration = TLspWorkspaceConfiguration.CreateDefault()
	Field dependencyCache:TLspDependencyCache = New TLspDependencyCache
	Field installedCatalogues:TLspInstalledModuleCatalogueStore = New TLspInstalledModuleCatalogueStore
	Field adHoc:TLspWorkspaceContext
	Field documents:TLspDocumentStore

	Method New()
		adHoc = TLspWorkspaceContext.Create("", "Ad hoc", defaultConfiguration.Copy(), dependencyCache, documents, installedCatalogues)
	End Method

	Method SetDocuments(documentStore:TLspDocumentStore)
		documents = documentStore
		adHoc.documents = documentStore
		For Local context:TLspWorkspaceContext = EachIn contexts.Values()
			context.documents = documentStore
		Next
	End Method

	Method Add:TLspWorkspaceContext(uri:String, name:String)
		Local context:TLspWorkspaceContext = Get(uri)
		If context Then
			context.name = name
			Return context
		End If
		context = TLspWorkspaceContext.Create(uri, name, defaultConfiguration.Copy(), dependencyCache, documents, installedCatalogues)
		contexts.Insert(uri, context)
		contextCount :+ 1
		Return context
	End Method

	Method Remove:TLspWorkspaceContext(uri:String)
		Local context:TLspWorkspaceContext = Get(uri)
		If context Then
			contexts.Remove(uri)
			contextCount :- 1
		End If
		Return context
	End Method

	Method Get:TLspWorkspaceContext(uri:String)
		Return TLspWorkspaceContext(contexts.ValueForKey(uri))
	End Method

	Method ContextForPath:TLspWorkspaceContext(documentPath:String)
		Local best:TLspWorkspaceContext
		For Local context:TLspWorkspaceContext = EachIn contexts.Values()
			If context.ContainsPath(documentPath) And (Not best Or context.path.length > best.path.length) Then best = context
		Next
		If best Then Return best
		Return adHoc
	End Method

	Method Count:Int()
		Return contextCount
	End Method

	Method ApplyDefaultConfiguration(settings:TJSONObject)
		defaultConfiguration.ApplyJson(settings)
		adHoc.configuration = defaultConfiguration.Copy()
		adHoc.ClearAnalyses()
		For Local context:TLspWorkspaceContext = EachIn contexts.Values()
			context.configuration = defaultConfiguration.Copy()
			context.ClearAnalyses()
		Next
	End Method

	Method ClearAnalyses()
		adHoc.ClearAnalyses()
		For Local context:TLspWorkspaceContext = EachIn contexts.Values()
			context.ClearAnalyses()
		Next
	End Method

	Method RefreshCatalogues()
		Local refreshed:TMap = New TMap
		Local key:String = TLspInstalledModuleCatalogue.ConfigurationKeyFor(adHoc.configuration)
		installedCatalogues.Refresh(adHoc.configuration, dependencyCache)
		installedCatalogues.RefreshNames(adHoc.configuration)
		refreshed.Insert(key, adHoc)
		For Local context:TLspWorkspaceContext = EachIn contexts.Values()
			key = TLspInstalledModuleCatalogue.ConfigurationKeyFor(context.configuration)
			If refreshed.Contains(key) Then Continue
			installedCatalogues.Refresh(context.configuration, dependencyCache)
			installedCatalogues.RefreshNames(context.configuration)
			refreshed.Insert(key, context)
		Next
	End Method

	Method ClearCatalogues()
		installedCatalogues.Clear()
	End Method
End Type
