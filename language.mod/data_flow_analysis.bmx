' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map

Import "conditional_evaluator.bmx"
Import "constant_evaluation.bmx"
Import "semantic_model.bmx"

Type TDataFlowAnalyzer
	Field model:TSemanticModel
	Field section:TDataSection
	Field definitions:TList = New TList
	Field items:TList = New TList
	Field restores:TList = New TList
	Field restoreBindings:TList = New TList
	Field reads:TList = New TList
	Field diagnostics:TList = New TList
	Field syntaxPaths:TMap = New TMap
	Field currentPath:String

	Function Analyze:TSemanticModel(model:TSemanticModel)
		TConstantEvaluator.Evaluate(model)
		Local analyzer:TDataFlowAnalyzer = New TDataFlowAnalyzer
		analyzer.model = model
		analyzer.section = New TDataSection
		Local document:TSourceDocumentModel
		If model.snapshot Then document = model.snapshot.rootDocument
		analyzer.VisitSequence(model.syntaxTree.root.members, document)
		analyzer.section.definitions = DataDefinitionsToArray(analyzer.definitions)
		analyzer.section.items = DataItemsToArray(analyzer.items)
		analyzer.ResolveRestores()
		analyzer.BuildReads()
		analyzer.section.restores = DataRestoresToArray(analyzer.restoreBindings)
		analyzer.section.reads = DataReadsToArray(analyzer.reads)
		model.dataSection = analyzer.section
		model.diagnostics = MergeDataDiagnostics(model.diagnostics, DataDiagnosticsToArray(analyzer.diagnostics))
		Return model
	End Function

	Method VisitSequence(nodes:TSyntaxNode[], document:TSourceDocumentModel)
		For Local node:TSyntaxNode = EachIn nodes
			VisitNode(node, document)
		Next
	End Method

	Method VisitNode(node:TSyntaxNode, document:TSourceDocumentModel)
		If Not node Then Return
		currentPath = DocumentPath(document)
		syntaxPaths.Insert(node, currentPath)
		Local includeSyntax:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
		If includeSyntax And document Then
			Local included:TSourceDocumentModel = IncludedDocument(document, includeSyntax)
			If included Then VisitSequence(included.tree.root.members, included)
			Return
		End If
		Local definitionSyntax:TDefDataStatementSyntax = TDefDataStatementSyntax(node)
		If definitionSyntax Then
			CollectDefinition(definitionSyntax)
			Return
		End If
		Local restoreSyntax:TRestoreDataStatementSyntax = TRestoreDataStatementSyntax(node)
		If restoreSyntax Then
			restores.AddLast(restoreSyntax)
			Return
		End If
		Local readSyntax:TReadDataStatementSyntax = TReadDataStatementSyntax(node)
		If readSyntax Then
			reads.AddLast(readSyntax)
			Return
		End If

		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration Then
			VisitSequence(typeDeclaration.body.statements, document)
			Return
		End If
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine Then
			VisitSequence(routine.body.statements, document)
			Return
		End If
		Local external:TExternBlockSyntax = TExternBlockSyntax(node)
		If external Then
			VisitSequence(external.body.statements, document)
			Return
		End If
		Local block:TBlockSyntax = TBlockSyntax(node)
		If block Then
			VisitSequence(block.statements, document)
			Return
		End If

		Local conditional:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
		If conditional Then
			If model.snapshot And model.snapshot.options Then
				Local indexes:Int[] = TConditionalEvaluator.ActiveBranchIndexes(conditional, model.snapshot.options.conditionalSymbols)
				For Local index:Int = EachIn indexes
					VisitSequence(conditional.branches[index].body.statements, document)
				Next
			Else
				For Local branch:TConditionalBranchSyntax = EachIn conditional.branches
					VisitSequence(branch.body.statements, document)
				Next
			End If
			Return
		End If

		Local conditionalIf:TIfStatementSyntax = TIfStatementSyntax(node)
		If conditionalIf Then
			VisitSequence(conditionalIf.thenBlock.statements, document)
			For Local clause:TElseIfClauseSyntax = EachIn conditionalIf.elseIfClauses
				VisitSequence(clause.block.statements, document)
			Next
			If conditionalIf.elseClause Then VisitSequence(conditionalIf.elseClause.block.statements, document)
			Return
		End If
		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(node)
		If whileStatement Then
			VisitSequence(whileStatement.body.statements, document)
			Return
		End If
		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(node)
		If repeatStatement Then
			VisitSequence(repeatStatement.body.statements, document)
			Return
		End If
		Local forStatement:TForStatementSyntax = TForStatementSyntax(node)
		If forStatement Then
			VisitSequence(forStatement.body.statements, document)
			Return
		End If
		Local selectStatement:TSelectStatementSyntax = TSelectStatementSyntax(node)
		If selectStatement Then
			For Local selectedCase:TCaseClauseSyntax = EachIn selectStatement.cases
				If Not model.snapshot Or TConditionalEvaluator.IsActive(selectedCase.conditionalExpression, model.snapshot.options.conditionalSymbols) Then VisitSequence(selectedCase.body.statements, document)
			Next
			For Local defaultClause:TDefaultClauseSyntax = EachIn selectStatement.defaultClauses
				If Not model.snapshot Or TConditionalEvaluator.IsActive(defaultClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then VisitSequence(defaultClause.body.statements, document)
			Next
			Return
		End If
		Local tryStatement:TTryStatementSyntax = TTryStatementSyntax(node)
		If tryStatement Then
			VisitSequence(tryStatement.body.statements, document)
			For Local catchClause:TCatchClauseSyntax = EachIn tryStatement.catches
				VisitSequence(catchClause.body.statements, document)
			Next
			If tryStatement.finallyClause Then VisitSequence(tryStatement.finallyClause.body.statements, document)
			Return
		End If
		Local usingStatement:TUsingStatementSyntax = TUsingStatementSyntax(node)
		If usingStatement Then VisitSequence(usingStatement.body.statements, document)
	End Method

	Method CollectDefinition(syntax:TDefDataStatementSyntax)
		Local definition:TDataDefinition = New TDataDefinition
		definition.syntax = syntax
		definition.startIndex = items.Count()
		If syntax.label And syntax.label.nameToken Then
			definition.labelName = syntax.label.nameToken.text
			definition.normalizedLabel = definition.labelName.ToLower()
			definition.labelToken = syntax.label.nameToken
			Local previous:TDataDefinition = TDataDefinition(section.labels.ValueForKey(definition.normalizedLabel))
			If previous Then
				AddDiagnostic("BMX3500", "Duplicate data label '" + definition.labelName + "'.", definition.labelToken.span)
			Else
				section.labels.Insert(definition.normalizedLabel, definition)
			End If
		End If
		Local definitionItems:TList = New TList
		For Local expressionSyntax:TExpressionSyntax = EachIn syntax.values
			Local item:TDataItem = New TDataItem
			item.index = items.Count()
			item.definition = definition
			item.syntax = expressionSyntax
			If expressionSyntax Then
				item.expression = model.BoundExpression(expressionSyntax)
				item.semanticType = model.ExpressionType(expressionSyntax)
				Local constant:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(model, expressionSyntax, currentPath)
				item.constantValue = constant
				If Not constant Or (constant.kind <> CONSTANT_VALUE_INTEGER And constant.kind <> CONSTANT_VALUE_FLOAT And constant.kind <> CONSTANT_VALUE_STRING) Then AddDiagnostic("BMX3503", "Data items must be constant numeric or string expressions.", expressionSyntax.span)
			Else
				AddDiagnostic("BMX3503", "A data item is missing between separators.", syntax.span)
			End If
			items.AddLast(item)
			definitionItems.AddLast(item)
		Next
		definition.items = DataItemsToArray(definitionItems)
		definitions.AddLast(definition)
		model.dataDefinitionMap.Insert(syntax, definition)
	End Method

	Method ResolveRestores()
		For Local syntax:TRestoreDataStatementSyntax = EachIn restores
			currentPath = PathForSyntax(syntax)
			Local name:TNameExpressionSyntax = TNameExpressionSyntax(syntax.label)
			If Not name Or Not name.nameToken Then
				Local span:TSourceSpan = syntax.span
				If syntax.label Then span = syntax.label.span
				AddDiagnostic("BMX3501", "RestoreData requires a data-label name.", span)
				Continue
			End If
			Local definition:TDataDefinition = TDataDefinition(section.labels.ValueForKey(name.nameToken.text.ToLower()))
			If Not definition Then
				AddDiagnostic("BMX3502", "Data label '" + name.nameToken.text + "' could not be found.", name.nameToken.span)
				Continue
			End If
			Local binding:TDataRestoreBinding = New TDataRestoreBinding
			binding.syntax = syntax
			binding.definition = definition
			binding.itemIndex = definition.startIndex
			model.dataRestoreMap.Insert(syntax, binding)
			restoreBindings.AddLast(binding)
		Next
	End Method

	Method BuildReads()
		Local syntaxes:TList = reads
		reads = New TList
		For Local syntax:TReadDataStatementSyntax = EachIn syntaxes
			currentPath = PathForSyntax(syntax)
			Local operation:TDataReadOperation = New TDataReadOperation
			operation.syntax = syntax
			operation.cursorAdvance = syntax.targets.length
			operation.targets = New TDataReadTarget[syntax.targets.length]
			For Local index:Int = 0 Until syntax.targets.length
				Local target:TDataReadTarget = New TDataReadTarget
				target.syntax = syntax.targets[index]
				target.cursorOffset = index
				If target.syntax Then
					target.expression = model.BoundExpression(target.syntax)
					target.targetType = model.ExpressionType(target.syntax)
					If Not IsWritableTarget(target.syntax) Then AddDiagnostic("BMX3510", "ReadData target must be a writable variable, field, or indexed element.", target.syntax.span)
					target.conversionKind = DataReadConversion(target.targetType)
					If target.targetType And target.conversionKind = DATA_READ_CONVERSION_NONE Then AddDiagnostic("BMX3511", "ReadData does not support target type '" + target.targetType.DisplayName() + "'.", target.syntax.span)
				Else
					AddDiagnostic("BMX3510", "A ReadData target is missing between separators.", syntax.span)
				End If
				operation.targets[index] = target
			Next
			reads.AddLast(operation)
			model.dataReadMap.Insert(syntax, operation)
		Next
	End Method

	Method IsWritableTarget:Int(expression:TExpressionSyntax)
		Local parentheses:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
		If parentheses Then Return IsWritableTarget(parentheses.expression)
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then
			Local symbol:TSymbol = model.ReferencedSymbol(name)
			If Not symbol Then Return False
			Return symbol.kind = SYMBOL_LOCAL Or symbol.kind = SYMBOL_GLOBAL Or symbol.kind = SYMBOL_FIELD Or symbol.kind = SYMBOL_PARAMETER Or symbol.kind = SYMBOL_CATCH_PARAMETER
		End If
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then
			Local resolved:TResolvedMemberAccess = model.ResolvedMember(member)
			Return resolved And resolved.member And resolved.member.kind = SYMBOL_FIELD
		End If
		If TIndexExpressionSyntax(expression) Then Return model.ResolvedIndex(expression) <> Null
		Return False
	End Method

	Method DataReadConversion:Int(semanticType:TSemanticType)
		If Not semanticType Then Return DATA_READ_CONVERSION_NONE
		If semanticType = model.BuiltinType("Byte") Or semanticType = model.BuiltinType("Short") Or semanticType = model.BuiltinType("Int") Then Return DATA_READ_CONVERSION_INT
		If semanticType = model.BuiltinType("UInt") Then Return DATA_READ_CONVERSION_UINT
		If semanticType = model.BuiltinType("Float") Then Return DATA_READ_CONVERSION_FLOAT
		If semanticType = model.BuiltinType("Double") Then Return DATA_READ_CONVERSION_DOUBLE
		If semanticType = model.BuiltinType("Long") Then Return DATA_READ_CONVERSION_LONG
		If semanticType = model.BuiltinType("ULong") Then Return DATA_READ_CONVERSION_ULONG
		If semanticType = model.BuiltinType("Size_T") Then Return DATA_READ_CONVERSION_SIZET
		If semanticType = model.BuiltinType("LongInt") Then Return DATA_READ_CONVERSION_LONGINT
		If semanticType = model.BuiltinType("ULongInt") Then Return DATA_READ_CONVERSION_ULONGINT
		If semanticType = model.BuiltinType("String") Then Return DATA_READ_CONVERSION_STRING
		Return DATA_READ_CONVERSION_NONE
	End Method

	Method IncludedDocument:TSourceDocumentModel(document:TSourceDocumentModel, syntax:TIncludeDirectiveSyntax)
		For Local edge:TIncludeEdge = EachIn document.includes
			If edge.syntax = syntax Then Return edge.target
		Next
		Return Null
	End Method

	Method DocumentPath:String(document:TSourceDocumentModel)
		If document Then Return document.path
		If model And model.syntaxTree And model.syntaxTree.source Then Return model.syntaxTree.source.path
		Return ""
	End Method

	Method PathForSyntax:String(syntax:TSyntaxNode)
		Local path:String = String(syntaxPaths.ValueForKey(syntax))
		If path.length Then Return path
		Return DocumentPath(Null)
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan)
		diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span, currentPath))
	End Method
