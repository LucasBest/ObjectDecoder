//
//  NotificationController.swift
//  ObjectDecoder Watch Extension
//
//  Created by Lucas Best on 6/12/19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import WatchKit
import Foundation
import UserNotifications

import ObjectDecoder

class NotificationController: WKUserNotificationInterfaceController {

    override init() {
        // Initialize variables here.
        super.init()
        
        class User: Decodable {
            var name: String
        }

        let objectDecoder = ObjectDecoder()
        do {
            let user = try objectDecoder.decode(User.self, from: ["name": "Lucas Best"])
            print("From Notification - User name is: " + user.name)
        }
        catch let error {
            print(error)
        }
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
}
