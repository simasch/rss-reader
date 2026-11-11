import Foundation

/// Stands in for the Feed Publisher: answers the app's requests from canned responses, so no test reaches the
/// network. Registered for `URLSession.shared`, which `FeedFetcher` uses.
final class FeedPublisherStub: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        case document(String, status: Int = 200, delay: Duration = .zero)
        case redirect(to: URL)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [URL: Answer] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    private var cancelled = false

    /// Starts answering requests; every URL without an answer gets a 404.
    static func install(_ answers: [URL: Answer]) {
        lock.withLock {
            self.answers = answers
            requests = []
        }
        URLProtocol.registerClass(FeedPublisherStub.self)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(FeedPublisherStub.self)
        lock.withLock {
            answers = [:]
            requests = []
        }
    }

    static var receivedRequests: [URLRequest] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let answer = Self.lock.withLock {
            Self.requests.append(request)
            return Self.answers[url]
        }
        switch answer {
        case .redirect(let target):
            let response = HTTPURLResponse(url: url, statusCode: 301, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .document(let body, let status, let delay):
            let deliver = { [self] in
                guard !cancelled else { return }
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "application/xml"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
            if delay == .zero {
                deliver()
            } else {
                let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: deliver)
            }
        case nil:
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        cancelled = true
    }
}

/// Feed and web page documents the Feed Publisher serves in the tests.
enum Documents {
    static func rss(title: String?, items: [(guid: String, title: String)] = [("1", "First"), ("2", "Second")]) -> String {
        let channelTitle = title.map { "<title>\($0)</title>" } ?? ""
        let entries = items.map { "<item><guid>\($0.guid)</guid><title>\($0.title)</title></item>" }.joined()
        return """
        <?xml version="1.0"?>
        <rss version="2.0"><channel>\(channelTitle)<link>https://example.com/</link>\(entries)</channel></rss>
        """
    }

    static func webPage(advertising feeds: [String]) -> String {
        let links = feeds.map { #"<link rel="alternate" type="application/rss+xml" href="\#($0)">"# }.joined()
        return "<!doctype html><html><head><title>Example</title>\(links)</head><body>Hello</body></html>"
    }
}
