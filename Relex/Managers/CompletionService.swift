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

    func generateCompletions(context: String, refinementKeyword: String? = nil) async throws -> [CompletionOption] {
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

        // Build system prompt based on whether this is a refinement
        let systemPrompt: String
        if let keyword = refinementKeyword {
            systemPrompt = """
You are **ReLex**, an AI text completion assistant like GitHub Copilot or Gmail Smart Compose.
The user has selected the keyword "\(keyword)" and wants 5 variations that DIRECTLY incorporate this concept into the completion.

CRITICAL: Each completion MUST explicitly reference or embody the concept of "\(keyword)" in its text. Don't just vaguely relate to it - make the keyword central to what you're completing.

Generate exactly 5 distinct completion options that progressively explore "\(keyword)":
- Option 1: Shortest, most direct reference to "\(keyword)"
- Option 2: Brief but natural integration of "\(keyword)"
- Option 3: Balanced completion featuring "\(keyword)" (DEFAULT)
- Option 4: Detailed completion emphasizing "\(keyword)"
- Option 5: Most comprehensive completion deeply exploring "\(keyword)"

CRITICAL RULES:
1. Output ONLY the continuation/completion - never repeat the input
2. Each completion MUST clearly incorporate the "\(keyword)" concept
3. Make the keyword the central focus of each completion
4. Do NOT greet, ask questions, or treat this as conversation
5. Keep each under 80 tokens
6. Make them meaningfully different in how they explore "\(keyword)"
7. Match the tone and style of the input

Examples of refinement:

Input: "I need to"
Selected keyword: "deadline"
Refined options focusing on DEADLINE:
1. keyword: "urgent", text: " finish this by end of day."
2. keyword: "specific date", text: " complete the project by Friday."
3. keyword: "time pressure", text: " meet the deadline we set with the client next week."
4. keyword: "multiple deadlines", text: " prioritize tasks since we have several deadlines approaching this month."
5. keyword: "tight schedule", text: " work efficiently because we're facing a very tight deadline - everything needs to be done and reviewed by Thursday at 3 PM."

Input: "The software update"
Selected keyword: "new features"
Refined options focusing on NEW FEATURES:
1. keyword: "added", text: " includes new features."
2. keyword: "improvements", text: " brings several new features and improvements."
3. keyword: "major additions", text: " introduces exciting new features like dark mode and voice commands."
4. keyword: "comprehensive", text: " delivers a comprehensive suite of new features including AI assistance, collaborative editing, and advanced analytics."
5. keyword: "detailed list", text: " includes an extensive range of new features: real-time collaboration, intelligent auto-complete, customizable workflows, advanced reporting dashboards, and seamless third-party integrations."
"""
        } else {
            systemPrompt = """
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
"""
        }

        // Add examples and formatting instructions if not in refinement mode
        let fullSystemPrompt: String
        if refinementKeyword == nil {
            fullSystemPrompt = systemPrompt + """

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
        } else {
            fullSystemPrompt = systemPrompt + """

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
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": fullSystemPrompt
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
