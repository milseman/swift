//===--- StringNormalization.swift ----------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftShims

extension _Normalization {
  internal typealias _SegmentOutputBuffer = _FixedArray16<UInt16>
}

extension Unicode.Scalar {
  // Normalization boundary - a place in a string where everything left of the
  // boundary can be normalized independently from everything right of the
  // boundary. The concatenation of each result is the same as if the entire
  // string had been normalized as a whole.
  //
  // Normalization segment - a sequence of code units between two normalization
  // boundaries (without any boundaries in the middle). Note that normalization
  // segments can, as a process of normalization, expand, contract, and even
  // produce new sub-segments.

  // Whether this scalar value always has a normalization boundary before it.
  internal var _hasNormalizationBoundaryBefore: Bool {
    @inline(__always) get {
      // Fast-path: All scalars up through U+02FF have boundaries before them
      if value < 0x0300 { return true }

      _sanityCheck(Int32(exactly: self.value) != nil, "top bit shouldn't be set")
      let value = Int32(bitPattern: self.value)
      return 0 != __swift_stdlib_unorm2_hasBoundaryBefore(
        _Normalization._nfcNormalizer, value)
    }
  }
  public // Just for testin! TODO(UTF8): Internalize
  var isNFCQCYes: Bool {
    @inline(__always) get {
      // Fast-path: All scalars up through U+02FF are NFC
      if value < 0x0300 { return true }

      return __swift_stdlib_u_getIntPropertyValue(
        // FIXME(UTF8): use the enum, not magic number
        Builtin.reinterpretCast(value), Builtin.reinterpretCast(0x100E)
      ) == 1
    }
  }
}

internal func _tryNormalize(
  _ input: UnsafeBufferPointer<UInt16>,
  into outputBuffer:
    UnsafeMutablePointer<_Normalization._SegmentOutputBuffer>
) -> Int? {
  return _tryNormalize(input, into: _castOutputBuffer(outputBuffer))
}
internal func _tryNormalize(
  _ input: UnsafeBufferPointer<UInt16>,
  into outputBuffer: UnsafeMutableBufferPointer<UInt16>
) -> Int? {
  var err = __swift_stdlib_U_ZERO_ERROR
  let count = __swift_stdlib_unorm2_normalize(
    _Normalization._nfcNormalizer,
    input.baseAddress._unsafelyUnwrappedUnchecked,
    numericCast(input.count),
    outputBuffer.baseAddress._unsafelyUnwrappedUnchecked,
    numericCast(outputBuffer.count),
    &err
  )
  guard err.isSuccess else {
    // The output buffer needs to grow
    return nil
  }
  return numericCast(count)
}

//
// Pointer casting helpers
//
@inline(__always)
private func _unsafeMutableBufferPointerCast<T, U>(
  _ ptr: UnsafeMutablePointer<T>,
  _ count: Int,
  to: U.Type = U.self
) -> UnsafeMutableBufferPointer<U> {
  return UnsafeMutableBufferPointer(
    start: UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: U.self),
    count: count
  )
}
@inline(__always)
private func _unsafeBufferPointerCast<T, U>(
  _ ptr: UnsafePointer<T>,
  _ count: Int,
  to: U.Type = U.self
) -> UnsafeBufferPointer<U> {
  return UnsafeBufferPointer(
    start: UnsafeRawPointer(ptr).assumingMemoryBound(to: U.self),
    count: count
  )
}

internal func _castOutputBuffer(
  _ ptr: UnsafeMutablePointer<_Normalization._SegmentOutputBuffer>,
  endingAt endIdx: Int = _Normalization._SegmentOutputBuffer.capacity
) -> UnsafeMutableBufferPointer<UInt16> {
  let bufPtr: UnsafeMutableBufferPointer<UInt16> =
    _unsafeMutableBufferPointerCast(
      ptr, _Normalization._SegmentOutputBuffer.capacity)
  return UnsafeMutableBufferPointer<UInt16>(rebasing: bufPtr[..<endIdx])
}
internal func _castOutputBuffer(
  _ ptr: UnsafePointer<_Normalization._SegmentOutputBuffer>,
  endingAt endIdx: Int = _Normalization._SegmentOutputBuffer.capacity
) -> UnsafeBufferPointer<UInt16> {
  let bufPtr: UnsafeBufferPointer<UInt16> =
    _unsafeBufferPointerCast(
      ptr, _Normalization._SegmentOutputBuffer.capacity)
  return UnsafeBufferPointer<UInt16>(rebasing: bufPtr[..<endIdx])
}

