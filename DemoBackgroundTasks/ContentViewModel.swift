//
//  ContentViewModel.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 19/3/26.
//

import SwiftUI
import Combine
import BackgroundTasks

enum TaskState {
    case notRunning
    case running
    case cancelling
}

final class ContentViewModel: ObservableObject {
    @Published var countPercentState: TaskState = .notRunning
    @Published var countPercentComplete: Int = 0
    
    func handleCountHundredByProcessingTask() {
        if countPercentState == .running { return }
        countPercentState = .running
        let title = "ProcessingTask count 100 seconds"
        let taskId = "\(Bundle.main.bundleIdentifier!).\(UUID().uuidString)"
        
        // 1. Register
        NSLog("Start Register \(taskId)")
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { [weak self] task in
            NSLog("Start running launchHandler block")
            guard let self,
                  let task = task as? BGContinuedProcessingTask else { return }
            
            // Check the expiration handler to confirm job completion.
            var wasExpired = false
            task.expirationHandler = {
                wasExpired = true
            }

            // Update progress.
            let progress = task.progress
            progress.totalUnitCount = 100
            while !progress.isFinished && !wasExpired && self.countPercentState == .running {
                progress.completedUnitCount += 1
                let formattedProgress = String(format: "%.2f", progress.fractionCompleted * 100)

                // Update task for displayed progress.
                task.updateTitle(task.title, subtitle: "Completed \(formattedProgress)%")

                // Update published property so UI re-renders.
                DispatchQueue.main.async {
                    self.countPercentComplete = Int(progress.completedUnitCount)
                }
                sleep(1)
            }
            // Check progress to confirm job completion.
            if progress.isFinished {
                task.setTaskCompleted(success: true)
            } else {
                task.setTaskCompleted(success: false)
            }
            
            DispatchQueue.main.async {
                self.countPercentState = .notRunning
                self.countPercentComplete = 0
            }
        }
        
        // 2. Submit
        NSLog("Start Submit \(taskId)")
        let request = BGContinuedProcessingTaskRequest(
            identifier: taskId,
            title: title,
            subtitle: "Running..."
        )
        request.strategy = .queue
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            countPercentState = .notRunning
            NSLog("Failed to submit task: \(error)")
        }
    }
}
