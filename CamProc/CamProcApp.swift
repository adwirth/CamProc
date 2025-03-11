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
    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController()
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
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
            ciImage.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.0]),
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