extension _StringGuts {
  internal func foreignHasNormalizationBoundary(
    before index: String.Index
  ) -> Bool {
    let offset = index.encodedOffset
    if offset == 0 || offset == count {
      return true
    }

    let cu = foreignErrorCorrectedUTF16CodeUnit(at: index)
    return Unicode.Scalar(cu)?._hasNormalizationBoundaryBefore ?? false
  }
}
extension UnsafeBufferPointer where Element == UInt8 {
  internal func hasNormalizationBoundary(before index: Int) -> Bool {
    if index == 0 || index == count {
      return true
    }

    assert(!_isContinuation(self[index]))

    let cu = _decodeScalar(self, startingAt: index).0
    return cu._hasNormalizationBoundaryBefore
  }
}

internal struct _NormalizedUTF8CodeUnitIterator: IteratorProtocol {
  internal typealias CodeUnit = UInt8

  var utf16Iterator: _NormalizedCodeUnitIterator
  var utf8Buffer = _FixedArray4<CodeUnit>(allZeros:())
  var bufferIndex = 0
  var bufferCount = 0

  internal init(foreign guts: _StringGuts, range: Range<String.Index>) {
    _sanityCheck(guts.isForeign)
    utf16Iterator = _NormalizedCodeUnitIterator(guts, range)
  }

  internal init(_ buffer: UnsafeBufferPointer<UInt8>, range: Range<Int>) {
    utf16Iterator = _NormalizedCodeUnitIterator(buffer, range)
  }

  internal mutating func next() -> UInt8? {
    if bufferIndex == bufferCount {
      bufferIndex = 0
      bufferCount = 0

      guard let cu = utf16Iterator.next() else {
        return nil
      }

      var array = _FixedArray2<UInt16>()
      array.append(cu)
      if _isSurrogate(cu) {
        guard let nextCU = utf16Iterator.next() else {
          fatalError("unpaired surrogate")
        }

        array.append(nextCU)
      }
      let iterator = array.makeIterator()
      _ = transcode(iterator, from: UTF16.self, to: UTF8.self,
        stoppingOnError: false) { codeUnit in
          _sanityCheck(bufferCount < 4)
          _sanityCheck(bufferIndex < 4)

          utf8Buffer[bufferIndex] = codeUnit
          bufferIndex += 1
          bufferCount += 1
      }
      bufferIndex = 0
    }

    defer { bufferIndex += 1 }

    return utf8Buffer[bufferIndex]
  }

  internal mutating func compare(
    with other: _NormalizedUTF8CodeUnitIterator
  ) -> _StringComparisonResult {
    var mutableOther = other

    for cu in self {
      if let otherCU = mutableOther.next() {
        let result = _lexicographicalCompare(cu, otherCU)
        if result == .equal {
          continue
        } else {
          return result
        }
      } else {
        //other returned nil, we are greater
        return .greater
      }
    }

    //we ran out of code units, either we are equal, or only we ran out and
    //other is greater
    if let _ = mutableOther.next() {
      return .less
    } else {
      return .equal
    }
  }
}

extension _NormalizedUTF8CodeUnitIterator: Sequence { }

internal
struct _NormalizedCodeUnitIterator: IteratorProtocol {
  internal typealias CodeUnit = UInt16
  var segmentBuffer = _FixedArray16<CodeUnit>(allZeros:())
  var overflowBuffer: [CodeUnit]? = nil
  var normalizationBuffer: [CodeUnit]? = nil
  var source: _SegmentSource

  var segmentBufferIndex = 0
  var segmentBufferCount = 0
  var overflowBufferIndex = 0
  var overflowBufferCount = 0

  init(_ guts: _StringGuts, _ range: Range<String.Index>) {
    source = _ForeignStringGutsSource(guts, range)
  }

