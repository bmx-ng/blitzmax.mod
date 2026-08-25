' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BlitzMax.Language

' Central ABI-name policy. Ordinary private names use the new deterministic
' scheme. NoMangle retains the legacy containing-scope name and suppresses only
' the overload-signature suffix.
Type TCompilerAbiNamer
	Function GlobalName:String(model:TSemanticModel, symbol:TSymbol, symbolId:String)
		If model And model.moduleName.length And symbol And symbol.visibility = VISIBILITY_PUBLIC Then
			Local result:String = model.moduleName.ToLower().Replace(".", "_")
			For Local owner:String = EachIn ContainingTypeNames(symbol)
				result :+ "_" + owner
			Next
			Return Sanitize(result + "_" + symbol.name)
		End If
		Local sourceName:String = "global"
		If symbol Then sourceName = symbol.name
		Return "bmx_global_" + Sanitize(symbolId + "_" + sourceName)
	End Function

	Function RoutineName:String(model:TSemanticModel, symbol:TSymbol, functionId:String)
		If HasContainingRoutine(symbol) Then Return PrivateRoutineName(model, symbol, functionId)
		If symbol And symbol.metadata And symbol.metadata.Has("nomangle") Then Return LegacyRoutineName(model, symbol)
		If model And model.moduleName.length And (IsPublishedSymbol(symbol) Or HasPublishedContainingType(symbol)) Then Return PublicModuleRoutineName(model, symbol)
		Return PrivateRoutineName(model, symbol, functionId)
	End Function

	Function PrivateRoutineName:String(model:TSemanticModel, symbol:TSymbol, functionId:String)
		Local sourceName:String = "routine"
		If symbol Then sourceName = RoutineSourceName(symbol.name)
		Local ownerPrefix:String
		If model And model.moduleName.length Then ownerPrefix = model.moduleName.ToLower().Replace(".", "_") + "_"
		Return "bmx_" + Sanitize(ownerPrefix + functionId + "_" + sourceName)
	End Function

	Function PublicModuleRoutineName:String(model:TSemanticModel, symbol:TSymbol)
		Local result:String = model.moduleName.ToLower().Replace(".", "_")
		For Local owner:String = EachIn ContainingTypeNames(symbol)
			result :+ "_" + owner
		Next
		result :+ "_" + RoutineSourceName(symbol.name)
		' These BRL.Blitz entry points are part of the runtime/native-header
		' authority and predate signature-suffixed ordinary ABI names. Native C
		' sources call them directly, so rebuilding the core module must retain
		' the established symbols.
		If model.moduleName.ToLower() = "brl.blitz" Then
			Select symbol.name.ToLower()
				Case "runtimeerror", "illegalargumenterror"
					Return Sanitize(result)
				Case "max"
					If symbol.parameters.length = 2 And symbol.parameters[0] And symbol.parameters[1] Then
						Local leftType:TSemanticType = symbol.parameters[0].semanticType
						Local rightType:TSemanticType = symbol.parameters[1].semanticType
						If leftType And rightType And leftType.DisplayName().ToLower() = "int" And rightType.DisplayName().ToLower() = "int" Then
							Return Sanitize(result)
						End If
					End If
			End Select
		End If
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			result :+ "__"
			If parameter And parameter.semanticType Then result :+ TypeKey(parameter.semanticType) Else result :+ "unknown"
			If parameter And parameter.passingMode = PARAMETER_PASS_VAR Then result :+ "V"
		Next
		Return Sanitize(result)
	End Function

	Function ClassName:String(model:TSemanticModel, symbol:TSymbol, classId:String)
		If model And model.moduleName.length And symbol And symbol.visibility = VISIBILITY_PUBLIC Then
			Return PublishedLayoutTypeName(model, symbol)
		End If
		Local sourceName:String = "type"
		If symbol Then sourceName = symbol.name
		Return "bmx_class_" + Sanitize(classId + "_" + sourceName)
	End Function

	Function PublishedLayoutTypeName:String(model:TSemanticModel, symbol:TSymbol)
		Local result:String
		If model Then result = model.moduleName.ToLower().Replace(".", "_")
		For Local owner:String = EachIn ContainingTypeNames(symbol)
			result :+ "_" + owner
		Next
		If symbol Then result :+ "_" + symbol.name
		Return Sanitize(result)
	End Function

	Function FieldName:String(classAbiName:String, fieldName:String)
		Return Sanitize("_" + classAbiName.ToLower() + "_" + fieldName.ToLower())
	End Function

	Function ClassSlotName:String(symbol:TSymbol)
		If Not symbol Then Return ""
		Local prefix:String = "f_"
		Local declaration:TRoutineDeclarationSyntax = TRoutineDeclarationSyntax(symbol.declaration)
		If declaration And declaration.isMethod Then prefix = "m_"
		Return ClassSlotNameWithPrefix(symbol, prefix)
	End Function

	' Interface requirements are instance methods even when they came from a
	' compact interface record rather than a source Method declaration.  Do not
	' let that representation detail give their class implementation slot a
	' Type-function prefix.
	Function ClassMethodSlotName:String(symbol:TSymbol)
		If Not symbol Then Return ""
		Return ClassSlotNameWithPrefix(symbol, "m_")
	End Function

	Function ClassSlotNameWithPrefix:String(symbol:TSymbol, prefix:String)
		Local result:String = prefix + RoutineSourceName(symbol.name)
		For Local parameter:TSemanticParameter = EachIn symbol.parameters
			result :+ "__"
			If parameter And parameter.semanticType Then result :+ TypeKey(parameter.semanticType) Else result :+ "unknown"
			If parameter And parameter.passingMode = PARAMETER_PASS_VAR Then result :+ "V"
		Next
		Return Sanitize(result)
	End Function

	Function ContainingTypeNames:String[](symbol:TSymbol)
		Local owners:String[]
		If Not symbol Then Return owners
		Local scope:TScope = symbol.containingScope
		While scope
			If scope.owner And (scope.owner.kind = SYMBOL_TYPE Or scope.owner.kind = SYMBOL_STRUCT Or scope.owner.kind = SYMBOL_INTERFACE) Then owners = [scope.owner.name] + owners
			scope = scope.parent
		Wend
		Return owners
	End Function

	Function HasContainingRoutine:Int(symbol:TSymbol)
		If Not symbol Then Return False
		Local scope:TScope = symbol.containingScope
		While scope
			If scope.owner And scope.owner.kind = SYMBOL_ROUTINE Then Return True
			scope = scope.parent
		Wend
		Return False
	End Function

	Function IsPublishedSymbol:Int(symbol:TSymbol)
		If Not symbol Or symbol.visibility <> VISIBILITY_PUBLIC Then Return False
		Return PublishedContainingTypes(symbol)
	End Function

	Function HasPublishedContainingType:Int(symbol:TSymbol)
		If Not symbol Then Return False
		Local found:Int
		Local scope:TScope = symbol.containingScope
		While scope
			If scope.owner And (scope.owner.kind = SYMBOL_TYPE Or scope.owner.kind = SYMBOL_STRUCT Or scope.owner.kind = SYMBOL_INTERFACE) Then
				found = True
				If scope.owner.visibility <> VISIBILITY_PUBLIC Then Return False
			End If
			scope = scope.parent
		Wend
		Return found
	End Function

	Function PublishedContainingTypes:Int(symbol:TSymbol)
		If Not symbol Then Return False
		Local scope:TScope = symbol.containingScope
		While scope
			If scope.owner And (scope.owner.kind = SYMBOL_TYPE Or scope.owner.kind = SYMBOL_STRUCT Or scope.owner.kind = SYMBOL_INTERFACE) And scope.owner.visibility <> VISIBILITY_PUBLIC Then Return False
			scope = scope.parent
		Wend
		Return True
	End Function

	Function TypeKey:String(semanticType:TSemanticType)
		Local builtin:TBuiltinSemanticType = TBuiltinSemanticType(semanticType)
		If builtin Then Return "B" + Sanitize(builtin.name.ToLower())
		Local pointer:TPointerSemanticType = TPointerSemanticType(semanticType)
		If pointer Then Return "P" + TypeKey(pointer.elementType)
		Local arrayType:TArraySemanticType = TArraySemanticType(semanticType)
		If arrayType Then Return "A" + arrayType.rank + "_" + TypeKey(arrayType.elementType)
		Local fixedArray:TStaticArraySemanticType = TStaticArraySemanticType(semanticType)
		If fixedArray Then Return "S" + fixedArray.length + "_" + TypeKey(fixedArray.elementType)
		Local callable:TCallableSemanticType = TCallableSemanticType(semanticType)
		If callable Then
			Local result:String = "F" + TypeKey(callable.returnType)
			For Local index:Int = 0 Until callable.parameterTypes.length
				result :+ "_"
				If index < callable.parameterModes.length And callable.parameterModes[index] = PARAMETER_PASS_VAR Then result :+ "V"
				result :+ TypeKey(callable.parameterTypes[index])
			Next
			Return result + "E"
		End If
		Local named:TNamedSemanticType = TNamedSemanticType(semanticType)
		If named Then
			Local result:String = "N"
			If named.symbol Then result :+ Sanitize(named.symbol.QualifiedName()) Else result :+ "unknown"
			For Local argument:TSemanticType = EachIn named.typeArguments
				result :+ "_" + TypeKey(argument)
			Next
			Return result + "E"
		End If
		If semanticType Then
			Local display:String = semanticType.DisplayName()
			Return "X" + display.length + "_" + Sanitize(display)
		End If
		Return "unknown"
	End Function

	Function LegacyRoutineName:String(model:TSemanticModel, symbol:TSymbol)
		Return LegacySourceRoutineName(model, symbol, "")
	End Function

	' A quoted source in an application was a distinct production-bcc scope
	' named m_<file>. Native glue has historically linked NoMangle routines
	' through that readable scope (for example, _m_common_Type_Update), so its
	' ABI must not inherit bcc2's synthetic application.<name> ownership.
	Function LegacyApplicationSourceRoutineName:String(symbol:TSymbol, sourceUnitName:String)
		If Not symbol Then Return ""
		Local unitName:String = StripExt(StripDir(sourceUnitName)).ToLower()
		If Not unitName.length Then unitName = "source"
		Local prefix:String = "_m_" + unitName
		For Local owner:String = EachIn ContainingTypeNames(symbol)
			prefix :+ "_" + owner
		Next
		Return Sanitize(prefix + "_" + RoutineSourceName(symbol.name))
	End Function

	' Production NoMangle linkage belongs to the physical module source unit,
	' not merely to the logical module.  The principal source unit normally
	' has the module's short name and therefore needs no extra component;
	' included units retain their readable file identity (for example,
	' audio.soloud/file.bmx becomes audio_soloud_file_*).
	Function LegacySourceRoutineName:String(model:TSemanticModel, symbol:TSymbol, sourceUnitName:String)
		If Not symbol Then Return ""
		Local prefix:String
		If model And model.moduleName.length Then
			prefix = model.moduleName.ToLower().Replace(".", "_")
			Local normalizedUnit:String = StripExt(StripDir(sourceUnitName)).ToLower()
			Local moduleLeaf:String = model.moduleName.ToLower()
			Local dot:Int = moduleLeaf.FindLast(".")
			If dot >= 0 Then moduleLeaf = moduleLeaf[dot + 1..]
			If normalizedUnit.length And normalizedUnit <> moduleLeaf Then prefix :+ "_" + normalizedUnit
		Else If symbol.originModule.length Then
			prefix = symbol.originModule.ToLower().Replace(".", "_")
		Else
			prefix = "_bb_main"
		End If
		For Local owner:String = EachIn ContainingTypeNames(symbol)
			prefix :+ "_" + owner
		Next
		Return Sanitize(prefix + "_" + RoutineSourceName(symbol.name))
	End Function

	' Symbolic operator spellings must be encoded before the general C
	' identifier sanitizer runs. Replacing every punctuation character with an
	' underscore makes distinct operators such as :=, :+, and :* collide when
	' their parameter types are otherwise identical.
	Function RoutineSourceName:String(name:String)
		Select name.ToLower()
			Case "*"
				Return "_mul"
			Case "/"
				Return "_div"
			Case "+"
				Return "_add"
			Case "-"
				Return "_sub"
			Case "&"
				Return "_and"
			Case "|"
				Return "_or"
			Case "~~", "~~~~"
				Return "_xor"
			Case "^"
				Return "_pow"
			Case ":*"
				Return "_muleq"
			Case ":/"
				Return "_diveq"
			Case ":+"
				Return "_addeq"
			Case ":-"
				Return "_subeq"
			Case ":&"
				Return "_andeq"
			Case ":|"
				Return "_oreq"
			Case ":~~", ":~~~~"
				Return "_xoreq"
			Case ":^"
				Return "_poweq"
			Case ":="
				Return "_assign"
			Case "<"
				Return "_lt"
			Case "<="
				Return "_le"
			Case ">"
				Return "_gt"
			Case ">="
				Return "_ge"
			Case "="
				Return "_eq"
			Case "<>"
				Return "_ne"
			Case "mod"
				Return "_mod"
			Case "shl"
				Return "_shl"
			Case "shr"
				Return "_shr"
			Case ":mod"
				Return "_modeq"
			Case ":shl"
				Return "_shleq"
			Case ":shr"
				Return "_shreq"
			Case "[]"
				Return "_iget"
			Case "[]="
				Return "_iset"
		End Select
		Return name
	End Function

	Function Sanitize:String(value:String)
		Local result:String
		For Local index:Int = 0 Until value.length
			Local character:Int = value[index]
			If (character >= 48 And character <= 57) Or (character >= 65 And character <= 90) Or (character >= 97 And character <= 122) Or character = 95 Then
				result :+ Chr(character)
			Else
				result :+ "_"
			End If
		Next
		If Not result.length Then result = "unnamed"
		If result[0] >= 48 And result[0] <= 57 Then result = "_" + result
		Return result
	End Function
