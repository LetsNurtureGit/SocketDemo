//
//  DriverVC.swift
//  SocketDemo
//
//  Created by LN-iMAC-003 on 01/02/18.
//  Copyright © 2018 LN-MCMI-005. All rights reserved.
//

import UIKit
import GooglePlaces

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l > r
    default:
        return rhs < lhs
    }
}

class DriverVC: UIViewController {

    @IBOutlet weak var gMapView: GMSMapView!
    
    let socket = SocketIOClient(socketURL: URL(string:socketURL)!, config: [.log(false),.forceNew(true)])
    
    var locationmanager: LocationManager!
    var gmsMarker : GMSMarker!
    var reachability: Reachability?
    var isInternetAvailable = false
    
    var socketConnectionTimeoutCount = 0
    var isConnected = false
    var isJoin = false
    var isTrack = false
    var isDriverFound = false
    var didFindMyLocation = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.locationmanager = LocationManager.sharedInstance
        locationmanager.showVerboseMessage = false
        locationmanager.autoUpdate = true
        
        //Internet active/Inactive state checking
        startNotifier()
        
        let dispatchTime = DispatchTime.now() + DispatchTimeInterval.seconds(1)
        DispatchQueue.main.asyncAfter(deadline: dispatchTime) {
            self.stopNotifier()
            self.setupReachability("google.com", useClosures: true)
            self.startNotifier()
        }
        
        if locationmanager == nil {
            self.locationmanager = LocationManager.sharedInstance
            self.locationmanager.isDriverOnline = true
            locationmanager.showVerboseMessage = false
            locationmanager.autoUpdate = true
            
            let status = CLLocationManager.authorizationStatus()
            if (status == .authorizedAlways || status == .authorizedWhenInUse){
                self.locationmanager.startUpdatingLocationWithCompletionHandler {[unowned self](latitude, longitude, speed, status, verboseMessage, error) -> () in
                    if let _ = error {
                        print(error ?? "")
                    }
                    else {
                        self.gMapView!.isMyLocationEnabled = false
                        let location:CLLocationCoordinate2D = CLLocationCoordinate2DMake(latitude, longitude)
                        self.gMapView!.camera = GMSCameraPosition.camera(withTarget: location, zoom: 15.0)
                        self.gmsMarker.position = location
                        self.gmsMarker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                        self.locationmanager.stopUpdatingLocation()
                    }
                }
            }
        }
        
        self.locationmanager.startUpdatingLocation()
        
        //gMapView!.isMyLocationEnabled = true
        
        gmsMarker = GMSMarker.init()
        gmsMarker.icon = UIImage(named: "ic_myLocation")
        gmsMarker.map = gMapView!
        gmsMarker.appearAnimation = .pop
        
        //gMapView!.settings.zoomGestures = false
        //gMapView!.settings.tiltGestures = false
        //gMapView!.settings.rotateGestures = false
        //gMapView!.settings.scrollGestures = false
        //gMapView!.settings.allowScrollGesturesDuringRotateOrZoom = false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension DriverVC: GMSMapViewDelegate{
    //MARK: Mapview delegate methods
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if !didFindMyLocation {
            if let myLocation: CLLocation = change![NSKeyValueChangeKey.newKey] as? CLLocation {
                gMapView.camera = GMSCameraPosition.camera(withTarget: myLocation.coordinate, zoom: 15.0)
                gMapView.settings.myLocationButton = false
                
                didFindMyLocation = true
            }
        }
    }
    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
        //reverseGeocodeCoordinate(position.target)
    }
    
    func didTapMyLocationButton(for mapView: GMSMapView) -> Bool {
        let position = CLLocationCoordinate2D(latitude: 37.470856, longitude: -121.930858)
        gMapView.camera = GMSCameraPosition.camera(withTarget: (position), zoom: 15.0)
        return true;
    }
    
    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {

        return true
    }
}

extension DriverVC {
    func connectSocket () {
        NSLog("connectSocket method")
        socket.connect()
        
        // Connects to socket
        socket.on("connect") {[unowned self]data, ack in
            NSLog("socket connected.")
            self.socketConnectionTimeoutCount = 0
            self.isConnected = true
            
            //self.socket.emit("track", self.parkingId! as String, self.userId! as String, "Customer" as String)
            self.trackEvent()
        }
        
        socket.on("close") {[unowned self]data, ack in // Disconnect from socket
            //print("socket disconnected.")
            self.isConnected = false
            self.isJoin = false
            self.isTrack = false
        }
        
        socket.on("reconnect") {data, ack in
            print("socket reconnecting. \(data)")
            if self.socketConnectionTimeoutCount > 10 {
                self.socketConnectionTimeoutCount = 0
                
            }
            else{
                self.socketConnectionTimeoutCount += 1
            }
        }
        
        socket.onAny {_ in
            ////print("Got event: \($0.event), with items: \($0.items)")
        }
        
        //Call this is anyone left from Socket
        socket.on("left") {[unowned self] data, ack in
            print("Left: \(data)")
        }
        
        //Receive data from Driver
        socket.on("tracked") {[unowned self] data, ack in
            print("tracked data: \(data)")
        }
        
        socket.on("error") {[unowned self]data, ack in
            if self.isInternetAvailable {
                if self.socket.status == .connecting{
                    //print("please wait socket connecting")
                }
                else if (self.socket.status == .notConnected || self.socket.status == .disconnected) && self.socket.status != .connected {
                    if self.socketConnectionTimeoutCount > 10 {
                        self.socketConnectionTimeoutCount = 0
                    }
                    else{
                        self.socketConnectionTimeoutCount += 1
                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(CustomerVC.tryForSocketReconnect), object: nil)
                        self.perform(#selector(CustomerVC.tryForSocketReconnect), with: nil, afterDelay: 1)
                    }
                }
            }
            else{
            }
        }
    }
    
