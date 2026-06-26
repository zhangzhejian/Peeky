# Peeky

Peeky is a native macOS read-only preview app for developer-facing text formats. It is intentionally small: AppKit, `NSTextView`, no WebView, no editor surface.

## Features

- Fast text loading with an 80 MB preview cap for very large files.
- Markdown preview with native attributed text rendering for headings, tables, lists, quotes, links, code, and a clickable heading outline.
- JSON, JSONL, XML, and plist formatting with lightweight syntax highlighting.
- Raw/format toggle, line wrap toggle, copy, reveal in Finder, and multi-file tabs.
- Finder document type registration when packaged as an app bundle.

## Run

```sh
swift run Peeky
swift run Peeky path/to/file.json
swift run Peeky path/to/file.json path/to/notes.md
swift run Peeky path/to/file.jsonl:12
```

## Build the app bundle

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open .build/Peeky.app
```

The generated app bundle is written to `.build/Peeky.app`.

## URL links

The app bundle registers a `peeky://` URL scheme:

```sh
open 'peeky://open?path=/absolute/path/to/file.jsonl&line=12'
```

Terminal tools can use OSC 8 hyperlinks so Ghostty shows normal `path:line`
text while opening Peeky on click:

```sh
file="$PWD/path/to/file.jsonl"
line=12
label="path/to/file.jsonl:$line"
encoded_path="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$file")"
printf '\e]8;;peeky://open?path=%s&line=%s\a%s\e]8;;\a\n' "$encoded_path" "$line" "$label"
```
