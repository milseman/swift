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

/// CR and LF are common special cases in grapheme breaking logic
private var _CR: UInt8 { return 0x0d }
private var _LF: UInt8 { return 0x0a }

private func _hasGraphemeBreakBetween(
  _ lhs: Unicode.Scalar, _ rhs: Unicode.Scalar
) -> Bool {

  // CR-LF is a special case: no break between these
  if lhs == Unicode.Scalar(_CR) && rhs == Unicode.Scalar(_LF) { return false }

  // Whether the given scalar, when it appears paired with another scalar
  // satisfying this property, has a grapheme break between it and the other
  // scalar.
  func hasBreakWhenPaired(_ x: Unicode.Scalar) -> Bool {
    // TODO: This doesn't generate optimal code, tune/re-write at a lower
    // level.
    //
    // NOTE: Order of case ranges affects codegen, and thus performance. All
    // things being equal, keep existing order below.
    switch x.value {
    // Unified CJK Han ideographs, common and some supplemental, amongst
    // others:
    //   0x3400-0xA4CF
    case 0x3400...0xa4cf: return true

    // Repeat sub-300 check, this is beneficial for common cases of Latin
    // characters embedded within non-Latin script (e.g. newlines, spaces,
    // proper nouns and/or jargon, punctuation).
    //
    // NOTE: CR-LF special case has already been checked.
    case 0x0000...0x02ff: return true

    // Non-combining kana:
    //   0x3041-0x3096
    //   0x30A1-0x30FA
    case 0x3041...0x3096: return true
    case 0x30a1...0x30fa: return true

    // Non-combining modern (and some archaic) Cyrillic:
    //   0x0400-0x0482 (first half of Cyrillic block)
    case 0x0400...0x0482: return true

    // Modern Arabic, excluding extenders and prependers:
    //   0x061D-0x064A
    case 0x061d...0x064a: return true

    // Precomposed Hangul syllables:
    //   0xAC00–0xD7AF
    case 0xac00...0xd7af: return true

    // Common general use punctuation, excluding extenders:
    //   0x2010-0x2029
    case 0x2010...0x2029: return true

    // CJK punctuation characters, excluding extenders:
    //   0x3000-0x3029
    case 0x3000...0x3029: return true

    default: return false
    }
  }
  return hasBreakWhenPaired(lhs) && hasBreakWhenPaired(rhs)
}

@inline(never) // slow-path
@_effects(releasenone)
private func _measureCharacterStrideICU(
  of utf8: UnsafeBufferPointer<UInt8>, startingAt i: Int
) -> Int {
  let iterator = _ThreadLocalStorage.getUBreakIterator(utf8)
  let offset = __swift_stdlib_ubrk_following(
    iterator, Int32(truncatingIfNeeded: i))
  // ubrk_following returns -1 (UBRK_DONE) when it hits the end of the buffer.
  if _fastPath(offset != -1) {
    // The offset into our buffer is the distance.
    _sanityCheck(offset > i, "zero-sized grapheme?")
    return Int(truncatingIfNeeded: offset) &- i
  }
  _sanityCheck(utf8.count > i)
  return utf8.count &- i
}

@inline(never) // slow-path
@_effects(releasenone)
private func _measureCharacterStrideICU(
  of utf16: UnsafeBufferPointer<UInt16>, startingAt i: Int
) -> Int {
  let iterator = _ThreadLocalStorage.getUBreakIterator(utf16)
  let offset = __swift_stdlib_ubrk_following(
    iterator, Int32(truncatingIfNeeded: i))
  // ubrk_following returns -1 (UBRK_DONE) when it hits the end of the buffer.
  if _fastPath(offset != -1) {
    // The offset into our buffer is the distance.
    _sanityCheck(offset > i, "zero-sized grapheme?")
    return Int(truncatingIfNeeded: offset) &- i
  }
  return utf16.count &- i
}

@inline(never) // slow-path
@_effects(releasenone)
private func _measureCharacterStrideICU(
  of utf8: UnsafeBufferPointer<UInt8>, endingAt i: Int
) -> Int {
  let iterator = _ThreadLocalStorage.getUBreakIterator(utf8)
  let offset = __swift_stdlib_ubrk_preceding(
    iterator, Int32(truncatingIfNeeded: i))
  // ubrk_following returns -1 (UBRK_DONE) when it hits the end of the buffer.
  if _fastPath(offset != -1) {
    // The offset into our buffer is the distance.
    _sanityCheck(offset < i, "zero-sized grapheme?")
    return i &- Int(truncatingIfNeeded: offset)
  }
  return i &- utf8.count
}

@inline(never) // slow-path
@_effects(releasenone)
private func _measureCharacterStrideICU(
  of utf16: UnsafeBufferPointer<UInt16>, endingAt i: Int
) -> Int {
  let iterator = _ThreadLocalStorage.getUBreakIterator(utf16)
  let offset = __swift_stdlib_ubrk_preceding(
    iterator, Int32(truncatingIfNeeded: i))
  // ubrk_following returns -1 (UBRK_DONE) when it hits the end of the buffer.
  if _fastPath(offset != -1) {
    // The offset into our buffer is the distance.
    _sanityCheck(offset < i, "zero-sized grapheme?")
    return i &- Int(truncatingIfNeeded: offset)
  }
  return i &- utf16.count
}

