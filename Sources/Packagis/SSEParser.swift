import Foundation

struct SSEParser {
    private var buffer = Data()
    private var eventName: String?
    private var dataLines: [String] = []
    private var eventID: String?
    private var retryMilliseconds: Int?
    private var hasDataField = false
    private var isFirstLine = true
    private var accumulatedEventBytes = 0
    private var accumulatedEventLines = 0
    private var shouldIgnoreLeadingLF = false

    private let maximumLineBytes: Int
    private let maximumEventBytes: Int
    private let maximumBufferBytes: Int
    private let maximumEventLines: Int

    init(
        maximumLineBytes: Int = 64 * 1_024,
        maximumEventBytes: Int = 2 * 1_024 * 1_024,
        maximumBufferBytes: Int = 4 * 1_024 * 1_024,
        maximumEventLines: Int = 16_384
    ) {
        self.maximumLineBytes = maximumLineBytes
        self.maximumEventBytes = maximumEventBytes
        self.maximumBufferBytes = maximumBufferBytes
        self.maximumEventLines = maximumEventLines
    }

    mutating func feed(_ chunk: Data) throws -> [SSEEvent] {
        buffer.append(chunk)

        guard buffer.count <= maximumBufferBytes else {
            throw PackagisError.SSELimitExceeded
        }

        var events: [SSEEvent] = []

        while true {
            if shouldIgnoreLeadingLF {
                guard !buffer.isEmpty else {
                    break
                }
                if buffer[buffer.startIndex] == 0x0A {
                    buffer.removeFirst()
                }
                shouldIgnoreLeadingLF = false
            }

            guard let delimiter = nextLineDelimiter() else {
                break
            }

            let endedWithCarriageReturn = buffer[delimiter.index] == 0x0D
            let lineData = Data(buffer[buffer.startIndex ..< delimiter.index])
            let removalEnd = buffer.index(
                delimiter.index,
                offsetBy: delimiter.length
            )
            buffer.removeSubrange(buffer.startIndex ..< removalEnd)

            guard lineData.count <= maximumLineBytes else {
                throw PackagisError.SSELimitExceeded
            }

            if endedWithCarriageReturn {
                shouldIgnoreLeadingLF = true
            }
            try process(lineData, events: &events)
        }

        guard buffer.count <= maximumLineBytes else {
            throw PackagisError.SSELimitExceeded
        }

        return events
    }

    mutating func finish() throws -> [SSEEvent] {
        try feed(Data([0x0A, 0x0A]))
    }

    private func nextLineDelimiter() -> (index: Data.Index, length: Int)? {
        var index = buffer.startIndex

        while index < buffer.endIndex {
            switch buffer[index] {
            case 0x0A:
                return (index, 1)
            case 0x0D:
                return (index, 1)
            default:
                index = buffer.index(after: index)
            }
        }

        return nil
    }

    private mutating func process(
        _ originalLineData: Data,
        events: inout [SSEEvent]
    ) throws {
        var lineData = originalLineData

        if isFirstLine {
            isFirstLine = false
            if lineData.starts(with: [0xEF, 0xBB, 0xBF]) {
                lineData.removeFirst(3)
            }
        }

        guard let line = String(data: lineData, encoding: .utf8) else {
            throw PackagisError.malformedSSE("Invalid UTF-8 in event stream.")
        }

        if line.isEmpty {
            if let event = dispatchEvent() {
                events.append(event)
            }
            resetEvent()
            return
        }

        accumulatedEventBytes += lineData.count + 1
        accumulatedEventLines += 1
        guard
            accumulatedEventBytes <= maximumEventBytes,
            accumulatedEventLines <= maximumEventLines
        else {
            throw PackagisError.SSELimitExceeded
        }

        guard !line.hasPrefix(":") else {
            return
        }

        let field: Substring
        var value: Substring

        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.first == " " {
                value = value.dropFirst()
            }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "event":
            eventName = String(value)
        case "data":
            let stringValue = String(value)
            hasDataField = true
            dataLines.append(stringValue)
        case "id":
            if !value.contains("\0") {
                eventID = String(value)
            }
        case "retry":
            retryMilliseconds = Int(value)
        default:
            break
        }
    }

    private func dispatchEvent() -> SSEEvent? {
        guard hasDataField else {
            return nil
        }

        return SSEEvent(
            name: eventName,
            data: dataLines.joined(separator: "\n"),
            id: eventID,
            retryMilliseconds: retryMilliseconds
        )
    }

    private mutating func resetEvent() {
        eventName = nil
        dataLines.removeAll(keepingCapacity: true)
        retryMilliseconds = nil
        hasDataField = false
        accumulatedEventBytes = 0
        accumulatedEventLines = 0
    }
}
