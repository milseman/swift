// RUN: %target-typecheck-verify-swift

func foo(chr: Character) -> String {
  return String(repeating: String(chr)) // expected-error {{argument labels '(repeating:)' do not match any available overloads}} expected-note {{overloads for 'String' exist with these partially matching parameter lists: (Character), (from: Decoder), (cString: UnsafePointer<CChar>), (cString: UnsafePointer<UInt8>), (validatingUTF8: UnsafePointer<CChar>), (_builtinUnicodeScalarLiteral: Int32), (Unicode.Scalar), (stringLiteral: String), (T), (String), (_cocoaString: AnyObject), (stringInterpolation: String...), (stringInterpolationSegment: T), (T, radix: Int, uppercase: Bool), (S), (String.UnicodeScalarView), (String.UTF16View), (String.UTF8View), (Substring), (Substring.UTF8View), (Substring.UTF16View), (Substring.UnicodeScalarView), (String, obsoletedInSwift4: ()), (describing: Subject), (reflecting: Subject)}}
}
