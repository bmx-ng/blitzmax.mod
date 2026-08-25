' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem

Import "cancellation.bmx"
Import "semantic_model.bmx"
Import "snapshot_model.bmx"
Import "source_interface_builder.bmx"
Import "interface_source_resolver.bmx"

Type TInterfaceSymbolImporter
	Function ImportSnapshot:TSemanticModel(model:TSemanticModel, snapshot:TCompilationSnapshot, cancellationToken:TLanguageCancellationToken = Null)
		Local sourceResolver:TInterfaceSourceResolver = New TInterfaceSourceResolver
		Local ownedSourceInterfaces:TMap = New TMap
		For Local dependency:TInterfaceDependency = EachIn snapshot.interfaces
			If Not dependency.logicalName.ToLower().EndsWith(".bmx") Then
				CollectSourceImportPaths(dependency, ownedSourceInterfaces, New TMap)
			End If
		Next
		For Local dependency:TInterfaceDependency = EachIn snapshot.interfaces
			If LanguageCancellationRequested(cancellationToken) Then Return model
			ImportDependency(model, dependency, sourceResolver, cancellationToken, ownedSourceInterfaces)
		Next
		' Imports in the root source and its included documents are visible at a
		' higher priority than modules reached only through another interface.
		For Local document:TSourceDocumentModel = EachIn snapshot.documents
			If LanguageCancellationRequested(cancellationToken) Then Return model
			For Local edge:TImportEdge = EachIn document.imports
				If LanguageCancellationRequested(cancellationToken) Then Return model
				If edge.target Then model.AddDirectImportedScope(ImportDependency(model, edge.target, sourceResolver, cancellationToken, ownedSourceInterfaces))
			Next
		Next
		Return model
	End Function

	Function ImportDependency:TScope(model:TSemanticModel, dependency:TInterfaceDependency, sourceResolver:TInterfaceSourceResolver = Null, cancellationToken:TLanguageCancellationToken = Null, ownedSourceInterfaces:TMap = Null)
		Local existing:TScope = model.ImportedInterfaceScope(dependency.path)
		If existing Then Return existing

		Local moduleScope:TScope = New TScope
		moduleScope.kind = SCOPE_INTERFACE_MODULE
		moduleScope.parent = model.globalScope
		model.globalScope.AddChild(moduleScope)
		' Quoted source interfaces remain addressable by path for graph reuse,
		' but are not independently visible through transitive global lookup.
		' Their declarations belong to the nominal module that merges them
		' below. A root source that explicitly imports the quoted file promotes
		' this same scope through AddDirectImportedScope.
		Local isSourceInterface:Int = dependency.logicalName.ToLower().EndsWith(".bmx")
		Local isOwnedSourceInterface:Int = isSourceInterface And ownedSourceInterfaces And ownedSourceInterfaces.Contains(NormalizedPath(dependency.path))
		model.AddImportedScope(dependency.logicalName, moduleScope, dependency.path, Not isOwnedSourceInterface)
		' A quoted source imported by the current compilation unit is another
		' source unit of that module/application, not a nominal module named after
		' the file. Interfaces reached through an imported module are merged into
		' that module's scope below and retain the imported module identity there.
		Local semanticModuleName:String = dependency.logicalName
		If isSourceInterface And Not isOwnedSourceInterface And model.moduleName.length Then semanticModuleName = model.moduleName

		If Not sourceResolver Then sourceResolver = New TInterfaceSourceResolver
		For Local record:TInterfaceRecord = EachIn dependency.interfaceFile.declarations
			If LanguageCancellationRequested(cancellationToken) Then Return moduleScope
			ImportRecord(model, moduleScope, semanticModuleName, dependency.path, record, sourceResolver, cancellationToken)
		Next
		If Not isSourceInterface And Not dependency.interfaceFile.hasSourceAggregate Then
			Local mergedSourceInterfaces:TMap = New TMap
			MergeSourceImports(model, moduleScope, dependency.logicalName, dependency, sourceResolver, mergedSourceInterfaces, cancellationToken)
		End If
		Return moduleScope
	End Function

	Function CollectSourceImportPaths(dependency:TInterfaceDependency, owned:TMap, visited:TMap)
		For Local imported:TInterfaceDependency = EachIn dependency.imports
			Local key:String = NormalizedPath(imported.path)
			If visited.Contains(key) Then Continue
			visited.Insert(key, imported)
			If imported.logicalName.ToLower().EndsWith(".bmx") Then
				owned.Insert(key, imported)
				CollectSourceImportPaths(imported, owned, visited)
			End If
		Next
	End Function

	Function NormalizedPath:String(path:String)
		Return path.Replace("\", "/").ToLower()
	End Function

	' A module's quoted BlitzMax imports are separately compiled source units,
	' not separate public modules. Merge their declarations into the owning
	' module scope while retaining each record's source-interface provenance.
	Function MergeSourceImports(model:TSemanticModel, moduleScope:TScope, moduleName:String, dependency:TInterfaceDependency, sourceResolver:TInterfaceSourceResolver, visited:TMap, cancellationToken:TLanguageCancellationToken)
		For Local imported:TInterfaceDependency = EachIn dependency.imports
			If LanguageCancellationRequested(cancellationToken) Then Return
			If Not imported.logicalName.ToLower().EndsWith(".bmx") Then Continue
			Local key:String = NormalizedPath(imported.path)
			If visited.Contains(key) Then Continue
			visited.Insert(key, imported)
			For Local record:TInterfaceRecord = EachIn imported.interfaceFile.declarations
				If LanguageCancellationRequested(cancellationToken) Then Return
				ImportRecord(model, moduleScope, moduleName, imported.path, record, sourceResolver, cancellationToken)
			Next
			MergeSourceImports(model, moduleScope, moduleName, imported, sourceResolver, visited, cancellationToken)
		Next
	End Function

	Function ImportRecord:TSymbol(model:TSemanticModel, scope:TScope, moduleName:String, originPath:String, record:TInterfaceRecord, sourceResolver:TInterfaceSourceResolver = Null, cancellationToken:TLanguageCancellationToken = Null)
		If LanguageCancellationRequested(cancellationToken) Then Return Null
		ExpandGenericTemplate(record)
		Local kind:Int = SymbolKind(record)
		If Not kind Or Not record.name.length Then Return Null
		Local symbol:TSymbol = New TSymbol
		symbol.kind = kind
		symbol.name = record.name
		symbol.normalizedName = record.name.ToLower()
		symbol.nameToken = record.nameToken
		symbol.declaration = record.declarationSyntax
		symbol.containingScope = scope
		symbol.visibility = record.visibility
		If IsLegacyGenericImplementation(record) Then symbol.visibility = VISIBILITY_PRIVATE
		symbol.isImported = True
		symbol.interfaceRecord = record
		symbol.genericTemplateArtifact = record.genericTemplateArtifact
		symbol.externalName = record.externalName
		If record.flags.Contains("W") Then symbol.callingConvention = CALLING_CONVENTION_STDCALL
		If kind = SYMBOL_INTERFACE Then
			symbol.isExternal = record.flags.Contains("E")
			If symbol.isExternal And Not symbol.externalName.length Then symbol.externalName = symbol.name
		Else
			symbol.isExternal = record.externalName.length > 0
		End If
		symbol.isReadOnly = record.flags.Contains("R")
		symbol.isAbstract = record.flags.Contains("A") Or kind = SYMBOL_INTERFACE
		If kind = SYMBOL_ROUTINE And scope And scope.owner And scope.owner.kind = SYMBOL_INTERFACE Then
			symbol.interfaceMethodKind = INTERFACE_METHOD_ABSTRACT
			If record.flags.Contains("D") Then
				symbol.interfaceMethodKind = INTERFACE_METHOD_DEFAULT
				symbol.isAbstract = False
			Else If record.flags.Contains("R") Then
				symbol.interfaceMethodKind = INTERFACE_METHOD_REABSTRACT
			End If
		End If
		symbol.originModule = moduleName
		If Not sourceResolver Then sourceResolver = New TInterfaceSourceResolver
		Local sourceLocation:TInterfaceSourceLocation = sourceResolver.Resolve(originPath, record)
		symbol.originPath = sourceLocation.path
		symbol.originLine = sourceLocation.line
		symbol.originColumn = sourceLocation.column
		symbol.documentation = record.documentation
		symbol.metadata = record.metadata
		symbol.documentationPath = record.documentationPath
		symbol.documentationLine = record.documentationLine
		symbol.documentationColumn = record.documentationColumn
		Local symbolOriginPath:String = symbol.originPath
		symbol.genericArity = 0
		If record.flags.Contains("G") Then symbol.genericArity = -1
		scope.AddSymbol(symbol)
		If kind = SYMBOL_ROUTINE And record.routineSignature Then
			Local routineScope:TScope = New TScope
			routineScope.kind = SCOPE_ROUTINE
			routineScope.parent = scope
			routineScope.owner = symbol
			routineScope.syntax = record.routineSignature
			scope.AddChild(routineScope)
			symbol.memberScope = routineScope
			model.syntaxScopeMap.Insert(record.routineSignature, routineScope)
			symbol.genericArity = record.routineSignature.genericParameters.length
			If symbol.genericArity = 0 And record.flags.Contains("G") Then symbol.genericArity = -1
			For Local genericParameter:TGenericParameterSyntax = EachIn record.routineSignature.genericParameters
				AddImportedChildSymbol(model, routineScope, SYMBOL_TYPE_PARAMETER, genericParameter.nameToken, genericParameter, moduleName, symbolOriginPath)
			Next
			For Local parameter:TParameterSyntax = EachIn record.routineSignature.parameters
				AddImportedChildSymbol(model, routineScope, SYMBOL_PARAMETER, parameter.nameToken, parameter, moduleName, symbolOriginPath)
			Next
		End If

		If kind = SYMBOL_TYPE Or kind = SYMBOL_STRUCT Or kind = SYMBOL_INTERFACE Or kind = SYMBOL_ENUM Then
			Local memberScope:TScope = New TScope
			If kind = SYMBOL_ENUM Then memberScope.kind = SCOPE_ENUM Else memberScope.kind = SCOPE_TYPE
			memberScope.parent = scope
			memberScope.owner = symbol
			scope.AddChild(memberScope)
			symbol.memberScope = memberScope
			If record.typeHeaderSyntax Then
				symbol.genericArity = record.typeHeaderSyntax.genericParameters.length
				For Local parameter:TGenericParameterSyntax = EachIn record.typeHeaderSyntax.genericParameters
					AddImportedChildSymbol(model, memberScope, SYMBOL_TYPE_PARAMETER, parameter.nameToken, parameter, moduleName, symbolOriginPath)
				Next
			End If
			For Local member:TInterfaceRecord = EachIn record.members
				If LanguageCancellationRequested(cancellationToken) Then Return symbol
				ImportRecord(model, memberScope, moduleName, originPath, member, sourceResolver, cancellationToken)
			Next
		End If
		Return symbol
	End Function

	Function IsLegacyGenericImplementation:Int(record:TInterfaceRecord)
		' Current bcc .i files may include concrete gimpl records needed by its
		' linker/code-generation scheme. They are not source API declarations.
		Return record And record.externalName.ToLower().Contains("|gimpl_")
	End Function

	Function ResolveRecordOrigin:String(interfacePath:String, sourcePath:String)
		Return TInterfaceSourceResolver.ResolvePath(interfacePath, sourcePath)
	End Function

	Function ExpandGenericTemplate(record:TInterfaceRecord)
		If Not record Or Not record.genericSource.length Or record.members.length Then Return
		Local path:String = record.genericSourcePath
		If Not path.length Then path = "<embedded-generic>"
		Local expanded:TInterfaceFile = TBlitzMaxSourceInterfaceBuilder.Build(path, record.genericSource)
		For Local candidate:TInterfaceRecord = EachIn expanded.declarations
			If candidate.kind <> INTERFACE_RECORD_TYPE Or candidate.name.ToLower() <> record.name.ToLower() Then Continue
			record.members = candidate.members
			record.baseTypeSyntax = candidate.baseTypeSyntax
			record.implementedTypeSyntax = candidate.implementedTypeSyntax
			record.typeHeaderSyntax = candidate.typeHeaderSyntax
			Return
		Next
	End Function

	Function AddImportedChildSymbol:TSymbol(model:TSemanticModel, scope:TScope, kind:Int, token:TSyntaxToken, declaration:TSyntaxNode, moduleName:String, originPath:String)
		If Not token Then Return Null
		Local symbol:TSymbol = New TSymbol
		symbol.kind = kind
		symbol.name = token.text
		symbol.normalizedName = token.text.ToLower()
		symbol.nameToken = token
		symbol.declaration = declaration
		symbol.containingScope = scope
		symbol.visibility = VISIBILITY_PRIVATE
		symbol.isImported = True
		symbol.originModule = moduleName
		symbol.originPath = originPath
		scope.AddSymbol(symbol)
		model.declaredSymbolMap.Insert(declaration, symbol)
		Return symbol
	End Function

	Function SymbolKind:Int(record:TInterfaceRecord)
		Select record.kind
			Case INTERFACE_RECORD_TYPE
				If record.flags.Contains("I") Then Return SYMBOL_INTERFACE
				If record.flags.Contains("S") Then Return SYMBOL_STRUCT
				Return SYMBOL_TYPE
			Case INTERFACE_RECORD_ENUM Return SYMBOL_ENUM
			Case INTERFACE_RECORD_FIELD Return SYMBOL_FIELD
			Case INTERFACE_RECORD_METHOD, INTERFACE_RECORD_TYPE_FUNCTION, INTERFACE_RECORD_FUNCTION Return SYMBOL_ROUTINE
			Case INTERFACE_RECORD_GLOBAL Return SYMBOL_GLOBAL
			Case INTERFACE_RECORD_CONST Return SYMBOL_CONST
			Case INTERFACE_RECORD_ENUM_VALUE Return SYMBOL_ENUM_MEMBER
		End Select
		Return 0
	End Function
End Type
