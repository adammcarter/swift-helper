import Foundation
import Subprocess

@discardableResult
func runCommand(_ command: String) async -> (output: String?, error: String?, exitCode: Int32) {
    do {
        // Run using sh/zsh to support shell features like pipes, redirects, etc.
        let args = Arguments(["-c", command])
        let result = try await Subprocess.run(
            .path("/bin/zsh"),
            arguments: args,
            environment: .custom(getEnvironmentWithHomebrewPath()),
            output: .string(limit: 10 * 1024 * 1024, encoding: UTF8.self), // 10MB limit
            error: .string(limit: 10 * 1024 * 1024, encoding: UTF8.self)
        )
        
        let output = result.standardOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = result.standardError?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let exitCode: Int32
        switch result.terminationStatus {
        case .exited(let code):
            exitCode = Int32(code)
        case .unhandledException(let signal):
            exitCode = Int32(signal)
        @unknown default:
            exitCode = -1
        }
        
        return (output?.isEmpty == false ? output : nil, error?.isEmpty == false ? error : nil, exitCode)
    } catch {
        return (nil, error.localizedDescription, -1)
    }
}

func runShellCommand(_ command: String) async -> Int32 {
    do {
        // Use standardOutput/Error to inherit (print to console directly)
        let args = Arguments(["-c", command])
        let result = try await Subprocess.run(
            .path("/bin/zsh"),
            arguments: args,
            environment: .custom(getEnvironmentWithHomebrewPath()),
            output: .standardOutput,
            error: .standardError
        )
        
        switch result.terminationStatus {
        case .exited(let code):
            return Int32(code)
        case .unhandledException(let signal):
            return Int32(signal)
        @unknown default:
            return -1
        }
    } catch {
        return -1
    }
}

private func getEnvironmentWithHomebrewPath() -> [Subprocess.Environment.Key: String] {
    var env = ProcessInfo.processInfo.environment
    let homebrewBin = "/opt/homebrew/bin"
    if let path = env["PATH"] {
        if !path.contains(homebrewBin) {
             env["PATH"] = "\(homebrewBin):\(path)"
        }
    } else {
        env["PATH"] = "\(homebrewBin):/usr/bin:/bin:/usr/sbin:/sbin"
    }
    
    var envKeys: [Subprocess.Environment.Key: String] = [:]
    for (k, v) in env {
        envKeys[Subprocess.Environment.Key(stringLiteral: k)] = v
    }
    return envKeys
}
