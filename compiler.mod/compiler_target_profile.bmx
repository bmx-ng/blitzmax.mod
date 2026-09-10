' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Tests whether a platform uses the compact compiled embedded runtime ABI.
about: Platform support is deliberately explicit. Embedded describes the runtime
profile rather than every target which might happen to run on embedded hardware.
End Rem
Function CompilerEmbeddedTarget:Int(platform:String)
	Return platform.ToLower() = "pico"
End Function
