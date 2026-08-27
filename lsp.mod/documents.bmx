' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import BRL.TextStream

Type TLspDocument
	Field uri:String
	Field path:String
	Field languageId:String
	Field version:Int
	Field text:String
	Field workspaceUri:String
	' An unmodified source opened for navigation remains passive. It becomes a
	' live Include/quoted-Import overlay after an editor change, or immediately
	' when the didOpen text already differs from the file on disk.
	Field liveOverlay:Int
End Type

Type TLspDocumentStore
	Field documents:TMap = New TMap
	Field documentsByPath:TMap = New TMap
	Field documentCount:Int

	Method Open:TLspDocument(uri:String, languageId:String, version:Int, text:String)
		Local previous:TLspDocument = Get(uri)
		If Not previous Then
			documentCount :+ 1
		Else If GetByPath(previous.path) = previous Then
			documentsByPath.Remove(DocumentPathKey(previous.path))
		End If
		Local document:TLspDocument = New TLspDocument
		document.uri = uri
		document.path = CanonicalDocumentPath(FileUriToPath(uri))
		document.languageId = languageId
		document.version = version
		document.text = text
		document.liveOverlay = TextDiffersFromDisk(document.path, text)
		documents.Insert(uri, document)
		documentsByPath.Insert(DocumentPathKey(document.path), document)
		Return document
	End Method

	Method Change:TLspDocument(uri:String, version:Int, text:String)
		Local document:TLspDocument = Get(uri)
		If Not document Then Return Null
		document.version = version
		document.text = text
		document.liveOverlay = True
		Return document
	End Method

	Method Close:TLspDocument(uri:String)
		Local document:TLspDocument = Get(uri)
		If document Then
			documents.Remove(uri)
			If GetByPath(document.path) = document Then documentsByPath.Remove(DocumentPathKey(document.path))
			documentCount :- 1
		End If
		Return document
	End Method

	Method Get:TLspDocument(uri:String)
		Return TLspDocument(documents.ValueForKey(uri))
	End Method

	Method GetByPath:TLspDocument(path:String)
		Return TLspDocument(documentsByPath.ValueForKey(DocumentPathKey(path)))
	End Method

	Method Count:Int()
		Return documentCount
	End Method
End Type

Function TextDiffersFromDisk:Int(path:String, text:String)
	If FileType(path) <> FILETYPE_FILE Then Return True
	Return LoadText(path) <> text
End Function

Function CanonicalDocumentPath:String(path:String)
	Local resolved:String = RealPath(path)
	If resolved.length Then Return NormalizeWorkspacePath(resolved)
	Return NormalizeWorkspacePath(path)
End Function

Function DocumentPathKey:String(path:String)
	Local result:String = NormalizeWorkspacePath(path)
	?win32
	result = result.ToLower()
	?
	Return result
End Function

Function FileUriToPath:String(uri:String)
	If uri.ToLower().StartsWith("file://") Then
		Local path:String = uri[7..]
		If path.StartsWith("localhost/") Then path = path[9..]
		path = PercentDecode(path)
		?win32
		If path.length > 2 And path[0] = 47 And path[2] = 58 Then path = path[1..]
		?
		Return path
	End If
	Return uri
End Function

' Produces a standards-compliant file URI for Markdown links and protocol
' locations. Encode UTF-8 bytes rather than String characters so non-ASCII
' source paths round-trip through FileUriToPath.
Function FileUriForPath:String(path:String)
	If path.ToLower().StartsWith("file://") Then Return path
	Local normalized:String = path.Replace("\", "/")
	?win32
	If normalized.length > 1 And normalized[0] <> 47 And normalized[1] = 58 Then normalized = "/" + normalized
	?
	Local source:Byte Ptr = normalized.ToUTF8String()
	Local result:String = "file://"
	Local digits:String = "0123456789ABCDEF"
	Local index:Int
	While source[index]
		Local value:Int = source[index] & 255
		If (value >= 65 And value <= 90) Or (value >= 97 And value <= 122) Or (value >= 48 And value <= 57) Or value = 45 Or value = 46 Or value = 47 Or value = 58 Or value = 95 Or value = 126 Then
			result :+ Chr(value)
		Else
			Local high:Int = (value Shr 4) & 15
			Local low:Int = value & 15
			result :+ "%" + digits[high..high + 1] + digits[low..low + 1]
		End If
		index :+ 1
	Wend
	MemFree(source)
	Return result
End Function

Function PercentDecode:String(value:String)
	Local bytes:Byte[]
	Local index:Int
	While index < value.length
		If value[index] = 37 And index + 2 < value.length Then
			Local high:Int = HexDigit(value[index + 1])
			Local low:Int = HexDigit(value[index + 2])
			If high >= 0 And low >= 0 Then
				bytes :+ [Byte(high * 16 + low)]
				index :+ 3
				Continue
			End If
		End If
		bytes :+ [Byte(value[index])]
		index :+ 1
	Wend
	Return String.FromUTF8Bytes(bytes, bytes.length)
End Function

Function HexDigit:Int(value:Int)
	If value >= 48 And value <= 57 Then Return value - 48
	If value >= 65 And value <= 70 Then Return value - 65 + 10
	If value >= 97 And value <= 102 Then Return value - 97 + 10
	Return -1
End Function

Function NormalizeWorkspacePath:String(path:String)
	Local result:String = path.Replace("\", "/")
	While result.length > 1 And result.EndsWith("/")
		result = result[..result.length - 1]
	Wend
	?win32
	result = result.ToLower()
	?
	Return result
End Function
