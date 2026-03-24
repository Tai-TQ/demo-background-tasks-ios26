//
//  ContentView.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 19/3/26.
//

import SwiftUI
import BackgroundTasks

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel = ContentViewModel()
    
    var body: some View {
        NavigationView {
            LazyVStack {
                firstView

                secondView
                
                thirdView
                
                Button("After 10s on main thread") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        viewModel.testProcessingTaskAfter10s()
                    }
                }
                
                Button("Test No Update Process") {
                    viewModel.testProcessingTaskNoUpdateProcess()
                }
            }
            .padding()
            .navigationTitle("Background Tasks")
//            .onAppear {
//                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
//                    NSLog("After 10s on background")
//                    viewModel.testProcessingTaskAfter10s()
//                }
//            }
        }
    }
    
    private var firstView: some View {
        VStack {
            Text("ProcessingTask count 100 seconds")
                .font(.system(size: 18, weight: .semibold))
            HStack {
                Button {
                    handleCountHundredByProcessingTask()
                } label: {
                    Text(viewModel.countPercentState == .running ? "Cancel" : "Start")
                        .foregroundStyle(viewModel.countPercentState == .running ? .red : .blue)
                }

                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: Double(viewModel.countPercentComplete) / 100.0)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(viewModel.countPercentComplete)%")
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 44, height: 44)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var secondView: some View {
        VStack(spacing: 8) {
            Text("Download Video")
                .font(.system(size: 18, weight: .semibold))
            HStack {
                Button {
                    viewModel.handleDownloadVideo()
                } label: {
                    Text(viewModel.downloadState == .downloading ? "Cancel" : "Start")
                        .foregroundStyle(viewModel.downloadState == .downloading ? .red : .blue)
                }

                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: Double(viewModel.downloadProgressPercent) / 100.0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(viewModel.downloadProgressPercent)%")
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 44, height: 44)
            }

            if viewModel.downloadState == .completed {
                Text("Completed!")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            } else if viewModel.downloadState == .failed {
                Text("Download failed. Tap Start to retry.")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var thirdView: some View {
        VStack(spacing: 8) {
            Text("Export Video with Overlay")
                .font(.system(size: 18, weight: .semibold))
            HStack {
                Button {
                    handleExportVideo()
                } label: {
                    Text(viewModel.exportState == .exporting ? "Cancel" : "Start")
                        .foregroundStyle(viewModel.exportState == .exporting ? .red : .blue)
                }

                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: Double(viewModel.exportProgressPercent) / 100.0)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(viewModel.exportProgressPercent)%")
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 44, height: 44)
            }

            if viewModel.exportState == .completed {
                Text("Saved to Photos!")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            } else if viewModel.exportState == .failed {
                Text("Export failed. Tap Start to retry.")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func handleExportVideo() {
        if viewModel.exportState == .exporting {
            viewModel.handleExportVideo() // triggers cancel inside ViewModel
        } else {
            viewModel.handleExportVideo()
        }
    }

    private func handleCountHundredByProcessingTask() {
        if viewModel.countPercentState == .running {
            viewModel.countPercentState = .cancelling
        } else {
            viewModel.handleCountHundredByProcessingTask()
        }
    }
    
}

#Preview {
    ContentView()
}