End Type

Type TDataSectionDumper
	Function Dump:String(section:TDataSection)
		If Not section Then Return "<missing data section>~n"
		Local result:String = "DataSection items=" + section.items.length + "~n"
		For Local definition:TDataDefinition = EachIn section.definitions
			result :+ "  DefData @" + definition.startIndex
			If definition.labelName.length Then result :+ " #" + definition.labelName
			result :+ " count=" + definition.items.length + "~n"
			For Local item:TDataItem = EachIn definition.items
				result :+ "    [" + item.index + "]"
				If item.semanticType Then result :+ " " + item.semanticType.DisplayName()
				If item.constantValue Then result :+ " = " + item.constantValue.DisplayValue()
				result :+ "~n"
			Next
		Next
		For Local read:TDataReadOperation = EachIn section.reads
			result :+ "  ReadData advance=" + read.cursorAdvance
			If read.mayRaiseOutOfData Then result :+ " [out-of-data-check]"
			result :+ "~n"
			For Local target:TDataReadTarget = EachIn read.targets
				result :+ "    +" + target.cursorOffset + " " + DataReadConversionName(target.conversionKind)
				If target.targetType Then result :+ " -> " + target.targetType.DisplayName()
				result :+ "~n"
			Next
		Next
		Return result
	End Function

	Function DataReadConversionName:String(kind:Int)
		Select kind
			Case DATA_READ_CONVERSION_INT Return "to-int"
			Case DATA_READ_CONVERSION_UINT Return "to-uint"
			Case DATA_READ_CONVERSION_FLOAT Return "to-float"
			Case DATA_READ_CONVERSION_DOUBLE Return "to-double"
			Case DATA_READ_CONVERSION_LONG Return "to-long"
			Case DATA_READ_CONVERSION_ULONG Return "to-ulong"
			Case DATA_READ_CONVERSION_SIZET Return "to-sizet"
			Case DATA_READ_CONVERSION_LONGINT Return "to-longint"
			Case DATA_READ_CONVERSION_ULONGINT Return "to-ulongint"
			Case DATA_READ_CONVERSION_STRING Return "to-string"
		End Select
		Return "unsupported"
	End Function
