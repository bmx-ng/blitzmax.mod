# BlitzMax toolchain message catalogues

`BlitzMax.Locale` localises user-facing toolchain errors from `bcc`, `bmk`,
`bls`, and `BlitzMax.Language`. Status and progress output is deliberately out
of scope for the first migration so existing scripts keep their current text.
JSON-RPC and LSP protocol errors also remain stable protocol strings.

## Source layout

Each domain owns one permanent ID registry and one canonical English source:

```text
language.mod/locales/
    language.ids.lock.toml
    en/language.bmxloc.toml
    de-de/language.bmxloc.toml
```

The corresponding source locations are `compiler.mod/locales` for the `bcc`
domain, `lsp.mod/locales` for BLS-only messages, and `src/bmk/locales` for
`bmk`. Directory and locale names are lowercase. BCC and BLS share
language-domain messages instead of copying them into their own catalogues.

Compiled catalogues are build artifacts and are not stored in `blitzmax.mod`
or the tool source repositories. They use the opaque `.bmxcat` extension even
though their current internal representation is MessagePack. A distribution
ships them in one SDK-owned tree:

```text
<sdk>/bin/locales/de-de/
    language.bmxcat
    bcc.bmxcat
    bls.bmxcat
    bmk.bmxcat
```

The canonical English text is generated into the programs as their fallback,
so an installed `en` catalogue is neither generated nor required.

## Canonical English format

```toml
format = 1
domain = "language"
locale = "en"
next_id = 11

[[contributor]]
name = "Example Translator"
role = "translator"

[[message]]
id = 3
name = "parser.unexpected_token_in_expression"
text = "Unexpected token '{token}' in expression."
description = "Reported when the parser cannot accept the next token."
diagnostic_codes = ["BMX2102"]
placeholders = [{ name = "token", type = "string" }]
```

`id` is the compact, permanent storage identity. `name` generates the readable
domain-prefixed constant and wrapper function used by source code. IDs and names
must never be reused; `next_id` is the next available ID and the lock file makes
accidental reassignment fail validation.

`[[contributor]]` entries recognise people who worked on a catalogue. `name` is
required and may be a preferred display name; `role` is optional. Contributor
order is preserved by `sync`. This source-only acknowledgement is not included
in generated BlitzMax code or compiled MessagePack catalogues.

`description` and `diagnostic_codes` are optional translator and maintenance
metadata. They are not stored in the MessagePack catalogue. Placeholder names
are part of the message contract and may be reordered by a translation.

Plural messages use a typed integer selector and the standard six slots:

```toml
[[message]]
id = 10
name = "type.expected_type_arguments"
plural = "expected"
forms = { one = "Type '{typeName}' expects one type argument, but {supplied} were supplied.", other = "Type '{typeName}' expects {expected} type arguments, but {supplied} were supplied." }
placeholders = [{ name = "typeName", type = "string" }, { name = "expected", type = "integer" }, { name = "supplied", type = "integer" }]
```

`other` is required. The runtime selects `zero`, `one`, `two`, `few`, `many`,
or `other` using the active locale and falls back to `other` when a selected
slot is absent.

## Source calls

Generated wrappers keep numeric IDs out of hand-written code:

```blitzmax
AddDiagnostic(
    "BMX2102",
    TLanguageMessages.ParserUnexpectedTokenInExpression(token.text),
    token.span
)
```

Diagnostics retain the structured message until the output boundary. An
explicit `TLocaleContext` can render another locale without changing the
process default, so a server can produce different locales concurrently.

## Workflow

Build `locale.mod/tools/bmxlocale.bmx`, then use:

```text
bmxlocale extract <domain> <source-path> <report.toml>
bmxlocale check <english.toml> [translation.toml]
bmxlocale generate <english.toml> <output.bmx>
bmxlocale lock <english.toml> <output.lock.toml>
bmxlocale verify-lock <english.toml> <lock.toml>
bmxlocale init <english.toml> <locale> <output.toml>
bmxlocale sync <english.toml> <translation.toml> <output.toml>
bmxlocale compile <english.toml> <translation.toml> <output.bmxcat>
bmxlocale verify <catalogue.bmxcat>
bmxlocale install <sdk-path> <catalogue.bmxcat> [catalogue.bmxcat ...]
```

`extract` is intentionally report-only. It records hard-coded candidate error
expressions, diagnostic codes where available, and source locations. A person
then chooses the stable name, assigns `next_id`, identifies placeholders, and
adds any useful description. Re-running extraction omits already migrated calls.

`init` creates a lowercase locale skeleton with `translated = false`. It omits
contributors until a real name is added. `sync` preserves contributors in their
existing order, preserves completed translations, and refreshes untranslated
entries. Untranslated entries are omitted from the compiled binary and fall back
through a regional locale, its base language, and finally embedded English.

`install` reads each compiled catalogue's domain and locale and copies it to
the canonical `<sdk>/bin/locales/<locale>/<domain>.bmxcat` path. It accepts
multiple catalogues so a developer can install a complete locale in one call.
`verify` proves that a compiled catalogue can be loaded and that its embedded
domain and locale are valid. Release assembly builds a host-native `bmxlocale`,
checks the canonical registry locks and translations, compiles directly into
the SDK's `bin/locales` tree, and verifies every output. The separately built
target `bin/bmxlocale` executable ships as part of the release.

## Locale selection

The command-line tools accept `--locale <name>` (`bcc`) or `-locale <name>`
(`bmk`). BLS uses the standard `locale` member of the LSP `initialize` request.
Without an explicit value, selection checks `BMX_LOCALE`, `LC_ALL`,
`LC_MESSAGES`, and `LANG`, in that order. Values such as `de_DE.UTF-8` normalize
to `de-de`.

Installed catalogues are discovered below `<sdk>/bin/locales`. Each executable
loads only the domains it can emit: bcc loads `language` and `bcc`, BLS loads
`language` and `bls`, and bmk loads only `bmk`.

During development, `BMX_LOCALE_PATH` may point at an override root containing
`<locale>/<domain>.bmxcat` files. For each locale candidate, this root is
searched before the installed SDK root. Regional catalogues are still preferred
to base-language catalogues, so `de-de` precedes `de` regardless of root.
