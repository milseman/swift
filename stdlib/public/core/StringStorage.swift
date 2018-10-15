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

// TODO(UTF8): We can drop the nonobjc annotations soon

@_fixed_layout
@usableFromInline
@objc
internal class _AbstractStringStorage: _SwiftNativeNSString, _NSStringCore {
  // Abstract interface
  internal var asString: String { get { Builtin.unreachable() } }
  internal var count: Int { get { Builtin.unreachable() } }
  internal func getOrComputeBreadcrumbs() -> _StringBreadcrumbs {
    Builtin.unreachable()
  }
}

// ObjC interfaces
#if _runtime(_ObjC)
extension _AbstractStringStorage {
  @objc(length)
  final internal var length: Int { return asString.utf16.count }

  @objc(characterAtIndex:)
  final func character(at offset: Int) -> UInt16 {
    let str = asString
    return str.utf16[str._toUTF16Index(offset)]
  }

  @objc(getCharacters:range:)
  final func getCharacters(
   _ buffer: UnsafeMutablePointer<UInt16>,
   range aRange: _SwiftNSRange) {
    _precondition(aRange.location >= 0 && aRange.length >= 0,
      "Range out of bounds")
    _precondition(aRange.location + aRange.length <= Int(count),
      "Range out of bounds")

    let range = Range(
      uncheckedBounds: (aRange.location, aRange.location+aRange.length))
    let str = asString
    let slice = str.utf16[str._toUTF16Indices(range)]
    let outputBufPtr = UnsafeMutableBufferPointer(
      start: buffer, count: range.count)

    let _ = slice._copyContents(initializing: outputBufPtr)
  }

  @objc(_fastCharacterContents)
  final func _fastCharacterContents() -> UnsafePointer<UInt16>? {
    return nil
  }

  @objc(_fastCStringContents)
  final func _fastCStringContents() -> UnsafePointer<CChar>? {
    if let native = self as? _StringStorage {
      // FIXME(UTF8): Need to check for interior nul
      return native.start._asCChar
    }

    // TODO(UTF8 perf): shared from literals are nul-terminated...

    return nil
  }

  @objc(copyWithZone:)
  @usableFromInline
  final func copy(with zone: _SwiftNSZone?) -> AnyObject {
    // While _StringStorage instances aren't immutable in general,
    // mutations may only occur when instances are uniquely referenced.
    // Therefore, it is safe to return self here; any outstanding Objective-C
    // reference will make the instance non-unique.
    return self
  }
}
#endif // _runtime(_ObjC)


//
// TODO(UTF8 merge): Documentation about the runtime layout of these instances,
// which is growing in complexity. For now, the second trailing allocation holds
// an Optional<_StringBreadcrumbs>.
//

@_fixed_layout
@usableFromInline
final internal class _StringStorage: _AbstractStringStorage {
  // The capacity of our allocation. Note that this includes the nul-terminator,
  // which is not available for overridding.
  @nonobjc
  @usableFromInline
  internal var _realCapacityAndFlags: Int

  @nonobjc
  @usableFromInline
  internal var _countAndFlags: Int

  @nonobjc
  @inlinable
  override internal var count: Int {
    @inline(__always) get { return _countAndFlags & _StringObject.countMask }
  }

  @nonobjc
  override internal var asString: String {
    @inline(__always) get { return String(_StringGuts(self)) }
  }

  @nonobjc
  private init(_doNotCallMe: ()) {
    _sanityCheckFailure("Use the create method")
  }

  deinit {
    _breadcrumbsAddress.deinitialize(count: 1)
  }
}

// Determine the actual number of code unit capacity to request from malloc. We
// round up the nearest multiple of 8 that isn't a mulitple of 16, to fully
// utilize malloc's small buckets while accounting for the trailing
// _StringBreadCrumbs.
//
// NOTE: We may still under-utilize the spare bytes from the actual allocation
// for Strings ~1KB or larger, though at this point we're well into our growth
// curve.
private func determineCodeUnitCapacity(_ desiredCapacity: Int) -> Int {
#if arch(i386) || arch(arm)
    unimplemented_utf8_32bit()
#else

  // Bigger than _SmallString, and we need 1 extra for nul-terminator
  let minCap = 1 + Swift.max(desiredCapacity, _SmallString.capacity)
  _sanityCheck(minCap < 0x1_0000_0000_0000, "max 48-bit length")

  // Round up to the nearest multiple of 8 that isn't also a multiple of 16
  let capacity = ((minCap + 7) & -16) + 8
  _sanityCheck(
    capacity > desiredCapacity && capacity % 8 == 0 && capacity % 16 != 0)
  return capacity

#endif
}

