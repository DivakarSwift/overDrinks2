//
//  SearchVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/8/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import Firebase
import Cluster
import GeoFire
import CloudKit

class SearchVC: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate, UIPopoverPresentationControllerDelegate, FilterOptionsTVCDelegate {
    
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var refreshOutlet: UIBarButtonItem!
    @IBOutlet weak var filterOutlet: UIBarButtonItem!
    @IBOutlet weak var legendOutlet: UIBarButtonItem!
    @IBOutlet weak var emptyLabel: UILabel!
    
    var locationManager: CLLocationManager!
    lazy var geocoder = CLGeocoder()
    var userLocation: CLLocationCoordinate2D?
    
    let clusterManager = ClusterManager()
    var annotations: [PeopleAnnotation] = []
    let searchRadius: Double = 400 // // meters; change to 400 before publication
    var refreshGroup = DispatchGroup()
    var isRefreshing = false
    var userInfo = [String: CLLocation]()
    var circleQuery: GFCircleQuery!
    var queryHandle: UInt!
    var likedIDs: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupNav()
        
        refreshOutlet.tintColor = .white
        filterOutlet.tintColor = .white
        legendOutlet.tintColor = .white
        
        mapView.delegate = self
        
        clusterManager.minCountForClustering = 2
        clusterManager.maxZoomLevel = 10000000
        clusterManager.cellSize = nil
        
        emptyLabel.isHidden = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        if reachability.connection == .none {
            print("No internet connection")
            self.alert(message: "Please check your internet connection and try again.", title: "Internet connection is not available")
        }
        else if !defaults.bool(forKey: "buy") {
            let myAlert = UIAlertController(title: "Please become active to begin searching", message: nil, preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .cancel, handler: { _ in
                self.tabBarController?.selectedIndex = 0
            })
            myAlert.addAction(okAction)
            self.present(myAlert, animated: true)
        }
        else {
            housekeeping()
            clusterManager.removeAll()
            for annotation in mapView.annotations {
                mapView.removeAnnotation(annotation)
            }
            
            if defaults.bool(forKey: "buy") {
                determineMyCurrentLocation()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            if let _ = self.userLocation {
                self.refreshPressed(nil)
            }
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
        })
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    @IBAction func unwindToSearch(_ sender: UIStoryboardSegue) {
        
    }
    
    func filterChanged(newFilters: [Bool]) {
        refreshPressed(nil)
    }
    
    @IBAction func legendPressed(_ sender: UIBarButtonItem) {
        let popoverContent = self.storyboard?.instantiateViewController(withIdentifier: "LegendVC") as! LegendVC
        
        let nav = UINavigationController(rootViewController: popoverContent)
        nav.modalPresentationStyle = .popover
        let popover = nav.popoverPresentationController
        
        popover?.barButtonItem = sender
        popover?.permittedArrowDirections = [.down, .up]
        popover?.delegate = self
        self.present(nav, animated: true, completion: nil)
    }
    
    
    @IBAction func filterPressed(_ sender: UIBarButtonItem) {
        let popoverContent = self.storyboard?.instantiateViewController(withIdentifier: "FilterOptionsTVC") as! FilterOptionsTVC
        popoverContent.delegate = self
        
        let nav = UINavigationController(rootViewController: popoverContent)
        nav.modalPresentationStyle = .popover
        let popover = nav.popoverPresentationController
        
        popover?.barButtonItem = sender
        popover?.permittedArrowDirections = [.down, .up]
        popover?.delegate = self
        self.present(nav, animated: true, completion: nil)
    }
    
    func filterChanged() {
        refreshPressed(nil)
    }
    
