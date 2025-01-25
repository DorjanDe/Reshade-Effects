#include "ReShade.fxh"

// By Liam very basic 
// Modified to support OKLab

uniform float MidGray <
    ui_type = "slider";
    ui_min = 0.1;
    ui_max = 0.5;
    ui_step = 0.01;
> = 0.2;
uniform float Contrast <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 2.0;
    ui_step = 0.01;
> = 0.85;
uniform float Saturation <
    ui_type = "slider";
    ui_min = 0.0;
    ui_max = 2.0;
    ui_step = 0.01;
> = 1.2;
uniform float ShoulderStrength <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 2.0;
    ui_step = 0.01;
> = 2.0;
uniform float WhitePoint <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 2.0;
    ui_step = 0.01;
> = 1.0;
uniform float HDR <
    ui_label = "Lower value is closer to HDR";
    ui_type = "slider";
    ui_min = 3.00;
    ui_max = 10.0;
    ui_step = 0.01;
> = 8.0;
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

float3 ReinhardExtendedOKLab(float3 color, float midGray, float whitePoint)
{
    float3 lab = RGBToOKLab(color);
    float L = lab.x;
    
    // Extended Reinhard with mid-gray adaptation and -2 cause it just works
    float scaledL = L * exp2(-2);
    float Ld = (scaledL * (1.0 + scaledL/(midGray*midGray))) / (1.0 + scaledL);
    
    Ld *= whitePoint;
    Ld = pow(Ld, Contrast);
    
  
    float2 ab = lab.yz * Saturation;
    
    return OKLabToRGB(float3(Ld, ab));
}

float4 PS_PerceptualReinhard(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 color = tex2D(ReShade::BackBuffer, uv);
    color = SRGBToLinear(color);
    color = ReinhardExtendedOKLab(color, MidGray, WhitePoint);
    
    // Shoulder strength and Reinhard Simple tonemapping for not letting color highlights go out of range look wrong
    color *= ShoulderStrength;
    color = color / (1 + color);
    
    color = LinearToSRGB(color);
	
	// Inverse Simple Reinhard to let color go out of range
	color = HDR * color / (HDR - color);
    return saturate(color);
}

technique Perceptual_Reinhard_Extended_OKLab
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_PerceptualReinhard;
    }
}
