' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import Text.Json
Import BlitzMax.Language

Import "documents.bmx"
Import "positions.bmx"
Import "workspaces.bmx"

Const IMPORT_COMPLETION_MODULE:Int = 1
Const IMPORT_COMPLETION_FILE:Int = 2
Const IMPORT_COMPLETION_INCLUDE:Int = 3

Type TImportCompletionContext
	Field kind:Int
	Field replacementStart:Int
	Field replacementEnd:Int
	Field prefix:String
	Field hasClosingQuote:Int
End Type

Type TBlitzMaxLspImportCompletion
	Function Query:TJSONArray(document:TLspDocument, workspace:TLspWorkspaceContext, source:TSourceText, offset:Int)
		Local context:TImportCompletionContext = Locate(source, offset)
		If Not context Then Return Null
		If context.kind = IMPORT_COMPLETION_MODULE Then Return ModuleItems(document, workspace, source, context)
		Return PathItems(document, source, context)
	End Function

	Function Locate:TImportCompletionContext(source:TSourceText, offset:Int)
		If Not source Then Return Null
		Local finish:Int = Min(offset, source.Length())
		Local lineStart:Int = finish
		While lineStart > 0 And source.text[lineStart - 1] <> 10 And source.text[lineStart - 1] <> 13; lineStart :- 1; Wend
		Local lineEnd:Int = finish
		While lineEnd < source.Length() And source.text[lineEnd] <> 10 And source.text[lineEnd] <> 13; lineEnd :+ 1; Wend
		Local cursor:Int = lineStart
		While cursor < finish And TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor]); cursor :+ 1; Wend
		Local keywordStart:Int = cursor
		While cursor < finish And TBlitzMaxLexer.IsIdentifierPart(source.text[cursor]); cursor :+ 1; Wend
		If cursor = keywordStart Then Return Null
		Local keyword:String = source.text[keywordStart..cursor].ToLower()
		If keyword <> "import" And keyword <> "framework" And keyword <> "include" Then Return Null
		If cursor >= finish Or Not TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor]) Then Return Null
		While cursor < finish And TBlitzMaxLexer.IsHorizontalWhitespace(source.text[cursor]); cursor :+ 1; Wend

		If cursor < lineEnd And source.text[cursor] = 34 Then
			Local contentStart:Int = cursor + 1
			If finish < contentStart Then Return Null
			Local contentEnd:Int = contentStart
			While contentEnd < lineEnd And source.text[contentEnd] <> 34; contentEnd :+ 1; Wend
			If finish > contentEnd Then Return Null
			Local result:TImportCompletionContext = New TImportCompletionContext
			If keyword = "include" Then result.kind = IMPORT_COMPLETION_INCLUDE Else result.kind = IMPORT_COMPLETION_FILE
			result.replacementStart = contentStart
			result.replacementEnd = contentEnd
			result.prefix = source.text[contentStart..finish]
			result.hasClosingQuote = contentEnd < lineEnd And source.text[contentEnd] = 34
			Return result
		End If

		If keyword = "include" Then Return Null
		Local targetStart:Int = cursor
		Local targetEnd:Int = targetStart
		While targetEnd < lineEnd And (TBlitzMaxLexer.IsIdentifierPart(source.text[targetEnd]) Or source.text[targetEnd] = Asc(".")); targetEnd :+ 1; Wend
		If finish > targetEnd Then Return Null
		Local result:TImportCompletionContext = New TImportCompletionContext
		result.kind = IMPORT_COMPLETION_MODULE
		result.replacementStart = targetStart
		result.replacementEnd = targetEnd
		result.prefix = source.text[targetStart..finish]
		Return result
	End Function

	Function ModuleItems:TJSONArray(document:TLspDocument, workspace:TLspWorkspaceContext, source:TSourceText, context:TImportCompletionContext)
		Local items:TJSONArray = JsonArray()
		If Not workspace Then Return items
		Local usedFamilies:TMap = New TMap
		Local imported:TMap = New TMap
		CollectWrittenModules(source.text, usedFamilies, imported)
		Local lowerPrefix:String = context.prefix.ToLower()
		For Local moduleName:String = EachIn workspace.InstalledModuleNames()
			If Not moduleName.length Then Continue
			Local item:TJSONObject = JsonObject()
			item.Set("label", moduleName)
			item.Set("kind", 9)
			item.Set("detail", "BlitzMax module")
			item.Set("insertText", moduleName)
			item.Set("filterText", moduleName)
			item.Set("textEdit", TextEdit(source, context.replacementStart, context.replacementEnd, moduleName))
			Local matchRank:Int = 1
			If moduleName.ToLower().StartsWith(lowerPrefix) Then matchRank = 0
			Local duplicateRank:Int = imported.Contains(moduleName.ToLower())
			Local familyRank:Int = 1
			Local separator:Int = moduleName.Find(".")
			If separator > 0 And usedFamilies.Contains(moduleName[..separator].ToLower()) Then familyRank = 0
			item.Set("sortText", matchRank + "" + duplicateRank + familyRank + moduleName.ToLower())
			items.Append(item)
		Next
		Return items
	End Function

	Function PathItems:TJSONArray(document:TLspDocument, source:TSourceText, context:TImportCompletionContext)
		Local items:TJSONArray = JsonArray()
		If Not document Or Not document.path.length Then Return items
		Local written:String = context.prefix.Replace(Chr(92), "/")
		Local separator:Int = written.FindLast("/")
		Local directoryPart:String
		Local leafPrefix:String = written
		If separator >= 0 Then
			directoryPart = written[..separator + 1]
			leafPrefix = written[separator + 1..]
		End If
		Local directoryPath:String
		If directoryPart.length Then directoryPath = ResolveRelativePath(document.path, directoryPart) Else directoryPath = ExtractDir(document.path)
		If FileType(directoryPath) <> FILETYPE_DIR Then Return items
		Local lowerLeaf:String = leafPrefix.ToLower()
		For Local name:String = EachIn LoadDir(directoryPath)
			If Not name.length Or name.StartsWith(".") Then Continue
			Local path:String = directoryPath + "/" + name
			Local fileType:Int = FileType(path)
			If fileType = FILETYPE_DIR Then
				AppendPathItem(items, source, context, directoryPart + name + "/", lowerLeaf, name, True, "directory")
			Else If fileType = FILETYPE_FILE And IsPathCandidate(name, context.kind) Then
				If SnapshotPathKey(path) = SnapshotPathKey(document.path) Then Continue
				Local detail:String = "native import"
				If name.ToLower().EndsWith(".bmx") Then detail = "BlitzMax source file"
				AppendPathItem(items, source, context, directoryPart + name, lowerLeaf, name, False, detail)
			End If
		Next
		Return items
	End Function

	Function AppendPathItem(items:TJSONArray, source:TSourceText, context:TImportCompletionContext, value:String, lowerPrefix:String, name:String, directory:Int, detail:String)
		Local replacement:String = value
		If Not directory And Not context.hasClosingQuote Then replacement :+ Chr(34)
		Local item:TJSONObject = JsonObject()
		item.Set("label", value)
		If directory Then item.Set("kind", 19) Else item.Set("kind", 17)
		item.Set("detail", detail)
		item.Set("insertText", replacement)
		item.Set("filterText", value)
		item.Set("textEdit", TextEdit(source, context.replacementStart, context.replacementEnd, replacement))
		Local matchRank:Int = 1
		If name.ToLower().StartsWith(lowerPrefix) Then matchRank = 0
		Local kindRank:Int = 1
		If directory Then kindRank = 0
		item.Set("sortText", matchRank + "" + kindRank + value.ToLower())
		items.Append(item)
	End Function

	Function IsPathCandidate:Int(name:String, kind:Int)
		Local lower:String = name.ToLower()
		If kind = IMPORT_COMPLETION_INCLUDE Then Return lower.EndsWith(".bmx")
		Local dot:Int = lower.FindLast(".")
		If dot < 0 Then Return False
		Select lower[dot + 1..]
			Case "bmx", "c", "cc", "cpp", "cxx", "h", "hpp", "hxx", "m", "mm", "s", "asm", "o", "a", "lib", "so", "dylib", "dll", "def", "rc"
				Return True
		End Select
		Return False
	End Function

	Function CollectWrittenModules(text:String, families:TMap, imported:TMap)
		For Local line:String = EachIn text.Split("~n")
			Local value:String = line.Trim()
			Local lower:String = value.ToLower()
			Local start:Int
			If lower.StartsWith("import ") Then start = 7 Else If lower.StartsWith("framework ") Then start = 10 Else Continue
			Local target:String = value[start..].Trim()
			If Not target.length Or target.StartsWith(Chr(34)) Then Continue
			Local finish:Int
			While finish < target.length And (TBlitzMaxLexer.IsIdentifierPart(target[finish]) Or target[finish] = Asc(".")); finish :+ 1; Wend
			target = target[..finish].ToLower()
			If Not target.length Then Continue
			imported.Insert(target, target)
			Local separator:Int = target.Find(".")
			If separator > 0 Then families.Insert(target[..separator], target)
		Next
	End Function

	Function TextEdit:TJSONObject(source:TSourceText, start:Int, finish:Int, newText:String)
		Local edit:TJSONObject = JsonObject()
		edit.Set("range", TLspPositions.Range(source, TSourceSpan.Create(start, finish - start)))
		edit.Set("newText", newText)
		Return edit
	End Function
End Type
