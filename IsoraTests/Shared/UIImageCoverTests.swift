import Testing
import UIKit
@testable import Isora

@Suite("Cover JPEG downsampling")
struct UIImageCoverTests {
    private func solidImage(side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    @Test("A large cover is capped at the maximum side")
    func largeCoverIsDownsampled() throws {
        let data = try #require(solidImage(side: 3000).coverJPEGData())
        let decoded = try #require(UIImage(data: data))
        #expect(max(decoded.size.width, decoded.size.height) * decoded.scale == UIImage.coverMaxPixels)
    }

    @Test("A small cover keeps its size")
    func smallCoverIsUntouched() throws {
        let data = try #require(solidImage(side: 400).coverJPEGData())
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width * decoded.scale == 400)
    }

    @Test("Sentence ids are stable across regrouping")
    func sentenceIDsAreStable() {
        let segments = [
            TranscriptionSegment(text: "Hello world.", start: 0, end: 1),
            TranscriptionSegment(text: "Second one.", start: 1, end: 2)
        ]
        let first = TranscriptSentence.group(segments, offset: 10)
        let second = TranscriptSentence.group(segments, offset: 10)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.id) == [10, 11])
    }
}
