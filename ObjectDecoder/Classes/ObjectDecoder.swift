//
//  ObjectDecoder.swift

//  ObjectDecoder
//
//  Created by Lucas Best on 12/5/17.
//

// swiftlint:disable todo

//Heavily references: https://github.com/apple/swift-corelibs-foundation/blob/master/Foundation/JSONEncoder.swift

// NOTE: This value is implicitly lazy and _must_ be lazy. We're compiled against the latest SDK (w/ ISO8601DateFormatter), but linked against whichever Foundation the user has. ISO8601DateFormatter might not exist, so we better not hit this code path on an older OS.
@available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
fileprivate var _iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    return formatter
}()

public typealias DateDecodingStrategy = JSONDecoder.DateDecodingStrategy
public typealias DataDecodingStrategy = JSONDecoder.DataDecodingStrategy
public typealias NonConformingFloatDecodingStrategy = JSONDecoder.NonConformingFloatDecodingStrategy

public class ObjectDecoder {
    /// The strategy to use in decoding dates. Defaults to `.deferredToDate`.
    open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate

    /// The strategy to use in decoding binary data. Defaults to `.base64`.
    open var dataDecodingStrategy: DataDecodingStrategy = .base64

    /// The strategy to use in decoding non-conforming numbers. Defaults to `.throw`.
    open var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw

    /// Contextual user-provided information for use during decoding.
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Initializes `self` with default strategies.
    public init() {}

    /// Options set on the top-level encoder to pass down the decoding hierarchy.
    fileprivate struct _Options {
        let dateDecodingStrategy: DateDecodingStrategy
        let dataDecodingStrategy: DataDecodingStrategy
        let nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }

    /// The options set on the top-level decoder.
    fileprivate var options: _Options {
        return _Options(dateDecodingStrategy: dateDecodingStrategy,
                        dataDecodingStrategy: dataDecodingStrategy,
                        nonConformingFloatDecodingStrategy: nonConformingFloatDecodingStrategy,
                        userInfo: userInfo)
    }

    // MARK: - Decoding Values

    /// - parameter type: The type of the value to decode.
    /// - parameter object: the structure to decode.
    /// - returns: A value of the requested type.
    /// - throws: `DecodingError.dataCorrupted` if values requested from the payload are corrupted.
    /// - throws: An error if any value throws an error during decoding.
    open func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let decoder = _ObjectDecoder(referencing: object, options: self.options)
        return try T(from: decoder)
    }
}

private class _ObjectDecoder: Decoder {
    var userInfo: [CodingUserInfoKey: Any] = [:]
    private(set) var codingPath: [CodingKey]

    fileprivate var storage: _ObjectDecodingStorage

    /// Options set on the top-level decoder.
    fileprivate let options: ObjectDecoder._Options

    init(referencing container: Any, at codingPath: [CodingKey] = [], options: ObjectDecoder._Options) {
        self.storage = _ObjectDecodingStorage()
        self.storage.push(container: container)
        self.codingPath = codingPath
        self.options = options
    }

    /// Performs the given closure with the given key pushed onto the end of the current coding path.
    ///
    /// - parameter key: The key to push. May be nil for unkeyed containers.
    /// - parameter work: The work to perform with the key in the path.
    fileprivate func with<T>(pushedKey key: CodingKey, _ work: () throws -> T) rethrows -> T {
        self.codingPath.append(key)
        let ret: T = try work()
        self.codingPath.removeLast()
        return ret
    }

