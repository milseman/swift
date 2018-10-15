//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// COW helpers
extension _StringGuts {
  internal var nativeCapacity: Int? {
      guard hasNativeStorage else { return nil }
      return _object.nativeStorage.capacity
  }

  internal var nativeUnusedCapacity: Int? {
      guard hasNativeStorage else { return nil }
      return _object.nativeStorage.unusedCapacity
  }

  // If natively stored and uniquely referenced, return the storage's total
  // capacity. Otherwise, nil.
  internal var uniqueNativeCapacity: Int? {
    @inline(__always) mutating get {
      guard isUniqueNative else { return nil }
      return _object.nativeStorage.capacity
    }
  }

  // If natively stored and uniquely referenced, return the storage's spare
  // capacity. Otherwise, nil.
  internal var uniqueNativeUnusedCapacity: Int? {
    @inline(__always) mutating get {
      guard isUniqueNative else { return nil }
      return _object.nativeStorage.unusedCapacity
    }
  }

  @usableFromInline // @testable
  internal var isUniqueNative: Bool {
    @inline(__always) mutating get {
      // Note: mutating so that self is `inout`.
      guard hasNativeStorage else { return false }
      defer { _fixLifetime(self) }
      var bits: UInt = _object.largeAddressBits
      return _isUnique_native(&bits)
    }
  }
}

// Range-replaceable operation support
extension _StringGuts {
  internal mutating func reserveCapacity(_ n: Int) {
    // Check if there's nothing to do
    if n <= _SmallString.capacity { return }
    if let currentCap = self.uniqueNativeCapacity, currentCap >= n { return }

    // Grow
    self.grow(n)
  }

  // Grow to accomodate at least `n` code units
  internal mutating func grow(_ n: Int) {
    defer { self._invariantCheck() }

    _sanityCheck(
      self.uniqueNativeCapacity == nil || self.uniqueNativeCapacity! < n)

    if _fastPath(isFastUTF8) {
      let storage = self.withFastUTF8 {
        _StringStorage.create(initializingFrom: $0, capacity: n)
      }

      // TODO(UTF8): Track known ascii
      self = _StringGuts(storage)
      return
    }

    _foreignGrow(n)
  }

  @inline(never) // slow-path
  internal mutating func _foreignGrow(_ n: Int) {
    // TODO(UTF8 perf): skip the intermediary arrays
    let selfUTF8 = Array(String(self).utf8)
    selfUTF8.withUnsafeBufferPointer {
      self = _StringGuts(_StringStorage.create(
        initializingFrom: $0, capacity: n))
    }
  }

  internal mutating func append(_ other: _StringGuts) {
    defer { self._invariantCheck() }

    // Try to form a small string if possible
    if !hasNativeStorage {
      if let smol = _SmallString(base: self, appending: other) {
        self = _StringGuts(smol)
        return
      }
    }

    // See if we can accomodate without growing or copying. If we have
    // sufficient capacity, we do not need to grow, and we can skip the copy if
    // unique. Otherwise, growth is required.
    let otherUTF8Count = other.utf8Count
    let sufficientCapacity: Bool
    if let unused = self.nativeUnusedCapacity, unused >= otherUTF8Count {
      sufficientCapacity = true
    } else {
      sufficientCapacity = false
    }
    if !self.isUniqueNative || !sufficientCapacity {
      let totalCount = self.utf8Count + otherUTF8Count

      // Non-unique storage: just make a copy of the appropriate size, otherwise
      // grow like an array.
      let growthTarget: Int
      if sufficientCapacity {
        growthTarget = totalCount
      } else {
        growthTarget = Swift.max(
          totalCount, _growArrayCapacity(nativeCapacity ?? 0))
      }
      self.grow(growthTarget)
    }

    _sanityCheck(self.uniqueNativeUnusedCapacity != nil,
      "growth should produce uniqueness")

    if other.isFastUTF8 {
      other.withFastUTF8 { self.appendInPlace($0) }
      return
    }
    _foreignAppendInPlace(other)
  }

  internal mutating func appendInPlace(_ other: UnsafeBufferPointer<UInt8>) {
    self._object.nativeStorage.appendInPlace(other)

    // We re-initialize from the modified storage to pick up new count, flags,
    // etc.
    self = _StringGuts(self._object.nativeStorage)
  }

  @inline(never) // slow-path
  internal mutating func _foreignAppendInPlace(_ other: _StringGuts) {
    _sanityCheck(!other.isFastUTF8)
    _sanityCheck(self.uniqueNativeUnusedCapacity != nil)

    var iter = String(other).utf8.makeIterator()
    self._object.nativeStorage.appendInPlace(&iter)

    // We re-initialize from the modified storage to pick up new count, flags,
    // etc.
    self = _StringGuts(self._object.nativeStorage)
  }

  internal mutating func clear() {
    guard hasNativeStorage else {
      self = _StringGuts()
      return
    }

    // Reset the count
    _object.nativeStorage.clear()
    self = _StringGuts(_object.nativeStorage)
  }

  @inline(__always) // Always-specialize
  internal mutating func replaceSubrange<C>(
    _ bounds: Range<Index>,
    with newElements: C
  ) where C : Collection, C.Iterator.Element == Character {
    if isUniqueNative {
      if let replStr = newElements as? String, replStr._guts.isFastUTF8 {
        replStr._guts.withFastUTF8 {
          uniqueNativeReplaceSubrange(bounds, with: $0)
        }
        return
      }
      // TODO(UTF8 perf): Probably also worth checking contiguous Substring
    }

    var result = String()
    let selfStr = String(self)
    result.append(contentsOf: selfStr[..<bounds.lowerBound])
    result.append(contentsOf: newElements)
    result.append(contentsOf: selfStr[bounds.upperBound...])
    self = result._guts
  }

  internal mutating func uniqueNativeReplaceSubrange(
    _ bounds: Range<Index>,
    with codeUnits: UnsafeBufferPointer<UInt8>
  ) {
    let neededCapacity =
      bounds.lowerBound.encodedOffset
      + codeUnits.count + (self.count - bounds.upperBound.encodedOffset)

    // TODO(UTF8 perf): efficient implementation
    var result = String()
    let selfStr = String(self)
    let prefix = selfStr[..<bounds.lowerBound]
    let suffix = selfStr[bounds.upperBound...]
    result.append(contentsOf: prefix)
    result._guts.append(_StringGuts(codeUnits, isKnownASCII: false))
    result.append(contentsOf: suffix)
    self = result._guts
  }
}



