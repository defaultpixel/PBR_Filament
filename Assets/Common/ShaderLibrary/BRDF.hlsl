#ifndef CUSTOM_BRDF_INCLUDE
#define CUSTOM_BRDF_INCLUDE

#include "Assets/Common/ShaderLibrary/Common.hlsl"


//----- UE -----

//----------------------------------------
// Diffuse

float3 Diffuse_Lambert(float3 diffuseColor)
{
    return diffuseColor * (1 / PI);
}

//----------------------------------------
// NDF

// GGX / Trowbridge-Reitz
// [Walter et al. 2007, "Microfacet models for refraction through rough surfaces"]
float D_GGX_UE4( float a2, float NoH )
{
    float d = ( NoH * a2 - NoH ) * NoH + 1;    // 2 mad
    return a2 / ( PI*d*d );                    // 4 mul, 1 rcp
}

//----------------------------------------
// Vis

// Appoximation of joint Smith term for GGX
// [Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"]
float Vis_SmithJointApprox( float a2, float NoV, float NoL )
{
    float a = sqrt(a2);
    float Vis_SmithV = NoL * ( NoV * ( 1 - a ) + a );
    float Vis_SmithL = NoV * ( NoL * ( 1 - a ) + a );
    return 0.5 * rcp( Vis_SmithV + Vis_SmithL );
}

// [Kelemen 2001, "A microfacet based coupled specular-matte brdf model with importance sampling"]
float Vis_Kelemen( float VoH )
{
    // constant to prevent NaN
    return rcp( 4 * VoH * VoH + 1e-5);
}

//----------------------------------------
// F

// [Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"]
float3 F_Schlick_UE4( float3 SpecularColor, float VoH )
{
    float Fc = Pow5( 1 - VoH );                    // 1 sub, 3 mul
    //return Fc + (1 - Fc) * SpecularColor;        // 1 add, 3 mad
    
    // Anything less than 2% is physically impossible and is instead considered to be shadowing
    return saturate( 50.0 * SpecularColor.g ) * Fc + (1 - Fc) * SpecularColor;
    
}

//----------------------------------------
// IBL dfg

half3 EnvBRDF( half3 SpecularColor, half Roughness, half NoV , half2 AB)
{
    // Importance sampled preintegrated G * F
    // float2 AB = Texture2DSampleLevel( PreIntegratedGF, PreIntegratedGFSampler, float2( NoV, Roughness ), 0 ).rg;

    // Anything less than 2% is physically impossible and is instead considered to be shadowing 
    float3 GF = SpecularColor * AB.x + saturate( 50.0 * SpecularColor.g ) * AB.y;
    return GF;
}

half3 EnvBRDFApprox( half3 SpecularColor, half Roughness, half NoV, out half2 enegyCompensation)
{
    // [ Lazarov 2013, "Getting More Physical in Call of Duty: Black Ops II" ]
    // Adaptation to fit our G term.
    const half4 c0 = { -1, -0.0275, -0.572, 0.022 };
    const half4 c1 = { 1, 0.0425, 1.04, -0.04 };
    half4 r = Roughness * c0 + c1;
    half a004 = min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
    half2 AB = half2( -1.04, 1.04 ) * a004 + r.zw;

    // 输出用于高光能量补偿=采样dfglut
    enegyCompensation = AB;

    // Anything less than 2% is physically impossible and is instead considered to be shadowing
    // Note: this is needed for the 'specular' show flag to work, since it uses a SpecularColor of 0
    AB.y *= saturate( 50.0 * SpecularColor.g );

    return SpecularColor * AB.x + AB.y;
}


// ----- Filament -----
// roughness = a = perceptualRoughness * perceptualRoughness


#define MEDIUMP_FLT_MAX    65504.0
#define saturateMediump(x) min(x, MEDIUMP_FLT_MAX)

float D_GGX_Filament(float roughness, float NoH, const float3 n, const float3 h)
{
    float3 NxH = cross(n, h);
    float a = NoH * roughness;
    float k = roughness / (dot(NxH, NxH) + a * a);
    float d = k * k * (1.0 / PI);
    return saturateMediump(d);
}

float V_SmithGGXCorrelated(float NoV, float NoL, float roughness)
{
    float a2 = roughness * roughness;
    float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / (GGXV + GGXL);
}

float V_SmithGGXCorrelatedFast(float NoV, float NoL, float roughness)
{
    float a = roughness;
    float GGXV = NoL * (NoV * (1.0 - a) + a);
    float GGXL = NoV * (NoL * (1.0 - a) + a);
    return 0.5 / (GGXV + GGXL);
}

float V_Kelemen_Filament(float LoH)
{
    return 0.25f / max(Pow2(LoH), 0.00001f);
}

float3 F_Schlick_Filament(float u, float3 f0)
{
    float f = pow(1.0 - u, 5.0);
    return f + f0 * (1.0 - f);
}


// --------------------
// Custom

// LD
half3 IndirectSpecularLD(half3 reflectVector, float3 positionWS, float perceptualRoughness, float occlusion)
{
    half3 irradiance;

    half mip = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness) * 6;
    half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));

    irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
    
    return irradiance * occlusion;
}



#endif






















