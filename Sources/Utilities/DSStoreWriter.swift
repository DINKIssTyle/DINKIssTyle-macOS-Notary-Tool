import Darwin
import Foundation

enum DSStoreWriterError: LocalizedError {
    case invalidStore(String)
    case layoutTooLarge(Int)
    case missingMetadata(String)
    case finderInfo(Int32)

    var errorDescription: String? {
        switch self {
        case let .invalidStore(reason):
            return "The generated .DS_Store is invalid: \(reason)"
        case let .layoutTooLarge(size):
            return "The generated Finder layout is \(size) bytes and does not fit in a .DS_Store leaf page."
        case let .missingMetadata(path):
            return "Required filesystem metadata could not be read for \(path)."
        case let .finderInfo(code):
            return "The volume custom-icon FinderInfo flag could not be written (errno \(code))."
        }
    }
}

/// Writes the minimal Finder metadata needed by a customized disk image.
///
/// The Buddy allocator/B-tree container and Alias Manager v2 serialization are
/// based on the reverse-engineered formats used by the MIT-licensed `ds_store`
/// and `mac_alias` projects. The implementation is intentionally write-once:
/// every generated layout fits in one sorted B-tree leaf.
enum DSStoreWriter {
    struct Layout: Equatable {
        var windowWidth: Int
        var windowHeight: Int
        var iconSize: Int
        var payloadName: String
        var payloadX: Int
        var payloadY: Int
        var includeApplicationsLink: Bool
        var applicationsX: Int
        var applicationsY: Int
        var backgroundFileName: String?
    }

    struct InspectedRecord: Equatable {
        let fileName: String
        let code: String
        let type: String
        let data: Data
    }

    private struct Record {
        let fileName: String
        let code: String
        let type: String
        let data: Data

        var encodedLength: Int {
            4 + fileName.utf16.count * 2 + 8 + (type == "blob" ? 4 : 0) + data.count
        }
    }

    private struct FreeBlock {
        var offset: UInt32
        var size: UInt32
    }

    private static let macEpochOffset: Int64 = 2_082_844_800

    static func write(to mountURL: URL, volumeName: String, layout: Layout) throws {
        let storeURL = mountURL.appendingPathComponent(".DS_Store")
        let records = try makeRecords(mountURL: mountURL, volumeName: volumeName, layout: layout)
        let store = try encodeStore(records: records)
        try store.write(to: storeURL, options: .atomic)

        let inspected = try inspect(store)
        guard inspected.count == records.count else {
            throw DSStoreWriterError.invalidStore("record count mismatch")
        }
    }

