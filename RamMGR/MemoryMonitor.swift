//
//  MemoryMonitor.swift
//  RamMGR
//
//  Created by Codex on 4/14/26.
//

import Combine
import Foundation
import SwiftUI
import Darwin

@MainActor
final class MemoryMonitor: ObservableObject {
    @Published private(set) var snapshot = MemorySnapshot.placeholder

    private var timer: Timer?
    private let sampler = MemorySampler()

    init() {
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        Task {
            if let nextSnapshot = sampler.sample() {
                snapshot = nextSnapshot
            }
        }
    }
}

struct MemorySnapshot {
    let pressureFraction: Double
    let usageFraction: Double
    let compressedFraction: Double
    let usedBytes: Double
    let compressedBytes: Double
    let totalBytes: Double

    static let placeholder = MemorySnapshot(
        pressureFraction: 0.0,
        usageFraction: 0.0,
        compressedFraction: 0.0,
        usedBytes: 0.0,
        compressedBytes: 0.0,
        totalBytes: Double(ProcessInfo.processInfo.physicalMemory)
    )

    var pressureText: String {
        "\(Int((pressureFraction * 100).rounded()))%"
    }

    var usageMultilineText: String {
        "\(usedBytes.gigabytesString)\n/\(totalBytes.gigabytesString)"
    }

    var compressedText: String {
        "\(compressedBytes.gigabytesString)\n(compressed)"
    }

    var pressureGradient: LinearGradient {
        Self.gradient(for: pressureFraction, warningThreshold: 0.72, criticalThreshold: 0.88)
    }

    var usageGradient: LinearGradient {
        Self.gradient(for: usageFraction, warningThreshold: 0.72, criticalThreshold: 0.9)
    }

    private static func gradient(
        for fraction: Double,
        warningThreshold: Double,
        criticalThreshold: Double
    ) -> LinearGradient {
        if fraction >= criticalThreshold {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.45),
                    Color(red: 0.98, green: 0.31, blue: 0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        if fraction >= warningThreshold {
            return LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.94, blue: 0.48),
                    Color(red: 1.0, green: 0.79, blue: 0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.40, green: 0.98, blue: 0.78),
                Color(red: 0.14, green: 0.78, blue: 0.74)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private actor MemorySampler {
    private let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

    nonisolated func sample() -> MemorySnapshot? {
        guard
            let memoryPressureOutput = CommandRunner.run(
                "/usr/bin/memory_pressure",
                arguments: ["-Q"]
            ),
            let vmStatOutput = CommandRunner.run(
                "/usr/bin/vm_stat",
                arguments: []
            ),
            let freePercent = parseFreePercent(from: memoryPressureOutput),
            let vmStats = parseVMStat(vmStatOutput)
        else {
            return nil
        }

        let pageSize = vmStats.pageSize
        let freePages = vmStats.values["Pages free"] ?? 0
        let speculativePages = vmStats.values["Pages speculative"] ?? 0
        let fileBackedPages = vmStats.values["File-backed pages"] ?? 0
        let compressorFootprintPages = vmStats.values["Pages occupied by compressor"] ?? 0

        // Activity Monitor's "Memory Used" lines up much better with total physical
        // memory minus free/speculative pages and file-backed cached pages.
        let availableBytes = (freePages + speculativePages + fileBackedPages) * pageSize
        let usedBytes = clamp(totalBytes - availableBytes, lower: 0, upper: totalBytes)
        let compressedBytes = min(compressorFootprintPages * pageSize, usedBytes)
        let pressureLevel = MemoryPressureReader.currentLevel()
        let pressureFraction = pressureFraction(
            freePercent: freePercent,
            pressureLevel: pressureLevel
        )
        let usageFraction = clamp(usedBytes / totalBytes)
        let compressedFraction = clamp(compressedBytes / totalBytes)

        return MemorySnapshot(
            pressureFraction: pressureFraction,
            usageFraction: usageFraction,
            compressedFraction: compressedFraction,
            usedBytes: usedBytes,
            compressedBytes: compressedBytes,
            totalBytes: totalBytes
        )
    }

    private nonisolated func parseFreePercent(from output: String) -> Double? {
        guard
            let match = output.captureGroup(for: #"System-wide memory free percentage:\s*(\d+)%"#),
            let value = Double(match)
        else {
            return nil
        }

        return value
    }

    private nonisolated func parseVMStat(_ output: String) -> ParsedVMStat? {
        let lines = output.split(separator: "\n").map(String.init)
        guard let header = lines.first else {
            return nil
        }

        guard
            let match = header.captureGroup(for: #"page size of\s+(\d+)\s+bytes"#),
            let pageSize = Double(match)
        else {
            return nil
        }

        var values: [String: Double] = [:]

        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }

            let key = pieces[0]
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let rawValue = pieces[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ".", with: "")

            if let value = Double(rawValue) {
                values[key] = value
            }
        }

        return ParsedVMStat(pageSize: pageSize, values: values)
    }

    private nonisolated func pressureFraction(
        freePercent: Double,
        pressureLevel: MemoryPressureLevel?
    ) -> Double {
        let rawPressure = clamp(1.0 - (freePercent / 100.0))

        guard let pressureLevel else {
            return rawPressure
        }

        switch pressureLevel {
        case .normal:
            return clamp(rawPressure * 0.45, lower: 0.05, upper: 0.34)
        case .warning:
            return clamp(0.35 + (rawPressure * 0.45), lower: 0.35, upper: 0.74)
        case .critical:
            return clamp(0.75 + (rawPressure * 0.25), lower: 0.75, upper: 1.0)
        }
    }
}

private struct ParsedVMStat {
    let pageSize: Double
    let values: [String: Double]
}

private enum CommandRunner {
    nonisolated static func run(_ executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private enum MemoryPressureLevel {
    case normal
    case warning
    case critical
}

private enum MemoryPressureReader {
    nonisolated static func currentLevel() -> MemoryPressureLevel? {
        var value = Int32(0)
        var size = MemoryLayout<Int32>.size

        let result = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &value,
            &size,
            nil,
            0
        )

        guard result == 0 else {
            return nil
        }

        switch value {
        case 0, 1:
            return .normal
        case 2:
            return .warning
        default:
            return .critical
        }
    }
}

nonisolated private func clamp(_ value: Double) -> Double {
    clamp(value, lower: 0, upper: 1)
}

nonisolated private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

private extension String {
    nonisolated func captureGroup(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        guard
            let match = regex.firstMatch(in: self, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: self)
        else {
            return nil
        }

        return String(self[captureRange])
    }
}

private extension Double {
    nonisolated var gigabytesString: String {
        let value = self / 1_073_741_824
        return String(format: "%.2fGB", value)
    }
}
