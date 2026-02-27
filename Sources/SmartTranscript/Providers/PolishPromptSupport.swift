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

    Rules markdown:
    \(rulesMarkdown)

    Raw transcript:
    \(rawText)

    Return only final Markdown text.
    """
}

func makeDiffPrompt(rawText: String, polishedText: String, feedback: String, currentRules: String) -> String {
    """
    Current rules file content:
    \(currentRules)

    Session raw transcript:
    \(rawText)

    Session polished transcript:
    \(polishedText)

    User feedback:
    \(feedback)

    Update rules to address feedback in future runs. Output ONLY a unified diff for file Rules/rules.md.
    Requirements:
    - Include --- and +++ headers
    - Include @@ hunks
    - Do not include prose outside diff
    """
}
