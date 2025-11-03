//
//  UsageTracker.swift
//  Relex
//
//  Created by Theo Depraetere on 25/10/2025.
//

import Foundation

struct TranscriptionUsage: Codable {
    let id: UUID
    let timestamp: Date
    let durationSeconds: Double
    let model: WhisperModel
    let cost: Double

    init(durationSeconds: Double, model: WhisperModel) {
        self.id = UUID()
        self.timestamp = Date()
        self.durationSeconds = durationSeconds
        self.model = model
        self.cost = (durationSeconds / 60.0) * model.costPerMinute
    }
}

struct GPTUsage: Codable {
    let id: UUID
    let timestamp: Date
    let promptTokens: Int
    let completionTokens: Int
    let model: GPTModel
    let cost: Double

    init(promptTokens: Int, completionTokens: Int, model: GPTModel) {
        self.id = UUID()
        self.timestamp = Date()
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.model = model

        // Calculate cost based on model pricing (per 1M tokens)
        let costs = model.costPer1MTokens
        let inputCost = (Double(promptTokens) / 1_000_000.0) * costs.input
        let outputCost = (Double(completionTokens) / 1_000_000.0) * costs.output
        self.cost = inputCost + outputCost
    }
}

struct UsageStatistics {
    let totalCost: Double
    let totalRequests: Int
    let totalMinutes: Double
    let usageByModel: [WhisperModel: (count: Int, cost: Double)]
}

struct GPTStatistics {
    let totalCost: Double
    let totalRequests: Int
    let totalTokens: Int
    let usageByModel: [GPTModel: (count: Int, cost: Double, tokens: Int)]
}

class UsageTracker {
    static let shared = UsageTracker()

    private let transcriptionFileURL: URL
    private let gptFileURL: URL

    private var transcriptionHistory: [TranscriptionUsage] = []
    private var gptHistory: [GPTUsage] = []

