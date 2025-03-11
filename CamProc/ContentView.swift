//
//  ContentView.swift
//  CamProc
//
//  Created by rtf59354 on 10/03/2025.
//
import UIKit
import AVFoundation
import CoreImage

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    let captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
    }

    func setupCaptureSession() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let cameraInput = try? AVCaptureDeviceInput(device: camera) else {
            print("Failed to access camera.")
            return
        }

        captureSession.beginConfiguration()

        if captureSession.canAddInput(cameraInput) {
            captureSession.addInput(cameraInput)
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                     Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        captureSession.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        if let autoAdjustedImage = autoLevelAdjust(ciImage) {
            DispatchQueue.main.async {
                self.previewLayer.contents = autoAdjustedImage.cgImage
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }

    func autoLevelAdjust(_ inputImage: CIImage) -> UIImage? {
        let context = CIContext()
        let filters = inputImage.autoAdjustmentFilters()
        var outputImage = inputImage
        for filter in filters {
            filter.setValue(outputImage, forKey: kCIInputImageKey)
            if let filtered = filter.outputImage {
                outputImage = filtered
            }
        }
        if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
