' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Stream
Import Text.Json

Const JSONRPC_PARSE_ERROR:Int = -32700
Const JSONRPC_INVALID_REQUEST:Int = -32600
Const JSONRPC_METHOD_NOT_FOUND:Int = -32601
Const JSONRPC_INTERNAL_ERROR:Int = -32603

Rem
bbdoc: Reads and writes byte-accurate Language Server Protocol messages over streams.
about: Messages use the LSP Base Protocol `Content-Length` framing and UTF-8 JSON payloads.
End Rem
Type TLspTransport
	Field input:TStream
	Field output:TStream
	Field reachedEof:Int

	Rem
	bbdoc: Creates an LSP transport over separate input and output streams.
	param: The stream from which framed requests are read.
	param: The stream to which framed responses are written.
	returns: A new transport.
	End Rem
	Function Create:TLspTransport(input:TStream, output:TStream)
		Local transport:TLspTransport = New TLspTransport
		transport.input = input
		transport.output = output
		Return transport
	End Function

	Rem
	bbdoc: Reads and decodes the next framed LSP message.
	returns: The UTF-8 JSON payload, or #Null after end of input.
	End Rem
	Method ReadMessage:String()
		reachedEof = False
		Local contentLength:Int = -1
		While True
			Local line:String = ReadHeaderLine()
			If reachedEof Then Return Null
			If line.length = 0 Then Exit
			Local separator:Int = line.Find(":")
			If separator < 0 Then Continue
			Local name:String = line[..separator].Trim().ToLower()
			If name = "content-length" Then contentLength = Int(line[separator + 1..].Trim())
		Wend
		If contentLength < 0 Then Throw "LSP message has no Content-Length header"
		If contentLength = 0 Then Return ""
		Local bytes:Byte[contentLength]
		input.ReadBytes(bytes, contentLength)
		Return String.FromUTF8Bytes(bytes, contentLength)
	End Method

	Rem
	bbdoc: Encodes and writes one framed LSP message.
	param: The JSON payload to write as UTF-8.
	End Rem
	Method WriteMessage(json:String)
		Local bytes:Byte Ptr = json.ToUTF8String()
		Local length:Int = strlen_(bytes)
		Local header:String = "Content-Length: " + length + "~r~n~r~n"
		output.WriteString(header)
		output.WriteBytes(bytes, length)
		output.Flush()
		MemFree(bytes)
	End Method

	Method ReadHeaderLine:String()
		Local line:String
		While True
			Local value:Byte
			If input.Read(Varptr value, 1) = 0 Then
				reachedEof = True
				Return line
			End If
			If value = 10 Then Return line
			If value <> 13 Then line :+ Chr(value)
		Wend
	End Method
End Type

Rem
bbdoc: Creates an empty JSON object.
End Rem
Function JsonObject:TJSONObject()
	Return New TJSONObject.Create()
End Function

Rem
bbdoc: Creates an empty JSON array.
End Rem
Function JsonArray:TJSONArray()
	Return New TJSONArray.Create()
End Function

Rem
bbdoc: Creates a JSON null value.
End Rem
Function JsonNull:TJSONNull()
	Return New TJSONNull.Create()
End Function

Rem
bbdoc: Creates a successful JSON-RPC response object.
param: The request identifier.
param: The result value, or #Null for a JSON null result.
returns: The response object.
End Rem
Function JsonResponse:TJSONObject(id:TJSON, result:TJSON)
	Local response:TJSONObject = JsonObject()
	response.Set("jsonrpc", "2.0")
	If id Then response.Set("id", id) Else response.Set("id", JsonNull())
	If result Then response.Set("result", result) Else response.Set("result", JsonNull())
	Return response
End Function

Rem
bbdoc: Creates a JSON-RPC error response object.
param: The request identifier.
param: The JSON-RPC error code.
param: The human-readable error message.
returns: The error response object.
End Rem
Function JsonErrorResponse:TJSONObject(id:TJSON, code:Int, message:String)
	Local errorObject:TJSONObject = JsonObject()
	errorObject.Set("code", code)
	errorObject.Set("message", message)
	Local response:TJSONObject = JsonObject()
	response.Set("jsonrpc", "2.0")
	If id Then response.Set("id", id) Else response.Set("id", JsonNull())
	response.Set("error", errorObject)
	Return response
End Function

Rem
bbdoc: Creates a JSON-RPC notification object.
param: The notification method name.
param: The optional notification parameters.
returns: The notification object.
End Rem
Function JsonNotification:TJSONObject(methodName:String, params:TJSON)
	Local notification:TJSONObject = JsonObject()
	notification.Set("jsonrpc", "2.0")
	notification.Set("method", methodName)
	If params Then notification.Set("params", params)
	Return notification
End Function
