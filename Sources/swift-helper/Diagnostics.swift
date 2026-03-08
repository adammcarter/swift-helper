import Foundation

struct Diagnostics {
    
    struct CheckResult {
        let ok: Bool
        let message: String
    }
    
    // MARK: - Core Checks
    
    static func checkArchitecture() async -> CheckResult {
        let arch = (await runCommand("uname -m")).output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        if arch == "arm64" {
            return CheckResult(ok: true, message: "Machine architecture is arm64")
        } else {
            return CheckResult(ok: false, message: "Machine architecture is \(arch) (expected arm64)")
        }
    }
    
    static func checkRosetta() async -> CheckResult {
        let translated = (await runCommand("sysctl -n sysctl.proc_translated")).output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        if translated == "1" {
            return CheckResult(ok: false, message: "Current shell is running under Rosetta")
        } else {
            return CheckResult(ok: true, message: "Current shell is not running under Rosetta")
        }
    }
    
    static func checkXcodeCLITools() async -> CheckResult {
        let result = await runCommand("/usr/bin/xcode-select -p")
        if result.exitCode == 0 {
            return CheckResult(ok: true, message: "Xcode command line tools are installed")
        } else {
            return CheckResult(ok: false, message: "Xcode command line tools are not installed")
        }
    }
    
    // MARK: - Tool Checks
    
    static func checkTool(_ tool: String, brewFormula: String? = nil) async -> CheckResult {
        guard let path = (await runCommand("which \(tool)")).output?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return CheckResult(ok: false, message: "\(tool) missing")
        }
        
        let fileInfo = (await runCommand("file \"\(path)\"")).output ?? ""
        
        // Simple architecture check
        let isArm64 = fileInfo.contains("arm64") || fileInfo.contains("arm64e")
        // Python universal binary check logic from Doctor.swift could be simplified here or preserved
        // Doctor: if fileInfo.contains("x86_64") && !fileInfo.contains("arm64")...
        
        if fileInfo.contains("x86_64") && !isArm64 {
            return CheckResult(ok: false, message: "\(tool) is x86_64-only (at \(path))")
        }
        
        return CheckResult(ok: true, message: "\(tool) is valid (at \(path))")
    }
    
    static func checkDeveloperTools() async -> [CheckResult] {
        var results: [CheckResult] = []
        
        // xcrun
        if let path = (await runCommand("which xcrun")).output?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let fileInfo = (await runCommand("file \"\(path)\"")).output ?? ""
            if fileInfo.contains("arm64") || fileInfo.contains("arm64e") {
                results.append(CheckResult(ok: true, message: "xcrun supports arm64"))
            } else {
                results.append(CheckResult(ok: false, message: "xcrun does not support arm64"))
            }
        } else {
            results.append(CheckResult(ok: false, message: "xcrun not found"))
        }
        
        // clang, swiftc via xcrun
        for tool in ["clang", "swiftc"] {
            if let path = (await runCommand("/usr/bin/xcrun -f \(tool)")).output?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let fileInfo = (await runCommand("file \"\(path)\"")).output ?? ""
                if fileInfo.contains("arm64") || fileInfo.contains("arm64e") {
                     results.append(CheckResult(ok: true, message: "\(tool) supports arm64"))
                } else {
                     results.append(CheckResult(ok: false, message: "\(tool) does not support arm64"))
                }
            } else {
                results.append(CheckResult(ok: false, message: "\(tool) not resolvable via xcrun"))
            }
        }
        
        return results
    }
    
    static func checkSDK() async -> CheckResult {
        if let sdkPath = (await runCommand("/usr/bin/xcrun --sdk macosx --show-sdk-path")).output?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return CheckResult(ok: true, message: "macOS SDK found at \(sdkPath)")
        } else {
            return CheckResult(ok: false, message: "Could not resolve macOS SDK path")
        }
    }
}
