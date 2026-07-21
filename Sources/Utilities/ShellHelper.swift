import Foundation

private final class StreamingOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingData = Data()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        pendingData.append(data)
        var completeLines: [String] = []
        while let newlineIndex = pendingData.firstIndex(of: 0x0A) {
            var lineData = Data(pendingData[..<newlineIndex])
            pendingData.removeSubrange(...newlineIndex)
            if lineData.last == 0x0D { lineData.removeLast() }
            completeLines.append(String(decoding: lineData, as: UTF8.self))
        }
        return completeLines
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pendingData.isEmpty else { return nil }
        defer { pendingData.removeAll() }
        return String(decoding: pendingData, as: UTF8.self)
    }
}

public class ShellManager: @unchecked Sendable {
    public static let shared = ShellManager()
    private var activeProcesses: [UUID: Process] = [:]
    private let queue = DispatchQueue(label: "com.dinkisstyle.notarytool.shellmanager")
    
    private init() {}
    
    /// Runs a process and streams the output (both stdout and stderr combined) line by line.
    /// - Parameters:
    ///   - executable: The absolute path to the executable (e.g. `/usr/bin/codesign`).
    ///   - arguments: The array of arguments.
    ///   - processId: A unique ID to track and cancel this process if needed.
    ///   - onOutput: A callback invoked for every line of output.
    /// - Returns: The exit status code.
    public func runStream(
        executable: String,
        arguments: [String],
        processId: UUID = UUID(),
        onOutput: @escaping (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        queue.sync {
            activeProcesses[processId] = process
        }
        
        defer {
            queue.sync {
                activeProcesses[processId] = nil
            }
        }
        
        do {
            try process.run()
        } catch {
            onOutput("Failed to start process: \(error.localizedDescription)")
            throw error
        }
        
        let fileHandle = pipe.fileHandleForReading
        
        // Read available chunks without waiting for EOF. Some macOS tools launch
        // detached helpers that retain the pipe even after the command exits.
        let outputBuffer = StreamingOutputBuffer()
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputBuffer.append(data).forEach(onOutput)
        }

        let status = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }

        fileHandle.readabilityHandler = nil
        if let remainingOutput = outputBuffer.flush() {
            onOutput(remainingOutput)
        }
        return status
    }
    
    /// Runs a shell command through zsh and streams the output.
    public func runZshStream(
        command: String,
        processId: UUID = UUID(),
        onOutput: @escaping (String) -> Void
    ) async throws -> Int32 {
        return try await runStream(
            executable: "/bin/zsh",
            arguments: ["-c", command],
            processId: processId,
            onOutput: onOutput
        )
    }
    
    /// Runs a command synchronously and returns the status code and output.
    public func runSync(executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    /// Cancels a running process by its ID.
    public func cancelProcess(id: UUID) {
        let process = queue.sync { () -> Process? in
            let proc = activeProcesses[id]
            activeProcesses[id] = nil
            return proc
        }
        
        if let process = process, process.isRunning {
            process.terminate()
        }
    }
    
    /// Cancels all active processes.
    public func cancelAll() {
        let processes = queue.sync { () -> [Process] in
            let procs = Array(activeProcesses.values)
            activeProcesses.removeAll()
            return procs
        }
        
        for process in processes {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
