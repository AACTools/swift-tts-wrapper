import Foundation

enum ArchiveExtractor {
    static func extractTarBz2(archivePath: String, destDir: URL) throws {
        #if canImport(AppKit)
        try extractViaProcess(archivePath: archivePath, destDir: destDir)
        #else
        try extractPureSwift(archivePath: archivePath, destDir: destDir)
        #endif
    }

    #if canImport(AppKit)
    private static func extractViaProcess(archivePath: String, destDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tar", "xf", archivePath, "-C", destDir.path]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown tar error"
            throw ArchiveError.extractionFailed("tar extraction failed: \(errorMsg)")
        }
    }
    #endif

    private static func extractPureSwift(archivePath: String, destDir: URL) throws {
        let compressed = try Data(contentsOf: URL(fileURLWithPath: archivePath))

        guard compressed.count >= 4 else {
            throw ArchiveError.invalidData("Data too short for bzip2")
        }
        guard compressed[0] == 0x42, compressed[1] == 0x5A, compressed[2] == 0x68 else {
            throw ArchiveError.invalidData("Not a valid bzip2 stream")
        }

        let decompressed = try Bzip2Decoder.decode(compressed)
        try TarReader.extract(tarData: decompressed, to: destDir)
    }
}

private enum Bzip2Decoder {
    static func decode(_ data: Data) throws -> Data {
        var br = _BitReader(data: data, startByte: 4)

        guard try br.readBits(8) == 0x42,
              try br.readBits(8) == 0x5A,
              try br.readBits(8) == 0x68 else {
            throw ArchiveError.invalidData("Bad bzip2 magic")
        }
        let blockSize100k = try br.readBits(8) - 0x30
        guard (1...9).contains(blockSize100k) else {
            throw ArchiveError.invalidData("Bad block size")
        }

        var output = Data()

        while true {
            let blockMagic = try br.readBits(48)
            if blockMagic == 0x314159_265359 {
                _ = try br.readBits(32) // blockCRC
                let blockOut = try decodeBlock(reader: &br, blockSize100k: blockSize100k)
                output.append(blockOut)
            } else if blockMagic == 0x177245_385090 {
                _ = try br.readBits(32) // finalCRC
                break
            } else {
                break
            }
        }
        return output
    }

