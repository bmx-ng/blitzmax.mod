' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "diagnostic.bmx"
Import "token.bmx"

Const SYNTAX_COMPILATION_UNIT:Int = 1
Const SYNTAX_BLOCK:Int = 2
Const SYNTAX_ROUTINE_DECLARATION:Int = 3
Const SYNTAX_TYPE_DECLARATION:Int = 4
Const SYNTAX_BLOCK_TERMINATOR:Int = 5
Const SYNTAX_END_STATEMENT:Int = 6
Const SYNTAX_CALL_STATEMENT:Int = 7
Const SYNTAX_RAW_STATEMENT:Int = 8
Const SYNTAX_ASSIGNMENT_STATEMENT:Int = 9
Const SYNTAX_VARIABLE_DECLARATION_STATEMENT:Int = 10
Const SYNTAX_VARIABLE_DECLARATOR:Int = 11
Const SYNTAX_NAME_EXPRESSION:Int = 20
Const SYNTAX_LITERAL_EXPRESSION:Int = 21
Const SYNTAX_PARENTHESES_EXPRESSION:Int = 22
Const SYNTAX_UNARY_EXPRESSION:Int = 23
Const SYNTAX_BINARY_EXPRESSION:Int = 24
Const SYNTAX_MEMBER_EXPRESSION:Int = 25
Const SYNTAX_CALL_EXPRESSION:Int = 26
Const SYNTAX_INDEX_EXPRESSION:Int = 27
Const SYNTAX_RAW_EXPRESSION:Int = 28
Const SYNTAX_TYPE_ASCRIPTION_EXPRESSION:Int = 29
Const SYNTAX_TYPE_REFERENCE:Int = 30
Const SYNTAX_ROUTINE_SIGNATURE:Int = 31
Const SYNTAX_PARAMETER:Int = 32
Const SYNTAX_SLICE_EXPRESSION:Int = 33
Const SYNTAX_NEW_EXPRESSION:Int = 34
Const SYNTAX_ARRAY_LITERAL_EXPRESSION:Int = 35
Const SYNTAX_SCOPE_EXPRESSION:Int = 36
Const SYNTAX_CAST_EXPRESSION:Int = 37
Const SYNTAX_OMITTED_ARGUMENT_EXPRESSION:Int = 38
Const SYNTAX_IF_STATEMENT:Int = 40
Const SYNTAX_ELSEIF_CLAUSE:Int = 41
Const SYNTAX_ELSE_CLAUSE:Int = 42
Const SYNTAX_WHILE_STATEMENT:Int = 43
Const SYNTAX_REPEAT_STATEMENT:Int = 44
Const SYNTAX_FOR_STATEMENT:Int = 45
Const SYNTAX_SELECT_STATEMENT:Int = 46
Const SYNTAX_CASE_CLAUSE:Int = 47
Const SYNTAX_DEFAULT_CLAUSE:Int = 48
Const SYNTAX_TRY_STATEMENT:Int = 49
Const SYNTAX_CATCH_CLAUSE:Int = 50
Const SYNTAX_FINALLY_CLAUSE:Int = 51
Const SYNTAX_USING_STATEMENT:Int = 52
Const SYNTAX_CONDITIONAL_REGION:Int = 53
Const SYNTAX_CONDITIONAL_BRANCH:Int = 54
Const SYNTAX_CONDITIONAL_NAME:Int = 55
Const SYNTAX_CONDITIONAL_NOT:Int = 56
Const SYNTAX_CONDITIONAL_BINARY:Int = 57
Const SYNTAX_CONDITIONAL_PARENTHESES:Int = 58
Const SYNTAX_FOR_HEADER:Int = 59
Const SYNTAX_RETURN_STATEMENT:Int = 60
Const SYNTAX_THROW_STATEMENT:Int = 61
Const SYNTAX_EXIT_STATEMENT:Int = 62
Const SYNTAX_CONTINUE_STATEMENT:Int = 63
Const SYNTAX_ASSERT_STATEMENT:Int = 64
Const SYNTAX_LABEL:Int = 65
Const SYNTAX_SOURCE_MODE:Int = 66
Const SYNTAX_DEFDATA_STATEMENT:Int = 67
Const SYNTAX_READDATA_STATEMENT:Int = 68
Const SYNTAX_RESTOREDATA_STATEMENT:Int = 69
Const SYNTAX_ENUM_DECLARATION:Int = 70
Const SYNTAX_ENUM_VALUE:Int = 71
Const SYNTAX_TYPE_DECLARATION_HEADER:Int = 72
Const SYNTAX_GENERIC_PARAMETER:Int = 73
Const SYNTAX_VISIBILITY_SECTION:Int = 74
Const SYNTAX_GENERIC_CONSTRAINT:Int = 75
Const SYNTAX_IMPORT_DIRECTIVE:Int = 76
Const SYNTAX_INCLUDE_DIRECTIVE:Int = 77
Const SYNTAX_EXTERN_BLOCK:Int = 78
Const SYNTAX_CALLABLE_TYPE:Int = 79
Const SYNTAX_TYPE_SUFFIX:Int = 80
Const SYNTAX_STATIC_ARRAY_BOUND:Int = 81
Const SYNTAX_FUNCTION_LITERAL_EXPRESSION:Int = 82
Const SYNTAX_RELEASE_STATEMENT:Int = 83
Const SYNTAX_RANGE_EXPRESSION:Int = 84
Const SYNTAX_YIELD_STATEMENT:Int = 85

