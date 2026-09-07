' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.FileSystem
Import BRL.MaxUtil
Import BRL.Stream
Import Pub.StdC
Import Text.MPack

Const BMX_LOCALE_CATALOGUE_MAGIC:String = "bmx.locale"
Const BMX_LOCALE_CATALOGUE_VERSION:Int = 2

Const MESSAGE_ARG_STRING:Int = 0
Const MESSAGE_ARG_INTEGER:Int = 1

Const PLURAL_ZERO:Int = 0
Const PLURAL_ONE:Int = 1
Const PLURAL_TWO:Int = 2
Const PLURAL_FEW:Int = 3
Const PLURAL_MANY:Int = 4
Const PLURAL_OTHER:Int = 5
Const PLURAL_FORM_COUNT:Int = 6

Rem
bbdoc: A named value substituted into a localised message.
End Rem
Type TMessageArg
	Field name:String
	Field value:String
	Field kind:Int
	Field integerValue:Long

	Function Create:TMessageArg(name:String, value:String)
		Local argument:TMessageArg = New TMessageArg
		argument.name = name
		argument.value = value
		Return argument
	End Function

	Function CreateInt:TMessageArg(name:String, value:Long)
		Local argument:TMessageArg = Create(name, String(value))
		argument.kind = MESSAGE_ARG_INTEGER
		argument.integerValue = value
		Return argument
	End Function
End Type

Rem
bbdoc: A stable domain/id reference and the generated English fallback text.
End Rem
Type TLocalisedMessage
	Field domain:String
	Field id:Int
	Field defaultText:String
	Field defaultForms:String[]
	Field pluralArgument:String
	Field arguments:TMessageArg[]

	Function Create:TLocalisedMessage(domain:String, id:Int, defaultText:String, arguments:TMessageArg[] = Null)
		If Not domain.length Then Throw "A localised message requires a domain"
		If id <= 0 Then Throw "A localised message ID must be positive"
		Local message:TLocalisedMessage = New TLocalisedMessage
		message.domain = domain
		message.id = id
		message.defaultText = defaultText
		If arguments Then
			message.arguments = arguments
		Else
			message.arguments = New TMessageArg[0]
		End If
		Return message
	End Function

	Function CreatePlural:TLocalisedMessage(domain:String, id:Int, pluralArgument:String, forms:String[], arguments:TMessageArg[])
		If forms.length <> PLURAL_FORM_COUNT Or Not forms[PLURAL_OTHER].length Then Throw "A plural message requires six form slots and an 'other' form"
		Local message:TLocalisedMessage = Create(domain, id, forms[PLURAL_OTHER], arguments)
		message.pluralArgument = pluralArgument
		message.defaultForms = forms
		Return message
	End Function

	Method IsPlural:Int()
		Return pluralArgument.length > 0
	End Method

	Method Render:String(context:TLocaleContext = Null)
		If context Then Return context.Render(Self)
		Return TLocale.Render(Self)
	End Method
End Type

Type TCompiledMessage
	Field text:String
	Field forms:String[]
	Field plural:Int
End Type

Type TLocaleCatalogueChain
	Field values:TLocaleCatalogue[]
End Type

