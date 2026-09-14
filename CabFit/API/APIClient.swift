//
//  APIClient.swift
//  CabFit
//
//  The transport: signs requests, refreshes expired tokens once, maps errors.
//

import Foundation

// MARK: - Errors

enum APIError: LocalizedError, Equatable {
    case offline
    case timedOut
    case unauthorized(code: String)
    case forbidden
    case notFound
    case conflict(serverRevision: Int)
    case rateLimited(retryAfter: TimeInterval)
    case quotaExceeded(String)
    case badRequest(String)
    case server(String)
    case decoding(String)
    case keychainUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .offline:            return "No connection."
        case .timedOut:           return "The server took too long to answer."
        case .unauthorized:       return "This device needs to sign in again."
        case .forbidden:          return "This device is not allowed to do that."
        case .notFound:           return "Not found on the server."
        case .conflict:           return "This run changed on another device."
        case .rateLimited:        return "Too many requests — try again shortly."
        case .quotaExceeded(let m): return m
        case .badRequest(let m):  return m
        case .server(let m):      return m
        case .decoding(let m):    return "Unexpected response. \(m)"
        case .keychainUnavailable(let m):
            return "This device's secure storage is unavailable, so syncing is off. \(m)"
        }
    }

    /// Whether retrying the same request later could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited, .server:
            return true
        case .unauthorized, .forbidden, .notFound, .conflict, .badRequest, .decoding,
             .quotaExceeded, .keychainUnavailable:
            return false
        }
    }
}

// MARK: - Wire envelopes

private struct APIErrorBody: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
        let meta: Meta?
    }
    struct Meta: Decodable {
        let retry_after: Double?
        let server_revision: Int?
    }
    let error: Payload
}

struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Double
}

// MARK: - Client

