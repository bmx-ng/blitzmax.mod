' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BlitzMax.Language
Import BlitzMax.Locale

If AppArgs.length <> 2 Then Throw "Expected the compiled language.bmxcat path"

Local nestedExpression:String
For Local index:Int = 0 Until 520
	nestedExpression :+ "- "
Next
nestedExpression :+ "1"
Local source:String = "SuperStrict~nGlobal value:Int = " + nestedExpression

TLocale.Clear()
Local english:TDiagnostic = FindDepthDiagnostic(TBlitzMaxParser.ParseText(source, "deep-expression.bmx"))
AssertEqual("Expression nesting is too deep to parse safely.", english.message, "English fallback")
AssertMessageIdentity(english)

Local catalogue:TLocaleCatalogue = TLocale.LoadCatalogue(AppArgs[1])
AssertEqual("language", catalogue.domain, "catalogue domain")
AssertEqual("de-de", catalogue.locale, "catalogue locale")
Local german:TDiagnostic = FindDepthDiagnostic(TBlitzMaxParser.ParseText(source, "deep-expression.bmx"))
AssertEqual("Die Verschachtelung des Ausdrucks ist zu tief, um ihn sicher zu analysieren.", german.message, "German translation")
AssertMessageIdentity(german)

' Explicit contexts can render the same structured message concurrently without
' changing the process default used by ordinary compiler diagnostics.
Local englishContext:TLocaleContext = New TLocaleContext
Local germanContext:TLocaleContext = New TLocaleContext("de_DE.UTF-8")
germanContext.LoadCatalogue(AppArgs[1])
AssertEqual("de-de", germanContext.locale, "locale normalization")
AssertEqual("Unexpected token '!' in expression.", TLanguageMessages.ParserUnexpectedTokenInExpression("!").Render(englishContext), "named English placeholder")
AssertEqual("Unerwartetes Token '!' im Ausdruck.", TLanguageMessages.ParserUnexpectedTokenInExpression("!").Render(germanContext), "named German placeholder")
AssertEqual("Type 'Box' expects 0 type arguments, but 2 were supplied.", TLanguageMessages.TypeExpectedTypeArguments("Box", 0, 2).Render(englishContext), "English zero quantity")
AssertEqual("Type 'Box' expects one type argument, but 2 were supplied.", TLanguageMessages.TypeExpectedTypeArguments("Box", 1, 2).Render(englishContext), "English one plural")
AssertEqual("Type 'Box' expects 3 type arguments, but 2 were supplied.", TLanguageMessages.TypeExpectedTypeArguments("Box", 3, 2).Render(englishContext), "English other plural")
AssertEqual("Der Typ 'Box' erwartet ein Typargument, aber 2 wurden angegeben.", TLanguageMessages.TypeExpectedTypeArguments("Box", 1, 2).Render(germanContext), "German one plural")

' Newly migrated entries deliberately remain untranslated in the German
' catalogue and therefore fall back to their generated English source.
Local sourceModeDiagnostic:TDiagnostic = FindDiagnostic(TBlitzMaxParser.ParseText("SuperStrict extra~n", "source-mode.bmx"), "BMX2325")
AssertEqual("Unexpected token 'extra' after 'SuperStrict'.", sourceModeDiagnostic.MessageFor(germanContext), "untranslated German fallback")
If sourceModeDiagnostic.localisedMessage.id <> LANGUAGE_MSG_PARSER_UNEXPECTED_TOKEN_AFTER_SOURCE_MODE Then Throw "Unexpected source-mode message ID"

Local forDiagnostic:TDiagnostic = FindDiagnostic(TBlitzMaxParser.ParseText("SuperStrict~nFor Local index:Int = To 10~nNext~n", "for-header.bmx"), "BMX2317")
AssertEqual("Expected an initial value before 'To'.", forDiagnostic.MessageFor(germanContext), "For-loop placeholder fallback")
If forDiagnostic.localisedMessage.id <> LANGUAGE_MSG_PARSER_EXPECTED_INITIAL_VALUE_BEFORE_RANGE_CLAUSE Then Throw "Unexpected For-loop message ID"

