//
//  BGTaskManager.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 7/4/26.
//

import BackgroundTasks
import UIKit

@objcMembers
public final class BGTaskManager: NSObject {
    public static let shared = BGTaskManager()
    private var runningTaskIds: [String: AnyObject?] = [:]
    private let lock = NSLock()

    // MARK: - App State Tracking

    /// Cached app active state, updated via notifications (always posted on main thread).
    /// Defaults to `true` — the wrapper is typically initialized while the app is active.
    private var _isAppActive: Bool = true
    private let stateLock = NSLock()
    private var isAppActive: Bool {
        get { stateLock.withLock { _isAppActive } }
        set { stateLock.withLock { _isAppActive = newValue } }
    }

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
    }

    @objc private func appDidBecomeActive() { isAppActive = true }
    @objc private func appWillResignActive() { isAppActive = false }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Forces early initialization of the wrapper and begins observing app lifecycle
    /// notifications. Call this in `application(_:didFinishLaunchingWithOptions:)`.
    public func setup() {
        NSLog("Setup BGTaskManager successfully")
    }

    /// Registers and submits a `BGContinuedProcessingTask` to the system, allowing long-running work
    /// to continue after the app moves to the background.
    ///
    /// On iOS 26.0+, this registers a launch handler with `BGTaskScheduler` and submits a
    /// `BGContinuedProcessingTaskRequest`. The system will invoke `launchHandler` when the task
    /// slot becomes available. On earlier OS versions, `launchHandler` is dispatched immediately
    /// on the provided queue (or a background queue) without any system-managed lifecycle.
    ///
    /// - Important: On iOS 26.0+, must be called while the app is in the **foreground** (active state).
    ///   Can be called from any thread. App state is tracked internally via `UIApplication`
    ///   lifecycle notifications to avoid main thread constraints.
    ///
    /// - Parameters:
    ///   - type: A `BackgroundTaskType` value used to compose the task identifier.
    ///   - strategy: The submission strategy for the scheduler. Defaults to `.fail`.
    ///     Use `.queue` to allow the request to wait for an available slot.
    ///   - totalUnitCount: The total number of progress units reported via `updateProgress`.
    ///     Defaults to `100`.
    ///   - title: The localized title displayed in the system Live Activity UI.
    ///   - subtitle: The localized subtitle displayed in the system Live Activity UI.
    ///   - queue: The dispatch queue on which the launch handler is invoked.
    ///     Pass `nil` to use the default background queue.
    ///   - launchHandler: Called when the task begins execution. Receives the unique `taskId`
    ///     string that identifies this task. Use this ID for subsequent `updateProgress`,
    ///     `finish`, and related calls.
    ///   - expirationHandler: Called just before the system forcibly terminates the task.
    ///     Use this to save state and cancel any in-flight work. The task is automatically
    ///     marked complete after this handler returns. Pass `nil` if no cleanup is needed.
    ///
    /// - Warning: Must call `updateProgress(for:completedUnitCount:)` regularly after `launchHandler` is invoked, 
    ///   otherwise the system will forcibly expire the task.
    ///   In debug, the system expires a stalled task after ~5 minutes without a progress update.
    ///
    /// - Returns: A unique `taskId` string scoped to this task instance.
    ///
    /// - Throws:
    ///   - `BGTaskError.appNotInForeground` if the app is not currently active (determined via cached notification state).
    ///   - `BGTaskError.taskAlreadyRunning` if the task ID already exists.
    ///   - `BGTaskError.submissionFailed` wrapping the underlying `BGTaskScheduler` error on iOS 26.0+.
    ///     Common causes include `.notPermitted` (missing Info.plist entry or entitlement),
    ///     `.immediateRunIneligible` (system load too high with strategy `.fail`),
    ///     and `.tooManyPendingTaskRequests`.
    public func execute(type: BackgroundTaskType,
                        strategy: BGTaskSubmissionStrategy = .fail,
//                        requestGPU: Bool = false,
                        totalUnitCount: Int64 = 100,
                        title: String,
                        subtitle: String,
                        using queue: dispatch_queue_t? = nil,
                        launchHandler: @escaping (String) -> Void,
                        expirationHandler: ((String) -> Void)?) throws -> String
    {
        let bundleId = Bundle.main.bundleIdentifier ?? "demo.bgtask"
        let taskId = "\(bundleId).\(type.identifier).\(UUID().uuidString)"
        
        /// Maybe it never happens because of the UUID.
        /// But App will crash if we register the same taskId again, 
        /// so double check here to be safe.
        guard !isTaskExist(taskId: taskId) else {
            NSLog("[BGTask] Task already running: \(taskId)")
            throw BGTaskError.taskAlreadyRunning
        }

        guard #available(iOS 26.0, *) else {
            NSLog("[BGTask] iOS < 26, running launchHandler directly for taskId: \(taskId)")
            registerTask(taskId: taskId)
            let queue = queue ?? DispatchQueue.global(qos: .background)
            queue.async {
                launchHandler(taskId)
            }
            return taskId
        }
        guard isAppActive else {
            throw BGTaskError.appNotInForeground
        }
        registerTask(taskId: taskId)

        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskId,
            using: queue,
            launchHandler: { [weak self] task in
                guard let self,
                      let task = task as? BGContinuedProcessingTask else { return }
                self.assignTask(task, for: taskId)
                task.expirationHandler = { [weak self, weak task] in
                    NSLog("[BGTask] Task expired: \(taskId)")
                    expirationHandler?(taskId)
                    guard self?.isTaskExist(taskId: taskId) == true else { return }
                    task?.setTaskCompleted(success: false)
                    self?.removeTask(taskId: taskId)
                }
                task.progress.totalUnitCount = totalUnitCount
                task.progress.completedUnitCount = 0
                task.updateTitle(title, subtitle: subtitle)

                launchHandler(taskId)
            }
        )
        guard registered else {
            NSLog("[BGTask] WARNING: Failed to register taskId: \(taskId). Check BGTaskSchedulerPermittedIdentifiers.")
            removeTask(taskId: taskId)
            throw BGTaskError.submissionFailed
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: taskId,
            title: title,
            subtitle: subtitle
        )
        request.strategy = strategy.toSubmissionStrategy()

        /// Currently not support, gpu only available on iPad M3 or newer, not available on iPhone.
