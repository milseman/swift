
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
  fatalError()

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


  // Next, try to find the desired invalid ranges
  do {
    try invalidUTF8.withUnsafeBufferView {
      try UTF8.validate($0)
    }
  } catch let error as UTF8.CollectionDecodingError<Int> {
    let lower = asciiStr.utf8.count
    expectEqual(lower, error.range.lowerBound)
    expectEqual(lower+1, error.range.upperBound)
  } catch {
    fatalError()
  }
}

UnicodeProcessing.test("UVUBP: Raw bytes") {
  
}




runAllTests()