Local selectDiagnostic:TDiagnostic = FindDiagnostic(TBlitzMaxParser.ParseText("SuperStrict~nSelect 1~nDefault~nDefault~nEnd Select~n", "select-default.bmx"), "BMX2400")
AssertEqual("A Select statement can contain only one Default clause.", selectDiagnostic.MessageFor(germanContext), "Select fallback")
If selectDiagnostic.localisedMessage.id <> LANGUAGE_MSG_PARSER_SELECT_ALLOWS_SINGLE_DEFAULT Then Throw "Unexpected Select message ID"

Local tryDiagnostic:TDiagnostic = FindDiagnostic(TBlitzMaxParser.ParseText("SuperStrict~nTry unexpected~nCatch error:Object~nEnd Try~n", "try-header.bmx"), "BMX2410")
AssertEqual("Try does not accept a header expression.", tryDiagnostic.MessageFor(germanContext), "Try fallback")
If tryDiagnostic.localisedMessage.id <> LANGUAGE_MSG_PARSER_TRY_REJECTS_HEADER_EXPRESSION Then Throw "Unexpected Try message ID"

Local usingDiagnostic:TDiagnostic = FindDiagnostic(TBlitzMaxParser.ParseText("SuperStrict~nUsing~nDo~nEnd Using~n", "using-resource.bmx"), "BMX2422")
AssertEqual("Using requires at least one Local resource declaration.", usingDiagnostic.MessageFor(germanContext), "Using fallback")
If usingDiagnostic.localisedMessage.id <> LANGUAGE_MSG_PARSER_USING_REQUIRES_LOCAL_RESOURCE Then Throw "Unexpected Using message ID"

Local bindingAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nLocal value:Int~nSelect value~nDefault~nDefault~nEnd Select~n", "active-default.bmx")
Local activeDefaultDiagnostic:TDiagnostic = FindModelDiagnostic(bindingAnalysis, "BMX2400")
AssertEqual("A Select statement can contain only one active Default clause.", activeDefaultDiagnostic.MessageFor(germanContext), "active Select fallback")
If activeDefaultDiagnostic.localisedMessage.id <> LANGUAGE_MSG_BINDING_SELECT_ALLOWS_SINGLE_ACTIVE_DEFAULT Then Throw "Unexpected active Select message ID"

Local activeCaseAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nLocal value:Int~nSelect value~nDefault~nCase 1~nEnd Select~n", "active-case.bmx")
Local activeCaseDiagnostic:TDiagnostic = FindModelDiagnostic(activeCaseAnalysis, "BMX2401")
AssertEqual("An active Case clause cannot follow Default.", activeCaseDiagnostic.MessageFor(germanContext), "active Case fallback")
If activeCaseDiagnostic.localisedMessage.id <> LANGUAGE_MSG_BINDING_ACTIVE_CASE_CANNOT_FOLLOW_DEFAULT Then Throw "Unexpected active Case message ID"

AssertEqual("Function 'Run' does not return a value, so Return cannot include an expression.", TLanguageMessages.BindingVoidRoutineReturnRejectsExpression("Function", "Run").Render(germanContext), "binding placeholder fallback")

Local unresolvedAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nLocal value:Int = missingValue~n", "unresolved-value.bmx")
Local unresolvedDiagnostic:TDiagnostic = FindModelDiagnostic(unresolvedAnalysis, "BMX3300")
AssertEqual("Name 'missingValue' could not be resolved as a value.", unresolvedDiagnostic.MessageFor(germanContext), "unresolved name fallback")
If unresolvedDiagnostic.localisedMessage.id <> LANGUAGE_MSG_BINDING_NAME_NOT_RESOLVED_AS_VALUE Then Throw "Unexpected unresolved-name message ID"

AssertEqual("Type 'String' cannot be explicitly converted to 'Int'.", TLanguageMessages.BindingExplicitConversionNotAvailable("String", "Int").Render(germanContext), "explicit conversion placeholder fallback")

