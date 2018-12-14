//
//  MyPhotosVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/8/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit
import MobileCoreServices
import Disk
import Photos
import CloudKit
import Firebase
import SwiftMessages
import AWSS3

protocol MyPhotosVCDelegate: class {
    func changedPhotos(newPhotos: [UIImage], newChangedPhoto: [Bool])
}

class MyPhotosVC: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UIGestureRecognizerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate {
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var doneOutlet: UIBarButtonItem!
    
    var myPhotos: [ProfilePic]!
    var selectedIndexPath: IndexPath!
    
    var rearrangedPhotos = false
    
    var delegate: MyPhotosVCDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationItem.setHidesBackButton(true, animated: true)
        
        let navigationTitleFont = UIFont(name: "AvenirNext-Bold", size: 18)!
        doneOutlet.setTitleTextAttributes([NSAttributedStringKey.font: navigationTitleFont, NSAttributedStringKey.foregroundColor: UIColor.white], for: .normal)
        
        setupCollectionView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        checkPermission()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        updateFirebaseProfilePic()
        if rearrangedPhotos {
            for (i, pic) in myPhotos.enumerated() {
                if pic.hasPhoto {
                    let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! as String
                    let localPath = (documentDirectory as NSString).appendingPathComponent("image\(i)")
                    do {
                        try pic.imageData!.write(to: URL(fileURLWithPath: localPath), options: .atomic)
                    }
                    catch { print(error) }
                    let imageURL = URL(fileURLWithPath: localPath)
                    self.uploadToS3(imageURL: imageURL, index: i)
                }
                else {
                    deleteFromS3(tag: i)
                }
            }
        }
    }
    
    func updateFirebaseProfilePic() {
        let userID = Auth.auth().currentUser!.uid
        
        for (index, pic) in myPhotos.enumerated() {
            if pic.hasPhoto {
                let image = self.myPhotos[index].imageData?.getImage()
                
                let imageData = UIImageJPEGRepresentation(image!, 0.2)
                
                let storageRef = Storage.storage().reference().child("usersProfilePics").child(userID)
                storageRef.putData(imageData!, metadata: nil, completion: { (metadata, err) in
                    if err == nil {
                        storageRef.downloadURL(completion: { url, error in
                            if let path = url?.absoluteString {
                                let value = ["profilePicLink": path]
                                Database.database().reference().child("users").child(userID).child("credentials").updateChildValues(value, withCompletionBlock: { (errr, _) in
                                    if errr == nil {
                                        print("updated profile pic")
                                    }
                                })
                            }
                        })
                        
                    }
                })
                break
            }
        }
    }
    
    func uploadToS3(imageURL: URL, index: Int) {
        // Configure AWS Cognito Credentials
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USEast1, identityPoolId:"us-east-1:b00b05b6-8a73-44ed-be9f-5a727fa9160e")
        let configuration = AWSServiceConfiguration(region:.USEast1, credentialsProvider:credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        // Set up AWS Transfer Manager Request
        let S3BucketName = "overdrinks"
        let uploadRequest = AWSS3TransferManagerUploadRequest()
        uploadRequest?.body = imageURL
        uploadRequest?.key = Auth.auth().currentUser!.uid + "-\(index)"
        uploadRequest?.bucket = S3BucketName
        uploadRequest?.contentType = "image/jpeg"
        uploadRequest?.uploadProgress = { (bytesSent, totalBytesSent, totalBytesExpectedtoSend) -> Void in
            let progressRatio = Float(totalBytesSent) / Float(totalBytesExpectedtoSend)
            DispatchQueue.main.async {
                if progressRatio >= 1 {
                    
                }
            }
        }
        
        let transferManager = AWSS3TransferManager.default()
        
        // Perform file upload
        transferManager.upload(uploadRequest!).continueWith(block: { (task: AWSTask) -> Any? in
            
            if let error = task.error {
                print("Upload failed with error: (\(error.localizedDescription))")
            }
            
            if task.result != nil {
                let s3URL = URL(string: "https://s3.amazonaws.com/\(S3BucketName)/\(uploadRequest!.key!)")!
                print("Uploaded to:\n\(s3URL)")
                
                
            }
            else {
                print("Unexpected empty result.")
            }
            return nil
        })
    }
    
    func deleteFromS3(tag: Int) {
        // Configure AWS Cognito Credentials
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USEast1, identityPoolId:"us-east-1:b00b05b6-8a73-44ed-be9f-5a727fa9160e")
        let configuration = AWSServiceConfiguration(region:.USEast1, credentialsProvider:credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        let s3Service = AWSS3.default()
        let deleteObjectRequest = AWSS3DeleteObjectRequest()
        deleteObjectRequest?.bucket = "overdrinks" // bucket name
        deleteObjectRequest?.key = Auth.auth().currentUser!.uid + "-\(tag)" // File name
        s3Service.deleteObject(deleteObjectRequest!).continueWith { (task:AWSTask) -> AnyObject? in
            if let error = task.error {
                print("Error occurred: \(error)")
                return nil
            }
            print("Bucket deleted successfully.")
            return nil
        }
    }
    
  
    func checkPermission() {
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
        switch photoAuthorizationStatus {
        case .authorized: print("Access is granted by user")
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ (newStatus) in
                print("status is \(newStatus)")
                if newStatus == PHAuthorizationStatus.authorized {
                    print("success") }
            })
            case .restricted: print("User do not have access to photo album.")
            case .denied: print("User has denied the permission.")
            }
        }
    
    func setupCollectionView() {
        let cellWidth = view.frame.width * 0.4
        let cellSize = CGSize(width: cellWidth , height: cellWidth) // make square
        
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = cellSize
        layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        layout.minimumLineSpacing = 30
        layout.minimumInteritemSpacing = 0
        
        collectionView.setCollectionViewLayout(layout, animated: true)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.longPressGesture))
        longPress.delegate = self
        longPress.minimumPressDuration = 0.4
        collectionView.addGestureRecognizer(longPress)
        
        collectionView.perform(#selector(collectionView.reloadData), with: nil, afterDelay: 0.2)
    }
    
    @IBAction func donePressed(_ sender: UIBarButtonItem) {
        sender.isEnabled = false
        let _ = self.navigationController?.popViewController(animated: true)
    }
    
    // OBJC gestures
    @objc func longPressGesture(gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let selectedIndexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else { break }
            collectionView.beginInteractiveMovementForItem(at: selectedIndexPath)
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: gesture.view!))
        case .ended:
            collectionView.endInteractiveMovement()
        default:
            collectionView.cancelInteractiveMovement()
        }
    }
    
    @objc func deletePic(_ sender: AnyObject) {
        let myAlert = UIAlertController(title: "Options", message: nil, preferredStyle: .actionSheet)
        let deleteAction = UIAlertAction(title: "Delete", style: .default) { (ACTION) in
            let defaultPic = UIImage(named: "profile pic")!
            self.myPhotos[sender.view.tag].imageData = defaultPic.getData(quality: 1)
            try? Disk.save(self.myPhotos, to: .documents, as: "myPhotos.json")
            self.deleteFromS3(tag: sender.view.tag)
            self.collectionView.reloadData()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        myAlert.addAction(deleteAction)
        myAlert.addAction(cancelAction)
        
        self.present(myAlert, animated: true, completion: nil)
    }
    
    // MARK: start collectionview setup
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return myPhotos.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell1", for: indexPath) as! ProfileCell
        cell.backgroundColor = UIColor.clear
        
        let image = myPhotos[indexPath.row].imageData?.getImage()
        cell.profilePic.image = image
        cell.profilePic.layer.cornerRadius = cell.profilePic.frame.height/2
        cell.profilePic.layer.borderWidth = 3
        cell.profilePic.layer.borderColor = GlobalVariables.purple.cgColor
        
        cell.deleteIcon.isHidden = myPhotos[indexPath.row].hasPhoto ? false : true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.deletePic))
        cell.deleteIcon.tag = indexPath.row
        cell.deleteIcon.addGestureRecognizer(tapGesture)
        
        return cell
    }
   
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedIndexPath = indexPath
        
        let myAlert = UIAlertController(title: "Media Options", message: nil, preferredStyle: .actionSheet)
        
        let libraryAction = UIAlertAction(title: "Photo Library", style: .default) { _ in
            self.openLibrary()
        }
        
        let takePhotoAction = UIAlertAction(title: "Camera", style: .default) { _ in
            self.takePhoto()
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        myAlert.addAction(libraryAction)
        myAlert.addAction(takePhotoAction)
        myAlert.addAction(cancelAction)
        
        self.present(myAlert, animated: true, completion: nil)
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let profilePic = myPhotos[sourceIndexPath.row]
        myPhotos.remove(at: sourceIndexPath.row)
        myPhotos.insert(profilePic, at: destinationIndexPath.row)
        
        rearrangedPhotos = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? Disk.save(self.myPhotos, to: .documents, as: "myPhotos.json")
            DispatchQueue.main.async {
                self.collectionView.perform(#selector(self.collectionView.reloadData), with: nil, afterDelay: 0.05)
            }
        }
    }
}

