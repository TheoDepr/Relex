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
    let keyword: String
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

    func generateCompletions(context: String) async throws -> [CompletionOption] {
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

Generate exactly 5 distinct completion options as variations of how to continue the text:
- Option 1: Short and concise continuation
- Option 2: Natural/likely continuation
- Option 3: Most balanced and common approach (DEFAULT)
- Option 4: Alternative style or direction
- Option 5: Creative or expansive approach

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
1. keyword: "brief update", text: " this now."
2. keyword: "current task", text: " a new project."
3. keyword: "project deadline", text: " a new project that should be finished by next week."
4. keyword: "productivity", text: " improving my productivity and time management skills."
5. keyword: "multitasking", text: " several tasks at once while also planning the next sprint."

Input: "The meeting is scheduled for tomorrow at"
Options:
1. keyword: "time only", text: " 2 PM."
2. keyword: "morning slot", text: " 10:00 AM."
3. keyword: "afternoon slot", text: " 2:00 PM in the conference room."
4. keyword: "detailed time", text: " 10:00 AM, so please be there on time."
5. keyword: "virtual meeting", text: " 3:30 PM via Zoom - I'll send the calendar invite with all the details."

Input: "Could you please send me"
Options:
1. keyword: "brief request", text: " the files?"
2. keyword: "document", text: " the updated document?"
3. keyword: "files request", text: " those files we discussed earlier today?"
4. keyword: "detailed ask", text: " the updated document when you get a chance?"
5. keyword: "urgent request", text: " your feedback by end of day so we can move forward with the proposal?"

Input: "I really appreciate"
Options:
1. keyword: "simple thanks", text: " it."
2. keyword: "your help", text: " your help."
3. keyword: "project help", text: " your help with this project."
4. keyword: "hard work", text: " all the hard work you've put in."
5. keyword: "detailed thanks", text: " you taking the time to explain this to me and answer all my questions."

Input: "Based on the data,"
Options:
1. keyword: "brief insight", text: " sales are up."
2. keyword: "trend", text: " we see growth."
3. keyword: "sales trend", text: " we can see a clear upward trend in sales."
4. keyword: "strategy", text: " it appears that our strategy is working effectively."
5. keyword: "recommendation", text: " I recommend we proceed with the proposed changes and allocate additional resources."

IMPORTANT: Keywords should be 1-3 words that capture the essence of each completion option.

Return as JSON with this structure:
{
  "options": [
    {"keyword": "brief summary", "text": "completion 1"},
    {"keyword": "brief summary", "text": "completion 2"},
    {"keyword": "brief summary", "text": "completion 3"},
    {"keyword": "brief summary", "text": "completion 4"},
    {"keyword": "brief summary", "text": "completion 5"}
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
                                        "keyword": ["type": "string"],
                                        "text": ["type": "string"]
                                    ],
                                    "required": ["keyword", "text"],
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

        // Ensure we have at least 5 options
        guard completionOptions.options.count >= 5 else {
            throw CompletionError.insufficientOptions
        }

        return Array(completionOptions.options.prefix(5))
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
