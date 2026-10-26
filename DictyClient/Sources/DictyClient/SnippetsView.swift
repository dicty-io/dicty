import SwiftUI

// MARK: - Models

struct DictySnippet: Codable, Identifiable, Equatable {
    let id: String
    let trigger: String
    let content: String
    let aliases: [String]?
    let expand_anywhere: Bool?

    var expandsAnywhere: Bool { expand_anywhere ?? false }
}

struct SnippetsResponse: Codable {
    let snippets: [DictySnippet]
}

// MARK: - View

/// Voice snippets: say a short trigger, Dicty pastes prepared text. Matching is deterministic (no LLM, ~0 ms).
struct SnippetsView: View {
    @EnvironmentObject var engineClient: EngineClient
    @Environment(\.colorScheme) var colorScheme

    @State private var editingId: String? = nil
    @State private var trigger = ""
    @State private var content = ""
    @State private var expandAnywhere = false
    @State private var errorMessage: String? = nil
    @State private var isSaving = false
    @State private var searchText = ""
    @State private var hoveredId: String? = nil

    private var filtered: [DictySnippet] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return engineClient.snippets }
        return engineClient.snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(q) || $0.content.localizedCaseInsensitiveContains(q)
        }
    }

    private var canSave: Bool {
        !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        // One scroll view for the whole page: a fixed editor + inner list scroller collapsed the
        // list to zero height in short windows, making the page unscrollable.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageHeader(
                    title: "Snippets",
                    description: "Save text you type a lot. Say a short phrase, and Dicty types the full text for you."
                )

                examplesCard

                Divider()

                editorCard

                if !engineClient.snippets.isEmpty {
                    searchField
                }

                LazyVStack(spacing: 8) {
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { row($0) }
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(20)
        }
        .navigationTitle("Snippets")
        .onAppear { engineClient.fetchSnippets() }
    }

    // MARK: Examples

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to use it")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            exampleRow(say: "my email", get: "john@example.com")
            exampleRow(say: "my LinkedIn", get: "linkedin.com/in/john")
            exampleRow(say: "Here's my profile, insert my LinkedIn", get: "Here's my profile, linkedin.com/in/john")
            Text("Say the phrase by itself. Inside a sentence, say \"insert\" first.")
                .font(.system(size: 11))
                .foregroundColor(.dictySecondary)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.sageGreen.opacity(colorScheme == .dark ? 0.08 : 0.06))
        )
    }

    private func exampleRow(say: String, get: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "mic.fill").font(.system(size: 9))
                Text("\u{201C}\(say)\u{201D}").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.primary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.dictySecondary)
            Text(get)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.dictySecondary)
                .lineLimit(1)
        }
    }

    // MARK: Editor

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: editingId == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.sageGreen)
                Text(editingId == nil ? "New snippet" : "Edit snippet")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Spacer()
                if editingId != nil {
                    Button("Cancel") { resetEditor() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.dictySecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("When you say")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dictySecondary)
                TextField("e.g. my LinkedIn", text: $trigger)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .modifier(SnippetFieldStyle(colorScheme: colorScheme))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Dicty types")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dictySecondary)
                TextEditor(text: $content)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .frame(minHeight: 64, maxHeight: 140)
                    .modifier(SnippetFieldStyle(colorScheme: colorScheme))
            }

            HStack(alignment: .center) {
                Toggle(isOn: $expandAnywhere) {
                    Text("Also work inside sentences, without saying \"insert\"")
                        .font(.system(size: 11.5))
                        .foregroundColor(.dictySecondary)
                }
                .toggleStyle(.checkbox)
                .help("Use this only for phrases you never say by accident. Otherwise normal sentences may get replaced.")

                Spacer()

                Button(action: save) {
                    Text(editingId == nil ? "Add Snippet" : "Save")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(canSave ? Color.sageGreen : Color.secondary.opacity(0.2))
                        )
                        .foregroundColor(canSave ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 230/255, green: 130/255, blue: 130/255))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.dictySecondary)
            TextField("Search snippets", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
    }

    // MARK: List

    private func row(_ s: DictySnippet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill").font(.system(size: 9))
                Text(s.trigger).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.sageGreen.opacity(colorScheme == .dark ? 0.2 : 0.14)))
            .foregroundColor(.primary)

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.dictySecondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(s.content)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
                if s.expandsAnywhere {
                    Text("Works inside sentences")
                        .font(.system(size: 10))
                        .foregroundColor(.dictySecondary)
                }
            }
            .padding(.top, 3)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button { beginEditing(s) } label: { Image(systemName: "pencil") }
                    .help("Edit")
                Button { engineClient.deleteSnippet(id: s.id); if editingId == s.id { resetEditor() } } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.dictySecondary)
            .opacity(hoveredId == s.id || editingId == s.id ? 1 : 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(editingId == s.id ? Color.sageGreen.opacity(0.08) : Color.primary.opacity(hoveredId == s.id ? 0.04 : 0.02))
        )
        .onHover { inside in
            if inside { hoveredId = s.id } else if hoveredId == s.id { hoveredId = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 22))
                .foregroundColor(.dictySecondary)
            Text(engineClient.snippets.isEmpty ? "No snippets yet" : "No matches")
                .font(.system(size: 13, weight: .semibold))
            if engineClient.snippets.isEmpty {
                Text("Try: \"my email address\" → your email. Then just say \"my email address\".")
                    .font(.system(size: 11.5))
                    .foregroundColor(.dictySecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: Actions

    private func beginEditing(_ s: DictySnippet) {
        editingId = s.id
        trigger = s.trigger
        content = s.content
        expandAnywhere = s.expandsAnywhere
        errorMessage = nil
    }

    private func resetEditor() {
        editingId = nil
        trigger = ""
        content = ""
        expandAnywhere = false
        errorMessage = nil
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let id = editingId
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = content
        let anywhere = expandAnywhere
        Task {
            let error = await engineClient.saveSnippet(id: id, trigger: t, content: c, expandAnywhere: anywhere)
            await MainActor.run {
                isSaving = false
                if let error { errorMessage = error } else { resetEditor() }
            }
        }
    }
}

private struct SnippetFieldStyle: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}
