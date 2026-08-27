' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import BRL.TextStream
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "protocol.bmx"

Type TLspDocumentationCacheEntry
	Field modified:Long
	Field size:Long
	Field documentVersion:Int = -1
	Field index:TDocumentationIndex
End Type

' Lazy source cache for symbols whose compiler interfaces carry @source
' provenance. Open buffers win over disk and entries refresh on version,
' timestamp, or size changes.
Type TLspDocumentationCache
	Field entries:TMap = New TMap

	Method Resolve:TDocumentationComment(symbol:TSymbol, documents:TLspDocumentStore)
		If Not symbol Then Return Null
		If symbol.documentation Then Return symbol.documentation
		If Not symbol.originPath.length Or symbol.originLine <= 0 Then Return Null
		Local key:String = symbol.originPath.Replace("\", "/")
		Local entry:TLspDocumentationCacheEntry = TLspDocumentationCacheEntry(entries.ValueForKey(key))
		Local openDocument:TLspDocument
		If documents Then openDocument = documents.GetByPath(symbol.originPath)
		If openDocument Then
			If Not entry Or entry.documentVersion <> openDocument.version Then
				entry = BuildEntry(openDocument.path, openDocument.text)
				entry.documentVersion = openDocument.version
				entries.Insert(key, entry)
			End If
		Else
			If FileType(symbol.originPath) <> FILETYPE_FILE Then Return Null
			Local modified:Long = FileTime(symbol.originPath)
			Local size:Long = FileSize(symbol.originPath)
			If Not entry Or entry.documentVersion >= 0 Or entry.modified <> modified Or entry.size <> size Then
				entry = BuildEntry(symbol.originPath, LoadText(symbol.originPath))
				entry.modified = modified
				entry.size = size
				entries.Insert(key, entry)
			End If
		End If
		If entry And entry.index Then Return entry.index.FindLine(symbol.originLine)
		Return Null
	End Method

	Method BuildEntry:TLspDocumentationCacheEntry(path:String, text:String)
		Local entry:TLspDocumentationCacheEntry = New TLspDocumentationCacheEntry
		Local parsed:TParseResult = TBlitzMaxParser.ParseText(text, path)
		entry.index = TDocumentationIndex.Build(parsed.syntaxTree)
		Return entry
	End Method

	Method Clear()
		entries.Clear()
	End Method
End Type

Type TBlitzMaxLspDocumentation
	Function Markdown:String(documentation:TDocumentationComment, symbol:TSymbol, model:TSemanticModel)
		If Not documentation Then Return ""
		Local result:String
		If documentation.summary.length Then result = RenderText(documentation.summary, symbol, model)
		If documentation.parameters.length Then
			AppendSection(result, "**Parameters**")
			For Local index:Int = 0 Until documentation.parameters.length
				Local name:String = "arg" + (index + 1)
				If symbol And index < symbol.parameters.length And symbol.parameters[index] And symbol.parameters[index].symbol Then name = symbol.parameters[index].symbol.name
				result :+ "~n- **" + name.Replace("*", "") + "** - " + RenderText(documentation.parameters[index], symbol, model)
			Next
		End If
		If documentation.returnsDescription.length Then AppendSection(result, "**Returns:** " + RenderText(documentation.returnsDescription, symbol, model))
		If documentation.keywords.length Then
			Local keywords:String
			For Local keyword:String = EachIn documentation.keywords
				If keywords.length Then keywords :+ ", "
				keywords :+ RenderText(keyword, symbol, model)
			Next
			AppendSection(result, "**Keywords:** " + keywords)
		End If
		If documentation.about.length Then AppendSection(result, RenderText(documentation.about, symbol, model))
		Return result
	End Function

	Function ParameterMarkdown:String(documentation:TDocumentationComment, index:Int, symbol:TSymbol, model:TSemanticModel)
		If Not documentation Or index < 0 Or index >= documentation.parameters.length Then Return ""
		Return RenderText(documentation.parameters[index], symbol, model)
	End Function

	Function MarkupContent:TJSONObject(markdown:String)
		Local content:TJSONObject = JsonObject()
		content.Set("kind", "markdown")
		content.Set("value", markdown)
		Return content
	End Function

	Function SourceLocationMarkdown:String(symbol:TSymbol)
		If Not symbol Or Not symbol.originPath.length Then Return ""
		Local path:String = symbol.originPath.Replace("`", "")
		If symbol.originLine <= 0 Or Not path.ToLower().EndsWith(".bmx") Then Return "Defined in `" + path + "`"
		Local slash:Int = Max(path.FindLast("/"), path.FindLast("\"))
		Local label:String = path
		If slash >= 0 Then label = path[slash + 1..]
		label :+ ":" + symbol.originLine
		Local result:String = "Defined in "
		If symbol.originModule.length Then result :+ "`" + symbol.originModule.Replace("`", "") + "` · "
		Return result + "[`" + label + "`](" + FileUriForPath(symbol.originPath) + "#L" + symbol.originLine + ")"
	End Function

	Function AppendSection(target:String Var, value:String)
		If Not value.length Then Return
		If target.length Then target :+ "~n~n"
		target :+ value
	End Function

	Function RenderText:String(text:String, context:TSymbol, model:TSemanticModel)
		Local result:String
		Local index:Int
		While index < text.length
			Local marker:Int = text[index]
			If (marker = Asc("@") Or marker = Asc("#")) And (index = 0 Or Not IsReferencePart(text[index - 1])) Then
				Local finish:Int = index + 1
				While finish < text.length
					If IsNamePart(text[finish]) Then
						finish :+ 1
						Continue
					End If
					If marker = Asc("#") And text[finish] = Asc(".") And finish + 1 < text.length And IsNamePart(text[finish + 1]) Then
						finish :+ 1
						Continue
					End If
					Exit
				Wend
				If finish > index + 1 Then
					Local name:String = text[index + 1..finish]
					If marker = Asc("@") Then
						result :+ "**" + name + "**"
					Else
						result :+ ReferenceMarkdown(name, context, model)
					End If
					index = finish
					Continue
				End If
			End If
			result :+ Chr(marker)
			index :+ 1
		Wend
		Return result
	End Function

	Function IsReferencePart:Int(char:Int)
		Return IsNamePart(char) Or char = Asc(".")
	End Function

	Function IsNamePart:Int(char:Int)
		Return (char >= Asc("a") And char <= Asc("z")) Or (char >= Asc("A") And char <= Asc("Z")) Or (char >= Asc("0") And char <= Asc("9")) Or char = Asc("_")
	End Function

	Function ReferenceMarkdown:String(name:String, context:TSymbol, model:TSemanticModel)
		Local target:TSymbol = ResolveReference(name, context, model)
		If target And target.originPath.length And target.originLine > 0 Then
			Local uri:String = FileUriForPath(target.originPath) + "#L" + target.originLine
			Return "[" + name + "](" + uri + ")"
		End If
		Return "`" + name + "`"
	End Function

	Function ResolveReference:TSymbol(name:String, context:TSymbol, model:TSemanticModel)
		If Not model Then Return Null
		Local simpleName:String = name
		Local dot:Int = simpleName.FindLast(".")
		If dot >= 0 Then simpleName = simpleName[dot + 1..]
		If context Then
			If context.memberScope Then
				Local values:TSymbol[] = context.memberScope.LookupLocal(simpleName)
				If values.length Then Return values[0]
			End If
			Local scope:TScope = context.containingScope
			If scope And scope.owner And scope.owner.memberScope Then
				Local values:TSymbol[] = scope.owner.memberScope.LookupLocal(simpleName)
				If values.length Then Return values[0]
			End If
			If scope Then
				Local values:TSymbol[] = scope.Lookup(simpleName)
				If values.length Then Return values[0]
			End If
		End If
		Local values:TSymbol[] = model.globalScope.LookupLocal(simpleName)
		If values.length Then Return values[0]
		For Local imported:TScope = EachIn model.directImportedScopes
			values = imported.LookupLocal(simpleName)
			If values.length Then Return values[0]
		Next
		For Local imported:TScope = EachIn model.importedScopes
			values = imported.LookupLocal(simpleName)
			If values.length Then Return values[0]
		Next
		Return Null
	End Function
End Type
