import AppKit
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab { case music, clipboard, docker }

    @Published var isExpanded = false { didSet { if isExpanded != oldValue { onExpandedChange?(isExpanded) } } }
    var onExpandedChange: ((Bool) -> Void)?
    @Published var tab: Tab = .music
    @Published var peek: ClipItem?
    private var peekWork: DispatchWorkItem?
    @Published var notchSize: CGSize
    @Published var screenFrame: CGRect

    let expandedSize = CGSize(width: 520, height: 182)
    let music: MusicManager
    private var cancellable: AnyCancellable?

    init(music: MusicManager, notchSize: CGSize, screenFrame: CGRect) {
        self.music = music
        self.notchSize = notchSize
        self.screenFrame = screenFrame
        cancellable = music.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var showsLiveActivity: Bool { music.hasTrack && music.isPlaying }

    var contentSize: CGSize {
        if isExpanded { return expandedSize }
        if peek != nil { return CGSize(width: notchSize.width + 190, height: notchSize.height + 56) }
        if showsLiveActivity { return CGSize(width: notchSize.width + 84, height: notchSize.height) }
        return notchSize
    }

    func showPeek(_ item: ClipItem) {
        guard !isExpanded else { return }
        peek = item
        peekWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.peek = nil }
        peekWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }

    var topRadius: CGFloat { isExpanded || peek != nil ? 14 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 32 : (peek != nil ? 22 : 12) }

    var shapeSize: CGSize {
        CGSize(width: contentSize.width + topRadius * 2, height: contentSize.height)
    }

    func hitRect(padding: CGFloat) -> CGRect {
        let s = shapeSize
        return CGRect(x: screenFrame.midX - s.width / 2 - padding,
                      y: screenFrame.maxY - s.height - padding,
                      width: s.width + padding * 2,
                      height: s.height + padding + 4)
    }
}
