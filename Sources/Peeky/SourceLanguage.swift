import Foundation

enum SourceLanguage: Equatable {
    case python
    case shell
    case javascript
    case typescript
    case jsx
    case tsx
    case swift
    case go
    case rust
    case java
    case kotlin
    case c
    case cpp
    case objectiveC
    case csharp
    case php
    case ruby
    case perl
    case lua
    case r
    case sql
    case html
    case css
    case scss
    case dart
    case scala
    case elixir
    case haskell
    case dockerfile
    case makefile

    var displayName: String {
        switch self {
        case .python: "Python"
        case .shell: "Shell"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .jsx: "JSX"
        case .tsx: "TSX"
        case .swift: "Swift"
        case .go: "Go"
        case .rust: "Rust"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .c: "C"
        case .cpp: "C++"
        case .objectiveC: "Objective-C"
        case .csharp: "C#"
        case .php: "PHP"
        case .ruby: "Ruby"
        case .perl: "Perl"
        case .lua: "Lua"
        case .r: "R"
        case .sql: "SQL"
        case .html: "HTML"
        case .css: "CSS"
        case .scss: "SCSS"
        case .dart: "Dart"
        case .scala: "Scala"
        case .elixir: "Elixir"
        case .haskell: "Haskell"
        case .dockerfile: "Dockerfile"
        case .makefile: "Makefile"
        }
    }

    static func detect(url: URL, text: String) -> SourceLanguage? {
        let fileName = url.lastPathComponent.lowercased()

        switch fileName {
        case "dockerfile", "containerfile":
            return .dockerfile
        case "makefile", "gnumakefile":
            return .makefile
        case "gemfile", "rakefile", "podfile", "fastfile", "appfile":
            return .ruby
        default:
            break
        }

        switch url.pathExtension.lowercased() {
        case "py", "pyw", "pyi":
            return .python
        case "sh", "bash", "zsh", "fish", "ksh", "command":
            return .shell
        case "js", "mjs", "cjs":
            return .javascript
        case "ts", "mts", "cts":
            return .typescript
        case "jsx":
            return .jsx
        case "tsx":
            return .tsx
        case "swift":
            return .swift
        case "go":
            return .go
        case "rs":
            return .rust
        case "java":
            return .java
        case "kt", "kts":
            return .kotlin
        case "c":
            return .c
        case "h", "hpp", "hh", "hxx", "cc", "cpp", "cxx":
            return .cpp
        case "m", "mm":
            return .objectiveC
        case "cs":
            return .csharp
        case "php", "phtml":
            return .php
        case "rb", "rake":
            return .ruby
        case "pl", "pm", "t":
            return .perl
        case "lua":
            return .lua
        case "r":
            return .r
        case "sql":
            return .sql
        case "html", "htm":
            return .html
        case "css":
            return .css
        case "scss", "sass", "less":
            return .scss
        case "dart":
            return .dart
        case "scala", "sc":
            return .scala
        case "ex", "exs":
            return .elixir
        case "hs", "lhs":
            return .haskell
        default:
            break
        }

        return detectShebang(text)
    }

    private static func detectShebang(_ text: String) -> SourceLanguage? {
        guard text.hasPrefix("#!") else { return nil }
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .lowercased() ?? ""

        if firstLine.contains("python") {
            return .python
        }
        if firstLine.contains("bash")
            || firstLine.contains("zsh")
            || firstLine.contains("fish")
            || firstLine.contains("/sh")
            || firstLine.contains("env sh") {
            return .shell
        }
        if firstLine.contains("node") || firstLine.contains("deno") || firstLine.contains("bun") {
            return .javascript
        }
        if firstLine.contains("ruby") {
            return .ruby
        }
        if firstLine.contains("perl") {
            return .perl
        }
        if firstLine.contains("php") {
            return .php
        }
        if firstLine.contains("lua") {
            return .lua
        }
        if firstLine.contains("rscript") {
            return .r
        }

        return nil
    }
}