Const TYPE_SUFFIX_POINTER:Int = 1
Const TYPE_SUFFIX_ARRAY:Int = 2

Const SOURCE_MODE_STRICT:Int = 1
Const SOURCE_MODE_SUPERSTRICT:Int = 2

Const VISIBILITY_PUBLIC:Int = 1
Const VISIBILITY_PRIVATE:Int = 2
Const VISIBILITY_PROTECTED:Int = 3
Const VISIBILITY_INTERNAL:Int = 4
Const VISIBILITY_PRIVATE_INTERNAL:Int = 5
Const VISIBILITY_PROTECTED_INTERNAL:Int = 6

Rem
bbdoc: Base type for every node in a BlitzMax syntax tree.
about: The #kind identifies the concrete syntax category and #span identifies its
characters in the original source.
End Rem
Type TSyntaxNode Abstract
	Field kind:Int
	Field span:TSourceSpan

	Rem
	bbdoc: Returns a readable name for this node's syntax kind.
	End Rem
	Method KindName:String()
		Select kind
			Case SYNTAX_COMPILATION_UNIT Return "CompilationUnit"
			Case SYNTAX_BLOCK Return "Block"
			Case SYNTAX_ROUTINE_DECLARATION Return "RoutineDeclaration"
			Case SYNTAX_TYPE_DECLARATION Return "TypeDeclaration"
			Case SYNTAX_BLOCK_TERMINATOR Return "BlockTerminator"
			Case SYNTAX_END_STATEMENT Return "EndStatement"
			Case SYNTAX_CALL_STATEMENT Return "CallStatement"
			Case SYNTAX_RAW_STATEMENT Return "RawStatement"
			Case SYNTAX_ASSIGNMENT_STATEMENT Return "AssignmentStatement"
			Case SYNTAX_VARIABLE_DECLARATION_STATEMENT Return "VariableDeclarationStatement"
			Case SYNTAX_VARIABLE_DECLARATOR Return "VariableDeclarator"
			Case SYNTAX_NAME_EXPRESSION Return "NameExpression"
			Case SYNTAX_LITERAL_EXPRESSION Return "LiteralExpression"
			Case SYNTAX_PARENTHESES_EXPRESSION Return "ParenthesizedExpression"
			Case SYNTAX_UNARY_EXPRESSION Return "UnaryExpression"
			Case SYNTAX_BINARY_EXPRESSION Return "BinaryExpression"
			Case SYNTAX_MEMBER_EXPRESSION Return "MemberAccessExpression"
			Case SYNTAX_CALL_EXPRESSION Return "CallExpression"
			Case SYNTAX_INDEX_EXPRESSION Return "IndexExpression"
			Case SYNTAX_RAW_EXPRESSION Return "RawExpression"
			Case SYNTAX_TYPE_ASCRIPTION_EXPRESSION Return "TypeAscriptionExpression"
			Case SYNTAX_TYPE_REFERENCE Return "TypeReference"
			Case SYNTAX_ROUTINE_SIGNATURE Return "RoutineSignature"
			Case SYNTAX_PARAMETER Return "Parameter"
			Case SYNTAX_CALLABLE_TYPE Return "CallableType"
			Case SYNTAX_TYPE_SUFFIX Return "TypeSuffix"
			Case SYNTAX_SLICE_EXPRESSION Return "SliceExpression"
			Case SYNTAX_NEW_EXPRESSION Return "NewExpression"
			Case SYNTAX_ARRAY_LITERAL_EXPRESSION Return "ArrayLiteralExpression"
			Case SYNTAX_SCOPE_EXPRESSION Return "ScopeExpression"
			Case SYNTAX_CAST_EXPRESSION Return "CastExpression"
			Case SYNTAX_OMITTED_ARGUMENT_EXPRESSION Return "OmittedArgumentExpression"
			Case SYNTAX_FUNCTION_LITERAL_EXPRESSION Return "FunctionLiteralExpression"
			Case SYNTAX_RANGE_EXPRESSION Return "RangeExpression"
			Case SYNTAX_IF_STATEMENT Return "IfStatement"
			Case SYNTAX_ELSEIF_CLAUSE Return "ElseIfClause"
			Case SYNTAX_ELSE_CLAUSE Return "ElseClause"
			Case SYNTAX_WHILE_STATEMENT Return "WhileStatement"
			Case SYNTAX_REPEAT_STATEMENT Return "RepeatStatement"
			Case SYNTAX_FOR_STATEMENT Return "ForStatement"
			Case SYNTAX_SELECT_STATEMENT Return "SelectStatement"
			Case SYNTAX_CASE_CLAUSE Return "CaseClause"
			Case SYNTAX_DEFAULT_CLAUSE Return "DefaultClause"
			Case SYNTAX_TRY_STATEMENT Return "TryStatement"
			Case SYNTAX_CATCH_CLAUSE Return "CatchClause"
			Case SYNTAX_FINALLY_CLAUSE Return "FinallyClause"
			Case SYNTAX_USING_STATEMENT Return "UsingStatement"
			Case SYNTAX_CONDITIONAL_REGION Return "ConditionalRegion"
			Case SYNTAX_CONDITIONAL_BRANCH Return "ConditionalBranch"
			Case SYNTAX_CONDITIONAL_NAME Return "ConditionalName"
			Case SYNTAX_CONDITIONAL_NOT Return "ConditionalNot"
			Case SYNTAX_CONDITIONAL_BINARY Return "ConditionalBinary"
			Case SYNTAX_CONDITIONAL_PARENTHESES Return "ConditionalParenthesized"
			Case SYNTAX_FOR_HEADER Return "ForHeader"
			Case SYNTAX_RETURN_STATEMENT Return "ReturnStatement"
			Case SYNTAX_THROW_STATEMENT Return "ThrowStatement"
			Case SYNTAX_EXIT_STATEMENT Return "ExitStatement"
			Case SYNTAX_CONTINUE_STATEMENT Return "ContinueStatement"
			Case SYNTAX_ASSERT_STATEMENT Return "AssertStatement"
			Case SYNTAX_RELEASE_STATEMENT Return "ReleaseStatement"
			Case SYNTAX_YIELD_STATEMENT Return "YieldStatement"
			Case SYNTAX_LABEL Return "Label"
			Case SYNTAX_SOURCE_MODE Return "SourceMode"
			Case SYNTAX_DEFDATA_STATEMENT Return "DefDataStatement"
			Case SYNTAX_READDATA_STATEMENT Return "ReadDataStatement"
			Case SYNTAX_RESTOREDATA_STATEMENT Return "RestoreDataStatement"
			Case SYNTAX_ENUM_DECLARATION Return "EnumDeclaration"
			Case SYNTAX_ENUM_VALUE Return "EnumValue"
			Case SYNTAX_TYPE_DECLARATION_HEADER Return "TypeDeclarationHeader"
			Case SYNTAX_GENERIC_PARAMETER Return "GenericParameter"
			Case SYNTAX_IMPORT_DIRECTIVE Return "ImportDirective"
			Case SYNTAX_INCLUDE_DIRECTIVE Return "IncludeDirective"
			Case SYNTAX_EXTERN_BLOCK Return "ExternBlock"
			Case SYNTAX_VISIBILITY_SECTION Return "VisibilitySection"
			Case SYNTAX_GENERIC_CONSTRAINT Return "GenericConstraint"
			Case SYNTAX_STATIC_ARRAY_BOUND Return "StaticArrayBound"
		End Select
		Return "UnknownSyntax"
	End Method
