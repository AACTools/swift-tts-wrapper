import Foundation

public final class SherpaOnnxModelManager {
    private let baseDir: URL

    public init(baseDir: URL? = nil) {
        if let dir = baseDir {
            self.baseDir = dir
        } else {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.baseDir = cachesDir.appendingPathComponent("SwiftTTSWrapper/sherpa-onnx-models", isDirectory: true)
        }
    }

    public var modelBaseDirectory: URL { baseDir }

    public func ensureBaseDir() throws {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    public func voiceDir(for modelId: String) -> URL {
        return baseDir.appendingPathComponent(modelId, isDirectory: true)
    }

    public func isModelDownloaded(modelId: String) -> Bool {
        let dir = voiceDir(for: modelId)
        let modelPath = dir.appendingPathComponent("model.onnx").path
        let tokensPath = dir.appendingPathComponent("tokens.txt").path
        return FileManager.default.fileExists(atPath: modelPath) && FileManager.default.fileExists(atPath: tokensPath)
    }

    public func resolveModelPaths(modelId: String) -> (
        modelPath: String,
        tokensPath: String,
        voiceDir: String,
        lexiconPath: String,
        dataDir: String,
        voicesPath: String,
        vocoderPath: String,
        dictDir: String
    ) {
        let dir = voiceDir(for: modelId)
        let dirPath = dir.path

        let modelPath = dir.appendingPathComponent("model.onnx").path
        let tokensPath = dir.appendingPathComponent("tokens.txt").path
        let lexiconPath = dir.appendingPathComponent("lexicon.txt").path
        let dataDir = dir.appendingPathComponent("espeak-ng-data").path
        let voicesPath = dir.appendingPathComponent("voices.bin").path
        let dictDirPath = dir.appendingPathComponent("dict").path

        let vocoderName = "vocos-22khz-univ.onnx"
        let vocoderPath = baseDir.appendingPathComponent(vocoderName).path

        return (
            modelPath: modelPath,
            tokensPath: tokensPath,
            voiceDir: dirPath,
            lexiconPath: FileManager.default.fileExists(atPath: lexiconPath) ? lexiconPath : "",
            dataDir: FileManager.default.fileExists(atPath: dataDir) ? dataDir : "",
            voicesPath: FileManager.default.fileExists(atPath: voicesPath) ? voicesPath : "",
            vocoderPath: FileManager.default.fileExists(atPath: vocoderPath) ? vocoderPath : "",
            dictDir: FileManager.default.fileExists(atPath: dictDirPath) ? dictDirPath : ""
        )
    }

    public func downloadAndExtract(entry: SherpaOnnxModelEntry) async throws {
        guard let urlString = entry.url, !urlString.isEmpty else {
            throw NSError(domain: "SherpaOnnxModelManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "No URL for model \(entry.id)"])
        }

        let dir = voiceDir(for: entry.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let modelType = entry.resolvedModelType

        if entry.compression == true {
            try await downloadAndExtractArchive(urlString: urlString, modelId: entry.id, modelType: modelType, destDir: dir)
        } else if isMmsUrl(urlString) {
            try await downloadMmsFiles(urlString: urlString, destDir: dir)
        } else {
            try await downloadDirectFiles(urlString: urlString, destDir: dir)
        }
    }

    public func ensureVocoder() async throws -> String {
        let vocoderName = "vocos-22khz-univ.onnx"
        let vocoderPath = baseDir.appendingPathComponent(vocoderName)
        try ensureBaseDir()

        if FileManager.default.fileExists(atPath: vocoderPath.path) {
            return vocoderPath.path
        }

        let vocoderURL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos-22khz-univ.onnx"
        try await downloadFile(urlString: vocoderURL, destination: vocoderPath.path)
        return vocoderPath.path
    }

    private func isMmsUrl(_ url: String) -> Bool {
        return url.contains("willwade/mms-tts-multilingual-models-onnx") || url.contains("huggingface.co")
    }

    private func downloadFile(urlString: String, destination: String) async throws {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "SherpaOnnxModelManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"])
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "SherpaOnnxModelManager", code: status, userInfo: [NSLocalizedDescriptionKey: "Failed to download \(urlString)"])
        }
        try data.write(to: URL(fileURLWithPath: destination))
    }

    private func downloadMmsFiles(urlString: String, destDir: URL) async throws {
        let modelFileUrl = "\(urlString)/model.onnx"
        let tokensFileUrl = "\(urlString)/tokens.txt"

        let modelDest = destDir.appendingPathComponent("model.onnx").path
        let tokensDest = destDir.appendingPathComponent("tokens.txt").path

        if !FileManager.default.fileExists(atPath: modelDest) {
            try await downloadFile(urlString: modelFileUrl, destination: modelDest)
        }
        if !FileManager.default.fileExists(atPath: tokensDest) {
            try await downloadFile(urlString: tokensFileUrl, destination: tokensDest)
        }
    }

    private func downloadDirectFiles(urlString: String, destDir: URL) async throws {
        let modelFileUrl = urlString.hasSuffix("/") ? "\(urlString)model.onnx?download=true" : "\(urlString)/model.onnx?download=true"
        let tokensFileUrl = urlString.hasSuffix("/") ? "\(urlString)tokens.txt" : "\(urlString)/tokens.txt"

        let modelDest = destDir.appendingPathComponent("model.onnx").path
        let tokensDest = destDir.appendingPathComponent("tokens.txt").path

        if !FileManager.default.fileExists(atPath: modelDest) {
            try await downloadFile(urlString: modelFileUrl, destination: modelDest)
        }
        if !FileManager.default.fileExists(atPath: tokensDest) {
            try await downloadFile(urlString: tokensFileUrl, destination: tokensDest)
        }
    }

    private func downloadAndExtractArchive(urlString: String, modelId: String, modelType: SherpaOnnxModelType, destDir: URL) async throws {
        let archiveName = urlString.components(separatedBy: "/").last ?? "model.tar.bz2"
        let archivePath = baseDir.appendingPathComponent(archiveName)

        try ensureBaseDir()

        if !FileManager.default.fileExists(atPath: archivePath.path) {
            try await downloadFile(urlString: urlString, destination: archivePath.path)
        }

        try extractTarBz2(archivePath: archivePath.path, destDir: destDir, modelType: modelType)

        try? FileManager.default.removeItem(at: archivePath)
    }

    private func extractTarBz2(archivePath: String, destDir: URL, modelType: SherpaOnnxModelType) throws {
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
            throw NSError(domain: "SherpaOnnxModelManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "tar extraction failed: \(errorMsg)"])
        }

        normalizeExtractedFiles(in: destDir)
    }

    private func normalizeExtractedFiles(in dir: URL) {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }

        var onnxFiles: [URL] = []
        var tokensFiles: [URL] = []
        var voicesFiles: [URL] = []
        var lexiconFiles: [URL] = []
        var espeakDirs: [URL] = []
        var dictDirs: [URL] = []
        var fstFiles: [URL] = []

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if name.hasSuffix(".onnx") { onnxFiles.append(fileURL) }
            else if name == "tokens.txt" { tokensFiles.append(fileURL) }
            else if name == "voices.bin" { voicesFiles.append(fileURL) }
            else if name.hasPrefix("lexicon") && name.hasSuffix(".txt") { lexiconFiles.append(fileURL) }
            else if name == "espeak-ng-data" && fm.fileExists(atPath: fileURL.path) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                    espeakDirs.append(fileURL)
                }
            } else if name == "dict" {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                    dictDirs.append(fileURL)
                }
            } else if name.hasSuffix(".fst") { fstFiles.append(fileURL) }
        }

        func moveFileToDir(_ src: URL, _ dest: URL) {
            if src.path != dest.path && fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dest)
            }
        }

        func copyDirToDir(_ src: URL, _ dest: URL) {
            if src.path != dest.path && fm.fileExists(atPath: src.path) {
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: src, to: dest)
            }
        }

        for file in onnxFiles {
            moveFileToDir(file, dir.appendingPathComponent("model.onnx"))
            break
        }
        for file in tokensFiles {
            moveFileToDir(file, dir.appendingPathComponent("tokens.txt"))
            break
        }
        for file in voicesFiles {
            moveFileToDir(file, dir.appendingPathComponent("voices.bin"))
            break
        }
        for file in lexiconFiles {
            moveFileToDir(file, dir.appendingPathComponent("lexicon.txt"))
            break
        }
        for d in espeakDirs {
            copyDirToDir(d, dir.appendingPathComponent("espeak-ng-data"))
            break
        }
        for d in dictDirs {
            copyDirToDir(d, dir.appendingPathComponent("dict"))
            break
        }
        for file in fstFiles {
            let dest = dir.appendingPathComponent(file.lastPathComponent)
            moveFileToDir(file, dest)
        }
    }
}
