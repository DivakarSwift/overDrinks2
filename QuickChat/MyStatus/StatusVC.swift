//
//  StatusVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/8/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit
import Eureka
import Disk
import Firebase
import CloudKit
import Reachability
import NVActivityIndicatorView
import GeoFire
import ViewRow

class StatusVC: FormViewController, MyPhotosVCDelegate, CLLocationManagerDelegate, NVActivityIndicatorViewable {
    
    var underage: Bool = true
    
    var myPhotos = [ProfilePic]()
    
    var locationManager: CLLocationManager!
    lazy var geocoder = CLGeocoder()
    var userLocation: CLLocationCoordinate2D?
    
    let defaultFont = UIFont(name: "AvenirNext-Regular", size: 16)!
    let boldFont = UIFont(name: "AvenirNext-Bold", size: 16)!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        changeEurekaText()
        setupUserDefaults()
        setupNav()
        setupForm()
        
        try? reachability.startNotifier()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        
        myPhotos = try! Disk.retrieve("myPhotos.json", from: .documents, as: [ProfilePic].self)
        
        if reachability.connection == .none {
            print("No internet connection")
            self.alert(message: "Please check your internet connection and try again.", title: "Internet connection is not available")
        }
        else {
            self.updateForm()
            self.determineMyCurrentLocation()
            self.housekeeping()
        }
    }
    
    func housekeeping() {
        // remove convos
        Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("conversations").observe(.value, with: { snapshot in
            if snapshot.exists() {
                for child in snapshot.children {
                    let childSnap = child as! DataSnapshot
                    let data = childSnap.value as! [String: String]
                    let location = data["location"]
                    Database.database().reference().child("conversations").child(location!).observe(.value, with: { (snap) in
                        if snap.exists() {
                            for child in snap.children {
                                let firstMsg = (child as! DataSnapshot).value as! [String : Any]
                                let sender = firstMsg["fromID"] as! String
                                let recip = firstMsg["toID"] as! String
                                let creationTime = firstMsg["timestamp"] as! Double
                                if Date().timeIntervalSince1970 - creationTime > 18 * 60 * 60 { //
                                    Database.database().reference().child("conversations").child(location!).removeValue()
                                    Database.database().reference().child("users").child(sender).child("conversations").child(recip).removeValue()
                                    Database.database().reference().child("users").child(recip).child("conversations").child(sender).removeValue()
                                }
                                break
                            }
                        }
                    })
                }
                
            }
        })
    }
    
    func checkS3() {
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        self.tabBarController?.tabBar.isHidden = true
        
        NVActivityIndicatorView.DEFAULT_COLOR = .white
        NVActivityIndicatorView.DEFAULT_TEXT_COLOR = .white
        NVActivityIndicatorView.DEFAULT_BLOCKER_MESSAGE = "Setting up profile"
        
        self.startAnimating()
        self.stopAnimating()
        
    }
    
    func updateFirebaseProfilePic(picture: UIImage) {
        if let userID = Auth.auth().currentUser?.uid {
            let imageData = UIImageJPEGRepresentation(picture, 0.2)
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
        }
    }
 
    func changedPhotos(newPhotos: [UIImage], newChangedPhoto newChangedPhotos: [Bool]) {
        if let viewRow:ViewRow<UIImageView> = form.rowBy(tag: "profilePic") {
            for (index, pic) in myPhotos.enumerated() {
                if pic.hasPhoto {
                    let image = UIImage(data: self.myPhotos[index].imageData!)!
                    viewRow.view?.image = image
                    viewRow.reload()
                    break
                }
            }
        }
    }
    
    func uploadCoordinates() {
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
            case .authorizedAlways, .authorizedWhenInUse:
                if let _ = userLocation {
                    let geofireRef = Database.database().reference()
                    let geoFire = GeoFire(firebaseRef: geofireRef.child("userLocations"))
                    geoFire.setLocation(CLLocation(latitude: userLocation!.latitude, longitude: userLocation!.longitude), forKey: Auth.auth().currentUser!.uid)
                    
                    //geoFire.setLocation(CLLocation(latitude: 39.1329, longitude: 84.5150), forKey: "N0O9bfURrhbFeIWagPYFkWmBEiD2")
                }
                
                var values = [String: String]()
                
                if defaults.bool(forKey: "receive") {
                    values.updateValue(String(Date().timeIntervalSince1970), forKey: "receive")
                }
                else {
                    values.updateValue("0", forKey: "receive")
                }
                
                if defaults.bool(forKey: "buy") {
                    values.updateValue(String(Date().timeIntervalSince1970), forKey: "buy")
                }
                else {
                    values.updateValue("0", forKey: "buy")
                }
                
                if let currentUserId = Auth.auth().currentUser?.uid {
                    Database.database().reference().child("users").child(currentUserId).child("credentials").updateChildValues(values, withCompletionBlock: { (errr, _) in
                        UIApplication.shared.isNetworkActivityIndicatorVisible = false
                    })
                }
                else {
                    UIApplication.shared.isNetworkActivityIndicatorVisible = false
                }
                
                
            case .notDetermined, .restricted, .denied:
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
                print("No access")
            }
        }
    }
    
    func updateForm() {
        
        checkTimers()
        
        if let bdayLabel = form.rowBy(tag: "validBday") {
            if let dateRow = form.rowBy(tag: "birthday") as? DateRow {
                if let bday = dateRow.value {
                    let ageComponents = Calendar.current.dateComponents([.year], from: bday, to: Date())
                    let age = ageComponents.year!
                    bdayLabel.title = age >= 21 ? "\(age) years old" : "Under 21 years old"
                    defaults.set(age > 21 ? "\(age) years old" : "Under 21 years old", forKey: "age")
                    underage = age >= 21 ? false : true
                    bdayLabel.updateCell()
                }
            }
        }
        
        reloadBuyElapse()
        
        if let viewRow: ViewRow<UIImageView> = form.rowBy(tag: "profilePic") {
            for (index, pic) in myPhotos.enumerated() {
                if pic.hasPhoto {
                    let image = UIImage(data: self.myPhotos[index].imageData!)!
                    viewRow.view?.image = image
                    viewRow.reload()
                    break
                }
            }
        } 
        
        if let section = form.sectionBy(tag: "section1") {
            section.evaluateHidden()
        }
        
        if let section = form.sectionBy(tag: "section3") {
            section.evaluateHidden()
        }
    }
    
    func checkTimers() {
        if defaults.bool(forKey: "receive") {
            let elapsedTime = Date().timeIntervalSince(defaults.object(forKey: "receiveCreated") as! Date)
            if elapsedTime > 60 * 60 * 4 {
                let switchRow: SwitchRow = form.rowBy(tag: "receive")!
                switchRow.value = false
                switchRow.reload(with: .fade)
                defaults.set(false, forKey: "receive")
            }
        }
        
        if defaults.bool(forKey: "buy") {
            let elapsedTime = Date().timeIntervalSince(defaults.object(forKey: "buyCreated") as! Date)
            if elapsedTime > 60 * 60 * 4 {
                let switchRow: SwitchRow = form.rowBy(tag: "buy")!
                switchRow.value = false
                switchRow.reload(with: .fade)
                defaults.set(false, forKey: "buy")
            }
        }
    }
    
    func reloadBuyElapse() {
        if let buyElapse = form.rowBy(tag: "buyElapse") {
            if defaults.bool(forKey: "buy") {
                if let buyCreated = defaults.object(forKey: "buyCreated") as? Date {
                    buyElapse.title = "Active for \(Date().offset(from: buyCreated))"
                    buyElapse.reload(with: .top)
                }
            }
        }
    }
    
    func setupForm() {
        form
            /*
        // Upgrades
        +++ Section("Upgrades")
        <<< ButtonRow("moreLikes") {
            $0.title = "Add more likes for tonight"
            }
        <<< ButtonRow("unlimitedLikes") {
            $0.title = "Get unlimited likes for the month"
        }
        <<< SwitchRow("pilot") {
            $0.title = "Get pilot status"
        } */
            
        // WHAT I WANT
        +++ Section(footer: "Note: You can stay active for up to 4 hours. The longer you are active, the more likely you are to be seen. Tap refresh to reset the timer.") { section in
            section.tag = "section1"
            section.hidden = Condition.function(["name", "birthday", "manage", "profilePic", "sex"], { form in
                if let _ = (form.rowBy(tag: "name") as? TextRow)?.value {
                    if !self.underage {
                        if self.myPhotos.compactMap({$0.hasPhoto}).contains(true) {
                            if let segRow: SegmentedRow<String> = form.rowBy(tag: "sex") {
                                if let _ = segRow.value {
                                    self.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
                                    return false
                                }
                            }
                            
                        }
                    }
                }
                return true
            })
        }
            
            <<< SwitchRow("buy") { row in
                row.value = defaults.bool(forKey: "buy") ? true : false
                if row.value! {
                    row.title = "ACTIVE: Find people nearby"
                }
                else {
                    row.title = "INACTIVE: You cannot be seen"
                }
                }.onChange { row in
                    row.title = row.value! ? "ACTIVE: Find people nearby" : "INACTIVE: You cannot be seen"
                    if row.value! {
                        defaults.set(true, forKey: "buy")
                        defaults.set(Date(), forKey: "buyCreated")
                    }
                    else {
                        defaults.set(false, forKey: "buy")
                    }
                    self.uploadCoordinates()
                    self.reloadBuyElapse()
                    row.updateCell()
                }.cellUpdate { cell, row in
                    cell.textLabel?.font = defaults.bool(forKey: "buy") ? self.boldFont : self.defaultFont
            }
            
            <<< LabelRow("buyElapse"){
                $0.hidden = Condition.function(["buy"], { form in
                    return !((form.rowBy(tag: "buy") as? SwitchRow)?.value ?? false)
                })
                if defaults.bool(forKey: "buy") {
                    if let buyCreated = defaults.object(forKey: "buyCreated") as? Date {
                        $0.title = "Active for \(Date().offset(from: buyCreated))"
                    }
                }
            }
            
            <<< ButtonRow("refresh") {
                $0.title = "Refresh"
                $0.onCellSelection( { (cell, row) in
                    if defaults.bool(forKey: "buy") {
                        defaults.set(Date(), forKey: "buyCreated")
                        self.reloadBuyElapse()
                    }
                    
                    self.uploadCoordinates()
                })
            }
        
            
        // MY INFORMATION
        +++ Section("My Information")
            <<< TextRow("name") { row in
                row.title = "First Name"
                row.placeholder = "Name Here"
                
                NVActivityIndicatorView.DEFAULT_COLOR = .white
                NVActivityIndicatorView.DEFAULT_TEXT_COLOR = .white
                NVActivityIndicatorView.DEFAULT_BLOCKER_MESSAGE = "Loading profile"
                self.startAnimating()
                User.info(forUserID: Auth.auth().currentUser!.uid, completion: { user in
                    DispatchQueue.main.async {
                        row.value = user.name
                        row.updateCell()
                        defaults.set(user.name.trimmingCharacters(in: .whitespaces), forKey: "name")
                        self.stopAnimating()
                    }
                })
                
                }.onCellHighlightChanged { cell, row in
                    if !row.isHighlighted {
                        if let name = row.value {
                            if name.trimmingCharacters(in: .whitespaces).count > 0 {
                                defaults.set(name.trimmingCharacters(in: .whitespaces), forKey: "name")
                                let value = ["name": name.trimmingCharacters(in: .whitespaces)]
                                Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("credentials").updateChildValues(value, withCompletionBlock: { (errr, _) in
                                    if errr == nil {
                                        print("updated name")
                                    }
                                })
                            }
                        }
                    }
                }.onChange { row in
                    row.updateCell()
                }.cellUpdate { cell, row in
                    if let name = row.value {
                        if name.trimmingCharacters(in: .whitespaces).count > 0 {
                            cell.textLabel?.textColor = .black
                        }
                    }
                    else {
                        cell.textLabel?.textColor = .red
                    }
            }
            
            <<< SegmentedRow<String>("sex") {
                $0.title = "Sex"
                $0.options = ["Male", "Female", "Non-binary"]
                
                if let sex = defaults.object(forKey: "sex") as? String {
                    $0.value = sex
                }
                
                }.onChange { row in
                    defaults.set(row.value!, forKey: "sex")
                    
                    var filters = [Bool](repeating: true, count: 5)
                    if row.value! == "Male" {
                        filters[0] = false
                        filters[2] = false
                        defaults.set(filters, forKey: "filters")
                    }
                    else if row.value! == "Female" {
                        filters[1] = false
                        filters[2] = false
                        defaults.set(filters, forKey: "filters")
                    }
                    
                    let value = ["sex": row.value!]
                    Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("credentials").updateChildValues(value, withCompletionBlock: { (errr, _) in
                        print("updated sex")
                    })
                    row.updateCell()
                }.cellUpdate { cell, row in
                    cell.segmentedControl.setContentHuggingPriority(UILayoutPriority.defaultHigh, for: .horizontal)
                    if let _ = defaults.object(forKey: "sex") as? String {
                        cell.textLabel?.textColor = .black
                    }
                    else {
                        cell.textLabel?.textColor = .red
                    }
            }
            
            <<< DateRow("birthday") {
                $0.title = "Date of Birth"
                if let bday = defaults.object(forKey: "birthday") as? Date {
                    $0.value = bday
                }
                else {
                    $0.value = Date()
                }
                }.onChange { row in
                    if let date = row.value {
                        defaults.set(date, forKey: "birthday")
                        let ageComponents = Calendar.current.dateComponents([.year], from: date, to: Date())
                        let age = ageComponents.year!
                        self.underage = age >= 21 ? false : true
                        
                        if let bdayLabel = self.form.rowBy(tag: "validBday") {
                            bdayLabel.title = age >= 21 ? "\(age) years old" : "Under 21 years old"
                            let value = ["age": bdayLabel.title!]
                            Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("credentials").updateChildValues(value, withCompletionBlock: { (errr, _) in
                                print("updated age")
                            })
                            print("saved bday")
                            bdayLabel.updateCell()
                        }
                    }
                }
            
            <<< LabelRow("validBday") {
                $0.title = ""
                $0.cellStyle = .default
                }.cellUpdate { cell, row in
                    cell.textLabel?.textColor = self.underage ? UIColor.red : UIColor.black
                    cell.textLabel?.textAlignment = .right
                }
            
            <<< TextAreaRow("blurb") {
                $0.placeholder = "Your tag line in 40 characters or fewer"
                $0.add(rule: RuleMaxLength(maxLength: 40))
                $0.validationOptions = .validatesAlways
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 40)
                $0.value = defaults.object(forKey: "blurb") as? String ?? ""
                $0.onCellHighlightChanged { cell, row in
                    let value = ["blurb": row.value]
                    Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("credentials").updateChildValues(value, withCompletionBlock: { (errr, _) in
                        if errr == nil {
                            print("updated blurb")
                            defaults.set(row.value, forKey: "blurb")
                        }
                    })
                }.cellUpdate { cell, row in
                    if !row.isValid {
                        row.value = String(row.value!.prefix(40))
                    }
                }
            }
            
            // MY PICTURES
            +++ Section("My Profile pictures") { section in
                section.tag = "section3"
                section.hidden = Condition.function(["name", "birthday", "sex"], { form in
                    if let _ = (form.rowBy(tag: "name") as? TextRow)?.value {
                        if !self.underage {
                            if let segRow: SegmentedRow<String> = form.rowBy(tag: "sex") {
                                if let _ = segRow.value {
                                    return false
                                }
                            }
                        }
                    }
                    return true
                })
            }
            
            <<< ButtonRow("manage") {
                $0.title = "Manage Pictures"
                $0.onCellSelection( { (cell, row) in
                    self.toManagePhotos()
                })
            }
            
            <<< ViewRow<UIImageView>("profilePic")
                .cellSetup { (cell, row) in
                    cell.height = { return CGFloat(200) }
                    
                    var image = UIImage(named: "profile pic")!
                    for (index, pic) in self.myPhotos.enumerated() {
                        if pic.hasPhoto {
                            image = UIImage(data: self.myPhotos[index].imageData!)!
                            break
                        }
                    }
                    image = image.resizeImage(targetSize: CGSize(width: 200, height: 200))
                    cell.view = UIImageView()
                    cell.contentView.addSubview(cell.view!)
                    cell.view?.isUserInteractionEnabled = true
                    
                    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.toManagePhotos))
                    cell.view?.addGestureRecognizer(tapGesture)
                    
                    cell.view!.image = image
                    cell.view!.contentMode = .scaleAspectFit
                    //cell.view!.layer.cornerRadius = 100
                    cell.view!.layer.masksToBounds = true
                    cell.view!.clipsToBounds = true
                    cell.clipsToBounds = true
            }
        
            <<< ButtonRow("view") {
                $0.title = "View Profile"
                $0.onCellSelection( { (cell, row) in
                    self.performSegue(withIdentifier: "toPicturesFromProfile", sender: self)
                })
            }
        
            <<< ButtonRow("logout") {
                $0.title = "Log Out"
                $0.onCellSelection( { (cell, row) in
                    let myAlert = UIAlertController(title: "Log out?", message: nil, preferredStyle: .alert)
                    let yesAction = UIAlertAction(title: "Yes", style: .default, handler: { _ in
                        User.logOutUser { (status) in
                            if status == true {
                                defaults.set(false, forKey: "secondTime")
                                self.dismiss(animated: true, completion: nil)
                            }
                        }
                    })
                    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                    myAlert.addAction(yesAction)
                    myAlert.addAction(cancelAction)
                    self.present(myAlert, animated: true, completion: nil)
                })
            }
    }
    
    @objc func toManagePhotos() {
        self.performSegue(withIdentifier: "toPhotos", sender: self)
    }
    
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? MyPhotosVC {
            destination.myPhotos = myPhotos
            destination.delegate = self
        }
        
        if let nc = segue.destination as? UINavigationController {
            if let destination = nc.topViewController as? CustomTabVC {
                destination.firebaseIDs = [Auth.auth().currentUser!.uid]
                destination.index = 0
                destination.ages = [defaults.string(forKey: "age")!]
            }
        }
    }

}

