' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Map
Import BRL.MaxUtil

Import "semantic_model.bmx"

' Central visibility policy shared by semantic binding and editor features.
Type TSymbolAccessibility
	Function IsAccessible:Int(symbol:TSymbol, accessScope:TScope, model:TSemanticModel, owner:TSymbol = Null)
		If Not symbol Then Return False
		If symbol.visibility = VISIBILITY_PUBLIC Then Return True
		If Not owner And symbol.containingScope Then owner = symbol.containingScope.owner
		Local accessingType:TSymbol = EnclosingType(accessScope)

		Select symbol.visibility
			Case VISIBILITY_PRIVATE
				' A private Type member belongs only to its declaring Type.  A
				' module-level private declaration instead belongs to the source
				' compilation unit because it has no declaring Type.
				If IsTypeOwner(owner) Then Return accessingType = owner
				Return SameCompilationUnit(symbol, model)
			Case VISIBILITY_PROTECTED
				Return owner And accessingType And IsSameOrDerived(model, accessingType, owner)
			Case VISIBILITY_INTERNAL
				Return SameCompilationUnit(symbol, model)
			Case VISIBILITY_PRIVATE_INTERNAL
				If SameCompilationUnit(symbol, model) Then Return True
				Return IsTypeOwner(owner) And accessingType = owner
			Case VISIBILITY_PROTECTED_INTERNAL
				If SameCompilationUnit(symbol, model) Then Return True
				Return owner And accessingType And IsSameOrDerived(model, accessingType, owner)
		End Select
		Return False
	End Function

	Function IsTypeOwner:Int(owner:TSymbol)
		Return owner And (owner.kind = SYMBOL_TYPE Or owner.kind = SYMBOL_ENUM)
	End Function

	Function EnclosingType:TSymbol(scope:TScope)
		While scope
			If scope.kind = SCOPE_TYPE Or scope.kind = SCOPE_ENUM Then Return scope.owner
			scope = scope.parent
		Wend
		Return Null
	End Function

	Function IsSameOrDerived:Int(model:TSemanticModel, candidate:TSymbol, baseType:TSymbol)
		Return IsSameOrDerivedCore(model, candidate, baseType, New TMap)
	End Function

	Function IsSameOrDerivedCore:Int(model:TSemanticModel, candidate:TSymbol, baseType:TSymbol, visited:TMap)
		If Not candidate Or Not baseType Then Return False
		If candidate = baseType Then Return True
		If Not model Or visited.Contains(candidate) Then Return False
		visited.Insert(candidate, candidate)
		Local info:TTypeInheritanceInfo = model.InheritanceInfo(candidate)
		If Not info Then Return False
		For Local edge:TInheritanceEdge = EachIn info.baseEdges
			Local named:TNamedSemanticType = TNamedSemanticType(edge.semanticType)
			If named And IsSameOrDerivedCore(model, named.symbol, baseType, visited) Then Return True
		Next
		Return False
	End Function

	Function SameCompilationUnit:Int(symbol:TSymbol, model:TSemanticModel)
		If Not symbol Or Not model Then Return False
		' Source declarations collected into this model include the root source and
		' all transitive Include files. Separately compiled source/interface imports
		' are marked imported even when they live under the same .mod directory.
		Return Not symbol.isImported
	End Function

	Function ModuleNameForPath:String(path:String)
		Return BRL.MaxUtil.ModuleNameForPath(path)
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
