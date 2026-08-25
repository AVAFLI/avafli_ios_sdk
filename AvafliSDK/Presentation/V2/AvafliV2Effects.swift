//
//  AvafliV2Effects.swift
//  AvafliSDK
//
//  Motion for the V2 experience: Joe's ACTUAL Figma animation files (bundled
//  GIFs, played via AvafliV2GifView) for the Day 2+ reveal beat, plus native
//  SwiftUI confetti/checkmark/glow used by the modals and toast bar.
//

import SwiftUI
import ImageIO

// MARK: - Confetti

/// A looping confetti field. `style` picks the palette: `.celebration` is the
/// multicolor sprinkle from the claim/celebration modals and streak tiles;
/// `.gold` is the winner-modal gold sparkle.
struct AvafliV2ConfettiView: View {
    enum Style { case celebration, gold }

    var style: Style = .celebration
    var count: Int = 42
    /// Continuous drift when true (dashboard accents); one-shot-feel flutter
    /// stays looping either way — Joe's GIFs loop too.
    var speed: Double = 1

    private static let celebrationPalette: [Color] = [
        Color(red: 0.96, green: 0.31, blue: 0.28), // red
        Color(red: 0.35, green: 0.78, blue: 0.42), // green
        Color(red: 0.30, green: 0.62, blue: 0.99), // blue
        Color(red: 0.99, green: 0.80, blue: 0.28), // yellow
        Color(red: 0.72, green: 0.52, blue: 0.96), // purple
    ]
    private static let goldPalette: [Color] = [
        Color(red: 1.00, green: 0.84, blue: 0.35),
        Color(red: 0.94, green: 0.70, blue: 0.18),
        Color(red: 1.00, green: 0.93, blue: 0.66),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate * speed
                let palette = style == .celebration ? Self.celebrationPalette : Self.goldPalette
                for i in 0..<count {
                    // Deterministic per-particle parameters (no Math.random —
                    // stable across frames).
                    let seed = Double(i)
                    let fx = fract(seed * 0.61803398875)          // 0..1 x anchor
                    let fall = 8.0 + fract(seed * 0.7548776662) * 7.0   // fall period s
                    let phase = fract(seed * 0.2928932188)
                    let progress = fract(t / fall + phase)        // 0..1 down screen
                    let sway = sin((t * 1.7) + seed * 1.3) * 9.0
                    let x = fx * size.width + sway
                    let y = progress * (size.height + 24) - 12
                    let rotation = Angle.radians(t * 2.1 + seed)
                    let w = 4.0 + fract(seed * 0.833) * 4.0
                    let h = w * (0.55 + fract(seed * 0.377) * 0.5)
                    let alpha = style == .gold ? 0.55 + fract(seed * 0.51) * 0.45 : 0.9

                    var particle = context
                    particle.translateBy(x: x, y: y)
                    particle.rotate(by: rotation)
                    // Flutter: squash on one axis as the piece "tumbles".
                    let squash = 0.35 + abs(sin(t * 2.6 + seed * 2.0)) * 0.65
                    particle.scaleBy(x: 1, y: squash)
                    particle.opacity = alpha
                    particle.fill(
                        Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 1),
                        with: .color(palette[i % palette.count])
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fract(_ v: Double) -> Double { v - v.rounded(.down) }
}

// MARK: - Animated checkmark (draw-on)

/// The white circle-check from Joe's modals: the circle sweeps in, then the
/// check strokes on. Replaces the static GIF frame.
struct AvafliV2AnimatedCheckmark: View {
    var lineWidth: CGFloat = 7
    @State private var circleProgress: CGFloat = 0
    @State private var checkProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: circleProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: checkProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) { circleProgress = 1 }
            withAnimation(.easeOut(duration: 0.35).delay(0.4)) { checkProgress = 1 }
        }
    }

    /// Check glyph matching the design: starts left-center, dips to the low
    /// point, kicks up past the circle's top-right edge.
    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.width * 0.26, y: rect.height * 0.54))
            p.addLine(to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.72))
            p.addLine(to: CGPoint(x: rect.width * 0.94, y: rect.height * 0.22))
            return p
        }
    }
}

// MARK: - Remote image prewarming (publisher prize art + logo)

