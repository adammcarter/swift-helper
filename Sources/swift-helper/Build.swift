import Foundation
import ArgumentParser

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the Swift build-script with a configurable workflow."
    )
    
    @Option(name: .shortAndLong, help: "Path to the swift-project root.")
    var projectPath: String = "~/repos/swift-project"

    @Flag(name: .long, help: "Skip interactive mode and use defaults.")
    var defaultBuild: Bool = false

    @Flag(name: .long, help: "Print the build command without executing it.")
    var dryRun: Bool = false
    
    @Flag(name: .long, help: "Rerun the last executed build command.")
    var rerun: Bool = false

    func run() async throws {
        let expandedPath = NSString(string: projectPath).expandingTildeInPath
        let fileManager = FileManager.default
        let lastCommandPath = NSHomeDirectory() + "/.swift-helper_last_command"
        
        // Preflight Checks
        if !dryRun {
            if await !performPreflightChecks() {
                print("\n❌ Preflight checks failed. Please run 'swift-helper doctor --fix' to resolve issues.")
                throw ExitCode.failure
            }
        }
        
        guard fileManager.fileExists(atPath: expandedPath) else {
            print("❌ Project path not found: \(expandedPath)")
            throw ExitCode.failure
        }
        
        guard fileManager.changeCurrentDirectoryPath(expandedPath) else {
            print("❌ Failed to change directory to: \(expandedPath)")
            throw ExitCode.failure
        }
        
        // Handle Rerun
        if rerun {
            do {
                let lastCommand = try String(contentsOfFile: lastCommandPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                if lastCommand.isEmpty {
                    print("❌ No previous build command found.")
                    throw ExitCode.failure
                }
                print("🔄 Rerunning last command in \(expandedPath)...")
                
                if dryRun {
                    print("\nExecuting (Dry Run):\n\(lastCommand)\n")
                    return
                }
                
                let status = await runShellCommand(lastCommand)
                if status != 0 {
                    print("\n❌ Build failed with exit code \(status)")
                    throw ExitCode.failure
                }
                print("\n✅ Build completed successfully!")
                return
            } catch {
                print("❌ Failed to read last command: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
        
        print("\n🔨 Swift Build Configuration Wizard")
        print("-----------------------------------")
        
        var options = BuildOptions()
        
        if !defaultBuild {
            options = await promptForOptions()
        } else {
            print("ℹ️  Using default minimal configuration.")
        }
        
        print("\n🚀 Starting build in \(expandedPath)...")
        print("Configuration:")
        print("  - Build Type: \(options.buildType.rawValue)")
        print("  - Platforms: \(options.platforms.map { $0.rawValue }.joined(separator: ", "))")
        print("  - Components: \(options.components.map { $0.rawValue }.joined(separator: ", "))")
        print("  - Tests: \(options.skipTests ? "Skipped" : "Enabled")")
        print("-----------------------------------\n")
        
        let buildCommand = constructBuildCommand(options)
        
        // Save command for rerun
        try? buildCommand.write(toFile: lastCommandPath, atomically: true, encoding: .utf8)
        
        if dryRun {
             print("Executing (Dry Run):\n\(buildCommand)\n")
             return
        }
        
        let status = await runShellCommand(buildCommand)
        if status != 0 {
            print("\n❌ Build failed with exit code \(status)")
            throw ExitCode.failure
        }
        
        print("\n✅ Build completed successfully!")
    }
    
    // MARK: - Interactive Prompts
    
    func promptForOptions() async -> BuildOptions {
        var options = BuildOptions()
        
        // 1. Build Type
        print("\n1. Select Build Type:")
        print("   1) Release with Debug Info (Recommended for Dev) [Default]")
        print("   2) Release (Fastest Runtime)")
        print("   3) Debug (Fastest Build)")
        if let input = readLine(), let choice = Int(input) {
            switch choice {
            case 2: options.buildType = .release
            case 3: options.buildType = .debug
            default: options.buildType = .releaseDebugInfo
            }
        }
        
        // 2. Platforms
        print("\n2. Select Target Platforms:")
        print("   1) macOS (arm64) only [Default]")
        print("   2) macOS + iOS")
        print("   3) macOS + iOS + tvOS + watchOS + visionOS")
        if let input = readLine(), let choice = Int(input) {
            switch choice {
            case 2:
                options.platforms = [.macOS, .iOS]
            case 3:
                options.platforms = [.macOS, .iOS, .tvOS, .watchOS, .visionOS]
            default:
                options.platforms = [.macOS]
            }
        }
        
        // 3. Components
        print("\n3. Select Components to Build:")
        print("   1) Minimal (Stdlib + SwiftPM + Driver + Testing) [Default]")
        print("   2) Compiler Only (Stdlib + Driver)")
        print("   3) Full Toolchain (Everything)")
        if let input = readLine(), let choice = Int(input) {
            switch choice {
            case 2:
                options.components = [.stdlib, .swiftDriver]
            case 3:
                options.components = Set(BuildComponent.allCases)
            default:
                options.components = [.stdlib, .swiftPM, .swiftDriver, .swiftSyntax, .swiftTesting, .swiftTestingMacros, .llbuild]
            }
        }
        
        // 4. Testing
        print("\n4. Run Tests?")
        print("   1) Skip All Tests (Fastest) [Default]")
        print("   2) Run Tests")
        if let input = readLine(), let choice = Int(input) {
            options.skipTests = (choice != 2)
        } else {
            options.skipTests = true
        }
        
        return options
    }
    
    // MARK: - Command Construction
    
    func constructBuildCommand(_ options: BuildOptions) -> String {
        var args: [String] = ["./swift/utils/build-script"]
        
        // Basic Flags
        args.append("--build-subdir arm64-testing") // Keeping consistent subdir
        args.append("--bootstrapping=hosttools")
        args.append("--sccache") // Always enable caching if available
        
        // Build Type
        switch options.buildType {
        case .debug:
            args.append("--debug")
        case .release:
            args.append("--release")
        case .releaseDebugInfo:
            args.append("--release-debuginfo")
            args.append("--swift-disable-dead-stripping")
        }
        
        // Platforms (Host is assumed macOS arm64 for now based on user context)
        args.append("--host-target macosx-arm64")
        args.append("--swift-darwin-supported-archs arm64")
        
        if options.platforms.contains(.macOS) {
            args.append("--stdlib-deployment-targets macosx-arm64")
            args.append("--build-stdlib-deployment-targets macosx-arm64")
        }
        
        // Skip other platforms if not selected
        if !options.platforms.contains(.iOS) { args.append("--skip-ios") }
        if !options.platforms.contains(.tvOS) { args.append("--skip-tvos") }
        if !options.platforms.contains(.watchOS) { args.append("--skip-watchos") }
        if !options.platforms.contains(.visionOS) { args.append("--skip-xros") }
        
        // Components
        if options.components.contains(.llbuild) { args.append("--llbuild"); args.append("--install-llbuild") }
        if options.components.contains(.swiftPM) { args.append("--swiftpm") }
        if options.components.contains(.swiftDriver) { args.append("--swift-driver") }
        if options.components.contains(.swiftSyntax) { args.append("--swiftsyntax"); args.append("--install-swiftsyntax") }
        if options.components.contains(.swiftTesting) { args.append("--swift-testing"); args.append("--install-swift-testing") }
        if options.components.contains(.swiftTestingMacros) { args.append("--swift-testing-macros"); args.append("--install-swift-testing-macros") }
        
        // Always install swift and llvm in this workflow? The original script did.
        args.append("--install-swift")
        args.append("--install-llvm")
        
        // Tests
        if options.skipTests {
            args.append("--skip-test-cmark")
            args.append("--skip-test-swift")
            args.append("--skip-test-llbuild")
            args.append("--skip-test-swiftpm")
            args.append("--skip-test-xctest")
            args.append("--skip-test-foundation")
            args.append("--skip-test-libdispatch")
        }
        
        return args.joined(separator: " \\\n  ")
    }
    
    func performPreflightChecks() async -> Bool {
        // Silent checks unless failure
        
        var passed = true
        var errors: [String] = []
        
        // 1. Architecture
        let archResult = await Diagnostics.checkArchitecture()
        if !archResult.ok {
            passed = false
            errors.append(archResult.message)
        }
        
        // 2. Rosetta
        let rosettaResult = await Diagnostics.checkRosetta()
        if !rosettaResult.ok {
            passed = false
            errors.append(rosettaResult.message)
        }
        
        // 3. Dependencies
        let tools = ["cmake", "ninja", "sccache", "python3"]
        for tool in tools {
            let result = await Diagnostics.checkTool(tool)
            if !result.ok {
                passed = false
                errors.append(result.message)
            }
        }
        
        // 4. Xcode CLI
        let xcodeResult = await Diagnostics.checkXcodeCLITools()
        if !xcodeResult.ok {
            passed = false
            errors.append(xcodeResult.message)
        }
        
        if !passed {
            print("⚠️ Preflight Check Failures:")
            for error in errors {
                print("  - \(error)")
            }
        }
        
        return passed
    }
}

// MARK: - Models

struct BuildOptions {
    var buildType: BuildType = .releaseDebugInfo
    var platforms: Set<Platform> = [.macOS]
    var components: Set<BuildComponent> = [.stdlib, .swiftPM, .swiftDriver, .swiftSyntax, .swiftTesting, .swiftTestingMacros, .llbuild]
    var skipTests: Bool = true
}

enum BuildType: String {
    case debug = "Debug"
    case release = "Release"
    case releaseDebugInfo = "Release with Debug Info"
}

enum Platform: String {
    case macOS, iOS, tvOS, watchOS, visionOS
}

enum BuildComponent: String, CaseIterable {
    case stdlib
    case swiftPM
    case swiftDriver
    case swiftSyntax
    case swiftTesting
    case swiftTestingMacros
    case llbuild
}
