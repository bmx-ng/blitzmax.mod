' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language
Import "documents.bmx"
Import "navigation_features.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

' Standard LSP 3.17 type hierarchy support. BlitzMax Struct declarations are
' deliberately excluded because the language does not currently permit them to
' participate in inheritance.
Type TBlitzMaxLspTypeHierarchy
	Function Prepare:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Or Not context.location Then Return JsonNull()
		Local symbol:TSymbol = HierarchySymbol(context.location)
		If Not Supported(symbol) Then Return JsonNull()
		Local item:TJSONObject = Item(symbol, context.analysis, document.uri, documents)
		If Not item Then Return JsonNull()
		Local result:TJSONArray = JsonArray()
		result.Append(item)
		Return result
	End Function

	Function Supertypes:TJSON(item:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		Local resolved:TLspTypeHierarchyResolution = Resolve(item, workspace)
		If Not resolved Then Return result
		Local info:TTypeInheritanceInfo = resolved.analysis.model.InheritanceInfo(resolved.symbol)
		If Not info Then Return result
		Local seen:TMap = New TMap
		AppendSupertypes(result, info.baseEdges, resolved.analysis, resolved.analysisUri, documents, seen)
		AppendSupertypes(result, info.interfaceEdges, resolved.analysis, resolved.analysisUri, documents, seen)
		Return result
	End Function

	Function Subtypes:TJSON(item:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		Local resolved:TLspTypeHierarchyResolution = Resolve(item, workspace)
		If Not resolved Then Return result
		Local targetKey:String = SymbolKey(resolved.symbol)
		If Not targetKey.length Then Return result
		Local seen:TMap = New TMap
		For Local key:Object = EachIn workspace.analyses.Keys()
			Local analysisUri:String = String(key)
			Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(analysisUri)
			If analysis And analysis.model Then AppendSubtypes(result, analysis.model.globalScope, analysis, analysisUri, targetKey, documents, seen)
		Next
		For Local value:Object = EachIn workspace.projectAnalyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			If analysis And analysis.model And analysis.snapshot And analysis.snapshot.rootDocument Then
				Local analysisUri:String = FileUriForPath(analysis.snapshot.rootDocument.path)
				AppendSubtypes(result, analysis.model.globalScope, analysis, analysisUri, targetKey, documents, seen)
			End If
		Next
		For Local rootPath:String = EachIn workspace.ProjectCandidateRoots(resolved.symbol.name, resolved.symbol.originPath)
			Local analysis:TLanguageAnalysis = workspace.ProjectFeatureAnalysis(rootPath)
			If analysis And analysis.model Then AppendSubtypes(result, analysis.model.globalScope, analysis, FileUriForPath(rootPath), targetKey, documents, seen)
		Next
		Return result
	End Function

	Function HierarchySymbol:TSymbol(location:TSemanticLocation)
		If Not location Then Return Null
		If Supported(location.symbol) Then Return location.symbol
		Local named:TNamedSemanticType = TNamedSemanticType(location.semanticType)
		If named And Supported(named.symbol) Then Return named.symbol
		If location.symbol Then
			named = TNamedSemanticType(location.symbol.declaredType)
			If named And Supported(named.symbol) Then Return named.symbol
		End If
		Return Null
	End Function

	Function Supported:Int(symbol:TSymbol)
		Return symbol <> Null And (symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_INTERFACE)
	End Function

	Function AppendSupertypes(target:TJSONArray, edges:TInheritanceEdge[], analysis:TLanguageAnalysis, analysisUri:String, documents:TLspDocumentStore, seen:TMap)
		For Local edge:TInheritanceEdge = EachIn edges
			Local named:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
			If Not named Or Not Supported(named.symbol) Then Continue
			Local key:String = SymbolKey(named.symbol)
			If Not key.length Or seen.Contains(key) Then Continue
			Local item:TJSONObject = Item(named.symbol, analysis, analysisUri, documents)
			If Not item Then Continue
			seen.Insert(key, named.symbol)
			target.Append(item)
		Next
	End Function

	Function AppendSubtypes(target:TJSONArray, scope:TScope, analysis:TLanguageAnalysis, analysisUri:String, targetKey:String, documents:TLspDocumentStore, seen:TMap)
		If Not scope Then Return
		For Local candidate:TSymbol = EachIn scope.declaredSymbols
			If Not Supported(candidate) Then Continue
			Local candidateKey:String = SymbolKey(candidate)
			If Not candidateKey.length Or candidateKey = targetKey Or seen.Contains(candidateKey) Then Continue
			Local info:TTypeInheritanceInfo = analysis.model.InheritanceInfo(candidate)
			If Not info Or Not DirectlyInherits(info, targetKey) Then Continue
			Local item:TJSONObject = Item(candidate, analysis, analysisUri, documents)
			If Not item Then Continue
			seen.Insert(candidateKey, candidate)
			target.Append(item)
		Next
		For Local child:TScope = EachIn scope.children
			AppendSubtypes(target, child, analysis, analysisUri, targetKey, documents, seen)
		Next
	End Function

	Function DirectlyInherits:Int(info:TTypeInheritanceInfo, targetKey:String)
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			Local named:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
			If named And SymbolKey(named.symbol) = targetKey Then Return True
		Next
		For Local edge:TInheritanceEdge = EachIn info.interfaceEdges
			Local named:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
			If named And SymbolKey(named.symbol) = targetKey Then Return True
		Next
		Return False
	End Function

	Function Item:TJSONObject(symbol:TSymbol, analysis:TLanguageAnalysis, analysisUri:String, documents:TLspDocumentStore)
		If Not Supported(symbol) Or Not analysis Then Return Null
		Local path:String = symbol.originPath
		If Not path.length And analysis.syntaxTree Then path = analysis.syntaxTree.source.path
		If Not path.ToLower().EndsWith(".bmx") Then Return Null
		Local source:TSourceText = TBlitzMaxLspNavigation.SourceForPath(path, analysis, documents)
		If Not source Then Return Null

		Local selection:TSourceSpan
		Local fullRange:TSourceSpan
		If Not symbol.isImported And symbol.declaration And analysis.syntaxTree And SnapshotPathKey(analysis.syntaxTree.source.path) = SnapshotPathKey(path) Then
			fullRange = symbol.declaration.span
			If symbol.nameToken Then selection = symbol.nameToken.span
		Else If symbol.originLine > 0 Then
			selection = TBlitzMaxLspNavigation.ProvenanceSpan(source, symbol)
			Local line:Int = symbol.originLine - 1
			Local first:Int = source.Offset(line, 0)
			Local last:Int = source.Offset(line, 2147483647)
			fullRange = TSourceSpan.Create(first, last - first)
		End If
		If Not selection And symbol.nameToken And Not symbol.isImported Then selection = symbol.nameToken.span
		If Not fullRange Then fullRange = selection
		If Not selection Or Not fullRange Then Return Null

		Local result:TJSONObject = JsonObject()
		result.Set("name", symbol.name)
		If symbol.kind = SYMBOL_INTERFACE Then result.Set("kind", 11) Else result.Set("kind", 5)
		Local detail:String = symbol.KindName()
		If symbol.originModule.length Then detail :+ " — " + symbol.originModule
		result.Set("detail", detail)
		result.Set("uri", TBlitzMaxLspNavigation.UriForPath(path, documents))
		result.Set("range", TLspPositions.Range(source, fullRange))
		result.Set("selectionRange", TLspPositions.Range(source, selection))
		Local data:TJSONObject = JsonObject()
		data.Set("analysisUri", analysisUri)
		data.Set("name", symbol.name)
		data.Set("qualifiedName", symbol.QualifiedName())
		data.Set("kind", symbol.kind)
		data.Set("originPath", path)
		data.Set("originLine", symbol.originLine)
		result.Set("data", data)
		Return result
	End Function

	Function Resolve:TLspTypeHierarchyResolution(item:TJSONObject, workspace:TLspWorkspaceContext)
		If Not item Or Not workspace Then Return Null
		Local data:TJSONObject = TJSONObject(item.Get("data"))
		If Not data Then Return Null
		Local preferredUri:String = data.GetString("analysisUri")
		Local preferred:TLanguageAnalysis = workspace.LatestAnalysis(preferredUri)
		Local symbol:TSymbol = FindSymbol(preferred, data)
		If symbol Then Return TLspTypeHierarchyResolution.Create(symbol, preferred, preferredUri)
		For Local key:Object = EachIn workspace.analyses.Keys()
			Local analysisUri:String = String(key)
			If analysisUri = preferredUri Then Continue
			Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(analysisUri)
			symbol = FindSymbol(analysis, data)
			If symbol Then Return TLspTypeHierarchyResolution.Create(symbol, analysis, analysisUri)
		Next
		For Local value:Object = EachIn workspace.projectAnalyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			symbol = FindSymbol(analysis, data)
			If symbol And analysis.snapshot And analysis.snapshot.rootDocument Then Return TLspTypeHierarchyResolution.Create(symbol, analysis, FileUriForPath(analysis.snapshot.rootDocument.path))
		Next
		Local projectRoot:String = workspace.ProjectRootForPath(data.GetString("originPath"))
		If projectRoot.length Then
			Local analysis:TLanguageAnalysis = workspace.ProjectFeatureAnalysis(projectRoot)
			symbol = FindSymbol(analysis, data)
			If symbol Then Return TLspTypeHierarchyResolution.Create(symbol, analysis, FileUriForPath(projectRoot))
		End If
		Return Null
	End Function

	Function FindSymbol:TSymbol(analysis:TLanguageAnalysis, data:TJSONObject)
		If Not analysis Or Not analysis.model Or Not data Then Return Null
		Return FindInScope(analysis.model.globalScope, data)
	End Function

	Function FindInScope:TSymbol(scope:TScope, data:TJSONObject)
		If Not scope Then Return Null
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If MatchesData(symbol, data) Then Return symbol
		Next
		For Local child:TScope = EachIn scope.children
			Local found:TSymbol = FindInScope(child, data)
			If found Then Return found
		Next
		Return Null
	End Function

	Function MatchesData:Int(symbol:TSymbol, data:TJSONObject)
		If Not Supported(symbol) Then Return False
		If symbol.kind <> data.GetInteger("kind") Or symbol.name.ToLower() <> data.GetString("name").ToLower() Then Return False
		If symbol.originLine <> data.GetInteger("originLine") Then Return False
		If SnapshotPathKey(symbol.originPath) <> SnapshotPathKey(data.GetString("originPath")) Then Return False
		Local qualifiedName:String = data.GetString("qualifiedName")
		Return Not qualifiedName.length Or symbol.QualifiedName().ToLower() = qualifiedName.ToLower()
	End Function

	Function SymbolKey:String(symbol:TSymbol)
		If Not Supported(symbol) Or Not symbol.originPath.length Then Return ""
		Return SnapshotPathKey(symbol.originPath) + "|" + symbol.originLine + "|" + symbol.kind + "|" + symbol.QualifiedName().ToLower()
	End Function
End Type

Type TLspTypeHierarchyResolution
	Field symbol:TSymbol
	Field analysis:TLanguageAnalysis
	Field analysisUri:String

	Function Create:TLspTypeHierarchyResolution(symbol:TSymbol, analysis:TLanguageAnalysis, analysisUri:String)
		Local result:TLspTypeHierarchyResolution = New TLspTypeHierarchyResolution
		result.symbol = symbol
		result.analysis = analysis
		result.analysisUri = analysisUri
		Return result
	End Function
End Type
