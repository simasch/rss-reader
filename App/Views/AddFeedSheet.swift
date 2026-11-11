import RSSReaderKit
import SwiftUI

struct AddFeedSheet: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var errorMessage: String?
    @State private var isAdding = false
    @State private var addTask: Task<Void, Never>?
    internal let inspection = Inspection<Self>() // UI test hook (ViewInspector)

    private let explanation = "Enter a feed URL, or a website address and the feed will be discovered."

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Feed").font(.headline)
            Text(explanation)
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
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .onAppear(perform: prefillFromPasteboard)
        .onDisappear { addTask?.cancel() }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
        #else
        NavigationStack {
            Form {
                Section {
                    TextField("URL", text: $urlString, prompt: Text("https://example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .disabled(isAdding)
                        .onSubmit(add)
                } footer: {
                    Text(explanation)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add", action: add).disabled(!canAdd)
                    }
                }
            }
            .onDisappear { addTask?.cancel() }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
        #endif
    }

    // UC-001 BR-010: the form can be confirmed only when the address holds more than spaces.
    private var canAdd: Bool {
        !isAdding && !urlString.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        isAdding = true
        errorMessage = nil
        addTask = Task {
            do {
                try await store.addFeed(from: urlString)
                dismiss()
            } catch is CancellationError {
                // UC-001 A7: the Reader cancelled; the form is already closing.
            } catch let error as URLError where error.code == .cancelled {
                // UC-001 A7: the retrieval was abandoned.
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
            addTask = nil
        }
    }

    /// UC-001 A7, BR-009: cancelling abandons a running retrieval so no feed is added.
    private func cancel() {
        addTask?.cancel()
        dismiss()
    }

    #if os(macOS)
    // Not done on iOS: reading the pasteboard there shows a "paste from…" privacy prompt.
    private func prefillFromPasteboard() {
        guard let string = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("feed:"),
            !string.contains(" ") else { return }
        urlString = string
    }
    #endif
}
