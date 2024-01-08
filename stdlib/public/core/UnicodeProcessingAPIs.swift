

extension UTF8 {
  public static func crash() {
    fatalError("running foo")
  }

  public static func returnTrue() -> Bool {
    true
  }

  public static func returnFalse() -> Bool {
    false
  }
}

// HACK: quick shim for testing
@frozen
public struct UnsafeBufferView {
  public var baseAddress: UnsafeRawPointer
  public var count: Int
}
extension UnsafeBufferView {
  public init(_ bufPtr: UnsafeRawBufferPointer) {
    self.init(
      baseAddress: bufPtr.baseAddress!, count: bufPtr.count)
  }
}

extension Collection<UInt8> {
  // HACK: quick shim for testing
  public func withUnsafeBufferView<T>(
    _ f: (UnsafeBufferView) throws -> T
  ) rethrows -> T {
    try Array(self).withUnsafeBytes {
      try f(.init($0))
    }
  }
}


extension Unicode.UTF8 {
  public enum DecodingError: Error {
    case todo
  }

  public static func validate(
    _ bytes: UnsafeBufferView
  ) throws {
    let res = bytes.baseAddress.withMemoryRebound(to: UInt8.self,  capacity: bytes.count) { ptr in
      validateUTF8(.init(start: ptr, count: bytes.count))
    }
    switch res {

    case .success(_): return
    case .error(_):
      throw UTF8.DecodingError.todo
    }
  }
}

