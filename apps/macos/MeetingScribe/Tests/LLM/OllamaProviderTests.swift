import Testing
import Foundation
@testable import MeetingScribe

@Suite("OllamaProvider")
struct OllamaProviderTests {

    @Test("listModels parses tags response")
    func testListModelsParsesTagsResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/tags")
            let json = """
            {"models":[{"name":"llama3.2:latest","size":2000000000,"modified_at":"2024-01-01T00:00:00Z"},{"name":"mistral:7b","size":4000000000,"modified_at":"2024-01-02T00:00:00Z"}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let provider = OllamaProvider(endpoint: "http://localhost:11434", model: "llama3.2", urlSession: mockSession())
        let models = try await provider.listModels()
        #expect(models.count == 2)
        #expect(models[0].name == "llama3.2:latest")
        MockURLProtocol.requestHandler = nil
    }

    @Test("summarize streams NDJSON deltas")
    func testSummarizeStreamsNDJSONDeltas() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/v1/chat/completions")
            #expect(request.httpMethod == "POST")
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
        #expect(collected == "Hello world!")
        #expect(result == "Hello world!")
        MockURLProtocol.requestHandler = nil
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// URLProtocol subclass that lets tests inject canned responses.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

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