Rem
bbdoc: A compiled catalogue for one locale and one message domain.
End Rem
Type TLocaleCatalogue
	Field domain:String
	Field locale:String
	Field messages:TCompiledMessage[]
	Field present:Byte[]

	Function Load:TLocaleCatalogue(path:String)
		Local stream:TStream = ReadStream(path)
		If Not stream Then Throw "Unable to open locale catalogue: " + path

		Local reader:TMPackReader = New TMPackReader(stream, TMPackLimits.Create(1024 * 1024, 1024, 1024 * 1024, 8))
		Local catalogue:TLocaleCatalogue = New TLocaleCatalogue
		Local rootCount:UInt = reader.BeginArray()
		If rootCount <> 5 Then reader.FlagError(EMPackError.error_data)

		Local magic:String = reader.ReadString()
		Local version:Int = reader.ReadInt()
		catalogue.domain = reader.ReadString()
		catalogue.locale = reader.ReadString()
		Local entryCount:UInt = reader.BeginArray()
		If entryCount > UInt(2147483647) Then reader.FlagError(EMPackError.error_too_big)
		catalogue.messages = New TCompiledMessage[Int(entryCount)]
		catalogue.present = New Byte[Int(entryCount)]
		For Local index:Int = 0 Until Int(entryCount)
			If reader.NextType() = EMPackType.type_nil Then
				reader.ReadNil()
			Else If reader.NextType() = EMPackType.type_str Then
				Local message:TCompiledMessage = New TCompiledMessage
				message.text = reader.ReadString()
				catalogue.messages[index] = message
				catalogue.present[index] = True
			Else If reader.NextType() = EMPackType.type_array Then
				Local formCount:UInt = reader.BeginArray()
				If formCount <> PLURAL_FORM_COUNT Then reader.FlagError(EMPackError.error_data)
				Local message:TCompiledMessage = New TCompiledMessage
				message.plural = True
				message.forms = New String[PLURAL_FORM_COUNT]
				For Local formIndex:Int = 0 Until PLURAL_FORM_COUNT
					If reader.NextType() = EMPackType.type_nil Then
						reader.ReadNil()
					Else
						message.forms[formIndex] = reader.ReadString()
					End If
				Next
				reader.DoneArray()
				If Not message.forms[PLURAL_OTHER].length Then reader.FlagError(EMPackError.error_data)
				catalogue.messages[index] = message
				catalogue.present[index] = True
			Else
				reader.FlagError(EMPackError.error_type)
			End If
		Next
		reader.DoneArray()
		reader.DoneArray()

		If magic <> BMX_LOCALE_CATALOGUE_MAGIC Or version <> BMX_LOCALE_CATALOGUE_VERSION Or Not catalogue.domain.length Or Not catalogue.locale.length Then
			reader.FlagError(EMPackError.error_data)
		End If
		Local result:EMPackError = reader.Free()
		stream.Close()
		If result <> EMPackError.ok Then Throw "Invalid locale catalogue '" + path + "' (MessagePack error " + Int(result) + ")"
		Return catalogue
	End Function

	Method Contains:Int(id:Int)
		Return id > 0 And id < present.length And present[id]
	End Method

	Method Message:TCompiledMessage(id:Int)
		If Contains(id) Then Return messages[id]
	End Method
End Type