End Type

Type TCompilationUnitSyntax Extends TSyntaxNode
	Field members:TSyntaxNode[]
	Field tokens:TSyntaxToken[]
	Field endOfFileToken:TSyntaxToken
	Field sourceMode:Int
	Field sourceModeDeclaration:TSourceModeSyntax
End Type

Type TSourceModeSyntax Extends TSyntaxNode
	Field modeToken:TSyntaxToken
	Field sourceMode:Int
End Type

Type TBlockSyntax Extends TSyntaxNode
	Field statements:TSyntaxNode[]
End Type

Type TBlockTerminatorSyntax Extends TSyntaxNode
	Field endToken:TSyntaxToken
	Field blockToken:TSyntaxToken
	Field expectedBlockKind:String
	Field actualBlockKind:String
End Type

Type TRoutineDeclarationSyntax Extends TSyntaxNode
	Field declarationToken:TSyntaxToken
	Field nameToken:TSyntaxToken
	Field headerTokens:TSyntaxToken[]
	Field body:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
	Field isMethod:Int
	Field signature:TRoutineSignatureSyntax
End Type

Type TTypeDeclarationSyntax Extends TSyntaxNode
	Field declarationToken:TSyntaxToken
	Field nameToken:TSyntaxToken
	Field headerTokens:TSyntaxToken[]
	Field header:TTypeDeclarationHeaderSyntax
	Field body:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TExternBlockSyntax Extends TSyntaxNode
	Field externToken:TSyntaxToken
	Field headerTokens:TSyntaxToken[]
	Field callingConventionToken:TSyntaxToken
	Field body:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TTypeDeclarationHeaderSyntax Extends TSyntaxNode
	Field tokens:TSyntaxToken[]
	Field nameToken:TSyntaxToken
	Field genericOpenToken:TSyntaxToken
	Field genericParameters:TGenericParameterSyntax[]
	Field genericCloseToken:TSyntaxToken
	Field whereToken:TSyntaxToken
	Field whereTokens:TSyntaxToken[]
	Field constraints:TGenericConstraintSyntax[]
	Field extendsToken:TSyntaxToken
	Field extendsTypes:TTypeReferenceSyntax[]
	Field implementsToken:TSyntaxToken
	Field implementedTypes:TTypeReferenceSyntax[]
	Field modifierTokens:TSyntaxToken[]
	Field metadataTokens:TSyntaxToken[]
	Field trailingTokens:TSyntaxToken[]
