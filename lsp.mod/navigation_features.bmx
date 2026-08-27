' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.TextStream
Import BRL.Map
Import Text.Json
Import BlitzMax.Language
Import "documents.bmx"
Import "hover.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

Type TBlitzMaxLspNavigation
	Function Definition:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Or Not context.location Or Not context.location.symbol Then Return JsonNull()
		Return LocationForSymbol(workspace.PreferredSourceSymbol(context.location.symbol), document.path, context.analysis, documents)
	End Function

	Function TypeDefinition:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Or Not context.location Then Return JsonNull()
		Local semanticType:TSemanticType = context.location.semanticType
		If Not semanticType And context.location.symbol Then semanticType = context.location.symbol.declaredType
		Local symbol:TSymbol = TypeSymbol(semanticType)
		If Not symbol Then
			For Local node:TSyntaxNode = EachIn context.location.syntax.parents
				Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(node)
				If declarator And declarator.initializer Then
					semanticType = context.analysis.model.ExpressionType(declarator.initializer)
					If Not semanticType Then
						Local bound:TBoundExpression = context.analysis.model.BoundExpression(declarator.initializer)
						If bound Then semanticType = bound.semanticType
					End If
					symbol = TypeSymbol(semanticType)
					Exit
				End If
			Next
		End If
		If Not symbol Then Return JsonNull()
		Return LocationForSymbol(symbol, document.path, context.analysis, documents)
	End Function

	Function TypeSymbol:TSymbol(semanticType:TSemanticType)
		Local current:TSemanticType = semanticType
		For Local depth:Int = 0 Until 32
			If Not current Then Return Null
			Local named:TNamedSemanticType = TNamedSemanticType(current)
			If named Then Return named.symbol
			Local parameter:TTypeParameterSemanticType = TTypeParameterSemanticType(current)
			If parameter Then Return parameter.symbol
			Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(current)
			If builtin Then Return builtin.runtimeSymbol
			Local arrayType:TArraySemanticType = TArraySemanticType(current)
			If arrayType Then current = arrayType.elementType; Continue
			Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(current)
			If staticArrayType Then current = staticArrayType.elementType; Continue
			Local pointer:TPointerSemanticType = TPointerSemanticType(current)
			If pointer Then current = pointer.elementType; Continue
			Local callable:TCallableSemanticType = TCallableSemanticType(current)
			If callable Then current = callable.returnType; Continue
			Return Null
		Next
		Return Null
	End Function

	Function LocationForSymbol:TJSON(symbol:TSymbol, fallbackPath:String, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		If Not symbol Then Return JsonNull()
		Local path:String = symbol.originPath
		If Not path.length Then path = fallbackPath
		' Navigate only when the symbol has a source-backed location. A raw
		' compiler-interface path without source provenance remains suppressed.
		If Not path.ToLower().EndsWith(".bmx") Then Return JsonNull()
		Local targetSource:TSourceText = SourceForPath(path, analysis, documents)
		If Not targetSource Then Return JsonNull()
		Local selection:TSourceSpan
		If symbol.originLine > 0 Then selection = ProvenanceSpan(targetSource, symbol)
		If Not selection And symbol.nameToken Then selection = symbol.nameToken.span
		If Not selection And symbol.declaration Then selection = ReferenceSpan(symbol.declaration)
		If Not selection Then Return JsonNull()
		Local result:TJSONObject = JsonObject()
		result.Set("uri", UriForPath(path, documents))
		result.Set("range", TLspPositions.Range(targetSource, selection))
		Return result
	End Function

	Function ProvenanceSpan:TSourceSpan(source:TSourceText, symbol:TSymbol)
		If Not source Or Not symbol Or symbol.originLine <= 0 Then Return Null
		Local line:Int = symbol.originLine - 1
		Local start:Int = source.Offset(line, Max(0, symbol.originColumn))
		Local lineEnd:Int = source.Offset(line, 2147483647)
		If symbol.name.length Then
			Local relative:Int = source.text[start..lineEnd].ToLower().Find(symbol.name.ToLower())
			If relative >= 0 Then start :+ relative
		End If
		Return TSourceSpan.Create(start, symbol.name.length)
	End Function

	Function DocumentSymbols:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext)
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not analysis Or Not analysis.model Or Not navigator Then Return JsonArray()
		Local result:TJSONArray = JsonArray()
		AppendScopeSymbols(result, analysis.model.globalScope, navigator, analysis.syntaxTree.source)
		Return result
	End Function

	Function AppendScopeSymbols(target:TJSONArray, scope:TScope, navigator:TSyntaxNavigator, source:TSourceText)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If Not symbol Or symbol.isImported Or Not symbol.declaration Or Not navigator.ContainsNode(symbol.declaration) Then Continue
			If symbol.kind = SYMBOL_PARAMETER Or symbol.kind = SYMBOL_TYPE_PARAMETER Or symbol.kind = SYMBOL_CATCH_PARAMETER Then Continue
			If symbol.kind = SYMBOL_LOCAL And scope.kind <> SCOPE_COMPILATION_UNIT Then Continue
			Local item:TJSONObject = JsonObject()
			item.Set("name", symbol.name)
			item.Set("kind", SymbolKind(symbol))
			Local selection:TSourceSpan = symbol.declaration.span
			If symbol.nameToken Then selection = symbol.nameToken.span
			Local fullRange:TSourceSpan = ContainingSpan(symbol.declaration.span, selection)
			item.Set("range", TLspPositions.Range(source, fullRange))
			item.Set("selectionRange", TLspPositions.Range(source, selection))
			If symbol.memberScope And (symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_STRUCT Or symbol.kind = SYMBOL_INTERFACE Or symbol.kind = SYMBOL_ENUM) Then
				Local children:TJSONArray = JsonArray()
				AppendScopeSymbols(children, symbol.memberScope, navigator, source)
				If children.Size() Then item.Set("children", children)
			End If
			target.Append(item)
		Next
	End Function

	Function ContainingSpan:TSourceSpan(fullRange:TSourceSpan, selection:TSourceSpan)
		If Not fullRange Then Return selection
		If Not selection Then Return fullRange
		Local start:Int = Min(fullRange.start, selection.start)
		Local finish:Int = Max(fullRange.EndOffset(), selection.EndOffset())
		Return TSourceSpan.Create(start, finish - start)
	End Function

	Function Highlights:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		Local result:TJSONArray = JsonArray()
		If Not context Or Not context.location Or Not context.location.symbol Then Return result
		Local seen:TMap = New TMap
		For Local value:Object = EachIn context.analysis.model.referencedSymbolMap.Keys()
			Local node:TSyntaxNode = TSyntaxNode(value)
			If node And context.navigator.ContainsNode(node) And context.analysis.model.ReferencedSymbol(node) = context.location.symbol Then AppendHighlight(result, node, context.analysis.syntaxTree.source, seen)
		Next
		For Local value:Object = EachIn context.analysis.model.declaredSymbolMap.Keys()
			Local node:TSyntaxNode = TSyntaxNode(value)
			If node And context.navigator.ContainsNode(node) And context.analysis.model.DeclaredSymbol(node) = context.location.symbol Then AppendHighlight(result, node, context.analysis.syntaxTree.source, seen)
		Next
		Return result
	End Function

	Function AppendHighlight(target:TJSONArray, node:TSyntaxNode, source:TSourceText, seen:TMap)
		If seen.Contains(node) Then Return
		seen.Insert(node, node)
		Local span:TSourceSpan = ReferenceSpan(node)
		If Not span Then Return
		Local item:TJSONObject = JsonObject()
		item.Set("range", TLspPositions.Range(source, span))
		item.Set("kind", 1)
		target.Append(item)
	End Function

	Function SignatureHelp:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int)
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Then Return JsonNull()
		Local resolved:TResolvedCall
		Local call:TCallExpressionSyntax = EnclosingCall(context.navigator, context.offset)
		If context.location And context.location.syntax Then
			For Local node:TSyntaxNode = EachIn context.location.syntax.parents
				If Not resolved Then resolved = context.analysis.model.ResolvedCall(node)
				If resolved And call Then Exit
			Next
		End If
		If call And Not resolved Then resolved = context.analysis.model.ResolvedCall(call)
		Local signatureSet:TCallSignatureSet
		If call Then signatureSet = context.analysis.model.CallSignatures(call)
		If signatureSet And signatureSet.candidates.length Then Return SignatureSetResult(signatureSet, call, context, workspace)
		If Not resolved Then Return JsonNull()
		Local callable:TCallableSemanticType
		Local closure:TClosureSemanticType
		If Not resolved.routine And call And call.callee Then
			Local calleeType:TSemanticType = context.analysis.model.ExpressionType(call.callee)
			closure = TClosureSemanticType(calleeType)
			If closure Then callable = closure.signature Else callable = TCallableSemanticType(calleeType)
			If Not callable Then Return JsonNull()
		End If
		Local signature:TJSONObject = JsonObject()
		Local documentation:TDocumentationComment
		If resolved.routine Then
			signature.Set("label", TBlitzMaxLspHover.RoutineDisplay(resolved.routine, resolved))
			documentation = workspace.Documentation(resolved.routine)
			Local documentationMarkdown:String = TBlitzMaxLspDocumentation.Markdown(documentation, resolved.routine, context.analysis.model)
			If documentationMarkdown.length Then signature.Set("documentation", TBlitzMaxLspDocumentation.MarkupContent(documentationMarkdown))
		Else If closure Then
			signature.Set("label", closure.DisplayName())
		Else
			signature.Set("label", callable.DisplayName())
		End If
		Local parameters:TJSONArray = JsonArray()
		For Local index:Int = 0 Until resolved.parameterTypes.length
			Local parameter:TJSONObject = JsonObject()
			If resolved.routine Then
				parameter.Set("label", ParameterLabel(resolved.routine, resolved, index))
				Local parameterMarkdown:String = TBlitzMaxLspDocumentation.ParameterMarkdown(documentation, index, resolved.routine, context.analysis.model)
				If parameterMarkdown.length Then parameter.Set("documentation", TBlitzMaxLspDocumentation.MarkupContent(parameterMarkdown))
			Else
				parameter.Set("label", StructuralParameterLabel(callable, closure, resolved, index))
			End If
			parameters.Append(parameter)
		Next
		signature.Set("parameters", parameters)
		Local signatures:TJSONArray = JsonArray()
		signatures.Append(signature)
		Local result:TJSONObject = JsonObject()
		result.Set("signatures", signatures)
		result.Set("activeSignature", 0)
		result.Set("activeParameter", ActiveParameter(call, context.offset, resolved.parameterTypes.length, context.analysis.syntaxTree.source))
		Return result
	End Function

	Function SignatureSetResult:TJSON(signatureSet:TCallSignatureSet, call:TCallExpressionSyntax, context:TLspFeatureContext, workspace:TLspWorkspaceContext)
		Local compatibleCount:Int
		For Local candidate:TCallSignatureCandidate = EachIn signatureSet.candidates
			If candidate.compatible Then compatibleCount :+ 1
		Next
		Local signatures:TJSONArray = JsonArray()
		Local activeSignature:Int
		Local outputIndex:Int
		Local bestScore:Int = -1
		For Local candidate:TCallSignatureCandidate = EachIn signatureSet.candidates
			If compatibleCount And Not candidate.compatible Then Continue
			signatures.Append(SignatureInformation(candidate, context, workspace))
			If candidate.selected Then
				activeSignature = outputIndex
				bestScore = -2
			Else If bestScore <> -2 And candidate.score >= 0 And (bestScore < 0 Or candidate.score < bestScore) Then
				activeSignature = outputIndex
				bestScore = candidate.score
			End If
			outputIndex :+ 1
		Next
		If signatures.Size() = 0 Then Return JsonNull()
		Local activeCandidate:TCallSignatureCandidate = EffectiveCandidate(signatureSet, compatibleCount, activeSignature)
		Local parameterCount:Int
		If activeCandidate Then parameterCount = activeCandidate.parameterTypes.length
		Local result:TJSONObject = JsonObject()
		result.Set("signatures", signatures)
		result.Set("activeSignature", activeSignature)
		result.Set("activeParameter", ActiveParameter(call, context.offset, parameterCount, context.analysis.syntaxTree.source))
		Return result
	End Function

	Function EffectiveCandidate:TCallSignatureCandidate(signatureSet:TCallSignatureSet, compatibleCount:Int, selectedIndex:Int)
		Local outputIndex:Int
		For Local candidate:TCallSignatureCandidate = EachIn signatureSet.candidates
			If compatibleCount And Not candidate.compatible Then Continue
			If outputIndex = selectedIndex Then Return candidate
			outputIndex :+ 1
		Next
		Return Null
	End Function

	Function SignatureInformation:TJSONObject(candidate:TCallSignatureCandidate, context:TLspFeatureContext, workspace:TLspWorkspaceContext)
		Local signature:TJSONObject = JsonObject()
		Local documentation:TDocumentationComment
		Local resolved:TResolvedCall = CandidateResolvedCall(candidate)
		If candidate.routine Then
			signature.Set("label", TBlitzMaxLspHover.RoutineDisplay(candidate.routine, resolved))
			documentation = workspace.Documentation(candidate.routine)
			Local documentationMarkdown:String = TBlitzMaxLspDocumentation.Markdown(documentation, candidate.routine, context.analysis.model)
			If documentationMarkdown.length Then signature.Set("documentation", TBlitzMaxLspDocumentation.MarkupContent(documentationMarkdown))
		Else If candidate.closure Then
			signature.Set("label", candidate.closure.DisplayName())
		Else If candidate.callable Then
			signature.Set("label", candidate.callable.DisplayName())
		End If
		Local parameters:TJSONArray = JsonArray()
		For Local index:Int = 0 Until candidate.parameterTypes.length
			Local parameter:TJSONObject = JsonObject()
			If candidate.routine Then
				parameter.Set("label", ParameterLabel(candidate.routine, resolved, index))
				Local parameterMarkdown:String = TBlitzMaxLspDocumentation.ParameterMarkdown(documentation, index, candidate.routine, context.analysis.model)
				If parameterMarkdown.length Then parameter.Set("documentation", TBlitzMaxLspDocumentation.MarkupContent(parameterMarkdown))
			Else
				parameter.Set("label", StructuralParameterLabel(candidate.callable, candidate.closure, resolved, index))
			End If
			parameters.Append(parameter)
		Next
		signature.Set("parameters", parameters)
		Return signature
	End Function

	Function CandidateResolvedCall:TResolvedCall(candidate:TCallSignatureCandidate)
		Local resolved:TResolvedCall = New TResolvedCall
		resolved.routine = candidate.routine
		resolved.parameterTypes = candidate.parameterTypes
		resolved.returnType = candidate.returnType
		Return resolved
	End Function

	Function EnclosingCall:TCallExpressionSyntax(navigator:TSyntaxNavigator, offset:Int)
		If Not navigator Then Return Null
		Local best:TCallExpressionSyntax
		For Local node:TSyntaxNode = EachIn navigator.nodes
			Local call:TCallExpressionSyntax = TCallExpressionSyntax(node)
			If Not call Or Not call.openToken Then Continue
			If offset < call.openToken.span.EndOffset() Then Continue
			Local endOffset:Int = call.span.EndOffset()
			If call.closeToken Then endOffset = call.closeToken.span.EndOffset()
			If offset > endOffset Then Continue
			If Not best Or call.span.length < best.span.length Then best = call
		Next
		Return best
	End Function

	Function StructuralParameterLabel:String(callable:TCallableSemanticType, closure:TClosureSemanticType, resolved:TResolvedCall, index:Int)
		Local name:String = "arg" + index
		If closure And index < closure.parameterNames.length And closure.parameterNames[index].length Then name = closure.parameterNames[index]
		Local result:String = name + ":"
		If index < resolved.parameterTypes.length And resolved.parameterTypes[index] Then result :+ resolved.parameterTypes[index].DisplayName() Else result :+ "<unresolved>"
		If callable And index < callable.parameterModes.length And callable.parameterModes[index] = PARAMETER_PASS_VAR Then result :+ " Var"
		Return result
	End Function

	Function ActiveParameter:Int(call:TCallExpressionSyntax, offset:Int, parameterCount:Int, source:TSourceText)
		If parameterCount <= 0 Then Return 0
		If Not call Or call.arguments.length = 0 Then Return 0
		For Local index:Int = 0 Until call.arguments.length
			Local argument:TExpressionSyntax = call.arguments[index]
			If Not argument Then Continue
			If offset <= argument.span.EndOffset() Then Return Min(index, parameterCount - 1)
			If index + 1 < call.arguments.length And offset < call.arguments[index + 1].span.start Then Return Min(index + 1, parameterCount - 1)
		Next
		Local active:Int = call.arguments.length - 1
		Local last:TExpressionSyntax = call.arguments[call.arguments.length - 1]
		If last And offset > last.span.EndOffset() Then
			Local between:TSourceSpan = TSourceSpan.Create(last.span.EndOffset(), offset - last.span.EndOffset())
			If source.Slice(between).Contains(",") Then active :+ 1
		End If
		Return Min(active, parameterCount - 1)
	End Function

	Function ParameterLabel:String(routine:TSymbol, resolved:TResolvedCall, index:Int)
		Local name:String = "arg" + (index + 1)
		If index < routine.parameters.length And routine.parameters[index] And routine.parameters[index].symbol Then name = routine.parameters[index].symbol.name
		Local result:String = name + ":"
		If index < resolved.parameterTypes.length And resolved.parameterTypes[index] Then result :+ resolved.parameterTypes[index].DisplayName() Else result :+ "<unresolved>"
		If index < routine.parameters.length And routine.parameters[index] Then
			If routine.parameters[index].passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
			If routine.parameters[index].optional Then result :+ " = ..."
		End If
		Return result
	End Function

	Function ReferenceSpan:TSourceSpan(node:TSyntaxNode)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(node)
		If name And name.nameToken Then Return name.nameToken.span
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(node)
		If member And member.nameToken Then Return member.nameToken.span
		Local parameter:TParameterSyntax = TParameterSyntax(node)
		If parameter And parameter.nameToken Then Return parameter.nameToken.span
		Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(node)
		If declarator And declarator.nameToken Then Return declarator.nameToken.span
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine And routine.nameToken Then Return routine.nameToken.span
		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration And typeDeclaration.nameToken Then Return typeDeclaration.nameToken.span
		Local enumValue:TEnumValueSyntax = TEnumValueSyntax(node)
		If enumValue And enumValue.nameToken Then Return enumValue.nameToken.span
		Local typeReference:TTypeReferenceSyntax = TTypeReferenceSyntax(node)
		If typeReference And typeReference.nameTokens.length Then
			Local first:TSyntaxToken = typeReference.nameTokens[0]
			Local last:TSyntaxToken = typeReference.nameTokens[typeReference.nameTokens.length - 1]
			Return TSourceSpan.Create(first.span.start, last.span.EndOffset() - first.span.start)
		End If
		Return node.span
	End Function

	Function SymbolKind:Int(symbol:TSymbol)
		Select symbol.kind
			Case SYMBOL_TYPE Return 5
			Case SYMBOL_STRUCT Return 23
			Case SYMBOL_INTERFACE Return 11
			Case SYMBOL_ENUM Return 10
			Case SYMBOL_ENUM_MEMBER Return 22
			Case SYMBOL_FIELD Return 8
			Case SYMBOL_CONST Return 14
			Case SYMBOL_ROUTINE
				If symbol.containingScope And symbol.containingScope.owner Then Return 6
				Return 12
		End Select
		Return 13
	End Function

	Function SourceForPath:TSourceText(path:String, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		Local openDocument:TLspDocument
		If documents Then openDocument = documents.GetByPath(path)
		If openDocument Then Return TSourceText.Create(openDocument.text, openDocument.path)
		If analysis And analysis.syntaxTree And SnapshotPathKey(analysis.syntaxTree.source.path) = SnapshotPathKey(path) Then Return analysis.syntaxTree.source
		If analysis And analysis.snapshot Then
			For Local sourceDocument:TSourceDocumentModel = EachIn analysis.snapshot.documents
				If SnapshotPathKey(sourceDocument.path) = SnapshotPathKey(path) Then Return sourceDocument.tree.source
			Next
		End If
		If FileType(path) = FILETYPE_FILE Then Return TSourceText.Create(LoadText(path), path)
		Return Null
	End Function

	Function UriForPath:String(path:String, documents:TLspDocumentStore)
		If documents Then
			Local openDocument:TLspDocument = documents.GetByPath(path)
			If openDocument Then Return openDocument.uri
		End If
		Return FileUriForPath(path)
	End Function
End Type

Type TLspFeatureContext
	Field analysis:TLanguageAnalysis
	Field navigator:TSyntaxNavigator
	Field location:TSemanticLocation
	Field offset:Int

	Function Create:TLspFeatureContext(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int)
		If Not document Or Not workspace Then Return Null
		Local result:TLspFeatureContext = New TLspFeatureContext
		result.analysis = workspace.LatestAnalysis(document.uri)
		result.navigator = workspace.LatestNavigator(document.uri)
		If Not result.analysis Or Not result.analysis.model Or Not result.analysis.syntaxTree Or Not result.navigator Then Return Null
		result.offset = TLspPositions.Offset(result.analysis.syntaxTree.source, line, character)
		result.location = TSemanticLocation.Query(result.analysis.model, result.navigator, result.offset)
		Return result
	End Function
End Type
