import Foundation
import ArgumentParser

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the Swift build-script with a configurable workflow."
    )
    
    @Option(name: .shortAndLong, help: "Path to the swift-project root.")
    var projectPath: String?

    @Flag(name: .long, help: "Skip interactive mode and use defaults.")
    var defaultBuild: Bool = false

    @Flag(name: .long, help: "Print the build command without executing it.")
    var dryRun: Bool = false
    
    @Flag(name: .long, help: "Rerun the last executed build command.")
    var rerun: Bool = false

    @Flag(name: .customLong("see-last"), help: "Print the last executed build command.")
    var seeLast: Bool = false

    @Flag(name: .long, inversion: .prefixedNo, help: "Sync built toolchain to ~/Library/Developer/Toolchains/swift-local.xctoolchain [Default: true]")
    var toolchain: Bool = true

    @Flag(name: .shortAndLong, help: "Skip confirmation prompts.")
    var yes: Bool = false

    func run() async throws {
        let fileManager = FileManager.default
        let lastCommandPath = NSTemporaryDirectory() + "/.swift-helper_last_command"
        
        // Resolve project path
        let resolvedPath: String
        if let userPath = projectPath {
            resolvedPath = NSString(string: userPath).expandingTildeInPath
        } else {
            // Check config
            let configPath = NSTemporaryDirectory() + "/.swift-helper_project_path"
            if let savedPath = try? String(contentsOfFile: configPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !savedPath.isEmpty {
                 resolvedPath = savedPath
            } else {
                 resolvedPath = NSString(string: "~/repos/swift-project").expandingTildeInPath
            }
        }
        
        // Handle See Last
        if seeLast {
             do {
                if fileManager.fileExists(atPath: lastCommandPath) {
                    let lastCommand = try String(contentsOfFile: lastCommandPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                    print("\nLast Executed Command:")
                    print("---------------------")
                    print(lastCommand)
                    print("---------------------\n")
                } else {
                    print("ℹ️  No previous build command found.")
                }
                return
            } catch {
                print("❌ Failed to read last command: \(error)")
                throw ExitCode.failure
            }
        }
        
        // Preflight Checks
        if !dryRun {
            let checksPassed = await performPreflightChecks()
            if !checksPassed {
                print("\n❌ Preflight checks failed. Please run 'swift-helper doctor --fix' to resolve issues.")
                throw ExitCode.failure
            }
        }
        
        guard fileManager.fileExists(atPath: resolvedPath) else {
            print("❌ Project path not found: \(resolvedPath)")
            throw ExitCode.failure
        }
        
        guard fileManager.changeCurrentDirectoryPath(resolvedPath) else {
            print("❌ Failed to change directory to: \(resolvedPath)")
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
                print("🔄 Rerunning last command in \(resolvedPath)...")
                
                print("Executing:")
                print("--------------------------------------------------")
                print(lastCommand)
                print("--------------------------------------------------\n")
                
                if dryRun {
                    print("(Dry Run - skipping execution)")
                    return
                }

                print("Press Enter to execute this command (or Ctrl+C to cancel)...", terminator: "")
                _ = readLine()
                
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
        
        print("\n🚀 Starting build in \(resolvedPath)...")
        print("Configuration:")
        print("  - Build Type: \(options.buildType.rawValue)")
        print("  - Platforms: \(options.platforms.map { $0.rawValue }.joined(separator: ", "))")
        print("  - Components: \(options.components.map { $0.rawValue }.joined(separator: ", "))")
        print("  - Tests: \(options.skipTests ? "Skipped" : "Enabled")")
        print("-----------------------------------\n")
        
        let buildCommand = constructBuildCommand(options)
        
        // Save command for rerun
        try? buildCommand.write(toFile: lastCommandPath, atomically: true, encoding: .utf8)
        
        print("Executing:")
        print("--------------------------------------------------")
        print(buildCommand)
        print("--------------------------------------------------\n")
        
        if dryRun {
             print("(Dry Run - skipping execution)")
        } else {
            if !yes {
                print("Press Enter to execute this command (or Ctrl+C to cancel)...", terminator: "")
                _ = readLine()
            }

            let status = await runShellCommand(buildCommand)
            if status != 0 {
                print("\n❌ Build failed with exit code \(status)")
                throw ExitCode.failure
            }
            
            print("\n✅ Build completed successfully!")
        }
        
        var shouldSync = toolchain
        
        if !shouldSync && !dryRun && !yes {
            print("\n📦 Do you want to install this toolchain locally? [y/N]: ", terminator: "")
            if let input = readLine(), input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "y" {
                shouldSync = true
            }
        }
        
        if shouldSync {
             var syncCmd = SyncToolchain()
             syncCmd.projectPath = resolvedPath
             syncCmd.yes = yes
             syncCmd.dryRun = dryRun
             try await syncCmd.run()
        }
    }
    
    // MARK: - Interactive Prompts
    
    func promptForOptions() async -> BuildOptions {
        var options = BuildOptions()
        
        // 1. Build Type
        while true {
            print("\n1. Select Build Type (Enter '?' for help):")
            print("   1) Release with Debug Info (Recommended for Dev) [Default]")
            print("   2) Release (Fastest Runtime)")
            print("   3) Debug (Fastest Build)")
            
            let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if input == "?" {
                print("\nℹ️  Build Types determine compiler optimizations and debug symbols:")
                print("   • Release with Debug Info: Best for development. Optimized code but keeps symbols for debugging.")
                print("   • Release: Maximum optimization. Harder to debug, but fastest execution.")
                print("   • Debug: No optimization. Fastest to build, but code runs slower. Best for step-through debugging.")
                continue
            }
            
            if input.isEmpty {
                options.buildType = .releaseDebugInfo
                break
            }
            
            if let choice = Int(input) {
                switch choice {
                case 1: options.buildType = .releaseDebugInfo; break
                case 2: options.buildType = .release; break
                case 3: options.buildType = .debug; break
                default: 
                    print("❌ Invalid selection.")
                    continue
                }
                break
            }
            print("❌ Invalid input.")
        }
        
        // 2. Platforms
        while true {
            print("\n2. Select Target Platforms (Enter '?' for help):")
            print("   1) macOS (arm64) only [Default]")
            print("   2) macOS + iOS")
            print("   3) macOS + iOS + tvOS + watchOS + visionOS")
            
            let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if input == "?" {
                print("\nℹ️  Platforms determine which OS SDKs the toolchain will support:")
                print("   • macOS only: Builds only for the host machine. Fastest.")
                print("   • macOS + iOS: Includes iOS device/simulator support.")
                print("   • All Platforms: Includes tvOS, watchOS, and visionOS. Significantly longer build time.")
                continue
            }
            
            if input.isEmpty {
                options.platforms = [.macOS]
                break
            }
            
            if let choice = Int(input) {
                switch choice {
                case 1: options.platforms = [.macOS]; break
                case 2: options.platforms = [.macOS, .iOS]; break
                case 3: options.platforms = [.macOS, .iOS, .tvOS, .watchOS, .visionOS]; break
                default: 
                    print("❌ Invalid selection.")
                    continue
                }
                break
            }
            print("❌ Invalid input.")
        }
        
        // 3. Components
        while true {
            print("\n3. Select Components to Build (Enter '?' for help):")
            print("   1) Minimal (Stdlib + SwiftPM + Driver + Testing) [Default]")
            print("   2) Compiler Only (Stdlib + Driver)")
            print("   3) Full Toolchain (Everything)")
            
            let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if input == "?" {
                print("\nℹ️  Components determine which parts of the Swift ecosystem are built:")
                print("   • Minimal: Standard development set.")
                print("     Builds: stdlib, swiftpm, swift-driver, swift-syntax")
                print("     Modules available to import:")
                print("       - Swift")
                print("       - _Concurrency")
                print("       - _StringProcessing")
                print("       - RegexBuilder")
                print("       - PackageDescription")
                print("       - SwiftSyntax")
                print("       - SwiftParser")
                
                print("   • Compiler Only: Just the essentials to run 'swiftc'.")
                print("     Builds: stdlib, swift-driver")
                print("     Modules available to import:")
                print("       - Swift")
                print("       - _Concurrency")
                
                print("   • Full Toolchain: Every component in the repo.")
                print("     Builds: All of the above plus llbuild, SourceKit, etc.")
                print("     Modules available to import:")
                print("       - All modules from Minimal")
                print("       - SwiftDriver")
                print("       - SwiftOptions")
                print("       - llbuild")
                continue
            }
            
            if input.isEmpty {
                options.components = [.stdlib, .swiftPM, .swiftDriver, .swiftSyntax, .llbuild]
                break
            }
            
            if let choice = Int(input) {
                switch choice {
                case 1: options.components = [.stdlib, .swiftPM, .swiftDriver, .swiftSyntax, .llbuild]; break
                case 2: options.components = [.stdlib, .swiftDriver]; break
                case 3: options.components = Set(BuildComponent.allCases); break
                default: 
                    print("❌ Invalid selection.")
                    continue
                }
                break
            }
            print("❌ Invalid input.")
        }
        
        // 4. Testing
        while true {
            print("\n4. Run Tests? (Enter '?' for help):")
            print("   1) Skip All Tests (Fastest) [Default]")
            print("   2) Run Tests")
            
            let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if input == "?" {
                print("\nℹ️  Testing runs the test suites for the built components:")
                print("   • Skip All Tests: Finishes immediately after build. Recommended unless you are verifying changes.")
                print("   • Run Tests: Runs thousands of tests. Can take 30+ minutes.")
                continue
            }
            
            if input.isEmpty {
                options.skipTests = true
                break
            }
            
            if let choice = Int(input) {
                options.skipTests = (choice != 2)
                break
            }
            print("❌ Invalid input.")
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
        let tools = ["cmake", "ninja", "sccache", "python3", "git", "rsync"]
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
    var components: Set<BuildComponent> = [.stdlib, .swiftPM, .swiftDriver, .swiftSyntax, .llbuild]
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
