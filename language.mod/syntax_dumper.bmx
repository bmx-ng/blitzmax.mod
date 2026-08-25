' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "syntax.bmx"

Type TSyntaxDumper
	Field source:TSourceText

	Function Dump:String(tree:TSyntaxTree)
		Local dumper:TSyntaxDumper = New TSyntaxDumper
		dumper.source = tree.source
		Return dumper.DumpNode(tree.root, "")
	End Function

	Method DumpNode:String(node:TSyntaxNode, indent:String)
		If Not node Then Return indent + "<missing>~n"
		Local result:String = indent + node.KindName() + " " + node.span.ToString()

		If TRoutineDeclarationSyntax(node) Then
			Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
			If routine.nameToken Then result :+ " " + routine.nameToken.text
			result :+ "~n" + DumpNode(routine.signature, indent + "  ")
			result :+ DumpNode(routine.body, indent + "  ")
			result :+ DumpNode(routine.terminator, indent + "  ")
		Else If TTypeDeclarationSyntax(node) Then
			Local declaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
			If declaration.nameToken Then result :+ " " + declaration.nameToken.text
			result :+ "~n" + DumpNode(declaration.header, indent + "  ")
			result :+ DumpNode(declaration.body, indent + "  ")
			result :+ DumpNode(declaration.terminator, indent + "  ")
		Else If TIfStatementSyntax(node) Then
			Local ifStatement:TIfStatementSyntax = TIfStatementSyntax(node)
			If ifStatement.singleLine Then result :+ " [single-line]"
			result :+ "~n" + DumpNode(ifStatement.condition, indent + "  ")
			result :+ DumpNode(ifStatement.thenBlock, indent + "  ")
			For Local clause:TElseIfClauseSyntax = EachIn ifStatement.elseIfClauses
				result :+ DumpNode(clause, indent + "  ")
			Next
			If ifStatement.elseClause Then result :+ DumpNode(ifStatement.elseClause, indent + "  ")
			If ifStatement.terminator Then result :+ DumpNode(ifStatement.terminator, indent + "  ")
		Else If TElseIfClauseSyntax(node) Then
			Local clause:TElseIfClauseSyntax = TElseIfClauseSyntax(node)
			result :+ "~n" + DumpNode(clause.condition, indent + "  ")
			result :+ DumpNode(clause.block, indent + "  ")
		Else If TElseClauseSyntax(node) Then
			result :+ "~n" + DumpNode(TElseClauseSyntax(node).block, indent + "  ")
		Else If TWhileStatementSyntax(node) Then
			Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(node)
			result :+ "~n"
			If whileStatement.label Then result :+ DumpNode(whileStatement.label, indent + "  ")
			result :+ DumpNode(whileStatement.condition, indent + "  ")
			result :+ DumpNode(whileStatement.body, indent + "  ")
			result :+ DumpNode(whileStatement.terminator, indent + "  ")
		Else If TRepeatStatementSyntax(node) Then
			Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(node)
			result :+ " " + repeatStatement.terminationToken.text + "~n"
			If repeatStatement.label Then result :+ DumpNode(repeatStatement.label, indent + "  ")
			result :+ DumpNode(repeatStatement.body, indent + "  ")
			If repeatStatement.condition Then result :+ DumpNode(repeatStatement.condition, indent + "  ")
		Else If TForStatementSyntax(node) Then
			Local forStatement:TForStatementSyntax = TForStatementSyntax(node)
			result :+ " " + TokensText(forStatement.headerTokens) + "~n"
			If forStatement.label Then result :+ DumpNode(forStatement.label, indent + "  ")
			result :+ DumpNode(forStatement.header, indent + "  ")
			result :+ DumpNode(forStatement.body, indent + "  ")
			result :+ DumpNode(forStatement.terminator, indent + "  ")
		Else If TForHeaderSyntax(node) Then
			Local header:TForHeaderSyntax = TForHeaderSyntax(node)
			If header.localToken Then result :+ " local"
			If header.eachInToken Then result :+ " eachin" Else If header.rangeToken Then result :+ " " + header.rangeToken.text.ToLower()
			result :+ "~n"
			For Local declaration:TVariableDeclaratorSyntax = EachIn header.declarations
				result :+ DumpNode(declaration, indent + "  ")
			Next
			If header.target Then result :+ DumpNode(header.target, indent + "  ")
			If header.initialValue Then result :+ DumpNode(header.initialValue, indent + "  ")
			If header.collection Then result :+ DumpNode(header.collection, indent + "  ")
			If header.limit Then result :+ DumpNode(header.limit, indent + "  ")
			If header.stepExpression Then result :+ DumpNode(header.stepExpression, indent + "  ")
		Else If TLabelSyntax(node) Then
			Local label:TLabelSyntax = TLabelSyntax(node)
			If label.nameToken Then result :+ " #" + label.nameToken.text
			result :+ "~n"
		Else If TSelectStatementSyntax(node) Then
			Local selectStatement:TSelectStatementSyntax = TSelectStatementSyntax(node)
			result :+ "~n" + DumpNode(selectStatement.expression, indent + "  ")
			For Local clause:TCaseClauseSyntax = EachIn selectStatement.cases
				result :+ DumpNode(clause, indent + "  ")
			Next
			For Local defaultClause:TDefaultClauseSyntax = EachIn selectStatement.defaultClauses
				result :+ DumpNode(defaultClause, indent + "  ")
			Next
			result :+ DumpNode(selectStatement.terminator, indent + "  ")
		Else If TCaseClauseSyntax(node) Then
			Local caseClause:TCaseClauseSyntax = TCaseClauseSyntax(node)
			result :+ "~n"
			If caseClause.conditionalExpression Then result :+ DumpNode(caseClause.conditionalExpression, indent + "  ")
			For Local value:TExpressionSyntax = EachIn caseClause.values
				result :+ DumpNode(value, indent + "  ")
			Next
			result :+ DumpNode(caseClause.body, indent + "  ")
		Else If TDefaultClauseSyntax(node) Then
			Local defaultClause:TDefaultClauseSyntax = TDefaultClauseSyntax(node)
			result :+ "~n"
			If defaultClause.conditionalExpression Then result :+ DumpNode(defaultClause.conditionalExpression, indent + "  ")
			result :+ DumpNode(defaultClause.body, indent + "  ")
		Else If TTryStatementSyntax(node) Then
			Local tryStatement:TTryStatementSyntax = TTryStatementSyntax(node)
			result :+ "~n" + DumpNode(tryStatement.body, indent + "  ")
			For Local clause:TCatchClauseSyntax = EachIn tryStatement.catches
				result :+ DumpNode(clause, indent + "  ")
			Next
			If tryStatement.finallyClause Then result :+ DumpNode(tryStatement.finallyClause, indent + "  ")
			result :+ DumpNode(tryStatement.terminator, indent + "  ")
		Else If TCatchClauseSyntax(node) Then
			Local catchClause:TCatchClauseSyntax = TCatchClauseSyntax(node)
			If catchClause.nameToken Then result :+ " " + catchClause.nameToken.text
			result :+ "~n"
			If catchClause.declaredType Then result :+ DumpNode(catchClause.declaredType, indent + "  ")
			result :+ DumpNode(catchClause.body, indent + "  ")
		Else If TFinallyClauseSyntax(node) Then
			result :+ "~n" + DumpNode(TFinallyClauseSyntax(node).body, indent + "  ")
		Else If TUsingStatementSyntax(node) Then
			Local usingStatement:TUsingStatementSyntax = TUsingStatementSyntax(node)
			result :+ "~n"
			For Local resource:TVariableDeclarationStatementSyntax = EachIn usingStatement.resources
				result :+ DumpNode(resource, indent + "  ")
			Next
			result :+ DumpNode(usingStatement.body, indent + "  ")
			result :+ DumpNode(usingStatement.terminator, indent + "  ")
		Else If TConditionalRegionSyntax(node) Then
			result :+ "~n"
			For Local branch:TConditionalBranchSyntax = EachIn TConditionalRegionSyntax(node).branches
				result :+ DumpNode(branch, indent + "  ")
			Next
			If TConditionalRegionSyntax(node).sharedRoutineBody Then result :+ DumpNode(TConditionalRegionSyntax(node).sharedRoutineBody, indent + "  ")
			If TConditionalRegionSyntax(node).sharedRoutineTerminator Then result :+ DumpNode(TConditionalRegionSyntax(node).sharedRoutineTerminator, indent + "  ")
		Else If TConditionalBranchSyntax(node) Then
			Local branch:TConditionalBranchSyntax = TConditionalBranchSyntax(node)
			result :+ " " + branch.conditionText + "~n"
			result :+ DumpNode(branch.condition, indent + "  ")
			result :+ DumpNode(branch.body, indent + "  ")
		Else If TConditionalNameSyntax(node) Then
			result :+ " " + TConditionalNameSyntax(node).nameToken.text + "~n"
		Else If TConditionalNotSyntax(node) Then
			result :+ " " + TConditionalNotSyntax(node).notToken.text + "~n"
			result :+ DumpNode(TConditionalNotSyntax(node).operand, indent + "  ")
		Else If TConditionalBinarySyntax(node) Then
			Local binary:TConditionalBinarySyntax = TConditionalBinarySyntax(node)
			result :+ " " + binary.operatorToken.text + "~n"
			result :+ DumpNode(binary.left, indent + "  ")
			result :+ DumpNode(binary.right, indent + "  ")
		Else If TConditionalParenthesizedSyntax(node) Then
			result :+ "~n" + DumpNode(TConditionalParenthesizedSyntax(node).expression, indent + "  ")
		Else If TReturnStatementSyntax(node) Then
			result :+ "~n"
			If TReturnStatementSyntax(node).expression Then result :+ DumpNode(TReturnStatementSyntax(node).expression, indent + "  ")
		Else If TYieldStatementSyntax(node) Then
			result :+ "~n"
			If TYieldStatementSyntax(node).expression Then result :+ DumpNode(TYieldStatementSyntax(node).expression, indent + "  ")
		Else If TThrowStatementSyntax(node) Then
			result :+ "~n" + DumpNode(TThrowStatementSyntax(node).expression, indent + "  ")
		Else If TExitStatementSyntax(node) Then
			result :+ "~n"
			If TExitStatementSyntax(node).label Then result :+ DumpNode(TExitStatementSyntax(node).label, indent + "  ")
		Else If TContinueStatementSyntax(node) Then
			result :+ "~n"
			If TContinueStatementSyntax(node).label Then result :+ DumpNode(TContinueStatementSyntax(node).label, indent + "  ")
		Else If TAssertStatementSyntax(node) Then
			Local assertStatement:TAssertStatementSyntax = TAssertStatementSyntax(node)
			If assertStatement.separatorToken Then result :+ " " + assertStatement.separatorToken.text
			result :+ "~n"
			If assertStatement.condition Then result :+ DumpNode(assertStatement.condition, indent + "  ")
			If assertStatement.message Then result :+ DumpNode(assertStatement.message, indent + "  ")
		Else If TReleaseStatementSyntax(node) Then
			result :+ "~n"
			If TReleaseStatementSyntax(node).expression Then result :+ DumpNode(TReleaseStatementSyntax(node).expression, indent + "  ")
		Else If TSourceModeSyntax(node) Then
			result :+ " " + TSourceModeSyntax(node).modeToken.text + "~n"
		Else If TImportDirectiveSyntax(node) Then
			Local importDirective:TImportDirectiveSyntax = TImportDirectiveSyntax(node)
			If importDirective.isFramework Then result :+ " Framework" Else result :+ " Import"
			result :+ " " + importDirective.targetText
			If importDirective.isSourceImport Then result :+ " [source]"
			If importDirective.isNativeImport Then result :+ " [native]"
			result :+ "~n"
		Else If TIncludeDirectiveSyntax(node) Then
			result :+ " " + TIncludeDirectiveSyntax(node).pathText + "~n"
		Else If TDefDataStatementSyntax(node) Then
			Local data:TDefDataStatementSyntax = TDefDataStatementSyntax(node)
			result :+ "~n"
			If data.label Then result :+ DumpNode(data.label, indent + "  ")
			For Local value:TExpressionSyntax = EachIn data.values
				If value Then result :+ DumpNode(value, indent + "  ")
			Next
		Else If TReadDataStatementSyntax(node) Then
			result :+ "~n"
			For Local target:TExpressionSyntax = EachIn TReadDataStatementSyntax(node).targets
				If target Then result :+ DumpNode(target, indent + "  ")
			Next
		Else If TRestoreDataStatementSyntax(node) Then
			result :+ "~n" + DumpNode(TRestoreDataStatementSyntax(node).label, indent + "  ")
		Else If TEnumDeclarationSyntax(node) Then
			Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(node)
			If enumDeclaration.nameToken Then result :+ " " + enumDeclaration.nameToken.text
			If enumDeclaration.typeTokens.length Then result :+ " :type=" + TokensText(enumDeclaration.typeTokens)
			If enumDeclaration.flagsToken Then result :+ " flags"
			result :+ "~n"
			For Local value:TEnumValueSyntax = EachIn enumDeclaration.values
				result :+ DumpNode(value, indent + "  ")
			Next
			If enumDeclaration.terminator Then result :+ DumpNode(enumDeclaration.terminator, indent + "  ")
		Else If TExternBlockSyntax(node) Then
			Local externBlock:TExternBlockSyntax = TExternBlockSyntax(node)
			result :+ "~n" + DumpNode(externBlock.body, indent + "  ")
			If externBlock.terminator Then result :+ DumpNode(externBlock.terminator, indent + "  ")
		Else If TEnumValueSyntax(node) Then
			Local enumValue:TEnumValueSyntax = TEnumValueSyntax(node)
			If enumValue.nameToken Then result :+ " " + enumValue.nameToken.text
			If enumValue.separatorToken Then result :+ " ,"
			result :+ "~n"
			If enumValue.value Then result :+ DumpNode(enumValue.value, indent + "  ")
		Else If TTypeDeclarationHeaderSyntax(node) Then
			Local header:TTypeDeclarationHeaderSyntax = TTypeDeclarationHeaderSyntax(node)
			If header.nameToken Then result :+ " " + header.nameToken.text
			result :+ "~n"
			For Local parameter:TGenericParameterSyntax = EachIn header.genericParameters
				result :+ DumpNode(parameter, indent + "  ")
			Next
			For Local extendedType:TTypeReferenceSyntax = EachIn header.extendsTypes
				result :+ DumpNode(extendedType, indent + "  ")
			Next
			For Local implementedType:TTypeReferenceSyntax = EachIn header.implementedTypes
				result :+ DumpNode(implementedType, indent + "  ")
			Next
			For Local constraint:TGenericConstraintSyntax = EachIn header.constraints
				result :+ DumpNode(constraint, indent + "  ")
			Next
		Else If TGenericParameterSyntax(node) Then
			result :+ " " + TGenericParameterSyntax(node).nameToken.text + "~n"
		Else If TGenericConstraintSyntax(node) Then
			Local constraint:TGenericConstraintSyntax = TGenericConstraintSyntax(node)
			result :+ " " + constraint.parameterNameToken.text + "~n"
			For Local constraintType:TTypeReferenceSyntax = EachIn constraint.constraintTypes
				result :+ DumpNode(constraintType, indent + "  ")
			Next
		Else If TVisibilitySectionSyntax(node) Then
			Local visibility:TVisibilitySectionSyntax = TVisibilitySectionSyntax(node)
			result :+ " " + visibility.visibilityToken.text
			If visibility.internalToken Then result :+ " " + visibility.internalToken.text
			result :+ "~n"
		Else If TCompilationUnitSyntax(node) Then
			result :+ "~n"
			For Local member:TSyntaxNode = EachIn TCompilationUnitSyntax(node).members
				result :+ DumpNode(member, indent + "  ")
			Next
		Else If TBlockSyntax(node) Then
			result :+ "~n"
			For Local statement:TSyntaxNode = EachIn TBlockSyntax(node).statements
				result :+ DumpNode(statement, indent + "  ")
			Next
		Else If TCallStatementSyntax(node) Then
			Local call:TCallStatementSyntax = TCallStatementSyntax(node)
			result :+ " " + source.Slice(call.span).Trim()
			If call.hasParentheses Then result :+ " [parenthesized]"
			result :+ "~n"
		Else If TAssignmentStatementSyntax(node) Then
			Local assignment:TAssignmentStatementSyntax = TAssignmentStatementSyntax(node)
			result :+ " " + assignment.operatorToken.text + "~n"
			result :+ DumpNode(assignment.left, indent + "  ")
			result :+ DumpNode(assignment.right, indent + "  ")
		Else If TVariableDeclarationStatementSyntax(node) Then
			Local declaration:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
			result :+ " " + declaration.declarationToken.text
			If declaration.staticArrayToken Then result :+ " StaticArray"
			result :+ "~n"
			For Local declarator:TVariableDeclaratorSyntax = EachIn declaration.declarators
				result :+ DumpNode(declarator, indent + "  ")
			Next
		Else If TVariableDeclaratorSyntax(node) Then
			Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(node)
			If declarator.nameToken Then result :+ " " + declarator.nameToken.text
			If declarator.inferenceToken Then result :+ " [inferred]"
			If declarator.typeTokens.length Then result :+ " :type=" + TokensText(declarator.typeTokens)
			result :+ "~n"
			If declarator.staticArrayBound Then result :+ DumpNode(declarator.staticArrayBound, indent + "  ")
			If declarator.callableType Then result :+ DumpNode(declarator.callableType, indent + "  ")
			For Local dimension:TExpressionSyntax = EachIn declarator.arrayDimensions
				result :+ DumpNode(dimension, indent + "  ")
			Next
			If declarator.initializer Then result :+ DumpNode(declarator.initializer, indent + "  ")
		Else If TRoutineSignatureSyntax(node) Then
			Local signature:TRoutineSignatureSyntax = TRoutineSignatureSyntax(node)
			If signature.nameToken Then result :+ " " + signature.nameToken.text
			If signature.operatorName.length Then result :+ " " + signature.operatorName
			result :+ "~n"
			For Local genericParameter:TGenericParameterSyntax = EachIn signature.genericParameters
				result :+ DumpNode(genericParameter, indent + "  ")
			Next
			If signature.returnType Then result :+ DumpNode(signature.returnType, indent + "  ")
			If signature.callableReturnType Then result :+ DumpNode(signature.callableReturnType, indent + "  ")
			For Local parameter:TParameterSyntax = EachIn signature.parameters
				result :+ DumpNode(parameter, indent + "  ")
			Next
			For Local constraint:TGenericConstraintSyntax = EachIn signature.constraints
				result :+ DumpNode(constraint, indent + "  ")
			Next
		Else If TParameterSyntax(node) Then
			Local parameter:TParameterSyntax = TParameterSyntax(node)
			If parameter.nameToken Then result :+ " " + parameter.nameToken.text
			If parameter.staticArrayToken Then result :+ " StaticArray"
			If parameter.varToken Then result :+ " Var"
			result :+ "~n"
			If parameter.declaredType Then result :+ DumpNode(parameter.declaredType, indent + "  ")
			If parameter.callableType Then result :+ DumpNode(parameter.callableType, indent + "  ")
			If parameter.defaultValue Then result :+ DumpNode(parameter.defaultValue, indent + "  ")
			If parameter.staticArrayBound Then result :+ DumpNode(parameter.staticArrayBound, indent + "  ")
		Else If TStaticArrayBoundSyntax(node) Then
			Local staticBound:TStaticArrayBoundSyntax = TStaticArrayBoundSyntax(node)
			result :+ "~n"
			If staticBound.lengthExpression Then result :+ DumpNode(staticBound.lengthExpression, indent + "  ")
		Else If TCallableTypeSyntax(node) Then
			Local callable:TCallableTypeSyntax = TCallableTypeSyntax(node)
			result :+ "~n"
			If callable.returnType Then result :+ DumpNode(callable.returnType, indent + "  ")
			For Local parameter:TParameterSyntax = EachIn callable.parameters
				result :+ DumpNode(parameter, indent + "  ")
			Next
			For Local suffix:TTypeSuffixSyntax = EachIn callable.suffixes
				result :+ DumpNode(suffix, indent + "  ")
			Next
		Else If TTypeReferenceSyntax(node) Then
			Local reference:TTypeReferenceSyntax = TTypeReferenceSyntax(node)
			result :+ " " + TokensText(reference.tokens)
			If reference.pointerTokens.length Then result :+ " [pointers=" + reference.pointerTokens.length + "]"
			If reference.arrayRanks.length Then result :+ " [arrays=" + reference.arrayRanks.length + "]"
			If reference.suffixes.length Then
				result :+ " [suffixes="
				For Local index:Int = 0 Until reference.suffixes.length
					If index Then result :+ ","
					If reference.suffixes[index].suffixKind = TYPE_SUFFIX_POINTER Then
						result :+ "Ptr"
					Else
						result :+ "Array" + reference.suffixes[index].rank
					End If
				Next
				result :+ "]"
			End If
			result :+ "~n"
			If reference.closureSignature Then result :+ DumpNode(reference.closureSignature, indent + "  ")
			For Local argument:TTypeReferenceSyntax = EachIn reference.genericArguments
				result :+ DumpNode(argument, indent + "  ")
			Next
		Else If TFunctionLiteralExpressionSyntax(node) Then
			Local functionLiteral:TFunctionLiteralExpressionSyntax = TFunctionLiteralExpressionSyntax(node)
			result :+ "~n"
			If functionLiteral.returnType Then result :+ DumpNode(functionLiteral.returnType, indent + "  ")
			For Local parameter:TParameterSyntax = EachIn functionLiteral.parameters
				result :+ DumpNode(parameter, indent + "  ")
			Next
			result :+ DumpNode(functionLiteral.body, indent + "  ")
			If functionLiteral.terminator Then result :+ DumpNode(functionLiteral.terminator, indent + "  ")
		Else If TBinaryExpressionSyntax(node) Then
			Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(node)
			result :+ " " + binary.operatorToken.text + "~n"
			result :+ DumpNode(binary.left, indent + "  ")
			result :+ DumpNode(binary.right, indent + "  ")
		Else If TUnaryExpressionSyntax(node) Then
			Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(node)
			result :+ " " + unary.operatorToken.text + "~n"
			result :+ DumpNode(unary.operand, indent + "  ")
		Else If TCallExpressionSyntax(node) Then
			Local invocation:TCallExpressionSyntax = TCallExpressionSyntax(node)
			result :+ "~n" + DumpNode(invocation.callee, indent + "  ")
			For Local typeArgument:TTypeReferenceSyntax = EachIn invocation.typeArguments
				result :+ DumpNode(typeArgument, indent + "  ")
			Next
			For Local argument:TExpressionSyntax = EachIn invocation.arguments
				result :+ DumpNode(argument, indent + "  ")
			Next
		Else If TMemberAccessExpressionSyntax(node) Then
			Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(node)
			result :+ " ." + member.nameToken.text
			If member.legacyTypeTagToken Then result :+ member.legacyTypeTagToken.text
			result :+ "~n"
			result :+ DumpNode(member.expression, indent + "  ")
			For Local typeArgument:TTypeReferenceSyntax = EachIn member.typeArguments
				result :+ DumpNode(typeArgument, indent + "  ")
			Next
		Else If TIndexExpressionSyntax(node) Then
			Local indexed:TIndexExpressionSyntax = TIndexExpressionSyntax(node)
			result :+ "~n" + DumpNode(indexed.expression, indent + "  ")
			For Local index:TExpressionSyntax = EachIn indexed.indexes
				result :+ DumpNode(index, indent + "  ")
			Next
		Else If TSliceExpressionSyntax(node) Then
			Local slice:TSliceExpressionSyntax = TSliceExpressionSyntax(node)
			If slice.lowerFromEndToken Then result :+ " [lower-from-end]"
			If slice.upperFromEndToken Then result :+ " [upper-from-end]"
			result :+ "~n" + DumpNode(slice.expression, indent + "  ")
			If slice.lowerBound Then result :+ DumpNode(slice.lowerBound, indent + "  ")
			If slice.upperBound Then result :+ DumpNode(slice.upperBound, indent + "  ")
		Else If TRangeExpressionSyntax(node) Then
			Local range:TRangeExpressionSyntax = TRangeExpressionSyntax(node)
			If range.lowerFromEndToken Then result :+ " [lower-from-end]"
			If range.upperFromEndToken Then result :+ " [upper-from-end]"
			result :+ "~n"
			If range.lowerBound Then result :+ DumpNode(range.lowerBound, indent + "  ")
			If range.upperBound Then result :+ DumpNode(range.upperBound, indent + "  ")
		Else If TTypeAscriptionExpressionSyntax(node) Then
			Local ascription:TTypeAscriptionExpressionSyntax = TTypeAscriptionExpressionSyntax(node)
			result :+ "~n" + DumpNode(ascription.expression, indent + "  ")
			result :+ DumpNode(ascription.targetType, indent + "  ")
		Else If TNewExpressionSyntax(node) Then
			Local creation:TNewExpressionSyntax = TNewExpressionSyntax(node)
			result :+ "~n" + DumpNode(creation.createdType, indent + "  ")
			For Local argument:TExpressionSyntax = EachIn creation.arguments
				result :+ DumpNode(argument, indent + "  ")
			Next
			For Local dimension:TExpressionSyntax = EachIn creation.dimensions
				result :+ DumpNode(dimension, indent + "  ")
			Next
		Else If TArrayLiteralExpressionSyntax(node) Then
			Local arrayLiteral:TArrayLiteralExpressionSyntax = TArrayLiteralExpressionSyntax(node)
			result :+ "~n"
			For Local element:TExpressionSyntax = EachIn arrayLiteral.elements
				result :+ DumpNode(element, indent + "  ")
			Next
		Else If TScopeExpressionSyntax(node) Then
			result :+ " .~n"
		Else If TCastExpressionSyntax(node) Then
			Local cast:TCastExpressionSyntax = TCastExpressionSyntax(node)
			result :+ "~n" + DumpNode(cast.targetType, indent + "  ")
			result :+ DumpNode(cast.expression, indent + "  ")
		Else If TParenthesizedExpressionSyntax(node) Then
			result :+ "~n" + DumpNode(TParenthesizedExpressionSyntax(node).expression, indent + "  ")
		Else If TNameExpressionSyntax(node) Then
			Local name:TNameExpressionSyntax = TNameExpressionSyntax(node)
			result :+ " " + name.nameToken.text
			If name.legacyTypeTagToken Then result :+ name.legacyTypeTagToken.text
			If name.typeArguments.length Then
				result :+ "~n"
				For Local typeArgument:TTypeReferenceSyntax = EachIn name.typeArguments
					result :+ DumpNode(typeArgument, indent + "  ")
				Next
			End If
			If name.qualifiedSuperType Then
				result :+ "~n" + DumpNode(name.qualifiedSuperType, indent + "  ")
			Else
				result :+ "~n"
			End If
		Else If TLiteralExpressionSyntax(node) Then
			result :+ " " + TLiteralExpressionSyntax(node).literalToken.text + "~n"
		Else If TOmittedArgumentExpressionSyntax(node) Then
			result :+ " [use default]~n"
		Else If TRawExpressionSyntax(node) Then
			result :+ " " + source.Slice(node.span).Trim() + "~n"
		Else If TRawStatementSyntax(node) Or TEndStatementSyntax(node) Then
			result :+ " " + source.Slice(node.span).Trim() + "~n"
		Else If TBlockTerminatorSyntax(node) Then
			Local terminator:TBlockTerminatorSyntax = TBlockTerminatorSyntax(node)
			result :+ " " + terminator.actualBlockKind + "~n"
		Else
			result :+ "~n"
		End If
		Return result
	End Method

	Function TokensText:String(tokens:TSyntaxToken[])
		Local result:String
		For Local token:TSyntaxToken = EachIn tokens
			result :+ token.text
		Next
		Return result
	End Function
End Type
