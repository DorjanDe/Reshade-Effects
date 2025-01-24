#include "ReShade.fxh"

// By Liam very basic 


uniform float MidGray <
    ui_type = "slider";
    ui_min = 0.1;
    ui_max = 0.5;
    ui_step = 0.01;
> = 0.18;
uniform float Contrast <
    ui_type = "slider";
    ui_min = 0.5;
    ui_max = 2.0;
    ui_step = 0.01;
> = 1.0;
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
    ui_max = 4.0;
    ui_step = 0.01;
> = 1.0;
float3 SRGBToLinear(float3 color)
{
    return color < 0.04045 ? color / 12.92 : pow((color + 0.055)/1.055, 2.4);
}

float3 LinearToSRGB(float3 color)
{
    return color < 0.0031308 ? 12.92 * color : 1.055 * pow(color, 1.0/2.4) - 0.055;
}

float3 RGBToXYZ(float3 c)
{
    const float3x3 m = float3x3(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    );
    return mul(m, c);
}

float3 XYZToLAB(float3 xyz)
{
    xyz /= float3(0.95047, 1.0, 1.08883); // D65 normalization
    float3 f = pow(xyz, 1.0/3.0);
    f = xyz > 0.008856 ? f : 7.787 * xyz + 16.0/116.0;
    return float3(
        (116.0 * f.y) - 16.0,
        500.0 * (f.x - f.y),
        200.0 * (f.y - f.z)
    );
}

float3 LABToXYZ(float3 lab)
{
    float fy = (lab.x + 16.0)/116.0;
    float fx = lab.y/500.0 + fy;
    float fz = fy - lab.z/200.0;
    
    float3 f = float3(fx, fy, fz);
    float3 xyz = f > 0.2068966 ? pow(f, 3.0) : (f - 16.0/116.0)/7.787;
    return xyz * float3(0.95047, 1.0, 1.08883);
}

float3 XYZToRGB(float3 xyz)
{
    const float3x3 m = float3x3(
         3.2404542, -1.5371385, -0.4985314,
        -0.9692660,  1.8760108,  0.0415560,
         0.0556434, -0.2040259,  1.0572252
    );
    return mul(m, xyz);
}

float3 ReinhardExtendedLAB(float3 color, float midGray, float whitePoint)
{
    float3 lab = XYZToLAB(RGBToXYZ(color));
    
  
    float L = lab.x / 100.0;
    
    // Its the extended Reinhard with mid-gray adaptatio
    float scaledL = L * exp2(-2);
    float Ld = (scaledL * (1.0 + scaledL/(midGray*midGray))) / (1.0 + scaledL);
    
    
    Ld *= whitePoint;
    
    Ld = pow(Ld, Contrast);

    float2 ab = lab.yz * Saturation;
    
    return XYZToRGB(LABToXYZ(float3(Ld * 100.0, ab)));
}
float4 PS_PerceptualReinhard(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 color = tex2D(ReShade::BackBuffer, uv);
    
   
    color = SRGBToLinear(color);
    
    // apply extended reinhard in perceptual space
    color = ReinhardExtendedLAB(color, MidGray, WhitePoint);
    
    
    color *= ShoulderStrength;
    color = color / (1.0 + color);
    
    
    color = LinearToSRGB(color);
    
    return saturate(color);
}


technique Perceptual_Reinhard_Extended
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_PerceptualReinhard;
    }
}