Local captureAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nLocal offset:Int = 1~nLocal add:Int(value:Int) = Function(value)~nReturn value + offset~nEnd Function~n", "thin-capture.bmx")
Local captureDiagnostic:TDiagnostic = FindModelDiagnostic(captureAnalysis, "BMX3346")
AssertEqual("Thin Function literal cannot capture 'offset'; captured lexical state requires managed Closure support.", captureDiagnostic.MessageFor(germanContext), "thin capture fallback")
If captureDiagnostic.localisedMessage.id <> LANGUAGE_MSG_BINDING_THIN_FUNCTION_LITERAL_CANNOT_CAPTURE Then Throw "Unexpected capture message ID"

AssertEqual("Function literal has 2 parameters but target type 'Int(Int)' requires 1.", TLanguageMessages.BindingFunctionLiteralParameterCountMismatch(2, "Int(Int)", 1).Render(germanContext), "integer placeholder fallback")

Local memberAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nType TValue~nEnd Type~nLocal value:TValue = New TValue~nLocal result:Int = value.missing~n", "missing-member.bmx")
Local memberDiagnostic:TDiagnostic = FindModelDiagnostic(memberAnalysis, "BMX3301")
AssertEqual("Member 'missing' could not be resolved.", memberDiagnostic.MessageFor(germanContext), "missing member fallback")
If memberDiagnostic.localisedMessage.id <> LANGUAGE_MSG_BINDING_MEMBER_NOT_RESOLVED Then Throw "Unexpected member message ID"

Local constructorAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nType TBad~nMethod New()~nLocal value:Int~nNew(1)~nEnd Method~nMethod New(value:Int)~nEnd Method~nEnd Type", "misplaced-constructor-delegation.bmx")
Local constructorDiagnostic:TDiagnostic = FindModelDiagnostic(constructorAnalysis, "BMX3322")
AssertEqual("Constructor delegation must be the first statement in a New method.", constructorDiagnostic.MessageFor(germanContext), "constructor delegation fallback")
If constructorDiagnostic.localisedMessage.id <> LANGUAGE_MSG_BINDING_CONSTRUCTOR_DELEGATION_MUST_BE_FIRST Then Throw "Unexpected constructor delegation message ID"

Local eachInAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nType TNotIterable~nEnd Type~nLocal value:TNotIterable = New TNotIterable~nFor Local item:Object = EachIn value~nNext", "invalid-eachin.bmx")
Local eachInDiagnostic:TDiagnostic = FindModelDiagnostic(eachInAnalysis, "BMX3330")
AssertEqual("EachIn requires an Array, String, StaticArray, IIterable, IIterator, or suitable ObjectEnumerator method.", eachInDiagnostic.MessageFor(germanContext), "EachIn protocol fallback")
If eachInDiagnostic.localisedMessage.id <> LANGUAGE_MSG_BINDING_ITERATION_REQUIRES_SUPPORTED_SOURCE Then Throw "Unexpected EachIn protocol message ID"

AssertEqual("EachIn binding 'first' has type 'Object', but IDeconstruct2 component 1 has type 'String'.", TLanguageMessages.BindingEachInDeconstructionBindingTypeMismatch("first", "Object", 1, "String").Render(germanContext), "deconstruction integer placeholder fallback")

Local duplicateDataAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~n#values~nDefData 1~n#VALUES~nDefData 2", "duplicate-data-label.bmx")
Local duplicateDataDiagnostic:TDiagnostic = FindModelDiagnostic(duplicateDataAnalysis, "BMX3500")
AssertEqual("Duplicate data label 'VALUES'.", duplicateDataDiagnostic.MessageFor(germanContext), "duplicate data label fallback")
If duplicateDataDiagnostic.localisedMessage.id <> LANGUAGE_MSG_DATA_DUPLICATE_LABEL Then Throw "Unexpected duplicate data label message ID"

