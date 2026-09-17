#if canImport(UIKit) && os(iOS)
import UIKit
import XCTest
@testable import SwiftTerm

/// 구명보트 터미널의 텍스트 선택 경로를 검증한다.
///
/// 호스트 앱은 한글 IME 때문에 키보드 응답자를 자기 뷰에 두므로 터미널은 first responder가
/// 아니다. 선택 메뉴가 응답자 체인에 의존하면 이 상태에서 조용히 아무 일도 하지 않는다.
final class IOSSelectionTests: XCTestCase {
    private final class StubDelegate: TerminalViewDelegate {
        func send(source: TerminalView, data: ArraySlice<UInt8>) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    /// 상태와 좌표를 지정할 수 있는 롱프레스 제스처. 실제 터치 없이 핸들러를 부른다.
    private final class StubLongPress: UILongPressGestureRecognizer {
        private var stubState: UIGestureRecognizer.State = .began
        private var stubLocation: CGPoint = .zero

        override var state: UIGestureRecognizer.State {
            get { stubState }
            set { stubState = newValue }
        }

        override func location(in view: UIView?) -> CGPoint { stubLocation }
    }

    private var delegate: StubDelegate!

    /// 호스트 앱과 같은 설정의 터미널을 만든다.
    private func makeHostedTerminal(_ text: String) -> TerminalView {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        delegate = StubDelegate()
        terminal.terminalDelegate = delegate
        // 호스트가 키보드 응답자를 소유한다.
        terminal.suppressSelectionKeyboardFocus = true
        terminal.layoutIfNeeded()
        terminal.feed(text: text)
        terminal.layoutIfNeeded()
        return terminal
    }

    /// 롱프레스와 같은 위치에서 메뉴를 띄우고, 메뉴 항목을 제목으로 실행한다.
    private func longPressThenTap(
        _ terminal: TerminalView,
        at position: Position,
        menuItem title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        terminal.showContextMenu(
            forRegion: terminal.makeContextMenuRegionForTap(
                point: CGPoint(
                    x: CGFloat(position.col) * terminal.cellDimension.width,
                    y: CGFloat(position.row) * terminal.cellDimension.height)),
            pos: position)
        let items = terminal.selectionMenuItems()
        let item = try XCTUnwrap(
            items.first { $0.title == title },
            "메뉴에 '\(title)'이 없다. 실제 항목: \(items.map(\.title))",
            file: file, line: line)
        item.perform()
    }

    func testLongPressSelectHighlightsWordWhileHostOwnsKeyboard() throws {
        let terminal = makeHostedTerminal("hermesagent rescue\r\n")

        XCTAssertFalse(terminal.isFirstResponder, "호스트가 키보드를 소유한 상태를 재현해야 한다.")

        // "hermesagent"의 가운데를 길게 누른 뒤 '선택'을 고른다.
        try longPressThenTap(terminal, at: Position(col: 4, row: 0), menuItem: "선택")

        XCTAssertTrue(terminal.selection.active, "선택이 활성화되지 않았다.")
        XCTAssertEqual(terminal.selection.getSelectedText(), "hermesagent")
        XCTAssertFalse(terminal.isFirstResponder, "선택이 키보드 응답자를 빼앗으면 안 된다.")
    }

    func testSelectedWordIsPaintedWithSelectionBackground() throws {
        let terminal = makeHostedTerminal("hermesagent rescue\r\n")
        try longPressThenTap(terminal, at: Position(col: 4, row: 0), menuItem: "선택")

        let columns = try XCTUnwrap(
            terminal.selectedColumnsRange(row: 0, cols: terminal.getTerminal().cols),
            "선택된 행이 그리기 단계에서 선택 범위를 돌려주지 않았다.")
        XCTAssertEqual(columns.lowerBound, 0)
        XCTAssertEqual(columns.count, "hermesagent".count)

        // 실제 렌더링이 선택 배경을 입히는지 확인한다.
        let line = terminal.getTerminal().displayBuffer.lines[0]
        let info = terminal.buildAttributedString(row: 0, line: line, cols: terminal.getTerminal().cols)
        var highlighted = ""
        for segment in info.segments {
            let text = segment.attributedString
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
                if attrs[.selectionBackgroundColor] != nil {
                    highlighted += text.attributedSubstring(from: range).string
                }
            }
        }
        XCTAssertEqual(highlighted, "hermesagent", "선택 배경이 칠해진 글자가 선택 범위와 다르다.")
    }

