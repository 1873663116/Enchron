#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float3x3 colorMatrix;
};

vertex VertexOut video_vertex(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    const float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 video_fragment(VertexOut in [[stage_in]],
                               texture2d<float> textureY [[texture(0)]],
                               texture2d<float> textureUV [[texture(1)]],
                               constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    
    float y = textureY.sample(s, in.texCoord).r - 0.0625; // Approximate 16/256
    float2 uv = textureUV.sample(s, in.texCoord).rg - 0.5;
    
    float3 rgb = uniforms.colorMatrix * float3(y, uv.x, uv.y);
    return float4(rgb, 1.0);
}

fragment float4 video_fragment_bgra(VertexOut in [[stage_in]],
                                   texture2d<float> texture [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    return texture.sample(s, in.texCoord);
}

// --- Fisheye → Equirectangular Remap ---

struct FisheyeUniforms {
    float fovRadiusRadians;
};

kernel void fisheye_remap(
    texture2d<float, access::sample> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant FisheyeUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;

    float outU = (float(gid.x) + 0.5) / float(outTexture.get_width());
    float outV = (float(gid.y) + 0.5) / float(outTexture.get_height());

    // Equirectangular UV → spherical coordinates
    float longitude = (outU - 0.5) * 2.0 * M_PI_F;
    float latitude = (0.5 - outV) * M_PI_F;

    float cosLat = cos(latitude);
    float x = cosLat * sin(longitude);
    float y = sin(latitude);
    float z = cosLat * cos(longitude);

    // Angle from optical axis (+Z)
    float theta = acos(clamp(z, -1.0f, 1.0f));

    if (theta > uniforms.fovRadiusRadians) {
        outTexture.write(float4(0, 0, 0, 1), gid);
        return;
    }

    // Equidistant fisheye projection: r proportional to theta
    float r = (theta / uniforms.fovRadiusRadians) * 0.5;
    float phi = atan2(y, x);

    float fishU = 0.5 + r * cos(phi);
    float fishV = 0.5 + r * sin(phi);

    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = inTexture.sample(s, float2(fishU, fishV));
    outTexture.write(color, gid);
}
