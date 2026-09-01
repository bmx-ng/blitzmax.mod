' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.MaxUtil
Import BRL.FileSystem
Import BlitzMax.Language

Rem
bbdoc: Configures source analysis, target selection, instrumentation, and emission for the compiler pipeline.
End Rem
Type TCompilerOptions
	Field sdkPath:String
	Field buildMode:String = "release"
	Field targetPlatform:String
	Field targetArchitecture:String
	Field conditionalSymbols:String[] = New String[0]
	Field requireCoreInterface:Int = True
	' Standalone and embedded consumers can retain the intrinsic core types
	' without importing the BRL.Blitz runtime module.
	Field implicitRuntime:Int = True
	Field sourceModuleName:String
	Field debugInstrumentation:Int
	Field coverageInstrumentation:Int
	Field applicationBuild:Int
	Field applicationSourceUnit:Int
	Field applicationIdentity:String
	' Stable path of this quoted source relative to its module or application
	' source root. bmk supplies this for path-owned secondary units so runtime
	' identities remain relocatable and same-basename nested sources cannot
	' collide.
	Field sourceUnitPath:String
	Field applicationType:String
	Field frameworkModule:String
	Field threaded:Int = True
	Field verbose:Int
	Field gdbDebug:Int
	Field musl:Int
	Field userDefinitions:String

	Rem
	bbdoc: Creates compiler options initialized for the host SDK, platform, and architecture.
	returns: A new default compiler configuration.
	End Rem
	Function CreateDefault:TCompilerOptions()
		Local result:TCompilerOptions = New TCompilerOptions
		Try
			result.sdkPath = BlitzMaxPath()
		Catch exception:Object
			result.sdkPath = ""
		End Try
		result.targetPlatform = CompilerHostPlatform()
		result.targetArchitecture = CompilerHostArchitecture()
		result.RefreshConditionalSymbols()
		Return result
	End Function

	Rem
	bbdoc: Returns the build-mode, platform, and architecture suffix used by module interfaces.
	End Rem
	Method InterfaceMung:String()
		Return buildMode.ToLower() + "." + targetPlatform.ToLower() + "." + targetArchitecture.ToLower()
	End Method

	Rem
	bbdoc: Derives language snapshot options from this compiler configuration.
	returns: Options suitable for #TBlitzMaxLanguage.BuildAndAnalyze.
	End Rem
	Method SnapshotOptions:TCompilationSnapshotOptions()
		Local result:TCompilationSnapshotOptions = New TCompilationSnapshotOptions
		result.targetPlatform = targetPlatform.ToLower()
		result.conditionalSymbols = conditionalSymbols[..]
		result.parseConfiguredConditionals = True
		If targetPlatform.ToLower() = "pico" And Not sourceModuleName.length Then
			result.implicitImports = ["brl.blitz"]
			If frameworkModule.length And frameworkModule.ToLower() <> "brl.blitz" Then result.implicitImports :+ [frameworkModule.ToLower()]
		Else If applicationBuild Then
			If frameworkModule.length Then
				result.implicitImports = [frameworkModule.ToLower()]
			Else
				result.implicitImports = CompilerDefaultApplicationImports(sdkPath)
			End If
		End If
		result.EnsureConditionalSymbol("bmxng")
		result.EnsureConditionalSymbol("bmxng2")
		result.requireCoreInterface = requireCoreInterface
		result.implicitRuntime = implicitRuntime
		result.sourceModuleName = sourceModuleName.ToLower()
		Return result
	End Method

	Rem
	bbdoc: Rebuilds the conditional-compilation symbol set from the current target options.
	End Rem
	Method RefreshConditionalSymbols()
		conditionalSymbols = CompilerDefaultConditionalSymbols(targetPlatform, targetArchitecture, buildMode, applicationType, threaded, coverageInstrumentation, gdbDebug, musl, userDefinitions)
	End Method
End Type