// Creation
extension _StringStorage {
  @_effects(releasenone)
  @nonobjc
  private static func create(capacity: Int, count: Int = 0) -> _StringStorage {
    _sanityCheck(capacity >= count)

    let realCapacity = determineCodeUnitCapacity(capacity)
    _sanityCheck(realCapacity > capacity)
    return _StringStorage.create(
      realCodeUnitCapacity: realCapacity, count: count)
  }

  @inline(never) // rdar://problem/44542202
  @_effects(releasenone)
  @nonobjc
  private static func create(
    realCodeUnitCapacity: Int, count: Int = 0
  ) -> _StringStorage {
    let storage = Builtin.allocWithTailElems_2(
      _StringStorage.self,
      realCodeUnitCapacity._builtinWordValue, UInt8.self,
      1._builtinWordValue, Optional<_StringBreadcrumbs>.self)

    // TODO(UTF8 perf): Use or document flags
    storage._realCapacityAndFlags = realCodeUnitCapacity
    storage._countAndFlags = count

    storage._breadcrumbsAddress.initialize(to: nil)
    storage.terminator.pointee = 0 // nul-terminated
    storage._invariantCheck()
    return storage
  }

  @_effects(releasenone)
  @nonobjc
  internal static func create(
    initializingFrom bufPtr: UnsafeBufferPointer<UInt8>, capacity: Int
  ) -> _StringStorage {
    _sanityCheck(capacity >= bufPtr.count)
    let storage = _StringStorage.create(
      capacity: capacity, count: bufPtr.count)
    let addr = bufPtr.baseAddress._unsafelyUnwrappedUnchecked
    storage.mutableStart.initialize(from: addr, count: bufPtr.count)
    storage._invariantCheck()
    return storage
  }

  @_effects(releasenone)
  @nonobjc
  internal static func create(
    initializingFrom bufPtr: UnsafeBufferPointer<UInt8>
  ) -> _StringStorage {
    return _StringStorage.create(
      initializingFrom: bufPtr, capacity: bufPtr.count)
  }
}

// Usage
extension _StringStorage {
  @nonobjc
  @inlinable
  internal var mutableStart: UnsafeMutablePointer<UInt8> {
    @inline(__always) get {
      return UnsafeMutablePointer(Builtin.projectTailElems(self, UInt8.self))
    }
  }
  @nonobjc
  private var mutableEnd: UnsafeMutablePointer<UInt8> {
    @inline(__always) get { return mutableStart + count }
  }

  @nonobjc
  @inlinable
  internal var start: UnsafePointer<UInt8> {
    @inline(__always) get { return UnsafePointer(mutableStart) }
  }

  @nonobjc
  private final var end: UnsafePointer<UInt8> {
    @inline(__always) get { return UnsafePointer(mutableEnd) }
  }

  // Point to the nul-terminator
  @nonobjc
  private final var terminator: UnsafeMutablePointer<UInt8> {
    @inline(__always) get { return mutableEnd }
  }

  @nonobjc
  private var codeUnits: UnsafeBufferPointer<UInt8> {
    @inline(__always) get {
      return UnsafeBufferPointer(start: start, count: count)
    }
  }

  @nonobjc
  // @opaque
  internal var _breadcrumbsAddress: UnsafeMutablePointer<_StringBreadcrumbs?> {
    let raw = Builtin.getTailAddr_Word(
      start._rawValue,
      realCapacity._builtinWordValue,
      UInt8.self,
      Optional<_StringBreadcrumbs>.self)
    return UnsafeMutablePointer(raw)
  }

  // The total capacity available for code units. Note that this excludes the
  // required nul-terminator
  @nonobjc
  internal var capacity: Int {
    return realCapacity &- 1
  }

  // The total capacity available for code units. Note that this excludes the
  // required nul-terminator
  @nonobjc
  private var realCapacity: Int {
    return _realCapacityAndFlags & _StringObject.countMask
  }

  // The unused capacity available for appending. Note that this excludes the
  // required nul-terminator.
  //
  // NOTE: Callers who wish to mutate this storage should enfore nul-termination
  @nonobjc
  private var unusedStorage: UnsafeMutableBufferPointer<UInt8> {
    @inline(__always) get {
      return UnsafeMutableBufferPointer(
        start: mutableEnd, count: capacity)
    }
  }

