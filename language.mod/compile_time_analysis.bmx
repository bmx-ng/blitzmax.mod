' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map

Import "conditional_evaluator.bmx"
Import "constant_evaluation.bmx"
Import "conversion_classification.bmx"
Import "semantic_model.bmx"

' Validates contexts which require compile-time values and opportunistically
' annotates contexts, such as Select Case, which may also be dynamic.
Type TCompileTimeAnalyzer
	Field model:TSemanticModel
	Field diagnostics:TList = New TList
	Field evaluatedStaticArrays:TMap = New TMap

	Function Analyze:TSemanticModel(model:TSemanticModel)
		If model.compileTimeAnalyzed Then Return model
		TConstantEvaluator.Evaluate(model)
		Local analyzer:TCompileTimeAnalyzer = New TCompileTimeAnalyzer
		analyzer.model = model
		analyzer.ValidateEnumConstantCasts()
		analyzer.EvaluateStaticArrays(model.globalScope)
		analyzer.EvaluateRoutineDefaults(model.globalScope)
		Local document:TSourceDocumentModel
		If model.snapshot Then document = model.snapshot.rootDocument
		analyzer.VisitSequence(model.syntaxTree.root.members, document)
		model.compileTimeAnalyzed = True
		model.diagnostics = MergeCompileTimeDiagnostics(model.diagnostics, CompileTimeDiagnosticsToArray(analyzer.diagnostics))
		Return model
	End Function

	Method ValidateEnumConstantCasts()
		For Local expression:TExpressionSyntax = EachIn model.expressionTypeMap.Keys()
			Local operand:TExpressionSyntax
			Local target:TSemanticType
			Local namedCast:TCallExpressionSyntax = TCallExpressionSyntax(expression)
			If namedCast And model.NamedCastTarget(namedCast) And namedCast.arguments.length = 1 Then
				operand = namedCast.arguments[0]
				target = model.NamedCastTarget(namedCast)
			End If
			Local cast:TCastExpressionSyntax = TCastExpressionSyntax(expression)
			If cast Then
				operand = cast.expression
				target = model.ExpressionType(cast)
			End If
			If Not operand Or Not TConversionClassifier.IsEnum(target) Or Not TConversionClassifier.IsIntegral(model.ExpressionType(operand)) Then Continue
			Local constant:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(model, operand)
			If Not constant Or constant.kind <> CONSTANT_VALUE_INTEGER Then Continue
			If Not EnumAcceptsConstant(target, constant.integerValue) Then
				AddDiagnostic("BMX3630", "The value " + constant.integerValue + " is not valid for Enum '" + target.DisplayName() + "'.", expression.span)
			End If
		Next
	End Method

	Method EnumAcceptsConstant:Int(enumType:TSemanticType, value:Long)
		Local named:TNamedSemanticType = TNamedSemanticType(enumType)
		If Not named Or Not named.symbol Or Not named.symbol.memberScope Then Return False
		Local flags:Int
		Local declaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(named.symbol.declaration)
		If declaration Then flags = declaration.flagsToken <> Null
		If named.symbol.interfaceRecord Then flags = named.symbol.interfaceRecord.flags.Contains("F")
		Local mask:Long
		Local foundZero:Int
		For Local member:TSymbol = EachIn named.symbol.memberScope.declaredSymbols
			If Not member Or member.kind <> SYMBOL_ENUM_MEMBER Then Continue
			Local constant:TConstantValue = model.SymbolConstantValue(member)
			If Not constant Or constant.kind <> CONSTANT_VALUE_INTEGER Then Continue
			If constant.integerValue = value Then Return True
			If constant.integerValue = 0 Then foundZero = True
			mask :| constant.integerValue
		Next
		If Not flags Then Return False
		If value = 0 Then Return foundZero
		Return (value & ~mask) = 0
	End Method

	Method EvaluateStaticArrays(scope:TScope)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			EvaluateStaticArraysInType(symbol.declaredType, symbol)
		Next
		For Local child:TScope = EachIn scope.children
			EvaluateStaticArrays(child)
		Next
	End Method

	Method EvaluateStaticArraysInType(semanticType:TSemanticType, symbol:TSymbol)
		If Not semanticType Then Return
		Local staticType:TStaticArraySemanticType = TStaticArraySemanticType(semanticType)
		If staticType Then
			If evaluatedStaticArrays.Contains(staticType) Then Return
			evaluatedStaticArrays.Insert(staticType, staticType)
			If Not SupportedStaticElement(staticType.elementType) Then
				AddDiagnostic("BMX3621", "StaticArray element type '" + staticType.elementType.DisplayName() + "' must be numeric, an Enum, a Pointer, a managed reference, or a Struct.", SymbolSpan(symbol), symbol.originPath)
			End If
			If Not staticType.boundSyntax Or Not staticType.boundSyntax.lengthExpression Then Return
			Local lengthValue:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(model, staticType.boundSyntax.lengthExpression)
			If Not lengthValue Or lengthValue.kind <> CONSTANT_VALUE_INTEGER Then
				AddDiagnostic("BMX3620", "StaticArray length must be an integral constant.", staticType.boundSyntax.span, symbol.originPath)
			Else If lengthValue.integerValue <= 0 Or lengthValue.integerValue > 2147483647:Long Then
				AddDiagnostic("BMX3620", "StaticArray length must be between 1 and 2147483647.", staticType.boundSyntax.span, symbol.originPath)
			Else
				staticType.length = lengthValue.integerValue
			End If
			Return
		End If
		Local callableType:TCallableSemanticType = TCallableSemanticType(semanticType)
		If callableType Then
			EvaluateStaticArraysInType(callableType.returnType, symbol)
			For Local parameterType:TSemanticType = EachIn callableType.parameterTypes
				EvaluateStaticArraysInType(parameterType, symbol)
			Next
			Return
		End If
		Local arrayType:TArraySemanticType = TArraySemanticType(semanticType)
		If arrayType Then EvaluateStaticArraysInType(arrayType.elementType, symbol)
	End Method

	Function SupportedStaticElement:Int(value:TSemanticType)
		' Generic templates validate the closed element ABI during specialization.
		' Rejecting the type parameter here prevents otherwise valid StaticArray
		' storage such as T[4] from ever reaching that closed validation.
		If TTypeParameterSemanticType(value) Then Return True
		If TPointerSemanticType(value) Or TConversionClassifier.IsEnum(value) Then Return True
		Local arrayType:TArraySemanticType = TArraySemanticType(value)
		If arrayType Then Return True
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(value)
		If builtin Then
			Select builtin.name.ToLower()
				Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "float", "double", "float64", "float128", "double128", "int128", "wparam", "lparam", "string", "object" Return True
			End Select
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(value)
		Return named And named.symbol And (named.symbol.kind = SYMBOL_STRUCT Or named.symbol.kind = SYMBOL_TYPE Or named.symbol.kind = SYMBOL_INTERFACE)
	End Function

	Function SymbolSpan:TSourceSpan(symbol:TSymbol)
		If symbol.nameToken Then Return symbol.nameToken.span
		If symbol.declaration Then Return symbol.declaration.span
		Return TSourceSpan.Create(0, 0)
	End Function

	Method EvaluateRoutineDefaults(scope:TScope)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol.kind <> SYMBOL_ROUTINE Then Continue
			Local signature:TRoutineSignatureSyntax
			If symbol.isImported And symbol.interfaceRecord Then
				signature = symbol.interfaceRecord.routineSignature
			Else
				Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
				If declaration Then signature = declaration.signature
			End If
			If Not signature Then Continue
			For Local index:Int = 0 Until signature.parameters.length
				Local parameter:TParameterSyntax = signature.parameters[index]
				If Not parameter.defaultValue Then Continue
				If Not RoutineParameterIdentityIsValid(symbol, parameter, index) Then Continue
				Local value:TConstantValue = TConstantEvaluator.EvaluateExpressionValue(model, parameter.defaultValue, symbol.originPath)
				If index < symbol.parameters.length And TCallableSemanticType(symbol.parameters[index].semanticType) Then
					Local callableValue:TConstantValue = CallableDefaultValue(parameter.defaultValue, symbol.parameters[index].semanticType, symbol, value)
					If callableValue Then value = callableValue
				End If
				If Not value Then
					AddDiagnostic("BMX3610", "Default value for parameter '" + parameter.nameToken.text + "' must be constant.", parameter.defaultValue.span, symbol.originPath)
					Continue
				End If
				If index < symbol.parameters.length Then
					If value.kind = CONSTANT_VALUE_CALLABLE Then
						symbol.parameters[index].defaultValue = value
						Continue
					End If
					Local converted:TConstantValue = TConstantEvaluator.ConvertValue(model, value, symbol.parameters[index].semanticType, parameter.defaultValue.span, symbol.originPath)
					If converted Then
						symbol.parameters[index].defaultValue = converted
					Else
						AddDiagnostic("BMX3611", "Constant default for parameter '" + parameter.nameToken.text + "' is incompatible with '" + symbol.parameters[index].semanticType.DisplayName() + "' in routine '" + symbol.name + "' at parameter " + index + " (declared type '" + ParameterTypeText(parameter) + "').", parameter.defaultValue.span, symbol.originPath)
					End If
				End If
			Next
		Next
		For Local child:TScope = EachIn scope.children
			EvaluateRoutineDefaults(child)
		Next
	End Method

	Method RoutineParameterIdentityIsValid:Int(symbol:TSymbol, parameter:TParameterSyntax, index:Int)
		If index >= symbol.parameters.length Or Not symbol.parameters[index] Then
			AddDiagnostic("BMX3690", "Internal semantic parameter mismatch in routine '" + symbol.name + "': syntax parameter " + index + " ('" + parameter.nameToken.text + "') has no semantic parameter.", parameter.span, symbol.originPath)
			Return False
		End If
		Local semanticParameter:TSemanticParameter = symbol.parameters[index]
		If Not semanticParameter.symbol Or semanticParameter.symbol.declaration <> parameter Or semanticParameter.symbol.name.ToLower() <> parameter.nameToken.text.ToLower() Then
			Local semanticName:String = "<missing>"
			Local semanticTypeName:String = "<missing>"
			If semanticParameter.symbol Then semanticName = semanticParameter.symbol.name
			If semanticParameter.semanticType Then semanticTypeName = semanticParameter.semanticType.DisplayName()
			AddDiagnostic("BMX3690", "Internal semantic parameter mismatch in routine '" + symbol.name + "' at parameter " + index + ": syntax '" + parameter.nameToken.text + "' (declared type '" + ParameterTypeText(parameter) + "'), semantic symbol '" + semanticName + "' (type '" + semanticTypeName + "').", parameter.span, symbol.originPath)
			Return False
		End If
		Return True
	End Method

	Function ParameterTypeText:String(parameter:TParameterSyntax)
		If Not parameter Then Return "<missing>"
		If parameter.callableType Then Return "Closure"
		If Not parameter.declaredType Then Return "<implicit Int>"
		Local result:String
		For Local token:TSyntaxToken = EachIn parameter.declaredType.tokens
			result :+ token.text
		Next
		If Not result.length Then Return "<empty>"
		Return result
	End Function

	Method CallableDefaultValue:TConstantValue(expression:TExpressionSyntax, required:TSemanticType, owner:TSymbol = Null, encodedValue:TConstantValue = Null)
		If Not TCallableSemanticType(required) Then Return Null
		Local routine:TSymbol
		Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
		If name Then routine = model.ReferencedSymbol(name)
		Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
		If member Then routine = model.ReferencedSymbol(member)
		Local actual:TSemanticType
		If Not routine And owner And owner.isImported And encodedValue And encodedValue.kind = CONSTANT_VALUE_STRING Then
			Local moduleScope:TScope = owner.containingScope
			While moduleScope And moduleScope.kind <> SCOPE_INTERFACE_MODULE
				moduleScope = moduleScope.parent
			Wend
			routine = ImportedRoutineByExternalName(moduleScope, encodedValue.stringValue)
			If routine Then actual = CallableTypeOf(routine)
		End If
		If Not routine Or routine.kind <> SYMBOL_ROUTINE Or IsInstanceMethod(routine) Then Return Null
		If Not actual Then actual = model.ExpressionType(expression)
		If Not TCallableSemanticType(actual) Then Return Null
		If Not TConversionClassifier.Create(model).Classify(actual, required).Exists() Then Return Null
		Local result:TConstantValue = New TConstantValue
		result.kind = CONSTANT_VALUE_CALLABLE
		result.semanticType = required
		result.callableSymbol = routine
		model.constantExpressionMap.Insert(expression, result)
		Return result
	End Method

	Method ImportedRoutineByExternalName:TSymbol(scope:TScope, externalName:String)
		If Not scope Or Not externalName.length Then Return Null
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol.kind = SYMBOL_ROUTINE And symbol.externalName = externalName Then Return symbol
		Next
		For Local child:TScope = EachIn scope.children
			Local found:TSymbol = ImportedRoutineByExternalName(child, externalName)
			If found Then Return found
		Next
		Return Null
	End Method

	Function CallableTypeOf:TCallableSemanticType(routine:TSymbol)
		If Not routine Then Return Null
		Local result:TCallableSemanticType = New TCallableSemanticType
		result.kind = SEMANTIC_TYPE_CALLABLE
		result.routine = routine
		result.callingConvention = routine.callingConvention
		result.parameterTypes = routine.parameterTypes
		result.parameterModes = New Int[routine.parameters.length]
		For Local index:Int = 0 Until routine.parameters.length
			result.parameterModes[index] = routine.parameters[index].passingMode
		Next
		result.returnType = routine.declaredType
		Return result
	End Function

	Function IsInstanceMethod:Int(routine:TSymbol)
		If routine.interfaceRecord Then Return routine.interfaceRecord.kind = INTERFACE_RECORD_METHOD
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(routine.declaration)
		Return declaration And declaration.isMethod
	End Function

	Method VisitSequence(nodes:TSyntaxNode[], document:TSourceDocumentModel)
		For Local node:TSyntaxNode = EachIn nodes
			VisitNode(node, document)
		Next
	End Method

	Method VisitNode(node:TSyntaxNode, document:TSourceDocumentModel)
		If Not node Then Return
		Local includeSyntax:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
		If includeSyntax And document Then
			Local included:TSourceDocumentModel = IncludedDocument(document, includeSyntax)
			If included Then VisitSequence(included.tree.root.members, included)
			Return
		End If
		Local selectStatement:TSelectStatementSyntax = TSelectStatementSyntax(node)
		If selectStatement Then
			Local boundSelect:TBoundSelectStatement = TBoundSelectStatement(model.BoundStatement(selectStatement))
			Local boundIndex:Int
			For Local clause:TCaseClauseSyntax = EachIn selectStatement.cases
				If model.snapshot And Not TConditionalEvaluator.IsActive(clause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then Continue
				If boundSelect And boundIndex < boundSelect.cases.length Then
					boundSelect.cases[boundIndex].constantValues = New TConstantValue[clause.values.length]
					For Local valueIndex:Int = 0 Until clause.values.length
						boundSelect.cases[boundIndex].constantValues[valueIndex] = TConstantEvaluator.EvaluateExpressionValue(model, clause.values[valueIndex])
					Next
				End If
				VisitSequence(clause.body.statements, document)
				boundIndex :+ 1
			Next
			For Local defaultClause:TDefaultClauseSyntax = EachIn selectStatement.defaultClauses
				If Not model.snapshot Or TConditionalEvaluator.IsActive(defaultClause.conditionalExpression, model.snapshot.options.conditionalSymbols) Then VisitSequence(defaultClause.body.statements, document)
			Next
			Return
		End If

		Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
		If typeDeclaration Then VisitSequence(typeDeclaration.body.statements, document); Return
		Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
		If routine Then VisitSequence(routine.body.statements, document); Return
		Local external:TExternBlockSyntax = TExternBlockSyntax(node)
		If external Then VisitSequence(external.body.statements, document); Return
		Local block:TBlockSyntax = TBlockSyntax(node)
		If block Then VisitSequence(block.statements, document); Return

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

		Local ifStatement:TIfStatementSyntax = TIfStatementSyntax(node)
		If ifStatement Then
			VisitSequence(ifStatement.thenBlock.statements, document)
			For Local clause:TElseIfClauseSyntax = EachIn ifStatement.elseIfClauses
				VisitSequence(clause.block.statements, document)
			Next
			If ifStatement.elseClause Then VisitSequence(ifStatement.elseClause.block.statements, document)
			Return
		End If
		Local whileStatement:TWhileStatementSyntax = TWhileStatementSyntax(node)
		If whileStatement Then VisitSequence(whileStatement.body.statements, document); Return
		Local repeatStatement:TRepeatStatementSyntax = TRepeatStatementSyntax(node)
		If repeatStatement Then VisitSequence(repeatStatement.body.statements, document); Return
		Local forStatement:TForStatementSyntax = TForStatementSyntax(node)
		If forStatement Then VisitSequence(forStatement.body.statements, document); Return
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

	Method IncludedDocument:TSourceDocumentModel(document:TSourceDocumentModel, syntax:TIncludeDirectiveSyntax)
		For Local edge:TIncludeEdge = EachIn document.includes
			If edge.syntax = syntax Then Return edge.target
		Next
		Return Null
	End Method

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan, path:String = "")
		If Not path.length Then
			If model.snapshot And model.snapshot.rootDocument Then path = model.snapshot.rootDocument.path Else If model.syntaxTree Then path = model.syntaxTree.source.path
		End If
		diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span, path))
	End Method
End Type

Function CompileTimeDiagnosticsToArray:TDiagnostic[](list:TList)
	Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
	Local index:Int
	For Local diagnostic:TDiagnostic = EachIn list
		result[index] = diagnostic
		index :+ 1
	Next
	Return result
End Function

Function MergeCompileTimeDiagnostics:TDiagnostic[](first:TDiagnostic[], second:TDiagnostic[])
	Local result:TDiagnostic[] = New TDiagnostic[first.length + second.length]
	For Local index:Int = 0 Until first.length
		result[index] = first[index]
	Next
	For Local index:Int = 0 Until second.length
		result[first.length + index] = second[index]
	Next
	Return result
End Function
