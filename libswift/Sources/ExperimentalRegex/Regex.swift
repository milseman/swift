import ExperimentalRegexBridging

public func experimental_regex_strawperson(
  _ s: UnsafePointer<CChar>
) -> UnsafePointer<CChar> {
  let str = "Hello, \(String(cString:s))"
  let count = str.utf8.count + 1
  return str.withCString {
    assert($0[count-1] == 0)
    let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: count)
    ptr.initialize(from: $0, count: count)
    return UnsafePointer(ptr)
  }
}

public func register() {
  registerSwiftPasses
}

public func registerParser() {
  Parser_registerParseRegexpFn({ experimental_regex_strawperson })
}
