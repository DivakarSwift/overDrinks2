//
//  CustomTabmanVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/9/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit
import CloudKit
import NVActivityIndicatorView
import SwipeMenuViewController
import Firebase
import Alamofire
import PopupDialog
import AWSS3

class CustomTabVC: UIViewController, NVActivityIndicatorViewable, UIPopoverPresentationControllerDelegate {
    
    @IBOutlet weak var doneOutlet: UIBarButtonItem!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var swipeMenuView: SwipeMenuView!
    @IBOutlet weak var dislikeView: UIView!
    @IBOutlet weak var dislikeOutlet: UIButton!
    @IBOutlet weak var superlikeView: UIView!
    @IBOutlet weak var superLikeOutlet: UIButton!
    @IBOutlet weak var likeView: UIView!
    @IBOutlet weak var likeOutlet: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var blurbLabel: UILabel!
    
    var viewControllers: [UIViewController]! = []
    
    var firebaseIDs: [String]!
    var index: Int!
    var currentFCM: String!
    var selectedUser: User?
    var operation: CKQueryOperation!
    var ages: [String]!
    var likedIDs: [String] = []
    
    var flagButton: UIBarButtonItem!
    var infoBarButtonItem: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        doneOutlet.tintColor = .white
        
        flagButton = UIBarButtonItem(image: UIImage(named: "flagIcon")!, style: .plain, target: self, action: #selector(self.showOptions))
        flagButton.tintColor = .white
        
        let infoButton = UIButton(type: .infoLight)
        infoButton.addTarget(self, action: #selector(self.showLegend), for: .touchUpInside)
        infoButton.tintColor = .white
        infoBarButtonItem = UIBarButtonItem(customView: infoButton)
        navigationItem.rightBarButtonItems = [infoBarButtonItem, flagButton]
        
        superlikeView.isHidden = true
        dislikeView.isHidden = true
        likeView.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        getUsedIDs(completion: {
            self.likedIDs = [] // *** COMMENT OUT BEFORE PUBLISHING
            self.loadVCs()
            self.loadButtons()
            self.loadSwipeMenu()
        })
        
    }
    
    @IBAction func messagePressed(_ sender: UIBarButtonItem) {
        self.performSegue(withIdentifier: "toChat", sender: self)
    }
    
    func loadVCs() {
        let timer = startClock()
        timer.start()
        
        if self.firebaseIDs.count == 0 {
            self.performSegue(withIdentifier: "unwindToSearch", sender: self)
        }
        else {
            activityIndicator.startAnimating()
            self.title = nil
            viewControllers = []
            swipeMenuView.reloadData()
            self.blurbLabel.text = nil
            
            User.info(forUserID: self.firebaseIDs[self.index], completion: { user in
                self.selectedUser = user
                DispatchQueue.main.async {
                    self.title = "\(user.name), \(self.ages[self.index].split(separator: " ").first!)"
                    self.currentFCM = user.FCMToken
                    if self.selectedUser?.id != Auth.auth().currentUser!.uid {
                        self.superlikeView.isHidden = false
                        self.dislikeView.isHidden = false
                        self.likeView.isHidden = false
                        if !defaults.bool(forKey: "firstPerson") {
                            self.showLegend()
                            defaults.set(true, forKey: "firstPerson")
                        }
                    }
                    if self.likedIDs.contains(self.selectedUser!.id) {
                        self.superlikeView.isHidden = true
                        self.dislikeView.isHidden = true
                        self.likeView.isHidden = true
                    }
                }
            })
            
            queryS3()
        }
    }
    
    func getUsedIDs(completion: @escaping () -> Void) { // IDs that have already been liked/disliked
        likedIDs = []
        Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).observeSingleEvent(of: .value, with: { snapshot in
            if snapshot.exists() {
                for snap in snapshot.children {
                    let child = snap as! DataSnapshot
                    if child.key != "credentials" && child.key != "conversations" && child.key != "reference" && child.key != "blockList" {
                        let data = child.value as! [String: Any]
                        let dataAge = Date().timeIntervalSince1970 - (data["timeStamp"] as! Double)
                        if dataAge > 18 * 60 * 60 {
                            Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child(child.key).removeValue()
                        }
                        else {
                            self.likedIDs.append(child.key)
                        }
                    }
                }
                completion()
            }
            else {
                completion()
            }
        })
    }
    
