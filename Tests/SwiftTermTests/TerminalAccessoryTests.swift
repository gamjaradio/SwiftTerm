#if canImport(UIKit)
import UIKit
import XCTest
@testable import SwiftTerm

final class TerminalAccessoryTests: XCTestCase {
    private let usageKey = "swiftterm.accessory.shortcutUsage.v1"
    private let identifierPrefix = "hermes.rescue.terminal.shortcut."

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: usageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: usageKey)
        super.tearDown()
    }

    func testScrollableShortcutsAreRankedAndCapped() {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 402, height: 600), font: nil)
        let accessory = try! XCTUnwrap(terminal.inputAccessoryView as? TerminalAccessory)
        accessory.frame = CGRect(x: 0, y: 0, width: 402, height: 52)
        accessory.layoutIfNeeded()

        let scrollView = try! XCTUnwrap(
            accessory.subviews.first { $0.accessibilityIdentifier == "hermes.rescue.terminal.shortcuts" }
                as? UIScrollView
        )
        let buttons: () -> [UIButton] = {
            scrollView.subviews.compactMap { $0 as? UIButton }
        }
        let button: (String) -> UIButton = { id in
            try! XCTUnwrap(buttons().first { $0.accessibilityIdentifier == self.identifierPrefix + id })
        }

        XCTAssertEqual(buttons().count, 23)
        XCTAssertEqual(button("tab").frame.minX, 2, accuracy: 0.1)
        XCTAssertEqual(button("tab").frame.width, 56, accuracy: 0.1)
        XCTAssertEqual(button("esc").frame.width, 56, accuracy: 0.1)
        XCTAssertTrue(buttons().allSatisfy { $0.frame.width >= 44 && $0.frame.width <= 56 })
        XCTAssertTrue(buttons().allSatisfy { $0.frame.height >= 44 })
        XCTAssertTrue(buttons().allSatisfy { !($0.accessibilityLabel ?? "").isEmpty })
        XCTAssertGreaterThan(scrollView.contentSize.width, scrollView.bounds.width)
        XCTAssertNotNil(button("f10"))

        let slashFrame = button("slash").frame
        for _ in 0..<4 {
            accessory.recordShortcutUsage(button("slash"))
        }
        accessory.layoutIfNeeded()
        XCTAssertEqual(button("slash").frame, slashFrame)

        accessory.setupUI()
        accessory.layoutIfNeeded()
        XCTAssertEqual(button("slash").frame.minX, 2, accuracy: 0.1)
        XCTAssertEqual(button("slash").frame.width, 56, accuracy: 0.1)
    }
}
#endif
