import Foundation

class LaunchAgentManager {
    private let plistLabel = "com.jaypark.chat2md"
    private var plistURL: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent("Library/LaunchAgents/\(plistLabel).plist")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func install() throws {
        let appPath = Bundle.main.bundlePath

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(plistLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(appPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """

        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path]
        try process.run()
        process.waitUntilExit()
    }

    func uninstall() throws {
        guard isInstalled else { return }

        // Unload the agent first
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]
        try process.run()
        process.waitUntilExit()

        // Remove the plist file
        try FileManager.default.removeItem(at: plistURL)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if !isInstalled {
                try install()
            }
        } else {
            if isInstalled {
                try uninstall()
            }
        }
    }
}
