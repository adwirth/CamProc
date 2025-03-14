//#include <metal_stdlib>
//using namespace metal;
//
//kernel void debayerBilinear(texture2d<uint, access::read> inputTexture [[texture(0)]],
//                            texture2d<float, access::write> outputTexture [[texture(1)]],
//                            uint2 gid [[thread_position_in_grid]]) {
//
//    uint width = inputTexture.get_width();
//    uint height = inputTexture.get_height();
//    
//    if (gid.x >= width || gid.y >= height) return;
//
//    // Correct index calculation to prevent misaligned reads
//    uint2 pixelIndex = uint2(gid.x, gid.y);
//
//    uint rawPixel = inputTexture.read(pixelIndex).r;
//
//    bool isRed = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 0);
//    bool isGreen1 = (pixelIndex.x % 2 == 1) && (pixelIndex.y % 2 == 0);
//    bool isGreen2 = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 1);
//    bool isBlue = (pixelIndex.x % 2 == 1) && (pixelIndex.y % 2 == 1);
//
//    float3 rgb = float3(0.0);
//
//    if (isRed) {
//        float green = (inputTexture.read(uint2(pixelIndex.x, max(uint(0), pixelIndex.y - 1))).r +
//                       inputTexture.read(uint2(pixelIndex.x, min(height - 1, pixelIndex.y + 1))).r +
//                       inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), pixelIndex.y)).r +
//                       inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), pixelIndex.y)).r) / 4.0;
//        
//        float blue = (inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), max(uint(0), pixelIndex.y - 1))).r +
//                      inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), max(uint(0), pixelIndex.y - 1))).r +
//                      inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), min(height - 1, pixelIndex.y + 1))).r +
//                      inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), min(height - 1, pixelIndex.y + 1))).r) / 4.0;
//        
//        rgb = float3(rawPixel / 65535.0, green / 65535.0, blue / 65535.0);
//    }
//    else if (isBlue) {
//        float red = (inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), max(uint(0), pixelIndex.y - 1))).r +
//                     inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), max(uint(0), pixelIndex.y - 1))).r +
//                     inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), min(height - 1, pixelIndex.y + 1))).r +
//                     inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), min(height - 1, pixelIndex.y + 1))).r) / 4.0;
//        
//        float green = (inputTexture.read(uint2(pixelIndex.x, max(uint(0), pixelIndex.y - 1))).r +
//                       inputTexture.read(uint2(pixelIndex.x, min(height - 1, pixelIndex.y + 1))).r +
//                       inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), pixelIndex.y)).r +
//                       inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), pixelIndex.y)).r) / 4.0;
//
//        rgb = float3(red / 65535.0, green / 65535.0, rawPixel / 65535.0);
//    }
//    else {
//        float green = rawPixel / 65535.0;
//        float red = (inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), pixelIndex.y)).r +
//                     inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), pixelIndex.y)).r) / 2.0 / 65535.0;
//        float blue = (inputTexture.read(uint2(pixelIndex.x, max(uint(0), pixelIndex.y - 1))).r +
//                      inputTexture.read(uint2(pixelIndex.x, min(height - 1, pixelIndex.y + 1))).r) / 2.0 / 65535.0;
//
//        rgb = float3(red, green, blue);
//    }
//
//    outputTexture.write(float4(rgb, 1.0), gid);
//}
//    


#include <metal_stdlib>
using namespace metal;

kernel void debayerBilinear(texture2d<uint, access::read> inputTexture [[texture(0)]],
                            texture2d<float, access::write> outputTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {

    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) return;

    // Scale pixel coordinates to avoid incorrect indexing
    uint2 pixelIndex = uint2(min(width - 1, gid.x), min(height - 1, gid.y));

    uint rawPixel = inputTexture.read(pixelIndex).r;

    bool isRed = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 0);
    bool isGreen1 = (pixelIndex.x % 2 == 1) && (pixelIndex.y % 2 == 0);
    bool isGreen2 = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 1);
    bool isBlue = (pixelIndex.x % 2 == 1) && (pixelIndex.y % 2 == 1);

    float3 rgb = float3(0.0);

    if (isRed) {
        float green = (inputTexture.read(uint2(pixelIndex.x, max(uint(0), pixelIndex.y - 1))).r +
                       inputTexture.read(uint2(pixelIndex.x, min(height - 1, pixelIndex.y + 1))).r +
                       inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), pixelIndex.y)).r +
                       inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), pixelIndex.y)).r) / 4.0;
        
        float blue = (inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), max(uint(0), pixelIndex.y - 1))).r +
                      inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), max(uint(0), pixelIndex.y - 1))).r +
                      inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), min(height - 1, pixelIndex.y + 1))).r +
                      inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), min(height - 1, pixelIndex.y + 1))).r) / 4.0;
        
        rgb = float3(rawPixel / 65535.0, green / 65535.0, blue / 65535.0);
    }
    else if (isBlue) {
        float red = (inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), max(uint(0), pixelIndex.y - 1))).r +
                     inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), max(uint(0), pixelIndex.y - 1))).r +
                     inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), min(height - 1, pixelIndex.y + 1))).r +
                     inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), min(height - 1, pixelIndex.y + 1))).r) / 4.0;
        
        float green = (inputTexture.read(uint2(pixelIndex.x, max(uint(0), pixelIndex.y - 1))).r +
                       inputTexture.read(uint2(pixelIndex.x, min(height - 1, pixelIndex.y + 1))).r +
                       inputTexture.read(uint2(max(uint(0), pixelIndex.x - 1), pixelIndex.y)).r +
                       inputTexture.read(uint2(min(width - 1, pixelIndex.x + 1), pixelIndex.y)).r) / 4.0;

        rgb = float3(red / 65535.0, green / 65535.0, rawPixel / 65535.0);
    }
    bool on;
    if ((((pixelIndex.x) % (width/4)) < 4) || (((pixelIndex.y) % (height/4)) < 4))
    {
        on = true;
    }
    else
    {
        on = false;
    }
    rgb = float3(on, on , on);
    outputTexture.write(float4(rgb, 1.0), gid);
}
