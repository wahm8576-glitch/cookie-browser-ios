import Foundation

struct ParsedCookie: Equatable, Identifiable {
    var id: String { "\(name)|\(domain ?? "")|\(path)" }

    var name: String
    var value: String
    var domain: String?
    var path: String
    var isSecure: Bool
    var isHTTPOnly: Bool
    var expires: Date?

    func asHTTPCookie(fallbackDomain: String?) -> HTTPCookie? {
        let resolvedDomain = Self.normalizeDomain(domain ?? fallbackDomain)
        guard !name.isEmpty, let resolvedDomain, !resolvedDomain.isEmpty else { return nil }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: resolvedDomain,
            .path: path.isEmpty ? "/" : path
        ]

        if isSecure {
            properties[.secure] = "TRUE"
        }

        let expiry = expires ?? Calendar.current.date(byAdding: .year, value: 10, to: Date())
        if let expiry {
            properties[.expires] = expiry
        }

        if isHTTPOnly {
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }

    private static func normalizeDomain(_ raw: String?) -> String? {
        guard var domain = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty else {
            return nil
        }
        if let schemeRange = domain.range(of: "://") {
            domain = String(domain[schemeRange.upperBound...])
        }
        if let slash = domain.firstIndex(of: "/") {
            domain = String(domain[..<slash])
        }
        if let colon = domain.firstIndex(of: ":"), !domain.hasPrefix("[") {
            domain = String(domain[..<colon])
        }
        return domain
    }
}

