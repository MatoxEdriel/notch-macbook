import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var music: MusicManager
    @ObservedObject var clipboard: ClipboardManager

    var body: some View {
        let size = vm.contentSize
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if vm.isExpanded {
                    ExpandedView(vm: vm, music: music, clipboard: clipboard)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85, anchor: .top))
                                .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.06)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))))
                } else if let peek = vm.peek {
                    PeekView(item: peek, notchHeight: vm.notchSize.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                } else if vm.showsLiveActivity {
                    CompactView(vm: vm, music: music)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .padding(.horizontal, vm.topRadius)
            .background(NotchBackground(vm: vm, music: music))
            .clipShape(NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius))
            .shadow(color: .black.opacity(vm.isExpanded || vm.peek != nil ? 0.5 : 0), radius: 16, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.76), value: vm.isExpanded)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: vm.showsLiveActivity)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: vm.peek?.id)
    }
}


struct NotchBackground: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var music: MusicManager

    var body: some View {
        let tint = music.backgroundTint
        let showTint = vm.isExpanded && vm.tab == .music && music.hasTrack
        let start = UnitPoint(x: 0.5, y: vm.notchSize.height / vm.expandedSize.height)
        ZStack {
            Color.black
            LinearGradient(colors: [tint.opacity(0), tint.opacity(0.9)],
                           startPoint: start, endPoint: .bottom)
            RadialGradient(colors: [tint.opacity(0.7), tint.opacity(0)],
                           center: UnitPoint(x: 0.15, y: 0.7), startRadius: 0, endRadius: 260)
        }
        .opacity(showTint ? 1 : 0)
        .background(Color.black)
        .animation(.easeInOut(duration: 0.6), value: tint)
        .animation(.easeInOut(duration: 0.3), value: showTint)
    }
}


struct CompactView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack {
            ArtworkView(image: music.artwork, size: vm.notchSize.height - 10, radius: 6)
            Spacer()
            Visualizer(isPlaying: music.isPlaying, color: music.accentColor, height: 12)
        }
        .padding(.horizontal, 10)
        .frame(height: vm.notchSize.height)
    }
}


struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var music: MusicManager
    @ObservedObject var clipboard: ClipboardManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TabButton(symbol: "music.note", selected: vm.tab == .music) { vm.tab = .music }
                TabButton(symbol: "doc.on.clipboard", selected: vm.tab == .clipboard) { vm.tab = .clipboard }
                if vm.tab == .clipboard && !clipboard.items.isEmpty {
                    Button { clipboard.clear() } label: {
                        Text("Borrar").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(PressableStyle())
                    .help("Borrar historial")
                }
                Spacer()
                TimelineView(.everyMinute) { ctx in
                    Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().hour().minute())
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .frame(height: vm.notchSize.height)

            Group {
                switch vm.tab {
                case .music:
                    if music.hasTrack { PlayerView(music: music) } else { IdleView(music: music) }
                case .clipboard:
                    ClipboardTabView(clipboard: clipboard)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct TabButton: View {
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? .black : .white.opacity(0.6))
                .frame(width: 26, height: 20)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}


struct ClipboardTabView: View {
    @ObservedObject var clipboard: ClipboardManager

    var body: some View {
        if clipboard.items.isEmpty {
            HStack(spacing: 14) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                Text("Vacío")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(clipboard.items) { item in
                        ClipCard(item: item, clipboard: clipboard)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 112)
        }
    }
}

struct ClipCard: View {
    let item: ClipItem
    @ObservedObject var clipboard: ClipboardManager

    private let side: CGFloat = 106
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        let copied = clipboard.lastCopiedID == item.id
        ZStack(alignment: .topTrailing) {
            content
                .frame(width: side, height: side)
                .background(Color.white.opacity(0.08))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.1)))
                .overlay {
                    if copied {
                        ZStack {
                            Color.black.opacity(0.6)
                            VStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 26)).foregroundStyle(.green)
                                Text("Copiado").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            }
                        }
                        .clipShape(shape)
                        .transition(.opacity)
                    }
                }
                .contentShape(shape)
                .onTapGesture { clipboard.copy(item) }
                .onDrag { clipboard.dragProvider(for: item) }
                .help("Clic para copiar · Arrastra para soltar en otra app")

            Button { clipboard.remove(item) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85), .black.opacity(0.55))
            }
            .buttonStyle(PressableStyle())
            .padding(4)
        }
        .animation(.easeOut(duration: 0.2), value: copied)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let t = item.thumbnail {
                Image(nsImage: t).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
            }
        case .text(let s):
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: item.isLink ? "link" : "text.alignleft")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.isLink ? Color.blue : Color.white.opacity(0.5))
                Text(String(s.prefix(240)))
                    .font(.system(size: 11))
                    .foregroundStyle(item.isLink ? Color.blue.opacity(0.9) : Color.white.opacity(0.85))
                    .lineLimit(item.isLink ? 4 : 5)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .files(let urls):
            VStack(spacing: 6) {
                if let icon = item.thumbnail {
                    Image(nsImage: icon).resizable().frame(width: 48, height: 48)
                }
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) archivos")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(6)
        }
    }
}

