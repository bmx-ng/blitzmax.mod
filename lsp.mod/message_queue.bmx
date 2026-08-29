' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.Threads
Import Text.Json
Import BlitzMax.Language

Import "protocol.bmx"

Const LSP_CHANGE_DEBOUNCE_MS:Int = 200
Const LSP_WATCH_DEBOUNCE_MS:Int = 75

Type TLspQueuedMessage
	Field payload:String
	Field methodName:String
	Field documentUri:String
	Field documentVersion:Int = -1
	Field requestId:TJSON
	Field requestKey:String
	Field readyAt:Int

	Function Parse:TLspQueuedMessage(payload:String, debounceMs:Int, watchDebounceMs:Int)
		Local error:TJSONError
		Local request:TJSONObject = TJSONObject(TJSON.Load(payload, 0, error))
		Local result:TLspQueuedMessage = New TLspQueuedMessage
		result.payload = payload
		If Not request Then Return result
		result.methodName = request.GetString("method")
		result.requestId = request.Get("id")
		result.requestKey = IdKey(result.requestId)
		Local params:TJSONObject = TJSONObject(request.Get("params"))
		Local document:TJSONObject
		If params Then document = TJSONObject(params.Get("textDocument"))
		If document Then
			result.documentUri = document.GetString("uri")
			If document.Get("version") Then result.documentVersion = Int(document.GetInteger("version"))
		End If
		' Resolve and follow-up hierarchy requests carry their originating
		' document in item data instead of textDocument.
		If Not result.documentUri.length And params Then
			Local data:TJSONObject = TJSONObject(params.Get("data"))
			If data Then result.documentUri = data.GetString("uri")
			If Not result.documentUri.length Then
				Local item:TJSONObject = TJSONObject(params.Get("item"))
				If item Then data = TJSONObject(item.Get("data"))
				If data Then
					result.documentUri = data.GetString("analysisUri")
					If Not result.documentUri.length Then result.documentUri = data.GetString("uri")
				End If
			End If
		End If
		If result.methodName = "textDocument/didChange" Then result.readyAt = MilliSecs() + Max(0, debounceMs)
		If result.methodName = "workspace/didChangeWatchedFiles" Then result.readyAt = MilliSecs() + Max(0, watchDebounceMs)
		Return result
	End Function

	Function IdKey:String(id:TJSON)
		If Not id Then Return ""
		Local integer:TJSONInteger = TJSONInteger(id)
		If integer Then Return "n:" + integer.Value()
		Local text:TJSONString = TJSONString(id)
		If text Then Return "s:" + text.Value()
		Return id.SaveString(JSON_COMPACT)
	End Function
End Type