enum CookieParser {
    /// Parses cookie export text. Supports:
    /// 1. Multi-line export blocks (`name = value` + indented attribute line)
    /// 2. A raw Cookie header (`name=value; name2=value2`)
    /// Values are kept as-is (not URL-decoded).
    static func parse(_ text: String, fallbackDomain: String? = nil) -> [ParsedCookie] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var collected: [ParsedCookie] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }

            // Indented attribute line with no preceding name line — skip.
            if isIndented(rawLine) && looksLikeAttributeLine(trimmed) {
                index += 1
                continue
            }

            let nextRaw = peekNextMeaningful(lines, after: index)
            if let nextRaw, isIndented(nextRaw.line), looksLikeAttributeLine(nextRaw.trimmed) {
                if let nameValue = parseNameValue(trimmed) {
                    var cookie = ParsedCookie(
                        name: nameValue.name,
                        value: nameValue.value,
                        domain: fallbackDomain,
                        path: "/",
                        isSecure: false,
                        isHTTPOnly: false,
                        expires: nil
                    )
                    applyAttributes(nextRaw.trimmed, to: &cookie)
                    collected.append(cookie)
                    index = nextRaw.index + 1
                    continue
                }
            }

            if looksLikeCookieHeader(trimmed), let headerCookies = parseCookieHeader(trimmed, fallbackDomain: fallbackDomain) {
                collected.append(contentsOf: headerCookies)
                index += 1
                continue
            }

            if let nameValue = parseNameValue(trimmed) {
                collected.append(
                    ParsedCookie(
                        name: nameValue.name,
                        value: nameValue.value,
                        domain: fallbackDomain,
                        path: "/",
                        isSecure: false,
                        isHTTPOnly: false,
                        expires: farFuture()
                    )
                )
            }
            index += 1
        }

        return deduplicate(collected)
    }

    static func parseCookieHeader(_ header: String, fallbackDomain: String?) -> [ParsedCookie]? {
        var input = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.lowercased().hasPrefix("cookie:") {
            input = String(input.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }

        let parts = input.split(separator: ";", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return nil }

        var cookies: [ParsedCookie] = []
        for part in parts {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = parseNameValue(piece) else { continue }
            if isReservedAttributeName(parsed.name) { continue }
            cookies.append(
                ParsedCookie(
                    name: parsed.name,
                    value: parsed.value,
                    domain: fallbackDomain,
                    path: "/",
                    isSecure: false,
                    isHTTPOnly: false,
                    expires: farFuture()
                )
            )
        }
        return cookies.isEmpty ? nil : cookies
    }

    // MARK: - Line helpers

    private static func isIndented(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first == " " || first == "\t"
    }

    private static func looksLikeAttributeLine(_ trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        return lower.contains("domain=")
            || lower.contains("path=")
            || lower.contains("secure=")
            || lower.contains("httponly=")
            || lower.contains("expires=")
    }

    private static func looksLikeCookieHeader(_ trimmed: String) -> Bool {
        trimmed.contains(";") && trimmed.contains("=")
    }

    private static func peekNextMeaningful(_ lines: [String], after index: Int) -> (index: Int, line: String, trimmed: String)? {
        var i = index + 1
        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                i += 1
                continue
            }
            if trimmed.hasPrefix("#") {
                return nil
            }
            return (i, raw, trimmed)
        }
        return nil
    }

    /// Splits on the first `=`. Does not URL-decode the value.
    static func parseNameValue(_ text: String) -> (name: String, value: String)? {
        guard let eq = text.firstIndex(of: "=") else { return nil }
        var name = String(text[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
        var value = String(text[text.index(after: eq)...])

        // Trim surrounding whitespace only — keep the raw value otherwise.
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2)
            || (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2) {
            value = String(value.dropFirst().dropLast())
        }

        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !name.isEmpty, !isReservedAttributeName(name) else { return nil }
        return (name, value)
    }

    private static func isReservedAttributeName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["domain", "path", "expires", "max-age", "secure", "httponly", "samesite", "priority", "version"].contains(lower)
    }

    // MARK: - Attributes

    private static func applyAttributes(_ line: String, to cookie: inout ParsedCookie) {
        if let domain = extractToken(named: "domain", from: line) {
            cookie.domain = domain
        }
        if let path = extractToken(named: "path", from: line) {
            cookie.path = path
        }
        if let secure = extractToken(named: "secure", from: line) {
            cookie.isSecure = isTruthy(secure)
        } else if containsBareFlag("secure", in: line) {
            cookie.isSecure = true
        }
        if let httpOnly = extractToken(named: "httponly", from: line) ?? extractToken(named: "httpOnly", from: line) {
            cookie.isHTTPOnly = isTruthy(httpOnly)
        } else if containsBareFlag("httponly", in: line) {
            cookie.isHTTPOnly = true
        }
        if let expiresRaw = extractExpires(from: line) {
            cookie.expires = parseExpiry(expiresRaw) ?? farFuture()
        } else {
            cookie.expires = farFuture()
        }
    }

    /// Extracts `key=value` where value has no spaces (domain, path, flags).
    private static func extractToken(named key: String, from line: String) -> String? {
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange])
    }

    /// Expires values contain spaces, Arabic AM/PM, and a timezone, so they run to the next key or end of line.
    private static func extractExpires(from line: String) -> String? {
        let pattern = "(?i)\\bexpires\\s*=\\s*(.+?)(?=\\s+(?:domain|path|secure|httponly|samesite|max-age)\\s*=|\\s*$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsBareFlag(_ flag: String, in line: String) -> Bool {
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: flag))\\b(?!\\s*=)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    private static func isTruthy(_ raw: String) -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes", "true", "1", "y", "on":
            return true
        default:
            return false
        }
    }

    // MARK: - Dates

    static func parseExpiry(_ raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Arabic / Latin day-period markers.
        var isPM: Bool?
        let pmTokens = ["مساءً", "مساء", "م", "PM", "pm", "P.M.", "p.m."]
        let amTokens = ["صباحاً", "صباحا", "ص", "AM", "am", "A.M.", "a.m."]

        // Prefer longer tokens first so "مساءً" is consumed before "م".
        for token in pmTokens.sorted(by: { $0.count > $1.count }) {
            if let range = text.range(of: token, options: [.diacriticInsensitive]) {
                // Avoid treating a lone Arabic letter mid-word; require it as its own chunk or flanked by spaces.
                if token.count == 1 && token == "م" {
                    if !isStandaloneMarker(in: text, range: range) { continue }
                }
                isPM = true
                text.removeSubrange(range)
                break
            }
        }
        if isPM == nil {
            for token in amTokens.sorted(by: { $0.count > $1.count }) {
                if let range = text.range(of: token, options: [.diacriticInsensitive]) {
                    if token.count == 1 && token == "ص" {
                        if !isStandaloneMarker(in: text, range: range) { continue }
                    }
                    isPM = false
                    text.removeSubrange(range)
                    break
                }
            }
        }

        text = text.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // `yyyy-MM-dd H:mm:ss Z` with optional timezone.
        let pattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{2}:?\d{2}|Z)?$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
            func group(_ i: Int) -> String? {
                guard let r = Range(match.range(at: i), in: text), match.range(at: i).location != NSNotFound else { return nil }
                return String(text[r])
            }
            guard let year = Int(group(1) ?? ""),
                  let month = Int(group(2) ?? ""),
                  let day = Int(group(3) ?? ""),
                  let hourRaw = Int(group(4) ?? ""),
                  let minute = Int(group(5) ?? "") else { return nil }
            let second = Int(group(6) ?? "0") ?? 0
            var hour = hourRaw
            if let isPM {
                if hour < 12, isPM { hour += 12 }
                if hour == 12, isPM == false { hour = 0 }
            }

            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            components.second = second

            let tzString = group(7)
            components.timeZone = parseTimeZone(tzString) ?? TimeZone(secondsFromGMT: 0)

            return Calendar(identifier: .gregorian).date(from: components)
        }

        // RFC 1123 / HTTP-date and a few other common formats.
        let formatters: [DateFormatter] = {
            let formats = [
                "yyyy-MM-dd HH:mm:ss Z",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "EEE, dd MMM yyyy HH:mm:ss zzz",
                "EEE, dd-MMM-yyyy HH:mm:ss zzz",
                "EEE MMM dd yyyy HH:mm:ss zzz"
            ]
            return formats.map { format in
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = format
                return f
            }
        }()
        for formatter in formatters {
            if let date = formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? formatter.date(from: text) {
                return date
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }

        return nil
    }

    private static func isStandaloneMarker(in text: String, range: Range<String.Index>) -> Bool {
        let beforeOK: Bool = {
            if range.lowerBound == text.startIndex { return true }
            let prev = text[text.index(before: range.lowerBound)]
            return prev.isWhitespace
        }()
        let afterOK: Bool = {
            if range.upperBound == text.endIndex { return true }
            let next = text[range.upperBound]
            return next.isWhitespace || next == "+" || next == "-"
        }()
        return beforeOK && afterOK
    }

    private static func parseTimeZone(_ raw: String?) -> TimeZone? {
        guard var raw, !raw.isEmpty else { return TimeZone(secondsFromGMT: 0) }
        if raw == "Z" || raw == "z" { return TimeZone(secondsFromGMT: 0) }
        raw = raw.replacingOccurrences(of: ":", with: "")
        guard raw.count == 5, let sign = raw.first, sign == "+" || sign == "-" else {
            return TimeZone(secondsFromGMT: 0)
        }
        let hours = Int(raw.dropFirst().prefix(2)) ?? 0
        let minutes = Int(raw.suffix(2)) ?? 0
        var seconds = (hours * 3600) + (minutes * 60)
        if sign == "-" { seconds = -seconds }
        return TimeZone(secondsFromGMT: seconds)
    }

    static func farFuture() -> Date {
        Calendar.current.date(byAdding: .year, value: 10, to: Date())
            ?? Date().addingTimeInterval(60 * 60 * 24 * 365 * 10)
    }

    /// Prefer the more detailed record (one that already has a domain or flags) when names collide.
    private static func deduplicate(_ cookies: [ParsedCookie]) -> [ParsedCookie] {
        var result: [ParsedCookie] = []
        for cookie in cookies {
            if let existing = result.firstIndex(where: { $0.name == cookie.name && ($0.domain ?? "") == (cookie.domain ?? "") }) {
                let existingScore = detailScore(result[existing])
                let newScore = detailScore(cookie)
                if newScore >= existingScore {
                    result[existing] = cookie
                }
            } else {
                result.append(cookie)
            }
        }
        return result
    }

    private static func detailScore(_ cookie: ParsedCookie) -> Int {
        var score = 0
        if cookie.domain != nil { score += 2 }
        if cookie.isSecure { score += 1 }
        if cookie.isHTTPOnly { score += 1 }
        if cookie.expires != nil { score += 1 }
        if cookie.path != "/" { score += 1 }
        return score
    }
}
