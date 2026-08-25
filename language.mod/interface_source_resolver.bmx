' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import BRL.TextStream

Import "interface_model.bmx"
Import "interface_parser.bmx"

Const INTERFACE_SOURCE_MAX_DEPTH:Int = 8

Type TInterfaceSourceLocation
	Field path:String
	Field line:Int
	Field column:Int

	Function Create:TInterfaceSourceLocation(path:String, line:Int, column:Int)
		Local result:TInterfaceSourceLocation = New TInterfaceSourceLocation
		result.path = path
		result.line = line
		result.column = column
		Return result
	End Function
End Type

' Follows compiler @source metadata through generated per-source interfaces.
' Resolution is deterministic and bounded: a missing, malformed, or cyclic
' hop leaves the last valid generated location intact for consumers to reject.
Type TInterfaceSourceResolver
	Field interfaceSources:TMap = New TMap
	Field unavailable:TMap = New TMap

	Method Resolve:TInterfaceSourceLocation(interfacePath:String, record:TInterfaceRecord)
		If Not record Then Return TInterfaceSourceLocation.Create(interfacePath, 0, 0)
		If Not record.originPath.length Then Return TInterfaceSourceLocation.Create(interfacePath, record.originLine, record.originColumn)
		Local currentInterface:String = interfacePath
		Local sourcePath:String = record.originPath
		Local sourceLine:Int = record.originLine
		Local sourceColumn:Int = record.originColumn
		Local result:TInterfaceSourceLocation
		Local seen:TMap = New TMap

		For Local depth:Int = 0 Until INTERFACE_SOURCE_MAX_DEPTH
			Local resolvedPath:String = ResolvePath(currentInterface, sourcePath)
			result = TInterfaceSourceLocation.Create(resolvedPath, sourceLine, sourceColumn)
			If Not IsInterfacePath(resolvedPath) Or sourceLine <= 0 Then Return result
			Local key:String = resolvedPath.Replace("\", "/").ToLower() + "|" + sourceLine
			If seen.Contains(key) Then Return result
			seen.Insert(key, result)
			Local source:TSourceText = LoadInterfaceSource(resolvedPath)
			If Not source Then Return result
			Local rawLine:String = LineAtSource(source, sourceLine)
			If rawLine = Null Then Return result
			Local nextPath:String
			Local nextLine:Int
			Local nextColumn:Int
			If Not ExtractSourceMetadata(rawLine, nextPath, nextLine, nextColumn) Then Return result
			currentInterface = resolvedPath
			sourcePath = nextPath
			sourceLine = nextLine
			sourceColumn = nextColumn
		Next
		Return result
	End Method

	Method LoadInterfaceText:String(path:String)
		Local source:TSourceText = LoadInterfaceSource(path)
		If source Then Return source.text
		Return Null
	End Method

	Method LoadInterfaceSource:TSourceText(path:String)
		Local key:String = path.Replace("\", "/").ToLower()
		If unavailable.Contains(key) Then Return Null
		Local cached:TSourceText = TSourceText(interfaceSources.ValueForKey(key))
		If cached Then Return cached
		If FileType(path) <> FILETYPE_FILE Then
			unavailable.Insert(key, key)
			Return Null
		End If
		Local source:TSourceText = TSourceText.Create(LoadText(path), path)
		interfaceSources.Insert(key, source)
		Return source
	End Method

	Function ResolvePath:String(interfacePath:String, sourcePath:String)
		Local normalized:String = sourcePath.Replace("\", "/")
		If normalized.StartsWith("/") Then
			Local rebasedAbsolute:String = RebaseModuleSource(interfacePath, normalized)
			If rebasedAbsolute.length Then Return rebasedAbsolute
			Local resolvedAbsolute:String = RealPath(normalized)
			If resolvedAbsolute.length Then Return resolvedAbsolute.Replace("\", "/")
			Return normalized
		End If
		?win32
		If normalized.length > 1 And normalized[1] = 58 Then
			Local rebasedWindowsAbsolute:String = RebaseModuleSource(interfacePath, normalized)
			If rebasedWindowsAbsolute.length Then Return rebasedWindowsAbsolute
			Local resolvedWindowsAbsolute:String = RealPath(normalized)
			If resolvedWindowsAbsolute.length Then Return resolvedWindowsAbsolute.Replace("\", "/")
			Return normalized
		End If
		?
		Local base:String = ExtractDir(interfacePath.Replace("\", "/"))
		If StripDir(base).ToLower() = ".bmx" Then base = ExtractDir(base)
		Local candidate:String = base + "/" + normalized
		Local resolved:String = RealPath(candidate)
		If resolved.length Then Return resolved.Replace("\", "/")
		Return candidate
	End Function

	Function RebaseModuleSource:String(interfacePath:String, sourcePath:String)
		Local moduleDirectory:String = ExtractDir(interfacePath.Replace("\", "/"))
		If StripDir(moduleDirectory).ToLower() = ".bmx" Then moduleDirectory = ExtractDir(moduleDirectory)
		Local moduleDirectoryName:String = StripDir(moduleDirectory)
		If Not moduleDirectoryName.ToLower().EndsWith(".mod") Then Return ""
		Local marker:String = "/" + moduleDirectoryName.ToLower() + "/"
		Local normalizedSource:String = sourcePath.Replace("\", "/")
		Local markerIndex:Int = normalizedSource.ToLower().Find(marker)
		If markerIndex < 0 Then Return ""
		Local relativeStart:Int = markerIndex + marker.length
		Local candidate:String = moduleDirectory + "/" + normalizedSource[relativeStart..]
		If FileType(candidate) <> FILETYPE_FILE Then Return ""
		Local resolved:String = RealPath(candidate)
		If resolved.length Then Return resolved.Replace("\", "/")
		Return candidate
	End Function

	Function IsInterfacePath:Int(path:String)
		Local lower:String = path.ToLower()
		Return lower.EndsWith(".i") Or lower.EndsWith(".i2")
	End Function

	Function LineAt:String(text:String, oneBasedLine:Int)
		Local source:TSourceText = TSourceText.Create(text)
		Return LineAtSource(source, oneBasedLine)
	End Function

	Function LineAtSource:String(source:TSourceText, oneBasedLine:Int)
		If Not source Or oneBasedLine <= 0 Then Return Null
		If oneBasedLine > source.LineCount() Then Return Null
		Local start:Int = source.Offset(oneBasedLine - 1, 0)
		Local finish:Int = source.Offset(oneBasedLine - 1, 2147483647)
		Return source.text[start..finish]
	End Function

	Function ExtractSourceMetadata:Int(text:String, path:String Var, line:Int Var, column:Int Var)
		Local marker:Int = text.ToLower().Find("'@source")
		If marker < 0 Then Return False
		Local payload:String = text[marker + 8..].Trim()
		Local parts:String[] = TInterfaceFileParser.SplitQuoted(payload, ",")
		If parts.length = 0 Then Return False
		path = TInterfaceFileParser.Unquote(parts[0].Trim())
		If Not path.length Then Return False
		If parts.length > 1 Then line = Int(parts[1].Trim())
		If parts.length > 2 Then column = Int(parts[2].Trim())
		Return True
	End Function
End Type
