//
//  CompletionService.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import Foundation
import Combine

// MARK: - Models for Structured Output
struct CompletionOptions: Codable {
    let options: [CompletionOption]
}

struct CompletionOption: Codable {
    let text: String
}

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

    func generateCompletions(context: String) async throws -> [String] {
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
                    "content": """
You are **ReLex**, an AI text completion assistant like GitHub Copilot or Gmail Smart Compose.
Your job: given text before the cursor, predict what comes next. This is NOT a chat - you're completing inline text.

Generate exactly 3 distinct completion options as variations of how to continue the text:
- Option 1: Most natural/likely continuation
- Option 2: Alternative style or direction
- Option 3: Creative or different approach

CRITICAL RULES:
1. Output ONLY the continuation/completion - never repeat the input
2. Each completion should be ONE clear sentence or phrase
3. Do NOT greet, ask questions, or treat this as conversation
4. Keep each under 80 tokens
5. Make them meaningfully different from each other
6. Match the tone and style of the input

Examples:

Input: "I'm working on"
Options:
1. " a new project that should be finished by next week."
2. " improving my productivity and time management skills."
3. " several tasks at once, but making good progress."

Input: "The meeting is scheduled for tomorrow at"
Options:
1. " 2:00 PM in the conference room."
2. " 10:00 AM, so please be there on time."
3. " 3:30 PM via Zoom."

Input: "Could you please send me"
Options:
1. " the updated document when you get a chance?"
2. " those files we discussed earlier today?"
3. " your feedback by end of day?"

Input: "I really appreciate"
Options:
1. " your help with this project."
2. " all the hard work you've put in."
3. " you taking the time to explain this to me."

Input: "Based on the data,"
Options:
1. " we can see a clear upward trend in sales."
2. " it appears that our strategy is working effectively."
3. " I recommend we proceed with the proposed changes."

Return as JSON with this structure:
{
  "options": [
    {"text": "completion 1"},
    {"text": "completion 2"},
    {"text": "completion 3"}
  ]
}
"""
                ],
                [
                    "role": "user",
                    "content": context
                ]
            ],
            "max_tokens": 250,
            "temperature": 0.8,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "completion_options",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "options": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "text": ["type": "string"]
                                    ],
                                    "required": ["text"],
                                    "additionalProperties": false
                                ]
                            ]
                        ],
                        "required": ["options"],
                        "additionalProperties": false
                    ]
                ]
            ]
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

        // Parse the structured JSON content
        guard let contentData = content.data(using: .utf8) else {
            throw CompletionError.parsingError
        }

        let decoder = JSONDecoder()
        let completionOptions = try decoder.decode(CompletionOptions.self, from: contentData)

        // Extract just the text from each option
        let completions = completionOptions.options.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Ensure we have at least 3 options, pad with empty if needed
        guard completions.count >= 3 else {
            throw CompletionError.insufficientOptions
        }

        return Array(completions.prefix(3))
    }
}

enum CompletionError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case parsingError
    case insufficientOptions

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
        case .insufficientOptions:
            return "API did not return enough completion options"
        }
    }
}