    func queryS3() {
        let timer = startClock()
        timer.start()
        
        // Update Blurb
        Database.database().reference().child("users").child(self.firebaseIDs[self.index]).child("credentials").observeSingleEvent(of: .value, with: { snapshot in
            if snapshot.exists() {
                let data = snapshot.value as! [String: Any]
                if let blurb = data["blurb"] as? String {
                    DispatchQueue.main.async {
                        self.blurbLabel.text = blurb == "" ? nil : "\"\(blurb)\""
                    }
                }
                else {
                    self.blurbLabel.text = nil
                }
            }
            else {
                self.blurbLabel.text = nil
            }
            timer.stop()
        })
        
        // Configure AWS Cognito Credentials
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType:.USEast1, identityPoolId:"us-east-1:b00b05b6-8a73-44ed-be9f-5a727fa9160e")
        let configuration = AWSServiceConfiguration(region:.USEast1, credentialsProvider:credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        // Set up AWS Transfer Manager Request
        for i in 0...5 { // go through all photos
            let imageName = "image\(i).jpg"
            let downloadedFilePath = NSTemporaryDirectory().appendingFormat("downloaded-\(imageName)")
            let downloadedFileURL = URL(fileURLWithPath: downloadedFilePath)
            let S3BucketName = "overdrinks"
            let downloadRequest = AWSS3TransferManagerDownloadRequest()
            downloadRequest?.key = "\(firebaseIDs[index])-\(i)"
            downloadRequest?.bucket = S3BucketName
            downloadRequest?.downloadingFileURL = downloadedFileURL
            downloadRequest?.downloadProgress = { (bytesWritten, totalBytesWritten, totalBytesExpectedtoWrite) -> Void in
                let progressRatio = Float(bytesWritten) / Float(totalBytesWritten)
                //print(progressRatio)
                DispatchQueue.main.async {
                    if progressRatio >= 1 {
                        
                    }
                }
            }
            
            let transferManager = AWSS3TransferManager.default()
            transferManager.download(downloadRequest!).continueWith(block: { (task) -> Any? in
                if let error = task.error {
                    print("downloadFile() failed: (\(error))")
                }
                    
                else if task.result != nil {
                    if let data = try? Data(contentsOf: downloadedFileURL) {
                        let vc = self.storyboard?.instantiateViewController(withIdentifier: "PicturesVC") as! PicturesVC
                        vc.picture = data.getImage()
                        vc.caption = "this will be removed"
                        self.viewControllers.append(vc)
                        DispatchQueue.main.async {
                            self.activityIndicator.stopAnimating()
                            self.swipeMenuView.reloadData()
                        }
                    }
                }
                else {
                    print("Unexpected empty result")
                }
                timer.stop()
                return nil
            })
        }
    }
    
    @objc func showLegend() {
        let popoverContent = self.storyboard?.instantiateViewController(withIdentifier: "LikeLegendVC") as! LikeLegendVC
        let nav = UINavigationController(rootViewController: popoverContent)
        nav.modalPresentationStyle = .popover
        let popover = nav.popoverPresentationController
        
        popover?.barButtonItem = self.navigationItem.rightBarButtonItem
        popover?.permittedArrowDirections = [.down, .up]
        popover?.delegate = self
        self.present(nav, animated: true, completion: nil)
    }
    
    func loadButtons() {
        dislikeOutlet.layer.cornerRadius = dislikeView.frame.height/2
        dislikeView.layer.cornerRadius = dislikeView.frame.height/2
        dislikeView.layer.masksToBounds = false
        dislikeView.layer.shadowOpacity = 0.3
        dislikeView.layer.shadowRadius = 1
        dislikeView.layer.shadowOffset = CGSize(width: 2, height: 3)
        dislikeView.layer.shadowColor = UIColor.black.cgColor
        
        superLikeOutlet.layer.cornerRadius = superLikeOutlet.frame.height/2
        superlikeView.layer.cornerRadius = superLikeOutlet.frame.height/2
        superlikeView.layer.masksToBounds = false
        superlikeView.layer.shadowOpacity = 0.3
        superlikeView.layer.shadowRadius = 1
        superlikeView.layer.shadowOffset = CGSize(width: 2, height: 3)
        superlikeView.layer.shadowColor = UIColor.black.cgColor
        
        likeOutlet.layer.cornerRadius = likeView.frame.height/2
        likeView.layer.cornerRadius = likeView.frame.height/2
        likeView.layer.masksToBounds = false
        likeView.layer.shadowOpacity = 0.3
        likeView.layer.shadowRadius = 1
        likeView.layer.shadowOffset = CGSize(width: 2, height: 3)
        likeView.layer.shadowColor = UIColor.black.cgColor
    }
    
