import SwiftUI
import AVFoundation
import MetalKit

@main
struct CamProcApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .edgesIgnoringSafeArea(.all)
        }
    }
}

// MARK: - Texture Store
class TextureStore: ObservableObject {
    static let shared = TextureStore()

    @Published var latestTexture: MTLTexture?
    private var device: MTLDevice!
    private var isFirstFrame = true

    init() {
        device = MTLCreateSystemDefaultDevice()
    }

    func updateTexture(rawBayerArray: [UInt16], width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Uint, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("Failed to create texture")
            return
        }

        let bytesPerRow = width * MemoryLayout<UInt16>.size
        texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: rawBayerArray,
                        bytesPerRow: bytesPerRow)

        if isFirstFrame {
            isFirstFrame = false
            print("[DEBUG] Delaying first texture assignment")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.latestTexture = texture
            }
        } else {
            latestTexture = texture
        }
    }
}



// MARK: - ViewModel
class AppViewModel: ObservableObject {
    @Published var columns: Int = 2
    @Published var rows: Int = 2

    @Published var definedPipelines: [PipelineDefinition] = [
        PipelineDefinition(name: "Pipeline 1"),
        PipelineDefinition(name: "Pipeline 2")
    ]

    @Published var assignedPipelines: [UUID] = []

    init() {
        updatePipelineGrid()
    }

    func updatePipelineGrid() {
        let total = rows * columns
        while assignedPipelines.count < total {
            assignedPipelines.append(definedPipelines[assignedPipelines.count % definedPipelines.count].id)
        }
        assignedPipelines = Array(assignedPipelines.prefix(total))
    }

    func pipeline(for id: UUID) -> PipelineDefinition? {
        return definedPipelines.first { $0.id == id }
    }
}

struct PipelineDefinition: Identifiable {
    let id = UUID()
    var name: String
    var debayer: DebayerType = .bilinear
    var filter: FilterType = .none
    var output: OutputType = .image
}

enum DebayerType: String, CaseIterable, Identifiable {
    case bilinear, malvar
    var id: String { self.rawValue }
}

enum FilterType: String, CaseIterable, Identifiable {
    case none, edgeDetect
    var id: String { self.rawValue }
}

enum OutputType: String, CaseIterable, Identifiable {
    case image, histogram
    var id: String { self.rawValue }
}

// MARK: - Camera Manager (simplified for single exposure)
class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    static let shared = CameraManager()

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var camera: AVCaptureDevice?

    private override init() {
        super.init()
        setupCamera()
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        camera = device
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }

        captureSession.beginConfiguration()
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.canAddOutput(photoOutput) { captureSession.addOutput(photoOutput) }
        captureSession.sessionPreset = .photo
        captureSession.commitConfiguration()

        captureSession.startRunning()
    }

    func captureRAW() {
        guard let formatType = photoOutput.availableRawPhotoPixelFormatTypes.first else {
            print("RAW format not available")
            return
        }
        let settings = AVCapturePhotoSettings(rawPixelFormatType: formatType)
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        print("Captured RAW photo")
        guard let pixelBuffer = photo.pixelBuffer else {
            print("Failed to get pixel buffer")
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("Failed to get base address")
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let pixelData = baseAddress.assumingMemoryBound(to: UInt16.self)
        let count = bytesPerRow / MemoryLayout<UInt16>.size * height
        let rawBayerArray = Array(UnsafeBufferPointer(start: pixelData, count: count))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        print("Captured RAW: \(width)x\(height), pixels: \(rawBayerArray.prefix(10))")
        // Create a Metal texture from the raw data and update view model
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            TextureStore.shared.updateTexture(rawBayerArray: rawBayerArray, width: width, height: height)
        }

    }
}


// MARK: - Main View
struct MainView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        HStack(spacing: 0) {
            ViewportGrid(viewModel: viewModel)
                .frame(maxWidth: .infinity)

            Divider()

            ConfigPanel(viewModel: viewModel)
                .frame(width: 300)
                .background(Color(UIColor.systemGray6))
        }
    }
}

