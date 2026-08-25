' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "interface_model.bmx"
Import "syntax.bmx"

Rem
bbdoc: Contains source, interface, or generic-template content returned by a snapshot resolver.
End Rem
Type TSnapshotText
	Field path:String
	Field text:String
	Field interfaceFile:TInterfaceFile
	' Resolvers may supply an already validated, immutable decoded artifact.
	' Request-specific template catalogues and specialization state are not
	' carried by the snapshot.
	Field genericTemplateArtifact:TGenericTemplateArtifact
	Field genericTemplateDiagnostics:String[] = New String[0]

	Function Create:TSnapshotText(path:String, text:String)
		Local result:TSnapshotText = New TSnapshotText
		result.path = path
		result.text = text
		Return result
	End Function

	Function CreateInterface:TSnapshotText(path:String, interfaceFile:TInterfaceFile)
		Local result:TSnapshotText = New TSnapshotText
		result.path = path
		result.interfaceFile = interfaceFile
		Return result
	End Function

	Function CreateGenericTemplate:TSnapshotText(path:String, artifact:TGenericTemplateArtifact, diagnostics:String[] = Null)
		Local result:TSnapshotText = New TSnapshotText
		result.path = path
		result.genericTemplateArtifact = artifact
		If diagnostics Then result.genericTemplateDiagnostics = diagnostics[..]
		Return result
	End Function
End Type

Rem
bbdoc: Resolves the external inputs needed to construct a compilation snapshot.
about: Consumers may resolve from a filesystem, an editor workspace, memory, or any
other store. Resolution methods should return #Null when a requested item cannot be found.
End Rem
Type TSnapshotResolver Abstract
	Rem
	bbdoc: Resolves a source file included by another source document.
	param: The path of the document containing the Include directive.
	param: The path written in the Include directive.
	returns: The resolved source text, or #Null if it could not be resolved.
	End Rem
	Method ResolveInclude:TSnapshotText(includingPath:String, includePath:String) Abstract
	Rem
	bbdoc: Resolves an imported module or source interface.
	param: The path of the importing source or interface.
	param: The module name or file target written by the import.
	param: Whether the target is a quoted file import.
	param: Whether the import is a Framework declaration.
	returns: The resolved interface, or #Null if it could not be resolved.
	End Rem
	Method ResolveInterface:TSnapshotText(importingPath:String, target:String, isFileImport:Int, isFramework:Int) Abstract
	Rem
	bbdoc: Resolves the core runtime interface for a target platform.
	param: The target platform name.
	returns: The resolved core interface, or #Null if it could not be resolved.
	End Rem
	Method ResolveCoreInterface:TSnapshotText(targetPlatform:String) Abstract

	Method ResolveGenericTemplate:TSnapshotText(interfacePath:String, artifactReference:String)
		Return ResolveInclude(interfacePath, artifactReference)
	End Method

	Method ResolveDocumentation:TSnapshotText(interfacePath:String, documentationPath:String)
		Return ResolveInclude(interfacePath, documentationPath)
	End Method
End Type

Rem
bbdoc: Configures dependency snapshot construction.
End Rem
Type TCompilationSnapshotOptions
	Field targetPlatform:String
	Field conditionalSymbols:String[] = New String[0]
	' Compiler consumers omit inactive source lines before grammar parsing.
	' Editor consumers leave this disabled so all conditional branches remain
	' available for navigation, highlighting and completion.
	Field parseConfiguredConditionals:Int
	' Build drivers may contribute application-wide imports which are not
	' written in the root source (a command-line Framework, or the production
	' default BRL/Pub application framework).
	Field implicitImports:String[] = New String[0]
	Field requireCoreInterface:Int = True
	' Build drivers may compile a quoted source file as one unit of its owning
	' module even though that file does not repeat the Module declaration.
	' The override is language identity only; output ownership remains a
	' compiler/build-driver concern.
	Field sourceModuleName:String

	Rem
	bbdoc: Adds a conditional-compilation symbol if it is not already present.
	param: The case-insensitive symbol name.
	End Rem
	Method EnsureConditionalSymbol(name:String)
		For Local symbol:String = EachIn conditionalSymbols
			If symbol.Compare(name, False) = 0 Then Return
		Next
		conditionalSymbols :+ [name.ToLower()]
	End Method
End Type