Rem
bbdoc: Tests whether the compiler supports a platform and architecture combination.
param: The target platform name.
param: The target architecture name.
returns: #True when the target combination is supported.
End Rem
Function CompilerTargetSupported:Int(platform:String, architecture:String)
	Local platformName:String = platform.ToLower()
	Local architectureName:String = architecture.ToLower()
	Select platformName
		Case "win32"
			Return architectureName = "x86" Or architectureName = "x64" Or architectureName = "armv7" Or architectureName = "arm64"
		Case "macos", "osx"
			Return architectureName = "x86" Or architectureName = "x64" Or architectureName = "ppc" Or architectureName = "arm64"
		Case "ios"
			Return architectureName = "x86" Or architectureName = "x64" Or architectureName = "armv7" Or architectureName = "arm64"
		Case "linux"
			Return architectureName = "x86" Or architectureName = "x64" Or architectureName = "arm" Or architectureName = "arm64" Or architectureName = "riscv32" Or architectureName = "riscv64"
		Case "android"
			Return architectureName = "x86" Or architectureName = "x64" Or architectureName = "arm" Or architectureName = "armeabi" Or architectureName = "armeabiv7a" Or architectureName = "arm64v8a"
		Case "raspberrypi"
			Return architectureName = "arm" Or architectureName = "arm64"
		Case "pico"
			Return architectureName = "arm"
		Case "emscripten"
			Return architectureName = "js"
		Case "nx"
			Return architectureName = "arm64"
		Case "haiku"
			Return architectureName = "x86" Or architectureName = "x64" Or architectureName = "arm64"
	End Select
	Return False
End Function