    func loadSwipeMenu() {
        contentView.layer.cornerRadius = 10
        contentView.layer.masksToBounds = false
        contentView.layer.shadowOpacity = 0.5
        contentView.layer.shadowRadius = 5
        contentView.layer.shadowOffset = CGSize(width: 0, height: 0)
        contentView.layer.shadowColor = UIColor.black.cgColor
        
        swipeMenuView.layer.cornerRadius = 10
        swipeMenuView.dataSource = self
        swipeMenuView.delegate = self
        var options = SwipeMenuViewOptions()
        options.tabView.style = .segmented
        options.tabView.additionView.backgroundColor = UIColor(red: 156/255, green: 119/255, blue: 255/255, alpha: 1)
        swipeMenuView.reloadData(options: options)
    }
    
    @objc func blockUser() {
        let title = "Block this user?"
        let message = "Blocking prevents this user from contacting you and being able to see your location. This action is permanent."
        
        let popup = PopupDialog(title: title, message: message)
        
        // Create buttons
        let blockButton = DefaultButton(title: "BLOCK USER") {
            User.blockUser(blockedUser: self.selectedUser!, completion: {
                self.getNextPerson()
                if self.firebaseIDs.count == 0 {
                    self.performSegue(withIdentifier: "unwindToSearch", sender: self)
                }
            })
        }
        
        let cancelButton = CancelButton(title: "CANCEL") {
        }
        
        popup.addButtons([blockButton, cancelButton])
        self.present(popup, animated: true, completion: nil)
    }
    
    @objc func showOptions() {
        let title = "Options"
        
        let popup = PopupDialog(title: title, message: nil)
        
        // Create buttons
        let flagButton = DefaultButton(title: "FLAG USER") {
            self.flagUser()
        }
        
        let blockButton = DefaultButton(title: "BLOCK USER") {
            self.blockUser()
        }
        
        let cancelButton = CancelButton(title: "CANCEL") {
        }
        
        popup.addButtons([flagButton, blockButton, cancelButton])
        self.present(popup, animated: true, completion: nil)
    }
    
    @objc func flagUser() {
        let title = "Flag this user?"
        let message = "Flagging this user will also block this user. Therefore, flag this user if you feel the content is inappropriate or if the user is abusive."
        
        let popup = PopupDialog(title: title, message: message)
        
        // Create buttons
        let flagButton = DefaultButton(title: "FLAG USER") {
            Database.database().reference().child("flags").child(self.selectedUser!.id).observeSingleEvent(of: .value, with: { snapshot in
                if snapshot.exists() {
                    let data = snapshot.value as! [String: Int]
                    let flags = data["flags"]
                    let newValue = ["flags": flags! + 1]
                    Database.database().reference().child("flags").child(self.selectedUser!.id).updateChildValues(newValue, withCompletionBlock: { err, reference in
                        self.getNextPerson()
                        if self.firebaseIDs.count == 0 {
                            self.performSegue(withIdentifier: "unwindToSearch", sender: self)
                        }
                        User.blockUser(blockedUser: self.selectedUser!, completion: {
                        })
                    })
                }
                else {
                    let value = ["flags": 1]
                    Database.database().reference().child("flags").child(self.selectedUser!.id).updateChildValues(value, withCompletionBlock: { err, reference in
                        self.getNextPerson()
                        if self.firebaseIDs.count == 0 {
                            self.performSegue(withIdentifier: "unwindToSearch", sender: self)
                        }
                        User.blockUser(blockedUser: self.selectedUser!, completion: {
                        })
                    })
                }
            })
        }
        
        let cancelButton = CancelButton(title: "CANCEL") {
        }
        
        popup.addButtons([flagButton, cancelButton])
        self.present(popup, animated: true, completion: nil)
    }
    
