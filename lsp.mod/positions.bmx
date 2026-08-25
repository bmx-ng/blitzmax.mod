' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import Text.Json
Import BlitzMax.Language
Import "protocol.bmx"

' LSP positions use UTF-16 code units. The language model deliberately keeps
' native BlitzMax String offsets, so all protocol conversion lives here.
Type TLspPositions
	Function Offset:Int(source:TSourceText, line:Int, character:Int)
		If Not source Then Return 0
		Local start:Int = source.Offset(line, 0)
		Local finish:Int = source.Offset(line, 2147483647)
		Local offset:Int = start
		Local units:Int
		Local requested:Int = Max(0, character)
		While offset < finish And units < requested
			Local width:Int = 1
			If Asc(source.text[offset..offset + 1]) > 65535 Then width = 2
			If units + width > requested Then Exit
			units :+ width
			offset :+ 1
		Wend
		Return offset
	End Function

	Function Position:TJSONObject(source:TSourceText, offset:Int)
		Local position:TSourcePosition = source.Position(offset)
		Local lineStart:Int = source.Offset(position.line, 0)
		Local units:Int
		For Local index:Int = lineStart Until offset
			If Asc(source.text[index..index + 1]) > 65535 Then units :+ 2 Else units :+ 1
		Next
		Local result:TJSONObject = JsonObject()
		result.Set("line", position.line)
		result.Set("character", units)
		Return result
	End Function

	Function Range:TJSONObject(source:TSourceText, span:TSourceSpan)
		Local result:TJSONObject = JsonObject()
		result.Set("start", Position(source, span.start))
		result.Set("end", Position(source, span.EndOffset()))
		Return result
	End Function
End Type