Rem
bbdoc: Represents a source, import, or dependency error encountered while building a snapshot.
End Rem
Type TSnapshotDiagnostic
	Field code:String
	Field message:String
	Field path:String
	Field span:TSourceSpan

	Function Create:TSnapshotDiagnostic(code:String, message:String, path:String, span:TSourceSpan = Null)
		Local result:TSnapshotDiagnostic = New TSnapshotDiagnostic
		result.code = code
		result.message = message
		result.path = path
		result.span = span
		Return result
	End Function

	Method Format:String(snapshot:TCompilationSnapshot = Null)
		Local location:String = path
		If snapshot And span Then
			Local document:TSourceDocumentModel = snapshot.DocumentForPath(path)
			If document And document.tree And document.tree.source Then
				location :+ ":" + document.tree.source.Position(span.start).ToString()
			End If
		End If
		If location.length Then location :+ ": "
		Return location + "error " + code + ": " + message
	End Method
End Type

Type TSourceDocumentModel
	Field path:String
	Field tree:TSyntaxTree
	Field isRoot:Int
	' Includes are parsed as separate documents for stable source positions, but
	' semantically inherit the root compilation unit's Strict/SuperStrict mode.
	Field effectiveSourceMode:Int
	Field includes:TIncludeEdge[] = New TIncludeEdge[0]
	Field imports:TImportEdge[] = New TImportEdge[0]

	Method AddInclude(edge:TIncludeEdge)
		includes :+ [edge]
	End Method

	Method AddImport(edge:TImportEdge)
		imports :+ [edge]
	End Method
End Type

Type TInterfaceDependency
	Field path:String
	Field logicalName:String
	Field interfaceFile:TInterfaceFile
	Field isCore:Int
	Field documentationSource:TSnapshotText
	Field imports:TInterfaceDependency[] = New TInterfaceDependency[0]
	Field genericTemplates:TGenericTemplateArtifact[] = New TGenericTemplateArtifact[0]

	Method AddImport(dependency:TInterfaceDependency)
		imports :+ [dependency]
	End Method

	Method AddGenericTemplate(artifact:TGenericTemplateArtifact)
		genericTemplates :+ [artifact]
	End Method
End Type

Type TIncludeEdge
	Field syntax:TIncludeDirectiveSyntax
	Field target:TSourceDocumentModel
End Type

Type TImportEdge
	Field syntax:TImportDirectiveSyntax
	Field target:TInterfaceDependency
End Type

Rem
bbdoc: Contains an immutable view of a root document and its resolved compilation dependencies.
about: A snapshot owns the parsed root and included documents, imported interfaces,
the core interface, snapshot diagnostics, and the options used to construct it.
End Rem
Type TCompilationSnapshot
	Field options:TCompilationSnapshotOptions
	Field rootDocument:TSourceDocumentModel
	Field documents:TSourceDocumentModel[] = New TSourceDocumentModel[0]
	Field interfaces:TInterfaceDependency[] = New TInterfaceDependency[0]
	Field coreInterface:TInterfaceDependency
	Field diagnostics:TSnapshotDiagnostic[] = New TSnapshotDiagnostic[0]
	Field succeeded:Int

	Method AddDocument(document:TSourceDocumentModel)
		documents :+ [document]
	End Method

	Method AddInterface(dependency:TInterfaceDependency)
		interfaces :+ [dependency]
	End Method

	Method AddDiagnostic(diagnostic:TSnapshotDiagnostic)
		diagnostics :+ [diagnostic]
	End Method

	Rem
	bbdoc: Finds a source document in this snapshot by path.
	param: The source path to find.
	returns: The matching root or included document, or #Null.
	End Rem
	Method DocumentForPath:TSourceDocumentModel(path:String)
		Local wanted:String = path.Replace(Chr(92), "/")
		For Local document:TSourceDocumentModel = EachIn documents
			If Not document Then Continue
			Local candidate:String = document.path.Replace(Chr(92), "/")
			?win32
			wanted = wanted.ToLower()
			candidate = candidate.ToLower()
			?
			If candidate = wanted Then Return document
		Next
		Return Null
	End Method

	Rem
	bbdoc: Finds mapped source text in this snapshot by path.
	param: The source path to find, or an empty string to request the root source.
	returns: The matching source text, or #Null.
	End Rem
	Method SourceForPath:TSourceText(path:String)
		Local document:TSourceDocumentModel = DocumentForPath(path)
		If document And document.tree Then Return document.tree.source
		If Not path.length And rootDocument And rootDocument.tree Then Return rootDocument.tree.source
		Return Null
	End Method
End Type
