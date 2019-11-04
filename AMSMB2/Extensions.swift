//
//  Extensions.swift
//  AMSMB2
//
//  Created by Amir Abbas Mousavian.
//  Copyright © 2018 Mousavian. Distributed under MIT license.
//

import Foundation
import SMB2

extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self = self else {
            throw POSIXError(.ENODATA, description: "Invalid/Empty data.")
        }
        return self
    }
}

extension Optional where Wrapped: SMB2Context {
     func unwrap() throws -> SMB2Context {
        guard let self = self, self.fileDescriptor >= 0 else {
            throw POSIXError(.ENOTCONN, description: "SMB2 server not connected.")
        }
        return self
    }
}

extension POSIXError {
    static func throwIfError(_ result: Int32, description: String?) throws {
        guard result < 0 else {
            return
        }
        let errno = -result
        let errorDesc = description.map { "Error code \(errno): \($0)" }
        throw POSIXError(.init(errno), description: errorDesc)
    }
    
    static func throwIfErrorStatus(_ status: UInt32) throws {
        if status & SMB2_STATUS_SEVERITY_MASK == SMB2_STATUS_SEVERITY_ERROR {
            let errorNo = nterror_to_errno(status)
            let description = nterror_to_str(status).map(String.init(cString:))
            try POSIXError.throwIfError(-errorNo, description: description)
        }
    }
    
    init(_ code: POSIXError.Code, description: String?) {
        let userInfo: [String: Any] = description.map({ [NSLocalizedFailureReasonErrorKey: $0] }) ?? [:]
        self = POSIXError(code, userInfo: userInfo)
    }
}

extension POSIXErrorCode {
    init(_ code: Int32) {
        self = POSIXErrorCode(rawValue: code) ?? .ECANCELED
    }
}

extension Dictionary where Key == URLResourceKey, Value == Any {
    var fileName: String? {
        return self[.nameKey] as? String
    }
    
    var filePath: String? {
        return self[.pathKey] as? String
    }
    
    var fileType: URLFileResourceType? {
        return self[.fileResourceTypeKey] as? URLFileResourceType
    }
    
    var fileSize: Int64? {
        return self[.fileSizeKey] as? Int64
    }
    
    var fileModificationDate: Date? {
        return self[.contentModificationDateKey] as? Date
    }
    
    var fileAccessDate: Date? {
        return self[.contentAccessDateKey] as? Date
    }
    
    var fileCreationDate: Date? {
        return self[.creationDateKey] as? Date
    }
}

extension Array where Element == [URLResourceKey: Any] {
    func sortedByName(_ comparison: ComparisonResult) -> [[URLResourceKey: Any]] {
        return sorted {
            guard let firstPath = $0.filePath, let secPath = $1.filePath else {
                return false
            }
            return firstPath.localizedStandardCompare(secPath) == comparison
        }
    }
    
    var overallSize: Int64 {
        return reduce(0, { (result, value) -> Int64 in
            if value.fileType  == URLFileResourceType.regular {
                return result + (value.fileSize ?? 0)
            } else {
                return result
            }
        })
    }
}

extension Array where Element == SMB2Share {
    func map(enumerateHidden: Bool) -> [(name: String, comment: String)] {
        var shares = self
        if enumerateHidden {
            shares = shares.filter { $0.props.type == .diskTree }
        } else {
            shares = shares.filter { !$0.props.isHidden && $0.props.type == .diskTree }
        }
        return shares.map { ($0.name, $0.comment) }
    }
}

extension Date {
    init(_ timespec: timespec) {
        self.init(timeIntervalSince1970: TimeInterval(timespec.tv_sec) + TimeInterval(timespec.tv_nsec / 1000) / TimeInterval(USEC_PER_SEC))
    }
}

extension Data {    
    mutating func append<T: FixedWidthInteger>(value: T) {
        var value = value.littleEndian
        let bytes = Swift.withUnsafeBytes(of: &value) { Array($0) }
        append(contentsOf: bytes)
    }
    
    mutating func append(value uuid: UUID) {
        // Microsoft GUID is mixed-endian
        append(contentsOf: [uuid.uuid.3,  uuid.uuid.2,  uuid.uuid.1,  uuid.uuid.0,
                            uuid.uuid.5,  uuid.uuid.4,  uuid.uuid.7,  uuid.uuid.6,
                            uuid.uuid.8,  uuid.uuid.9,  uuid.uuid.10, uuid.uuid.11,
                            uuid.uuid.12, uuid.uuid.13, uuid.uuid.14, uuid.uuid.15])
    }
    
    func scanValue<T: FixedWidthInteger>(offset: Int, as: T.Type) -> T? {
        guard count >= offset + MemoryLayout<T>.size else { return nil }
        return T(littleEndian: withUnsafeBytes { $0.load(fromByteOffset: offset, as: T.self) })
    }
    
    func scanInt<T: FixedWidthInteger>(offset: Int, as: T.Type) -> Int? {
        return scanValue(offset: offset, as: T.self).map(Int.init)
    }
}

extension String {
    var canonical: String {
        return trimmingCharacters(in: .init(charactersIn: "/\\"))
    }
}

extension Stream {
    func withOpenStream(_ handler: () throws -> Void) rethrows {
        let shouldCloseStream = streamStatus == .notOpen
        if streamStatus == .notOpen {
            open()
        }
        defer {
            if shouldCloseStream {
                close()
            }
        }
        try handler()
    }
}

extension InputStream {
    func readData(maxLength length: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: length)
        let result = read(&buffer, maxLength: buffer.count)
        if result < 0 {
            throw streamError ?? POSIXError(.EIO, description: "Unknown stream error.")
        } else {
            return Data(buffer.prefix(result))
        }
    }
}

extension OutputStream {
    func write<DataType: DataProtocol>(_ data: DataType) throws -> Int {
        var buffer = Array(data)
        let result = write(&buffer, maxLength: buffer.count)
        if result < 0 {
            throw streamError ?? POSIXError(.EIO, description: "Unknown stream error.")
        } else {
            return result
        }
    }
}
