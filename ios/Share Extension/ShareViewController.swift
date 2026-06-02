import MobileCoreServices
import UIKit

private let appGroupId = "group.ai.portraitor.portraitorMobile"
private let hostAppBundleIdentifier = "ai.portraitor.portraitorMobile"
private let userDefaultsKey = "ShareKey"
private let userDefaultsMessageKey = "ShareMessageKey"

private struct SharedMediaFile: Codable {
    let path: String
    let mimeType: String?
    let thumbnail: String?
    let duration: Double?
    let message: String?
    let type: String
}

class ShareViewController: UIViewController {
    private var sharedMedia: [SharedMediaFile] = []
    private var pendingLoads = 0
    private var didFinish = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processSharedItems()
    }

    private func processSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish()
            return
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if loadFile(from: provider) { continue }
                if loadText(from: provider) { continue }
                if loadURL(from: provider) { continue }
            }
        }

        if pendingLoads == 0 {
            finish()
        }
    }

    private func loadFile(from provider: NSItemProvider) -> Bool {
        let typeIdentifiers = [
            kUTTypeFileURL as String,
            "public.zip-archive",
            "com.pkware.zip-archive",
            "public.data",
        ]

        guard let typeIdentifier = typeIdentifiers.first(where: provider.hasItemConformingToTypeIdentifier) else {
            return false
        }

        pendingLoads += 1
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            defer { self?.loadFinished() }

            if let url = item as? URL {
                self?.copySharedFile(from: url)
            } else if let data = item as? Data {
                self?.writeSharedData(data, suggestedName: "SharedChatExport.zip", mimeType: "application/zip")
            }
        }

        return true
    }

    private func loadText(from provider: NSItemProvider) -> Bool {
        let typeIdentifier = kUTTypeText as String
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else {
            return false
        }

        pendingLoads += 1
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            defer { self?.loadFinished() }

            if let text = item as? String {
                self?.sharedMedia.append(SharedMediaFile(
                    path: text,
                    mimeType: "text/plain",
                    thumbnail: nil,
                    duration: nil,
                    message: nil,
                    type: "text"
                ))
            }
        }

        return true
    }

    private func loadURL(from provider: NSItemProvider) -> Bool {
        let typeIdentifier = kUTTypeURL as String
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else {
            return false
        }

        pendingLoads += 1
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
            defer { self?.loadFinished() }

            if let url = item as? URL {
                self?.sharedMedia.append(SharedMediaFile(
                    path: url.absoluteString,
                    mimeType: nil,
                    thumbnail: nil,
                    duration: nil,
                    message: nil,
                    type: "url"
                ))
            }
        }

        return true
    }

    private func copySharedFile(from url: URL) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return
        }

        let destination = uniqueDestinationURL(in: container, originalName: url.lastPathComponent)

        do {
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: url, to: destination)
            sharedMedia.append(SharedMediaFile(
                path: destination.absoluteString.removingPercentEncoding ?? destination.absoluteString,
                mimeType: mimeType(for: destination),
                thumbnail: nil,
                duration: nil,
                message: nil,
                type: "file"
            ))
        } catch {
            return
        }
    }

    private func writeSharedData(_ data: Data, suggestedName: String, mimeType: String) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return
        }

        let destination = uniqueDestinationURL(in: container, originalName: suggestedName)

        do {
            try data.write(to: destination, options: .atomic)
            sharedMedia.append(SharedMediaFile(
                path: destination.absoluteString.removingPercentEncoding ?? destination.absoluteString,
                mimeType: mimeType,
                thumbnail: nil,
                duration: nil,
                message: nil,
                type: "file"
            ))
        } catch {
            return
        }
    }

    private func uniqueDestinationURL(in container: URL, originalName: String) -> URL {
        let name = originalName.isEmpty ? "SharedChatExport.zip" : originalName
        let timestamp = Int(Date().timeIntervalSince1970)
        return container.appendingPathComponent("\(timestamp)-\(name)")
    }

    private func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "zip":
            return "application/zip"
        case "txt":
            return "text/plain"
        case "html", "htm":
            return "text/html"
        default:
            return nil
        }
    }

    private func loadFinished() {
        DispatchQueue.main.async {
            self.pendingLoads -= 1
            if self.pendingLoads <= 0 {
                self.finish()
            }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true

        if !sharedMedia.isEmpty {
            let userDefaults = UserDefaults(suiteName: appGroupId)
            let data = try? JSONEncoder().encode(sharedMedia)
            userDefaults?.set(data, forKey: userDefaultsKey)
            userDefaults?.set(nil, forKey: userDefaultsMessageKey)
            userDefaults?.synchronize()
            openHostApp()
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    private func openHostApp() {
        guard let url = URL(string: "ShareMedia-\(hostAppBundleIdentifier):share") else {
            return
        }

        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = responder?.next
        }
    }
}
