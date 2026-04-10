import XCTest
@testable import MeetingScribe

final class OllamaProviderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testListModelsParsesTagsResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            let json = """
            {"models":[{"name":"llama3.2:latest","size":2000000000,"modified_at":"2024-01-01T00:00:00Z"},{"name":"mistral:7b","size":4000000000,"modified_at":"2024-01-02T00:00:00Z"}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let provider = OllamaProvider(endpoint: "http://localhost:11434", model: "llama3.2", urlSession: mockSession())
        let models = try await provider.listModels()
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].name, "llama3.2:latest")
    }

    func testSummarizeStreamsNDJSONDeltas() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            // SSE stream: 3 chunks + [DONE]
            let body = """
            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[{"delta":{"content":" world"}}]}

            data: {"choices":[{"delta":{"content":"!"}}]}

            data: [DONE]


            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            return (response, body)
        }

        let provider = OllamaProvider(endpoint: "http://localhost:11434", model: "llama3.2", urlSession: mockSession())
        var collected = ""
        let result = try await provider.summarize(transcript: "Test transcript", template: "default") { delta in
            collected += delta
        }
        XCTAssertEqual(collected, "Hello world!")
        XCTAssertEqual(result, "Hello world!")
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// URLProtocol subclass that lets tests inject canned responses.
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: 0))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
