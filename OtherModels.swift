//
//  OtherModels.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/8/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import Foundation
import UIKit
import CloudKit
import MapKit
import Cluster
import Disk

class CloudProfilePictures {
    var name: String?
    var age: String?
    var firebaseID: String?
    var pictureAssets: [CKAsset] = []
    var changedPhoto: [Bool] = []
}

class ProfilePic: Codable {
    var hasPhoto: Bool!
    var s3Key: String!
    var imageData: Data?
}

class MyPointAnnotation: MKPointAnnotation {
    var imageName: String!
}

class PeopleAnnotation: Annotation {
    var firebaseID: String!
    var name: String!
    var age: String!
    var buy: Bool!
    var receive: Bool!
}
