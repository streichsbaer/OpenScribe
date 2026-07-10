import SwiftUI

struct AudioLevelIndicatorView: View {
    @EnvironmentObject private var audioMeter: AudioMeterState

    let permissionState: MicrophonePermissionState
    let trackWidth: CGFloat
    let trackHeight: CGFloat
    private let cornerRadius: CGFloat = 9
    private let strokeOpacity: CGFloat = 0.08

    private var fillColor: Color {
        switch permissionState {
        case .authorized:
            return audioMeter.snapshot.isActive ? .green : .gray
        case .denied, .undetermined:
            return .gray
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.5))

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.18))

                Capsule()
                    .fill(fillColor)
                    .frame(width: max(4, normalizedMeterLevel * trackWidth))
            }
            .frame(width: trackWidth, height: trackHeight)
        }
    }

    private var normalizedMeterLevel: CGFloat {
        let minimumDBFS: Float = -60
        let maximumDBFS: Float = -6
        let bounded = min(max(audioMeter.snapshot.levelDBFS, minimumDBFS), maximumDBFS)
        return CGFloat((bounded - minimumDBFS) / (maximumDBFS - minimumDBFS))
    }
}

struct TranscriptPopupView: View {
    let title: String
    let text: String
    let sourceSummary: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(sourceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 320)
    }
}

/// App logo matching the adaptive SVG geometry from site-docs/images/logo.svg.
/// Uses .primary foreground so it adapts to light and dark mode automatically.
struct OpenScribeLogo: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 18.0
            let center = CGPoint(x: 9 * scale, y: 9 * scale)
            let radius = 7.75 * scale
            let strokeWidth = 1.3 * scale
            let circlePath = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(circlePath, with: .foreground, lineWidth: strokeWidth)

            let bars: [(x: CGFloat, y: CGFloat, height: CGFloat)] = [
                (5.55, 7.357, 3.285),
                (8.55, 6.08, 5.84),
                (11.55, 7.357, 3.285)
            ]
            let barWidth = 1.6 * scale
            let cornerRadius = 0.9 * scale

            for bar in bars {
                let rect = CGRect(
                    x: bar.x * scale,
                    y: bar.y * scale,
                    width: barWidth,
                    height: bar.height * scale
                )
                context.fill(Path(roundedRect: rect, cornerRadius: cornerRadius), with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct InstantHintModifier: ViewModifier {
    let text: String
    @Binding var hoverHint: String?

    func body(content: Content) -> some View {
        content
            .help(text)
            .onHover { isHovering in
                if isHovering {
                    hoverHint = text
                } else if hoverHint == text {
                    hoverHint = nil
                }
            }
    }
}

extension View {
    func instantHint(_ text: String, hoverHint: Binding<String?>) -> some View {
        modifier(InstantHintModifier(text: text, hoverHint: hoverHint))
    }
}
