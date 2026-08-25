' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "syntax.bmx"
Import "generic_template_model.bmx"
Import "documentation_model.bmx"
Import "declaration_metadata.bmx"

Const INTERFACE_RECORD_CONST:Int = 1
Const INTERFACE_RECORD_GLOBAL:Int = 2
Const INTERFACE_RECORD_FUNCTION:Int = 3
Const INTERFACE_RECORD_TYPE:Int = 4
Const INTERFACE_RECORD_ENUM:Int = 5
Const INTERFACE_RECORD_FIELD:Int = 6
Const INTERFACE_RECORD_METHOD:Int = 7
Const INTERFACE_RECORD_TYPE_FUNCTION:Int = 8
Const INTERFACE_RECORD_ENUM_VALUE:Int = 9
Const INTERFACE_RECORD_UNKNOWN:Int = 10

Type TInterfaceImport
	Field name:String
	Field isFileImport:Int
	Field rawText:String
	Field line:Int
	Field originPath:String
End Type

Type TInterfaceRecord
	Field kind:Int
	Field name:String
	' Source-built editor interfaces retain their declaration identity for
	' source navigation. Parsed compiler interfaces leave these fields null.
	Field nameToken:TSyntaxToken
	Field declarationSyntax:TSyntaxNode
	Field rawText:String
	Field signatureText:String
	Field externalName:String
	Field flags:String
	Field visibility:Int = VISIBILITY_PUBLIC
	Field line:Int
	Field originPath:String
	Field originLine:Int
	Field originColumn:Int
	Field documentation:TDocumentationComment
	Field metadata:TDeclarationMetadata
	Field documentationPath:String
	Field documentationLine:Int
	Field documentationColumn:Int
	Field baseTypeText:String
	Field implementedTypeTexts:String[] = New String[0]
	Field members:TInterfaceRecord[] = New TInterfaceRecord[0]
	Field trailerText:String
	Field valueText:String
	Field valueSyntax:TExpressionSyntax
	Field isStaticArray:Int
	Field staticArrayBound:TStaticArrayBoundSyntax
	Field declaredTypeSyntax:TTypeReferenceSyntax
	Field callableTypeSyntax:TCallableTypeSyntax
	Field routineSignature:TRoutineSignatureSyntax
	Field baseTypeSyntax:TTypeReferenceSyntax
	Field implementedTypeSyntax:TTypeReferenceSyntax[] = New TTypeReferenceSyntax[0]
	Field typeHeaderSyntax:TTypeDeclarationHeaderSyntax
	Field genericSourceStart:Int
	Field genericSourcePath:String
	Field genericSource:String
	Field genericTemplateFormat:Int
	Field genericTemplateIdentity:String
	Field genericTemplateRevision:String
	Field genericTemplateReference:String
	Field genericTemplateLanguageRevision:String
	Field genericTemplateArtifact:TGenericTemplateArtifact

	Method KindName:String()
		Select kind
			Case INTERFACE_RECORD_CONST Return "Const"
			Case INTERFACE_RECORD_GLOBAL Return "Global"
			Case INTERFACE_RECORD_FUNCTION Return "Function"
			Case INTERFACE_RECORD_TYPE Return "Type"
			Case INTERFACE_RECORD_ENUM Return "Enum"
			Case INTERFACE_RECORD_FIELD Return "Field"
			Case INTERFACE_RECORD_METHOD Return "Method"
			Case INTERFACE_RECORD_TYPE_FUNCTION Return "TypeFunction"
			Case INTERFACE_RECORD_ENUM_VALUE Return "EnumValue"
		End Select
		Return "Unknown"
	End Method

	Method AddMember(member:TInterfaceRecord)
		Local values:TInterfaceRecord[] = New TInterfaceRecord[members.length + 1]
		For Local index:Int = 0 Until members.length
			values[index] = members[index]
		Next
		values[members.length] = member
		members = values
	End Method
End Type

Type TInterfaceDiagnostic
	Field code:String
	Field message:String
	Field line:Int

	Function Create:TInterfaceDiagnostic(code:String, message:String, line:Int)
		Local result:TInterfaceDiagnostic = New TInterfaceDiagnostic
		result.code = code
		result.message = message
		result.line = line
		Return result
	End Function

	Method Format:String(path:String)
		Local location:String
		If path.length Then location = path + ":" + line + ": "
		Return location + "error " + code + ": " + message
	End Method
End Type

Type TInterfaceFile
	Field path:String
	Field sourceText:String
	Field isSuperStrict:Int
	' A primary module interface carrying this marker has already published the
	' public declarations of its transitive quoted-source units. Consumers still
	' load those imports for dependency provenance and freshness, but must not
	' merge their declarations into the nominal module scope a second time.
	Field hasSourceAggregate:Int
	Field metadata:String[] = New String[0]
	Field pragmas:String[] = New String[0]
	Field documentationSource:String
	Field imports:TInterfaceImport[] = New TInterfaceImport[0]
	Field declarations:TInterfaceRecord[] = New TInterfaceRecord[0]
	Field diagnostics:TInterfaceDiagnostic[] = New TInterfaceDiagnostic[0]

	Method AddImport(value:TInterfaceImport)
		Local values:TInterfaceImport[] = New TInterfaceImport[imports.length + 1]
		For Local index:Int = 0 Until imports.length
			values[index] = imports[index]
		Next
		values[imports.length] = value
		imports = values
	End Method

	Method AddDeclaration(value:TInterfaceRecord)
		Local values:TInterfaceRecord[] = New TInterfaceRecord[declarations.length + 1]
		For Local index:Int = 0 Until declarations.length
			values[index] = declarations[index]
		Next
		values[declarations.length] = value
		declarations = values
	End Method
End Type
