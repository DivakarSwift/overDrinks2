//
//  OtherModels.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/8/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import Foundation
import UIKit
import MapKit
import Cluster


class ProfilePic: Codable {
    var hasPhoto: Bool!
    var s3Key: String!
    var imageData: Data?
}

class PeopleAnnotation: Annotation {
    var firebaseID: String!
    var name: String!
    var age: String!
    var buy: Bool!
    var receive: Bool!
    var duration: Double!
    var superlike: Bool = false
    var deviceToken: String!
    var blurb: String?
    var profilePic: UIImage?
}


class startClock {
    var startTime: CFAbsoluteTime!
    var endTime: CFAbsoluteTime!
    func start() {
        startTime = CFAbsoluteTimeGetCurrent()
    }
    func stop() {
        endTime = CFAbsoluteTimeGetCurrent()
        print(endTime - startTime)
    }
}
