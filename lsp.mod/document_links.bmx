' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.MaxUtil
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "navigation_features.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspace_analysis.bmx"
Import "workspaces.bmx"

Type TBlitzMaxLspDocumentLinks
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		Local result:TJSONArray = JsonArray()
		If Not document Or Not workspace Then Return result
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not analysis Or Not analysis.syntaxTree Or Not navigator Then Return result

		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local imported:TImportDirectiveSyntax = TImportDirectiveSyntax(node)
			If imported Then
				AppendImport(result, imported, document, workspace, documents, analysis.syntaxTree.source)
				Continue
			End If
			Local included:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
			If included Then AppendInclude(result, included, document, documents, analysis.syntaxTree.source)
		Next
		Return result
	End Function

	Function AppendImport(target:TJSONArray, syntax:TImportDirectiveSyntax, document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore, source:TSourceText)
		If Not syntax Or Not syntax.targetText.length Or syntax.targetTokens.length = 0 Then Return
		Local path:String
		If syntax.isFileImport Then
			path = ResolveRelativePath(document.path, syntax.targetText)
		Else
			path = ModuleSourcePath(workspace.configuration.sdkPath, syntax.targetText)
		End If
		If Not LinkablePath(path, documents) Then Return
		Local span:TSourceSpan
		If syntax.isFileImport Then
			span = TokenContentSpan(syntax.targetTokens[0])
		Else
			Local first:TSyntaxToken = syntax.targetTokens[0]
			Local last:TSyntaxToken = syntax.targetTokens[syntax.targetTokens.length - 1]
			span = TSourceSpan.Create(first.span.start, last.span.EndOffset() - first.span.start)
		End If
		AppendLink(target, span, path, documents, source, "Open imported source")
	End Function

	Function AppendInclude(target:TJSONArray, syntax:TIncludeDirectiveSyntax, document:TLspDocument, documents:TLspDocumentStore, source:TSourceText)
		If Not syntax Or Not syntax.pathToken Or Not syntax.pathText.length Then Return
		Local path:String = ResolveRelativePath(document.path, syntax.pathText)
		If Not LinkablePath(path, documents) Then Return
		AppendLink(target, TokenContentSpan(syntax.pathToken), path, documents, source, "Open included source")
	End Function

	Function AppendLink(target:TJSONArray, span:TSourceSpan, path:String, documents:TLspDocumentStore, source:TSourceText, tooltip:String)
		If Not span Or Not source Then Return
		Local item:TJSONObject = JsonObject()
		item.Set("range", TLspPositions.Range(source, span))
		item.Set("target", TBlitzMaxLspNavigation.UriForPath(path, documents))
		item.Set("tooltip", tooltip)
		target.Append(item)
	End Function

	Function TokenContentSpan:TSourceSpan(token:TSyntaxToken)
		If Not token Then Return Null
		If token.text.length >= 2 And token.text.StartsWith(Chr(34)) And token.text.EndsWith(Chr(34)) Then Return TSourceSpan.Create(token.span.start + 1, token.span.length - 2)
		Return token.span
	End Function

	Function LinkablePath:Int(path:String, documents:TLspDocumentStore)
		If Not path.length Then Return False
		If documents And documents.GetByPath(path) Then Return True
		Return FileType(path) = FILETYPE_FILE
	End Function

	Function ModuleSourcePath:String(sdkPath:String, moduleName:String)
		If Not sdkPath.length Or Not moduleName.length Then Return ""
		Local normalized:String = moduleName.ToLower()
		Local dot:Int = normalized.FindLast(".")
		Local identifier:String = normalized
		If dot >= 0 Then identifier = normalized[dot + 1..]
		Local moduleRoot:String = NormalizeWorkspacePath(sdkPath) + "/mod"
		Return ModulePathAtRoot(moduleRoot, normalized) + "/" + identifier + ".bmx"
	End Function
End Type
