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
            List {
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
                .listRowSeparator(.hidden)

                Button("Button 2") {
                    print("Button 2")
                }
                Button("Button 3") {
                    print("Button 3")
                }
                Button("Button 4") {
                    print("Button 4")
                }
                Button("Button 5") {
                    print("Button 5")
                }
                Button("Button 6") {
                    print("Button 6")
                }
                Button("Button 7") {
                    print("Button 7")
                }
                Button("Button 8") {
                    print("Button 8")
                }
                Button("Button 9") {
                    print("Button 9")
                }
                Button("Button 10") {
                    print("Button 10")
                }
            }
            .listStyle(.plain)
            .listRowSpacing(20)
            .navigationTitle("Background Tasks")
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