/// Decodes the publisher's remote art (prize hero + logo) into an in-memory
/// cache ahead of the drawer opening, so the prize card paints its image on its
/// FIRST frame instead of popping in a beat after everything else.
///
/// This is the remote-image sibling of `AvafliV2GifAsset.prewarm`: the SDK learns
/// `prizeImageUrl` at registration / giveaway refresh, long before the
/// experience is presented, which is exactly the moment to pay the download.
///
/// The cache is read SYNCHRONOUSLY by `AvafliV2RemoteImage` at init — something
/// `AsyncImage` structurally cannot do (it always costs at least one blank
/// frame, which is the late pop-in this replaces).
enum AvafliV2ImageWarmer {
    private static let lock = NSLock()
    private static var images: [String: UIImage] = [:]
    /// URLs already warmed (or in flight) — a repeated refresh is a no-op.
    private static var warmed: Set<String> = []

    /// The byte fetch. Injectable so tests can exercise warm / no-op / retry
    /// without touching the network. Completion may arrive on any thread.
    static var fetch: (String, @escaping (UIImage?) -> Void) -> Void = defaultFetch

    /// Kicks off a decode for `url` if it hasn't been warmed yet. Silent and
    /// fire-and-forget: a failure just means the widget loads it normally — and
    /// drops the URL from the warmed set so the next refresh can retry it.
    static func prewarm(_ url: String?) {
        guard let url, !url.isEmpty, URL(string: url) != nil else { return }
        lock.lock()
        let isNew = warmed.insert(url).inserted
        lock.unlock()
        guard isNew else { return }
        fetch(url) { image in
            lock.lock()
            if let image {
                images[url] = image
            } else {
                warmed.remove(url)
            }
            lock.unlock()
        }
    }

    /// Synchronous cache read — a warmed URL paints on the first frame.
    static func cached(_ url: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images[url]
    }

    /// Load for display: a cache hit returns immediately (on the caller's
    /// thread), a miss goes to the network and populates the cache on the way
    /// through. Completion is always delivered on the main queue for a miss.
    static func load(_ url: String, completion: @escaping (UIImage?) -> Void) {
        if let hit = cached(url) { completion(hit); return }
        fetch(url) { image in
            lock.lock()
            if let image {
                images[url] = image
                warmed.insert(url)
            } else {
                warmed.remove(url)
            }
            lock.unlock()
            DispatchQueue.main.async { completion(image) }
        }
    }

    private static func defaultFetch(_ url: String, completion: @escaping (UIImage?) -> Void) {
        guard let parsed = URL(string: url) else { completion(nil); return }
        URLSession.shared.dataTask(with: parsed) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { completion(nil); return }
            // Rasterize off-main so the first display is a straight blit.
            completion(image.preparingForDisplay() ?? image)
        }.resume()
    }

    // MARK: Test hooks

    static func isWarmed(_ url: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return warmed.contains(url)
    }

    static func resetForTesting() {
        lock.lock()
        images.removeAll()
        warmed.removeAll()
        lock.unlock()
        fetch = defaultFetch
    }
}

/// Fade-in duration for a remote image that wasn't already decoded — short
/// enough to feel instant, long enough to avoid a hard pop.
let avafliV2ImageFadeDuration: Double = 0.2

/// A remote image with the SDK's standard arrival behaviour: NO fade at all
/// when the warmer already decoded it (the common case — it paints with the
/// rest of the card), otherwise a dark placeholder (never a blank/white flash)
/// and a ~200ms fade-in when the bytes land, with a caller-supplied fallback on
/// error.
struct AvafliV2RemoteImage<Fallback: View>: View {
    let url: String
    let contentMode: ContentMode
    /// Painted behind the image while it decodes.
    let placeholderColor: Color
    let fallback: () -> Fallback

    @State private var image: UIImage?
    @State private var failed = false
    @State private var opacity: Double

    init(
        url: String,
        contentMode: ContentMode = .fill,
        placeholderColor: Color = AvafliV2Color.deepCharcoal,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholderColor = placeholderColor
        self.fallback = fallback
        let warm = AvafliV2ImageWarmer.cached(url)
        _image = State(initialValue: warm)
        // Prewarmed: already decoded, so it paints fully opaque on the first
        // frame with everything else — no fade, no placeholder.
        _opacity = State(initialValue: warm == nil ? 0 : 1)
    }

