' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Supplies cooperative cancellation to language-analysis operations.
about: Implementations must be thread safe. Language stages poll cancellation only
at deterministic model boundaries; cancellation does not interrupt a stage at an
arbitrary instruction.
End Rem
Type TLanguageCancellationToken Abstract
	Rem
	bbdoc: Reports whether the consumer has requested cancellation.
	End Rem
	Method IsCancellationRequested:Int() Abstract
End Type

Rem
bbdoc: Safely tests an optional language cancellation token.
param: The token to test, or #Null when cancellation is not required.
returns: #True when the token exists and cancellation has been requested.
End Rem
Function LanguageCancellationRequested:Int(token:TLanguageCancellationToken)
	Return token And token.IsCancellationRequested()
End Function
