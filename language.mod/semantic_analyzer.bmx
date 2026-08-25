' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "cancellation.bmx"
Import "inheritance_validation.bmx"
Import "interface_symbol_importer.bmx"

Type TBlitzMaxSemanticAnalyzer
	Function AnalyzeSnapshot:TSemanticModel(snapshot:TCompilationSnapshot, options:TTypeResolutionOptions = Null, cancellationToken:TLanguageCancellationToken = Null)
		Local model:TSemanticModel = TDeclarationCollector.CollectSnapshot(snapshot)
		If LanguageCancellationRequested(cancellationToken) Then Return model
		TInterfaceSymbolImporter.ImportSnapshot(model, snapshot, cancellationToken)
		If LanguageCancellationRequested(cancellationToken) Then Return model
		model = TTypeResolver.Bind(model, options)
		If LanguageCancellationRequested(cancellationToken) Then Return model
		Return TInheritanceValidator.Validate(model)
	End Function

	Function Analyze:TSemanticModel(tree:TSyntaxTree, options:TTypeResolutionOptions = Null, cancellationToken:TLanguageCancellationToken = Null)
		If LanguageCancellationRequested(cancellationToken) Then Return TDeclarationCollector.Collect(tree)
		Local model:TSemanticModel = TTypeResolver.Bind(TDeclarationCollector.Collect(tree), options)
		If LanguageCancellationRequested(cancellationToken) Then Return model
		Return TInheritanceValidator.Validate(model)
	End Function
End Type
