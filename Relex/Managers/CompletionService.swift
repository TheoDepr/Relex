//
//  CompletionService.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import Foundation
import Combine

@MainActor
class CompletionService: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?

    var apiKey: String {
        return UserDefaults.standard.string(forKey: "OpenAIAPIKey") ?? ""
    }

    private let apiURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"

    init() {}

    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "OpenAIAPIKey")
        objectWillChange.send()
    }

    func generateCompletion(context: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw CompletionError.missingAPIKey
        }

        isLoading = true
        lastError = nil

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        // Prepare the request
        guard let url = URL(string: apiURL) else {
            throw CompletionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a text completion assistant. The user will provide partial text, and you should continue it naturally. ONLY output the continuation/completion text - do NOT repeat what the user wrote, do NOT ask questions, do NOT provide explanations. Just complete their sentence or thought as if you were autocomplete."
                ],
                [
                    "role": "user",
                    "content": "Complete this text: \(context)"
                ]
            ],
            "max_tokens": 100,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Perform the request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompletionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                lastError = "API Error: \(httpResponse.statusCode) - \(errorBody)"
            }
            throw CompletionError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse the response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CompletionError.parsingError
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CompletionError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing. Please configure it in settings."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode):
            return "API Error: HTTP \(statusCode)"
        case .parsingError:
            return "Failed to parse API response"
        }
    }
}