  init(_ buffer: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) {
    source = _UTF8BufferSource(buffer, range)
  }

  mutating func compare(
    with other: _NormalizedCodeUnitIterator
  ) -> _StringComparisonResult {
    var mutableOther = other
    for cu in IteratorSequence(self) {
      if let otherCU = mutableOther.next() {
        let result = _lexicographicalCompare(cu, otherCU)
        if result == .equal {
          continue
        } else {
          return result
        }
      } else {
        //other returned nil, we are greater
        return .greater
      }
    }

    //we ran out of code units, either we are equal, or only we ran out and
    //other is greater
    if let _ = mutableOther.next() {
      return .less
    } else {
      return .equal
    }
  }

  struct _UTF8BufferSource: _SegmentSource {
    var remaining: Int {
      return range.count - index
    }
    var isEmpty: Bool {
      return remaining <= 0
    }
    var buffer: UnsafeBufferPointer<UInt8>
    var index: Int
    var range: Range<Int>

    init(_ buffer: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) {
      self.buffer = buffer
      self.range = range
      index = range.lowerBound
    }

    mutating func tryFill(
      into output: UnsafeMutableBufferPointer<UInt16>
    ) -> Int? {
      var outputIndex = 0
      let originalIndex = index
      repeat {
        guard !isEmpty else {
          break
        }

        guard outputIndex < output.count else {
          //The buff isn't big enough for the current segment
          index = originalIndex
          return nil
        }

        let (cu, nextIndex) = _decodeScalar(buffer, startingAt: index)
        let utf16 = cu.utf16
        switch utf16.count {
        case 1:
          output[outputIndex] = utf16[0]
          outputIndex += 1
        case 2:
          if outputIndex+1 >= output.count {
            index = originalIndex
            return nil
          }
          output[outputIndex] = utf16[0]
          output[outputIndex+1] = utf16[1]
          outputIndex += 2
        default:
          _conditionallyUnreachable()
        }
        index = nextIndex
      } while !buffer.hasNormalizationBoundary(before: index)
      return outputIndex
    }
  }

  struct _ForeignStringGutsSource: _SegmentSource {
    var remaining: Int {
      return range.upperBound.encodedOffset - index.encodedOffset
    }
    var isEmpty: Bool {
      return index >= range.upperBound
    }
    var guts: _StringGuts
    var index: String.Index
    var range: Range<String.Index>

    init(_ guts: _StringGuts, _ range: Range<String.Index>) {
      self.guts = guts
      self.range = range
      index = range.lowerBound
    }

    mutating func tryFill(
      into output: UnsafeMutableBufferPointer<UInt16>
    ) -> Int? {
      var outputIndex = 0
      let originalIndex = index
      repeat {
        guard index != range.upperBound else {
          break
        }

        guard outputIndex < output.count else {
          //The buffer isn't big enough for the current segment
          index = originalIndex
          return nil
        }

        let cu = guts.foreignErrorCorrectedUTF16CodeUnit(at: index)
        output[outputIndex] = cu
        index = index.nextEncoded
        outputIndex += 1
      } while !guts.foreignHasNormalizationBoundary(before: index)

      return outputIndex
    }
  }

