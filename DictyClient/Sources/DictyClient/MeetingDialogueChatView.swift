import SwiftUI

// MARK: - Chat Turn Model
struct MeetingChatTurn: Identifiable, Equatable {
    let id: String
    let speaker: String
    let isYou: Bool
    let timestamp: String?
    let text: String
}

// MARK: - Dialogue Parser
enum MeetingDialogueParser {
    private static let inlineTimestampRegex = try? NSRegularExpression(
        pattern: #"\[(?:\d{1,2}:)?\d{1,2}:\d{2}(?:\.\d+)?\s*(?:-|-->)\s*(?:\d{1,2}:)?\d{1,2}:\d{2}(?:\.\d+)?\]\s*"#,
        options: []
    )

    private static func stripInlineTimestamps(_ s: String) -> String {
        guard let rx = inlineTimestampRegex else { return s }
        let ns = s as NSString
        return rx.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts structured chat turns from Markdown meeting transcripts:
    /// Lines like `**Speaker 1**: text`, `*(01:23)* **Kenny**: text`, or `**You**: text`
    static func parseTurns(from rawText: String, youLabel: String = "You") -> (turns: [MeetingChatTurn], otherContent: String?) {
        guard !rawText.isEmpty else { return ([], nil) }

        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        
        // Regex matches lines formatted as:
        // optional: *(00:15)* or *[00:15]* or (00:15)
        // required: **Speaker Name**: Text...
        let pattern = #"(?m)^(?:\*(?:\(|\[)?(\d{1,2}:\d{2}(?:\.\d+)?)(?:\)|\])?\*\s*)?\*\*([^\*]+)\*\*:\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ([], rawText)
        }

        let nsString = normalized as NSString
        let matches = regex.matches(in: normalized, options: [], range: NSRange(location: 0, length: nsString.length))

        guard !matches.isEmpty else {
            return ([], rawText)
        }

        var turns: [MeetingChatTurn] = []
        var turnIndex = 0
        let youNormalized = youLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for match in matches {
            var timestamp: String? = nil
            if match.range(at: 1).location != NSNotFound {
                timestamp = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let speaker = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let text = stripInlineTimestamps(nsString.substring(with: match.range(at: 3)))

            let isYou = speaker.lowercased() == "you" || speaker.lowercased() == youNormalized

            turns.append(MeetingChatTurn(
                id: "turn_\(turnIndex)",
                speaker: speaker,
                isYou: isYou,
                timestamp: timestamp,
                text: text
            ))
            turnIndex += 1
        }

        // Check if there is a separate section (like ## Summary or ## Action items) before or after Dialogue
        var remainingSections: [String] = []
        let sections = normalized.components(separatedBy: "\n\n")
        for sec in sections {
            let trimmed = sec.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip the Dialogue header itself and turn lines
            if trimmed.hasPrefix("## Dialogue") || trimmed == "Dialogue" { continue }
            if trimmed.hasPrefix("> Speaker separation incomplete:") { continue }
            let isTurnLine = trimmed.hasPrefix("**") || (trimmed.hasPrefix("*(") && trimmed.contains("**"))
            if !isTurnLine && !trimmed.isEmpty {
                remainingSections.append(trimmed)
            }
        }

        let extra = remainingSections.isEmpty ? nil : remainingSections.joined(separator: "\n\n")
        return (turns, extra)
    }
}

// MARK: - Speaker Color Palette
private enum SpeakerColorPalette {
    static let colors: [Color] = [
        Color(red: 130/255.0, green: 175/255.0, blue: 215/255.0), // Sky blue
        Color(red: 180/255.0, green: 160/255.0, blue: 215/255.0), // Lavender
        Color(red: 235/255.0, green: 170/255.0, blue: 140/255.0), // Peach / Warm coral
        Color(red: 235/255.0, green: 205/255.0, blue: 130/255.0), // Buttercup / Sand
        Color(red: 130/255.0, green: 195/255.0, blue: 190/255.0), // Mint / Seafoam
        Color(red: 215/255.0, green: 160/255.0, blue: 190/255.0), // Dusty rose
        Color(red: 160/255.0, green: 180/255.0, blue: 195/255.0)  // Slate
    ]

    static func color(for speaker: String) -> Color {
        let hash = abs(speaker.hashValue)
        return colors[hash % colors.count]
    }

    static func initials(for speaker: String) -> String {
        let parts = speaker.split(separator: " ").map(String.init)
        if parts.count >= 2, let first = parts[0].first, let second = parts[1].first {
            return "\(first)\(second)".uppercased()
        } else if let firstWord = parts.first, !firstWord.isEmpty {
            return String(firstWord.prefix(2)).uppercased()
        }
        return "S"
    }
}

// MARK: - Single Chat Bubble View
struct MeetingChatBubbleView: View {
    let turn: MeetingChatTurn

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if turn.isYou {
                Spacer(minLength: 44)
            } else {
                // Speaker Avatar Circle
                ZStack {
                    Circle()
                        .fill(SpeakerColorPalette.color(for: turn.speaker).opacity(0.22))
                    Text(SpeakerColorPalette.initials(for: turn.speaker))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(SpeakerColorPalette.color(for: turn.speaker))
                }
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(SpeakerColorPalette.color(for: turn.speaker).opacity(0.35), lineWidth: 0.8)
                )
            }

            VStack(alignment: turn.isYou ? .trailing : .leading, spacing: 4) {
                // Speaker Label + Timestamp
                HStack(spacing: 6) {
                    if !turn.isYou {
                        Text(turn.speaker)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(SpeakerColorPalette.color(for: turn.speaker))
                    }

                    if let ts = turn.timestamp {
                        Text(ts)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.dictySecondary.opacity(0.8))
                    }

                    if turn.isYou {
                        Text("You")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.stylishGreen)
                    }
                }
                .padding(.horizontal, 4)

                // Bubble Container
                Text(turn.text)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.primary)
                    .lineSpacing(2.5)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(turn.isYou ? Color.stylishGreen.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(turn.isYou ? Color.stylishGreen.opacity(0.32) : Color.primary.opacity(0.09), lineWidth: 1)
                    )
            }

            if turn.isYou {
                // "You" Avatar Circle
                ZStack {
                    Circle()
                        .fill(Color.stylishGreen.opacity(0.25))
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.stylishGreen)
                }
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.stylishGreen.opacity(0.4), lineWidth: 0.8)
                )
            } else {
                Spacer(minLength: 44)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Dialogue Chat Stream View
struct MeetingDialogueChatView: View {
    let turns: [MeetingChatTurn]
    let isExpanded: Bool

    private var displayedTurns: [MeetingChatTurn] {
        if isExpanded {
            return turns
        }
        // In collapsed card mode: preview the first 2 turns
        return Array(turns.prefix(2))
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(displayedTurns) { turn in
                MeetingChatBubbleView(turn: turn)
            }

            if !isExpanded && turns.count > 2 {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis.bubble")
                        .font(.system(size: 10, weight: .medium))
                    Text("+\(turns.count - 2) more messages in meeting dialogue")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.dictySecondary)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
