' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "navigation_features.bmx"
Import "workspaces.bmx"

' Standard textDocument/implementation support. Live semantic models provide
' exact generic-aware override matching; the installed catalogue contributes
' implementations from modules that are not open or imported by the document.
Type TBlitzMaxLspImplementation
	Function Query:TJSON(document:TLspDocument, workspace:TLspWorkspaceContext, documents:TLspDocumentStore, line:Int, character:Int)
		Local result:TJSONArray = JsonArray()
		Local context:TLspFeatureContext = TLspFeatureContext.Create(document, workspace, line, character)
		If Not context Or Not context.location Then Return result
		Local target:TSymbol = TargetSymbol(context.location)
		If Not SupportedTarget(target) Then Return result
		Local seen:TMap = New TMap
		AppendLive(result, seen, target, workspace, documents)
		AppendCatalogue(result, seen, target, context.analysis, document.path, workspace.InstalledCatalogue().catalogue, documents)
		Return result
	End Function

	Function TargetSymbol:TSymbol(location:TSemanticLocation)
		If Not location Then Return Null
		If SupportedTarget(location.symbol) Then Return location.symbol
		Local symbol:TSymbol = TBlitzMaxLspNavigation.TypeSymbol(location.semanticType)
		If SupportedTarget(symbol) Then Return symbol
		If location.symbol Then
			symbol = TBlitzMaxLspNavigation.TypeSymbol(location.symbol.declaredType)
			If SupportedTarget(symbol) Then Return symbol
		End If
		Return Null
	End Function

	Function SupportedTarget:Int(symbol:TSymbol)
		If Not symbol Then Return False
		If symbol.kind = SYMBOL_TYPE Or symbol.kind = SYMBOL_INTERFACE Then Return True
		Return symbol.kind = SYMBOL_ROUTINE And IsInstanceRoutine(symbol) And OwnerType(symbol) <> Null
	End Function

	Function IsInstanceRoutine:Int(symbol:TSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Then Return False
		If symbol.interfaceRecord Then Return symbol.interfaceRecord.kind = INTERFACE_RECORD_METHOD
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		Return declaration <> Null And declaration.isMethod
	End Function

	Function OwnerType:TSymbol(symbol:TSymbol)
		If Not symbol Or Not symbol.containingScope Or symbol.containingScope.kind <> SCOPE_TYPE Then Return Null
		Local owner:TSymbol = symbol.containingScope.owner
		If owner And (owner.kind = SYMBOL_TYPE Or owner.kind = SYMBOL_INTERFACE) Then Return owner
		Return Null
	End Function

	Function AppendLive(target:TJSONArray, seen:TMap, requested:TSymbol, workspace:TLspWorkspaceContext, documents:TLspDocumentStore)
		If Not workspace Then Return
		For Local value:Object = EachIn workspace.analyses.Keys()
			Local analysisUri:String = String(value)
			Local analysis:TLanguageAnalysis = workspace.LatestAnalysis(analysisUri)
			If Not analysis Or Not analysis.model Then Continue
			If requested.kind = SYMBOL_ROUTINE Then
				AppendLiveRoutines(target, seen, requested, analysis, documents)
			Else
				AppendLiveTypes(target, seen, requested, analysis, documents)
			End If
		Next
		For Local value:Object = EachIn workspace.projectAnalyses.Values()
			Local analysis:TLanguageAnalysis = TLanguageAnalysis(value)
			If Not analysis Or Not analysis.model Then Continue
			If requested.kind = SYMBOL_ROUTINE Then
				AppendLiveRoutines(target, seen, requested, analysis, documents)
			Else
				AppendLiveTypes(target, seen, requested, analysis, documents)
			End If
		Next
	End Function

	Function AppendLiveTypes(target:TJSONArray, seen:TMap, requested:TSymbol, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		Local requestedKey:String = SymbolIdentity(requested)
		If Not requestedKey.length Then Return
		AppendLiveTypesInScope(target, seen, requestedKey, analysis.model.globalScope, analysis, documents)
	End Function

	Function AppendLiveTypesInScope(target:TJSONArray, seen:TMap, requestedKey:String, scope:TScope, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		If Not scope Then Return
		For Local candidate:TSymbol = EachIn scope.declaredSymbols
			If candidate.kind <> SYMBOL_TYPE Or SymbolIdentity(candidate) = requestedKey Then Continue
			If Not InheritedType(analysis.model, candidate, requestedKey) Then Continue
			AppendSymbolLocation(target, seen, candidate, analysis, documents)
		Next
		For Local child:TScope = EachIn scope.children
			AppendLiveTypesInScope(target, seen, requestedKey, child, analysis, documents)
		Next
	End Function

	Function AppendLiveRoutines(target:TJSONArray, seen:TMap, requested:TSymbol, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		Local requestedOwner:TSymbol = OwnerType(requested)
		If Not requestedOwner Then Return
		Local ownerKey:String = SymbolIdentity(requestedOwner)
		Local requestedInModel:TSymbol = FindSymbol(analysis.model.globalScope, requested)
		If Not ownerKey.length Or Not requestedInModel Then Return
		AppendLiveRoutinesInScope(target, seen, requestedInModel, ownerKey, analysis.model.globalScope, analysis, documents)
	End Function

	Function AppendLiveRoutinesInScope(target:TJSONArray, seen:TMap, requested:TSymbol, ownerKey:String, scope:TScope, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		If Not scope Then Return
		For Local candidateOwner:TSymbol = EachIn scope.declaredSymbols
			If candidateOwner.kind <> SYMBOL_TYPE Or Not candidateOwner.memberScope Then Continue
			Local inherited:TNamedSemanticType = InheritedType(analysis.model, candidateOwner, ownerKey)
			If Not inherited Then Continue
			Local validator:TInheritanceValidator = New TInheritanceValidator
			validator.model = analysis.model
			For Local candidate:TSymbol = EachIn candidateOwner.memberScope.LookupLocal(requested.name)
				If Not IsInstanceRoutine(candidate) Then Continue
				If SymbolIdentity(candidate) = SymbolIdentity(requested) Then Continue
				If validator.OverrideSignaturesMatch(candidate, requested, inherited) Then AppendSymbolLocation(target, seen, candidate, analysis, documents)
			Next
		Next
		For Local child:TScope = EachIn scope.children
			AppendLiveRoutinesInScope(target, seen, requested, ownerKey, child, analysis, documents)
		Next
	End Function

	Function InheritedType:TNamedSemanticType(model:TSemanticModel, candidate:TSymbol, requiredKey:String)
		Local named:TNamedSemanticType = TNamedSemanticType(candidate.declaredType)
		If Not named Then Return Null
		Local validator:TInheritanceValidator = New TInheritanceValidator
		validator.model = model
		Return InheritedTypeRecursive(model, named, requiredKey, validator, New TMap, 0)
	End Function

	Function InheritedTypeRecursive:TNamedSemanticType(model:TSemanticModel, current:TNamedSemanticType, requiredKey:String, validator:TInheritanceValidator, seen:TMap, depth:Int)
		If Not current Or Not current.symbol Or depth > 64 Then Return Null
		Local key:String = SymbolIdentity(current.symbol)
		If key = requiredKey Then Return current
		If seen.Contains(key) Then Return Null
		seen.Insert(key, current.symbol)
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(current.symbol)
		If Not info Then Return Null
		Local parameters:TSymbol[] = TInheritanceValidator.DeclaredTypeParameters(current.symbol)
		For Local edge:TInheritanceEdge = EachIn TInheritanceValidator.CombinedEdges(info)
			Local nextType:TSemanticType = validator.Substitute(edge.semanticType, parameters, current.typeArguments)
			Local found:TNamedSemanticType = InheritedTypeRecursive(model, TNamedSemanticType(nextType), requiredKey, validator, seen, depth + 1)
			If found Then Return found
		Next
		Return Null
	End Function

	Function AppendCatalogue(target:TJSONArray, seen:TMap, requested:TSymbol, analysis:TLanguageAnalysis, fallbackPath:String, catalogue:TModuleSymbolCatalogue, documents:TLspDocumentStore)
		If Not catalogue Then Return
		Local catalogueTarget:TModuleCatalogueSymbol = FindCatalogueSymbol(catalogue, requested)
		If Not catalogueTarget Then Return
		If requested.kind = SYMBOL_ROUTINE Then
			Local owner:TModuleCatalogueSymbol = catalogueTarget.parent
			If Not owner Then Return
			Local shape:String = catalogue.RoutineSignatureShape(catalogueTarget)
			For Local candidateOwner:TModuleCatalogueSymbol = EachIn catalogue.typeSymbols
				If candidateOwner.kind <> SYMBOL_TYPE Or Not catalogue.Inherits(candidateOwner, owner) Then Continue
				For Local candidate:TModuleCatalogueSymbol = EachIn catalogue.EnsureMembers(candidateOwner)
					If candidate.kind <> SYMBOL_ROUTINE Or candidate.record.kind <> INTERFACE_RECORD_METHOD Or candidate.normalizedName <> catalogueTarget.normalizedName Then Continue
					If catalogue.RoutineSignatureShape(candidate) = shape Then AppendCatalogueLocation(target, seen, candidate, analysis, fallbackPath, documents)
				Next
			Next
		Else
			For Local candidate:TModuleCatalogueSymbol = EachIn catalogue.typeSymbols
				If candidate.kind = SYMBOL_TYPE And candidate <> catalogueTarget And catalogue.Inherits(candidate, catalogueTarget) Then AppendCatalogueLocation(target, seen, candidate, analysis, fallbackPath, documents)
			Next
		End If
	End Function

	Function FindCatalogueSymbol:TModuleCatalogueSymbol(catalogue:TModuleSymbolCatalogue, symbol:TSymbol)
		If Not catalogue Or Not symbol Then Return Null
		For Local candidate:TModuleCatalogueSymbol = EachIn catalogue.SymbolsNamed(symbol.name)
			If candidate.kind <> symbol.kind Or candidate.originLine <> symbol.originLine Then Continue
			If SnapshotPathKey(candidate.originPath) <> SnapshotPathKey(symbol.originPath) Then Continue
			Local owner:TSymbol = OwnerType(symbol)
			If owner And candidate.parent And candidate.parent.name.ToLower() <> owner.name.ToLower() Then Continue
			Return candidate
		Next
		Return Null
	End Function

	Function FindSymbol:TSymbol(scope:TScope, requested:TSymbol)
		If Not scope Or Not requested Then Return Null
		Local requestedKey:String = SymbolIdentity(requested)
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			If SymbolIdentity(symbol) = requestedKey Then Return symbol
		Next
		For Local child:TScope = EachIn scope.children
			Local found:TSymbol = FindSymbol(child, requested)
			If found Then Return found
		Next
		Return Null
	End Function

	Function AppendSymbolLocation(target:TJSONArray, seen:TMap, symbol:TSymbol, analysis:TLanguageAnalysis, documents:TLspDocumentStore)
		Local key:String = SymbolIdentity(symbol)
		If Not key.length Or seen.Contains(key) Then Return
		Local location:TJSONObject = TJSONObject(TBlitzMaxLspNavigation.LocationForSymbol(symbol, analysis.syntaxTree.source.path, analysis, documents))
		If Not location Then Return
		seen.Insert(key, symbol)
		target.Append(location)
	End Function

	Function AppendCatalogueLocation(target:TJSONArray, seen:TMap, symbol:TModuleCatalogueSymbol, analysis:TLanguageAnalysis, fallbackPath:String, documents:TLspDocumentStore)
		Local key:String = CatalogueIdentity(symbol)
		If Not key.length Or seen.Contains(key) Then Return
		Local proxy:TSymbol = New TSymbol
		proxy.kind = symbol.kind
		proxy.name = symbol.name
		proxy.normalizedName = symbol.normalizedName
		proxy.originModule = symbol.moduleEntry.name
		proxy.originPath = symbol.originPath
		proxy.originLine = symbol.originLine
		proxy.originColumn = symbol.originColumn
		Local location:TJSONObject = TJSONObject(TBlitzMaxLspNavigation.LocationForSymbol(proxy, fallbackPath, analysis, documents))
		If Not location Then Return
		seen.Insert(key, symbol)
		target.Append(location)
	End Function

	Function SymbolIdentity:String(symbol:TSymbol)
		If Not symbol Or Not symbol.originPath.length Or symbol.originLine <= 0 Then Return ""
		Return SnapshotPathKey(symbol.originPath) + "|" + symbol.originLine + "|" + symbol.kind + "|" + symbol.QualifiedName().ToLower()
	End Function

	Function CatalogueIdentity:String(symbol:TModuleCatalogueSymbol)
		If Not symbol Or Not symbol.originPath.length Or symbol.originLine <= 0 Then Return ""
		Local name:String = symbol.name.ToLower()
		If symbol.parent Then name = symbol.parent.name.ToLower() + "." + name
		Return SnapshotPathKey(symbol.originPath) + "|" + symbol.originLine + "|" + symbol.kind + "|" + name
	End Function
End Type
