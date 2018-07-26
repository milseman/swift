//===--- Print.swift ------------------------------------------------------===//
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

/// Writes the textual representations of the given items into the standard
/// output.
///
/// You can pass zero or more items to the `print(_:separator:terminator:)`
/// function. The textual representation for each item is the same as that
/// obtained by calling `String(item)`. The following example prints a string,
/// a closed range of integers, and a group of floating-point values to
/// standard output:
///
///     print("One two three four five")
///     // Prints "One two three four five"
///
///     print(1...5)
///     // Prints "1...5"
///
///     print(1.0, 2.0, 3.0, 4.0, 5.0)
///     // Prints "1.0 2.0 3.0 4.0 5.0"
///
/// To print the items separated by something other than a space, pass a string
/// as `separator`.
///
///     print(1.0, 2.0, 3.0, 4.0, 5.0, separator: " ... ")
///     // Prints "1.0 ... 2.0 ... 3.0 ... 4.0 ... 5.0"
///
/// The output from each call to `print(_:separator:terminator:)` includes a
/// newline by default. To print the items without a trailing newline, pass an
/// empty string as `terminator`.
///
///     for n in 1...5 {
///         print(n, terminator: "")
///     }
///     // Prints "12345"
///
/// - Parameters:
///   - items: Zero or more items to print.
///   - separator: A string to print between each item. The default is a single
///     space (`" "`).
///   - terminator: The string to print after all items have been printed. The
///     default is a newline (`"\n"`).
@inline(never)
public func print(
  _ items: Any...,
  separator: String = " ",
  terminator: String = "\n"
) {
  if let hook = _playgroundPrintHook {
    var output = _TeeStream(left: "", right: _Stdout())
    _print(
      items, separator: separator, terminator: terminator, to: &output)
    hook(output.left)
  }
  else {
    var output = _Stdout()
    _print(
      items, separator: separator, terminator: terminator, to: &output)
  }
}

/// Writes the textual representations of the given items most suitable for
/// debugging into the standard output.
///
/// You can pass zero or more items to the
/// `debugPrint(_:separator:terminator:)` function. The textual representation
/// for each item is the same as that obtained by calling
/// `String(reflecting: item)`. The following example prints the debugging
/// representation of a string, a closed range of integers, and a group of
/// floating-point values to standard output:
///
///     debugPrint("One two three four five")
///     // Prints "One two three four five"
///
///     debugPrint(1...5)
///     // Prints "ClosedRange(1...5)"
///
///     debugPrint(1.0, 2.0, 3.0, 4.0, 5.0)
///     // Prints "1.0 2.0 3.0 4.0 5.0"
///
/// To print the items separated by something other than a space, pass a string
/// as `separator`.
///
///     debugPrint(1.0, 2.0, 3.0, 4.0, 5.0, separator: " ... ")
///     // Prints "1.0 ... 2.0 ... 3.0 ... 4.0 ... 5.0"
///
/// The output from each call to `debugPrint(_:separator:terminator:)` includes
/// a newline by default. To print the items without a trailing newline, pass
/// an empty string as `terminator`.
///
///     for n in 1...5 {
///         debugPrint(n, terminator: "")
///     }
///     // Prints "12345"
///
/// - Parameters:
///   - items: Zero or more items to print.
///   - separator: A string to print between each item. The default is a single
///     space (`" "`).
///   - terminator: The string to print after all items have been printed. The
///     default is a newline (`"\n"`).
@inline(never)
public func debugPrint(
  _ items: Any...,
  separator: String = " ",
  terminator: String = "\n") {
  if let hook = _playgroundPrintHook {
    var output = _TeeStream(left: "", right: _Stdout())
    _debugPrint(
      items, separator: separator, terminator: terminator, to: &output)
    hook(output.left)
  }
  else {
    var output = _Stdout()
    _debugPrint(
      items, separator: separator, terminator: terminator, to: &output)
  }
}

/// Writes the textual representations of the given items into the given output
/// stream.
///
/// You can pass zero or more items to the `print(_:separator:terminator:to:)`
/// function. The textual representation for each item is the same as that
/// obtained by calling `String(item)`. The following example prints a closed
/// range of integers to a string:
///
///     var range = "My range: "
///     print(1...5, to: &range)
///     // range == "My range: 1...5\n"
///
/// To print the items separated by something other than a space, pass a string
/// as `separator`.
///
///     var separated = ""
///     print(1.0, 2.0, 3.0, 4.0, 5.0, separator: " ... ", to: &separated)
///     // separated == "1.0 ... 2.0 ... 3.0 ... 4.0 ... 5.0\n"
///
/// The output from each call to `print(_:separator:terminator:to:)` includes a
/// newline by default. To print the items without a trailing newline, pass an
/// empty string as `terminator`.
///
///     var numbers = ""
///     for n in 1...5 {
///         print(n, terminator: "", to: &numbers)
///     }
///     // numbers == "12345"
///
/// - Parameters:
///   - items: Zero or more items to print.
///   - separator: A string to print between each item. The default is a single
///     space (`" "`).
///   - terminator: The string to print after all items have been printed. The
///     default is a newline (`"\n"`).
///   - output: An output stream to receive the text representation of each
///     item.
@inlinable // FIXME(sil-serialize-all)
@inline(__always)
public func print<Target : TextOutputStream>(
  _ items: Any...,
  separator: String = " ",
  terminator: String = "\n",
  to output: inout Target
) {
  _print(items, separator: separator, terminator: terminator, to: &output)
}