Rem
bbdoc: A set of catalogues used to render messages for one locale preference.
End Rem
Type TLocaleContext
	Field catalogues:TMap = New TMap
	Field locale:String = "en"

	Method New(locale:String = "en")
		Self.locale = NormalizeLocale(locale)
	End Method

	Method UseCatalogue(catalogue:TLocaleCatalogue)
		If Not catalogue Then Throw "Cannot use a null locale catalogue"
		Local key:String = catalogue.domain.ToLower()
		Local chain:TLocaleCatalogueChain = TLocaleCatalogueChain(catalogues.ValueForKey(key))
		If Not chain Then
			chain = New TLocaleCatalogueChain
			catalogues.Insert(key, chain)
		End If
		For Local existing:TLocaleCatalogue = EachIn chain.values
			If existing.locale = catalogue.locale Then Return
		Next
		chain.values :+ [catalogue]
	End Method

	Method LoadCatalogue:TLocaleCatalogue(path:String)
		Local catalogue:TLocaleCatalogue = TLocaleCatalogue.Load(path)
		UseCatalogue(catalogue)
		Return catalogue
	End Method

	Method Clear()
		catalogues = New TMap
	End Method

	Method LoadDomain:Int(domain:String, catalogueRoot:String)
		Return LoadDomainFromRoots(domain, [catalogueRoot])
	End Method

	Rem
	bbdoc: Loads one domain from ordered catalogue roots, preserving locale specificity.
	about: For each regional-to-base locale candidate, earlier roots take precedence.
	End Rem
	Method LoadDomainFromRoots:Int(domain:String, catalogueRoots:String[])
		Local loaded:Int
		Local candidate:String = locale
		While candidate.length And candidate <> "en"
			For Local catalogueRoot:String = EachIn catalogueRoots
				If Not catalogueRoot.length Then Continue
				Local path:String = catalogueRoot + "/" + candidate + "/" + domain.ToLower() + ".bmxcat"
				If FileType(path) = FILETYPE_FILE Then
					Local catalogue:TLocaleCatalogue = TLocaleCatalogue.Load(path)
					If catalogue.domain.ToLower() <> domain.ToLower() Then Throw "Locale catalogue domain mismatch: " + path
					If NormalizeLocale(catalogue.locale) <> candidate Then Throw "Locale catalogue locale mismatch: " + path
					UseCatalogue(catalogue)
					loaded :+ 1
				End If
			Next
			Local separator:Int = candidate.FindLast("-")
			If separator < 0 Then Exit
			candidate = candidate[..separator]
		Wend
		Return loaded
	End Method

	Method Render:String(message:TLocalisedMessage)
		If Not message Then Return ""
		Local templateText:String = message.defaultText
		Local chain:TLocaleCatalogueChain = TLocaleCatalogueChain(catalogues.ValueForKey(message.domain.ToLower()))
		Local compiled:TCompiledMessage
		If chain Then
			For Local catalogue:TLocaleCatalogue = EachIn chain.values
				compiled = catalogue.Message(message.id)
				If compiled Then Exit
			Next
		End If
		If message.IsPlural() Then
			Local category:Int = PluralCategory(message)
			templateText = PluralText(message.defaultForms, category)
			If compiled And compiled.plural Then templateText = PluralText(compiled.forms, category)
		Else If compiled And Not compiled.plural Then
			templateText = compiled.text
		End If
		Return FormatTemplate(templateText, message.arguments)
	End Method

	Method PluralCategory:Int(message:TLocalisedMessage)
		Local value:Long
		For Local argument:TMessageArg = EachIn message.arguments
			If argument And argument.name = message.pluralArgument And argument.kind = MESSAGE_ARG_INTEGER Then
				value = argument.integerValue
				Exit
			End If
		Next
		Local language:String = locale
		Local separator:Int = language.Find("-")
		If separator >= 0 Then language = language[..separator]
		If value < 0 Then value = -value
		Local mod10:Int = Int(value Mod 10)
		Local mod100:Int = Int(value Mod 100)
		Select language
			Case "ar"
				If value = 0 Then Return PLURAL_ZERO
				If value = 1 Then Return PLURAL_ONE
				If value = 2 Then Return PLURAL_TWO
				If mod100 >= 3 And mod100 <= 10 Then Return PLURAL_FEW
				If mod100 >= 11 And mod100 <= 99 Then Return PLURAL_MANY
			Case "cs", "sk"
				If value = 1 Then Return PLURAL_ONE
				If value >= 2 And value <= 4 Then Return PLURAL_FEW
			Case "fr"
				If value = 0 Or value = 1 Then Return PLURAL_ONE
			Case "pl"
				If value = 1 Then Return PLURAL_ONE
				If mod10 >= 2 And mod10 <= 4 And (mod100 < 12 Or mod100 > 14) Then Return PLURAL_FEW
				If mod10 = 0 Or mod10 = 1 Or mod10 >= 5 Or (mod100 >= 12 And mod100 <= 14) Then Return PLURAL_MANY
			Case "ru", "uk", "be"
				If mod10 = 1 And mod100 <> 11 Then Return PLURAL_ONE
				If mod10 >= 2 And mod10 <= 4 And (mod100 < 12 Or mod100 > 14) Then Return PLURAL_FEW
				If mod10 = 0 Or mod10 >= 5 Or (mod100 >= 11 And mod100 <= 14) Then Return PLURAL_MANY
			Case "sl"
				If mod100 = 1 Then Return PLURAL_ONE
				If mod100 = 2 Then Return PLURAL_TWO
				If mod100 = 3 Or mod100 = 4 Then Return PLURAL_FEW
			Case "ro"
				If value = 1 Then Return PLURAL_ONE
				If value = 0 Or (mod100 >= 1 And mod100 <= 19) Then Return PLURAL_FEW
			Default
				If value = 1 Then Return PLURAL_ONE
		End Select
		Return PLURAL_OTHER
	End Method

	Function NormalizeLocale:String(value:String)
		Local result:String = value.Trim().ToLower().Replace("_", "-")
		Local dot:Int = result.Find(".")
		If dot >= 0 Then result = result[..dot]
		Local modifier:Int = result.Find("@")
		If modifier >= 0 Then result = result[..modifier]
		If result = "c" Or result = "posix" Or Not result.length Then Return "en"
		Return result
	End Function

	Method PluralText:String(forms:String[], category:Int)
		If forms And category >= 0 And category < forms.length And forms[category].length Then Return forms[category]
		If forms And forms.length > PLURAL_OTHER Then Return forms[PLURAL_OTHER]
	End Method

	Method FormatTemplate:String(templateText:String, arguments:TMessageArg[])
		Local result:String
		Local index:Int
		While index < templateText.length
			If templateText[index] = 123 Then
				If index + 1 < templateText.length And templateText[index + 1] = 123 Then
					result :+ "{"
					index :+ 2
					Continue
				End If
				Local closing:Int = templateText.Find("}", index + 1)
				If closing > index + 1 Then
					Local name:String = templateText[index + 1..closing]
					Local replacement:String
					Local found:Int
					For Local argument:TMessageArg = EachIn arguments
						If argument And argument.name = name Then
							replacement = argument.value
							found = True
							Exit
						End If
					Next
					If found Then
						result :+ replacement
					Else
						result :+ templateText[index..closing + 1]
					End If
					index = closing + 1
					Continue
				End If
			Else If templateText[index] = 125 And index + 1 < templateText.length And templateText[index + 1] = 125 Then
				result :+ "}"
				index :+ 2
				Continue
			End If
			result :+ Chr(templateText[index])
			index :+ 1
		Wend
		Return result
	End Method
