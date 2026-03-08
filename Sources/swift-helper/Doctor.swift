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
        
        var allPassed = true
        
        allPassed = await checkMachine() && allPassed
        allPassed = await checkRosetta() && allPassed
        allPassed = await checkXcodeCLITools() && allPassed
        allPassed = await checkPathOrder() && allPassed
        allPassed = await checkBrew() && allPassed
        
        print("\n== Required Tools ==")
        allPassed = await checkTool("cmake") && allPassed
        allPassed = await checkTool("ninja") && allPassed
        allPassed = await checkTool("sccache") && allPassed
        allPassed = await checkTool("python3", brewFormula: "python") && allPassed
        
        allPassed = await checkDeveloperTools() && allPassed
        allPassed = await checkSDK() && allPassed

        if shouldFix {
            await runFixes()
        } else if !allPassed {
            print("\n⚠️  Issues were found that can be automatically fixed.")
            print("Would you like to run the repair process now? [y/N]: ", terminator: "")
            if let input = readLine(), input.lowercased() == "y" {
                await runFixes()
            }
        }
    }
    
    func runFixes() async {
        print("\n🚀 Starting repair process...")
        await fixPath()
        await installDependencies()
        await installXcodeCLI()
        print("\n🎉 Repair complete. Please restart your terminal session for changes to take effect.")
        print("Run: exec /bin/zsh -l")
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
            let result = await Diagnostics.checkTool(tool)
            if !result.ok {
                let formula = (tool == "python3") ? "python" : tool
                
                // If missing or wrong arch
                if result.message.contains("missing") {
                    print("⚠️ Installing \(tool)...")
                    let status = await runShellCommand("brew install \(formula)")
                    if status == 0 {
                        print("✅ Installed \(tool)")
                    } else {
                        print("❌ Failed to install \(tool)")
                    }
                } else {
                    // Wrong architecture
                    print("⚠️ Reinstalling \(tool) (architecture mismatch)...")
                    let status = await runShellCommand("brew reinstall \(formula)")
                    if status == 0 {
                        print("✅ Reinstalled \(tool)")
                    } else {
                        print("❌ Failed to reinstall \(tool)")
                    }
                }
            } else {
                print("✅ \(tool) is valid")
            }
        }
    }
    
    func installXcodeCLI() async {
        print("\n== Xcode CLI Tools ==")
        let result = await Diagnostics.checkXcodeCLITools()
        if !result.ok {
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
    
    func checkMachine() async -> Bool {
        print("\n== Machine ==")
        // Still printing uname info for user context
        let os = (await runCommand("uname -s")).output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let arch = (await runCommand("uname -m")).output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        
        print("uname -s: \(os)")
        print("uname -m: \(arch)")
        
        let result = await Diagnostics.checkArchitecture()
        printResult(result)
        return result.ok
    }
    
    func checkRosetta() async -> Bool {
        print("\n== Rosetta ==")
        let result = await Diagnostics.checkRosetta()
        printResult(result)
        return result.ok
    }
    
    func checkXcodeCLITools() async -> Bool {
        print("\n== Xcode CLI Tools ==")
        let result = await Diagnostics.checkXcodeCLITools()
        printResult(result)
        return result.ok
    }
    
    func checkBrew() async -> Bool {
        print("\n== Homebrew ==")
        
        var success = true
        let whichBrew = (await runCommand("which brew")).output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let armBrewPath = "/opt/homebrew/bin/brew"
        
        if FileManager.default.fileExists(atPath: armBrewPath) {
            print("✅ \(armBrewPath) exists")
        } else {
            print("❌ \(armBrewPath) does not exist")
            success = false
        }
        
        if whichBrew == armBrewPath {
            print("✅ Current shell resolves brew to \(armBrewPath)")
        } else {
            print("⚠️ Current shell resolves brew to '\(whichBrew)'")
            success = false
        }
        
        let brewPrefix = (await runCommand("brew --prefix")).output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if brewPrefix == "/opt/homebrew" {
            print("✅ brew prefix is /opt/homebrew")
        } else {
            print("⚠️ brew prefix is '\(brewPrefix)'")
            success = false
        }
        
        return success
    }
    
    func checkTool(_ tool: String, brewFormula: String? = nil) async -> Bool {
        // Detailed print for Doctor, using Diagnostics result logic
        if let path = (await runCommand("which \(tool)")).output?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let fileInfo = (await runCommand("file \"\(path)\"")).output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            print("\(tool)")
            print("  path: \(path)")
            print("  file: \(fileInfo)")
        }
        
        let result = await Diagnostics.checkTool(tool)
        // Doctor prints specific messages
        if result.ok {
             print("✅ \(tool) supports arm64")
        } else {
             print("❌ \(result.message)")
        }
        return result.ok
    }
    
    func checkDeveloperTools() async -> Bool {
        print("\n== Developer Tools ==")
        let results = await Diagnostics.checkDeveloperTools()
        var allOk = true
        for result in results {
            printResult(result)
            if !result.ok { allOk = false }
        }
        return allOk
    }
    
    func checkSDK() async -> Bool {
        print("\n== SDK ==")
        let result = await Diagnostics.checkSDK()
        printResult(result)
        return result.ok
    }
    
    func checkPathOrder() async -> Bool {
        // Keep the complex PATH logic here in Doctor as it's specific to "Doctor" diagnosis
        print("\n== PATH ==")
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        print("PATH (current) = \(currentPath)")
        
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swift-helper_login_path.txt")
        let command = "/bin/zsh -c 'source ~/.zshrc; printf \"%s\" \"$PATH\"' > \"\(tempFile.path)\" 2>/dev/null"
        
        _ = await runShellCommand(command)
        
        let rawLoginPath = (try? String(contentsOf: tempFile, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: tempFile)
        
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
        
        var success = true
        
        if let firstOpt = firstOpt {
            print("✅ /opt/homebrew/bin is in fresh login PATH")
            if let firstUsrLocal = firstUsrLocal {
                if firstOpt < firstUsrLocal {
                    print("✅ /opt/homebrew/bin comes before /usr/local/bin")
                } else {
                    print("❌ /opt/homebrew/bin comes after /usr/local/bin")
                    success = false
                }
            } else {
                 print("✅ /usr/local/bin is not in fresh login PATH")
            }
            if firstOpt == 0 {
                print("✅ /opt/homebrew/bin is the first entry")
            } else {
                print("❌ /opt/homebrew/bin is not the first entry")
                success = false
            }
        } else {
            print("❌ /opt/homebrew/bin is missing from fresh login PATH")
            success = false
        }
        
        if currentPath == loginPath {
            print("✅ Current shell PATH matches fresh login PATH")
        } else {
            print("⚠️ Current shell PATH differs from fresh login PATH")
            // This is a warning, maybe not a hard failure? 
            // The prompt says "failures or warnings". So let's count it as failure to trigger the prompt.
            success = false
        }
        
        return success
    }

    private func printResult(_ result: Diagnostics.CheckResult) {
        if result.ok {
            print("✅ \(result.message)")
        } else {
            print("❌ \(result.message)")
        }
    }
}