  // The capacity available for appending. Note that this excludes the required
  // nul-terminator
  @nonobjc
  internal var unusedCapacity: Int {
    get { return realCapacity &- count &- 1 }
  }

  #if !INTERNAL_CHECKS_ENABLED
  @nonobjc @inline(__always) internal func _invariantCheck() {}
  #else
  @nonobjc @inline(never) @_effects(releasenone)
  internal func _invariantCheck() {
    let rawSelf = UnsafeRawPointer(Builtin.bridgeToRawPointer(self))
    let rawStart = UnsafeRawPointer(start)
    _sanityCheck(unusedCapacity >= 0)
    _sanityCheck(rawSelf + Int(_StringObject.nativeBias) == rawStart)
    _sanityCheck(self.realCapacity > self.count, "no room for nul-terminator")
    _sanityCheck(self.terminator.pointee == 0, "not nul terminated")
  }
  #endif // INTERNAL_CHECKS_ENABLED
}

// Appending
extension _StringStorage {
  @nonobjc
  internal func appendInPlace(_ other: UnsafeBufferPointer<UInt8>) {
    _sanityCheck(self.capacity >= other.count)
    let oldTerminator = self.terminator

    let srcAddr = other.baseAddress._unsafelyUnwrappedUnchecked
    let srcCount = other.count
    self.mutableEnd.initialize(from: srcAddr, count: srcCount)
    self._countAndFlags += srcCount

    _sanityCheck(oldTerminator + other.count == self.terminator)
    self.terminator.pointee = 0

    _invariantCheck()
  }

  @nonobjc
  internal func appendInPlace<Iter: IteratorProtocol>(
    _ other: inout Iter
  ) where Iter.Element == UInt8 {
    let oldTerminator = self.terminator
    var srcCount = 0
    while let cu = other.next() {
      _sanityCheck(self.unusedCapacity >= 1)
      unusedStorage[srcCount] = cu
      srcCount += 1
    }
    self._countAndFlags += srcCount

    _sanityCheck(oldTerminator + srcCount == self.terminator)
    self.terminator.pointee = 0

    _invariantCheck()
  }

  @nonobjc
  internal func clear() {
    // TODO(UTF8 perf flags): Clear or restore flags
    self._countAndFlags &= ~_StringObject.countMask
  }
}

// Removing
extension _StringStorage {
  @nonobjc
  internal func remove(from lower: Int, to upper: Int) {
    _sanityCheck(lower <= upper)

    let lowerPtr = mutableStart + lower
    let upperPtr = mutableStart + upper
    let tailCount = mutableEnd - upperPtr
    lowerPtr.moveInitialize(from: upperPtr, count: tailCount)
    self._countAndFlags -= (upper &- lower)
    _invariantCheck()
  }
}

// For bridging literals
//
// TODO(UTF8): Unify impls with _StringStorage
//
@_fixed_layout
@usableFromInline
final internal class _SharedStringStorage: _AbstractStringStorage {
  @nonobjc
  @usableFromInline
  internal var owner: AnyObject?

  @nonobjc
  @usableFromInline
  internal var contents: UnsafeBufferPointer<UInt8>

  @nonobjc
  internal var _breadcrumbs: _StringBreadcrumbs?

  @nonobjc
  @usableFromInline
  internal var start: UnsafePointer<UInt8> {
    return contents.baseAddress._unsafelyUnwrappedUnchecked
  }

  @nonobjc
  @usableFromInline
  override internal var count: Int { return contents.count }

  @nonobjc
  internal init(owner: AnyObject, contents bufPtr: UnsafeBufferPointer<UInt8>) {
    self.owner = owner
    self.contents = bufPtr
    super.init()
    self._invariantCheck()
  }

  @nonobjc
  internal init(immortal bufPtr: UnsafeBufferPointer<UInt8>) {
    self.owner = nil
    self.contents = bufPtr
    super.init()
    self._invariantCheck()
  }

  @nonobjc
  override internal var asString: String { return String(_StringGuts(self)) }
}

extension _SharedStringStorage {
  #if !INTERNAL_CHECKS_ENABLED
  @nonobjc @inline(__always) internal func _invariantCheck() {}
  #else
  @nonobjc @inline(never) @_effects(releasenone)
  internal func _invariantCheck() {
  }
  #endif // INTERNAL_CHECKS_ENABLED
}


