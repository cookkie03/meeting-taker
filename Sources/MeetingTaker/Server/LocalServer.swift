import Foundation
import Vapor
import OpenAPIRuntime
import OpenAPIVapor
import WhisperKit
import SpeakerKit

/// Local server providing OpenAI-compatible API for transcription
/// Runs entirely on-device, no external dependencies
public actor LocalServer {

    // MARK: - Properties

    private var app: Application?
    private var transcriptionEngine: TranscriptionEngine?
    private var diarizationEngine: DiarizationEngine?
    private let port: Int
    private let modelName: String

    // MARK: - Initialization

    public init(port: Int = 50060, modelName: String = TranscriptionEngine.defaultModel) {
        self.port = port
        self.modelName = modelName
    }

    // MARK: - Server Control

    /// Start the local server
    public func start() async throws {
        // Initialize engines
        transcriptionEngine = TranscriptionEngine(model: modelName)
        try await transcriptionEngine?.initialize()

        diarizationEngine = DiarizationEngine()
        try await diarizationEngine?.initialize()

        // Create Vapor app
        let env = try Environment.detect()
        let app = Application(env)
        self.app = app

        // Configure server
        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = port

        // Setup routes
        try setupRoutes(app)

        // Start server
        try app.start()

        print("MeetingTaker server running at http://localhost:\(port)/v1")
    }

    /// Stop the server
    public func stop() async {
        await app?.shutdown()
        app = nil
    }

    // MARK: - Routes

    private func setupRoutes(_ app: Application) throws {
        // Health check
        app.get("health") { req in
            ["status": "ok", "model": self.modelName]
        }

        // Transcription endpoint (OpenAI-compatible)
        app.on(.POST, "v1", "audio", "transcriptions") { [weak self] req -> Response in
            guard let self = self else {
                return Response(status: .internalServerError)
            }
            return try await self.handleTranscription(req: req)
        }

        // Translation endpoint (OpenAI-compatible)
        app.on(.POST, "v1", "audio", "translations") { [weak self] req -> Response in
            guard let self = self else {
                return Response(status: .internalServerError)
            }
            return try await self.handleTranslation(req: req)
        }

        // Models endpoint
        app.get("v1", "models") { req in
            [
                "object": "list",
                "data": [
                    [
                        "id": self.modelName,
                        "object": "model",
                        "created": Int(Date().timeIntervalSince1970),
                        "owned_by": "meeting-taker"
                    ]
                ]
            ]
        }
    }

    // MARK: - Transcription Handler

    private func handleTranscription(req: Request) async throws -> Response {
        // Parse multipart form data
        guard let file = req.body.data else {
            throw Abort(.badRequest, reason: "No audio file provided")
        }

        // Save to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("upload_\(UUID().uuidString).wav")
        try await file.write(to: tempFile)

        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Get parameters from query/body
        let language = req.query[String.self, at: "language"]
        let enableDiarization = req.query[Bool.self, at: "diarize"] ?? false

        // Transcribe
        guard let engine = transcriptionEngine else {
            throw Abort(.internalServerError, reason: "Transcription engine not initialized")
        }

        let result = try await engine.transcribeFile(
            at: tempFile.path,
            language: language
        )

        // Build OpenAI-compatible response
        let response: [String: Any] = [
            "text": result.fullText,
            "language": result.language ?? "unknown",
            "duration": result.duration,
            "segments": result.segments.map { segment in
                [
                    "id": segment.id.uuidString,
                    "start": segment.startTime,
                    "end": segment.endTime,
                    "text": segment.text,
                    "speaker": segment.speaker ?? NSNull(),
                ]
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: jsonData))
    }

    // MARK: - Translation Handler

    private func handleTranslation(req: Request) async throws -> Response {
        // For now, translation is the same as transcription to English
        // WhisperKit handles translation natively
        try await handleTranscription(req: req)
    }
}
