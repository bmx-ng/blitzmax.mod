' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "interface_model.bmx"

' Snapshot loading adds request-specific documentation, decoded generic
' artifacts, and core intrinsics to interface records. Clone the compact
' mutable graph while sharing immutable syntax, metadata, source Strings,
' and decoded value syntax.
Type TInterfaceFileCloner
	Function Clone:TInterfaceFile(source:TInterfaceFile)
		If Not source Then Return Null
		Local result:TInterfaceFile = New TInterfaceFile
		result.path = source.path
		result.sourceText = source.sourceText
		result.isSuperStrict = source.isSuperStrict
		result.hasSourceAggregate = source.hasSourceAggregate
		result.metadata = source.metadata[..]
		result.pragmas = source.pragmas[..]
		result.documentationSource = source.documentationSource
		result.imports = New TInterfaceImport[source.imports.length]
		For Local index:Int = 0 Until source.imports.length
			result.imports[index] = CloneImport(source.imports[index])
		Next
		result.declarations = CloneRecords(source.declarations)
		result.diagnostics = New TInterfaceDiagnostic[source.diagnostics.length]
		For Local index:Int = 0 Until source.diagnostics.length
			result.diagnostics[index] = CloneDiagnostic(source.diagnostics[index])
		Next
		Return result
	End Function

	Function CloneImport:TInterfaceImport(source:TInterfaceImport)
		If Not source Then Return Null
		Local result:TInterfaceImport = New TInterfaceImport
		result.name = source.name
		result.isFileImport = source.isFileImport
		result.rawText = source.rawText
		result.line = source.line
		result.originPath = source.originPath
		Return result
	End Function

	Function CloneDiagnostic:TInterfaceDiagnostic(source:TInterfaceDiagnostic)
		If Not source Then Return Null
		Return TInterfaceDiagnostic.Create(source.code, source.message, source.line)
	End Function

	Function CloneRecords:TInterfaceRecord[](source:TInterfaceRecord[])
		Local result:TInterfaceRecord[] = New TInterfaceRecord[source.length]
		For Local index:Int = 0 Until source.length
			result[index] = CloneRecord(source[index])
		Next
		Return result
	End Function

	Function CloneRecord:TInterfaceRecord(source:TInterfaceRecord)
		If Not source Then Return Null
		Local result:TInterfaceRecord = New TInterfaceRecord
		result.kind = source.kind
		result.name = source.name
		result.nameToken = source.nameToken
		result.declarationSyntax = source.declarationSyntax
		result.rawText = source.rawText
		result.signatureText = source.signatureText
		result.externalName = source.externalName
		result.flags = source.flags
		result.visibility = source.visibility
		result.line = source.line
		result.originPath = source.originPath
		result.originLine = source.originLine
		result.originColumn = source.originColumn
		result.documentation = source.documentation
		result.metadata = source.metadata
		result.documentationPath = source.documentationPath
		result.documentationLine = source.documentationLine
		result.documentationColumn = source.documentationColumn
		result.baseTypeText = source.baseTypeText
		result.implementedTypeTexts = source.implementedTypeTexts[..]
		result.members = CloneRecords(source.members)
		result.trailerText = source.trailerText
		result.valueText = source.valueText
		result.valueSyntax = source.valueSyntax
		result.isStaticArray = source.isStaticArray
		result.staticArrayBound = source.staticArrayBound
		result.declaredTypeSyntax = source.declaredTypeSyntax
		result.callableTypeSyntax = source.callableTypeSyntax
		result.routineSignature = source.routineSignature
		result.baseTypeSyntax = source.baseTypeSyntax
		result.implementedTypeSyntax = source.implementedTypeSyntax[..]
		result.typeHeaderSyntax = source.typeHeaderSyntax
		result.genericSourceStart = source.genericSourceStart
		result.genericSourcePath = source.genericSourcePath
		result.genericSource = source.genericSource
		result.genericTemplateFormat = source.genericTemplateFormat
		result.genericTemplateIdentity = source.genericTemplateIdentity
		result.genericTemplateRevision = source.genericTemplateRevision
		result.genericTemplateReference = source.genericTemplateReference
		result.genericTemplateLanguageRevision = source.genericTemplateLanguageRevision
		result.genericTemplateArtifact = source.genericTemplateArtifact
		Return result
	End Function
End Type
