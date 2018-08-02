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

import SwiftShims

//
// StringGuts is a parameterization over String's representations. It provides
// functionality and guidance for efficiently working with Strings.
//
@_fixed_layout @usableFromInline
internal struct _StringGuts {
  @usableFromInline
  internal var _object: _StringObject

  @inlinable @inline(__always)
  internal init(_ object: _StringObject) {
    self._object = object
    _invariantCheck()
  }

  // Empty string
  @inlinable @inline(__always)
  init() {
    self.init(_StringObject(empty: ()))
  }
}

// Raw
extension _StringGuts {
  @usableFromInline
  internal typealias RawBitPattern = _StringObject.RawBitPattern

  @inlinable
  internal var rawBits: RawBitPattern {
    @inline(__always) get { return _object.rawBits }
  }

  @inlinable @inline(__always)
  init(raw bits: RawBitPattern) {
    self.init(_StringObject(raw: bits))
  }

}

// Creation
extension _StringGuts {
  @inlinable @inline(__always)
  internal init(_ smol: _SmallUTF8String) {
    self.init(_StringObject(smol))
  }

  @inlinable @inline(__always)
  internal init(_ bufPtr: UnsafeBufferPointer<UInt8>, isKnownASCII: Bool) {
//    if let smol = _SmallUTF8String(bufPtr) {
//      self.init(smol)
//      return
//    }
    self.init(_StringObject(immortal: bufPtr, isASCII: isKnownASCII))
  }

  @inlinable @inline(__always)
  internal init(_ storage: _StringStorage) {
    // TODO(UTF8): We should probably store perf flags on the storage's capacity
    self.init(_StringObject(storage, isASCII: false))
  }

  internal init(_ storage: _SharedStringStorage) {
    // TODO(UTF8 perf): Is it better, or worse, to throw the object away if
    // immortal? We could avoid having to ARC the object itself when owner is
    // nil, at the cost of repeatedly creating a new one when this string is
    // bridged back-and-forth to ObjC. For now, we're choosing to keep the
    // object allocation, perform some ARC, and require a dependent load for
    // literals that have bridged back in from ObjC. Long term, we will likely
    // emit some kind of "immortal" object for literals with efficient bridging
    // anyways, so this may be a short-term decision.

    // TODO(UTF8): We should probably store perf flags in the object
    self.init(_StringObject(storage, isASCII: false))
  }

  internal init(cocoa: AnyObject, providesFastUTF8: Bool, length: Int) {
    self.init(_StringObject(
      cocoa: cocoa, providesFastUTF8: providesFastUTF8, length: length))
  }
}

// Queries
extension _StringGuts {
  // The number of code units
  @inlinable
  internal var count: Int { @inline(__always) get { return _object.count } }

  @inlinable
  internal var isEmpty: Bool { @inline(__always) get { return count == 0 } }

  @inlinable
  internal var isKnownASCII: Bool  {
    @inline(__always) get { return _object.isASCII }
  }

  @inlinable
  internal var capacity: Int? {
    // TODO: Should small strings return their capacity too?
    guard _object.hasNativeStorage else { return nil }
    return _object.nativeStorage.capacity
  }
}

//
extension _StringGuts {
  // Whether we can provide fast access to contiguous UTF-8 code units
  @inlinable
  internal var isFastUTF8: Bool {
    @inline(__always) get {
      // TODO(UTF8 merge): Can we add the Builtin.expected here?
      return _object.providesFastUTF8
    }
  }
  // A String which does not provide fast access to contiguous UTF-8 code units
  @inlinable
  internal var isForeign: Bool {
    @inline(__always) get { return _object.isForeign }
  }

  @inlinable @inline(__always)
  internal func withFastUTF8<R>(
    _ f: (UnsafeBufferPointer<UInt8>) throws -> R
  ) rethrows -> R {
    _sanityCheck(isFastUTF8)

    if _object.isSmall { return try _object.asSmallString.withUTF8(f) }

    defer { _fixLifetime(self) }
    return try f(_object.fastUTF8)
  }

  @inlinable @inline(__always)
  internal func withUTF8IfAvailable<R>(
    _ f: (UnsafeBufferPointer<UInt8>) throws -> R
  ) rethrows -> R? {
    if _slowPath(isForeign) { return nil }
    return try withFastUTF8(f)
  }
}

