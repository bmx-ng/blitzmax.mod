' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import Pub.StdC
Import "../runtime.bmx"

If AppArgs.length <> 5 Then Throw "Expected SDK, regional override, base override, and empty override roots"

Local sdkPath:String = AppArgs[1]
Local regionalOverrideRoot:String = AppArgs[2]
Local baseOverrideRoot:String = AppArgs[3]
Local emptyOverrideRoot:String = AppArgs[4]

' A same-locale development catalogue overrides the installed catalogue, and
' an unrequested domain remains on its embedded English fallback.
putenv_("BMX_LOCALE_PATH=" + regionalOverrideRoot)
TLocale.ConfigureToolchain(["language"], "de-de", sdkPath)
AssertEqual("regional override", TLocalisedMessage.Create("language", 1, "language fallback").Render(), "regional override precedence")
AssertEqual("bcc fallback", TLocalisedMessage.Create("bcc", 1, "bcc fallback").Render(), "selective language loading")

' Locale specificity wins before root precedence: an installed de-de catalogue
' is preferred to a development override that only supplies de.
putenv_("BMX_LOCALE_PATH=" + baseOverrideRoot)
TLocale.ConfigureToolchain(["language"], "de-de", sdkPath)
AssertEqual("Die Verschachtelung des Ausdrucks ist zu tief, um ihn sicher zu analysieren.", TLocalisedMessage.Create("language", 1, "language fallback").Render(), "regional installed catalogue before base override")

' Selecting bcc loads its catalogue without retaining the previously loaded
' language domain. ConfigureToolchain always creates a fresh context.
putenv_("BMX_LOCALE_PATH=" + emptyOverrideRoot)
TLocale.ConfigureToolchain(["bcc"], "de-de", sdkPath)
AssertEqual("Die Quelldatei wurde nicht gefunden", TLocalisedMessage.Create("bcc", 1, "bcc fallback").Render(), "installed bcc catalogue")
AssertEqual("language fallback", TLocalisedMessage.Create("language", 1, "language fallback").Render(), "selective bcc loading")

Print "toolchain locale loading tests passed"

Function AssertEqual(expected:String, actual:String, label:String)
	If actual <> expected Then Throw label + ": expected '" + expected + "', got '" + actual + "'"
End Function
