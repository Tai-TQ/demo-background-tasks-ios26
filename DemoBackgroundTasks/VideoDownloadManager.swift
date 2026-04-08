//
//  VideoDownloadManager.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 20/3/26.
//

import Combine
import Foundation

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
    private var startTime: Date?

    private lazy var session = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    func start(url: URL) {
        startTime = Date()
        NSLog("[Download] Started at %@", ISO8601DateFormatter().string(from: startTime!))
        stateSubject.send(.downloading)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    func cancel() {
        cancelDownload()
        progressSubject.send(0)
        stateSubject.send(.notStarted)
    }

    // MARK: - Private

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension VideoDownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
        progressSubject.send(percent)
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = Constants.videoFileUrl
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        progressSubject.send(100)
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            NSLog("[Download] Completed successfully in %.2f seconds", elapsed)
        }
        stateSubject.send(.completed)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            NSLog("[Download] Failed after %.2f seconds: %@", elapsed, error.localizedDescription)
        }
        stateSubject.send(.failed)
    }
}