Local readDataAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nType TUnsupportedRead~nEnd Type~nLocal value:TUnsupportedRead = New TUnsupportedRead~nReadData value", "unsupported-read-data.bmx")
Local readDataDiagnostic:TDiagnostic = FindModelDiagnostic(readDataAnalysis, "BMX3511")
AssertEqual("ReadData does not support target type 'TUnsupportedRead'.", readDataDiagnostic.MessageFor(germanContext), "ReadData target type fallback")
If readDataDiagnostic.localisedMessage.id <> LANGUAGE_MSG_DATA_READ_TARGET_TYPE_UNSUPPORTED Then Throw "Unexpected ReadData target type message ID"

Local constantRangeAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nConst TooBig:Byte = 256", "constant-range.bmx")
Local constantRangeDiagnostic:TDiagnostic = FindModelDiagnostic(constantRangeAnalysis, "BMX3603")
AssertEqual("Constant value is outside the range of 'Byte'.", constantRangeDiagnostic.MessageFor(germanContext), "constant range fallback")
If constantRangeDiagnostic.localisedMessage.id <> LANGUAGE_MSG_CONSTANT_VALUE_OUT_OF_RANGE Then Throw "Unexpected constant range message ID"

Local enumRangeAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nEnum ESmall:Byte~nLarge = 300~nEnd Enum", "enum-range.bmx")
Local enumRangeDiagnostic:TDiagnostic = FindModelDiagnostic(enumRangeAnalysis, "BMX3603")
AssertEqual("Enum value 'Large' is outside the range of 'Byte'.", enumRangeDiagnostic.MessageFor(germanContext), "Enum range fallback")
If enumRangeDiagnostic.localisedMessage.id <> LANGUAGE_MSG_CONSTANT_ENUM_VALUE_OUT_OF_RANGE Then Throw "Unexpected Enum range message ID"

AssertEqual("Constant definition cycle involving 'Answer'.", TLanguageMessages.ConstantDefinitionCycle("Answer").Render(germanContext), "constant-name placeholder fallback")

Local compileEnumAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nEnum EState~nUnknown = 5~nReady~nEnd Enum~nLocal state:EState = EState(7)", "invalid-enum-constant-cast.bmx")
Local compileEnumDiagnostic:TDiagnostic = FindModelDiagnostic(compileEnumAnalysis, "BMX3630")
AssertEqual("The value 7 is not valid for Enum 'EState'.", compileEnumDiagnostic.MessageFor(germanContext), "Enum constant cast fallback")
If compileEnumDiagnostic.localisedMessage.id <> LANGUAGE_MSG_COMPILE_TIME_ENUM_CONSTANT_VALUE_INVALID Then Throw "Unexpected Enum constant cast message ID"

Local staticArrayAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nLocal StaticArray empty:Int[0]", "invalid-static-array-length.bmx")
Local staticArrayDiagnostic:TDiagnostic = FindModelDiagnostic(staticArrayAnalysis, "BMX3620")
AssertEqual("StaticArray length must be between 1 and 2147483647.", staticArrayDiagnostic.MessageFor(germanContext), "StaticArray range fallback")
If staticArrayDiagnostic.localisedMessage.id <> LANGUAGE_MSG_COMPILE_TIME_STATIC_ARRAY_LENGTH_OUT_OF_RANGE Then Throw "Unexpected StaticArray range message ID"

AssertEqual("Constant default for parameter 'count' is incompatible with 'Byte' in routine 'Run' at parameter 1 (declared type 'Byte').", TLanguageMessages.CompileTimeParameterConstantDefaultIncompatible("count", "Byte", "Run", 1, "Byte").Render(germanContext), "parameter default placeholders fallback")

Local loopLabelAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nFunction BadFlow()~nContinue nowhere~nEnd Function", "missing-loop-label.bmx")
Local loopLabelDiagnostic:TDiagnostic = FindModelDiagnostic(loopLabelAnalysis, "BMX3404")
AssertEqual("Loop label 'nowhere' could not be found for Continue.", loopLabelDiagnostic.MessageFor(germanContext), "loop label fallback")
If loopLabelDiagnostic.localisedMessage.id <> LANGUAGE_MSG_CONTROL_FLOW_LOOP_LABEL_NOT_FOUND Then Throw "Unexpected loop label message ID"

