' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Localised messages for the BlitzMax toolchain.
about: Provides the small runtime used by bcc, bmk, bls, and BlitzMax.Language.
Canonical TOML catalogues are compiled to .bmxcat files before distribution.
End Rem
Module BlitzMax.Locale

ModuleInfo "Version: 0.5.1"
ModuleInfo "History: Generate and verify release catalogues while keeping compiled files out of module sources."
ModuleInfo "History: Install .bmxcat catalogues centrally and load only requested domains."
ModuleInfo "History: Exclude localisation wrappers and quoted marker words from extraction reports."
ModuleInfo "History: Preserve source-only contributor acknowledgements in translation catalogues."
ModuleInfo "History: Add report-only source extraction and document the catalogue workflow."
ModuleInfo "History: Add catalogue discovery, locale fallback, translation sync, and registry locks."
ModuleInfo "History: Add typed placeholders, plural forms, and explicit locale contexts."
ModuleInfo "History: Initial locale runtime and compiled catalogue support."
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

Import "runtime.bmx"