    // MARK: - Decoder

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard !(self.storage.topContainer is NSNull) else {
            throw DecodingError.valueNotFound(KeyedDecodingContainer<Key>.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Cannot get keyed decoding container -- found null value instead."))
        }

        guard let topContainer = self.storage.topContainer as? [String: Any] else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: [String: Any].self, reality: self.storage.topContainer)
        }

        let container = _ObjectKeyedDecodingContainer<Key>(referencing: self, wrapping: topContainer)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !(self.storage.topContainer is NSNull) else {
            throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Cannot get unkeyed decoding container -- found null value instead."))
        }

        guard let topContainer = self.storage.topContainer as? [Any] else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: [Any].self, reality: self.storage.topContainer)
        }

        return _ObjectUnkeyedDecodingContainer(referencing: self, wrapping: topContainer)
    }

    public func singleValueContainer() throws -> SingleValueDecodingContainer {
        return self
    }
}

private struct _ObjectDecodingStorage {
    /// The container stack.
    /// Elements may be any one of the following types (NSNull, NSNumber, String, Array, [String : Any]).
    private(set) fileprivate var containers: [Any] = []

    fileprivate init() {}

    fileprivate var count: Int {
        return self.containers.count
    }

    fileprivate var topContainer: Any {
        precondition(self.containers.count > 0, "Empty container stack.")
        return self.containers.last!
    }

    fileprivate mutating func push(container: Any) {
        self.containers.append(container)
    }

    fileprivate mutating func popContainer() {
        precondition(self.containers.count > 0, "Empty container stack.")
        self.containers.removeLast()
    }
}

private struct _ObjectKeyedDecodingContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Key = K

    private let decoder: _ObjectDecoder

    /// A reference to the container we're reading from.
    private let container: [String: Any]

    /// The path of coding keys taken to get to this point in decoding.
    private(set) public var codingPath: [CodingKey]

    /// Initializes `self` by referencing the given decoder and container.
    init(referencing decoder: _ObjectDecoder, wrapping container: [String: Any]) {
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
    }

    // MARK: - KeyedDecodingContainerProtocol

    public var allKeys: [Key] {
        return self.container.keys.compactMap { Key(stringValue: $0) }
    }

    public func contains(_ key: Key) -> Bool {
        return self.container[key.stringValue] != nil
    }

    public func decodeNil(forKey key: Key) throws -> Bool {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return entry is NSNull
    }

    public func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Bool.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Int.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Int8.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Int16.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Int32.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Int64.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: UInt.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: UInt8.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: UInt16.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: UInt32.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: UInt64.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Float.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: Double.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode(_ type: String.Type, forKey key: Key) throws -> String {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: String.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }

        return try self.decoder.with(pushedKey: key) {
            guard let value = try self.decoder.unbox(entry, as: T.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }

            return value
        }
    }

    public func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        return try self.decoder.with(pushedKey: key) {
            guard let value = self.container[key.stringValue] else {
                throw DecodingError.keyNotFound(key,
                                                DecodingError.Context(codingPath: self.codingPath,
                                                                      debugDescription: "Cannot get \(KeyedDecodingContainer<NestedKey>.self) -- no value found for key \"\(key.stringValue)\""))
            }

            guard let dictionary = value as? [String: Any] else {
                throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: [String: Any].self, reality: value)
            }

            let container = _ObjectKeyedDecodingContainer<NestedKey>(referencing: self.decoder, wrapping: dictionary)
            return KeyedDecodingContainer(container)
        }
    }

    public func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        return try self.decoder.with(pushedKey: key) {
            guard let value = self.container[key.stringValue] else {
                throw DecodingError.keyNotFound(key,
                                                DecodingError.Context(codingPath: self.codingPath,
                                                                      debugDescription: "Cannot get UnkeyedDecodingContainer -- no value found for key \"\(key.stringValue)\""))
            }

            guard let array = value as? [Any] else {
                throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: [Any].self, reality: value)
            }

            return _ObjectUnkeyedDecodingContainer(referencing: self.decoder, wrapping: array)
        }
    }

    private func _superDecoder(forKey key: CodingKey) throws -> Decoder {
        return self.decoder.with(pushedKey: key) {
            let value: Any = self.container[key.stringValue] ?? NSNull()
            return _ObjectDecoder(referencing: value, at: self.decoder.codingPath, options: self.decoder.options)
        }
    }

    public func superDecoder() throws -> Decoder {
        return try _superDecoder(forKey: _ObjectKey.super)
    }

    public func superDecoder(forKey key: Key) throws -> Decoder {
        return try _superDecoder(forKey: key)
    }
}

