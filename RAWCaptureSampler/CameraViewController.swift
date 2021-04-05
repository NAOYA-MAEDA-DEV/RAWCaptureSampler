//
//  CameraViewController.swift
//  RAWCaptureSampler
//
//  Created by NAOYA MAEDA on 2021/04/05.
//

import UIKit
import Photos
import AVFoundation

class CameraViewController: UIViewController {
    
    @IBOutlet weak var typeSegmentControl: UISegmentedControl!
    @IBOutlet weak var previewImageView: UIImageView!
    @IBOutlet weak var shutterButton: UIButton!
    
    let captureSession = AVCaptureSession()
    var captureVideoLayer: AVCaptureVideoPreviewLayer!
    let photoOutput = AVCapturePhotoOutput()
    let videoDataOutput = AVCaptureVideoDataOutput()
    
    var currentDevice: AVCaptureDevice?
    var videoDeviceInput: AVCaptureDeviceInput!
    var settingsForMonitoring =  AVCapturePhotoSettings()
    
    let sessionQueue = DispatchQueue(label: "session_queue")
    
    var setupResult: SessionSetupResult = .success // Session Setup Result
    enum SessionSetupResult {
        case success // Success
        case notAuthorized // No permisson to Camera device or Photo album
        case configurationFailed // Failed
    }
    
    var captureType: CaptureType = .photo // Capture Type
    enum CaptureType {
        case photo // Photo
        case raw // RAW
        case proRaw // Apple ProRAW
    }
    
    var compressedData: Data?
    var rawImageFileURL: URL!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.checkPermission()
        
