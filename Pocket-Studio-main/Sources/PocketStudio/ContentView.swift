import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                main
            }
            statusBar
        }
        .background(Color(red: 0.055, green: 0.067, blue: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(12)
        .background(Color.black)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.aperture").font(.system(size: 22, weight: .semibold)).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("POCKET STUDIO").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1.5)
                Text("DJI media manager").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(model.selectedVolume == nil ? .orange : .green).frame(width: 7, height: 7)
                Text(model.selectedVolume == nil ? "No camera detected" : "Device connected").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 8).background(.white.opacity(0.06), in: Capsule())
            Button { model.refreshVolumes() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, 22).padding(.vertical, 17)
        .background(Color.white.opacity(0.025))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKSPACE").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 18)
            sideButton("Media browser", icon: "rectangle.stack", index: 0)
            sideButton("GitHub upload", icon: "arrow.up.to.line", index: 1)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("SOURCE").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                if model.volumes.isEmpty {
                    Label("Waiting for camera", systemImage: "cable.connector").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(model.volumes, id: \.path) { volume in
                        Button { model.selectVolume(volume) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "externaldrive.fill").foregroundStyle(.cyan)
                                Text(volume.lastPathComponent).lineLimit(1)
                                Spacer()
                                if model.selectedVolume == volume { Image(systemName: "checkmark").foregroundStyle(.cyan) }
                            }.font(.system(size: 11)).padding(8).background(model.selectedVolume == volume ? .cyan.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).foregroundStyle(.white)
                    }
                }
            }.padding(12)
            Text("Pocket Studio  •  v1.0").font(.system(size: 10)).foregroundStyle(.tertiary).padding(12)
        }
        .frame(width: 210).background(Color.white.opacity(0.018))
    }

    private func sideButton(_ title: String, icon: String, index: Int) -> some View {
        Button { tab = index } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(tab == index ? .white : .secondary)
                .padding(11).background(tab == index ? .cyan.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }

    @ViewBuilder private var main: some View {
        if tab == 0 { mediaBrowser } else { githubPanel }
    }

    private var mediaBrowser: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your footage").font(.system(size: 23, weight: .semibold))
                    Text(model.selectedVolume?.path ?? "Connect the Pocket 3 and choose File Transfer").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search media", text: $model.searchText).textFieldStyle(.plain).padding(9).frame(width: 180).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                Button("Refresh") { model.scanFiles() }.buttonStyle(SecondaryButtonStyle())
            }.padding(22)
            if model.selectedVolume == nil {
                VStack(spacing: 12) {
                    Image(systemName: "camera")
                        .font(.system(size: 42))
                        .foregroundStyle(.cyan)
                    Text("Connect your Pocket 3")
                        .font(.title2.bold())
                    Text("Power on the camera, connect USB-C, then tap File Transfer on its screen.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(model.visibleFiles.count) items").foregroundStyle(.secondary)
                    Spacer()
                    Button("Select all") { model.selectAll() }.buttonStyle(.plain).foregroundStyle(.cyan)
                    Button("Clear") { model.clearSelection() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }.font(.system(size: 11)).padding(.horizontal, 22).padding(.bottom, 10)
                HStack(spacing: 14) {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.visibleFiles) { file in
                                fileRow(file)
                            }
                        }.padding(.horizontal, 14).padding(.bottom, 14)
                    }
                    .frame(minWidth: 360)
                    Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                    previewPane
                        .frame(minWidth: 280, maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            bottomActions
        }
    }

    private func fileRow(_ file: MediaFile) -> some View {
        let selected = model.selectedFiles.contains(file.id)
        return Button {
            model.toggle(file)
            model.previewFile = file
        } label: {
            HStack(spacing: 10) {
                Image(systemName: file.isVideo ? "film" : "photo").font(.system(size: 18)).foregroundStyle(.cyan).frame(width: 34, height: 34).background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text("\(file.sizeText)  •  \(file.modified.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
            }.padding(9).background(selected ? .cyan.opacity(0.12) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? .cyan.opacity(0.4) : .clear, lineWidth: 1))
        }.buttonStyle(.plain).foregroundStyle(.white)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PREVIEW").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(.secondary)
            if let file = model.previewFile {
                if file.isVideo {
                    VideoPlayer(player: AVPlayer(url: file.url))
                        .frame(maxWidth: .infinity).aspectRatio(16/9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(nsImage: NSImage(contentsOf: file.url) ?? NSImage()).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 210)
                }
                Text(file.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text(file.sizeText).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                    Label("Reveal on device", systemImage: "folder")
                }.buttonStyle(SecondaryButtonStyle())
            } else {
                Spacer()
                Image(systemName: "play.rectangle").font(.system(size: 42)).foregroundStyle(.white.opacity(0.15)).frame(maxWidth: .infinity)
                Text("Select a video or photo to preview").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
        }.padding(18)
    }

    private var bottomActions: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(model.selectedMedia.count) selected").font(.system(size: 11, weight: .semibold))
                Text(ByteCountFormatter.string(fromByteCount: model.selectedSize, countStyle: .file)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.chooseDestination() } label: { Label(model.destination.lastPathComponent, systemImage: "folder") }.buttonStyle(SecondaryButtonStyle())
            Button { model.copySelected() } label: { Label(model.isCopying ? "Downloading…" : "Download selected", systemImage: "arrow.down.circle.fill") }.buttonStyle(PrimaryButtonStyle()).disabled(model.selectedFiles.isEmpty || model.isCopying)
        }.padding(16).background(.white.opacity(0.025))
    }

    private var githubPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Publish to GitHub").font(.system(size: 23, weight: .semibold))
                Text("Create a repository and place your selected footage inside a folder you name.").font(.system(size: 12)).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("GitHub account", systemImage: "person.crop.circle").font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 10) {
                            Image(systemName: model.isGitHubConnected ? "checkmark.circle.fill" : "person.crop.circle")
                                .foregroundStyle(model.isGitHubConnected ? .green : .secondary)
                            Text(model.isGitHubConnected ? "GitHub account connected" : "Sign in securely with GitHub")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            if model.isGitHubConnected {
                                Button("Disconnect") { model.logoutGitHub() }.buttonStyle(SecondaryButtonStyle())
                            } else {
                                Button("Sign in with GitHub") { model.loginGitHub() }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        Text("A browser window opens for GitHub authorization. Your access session is stored in macOS Keychain; you never paste or handle a token.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Repository setup", systemImage: "shippingbox").font(.system(size: 13, weight: .semibold))
                        labeledField("Repository name", text: $model.repoName)
                        labeledField("Folder inside repository", text: $model.folderName)
                        Toggle("Private repository", isOn: $model.isPrivate).toggleStyle(.switch)
                        HStack {
                            Text("Files selected").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(model.selectedMedia.count)  •  \(ByteCountFormatter.string(fromByteCount: model.selectedSize, countStyle: .file))").fontWeight(.semibold)
                        }.font(.system(size: 11))
                        Button { model.createRepositoryAndUpload() } label: {
                            Label(model.isUploading ? "Uploading…" : "Create repository & upload", systemImage: "arrow.up.circle.fill")
                        }.buttonStyle(PrimaryButtonStyle()).disabled(model.isUploading || model.selectedMedia.isEmpty)
                        if model.isUploading { ProgressView(value: model.uploadProgress).tint(.cyan) }
                        Text(model.githubStatus).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(8)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Large video note", systemImage: "info.circle").font(.system(size: 12, weight: .semibold))
                        Text("Large files require Git LFS. Install it with `brew install git-lfs`. GitHub Free/Pro currently limit each LFS file to 2 GB, and each Git push to 2 GB. A 15 GB upload must be split into batches and may require paid LFS storage/bandwidth. Transfer speed depends on your internet upload speed.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(8)
                }
            }.padding(24).frame(maxWidth: 650, alignment: .leading)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var statusBar: some View {
        HStack {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text(model.status).lineLimit(1)
            Spacer()
            Text("LOCAL FILES • NO CLOUD SYNC").tracking(0.8)
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 10)
            .background(.black.opacity(0.25))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(Color.cyan.opacity(configuration.isPressed ? 0.55 : 0.85), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white.opacity(0.8)).padding(8).background(.white.opacity(0.07), in: Circle())
    }
}
