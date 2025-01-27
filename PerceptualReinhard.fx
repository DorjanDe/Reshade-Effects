#include "ReShade.fxh"
// By Liam Very Basic starting to get medium stuff
//To do
//Add BT2020 to bt709 before okLAB for pq/hdr10
uniform int ColorSpace <
    ui_type = "combo";
    ui_items = "SRGB\0scRGB\0HLG\0PQ\0";
    ui_label = "Color Space";
> = 0;
uniform float MidGray <
    ui_type = "slider";
    ui_min = 0.14;
    ui_max = 0.18;
    ui_step = 0.01;
> = 0.18;
uniform float Contrast <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
> = 1.0;
uniform float ShoulderStrength <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 4.0;
    ui_step = 0.01;
> = 4.0;
uniform float WhitePoint <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
> = 1.0;
uniform float HDR <
    ui_label = "Lower value is closer to HDR";
    ui_type = "slider";
    ui_min = 1.0;
    ui_max = 4.0;
    ui_step = 0.01;
> = 4.0;
uniform int ReinhardMode <
    ui_type = "combo";
    ui_items = "Luminance-Based\0Per-Channel\0";
    ui_label = "Reinhard Mode";
> = 0;
uniform float ShadowSaturation <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
> = 1.08;
uniform float HighlightSaturation <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
> = 1.0;
uniform float Saturation <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 1.5;
    ui_step = 0.01;
	ui_label = "Global Saturation";
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

float3 HLGToLinear(float3 color)
{
    float3 E;
    E.r = (color.r <= 0.5) ? (color.r * color.r) / 3.0 : (exp((color.r - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    E.g = (color.g <= 0.5) ? (color.g * color.g) / 3.0 : (exp((color.g - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    E.b = (color.b <= 0.5) ? (color.b * color.b) / 3.0 : (exp((color.b - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    return E;
}

float3 LinearToHLG(float3 E)
{
    float3 V;
    V.r = (E.r <= 1.0/12.0) ? sqrt(3.0 * E.r) : 0.17883277 * log(12.0 * E.r - 0.28466892) + 0.55991073;
    V.g = (E.g <= 1.0/12.0) ? sqrt(3.0 * E.g) : 0.17883277 * log(12.0 * E.g - 0.28466892) + 0.55991073;
    V.b = (E.b <= 1.0/12.0) ? sqrt(3.0 * E.b) : 0.17883277 * log(12.0 * E.b - 0.28466892) + 0.55991073;
    return V;
}

float3 PQToLinear(float3 V)
{
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;
    
    V = pow(V, 1.0/m2);
    float3 L = pow(max(V - c1, 0.0) / (c2 - c3 * V), 1.0/m1);
    return L * 10000.0;
}

float3 LinearToPQ(float3 L)
{
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;
    
    L /= 10000.0;
    L = pow(max(L, 0.0), m1);
    float3 V = pow((c2 * L + c1) / (1.0 + c3 * L), m2);
    return saturate(V);
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

float Luminance(float3 rgb)
{
    return dot(rgb, float3(0.2126, 0.7152, 0.0722));
}

float3 ApplyReinhardToLuminance(float3 color, float midGray, float whitePoint)
{
    float Y = Luminance(color);
    float scaledY = Y * 0.25;
    float Yd = (scaledY * (1.0 + scaledY/(midGray*midGray))) / (1.0 + scaledY);
    Yd *= whitePoint;
    Yd = pow(Yd, Contrast);
    return color * (Yd / max(Y, 1e-6));
}

float3 ApplyReinhardPerChannel(float3 color, float midGray, float whitePoint)
{
    float3 scaled = color * 0.25;
    float3 scaledY = 1.0 + scaled;
    float3 scaledX = scaled * (1.0 + scaled/(midGray*midGray));
    color = (scaledX / scaledY) * whitePoint;
    return pow(color, Contrast);
}

float3 AdaptiveAdjustments(float3 oklab, float3 linearRGB)
{
    float luma = Luminance(linearRGB);
    float t = smoothstep(0.1, 0.9, luma);
    
    
    float satFactor = lerp(ShadowSaturation, HighlightSaturation, t) * Saturation;
    
   
    float brightness = lerp(1, HighlightBrightness, t);
    
    return float3(oklab.x * brightness, oklab.yz * satFactor);
}

float4 PS_PerceptualReinhard(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 color = tex2D(ReShade::BackBuffer, uv);
    
    if (ColorSpace == 0)
        color.rgb = SRGBToLinear(color.rgb);
    else if (ColorSpace == 2)
        color.rgb = HLGToLinear(color.rgb);
    else if (ColorSpace == 3)
        color.rgb = PQToLinear(color.rgb);

    if (ReinhardMode == 0)
        color.rgb = ApplyReinhardToLuminance(color.rgb, MidGray, WhitePoint);
    else
        color.rgb = ApplyReinhardPerChannel(color.rgb, MidGray, WhitePoint);

    float3 lab = RGBToOKLab(color.rgb);
    lab = AdaptiveAdjustments(lab, color.rgb); 
    color.rgb = OKLabToRGB(lab);
    
    color.rgb *= ShoulderStrength;
    color.rgb = color.rgb / (1 + color.rgb);

    float hdrParam = (ColorSpace == 3) ? 1.0 : HDR; 
    color.rgb = hdrParam * color.rgb / max((hdrParam - color.rgb), 1e-5);
    
    if (ColorSpace == 0)
        color.rgb = LinearToSRGB(color.rgb);
    else if (ColorSpace == 2)
        color.rgb = LinearToHLG(color.rgb);
    else if (ColorSpace == 3)
        color.rgb = LinearToPQ(color.rgb);
    
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