        self.sessionQueue.async {
            self.configureSession()
        }
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.captureSession.startRunning()
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "RAW Capture Smapler",
                                                            message: "RAW Capture Smapler doesn't have permission to use the camera.",
                                                            preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: "OK",
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: "Settings",
                                                            style: .default,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "RAW Capture Smapler",
                                                            message: "RAW Capture Smapler doesn't have permission to use the photo album",
                                                            preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: "OK",
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
    }
    
    
    func checkPermission() {
        // Camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
            
        case .notDetermined:
            self.sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                  self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            self.setupResult = .notAuthorized
            break
        }
        
        // Photo album
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            break
            
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ photoAuthStatus in
                if photoAuthStatus ==  PHAuthorizationStatus.authorized {
                }
            })
            
        default :
            break
        }
    }
    
    
    func configureSession() {
        guard setupResult == .success else { return }
        self.captureSession.beginConfiguration()
        do {
            var defaultVideoDevice: AVCaptureDevice?
            if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                defaultVideoDevice = backCameraDevice
            }
            
            guard let videoDevice = defaultVideoDevice else {
                self.setupResult = .configurationFailed
                self.captureSession.commitConfiguration()
                return
            }
            
            currentDevice = videoDevice
            
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
                self.videoDeviceInput = input
                
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                    self.captureVideoLayer = AVCaptureVideoPreviewLayer.init(session: self.captureSession)
                    self.captureVideoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
                    DispatchQueue.main.async {
                        self.captureVideoLayer.frame = self.previewImageView.bounds
                        self.previewImageView.contentMode = .scaleAspectFill
                        self.previewImageView.layer.addSublayer(self.captureVideoLayer)
                    }
                }
                
                if self.captureSession.canAddOutput(self.videoDataOutput) {
                    self.captureSession.addOutput(self.videoDataOutput)
                }
                
                self.captureSession.sessionPreset = AVCaptureSession.Preset.photo
                
                self.videoDataOutput.videoSettings =
                               [kCVPixelBufferPixelFormatTypeKey as AnyHashable as!
                                   String: Int(kCVPixelFormatType_32BGRA)]
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            }
        } catch {
            self.setupResult = .configurationFailed
            self.captureSession.commitConfiguration()
            return
        }
        
        captureSession.commitConfiguration()
        
        do {
            try self.currentDevice!.lockForConfiguration()
            if self.currentDevice!.isExposureModeSupported(.continuousAutoExposure) {
                self.currentDevice!.exposureMode = .continuousAutoExposure
            }
            if self.currentDevice!.isFocusModeSupported(.continuousAutoFocus) {
                self.currentDevice!.focusMode = .continuousAutoFocus
            }
            if self.currentDevice!.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                self.currentDevice!.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            self.currentDevice!.unlockForConfiguration()
        } catch let error {
            print("ERROR:\(error)")
        }
        
        /*
         Check if it is possible to shoot RAW.
         Only iPhone 12 Pro and iPhone 12 Pro Max installed iOS 14.3 or later can shoot Apple Pro Raw.
         */
        if let _ = self.photoOutput.availableRawPhotoPixelFormatTypes.first {
            if #available(iOS 14.3, *) {
                self.photoOutput.isAppleProRAWEnabled = self.photoOutput.isAppleProRAWSupported
                if !self.photoOutput.isAppleProRAWEnabled {
                    DispatchQueue.main.async {
                        self.typeSegmentControl.removeSegment(at: 2, animated: true)
                    }
                }
            }
        } else {
            self.typeSegmentControl.removeAllSegments()
        }
    }
    
    
    /**
     @brief Capture photo
     */
    @IBAction func shutterButtonTUP(_ sender: Any) {
        self.shutterButton.isEnabled = false
        
        self.settingsForMonitoring = AVCapturePhotoSettings()
        
        switch self.typeSegmentControl.selectedSegmentIndex {
        // Photo
        case 0:
            self.settingsForMonitoring.embeddedThumbnailPhotoFormat = [AVVideoCodecKey : AVVideoCodecType.jpeg]
        
        // RAW
        case 1:
            guard let availableRawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first else { return }
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                self.settingsForMonitoring = AVCapturePhotoSettings(rawPixelFormatType: availableRawFormat,
                                                                    processedFormat: [AVVideoCodecKey : AVVideoCodecType.hevc])
            }
            
        // Apple ProRAW
        case 2:
            if #available(iOS 14.3, *) {
                let query = self.photoOutput.isAppleProRAWEnabled ?
                    { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) } :
                    { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
                
                guard let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first(where: query) else {
                    fatalError("No RAW format found.")
                }
                
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settingsForMonitoring = AVCapturePhotoSettings(rawPixelFormatType: rawFormat,
                                                                   processedFormat: [AVVideoCodecKey : AVVideoCodecType.hevc])
                }
            } else {
                return
            }
        
        default:
            return
        }
        
        self.settingsForMonitoring.isHighResolutionPhotoEnabled = false
        
        self.photoOutput.capturePhoto(with: self.settingsForMonitoring, delegate: self)
    }
    
    /**
     @brief Make unique url
     */
    func makeUniqueTempFileURL(extension type: String) -> URL {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let uniqueFilename = ProcessInfo.processInfo.globallyUniqueString
        let urlNoExt = temporaryDirectoryURL.appendingPathComponent(uniqueFilename)
        let url = urlNoExt.appendingPathExtension(type)
        return url
    }

}


extension CameraViewController: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        guard error == nil else {
            print("Error capturing photo: \(error!)")
            return
        }
        
        // Access the file data representation of this photo.
        guard let photoData = photo.fileDataRepresentation() else {
            print("No photo data to write.")
            return
        }
        
        if photo.isRawPhoto {
            self.rawImageFileURL = self.makeUniqueTempFileURL(extension: "dng")
            do {
                try photo.fileDataRepresentation()!.write(to: self.rawImageFileURL!)
            } catch {
                fatalError("couldn't write DNG file to URL")
            }
        } else {
            self.compressedData = photoData
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        
        guard error == nil else {
            self.shutterButton.isEnabled = true
            print("Error capturing photo: \(error!)")
            return
        }
        
        // Ensure the RAW and processed photo data exists.
        guard let compressedData = self.compressedData else {
            self.shutterButton.isEnabled = true
            print("The expected photo data isn't available.")
            return
        }
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: compressedData, options: nil)
                
                if let rawFileURL = self.rawImageFileURL {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    creationRequest.addResource(with: .alternatePhoto, fileURL: rawFileURL, options: options)
                }
                
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    self.shutterButton.isEnabled = true
                }
            }
        }
    }
    
}
