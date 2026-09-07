' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.Map
Import BRL.FileSystem
Import BRL.Stream
Import BlitzMax.Locale
Import Text.MPack
Import Text.Toml

Type TSourcePlaceholder
	Field name:String
	Field kind:String
End Type

Type TSourceContributor
	Field name:String
	Field role:String
End Type

Type TSourceMessage
	Field id:Int
	Field name:String
	Field text:String
	Field forms:String[] = New String[PLURAL_FORM_COUNT]
	Field pluralArgument:String
	Field description:String
	Field placeholders:TSourcePlaceholder[]
	Field translated:Int = True

	Method IsPlural:Int()
		Return pluralArgument.length > 0
	End Method
End Type

Type TMessageFile
	Field domain:String
	Field locale:String
	Field nextId:Int
	Field contributors:TSourceContributor[]
	Field messages:TSourceMessage[]

	Function Load:TMessageFile(path:String)
		Local root:TTomlTable = TToml.Load(path)
		If Not root Then Throw "Unable to open TOML file: " + path
		RequireInteger(root, "format", path, 1)
		Local result:TMessageFile = New TMessageFile
		result.domain = RequireString(root, "domain", path)
		result.locale = RequireString(root, "locale", path).ToLower()
		result.nextId = Int(OptionalInteger(root, "next_id", path, 0))
		Local contributorNode:ITomlNode = root["contributor"]
		If contributorNode Then
			If Not contributorNode.IsArray() Then Throw path + ": 'contributor' must be an array of tables"
			For Local node:ITomlNode = EachIn contributorNode.AsArray().value
				If Not node.IsTable() Then Throw path + ": every contributor must be a table"
				Local table:TTomlTable = node.AsTable()
				Local contributor:TSourceContributor = New TSourceContributor
				contributor.name = RequireString(table, "name", path)
				If Not contributor.name.Trim().length Then Throw path + ": contributor 'name' must not be empty"
				Local roleNode:ITomlNode = table["role"]
				If roleNode Then
					If Not roleNode.IsString() Then Throw path + ": contributor 'role' must be a string"
					contributor.role = roleNode.AsString()
				End If
				result.contributors :+ [contributor]
			Next
		End If
		Local messageNode:ITomlNode = root["message"]
		If Not messageNode Or Not messageNode.IsArray() Then Throw path + ": 'message' must be an array of tables"
		Local messageArray:TTomlArray = messageNode.AsArray()
		For Local node:ITomlNode = EachIn messageArray.value
			If Not node.IsTable() Then Throw path + ": every message must be a table"
			Local table:TTomlTable = node.AsTable()
			Local message:TSourceMessage = New TSourceMessage
			message.id = Int(RequireInteger(table, "id", path))
			If message.id <= 0 Then Throw path + ": message IDs must be positive"
			message.name = RequireString(table, "name", path)
			Local textNode:ITomlNode = table["text"]
			Local formsNode:ITomlNode = table["forms"]
			If textNode And textNode.IsString() And Not formsNode Then
				message.text = textNode.AsString()
			Else If formsNode And formsNode.IsTable() And Not textNode Then
				message.pluralArgument = RequireString(table, "plural", path)
				Local formsTable:TTomlTable = formsNode.AsTable()
				For Local formIndex:Int = 0 Until PLURAL_FORM_COUNT
					message.forms[formIndex] = OptionalString(formsTable, PluralName(formIndex))
				Next
				If Not message.forms[PLURAL_OTHER].length Then Throw path + ": plural message '" + message.name + "' requires an 'other' form"
			Else
				Throw path + ": message '" + message.name + "' requires either 'text' or 'forms'"
			End If
			message.description = OptionalString(table, "description")
			message.placeholders = OptionalPlaceholders(table, "placeholders", path)
			message.translated = OptionalBoolean(table, "translated", path, True)
			For Local existing:TSourceMessage = EachIn result.messages
				If existing.id = message.id Then Throw path + ": duplicate message ID " + message.id
				If existing.name = message.name Then Throw path + ": duplicate message name '" + message.name + "'"
			Next
			ValidateTemplate(message, path)
			result.messages :+ [message]
		Next
		If result.locale = "en" Then ValidateRegistry(result, path)
		Return result
	End Function
End Type

Type TRegistryLock
	Field domain:String
	Field nextId:Int
	Field names:TStringMap = New TStringMap

	Function Load:TRegistryLock(path:String)
		Local root:TTomlTable = TToml.Load(path)
		If Not root Then Throw "Unable to open registry lock: " + path
		RequireInteger(root, "format", path, 1)
		Local result:TRegistryLock = New TRegistryLock
		result.domain = RequireString(root, "domain", path)
		result.nextId = Int(RequireInteger(root, "next_id", path))
		Local ids:ITomlNode = root["ids"]
		If Not ids Or Not ids.IsTable() Then Throw path + ": 'ids' must be a table"
		For Local key:String = EachIn ids.AsTable().Keys()
			Local node:ITomlNode = ids.AsTable()[key]
			If Not node.IsString() Then Throw path + ": locked ID names must be strings"
			result.names.Insert(key, node.AsString())
		Next
		Return result
	End Function
