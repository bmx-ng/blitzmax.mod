' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "syntax.bmx"

Type TConditionalEvaluator
	Function Evaluate:Int(expression:TConditionalExpressionSyntax, definedSymbols:String[])
		If Not expression Then Return False
		Local name:TConditionalNameSyntax = TConditionalNameSyntax(expression)
		If name Then Return ContainsSymbol(name.nameToken.text, definedSymbols)
		Local negation:TConditionalNotSyntax = TConditionalNotSyntax(expression)
		If negation Then Return Not Evaluate(negation.operand, definedSymbols)
		Local binary:TConditionalBinarySyntax = TConditionalBinarySyntax(expression)
		If binary Then
			If EqualsIgnoreCase(binary.operatorToken.text, "and") Then Return Evaluate(binary.left, definedSymbols) And Evaluate(binary.right, definedSymbols)
			If EqualsIgnoreCase(binary.operatorToken.text, "or") Then Return Evaluate(binary.left, definedSymbols) Or Evaluate(binary.right, definedSymbols)
			Return False
		End If
		Local parentheses:TConditionalParenthesizedSyntax = TConditionalParenthesizedSyntax(expression)
		If parentheses Then Return Evaluate(parentheses.expression, definedSymbols)
		Return False
	End Function

	Function ActiveBranchIndexes:Int[](region:TConditionalRegionSyntax, definedSymbols:String[])
		Local values:Int[] = New Int[region.branches.length]
		Local count:Int
		For Local index:Int = 0 Until region.branches.length
			If Evaluate(region.branches[index].condition, definedSymbols) Then
				values[count] = index
				count :+ 1
			End If
		Next
		If count = values.length Then Return values
		Return values[..count]
	End Function

	Function ContainsSymbol:Int(name:String, definedSymbols:String[])
		For Local symbol:String = EachIn definedSymbols
			If EqualsIgnoreCase(symbol, name) Then Return True
		Next
		Return False
	End Function

	Function EqualsIgnoreCase:Int(left:String, right:String)
		Return left.Compare(right, False) = 0
	End Function

	Function IsActive:Int(expression:TConditionalExpressionSyntax, definedSymbols:String[])
		Return Not expression Or Evaluate(expression, definedSymbols)
	End Function
End Type