    private init() {
        // Use Application Support directory for persistent storage
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("Relex", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        transcriptionFileURL = appDirectory.appendingPathComponent("transcription_usage.json")
        gptFileURL = appDirectory.appendingPathComponent("gpt_usage.json")

        loadUsage()
    }

    func trackUsage(durationSeconds: Double, model: WhisperModel) {
        let usage = TranscriptionUsage(durationSeconds: durationSeconds, model: model)
        transcriptionHistory.append(usage)
        saveTranscriptionUsage()

        print("💰 Tracked transcription usage: \(String(format: "%.1f", durationSeconds))s with \(model.rawValue) = $\(String(format: "%.4f", usage.cost))")
    }

    func trackGPTUsage(promptTokens: Int, completionTokens: Int, model: GPTModel) {
        let usage = GPTUsage(promptTokens: promptTokens, completionTokens: completionTokens, model: model)
        gptHistory.append(usage)
        saveGPTUsage()

        let totalTokens = promptTokens + completionTokens
        print("💰 Tracked GPT usage: \(totalTokens) tokens with \(model.rawValue) = $\(String(format: "%.4f", usage.cost))")
    }

    func getStatistics(since date: Date? = nil) -> UsageStatistics {
        let filteredUsage = if let date = date {
            transcriptionHistory.filter { $0.timestamp >= date }
        } else {
            transcriptionHistory
        }

        let totalCost = filteredUsage.reduce(0.0) { $0 + $1.cost }
        let totalRequests = filteredUsage.count
        let totalMinutes = filteredUsage.reduce(0.0) { $0 + ($1.durationSeconds / 60.0) }

        var usageByModel: [WhisperModel: (count: Int, cost: Double)] = [:]
        for usage in filteredUsage {
            let current = usageByModel[usage.model] ?? (count: 0, cost: 0.0)
            usageByModel[usage.model] = (count: current.count + 1, cost: current.cost + usage.cost)
        }

        return UsageStatistics(
            totalCost: totalCost,
            totalRequests: totalRequests,
            totalMinutes: totalMinutes,
            usageByModel: usageByModel
        )
    }

    func getGPTStatistics(since date: Date? = nil) -> GPTStatistics {
        let filteredUsage = if let date = date {
            gptHistory.filter { $0.timestamp >= date }
        } else {
            gptHistory
        }

        let totalCost = filteredUsage.reduce(0.0) { $0 + $1.cost }
        let totalRequests = filteredUsage.count
        let totalTokens = filteredUsage.reduce(0) { $0 + $1.promptTokens + $1.completionTokens }

        var usageByModel: [GPTModel: (count: Int, cost: Double, tokens: Int)] = [:]
        for usage in filteredUsage {
            let current = usageByModel[usage.model] ?? (count: 0, cost: 0.0, tokens: 0)
            let tokens = usage.promptTokens + usage.completionTokens
            usageByModel[usage.model] = (
                count: current.count + 1,
                cost: current.cost + usage.cost,
                tokens: current.tokens + tokens
            )
        }

        return GPTStatistics(
            totalCost: totalCost,
            totalRequests: totalRequests,
            totalTokens: totalTokens,
            usageByModel: usageByModel
        )
    }

    func getTodayStatistics() -> UsageStatistics {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return getStatistics(since: startOfDay)
    }

    func getThisMonthStatistics() -> UsageStatistics {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        let startOfMonth = calendar.date(from: components)!
        return getStatistics(since: startOfMonth)
    }

    func getTodayGPTStatistics() -> GPTStatistics {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return getGPTStatistics(since: startOfDay)
    }

    func getThisMonthGPTStatistics() -> GPTStatistics {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        let startOfMonth = calendar.date(from: components)!
        return getGPTStatistics(since: startOfMonth)
    }

    func resetUsage() {
        transcriptionHistory.removeAll()
        gptHistory.removeAll()
        saveTranscriptionUsage()
        saveGPTUsage()
        print("🗑️ Usage history reset")
    }

    private func loadUsage() {
        // Load transcription usage
        if FileManager.default.fileExists(atPath: transcriptionFileURL.path) {
            do {
                let data = try Data(contentsOf: transcriptionFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                transcriptionHistory = try decoder.decode([TranscriptionUsage].self, from: data)
                print("📊 Loaded \(transcriptionHistory.count) transcription records")
            } catch {
                print("❌ Failed to load transcription usage data: \(error)")
            }
        } else {
            // Try legacy file path for backward compatibility
            let legacyFileURL = transcriptionFileURL.deletingLastPathComponent().appendingPathComponent("usage.json")
            if FileManager.default.fileExists(atPath: legacyFileURL.path) {
                do {
                    let data = try Data(contentsOf: legacyFileURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    transcriptionHistory = try decoder.decode([TranscriptionUsage].self, from: data)
                    print("📊 Migrated \(transcriptionHistory.count) transcription records from legacy file")
                    saveTranscriptionUsage() // Save to new location
                    try? FileManager.default.removeItem(at: legacyFileURL) // Clean up old file
                } catch {
                    print("❌ Failed to migrate legacy usage data: \(error)")
                }
            } else {
                print("📊 No existing transcription usage data found")
            }
        }

        // Load GPT usage
        if FileManager.default.fileExists(atPath: gptFileURL.path) {
            do {
                let data = try Data(contentsOf: gptFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                gptHistory = try decoder.decode([GPTUsage].self, from: data)
                print("📊 Loaded \(gptHistory.count) GPT usage records")
            } catch {
                print("❌ Failed to load GPT usage data: \(error)")
            }
        } else {
            print("📊 No existing GPT usage data found")
        }
    }

    private func saveTranscriptionUsage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(transcriptionHistory)
            try data.write(to: transcriptionFileURL, options: .atomic)
        } catch {
            print("❌ Failed to save transcription usage data: \(error)")
        }
    }

    private func saveGPTUsage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(gptHistory)
            try data.write(to: gptFileURL, options: .atomic)
        } catch {
            print("❌ Failed to save GPT usage data: \(error)")
        }
    }
}