private struct _ObjectUnkeyedDecodingContainer: UnkeyedDecodingContainer {

    private let decoder: _ObjectDecoder

    private let container: [Any]

    private(set) public var codingPath: [CodingKey]

    private(set) public var currentIndex: Int

    fileprivate init(referencing decoder: _ObjectDecoder, wrapping container: [Any]) {
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
        self.currentIndex = 0
    }

    // MARK: - UnkeyedDecodingContainer

    public var count: Int? {
        return self.container.count
    }

    public var isAtEnd: Bool {
        return self.currentIndex >= self.count!
    }

    public mutating func decodeNil() throws -> Bool {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(Any?.self, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        if self.container[self.currentIndex] is NSNull {
            self.currentIndex += 1
            return true
        } else {
            return false
        }
    }

    public mutating func decode(_ type: Bool.Type) throws -> Bool {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Bool.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: Int.Type) throws -> Int {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: Int8.Type) throws -> Int8 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int8.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: Int16.Type) throws -> Int16 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int16.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: Int32.Type) throws -> Int32 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int32.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: Int64.Type) throws -> Int64 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int64.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: UInt.Type) throws -> UInt {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt8.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt16.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt32.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt64.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: Float.Type) throws -> Float {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Float.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: Double.Type) throws -> Double {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Double.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode(_ type: String.Type) throws -> String {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: String.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }

        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: T.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_ObjectKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }

            self.currentIndex += 1
            return decoded
        }
    }

    public mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(KeyedDecodingContainer<NestedKey>.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get nested keyed container -- unkeyed container is at end."))
            }

            let value = self.container[self.currentIndex]
            guard !(value is NSNull) else {
                throw DecodingError.valueNotFound(KeyedDecodingContainer<NestedKey>.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get keyed decoding container -- found null value instead."))
            }

            guard let dictionary = value as? [String: Any] else {
                throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: [String: Any].self, reality: value)
            }

            self.currentIndex += 1
            let container = _ObjectKeyedDecodingContainer<NestedKey>(referencing: self.decoder, wrapping: dictionary)
            return KeyedDecodingContainer(container)
        }
    }

    public mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get nested keyed container -- unkeyed container is at end."))
            }

            let value = self.container[self.currentIndex]
            guard !(value is NSNull) else {
                throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get keyed decoding container -- found null value instead."))
            }

            guard let array = value as? [Any] else {
                throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: [Any].self, reality: value)
            }

            self.currentIndex += 1
            return _ObjectUnkeyedDecodingContainer(referencing: self.decoder, wrapping: array)
        }
    }

    public mutating func superDecoder() throws -> Decoder {
        return try self.decoder.with(pushedKey: _ObjectKey(index: self.currentIndex)) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(Decoder.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get superDecoder() -- unkeyed container is at end."))
            }

            let value = self.container[self.currentIndex]
            self.currentIndex += 1
            return _ObjectDecoder(referencing: value, at: self.decoder.codingPath, options: self.decoder.options)
        }
    }
}

extension _ObjectDecoder: SingleValueDecodingContainer {

