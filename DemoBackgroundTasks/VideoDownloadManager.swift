//
//  VideoDownloadManager.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 20/3/26.
//

import Foundation
import Combine
import BackgroundTasks

enum DownloadState: Equatable {
    case notStarted
    case downloading
    case completed
    case failed
}

final class VideoDownloadManager: NSObject {

    let progressSubject = PassthroughSubject<Int, Never>()
    let stateSubject = PassthroughSubject<DownloadState, Never>()

    private var downloadTask: URLSessionDownloadTask?
    private var bgTask: BGContinuedProcessingTask?
    private let lock = NSLock()
    private var isBGTaskCompleted = false

    private lazy var session = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    /// Start the download. Pass a `BGContinuedProcessingTask` to automatically
    /// bridge download progress → BGTask progress and handle expiration/completion.
    func start(url: URL, bgTask: BGContinuedProcessingTask? = nil) {
        if let bgTask {
            self.bgTask = bgTask
            self.isBGTaskCompleted = false
            bgTask.progress.totalUnitCount = 100
            // Must call setTaskCompleted immediately inside expirationHandler
            // (the process will be killed very shortly after this is called).
            bgTask.expirationHandler = { [weak self] in
                self?.cancelDownload()
                self?.completeBGTask(success: false)
            }
        }
        stateSubject.send(.downloading)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancel() {
        cancelDownload()
        completeBGTask(success: false)
        progressSubject.send(0)
        stateSubject.send(.notStarted)
    }

    // MARK: - Private

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    private func completeBGTask(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !isBGTaskCompleted else { return }
        isBGTaskCompleted = true
        bgTask?.setTaskCompleted(success: success)
        bgTask = nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension VideoDownloadManager: URLSessionDownloadDelegate {

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
        progressSubject.send(percent)
        if let bgTask {
            bgTask.progress.completedUnitCount = Int64(percent)
            bgTask.updateTitle(bgTask.title, subtitle: "Downloading \(percent)%")
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = Constants.videoFileUrl
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        progressSubject.send(100)
        stateSubject.send(.completed)
        completeBGTask(success: true)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        stateSubject.send(.failed)
        completeBGTask(success: false)
    }
}
