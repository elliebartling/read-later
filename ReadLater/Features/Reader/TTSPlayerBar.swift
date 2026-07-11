import SwiftUI

struct TTSPlayerBar: View {
    let controller: TTSController

    var body: some View {
        HStack(spacing: 16) {
            Button {
                if controller.isPlaying { controller.pause() } else { controller.resume() }
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Paragraph \(controller.currentParagraph + 1) of \(controller.totalParagraphs)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(controller.currentParagraph),
                             total: Double(max(1, controller.totalParagraphs)))
                    .progressViewStyle(.linear)
            }
            Button {
                controller.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .shadow(radius: 4, y: 2)
    }
}