Local unreachableAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nFunction Dead()~nReturn~nLocal value:Int = 1~nEnd Function", "unreachable-statement.bmx")
Local unreachableDiagnostic:TDiagnostic = FindModelDiagnostic(unreachableAnalysis, "BMX3401")
AssertEqual("Unreachable statement.", unreachableDiagnostic.MessageFor(germanContext), "unreachable statement fallback")
If unreachableDiagnostic.localisedMessage.id <> LANGUAGE_MSG_CONTROL_FLOW_UNREACHABLE_STATEMENT Then Throw "Unexpected unreachable statement message ID"

AssertEqual("Routine 'Calculate' can reach its implicit default return.", TLanguageMessages.ControlFlowImplicitDefaultReturnReachable("Calculate").Render(germanContext), "implicit return placeholder fallback")
AssertEqual("Exit can be used only inside a loop.", TLanguageMessages.ControlFlowLoopControlRequiresLoop("Exit").Render(germanContext), "loop operation placeholder fallback")

Local finalInheritanceAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nType TFinal Final~nEnd Type~nType TChild Extends TFinal~nEnd Type", "final-inheritance.bmx")
Local finalInheritanceDiagnostic:TDiagnostic = FindModelDiagnostic(finalInheritanceAnalysis, "BMX3205")
AssertEqual("Type 'TFinal' is Final and cannot be extended.", finalInheritanceDiagnostic.MessageFor(germanContext), "Final inheritance fallback")
If finalInheritanceDiagnostic.localisedMessage.id <> LANGUAGE_MSG_INHERITANCE_FINAL_TYPE_CANNOT_BE_EXTENDED Then Throw "Unexpected Final inheritance message ID"

Local constraintAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nInterface ITag~nEnd Interface~nType TBase~nEnd Type~nType TBox<T> Where T Extends ITag~nEnd Type~nGlobal bad:TBox<TBase>", "generic-constraint.bmx")
Local constraintDiagnostic:TDiagnostic = FindModelDiagnostic(constraintAnalysis, "BMX3209")
AssertEqual("Type argument 'TBase' does not satisfy constraint 'ITag' for 'T'.", constraintDiagnostic.MessageFor(germanContext), "generic constraint fallback")
If constraintDiagnostic.localisedMessage.id <> LANGUAGE_MSG_INHERITANCE_TYPE_ARGUMENT_CONSTRAINT_UNSATISFIED Then Throw "Unexpected generic constraint message ID"

Local overrideAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nType TExample~nMethod Missing() Override~nEnd Method~nEnd Type", "invalid-override.bmx")
Local overrideDiagnostic:TDiagnostic = FindModelDiagnostic(overrideAnalysis, "BMX3211")
AssertEqual("Method 'Missing' is marked Override but does not override a method from a base type.", overrideDiagnostic.MessageFor(germanContext), "Override fallback")
If overrideDiagnostic.localisedMessage.id <> LANGUAGE_MSG_INHERITANCE_OVERRIDE_METHOD_NOT_FOUND Then Throw "Unexpected Override message ID"

AssertEqual("Public Function 'Create' exposes private Type 'THidden' through its return type.", TLanguageMessages.InheritancePublicContractExposesHiddenType("Function", "Create", "private", "Type", "THidden", "return type").Render(germanContext), "public contract placeholders fallback")

Local typeResolutionOptions:TLanguageAnalysisOptions = TLanguageAnalysisOptions.Create()
typeResolutionOptions.typeResolution = New TTypeResolutionOptions
typeResolutionOptions.typeResolution.reportUnresolvedTypes = True
Local unresolvedTypeAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nLocal value:MissingType", "unresolved-type.bmx", typeResolutionOptions)
Local unresolvedTypeDiagnostic:TDiagnostic = FindModelDiagnostic(unresolvedTypeAnalysis, "BMX3100")
AssertEqual("Type 'MissingType' could not be resolved in the available scopes.", unresolvedTypeDiagnostic.MessageFor(germanContext), "unresolved type fallback")
If unresolvedTypeDiagnostic.localisedMessage.id <> LANGUAGE_MSG_TYPE_RESOLUTION_TYPE_NOT_RESOLVED Then Throw "Unexpected unresolved type message ID"

