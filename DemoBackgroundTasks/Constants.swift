//
//  Constants.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 20/3/26.
//

import Foundation

enum Constants {
    static let videoFileUrl = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BigBuckBunny.mp4")
}