//        if BGTaskScheduler.supportedResources.contains(.gpu) {
//            request.requiredResources = .gpu
//        }

        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[BGTask] Submitted successfully: \(taskId)")
            return taskId
        } catch {
            NSLog("[BGTask] Failed to submit taskId: \(taskId), error: \(error)")
            removeTask(taskId: taskId)
            throw NSError.bgTaskError(
                .submissionFailed,
                underlying: error
            )
        }
    }

    /// Returns whether a task identified by `taskId` is actively running.
    ///
    /// On iOS 26.0+, a task is considered running only after the system has invoked its launch
    /// handler and the `BGContinuedProcessingTask` object has been assigned internally.
    /// A submitted-but-not-yet-launched (pending) task returns `false`.
    ///
    /// On iOS versions earlier than 26.0, returns `true` for any taskId that was successfully
    /// returned by `execute()` and has not yet been passed to `finish()`.
    ///
    /// - Parameter taskId: The task identifier returned by `execute()`.
    /// - Returns: `true` if the task is currently executing; `false` if it is pending,
    ///   finished, or unknown.
    public func isTaskRunning(taskId: String) -> Bool {
        guard #available(iOS 26.0, *) else {
            return isTaskExist(taskId: taskId)
        }
        return getTask(taskId: taskId) != nil
    }

    /// Updates the progress and optionally the displayed title/subtitle of a running task.
    ///
    /// Progress is reflected in the system Live Activity UI associated with the task.
    /// This method only operates on tasks that are actively running (i.e., their launch handler
    /// has been invoked). Calling this while the task is still pending will throw `.taskStillPending`.
    ///
    ///
    /// - Parameters:
    ///   - taskId: The task identifier returned by `execute()`.
    ///   - completedUnitCount: The number of completed progress units out of the `totalUnitCount`
    ///     specified in `execute()`. Value should be in the range `0...totalUnitCount`.
    ///   - title: Updated title to display in the system UI. Pass `nil` to keep the current title.
    ///   - subtitle: Updated subtitle to display in the system UI. Pass `nil` to keep the current subtitle.
    ///
    /// - Throws:
    ///   - `BGTaskError.notFoundTask` if `taskId` is not registered (e.g., already finished or never started).
    ///   - `BGTaskError.taskStillPending` if the task has been submitted but the launch handler
    ///     has not yet been called by the system.
    public func updateProgress(for taskId: String,
                               completedUnitCount: Int64,
                               title: String? = nil,
                               subtitle: String? = nil) throws
    {
        guard #available(iOS 26.0, *) else {
            return
        }

        guard isTaskExist(taskId: taskId) else {
            throw BGTaskError.notFoundTask
        }

        guard let task = getTask(taskId: taskId) else {
            throw BGTaskError.taskStillPending
        }

        task.progress.completedUnitCount = completedUnitCount

        if title != nil || subtitle != nil {
            let title = title ?? task.title
            let subtitle = subtitle ?? task.subtitle
            task.updateTitle(title, subtitle: subtitle)
        }
    }

    /// Marks a task as successfully completed and removes it from internal tracking.
    ///
    /// - If the task is actively running (launch handler was called), calls
    ///   `setTaskCompleted(success: true)` to dismiss the Live Activity UI and
    ///   signal success to the system.
    /// - If the task is still pending (submitted but not yet launched), cancels the
    ///   pending request via `BGTaskScheduler`.
    /// - If `taskId` is not tracked, the call is a no-op.
    ///
    /// - Note: On iOS < 26.0, only removes the task from internal tracking.
    ///   Caller proactive stop flow in launchHandler callback
    ///   The dispatched work cannot be cancelled once started.
    ///
    /// - Parameter taskId: The task identifier returned by `execute()`.
    public func finish(taskId: String) {
        guard #available(iOS 26.0, *) else {
            removeTask(taskId: taskId)
            NSLog("[BGTask] Finished taskId: \(taskId)")
            return
        }

        guard isTaskExist(taskId: taskId) else {
            NSLog("[BGTask] No need to finish, taskId: \(taskId)")
            return
        }

        // pending task
        guard let task = getTask(taskId: taskId) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
            removeTask(taskId: taskId)
            return
        }

        // running task
        task.setTaskCompleted(success: true)
        removeTask(taskId: taskId)
        NSLog("[BGTask] Finished taskId: \(taskId)")
    }

    /// Cancels all tasks that have been submitted but not yet launched by the system.
    ///
    /// Pending tasks are those for which `execute()` returned successfully but whose
    /// launch handler has not yet been called. This method cancels their `BGContinuedProcessingTaskRequest`
    /// via `BGTaskScheduler` and removes them from internal tracking.
    ///
    /// Already-running tasks are not affected. Use `cancelAllTasks()` to cancel both
    /// pending and running tasks.
    ///
    /// - Note: On iOS < 26.0, all tasks are launched immediately and cannot be pending,
    ///   so this method is a no-op on those versions.
    public func cancelAllPendingTasks() {
        guard #available(iOS 26.0, *) else { return }
        let snapshot = snapshotRunningTaskIds()
        for (id, task) in snapshot {
            if task == nil {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
            }
        }
        removeAllPendingTask()
    }

    /// Cancels all tracked tasks, both pending and actively running.
    ///
    /// - For running tasks, calls `setTaskCompleted(success: true)` to signal the system
    ///   and dismiss the Live Activity UI.
    /// - For pending tasks, cancels the `BGContinuedProcessingTaskRequest` via `BGTaskScheduler`.
    /// - All tasks are removed from internal tracking.
    ///
    /// - Note: On iOS < 26.0, only clears internal tracking. Any dispatched work
    ///   that is already executing on a queue cannot be cancelled.
    public func cancelAllTasks() {
        if #available(iOS 26.0, *) {
            let snapshot = snapshotRunningTaskIds()
            for (id, task) in snapshot {
                if let task = task as? BGContinuedProcessingTask {
                    task.setTaskCompleted(success: true)
                } else {
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
                }
            }
        }
        removeAllTask()
    }

    /// Queries the system for pending task requests that were submitted by this wrapper.
    ///
    /// Filters `BGTaskScheduler.getPendingTaskRequests()` to only return requests whose
    /// identifiers are currently tracked by this wrapper instance. This excludes requests
    /// submitted by other parts of the app or previous app sessions.
    ///
    /// The completion handler is called asynchronously on an unspecified queue.
    ///
    /// - Note: On iOS < 26.0, the completion handler is called immediately with an empty array.
    ///
    /// - Parameter completionHandler: Called with the array of matching pending `BGTaskRequest` objects.
    ///   The array will be empty if no tracked tasks are pending.
    public func getPendingTaskRequests(completionHandler: @escaping @Sendable ([BGTaskRequest]) -> Void) {
        guard #available(iOS 26.0, *) else {
            completionHandler([])
            return
        }
        BGTaskScheduler.shared.getPendingTaskRequests { [weak self] taskRequests in
            guard let self else { return }
            completionHandler(taskRequests.filter { [weak self] task in
                guard let self else { return false }
                let snapshot = snapshotRunningTaskIds()
                return snapshot.keys.contains(task.identifier)
            })
        }
    }
}

