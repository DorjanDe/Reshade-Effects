#include "ReShade.fxh"
// By Liam Very Basic starting to get medium stuff

uniform int ColorSpace <
    ui_type = "combo";
    ui_items = "SRGB_SDR\0scRGB_HDR\0";
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
    ui_min = 0.2;
    ui_max = 0.32;
    ui_step = 0.01;
> = 0.26;

uniform float HDR <
    ui_label = "Lower is closer to HDR useful for both hdr/sdr";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 4.0;
    ui_step = 0.01;
> = 3.5;
uniform float Vibrance <
    ui_type = "slider";
    ui_label = "Vibrance";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
    ui_tooltip = "Saturation boost for entire screen";
> = 1.0;
uniform float ShadowSaturation <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
	hidden = true;
> = 1.0;
uniform float HighlightSaturation <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
	ui_tooltip = "Saturation boost only for highlight,ignores dark colors";
	
> = 1.0;
uniform float HighlightExposure <
   ui_label = "Highlight Exposure";
   ui_type = "slider";
    ui_min = 0.9;
    ui_max = 1.9;
   ui_step = 0.01;
   ui_tooltip = "Intensity boost for highlights like flames";
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
        const float epsilon = 1e-6;
        float Y = lab.x;
        float scaledY = Y * Exp;
        float Yd = (scaledY * (1.0 + scaledY/(midGray*midGray + epsilon))) / 
                  (1.0 + scaledY + epsilon);
        
        Yd = pow(Yd, Contrast);
        lab.x = Yd;
        return lab;
    }

    float3 AdaptiveAdjustments(float3 oklab)
    {
        
        const float shadowRange = 0.15;
        const float highlightRange = 0.85;
        float t = smoothstep(shadowRange, highlightRange, oklab.x);
        
        // Chroma-aware adjustments
        float chroma = length(oklab.yz);
        float chromaBias = 1.0 + (Vibrance - 1.0) * (1.0 - smoothstep(0.1, 0.4, chroma));
        float compressedChroma = (chroma * chromaBias) / (0.8 + chroma + 1e-6);
        
        // Apply saturation adjustments
        float satFactor = lerp(ShadowSaturation, HighlightSaturation, t);
		const float blackProtection = 0.08; // Adjust this to control darkness threshold
        float darkness = smoothstep(0.0, blackProtection, oklab.x);
        satFactor = lerp(1.0, satFactor, darkness);
        oklab.yz *= compressedChroma * satFactor / max(chroma, 1e-6);

        // Luminance preservation for highlight exposure
        const float threshold = 0.7; // Start affecting highlights above 70% luminance
        const float softRange = 0.2; // Smooth transition range
        float t_exposure = smoothstep(threshold - softRange, threshold + softRange, oklab.x);
        float exposureBoost = 1.0 + (pow(HighlightExposure, 0.5) - 1.0) * t_exposure * (1.0 - t_exposure * 0.5);
        oklab.x *= exposureBoost;
        return oklab;
    }

    float4 PS_PerceptualReinhard(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float4 color = tex2D(ReShade::BackBuffer, uv);
        
        
        if (ColorSpace == 0)
            color.rgb = SRGBToLinear(color.rgb);
        
        // Core tonemapping in perceptual space
        float3 lab = RGBToOKLab(color.rgb);
        lab = ApplyReinhardToOKLab(lab, MidGray);
        lab = AdaptiveAdjustments(lab);
        
        // Convert back to RGB and apply highlight compression(SimpleReinhard) and highlight control compression(InverseReinhard)
        color.rgb = OKLabToRGB(lab);
		color.rgb = color.rgb / (color.rgb + 1);
        color.rgb = HDR * color.rgb / max((HDR - color.rgb), 1e-5);
        
        
        if (ColorSpace == 0)
            color.rgb = LinearToSRGB(saturate(color.rgb));
            
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
