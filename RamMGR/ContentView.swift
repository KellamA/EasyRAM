//
//  ContentView.swift
//  RamMGR
//
//  Created by Kellam Adams on 4/14/26.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var memoryMonitor = MemoryMonitor()

    var body: some View {
        ZStack {
            WindowConfigurator()

            HStack(spacing: 10) {
                MeterCard(
                    title: "Pressure",
                    valueText: memoryMonitor.snapshot.pressureText,
                    multilineValue: false,
                    fillFraction: memoryMonitor.snapshot.pressureFraction,
                    fillGradient: memoryMonitor.snapshot.pressureGradient,
                    detailText: nil,
                    detailFraction: 0
                )

                MeterCard(
                    title: "Usage",
                    valueText: memoryMonitor.snapshot.usageMultilineText,
                    multilineValue: true,
                    fillFraction: memoryMonitor.snapshot.usageFraction,
                    fillGradient: memoryMonitor.snapshot.usageGradient,
                    detailText: memoryMonitor.snapshot.compressedText,
                    detailFraction: memoryMonitor.snapshot.compressedFraction
                )
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.55))
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 6)
                }
        }
        .padding(8)
        .frame(width: 309, height: 320)
        .background(Color.clear)
    }
}

private struct MeterCard: View {
    let title: String
    let valueText: String
    let multilineValue: Bool
    let fillFraction: Double
    let fillGradient: LinearGradient
    let detailText: String?
    let detailFraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                Spacer()
            }

            GeometryReader { geometry in
                let meterHeight = geometry.size.height
                let fillHeight = max(geometry.size.height * fillFraction, 44)
                let detailHeight = geometry.size.height * detailFraction

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fillGradient)
                        .frame(height: min(fillHeight, meterHeight - 12))
                        .padding(8)
                        .overlay(alignment: .bottom) {
                            if let detailText, detailFraction > 0 {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.black.opacity(0.18))
                                    .frame(height: max(min(detailHeight, meterHeight - 28), 22))
                                    .padding(.horizontal, 3)
                                    .padding(.bottom, 3)
                                    .overlay(alignment: .bottom) {
                                        Text(detailText)
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.92))
                                            .multilineTextAlignment(.center)
                                            .minimumScaleFactor(0.55)
                                            .lineLimit(2)
                                            .padding(.horizontal, 8)
                                            .padding(.bottom, 8)
                                    }
                            }
                        }
                        .overlay(alignment: .top) {
                            Text(valueText)
                                .font(.system(size: multilineValue ? 15 : 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .lineSpacing(1)
                                .minimumScaleFactor(0.45)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(multilineValue ? 2 : 1)
                                .padding(.horizontal, 10)
                                .padding(.top, 14)
                        }
                        .animation(.easeInOut(duration: 0.35), value: fillFraction)
                        .animation(.easeInOut(duration: 0.35), value: detailFraction)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.backgroundColor = .clear
            window.isOpaque = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