End Type

Function RequireString:String(table:TTomlTable, key:String, path:String)
	Local node:ITomlNode = table[key]
	If Not node Or Not node.IsString() Then Throw path + ": '" + key + "' must be a string"
	Return node.AsString()
End Function

Function OptionalInteger:Long(table:TTomlTable, key:String, path:String, defaultValue:Long)
	Local node:ITomlNode = table[key]
	If Not node Then Return defaultValue
	If Not node.IsInteger() Then Throw path + ": '" + key + "' must be an integer"
	Return node.AsLong()
End Function

Function ValidateRegistry(source:TMessageFile, path:String)
	If source.nextId <= 1 Then Throw path + ": canonical English registry requires a positive 'next_id'"
	Local maxId:Int
	For Local message:TSourceMessage = EachIn source.messages
		If message.id >= source.nextId Then Throw path + ": message ID " + message.id + " must be below next_id " + source.nextId
		maxId = Max(maxId, message.id)
	Next
	If maxId >= source.nextId Then Throw path + ": next_id must exceed every assigned ID"
End Function

Function OptionalBoolean:Int(table:TTomlTable, key:String, path:String, defaultValue:Int)
	Local node:ITomlNode = table[key]
	If Not node Then Return defaultValue
	If Not node.IsBoolean() Then Throw path + ": '" + key + "' must be a boolean"
	Return node.AsBoolean()
End Function

Function OptionalString:String(table:TTomlTable, key:String)
	Local node:ITomlNode = table[key]
	If node And node.IsString() Then Return node.AsString()
End Function

Function PluralName:String(index:Int)
	Select index
		Case PLURAL_ZERO Return "zero"
		Case PLURAL_ONE Return "one"
		Case PLURAL_TWO Return "two"
		Case PLURAL_FEW Return "few"
		Case PLURAL_MANY Return "many"
		Default Return "other"
	End Select
End Function

Function RequireInteger:Long(table:TTomlTable, key:String, path:String, expected:Long = -1)
	Local node:ITomlNode = table[key]
	If Not node Or Not node.IsInteger() Then Throw path + ": '" + key + "' must be an integer"
	Local value:Long = node.AsLong()
	If expected >= 0 And value <> expected Then Throw path + ": unsupported " + key + " " + value
	Return value
End Function

Function OptionalPlaceholders:TSourcePlaceholder[](table:TTomlTable, key:String, path:String)
	Local result:TSourcePlaceholder[] = New TSourcePlaceholder[0]
	Local node:ITomlNode = table[key]
	If Not node Then Return result
	If Not node.IsArray() Then Throw path + ": '" + key + "' must be an array"
	For Local item:ITomlNode = EachIn node.AsArray().value
		Local placeholder:TSourcePlaceholder = New TSourcePlaceholder
		If item.IsString() Then
			placeholder.name = item.AsString()
			placeholder.kind = "string"
		Else If item.IsTable() Then
			placeholder.name = RequireString(item.AsTable(), "name", path)
			placeholder.kind = RequireString(item.AsTable(), "type", path).ToLower()
		Else
			Throw path + ": '" + key + "' must contain strings or { name, type } tables"
		End If
		If placeholder.kind <> "string" And placeholder.kind <> "integer" Then Throw path + ": unsupported placeholder type '" + placeholder.kind + "'"
		For Local existing:TSourcePlaceholder = EachIn result
			If existing.name = placeholder.name Then Throw path + ": duplicate placeholder '" + placeholder.name + "'"
		Next
		result :+ [placeholder]
	Next
	Return result
End Function

Function ValidateTemplate(message:TSourceMessage, path:String)
	Local seen:TStringMap = New TStringMap
	If message.IsPlural() Then
		For Local form:String = EachIn message.forms
			If form.length Then CollectTemplatePlaceholders(form, message.name, path, seen)
		Next
	Else
		CollectTemplatePlaceholders(message.text, message.name, path, seen)
	End If
	For Local placeholder:TSourcePlaceholder = EachIn message.placeholders
		If Not seen.Contains(placeholder.name) Then Throw path + ": declared placeholder '" + placeholder.name + "' is unused in '" + message.name + "'"
		seen.Remove(placeholder.name)
	Next
	For Local undeclared:String = EachIn seen.Keys()
		Throw path + ": placeholder '" + undeclared + "' is not declared in '" + message.name + "'"
	Next
	If message.IsPlural() Then
		Local selector:TSourcePlaceholder
		For Local placeholder:TSourcePlaceholder = EachIn message.placeholders
			If placeholder.name = message.pluralArgument Then selector = placeholder; Exit
		Next
		If Not selector Then Throw path + ": plural selector '" + message.pluralArgument + "' is not declared in '" + message.name + "'"
		If selector.kind <> "integer" Then Throw path + ": plural selector '" + message.pluralArgument + "' must be an integer"
	End If
