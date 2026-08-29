' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "auto_import_completion.bmx"
Import "documents.bmx"
Import "import_completion.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

' A source declaration eligible for generated bbdoc. This stays local to the
' protocol adapter because it describes the edit surface, not language semantics.
Type TGeneratedBBDocTarget
	Field node:TSyntaxNode
	Field anchorToken:TSyntaxToken
	Field symbol:TSymbol
	Field name:String
	Field displayKind:String
	Field firstLine:Int
	Field lastLine:Int
	Field headerStart:Int
	Field headerEnd:Int
	Field hasReturns:Int
	Field parameterNames:String[] = New String[0]

	Function Create:TGeneratedBBDocTarget(node:TSyntaxNode, navigator:TSyntaxNavigator, model:TSemanticModel, source:TSourceText)
		If Not node Or Not navigator Or Not model Or Not source Then Return Null
		Local result:TGeneratedBBDocTarget = New TGeneratedBBDocTarget
		result.node = node
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine Then
			result.anchorToken = routine.declarationToken
			result.symbol = model.DeclaredSymbol(routine)
			If routine.isMethod Then result.displayKind = "Method" Else result.displayKind = "Function"
			If routine.signature Then
				result.headerEnd = routine.signature.span.EndOffset()
				For Local parameter:TParameterSyntax = EachIn routine.signature.parameters
					If parameter And parameter.nameToken And Not parameter.nameToken.missing Then result.parameterNames :+ [parameter.nameToken.text]
				Next
			End If
			If result.symbol And result.symbol.declaredType And result.symbol.declaredType <> model.BuiltinType("Void") Then result.hasReturns = True
		Else
			Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
			If typeDeclaration Then
				result.anchorToken = typeDeclaration.declarationToken
				result.symbol = model.DeclaredSymbol(typeDeclaration)
				result.displayKind = CapitalizeBBDocKind(typeDeclaration.declarationToken.text)
				If typeDeclaration.header Then result.headerEnd = typeDeclaration.header.span.EndOffset()
			Else
				Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(node)
				If enumDeclaration Then
					result.anchorToken = enumDeclaration.enumToken
					result.symbol = model.DeclaredSymbol(enumDeclaration)
					result.displayKind = "Enum"
				Else
					Local enumValue:TEnumValueSyntax = TEnumValueSyntax(node)
					If enumValue Then
						result.anchorToken = enumValue.nameToken
						result.symbol = model.DeclaredSymbol(enumValue)
						result.displayKind = "Enum value"
						result.headerEnd = enumValue.span.EndOffset()
					Else
						Local variables:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
						If Not variables Or Not variables.declarationToken Then Return Null
						Select variables.declarationToken.text.ToLower()
							Case "field" result.displayKind = "Field"
							Case "global" result.displayKind = "Global"
							Case "const" result.displayKind = "Const"
							Default Return Null
						End Select
						If Not variables.declarators.length Then Return Null
						result.anchorToken = variables.declarationToken
						result.symbol = model.DeclaredSymbol(variables.declarators[0])
						result.headerEnd = variables.span.EndOffset()
					End If
				End If
			End If
		End If
		If Not result.anchorToken Or Not result.anchorToken.span Or result.anchorToken.missing Then Return Null
		If Not result.symbol Or result.symbol.isImported Or NormalizeWorkspacePath(result.symbol.originPath) <> NormalizeWorkspacePath(source.path) Then Return Null
		result.name = result.symbol.name
		If Not result.name.length Then Return Null
		result.headerStart = result.anchorToken.span.start
		If result.headerEnd <= result.headerStart Then result.headerEnd = source.Offset(source.Position(result.headerStart).line, 2147483647)
		result.firstLine = source.Position(result.headerStart).line
		result.lastLine = source.Position(Max(result.headerStart, result.headerEnd - 1)).line
		Return result
	End Function

	Method HeaderLength:Int()
		Return Max(0, headerEnd - headerStart)
	End Method

	Function CapitalizeBBDocKind:String(value:String)
		If Not value.length Then Return "Type"
		Return value[..1].ToUpper() + value[1..].ToLower()
	End Function
End Type

