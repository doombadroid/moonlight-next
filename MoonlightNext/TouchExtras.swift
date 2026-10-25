//
//  TouchExtras.swift
//  MoonLume
//
//  Touchscreen-mode click and two-finger options, native-touch swipe speed, the key bar above
//  the soft keyboard, Globe as Escape, and the "send dummy input" keep-awake timer. Settings
//  live in TouchExtrasSettings.swift.
//

import UIKit

@objc final class MNTouchExtras: NSObject {
    static let clickOnLiftKey = "mnTouchClickOnLift"
    static let dragHoldKey = "mnTouchDragHold"
    static let twoFingerKey = "mnTouchTwoFinger"
    static let nativeSpeedKey = "mnNativeSwipeSpeed"
    static let nativeSplitKey = "mnNativeSwipeSplit"
    static let keyBarKey = "mnKeyBarKeys"
    static let keyboardHeightKey = "mnKeyboardHeight"
    // Read from ObjC (KeyboardSupport.m) by name
    static let globeEscapeKey = "mnGlobeEscape"
    static let dummyInputKey = "mnSendDummyInput"

    private static func value<T>(_ key: String, _ fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }

    /// Touchscreen mode: a tap clicks when the finger lifts, not when it lands
    @objc static var clickOnLift: Bool { value(clickOnLiftKey, false) }
    /// Click on lift: seconds a finger rests before moving drags instead of moving the pointer
    @objc static var dragHold: Double { value(dragHoldKey, 0.1) }
    /// Touchscreen mode: two fingers scroll, pinch-zoom and tap to right-click
    @objc static var twoFingerGestures: Bool { value(twoFingerKey, true) }
    /// Native touch: fingers that land right of `nativeSplit` move this many times faster
    /// (1 = off)
    @objc static var nativeSpeed: Double { value(nativeSpeedKey, 1.0) }
    /// Native touch: where the fast zone starts, as a fraction of the width
    @objc static var nativeSplit: Double { value(nativeSplitKey, 0.5) }
    /// Soft keyboard height as a fraction of the screen; 0 = what iOS reports
    @objc static var keyboardHeight: Double { value(keyboardHeightKey, 0.0) }

    /// Keys the bar above the soft keyboard can show, in bar order (Windows virtual-key codes)
    static let keyBarChoices: [Int] = [0x1B, 0x09, 0xA2, 0xA4, 0xA0, 0x5B, 0x2E, 0x08, 0x0D,
                                       0x25, 0x26, 0x28, 0x27, 0x24, 0x23, 0x21, 0x22, 0x2C]
                                       + Array(0x70...0x7B)
    static let keyBarDefault = "27,9,162,164,160,91,46,37,38,40,39"

    /// The keys chosen in Settings, in bar order
    static var keyBarKeys: [Int] {
        let chosen = Set(value(keyBarKey, keyBarDefault).split(separator: ",").compactMap { Int($0) })
        return keyBarChoices.filter { chosen.contains($0) }
    }
}

/// The row above the stream's soft keyboard. Modifiers latch until tapped again (so Ctrl, then
/// C on the keyboard, sends Ctrl+C); other keys send a press. Adapted from VoidLink (GPLv3),
/// Input/InputAccessoryBar.swift, which edits its keys in place; here Settings picks them.
@objc final class MNKeyBar: UIView {
    private let onDismiss: () -> Void
    private var latched = Set<Int>()
    private var buttons: [UIButton] = []

    @objc init(dismiss: @escaping () -> Void) {
        onDismiss = dismiss
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 48))
        autoresizingMask = .flexibleWidth
        backgroundColor = UIColor(white: 0.05, alpha: 1)

        let stack = UIStackView()
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        for vk in MNTouchExtras.keyBarKeys {
            let b = UIButton(configuration: .plain())
            b.tag = vk
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            style(b, on: false)
            buttons.append(b)
            stack.addArrangedSubview(b)
        }
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let done = UIButton(type: .system)
        done.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        done.tintColor = UIColor(white: 0.9, alpha: 1)
        done.accessibilityLabel = "Hide keyboard"
        done.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        addSubview(done)
        NSLayoutConstraint.activate([
            done.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),
            done.widthAnchor.constraint(equalToConstant: 44),
            done.heightAnchor.constraint(equalToConstant: 44),
            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -4),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func style(_ b: UIButton, on: Bool) {
        var c = UIButton.Configuration.plain()
        var title = AttributedString(WidgetCatalog.shortName(.key(b.tag)))
        title.font = .systemFont(ofSize: 15, weight: .medium)
        c.attributedTitle = title
        c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        c.baseForegroundColor = on ? .black : UIColor(white: 0.95, alpha: 1)
        c.background.backgroundColor = on ? UIColor(red: 0x8A / 255, green: 0xB4 / 255, blue: 1, alpha: 1)
                                          : UIColor(white: 0.09, alpha: 1)
        c.background.strokeColor = UIColor(white: 0.16, alpha: 1)
        c.background.strokeWidth = 1
        c.background.cornerRadius = 8
        b.configuration = c
    }

    @objc private func keyTapped(_ sender: UIButton) {
        let vk = sender.tag
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if WidgetCatalog.modifierBit(vk) != 0 {
            if latched.remove(vk) != nil {
                MNInput.keyUp(Int16(vk), modifiers: [])
                style(sender, on: false)
            }
            else {
                latched.insert(vk)
                MNInput.keyDown(Int16(vk), modifiers: [])
                style(sender, on: true)
            }
            return
        }
        MNInput.keyDown(Int16(vk), modifiers: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MNInput.keyUp(Int16(vk), modifiers: [])
        }
    }

    @objc private func dismissTapped() {
        onDismiss()
    }

    /// The keyboard closed: nothing latched may stay down on the host
    @objc func releaseKeys() {
        for vk in latched {
            MNInput.keyUp(Int16(vk), modifiers: [])
        }
        latched.removeAll()
        for b in buttons {
            style(b, on: false)
        }
    }
}

/// Adapted from VoidLink (GPLv3), ViewControllers/StreamFrameViewController.m (setupTimer): a
/// key-up for an unused key code once per frame keeps input packets flowing, so a Wi-Fi radio
/// that naps between packets stays awake. Off unless Settings turns it on.
@objc final class MNDummyInput: NSObject {
    private static var timer: DispatchSourceTimer?

    @objc static func start(fps: Int) {
        stop()
        guard UserDefaults.standard.bool(forKey: MNTouchExtras.dummyInputKey) else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: 1.0 / Double(min(max(fps, 30), 120)))
        // 0xFF is no key on any host; a key-up for it changes nothing
        t.setEventHandler { MNInput.keyUp(0xFF, modifiers: []) }
        t.resume()
        timer = t
    }

    @objc static func stop() {
        timer?.cancel()
        timer = nil
    }
}