  mutating func next() -> UInt16? {
    if segmentBufferCount == segmentBufferIndex {
      segmentBuffer = _FixedArray16<CodeUnit>(allZeros:())
      segmentBufferCount = 0
      segmentBufferIndex = 0
    }

    if overflowBufferCount == overflowBufferIndex {
      overflowBufferCount = 0
      overflowBufferIndex = 0
    }

    if source.isEmpty
    && segmentBufferCount == 0
    && overflowBufferCount == 0 {
      // Our source of code units to normalize is empty and our buffers from
      // previous normalizations are also empty.
      return nil
    }
    if segmentBufferCount == 0 && overflowBufferCount == 0 {
      //time to fill a buffer if possible. Otherwise we are done, return nil
      // Normalize segment, and then compare first code unit
      var intermediateBuffer = _FixedArray16<CodeUnit>(allZeros:())
      if overflowBuffer == nil,
         let filled = source.tryFill(into: &intermediateBuffer)
      {
        guard let count = _tryNormalize(
          _castOutputBuffer(&intermediateBuffer,
          endingAt: filled),
          into: &segmentBuffer
        )
        else {
          fatalError("Output buffer was not big enough, this should not happen")
        }
        segmentBufferCount = count
      } else {
        if overflowBuffer == nil {
          let size = source.remaining * _Normalization._maxNFCExpansionFactor
          overflowBuffer = Array(repeating: 0, count: size)
          normalizationBuffer = Array(repeating:0, count: size)
        }

        guard let count = normalizationBuffer!.withUnsafeMutableBufferPointer({
          (normalizationBufferPtr) -> Int? in
          guard let filled = source.tryFill(into: normalizationBufferPtr)
          else {
            fatalError("Invariant broken, buffer should have space")
          }
          return overflowBuffer!.withUnsafeMutableBufferPointer {
            (overflowBufferPtr) -> Int? in
            return _tryNormalize(
              UnsafeBufferPointer(rebasing: normalizationBufferPtr[..<filled]),
              into: overflowBufferPtr
            )
          }
        }) else {
          fatalError("Invariant broken, overflow buffer should have space")
        }

        overflowBufferCount = count
      }
    }

    //exactly one of the buffers should have code units for us to return
    _sanityCheck((segmentBufferCount == 0)
              != ((overflowBuffer?.count ?? 0) == 0))

    if segmentBufferIndex < segmentBufferCount {
      let index = segmentBufferIndex
      segmentBufferIndex += 1
      return segmentBuffer[index]
    } else if overflowBufferIndex < overflowBufferCount {
      _sanityCheck(overflowBufferIndex < overflowBuffer!.count)
      let index = overflowBufferIndex
      overflowBufferIndex += 1
      return overflowBuffer![index]
    } else {
        return nil
    }
  }
}

protocol _SegmentSource {
  var remaining: Int { get }
  var isEmpty: Bool { get }
  mutating func tryFill(into: UnsafeMutableBufferPointer<UInt16>) -> Int?
}

extension _SegmentSource {
  mutating func tryFill(
    into output: UnsafeMutablePointer<_Normalization._SegmentOutputBuffer>
  ) -> Int? {
    return tryFill(into: _castOutputBuffer(output))
  }
}

// Just for testing!

extension Unicode.Scalar {
 public // Just for testin! TODO(UTF8): Internalize
 func hasBinaryProperty(
    _ property: __swift_stdlib_UProperty
  ) -> Bool {
    return __swift_stdlib_u_hasBinaryProperty(
      Builtin.reinterpretCast(value), property
    ) != 0
  }

  public // Just for testin! TODO(UTF8): Remove
  var hasNormalizationBoundaryBefore: Bool {
    return _hasNormalizationBoundaryBefore
  }
}


internal struct _NormalizedUTF8CodeUnitIterator_2: Sequence, IteratorProtocol {
  private var outputBuffer = _SmallBuffer<UInt8>()
  private var outputPosition = 0
  private var outputBufferCount = 0

  private var slicedGuts: _SlicedStringGuts
  private var readPosition: String.Index

  private var _backupIsEmpty = false

  // TODO: This is getting super ugly...
  private var _foreignNFCIterator: _NormalizedUTF8CodeUnitIterator? = nil

  internal init(_ sliced: _SlicedStringGuts) {
    self.slicedGuts = sliced
    self.readPosition = self.slicedGuts.range.lowerBound
  }

  internal mutating func next() -> UInt8? {
    return _next()
  }
}

extension _NormalizedUTF8CodeUnitIterator_2 {
  private var outputBufferThreshold: Int {
    return outputBuffer.capacity
  }

  private var outputBufferEmpty: Bool {
    return outputPosition == outputBufferCount
  }
  private var outputBufferFull: Bool {
    return outputBufferCount >= outputBufferThreshold
  }

  private var inputBufferEmpty: Bool {
    return slicedGuts.range.isEmpty
  }
}

