import Foundation

/// Icon discovery deliberately stays on the page’s origin, including through redirects.
enum FaviconPolicy {
    static let htmlLimit = 256 * 1024
    static let imageLimit = 512 * 1024

    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host?.lowercased() == b.host?.lowercased()
            && ServiceCatalog.port(of: a) == ServiceCatalog.port(of: b)
    }

    static func resolve(_ reference: String, relativeTo page: URL) -> URL? {
        guard let url = URL(string: reference, relativeTo: page)?.absoluteURL,
              BrowserAddress.parse(url.absoluteString) != nil, sameOrigin(url, page) else { return nil }
        return url
    }

    static func candidates(in html: String, page: URL) -> [URL] {
        let cleaned = html.replacingOccurrences(of: "(?is)<!--.*?--!?>|<script\\b[^>]*>.*?</script\\b[^>]*>", with: "", options: .regularExpression)
        let links = try! NSRegularExpression(pattern: "(?is)<link\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>")
        let attributes = try! NSRegularExpression(pattern: #"(?is)([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        var urls: [URL] = []
        for match in links.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            let tag = (cleaned as NSString).substring(with: match.range)
            var values: [String: String] = [:]
            for attribute in attributes.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                let key = (tag as NSString).substring(with: attribute.range(at: 1)).lowercased()
                let valueRange = (2...4).map { attribute.range(at: $0) }.first { $0.location != NSNotFound }!
                values[key] = entities((tag as NSString).substring(with: valueRange))
            }
            guard values["rel"]?.lowercased().split(whereSeparator: { $0.isWhitespace }).contains("icon") == true,
                  let href = values["href"], let url = resolve(href, relativeTo: page), !urls.contains(url) else { continue }
            urls.append(url)
            if urls.count == 8 { break }
        }
        if let fallback = resolve("/favicon.ico", relativeTo: page), !urls.contains(fallback) { urls.append(fallback) }
        return urls
    }

    private static func entities(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let number = (text as NSString).substring(with: match.range(at: 1))
            let value = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
            if let value, let scalar = UnicodeScalar(value), let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: String(scalar))
            }
        }
        for (entity, character) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}

struct FaviconResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data
}

/// Incremental HTTP framing, separate from the diagnostics’ intentionally short page peek.
enum FaviconHTTP {
    enum Result {
        case incomplete, rejected
        case complete(FaviconResponse)
    }

    static func parse(_ data: Data, limit: Int, eof: Bool = false) -> Result {
        guard data.count <= limit * 2 + 16_384 else { return .rejected }
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16_384 || eof ? .rejected : .incomplete
        }
        guard boundary.lowerBound <= 16_384,
              let head = String(data: data[..<boundary.lowerBound], encoding: .isoLatin1) else { return .rejected }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first, first.hasPrefix("HTTP/1."),
              let status = first.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) else { return .rejected }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .rejected }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let previous = headers[key] {
                guard !["content-length", "transfer-encoding", "content-encoding", "location"].contains(key) else { return .rejected }
                headers[key] = previous + ", " + value
            } else {
                headers[key] = value
            }
        }
        var response = FaviconResponse(status: status, headers: headers, body: Data())
        // Redirects and failures don’t need a body.
        guard status == 200 else { return .complete(response) }
        guard headers["content-encoding"].map({ $0.lowercased() == "identity" }) ?? true else { return .rejected }
        let body = Data(data[boundary.upperBound...])
        if let transfer = headers["transfer-encoding"] {
            guard transfer.lowercased() == "chunked", headers["content-length"] == nil else { return .rejected }
            var cursor = body.startIndex
            while true {
                guard let end = body.range(of: Data("\r\n".utf8), in: cursor..<body.endIndex) else { return eof ? .rejected : .incomplete }
                guard let line = String(data: body[cursor..<end.lowerBound], encoding: .ascii),
                      let count = Int(line.split(separator: ";", omittingEmptySubsequences: false)[0], radix: 16),
                      count >= 0, count <= limit - response.body.count else { return .rejected }
                cursor = end.upperBound
                if count == 0 { return .complete(response) }
                guard body.endIndex - cursor >= count + 2 else { return eof ? .rejected : .incomplete }
                let next = cursor + count
                guard body[next..<next + 2] == Data("\r\n".utf8) else { return .rejected }
                response.body.append(body[cursor..<next])
                cursor = next + 2
            }
        }
        if let length = headers["content-length"] {
            guard let size = Int(length), size >= 0, size <= limit else { return .rejected }
            guard body.count >= size else { return eof ? .rejected : .incomplete }
            response.body = Data(body.prefix(size))
            return .complete(response)
        }
        guard body.count <= limit else { return .rejected }
        guard eof else { return .incomplete }
        response.body = body
        return .complete(response)
    }
}
