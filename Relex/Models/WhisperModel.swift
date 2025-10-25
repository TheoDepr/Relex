//
//  WhisperModel.swift
//  Relex
//
//  Created by Theo Depraetere on 25/10/2025.
//

import Foundation

enum WhisperModel: String, CaseIterable, Codable {
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMini = "gpt-4o-mini-transcribe"
    case gpt4oDiarize = "gpt-4o-transcribe-diarize"

    var displayName: String {
        switch self {
        case .gpt4oTranscribe:
            return "gpt-4o-transcribe"
        case .gpt4oMini:
            return "gpt-4o-mini-transcribe"
        case .gpt4oDiarize:
            return "gpt-4o-transcribe-diarize"
        }
    }

    var costPerMinute: Double {
        switch self {
        case .gpt4oTranscribe:
            return 0.006
        case .gpt4oMini:
            return 0.003
        case .gpt4oDiarize:
            return 0.006
        }
    }

    var description: String {
        switch self {
        case .gpt4oTranscribe:
            return "Standard quality, $0.006/min"
        case .gpt4oMini:
            return "50% cheaper, $0.003/min"
        case .gpt4oDiarize:
            return "Speaker identification, $0.006/min"
        }
    }
}
