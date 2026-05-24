import Cocoa

class NotchPanel: NSPanel {
    private let minWidth: CGFloat = 200
    private let maxWidth: CGFloat = 700
    private let minHeight: CGFloat = 32
    private let maxHeight: CGFloat = 320
    private let animationDuration: TimeInterval = 0.25

    private var isExpanded = false
    private var trackingArea: NSTrackingArea?
    private let contentContainer = NSView()

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        let screenWithNotch = NotchPanel.screenWithNotch() ?? NSScreen.main ?? NSScreen.screens.first!
        let notchHeight = screenWithNotch.safeAreaInsets.top
        let hasNotch = notchHeight > 0

        let screenFrame = screenWithNotch.frame
        let initialWidth = minWidth
        let initialHeight = minHeight
        let initialX = screenFrame.midX - (initialWidth / 2)
        let initialY = screenFrame.maxY - initialHeight

        let rect = NSRect(x: initialX, y: initialY, width: initialWidth, height: initialHeight)

        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: backingStoreType, defer: flag)

        self.level = .statusBar - 1
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.isMovableByWindowBackground = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        self.contentView?.addSubview(contentContainer)

        if let contentView = self.contentView {
            NSLayoutConstraint.activate([
                contentContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
                contentContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        setupTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func screenWithNotch() -> NSScreen? {
        return NSScreen.screens.first { screen in
            screen.safeAreaInsets.top > 0
        }
    }

    private func setupTrackingArea() {
        let rect = self.contentView?.bounds ?? .zero
        trackingArea = NSTrackingArea(
            rect: rect,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        if let trackingArea = trackingArea {
            self.contentView?.addTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if !isExpanded {
            animateToExpanded()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if isExpanded {
            animateToCollapsed()
        }
    }

    func attachContentView(_ view: NSView) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    func animateToCollapsed() {
        isExpanded = false
        animateResize(toWidth: minWidth, toHeight: minHeight)
    }

    func animateToExpanded() {
        isExpanded = true
        animateResize(toWidth: maxWidth, toHeight: maxHeight)
    }

    private func animateResize(toWidth: CGFloat, toHeight: CGFloat) {
        guard let screen = self.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let screenFrame = screen.frame
        let currentFrame = self.frame
        let newX = screenFrame.midX - (toWidth / 2)
        let newY = screenFrame.maxY - toHeight
        let newFrame = NSRect(x: newX, y: newY, width: toWidth, height: toHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }

    func positionOnScreenWithNotch() {
        guard let screen = NotchPanel.screenWithNotch() ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let screenFrame = screen.frame
        let currentWidth = self.frame.width
        let newX = screenFrame.midX - (currentWidth / 2)
        let newY = screenFrame.maxY - self.frame.height

        self.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
}
