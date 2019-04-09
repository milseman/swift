//===--- StringIndex.swift ------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftShims

/*

String's Index has the following layout:

 ┌──────────┬───────────────────┬─────────╥────────────────┬──────────┐
 │ b63:b16  │      b15:b14      │   b13   ║     b12:b8     │  b6:b0   │
 ├──────────┼───────────────────┼─────────╫────────────────┼──────────┤
 │ position │ transcoded offset │ aligned ║ grapheme cache │ reserved │
 └──────────┴───────────────────┴─────────╨────────────────┴──────────┘

Position, transcoded offset, and aligned are fully exposed in the ABI. Grapheme
cache and reserved are partially resilient: the fact that there are 13 bits with
a default value of `0` is ABI, but not the layout, construction, or
interpretation of those bits. All use of grapheme cache should be behind
non-inlinable function calls.

- position aka `encodedOffset`: A 48-bit offset into the string's code units
- transcoded offset: a 2-bit sub-scalar offset, derived from transcoding
- aligned, whether this index is known to be scalar-aligned
<resilience barrier>
- grapheme cache: A 5-bit value remembering the distance to the next grapheme
boundary
- reserved: 8-bit for future use.

*/
extension String {
  /// A position of a character or code unit in a string.
  @frozen
  public struct Index {
    @usableFromInline
    internal var _rawBits: UInt64

    @inlinable @inline(__always)
    init(_ raw: UInt64) {
      self._rawBits = raw
      self._invariantCheck()
    }
  }
}

extension String.Index {
  @inlinable @inline(__always)
  internal var orderingValue: UInt64 { return _rawBits &>> 14 }

  // Whether this is at the canonical "start" position, that is encoded AND
  // transcoded offset of 0.
  @inlinable @inline(__always)
  internal var isZeroPosition: Bool { return orderingValue == 0 }

  /// The UTF-16 code unit offset corresponding to this Index
  public func utf16Offset<S: StringProtocol>(in s: S) -> Int {
    return s.utf16.distance(from: s.utf16.startIndex, to: self)
  }

  /// The offset into a string's code units for this index.
  @available(swift, deprecated: 4.2, message: """
    encodedOffset has been deprecated as most common usage is incorrect. \
    Use utf16Offset(in:) to achieve the same behavior.
    """)
  @inlinable
  public var encodedOffset: Int { return _encodedOffset }

  @inlinable @inline(__always)
  internal var _encodedOffset: Int {
    return Int(truncatingIfNeeded: _rawBits &>> 16)
  }

  @inlinable @inline(__always)
  internal var transcodedOffset: Int {
    return Int(truncatingIfNeeded: orderingValue & 0x3)
  }

  @_alwaysEmitIntoClient // Swift 5.1
  @inline(__always)
  internal var isAligned: Bool { return 0 != _rawBits & 0x2000 }

  @usableFromInline
  internal var characterStride: Int? {
    let value = (_rawBits & 0x1F00) &>> 8
    return value > 0 ? Int(truncatingIfNeeded: value) : nil
  }

  @inlinable @inline(__always)
  internal init(encodedOffset: Int, transcodedOffset: Int) {
    let pos = UInt64(truncatingIfNeeded: encodedOffset)
    let trans = UInt64(truncatingIfNeeded: transcodedOffset)
    _internalInvariant(pos == pos & 0x0000_FFFF_FFFF_FFFF)
    _internalInvariant(trans <= 3)

    self.init((pos &<< 16) | (trans &<< 14))
  }

  /// Creates a new index at the specified UTF-16 code unit offset
  ///
  /// - Parameter offset: An offset in UTF-16 code units.
  public init<S: StringProtocol>(utf16Offset offset: Int, in s: S) {
    let (start, end) = (s.utf16.startIndex, s.utf16.endIndex)
    guard offset >= 0,
          let idx = s.utf16.index(start, offsetBy: offset, limitedBy: end)
    else {
      self = end.nextEncoded
      return
    }
    self = idx
  }