// MARK: - Viewport Grid
struct ViewportGrid: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / CGFloat(viewModel.columns)
            let cellHeight = geometry.size.height / CGFloat(viewModel.rows)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: viewModel.columns), spacing: 2) {
                ForEach(0..<viewModel.assignedPipelines.count, id: \ .self) { index in
                    if let pipeline = viewModel.pipeline(for: viewModel.assignedPipelines[index]) {
                        MetalViewport(pipeline: pipeline)
                            .frame(width: cellWidth, height: cellHeight)
                            .background(Color.black)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Metal Viewport with Texture
struct MetalViewport: View {
    let pipeline: PipelineDefinition
    @ObservedObject var textureStore = TextureStore.shared
    var body: some View {
        ZStack {
            if let texture = textureStore.latestTexture {
                MetalTextureView(texture: texture)
    } else {
        Color.black
    }
    VStack {
        Text(pipeline.name).foregroundColor(.white)
        Text("\(pipeline.debayer.rawValue) + \(pipeline.filter.rawValue) → \(pipeline.output.rawValue)")
            .font(.caption)
            .foregroundColor(.gray)
    }
}
        }
    }

// MARK: - Metal Texture View
struct MetalTextureView: UIViewRepresentable {
    var texture: MTLTexture

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        // Ensure view has size
        mtkView.frame = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        mtkView.drawableSize = CGSize(width: texture.width, height: texture.height)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        print("[DEBUG] updateUIView called")

        uiView.drawableSize = CGSize(width: texture.width, height: texture.height)

        DispatchQueue.main.async {
            guard let drawable = uiView.currentDrawable else {
                print("[DEBUG] No currentDrawable")
                return
            }

            guard
                let commandQueue = uiView.device?.makeCommandQueue(),
                let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("[DEBUG] Failed to create command queue/buffer")
                return
            }

            guard let computeFunction = try? uiView.device?.makeDefaultLibrary()?.makeFunction(name: "debayerBilinear"),
                  let computePipeline = try? uiView.device?.makeComputePipelineState(function: computeFunction) else {
                print("[DEBUG] Failed to create compute pipeline")
                return
            }

            let outputTexture = drawable.texture
            print("[DEBUG] Drawable texture size: \(outputTexture.width)x\(outputTexture.height)")
            print("[DEBUG] Input texture size: \(texture.width)x\(texture.height)")

            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("[DEBUG] Failed to create compute encoder")
                return
            }

            computeEncoder.setComputePipelineState(computePipeline)
            computeEncoder.setTexture(texture, index: 0)
            computeEncoder.setTexture(outputTexture, index: 1)

            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let threadGroups = MTLSize(width: (texture.width + 15) / 16,
                                       height: (texture.height + 15) / 16,
                                       depth: 1)

            print("[DEBUG] Dispatched threadgroups: \(threadGroups)")
            
            if uiView.drawableSize != CGSize(width: texture.width, height: texture.height) {
                print("[DEBUG] Adjusting drawableSize to match input texture")
                uiView.drawableSize = CGSize(width: texture.width, height: texture.height)
            }


            computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            computeEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()

            print("[DEBUG] Frame rendered")
        }
    }
}



// MARK: - Exposure Control + Configuration Panel
struct ConfigPanel: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configuration").font(.headline)

            Stepper("Columns: \(viewModel.columns)", value: $viewModel.columns, in: 1...4, onEditingChanged: { _ in
                viewModel.updatePipelineGrid()
            })

            Stepper("Rows: \(viewModel.rows)", value: $viewModel.rows, in: 1...4, onEditingChanged: { _ in
                viewModel.updatePipelineGrid()
            })

            Divider()

            Text("Defined Pipelines").font(.subheadline)
            ScrollView {
                ForEach($viewModel.definedPipelines) { $pipeline in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name", text: $pipeline.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Picker("Debayer", selection: $pipeline.debayer) {
                            ForEach(DebayerType.allCases) { type in
                                Text(type.rawValue.capitalized).tag(type)
                            }
                        }.pickerStyle(.segmented)

                        Picker("Filter", selection: $pipeline.filter) {
                            ForEach(FilterType.allCases) { type in
                                Text(type.rawValue.capitalized).tag(type)
                            }
                        }.pickerStyle(.segmented)

                        Picker("Output", selection: $pipeline.output) {
                            ForEach(OutputType.allCases) { type in
                                Text(type.rawValue.capitalized).tag(type)
                            }
                        }.pickerStyle(.segmented)

                        Divider()
                    }
                }
                Button("Add Pipeline") {
                    viewModel.definedPipelines.append(PipelineDefinition(name: "Pipeline \(viewModel.definedPipelines.count + 1)"))
                    viewModel.updatePipelineGrid()
                }.padding(.top)
            }
            Button("Trigger Exposure") {
                CameraManager.shared.captureRAW()
            }
            .padding(.vertical)

            Spacer()
        }.padding()
    }
}
