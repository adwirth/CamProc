import SwiftUI
import AVFoundation
import CoreImage
import Metal
import MetalKit

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

class RAWCaptureViewController: UIViewController, AVCapturePhotoCaptureDelegate, MTKViewDelegate {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var metalView: MTKView!
    private var metalDevice: MTLDevice!
    private var metalCommandQueue: MTLCommandQueue!
    private var metalPipeline: MTLComputePipelineState!
    private var metalTexture: MTLTexture?

    override func viewDidLoad() {
        super.viewDidLoad()

        setupSession()
        setupMetal()
        captureSession.startRunning()

        // Start continuous RAW capture
        captureRAWContinuously()
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

    func setupMetal() {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            print("Failed to create Metal device.")
            return
        }
        self.metalDevice = metalDevice
        self.metalCommandQueue = metalDevice.makeCommandQueue()
        
        // Set up Metal view with full drawable size
        metalView = MTKView(frame: view.bounds, device: metalDevice)
        metalView.contentMode = .scaleAspectFill
        metalView.framebufferOnly = false
        // Ensure drawable size matches screen dimensions
        let screenSize = UIScreen.main.bounds.size
        metalView.drawableSize = CGSize(width: screenSize.width, height: screenSize.height)

        metalView.delegate = self
        view.addSubview(metalView)

      
        // Load Metal shader
        do {
            let metalLibrary = metalDevice.makeDefaultLibrary()
            let kernelFunction = metalLibrary?.makeFunction(name: "debayerBilinear")
            self.metalPipeline = try metalDevice.makeComputePipelineState(function: kernelFunction!)
        } catch {
            print("Failed to create Metal pipeline: \(error.localizedDescription)")
        }
    }

    
    
    func captureRAWContinuously() {
        guard let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else {
            print("RAW capture unsupported.")
            return
        }

        Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let dngData = photo.fileDataRepresentation(),
              let (rawBayerData, width, height) = extractBayerFromDNG(dngData) else {
            print("Failed to extract Bayer data.")
            return
        }

        processWithMetal(rawBayerData, width: width, height: height)
    }
    
    func extractBayerFromDNG(_ dngData: Data) -> ([UInt16], Int, Int)? {
        guard let imageSource = CGImageSourceCreateWithData(dngData as CFData, nil) else {
            print("Failed to create image source.")
            return nil
        }

        // Extract metadata to get full sensor resolution
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            print("Failed to read DNG metadata.")
            return nil
        }

        guard let width = imageProperties[kCGImagePropertyPixelWidth] as? Int,
              let height = imageProperties[kCGImagePropertyPixelHeight] as? Int else {
            print("Failed to extract width and height from DNG metadata.")
            return nil
        }

        print("DNG Image Dimensions: \(width) x \(height)")

        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("Failed to create CGImage from RAW.")
            return nil
        }

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

    func processWithMetal(_ bayerData: [UInt16], width: Int, height: Int) {
        guard let texture = createTexture(from: bayerData, width: width, height: height) else {
            print("Failed to create Metal texture.")
            return
        }
        metalTexture = texture
        metalView.setNeedsDisplay()
    }

    func createTexture(from data: [UInt16], width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .r16Uint  // Ensure correct format
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        guard let texture = metalDevice.makeTexture(descriptor: descriptor) else {
            print("Failed to create Metal texture")
            return nil
        }

        let bytesPerRow = width * MemoryLayout<UInt16>.size

        texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: data,
                        bytesPerRow: bytesPerRow)

        return texture
    }

    func draw(in view: MTKView) {
        guard let currentDrawable = metalView.currentDrawable,
              let texture = metalTexture,
              let commandBuffer = metalCommandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        computeEncoder.setComputePipelineState(metalPipeline)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setTexture(currentDrawable.texture, index: 1)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(width: (texture.width + 15) / 16,
                                   height: (texture.height + 15) / 16,
                                   depth: 1)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)

        computeEncoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resizing if needed
    }
}
