//
//  APIConfig.swift
//  CabFit
//
//  Where the app talks to, and nothing else.
//

import Foundation

/// The API endpoint.
///
/// This is a compile-time constant on purpose. There is no setting, no text field and
/// no debug menu anywhere in the app that can repoint the client at another host:
/// a build talks to this origin or to nothing. Changing it means shipping a new build.
enum APIConfig {

    /// Production origin. The API is deployed at the domain root, so routes are
    /// reached as /v1/... with no path prefix. If it is ever moved into a
    /// subdirectory, add the prefix here — the server detects its own mount point.
    static let baseURL = URL(string: "https://cabfit-app.space")!

    /// Sent with every request so the server can tell builds apart in its logs.
    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    static let requestTimeout: TimeInterval = 20
    static let uploadTimeout: TimeInterval = 60

    /// How long the app waits after a failed sync before trying again, in seconds.
    /// Backs off so a server outage does not turn into a retry storm.
    static let retryBackoff: [TimeInterval] = [5, 15, 60, 300]
}
