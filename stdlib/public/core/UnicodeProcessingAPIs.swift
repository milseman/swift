/// An unsafe buffer pointer to validly-encoded UTF-8 code units stored in
/// contiguous memory.
///
/// UTF-8 validity is checked upon creation.
///
/// TODO: Detail the programmer invariants required with its use, i.e.
/// memory safety and exclusivity / non-mutability. Violations of those
/// can result in UB
///
@frozen
public struct UnsafeValidUTF8BufferPointer {
  @usableFromInline
  internal var _baseAddress: UnsafeRawPointer

  // A bit-packed count and flags (such as isASCII)
  @usableFromInline
  internal var _countAndFlags: UInt64
}

extension String {
  // TESTING
  public func _withUnsafeVUTF8BP<T>(
    _ f: (UnsafeValidUTF8BufferPointer) throws -> T
  ) rethrows -> T {
    var copy = self
    return try copy.withUTF8 {
      let buf = UnsafeValidUTF8BufferPointer(
        _baseAddress: $0.baseAddress!, _countAndFlags: UInt64($0.count))
      return try f(buf)
    }
  }
}

extension UnsafeValidUTF8BufferPointer {
  @frozen
  public struct DecodingError: Error, Sendable, Hashable, Codable {
    public var kind: UTF8.EncodingErrorKind
    public var offsets: Range<Int>
  }
}

/*

  NOTE: We will want a assuming-valid init somehow, perhaps
 with a debug-mode branch to validate. We will _need_ it if
 we don't have a String.withUnsafeVUTF8BP, for example.

 NOTE: We will want to explore different bounds checking:

 1. Make sure Index's byte offset is in-bounds of the collection
 2. Make sure Index's byte offset is scalar-aligned
 3. (Optional) some API to Character-align Index's byte offset




 */

/*

  _countAndFlags uses a 56-bit length and 8 bits for flags


┌───────┬──────────┬───────┐
│ b63   │ b62:56   │ b56:0 │
├───────┼──────────┼───────┤
│ ASCII │ reserved │ count │
└───────┴──────────┴───────┘


 TODO: single-byte-Characters bit? Should we reserve it and add the branch?

 ┌─────────────┬───────────────────┐
 │  b63:b01    │        b0         │
 ├─────────────┼───────────────────┤
 │ byte offset │ second code unit  │
 └─────────────┴───────────────────┘




*/

// TODO: consider AEIC for some of these...

extension UnsafeValidUTF8BufferPointer {
  // TODO: 32-bit support

  /// Returns whether the validated contents were all-ASCII. This is checked at
  /// initialization time and remembered.
  @inlinable
  public var isASCII: Bool {
    0 != _countAndFlags & 0x8000_0000_0000_0000
  }

  /// The number of bytes in the buffer
  @inlinable
  public var byteCount: Int {
    .init(truncatingIfNeeded: _countAndFlags & 0x00FF_FFFF_FFFF_FFFF)
  }

  /// Future work: `isKnownNFC` and `isKnownSingleScalarCharacter`

  /// Access the underlying raw bytes
  @inlinable
  public var rawBytes: UnsafeRawBufferPointer {
    .init(start: _baseAddress, count: byteCount)
  }
}

/// All the initializers below are `throw`ing, as they validate the contents
/// upon construction.
///
/// TODO: Typed throws? Stdlib currently only has notion of valid-or-not, need to
/// add specific errors
///
/// TODO: How do we handle nul-termination for the ones that take a length?
/// Is that passed in as an API option, etc?
///
/// Alternative: These could be static methods, e.g.
///   ```
///   extension UTF8 {
///     static func validate(
///       ...
///     ) throws -> UnsafeValidUTF8BufferPointer
///   }
///   ```
extension UnsafeValidUTF8BufferPointer {
  @usableFromInline
  internal static func _validate(
    baseAddress: UnsafeRawPointer, length: Int
  ) -> Result<UnsafeValidUTF8BufferPointer, DecodingError> {
    _internalInvariant(length <= 0x00FF_FFFF_FFFF_FFFF)
    return baseAddress.withMemoryRebound(
      to: UInt8.self, capacity: length
    ) {
      switch validateUTF8(.init(start: $0, count: length)) {
      case .success(let isASCII):
        let countAndFlags = UInt64(truncatingIfNeeded: length)
          & (isASCII.isASCII ? 0x8000_0000_0000_0000 : 0)

        return .success(UnsafeValidUTF8BufferPointer(
          _baseAddress: baseAddress,
          _countAndFlags: countAndFlags))
      case .error(let toBeReplaced):
        // FIXME: decypher reason
        return .failure(.init(
          kind: .expectedContinuationByte,
          offsets: toBeReplaced))
      }
    }
  }

