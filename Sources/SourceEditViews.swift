// SourceEditViews.swift
// Add-source form and edit-source sheet.

import SwiftUI

// MARK: - Add Source Form

struct AddSourceForm: View {
    @ObservedObject var service: StatusService
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var url = ""
    @FocusState private var focusedField: Field?
    @State private var urlAnnouncementTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field: Hashable {
        case name
        case url
    }

    private var urlValidation: URLValidationResult {
        validateSourceURL(url.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(spacing: Design.Spacing.cellInner) {
            TextField("Name", text: $name)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .name)

            TextField("URL (e.g. https://status.example.com)", text: $url)
                .font(Design.Typography.mono)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .url)

            URLValidationMessage(url: url, validation: urlValidation)

            HStack {
                Spacer()
                Button("Add") {
                    let trimmedName = name.trimmingCharacters(in: .whitespaces)
                    let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedName.isEmpty, urlValidation.isAcceptable else { return }
                    withAnimation(reduceMotionAnimation(Design.Timing.expand, reduceMotion: reduceMotion)) {
                        service.addSource(name: trimmedName, baseURL: trimmedURL)
                        isPresented = false
                    }
                }
                .font(Design.Typography.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                        || !urlValidation.isAcceptable
                )
            }
        }
        .padding(.horizontal, Design.Spacing.sectionH)
        .padding(.vertical, Design.Spacing.sectionV)
        .accessibleTransition(.opacity.combined(with: .move(edge: .top)))
        .onAppear { focusedField = .name }
        .onChange(of: url) { _, newValue in
            urlAnnouncementTask?.cancel()
            urlAnnouncementTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let result = validateSourceURL(trimmed)
                if let message = result.message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}

// MARK: - Edit Source Sheet

struct EditSourceSheet: View {
    @ObservedObject var service: StatusService
    let source: StatusSource
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var url: String
    @FocusState private var nameFocused: Bool

    init(service: StatusService, source: StatusSource) {
        self.service = service
        self.source = source
        _name = State(initialValue: source.name)
        _url = State(initialValue: source.baseURL)
    }

    private var urlValidation: URLValidationResult {
        validateSourceURL(url.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && urlValidation.isAcceptable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.cardInner) {
            Text("Edit Source")
                .font(Design.Typography.bodyMedium)

            TextField("Name", text: $name)
                .font(Design.Typography.caption)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            TextField("URL", text: $url)
                .font(Design.Typography.mono)
                .textFieldStyle(.roundedBorder)

            URLValidationMessage(url: url, validation: urlValidation)

            if url.trimmingCharacters(in: CharacterSet(charactersIn: "/")) != source.baseURL {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(Design.Typography.micro)
                    Text("Changing the URL re-detects the provider and resets current status.")
                        .font(Design.Typography.micro)
                }
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .controlSize(.small)
                Button("Save") {
                    service.updateSource(
                        sourceID: source.id,
                        name: name.trimmingCharacters(in: .whitespaces),
                        baseURL: url.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSave)
            }
        }
        .padding(Design.Spacing.sectionH)
        .frame(width: 300)
        .onAppear { nameFocused = true }
    }
}

// MARK: - URL Validation Message

struct URLValidationMessage: View {
    let url: String
    let validation: URLValidationResult

    var body: some View {
        if !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let message = validation.message
        {
            HStack(spacing: 4) {
                Image(systemName: validation.isAcceptable ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                    .font(Design.Typography.micro)
                Text(message)
                    .font(Design.Typography.micro)
            }
            .foregroundStyle(validation.isAcceptable ? .orange : .red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
