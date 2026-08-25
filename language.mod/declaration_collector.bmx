' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList

Import "conditional_evaluator.bmx"
Import "semantic_model.bmx"
Import "snapshot_model.bmx"
Import "symbol_accessibility.bmx"

Type TDeclarationCollector
	Field model:TSemanticModel
	Field diagnostics:TList = New TList
	Field snapshot:TCompilationSnapshot
	Field currentDocument:TSourceDocumentModel
	Field currentPath:String
	Field externDepth:Int
	Field externCallingConvention:String = CALLING_CONVENTION_C
	Field documentationIndexes:TMap = New TMap

	Function Collect:TSemanticModel(tree:TSyntaxTree)
		Local collector:TDeclarationCollector = New TDeclarationCollector
		collector.model = New TSemanticModel
		collector.model.syntaxTree = tree
		collector.model.moduleName = TSymbolAccessibility.ModuleNameForPath(tree.source.path)
		collector.currentPath = tree.source.path
		collector.model.globalScope = collector.CreateScope(SCOPE_COMPILATION_UNIT, Null, Null, tree.root)
		collector.CollectSequence(tree.root.members, collector.model.globalScope, VISIBILITY_PUBLIC)
		collector.model.diagnostics = DiagnosticsToArray(collector.diagnostics)
		Return collector.model
	End Function

	Function CollectSnapshot:TSemanticModel(snapshot:TCompilationSnapshot)
		Local collector:TDeclarationCollector = New TDeclarationCollector
		collector.snapshot = snapshot
		collector.currentDocument = snapshot.rootDocument
		collector.model = New TSemanticModel
		collector.model.snapshot = snapshot
		collector.model.syntaxTree = snapshot.rootDocument.tree
		collector.model.moduleName = TSymbolAccessibility.ModuleNameForPath(snapshot.rootDocument.path)
		If snapshot.options And snapshot.options.sourceModuleName.length Then
			collector.model.moduleName = snapshot.options.sourceModuleName.ToLower()
		End If
		collector.model.globalScope = collector.CreateScope(SCOPE_COMPILATION_UNIT, Null, Null, snapshot.rootDocument.tree.root)
		collector.CollectSequence(snapshot.rootDocument.tree.root.members, collector.model.globalScope, VISIBILITY_PUBLIC)
		collector.model.diagnostics = DiagnosticsToArray(collector.diagnostics)
		Return collector.model
	End Function

	Method CreateScope:TScope(kind:Int, parent:TScope, owner:TSymbol, syntax:TSyntaxNode)
		Local scope:TScope = New TScope
		scope.kind = kind
		scope.parent = parent
		scope.owner = owner
		scope.syntax = syntax
		If parent Then parent.AddChild(scope)
		If syntax Then model.syntaxScopeMap.Insert(syntax, scope)
		Return scope
	End Method

	Method Declare:TSymbol(kind:Int, token:TSyntaxToken, declaration:TSyntaxNode, scope:TScope, visibility:Int, nameOverride:String = "")
		If Not token Then Return Null
		Local symbol:TSymbol = New TSymbol
		symbol.kind = kind
		symbol.name = token.text
		If nameOverride.length Then symbol.name = nameOverride
		symbol.normalizedName = token.text.ToLower()
		If nameOverride.length Then symbol.normalizedName = nameOverride.ToLower()
		symbol.nameToken = token
		symbol.declaration = declaration
		symbol.containingScope = scope
		symbol.visibility = visibility
		symbol.originPath = CurrentSourcePath()
		symbol.originModule = model.moduleName
		Local tree:TSyntaxTree = model.syntaxTree
		If currentDocument Then tree = currentDocument.tree
		If tree And token.span Then
			Local position:TSourcePosition = tree.source.Position(token.span.start)
			symbol.originLine = position.line + 1
			symbol.originColumn = position.column
			symbol.documentation = DocumentationFor(tree, declaration)
		End If
		Local existing:TSymbol[] = scope.LookupLocal(symbol.name)
		For Local candidate:TSymbol = EachIn existing
			If candidate.NamespaceKind() = symbol.NamespaceKind() And symbol.NamespaceKind() <> SYMBOL_NAMESPACE_ROUTINE Then
				diagnostics.AddLast(TDiagnostic.Create("BMX3000", "Duplicate " + symbol.KindName().ToLower() + " declaration '" + symbol.name + "'.", DIAGNOSTIC_ERROR, token.span, CurrentSourcePath()))
				Exit
			End If
		Next
		scope.AddSymbol(symbol)
		model.declaredSymbolMap.Insert(declaration, symbol)
		Return symbol
	End Method

	Method DocumentationFor:TDocumentationComment(tree:TSyntaxTree, declaration:TSyntaxNode)
		If Not tree Or Not declaration Then Return Null
		Local index:TDocumentationIndex = TDocumentationIndex(documentationIndexes.ValueForKey(tree))
		If Not index Then
			index = TDocumentationIndex.Build(tree)
			documentationIndexes.Insert(tree, index)
		End If
		Return index.FindDeclaration(declaration)
	End Method

	Method CurrentSourcePath:String()
		If currentDocument Then Return currentDocument.path
		Return currentPath
	End Method

	Method CollectSequence(nodes:TSyntaxNode[], scope:TScope, initialVisibility:Int)
		Local visibility:Int = initialVisibility
		For Local node:TSyntaxNode = EachIn nodes
			Local section:TVisibilitySectionSyntax = TVisibilitySectionSyntax(node)
			If section Then
				visibility = section.visibility
				Continue
			End If
			CollectNode(node, scope, visibility)
		Next
	End Method

	Method CollectNode(node:TSyntaxNode, scope:TScope, visibility:Int)
		If Not node Then Return
		Local includeSyntax:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
		If includeSyntax And snapshot Then
			For Local edge:TIncludeEdge = EachIn currentDocument.includes
				If edge.syntax = includeSyntax And edge.target Then
					Local previous:TSourceDocumentModel = currentDocument
					currentDocument = edge.target
					CollectSequence(edge.target.tree.root.members, scope, visibility)
					currentDocument = previous
					Exit
				End If
			Next
			Return
		End If
		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration Then
			CollectType(typeDeclaration, scope, visibility)
			Return
		End If
		Local externBlock:TExternBlockSyntax = TExternBlockSyntax(node)
		If externBlock Then
			Local previousConvention:String = externCallingConvention
			If Not TCallingConventionResolver.IsRecognized(externBlock.callingConventionToken) Then
				diagnostics.AddLast(TDiagnostic.Create("BMX3016", "Unrecognized calling convention '" + TCallingConventionResolver.WrittenName(externBlock.callingConventionToken) + "'.", DIAGNOSTIC_ERROR, externBlock.callingConventionToken.span, CurrentSourcePath()))
			End If
			externCallingConvention = TCallingConventionResolver.Resolve(externBlock.callingConventionToken, TargetPlatform())
			externDepth :+ 1
			CollectSequence(externBlock.body.statements, scope, visibility)
			externDepth :- 1
			externCallingConvention = previousConvention
			Return
		End If
		Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(node)
		If enumDeclaration Then
			CollectEnum(enumDeclaration, scope, visibility)
			Return
		End If
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine Then
			CollectRoutine(routine, scope, visibility)
			Return
		End If
		Local variables:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
		If variables Then
			CollectVariables(variables, scope, visibility)
			For Local declarator:TVariableDeclaratorSyntax = EachIn variables.declarators
				CollectExpression(declarator.initializer, scope)
			Next
			Return
		End If
		Local assignment:TAssignmentStatementSyntax = TAssignmentStatementSyntax(node)
		If assignment Then CollectExpression(assignment.left, scope); CollectExpression(assignment.right, scope); Return
		Local callStatement:TCallStatementSyntax = TCallStatementSyntax(node)
		If callStatement Then
			CollectExpression(callStatement.expression, scope)
			For Local argument:TExpressionSyntax = EachIn callStatement.argumentExpressions; CollectExpression(argument, scope); Next
			Return
		End If
		Local returned:TReturnStatementSyntax = TReturnStatementSyntax(node)
		If returned Then CollectExpression(returned.expression, scope); Return
		Local yielded:TYieldStatementSyntax = TYieldStatementSyntax(node)
		If yielded Then
			Local owner:TSymbol = EnclosingRoutine(scope)
			If owner Then owner.isIteratorRoutine = True
			CollectExpression(yielded.expression, scope)
			Return
		End If
		Local thrown:TThrowStatementSyntax = TThrowStatementSyntax(node)
		If thrown Then CollectExpression(thrown.expression, scope); Return
		Local asserted:TAssertStatementSyntax = TAssertStatementSyntax(node)
		If asserted Then CollectExpression(asserted.condition, scope); CollectExpression(asserted.message, scope); Return
		Local released:TReleaseStatementSyntax = TReleaseStatementSyntax(node)
		If released Then CollectExpression(released.expression, scope); Return
		Local conditional:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
		If conditional Then
			If snapshot Then
				Local indexes:Int[] = TConditionalEvaluator.ActiveBranchIndexes(conditional, snapshot.options.conditionalSymbols)
				For Local index:Int = EachIn indexes
					Local activeBranch:TConditionalBranchSyntax = conditional.branches[index]
					model.syntaxScopeMap.Insert(activeBranch, scope)
					model.syntaxScopeMap.Insert(activeBranch.body, scope)
					CollectSequence(activeBranch.body.statements, scope, visibility)
				Next
				Return
			End If
			For Local branch:TConditionalBranchSyntax = EachIn conditional.branches
				Local branchScope:TScope = CreateScope(SCOPE_CONDITIONAL_BRANCH, scope, Null, branch)
				model.syntaxScopeMap.Insert(branch.body, branchScope)
				CollectSequence(branch.body.statements, branchScope, visibility)
			Next
			Return
		End If
		Local ifStatement:TIfStatementSyntax = TIfStatementSyntax(node)
		If ifStatement Then
			CollectExpression(ifStatement.condition, scope)
			CollectChildBlock(ifStatement.thenBlock, scope)
			For Local clause:TElseIfClauseSyntax = EachIn ifStatement.elseIfClauses
				CollectExpression(clause.condition, scope)
				CollectChildBlock(clause.block, scope)
			Next
			If ifStatement.elseClause Then CollectChildBlock(ifStatement.elseClause.block, scope)
			Return
		End If
		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(node)
		If whileStatement Then
			CollectExpression(whileStatement.condition, scope)
			CollectScopedBlock(whileStatement.body, scope, SCOPE_LOOP, whileStatement)
			Return
		End If
		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(node)
		If repeatStatement Then
			CollectScopedBlock(repeatStatement.body, scope, SCOPE_LOOP, repeatStatement)
			CollectExpression(repeatStatement.condition, scope)
			Return
		End If
		Local forStatement:TForStatementSyntax = TForStatementSyntax(node)
		If forStatement Then
			Local loopScope:TScope = CreateScope(SCOPE_LOOP, scope, Null, forStatement)
			model.syntaxScopeMap.Insert(forStatement.body, loopScope)
			If forStatement.header Then
				For Local declarator:TVariableDeclaratorSyntax = EachIn forStatement.header.declarations
					Local symbol:TSymbol = Declare(SYMBOL_LOCAL, declarator.nameToken, declarator, loopScope, VISIBILITY_PUBLIC)
					' A multi-binding EachIn header infers omitted component types from
					' IDeconstruct2 rather than applying the ordinary implicit Int type.
					If symbol And forStatement.header.eachInToken And forStatement.header.declarations.length > 1 And Not declarator.declaredType And Not declarator.callableType Then symbol.isTypeInferred = True
				Next
			End If
			CollectSequence(forStatement.body.statements, loopScope, VISIBILITY_PUBLIC)
			Return
		End If
		Local selectStatement:TSelectStatementSyntax = TSelectStatementSyntax(node)
		If selectStatement Then
			CollectExpression(selectStatement.expression, scope)
			For Local caseClause:TCaseClauseSyntax = EachIn selectStatement.cases
				If Not model.snapshot Or TConditionalEvaluator.IsActive(caseClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then CollectChildBlock(caseClause.body, scope)
			Next
			For Local defaultClause:TDefaultClauseSyntax = EachIn selectStatement.defaultClauses
				If Not model.snapshot Or TConditionalEvaluator.IsActive(defaultClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then CollectChildBlock(defaultClause.body, scope)
			Next
			Return
		End If
		Local tryStatement:TTryStatementSyntax = TTryStatementSyntax(node)
		If tryStatement Then
			CollectChildBlock(tryStatement.body, scope)
			For Local catchClause:TCatchClauseSyntax = EachIn tryStatement.catches
				Local catchScope:TScope = CreateScope(SCOPE_CATCH, scope, Null, catchClause)
				model.syntaxScopeMap.Insert(catchClause.body, catchScope)
				If catchClause.nameToken Then Declare(SYMBOL_CATCH_PARAMETER, catchClause.nameToken, catchClause, catchScope, VISIBILITY_PUBLIC)
				CollectSequence(catchClause.body.statements, catchScope, VISIBILITY_PUBLIC)
			Next
			If tryStatement.finallyClause Then CollectChildBlock(tryStatement.finallyClause.body, scope)
			Return
		End If
		Local usingStatement:TUsingStatementSyntax = TUsingStatementSyntax(node)
		If usingStatement Then
			Local usingScope:TScope = CreateScope(SCOPE_USING, scope, Null, usingStatement)
			model.syntaxScopeMap.Insert(usingStatement.body, usingScope)
			For Local resource:TVariableDeclarationStatementSyntax = EachIn usingStatement.resources
				CollectVariables(resource, usingScope, VISIBILITY_PUBLIC)
			Next
			CollectSequence(usingStatement.body.statements, usingScope, VISIBILITY_PUBLIC)
		End If
	End Method

	Method CollectExpression(expression:TExpressionSyntax, scope:TScope)
		If Not expression Then Return
		Local functionLiteral:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(expression)
		If functionLiteral Then
			CollectFunctionLiteral(functionLiteral, scope)
			Return
		End If
		Local parentheses:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parentheses Then CollectExpression(parentheses.expression, scope); Return
		Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(expression)
		If unary Then CollectExpression(unary.operand, scope); Return
		Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
		If binary Then CollectExpression(binary.left, scope); CollectExpression(binary.right, scope); Return
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then CollectExpression(member.expression, scope); Return
		Local call:TCallExpressionSyntax = TCallExpressionSyntax(expression)
		If call Then
			CollectExpression(call.callee, scope)
			For Local argument:TExpressionSyntax = EachIn call.arguments; CollectExpression(argument, scope); Next
			Return
		End If
		Local indexed:TIndexExpressionSyntax = TIndexExpressionSyntax(expression)
		If indexed Then
			CollectExpression(indexed.expression, scope)
			For Local index:TExpressionSyntax = EachIn indexed.indexes; CollectExpression(index, scope); Next
			Return
		End If
		Local slice:TSliceExpressionSyntax = TSliceExpressionSyntax(expression)
		If slice Then CollectExpression(slice.expression, scope); CollectExpression(slice.lowerBound, scope); CollectExpression(slice.upperBound, scope); Return
		Local ascription:TTypeAscriptionExpressionSyntax = TTypeAscriptionExpressionSyntax(expression)
		If ascription Then CollectExpression(ascription.expression, scope); Return
		Local creation:TNewExpressionSyntax = TNewExpressionSyntax(expression)
		If creation Then
			For Local argument:TExpressionSyntax = EachIn creation.arguments; CollectExpression(argument, scope); Next
			For Local dimension:TExpressionSyntax = EachIn creation.dimensions; CollectExpression(dimension, scope); Next
			Return
		End If
		Local arrayLiteral:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(expression)
		If arrayLiteral Then For Local element:TExpressionSyntax = EachIn arrayLiteral.elements; CollectExpression(element, scope); Next; Return
		Local cast:TCastExpressionSyntax = TCastExpressionSyntax(expression)
		If cast Then CollectExpression(cast.expression, scope)
	End Method

	Method CollectFunctionLiteral(literal:TFunctionLiteralExpressionSyntax, parent:TScope)
		Local symbol:TSymbol = New TSymbol
		symbol.kind = SYMBOL_ROUTINE
		symbol.name = "<Function>"
		symbol.normalizedName = "<function>"
		symbol.nameToken = literal.functionToken
		symbol.declaration = literal
		symbol.containingScope = parent
		symbol.visibility = VISIBILITY_PRIVATE
		symbol.originPath = CurrentSourcePath()
		symbol.originModule = model.moduleName
		model.declaredSymbolMap.Insert(literal, symbol)

		Local literalScope:TScope = CreateScope(SCOPE_ROUTINE, parent, symbol, literal)
		symbol.memberScope = literalScope
		model.syntaxScopeMap.Insert(literal.body, literalScope)
		For Local parameter:TParameterSyntax = EachIn literal.parameters
			Declare(SYMBOL_PARAMETER, parameter.nameToken, parameter, literalScope, VISIBILITY_PRIVATE)
		Next
		CollectSequence(literal.body.statements, literalScope, VISIBILITY_PUBLIC)
	End Method

	Method CollectType(declaration:TTypeDeclarationSyntax, parent:TScope, visibility:Int)
		Local kind:Int = SYMBOL_TYPE
		Select declaration.declarationToken.text.ToLower()
			Case "struct" kind = SYMBOL_STRUCT
			Case "interface" kind = SYMBOL_INTERFACE
		End Select
		Local symbol:TSymbol = Declare(kind, declaration.nameToken, declaration, parent, visibility)
		If symbol And externDepth > 0 Then
			symbol.isExternal = True
			' Extern type names are native C ABI identities.  Unlike routine and
			' Global bindings they have no independent linkage assignment.
			symbol.externalName = symbol.name
		End If
		If symbol And declaration.header Then symbol.metadata = TDeclarationMetadata.Parse(declaration.header.metadataTokens, diagnostics, CurrentSourcePath())
		If symbol And kind = SYMBOL_INTERFACE Then symbol.isAbstract = True
		If symbol And declaration.header Then
			For Local modifier:TSyntaxToken = EachIn declaration.header.modifierTokens
				If modifier.text.ToLower() = "abstract" Then symbol.isAbstract = True
			Next
		End If
		Local scope:TScope = CreateScope(SCOPE_TYPE, parent, symbol, declaration)
		symbol.memberScope = scope
		model.syntaxScopeMap.Insert(declaration.body, scope)
		If declaration.header Then
			For Local parameter:TGenericParameterSyntax = EachIn declaration.header.genericParameters
				Declare(SYMBOL_TYPE_PARAMETER, parameter.nameToken, parameter, scope, VISIBILITY_PRIVATE)
			Next
		End If
		CollectSequence(declaration.body.statements, scope, VISIBILITY_PUBLIC)
	End Method

	Method CollectEnum(declaration:TEnumDeclarationSyntax, parent:TScope, visibility:Int)
		Local symbol:TSymbol = Declare(SYMBOL_ENUM, declaration.nameToken, declaration, parent, visibility)
		Local scope:TScope = CreateScope(SCOPE_ENUM, parent, symbol, declaration)
		symbol.memberScope = scope
		For Local value:TEnumValueSyntax = EachIn declaration.values
			Declare(SYMBOL_ENUM_MEMBER, value.nameToken, value, scope, VISIBILITY_PUBLIC)
		Next
	End Method

	Method CollectRoutine(declaration:TRoutineDeclarationSyntax, parent:TScope, visibility:Int)
		Local operatorName:String
		If declaration.signature Then operatorName = declaration.signature.operatorName
		Local symbol:TSymbol = Declare(SYMBOL_ROUTINE, declaration.nameToken, declaration, parent, visibility, operatorName)
		If declaration.signature Then
			Local afterAssignment:Int
			For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
				If token.text = "=" Then afterAssignment = True; Continue
				If afterAssignment Then Continue
				If token.kind = TOKEN_STRING_LITERAL And Not TCallingConventionResolver.IsRecognized(token) Then
					diagnostics.AddLast(TDiagnostic.Create("BMX3016", "Unrecognized calling convention '" + TCallingConventionResolver.WrittenName(token) + "'.", DIAGNOSTIC_ERROR, token.span, CurrentSourcePath()))
				End If
			Next
		End If
		If symbol Then symbol.callingConvention = TCallingConventionResolver.RoutineConvention(declaration, externCallingConvention, TargetPlatform())
		If symbol And declaration.signature Then symbol.metadata = TDeclarationMetadata.Parse(declaration.signature.modifierTokens, diagnostics, CurrentSourcePath())
		If symbol And symbol.metadata And symbol.metadata.Has("nomangle") And declaration.isMethod Then
			diagnostics.AddLast(TDiagnostic.Create("BMX3014", "Only functions can specify NoMangle.", DIAGNOSTIC_ERROR, declaration.span, CurrentSourcePath()))
		End If
		If symbol Then ValidateNoMangleOverload(symbol, parent, declaration)
		Local interfaceOwner:Int = symbol And parent And parent.owner And parent.owner.kind = SYMBOL_INTERFACE
		If interfaceOwner Then
			symbol.isAbstract = True
			symbol.interfaceMethodKind = INTERFACE_METHOD_ABSTRACT
		End If
		If symbol And declaration.signature Then
			For Local modifier:TSyntaxToken = EachIn declaration.signature.modifierTokens
				Local modifierText:String = modifier.text.ToLower()
				If modifierText = "abstract" Then symbol.isAbstract = True
				If interfaceOwner And modifierText = "default" Then
					symbol.isAbstract = False
					symbol.interfaceMethodKind = INTERFACE_METHOD_DEFAULT
				End If
			Next
			If interfaceOwner And symbol.interfaceMethodKind = INTERFACE_METHOD_ABSTRACT And ContainsRoutineModifier(declaration, "override") Then symbol.interfaceMethodKind = INTERFACE_METHOD_REABSTRACT
		End If
		If symbol And (externDepth > 0 Or RoutineHasExternalBinding(declaration)) Then
			symbol.isExternal = True
			symbol.externalName = ExternalRoutineName(declaration, symbol.name)
		End If
		Local scope:TScope = CreateScope(SCOPE_ROUTINE, parent, symbol, declaration)
		symbol.memberScope = scope
		model.syntaxScopeMap.Insert(declaration.body, scope)
		If declaration.signature Then
			symbol.genericArity = declaration.signature.genericParameters.length
			For Local genericParameter:TGenericParameterSyntax = EachIn declaration.signature.genericParameters
				Declare(SYMBOL_TYPE_PARAMETER, genericParameter.nameToken, genericParameter, scope, VISIBILITY_PRIVATE)
			Next
			For Local parameter:TParameterSyntax = EachIn declaration.signature.parameters
				Declare(SYMBOL_PARAMETER, parameter.nameToken, parameter, scope, VISIBILITY_PRIVATE)
			Next
		End If
		CollectSequence(declaration.body.statements, scope, VISIBILITY_PUBLIC)
	End Method

	Function ContainsRoutineModifier:Int(declaration:TRoutineDeclarationSyntax, name:String)
		If Not declaration Or Not declaration.signature Then Return False
		For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
			If token.text.ToLower() = name.ToLower() Then Return True
		Next
		Return False
	End Function

	Method ValidateNoMangleOverload(symbol:TSymbol, parent:TScope, declaration:TRoutineDeclarationSyntax)
		If Not symbol Or Not parent Then Return
		Local symbolNoMangle:Int = symbol.metadata And symbol.metadata.Has("nomangle")
		For Local candidate:TSymbol = EachIn parent.LookupLocal(symbol.name)
			If Not candidate Or candidate = symbol Or candidate.kind <> SYMBOL_ROUTINE Then Continue
			Local candidateNoMangle:Int = candidate.metadata And candidate.metadata.Has("nomangle")
			If (symbolNoMangle And (candidateNoMangle Or RoutineParameterCount(candidate) = 0)) Or (candidateNoMangle And RoutineParameterCount(symbol) = 0) Then
				diagnostics.AddLast(TDiagnostic.Create("BMX3015", "NoMangle routine '" + symbol.name + "' conflicts with another overload.", DIAGNOSTIC_ERROR, declaration.span, CurrentSourcePath()))
				Return
			End If
		Next
	End Method

	Function RoutineParameterCount:Int(symbol:TSymbol)
		If Not symbol Then Return 0
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If declaration And declaration.signature Then Return declaration.signature.parameters.length
		If symbol.parameters Then Return symbol.parameters.length
		Return 0
	End Function

	Method CollectVariables(declaration:TVariableDeclarationStatementSyntax, scope:TScope, visibility:Int)
		Local kind:Int = SYMBOL_LOCAL
		Select declaration.declarationToken.text.ToLower()
			Case "field" kind = SYMBOL_FIELD
			Case "global", "threadedglobal" kind = SYMBOL_GLOBAL
			Case "const" kind = SYMBOL_CONST
		End Select
		For Local declarator:TVariableDeclaratorSyntax = EachIn declaration.declarators
			Local symbol:TSymbol = Declare(kind, declarator.nameToken, declarator, scope, visibility)
			If symbol Then symbol.isTypeInferred = kind = SYMBOL_LOCAL And declarator.inferenceToken <> Null
			If symbol Then symbol.metadata = TDeclarationMetadata.Parse(declarator.metadataTokens, diagnostics, CurrentSourcePath())
			If symbol Then symbol.isReadOnly = HasVariableModifier(declaration, "readonly")
			If symbol And externDepth > 0 Then
				symbol.isExternal = True
				symbol.externalName = ExternalVariableName(declarator, symbol.name)
			End If
		Next
	End Method

	Function HasVariableModifier:Int(declaration:TVariableDeclarationStatementSyntax, name:String)
		If Not declaration Then Return False
		For Local token:TSyntaxToken = EachIn declaration.modifierTokens
			If token.text.ToLower() = name Then Return True
		Next
		Return False
	End Function

	Function RoutineHasExternalBinding:Int(declaration:TRoutineDeclarationSyntax)
		If Not declaration Or Not declaration.signature Then Return False
		Local metadataDepth:Int
		For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
			If token.text = "{" Then metadataDepth :+ 1; Continue
			If token.text = "}" Then
				If metadataDepth > 0 Then metadataDepth :- 1
				Continue
			End If
			If token.text = "=" And metadataDepth = 0 Then Return True
		Next
		Return False
	End Function

	Function ExternalRoutineName:String(declaration:TRoutineDeclarationSyntax, fallback:String)
		If declaration And declaration.signature Then
			Local afterAssignment:Int
			Local metadataDepth:Int
			For Local token:TSyntaxToken = EachIn declaration.signature.modifierTokens
				If token.text = "{" Then metadataDepth :+ 1; Continue
				If token.text = "}" Then
					If metadataDepth > 0 Then metadataDepth :- 1
					Continue
				End If
				If metadataDepth Then Continue
				If afterAssignment And token.kind = TOKEN_STRING_LITERAL Then Return DecodeExternalName(token.text)
				If token.text = "=" Then afterAssignment = True
			Next
		End If
		Return fallback
	End Function

	Function ExternalVariableName:String(declarator:TVariableDeclaratorSyntax, fallback:String)
		If declarator Then
			Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(declarator.initializer)
			If literal And literal.literalToken.kind = TOKEN_STRING_LITERAL Then Return DecodeExternalName(literal.literalToken.text)
		End If
		Return fallback
	End Function

	Function DecodeExternalName:String(text:String)
		If text.length >= 2 And text[0] = 34 And text[text.length - 1] = 34 Then Return text[1..text.length - 1]
		Return text
	End Function

	Method TargetPlatform:String()
		If snapshot And snapshot.options Then Return snapshot.options.targetPlatform
		Return ""
	End Method

	Method CollectChildBlock(block:TBlockSyntax, parent:TScope)
		CollectScopedBlock(block, parent, SCOPE_BLOCK, block)
	End Method

	Method CollectScopedBlock(block:TBlockSyntax, parent:TScope, kind:Int, syntax:TSyntaxNode)
		If Not block Then Return
		Local scope:TScope = CreateScope(kind, parent, Null, syntax)
		model.syntaxScopeMap.Insert(block, scope)
		CollectSequence(block.statements, scope, VISIBILITY_PUBLIC)
	End Method

	Function EnclosingRoutine:TSymbol(scope:TScope)
		While scope
			If scope.kind = SCOPE_ROUTINE Then Return scope.owner
			scope = scope.parent
		Wend
		Return Null
	End Function

	Function DiagnosticsToArray:TDiagnostic[](list:TList)
		Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
		Local index:Int
		For Local value:TDiagnostic = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function
End Type
