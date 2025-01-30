#include "ReShade.fxh"
// By Liam Very Basic starting to get medium stuff

uniform int ColorSpace <
    ui_type = "combo";
    ui_items = "SRGB\0scRGB\0";
    ui_label = "Color Space";
> = 0;
uniform float MidGray <
    ui_type = "slider";
    ui_min = 0.14;
    ui_max = 0.28;
    ui_step = 0.01;
	hidden = true;
> = 0.18;
uniform float Contrast <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
> = 0.8;
uniform float Exp <
    ui_type = "slider";
    ui_min = 0.1;
    ui_max = 0.4;
    ui_step = 0.01;
> = 0.26;

uniform float HDR <
    ui_label = "Lower value is closer to HDR";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 4.0;
    ui_step = 0.01;
> = 2.0;
uniform float Vibrance <
    ui_type = "slider";
    ui_label = "Vibrance";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
    ui_tooltip = "Intelligent saturation boost for mid-chroma colors";
> = 1.3;
uniform float ShadowSaturation <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
	hidden = true;
> = 1.0;
uniform float HighlightSaturation <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
	hidden = true;
> = 1.0;
uniform float Saturation <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
    ui_label = "Global Saturation";
	hidden = true;
> = 1.0;
uniform float ShadowsBrightness <
    ui_type = "slider";
    ui_min = 0.8;
    ui_max = 1.2;
    ui_step = 0.01;
    hidden = true;
> = 1.0;
uniform float HighlightBrightness <
    ui_type = "slider";
    ui_min = 0.8;
    ui_max = 1.2;
    ui_step = 0.01;
    ui_label = "Highlight Brightness";
> = 1.0;
float3 SRGBToLinear(float3 color)
{
    return color < 0.04045 ? color / 12.92 : pow((color + 0.055)/1.055, 2.4);
}

float3 LinearToSRGB(float3 color)
{
    return color < 0.0031308 ? 12.92 * color : 1.055 * pow(color, 1.0/2.4) - 0.055;
}

float3 RGBToOKLab(float3 rgb)
{
    float3 lms;
    lms.x = 0.4122214708 * rgb.x + 0.5363325363 * rgb.y + 0.0514459929 * rgb.z;
    lms.y = 0.2119034982 * rgb.x + 0.6806995451 * rgb.y + 0.1073969566 * rgb.z;
    lms.z = 0.0883024619 * rgb.x + 0.2817188376 * rgb.y + 0.6299787005 * rgb.z;
    
    lms = pow(lms, 1.0/3.0);
    
    float3 lab;
    lab.x = 0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z;
    lab.y = 1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z;
    lab.z = 0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z;
    
    return lab;
}

float3 OKLabToRGB(float3 lab)
{
    float3 lms_;
    lms_.x = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
    lms_.y = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
    lms_.z = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
    
    float3 lms = lms_ * lms_ * lms_;
    
    float3 rgb;
    rgb.x =  4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z;
    rgb.y = -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z;
    rgb.z = -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z;
    
    return rgb;
}

float3 ApplyReinhardToOKLab(float3 lab, float midGray)
{
    float Y = lab.x;
    float scaledY = Y * Exp;
    float Yd = (scaledY * (1.0 + scaledY/(midGray*midGray))) / (1.0 + scaledY);
    
    Yd = pow(Yd, Contrast);
    lab.x = Yd;
    return lab;
}

float3 AdaptiveAdjustments(float3 oklab)
{
    // Expanded transition range for better midtone handling
    float t = smoothstep(0.15, 0.85, oklab.x);
    float satFactor = lerp(ShadowSaturation, HighlightSaturation, t) * Saturation;
    float brightness = lerp(ShadowsBrightness, HighlightBrightness, t);

    // Chroma processing with dual compensation
    float chroma = length(oklab.yz);
    if (chroma > 1e-5)
    {
        // Vibrance-enhanced compression curve
        float chromaBias = 1.0 + (Vibrance - 1.0) * (1.0 - smoothstep(0.1, 0.4, chroma));
        float compressedChroma = (chroma * satFactor * chromaBias) / (0.8 + chroma);
        
        // Warmth preservation for neutrals
        float warmth = 1.0 + 0.1 * (Vibrance - 1.0) * (1.0 - chroma);
        oklab.yz *= compressedChroma / chroma * float2(warmth, 1.0);
    }
    
    // Lightness-preserving brightness adjustment
    oklab.x = pow(oklab.x * brightness, 1.0 + 0.2 * (1.0 - Vibrance));

    return oklab;
}

float4 PS_PerceptualReinhard(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 color = tex2D(ReShade::BackBuffer, uv);
    
    // Convert to linear RGB
    if (ColorSpace == 0)
        color.rgb = SRGBToLinear(color.rgb);

    // Convert to OKLab and apply Reinhard
    float3 lab = RGBToOKLab(color.rgb);
    lab = ApplyReinhardToOKLab(lab, MidGray);
    
    // Adjust saturation and brightness in OKLab using lightness channel
    lab = AdaptiveAdjustments(lab);
    color.rgb = OKLabToRGB(lab);

    
    color.rgb /= (1.0 + color.rgb); //Using Simple Reinhard to contains highlights 
    color.rgb = HDR * color.rgb / max(HDR - color.rgb, 1e-5); // Using Inverse Simple Reinhard to controll highlights 

    // Convert back to original color space
    if (ColorSpace == 0)
        color.rgb = LinearToSRGB(color.rgb);
    
    return color;
}

technique Perceptual_Reinhard_OKLab
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_PerceptualReinhard;
    }
}
