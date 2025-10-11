import SwiftUI
import Combine

@MainActor
class OverlayViewModel: ObservableObject {
    @Published var isVisible = false
    @Published var isLoading = false
    @Published var completions: [CompletionOption] = []
    @Published var selectedIndex: Int = 0
    @Published var error: String?
    @Published var cursorPosition: CGPoint?

    // History stack for drill-down navigation
    @Published var completionHistory: [[CompletionOption]] = []
    @Published var contextHistory: [String] = []
    @Published var selectedIndexHistory: [Int] = []
    @Published var keywordPath: [String] = []  // Breadcrumb trail of keywords

    var currentDepth: Int {
        return completionHistory.count
    }

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
        selectedIndex = 2  // Default to middle option (index 2 of 5 options)
        cursorPosition = accessibilityManager.getCursorPosition()

        // Clear history when showing fresh overlay
        completionHistory = []
        contextHistory = []
        selectedIndexHistory = []
        keywordPath = []
    }

    func hide() {
        isVisible = false
        isLoading = false
        completions = []
        selectedIndex = 2  // Reset to middle option
        error = nil

        // Clear history
        completionHistory = []
        contextHistory = []
        selectedIndexHistory = []
        keywordPath = []

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

                print("🔄 Refreshing completion due to keystroke at depth \(currentDepth)")

                if currentDepth > 0 {
                    // At drill-down level - regenerate with keyword context
                    await requestCompletionWithKeywordPath()
                } else {
                    // At root level - normal completion
                    await requestCompletion()
                }
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    func requestCompletionWithKeywordPath() async {
        guard !keywordPath.isEmpty else {
            await requestCompletion()
            return
        }

        isLoading = true
        error = nil

        // Get fresh context from text field
        guard let currentContext = await accessibilityManager.captureTextFromFocusedElement() else {
            error = accessibilityManager.lastError ?? "Failed to capture text"
            print("❌ Failed to capture context for keyword refresh")
            isLoading = false
            return
        }

        print("🔄 Refreshing with keyword path: \(keywordPath.joined(separator: " > "))")

        // Use the last keyword in the path for refinement
        let lastKeyword = keywordPath.last!

        do {
            let results = try await completionService.generateCompletions(
                context: currentContext,
                refinementKeyword: lastKeyword
            )
            print("✅ Received \(results.count) refreshed completions for '\(lastKeyword)'")
            completions = results
            selectedIndex = 2
        } catch {
            print("❌ Refresh error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func requestCompletion() async {
        isLoading = true
        error = nil
        completions = []
        selectedIndex = 2  // Default to middle option

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
            selectedIndex = 2 // Default to middle option (3rd of 5)
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

        let selectedCompletion = completions[selectedIndex].text
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

    // MARK: - Drill-Down Navigation

    func drillDownIntoKeyword() async {
        guard !completions.isEmpty else {
            print("❌ No completions to drill down into")
            return
        }

        let selectedOption = completions[selectedIndex]
        print("🔍 Drilling down into keyword: \"\(selectedOption.keyword)\"")

        // Save current state to history
        completionHistory.append(completions)
        selectedIndexHistory.append(selectedIndex)
        keywordPath.append(selectedOption.keyword)

        // ALWAYS capture fresh context from the text field
        guard let currentContext = await accessibilityManager.captureTextFromFocusedElement() else {
            print("❌ Failed to capture context for drill-down")
            // Restore state
            _ = completionHistory.popLast()
            _ = selectedIndexHistory.popLast()
            _ = keywordPath.popLast()
            return
        }

        print("📝 Using fresh context for drill-down: \"\(currentContext)\"")
        contextHistory.append(currentContext)

        // Generate refined completions (keep existing completions visible during load)
        isLoading = true
        error = nil
        // Don't clear completions here - keep them visible during loading

        do {
            let results = try await completionService.generateCompletions(
                context: currentContext,
                refinementKeyword: selectedOption.keyword
            )
            print("✅ Received \(results.count) refined completions for '\(selectedOption.keyword)'")
            completions = results
            selectedIndex = 2
        } catch {
            print("❌ Drill-down error: \(error.localizedDescription)")
            self.error = error.localizedDescription

            // Restore state on error
            _ = completionHistory.popLast()
            _ = contextHistory.popLast()
            _ = selectedIndexHistory.popLast()
            _ = keywordPath.popLast()
        }

        isLoading = false
    }

    func navigateBack() {
        guard !completionHistory.isEmpty else {
            print("⚠️ Already at root level, cannot go back")
            return
        }

        print("⬅️ Navigating back from depth \(currentDepth)")

        // Restore previous state
        completions = completionHistory.popLast() ?? []
        selectedIndex = selectedIndexHistory.popLast() ?? 2
        _ = contextHistory.popLast()
        _ = keywordPath.popLast()

        print("✅ Restored to depth \(currentDepth)")
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Breadcrumb header (show when depth > 0)
            if viewModel.currentDepth > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.7))

                    HStack(spacing: 4) {
                        ForEach(Array(viewModel.keywordPath.enumerated()), id: \.offset) { index, keyword in
                            if index > 0 {
                                Text(">")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            Text(keyword)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue.opacity(0.8))
                        }
                    }

                    Spacer()

                    Text("Level \(viewModel.currentDepth)")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(6)
            }

            // Error state
            if let error = viewModel.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Completion state (or loading without completions)
            else if !viewModel.completions.isEmpty || viewModel.isLoading {
                ZStack {
                    // Show completions if available
                    if !viewModel.completions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            // Show 5 completion options
                            ForEach(0..<viewModel.completions.count, id: \.self) { index in
                                CompletionOptionRow(
                                    number: index + 1,
                                    option: viewModel.completions[index],
                                    isSelected: index == viewModel.selectedIndex,
                                    depth: viewModel.currentDepth
                                )
                            }

                            // Key hint row
                            HStack(spacing: 16) {
                                Label("⌥J/⌥K to navigate", systemImage: "arrow.up.arrow.down.circle")
                                    .foregroundStyle(.gray)
                                Label("⌥L to refine", systemImage: "arrow.down.circle")
                                    .foregroundStyle(.blue)
                                Label("⇧⌥L to accept", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                                if viewModel.currentDepth > 0 {
                                    Label("⌥H to back", systemImage: "arrow.left.circle")
                                        .foregroundStyle(.orange)
                                }
                                Label("⎋ to cancel", systemImage: "xmark.circle")
                                    .foregroundStyle(.purple)
                            }
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                        }
                        .opacity(viewModel.isLoading ? 0.5 : 1.0)
                    } else {
                        // Show loading dots when no completions yet (initial load)
                        PulsingDotsView()
                            .frame(width: 200, height: 30)
                    }

                    // Loading overlay indicator
                    if viewModel.isLoading && !viewModel.completions.isEmpty {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                PulsingDotsView()
                                    .frame(width: 60, height: 20)
                                    .padding(8)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .frame(minWidth: (!viewModel.completions.isEmpty || viewModel.currentDepth > 0) ? 550 : 200,
               maxWidth: (!viewModel.completions.isEmpty || viewModel.currentDepth > 0) ? 650 : 200,
               minHeight: (!viewModel.completions.isEmpty || viewModel.currentDepth > 0) ? 60 : 30)
        .padding(.horizontal, (!viewModel.completions.isEmpty || viewModel.currentDepth > 0) ? 16 : 12)
        .padding(.vertical, (!viewModel.completions.isEmpty || viewModel.currentDepth > 0) ? 16 : 8)
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
    let option: CompletionOption
    let isSelected: Bool
    let depth: Int

    var body: some View {
        HStack(spacing: 12) {
            // Keyword (flexible width with max constraint to keep dots aligned)
            Text(option.keyword)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? Color(red: 0.6, green: 0.8, blue: 1.0) : Color.gray.opacity(0.7))
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 160, alignment: .trailing)

            // Dot indicator with gradient
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
                .frame(width: 10, height: 10)

            // Completion text (takes remaining space, truncates if needed)
            Text(option.text)
                .font(.body)
                .foregroundColor(isSelected ? .white : .gray)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

struct PulsingDotsView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 10, height: 10)
                    .scaleEffect(isAnimating ? 1.5 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
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
        CompletionOption(keyword: "brief", text: "and learned."),
        CompletionOption(keyword: "simple", text: "and then I learned something important."),
        CompletionOption(keyword: "consistency", text: "and then I realized that the key to success is consistency."),
        CompletionOption(keyword: "perseverance", text: "and subsequently discovered the importance of perseverance."),
        CompletionOption(keyword: "dedication", text: "and finally understood that dedication leads to mastery, requiring patience and continuous effort.")
    ]
    viewModel.selectedIndex = 2
    // Simulate being at depth 2
    viewModel.keywordPath = ["productivity", "consistency"]
    viewModel.completionHistory = [[], []]

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