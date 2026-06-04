//
//  MemoryMonitor.swift
//  RamMGR
//
//  Created by Codex on 4/14/26.
//

import Combine
import Darwin
import Darwin.Mach
import Foundation
import SwiftUI

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
        guard let vmStats = VMStatistics.current() else {
            return nil
        }

        let appBytes = vmStats.anonymousBytes
        let wiredBytes = vmStats.wiredBytes
        let compressedBytes = vmStats.compressedBytes
        let usedBytes = clamp(appBytes + wiredBytes + compressedBytes, lower: 0, upper: totalBytes)
        let pressureLevel = MemoryPressureReader.currentLevel()
        let availablePercent = MemoryPressureReader.currentAvailablePercent(vmStats: vmStats)
        let pressureFraction = pressureFraction(
            availablePercent: availablePercent,
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

    private nonisolated func pressureFraction(
        availablePercent: Double,
        pressureLevel: MemoryPressureLevel?
    ) -> Double {
        let rawPressure = clamp(1.0 - (availablePercent / 100.0))

        guard let pressureLevel else {
            return rawPressure
        }

        switch pressureLevel {
        case .normal:
            return rawPressure
        case .warning:
            return max(rawPressure, 0.5)
        case .critical:
            return max(rawPressure, 0.8)
        }
    }
}

private enum MemoryPressureLevel {
    case normal
    case warning
    case critical
}

private struct VMStatistics {
    let pageSize: Double
    let freePages: Double
    let speculativePages: Double
    let purgeablePages: Double
    let fileBackedPages: Double
    let anonymousPages: Double
    let wiredPages: Double
    let compressorPages: Double

    nonisolated var anonymousBytes: Double {
        anonymousPages * pageSize
    }

    nonisolated var wiredBytes: Double {
        wiredPages * pageSize
    }

    nonisolated var compressedBytes: Double {
        compressorPages * pageSize
    }

    nonisolated var reclaimableBytes: Double {
        (freePages + speculativePages + purgeablePages + fileBackedPages) * pageSize
    }

    nonisolated static func current() -> VMStatistics? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return VMStatistics(
            pageSize: Double(vm_kernel_page_size),
            freePages: Double(stats.free_count),
            speculativePages: Double(stats.speculative_count),
            purgeablePages: Double(stats.purgeable_count),
            fileBackedPages: Double(stats.external_page_count),
            anonymousPages: Double(stats.internal_page_count),
            wiredPages: Double(stats.wire_count),
            compressorPages: Double(stats.compressor_page_count)
        )
    }
}

private enum MemoryPressureReader {
    nonisolated static func currentAvailablePercent(vmStats: VMStatistics) -> Double {
        if let kernelLevel = intSysctl(named: "kern.memorystatus_level") {
            return clamp(Double(kernelLevel), lower: 0, upper: 100)
        }

        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else {
            return 0
        }

        return clamp((vmStats.reclaimableBytes / totalBytes) * 100, lower: 0, upper: 100)
    }

    nonisolated static func currentLevel() -> MemoryPressureLevel? {
        guard let value = intSysctl(named: "kern.memorystatus_vm_pressure_level") else {
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

    private nonisolated static func intSysctl(named name: String) -> Int32? {
        var value = Int32(0)
        var size = MemoryLayout<Int32>.size

        let result = sysctlbyname(
            name,
            &value,
            &size,
            nil,
            0
        )

        guard result == 0, size == MemoryLayout<Int32>.size else {
            return nil
        }

        return value
    }
}

nonisolated private func clamp(_ value: Double) -> Double {
    clamp(value, lower: 0, upper: 1)
}

nonisolated private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

private extension Double {
    nonisolated var gigabytesString: String {
        let value = self / 1_073_741_824
        return String(format: "%.2fGB", value)
    }
}