End Function

Function CollectTemplatePlaceholders(templateText:String, messageName:String, path:String, seen:TStringMap)
	Local index:Int
	While index < templateText.length
		If templateText[index] = 123 Then
			If index + 1 < templateText.length And templateText[index + 1] = 123 Then index :+ 2; Continue
			Local closing:Int = templateText.Find("}", index + 1)
			If closing < 0 Then Throw path + ": unclosed placeholder in '" + messageName + "'"
			Local name:String = templateText[index + 1..closing]
			If Not name.length Then Throw path + ": empty placeholder in '" + messageName + "'"
			seen.Insert(name, name)
			index = closing + 1
			Continue
		Else If templateText[index] = 125 Then
			If index + 1 < templateText.length And templateText[index + 1] = 125 Then index :+ 2; Continue
			Throw path + ": unmatched closing brace in '" + messageName + "'"
		End If
		index :+ 1
	Wend
End Function

Function ConstantName:String(domain:String, name:String)
	Return domain.ToUpper() + "_MSG_" + name.Replace(".", "_").ToUpper()
End Function

Function TypeName:String(domain:String)
	Return "T" + PascalName(domain) + "Messages"
End Function

Function PascalName:String(name:String)
	Local result:String
	Local upperNext:Int = True
	For Local index:Int = 0 Until name.length
		Local code:Int = name[index]
		If (code >= 65 And code <= 90) Or (code >= 97 And code <= 122) Or (code >= 48 And code <= 57) Then
			Local part:String = Chr(code)
			If upperNext Then part = part.ToUpper()
			result :+ part
			upperNext = False
		Else
			upperNext = True
		End If
	Next
	Return result
End Function

Function Quote:String(value:String)
	Return "~q" + value.Replace("~~", "~~~~").Replace("~q", "~~q").Replace("~r", "~~r").Replace("~n", "~~n").Replace("~t", "~~t") + "~q"
End Function

