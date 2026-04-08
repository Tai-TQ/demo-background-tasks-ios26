//
//  BGTaskError.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 8/4/26.
//

import Foundation

public let BGTaskErrorDomain = "\(Bundle.main.bundleIdentifier ?? "demo").bgtask"

@objc public enum BGTaskError: Int, Error {
    case notOnMainThread = 1
    case appNotInForeground
    case taskAlreadyRunning
    case taskStillPending
    case notFoundTask
    case unsupportedOSVersion
    case submissionFailed
}

extension BGTaskError: CustomNSError {
    public static var errorDomain: String {
        BGTaskErrorDomain
    }

    public var errorCode: Int {
        rawValue
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .notOnMainThread:
            return [
                NSLocalizedDescriptionKey: "This API must be called on the main thread.",
            ]

        case .appNotInForeground:
            return [
                NSLocalizedDescriptionKey: "The app is not in the foreground.",
            ]

        case .taskAlreadyRunning:
            return [
                NSLocalizedDescriptionKey: "The task is already running.",
            ]

        case .taskStillPending:
            return [
                NSLocalizedDescriptionKey: "The task is still pending.",
            ]

        case .notFoundTask:
            return [
                NSLocalizedDescriptionKey: "The task was not found.",
            ]

        case .unsupportedOSVersion:
            return [
                NSLocalizedDescriptionKey: "This feature is not supported on the current iOS version.",
            ]

        case .submissionFailed:
            return [
                NSLocalizedDescriptionKey: "Failed to submit the background task request.",
            ]
        }
    }
}

public extension NSError {
    static func bgTaskError(
        _ code: BGTaskError,
        underlying: Error? = nil,
        extraUserInfo: [String: Any] = [:]
    ) -> NSError {
        var userInfo = code.errorUserInfo

        if let underlying {
            userInfo[NSUnderlyingErrorKey] = underlying as NSError
        }

        for (key, value) in extraUserInfo {
            userInfo[key] = value
        }

        return NSError(
            domain: BGTaskError.errorDomain,
            code: code.rawValue,
            userInfo: userInfo
        )
    }

    var bgTaskErrorCode: BGTaskError? {
        guard domain == BGTaskError.errorDomain else { return nil }
        return BGTaskError(rawValue: code)
    }
}
