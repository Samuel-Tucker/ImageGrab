import Foundation

final class AIRenamer: Sendable {
    func suggestName(for filename: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/Users/charles/.local/bin/kimi-cli")
                process.arguments = ["--quiet", "--no-thinking", "-p",
                    "I have an image file named \(filename). Suggest a short descriptive name (2-4 words, kebab-case, no extension). Output ONLY the filename, nothing else."]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                let timer = DispatchSource.makeTimerSource()
                timer.schedule(deadline: .now() + 5)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty, output.count < 60 {
                        let sanitized = output.lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                        continuation.resume(returning: sanitized.isEmpty ? nil : sanitized)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    timer.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