End Type

Type TGenericParameterSyntax Extends TSyntaxNode
	Field nameToken:TSyntaxToken
	Field separatorToken:TSyntaxToken
End Type

Type TGenericConstraintSyntax Extends TSyntaxNode
	Field parameterNameToken:TSyntaxToken
	Field extendsToken:TSyntaxToken
	Field constraintTypes:TTypeReferenceSyntax[]
	Field andTokens:TSyntaxToken[]
	Field separatorToken:TSyntaxToken
End Type

Type TVisibilitySectionSyntax Extends TSyntaxNode
	Field visibilityToken:TSyntaxToken
	Field internalToken:TSyntaxToken
	Field visibility:Int
End Type

Type TEnumDeclarationSyntax Extends TSyntaxNode
	Field enumToken:TSyntaxToken
	Field nameToken:TSyntaxToken
	Field typeTokens:TSyntaxToken[]
	Field underlyingType:TTypeReferenceSyntax
	Field flagsToken:TSyntaxToken
	Field values:TEnumValueSyntax[]
	Field terminator:TBlockTerminatorSyntax
End Type

Type TEnumValueSyntax Extends TSyntaxNode
	Field nameToken:TSyntaxToken
	Field assignmentToken:TSyntaxToken
	Field value:TExpressionSyntax
	Field separatorToken:TSyntaxToken
End Type

Type TEndStatementSyntax Extends TSyntaxNode
	Field endToken:TSyntaxToken
End Type

Type TReturnStatementSyntax Extends TSyntaxNode
	Field returnToken:TSyntaxToken
	Field expression:TExpressionSyntax
End Type

Type TYieldStatementSyntax Extends TSyntaxNode
	Field yieldToken:TSyntaxToken
	Field fromToken:TSyntaxToken
	Field expression:TExpressionSyntax
End Type

Type TThrowStatementSyntax Extends TSyntaxNode
	Field throwToken:TSyntaxToken
	Field expression:TExpressionSyntax
End Type

Type TExitStatementSyntax Extends TSyntaxNode
	Field exitToken:TSyntaxToken
	Field label:TExpressionSyntax
End Type

