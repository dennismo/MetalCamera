#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position [[position]];
    float2 text_coord;
};

struct TwoInputVertex
{
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
    float2 textureCoordinate2 [[user(texturecoord2)]];
};

struct Uniforms {
    float4x4 scaleMatrix;
};

vertex Vertex vertex_render_target(constant Vertex *vertexes [[ buffer(0) ]],
                                   constant Uniforms &uniforms [[ buffer(1) ]],
                                   uint vid [[vertex_id]])
{
    Vertex out = vertexes[vid];
    out.position = uniforms.scaleMatrix * out.position;// * in.position;
    return out;
};

vertex TwoInputVertex two_vertex_render_target(const device packed_float2 *position [[buffer(0)]],
                                               const device packed_float2 *texturecoord [[buffer(1)]],
                                               const device packed_float2 *texturecoord2 [[buffer(2)]],
                                               uint vid [[vertex_id]]) {
    TwoInputVertex outputVertices;
    outputVertices.position = float4(position[vid], 0, 1.0);
    outputVertices.textureCoordinate = texturecoord[vid];
    outputVertices.textureCoordinate2 = texturecoord2[vid];
    return outputVertices;
};


fragment float4 fragment_render_target(Vertex vertex_data [[ stage_in ]],
                                       texture2d<float> tex2d [[ texture(0) ]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 color = float4(tex2d.sample(textureSampler, vertex_data.text_coord));
    return color;
};

fragment float4 gray_fragment_render_target(Vertex vertex_data [[ stage_in ]],
                                            texture2d<float> tex2d [[ texture(0) ]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 color = float4(tex2d.sample(textureSampler, vertex_data.text_coord));
    if (color[3] == 0){
        return float4(0, 0, 0, 0);
    }
    float gray = (color[0] + color[1] + color[2])/3;
    return float4(gray, gray, gray, 1.0);
};

typedef struct
{
    float mixturePercent;
} AlphaBlendUniform;

fragment half4 alphaBlendFragment(TwoInputVertex fragmentInput [[stage_in]],
                                  texture2d<half> inputTexture [[texture(0)]],
                                  texture2d<half> inputTexture2 [[texture(1)]],
                                  constant AlphaBlendUniform& uniform [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    half4 textureColor = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    constexpr sampler quadSampler2;
    half4 textureColor2 = inputTexture2.sample(quadSampler, fragmentInput.textureCoordinate2);

    return half4(mix(textureColor.rgb, textureColor2.rgb, textureColor2.a * half(uniform.mixturePercent)), textureColor.a);
}

fragment half4 backgroundFragment(TwoInputVertex fragmentInput [[stage_in]],
                            texture2d<half> inputTexture [[texture(0)]],
                            texture2d<half> inputTexture2 [[texture(1)]])
{
    constexpr sampler quadSampler;
    half4 textureColor = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    constexpr sampler quadSampler2;
    half4 textureColor2 = inputTexture2.sample(quadSampler, fragmentInput.textureCoordinate2);
    
    if(textureColor.a > 0) {
        return textureColor;
    } else {
        return textureColor2;
    }
}

fragment half4 maskFragment(TwoInputVertex fragmentInput [[stage_in]],
                            texture2d<half> inputTexture [[texture(0)]],
                            texture2d<half> inputTexture2 [[texture(1)]])
{
    constexpr sampler quadSampler;
    half4 textureColor = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    constexpr sampler quadSampler2;
    half4 textureColor2 = inputTexture2.sample(quadSampler, fragmentInput.textureCoordinate2);
    
    if(textureColor2.a > 0) {
        return textureColor;
    } else {
        return half4(0, 0, 0 ,0);
    }

    if(textureColor2.r + textureColor2.g + textureColor2.b > 0) {
        return textureColor;
    } else {
        return half4(0, 0, 0 ,0);
    }
}

typedef struct
{
    int32_t classNum;
} SegmentationValue;

typedef struct
{
    int32_t targetClass;
    int32_t width;
    int32_t height;
} SegmentationUniform;

fragment float4 segmentation_render_target(Vertex vertex_data [[ stage_in ]],
                                           constant SegmentationValue *segmentation [[ buffer(0) ]],
                                           constant SegmentationUniform& uniform [[ buffer(1) ]])

{
    int index = int(vertex_data.position.x) + int(vertex_data.position.y) * uniform.width;
    if(segmentation[index].classNum == uniform.targetClass) {
        return float4(1.0, 0, 0, 1.0);
    }

    return float4(0,0,0,1.0);
};

fragment float4 crop_background_render_target(Vertex vertex_data [[ stage_in ]],
                                           constant SegmentationValue *segmentation [[ buffer(0) ]],
                                           constant SegmentationUniform& uniform [[ buffer(1) ]])

{
    int index = int(vertex_data.position.x) + int(vertex_data.position.y) * uniform.width;
    if(segmentation[index].classNum == 0) {
        return float4(0, 0, 0, 0);
    }

    return float4(0,0,0,1.0);
};



fragment half4 lookupFragment(TwoInputVertex fragmentInput [[stage_in]],
                              texture2d<half> inputTexture [[texture(0)]],
                              texture2d<half> inputTexture2 [[texture(1)]],
                              constant float& intensity [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    half4 base = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);

    half blueColor = base.b * 63.0h;

    half2 quad1;
    quad1.y = floor(floor(blueColor) / 8.0h);
    quad1.x = floor(blueColor) - (quad1.y * 8.0h);

    half2 quad2;
    quad2.y = floor(ceil(blueColor) / 8.0h);
    quad2.x = ceil(blueColor) - (quad2.y * 8.0h);

    float2 texPos1;
    texPos1.x = (quad1.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
    texPos1.y = (quad1.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

    float2 texPos2;
    texPos2.x = (quad2.x * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.r);
    texPos2.y = (quad2.y * 0.125) + 0.5/512.0 + ((0.125 - 1.0/512.0) * base.g);

    constexpr sampler quadSampler3;
    half4 newColor1 = inputTexture2.sample(quadSampler3, texPos1);
    constexpr sampler quadSampler4;
    half4 newColor2 = inputTexture2.sample(quadSampler4, texPos2);

    half4 newColor = mix(newColor1, newColor2, fract(blueColor));

    return half4(mix(base, half4(newColor.rgb, base.w), half(intensity)));
}

// MARK: Hue
// Hue Constants
constant half4 kRGBToYPrime = half4(0.299, 0.587, 0.114, 0.0);
constant half4 kRGBToI = half4(0.595716, -0.274453, -0.321263, 0.0);
constant half4 kRGBToQ = half4(0.211456, -0.522591, 0.31135, 0.0);

constant half4 kYIQToR = half4(1.0, 0.9563, 0.6210, 0.0);
constant half4 kYIQToG = half4(1.0, -0.2721, -0.6474, 0.0);
constant half4 kYIQToB = half4(1.0, -1.1070, 1.7046, 0.0);

typedef struct
{
    float hue;
} HueUniform;

fragment half4 hueFragment(Vertex fragmentInput [[stage_in]],
                             texture2d<half> inputTexture [[texture(0)]])
//                             constant HueUniform& uniform [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.text_coord);
    
    // Convert to YIQ
    float YPrime = dot (color, kRGBToYPrime);
    float I = dot (color, kRGBToI);
    float Q = dot (color, kRGBToQ);
    
    // Calculate the hue and chroma
    float hue = atan2(Q, I);
    float chroma = sqrt(I * I + Q * Q);
    
    // Make the user's adjustments
//    hue += (-uniform.hue); //why negative rotation?
    hue += (-90.0);
    
    // Convert back to YIQ
    Q = chroma * sin (hue);
    I = chroma * cos (hue);
    
    // Convert back to RGB
    half4 yIQ = half4(YPrime, I, Q, 0.0);
    color.r = dot(yIQ, kYIQToR);
    color.g = dot(yIQ, kYIQToG);
    color.b = dot(yIQ, kYIQToB);
    
    // Return result
    return color;
}

