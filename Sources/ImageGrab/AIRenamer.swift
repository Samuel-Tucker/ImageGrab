import Foundation

final class AIRenamer: Sendable {
    /// Suggest a descriptive name for a screenshot.
    /// Tries ollama+moondream (vision) first, falls back to kimi-cli (text-only).
    func suggestName(for filename: String, imageURL: URL) async -> String? {
        if let name = await ollamaSuggestName(imageURL: imageURL) {
            return name
        }
        return await kimiSuggestName(for: filename)
    }

    // MARK: - Ollama (vision model)

    private func ollamaSuggestName(imageURL: URL) async -> String? {
        guard let imageData = try? Data(contentsOf: imageURL) else { return nil }
        let base64Image = imageData.base64EncodedString()

        guard let url = URL(string: "http://localhost:11434/api/generate") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "moondream",
            "prompt": "Describe this screenshot in 2-4 words for use as a filename. Use kebab-case, no extension. Output ONLY the filename, nothing else.",
            "images": [base64Image],
            "stream": false
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["response"] as? String else { return nil }
            return Self.sanitize(output)
        } catch {
            return nil
        }
    }

    // MARK: - Kimi CLI (text-only fallback)

    private func kimiSuggestName(for filename: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                guard let kimiPath = Self.findKimiCli() else {
                    continuation.resume(returning: nil)
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: kimiPath)
                process.arguments = ["--quiet", "--no-thinking", "-p",
                    "I have a screenshot file named \(filename). Suggest a short descriptive name (2-4 words, kebab-case, no extension). Output ONLY the filename, nothing else."]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                let timer = DispatchSource.makeTimerSource()
                timer.schedule(deadline: .now() + 10)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty, output.count < 60 {
                        continuation.resume(returning: Self.sanitize(output))
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

    // MARK: - Helpers

    private static func findKimiCli() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/kimi-cli",
            "/usr/local/bin/kimi-cli",
            "/opt/homebrew/bin/kimi-cli"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func sanitize(_ output: String) -> String? {
        let sanitized = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !sanitized.isEmpty, sanitized.count < 60 else { return nil }
        return sanitized
    }
}