Type TContinueStatementSyntax Extends TSyntaxNode
	Field continueToken:TSyntaxToken
	Field label:TExpressionSyntax
End Type

Type TAssertStatementSyntax Extends TSyntaxNode
	Field assertToken:TSyntaxToken
	Field condition:TExpressionSyntax
	Field separatorToken:TSyntaxToken
	Field message:TExpressionSyntax
End Type

Type TReleaseStatementSyntax Extends TSyntaxNode
	Field releaseToken:TSyntaxToken
	Field expression:TExpressionSyntax
End Type

Type TDefDataStatementSyntax Extends TSyntaxNode
	Field defDataToken:TSyntaxToken
	Field label:TLabelSyntax
	Field values:TExpressionSyntax[]
End Type

Type TReadDataStatementSyntax Extends TSyntaxNode
	Field readDataToken:TSyntaxToken
	Field targets:TExpressionSyntax[]
End Type

Type TRestoreDataStatementSyntax Extends TSyntaxNode
	Field restoreDataToken:TSyntaxToken
	Field label:TExpressionSyntax
End Type

Type TCallStatementSyntax Extends TSyntaxNode
	Field tokens:TSyntaxToken[]
	Field calleeTokens:TSyntaxToken[]
	Field argumentTokens:TSyntaxToken[]
	Field hasParentheses:Int
	Field expression:TExpressionSyntax
	Field argumentExpressions:TExpressionSyntax[]
End Type

Type TRawStatementSyntax Extends TSyntaxNode
	Field tokens:TSyntaxToken[]
End Type

Type TImportDirectiveSyntax Extends TSyntaxNode
	Field importToken:TSyntaxToken
	Field targetTokens:TSyntaxToken[]
	Field targetText:String
	Field isFramework:Int
	Field isFileImport:Int
	Field isSourceImport:Int
	Field isNativeImport:Int
End Type

Type TIncludeDirectiveSyntax Extends TSyntaxNode
	Field includeToken:TSyntaxToken
	Field pathToken:TSyntaxToken
	Field pathText:String
End Type

Type TAssignmentStatementSyntax Extends TSyntaxNode
	Field left:TExpressionSyntax
	Field operatorToken:TSyntaxToken
	Field right:TExpressionSyntax
End Type

Type TVariableDeclarationStatementSyntax Extends TSyntaxNode
	Field declarationToken:TSyntaxToken
	Field staticArrayToken:TSyntaxToken
	Field modifierTokens:TSyntaxToken[]
	Field declarators:TVariableDeclaratorSyntax[]
End Type

Type TVariableDeclaratorSyntax Extends TSyntaxNode
	Field nameToken:TSyntaxToken
	Field typeTokens:TSyntaxToken[]
	Field assignmentToken:TSyntaxToken
	' Present only for the explicit Local name := initializer form.  Keep
	' inference distinct from both a written type and ordinary '=' syntax.
	Field inferenceToken:TSyntaxToken
	Field initializer:TExpressionSyntax
	Field arrayDimensions:TExpressionSyntax[] = New TExpressionSyntax[0]
	Field declaredType:TTypeReferenceSyntax
	Field callableType:TCallableTypeSyntax
	Field staticArrayBound:TStaticArrayBoundSyntax
	Field metadataTokens:TSyntaxToken[]
End Type

Type TStaticArrayBoundSyntax Extends TSyntaxNode
	Field openToken:TSyntaxToken
	Field lengthExpression:TExpressionSyntax
	Field closeToken:TSyntaxToken
End Type

Type TCallableTypeSyntax Extends TSyntaxNode
	Field returnType:TTypeReferenceSyntax
	Field openParenToken:TSyntaxToken
	Field parameters:TParameterSyntax[]
	Field closeParenToken:TSyntaxToken
	Field callingConventionToken:TSyntaxToken
	Field suffixes:TTypeSuffixSyntax[]
End Type

Type TTypeReferenceSyntax Extends TSyntaxNode
	Field tokens:TSyntaxToken[]
	Field markerToken:TSyntaxToken
	Field nameTokens:TSyntaxToken[]
	Field genericArguments:TTypeReferenceSyntax[]
	' Compiler-intrinsic Closure<return(parameters)> stores its signature
	' explicitly rather than pretending the signature is an ordinary type arg.
	Field closureSignature:TCallableTypeSyntax
	Field pointerTokens:TSyntaxToken[]
	Field arrayRanks:Int[]
	Field suffixes:TTypeSuffixSyntax[]
