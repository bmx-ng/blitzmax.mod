' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "positions.bmx"
Import "protocol.bmx"
Import "workspaces.bmx"

Type TInlayHintEntry
	Field offset:Int
	Field hint:TJSONObject
End Type

Type TBlitzMaxLspInlayHints
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, range:TJSONObject)
		Local result:TJSONArray = JsonArray()
		If Not document Or Not workspace Then Return result
		Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(document.uri)
		If Not analysis Then analysis = workspace.Analyze(document)
		If Not analysis Or Not analysis.model Or Not analysis.syntaxTree Then Return result
		Local navigator:TSyntaxNavigator = workspace.LatestNavigator(document.uri)
		If Not navigator Then navigator = TSyntaxNavigator.Create(analysis.syntaxTree)
		If Not navigator Then Return result
		Local startOffset:Int
		Local endOffset:Int = analysis.syntaxTree.source.Length()
		If range Then
			Local startPosition:TJSONObject = TJSONObject(range.Get("start"))
			Local endPosition:TJSONObject = TJSONObject(range.Get("end"))
			If startPosition Then startOffset = TLspPositions.Offset(analysis.syntaxTree.source, Int(startPosition.GetInteger("line")), Int(startPosition.GetInteger("character")))
			If endPosition Then endOffset = TLspPositions.Offset(analysis.syntaxTree.source, Int(endPosition.GetInteger("line")), Int(endPosition.GetInteger("character")))
		End If

		Local entries:TInlayHintEntry[]
		Local seen:TMap = New TMap
		AppendTypeHints(entries, seen, analysis, navigator, startOffset, endOffset)
		AppendParameterHints(entries, seen, analysis, navigator, startOffset, endOffset)
		SortEntries(entries)
		For Local entry:TInlayHintEntry = EachIn entries
			result.Append(entry.hint)
		Next
		Return result
	End Function

	Function AppendTypeHints(entries:TInlayHintEntry[] Var, seen:TMap, analysis:TLanguageAnalysis, navigator:TSyntaxNavigator, startOffset:Int, endOffset:Int)
		For Local value:Object = EachIn analysis.model.declaredSymbolMap.Keys()
			Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(value)
			If Not declarator Or Not navigator.ContainsNode(declarator) Or Not declarator.nameToken Then Continue
			If declarator.declaredType Or declarator.callableType Or declarator.staticArrayBound Then Continue
			Local symbol:TSymbol = analysis.model.DeclaredSymbol(declarator)
			If Not symbol Or symbol.kind <> SYMBOL_LOCAL Then Continue
			If Not declarator.initializer And Not symbol.isTypeInferred Then Continue
			' Proper ':=' locals expose their ordinary fixed symbol type. Retain
			' the legacy editing aid for incomplete untyped '=' declarations.
			Local semanticType:TSemanticType
			If symbol.isTypeInferred Then semanticType = symbol.declaredType Else semanticType = analysis.model.ExpressionType(declarator.initializer)
			If Not semanticType Then
				Local bound:TBoundExpression = analysis.model.BoundExpression(declarator.initializer)
				If bound Then semanticType = bound.semanticType
			End If
			If Not semanticType Then Continue
			Local display:String = semanticType.DisplayName()
			If Not display.length Or display.StartsWith("<unresolved") Or display.ToLower() = "void" Then Continue
			Local offset:Int = declarator.nameToken.span.EndOffset()
			If offset < startOffset Or offset > endOffset Then Continue
			AppendHint(entries, seen, analysis.syntaxTree.source, offset, ": " + display, 1, False, False, "Inferred type: `" + display + "`")
		Next
	End Function

	Function AppendParameterHints(entries:TInlayHintEntry[] Var, seen:TMap, analysis:TLanguageAnalysis, navigator:TSyntaxNavigator, startOffset:Int, endOffset:Int)
		For Local value:Object = EachIn analysis.model.resolvedCallMap.Keys()
			Local syntax:TSyntaxNode = TSyntaxNode(value)
			If Not syntax Or Not navigator.ContainsNode(syntax) Then Continue
			Local resolved:TResolvedCall = analysis.model.ResolvedCall(syntax)
			If Not resolved Or Not resolved.routine Then Continue
			Local arguments:TExpressionSyntax[]
			Local call:TCallExpressionSyntax = TCallExpressionSyntax(syntax)
			If call Then arguments = call.arguments
			Local callStatement:TCallStatementSyntax = TCallStatementSyntax(syntax)
			If callStatement Then arguments = callStatement.argumentExpressions
			Local creation:TNewExpressionSyntax = TNewExpressionSyntax(syntax)
			If creation Then arguments = creation.arguments
			If Not arguments.length Then Continue
			For Local index:Int = 0 Until Min(arguments.length, resolved.routine.parameters.length)
				Local argument:TExpressionSyntax = arguments[index]
				Local parameter:TSemanticParameter = resolved.routine.parameters[index]
				If Not argument Or Not parameter Or Not parameter.symbol Or Not parameter.symbol.name.length Then Continue
				Local name:String = parameter.symbol.name
				If ArgumentAlreadyNamed(argument, name) Then Continue
				Local offset:Int = argument.span.start
				If offset < startOffset Or offset > endOffset Then Continue
				Local tooltip:String = ParameterTooltip(name, resolved, index)
				AppendHint(entries, seen, analysis.syntaxTree.source, offset, name + ":", 2, False, True, tooltip)
			Next
		Next
	End Function

	Function ParameterTooltip:String(name:String, resolved:TResolvedCall, index:Int)
		If Not resolved Or Not resolved.routine Then Return ""
		Local effective:TSemanticType
		If index < resolved.parameterTypes.length Then effective = resolved.parameterTypes[index]
		If Not effective And index < resolved.routine.parameterTypes.length Then effective = resolved.routine.parameterTypes[index]
		If Not effective Then Return ""
		Local effectiveDisplay:String = effective.DisplayName()
		If Not effectiveDisplay.length Or effectiveDisplay.StartsWith("<unresolved") Then Return ""
		Local result:String = "`" + name + ": " + effectiveDisplay + "`"
		If index < resolved.routine.parameterTypes.length And resolved.routine.parameterTypes[index] Then
			Local declaredDisplay:String = resolved.routine.parameterTypes[index].DisplayName()
			If declaredDisplay.length And declaredDisplay.ToLower() <> effectiveDisplay.ToLower() Then
				result :+ "~n~nDeclared as: `" + name + ": " + declaredDisplay + "`"
			End If
		End If
		Return result
	End Function

	Function ArgumentAlreadyNamed:Int(argument:TExpressionSyntax, parameterName:String)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(argument)
		If name And name.nameToken Then Return name.nameToken.text.ToLower() = parameterName.ToLower()
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(argument)
		If member And member.nameToken Then Return member.nameToken.text.ToLower() = parameterName.ToLower()
		Return False
	End Function

	Function AppendHint(entries:TInlayHintEntry[] Var, seen:TMap, source:TSourceText, offset:Int, label:String, kind:Int, paddingLeft:Int, paddingRight:Int, tooltip:String = "")
		Local key:String = offset + ":" + kind + ":" + label.ToLower()
		If seen.Contains(key) Then Return
		seen.Insert(key, key)
		Local hint:TJSONObject = JsonObject()
		hint.Set("position", TLspPositions.Position(source, offset))
		hint.Set("label", label)
		hint.Set("kind", kind)
		hint.Set("paddingLeft", New TJSONBool.Create(paddingLeft))
		hint.Set("paddingRight", New TJSONBool.Create(paddingRight))
		If tooltip.length Then
			Local content:TJSONObject = JsonObject()
			content.Set("kind", "markdown")
			content.Set("value", tooltip)
			hint.Set("tooltip", content)
		End If
		Local entry:TInlayHintEntry = New TInlayHintEntry
		entry.offset = offset
		entry.hint = hint
		entries :+ [entry]
	End Function

	Function SortEntries(entries:TInlayHintEntry[] Var)
		For Local index:Int = 1 Until entries.length
			Local value:TInlayHintEntry = entries[index]
			Local cursor:Int = index - 1
			While cursor >= 0 And entries[cursor].offset > value.offset
				entries[cursor + 1] = entries[cursor]
				cursor :- 1
			Wend
			entries[cursor + 1] = value
		Next
	End Function
End Type
