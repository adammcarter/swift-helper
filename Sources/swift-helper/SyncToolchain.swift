import Foundation
import ArgumentParser

struct SyncToolchain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync-toolchain",
        abstract: "Sync the built toolchain to ~/Library/Developer/Toolchains/swift-local.xctoolchain."
    )
    
    @Option(name: .shortAndLong, help: "Path to the swift-project root.")
    var projectPath: String = "~/repos/swift-project"

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    @Flag(name: .long, help: "Print the sync command without executing it.")
    var dryRun: Bool = false

    func run() async throws {
        let toolchainDest = NSString(string: "~/Library/Developer/Toolchains/swift-local.xctoolchain").expandingTildeInPath
        
        // Source path depends on build settings. We hardcode arm64-testing for now based on Build.swift
        let projectDir = NSString(string: projectPath).expandingTildeInPath
        let sourcePath = "\(projectDir)/build/arm64-testing/toolchain-macosx-arm64/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/"
        
        let rsyncCommand = "rsync -a --delete --exclude 'Info.plist' \"\(sourcePath)\" \"\(toolchainDest)/\""
        
        print("\n🚀 Syncing toolchain to \(toolchainDest)...")
        print("Executing:")
        print("--------------------------------------------------")
        print(rsyncCommand)
        print("--------------------------------------------------\n")
        
        if dryRun {
            print("(Dry Run - skipping execution)")
            return
        }
        
        if !yes {
            print("Press Enter to execute this command (or Ctrl+C to cancel)...", terminator: "")
            _ = readLine()
        }
        
        // Ensure destination directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: toolchainDest) {
            do {
                try fileManager.createDirectory(atPath: toolchainDest, withIntermediateDirectories: true)
            } catch {
                print("❌ Failed to create destination directory: \(error)")
                return
            }
        }

        // Get Git Info
        var extraInfo = ""
        // Check swift repo specifically since project root is likely a monorepo workspace
        let swiftRepoPath = "\(projectDir)/swift"
        
        // Only attempt if directory exists
        var isGitRepo = false
        let checkGit = await runCommand("test -d \(swiftRepoPath)/.git")
        if checkGit.exitCode == 0 {
             isGitRepo = true
        }

        if isGitRepo {
            let gitSha = await runCommand("cd \(swiftRepoPath) && git rev-parse --short HEAD")
            let gitBranch = await runCommand("cd \(swiftRepoPath) && git rev-parse --abbrev-ref HEAD")
            
            if let sha = gitSha.output {
               extraInfo += " (\(sha)"
               if let branch = gitBranch.output {
                   extraInfo += "/\(branch)"
               }
               extraInfo += ")"
            }
        } else {
            print("⚠️  Warning: Could not find .git directory in \(swiftRepoPath). Skipping metadata.")
        }
        
        // Ensure Info.plist exists or update it
        let infoPlistPath = "\(toolchainDest)/Info.plist"
        // Always overwrite Info.plist to update metadata
        print("ℹ️  Updating Info.plist with metadata...")
        let infoPlistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
           <key>CFBundleIdentifier</key>
           <string>org.swift.swift-local</string>
           <key>DisplayName</key>
           <string>Swift Local\(extraInfo)</string>
           <key>CompatibilityVersion</key>
           <integer>2</integer>
        </dict>
        </plist>
        """
        do {
            try infoPlistContent.write(toFile: infoPlistPath, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to create Info.plist: \(error)")
        }
        
        let status = await runShellCommand(rsyncCommand)
        if status == 0 {
            print("✅ Toolchain synced successfully!")
            print("👉 You can select 'swift-local' in Xcode > Settings > Components > Toolchains")
        } else {
            print("❌ Sync failed with exit code \(status)")
        }
    }
}
