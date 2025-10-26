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

struct UsageStatistics {
    let totalCost: Double
    let totalRequests: Int
    let totalMinutes: Double
    let usageByModel: [WhisperModel: (count: Int, cost: Double)]
}

class UsageTracker {
    static let shared = UsageTracker()

    private let storageKey = "com.relex.transcriptionUsage"
    private let fileURL: URL

    private var usageHistory: [TranscriptionUsage] = []

    private init() {
        // Use Application Support directory for persistent storage
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("Relex", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        fileURL = appDirectory.appendingPathComponent("usage.json")

        loadUsage()
    }

    func trackUsage(durationSeconds: Double, model: WhisperModel) {
        let usage = TranscriptionUsage(durationSeconds: durationSeconds, model: model)
        usageHistory.append(usage)
        saveUsage()

        print("💰 Tracked usage: \(String(format: "%.1f", durationSeconds))s with \(model.rawValue) = $\(String(format: "%.4f", usage.cost))")
    }

    func getStatistics(since date: Date? = nil) -> UsageStatistics {
        let filteredUsage = if let date = date {
            usageHistory.filter { $0.timestamp >= date }
        } else {
            usageHistory
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

    func resetUsage() {
        usageHistory.removeAll()
        saveUsage()
        print("🗑️ Usage history reset")
    }

    private func loadUsage() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("📊 No existing usage data found")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            usageHistory = try decoder.decode([TranscriptionUsage].self, from: data)
            print("📊 Loaded \(usageHistory.count) usage records")
        } catch {
            print("❌ Failed to load usage data: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }

    private func saveUsage() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(usageHistory)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ Failed to save usage data: \(error)")
        }
    }
}
