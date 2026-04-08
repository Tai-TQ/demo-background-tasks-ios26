//
//  AppDelegate.swift
//  DemoBackgroundTasks
//
//  Created by TaiTQ2 on 8/4/26.
//

import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication,
                     didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        BackgroundTaskWrapper.shared.setup()
        return true
    }
}
