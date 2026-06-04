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
        ZStack(alignment: .top) {
            WindowConfigurator()

            HStack(spacing: 12) {
                MeterColumn(
                    title: "Pressure",
                    valueText: memoryMonitor.snapshot.pressureText,
                    multilineValue: false,
                    fillFraction: memoryMonitor.snapshot.pressureFraction,
                    fillGradient: memoryMonitor.snapshot.pressureGradient,
                    detailText: nil,
                    detailFraction: 0
                )

                MeterColumn(
                    title: "Usage",
                    valueText: memoryMonitor.snapshot.usageMultilineText,
                    multilineValue: true,
                    fillFraction: memoryMonitor.snapshot.usageFraction,
                    fillGradient: memoryMonitor.snapshot.usageGradient,
                    detailText: memoryMonitor.snapshot.compressedText,
                    detailFraction: memoryMonitor.snapshot.compressedFraction
                )
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.62))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
            }

            DraggableTopArea()
                .frame(height: 68)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .padding(8)
        .frame(width: 309, height: 320)
        .background(Color.clear)
    }
}

private struct MeterColumn: View {
    let title: String
    let valueText: String
    let multilineValue: Bool
    let fillFraction: Double
    let fillGradient: LinearGradient
    let detailText: String?
    let detailFraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            GeometryReader { geometry in
                let trackHeight = geometry.size.height
                let fillHeight = min(max(trackHeight * fillFraction, 42), trackHeight)
                let detailHeight = min(max(trackHeight * detailFraction, 22), fillHeight)

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.055))

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fillGradient)
                        .frame(height: fillHeight)
                        .overlay(alignment: .bottom) {
                            if let detailText, detailFraction > 0 {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.black.opacity(0.24))
                                    .frame(height: detailHeight)
                                    .overlay(alignment: .bottom) {
                                        Text(detailText)
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.92))
                                            .multilineTextAlignment(.center)
                                            .minimumScaleFactor(0.55)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineLimit(2)
                                            .padding(.horizontal, 6)
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
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure(window)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}

private struct DraggableTopArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