  @_alwaysEmitIntoClient
  public init(baseAddress: UnsafeRawPointer, length: Int) throws {
    fatalError()
  }

  @_alwaysEmitIntoClient
  public init(nulTerminatedCString: UnsafeRawPointer) throws {
    fatalError()
  }

  @_alwaysEmitIntoClient
  public init(nulTerminatedCString: UnsafePointer<CChar>) throws {
    fatalError()
  }

  @_alwaysEmitIntoClient
  public init(_ bufPtr: UnsafeRawBufferPointer) throws {
    fatalError()
  }

  @_alwaysEmitIntoClient
  public init(_ bufPtr: UnsafeBufferPointer<UInt8>) throws {
    fatalError()
  }
}

extension UnsafeValidUTF8BufferPointer {
  /// A view of the buffer's contents as a bidirectional collection of `Unicode.Scalar`s.
  @frozen
  public struct UnicodeScalarView {
    public var buffer: UnsafeValidUTF8BufferPointer

    @inlinable
    public init(_ buffer: UnsafeValidUTF8BufferPointer) {
      self.buffer = buffer
    }
  }
  @inlinable
  public var unicodeScalars: UnicodeScalarView {
    .init(self)
  }

  /// A view of the buffer's contents as a bidirectional collection of `Character`s.
  @frozen
  public struct CharacterView {
    public var buffer: UnsafeValidUTF8BufferPointer

    @inlinable
    public init(_ buffer: UnsafeValidUTF8BufferPointer) {
      self.buffer = buffer
    }
  }
  @inlinable
  public var characters: CharacterView {
    .init(self)
  }

  /// A view off the buffer's contents as a bidirectional collection of transcoded
  /// `UTF16.CodeUnit`s.
  @frozen
  public struct UTF16View {
    public var buffer: UnsafeValidUTF8BufferPointer

    @inlinable
    public init(_ buffer: UnsafeValidUTF8BufferPointer) {
      self.buffer = buffer
    }
  }
  @inlinable
  public var utf16: UTF16View {
    .init(self)
  }

  /// Future work: Expose UTF-8 <=> UTF-16 breadcrumbs API
}

/// Alternative / future work: generic transcoded views.
///
/// This would need some perf investigation to make sure we can specialize for
/// UTF-16 sufficiently.
///
/// It might also make sense to add to String as well
extension UnsafeValidUTF8BufferPointer {
  /// A view off the buffer's contents as a bidirectional collection of transcoded
  /// `Encoding.CodeUnit`s.
  @frozen
  public struct TranscodedView<Encoding: _UnicodeEncoding> {
    public var buffer: UnsafeValidUTF8BufferPointer

    @inlinable
    public init(_ buffer: UnsafeValidUTF8BufferPointer) {
      self.buffer = buffer
    }
  }

  //  public var utf16: TranscodedView<UTF16>
}

extension UnsafeValidUTF8BufferPointer.UnicodeScalarView: BidirectionalCollection {
  public typealias Element = Unicode.Scalar

  @frozen
  public struct Index: Comparable, Hashable, Sendable {
    @usableFromInline
    internal var _byteOffset: Int

    @inlinable
    public var byteOffset: Int { _byteOffset }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.byteOffset < rhs.byteOffset
    }

