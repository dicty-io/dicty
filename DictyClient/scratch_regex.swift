import Foundation

let input = """
**Executive Summary:** Hello

- [ ] Task 1
- [x] Task 2
"""
let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
if let attr = try? AttributedString(markdown: input, options: options) {
    print("Parsed: \(String(attr.characters))")
}
