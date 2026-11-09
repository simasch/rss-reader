import SwiftUI

struct AddFeedSheet: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var errorMessage: String?
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Feed").font(.headline)
            Text("Enter a feed URL, or a website address and the feed will be discovered.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("URL", text: $urlString, prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 400)
                .disabled(isAdding)
                .onSubmit(add)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                if isAdding { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAdding || urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear(perform: prefillFromPasteboard)
    }

    private func add() {
        guard !isAdding else { return }
        isAdding = true
        errorMessage = nil
        Task {
            do {
                try await store.addFeed(from: urlString)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }

    private func prefillFromPasteboard() {
        guard let string = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("feed:"),
            !string.contains(" ") else { return }
        urlString = string
    }
}
