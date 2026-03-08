import Foundation
import ArgumentParser
import Subprocess

struct Test: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run package tests using the local Swift toolchain."
    )
    
    @Option(name: .shortAndLong, help: "Path to the swift-project root.")
    var projectPath: String = "~/repos/swift-project"
    
    @Argument(parsing: .captureForPassthrough, help: "Arguments to pass to `swift test`.")
    var testArguments: [String] = []

    func run() async throws {
        let expandedPath = NSString(string: projectPath).expandingTildeInPath
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            print("❌ Project path not found: \(expandedPath)")
            throw ExitCode.failure
        }
        
        // Construct the path to the built swiftc
        let swiftcPath = expandedPath + "/build/arm64-testing/toolchain-macosx-arm64/usr/bin/swiftc"
        
        guard fileManager.fileExists(atPath: swiftcPath) else {
            print("❌ Local swiftc not found at: \(swiftcPath)")
            print("   Please run `swiftbuild build` first.")
            throw ExitCode.failure
        }
        
        print("🧪 Running tests with local toolchain...")
        print("   Compiler: \(swiftcPath)")
        
        let environment = ProcessInfo.processInfo.environment
        // Convert to [Environment.Key: String?]
        var envUpdates: [Environment.Key: String?] = [:]
        for (key, value) in environment {
            if let envKey = Environment.Key(rawValue: key) {
                envUpdates[envKey] = value
            }
        }
        if let swiftExecKey = Environment.Key(rawValue: "SWIFT_EXEC") {
            envUpdates[swiftExecKey] = swiftcPath
        }
        
        do {
            let result = try await Subprocess.run(
                .path("/usr/bin/swift"),
                arguments: Arguments(["test"] + testArguments),
                environment: .inherit.updating(envUpdates),
                output: .standardOutput,
                error: .standardError
            )
            
            if case .exited(let code) = result.terminationStatus, code != 0 {
                 throw ExitCode.failure
            } else if case .unhandledException = result.terminationStatus {
                 throw ExitCode.failure
            }
        } catch {
             throw ExitCode.failure
        }
    }
}
