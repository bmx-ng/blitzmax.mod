' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Identifies a zero-based line and column in source text.
End Rem
Type TSourcePosition
	Field line:Int
	Field column:Int

	Rem
	bbdoc: Creates a source position.
	param: The zero-based line number.
	param: The zero-based column number.
	returns: A new source position.
	End Rem
	Function Create:TSourcePosition(line:Int, column:Int)
		Local position:TSourcePosition = New TSourcePosition
		position.line = line
		position.column = column
		Return position
	End Function

	Rem
	bbdoc: Formats this position using one-based line and column numbers.
	returns: A position in `line:column` form.
	End Rem
	Method ToString:String()
		Return (line + 1) + ":" + (column + 1)
	End Method
End Type

Rem
bbdoc: Identifies a half-open range of characters in source text.
about: The range starts at #start and extends for #length characters. Offsets are
zero-based BlitzMax String indexes.
End Rem
Type TSourceSpan
	Field start:Int
	Field length:Int

	Rem
	bbdoc: Creates a source span.
	param: The zero-based starting offset.
	param: The number of characters in the span.
	returns: A new source span.
	End Rem
	Function Create:TSourceSpan(start:Int, length:Int)
		Local span:TSourceSpan = New TSourceSpan
		span.start = start
		span.length = length
		Return span
	End Function

	Rem
	bbdoc: Returns the exclusive ending offset of this span.
	End Rem
	Method EndOffset:Int()
		Return start + length
	End Method

	Rem
	bbdoc: Tests whether an offset lies within this span.
	param: The zero-based source offset to test.
	returns: #True when the offset is at or after the start and before the end.
	End Rem
	Method Contains:Int(offset:Int)
		Return offset >= start And offset < EndOffset()
	End Method

	Method ToString:String()
		Return "[" + start + ".." + EndOffset() + ")"
	End Method
End Type

Rem
bbdoc: Stores source text together with its path and line map.
about: #TSourceText translates efficiently between absolute character offsets and
line/column positions while preserving the original source string.
End Rem
Type TSourceText
	Field path:String
	Field text:String
	Field lineStarts:Int[]

	Rem
	bbdoc: Creates a mapped source text.
	param: The complete source string.
	param: The path used for diagnostics and identity.
	returns: A new source text with its line map populated.
	End Rem
	Function Create:TSourceText(text:String, path:String = "")
		Local source:TSourceText = New TSourceText
		source.path = path
		source.text = text
		source.BuildLineMap()
		Return source
	End Function

	Rem
	bbdoc: Returns the number of characters in the source.
	End Rem
	Method Length:Int()
		Return text.length
	End Method

	Rem
	bbdoc: Returns the number of lines in the source.
	End Rem
	Method LineCount:Int()
		Return lineStarts.length
	End Method

	Rem
	bbdoc: Returns the source characters covered by a span.
	param: The source span to read.
	returns: The selected text, clamped to the source bounds.
	End Rem
	Method Slice:String(span:TSourceSpan)
		If Not span Then Return ""
		Local first:Int = Max(0, Min(span.start, text.length))
		Local last:Int = Max(first, Min(span.EndOffset(), text.length))
		Return text[first..last]
	End Method

	Rem
	bbdoc: Converts a source offset to a zero-based line and column.
	param: The absolute character offset, which is clamped to the source bounds.
	returns: The corresponding source position.
	End Rem
	Method Position:TSourcePosition(offset:Int)
		Local clamped:Int = Max(0, Min(offset, text.length))
		Local low:Int = 0
		Local high:Int = lineStarts.length

		While low + 1 < high
			Local middle:Int = low + (high - low) / 2
			If lineStarts[middle] <= clamped Then
				low = middle
			Else
				high = middle
			End If
		Wend

		Return TSourcePosition.Create(low, clamped - lineStarts[low])
	End Method

	Rem
	bbdoc: Converts zero-based line and column coordinates to a source offset.
	param: The zero-based line number.
	param: The zero-based column number.
	returns: The corresponding absolute character offset, clamped to the line and source bounds.
	about: Columns use BlitzMax String indexing. Protocol adapters with a different
	encoding, such as LSP UTF-16, must convert their coordinates first.
	End Rem
	Method Offset:Int(line:Int, column:Int)
		If lineStarts.length = 0 Then Return 0
		Local clampedLine:Int = Max(0, Min(line, lineStarts.length - 1))
		Local lineStart:Int = lineStarts[clampedLine]
		Local lineEnd:Int = text.length
		If clampedLine + 1 < lineStarts.length Then
			lineEnd = lineStarts[clampedLine + 1]
			While lineEnd > lineStart And (text[lineEnd - 1] = 10 Or text[lineEnd - 1] = 13)
				lineEnd :- 1
			Wend
		End If
		Return lineStart + Max(0, Min(column, lineEnd - lineStart))
	End Method

	Rem
	bbdoc: Returns a span covering the complete source text.
	End Rem
	Method FullSpan:TSourceSpan()
		Return TSourceSpan.Create(0, text.length)
	End Method

	Method BuildLineMap()
		lineStarts = [0]
		For Local index:Int = 0 Until text.length
			If text[index] = 10 Then
				lineStarts :+ [index + 1]
			Else If text[index] = 13 And (index + 1 >= text.length Or text[index + 1] <> 10) Then
				lineStarts :+ [index + 1]
			End If
		Next
	End Method
End Type