End Type

Type TTypeSuffixSyntax Extends TSyntaxNode
	Field suffixKind:Int
	Field tokens:TSyntaxToken[]
	Field rank:Int
End Type

Type TRoutineSignatureSyntax Extends TSyntaxNode
	Field nameToken:TSyntaxToken
	Field operatorTokens:TSyntaxToken[]
	Field operatorName:String
	Field genericOpenToken:TSyntaxToken
	Field genericParameters:TGenericParameterSyntax[]
	Field genericCloseToken:TSyntaxToken
	Field returnType:TTypeReferenceSyntax
	Field callableReturnType:TCallableTypeSyntax
	Field openParenToken:TSyntaxToken
	Field parameters:TParameterSyntax[]
	Field closeParenToken:TSyntaxToken
	Field whereToken:TSyntaxToken
	Field whereTokens:TSyntaxToken[]
	Field constraints:TGenericConstraintSyntax[]
	Field modifierTokens:TSyntaxToken[]
End Type

Type TParameterSyntax Extends TSyntaxNode
	Field modifierTokens:TSyntaxToken[]
	Field staticArrayToken:TSyntaxToken
	Field staticArrayBound:TStaticArrayBoundSyntax
	Field nameToken:TSyntaxToken
	Field declaredType:TTypeReferenceSyntax
	Field callableType:TCallableTypeSyntax
	Field varToken:TSyntaxToken
	Field assignmentToken:TSyntaxToken
	Field defaultValue:TExpressionSyntax
End Type

Type TIfStatementSyntax Extends TSyntaxNode
	Field ifToken:TSyntaxToken
	Field condition:TExpressionSyntax
	Field thenToken:TSyntaxToken
	Field thenBlock:TBlockSyntax
	Field elseIfClauses:TElseIfClauseSyntax[]
	Field elseClause:TElseClauseSyntax
	Field terminator:TBlockTerminatorSyntax
	Field singleLine:Int
End Type

Type TElseIfClauseSyntax Extends TSyntaxNode
	Field elseIfToken:TSyntaxToken
	Field condition:TExpressionSyntax
	Field thenToken:TSyntaxToken
	Field block:TBlockSyntax
End Type

Type TElseClauseSyntax Extends TSyntaxNode
	Field elseToken:TSyntaxToken
	Field block:TBlockSyntax
End Type

Type TWhileStatementSyntax Extends TSyntaxNode
	Field label:TLabelSyntax
	Field whileToken:TSyntaxToken
	Field condition:TExpressionSyntax
	Field body:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TRepeatStatementSyntax Extends TSyntaxNode
	Field label:TLabelSyntax
	Field repeatToken:TSyntaxToken
	Field body:TBlockSyntax
	Field terminationToken:TSyntaxToken
	Field condition:TExpressionSyntax
End Type

Type TForStatementSyntax Extends TSyntaxNode
	Field label:TLabelSyntax
	Field forToken:TSyntaxToken
	Field headerTokens:TSyntaxToken[]
	Field header:TForHeaderSyntax
	Field body:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TLabelSyntax Extends TSyntaxNode
	Field hashToken:TSyntaxToken
	Field nameToken:TSyntaxToken
End Type

Type TForHeaderSyntax Extends TSyntaxNode
	Field localToken:TSyntaxToken
	Field declaration:TVariableDeclaratorSyntax
	' All declared loop bindings. declaration remains the compatibility view of
	' the first binding used by ordinary one-variable For loops.
	Field declarations:TVariableDeclaratorSyntax[] = New TVariableDeclaratorSyntax[0]
	Field target:TExpressionSyntax
	Field assignmentToken:TSyntaxToken
	Field initialValue:TExpressionSyntax
	Field eachInToken:TSyntaxToken
	Field collection:TExpressionSyntax
	Field rangeToken:TSyntaxToken
	Field limit:TExpressionSyntax
	Field stepToken:TSyntaxToken
	Field stepExpression:TExpressionSyntax
End Type

Type TSelectStatementSyntax Extends TSyntaxNode
	Field selectToken:TSyntaxToken
	Field expression:TExpressionSyntax
	Field cases:TCaseClauseSyntax[]
	' Compatibility view of the first Default clause. Use defaultClauses when
	' conditional compilation can provide target-specific alternatives.
	Field defaultClause:TDefaultClauseSyntax
	Field defaultClauses:TDefaultClauseSyntax[] = New TDefaultClauseSyntax[0]
	Field terminator:TBlockTerminatorSyntax
