//
//  CamProcApp.swift
//  CamProc
//
//  Created by rtf59354 on 10/03/2025.
//

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
    private var previewLayer = CALayer()
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

        previewLayer.contentsGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        captureSession.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard let adjustedImage = autoLevelAdjust(ciImage) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }

        DispatchQueue.main.async {
            self.previewLayer.contents = adjustedImage.cgImage
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }

    private func autoLevelAdjust(_ image: CIImage) -> UIImage? {
        let filters = image.autoAdjustmentFilters()
        var adjustedImage = image

        for filter in filters {
            filter.setValue(adjustedImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                adjustedImage = output
            }
        }

        if let cgImage = ciContext.createCGImage(adjustedImage, from: adjustedImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

struct CameraView: View {
    var body: some View {
        CameraViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}
