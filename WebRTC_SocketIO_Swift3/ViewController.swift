//
//  ViewController.swift
//  WebRTC_SocketIO_Swift3
//
//  Created by Pouria Sanae on 8/20/16.
//  Copyright © 2016 Pouria Sanae. All rights reserved.

/********************************
 Information
 ------------
 Frame workes and libs
 https://github.com/socketio/socket.io-client-swift (Swift3)
 https://github.com/socketio/socket.io-client-swift/issues/462
 https://github.com/unkei/MyWebRTCSwift/blob/master/MyWebRTCSwift/ViewController.swift
 https://cocoapods.org/pods/libjingle_peerconnection
 
 
 
 Build setting > Build option > ENABLE_BITCODE is tunrened of see
 https://github.com/pristineio/webrtc-build-scripts/issues/131
 http://stackoverflow.com/questions/31088618/impact-of-xcode-build-options-enable-bitcode-yes-no
 

*/
import AVFoundation
import UIKit
//import Socket_IO_Client_Swift //SocketIOClientSwift

let TAG = "ViewController"
let VIDEO_TRACK_ID = TAG + "VIDEO"
let AUDIO_TRACK_ID = TAG + "AUDIO"
let LOCAL_MEDIA_STREAM_ID = TAG + "STREAM"

class ViewController: UIViewController, RTCSessionDescriptionDelegate, RTCPeerConnectionDelegate, RTCEAGLVideoViewDelegate {
    
    var mediaStream: RTCMediaStream!
    var localVideoTrack: RTCVideoTrack!
    var localAudioTrack: RTCAudioTrack!
    var remoteVideoTrack: RTCVideoTrack!
    var remoteAudioTrack: RTCAudioTrack!
    var renderer: RTCEAGLVideoView!
    var renderer_sub: RTCEAGLVideoView!
    var roomName: String!
    
    
    // *** Initial ViewController methods ********--------------------------------------
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        initWebRTC();
        sigConnect(wsUrl: "unwebrtc.herokuapp.com");  //sigConnect("10.54.36.19:8000");
        
        renderer = RTCEAGLVideoView(frame: self.view.frame)
        renderer_sub = RTCEAGLVideoView(frame: CGRect(x:20,y:50,width:90,height:120))
        self.view.addSubview(renderer)
        self.view.addSubview(renderer_sub)
        renderer.delegate = self;
        
