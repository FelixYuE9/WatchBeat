import Foundation

struct WFDBSignalSpecification: Equatable {
    let dataFileName: String
    let format: Int
    let gainADCUnitsPerMillivolt: Double
    let baselineADCUnits: Int
    let name: String
}

struct WFDBRecordHeader: Equatable {
    let recordId: String
    let samplingFrequencyHz: Double
    let sampleCount: Int
    let signals: [WFDBSignalSpecification]
}

enum WFDB212Reader {
    static func parseHeader(_ text: String, expectedRecordId: String) throws -> WFDBRecordHeader {
        let lines = text
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let firstLine = lines.first else {
            throw BenchmarkToolError.invalidWFDB("header is empty")
        }
        let firstFields = firstLine.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard firstFields.count >= 4,
              firstFields[0] == expectedRecordId,
              let signalCount = Int(firstFields[1]), signalCount == 2,
              let samplingFrequencyHz = Double(firstFields[2].split(separator: "/").first ?? ""),
              samplingFrequencyHz.isFinite, samplingFrequencyHz > 0,
              let sampleCount = Int(firstFields[3]), sampleCount > 0 else {
            throw BenchmarkToolError.invalidWFDB(
                "record \(expectedRecordId) has an unsupported first header line"
            )
        }
        guard lines.count >= signalCount + 1 else {
            throw BenchmarkToolError.invalidWFDB(
                "record \(expectedRecordId) has fewer signal lines than declared"
            )
        }

        let signals = try lines[1...signalCount].enumerated().map { offset, line in
            let fields = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard fields.count >= 9 else {
                throw BenchmarkToolError.invalidWFDB(
                    "record \(expectedRecordId) signal \(offset) has too few fields"
                )
            }
            let dataFileName = fields[0]
            guard !dataFileName.contains("/"),
                  !dataFileName.contains("\\"),
                  !dataFileName.contains(".."),
                  !dataFileName.contains(":") else {
                throw BenchmarkToolError.invalidWFDB("unsafe WFDB data filename")
            }
            guard fields[1] == "212" else {
                throw BenchmarkToolError.invalidWFDB(
                    "record \(expectedRecordId) requires unsupported format \(fields[1])"
                )
            }
            let gainToken = fields[2].split(separator: "/").first.map(String.init) ?? fields[2]
            let gainNumber = gainToken.split(separator: "(").first.map(String.init) ?? gainToken
            guard let gain = Double(gainNumber), gain.isFinite, gain > 0,
                  let adcZero = Int(fields[4]) else {
                throw BenchmarkToolError.invalidWFDB(
                    "record \(expectedRecordId) signal \(offset) has invalid gain/baseline"
                )
            }
            let explicitBaseline: Int?
            if let open = fields[2].firstIndex(of: "("),
               let close = fields[2][open...].firstIndex(of: ")") {
                explicitBaseline = Int(fields[2][fields[2].index(after: open)..<close])
                guard explicitBaseline != nil else {
                    throw BenchmarkToolError.invalidWFDB("invalid explicit WFDB baseline")
                }
            } else {
                explicitBaseline = nil
            }
            return WFDBSignalSpecification(
                dataFileName: dataFileName,
                format: 212,
                gainADCUnitsPerMillivolt: gain,
                baselineADCUnits: explicitBaseline ?? adcZero,
                name: fields.dropFirst(8).joined(separator: " ")
            )
        }

        guard Set(signals.map(\.dataFileName)).count == 1 else {
            throw BenchmarkToolError.invalidWFDB(
                "record \(expectedRecordId) format 212 signals must share one data file"
            )
        }
        return WFDBRecordHeader(
            recordId: expectedRecordId,
            samplingFrequencyHz: samplingFrequencyHz,
            sampleCount: sampleCount,
            signals: signals
        )
    }

    static func readChannel(
        datasetDirectoryURL: URL,
        recordId: String,
        channelIndex: Int
    ) throws -> (header: WFDBRecordHeader, millivolts: [Double]) {
        let headerURL = datasetDirectoryURL.appendingPathComponent("\(recordId).hea")
        let headerText = try String(contentsOf: headerURL, encoding: .ascii)
        let header = try parseHeader(headerText, expectedRecordId: recordId)
        guard header.signals.indices.contains(channelIndex) else {
            throw BenchmarkToolError.invalidWFDB(
                "record \(recordId) has no channel \(channelIndex)"
            )
        }
        let signal = header.signals[channelIndex]
        let dataURL = datasetDirectoryURL.appendingPathComponent(signal.dataFileName)
        let data = try Data(contentsOf: dataURL, options: [.mappedIfSafe])
        return (
            header,
            try decodeChannel(
                data: data,
                sampleCount: header.sampleCount,
                channelIndex: channelIndex,
                gainADCUnitsPerMillivolt: signal.gainADCUnitsPerMillivolt,
                baselineADCUnits: signal.baselineADCUnits
            )
        )
    }

    static func decodeChannel(
        data: Data,
        sampleCount: Int,
        channelIndex: Int,
        gainADCUnitsPerMillivolt: Double,
        baselineADCUnits: Int
    ) throws -> [Double] {
        guard sampleCount > 0, sampleCount <= Int.max / 3,
              channelIndex == 0 || channelIndex == 1,
              gainADCUnitsPerMillivolt.isFinite,
              gainADCUnitsPerMillivolt > 0 else {
            throw BenchmarkToolError.invalidWFDB("invalid format 212 decode parameters")
        }
        let expectedByteCount = sampleCount * 3
        guard data.count == expectedByteCount else {
            throw BenchmarkToolError.invalidWFDB(
                "format 212 byte count \(data.count) does not equal expected \(expectedByteCount)"
            )
        }

        let bytes = [UInt8](data)
        var result = [Double]()
        result.reserveCapacity(sampleCount)
        for sampleIndex in 0..<sampleCount {
            let byteIndex = sampleIndex * 3
            let packed: Int
            if channelIndex == 0 {
                packed = Int(bytes[byteIndex]) | ((Int(bytes[byteIndex + 1]) & 0x0F) << 8)
            } else {
                packed = Int(bytes[byteIndex + 2]) | ((Int(bytes[byteIndex + 1]) & 0xF0) << 4)
            }
            let signed = packed >= 0x800 ? packed - 0x1000 : packed
            result.append(
                Double(signed - baselineADCUnits) / gainADCUnitsPerMillivolt
            )
        }
        return result
    }
}
