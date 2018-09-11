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
  static var breadcrumbStride: Int { return 64 }

  var utf16Length: Int

  // TODO: does this need to be a pair?.... Can we be smaller than Int?
  var utf16ToIndex: [String.Index]

  // TODO: Does this need to be inout, unique, or how will we be enforcing
  // atomicity?
  init(_ str: String) {
    self.utf16ToIndex = []
    if str.isEmpty {
      self.utf16Length = 0
      return
    }

    let stride = _StringBreadcrumbs.breadcrumbStride

    self.utf16ToIndex.reserveCapacity(
      (str._guts.count / 3) / stride)

    // TODO(UTF8 perf): More efficient implementation

    let utf16 = str.utf16

    var i = 1
    var curIdx = utf16.index(after: utf16.startIndex)
    while curIdx != utf16.endIndex {
      if i % stride == 0 { //i.isMultiple(of: stride) {
        self.utf16ToIndex.append(curIdx)
      }
      i = i &+ 1
      curIdx = utf16.index(after: curIdx)
    }

    self.utf16Length = i

    _sanityCheck(self.utf16Length == utf16.count)
    if self.utf16ToIndex.isEmpty {
      // Last offset is stride-1, so we don't allocate an array for any length
      // up to and including stride.
      _sanityCheck(self.utf16Length <= stride)
    } else {
      _sanityCheck(self.utf16ToIndex.count == (self.utf16Length-1) / stride)
    }
  }
}

// Tail-allocate from StringStorage rather than using the header...
//
// Checking the pointer should be fine, if it's set then off to the races...
//
// Reserve bits/flags in _StringStorage...
//
// Create the new structure, then do a memory fence, compare-and-swap
//
// Custom destructor for _StringStorage checks bit to know if there's an extra
// tail allocation to destruct...
//
// Follow pattern from _stdlib_atomicInitializeARCRef for CAS...
//
//