    private func expectNonNull<T>(_ type: T.Type) throws {
        guard !self.decodeNil() else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Expected \(type) but found null value instead."))
        }
    }

    public func decodeNil() -> Bool {
        return self.storage.topContainer is NSNull
    }

    public func decode(_ type: Bool.Type) throws -> Bool {
        try expectNonNull(Bool.self)
        return try self.unbox(self.storage.topContainer, as: Bool.self)!
    }

    public func decode(_ type: Int.Type) throws -> Int {
        try expectNonNull(Int.self)
        return try self.unbox(self.storage.topContainer, as: Int.self)!
    }

    public func decode(_ type: Int8.Type) throws -> Int8 {
        try expectNonNull(Int8.self)
        return try self.unbox(self.storage.topContainer, as: Int8.self)!
    }

    public func decode(_ type: Int16.Type) throws -> Int16 {
        try expectNonNull(Int16.self)
        return try self.unbox(self.storage.topContainer, as: Int16.self)!
    }

    public func decode(_ type: Int32.Type) throws -> Int32 {
        try expectNonNull(Int32.self)
        return try self.unbox(self.storage.topContainer, as: Int32.self)!
    }

    public func decode(_ type: Int64.Type) throws -> Int64 {
        try expectNonNull(Int64.self)
        return try self.unbox(self.storage.topContainer, as: Int64.self)!
    }

    public func decode(_ type: UInt.Type) throws -> UInt {
        try expectNonNull(UInt.self)
        return try self.unbox(self.storage.topContainer, as: UInt.self)!
    }

    public func decode(_ type: UInt8.Type) throws -> UInt8 {
        try expectNonNull(UInt8.self)
        return try self.unbox(self.storage.topContainer, as: UInt8.self)!
    }

    public func decode(_ type: UInt16.Type) throws -> UInt16 {
        try expectNonNull(UInt16.self)
        return try self.unbox(self.storage.topContainer, as: UInt16.self)!
    }

    public func decode(_ type: UInt32.Type) throws -> UInt32 {
        try expectNonNull(UInt32.self)
        return try self.unbox(self.storage.topContainer, as: UInt32.self)!
    }

    public func decode(_ type: UInt64.Type) throws -> UInt64 {
        try expectNonNull(UInt64.self)
        return try self.unbox(self.storage.topContainer, as: UInt64.self)!
    }

    public func decode(_ type: Float.Type) throws -> Float {
        try expectNonNull(Float.self)
        return try self.unbox(self.storage.topContainer, as: Float.self)!
    }

    public func decode(_ type: Double.Type) throws -> Double {
        try expectNonNull(Double.self)
        return try self.unbox(self.storage.topContainer, as: Double.self)!
    }

    public func decode(_ type: String.Type) throws -> String {
        try expectNonNull(String.self)
        return try self.unbox(self.storage.topContainer, as: String.self)!
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try expectNonNull(T.self)
        return try self.unbox(self.storage.topContainer, as: T.self)!
    }
}

extension _ObjectDecoder {

