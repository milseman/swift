// RUN: %target-run-stdlib-swift
// REQUIRES: executable_test

// Some targetted tests for the breadcrumbs path. There is some overlap with
// UTF16View tests for huge strings, but we want a simpler suite that targets
// some corner cases specifically.

import Swift
import StdlibUnittest

let smallASCII = "abcdefg"
let smallUnicode = "abéÏ𓀀"
let largeASCII = "012345678901234567890"
let largeUnicode = "abéÏ012345678901234567890𓀀"
let emoji = "😀😃🤢🤮👩🏿‍🎤🧛🏻‍♂️🧛🏻‍♂️👩‍👩‍👦‍👦"
let chinese = "Swift 是面向 Apple 平台的编程语言，功能强大且直观易用，而本次更新对其进行了全面优化。"

let largeString: String = {
  var result = ""
  result += smallASCII
  result += smallUnicode
  result += largeASCII
  result += chinese
  result += largeUnicode
  result += emoji
  result += smallASCII
  result += result.reversed()
  return result
}()

extension FixedWidthInteger {
  var hexStr: String { return "0x\(String(self, radix: 16, uppercase: true))" }
}

let StringBreadcrumbsTests = TestSuite("StringBreadcrumbsTests")

func validateBreadcrumbs(_ str: String) {
  var utf16CodeUnits = Array(str.utf16)
  var utf16Indices = Array(str.utf16.indices)
  var outputBuffer = Array<UInt16>(repeating: 0, count: utf16CodeUnits.count)

  for i in 0..<(utf16CodeUnits.count-1) {
    for j in (i+1)..<utf16CodeUnits.count {
      let range = Range(uncheckedBounds: (i, j))

      let indexRange = str._toUTF16Indices(range)
      // Range<String.Index> <=> Range<Int>
      expectEqual(utf16Indices[i], indexRange.lowerBound)
      expectEqual(utf16Indices[j], indexRange.upperBound)
      expectEqualSequence(
        utf16CodeUnits[i..<j], str.utf16[indexRange])
      let roundTripOffsets = str._toUTF16Offsets(indexRange)
      expectEqualSequence(range, roundTripOffsets)

      // Single Int <=> String.Index
      expectEqual(indexRange.lowerBound, str._toUTF16Index(i))
      expectEqual(indexRange.upperBound, str._toUTF16Index(j))
      expectEqual(i, str._toUTF16Offset(indexRange.lowerBound))
      expectEqual(j, str._toUTF16Offset(indexRange.upperBound))

      // Copy characters
      outputBuffer.withUnsafeMutableBufferPointer {
        str._copyUTF16CodeUnits(into: $0, range: range)
      }
      expectEqualSequence(utf16CodeUnits[i..<j], outputBuffer[..<range.count])
    }
  }
}

StringBreadcrumbsTests.test("largeString") {
  validateBreadcrumbs(largeString)
}

// Test various boundary conditions with surrogate pairs aligning or not
// aligning
StringBreadcrumbsTests.test("surrogates-heavy") {
  let nonBMP = String(repeating: "𓀀", count: 1 + (64 / 2))

  // Mis-align the hieroglyphics by 1,2,3 UTF-8 and UTF-16 code units
  validateBreadcrumbs(nonBMP)
  validateBreadcrumbs("a" + nonBMP)
  validateBreadcrumbs("ab" + nonBMP)
  validateBreadcrumbs("abc" + nonBMP)
  validateBreadcrumbs("é" + nonBMP)
  validateBreadcrumbs("是" + nonBMP)
  validateBreadcrumbs("aé" + nonBMP)
}

// TODO(String testing): test breadcrumb validity after mutation

runAllTests()
