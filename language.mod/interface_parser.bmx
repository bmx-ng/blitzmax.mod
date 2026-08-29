' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.LinkedList
Import BRL.Base64
Import Archive.ZLib

Import "interface_model.bmx"
Import "interface_signature_decoder.bmx"

Type TInterfaceFileParser
	Field result:TInterfaceFile
	Field diagnostics:TList = New TList
	Field current:TInterfaceRecord
	Field lastDeclaration:TInterfaceRecord
	Field decodeSignatures:Int = True
	Field decodeGenericTemplates:Int = True

	Function Parse:TInterfaceFile(text:String, path:String = "", decodeSignatures:Int = True, decodeGenericTemplates:Int = True)
		Local parser:TInterfaceFileParser = New TInterfaceFileParser
		parser.decodeSignatures = decodeSignatures
		parser.decodeGenericTemplates = decodeGenericTemplates
		parser.result = New TInterfaceFile
		parser.result.path = path
		parser.result.sourceText = text
		parser.ParseLines(text)
		If parser.decodeSignatures Then TInterfaceSignatureDecoder.Decode(parser.result)
		parser.result.diagnostics = DiagnosticsToArray(parser.diagnostics)
		Return parser.result
	End Function

	Method ParseLines(text:String)
		Local lines:String[] = text.Split("~n")
		For Local index:Int = 0 Until lines.length
			Local raw:String = lines[index]
			If raw.EndsWith("~r") Then raw = raw[..raw.length - 1]
			ParseLine(raw, index + 1)
		Next
		If current Then AddDiagnostic("BMXI100", "Unterminated " + current.KindName().ToLower() + " record '" + current.name + "'.", current.line)
	End Method

	Method ParseLine(raw:String, line:Int)
		Local text:String = raw.Trim()
		If Not text.length Then Return
		If StartsWithAsciiIgnoreCase(text, "'@source-aggregate ") Then
			result.hasSourceAggregate = Int(text[19..].Trim()) > 0
			Return
		End If
		Local sourcePath:String
		Local sourceLine:Int
		Local sourceColumn:Int
		ExtractSourceMetadata(text, sourcePath, sourceLine, sourceColumn)
		If StartsWithAsciiIgnoreCase(text, "'@generic-template ") Then
			ParseGenericTemplateReference(text, line)
			Return
		End If
		If current Then
			If text.StartsWith("}") Then
				current.trailerText = text
				ParseTrailer(current, text)
				lastDeclaration = current
				current = Null
			Else
				Local member:TInterfaceRecord = ParseOrdinaryRecord(text, line, current.kind)
				ApplySourceMetadata(member, sourcePath, sourceLine, sourceColumn)
				current.AddMember(member)
				lastDeclaration = member
			End If
			Return
		End If

		lastDeclaration = Null
		If StartsWithAsciiIgnoreCase(text, "'@docs ") Then
			result.documentationSource = Unquote(text[7..].Trim())
			Return
		End If
		If EqualsIgnoreCase(text, "superstrict") Then
			result.isSuperStrict = True
			Return
		End If
		If StartsWithAsciiIgnoreCase(text, "moduleinfo ") Then
			result.metadata :+ [Unquote(text[11..].Trim())]
			Return
		End If
		If StartsWithAsciiIgnoreCase(text, "#pragma ") Then
			result.pragmas :+ [Unquote(text[8..].Trim())]
			Return
		End If
		If StartsWithAsciiIgnoreCase(text, "import ") Then
			Local value:String = text[7..].Trim()
			Local item:TInterfaceImport = New TInterfaceImport
			item.rawText = text
			item.line = line
			item.isFileImport = value.StartsWith(Chr(34))
			item.name = Unquote(value)
			result.AddImport(item)
			Return
		End If

		Local openBrace:Int = text.Find("{")
		Local classMarker:Int = text.Find("^")
		Local enumMarker:Int = text.Find(Chr(92))
		If openBrace >= 0 And classMarker > 0 And classMarker < openBrace Then
			current = ParseTypeHeader(text, line, classMarker, openBrace)
			lastDeclaration = current
			ApplySourceMetadata(current, sourcePath, sourceLine, sourceColumn)
			result.AddDeclaration(current)
			Return
		End If
		If openBrace >= 0 And enumMarker > 0 And enumMarker < openBrace Then
			current = ParseEnumHeader(text, line, enumMarker)
			lastDeclaration = current
			ApplySourceMetadata(current, sourcePath, sourceLine, sourceColumn)
			result.AddDeclaration(current)
			Return
		End If
		Local ordinary:TInterfaceRecord = ParseOrdinaryRecord(text, line, 0)
		lastDeclaration = ordinary
		ApplySourceMetadata(ordinary, sourcePath, sourceLine, sourceColumn)
		result.AddDeclaration(ordinary)
	End Method

	Function StartsWithAsciiIgnoreCase:Int(text:String, prefix:String)
		If text.length < prefix.length Then Return False
		For Local index:Int = 0 Until prefix.length
			If FoldAscii(text[index]) <> FoldAscii(prefix[index]) Then Return False
		Next
		Return True
	End Function

	Function EqualsIgnoreCase:Int(left:String, right:String)
		Return left.Compare(right, False) = 0
	End Function

	Function FoldAscii:Int(character:Int)
		If character >= Asc("A") And character <= Asc("Z") Then Return character + Asc("a") - Asc("A")
		Return character
	End Function

	Method ParseGenericTemplateReference(text:String, line:Int)
		If Not lastDeclaration Or (lastDeclaration.kind <> INTERFACE_RECORD_TYPE And lastDeclaration.kind <> INTERFACE_RECORD_FUNCTION And lastDeclaration.kind <> INTERFACE_RECORD_METHOD And lastDeclaration.kind <> INTERFACE_RECORD_TYPE_FUNCTION) Then
			AddDiagnostic("BMXI110", "Generic template reference does not follow a Type, Function, or Method record.", line)
			Return
		End If
		Local parts:String[] = SplitQuoted(text[19..], ",")
		If parts.length <> 5 Then
			AddDiagnostic("BMXI111", "Generic template reference requires format, identity, revision, artifact and language revision.", line)
			Return
		End If
		lastDeclaration.genericTemplateFormat = Int(parts[0].Trim())
		lastDeclaration.genericTemplateIdentity = Unquote(parts[1].Trim())
		lastDeclaration.genericTemplateRevision = Unquote(parts[2].Trim())
		lastDeclaration.genericTemplateReference = Unquote(parts[3].Trim())
		lastDeclaration.genericTemplateLanguageRevision = Unquote(parts[4].Trim())
	End Method

	Method ExtractSourceMetadata(text:String Var, path:String Var, line:Int Var, column:Int Var)
		Local marker:Int = text.ToLower().Find("'@source")
		If marker < 0 Then Return
		Local payload:String = text[marker + 8..].Trim()
		text = text[..marker].Trim()
		Local parts:String[] = SplitQuoted(payload, ",")
		If parts.length > 0 Then path = Unquote(parts[0].Trim())
		If parts.length > 1 Then line = Int(parts[1].Trim())
		If parts.length > 2 Then column = Int(parts[2].Trim())
	End Method

	Function ApplySourceMetadata(record:TInterfaceRecord, path:String, line:Int, column:Int)
		If Not record Or Not path.length Then Return
		record.originPath = path
		record.originLine = line
		record.originColumn = column
	End Function

	Method ParseTypeHeader:TInterfaceRecord(text:String, line:Int, marker:Int, openBrace:Int)
		Local record:TInterfaceRecord = New TInterfaceRecord
		record.kind = INTERFACE_RECORD_TYPE
		record.name = text[..marker]
		record.rawText = text
		record.signatureText = text[..openBrace]
		record.line = line
		Local inheritance:String = text[marker + 1..openBrace]
		Local implementsIndex:Int = FindTopLevel(inheritance, "@")
		If implementsIndex >= 0 Then
			record.baseTypeText = inheritance[..implementsIndex]
			record.implementedTypeTexts = SplitTopLevel(inheritance[implementsIndex + 1..], ",")
		Else
			record.baseTypeText = inheritance
		End If
		Return record
	End Method

	Method ParseEnumHeader:TInterfaceRecord(text:String, line:Int, marker:Int)
		Local record:TInterfaceRecord = New TInterfaceRecord
		record.kind = INTERFACE_RECORD_ENUM
		record.name = text[..marker]
		record.rawText = text
		record.signatureText = text[..text.Find("{")]
		record.line = line
		record.baseTypeText = text[marker + 1..text.Find("{")]
		Return record
	End Method

	Method ParseOrdinaryRecord:TInterfaceRecord(text:String, line:Int, containerKind:Int)
		Local record:TInterfaceRecord = New TInterfaceRecord
		record.rawText = text
		record.line = line
		Local assignment:Int = ExternalAssignmentIndex(text)
		If assignment >= 0 Then
			record.signatureText = text[..assignment]
			record.externalName = FirstQuotedValue(text[assignment + 1..])
		Else
			record.signatureText = text
		End If

		If containerKind = INTERFACE_RECORD_ENUM Then
			record.kind = INTERFACE_RECORD_ENUM_VALUE
			record.name = ReadIdentifier(text, 0)
			If assignment >= 0 Then record.valueText = text[assignment + 1..]
			Return record
		End If

		Local first:String = text[..1]
		If first = "-" Or first = "+" Then
			record.kind = INTERFACE_RECORD_METHOD
			If first = "+" Then record.kind = INTERFACE_RECORD_TYPE_FUNCTION
			record.name = ReadCallableName(text, 1)
			record.flags = FlagsBeforeAssignment(text, assignment)
			record.visibility = VisibilityFromRoutineFlags(record.flags)
			Return record
		End If
		If containerKind = INTERFACE_RECORD_TYPE And (first = "." Or first = "@" Or first = "~~") Then
			record.kind = INTERFACE_RECORD_FIELD
			If first = "~~" Then record.isStaticArray = True
			If first = "@" Then record.flags :+ "R"
			Local start:Int = 1
			record.name = ReadIdentifier(text, start)
			record.visibility = VisibilityFromTicks(record.signatureText)
			Return record
		End If

		Local isGlobal:Int = IsGlobalSignature(record.signatureText)
		Local paren:Int = text.Find("(")
		If paren >= 0 And (assignment < 0 Or paren < assignment) And Not isGlobal Then
			record.kind = INTERFACE_RECORD_FUNCTION
			record.name = ReadCallableName(text, 0)
			record.flags = FlagsBeforeAssignment(text, assignment)
			record.visibility = VisibilityFromRoutineFlags(record.flags)
			Return record
		End If
		record.name = ReadIdentifier(text, 0)
		If isGlobal Then record.kind = INTERFACE_RECORD_GLOBAL Else record.kind = INTERFACE_RECORD_CONST
		record.visibility = VisibilityFromTicks(record.signatureText)
		If record.kind = INTERFACE_RECORD_CONST And assignment >= 0 Then record.valueText = text[assignment + 1..]
		Return record
	End Method

	Method ParseTrailer(record:TInterfaceRecord, text:String)
		Local assignment:Int = text.Find("=")
		If assignment >= 0 Then
			record.flags = text[1..assignment]
			record.externalName = FirstQuotedValue(text[assignment + 1..])
		Else
			record.flags = text[1..]
		End If
		If decodeGenericTemplates And record.flags.Contains("G") Then DecodeGenericTemplate(record, text)
		If record.flags.Contains("P") Then record.visibility = VISIBILITY_PRIVATE
	End Method

	Method DecodeGenericTemplate(record:TInterfaceRecord, text:String)
		Local templateMarker:Int = text.Find("<?>")
		If templateMarker < 0 Then Return
		Local openBrace:Int = text.Find("{", templateMarker)
		Local closeBrace:Int = text.FindLast("}")
		If openBrace < 0 Or closeBrace <= openBrace Then Return
		Local parts:String[] = SplitQuoted(text[openBrace + 1..closeBrace], ",")
		If parts.length <> 4 Then Return
		Local sourceLength:Int = Int(parts[1].Trim())
		If sourceLength <= 0 Then Return
		Try
			Local compressed:Byte[] = TBase64.Decode(Unquote(parts[3].Trim()))
			Local sourceBytes:Byte[] = New Byte[sourceLength + 1]
			Local outputLength:ULongInt = ULongInt(sourceLength + 1)
			If uncompress(sourceBytes, outputLength, compressed, ULongInt(compressed.length)) <> 0 Then Return
			record.genericSourceStart = Int(parts[0].Trim())
			record.genericSourcePath = Unquote(parts[2].Trim())
			record.genericSource = String.FromUTF8Bytes(sourceBytes, sourceLength)
		Catch exception:Object
			' Malformed or unsupported payloads leave the generic shell intact; the
			' semantic layer will then report only uses that require its API.
		End Try
	End Method

	Method AddDiagnostic(code:String, message:String, line:Int)
		diagnostics.AddLast(TInterfaceDiagnostic.Create(code, message, line))
	End Method

	Function ReadCallableName:String(text:String, start:Int)
		If start < text.length And text[start..start + 1] = Chr(34) Then
			Local close:Int = text.Find(Chr(34), start + 1)
			If close >= 0 Then Return text[start + 1..close]
		End If
		Return ReadIdentifier(text, start)
	End Function

	Function ReadIdentifier:String(text:String, start:Int)
		Local finish:Int = start
		While finish < text.length
			Local char:Int = text[finish]
			If Not ((char >= Asc("a") And char <= Asc("z")) Or (char >= Asc("A") And char <= Asc("Z")) Or (char >= Asc("0") And char <= Asc("9")) Or char = Asc("_")) Then Exit
			finish :+ 1
		Wend
		Return text[start..finish]
	End Function

	Function ExternalAssignmentIndex:Int(text:String)
		Local parentheses:Int
		Local brackets:Int
		Local angles:Int
		Local quoted:Int
		For Local index:Int = 0 Until text.length
			Local char:Int = text[index]
			If char = Asc("~q") Then
				quoted = Not quoted
				Continue
			End If
			If quoted Then Continue
			Select char
				Case Asc("(") parentheses :+ 1
				Case Asc(")") parentheses :- 1
				Case Asc("[") brackets :+ 1
				Case Asc("]") brackets :- 1
				Case Asc("<") angles :+ 1
				Case Asc(">") angles :- 1
				Case Asc("=")
					If parentheses = 0 And brackets = 0 And angles = 0 Then Return index
			End Select
		Next
		Return -1
	End Function

	Function FirstQuotedValue:String(text:String)
		Local open:Int = text.Find(Chr(34))
		If open < 0 Then Return ""
		Local close:Int = text.Find(Chr(34), open + 1)
		If close < 0 Then Return text[open + 1..]
		Return text[open + 1..close]
	End Function

	Function FlagsBeforeAssignment:String(text:String, assignment:Int)
		Local flagsEnd:Int = assignment
		If flagsEnd < 0 Then flagsEnd = text.length
		Local closeParen:Int = text[..flagsEnd].FindLast(")")
		If closeParen < 0 Then Return ""
		Local result:String
		For Local index:Int = closeParen + 1 Until flagsEnd
			Local flag:String = text[index..index + 1]
			If "ADEFGIPRSW".Find(flag) < 0 Then Exit
			result :+ flag
		Next
		Return result
	End Function

	Function VisibilityFromRoutineFlags:Int(flags:String)
		If flags.Contains("P") And flags.Contains("I") Then Return VISIBILITY_PRIVATE_INTERNAL
		If flags.Contains("R") And flags.Contains("I") Then Return VISIBILITY_PROTECTED_INTERNAL
		If flags.Contains("P") Then Return VISIBILITY_PRIVATE
		If flags.Contains("R") Then Return VISIBILITY_PROTECTED
		If flags.Contains("I") Then Return VISIBILITY_INTERNAL
		Return VISIBILITY_PUBLIC
	End Function

	Function VisibilityFromTicks:Int(text:String)
		Local count:Int
		Local index:Int = text.length - 1
		While index >= 0 And text[index] = Asc("`")
			count :+ 1
			index :- 1
		Wend
		Select count
			Case 1 Return VISIBILITY_PRIVATE
			Case 2 Return VISIBILITY_PROTECTED
			Case 3 Return VISIBILITY_INTERNAL
			Case 4 Return VISIBILITY_PRIVATE_INTERNAL
			Case 5 Return VISIBILITY_PROTECTED_INTERNAL
		End Select
		Return VISIBILITY_PUBLIC
	End Function

	Function IsGlobalSignature:Int(signature:String)
		Local value:String = signature
		While value.EndsWith("`")
			value = value[..value.length - 1]
		Wend
		Return value.EndsWith("&")
	End Function

	Function Unquote:String(text:String)
		If text.length >= 2 And text.StartsWith(Chr(34)) And text.EndsWith(Chr(34)) Then Return text[1..text.length - 1]
		Return text
	End Function

	Function FindTopLevel:Int(text:String, target:String)
		Local angles:Int
		Local brackets:Int
		For Local index:Int = 0 Until text.length
			Select text[index]
				Case Asc("<") angles :+ 1
				Case Asc(">") angles :- 1
				Case Asc("[") brackets :+ 1
				Case Asc("]") brackets :- 1
			End Select
			If angles = 0 And brackets = 0 And text[index..index + 1] = target Then Return index
		Next
		Return -1
	End Function

	Function SplitTopLevel:String[](text:String, separator:String)
		Local result:String[]
		Local start:Int
		Local angles:Int
		Local brackets:Int
		For Local index:Int = 0 To text.length
			Local split:Int = index = text.length
			If Not split Then
				Select text[index]
					Case Asc("<") angles :+ 1
					Case Asc(">") angles :- 1
					Case Asc("[") brackets :+ 1
					Case Asc("]") brackets :- 1
				End Select
				If angles = 0 And brackets = 0 And text[index..index + 1] = separator Then split = True
			End If
			If split Then
				If index > start Then result :+ [text[start..index]]
				start = index + 1
			End If
		Next
		Return result
	End Function

	Function SplitQuoted:String[](text:String, separator:String)
		Local result:String[]
		Local start:Int
		Local quoted:Int
		For Local index:Int = 0 To text.length
			Local split:Int = index = text.length
			If Not split Then
				If text[index] = Asc("~q") Then quoted = Not quoted
				If Not quoted And text[index..index + 1] = separator Then split = True
			End If
			If split Then
				result :+ [text[start..index]]
				start = index + 1
			End If
		Next
		Return result
	End Function

	Function DiagnosticsToArray:TInterfaceDiagnostic[](list:TList)
		Local result:TInterfaceDiagnostic[] = New TInterfaceDiagnostic[list.Count()]
		Local index:Int
		For Local value:TInterfaceDiagnostic = EachIn list
			result[index] = value
			index :+ 1
		Next
		Return result
	End Function
End Type
