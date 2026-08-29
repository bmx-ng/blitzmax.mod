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

' Standard LSP call hierarchy over the semantic compilation units already
' loaded for a workspace. Calls are grouped by their containing named routine;
' anonymous Function literals and unrelated workspace files are not guessed.
Type TBlitzMaxLspCallHierarchy
	Function Prepare:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Then Return JsonNull()
		Local symbol:TSymbol = RoutineAt(context)
		If Not Supported(symbol) Then Return JsonNull()
		Local item:TJSONObject = Item(symbol, context.analysis, document.uri, documents)
		If Not item Then Return JsonNull()
		Local result:TJSONArray = JsonArray()
		result.Append(item)
		Return result
	End Function

	Function Incoming:TJSON(item:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		Local data:TJSONObject = ItemData(item)
		If Not data Or Not workspace Then Return result
		Local groups:TMap = New TMap
		Local seenRanges:TMap = New TMap
		Local seenModels:TMap = New TMap
		AppendPreferredIncoming(result, groups, seenRanges, seenModels, data, workspace, documents)
		For Local key:Object = EachIn workspace.analyses.Keys()
			Local analysisUri:String = String(key)
			AppendIncomingAnalysis(result, groups, seenRanges, seenModels, workspace.LatestAnalysis(analysisUri), analysisUri, data, documents)
		Next
		For Local rootPath:String = EachIn workspace.ProjectCandidateRoots(data.GetString("name"), data.GetString("originPath"))
			AppendIncomingAnalysis(result, groups, seenRanges, seenModels, workspace.ProjectFeatureAnalysis(rootPath), FileUriForPath(rootPath), data, documents)
		Next
		For Local value:Object = EachIn workspace.projectAnalyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			Local analysisUri:String
			If analysis And analysis.snapshot And analysis.snapshot.rootDocument Then analysisUri = FileUriForPath(analysis.snapshot.rootDocument.path)
			AppendIncomingAnalysis(result, groups, seenRanges, seenModels, analysis, analysisUri, data, documents)
		Next
		Return result
	End Function

	Function Outgoing:TJSON(item:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		Local data:TJSONObject = ItemData(item)
		If Not data Or Not workspace Then Return result
		Local groups:TMap = New TMap
		Local seenRanges:TMap = New TMap
		Local seenModels:TMap = New TMap
		AppendPreferredOutgoing(result, groups, seenRanges, seenModels, data, workspace, documents)
		For Local key:Object = EachIn workspace.analyses.Keys()
			Local analysisUri:String = String(key)
			AppendOutgoingAnalysis(result, groups, seenRanges, seenModels, workspace.LatestAnalysis(analysisUri), analysisUri, data, documents)
		Next
		For Local rootPath:String = EachIn workspace.ProjectCandidateRoots(data.GetString("name"), data.GetString("originPath"))
			AppendOutgoingAnalysis(result, groups, seenRanges, seenModels, workspace.ProjectFeatureAnalysis(rootPath), FileUriForPath(rootPath), data, documents)
		Next
		For Local value:Object = EachIn workspace.projectAnalyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			Local analysisUri:String
			If analysis And analysis.snapshot And analysis.snapshot.rootDocument Then analysisUri = FileUriForPath(analysis.snapshot.rootDocument.path)
			AppendOutgoingAnalysis(result, groups, seenRanges, seenModels, analysis, analysisUri, data, documents)
		Next
		Return result
	End Function

	Function AppendPreferredIncoming(target:TJSONArray, groups:TMap, seenRanges:TMap, seenModels:TMap, data:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local analysisUri:String = data.GetString("analysisUri")
		If analysisUri.length Then AppendIncomingAnalysis(target, groups, seenRanges, seenModels, workspace.LatestAnalysis(analysisUri), analysisUri, data, documents)
	End Function

	Function AppendPreferredOutgoing(target:TJSONArray, groups:TMap, seenRanges:TMap, seenModels:TMap, data:TJSONObject, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local analysisUri:String = data.GetString("analysisUri")
		If analysisUri.length Then AppendOutgoingAnalysis(target, groups, seenRanges, seenModels, workspace.LatestAnalysis(analysisUri), analysisUri, data, documents)
	End Function

	Function AppendIncomingAnalysis(target:TJSONArray, groups:TMap, seenRanges:TMap, seenModels:TMap, analysis:TLanguageAnalysis, analysisUri:String, requested:TJSONObject, documents:TLspDocumentStore)
		If Not analysis Or Not analysis.model Or seenModels.Contains(analysis.model) Then Return
		seenModels.Insert(analysis.model, analysis.model)
		If analysis.snapshot And analysis.snapshot.documents.length Then
			For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If sourceDocument And sourceDocument.tree Then AppendIncomingDocument(target, groups, seenRanges, analysis, analysisUri, sourceDocument.tree, sourceDocument.path, requested, documents)
			Next
		Else If analysis.syntaxTree Then
			AppendIncomingDocument(target, groups, seenRanges, analysis, analysisUri, analysis.syntaxTree, analysis.syntaxTree.source.path, requested, documents)
		End If
	End Function

	Function AppendOutgoingAnalysis(target:TJSONArray, groups:TMap, seenRanges:TMap, seenModels:TMap, analysis:TLanguageAnalysis, analysisUri:String, requested:TJSONObject, documents:TLspDocumentStore)
		If Not analysis Or Not analysis.model Or seenModels.Contains(analysis.model) Then Return
		seenModels.Insert(analysis.model, analysis.model)
		If analysis.snapshot And analysis.snapshot.documents.length Then
			For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If sourceDocument And sourceDocument.tree Then AppendOutgoingDocument(target, groups, seenRanges, analysis, analysisUri, sourceDocument.tree, sourceDocument.path, requested, documents)
			Next
		Else If analysis.syntaxTree Then
			AppendOutgoingDocument(target, groups, seenRanges, analysis, analysisUri, analysis.syntaxTree, analysis.syntaxTree.source.path, requested, documents)
		End If
	End Function

	Function AppendIncomingDocument(target:TJSONArray, groups:TMap, seenRanges:TMap, analysis:TLanguageAnalysis, analysisUri:String, tree:TSyntaxTree, path:String, requested:TJSONObject, documents:TLspDocumentStore)
		If Not tree Or Not tree.source Then Return
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(tree)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local resolved:TResolvedCall = ResolvedRoutineCall(analysis.model, node)
			If Not resolved Or Not MatchesData(resolved.routine, requested) Then Continue
			Local caller:TSymbol = ContainingRoutine(analysis.model, navigator, node)
			If Not Supported(caller) Then Continue
			Local span:TSourceSpan = CallSpan(node, resolved.routine)
			AppendCall(target, groups, seenRanges, "from", caller, analysis, analysisUri, documents, tree.source, path, span)
		Next
	End Function

	Function AppendOutgoingDocument(target:TJSONArray, groups:TMap, seenRanges:TMap, analysis:TLanguageAnalysis, analysisUri:String, tree:TSyntaxTree, path:String, requested:TJSONObject, documents:TLspDocumentStore)
		If Not tree Or Not tree.source Then Return
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(tree)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local resolved:TResolvedCall = ResolvedRoutineCall(analysis.model, node)
			If Not resolved Or Not Supported(resolved.routine) Then Continue
			Local caller:TSymbol = ContainingRoutine(analysis.model, navigator, node)
			If Not MatchesData(caller, requested) Then Continue
			Local span:TSourceSpan = CallSpan(node, resolved.routine)
			AppendCall(target, groups, seenRanges, "to", resolved.routine, analysis, analysisUri, documents, tree.source, path, span)
		Next
	End Function

	Function AppendCall(target:TJSONArray, groups:TMap, seenRanges:TMap, direction:String, symbol:TSymbol, analysis:TLanguageAnalysis, analysisUri:String, documents:TLspDocumentStore, source:TSourceText, callPath:String, span:TSourceSpan)
		If Not span Then Return
		Local item:TJSONObject = Item(symbol, analysis, analysisUri, documents)
		If Not item Then Return
		Local groupKey:String = SymbolKey(symbol)
		If Not groupKey.length Then Return
		Local rangeKey:String = SnapshotPathKey(callPath) + "|" + span.start + ":" + span.length + "|" + groupKey
		If seenRanges.Contains(rangeKey) Then Return
		seenRanges.Insert(rangeKey, span)
		Local entry:TJSONObject = TJSONObject(groups.ValueForKey(groupKey))
		If Not entry Then
			entry = JsonObject()
			entry.Set(direction, item)
			entry.Set("fromRanges", JsonArray())
			groups.Insert(groupKey, entry)
			target.Append(entry)
		End If
		TJSONArray(entry.Get("fromRanges")).Append(TLspPositions.Range(source, span))
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

	Function Item:TJSONObject(symbol:TSymbol, analysis:TLanguageAnalysis, analysisUri:String, documents:TLspDocumentStore)
		If Not Supported(symbol) Or Not analysis Then Return Null
		Local path:String = symbol.originPath
		If Not path.length And analysis.syntaxTree Then path = analysis.syntaxTree.source.path
		If Not path.ToLower().EndsWith(".bmx") Then Return Null
		Local source:TSourceText = TBlitzMaxLspNavigation.SourceForPath(path, analysis, documents)
		If Not source Then Return Null
		Local selection:TSourceSpan
		Local fullRange:TSourceSpan
		If Not symbol.isImported And symbol.declaration And symbol.nameToken Then
			selection = symbol.nameToken.span
			fullRange = symbol.declaration.span
		Else If symbol.originLine > 0 Then
			selection = TBlitzMaxLspNavigation.ProvenanceSpan(source, symbol)
			Local line:Int = symbol.originLine - 1
			Local first:Int = source.Offset(line, 0)
			Local last:Int = source.Offset(line, 2147483647)
			fullRange = TSourceSpan.Create(first, last - first)
		End If
		If Not selection Or Not fullRange Then Return Null
		Local result:TJSONObject = JsonObject()
		result.Set("name", symbol.name)
		result.Set("kind", RoutineKind(symbol))
		Local detail:String = "Function"
		If IsInstanceRoutine(symbol) Then detail = "Method"
		If symbol.containingScope And symbol.containingScope.owner Then detail :+ " — " + symbol.containingScope.owner.QualifiedName()
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
		data.Set("originColumn", symbol.originColumn)
		result.Set("data", data)
		Return result
	End Function

	Function ItemData:TJSONObject(item:TJSONObject)
		If Not item Then Return Null
		Return TJSONObject(item.Get("data"))
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

	Function MatchesData:Int(symbol:TSymbol, data:TJSONObject)
		If Not Supported(symbol) Or Not data Then Return False
		If symbol.kind <> data.GetInteger("kind") Or symbol.name.ToLower() <> data.GetString("name").ToLower() Then Return False
		If symbol.originLine <> data.GetInteger("originLine") Or symbol.originColumn <> data.GetInteger("originColumn") Then Return False
		If SnapshotPathKey(symbol.originPath) <> SnapshotPathKey(data.GetString("originPath")) Then Return False
		Local qualifiedName:String = data.GetString("qualifiedName")
		Return Not qualifiedName.length Or symbol.QualifiedName().ToLower() = qualifiedName.ToLower()
	End Function

	Function SymbolKey:String(symbol:TSymbol)
		If Not Supported(symbol) Or Not symbol.originPath.length Then Return ""
		Return SnapshotPathKey(symbol.originPath) + "|" + symbol.originLine + ":" + symbol.originColumn + "|" + symbol.QualifiedName().ToLower()
	End Function
End Type
