import Foundation

@MainActor
final class RemoteMcpClient {
    private struct HTTPJSONResponse {
        let code: Int
        let body: String
    }

    enum ClientError: LocalizedError {
        case invalidEndpoint
        case invalidResponse(String)
        case serverError(String)
        case httpStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Invalid MCP endpoint."
            case let .invalidResponse(message):
                return message
            case let .serverError(message):
                return message
            case let .httpStatus(code, message):
                return "HTTP \(code): \(message)"
            }
        }
    }

    static let shared = RemoteMcpClient()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 40
        configuration.timeoutIntervalForResource = 40
        return URLSession(configuration: configuration)
    }()

    func listTools(server: RemoteMcpStore.ServerRecord) async throws -> [RemoteMcpStore.ToolRecord] {
        let result = try await callMethod(
            server: server,
            method: "tools/list",
            params: [:]
        )
        let tools = (result["tools"] as? [Any]) ?? []
        return tools.compactMap { raw in
            guard let map = deepStringMap(raw) else { return nil }
            let name = (map["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard name.isEmpty == false else { return nil }
            return RemoteMcpStore.ToolRecord(
                serverId: server.id,
                serverName: server.name,
                toolName: name,
                description: (map["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                inputSchema: deepStringMap(map["inputSchema"]) ?? deepStringMap(map["parameters"]) ?? [:]
            )
        }
    }

    func callTool(
        server: RemoteMcpStore.ServerRecord,
        toolName: String,
        arguments: [String: Any]
    ) async throws -> RemoteMcpStore.ToolCallResult {
        let result = try await callMethod(
            server: server,
            method: "tools/call",
            params: [
                "name": toolName,
                "arguments": arguments,
            ]
        )
        let rawData = try JSONSerialization.data(withJSONObject: sanitize(result), options: [.sortedKeys])
        let rawJSONString = String(data: rawData, encoding: .utf8) ?? "{}"
        return RemoteMcpStore.ToolCallResult(
            summaryText: buildSummaryText(result),
            previewJSON: rawJSONString.count > 1200 ? String(rawJSONString.prefix(1200)) + "..." : rawJSONString,
            rawResultJSON: rawJSONString,
            success: (result["isError"] as? Bool) != true
        )
    }

    private func callMethod(
        server: RemoteMcpStore.ServerRecord,
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        if looksLikeSSE(endpoint: server.endpointURL) {
            return try await callSSEMethod(server: server, method: method, params: params)
        }
        _ = try await callJSONRPC(server: server, method: "initialize", params: initializeParams())
        _ = try? await callJSONRPC(server: server, method: "notifications/initialized", params: [:])
        return try await callJSONRPC(server: server, method: method, params: params)
    }

    private func callJSONRPC(
        server: RemoteMcpStore.ServerRecord,
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        let expectResponse = method.hasPrefix("notifications/") == false && method.hasPrefix("$/") == false
        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method,
            "params": params,
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let response = try await postJSON(
            urlString: server.endpointURL,
            bearerToken: server.bearerToken,
            bodyData: bodyData,
            accept: "application/json, text/event-stream"
        )
        if expectResponse == false {
            return [:]
        }
        guard let object = try JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any] else {
            throw ClientError.invalidResponse("Invalid MCP response.")
        }
        if let error = deepStringMap(object["error"]),
           let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           message.isEmpty == false
        {
            throw ClientError.serverError(message)
        }
        return deepStringMap(object["result"]) ?? [:]
    }

    private func callSSEMethod(
        server: RemoteMcpStore.ServerRecord,
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        guard let endpointURL = URL(string: server.endpointURL) else {
            throw ClientError.invalidEndpoint
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 40
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if server.bearerToken.isEmpty == false {
            request.setValue("Bearer \(server.bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse("SSE response missing HTTP metadata.")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode, HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        var iterator = bytes.lines.makeAsyncIterator()
        let messageURL = try await readEndpointEvent(from: &iterator, baseURL: server.endpointURL)

        let initId = UUID().uuidString
        let initializePayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": initId,
            "method": "initialize",
            "params": initializeParams(),
        ]
        let initializeData = try JSONSerialization.data(withJSONObject: initializePayload)
        _ = try await postJSON(
            urlString: messageURL,
            bearerToken: server.bearerToken,
            bodyData: initializeData
        )
        _ = try await readSSEJSONResponse(from: &iterator, requestId: initId)

        let notificationPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [:],
        ]
        let notificationData = try JSONSerialization.data(withJSONObject: notificationPayload)
        _ = try await postJSON(
            urlString: messageURL,
            bearerToken: server.bearerToken,
            bodyData: notificationData
        )

        let requestId = UUID().uuidString
        let requestPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": method,
            "params": params,
        ]
        let requestData = try JSONSerialization.data(withJSONObject: requestPayload)
        _ = try await postJSON(
            urlString: messageURL,
            bearerToken: server.bearerToken,
            bodyData: requestData
        )

        let rawJSON = try await readSSEJSONResponse(from: &iterator, requestId: requestId)
        guard let object = try JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else {
            throw ClientError.invalidResponse("Invalid MCP SSE response.")
        }
        if let error = deepStringMap(object["error"]),
           let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           message.isEmpty == false
        {
            throw ClientError.serverError(message)
        }
        return deepStringMap(object["result"]) ?? [:]
    }

    private func readEndpointEvent(
        from iterator: inout AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator,
        baseURL: String
    ) async throws -> String {
        var currentEvent: String?
        while let line = try await iterator.next() {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("event:") {
                currentEvent = String(trimmed.dropFirst("event:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if trimmed.hasPrefix("data:") {
                let data = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if currentEvent == "endpoint" && data.isEmpty == false {
                    guard let resolved = resolveAgainstBase(baseURL: baseURL, value: data) else {
                        throw ClientError.invalidEndpoint
                    }
                    return resolved
                }
            }
        }
        throw ClientError.invalidResponse("SSE stream closed before endpoint event.")
    }

    private func readSSEJSONResponse(
        from iterator: inout AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator,
        requestId: String
    ) async throws -> String {
        while let line = try await iterator.next() {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.isEmpty || payload == "[DONE]" {
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
                continue
            }
            let rawId = object["id"]
            let payloadID = (rawId as? String) ?? (rawId as? NSNumber)?.stringValue
            if payloadID == requestId || payloadID == "\"\(requestId)\"" {
                return payload
            }
        }
        throw ClientError.invalidResponse("SSE stream closed before RPC response.")
    }

    private func postJSON(
        urlString: String,
        bearerToken: String,
        bodyData: Data,
        accept: String = "application/json"
    ) async throws -> HTTPJSONResponse {
        guard let url = URL(string: urlString) else {
            throw ClientError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if bearerToken.isEmpty == false {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse("HTTP response missing metadata.")
        }
        let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(
                httpResponse.statusCode,
                body.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode) : body
            )
        }
        return HTTPJSONResponse(code: httpResponse.statusCode, body: body.isEmpty ? "{}" : body)
    }

    private func initializeParams() -> [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "clientInfo": [
                "name": "omnibot-ios",
                "version": "1.0",
            ],
        ]
    }

    private func looksLikeSSE(endpoint: String) -> Bool {
        guard let url = URL(string: endpoint) else { return false }
        return url.path.lowercased().hasSuffix("/sse")
    }

    private func resolveAgainstBase(baseURL: String, value: String) -> String? {
        if URL(string: value)?.scheme != nil {
            return value
        }
        guard let base = URL(string: baseURL) else { return nil }
        return URL(string: value, relativeTo: base)?.absoluteURL.absoluteString
    }

    private func buildSummaryText(_ result: [String: Any]) -> String {
        if let contentList = result["content"] as? [[String: Any]] {
            let texts = contentList.compactMap { item -> String? in
                guard (item["type"] as? String) == "text" else { return nil }
                let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.isEmpty ? nil : text
            }
            if texts.isEmpty == false {
                return texts.joined(separator: "\n").prefix(600).description
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: sanitize(result), options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8)
        {
            return String(json.prefix(600))
        }
        return ""
    }

    private func deepStringMap(_ value: Any?) -> [String: Any]? {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.mapValues(sanitize)
        case let dictionary as [AnyHashable: Any]:
            return dictionary.reduce(into: [String: Any]()) { partialResult, entry in
                partialResult[String(describing: entry.key)] = sanitize(entry.value)
            }
        default:
            return nil
        }
    }

    private func sanitize(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.mapValues(sanitize)
        case let dictionary as [AnyHashable: Any]:
            return dictionary.reduce(into: [String: Any]()) { partialResult, entry in
                partialResult[String(describing: entry.key)] = sanitize(entry.value)
            }
        case let array as [Any]:
            return array.map(sanitize)
        default:
            return value
        }
    }
}
