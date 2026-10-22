import AppKit
import Foundation

struct MarkdownOutlineItem {
    let level: Int
    let title: String
    let sourceLine: Int
    let renderedLocation: Int?
}

struct MarkdownRenderResult {
    let attributedText: NSAttributedString
    let outline: [MarkdownOutlineItem]
}

enum MarkdownRenderer {
    private enum TableAlignment {
        case left
        case center
        case right
    }

    private struct MarkdownTable {
        let rows: [[String]]
        let alignments: [TableAlignment]
        let endIndex: Int
    }

    static func render(_ text: String) -> NSAttributedString {
        renderWithOutline(text).attributedText
    }

    static func renderWithOutline(_ text: String) -> MarkdownRenderResult {
        let output = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)
        var outline: [MarkdownOutlineItem] = []
        var lineIndex = 0

        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if let opening = parseFence(rawLine) {
                var code: [String] = []
                lineIndex += 1
                while lineIndex < lines.count {
                    if closesFence(lines[lineIndex], opening: opening) {
                        lineIndex += 1
                        break
                    }
                    code.append(lines[lineIndex])
                    lineIndex += 1
                }
                appendBlock(code.joined(separator: "\n"), to: output, isCode: true)
                continue
            }

            if trimmed.isEmpty {
                lineIndex += 1
                continue
            }

            if let table = parseTable(in: lines, startingAt: lineIndex) {
                appendTable(table, to: output)
                lineIndex = table.endIndex
                continue
            }

            if let heading = parseHeading(rawLine) {
                outline.append(
                    MarkdownOutlineItem(
                        level: heading.level,
                        title: inlinePlainText(heading.text),
                        sourceLine: lineIndex + 1,
                        renderedLocation: output.length
                    )
                )
                appendInline(heading.text + "\n", to: output, attributes: headingAttributes(level: heading.level))
                lineIndex += 1
                continue
            }

            if let quote = parseBlockQuote(rawLine) {
                var quotes = [quote]
                lineIndex += 1
                while lineIndex < lines.count, let next = parseBlockQuote(lines[lineIndex]) {
                    quotes.append(next)
                    lineIndex += 1
                }
                appendBlock(quotes.joined(separator: "\n"), to: output, isCode: false)
                continue
            }

