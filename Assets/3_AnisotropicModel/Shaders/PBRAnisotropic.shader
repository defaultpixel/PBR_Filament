Shader "CustomPBR/PBRAnisotropic"
{
    Properties
    {
        [MainTexture] _BaseMap  ("Albedo", 2D)            = "white" {}
        [MainColor]   _BaseColor("Color", Color)          = (1,1,1,1)
               
        _MetallicMap ("Metallic Map",2D)                  = "white" {}
        _Metallic    ("Metallic",Range(0.0,1.0))          = 1.0
               
        _RoughnessMap("Roughness Map",2D)                 = "white" {}
        _PerceptualRoughness("Roughness",Range(0.0,1.0))  = 1.0
         
        _Specular ("Specular", Range(0.0, 1.0))           = 0.5
               
        _NormalMap   ("Normal Map",2D)                    = "bump" {}
        _NormalScale ("Normal", Range(0.0, 1.0))          = 1.0
       
        _AOMap       ("AOMap",2D)                         = "white" {}
        _AOStrength  ("AOStrength",Range(0.0,1.0))        = 1.0
        
        _Anisotropy  ("Anisotropy", Range(-1, 1))         = 0
        
        // Test, linear,clamp
        _dfgLUT      ("dfg LUT", 2D)                      = "white" {}

        [Toggle(_DIFFUSE_OFF)]  _DIFFUSE_OFF ("DIFFUSE OFF",  Float) = 0.0
        [Toggle(_SPECULAR_OFF)] _SPECULAR_OFF("SPECULAR OFF", Float) = 0.0
        [Toggle(_SH_OFF)]       _SH_OFF      ("SH OFF",       Float) = 0.0
        [Toggle(_IBL_OFF)]      _IBL_OFF     ("IBL OFF",      Float) = 0.0
        
        [Toggle(_ECompen_OFF)]   _ECompen_OFF       ("_ECompen_OFF",    Float) = 0.0
        [Toggle(_ECompen_DEBUG)] _ECompen_DEBUG     ("_ECompen_DEBUG",  Float) = 0.0
        
        [Toggle(_SAMPLE_dfgLUT)] _SAMPLE_dfgLUT     ("_SAMPLE_dfgLUT",  Float) = 0.0
    }
    
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "IgnoreProjector" = "True"
            "ShaderModel" = "4.5"
        }
        
        // Forward
        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }
            
            HLSLPROGRAM

            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            // -------------------------------------
            // Material Keywords

            // debug
            #pragma shader_feature_local_fragment _DIFFUSE_OFF
            #pragma shader_feature_local_fragment _SPECULAR_OFF
            #pragma shader_feature_local_fragment _SH_OFF
            #pragma shader_feature_local_fragment _IBL_OFF
            #pragma shader_feature_local_fragment _ECompen_DEBUG
            #pragma shader_feature_local_fragment _ECompen_OFF
            
            #pragma shader_feature_local_fragment _SAMPLE_dfgLUT
            
            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #pragma vertex PBRVertex
            #pragma fragment PBRFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // PBR光照计算
            #include "PBRLighting_Anisotropic.hlsl"

            TEXTURE2D(_BaseMap);         SAMPLER(sampler_BaseMap);
            TEXTURE2D(_MetallicMap);     SAMPLER(sampler_MetallicMap);
            TEXTURE2D(_RoughnessMap);    SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_NormalMap);       SAMPLER(sampler_NormalMap);
            TEXTURE2D(_AOMap);           SAMPLER(sampler_AOMap);
            TEXTURE2D(_dfgLUT);          SAMPLER(sampler_dfgLUT);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half  _Specular;
                half  _Metallic;
                half  _PerceptualRoughness;
                half  _NormalScale;
                half  _AOStrength;

                half  _Anisotropy;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 texcoord     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv           : TEXCOORD0;
                float3 positionWS   : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                float4 tangentWS    : TEXCOORD3;    // xyz: tangent, w: sign
                float4 shadowCoord  : TEXCOORD4;
                float4 positionCS   : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings PBRVertex(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                VertexPositionInputs vertexInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs   normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.uv       = input.texcoord;
                output.normalWS = normalInputs.normalWS;

                real sign = input.tangentOS.w * GetOddNegativeScale();
                half4 tangentWS = half4(normalInputs.tangentWS.xyz, sign);

                output.tangentWS   = tangentWS;
                output.positionWS  = vertexInputs.positionWS;
                output.shadowCoord = GetShadowCoord(vertexInputs);
                output.positionCS  = vertexInputs.positionCS;

                return output;
            }

            real4 PBRFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(input);

                // 顶点着色器输入数据
                float2 uv = input.uv;
                float3 positionWS = input.positionWS;
                
                half3  view_dir   = GetWorldSpaceNormalizeViewDir(positionWS);
                half3  normalWS   = normalize(input.normalWS);
                half3  tangentWS  = normalize(input.tangentWS.xyz);
                half3  binormalWS = normalize(cross(normalWS, tangentWS) * input.tangentWS.w);

                half3x3 TBN = half3x3(tangentWS, binormalWS, normalWS);

                float4 shadowCoord = input.shadowCoord;
                float2 screen_uv   = GetNormalizedScreenSpaceUV(input.positionCS);
                half4  shadowMask  = float4(1.0, 1.0, 1.0, 1.0);

                // 贴图采样
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
                half3 baseColor = baseMap.rgb;

                float metallic  = saturate(SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, uv).r * _Metallic);
                float perceptualRoughness =
                    max(SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, uv).r * _PerceptualRoughness, 0.089); // float:0.045
                
                half3 normalTS  = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv), _NormalScale);
                normalWS = normalize(mul(normalTS, TBN));

                half ao = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, uv).r;
                ao = lerp(1.0, ao, _AOStrength);

                // 让材质在高粗糙度时候的表现更线性
                // a  = perceptualRoughness * perceptualRoughness;
                // a2 = Pow4(perceptualRoughness);
                half roughness = perceptualRoughness * perceptualRoughness;

                // float roughness = Pow2(perceptualRoughness); // Filament

                half anisotropy = _Anisotropy; // 负值使各向异性平行于副切线方向,而不是切线方向

                half3 F0 = float3(0.08,0.08,0.08) * _Specular;

                half3 diffuseColor  = lerp(baseColor, float3(0.0, 0.0, 0.0), metallic);
                half3 F0_specularColor = lerp(F0, baseColor, metallic);

                #if defined(_SCREEN_SPACE_OCCLUSION)
                    AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(screen_uv);
                    ao = min(ao, aoFactor.indirectAmbientOcclusion);
                #endif

                // Test

                half2 dfg = 0.0;
                half  eneryCompensation = 1.0;

                #if defined(_SAMPLE_dfgLUT)
                half  dfg_NdotV = saturate(dot(normalWS, view_dir));
                dfg = SAMPLE_TEXTURE2D_LOD(_dfgLUT,sampler_dfgLUT,float2(dfg_NdotV, perceptualRoughness),0.0).rg;
                eneryCompensation = 1.0 + F0_specularColor * (rcp(dfg.x + dfg.y) - 1.0);
                #endif

                // 光照计算:环境光
                half3 IndirectLighting = CalIndirectLighting(diffuseColor, F0_specularColor, perceptualRoughness, positionWS,
                    normalWS, view_dir, ao, eneryCompensation, dfg);
                
                // 光照计算:直接光
                half3 DirectLigthing = CalDirectLighting(diffuseColor, F0_specularColor, roughness, positionWS, normalWS,
                    tangentWS, binormalWS, view_dir, eneryCompensation, anisotropy);


                half3 finalColor = DirectLigthing + IndirectLighting;

                #if defined (_ECompen_DEBUG) // debug
                    return half4((eneryCompensation - 1.0).xxx, 1.0);
                #endif
                
                return half4(finalColor, 1.0);
            }
            
            ENDHLSL
        }
        
        
        // ShadowCaster
        Pass
        {
            Name "ShadowCaster"
            Tags{ "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            // -------------------------------------
            // Universal Pipeline keywords

            // This is used during shadow map generation to differentiate between directional and punctual light shadows, as they use different formulas to apply Normal Bias
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            
            ENDHLSL
        }
        
        // DepthOnly
        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        
        // DepthNormals
        // This pass is used when drawing to a _CameraNormalsTexture texture
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
        
        // This pass it not used during regular rendering, only for lightmap baking.
        Pass
        {
            Name "Meta"
            Tags
            {
                "LightMode" = "Meta"
            }

            // -------------------------------------
            // Render State Commands
            Cull Off

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // Shader Stages
            #pragma vertex UniversalVertexMeta
            #pragma fragment UniversalFragmentMetaLit

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local _ _DETAIL_MULX2 _DETAIL_SCALED
            #pragma shader_feature_local_fragment _SPECGLOSSMAP
            #pragma shader_feature EDITOR_VISUALIZATION

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitMetaPass.hlsl"

            ENDHLSL
        }
    }
}
