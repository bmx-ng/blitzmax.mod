' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "blitzmax_parser.bmx"
Import "conditional_evaluator.bmx"
Import "interface_model.bmx"
Import "semantic_model.bmx"
Import "snapshot_model.bmx"

' Builds an editor-time public interface directly from source syntax. It is
' deliberately independent of LSP state: callers supply the source text,
' snapshot resolver and conditional-compilation options.
Type TBlitzMaxSourceInterfaceBuilder
	Field file:TInterfaceFile
	Field resolver:TSnapshotResolver
	Field options:TCompilationSnapshotOptions
	Field visiting:TMap = New TMap
	Field externCallingConvention:String = CALLING_CONVENTION_C
	Field externDepth:Int

	Function Build:TInterfaceFile(path:String, text:String, resolver:TSnapshotResolver = Null, options:TCompilationSnapshotOptions = Null)
		Local builder:TBlitzMaxSourceInterfaceBuilder = New TBlitzMaxSourceInterfaceBuilder
		builder.file = New TInterfaceFile
		builder.file.path = path
		builder.file.sourceText = text
		builder.resolver = resolver
		builder.options = options
		If Not builder.options Then builder.options = New TCompilationSnapshotOptions
		builder.VisitText(path, text, VISIBILITY_PUBLIC, Null)
		Return builder.file
	End Function

	Method VisitText:Int(path:String, text:String, visibility:Int, container:TInterfaceRecord)
		Local key:String = PathKey(path)
		If visiting.Contains(key) Then Return visibility
		visiting.Insert(key, path)
		Local tree:TSyntaxTree = TBlitzMaxParser.ParseText(text, path).syntaxTree
		visibility = VisitNodes(tree.root.members, visibility, container, path, tree.source)
		visiting.Remove(key)
		Return visibility
	End Method

	Method VisitNodes:Int(nodes:TSyntaxNode[], visibility:Int, container:TInterfaceRecord, originPath:String, source:TSourceText)
		For Local node:TSyntaxNode = EachIn nodes
			Local section:TVisibilitySectionSyntax = TVisibilitySectionSyntax(node)
			If section Then
				visibility = section.visibility
				Continue
			End If

			Local includeSyntax:TIncludeDirectiveSyntax = TIncludeDirectiveSyntax(node)
			If includeSyntax Then
				If resolver And includeSyntax.pathToken Then
					Local included:TSnapshotText = resolver.ResolveInclude(originPath, includeSyntax.pathText)
					If included Then visibility = VisitText(included.path, included.text, visibility, container)
				End If
				Continue
			End If

			Local importSyntax:TImportDirectiveSyntax = TImportDirectiveSyntax(node)
			If importSyntax Then
				If importSyntax.targetText.length And Not importSyntax.isNativeImport Then
					Local item:TInterfaceImport = New TInterfaceImport
					item.name = importSyntax.targetText
					item.isFileImport = importSyntax.isFileImport
					item.originPath = originPath
					file.AddImport(item)
				End If
				Continue
			End If

			Local conditional:TConditionalRegionSyntax = TConditionalRegionSyntax(node)
			If conditional Then
				Local indexes:Int[] = TConditionalEvaluator.ActiveBranchIndexes(conditional, options.conditionalSymbols)
				For Local index:Int = EachIn indexes
					visibility = VisitNodes(conditional.branches[index].body.statements, visibility, container, originPath, source)
				Next
				Continue
			End If

			Local external:TExternBlockSyntax = TExternBlockSyntax(node)
			If external Then
				Local previousConvention:String = externCallingConvention
				externCallingConvention = TCallingConventionResolver.Resolve(external.callingConventionToken, options.targetPlatform)
				externDepth :+ 1
				visibility = VisitNodes(external.body.statements, visibility, container, originPath, source)
				externDepth :- 1
				externCallingConvention = previousConvention
				Continue
			End If

			Local typeDeclaration:TTypeDeclarationSyntax = TTypeDeclarationSyntax(node)
			If typeDeclaration Then
				Local record:TInterfaceRecord = TypeRecord(typeDeclaration, visibility, originPath, source)
				AddRecord(record, container)
				VisitNodes(typeDeclaration.body.statements, VISIBILITY_PUBLIC, record, originPath, source)
				Continue
			End If

			Local enumDeclaration:TEnumDeclarationSyntax = TEnumDeclarationSyntax(node)
			If enumDeclaration Then
				AddRecord(EnumRecord(enumDeclaration, visibility, originPath, source), container)
				Continue
			End If

			Local routine:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(node)
			If routine Then
				AddRecord(RoutineRecord(routine, container <> Null, visibility, originPath, source), container)
				Continue
			End If

			Local variables:TVariableDeclarationStatementSyntax = TVariableDeclarationStatementSyntax(node)
			If variables Then AddVariables(variables, container, visibility, originPath, source)
		Next
		Return visibility
	End Method

	Method TypeRecord:TInterfaceRecord(syntax:TTypeDeclarationSyntax, visibility:Int, originPath:String, source:TSourceText)
		Local record:TInterfaceRecord = New TInterfaceRecord
		record.kind = INTERFACE_RECORD_TYPE
		If syntax.nameToken Then record.name = syntax.nameToken.text
		record.nameToken = syntax.nameToken
		record.declarationSyntax = syntax
		record.visibility = visibility
		ApplyOrigin(record, syntax.nameToken, originPath, source)
		If syntax.header Then
			record.typeHeaderSyntax = syntax.header
			record.metadata = TDeclarationMetadata.Parse(syntax.header.metadataTokens)
			If syntax.header.extendsTypes.length Then record.baseTypeSyntax = syntax.header.extendsTypes[0]
			record.implementedTypeSyntax = syntax.header.implementedTypes
			' Compact interfaces have one base slot followed by an Interface list.
			' A source Interface may spell multiple parents after Extends, so retain
			' every parent after the first in that list when building its record.
			If syntax.declarationToken.text.ToLower() = "interface" And syntax.header.extendsTypes.length > 1 Then
				Local inheritedInterfaces:TTypeReferenceSyntax[] = New TTypeReferenceSyntax[syntax.header.extendsTypes.length - 1 + syntax.header.implementedTypes.length]
				For Local index:Int = 1 Until syntax.header.extendsTypes.length
					inheritedInterfaces[index - 1] = syntax.header.extendsTypes[index]
				Next
				For Local index:Int = 0 Until syntax.header.implementedTypes.length
					inheritedInterfaces[syntax.header.extendsTypes.length - 1 + index] = syntax.header.implementedTypes[index]
				Next
				record.implementedTypeSyntax = inheritedInterfaces
			End If
		End If
		Select syntax.declarationToken.text.ToLower()
			Case "struct"
				record.flags :+ "S"
				If externDepth > 0 Then record.flags :+ "E"
			Case "interface"
				If externDepth > 0 Then record.flags :+ "E"
				record.flags :+ "I"
		End Select
		Return record
	End Method

	Method EnumRecord:TInterfaceRecord(syntax:TEnumDeclarationSyntax, visibility:Int, originPath:String, source:TSourceText)
		Local record:TInterfaceRecord = New TInterfaceRecord
		record.kind = INTERFACE_RECORD_ENUM
		If syntax.nameToken Then record.name = syntax.nameToken.text
		record.nameToken = syntax.nameToken
		record.declarationSyntax = syntax
		record.visibility = visibility
		ApplyOrigin(record, syntax.nameToken, originPath, source)
		record.baseTypeSyntax = syntax.underlyingType
		If syntax.flagsToken Then record.flags :+ "F"
		For Local value:TEnumValueSyntax = EachIn syntax.values
			Local member:TInterfaceRecord = New TInterfaceRecord
			member.kind = INTERFACE_RECORD_ENUM_VALUE
			If value.nameToken Then member.name = value.nameToken.text
			member.nameToken = value.nameToken
			member.declarationSyntax = value
			member.valueSyntax = value.value
			ApplyOrigin(member, value.nameToken, originPath, source)
			record.AddMember(member)
		Next
		Return record
	End Method

	Method RoutineRecord:TInterfaceRecord(syntax:TRoutineDeclarationSyntax, inType:Int, visibility:Int, originPath:String, source:TSourceText)
		Local record:TInterfaceRecord = New TInterfaceRecord
		If inType Then
			If syntax.isMethod Then record.kind = INTERFACE_RECORD_METHOD Else record.kind = INTERFACE_RECORD_TYPE_FUNCTION
		Else
			record.kind = INTERFACE_RECORD_FUNCTION
		End If
		If syntax.nameToken Then record.name = syntax.nameToken.text
		record.nameToken = syntax.nameToken
		record.declarationSyntax = syntax
		record.visibility = visibility
		If syntax.signature And syntax.signature.operatorName.length Then record.name = syntax.signature.operatorName
		record.routineSignature = syntax.signature
		If syntax.signature Then
			record.metadata = TDeclarationMetadata.Parse(syntax.signature.modifierTokens)
			For Local modifier:TSyntaxToken = EachIn syntax.signature.modifierTokens
				If modifier.text.ToLower() = "default" Then record.flags :+ "D"
				If modifier.text.ToLower() = "abstract" Then record.flags :+ "A"
			Next
			If TCallingConventionResolver.RoutineConvention(syntax, externCallingConvention, options.targetPlatform) = CALLING_CONVENTION_STDCALL Then record.flags :+ "W"
		End If
		ApplyOrigin(record, syntax.nameToken, originPath, source)
		Return record
	End Method

	Method AddVariables(syntax:TVariableDeclarationStatementSyntax, container:TInterfaceRecord, visibility:Int, originPath:String, source:TSourceText)
		Local kind:Int
		Select syntax.declarationToken.text.ToLower()
			Case "const" kind = INTERFACE_RECORD_CONST
			Case "global" kind = INTERFACE_RECORD_GLOBAL
			Case "field" kind = INTERFACE_RECORD_FIELD
		End Select
		If Not kind Then Return
		For Local declarator:TVariableDeclaratorSyntax = EachIn syntax.declarators
			Local record:TInterfaceRecord = New TInterfaceRecord
			record.kind = kind
			record.visibility = visibility
			If declarator.nameToken Then record.name = declarator.nameToken.text
			record.nameToken = declarator.nameToken
			record.declarationSyntax = declarator
			record.declaredTypeSyntax = declarator.declaredType
			record.callableTypeSyntax = declarator.callableType
			record.staticArrayBound = declarator.staticArrayBound
			record.metadata = TDeclarationMetadata.Parse(declarator.metadataTokens)
			record.isStaticArray = declarator.staticArrayBound <> Null
			If HasVariableModifier(syntax, "readonly") Then record.flags :+ "R"
			If kind = INTERFACE_RECORD_CONST Then record.valueSyntax = declarator.initializer
			ApplyOrigin(record, declarator.nameToken, originPath, source)
			AddRecord(record, container)
		Next
	End Method

	Function HasVariableModifier:Int(declaration:TVariableDeclarationStatementSyntax, name:String)
		If Not declaration Then Return False
		For Local token:TSyntaxToken = EachIn declaration.modifierTokens
			If token.text.ToLower() = name Then Return True
		Next
		Return False
	End Function

	Function ApplyOrigin(record:TInterfaceRecord, token:TSyntaxToken, path:String, source:TSourceText)
		If Not record Then Return
		record.originPath = path
		If Not token Or Not source Then Return
		Local position:TSourcePosition = source.Position(token.span.start)
		record.originLine = position.line + 1
		record.originColumn = position.column
	End Function

	Method AddRecord(record:TInterfaceRecord, container:TInterfaceRecord)
		If Not record Or Not record.name.length Then Return
		If container Then container.AddMember(record) Else file.AddDeclaration(record)
	End Method

	Function PathKey:String(path:String)
		Return path.Replace(Chr(92), "/").ToLower()
	End Function
End Type
