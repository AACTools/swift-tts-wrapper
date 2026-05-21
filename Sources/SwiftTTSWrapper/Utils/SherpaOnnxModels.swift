import Foundation

public enum SherpaOnnxModelType: String, Codable {
    case vits
    case kokoro
    case matcha
    case mms
}

public struct SherpaOnnxLanguageInfo: Codable {
    public var langCode: String?
    public var languageName: String?
    public var country: String?

    public var isoCode: String?
    public var languageNameAlt: String?
    public var countryAlt: String?

    enum CodingKeys: String, CodingKey {
        case langCode = "lang_code"
        case languageName = "language_name"
        case country
        case isoCode = "Iso Code"
        case languageNameAlt = "Language Name"
        case countryAlt = "Country"
    }

    public var bestLangCode: String {
        langCode ?? isoCode ?? "en"
    }

    public var bestLanguageName: String {
        languageName ?? languageNameAlt ?? bestLangCode
    }

    public var bestCountry: String {
        country ?? countryAlt ?? ""
    }
}

public struct SherpaOnnxModelEntry: Codable {
    public var id: String
    public var modelType: String?
    public var developer: String?
    public var name: String?
    public var language: [SherpaOnnxLanguageInfo]?
    public var gender: String?
    public var quality: String?
    public var sampleRate: Int?
    public var numSpeakers: Int?
    public var url: String?
    public var compression: Bool?
    public var filesizeMb: Double?
    public var region: String?
    public var onnxExists: Bool?
    public var sampleExists: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, language, gender, quality, url, compression, region
        case modelType = "model_type"
        case developer
        case sampleRate = "sample_rate"
        case numSpeakers = "num_speakers"
        case filesizeMb = "filesize_mb"
        case onnxExists = "ONNX Exists"
        case sampleExists = "Sample Exists"
    }

    public var resolvedModelType: SherpaOnnxModelType {
        if let mt = modelType, let parsed = SherpaOnnxModelType(rawValue: mt) {
            return parsed
        }
        if id.hasPrefix("mms_") { return .mms }
        if let u = url {
            if u.lowercased().contains("kokoro") { return .kokoro }
            if u.lowercased().contains("matcha") { return .matcha }
        }
        return .vits
    }

    public var bcp47Code: String {
        guard let langs = language, let first = langs.first else { return "en-US" }
        let code = first.bestLangCode
        if code.contains("-") { return code }
        if code.count == 3 {
            return "\(code.prefix(2))-\(code.prefix(2).uppercased())"
        }
        if code.count == 2 {
            return "\(code)-\(code.uppercased())"
        }
        return code
    }

    public var displayLanguage: String {
        guard let langs = language, let first = langs.first else { return "Unknown" }
        return first.bestLanguageName
    }

    public var resolvedGender: UnifiedVoice.Gender {
        guard let g = gender?.lowercased() else { return .unknown }
        if g == "male" { return .male }
        if g == "female" { return .female }
        return .unknown
    }
}

public enum SherpaOnnxModelsCatalog {
    private static var cachedModels: [String: SherpaOnnxModelEntry]?

    public static let modelsURL = URL(string: "https://cdn.jsdelivr.net/gh/willwade/js-tts-wrapper-assets@main/sherpaonnx/models/merged_models.json")

    public static func loadBundled() -> [String: SherpaOnnxModelEntry]? {
        if let cached = cachedModels { return cached }

        guard let url = Bundle.module.url(forResource: "merged_models", withExtension: "json") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let entries = try? decoder.decode([String: SherpaOnnxModelEntry].self, from: data) else {
            return nil
        }

        cachedModels = entries
        return entries
    }

    public static func loadFromURL(_ url: URL) async throws -> [String: SherpaOnnxModelEntry] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "SherpaOnnxModelsCatalog", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to download models catalog"])
        }
        let decoder = JSONDecoder()
        let entries = try decoder.decode([String: SherpaOnnxModelEntry].self, from: data)
        cachedModels = entries
        return entries
    }

    public static func load(credentials: TTSCredentials) async throws -> [String: SherpaOnnxModelEntry] {
        if let customURLStr = credentials["modelsURL"], let customURL = URL(string: customURLStr) {
            return try await loadFromURL(customURL)
        }
        if let bundled = loadBundled() {
            return bundled
        }
        if let remoteURL = modelsURL {
            return try await loadFromURL(remoteURL)
        }
        return [:]
    }

    public static func toUnifiedVoices(_ models: [String: SherpaOnnxModelEntry]) -> [UnifiedVoice] {
        models.compactMap { _, entry -> UnifiedVoice? in
            guard let _ = entry.url else { return nil }
            return UnifiedVoice(
                id: entry.id,
                name: entry.name ?? entry.id,
                gender: entry.resolvedGender,
                provider: "sherpaonnx",
                languageCodes: [
                    UnifiedVoice.LanguageCode(
                        bcp47: entry.bcp47Code,
                        iso639_3: String(entry.bcp47Code.split(separator: "-").first ?? "en"),
                        display: entry.displayLanguage
                    )
                ]
            )
        }
    }
}