extension StatusVC {
    func determineMyCurrentLocation() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        manager.delegate = nil
        manager.stopUpdatingLocation()
        
        if let location = locations.last{
            userLocation = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.uploadCoordinates()
        }
    }
    
    func changeEurekaText() {
        SwitchRow.defaultCellSetup =  { cell, row in
            cell.textLabel?.font = self.defaultFont
            cell.separatorInset = .zero
        }
        
        LabelRow.defaultCellSetup =  { cell, row in
            cell.textLabel?.font = self.defaultFont
            cell.separatorInset = .zero
        }
        
        ButtonRow.defaultCellSetup =  { cell, row in
            cell.textLabel?.font = self.defaultFont
            cell.separatorInset = .zero
        }
        
        SegmentedRow<String>.defaultCellSetup =  { cell, row in
            cell.textLabel?.font = self.defaultFont
            cell.separatorInset = .zero
        }
        
        DateRow.defaultCellSetup =  { cell, row in
            cell.textLabel?.font = self.defaultFont
            cell.detailTextLabel?.font = self.defaultFont
            cell.separatorInset = .zero
        }
        
        TextRow.defaultCellSetup =  { cell, row in
            cell.textLabel?.font = self.defaultFont
            cell.detailTextLabel?.font = self.defaultFont
            cell.separatorInset = .zero
        }
        
        TextAreaRow.defaultCellSetup =  { cell, row in
            cell.textView.textAlignment = .center
            cell.textView.font = UIFont(name: "AvenirNext-Italic", size: 16)!
            cell.placeholderLabel?.textAlignment = .center
            cell.placeholderLabel?.font = UIFont(name: "AvenirNext-Italic", size: 16)!
            cell.separatorInset = .zero
        }
    }
    
    func setupUserDefaults() {
        if Disk.exists("myPhotos.json", in: .documents) {
            myPhotos = try! Disk.retrieve("myPhotos.json", from: .documents, as: [ProfilePic].self)
        }
        else {
            for i in 0...5 {
                let profilePic = ProfilePic()
                profilePic.hasPhoto = false
                profilePic.s3Key = Auth.auth().currentUser!.uid + "-\(i)"
                profilePic.imageData = UIImageJPEGRepresentation(UIImage(named: "profile pic")!, 1.0)
                myPhotos.append(profilePic)
            }
            try? Disk.save(myPhotos, to: .documents, as: "myPhotos.json")
        }
        
        if !defaults.bool(forKey: "secondTime") { // if first time, check cloud, otherwise use saved info
            defaults.set(false, forKey: "receive")
            defaults.set(false, forKey: "buy")
            
            checkS3()
            
            if let bday = defaults.object(forKey: "birthday") as? Date {
                let ageComponents = Calendar.current.dateComponents([.year], from: bday, to: Date())
                let age = ageComponents.year!
                self.underage = age >= 21 ? false : true
                
                let label = age >= 21 ? "\(age) years old" : "Under 21 years old"
                let value = ["age": label]
                
                Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("credentials").updateChildValues(value, withCompletionBlock: { (errr, _) in
                    print("updated age")
                })
            }
            
            defaults.set(true, forKey: "secondTime")
        }
        
        // setup filters
        if let _ = defaults.array(forKey: "filters") as? [Bool] {
        }
        else {
            var filters = [Bool](repeating: true, count: 3)
            defaults.set(filters, forKey: "filters")
        }
        
        if let _ = defaults.object(forKey: "minAge") as? Int {
        }
        else {
            defaults.set(21, forKey: "minAge")
        }
        
        if let _ = defaults.object(forKey: "maxAge") as? Int {
        }
        else {
            defaults.set(87, forKey: "maxAge")
        }
    }
    
}
