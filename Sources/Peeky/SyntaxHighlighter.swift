import AppKit
import Foundation

enum SyntaxHighlighter {
    private static let highlightLimit = 1_500_000

    static func canHighlight(_ text: String) -> Bool {
        text.utf16.count <= highlightLimit
    }

    static func monospace(_ text: String) -> NSAttributedString {
        NSMutableAttributedString(string: text, attributes: baseMonospaceAttributes())
    }

    static func highlightJSON(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseMonospaceAttributes())
        guard canHighlight(text) else {
            return attributed
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let stringRanges = applyStringHighlighting(to: attributed, nsText: nsText, fullRange: fullRange)

        applyRegex(
            pattern: #"(?<![\w.])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemPurple,
            excludedRanges: stringRanges
        )
        applyRegex(
            pattern: #"\b(?:true|false)\b"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemOrange,
            excludedRanges: stringRanges
        )
        applyRegex(
            pattern: #"\bnull\b"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .secondaryLabelColor,
            excludedRanges: stringRanges
        )
        applyRegex(
            pattern: #"[{}\[\],:]"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .tertiaryLabelColor,
            excludedRanges: []
        )

        return attributed
    }

    static func highlightXML(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseMonospaceAttributes())
        guard canHighlight(text) else {
            return attributed
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        applyRegex(
            pattern: #"<!--[\s\S]*?-->"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .secondaryLabelColor,
            excludedRanges: []
        )
        applyRegex(
            pattern: #"</?[\w:.-]+"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemBlue,
            excludedRanges: []
        )
        applyRegex(
            pattern: #"[\w:.-]+(?=\=)"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemPurple,
            excludedRanges: []
        )
        applyRegex(
            pattern: #""(?:\\.|[^"\\])*""#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemGreen,
            excludedRanges: []
        )
        applyRegex(
            pattern: #"[<>/=]"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .tertiaryLabelColor,
            excludedRanges: []
        )

        return attributed
    }

