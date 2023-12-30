#ifndef CUSTOM_PBRLIGHTING_INCLUDED
#define CUSTOM_PBRLIGHTING_INCLUDED

#include "BRDF.hlsl"


float3 CustomBRDF(
    float3 diffuseColor,
    float3 F0_specularColor,
    float  roughness,
    float3 N,
    float3 V,
    float3 L,
    float3 lightColor,
    float  shadow,
    float  enegyCompensation
)
{
    float3 H = normalize(L + V);

    float NoV = abs(dot(N, V)) + 1e-5;
    float NoH = clamp(dot(N, H),0.0,1.0);
    float NoL = clamp(dot(N, L),0.0,1.0);
    float VoH = clamp(dot(V, H),0.0,1.0);

    float3 Radiance = NoL * lightColor * shadow * PI;

    // Diffuse
    float3 Fd = Diffuse_Lambert(diffuseColor);

    #if defined(_DIFFUSE_OFF) //debug
        Fd = half3(0,0,0);
    #endif

    // Specular
    float  D   = D_GGX_UE4(roughness, NoH);
    float  Vis = Vis_SmithJointApprox(roughness, NoV, NoL);
    float3 F   = F_Schlick_UE4(F0_specularColor, VoH);

    float3 Fr = (D * Vis) * F;

    // 能量补偿
    Fr *= enegyCompensation;

    #if defined(_SPECULAR_OFF) //debug
        Fr = half3(0,0,0);
    #endif

    // 直接光 Diffuse + Specular
    return (Fd + Fr) * Radiance;
}


float3 CalDirectLighting(
    float3 diffuseColor,
    float3 F0_specularColor,
    float  roughness,
    float3 positionWS,
    float3 N,
    float3 V,
    float  enegyCompensation
)
{
    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
        float4 positionCS = TransformWorldToHClip(positionWS);
        float4 shadowCoord = ComputeScreenPos(positionCS);
    #else
        float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    #endif

    float4 shadowMask = float4(1.0,1.0,1.0,1.0);

    // MainLight
    half3 DirectLighting_MainLight = half3(0.0, 0.0, 0.0);
    {
        Light mainLight  = GetMainLight(shadowCoord, positionWS, shadowMask);
        half3 L          = mainLight.direction;
        half3 lightColor = mainLight.color;
        half  shadow     = mainLight.shadowAttenuation * mainLight.distanceAttenuation;

        DirectLighting_MainLight =
            CustomBRDF(
                diffuseColor,F0_specularColor,roughness,N,V,L,lightColor,shadow,enegyCompensation);
    }

    // AddLights
    half3 DirectLighting_AddLight = half3(0.0, 0.0, 0.0);

    #ifdef _ADDITIONAL_LIGHTS
    
    uint additionalLightCount = GetAdditionalLightsCount();
    for (uint lightIndex = 0; lightIndex < additionalLightCount; ++lightIndex)
    {
        Light addLight   = GetAdditionalLight(lightIndex, positionWS, shadowMask);
        half3 L          = addLight.direction;
        half3 lightColor = addLight.color;
        half  shadow     = addLight.shadowAttenuation * addLight.distanceAttenuation;

        DirectLighting_AddLight +=
            CustomBRDF(
                diffuseColor,F0_specularColor,roughness,N,V,L,lightColor,shadow,enegyCompensation);
    }
    
    #endif

    float3 DirectLighting = DirectLighting_MainLight + DirectLighting_AddLight;
    
    return DirectLighting;
}


float3 CalIndirectLighting(
    float3 diffuseColor,
    float3 F0_specularColor,
    float  perceptualRoughness,
    float3 positionWS,
    float3 N,
    float3 V,
    float  ao,
    float  enegyCompensation
)
{
    float NoV = abs(dot(N, V)) + 1e-5;
    
    // SH
    float3 ao_diffuse = AOMultiBounce(diffuseColor, ao);
    float3 radianceSH = SampleSH(N);
    float3 IndirectDiffuse = ao_diffuse * radianceSH * diffuseColor;

    #if defined(_SH_OFF) // debug
        IndirectDiffuse = half3(0.0, 0.0, 0.0);
    #endif

    // IBL
    half3 R = reflect(-V, N);

    // unity 2020.3.8
    // half3 SpecLD  = GlossyEnvironmentReflection(r, positionWS, roughness, ao);
    half3  SpecLD            = GlossyEnvironmentReflection(R, positionWS, perceptualRoughness, ao);
    half3  SpecDFG           = EnvBRDFApprox(F0_specularColor, perceptualRoughness, NoV);
    float  SpecularOcclusion = GetSpecularOcclusion(NoV, Pow2(perceptualRoughness), ao);
    float3 SpecularAO        = AOMultiBounce(F0_specularColor, SpecularOcclusion);

    float3 IndirectSpec = SpecLD * SpecDFG * SpecularAO;

    // 能量补偿
    IndirectSpec *= enegyCompensation;

    #if defined(_IBL_OFF) // debug
        IndirectSpec = half3(0.0, 0.0, 0.0);
    #endif

    float3 IndirectLighting = IndirectDiffuse + IndirectSpec;

    return IndirectLighting;
}









#endif