    /// TODO: Note about unsafety if `offset` it's not actually scalar-aligned
    @inlinable
    internal init(_uncheckedByteOffset offset: Int) {
      self._byteOffset = offset
    }
  }

  @inlinable
  public subscript(position: Index) -> Element {
    _read {
      // TODO: what kinds of bounds checks are we looking for?
      yield _decodeScalar(
        _unsafeUnchecked: buffer._baseAddress,
        offset: position.byteOffset).0
    }
  }

  @inlinable
  public func index(after i: Index) -> Index {
    let off = i.byteOffset
    let len = _scalarLength(
      _unsafeUnchecked: buffer._baseAddress,
      offset: off)
    return .init(_uncheckedByteOffset: off &+ len)
  }

  @inlinable
  public func index(before i: Index) -> Index {
    let off = i.byteOffset
    let len = _scalarLength(
      _unsafeUnchecked: buffer._baseAddress,
      endingAtOffset: off)
    return .init(_uncheckedByteOffset: off &- len)
  }

  @inlinable
  public var startIndex: Index {
    .init(_uncheckedByteOffset: 0)
  }

  @inlinable
  public var endIndex: Index {
    .init(_uncheckedByteOffset: buffer.byteCount)
  }

  @frozen
  public struct Iterator: IteratorProtocol {
    @usableFromInline
    internal var _buffer: UnsafeValidUTF8BufferPointer

    @usableFromInline
    internal var _offset: Int

    public typealias Element = Unicode.Scalar

    @inlinable
    public mutating func next() -> Unicode.Scalar? {
      if _slowPath(_offset >= _buffer.byteCount) {
        return nil
      }
      let (scalar, len) = _decodeScalar(
        _unsafeUnchecked: _buffer._baseAddress, offset: _offset)
      self._offset &+= len
      return scalar
    }
  }

  public func makeIterator() -> Iterator {
    .init(_buffer: buffer, _offset: 0)
  }
}


extension UnsafeValidUTF8BufferPointer.CharacterView: BidirectionalCollection {
  public typealias Element = Character

  @frozen
  public struct Index: Comparable, Hashable, Sendable {
    @usableFromInline internal var _byteOffset: Int

    // TODO: consider two offsets, which span the range of
    // the character. What about USV?

    @inlinable
    public var byteOffset: Int { _byteOffset }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.byteOffset < rhs.byteOffset
    }

    /// TODO: Note about unsafety if `offset` it's not actually scalar-aligned
    ///
    /// TODO: Note about emergent (or whatever it is) behavior if `offset` is not
    /// actually Character-aligned
    @inlinable
    internal init(_uncheckedByteOffset offset: Int) {
      self._byteOffset = offset
    }
  }

  // Custom-defined for performance to avoid double-measuring
  // grapheme cluster length
  @frozen
  public struct Iterator: IteratorProtocol {
    @usableFromInline
    internal var _buffer: UnsafeValidUTF8BufferPointer

    @usableFromInline
    internal var _position: Index

    @inlinable
    public var buffer: UnsafeValidUTF8BufferPointer { _buffer }

    @inlinable
    public var position: Index { _position }

    public typealias Element = Character

    public mutating func next() -> Character? {
      guard position.byteOffset < buffer.byteCount else {
        return nil
      }

      let end = buffer._characterEnd(
        startingAtByteOffet: _position.byteOffset)
      let c = buffer._uncheckedCharacter(
        startingAt: position._byteOffset, endingAt: end)
      _position = .init(_uncheckedByteOffset: end)
      return c
    }

    @inlinable
    internal init(
      _buffer: UnsafeValidUTF8BufferPointer, _position: Index
    ) {
      self._buffer = _buffer
      self._position = _position
    }
  }

  @inlinable
  public func makeIterator() -> Iterator {
    .init(_buffer: self.buffer, _position: startIndex)
  }

  public subscript(position: Index) -> Element {
    _read {
      let end = index(after: position)
      yield buffer._uncheckedCharacter(
        startingAt: position._byteOffset,
        endingAt: end.byteOffset)
    }
  }

  public func index(after i: Index) -> Index {
    .init(_uncheckedByteOffset: buffer._characterEnd(
      startingAtByteOffet: i.byteOffset))
  }

  public func index(before i: Index) -> Index {
    .init(_uncheckedByteOffset: buffer._characterStart(
      endingAtByteOffet: i.byteOffset))
  }

  @inlinable
  public var startIndex: Index {
    .init(_uncheckedByteOffset: 0)
  }

  @inlinable
  public var endIndex: Index {
    .init(_uncheckedByteOffset: buffer.byteCount)
  }
}

