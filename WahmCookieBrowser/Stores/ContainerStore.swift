import Foundation
import WebKit

@MainActor
final class ContainerStore: ObservableObject {
    @Published private(set) var containers: [BrowserContainer] = []

    private let defaultsKey = "wahm.containers.v1"

    init() {
        load()
        if containers.isEmpty {
            addContainer(named: "القسم 1")
        }
    }

    func addContainer(named name: String? = nil) {
        let nextIndex = containers.count + 1
        let container = BrowserContainer(name: name ?? "قسم \(nextIndex)")
        containers.append(container)
        persist()
    }

    func rename(_ container: BrowserContainer, to name: String) {
        guard let index = containers.firstIndex(where: { $0.id == container.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        containers[index].name = trimmed
        persist()
    }

    func delete(_ container: BrowserContainer) {
        containers.removeAll { $0.id == container.id }
        persist()
        WKWebsiteDataStore.remove(forIdentifier: container.id) { error in
            if let error {
                print("Failed to remove data store for \(container.id): \(error)")
            }
        }
        if containers.isEmpty {
            addContainer(named: "القسم 1")
        }
    }

    func updateLastURL(_ containerID: UUID, url: URL?) {
        guard let index = containers.firstIndex(where: { $0.id == containerID }) else { return }
        let newValue = url?.absoluteString
        if containers[index].lastURLString != newValue {
            containers[index].lastURLString = newValue
            persist()
        }
    }

    func container(id: UUID) -> BrowserContainer? {
        containers.first { $0.id == id }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            containers = try JSONDecoder().decode([BrowserContainer].self, from: data)
        } catch {
            print("Failed to load containers: \(error)")
            containers = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(containers)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("Failed to save containers: \(error)")
        }
    }
}