    @IBAction func refreshPressed(_ sender: UIBarButtonItem?) {
        sender?.isEnabled = false
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        refreshGroup.enter()
        isRefreshing = true
        
        clusterManager.removeAll()
        for overlay in self.mapView.overlays {
            self.mapView.remove(overlay)
        }
        DispatchQueue.main.async {
            self.findPeopleNearMe()
        }
        
        refreshGroup.notify(queue: .main) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                self.clusterManager.reload(mapView: self.mapView)
                let region = MKCoordinateRegionMakeWithDistance(self.userLocation!, self.searchRadius*2, self.searchRadius*2)
                self.mapView.setRegion(region, animated: true)
                
                let circle = MKCircle(center: self.mapView.userLocation.coordinate, radius: self.searchRadius)
                self.mapView.add(circle)
                sender?.isEnabled = true
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            })
        }
    }
    
    func getUsedIDs(completion: @escaping () -> Void) {
        likedIDs = []
        Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).observeSingleEvent(of: .value, with: { snapshot in
            if snapshot.exists() {
                for snap in snapshot.children {
                    let child = snap as! DataSnapshot
                    if !["credentials", "conversations", "reference", "blockList"].contains(child.key) {
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
    
    func findPeopleNearMe() {
        let geofireRef = Database.database().reference()
        let geoFire = GeoFire(firebaseRef: geofireRef.child("userLocations"))
        
        circleQuery = geoFire.query(at: CLLocation(latitude: userLocation!.latitude, longitude: userLocation!.longitude), withRadius: searchRadius/1000)
        userInfo = [String: CLLocation]()
        queryHandle = circleQuery.observe(.keyEntered, with: { (userID: String!, location: CLLocation!) in
            print("start query")
            self.clusterManager.removeAll()
            if userID != Auth.auth().currentUser!.uid {
                self.userInfo.updateValue(location, forKey: userID)
                //print("userID '\(userID)' entered the search area and is at location '\(location)'")
            }
            //geoFire.removeKey(userID)
        })
        
        circleQuery.observeReady({
            print("finished getting users and locations")
            if self.userInfo.count > 0 {
                DispatchQueue.main.async {
                    self.emptyLabel.isHidden = true
                }
                self.getUsedIDs(completion: {
                    self.addUsersToMap(userInfo: self.userInfo)
                    for (userID, location) in self.userInfo {
                        geoFire.removeKey(userID)
                    }
                })
            }
            else {
                if self.tabBarController?.selectedIndex == 1 {
                    DispatchQueue.main.async {
                        self.emptyLabel.isHidden = false
                        self.emptyLabel.frame.origin.x = -self.view.frame.width
                        UIView.animate(withDuration: 0.3, animations: {
                            self.emptyLabel.frame.origin.x = 12
                        })
                    }
                }
            }
        })
    
    }
    
    func addUsersToMap(userInfo: [String: CLLocation]) {
        let group = DispatchGroup()
        Database.database().reference().child("users").observe(.value, with: { (snapshot) in
            if snapshot.exists() {
                for child in snapshot.children {
                    let snap = child as! DataSnapshot
                    if let location = userInfo[snap.key] {
                        group.enter()
                        
                        let person = snap.childSnapshot(forPath: "credentials").value as! [String: String]
                        
                        let thisLocation = location.coordinate
                        
                        let personBuyDuration = Double(Date().timeIntervalSince1970) - Double(person["buy"]!)!
                        let personBuying = personBuyDuration < 60 * 60 * 4
                        
                        if personBuying {
                            let annotation = PeopleAnnotation()
                            annotation.coordinate = thisLocation
                            annotation.firebaseID = snap.key
                            annotation.deviceToken = person["deviceToken"]
                            annotation.name = person["name"]
                            annotation.age = person["age"]
                            annotation.buy = personBuying
                            annotation.blurb = person["blurb"] ?? ""
                            User.info(forUserID: annotation.firebaseID, completion: { user in
                                annotation.profilePic = user.profilePic
                            })
                            
                            if let me = snap.childSnapshot(forPath: Auth.auth().currentUser!.uid).value as? [String: Any] {
                                if let superlike = me["superlike"] as? Bool {
                                    annotation.superlike = superlike
                                }
                            }
                            
                            if personBuying {
                                annotation.style = .color(UIColor(red: 65/255, green: 181/255, blue: 86/255, alpha: 1), radius: 25)
                                annotation.duration = personBuyDuration
                            }
                            
                            self.clusterManager.add(annotation)
                            
                            let filters = defaults.array(forKey: "filters") as! [Bool]
                            
                            if !filters[0] && person["sex"] == "Male" {
                                self.clusterManager.remove(annotation)
                                group.leave()
                            }
                            else if !filters[1] && person["sex"] == "Female" {
                                self.clusterManager.remove(annotation)
                                group.leave()
                            }
                            else if !filters[2] && person["sex"] == "Non-binary" {
                                self.clusterManager.remove(annotation)
                                group.leave()
                            }
                            else if Int(annotation.age.split(separator: " ").first!)! < defaults.integer(forKey: "minAge") { // min age filter
                                self.clusterManager.remove(annotation)
                                group.leave()
                            }
                            else if Int(annotation.age.split(separator: " ").first!)! > defaults.integer(forKey: "maxAge") { // max age filters
                                self.clusterManager.remove(annotation)
                                group.leave()
                            } /*
                            else if self.likedIDs.contains(annotation.firebaseID) { // remove already liked/disliked ppl
                                self.clusterManager.remove(annotation)
                                group.leave()
                            } */
                            else { // remove if blocked
                                Database.database().reference().child("users").child(annotation.firebaseID).child("blockList").observe(.value, with: { snapshot in
                                    if snapshot.exists() {
                                        let data = snapshot.value as! [String: Bool]
                                        if let blocked = data[Auth.auth().currentUser!.uid] {
                                            if blocked {
                                                self.clusterManager.remove(annotation)
                                            }
                                        }
                                        group.leave()
                                    }
                                })
                            }
                        }
                        else {
                            group.leave()
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    print("finished updating map")
                    
                    self.clusterManager.reload(mapView: self.mapView)
                    
                    if self.clusterManager.annotations.count == 0 {
                        if self.tabBarController?.selectedIndex == 1 {
                            DispatchQueue.main.async {
                                self.emptyLabel.isHidden = false
                                self.emptyLabel.frame.origin.x = -self.view.frame.width
                                UIView.animate(withDuration: 0.3, animations: {
                                    self.emptyLabel.frame.origin.x = 12
                                })
                            }
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            self.emptyLabel.isHidden = true
                        }
                    }
                }
            }
        })
        
        if self.isRefreshing { // leave refresh dispatch group
            self.isRefreshing = false
            self.refreshGroup.leave()
        }
    }
    
    func region(for annotation: MKAnnotation) -> MKCoordinateRegion {
        let region: MKCoordinateRegion = MKCoordinateRegionMakeWithDistance(annotation.coordinate, searchRadius, searchRadius)
        
        return mapView.regionThatFits(region)
    }
    
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        if let userLocation = annotation as? MKUserLocation {
            userLocation.title = nil
            return nil
        }
        
        if let annotation = annotation as? ClusterAnnotation {
            //guard let style = annotation.style else { return nil }
            let identifier = "Cluster"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if let view = view as? BorderedClusterAnnotationView {
                view.annotation = annotation
                view.style = .color(.orange, radius: 25)
                view.configure()
            }
            else {
                view = BorderedClusterAnnotationView(annotation: annotation, reuseIdentifier: identifier, style: .color(.orange, radius: 25), borderColor: .white)
            }
            
            return view
        }
        else {
            guard let annotation = annotation as? PeopleAnnotation, let style = annotation.style else { return nil }
            
            if annotation.superlike {
                let identifier = "logo"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if let view = view {
                    view.annotation = annotation
                    view.canShowCallout = false
                }
                else {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                }
                
                view?.image = UIImage(named: "roundedLogo")
                view?.contentMode = .scaleAspectFill
                view?.frame.size = CGSize(width: 28, height: 28)
                view?.layer.cornerRadius = view!.frame.size.height/2
                view?.layer.masksToBounds = true
                view?.layer.borderColor = UIColor.white.cgColor
                view?.layer.borderWidth = 2
                
                return view
            }
            else {
                let identifier = "Pin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) //as MKPinAnnotationView
                if let view = view {
                    view.annotation = annotation
                    view.canShowCallout = false
                }
                else {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier) //as MKPinAnnotationView
                }
                
                view?.image = annotation.profilePic
                view?.contentMode = .scaleAspectFill
                view?.frame.size = CGSize(width: 28, height: 28)
                view?.layer.cornerRadius = view!.frame.size.height/2
                view?.layer.masksToBounds = true
                view?.layer.borderColor = UIColor.white.cgColor
                view?.layer.borderWidth = 2
                
                return view
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        clusterManager.reload(mapView: mapView) { finished in
            
        }
    }
    
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        views.forEach { $0.alpha = 0 }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [], animations: {
            views.forEach { $0.alpha = 1 }
        }, completion: nil)
    }
    
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        
        annotations = []
        
        if let cluster = annotation as? ClusterAnnotation {
            for annotation in cluster.annotations {
                let annotation = annotation as! PeopleAnnotation
                annotations.append(annotation)
            }
        }
        
        if let annotation = annotation as? PeopleAnnotation {
            annotations.append(annotation)
        }
        
        if annotations.count > 1 {
            self.performSegue(withIdentifier: "toClusterResults", sender: self)
        }
        else if annotations.count == 1 {
            self.performSegue(withIdentifier: "toProfilePicsFromMap", sender: self)
        }
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay.isKind(of: MKCircle.self) {
            let view = MKCircleRenderer(overlay: overlay)
            view.fillColor = UIColor.blue.withAlphaComponent(0.1)
            view.strokeColor = .blue
            view.lineWidth = 1
            return view
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? ClusterResultsVC {
            destination.annotations = annotations
        }
        
        if let nc = segue.destination as? UINavigationController {
            if let destination = nc.topViewController as? CustomTabVC {
                destination.firebaseIDs = annotations.map({ $0.firebaseID })
                destination.index = 0
                destination.ages = [annotations.first!.age]
            }
        }
        
    }
}

extension SearchVC {
    func housekeeping() {
        let currentDateTime = Date()
        let userCalendar = Calendar.current
        let requestedComponents: Set<Calendar.Component> = [.year, .month, .day, .hour]
        let dateTimeComponents = userCalendar.dateComponents(requestedComponents, from: currentDateTime)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd-yyyy HH:mm"
        
        if let reference = defaults.value(forKey: "reference") as? Double {
            if Date().timeIntervalSince1970 - reference > 24 * 60 * 60 {
                updateReference(dateTimeComponents: dateTimeComponents, dateFormatter: dateFormatter)
            }
        }
        else {
            Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("reference").observeSingleEvent(of: .value, with: { snapshot in
                if snapshot.exists() {
                    let data = snapshot.value as! [String: Any]
                    let reference = data["checkpoint"] as! Double
                    defaults.set(reference, forKey: "reference")
                    if Date().timeIntervalSince1970 - reference > 24 * 60 * 60 {
                        self.updateReference(dateTimeComponents: dateTimeComponents, dateFormatter: dateFormatter)
                    }
                }
                else {
                    self.updateReference(dateTimeComponents: dateTimeComponents, dateFormatter: dateFormatter)
                }
            })
        }
    }
    
    func updateReference(dateTimeComponents: DateComponents, dateFormatter: DateFormatter) {
        let dateString = "\(dateTimeComponents.month!)-\(dateTimeComponents.day!)-\(dateTimeComponents.year!) 11:00"
        let date = dateFormatter.date(from: dateString)?.timeIntervalSince1970
        defaults.set(date, forKey: "reference")
        let reference = ["checkpoint": date!, "likes": 50, "superlikes": 1] as [String : Any]
        Database.database().reference().child("users").child(Auth.auth().currentUser!.uid).child("reference").updateChildValues(reference)
        defaults.set(50, forKey: "likes")
        defaults.set(1, forKey: "superlikes")
    }
    
    func determineMyCurrentLocation() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization()
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .notDetermined, .denied, .restricted:
            let myAlert = UIAlertController(title: "Location services not enabled.", message: "Please enable location services to begin finding exciting people.", preferredStyle: .alert)
            let settingsAction = UIAlertAction(title: "Open Settings", style: .cancel, handler: { _ in
                if let url = URL(string: UIApplicationOpenSettingsURLString) {
                    if UIApplication.shared.canOpenURL(url) {
                        if #available(iOS 10.0, *) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                        else {
                            UIApplication.shared.openURL(url)
                        }
                    }
                }
            })
            let cancelAction = UIAlertAction(title: "Maybe Later", style: .default, handler: nil)
            myAlert.addAction(settingsAction)
            myAlert.addAction(cancelAction)
            self.present(myAlert, animated: true, completion: {
                self.tabBarController?.selectedIndex = 0
            })
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        manager.delegate = nil
        manager.stopUpdatingLocation()
        
        if let location = locations.last {
            userLocation = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            
            let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let region = MKCoordinateRegionMakeWithDistance(center, searchRadius*2, searchRadius*2)
            self.mapView.setRegion(region, animated: false)
        }
    }
    
    // MARK: popover delegates
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
    
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        return true
    }
    
}

class BorderedClusterAnnotationView: ClusterAnnotationView {
    let borderColor: UIColor
    
    init(annotation: MKAnnotation?, reuseIdentifier: String?, style: ClusterAnnotationStyle, borderColor: UIColor) {
        self.borderColor = borderColor
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier, style: style)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func configure() {
        super.configure()
        
        switch style {
        case .image:
            layer.borderWidth = 0
        case .color:
            layer.borderColor = borderColor.cgColor
            layer.borderWidth = 2
        }
    }
}