extension UnsafeValidUTF8BufferPointer.UTF16View: BidirectionalCollection {
  public typealias Element = UInt16

  @frozen
  public struct Index: Comparable, Hashable, Sendable {
    // Bitpacked byte offset and transcoded offset
    @usableFromInline
    internal var _byteOffsetAndTranscodedOffset: UInt64

    /// Offset of the first byte of the currently-indexed scalar
    @inlinable
    public var byteOffset: Int {
      Int(truncatingIfNeeded: 
            _byteOffsetAndTranscodedOffset &>> 1)
    }

    /// Whether the index refers to the second code unit of a 2-code-unit scalar
    @inlinable
    public var  secondCodeUnit: Bool {
      (_byteOffsetAndTranscodedOffset & 0x01) == 1
    }

    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
      lhs._byteOffsetAndTranscodedOffset < rhs._byteOffsetAndTranscodedOffset
    }

    /// TODO: Note about unsafety if `offset` it's not actually scalar-aligned
    @inlinable
    internal init(
      _uncheckedByteOffset offset: Int, secondCodeUnit: Bool
    ) {
      _internalInvariant(
        offset >= 0 && offset < 0x7FFF_FFFF_FFFF_FFFF)
      let byteOffset = UInt64(truncatingIfNeeded: offset) &<< 63
      self._byteOffsetAndTranscodedOffset =
        byteOffset & (secondCodeUnit ? 1 : 0)
    }
  }

  @inlinable
  public subscript(position: Index) -> Element {
    _read {
      let scalar = _decodeScalar(
        _unsafeUnchecked: buffer._baseAddress,
        offset: position.byteOffset).0
      yield scalar.utf16[position.secondCodeUnit ? 1 : 0]
    }
  }

  @inlinable
  public func index(after i: Index) -> Index {
    // TODO: ASCII fast path

    let len = _scalarLength(
      _unsafeUnchecked: buffer._baseAddress, 
      offset: i.byteOffset)
    if len == 4 && !i.secondCodeUnit {
      return .init(
        _uncheckedByteOffset: i.byteOffset,
        secondCodeUnit: true)
    }
    return .init(
      _uncheckedByteOffset: i.byteOffset &+ len,
      secondCodeUnit: false)
  }

  @inlinable
  public func index(before i: Index) -> Index {
    if i.secondCodeUnit {
      return .init(
        _uncheckedByteOffset: i.byteOffset, 
        secondCodeUnit: false)
    }

    // TODO: ASCII fast path
    let len = _scalarLength(
      _unsafeUnchecked: buffer._baseAddress,
      endingAtOffset: i.byteOffset)
    return .init(
      _uncheckedByteOffset: i.byteOffset &- len,
      secondCodeUnit: len == 4)
  }

  @inlinable
  public var startIndex: Index {
    .init(_uncheckedByteOffset: 0, secondCodeUnit: false)
  }

  @inlinable
  public var endIndex: Index {
    .init(
      _uncheckedByteOffset: buffer.byteCount,
      secondCodeUnit: false)
  }
}

// Canonical equivalence
extension UnsafeValidUTF8BufferPointer {
  /// Whether `self` is equivalent to `other` under Unicode Canonical Equivalance
  public func isCanonicallyEquivalent(
    to other: UnsafeValidUTF8BufferPointer
  ) -> Bool {
    // FIXME: isNFC
    let bothAreNFC = false

    // TODO: refactor to raw pointers

    // TODO: consider early-exit when one normalization segment 
    // is longer than the other

    return self._withUBP { selfUBP in
      other._withUBP { otherUBP in
        return _stringCompareFastUTF8(
          selfUBP,
          otherUBP,
          expecting: .equal,
          bothNFC: bothAreNFC)
      }
    }
  }

  /// Whether `self` orders less than `other` (under Unicode Canonical Equivalance
  /// using normalized code-unit order)
  public func isCanonicallyLessThan(
    _ other: UnsafeValidUTF8BufferPointer
  ) -> Bool {
    // FIXME: isNFC
    let bothAreNFC = false

    // TODO: refactor to raw pointers

    // TODO: consider early-exit when one normalization segment
    // is longer than the other

    return self._withUBP { selfUBP in
      other._withUBP { otherUBP in
        return _stringCompareFastUTF8(
          selfUBP,
          otherUBP,
          expecting: .less,
          bothNFC: bothAreNFC)
      }
    }
  }