' Source-backed quick fixes. Each requested diagnostic is matched against the
' current immutable syntax tree before an edit is offered, preventing a stale
' or fabricated client range from deleting unrelated source text.
Type TBlitzMaxLspCodeActions
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, params:TJSONObject, workspaceSnippetEditSupport:Int = False)
		Local result:TJSONArray = JsonArray()
		If Not document Or Not workspace Or Not params Then Return result
		Local context:TJSONObject = TJSONObject(params.Get("context"))
		If Not context Then Return result
		Local only:TJSONArray = TJSONArray(context.Get("only"))

		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.syntaxTree Or Not analysis.syntaxTree.source Then Return result

		If AllowsKind(only, "quickfix") Then AppendQuickFixes(result, document, workspace, analysis, TJSONArray(context.Get("diagnostics")))
		If AllowsKind(only, "refactor.rewrite.bbdoc") Then
			Local action:TJSONObject = GenerateBBDocAction(document, analysis, TJSONObject(params.Get("range")), workspaceSnippetEditSupport)
			If action Then result.Append(action)
		End If
		If AllowsKind(only, "refactor.rewrite.implement") Then
			Local action:TJSONObject = ImplementMissingMembersAction(document, analysis, TJSONObject(params.Get("range")), workspaceSnippetEditSupport)
			If action Then result.Append(action)
		End If
		Return result
	End Function

	Function AllowsKind:Int(only:TJSONArray, offeredKind:String)
		If Not only Or only.Size() = 0 Then Return True
		For Local index:Int = 0 Until only.Size()
			Local kind:TJSONString = TJSONString(only.Get(index))
			If Not kind Then Continue
			Local requested:String = kind.Value()
			If requested = offeredKind Or offeredKind.StartsWith(requested + ".") Then Return True
		Next
		Return False
	End Function

	Function AppendQuickFixes(result:TJSONArray, document:TLspDocument, workspace:TLspWorkspaceContext, analysis:TLanguageAnalysis, requestedDiagnostics:TJSONArray)
		If Not requestedDiagnostics Or requestedDiagnostics.Size() = 0 Then Return
		For Local index:Int = 0 Until requestedDiagnostics.Size()
			Local requested:TJSONObject = TJSONObject(requestedDiagnostics.Get(index))
			If Not requested Then Continue
			If requested.GetString("source").length And requested.GetString("source") <> "blitzmax" Then Continue
			Local requestedRange:TJSONObject = TJSONObject(requested.Get("range"))
			If Not requestedRange Then Continue
			Select requested.GetString("code")
				Case "BMX2105"
					For Local diagnostic:TDiagnostic = EachIn analysis.syntaxTree.diagnostics
						If Not Matches(document, analysis.syntaxTree.source, diagnostic, requestedRange, "BMX2105") Then Continue
						result.Append(RemovePostfixTypeAction(document.uri, analysis.syntaxTree.source, diagnostic.span, requested))
						Exit
					Next
				Case "BMX3300"
					If Not analysis.model Then Continue
					For Local diagnostic:TDiagnostic = EachIn analysis.model.diagnostics
						If Not Matches(document, analysis.syntaxTree.source, diagnostic, requestedRange, "BMX3300") Then Continue
						Local action:TJSONObject = AddMissingImportAction(document, workspace, analysis, diagnostic, requested, False)
						If action Then result.Append(action)
						Exit
					Next
				Case "BMX3100"
					If Not analysis.model Then Continue
					For Local diagnostic:TDiagnostic = EachIn analysis.model.diagnostics
						If Not Matches(document, analysis.syntaxTree.source, diagnostic, requestedRange, "BMX3100") Then Continue
						Local action:TJSONObject = AddMissingImportAction(document, workspace, analysis, diagnostic, requested, True)
						If action Then result.Append(action)
						Exit
					Next
			End Select
		Next
	End Function

	Function GenerateBBDocAction:TJSONObject(document:TLspDocument, analysis:TLanguageAnalysis, requestedRange:TJSONObject, snippetSupport:Int)
		If Not document Or Not analysis Or Not analysis.model Or Not requestedRange Then Return Null
		Local source:TSourceText = analysis.syntaxTree.source
		Local startPosition:TJSONObject = TJSONObject(requestedRange.Get("start"))
		Local endPosition:TJSONObject = TJSONObject(requestedRange.Get("end"))
		If Not startPosition Or Not endPosition Then Return Null
		Local requestedStart:Int = TLspPositions.Offset(source, Int(startPosition.GetInteger("line")), Int(startPosition.GetInteger("character")))
		Local requestedEnd:Int = TLspPositions.Offset(source, Int(endPosition.GetInteger("line")), Int(endPosition.GetInteger("character")))
		If requestedEnd < requestedStart Then requestedEnd = requestedStart
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		If Not navigator Then Return Null
		Local target:TGeneratedBBDocTarget
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local candidate:TGeneratedBBDocTarget = TGeneratedBBDocTarget.Create(node, navigator, analysis.model, source)
			If Not candidate Then Continue
			Local candidateStart:Int = source.Offset(candidate.firstLine, 0)
			If requestedEnd < candidateStart Or requestedStart > candidate.headerEnd Then Continue
			If Not target Or candidate.HeaderLength() < target.HeaderLength() Then target = candidate
		Next
		If Not target Or HasAttachedBBDoc(target.anchorToken, source) Then Return Null
		If target.symbol And target.symbol.documentation Then Return Null

		Local lineStart:Int = source.Offset(target.firstLine, 0)
		Local indent:String = source.text[lineStart..target.anchorToken.span.start]
		Local eol:String = PreferredEol(source.text)
		Local snippet:String = BBDocText(target, indent, eol, True)
		Local plain:String = BBDocText(target, indent, eol, False)
		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, TSourceSpan.Create(lineStart, 0)))
		If snippetSupport Then
			Local snippetValue:TJSONObject = JsonObject()
			snippetValue.Set("kind", "snippet")
			snippetValue.Set("value", snippet)
			edit.Set("snippet", snippetValue)
		Else
			edit.Set("newText", plain)
		End If
		Local edits:TJSONArray = JsonArray()
		edits.Append(edit)
		Local identifier:TJSONObject = JsonObject()
		identifier.Set("uri", document.uri)
		identifier.Set("version", document.version)
		Local documentEdit:TJSONObject = JsonObject()
		documentEdit.Set("textDocument", identifier)
		documentEdit.Set("edits", edits)
		Local documentChanges:TJSONArray = JsonArray()
		documentChanges.Append(documentEdit)
		Local workspaceEdit:TJSONObject = JsonObject()
		workspaceEdit.Set("documentChanges", documentChanges)
		Local action:TJSONObject = JsonObject()
		action.Set("title", "Generate bbdoc for " + target.displayKind + " " + target.name)
		action.Set("kind", "refactor.rewrite.bbdoc")
		action.Set("edit", workspaceEdit)
		Return action
	End Function

	Function ImplementMissingMembersAction:TJSONObject(document:TLspDocument, analysis:TLanguageAnalysis, requestedRange:TJSONObject, snippetSupport:Int)
		If Not document Or Not analysis Or Not analysis.model Or Not requestedRange Then Return Null
		Local source:TSourceText = analysis.syntaxTree.source
		Local startPosition:TJSONObject = TJSONObject(requestedRange.Get("start"))
		Local endPosition:TJSONObject = TJSONObject(requestedRange.Get("end"))
		If Not source Or Not startPosition Or Not endPosition Then Return Null
		Local requestedStart:Int = TLspPositions.Offset(source, Int(startPosition.GetInteger("line")), Int(startPosition.GetInteger("character")))
		Local requestedEnd:Int = TLspPositions.Offset(source, Int(endPosition.GetInteger("line")), Int(endPosition.GetInteger("character")))
		If requestedEnd < requestedStart Then requestedEnd = requestedStart
		Local target:TTypeDeclarationSyntax
		Local targetSymbol:TSymbol
		Local navigator:TSyntaxNavigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
			If Not declaration Or Not declaration.header Or Not declaration.terminator Or Not declaration.terminator.endToken Then Continue
			Local symbol:TSymbol = analysis.model.DeclaredSymbol(declaration)
			If Not symbol Or symbol.kind <> SYMBOL_TYPE Or symbol.isImported Or SnapshotPathKey(symbol.originPath) <> SnapshotPathKey(document.path) Then Continue
			Local headerStart:Int = declaration.declarationToken.span.start
			Local headerEnd:Int = declaration.header.span.EndOffset()
			If requestedEnd < headerStart Or requestedStart > headerEnd Then Continue
			If Not target Or declaration.span.length < target.span.length Then target = declaration; targetSymbol = symbol
		Next
		If Not target Or Not targetSymbol Then Return Null
		Local obligations:TAbstractRoutineObligation[] = analysis.model.AbstractObligations(targetSymbol)
		If Not obligations.length Then Return Null

		Local eol:String = PreferredEol(source.text)
		Local endLine:Int = source.Position(target.terminator.endToken.span.start).line
		Local insertionOffset:Int = source.Offset(endLine, 0)
		Local typeIndent:String = source.text[insertionOffset..target.terminator.endToken.span.start]
		Local memberIndent:String = MissingMemberIndent(source, target, typeIndent)
		Local bodyIndent:String = memberIndent + IndentUnit(memberIndent, typeIndent)
		Local generated:String
		Local placeholder:Int = 1
		For Local obligation:TAbstractRoutineObligation = EachIn obligations
			If generated.length Then generated :+ eol
			generated :+ MissingMemberText(obligation, memberIndent, bodyIndent, eol, snippetSupport, placeholder)
		Next
		If snippetSupport Then generated :+ "$0"

		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, TSourceSpan.Create(insertionOffset, 0)))
		If snippetSupport Then
			Local snippetValue:TJSONObject = JsonObject()
			snippetValue.Set("kind", "snippet")
			snippetValue.Set("value", generated)
			edit.Set("snippet", snippetValue)
		Else
			edit.Set("newText", generated)
		End If
		Local edits:TJSONArray = JsonArray()
		edits.Append(edit)
		Local identifier:TJSONObject = JsonObject()
		identifier.Set("uri", document.uri)
		identifier.Set("version", document.version)
		Local documentEdit:TJSONObject = JsonObject()
		documentEdit.Set("textDocument", identifier)
		documentEdit.Set("edits", edits)
		Local documentChanges:TJSONArray = JsonArray()
		documentChanges.Append(documentEdit)
		Local workspaceEdit:TJSONObject = JsonObject()
		workspaceEdit.Set("documentChanges", documentChanges)
		Local action:TJSONObject = JsonObject()
		action.Set("title", "Implement " + obligations.length + " missing member" + PluralSuffix(obligations.length) + " in " + targetSymbol.name)
		action.Set("kind", "refactor.rewrite.implement")
		action.Set("edit", workspaceEdit)
		Return action
	End Function

	Function MissingMemberText:String(obligation:TAbstractRoutineObligation, memberIndent:String, bodyIndent:String, eol:String, snippet:Int, placeholder:Int Var)
		Local routine:TSymbol = obligation.routine
		Local keyword:String = "Function"
		If TMemberCompletion.IsInstanceRoutine(routine) Then keyword = "Method"
		Local result:String = memberIndent + keyword + " " + routine.name + RoutineTypeParameters(routine)
		If obligation.returnType And obligation.returnType.DisplayName().ToLower() <> "void" Then result :+ ":" + obligation.returnType.DisplayName()
		result :+ "("
		For Local index:Int = 0 Until obligation.parameterTypes.length
			If index Then result :+ ", "
			Local parameterType:TSemanticType = obligation.parameterTypes[index]
			If TStaticArraySemanticType(parameterType) Then result :+ "StaticArray "
			Local parameterName:String = "arg" + (index + 1)
			If index < routine.parameters.length And routine.parameters[index] And routine.parameters[index].symbol Then parameterName = routine.parameters[index].symbol.name
			result :+ parameterName + ":"
			If parameterType Then result :+ parameterType.DisplayName() Else result :+ "Object"
			If index < routine.parameters.length And routine.parameters[index] Then
				If routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
				If routine.parameters[index].optional Then
					result :+ " = "
					If routine.parameters[index].defaultValue Then result :+ routine.parameters[index].defaultValue.DisplayValue() Else result :+ "Null"
				End If
			End If
		Next
		result :+ ")" + RoutineConstraints(routine, obligation.ownerType)
		If keyword = "Method" Then result :+ " Override"
		result :+ eol
		result :+ bodyIndent + "Throw ~q"
		If snippet Then
			result :+ Placeholder(placeholder, "Not implemented")
			placeholder :+ 1
		Else
			result :+ "Not implemented"
		End If
		result :+ "~q" + eol + memberIndent + "End " + keyword + eol
		Return result
	End Function

	Function RoutineTypeParameters:String(routine:TSymbol)
		If Not routine Or Not routine.genericArity Then Return ""
		Local result:String = "<"
		Local added:Int
		If routine.memberScope Then
			For Local symbol:TSymbol = EachIn routine.memberScope.declaredSymbols
				If symbol.kind <> SYMBOL_TYPE_PARAMETER Then Continue
				If added Then result :+ ", "
				result :+ symbol.name
				added :+ 1
			Next
		End If
		While added < routine.genericArity
			If added Then result :+ ", "
			result :+ "T" + (added + 1)
			added :+ 1
		Wend
		Return result + ">"
	End Function

	Function RoutineConstraints:String(routine:TSymbol, ownerType:TNamedSemanticType)
		If Not routine Or Not routine.genericConstraints.length Then Return ""
		Local substitutions:TMap = TMemberCompletion.TypeSubstitutions(ownerType)
		Local result:String = " Where "
		For Local constraintIndex:Int = 0 Until routine.genericConstraints.length
			Local constraint:TGenericConstraintInfo = routine.genericConstraints[constraintIndex]
			If constraintIndex Then result :+ ", "
			If constraint.parameterSymbol Then result :+ constraint.parameterSymbol.name Else result :+ "T" + (constraintIndex + 1)
			result :+ " Extends "
			For Local boundIndex:Int = 0 Until constraint.bounds.length
				If boundIndex Then result :+ " And "
				Local bound:TSemanticType = TGenericRoutineInference.Substitute(constraint.bounds[boundIndex], substitutions)
				If bound Then result :+ bound.DisplayName() Else result :+ "Object"
			Next
		Next
		Return result
	End Function

	Function MissingMemberIndent:String(source:TSourceText, declaration:TTypeDeclarationSyntax, typeIndent:String)
		If declaration.body Then
			For Local statement:TSyntaxNode = EachIn declaration.body.statements
				If Not statement Or Not statement.span Then Continue
				Local line:Int = source.Position(statement.span.start).line
				Local lineStart:Int = source.Offset(line, 0)
				Local indent:String = source.text[lineStart..statement.span.start]
				If indent.Trim().length = 0 And indent.length > typeIndent.length Then Return indent
			Next
		End If
		Return typeIndent + "~t"
	End Function

	Function IndentUnit:String(memberIndent:String, typeIndent:String)
		If memberIndent.length > typeIndent.length Then Return memberIndent[typeIndent.length..]
		Return "~t"
	End Function

	Function PluralSuffix:String(count:Int)
		If count = 1 Then Return ""
		Return "s"
	End Function

	Function HasAttachedBBDoc:Int(token:TSyntaxToken, source:TSourceText)
		If Not token Then Return False
		For Local index:Int = token.leadingTrivia.length - 1 To 0 Step -1
			Local trivia:TSyntaxTrivia = token.leadingTrivia[index]
			If Not trivia Or trivia.kind <> TRIVIA_BLOCK_COMMENT Then Continue
			Local lines:String[] = trivia.text.Replace("~r~n", "~n").Replace("~r", "~n").Split("~n")
			For Local line:String = EachIn lines
				If line.Trim().ToLower().StartsWith("bbdoc:") Then Return True
			Next
			Return False
		Next
		' Empty bbdoc blocks intentionally do not become semantic documentation.
		' Recover that case from the immediately preceding source lines because a
		' block comment may be carried as trivia by a separator token.
		If source And token.span Then
			Local declarationLine:Int = source.Position(token.span.start).line
			If declarationLine > 0 Then
				Local normalized:String = source.text.Replace("~r~n", "~n").Replace("~r", "~n")
				Local lines:String[] = normalized.Split("~n")
				Local lineIndex:Int = declarationLine - 1
				If lineIndex < lines.length And (lines[lineIndex].Trim().ToLower() = "end rem" Or lines[lineIndex].Trim().ToLower() = "endrem") Then
					Local foundMarker:Int
					lineIndex :- 1
					While lineIndex >= 0
						Local line:String = lines[lineIndex].Trim().ToLower()
						If line.StartsWith("bbdoc:") Then foundMarker = True
						If line = "rem" Then Return foundMarker
						lineIndex :- 1
					Wend
				End If
			End If
		End If
		Return False
	End Function

	Function BBDocText:String(target:TGeneratedBBDocTarget, indent:String, eol:String, snippet:Int)
		Local result:String = indent + "Rem" + eol
		Local placeholder:Int = 1
		result :+ indent + "bbdoc: "
		If snippet Then result :+ Placeholder(placeholder, "Summary of " + target.name + ".")
		result :+ eol
		placeholder :+ 1
		If target.hasReturns Then
			result :+ indent + "returns: "
			If snippet Then result :+ Placeholder(placeholder, "Description of the returned value.")
			result :+ eol
			placeholder :+ 1
		End If
		For Local parameterName:String = EachIn target.parameterNames
			result :+ indent + "param: "
			If snippet Then result :+ Placeholder(placeholder, "Description of " + parameterName + ".")
			result :+ eol
			placeholder :+ 1
		Next
		result :+ indent + "End Rem" + eol
		If snippet Then result :+ "$0"
		Return result
	End Function

	Function Placeholder:String(index:Int, value:String)
		value = value.Replace("\", "\\").Replace("$", "\$").Replace("}", "\}")
		Return "${" + index + ":" + value + "}"
	End Function

	Function PreferredEol:String(text:String)
		If text.Contains("~r~n") Then Return "~r~n"
		If text.Contains("~r") Then Return "~r"
		Return "~n"
	End Function

	Function Matches:Int(document:TLspDocument, source:TSourceText, diagnostic:TDiagnostic, requestedRange:TJSONObject, code:String)
		If Not diagnostic Or diagnostic.code <> code Or Not diagnostic.span Then Return False
		If diagnostic.path.length And NormalizeWorkspacePath(diagnostic.path) <> NormalizeWorkspacePath(document.path) Then Return False
		Return SameRange(TLspPositions.Range(source, diagnostic.span), requestedRange)
	End Function

	Function AddMissingImportAction:TJSONObject(document:TLspDocument, workspace:TLspWorkspaceContext, analysis:TLanguageAnalysis, diagnostic:TDiagnostic, requested:TJSONObject, typeOnly:Int)
		If typeOnly Then
			If Not diagnostic.message.StartsWith("Type '") Then Return Null
		Else
			If Not diagnostic.message.StartsWith("Name '") Then Return Null
		End If
		Local name:String = analysis.syntaxTree.source.Slice(diagnostic.span)
		If Not IsIdentifier(name) Then Return Null
		Local moduleName:String
		If typeOnly Then
			moduleName = UniqueModuleForType(workspace, name)
		Else
			moduleName = UniqueModuleForValue(workspace, name)
		End If
		If Not moduleName.length Then Return Null
		Local families:TMap = New TMap
		Local imported:TMap = New TMap
		TBlitzMaxLspImportCompletion.CollectWrittenModules(analysis.syntaxTree.source.text, families, imported)
		If imported.Contains(moduleName.ToLower()) Then Return Null

		Local edit:TJSONObject = TBlitzMaxLspAutoImportCompletion.ImportEdit(analysis.syntaxTree, analysis.syntaxTree.source, moduleName)
		Local edits:TJSONArray = JsonArray()
		edits.Append(edit)
		Local changes:TJSONObject = JsonObject()
		changes.Set(document.uri, edits)
		Local workspaceEdit:TJSONObject = JsonObject()
		workspaceEdit.Set("changes", changes)
		Local diagnostics:TJSONArray = JsonArray()
		diagnostics.Append(requested)
		Local action:TJSONObject = JsonObject()
		action.Set("title", "Import " + moduleName)
		action.Set("kind", "quickfix")
		action.Set("diagnostics", diagnostics)
		action.Set("isPreferred", New TJSONBool.Create(True))
		action.Set("edit", workspaceEdit)
		Return action
	End Function

	Function UniqueModuleForValue:String(workspace:TLspWorkspaceContext, name:String)
		Return UniqueModuleForSymbol(workspace, name, False)
	End Function

	Function UniqueModuleForType:String(workspace:TLspWorkspaceContext, name:String)
		Return UniqueModuleForSymbol(workspace, name, True)
	End Function

	Function UniqueModuleForSymbol:String(workspace:TLspWorkspaceContext, name:String, typeOnly:Int)
		If Not workspace Or Not name.length Then Return ""
		Local installed:TLspInstalledModuleCatalogue = workspace.InstalledCatalogue()
		If Not installed Or Not installed.catalogue Then Return ""
		Local moduleName:String
		For Local symbol:TModuleCatalogueSymbol = EachIn installed.catalogue.SymbolsNamed(name)
			If Not symbol Or symbol.parent Or Not symbol.isPublic Or Not symbol.moduleEntry Or symbol.moduleEntry.isCore Then Continue
			If TInterfaceSymbolImporter.IsLegacyGenericImplementation(symbol.record) Then Continue
			If typeOnly Then
				If Not symbol.IsType() Then Continue
			Else
				If symbol.kind <> SYMBOL_ROUTINE And symbol.kind <> SYMBOL_GLOBAL And symbol.kind <> SYMBOL_CONST Then Continue
			End If
			If Not moduleName.length Then
				moduleName = symbol.moduleEntry.name
			Else If moduleName.ToLower() <> symbol.moduleEntry.normalizedName Then
				Return ""
			End If
		Next
		Return moduleName
	End Function

	Function IsIdentifier:Int(value:String)
		If Not value.length Or Not TBlitzMaxLexer.IsIdentifierStart(value[0]) Then Return False
		For Local index:Int = 1 Until value.length
			If Not TBlitzMaxLexer.IsIdentifierPart(value[index]) Then Return False
		Next
		Return True
	End Function

	Function SameRange:Int(left:TJSONObject, right:TJSONObject)
		If Not left Or Not right Then Return False
		Local leftStart:TJSONObject = TJSONObject(left.Get("start"))
		Local leftEnd:TJSONObject = TJSONObject(left.Get("end"))
		Local rightStart:TJSONObject = TJSONObject(right.Get("start"))
		Local rightEnd:TJSONObject = TJSONObject(right.Get("end"))
		If Not leftStart Or Not leftEnd Or Not rightStart Or Not rightEnd Then Return False
		Return leftStart.GetInteger("line") = rightStart.GetInteger("line") And ..
			leftStart.GetInteger("character") = rightStart.GetInteger("character") And ..
			leftEnd.GetInteger("line") = rightEnd.GetInteger("line") And ..
			leftEnd.GetInteger("character") = rightEnd.GetInteger("character")
	End Function

	Function RemovePostfixTypeAction:TJSONObject(uri:String, source:TSourceText, span:TSourceSpan, diagnostic:TJSONObject)
		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, span))
		edit.Set("newText", "")
		Local edits:TJSONArray = JsonArray()
		edits.Append(edit)
		Local changes:TJSONObject = JsonObject()
		changes.Set(uri, edits)
		Local workspaceEdit:TJSONObject = JsonObject()
		workspaceEdit.Set("changes", changes)

		Local diagnostics:TJSONArray = JsonArray()
		diagnostics.Append(diagnostic)
		Local action:TJSONObject = JsonObject()
		action.Set("title", "Remove postfix type annotation")
		action.Set("kind", "quickfix")
		action.Set("diagnostics", diagnostics)
		action.Set("isPreferred", New TJSONBool.Create(True))
		action.Set("edit", workspaceEdit)
		Return action
	End Function
End Type
