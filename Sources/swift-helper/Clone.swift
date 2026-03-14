import Foundation
import ArgumentParser

struct Clone: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clone the Swift project and dependencies."
    )

    @Option(name: .shortAndLong, help: "Path to where the project should be cloned.")
    var projectPath: String?

    func run() async throws {
        let fileManager = FileManager.default
        let expandedPath: String
        
        if let userPath = projectPath {
             expandedPath = NSString(string: userPath).expandingTildeInPath
        } else {
             // Default: Clone into current working directory
             expandedPath = fileManager.currentDirectoryPath + "/swift-project"
        }
        
        if fileManager.fileExists(atPath: expandedPath) {
            print("❌ Directory already exists at \(expandedPath). Aborting.")
            throw ExitCode.failure
        }

        print("🚀 Cloning Swift Project to \(expandedPath)...")
        
        // Save path for future use
        let configPath = NSTemporaryDirectory() + "/.swift-helper_project_path"
        do {
            try expandedPath.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
             print("⚠️ Failed to save project path to config: \(error)")
        }

        // 1. Create Directory
        do {
            try fileManager.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
        } catch {
             print("❌ Failed to create directory: \(error)")
             throw ExitCode.failure
        }

        // 2. Clone Swift
        print("📦 Cloning swiftlang/swift...")
        let gitClone = await runShellCommand("git clone https://github.com/swiftlang/swift.git \"\(expandedPath)/swift\"")
        if gitClone != 0 {
             print("❌ Failed to clone swift repository.")
             throw ExitCode.failure
        }

        // 3. Update Checkout
        print("📦 Cloning dependencies (this may take a while)...")
        // We need to verify where update-checkout is. It's in swift/utils/update-checkout.
        // And it requires python3.
        let updateCheckoutCmd = "cd \"\(expandedPath)/swift\" && ./utils/update-checkout --clone"
        
        // This command prints a lot of output, we should probably let it stream to stdout. 
        // runShellCommand does stream to stdout (it uses .standardOutput).
        let updateStatus = await runShellCommand(updateCheckoutCmd)
        
        if updateStatus != 0 {
            print("❌ Failed to clone dependencies.")
            print("You may need to run './utils/update-checkout --clone' manually in \(expandedPath)/swift")
            throw ExitCode.failure
        }

        print("\n✅ Successfully cloned Swift project!")
        print("👉 You can now run 'swift-helper build' to build the toolchain.")
    }
}
