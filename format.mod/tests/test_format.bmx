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
