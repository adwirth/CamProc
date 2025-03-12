import SwiftUI
import AVFoundation
import CoreImage

@main
struct CamProcApp: App {
    var body: some Scene {
        WindowGroup {
            CameraView()
                .edgesIgnoringSafeArea(.all)
        }
    }
}

//struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
//    func makeUIViewController(context: Context) -> CameraViewController {
//        CameraViewController()
//    }
//    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
//}
//

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RAWCaptureViewController {
        RAWCaptureViewController()
    }
    func updateUIViewController(_ uiViewController: RAWCaptureViewController, context: Context) {}
}

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayers: [CALayer] = [CALayer(), CALayer(), CALayer(), CALayer()]
    private let ciContext = CIContext()

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }

        captureSession.beginConfiguration()

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                     Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()

        previewLayers.forEach { layer in
            layer.contentsGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
        }

        captureSession.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let halfWidth = view.bounds.width / 2
        let halfHeight = view.bounds.height / 2

        previewLayers[0].frame = CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight)
        previewLayers[1].frame = CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight)
        previewLayers[2].frame = CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight)
        previewLayers[3].frame = CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let adjustments: [CIImage?] = [
            ciImage,
            ciImage.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 2.0]),
            ciImage.applyingFilter("CIColorControls", parameters: ["inputContrast": 1.5]),
            applyAutoEnhance(to: ciImage)
        ]

        DispatchQueue.main.async {
            for (layer, image) in zip(self.previewLayers, adjustments) {
                if let cgImage = self.ciContext.createCGImage(image ?? ciImage, from: ciImage.extent) {
                    layer.contents = cgImage
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }

    private func applyAutoEnhance(to image: CIImage) -> CIImage? {
        let filters = image.autoAdjustmentFilters()
        var enhancedImage = image
        for filter in filters {
            filter.setValue(enhancedImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                enhancedImage = output
            }
        }
        return enhancedImage
    }
}

struct CameraView: View {
    var body: some View {
        CameraViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}

class RAWCaptureViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: UIImageView!
    private let ciContext = CIContext()
    private var captureTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()

        setupSession()
        setupPreview()
        captureSession.startRunning()

        // Start continuous capture
        captureRAWContinuously()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureTimer?.invalidate()
    }

    func setupSession() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input),
              captureSession.canAddOutput(photoOutput) else {
            print("Unable to configure session.")
            return
        }
//        guard let camera = AVCaptureDevice.default(for: .video) else { return }
        try? camera.lockForConfiguration()
        camera.exposureMode = .custom
        camera.whiteBalanceMode = .locked
        camera.focusMode = .locked
        camera.setExposureModeCustom(duration: CMTime(value: 1, timescale: 100), iso: 1000, completionHandler: nil)
        camera.setWhiteBalanceModeLocked(with: AVCaptureDevice.WhiteBalanceGains(redGain: 2.0, greenGain: 1.0, blueGain: 1.5), completionHandler: nil)
        camera.setFocusModeLocked(lensPosition: 0.5, completionHandler: nil) // 0.0 = close, 1.0 = infinity
        camera.unlockForConfiguration()



        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        captureSession.addInput(input)
        captureSession.addOutput(photoOutput)
        captureSession.commitConfiguration()
    }

    func setupPreview() {
        previewLayer = UIImageView(frame: view.bounds)
        previewLayer.contentMode = .scaleAspectFill
        view.addSubview(previewLayer)
    }

    func captureRAWContinuously() {
        guard let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else {
            print("RAW capture unsupported.")
            return
        }

        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            
            if #available(iOS 16.0, *), let camera = AVCaptureDevice.default(for: .video) {
                let supportedSizes = camera.activeFormat.supportedMaxPhotoDimensions
                if let closestSize = supportedSizes.min(by: { abs($0.width - 1920) < abs($1.width - 1920) }) {
                    photoSettings.maxPhotoDimensions = closestSize
                }
            }
            
            photoSettings.isAutoVirtualDeviceFusionEnabled = false // Disable extra processing
            photoSettings.flashMode = .off // Ensure flash is off
            
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    // Suppress the camera shutter sound
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        AudioServicesDisposeSystemSoundID(1108) // Dispose of the system shutter sound
    }

    // Delegate for RAW capture
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { photoOutput.maxPhotoQualityPrioritization = .balanced } // Release resources

        guard let dngData = photo.fileDataRepresentation(),
              let ciRawFilter = CIFilter(imageData: dngData, options: [CIRAWFilterOption.allowDraftMode: true]),
              let outputImage = ciRawFilter.outputImage else {
            // print("Failed RAW processing.")
            return
        }

        // Downscaling for performance
        // let scaleFactor: CGFloat = 0.1
        let scaledImage = outputImage //.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let cgImage = self.ciContext.createCGImage(scaledImage, from: scaledImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)

                DispatchQueue.main.async {
                    self.previewLayer.image = uiImage
                }
            }
        }
    }
}