extension _StringGuts {
  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func isOnGraphemeClusterBoundary(_ i: String.Index) -> Bool {
    guard i.transcodedOffset == 0 else { return false }

    let offset = i.encodedOffset
    if offset == 0 || offset == self.count { return true }

    guard isOnUnicodeScalarBoundary(i) else { return false }

    let str = String(self)
    return i == str.index(before: str.index(after: i))
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _opaqueCharacterStride(startingAt i: Int) -> Int {
    if _slowPath(isForeign) {
      return _foreignOpaqueCharacterStride(startingAt: i)
    }

    return self.withFastUTF8 { utf8 in
      let (sc1, len) = _decodeScalar(utf8, startingAt: i)
      if i &+ len == utf8.endIndex {
        // Last scalar is last grapheme
        return len
      }
      let (sc2, _) = _decodeScalar(utf8, startingAt: i &+ len)
      if _fastPath(_hasGraphemeBreakBetween(sc1, sc2)) {
        return len
      }

      return _measureCharacterStrideICU(of: utf8, startingAt: i)
    }
  }

  @inline(never)
  @_effects(releasenone)
  private func _foreignOpaqueCharacterStride(startingAt i: Int) -> Int {
    _sanityCheck(isForeign)

    // TODO(String performance): Faster to do it from a pointer directly
    let count = _object.largeCount
    let cocoa = _object.cocoaObject

    let startIdx = String.Index(encodedOffset: i)
    let (sc1, len) = foreignErrorCorrectedScalar(startingAt: startIdx)
    if i &+ len == count {
      // Last scalar is last grapheme
      return len
    }
    let (sc2, _) = foreignErrorCorrectedScalar(
      startingAt: startIdx.encoded(offsetBy: len))
    if _fastPath(_hasGraphemeBreakBetween(sc1, sc2)) {
      return len
    }

    if let utf16Ptr = _stdlib_binary_CFStringGetCharactersPtr(cocoa) {
      let utf16 = UnsafeBufferPointer(start: utf16Ptr, count: count)
      return _measureCharacterStrideICU(of: utf16, startingAt: i)
    }

    // TODO(String performance): Local small stack first, before making large
    // array. Also, make a smaller initial array and grow over time.
    var codeUnits = Array<UInt16>(repeating: 0, count: count)

    codeUnits.withUnsafeMutableBufferPointer {
      _cocoaStringCopyCharacters(
        from: cocoa,
        range: 0..<count,
        into: $0.baseAddress._unsafelyUnwrappedUnchecked)
    }
    return codeUnits.withUnsafeBufferPointer {
      _measureCharacterStrideICU(of: $0, startingAt: i)
    }
  }

  @usableFromInline @inline(never)
  @_effects(releasenone)
  internal func _opaqueCharacterStride(endingAt i: Int) -> Int {
    if _slowPath(isForeign) {
      return _foreignOpaqueCharacterStride(endingAt: i)
    }

    return self.withFastUTF8 { utf8 in
      let (sc2, len) = _decodeScalar(utf8, endingAt: i)
      if i &- len == utf8.startIndex {
        // First scalar is first grapheme
        return len
      }
      let (sc1, _) = _decodeScalar(utf8, endingAt: i &- len)
      if _fastPath(_hasGraphemeBreakBetween(sc1, sc2)) {
        return len
      }
      return _measureCharacterStrideICU(of: utf8, endingAt: i)
    }
  }

  @inline(never)
  @_effects(releasenone)
  private func _foreignOpaqueCharacterStride(endingAt i: Int) -> Int {
    _sanityCheck(isForeign)

    // TODO(String performance): Faster to do it from a pointer directly
    let count = _object.largeCount
    let cocoa = _object.cocoaObject

    let endIdx = String.Index(encodedOffset: i)
    let (sc2, len) = foreignErrorCorrectedScalar(endingAt: endIdx)
    if i &- len == 0 {
      // First scalar is first grapheme
      return len
    }
    let (sc1, _) = foreignErrorCorrectedScalar(
      endingAt: endIdx.encoded(offsetBy: -len))
    if _fastPath(_hasGraphemeBreakBetween(sc1, sc2)) {
      return len
    }

    if let utf16Ptr = _stdlib_binary_CFStringGetCharactersPtr(cocoa) {
      let utf16 = UnsafeBufferPointer(start: utf16Ptr, count: count)
      return _measureCharacterStrideICU(of: utf16, endingAt: i)
    }

    // TODO(String performance): Local small stack first, before making large
    // array. Also, make a smaller initial array and grow over time.
    var codeUnits = Array<UInt16>(repeating: 0, count: count)

    codeUnits.withUnsafeMutableBufferPointer {
      _cocoaStringCopyCharacters(
        from: cocoa,
        range: 0..<count,
        into: $0.baseAddress._unsafelyUnwrappedUnchecked)
    }
    return codeUnits.withUnsafeBufferPointer {
      _measureCharacterStrideICU(of: $0, endingAt: i)
    }
  }
}

