' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "interface_signature_decoder.bmx"
Import "interface_symbol_importer.bmx"
Import "type_resolution.bmx"
Import "interface_source_resolver.bmx"

Private

Type TModuleCatalogueEntryBuffer
	Field values:TModuleCatalogueEntry[]
	Field count:Int

	Function Create:TModuleCatalogueEntryBuffer(existing:TModuleCatalogueEntry[])
		Local result:TModuleCatalogueEntryBuffer = New TModuleCatalogueEntryBuffer
		Local capacity:Int = Max(16, existing.length)
		result.values = New TModuleCatalogueEntry[capacity]
		result.count = existing.length
		For Local index:Int = 0 Until existing.length
			result.values[index] = existing[index]
		Next
		Return result
	End Function

	Method Add(value:TModuleCatalogueEntry)
		If count = values.length Then Grow()
		values[count] = value
		count :+ 1
	End Method

	Method Finish:TModuleCatalogueEntry[]()
		Local result:TModuleCatalogueEntry[] = New TModuleCatalogueEntry[count]
		For Local index:Int = 0 Until count
			result[index] = values[index]
		Next
		Return result
	End Method

	Method Grow()
		Local expanded:TModuleCatalogueEntry[] = New TModuleCatalogueEntry[Max(16, values.length * 2)]
		For Local index:Int = 0 Until count
			expanded[index] = values[index]
		Next
		values = expanded
	End Method
End Type

Type TModuleCatalogueSymbolBuffer
	Field values:TModuleCatalogueSymbol[]
	Field count:Int

	Function Create:TModuleCatalogueSymbolBuffer(existing:TModuleCatalogueSymbol[])
		Local result:TModuleCatalogueSymbolBuffer = New TModuleCatalogueSymbolBuffer
		Local capacity:Int = Max(16, existing.length)
		result.values = New TModuleCatalogueSymbol[capacity]
		result.count = existing.length
		For Local index:Int = 0 Until existing.length
			result.values[index] = existing[index]
		Next
		Return result
	End Function

	Method Add(value:TModuleCatalogueSymbol)
		If count = values.length Then Grow()
		values[count] = value
		count :+ 1
	End Method

	Method Finish:TModuleCatalogueSymbol[]()
		Local result:TModuleCatalogueSymbol[] = New TModuleCatalogueSymbol[count]
		For Local index:Int = 0 Until count
			result[index] = values[index]
		Next
		Return result
	End Method

	Method Grow()
		Local expanded:TModuleCatalogueSymbol[] = New TModuleCatalogueSymbol[Max(16, values.length * 2)]
		For Local index:Int = 0 Until count
			expanded[index] = values[index]
		Next
		values = expanded
	End Method
End Type

Public

' A filesystem-independent catalogue entry for one compiler interface module.
' The catalogue deliberately preserves module boundaries; consumers decide
' which entries are visible for binding and which are searchable globally.
Type TModuleCatalogueEntry
	Field name:String
	Field normalizedName:String
	Field interfacePath:String
	Field interfaceFile:TInterfaceFile
	Field decodedInterfaceFile:TInterfaceFile
	Field isCore:Int
	Field imports:String[] = New String[0]
	Field symbols:TModuleCatalogueSymbol[] = New TModuleCatalogueSymbol[0]
	Internal Field symbolBuffer:TModuleCatalogueSymbolBuffer
	Public

	Function Create:TModuleCatalogueEntry(name:String, interfacePath:String, interfaceFile:TInterfaceFile, isCore:Int = False)
		If Not name.length Or Not interfaceFile Then Return Null
		Local result:TModuleCatalogueEntry = New TModuleCatalogueEntry
		result.name = name
		result.normalizedName = name.ToLower()
		result.interfacePath = interfacePath
		result.interfaceFile = interfaceFile
		result.isCore = isCore
		result.imports = New String[interfaceFile.imports.length]
		For Local index:Int = 0 Until interfaceFile.imports.length
			result.imports[index] = interfaceFile.imports[index].name
		Next
		Return result
	End Function
End Type

