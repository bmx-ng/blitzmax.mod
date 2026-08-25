' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "syntax.bmx"

' Protocol-independent representation of a BlitzMax bbdoc Rem block.
Type TDocumentationComment
	Field summary:String
	Field returnsDescription:String
	Field about:String
	Field parameters:String[] = New String[0]
	Field keywords:String[] = New String[0]
	Field rawText:String

	Method HasContent:Int()
		Return summary.length Or returnsDescription.length Or about.length Or parameters.length Or keywords.length
	End Method
End Type

Type TBBDocParser
	Function Parse:TDocumentationComment(text:String)
		If Not text.length Then Return Null
		Local normalized:String = text.Replace("~r~n", "~n").Replace("~r", "~n")
		Local lines:String[] = normalized.Split("~n")
		Local result:TDocumentationComment = New TDocumentationComment
		result.rawText = text
		Local foundBBDoc:Int
		Local section:Int
		For Local index:Int = 0 Until lines.length
			Local line:String = lines[index].Trim()
			Local lower:String = line.ToLower()
			If index = 0 And lower = "rem" Then Continue
			If lower = "endrem" Or lower = "end rem" Then Continue
			If lower.StartsWith("bbdoc:") Then
				foundBBDoc = True
				section = 1
				AppendText(result.summary, line[6..].Trim())
				Continue
			End If
			If lower.StartsWith("returns:") Then
				section = 2
				AppendText(result.returnsDescription, line[8..].Trim())
				Continue
			End If
			If lower.StartsWith("param:") Then
				section = 0
				result.parameters :+ [line[6..].Trim()]
				Continue
			End If
			If lower.StartsWith("keyword:") Then
				section = 0
				result.keywords :+ [line[8..].Trim()]
				Continue
			End If
			If lower.StartsWith("about:") Then
				section = 3
				AppendText(result.about, line[6..].Trim())
				Continue
			End If
			Select section
				Case 1 AppendText(result.summary, line)
				Case 2 AppendText(result.returnsDescription, line)
				Case 3 AppendLine(result.about, line)
			End Select
		Next
		If Not foundBBDoc Or Not result.HasContent() Then Return Null
		result.summary = result.summary.Trim()
		result.returnsDescription = result.returnsDescription.Trim()
		result.about = result.about.Trim()
		Return result
	End Function

	Function AppendText(target:String Var, value:String)
		If Not value.length Then Return
		If target.length Then target :+ " "
		target :+ value
	End Function

	Function AppendLine(target:String Var, value:String)
		If target.length Then target :+ "~n"
		target :+ value
	End Function
End Type

' Immutable index used both by semantic collection and lazy provenance-source
' documentation lookup. Source provenance lines are one-based.
Type TDocumentationIndex
	Field source:TSourceText
	Field byLine:TMap = New TMap

	Function Build:TDocumentationIndex(tree:TSyntaxTree)
		If Not tree Or Not tree.root Or Not tree.source Then Return Null
		Local result:TDocumentationIndex = New TDocumentationIndex
		result.source = tree.source
		Local pending:TDocumentationComment
		For Local token:TSyntaxToken = EachIn tree.root.tokens
			For Local trivia:TSyntaxTrivia = EachIn token.leadingTrivia
				If trivia.kind = TRIVIA_BLOCK_COMMENT Then pending = TBBDocParser.Parse(trivia.text)
			Next
			If token.kind = TOKEN_NEWLINE Then Continue
			If pending Then
				Local line:Int = tree.source.Position(token.span.start).line + 1
				result.byLine.Insert(String(line), pending)
			End If
			pending = Null
		Next
		Return result
	End Function

	Method FindLine:TDocumentationComment(line:Int)
		Return TDocumentationComment(byLine.ValueForKey(String(line)))
	End Method

	Method FindDeclaration:TDocumentationComment(declaration:TSyntaxNode)
		If Not declaration Or Not declaration.span Or Not source Then Return Null
		Return FindLine(source.Position(declaration.span.start).line + 1)
	End Method
End Type
