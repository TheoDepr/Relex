//
//  GPTService.swift
//  Relex
//
//  Created by Claude Code on 03/11/2025.
//

import Foundation
import Combine

@MainActor
class GPTService: ObservableObject {
    @Published var isProcessing = false
    @Published var lastError: String?
    @Published var selectedModel: GPTModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedGPTModel")
        }
    }

    private let apiURL = "https://api.openai.com/v1/chat/completions"
    private let keychainManager = KeychainManager.shared
    private let usageTracker = UsageTracker.shared

    var apiKey: String {
        return keychainManager.getAPIKey()
    }

    init() {
        // Load saved model preference or default to gpt-4o-mini (cheaper)
        if let savedModel = UserDefaults.standard.string(forKey: "selectedGPTModel"),
           let model = GPTModel(rawValue: savedModel) {
            self.selectedModel = model
        } else {
            self.selectedModel = .gpt4oMini
        }
    }

    /// Process a text command by sending selected text and voice command to GPT
    /// - Parameters:
    ///   - selectedText: The text that the user selected/highlighted
    ///   - voiceCommand: The transcribed voice command (e.g., "rewrite this better")
    /// - Returns: The transformed text from GPT
    func processTextCommand(selectedText: String, voiceCommand: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GPTError.missingAPIKey
        }

        guard !selectedText.isEmpty else {
            throw GPTError.emptySelectedText
        }

        guard !voiceCommand.isEmpty else {
            throw GPTError.emptyCommand
        }

        isProcessing = true
        lastError = nil

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Build the chat completion request
        let systemMessage = [
            "role": "system",
            "content": "You are a text editor assistant. Transform the provided text according to the user's command. Return only the transformed text without any explanations, preamble, or additional commentary. Do not wrap the result in quotes or add any formatting unless specifically requested. IMPORTANT: If not specified, respect and preserve the original text structure, including line breaks, paragraphs, spacing, and formatting. Keep the same number of lines and paragraphs as the original."
        ]

        let userMessage = [
            "role": "user",
            "content": "Transform this text:\n\n\(selectedText)\n\nCommand: \(voiceCommand)"
        ]

        let requestBody: [String: Any] = [
            "model": selectedModel.rawValue,
            "messages": [systemMessage, userMessage],
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("📤 Sending GPT request:")
        print("   Model: \(selectedModel.rawValue)")
        print("   Selected text length: \(selectedText.count) chars")
        print("   Command: \"\(voiceCommand)\"")

        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GPTError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                lastError = "API Error: \(httpResponse.statusCode) - \(errorBody)"
                print("❌ GPT API error: \(errorBody)")
            }
            throw GPTError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GPTError.parsingError
        }

        // Track usage for cost calculation
        if let usage = json?["usage"] as? [String: Any],
           let promptTokens = usage["prompt_tokens"] as? Int,
           let completionTokens = usage["completion_tokens"] as? Int {
            let totalTokens = promptTokens + completionTokens
            usageTracker.trackGPTUsage(
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                model: selectedModel
            )
            print("✅ GPT processing successful")
            print("   Tokens: \(promptTokens) prompt + \(completionTokens) completion = \(totalTokens) total")
        }

        let transformedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ Transformed text length: \(transformedText.count) chars")

        return transformedText
    }
}

enum GPTModel: String, CaseIterable, Codable {
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"

    var displayName: String {
        switch self {
        case .gpt4o:
            return "GPT-4o"
        case .gpt4oMini:
            return "GPT-4o Mini"
        }
    }

    var costPer1MTokens: (input: Double, output: Double) {
        switch self {
        case .gpt4o:
            return (input: 2.50, output: 10.00)  // $2.50/1M input, $10.00/1M output
        case .gpt4oMini:
            return (input: 0.15, output: 0.60)   // $0.15/1M input, $0.60/1M output
        }
    }

    var description: String {
        switch self {
        case .gpt4o:
            return "Higher quality, ~$0.01 per command"
        case .gpt4oMini:
            return "Fast & cheap, ~$0.001 per command"
        }
    }
}

enum GPTError: LocalizedError {
    case missingAPIKey
    case emptySelectedText
    case emptyCommand
    case invalidResponse
    case apiError(statusCode: Int)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing. Please configure it in settings."
        case .emptySelectedText:
            return "No text selected to transform"
        case .emptyCommand:
            return "No voice command provided"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode):
            return "GPT API Error: HTTP \(statusCode)"
        case .parsingError:
            return "Failed to parse GPT response"
        }
    }
}
