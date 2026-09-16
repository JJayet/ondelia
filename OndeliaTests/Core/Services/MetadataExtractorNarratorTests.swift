import AVFoundation
import Testing
@testable import Isora

@Suite("MetadataExtractor narrator")
struct MetadataExtractorNarratorTests {

    private func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        return item
    }

    private var nrt: AVMetadataIdentifier {
        AVMetadataItem.identifier(forKey: "©nrt", keySpace: .iTunes)!
    }

    @Test("©nrt wins over composer")
    func nrtWins() async {
        let narrator = await MetadataExtractor.narratorTag(in: [
            item(.iTunesMetadataComposer, "Composer"),
            item(nrt, "  Derek Jacobi "),
        ])
        #expect(narrator == "Derek Jacobi")
    }

    @Test("composer is the fallback, blank values are skipped")
    func composerFallback() async {
        let narrator = await MetadataExtractor.narratorTag(in: [
            item(nrt, "   "),
            item(.id3MetadataComposer, "Juliet Stevenson"),
        ])
        #expect(narrator == "Juliet Stevenson")
    }

    @Test("title and artist alone yield no narrator")
    func none() async {
        let narrator = await MetadataExtractor.narratorTag(in: [
            item(.commonIdentifierTitle, "Emma"),
            item(.commonIdentifierArtist, "Jane Austen"),
        ])
        #expect(narrator == nil)
    }
}
