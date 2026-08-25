' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map

Import "blitzmax_parser.bmx"
Import "documentation_model.bmx"
Import "interface_model.bmx"
Import "source_interface_builder.bmx"

' Merges a documentation-only BlitzMax source companion into a compiler
' interface. Declarations are matched by stable qualified signatures, so
' documentation remains attached when either file is reordered.
Type TInterfaceDocumentationMerger
	Function Apply:Int(interfaceFile:TInterfaceFile, documentationPath:String, documentationText:String)
		If Not interfaceFile Or Not documentationText.length Then Return 0
		ClearRecords(interfaceFile.declarations)
		Local parsed:TParseResult = TBlitzMaxParser.ParseText(documentationText, documentationPath)
		Local index:TDocumentationIndex = TDocumentationIndex.Build(parsed.syntaxTree)
		Local documentationFile:TInterfaceFile = TBlitzMaxSourceInterfaceBuilder.Build(documentationPath, documentationText)
		Local entries:TMap = New TMap
		IndexRecords(documentationFile.declarations, "", entries, index, documentationPath)
		Return MergeRecords(interfaceFile.declarations, "", entries)
	End Function

	Function ClearRecords(records:TInterfaceRecord[])
		For Local record:TInterfaceRecord = EachIn records
			record.documentation = Null
			record.documentationPath = ""
			record.documentationLine = 0
			record.documentationColumn = 0
			If record.members.length Then ClearRecords(record.members)
		Next
	End Function

	Function IndexRecords(records:TInterfaceRecord[], container:String, entries:TMap, index:TDocumentationIndex, path:String)
		For Local record:TInterfaceRecord = EachIn records
			Local qualified:String = QualifiedName(container, record.name)
			Local documentation:TDocumentationComment = index.FindLine(record.originLine)
			If documentation Then
				Local entry:TInterfaceDocumentationEntry = New TInterfaceDocumentationEntry
				entry.documentation = documentation
				entry.path = path
				entry.line = record.originLine
				entry.column = record.originColumn
				entries.Insert(RecordKey(record, container), entry)
			End If
			If record.members.length Then IndexRecords(record.members, qualified, entries, index, path)
		Next
	End Function

	Function MergeRecords:Int(records:TInterfaceRecord[], container:String, entries:TMap)
		Local matched:Int
		For Local record:TInterfaceRecord = EachIn records
			Local entry:TInterfaceDocumentationEntry = TInterfaceDocumentationEntry(entries.ValueForKey(RecordKey(record, container)))
			If entry Then
				record.documentation = entry.documentation
				record.documentationPath = entry.path
				record.documentationLine = entry.line
				record.documentationColumn = entry.column
				matched :+ 1
			End If
			If record.members.length Then matched :+ MergeRecords(record.members, QualifiedName(container, record.name), entries)
		Next
		Return matched
	End Function

	Function RecordKey:String(record:TInterfaceRecord, container:String)
		Local result:String = record.kind + "|" + QualifiedName(container, record.name).ToLower()
		Local signature:TRoutineSignatureSyntax = record.routineSignature
		If Not signature Then Return result
		result :+ "<" + signature.genericParameters.length
		result :+ ">("' parameter signature follows
		For Local index:Int = 0 Until signature.parameters.length
			If index Then result :+ ","
			result :+ ParameterKey(signature.parameters[index])
		Next
		Return result + ")"
	End Function

	Function ParameterKey:String(parameter:TParameterSyntax)
		Local result:String
		If parameter.callableType Then
			result = CallableKey(parameter.callableType)
		Else If parameter.declaredType Then
			result = TypeKey(parameter.declaredType)
		Else
			result = "int"
		End If
		If parameter.staticArrayToken Then result = "staticarray " + result
		If parameter.varToken Then result :+ " var"
		Return result
	End Function

	Function CallableKey:String(callable:TCallableTypeSyntax)
		Local result:String = "callable "
		If callable.returnType Then result :+ TypeKey(callable.returnType) Else result :+ "void"
		result :+ "("
		For Local index:Int = 0 Until callable.parameters.length
			If index Then result :+ ","
			result :+ ParameterKey(callable.parameters[index])
		Next
		result :+ ")"
		For Local suffix:TTypeSuffixSyntax = EachIn callable.suffixes
			If suffix.suffixKind = TYPE_SUFFIX_POINTER Then result :+ " ptr" Else If suffix.suffixKind = TYPE_SUFFIX_ARRAY Then result :+ "[" + suffix.rank + "]"
		Next
		Return result
	End Function

	Function TypeKey:String(syntax:TTypeReferenceSyntax)
		If Not syntax Then Return "int"
		Local result:String = MarkerName(syntax.markerToken)
		If Not result.length Then
			For Local token:TSyntaxToken = EachIn syntax.nameTokens
				result :+ token.text.ToLower()
			Next
		End If
		If syntax.genericArguments.length Then
			result :+ "<"
			For Local index:Int = 0 Until syntax.genericArguments.length
				If index Then result :+ ","
				result :+ TypeKey(syntax.genericArguments[index])
			Next
			result :+ ">"
		End If
		If syntax.suffixes.length Then
			For Local suffix:TTypeSuffixSyntax = EachIn syntax.suffixes
				If suffix.suffixKind = TYPE_SUFFIX_POINTER Then
					result :+ " ptr"
				Else If suffix.suffixKind = TYPE_SUFFIX_ARRAY Then
					result :+ "[" + suffix.rank + "]"
				End If
			Next
		Else
			For Local index:Int = 0 Until syntax.pointerTokens.length
				result :+ " ptr"
			Next
			For Local rank:Int = EachIn syntax.arrayRanks
				result :+ "[" + rank + "]"
			Next
		End If
		Return result
	End Function

	Function MarkerName:String(marker:TSyntaxToken)
		If Not marker Then Return ""
		Select marker.text.ToLower()
			Case "@" Return "byte"
			Case "@@" Return "short"
			Case "%" Return "int"
			Case "%%" Return "long"
			Case "|" Return "uint"
			Case "||" Return "ulong"
			Case "#" Return "float"
			Case "!" Return "double"
			Case "$" Return "string"
			Case "%z" Return "size_t"
			Case "%v" Return "longint"
			Case "%e" Return "ulongint"
			Case "%w" Return "wparam"
			Case "%x" Return "lparam"
			Case "%j" Return "int128"
			Case "!k" Return "float128"
			Case "!m" Return "double128"
			Case "!h" Return "float64"
		End Select
		Return ""
	End Function

	Function QualifiedName:String(container:String, name:String)
		If Not container.length Then Return name
		Return container + "." + name
	End Function
End Type

Type TInterfaceDocumentationEntry
	Field documentation:TDocumentationComment
	Field path:String
	Field line:Int
	Field column:Int
End Type