Local explicitTypeAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("SuperStrict~nLocal value", "missing-explicit-type.bmx")
Local explicitTypeDiagnostic:TDiagnostic = FindModelDiagnostic(explicitTypeAnalysis, "BMX3103")
AssertEqual("Local 'value' requires an explicit type in SuperStrict code.", explicitTypeDiagnostic.MessageFor(germanContext), "explicit type fallback")
If explicitTypeDiagnostic.localisedMessage.id <> LANGUAGE_MSG_TYPE_RESOLUTION_SYMBOL_REQUIRES_EXPLICIT_TYPE Then Throw "Unexpected explicit type message ID"

Local closureModeAnalysis:TLanguageAnalysis = TBlitzMaxLanguage.AnalyzeText("Strict~nLocal action:Closure<()> = Null", "strict-closure.bmx")
Local closureModeDiagnostic:TDiagnostic = FindModelDiagnostic(closureModeAnalysis, "BMX3120")
AssertEqual("Closure types require SuperStrict mode.", closureModeDiagnostic.MessageFor(germanContext), "Closure mode fallback")
If closureModeDiagnostic.localisedMessage.id <> LANGUAGE_MSG_TYPE_RESOLUTION_CLOSURE_REQUIRES_SUPERSTRICT Then Throw "Unexpected Closure mode message ID"

AssertEqual("Type name 'TValue' is ambiguous. Candidates:~n  first.TValue (first.bmx:2)~n  second.TValue (second.bmx:4)", TLanguageMessages.TypeResolutionAmbiguousTypeName("TValue", "~n  first.TValue (first.bmx:2)~n  second.TValue (second.bmx:4)").Render(germanContext), "ambiguous type candidates fallback")

Local unresolvedSnapshot:TCompilationSnapshot = TCompilationSnapshotBuilder.Build("snapshot-main.bmx", "SuperStrict", Null)
If unresolvedSnapshot.diagnostics.length <> 1 Then Throw "Expected one unresolved snapshot diagnostic"
Local snapshotDiagnostic:TSnapshotDiagnostic = unresolvedSnapshot.diagnostics[0]
AssertEqual("The compiler could not resolve source and module dependencies.", snapshotDiagnostic.MessageFor(germanContext), "snapshot dependency fallback")
If snapshotDiagnostic.localisedMessage.id <> LANGUAGE_MSG_SNAPSHOT_DEPENDENCIES_UNRESOLVED Then Throw "Unexpected snapshot dependency message ID"
AssertEqual("snapshot-main.bmx: error BMX4000: The compiler could not resolve source and module dependencies.", snapshotDiagnostic.FormatFor(unresolvedSnapshot, germanContext), "formatted snapshot fallback")

Local includedSourceDiagnostic:TSnapshotDiagnostic = TSnapshotDiagnostic.Create("BMX4002", TLanguageMessages.SnapshotIncludedSourceNotFound("shared.bmx"), "snapshot-main.bmx")
AssertEqual("Included source 'shared.bmx' could not be found.", includedSourceDiagnostic.MessageFor(germanContext), "included source placeholder fallback")
If includedSourceDiagnostic.localisedMessage.id <> LANGUAGE_MSG_SNAPSHOT_INCLUDED_SOURCE_NOT_FOUND Then Throw "Unexpected included source message ID"

AssertEqual("Generic template artifact 'box.gtmpl' for 'TBox' is invalid. BMXGT100 malformed header", TLanguageMessages.SnapshotGenericTemplateArtifactInvalid("box.gtmpl", "TBox", " BMXGT100 malformed header").Render(germanContext), "generic template detail fallback")

AssertEqual("Function 'Run' is being used as a value rather than called.~nAdd parentheses to call it: Run()", TLanguageMessages.BindingRoutineUsedAsValue("Function", "Run", "Run").Render(germanContext), "multiline binding fallback")
AssertEqual("Generic type 'TBox' expects 2 type argument(s), but 1 were supplied.", TLanguageMessages.BindingGenericTypeArgumentCountMismatch("TBox", 2, 1).Render(germanContext), "generic count fallback")

