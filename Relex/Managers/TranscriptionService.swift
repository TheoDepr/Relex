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

    private let apiURL = "https://api.openai.com/v1/audio/transcriptions"
    private let model = "whisper-1"

    // Reuse API key from UserDefaults (same as CompletionService)
    var apiKey: String {
        return UserDefaults.standard.string(forKey: "OpenAIAPIKey") ?? ""
    }

    func transcribe(audioFileURL: URL, context: String?) async throws -> String {
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
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add language parameter (optional but helps accuracy)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)

        // Add prompt with context (helps with accuracy and punctuation)
        if let context = context, !context.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(context)\r\n".data(using: .utf8)!)
        }

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

        print("✅ Transcription successful: \"\(text)\"")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
