//
//  CompletionResult.swift
//  Relex
//
//  Created by Theo Depraetere on 08/10/2025.
//

import Foundation

struct CompletionResult: Identifiable, Codable {
    let id: UUID
    let context: String
    let completion: String
    let timestamp: Date
    let accepted: Bool

    init(context: String, completion: String, accepted: Bool = false) {
        self.id = UUID()
        self.context = context
        self.completion = completion
        self.timestamp = Date()
        self.accepted = accepted
    }
}

struct CompletionState {
    var isVisible: Bool = false
    var context: String = ""
    var completion: String?
    var isLoading: Bool = false
    var error: String?
    var cursorPosition: CGPoint?
}
