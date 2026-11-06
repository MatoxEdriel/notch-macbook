import Foundation

struct DockerContainer: Identifiable, Equatable {
    let id: String
    let image: String
    let name: String
    let status: String
}

/// SOLO LECTURA: consulta `docker ps` periódicamente para mostrar qué imágenes corren.
@MainActor
final class DockerManager: ObservableObject {
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var dockerAvailable = true

    private var timer: Timer?
    private let work = DispatchQueue(label: "notchbar.docker", qos: .utility)
    private var inFlight = false

    nonisolated private static let candidates = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    /// Solo consulta Docker mientras el notch está abierto.
    func setWatching(_ on: Bool) {
        if on {
            guard timer == nil else { return }
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Consulta inmediata (p. ej. al abrir la pestaña).
    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        work.async { [weak self] in
            let result = Self.query()
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                switch result {
                case .some(let list):
                    self.dockerAvailable = true
                    if list != self.containers { self.containers = list }
                case .none:
                    self.dockerAvailable = false
                    if !self.containers.isEmpty { self.containers = [] }
                }
            }
        }
    }

    nonisolated private static func query() -> [DockerContainer]? {
        guard let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["ps", "--format", "{{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 4 else { return nil }
                return DockerContainer(id: f[0], image: f[1], name: f[2], status: f[3])
            }
    }
}
