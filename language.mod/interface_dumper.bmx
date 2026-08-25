' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "interface_model.bmx"

Type TInterfaceDumper
	Function Dump:String(file:TInterfaceFile)
		Local result:String = "InterfaceFile " + file.path + "~n"
		If file.isSuperStrict Then result :+ "  SuperStrict~n"
		For Local item:TInterfaceImport = EachIn file.imports
			result :+ "  Import " + item.name
			If item.isFileImport Then result :+ " [file]"
			result :+ "~n"
		Next
		For Local declaration:TInterfaceRecord = EachIn file.declarations
			result :+ DumpRecord(declaration, "  ")
		Next
		Return result
	End Function

	Function DumpRecord:String(record:TInterfaceRecord, indent:String)
		Local result:String = indent + record.KindName() + " " + record.name
		If record.kind = INTERFACE_RECORD_TYPE Then
			If record.baseTypeText.length Then result :+ " Extends " + record.baseTypeText
			If record.implementedTypeTexts.length Then
				result :+ " Implements "
				For Local index:Int = 0 Until record.implementedTypeTexts.length
					If index Then result :+ ", "
					result :+ record.implementedTypeTexts[index]
				Next
			End If
		Else If record.kind = INTERFACE_RECORD_ENUM And record.baseTypeText.length Then
			result :+ " : " + record.baseTypeText
		End If
		If record.flags.length Then result :+ " [" + record.flags + "]"
		If record.externalName.length Then result :+ " = " + record.externalName
		result :+ "~n"
		For Local member:TInterfaceRecord = EachIn record.members
			result :+ DumpRecord(member, indent + "  ")
		Next
		Return result
	End Function
End Type