    private static func decodeBlock(reader: inout _BitReader, blockSize100k: Int) throws -> Data {
        _ = try reader.readBit() // randomised
        let bwtOrigPtr = try reader.readBits(24)

        var usedMap = [Bool](repeating: false, count: 16)
        for i in 0..<16 { usedMap[i] = try reader.readBit() != 0 }

        var usedBitmap = [Bool](repeating: false, count: 256)
        var inUseCount = 0
        for i in 0..<16 {
            if usedMap[i] {
                for j in 0..<16 {
                    if try reader.readBit() != 0 {
                        usedBitmap[i * 16 + j] = true
                        inUseCount += 1
                    }
                }
            }
        }

        var seqToUnseq = [UInt8]()
        for i in 0..<256 where usedBitmap[i] { seqToUnseq.append(UInt8(i)) }

        let alphaSize = inUseCount + 2

        let numSelectors = try reader.readBits(15)
        let numGroups = try reader.readBits(3)

        var selectorMtf = [Int]()
        for _ in 0..<numSelectors {
            var j = 0
            while try reader.readBit() != 0 { j += 1 }
            selectorMtf.append(j)
        }

        var selector = selectorMtf
        var mtf = [Int](0..<numGroups)
        for i in 0..<selectorMtf.count {
            let idx = selectorMtf[i]
            let val = mtf[idx]
            for j in stride(from: idx, to: 0, by: -1) { mtf[j] = mtf[j - 1] }
            mtf[0] = val
            selector[i] = val
        }

        var len = [[Int]](repeating: [Int](repeating: 0, count: alphaSize), count: numGroups)
        for t in 0..<numGroups {
            var curr = try reader.readBits(5)
            for i in 0..<alphaSize {
                while true {
                    let bit = try reader.readBit()
                    if bit == 0 { break }
                    curr += try reader.readBit() == 0 ? -1 : 1
                }
                len[t][i] = curr
            }
        }

        var limit = [[Int]](repeating: [Int](repeating: 0, count: alphaSize), count: numGroups)
        var base = [[Int]](repeating: [Int](repeating: 0, count: alphaSize), count: numGroups)
        var perm = [[Int]](repeating: [Int](repeating: 0, count: alphaSize), count: numGroups)

        for t in 0..<numGroups {
            let minLen = len[t].reduce(Int.max, min)
            let maxLen = len[t].reduce(Int.min, max)
            guard minLen >= 1 && maxLen <= 20 else {
                throw ArchiveError.invalidData("Bad huffman lengths")
            }

            var pp = 0
            for i in minLen...maxLen {
                base[t][i - minLen] = pp
                limit[t][i - minLen] = (1 << i) - 1
                pp += len[t].filter { $0 == i }.count
            }
            for i in 0..<alphaSize {
                let l = len[t][i] - minLen
                perm[t][base[t][l]] = i
                base[t][l] += 1
            }

            var bb = 0
            for i in minLen...maxLen {
                bb += (1 << i)
                base[t][i - minLen] = bb - (1 << i)
            }
            // recalculate perm using sorted order
            let sortedIdx = Array(0..<alphaSize).sorted { len[t][$0] < len[t][$1] || (len[t][$0] == len[t][$1] && $0 < $1) }
            pp = 0
            for i in minLen...maxLen {
                for j in 0..<alphaSize where len[t][sortedIdx[j]] == i {
                    perm[t][pp] = sortedIdx[j]
                    pp += 1
                }
            }
        }

        let maxBlockSize = blockSize100k * 100_000
        var tt = [Int](repeating: 0, count: maxBlockSize)
        var nOut = 0

        var mtfBuf = [Int](repeating: 0, count: 256)
        for i in 0..<inUseCount { mtfBuf[i] = i }

        var groupNo = -1
        var groupPos = 0

        while nOut < maxBlockSize {
            if groupPos == 0 {
                groupNo += 1
                if groupNo >= selector.count { break }
                groupPos = 50
            }
            groupPos -= 1

            let t = selector[groupNo]
            var zn = 0
            var zj: Int
            repeat {
                zn += 1
                zj = try reader.readBit()
            } while zj != 0

            let l = zn - 1
            let sym = perm[t][l + base[t][l]]
            if sym == 0 || sym == 1 {
                var s = try reader.readBit() + 1
                var n = 1
                while try reader.readBit() != 0 {
                    let extra = try reader.readBit()
                    s += extra << n
                    n += 1
                }
                s += (1 << n) - 1
                if sym == 0 {
                    // RUNA
                    for _ in 0..<s { tt[nOut] = 0; nOut += 1 }
                } else {
                    // RUNB
                    for _ in 0..<s { tt[nOut] = 0; nOut += 1 }
                }
            } else {
                let symVal = sym - 1
                let moved = mtfBuf[symVal]
                for j in stride(from: symVal, to: 0, by: -1) { mtfBuf[j] = mtfBuf[j - 1] }
                mtfBuf[0] = moved
                tt[nOut] = moved + 1
                nOut += 1
            }
        }

        guard nOut > 0 else { return Data() }

        var bwtBlock = [UInt8](repeating: 0, count: nOut)
        for i in 0..<nOut {
            if tt[i] == 0 {
                bwtBlock[i] = seqToUnseq[mtfBuf[0]]
            } else {
                bwtBlock[i] = seqToUnseq[tt[i] - 1]
            }
        }

        return inverseBWT(data: bwtBlock, origPtr: bwtOrigPtr)
    }