/// Writes the textual representations of the given items most suitable for
/// debugging into the given output stream.
///
/// You can pass zero or more items to the
/// `debugPrint(_:separator:terminator:to:)` function. The textual
/// representation for each item is the same as that obtained by calling
/// `String(reflecting: item)`. The following example prints a closed range of
/// integers to a string:
///
///     var range = "My range: "
///     debugPrint(1...5, to: &range)
///     // range == "My range: ClosedRange(1...5)\n"
///
/// To print the items separated by something other than a space, pass a string
/// as `separator`.
///
///     var separated = ""
///     debugPrint(1.0, 2.0, 3.0, 4.0, 5.0, separator: " ... ", to: &separated)
///     // separated == "1.0 ... 2.0 ... 3.0 ... 4.0 ... 5.0\n"
///
/// The output from each call to `debugPrint(_:separator:terminator:to:)`
/// includes a newline by default. To print the items without a trailing
/// newline, pass an empty string as `terminator`.
///
///     var numbers = ""
///     for n in 1...5 {
///         debugPrint(n, terminator: "", to: &numbers)
///     }
///     // numbers == "12345"
///
/// - Parameters:
///   - items: Zero or more items to print.
///   - separator: A string to print between each item. The default is a single
///     space (`" "`).
///   - terminator: The string to print after all items have been printed. The
///     default is a newline (`"\n"`).
///   - output: An output stream to receive the text representation of each
///     item.
@inlinable // FIXME(sil-serialize-all)
@inline(__always)
public func debugPrint<Target : TextOutputStream>(
  _ items: Any...,
  separator: String = " ",
  terminator: String = "\n",
  to output: inout Target
) {
  _debugPrint(
    items, separator: separator, terminator: terminator, to: &output)
}

@usableFromInline
@inline(never)
internal func _print<Target : TextOutputStream>(
  _ items: [Any],
  separator: String = " ",
  terminator: String = "\n",
  to output: inout Target
) {
  var prefix = ""
  output._lock()
  defer { output._unlock() }
  for item in items {
    output.write(prefix)
    _print_unlocked(item, &output)
    prefix = separator
  }
  output.write(terminator)
}

@usableFromInline
@inline(never)
internal func _debugPrint<Target : TextOutputStream>(
  _ items: [Any],
  separator: String = " ",
  terminator: String = "\n",
  to output: inout Target
) {
  var prefix = ""
  output._lock()
  defer { output._unlock() }
  for item in items {
    output.write(prefix)
    _debugPrint_unlocked(item, &output)
    prefix = separator
  }
  output.write(terminator)
}

//===----------------------------------------------------------------------===//
// Default (ad-hoc) printing
//===----------------------------------------------------------------------===//

@usableFromInline // FIXME(sil-serialize-all)
@_silgen_name("swift_EnumCaseName")
internal func _getEnumCaseName<T>(_ value: T) -> UnsafePointer<CChar>?

@usableFromInline // FIXME(sil-serialize-all)
@_silgen_name("swift_OpaqueSummary")
internal func _opaqueSummary(_ metadata: Any.Type) -> UnsafePointer<CChar>?

/// Do our best to print a value that cannot be printed directly.
@inline(never) // slow-path
@_semantics("optimize.sil.specialize.generic.never")
internal func _adHocPrint_unlocked<T, TargetStream: TextOutputStream>(
    _ value: T, _ mirror: Mirror, _ target: inout TargetStream,
    isDebugPrint: Bool
) {
  func printTypeName(_ type: Any.Type) {
    // Print type names without qualification, unless we're debugPrint'ing.
    target.write(_typeName(type, qualified: isDebugPrint))
  }

  if let displayStyle = mirror.displayStyle {
    switch displayStyle {
      case .optional:
        if let child = mirror.children.first {
          _debugPrint_unlocked(child.1, &target)
        } else {
          _debugPrint_unlocked("nil", &target)
        }
      case .tuple:
        target.write("(")
        var first = true
        for (label, value) in mirror.children {
          if first {
            first = false
          } else {
            target.write(", ")
          }

          if let label = label {
            if !label.isEmpty && label[label.startIndex] != "." {
              target.write(label)
              target.write(": ")
            }
          }

          _debugPrint_unlocked(value, &target)
        }
        target.write(")")
      case .struct:
        printTypeName(mirror.subjectType)
        target.write("(")
        var first = true
        for (label, value) in mirror.children {
          if let label = label {
            if first {
              first = false
            } else {
              target.write(", ")
            }
            target.write(label)
            target.write(": ")
            _debugPrint_unlocked(value, &target)
          }
        }
        target.write(")")
      case .enum:
        if let cString = _getEnumCaseName(value),
            let caseName = String(validatingUTF8: cString) {
          // Write the qualified type name in debugPrint.
          if isDebugPrint {
            printTypeName(mirror.subjectType)
            target.write(".")
          }
          target.write(caseName)
        } else {
          // If the case name is garbage, just print the type name.
          printTypeName(mirror.subjectType)
        }
        if let (_, value) = mirror.children.first {
          if Mirror(reflecting: value).displayStyle == .tuple {
            _debugPrint_unlocked(value, &target)
          } else {
            target.write("(")
            _debugPrint_unlocked(value, &target)
            target.write(")")
          }
        }
      default:
        target.write(_typeName(mirror.subjectType))
    }
  } else if let metatypeValue = value as? Any.Type {
    // Metatype
    printTypeName(metatypeValue)
  } else {
    // Fall back to the type or an opaque summary of the kind
    if let cString = _opaqueSummary(mirror.subjectType),
        let opaqueSummary = String(validatingUTF8: cString) {
      target.write(opaqueSummary)
    } else {
      target.write(_typeName(mirror.subjectType, qualified: true))
    }
  }
}