/// One shared instance drives every call. It owns the session tokens and is the only
/// place that knows how to authenticate.
final class APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    /// Serialises token refresh so ten parallel 401s cause one refresh, not ten.
    private let authQueue = DispatchQueue(label: "cabfit.api.auth")
    private var tokens: SessionTokens?
    private var identity: DeviceIdentity?
    /// Single-flight refresh. Two requests refreshing with the same refresh token would
    /// look like a replayed token to the server, which revokes the whole session — so
    /// concurrent callers queue up behind one in-flight attempt instead.
    private var isRenewing = false
    private var renewWaiters: [(Result<Void, APIError>) -> Void] = []

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = APIConfig.requestTimeout
        config.timeoutIntervalForResource = APIConfig.uploadTimeout
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        // Responses are per-device and short-lived; the app keeps its own cache.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.session = URLSession(configuration: config)
        self.tokens = SessionStore.load()
    }

    var hasSession: Bool { authQueue.sync { tokens != nil } }

    // MARK: Authentication

    private enum RenewPlan {
        case alreadyValid
        case waitForInFlight
        case refresh(String)
        case register
    }

    /// Make sure this device has a usable access token, registering on first launch.
    ///
    /// `force` is set when the server has just rejected a token. An unexpired-by-clock
    /// token can still be dead — the session may have been revoked, or the server's
    /// tokens cleared — so trusting the expiry date alone leaves the app retrying a
    /// credential that will never be accepted again.
    func ensureAuthenticated(force: Bool = false,
                             completion: @escaping (Result<Void, APIError>) -> Void) {
        let identity: DeviceIdentity
        do {
            identity = try currentIdentity()
        } catch {
            // Without a Keychain credential there is nothing to authenticate with, and
            // retrying will not change that — say so rather than spinning.
            completion(.failure(.keychainUnavailable(error.localizedDescription)))
            return
        }

        let plan: RenewPlan = authQueue.sync {
            if let current = tokens, !current.needsRefresh, !force {
                return .alreadyValid
            }
            if isRenewing {
                renewWaiters.append(completion)
                return .waitForInFlight
            }
            isRenewing = true
            if let current = tokens { return .refresh(current.refreshToken) }
            return .register
        }

        switch plan {
        case .alreadyValid:
            completion(.success(()))
        case .waitForInFlight:
            break   // the in-flight attempt will call this completion
        case .refresh(let refreshToken):
            refresh(refreshToken) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.finishRenewal(.success(()), completion)
                case .failure(let error):
                    // A refused refresh means the session is gone for good; fall back to
                    // re-authenticating with the Keychain credential.
                    if case .unauthorized = error {
                        self.authenticate(identity) { registerResult in
                            self.finishRenewal(registerResult, completion)
                        }
                    } else {
                        self.finishRenewal(.failure(error), completion)
                    }
                }
            }
        case .register:
            authenticate(identity) { [weak self] result in
                self?.finishRenewal(result, completion)
            }
        }
    }

    /// Release everyone waiting on the single in-flight renewal.
    private func finishRenewal(_ result: Result<Void, APIError>,
                               _ completion: @escaping (Result<Void, APIError>) -> Void) {
        let waiters: [(Result<Void, APIError>) -> Void] = authQueue.sync {
            isRenewing = false
            let pending = renewWaiters
            renewWaiters.removeAll()
            return pending
        }
        completion(result)
        waiters.forEach { $0(result) }
    }

    private func currentIdentity() throws -> DeviceIdentity {
        if let identity = identity { return identity }
        let loaded = try DeviceIdentityStore.loadOrCreate()
        identity = loaded
        return loaded
    }

    private func authenticate(_ identity: DeviceIdentity,
                              completion: @escaping (Result<Void, APIError>) -> Void) {
        let body: [String: Any] = [
            "device_uid": identity.uid,
            "device_secret": identity.secret,
            "platform": "ios",
            "app_version": APIConfig.appVersion
        ]
        // Register is idempotent for a device that already exists with this secret, so
        // one endpoint covers both first launch and a reinstall that kept the Keychain.
        post("/v1/devices/register", body: body, authenticated: false) { [weak self] (result: Result<TokenResponse, APIError>) in
            switch result {
            case .success(let tokens):
                self?.store(tokens)
                completion(.success(()))
            case .failure(let error):
                if case .unauthorized = error {
                    // The uid exists with a different secret — this credential can never
                    // work again, so start over with a fresh one.
                    DeviceIdentityStore.reset()
                    self?.identity = nil
                }
                completion(.failure(error))
            }
        }
    }

    private func refresh(_ refreshToken: String,
                         completion: @escaping (Result<Void, APIError>) -> Void) {
        post("/v1/auth/refresh", body: ["refresh_token": refreshToken], authenticated: false) { [weak self] (result: Result<TokenResponse, APIError>) in
            switch result {
            case .success(let tokens):
                self?.store(tokens)
                completion(.success(()))
            case .failure(let error):
                if case .unauthorized = error {
                    self?.clearSession()
                }
                completion(.failure(error))
            }
        }
    }

    private func store(_ response: TokenResponse) {
        let tokens = SessionTokens(accessToken: response.access_token,
                                   refreshToken: response.refresh_token,
                                   expiresAt: Date().addingTimeInterval(response.expires_in))
        authQueue.sync { self.tokens = tokens }
        SessionStore.save(tokens)
    }

    func clearSession() {
        authQueue.sync { tokens = nil }
        SessionStore.clear()
    }

    // MARK: Verbs

    func get<T: Decodable>(_ path: String,
                           query: [String: String] = [:],
                           completion: @escaping (Result<T, APIError>) -> Void) {
        send(makeRequest("GET", path, query: query), authenticated: true, completion: completion)
    }

    func put<T: Decodable>(_ path: String,
                           body: [String: Any],
                           completion: @escaping (Result<T, APIError>) -> Void) {
        var request = makeRequest("PUT", path)
        attach(body, to: &request)
        send(request, authenticated: true, completion: completion)
    }

    func post<T: Decodable>(_ path: String,
                            body: [String: Any],
                            authenticated: Bool = true,
                            completion: @escaping (Result<T, APIError>) -> Void) {
        var request = makeRequest("POST", path)
        attach(body, to: &request)
        send(request, authenticated: authenticated, completion: completion)
    }

    /// For endpoints that answer 204.
    func delete(_ path: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        send(makeRequest("DELETE", path), authenticated: true) { (result: Result<EmptyBody, APIError>) in
            completion(result.map { _ in () })
        }
    }

    /// Raw bytes, for attachment downloads.
    func download(_ path: String, completion: @escaping (Result<Data, APIError>) -> Void) {
        perform(makeRequest("GET", path), authenticated: true, allowRefresh: true) { result in
            completion(result.map { $0.0 })
        }
    }

    /// Multipart upload, for attachments.
    func upload(_ path: String,
                fileData: Data,
                fileName: String,
                mimeType: String,
                fields: [String: String],
                completion: @escaping (Result<AttachmentDTO, APIError>) -> Void) {
        var request = makeRequest("POST", path)
        let boundary = "cabfit.\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = APIConfig.uploadTimeout

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        for (key, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        send(request, authenticated: true, completion: completion)
    }

    // MARK: Plumbing

    private func makeRequest(_ method: String, _ path: String, query: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components?.url ?? APIConfig.baseURL)
        request.httpMethod = method
        request.setValue(APIConfig.appVersion, forHTTPHeaderField: "X-CabFit-Version")
        return request
    }

    private func attach(_ body: [String: Any], to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
    }

    private func send<T: Decodable>(_ request: URLRequest,
                                    authenticated: Bool,
                                    completion: @escaping (Result<T, APIError>) -> Void) {
        perform(request, authenticated: authenticated, allowRefresh: true) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let (data, status)):
                if T.self == EmptyBody.self || status == 204 || data.isEmpty {
                    // swiftlint:disable:next force_cast
                    completion(.success(EmptyBody() as! T))
                    return
                }
                guard let decoded = try? self?.decoder.decode(T.self, from: data) else {
                    completion(.failure(.decoding(String(data: data.prefix(200), encoding: .utf8) ?? "")))
                    return
                }
                completion(.success(decoded))
            }
        }
    }

    private func perform(_ request: URLRequest,
                         authenticated: Bool,
                         allowRefresh: Bool,
                         completion: @escaping (Result<(Data, Int), APIError>) -> Void) {
        var signed = request
        if authenticated {
            guard let token = authQueue.sync(execute: { tokens?.accessToken }) else {
                completion(.failure(.unauthorized(code: "no_session")))
                return
            }
            signed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        session.dataTask(with: signed) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error as NSError? {
                switch error.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                     NSURLErrorCannotConnectToHost, NSURLErrorDataNotAllowed:
                    completion(.failure(.offline))
                case NSURLErrorTimedOut:
                    completion(.failure(.timedOut))
                default:
                    completion(.failure(.server(error.localizedDescription)))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.server("No response.")))
                return
            }
            let body = data ?? Data()

            if (200..<300).contains(http.statusCode) {
                completion(.success((body, http.statusCode)))
                return
            }

            let apiError = self.mapError(status: http.statusCode, body: body, headers: http)

            // One transparent refresh-and-retry for an expired access token.
            if case .unauthorized(let code) = apiError,
               authenticated, allowRefresh, code == "expired_access_token" || code == "bad_access_token" {
                self.ensureAuthenticated(force: true) { result in
                    switch result {
                    case .success:
                        self.perform(request, authenticated: authenticated, allowRefresh: false, completion: completion)
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                return
            }
            completion(.failure(apiError))
        }.resume()
    }

    private func mapError(status: Int, body: Data, headers: HTTPURLResponse) -> APIError {
        let parsed = try? decoder.decode(APIErrorBody.self, from: body)
        let code = parsed?.error.code ?? "http_\(status)"
        let message = parsed?.error.message ?? "Request failed (\(status))."

        switch status {
        case 400:
            return .badRequest(message)
        case 401:
            return .unauthorized(code: code)
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict(serverRevision: parsed?.error.meta?.server_revision ?? 0)
        case 413:
            return .badRequest(message)
        case 422:
            return .quotaExceeded(message)
        case 429:
            let header = headers.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            return .rateLimited(retryAfter: header ?? parsed?.error.meta?.retry_after ?? 60)
        default:
            return .server(message)
        }
    }
}

/// Placeholder for endpoints that answer 204 with no body.
struct EmptyBody: Decodable {}
