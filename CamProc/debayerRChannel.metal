#include <metal_stdlib>
using namespace metal;

kernel void debayerRChannel(texture2d<uint, access::read> inputTexture [[texture(0)]],
                            texture2d<float, access::write> outputTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }

    uint rawValue = inputTexture.read(gid).r;

    // Normalize 16-bit unsigned integer to [0,1] float range
    float normalizedValue = float(rawValue) / 65535.0;

    // Apply the R channel to all pixels
    float3 rgb = float3(normalizedValue, normalizedValue, normalizedValue);

    outputTexture.write(float4(rgb, 1.0), gid);
}
