import Foundation
import ArgumentParser
import WhisperKit
import SpeakerKit
import Vapor

/// MeetingTaker CLI — Professional transcription from the command line
@main
struct MeetingTakerCLI: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "mtaker",
        abstract: "Professional-grade, on-device transcription for macOS",
        version: "1.0.0",
        subcommands: [Transcribe.self, Diarize.self, Serve.self, Models.self],
        defaultSubcommand: Transcribe.self
    )
}

// MARK: - Transcribe Command

struct Transcribe: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio file to text"
    )

    @Option(name: .shortAndLong, help: "Path to the audio file")
    var audioPath: String

    @Option(name: .shortAndLong, help: "Model to use (default: large-v3-v20240930_626MB)")
    var model: String = TranscriptionEngine.defaultModel

    @Option(name: .shortAndLong, help: "Language code (e.g. en, it, auto)")
    var language: String?

    @Option(name: .shortAndLong, help: "Output format (txt, json, srt, vtt, csv)")
    var format: String = "txt"

    @Option(name: .shortAndLong, help: "Output file path (default: stdout)")
    var output: String?

    @Flag(name: .shortAndLong, help: "Enable speaker diarization")
    var diarize: Bool = false

    @Option(name: .long, help: "Maximum number of speakers (0 = auto)")
    var maxSpeakers: Int = 0

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    func run() async throws {
        if verbose {
            print("Initializing MeetingTaker...")
            print("Model: \(model)")
        }

        // Initialize engine
        let engine = TranscriptionEngine(model: model)
        try await engine.initialize()

        if verbose {
            print("Transcribing: \(audioPath)")
        }

        // Transcribe
        let result = try await engine.transcribeFile(
            at: audioPath,
            language: language,
            progressCallback: { progress in
                if verbose {
                    let pct = Int(progress * 100)
                    print("\rProgress: \(pct)%", terminator: "")
                    fflush(stdout)
                }
            }
        )

        if verbose {
            print("\nTranscription complete!")
            print("Duration: \(result.duration)s")
            print("Segments: \(result.segments.count)")
        }

        // Diarize if requested
        var finalResult = result
        if diarize {
            if verbose { print("Running speaker diarization...") }
            let diarEngine = DiarizationEngine()
            let diarSegments = try await diarEngine.diarize(
                audioPath: audioPath,
                maxSpeakers: maxSpeakers == 0 ? nil : maxSpeakers
            )
            // Merge (simplified)
            if verbose { print("Found \(Set(diarSegments.map(\.speaker)).count) speakers") }
        }

        // Export
        let exportFormat = ExportFormat(rawValue: format) ?? .txt
        let exporter = ExportEngine()

        if let outputPath = output {
            let url = URL(fileURLWithPath: outputPath)
            try exporter.export(finalResult, to: exportFormat, at: url)
            if verbose { print("Saved to: \(outputPath)") }
        } else {
            // Print to stdout
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("output.\(format)")
            try exporter.export(finalResult, to: exportFormat, at: tempURL)
            let content = try String(contentsOf: tempURL)
            print(content)
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}

// MARK: - Diarize Command

struct Diarize: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "diarize",
        abstract: "Identify speakers in an audio file"
    )

    @Option(name: .shortAndLong, help: "Path to the audio file")
    var audioPath: String

    @Option(name: .long, help: "Maximum number of speakers (0 = auto)")
    var maxSpeakers: Int = 0

    @Option(name: .shortAndLong, help: "Output file path (default: stdout)")
    var output: String?

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    func run() async throws {
        if verbose { print("Initializing SpeakerKit...") }

        let engine = DiarizationEngine()
        try await engine.initialize()

        if verbose { print("Diarizing: \(audioPath)") }

        let segments = try await engine.diarize(
            audioPath: audioPath,
            maxSpeakers: maxSpeakers == 0 ? nil : maxSpeakers
        )

        let speakers = Set(segments.map(\.speaker))
        if verbose {
            print("Found \(speakers.count) speakers:")
            for speaker in speakers.sorted() {
                let speakerSegments = segments.filter { $0.speaker == speaker }
                let totalTime = speakerSegments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
                print("  \(speaker): \(String(format: "%.1f", totalTime))s")
            }
        }

        // Output RTTM
        let rttm = engine.exportRTTM(segments: segments, fileId: URL(fileURLWithPath: audioPath).lastPathComponent)

        if let outputPath = output {
            try rttm.write(toFile: outputPath, atomically: true, encoding: .utf8)
            if verbose { print("Saved RTTM to: \(outputPath)") }
        } else {
            print(rttm)
        }
    }
}

// MARK: - Serve Command

struct Serve: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start a local OpenAI-compatible transcription server"
    )

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 50060

    @Option(name: .shortAndLong, help: "Model to use")
    var model: String = TranscriptionEngine.defaultModel

    @Option(name: .shortAndLong, help: "Host to bind to")
    var host: String = "0.0.0.0"

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    func run() async throws {
        print("Starting MeetingTaker server...")
        print("  Host: \(host)")
        print("  Port: \(port)")
        print("  Model: \(model)")
        print("")
        print("API endpoints:")
        print("  POST http://localhost:\(port)/v1/audio/transcriptions")
        print("  POST http://localhost:\(port)/v1/audio/translations")
        print("  GET  http://localhost:\(port)/v1/models")
        print("  GET  http://localhost:\(port)/health")
        print("")
        print("Example:")
        print("  curl -X POST http://localhost:\(port)/v1/audio/transcriptions \\")
        print("    -F file=@audio.wav \\")
        print("    -F model=\(model)")
        print("")

        let server = LocalServer(port: port, modelName: model)
        try await server.start()

        // Keep running
        try await Task.sleep(for: .seconds(999999))
    }
}

// MARK: - Models Command

struct Models: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List available transcription models"
    )

    func run() throws {
        print("Available models:")
        print("")
        for tier in TranscriptionEngine.modelTiers {
            let marker = tier.name == TranscriptionEngine.defaultModel ? " (recommended)" : ""
            print("  \(tier.name)\(marker)")
            print("    \(tier.description)")
            print("    Size: \(tier.size)")
            print("")
        }
    }
}
