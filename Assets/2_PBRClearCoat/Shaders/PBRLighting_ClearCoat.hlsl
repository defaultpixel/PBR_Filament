#ifndef CUSTOM_PBRLIGHTING_INCLUDED
#define CUSTOM_PBRLIGHTING_INCLUDED

#include "Assets/Common/ShaderLibrary/BRDF.hlsl"

// TODO
// 1. 在原本的高光上再叠一层高光
// 2. 将基础层乘上一个衰减保证能量守恒
// 3. 清漆会导致底层的F0和粗糙度改变
float3 ClearCoatFrc(
    float clearCoat,
    float clearCoatRoughness,
    float3 N_mesh,
    float3 V,
    float3 L,
    out float3 EnergyLoss)
{
    float3 H = normalize(L + V);
    float NoH = saturate(dot(N_mesh,H));
    float NoV = abs(dot(N_mesh,V)) + 1e-5;
    float NoL = saturate(dot(N_mesh,L));
    float VoH = saturate(dot(V,H));
    
    float  D   = D_GGX_UE4(clearCoatRoughness,NoH);
    float  Vis = Vis_Kelemen(VoH);
    float3 F   = F_Schlick_UE4( float3(0.04,0.04,0.04), VoH ) * clearCoat;
    EnergyLoss = F;

    return (D * Vis) * F;
}


float3 CustomBRDF(
    float3 diffuseColor,
    float3 F0_specularColor,
    float  roughness,
    float3 N,
    float3 V,
    float3 L,
    float3 lightColor,
    float  shadow,
    float  enegyCompensation,
    float  clearCoat,
    float  clearCoatRoughenss,
    float3 normalWS_mesh
)
{
    float3 H = normalize(L + V);

    float NoV = abs(dot(N, V)) + 1e-5;
    float clampedNoH = clamp(dot(N, H),0.0,1.0);
    float clampedNoL = clamp(dot(N, L),0.0,1.0);
    float clampedVoH = clamp(dot(V, H),0.0,1.0);

    float3 Radiance = clampedNoL * lightColor * shadow * PI;

    // ClearCoat
    float3 EnergyLoss = 0.0;
    float3 F0;
    float  Roughness;
    float3 ClearCoatLighting = ClearCoatFrc(clearCoat, clearCoatRoughenss,
        normalWS_mesh, V, L, EnergyLoss);

    // Diffuse
    float3 Fd = Diffuse_Lambert(diffuseColor);

    #if defined(_DIFFUSE_OFF) //debug
        Fd = half3(0,0,0);
    #endif

    // Specular
    float  D   = D_GGX_UE4(roughness, clampedNoH);
    float  Vis = Vis_SmithJointApprox(roughness, NoV, clampedNoL);
    float3 F   = F_Schlick_UE4(F0_specularColor, clampedVoH);

    float3 Fr = (D * Vis) * F;

    // 能量补偿
    Fr *= enegyCompensation;

    #if defined(_SPECULAR_OFF) //debug
        Fr = half3(0,0,0);
    #endif

    float3 DiffuseLighting = Radiance * Fd;
    float3 SpecLighting    = Radiance * Fr;

    // 加上清漆后基础层能量损失
    DiffuseLighting *= (1.0 - EnergyLoss);
    SpecLighting    *= (1.0 - EnergyLoss);

    float3 DirectLighting = DiffuseLighting + SpecLighting + ClearCoatLighting;

    // 直接光 Diffuse + Specular
    return DirectLighting;
}


float3 CalDirectLighting(
    float3 diffuseColor,
    float3 F0_specularColor,
    float  roughness,
    float3 positionWS,
    float3 N,
    float3 V,
    float  enegyCompensation,
    float  clearCoat,
    float  clearCoatRoughenss,
    float3 normalWS_mesh
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
                diffuseColor,F0_specularColor,roughness,N,V,L,lightColor,shadow,enegyCompensation,
                clearCoat,clearCoatRoughenss,normalWS_mesh);
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
                diffuseColor,F0_specularColor,roughness,N,V,L,lightColor,shadow,enegyCompensation,
                clearCoat,clearCoatRoughenss,normalWS_mesh);
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
    float  enegyCompensation,
    float  clearCoat,
    float  clearCoatRoughness,
    float3 normalWS_mesh
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
    half3  SpecDFG           = EnvBRDFApprox(F0_specularColor, perceptualRoughness, NoV, half2(0,0));
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