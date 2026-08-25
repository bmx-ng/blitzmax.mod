' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "semantic_model.bmx"

Type TSemanticDumper
	Function Dump:String(model:TSemanticModel)
		If Not model Or Not model.globalScope Then Return "<missing semantic model>~n"
		Return DumpScope(model, model.globalScope, "")
	End Function

	Function DumpScope:String(model:TSemanticModel, scope:TScope, indent:String)
		Local result:String = indent + "Scope " + scope.KindName()
		If scope.owner Then result :+ " " + scope.owner.name
		result :+ "~n"
		If scope.owner Then
			Local inheritance:TTypeInheritanceInfo = model.InheritanceInfo(scope.owner)
			If inheritance Then
				For Local edge:TInheritanceEdge = EachIn inheritance.baseEdges
					result :+ indent + "  Extends " + edge.semanticType.DisplayName()
					If edge.isImplicit Then result :+ " [implicit]"
					result :+ "~n"
				Next
				For Local edge:TInheritanceEdge = EachIn inheritance.interfaceEdges
					result :+ indent + "  Implements " + edge.semanticType.DisplayName() + "~n"
				Next
				For Local constraint:TGenericConstraintInfo = EachIn inheritance.constraints
					result :+ indent + "  Where " + constraint.parameterSymbol.name + " Extends "
					For Local index:Int = 0 Until constraint.bounds.length
						If index Then result :+ " And "
						result :+ constraint.bounds[index].DisplayName()
					Next
					result :+ "~n"
				Next
			End If
		End If
		For Local symbol:TSymbol = EachIn scope.declaredSymbols
			result :+ indent + "  " + symbol.KindName() + " " + symbol.name
			If symbol.declaredType And symbol.NamespaceKind() <> SYMBOL_NAMESPACE_TYPE Then result :+ " : " + symbol.declaredType.DisplayName()
			If symbol.kind = SYMBOL_PARAMETER And symbol.parameterMode = PARAMETER_PASS_VAR Then result :+ " [Var]"
			If symbol.isExternal Then result :+ " [extern=" + symbol.externalName + "]"
			If symbol.visibility <> VISIBILITY_PUBLIC Then result :+ " [" + VisibilityName(symbol.visibility) + "]"
			If symbol.nameToken Then result :+ " " + symbol.nameToken.span.ToString()
			result :+ "~n"
		Next
		For Local child:TScope = EachIn scope.children
			result :+ DumpScope(model, child, indent + "  ")
		Next
		Return result
	End Function

	Function VisibilityName:String(visibility:Int)
		Select visibility
			Case VISIBILITY_PRIVATE Return "private"
			Case VISIBILITY_PROTECTED Return "protected"
			Case VISIBILITY_INTERNAL Return "internal"
			Case VISIBILITY_PRIVATE_INTERNAL Return "private internal"
			Case VISIBILITY_PROTECTED_INTERNAL Return "protected internal"
		End Select
		Return "public"
	End Function
End Type
