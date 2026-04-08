//
//  VideoOverlayExporter.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 20/3/26.
//

import AVFoundation
import Combine
import Photos
import UIKit

enum ExportState: Equatable {
    case notStarted
    case exporting
    case completed
    case failed
}

final class VideoOverlayExporter: NSObject {
    // Subjects for the ViewModel to subscribe to.
    let progressSubject = PassthroughSubject<Int, Never>()
    let stateSubject = PassthroughSubject<ExportState, Never>()

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?
    // Tracks whether cancel() was explicitly called so the export catch-block
    // does not override the .notStarted state already sent by cancel().
    private var exportCancelled = false
    private var startTime: Date?

    // MARK: - Public API

    /// Begins the export pipeline.
    ///
    /// - Parameters:
    ///   - inputURL: Local file URL of the source video.
    func exportProcessedVideo(inputURL: URL) {
        exportCancelled = false

        startTime = Date()
        NSLog("[Export] Started at %@", ISO8601DateFormatter().string(from: startTime!))
        stateSubject.send(.exporting)

        Task {
            await performExport(inputURL: inputURL)
        }
    }

    /// Cancels an in-progress export and resets state to `.notStarted`.
    func cancel() {
        exportCancelled = true
        cancelExportSession()
        progressSubject.send(0)
    }

    // MARK: - Private helpers

    private func cancelExportSession() {
        exportSession?.cancelExport()
        exportSession = nil
        stopProgressPolling()
        stateSubject.send(.notStarted)
    }

    // MARK: - Export pipeline

    private func performExport(inputURL: URL) async {
        let asset = AVURLAsset(url: inputURL)
        do {
            let (composition, videoComposition) = try await buildComposition(asset: asset)

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProcessedVideo_\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: outputURL)

            // AVAssetExportPresetHighestQuality re-encodes the video, which is required
            // when using AVMutableVideoComposition (passthrough cannot composite overlays).
            guard let session = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                stateSubject.send(.failed)

                return
            }

            session.videoComposition = videoComposition
            // outputURL and outputFileType are passed directly to export(to:as:) below.
            session.shouldOptimizeForNetworkUse = true
            exportSession = session

