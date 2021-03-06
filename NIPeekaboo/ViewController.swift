/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that facilitates the primary Nearby-Interaction user experience.
*/

import UIKit
import NearbyInteraction
import MultipeerConnectivity

class ViewController: UIViewController, NISessionDelegate {

    // MARK: - IBOutlets
    @IBOutlet weak var monkeyLabel: UILabel!
    @IBOutlet weak var centerInformationLabel: UILabel!
    @IBOutlet weak var detailContainer: UIView!
    @IBOutlet weak var detailAzimuthLabel: UILabel!
    @IBOutlet weak var detailDeviceNameLabel: UILabel!
    @IBOutlet weak var detailDistanceLabel: UILabel!
    @IBOutlet weak var detailDownArrow: UIImageView!
    @IBOutlet weak var detailElevationLabel: UILabel!
    @IBOutlet weak var detailLeftArrow: UIImageView!
    @IBOutlet weak var detailRightArrow: UIImageView!
    @IBOutlet weak var detailUpArrow: UIImageView!
    @IBOutlet weak var detailAngleInfoView: UIView!
    @IBOutlet weak var offerLabel: UILabel!
    @IBOutlet weak var offerImage: UIImageView!

    // MARK: - Distance and direction state
    let nearbyDistanceThreshold: Float = 0.5 // meters

    enum DistanceDirectionState {
        case closeUpInFOV, notCloseUpInFOV, outOfFOV, unknown
    }
    
    // MARK: - Class variables
    var session: NISession?
    var peerDiscoveryToken: NIDiscoveryToken?
    let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    var currentDistanceDirectionState: DistanceDirectionState = .unknown
    var mpc: MPCSession?
    var connectedPeer: MCPeerID?
    var sharedTokenWithPeer = false
    var peerDisplayName: String?
    var myPeerName = "Pizza Hut"

    // MARK: - UI LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        monkeyLabel.alpha = 0.0
        monkeyLabel.text = "🙈"
        centerInformationLabel.alpha = 1.0
        detailContainer.alpha = 0.0
        offerLabel.text = "Complimentary Lounge Access to Visa Cardholders"
        offerImage.image = UIImage(named: "lounge")
        
//        applyMerchantModeSettings()
        