        var device: AVCaptureDevice! = nil
        for captureDevice in AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) {
            if ((captureDevice as AnyObject).position == AVCaptureDevicePosition.front) {
                device = captureDevice as! AVCaptureDevice
            }
        }
        if (device != nil) {
            let capturer = RTCVideoCapturer(deviceName: device.localizedName)
            
            let videoConstraints = RTCMediaConstraints()
            var audioConstraints = RTCMediaConstraints()
            let videoSource = peerConnectionFactory.videoSource(with: capturer, constraints: videoConstraints)
            localVideoTrack = peerConnectionFactory.videoTrack(withID: VIDEO_TRACK_ID, source: videoSource)
            //            AudioSource audioSource = peerConnectionFactory.createAudioSource(audioConstraints)
            localAudioTrack = peerConnectionFactory.audioTrack(withID: AUDIO_TRACK_ID)
            
            mediaStream = peerConnectionFactory.mediaStream(withLabel: LOCAL_MEDIA_STREAM_ID)
            mediaStream.addVideoTrack(localVideoTrack)
            mediaStream.addAudioTrack(localAudioTrack)
            
            localVideoTrack.add(renderer_sub)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        // FIXME: temporarily placed here but should be somwhere called only when app terminates
        RTCPeerConnectionFactory.deinitializeSSL()
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    // *** Controler functions  ********--------------------------------------
    func showRoomDialog() {
        // show dialog to enter room number and call sigReconnect() to reconnect ws and join into new room
        // Performing just leave and join again would work though but it needs sever to support leave message.
        sigRecoonect();
    }
    func getRoomName() -> String {
        return (roomName == nil || roomName.isEmpty) ? "_defaultroom": roomName;
    }
    func Log(value:String) {
        print(TAG + " " + value)
    }
    
    
    // *** RTCEAGLVideoViewDelegate related methods ********----------------------------
    func videoView(_ videoView: RTCEAGLVideoView!, didChangeVideoSize size: CGSize) {
        // scale by height
        let w = renderer.bounds.height * size.width / size.height
        let h = renderer.bounds.height
        let x = (w - renderer.bounds.width) / 2
        renderer.frame = CGRect(x:-x,y:0,width:w,height:h) // CGRectMake(-x, 0, w, h)
    }
    
    
    // *** WebRTC methods  ********--------------------------------------------
    var peerConnectionFactory: RTCPeerConnectionFactory! = nil
    var peerConnection: RTCPeerConnection! = nil
    var pcConstraints: RTCMediaConstraints! = nil
    var videoConstraints: RTCMediaConstraints! = nil
    var audioConstraints: RTCMediaConstraints! = nil
    var mediaConstraints: RTCMediaConstraints! = nil
    var socket: SocketIOClient! = nil
    var wsServerUrl: String! = nil
    var peerStarted: Bool = false
    
    func initWebRTC() {
        RTCPeerConnectionFactory.initializeSSL()
        peerConnectionFactory = RTCPeerConnectionFactory()
        
        pcConstraints = RTCMediaConstraints()
        videoConstraints = RTCMediaConstraints()
        audioConstraints = RTCMediaConstraints()
        mediaConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                RTCPair(key: "OfferToReceiveAudio", value: "true"),
                RTCPair(key: "OfferToReceiveVideo", value: "true")
            ],
            optionalConstraints: nil)
    }
    func connect() {
        if (!peerStarted) {
            sendOffer()
            peerStarted = true
        }
    }
    func hangUp() {
        sendDisconnect()
        stop()
    }
    func stop() {
        if (peerConnection != nil) {
            peerConnection.close()
            peerConnection = nil
            peerStarted = false
        }
    }
    
    func prepareNewConnection() -> RTCPeerConnection {
        let icsServers: [RTCICEServer] = []
        let rtcConfig: RTCConfiguration = RTCConfiguration()
        rtcConfig.tcpCandidatePolicy = RTCTcpCandidatePolicy.disabled
        rtcConfig.bundlePolicy = RTCBundlePolicy.maxBundle
        rtcConfig.rtcpMuxPolicy = RTCRtcpMuxPolicy.require
        
        peerConnection = peerConnectionFactory.peerConnection(withICEServers: icsServers, constraints: pcConstraints, delegate: self)
        peerConnection.add(mediaStream);
        return peerConnection;
    }

    
    // *** RTCPeerConnectionDelegate  ********--------------------------------------------
    func peerConnection(_ peerConnection: RTCPeerConnection!, signalingStateChanged stateChanged: RTCSignalingState) {
    }
    func peerConnection(_ peerConnection: RTCPeerConnection!, iceConnectionChanged newState: RTCICEConnectionState) {
    }
    func peerConnection(_ peerConnection: RTCPeerConnection!, iceGatheringChanged newState: RTCICEGatheringState) {
    }
    func peerConnection(_ peerConnection: RTCPeerConnection!, gotICECandidate candidate: RTCICECandidate!) {
        if (candidate != nil) {
            Log(value: "iceCandidate: " + candidate.description)
            let json:[String: AnyObject] = [
                "type" : "candidate" as AnyObject,
                "sdpMLineIndex" : candidate.sdpMLineIndex as AnyObject,
                "sdpMid" : candidate.sdpMid as AnyObject,
                "candidate" : candidate.sdp as AnyObject
            ]
            sigSend(msg: json as NSDictionary)
        } else {
            Log(value: "End of candidates. -------------------")
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection!, addedStream stream: RTCMediaStream!) {
        if (peerConnection == nil) {
            return
        }
        if (stream.audioTracks.count > 1 || stream.videoTracks.count > 1) {
            Log(value: "Weird-looking stream: " + stream.description)
            return
        }
        if (stream.videoTracks.count == 1) {
            remoteVideoTrack = stream.videoTracks[0] as! RTCVideoTrack
            remoteVideoTrack.setEnabled(true)
            remoteVideoTrack.add(renderer);
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection!, removedStream stream: RTCMediaStream!) {
        remoteVideoTrack = nil
        //stream.videoTracks[0].dispose();
    }
    func peerConnection(_ peerConnection: RTCPeerConnection!, didOpen dataChannel: RTCDataChannel!) {
    }
    func peerConnection(onRenegotiationNeeded peerConnection: RTCPeerConnection!) {
    }
   
    
    
    // *** RTCSessionDescriptionDelegate ********--------------------------------------
    func onOffer(sdp:RTCSessionDescription) {
        setOffer(sdp: sdp)
        sendAnswer()
        peerStarted = true;
    }
    func onAnswer(sdp:RTCSessionDescription) {
        setAnswer(sdp: sdp)
    }
    func onCandidate(candidate:RTCICECandidate) {
        peerConnection.add(candidate)
    }
    func sendSDP(sdp:RTCSessionDescription) {
        let json:[String: AnyObject] = [
            "type" : sdp.type as AnyObject,
            "sdp"  : sdp.description as AnyObject
        ]
        sigSend(msg: json as NSDictionary);
    }
    func sendOffer() {
        peerConnection = prepareNewConnection();
        peerConnection.createOffer(with: self, constraints: mediaConstraints)
    }
    func setOffer(sdp:RTCSessionDescription) {
        if (peerConnection != nil) {
            Log(value: "peer connection already exists")
        }
        peerConnection = prepareNewConnection();
        peerConnection.setRemoteDescriptionWith(self, sessionDescription: sdp)
    }
    func sendAnswer() {
        Log(value: "sending Answer. Creating remote session description...")
        if (peerConnection == nil) {
            Log(value: "peerConnection NOT exist!")
            return
        }
        peerConnection.createAnswer(with: self, constraints: mediaConstraints)
    }
    func setAnswer(sdp:RTCSessionDescription) {
        if (peerConnection == nil) {
            Log(value: "peerConnection NOT exist!")
            return
        }
        peerConnection.setRemoteDescriptionWith(self, sessionDescription: sdp)
    }
    func sendDisconnect() {
        let json:[String: AnyObject] = [
            "type" : "user disconnected" as AnyObject
        ]
        sigSend(msg: json as NSDictionary);
    }

    func peerConnection(_ peerConnection: RTCPeerConnection!, didSetSessionDescriptionWithError error: Error!) {
    }
    func peerConnection(_ peerConnection: RTCPeerConnection!, didCreateSessionDescription sdp: RTCSessionDescription!, error: Error!) {
        if (error == nil) {
            peerConnection.setLocalDescriptionWith(self, sessionDescription: sdp)
            Log(value: "Sending: SDP")
            Log(value: sdp.description)
            sendSDP(sdp: sdp)
        } else {
            print(error)
            //Log(value: "sdp creation error: " + error.description)
        }
    }

 
    // *** websocket related operations ********----------------------------------------
    func sigConnect(wsUrl:String) {
        wsServerUrl = wsUrl;
        
        //let opts:[String: AnyObject] = [
        let opts:NSDictionary = [
            "log"  : true
        ]
        Log(value: "connecting to " + wsServerUrl)
        socket = SocketIOClient(socketURL: NSURL(string: wsServerUrl)!, config: opts)
        // pouria socket = SocketIOClient(socketURL: wsServerUrl, opts: opts)
        socket.on("connect") { data in
            self.Log(value: "WebSocket connection opened to: " + self.wsServerUrl);
            self.sigEnter();
        }
        socket.on("disconnect") { data in
            self.Log(value: "WebSocket connection closed.")
        }
        socket.on("message") { (data, emitter) in
            if (data.count == 0) {
                return
            }
            
            let json = data[0] as! NSDictionary
            self.Log(value: "WSS->C: " + json.description);
            
            let type = json["type"] as! String
            
            if (type == "offer") {
                self.Log(value: "Received offer, set offer, sending answer....");
//                var sdp = RTCSessionDescription(type: type, sdp: json["sdp"] as! String)
//                self.onOffer(sdp: sdp!);
            } else if (type == "answer" && self.peerStarted) {
                self.Log(value: "Received answer, setting answer SDP");
 //               var sdp = RTCSessionDescription(type: type, sdp: json["sdp"] as! String)
 //               self.onAnswer(sdp: sdp!);
            } else if (type == "candidate" && self.peerStarted) {
                self.Log(value: "Received ICE candidate...");
 //               var candidate = RTCICECandidate(
//                    mid: json["sdpMid"] as! String,
//                    index: json["sdpMLineIndex"] as! Int,
//                    sdp: json["candidate"] as! String)
//                self.onCandidate(candidate: candidate!);
            } else if (type == "user disconnected" && self.peerStarted) {
                self.Log(value: "disconnected");
//                self.stop();
            } else {
                self.Log(value: "Unexpected WebSocket message: " + data[0].description);
            }
        }
        socket.connect();
    }
    func sigRecoonect() {
        socket.disconnect() //pouria .disconnect(fast: true);
        socket.connect();
    }
    func sigEnter() {
//        var roomName = getRoomName();
 //       self.Log(value: "Entering room: " + roomName);
 //       socket.emit("enter", roomName);
    }
    func sigSend(msg:NSDictionary) {
        socket.emit("message", msg)
    }

}

