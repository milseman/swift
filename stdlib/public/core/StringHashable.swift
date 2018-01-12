//===----------------------------------------------------------------------===//
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

#if _runtime(_ObjC)
@_inlineable // FIXME(sil-serialize-all)
@_versioned // FIXME(sil-serialize-all)
@_silgen_name("swift_stdlib_NSStringHashValue")
internal func _stdlib_NSStringHashValue(
  _ str: AnyObject, isASCII: Bool) -> Int

@_inlineable // FIXME(sil-serialize-all)
@_versioned // FIXME(sil-serialize-all)
@_silgen_name("swift_stdlib_NSStringHashValuePointer")
internal func _stdlib_NSStringHashValuePointer(
  _ str: OpaquePointer, isASCII: Bool) -> Int

@_inlineable // FIXME(sil-serialize-all)
@_versioned // FIXME(sil-serialize-all)
@_silgen_name("swift_stdlib_CFStringHashCString")
internal func _stdlib_CFStringHashCString(
  _ str: OpaquePointer, _ len: Int) -> Int
#endif

extension Unicode {
  // FIXME: cannot be marked @_versioned. See <rdar://problem/34438258>
  // @_inlineable // FIXME(sil-serialize-all)
  // @_versioned // FIXME(sil-serialize-all)
  internal static func hashASCII(
    _ string: UnsafeBufferPointer<UInt8>
  ) -> Int {
    let collationTable = _swift_stdlib_unicode_getASCIICollationTable()
    var hasher = _SipHash13Context(key: _Hashing.secretKey)
    for c in string {
      _precondition(c <= 127)
      let element = collationTable[Int(c)]
      // Ignore zero valued collation elements. They don't participate in the
      // ordering relation.
      if element != 0 {
        hasher.append(element)
      }
    }
    return hasher._finalizeAndReturnIntHash()
  }

  // FIXME: cannot be marked @_versioned. See <rdar://problem/34438258>
  // @_inlineable // FIXME(sil-serialize-all)
  // @_versioned // FIXME(sil-serialize-all)
  internal static func hashUTF16(
    _ string: UnsafeBufferPointer<UInt16>
  ) -> Int {
    let collationIterator = _swift_stdlib_unicodeCollationIterator_create(
      string.baseAddress!,
      UInt32(string.count))
    defer { _swift_stdlib_unicodeCollationIterator_delete(collationIterator) }

    var hasher = _SipHash13Context(key: _Hashing.secretKey)
    while true {
      var hitEnd = false
      let element =
        _swift_stdlib_unicodeCollationIterator_next(collationIterator, &hitEnd)
      if hitEnd {
        break
      }
      // Ignore zero valued collation elements. They don't participate in the
      // ordering relation.
      if element != 0 {
        hasher.append(element)
      }
    }
    return hasher._finalizeAndReturnIntHash()
  }
}

#if _runtime(_ObjC)
#if arch(i386) || arch(arm)
    private let stringHashOffset = Int(bitPattern: 0x88dd_cc21)
#else
    private let stringHashOffset = Int(bitPattern: 0x429b_1266_88dd_cc21)
#endif // arch(i386) || arch(arm)
#endif // _runtime(_ObjC)

extension _UnmanagedString where CodeUnit == UInt8 {
  @_versioned
  @inline(never) // Hide the CF dependency
  internal func computeHashValue() -> Int {
#if _runtime(_ObjC)
    let hash = _stdlib_CFStringHashCString(OpaquePointer(start), count)
    // Mix random bits into NSString's hash so that clients don't rely on
    // Swift.String.hashValue and NSString.hash being the same.
    return stringHashOffset ^ hash
#else
    return Unicode.hashASCII(self.buffer)
#endif // _runtime(_ObjC)
  }
}

extension _UnmanagedString where CodeUnit == UTF16.CodeUnit {
  @_versioned
  @inline(never) // Hide the CF dependency
  internal func computeHashValue() -> Int {
#if _runtime(_ObjC)
    let temp = _NSContiguousString(_StringGuts(self))
    let hash = temp._unsafeWithNotEscapedSelfPointer {
      return _stdlib_NSStringHashValuePointer($0, isASCII: false)
    }
    // Mix random bits into NSString's hash so that clients don't rely on
    // Swift.String.hashValue and NSString.hash being the same.
    return stringHashOffset ^ hash
#else
    return Unicode.hashUTF16(self.buffer)
#endif // _runtime(_ObjC)
  }
}

extension _UnmanagedOpaqueString {
  @_versioned
  @inline(never) // Hide the CF dependency
  internal func computeHashValue() -> Int {
#if _runtime(_ObjC)
    // TODO: ranged hash?
    let hash = _stdlib_NSStringHashValue(cocoaSlice(), isASCII: false)
    // Mix random bits into NSString's hash so that clients don't rely on
    // Swift.String.hashValue and NSString.hash being the same.
    return stringHashOffset ^ hash
#else
    // FIXME: Streaming hash
    let p = UnsafeMutablePointer<UTF16.CodeUnit>.allocate(capacity: count)
    defer { p.deallocate(capacity: count) }
    let buffer = UnsafeMutableBufferPointer(start: p, count: count)
    _copy(into: buffer)
    return Unicode.hashUTF16(UnsafeBufferPointer(buffer))
#endif
  }
}

extension _StringGuts {
  @_versioned
  @inline(never) // Hide the CF dependency
  internal func _computeHashValue() -> Int {
    if _slowPath(_isOpaque) {
      return _asOpaque().computeHashValue()
    }
    if isASCII {
      return _unmanagedASCIIView.computeHashValue()
    }
    return _unmanagedUTF16View.computeHashValue()
  }

  @_versioned
  @inline(never) // Hide the CF dependency
  internal func _computeHashValue(_ range: Range<Int>) -> Int {
    if _slowPath(_isOpaque) {
      return _asOpaque()[range].computeHashValue()
    }
    if isASCII {
      return _unmanagedASCIIView[range].computeHashValue()
    }
    return _unmanagedUTF16View[range].computeHashValue()
  }
}

extension String : Hashable {
  /// The string's hash value.
  ///
  /// Hash values are not guaranteed to be equal across different executions of
  /// your program. Do not save hash values to use during a future execution.
  @_inlineable // FIXME(sil-serialize-all)
  public var hashValue: Int {
    return _guts._computeHashValue()
  }
}

extension StringProtocol {
  @_inlineable // FIXME(sil-serialize-all)
  public var hashValue : Int {
    return _wholeString._guts._computeHashValue(_encodedOffsetRange)
  }
}
