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

' References across loaded semantic compilation units in the requesting
' workspace. Root-and-Include trees share exact symbol identity; separate roots
' are joined only when their bound symbols carry identical source provenance.
' Unopened and unrelated workspace files are never scanned speculatively.
Type TBlitzMaxLspReferences
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int, includeDeclaration:Int)
		Local result:TJSONArray = JsonArray()
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Or Not context.location Or Not context.location.symbol Then Return result
		Local symbol:TSymbol = context.location.symbol
		Local seen:TMap = New TMap
		Local seenModels:TMap = New TMap
		AppendAnalysis(result, seen, seenModels, context.analysis, symbol, workspace, includeDeclaration)
		For Local value:Object = EachIn workspace.analyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			AppendAnalysis(result, seen, seenModels, analysis, symbol, workspace, includeDeclaration)
		Next
		For Local rootPath:String = EachIn workspace.ProjectCandidateRoots(symbol.name, symbol.originPath)
			Local analysis:TLanguageAnalysis = workspace.ProjectFeatureAnalysis(rootPath)
			AppendAnalysis(result, seen, seenModels, analysis, symbol, workspace, includeDeclaration)
		Next
		For Local value:Object = EachIn workspace.projectAnalyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			AppendAnalysis(result, seen, seenModels, analysis, symbol, workspace, includeDeclaration)
		Next
		If includeDeclaration And symbol.isImported Then AppendSourceDeclaration(result, symbol, document.path, context.analysis, workspace)
		Return result
	End Function

	Function AppendAnalysis(target:TJSONArray, seen:TMap, seenModels:TMap, analysis:TLanguageAnalysis, symbol:TSymbol, workspace:TLspWorkspaceContext, includeDeclaration:Int)
		If Not analysis Or Not analysis.model Or seenModels.Contains(analysis.model) Then Return
		seenModels.Insert(analysis.model, analysis.model)
		If analysis.snapshot And analysis.snapshot.documents.length Then
			For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If Not sourceDocument Or Not sourceDocument.tree Then Continue
				AppendDocument(target, seen, analysis.model, symbol, sourceDocument.tree, sourceDocument.path, workspace, includeDeclaration)
			Next
		Else If analysis.syntaxTree Then
			AppendDocument(target, seen, analysis.model, symbol, analysis.syntaxTree, analysis.syntaxTree.source.path, workspace, includeDeclaration)
		End If
	End Function

	Function AppendDocument(target:TJSONArray, seen:TMap, model:TSemanticModel, symbol:TSymbol, tree:TSyntaxTree, path:String, workspace:TLspWorkspaceContext, includeDeclaration:Int)
		If Not tree Or Not tree.source Then Return
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(tree)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local matches:Int = ReferencesSymbol(model, node, symbol)
			If includeDeclaration And SymbolsMatch(model.DeclaredSymbol(node), symbol) Then matches = True
			If Not matches Then Continue
			Local span:TSourceSpan = TBlitzMaxLspNavigation.ReferenceSpan(node)
			If Not span Then Continue
			Local key:String = SnapshotPathKey(path) + "|" + span.start + ":" + span.length
			If seen.Contains(key) Then Continue
			seen.Insert(key, span)
			Local location:TJSONObject = JsonObject()
			location.Set("uri", TBlitzMaxLspNavigation.UriForPath(path, workspace.documents))
			location.Set("range", TLspPositions.Range(tree.source, span))
			target.Append(location)
		Next
	End Function

	Function ReferencesSymbol:Int(model:TSemanticModel, node:TSyntaxNode, symbol:TSymbol)
		If SymbolsMatch(model.ReferencedSymbol(node), symbol) Then Return True
		Local typeReference:TTypeReferenceSyntax = TTypeReferenceSyntax(node)
		If typeReference And SymbolsMatch(TBlitzMaxLspNavigation.TypeSymbol(model.TypeOf(typeReference)), symbol) Then Return True
		Return False
	End Function

	Function SymbolsMatch:Int(candidate:TSymbol, target:TSymbol)
		If candidate = target Then Return True
		If Not candidate Or Not target Or candidate.kind <> target.kind Then Return False
		If Not candidate.originPath.length Or Not target.originPath.length Then Return False
		If SnapshotPathKey(candidate.originPath) <> SnapshotPathKey(target.originPath) Then Return False
		If candidate.originLine <> target.originLine Or candidate.originColumn <> target.originColumn Then Return False
		Return candidate.QualifiedName().ToLower() = target.QualifiedName().ToLower()
	End Function

	Function AppendSourceDeclaration(target:TJSONArray, symbol:TSymbol, fallbackPath:String, analysis:TLanguageAnalysis, workspace:TLspWorkspaceContext)
		Local sourceSymbol:TSymbol = workspace.PreferredSourceSymbol(symbol)
		Local location:TJSONObject = TJSONObject(TBlitzMaxLspNavigation.LocationForSymbol(sourceSymbol, fallbackPath, analysis, workspace.documents))
		If Not location Or ContainsLocation(target, location) Then Return
		target.Append(location)
	End Function

	Function ContainsLocation:Int(target:TJSONArray, location:TJSONObject)
		If Not target Or Not location Then Return False
		Local expectedUri:String = location.GetString("uri")
		Local expectedRange:TJSONObject = TJSONObject(location.Get("range"))
		Local expectedStart:TJSONObject
		If expectedRange Then expectedStart = TJSONObject(expectedRange.Get("start"))
		If Not expectedStart Then Return False
		For Local index:Int = 0 Until target.Size()
			Local item:TJSONObject = TJSONObject(target.Get(index))
			If Not item Or item.GetString("uri") <> expectedUri Then Continue
			Local range:TJSONObject = TJSONObject(item.Get("range"))
			Local start:TJSONObject
			If range Then start = TJSONObject(range.Get("start"))
			If start And start.GetInteger("line") = expectedStart.GetInteger("line") And start.GetInteger("character") = expectedStart.GetInteger("character") Then Return True
		Next
		Return False
	End Function
End Type