  /// Future: spaceship operator
}


/// MARK: - rest...
///



// TODO: what should be protocolized for a future
// ValidUTF8BufferView?



// TODO: repairing API which would yield an owner _and_ an
// object
// Or, would that be future work pending buffer views?

// TODO: with ephemeral string API

// TODO: normalized views (with protocol or what?)

// TODO: case-folded views, etc., or better left for future?
// I.e. can be derived from core operations, lazy flat maps,
// etc. Might be nice but is also a _lot_ if we're throwing
// protocols into the mix

extension Array {
  subscript(some someLabel: UnsafeRawPointer) -> Int {
    get throws { return 0 }
  }
}

extension Unicode.UTF8 {
  @frozen
  public enum EncodingErrorKind: Error, Sendable, Hashable, Codable {
    case unexpectedContinuationByte
    case expectedContinuationByte
    case overlongEncoding
    case invalidCodePoint

    case invalidStarterByte

    case unexpectedEndOfInput
  }
}

extension Unicode.UTF8 {
  @frozen
  public struct _EncodingErrorKind: Error, Sendable, Hashable, Codable {
    public var rawValue: UInt8

    @inlinable
    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    @inlinable
    public static var unexpectedContinuationByte: Self {
      .init(rawValue: 0x01)
    }

    @inlinable
    public static var overlongEncoding: Self {
      .init(rawValue: 0x02)
    }

    // ...
  }
}


#if false

// MARK: - Old stuff

extension UTF8 {
  public static func crash() {
    fatalError("running foo")
  }

  public static func returnTrue() -> Bool {
    true
  }

  public static func returnFalse() -> Bool {
    false
  }
}


// MARK: - Errors

extension Unicode.UTF8 {
  /// Alternate name: DecodingError?
  ///
  /// Would be nice to couple this with Range<Index> for Collection-taking API
  ///
  /// Should the non-collection ones have payloads for the bytes?
  public enum DecodingError: Error {
    case expectedStarter
    case expectedContinuation
    case overlongEncoding
    case invalidCodePoint
    case invalidStarterByte

    // FIXME: Not a real error when we finish implementation
    case todo
  }
}

extension Unicode.UTF16 {
  public enum DecodingError: Error {
    case expectedTrailingSurrogate
    case unexpectedTrailingSurrogate
  }
}

extension Unicode.UTF32 {
  public enum DecodingError: Error {
    case invalidCodePoint
  }
}

/// Should we make a protocol for encoding errors? What is the library extensiblity story
/// here?

extension Unicode.UTF8 {
  public struct CollectionDecodingError<Index: Comparable>: Error {
    public var kind: Unicode.UTF8.DecodingError
    public var range: Range<Index>
  }

  public struct ByteStreamDecodingError: Error {
    public var kind: Unicode.UTF8.DecodingError
    public var bytes: (UInt8, UInt8?, UInt8?)
  }
}


// MARK: - Validation


// HACK: quick shim for testing
@frozen
public struct UnsafeBufferView {
  public var baseAddress: UnsafeRawPointer
  public var count: Int
}
extension UnsafeBufferView {
  public init(_ bufPtr: UnsafeRawBufferPointer) {
    self.init(
      baseAddress: bufPtr.baseAddress!, count: bufPtr.count)
  }
}

extension Collection<UInt8> {
  // HACK: quick shim for testing
  public func withUnsafeBufferView<T>(
    _ f: (UnsafeBufferView) throws -> T
  ) rethrows -> T {
    try Array(self).withUnsafeBytes {
      try f(.init($0))
    }
  }
}


extension Unicode.UTF8 {
  public static func validate(
    _ bytes: UnsafeBufferView
  ) throws {
    let res = bytes.baseAddress.withMemoryRebound(to: UInt8.self,  capacity: bytes.count) { ptr in
      validateUTF8(.init(start: ptr, count: bytes.count))
    }
    switch res {

    case .success(_): return
    case .error(let intRange):
      throw UTF8.CollectionDecodingError(
        kind: .todo, range: intRange)
    }
  }
}

