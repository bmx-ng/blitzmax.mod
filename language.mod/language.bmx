' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Reusable BlitzMax language syntax and semantic model
about: Parses and analyses BlitzMax source for compilers, editors, interpreters, and other development tools.
End Rem
Module BlitzMax.Language

ModuleInfo "Version: 0.13.10"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

Import "cancellation.bmx"
Import "blitzmax_parser.bmx"
Import "snapshot_loader.bmx"
Import "semantic_analyzer.bmx"
Import "expression_binding.bmx"
Import "constant_evaluation.bmx"
Import "compile_time_analysis.bmx"
Import "control_flow_analysis.bmx"
Import "data_flow_analysis.bmx"
Import "generic_template_model.bmx"
Import "generic_template_codec.bmx"
Import "syntax_dumper.bmx"
Import "semantic_dumper.bmx"
Import "bound_dumper.bmx"
Import "interface_dumper.bmx"
Import "interface_cloner.bmx"
Import "interface_documentation.bmx"
Import "source_interface_builder.bmx"
Import "syntax_navigation.bmx"
Import "documentation_model.bmx"
Import "declaration_metadata.bmx"
Import "symbol_accessibility.bmx"
Import "member_completion.bmx"
Import "contextual_completion.bmx"
Import "type_completion.bmx"
Import "completion_ranking.bmx"
Import "symbol_catalogue.bmx"
Import "interface_source_resolver.bmx"
Import "language_api.bmx"