Local unterminatedString:TDiagnostic = FindDiagnostic(TBlitzMaxParser.ParseText(Chr(34) + "unfinished", "unterminated-string.bmx"), "BMX1000")
AssertEqual("Unterminated string literal.", unterminatedString.MessageFor(germanContext), "lexer fallback")
If unterminatedString.localisedMessage.id <> LANGUAGE_MSG_LEXER_UNTERMINATED_STRING Then Throw "Unexpected lexer message ID"

Local missingRoutineName:TDiagnostic = FindDiagnostic(TBlitzMaxParser.ParseText("SuperStrict~nFunction~nEnd Function", "missing-routine-name.bmx"), "BMX2000")
AssertEqual("Expected a routine name.", missingRoutineName.MessageFor(germanContext), "parser routine fallback")
If missingRoutineName.localisedMessage.id <> LANGUAGE_MSG_PARSER_EXPECTED_ROUTINE_NAME Then Throw "Unexpected routine-name message ID"

Local interfaceFile:TInterfaceFile = TBlitzMaxParser.ParseInterfaceText("'@generic-template 1", "invalid-interface.i")
If interfaceFile.diagnostics.length <> 1 Then Throw "Expected one interface diagnostic"
Local interfaceDiagnostic:TInterfaceDiagnostic = interfaceFile.diagnostics[0]
AssertEqual("Generic template reference does not follow a Type, Function, or Method record.", interfaceDiagnostic.MessageFor(germanContext), "interface fallback")
If interfaceDiagnostic.localisedMessage.id <> LANGUAGE_MSG_INTERFACE_GENERIC_TEMPLATE_REQUIRES_DECLARATION Then Throw "Unexpected interface message ID"
AssertEqual("invalid-interface.i:1: error BMXI110: Generic template reference does not follow a Type, Function, or Method record.", interfaceDiagnostic.FormatFor("invalid-interface.i", germanContext), "formatted interface fallback")

AssertEqual("Expected '}' after declaration metadata.", TLanguageMessages.MetadataExpectedCloseBrace().Render(germanContext), "escaped metadata brace fallback")
AssertEqual("Variable 'value' is assigned to itself. Did you mean 'Self.value'?", TLanguageMessages.BindingVariableAssignedToItself("value", " Did you mean 'Self.value'?").Render(germanContext), "self-assignment suggestion fallback")

Print "PASS: localised diagnostics, typed placeholders, plurals, and explicit contexts"

Function FindDepthDiagnostic:TDiagnostic(parsed:TParseResult)
	For Local diagnostic:TDiagnostic = EachIn parsed.syntaxTree.diagnostics
		If diagnostic.code = "BMX2103" Then Return diagnostic
	Next
	Throw "BMX2103 was not produced"
End Function

Function FindDiagnostic:TDiagnostic(parsed:TParseResult, code:String)
	For Local diagnostic:TDiagnostic = EachIn parsed.syntaxTree.diagnostics
		If diagnostic.code = code Then Return diagnostic
	Next
	Throw code + " was not produced"
End Function

Function FindModelDiagnostic:TDiagnostic(analysis:TLanguageAnalysis, code:String)
	If analysis And analysis.model Then
		For Local diagnostic:TDiagnostic = EachIn analysis.model.diagnostics
			If diagnostic.code = code Then Return diagnostic
		Next
	End If
	Throw code + " was not produced by semantic analysis"
End Function

Function AssertMessageIdentity(diagnostic:TDiagnostic)
	If Not diagnostic.localisedMessage Then Throw "Diagnostic did not retain its localised message"
	AssertEqual("language", diagnostic.localisedMessage.domain, "message domain")
	If diagnostic.localisedMessage.id <> LANGUAGE_MSG_PARSER_EXPRESSION_NESTING_TOO_DEEP Then Throw "Unexpected message ID"
End Function

Function AssertEqual(expected:String, actual:String, label:String)
	If expected <> actual Then Throw label + ": expected '" + expected + "', got '" + actual + "'"
End Function