    static func setCustomVolumeIconFlag(at volumeURL: URL) throws {
        var finderInfo = Data(repeating: 0, count: 32)
        let attributeName = "com.apple.FinderInfo"

        let readResult: ssize_t = finderInfo.withUnsafeMutableBytes { bytes in
            attributeName.withCString { name in
                volumeURL.withUnsafeFileSystemRepresentation { path in
                    guard let path else { return -1 }
                    return getxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        if readResult >= 0, readResult < finderInfo.count {
            finderInfo.replaceSubrange(Int(readResult)..<finderInfo.count, with: repeatElement(0, count: finderInfo.count - Int(readResult)))
        }

        // Finder flag kHasCustomIcon (0x0400), stored as a big-endian UInt16.
        finderInfo[8] |= 0x04
        let writeResult: Int32 = finderInfo.withUnsafeBytes { bytes in
            attributeName.withCString { name in
                volumeURL.withUnsafeFileSystemRepresentation { path in
                    guard let path else { return -1 }
                    return setxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        guard writeResult == 0 else {
            throw DSStoreWriterError.finderInfo(errno)
        }
    }

    static func hasCustomVolumeIconFlag(at volumeURL: URL) -> Bool {
        var finderInfo = Data(repeating: 0, count: 32)
        let result: ssize_t = finderInfo.withUnsafeMutableBytes { bytes in
            "com.apple.FinderInfo".withCString { name in
                volumeURL.withUnsafeFileSystemRepresentation { path in
                    guard let path else { return -1 }
                    return getxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        return result >= 10 && finderInfo[8] & 0x04 != 0
    }

    static func verify(at mountURL: URL, layout: Layout, requiresVolumeIcon: Bool) throws {
        let fileManager = FileManager.default
        let storeURL = mountURL.appendingPathComponent(".DS_Store")
        let records = try inspect(Data(contentsOf: storeURL))
        let keys = Set(records.map { "\($0.fileName)|\($0.code)" })

        for key in [".|bwsp", ".|icvp", ".|icvl", ".|vSrn", "\(layout.payloadName)|Iloc"] {
            guard keys.contains(key) else {
                throw DSStoreWriterError.invalidStore("missing \(key) record")
            }
        }
        guard let browserRecord = records.first(where: { $0.fileName == "." && $0.code == "bwsp" }),
              let browserSettings = try PropertyListSerialization.propertyList(from: browserRecord.data, format: nil) as? [String: Any],
              browserSettings["WindowBounds"] as? String == "{{100, 100}, {\(layout.windowWidth), \(layout.windowHeight)}}" else {
            throw DSStoreWriterError.invalidStore("incorrect Finder window size")
        }
        guard let iconViewRecord = records.first(where: { $0.fileName == "." && $0.code == "icvp" }),
              let iconViewSettings = try PropertyListSerialization.propertyList(from: iconViewRecord.data, format: nil) as? [String: Any],
              (iconViewSettings["iconSize"] as? NSNumber)?.intValue == layout.iconSize else {
            throw DSStoreWriterError.invalidStore("incorrect Finder icon size")
        }
        guard records.first(where: { $0.fileName == layout.payloadName && $0.code == "Iloc" })?.data
                == iconLocation(x: layout.payloadX, y: layout.payloadY) else {
            throw DSStoreWriterError.invalidStore("incorrect payload icon location")
        }
        if layout.includeApplicationsLink {
            guard keys.contains("Applications|Iloc") else {
                throw DSStoreWriterError.invalidStore("missing Applications icon location")
            }
            guard records.first(where: { $0.fileName == "Applications" && $0.code == "Iloc" })?.data
                    == iconLocation(x: layout.applicationsX, y: layout.applicationsY) else {
                throw DSStoreWriterError.invalidStore("incorrect Applications icon location")
            }
            guard fileManager.fileExists(atPath: mountURL.appendingPathComponent("Applications").path) else {
                throw DSStoreWriterError.invalidStore("missing Applications shortcut")
            }
        }
        guard fileManager.fileExists(atPath: mountURL.appendingPathComponent(layout.payloadName).path) else {
            throw DSStoreWriterError.invalidStore("missing payload")
        }
        if let backgroundFileName = layout.backgroundFileName {
            let backgroundURL = mountURL
                .appendingPathComponent(".background", isDirectory: true)
                .appendingPathComponent(backgroundFileName)
            guard fileManager.fileExists(atPath: backgroundURL.path) else {
                throw DSStoreWriterError.invalidStore("missing background asset")
            }
            guard (iconViewSettings["backgroundType"] as? NSNumber)?.intValue == 2,
                  iconViewSettings["backgroundImageAlias"] is Data else {
                throw DSStoreWriterError.invalidStore("missing background alias")
            }
        }
        if requiresVolumeIcon {
            guard fileManager.fileExists(atPath: mountURL.appendingPathComponent(".VolumeIcon.icns").path) else {
                throw DSStoreWriterError.invalidStore("missing volume icon")
            }
            guard hasCustomVolumeIconFlag(at: mountURL) else {
                throw DSStoreWriterError.invalidStore("missing volume custom-icon flag")
            }
        }
    }

    static func inspect(_ data: Data) throws -> [InspectedRecord] {
        guard data.count >= 36,
              try data.readUInt32BE(at: 0) == 1,
              String(data: data[4..<8], encoding: .ascii) == "Bud1" else {
            throw DSStoreWriterError.invalidStore("bad Buddy header")
        }

        let rootOffset = Int(try data.readUInt32BE(at: 8)) + 4
        let offsetCount = Int(try data.readUInt32BE(at: rootOffset))
        guard offsetCount >= 3 else {
            throw DSStoreWriterError.invalidStore("missing allocator blocks")
        }
        var offsets: [UInt32] = []
        for index in 0..<offsetCount {
            offsets.append(try data.readUInt32BE(at: rootOffset + 8 + index * 4))
        }

        let tocOffset = rootOffset + 8 + ((offsetCount + 255) & ~255) * 4
        let tocCount = Int(try data.readUInt32BE(at: tocOffset))
        var cursor = tocOffset + 4
        var dsdbIndex: Int?
        for _ in 0..<tocCount {
            let nameLength = Int(try data.readUInt8(at: cursor))
            cursor += 1
            let name = try data.readASCII(at: cursor, count: nameLength)
            cursor += nameLength
            let index = Int(try data.readUInt32BE(at: cursor))
            cursor += 4
            if name == "DSDB" { dsdbIndex = index }
        }
        guard let dsdbIndex, offsets.indices.contains(dsdbIndex) else {
            throw DSStoreWriterError.invalidStore("missing DSDB topic")
        }

        let dsdbOffset = Int(blockOffset(offsets[dsdbIndex])) + 4
        let leafIndex = Int(try data.readUInt32BE(at: dsdbOffset))
        let expectedCount = Int(try data.readUInt32BE(at: dsdbOffset + 8))
        guard offsets.indices.contains(leafIndex) else {
            throw DSStoreWriterError.invalidStore("invalid leaf index")
        }

        cursor = Int(blockOffset(offsets[leafIndex])) + 4
        let nextNode = try data.readUInt32BE(at: cursor)
        let recordCount = Int(try data.readUInt32BE(at: cursor + 4))
        cursor += 8
        guard nextNode == 0, recordCount == expectedCount else {
            throw DSStoreWriterError.invalidStore("unexpected B-tree shape")
        }

        var records: [InspectedRecord] = []
        for _ in 0..<recordCount {
            let nameLength = Int(try data.readUInt32BE(at: cursor))
            cursor += 4
            let fileName = try data.readUTF16BE(at: cursor, codeUnitCount: nameLength)
            cursor += nameLength * 2
            let code = try data.readASCII(at: cursor, count: 4)
            cursor += 4
            let type = try data.readASCII(at: cursor, count: 4)
            cursor += 4

            let value: Data
            switch type {
            case "blob", "ustr":
                let length = Int(try data.readUInt32BE(at: cursor))
                cursor += 4
                value = try data.slice(at: cursor, count: type == "ustr" ? length * 2 : length)
                cursor += value.count
            case "bool":
                value = try data.slice(at: cursor, count: 1)
                cursor += 1
            case "long", "shor", "type":
                value = try data.slice(at: cursor, count: 4)
                cursor += 4
            case "comp", "dutc":
                value = try data.slice(at: cursor, count: 8)
                cursor += 8
            default:
                throw DSStoreWriterError.invalidStore("unsupported record type \(type)")
            }
            records.append(InspectedRecord(fileName: fileName, code: code, type: type, data: value))
        }
        return records
    }

    private static func makeRecords(mountURL: URL, volumeName: String, layout: Layout) throws -> [Record] {
        let bounds = "{{100, 100}, {\(layout.windowWidth), \(layout.windowHeight)}}"
        let browserSettings: [String: Any] = [
            "ShowStatusBar": false,
            "WindowBounds": bounds,
            "ContainerShowSidebar": false,
            "PreviewPaneVisibility": false,
            "SidebarWidth": 0,
            "ShowTabView": false,
            "ShowToolbar": false,
            "ShowPathbar": false,
            "ShowSidebar": false
        ]

        var iconViewSettings: [String: Any] = [
            "viewOptionsVersion": 1,
            "backgroundType": 0,
            "backgroundColorRed": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "arrangeBy": "none",
            "showIconPreview": true,
            "showItemInfo": false,
            "labelOnBottom": true,
            "textSize": 12.0,
            "iconSize": Double(layout.iconSize),
            "scrollPositionX": 0.0,
            "scrollPositionY": 0.0
        ]

        var records: [Record] = []
        if let backgroundFileName = layout.backgroundFileName {
            let backgroundDirectory = mountURL.appendingPathComponent(".background", isDirectory: true)
            let backgroundURL = backgroundDirectory.appendingPathComponent(backgroundFileName)
            let fileMetadata = try metadata(at: backgroundURL)
            let directoryMetadata = try metadata(at: backgroundDirectory)
            let volumeMetadata = try metadata(at: mountURL)
            let alias = backgroundAlias(
                volumeName: volumeName,
                folderName: ".background",
                fileName: backgroundFileName,
                volumeCreationDate: volumeMetadata.creationDate,
                fileCreationDate: fileMetadata.creationDate,
                folderID: directoryMetadata.fileID,
                fileID: fileMetadata.fileID
            )
            iconViewSettings["backgroundType"] = 2
            iconViewSettings["backgroundImageAlias"] = alias
            records.append(blobRecord(fileName: ".background", code: "Iloc", data: iconLocation(x: layout.applicationsX, y: layout.windowHeight + 300)))
        }

        let bwsp = try PropertyListSerialization.data(fromPropertyList: browserSettings, format: .binary, options: 0)
        let icvp = try PropertyListSerialization.data(fromPropertyList: iconViewSettings, format: .binary, options: 0)
        records.append(blobRecord(fileName: ".", code: "bwsp", data: bwsp))
        records.append(blobRecord(fileName: ".", code: "icvp", data: icvp))
        records.append(Record(fileName: ".", code: "icvl", type: "type", data: Data("icnv".utf8)))
        records.append(Record(fileName: ".", code: "vSrn", type: "long", data: Data([0, 0, 0, 1])))
        records.append(blobRecord(fileName: layout.payloadName, code: "Iloc", data: iconLocation(x: layout.payloadX, y: layout.payloadY)))
        if layout.includeApplicationsLink {
            records.append(blobRecord(fileName: "Applications", code: "Iloc", data: iconLocation(x: layout.applicationsX, y: layout.applicationsY)))
        }

        return records.sorted {
            let lhsName = $0.fileName.lowercased()
            let rhsName = $1.fileName.lowercased()
            return lhsName == rhsName ? $0.code < $1.code : lhsName < rhsName
        }
    }

    private static func metadata(at url: URL) throws -> (fileID: UInt32, creationDate: Date) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileNumber = attributes[.systemFileNumber] as? NSNumber,
              let creationDate = attributes[.creationDate] as? Date else {
            throw DSStoreWriterError.missingMetadata(url.path)
        }
        return (fileNumber.uint32Value, creationDate)
    }

    private static func blobRecord(fileName: String, code: String, data: Data) -> Record {
        Record(fileName: fileName, code: code, type: "blob", data: data)
    }

    private static func iconLocation(x: Int, y: Int) -> Data {
        var data = Data()
        data.appendUInt32BE(UInt32(clamping: x))
        data.appendUInt32BE(UInt32(clamping: y))
        data.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00])
        return data
    }

    private static func encodeStore(records: [Record]) throws -> Data {
        var leaf = Data()
        leaf.appendUInt32BE(0)
        leaf.appendUInt32BE(UInt32(records.count))
        for record in records {
            let name = record.fileName.data(using: .utf16BigEndian) ?? Data()
            leaf.appendUInt32BE(UInt32(name.count / 2))
            leaf.append(name)
            leaf.append(fourCharacterData(record.code))
            leaf.append(fourCharacterData(record.type))
            if record.type == "blob" || record.type == "ustr" {
                leaf.appendUInt32BE(UInt32(record.type == "ustr" ? record.data.count / 2 : record.data.count))
            }
            leaf.append(record.data)
        }
        guard leaf.count <= 4096 else {
            throw DSStoreWriterError.layoutTooLarge(leaf.count)
        }
        leaf.append(contentsOf: repeatElement(0, count: 4096 - leaf.count))

        var dsdb = Data()
        dsdb.appendUInt32BE(2)
        dsdb.appendUInt32BE(0)
        dsdb.appendUInt32BE(UInt32(records.count))
        dsdb.appendUInt32BE(1)
        dsdb.appendUInt32BE(4096)
        dsdb = padded(dsdb, minimum: 32)

        var freeBlocks = (5..<31).map { FreeBlock(offset: UInt32(1) << UInt32($0), size: UInt32(1) << UInt32($0)) }
        let preliminaryRoot = rootBlock(rootAddress: 0, dsdbAddress: 0, leafAddress: 0, freeBlocks: freeBlocks)
        let rootCapacity = nextPowerOfTwo(max(32, preliminaryRoot.count))

        let leafAddress = allocate(size: 4096, from: &freeBlocks)
        let dsdbAddress = allocate(size: dsdb.count, from: &freeBlocks)
        let rootAddress = allocate(size: rootCapacity, from: &freeBlocks)
        let root = rootBlock(rootAddress: rootAddress, dsdbAddress: dsdbAddress, leafAddress: leafAddress, freeBlocks: freeBlocks)
        guard root.count <= rootCapacity else {
            throw DSStoreWriterError.invalidStore("allocator root overflow")
        }

        let rootOffset = Int(blockOffset(rootAddress))
        let dsdbOffset = Int(blockOffset(dsdbAddress))
        let leafOffset = Int(blockOffset(leafAddress))
        let fileSize = max(rootOffset + rootCapacity, dsdbOffset + dsdb.count, leafOffset + leaf.count) + 4
        var result = Data(repeating: 0, count: fileSize)

        var header = Data()
        header.appendUInt32BE(1)
        header.append(Data("Bud1".utf8))
        header.appendUInt32BE(UInt32(rootOffset))
        header.appendUInt32BE(UInt32(root.count))
        header.appendUInt32BE(UInt32(rootOffset))
        header.append(Data(repeating: 0, count: 16))
        result.replaceSubrange(0..<header.count, with: header)
        result.replaceSubrange((4 + rootOffset)..<(4 + rootOffset + root.count), with: root)
        result.replaceSubrange((4 + dsdbOffset)..<(4 + dsdbOffset + dsdb.count), with: dsdb)
        result.replaceSubrange((4 + leafOffset)..<(4 + leafOffset + leaf.count), with: leaf)
        return result
    }

    private static func rootBlock(rootAddress: UInt32, dsdbAddress: UInt32, leafAddress: UInt32, freeBlocks: [FreeBlock]) -> Data {
        var data = Data()
        data.appendUInt32BE(3)
        data.appendUInt32BE(0)
        data.appendUInt32BE(rootAddress)
        data.appendUInt32BE(dsdbAddress)
        data.appendUInt32BE(leafAddress)
        data.append(Data(repeating: 0, count: 253 * 4))
        data.appendUInt32BE(1)
        data.append(4)
        data.append(Data("DSDB".utf8))
        data.appendUInt32BE(1)

        let sorted = freeBlocks.sorted { $0.size == $1.size ? $0.offset < $1.offset : $0.size < $1.size }
        for width in 0..<32 {
            let blockSize = UInt32(1) << UInt32(width)
            let matching = sorted.filter { block in
                let powerOfTwo = block.size > 0 && block.size & (block.size - 1) == 0
                return block.size == blockSize || (block.size > blockSize && !powerOfTwo)
            }
            data.appendUInt32BE(UInt32(matching.count))
            matching.forEach { data.appendUInt32BE($0.offset) }
        }
        return data
    }

    private static func allocate(size: Int, from freeBlocks: inout [FreeBlock]) -> UInt32 {
        let capacity = UInt32(nextPowerOfTwo(max(32, size)))
        let width = UInt32(capacity.trailingZeroBitCount)
        freeBlocks.sort { $0.size == $1.size ? $0.offset < $1.offset : $0.size < $1.size }
        let index = freeBlocks.firstIndex { $0.size >= capacity }!
        let block = freeBlocks.remove(at: index)
        if block.size > capacity {
            freeBlocks.append(FreeBlock(offset: block.offset + capacity, size: block.size - capacity))
        }
        return block.offset | width
    }

    private static func padded(_ data: Data, minimum: Int) -> Data {
        var result = data
        let capacity = nextPowerOfTwo(max(minimum, result.count))
        result.append(contentsOf: repeatElement(0, count: capacity - result.count))
        return result
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int {
        guard value > 1 else { return 1 }
        return 1 << (Int.bitWidth - (value - 1).leadingZeroBitCount)
    }

    private static func blockOffset(_ address: UInt32) -> UInt32 {
        address & ~UInt32(0x1f)
    }

    private static func fourCharacterData(_ string: String) -> Data {
        var bytes = Array(string.utf8.prefix(4))
        bytes.append(contentsOf: repeatElement(0, count: max(0, 4 - bytes.count)))
        return Data(bytes)
    }

    private static func backgroundAlias(
        volumeName: String,
        folderName: String,
        fileName: String,
        volumeCreationDate: Date,
        fileCreationDate: Date,
        folderID: UInt32,
        fileID: UInt32
    ) -> Data {
        let volumeSeconds = UInt32(clamping: Int64(volumeCreationDate.timeIntervalSince1970) + macEpochOffset)
        let fileSeconds = UInt32(clamping: Int64(fileCreationDate.timeIntervalSince1970) + macEpochOffset)
        var body = Data()
        body.appendUInt16BE(0)
        body.appendPascalString(volumeName, totalLength: 28)
        body.appendUInt32BE(volumeSeconds)
        body.append(Data("H+".utf8))
        body.appendUInt16BE(5)
        body.appendUInt32BE(folderID)
        body.appendPascalString(fileName, totalLength: 64)
        body.appendUInt32BE(fileID)
        body.appendUInt32BE(fileSeconds)
        body.append(Data(repeating: 0, count: 8))
        body.appendUInt16BE(UInt16.max)
        body.appendUInt16BE(UInt16.max)
        body.appendUInt32BE(0)
        body.appendUInt16BE(0)
        body.append(Data(repeating: 0, count: 10))

        body.appendAliasTag(0, data: Data(folderName.utf8))
        var volumeHighResolution = Data()
        volumeHighResolution.appendUInt64BE(UInt64(volumeSeconds) * 65_536)
        body.appendAliasTag(16, data: volumeHighResolution)
        var fileHighResolution = Data()
        fileHighResolution.appendUInt64BE(UInt64(fileSeconds) * 65_536)
        body.appendAliasTag(17, data: fileHighResolution)
        var catalogPath = Data()
        catalogPath.appendUInt32BE(folderID)
        body.appendAliasTag(1, data: catalogPath)
        body.appendAliasTag(2, data: Data("\(volumeName):\(folderName):\0\(fileName)".utf8))

        var unicodeFileName = Data()
        let unicodeFileNameData = fileName.data(using: .utf16BigEndian) ?? Data()
        unicodeFileName.appendUInt16BE(UInt16(unicodeFileNameData.count / 2))
        unicodeFileName.append(unicodeFileNameData)
        body.appendAliasTag(14, data: unicodeFileName)

        var unicodeVolumeName = Data()
        let unicodeVolumeNameData = volumeName.data(using: .utf16BigEndian) ?? Data()
        unicodeVolumeName.appendUInt16BE(UInt16(unicodeVolumeNameData.count / 2))
        unicodeVolumeName.append(unicodeVolumeNameData)
        body.appendAliasTag(15, data: unicodeVolumeName)
        body.appendAliasTag(18, data: Data("/\(folderName)/\(fileName)".utf8))
        body.appendAliasTag(19, data: Data("/Volumes/\(volumeName)".utf8))
        body.appendUInt16BE(UInt16.max)
        body.appendUInt16BE(0)

        var alias = Data(repeating: 0, count: 4)
        alias.appendUInt16BE(UInt16(8 + body.count))
        alias.appendUInt16BE(2)
        alias.append(body)
        return alias
    }
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendPascalString(_ string: String, totalLength: Int) {
        let source = Array(string.utf8.prefix(Swift.max(0, totalLength - 1)))
        append(UInt8(source.count))
        append(contentsOf: source)
        append(contentsOf: repeatElement(0, count: totalLength - source.count - 1))
    }

    mutating func appendAliasTag(_ tag: UInt16, data: Data) {
        appendUInt16BE(tag)
        appendUInt16BE(UInt16(clamping: data.count))
        append(data)
        if data.count.isMultiple(of: 2) == false { append(0) }
    }

    func readUInt8(at offset: Int) throws -> UInt8 {
        guard indices.contains(offset) else { throw DSStoreWriterError.invalidStore("truncated byte") }
        return self[offset]
    }

    func readUInt32BE(at offset: Int) throws -> UInt32 {
        let bytes = try slice(at: offset, count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func readASCII(at offset: Int, count: Int) throws -> String {
        guard let value = String(data: try slice(at: offset, count: count), encoding: .ascii) else {
            throw DSStoreWriterError.invalidStore("invalid ASCII field")
        }
        return value
    }

    func readUTF16BE(at offset: Int, codeUnitCount: Int) throws -> String {
        guard let value = String(data: try slice(at: offset, count: codeUnitCount * 2), encoding: .utf16BigEndian) else {
            throw DSStoreWriterError.invalidStore("invalid UTF-16 filename")
        }
        return value
    }

    func slice(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= self.count, count <= self.count - offset else {
            throw DSStoreWriterError.invalidStore("truncated data")
        }
        return self[offset..<(offset + count)]
    }
}
