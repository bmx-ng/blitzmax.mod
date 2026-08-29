' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import Text.Json
Import BlitzMax.Language
Import "documents.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

Type TBlitzMaxLspHover
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, line:Int, character:Int)
		If Not document Or Not workspace Then Return JsonNull()
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.model Or Not analysis.syntaxTree Then Return JsonNull()
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not navigator Then navigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		Local source:TSourceText = analysis.syntaxTree.source
		Local offset:Int = TLspPositions.Offset(source, line, character)
		Local location:TSemanticLocation = TSemanticLocation.Query(analysis.model, navigator, offset)
		If Not location Or Not location.syntax Or Not location.syntax.token Then Return JsonNull()
		Local display:String = HoverDisplay(location)
		If Not display.length Then Return JsonNull()

		Local contents:TJSONObject = JsonObject()
		contents.Set("kind", "markdown")
		Local markdown:String = "```blitzmax~n" + display + "~n```"
		Local declarationDisplay:String = GenericDeclarationDisplay(location)
		If declarationDisplay.length Then markdown :+ "~n~nDeclared as:~n~n```blitzmax~n" + declarationDisplay + "~n```"
		If location.symbol Then
			Local sourceSymbol:TSymbol = workspace.PreferredSourceSymbol(location.symbol)
			Local documentation:TDocumentationComment = workspace.Documentation(sourceSymbol)
			Local documentationMarkdown:String = TBlitzMaxLspDocumentation.Markdown(documentation, location.symbol, analysis.model)
			If documentationMarkdown.length Then markdown :+ "~n~n" + documentationMarkdown
			Local sourceLocation:String = TBlitzMaxLspDocumentation.SourceLocationMarkdown(sourceSymbol)
			If sourceLocation.length Then markdown :+ "~n~n" + sourceLocation
		End If
		contents.Set("value", markdown)
		Local result:TJSONObject = JsonObject()
		result.Set("contents", contents)
		result.Set("range", TLspPositions.Range(source, location.syntax.token.span))
		Return result
	End Function

	Function HoverDisplay:String(location:TSemanticLocation)
		If location.symbol Then Return SymbolDisplay(location.symbol, ResolvedCallForSymbol(location), location.constantValue, location.semanticType)
		If location.semanticType Then Return location.semanticType.DisplayName()
		Return ""
	End Function

	Function GenericDeclarationDisplay:String(location:TSemanticLocation)
		If Not location Or Not location.symbol Then Return ""
		If location.symbol.kind = SYMBOL_ROUTINE Then
			Local resolved:TResolvedCall = ResolvedCallForSymbol(location)
			If Not resolved Then Return ""
			Local resolvedDisplay:String = RoutineDisplay(location.symbol, resolved)
			Local declaredDisplay:String = RoutineDisplay(location.symbol, Null)
			If resolvedDisplay <> declaredDisplay Then Return declaredDisplay
			Return ""
		End If
		If Not location.semanticType Or Not location.symbol.declaredType Then Return ""
		If location.semanticType.DisplayName() = location.symbol.declaredType.DisplayName() Then Return ""
		Return SymbolDisplay(location.symbol, Null, location.constantValue)
	End Function

	Function ResolvedCallForSymbol:TResolvedCall(location:TSemanticLocation)
		If Not location Or Not location.symbol Or location.symbol.kind <> SYMBOL_ROUTINE Or Not location.resolvedCall Then Return Null
		If location.resolvedCall.routine = location.symbol Then Return location.resolvedCall
		Return Null
	End Function

	Function SymbolDisplay:String(symbol:TSymbol, resolved:TResolvedCall, constant:TConstantValue, useSiteType:TSemanticType = Null)
		If Not symbol Then Return ""
		Select symbol.kind
			Case SYMBOL_TYPE Return "Type " + symbol.QualifiedName()
			Case SYMBOL_STRUCT Return "Struct " + symbol.QualifiedName()
			Case SYMBOL_INTERFACE Return "Interface " + symbol.QualifiedName()
			Case SYMBOL_ENUM Return "Enum " + symbol.QualifiedName()
			Case SYMBOL_ROUTINE Return RoutineDisplay(symbol, resolved)
		End Select
		Local result:String = symbol.KindName() + " " + symbol.name
		Local displayType:TSemanticType = symbol.declaredType
		If useSiteType Then displayType = useSiteType
		If displayType Then result :+ ":" + displayType.DisplayName()
		If constant Then result :+ " = " + constant.DisplayValue()
		Return result
	End Function

	Function RoutineDisplay:String(symbol:TSymbol, resolved:TResolvedCall)
		Local keyword:String = "Function"
		If TMemberCompletion.IsInstanceRoutine(symbol) Then keyword = "Method"
		Local result:String = keyword + " " + symbol.name
		If symbol.genericArity > 0 Then
			result :+ "<"
			Local added:Int
			If symbol.memberScope Then
				For Local candidate:TSymbol = EachIn symbol.memberScope.declaredSymbols
					If candidate.kind <> SYMBOL_TYPE_PARAMETER Then Continue
					If added Then result :+ ", "
					result :+ candidate.name
					added :+ 1
				Next
			End If
			While added < symbol.genericArity
				If added Then result :+ ", "
				result :+ "T" + (added + 1)
				added :+ 1
			Wend
			result :+ ">"
		End If
		Local returnType:TSemanticType = symbol.declaredType
		If resolved And resolved.returnType Then returnType = resolved.returnType
		If returnType And returnType.DisplayName().ToLower() <> "void" Then result :+ ":" + returnType.DisplayName()
		result :+ "("
		Local parameterTypes:TSemanticType[] = symbol.parameterTypes
		If resolved And resolved.parameterTypes.length Then parameterTypes = resolved.parameterTypes
		For Local index:Int = 0 Until parameterTypes.length
			If index Then result :+ ", "
			Local name:String = "arg" + (index + 1)
			If index < symbol.parameters.length And symbol.parameters[index] And symbol.parameters[index].symbol Then name = symbol.parameters[index].symbol.name
			result :+ name + ":"
			If parameterTypes[index] Then result :+ parameterTypes[index].DisplayName() Else result :+ "<unresolved>"
			If index < symbol.parameters.length And symbol.parameters[index] Then
				If symbol.parameters[index].passingMode = PARAMETER_PASS_VAR Then result :+ " Var"
				If symbol.parameters[index].optional Then
					result :+ " = "
					If symbol.parameters[index].defaultValue Then result :+ symbol.parameters[index].defaultValue.DisplayValue() Else result :+ "..."
				End If
			End If
		Next
		Return result + ")"
	End Function

	Function Utf16PositionOffset:Int(source:TSourceText, line:Int, character:Int)
		Return TLspPositions.Offset(source, line, character)
	End Function

	Function Utf16Position:TJSONObject(source:TSourceText, offset:Int)
		Return TLspPositions.Position(source, offset)
	End Function

	Function TokenRange:TJSONObject(source:TSourceText, token:TSyntaxToken)
		Return TLspPositions.Range(source, token.span)
	End Function
End Type