    var body: some View {
        ZStack {
            if failed {
                fallback()
            } else {
                placeholderColor
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .opacity(opacity)
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard image == nil, !failed else { return }
        AvafliV2ImageWarmer.load(url) { loaded in
            guard let loaded else {
                failed = true
                return
            }
            image = loaded
            withAnimation(.easeOut(duration: avafliV2ImageFadeDuration)) { opacity = 1 }
        }
    }
}

// MARK: - Bundled GIF playback (Joe's Figma animation files)

/// A decoded, downsampled GIF: frames + the per-frame start times from the
/// file's own delay table. Decoding a 1500×1500 47-frame GIF takes hundreds
/// of milliseconds, so assets are cached and can be prewarmed off-main
/// BEFORE the reveal beat needs them.
final class AvafliV2GifAsset {
    let frames: [UIImage]
    /// Cumulative start time (seconds) of each frame.
    let starts: [Double]
    let duration: Double

    private init?(url: URL, maxPixelSize: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        var frames: [UIImage] = []
        var starts: [Double] = []
        var t: Double = 0
        for index in 0..<count {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: cg))
            starts.append(t)
            t += Self.delay(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        self.frames = frames
        self.starts = starts
        self.duration = t
    }

    /// Frame for `time` seconds into playback. Past the end: the LAST frame
    /// (one-shot playback freezes on it) unless `loops`.
    func frame(at time: Double, loops: Bool) -> UIImage {
        var t = time
        if loops, duration > 0 { t = t.truncatingRemainder(dividingBy: duration) }
        guard t < duration else { return frames[frames.count - 1] }
        var index = 0
        for (i, start) in starts.enumerated() where start <= t { index = i }
        return frames[index]
    }

    private static func delay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        let d = unclamped > 0.011 ? unclamped : (gif[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)
        return max(d, 0.02)
    }

    // MARK: Cache

    private static let lock = NSLock()
    private static var cache: [String: AvafliV2GifAsset] = [:]
    private static let decodeQueue = DispatchQueue(label: "com.winr.gif-decode", qos: .userInitiated)

    static func cached(_ name: String) -> AvafliV2GifAsset? {
        lock.lock(); defer { lock.unlock() }
        return cache[name]
    }

    /// Decode into the cache off-main so a later mount plays instantly.
    static func prewarm(_ name: String) {
        decodeQueue.async { _ = load(name) }
    }

    /// Cached load; decodes synchronously on a miss.
    static func load(_ name: String) -> AvafliV2GifAsset? {
        if let hit = cached(name) { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "gif"),
              let asset = AvafliV2GifAsset(url: url, maxPixelSize: 600) else { return nil }
        lock.lock(); cache[name] = asset; lock.unlock()
        return asset
    }
}

/// Plays a bundled GIF ONCE, starting exactly when the view mounts, honoring
/// the file's own per-frame delays. After the last frame it HOLDS there
/// (frozen, still rendered) — it does not disappear. `loops: true` opts into
/// continuous looping instead.
struct AvafliV2GifView: View {
    let name: String
    var loops: Bool = false
    var onFinished: (() -> Void)? = nil

    @State private var asset: AvafliV2GifAsset?
    @State private var startDate = Date()
    @State private var finished = false

    init(_ name: String, loops: Bool = false, onFinished: (() -> Void)? = nil) {
        self.name = name
        self.loops = loops
        self.onFinished = onFinished
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { context in
            Group {
                if let asset {
                    Image(uiImage: asset.frame(at: context.date.timeIntervalSince(startDate), loops: loops))
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
        }
        .onAppear {
            // Mount IS the beat: the playback clock starts now, even if the
            // frames are still decoding (prewarming makes that a non-event).
            startDate = Date()
            if let hit = AvafliV2GifAsset.cached(name) {
                begin(with: hit)
            } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    let loaded = AvafliV2GifAsset.load(name)
                    DispatchQueue.main.async {
                        guard let loaded, asset == nil else { return }
                        begin(with: loaded)
                    }
                }
            }
        }
    }

    private func begin(with loaded: AvafliV2GifAsset) {
        asset = loaded
        guard !loops else { return }
        // Freeze the timeline on the held last frame once playback completes,
        // measured against the mount clock so a slow decode can't stretch it.
        let remaining = max(0, loaded.duration - Date().timeIntervalSince(startDate))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            finished = true
            onFinished?()
        }
    }
}

// MARK: - Pulsing glow (active streak tile)

struct AvafliV2PulseGlow: ViewModifier {
    let accent: Color
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: accent.opacity(pulsing ? 0.95 : 0.55), radius: pulsing ? 14 : 7)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

extension View {
    /// Joe's active-tile treatment: the accent glow breathes.
    func avafliPulseGlow(_ accent: Color) -> some View {
        modifier(AvafliV2PulseGlow(accent: accent))
    }
}
