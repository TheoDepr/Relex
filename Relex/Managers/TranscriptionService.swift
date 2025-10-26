//
//  TranscriptionService.swift
//  Relex
//
//  Created by Theo Depraetere on 09/10/2025.
//

import Foundation
import Combine

@MainActor
class TranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var selectedModel: WhisperModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedWhisperModel")
        }
    }

    private let apiURL = "https://api.openai.com/v1/audio/transcriptions"
    private let keychainManager = KeychainManager.shared
    private let usageTracker = UsageTracker.shared

    var apiKey: String {
        return keychainManager.getAPIKey()
    }

    init() {
        // Load saved model preference or default to gpt-4o-mini (cheaper)
        if let savedModel = UserDefaults.standard.string(forKey: "selectedWhisperModel"),
           let model = WhisperModel(rawValue: savedModel) {
            self.selectedModel = model
        } else {
            self.selectedModel = .gpt4oMini
        }
    }

    func setAPIKey(_ key: String) {
        do {
            try keychainManager.setAPIKey(key)
        } catch {
            print("❌ Failed to save API key: \(error.localizedDescription)")
            lastError = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    func transcribe(audioFileURL: URL, context: String?, durationSeconds: TimeInterval) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }

        isTranscribing = true
        lastError = nil

        defer {
            Task { @MainActor in
                isTranscribing = false
            }
        }

        // Create multipart/form-data request
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(selectedModel.rawValue)\r\n".data(using: .utf8)!)

        // Add language parameter (optional but helps accuracy)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)

        // Note: Context is NOT sent to Whisper API as it can confuse the model
        // Instead, context is only used for post-processing spacing and capitalization

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)

        let audioData = try Data(contentsOf: audioFileURL)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("📤 Sending transcription request, audio size: \(audioData.count) bytes")

        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                lastError = "API Error: \(httpResponse.statusCode) - \(errorBody)"
                print("❌ Transcription API error: \(errorBody)")
            }
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = json?["text"] as? String else {
            throw TranscriptionError.parsingError
        }

        // Track usage for cost calculation
        usageTracker.trackUsage(durationSeconds: durationSeconds, model: selectedModel)

        print("✅ Transcription successful: \"\(text)\"")

        // Post-process the transcribed text based on context
        let processedText = postProcessTranscription(text, context: context)
        print("✅ Post-processed text: \"\(processedText)\"")

        return processedText
    }

    /// Post-processes transcribed text to ensure proper spacing and capitalization based on context
    private func postProcessTranscription(_ text: String, context: String?) -> String {
        var processedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If no context, just return trimmed text with first letter capitalized
        guard let context = context, !context.isEmpty else {
            print("📝 No context available, capitalizing first letter")
            return processedText.isEmpty ? processedText : processedText.prefix(1).uppercased() + processedText.dropFirst()
        }

        // Check if context is only whitespace
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else {
            print("📝 Empty context, capitalizing first letter")
            return processedText.isEmpty ? processedText : processedText.prefix(1).uppercased() + processedText.dropFirst()
        }

        // For capitalization: find the last meaningful character (before any trailing spaces, but include newlines)
        // Walk backwards through the context, skipping only spaces and tabs (not newlines)
        var lastMeaningfulChar: Character?
        for char in context.reversed() {
            if char == " " || char == "\t" {
                continue
            }
            lastMeaningfulChar = char
            break
        }

        // Sentence-ending punctuation: capitalize first letter
        let sentenceEnders: Set<Character> = [".", "!", "?", "\n"]
        let shouldCapitalize = lastMeaningfulChar.map { sentenceEnders.contains($0) } ?? false

        if shouldCapitalize {
            print("📝 Context ends with sentence ender '\(lastMeaningfulChar!)', capitalizing first letter")
            if !processedText.isEmpty {
                processedText = processedText.prefix(1).uppercased() + processedText.dropFirst()
            }
        } else {
            print("📝 Context is mid-sentence (last char: '\(lastMeaningfulChar?.description ?? "none")'), adjusting capitalization")
            // Mid-sentence: keep lowercase unless the word should be capitalized (like "I")
            if !processedText.isEmpty && processedText.first?.isUppercase == true {
                // Check if this is a word that should always be capitalized
                let firstWord = processedText.components(separatedBy: .whitespaces).first ?? ""
                let alwaysCapitalized = ["I", "I'm", "I'll", "I've", "I'd"]

                if !alwaysCapitalized.contains(firstWord) {
                    print("📝 Converting to lowercase since mid-sentence")
                    processedText = processedText.prefix(1).lowercased() + processedText.dropFirst()
                }
            }
        }

        // For spacing: use ORIGINAL context (not trimmed) to check if space is needed
        // If context ends with any whitespace (space, newline, tab), don't add more
        let lastChar = context.last!
        if lastChar.isWhitespace {
            print("📝 No space needed, context already ends with whitespace: '\\(lastChar.unicodeScalars.first!.value)'")
        } else {
            print("📝 Adding space before transcribed text (last char: '\(lastChar)')")
            processedText = " " + processedText
        }

        return processedText
    }
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case audioFileNotFound
    case invalidResponse
    case apiError(statusCode: Int)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing. Please configure it in settings."
        case .audioFileNotFound:
            return "Audio file not found"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode):
            return "Transcription API Error: HTTP \(statusCode)"
        case .parsingError:
            return "Failed to parse transcription response"
        }
    }
}