extension _NormalizedUTF8CodeUnitIterator_2 {
  private mutating func _next() -> UInt8? {
    defer { _fixLifetime(self) }
    if _slowPath(outputBufferEmpty) {
      if _slowPath(inputBufferEmpty) {
        return nil
      }
      fill()
      if _slowPath(outputBufferEmpty) {
        _sanityCheck(inputBufferEmpty)
        return nil
      }
    }
    _sanityCheck(!outputBufferEmpty)

    _sanityCheck(outputPosition < outputBufferCount)
    let result = outputBuffer[outputPosition]
    outputPosition &+= 1
    return result
  }

  private mutating func fill() {
    _sanityCheck(outputBufferEmpty)
    outputPosition = 0
    outputBufferCount = 0

    print(String(slicedGuts._guts).asSwiftString)

    let priorCount = slicedGuts._offsetRange.count
    if _fastPath(slicedGuts.isFastUTF8) {
      slicedGuts.withFastUTF8 { utf8 in
        let latinyUpperbound: UInt8 = 0xCC
        var idx = 0
        let endIdx = Swift.min(utf8.count, outputBufferThreshold)
        while idx < endIdx {
          // Check scalar-based fast-paths
          let (scalar, scalarEndIdx) = _decodeScalar(utf8, startingAt: idx)
          guard scalarEndIdx <= endIdx else { break }
          guard utf8.hasNormalizationBoundary(before: scalarEndIdx) else { break }
          //
          // Fast-path: All scalars that are NFC_QC AND segment starters are NFC
          //
          if _fastPath(
            scalar._hasNormalizationBoundaryBefore && scalar.isNFCQCYes
          ) {
            while idx < scalarEndIdx {
              outputBuffer[idx] = utf8[idx]
              idx &+= 1
            }
            continue
          }

          //
          // TODO: Fast-path: All NFC_QC AND CCC-ascending scalars are NFC
          //

          //
          // TODO: Just freakin do normalization and don't bother with ICU
          //

          break
        }
        outputBufferCount = idx
      }
    }

    // Check if we hit a fast-path
    if outputBufferCount > 0 {
      slicedGuts._offsetRange = Range(uncheckedBounds: (
        slicedGuts._offsetRange.lowerBound + outputBufferCount,
        slicedGuts._offsetRange.upperBound))
      _sanityCheck(slicedGuts._offsetRange.count >= 0)
      return
    }

    if !slicedGuts.isFastUTF8 && _foreignNFCIterator == nil {
      _foreignNFCIterator = _NormalizedUTF8CodeUnitIterator(
        foreign: slicedGuts._guts, range: slicedGuts.range)
    }
    let remaining: Int
    if slicedGuts.isFastUTF8 {
      remaining = slicedGuts.withNFCCodeUnits {
        var nfc = $0
        while !outputBufferFull, let cu = nfc.next() {
          outputBuffer[outputBufferCount] = cu
          outputBufferCount &+= 1
        }
        return nfc.utf16Iterator.source.remaining
      }
    } else {
      while !outputBufferFull, let cu = _foreignNFCIterator!.next() {
        outputBuffer[outputBufferCount] = cu
        outputBufferCount &+= 1
      }
      // Super duper ugly, but we'll adjust our range just for emptiness..
      remaining = _foreignNFCIterator!.utf16Iterator.source.remaining      
    }

    _sanityCheck(outputBufferCount == 0 || remaining < priorCount)

    slicedGuts._offsetRange = Range(uncheckedBounds: (
      slicedGuts._offsetRange.lowerBound + (priorCount - remaining),
      slicedGuts._offsetRange.upperBound))

    _sanityCheck(outputBufferFull || slicedGuts._offsetRange.isEmpty)
    _sanityCheck(slicedGuts._offsetRange.count >= 0)
  }

  internal mutating func compare(
    with other: _NormalizedUTF8CodeUnitIterator_2
  ) -> _StringComparisonResult {
    var iter = self
    var mutableOther = other

    while let cu = iter.next() {
      if let otherCU = mutableOther.next() {
        let result = _lexicographicalCompare(cu, otherCU)
        if result == .equal {
          continue
        } else {
          return result
        }
      } else {
        //other returned nil, we are greater
        return .greater
      }
    }

    //we ran out of code units, either we are equal, or only we ran out and
    //other is greater
    if let _ = mutableOther.next() {
      return .less
    } else {
      return .equal
    }
  }
}


