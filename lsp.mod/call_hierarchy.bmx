' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "navigation_features.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

' Standard LSP call hierarchy over the semantic compilation units already
' loaded for a workspace. Compact indexes are built for only the requested
' incoming target or outgoing caller and reused until that source root changes.
Type TBlitzMaxLspCallHierarchy
	Function Prepare:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Then Return JsonNull()
		Local symbol:TSymbol = RoutineAt(context)
		If Not Supported(symbol) Then Return JsonNull()
		Local record:TCallHierarchySymbolRecord = TCallHierarchySymbolRecord.Create(symbol, context.analysis, document.uri, documents)
		Local item:TJSONObject = Item(record, documents)
		If Not item Then Return JsonNull()
		Local result:TJSONArray = JsonArray()
		result.Append(item)
		Return result
	End Function

	Function Incoming:TJSON(item:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		Local data:TJSONObject = ItemData(item)
		Local requestedKey:String = DataKey(data)
		If Not requestedKey.length Or Not workspace Then Return result
		Local groups:TMap = New TMap
		Local seenRanges:TMap = New TMap
		Local seenIndexes:TMap = New TMap

		Local analysisUri:String = data.GetString("analysisUri")
		If analysisUri.length Then AppendIncomingIndex(result, groups, seenRanges, seenIndexes, IncomingIndexForAnalysis(workspace, workspace.LatestAnalysis(analysisUri), analysisUri, requestedKey, data.GetString("name")), requestedKey, documents)
		For Local key:Object = EachIn workspace.analyses.Keys()
			Local currentUri:String = String(key)
			AppendIncomingIndex(result, groups, seenRanges, seenIndexes, IncomingIndexForAnalysis(workspace, workspace.LatestAnalysis(currentUri), currentUri, requestedKey, data.GetString("name")), requestedKey, documents)
		Next
		For Local rootPath:String = EachIn workspace.ProjectCallCandidateRoots(data.GetString("name"), data.GetString("originPath"))
			AppendIncomingIndex(result, groups, seenRanges, seenIndexes, IncomingIndexForProjectRoot(workspace, rootPath, requestedKey, data.GetString("name")), requestedKey, documents)
		Next
		For Local value:Object = EachIn workspace.projectAnalyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			Local currentUri:String
			If analysis And analysis.snapshot And analysis.snapshot.rootDocument Then currentUri = FileUriForPath(analysis.snapshot.rootDocument.path)
			AppendIncomingIndex(result, groups, seenRanges, seenIndexes, IncomingIndexForAnalysis(workspace, analysis, currentUri, requestedKey, data.GetString("name")), requestedKey, documents)
		Next
		Return result
	End Function

	Function Outgoing:TJSON(item:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		Local data:TJSONObject = ItemData(item)
		Local requestedKey:String = DataKey(data)
		If Not requestedKey.length Or Not workspace Then Return result
		Local groups:TMap = New TMap
		Local seenRanges:TMap = New TMap
		Local analysisUri:String = data.GetString("analysisUri")
		Local preferred:TLanguageAnalysis
		If analysisUri.length Then preferred = workspace.LatestAnalysis(analysisUri)
		Local index:TCallHierarchyIndex = OutgoingIndexForAnalysis(workspace, preferred, analysisUri, requestedKey, data.GetString("originPath"))
		If AppendOutgoingIndex(result, groups, seenRanges, index, requestedKey, documents) Then Return result

		workspace.EnsureProjectGraph()
		Local targetRoot:String = workspace.ProjectRootForPath(data.GetString("originPath"))
		If targetRoot.length Then
			index = OutgoingIndexForProjectRoot(workspace, targetRoot, requestedKey, data.GetString("originPath"))
			If AppendOutgoingIndex(result, groups, seenRanges, index, requestedKey, documents) Then Return result
		End If
		' Ad-hoc and multi-root workspaces may have the source body in another
		' already-loaded analysis. Inspect only analyses which contain its path.
		For Local key:Object = EachIn workspace.analyses.Keys()
			Local currentUri:String = String(key)
			Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(currentUri)
			If analysis = preferred Or Not workspace.AnalysisContainsSourcePath(analysis, data.GetString("originPath")) Then Continue
			index = OutgoingIndexForAnalysis(workspace, analysis, currentUri, requestedKey, data.GetString("originPath"))
			If AppendOutgoingIndex(result, groups, seenRanges, index, requestedKey, documents) Then Return result
		Next
		Return result
	End Function

	Function AppendIncomingIndex(target:TJSONArray, groups:TMap, seenRanges:TMap, seenIndexes:TMap, index:TCallHierarchyIndex, requestedKey:String, documents:TLspDocumentStore)
		If Not index Or seenIndexes.Contains(index) Then Return
		seenIndexes.Insert(index, index)
		AppendEdges(target, groups, seenRanges, TList(index.incoming.ValueForKey(requestedKey)), True, documents)
	End Function

	Function AppendOutgoingIndex:Int(target:TJSONArray, groups:TMap, seenRanges:TMap, index:TCallHierarchyIndex, requestedKey:String, documents:TLspDocumentStore)
		If Not index Then Return False
		Local edges:TList = TList(index.outgoing.ValueForKey(requestedKey))
		If Not edges Then Return False
		AppendEdges(target, groups, seenRanges, edges, False, documents)
		Return True
	End Function

	Function AppendEdges(target:TJSONArray, groups:TMap, seenRanges:TMap, edges:TList, incoming:Int, documents:TLspDocumentStore)
		If Not edges Then Return
		For Local edge:TCallHierarchyEdge = EachIn edges
			Local record:TCallHierarchySymbolRecord = edge.callee
			Local direction:String = "to"
			If incoming Then record = edge.caller; direction = "from"
			Local item:TJSONObject = Item(record, documents)
			If Not item Or Not edge.range Then Continue
			Local rangeKey:String = edge.key + "|" + record.key
			If seenRanges.Contains(rangeKey) Then Continue
			seenRanges.Insert(rangeKey, edge)
			Local entry:TJSONObject = TJSONObject(groups.ValueForKey(record.key))
			If Not entry Then
				entry = JsonObject()
				entry.Set(direction, item)
				entry.Set("fromRanges", JsonArray())
				groups.Insert(record.key, entry)
				target.Append(entry)
			End If
			TJSONArray(entry.Get("fromRanges")).Append(edge.range)
		Next
	End Function

	Function IncomingIndexForProjectRoot:TCallHierarchyIndex(workspace:TLspWorkspaceContext, rootPath:String, requestedKey:String, requestedName:String)
		If Not workspace Or Not rootPath.length Then Return Null
		Local cached:TCallHierarchyIndex = CachedIncoming(workspace, rootPath, requestedKey)
		If cached Then Return cached
		Return IncomingIndexForAnalysis(workspace, workspace.CallHierarchyFeatureAnalysis(rootPath), FileUriForPath(rootPath), requestedKey, requestedName)
	End Function

	Function IncomingIndexForAnalysis:TCallHierarchyIndex(workspace:TLspWorkspaceContext, analysis:TLanguageAnalysis, analysisUri:String, requestedKey:String, requestedName:String)
		If Not workspace Or Not analysis Or Not analysis.model Then Return Null
		Local rootPath:String = TLspWorkspaceContext.AnalysisRootPath(analysis)
		If Not rootPath.length Then Return Null
		Local cached:TCallHierarchyIndex = CachedIncoming(workspace, rootPath, requestedKey)
		If cached Then Return cached
		Local started:Int = MilliSecs()
		Local index:TCallHierarchyIndex = TCallHierarchyIndex.BuildIncoming(analysis, analysisUri, requestedKey, requestedName)
		If Not index Then Return Null
		IndexSet(workspace, rootPath).incoming.Insert(requestedKey, index)
		RecordIndexBuild(workspace, index, started)
		Return index
	End Function

	Function OutgoingIndexForProjectRoot:TCallHierarchyIndex(workspace:TLspWorkspaceContext, rootPath:String, requestedKey:String, originPath:String)
		If Not workspace Or Not rootPath.length Then Return Null
		Local cached:TCallHierarchyIndex = CachedOutgoing(workspace, rootPath, requestedKey)
		If cached Then Return cached
		Return OutgoingIndexForAnalysis(workspace, workspace.CallHierarchyFeatureAnalysis(rootPath), FileUriForPath(rootPath), requestedKey, originPath)
	End Function

	Function OutgoingIndexForAnalysis:TCallHierarchyIndex(workspace:TLspWorkspaceContext, analysis:TLanguageAnalysis, analysisUri:String, requestedKey:String, originPath:String)
		If Not workspace Or Not analysis Or Not analysis.model Then Return Null
		Local rootPath:String = TLspWorkspaceContext.AnalysisRootPath(analysis)
		If Not rootPath.length Then Return Null
		Local cached:TCallHierarchyIndex = CachedOutgoing(workspace, rootPath, requestedKey)
		If cached Then Return cached
		Local started:Int = MilliSecs()
		Local index:TCallHierarchyIndex = TCallHierarchyIndex.BuildOutgoing(analysis, analysisUri, requestedKey, originPath)
		If Not index Then Return Null
		IndexSet(workspace, rootPath).outgoing.Insert(requestedKey, index)
		RecordIndexBuild(workspace, index, started)
		Return index
	End Function

	Function IndexSet:TCallHierarchyRootIndexes(workspace:TLspWorkspaceContext, rootPath:String)
		Local rootKey:String = SnapshotPathKey(rootPath)
		Local result:TCallHierarchyRootIndexes = TCallHierarchyRootIndexes(workspace.callHierarchyIndexes.ValueForKey(rootKey))
		If result Then Return result
		result = New TCallHierarchyRootIndexes
		workspace.callHierarchyIndexes.Insert(rootKey, result)
		Return result
	End Function

	Function CachedIncoming:TCallHierarchyIndex(workspace:TLspWorkspaceContext, rootPath:String, requestedKey:String)
		Local indexes:TCallHierarchyRootIndexes = TCallHierarchyRootIndexes(workspace.callHierarchyIndexes.ValueForKey(SnapshotPathKey(rootPath)))
		If Not indexes Then Return Null
		Local result:TCallHierarchyIndex = TCallHierarchyIndex(indexes.incoming.ValueForKey(requestedKey))
		If result Then workspace.callHierarchyIndexHits :+ 1
		Return result
	End Function

	Function CachedOutgoing:TCallHierarchyIndex(workspace:TLspWorkspaceContext, rootPath:String, requestedKey:String)
		Local indexes:TCallHierarchyRootIndexes = TCallHierarchyRootIndexes(workspace.callHierarchyIndexes.ValueForKey(SnapshotPathKey(rootPath)))
		If Not indexes Then Return Null
		Local result:TCallHierarchyIndex = TCallHierarchyIndex(indexes.outgoing.ValueForKey(requestedKey))
		If result Then workspace.callHierarchyIndexHits :+ 1
		Return result
	End Function

	Function RecordIndexBuild(workspace:TLspWorkspaceContext, index:TCallHierarchyIndex, started:Int)
		workspace.callHierarchyIndexBuilds :+ 1
		workspace.callHierarchyIndexedNodes :+ index.nodeCount
		workspace.callHierarchyIndexedEdges :+ index.edgeCount
		workspace.callHierarchyIndexMilliseconds :+ MilliSecs() - started
	End Function

	Function RoutineAt:TSymbol(context:TLspFeatureContext)
		If Not context Or Not context.analysis Or Not context.location Then Return Null
		If Supported(context.location.symbol) Then Return context.location.symbol
		If context.location.syntax Then
			For Local node:TSyntaxNode = EachIn context.location.syntax.parents
				Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
				If declaration Then Return context.analysis.model.DeclaredSymbol(declaration)
				If TFunctionLiteralExpressionSyntax(node) Then Return Null
			Next
		End If
		Return Null
	End Function

	Function ContainingRoutine:TSymbol(model:TSemanticModel, navigator:TSyntaxNavigator, node:TSyntaxNode)
		Local current:TSyntaxNode = navigator.Parent(node)
		While current
			If TFunctionLiteralExpressionSyntax(current) Then Return Null
			Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(current)
			If declaration Then Return model.DeclaredSymbol(declaration)
			current = navigator.Parent(current)
		Wend
		Return Null
	End Function

	Function ResolvedRoutineCall:TResolvedCall(model:TSemanticModel, node:TSyntaxNode)
		If Not model Or Not node Then Return Null
		If Not TCallStatementSyntax(node) And Not TCallExpressionSyntax(node) And Not TNewExpressionSyntax(node) And Not TNameExpressionSyntax(node) And Not TMemberAccessExpressionSyntax(node) Then Return Null
		Local resolved:TResolvedCall = model.ResolvedCall(node)
		If Not resolved Or Not Supported(resolved.routine) Then Return Null
		Return resolved
	End Function

	Function CallSpan:TSourceSpan(node:TSyntaxNode, routine:TSymbol)
		Local statement:TCallStatementSyntax = TCallStatementSyntax(node)
		If statement And statement.calleeTokens.length Then
			For Local index:Int = statement.calleeTokens.length - 1 To 0 Step -1
				If routine And statement.calleeTokens[index].text.ToLower() = routine.name.ToLower() Then Return statement.calleeTokens[index].span
			Next
			Return statement.calleeTokens[statement.calleeTokens.length - 1].span
		End If
		Local call:TCallExpressionSyntax = TCallExpressionSyntax(node)
		If call And call.callee Then Return TBlitzMaxLspNavigation.ReferenceSpan(call.callee)
		Local creation:TNewExpressionSyntax = TNewExpressionSyntax(node)
		If creation And creation.createdType Then Return TBlitzMaxLspNavigation.ReferenceSpan(creation.createdType)
		Return TBlitzMaxLspNavigation.ReferenceSpan(node)
	End Function

	Function Item:TJSONObject(record:TCallHierarchySymbolRecord, documents:TLspDocumentStore)
		If Not record Or Not record.path.ToLower().EndsWith(".bmx") Then Return Null
		If Not record.selectionRange Or Not record.fullRange Then Return Null
		Local result:TJSONObject = JsonObject()
		result.Set("name", record.name)
		result.Set("kind", record.itemKind)
		result.Set("detail", record.detail)
		result.Set("uri", TBlitzMaxLspNavigation.UriForPath(record.path, documents))
		result.Set("range", record.fullRange)
		result.Set("selectionRange", record.selectionRange)
		Local data:TJSONObject = JsonObject()
		data.Set("analysisUri", record.analysisUri)
		data.Set("name", record.name)
		data.Set("qualifiedName", record.qualifiedName)
		data.Set("kind", record.symbolKind)
		data.Set("originPath", record.path)
		data.Set("originLine", record.originLine)
		data.Set("originColumn", record.originColumn)
		result.Set("data", data)
		Return result
	End Function

	Function ItemData:TJSONObject(item:TJSONObject)
		If Not item Then Return Null
		Return TJSONObject(item.Get("data"))
	End Function

	Function DataKey:String(data:TJSONObject)
		If Not data Or Not data.GetString("originPath").length Then Return ""
		Return SnapshotPathKey(data.GetString("originPath")) + "|" + data.GetInteger("originLine") + ":" + data.GetInteger("originColumn") + "|" + data.GetString("qualifiedName").ToLower()
	End Function

	Function Supported:Int(symbol:TSymbol)
		Return symbol <> Null And symbol.kind = SYMBOL_ROUTINE
	End Function

	Function IsInstanceRoutine:Int(symbol:TSymbol)
		If Not Supported(symbol) Then Return False
		If symbol.interfaceRecord Then Return symbol.interfaceRecord.kind = INTERFACE_RECORD_METHOD
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		Return declaration <> Null And declaration.isMethod
	End Function

	Function RoutineKind:Int(symbol:TSymbol)
		If IsInstanceRoutine(symbol) And symbol.name.ToLower() = "new" Then Return 9
		If IsInstanceRoutine(symbol) Then Return 6
		Return 12
	End Function

	Function SymbolKey:String(symbol:TSymbol)
		If Not Supported(symbol) Or Not symbol.originPath.length Then Return ""
		Return SnapshotPathKey(symbol.originPath) + "|" + symbol.originLine + ":" + symbol.originColumn + "|" + symbol.QualifiedName().ToLower()
	End Function
End Type

Type TCallHierarchySymbolRecord
	Field key:String
	Field name:String
	Field qualifiedName:String
	Field symbolKind:Int
	Field itemKind:Int
	Field detail:String
	Field path:String
	Field originLine:Int
	Field originColumn:Int
	Field selectionRange:TJSONObject
	Field fullRange:TJSONObject
	Field analysisUri:String

	Function Create:TCallHierarchySymbolRecord(symbol:TSymbol, analysis:TLanguageAnalysis, analysisUri:String, documents:TLspDocumentStore = Null)
		If Not TBlitzMaxLspCallHierarchy.Supported(symbol) Then Return Null
		Local result:TCallHierarchySymbolRecord = New TCallHierarchySymbolRecord
		result.key = TBlitzMaxLspCallHierarchy.SymbolKey(symbol)
		If Not result.key.length Then Return Null
		result.name = symbol.name
		result.qualifiedName = symbol.QualifiedName()
		result.symbolKind = symbol.kind
		result.itemKind = TBlitzMaxLspCallHierarchy.RoutineKind(symbol)
		result.path = symbol.originPath
		If Not result.path.length And analysis And analysis.syntaxTree Then result.path = analysis.syntaxTree.source.path
		result.originLine = symbol.originLine
		result.originColumn = symbol.originColumn
		result.analysisUri = analysisUri
		result.detail = "Function"
		If TBlitzMaxLspCallHierarchy.IsInstanceRoutine(symbol) Then result.detail = "Method"
		If symbol.containingScope And symbol.containingScope.owner Then result.detail :+ " — " + symbol.containingScope.owner.QualifiedName()
		If symbol.originModule.length Then result.detail :+ " — " + symbol.originModule
		Local source:TSourceText = TBlitzMaxLspNavigation.SourceForPath(result.path, analysis, documents)
		If source And Not symbol.isImported And symbol.declaration And symbol.nameToken Then
			result.selectionRange = TLspPositions.Range(source, symbol.nameToken.span)
			result.fullRange = TLspPositions.Range(source, symbol.declaration.span)
		Else If source And symbol.originLine > 0 Then
			Local selection:TSourceSpan = TBlitzMaxLspNavigation.ProvenanceSpan(source, symbol)
			Local line:Int = symbol.originLine - 1
			Local first:Int = source.Offset(line, 0)
			Local last:Int = source.Offset(line, 2147483647)
			result.selectionRange = TLspPositions.Range(source, selection)
			result.fullRange = TLspPositions.Range(source, TSourceSpan.Create(first, last - first))
		End If
		Return result
	End Function
End Type

Type TCallHierarchyEdge
	Field caller:TCallHierarchySymbolRecord
	Field callee:TCallHierarchySymbolRecord
	Field sourcePath:String
	Field key:String
	Field range:TJSONObject
End Type

Type TCallHierarchyRootIndexes
	Field incoming:TMap = New TMap
	Field outgoing:TMap = New TMap
End Type

Type TCallHierarchyIndex
	Field rootPath:String
	Field incoming:TMap = New TMap
	Field outgoing:TMap = New TMap
	Field symbols:TMap = New TMap
	Field seenEdges:TMap = New TMap
	Field nodeCount:Int
	Field edgeCount:Int

	Function BuildIncoming:TCallHierarchyIndex(analysis:TLanguageAnalysis, analysisUri:String, requestedKey:String, requestedName:String)
		If Not analysis Or Not analysis.model Then Return Null
		Local result:TCallHierarchyIndex = New TCallHierarchyIndex
		result.rootPath = TLspWorkspaceContext.AnalysisRootPath(analysis)
		If analysis.snapshot And analysis.snapshot.documents.length Then
			For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If sourceDocument And sourceDocument.tree Then result.IndexIncomingDocument(analysis, analysisUri, sourceDocument.tree, sourceDocument.path, requestedKey, requestedName)
			Next
		Else If analysis.syntaxTree Then
			result.IndexIncomingDocument(analysis, analysisUri, analysis.syntaxTree, analysis.syntaxTree.source.path, requestedKey, requestedName)
		End If
		Return result
	End Function

	Function BuildOutgoing:TCallHierarchyIndex(analysis:TLanguageAnalysis, analysisUri:String, requestedKey:String, originPath:String)
		If Not analysis Or Not analysis.model Then Return Null
		Local result:TCallHierarchyIndex = New TCallHierarchyIndex
		result.rootPath = TLspWorkspaceContext.AnalysisRootPath(analysis)
		If analysis.snapshot And analysis.snapshot.documents.length Then
			For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If sourceDocument And sourceDocument.tree And SnapshotPathKey(sourceDocument.path) = SnapshotPathKey(originPath) Then result.IndexOutgoingDocument(analysis, analysisUri, sourceDocument.tree, sourceDocument.path, requestedKey)
			Next
		Else If analysis.syntaxTree And SnapshotPathKey(analysis.syntaxTree.source.path) = SnapshotPathKey(originPath) Then
			result.IndexOutgoingDocument(analysis, analysisUri, analysis.syntaxTree, analysis.syntaxTree.source.path, requestedKey)
		End If
		Return result
	End Function

	Method IndexIncomingDocument(analysis:TLanguageAnalysis, analysisUri:String, tree:TSyntaxTree, path:String, requestedKey:String, requestedName:String)
		If Not tree Or Not tree.source Then Return
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(tree)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			nodeCount :+ 1
			Local resolved:TResolvedCall = TBlitzMaxLspCallHierarchy.ResolvedRoutineCall(analysis.model, node)
			If Not resolved Or resolved.routine.name.ToLower() <> requestedName.ToLower() Or TBlitzMaxLspCallHierarchy.SymbolKey(resolved.routine) <> requestedKey Then Continue
			Local callerSymbol:TSymbol = TBlitzMaxLspCallHierarchy.ContainingRoutine(analysis.model, navigator, node)
			If Not TBlitzMaxLspCallHierarchy.Supported(callerSymbol) Then Continue
			Local span:TSourceSpan = TBlitzMaxLspCallHierarchy.CallSpan(node, resolved.routine)
			If Not span Then Continue
			Local caller:TCallHierarchySymbolRecord = SymbolRecord(callerSymbol, analysis, analysisUri)
			Local callee:TCallHierarchySymbolRecord = SymbolRecord(resolved.routine, analysis, analysisUri)
			AddEdge(caller, callee, path, span, tree.source)
		Next
	End Method

	Method IndexOutgoingDocument(analysis:TLanguageAnalysis, analysisUri:String, tree:TSyntaxTree, path:String, requestedKey:String)
		If Not tree Or Not tree.source Then Return
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(tree)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			nodeCount :+ 1
			Local resolved:TResolvedCall = TBlitzMaxLspCallHierarchy.ResolvedRoutineCall(analysis.model, node)
			If Not resolved Then Continue
			Local callerSymbol:TSymbol = TBlitzMaxLspCallHierarchy.ContainingRoutine(analysis.model, navigator, node)
			If Not TBlitzMaxLspCallHierarchy.Supported(callerSymbol) Or TBlitzMaxLspCallHierarchy.SymbolKey(callerSymbol) <> requestedKey Then Continue
			Local span:TSourceSpan = TBlitzMaxLspCallHierarchy.CallSpan(node, resolved.routine)
			If Not span Then Continue
			Local caller:TCallHierarchySymbolRecord = SymbolRecord(callerSymbol, analysis, analysisUri)
			Local callee:TCallHierarchySymbolRecord = SymbolRecord(resolved.routine, analysis, analysisUri)
			AddEdge(caller, callee, path, span, tree.source)
		Next
	End Method

	Method SymbolRecord:TCallHierarchySymbolRecord(symbol:TSymbol, analysis:TLanguageAnalysis, analysisUri:String)
		Local key:String = TBlitzMaxLspCallHierarchy.SymbolKey(symbol)
		If Not key.length Then Return Null
		Local result:TCallHierarchySymbolRecord = TCallHierarchySymbolRecord(symbols.ValueForKey(key))
		If result Then Return result
		result = TCallHierarchySymbolRecord.Create(symbol, analysis, analysisUri)
		If result Then symbols.Insert(key, result)
		Return result
	End Method

	Method AddEdge(caller:TCallHierarchySymbolRecord, callee:TCallHierarchySymbolRecord, sourcePath:String, span:TSourceSpan, source:TSourceText)
		If Not caller Or Not callee Or Not span Or Not source Then Return
		Local edgeKey:String = SnapshotPathKey(sourcePath) + "|" + span.start + ":" + span.length + "|" + caller.key + "|" + callee.key
		If seenEdges.Contains(edgeKey) Then Return
		Local edge:TCallHierarchyEdge = New TCallHierarchyEdge
		edge.caller = caller
		edge.callee = callee
		edge.sourcePath = sourcePath
		edge.key = SnapshotPathKey(sourcePath) + "|" + span.start + ":" + span.length
		edge.range = TLspPositions.Range(source, span)
		Append(incoming, callee.key, edge)
		Append(outgoing, caller.key, edge)
		seenEdges.Insert(edgeKey, edge)
		edgeCount :+ 1
	End Method

	Function Append(target:TMap, key:String, edge:TCallHierarchyEdge)
		Local edges:TList = TList(target.ValueForKey(key))
		If Not edges Then edges = New TList; target.Insert(key, edges)
		edges.AddLast(edge)
	End Function
End Type