' Thread-safe protocol inbox. didChange notifications for the same document
' are collapsed while queued, even when obsolete feature requests sit between
' them. Foreground editor requests may overtake automatic background requests
' within a stable document generation. Document lifecycle and protocol or
' configuration messages remain global ordering barriers so cross-file live
' dependencies can never be observed at a stale generation.
Type TLspMessageQueue
	Field messages:TLspQueuedMessage[] = New TLspQueuedMessage[0]
	Field canceled:TMap = New TMap
	Field activeRequestKey:String
	Field mutex:TMutex = TMutex.Create()
	Field changed:TCondVar = TCondVar.Create()
	Field closed:Int
	Field debounceMs:Int
	Field watchDebounceMs:Int

	Method New(debounceMs:Int = LSP_CHANGE_DEBOUNCE_MS, watchDebounceMs:Int = LSP_WATCH_DEBOUNCE_MS)
		Self.debounceMs = Max(0, debounceMs)
		Self.watchDebounceMs = Max(0, watchDebounceMs)
	End Method

	Method Enqueue(payload:String)
		Local message:TLspQueuedMessage = TLspQueuedMessage.Parse(payload, debounceMs, watchDebounceMs)
		mutex.Lock()
		If closed Then
			mutex.Unlock()
			Return
		End If
		If message.methodName = "workspace/didChangeWatchedFiles" And messages.length Then
			Local existing:TLspQueuedMessage = messages[messages.length - 1]
			If existing.methodName = message.methodName Then
				existing.payload = MergeWatchedFilePayload(existing.payload, message.payload)
				existing.readyAt = message.readyAt
				changed.Broadcast()
				mutex.Unlock()
				Return
			End If
		End If
		If message.methodName = "$/cancelRequest" Then
			Local error:TJSONError
			Local request:TJSONObject = TJSONObject(TJSON.Load(payload, 0, error))
			Local params:TJSONObject
			If request Then params = TJSONObject(request.Get("params"))
			Local key:String
			If params Then key = TLspQueuedMessage.IdKey(params.Get("id"))
			Local known:Int = key.length And key = activeRequestKey
			If key.length And Not known Then
				For Local pending:TLspQueuedMessage = EachIn messages
					If pending.requestKey = key Then known = True; Exit
				Next
			End If
			If known Then canceled.Insert(key, key)
			changed.Broadcast()
			mutex.Unlock()
			Return
		End If
		If message.methodName = "textDocument/didChange" And message.documentUri.length Then
			For Local index:Int = messages.length - 1 To 0 Step -1
				Local existing:TLspQueuedMessage = messages[index]
				If IsOrderingBarrier(existing.methodName) Then Exit
				If existing.documentUri <> message.documentUri Then Continue
				If existing.methodName = "textDocument/didOpen" Or existing.methodName = "textDocument/didClose" Then Exit
				If existing.methodName = "textDocument/didChange" Then
					messages[index] = message
					changed.Broadcast()
					mutex.Unlock()
					Return
				End If
			Next
		End If
		messages :+ [message]
		changed.Signal()
		mutex.Unlock()
	End Method

	Function IsOrderingBarrier:Int(methodName:String)
		Select methodName
			Case "initialize", "initialized", "shutdown", "exit", "workspace/didChangeConfiguration", "workspace/didChangeWatchedFiles", "workspace/didChangeWorkspaceFolders"
				Return True
		End Select
		Return False
	End Function

	Method Dequeue:TLspQueuedMessage()
		mutex.Lock()
		While True
			While messages.length = 0 And Not closed
				changed.Wait(mutex)
			Wend
			If messages.length = 0 And closed Then
				mutex.Unlock()
				Return Null
			End If
			Local index:Int = NextMessageIndex()
			Local message:TLspQueuedMessage = messages[index]
			If message.readyAt > 0 Then
				Local remaining:Int = message.readyAt - MilliSecs()
				If remaining > 0 Then
					changed.TimedWait(mutex, remaining)
					Continue
				End If
			End If
			RemoveAt(index)
			activeRequestKey = message.requestKey
			mutex.Unlock()
			Return message
		Wend
	End Method

	Function MergeWatchedFilePayload:String(firstPayload:String, secondPayload:String)
		Local firstError:TJSONError
		Local first:TJSONObject = TJSONObject(TJSON.Load(firstPayload, 0, firstError))
		Local secondError:TJSONError
		Local second:TJSONObject = TJSONObject(TJSON.Load(secondPayload, 0, secondError))
		If Not first Or Not second Then Return secondPayload
		Local firstParams:TJSONObject = TJSONObject(first.Get("params"))
		Local secondParams:TJSONObject = TJSONObject(second.Get("params"))
		If Not firstParams Or Not secondParams Then Return secondPayload
		Local firstChanges:TJSONArray = TJSONArray(firstParams.Get("changes"))
		Local secondChanges:TJSONArray = TJSONArray(secondParams.Get("changes"))
		If Not firstChanges Or Not secondChanges Then Return secondPayload
		Local order:String[]
		Local latest:TMap = New TMap
		AppendWatchedChanges(order, latest, firstChanges)
		AppendWatchedChanges(order, latest, secondChanges)
		Local merged:TJSONArray = JsonArray()
		For Local uri:String = EachIn order
			merged.Append(TJSON(latest.ValueForKey(uri)))
		Next
		firstParams.Set("changes", merged)
		Return first.SaveString(JSON_COMPACT)
	End Function

	Function AppendWatchedChanges(order:String[] Var, latest:TMap, changes:TJSONArray)
		For Local index:Int = 0 Until changes.Size()
			Local change:TJSONObject = TJSONObject(changes.Get(index))
			If Not change Then Continue
			Local uri:String = change.GetString("uri")
			If Not latest.Contains(uri) Then order :+ [uri]
			latest.Insert(uri, change)
		Next
	End Function

	Method NextMessageIndex:Int()
		If messages.length < 2 Or IsOrderingBarrier(messages[0].methodName) Or IsDocumentLifecycle(messages[0].methodName) Then Return 0
		Local bestIndex:Int = -1
		Local bestPriority:Int = -1
		For Local index:Int = 0 Until messages.length
			Local message:TLspQueuedMessage = messages[index]
			If IsOrderingBarrier(message.methodName) Or IsDocumentLifecycle(message.methodName) Then Exit
			Local priority:Int = RequestPriority(message)
			If priority <= bestPriority Then Continue
			bestIndex = index
			bestPriority = priority
		Next
		If bestIndex >= 0 Then Return bestIndex
		Return 0
	End Method

	Function RequestPriority:Int(message:TLspQueuedMessage)
		If Not message Or Not message.requestKey.length Then Return 0
		Select message.methodName
			Case "textDocument/hover", "textDocument/completion", "completionItem/resolve", "textDocument/definition", "textDocument/typeDefinition", "textDocument/implementation", "textDocument/documentHighlight", "textDocument/references", "textDocument/signatureHelp", "textDocument/codeAction", "textDocument/prepareRename", "textDocument/rename", "textDocument/selectionRange", "textDocument/prepareTypeHierarchy", "typeHierarchy/supertypes", "typeHierarchy/subtypes", "textDocument/prepareCallHierarchy", "callHierarchy/incomingCalls", "callHierarchy/outgoingCalls", "workspace/symbol"
				Return 2
		End Select
		Return 1
	End Function

	Function IsDocumentLifecycle:Int(methodName:String)
		Return methodName = "textDocument/didOpen" Or methodName = "textDocument/didChange" Or methodName = "textDocument/didClose"
	End Function

	Method IsCanceled:Int(requestKey:String)
		If Not requestKey.length Then Return False
		mutex.Lock()
		Local result:Int = canceled.Contains(requestKey)
		mutex.Unlock()
		Return result
	End Method

	Method CompleteRequest(requestKey:String)
		If Not requestKey.length Then Return
		mutex.Lock()
		canceled.Remove(requestKey)
		If activeRequestKey = requestKey Then activeRequestKey = ""
		mutex.Unlock()
	End Method

	Method HasNewerDocumentVersion:Int(uri:String, version:Int)
		If Not uri.length Then Return False
		mutex.Lock()
		Local result:Int
		For Local message:TLspQueuedMessage = EachIn messages
			If message.methodName = "textDocument/didChange" And message.documentUri = uri And message.documentVersion > version Then
				result = True
				Exit
			End If
		Next
		mutex.Unlock()
		Return result
	End Method

	Method PendingCount:Int()
		mutex.Lock()
		Local result:Int = messages.length
		mutex.Unlock()
		Return result
	End Method

	Method Close()
		mutex.Lock()
		closed = True
		changed.Broadcast()
		mutex.Unlock()
	End Method

	Method RemoveAt(index:Int)
		For Local offset:Int = index Until messages.length - 1
			messages[offset] = messages[offset + 1]
		Next
		messages = messages[..messages.length - 1]
	End Method