struct PeekView: View {
    let item: ClipItem
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 10) {
                preview
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16)).foregroundStyle(.green)
            }
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
    }

    private var subtitle: String {
        if case .text(let s) = item.kind {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
        }
        return item.detail
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image:
            if let t = item.thumbnail { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill) }
        case .files:
            if let t = item.thumbnail { Image(nsImage: t).resizable() }
        case .text:
            ZStack {
                Color.white.opacity(0.1)
                Image(systemName: item.isLink ? "link" : "text.alignleft")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.isLink ? Color.blue : Color.white.opacity(0.8))
            }
        }
    }
}

struct PlayerView: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(image: music.artwork, size: 104, radius: 16)
                .shadow(color: music.accentColor.opacity(0.45), radius: 12)
                .scaleEffect(music.isPlaying ? 1 : 0.92)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: music.isPlaying)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(music.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    Spacer()
                    Visualizer(isPlaying: music.isPlaying, color: music.accentColor, height: 16)
                }
                Spacer(minLength: 0)
                ProgressBarView(music: music)
                HStack(spacing: 34) {
                    ControlButton(symbol: "backward.fill", size: 16) { music.previous() }
                    ControlButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 24) { music.playPause() }
                    ControlButton(symbol: "forward.fill", size: 16) { music.next() }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 104)
        }
    }
}

struct IdleView: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: nil, size: 64, radius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nada en reproducción")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text("Abre una app y pon algo de música")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            ForEach(PlayerSource.allCases, id: \.self) { src in
                if let url = src.appURL {
                    Button { music.open(src) } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 40, height: 40)
                    }
                    .buttonStyle(PressableStyle())
                    .help("Abrir \(src.rawValue)")
                }
            }
        }
        .padding(.top, 14)
    }
}


struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.55, green: 0.3, blue: 0.95),
                                            Color(red: 0.2, green: 0.5, blue: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct Visualizer: View {
    let isPlaying: Bool
    let color: Color
    let height: CGFloat

    var body: some View {
        VisualizerLayerView(isPlaying: isPlaying, color: color)
            .frame(width: VisualizerNSView.totalWidth, height: height)
    }
}

struct VisualizerLayerView: NSViewRepresentable {
    let isPlaying: Bool
    let color: Color

    func makeNSView(context: Context) -> VisualizerNSView { VisualizerNSView(frame: .zero) }

    func updateNSView(_ view: VisualizerNSView, context: Context) {
        view.color = NSColor(color)
        view.isPlaying = isPlaying
    }
}

final class VisualizerNSView: NSView {
    static let barCount = 4
    static let barWidth: CGFloat = 3
    static let spacing: CGFloat = 2
    static var totalWidth: CGFloat { CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing }

    private static let durations: [CFTimeInterval] = [0.42, 0.31, 0.53, 0.37]
    private static let restScale: CGFloat = 0.25
    private var bars: [CALayer] = []

    var color: NSColor = .white {
        didSet {
            guard color != oldValue else { return }
            bars.forEach { $0.backgroundColor = color.cgColor }
        }
    }

    var isPlaying = false {
        didSet { if isPlaying != oldValue { updateAnimations() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.backgroundColor = color.cgColor
            bar.cornerRadius = Self.barWidth / 2
            bar.transform = CATransform3DMakeScale(1, Self.restScale, 1)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let x0 = (bounds.width - Self.totalWidth) / 2
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
            bar.position = CGPoint(x: x0 + CGFloat(i) * (Self.barWidth + Self.spacing) + Self.barWidth / 2,
                                   y: bounds.midY)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimations()
    }

    private func updateAnimations() {
        let now = CACurrentMediaTime()
        for (i, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "pulse")
            guard isPlaying, window != nil else { continue }
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = Self.restScale
            a.toValue = 1.0
            a.duration = Self.durations[i % Self.durations.count]
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.beginTime = now - Double(i) * 0.13
            bar.add(a, forKey: "pulse")
        }
    }
}

struct ProgressBarView: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let current = music.scrubPosition ?? music.elapsed(at: ctx.date)
            let frac = music.duration > 0 ? min(max(current / music.duration, 0), 1) : 0
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(music.accentColor)
                            .frame(width: max(5, geo.size.width * frac))
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            music.scrubPosition = clamp(v.location.x / geo.size.width) * music.duration
                        }
                        .onEnded { v in
                            music.seek(to: clamp(v.location.x / geo.size.width) * music.duration)
                            music.scrubPosition = nil
                        })
                }
                .frame(height: music.scrubPosition == nil ? 5 : 7)
                .animation(.easeOut(duration: 0.15), value: music.scrubPosition == nil)

                HStack {
                    Text(format(current))
                    Spacer()
                    Text("-" + format(max(music.duration - current, 0)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    private func format(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