End Type

Function DataDefinitionsToArray:TDataDefinition[](list:TList)
	Local result:TDataDefinition[] = New TDataDefinition[list.Count()]
	Local index:Int
	For Local definition:TDataDefinition = EachIn list
		result[index] = definition
		index :+ 1
	Next
	Return result
End Function

Function DataItemsToArray:TDataItem[](list:TList)
	Local result:TDataItem[] = New TDataItem[list.Count()]
	Local index:Int
	For Local item:TDataItem = EachIn list
		result[index] = item
		index :+ 1
	Next
	Return result
End Function

Function DataRestoresToArray:TDataRestoreBinding[](list:TList)
	Local result:TDataRestoreBinding[] = New TDataRestoreBinding[list.Count()]
	Local index:Int
	For Local binding:TDataRestoreBinding = EachIn list
		result[index] = binding
		index :+ 1
	Next
	Return result
End Function

Function DataReadsToArray:TDataReadOperation[](list:TList)
	Local result:TDataReadOperation[] = New TDataReadOperation[list.Count()]
	Local index:Int
	For Local operation:TDataReadOperation = EachIn list
		result[index] = operation
		index :+ 1
	Next
	Return result
End Function

Function DataDiagnosticsToArray:TDiagnostic[](list:TList)
	Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
	Local index:Int
	For Local diagnostic:TDiagnostic = EachIn list
		result[index] = diagnostic
		index :+ 1
	Next
	Return result
End Function

Function MergeDataDiagnostics:TDiagnostic[](first:TDiagnostic[], second:TDiagnostic[])
	Local result:TDiagnostic[] = New TDiagnostic[first.length + second.length]
	For Local index:Int = 0 Until first.length
		result[index] = first[index]
	Next
	For Local index:Int = 0 Until second.length
		result[first.length + index] = second[index]
	Next
	Return result
End Function
