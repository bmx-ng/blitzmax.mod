' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Reusable JSON-RPC and Language Server Protocol support for BlitzMax
about: Provides protocol framing, document and workspace services, and an embeddable BlitzMax language server.
End Rem
Module BlitzMax.LSP

ModuleInfo "Version: 0.24.10"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

Import BRL.Map
Import BRL.Stream
Import Text.Json
Import BlitzMax.Language

Import "protocol.bmx"
Import "message_queue.bmx"
Import "documents.bmx"
Import "workspace_analysis.bmx"
Import "installed_modules.bmx"
Import "workspaces.bmx"
Import "positions.bmx"
Import "diagnostics.bmx"
Import "documentation.bmx"
Import "hover.bmx"
Import "completion.bmx"
Import "semantic_tokens.bmx"
Import "inlay_hints.bmx"
Import "import_completion.bmx"
Import "navigation_features.bmx"
Import "type_hierarchy.bmx"
Import "implementation.bmx"
Import "folding_ranges.bmx"
Import "selection_ranges.bmx"
Import "workspace_symbols.bmx"
Import "rename.bmx"
Import "document_links.bmx"
Import "references.bmx"
Import "code_actions.bmx"
Import "server.bmx"
