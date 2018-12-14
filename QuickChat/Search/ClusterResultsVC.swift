//
//  ClusterResultsVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/9/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit
import PopupDialog
import Alamofire
import Firebase

class ClusterResultsVC: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    var profilePics: [UIImage]!
    var annotations: [PeopleAnnotation]!
    
    var selectedIndexPath: IndexPath!
    var selectedUser: User?
    var selectedAnnotation: PeopleAnnotation!

    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.navigationBar.tintColor = .white
        
        var uniqueAnnotations = [PeopleAnnotation]()
        for annotation in annotations {
            if !(uniqueAnnotations.map({ $0.firebaseID == annotation.firebaseID }).contains(true)) {
                uniqueAnnotations.append(annotation)
            }
        }
        annotations = uniqueAnnotations
        annotations = annotations.sorted {
            if $0.superlike == $1.superlike {
                return $0.duration > $1.duration
            }
            else {
                return $0.superlike && !$1.superlike
            }
        }
        
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if annotations.count == 0 {
            let _ = self.navigationController?.popViewController(animated: true)
        }
    }
    
    func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = 120
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.tableFooterView = UIView(frame: CGRect.zero)
        tableView.separatorColor = .white
    }
    
    func updateTable(index: Int) {
        annotations.remove(at: index)
        if annotations.count > 0 {
            let range = NSMakeRange(0, self.tableView.numberOfSections)
            let sections = NSIndexSet(indexesIn: range)
            self.tableView.reloadSections(sections as IndexSet, with: .automatic)
        }
    }
    
    // MARK: - Table view data source
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
 
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return annotations.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell1", for: indexPath) as! ClusterResultsCell
        cell.separatorInset = .zero
        
        cell.profilePic.layer.cornerRadius = cell.profilePic.frame.height / 2
        cell.profilePic.layer.borderColor = UIColor.white.cgColor
        cell.profilePic.layer.borderWidth = 1.5
        
        User.info(forUserID: annotations[indexPath.row].firebaseID, completion: { user in
            DispatchQueue.main.async {
                cell.profilePic.image = user.profilePic
            }
        })
        
        cell.nameLabel.text = annotations[indexPath.row].name
        cell.ageLabel.text = annotations[indexPath.row].age
        cell.blurbLabel.text = annotations[indexPath.row].blurb
        
        cell.superlikeView.image = annotations[indexPath.row].superlike ? UIImage(named: "roundedLogo") : nil
        
        if annotations[indexPath.row].buy && annotations[indexPath.row].receive {
            cell.statusLabel.text = "Wants to buy or receive a drink"
            cell.indicatorView.backgroundColor = UIColor(red: 129/255, green: 144/255, blue: 255/255, alpha: 0.4)
            //cell.backgroundColor = UIColor(red: 129/255, green: 144/255, blue: 255/255, alpha: 0.4)
        }
        else if annotations[indexPath.row].buy {
            cell.statusLabel.text = "Wants to buy someone a drink"
            cell.indicatorView.backgroundColor = UIColor(red: 65/255, green: 181/255, blue: 86/255, alpha: 0.4)
            //cell.backgroundColor = UIColor(red: 65/255, green: 181/255, blue: 86/255, alpha: 0.4)
        }
        else if annotations[indexPath.row].receive {
            cell.statusLabel.text = "Wants to receive a drink"
            cell.indicatorView.backgroundColor = UIColor(red: 250/255, green: 128/255, blue: 114/255, alpha: 0.4)
            //cell.backgroundColor = UIColor(red: 250/255, green: 128/255, blue: 114/255, alpha: 0.4)
        }
        
        if annotations[indexPath.row].superlike {
            let resizedLogo = UIImage(named: "purpleGlasses")!.resizeImageForMatch(newSize: CGSize(width: cell.frame.height/6, height: cell.frame.height/6))
            cell.backgroundColor = UIColor(patternImage: resizedLogo)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedIndexPath = indexPath
        self.performSegue(withIdentifier: "toPicturesFromSearch", sender: self)
        tableView.deselectRow(at: indexPath, animated: true)
    }
   
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let likeAction = UITableViewRowAction(style: .default, title: "Like") { action, indexPath in
            if defaults.integer(forKey: "likes") > 0 {
                self.likeUser(recipID: self.annotations[indexPath.row].firebaseID, completion: { bool in
                    defaults.set(defaults.integer(forKey: "likes") - 1, forKey: "likes")
                    if bool { // this means other person liked
                        let cell = tableView.cellForRow(at: indexPath) as! ClusterResultsCell
                        self.createMatchPopup(image: cell.profilePic.image?.resizeImageForMatch(newSize: CGSize(width: 200, height: 200)), annotation: self.annotations[indexPath.row], indexPath: indexPath)
                    }
                    else {
                        self.updateTable(index: indexPath.row)
                        if self.annotations.count == 0 {
                            let _ = self.navigationController?.popViewController(animated: true)
                        }
                    }
                })
            }
            else {
                self.ranOutOfLikes()
            }
            
        }
        likeAction.backgroundColor = UIColor(red: 65/255, green: 181/255, blue: 86/255, alpha: 1.0)
        
        let dislikeAction = UITableViewRowAction(style: .default, title: "Dislike") { action, indexPath in
            self.dislikeUser(recipID: self.annotations[indexPath.row].firebaseID, completion: {
                self.updateTable(index: indexPath.row)
                if self.annotations.count == 0 {
                    let _ = self.navigationController?.popViewController(animated: true)
                }
            })
        }
        dislikeAction.backgroundColor = UIColor(red: 237/255, green: 44/255, blue: 44/255, alpha: 1.0)
        
        let superlikeAction = UITableViewRowAction(style: .default, title: "Toast!") { action, indexPath in
            let myAlert = UIAlertController(title: "Toast this person?", message: nil, preferredStyle: .alert)
            let yesAction = UIAlertAction(title: "Yes", style: .cancel, handler: { _ in
                if defaults.integer(forKey: "superlikes") > 0 {
                    self.superlikeUser(recipID: self.annotations[indexPath.row].firebaseID, completion: { bool in
                        defaults.set(defaults.integer(forKey: "superlikes") - 1, forKey: "superlikes")
                        if bool { // this means other person liked
                            let cell = tableView.cellForRow(at: indexPath) as! ClusterResultsCell
                            self.createMatchPopup(image: cell.profilePic.image?.resizeImageForMatch(newSize: CGSize(width: 200, height: 200)), annotation: self.annotations[indexPath.row], indexPath: indexPath)
                        }
                        else {
                            self.updateTable(index: indexPath.row)
                            if self.annotations.count == 0 {
                                let _ = self.navigationController?.popViewController(animated: true)
                            }
                        }
                    })
                }
                else {
                    self.ranOutOfSuperlikes()
                }
            })
            let cancelAction = UIAlertAction(title: "Cancel", style: .default, handler: nil)
            
            myAlert.addAction(yesAction)
            myAlert.addAction(cancelAction)
            self.present(myAlert, animated: true, completion: nil)
        }
        superlikeAction.backgroundColor = GlobalVariables.purple
        
        return [likeAction, dislikeAction, superlikeAction]
    }

    

    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let nc = segue.destination as? UINavigationController {
            if let destination = nc.topViewController as? CustomTabVC {
                destination.firebaseIDs = annotations.map({ $0.firebaseID })
                destination.index = selectedIndexPath.row
                destination.ages = annotations.map({ $0.age })
            }
        }
        
        if let destination = segue.destination as? ChatVC {
            destination.currentUser = User(name: selectedAnnotation.name, email: "", id: selectedAnnotation.firebaseID, FCMToken: selectedAnnotation.deviceToken, profilePic: UIImage())
            self.updateTable(index: selectedIndexPath.row)
        }
        
    }

}

