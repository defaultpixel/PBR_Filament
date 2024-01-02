#ifndef CUSTOM_PBRLIGHTING_INCLUDED
#define CUSTOM_PBRLIGHTING_INCLUDED

#include "Assets/Common/ShaderLibrary/BRDF.hlsl"


half3 CustomBRDF(
    half3 diffuseColor,
    half3 F0_specularColor,
    half  roughness,
    half3 N,
    half3 V,
    half3 L,
    half3 lightColor,
    half  shadow,
    half  enegyCompensation
)
{
    half3 H = normalize(L + V);

    half NoV = abs(dot(N, V)) + 1e-5;
    half NoH = clamp(dot(N, H),0.0,1.0);
    half NoL = clamp(dot(N, L),0.0,1.0);
    half VoH = clamp(dot(V, H),0.0,1.0);
    half LoH = clamp(dot(L, H),0.0,1.0);

    half3 Radiance = NoL * lightColor * shadow;

    // Diffuse
    half3 Fd = Diffuse_Lambert(diffuseColor);

    #if defined(_DIFFUSE_OFF) //debug
        Fd = half3(0,0,0);
    #endif

    // Specular

    // UE
    half   D   = D_GGX_UE4(roughness, NoH);
    float  Vis = Vis_SmithJointApprox(roughness, NoV, NoL);
    half3  F   = F_Schlick_UE4(F0_specularColor, VoH);

    // Filament
    /*half D = D_GGX(roughness, NoH, N, H);
    float Vis = V_SmithGGXCorrelated(NoV, NoL, roughness);
    half3 F = F_Schlick(VoH, F0_specularColor);*/

    half3 Fr = (D * Vis) * F;
    
    // 能量补偿
    #if defined(_ECompen_OFF)
    #else
        Fr *= enegyCompensation;
    #endif

    #if defined(_SPECULAR_OFF) //debug
        Fr = half3(0,0,0);
    #endif
    
    // test
    // return F * Radiance;
    

    // 直接光 Diffuse + Specular
    return (Fd + Fr) * Radiance;
}


half3 CalDirectLighting(
    half3 diffuseColor,
    half3 F0_specularColor,
    half  roughness,
    half3 positionWS,
    half3 N,
    half3 V,
    half  enegyCompensation
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


half3 CalIndirectLighting(
    half3 diffuseColor,
    half3 F0_specularColor,
    half  perceptualRoughness,
    half3 positionWS,
    half3 N,
    half3 V,
    half  ao,
    inout half enegyCompensation,
    half2  dfg
)
{
    half NoV = abs(dot(N, V)) + 1e-5;
    
    // SH
    half3 ao_diffuse = AOMultiBounce(diffuseColor, ao);
    half3 radianceSH = SampleSH(N);
    // float3 radianceSH = IrradianceSH_2Bands(N); // TODO
    half3 IndirectDiffuse = ao_diffuse * radianceSH * diffuseColor;

    #if defined(_SH_OFF) // debug
        IndirectDiffuse = half3(0.0, 0.0, 0.0);
    #endif

    // IBL
    half3 R = reflect(-V, N);

    #if defined(_SAMPLE_dfgLUT)
    half3  SpecDFG =  EnvBRDF(F0_specularColor, perceptualRoughness, NoV, dfg);   // dfg方案一:采样生成的dfgLUT
    #else
    half3  SpecDFG =  EnvBRDFApprox(F0_specularColor, perceptualRoughness, NoV, dfg);  // dfg方案二:拟合
    enegyCompensation = 1.0 + F0_specularColor * (rcp(dfg.x + dfg.y) - 1.0);
    #endif
    
    half3 SpecLD  = IndirectSpecularLD(R, positionWS, perceptualRoughness, ao);
    half  SpecularOcclusion = GetSpecularOcclusion(NoV, Pow2(perceptualRoughness), ao);
    half3 SpecularAO        = AOMultiBounce(F0_specularColor, SpecularOcclusion);

    half3 IndirectSpec = SpecLD * SpecDFG * SpecularAO;

    // 能量补偿
    #if defined(_ECompen_OFF)
    #else
        IndirectSpec *= enegyCompensation;
    #endif

    #if defined(_IBL_OFF) // debug
        IndirectSpec = half3(0.0, 0.0, 0.0);
    #endif

    float3 IndirectLighting = IndirectDiffuse + IndirectSpec;

    return IndirectLighting;
}









#endif