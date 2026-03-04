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
