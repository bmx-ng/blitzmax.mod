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

Type TLspProjectAnalysisProgress Abstract
	Method Begin(rootPath:String, workspaceName:String) Abstract
	Method Report(message:String) Abstract
	Method Finish(message:String) Abstract
End Type

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
	Field projectInterfaceFingerprints:TMap = New TMap
	Field projectSourceSearchTerms:TMap = New TMap
	Field projectRootSearchTerms:TMap = New TMap
	Field projectExactTermRoots:TMap = New TMap
	Field projectReachability:TMap = New TMap
	Field projectGraphDirty:Int = True
	Field documentationCache:TLspDocumentationCache = New TLspDocumentationCache
	Field installedCatalogues:TLspInstalledModuleCatalogueStore
	Field projectProgress:TLspProjectAnalysisProgress

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
		Local rootPath:String = configuration.rootSourcePath
		If Not rootPath.length Or Not rootPath.ToLower().EndsWith(".bmx") Or FileType(rootPath) <> FILETYPE_FILE Then
			ClearProjectGraph()
			projectGraphDirty = False
			Return
		End If
		If projectProgress Then projectProgress.Begin(rootPath, name)
		ClearProjectGraph()
		projectGraphDirty = False
		If projectProgress Then projectProgress.Report("Discovering source dependencies")
		If Not DiscoverProjectRoot(rootPath, New TMap, cancellationToken) Then
			projectGraphDirty = True
			If projectProgress Then projectProgress.Finish("Project analysis cancelled")
			Return
		End If
		If projectProgress Then projectProgress.Report("Analysing " + StripDir(rootPath))
		EnsureProjectAnalysis(rootPath, cancellationToken)
		If projectProgress Then projectProgress.Finish("Project analysis ready")
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
		For Local value:Object = EachIn unitSources.Values()
			IndexProjectSource(String(value))
		Next
		projectRoots.Insert(rootKey, rootPath)
		projectUnitSources.Insert(rootKey, unitSources)
		IndexProjectRootSearch(rootPath)
		projectDependencies.Insert(rootKey, resolver.sourceDependencies)
		projectInterfaceFingerprints.Insert(rootKey, ProjectInterfaceFingerprint(sourceInterface))
		liveInterfaces.Insert(rootKey, TSnapshotText.CreateInterface(rootPath, sourceInterface))
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
		Local candidateRoots:TMap = projectRoots
		If targetRoot.length Then
			candidateRoots = TMap(projectExactTermRoots.ValueForKey(normalized))
			If Not candidateRoots Then Return []
		End If
		Local result:String[]
		For Local value:Object = EachIn candidateRoots.Values()
			Local rootPath:String = String(value)
			If targetRoot.length And Not ProjectRootReaches(rootPath, targetRoot) Then Continue
			If targetRoot.length Or ProjectRootContains(rootPath, normalized) Then result :+ [rootPath]
		Next
		Return result
	End Method

	Method ProjectRootReaches:Int(rootPath:String, targetRoot:String)
		Local cacheKey:String = SnapshotPathKey(rootPath) + "~n" + SnapshotPathKey(targetRoot)
		If projectReachability.Contains(cacheKey) Then Return String(projectReachability.ValueForKey(cacheKey)) = "1"
		Local result:Int = ProjectRootReachesCore(rootPath, targetRoot, New TMap)
		If result Then projectReachability.Insert(cacheKey, "1") Else projectReachability.Insert(cacheKey, "0")
		Return result
	End Method

	Method ProjectRootReachesCore:Int(rootPath:String, targetRoot:String, visited:TMap)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local targetKey:String = SnapshotPathKey(targetRoot)
		If rootKey = targetKey Then Return True
		If visited.Contains(rootKey) Then Return False
		visited.Insert(rootKey, rootPath)
		Local imports:TMap = TMap(projectImports.ValueForKey(rootKey))
		If Not imports Then Return False
		For Local value:Object = EachIn imports.Values()
			If ProjectRootReachesCore(String(value), targetRoot, visited) Then Return True
		Next
		Return False
	End Method

	Method ProjectRootContains:Int(rootPath:String, normalizedIdentifier:String)
		Local terms:TMap = TMap(projectRootSearchTerms.ValueForKey(SnapshotPathKey(rootPath)))
		If Not terms Then Return False
		For Local term:Object = EachIn terms.Keys()
			If String(term).Find(normalizedIdentifier) >= 0 Then Return True
		Next
		Return False
	End Method

	Method IndexProjectSource(sourcePath:String)
		Local text:String = SourceTextForPath(sourcePath)
		If text = Null Then
			projectSourceSearchTerms.Remove(SnapshotPathKey(sourcePath))
			Return
		End If
		Local terms:TMap = New TMap
		Local start:Int = -1
		For Local index:Int = 0 To text.length
			Local character:Int
			If index < text.length Then character = text[index]
			Local isIdentifier:Int = character >= Asc("A") And character <= Asc("Z") Or character >= Asc("a") And character <= Asc("z") Or character >= Asc("0") And character <= Asc("9") Or character = Asc("_") Or character > 127
			If isIdentifier Then
				If start < 0 Then start = index
			Else If start >= 0 Then
				terms.Insert(text[start..index].ToLower(), text[start..index])
				start = -1
			End If
		Next
		projectSourceSearchTerms.Insert(SnapshotPathKey(sourcePath), terms)
	End Method

	Method IndexProjectRootSearch(rootPath:String)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local previous:TMap = TMap(projectRootSearchTerms.ValueForKey(rootKey))
		If previous Then
			For Local term:Object = EachIn previous.Keys()
				Local roots:TMap = TMap(projectExactTermRoots.ValueForKey(term))
				If Not roots Then Continue
				roots.Remove(rootKey)
				Local hasRoot:Int
				For Local unused:Object = EachIn roots.Keys()
					hasRoot = True
					Exit
				Next
				If Not hasRoot Then projectExactTermRoots.Remove(term)
			Next
		End If
		Local terms:TMap = New TMap
		Local sources:TMap = TMap(projectUnitSources.ValueForKey(rootKey))
		If sources Then
			For Local sourceValue:Object = EachIn sources.Values()
				Local sourceTerms:TMap = TMap(projectSourceSearchTerms.ValueForKey(SnapshotPathKey(String(sourceValue))))
				If Not sourceTerms Then Continue
				For Local term:Object = EachIn sourceTerms.Keys()
					terms.Insert(term, term)
				Next
			Next
		End If
		projectRootSearchTerms.Insert(rootKey, terms)
		For Local term:Object = EachIn terms.Keys()
			Local roots:TMap = TMap(projectExactTermRoots.ValueForKey(term))
			If Not roots Then
				roots = New TMap
				projectExactTermRoots.Insert(term, roots)
			End If
			roots.Insert(rootKey, rootPath)
		Next
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

	' Refreshes the lightweight source interface for one project root. Routine-body
	' edits retain importing analyses; declaration changes invalidate only roots
	' which can reach the changed source. Include/import membership changes still
	' request a complete graph discovery because ownership may have changed.
	Method RefreshProjectPath(changedPath:String)
		If Not configuration.rootSourcePath.length Or projectGraphDirty Or Not changedPath.length Then Return
		Local changedKey:String = SnapshotPathKey(changedPath)
		Local ownerPath:String = ProjectRootForPath(changedPath)
		If Not ownerPath.length Then
			For Local value:Object = EachIn projectDependencies.Values()
				Local dependencies:TMap = TMap(value)
				If dependencies And dependencies.Contains(changedKey) Then projectGraphDirty = True; Return
			Next
			Return
		End If

		Local ownerKey:String = SnapshotPathKey(ownerPath)
		Local sourceText:String = SourceTextForPath(ownerPath)
		If sourceText = Null Then projectGraphDirty = True; Return
		Local resolver:TLspFileSnapshotResolver = TLspFileSnapshotResolver.Create(configuration, dependencyCache, documents, liveInterfaces)
		Local sourceInterface:TInterfaceFile = TBlitzMaxSourceInterfaceBuilder.Build(ownerPath, sourceText, resolver, configuration.SnapshotOptions())
		Local unitSources:TMap = New TMap
		unitSources.Insert(ownerKey, ownerPath)
		For Local value:Object = EachIn resolver.includeDependencies.Values()
			Local includePath:String = String(value)
			unitSources.Insert(SnapshotPathKey(includePath), includePath)
		Next
		Local imports:TMap = ProjectSourceImports(ownerPath, sourceInterface, resolver)
		If Not MapsHaveSameKeys(unitSources, TMap(projectUnitSources.ValueForKey(ownerKey))) Or Not MapsHaveSameKeys(imports, TMap(projectImports.ValueForKey(ownerKey))) Then
			projectGraphDirty = True
			Return
		End If

		Local previousFingerprint:String = String(projectInterfaceFingerprints.ValueForKey(ownerKey))
		Local currentFingerprint:String = ProjectInterfaceFingerprint(sourceInterface)
		projectDependencies.Insert(ownerKey, resolver.sourceDependencies)
		projectInterfaceFingerprints.Insert(ownerKey, currentFingerprint)
		liveInterfaces.Insert(ownerKey, TSnapshotText.CreateInterface(ownerPath, sourceInterface))
		IndexProjectSource(changedPath)
		IndexProjectRootSearch(ownerPath)
		InvalidateProjectAnalysis(ownerPath)
		If previousFingerprint <> currentFingerprint Then
			Local affectedRoots:String[]
			For Local value:Object = EachIn projectRoots.Values()
				Local rootPath:String = String(value)
				If SnapshotPathKey(rootPath) <> ownerKey And ProjectRootReaches(rootPath, ownerPath) Then affectedRoots :+ [rootPath]
			Next
			For Local rootPath:String = EachIn affectedRoots
				InvalidateProjectAnalysis(rootPath)
			Next
		End If
	End Method

	Method RefreshWatchedPath(changedPath:String)
		If Not changedPath.length Then Return
		If changedPath.ToLower().EndsWith(".bmx") Then RefreshProjectPath(changedPath); Return
		If projectGraphDirty Then Return
		Local changedKey:String = SnapshotPathKey(changedPath)
		Local directlyAffected:String[]
		For Local key:Object = EachIn projectDependencies.Keys()
			Local dependencies:TMap = TMap(projectDependencies.ValueForKey(key))
			If dependencies And dependencies.Contains(changedKey) Then directlyAffected :+ [String(projectRoots.ValueForKey(key))]
		Next
		If Not directlyAffected.length Then Return
		Local affected:TMap = New TMap
		For Local directRoot:String = EachIn directlyAffected
			For Local value:Object = EachIn projectRoots.Values()
				Local rootPath:String = String(value)
				If ProjectRootReaches(rootPath, directRoot) Then affected.Insert(SnapshotPathKey(rootPath), rootPath)
			Next
		Next
		For Local value:Object = EachIn affected.Values()
			InvalidateProjectAnalysis(String(value))
		Next
	End Method

	Method ProjectSourceImports:TMap(rootPath:String, sourceInterface:TInterfaceFile, resolver:TLspFileSnapshotResolver)
		Local imports:TMap = New TMap
		If Not sourceInterface Then Return imports
		For Local item:TInterfaceImport = EachIn sourceInterface.imports
			If Not item.isFileImport Or Not item.name.ToLower().EndsWith(".bmx") Then Continue
			Local importingPath:String = rootPath
			If item.originPath.length Then importingPath = item.originPath
			Local dependencyPath:String = ResolveRelativePath(importingPath, item.name)
			If resolver Then resolver.RecordSourceDependency(dependencyPath)
			imports.Insert(SnapshotPathKey(dependencyPath), dependencyPath)
		Next
		Return imports
	End Method

	Function MapsHaveSameKeys:Int(left:TMap, right:TMap)
		If Not left Or Not right Then Return left = right
		Local leftCount:Int
		For Local key:Object = EachIn left.Keys()
			leftCount :+ 1
			If Not right.Contains(key) Then Return False
		Next
		Local rightCount:Int
		For Local key:Object = EachIn right.Keys()
			rightCount :+ 1
		Next
		Return leftCount = rightCount
	End Function

	Method InvalidateProjectAnalysis(rootPath:String)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local previous:TLanguageAnalysis = TLanguageAnalysis(projectAnalyses.ValueForKey(rootKey))
		projectAnalyses.Remove(rootKey)
		If Not previous Then Return
		Local staleUris:String[]
		For Local key:Object = EachIn analyses.Keys()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(analyses.ValueForKey(key))
			If analysis And analysis.snapshot = previous.snapshot Then staleUris :+ [String(key)]
		Next
		For Local uri:String = EachIn staleUris
			' Keep the dependency set long enough for ReanalyzeAffected to route the
			' change to open importing documents. Their replacement views refresh it.
			analyses.Remove(uri)
			navigators.Remove(uri)
		Next
	End Method

	Method ProjectInterfaceFingerprint:String(sourceInterface:TInterfaceFile)
		If Not sourceInterface Then Return ""
		Local sourceCache:TMap = New TMap
		If sourceInterface.sourceText <> Null Then sourceCache.Insert(SnapshotPathKey(sourceInterface.path), TSourceText.Create(sourceInterface.sourceText, sourceInterface.path))
		Local result:String = "strict=" + sourceInterface.isSuperStrict + "~n"
		For Local item:TInterfaceImport = EachIn sourceInterface.imports
			result :+ "import=" + item.isFileImport + ":" + item.name.ToLower() + ":" + SnapshotPathKey(item.originPath) + "~n"
		Next
		For Local record:TInterfaceRecord = EachIn sourceInterface.declarations
			AppendProjectRecordFingerprint(result, record, sourceInterface.path, sourceCache)
		Next
		Return result
	End Method

	Method AppendProjectRecordFingerprint(value:String Var, record:TInterfaceRecord, defaultPath:String, sourceCache:TMap)
		If Not record Then Return
		value :+ record.kind + ":" + record.name.ToLower() + ":" + record.flags + ":" + record.visibility + ":"
		Local sourcePath:String = record.originPath
		If Not sourcePath.length Then sourcePath = defaultPath
		Local source:TSourceText = TSourceText(sourceCache.ValueForKey(SnapshotPathKey(sourcePath)))
		If Not source Then
			Local text:String = SourceTextForPath(sourcePath)
			If text <> Null Then
				source = TSourceText.Create(text, sourcePath)
				sourceCache.Insert(SnapshotPathKey(sourcePath), source)
			End If
		End If
		If source Then
			If record.routineSignature Then
				value :+ source.Slice(record.routineSignature.span)
			Else If record.typeHeaderSyntax Then
				value :+ source.Slice(record.typeHeaderSyntax.span)
			Else If record.declarationSyntax Then
				value :+ source.Slice(record.declarationSyntax.span)
			Else
				value :+ record.signatureText + record.rawText
			End If
		Else
			value :+ record.signatureText + record.rawText
		End If
		value :+ "~n"
		For Local member:TInterfaceRecord = EachIn record.members
			AppendProjectRecordFingerprint(value, member, sourcePath, sourceCache)
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
		projectInterfaceFingerprints.Clear()
		projectSourceSearchTerms.Clear()
		projectRootSearchTerms.Clear()
		projectExactTermRoots.Clear()
		projectReachability.Clear()
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
		projectInterfaceFingerprints.Clear()
		projectSourceSearchTerms.Clear()
		projectRootSearchTerms.Clear()
		projectExactTermRoots.Clear()
		projectReachability.Clear()
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
	Field projectProgress:TLspProjectAnalysisProgress

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

	Method SetProjectProgress(progress:TLspProjectAnalysisProgress)
		projectProgress = progress
		adHoc.projectProgress = progress
		For Local context:TLspWorkspaceContext = EachIn contexts.Values()
			context.projectProgress = progress
		Next
	End Method

	Method Add:TLspWorkspaceContext(uri:String, name:String)
		Local context:TLspWorkspaceContext = Get(uri)
		If context Then
			context.name = name
			Return context
		End If
		context = TLspWorkspaceContext.Create(uri, name, defaultConfiguration.Copy(), dependencyCache, documents, installedCatalogues)
		context.projectProgress = projectProgress
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

	Method RefreshWatchedPath(path:String)
		adHoc.RefreshWatchedPath(path)
		For Local context:TLspWorkspaceContext = EachIn contexts.Values()
			context.RefreshWatchedPath(path)
		Next
	End Method
End Type
