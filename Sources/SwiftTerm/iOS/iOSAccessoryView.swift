//
//  iOSAccessoryView.swift
//  
//  Implements an inputAccessoryView for the iOS terminal for common operations
//
//  Created by Miguel de Icaza on 5/9/20.
//
#if os(iOS) || os(visionOS)

import Foundation
import UIKit

/**
 * This class provides an input accessory for the terminal on iOS, you can access this via the `inputAccessoryView`
 * property in the `TerminalView` and casting the result to `TerminalAccessory`.
 *
 * This class surfaces some state that the terminal might want to poke at, you should at least support the following
 * properties;
 * `controlModifer` should be set if the control key is pressed
 */
public class TerminalAccessory: UIInputView, UIInputViewAudioFeedback {
    /// This points to an instanace of the `TerminalView` where events are sent
    public weak var terminalView: TerminalView?
    weak var terminal: Terminal?
    var controlButton: UIButton?
    /// This tracks whether the "control" button is turned on or not
    public var controlModifier: Bool = false {
        didSet {
            controlButton?.isSelected = controlModifier
            controlButton?.accessibilityValue = controlModifier ? "켜짐" : "꺼짐"
        }
    }
    
    var touchButton: UIButton!
    var keyboardButton: UIButton!

    private static let shortcutUsageKey = "swiftterm.accessory.shortcutUsage.v1"
    private static let shortcutIdentifierPrefix = "hermes.rescue.terminal.shortcut."
    private static let defaultShortcutUsage = ["tab": 3, "esc": 2, "ctrl": 1]
    private static let minimumButtonWidth: CGFloat = 44
    private static let maximumButtonWidth: CGFloat = 64
    private let shortcutsScrollView = UIScrollView()
    private var views: [UIButton] = []
    private var shortcutUsage = TerminalAccessory.loadShortcutUsage()

    private static func loadShortcutUsage() -> [String: Int] {
        let stored = UserDefaults.standard.dictionary(forKey: shortcutUsageKey) ?? [:]
        return stored.compactMapValues { ($0 as? NSNumber)?.intValue }
    }
    
