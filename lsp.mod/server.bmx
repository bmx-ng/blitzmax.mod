' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import Text.Json
Import "protocol.bmx"
Import "message_queue.bmx"
Import "documents.bmx"
Import "workspaces.bmx"
Import "diagnostics.bmx"
Import "hover.bmx"
Import "completion.bmx"
Import "semantic_tokens.bmx"
Import "inlay_hints.bmx"
Import "navigation_features.bmx"
Import "type_hierarchy.bmx"
Import "implementation.bmx"
Import "folding_ranges.bmx"
Import "selection_ranges.bmx"
Import "workspace_symbols.bmx"
Import "rename.bmx"
Import "document_links.bmx"
Import "references.bmx"
Import "code_actions.bmx"

Const LSP_STATE_CREATED:Int = 0
Const LSP_STATE_INITIALIZED:Int = 1
Const LSP_STATE_SHUTDOWN:Int = 2
Const LSP_REQUEST_CANCELLED:Int = -32800

Rem
bbdoc: Implements a reusable BlitzMax Language Server Protocol endpoint.
about: The server owns open-document and workspace state and dispatches JSON-RPC
requests to the BlitzMax language services. Use #Run for a complete transport loop,
or #HandlePayload when embedding request dispatch in another host.
End Rem
Type TBlitzMaxLspServer
	Field documents:TLspDocumentStore = New TLspDocumentStore
	Field workspaces:TLspWorkspaceStore = New TLspWorkspaceStore
	Field state:Int = LSP_STATE_CREATED
	Field exitRequested:Int
	Field cleanExit:Int
	Field activeQueue:TLspMessageQueue
	Field completionSnippetSupport:Int
	Field workspaceSnippetEditSupport:Int

	Method New()
		workspaces.SetDocuments(documents)
	End Method

	Rem
	bbdoc: Runs the language server until the client sends `exit` or the input closes.
	param: The framed LSP transport used to read requests and write responses.
	End Rem
	Method Run(transport:TLspTransport)
		activeQueue = New TLspMessageQueue
		Local reader:TLspTransportReader = TLspTransportReader.Create(transport, activeQueue)
		Local readerThread:TThread = TThread.Create(TLspTransportReader.ReadLoop, reader)
		While Not exitRequested
			Local message:TLspQueuedMessage = activeQueue.Dequeue()
			If Not message Then Exit
			Local responses:String[]
			If message.requestKey.length And activeQueue.IsCanceled(message.requestKey) Then
				responses = [JsonErrorResponse(message.requestId, LSP_REQUEST_CANCELLED, "Request cancelled").SaveString(JSON_COMPACT)]
			Else
				responses = HandlePayload(message.payload)
				If message.requestKey.length And activeQueue.IsCanceled(message.requestKey) Then responses = [JsonErrorResponse(message.requestId, LSP_REQUEST_CANCELLED, "Request cancelled").SaveString(JSON_COMPACT)]
			End If
			For Local response:String = EachIn responses
				transport.WriteMessage(response)
			Next
			activeQueue.CompleteRequest(message.requestKey)
		Wend
		activeQueue.Close()
		activeQueue = Null
	End Method

	Rem
	bbdoc: Handles one unframed JSON-RPC request or notification payload.
	param: A UTF-8-decoded JSON payload.
	returns: Zero or more compact JSON response or notification payloads.
	End Rem
	Method HandlePayload:String[](payload:String)
		Local error:TJSONError
		Local json:TJSON = TJSON.Load(payload, 0, error)
		Local request:TJSONObject = TJSONObject(json)
		If Not request Then Return [JsonErrorResponse(Null, JSONRPC_PARSE_ERROR, "Parse error").SaveString(JSON_COMPACT)]
		Return HandleRequest(request)
	End Method

	Method HandleRequest:String[](request:TJSONObject)
		Local methodName:String = request.GetString("method")
		Local id:TJSON = request.Get("id")
		If methodName.length = 0 Then Return [JsonErrorResponse(id, JSONRPC_INVALID_REQUEST, "Invalid Request").SaveString(JSON_COMPACT)]

		Select methodName
			Case "initialize"
				Local initializeParams:TJSONObject = TJSONObject(request.Get("params"))
				CaptureClientCapabilities(initializeParams)
				ApplyInitializationOptions(initializeParams)
				InitializeWorkspaces(initializeParams)
				If initializeParams Then ApplyWorkspaceOverrides(TJSONObject(initializeParams.Get("initializationOptions")))
				state = LSP_STATE_INITIALIZED
				Return [JsonResponse(id, InitializeResult()).SaveString(JSON_COMPACT)]
			Case "initialized"
				Return []
			Case "shutdown"
				state = LSP_STATE_SHUTDOWN
				Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
			Case "exit"
				exitRequested = True
				cleanExit = state = LSP_STATE_SHUTDOWN
				Return []
			Case "$/pause", "$/cancelRequest", "$/setTrace"
				Return []
			Case "textDocument/didOpen"
				Return DidOpen(TJSONObject(request.Get("params")))
			Case "textDocument/didChange"
				Return DidChange(TJSONObject(request.Get("params")))
			Case "textDocument/didClose"
				Return DidClose(TJSONObject(request.Get("params")))
			Case "textDocument/hover"
				Return Hover(id, TJSONObject(request.Get("params")))
			Case "textDocument/completion"
				Return Completion(id, TJSONObject(request.Get("params")))
			Case "completionItem/resolve"
				Return ResolveCompletion(id, TJSONObject(request.Get("params")))
			Case "textDocument/semanticTokens/full"
				Return SemanticTokens(id, TJSONObject(request.Get("params")))
			Case "textDocument/inlayHint"
				Return InlayHints(id, TJSONObject(request.Get("params")))
			Case "textDocument/definition"
				Return Definition(id, TJSONObject(request.Get("params")))
			Case "textDocument/typeDefinition"
				Return TypeDefinition(id, TJSONObject(request.Get("params")))
			Case "textDocument/implementation"
				Return Implementation(id, TJSONObject(request.Get("params")))
			Case "textDocument/foldingRange"
				Return FoldingRanges(id, TJSONObject(request.Get("params")))
			Case "textDocument/selectionRange"
				Return SelectionRanges(id, TJSONObject(request.Get("params")))
			Case "workspace/symbol"
				Return WorkspaceSymbols(id, TJSONObject(request.Get("params")))
			Case "textDocument/prepareRename"
				Return PrepareRename(id, TJSONObject(request.Get("params")))
			Case "textDocument/rename"
				Return Rename(id, TJSONObject(request.Get("params")))
			Case "textDocument/documentSymbol"
				Return DocumentSymbols(id, TJSONObject(request.Get("params")))
			Case "textDocument/documentHighlight"
				Return DocumentHighlights(id, TJSONObject(request.Get("params")))
			Case "textDocument/documentLink"
				Return DocumentLinks(id, TJSONObject(request.Get("params")))
			Case "textDocument/references"
				Return References(id, TJSONObject(request.Get("params")))
			Case "textDocument/signatureHelp"
				Return SignatureHelp(id, TJSONObject(request.Get("params")))
			Case "textDocument/codeAction"
				Return CodeActions(id, TJSONObject(request.Get("params")))
			Case "textDocument/prepareTypeHierarchy"
				Return PrepareTypeHierarchy(id, TJSONObject(request.Get("params")))
			Case "typeHierarchy/supertypes"
				Return TypeHierarchySupertypes(id, TJSONObject(request.Get("params")))
			Case "typeHierarchy/subtypes"
				Return TypeHierarchySubtypes(id, TJSONObject(request.Get("params")))
			Case "workspace/didChangeWorkspaceFolders"
				Return DidChangeWorkspaceFolders(TJSONObject(request.Get("params")))
			Case "workspace/didChangeConfiguration"
				Return DidChangeConfiguration(TJSONObject(request.Get("params")))
			Case "workspace/didChangeWatchedFiles"
				Return DidChangeWatchedFiles(TJSONObject(request.Get("params")))
		End Select

		If id Then Return [JsonErrorResponse(id, JSONRPC_METHOD_NOT_FOUND, "Method not found: " + methodName).SaveString(JSON_COMPACT)]
		Return []
	End Method

	Method InitializeResult:TJSONObject()
		Local sync:TJSONObject = JsonObject()
		sync.Set("openClose", New TJSONBool.Create(True))
		sync.Set("change", 1)
		Local capabilities:TJSONObject = JsonObject()
		capabilities.Set("textDocumentSync", sync)
		capabilities.Set("hoverProvider", New TJSONBool.Create(True))
		Local completion:TJSONObject = JsonObject()
		Local completionTriggers:TJSONArray = JsonArray()
		completionTriggers.Append(New TJSONString.Create("."))
		completionTriggers.Append(New TJSONString.Create(" "))
		completionTriggers.Append(New TJSONString.Create(":"))
		completionTriggers.Append(New TJSONString.Create(Chr(34)))
		completionTriggers.Append(New TJSONString.Create("/"))
		completionTriggers.Append(New TJSONString.Create(Chr(92)))
		completion.Set("triggerCharacters", completionTriggers)
		completion.Set("resolveProvider", New TJSONBool.Create(True))
		capabilities.Set("completionProvider", completion)
		Local semanticTokens:TJSONObject = JsonObject()
		Local semanticLegend:TJSONObject = JsonObject()
		semanticLegend.Set("tokenTypes", TBlitzMaxLspSemanticTokens.TokenTypes())
		semanticLegend.Set("tokenModifiers", TBlitzMaxLspSemanticTokens.TokenModifiers())
		semanticTokens.Set("legend", semanticLegend)
		semanticTokens.Set("full", New TJSONBool.Create(True))
		semanticTokens.Set("range", New TJSONBool.Create(False))
		capabilities.Set("semanticTokensProvider", semanticTokens)
		Local inlayHints:TJSONObject = JsonObject()
		inlayHints.Set("resolveProvider", New TJSONBool.Create(False))
		capabilities.Set("inlayHintProvider", inlayHints)
		capabilities.Set("definitionProvider", New TJSONBool.Create(True))
		capabilities.Set("typeDefinitionProvider", New TJSONBool.Create(True))
		capabilities.Set("implementationProvider", New TJSONBool.Create(True))
		capabilities.Set("foldingRangeProvider", New TJSONBool.Create(True))
		capabilities.Set("selectionRangeProvider", New TJSONBool.Create(True))
		capabilities.Set("workspaceSymbolProvider", New TJSONBool.Create(True))
		Local renameProvider:TJSONObject = JsonObject()
		renameProvider.Set("prepareProvider", New TJSONBool.Create(True))
		capabilities.Set("renameProvider", renameProvider)
		capabilities.Set("documentSymbolProvider", New TJSONBool.Create(True))
		capabilities.Set("documentHighlightProvider", New TJSONBool.Create(True))
		Local documentLinks:TJSONObject = JsonObject()
		documentLinks.Set("resolveProvider", New TJSONBool.Create(False))
		capabilities.Set("documentLinkProvider", documentLinks)
		capabilities.Set("referencesProvider", New TJSONBool.Create(True))
		Local codeActions:TJSONObject = JsonObject()
		Local codeActionKinds:TJSONArray = JsonArray()
		codeActionKinds.Append(New TJSONString.Create("quickfix"))
		codeActionKinds.Append(New TJSONString.Create("refactor.rewrite"))
		codeActions.Set("codeActionKinds", codeActionKinds)
		codeActions.Set("resolveProvider", New TJSONBool.Create(False))
		capabilities.Set("codeActionProvider", codeActions)
		capabilities.Set("typeHierarchyProvider", New TJSONBool.Create(True))
		Local signatureHelp:TJSONObject = JsonObject()
		Local signatureTriggers:TJSONArray = JsonArray()
		signatureTriggers.Append(New TJSONString.Create("("))
		signatureTriggers.Append(New TJSONString.Create(","))
		signatureHelp.Set("triggerCharacters", signatureTriggers)
		capabilities.Set("signatureHelpProvider", signatureHelp)
		Local workspaceFolders:TJSONObject = JsonObject()
		workspaceFolders.Set("supported", New TJSONBool.Create(True))
		workspaceFolders.Set("changeNotifications", New TJSONBool.Create(True))
		Local workspace:TJSONObject = JsonObject()
		workspace.Set("workspaceFolders", workspaceFolders)
		capabilities.Set("workspace", workspace)
		Local serverInfo:TJSONObject = JsonObject()
		serverInfo.Set("name", "BlitzMax Language Server")
		serverInfo.Set("version", "0.24.7")
		Local result:TJSONObject = JsonObject()
		result.Set("capabilities", capabilities)
		result.Set("serverInfo", serverInfo)
		Return result
	End Method

	Method Hover:String[](id:TJSON, params:TJSONObject)
		If Not params Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local item:TJSONObject = TJSONObject(params.Get("textDocument"))
		Local position:TJSONObject = TJSONObject(params.Get("position"))
		If Not item Or Not position Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local document:TLspDocument = documents.Get(item.GetString("uri"))
		If Not document Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspHover.Query(document, DocumentWorkspace(document), Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method Definition:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspNavigation.Definition(document, DocumentWorkspace(document), documents, Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method TypeDefinition:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspNavigation.TypeDefinition(document, DocumentWorkspace(document), documents, Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method Implementation:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspImplementation.Query(document, DocumentWorkspace(document), documents, Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method FoldingRanges:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		If Not document Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Return [JsonResponse(id, TBlitzMaxLspFoldingRanges.Query(document, DocumentWorkspace(document))).SaveString(JSON_COMPACT)]
	End Method

	Method SelectionRanges:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local positions:TJSONArray
		If params Then positions = TJSONArray(params.Get("positions"))
		If Not document Or Not positions Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Return [JsonResponse(id, TBlitzMaxLspSelectionRanges.Query(document, DocumentWorkspace(document), positions)).SaveString(JSON_COMPACT)]
	End Method

	Method WorkspaceSymbols:String[](id:TJSON, params:TJSONObject)
		Local query:String
		If params Then query = params.GetString("query")
		Return [JsonResponse(id, TBlitzMaxLspWorkspaceSymbols.Query(query, workspaces, documents)).SaveString(JSON_COMPACT)]
	End Method

	Method PrepareRename:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspRename.Prepare(document, DocumentWorkspace(document), Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method Rename:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Or Not params Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspRename.Rename(document, DocumentWorkspace(document), Int(position.GetInteger("line")), Int(position.GetInteger("character")), params.GetString("newName"))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method Completion:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspCompletion.Query(document, DocumentWorkspace(document), Int(position.GetInteger("line")), Int(position.GetInteger("character")), completionSnippetSupport)
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method ResolveCompletion:String[](id:TJSON, item:TJSONObject)
		If Not item Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local data:TJSONObject = TJSONObject(item.Get("data"))
		If Not data Then Return [JsonResponse(id, item).SaveString(JSON_COMPACT)]
		Local document:TLspDocument = documents.Get(data.GetString("uri"))
		If Not document Then Return [JsonResponse(id, item).SaveString(JSON_COMPACT)]
		Local result:TJSONObject = TBlitzMaxLspCompletion.Resolve(item, document, DocumentWorkspace(document))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method SemanticTokens:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		If Not document Then
			Local empty:TJSONObject = JsonObject()
			empty.Set("data", JsonArray())
			Return [JsonResponse(id, empty).SaveString(JSON_COMPACT)]
		End If
		Return [JsonResponse(id, TBlitzMaxLspSemanticTokens.Query(document, DocumentWorkspace(document))).SaveString(JSON_COMPACT)]
	End Method

	Method InlayHints:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		If Not document Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local range:TJSONObject
		If params Then range = TJSONObject(params.Get("range"))
		Return [JsonResponse(id, TBlitzMaxLspInlayHints.Query(document, DocumentWorkspace(document), range)).SaveString(JSON_COMPACT)]
	End Method

	Method DocumentSymbols:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		If Not document Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Return [JsonResponse(id, TBlitzMaxLspNavigation.DocumentSymbols(document, DocumentWorkspace(document))).SaveString(JSON_COMPACT)]
	End Method

	Method DocumentHighlights:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspNavigation.Highlights(document, DocumentWorkspace(document), Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method DocumentLinks:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		If Not document Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspDocumentLinks.Query(document, DocumentWorkspace(document), documents)
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method References:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local includeDeclaration:Int
		Local referenceContext:TJSONObject = TJSONObject(params.Get("context"))
		If referenceContext Then includeDeclaration = referenceContext.GetBool("includeDeclaration")
		Local result:TJSON = TBlitzMaxLspReferences.Query(document, DocumentWorkspace(document), Int(position.GetInteger("line")), Int(position.GetInteger("character")), includeDeclaration)
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method SignatureHelp:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspNavigation.SignatureHelp(document, DocumentWorkspace(document), Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method CodeActions:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		If Not document Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspCodeActions.Query(document, DocumentWorkspace(document), params, workspaceSnippetEditSupport)
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method PrepareTypeHierarchy:String[](id:TJSON, params:TJSONObject)
		Local document:TLspDocument = RequestDocument(params)
		Local position:TJSONObject = RequestPosition(params)
		If Not document Or Not position Then Return [JsonResponse(id, JsonNull()).SaveString(JSON_COMPACT)]
		Local result:TJSON = TBlitzMaxLspTypeHierarchy.Prepare(document, DocumentWorkspace(document), documents, Int(position.GetInteger("line")), Int(position.GetInteger("character")))
		Return [JsonResponse(id, result).SaveString(JSON_COMPACT)]
	End Method

	Method TypeHierarchySupertypes:String[](id:TJSON, params:TJSONObject)
		Local item:TJSONObject
		If params Then item = TJSONObject(params.Get("item"))
		If Not item Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local data:TJSONObject = TJSONObject(item.Get("data"))
		Local document:TLspDocument
		If data Then document = documents.Get(data.GetString("analysisUri"))
		Local workspace:TLspWorkspaceContext
		If document Then workspace = DocumentWorkspace(document) Else workspace = workspaces.ContextForPath(FileUriToPath(item.GetString("uri")))
		Return [JsonResponse(id, TBlitzMaxLspTypeHierarchy.Supertypes(item, workspace, documents)).SaveString(JSON_COMPACT)]
	End Method

	Method TypeHierarchySubtypes:String[](id:TJSON, params:TJSONObject)
		Local item:TJSONObject
		If params Then item = TJSONObject(params.Get("item"))
		If Not item Then Return [JsonResponse(id, JsonArray()).SaveString(JSON_COMPACT)]
		Local data:TJSONObject = TJSONObject(item.Get("data"))
		Local document:TLspDocument
		If data Then document = documents.Get(data.GetString("analysisUri"))
		Local workspace:TLspWorkspaceContext
		If document Then workspace = DocumentWorkspace(document) Else workspace = workspaces.ContextForPath(FileUriToPath(item.GetString("uri")))
		Return [JsonResponse(id, TBlitzMaxLspTypeHierarchy.Subtypes(item, workspace, documents)).SaveString(JSON_COMPACT)]
	End Method

	Method RequestDocument:TLspDocument(params:TJSONObject)
		If Not params Then Return Null
		Local item:TJSONObject = TJSONObject(params.Get("textDocument"))
		If Not item Then Return Null
		Return documents.Get(item.GetString("uri"))
	End Method

	Method RequestPosition:TJSONObject(params:TJSONObject)
		If Not params Then Return Null
		Return TJSONObject(params.Get("position"))
	End Method

	Method InitializeWorkspaces(params:TJSONObject)
		If Not params Then Return
		Local folders:TJSONArray = TJSONArray(params.Get("workspaceFolders"))
		If folders Then
			For Local index:Int = 0 Until folders.Size()
				AddWorkspaceItem(TJSONObject(folders.Get(index)))
			Next
			Return
		End If
		Local rootUri:String = params.GetString("rootUri")
		If rootUri.length Then workspaces.Add(rootUri, "Workspace")
	End Method

	Method ApplyInitializationOptions(params:TJSONObject)
		If Not params Then Return
		Local options:TJSONObject = TJSONObject(params.Get("initializationOptions"))
		If Not options Then Return
		Local defaults:TJSONObject = TJSONObject(options.Get("blitzmax"))
		If Not defaults Then defaults = options
		workspaces.ApplyDefaultConfiguration(defaults)
	End Method

	Method CaptureClientCapabilities(params:TJSONObject)
		completionSnippetSupport = False
		workspaceSnippetEditSupport = False
		If Not params Then Return
		Local capabilities:TJSONObject = TJSONObject(params.Get("capabilities"))
		If Not capabilities Then Return
		Local textDocument:TJSONObject = TJSONObject(capabilities.Get("textDocument"))
		If textDocument Then
			Local completion:TJSONObject = TJSONObject(textDocument.Get("completion"))
			If completion Then
				Local completionItem:TJSONObject = TJSONObject(completion.Get("completionItem"))
				If completionItem Then completionSnippetSupport = completionItem.GetBool("snippetSupport")
			End If
		End If
		Local workspace:TJSONObject = TJSONObject(capabilities.Get("workspace"))
		If workspace Then
			Local workspaceEdit:TJSONObject = TJSONObject(workspace.Get("workspaceEdit"))
			If workspaceEdit Then workspaceSnippetEditSupport = workspaceEdit.GetBool("snippetEditSupport")
		End If
	End Method

	Method ApplyWorkspaceOverrides(options:TJSONObject)
		If Not options Then Return
		Local overrides:TJSONArray = TJSONArray(options.Get("workspaces"))
		If Not overrides Then Return
		For Local index:Int = 0 Until overrides.Size()
			Local item:TJSONObject = TJSONObject(overrides.Get(index))
			If Not item Then Continue
			Local context:TLspWorkspaceContext = workspaces.Get(item.GetString("uri"))
			If context Then
				context.configuration.ApplyJson(item)
				context.ClearAnalyses()
			End If
		Next
	End Method

	Method DidChangeConfiguration:String[](params:TJSONObject)
		If Not params Then Return []
		Local settings:TJSONObject = TJSONObject(params.Get("settings"))
		If Not settings Then Return []
		Local defaults:TJSONObject = TJSONObject(settings.Get("blitzmax"))
		If Not defaults Then defaults = settings
		workspaces.ApplyDefaultConfiguration(defaults)
		ApplyWorkspaceOverrides(settings)
		workspaces.dependencyCache.Clear()
		workspaces.ClearCatalogues()
		RerouteDocuments()
		Return ReanalyzeDocuments()
	End Method

	Method DidChangeWatchedFiles:String[](params:TJSONObject)
		If Not params Then Return []
		Local changes:TJSONArray = TJSONArray(params.Get("changes"))
		If Not changes Or changes.Size() = 0 Then Return []
		Local interfaceChanged:Int
		For Local index:Int = 0 Until changes.Size()
			Local change:TJSONObject = TJSONObject(changes.Get(index))
			If change And FileUriToPath(change.GetString("uri")).ToLower().EndsWith(".i") Then interfaceChanged = True
		Next
		workspaces.dependencyCache.Clear()
		If interfaceChanged Then
			workspaces.ClearCatalogues()
		End If
		workspaces.ClearAnalyses()
		Return ReanalyzeDocuments()
	End Method

	Method DidChangeWorkspaceFolders:String[](params:TJSONObject)
		If Not params Then Return []
		Local event:TJSONObject = TJSONObject(params.Get("event"))
		If Not event Then Return []
		Local removed:TJSONArray = TJSONArray(event.Get("removed"))
		If removed Then
			For Local index:Int = 0 Until removed.Size()
				Local item:TJSONObject = TJSONObject(removed.Get(index))
				If item Then workspaces.Remove(item.GetString("uri"))
			Next
		End If
		Local added:TJSONArray = TJSONArray(event.Get("added"))
		If added Then
			For Local index:Int = 0 Until added.Size()
				AddWorkspaceItem(TJSONObject(added.Get(index)))
			Next
		End If
		RerouteDocuments()
		Return ReanalyzeDocuments()
	End Method

	Method AddWorkspaceItem(item:TJSONObject)
		If Not item Then Return
		Local uri:String = item.GetString("uri")
		If uri.length Then workspaces.Add(uri, item.GetString("name"))
	End Method

	Method RerouteDocuments()
		For Local document:TLspDocument = EachIn documents.documents.Values()
			AssignWorkspace(document)
		Next
	End Method

	Method ReanalyzeDocuments:String[]()
		Local responses:String[]
		For Local document:TLspDocument = EachIn documents.documents.Values()
			responses :+ [TBlitzMaxLspDiagnostics.Publish(document, DocumentWorkspace(document)).SaveString(JSON_COMPACT)]
		Next
		Return responses
	End Method

	Method AssignWorkspace:TLspWorkspaceContext(document:TLspDocument)
		Local previous:TLspWorkspaceContext = workspaces.Get(document.workspaceUri)
		If Not previous And document.workspaceUri.length = 0 Then previous = workspaces.adHoc
		Local workspace:TLspWorkspaceContext = workspaces.ContextForPath(document.path)
		If previous And previous <> workspace Then previous.Forget(document.uri)
		document.workspaceUri = workspace.uri
		Return workspace
	End Method

	Method DocumentWorkspace:TLspWorkspaceContext(document:TLspDocument)
		Local workspace:TLspWorkspaceContext = workspaces.Get(document.workspaceUri)
		If workspace Then Return workspace
		Return workspaces.adHoc
	End Method

	Method DidOpen:String[](params:TJSONObject)
		If Not params Then Return []
		Local item:TJSONObject = TJSONObject(params.Get("textDocument"))
		If Not item Then Return []
		Local document:TLspDocument = documents.Open(item.GetString("uri"), item.GetString("languageId"), Int(item.GetInteger("version")), item.GetString("text"))
		AssignWorkspace(document)
		Return ReanalyzeAffected(document.path, document, document.liveOverlay)
	End Method

	Method DidChange:String[](params:TJSONObject)
		If Not params Then Return []
		Local item:TJSONObject = TJSONObject(params.Get("textDocument"))
		Local changes:TJSONArray = TJSONArray(params.Get("contentChanges"))
		If Not item Or Not changes Or changes.Size() = 0 Then Return []
		Local change:TJSONObject = TJSONObject(changes.Get(changes.Size() - 1))
		If Not change Then Return []
		Local document:TLspDocument = documents.Change(item.GetString("uri"), Int(item.GetInteger("version")), change.GetString("text"))
		If Not document Then Return []
		Return ReanalyzeAffected(document.path, document)
	End Method

	Method DidClose:String[](params:TJSONObject)
		If Not params Then Return []
		Local item:TJSONObject = TJSONObject(params.Get("textDocument"))
		If Not item Then Return []
		Local uri:String = item.GetString("uri")
		Local document:TLspDocument = documents.Get(uri)
		If Not document Then Return [TBlitzMaxLspDiagnostics.Clear(uri).SaveString(JSON_COMPACT)]
		Local path:String = document.path
		Local workspace:TLspWorkspaceContext = DocumentWorkspace(document)
		Local dependencyChanged:Int = document.liveOverlay
		documents.Close(uri)
		workspace.Forget(uri)
		workspace.InvalidateLiveInterfaceForPath(path)
		If dependencyChanged Then workspace.RefreshProjectPath(path)
		Local responses:String[] = [TBlitzMaxLspDiagnostics.Clear(uri).SaveString(JSON_COMPACT)]
		responses :+ ReanalyzeAffected(path, Null, dependencyChanged)
		Return responses
	End Method

	Method ReanalyzeAffected:String[](path:String, primary:TLspDocument, dependencyChanged:Int = True)
		If primary And dependencyChanged Then DocumentWorkspace(primary).RefreshProjectPath(primary.path)
		Local affected:TLspDocument[]
		If primary Then affected :+ [primary]
		For Local candidate:TLspDocument = EachIn documents.documents.Values()
			If candidate = primary Then Continue
			Local workspace:TLspWorkspaceContext = DocumentWorkspace(candidate)
			Local sameCompilationUnit:Int
			Local dependencyRoot:String
			If primary And DocumentWorkspace(primary) = workspace Then
				Local rootPath:String = workspace.CompilationRootForPath(primary.path)
				If Not rootPath.length Then rootPath = primary.path
				sameCompilationUnit = workspace.IsDocumentInCompilationUnit(candidate.path, rootPath)
				dependencyRoot = rootPath
			Else If dependencyChanged Then
				sameCompilationUnit = workspace.IsDocumentInCompilationUnit(candidate.path, path)
			End If
			Local dependsOnChange:Int = dependencyChanged And workspace.DependsOnPath(candidate.uri, path)
			If Not dependsOnChange And dependencyRoot.length Then dependsOnChange = workspace.DependsOnPath(candidate.uri, dependencyRoot)
			If sameCompilationUnit Or dependsOnChange Then affected :+ [candidate]
		Next
		Local responses:String[]
		Local published:TMap = New TMap
		Local analyzedRoots:TMap = New TMap
		For Local candidate:TLspDocument = EachIn affected
			If activeQueue And activeQueue.HasNewerDocumentVersion(candidate.uri, candidate.version) Then Continue
			Local cancellationToken:TLanguageCancellationToken
			If activeQueue Then cancellationToken = TLspDocumentVersionCancellation.Create(activeQueue, candidate.uri, candidate.version)
			Local publication:TJSONObject = TBlitzMaxLspDiagnostics.Publish(candidate, DocumentWorkspace(candidate), cancellationToken)
			If activeQueue And activeQueue.HasNewerDocumentVersion(candidate.uri, candidate.version) Then Continue
			responses :+ [publication.SaveString(JSON_COMPACT)]
			published.Insert(candidate.uri, candidate)
			Local workspace:TLspWorkspaceContext = DocumentWorkspace(candidate)
			Local rootPath:String = workspace.CompilationRootForPath(candidate.path)
			If Not rootPath.length Then rootPath = candidate.path
			analyzedRoots.Insert(SnapshotPathKey(rootPath), rootPath)
		Next

		' Analysing an including root can establish ownership for files which were
		' already open as standalone documents. Publish those newly contextualized
		' views immediately so stale standalone diagnostics disappear.
		For Local candidate:TLspDocument = EachIn documents.documents.Values()
			If published.Contains(candidate.uri) Then Continue
			Local workspace:TLspWorkspaceContext = DocumentWorkspace(candidate)
			Local rootPath:String = workspace.CompilationRootForPath(candidate.path)
			If Not rootPath.length Or Not analyzedRoots.Contains(SnapshotPathKey(rootPath)) Then Continue
			If activeQueue And activeQueue.HasNewerDocumentVersion(candidate.uri, candidate.version) Then Continue
			Local cancellationToken:TLanguageCancellationToken
			If activeQueue Then cancellationToken = TLspDocumentVersionCancellation.Create(activeQueue, candidate.uri, candidate.version)
			Local publication:TJSONObject = TBlitzMaxLspDiagnostics.Publish(candidate, workspace, cancellationToken)
			If activeQueue And activeQueue.HasNewerDocumentVersion(candidate.uri, candidate.version) Then Continue
			responses :+ [publication.SaveString(JSON_COMPACT)]
			published.Insert(candidate.uri, candidate)
		Next
		Return responses
	End Method
End Type