End Type

' Parses the complete C declarations accepted in an Extern linker string.
' Keeping this beside ABI naming gives ordinary IR and canonical generic
' lowering one authoritative split between semantic linker identity and the
' typedef-rich C call contract.
Type TCompilerNativeDeclaration
	Function LinkerName:String(externalName:String)
		If Not externalName.length Then Return ""
		If TCompilerAbiNamer.Sanitize(externalName) = externalName Then Return externalName
		Local openParen:Int = externalName.Find("(")
		Local closeParen:Int = externalName.FindLast(")")
		If openParen <= 0 Or closeParen <= openParen Then Return ""
		Local trailing:String = externalName[closeParen + 1..].Trim()
		If trailing.length And trailing <> "!" Then Return ""
		Local cursor:Int = openParen - 1
		While cursor >= 0 And (externalName[cursor] = 32 Or externalName[cursor] = 9)
			cursor :- 1
		Wend
		Local finish:Int = cursor + 1
		While cursor >= 0 And TBlitzMaxLexer.IsIdentifierPart(externalName[cursor])
			cursor :- 1
		Wend
		Local result:String = externalName[cursor + 1..finish]
		If Not result.length Or Not TBlitzMaxLexer.IsIdentifierStart(result[0]) Then Return ""
		If TCompilerAbiNamer.Sanitize(result) <> result Then Return ""
		Return result
	End Function

	Function Declaration:String(externalName:String)
		If Not externalName.length Or TCompilerAbiNamer.Sanitize(externalName) = externalName Then Return ""
		If Not LinkerName(externalName).length Then Return ""
		Local result:String = externalName.Trim()
		If result.EndsWith("!") Then result = result[..result.length - 1].Trim()
		Return result
	End Function

	Function ReturnType:String(externalName:String)
		Local declaration:String = Declaration(externalName)
		Local linkerName:String = LinkerName(externalName)
		If Not declaration.length Or Not linkerName.length Then Return ""
		Local openParen:Int = declaration.Find("(")
		If openParen <= 0 Then Return ""
		Local linkerStart:Int = declaration[..openParen].FindLast(linkerName)
		If linkerStart <= 0 Then Return ""
		Return declaration[..linkerStart].Trim()
	End Function

	Function ParameterTypes:String[](externalName:String)
		Local declaration:String = Declaration(externalName)
		If Not declaration.length Then Return New String[0]
		Local openParen:Int = declaration.Find("(")
		Local closeParen:Int = declaration.FindLast(")")
		If openParen < 0 Or closeParen <= openParen Then Return New String[0]
		Local parameterText:String = declaration[openParen + 1..closeParen].Trim()
		If Not parameterText.length Or parameterText.ToLower() = "void" Then Return New String[0]
		Local result:String[]
		Local start:Int
		Local depth:Int
		For Local index:Int = 0 Until parameterText.length
			Select parameterText[index]
				Case 40
					depth :+ 1
				Case 41
					If depth > 0 Then depth :- 1
				Case 44
					If depth = 0 Then
						result :+ [parameterText[start..index].Trim()]
						start = index + 1
					End If
			End Select
		Next
		result :+ [parameterText[start..].Trim()]
		Return result
	End Function
End Type
