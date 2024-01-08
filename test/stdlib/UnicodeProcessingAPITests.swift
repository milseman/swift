
// RUN: %target-run-stdlib-swift
// REQUIRES: executable_test

import Swift
import StdlibUnittest


var UnicodeProcessing = TestSuite("UnicodeProcessing")

UnicodeProcessing.test("true") {
  expectTrue(UTF8.returnTrue())
}

UnicodeProcessing.test("false") {
  expectFalse(UTF8.returnFalse())
}

// UnicodeProcessing.test("true-fail") {
//   expectFalse(UTF8.returnTrue())
// }


// UnicodeProcessing.test("crash") {
//   UTF8.crash()
// }

UnicodeProcessing.test("validate") {
  var asciiStr = "abcdefg ./?\n\r\n123$"

  var invalidUTF8 =
    Array(asciiStr.utf8) + [0xC0, 0x0A] + Array(asciiStr.utf8)

  let nonNil = try? asciiStr.utf8.withUnsafeBufferView {
    try UTF8.validate($0)
  }
  expectNotNil(nonNil)

  let shouldBeNil = try? invalidUTF8.withUnsafeBufferView {
    try UTF8.validate($0)
  }
  expectNil(shouldBeNil)
}



runAllTests()