    public init (frame: CGRect, inputViewStyle: UIInputView.Style, container: TerminalView)
    {
        self.terminalView = container
        self.terminal = terminalView?.getTerminal()
        super.init (frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
        shortcutsScrollView.alwaysBounceHorizontal = true
        shortcutsScrollView.canCancelContentTouches = true
        shortcutsScrollView.delaysContentTouches = true
        shortcutsScrollView.showsHorizontalScrollIndicator = true
        shortcutsScrollView.accessibilityIdentifier = "hermes.rescue.terminal.shortcuts"
        addSubview(shortcutsScrollView)
        setupUI()
    }
    
    public override var bounds: CGRect {
        didSet {
            setupUI ()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        shortcutUsage = Self.loadShortcutUsage()
        sortViewsByUsage()
        setNeedsLayout()
    }
    
    #if os(iOS)
    // Override for UIInputViewAudioFeedback
    public var enableInputClicksWhenVisible: Bool { true }
    #endif
    
    func clickAndSend (_ data: [UInt8])
    {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        terminalView?.send (data)
    }

    func clickAndInsertText (_ text: String)
    {
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        terminalView?.insertTextFromAccessory(text)
    }
    
    @objc func esc (_ sender: AnyObject) { clickAndSend ([0x1b]) }
    @objc func tab (_ sender: AnyObject) { clickAndSend ([0x9]) }
    @objc func tilde (_ sender: AnyObject) { clickAndInsertText ("~") }
    @objc func pipe (_ sender: AnyObject) { clickAndInsertText ("|") }
    @objc func slash (_ sender: AnyObject) { clickAndInsertText ("/") }
    @objc func dash (_ sender: AnyObject) { clickAndInsertText ("-") }
    @objc func f1 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[0]) }
    @objc func f2 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[1]) }
    @objc func f3 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[2]) }
    @objc func f4 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[3]) }
    @objc func f5 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[4]) }
    @objc func f6 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[5]) }
    @objc func f7 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[6]) }
    @objc func f8 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[7]) }
    @objc func f9 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[8]) }
    @objc func f10 (_ sender: AnyObject) { clickAndSend (EscapeSequences.cmdF[9]) }
    
    @objc
    func ctrl (_ sender: UIButton)
    {
        controlModifier.toggle()
    }

    var repeatCommand: (() -> ())? = nil
    var repeatTimer: Timer?

    func startRepeatingKeypress (repeatKey: @escaping () -> ())
    {
        cancelTimer()
        repeatKey ()
        repeatCommand = repeatKey
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.repeatCommand? ()
        }
    }
    
    @objc
    func cancelTimer ()
    {
        repeatTimer?.invalidate()
        repeatCommand = nil
        repeatTimer = nil
    }
    
    @objc func up (_ sender: UIButton)
    {
        terminalView?.sendKeyUp ()
    }
    
    @objc func down (_ sender: UIButton)
    {
        terminalView?.sendKeyDown ()
    }
    
    @objc func left (_ sender: UIButton)
    {
        terminalView?.sendKeyLeft()
    }
    
    @objc func right (_ sender: UIButton)
    {
        terminalView?.sendKeyRight ()
    }

    @objc func handleAutoRepeat (_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? UIButton, let id = shortcutID(button) else { return }
        switch gesture.state {
        case .began:
            let command: (() -> Void)?
            switch id {
            case "left": command = { [weak self] in self?.terminalView?.sendKeyLeft() }
            case "down": command = { [weak self] in self?.terminalView?.sendKeyDown() }
            case "up": command = { [weak self] in self?.terminalView?.sendKeyUp() }
            case "right": command = { [weak self] in self?.terminalView?.sendKeyRight() }
            default: command = nil
            }
            guard let command else { return }
            recordShortcutUsage(button)
            startRepeatingKeypress(repeatKey: command)
        case .ended, .cancelled, .failed:
            cancelTimer()
        default:
            break
        }
    }


    @objc func toggleInputKeyboard (_ sender: UIButton) {
        guard let tv = terminalView else { return }

        if tv.inputView == nil {
            #if os(visionOS)
            tv.inputView = KeyboardView (frame: CGRect (origin: CGPoint.zero,
                                                        size: CGSize (width: 300,
                                                                      height: 400)),
                                         terminalView: terminalView)
            #else
            tv.inputView = KeyboardView (frame: CGRect (origin: CGPoint.zero,
                                                        size: CGSize (width: UIScreen.main.bounds.width,
                                                                      height: max((UIScreen.main.bounds.height / 5),140))),
                                         terminalView: terminalView)
            #endif
        } else {
            tv.inputView = nil
        }
        keyboardButton.accessibilityValue = tv.inputView == nil ? "기본 키보드" : "터미널 키보드"
        UIView.performWithoutAnimation {
            tv.reloadInputViews()
        }
    }

    @objc func toggleTouch (_ sender: UIButton) {
        terminalView?.allowMouseReporting.toggle()
        let enabled = terminalView?.allowMouseReporting ?? false
        touchButton.isSelected = enabled
        touchButton.accessibilityValue = enabled ? "켜짐" : "꺼짐"
    }

    /**
     * This method setups the internal data structures to setup the UI shown on the accessory view,
     * if you provide your own implementation, you are responsible for adding all the elements to the
     * this view, and flagging some of the public properties declared here.
     */
    public func setupUI ()
    {
        cancelTimer()
        shortcutUsage = Self.loadShortcutUsage()
        for view in views {
            view.removeFromSuperview()
        }
        views = []
        terminalView?.setupKeyboardButtonColors ()

        let tabButton = makeButton(
            "", #selector(tab), id: "tab", icon: "arrow.right.to.line.compact",
            isNormal: false, accessibilityLabel: "탭"
        )
        let escapeButton = makeButton("esc", #selector(esc), id: "esc", isNormal: false, accessibilityLabel: "이스케이프")
        let controlButton = makeButton("ctrl", #selector(ctrl), id: "ctrl", isNormal: false, accessibilityLabel: "컨트롤")
        controlButton.isSelected = controlModifier
        controlButton.accessibilityValue = controlModifier ? "켜짐" : "꺼짐"
        controlButton.accessibilityHint = "다음 문자에 컨트롤 키를 적용합니다."
        self.controlButton = controlButton
        touchButton = makeButton("", #selector(toggleTouch), id: "touch", icon: "hand.draw", isNormal: false, accessibilityLabel: "터치 모드")
        let touchEnabled = terminalView?.allowMouseReporting ?? false
        touchButton.isSelected = touchEnabled
        touchButton.accessibilityValue = touchEnabled ? "켜짐" : "꺼짐"
        touchButton.accessibilityHint = "터미널 마우스 입력을 전환합니다."
        keyboardButton = makeButton("", #selector(toggleInputKeyboard), id: "keyboard", icon: "keyboard.chevron.compact.down", isNormal: false, accessibilityLabel: "키보드 전환")
        keyboardButton.accessibilityValue = terminalView?.inputView == nil ? "기본 키보드" : "터미널 키보드"
        keyboardButton.accessibilityHint = "기본 키보드와 터미널 키보드를 전환합니다."

        views = [
            tabButton,
            escapeButton,
            controlButton,
            makeButton("/", #selector(slash), id: "slash", accessibilityLabel: "슬래시"),
            makeButton("~", #selector(tilde), id: "tilde", accessibilityLabel: "틸드"),
            makeButton("|", #selector(pipe), id: "pipe", accessibilityLabel: "파이프"),
            makeButton("-", #selector(dash), id: "dash", accessibilityLabel: "대시"),
            makeAutoRepeatButton("arrow.left", #selector(left), id: "left", accessibilityLabel: "왼쪽 화살표"),
            makeAutoRepeatButton("arrow.down", #selector(down), id: "down", accessibilityLabel: "아래쪽 화살표"),
            makeAutoRepeatButton("arrow.up", #selector(up), id: "up", accessibilityLabel: "위쪽 화살표"),
            makeAutoRepeatButton("arrow.right", #selector(right), id: "right", accessibilityLabel: "오른쪽 화살표"),
            makeButton("F1", #selector(f1), id: "f1"),
            makeButton("F2", #selector(f2), id: "f2"),
            makeButton("F3", #selector(f3), id: "f3"),
            makeButton("F4", #selector(f4), id: "f4"),
            makeButton("F5", #selector(f5), id: "f5"),
            makeButton("F6", #selector(f6), id: "f6"),
            makeButton("F7", #selector(f7), id: "f7"),
            makeButton("F8", #selector(f8), id: "f8"),
            makeButton("F9", #selector(f9), id: "f9"),
            makeButton("F10", #selector(f10), id: "f10"),
            touchButton,
            keyboardButton,
        ]
        for (index, view) in views.enumerated() {
            view.tag = index
        }
        sortViewsByUsage()
        for view in views {
            shortcutsScrollView.addSubview(view)
        }
        layoutSubviews ()
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setupUI()
    }

    private let buttonPad: CGFloat = 6
    public override func layoutSubviews() {
        super.layoutSubviews()
        shortcutsScrollView.frame = bounds
        var x: CGFloat = 2
        let buttonHeight = max(1, bounds.height - 8)

        for (index, view) in views.enumerated() {
            let width = index < 4 && shortcutUsageCount(view) > 0
                ? Self.maximumButtonWidth
                : Self.minimumButtonWidth
            view.frame = CGRect(x: x, y: 4, width: width, height: buttonHeight)
            x += width + buttonPad
        }
        shortcutsScrollView.contentSize = CGSize(width: max(bounds.width + 1, x - buttonPad + 2), height: bounds.height)
        shortcutsScrollView.accessibilityElements = views
    }

    private func sortViewsByUsage() {
        views.sort {
            let lhsUsage = shortcutUsageCount($0)
            let rhsUsage = shortcutUsageCount($1)
            return lhsUsage == rhsUsage ? $0.tag < $1.tag : lhsUsage > rhsUsage
        }
    }

    private func shortcutUsageCount(_ button: UIButton) -> Int {
        guard let id = shortcutID(button) else { return 0 }
        return shortcutUsage[id] ?? Self.defaultShortcutUsage[id] ?? 0
    }

    private func shortcutID(_ button: UIButton) -> String? {
        guard
            let identifier = button.accessibilityIdentifier,
            identifier.hasPrefix(Self.shortcutIdentifierPrefix)
        else { return nil }
        return String(identifier.dropFirst(Self.shortcutIdentifierPrefix.count))
    }

    @objc func recordShortcutUsage(_ sender: UIButton) {
        guard let id = shortcutID(sender) else { return }
        shortcutUsage = Self.loadShortcutUsage()
        shortcutUsage[id] = shortcutUsageCount(sender) + 1
        UserDefaults.standard.set(shortcutUsage, forKey: Self.shortcutUsageKey)
    }

    func makeAutoRepeatButton (
        _ iconName: String,
        _ action: Selector,
        id: String,
        accessibilityLabel: String
    ) -> UIButton
    {
        let b = makeButton("", action, id: id, icon: iconName, accessibilityLabel: accessibilityLabel)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleAutoRepeat(_:)))
        longPress.minimumPressDuration = 0.6
        b.addGestureRecognizer(longPress)
        return b
    }

    func makeButton (
        _ title: String,
        _ action: Selector,
        id: String,
        icon: String = "",
        isNormal: Bool = true,
        iconPointSize: CGFloat = 18,
        accessibilityLabel: String? = nil
    ) -> UIButton
    {
        let b = BackgroundSelectedButton.init(type: .roundedRect)

        TerminalAccessory.styleButton (b)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.addTarget(self, action: #selector(recordShortcutUsage), for: .touchUpInside)
        b.setTitle(title, for: .normal)
        b.accessibilityIdentifier = Self.shortcutIdentifierPrefix + id
        b.accessibilityLabel = accessibilityLabel ?? title
        guard let terminalView else {
            return b
        }
        b.color = isNormal ? terminalView.buttonBackgroundColor : terminalView.buttonDarkBackgroundColor
        b.setTitleColor(terminalView.buttonColor, for: .normal)
        b.setTitleColor(terminalView.buttonColor, for: .selected)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        b.backgroundColor = isNormal ? terminalView.buttonBackgroundColor : terminalView.buttonDarkBackgroundColor

        if icon != "" {
            if let img = UIImage (systemName: icon, withConfiguration: UIImage.SymbolConfiguration (pointSize: iconPointSize, weight: .semibold)) {
                b.setImage(img.withTintColor(terminalView.buttonColor, renderingMode: .alwaysOriginal), for: .normal)
            }
        }
        return b
    }
    
    // I am not committed to this style, this is just something quick to get going
    static func styleButton (_ b: UIButton)
    {
        b.layer.cornerRadius = 5
        b.layer.masksToBounds = true
        b.layer.shadowOffset = CGSize(width: 0, height: 1.0)
        b.layer.shadowRadius = 0.0
        b.layer.shadowOpacity = 0.35
    }
}


class BackgroundSelectedButton: UIButton {
    
    var color: UIColor?
    
    override var isSelected: Bool {
        didSet {
            self.backgroundColor = isSelected ? UIView().tintColor : color
        }
    }
}
#endif