extension MyPhotosVC {
    func openLibrary() {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let imagePicker = UIImagePickerController()
            imagePicker.navigationBar.titleTextAttributes = [NSAttributedStringKey.foregroundColor : UIColor.white]
            imagePicker.navigationBar.tintColor = .white
            imagePicker.delegate = self
            imagePicker.sourceType = .photoLibrary
            imagePicker.allowsEditing = false
            self.present(imagePicker, animated: true, completion: nil)
        }
    }
    
    func takePhoto() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.navigationBar.titleTextAttributes = [NSAttributedStringKey.foregroundColor : UIColor.white]
            imagePicker.navigationBar.tintColor = .white
            imagePicker.delegate = self
            imagePicker.sourceType = .camera
            imagePicker.allowsEditing = false
            self.present(imagePicker, animated: true, completion: nil)
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let pickedImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
            self.myPhotos[self.selectedIndexPath.row].imageData = pickedImage.getData(quality: 0.1)
            self.myPhotos[self.selectedIndexPath.row].hasPhoto = true
            self.collectionView.reloadData()
            
            //details of image
            let uploadFileURL = info[UIImagePickerControllerReferenceURL] as! NSURL
            let imageName = uploadFileURL.lastPathComponent
            let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! as String
            // getting local path
            let localPath = (documentDirectory as NSString).appendingPathComponent(imageName!)
            //get actual image
            let data = UIImageJPEGRepresentation(pickedImage, 0.1)
            do {
                try data!.write(to: URL(fileURLWithPath: localPath), options: .atomic)
            }
            catch { print(error) }
            let imageURL = URL(fileURLWithPath: localPath)
            self.uploadToS3(imageURL: imageURL, index: selectedIndexPath.row)
            
            self.dismiss(animated: true, completion: {
                try? Disk.save(self.myPhotos, to: .documents, as: "myPhotos.json")
            })
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
}

class ProfileCell: UICollectionViewCell {
    @IBOutlet weak var profilePic: UIImageView!
    @IBOutlet weak var deleteIcon: UIImageView!
    @IBOutlet weak var captionIcon: UIImageView!
}