@usableFromInline
@inline(never)
@_semantics("optimize.sil.specialize.generic.never")
internal func _print_unlocked<T, TargetStream: TextOutputStream>(
  _ value: T, _ target: inout TargetStream
) {
  // Optional has no representation suitable for display; therefore,
  // values of optional type should be printed as a debug
  // string. Check for Optional first, before checking protocol
  // conformance below, because an Optional value is convertible to a
  // protocol if its wrapped type conforms to that protocol.
  if _isOptional(type(of: value)) {
    let debugPrintable = value as! CustomDebugStringConvertible
    debugPrintable.debugDescription.write(to: &target)
    return
  }
  if case let streamableObject as TextOutputStreamable = value {
    streamableObject.write(to: &target)
    return
  }

  if case let printableObject as CustomStringConvertible = value {
    printableObject.description.write(to: &target)
    return
  }

  if case let debugPrintableObject as CustomDebugStringConvertible = value {
    debugPrintableObject.debugDescription.write(to: &target)
    return
  }

  let mirror = Mirror(reflecting: value)
  _adHocPrint_unlocked(value, mirror, &target, isDebugPrint: false)
}

//===----------------------------------------------------------------------===//
// `debugPrint`
//===----------------------------------------------------------------------===//

@_semantics("optimize.sil.specialize.generic.never")
@inline(never)
public func _debugPrint_unlocked<T, TargetStream: TextOutputStream>(
    _ value: T, _ target: inout TargetStream
) {
  if let debugPrintableObject = value as? CustomDebugStringConvertible {
    debugPrintableObject.debugDescription.write(to: &target)
    return
  }

  if let printableObject = value as? CustomStringConvertible {
    printableObject.description.write(to: &target)
    return
  }

  if let streamableObject = value as? TextOutputStreamable {
    streamableObject.write(to: &target)
    return
  }

  let mirror = Mirror(reflecting: value)
  _adHocPrint_unlocked(value, mirror, &target, isDebugPrint: true)
}

@usableFromInline
@_semantics("optimize.sil.specialize.generic.never")
internal func _dumpPrint_unlocked<T, TargetStream: TextOutputStream>(
    _ value: T, _ mirror: Mirror, _ target: inout TargetStream
) {
  if let displayStyle = mirror.displayStyle {
    // Containers and tuples are always displayed in terms of their element
    // count
    switch displayStyle {
    case .tuple:
      let count = mirror.children.count
      target.write(count == 1 ? "(1 element)": "(\(count) elements)")
      return
    case .collection:
      let count = mirror.children.count
      target.write(count == 1 ? "1 element": "\(count) elements")
      return
    case .dictionary:
      let count = mirror.children.count
      target.write(count == 1 ? "1 key/value pair": "\(count) key/value pairs")
      return
    case .`set`:
      let count = mirror.children.count
      target.write(count == 1 ? "1 member": "\(count) members")
      return
    default:
      break
    }
  }

  if let debugPrintableObject = value as? CustomDebugStringConvertible {
    debugPrintableObject.debugDescription.write(to: &target)
    return
  }

  if let printableObject = value as? CustomStringConvertible {
    printableObject.description.write(to: &target)
    return
  }

  if let streamableObject = value as? TextOutputStreamable {
    streamableObject.write(to: &target)
    return
  }

  if let displayStyle = mirror.displayStyle {
    switch displayStyle {
    case .`class`, .`struct`:
      // Classes and structs without custom representations are displayed as
      // their fully qualified type name
      target.write(_typeName(mirror.subjectType, qualified: true))
      return
    case .`enum`:
      target.write(_typeName(mirror.subjectType, qualified: true))
      if let cString = _getEnumCaseName(value),
          let caseName = String(validatingUTF8: cString) {
        target.write(".")
        target.write(caseName)
      }
      return
    default:
      break
    }
  }

  _adHocPrint_unlocked(value, mirror, &target, isDebugPrint: true)
}