// Internal invariants
extension _StringGuts {
  @inlinable @inline(__always)
  internal func _invariantCheck() {
    #if INTERNAL_CHECKS_ENABLED
    _object._invariantCheck()
    #if arch(i386) || arch(arm)
    _sanityCheck(MemoryLayout<String>.size == 12, """
    the runtime is depending on this, update Reflection.mm and \
    this if you change it
    """)
    #else
    _sanityCheck(MemoryLayout<String>.size == 16, """
    the runtime is depending on this, update Reflection.mm and \
    this if you change it
    """)
    #endif
    #endif // INTERNAL_CHECKS_ENABLED
  }

  internal func _dump() { _object._dump() }
}

// Append
extension _StringGuts {
  internal mutating func reserveCapacity(_ n: Int) {
    // Check if there's nothing to do
    if n <= _SmallUTF8String.capacity { return }
    if let currentCap = self.capacity, currentCap >= n { return }

    // Grow
    if isFastUTF8 {
      let storage = self.withFastUTF8 {
        _StringStorage.create(initializingFrom: $0, capacity: n)
      }

      // TODO(UTF8): Track known ascii
      self = _StringGuts(storage)
      return
    }

    unimplemented_utf8()
  }

  internal mutating func append(_ bufPtr: UnsafeBufferPointer<UInt8>) {
    // Try to fit in existing storage if possible
    if _object.isSmall {
      // TODO(UTF8 perf): Try to fit into smol whenever possible
    } else if _object.hasNativeStorage {
      if _object.nativeStorage.unusedCapacity >= bufPtr.count {
        // TODO(UTF8 perf): Uniqueness check and skip the reallocation
      }
    }

    // Grow into an appropriately sized storage
    //
    // TODO(UTF8): How do we want to grow? Take current capacity into account?
    if isFastUTF8 {
      let storage = self.withFastUTF8 {
        _StringStorage.create(initializingFrom: $0, andAppending: bufPtr)
      }

      // TODO(UTF8): Track known ascii
      self = _StringGuts(storage)
      return
    }

    unimplemented_utf8()
  }
}

// C String interop
extension _StringGuts {
  @inlinable @inline(__always) // fast-path: already C-string compatible
  internal func withCString<Result>(
    _ body: (UnsafePointer<Int8>) throws -> Result
  ) rethrows -> Result {
    if _slowPath(!_object.isFastZeroTerminated) {
      return try _slowWithCString(body)
    }

    return try self.withFastUTF8 {
      let ptr = $0._asCChar.baseAddress._unsafelyUnwrappedUnchecked
      return try body(ptr)
    }
  }

  @inlinable @inline(__always) // fast-path: already C-string compatible
  internal func withCString<Result>(
    _ body: (UnsafePointer<Int8>) throws -> Result,
    _ range: Range<Int>
  ) rethrows -> Result {
    if _slowPath(!_object.isFastZeroTerminated) {
      return try _slowWithCString(body, range)
    }

    return try self.withFastUTF8 {
      let ptr =
        $0[range]._rebased._asCChar.baseAddress._unsafelyUnwrappedUnchecked
      return try body(ptr)
    }
  }

  @inline(never) // slow-path
  @usableFromInline
  internal func _slowWithCString<Result>(
    _ body: (UnsafePointer<Int8>) throws -> Result
  ) rethrows -> Result {
    _sanityCheck(!_object.isFastZeroTerminated)
    return try String(self).utf8CString.withUnsafeBufferPointer {
      let ptr = $0.baseAddress._unsafelyUnwrappedUnchecked
      return try body(ptr)
    }
  }

  @inline(never) // slow-path
  @usableFromInline
  internal func _slowWithCString<Result>(
    _ body: (UnsafePointer<Int8>) throws -> Result,
    _ range: Range<Int>
  ) rethrows -> Result {
    _sanityCheck(!_object.isFastZeroTerminated)

    return try String(self).utf8CString.withUnsafeBufferPointer {
      let ptr = $0[range]._rebased.baseAddress._unsafelyUnwrappedUnchecked
      return try body(ptr)
    }
  }

}


