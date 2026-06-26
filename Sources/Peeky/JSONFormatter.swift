import Foundation

enum JSONFormatter {
    static func prettyJSON(_ text: String) throws -> String {
        let data = Data(text.utf8)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        guard JSONSerialization.isValidJSONObject(object) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let formattedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )

        return String(data: formattedData, encoding: .utf8) ?? text
    }

    static func prettyJSONLines(_ text: String) -> (text: String, invalidLineCount: Int) {
        var invalidLineCount = 0
        var output: [String] = []

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            do {
                output.append(try prettyJSON(trimmed))
            } catch {
                invalidLineCount += 1
                output.append(line)
            }
        }

        return (output.joined(separator: "\n"), invalidLineCount)
    }
}
