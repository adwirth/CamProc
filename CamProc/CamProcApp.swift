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

struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RAWCaptureViewController {
        RAWCaptureViewController()
    }
    func updateUIViewController(_ uiViewController: RAWCaptureViewController, context: Context) {}
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
    private var cachedCGImage: CGImage?

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
        try? camera.lockForConfiguration()
        camera.exposureMode = .custom
        camera.whiteBalanceMode = .locked
        camera.focusMode = .locked
        camera.setExposureModeCustom(duration: CMTime(value: 1, timescale: 100), iso: 1000, completionHandler: nil)
        camera.setWhiteBalanceModeLocked(with: AVCaptureDevice.WhiteBalanceGains(redGain: 2.0, greenGain: 1.0, blueGain: 1.5), completionHandler: nil)
        camera.setFocusModeLocked(lensPosition: 0.5, completionHandler: nil)
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

        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            
            photoSettings.isAutoVirtualDeviceFusionEnabled = false // Disable extra processing
            photoSettings.flashMode = .off // Ensure flash is off
            
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        AudioServicesDisposeSystemSoundID(1108) // Dispose of the system shutter sound

        guard let dngData = photo.fileDataRepresentation() else {
            print("Failed to get DNG data.")
            return
        }

        if let (rawBayerData, width, height) = extractBayerFromDNG(dngData) {
            updateBayerImage(rawBayerData, width: width, height: height)
        }
    }
    
    func extractBayerFromDNG(_ dngData: Data) -> ([UInt16], Int, Int)? {
        guard let imageSource = CGImageSourceCreateWithData(dngData as CFData, nil) else {
            print("Failed to create image source.")
            return nil
        }
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("Failed to create CGImage from RAW.")
            return nil
        }
        let width = image.width
        let height = image.height
        guard let dataProvider = image.dataProvider else {
            print("Failed to get data provider.")
            return nil
        }
        guard let rawPixelData = dataProvider.data else {
            print("Failed to extract raw pixel data.")
            return nil
        }
        let pixelArray = CFDataGetBytePtr(rawPixelData)!.withMemoryRebound(to: UInt16.self, capacity: width * height) {
            Array(UnsafeBufferPointer(start: $0, count: width * height))
        }
        return (pixelArray, width, height)
    }
    
    func updateBayerImage(_ bayerData: [UInt16], width: Int, height: Int) {
        let bitsPerComponent = 16
        let bytesPerPixel = 2
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        if let providerRef = CGDataProvider(data: NSData(bytes: bayerData, length: bayerData.count * MemoryLayout<UInt16>.size)),
           let newCGImage = CGImage(width: width, height: height, bitsPerComponent: bitsPerComponent, bitsPerPixel: bytesPerPixel * 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: providerRef, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            
            cachedCGImage = newCGImage
            DispatchQueue.main.async {
                self.previewLayer.image = UIImage(cgImage: newCGImage)
            }
        }
    }
}