extension ClusterResultsVC {
    func createMatchPopup(image: UIImage?, annotation: PeopleAnnotation, indexPath: IndexPath) {
        self.createConvo(currentUserID: Auth.auth().currentUser!.uid, toID: annotation.firebaseID)
        
        var headers: HTTPHeaders = HTTPHeaders()
        
        headers = ["Content-Type": "application/json", "Authorization":"key=\(AppDelegate.SERVERKEY)"]
        
        let notification = ["to": annotation.deviceToken,
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
        
        let msgButton = DefaultButton(title: "MESSAGE") {
            self.selectedIndexPath = indexPath
            self.selectedAnnotation = annotation
            self.performSegue(withIdentifier: "toChatFromTable", sender: self)
        }
        
        let searchButton = DefaultButton(title: "CONTINUE SEARCHING") {
            self.updateTable(index: indexPath.row)
            if self.annotations.count == 0 {
                let _ = self.navigationController?.popViewController(animated: true)
            }
        }
        
        popup.addButtons([msgButton, searchButton])
        self.present(popup, animated: true, completion: nil)
    }
}

class ClusterResultsCell: UITableViewCell {
    @IBOutlet weak var ageLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var profilePic: UIImageView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var blurbLabel: UILabel!
    @IBOutlet weak var superlikeView: UIImageView!
    @IBOutlet weak var indicatorView: UIView!
    
    override func prepareForReuse() {
        ageLabel.text = nil
        nameLabel.text = nil
        statusLabel.text = nil
        blurbLabel.text = nil
        profilePic.image = nil
        superlikeView.image = nil
        indicatorView.backgroundColor = .white
    }
}
