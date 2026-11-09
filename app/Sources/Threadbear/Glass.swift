import AppKit
import Observation
import SwiftUI
import Synchronization

/// The MonoCode look (Jordan, 6 Nov): the window as frosted glass over the
/// desktop, and MonoCode 0.16's style (its text sizes, flat grey pills
/// under the message box and grey message bubbles). Both are this Mac's own
/// settings (Settings > General > Appearance), kept in UserDefaults like
/// the zoom, and both start on.
///
/// Glass is macOS's own blur behind the window (an NSVisualEffectView that
/// blends behind it) with a tint over it: `shellTint` under everything, and
/// `cardTint` again over the thread and the panels beside it, so the
/// sidebar is the clearest part, as in MonoCode. `strength` runs between the
/// two mockups Jordan picked: 0 is "Glass everywhere" (MonoCode's own 80%
/// window with a 40% card), 1 is "Clearer glass".
@Observable @MainActor
final class Glass {
    static let shared = Glass()

    nonisolated static let enabledKey = "glassEnabled"
    nonisolated static let strengthKey = "glassStrength"
    nonisolated static let monoStyleKey = "monoCodeStyle"
    nonisolated static let defaultStrength = 0.5
    /// For renderers off the main thread (TypeScale), as `TextZoom.current`.
    nonisolated static let monoStyleNow = Atomic<Bool>(true)

    var enabled: Bool { didSet { defaults.set(enabled, forKey: Self.enabledKey) } }
    /// 0...1, how much of the desktop shows through.
    var strength: Double {
        didSet {
            // Setting it again in its own didSet doesn't call didSet again.
            let clamped = min(max(strength, 0), 1)
            if clamped != strength { strength = clamped }
            defaults.set(strength, forKey: Self.strengthKey)
        }
    }
    /// MonoCode's text sizes (TypeScale.pick), its flat square-cornered
    /// pills and send button under the message box, and grey bubbles.
    var monoStyle: Bool {
        didSet {
            defaults.set(monoStyle, forKey: Self.monoStyleKey)
            Self.monoStyleNow.store(monoStyle, ordering: .relaxed)
            // The transcript and the composer re-lay and redraw themselves
            // on the zoom's notice; new sizes and bubbles need the same.
            NotificationCenter.default.post(name: TextZoom.didChange, object: TextZoom.shared)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let saved = defaults.object(forKey: Self.strengthKey) as? Double ?? Self.defaultStrength
        strength = min(max(saved, 0), 1)
        monoStyle = defaults.object(forKey: Self.monoStyleKey) as? Bool ?? true
        Self.monoStyleNow.store(monoStyle, ordering: .relaxed)
    }

    /// How opaque the tint over the blur is, under the whole window:
    /// 0.62 at "Glass everywhere", 0.45 at "Clearer glass".
    var shellTint: Double { Self.mix(0.62, 0.45, strength) }
    /// The thread's and the side panels' extra tint, over the shell's:
    /// 0.40 down to 0.28.
    var cardTint: Double { Self.mix(0.40, 0.28, strength) }

    nonisolated static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * min(max(t, 0), 1) }

    /// The tint's colour: MonoCode's #0d0d0d in dark, its #f5f5f5 in light.
    static let shellColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 13 / 255, green: 13 / 255, blue: 13 / 255, alpha: 1)
            : NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
    })
    /// The card's: MonoCode's rgba(6,6,6) in dark, white in light.
    static let cardColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 6 / 255, green: 6 / 255, blue: 6 / 255, alpha: 1)
            : .white
    })
    /// The thread card's corners while glass is on, as MonoCode's 10 pt.
    static var cardCorner: CGFloat { zoomed(10) }
    /// The room left under the card, so its bottom corners show.
    static var cardMargin: CGFloat { zoomed(6) }

    /// MonoCode's wash over the shell, which also shows in the 1 pt gaps
    /// between panels as their dividers: its text colour at 5%.
    static let wash = Color.primary.opacity(0.05)
}

/// Under the whole window while glass is on: the desktop, blurred by macOS,
/// with the shell's tint over it. Makes the window see-through for it, and
/// opaque again when glass goes off.
struct GlassBackground: View {
    private let glass = Glass.shared

    var body: some View {
        ZStack {
            if glass.enabled {
                BehindWindowBlur()
                Glass.shellColor.opacity(glass.shellTint)
            }
        }
        .background(GlassWindowSetter(enabled: glass.enabled))
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// macOS's blur of whatever's behind the window.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        // Stays frosted while another app is in front, as MonoCode's does;
        // `.followsWindowActiveState` turns it flat grey then.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The window has to be clear for the blur to show through it.
private struct GlassWindowSetter: NSViewRepresentable {
    let enabled: Bool

    func makeNSView(context: Context) -> Setter { Setter() }

    func updateNSView(_ view: Setter, context: Context) {
        view.enabled = enabled
        view.apply()
    }

    final class Setter: NSView {
        var enabled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.isOpaque = !enabled
            window.backgroundColor = enabled ? .clear : .windowBackgroundColor
        }
    }
}
