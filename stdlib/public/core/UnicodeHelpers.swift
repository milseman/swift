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

//
// A collection of helper functions and utilities for interpreting Unicode
// contents at a low-level.
//

internal let _leadingSurrogateBias: UInt16 = 0xd800
internal let _trailingSurrogateBias: UInt16 = 0xdc00
internal let _surrogateMask: UInt16 = 0xfc00

@inline(__always)
internal func _isTrailingSurrogate(_ cu: UInt16) -> Bool {
  return cu & _surrogateMask == _trailingSurrogateBias
}
@inline(__always)
internal func _isLeadingSurrogate(_ cu: UInt16) -> Bool {
  return cu & _surrogateMask == _leadingSurrogateBias
}
@inline(__always)
internal func _isSurrogate(_ cu: UInt16) -> Bool {
  // TODO(UTF8 perf): check codegen
  return _isLeadingSurrogate(cu) || _isTrailingSurrogate(cu)
}

@inlinable @inline(__always)
internal func _isASCII(_ x: UInt8) -> Bool {
  return x & 0b1000_0000 == 0
}

@inlinable @inline(__always)
internal func _decodeUTF8(_ x: UInt8) -> Unicode.Scalar {
  _sanityCheck(_isASCII(x))
  return Unicode.Scalar(_unchecked: UInt32(x))
}

@inlinable @inline(__always)
internal func _decodeUTF8(_ x: UInt8, _ y: UInt8) -> Unicode.Scalar {
  _sanityCheck(_utf8ScalarLength(x) == 2)
  _sanityCheck(_isContinuation(y))
  let x = UInt32(x)
  let value = ((x & 0b0001_1111) &<< 6) | _continuationPayload(y)
  return Unicode.Scalar(_unchecked: value)
}

@inlinable @inline(__always)
internal func _decodeUTF8(
  _ x: UInt8, _ y: UInt8, _ z: UInt8
) -> Unicode.Scalar {
  _sanityCheck(_utf8ScalarLength(x) == 3)
  _sanityCheck(_isContinuation(y) && _isContinuation(z))
  let x = UInt32(x)
  let value = ((x & 0b0000_1111) &<< 12)
            | (_continuationPayload(y) &<< 6)
            | _continuationPayload(z)
  return Unicode.Scalar(_unchecked: value)
}

@inlinable @inline(__always)
internal func _decodeUTF8(
  _ x: UInt8, _ y: UInt8, _ z: UInt8, _ w: UInt8
) -> Unicode.Scalar {
  _sanityCheck(_utf8ScalarLength(x) == 4)
  _sanityCheck(
    _isContinuation(y) && _isContinuation(z) && _isContinuation(w))
  let x = UInt32(x)
  let value = ((x & 0b0000_1111) &<< 18)
            | (_continuationPayload(y) &<< 12)
            | (_continuationPayload(z) &<< 6)
            | _continuationPayload(w)
  return Unicode.Scalar(_unchecked: value)
}

@usableFromInline @inline(__always)
internal func _utf8ScalarLength(_ x: UInt8) -> Int {
  _sanityCheck(!_isContinuation(x))
  if _isASCII(x) { return 1 }
  // TODO(UTF8): Not great codegen on x86
  return (~x).leadingZeroBitCount
}

@usableFromInline @inline(__always)
internal func _isContinuation(_ x: UInt8) -> Bool {
  return x & 0b1100_0000 == 0b1000_0000
}

@usableFromInline @inline(__always)
internal func _continuationPayload(_ x: UInt8) -> UInt32 {
  return UInt32(x & 0x3F)
}

@inline(__always)
internal func _decodeSurrogatePair(
  leading high: UInt16, trailing low: UInt16
) -> UInt32 {
  _sanityCheck(_isLeadingSurrogate(high) && _isTrailingSurrogate(low))
  let hi10: UInt32 = UInt32(high) &- UInt32(_leadingSurrogateBias)
  _sanityCheck(hi10 < 1<<10, "I said high 10. Not high, like, 20 or something")
  let lo10: UInt32 = UInt32(low) &- UInt32(_trailingSurrogateBias)
  _sanityCheck(lo10 < 1<<10, "I said low 10. Not low, like, 20 or something")

  return ((hi10 &<< 10) | lo10) &+ 0x1_00_00
}

