import Foundation
import ArgumentParser

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check the local environment for swift toolchain development."
    )

    @Flag(name: .customLong("fix"), help: "Attempt to fix identified issues automatically.")
    var shouldFix: Bool = false

    func run() async throws {
        print("Running diagnostics...")
        
        await checkMachine()
        await checkRosetta()
        await checkXcodeCLITools()
        await checkPathOrder()
        await checkBrew()
        
        print("\n== Required Tools ==")
        await checkTool("cmake")
        await checkTool("ninja")
        await checkTool("sccache")
        await checkTool("python3", brewFormula: "python")
        
        await checkDeveloperTools()
        await checkSDK()

        if shouldFix {
            print("\n🚀 Starting repair process...")
            await fixPath()
            await installDependencies()
            await installXcodeCLI()
            print("\n🎉 Repair complete. Please restart your terminal session for changes to take effect.")
            print("Run: exec /bin/zsh -l")
        }
    }
    
    // MARK: - Fixes

    func fixPath() async {
        print("\n== PATH Fix ==")
        
        let zshrcPath = NSHomeDirectory() + "/.zshrc"
        let requiredLines = [
            "typeset -U path",
            "path=(/opt/homebrew/bin /opt/homebrew/sbin $path)",
            "export PATH"
        ]
        
        var zshrcContent = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""
        var changesMade = false
        
        for line in requiredLines {
            if !zshrcContent.contains(line) {
                print("➕ Adding '\(line)' to .zshrc")
                zshrcContent += "\n\(line)"
                changesMade = true
            }
        }
        
        if changesMade {
            // Backup
            do {
                if FileManager.default.fileExists(atPath: zshrcPath) {
                    try FileManager.default.copyItem(atPath: zshrcPath, toPath: zshrcPath + ".bak")
                }
                try zshrcContent.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
                print("✅ Updated .zshrc")
            } catch {
                print("❌ Failed to write .zshrc: \(error)")
            }
        } else {
            print("✅ .zshrc already contains necessary PATH configuration")
        }
    }
    
    func installDependencies() async {
        print("\n== Dependencies ==")
        let tools = ["cmake", "ninja", "sccache", "python3"]
        
        for tool in tools {
            let formula = (tool == "python3") ? "python" : tool
            
            // Check if installed
            let whichResult = await runCommand("which \(tool)")
            if whichResult.exitCode != 0 {
                print("⚠️ Installing \(tool)...")
                let status = await runShellCommand("brew install \(formula)")
                if status == 0 {
                    print("✅ Installed \(tool)")
                } else {
                    print("❌ Failed to install \(tool)")
                }
                continue
            }
            
            // Check architecture
            if let path = whichResult.output {
                let fileInfo = (await runCommand("file \"\(path)\"")).output ?? ""
                if fileInfo.contains("x86_64") && !fileInfo.contains("arm64") && !fileInfo.contains("arm64e") {
                     print("⚠️ Reinstalling \(tool) (architecture mismatch)...")
                     let status = await runShellCommand("brew reinstall \(formula)")
                     if status == 0 {
                         print("✅ Reinstalled \(tool)")
                     } else {
                         print("❌ Failed to reinstall \(tool)")
                     }
                } else {
                    print("✅ \(tool) is valid")
                }
            }
        }
    }
    
    func installXcodeCLI() async {
        print("\n== Xcode CLI Tools ==")
        if (await runCommand("/usr/bin/xcode-select -p")).exitCode != 0 {
            print("⚠️ Installing Xcode CLI tools...")
            let status = await runShellCommand("xcode-select --install")
             if status == 0 {
                 print("✅ Triggered Xcode CLI install")
             } else {
                 print("❌ Failed to trigger install (might require manual intervention)")
             }
        } else {
            print("✅ Xcode CLI tools installed")
        }
    }

    // MARK: - Checks
    
    func checkMachine() async {
        print("\n== Machine ==")
        let arch = (await runCommand("uname -m")).output ?? "unknown"
        let os = (await runCommand("uname -s")).output ?? "unknown"
        
        print("uname -s: \(os)")
        print("uname -m: \(arch)")
        
        if arch == "arm64" {
            print("✅ Machine architecture is arm64")
        } else {
            print("❌ Machine architecture is not arm64")
        }
    }
    
    func checkRosetta() async {
        print("\n== Rosetta ==")
        let translated = (await runCommand("sysctl -n sysctl.proc_translated")).output ?? "0"
        if translated == "1" {
            print("❌ Current shell is running under Rosetta")
        } else {
            print("✅ Current shell is not running under Rosetta")
        }
    }
    
    func checkXcodeCLITools() async {
        print("\n== Xcode CLI Tools ==")
        if (await runCommand("/usr/bin/xcode-select -p")).exitCode == 0 {
            print("✅ Xcode command line tools are installed")
        } else {
            print("❌ Xcode command line tools are not installed")
        }
    }
    
    func checkPathOrder() async {
        print("\n== PATH ==")
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        print("PATH (current) = \(currentPath)")
        
        // Check fresh login shell path
        // Use a temporary file to capture output to avoid pipe hangs with background processes
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swiftbuild_login_path.txt")
        // Trying to source .zshrc directly instead of -i to avoid interactive shell hangs
        let command = "/bin/zsh -c 'source ~/.zshrc; printf \"%s\" \"$PATH\"' > \"\(tempFile.path)\" 2>/dev/null"
        
        _ = await runShellCommand(command)
        
        let rawLoginPath = (try? String(contentsOf: tempFile, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: tempFile)
        
        // Filter out zsh noise
        let loginPathLines = rawLoginPath.components(separatedBy: .newlines).filter { line in
            !line.isEmpty &&
            !line.hasPrefix("Restored session") &&
            !line.hasPrefix("Saving session") &&
            !line.hasPrefix("...copying shared history") &&
            !line.hasPrefix("...saving history") &&
            !line.hasPrefix("...truncating history files") &&
            !line.hasPrefix("...completed")
        }
        
        let loginPath = loginPathLines.joined(separator: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("PATH (login)   = \(loginPath)")
        
        let pathEntries = loginPath.split(separator: ":").map { String($0) }
        
        let firstOpt = pathEntries.firstIndex(of: "/opt/homebrew/bin")
        let firstUsrLocal = pathEntries.firstIndex(of: "/usr/local/bin")
        
        if let firstOpt = firstOpt {
            print("✅ /opt/homebrew/bin is in fresh login PATH")
            
            if let firstUsrLocal = firstUsrLocal {
                if firstOpt < firstUsrLocal {
                    print("✅ /opt/homebrew/bin comes before /usr/local/bin")
                } else {
                    print("❌ /opt/homebrew/bin comes after /usr/local/bin")
                }
            } else {
                 print("✅ /usr/local/bin is not in fresh login PATH")
            }
            
            if firstOpt == 0 {
                print("✅ /opt/homebrew/bin is the first entry")
            } else {
                print("❌ /opt/homebrew/bin is not the first entry")
            }
            
        } else {
            print("❌ /opt/homebrew/bin is missing from fresh login PATH")
        }
        
        if currentPath == loginPath {
            print("✅ Current shell PATH matches fresh login PATH")
        } else {
            print("⚠️ Current shell PATH differs from fresh login PATH")
        }
    }
    
    func checkBrew() async {
        print("\n== Homebrew ==")
        
        let whichBrew = (await runCommand("which brew")).output ?? ""
        let armBrewPath = "/opt/homebrew/bin/brew"
        
        if FileManager.default.fileExists(atPath: armBrewPath) {
            print("✅ \(armBrewPath) exists")
        } else {
            print("❌ \(armBrewPath) does not exist")
        }
        
        if whichBrew == armBrewPath {
            print("✅ Current shell resolves brew to \(armBrewPath)")
        } else {
            print("⚠️ Current shell resolves brew to '\(whichBrew)'")
        }
        
        let brewPrefix = (await runCommand("brew --prefix")).output ?? ""
        if brewPrefix == "/opt/homebrew" {
            print("✅ brew prefix is /opt/homebrew")
        } else {
            print("⚠️ brew prefix is '\(brewPrefix)'")
        }
    }
    
    func checkTool(_ tool: String, brewFormula: String? = nil) async {
        if let path = (await runCommand("which \(tool)")).output {
            let fileInfo = (await runCommand("file \"\(path)\"")).output ?? ""
            
            print("\(tool)")
            print("  path: \(path)")
            print("  file: \(fileInfo)")
            
            if fileInfo.contains("x86_64") && !fileInfo.contains("arm64") && !fileInfo.contains("arm64e") {
                 print("❌ \(tool) is x86_64-only")
            } else if fileInfo.contains("arm64") || fileInfo.contains("arm64e") {
                 print("✅ \(tool) supports arm64")
            } else {
                 print("⚠️ \(tool) does not report arm64 support (script or unknown)")
            }
        } else {
            print("❌ \(tool) missing")
        }
    }
    
    func checkDeveloperTools() async {
        print("\n== Developer Tools ==")
        
        // Check xcrun directly
        if let path = (await runCommand("which xcrun")).output {
             let fileInfo = (await runCommand("file \"\(path)\"")).output ?? ""
             print("xcrun")
             print("  path: \(path)")
             if fileInfo.contains("arm64") || fileInfo.contains("arm64e") {
                 print("✅ xcrun supports arm64")
             } else {
                 print("❌ xcrun does not support arm64")
             }
        } else {
            print("❌ xcrun not found")
        }
        
        let tools = ["clang", "clang++", "swiftc"]
        
        for tool in tools {
            if let path = (await runCommand("/usr/bin/xcrun -f \(tool)")).output {
                let fileInfo = (await runCommand("file \"\(path)\"")).output ?? ""
                 print("\(tool) (via xcrun)")
                 print("  path: \(path)")
                 
                 if fileInfo.contains("arm64") || fileInfo.contains("arm64e") {
                     print("✅ \(tool) supports arm64")
                 } else {
                     print("❌ \(tool) does not support arm64")
                 }
            } else {
                print("❌ \(tool) not resolvable via xcrun")
            }
        }
    }
    
    func checkSDK() async {
        print("\n== SDK ==")
        if let sdkPath = (await runCommand("/usr/bin/xcrun --sdk macosx --show-sdk-path")).output {
            print("✅ macOS SDK: \(sdkPath)")
        } else {
            print("❌ Could not resolve macOS SDK path")
        }
    }
}