    func testSelectionSurvivesDragExtensionAndCopies() throws {
        let terminal = makeHostedTerminal("hermesagent rescue\r\n")
        try longPressThenTap(terminal, at: Position(col: 4, row: 0), menuItem: "선택")

        // 선택 핸들을 오른쪽으로 끌어 범위를 넓힌다.
        terminal.selection.pivot = terminal.selection.start
        terminal.selection.pivotExtend(bufferPosition: Position(col: 18, row: 0))
        XCTAssertEqual(terminal.selection.getSelectedText(), "hermesagent rescue")

        // 선택 중에는 스크롤이 꺼져 드래그가 스크롤에 먹히지 않는다.
        XCTAssertFalse(terminal.isScrollEnabled, "선택 중에는 스크롤 pan이 선택 드래그를 이기면 안 된다.")

        // 시뮬레이터에서 UIPasteboard 를 읽으면 붙여넣기 권한 알림이 떠 테스트가 멈춘다.
        // 복사 대상 문자열은 위에서 확인했으므로, 여기서는 복사 뒤 정리 상태만 본다.
        let items = terminal.selectionMenuItems()
        let copy = try XCTUnwrap(
            items.first { $0.title == "복사" },
            "선택 상태에서는 '복사'가 있어야 한다. 실제 항목: \(items.map(\.title))")
        copy.perform()

        XCTAssertFalse(terminal.selection.active)
        XCTAssertTrue(terminal.isScrollEnabled, "선택이 끝나면 스크롤이 돌아와야 한다.")
    }

    /// 출력이 흘러도 사용자가 만든 선택이 남아 있어야 한다.
    ///
    /// tmux는 상태줄을 1초마다 다시 그린다. 예전에는 마우스 리포팅이 켜져 있으면 출력이
    /// 들어올 때마다 선택을 지워서, 복사하기도 전에 하이라이트가 사라졌다.
    func testSelectionSurvivesStreamingOutputWithMouseReporting() throws {
        let terminal = makeHostedTerminal("hermesagent rescue\r\n")
        // tmux가 켜는 마우스 리포팅.
        terminal.feed(text: "\u{1b}[?1000h\u{1b}[?1002h\u{1b}[?1006h")
        XCTAssertNotEqual(terminal.getTerminal().mouseMode, .off)
        XCTAssertTrue(terminal.allowMouseReporting)

        try longPressThenTap(terminal, at: Position(col: 4, row: 0), menuItem: "선택")
        XCTAssertTrue(terminal.selection.active)

        // 상태줄 갱신처럼 화면을 건드리는 출력이 들어온다.
        for _ in 0..<3 {
            terminal.feed(text: "\u{1b}[s\u{1b}[24;1H[status]\u{1b}[u")
        }

        XCTAssertTrue(terminal.selection.active, "출력이 사용자의 선택을 지웠다.")
        XCTAssertEqual(terminal.selection.getSelectedText(), "hermesagent")
    }

    /// 선택한 줄이 스크롤백에서 밀려나면 선택을 버린다.
    func testSelectionIsDroppedOnceItsRowsLeaveTheBuffer() throws {
        let terminal = makeHostedTerminal("hermesagent rescue\r\n")
        try longPressThenTap(terminal, at: Position(col: 4, row: 0), menuItem: "선택")
        XCTAssertTrue(terminal.selection.active)

        // 선택 위치를 버퍼 밖으로 옮겨 놓고 출력을 흘린다.
        let outOfRange = terminal.getTerminal().displayBuffer.lines.count + 10
        terminal.selection.setSoftStart(row: outOfRange, col: 0)
        terminal.selection.pivotExtend(bufferPosition: Position(col: 3, row: outOfRange))
        terminal.feed(text: "tick\r\n")

        XCTAssertFalse(terminal.selection.active, "버퍼에서 사라진 선택이 남아 있다.")
        XCTAssertTrue(terminal.isScrollEnabled, "선택이 풀렸으면 스크롤이 돌아와야 한다.")
    }

