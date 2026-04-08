//
//  BackgroundTaskType.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 8/4/26.
//

import Foundation

public enum BackgroundTaskType: Int {
    case backup = 0
    case restore = 1
    case socialUpload = 2
    case chatUpload = 3

    // TODO: Remove all cases below
    case count = 4
    case download = 5
    case export = 6

    var identifier: String {
        switch self {
        case .backup:
            return "backup"
        case .restore:
            return "restore"
        case .socialUpload:
            return "socialUpload"
        case .chatUpload:
            return "chatUpload"
        case .count:
            return "count"
        case .download:
            return "download"
        case .export:
            return "export"
        }
    }
}