    // Customer Transmits his/ her Data
    func trackEvent () {
        self.isTrack = true
        self.isJoin = true
        if locationmanager != nil {
            self.locationmanager.startUpdatingLocationWithCompletionHandler {[unowned self] (latitude, longitude, speed, status, verboseMessage, error) -> () in
                if let _ = error {
                    
                }
                else {
                    self.gMapView.isMyLocationEnabled = true
                    let location:CLLocationCoordinate2D = CLLocationCoordinate2DMake(latitude, longitude)
                    self.gMapView!.camera = GMSCameraPosition.camera(withTarget: location, zoom: 15.0)
                    self.gmsMarker.position = location
                    if self.isTrack {
                        let msgob = [
                            "lat"  :  String(latitude),
                            "lng"   : String(longitude)
                        ]
                        print("Driver Location: \(msgob)")
                        self.socket.emit("track", msgob )
                    }
                }
            }
        }
    }
    
    // MARK: Car Rotation methods
    func DegreeBearing(_ A:CLLocation,B:CLLocation)-> Double{
        var dlon = self.ToRad(B.coordinate.longitude - A.coordinate.longitude)
        let dPhi = log(tan(self.ToRad(B.coordinate.latitude) / 2 + Double.pi / 4) / tan(self.ToRad(A.coordinate.latitude) / 2 + Double.pi / 4))
        if  abs(dlon) > Double.pi{
            dlon = (dlon > 0) ? (dlon - 2*Double.pi) : (2*Double.pi + dlon)
        }
        return self.ToBearing(atan2(dlon, dPhi))
    }
    
    func ToRad(_ degrees:Double) -> Double{
        return degrees*(Double.pi/180)
    }
    
    func ToBearing(_ radians:Double)-> Double{
        return (ToDegrees(radians) + 360).truncatingRemainder(dividingBy: 360)
    }
    
    func ToDegrees(_ radians:Double)->Double {
        return radians * 180 / Double.pi
    }
}

extension DriverVC {
    //MARK: Reachability Management
    func setupReachability(_ hostName: String?, useClosures: Bool) {
        let reachability = hostName == nil ? Reachability() : Reachability(hostname: hostName!)
        self.reachability = reachability
        
        if useClosures {
            reachability?.whenReachable = { reachability in
                DispatchQueue.main.async {
                    self.startSocketAgain(reachability)
                }
            }
            reachability?.whenUnreachable = { reachability in
                DispatchQueue.main.async {
                    self.startSocketAgain(reachability)
                }
            }
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(CustomerVC.reachabilityChanged(_:)), name: ReachabilityChangedNotification, object: reachability)
        }
    }
    
    func startNotifier() {
        do {
            try reachability?.startNotifier()
        } catch {
            return
        }
    }
    
    func stopNotifier() {
        reachability?.stopNotifier()
        NotificationCenter.default.removeObserver(self, name: ReachabilityChangedNotification, object: nil)
        reachability = nil
    }
    
    func reachabilityChanged(_ note: Notification) {
        let reachability = note.object as! Reachability
        
        if reachability.isReachable {
            self.startSocketAgain(reachability)
        } else {
            self.startSocketAgain(reachability)
        }
    }
    
    func startSocketAgain(_ reachability: Reachability) {
        if reachability.isReachable{
            isInternetAvailable = true
            if self.isJoin{
                if self.socket.status == .connecting {
                    //                    print("please wait socket connecting")
                }
                else if (self.socket.status == .notConnected || self.socket.status == .disconnected) {
                    //                    print("please wait socket reconnecting")
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(CustomerVC.tryForSocketReconnect), object: nil)
                    self.perform(#selector(CustomerVC.tryForSocketReconnect), with: nil, afterDelay: 1)
                }
                else{
                    //print("socket is already connected.")
                }
            }
            else{
                DispatchQueue.main.async {
                    self.connectSocket()
                }
            }
        }
        else {
            isInternetAvailable = false
            showNoInternetAlert("The Internet Connection appears to be Offline.")
            self.locationmanager.stopUpdatingLocation()
        }
    }
    
    func showNoInternetAlert(_ message: String) {
        let actionSheetController: UIAlertController = UIAlertController(title: "Parcel", message: message, preferredStyle: .alert)
        let okAction: UIAlertAction = UIAlertAction(title: "OK", style: .cancel) { action -> Void in
            //Just dismiss the action sheet
        }
        actionSheetController.addAction(okAction)
        self.present(actionSheetController, animated: true, completion: nil)
    }
    
    func tryForSocketReconnect() {
        self.socket.reconnect()
    }
}
