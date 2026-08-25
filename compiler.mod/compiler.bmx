' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Reusable staged BlitzMax compiler pipeline
about: Analyses BlitzMax programs, lowers them to typed compiler IR, and emits C, interfaces, and generic build artifacts.
End Rem
Module BlitzMax.Compiler

ModuleInfo "Version: 0.1.0"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

Import BRL.FileSystem
Import BRL.Map
Import BRL.MaxUtil
Import BlitzMax.Language

Import "compiler_diagnostic.bmx"
Import "compiler_options.bmx"
Import "file_snapshot_resolver.bmx"
Import "ir_model.bmx"
Import "abi_naming.bmx"
Import "generic_specialization.bmx"
Import "generic_application_plan.bmx"
Import "ir_lowering.bmx"
Import "ir_dumper.bmx"
Import "c_backend.bmx"
Import "interface_emitter.bmx"
Import "build_output_plan.bmx"
Import "compiler_api.bmx"
Import "build_output_publish.c"
