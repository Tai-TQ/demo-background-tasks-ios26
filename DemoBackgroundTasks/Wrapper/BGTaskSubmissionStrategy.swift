//
//  BGTaskSubmissionStrategy.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 8/4/26.
//

import BackgroundTasks
import Foundation

public enum BGTaskSubmissionStrategy: Int {
    case fail = 0
    case queue = 1

    @available(iOS 26.0, *)
    func toSubmissionStrategy() -> BGContinuedProcessingTaskRequest.SubmissionStrategy {
        BGContinuedProcessingTaskRequest.SubmissionStrategy(rawValue: rawValue) ?? .fail
    }
}
