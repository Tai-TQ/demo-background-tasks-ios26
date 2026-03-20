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

    @Published var downloadState: DownloadState = .notStarted
    @Published var downloadProgressPercent: Int = 0

    @Published var exportState: ExportState = .notStarted
    @Published var exportProgressPercent: Int = 0

    private let downloader = VideoDownloadManager()
    private let exporter   = VideoOverlayExporter()
    private let cancellables: Set<AnyCancellable> = []

    init() {
        downloader.progressSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$downloadProgressPercent)

        downloader.stateSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$downloadState)

        exporter.progressSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$exportProgressPercent)

        exporter.stateSubject
            .receive(on: DispatchQueue.main)
            .assign(to: &$exportState)
    }

    // MARK: - Download Video

    private static let videoURL = URL(string: "https://ia601903.us.archive.org/32/items/BigBuckBunny_328/BigBuckBunny_512kb.mp4")!

    func handleDownloadVideo() {
        if downloadState == .downloading {
            downloader.cancel()
            return
        }

        let title = "Download Video"
        let taskId = "\(Bundle.main.bundleIdentifier!).download.\(UUID().uuidString)"

        // 1. Register – the download is started inside launchHandler so it runs
        //    within the BGContinuedProcessingTask's background execution window.
        NSLog("Start Register \(taskId)")
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { [weak self] task in
            guard let self,
                  let bgTask = task as? BGContinuedProcessingTask else { return }
            // Delegate all download progress & BGTask lifecycle to the manager.
            self.downloader.start(url: Self.videoURL, bgTask: bgTask)
        }

        // 2. Submit
        NSLog("Start Submit \(taskId)")
        let request = BGContinuedProcessingTaskRequest(
            identifier: taskId,
            title: title,
            subtitle: "Downloading..."
        )
        request.strategy = .queue

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            downloadState = .notStarted
            NSLog("Failed to submit download task: \(error)")
        }
    }

    // MARK: - Export Video with Overlay

    func handleExportVideo() {
        if exportState == .exporting {
            exporter.cancel()
            return
        }

        guard FileManager.default.fileExists(atPath: Constants.videoFileUrl.path) else {
            NSLog("No downloaded video found — download the video first")
            return
        }

        let title  = "Export Video with Overlay"
        let taskId = "\(Bundle.main.bundleIdentifier!).export.\(UUID().uuidString)"

        // 1. Register
        NSLog("Start Register \(taskId)")
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { [weak self] task in
            guard let self,
                  let bgTask = task as? BGContinuedProcessingTask else { return }
            self.exporter.exportProcessedVideo(inputURL: Constants.videoFileUrl, bgTask: bgTask)
        }

        // 2. Submit
        NSLog("Start Submit \(taskId)")
        let request = BGContinuedProcessingTaskRequest(
            identifier: taskId,
            title: title,
            subtitle: "Preparing..."
        )
        if BGTaskScheduler.supportedResources.contains(.gpu) {
            request.requiredResources = .gpu
            NSLog("\(taskId) using GPU")
        }
        request.strategy = .queue

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            exportState = .notStarted
            NSLog("Failed to submit export task: \(error)")
        }
    }

    // MARK: - Processing Task

    func handleCountHundredByProcessingTask() {
        if countPercentState == .running { return }
        countPercentState = .running
        let title = "ProcessingTask count 100 seconds"
        let taskId = "\(Bundle.main.bundleIdentifier!).counthundred.\(UUID().uuidString)"

        // 1. Register
        NSLog("Start Register \(taskId)")
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { [weak self] task in
            NSLog("Start running launchHandler block")
            guard let self,
                  let task = task as? BGContinuedProcessingTask else { return }

            // Flag to prevent calling setTaskCompleted more than once.
            var isCompleted = false

            // Per doc section 4: when the user force-quits the app while the task
            // is running, the system calls expirationHandler and the process will
            // be killed very shortly after. We must call setTaskCompleted HERE,
            // immediately — not after the loop, because sleep(1) may still be
            // blocking the loop thread when the process is killed.
            task.expirationHandler = { [weak task] in
                guard !isCompleted else { return }
                isCompleted = true
                task?.setTaskCompleted(success: false)
            }

            // Update progress.
            let progress = task.progress
            progress.totalUnitCount = 100
            while !progress.isFinished && !isCompleted && self.countPercentState == .running {
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

            // Only call setTaskCompleted if expirationHandler hasn't already done so.
            if !isCompleted {
                isCompleted = true
                task.setTaskCompleted(success: progress.isFinished)
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
