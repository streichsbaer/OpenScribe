import Foundation

enum UnifiedDiffError: Error, LocalizedError {
    case malformed(String)
    case pathNotAllowed(String)
    case contextMismatch(expected: String, actual: String)
    case outOfBounds

    var errorDescription: String? {
        switch self {
        case .malformed(let message):
            return "Malformed unified diff: \(message)"
        case .pathNotAllowed(let path):
            return "Diff path is not allowed: \(path)"
        case .contextMismatch(let expected, let actual):
            return "Diff context mismatch. Expected '\(expected)' got '\(actual)'."
        case .outOfBounds:
            return "Diff hunk is out of bounds for target file."
        }
    }
}

enum UnifiedDiff {
    struct Hunk {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        let lines: [HunkLine]
    }

    enum HunkLine {
        case context(String)
        case add(String)
        case remove(String)
    }

    struct Patch {
        let oldPath: String
        let newPath: String
        let hunks: [Hunk]
    }

    static func parse(_ diff: String) throws -> Patch {
        let rawLines = diff
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        guard let oldHeaderIndex = rawLines.firstIndex(where: { $0.hasPrefix("--- ") }) else {
            throw UnifiedDiffError.malformed("Missing old file header.")
        }

        let oldPath = rawLines[oldHeaderIndex].dropFirst(4).trimmingCharacters(in: .whitespaces)
        let newHeaderIndex = oldHeaderIndex + 1

        guard rawLines.indices.contains(newHeaderIndex), rawLines[newHeaderIndex].hasPrefix("+++ ") else {
            throw UnifiedDiffError.malformed("Missing new file header.")
        }

        let newPath = rawLines[newHeaderIndex].dropFirst(4).trimmingCharacters(in: .whitespaces)

        var hunks: [Hunk] = []
        var index = newHeaderIndex + 1

        while index < rawLines.count {
            let line = rawLines[index]
            if line.isEmpty {
                index += 1
                continue
            }

            guard line.hasPrefix("@@") else {
                throw UnifiedDiffError.malformed("Unexpected line before hunk: \(line)")
            }

            let header = try parseHeader(line)
            index += 1

            var hunkLines: [HunkLine] = []
            while index < rawLines.count {
                let current = rawLines[index]

                if current.hasPrefix("@@") || current.hasPrefix("--- ") {
                    break
                }

                if current == "\\ No newline at end of file" {
                    index += 1
                    continue
                }

                guard let prefix = current.first else {
                    hunkLines.append(.context(""))
                    index += 1
                    continue
                }

                let content = String(current.dropFirst())
                switch prefix {
                case " ":
                    hunkLines.append(.context(content))
                case "+":
                    hunkLines.append(.add(content))
                case "-":
                    hunkLines.append(.remove(content))
                default:
                    throw UnifiedDiffError.malformed("Invalid hunk line prefix: \(current)")
                }

                index += 1
            }

            hunks.append(Hunk(
                oldStart: header.oldStart,
                oldCount: header.oldCount,
                newStart: header.newStart,
                newCount: header.newCount,
                lines: hunkLines
            ))
        }

        return Patch(oldPath: String(oldPath), newPath: String(newPath), hunks: hunks)
    }

    static func validateSingleRulesFile(_ patch: Patch) throws {
        guard normalizedRulesPath(patch.oldPath) || normalizedRulesPath(patch.newPath) else {
            throw UnifiedDiffError.pathNotAllowed("\(patch.oldPath) -> \(patch.newPath)")
        }
    }

    static func apply(patch: Patch, to original: String) throws -> String {
        var source = original.replacingOccurrences(of: "\r\n", with: "\n")
        let hadTrailingNewline = source.hasSuffix("\n")

        if hadTrailingNewline {
            source.removeLast()
        }

        let sourceLines = source.isEmpty ? [] : source.components(separatedBy: "\n")

        var result: [String] = []
        var sourceIndex = 0

        for hunk in patch.hunks {
            let hunkStart = max(0, hunk.oldStart - 1)
            guard hunkStart <= sourceLines.count else {
                throw UnifiedDiffError.outOfBounds
            }

            if sourceIndex < hunkStart {
                result.append(contentsOf: sourceLines[sourceIndex..<hunkStart])
                sourceIndex = hunkStart
            }

            for entry in hunk.lines {
                switch entry {
                case .context(let text):
                    guard sourceIndex < sourceLines.count else {
                        throw UnifiedDiffError.outOfBounds
                    }
                    let actual = sourceLines[sourceIndex]
                    guard actual == text else {
                        throw UnifiedDiffError.contextMismatch(expected: text, actual: actual)
                    }
                    result.append(text)
                    sourceIndex += 1
                case .remove(let text):
                    guard sourceIndex < sourceLines.count else {
                        throw UnifiedDiffError.outOfBounds
                    }
                    let actual = sourceLines[sourceIndex]
                    guard actual == text else {
                        throw UnifiedDiffError.contextMismatch(expected: text, actual: actual)
                    }
                    sourceIndex += 1
                case .add(let text):
                    result.append(text)
                }
            }
        }

        if sourceIndex < sourceLines.count {
            result.append(contentsOf: sourceLines[sourceIndex...])
        }

        var output = result.joined(separator: "\n")
        if hadTrailingNewline {
            output.append("\n")
        }
        return output
    }

    private static func parseHeader(_ line: String) throws -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        let pattern = #"^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)

        guard let match = regex.firstMatch(in: line, range: range) else {
            throw UnifiedDiffError.malformed("Invalid hunk header: \(line)")
        }

        func intAt(_ idx: Int, defaultValue: Int = 1) throws -> Int {
            let nsRange = match.range(at: idx)
            if nsRange.location == NSNotFound {
                return defaultValue
            }

            guard let range = Range(nsRange, in: line), let value = Int(line[range]) else {
                throw UnifiedDiffError.malformed("Invalid number in hunk header: \(line)")
            }

            return value
        }

        return (
            try intAt(1, defaultValue: 0),
            try intAt(2),
            try intAt(3, defaultValue: 0),
            try intAt(4)
        )
    }

    private static func normalizedRulesPath(_ raw: String) -> Bool {
        let normalized = raw
            .replacingOccurrences(of: "a/", with: "")
            .replacingOccurrences(of: "b/", with: "")
            .trimmingCharacters(in: .whitespaces)
        return normalized == "Rules/rules.md" || normalized.hasSuffix("/Rules/rules.md") || normalized == "rules.md"
    }
}
