' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "semantic_model.bmx"

Type TLoopFlowContext
	Field parent:TLoopFlowContext
	Field label:String
	Field exitTarget:TControlFlowBlock
	Field continueTarget:TControlFlowBlock
	Field finallyContext:TFinallyFlowContext
End Type

Type TFinallyFlowContext
	Field parent:TFinallyFlowContext
	Field body:TBoundBlockStatement
	Field loopContext:TLoopFlowContext
	Field exceptionParent:TExceptionFlowContext
End Type

Type TExceptionFlowContext
	Field parent:TExceptionFlowContext
	Field finallyContext:TFinallyFlowContext
	Field catchTargets:TControlFlowBlock[] = New TControlFlowBlock[0]
End Type

' BlitzMax supplies an implicit zero/null return when a value-returning routine
' reaches its end. Consumers may still opt into a lint warning for this case.
Type TControlFlowAnalysisOptions
	Field reportImplicitDefaultReturns:Int
	Field implicitDefaultReturnSeverity:Int = DIAGNOSTIC_WARNING

	Function Create:TControlFlowAnalysisOptions()
		Return New TControlFlowAnalysisOptions
	End Function
End Type

Type TControlFlowAnalyzer
	Field model:TSemanticModel
	Field diagnostics:TList = New TList
	Field options:TControlFlowAnalysisOptions

	Function Analyze:TSemanticModel(model:TSemanticModel, options:TControlFlowAnalysisOptions = Null)
		Local analyzer:TControlFlowAnalyzer = New TControlFlowAnalyzer
		analyzer.model = model
		If options Then analyzer.options = options Else analyzer.options = TControlFlowAnalysisOptions.Create()
		If model.boundGlobalBody Then
			Local builder:TControlFlowBuilder = TControlFlowBuilder.Create(model, Null, analyzer.diagnostics)
			model.globalControlFlowGraph = builder.Build(model.boundGlobalBody)
		End If
		For Local routine:TSymbol = EachIn model.boundRoutineBodyMap.Keys()
			Local body:TBoundBlockStatement = model.BoundRoutineBody(routine)
			Local builder:TControlFlowBuilder = TControlFlowBuilder.Create(model, routine, analyzer.diagnostics)
			Local graph:TControlFlowGraph = builder.Build(body)
			model.controlFlowGraphMap.Insert(routine, graph)
			If analyzer.options.reportImplicitDefaultReturns And analyzer.RequiresReturn(routine) And graph.canFallThrough Then
				Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
				analyzer.AddDiagnostic("BMX3400", "Routine '" + routine.name + "' can reach its implicit default return.", declaration.span, analyzer.options.implicitDefaultReturnSeverity, routine.originPath)
			End If
		Next
		model.diagnostics = MergeControlFlowDiagnostics(model.diagnostics, ControlFlowDiagnosticsToArray(analyzer.diagnostics))
		Return model
	End Function

	Method RequiresReturn:Int(routine:TSymbol)
		If Not routine Or Not routine.declaredType Or routine.declaredType = model.BuiltinType("Void") Then Return False
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
		If Not declaration Or Not declaration.signature Then Return False
		If routine.containingScope And routine.containingScope.owner And routine.containingScope.owner.kind = SYMBOL_INTERFACE Then Return False
		For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
			Local text:String = token.text.ToLower()
			If text = "abstract" Or text.StartsWith("=") Then Return False
		Next
		Return True
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan, severity:Int, path:String = "")
		If Not path.length And model.syntaxTree Then path = model.syntaxTree.source.path
		diagnostics.AddLast(TDiagnostic.Create(code, message, severity, span, path))
	End Method
End Type