Rem
bbdoc: Builds the standard conditional-compilation symbols for a compiler target.
param: The target platform name.
param: The target architecture name.
param: The build mode, normally `debug` or `release`.
param: The application type, such as `console` or `gui`.
param: Whether threaded runtime support is enabled.
param: Whether coverage instrumentation is enabled.
param: Whether GDB-specific debug support is enabled.
param: Whether the musl C library is targeted.
param: Comma-separated user definitions, optionally using `name=value` form.
returns: The normalized, de-duplicated conditional symbol array.
End Rem
Function CompilerDefaultConditionalSymbols:String[](platform:String, architecture:String, buildMode:String = "release", applicationType:String = "", threaded:Int = True, coverage:Int = False, gdbDebug:Int = False, musl:Int = False, userDefinitions:String = "")
	Local result:String[] = New String[0]
	Local platformName:String = platform.ToLower()
	Local architectureName:String = architecture.ToLower()
	AddCompilerConditional(result, platformName)
	AddCompilerConditional(result, architectureName)
	AddCompilerConditional(result, "bmxng")
	AddCompilerConditional(result, "bmxng2")
	If buildMode.ToLower() = "debug" Then AddCompilerConditional(result, "debug")
	If threaded Then AddCompilerConditional(result, "threaded")
	If coverage Then AddCompilerConditional(result, "coverage")
	If gdbDebug Then AddCompilerConditional(result, "gdbdebug")
	If applicationType.ToLower() = "console" Then AddCompilerConditional(result, "console")
	If applicationType.ToLower() = "gui" Then AddCompilerConditional(result, "gui")

	' BlitzMax source convention predates the current bmk platform spelling:
	' macOS builds expose both names, and SDK modules commonly select their
	' implementation with ?osx.
	If platformName = "macos" Or platformName = "osx" Or platformName = "ios" Then
		AddCompilerConditional(result, "macos")
		If architectureName = "x86" Or architectureName = "x64" Or architectureName = "arm64" Then AddCompilerConditional(result, "macos" + architectureName)
		If architectureName = "ppc" And platformName <> "ios" Then AddCompilerConditional(result, "macosppc")
	End If
	If platformName = "macos" Or platformName = "osx" Then
		AddCompilerConditional(result, "osx")
		If architectureName = "x86" Or architectureName = "x64" Or architectureName = "ppc" Or architectureName = "arm64" Then AddCompilerConditional(result, "osx" + architectureName)
	End If
	If platformName = "ios" Then
		If architectureName = "x86" Or architectureName = "x64" Or architectureName = "armv7" Or architectureName = "arm64" Then AddCompilerConditional(result, "ios" + architectureName)
	End If
	If platformName = "win32" Or platformName = "win64" Then
		If platformName = "win32" And architectureName = "x86" Then AddCompilerConditional(result, "win32x86")
		If architectureName = "x64" Then AddCompilerConditional(result, "win32x64")
		If platformName = "win32" And architectureName = "armv7" Then AddCompilerConditional(result, "win32armv7")
		If platformName = "win32" And architectureName = "arm64" Then AddCompilerConditional(result, "win32arm64")
		If architectureName = "x64" Or (platformName = "win32" And architectureName = "arm64") Then AddCompilerConditional(result, "win64")
	End If
	If platformName = "linux" Or platformName = "android" Or platformName = "raspberrypi" Then
		AddCompilerConditional(result, "linux")
		If (platformName = "linux" Or platformName = "android") And architectureName = "x86" Then AddCompilerConditional(result, "linuxx86")
		If (platformName = "linux" Or platformName = "android") And architectureName = "x64" Then AddCompilerConditional(result, "linuxx64")
		If ((platformName = "linux" Or platformName = "android") And (architectureName = "arm" Or architectureName = "armeabi" Or architectureName = "armeabiv7a" Or architectureName = "arm64v8a")) Or (platformName = "raspberrypi" And architectureName = "arm") Then AddCompilerConditional(result, "linuxarm")
		If (platformName = "android" And architectureName = "arm64v8a") Or ((platformName = "linux" Or platformName = "raspberrypi") And architectureName = "arm64") Then AddCompilerConditional(result, "linuxarm64")
		If platformName = "linux" And (architectureName = "riscv32" Or architectureName = "riscv64") Then AddCompilerConditional(result, "linux" + architectureName)
	End If
	If platformName = "android" Then
		If architectureName = "x86" Or architectureName = "x64" Or architectureName = "armeabi" Or architectureName = "armeabiv7a" Or architectureName = "arm64v8a" Then AddCompilerConditional(result, "android" + architectureName)
		If architectureName = "arm" Or architectureName = "armeabi" Or architectureName = "armeabiv7a" Or architectureName = "arm64v8a" Then AddCompilerConditional(result, "androidarm")
	End If
	If platformName = "raspberrypi" And (architectureName = "arm" Or architectureName = "arm64") Then AddCompilerConditional(result, "raspberrypi" + architectureName)
	If platformName = "pico" And architectureName = "arm" Then AddCompilerConditional(result, "picoarm")
	If platformName = "haiku" And (architectureName = "x86" Or architectureName = "x64" Or architectureName = "arm64") Then AddCompilerConditional(result, "haiku" + architectureName)
	If platformName = "emscripten" And architectureName = "js" Then AddCompilerConditional(result, "emscriptenjs")
	If platformName = "nx" And architectureName = "arm64" Then AddCompilerConditional(result, "nxarm64")
	If architectureName = "armeabi" Or architectureName = "armeabiv7a" Or architectureName = "arm64v8a" Then
		AddCompilerConditional(result, "arm")
	End If
	Local pointer64:Int = architectureName = "x64" Or architectureName = "arm64" Or architectureName = "arm64v8a" Or architectureName = "riscv64"
	If pointer64 Then AddCompilerConditional(result, "ptr64") Else AddCompilerConditional(result, "ptr32")
	' LongInt follows the selected native C long ABI: Windows, Pico's ILP32 Arm
	' ABI, and the legacy 32-bit x86/PPC targets use four bytes.
	Local longInt8:Int = platformName <> "win32" And platformName <> "win64" And platformName <> "pico" And architectureName <> "x86" And architectureName <> "ppc"
	If longInt8 Then
		AddCompilerConditional(result, "longint8")
		AddCompilerConditional(result, "ulongint8")
	Else
		AddCompilerConditional(result, "longint4")
		AddCompilerConditional(result, "ulongint4")
	End If
	If architectureName = "ppc" Then AddCompilerConditional(result, "bigendian") Else AddCompilerConditional(result, "littleendian")
	If platformName = "android" Or platformName = "raspberrypi" Or platformName = "emscripten" Or platformName = "ios" Then AddCompilerConditional(result, "opengles")
	If musl And (platformName = "linux" Or platformName = "android" Or platformName = "raspberrypi") Then AddCompilerConditional(result, "musl")
	For Local definition:String = EachIn userDefinitions.Split(",")
		definition = definition.Trim().ToLower()
		If Not definition.length Then Continue
		Local separator:Int = definition.Find("=")
		If separator < 0 Then
			AddCompilerConditional(result, definition)
		Else If Int(definition[separator + 1..].Trim()) <> 0 Then
			AddCompilerConditional(result, definition[..separator].Trim())
		End If
	Next
	Return result