  /// Creates a new index at the specified code unit offset.
  ///
  /// - Parameter offset: An offset in code units.
  @available(swift, deprecated: 4.2, message: """
    encodedOffset has been deprecated as most common usage is incorrect. \
    Use String.Index(utf16Offset:in:) to achieve the same behavior.
    """)
  @inlinable
  public init(encodedOffset offset: Int) {
    self.init(_encodedOffset: offset)
  }

  @inlinable @inline(__always)
  internal init(_encodedOffset offset: Int) {
    self.init(encodedOffset: offset, transcodedOffset: 0)
  }

  @usableFromInline
  internal init(
    encodedOffset: Int, transcodedOffset: Int, characterStride: Int
  ) {
    self.init(encodedOffset: encodedOffset, transcodedOffset: transcodedOffset)
    if _slowPath(characterStride > 0x1F) { return }
    self._rawBits |= UInt64(truncatingIfNeeded: characterStride &<< 8)
    self._invariantCheck()
  }

  @usableFromInline
  internal init(encodedOffset pos: Int, characterStride char: Int) {
    self.init(encodedOffset: pos, transcodedOffset: 0, characterStride: char)
  }

  #if !INTERNAL_CHECKS_ENABLED
  @inlinable @inline(__always) internal func _invariantCheck() {}
  #else
  @usableFromInline @inline(never) @_effects(releasenone)
  internal func _invariantCheck() {
    _internalInvariant(_encodedOffset >= 0)
    if self.isAligned {
      _internalInvariant(transcodedOffset == 0)
    }
  }
  #endif // INTERNAL_CHECKS_ENABLED
}

// Creation helpers, which will make migration easier if we decide to use and
// propagate the reserved bits.
extension String.Index {
  @inlinable @inline(__always)
  internal var strippingTranscoding: String.Index {
    return String.Index(_encodedOffset: self._encodedOffset)
  }

  @inlinable @inline(__always)
  internal var nextEncoded: String.Index {
    _internalInvariant(self.transcodedOffset == 0)
    return String.Index(_encodedOffset: self._encodedOffset &+ 1)
  }

  @inlinable @inline(__always)
  internal var priorEncoded: String.Index {
    _internalInvariant(self.transcodedOffset == 0)
    return String.Index(_encodedOffset: self._encodedOffset &- 1)
  }

  @inlinable @inline(__always)
  internal var nextTranscoded: String.Index {
    return String.Index(
      encodedOffset: self._encodedOffset,
      transcodedOffset: self.transcodedOffset &+ 1)
  }

  @inlinable @inline(__always)
  internal var priorTranscoded: String.Index {
    return String.Index(
      encodedOffset: self._encodedOffset,
      transcodedOffset: self.transcodedOffset &- 1)
  }

  @_alwaysEmitIntoClient // Swift 5.1
  @inline(__always)
  internal var aligned: String.Index {
    var idx = self
    _internalInvariant(idx.transcodedOffset == 0, "can't be aligned")
    idx._rawBits |= 0x2000
    idx._invariantCheck()
    return idx
  }

  // Get an index with an encoded offset relative to this one.
  // Note: strips any transcoded offset.
  @inlinable @inline(__always)
  internal func encoded(offsetBy n: Int) -> String.Index {
    return String.Index(_encodedOffset: self._encodedOffset &+ n)
  }

  @inlinable @inline(__always)
  internal func transcoded(withOffset n: Int) -> String.Index {
    _internalInvariant(self.transcodedOffset == 0)
    return String.Index(encodedOffset: self._encodedOffset, transcodedOffset: n)
  }

}

extension String.Index: Equatable {
  @inlinable @inline(__always)
  public static func == (lhs: String.Index, rhs: String.Index) -> Bool {
    return lhs.orderingValue == rhs.orderingValue
  }
}

extension String.Index: Comparable {
  @inlinable @inline(__always)
  public static func < (lhs: String.Index, rhs: String.Index) -> Bool {
    return lhs.orderingValue < rhs.orderingValue
  }
}

extension String.Index: Hashable {
  /// Hashes the essential components of this value by feeding them into the
  /// given hasher.
  ///
  /// - Parameter hasher: The hasher to use when combining the components
  ///   of this instance.
  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(orderingValue)
  }
}
