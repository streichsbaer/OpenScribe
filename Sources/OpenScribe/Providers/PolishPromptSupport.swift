import Foundation

func unwrapCodeBlockIfNeeded(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else {
        return trimmed
    }

    let lines = trimmed.components(separatedBy: "\n")
    guard lines.count >= 2 else {
        return trimmed
    }

    var body = lines
    if body.first?.hasPrefix("```") == true {
        body.removeFirst()
    }
    if body.last?.hasPrefix("```") == true {
        body.removeLast()
    }

    return body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

func makePolishUserPrompt(rawText: String, rulesMarkdown: String) -> String {
    """
    Apply these markdown formatting and glossary rules to the transcript.

    Hard constraints:
    - Output ONLY the polished transcript content.
    - Do NOT add meta sections, notes, or headings such as "Glossary", "Rules", "Summary", or "Notes" unless those words were explicitly spoken in the transcript.
    - Do NOT append explanations, labels, or any extra commentary.
    - Keep intent and meaning unchanged.

    Rules markdown:
    \(rulesMarkdown)

    Raw transcript:
    \(rawText)

    Return only final Markdown text.
    """
}

func sanitizePolishedOutput(_ markdown: String, rawText: String) -> String {
    let cleaned = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawLower = rawText.lowercased()
    if rawLower.contains("glossary") {
        return cleaned
    }

    let pattern = #"(?im)^#{1,6}\s+glossary\b.*(?:\n|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return cleaned
    }

    let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
    guard let match = regex.firstMatch(in: cleaned, range: range),
          let headingRange = Range(match.range, in: cleaned) else {
        return cleaned
    }

    let prefix = String(cleaned[..<headingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    return prefix
}