            if isThematicBreak(trimmed) {
                let paragraph = NSMutableParagraphStyle()
                let table = NSTextTable()
                table.numberOfColumns = 1
                table.setContentWidth(100, type: .percentageValueType)
                let block = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
                block.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
                block.setBorderColor(blockBorderColor)
                paragraph.textBlocks = [block]
                paragraph.paragraphSpacing = 16
                append("\n", to: output, attributes: [.paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: 2)])
                lineIndex += 1
                continue
            }

            if let bullet = parseBullet(rawLine) {
                let attributes = listAttributes(indent: indentation(rawLine))
                let isTask = bullet.hasPrefix("[ ] ") || bullet.lowercased().hasPrefix("[x] ")
                let marker = isTask ? (bullet.hasPrefix("[ ] ") ? "☐" : "☑") : "•"
                append(marker + "\t", to: output, attributes: attributes)
                appendInline((isTask ? String(bullet.dropFirst(4)) : bullet) + "\n", to: output, attributes: attributes)
                lineIndex += 1
                continue
            }

            if let numbered = parseNumberedItem(rawLine) {
                let attributes = listAttributes(indent: indentation(rawLine))
                append(numbered.prefix.trimmingCharacters(in: .whitespaces) + "\t", to: output, attributes: attributes)
                appendInline(numbered.text + "\n", to: output, attributes: attributes)
                lineIndex += 1
                continue
            }

            var paragraph = rawLine
            lineIndex += 1
            while lineIndex < lines.count {
                let next = lines[lineIndex]
                if next.trimmingCharacters(in: .whitespaces).isEmpty || parseFence(next) != nil
                    || parseHeading(next) != nil || parseBlockQuote(next) != nil
                    || parseBullet(next) != nil || parseNumberedItem(next) != nil
                    || isThematicBreak(next) || parseTable(in: lines, startingAt: lineIndex) != nil {
                    break
                }
                if paragraph.hasSuffix("  ") {
                    paragraph = String(paragraph.dropLast(2)) + "\u{2028}" + next
                } else {
                    paragraph += " " + next
                }
                lineIndex += 1
            }
            appendInline(paragraph + "\n", to: output, attributes: bodyAttributes())
        }

        return MarkdownRenderResult(attributedText: output, outline: outline)
    }

    static func outline(in text: String) -> [MarkdownOutlineItem] {
        let lines = text.components(separatedBy: .newlines)
        var outline: [MarkdownOutlineItem] = []
        var fence: (marker: Character, count: Int)?

        for (lineIndex, rawLine) in lines.enumerated() {
            if let opening = fence {
                if closesFence(rawLine, opening: opening) { fence = nil }
                continue
            }
            if let opening = parseFence(rawLine) {
                fence = opening
                continue
            }

            if let heading = parseHeading(rawLine) {
                outline.append(
                    MarkdownOutlineItem(
                        level: heading.level,
                        title: inlinePlainText(heading.text),
                        sourceLine: lineIndex + 1,
                        renderedLocation: nil
                    )
                )
            }
        }

        return outline
    }

    private static func parseFence(_ line: String) -> (marker: Character, count: Int)? {
        let trimmed = line.drop(while: { $0 == " " })
        guard line.count - trimmed.count <= 3,
              let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        if marker == "`", trimmed.dropFirst(count).contains("`") { return nil }
        return (marker, count)
    }

    private static func closesFence(_ line: String, opening: (marker: Character, count: Int)) -> Bool {
        guard let candidate = parseFence(line), candidate.marker == opening.marker,
              candidate.count >= opening.count else { return false }
        return line.trimmingCharacters(in: .whitespaces).dropFirst(candidate.count)
            .trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func indentation(_ line: String) -> CGFloat {
        CGFloat(line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }) * 8
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first, "*-_".contains(marker) else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func appendBlock(_ text: String, to output: NSMutableAttributedString, isCode: Bool) {
        let table = NSTextTable()
        table.numberOfColumns = 1
        table.setContentWidth(100, type: .percentageValueType)
        let block = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
        block.setWidth(16, type: .absoluteValueType, for: .padding)
        if isCode {
            block.backgroundColor = blockBackgroundColor
        } else {
            block.setWidth(4, type: .absoluteValueType, for: .border, edge: .minX)
            block.setBorderColor(blockBorderColor)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [block]
        paragraph.lineSpacing = 4
        var attributes: [NSAttributedString.Key: Any] = [
            .font: isCode ? NSFont.monospacedSystemFont(ofSize: 13.6, weight: .regular) : bodyFont(),
            .foregroundColor: isCode ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        // Line separators keep the entire block in one padded table cell.
        let content = text.replacingOccurrences(of: "\n", with: "\u{2028}") + "\n"
        if isCode { append(content, to: output, attributes: attributes) }
        else { appendInline(content, to: output, attributes: attributes) }
        attributes = bodyAttributes()
        attributes[.font] = NSFont.systemFont(ofSize: 2)
        append("\n", to: output, attributes: attributes)
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex

        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }

        guard level > 0, index < line.endIndex, line[index].isWhitespace else {
            return nil
        }

        let textStart = line.index(after: index)
        return (level, String(line[textStart...]).trimmingCharacters(in: .whitespaces))
    }

    private static func parseBlockQuote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func parseBullet(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    private static func parseNumberedItem(_ line: String) -> (prefix: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let number = trimmed[..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let afterDot = trimmed.index(after: dot)
        guard afterDot < trimmed.endIndex, trimmed[afterDot].isWhitespace else { return nil }

        let textStart = trimmed.index(after: afterDot)
        return ("\(number). ", String(trimmed[textStart...]))
    }

    private static func parseTable(in lines: [String], startingAt startIndex: Int) -> MarkdownTable? {
        guard startIndex + 1 < lines.count else { return nil }

        let headerLine = lines[startIndex]
        let separatorLine = lines[startIndex + 1]
        guard containsTablePipe(headerLine) || containsTablePipe(separatorLine) else { return nil }

        let header = splitTableRow(headerLine)
        guard let alignments = parseTableSeparator(separatorLine),
              !header.isEmpty,
              header.count == alignments.count else {
            return nil
        }

        var rows = [normalizeTableRow(header, columnCount: alignments.count)]
        var lineIndex = startIndex + 2

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  containsTablePipe(line) else {
                break
            }

            let cells = splitTableRow(line)
            guard !cells.isEmpty else { break }

            rows.append(normalizeTableRow(cells, columnCount: alignments.count))
            lineIndex += 1
        }

        return MarkdownTable(rows: rows, alignments: alignments, endIndex: lineIndex)
    }

    private static func parseTableSeparator(_ line: String) -> [TableAlignment]? {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }

        var alignments: [TableAlignment] = []
        for cell in cells {
            let marker = cell.filter { !$0.isWhitespace }
            let startsWithColon = marker.first == ":"
            let endsWithColon = marker.last == ":"
            var hyphenMarker = marker
            if startsWithColon {
                hyphenMarker.removeFirst()
            }
            if endsWithColon {
                hyphenMarker.removeLast()
            }

            guard hyphenMarker.count >= 3,
                  hyphenMarker.allSatisfy({ $0 == "-" }) else {
                return nil
            }

            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }

        return alignments
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var isEscaping = false
        var activeBacktickCount = 0
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if isEscaping {
                current.append(character)
                isEscaping = false
                index = line.index(after: index)
                continue
            }

            if character == "\\", activeBacktickCount == 0 {
                isEscaping = true
                index = line.index(after: index)
                continue
            }

            if character == "`" {
                let tickCount = consecutiveBacktickCount(in: line, startingAt: index)
                if activeBacktickCount == 0 {
                    activeBacktickCount = tickCount
                } else if activeBacktickCount == tickCount {
                    activeBacktickCount = 0
                }

                current.append(String(repeating: "`", count: tickCount))
                index = line.index(index, offsetBy: tickCount)
                continue
            }

            if character == "|", activeBacktickCount == 0 {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }

            index = line.index(after: index)
        }

        if isEscaping {
            current.append("\\")
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))

        if startsWithTableDelimiter(line), cells.first == "" {
            cells.removeFirst()
        }
        if endsWithTableDelimiter(line), cells.last == "" {
            cells.removeLast()
        }

        return cells
    }

    private static func normalizeTableRow(_ cells: [String], columnCount: Int) -> [String] {
        var normalized = Array(cells.prefix(columnCount))
        if normalized.count < columnCount {
            normalized.append(contentsOf: Array(repeating: "", count: columnCount - normalized.count))
        }
        return normalized
    }

    private static func containsTablePipe(_ line: String) -> Bool {
        var isEscaping = false
        var activeBacktickCount = 0
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if isEscaping {
                isEscaping = false
                index = line.index(after: index)
                continue
            }

            if character == "\\", activeBacktickCount == 0 {
                isEscaping = true
                index = line.index(after: index)
                continue
            }

            if character == "`" {
                let tickCount = consecutiveBacktickCount(in: line, startingAt: index)
                if activeBacktickCount == 0 {
                    activeBacktickCount = tickCount
                } else if activeBacktickCount == tickCount {
                    activeBacktickCount = 0
                }
                index = line.index(index, offsetBy: tickCount)
                continue
            }

            if character == "|", activeBacktickCount == 0 {
                return true
            }

            index = line.index(after: index)
        }

        return false
    }

    private static func startsWithTableDelimiter(_ line: String) -> Bool {
        guard let firstNonWhitespace = line.firstIndex(where: { !$0.isWhitespace }) else {
            return false
        }
        return line[firstNonWhitespace] == "|"
    }

    private static func endsWithTableDelimiter(_ line: String) -> Bool {
        guard let lastNonWhitespace = line.lastIndex(where: { !$0.isWhitespace }) else {
            return false
        }
        return line[lastNonWhitespace] == "|"
    }

    private static func consecutiveBacktickCount(in line: String, startingAt startIndex: String.Index) -> Int {
        var count = 0
        var index = startIndex
        while index < line.endIndex, line[index] == "`" {
            count += 1
            index = line.index(after: index)
        }
        return count
    }

    private static func appendTable(_ table: MarkdownTable, to output: NSMutableAttributedString) {
        let textTable = NSTextTable()
        textTable.numberOfColumns = table.alignments.count
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.setContentWidth(100, type: .percentageValueType)
        textTable.setWidth(0, type: .absoluteValueType, for: .border)
        let columnWidthPercentages = tableColumnWidthPercentages(table)

        for rowIndex in table.rows.indices {
            let isHeader = rowIndex == 0
            let isLastRow = rowIndex == table.rows.index(before: table.rows.endIndex)
            let row = table.rows[rowIndex]

            for columnIndex in row.indices {
                let cellBlock = tableCellBlock(
                    table: textTable,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    widthPercentage: columnWidthPercentages[columnIndex],
                    isHeader: isHeader
                )
                let paragraph = tableParagraphStyle(
                    cellBlock: cellBlock,
                    alignment: table.alignments[columnIndex],
                    isFirstRow: isHeader,
                    isLastRow: isLastRow
                )
                let attributes = tableCellAttributes(isHeader: isHeader, paragraphStyle: paragraph)
                appendInline(row[columnIndex], to: output, attributes: attributes)
                append("\n", to: output, attributes: attributes)
            }
        }

        output.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
    }

    private static func tableColumnWidthPercentages(_ table: MarkdownTable) -> [CGFloat] {
        let columnCount = table.alignments.count
        guard columnCount > 0 else { return [] }

        var measuredWidths = Array(repeating: CGFloat(48), count: columnCount)
        for rowIndex in table.rows.indices {
            let font = rowIndex == 0 ? tableHeaderFont() : bodyFont()
            for columnIndex in table.rows[rowIndex].indices {
                let text = inlinePlainText(table.rows[rowIndex][columnIndex])
                let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
                measuredWidths[columnIndex] = max(measuredWidths[columnIndex], width)
            }
        }

        let totalWidth = measuredWidths.reduce(0, +)
        guard totalWidth > 0 else {
            return Array(repeating: 100 / CGFloat(columnCount), count: columnCount)
        }

        let rawPercentages = measuredWidths.map { $0 / totalWidth * 100 }
        let minimum = min(CGFloat(10), 75 / CGFloat(columnCount))
        let maximum = max(100 / CGFloat(columnCount), min(CGFloat(55), 100 - minimum * CGFloat(columnCount - 1)))
        let percentages = balancedPercentages(rawPercentages, minimum: minimum, maximum: maximum)
        return percentages.map { $0 * 0.92 }
    }

    private static func balancedPercentages(
        _ percentages: [CGFloat],
        minimum: CGFloat,
        maximum: CGFloat
    ) -> [CGFloat] {
        var balanced = percentages.map { min(max($0, minimum), maximum) }
        var delta = 100 - balanced.reduce(0, +)

        while abs(delta) > 0.01 {
            let adjustable = balanced.indices.filter { delta > 0 ? balanced[$0] < maximum : balanced[$0] > minimum }
            guard !adjustable.isEmpty else { break }

            let weights = adjustable.map { index in
                if delta > 0 {
                    max(percentages[index], 0.1)
                } else {
                    max(balanced[index] - percentages[index], 0.1)
                }
            }
            let totalWeight = weights.reduce(0, +)
            var applied = CGFloat(0)

            for (offset, index) in adjustable.enumerated() {
                let share = delta * weights[offset] / totalWeight
                let limit = delta > 0 ? maximum - balanced[index] : minimum - balanced[index]
                let change = delta > 0 ? min(share, limit) : max(share, limit)
                balanced[index] += change
                applied += change
            }

            guard abs(applied) > 0.001 else { break }
            delta -= applied
        }

        return balanced
    }

    private static func inlinePlainText(_ text: String) -> String {
        let output = NSMutableAttributedString()
        appendInline(text, to: output, attributes: bodyAttributes())
        return output.string
    }

    private static func appendInline(
        _ text: String,
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            append(text, to: output, attributes: attributes)
            return
        }
        for run in parsed.runs {
            var styled = attributes
            let intent = run.inlinePresentationIntent ?? []
            var font = attributes[.font] as? NSFont ?? bodyFont()
            if intent.contains(.code) {
                styled = attributes.merging(inlineCodeAttributes(baseAttributes: attributes)) { _, new in new }
                font = styled[.font] as? NSFont ?? font
            }
            if intent.contains(.stronglyEmphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if intent.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            styled[.font] = font
            if intent.contains(.strikethrough) {
                styled[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                styled[.link] = link
                styled[.foregroundColor] = NSColor.linkColor
            }
            append(String(parsed.characters[run.range]), to: output, attributes: styled)
        }
    }

    private static func append(
        _ text: String,
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        output.append(NSAttributedString(string: text, attributes: attributes))
    }

    // GitHub-style neutral surfaces; dynamic colors also track appearance changes.
    private static var blockBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: dark ? 0.16 : 0.96, alpha: 1)
        }
    }

    private static var blockBorderColor: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: dark ? 0.32 : 0.82, alpha: 1)
        }
    }

    private static func bodyFont() -> NSFont {
        NSFont.systemFont(ofSize: 16)
    }

    private static func tableHeaderFont() -> NSFont {
        NSFont.systemFont(ofSize: 16, weight: .semibold)
    }

    private static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 16

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 24
        paragraph.paragraphSpacing = 16

        let size: CGFloat
        switch level {
        case 1: size = 32
        case 2: size = 24
        case 3: size = 20
        case 4: size = 16
        default: size = 14
        }

        return [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func inlineCodeAttributes(baseAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.quaternaryLabelColor
        ]

        if let paragraphStyle = baseAttributes[.paragraphStyle] {
            attributes[.paragraphStyle] = paragraphStyle
        }

        return attributes
    }

    private static func listAttributes(indent: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent + 28
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent + 28)]

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func tableCellBlock(
        table: NSTextTable,
        rowIndex: Int,
        columnIndex: Int,
        widthPercentage: CGFloat,
        isHeader: Bool
    ) -> NSTextTableBlock {
        let block = NSTextTableBlock(
            table: table,
            startingRow: rowIndex,
            rowSpan: 1,
            startingColumn: columnIndex,
            columnSpan: 1
        )
        block.verticalAlignment = .topAlignment
        block.setContentWidth(widthPercentage, type: .percentageValueType)
        block.setWidth(8, type: .absoluteValueType, for: .padding)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(blockBorderColor)
        block.backgroundColor = isHeader || rowIndex.isMultiple(of: 2)
            ? blockBackgroundColor
            : NSColor.textBackgroundColor
        return block
    }

    private static func tableParagraphStyle(
        cellBlock: NSTextTableBlock,
        alignment: TableAlignment,
        isFirstRow: Bool,
        isLastRow: Bool
    ) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacingBefore = isFirstRow ? 8 : 0
        paragraph.paragraphSpacing = isLastRow ? 8 : 0
        paragraph.textBlocks = [cellBlock]
        switch alignment {
        case .left:
            paragraph.alignment = .left
        case .center:
            paragraph.alignment = .center
        case .right:
            paragraph.alignment = .right
        }
        return paragraph
    }

    private static func tableCellAttributes(
        isHeader: Bool,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: isHeader ? tableHeaderFont() : bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }
}
