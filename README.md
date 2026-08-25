# BlitzMax language tools

Reusable BlitzMax NG modules for parsing, analysing, compiling, and providing
editor tooling for the BlitzMax language.

## Modules

### BlitzMax.Language

Provides the shared source model, lexer, parser, immutable syntax tree,
semantic model, analysis passes, symbol catalogue, completion services,
interface readers, and compilation snapshots.

```blitzmax
Import BlitzMax.Language
```

### BlitzMax.Compiler

Builds on `BlitzMax.Language` with compiler options and diagnostics, typed
intermediate representation, lowering, generic specialization planning,
interface and build-artifact emission, and the native C backend.

```blitzmax
Import BlitzMax.Compiler
```

### BlitzMax.LSP

Builds on `BlitzMax.Language` with reusable Language Server Protocol support,
including diagnostics, completion, hover, navigation, rename, references,
semantic tokens, inlay hints, workspace symbols, and installed-module
discovery.

```blitzmax
Import BlitzMax.LSP
```

The dependency direction is intentionally one-way:

```text
BlitzMax.Compiler -> BlitzMax.Language
BlitzMax.LSP      -> BlitzMax.Language
```

Compiler-only planning and code generation do not enter the LSP module.

## Installation

Clone this repository as `blitzmax.mod` beneath the `mod` directory of a
matching BlitzMax NG SDK:

```text
BlitzMax/
  mod/
    blitzmax.mod/
      language.mod/
      compiler.mod/
      lsp.mod/
```

Build the modules with bmk2, for example:

```sh
bmk makemods -a -r BlitzMax.Language
bmk makemods -a -r BlitzMax.Compiler
bmk makemods -a -r BlitzMax.LSP
```

These modules are developed together with bmk2 and bcc2 and should be updated
as a matched toolchain. The runnable `bcc` compiler and `bls` language-server
applications are maintained in the separate `bcc2` repository.

## Documentation

Each module's `doc` directory contains source material used by the BlitzMax
documentation generator. Public APIs also carry bbdoc comments alongside their
declarations.
