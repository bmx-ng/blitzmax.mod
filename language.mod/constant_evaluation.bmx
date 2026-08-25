' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map
Import BRL.StringBuilder

Import "semantic_model.bmx"

' Evaluates the source-level constants that are useful to every later client:
' Const declarations, enum members, case/data values and compile-time tools.
Type TConstantEvaluator
	Field model:TSemanticModel
	Field visiting:TMap = New TMap
	Field failed:TMap = New TMap
	Field diagnostics:TList = New TList
	Field currentPath:String

	Function Evaluate:TSemanticModel(model:TSemanticModel)
		If model.constantsEvaluated Then Return model
		Local evaluator:TConstantEvaluator = New TConstantEvaluator
		evaluator.model = model
		evaluator.EvaluateScope(model.globalScope)
		model.constantsEvaluated = True
		model.diagnostics = MergeConstantDiagnostics(model.diagnostics, ConstantDiagnosticsToArray(evaluator.diagnostics))
		Return model
	End Function

	Function EvaluateExpressionValue:TConstantValue(model:TSemanticModel, expression:TExpressionSyntax, path:String = "")
		Local existing:TConstantValue = model.ConstantValue(expression)
		If existing Then Return existing
		Local evaluator:TConstantEvaluator = New TConstantEvaluator
		evaluator.model = model
		evaluator.currentPath = path
		If Not evaluator.currentPath.length And model.syntaxTree Then evaluator.currentPath = model.syntaxTree.source.path
		Local result:TConstantValue = evaluator.EvaluateExpression(expression)
		model.diagnostics = MergeConstantDiagnostics(model.diagnostics, ConstantDiagnosticsToArray(evaluator.diagnostics))
		Return result
	End Function

	Function ConvertValue:TConstantValue(model:TSemanticModel, value:TConstantValue, target:TSemanticType, span:TSourceSpan, path:String = "")
		Local evaluator:TConstantEvaluator = New TConstantEvaluator
		evaluator.model = model
		evaluator.currentPath = path
		If Not evaluator.currentPath.length And model.syntaxTree Then evaluator.currentPath = model.syntaxTree.source.path
		Local result:TConstantValue = evaluator.Convert(value, target, span)
		model.diagnostics = MergeConstantDiagnostics(model.diagnostics, ConstantDiagnosticsToArray(evaluator.diagnostics))
		Return result
	End Function

	Method EvaluateRequired:TConstantValue(expression:TExpressionSyntax)
		Return EvaluateExpression(expression)
	End Method

	Method EvaluateScope(scope:TScope)
		If Not scope Then Return
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If symbol.kind = SYMBOL_CONST Or symbol.kind = SYMBOL_ENUM_MEMBER Then EvaluateSymbol(symbol)
		Next
		For Local child:TScope = EachIn scope.children
			EvaluateScope(child)
		Next
	End Method

	Method EvaluateSymbol:TConstantValue(symbol:TSymbol)
		Local previousPath:String = currentPath
		currentPath = symbol.originPath
		Local result:TConstantValue = EvaluateSymbolWithOrigin(symbol)
		currentPath = previousPath
		Return result
	End Method

	Method EvaluateSymbolWithOrigin:TConstantValue(symbol:TSymbol)
		Local existing:TConstantValue = model.SymbolConstantValue(symbol)
		If existing Then Return existing
		If failed.Contains(symbol) Then Return Null
		If visiting.Contains(symbol) Then
			AddDiagnostic("BMX3600", "Constant definition cycle involving '" + symbol.name + "'.", SymbolSpan(symbol))
			failed.Insert(symbol, symbol)
			Return Null
		End If
		visiting.Insert(symbol, symbol)
		Local result:TConstantValue
		If symbol.kind = SYMBOL_CONST Then
			If symbol.isImported And symbol.interfaceRecord Then
				result = EvaluateExpression(symbol.interfaceRecord.valueSyntax)
			Else
				Local declarator:TVariableDeclaratorSyntax = TVariableDeclaratorSyntax(symbol.declaration)
				If declarator And declarator.initializer Then result = EvaluateExpression(declarator.initializer)
			End If
			If result And symbol.declaredType Then result = Convert(result, symbol.declaredType, SymbolSpan(symbol))
			If Not result And Not failed.Contains(symbol) Then AddDiagnostic("BMX3601", "Const '" + symbol.name + "' requires a constant initializer.", SymbolSpan(symbol))
		Else If symbol.kind = SYMBOL_ENUM_MEMBER Then
			result = EvaluateEnumMember(symbol)
		End If
		visiting.Remove(symbol)
		If result Then
			model.constantSymbolMap.Insert(symbol, result)
		Else
			failed.Insert(symbol, symbol)
		End If
		Return result
	End Method

	Method EvaluateEnumMember:TConstantValue(symbol:TSymbol)
		If Not symbol.containingScope Or Not symbol.containingScope.owner Then Return Null
		Local enumSymbol:TSymbol = symbol.containingScope.owner
		If symbol.isImported And symbol.interfaceRecord Then
			Local importedValue:TConstantValue = EvaluateExpression(symbol.interfaceRecord.valueSyntax)
			If importedValue And importedValue.kind = CONSTANT_VALUE_INTEGER Then
				Local importedUnderlying:TSemanticType = model.BuiltinType("Int")
				If enumSymbol.interfaceRecord And enumSymbol.interfaceRecord.baseTypeSyntax Then importedUnderlying = model.TypeOf(enumSymbol.interfaceRecord.baseTypeSyntax)
				If importedUnderlying And FitsIntegral(importedValue.integerValue, importedUnderlying) Then
					importedValue.semanticType = enumSymbol.declaredType
					Return importedValue
				End If
			End If
			AddDiagnostic("BMX3602", "Imported enum value '" + symbol.name + "' has no usable integral constant.", SymbolSpan(symbol))
			Return Null
		End If
		Local declaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(enumSymbol.declaration)
		Local valueSyntax:TEnumValueSyntax = TEnumValueSyntax(symbol.declaration)
		If Not declaration Or Not valueSyntax Then Return Null
		Local index:Int = EnumValueIndex(declaration, valueSyntax)
		Local result:TConstantValue
		If valueSyntax.value Then
			result = EvaluateExpression(valueSyntax.value)
		Else If index = 0 Then
			If declaration.flagsToken Then
				result = IntegerValue(1, enumSymbol.declaredType)
			Else
				result = IntegerValue(0, enumSymbol.declaredType)
			End If
		Else
			Local previousSymbol:TSymbol = model.DeclaredSymbol(declaration.values[index - 1])
			Local previous:TConstantValue = EvaluateSymbol(previousSymbol)
			If previous And previous.kind = CONSTANT_VALUE_INTEGER Then
				Local nextValue:Long = previous.integerValue + 1
				If declaration.flagsToken Then nextValue = NextFlagValue(previous.integerValue)
				If nextValue >= 0 Then result = IntegerValue(nextValue, enumSymbol.declaredType)
			End If
		End If
		If result And result.kind <> CONSTANT_VALUE_INTEGER Then result = Null
		If result Then
			Local underlying:TSemanticType = model.BuiltinType("Int")
			If declaration.underlyingType Then underlying = model.TypeOf(declaration.underlyingType)
			If Not FitsIntegral(result.integerValue, underlying) Then
				AddDiagnostic("BMX3603", "Enum value '" + symbol.name + "' is outside the range of '" + underlying.DisplayName() + "'.", valueSyntax.span)
				result = Null
			Else
				result.semanticType = enumSymbol.declaredType
			End If
		Else If Not failed.Contains(symbol) Then
			AddDiagnostic("BMX3602", "Enum value '" + symbol.name + "' requires an integral constant expression.", valueSyntax.span)
		End If
		If result And valueSyntax.value Then model.constantExpressionMap.Insert(valueSyntax.value, result)
		Return result
	End Method

	Method EvaluateExpression:TConstantValue(expression:TExpressionSyntax)
		If Not expression Then Return Null
		Local existing:TConstantValue = model.ConstantValue(expression)
		If existing Then Return existing
		Local result:TConstantValue
		Local literal:TLiteralExpressionSyntax = TLiteralExpressionSyntax(expression)
		If literal Then
			result = EvaluateLiteral(literal)
		Else
			Local name:TNameExpressionSyntax = TNameExpressionSyntax(expression)
			If name Then
				Local symbol:TSymbol = model.ReferencedSymbol(name)
				If symbol And (symbol.kind = SYMBOL_CONST Or symbol.kind = SYMBOL_ENUM_MEMBER) Then result = EvaluateSymbol(symbol)
			Else
				Local member:TMemberAccessExpressionSyntax = TMemberAccessExpressionSyntax(expression)
				If member Then
					Local memberSymbol:TSymbol = model.ReferencedSymbol(member)
					If memberSymbol And (memberSymbol.kind = SYMBOL_CONST Or memberSymbol.kind = SYMBOL_ENUM_MEMBER) Then result = EvaluateSymbol(memberSymbol)
					If Not result And member.nameToken And member.nameToken.text.ToLower() = "length" Then
						Local staticArrayType:TStaticArraySemanticType = TStaticArraySemanticType(model.ExpressionType(member.expression))
						If staticArrayType Then
							Local lengthValue:Long = staticArrayType.length
							If lengthValue <= 0 And staticArrayType.boundSyntax And staticArrayType.boundSyntax.lengthExpression Then
								Local boundValue:TConstantValue = EvaluateExpression(staticArrayType.boundSyntax.lengthExpression)
								If boundValue And boundValue.kind = CONSTANT_VALUE_INTEGER Then lengthValue = boundValue.integerValue
							End If
							If lengthValue > 0 Then result = IntegerValue(lengthValue, model.BuiltinType("Int"))
						End If
					End If
				End If
				Local parentheses:TParenthesizedExpressionSyntax = TParenthesizedExpressionSyntax(expression)
				If parentheses Then result = EvaluateExpression(parentheses.expression)
				Local ascription:TTypeAscriptionExpressionSyntax = TTypeAscriptionExpressionSyntax(expression)
				If ascription Then result = Convert(EvaluateExpression(ascription.expression), TypeOfSyntax(ascription.targetType), expression.span)
				Local cast:TCastExpressionSyntax = TCastExpressionSyntax(expression)
				If cast Then result = Convert(EvaluateExpression(cast.expression), TypeOfSyntax(cast.targetType), expression.span)
				Local call:TCallExpressionSyntax = TCallExpressionSyntax(expression)
				If call And model.NamedCastTarget(call) And call.arguments.length = 1 Then
					result = Convert(EvaluateExpression(call.arguments[0]), model.NamedCastTarget(call), expression.span)
				End If
				Local unary:TUnaryExpressionSyntax = TUnaryExpressionSyntax(expression)
				If unary Then result = EvaluateUnary(unary)
				Local binary:TBinaryExpressionSyntax = TBinaryExpressionSyntax(expression)
				If binary Then result = EvaluateBinary(binary)
			End If
		End If
		If result Then
			If Not result.semanticType Then result.semanticType = model.ExpressionType(expression)
			model.constantExpressionMap.Insert(expression, result)
		End If
		Return result
	End Method

	Method EvaluateLiteral:TConstantValue(literal:TLiteralExpressionSyntax)
		Local token:TSyntaxToken = literal.literalToken
		Select token.kind
			Case TOKEN_INTEGER_LITERAL
				Local value:Long
				If TryParseInteger(token.text, value) Then
					Local semanticType:TSemanticType = model.ExpressionType(literal)
					Local result:TConstantValue = IntegerValue(value, semanticType)
					result.isRadixLiteral = token.text.length > 1 And (token.text[0] = 36 Or token.text[0] = 37)
					Return result
				End If
			Case TOKEN_FLOAT_LITERAL
				Return FloatValue(token.text.ToDouble(), model.ExpressionType(literal))
			Case TOKEN_STRING_LITERAL
				Return StringValue(DecodeString(token.text, False), model.ExpressionType(literal))
			Case TOKEN_MULTILINE_STRING_LITERAL
				Return StringValue(DecodeString(token.text, True), model.ExpressionType(literal))
		End Select
		Select token.text.ToLower()
			Case "true" Return IntegerValue(1, model.BuiltinType("Int"))
			Case "false" Return IntegerValue(0, model.BuiltinType("Int"))
			Case "pi" Return FloatValue(Pi, model.BuiltinType("Double"))
			Case "null"
				Local result:TConstantValue = New TConstantValue
				result.kind = CONSTANT_VALUE_NULL
				result.semanticType = model.BuiltinType("Null")
				Return result
		End Select
		Return Null
	End Method

	Method EvaluateUnary:TConstantValue(syntax:TUnaryExpressionSyntax)
		Local operand:TConstantValue = EvaluateExpression(syntax.operand)
		If Not operand Then Return Null
		NormalizeRadixOperand(operand)
		Local operation:String = syntax.operatorToken.text.ToLower()
		If operation = "len" Then
			If operand.kind = CONSTANT_VALUE_STRING Then Return IntegerValue(operand.stringValue.length, model.BuiltinType("Int"))
			Return IntegerValue(1, model.BuiltinType("Int"))
		End If
		If operation = "asc" Then
			Local text:String = ConstantText(operand)
			If Not text.length Then Return IntegerValue(-1, model.BuiltinType("Int"))
			Return IntegerValue(text[0], model.BuiltinType("Int"))
		End If
		If operation = "chr" Then
			Local code:Int
			Select operand.kind
				Case CONSTANT_VALUE_INTEGER code = Int(operand.integerValue)
				Case CONSTANT_VALUE_FLOAT code = Int(operand.floatValue)
				Case CONSTANT_VALUE_STRING code = operand.stringValue.ToInt()
				Default Return Null
			End Select
			Return StringValue(Chr(code), model.BuiltinType("String"))
		End If
		If operand.kind = CONSTANT_VALUE_INTEGER Then
			Select operation
				Case "+" Return IntegerOperationValue(operand.integerValue, model.ExpressionType(syntax))
				Case "-" Return IntegerOperationValue(-operand.integerValue, model.ExpressionType(syntax))
				Case "not" Return IntegerValue(operand.integerValue = 0, model.ExpressionType(syntax))
				Case "~~" Return IntegerOperationValue(~operand.integerValue, model.ExpressionType(syntax))
			End Select
		Else If operand.kind = CONSTANT_VALUE_FLOAT Then
			Select operation
				Case "+" Return FloatValue(operand.floatValue, model.ExpressionType(syntax))
				Case "-" Return FloatValue(-operand.floatValue, model.ExpressionType(syntax))
				Case "not" Return IntegerValue(operand.floatValue = 0.0, model.BuiltinType("Int"))
			End Select
		End If
		Return Null
	End Method

	Method EvaluateBinary:TConstantValue(syntax:TBinaryExpressionSyntax)
		Local left:TConstantValue = EvaluateExpression(syntax.left)
		Local right:TConstantValue = EvaluateExpression(syntax.right)
		If Not left Or Not right Then Return Null
		NormalizeRadixOperand(left)
		NormalizeRadixOperand(right)
		Local operation:String = syntax.operatorToken.text.ToLower()
		If operation = "+" And (left.kind = CONSTANT_VALUE_STRING Or right.kind = CONSTANT_VALUE_STRING) Then
			Return StringValue(ConstantText(left) + ConstantText(right), model.ExpressionType(syntax))
		End If
		If left.kind = CONSTANT_VALUE_STRING And right.kind = CONSTANT_VALUE_STRING Then
			Select operation
				Case "=" Return IntegerValue(left.stringValue = right.stringValue, model.BuiltinType("Int"))
				Case "<>" Return IntegerValue(left.stringValue <> right.stringValue, model.BuiltinType("Int"))
				Case "<" Return IntegerValue(left.stringValue < right.stringValue, model.BuiltinType("Int"))
				Case ">" Return IntegerValue(left.stringValue > right.stringValue, model.BuiltinType("Int"))
				Case "<=" Return IntegerValue(left.stringValue <= right.stringValue, model.BuiltinType("Int"))
				Case ">=" Return IntegerValue(left.stringValue >= right.stringValue, model.BuiltinType("Int"))
			End Select
		End If
		If IsNumeric(left) And IsNumeric(right) Then
			If left.kind = CONSTANT_VALUE_FLOAT Or right.kind = CONSTANT_VALUE_FLOAT Then Return EvaluateFloatBinary(syntax, AsDouble(left), AsDouble(right), operation)
			Return EvaluateIntegerBinary(syntax, left.integerValue, right.integerValue, operation)
		End If
		Return Null
	End Method

	Method EvaluateIntegerBinary:TConstantValue(syntax:TBinaryExpressionSyntax, left:Long, right:Long, operation:String)
		Local resultType:TSemanticType = model.ExpressionType(syntax)
		Select operation
			Case "+" Return IntegerOperationValue(left + right, resultType)
			Case "-" Return IntegerOperationValue(left - right, resultType)
			Case "*" Return IntegerOperationValue(left * right, resultType)
			Case "/", "mod"
				If right = 0 Then
					AddDiagnostic("BMX3604", "Division by zero in constant expression.", syntax.span)
					Return Null
				End If
				If operation = "/" Then Return IntegerOperationValue(left / right, resultType)
				Return IntegerOperationValue(left Mod right, resultType)
			Case "shl" Return IntegerOperationValue(left Shl Int(right), resultType)
			Case "shr" Return IntegerOperationValue(left Shr Int(right), resultType)
			Case "sar" Return IntegerOperationValue(left Sar Int(right), resultType)
			Case "&" Return IntegerOperationValue(left & right, resultType)
			Case "|" Return IntegerOperationValue(left | right, resultType)
			Case "~~" Return IntegerOperationValue(left ~ right, resultType)
			Case "and" Return IntegerValue(left <> 0 And right <> 0, model.BuiltinType("Int"))
			Case "or" Return IntegerValue(left <> 0 Or right <> 0, model.BuiltinType("Int"))
			Case "=" Return IntegerValue(left = right, model.BuiltinType("Int"))
			Case "<>" Return IntegerValue(left <> right, model.BuiltinType("Int"))
			Case "<" Return IntegerValue(left < right, model.BuiltinType("Int"))
			Case ">" Return IntegerValue(left > right, model.BuiltinType("Int"))
			Case "<=" Return IntegerValue(left <= right, model.BuiltinType("Int"))
			Case ">=" Return IntegerValue(left >= right, model.BuiltinType("Int"))
			Case "^" Return IntegerOperationValue(Long(Double(left) ^ Double(right)), resultType)
		End Select
		Return Null
	End Method

	Method EvaluateFloatBinary:TConstantValue(syntax:TBinaryExpressionSyntax, left:Double, right:Double, operation:String)
		Select operation
			Case "+" Return FloatValue(left + right, model.ExpressionType(syntax))
			Case "-" Return FloatValue(left - right, model.ExpressionType(syntax))
			Case "*" Return FloatValue(left * right, model.ExpressionType(syntax))
			Case "/"
				If right = 0.0 Then
					AddDiagnostic("BMX3604", "Division by zero in constant expression.", syntax.span)
					Return Null
				End If
				Return FloatValue(left / right, model.ExpressionType(syntax))
			Case "^" Return FloatValue(left ^ right, model.ExpressionType(syntax))
			Case "and" Return IntegerValue(left <> 0.0 And right <> 0.0, model.BuiltinType("Int"))
			Case "or" Return IntegerValue(left <> 0.0 Or right <> 0.0, model.BuiltinType("Int"))
			Case "=" Return IntegerValue(left = right, model.BuiltinType("Int"))
			Case "<>" Return IntegerValue(left <> right, model.BuiltinType("Int"))
			Case "<" Return IntegerValue(left < right, model.BuiltinType("Int"))
			Case ">" Return IntegerValue(left > right, model.BuiltinType("Int"))
			Case "<=" Return IntegerValue(left <= right, model.BuiltinType("Int"))
			Case ">=" Return IntegerValue(left >= right, model.BuiltinType("Int"))
		End Select
		Return Null
	End Method

	Method Convert:TConstantValue(value:TConstantValue, target:TSemanticType, span:TSourceSpan)
		If Not value Or Not target Then Return Null
		If value.kind = CONSTANT_VALUE_INTEGER And value.isRadixLiteral And IsIntegralType(target) Then
			Return IntegerValue(NormalizeRadixInteger(value.integerValue, target), target)
		End If
		If value.semanticType = target Then Return value
		If TPointerSemanticType(target) And value.kind = CONSTANT_VALUE_INTEGER And value.integerValue = 0 Then
			Return IntegerValue(0, target)
		End If
		If value.kind = CONSTANT_VALUE_NULL Then
			Local nullBuiltin:TBuiltinSemanticType = TBuiltinSemanticType(target)
			If nullBuiltin And nullBuiltin.name.ToLower() = "void" Then Return Null
			' Null is the constant spelling of the default value for every BlitzMax
			' value type, including primitives, enums, structs and references.
			Return value
		End If
		Local namedTarget:TNamedSemanticType = TNamedSemanticType(target)
		If namedTarget And namedTarget.symbol And namedTarget.symbol.kind = SYMBOL_ENUM And value.kind = CONSTANT_VALUE_INTEGER Then
			Local underlying:TSemanticType = EnumUnderlyingType(namedTarget.symbol)
			If underlying And Not FitsIntegral(value.integerValue, underlying) Then
				AddDiagnostic("BMX3603", "Constant value is outside the range of '" + target.DisplayName() + "'.", span)
				Return Null
			End If
			Return IntegerValue(value.integerValue, target)
		End If
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(target)
		If Not builtin Then Return Null
		Local name:String = builtin.name.ToLower()
		If name = "string" Then Return StringValue(ConstantText(value), target)
		If IsIntegralType(target) Then
			Local integer:Long
			If value.kind = CONSTANT_VALUE_INTEGER Then
				integer = value.integerValue
			Else If value.kind = CONSTANT_VALUE_FLOAT Then
				integer = Long(value.floatValue)
			Else
				Return Null
			End If
			If Not FitsIntegral(integer, target) Then
				AddDiagnostic("BMX3603", "Constant value is outside the range of '" + target.DisplayName() + "'.", span)
				Return Null
			End If
			Return IntegerValue(integer, target)
		End If
		If name = "float" Or name = "double" Or name = "float64" Or name = "float128" Or name = "double128" Then
			If IsNumeric(value) Then Return FloatValue(AsDouble(value), target)
		End If
		Return Null
	End Method

	Method EnumUnderlyingType:TSemanticType(symbol:TSymbol)
		If symbol.interfaceRecord And symbol.interfaceRecord.baseTypeSyntax Then Return model.TypeOf(symbol.interfaceRecord.baseTypeSyntax)
		Local declaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(symbol.declaration)
		If declaration And declaration.underlyingType Then Return model.TypeOf(declaration.underlyingType)
		Return model.BuiltinType("Int")
	End Method

	Function IntegerValue:TConstantValue(value:Long, semanticType:TSemanticType)
		Local result:TConstantValue = New TConstantValue
		result.kind = CONSTANT_VALUE_INTEGER
		result.integerValue = value
		result.semanticType = semanticType
		Return result
	End Function

	Function IntegerOperationValue:TConstantValue(value:Long, semanticType:TSemanticType)
		' BlitzMax integral operators execute in their bound result width. Preserve
		' that bit pattern while folding, so an Int sign-bit shift or overflow is
		' published as the corresponding signed Int rather than a wider positive
		' Long value that a later compact-interface consumer would reject.
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If builtin Then
			Select builtin.name.ToLower()
				Case "byte" value = Long(Byte(value))
				Case "short" value = Long(Short(value))
				Case "int" value = Long(Int(value))
				Case "uint" value = Long(UInt(value))
			End Select
		End If
		Return IntegerValue(value, semanticType)
	End Function

	Function FloatValue:TConstantValue(value:Double, semanticType:TSemanticType)
		Local result:TConstantValue = New TConstantValue
		result.kind = CONSTANT_VALUE_FLOAT
		result.floatValue = value
		result.semanticType = semanticType
		Return result
	End Function

	Function StringValue:TConstantValue(value:String, semanticType:TSemanticType)
		Local result:TConstantValue = New TConstantValue
		result.kind = CONSTANT_VALUE_STRING
		result.stringValue = value
		result.semanticType = semanticType
		Return result
	End Function

	Function IsNumeric:Int(value:TConstantValue)
		Return value And (value.kind = CONSTANT_VALUE_INTEGER Or value.kind = CONSTANT_VALUE_FLOAT)
	End Function

	Function AsDouble:Double(value:TConstantValue)
		If value.kind = CONSTANT_VALUE_FLOAT Then Return value.floatValue
		Return Double(value.integerValue)
	End Function

	Function ConstantText:String(value:TConstantValue)
		Select value.kind
			Case CONSTANT_VALUE_STRING Return value.stringValue
			Case CONSTANT_VALUE_INTEGER Return value.DisplayValue()
			Case CONSTANT_VALUE_FLOAT Return value.floatValue
			Case CONSTANT_VALUE_NULL Return "Null"
		End Select
		Return ""
	End Function

	Function IsIntegralType:Int(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte", "short", "int", "uint", "long", "ulong", "longint", "ulongint", "size_t", "wparam", "lparam" Return True
		End Select
		Return False
	End Function

	Method TypeOfSyntax:TSemanticType(syntax:TTypeReferenceSyntax)
		If Not syntax Then Return Null
		Local resolved:TSemanticType = model.TypeOf(syntax)
		If resolved Then Return resolved
		If syntax.markerToken Then
			Select syntax.markerToken.text
				Case "%" Return model.BuiltinType("Int")
				Case "%%" Return model.BuiltinType("UInt")
				Case "@" Return model.BuiltinType("Byte")
				Case "@@" Return model.BuiltinType("Short")
				Case "#" Return model.BuiltinType("Float")
				Case "!" Return model.BuiltinType("Double")
				Case "$" Return model.BuiltinType("String")
			End Select
		End If
		If syntax.nameTokens.length Then Return model.BuiltinType(syntax.nameTokens[0].text)
		Return Null
	End Method

	Function FitsIntegral:Int(value:Long, semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return False
		Select builtin.name.ToLower()
			Case "byte" Return value >= 0 And value <= 255
			Case "short" Return value >= 0 And value <= 65535
			Case "int" Return value >= -2147483648:Long And value <= 2147483647:Long
			Case "uint" Return value >= 0 And value <= 4294967295:Long
			' ULong and ULongInt use the complete 64-bit pattern held by Long.
			' Negative Long values therefore represent their upper unsigned half.
			Case "ulong", "ulongint" Return True
			Case "size_t", "wparam" Return value >= 0
			Case "long", "longint", "lparam" Return True
		End Select
		Return False
	End Function

	' Hexadecimal and binary literals denote bit patterns in their inferred
	' integral type.  Normalize that pattern before later constant conversions,
	' matching the production compiler without allowing decimal overflow.
	Function NormalizeRadixInteger:Long(value:Long, semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If Not builtin Then Return value
		Select builtin.name.ToLower()
			Case "byte" Return Long(Byte(value))
			Case "short" Return Long(Short(value))
			Case "int" Return Long(Int(value))
		End Select
		Return value
	End Function

	Function NormalizeRadixOperand(value:TConstantValue)
		If Not value Or value.kind <> CONSTANT_VALUE_INTEGER Or Not value.isRadixLiteral Then Return
		value.integerValue = NormalizeRadixInteger(value.integerValue, value.semanticType)
		value.isRadixLiteral = False
	End Function

	Function TryParseInteger:Int(text:String, value:Long Var)
		Local radix:Int = 10
		Local start:Int
		If text.length > 1 And text[0] = 36 Then
			radix = 16
			start = 1
		Else If text.length > 1 And text[0] = 37 Then
			radix = 2
			start = 1
		End If
		Local accumulator:ULong
		Local maximum:ULong = $ffffffffffffffff:ULong
		For Local index:Int = start Until text.length
			Local char:Int = text[index]
			Local digit:Int
			If char >= 48 And char <= 57 Then
				digit = char - 48
			Else If char >= 65 And char <= 70 Then
				digit = char - 55
			Else If char >= 97 And char <= 102 Then
				digit = char - 87
			Else
				Return False
			End If
			If digit >= radix Or accumulator > (maximum - ULong(digit)) / ULong(radix) Then Return False
			accumulator = accumulator * ULong(radix) + ULong(digit)
		Next
		value = Long(accumulator)
		Return start < text.length
	End Function

	Function DecodeString:String(text:String, multiline:Int)
		Local start:Int = 1
		Local finish:Int = text.length - 1
		If multiline Then
			start = 3
			finish = text.length - 3
		End If
		If finish < start Then Return ""
		Local body:String = text[start..finish]
		If multiline Then body = NormalizeMultilineString(body)
		Local result:String
		Local index:Int
		While index < body.length
			Local char:Int = body[index]
			If char = 126 And index + 1 < body.length Then
				index :+ 1
				Select body[index]
					Case 48 result :+ Chr(0)
					Case 110, 78 result :+ "~n"
					Case 114, 82 result :+ "~r"
					Case 116, 84 result :+ "~t"
					Case 113, 81 result :+ "~q"
					Case 126 result :+ "~~"
					Case 36
						Local value:Int
						Local cursor:Int = index + 1
						While cursor < body.length And body[cursor] <> 126
							value = (value Shl 4) | HexEscapeDigit(body[cursor])
							cursor :+ 1
						Wend
						result :+ Chr(value)
						index = cursor
					Case 37
						Local value:Int
						Local cursor:Int = index + 1
						While cursor < body.length And body[cursor] <> 126
							value :Shl 1
							If body[cursor] = 49 Then value :| 1
							cursor :+ 1
						Wend
						result :+ Chr(value)
						index = cursor
					Default
						If body[index] >= 49 And body[index] <= 57 Then
							Local value:Int
							Local cursor:Int = index
							While cursor < body.length And body[cursor] >= 48 And body[cursor] <= 57
								value = value * 10 + body[cursor] - 48
								cursor :+ 1
							Wend
							result :+ Chr(value)
							index = cursor
						Else
							result :+ Chr(body[index])
						End If
				End Select
			Else
				result :+ Chr(char)
			End If
			index :+ 1
		Wend
		Return result
	End Function

	Function HexEscapeDigit:Int(char:Int)
		If char >= 48 And char <= 57 Then Return char - 48
		If char >= 65 And char <= 70 Then Return char - 55
		If char >= 97 And char <= 102 Then Return char - 87
		Return 0
	End Function

	' Production multiline strings use the indentation before the closing
	' delimiter as their margin. They also trim line-end whitespace and allow a
	' trailing backslash to soft-wrap the following physical line.
	Function NormalizeMultilineString:String(body:String)
		body = body.Replace("~r~n", "~n").Replace("~r", "~n")
		If Not body.length Or body[0] <> 10 Then Return body
		body = body[1..]
		Local lines:String[] = body.Split("~n")
		If lines.length = 0 Then Return ""
		Local lineCount:Int = lines.length - 1
		Local trailingIndent:String = lines[lineCount]
		For Local index:Int = 0 Until trailingIndent.length
			If trailingIndent[index] <> 32 And trailingIndent[index] <> 9 Then Return body
		Next

		Local result:TStringBuilder = New TStringBuilder(body.length)
		For Local index:Int = 0 Until lineCount
			Local line:String = lines[index]
			If trailingIndent.length And line.StartsWith(trailingIndent) Then line = line[trailingIndent.length..]
			Local finish:Int = line.length
			While finish > 0 And (line[finish - 1] = 32 Or line[finish - 1] = 9)
				finish :- 1
			Wend
			Local softWrap:Int = finish > 0 And line[finish - 1] = 92
			If softWrap Then finish :- 1
			If finish Then result.Append(line[..finish])
			If Not softWrap And index < lineCount - 1 Then result.Append("~n")
		Next
		Return result.ToString()
	End Function

	Function NextFlagValue:Long(value:Long)
		If value <= 0 Then Return 1
		Local candidate:Long = 1
		While candidate <= value
			If candidate > 4611686018427387904:Long Then Return -1
			candidate :Shl 1
		Wend
		Return candidate
	End Function

	Function EnumValueIndex:Int(declaration:TEnumDeclarationSyntax, value:TEnumValueSyntax)
		For Local index:Int = 0 Until declaration.values.length
			If declaration.values[index] = value Then Return index
		Next
		Return -1
	End Function

	Function SymbolSpan:TSourceSpan(symbol:TSymbol)
		If symbol.nameToken Then Return symbol.nameToken.span
		If symbol.declaration Then Return symbol.declaration.span
		Return TSourceSpan.Create(0, 0)
	End Function

	Method AddDiagnostic(code:String, message:String, span:TSourceSpan)
		diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span, currentPath))
	End Method
End Type

Function ConstantDiagnosticsToArray:TDiagnostic[](list:TList)
	Local result:TDiagnostic[] = New TDiagnostic[list.Count()]
	Local index:Int
	For Local diagnostic:TDiagnostic = EachIn list
		result[index] = diagnostic
		index :+ 1
	Next
	Return result
End Function

Function MergeConstantDiagnostics:TDiagnostic[](first:TDiagnostic[], second:TDiagnostic[])
	Local result:TDiagnostic[] = New TDiagnostic[first.length + second.length]
	For Local index:Int = 0 Until first.length
		result[index] = first[index]
	Next
	For Local index:Int = 0 Until second.length
		result[first.length + index] = second[index]
	Next
	Return result
End Function
