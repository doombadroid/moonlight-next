//
//  WidgetView.swift
//  MoonLume
//
//  How one widget looks. All touch handling is in MNWidgetLayer; these views only draw.
//

import GameController
import UIKit

final class WidgetView: UIView {
    private(set) var widget: MNWidget
    private let shape = CAShapeLayer()
    private let label = UILabel()
    private let icon = UIImageView()
    /// Pads: where the thumb is, shown while touching
    private let knob = CALayer()
    /// Pads: where the thumb landed
    private let base = CAShapeLayer()
    private var diagram: PadDiagramView?

    var pressed = false { didSet { if pressed != oldValue { updateColors() } } }
    /// While editing: children of a collapsed folder show faintly so they can still be picked
    var dimmed = false { didSet { if dimmed != oldValue { updateAlpha() } } }
    var globalOpacity: CGFloat = 1 { didSet { updateAlpha() } }

    private static let accent = UIColor(red: 0x8A / 255.0, green: 0xB4 / 255.0, blue: 1, alpha: 1) // Theme.accent

    init(widget: MNWidget) {
        self.widget = widget
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        label.textAlignment = .center
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.numberOfLines = 2
        addSubview(label)
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        addSubview(icon)
        base.fillColor = UIColor(white: 1, alpha: 0.08).cgColor
        base.strokeColor = UIColor(white: 1, alpha: 0.35).cgColor
        base.lineWidth = 1.5
        base.isHidden = true
        layer.addSublayer(base)
        knob.backgroundColor = UIColor(white: 1, alpha: 0.55).cgColor
        knob.isHidden = true
        layer.addSublayer(knob)
        configure(widget)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ widget: MNWidget) {
        self.widget = widget
        let symbolName = widget.symbol.isEmpty && widget.label.isEmpty ? widget.defaultSymbol : widget.symbol
        let image = symbolName.isEmpty ? nil : UIImage(systemName: symbolName)
        icon.image = image
        icon.isHidden = image == nil || widget.kind == .overlay
        label.isHidden = !icon.isHidden || widget.kind == .overlay
        label.text = widget.title
        isPad = [.stickPad, .cameraPad, .triggerPad, .directionPad, .mousePad, .scrollPad, .blocker].contains(widget.kind)
        if widget.kind == .overlay, diagram == nil {
            let view = PadDiagramView(frame: bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
            diagram = view
        }
        setNeedsLayout()
        updateColors()
        updateAlpha()
    }

    private var isPad = false

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        let radius = widget.shape == .circle ? min(b.width, b.height) / 2 : min(12, min(b.width, b.height) / 4)
        shape.frame = b
        shape.path = (widget.shape == .circle ? UIBezierPath(ovalIn: b.insetBy(dx: 1, dy: 1))
                                              : UIBezierPath(roundedRect: b.insetBy(dx: 1, dy: 1), cornerRadius: radius)).cgPath
        shape.lineDashPattern = isPad ? [6, 5] : nil
        let side = min(b.width, b.height)
        if isPad {
            // A small caption at the top; the middle is where the thumb goes
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.frame = CGRect(x: 6, y: 6, width: b.width - 12, height: 16)
            label.alpha = 0.6
        }
        else {
            label.font = .systemFont(ofSize: max(10, min(18, side * 0.32)), weight: .semibold)
            label.frame = b.insetBy(dx: 4, dy: 2)
            label.alpha = 1
        }
        let iconSide = side * 0.5
        icon.frame = CGRect(x: b.midX - iconSide / 2, y: b.midY - iconSide / 2, width: iconSide, height: iconSide)
        knob.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        knob.cornerRadius = 20
        CATransaction.commit()
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let highlight = pressed && (UserDefaults.standard.object(forKey: "mnOSCPressHighlight") as? Bool ?? true)
        if widget.kind == .overlay {
            shape.fillColor = UIColor(white: 0, alpha: 0.35).cgColor
            shape.strokeColor = nil
        }
        else {
            shape.fillColor = highlight ? WidgetView.accent.withAlphaComponent(0.45).cgColor
                                        : UIColor(white: 0, alpha: isPad ? 0.12 : 0.35).cgColor
            shape.strokeColor = widget.border || highlight ? (highlight ? WidgetView.accent : UIColor(white: 1, alpha: 0.45)).cgColor : nil
        }
        shape.lineWidth = 1.5
        shape.shadowColor = WidgetView.accent.cgColor
        shape.shadowOffset = .zero
        shape.shadowRadius = 6
        shape.shadowOpacity = highlight ? 0.9 : 0
        CATransaction.commit()
        updateAlpha()
    }

    private func updateAlpha() {
        // Held buttons show at full strength even in a faded layout
        let a = (pressed ? 1 : CGFloat(widget.opacity) * globalOpacity) * (dimmed ? 0.35 : 1)
        alpha = max(a, 0.05)
    }

    // MARK: Pads