#endif

// MARK: - Unicode helpers

// TODO: AEIC?

@inlinable
internal func _getByte(
  _ ptr: UnsafeRawPointer,
  offset: Int
) -> UInt8 {
  ptr.loadUnaligned(fromByteOffset: offset, as: UInt8.self)
}

@inlinable
internal func _scalarLength(
  _unsafeUnchecked ptr: UnsafeRawPointer,
  offset: Int
) -> Int {
  _utf8ScalarLength(_getByte(ptr, offset: offset))
}

@inlinable
internal func _scalarLength(
  _unsafeUnchecked ptr: UnsafeRawPointer,
  endingAtOffset end: Int
) -> Int {
  var len = 1
  while UTF8.isContinuation(_getByte(ptr, offset: end &- len)) {
    len &+= 1
  }
  _internalInvariant(
    len == _scalarLength(
      _unsafeUnchecked: ptr, offset: end &- len))
  return len
}

@inlinable
internal func _decodeScalar(
  _unsafeUnchecked ptr: UnsafeRawPointer,
  endingAtOffset end: Int
) -> (Unicode.Scalar, scalarLength: Int) {
  let len = _scalarLength(
    _unsafeUnchecked: ptr, endingAtOffset: end)
  let (scalar, scalarLen) = _decodeScalar(
    _unsafeUnchecked: ptr, offset: end &- len)
  _internalInvariant(len == scalarLen)
  return (scalar, len)

}

@inlinable
internal func _decodeScalar(
  _unsafeUnchecked ptr: UnsafeRawPointer,
  offset: Int
) -> (Unicode.Scalar, scalarLength: Int) {
  let cu0 = _getByte(ptr, offset: offset)
  let len = _utf8ScalarLength(cu0)
  switch  len {
  case 1: return (_decodeUTF8(cu0), len)
  case 2: return (_decodeUTF8(
    cu0, _getByte(ptr, offset: offset &+ 1)), len)
  case 3:
    return (_decodeUTF8(
      cu0,
      _getByte(ptr, offset: offset &+ 1),
      _getByte(ptr, offset: offset &+ 2)),
    len)
  case 4:
    return (_decodeUTF8(
      cu0,
      _getByte(ptr, offset: offset &+ 1),
      _getByte(ptr, offset: offset &+ 2),
      _getByte(ptr, offset: offset &+ 3)),
    len)
  default: fatalError() // Builtin.unreachable()
  }
}

extension UnsafeValidUTF8BufferPointer {
  internal func _characterStart(
    endingAtByteOffet i: Int
  ) -> Int {
    let end = byteCount
    let ptr = _baseAddress
    return _previousCharacterBoundary(endingAt: i) { j in
      _internalInvariant(j <= end)
      guard j > 0 else { return nil }
      let (scalar, len) = _decodeScalar(
        _unsafeUnchecked: ptr, endingAtOffset: j)
      return (scalar, j &- len)
    }
  }

  internal func _characterEnd(
    startingAtByteOffet i: Int
  ) -> Int {
    let end = byteCount
    let ptr = _baseAddress
    return _nextCharacterBoundary(startingAt: i) { j in
      _internalInvariant(j >= 0)
      guard j < end else { return nil }
      let (scalar, len) = _decodeScalar(
        _unsafeUnchecked: ptr, offset: j)
      return (scalar, j &+ len)
    }
  }

  // TODO: eliminate making UBPs, also take isASCII etc
  internal func _withUBP<T>(
    _ f: (UnsafeBufferPointer<UInt8>) throws -> T
  ) rethrows -> T {
    try _baseAddress.withMemoryRebound(
      to: UInt8.self, capacity: byteCount
    ) {
      try f(.init(start: $0, count: byteCount))
    }
  }

  internal func _uncheckedCharacter(
    startingAt start: Int,
    endingAt end: Int
  ) -> Character {
    assert(start >= 0)
    assert(start <= end)
    assert(end <= byteCount)
    return _withUBP {
      let bufPtr = UnsafeBufferPointer(
        rebasing: $0[start..<end])
      return Character(unchecked: ._uncheckedFromUTF8(bufPtr))
    }
  }
}