    func createMatchPopup(image: UIImage?) {
        self.createConvo(currentUserID: Auth.auth().currentUser!.uid, toID: self.firebaseIDs[self.index])
        
        var headers: HTTPHeaders = HTTPHeaders()
        
        headers = ["Content-Type": "application/json", "Authorization":"key=\(AppDelegate.SERVERKEY)"]
        
        let notification = ["to": self.currentFCM,
                            "notification": ["body": "You've got a match!",
                                             "title": "",
                                             "badge": 1,
                                             "sound": "default"]] as [String:Any]
        
        Alamofire.request(AppDelegate.NOTIFICATION_URL as URLConvertible, method: .post as HTTPMethod, parameters: notification, encoding: JSONEncoding.default, headers: headers).responseJSON { (response) in
            print(response)
        }
        
        let title = "Time for drinks!"
        let message = "Move fast! This match only lasts for 18 hours."
        
        let popup = PopupDialog(title: title, message: message, image: image)
        
        // Create buttons
        let msgButton = DefaultButton(title: "MESSAGE") {
            self.performSegue(withIdentifier: "toChat", sender: self)
        }
        
        let searchButton = DefaultButton(title: "CONTINUE SEARCHING") {
            self.getNextPerson()
            if self.firebaseIDs.count == 0 {
                self.performSegue(withIdentifier: "unwindToSearch", sender: self)
            }
        }
        
        popup.addButtons([msgButton, searchButton])
        self.present(popup, animated: true, completion: nil)
    }
    
    func getNextPerson() {
        firebaseIDs.remove(at: index)
        if firebaseIDs.count > 0 {
            index = 0
            loadVCs()
        }
    }
    
    // MARK: IBaction outlets
    @IBAction func donePressed(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func dislikePressed(_ sender: UIButton) {
        dislikeUser(recipID: firebaseIDs[index], completion: {
            self.getNextPerson()
            if self.firebaseIDs.count == 0 {
                self.performSegue(withIdentifier: "unwindToSearch", sender: self)
            }
        })
    }
    
    @IBAction func superLikePressed(_ sender: UIButton) {
        if defaults.integer(forKey: "superlikes") > 0 {
            superlikeUser(recipID: firebaseIDs[index], completion: { bool in
                defaults.set(defaults.integer(forKey: "superlikes") - 1, forKey: "superlikes")
                if bool { // this means other person liked
                    let image = self.selectedUser?.profilePic.resizeImageForMatch(newSize: CGSize(width: 200, height: 200))
                    self.createMatchPopup(image: image)
                }
                else {
                    self.getNextPerson()
                    if self.firebaseIDs.count == 0 {
                        self.performSegue(withIdentifier: "unwindToSearch", sender: self)
                    }
                }
            })
        }
        else {
            ranOutOfSuperlikes()
        }
    }
    
    @IBAction func likePressed(_ sender: UIButton) {
        if defaults.integer(forKey: "likes") > 0 {
            likeUser(recipID: firebaseIDs[index], completion: { bool in
                defaults.set(defaults.integer(forKey: "likes") - 1, forKey: "likes")
                if bool { // this means other person liked
                    let image = self.selectedUser?.profilePic.resizeImageForMatch(newSize: CGSize(width: 200, height: 200))
                    self.createMatchPopup(image: image)
                }
                else {
                    self.getNextPerson()
                    if self.firebaseIDs.count == 0 {
                        self.performSegue(withIdentifier: "unwindToSearch", sender: self)
                    }
                }
            })
        }
        else {
            ranOutOfLikes()
        }
    }
    
    // MARK: popover delegates
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
    
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        return true
    }
    
    // MARK: Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? ChatVC {
            destination.currentUser = selectedUser
            self.getNextPerson()
        }
    }

}

extension CustomTabVC: SwipeMenuViewDelegate {
    
    // MARK - SwipeMenuViewDelegate
    func swipeMenuView(_ swipeMenuView: SwipeMenuView, viewWillSetupAt currentIndex: Int) {
    }
    
    func swipeMenuView(_ swipeMenuView: SwipeMenuView, viewDidSetupAt currentIndex: Int) {
    }
    
    func swipeMenuView(_ swipeMenuView: SwipeMenuView, willChangeIndexFrom fromIndex: Int, to toIndex: Int) {
        // Codes
    }
    
    func swipeMenuView(_ swipeMenuView: SwipeMenuView, didChangeIndexFrom fromIndex: Int, to toIndex: Int) {
        // Codes
    }
}

extension CustomTabVC: SwipeMenuViewDataSource {
    
    //MARK - SwipeMenuViewDataSource
    func numberOfPages(in swipeMenuView: SwipeMenuView) -> Int {
        return viewControllers.count
    }
    
    func swipeMenuView(_ swipeMenuView: SwipeMenuView, titleForPageAt index: Int) -> String {
        return "#\(index+1)"
    }
    
    func swipeMenuView(_ swipeMenuView: SwipeMenuView, viewControllerForPageAt index: Int) -> UIViewController {
        return viewControllers[index]
    }
}
