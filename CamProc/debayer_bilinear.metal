#include <metal_stdlib>
using namespace metal;

kernel void debayerBilinearOld(texture2d<uint, access::read> inputTexture [[texture(0)]],
                            texture2d<float, access::write> outputTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {

    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();
    uint owidth = outputTexture.get_width();
    uint oheight = outputTexture.get_height();
    
    if (/*(gid.x >= width || gid.y >= height)||*/(gid.x >= owidth || gid.y >= oheight))  return;

    // Scale pixel coordinates to avoid incorrect indexing
//    uint2 pixelIndex = uint2(min(width - 1, uint(gid.x * float(width) / owidth)), min(height - 1, uint(gid.y * float(width) / owidth)));
    float sc = float(width) / owidth;
    uint x = uint(gid.x * sc) / 2 * 2;
    uint y = uint(gid.y * sc) / 2 * 2;
    if ((x >= width) || (y >= height))
        return;
    uint2 pixelIndex = uint2(x, y);
    uint rawPixel = inputTexture.read(pixelIndex).r;

    bool isRed = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 0);
//    bool isGreen1 = (pixelIndex.x % 2 == 1) && (pixelIndex.y % 2 == 0);
//    bool isGreen2 = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 1);
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
//        rgb = float3(rawPixel / 655350.0, rawPixel / 655350.0, rawPixel / 655350.0);
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
//        rgb = float3(rawPixel / 655350., rawPixel / 655350.0, rawPixel / 655350.0);

    }
    uint border = 20;
    if ((gid.x+border) % owidth < border * 2)
        rgb = float3(1.f, 0.f, 0.f);
    if ((gid.y+border) % oheight < border * 2)
        rgb = float3(1.f, 0.f, 0.f);
    outputTexture.write(float4(rgb, 1.0), gid);
}


kernel void debayerBilinear(texture2d<uint, access::read> inputTexture [[texture(0)]],
                            texture2d<float, access::write> outputTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {

    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();
    uint owidth = outputTexture.get_width();
    uint oheight = outputTexture.get_height();
    
    if (/*(gid.x >= width || gid.y >= height)||*/(gid.x >= owidth || gid.y >= oheight))  return;

    // Scale pixel coordinates to avoid incorrect indexing
//    uint2 pixelIndex = uint2(min(width - 1, uint(gid.x * float(width) / owidth)), min(height - 1, uint(gid.y * float(width) / owidth)));
    float sc = float(width) / owidth;
    uint x = uint(gid.x * sc) / 2 * 2;
    uint y = uint(gid.y * sc) / 2 * 2;
    if ((x >= width) || (y >= height))
        return;
    uint2 pixelIndex = uint2(x, y);
    uint rawPixel = inputTexture.read(pixelIndex).r;

    bool isRed = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 0);
//    bool isGreen1 = (pixelIndex.x % 2 == 1) && (pixelIndex.y % 2 == 0);
//    bool isGreen2 = (pixelIndex.x % 2 == 0) && (pixelIndex.y % 2 == 1);
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
//        rgb = float3(rawPixel / 655350.0, rawPixel / 655350.0, rawPixel / 655350.0);
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
//        rgb = float3(rawPixel / 655350., rawPixel / 655350.0, rawPixel / 655350.0);

    }
    uint border = 20;
    if ((gid.x+border) % owidth < border * 2)
        rgb = float3(1.f, 0.f, 0.f);
    if ((gid.y+border) % oheight < border * 2)
        rgb = float3(1.f, 0.f, 0.f);
    outputTexture.write(float4(rgb, 1.0), gid);
}
