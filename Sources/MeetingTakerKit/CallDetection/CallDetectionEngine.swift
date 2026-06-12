import Foundation
import CoreAudio
import AppKit

// MARK: - Call Detection Result

/// Represents a detected meeting/call
public struct DetectedCall: Sendable {
    public let appName: String
    public let source: DetectionSource
    public let confidence: CallConfidence

    public enum DetectionSource: Sendable {
        case processActive       // Known meeting process running
        case micInUseByApp       // CoreAudio: this app's PID is capturing mic
        case browserTab          // Chrome/Safari has meeting tab
        case calendarEvent       // Calendar integration
    }

    public enum CallConfidence: Sendable {
        case high    // Multiple signals agree
        case medium  // Single strong signal
        case low     // Weak signal (e.g. mic active but no known app)
    }
}

// MARK: - Call Detection Engine

/// Automatically detects when the Mac is in a meeting/call.
///
/// Uses multiple signals:
/// 1. Process detection — known meeting apps running
/// 2. CoreAudio per-process mic check — which PIDs are capturing audio
/// 3. Browser tab detection — Chrome/Safari meeting URLs
///
/// All checks are local, no network calls, no external dependencies.
public actor CallDetectionEngine {

    // MARK: - Known Meeting Processes

    /// Processes that exist ONLY during an active meeting session.
    /// These are narrow — no "Helper" processes that run all the time.
    private let activeSessionProcesses: [(fragment: String, name: String)] = [
        ("CptHost",              "Zoom"),           // Zoom meeting capture host
        ("zoom.us",              "Zoom"),           // Zoom main process
        ("FaceTime",             "FaceTime"),       // FaceTime (only during call)
        ("Tuple",                "Tuple"),          // Tuple screen share
        ("Webex",                "Webex"),          // Webex meeting
        ("Around Helper",        "Around"),         // Around meeting
        ("Loom",                 "Loom"),           // Loom recording
    ]

    /// Broader list for initial detection (includes helpers).
    /// Used only at recording start to identify the meeting name.
    private let broadMeetingProcesses: [(fragment: String, name: String)] = [
        ("zoom.us",                    "Zoom"),
        ("Slack Helper",               "Slack Huddle"),
        ("Microsoft Teams Helper",     "Microsoft Teams"),
        ("Webex",                      "Webex"),
        ("Around Helper",              "Around"),
        ("Tuple",                      "Tuple"),
        ("Loom",                       "Loom"),
        ("FaceTime",                   "FaceTime"),
        ("Discord Helper",             "Discord"),
        ("Google Meet",                "Google Meet"),
    ]

    /// Meeting URL patterns to check in browser tabs
    private let meetingURLPatterns: [(pattern: String, name: String)] = [
        ("meet.google.com",           "Google Meet"),
        ("teams.microsoft.com/meet",  "Microsoft Teams"),
        ("teams.microsoft.com/v2",    "Microsoft Teams"),
        ("app.huddle.team",           "Slack Huddle"),
        ("zoom.us/j/",                "Zoom"),
    ]

    // MARK: - Public API

    /// Check if a meeting is currently in progress.
    /// Returns the detected call info, or nil if no meeting detected.
    public func detectCall() async -> DetectedCall? {
        var detectedSource: DetectedCall.DetectionSource?
        var appName: String?
        var confidence: DetectedCall.CallConfidence = .low

        // Signal 1: Active session process check (highest confidence)
        if let (name, source) = checkActiveSessionProcesses() {
            appName = name
            detectedSource = source
            confidence = .high
        }

        // Signal 2: CoreAudio per-process mic check (high confidence)
        if detectedSource == nil {
            if let (name, source) = await checkMicUsageByMeetingApps() {
                appName = name
                detectedSource = source
                confidence = .high
            }
        }

        // Signal 3: Browser tab check (medium confidence)
        if detectedSource == nil {
            if let (name, source) = checkBrowserTabs() {
                appName = name
                detectedSource = source
                confidence = .medium
            }
        }

        // Signal 4: Broad process check + mic activity (low-medium confidence)
        if detectedSource == nil {
            if isMicActive(), let (name, source) = checkBroadMeetingProcesses() {
                appName = name
                detectedSource = source
                confidence = .medium
            }
        }

        // Signal 5: Mic active but no known app (low confidence — could be dictation, Siri, etc.)
        if detectedSource == nil && isMicActive() {
            appName = "Unknown Call"
            detectedSource = .micInUseByApp
            confidence = .low
        }

        guard let source = detectedSource, let name = appName else { return nil }

        return DetectedCall(
            appName: name,
            source: source,
            confidence: confidence
        )
    }

    /// Check if microphone is currently in use by any process.
    /// Uses CoreAudio's `kAudioDevicePropertyDeviceIsRunningSomewhere`.
    public func isMicActive() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard getStatus == noErr, deviceID != 0 else { return false }

        var running = UInt32(0)
        var runningSize = UInt32(MemoryLayout<UInt32>.size)

        let runStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &runningSize,
            &running
        )

        return runStatus == noErr && running != 0
    }

    /// Get the name of the current meeting if detectable (broad check).
    public func detectMeetingName() -> String? {
        // Check native processes
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: [])
        let processNames = runningApps.map { $0.localizedName ?? "" }

        for (fragment, name) in broadMeetingProcesses {
            if processNames.contains(where: { $0.contains(fragment) }) {
                return name
            }
        }

        // Check browser tabs
        if let (name, _) = checkBrowserTabs() {
            return name
        }

        return nil
    }

    // MARK: - Signal 1: Active Session Processes

    private func checkActiveSessionProcesses() -> (String, DetectedCall.DetectionSource)? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: [])
        let processNames = runningApps.map { $0.localizedName ?? "" }

        for (fragment, name) in activeSessionProcesses {
            if processNames.contains(where: { $0.contains(fragment) }) {
                return (name, .processActive)
            }
        }
        return nil
    }

    // MARK: - Signal 2: CoreAudio Per-Process Mic Check

    private func checkMicUsageByMeetingApps() async -> (String, DetectedCall.DetectionSource)? {
        guard let micPids = getPIDsUsingMicInput() else { return nil }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: [])

        for app in runningApps {
            guard let pid = app.processIdentifier as? Int32 else { continue }
            if micPids.contains(pid) {
                let appName = app.localizedName ?? "Unknown"

                // Check if this is a known meeting app
                for (fragment, name) in activeSessionProcesses {
                    if appName.contains(fragment) {
                        return (name, .micInUseByApp)
                    }
                }

                // Check broad list
                for (fragment, name) in broadMeetingProcesses {
                    if appName.contains(fragment) {
                        return (name, .micInUseByApp)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Signal 3: Browser Tab Detection

    private func checkBrowserTabs() -> (String, DetectedCall.DetectionSource)? {
        // Check Chrome
        if let name = checkChromeTabs() {
            return (name, .browserTab)
        }
        // Check Safari
        if let name = checkSafariTabs() {
            return (name, .browserTab)
        }
        return nil
    }

    private func checkChromeTabs() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Google Chrome") then return ""
        end tell
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "meet.google.com" then
                        if not (title of t contains "ended") then return "Google Meet"
                    end if
                    if u contains "teams.microsoft.com" then return "Microsoft Teams"
                    if u contains "app.huddle.team" then return "Slack Huddle"
                    if u contains "zoom.us/j/" then return "Zoom"
                end repeat
            end repeat
        end tell
        return ""
        """

        if let result = runAppleScript(script), !result.isEmpty {
            return result
        }
        return nil
    }

    private func checkSafariTabs() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
            repeat with w in windows
                try
                    set u to URL of current tab of w
                    if u contains "meet.google.com" then return "Google Meet"
                    if u contains "teams.microsoft.com" then return "Microsoft Teams"
                    if u contains "zoom.us/j/" then return "Zoom"
                end try
            end repeat
        end tell
        return ""
        """

        if let result = runAppleScript(script), !result.isEmpty {
            return result
        }
        return nil
    }

    // MARK: - Signal 4: Broad Process Check

    private func checkBroadMeetingProcesses() -> (String, DetectedCall.DetectionSource)? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: [])
        let processNames = runningApps.map { $0.localizedName ?? "" }

        for (fragment, name) in broadMeetingProcesses {
            if processNames.contains(where: { $0.contains(fragment) }) {
                return (name, .processActive)
            }
        }
        return nil
    }

    // MARK: - CoreAudio C API

    /// Get PIDs of all processes currently capturing audio input.
    /// Uses `kAudioHardwarePropertyProcessObjectList` (macOS 14+).
    private func getPIDsUsingMicInput() -> Set<Int32>? {
        let ownPID = getpid()

        // Get the default input device
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &deviceSize,
            &deviceID
        )

        guard deviceStatus == noErr, deviceID != 0 else { return nil }

        // Get process object list
        var processListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var listSize: UInt32 = 0
        let listStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &processListAddress,
            0,
            nil,
            &listSize
        )

        guard listStatus == noErr, listSize > 0 else { return nil }

        let count = Int(listSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)

        let getDataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &processListAddress,
            0,
            nil,
            &listSize,
            &processIDs
        )

        guard getDataStatus == noErr else { return nil }

        var result = Set<Int32>()

        for processObjectID in processIDs {
            // Check if this process is using audio input
            var isRunningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var isRunning = UInt32(0)
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)

            let runStatus = AudioObjectGetPropertyData(
                processObjectID,
                &isRunningAddress,
                0,
                nil,
                &isRunningSize,
                &isRunning
            )

            guard runStatus == noErr, isRunning != 0 else { continue }

            // Get the PID
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var pid = Int32(0)
            var pidSize = UInt32(MemoryLayout<Int32>.size)

            let pidStatus = AudioObjectGetPropertyData(
                processObjectID,
                &pidAddress,
                0,
                nil,
                &pidSize,
                &pid
            )

            guard pidStatus == noErr, pid != ownPID else { continue }

            result.insert(pid)
        }

        return result
    }

    // MARK: - AppleScript Helper

    private func runAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else { return nil }

        let output = scriptObject.executeAndReturnError(&error)
        if let error = error {
            return nil
        }
        return output.stringValue
    }
}