End Type

Type TCaseClauseSyntax Extends TSyntaxNode
	Field caseToken:TSyntaxToken
	Field values:TExpressionSyntax[]
	Field body:TBlockSyntax
	Field conditionalExpression:TConditionalExpressionSyntax
End Type

Type TDefaultClauseSyntax Extends TSyntaxNode
	Field defaultToken:TSyntaxToken
	Field body:TBlockSyntax
	Field conditionalExpression:TConditionalExpressionSyntax
End Type

Type TTryStatementSyntax Extends TSyntaxNode
	Field tryToken:TSyntaxToken
	Field body:TBlockSyntax
	Field catches:TCatchClauseSyntax[]
	Field finallyClause:TFinallyClauseSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TCatchClauseSyntax Extends TSyntaxNode
	Field catchToken:TSyntaxToken
	Field headerTokens:TSyntaxToken[]
	Field nameToken:TSyntaxToken
	Field declaredType:TTypeReferenceSyntax
	Field body:TBlockSyntax
End Type

Type TFinallyClauseSyntax Extends TSyntaxNode
	Field finallyToken:TSyntaxToken
	Field body:TBlockSyntax
End Type

Type TUsingStatementSyntax Extends TSyntaxNode
	Field usingToken:TSyntaxToken
	Field resources:TVariableDeclarationStatementSyntax[]
	Field doToken:TSyntaxToken
	Field body:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TConditionalRegionSyntax Extends TSyntaxNode
	Field branches:TConditionalBranchSyntax[]
	Field endDirectiveToken:TSyntaxToken
	Field sharedRoutineBody:TBlockSyntax
	Field sharedRoutineTerminator:TBlockTerminatorSyntax
	Field sharedControlTerminator:TBlockTerminatorSyntax
	Field trailingRegion:TConditionalRegionSyntax
End Type

Type TConditionalBranchSyntax Extends TSyntaxNode
	Field directiveToken:TSyntaxToken
	Field conditionText:String
	Field condition:TConditionalExpressionSyntax
	Field body:TBlockSyntax
	Field trailingBody:TBlockSyntax
End Type

Type TConditionalExpressionSyntax Extends TSyntaxNode Abstract
End Type

Type TConditionalNameSyntax Extends TConditionalExpressionSyntax
	Field nameToken:TSyntaxToken
End Type

Type TConditionalNotSyntax Extends TConditionalExpressionSyntax
	Field notToken:TSyntaxToken
	Field operand:TConditionalExpressionSyntax
End Type

Type TConditionalBinarySyntax Extends TConditionalExpressionSyntax
	Field left:TConditionalExpressionSyntax
	Field operatorToken:TSyntaxToken
	Field right:TConditionalExpressionSyntax
End Type

Type TConditionalParenthesizedSyntax Extends TConditionalExpressionSyntax
	Field openToken:TSyntaxToken
	Field expression:TConditionalExpressionSyntax
	Field closeToken:TSyntaxToken
End Type

Type TExpressionSyntax Extends TSyntaxNode Abstract
End Type

Type TFunctionLiteralExpressionSyntax Extends TExpressionSyntax
	Field functionToken:TSyntaxToken
	Field headerTokens:TSyntaxToken[]
	Field returnType:TTypeReferenceSyntax
	Field openParenToken:TSyntaxToken
	Field parameters:TParameterSyntax[]
	Field closeParenToken:TSyntaxToken
	Field body:TBlockSyntax
	Field terminator:TBlockTerminatorSyntax
End Type

Type TNameExpressionSyntax Extends TExpressionSyntax
	Field nameToken:TSyntaxToken
	Field legacyTypeTagToken:TSyntaxToken
	Field genericOpenToken:TSyntaxToken
	Field typeArguments:TTypeReferenceSyntax[]
	Field genericCloseToken:TSyntaxToken
	Field qualifiedSuperOpenToken:TSyntaxToken
	Field qualifiedSuperType:TTypeReferenceSyntax
	Field qualifiedSuperCloseToken:TSyntaxToken
End Type

Type TLiteralExpressionSyntax Extends TExpressionSyntax
	Field literalToken:TSyntaxToken
End Type

Type TParenthesizedExpressionSyntax Extends TExpressionSyntax
	Field openToken:TSyntaxToken
	Field expression:TExpressionSyntax
	Field closeToken:TSyntaxToken
