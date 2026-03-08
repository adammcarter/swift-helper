import ArgumentParser
import Foundation

@main
struct SwiftHelper: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-helper",
        abstract: "A utility for managing local Swift toolchain builds.",
        subcommands: [Doctor.self, Build.self, Test.self],
        defaultSubcommand: Doctor.self
    )
}
