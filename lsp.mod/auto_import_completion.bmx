' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "import_completion.bmx"
Import "positions.bmx"
Import "workspaces.bmx"

Const LSP_AUTO_IMPORT_MINIMUM_PREFIX:Int = 3
Const LSP_AUTO_IMPORT_LIMIT:Int = 64

' Completion candidates backed by installed compiler interfaces. These remain
' outside the semantic model until their additional edit makes the module a
' real source import.
Type TBlitzMaxLspAutoImportCompletion
	Function Query:TJSONArray(document:TLspDocument, workspace:TLspWorkspaceContext, analysis:TLanguageAnalysis, source:TSourceText, offset:Int, visible:TJSONArray, typeContext:TTypeCompletionResult, ranking:TCompletionRankingContext, snippetSupport:Int)
		Local items:TJSONArray = JsonArray()
		If Not document Or Not workspace Or Not analysis Or Not analysis.model Or Not source Then Return items
		Local prefix:String = TCompletionRankingContext.IdentifierPrefix(source, offset)
		If prefix.length < LSP_AUTO_IMPORT_MINIMUM_PREFIX Then Return items

		Local visibleNames:TMap = New TMap
		If visible Then
			For Local index:Int = 0 Until visible.Size()
				Local item:TJSONObject = TJSONObject(visible.Get(index))
				If item Then visibleNames.Insert(item.GetString("label").ToLower(), item)
			Next
		End If
		Local writtenFamilies:TMap = New TMap
		Local writtenModules:TMap = New TMap
		TBlitzMaxLspImportCompletion.CollectWrittenModules(source.text, writtenFamilies, writtenModules)
		Local importEdits:TMap = New TMap
		Local seen:TMap = New TMap
		Local installed:TLspInstalledModuleCatalogue = workspace.InstalledCatalogue()
		If Not installed Or Not installed.catalogue Then Return items
		For Local symbol:TModuleCatalogueSymbol = EachIn installed.catalogue.ExportedTopLevelSymbolsWithPrefix(prefix, LSP_AUTO_IMPORT_LIMIT * 2)
			If items.Size() >= LSP_AUTO_IMPORT_LIMIT Then Exit
			If Not IsContextCandidate(symbol, typeContext) Then Continue
			If visibleNames.Contains(symbol.normalizedName) Then Continue
			Local moduleName:String = symbol.moduleEntry.name
			If writtenModules.Contains(moduleName.ToLower()) Then Continue
			Local identity:String = moduleName.ToLower() + "|" + symbol.normalizedName + "|" + symbol.kind + "|" + symbol.record.signatureText.ToLower()
			If seen.Contains(identity) Then Continue
			seen.Insert(identity, symbol)
			Local importEdit:TJSONObject = TJSONObject(importEdits.ValueForKey(moduleName.ToLower()))
			If Not importEdit Then
				importEdit = ImportEdit(analysis.syntaxTree, source, moduleName)
				importEdits.Insert(moduleName.ToLower(), importEdit)
			End If
			Local item:TJSONObject = CompletionItem(symbol, document.uri, source, offset, importEdit, ranking, snippetSupport)
			If item Then items.Append(item)
		Next
		Return items
	End Function

	Function IsContextCandidate:Int(symbol:TModuleCatalogueSymbol, typeContext:TTypeCompletionResult)
		If Not symbol Then Return False
		If typeContext Then
			If Not symbol.IsType() Then Return False
			If typeContext.isNewExpression And (symbol.kind = SYMBOL_INTERFACE Or symbol.kind = SYMBOL_ENUM) Then Return False
			Return True
		End If
		Return symbol.kind = SYMBOL_ROUTINE Or symbol.kind = SYMBOL_GLOBAL Or symbol.kind = SYMBOL_CONST
	End Function

	Function CompletionItem:TJSONObject(symbol:TModuleCatalogueSymbol, documentUri:String, source:TSourceText, offset:Int, importEdit:TJSONObject, ranking:TCompletionRankingContext, snippetSupport:Int)
		If Not symbol Or Not importEdit Then Return Null
		Local item:TJSONObject = JsonObject()
		item.Set("label", symbol.name)
		item.Set("kind", CompletionKind(symbol))
		Local detail:String = DeclarationDisplay(symbol)
		If detail.length Then item.Set("detail", detail + " — auto import from " + symbol.moduleEntry.name)
		Local labelDetails:TJSONObject = JsonObject()
		If symbol.kind = SYMBOL_ROUTINE Then
			Local signature:TRoutineSignatureSyntax = RoutineSignature(symbol.record)
			If signature Then labelDetails.Set("detail", ParameterList(signature))
		End If
		labelDetails.Set("description", symbol.moduleEntry.name)
		item.Set("labelDetails", labelDetails)
		Local insertionText:String = symbol.name
		Local snippet:Int = snippetSupport And symbol.kind = SYMBOL_ROUTINE And ShouldInsertCallSnippet(symbol.record, ranking, source, offset)
		If snippet Then insertionText = CallSnippet(symbol.record)
		item.Set("insertText", insertionText)
		If snippet Then item.Set("insertTextFormat", 2)
		item.Set("filterText", symbol.name)
		item.Set("textEdit", ReplacementEdit(source, offset, insertionText))
		Local edits:TJSONArray = JsonArray()
		edits.Append(importEdit)
		item.Set("additionalTextEdits", edits)
		item.Set("sortText", "9" + symbol.normalizedName + "|" + symbol.moduleEntry.normalizedName + "|" + symbol.record.signatureText.ToLower())
		item.Set("data", ItemData(symbol, documentUri, detail))
		Return item
	End Function

	Function ItemData:TJSONObject(symbol:TModuleCatalogueSymbol, documentUri:String, detail:String)
		Local data:TJSONObject = JsonObject()
		data.Set("uri", documentUri)
		data.Set("autoImportModule", symbol.moduleEntry.name)
		data.Set("name", symbol.name)
		data.Set("symbolKind", symbol.kind)
		data.Set("originPath", symbol.originPath)
		data.Set("originLine", symbol.originLine)
		data.Set("detail", detail)
		data.Set("signature", symbol.record.signatureText)
		Return data
	End Function

	Function ImportEdit:TJSONObject(tree:TSyntaxTree, source:TSourceText, moduleName:String)
		Local offset:Int
		Local prefix:String
		Local newline:String = "~n"
		If source.text.Contains("~r~n") Then newline = "~r~n"
		Local root:TCompilationUnitSyntax
		If tree Then root = tree.root
		Local lastImport:TImportDirectiveSyntax
		If root Then
			For Local node:TSyntaxNode = EachIn root.members
				Local importDirective:TImportDirectiveSyntax = TImportDirectiveSyntax(node)
				If importDirective Then lastImport = importDirective
			Next
		End If
		If lastImport Then
			offset = lastImport.span.EndOffset()
			prefix = newline
		Else If root And root.sourceModeDeclaration Then
			offset = root.sourceModeDeclaration.span.EndOffset()
			prefix = newline + newline
		Else
			offset = 0
		End If
		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, TSourceSpan.Create(offset, 0)))
		If offset = 0 Then edit.Set("newText", "Import " + moduleName + newline + newline) Else edit.Set("newText", prefix + "Import " + moduleName)
		Return edit
	End Function

	Function CompletionKind:Int(symbol:TModuleCatalogueSymbol)
		Select symbol.kind
			Case SYMBOL_ROUTINE Return 3
			Case SYMBOL_GLOBAL Return 6
			Case SYMBOL_CONST Return 21
			Case SYMBOL_TYPE Return 7
			Case SYMBOL_STRUCT Return 22
			Case SYMBOL_INTERFACE Return 8
			Case SYMBOL_ENUM Return 13
		End Select
		Return 1
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

	Function DeclarationDisplay:String(symbol:TModuleCatalogueSymbol)
		If Not symbol Or Not symbol.record Then Return ""
		Select symbol.kind
			Case SYMBOL_TYPE Return "Type " + symbol.name
			Case SYMBOL_STRUCT Return "Struct " + symbol.name
			Case SYMBOL_INTERFACE Return "Interface " + symbol.name
			Case SYMBOL_ENUM Return "Enum " + symbol.name
			Case SYMBOL_ROUTINE
				Local signature:TRoutineSignatureSyntax = RoutineSignature(symbol.record)
				If Not signature Then Return "Function " + symbol.name
				Local result:String = "Function " + symbol.name
				If signature.genericParameters.length Then
					result :+ "<"
					For Local index:Int = 0 Until signature.genericParameters.length
						If index Then result :+ ", "
						result :+ signature.genericParameters[index].nameToken.text
					Next
					result :+ ">"
				End If
				If signature.returnType Then result :+ ":" + TypeText(signature.returnType)
				If signature.callableReturnType Then result :+ ":" + CallableText(signature.callableReturnType)
				Return result + ParameterList(signature)
			Case SYMBOL_GLOBAL Return VariableDisplay("Global", symbol)
			Case SYMBOL_CONST Return VariableDisplay("Const", symbol)
		End Select
		Return symbol.name
	End Function

	Function VariableDisplay:String(keyword:String, symbol:TModuleCatalogueSymbol)
		TInterfaceSignatureDecoder.DecodeRecord(symbol.record)
		Local result:String = keyword + " " + symbol.name
		If symbol.record.declaredTypeSyntax Then result :+ ":" + TypeText(symbol.record.declaredTypeSyntax)
		If symbol.record.callableTypeSyntax Then result :+ ":" + CallableText(symbol.record.callableTypeSyntax)
		Return result
	End Function

	Function RoutineSignature:TRoutineSignatureSyntax(record:TInterfaceRecord)
		If Not record Then Return Null
		If Not record.routineSignature Then TInterfaceSignatureDecoder.DecodeRecord(record)
		Return record.routineSignature
	End Function

	Function ParameterList:String(signature:TRoutineSignatureSyntax)
		If Not signature Then Return "()"
		Local result:String = "("
		For Local index:Int = 0 Until signature.parameters.length
			If index Then result :+ ", "
			Local parameter:TParameterSyntax = signature.parameters[index]
			If parameter.nameToken Then result :+ parameter.nameToken.text Else result :+ "arg" + (index + 1)
			result :+ ":"
			If parameter.callableType Then result :+ CallableText(parameter.callableType) Else result :+ TypeText(parameter.declaredType)
			If parameter.varToken Then result :+ " Var"
			If parameter.assignmentToken Then result :+ " = ..."
		Next
		Return result + ")"
	End Function

	Function TypeText:String(syntax:TTypeReferenceSyntax)
		If Not syntax Then Return "Void"
		Return TokenText(syntax.tokens)
	End Function

	Function CallableText:String(syntax:TCallableTypeSyntax)
		If Not syntax Then Return "<unresolved>"
		Local result:String
		If syntax.returnType Then result = TypeText(syntax.returnType)
		result :+ "("
		For Local index:Int = 0 Until syntax.parameters.length
			If index Then result :+ ", "
			Local parameter:TParameterSyntax = syntax.parameters[index]
			If parameter.nameToken Then result :+ parameter.nameToken.text + ":"
			If parameter.callableType Then result :+ CallableText(parameter.callableType) Else result :+ TypeText(parameter.declaredType)
			If parameter.varToken Then result :+ " Var"
		Next
		result :+ ")"
		For Local suffix:TTypeSuffixSyntax = EachIn syntax.suffixes
			If suffix.suffixKind = TYPE_SUFFIX_POINTER Then
				If suffix.tokens.length Then result :+ " " + TokenText(suffix.tokens) Else result :+ " Ptr"
			Else If suffix.suffixKind = TYPE_SUFFIX_ARRAY Then
				If suffix.tokens.length Then result :+ TokenText(suffix.tokens) Else result :+ "[]"
			End If
		Next
		Return result
	End Function

	Function TokenText:String(tokens:TSyntaxToken[])
		Local result:String
		For Local index:Int = 0 Until tokens.length
			Local token:TSyntaxToken = tokens[index]
			If Not token Or Not token.text.length Then Continue
			If Not result.length And token.text = ":" Then Continue
			If result.length And TBlitzMaxLexer.IsIdentifierPart(result[result.length - 1]) And TBlitzMaxLexer.IsIdentifierPart(token.text[0]) Then result :+ " "
			result :+ token.text
		Next
		Return result
	End Function

	Function ShouldInsertCallSnippet:Int(record:TInterfaceRecord, ranking:TCompletionRankingContext, source:TSourceText, offset:Int)
		If ranking And IsCallableType(ranking.expectedType) Then Return False
		Local cursor:Int = Min(offset, source.Length())
		While cursor < source.Length() And TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor]); cursor :+ 1; Wend
		If cursor < source.Length() And source.text[cursor] = Asc("(") Then Return False
		Return RoutineSignature(record) <> Null
	End Function

	Function IsCallableType:Int(semanticType:TSemanticType)
		Return TCallableSemanticType(semanticType) <> Null Or TClosureSemanticType(semanticType) <> Null
	End Function

	Function CallSnippet:String(record:TInterfaceRecord)
		Local signature:TRoutineSignatureSyntax = RoutineSignature(record)
		If Not signature Then Return record.name
		Local includedCount:Int
		For Local index:Int = 0 Until signature.parameters.length
			If Not signature.parameters[index].assignmentToken Then includedCount = index + 1
		Next
		Local result:String = record.name + "("
		For Local index:Int = 0 Until includedCount
			If index Then result :+ ", "
			Local name:String = "arg" + (index + 1)
			If signature.parameters[index].nameToken Then name = signature.parameters[index].nameToken.text
			result :+ "${" + (index + 1) + ":" + name + "}"
		Next
		Return result + ")$0"
	End Function
End Type