End Type

Type TLspDocumentVersionCancellation Extends TLanguageCancellationToken
	Field queue:TLspMessageQueue
	Field uri:String
	Field version:Int

	Function Create:TLspDocumentVersionCancellation(queue:TLspMessageQueue, uri:String, version:Int)
		Local result:TLspDocumentVersionCancellation = New TLspDocumentVersionCancellation
		result.queue = queue
		result.uri = uri
		result.version = version
		Return result
	End Function

	Method IsCancellationRequested:Int() Override
		Return queue And queue.HasNewerDocumentVersion(uri, version)
	End Method
End Type

Type TLspTransportReader
	Field transport:TLspTransport
	Field queue:TLspMessageQueue

	Function Create:TLspTransportReader(transport:TLspTransport, queue:TLspMessageQueue)
		Local result:TLspTransportReader = New TLspTransportReader
		result.transport = transport
		result.queue = queue
		Return result
	End Function

	Function ReadLoop:Object(value:Object)
		Local reader:TLspTransportReader = TLspTransportReader(value)
		Try
			While True
				Local payload:String = reader.transport.ReadMessage()
				If payload = Null Then Exit
				reader.queue.Enqueue(payload)
			Wend
		Catch exception:Object
		End Try
		reader.queue.Close()
		Return Null
	End Function
End Type
