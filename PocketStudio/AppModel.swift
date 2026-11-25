import SwiftUI
import AVFoundation
import AppKit
import Security

struct MediaFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isVideo: Bool {
        ["mov", "mp4", "m4v", "avi", "mts"].contains(url.pathExtension.lowercased())
    }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var volumes: [URL] = []
    @Published var selectedVolume: URL?
    @Published var files: [MediaFile] = []
    @Published var selectedFiles: Set<String> = []
    @Published var previewFile: MediaFile?
    @Published var destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @Published var status = "Connect your Pocket 3 to get started"
    @Published var isCopying = false
    @Published var copyProgress = 0.0
    @Published var githubOwner = ""
    @Published var repoName = "pocket-3-footage"
    @Published var folderName = "Footage"
    @Published var isPrivate = true
    @Published private(set) var isGitHubConnected = false
    @Published var githubStatus = "Not connected to GitHub"
    private var githubToken = ""
    @Published var isUploading = false
    @Published var uploadProgress = 0.0
    @Published var searchText = ""

    private var scanTimer: Timer?

    init() {
        refreshVolumes()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshVolumes() }
        }
        loadGitHubToken()
    }

    deinit { scanTimer?.invalidate() }

    var visibleFiles: [MediaFile] {
        files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var selectedMedia: [MediaFile] {
        files.filter { selectedFiles.contains($0.id) }
    }

    var selectedSize: Int64 { selectedMedia.reduce(0) { $0 + $1.size } }

    func refreshVolumes() {
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey], options: [.skipHiddenVolumes]) ?? []
        let candidates = mounted.filter { $0.path.hasPrefix("/Volumes/") }
        volumes = candidates
        if let current = selectedVolume, !candidates.contains(current) {
            selectedVolume = nil
            files = []
            selectedFiles = []
            previewFile = nil
            status = "Camera disconnected"
        }
        if selectedVolume == nil, let pocket = candidates.first(where: {
            let n = $0.lastPathComponent.lowercased()
            return n.contains("dji") || n.contains("pocket") || n.contains("untitled")
        }) {
            selectVolume(pocket)
        } else if selectedVolume == nil, candidates.count == 1 {
            selectVolume(candidates[0])
        }
    }

    func selectVolume(_ url: URL) {
        selectedVolume = url
        scanFiles()
        status = "Browsing \(url.lastPathComponent)"
    }

    func scanFiles() {
        guard let root = selectedVolume else { files = []; return }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        var found: [MediaFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard ["mov", "mp4", "m4v", "jpg", "jpeg", "png", "dng", "wav"].contains(ext) else { continue }
            found.append(MediaFile(url: url, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
        }
        files = found.sorted { $0.modified > $1.modified }
    }

    func toggle(_ file: MediaFile) {
        if selectedFiles.contains(file.id) { selectedFiles.remove(file.id) }
        else { selectedFiles.insert(file.id) }
    }

    func selectAll() { selectedFiles = Set(visibleFiles.map(\.id)) }
    func clearSelection() { selectedFiles.removeAll() }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Download Folder"
        if panel.runModal() == .OK, let url = panel.url { destination = url }
    }

    func copySelected() {
        let items = selectedMedia
        guard !items.isEmpty else { status = "Select at least one file"; return }
        isCopying = true
        copyProgress = 0
        status = "Copying \(items.count) file(s)…"
        Task.detached(priority: .userInitiated) { [weak self] in
            var copied = 0
            var errors: [String] = []
            for item in items {
                do {
                    let target = await MainActor.run { self?.destination.appendingPathComponent(item.name) ?? item.url }
                    var finalTarget = target
                    if FileManager.default.fileExists(atPath: finalTarget.path) {
                        let stem = target.deletingPathExtension().lastPathComponent
                        let ext = target.pathExtension
                        finalTarget = target.deletingLastPathComponent().appendingPathComponent("\(stem)-\(Int(Date().timeIntervalSince1970)).\(ext)")
                    }
                    try FileManager.default.copyItem(at: item.url, to: finalTarget)
                    copied += 1
                } catch { errors.append("\(item.name): \(error.localizedDescription)") }
                await MainActor.run {
                    self?.copyProgress = Double(copied + errors.count) / Double(items.count)
                }
            }
            await MainActor.run {
                self?.isCopying = false
                self?.status = errors.isEmpty ? "Downloaded \(copied) file(s) to \(self?.destination.lastPathComponent ?? "Downloads")" : "Copied \(copied); \(errors.count) failed"
            }
        }
    }

    func loginGitHub() {
        guard !GitHubOAuthConfig.clientID.contains("PASTE_YOUR_GITHUB_OAUTH_CLIENT_ID") else {
            githubStatus = "Set your GitHub OAuth App Client ID in GitHubOAuthConfig.swift first"
            return
        }
        githubStatus = "Starting GitHub sign-in…"
        Task {
            do {
                let session = try await GitHubOAuth.login()
                githubToken = session.accessToken
                isGitHubConnected = true
                githubStatus = "Connected as @\(session.login)"
                saveGitHubTokenToKeychain()
            } catch {
                githubStatus = "GitHub sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    func logoutGitHub() {
        githubToken = ""
        isGitHubConnected = false
        deleteGitHubTokenFromKeychain()
        githubStatus = "Disconnected from GitHub"
    }

    private func saveGitHubTokenToKeychain() {
        let data = Data(githubToken.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PocketStudio.GitHub",
            kSecAttrAccount as String: "oauth-access-token",
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let result = SecItemAdd(query as CFDictionary, nil)
        if result != errSecSuccess {
            githubStatus = "Signed in, but could not save the session to Keychain"
        }
    }

    private func loadGitHubToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PocketStudio.GitHub",
            kSecAttrAccount as String: "oauth-access-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            githubToken = token
            isGitHubConnected = true
            githubStatus = "GitHub session restored from Keychain"
        }
    }

    private func deleteGitHubTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PocketStudio.GitHub",
            kSecAttrAccount as String: "oauth-access-token"
        ]
        SecItemDelete(query as CFDictionary)
    }

    func createRepositoryAndUpload() {
        guard isGitHubConnected, !githubToken.isEmpty else { githubStatus = "Sign in to GitHub first"; return }
        guard !selectedMedia.isEmpty else { githubStatus = "Select files to upload"; return }
        guard !repoName.isEmpty, !folderName.isEmpty else { githubStatus = "Enter a repository and folder name"; return }
        let filesToUpload = selectedMedia
        let token = githubToken
        let repo = repoName
        let folder = folderName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let privacy = isPrivate
        isUploading = true
        uploadProgress = 0
        githubStatus = "Creating repository…"
        Task {
            do {
                let owner = try await GitHubClient(token: token).createRepository(name: repo, isPrivate: privacy)
                githubOwner = owner
                githubStatus = "Repository created. Preparing Git upload…"
                let result = try await GitHubClient(token: token).push(files: filesToUpload, owner: owner, repo: repo, folder: folder) { [weak self] progress in
                    Task { @MainActor in self?.uploadProgress = progress }
                }
                githubStatus = "Uploaded to github.com/\(owner)/\(repo) — \(result)"
            } catch {
                githubStatus = error.localizedDescription
            }
            isUploading = false
        }
    }
}

