# DemoBackgroundTasks

A demo iOS application showcasing how to use **BGContinuedProcessingTask** from Apple's `BackgroundTasks` framework to execute long-running tasks in the background.

## Overview

This project demonstrates the end-to-end lifecycle of a `BGContinuedProcessingTask`:

- Dynamically registering and submitting a `BGContinuedProcessingTask` at runtime using a unique identifier per session.
- Tracking task progress via `task.progress` and reflecting it live in the SwiftUI UI as a circular progress indicator.
- Handling task lifecycle events including expiration (`expirationHandler`) and user-initiated cancellation.
- Updating the system UI (Lock Screen / Dynamic Island) with `task.updateTitle(_:subtitle:)` while the task runs in the background.
- Reporting task completion or failure to the system via `task.setTaskCompleted(success:)`.
