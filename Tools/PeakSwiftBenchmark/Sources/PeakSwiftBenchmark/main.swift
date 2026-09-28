import Darwin
import Foundation
import PeakSwiftBenchmarkSupport

do {
    let options = try BenchmarkOptions.parse(Array(CommandLine.arguments.dropFirst()))
    try PeakSwiftPredictionRunner.run(options: options)
} catch {
    let message = "PeakSwift benchmark error: \(error.localizedDescription)\n\n\(BenchmarkOptions.usage)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(2)
}
