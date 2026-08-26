' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "hover.bmx"
Import "import_completion.bmx"
Import "auto_import_completion.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

Type TBlitzMaxLspCompletion
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int, snippetSupport:Int = False)
		Local items:TJSONArray = JsonArray()
		If Not document Or Not workspace Then Return items
		Local rawSource:TSourceText = TSourceText.Create(document.text, document.path)
		Local rawOffset:Int = TLspPositions.Offset(rawSource, line, character)
		Local importItems:TJSONArray = TBlitzMaxLspImportCompletion.Query(document, workspace, rawSource, rawOffset)
		If importItems Then Return importItems
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.model Or Not analysis.syntaxTree Then Return items
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not navigator Then navigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		Local offset:Int = TLspPositions.Offset(analysis.syntaxTree.source, line, character)
		Local ranking:TCompletionRankingContext = TCompletionRankingContext.Query(analysis.model, navigator, offset)
		Local completion:TMemberCompletionResult = TMemberCompletion.Query(analysis.model, navigator, offset)
		Local symbols:TSymbol[]
		Local typeContext:TTypeCompletionResult
		If completion Then
			symbols = completion.symbols
		Else
			typeContext = TTypeCompletion.Query(analysis.model, navigator, offset)
			If typeContext Then
				items = TypeItems(typeContext, analysis.model, document.uri, analysis.syntaxTree.source, offset)
			Else
				Local contextual:TContextualCompletionResult = TContextualCompletion.Query(analysis.model, navigator, offset)
				If Not contextual Then Return items
				symbols = contextual.symbols
			End If
		End If
		Local seen:TMap = New TMap
		Local sourceOrder:Int
		For Local symbol:TSymbol = EachIn symbols
			Local resolved:TResolvedCall
			Local useSiteType:TSemanticType
			If completion Then
				Local declaringType:TSemanticType = TMemberCompletion.ConstructedDeclaringType(analysis.model, completion.receiverType, symbol)
				resolved = TMemberCompletion.EffectiveRoutine(analysis.model, completion.receiverType, symbol, declaringType)
				useSiteType = TMemberCompletion.EffectiveMemberType(analysis.model, completion.receiverType, symbol, declaringType)
			End If
			Local constantValue:TConstantValue = analysis.model.SymbolConstantValue(symbol)
			Local detail:String = TBlitzMaxLspHover.SymbolDisplay(symbol, resolved, constantValue, useSiteType)
			Local key:String = symbol.name.ToLower() + "|" + detail.ToLower()
			If seen.Contains(key) Then Continue
			seen.Insert(key, symbol)
			Local item:TJSONObject = JsonObject()
			item.Set("label", symbol.name)
			item.Set("kind", CompletionItemKind(symbol))
			If detail.length Then item.Set("detail", detail)
			Local labelDetails:TJSONObject = RoutineLabelDetails(symbol, resolved)
			If Not labelDetails And completion And useSiteType Then labelDetails = MemberLabelDetails(useSiteType)
			If labelDetails Then item.Set("labelDetails", labelDetails)
			Local insertionText:String = symbol.name
			Local snippet:Int = snippetSupport And ShouldInsertCallSnippet(symbol, ranking, analysis.syntaxTree.source, offset)
			If snippet Then insertionText = CallSnippet(symbol, resolved)
			item.Set("insertText", insertionText)
			If snippet Then item.Set("insertTextFormat", 2)
			item.Set("filterText", symbol.name)
			item.Set("textEdit", ReplacementEdit(analysis.syntaxTree.source, offset, insertionText))
			If ranking Then item.Set("sortText", ranking.SortKey(symbol, useSiteType, resolved, sourceOrder))
			Local declaredDetail:String = TBlitzMaxLspHover.SymbolDisplay(symbol, Null, constantValue)
			item.Set("data", ItemData(symbol, document.uri, declaredDetail, detail))
			items.Append(item)
			sourceOrder :+ 1
		Next
		If Not completion Then AppendItems(items, TBlitzMaxLspAutoImportCompletion.Query(document, workspace, analysis, analysis.syntaxTree.source, offset, items, typeContext, ranking, snippetSupport))
		Return items
	End Function

	Function AppendItems(target:TJSONArray, values:TJSONArray)
		If Not target Or Not values Then Return
		For Local index:Int = 0 Until values.Size()
			target.Append(values.Get(index))
		Next
	End Function

	Function ShouldInsertCallSnippet:Int(symbol:TSymbol, ranking:TCompletionRankingContext, source:TSourceText, offset:Int)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return False
		If Not IsCallableRoutineName(symbol.name) Then Return False
		If ranking And IsCallableType(ranking.expectedType) Then Return False
		Local cursor:Int = Min(offset, source.Length())
		While cursor < source.Length() And TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor]); cursor :+ 1; Wend
		If cursor < source.Length() And source.text[cursor] = Asc("(") Then Return False
		Return True
	End Function

	Function IsCallableRoutineName:Int(name:String)
		If Not name.length Or Not TBlitzMaxLexer.IsIdentifierStart(name[0]) Then Return False
		For Local index:Int = 1 Until name.length
			If Not TBlitzMaxLexer.IsIdentifierPart(name[index]) Then Return False
		Next
		Return True
	End Function

	Function IsCallableType:Int(semanticType:TSemanticType)
		Return TCallableSemanticType(semanticType) <> Null Or TClosureSemanticType(semanticType) <> Null
	End Function

	Function CallSnippet:String(symbol:TSymbol, resolved:TResolvedCall)
		Local parameterCount:Int = symbol.parameterTypes.length
		If resolved And resolved.parameterTypes.length Then parameterCount = resolved.parameterTypes.length
		Local includedCount:Int = parameterCount
		If symbol.parameters.length Then
			includedCount = 0
			For Local index:Int = 0 Until Min(parameterCount, symbol.parameters.length)
				If symbol.parameters[index] And Not symbol.parameters[index].optional Then includedCount = index + 1
			Next
			If symbol.parameters.length < parameterCount Then includedCount = parameterCount
		End If
		Local result:String = symbol.name + "("
		For Local index:Int = 0 Until includedCount
			If index Then result :+ ", "
			Local name:String = "arg" + (index + 1)
			If index < symbol.parameters.length And symbol.parameters[index] And symbol.parameters[index].symbol And symbol.parameters[index].symbol.name.length Then name = symbol.parameters[index].symbol.name
			result :+ "${" + (index + 1) + ":" + name + "}"
		Next
		Return result + ")$0"
	End Function

	Function TypeItems:TJSONArray(completion:TTypeCompletionResult, model:TSemanticModel, documentUri:String, source:TSourceText, offset:Int)
		Local items:TJSONArray = JsonArray()
		Local seen:TMap = New TMap
		For Local candidate:TTypeCompletionCandidate = EachIn completion.candidates
			Local detail:String
			Local kind:Int = 14
			If candidate.symbol Then
				detail = TBlitzMaxLspHover.SymbolDisplay(candidate.symbol, Null, model.SymbolConstantValue(candidate.symbol))
				kind = CompletionItemKind(candidate.symbol)
			Else If candidate.builtinType Then
				detail = candidate.builtinType.DisplayName()
			End If
			Local key:String = candidate.name.ToLower() + "|" + detail.ToLower()
			If seen.Contains(key) Then Continue
			seen.Insert(key, candidate)
			Local item:TJSONObject = JsonObject()
			item.Set("label", candidate.name)
			item.Set("kind", kind)
			If detail.length Then item.Set("detail", detail)
			If candidate.symbol Then
				Local labelDetails:TJSONObject = RoutineLabelDetails(candidate.symbol)
				If labelDetails Then item.Set("labelDetails", labelDetails)
			End If
			item.Set("insertText", candidate.name)
			item.Set("filterText", candidate.name)
			item.Set("textEdit", ReplacementEdit(source, offset, candidate.name))
			If candidate.symbol Then item.Set("data", ItemData(candidate.symbol, documentUri, detail))
			Local matchPriority:String = "1"
			If candidate.name.ToLower().StartsWith(completion.prefix.ToLower()) Then matchPriority = "0"
			item.Set("sortText", matchPriority + candidate.constraintPriority + candidate.priority + candidate.name.ToLower())
			items.Append(item)
		Next
		Return items
	End Function

	Function ReplacementEdit:TJSONObject(source:TSourceText, offset:Int, newText:String)
		Local finish:Int = Min(offset, source.Length())
		Local start:Int = finish
		While start > 0 And TBlitzMaxLexer.IsIdentifierPart(source.text[start - 1]); start :- 1; Wend
		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, TSourceSpan.Create(start, finish - start)))
		edit.Set("newText", newText)
		Return edit
	End Function

	' Keep the completion label and insertion text as the bare symbol name while
	' giving clients a compact, overload-specific signature for the suggestion
	' list. Older clients safely ignore this optional LSP 3.17 field.
	Function RoutineLabelDetails:TJSONObject(symbol:TSymbol, resolved:TResolvedCall = Null)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return Null
		Local parameterTypes:TSemanticType[] = symbol.parameterTypes
		If resolved And resolved.parameterTypes.length Then parameterTypes = resolved.parameterTypes
		Local parameterDetail:String = "("
		For Local index:Int = 0 Until parameterTypes.length
			If index Then parameterDetail :+ ", "
			Local name:String = "arg" + (index + 1)
			If index < symbol.parameters.length And symbol.parameters[index] And symbol.parameters[index].symbol Then name = symbol.parameters[index].symbol.name
			parameterDetail :+ name + ":"
			If parameterTypes[index] Then parameterDetail :+ parameterTypes[index].DisplayName() Else parameterDetail :+ "<unresolved>"
			If index < symbol.parameters.length And symbol.parameters[index] Then
				If symbol.parameters[index].passingMode = PARAMETER_PASS_VAR Then parameterDetail :+ " Var"
				If symbol.parameters[index].optional Then parameterDetail :+ " = ..."
			End If
		Next
		parameterDetail :+ ")"
		Local result:TJSONObject = JsonObject()
		result.Set("detail", parameterDetail)
		Local returnType:TSemanticType = symbol.declaredType
		If resolved And resolved.returnType Then returnType = resolved.returnType
		If returnType And returnType.DisplayName().ToLower() <> "void" Then result.Set("description", ":" + returnType.DisplayName())
		Return result
	End Function

	Function MemberLabelDetails:TJSONObject(semanticType:TSemanticType)
		If Not semanticType Then Return Null
		Local display:String = semanticType.DisplayName()
		If Not display.length Then Return Null
		Local result:TJSONObject = JsonObject()
		result.Set("description", ":" + display)
		Return result
	End Function

	Function ItemData:TJSONObject(symbol:TSymbol, documentUri:String, detail:String, presentation:String = "")
		Local data:TJSONObject = JsonObject()
		data.Set("uri", documentUri)
		data.Set("name", symbol.name)
		data.Set("symbolKind", symbol.kind)
		data.Set("originPath", symbol.originPath)
		data.Set("originLine", symbol.originLine)
		data.Set("detail", detail)
		If presentation.length And presentation <> detail Then data.Set("presentation", presentation)
		Return data
	End Function

	Function Resolve:TJSONObject(item:TJSONObject, document:TLspDocument, workspace:TLspWorkspaceContext)
		If Not item Or Not document Or Not workspace Then Return item
		If item.Get("documentation") Then Return item
		Local data:TJSONObject = TJSONObject(item.Get("data"))
		If Not data Then Return item
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.model Then Return item
		If data.GetString("autoImportModule").length Then Return ResolveAutoImport(item, data, analysis, workspace)
		Local symbol:TSymbol = FindSymbol(analysis.model.globalScope, data)
		If Not symbol Then Return item
		Local documentation:TDocumentationComment = workspace.Documentation(symbol)
		Local markdown:String = TBlitzMaxLspDocumentation.Markdown(documentation, symbol, analysis.model)
		Local presentation:String = data.GetString("presentation")
		Local declaration:String = data.GetString("detail")
		If presentation.length And presentation <> declaration Then
			Local signatures:String = "```blitzmax~n" + presentation + "~n```~n~nDeclared as:~n~n```blitzmax~n" + declaration + "~n```"
			If markdown.length Then markdown = signatures + "~n~n" + markdown Else markdown = signatures
		End If
		If markdown.length Then item.Set("documentation", TBlitzMaxLspDocumentation.MarkupContent(markdown))
		Return item
	End Function

	Function ResolveAutoImport:TJSONObject(item:TJSONObject, data:TJSONObject, analysis:TLanguageAnalysis, workspace:TLspWorkspaceContext)
		Local symbol:TModuleCatalogueSymbol = FindAutoImportSymbol(workspace, data)
		If Not symbol Then Return item
		Local declaration:String = data.GetString("detail")
		Local markdown:String
		If declaration.length Then markdown = "```blitzmax~n" + declaration + "~n```~n~nAuto import from `" + symbol.moduleEntry.name + "`."
		Local documentation:TDocumentationComment = symbol.record.documentation
		If Not documentation Then
			Local temporary:TSymbol = New TSymbol
			temporary.name = symbol.name
			temporary.kind = symbol.kind
			temporary.originPath = symbol.originPath
			temporary.originLine = symbol.originLine
			documentation = workspace.Documentation(temporary)
		End If
		Local rendered:String = TBlitzMaxLspDocumentation.Markdown(documentation, Null, analysis.model)
		If rendered.length Then
			If markdown.length Then markdown :+ "~n~n"
			markdown :+ rendered
		End If
		If markdown.length Then item.Set("documentation", TBlitzMaxLspDocumentation.MarkupContent(markdown))
		Return item
	End Function

	Function FindAutoImportSymbol:TModuleCatalogueSymbol(workspace:TLspWorkspaceContext, data:TJSONObject)
		If Not workspace Or Not data Then Return Null
		Local moduleName:String = data.GetString("autoImportModule")
		Local name:String = data.GetString("name")
		Local kind:Int = Int(data.GetInteger("symbolKind"))
		Local signature:String = data.GetString("signature")
		Local originPath:String = data.GetString("originPath")
		Local installed:TLspInstalledModuleCatalogue = workspace.InstalledCatalogue()
		If Not installed Or Not installed.catalogue Then Return Null
		For Local symbol:TModuleCatalogueSymbol = EachIn installed.catalogue.SymbolsQualified(moduleName + "." + name)
			If Not symbol Or symbol.parent Or symbol.kind <> kind Then Continue
			If signature.length And symbol.record.signatureText <> signature Then Continue
			If originPath.length And SnapshotPathKey(symbol.originPath) <> SnapshotPathKey(originPath) Then Continue
			Return symbol
		Next
		Return Null
	End Function

	Function FindSymbol:TSymbol(scope:TScope, data:TJSONObject)
		If Not scope Then Return Null
		Local name:String = data.GetString("name").ToLower()
		Local kind:Int = Int(data.GetInteger("symbolKind"))
		Local originPath:String = data.GetString("originPath")
		Local originLine:Int = Int(data.GetInteger("originLine"))
		Local detail:String = data.GetString("detail")
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol.normalizedName <> name Or symbol.kind <> kind Then Continue
			If originPath.length And SnapshotPathKey(symbol.originPath) <> SnapshotPathKey(originPath) Then Continue
			If originLine > 0 And symbol.originLine <> originLine Then Continue
			If kind = SYMBOL_ROUTINE And detail.length And TBlitzMaxLspHover.SymbolDisplay(symbol, Null, Null) <> detail Then Continue
			Return symbol
		Next
		For Local child:TScope = EachIn scope.children
			Local symbol:TSymbol = FindSymbol(child, data)
			If symbol Then Return symbol
		Next
		Return Null
	End Function

	Function CompletionItemKind:Int(symbol:TSymbol)
		If Not symbol Then Return 1
		Select symbol.kind
			Case SYMBOL_ROUTINE
				If TMemberCompletion.IsInstanceRoutine(symbol) Then Return 2
				Return 3
			Case SYMBOL_FIELD Return 5
			Case SYMBOL_GLOBAL, SYMBOL_LOCAL, SYMBOL_PARAMETER, SYMBOL_CATCH_PARAMETER Return 6
			Case SYMBOL_CONST Return 21
			Case SYMBOL_ENUM_MEMBER Return 20
			Case SYMBOL_TYPE Return 7
			Case SYMBOL_STRUCT Return 22
			Case SYMBOL_INTERFACE Return 8
			Case SYMBOL_ENUM Return 13
			Case SYMBOL_TYPE_PARAMETER Return 25
		End Select
		Return 1
	End Function
End Type
