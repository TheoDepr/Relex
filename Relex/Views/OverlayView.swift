import SwiftUI
import Combine

@MainActor
class OverlayViewModel: ObservableObject {
    @Published var isVisible = false
    @Published var isLoading = false
    @Published var completion: String?
    @Published var error: String?
    @Published var cursorPosition: CGPoint?

    private let accessibilityManager: AccessibilityManager
    private let completionService: CompletionService
    weak var windowManager: OverlayWindowManager?

    init(accessibilityManager: AccessibilityManager, completionService: CompletionService) {
        self.accessibilityManager = accessibilityManager
        self.completionService = completionService
    }

    func show() {
        isVisible = true
        error = nil
        completion = nil
        cursorPosition = accessibilityManager.getCursorPosition()
    }

    func hide() {
        isVisible = false
        isLoading = false
        completion = nil
        error = nil
    }

    func requestCompletion() async {
        isLoading = true
        error = nil
        completion = nil

        // Check API key first
        guard !completionService.apiKey.isEmpty else {
            error = "Please configure your OpenAI API key in the main window"
            print("❌ API key not configured")
            isLoading = false
            return
        }

        // Get text from focused element
        guard let context = await accessibilityManager.captureTextFromFocusedElement() else {
            error = accessibilityManager.lastError ?? "Failed to capture text"
            print("❌ Failed to capture text: \(accessibilityManager.lastError ?? "unknown error")")
            isLoading = false
            return
        }

        print("📝 Captured text from input field:")
        print("Context length: \(context.count) characters")
        print("Context: \"\(context)\"")

        // Request completion
        do {
            let result = try await completionService.generateCompletion(context: context)
            print("✅ Received completion: \"\(result)\"")
            completion = result
        } catch {
            print("❌ Completion error: \(error.localizedDescription)")
            // Make API authentication errors more user-friendly
            if error.localizedDescription.contains("401") {
                self.error = "Invalid API key. Please check your OpenAI API key in settings"
            } else {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    func acceptCompletion() async {
        guard let completion = completion else {
            print("❌ No completion to accept")
            return
        }

        print("✍️ Hiding overlay first, then inserting completion: \"\(completion)\"")
        hide()
        windowManager?.hideOverlay()

        // Small delay to ensure overlay is fully hidden and focus returns to the field
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        let success = await accessibilityManager.insertText(completion)
        print("✍️ Insert result: \(success)")

        if !success {
            print("❌ Failed to insert text")
            error = "Failed to insert text"
        }
    }

    func cancelCompletion() {
        hide()
        windowManager?.hideOverlay()
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Loading state
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Generating completion…")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // Error state
            else if let error = viewModel.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Completion state
            else if let completion = viewModel.completion {
                VStack(alignment: .leading, spacing: 10) {
                    // Main suggestion box
                    Text(completion)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .shadow(radius: 1, y: 1)
                        )

                    // Key hint row
                    HStack(spacing: 20) {
                        Label("Option+[ to accept", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        Label("Escape to cancel", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                    .padding(.horizontal, 4)
                }
            }
        }
        .frame(minWidth: 400, maxWidth: 500, minHeight: 60)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }
}

#Preview("Loading State") {
    let accessibilityManager = AccessibilityManager()
    let completionService = CompletionService()
    let viewModel = OverlayViewModel(
        accessibilityManager: accessibilityManager,
        completionService: completionService
    )
    viewModel.isVisible = true
    viewModel.isLoading = true

    return OverlayView(viewModel: viewModel)
        .frame(width: 500, height: 200)
}

#Preview("With Completion") {
    let accessibilityManager = AccessibilityManager()
    let completionService = CompletionService()
    let viewModel = OverlayViewModel(
        accessibilityManager: accessibilityManager,
        completionService: completionService
    )
    viewModel.isVisible = true
    viewModel.completion = "and then I realized that the key to success is consistency and dedication to your craft."

    return OverlayView(viewModel: viewModel)
        .frame(width: 500, height: 200)
}

#Preview("Error State") {
    let accessibilityManager = AccessibilityManager()
    let completionService = CompletionService()
    let viewModel = OverlayViewModel(
        accessibilityManager: accessibilityManager,
        completionService: completionService
    )
    viewModel.isVisible = true
    viewModel.error = "Failed to capture text from the focused element"

    return OverlayView(viewModel: viewModel)
        .frame(width: 500, height: 200)
}