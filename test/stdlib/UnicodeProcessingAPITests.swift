
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

UnicodeProcessing.test("true-fail") {
  expectFalse(UTF8.returnTrue())
}


UnicodeProcessing.test("foo") {
  UTF8.foo()
}


runAllTests()

