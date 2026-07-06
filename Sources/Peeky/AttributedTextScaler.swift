import AppKit

enum AttributedTextScaler {
    static func scaled(_ source: NSAttributedString, by scale: CGFloat) -> NSAttributedString {
        guard scale > 0, abs(scale - 1) > 0.001 else {
            return NSAttributedString(attributedString: source)
        }

        let output = NSMutableAttributedString(attributedString: source)
        guard output.length > 0 else { return output }

        let fullRange = NSRange(location: 0, length: output.length)

        output.enumerateAttributes(in: fullRange) { attributes, range, _ in
            if let font = attributes[.font] as? NSFont {
                output.addAttribute(.font, value: scaledFont(font, by: scale), range: range)
            }

            if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
                output.addAttribute(
                    .paragraphStyle,
                    value: scaledParagraphStyle(paragraphStyle, by: scale),
                    range: range
                )
            }
        }

        return output
    }

    private static func scaledFont(_ font: NSFont, by scale: CGFloat) -> NSFont {
        let size = min(max(font.pointSize * scale, 6), 96)
        if let scaled = NSFont(descriptor: font.fontDescriptor, size: size) {
            return scaled
        }
        return NSFontManager.shared.convert(font, toSize: size)
    }

    private static func scaledParagraphStyle(
        _ paragraphStyle: NSParagraphStyle,
        by scale: CGFloat
    ) -> NSParagraphStyle {
        guard let scaled = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle else {
            return paragraphStyle
        }

        scaled.lineSpacing *= scale
        scaled.paragraphSpacing *= scale
        scaled.paragraphSpacingBefore *= scale
        scaled.headIndent *= scale
        scaled.firstLineHeadIndent *= scale
        scaled.tailIndent *= scale
        scaled.minimumLineHeight *= scale
        scaled.maximumLineHeight *= scale
        scaled.defaultTabInterval *= scale

        return scaled
    }
}
