// Sharpening filter in Oklab color space 
//Performance is not optional
#include "ReShade.fxh"

uniform float SharpnessStrength <
    ui_label = "Sharpness Strength";
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
> = 0.5;

uniform int KernelSize <
    ui_label = "Kernel Size (1=3x3, 2=5x5)";
    ui_type = "slider";
    ui_min = 1;
    ui_max = 2;
> = 1;

// sRGB to linear conversion with safety for pow
float3 srgb_to_linear(float3 color)
{
    return lerp(
        color / 12.92,
        pow(max((color + 0.055) / 1.055, 0.0), 2.4),
        step(0.04045, color)
    );
}

// Linear to sRGB conversion with safety for pow
float3 linear_to_srgb(float3 color)
{
    return lerp(
        color * 12.92,
        1.055 * pow(max(color, 0.0), 1.0 / 2.4) - 0.055,
        step(0.0031308, color)
    );
}

// Optimized RGB to Oklab L-channel conversion
float rgb_to_oklab_L(float3 rgb)
{
    const float3x3 rgb_to_lms = float3x3(
        0.4122214708, 0.5363325363, 0.0514459929,
        0.2119034982, 0.6806995451, 0.1073969566,
        0.0883024619, 0.2817188376, 0.6299787005
    );
    
    float3 lms = mul(rgb_to_lms, rgb);
    lms = max(lms, 0.0); // Ensure non-negative before cube root
    lms = pow(lms, 1.0 / 3.0);
    return dot(float3(0.2104542553, 0.793617785, -0.0040720468), lms);
}

// Full RGB to Oklab conversion
float3 rgb_to_oklab(float3 rgb)
{
    const float3x3 rgb_to_lms = float3x3(
        0.4122214708, 0.5363325363, 0.0514459929,
        0.2119034982, 0.6806995451, 0.1073969566,
        0.0883024619, 0.2817188376, 0.6299787005
    );
    
    float3 lms = mul(rgb_to_lms, rgb);
    lms = max(lms, 0.0); // Ensure non-negative before cube root
    lms = pow(lms, 1.0 / 3.0);
    
    const float3x3 lms_to_oklab = float3x3(
        0.2104542553, 0.793617785, -0.0040720468,
        1.9779984951, -2.428592205, 0.4505937099,
        0.0259040371, 0.7827717662, -0.808675766
    );
    
    return mul(lms_to_oklab, lms);
}

// Oklab to RGB conversion
float3 oklab_to_rgb(float3 lab)
{
    const float3x3 oklab_to_lms = float3x3(
        1.0, 0.3963377774, 0.2158037573,
        1.0, -0.1055613458, -0.0638541728,
        1.0, -0.0894841775, -1.2914855480
    );
    
    float3 lms_prime = mul(oklab_to_lms, lab);
    float3 lms = lms_prime * lms_prime * lms_prime;
    
    const float3x3 lms_to_rgb = float3x3(
        4.0767416621, -3.3077115913, 0.2309699292,
        -1.2684380046, 2.6097574011, -0.3413193965,
        -0.0041960863, -0.7034186147, 1.7076147010
    );
    
    return mul(lms_to_rgb, lms);
}

void VS(uint id : SV_VertexID, out float4 pos : SV_Position, out float2 texcoord : TEXCOORD)
{
    PostProcessVS(id, pos, texcoord);
}

float4 PS(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 center_color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    center_color = srgb_to_linear(center_color);
    float3 center_lab = rgb_to_oklab(center_color);
    
    float blurred_L = 0.0;
    float weight_sum = 0.0;
    const float2 px = ReShade::PixelSize;
    
    static const float3 kernel3x3 = float3(0.0625, 0.125, 0.0625);
    static const float3 kernel5x5 = float3(0.00390625, 0.015625, 0.0234375);
    
    if (KernelSize == 1)
    {
        [unroll]
        for (int y = -1; y <= 1; y++)
        {
            [unroll]
            for (int x = -1; x <= 1; x++)
            {
                float weight = kernel3x3[abs(x)] * kernel3x3[abs(y)];
                float2 sampleCoord = texcoord + float2(x, y) * px;
                float3 sampleColor = tex2Dlod(ReShade::BackBuffer, float4(sampleCoord, 0, 0)).rgb;
                
                blurred_L += rgb_to_oklab_L(srgb_to_linear(sampleColor)) * weight;
                weight_sum += weight;
            }
        }
    }
    else
    {
        [unroll]
        for (int y = -2; y <= 2; y++)
        {
            [unroll]
            for (int x = -2; x <= 2; x++)
            {
                if (abs(x) == 2 && abs(y) == 2) continue;
                
                float weight = kernel5x5[abs(x)] * kernel5x5[abs(y)];
                float2 sampleCoord = texcoord + float2(x, y) * px;
                float3 sampleColor = tex2Dlod(ReShade::BackBuffer, float4(sampleCoord, 0, 0)).rgb;
                
                blurred_L += rgb_to_oklab_L(srgb_to_linear(sampleColor)) * weight;
                weight_sum += weight;
            }
        }
    }
    
    blurred_L /= weight_sum;
    
    float detail = center_lab.x - blurred_L;
    float sharp_L = clamp(center_lab.x + detail * SharpnessStrength, 0.0, 1.0);
    
    float3 sharp_lab = float3(sharp_L, center_lab.yz);
    float3 sharp_rgb = oklab_to_rgb(sharp_lab);
    
    return float4(linear_to_srgb(sharp_rgb), 1.0);
}

technique PerceptualOKlabSharpening
{
    pass
    {
        VertexShader = VS;
        PixelShader = PS;
    }
}
