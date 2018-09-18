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


// @opaque
internal final class _StringBreadcrumbs {
  static var breadcrumbStride: Int { return 32 }

  var utf16Length: Int

  // TODO: does this need to be a pair?.... Can we be smaller than Int?
  var crumbs: [String.Index]

  // TODO: Does this need to be inout, unique, or how will we be enforcing
  // atomicity?
  init(_ str: String) {
    let stride = _StringBreadcrumbs.breadcrumbStride

    self.crumbs = []

    if str.isEmpty {
      self.utf16Length = 0
      return
    }

    self.crumbs.reserveCapacity(
      (str._guts.count / 3) / stride)

    // TODO(UTF8 perf): More efficient implementation

    let utf16 = str.utf16
    var i = 0
    var curIdx = utf16.startIndex
    while curIdx != utf16.endIndex {
      if i % stride == 0 { //i.isMultiple(of: stride) {
        self.crumbs.append(curIdx)
      }
      i = i &+ 1
      curIdx = utf16.index(after: curIdx)
    }
    self.utf16Length = i
    _sanityCheck(self.crumbs.count == 1 + ((self.utf16Length-1) / stride))
  }
}

extension _StringBreadcrumbs {
  var stride: Int {
    @inline(__always) get { return _StringBreadcrumbs.breadcrumbStride }
  }

  // Return the stored (utf16Offset, Index) closest to the given index
  internal func lowerBound(_ i : String.Index) -> (offset: Int, String.Index) {
    // FIXME: This is... probably off-by-one

    // TODO: Bisect for large input, or at very least search the more narrow
    // range of (stride * encodedOffset / 3)...(stride * encodedOffset).

    guard let idx = crumbs.lastIndex(where: { i >= $0 }) else {
      return (0, String.Index(encodedOffset: 0))
    }

    fatalError("Incorrect implementation")
    return (idx * stride, crumbs[idx])
  }
}

extension _StringGuts {
  @_effects(releasenone)
  internal func getBreadcrumbsPtr() -> UnsafePointer<_StringBreadcrumbs> {
    _sanityCheck(hasBreadcrumbs)

    let mutPtr: UnsafeMutablePointer<_StringBreadcrumbs?>
    if hasNativeStorage {
      mutPtr = _object.nativeStorage._breadcrumbsAddress
    } else {
      mutPtr = UnsafeMutablePointer(
        Builtin.addressof(&_object.sharedStorage._breadcrumbs))
    }

    if _slowPath(mutPtr.pointee == nil) {
      populateBreadcrumbs(mutPtr)
    }

    _sanityCheck(mutPtr.pointee != nil)
    return UnsafePointer(mutPtr)
  }

  @inline(never) // slow-path
  @_effects(releasenone)
  internal func populateBreadcrumbs(
    _ mutPtr: UnsafeMutablePointer<_StringBreadcrumbs?>
  ) {
    // Thread-safe compare-and-swap
    let crumbs = _StringBreadcrumbs(String(self))
    _stdlib_atomicInitializeARCRef(
      object: UnsafeMutablePointer(mutPtr), desired: crumbs)
  }
}
