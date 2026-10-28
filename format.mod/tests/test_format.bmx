' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict
Framework BRL.StandardIO
Import BlitzMax.Format

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local source:String = "SuperStrict~nFunction Probe()~nIf True~nPrint ~qone~q,~qtwo~q  ~nEnd If~nEnd Function~n"
Local expected:String = "SuperStrict~nFunction Probe()~n~tIf True~n~t~tPrint ~qone~q, ~qtwo~q~n~tEnd If~nEnd Function~n"
Local defaults:TBlitzMaxFormatOptions = New TBlitzMaxFormatOptions
Local edits:TBlitzMaxFormatEdits = TBlitzMaxFormatter.Query(source, "probe.bmx")
Check(edits.Size() > 0, "standalone formatter returns source-offset edits")
For Local edit:TBlitzMaxFormatEdit = EachIn edits.items
	Check(edit.start >= 0 And edit.finish >= edit.start And edit.finish <= source.length, "edits use valid source offsets")
Next
Check(edits.Apply(source) = expected, "edits apply without LSP positions or JSON")
Check(TBlitzMaxFormatter.FormatText(source, "probe.bmx") = expected, "convenience API returns formatted source")
Check(TBlitzMaxFormatter.FormatText(expected, "probe.bmx") = expected, "standalone formatting is idempotent")

Local inlineSource:String = "SuperStrict~nFunction Probe()~nIf True Then Print ~qone~q~nIf True Then Print ~qtwo~q~nPrint ~qdone~q~nEnd Function~n"
Local inlineExpected:String = "SuperStrict~nFunction Probe()~n~tIf True Then~n~t~tPrint ~qone~q~n~tEnd If~n~n~tIf True Then~n~t~tPrint ~qtwo~q~n~tEnd If~n~n~tPrint ~qdone~q~nEnd Function~n"
Local inlineOptions:TBlitzMaxFormatOptions = New TBlitzMaxFormatOptions
inlineOptions.inlineIfStyle = "expand"
inlineOptions.controlBlankLines = "one"
Check(TBlitzMaxFormatter.FormatText(inlineSource, "probe.bmx", inlineOptions) = inlineExpected, "expanded inline If blocks receive blank lines before sibling statements")
Check(TBlitzMaxFormatter.FormatText(inlineExpected, "probe.bmx", inlineOptions) = inlineExpected, "combined inline expansion and blank lines are idempotent")
Check(TBlitzMaxParser.ParseText(inlineExpected).syntaxTree.diagnostics.length = 0, "combined formatting remains parseable")

Local commentsSource:String = "SuperStrict~nType TProbe~n ' method description~nMethod Run()~n' body description~nRem~n  keep relative spacing~nEnd Rem~nPrint ~qready~q ' trailing comment~nEnd Method~nEnd Type~n"
Local commentsExpected:String = "SuperStrict~nType TProbe~n~t' method description~n~tMethod Run()~n~t~t' body description~n~t~tRem~n~t~t  keep relative spacing~n~t~tEnd Rem~n~t~tPrint ~qready~q ' trailing comment~n~tEnd Method~nEnd Type~n"
Check(TBlitzMaxFormatter.FormatText(commentsSource) = commentsExpected, "standalone formatter aligns line comments and shifts Rem blocks without changing their internal spacing")
Check(TBlitzMaxFormatter.FormatText(commentsExpected) = commentsExpected, "comment indentation is idempotent")
Check(TBlitzMaxParser.ParseText(commentsExpected).syntaxTree.diagnostics.length = 0, "indented comments remain parseable")
Local commentCrLf:String = "SuperStrict~r~nType TProbe~r~n ' note~r~nMethod Run()~r~nEnd Method~r~nEnd Type~r~n"
Check(TBlitzMaxFormatter.FormatText(commentCrLf) = "SuperStrict~r~nType TProbe~r~n~t' note~r~n~tMethod Run()~r~n~tEnd Method~r~nEnd Type~r~n", "comment indentation preserves CRLF")
Local commentBeforeClose:String = "SuperStrict~nType TProbe~nMethod Run()~n' inside method~nEnd Method~n' inside type~nEnd Type~n"
Check(TBlitzMaxFormatter.FormatText(commentBeforeClose) = "SuperStrict~nType TProbe~n~tMethod Run()~n~t~t' inside method~n~tEnd Method~n~t' inside type~nEnd Type~n", "comments before closing lines stay inside their blocks")
Local noIndent:TBlitzMaxFormatOptions = New TBlitzMaxFormatOptions
noIndent.indent = False
Check(TBlitzMaxFormatter.FormatText(commentsSource, "probe.bmx", noIndent) = commentsSource, "disabling indentation also preserves comment indentation")

Local custom:TBlitzMaxFormatOptions = defaults.Copy()
custom.thenStyle = "add"
custom.endStyle = "combined"
custom.indent = False
custom.spaceAfterComma = False
custom.trimTrailingWhitespace = False
Check(defaults.thenStyle = "preserve" And defaults.indent And defaults.spaceAfterComma, "copying options does not mutate defaults")
Check(TBlitzMaxFormatter.FormatText(source, "probe.bmx", custom) = "SuperStrict~nFunction Probe()~nIf True Then~nPrint ~qone~q,~qtwo~q  ~nEndIf~nEndFunction~n", "custom options work without an LSP workspace")

Local multiline:String = "SuperStrict~nLocal value:String = ~q~q~q~n  text  ~n~q~q~q~nPrint value~n"
Check(TBlitzMaxFormatter.FormatText(multiline) = multiline, "multiline string contents remain untouched")
Local crlf:String = "SuperStrict~r~nFunction Probe()~r~nPrint ~qx~q~r~nEnd Function~r~n"
Check(TBlitzMaxFormatter.FormatText(crlf) = "SuperStrict~r~nFunction Probe()~r~n~tPrint ~qx~q~r~nEnd Function~r~n", "standalone formatter preserves CRLF")
Local malformed:String = "SuperStrict~nFunction Broken:Int(~nEnd Function~n"
Check(TBlitzMaxFormatter.Query(malformed).Size() = 0 And TBlitzMaxFormatter.FormatText(malformed) = malformed, "source with parse errors is unchanged")

Print "BlitzMax.Format standalone tests passed"