    fileprivate func unbox(_ value: Any, as type: Bool.Type) throws -> Bool? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        return number.boolValue
    }

    fileprivate func unbox(_ value: Any, as type: Int.Type) throws -> Int? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let int = number.intValue
        guard NSNumber(value: int) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return int
    }

    fileprivate func unbox(_ value: Any, as type: Int8.Type) throws -> Int8? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let int8 = number.int8Value
        guard NSNumber(value: int8) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return int8
    }

    fileprivate func unbox(_ value: Any, as type: Int16.Type) throws -> Int16? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let int16 = number.int16Value
        guard NSNumber(value: int16) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return int16
    }

    fileprivate func unbox(_ value: Any, as type: Int32.Type) throws -> Int32? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let int32 = number.int32Value
        guard NSNumber(value: int32) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return int32
    }

    fileprivate func unbox(_ value: Any, as type: Int64.Type) throws -> Int64? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let int64 = number.int64Value
        guard NSNumber(value: int64) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return int64
    }

    fileprivate func unbox(_ value: Any, as type: UInt.Type) throws -> UInt? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let uint = number.uintValue
        guard NSNumber(value: uint) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return uint
    }

    fileprivate func unbox(_ value: Any, as type: UInt8.Type) throws -> UInt8? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let uint8 = number.uint8Value
        guard NSNumber(value: uint8) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return uint8
    }

    fileprivate func unbox(_ value: Any, as type: UInt16.Type) throws -> UInt16? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let uint16 = number.uint16Value
        guard NSNumber(value: uint16) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return uint16
    }

    fileprivate func unbox(_ value: Any, as type: UInt32.Type) throws -> UInt32? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let uint32 = number.uint32Value
        guard NSNumber(value: uint32) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return uint32
    }

    fileprivate func unbox(_ value: Any, as type: UInt64.Type) throws -> UInt64? {
        guard !(value is NSNull) else { return nil }

        guard let number = value as? NSNumber else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        let uint64 = number.uint64Value
        guard NSNumber(value: uint64) == number else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number <\(number)> does not fit in \(type)."))
        }

        return uint64
    }

    fileprivate func unbox(_ value: Any, as type: Float.Type) throws -> Float? {
        guard !(value is NSNull) else { return nil }

        if let number = value as? NSNumber {
            // We are willing to return a Float by losing precision:
            // * If the original value was integral,
            //   * and the integral value was > Float.greatestFiniteMagnitude, we will fail
            //   * and the integral value was <= Float.greatestFiniteMagnitude, we are willing to lose precision past 2^24
            // * If it was a Float, you will get back the precise value
            // * If it was a Double or Decimal, you will get back the nearest approximation if it will fit
            let double = number.doubleValue
            guard abs(double) <= Double(Float.greatestFiniteMagnitude) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Parsed number \(number) does not fit in \(type)."))
            }

            return Float(double)

            /* FIXME: If swift-corelibs-foundation doesn't change to use NSNumber, this code path will need to be included and tested:
             } else if let double = value as? Double {
             if abs(double) <= Double(Float.max) {
             return Float(double)
             }
             overflow = true
             } else if let int = value as? Int {
             if let float = Float(exactly: int) {
             return float
             }
             overflow = true
             */

        } else if let string = value as? NSString {
            return string.floatValue
        }

        throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
    }

    fileprivate func unbox(_ value: Any, as type: Double.Type) throws -> Double? {
        guard !(value is NSNull) else { return nil }

        if let number = value as? NSNumber {
            // We are always willing to return the number as a Double:
            // * If the original value was integral, it is guaranteed to fit in a Double; we are willing to lose precision past 2^53 if you encoded a UInt64 but requested a Double
            // * If it was a Float or Double, you will get back the precise value
            // * If it was Decimal, you will get back the nearest approximation
            return number.doubleValue

            /* FIXME: If swift-corelibs-foundation doesn't change to use NSNumber, this code path will need to be included and tested:
             } else if let double = value as? Double {
             return double
             } else if let int = value as? Int {
             if let double = Double(exactly: int) {
             return double
             }
             overflow = true
             */
        } else if let string = value as? NSString {
            return string.doubleValue
        }

        throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
    }

    fileprivate func unbox(_ value: Any, as type: String.Type) throws -> String? {
        guard !(value is NSNull) else { return nil }

        guard let string = value as? String else {
            throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
        }

        return string
    }

    fileprivate func unbox(_ value: Any, as type: Date.Type) throws -> Date? {
        guard !(value is NSNull) else { return nil }

        switch self.options.dateDecodingStrategy {
        case .deferredToDate:
            self.storage.push(container: value)
            let date = try Date(from: self)
            self.storage.popContainer()
            return date
        case .secondsSince1970:
            let double = try self.unbox(value, as: Double.self)!
            return Date(timeIntervalSince1970: double)
        case .millisecondsSince1970:
            let double = try self.unbox(value, as: Double.self)!
            return Date(timeIntervalSince1970: double / 1000.0)
        case .iso8601:
            if #available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                let string = try self.unbox(value, as: String.self)!
                guard let date = _iso8601Formatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
                }

                return date
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }

        case .formatted(let formatter):
            let string = try self.unbox(value, as: String.self)!
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Date string does not match format expected by formatter."))
            }
            return date
        case .custom(let closure):
            self.storage.push(container: value)
            let date = try closure(self)
            self.storage.popContainer()
            return date
        @unknown default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Currently unsupported dateDecodingStrategy."))
        }
    }

    fileprivate func unbox(_ value: Any, as type: Data.Type) throws -> Data? {
        guard !(value is NSNull) else { return nil }

        switch self.options.dataDecodingStrategy {
        case .deferredToData:
            self.storage.push(container: value)
            let data = try Data(from: self)
            self.storage.popContainer()
            return data
        case .base64:
            guard let string = value as? String else {
                throw DecodingError.__ObjectDecoderTypeMismatch(at: self.codingPath, expectation: type, reality: value)
            }

            guard let data = Data(base64Encoded: string) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Encountered Data is not valid Base64."))
            }

            return data
        case .custom(let closure):
            self.storage.push(container: value)
            let data = try closure(self)
            self.storage.popContainer()
            return data
        @unknown default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Currently unsupported dataDecodingStrategy."))
        }
    }

    fileprivate func unbox(_ value: Any, as type: Decimal.Type) throws -> Decimal? {
        guard !(value is NSNull) else { return nil }

        let doubleValue = try self.unbox(value, as: Double.self)!
        return Decimal(doubleValue)
    }

    fileprivate func unbox<T: Decodable>(_ value: Any, as type: T.Type) throws -> T? {
        let decoded: T
        if T.self == Date.self {
            guard let date = try self.unbox(value, as: Date.self) else { return nil }
            decoded = date as! T
        } else if T.self == Data.self {
            guard let data = try self.unbox(value, as: Data.self) else { return nil }
            decoded = data as! T
        } else if T.self == URL.self {
            guard let urlString = try self.unbox(value, as: String.self) else {
                return nil
            }

            let unreserved = "-._~/?"
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: unreserved)

            guard let encodedURLString = urlString.addingPercentEncoding(withAllowedCharacters: allowed), let url = URL(string: encodedURLString) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Invalid URL string."))
            }

            decoded = (url as! T)
        } else if T.self == Decimal.self {
            guard let decimal = try self.unbox(value, as: Decimal.self) else { return nil }
            decoded = decimal as! T
        } else {
            self.storage.push(container: value)
            decoded = try T(from: self)
            self.storage.popContainer()
        }

        return decoded
    }
}