    /// 편집 메뉴 인터랙션이 터미널의 롱프레스를 빼앗지 않는지 확인한다.
    ///
    /// `UIEditMenuInteraction`은 뷰에 자기 제스처를 붙인다. 그 제스처가 SwiftTerm의 롱프레스를
    /// 취소시키면 메뉴 자체가 뜨지 않아 선택을 시작할 방법이 사라진다.
    func testEditMenuInteractionDoesNotShadowTerminalLongPress() throws {
        let terminal = makeHostedTerminal("hermesagent\r\n")
        let recognizers = terminal.gestureRecognizers ?? []

        // UIScrollView의 스크롤 인디케이터 롱프레스는 서브클래스라 제외한다.
        let terminalLongPresses = recognizers.filter {
            type(of: $0) == UILongPressGestureRecognizer.self
        }
        XCTAssertEqual(terminalLongPresses.count, 1, "터미널 롱프레스가 사라졌거나 중복됐다.")
        XCTAssertEqual(
            (terminalLongPresses.first as? UILongPressGestureRecognizer)?.minimumPressDuration,
            0.7)

        // 편집 메뉴 인터랙션이 실제로 설치되어 있어야 메뉴를 띄울 수 있다.
        let editMenuRecognizers = recognizers.filter {
            let owner = $0.delegate.map { String(describing: type(of: $0)) } ?? ""
            return owner.contains("Click")
        }
        XCTAssertFalse(editMenuRecognizers.isEmpty, "편집 메뉴 인터랙션이 설치되지 않았다.")
    }

    /// 실제 window scene에 올린 터미널에서 선택 메뉴가 화면에 뜨는지 확인한다.
    ///
    /// `UIEditMenuInteraction`은 뷰가 window scene 안에 있을 때만 메뉴를 띄운다. 이 조건이
    /// 깨지면 롱프레스는 아무 반응이 없고 선택도 시작되지 않는다.
    func testContextMenuActuallyPresentsInWindowScene() throws {
        // SPM 테스트 번들은 호스트 앱이 없어 scene이 없다. 그때는 이 검증을 건너뛰고,
        // 메뉴 표시 자체는 시뮬레이터 하니스 앱으로 확인한다.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            throw XCTSkip("window scene이 없는 테스트 번들에서는 메뉴 표시를 검증할 수 없다.")
        }

        let terminal = makeHostedTerminal("hermesagent rescue\r\n")
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        let root = UIViewController()
        root.view.addSubview(terminal)
        window.rootViewController = root
        window.makeKeyAndVisible()
        terminal.layoutIfNeeded()

        terminal.showContextMenu(
            forRegion: terminal.makeContextMenuRegionForTap(point: CGPoint(x: 40, y: 4)),
            pos: Position(col: 4, row: 0))

        let shown = expectation(description: "선택 메뉴 표시")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { shown.fulfill() }
        wait(for: [shown], timeout: 3)

        XCTAssertTrue(terminal.isContextMenuVisible, "롱프레스 선택 메뉴가 화면에 뜨지 않았다.")
    }

    func testLongPressDoesNotStealKeyboardWhenHostOwnsIt() {
        let terminal = makeHostedTerminal("hermesagent\r\n")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        window.addSubview(terminal)
        window.makeKeyAndVisible()

        terminal.longPress(StubLongPress())

        XCTAssertFalse(terminal.isFirstResponder, "롱프레스가 키보드를 열면 안 된다.")
    }

    func testLongPressTakesResponderWhenHostDoesNotOwnKeyboard() {
        let terminal = makeHostedTerminal("hermesagent\r\n")
        // 기본 SwiftTerm 호스트는 응답자 체인을 그대로 쓴다.
        terminal.suppressSelectionKeyboardFocus = false
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        window.addSubview(terminal)
        window.makeKeyAndVisible()

        terminal.longPress(StubLongPress())

        XCTAssertTrue(terminal.isFirstResponder)
    }
}
#endif
