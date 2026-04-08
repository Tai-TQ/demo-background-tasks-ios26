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
        BGTaskManager.shared.setup()
        return true
    }
}