End Function

Function AddCompilerConditional(symbols:String[] Var, name:String)
	name = name.Trim().ToLower()
	If Not name.length Then Return
	For Local existing:String = EachIn symbols
		If existing.ToLower() = name Then Return
	Next
	symbols :+ [name]
End Function

Function CompilerDefaultApplicationImports:String[](sdkPath:String)
	Local result:String[] = New String[0]
	CollectCompilerApplicationImports(result, sdkPath, "brl")
	CollectCompilerApplicationImports(result, sdkPath, "pub")
	' Keep the implicit import order independent of filesystem enumeration.
	For Local index:Int = 1 Until result.length
		Local value:String = result[index]
		Local position:Int = index
		While position > 0 And result[position - 1] > value
			result[position] = result[position - 1]
			position :- 1
		Wend
		result[position] = value
	Next
	Return result
End Function

Function CollectCompilerApplicationImports(result:String[] Var, sdkPath:String, namespaceName:String)
	Local namespaceRoot:String = CompilerOptionsNormalizePath(sdkPath) + "/mod/" + namespaceName + ".mod"
	If FileType(namespaceRoot) <> FILETYPE_DIR Then Return
	For Local directoryName:String = EachIn LoadDir(namespaceRoot)
		If Not directoryName.ToLower().EndsWith(".mod") Then Continue
		Local identifier:String = directoryName[..directoryName.length - 4].ToLower()
		If namespaceName = "brl" And (identifier = "blitz" Or identifier = "appstub") Then Continue
		Local sourcePath:String = namespaceRoot + "/" + directoryName + "/" + identifier + ".bmx"
		If FileType(sourcePath) = FILETYPE_FILE Then result :+ [namespaceName + "." + identifier]
	Next
End Function

Function CompilerOptionsNormalizePath:String(path:String)
	If Not path.length Then Return ""
	Local resolved:String = RealPath(path)
	If resolved.length Then Return resolved.Replace("\", "/")
	Return path.Replace("\", "/")
End Function

Function CompilerHostPlatform:String()
	?win32
	Return "win32"
	?macos
	Return "macos"
	?linux
	Return "linux"
	?haiku
	Return "haiku"
	?android
	Return "android"
	?Not win32 And Not macos And Not linux And Not haiku And Not android
	Return ""
	?
End Function

Function CompilerHostArchitecture:String()
	?arm64
	Return "arm64"
	?x64
	Return "x64"
	?x86
	Return "x86"
	?arm
	Return "arm"
	?ppc64
	Return "ppc64"
	?Not arm64 And Not x64 And Not x86 And Not arm And Not ppc64
	Return ""
	?
End Function