End Type

Rem
bbdoc: Process-default locale context used by ordinary command-line tools.
End Rem
Type TLocale
	Global defaultContext:TLocaleContext = New TLocaleContext(SystemLocale())

	Function SystemLocale:String()
		Local value:String = getenv_("BMX_LOCALE")
		If Not value.length Then value = getenv_("LC_ALL")
		If Not value.length Then value = getenv_("LC_MESSAGES")
		If Not value.length Then value = getenv_("LANG")
		Return TLocaleContext.NormalizeLocale(value)
	End Function

	Function SetLocale(locale:String)
		defaultContext = New TLocaleContext(locale)
	End Function

	Function Locale:String()
		Return defaultContext.locale
	End Function

	Function UseCatalogue(catalogue:TLocaleCatalogue)
		defaultContext.UseCatalogue(catalogue)
	End Function

	Function LoadCatalogue:TLocaleCatalogue(path:String)
		Return defaultContext.LoadCatalogue(path)
	End Function

	Function Clear()
		defaultContext = New TLocaleContext("en")
	End Function

	Function LoadDomain:Int(domain:String, catalogueRoot:String)
		Return defaultContext.LoadDomain(domain, catalogueRoot)
	End Function

	Rem
	bbdoc: Selects a locale and loads selected toolchain domains from an SDK.
	about: Catalogue roots use the installed layout bin/locales/[locale]/[domain].bmxcat.
	BMX_LOCALE_PATH is searched first so development catalogues override installed catalogues.
	End Rem
	Function ConfigureToolchain(domains:String[], locale:String = "", sdkPath:String = "")
		If Not locale.length Then locale = SystemLocale()
		If Not sdkPath.length Then sdkPath = BlitzMaxPath()
		SetLocale(locale)
		Local roots:String[] = New String[0]
		Local extraRoot:String = getenv_("BMX_LOCALE_PATH")
		If extraRoot.length Then roots :+ [extraRoot]
		roots :+ [sdkPath + "/bin/locales"]
		For Local domain:String = EachIn domains
			If domain.length Then defaultContext.LoadDomainFromRoots(domain, roots)
		Next
	End Function

	Function Render:String(message:TLocalisedMessage)
		Return defaultContext.Render(message)
	End Function
End Type
