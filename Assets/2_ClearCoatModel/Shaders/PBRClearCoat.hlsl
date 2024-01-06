#ifndef CUSTOM_PBRLIGHTING_INCLUDED
#define CUSTOM_PBRLIGHTING_INCLUDED

#include "Assets/Common/ShaderLibrary/BRDF.hlsl"

// 直接光清漆层
// 1. 如果清漆没有自己的法线贴图,使用模型几何法线 ?TODO: 使用模型的法线贴图或许效果更好?
// 2. V项替换为更节省的V_Kelemen
half3 ClearCoatFrc(
    half clearCoat,
    half clearCoatRoughness,
    half3 N_mesh,
    half3 L,
    half3 V,
    inout half Fc
    )
{
    half3 H = normalize(L + V); //TODO: safenormalize?

    half NoH = saturate(dot(N_mesh, H));
    half LoH = saturate(dot(L, H));
    
    half  Dc = D_GGX_Filament(clearCoatRoughness, NoH, N_mesh, H);
    float Vc = V_Kelemen_Filament(LoH);
    Fc = F_Schlick_Filament(LoH, 0.04h) * clearCoat;

    half Frc = (Dc * Vc) * Fc;

    return Frc;
}

// 间接光清漆层
// 1. 和计算间接光主镜面光一样
// 2. Fc 作为能量损失
half3 ClearCoatDFG(
    half3 F0_specularColor,
    half clearCoat,
    half clearCoatPerceptualRoughness,
    half3 V,
    half3 N_mesh,
    half3 positionWS,
    half ao,
    inout half Fc)
{
    half3 R = reflect(-V, N_mesh);

    half NoV = saturate(dot(N_mesh, V));

    #if defined(_SAMPLE_dfgLUT)
    half3  SpecDFG =  EnvBRDF(0.04, clearCoatPerceptualRoughness, NoV, dfg);   // dfg方案一:采样生成的dfgLUT
    #else
    half3  SpecDFG =  EnvBRDFApprox(0.04, clearCoatPerceptualRoughness, NoV);  // dfg方案二:拟合
    #endif
    
    half3 SpecLD  = IndirectSpecularLD(R, positionWS, clearCoatPerceptualRoughness, ao);

    Fc = F_Schlick_Filament(NoV, 0.04) * clearCoat;

    return SpecLD * SpecDFG;
}

half3 CustomBRDF(
    half3 diffuseColor,
    half3 F0_specularColor,
    half  roughness,
    half3 N,
    half3 N_mesh,
    half3 V,
    half3 L,
    half3 lightColor,
    half  shadow,
    half  enegyCompensation,
    half  clearCoat,
    half  clearCoatRoughness
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
    /*half a2 = roughness * roughness; // Pow4(perceptualRoughness)
    half   D   = D_GGX_UE4(a2, NoH);
    float  Vis = Vis_SmithJointApprox(a2, NoV, NoL);
    half3  F   = F_Schlick_UE4(F0_specularColor, VoH);*/

    // Filament
    half  D = D_GGX_Filament(roughness, NoH, N, H);
    float Vis = V_SmithGGXCorrelatedFast(NoV, NoL, roughness);
    half F = F_Schlick_Filament(0.04, 1.0, VoH);

    half3 Fr = (D * Vis) * F;
    
    // 能量补偿
    #if defined(_ECompen_OFF)
    #else
        Fr *= enegyCompensation;
    #endif

    // 清漆BRDF
    half Fc = 1.0h; // 清漆BRDF F项,基层能量损失
    half Frc = ClearCoatFrc(clearCoat, clearCoatRoughness, N_mesh, L, V, Fc);
    
    #if defined(_SPECULAR_OFF) //debug
        Fr = half3(0,0,0);
    #endif


    // 考虑清漆带来的基层能量损失
    half3 DirectLighting = Radiance * ((Fd + Fr * (1.0 - Fc)) * (1.0 - Fc) + Frc);

    #if defined(_DirectClearCoat_OFF)
        DirectLighting = Radiance * (Fd + Fr);
    #endif

    return DirectLighting;
}


half3 CalDirectLighting(
    half3 diffuseColor,
    half3 F0_specularColor,
    half  roughness,
    half3 positionWS,
    half3 N,
    half3 N_mesh,
    half3 V,
    half  enegyCompensation,
    half  clearCoat,
    half  clearCoatRoughness
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
        half  shadow     = mainLight.shadowAttenuation; // * aoFactor.directAmbientOcclusion;

        DirectLighting_MainLight =
            CustomBRDF(
                diffuseColor,F0_specularColor,roughness,N,N_mesh,V,L,lightColor,shadow,enegyCompensation,
                clearCoat, clearCoatRoughness);
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
        half  shadow     = addLight.shadowAttenuation * addLight.distanceAttenuation; // * aoFactor.directAmbientOcclusion;

        DirectLighting_AddLight +=
            CustomBRDF(
                diffuseColor,F0_specularColor,roughness,N,N_mesh,V,L,lightColor,shadow,enegyCompensation,
                clearCoat, clearCoatRoughness);
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
    half3 N_mesh,
    half3 V,
    half  ao,
    inout half enegyCompensation,
    half2  dfg,
    half  clearCoat,
    half  clearCoatPerceptualRoughness
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
        enegyCompensation = 1.0h;
    #else
        IndirectSpec *= enegyCompensation;
    #endif

    #if defined(_IBL_OFF) // debug
        IndirectSpec = half3(0.0, 0.0, 0.0);
    #endif

    // 清漆高光波瓣计算
    half Fc = 0.0h;
    half3 IndirecSpec_clearCoat = ClearCoatDFG(F0_specularColor,clearCoat,clearCoatPerceptualRoughness,
        V,N_mesh,positionWS,ao,Fc) * SpecularAO;

    half3 IndirectLighting;
    #if defined(_IndirectClearCoat_OFF)
    {
        Fc = 0.0h;
        
        IndirectLighting = IndirectDiffuse + IndirectSpec;
        return IndirectLighting;
    }
    #endif

    // 基础层衰减的能量
    IndirectDiffuse *= (1.0 - Fc);
    // IndirectSpec    *= (1.0 - Fc) * (1.0 - Fc);
    IndirectSpec    *= sqrt(1.0 - Fc);
    IndirectSpec    += IndirecSpec_clearCoat * Fc;

    IndirectLighting = IndirectDiffuse + IndirectSpec;
    
    return IndirectLighting;
}









#endif