// MARK: - Auto-Recording Trigger

/// Watches for calls and can auto-start/auto-stop recording.
/// Uses a polling loop with configurable intervals.
public actor CallWatcher {

    public struct Configuration: Sendable {
        public var pollInterval: TimeInterval = 2.0
        public var warmupDuration: TimeInterval = 5.0   // Mic must be active this long before starting
        public var graceDuration: TimeInterval = 5.0    // Mic must be idle this long before stopping
        public var minimumRecordingDuration: TimeInterval = 30.0  // Discard recordings shorter than this
        public var autoStartRecording: Bool = false
        public var autoStopRecording: Bool = false

        public init() {}
    }

    public enum State: Sendable {
        case idle
        case warming       // Mic active, waiting to confirm
        case recording     // Actively recording
        case cooling       // Mic idle, waiting to confirm stop
    }

    public var state: State = .idle
    public var currentCall: DetectedCall?

    private let config: Configuration
    private let detectionEngine: CallDetectionEngine
    private var isWatching = false
    private var onCallDetected: ((DetectedCall) -> Void)?
    private var onCallEnded: ((DetectedCall) -> Void)?

    public init(config: Configuration = Configuration()) {
        self.config = config
        self.detectionEngine = CallDetectionEngine()
    }

    /// Start watching for calls.
    /// - Parameters:
    ///   - onCallDetected: Called when a call is detected (after warmup)
    ///   - onCallEnded: Called when a call ends (after grace period)
    public func startWatching(
        onCallDetected: @escaping @Sendable (DetectedCall) -> Void,
        onCallEnded: @escaping @Sendable (DetectedCall) -> Void
    ) {
        guard !isWatching else { return }
        isWatching = true
        self.onCallDetected = onCallDetected
        self.onCallEnded = onCallEnded

        Task {
            await watchLoop()
        }
    }

    public func stopWatching() {
        isWatching = false
        state = .idle
        currentCall = nil
    }

    private func watchLoop() async {
        var warmupStart: Date?
        var coolingStart: Date?
        var recordingStart: Date?

        while isWatching {
            let call = await detectionEngine.detectCall()
            let now = Date()

            switch state {
            case .idle:
                if call != nil {
                    state = .warming
                    warmupStart = now
                }

            case .warming:
                if call == nil {
                    // False positive — mic was briefly active
                    state = .idle
                    warmupStart = nil
                } else if let start = warmupStart, now.timeIntervalSince(start) >= config.warmupDuration {
                    // Confirmed call
                    currentCall = call
                    state = .recording
                    recordingStart = now
                    warmupStart = nil
                    onCallDetected?(call!)
                }

            case .recording:
                if call == nil {
                    // Mic went silent — start grace period
                    state = .cooling
                    coolingStart = now
                }

            case .cooling:
                if call != nil {
                    // Call came back (e.g. rejoined)
                    state = .recording
                    coolingStart = nil
                } else if let start = coolingStart, now.timeIntervalSince(start) >= config.graceDuration {
                    // Confirmed call end
                    let duration = recordingStart.map { now.timeIntervalSince($0) } ?? 0
                    if duration >= config.minimumRecordingDuration, let call = currentCall {
                        onCallEnded?(call)
                    }
                    state = .idle
                    currentCall = nil
                    coolingStart = nil
                    recordingStart = nil
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))
        }
    }
}