        // Start the NISessions
        startup()
    }
    
    func applyMerchantModeSettings() {
        myPeerName = "Consumer"
        offerImage.isHidden = true
        offerLabel.isHidden = true
    }

    func startup() {
        // Create the NISession.
        session = NISession()
        
        // Set the delegate.
        session?.delegate = self
        
        // Since the session is new, this token has not been shared.
        sharedTokenWithPeer = false

        // If `connectedPeer` exists, share the discovery token if needed.
        if connectedPeer != nil && mpc != nil {
            if let myToken = session?.discoveryToken {
                updateInformationLabel(description: "Initializing ...")
                if !sharedTokenWithPeer {
                    shareMyDiscoveryToken(token: myToken)
                }
            } else {
                fatalError("Unable to get self discovery token, is this session invalidated?")
            }
        } else {
            updateInformationLabel(description: "Discovering Peer ...")
            startupMPC()
            
            // Set display state.
            currentDistanceDirectionState = .unknown
        }
    }

    // MARK: - NISessionDelegate

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerToken = peerDiscoveryToken else {
            fatalError("don't have peer token")
        }

        // Find the right peer.
        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }

        guard let nearbyObjectUpdate = peerObj else {
            return
        }

        // Update the the state and visualizations.
        sendOfferData(peer: nearbyObjectUpdate)
        let nextState = getDistanceDirectionState(from: nearbyObjectUpdate)
        updateVisualization(from: currentDistanceDirectionState, to: nextState, with: nearbyObjectUpdate)
        currentDistanceDirectionState = nextState
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let peerToken = peerDiscoveryToken else {
            fatalError("don't have peer token")
        }
        // Find the right peer.
        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }

        if peerObj == nil {
            return
        }

        currentDistanceDirectionState = .unknown
        offerLabel.text = ""
        switch reason {
        case .peerEnded:
            // Peer stopped communicating, this session is finished, invalidate.
            session.invalidate()
            
            // Restart the sequence to see if the other side comes back.
            startup()
            
            // Update visuals.
            updateInformationLabel(description: "Peer Ended")
        case .timeout:
            
            // Peer timeout occurred, but the session is still valid.
            // Check the configuration is still valid and re-run the session.
            if let config = session.configuration {
                session.run(config)
            }
            updateInformationLabel(description: "Peer Timeout")
        default:
            fatalError("Unknown and unhandled NINearbyObject.RemovalReason")
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        currentDistanceDirectionState = .unknown
        updateInformationLabel(description: "Session suspended")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        // Session suspension ended. The session can now be run again.
        if let config = self.session?.configuration {
            session.run(config)
        }

        centerInformationLabel.text = peerDisplayName
        detailDeviceNameLabel.text = peerDisplayName
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        currentDistanceDirectionState = .unknown
        
        // Session was invalidated, startup again to see if everything works.
        startup()
    }

    // MARK: - sharing and receiving discovery token via mpc mechanics

    func startupMPC() {
        if mpc == nil {
            // Avoid any simulator instances from finding any actual devices.
            #if targetEnvironment(simulator)
            mpc = MPCSession(service: "nisample",
                             identity: "com.example.apple-samplecode.simulator.peekaboo-nearbyinteraction",
                             maxPeers: 1,
                             myPeerName: myPeerName)
            #else
            mpc = MPCSession(service: "nisample",
                             identity: "com.example.apple-samplecode.peekaboo-nearbyinteraction",
                             maxPeers: 1,
                             myPeerName: myPeerName)
            #endif
            mpc?.peerConnectedHandler = connectedToPeer
            mpc?.peerDataHandler = dataReceivedHandler
            mpc?.peerDisconnectedHandler = disconnectedFromPeer
        }
        mpc?.invalidate()
        mpc?.start()
    }

    func connectedToPeer(peer: MCPeerID) {
        guard let myToken = session?.discoveryToken else {
            fatalError("Unexpectedly failed to initialize nearby interaction session.")
        }

        if connectedPeer != nil {
            fatalError("Already connected to a peer.")
        }

        if !sharedTokenWithPeer {
            shareMyDiscoveryToken(token: myToken)
        }

        connectedPeer = peer
        peerDisplayName = peer.displayName
        print("display name", peer)

        centerInformationLabel.text = peerDisplayName
        detailDeviceNameLabel.text = peerDisplayName
    }

    func disconnectedFromPeer(peer: MCPeerID) {
        if connectedPeer == peer {
            connectedPeer = nil
        }
    }

    func dataReceivedHandler(data: Data, peer: MCPeerID) {
        guard let dataObject = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NIDiscoveryToken.self, NSString.self], from: data) else {
            fatalError("Unexpectedly failed to decode dataObject.")
        }
        
        print("dataObject", dataObject)
        print(type(of: dataObject))
        
        if (dataObject is NIDiscoveryToken) {
            peerDidShareDiscoveryToken(peer: peer, token: dataObject as! NIDiscoveryToken)
        } else if (dataObject is NSString) {
            let data: String = dataObject as! String
            let dataObjectArray = data.components(separatedBy: "@@")
            print("received data", dataObjectArray)
            offerLabel.text = dataObjectArray[0]
            offerImage.image = UIImage(named: dataObjectArray[1])
//            let image = UIImage(named: dataObjectArray[1])
//            let imageView = UIImageView(image: image!)
//            imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 200)
//            detailContainer.addSubview(imageView)
        }
    }

    func shareMyDiscoveryToken(token: NIDiscoveryToken) {
        guard let encodedData = try?  NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            fatalError("Unexpectedly failed to encode discovery token.")
        }
        mpc?.sendDataToAllPeers(data: encodedData)
        sharedTokenWithPeer = true
    }

    func peerDidShareDiscoveryToken(peer: MCPeerID, token: NIDiscoveryToken) {
        if connectedPeer != peer {
            fatalError("Received token from unexpected peer.")
        }
        // Create an NI configuration
        peerDiscoveryToken = token

        let config = NINearbyPeerConfiguration(peerToken: token)

        // Run the session
        session?.run(config)
    }

    // MARK: - Visualizations
    func isNearby(_ distance: Float) -> Bool {
        return distance < nearbyDistanceThreshold
    }

    func isPointingAt(_ angleRad: Float) -> Bool {
        return abs(angleRad.radiansToDegrees) <= 15 // let's say that -15 to +15 degrees means pointing at
    }

    func getDistanceDirectionState(from nearbyObject: NINearbyObject) -> DistanceDirectionState {
        if nearbyObject.distance == nil && nearbyObject.direction == nil {
            return .unknown
        }

        let isNearby = nearbyObject.distance.map(isNearby(_:)) ?? false
        let directionAvailable = nearbyObject.direction != nil

        if isNearby && directionAvailable {
            return .closeUpInFOV
        }

        if !isNearby && directionAvailable {
            return .notCloseUpInFOV
        }

        return .outOfFOV
    }
    
    private func sendOfferData(peer: NINearbyObject) {
        let distance = String(format: "%0.2f", peer.distance!)
//        print("distance", distance)
        var data = ""
        var sendData = false
        
        if distance == "1.00" {
            data = "10% off for Pizza for Visa cardholders" + "@@" + "pizza"
            sendData = true
        } else if (distance == "0.80") {
            data = "20% off for Pasta for Visa Platinum cardholders" + "@@" + "pasta"
            sendData = true
        } else if (distance == "0.60") {
            data = "Free drinks for all Visa cardholders" + "@@" + "drinks"
            sendData = true
        }
        
        if sendData == true {
            guard let encodedData = try?  NSKeyedArchiver.archivedData(withRootObject: data) else {
                fatalError("Unexpectedly failed to send offer data.")
            }
            mpc?.sendDataToAllPeers(data: encodedData)
        }
    }
 
    private func animate(from currentState: DistanceDirectionState, to nextState: DistanceDirectionState, with peer: NINearbyObject) {
        let azimuth = peer.direction.map(azimuth(from:))
        let elevation = peer.direction.map(elevation(from:))

        centerInformationLabel.text = peerDisplayName
        detailDeviceNameLabel.text = peerDisplayName
        
        // If transitioning from unavailable state, bring the monkey and details into view,
        //  hide the center inforamtion label.
        if currentState == .unknown && nextState != .unknown {
            monkeyLabel.alpha = 0.0
            centerInformationLabel.alpha = 0.0
            detailContainer.alpha = 1.0
        }
        
        if nextState == .unknown {
            monkeyLabel.alpha = 0.0
            centerInformationLabel.alpha = 1.0
            detailContainer.alpha = 0.0
        }
        
        if nextState == .outOfFOV || nextState == .unknown {
            detailAngleInfoView.alpha = 0.0
        } else {
            detailAngleInfoView.alpha = 1.0
        }
        
        // Update the monkey label based on the next state.
        switch nextState {
        case .closeUpInFOV:
            monkeyLabel.text = "🙉"
        case .notCloseUpInFOV:
            monkeyLabel.text = "🙈"
        case .outOfFOV:
            monkeyLabel.text = "🙊"
        case .unknown:
            monkeyLabel.text = ""
        }
        
        if peer.distance != nil {
            detailDistanceLabel.text = String(format: "%0.2f m", peer.distance!)
        }
        
        monkeyLabel.transform = CGAffineTransform(rotationAngle: CGFloat(azimuth ?? 0.0))
        
        // No more visuals need to be updated if out of field of view or unavailable.
        if nextState == .outOfFOV || nextState == .unknown {
            return
        }
        
        if elevation != nil {
            if elevation! < 0 {
                detailDownArrow.alpha = 1.0
                detailUpArrow.alpha = 0.0
            } else {
                detailDownArrow.alpha = 0.0
                detailUpArrow.alpha = 1.0
            }
            
            if isPointingAt(elevation!) {
                detailElevationLabel.alpha = 1.0
            } else {
                detailElevationLabel.alpha = 0.5
            }
            detailElevationLabel.text = String(format: "% 3.0f°", elevation!.radiansToDegrees)
        }
        
        if azimuth != nil {
            if isPointingAt(azimuth!) {
                detailAzimuthLabel.alpha = 1.0
                detailLeftArrow.alpha = 0.25
                detailRightArrow.alpha = 0.25
            } else {
                detailAzimuthLabel.alpha = 0.5
                if azimuth! < 0 {
                    detailLeftArrow.alpha = 1.0
                    detailRightArrow.alpha = 0.25
                } else {
                    detailLeftArrow.alpha = 0.25
                    detailRightArrow.alpha = 1.0
                }
            }
            detailAzimuthLabel.text = String(format: "% 3.0f°", azimuth!.radiansToDegrees)
        }
    }
    
    func updateVisualization(from currentState: DistanceDirectionState, to nextState: DistanceDirectionState, with peer: NINearbyObject) {
        // Peekaboo or first measurement - use haptics.
        if currentState == .notCloseUpInFOV && nextState == .closeUpInFOV || currentState == .unknown {
            impactGenerator.impactOccurred()
        }

        // Animate into the next visuals.
        UIView.animate(withDuration: 0.3, animations: {
            self.animate(from: currentState, to: nextState, with: peer)
        })
    }

    func updateInformationLabel(description: String) {
        UIView.animate(withDuration: 0.3, animations: {
            self.monkeyLabel.alpha = 0.0
            self.detailContainer.alpha = 0.0
            self.centerInformationLabel.alpha = 1.0
            self.centerInformationLabel.text = description
        })
    }
}