private struct _ObjectKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    fileprivate init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }

    fileprivate static let `super` = _ObjectKey(stringValue: "super")!
}

extension DecodingError {
    /// Returns a `.typeMismatch` error describing the expected type.
    ///
    /// - parameter path: The path of `CodingKey`s taken to decode a value of this type.
    /// - parameter expectation: The type expected to be encountered.
    /// - parameter reality: The value that was encountered instead of the expected type.
    /// - returns: A `DecodingError` with the appropriate path and debug description.
    internal static func __ObjectDecoderTypeMismatch(at path: [CodingKey], expectation: Any.Type, reality: Any) -> DecodingError {
        let description = "Expected to decode \(expectation) but found \(__ObjectDecoderTypeDescription(of: reality)) instead."
        return .typeMismatch(expectation, Context(codingPath: path, debugDescription: description))
    }

    /// Returns a description of the type of `value` appropriate for an error message.
    ///
    /// - parameter value: The value whose type to describe.
    /// - returns: A string describing `value`.
    /// - precondition: `value` is one of the types below.
    fileprivate static func __ObjectDecoderTypeDescription(of value: Any) -> String {
        if value is NSNull {
            return "a null value"
        } else if value is NSNumber /* FIXME: If swift-corelibs-foundation isn't updated to use NSNumber, this check will be necessary: || value is Int || value is Double */ {
            return "a number"
        } else if value is String {
            return "a string/data"
        } else if value is [Any] {
            return "an array"
        } else if value is [String: Any] {
            return "a dictionary"
        } else {
            // This should never happen.
            preconditionFailure("Invalid storage type \(type(of: value)).")
        }
    }
}
