//
//  UndoSeekTests.swift
//  IsoraTests
//

import Testing
import Foundation
@testable import Isora

@MainActor
@Suite("Undo last seek", .serialized, .tags(.manager))
struct UndoSeekTests {
    @Test("Only sizeable, finite jumps are undoable")
    func threshold() {
        #expect(GlobalAudioManager.isUndoableSeek(from: 100, to: 130))
        #expect(GlobalAudioManager.isUndoableSeek(from: 130, to: 100))
        #expect(!GlobalAudioManager.isUndoableSeek(from: 100, to: 105))
        #expect(!GlobalAudioManager.isUndoableSeek(from: .nan, to: 100))
    }

    @Test("Remembering keeps the latest origin; undoing clears it")
    func rememberAndUndo() {
        let manager = GlobalAudioManager.shared
        manager.clearUndoSeek()

        manager.rememberSeekOrigin(100, target: 200)
        manager.rememberSeekOrigin(200, target: 300)
        #expect(manager.undoSeekOrigin == 200)

        manager.rememberSeekOrigin(300, target: 302)
        #expect(manager.undoSeekOrigin == 200)

        manager.undoLastSeek()
        #expect(manager.undoSeekOrigin == nil)
    }
}
