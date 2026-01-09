#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 mvp;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texcoord;
    float4 color;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    out.texcoord = in.texcoord;
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> tex [[texture(0)]],
                               sampler smp [[sampler(0)]]) {
    float4 texColor = tex.sample(smp, in.texcoord);
    return texColor * in.color;
}
