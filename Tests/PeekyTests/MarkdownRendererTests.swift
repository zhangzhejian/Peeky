import AppKit
import XCTest
@testable import Peeky

final class MarkdownRendererTests: XCTestCase {
    func testInlineStylesAndHeadingOutline() {
        let result = MarkdownRenderer.renderWithOutline("# Hello **world**\n\n*italic* ~~removed~~ `**literal**` [link](https://example.com)")
        XCTAssertEqual(result.outline.first?.title, "Hello world")
        XCTAssertEqual(result.outline.first?.renderedLocation, 0)
        XCTAssertTrue(result.attributedText.string.contains("italic removed **literal** link"))
        let text = result.attributedText.string as NSString
        let italic = result.attributedText.attribute(.font, at: text.range(of: "italic").location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        XCTAssertNotNil(result.attributedText.attribute(.strikethroughStyle, at: text.range(of: "removed").location, effectiveRange: nil))
        XCTAssertNotNil(result.attributedText.attribute(.link, at: text.range(of: "link").location, effectiveRange: nil))
    }

    func testFenceMatchingAndOutlineLocations() {
        let source = "````swift\n# hidden\n```\n~~~\n````\n# Visible 😀"
        let result = MarkdownRenderer.renderWithOutline(source)
        XCTAssertEqual(result.outline.count, 1)
        XCTAssertEqual(result.outline.first?.sourceLine, 6)
        XCTAssertEqual(MarkdownRenderer.outline(in: source).map(\.title), result.outline.map(\.title))
        let location = result.outline[0].renderedLocation!
        XCTAssertTrue((result.attributedText.string as NSString).substring(from: location).hasPrefix("Visible 😀"))
        XCTAssertTrue(result.attributedText.string.contains("```"))
        XCTAssertTrue(result.attributedText.string.contains("~~~"))
    }

    func testUnclosedFencePreservesCode() {
        let result = MarkdownRenderer.renderWithOutline("~~~\n**literal**\n# code")
        XCTAssertTrue(result.outline.isEmpty)
        XCTAssertTrue(result.attributedText.string.contains("**literal**"))
    }

    func testTasksNestedListsAndThematicBreak() {
        let result = MarkdownRenderer.render("- [ ] Todo\n  - [x] Done\n---\n1. First")
        XCTAssertTrue(result.string.contains("☐\tTodo"))
        XCTAssertTrue(result.string.contains("☑\tDone"))
        XCTAssertFalse(result.string.contains("---"))
        let nested = (result.string as NSString).range(of: "Done").location
        let style = result.attribute(.paragraphStyle, at: nested, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertGreaterThan(style.firstLineHeadIndent, 0)
        XCTAssertGreaterThan(style.headIndent, style.firstLineHeadIndent)
    }

    func testParagraphSoftAndHardBreaks() {
        XCTAssertEqual(MarkdownRenderer.render("one\ntwo\n\nthree").string, "one two\nthree\n")
        XCTAssertTrue(MarkdownRenderer.render("one  \ntwo").string.contains("one\u{2028}two"))
    }

    func testTablesRetainAlignmentAndInlineFormatting() {
        let text = MarkdownRenderer.render("| Name | Count |\n| --- | ---: |\n| **A** | 2 |")
        let location = (text.string as NSString).range(of: "2").location
        let style = text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(style.alignment, .right)
        XCTAssertTrue(style.textBlocks.first is NSTextTableBlock)
        XCTAssertFalse(text.string.contains("**"))
    }

    @MainActor
    func testNativeLayoutAndCapture() throws {
        _ = NSApplication.shared
        let source = try String(contentsOf: Bundle.module.url(forResource: "markdown-showcase", withExtension: "md", subdirectory: "Fixtures")!, encoding: .utf8)
        let rendered = MarkdownRenderer.render(source)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 1100))
            view.appearance = NSAppearance(named: appearance)
            view.textContainerInset = NSSize(width: 48, height: 28)
            view.textContainer?.containerSize = NSSize(width: 804, height: 1100)
            view.textStorage?.setAttributedString(rendered)
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            let used = view.layoutManager!.usedRect(for: view.textContainer!)
            XCTAssertGreaterThan(used.height, 400)
            XCTAssertLessThan(used.width, 850)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/peeky-markdown-\(name).png"))
        }
    }
}
