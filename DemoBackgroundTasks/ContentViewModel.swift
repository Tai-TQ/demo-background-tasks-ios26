//
//  ContentViewModel.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 19/3/26.
//

import BackgroundTasks
import Combine
import SwiftUI

enum TaskState {
    case notRunning
    case running
    case cancelling
}

final class ContentViewModel: ObservableObject {
    @Published var countPercentState: TaskState = .notRunning
    @Published var countPercentComplete: Int = 0
    private var countPercentTaskId: String?

    @Published var downloadState: DownloadState = .notStarted
    @Published var downloadProgressPercent: Int = 0
    private var downloadTaskId: String?

    @Published var exportState: ExportState = .notStarted
    @Published var exportProgressPercent: Int = 0
    private var exportTaskId: String?

    private let downloader = VideoDownloadManager()
    private let exporter = VideoOverlayExporter()
    private let cancellables: Set<AnyCancellable> = []
    private var downloadCancellables = Set<AnyCancellable>()
    private var exportCancellables = Set<AnyCancellable>()

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
        guard downloadState != .downloading else { return }
        do {
            let taskId = try BackgroundTaskWrapper.shared.execute(
                type: .download,
                strategy: .queue,
                title: "Download Video",
                subtitle: "Downloading...",
                launchHandler: { [weak self] taskId in
                    guard let self else { return }
                    downloader.progressSubject
                        .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
                        .sink { percent in
                            do {
                                try BackgroundTaskWrapper.shared.updateProgress(
                                    for: taskId,
                                    completedUnitCount: Int64(percent),
                                    subtitle: "Downloading \(percent)%"
                                )
                                NSLog("[Download Video] Updated progress for \(taskId), completed: \(percent)%")
                            } catch {
                                NSLog("[Download Video] Failed to update progress: \(error)")
                            }
                        }
                        .store(in: &downloadCancellables)

                    downloader.stateSubject
                        .filter { $0 == .completed || $0 == .failed }
                        .first()
                        .sink { [weak self] _ in
                            BackgroundTaskWrapper.shared.finish(taskId: taskId)
                            DispatchQueue.main.async { [weak self] in
                                self?.downloadTaskId = nil
                                self?.downloadCancellables.removeAll()
                            }
                        }
                        .store(in: &downloadCancellables)

                    downloader.start(url: Self.videoURL)
                },
                expirationHandler: { [weak self] taskId in
                    guard let self else { return }
                    NSLog("[Download Video] Task \(taskId) expired by system")
                    downloadCancellables.removeAll()
                    downloader.cancel()
                    DispatchQueue.main.async { [weak self] in
                        self?.downloadTaskId = nil
                    }
                }
            )
            downloadTaskId = taskId
            NSLog("[Download Video] Executed download task with ID: \(taskId)")
        } catch {
            NSLog("[Download Video] Failed to execute download task: \(error)")
            downloadState = .notStarted
        }
    }

    func finishDownloadingVideo() {
        guard downloadState == .downloading,
              let taskId = downloadTaskId else { return }

        BackgroundTaskWrapper.shared.finish(taskId: taskId)
        NSLog("[Download Video] Finished task \(taskId)")
        downloadCancellables.removeAll()
        downloader.cancel()
        downloadTaskId = nil
    }

    // MARK: - Export Video with Overlay

    func handleExportVideo() {
        guard exportState != .exporting else { return }

        guard FileManager.default.fileExists(atPath: Constants.videoFileUrl.path) else {
            NSLog("No downloaded video found — download the video first")
            return
        }
        do {
            let taskId = try BackgroundTaskWrapper.shared.execute(
                type: .export,
                strategy: .queue,
                title: "Export Video with Overlay",
                subtitle: "Preparing...",
                launchHandler: { [weak self] taskId in
                    guard let self else { return }
                    exporter.progressSubject
                        .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
                        .sink { percent in
                            do {
                                try BackgroundTaskWrapper.shared.updateProgress(
                                    for: taskId,
                                    completedUnitCount: Int64(percent),
                                    subtitle: "Exporting \(percent)%"
                                )
                                NSLog("[Export Video] Updated progress for \(taskId), completed: \(percent)%")
                            } catch {
                                NSLog("[Export Video] Failed to update progress: \(error)")
                            }
                        }
                        .store(in: &exportCancellables)

                    exporter.stateSubject
                        .filter { $0 == .completed || $0 == .failed }
                        .first()
                        .sink { [weak self] _ in
                            BackgroundTaskWrapper.shared.finish(taskId: taskId)
                            DispatchQueue.main.async { [weak self] in
                                self?.exportTaskId = nil
                                self?.exportCancellables.removeAll()
                            }
                        }
                        .store(in: &exportCancellables)

                    exporter.exportProcessedVideo(inputURL: Constants.videoFileUrl)
                },
                expirationHandler: { [weak self] taskId in
                    guard let self else { return }
                    NSLog("[Export Video] Task \(taskId) expired by system")
                    exportCancellables.removeAll()
                    exporter.cancel()
                    DispatchQueue.main.async { [weak self] in
                        self?.exportTaskId = nil
                    }
                }
            )
            exportTaskId = taskId
            NSLog("[Export Video] Executed export task with ID: \(taskId)")
        } catch {
            NSLog("[Export Video] Failed to execute export task: \(error)")
            exportState = .notStarted
        }
    }

    func finishExportingVideo() {
        guard exportState == .exporting,
              let taskId = exportTaskId else { return }

        BackgroundTaskWrapper.shared.finish(taskId: taskId)
        NSLog("[Export Video] Finished task \(taskId)")
        exportCancellables.removeAll()
        exporter.cancel()
        exportTaskId = nil
    }

    // MARK: - Processing Task

    func handleCountHundredByProcessingTask() {
        guard countPercentState != .running else { return }
        countPercentState = .running
        do {
            let taskId = try BackgroundTaskWrapper.shared.execute(
                type: .count,
                title: "Count 100 seconds",
                subtitle: "Starting...",
                launchHandler: { [weak self] taskId in
                    guard let self else { return }
                    var count = 0
                    while countPercentState == .running {
                        count += 1

                        if count == 100 {
                            finishCountingTask()
                        }
                        do {
                            try BackgroundTaskWrapper.shared.updateProgress(for: taskId,
                                                                            completedUnitCount: Int64(count),
                                                                            subtitle: "Counting...(\(count)/100)")
                            NSLog("[Counting Task] Updated progress for \(taskId), completed: \(count)%")
                            DispatchQueue.main.async { [weak self] in
                                guard let self else { return }
                                countPercentComplete = count
                            }
                        } catch {
                            NSLog("[Counting Task] Failed to update progress: \(error)")
                        }
                        sleep(1)
                    }
                },
                expirationHandler: { [weak self] taskId in
                    guard let self else { return }
                    NSLog("[Counting Task] Task \(taskId) expired by system")
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        countPercentState = .notRunning
                        countPercentComplete = 0
                        countPercentTaskId = nil
                    }
                }
            )
            countPercentTaskId = taskId
            NSLog("[Counting Task] Excuted task with ID: \(taskId)")
        } catch {
            NSLog("[Counting Task] Failed to excute task: \(error)")
        }
    }

    func finishCountingTask() {
        guard countPercentState == .running,
              let taskId = countPercentTaskId else { return }

        BackgroundTaskWrapper.shared.finish(taskId: taskId)
        NSLog("[Counting Task] Finish counting task: \(taskId)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            countPercentState = .notRunning
            countPercentComplete = 0
            countPercentTaskId = nil
        }
    }
}
