' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BlitzMax.Language

Rem
bbdoc: Describes a problem reported by compiler planning, lowering, or emission.
End Rem
Type TCompilerDiagnostic
	Field code:String
	Field message:String
	Field path:String
	Field span:TSourceSpan
	' Source locations decoded from interfaces or retained IR may no longer
	' have their original source text or offset span. Lines are one-based and
	' columns are zero-based, matching TCompilerSourceLocation.
	Field line:Int
	Field column:Int

	Rem
	bbdoc: Creates a compiler diagnostic.
	param: The stable compiler diagnostic code.
	param: The human-readable diagnostic message.
	param: The source or artifact path.
	param: An optional source span.
	param: An optional one-based line used when source text is unavailable.
	param: An optional zero-based column used when source text is unavailable.
	returns: A new compiler diagnostic.
	End Rem
	Function Create:TCompilerDiagnostic(code:String, message:String, path:String = "", span:TSourceSpan = Null, line:Int = 0, column:Int = 0)
		Local result:TCompilerDiagnostic = New TCompilerDiagnostic
		result.code = code
		result.message = message
		result.path = path
		result.span = span
		result.line = line
		result.column = column
		Return result
	End Function

	Rem
	bbdoc: Formats this compiler diagnostic for display.
	param: Optional source text used to resolve a source span.
	returns: A path, location, diagnostic code, and message suitable for logs or a console.
	End Rem
	Method Format:String(source:TSourceText = Null)
		Local location:String = path
		If source And span And (Not path.length Or source.path = path) Then
			Local position:TSourcePosition = source.Position(span.start)
			If Not location.length Then location = source.path
			location :+ ":" + position.ToString()
		Else If line > 0 Then
			location :+ ":" + line + ":" + (column + 1)
		End If
		If location.length Then location :+ ": "
		Return location + "error " + code + ": " + message
	End Method
End Type