    private static func inverseBWT(data: [UInt8], origPtr: Int) -> Data {
        let n = data.count
        guard n > 0 else { return Data() }

        var cumFreq = [Int](repeating: 0, count: 257)
        for b in data { cumFreq[Int(b) + 1] += 1 }
        for i in 1..<257 { cumFreq[i] += cumFreq[i - 1] }

        var t = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let c = Int(data[i])
            t[cumFreq[c]] = i
            cumFreq[c] += 1
        }

        var result = [UInt8](repeating: 0, count: n)
        var idx = origPtr
        for i in 0..<n {
            result[i] = data[idx]
            idx = t[idx]
        }
        return Data(result)
    }
}

private struct _BitReader {
    let data: Data
    var bytePos: Int
    var bitBuf: UInt64 = 0
    var bitsInBuf: Int = 0

    init(data: Data, startByte: Int) {
        self.data = data
        self.bytePos = startByte
    }

    private mutating func fill() {
        while bitsInBuf <= 56 && bytePos < data.count {
            bitBuf |= UInt64(data[bytePos]) << UInt64(56 - bitsInBuf)
            bitsInBuf += 8
            bytePos += 1
        }
    }

    mutating func readBit() throws -> Int {
        if bitsInBuf == 0 { fill() }
        guard bitsInBuf > 0 else { throw ArchiveError.invalidData("Unexpected end of data") }
        let bit = Int(bitBuf >> 63) & 1
        bitBuf <<= 1
        bitsInBuf -= 1
        return bit
    }

    mutating func readBits(_ n: Int) throws -> Int {
        guard n <= 64 else { throw ArchiveError.invalidData("Too many bits requested") }
        while bitsInBuf < n { fill() }
        guard bitsInBuf >= n else { throw ArchiveError.invalidData("Unexpected end of data") }
        let val = Int(bitBuf >> UInt64(64 - n))
        bitBuf <<= UInt64(n)
        bitsInBuf -= n
        return val
    }
}

enum TarReader {
    static func extract(tarData: Data, to destDir: URL) throws {
        let blockSize = 512
        var offset = 0
        let fm = FileManager.default
        let end = tarData.count

        while offset + blockSize <= end {
            let header = tarData[offset..<(offset + blockSize)]

            guard !header.allSatisfy({ $0 == 0 }) else {
                offset += blockSize
                continue
            }

            guard let name = parseString(header, offset: 0, length: 100), !name.isEmpty else {
                offset += blockSize
                continue
            }

            let size = parseOctal(header, offset: 124, length: 12) ?? 0
            let typeFlag = header[156]

            let fullPath = destDir.appendingPathComponent(name)
            let parent = fullPath.deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            offset += blockSize

            if size > 0 && (typeFlag == 0 || typeFlag == 0x30) {
                let fileEnd = min(offset + Int(size), end)
                let fileData = tarData[offset..<fileEnd]
                try Data(fileData).write(to: fullPath)
                offset += ((Int(size) + blockSize - 1) / blockSize) * blockSize
            } else if typeFlag == 0x35 {
                try fm.createDirectory(at: fullPath, withIntermediateDirectories: true)
            } else if typeFlag == 0x32 {
                let target = parseString(header, offset: 157, length: 100) ?? ""
                try? fm.createSymbolicLink(atPath: fullPath.path, withDestinationPath: target)
            }
        }
    }

    private static func parseString(_ data: Data.SubSequence, offset: Int, length: Int) -> String? {
        var bytes = [UInt8](data[offset..<(offset + length)])
        if let nul = bytes.firstIndex(of: 0) { bytes = Array(bytes[..<nul]) }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func parseOctal(_ data: Data.SubSequence, offset: Int, length: Int) -> UInt64? {
        var s = parseString(data, offset: offset, length: length)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if s.hasPrefix("0") { s = String(s.dropFirst()) }
        return UInt64(s, radix: 8)
    }
}

enum ArchiveError: Error, LocalizedError {
    case invalidData(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidData(let m): return "Archive error: \(m)"
        case .extractionFailed(let m): return "Extraction failed: \(m)"
        }
    }
}