' A declaration indexed from a compiler interface. It is intentionally lighter
' than TSymbol: no per-document scope, binding or flow-analysis state is held.
Type TModuleCatalogueSymbol
	Field moduleEntry:TModuleCatalogueEntry
	Field parent:TModuleCatalogueSymbol
	Field record:TInterfaceRecord
	Field kind:Int
	Field name:String
	Field normalizedName:String
	Field qualifiedName:String
	Field normalizedQualifiedName:String
	Field originPath:String
	Field originLine:Int
	Field originColumn:Int
	Field isPublic:Int
	Field members:TModuleCatalogueSymbol[] = New TModuleCatalogueSymbol[0]
	Field membersIndexed:Int
	Internal Field memberBuffer:TModuleCatalogueSymbolBuffer
	Public

	Method IsType:Int()
		Return kind = SYMBOL_TYPE Or kind = SYMBOL_STRUCT Or kind = SYMBOL_INTERFACE Or kind = SYMBOL_ENUM
	End Method
End Type

' Compact, reusable index over module interface declarations. Adding modules
' does not make their symbols visible to a source program; this is a discovery
' catalogue for tooling and other language consumers.
Type TModuleSymbolCatalogue
	Field modules:TModuleCatalogueEntry[] = New TModuleCatalogueEntry[0]
	Field symbols:TModuleCatalogueSymbol[] = New TModuleCatalogueSymbol[0]
	Field typeSymbols:TModuleCatalogueSymbol[] = New TModuleCatalogueSymbol[0]
	Field modulesByName:TMap = New TMap
	Field symbolsByName:TMap = New TMap
	Field symbolsByQualifiedName:TMap = New TMap
	Field sourceResolver:TInterfaceSourceResolver = New TInterfaceSourceResolver
	Private Field updateDepth:Int
	Private Field moduleBuffer:TModuleCatalogueEntryBuffer
	Private Field symbolBuffer:TModuleCatalogueSymbolBuffer
	Private Field typeSymbolBuffer:TModuleCatalogueSymbolBuffer
	Public

	' Catalogue discovery is naturally a bulk operation. Keep exact public
	' arrays at the API boundary while avoiding a complete array copy for every
	' declaration added during construction.
	Private
	Method BeginUpdate()
		If updateDepth = 0 Then
			moduleBuffer = TModuleCatalogueEntryBuffer.Create(modules)
			symbolBuffer = TModuleCatalogueSymbolBuffer.Create(symbols)
			typeSymbolBuffer = TModuleCatalogueSymbolBuffer.Create(typeSymbols)
		End If
		updateDepth :+ 1
	End Method

	Method EndUpdate()
		If updateDepth <= 0 Then Return
		updateDepth :- 1
		If updateDepth Then Return
		modules = moduleBuffer.Finish()
		symbols = symbolBuffer.Finish()
		typeSymbols = typeSymbolBuffer.Finish()
		moduleBuffer = Null
		symbolBuffer = Null
		typeSymbolBuffer = Null
		For Local entry:TModuleCatalogueEntry = EachIn modules
			If entry.symbolBuffer Then
				entry.symbols = entry.symbolBuffer.Finish()
				entry.symbolBuffer = Null
			End If
		Next
		For Local symbol:TModuleCatalogueSymbol = EachIn symbols
			If symbol.memberBuffer Then
				symbol.members = symbol.memberBuffer.Finish()
				symbol.memberBuffer = Null
			End If
		Next
		FinalizeIndex(symbolsByName)
		FinalizeIndex(symbolsByQualifiedName)
	End Method
	Public

	Method AddModules(names:String[], interfacePaths:String[], interfaceFiles:TInterfaceFile[], coreFlags:Int[] = Null)
		BeginUpdate()
		Local count:Int = Min(names.length, Min(interfacePaths.length, interfaceFiles.length))
		For Local index:Int = 0 Until count
			Local isCore:Int
			If index < coreFlags.length Then isCore = coreFlags[index]
			AddModule(names[index], interfacePaths[index], interfaceFiles[index], isCore)
		Next
		EndUpdate()
	End Method

	Method AddModule:TModuleCatalogueEntry(name:String, interfacePath:String, interfaceFile:TInterfaceFile, isCore:Int = False)
		Local entry:TModuleCatalogueEntry = TModuleCatalogueEntry.Create(name, interfacePath, interfaceFile, isCore)
		If Not entry Then Return Null
		Local existing:TModuleCatalogueEntry = FindModule(name)
		If existing Then Return existing
		Local ownsUpdate:Int = updateDepth = 0
		If ownsUpdate Then BeginUpdate()
		moduleBuffer.Add(entry)
		modulesByName.Insert(entry.normalizedName, entry)
		For Local record:TInterfaceRecord = EachIn interfaceFile.declarations
			Local symbol:TModuleCatalogueSymbol = IndexRecord(entry, record, Null)
			If symbol Then AppendEntrySymbol(entry, symbol)
		Next
		If ownsUpdate Then EndUpdate()
		Return entry
	End Method

	Method FindModule:TModuleCatalogueEntry(name:String)
		Return TModuleCatalogueEntry(modulesByName.ValueForKey(name.ToLower()))
	End Method

	Method SymbolsNamed:TModuleCatalogueSymbol[](name:String)
		Local group:TModuleCatalogueSymbolGroup = TModuleCatalogueSymbolGroup(symbolsByName.ValueForKey(name.ToLower()))
		If group Then Return group.symbols
		Return New TModuleCatalogueSymbol[0]
	End Method

	Method SymbolsQualified:TModuleCatalogueSymbol[](name:String)
		Local group:TModuleCatalogueSymbolGroup = TModuleCatalogueSymbolGroup(symbolsByQualifiedName.ValueForKey(name.ToLower()))
		If group Then Return group.symbols
		Return New TModuleCatalogueSymbol[0]
	End Method

	Method TypesNamed:TModuleCatalogueSymbol[](name:String)
		Local result:TModuleCatalogueSymbol[]
		For Local symbol:TModuleCatalogueSymbol = EachIn SymbolsNamed(name)
			If symbol.IsType() Then result :+ [symbol]
		Next
		Return result
	End Method

	' Resolves an interface-encoded type name in the declaring module's import
	' context. This does not affect source visibility; it is solely for catalogue
	' relationship queries.
	Method ResolveTypeReference:TModuleCatalogueSymbol(moduleEntry:TModuleCatalogueEntry, encodedName:String)
		If Not moduleEntry Or Not encodedName.length Then Return Null
		Local syntax:TTypeReferenceSyntax = TInterfaceSignatureDecoder.DecodeType(encodedName)
		Local name:String = TTypeResolver.WrittenName(syntax)
		If Not name.length Or name.ToLower() = "null" Then Return Null
		Local candidates:TModuleCatalogueSymbol[]
		If name.Contains(".") Then
			candidates = TypeSymbolsQualified(name)
			If candidates.length = 1 Then Return candidates[0]
		End If
		candidates = TypeSymbolsQualified(moduleEntry.name + "." + name)
		If candidates.length = 1 Then Return candidates[0]
		For Local importedName:String = EachIn moduleEntry.imports
			If importedName.StartsWith(Chr(34)) Or importedName.ToLower().EndsWith(".bmx") Then Continue
			candidates = TypeSymbolsQualified(importedName + "." + name)
			If candidates.length = 1 Then Return candidates[0]
		Next
		candidates = TypeSymbolsQualified("brl.classes." + name)
		If candidates.length = 1 Then Return candidates[0]
		candidates = TypesNamed(name)
		If candidates.length = 1 Then Return candidates[0]
		Return Null
	End Method

	Method DirectSupertypes:TModuleCatalogueSymbol[](symbol:TModuleCatalogueSymbol)
		Local result:TModuleCatalogueSymbol[]
		If Not symbol Or Not symbol.IsType() Then Return result
		Local resolved:TModuleCatalogueSymbol = ResolveTypeReference(symbol.moduleEntry, symbol.record.baseTypeText)
		If resolved Then result :+ [resolved]
		For Local encodedName:String = EachIn symbol.record.implementedTypeTexts
			resolved = ResolveTypeReference(symbol.moduleEntry, encodedName)
			If resolved Then result :+ [resolved]
		Next
		Return result
	End Method

	Method Inherits:Int(candidate:TModuleCatalogueSymbol, required:TModuleCatalogueSymbol)
		Return InheritsRecursive(candidate, required, New TMap, 0)
	End Method

	Method RoutineSignatureShape:String(symbol:TModuleCatalogueSymbol)
		If Not symbol Or symbol.kind <> SYMBOL_ROUTINE Or Not symbol.record Then Return ""
		If Not symbol.record.routineSignature Then TInterfaceSignatureDecoder.DecodeRecord(symbol.record)
		Local signature:TRoutineSignatureSyntax = symbol.record.routineSignature
		If Not signature Then Return symbol.record.signatureText.ToLower()
		Local substitutions:TMap = New TMap
		For Local index:Int = 0 Until signature.genericParameters.length
			substitutions.Insert(signature.genericParameters[index].nameToken.text.ToLower(), "$" + index)
		Next
		Local returnShape:String = TypeSyntaxShape(signature.returnType, substitutions)
		If signature.callableReturnType Then returnShape = CallableSyntaxShape(signature.callableReturnType, substitutions)
		Local result:String = symbol.record.kind + "|" + signature.genericParameters.length + "|" + returnShape + "("
		For Local index:Int = 0 Until signature.parameters.length
			If index Then result :+ ","
			Local parameter:TParameterSyntax = signature.parameters[index]
			If parameter.staticArrayToken Then result :+ "staticarray "
			If parameter.callableType Then
				result :+ CallableSyntaxShape(parameter.callableType, substitutions)
			Else
				result :+ TypeSyntaxShape(parameter.declaredType, substitutions)
			End If
			If parameter.varToken Then result :+ " var"
		Next
		Return result + ")"
	End Method

	Method ModuleCount:Int()
		Return modules.length
	End Method

	Method SymbolCount:Int()
		Return symbols.length
	End Method

	Method TypeCount:Int()
		Return typeSymbols.length
	End Method

	' Generic compiler interfaces may embed their original source instead of a
	' serialized member list. Expand that source only when a consumer needs the
	' members, keeping whole-environment catalogue startup lightweight.
	Method EnsureMembers:TModuleCatalogueSymbol[](symbol:TModuleCatalogueSymbol)
		If Not symbol Or symbol.membersIndexed Then
			If symbol Then Return symbol.members
			Return New TModuleCatalogueSymbol[0]
		End If
		If symbol.record.flags.Contains("G") And Not symbol.record.genericSource.length Then
			If Not symbol.moduleEntry.decodedInterfaceFile Then symbol.moduleEntry.decodedInterfaceFile = TBlitzMaxParser.ParseInterfaceText(symbol.moduleEntry.interfaceFile.sourceText, symbol.moduleEntry.interfacePath)
			Local decoded:TInterfaceRecord = DecodedRecord(symbol, symbol.moduleEntry.decodedInterfaceFile.declarations)
			If decoded Then symbol.record = decoded
		End If
		Local ownsUpdate:Int = updateDepth = 0
		If ownsUpdate Then BeginUpdate()
		TInterfaceSymbolImporter.ExpandGenericTemplate(symbol.record)
		For Local member:TInterfaceRecord = EachIn symbol.record.members
			Local child:TModuleCatalogueSymbol = IndexRecord(symbol.moduleEntry, member, symbol)
			If child Then AppendMemberSymbol(symbol, child)
		Next
		symbol.membersIndexed = True
		If ownsUpdate Then EndUpdate()
		Return symbol.members
	End Method

	Method TypeSymbolsQualified:TModuleCatalogueSymbol[](name:String)
		Local result:TModuleCatalogueSymbol[]
		For Local symbol:TModuleCatalogueSymbol = EachIn SymbolsQualified(name)
			If symbol.IsType() Then result :+ [symbol]
		Next
		Return result
	End Method

	Method InheritsRecursive:Int(candidate:TModuleCatalogueSymbol, required:TModuleCatalogueSymbol, seen:TMap, depth:Int)
		If Not candidate Or Not required Or depth > 64 Then Return False
		If candidate = required Then Return depth > 0
		If seen.Contains(candidate.normalizedQualifiedName) Then Return False
		seen.Insert(candidate.normalizedQualifiedName, candidate)
		For Local parent:TModuleCatalogueSymbol = EachIn DirectSupertypes(candidate)
			If parent = required Or InheritsRecursive(parent, required, seen, depth + 1) Then Return True
		Next
		Return False
	End Method

	Function TypeSyntaxShape:String(syntax:TTypeReferenceSyntax, substitutions:TMap)
		If Not syntax Then Return "void"
		Local result:String
		For Local token:TSyntaxToken = EachIn syntax.tokens
			Local text:String = token.text.ToLower()
			Local replacement:Object = substitutions.ValueForKey(text)
			If replacement Then text = String(replacement)
			result :+ text
		Next
		Return result
	End Function

	Function CallableSyntaxShape:String(syntax:TCallableTypeSyntax, substitutions:TMap)
		If Not syntax Then Return ""
		Local result:String = TypeSyntaxShape(syntax.returnType, substitutions) + "("
		For Local index:Int = 0 Until syntax.parameters.length
			If index Then result :+ ","
			Local parameter:TParameterSyntax = syntax.parameters[index]
			If parameter.callableType Then result :+ CallableSyntaxShape(parameter.callableType, substitutions) Else result :+ TypeSyntaxShape(parameter.declaredType, substitutions)
			If parameter.varToken Then result :+ " var"
		Next
		result :+ ")"
		For Local suffix:TTypeSuffixSyntax = EachIn syntax.suffixes
			If suffix.suffixKind = TYPE_SUFFIX_POINTER Then result :+ " ptr" Else If suffix.suffixKind = TYPE_SUFFIX_ARRAY Then result :+ "[" + suffix.rank + "]"
		Next
		Return result
	End Function

	Function DecodedRecord:TInterfaceRecord(symbol:TModuleCatalogueSymbol, records:TInterfaceRecord[])
		If Not symbol Then Return Null
		Local parentRecord:TInterfaceRecord
		If symbol.parent Then parentRecord = DecodedRecord(symbol.parent, records)
		Local candidates:TInterfaceRecord[] = records
		If parentRecord Then candidates = parentRecord.members
		For Local record:TInterfaceRecord = EachIn candidates
			If record.kind = symbol.record.kind And record.name.ToLower() = symbol.normalizedName Then Return record
		Next
		Return Null
	End Function

	Method IndexRecord:TModuleCatalogueSymbol(entry:TModuleCatalogueEntry, record:TInterfaceRecord, parent:TModuleCatalogueSymbol)
		If Not record Then Return Null
		Local kind:Int = TInterfaceSymbolImporter.SymbolKind(record)
		If Not kind Or Not record.name.length Then Return Null
		Local symbol:TModuleCatalogueSymbol = New TModuleCatalogueSymbol
		symbol.moduleEntry = entry
		symbol.parent = parent
		symbol.record = record
		symbol.kind = kind
		symbol.name = record.name
		symbol.normalizedName = record.name.ToLower()
		symbol.qualifiedName = entry.name + "."
		If parent Then symbol.qualifiedName :+ parent.qualifiedName[entry.name.length + 1..] + "."
		symbol.qualifiedName :+ symbol.name
		symbol.normalizedQualifiedName = symbol.qualifiedName.ToLower()
		Local sourceLocation:TInterfaceSourceLocation = sourceResolver.Resolve(entry.interfacePath, record)
		symbol.originPath = sourceLocation.path
		symbol.originLine = sourceLocation.line
		symbol.originColumn = sourceLocation.column
		symbol.isPublic = record.visibility = VISIBILITY_PUBLIC
		symbolBuffer.Add(symbol)
		If symbol.IsType() Then typeSymbolBuffer.Add(symbol)
		AddToIndex(symbolsByName, symbol.normalizedName, symbol)
		AddToIndex(symbolsByQualifiedName, symbol.normalizedQualifiedName, symbol)
		If record.members.length Or Not record.genericSource.length Then
			For Local member:TInterfaceRecord = EachIn record.members
				Local child:TModuleCatalogueSymbol = IndexRecord(entry, member, symbol)
				If child Then AppendMemberSymbol(symbol, child)
			Next
			symbol.membersIndexed = True
		End If
		Return symbol
	End Method

	Method AppendEntrySymbol(entry:TModuleCatalogueEntry, symbol:TModuleCatalogueSymbol)
		If Not entry.symbolBuffer Then entry.symbolBuffer = TModuleCatalogueSymbolBuffer.Create(entry.symbols)
		entry.symbolBuffer.Add(symbol)
	End Method

	Method AppendMemberSymbol(parent:TModuleCatalogueSymbol, symbol:TModuleCatalogueSymbol)
		If Not parent.memberBuffer Then parent.memberBuffer = TModuleCatalogueSymbolBuffer.Create(parent.members)
		parent.memberBuffer.Add(symbol)
	End Method

	Method AddToIndex(index:TMap, key:String, symbol:TModuleCatalogueSymbol)
		Local group:TModuleCatalogueSymbolGroup = TModuleCatalogueSymbolGroup(index.ValueForKey(key))
		If Not group Then
			group = New TModuleCatalogueSymbolGroup
			index.Insert(key, group)
		End If
		If Not group.symbolBuffer Then group.symbolBuffer = TModuleCatalogueSymbolBuffer.Create(group.symbols)
		group.symbolBuffer.Add(symbol)
	End Method

	Method FinalizeIndex(index:TMap)
		For Local group:TModuleCatalogueSymbolGroup = EachIn index.Values()
			If group.symbolBuffer Then
				group.symbols = group.symbolBuffer.Finish()
				group.symbolBuffer = Null
			End If
		Next
	End Method
End Type

Type TModuleCatalogueSymbolGroup
	Field symbols:TModuleCatalogueSymbol[] = New TModuleCatalogueSymbol[0]
	Internal Field symbolBuffer:TModuleCatalogueSymbolBuffer
End Type
