import AppKit
import Foundation

enum PreviewMode: Int {
    case formatted = 0
    case raw = 1
}

struct RenderedPreview {
    let attributedText: NSAttributedString
    let note: String?
    let outline: [MarkdownOutlineItem]

    init(
        attributedText: NSAttributedString,
        note: String?,
        outline: [MarkdownOutlineItem] = []
    ) {
        self.attributedText = attributedText
        self.note = note
        self.outline = outline
    }
}

enum PreviewRenderer {
    private static let richFormatLimit = 8 * 1024 * 1024

    static func render(document: LoadedText, mode: PreviewMode) -> RenderedPreview {
        if mode == .raw || !document.kind.hasFormattedPreview {
            let raw = renderRaw(document)
            if document.kind == .markdown {
                return RenderedPreview(
                    attributedText: raw.attributedText,
                    note: raw.note,
                    outline: MarkdownRenderer.outline(in: document.text)
                )
            }
            return raw
        }

        if document.readBytes > richFormatLimit {
            let raw = renderRaw(document)
            let outline = document.kind == .markdown ? MarkdownRenderer.outline(in: document.text) : []
            return RenderedPreview(
                attributedText: raw.attributedText,
                note: "Raw preview for large file",
                outline: outline
            )
        }

        switch document.kind {
        case .markdown:
            let rendered = MarkdownRenderer.renderWithOutline(document.text)
            return RenderedPreview(
                attributedText: rendered.attributedText,
                note: nil,
                outline: rendered.outline
            )
        case .json:
            do {
                let pretty = try JSONFormatter.prettyJSON(document.text)
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightJSON(pretty),
                    note: "Formatted"
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightJSON(document.text),
                    note: "Invalid JSON"
                )
            }
        case .jsonl:
            let result = JSONFormatter.prettyJSONLines(document.text)
            return RenderedPreview(
                attributedText: SyntaxHighlighter.highlightJSON(result.text),
                note: result.invalidLineCount == 0 ? "Formatted" : "\(result.invalidLineCount) invalid line(s)"
            )
        case .xml:
            do {
                let pretty = try XMLFormatter.prettyXML(document.text)
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightXML(pretty),
                    note: "Formatted"
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightXML(document.text),
                    note: "Invalid XML"
                )
            }
        case .plist:
            do {
                let pretty = try XMLFormatter.prettyPropertyList(document.text)
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightXML(pretty),
                    note: "Formatted"
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.monospace(document.text),
                    note: "Invalid plist"
                )
            }
        case .source(let language):
            return RenderedPreview(
                attributedText: SyntaxHighlighter.highlightSource(document.text, language: language),
                note: SyntaxHighlighter.canHighlight(document.text) ? "Highlighted" : "Highlight skipped for large file"
            )
        case .yaml, .csv, .log, .text:
            return renderRaw(document)
        }
    }

    private static func renderRaw(_ document: LoadedText) -> RenderedPreview {
        switch document.kind {
        case .json, .jsonl:
            return RenderedPreview(attributedText: SyntaxHighlighter.highlightJSON(document.text), note: "Raw")
        case .xml, .plist:
            return RenderedPreview(attributedText: SyntaxHighlighter.highlightXML(document.text), note: "Raw")
        case .source:
            return RenderedPreview(attributedText: SyntaxHighlighter.monospace(document.text), note: "Raw")
        default:
            return RenderedPreview(attributedText: SyntaxHighlighter.monospace(document.text), note: "Raw")
        }
    }
}