End Type

Type TUnaryExpressionSyntax Extends TExpressionSyntax
	Field operatorToken:TSyntaxToken
	Field operand:TExpressionSyntax
End Type

Type TBinaryExpressionSyntax Extends TExpressionSyntax
	Field left:TExpressionSyntax
	Field operatorToken:TSyntaxToken
	Field right:TExpressionSyntax
End Type

Type TMemberAccessExpressionSyntax Extends TExpressionSyntax
	Field expression:TExpressionSyntax
	Field dotToken:TSyntaxToken
	Field nameToken:TSyntaxToken
	Field legacyTypeTagToken:TSyntaxToken
	Field genericOpenToken:TSyntaxToken
	Field typeArguments:TTypeReferenceSyntax[]
	Field genericCloseToken:TSyntaxToken
End Type

Type TCallExpressionSyntax Extends TExpressionSyntax
	Field callee:TExpressionSyntax
	Field genericOpenToken:TSyntaxToken
	Field typeArguments:TTypeReferenceSyntax[]
	Field genericCloseToken:TSyntaxToken
	Field openToken:TSyntaxToken
	Field arguments:TExpressionSyntax[]
	Field closeToken:TSyntaxToken
End Type

Type TIndexExpressionSyntax Extends TExpressionSyntax
	Field expression:TExpressionSyntax
	Field openToken:TSyntaxToken
	Field indexes:TExpressionSyntax[]
	Field closeToken:TSyntaxToken
End Type

Type TSliceExpressionSyntax Extends TExpressionSyntax
	Field expression:TExpressionSyntax
	Field openToken:TSyntaxToken
	Field lowerBound:TExpressionSyntax
	Field lowerFromEndToken:TSyntaxToken
	Field rangeToken:TSyntaxToken
	Field upperBound:TExpressionSyntax
	Field upperFromEndToken:TSyntaxToken
	Field closeToken:TSyntaxToken
End Type

Type TRangeExpressionSyntax Extends TExpressionSyntax
	Field lowerBound:TExpressionSyntax
	Field lowerFromEndToken:TSyntaxToken
	Field rangeToken:TSyntaxToken
	Field upperBound:TExpressionSyntax
	Field upperFromEndToken:TSyntaxToken
End Type

Type TTypeAscriptionExpressionSyntax Extends TExpressionSyntax
	Field expression:TExpressionSyntax
	Field colonToken:TSyntaxToken
	Field targetType:TTypeReferenceSyntax
End Type

Type TNewExpressionSyntax Extends TExpressionSyntax
	Field newToken:TSyntaxToken
	Field createdType:TTypeReferenceSyntax
	' Bound only for the deprecated production-compatible `New value` form.
	' It is synthetic because the source token initially occupies the grammar's
	' type position.
	Field instanceExpression:TExpressionSyntax
	Field openParenToken:TSyntaxToken
	Field arguments:TExpressionSyntax[]
	Field closeParenToken:TSyntaxToken
	Field suffixTokens:TSyntaxToken[]
	Field dimensions:TExpressionSyntax[]
	Field dimensionRanks:Int[]
End Type

Type TArrayLiteralExpressionSyntax Extends TExpressionSyntax
	Field openToken:TSyntaxToken
	Field elements:TExpressionSyntax[]
	Field closeToken:TSyntaxToken
	Field emptyToken:TSyntaxToken
End Type

Type TScopeExpressionSyntax Extends TExpressionSyntax
	Field dotToken:TSyntaxToken
End Type

Type TOmittedArgumentExpressionSyntax Extends TExpressionSyntax
End Type

Type TCastExpressionSyntax Extends TExpressionSyntax
	Field targetType:TTypeReferenceSyntax
	Field openToken:TSyntaxToken
	Field expression:TExpressionSyntax
	Field closeToken:TSyntaxToken
End Type

Type TRawExpressionSyntax Extends TExpressionSyntax
	Field tokens:TSyntaxToken[]
End Type

Rem
bbdoc: Contains parsed BlitzMax source, its root syntax node, and parse diagnostics.
End Rem
Type TSyntaxTree
	Field source:TSourceText
	Field root:TCompilationUnitSyntax
	Field diagnostics:TDiagnostic[]
End Type

Rem
bbdoc: Contains the result of parsing BlitzMax source text.
End Rem
Type TParseResult
	Field syntaxTree:TSyntaxTree
End Type
