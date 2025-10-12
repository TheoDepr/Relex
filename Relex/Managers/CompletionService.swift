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

    func generateCompletions(context: String, refinementKeywords: [String] = []) async throws -> [CompletionOption] {
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
        if !refinementKeywords.isEmpty {
            let keywordChain = refinementKeywords.joined(separator: " > ")
            let currentKeyword = refinementKeywords.last!

            systemPrompt = """
You are **ReLex**, an AI text completion assistant like GitHub Copilot or Gmail Smart Compose.
The user has drilled down through these keywords: "\(keywordChain)"
Currently focusing on: "\(currentKeyword)"

CONTEXT: The full keyword path shows the user's refined intent through multiple levels of exploration.
- All previous keywords (\(refinementKeywords.dropLast().joined(separator: ", "))) provide context for what the user is seeking
- The current keyword "\(currentKeyword)" is the immediate focus to explore

CRITICAL: Each completion MUST embody the concept of "\(currentKeyword)" within the broader context of the keyword chain, but should NOT simply repeat the exact word "\(currentKeyword)".
Use related words, synonyms, or ways to express the same concept naturally in the sentence.

Generate exactly 5 distinct completion options that progressively explore "\(currentKeyword)" in the context of "\(keywordChain)":
The 5 options should further find the goal of the user based on their keyword exploration path.
- Option 1: Shortest, most direct way to convey the "\(currentKeyword)" concept
- Option 2: Brief but natural expression of the "\(currentKeyword)" idea
- Option 3: Balanced completion expressing "\(currentKeyword)" concept (DEFAULT)
- Option 4: Detailed completion emphasizing the "\(currentKeyword)" theme
- Option 5: Most comprehensive completion deeply exploring "\(currentKeyword)" meaning

CRITICAL RULES:
1. Output ONLY the continuation/completion - never repeat the input
2. Your completion MUST flow naturally from the EXACT LAST WORDS in the input text
3. DO NOT use the exact word "\(currentKeyword)" in your completions - use synonyms, related terms, or natural expressions of the concept
4. Consider the full keyword path (\(keywordChain)) when crafting completions - the earlier keywords inform the direction and intent
5. LANGUAGE MATCHING: Generate keywords in the SAME LANGUAGE as the input context text
   - If input is in English, keywords must be in English
   - If input is in French, keywords must be in French
   - If input is in Spanish, keywords must be in Spanish
   - Match the language naturally - this is critical for user experience
6. Handle spacing correctly - this is CRITICAL:
   - If input ends with a space (e.g., "Sure, " or "I need to "), DO NOT add another space - start directly with the word
   - If input ends WITHOUT a space (e.g., "The software" or "Hello"), add a space before your completion
   - Examples:
     * Input "Sure, " (ends with space) → "I can help" NOT " I can help"
     * Input "I need to " (ends with space) → "finish" NOT " finish"
     * Input "The software" (no space) → " includes" (with space)
     * Input "Hello" (no space) → " there" (with space)
7. SPECIAL CASE - Single character input:
   - If input is just one letter (e.g., "I" or "T"), complete it into a full word first
   - Example: Input "I" → " need to..." or " am working on..." or " believe that..."
   - Example: Input "T" → "he project is..." or "oday I will..." or "his will help..."
8. Each completion MUST clearly embody the "\(currentKeyword)" concept through meaning, informed by the full path
9. Make the "\(currentKeyword)" concept the central focus through natural language
10. Do NOT greet, ask questions, or treat this as conversation
11. Keep each under 80 tokens
12. Make them meaningfully different in how they express the "\(currentKeyword)" idea within the broader context
13. Match the tone and style of the input
14. The completion should read smoothly when appended directly to the input text

Examples of refinement with keyword chains (note how completions express the concept WITHOUT repeating the exact keyword):

Example 1 - Single level:
Input: "I need to "
Keyword chain: "deadline"
Refined options expressing DEADLINE concept:
1. keyword: "urgent", text: "finish this by end of day."
2. keyword: "due date", text: "complete the project by Friday."
3. keyword: "time constraint", text: "get this done before the client meeting next week."
4. keyword: "pressing timeline", text: "prioritize tasks since several things are due this month."
5. keyword: "tight schedule", text: "work efficiently because everything needs to be done and reviewed by Thursday at 3 PM."

Example 2 - Multi-level drill-down:
Input: "I need to "
Keyword chain: "project > deadline > urgent"
Context: User first selected "project", then "deadline", now exploring "urgent"
Refined options expressing URGENT concept in context of project deadlines:
1. keyword: "immediate", text: "complete the critical path items today."
2. keyword: "priority", text: "focus on the high-impact deliverables that block other teams."
3. keyword: "time-sensitive", text: "finish the MVP features before tomorrow's stakeholder demo."
4. keyword: "critical path", text: "resolve the blocking bugs and deploy the hotfix by end of business today."
5. keyword: "emergency mode", text: "coordinate with the team to parallelize work streams and hit tonight's production cutoff."
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
2. Your completion MUST flow naturally from the EXACT LAST WORDS in the input text
3. LANGUAGE MATCHING: Generate keywords and completions in the SAME LANGUAGE as the input context text
   - If input is in English, keywords and completions must be in English
   - If input is in French, keywords and completions must be in French
   - If input is in Spanish, keywords and completions must be in Spanish
   - Match the language naturally - this is critical for user experience
4. Handle spacing correctly - this is CRITICAL:
   - If input ends with a space (e.g., "Sure, " or "I need to "), DO NOT add another space - start directly with the word
   - If input ends WITHOUT a space (e.g., "The software" or "Hello"), add a space before your completion
   - Examples:
     * Input "Sure, " (ends with space) → "I can help" NOT " I can help"
     * Input "I need to " (ends with space) → "finish" NOT " finish"
     * Input "The software" (no space) → " includes" (with space)
     * Input "Hello" (no space) → " there" (with space)
5. SPECIAL CASE - Single character input:
   - If input is just one letter (e.g., "I" or "T"), complete it into a full word first
   - Example: Input "I" → " need to..." or " am working on..." or " believe that..."
   - Example: Input "T" → "he project is..." or "oday I will..." or "his will help..."
6. Each completion should be ONE clear sentence or phrase
7. Do NOT greet, ask questions, or treat this as conversation
8. Keep each under 80 tokens
9. Make them meaningfully different from each other
10. Match the tone and style of the input
11. The completion should read smoothly when appended directly to the input text
"""
        }

        // Add examples and formatting instructions if not in refinement mode
        let fullSystemPrompt: String
        if refinementKeywords.isEmpty {
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

        // Log the request
        print("🤖 ===== LLM REQUEST =====")
        print("Model: \(model)")
        print("Context: \"\(context)\"")
        if !refinementKeywords.isEmpty {
            print("Refinement Keywords: \(refinementKeywords.joined(separator: " > "))")
        }
        print("System Prompt Preview: \(String(fullSystemPrompt.prefix(200)))...")
        print("========================")

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

        // Log the response
        print("🤖 ===== LLM RESPONSE =====")
        print("Raw JSON: \(content)")
        print("Parsed Options:")
        for (index, option) in completionOptions.options.enumerated() {
            print("  \(index + 1). keyword: \"\(option.keyword)\", text: \"\(option.text)\"")
        }
        print("==========================")

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
