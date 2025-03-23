# CamProcApp

CamProcApp is an iOS application that captures and processes raw Bayer images from the camera in real time, utilizing Metal for efficient GPU-based debayering and display. This project is designed to experiment with low-level camera image acquisition and processing while maintaining high performance.

## Features

- **Direct RAW Capture**: Uses `AVCapturePhotoOutput` with `CVPixelBuffer` to acquire unprocessed camera data.
- **Bayer Processing**: Implements custom **bilinear debayering** using a **Metal compute shader**.
- **High Performance Rendering**: Uses `CVMetalTextureCache` for efficient GPU-based texture handling.
- **Manual Exposure & White Balance**: Allows for full control over image processing and color correction.
- **Optimized for iPads & iPhones**: Designed for real-time performance on modern Apple hardware.

## Setup

### Prerequisites
- macOS with Xcode installed
- An iOS device running iOS 16 or later with a RAW-capable camera
- An Apple Developer account (for deployment to physical devices)

### Installation
1. Clone the repository:
   ```sh
   git clone https://github.com/adwirth/CamProcApp.git
   cd CamProcApp
   ```
2. Open `CamProcApp.xcodeproj` in Xcode.
3. Connect an iOS device and enable **Developer Mode**.
4. Build and run the project on a real device (RAW capture does not work in the iOS simulator).

## Technical Overview

### Image Capture
- Uses `AVCapturePhotoOutput` to obtain `CVPixelBuffer` directly from the camera sensor.
- Processes **14-bit or 16-bit Bayer RAW data** into `MTLTexture` for GPU-based processing.

### Debayering Pipeline
- The Metal compute shader extracts **Red, Green, and Blue channels** using bilinear interpolation.
- Supports **multiple Bayer patterns** (RGGB, BGGR, GBRG, GRBG) for device compatibility.
- Applies optional **white balance and gamma correction** for color accuracy.

### Performance Optimizations
- **GPU Acceleration**: Metal compute shaders handle Bayer-to-RGB conversion efficiently.
- **Direct Texture Binding**: Uses `CVMetalTextureCache` to avoid unnecessary CPU overhead.
- **Adaptive Scaling**: Resizes the image dynamically to match display resolution while retaining detail.

## Usage

### Adjusting Camera Settings
Modify `setupSession()` in `RAWCaptureViewController.swift` to enable or disable manual settings:
```swift
try? camera.lockForConfiguration()
camera.exposureMode = .custom
camera.setExposureModeCustom(duration: CMTime(value: 1, timescale: 100), iso: 100, completionHandler: nil)
camera.whiteBalanceMode = .locked
camera.unlockForConfiguration()
```

### Debugging Bayer Patterns
To identify the correct Bayer pattern for your device, use the **debug shader**:
```metal
if (isRed) rgb = float3(1.0, 0.0, 0.0);
if (isGreen1 || isGreen2) rgb = float3(0.0, 1.0, 0.0);
if (isBlue) rgb = float3(0.0, 0.0, 1.0);
```

## Roadmap
- [ ] Support additional debayering algorithms (e.g., **Malvar-He-Cutler interpolation**)
- [ ] Implement real-time **HDR tone mapping**
- [ ] Add Metal-based **denoising filters** for low-light improvement
- [ ] Expose manual controls in a UI for dynamic tuning

## Contributing
Pull requests and feature suggestions are welcome! Please open an issue for discussions or bug reports.

## License
This project is licensed under the **MIT License**.