    static func highlightSource(_ text: String, language: SourceLanguage) -> NSAttributedString {
        if language == .html {
            return highlightXML(text)
        }

        let attributed = NSMutableAttributedString(string: text, attributes: baseMonospaceAttributes())
        guard canHighlight(text) else {
            return attributed
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let stringRanges = applySourceStringHighlighting(
            to: attributed,
            language: language,
            nsText: nsText,
            fullRange: fullRange
        )
        let commentRanges = applySourceCommentHighlighting(
            to: attributed,
            language: language,
            nsText: nsText,
            fullRange: fullRange,
            excludedRanges: stringRanges
        )
        let protectedRanges = stringRanges + commentRanges

        applySourceSpecificHighlighting(
            language,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            protectedRanges: protectedRanges
        )
        applyKeywordGroup(
            sourceKeywords(for: language),
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            caseInsensitive: usesCaseInsensitiveKeywords(language),
            color: .systemPink,
            excludedRanges: protectedRanges
        )
        applyKeywordGroup(
            sourceTypeKeywords(for: language),
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            caseInsensitive: usesCaseInsensitiveKeywords(language),
            color: .systemTeal,
            excludedRanges: protectedRanges
        )
        applyKeywordGroup(
            sourceConstants(for: language),
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            caseInsensitive: usesCaseInsensitiveKeywords(language),
            color: .systemOrange,
            excludedRanges: protectedRanges
        )
        applyRegex(
            pattern: #"(?<![\w.])-?(?:0x[0-9A-Fa-f]+|0b[01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemPurple,
            excludedRanges: protectedRanges
        )
        for pattern in sourceDeclarationPatterns(for: language) {
            applyRegexCaptures(
                pattern: pattern,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                captureGroups: [1],
                color: .systemBlue,
                excludedRanges: protectedRanges
            )
        }
        applyRegex(
            pattern: #"[{}()[\],.;:]"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .tertiaryLabelColor,
            excludedRanges: protectedRanges
        )

        return attributed
    }

    private static func applySourceStringHighlighting(
        to attributed: NSMutableAttributedString,
        language: SourceLanguage,
        nsText: NSString,
        fullRange: NSRange
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        for pattern in sourceStringPatterns(for: language) {
            ranges += applyRegex(
                pattern: pattern,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemGreen,
                excludedRanges: ranges
            )
        }
        return ranges
    }

    private static func applySourceCommentHighlighting(
        to attributed: NSMutableAttributedString,
        language: SourceLanguage,
        nsText: NSString,
        fullRange: NSRange,
        excludedRanges: [NSRange]
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        for pattern in sourceCommentPatterns(for: language) {
            ranges += applyRegex(
                pattern: pattern,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .secondaryLabelColor,
                excludedRanges: excludedRanges + ranges
            )
        }
        return ranges
    }

    private static func applySourceSpecificHighlighting(
        _ language: SourceLanguage,
        to attributed: NSMutableAttributedString,
        nsText: NSString,
        fullRange: NSRange,
        protectedRanges: [NSRange]
    ) {
        if [.python, .java, .kotlin, .scala, .typescript, .tsx].contains(language) {
            applyRegex(
                pattern: #"(?m)^\s*@[\w.]+(?:\([^)]*\))?"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemPurple,
                excludedRanges: protectedRanges
            )
        }

        if [.shell, .makefile].contains(language) {
            applyRegex(
                pattern: #"\$(?:\{[^}\s]+\}|[A-Za-z_][A-Za-z0-9_]*|[0-9?#$!@*-])"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemPurple,
                excludedRanges: protectedRanges
            )
        }

        if [.c, .cpp, .objectiveC].contains(language) {
            applyRegex(
                pattern: #"(?m)^\s*#\s*[A-Za-z_]\w*.*$"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemPurple,
                excludedRanges: protectedRanges
            )
        }

        if [.css, .scss].contains(language) {
            applyRegexCaptures(
                pattern: #"(?m)(?:^|[{};])\s*([-A-Za-z]+)\s*(?=:)"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                captureGroups: [1],
                color: .systemBlue,
                excludedRanges: protectedRanges
            )
            applyRegex(
                pattern: #"#[0-9A-Fa-f]{3,8}\b"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemPurple,
                excludedRanges: protectedRanges
            )
            applyRegex(
                pattern: #"@[A-Za-z-]+"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemPink,
                excludedRanges: protectedRanges
            )
        }

        if [.jsx, .tsx].contains(language) {
            applyRegex(
                pattern: #"</?[A-Za-z][\w.:-]*"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemBlue,
                excludedRanges: protectedRanges
            )
        }

        if language == .dockerfile {
            applyRegex(
                pattern: #"(?m)^\s*[A-Z][A-Z0-9_]*\b"#,
                to: attributed,
                nsText: nsText,
                fullRange: fullRange,
                color: .systemPink,
                excludedRanges: protectedRanges
            )
        }
    }

    private static func sourceStringPatterns(for language: SourceLanguage) -> [String] {
        var patterns: [String] = []

        switch language {
        case .python, .swift:
            patterns.append("\"\"\"[\\s\\S]*?\"\"\"")
        default:
            break
        }

        switch language {
        case .python:
            patterns.append("'''[\\s\\S]*?'''")
        default:
            break
        }

        switch language {
        case .sql:
            patterns += [
                #"'(?:''|[^'])*'"#,
                #""(?:""|[^"])*""#
            ]
        default:
            patterns += [
                #""(?:\\.|[^"\\])*""#,
                #"'(?:\\.|[^'\\])*'"#
            ]
        }

        switch language {
        case .javascript, .typescript, .jsx, .tsx, .shell, .go:
            patterns.append(#"`(?:\\.|[^`\\])*`"#)
        default:
            break
        }

        return patterns
    }

    private static func sourceCommentPatterns(for language: SourceLanguage) -> [String] {
        switch language {
        case .python, .shell, .ruby, .perl, .r, .dockerfile, .makefile:
            return [#"(?m)#.*$"#]
        case .lua:
            return [
                #"--\[\[[\s\S]*?\]\]"#,
                #"(?m)--.*$"#
            ]
        case .sql:
            return [
                #"/\*[\s\S]*?\*/"#,
                #"(?m)--.*$"#
            ]
        case .css:
            return [#"/\*[\s\S]*?\*/"#]
        case .scss:
            return [
                #"/\*[\s\S]*?\*/"#,
                #"(?m)//.*$"#
            ]
        case .php:
            return [
                #"/\*[\s\S]*?\*/"#,
                #"(?m)//.*$"#,
                #"(?m)#.*$"#
            ]
        case .haskell:
            return [
                #"\{-[\s\S]*?-\}"#,
                #"(?m)--.*$"#
            ]
        default:
            return [
                #"/\*[\s\S]*?\*/"#,
                #"(?m)//.*$"#
            ]
        }
    }

    private static func sourceKeywords(for language: SourceLanguage) -> [String] {
        switch language {
        case .python:
            return ["and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "match", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"]
        case .shell:
            return ["case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "select", "then", "until", "while"]
        case .javascript, .jsx:
            return ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "finally", "for", "from", "function", "get", "if", "import", "in", "instanceof", "let", "new", "of", "return", "set", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield"]
        case .typescript, .tsx:
            return ["abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "is", "keyof", "let", "module", "namespace", "new", "of", "private", "protected", "public", "readonly", "return", "satisfies", "set", "static", "super", "switch", "this", "throw", "try", "type", "typeof", "var", "void", "while", "with", "yield"]
        case .swift:
            return ["actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "for", "func", "guard", "if", "import", "in", "init", "inout", "is", "let", "mutating", "nonisolated", "operator", "private", "protocol", "public", "repeat", "return", "self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "try", "typealias", "var", "where", "while"]
        case .go:
            return ["break", "case", "chan", "const", "continue", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"]
        case .rust:
            return ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "static", "struct", "super", "trait", "type", "unsafe", "use", "where", "while"]
        case .java:
            return ["abstract", "assert", "break", "case", "catch", "class", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "volatile", "while"]
        case .kotlin:
            return ["as", "break", "by", "catch", "class", "companion", "constructor", "continue", "data", "do", "else", "enum", "finally", "for", "fun", "if", "import", "in", "interface", "internal", "is", "object", "open", "operator", "out", "override", "package", "private", "protected", "public", "return", "sealed", "super", "this", "throw", "try", "typealias", "val", "var", "when", "where", "while"]
        case .c, .cpp, .objectiveC:
            return ["asm", "auto", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else", "enum", "extern", "for", "friend", "goto", "if", "inline", "namespace", "new", "operator", "private", "protected", "public", "register", "return", "sizeof", "static", "struct", "switch", "template", "this", "throw", "try", "typedef", "union", "using", "virtual", "volatile", "while"]
        case .csharp:
            return ["abstract", "as", "async", "await", "base", "break", "case", "catch", "class", "const", "continue", "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "finally", "fixed", "for", "foreach", "get", "if", "implicit", "in", "interface", "internal", "is", "lock", "namespace", "new", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "ref", "return", "sealed", "set", "sizeof", "stackalloc", "static", "struct", "switch", "this", "throw", "try", "typeof", "unchecked", "unsafe", "using", "virtual", "volatile", "while", "yield"]
        case .php:
            return ["abstract", "and", "array", "as", "break", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "enum", "extends", "final", "finally", "fn", "for", "foreach", "function", "global", "if", "implements", "include", "include_once", "interface", "match", "namespace", "new", "or", "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch", "throw", "trait", "try", "use", "var", "while", "xor", "yield"]
        case .ruby:
            return ["alias", "and", "begin", "break", "case", "class", "def", "defined", "do", "else", "elsif", "end", "ensure", "for", "if", "in", "module", "next", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "undef", "unless", "until", "when", "while", "yield"]
        case .perl:
            return ["continue", "do", "else", "elsif", "foreach", "for", "given", "if", "last", "local", "my", "next", "our", "package", "redo", "require", "return", "state", "sub", "unless", "until", "use", "when", "while"]
        case .lua:
            return ["and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if", "in", "local", "not", "or", "repeat", "return", "then", "until", "while"]
        case .r:
            return ["break", "else", "for", "function", "if", "in", "next", "repeat", "return", "while"]
        case .sql:
            return ["alter", "and", "as", "begin", "between", "by", "case", "create", "delete", "distinct", "drop", "else", "end", "exists", "from", "group", "having", "in", "inner", "insert", "into", "is", "join", "left", "like", "limit", "not", "null", "on", "or", "order", "outer", "right", "select", "set", "then", "union", "update", "values", "when", "where", "with"]
        case .css, .scss:
            return ["and", "from", "important", "not", "only", "or", "to"]
        case .dart:
            return ["abstract", "as", "async", "await", "base", "break", "case", "catch", "class", "const", "continue", "covariant", "default", "deferred", "do", "else", "enum", "export", "extends", "extension", "external", "factory", "final", "finally", "for", "function", "get", "hide", "if", "implements", "import", "in", "interface", "is", "late", "library", "mixin", "new", "of", "on", "operator", "part", "required", "return", "sealed", "set", "show", "static", "super", "switch", "sync", "this", "throw", "try", "typedef", "var", "void", "when", "while", "with", "yield"]
        case .scala:
            return ["abstract", "case", "catch", "class", "def", "do", "else", "enum", "export", "extends", "final", "finally", "for", "given", "if", "implicit", "import", "lazy", "match", "new", "object", "override", "package", "private", "protected", "return", "sealed", "then", "throw", "trait", "try", "type", "val", "var", "while", "with", "yield"]
        case .elixir:
            return ["after", "alias", "and", "case", "catch", "cond", "def", "defmodule", "defp", "defprotocol", "defstruct", "defimpl", "do", "else", "end", "fn", "for", "if", "import", "in", "not", "or", "quote", "raise", "receive", "require", "rescue", "try", "unless", "use", "when", "with"]
        case .haskell:
            return ["case", "class", "data", "default", "deriving", "do", "else", "family", "forall", "foreign", "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "module", "newtype", "of", "then", "type", "where"]
        case .dockerfile:
            return ["add", "arg", "cmd", "copy", "entrypoint", "env", "expose", "from", "healthcheck", "label", "maintainer", "onbuild", "run", "shell", "stopsignal", "user", "volume", "workdir"]
        case .makefile:
            return ["define", "else", "endef", "endif", "export", "ifeq", "ifneq", "ifdef", "ifndef", "include", "override", "private", "undefine", "unexport", "vpath"]
        case .html:
            return []
        }
    }

    private static func sourceTypeKeywords(for language: SourceLanguage) -> [String] {
        switch language {
        case .python:
            return ["Any", "bool", "bytes", "dict", "float", "frozenset", "int", "list", "object", "set", "str", "tuple"]
        case .javascript, .jsx:
            return ["Array", "BigInt", "Boolean", "Date", "Error", "Map", "Number", "Object", "Promise", "RegExp", "Set", "String", "Symbol", "WeakMap", "WeakSet"]
        case .typescript, .tsx:
            return ["Array", "Record", "Promise", "Map", "Set", "WeakMap", "WeakSet", "any", "bigint", "boolean", "never", "number", "object", "string", "symbol", "unknown"]
        case .swift:
            return ["Any", "Array", "Bool", "Character", "Dictionary", "Double", "Float", "Int", "Never", "Optional", "Result", "Set", "String", "UInt", "Void"]
        case .go:
            return ["any", "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"]
        case .rust:
            return ["Self", "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8", "u16", "u32", "u64", "u128", "usize"]
        case .java, .kotlin, .c, .cpp, .objectiveC, .csharp, .dart, .scala:
            return ["bool", "boolean", "byte", "char", "double", "float", "int", "long", "short", "string", "String", "void", "Void"]
        case .php:
            return ["array", "bool", "callable", "float", "int", "iterable", "mixed", "object", "string", "void"]
        case .r:
            return ["data.frame", "double", "factor", "integer", "list", "logical", "matrix", "numeric", "tibble", "vector"]
        case .sql:
            return ["bigint", "boolean", "char", "date", "decimal", "double", "float", "int", "integer", "numeric", "real", "text", "timestamp", "varchar"]
        default:
            return []
        }
    }

    private static func sourceConstants(for language: SourceLanguage) -> [String] {
        switch language {
        case .python:
            return ["False", "None", "True"]
        case .shell, .makefile:
            return ["false", "true"]
        case .javascript, .typescript, .jsx, .tsx:
            return ["false", "null", "true", "undefined"]
        case .swift:
            return ["false", "nil", "true"]
        case .go:
            return ["false", "iota", "nil", "true"]
        case .rust:
            return ["false", "true"]
        case .java, .kotlin, .csharp, .dart, .scala:
            return ["false", "null", "true"]
        case .c, .cpp, .objectiveC:
            return ["NULL", "false", "nullptr", "true"]
        case .php:
            return ["FALSE", "NULL", "TRUE", "false", "null", "true"]
        case .ruby:
            return ["false", "nil", "true"]
        case .perl:
            return ["undef"]
        case .lua:
            return ["false", "nil", "true"]
        case .r:
            return ["FALSE", "NA", "NULL", "TRUE"]
        case .sql:
            return ["false", "null", "true"]
        case .elixir:
            return ["false", "nil", "true"]
        case .haskell:
            return ["False", "Nothing", "True"]
        default:
            return []
        }
    }

    private static func sourceDeclarationPatterns(for language: SourceLanguage) -> [String] {
        switch language {
        case .python:
            return [#"\b(?:def|class)\s+([A-Za-z_]\w*)"#]
        case .shell:
            return [
                #"\bfunction\s+([A-Za-z_][\w-]*)"#,
                #"(?m)^\s*([A-Za-z_][\w-]*)\s*\(\s*\)"#
            ]
        case .javascript, .jsx:
            return [
                #"\b(?:function|class)\s+([A-Za-z_$][\w$]*)"#,
                #"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>"#
            ]
        case .typescript, .tsx:
            return [
                #"\b(?:function|class|interface|type|enum)\s+([A-Za-z_$][\w$]*)"#,
                #"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>"#
            ]
        case .swift:
            return [#"\b(?:func|class|struct|enum|protocol|actor|extension)\s+([A-Za-z_]\w*)"#]
        case .go:
            return [
                #"\bfunc\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)"#,
                #"\btype\s+([A-Za-z_]\w*)\s+(?:struct|interface)"#
            ]
        case .rust:
            return [#"\b(?:fn|struct|enum|trait|impl|mod)\s+([A-Za-z_]\w*)"#]
        case .java, .kotlin, .csharp, .dart, .scala:
            return [#"\b(?:class|interface|enum|record|struct|trait|object)\s+([A-Za-z_]\w*)"#]
        case .c, .cpp, .objectiveC:
            return [#"\b(?:class|struct|enum|typedef\s+struct)\s+([A-Za-z_]\w*)"#]
        case .php:
            return [#"\b(?:function|class|interface|trait|enum)\s+([A-Za-z_]\w*)"#]
        case .ruby:
            return [#"\b(?:def|class|module)\s+([A-Za-z_]\w*[!?=]?)"#]
        case .perl:
            return [#"\bsub\s+([A-Za-z_]\w*)"#]
        case .lua:
            return [#"\bfunction\s+([A-Za-z_][\w.:]*)"#]
        case .r:
            return [#"(?m)^\s*([A-Za-z_.]\w*)\s*<-\s*function\b"#]
        case .elixir:
            return [#"\b(?:defmodule|def|defp|defprotocol|defimpl)\s+([A-Za-z_][\w.!?]*)"#]
        case .haskell:
            return [#"(?m)^([A-Za-z_]\w*)\s*(?:::|=)"#]
        default:
            return []
        }
    }

    private static func applyKeywordGroup(
        _ keywords: [String],
        to attributed: NSMutableAttributedString,
        nsText: NSString,
        fullRange: NSRange,
        caseInsensitive: Bool = false,
        color: NSColor,
        excludedRanges: [NSRange]
    ) {
        guard !keywords.isEmpty else { return }
        let joined = keywords
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?<![\\w$])(?:\(joined))(?![\\w$])"
        applyRegex(
            pattern: pattern,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            options: caseInsensitive ? .caseInsensitive : [],
            color: color,
            excludedRanges: excludedRanges
        )
    }

    private static func usesCaseInsensitiveKeywords(_ language: SourceLanguage) -> Bool {
        switch language {
        case .sql, .dockerfile:
            true
        default:
            false
        }
    }

    private static func baseMonospaceAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2

        return [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func applyStringHighlighting(
        to attributed: NSMutableAttributedString,
        nsText: NSString,
        fullRange: NSRange
    ) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#) else {
            return []
        }

        let matches = regex.matches(in: nsText as String, range: fullRange)
        var stringRanges: [NSRange] = []

        for match in matches {
            stringRanges.append(match.range)
            let color: NSColor = isObjectKey(match.range, in: nsText) ? .systemBlue : .systemGreen
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }

        return stringRanges
    }

    private static func isObjectKey(_ range: NSRange, in text: NSString) -> Bool {
        var index = NSMaxRange(range)
        while index < text.length {
            let character = text.character(at: index)
            if character == 32 || character == 9 || character == 10 || character == 13 {
                index += 1
                continue
            }
            return character == 58
        }
        return false
    }

    @discardableResult
    private static func applyRegex(
        pattern: String,
        to attributed: NSMutableAttributedString,
        nsText: NSString,
        fullRange: NSRange,
        options: NSRegularExpression.Options = [],
        color: NSColor,
        excludedRanges: [NSRange]
    ) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let matches = regex.matches(in: nsText as String, range: fullRange)
        var appliedRanges: [NSRange] = []

        for match in matches where !intersects(match.range, excludedRanges) {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
            appliedRanges.append(match.range)
        }

        return appliedRanges
    }

    private static func applyRegexCaptures(
        pattern: String,
        to attributed: NSMutableAttributedString,
        nsText: NSString,
        fullRange: NSRange,
        options: NSRegularExpression.Options = [],
        captureGroups: [Int],
        color: NSColor,
        excludedRanges: [NSRange]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let matches = regex.matches(in: nsText as String, range: fullRange)

        for match in matches {
            for captureGroup in captureGroups where captureGroup < match.numberOfRanges {
                let range = match.range(at: captureGroup)
                guard range.location != NSNotFound,
                      !intersects(range, excludedRanges) else {
                    continue
                }
                attributed.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
    }

    private static func intersects(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
