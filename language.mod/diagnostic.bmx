' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BlitzMax.Locale

Import "source.bmx"

Const DIAGNOSTIC_INFO:Int = 0
Const DIAGNOSTIC_WARNING:Int = 1
Const DIAGNOSTIC_ERROR:Int = 2

Rem
bbdoc: Describes a syntax or semantic problem found in BlitzMax source.
End Rem
Type TDiagnostic
	Field code:String
	Field message:String
	Field localisedMessage:TLocalisedMessage
	Field severity:Int
	Field span:TSourceSpan
	Field path:String

	Rem
	bbdoc: Creates a language diagnostic.
	param: The stable diagnostic code.
	param: The human-readable diagnostic message.
	param: One of #DIAGNOSTIC_INFO, #DIAGNOSTIC_WARNING, or #DIAGNOSTIC_ERROR.
	param: The source span associated with the diagnostic.
	param: The source path associated with the diagnostic.
	returns: A new diagnostic.
	End Rem
	Function Create:TDiagnostic(code:String, message:String, severity:Int, span:TSourceSpan, path:String = "")
		Local diagnostic:TDiagnostic = New TDiagnostic
		diagnostic.code = code
		diagnostic.message = message
		diagnostic.severity = severity
		diagnostic.span = span
		diagnostic.path = path
		Return diagnostic
	End Function

	Rem
	bbdoc: Creates a language diagnostic from a stable localised message reference.
	about: The rendered #message field remains available for existing consumers while
	#localisedMessage preserves the domain, ID, fallback, and named arguments.
	End Rem
	Function Create:TDiagnostic(code:String, message:TLocalisedMessage, severity:Int, span:TSourceSpan, path:String = "")
		Local diagnostic:TDiagnostic = New TDiagnostic
		diagnostic.code = code
		diagnostic.localisedMessage = message
		diagnostic.message = message.Render()
		diagnostic.severity = severity
		diagnostic.span = span
		diagnostic.path = path
		Return diagnostic
	End Function

	Rem
	bbdoc: Returns the lowercase name of this diagnostic's severity.
	End Rem
	Method SeverityName:String()
		Select severity
			Case DIAGNOSTIC_INFO
				Return "info"
			Case DIAGNOSTIC_WARNING
				Return "warning"
			Default
				Return "error"
		End Select
	End Method

	Rem
	bbdoc: Renders this diagnostic using an explicit locale context.
	End Rem
	Method MessageFor:String(context:TLocaleContext)
		If localisedMessage Then Return localisedMessage.Render(context)
		Return message
	End Method

	Rem
	bbdoc: Formats this diagnostic for display.
	param: Optional source text used to resolve the span to a line and column.
	returns: A path, location, severity, code, and message suitable for logs or a console.
	End Rem
	Method Format:String(source:TSourceText)
		Return FormatFor(source, Null)
	End Method

	Rem
	bbdoc: Formats this diagnostic using an explicit locale context.
	End Rem
	Method FormatFor:String(source:TSourceText, context:TLocaleContext)
		Local location:String = path
		Local sourceMatchesPath:Int = source <> Null And (Not path.length Or source.path.Replace(Chr(92), "/").ToLower() = path.Replace(Chr(92), "/").ToLower())
		If sourceMatchesPath And span Then
			Local position:TSourcePosition = source.Position(span.start)
			Local locationPath:String = path
			If Not locationPath.length Then locationPath = source.path
			location = locationPath + ":" + position.ToString() + ": "
		Else If location.length Then
			location :+ ": "
		End If
		Return location + SeverityName() + " " + code + ": " + MessageFor(context)
	End Method
End Type
