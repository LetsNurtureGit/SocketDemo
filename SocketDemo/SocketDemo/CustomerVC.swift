//
//  CustomerVC.swift
//  SocketDemo
//
//  Created by LN-MCMI-005 on 30/01/18.
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

class CustomerVC: UIViewController {

    @IBOutlet weak var gMapView: GMSMapView!
    
    let socket = SocketIOClient(socketURL: URL(string:socketURL)!, config: [.log(false),.forceNew(true)])
    
    //let socket = SocketIOClient(socketURL: URL(string:socketURL)!, config: [.path("/socket.io"),.log(false),.secure(true),.forceWebsockets(true)])
    var locationmanager: LocationManager!
    var reachability: Reachability?
    var isInternetAvailable = false
    
    var socketConnectionTimeoutCount = 0
    var isConnected = false
    var isJoin = false
    var isTrack = false
    
    var markers : [String : GMSMarker] = [:]
    
    //MARK: - ViewDidLoad Method -
    override func viewDidLoad() {
        super.viewDidLoad()

        self.locationmanager = LocationManager.sharedInstance
        locationmanager.showVerboseMessage = false
        locationmanager.autoUpdate = true
        
        //Internet active/Inactive state checking
        startNotifier()
        // After 5 seconds, stop and re-start reachability, this time using a hostname
        let dispatchTime = DispatchTime.now() + DispatchTimeInterval.seconds(1)
        DispatchQueue.main.asyncAfter(deadline: dispatchTime) {
            self.stopNotifier()
            self.setupReachability("google.com", useClosures: true)
            self.startNotifier()
        }
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

extension CustomerVC {
    func connectSocket () {
        NSLog("connectSocket method")
        socket.connect()
        
        // Connects to socket
        socket.on("connect") {[unowned self]data, ack in
            NSLog("Customer Socket connected.")
            self.socketConnectionTimeoutCount = 0
            self.isConnected = true
            
            //self.socket.emit("track", self.parkingId! as String, self.userId! as String, "Customer" as String)
            self.emitMyLocation()
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
            
            if self.isJoin {
                if data.count > 0 {
                    let obj = data[0] as! [String : AnyObject]
                    let lat = Double(obj["lat"]! as! String)!
                    let lng = Double(obj["lng"]! as! String)!
                    let userOBJ = ""
                    
                    if lat != 0 && lng != 0 {
                        //let locationCoordinates = CLLocationCoordinate2D(latitude: Double(lat), longitude: Double(lng))
                        let position = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        //if self.markers[userOBJ] != nil { // rotate car on map
                            //self.markers[userOBJ]!.rotation = Double(obj["heading"] as! String)!
                            self.markers[userOBJ] = GMSMarker(position: position)
                            self.markers[userOBJ]!.icon = UIImage(named: "ic_Car")
                            //self.markers[userOBJ]!.userData = ["markerInfo": "Driver", "data": data]
                            //self.markers[userOBJ]!.isTappable  = true
                            self.markers[userOBJ]!.appearAnimation = .pop
                            self.markers[userOBJ]!.map = self.gMapView
                        //}
                    }
                }
            }
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
    
    // Customer Transmits Data
    func emitMyLocation () {
        self.isTrack = true
        self.isJoin = true
        if locationmanager != nil {
            self.locationmanager.startUpdatingLocationWithCompletionHandler {[unowned self] (latitude, longitude, speed, status, verboseMessage, error) -> () in
                if let _ = error {
                    
                }
                else {
                    self.gMapView.isMyLocationEnabled = true
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
}

extension CustomerVC {
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
                else if (self.socket.status == .notConnected || self.socket.status == .disconnected){
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
