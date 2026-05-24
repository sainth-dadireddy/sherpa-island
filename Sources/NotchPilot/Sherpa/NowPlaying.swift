import Foundation
import Combine
import AppKit
import Darwin

@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published var trackTitle: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage?
    @Published var isPlaying: Bool = false

    private var debounceTask: Task<Void, Never>?
    private var notificationToken: NSObjectProtocol?
    private let mediaRemoteQueue = DispatchQueue(label: "com.sherpa.nowplaying.mediaremote")

    private var mrGetNowPlayingInfo: (@escaping ([String: Any]?) -> Void) -> Void = { _ in }
    private var mrRegisterForNotifications: (() -> Void)? = nil

    init() {
        setupMediaRemote()
        registerForNotifications()
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupMediaRemote() {
        guard let mediaRemoteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            fallbackToAppleScript()
            return
        }

        let getInfoSymbol = dlsym(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingInfo")
        let registerSymbol = dlsym(mediaRemoteHandle, "MRMediaRemoteRegisterForNowPlayingNotifications")

        guard let getInfoAddr = getInfoSymbol, let registerAddr = registerSymbol else {
            dlclose(mediaRemoteHandle)
            fallbackToAppleScript()
            return
        }

        typealias GetNowPlayingInfoType = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
        typealias RegisterNotificationType = @convention(c) (DispatchQueue) -> Void

        let getInfoFn = unsafeBitCast(getInfoAddr, to: GetNowPlayingInfoType.self)
        let registerFn = unsafeBitCast(registerAddr, to: RegisterNotificationType.self)

        self.mrGetNowPlayingInfo = { callback in
            getInfoFn(self.mediaRemoteQueue, callback)
        }

        self.mrRegisterForNotifications = {
            registerFn(self.mediaRemoteQueue)
        }

        queryNowPlayingInfo()
        registerFn(mediaRemoteQueue)
    }

    private func registerForNotifications() {
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debounceNowPlayingUpdate()
        }
    }

    private func debounceNowPlayingUpdate() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                await queryNowPlayingInfoOnMain()
            }
        }
    }

    private func queryNowPlayingInfo() {
        mediaRemoteQueue.async { [weak self] in
            self?.mrGetNowPlayingInfo { info in
                Task { @MainActor in
                    self?.updateFromMediaRemoteInfo(info)
                }
            }
        }
    }

    @MainActor
    private func queryNowPlayingInfoOnMain() {
        queryNowPlayingInfo()
    }

    @MainActor
    private func updateFromMediaRemoteInfo(_ info: [String: Any]?) {
        guard let info = info else {
            fallbackToAppleScript()
            return
        }

        if let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String {
            trackTitle = title
        }

        if let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String {
            artistName = artist
        }

        if let playbackState = info["kMRMediaRemoteNowPlayingInfoPlaybackState"] as? NSNumber {
            isPlaying = playbackState.intValue == 2
        }

        if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            albumArt = NSImage(data: artworkData)
        } else if let artworkDict = info["kMRMediaRemoteNowPlayingInfoArtwork"] as? [String: Any],
                  let artData = artworkDict["_imageData"] as? Data {
            albumArt = NSImage(data: artData)
        }
    }

    private func fallbackToAppleScript() {
        DispatchQueue.global().async { [weak self] in
            let script = """
            tell application "Spotify"
                if it is running then
                    try
                        set trackName to name of current track
                        set artistName to artist of current track
                        return trackName & " | " & artistName
                    on error
                        return ""
                    end try
                end if
            end tell
            """

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !result.isEmpty {
                    let components = result.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    Task { @MainActor in
                        if components.count >= 1 {
                            self?.trackTitle = components[0]
                        }
                        if components.count >= 2 {
                            self?.artistName = components[1]
                        }
                        self?.isPlaying = true
                    }
                }
            } catch {
                Task { @MainActor in
                    self?.trackTitle = ""
                    self?.artistName = ""
                    self?.isPlaying = false
                }
            }
        }
    }
}
