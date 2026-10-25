' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Reusable BlitzMax source formatter
about: Formats source text using the BlitzMax parser without depending on an editor or language server.
End Rem
Module BlitzMax.Format

ModuleInfo "Version: 0.1.0"
ModuleInfo "History: Extract the parser-based formatter from BlitzMax.LSP for standalone use."
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

Import BRL.Map
Import BlitzMax.Language

Import "formatting.bmx"