            startProgressPolling(session: session)
            do {
                try await session.export(to: outputURL, as: .mp4)
                stopProgressPolling()
                progressSubject.send(100)
                if let start = startTime {
                    let elapsed = Date().timeIntervalSince(start)
                    NSLog("[Export] Completed successfully in %.2f seconds", elapsed)
                }
                await saveToPhotos(url: outputURL)
                stateSubject.send(.completed)
            } catch {
                stopProgressPolling()
                // If the user explicitly cancelled, state has already been reset by cancel().
                guard !exportCancelled else {
                    exportCancelled = false
                    return
                }
                if let start = startTime {
                    let elapsed = Date().timeIntervalSince(start)
                    NSLog("[Export] Failed after %.2f seconds: %@", elapsed, error.localizedDescription)
                } else {
                    NSLog("Export failed: \(error.localizedDescription)")
                }
                stateSubject.send(.failed)
            }
        } catch {
            NSLog("Export pipeline error: \(error)")
            stateSubject.send(.failed)
        }
    }

    // MARK: - Composition builder

    private func buildComposition(
        asset: AVURLAsset
    ) async throws -> (AVMutableComposition, AVVideoComposition) {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let videoTrack = videoTracks.first else {
            throw NSError(
                domain: "VideoOverlayExporter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No video track found in asset"]
            )
        }

        // Load track properties in parallel.
        async let naturalSizeAsync = videoTrack.load(.naturalSize)
        async let transformAsync = videoTrack.load(.preferredTransform)
        async let frameRateAsync = videoTrack.load(.nominalFrameRate)
        async let durationAsync = asset.load(.duration)

        let naturalSize = try await naturalSizeAsync
        let preferredTransform = try await transformAsync
        let nominalFrameRate = try await frameRateAsync
        let duration = try await durationAsync

        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(
            width: abs(transformedSize.width),
            height: abs(transformedSize.height)
        )

        // --- Composition ---
        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(
                domain: "VideoOverlayExporter",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not add video track to composition"]
            )
        }
        let fullRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(fullRange, of: videoTrack, at: .zero)

        // Preserve audio when present; non-fatal if missing.
        if let audioTrack = audioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            try? compositionAudioTrack.insertTimeRange(fullRange, of: audioTrack, at: .zero)
        }

        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(
            trackID: compositionVideoTrack.trackID
        )
        layerConfig.setTransform(preferredTransform, at: .zero)

        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        let configuration = AVVideoCompositionInstruction.Configuration(
            layerInstructions: [layerInstruction],
            timeRange: fullRange
        )

        let instruction = AVVideoCompositionInstruction(configuration: configuration)

        // --- Core Animation overlay ---
        let (parentLayer, videoLayer) = buildOverlayLayers(renderSize: renderSize)

        let safeTimescale = CMTimeScale((nominalFrameRate > 0 ? nominalFrameRate : 30).rounded())
        var compositionConfig = AVVideoComposition.Configuration()
        compositionConfig.frameDuration = CMTimeMake(value: 1, timescale: safeTimescale)
        compositionConfig.renderSize = renderSize
        compositionConfig.instructions = [instruction]
        // postProcessingAsVideoLayer: composites CA layers on top of every rendered frame.
        compositionConfig.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        let videoComposition = AVVideoComposition(configuration: compositionConfig)

        return (composition, videoComposition)
    }

    // MARK: - Overlay layer hierarchy

    private func buildOverlayLayers(renderSize: CGSize) -> (parent: CALayer, video: CALayer) {
        let parentLayer = CALayer()
        let videoLayer = CALayer()

        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)

        parentLayer.isGeometryFlipped = true

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(makeTextOverlayLayer(renderSize: renderSize))

        return (parentLayer, videoLayer)
    }

    private func makeTextOverlayLayer(renderSize: CGSize) -> CALayer {
        let overlayWidth: CGFloat = min(renderSize.width * 0.75, 420)
        let overlayHeight: CGFloat = 68
        let bottomPadding: CGFloat = 28

        // With isGeometryFlipped = true on parent: y=0 is visual top, y=height is visual bottom.
        let container = CALayer()
        container.frame = CGRect(
            x: (renderSize.width - overlayWidth) / 2,
            y: renderSize.height - overlayHeight - bottomPadding,
            width: overlayWidth,
            height: overlayHeight
        )
        container.backgroundColor = UIColor.black.withAlphaComponent(0.55).cgColor
        container.cornerRadius = 10

        let scale: CGFloat = 2.0

        // Title
        let titleLayer = CATextLayer()
        titleLayer.string = "Processed in background"
        titleLayer.font = CTFontCreateWithName("Helvetica-Bold" as CFString, 0, nil)
        titleLayer.fontSize = 16
        titleLayer.foregroundColor = UIColor.white.cgColor
        titleLayer.alignmentMode = .center
        titleLayer.contentsScale = scale
        titleLayer.frame = CGRect(x: 8, y: 8, width: overlayWidth - 16, height: 26)

        // Timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let timestampLayer = CATextLayer()
        timestampLayer.string = formatter.string(from: Date())
        timestampLayer.font = CTFontCreateWithName("Helvetica" as CFString, 0, nil)
        timestampLayer.fontSize = 13
        timestampLayer.foregroundColor = UIColor.white.withAlphaComponent(0.85).cgColor
        timestampLayer.alignmentMode = .center
        timestampLayer.contentsScale = scale
        timestampLayer.frame = CGRect(x: 8, y: 38, width: overlayWidth - 16, height: 22)

        container.addSublayer(titleLayer)
        container.addSublayer(timestampLayer)

        return container
    }

    // MARK: - Progress polling

    private func startProgressPolling(session: AVAssetExportSession) {
        DispatchQueue.main.async { [weak self, weak session] in
            self?.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak session] _ in
                guard let self, let session else { return }
                let percent = Int(session.progress * 100)
                self.progressSubject.send(percent)
            }
        }
    }

    private func stopProgressPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
    }

    // MARK: - Save to Photos

    /// Saves the exported video file to the user's Photos library.
    ///
    /// Required Info.plist key:
    ///   NSPhotoLibraryAddUsageDescription (add-only access; does not request read access)
    private func saveToPhotos(url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            NSLog("Photos authorization denied — video will not be saved to Photos")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            NSLog("Video saved to Photos successfully")
        } catch {
            NSLog("Failed to save video to Photos: \(error)")
        }
    }
}
