import SwiftUI

extension PlayerView {
    // MARK: - Either side of the fold (design 9c)
    //
    // iPhone Duo: everything you touch on the left — cover, scrubber, transport, speed, sleep,
    // bookmark — and the chapters on the right. No mini player: it would repeat the transport.
    var foldControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            wideTopBar

            HStack(alignment: .top, spacing: 20) {
                CoverArtView(audiobook: audiobook, size: 150, cornerRadius: 18)
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 12)
                    .id(audiobook.id)

                VStack(alignment: .leading, spacing: 0) {
                    if let eyebrow {
                        Text(eyebrow.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(.tint)
                            .padding(.bottom, 6)
                    }
                    Text(audiobook.title ?? AudiobookModel.unknownTitle)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(credits)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 4)
                    metaChips.padding(.top, 12)
                }
                .accessibilityElement(children: .contain)
            }
            .padding(.top, 6)

            controlPanel.padding(.top, 22)

            Spacer(minLength: 16)

            chipRow
            playerTips.padding(.top, 12)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    var foldChapters: some View {
        chapterTable
            .padding(.top, 50)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
    }
}
