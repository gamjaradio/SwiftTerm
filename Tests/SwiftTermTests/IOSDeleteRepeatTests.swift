#if canImport(UIKit)
import UIKit
import XCTest
@testable import SwiftTerm

final class IOSDeleteRepeatTests: XCTestCase {
    private final class CapturingDelegate: TerminalViewDelegate {
        var sent: [UInt8] = []

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            sent.append(contentsOf: data)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private func makeTerminal() -> (TerminalView, CapturingDelegate) {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        let delegate = CapturingDelegate()
        terminal.terminalDelegate = delegate
        return (terminal, delegate)
    }

    func testDeleteBackwardKeepsSyntheticDocumentAvailableAfterExhaustion() {
        let (terminal, delegate) = makeTerminal()
        let deleteCount = TerminalView.syntheticDeleteStorage.count + 1

        for _ in 0..<deleteCount {
            terminal.deleteBackward()
        }

        XCTAssertEqual(delegate.sent, Array(repeating: 0x7f, count: deleteCount))
        XCTAssertTrue(terminal.hasText)
        XCTAssertTrue(terminal.textInputStorageIsSynthetic)
        XCTAssertFalse(terminal.textInputStorage.isEmpty)
    }

    func testCommittedTextDiscardsSyntheticDocument() {
        let (terminal, delegate) = makeTerminal()

        terminal.insertText("abc")

        XCTAssertEqual(delegate.sent, Array("abc".utf8))
        XCTAssertEqual(terminal.textInputStorage, "abc")
        XCTAssertFalse(terminal.textInputStorageIsSynthetic)
    }

    func testDeleteAtDocumentStartPreservesCommittedText() {
        let (terminal, delegate) = makeTerminal()
        terminal.insertText("abc")
        terminal.selectedTextRange = terminal.textRange(
            from: terminal.beginningOfDocument,
            to: terminal.beginningOfDocument)

        terminal.deleteBackward()

        XCTAssertEqual(delegate.sent, Array("abc".utf8) + [0x7f])
        XCTAssertEqual(terminal.textInputStorage, "abc")
        XCTAssertFalse(terminal.textInputStorageIsSynthetic)
    }

    func testUITextInputEditsDiscardSyntheticDocument() {
        let (terminal, delegate) = makeTerminal()
        terminal.replace(terminal.selectedTextRange!, withText: "a")

        XCTAssertEqual(delegate.sent, Array("a".utf8))
        XCTAssertEqual(terminal.textInputStorage, "a")
        XCTAssertFalse(terminal.textInputStorageIsSynthetic)

        terminal.resetInputBuffer()
        terminal.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0))

        XCTAssertEqual(terminal.textInputStorage, "한")
        XCTAssertFalse(terminal.textInputStorageIsSynthetic)
        XCTAssertNotNil(terminal.markedTextRange)
    }

    func testCancelledMarkedTextRestoresSyntheticDocument() {
        let (terminal, _) = makeTerminal()

        terminal.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0))
        terminal.setMarkedText(nil, selectedRange: NSRange(location: 0, length: 0))

        XCTAssertTrue(terminal.hasText)
        XCTAssertTrue(terminal.textInputStorageIsSynthetic)
        XCTAssertFalse(terminal.textInputStorage.isEmpty)
        XCTAssertNil(terminal.markedTextRange)
    }
}
#endif
