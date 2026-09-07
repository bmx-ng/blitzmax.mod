' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Reusable staged BlitzMax compiler pipeline
about: Analyses BlitzMax programs, lowers them to typed compiler IR, and emits C, interfaces, and generic build artifacts.
End Rem
Module BlitzMax.Compiler

ModuleInfo "Version: 0.1.1"
ModuleInfo "History: Complete localisation of C-backend diagnostics."
ModuleInfo "History: Localise C-backend Object, dispatch, Catch, and assignment diagnostics."
ModuleInfo "History: Localise C-backend expression, call, and Array diagnostics."
ModuleInfo "History: Localise C-backend layout, iterator, and statement diagnostics."
ModuleInfo "History: Begin localisation of C-backend and Pico-profile diagnostics."
ModuleInfo "History: Complete localisation of IR-lowering diagnostics."
ModuleInfo "History: Localise imported ABI, symbol ownership, and value-layout diagnostics."
ModuleInfo "History: Localise callable invocation, member dispatch, and function-literal diagnostics."
ModuleInfo "History: Localise call dispatch and construction lowering diagnostics."
ModuleInfo "History: Localise operator, indexing, conversion, and Range lowering diagnostics."
ModuleInfo "History: Localise storage and statement lowering diagnostics."
ModuleInfo "History: Localise iterator and EachIn lowering diagnostics."
ModuleInfo "History: Localise routine and Extern declaration lowering diagnostics."
ModuleInfo "History: Localise Closure environment and Using resource diagnostics."
ModuleInfo "History: Localise Interface and Type IR-lowering diagnostics."
ModuleInfo "History: Localise data, Enum, and Struct IR-lowering diagnostics."
ModuleInfo "History: Localise core IR-lowering diagnostics."
ModuleInfo "History: Localise compact interface-emission diagnostics."
ModuleInfo "History: Localise generic application planning diagnostics."
ModuleInfo "History: Localise compiler API and build-output diagnostics."
ModuleInfo "History: Add the first compiler-domain localised diagnostic."
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

Import BRL.FileSystem
Import BRL.Map
Import BRL.MaxUtil
Import BlitzMax.Language
Import BlitzMax.Locale

Import "bcc_messages.generated.bmx"
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
