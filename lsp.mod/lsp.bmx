' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Reusable JSON-RPC and Language Server Protocol support for BlitzMax
about: Provides protocol framing, document and workspace services, and an embeddable BlitzMax language server.
End Rem
Module BlitzMax.LSP

ModuleInfo "Version: 0.24.21"
ModuleInfo "History: Use the standalone BlitzMax.Format engine for document and range formatting."
ModuleInfo "History: Add configurable blank lines between declarations and after control blocks."
ModuleInfo "History: Trim trailing whitespace outside protected multiline and native text."
ModuleInfo "History: Add token-safe compact spacing for assignment and binary operators."
ModuleInfo "History: Add configurable spacing around parsed assignments and binary expressions."
ModuleInfo "History: Add configurable metadata brace and call-parenthesis spacing."
ModuleInfo "History: Allow Case and Default labels to align with Select while indenting case bodies."
ModuleInfo "History: Add configurable spacing after commas while preserving wrapped lines and multiline strings."
ModuleInfo "History: Add conservative document and range formatting for indentation, If headers, and named block endings."
ModuleInfo "History: Localise BLS protocol and installed-module discovery errors."
ModuleInfo "History: Honour the LSP client locale for user-facing diagnostics."
ModuleInfo "History: Added a preferred Self-qualification fix for hidden-field self-assignment warnings."
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

Import BRL.Map
Import BRL.Stream
Import Text.Json
Import BlitzMax.Format
Import BlitzMax.Language

Import "bls_messages.generated.bmx"
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
Import "call_hierarchy.bmx"
Import "folding_ranges.bmx"
Import "selection_ranges.bmx"
Import "workspace_symbols.bmx"
Import "rename.bmx"
Import "document_links.bmx"
Import "references.bmx"
Import "code_actions.bmx"
Import "server.bmx"
