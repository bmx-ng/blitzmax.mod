' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Map

Import "diagnostic.bmx"
Import "token.bmx"

Type TDeclarationMetadataEntry
	Field key:String
	Field value:String
	Field writtenValue:String
	Field span:TSourceSpan
End Type

' Normalized, case-insensitive declaration metadata. Syntax tokens remain on
' declarations for lossless tooling; semantic consumers use this model instead
' of scanning braces or modifier tokens themselves.
Type TDeclarationMetadata
	Field entries:TDeclarationMetadataEntry[] = New TDeclarationMetadataEntry[0]
	Field byKey:TMap = New TMap
	Field tokens:TSyntaxToken[] = New TSyntaxToken[0]

	Method Has:Int(key:String)
		Return byKey.Contains(key.ToLower())
	End Method

	Method Entry:TDeclarationMetadataEntry(key:String)
		Return TDeclarationMetadataEntry(byKey.ValueForKey(key.ToLower()))
	End Method

	Method Value:String(key:String, fallback:String = "")
		Local item:TDeclarationMetadataEntry = Entry(key)
		If item Then Return item.value
		Return fallback
	End Method

	Method Add(entry:TDeclarationMetadataEntry)
		entries :+ [entry]
		byKey.Insert(entry.key.ToLower(), entry)
	End Method

	Function Parse:TDeclarationMetadata(values:TSyntaxToken[], diagnostics:TList = Null, path:String = "")
		If Not values Or values.length = 0 Then Return Null
		Local openIndex:Int = -1
		For Local index:Int = 0 Until values.length
			If values[index].text = "{" Then openIndex = index; Exit
		Next
		If openIndex < 0 Then Return Null

		Local result:TDeclarationMetadata = New TDeclarationMetadata
		result.tokens = values[openIndex..]
		Local cursor:Int = openIndex + 1
		Local closed:Int
		While cursor < values.length
			Local token:TSyntaxToken = values[cursor]
			If token.text = "}" Then closed = True; Exit
			If token.kind <> TOKEN_IDENTIFIER And token.kind <> TOKEN_KEYWORD Then
				AddDiagnostic(diagnostics, "BMX3010", "Expected a metadata key.", token.span, path)
				cursor :+ 1
				Continue
			End If
			Local entry:TDeclarationMetadataEntry = New TDeclarationMetadataEntry
			entry.key = token.text.ToLower()
			entry.value = "1"
			entry.writtenValue = "1"
			entry.span = token.span
			cursor :+ 1
			If cursor < values.length And values[cursor].text = "=" Then
				cursor :+ 1
				If cursor >= values.length Or values[cursor].text = "}" Then
					AddDiagnostic(diagnostics, "BMX3011", "Expected a literal metadata value after '='.", token.span, path)
				Else If Not IsLiteralValue(values[cursor]) Then
					AddDiagnostic(diagnostics, "BMX3011", "Expected a literal metadata value after '='.", values[cursor].span, path)
					cursor :+ 1
				Else
					entry.writtenValue = values[cursor].text
					entry.value = DecodeValue(entry.writtenValue)
					cursor :+ 1
				End If
			End If
			If result.Has(entry.key) Then
				AddDiagnostic(diagnostics, "BMX3012", "Duplicate metadata key '" + entry.key + "'.", entry.span, path)
			Else
				result.Add(entry)
			End If
		Wend
		If Not closed Then AddDiagnostic(diagnostics, "BMX3013", "Expected '}' after declaration metadata.", values[openIndex].span, path)
		Return result
	End Function

	Function IsLiteralValue:Int(token:TSyntaxToken)
		If Not token Then Return False
		Return token.kind = TOKEN_INTEGER_LITERAL Or token.kind = TOKEN_FLOAT_LITERAL Or token.kind = TOKEN_STRING_LITERAL Or token.kind = TOKEN_MULTILINE_STRING_LITERAL
	End Function

	Function DecodeValue:String(value:String)
		If value.length >= 2 And value[0] = 34 And value[value.length - 1] = 34 Then Return value[1..value.length - 1]
		Return value
	End Function

	Function AddDiagnostic(diagnostics:TList, code:String, message:String, span:TSourceSpan, path:String)
		If diagnostics Then diagnostics.AddLast(TDiagnostic.Create(code, message, DIAGNOSTIC_ERROR, span, path))
	End Function
End Type
