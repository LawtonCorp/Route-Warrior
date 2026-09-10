import SwiftUI

/// A bundled legal document, rendered from its Markdown blocks (D-053),
/// with the same document's web address one tap away.
struct LegalDocumentView: View {
    let document: Legal.Document
    @State private var parsed: LegalDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let parsed {
                    ForEach(Array(parsed.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                } else {
                    Text("This document is not in this build. Read it on the web.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: document.url) {
                    Label("Open on the web", systemImage: "safari")
                }
            }
        }
        .task {
            if parsed == nil { parsed = Legal.bundled(document) }
        }
    }

    @ViewBuilder
    private func blockView(_ block: LegalMarkdown.Block) -> some View {
        switch block {
        case let .heading(level, text):
            Text(text)
                .font(level <= 2 ? .title3.bold() : .headline)
                .padding(.top, 6)
        case let .paragraph(text):
            inline(text)
        case let .bullets(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        inline(item)
                    }
                }
            }
        case let .numbered(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                        inline(item)
                    }
                }
            }
        }
    }

    /// Inline Markdown (bold, italic, links) through Foundation's
    /// parser; the raw text if it will not parse.
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}

/// Shown once per new Terms version to an install that accepted an
/// older one (D-053). Recording is not paused by it: the recorder runs
/// in the background whatever the root shows.
struct TermsUpdateView: View {
    @AppStorage(Legal.acceptedTermsKey) private var acceptedTerms = ""
    @State private var reading = false

    private var effective: String? {
        Legal.bundled(.terms)?.effectiveDate.map { $0.formatted(date: .long, time: .omitted) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.route)
                .frame(width: 136, height: 136)
                .background(Theme.route.opacity(0.12), in: Circle())
            Text("The Terms of Use have changed")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(effective.map { "The new Terms take effect \($0). Please read them; continuing means you agree to them and to the Privacy Policy." }
                ?? "Please read the new Terms; continuing means you agree to them and to the Privacy Policy.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 10) {
                Button("Read the Terms") { reading = true }
                    .buttonStyle(.bordered)
                    .tint(Theme.route)
                Button("Continue") { acceptedTerms = Legal.termsVersion }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.route)
                Text(.init(Legal.acceptanceLine))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .tint(Theme.route)
            }
            Spacer().frame(height: 40)
        }
        .padding()
        .sheet(isPresented: $reading) {
            NavigationStack {
                LegalDocumentView(document: .terms)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { reading = false }
                        }
                    }
            }
        }
    }
}
