import SwiftUI
import Combine

@MainActor
class OverlayViewModel: ObservableObject {
    @Published var isVisible = false
    @Published var isLoading = false
    @Published var completions: [String] = []
    @Published var selectedIndex: Int = 0
    @Published var error: String?
    @Published var cursorPosition: CGPoint?

    private let accessibilityManager: AccessibilityManager
    private let completionService: CompletionService
    weak var windowManager: OverlayWindowManager?

    private var refreshTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init(accessibilityManager: AccessibilityManager, completionService: CompletionService) {
        self.accessibilityManager = accessibilityManager
        self.completionService = completionService
    }

    func show() {
        isVisible = true
        error = nil
        completions = []
        selectedIndex = 0
        cursorPosition = accessibilityManager.getCursorPosition()
    }

    func hide() {
        isVisible = false
        isLoading = false
        completions = []
        selectedIndex = 0
        error = nil

        // Cancel any pending refresh tasks
        debounceTask?.cancel()
        refreshTask?.cancel()
    }

    func selectOption(_ index: Int) {
        guard index >= 0 && index < completions.count else { return }
        selectedIndex = index
        print("📍 Selected option \(index + 1): \"\(completions[index])\"")
    }

    func scheduleCompletionRefresh() {
        // Cancel existing debounce task
        debounceTask?.cancel()

        // Create new debounce task that waits 500ms before refreshing
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce

                guard !Task.isCancelled else { return }

                print("🔄 Refreshing completion due to keystroke")
                await requestCompletion()
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    func requestCompletion() async {
        isLoading = true
        error = nil
        completions = []
        selectedIndex = 0

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

        // Request completions
        do {
            let results = try await completionService.generateCompletions(context: context)
            print("✅ Received \(results.count) completions")
            for (index, result) in results.enumerated() {
                print("   \(index + 1). \"\(result)\"")
            }
            completions = results
            selectedIndex = 0 // Default to first option
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
        guard !completions.isEmpty else {
            print("❌ No completions to accept")
            return
        }

        let selectedCompletion = completions[selectedIndex]
        print("✍️ Hiding overlay first, then inserting completion \(selectedIndex + 1): \"\(selectedCompletion)\"")
        hide()
        windowManager?.hideOverlay()

        // Small delay to ensure overlay is fully hidden and focus returns to the field
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        let success = await accessibilityManager.insertText(selectedCompletion)
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
            else if !viewModel.completions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Show 3 completion options
                    ForEach(0..<viewModel.completions.count, id: \.self) { index in
                        CompletionOptionRow(
                            number: index + 1,
                            text: viewModel.completions[index],
                            isSelected: index == viewModel.selectedIndex
                        )
                    }

                    // Key hint row
                    HStack(spacing: 16) {
                        Label("1, 2, 3 to select", systemImage: "number.circle")
                            .foregroundStyle(.gray)
                        Label("⌥[ to accept", systemImage: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Label("⎋ to cancel", systemImage: "xmark.circle")
                            .foregroundStyle(.purple)
                    }
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            }
        }
        .frame(minWidth: 400, maxWidth: 500, minHeight: 60)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        )
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }
}

struct CompletionOptionRow: View {
    let number: Int
    let text: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Number badge with gradient
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [.gray.opacity(0.5), .gray.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                )

            // Completion text
            Text(text)
                .font(.body)
                .foregroundColor(isSelected ? .white : .gray)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected
                                ? LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [.clear, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                            lineWidth: 2
                        )
                )
        )
        .contentShape(Rectangle())
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

#Preview("With Completions") {
    let accessibilityManager = AccessibilityManager()
    let completionService = CompletionService()
    let viewModel = OverlayViewModel(
        accessibilityManager: accessibilityManager,
        completionService: completionService
    )
    viewModel.isVisible = true
    viewModel.completions = [
        "and then I realized that the key to success is consistency.",
        "and subsequently discovered the importance of perseverance.",
        "and finally understood that dedication leads to mastery."
    ]
    viewModel.selectedIndex = 0

    return OverlayView(viewModel: viewModel)
        .frame(width: 500, height: 250)
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