// MARK: - runningTaskIds Helpers

extension BGTaskManager {
    private func registerTask(taskId: String) {
        lock.withLock { runningTaskIds[taskId] = nil }
        NSLog("[RunningTaskIds] Registered taskId: \(taskId)")
    }

    @available(iOS 26.0, *)
    private func assignTask(_ task: BGContinuedProcessingTask, for taskId: String) {
        lock.withLock { runningTaskIds[taskId] = task }
        NSLog("[RunningTaskIds] Assigned task object for taskId: \(taskId)")
    }

    private func removeTask(taskId: String) {
        lock.withLock { _ = runningTaskIds.removeValue(forKey: taskId) }
        NSLog("[RunningTaskIds] Removed taskId: \(taskId)")
    }

    private func removeAllPendingTask() {
        lock.withLock { runningTaskIds = runningTaskIds.filter { $0.value != nil } }
        NSLog("[RunningTaskIds] Removed all pending tasks")
    }

    private func removeAllTask() {
        lock.withLock { runningTaskIds.removeAll() }
        NSLog("[RunningTaskIds] Removed all tasks")
    }

    private func isTaskExist(taskId: String) -> Bool {
        lock.withLock { runningTaskIds.keys.contains(taskId) }
    }

    @available(iOS 26.0, *)
    private func getTask(taskId: String) -> BGContinuedProcessingTask? {
        lock.withLock { (runningTaskIds[taskId] ?? nil) as? BGContinuedProcessingTask }
    }

    @available(iOS 26.0, *)
    private func snapshotRunningTaskIds() -> [String: AnyObject?] {
        lock.withLock { runningTaskIds }
    }
}