Function TomlQuote:String(value:String)
	Return "~q" + value.Replace("\", "\\").Replace("~q", "\~q").Replace("~r", "\r").Replace("~n", "\n").Replace("~t", "\t") + "~q"
End Function

Function GenerateSource(source:TMessageFile, outputPath:String)
	Local output:String = "' Generated by bmxlocale from the canonical English catalogue.~n"
	output :+ "' Do not edit this file directly.~n~n"
	output :+ "SuperStrict~n~n"
	output :+ "Import BlitzMax.Locale~n~n"
	For Local message:TSourceMessage = EachIn source.messages
		output :+ "Const " + ConstantName(source.domain, message.name) + ":Int = " + message.id + "~n"
	Next
	output :+ "~nType " + TypeName(source.domain) + "~n"
	For Local message:TSourceMessage = EachIn source.messages
		output :+ "~tFunction " + PascalName(message.name) + ":TLocalisedMessage("
		For Local index:Int = 0 Until message.placeholders.length
			If index Then output :+ ", "
			Local placeholder:TSourcePlaceholder = message.placeholders[index]
			output :+ placeholder.name + ":"
			If placeholder.kind = "integer" Then output :+ "Long" Else output :+ "String"
		Next
		output :+ ")~n"
		If message.IsPlural() Then
			output :+ "~t~tReturn TLocalisedMessage.CreatePlural(" + Quote(source.domain) + ", " + ConstantName(source.domain, message.name) + ", " + Quote(message.pluralArgument) + ", ["
			For Local formIndex:Int = 0 Until PLURAL_FORM_COUNT
				If formIndex Then output :+ ", "
				output :+ Quote(message.forms[formIndex])
			Next
			output :+ "]"
		Else
			output :+ "~t~tReturn TLocalisedMessage.Create(" + Quote(source.domain) + ", " + ConstantName(source.domain, message.name) + ", " + Quote(message.text)
		End If
		If message.placeholders.length Then
			output :+ ", ["
			For Local index:Int = 0 Until message.placeholders.length
				If index Then output :+ ", "
				Local placeholder:TSourcePlaceholder = message.placeholders[index]
				If placeholder.kind = "integer" Then
					output :+ "TMessageArg.CreateInt(" + Quote(placeholder.name) + ", " + placeholder.name + ")"
				Else
					output :+ "TMessageArg.Create(" + Quote(placeholder.name) + ", " + placeholder.name + ")"
				End If
			Next
			output :+ "]"
		Else If message.IsPlural() Then
			output :+ ", New TMessageArg[0]"
		End If
		output :+ ")~n~tEnd Function~n"
	Next
	output :+ "End Type~n"
	If Not SaveText(output, outputPath) Then Throw "Unable to write generated source: " + outputPath
End Function

Function AppendTranslationMessage:String(output:String, message:TSourceMessage, translated:Int)
	output :+ "~n[[message]]~n"
	output :+ "id = " + message.id + "~n"
	output :+ "name = " + TomlQuote(message.name) + "~n"
	If Not translated Then output :+ "translated = false~n"
	If message.IsPlural() Then
		output :+ "plural = " + TomlQuote(message.pluralArgument) + "~n"
		output :+ "forms = { "
		Local first:Int = True
		For Local formIndex:Int = 0 Until PLURAL_FORM_COUNT
			If message.forms[formIndex].length Then
				If Not first Then output :+ ", "
				output :+ PluralName(formIndex) + " = " + TomlQuote(message.forms[formIndex])
				first = False
			End If
		Next
		output :+ " }~n"
	Else
		output :+ "text = " + TomlQuote(message.text) + "~n"
	End If
	output :+ "placeholders = ["
	For Local index:Int = 0 Until message.placeholders.length
		If index Then output :+ ", "
		Local placeholder:TSourcePlaceholder = message.placeholders[index]
		output :+ "{ name = " + TomlQuote(placeholder.name) + ", type = " + TomlQuote(placeholder.kind) + " }"
	Next
	output :+ "]~n"
	Return output
End Function

Function AppendContributors:String(output:String, contributors:TSourceContributor[])
	For Local contributor:TSourceContributor = EachIn contributors
		output :+ "~n[[contributor]]~n"
		output :+ "name = " + TomlQuote(contributor.name) + "~n"
		If contributor.role.length Then output :+ "role = " + TomlQuote(contributor.role) + "~n"
	Next
	Return output
End Function

Function SyncTranslation(source:TMessageFile, locale:String, existing:TMessageFile, outputPath:String)
	locale = TLocaleContext.NormalizeLocale(locale)
	If locale = "en" Then Throw "A translation catalogue must not use the 'en' locale"
	If existing And (existing.domain <> source.domain Or existing.locale <> locale) Then Throw "Existing translation header does not match the requested domain and locale"
	Local output:String = "format = 1~n"
	output :+ "domain = " + TomlQuote(source.domain) + "~n"
	output :+ "locale = " + TomlQuote(locale) + "~n"
	If existing Then output = AppendContributors(output, existing.contributors)
	For Local original:TSourceMessage = EachIn source.messages
		Local translated:TSourceMessage
		If existing Then translated = FindById(existing.messages, original.id)
		If translated And translated.translated Then
			output = AppendTranslationMessage(output, translated, translated.translated)
		Else
			output = AppendTranslationMessage(output, original, False)
		End If
	Next
	If Not SaveText(output, outputPath) Then Throw "Unable to write translation source: " + outputPath
End Function

Function WriteRegistryLock(source:TMessageFile, outputPath:String)
	Local output:String = "format = 1~n"
	output :+ "domain = " + TomlQuote(source.domain) + "~n"
	output :+ "next_id = " + source.nextId + "~n~n"
	output :+ "[ids]~n"
	For Local message:TSourceMessage = EachIn source.messages
		output :+ TomlQuote(String(message.id)) + " = " + TomlQuote(message.name) + "~n"
	Next
	If Not SaveText(output, outputPath) Then Throw "Unable to write registry lock: " + outputPath
End Function

Function VerifyRegistryLock(source:TMessageFile, lock:TRegistryLock)
	If source.domain <> lock.domain Then Throw "Registry lock domain does not match"
	If source.nextId <> lock.nextId Then Throw "Registry next_id changed without updating its lock"
	Local lockedCount:Int
	For Local key:String = EachIn lock.names.Keys()
		lockedCount :+ 1
	Next
	If source.messages.length <> lockedCount Then Throw "Registry message set changed without updating its lock"
	For Local message:TSourceMessage = EachIn source.messages
		Local lockedName:String = String(lock.names.ValueForKey(String(message.id)))
		If Not lockedName.length Then Throw "Message ID " + message.id + " is not present in the registry lock"
		If lockedName <> message.name Then Throw "Message ID " + message.id + " changed from '" + lockedName + "' to '" + message.name + "'"
	Next
End Function

Function FindById:TSourceMessage(messages:TSourceMessage[], id:Int)
	For Local message:TSourceMessage = EachIn messages
		If message.id = id Then Return message
	Next
End Function

Function SamePlaceholders:Int(left:TSourcePlaceholder[], right:TSourcePlaceholder[])
	If left.length <> right.length Then Return False
	For Local value:TSourcePlaceholder = EachIn left
		Local found:Int
		For Local candidate:TSourcePlaceholder = EachIn right
			If value.name = candidate.name And value.kind = candidate.kind Then found = True; Exit
		Next
		If Not found Then Return False
	Next
	Return True
End Function

Function ValidateTranslation(source:TMessageFile, translation:TMessageFile)
	If source.locale <> "en" Then Throw "The canonical registry must use the 'en' locale"
	If source.domain <> translation.domain Then Throw "Catalogue domain does not match the English registry"
	If translation.locale = "en" Then Throw "A translation catalogue must not use the 'en' locale"
	For Local message:TSourceMessage = EachIn translation.messages
		Local original:TSourceMessage = FindById(source.messages, message.id)
		If Not original Then Throw "Translation has unknown message ID " + message.id
		If original.name <> message.name Then Throw "Message ID " + message.id + " must retain the name '" + original.name + "'"
		If original.IsPlural() <> message.IsPlural() Then Throw "Message shape differs for '" + message.name + "'"
		If original.IsPlural() And original.pluralArgument <> message.pluralArgument Then Throw "Plural selector differs for '" + message.name + "'"
		If Not SamePlaceholders(original.placeholders, message.placeholders) Then Throw "Placeholder set differs for '" + message.name + "'"
	Next
End Function

Function CompileCatalogue(source:TMessageFile, translation:TMessageFile, outputPath:String)
	ValidateTranslation(source, translation)
	Local maxId:Int
	For Local message:TSourceMessage = EachIn source.messages
		maxId = Max(maxId, message.id)
	Next
	Local translated:TSourceMessage[] = New TSourceMessage[maxId + 1]
	Local present:Byte[] = New Byte[maxId + 1]
	For Local message:TSourceMessage = EachIn translation.messages
		If Not message.translated Then Continue
		translated[message.id] = message
		present[message.id] = True
	Next

	Local stream:TStream = WriteStream(outputPath)
	If Not stream Then Throw "Unable to write compiled catalogue: " + outputPath
	Local writer:TMPackWriter = New TMPackWriter(stream)
	writer.StartArray(5)
	writer.Write(BMX_LOCALE_CATALOGUE_MAGIC)
	writer.WriteInt(BMX_LOCALE_CATALOGUE_VERSION)
	writer.Write(source.domain)
	writer.Write(translation.locale)
	writer.StartArray(UInt(translated.length))
	For Local index:Int = 0 Until translated.length
		If Not present[index] Then
			writer.WriteNil()
		Else If translated[index].IsPlural() Then
			writer.StartArray(PLURAL_FORM_COUNT)
			For Local formIndex:Int = 0 Until PLURAL_FORM_COUNT
				If translated[index].forms[formIndex].length Then writer.Write(translated[index].forms[formIndex]) Else writer.WriteNil()
			Next
			writer.FinishArray()
		Else
			writer.Write(translated[index].text)
		End If
	Next
	writer.FinishArray()
	writer.FinishArray()
	Local result:EMPackError = writer.Free()
	stream.Close()
	If result <> EMPackError.ok Then Throw "Unable to encode catalogue (MessagePack error " + Int(result) + ")"
End Function

Function IsCataloguePathComponent:Int(value:String)
	If Not value.length Then Return False
	For Local index:Int = 0 Until value.length
		Local code:Int = value[index]
		If (code >= 48 And code <= 57) Or (code >= 97 And code <= 122) Or code = 45 Or code = 95 Then Continue
		Return False
	Next
	Return True
End Function

Function InstallCatalogue:String(cataloguePath:String, sdkPath:String)
	If Not cataloguePath.ToLower().EndsWith(".bmxcat") Then Throw "Compiled catalogue input must use the .bmxcat extension: " + cataloguePath
	If FileType(sdkPath) <> FILETYPE_DIR Then Throw "SDK path is not a directory: " + sdkPath
	Local catalogue:TLocaleCatalogue = TLocaleCatalogue.Load(cataloguePath)
	Local domain:String = catalogue.domain.ToLower()
	Local locale:String = TLocaleContext.NormalizeLocale(catalogue.locale)
	If Not IsCataloguePathComponent(domain) Then Throw "Compiled catalogue has an invalid domain: " + catalogue.domain
	If Not IsCataloguePathComponent(locale) Or locale = "en" Then Throw "Compiled catalogue has an invalid install locale: " + catalogue.locale
	Local destinationDirectory:String = sdkPath + "/bin/locales/" + locale
	If Not CreateDir(destinationDirectory, True) Or FileType(destinationDirectory) <> FILETYPE_DIR Then
		Throw "Unable to create locale catalogue directory: " + destinationDirectory
	End If
	Local destination:String = destinationDirectory + "/" + domain + ".bmxcat"
	If Not CopyFile(cataloguePath, destination) Then Throw "Unable to install locale catalogue: " + destination
	Return destination
End Function

Function VerifyCatalogue:TLocaleCatalogue(cataloguePath:String)
	If Not cataloguePath.ToLower().EndsWith(".bmxcat") Then Throw "Compiled catalogue input must use the .bmxcat extension: " + cataloguePath
	Local catalogue:TLocaleCatalogue = TLocaleCatalogue.Load(cataloguePath)
	If Not IsCataloguePathComponent(catalogue.domain.ToLower()) Then Throw "Compiled catalogue has an invalid domain: " + catalogue.domain
	Local locale:String = TLocaleContext.NormalizeLocale(catalogue.locale)
	If Not IsCataloguePathComponent(locale) Or locale = "en" Then Throw "Compiled catalogue has an invalid locale: " + catalogue.locale
	Return catalogue
End Function

Type TExtractionCandidate
	Field source:String
	Field line:Int
	Field callName:String
	Field code:String
	Field messageExpression:String
End Type

Function SortCandidates(values:TExtractionCandidate[])
	For Local index:Int = 1 Until values.length
		Local value:TExtractionCandidate = values[index]
		Local target:Int = index
		While target > 0 And (values[target - 1].line > value.line Or (values[target - 1].line = value.line And values[target - 1].callName > value.callName))
			values[target] = values[target - 1]
			target :- 1
		Wend
		values[target] = value
	Next
End Function

Function SortStrings(values:String[])
	For Local index:Int = 1 Until values.length
		Local value:String = values[index]
		Local target:Int = index
		While target > 0 And values[target - 1] > value
			values[target] = values[target - 1]
			target :- 1
		Wend
		values[target] = value
	Next
End Function

Function CollectSourceFiles:String[](path:String)
	Local result:String[] = New String[0]
	Select FileType(path)
		Case FILETYPE_FILE
			If path.ToLower().EndsWith(".bmx") Then result :+ [path]
		Case FILETYPE_DIR
			Local names:String[] = LoadDir(path)
			SortStrings(names)
			For Local name:String = EachIn names
				If name = "." Or name = ".." Or name = ".git" Or name = ".bmx" Then Continue
				result :+ CollectSourceFiles(path + "/" + name)
			Next
		Default
			Throw "Source path does not exist: " + path
	End Select
	Return result
End Function

Function SourceLine:Int(source:String, offset:Int)
	Local line:Int = 1
	For Local index:Int = 0 Until Min(offset, source.length)
		If source[index] = 10 Then line :+ 1
	Next
	Return line
End Function

Function ClosingParenthesis:Int(source:String, opening:Int)
	Local depth:Int = 1
	Local quoted:Int
	For Local index:Int = opening + 1 Until source.length
		Local code:Int = source[index]
		If quoted Then
			If code = 126 Then
				index :+ 1
			Else If code = 34 Then
				quoted = False
			End If
		Else
			Select code
				Case 34
					quoted = True
				Case 40
					depth :+ 1
				Case 41
					depth :- 1
					If depth = 0 Then Return index
			End Select
		End If
	Next
	Return -1
End Function

Function SplitCallArguments:String[](source:String, startOffset:Int, endOffset:Int)
	Local result:String[] = New String[0]
	Local argumentStart:Int = startOffset
	Local depth:Int
	Local quoted:Int
	For Local index:Int = startOffset Until endOffset
		Local code:Int = source[index]
		If quoted Then
			If code = 126 Then
				index :+ 1
			Else If code = 34 Then
				quoted = False
			End If
		Else
			Select code
				Case 34
					quoted = True
				Case 40, 91, 123
					depth :+ 1
				Case 41, 93, 125
					depth :- 1
				Case 44
					If depth = 0 Then
						result :+ [source[argumentStart..index].Trim()]
						argumentStart = index + 1
					End If
			End Select
		End If
	Next
	result :+ [source[argumentStart..endOffset].Trim()]
	Return result
End Function

Function LiteralValue:String(expression:String)
	expression = expression.Trim()
	If expression.length < 2 Or expression[0] <> 34 Then Return ""
	Local result:String
	For Local index:Int = 1 Until expression.length
		Local code:Int = expression[index]
		If code = 34 Then Return result
		If code = 126 And index + 1 < expression.length Then
			index :+ 1
			Select expression[index]
				Case 113 result :+ Chr(34)
				Case 110 result :+ "~n"
				Case 114 result :+ "~r"
				Case 116 result :+ "~t"
				Default result :+ Chr(expression[index])
			End Select
		Else
			result :+ Chr(code)
		End If
	Next
	Return ""
End Function

Function RelativeSource:String(root:String, path:String)
	Local normalizedRoot:String = root.Replace("\", "/")
	Local normalizedPath:String = path.Replace("\", "/")
	If FileType(root) = FILETYPE_DIR And normalizedPath.StartsWith(normalizedRoot + "/") Then Return normalizedPath[normalizedRoot.length + 1..]
	Return normalizedPath
End Function

Function ExtractFromFile:TExtractionCandidate[](root:String, path:String)
	Local result:TExtractionCandidate[] = New TExtractionCandidate[0]
	Local source:String = LoadText(path)
	Local callNames:String[] = ["AddDiagnostic", "AddUnsupported", "TDiagnostic.Create", "TCompilerDiagnostic.Create", "CmdError"]
	For Local callName:String = EachIn callNames
		Local marker:String = callName + "("
		Local offset:Int
		While offset < source.length
			Local found:Int = source.Find(marker, offset)
			If found < 0 Then Exit
			Local opening:Int = found + callName.length
			Local closing:Int = ClosingParenthesis(source, opening)
			If closing < 0 Then Exit
			Local arguments:String[] = SplitCallArguments(source, opening + 1, closing)
			Local code:String
			Local messageExpression:String
			If callName = "CmdError" Then
				If arguments.length Then messageExpression = arguments[0]
			Else If arguments.length >= 2 Then
				code = LiteralValue(arguments[0])
				messageExpression = arguments[1]
			End If
			' A hard-coded message begins with a literal. Quotes appearing later in
			' a generated localisation wrapper are placeholder arguments, not the
			' diagnostic text itself.
			If messageExpression.Trim().StartsWith("~q") Then
				Local candidate:TExtractionCandidate = New TExtractionCandidate
				candidate.source = RelativeSource(root, path)
				candidate.line = SourceLine(source, found)
				candidate.callName = callName
				candidate.code = code
				candidate.messageExpression = messageExpression
				result :+ [candidate]
			End If
			offset = closing + 1
		Wend
	Next
	Local lines:String[] = source.Replace("~r", "").Split("~n")
	Local statementNames:String[] = ["CmdError", "Throw"]
	For Local lineIndex:Int = 0 Until lines.length
		For Local statementName:String = EachIn statementNames
			Local marker:String = statementName + " "
			Local found:Int = lines[lineIndex].Find(marker)
			If found < 0 Then Continue
			' Ignore marker words inside quoted diagnostic text or comments.
			Local firstQuote:Int = lines[lineIndex].Find("~q")
			If firstQuote >= 0 And firstQuote < found Then Continue
			Local firstComment:Int = lines[lineIndex].Find("'")
			If firstComment >= 0 And firstComment < found Then Continue
			Local expression:String = lines[lineIndex][found + marker.length..].Trim()
			If statementName = "CmdError" Then
				Local arguments:String[] = SplitCallArguments(expression, 0, expression.length)
				If arguments.length Then expression = arguments[0]
			End If
			If expression.Find("~q") < 0 Then Continue
			Local candidate:TExtractionCandidate = New TExtractionCandidate
			candidate.source = RelativeSource(root, path)
			candidate.line = lineIndex + 1
			candidate.callName = statementName
			candidate.messageExpression = expression
			result :+ [candidate]
		Next
	Next
	SortCandidates(result)
	Return result
End Function

Function WriteExtractionReport(domain:String, sourceRoot:String, outputPath:String)
	Local candidates:TExtractionCandidate[] = New TExtractionCandidate[0]
	For Local path:String = EachIn CollectSourceFiles(sourceRoot)
		candidates :+ ExtractFromFile(sourceRoot, path)
	Next
	Local output:String = "format = 1~n"
	output :+ "domain = " + TomlQuote(domain) + "~n"
	output :+ "source_root = " + TomlQuote(sourceRoot.Replace("\", "/")) + "~n"
	output :+ "candidate_count = " + candidates.length + "~n"
	For Local candidate:TExtractionCandidate = EachIn candidates
		output :+ "~n[[candidate]]~n"
		output :+ "source = " + TomlQuote(candidate.source) + "~n"
		output :+ "line = " + candidate.line + "~n"
		output :+ "call = " + TomlQuote(candidate.callName) + "~n"
		If candidate.code.length Then output :+ "diagnostic_code = " + TomlQuote(candidate.code) + "~n"
		output :+ "message_expression = " + TomlQuote(candidate.messageExpression) + "~n"
	Next
	If Not SaveText(output, outputPath) Then Throw "Unable to write extraction report: " + outputPath
End Function

Function Usage()
	Print "bmxlocale check <english.toml> [translation.toml]"
	Print "bmxlocale generate <english.toml> <output.bmx>"
	Print "bmxlocale compile <english.toml> <translation.toml> <output.bmxcat>"
	Print "bmxlocale verify <catalogue.bmxcat>"
	Print "bmxlocale install <sdk-path> <catalogue.bmxcat> [catalogue.bmxcat ...]"
	Print "bmxlocale init <english.toml> <locale> <output.toml>"
	Print "bmxlocale sync <english.toml> <translation.toml> <output.toml>"
	Print "bmxlocale lock <english.toml> <output.lock.toml>"
	Print "bmxlocale verify-lock <english.toml> <lock.toml>"
	Print "bmxlocale extract <domain> <source-path> <output.toml>"
End Function

Try
	' BlitzMax applications start in AppDir. Command-line paths conventionally
	' belong to the directory from which the tool was launched.
	If Not ChangeDir(LaunchDir) Then Throw "Unable to use launch directory: " + LaunchDir
	If AppArgs.length < 2 Then Usage(); End
	Select AppArgs[1].ToLower()
		Case "check"
			If AppArgs.length <> 3 And AppArgs.length <> 4 Then Usage(); End
			Local source:TMessageFile = TMessageFile.Load(AppArgs[2])
			If source.locale <> "en" Then Throw "The canonical registry must use the 'en' locale"
			If AppArgs.length = 4 Then
				Local translation:TMessageFile = TMessageFile.Load(AppArgs[3])
				ValidateTranslation(source, translation)
			End If
			Print "Valid " + AppArgs[AppArgs.length - 1]
		Case "generate"
			If AppArgs.length <> 4 Then Usage(); End
			Local source:TMessageFile = TMessageFile.Load(AppArgs[2])
			If source.locale <> "en" Then Throw "Generated APIs must use the canonical 'en' catalogue"
			GenerateSource(source, AppArgs[3])
			Print "Generated " + AppArgs[3]
		Case "compile"
			If AppArgs.length <> 5 Then Usage(); End
			If Not AppArgs[4].ToLower().EndsWith(".bmxcat") Then Throw "Compiled catalogue output must use the .bmxcat extension"
			Local source:TMessageFile = TMessageFile.Load(AppArgs[2])
			Local translation:TMessageFile = TMessageFile.Load(AppArgs[3])
			CompileCatalogue(source, translation, AppArgs[4])
			Print "Compiled " + AppArgs[4]
		Case "verify"
			If AppArgs.length <> 3 Then Usage(); End
			Local catalogue:TLocaleCatalogue = VerifyCatalogue(AppArgs[2])
			Print "Verified " + AppArgs[2] + " (" + catalogue.domain + "/" + catalogue.locale + ")"
		Case "install"
			If AppArgs.length < 4 Then Usage(); End
			For Local index:Int = 3 Until AppArgs.length
				Print "Installed " + InstallCatalogue(AppArgs[index], AppArgs[2])
			Next
		Case "init"
			If AppArgs.length <> 5 Then Usage(); End
			Local source:TMessageFile = TMessageFile.Load(AppArgs[2])
			SyncTranslation(source, AppArgs[3], Null, AppArgs[4])
			Print "Initialised " + AppArgs[4]
		Case "sync"
			If AppArgs.length <> 5 Then Usage(); End
			Local source:TMessageFile = TMessageFile.Load(AppArgs[2])
			Local translation:TMessageFile = TMessageFile.Load(AppArgs[3])
			SyncTranslation(source, translation.locale, translation, AppArgs[4])
			Print "Synchronised " + AppArgs[4]
		Case "lock"
			If AppArgs.length <> 4 Then Usage(); End
			Local source:TMessageFile = TMessageFile.Load(AppArgs[2])
			WriteRegistryLock(source, AppArgs[3])
			Print "Locked " + AppArgs[3]
		Case "verify-lock"
			If AppArgs.length <> 4 Then Usage(); End
			Local source:TMessageFile = TMessageFile.Load(AppArgs[2])
			Local lock:TRegistryLock = TRegistryLock.Load(AppArgs[3])
			VerifyRegistryLock(source, lock)
			Print "Verified " + AppArgs[3]
		Case "extract"
			If AppArgs.length <> 5 Then Usage(); End
			WriteExtractionReport(AppArgs[2], AppArgs[3], AppArgs[4])
			Print "Extracted candidates to " + AppArgs[4]
		Default
			Usage()
			End
	End Select
Catch error:Object
	ErrPrint "bmxlocale: " + error.ToString()
	Exit_ 1
End Try
