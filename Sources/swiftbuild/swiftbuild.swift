import ArgumentParser
import Foundation

@main
struct SwiftBuild: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftbuild",
        abstract: "A utility for managing local Swift toolchain builds.",
        subcommands: [Doctor.self, Build.self, Test.self],
        defaultSubcommand: Doctor.self
    )
}