    func showTouch(origin: CGPoint?, at point: CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let origin, widget.kind == .stickPad || widget.kind == .directionPad {
            let r: CGFloat = widget.kind == .stickPad ? MNWidgetLayer.stickRadius : 50
            base.path = UIBezierPath(ovalIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2)).cgPath
            base.isHidden = false
        }
        else {
            base.isHidden = true
        }
        if let point {
            knob.position = point
            knob.isHidden = false
        }
        else {
            knob.isHidden = true
        }
        CATransaction.commit()
    }

    /// Trigger pads fill from the bottom as the value rises
    func showLevel(_ value: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if value > 0 {
            let h = bounds.height * value
            base.path = UIBezierPath(roundedRect: CGRect(x: 2, y: bounds.height - h, width: bounds.width - 4, height: h), cornerRadius: 8).cgPath
            base.fillColor = WidgetView.accent.withAlphaComponent(0.35).cgColor
            base.isHidden = false
        }
        else {
            base.isHidden = true
            base.fillColor = UIColor(white: 1, alpha: 0.08).cgColor
        }
        CATransaction.commit()
    }

    // MARK: Controller overlay

    /// Redraws the controller diagram (overlay widgets only)
    func refreshDiagram() {
        diagram?.setNeedsDisplay()
    }

    fileprivate static func accentColor() -> UIColor { accent }
}

/// The controller overlay's drawing: triggers and shoulders on top, sticks, d-pad and face
/// buttons, each lit while pressed. Proportions loosely follow an Xbox pad.
final class PadDiagramView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        PadDiagramView.drawPad(GCController.current?.extendedGamepad ?? GCController.controllers().first?.extendedGamepad,
                               in: bounds.insetBy(dx: 8, dy: 8))
    }

    private static func drawPad(_ pad: GCExtendedGamepad?, in r: CGRect) {
        let idle = UIColor(white: 1, alpha: 0.25)
        let lit = WidgetView.accentColor()
        func fill(_ path: UIBezierPath, _ on: Bool) {
            (on ? lit : idle).setFill()
            path.fill()
        }
        guard let pad else {
            let text = NSAttributedString(string: "No controller", attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.6),
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2))
            return
        }
        let u = min(r.width / 10, r.height / 6.5)
        let o = CGPoint(x: r.midX - 5 * u, y: r.midY - 3.25 * u)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        func circle(_ c: CGPoint, _ radius: CGFloat) -> UIBezierPath {
            UIBezierPath(ovalIn: CGRect(x: c.x - radius * u, y: c.y - radius * u, width: radius * 2 * u, height: radius * 2 * u))
        }
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: o.x + x * u, y: o.y + y * u, width: w * u, height: h * u)
        }
        // Triggers: outline with a fill that follows the analog value
        for (x, value) in [(CGFloat(0.6), pad.leftTrigger.value), (CGFloat(7.4), pad.rightTrigger.value)] {
            let frame = bar(x, 0, 2, 1)
            idle.setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: 0.3 * u).fill()
            lit.setFill()
            UIBezierPath(roundedRect: CGRect(x: frame.minX, y: frame.minY, width: frame.width * CGFloat(value), height: frame.height),
                         cornerRadius: 0.3 * u).fill()
        }
        fill(UIBezierPath(roundedRect: bar(0.4, 1.3, 2.4, 0.7), cornerRadius: 0.3 * u), pad.leftShoulder.isPressed)
        fill(UIBezierPath(roundedRect: bar(7.2, 1.3, 2.4, 0.7), cornerRadius: 0.3 * u), pad.rightShoulder.isPressed)
        // Sticks: a ring with a dot that moves
        for (c, stick, click) in [(p(1.8, 3.3), pad.leftThumbstick, pad.leftThumbstickButton),
                                  (p(6.4, 5.2), pad.rightThumbstick, pad.rightThumbstickButton)] {
            UIColor(white: 1, alpha: 0.4).setStroke()
            let ring = circle(c, 1)
            ring.lineWidth = 1
            ring.stroke()
            let dot = CGPoint(x: c.x + CGFloat(stick.xAxis.value) * 0.55 * u, y: c.y - CGFloat(stick.yAxis.value) * 0.55 * u)
            fill(circle(dot, 0.45), click?.isPressed == true)
        }
        // D-pad
        fill(UIBezierPath(rect: bar(3.3, 4.2, 0.6, 0.7)), pad.dpad.up.isPressed)
        fill(UIBezierPath(rect: bar(3.3, 5.5, 0.6, 0.7)), pad.dpad.down.isPressed)
        fill(UIBezierPath(rect: bar(2.6, 4.9, 0.7, 0.6)), pad.dpad.left.isPressed)
        fill(UIBezierPath(rect: bar(3.9, 4.9, 0.7, 0.6)), pad.dpad.right.isPressed)
        // Face buttons: Y top, B right, A bottom, X left
        fill(circle(p(8.2, 2.4), 0.45), pad.buttonY.isPressed)
        fill(circle(p(9.1, 3.3), 0.45), pad.buttonB.isPressed)
        fill(circle(p(8.2, 4.2), 0.45), pad.buttonA.isPressed)
        fill(circle(p(7.3, 3.3), 0.45), pad.buttonX.isPressed)
        // Menu buttons in the middle
        fill(circle(p(4.2, 3.3), 0.3), pad.buttonOptions?.isPressed == true)
        fill(circle(p(5.8, 3.3), 0.3), pad.buttonMenu.isPressed)
        fill(circle(p(5.0, 2.3), 0.35), pad.buttonHome?.isPressed == true)
    }
}