struct GitHubOAuthSession {
    let accessToken: String
    let login: String
}

private struct DeviceCodeResponse: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int?
}

private struct OAuthTokenResponse: Decodable {
    let access_token: String?
    let error: String?
    let error_description: String?
}

private struct GitHubUserResponse: Decodable {
    let login: String
}

enum GitHubOAuth {
    static func login() async throws -> GitHubOAuthSession {
        let clientID = GitHubOAuthConfig.clientID
        let deviceURL = URL(string: "https://github.com/login/device/code")!
        var deviceRequest = URLRequest(url: deviceURL)
        deviceRequest.httpMethod = "POST"
        deviceRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        deviceRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        deviceRequest.httpBody = formBody([
            "client_id": clientID,
            "scope": "repo"
        ])
        let (deviceData, deviceResponse) = try await URLSession.shared.data(for: deviceRequest)
        guard let deviceHTTP = deviceResponse as? HTTPURLResponse, (200...299).contains(deviceHTTP.statusCode) else {
            throw oauthError("Could not start GitHub device authorization")
        }
        let device = try JSONDecoder().decode(DeviceCodeResponse.self, from: deviceData)
        guard let verificationURL = URL(string: device.verification_uri) else {
            throw oauthError("GitHub returned an invalid verification URL")
        }

        await MainActor.run {
            NSWorkspace.shared.open(verificationURL)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(device.user_code, forType: .string)
        }

        let deadline = Date().addingTimeInterval(TimeInterval(device.expires_in))
        let interval = max(5, device.interval ?? 5)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            var poll = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            poll.httpMethod = "POST"
            poll.setValue("application/json", forHTTPHeaderField: "Accept")
            poll.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            poll.httpBody = formBody([
                "client_id": clientID,
                "device_code": device.device_code,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            let (tokenData, tokenResponse) = try await URLSession.shared.data(for: poll)
            guard let tokenHTTP = tokenResponse as? HTTPURLResponse, (200...299).contains(tokenHTTP.statusCode) else {
                throw oauthError("GitHub authorization polling failed")
            }
            let tokenResult = try JSONDecoder().decode(OAuthTokenResponse.self, from: tokenData)
            if let token = tokenResult.access_token {
                var userRequest = URLRequest(url: URL(string: "https://api.github.com/user")!)
                userRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                userRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (userData, _) = try await URLSession.shared.data(for: userRequest)
                let user = try JSONDecoder().decode(GitHubUserResponse.self, from: userData)
                return GitHubOAuthSession(accessToken: token, login: user.login)
            }
            switch tokenResult.error {
            case "authorization_pending":
                continue
            case "slow_down":
                try await Task.sleep(for: .seconds(5))
            case "expired_token":
                throw oauthError("The sign-in code expired. Please try again.")
            case "access_denied":
                throw oauthError("You denied the GitHub sign-in request.")
            case .some(let message):
                throw oauthError(tokenResult.error_description ?? message)
            case .none:
                continue
            }
        }
        throw oauthError("The sign-in code expired. Please try again.")
    }

    private static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = values.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    private static func oauthError(_ message: String) -> NSError {
        NSError(domain: "PocketStudio.GitHubOAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct GitHubClient {
    let token: String

    func createRepository(name: String, isPrivate: Bool) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/user/repos")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "private": isPrivate, "auto_init": false])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode) else {
            throw NSError(domain: "GitHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "GitHub repository creation failed: \(String(data: data, encoding: .utf8) ?? "unknown response"). Check token permissions and repository name."])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let owner = (json?["owner"] as? [String: Any])?["login"] as? String else {
            throw NSError(domain: "GitHub", code: 2, userInfo: [NSLocalizedDescriptionKey: "GitHub did not return an account name"])
        }
        return owner
    }

    func push(files: [MediaFile], owner: String, repo: String, folder: String, progress: @escaping (Double) -> Void) async throws -> String {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("PocketStudio-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        func run(_ executable: String, _ args: [String]) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            p.currentDirectoryURL = work
            var env = ProcessInfo.processInfo.environment
            env["GIT_TERMINAL_PROMPT"] = "0"
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try p.run()
            p.waitUntilExit()
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard p.terminationStatus == 0 else {
                throw NSError(domain: "Git", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: stderr.isEmpty ? stdout : stderr])
            }
            return stdout
        }
        let git = "/usr/bin/git"
        let lfsCandidates = ["/opt/homebrew/bin/git-lfs", "/usr/local/bin/git-lfs"]
        let lfsPath = lfsCandidates.first { fm.isExecutableFile(atPath: $0) }
        let largeFiles = files.filter { $0.size > 100 * 1024 * 1024 }
        for file in largeFiles where file.size >= 2_000_000_000 {
            throw NSError(domain: "Git LFS", code: 4, userInfo: [NSLocalizedDescriptionKey: "\(file.name) is 2 GB or larger. GitHub Free/Pro Git LFS has a 2 GB per-file limit. Split or store that file elsewhere."])
        }
        if !largeFiles.isEmpty && lfsPath == nil {
            throw NSError(domain: "Git LFS", code: 1, userInfo: [NSLocalizedDescriptionKey: "Large video files need Git LFS. Install it with: brew install git-lfs, then reopen PocketStudio."])
        }
        _ = try run(git, ["init", "-b", "main"])
        _ = try run(git, ["config", "user.name", "PocketStudio"])
        _ = try run(git, ["config", "user.email", "pocketstudio@users.noreply.github.com"])
        if let lfsPath {
            _ = try run(lfsPath, ["install", "--local"])
            _ = try run(lfsPath, ["track", "\(folder)/*"])
            _ = try run(git, ["add", ".gitattributes"])
            _ = try run(git, ["commit", "-m", "Configure Git LFS"])
        }
        let authURL = "https://x-access-token:\(token)@github.com/\(owner)/\(repo).git"
        _ = try run(git, ["remote", "add", "origin", authURL])
        // One commit and push per file keeps each push comfortably below GitHub's 2 GB push limit.
        for (index, file) in files.enumerated() {
            let targetDir = work.appendingPathComponent(folder, isDirectory: true)
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let target = targetDir.appendingPathComponent(file.name)
            try fm.copyItem(at: file.url, to: target)
            _ = try run(git, ["add", "--", "\(folder)/\(file.name)"])
            _ = try run(git, ["commit", "-m", "Add \(file.name)"])
            _ = try run(git, ["push", "-u", "origin", "main"])
            progress(Double(index + 1) / Double(files.count))
        }
        return "\(files.count) file(s)"
    }
}
