import Foundation
import ArgumentParser

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the Swift build-script with the known-good configuration."
    )
    
    @Option(name: .shortAndLong, help: "Path to the swift-project root.")
    var projectPath: String = "~/repos/swift-project"

    func run() async throws {
        let expandedPath = NSString(string: projectPath).expandingTildeInPath
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            print("❌ Project path not found: \(expandedPath)")
            throw ExitCode.failure
        }
        
        guard fileManager.changeCurrentDirectoryPath(expandedPath) else {
            print("❌ Failed to change directory to: \(expandedPath)")
            throw ExitCode.failure
        }
        
        print("🚀 Starting Swift build in \(expandedPath)...")
        
        let buildCommand = """
        ./swift/utils/build-script \\
          --build-subdir arm64-testing \\
          --release-debuginfo \\
          --swift-disable-dead-stripping \\
          --bootstrapping=hosttools \\
          --host-target macosx-arm64 \\
          --swift-darwin-supported-archs arm64 \\
          --stdlib-deployment-targets macosx-arm64 \\
          --build-stdlib-deployment-targets macosx-arm64 \\
          --llbuild \\
          --swiftpm \\
          --swift-driver \\
          --swiftsyntax \\
          --swift-testing \\
          --swift-testing-macros \\
          --install-swift \\
          --install-llvm \\
          --install-llbuild \\
          --install-swiftsyntax \\
          --install-swift-testing \\
          --install-swift-testing-macros \\
          --skip-ios \\
          --skip-tvos \\
          --skip-watchos \\
          --skip-xros \\
          --skip-test-cmark \\
          --skip-test-swift \\
          --skip-test-llbuild \\
          --skip-test-swiftpm \\
          --skip-test-xctest \\
          --skip-test-foundation \\
          --skip-test-libdispatch \\
          --sccache
        """
        
        let status = await runShellCommand(buildCommand)
        if status != 0 {
            print("❌ Build failed with exit code \(status)")
            throw ExitCode.failure
        }
        
        print("✅ Build completed successfully!")
    }
}