Type TControlFlowBuilder
	Field model:TSemanticModel
	Field routine:TSymbol
	Field diagnostics:TList
	Field graph:TControlFlowGraph
	Field blockList:TList = New TList
	Field edgeList:TList = New TList
	Field activeFinally:TFinallyFlowContext
	Field activeException:TExceptionFlowContext
	Field originPath:String

	Function Create:TControlFlowBuilder(model:TSemanticModel, routine:TSymbol, diagnostics:TList)
		Local builder:TControlFlowBuilder = New TControlFlowBuilder
		builder.model = model
		builder.routine = routine
		If routine Then builder.originPath = routine.originPath Else If model.syntaxTree Then builder.originPath = model.syntaxTree.source.path
		builder.diagnostics = diagnostics
		Return builder
	End Function

	Method Build:TControlFlowGraph(body:TBoundBlockStatement)
		graph = New TControlFlowGraph
		graph.routine = routine
		graph.entryBlock = NewBlock(Null)
		graph.entryBlock.isEntry = True
		graph.exitBlock = NewBlock(Null)
		graph.exitBlock.isExit = True
		Local outgoing:TControlFlowBlock[] = BuildSequence(body.statements, [graph.entryBlock], Null)
		ConnectAll(outgoing, graph.exitBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		graph.blocks = BlocksToArray(blockList)
		graph.edges = EdgesToArray(edgeList)
		MarkReachable()
		graph.canFallThrough = HasReachableIncoming(graph.exitBlock, CONTROL_FLOW_EDGE_FALLTHROUGH)
		graph.allPathsTerminate = Not graph.canFallThrough
		ReportUnreachable()
		Return graph
	End Method

	Method BuildSequence:TControlFlowBlock[](statements:TBoundStatement[], incoming:TControlFlowBlock[], loopContext:TLoopFlowContext)
		Local current:TControlFlowBlock[] = incoming
		For Local statement:TBoundStatement = EachIn statements
			current = BuildStatement(statement, current, loopContext)
		Next
		Return current
	End Method

	Method BuildStatement:TControlFlowBlock[](statement:TBoundStatement, incoming:TControlFlowBlock[], loopContext:TLoopFlowContext)
		If Not statement Then Return incoming
		Local nestedBlock:TBoundBlockStatement = TBoundBlockStatement(statement)
		If nestedBlock Then Return BuildSequence(nestedBlock.statements, incoming, loopContext)

		Local conditionalIf:TBoundIfStatement = TBoundIfStatement(statement)
		If conditionalIf Then Return BuildIf(conditionalIf, incoming, loopContext)
		Local whileStatement:TBoundWhileStatement = TBoundWhileStatement(statement)
		If whileStatement Then Return BuildWhile(whileStatement, incoming, loopContext)
		Local repeatStatement:TBoundRepeatStatement = TBoundRepeatStatement(statement)
		If repeatStatement Then Return BuildRepeat(repeatStatement, incoming, loopContext)
		Local forStatement:TBoundForStatement = TBoundForStatement(statement)
		If forStatement Then Return BuildFor(forStatement, incoming, loopContext)
		Local selectStatement:TBoundSelectStatement = TBoundSelectStatement(statement)
		If selectStatement Then Return BuildSelect(selectStatement, incoming, loopContext)
		Local tryStatement:TBoundTryStatement = TBoundTryStatement(statement)
		If tryStatement Then Return BuildTry(tryStatement, incoming, loopContext)
		Local usingStatement:TBoundUsingStatement = TBoundUsingStatement(statement)
		If usingStatement Then Return BuildUsing(usingStatement, incoming, loopContext)
		Local conditional:TBoundConditionalStatement = TBoundConditionalStatement(statement)
		If conditional Then Return BuildConditional(conditional, incoming, loopContext)

		Local block:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, block, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		If TBoundReturnStatement(statement) Then
			RouteCleanupUntil([block], activeFinally, Null, graph.exitBlock, CONTROL_FLOW_EDGE_RETURN)
			Return New TControlFlowBlock[0]
		End If
		If TBoundThrowStatement(statement) Then
			RouteException([block], activeException)
			Return New TControlFlowBlock[0]
		End If
		Local flow:TBoundFlowStatement = TBoundFlowStatement(statement)
		If flow Then Return BuildFlow(flow, block, loopContext)
		If TReadDataStatementSyntax(statement.syntax) Then RouteException([block], activeException, CONTROL_FLOW_EDGE_OUT_OF_DATA)
		Return [block]
	End Method

	Method BuildIf:TControlFlowBlock[](statement:TBoundIfStatement, incoming:TControlFlowBlock[], loopContext:TLoopFlowContext)
		Local conditionBlock:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, conditionBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local mergeBlock:TControlFlowBlock = NewBlock(Null)
		Local thenStart:TControlFlowBlock = BranchStart(conditionBlock, CONTROL_FLOW_EDGE_TRUE, statement.condition)
		ConnectAll(BuildSequence(statement.thenBody.statements, [thenStart], loopContext), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		For Local clause:TBoundConditionalClause = EachIn statement.elseIfClauses
			Local clauseStart:TControlFlowBlock = BranchStart(conditionBlock, CONTROL_FLOW_EDGE_TRUE, clause.condition)
			ConnectAll(BuildSequence(clause.body.statements, [clauseStart], loopContext), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Next
		If statement.elseBody Then
			Local elseStart:TControlFlowBlock = BranchStart(conditionBlock, CONTROL_FLOW_EDGE_FALSE, statement.condition)
			ConnectAll(BuildSequence(statement.elseBody.statements, [elseStart], loopContext), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Else
			Connect(conditionBlock, mergeBlock, CONTROL_FLOW_EDGE_FALSE, statement.condition)
		End If
		Return [mergeBlock]
	End Method

	Method BuildWhile:TControlFlowBlock[](statement:TBoundWhileStatement, incoming:TControlFlowBlock[], parent:TLoopFlowContext)
		Local header:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, header, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local afterLoop:TControlFlowBlock = NewBlock(Null)
		Local context:TLoopFlowContext = CreateLoopContext(parent, LoopLabel(statement.syntax), afterLoop, header)
		Local bodyStart:TControlFlowBlock = BranchStart(header, CONTROL_FLOW_EDGE_TRUE, statement.condition)
		ConnectAll(BuildSequence(statement.body.statements, [bodyStart], context), header, CONTROL_FLOW_EDGE_LOOP_BACK, statement.condition)
		Connect(header, afterLoop, CONTROL_FLOW_EDGE_FALSE, statement.condition)
		Return [afterLoop]
	End Method

	Method BuildRepeat:TControlFlowBlock[](statement:TBoundRepeatStatement, incoming:TControlFlowBlock[], parent:TLoopFlowContext)
		Local conditionBlock:TControlFlowBlock = NewBlock(statement)
		Local afterLoop:TControlFlowBlock = NewBlock(Null)
		Local bodyStart:TControlFlowBlock = NewBlock(Null)
		ConnectAll(incoming, bodyStart, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local context:TLoopFlowContext = CreateLoopContext(parent, LoopLabel(statement.syntax), afterLoop, conditionBlock)
		ConnectAll(BuildSequence(statement.body.statements, [bodyStart], context), conditionBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		If statement.isForever Then
			Connect(conditionBlock, bodyStart, CONTROL_FLOW_EDGE_LOOP_BACK, Null)
		Else
			Connect(conditionBlock, afterLoop, CONTROL_FLOW_EDGE_TRUE, statement.condition)
			Connect(conditionBlock, bodyStart, CONTROL_FLOW_EDGE_FALSE, statement.condition)
		End If
		Return [afterLoop]
	End Method

	Method BuildFor:TControlFlowBlock[](statement:TBoundForStatement, incoming:TControlFlowBlock[], parent:TLoopFlowContext)
		Local header:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, header, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local afterLoop:TControlFlowBlock = NewBlock(Null)
		Local context:TLoopFlowContext = CreateLoopContext(parent, LoopLabel(statement.syntax), afterLoop, header)
		Local bodyStart:TControlFlowBlock = BranchStart(header, CONTROL_FLOW_EDGE_TRUE, statement.collection)
		ConnectAll(BuildSequence(statement.body.statements, [bodyStart], context), header, CONTROL_FLOW_EDGE_LOOP_BACK, Null)
		Connect(header, afterLoop, CONTROL_FLOW_EDGE_FALSE, statement.collection)
		Return [afterLoop]
	End Method

	Method BuildSelect:TControlFlowBlock[](statement:TBoundSelectStatement, incoming:TControlFlowBlock[], loopContext:TLoopFlowContext)
		Local selectBlock:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, selectBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local mergeBlock:TControlFlowBlock = NewBlock(Null)
		For Local selectedCase:TBoundSelectCase = EachIn statement.cases
			Local condition:TBoundExpression
			If selectedCase.values.length Then condition = selectedCase.values[0]
			Local caseStart:TControlFlowBlock = BranchStart(selectBlock, CONTROL_FLOW_EDGE_CASE, condition)
			ConnectAll(BuildSequence(selectedCase.body.statements, [caseStart], loopContext), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Next
		If statement.defaultBody Then
			Local defaultStart:TControlFlowBlock = BranchStart(selectBlock, CONTROL_FLOW_EDGE_FALSE, statement.expression)
			ConnectAll(BuildSequence(statement.defaultBody.statements, [defaultStart], loopContext), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Else
			Connect(selectBlock, mergeBlock, CONTROL_FLOW_EDGE_FALSE, statement.expression)
		End If
		Return [mergeBlock]
	End Method

	Method BuildTry:TControlFlowBlock[](statement:TBoundTryStatement, incoming:TControlFlowBlock[], loopContext:TLoopFlowContext)
		Local tryBlock:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, tryBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local previousFinally:TFinallyFlowContext = activeFinally
		Local previousException:TExceptionFlowContext = activeException
		Local currentFinally:TFinallyFlowContext
		If statement.finallyBody Then
			currentFinally = New TFinallyFlowContext
			currentFinally.parent = previousFinally
			currentFinally.body = statement.finallyBody
			currentFinally.loopContext = loopContext
			currentFinally.exceptionParent = previousException
		End If
		Local catchStarts:TControlFlowBlock[] = New TControlFlowBlock[statement.catches.length]
		For Local index:Int = 0 Until statement.catches.length
			catchStarts[index] = NewBlock(Null)
		Next
		Local tryException:TExceptionFlowContext = New TExceptionFlowContext
		tryException.parent = previousException
		tryException.finallyContext = currentFinally
		tryException.catchTargets = catchStarts
		If currentFinally Then activeFinally = currentFinally Else activeFinally = previousFinally
		activeException = tryException
		Local endings:TList = New TList
		Local bodyStart:TControlFlowBlock = BranchStart(tryBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		AddBlocks(endings, BuildSequence(statement.body.statements, [bodyStart], loopContext))
		Local catchException:TExceptionFlowContext = New TExceptionFlowContext
		catchException.parent = previousException
		catchException.finallyContext = currentFinally
		For Local index:Int = 0 Until statement.catches.length
			activeException = catchException
			AddBlocks(endings, BuildSequence(statement.catches[index].body.statements, [catchStarts[index]], loopContext))
		Next
		activeFinally = previousFinally
		activeException = previousException
		Local mergeBlock:TControlFlowBlock = NewBlock(Null)
		If currentFinally Then
			ConnectAll(BuildCleanupOnce(BlocksToArray(endings), currentFinally), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Else
			ConnectAll(BlocksToArray(endings), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		End If
		RouteException([tryBlock], tryException)
		Return [mergeBlock]
	End Method

	Method BuildUsing:TControlFlowBlock[](statement:TBoundUsingStatement, incoming:TControlFlowBlock[], loopContext:TLoopFlowContext)
		Local usingBlock:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, usingBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local current:TControlFlowBlock[] = [usingBlock]
		For Local resource:TBoundVariableDeclarationStatement = EachIn statement.resources
			current = BuildStatement(resource, current, loopContext)
		Next
		Return BuildSequence(statement.body.statements, current, loopContext)
	End Method

	Method BuildConditional:TControlFlowBlock[](statement:TBoundConditionalStatement, incoming:TControlFlowBlock[], loopContext:TLoopFlowContext)
		Local hasStatements:Int
		For Local branch:TBoundConditionalBranch = EachIn statement.branches
			If branch.body And branch.body.statements.length Then
				hasStatements = True
				Exit
			End If
		Next
		If Not hasStatements Then Return incoming
		Local conditionalBlock:TControlFlowBlock = NewBlock(statement)
		ConnectAll(incoming, conditionalBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Local mergeBlock:TControlFlowBlock = NewBlock(Null)
		For Local branch:TBoundConditionalBranch = EachIn statement.branches
			Local branchStart:TControlFlowBlock = BranchStart(conditionalBlock, CONTROL_FLOW_EDGE_CASE, Null)
			ConnectAll(BuildSequence(branch.body.statements, [branchStart], loopContext), mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Next
		If statement.branches.length = 0 Then Connect(conditionalBlock, mergeBlock, CONTROL_FLOW_EDGE_FALLTHROUGH, Null)
		Return [mergeBlock]
	End Method

	Method BuildFlow:TControlFlowBlock[](statement:TBoundFlowStatement, block:TControlFlowBlock, loopContext:TLoopFlowContext)
		If TEndStatementSyntax(statement.syntax) Then
			Connect(block, graph.exitBlock, CONTROL_FLOW_EDGE_APPLICATION_END, Null)
			Return New TControlFlowBlock[0]
		End If
		Local exitStatement:TExitStatementSyntax = TExitStatementSyntax(statement.syntax)
		If exitStatement Then
			Local target:TLoopFlowContext = ResolveLoop(loopContext, exitStatement.label, "Exit", exitStatement.exitToken.span)
			If target Then RouteCleanupUntil([block], activeFinally, target.finallyContext, target.exitTarget, CONTROL_FLOW_EDGE_EXIT)
			Return New TControlFlowBlock[0]
		End If
		Local continueStatement:TContinueStatementSyntax = TContinueStatementSyntax(statement.syntax)
		If continueStatement Then
			Local target:TLoopFlowContext = ResolveLoop(loopContext, continueStatement.label, "Continue", continueStatement.continueToken.span)
			If target Then RouteCleanupUntil([block], activeFinally, target.finallyContext, target.continueTarget, CONTROL_FLOW_EDGE_CONTINUE)
			Return New TControlFlowBlock[0]
		End If
		Return [block]
	End Method

	Method ResolveLoop:TLoopFlowContext(context:TLoopFlowContext, labelExpression:TExpressionSyntax, operation:String, span:TSourceSpan)
		If Not labelExpression Then
			If Not context Then
				Local code:String = "BMX3403"
				If operation = "Exit" Then code = "BMX3402"
				AddDiagnostic(code, operation + " can be used only inside a loop.", span, DIAGNOSTIC_ERROR)
			End If
			Return context
		End If
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(labelExpression)
		If Not name Or Not name.nameToken Then
			AddDiagnostic("BMX3404", operation + " requires a loop-label name.", labelExpression.span, DIAGNOSTIC_ERROR)
			Return Null
		End If
		Local normalized:String = name.nameToken.text.ToLower()
		While context
			If context.label = normalized Then Return context
			context = context.parent
		Wend
		AddDiagnostic("BMX3404", "Loop label '" + name.nameToken.text + "' could not be found for " + operation + ".", name.nameToken.span, DIAGNOSTIC_ERROR)
		Return Null
	End Method

	Method CreateLoopContext:TLoopFlowContext(parent:TLoopFlowContext, label:String, exitTarget:TControlFlowBlock, continueTarget:TControlFlowBlock)
		Local context:TLoopFlowContext = New TLoopFlowContext
		context.parent = parent
		context.label = label
		context.exitTarget = exitTarget
		context.continueTarget = continueTarget
		context.finallyContext = activeFinally
		Return context
	End Method

	Method RouteCleanupUntil(sources:TControlFlowBlock[], context:TFinallyFlowContext, stopContext:TFinallyFlowContext, target:TControlFlowBlock, kind:Int)
		If context = stopContext Or Not context Then
			ConnectAll(sources, target, kind, Null)
			Return
		End If
		RouteCleanupUntil(BuildCleanupOnce(sources, context), context.parent, stopContext, target, kind)
	End Method

	Method BuildCleanupOnce:TControlFlowBlock[](sources:TControlFlowBlock[], context:TFinallyFlowContext)
		If Not context Or Not context.body Then Return sources
		Local previousFinally:TFinallyFlowContext = activeFinally
		Local previousException:TExceptionFlowContext = activeException
		activeFinally = context.parent
		activeException = context.exceptionParent
		Local result:TControlFlowBlock[] = BuildSequence(context.body.statements, sources, context.loopContext)
		activeFinally = previousFinally
		activeException = previousException
		Return result
	End Method

	Method RouteException(sources:TControlFlowBlock[], context:TExceptionFlowContext, terminalKind:Int = CONTROL_FLOW_EDGE_THROW)
		If Not context Then
			ConnectAll(sources, graph.exitBlock, terminalKind, Null)
			Return
		End If
		For Local catchTarget:TControlFlowBlock = EachIn context.catchTargets
			ConnectAll(sources, catchTarget, CONTROL_FLOW_EDGE_EXCEPTION, Null)
		Next
		Local unhandled:TControlFlowBlock[] = sources
		If context.finallyContext Then unhandled = BuildCleanupOnce(unhandled, context.finallyContext)
		RouteException(unhandled, context.parent, terminalKind)
	End Method

	Function LoopLabel:String(syntax:TSyntaxNode)
		Local label:TLabelSyntax
		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(syntax)
		If whileStatement Then label = whileStatement.label
		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(syntax)
		If repeatStatement Then label = repeatStatement.label
		Local forStatement:TForStatementSyntax = TForStatementSyntax(syntax)
		If forStatement Then label = forStatement.label
		If label And label.nameToken Then Return label.nameToken.text.ToLower()
		Return ""
	End Function

	Method NewBlock:TControlFlowBlock(statement:TBoundStatement)
		Local block:TControlFlowBlock = New TControlFlowBlock
		block.id = blockList.Count()
		block.statement = statement
		blockList.AddLast(block)
		Return block
	End Method

	Method BranchStart:TControlFlowBlock(source:TControlFlowBlock, kind:Int, condition:TBoundExpression)
		Local result:TControlFlowBlock = NewBlock(Null)
		Connect(source, result, kind, condition)
		Return result
	End Method

	Method ConnectAll(sources:TControlFlowBlock[], target:TControlFlowBlock, kind:Int, condition:TBoundExpression)
		For Local source:TControlFlowBlock = EachIn sources
			Connect(source, target, kind, condition)
		Next
	End Method

	Method Connect(source:TControlFlowBlock, target:TControlFlowBlock, kind:Int, condition:TBoundExpression)
		If Not source Or Not target Then Return
		Local edge:TControlFlowEdge = New TControlFlowEdge
		edge.source = source
		edge.target = target
		edge.kind = kind
		edge.condition = condition
		edgeList.AddLast(edge)
		source.outgoing = AppendEdge(source.outgoing, edge)
		target.incoming = AppendEdge(target.incoming, edge)
	End Method

	Method MarkReachable()
		graph.entryBlock.isReachable = True
		Local changed:Int = True
		While changed
			changed = False
			For Local edge:TControlFlowEdge = EachIn graph.edges
				If edge.source.isReachable And Not edge.target.isReachable Then
					edge.target.isReachable = True
					changed = True
				End If
			Next
		Wend
	End Method

	Method HasReachableIncoming:Int(block:TControlFlowBlock, kind:Int)
		For Local edge:TControlFlowEdge = EachIn block.incoming
			If edge.kind = kind And edge.source.isReachable Then Return True
		Next
		Return False
	End Method

	Method ReportUnreachable()
		For Local block:TControlFlowBlock = EachIn graph.blocks
			If block.statement And Not block.isReachable And Not HasReachableCopy(block.statement) And StartsUnreachableRegion(block, 0) Then
				AddDiagnostic("BMX3401", "Unreachable statement.", block.statement.syntax.span, DIAGNOSTIC_WARNING)
			End If
		Next
	End Method

	Method HasReachableCopy:Int(statement:TBoundStatement)
		For Local block:TControlFlowBlock = EachIn graph.blocks
			If block.statement = statement And block.isReachable Then Return True
		Next
		Return False
	End Method

	Method StartsUnreachableRegion:Int(block:TControlFlowBlock, depth:Int)
		If depth > 64 Then Return False
		If block.incoming.length = 0 Then Return True
		For Local edge:TControlFlowEdge = EachIn block.incoming
			If edge.source.statement Then Return False
			If Not StartsUnreachableRegion(edge.source, depth + 1) Then Return False
		Next
		Return True
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan, severity:Int)
		diagnostics.AddLast(TDiagnostic.Create(code, message, severity, span, originPath))
	End Method

	Function AddBlocks(list:TList, blocks:TControlFlowBlock[])
		For Local block:TControlFlowBlock = EachIn blocks
			list.AddLast(block)
		Next
	End Function

	Function AppendEdge:TControlFlowEdge[](values:TControlFlowEdge[], edge:TControlFlowEdge)
		Local result:TControlFlowEdge[] = New TControlFlowEdge[values.length + 1]
		For Local index:Int = 0 Until values.length
			result[index] = values[index]
		Next
		result[values.length] = edge
		Return result
	End Function

	Function BlocksToArray:TControlFlowBlock[](list:TList)
		Local result:TControlFlowBlock[] = New TControlFlowBlock[list.Count()]
		Local index:Int
		For Local block:TControlFlowBlock = EachIn list
			result[index] = block
			index :+ 1
		Next
		Return result
	End Function

	Function EdgesToArray:TControlFlowEdge[](list:TList)
		Local result:TControlFlowEdge[] = New TControlFlowEdge[list.Count()]
		Local index:Int
		For Local edge:TControlFlowEdge = EachIn list
			result[index] = edge
			index :+ 1
		Next
		Return result
	End Function
End Type

Type TControlFlowDumper
	Function Dump:String(graph:TControlFlowGraph)
		If Not graph Then Return "<missing control-flow graph>~n"
		Local result:String
		For Local block:TControlFlowBlock = EachIn graph.blocks
			result :+ "Block " + block.id
			If block.isEntry Then result :+ " [entry]"
			If block.isExit Then result :+ " [exit]"
			If Not block.isReachable Then result :+ " [unreachable]"
			If block.statement And block.statement.syntax Then result :+ " " + block.statement.syntax.KindName()
			result :+ "~n"
			For Local edge:TControlFlowEdge = EachIn block.outgoing
				result :+ "  -> " + edge.target.id + " " + EdgeKindName(edge.kind) + "~n"
			Next
		Next
		Return result
	End Function

	Function EdgeKindName:String(kind:Int)
		Select kind
			Case CONTROL_FLOW_EDGE_FALLTHROUGH Return "fallthrough"
			Case CONTROL_FLOW_EDGE_TRUE Return "true"
			Case CONTROL_FLOW_EDGE_FALSE Return "false"
			Case CONTROL_FLOW_EDGE_CASE Return "case"
			Case CONTROL_FLOW_EDGE_LOOP_BACK Return "loop-back"
			Case CONTROL_FLOW_EDGE_EXIT Return "exit-loop"
			Case CONTROL_FLOW_EDGE_CONTINUE Return "continue-loop"
			Case CONTROL_FLOW_EDGE_RETURN Return "return"
			Case CONTROL_FLOW_EDGE_THROW Return "throw"
			Case CONTROL_FLOW_EDGE_APPLICATION_END Return "end-application"
			Case CONTROL_FLOW_EDGE_EXCEPTION Return "exception"
			Case CONTROL_FLOW_EDGE_OUT_OF_DATA Return "out-of-data"
		End Select
		Return "edge"
	End Function
End Type

Function ControlFlowDiagnosticsToArray:TDiagnostic[](list:TList)
	Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
	Local index:Int
	For Local diagnostic:TDiagnostic = EachIn list
		result[index] = diagnostic
		index :+ 1
	Next
	Return result
End Function

Function MergeControlFlowDiagnostics:TDiagnostic[](first:TDiagnostic[], second:TDiagnostic[])
	Local result:TDiagnostic[] = New TDiagnostic[first.length + second.length]
	For Local index:Int = 0 Until first.length
		result[index] = first[index]
	Next
	For Local index:Int = 0 Until second.length
		result[first.length + index] = second[index]
	Next
	Return result
End Function
