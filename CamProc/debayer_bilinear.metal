#include <metal_stdlib>
using namespace metal;

kernel void debayerBilinear(texture2d<uint, access::read> inputTexture [[texture(0)]],
                            texture2d<float, access::write> outputTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {

    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();
    uint owidth = outputTexture.get_width();
    uint oheight = outputTexture.get_height();
    
    if ((gid.x >= owidth || gid.y >= oheight))  return;

    // Calculating input image coordinates
    float sc = float(width) / owidth;
    uint2 base = uint2((gid.x * sc) / 2 * 2, uint(gid.y * sc) / 2 * 2);
    if ((base.x >= width) || (base.y >= height))
        return;

    uint32_t pval[4][4];

    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            uint2 pixelIndex = uint2(base.x + x - 1, base.y + y - 1);
            pval[x][y] = inputTexture.read(pixelIndex).r;
            // tex2D<uint8_t>(source_tex, x + base.x - 1, y + base.y - 1);
        }
    }
    int2 shifts[4] = { {0, 0}, {0, 1}, {1, 0}, {1, 1} };

    float3 rgb = float3(0.0);
    int i = 0;
    int2 shift = shifts[i];
    int x = base.x + shift.x;
    int y = base.y + shift.y;
    const int2 center = int2(x, y);
    uint16_t r = 0, g = 0, b = 0;
    
    if (center.x % 2 == 0) {
        if (center.y % 2 == 0) {
            b = pval[shift.x + 1][shift.y + 1];
            g = uint16_t((pval[shift.x][shift.y + 1] +
                         pval[shift.x + 2][shift.y + 1] +
                         pval[shift.x + 1][shift.y] +
                         pval[shift.x + 1][shift.y + 2]) / 4);
            r = uint16_t((pval[shift.x][shift.y] +
                         pval[shift.x + 2][shift.y + 2] +
                         pval[shift.x + 2][shift.y] +
                         pval[shift.x][shift.y + 2]) / 4);
        } else {
            b = uint16_t((pval[shift.x + 1][shift.y] + pval[shift.x + 1][shift.y + 2]) / 2);
            g = pval[shift.x + 1][shift.y + 1];
            r = uint16_t((pval[shift.x][shift.y + 1] + pval[shift.x + 2][shift.y + 1]) / 2);
        }
    } else {
        if (center.y % 2 == 0) {
            b = uint16_t((pval[shift.x][shift.y + 1] + pval[shift.x + 2][shift.y + 1]) / 2);
            g = pval[shift.x + 1][shift.y + 1];
            r = uint16_t((pval[shift.x + 1][shift.y] + pval[shift.x + 1][shift.y + 2]) / 2);
        } else {
            r = pval[shift.x + 1][shift.y + 1];
            g = uint16_t((pval[shift.x][shift.y + 1] +
                         pval[shift.x + 2][shift.y + 1] +
                         pval[shift.x + 1][shift.y] +
                         pval[shift.x + 1][shift.y + 2]) / 4);
            b = uint16_t((pval[shift.x][shift.y] +
                         pval[shift.x + 2][shift.y + 2] +
                         pval[shift.x + 2][shift.y] +
                         pval[shift.x][shift.y + 2]) / 4);
        }
    }
    g *= 0.7;
    rgb = float3(b / 16384.0, g / 16384.0, r / 16384.0);
    uint border = 20;
    if ((gid.x+border) % owidth < border * 2)
        rgb = float3(1.f, 0.f, 0.f);
    if ((gid.y+border) % oheight < border * 2)
        rgb = float3(1.f, 0.f, 0.f);
    outputTexture.write(float4(rgb, 1.0), gid);
}
