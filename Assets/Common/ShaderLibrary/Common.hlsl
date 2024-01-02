#ifndef CUSTOM_COMMON_INCLUDE
#define CUSTOM_COMMON_INCLUDE

inline half Pow2 (half x)
{
    return x*x;
}

/*inline half Pow4 (half x)
{
    return x*x * x*x;
}*/

inline half Pow5 (half x)
{
    return x*x * x*x * x;
}

void GetSSAO_float(float2 screen_uv,out float SSAO)
{
    SSAO = 1.0f;
    #ifndef SHADERGRAPH_PREVIEW
        #if defined(_SCREEN_SPACE_OCCLUSION)
            AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(screen_uv);
            SSAO = aoFactor.indirectAmbientOcclusion;
        #endif
    #endif
}

inline half3 RotateDirection(half3 R, half degrees)
{
    float3 reflUVW = R;
    half theta = degrees * PI / 180.0f;
    half costha = cos(theta);
    half sintha = sin(theta);
    reflUVW = half3(reflUVW.x * costha - reflUVW.z * sintha, reflUVW.y, reflUVW.x * sintha + reflUVW.z * costha);
    return reflUVW;
}

// RoughnessSq = pow2(perceptualRoughness)
float GetSpecularOcclusion(float NoV, float RoughnessSq, float AO)
{
    return saturate( pow( NoV + AO, RoughnessSq ) - 1 + AO );
}

float3 AOMultiBounce( float3 BaseColor, float AO )
{
    float3 a =  2.0404 * BaseColor - 0.3324;
    float3 b = -4.7951 * BaseColor + 0.6417;
    float3 c =  2.7552 * BaseColor + 0.6903;
    return max( AO, ( ( AO * a + b ) * AO + c ) * AO );
}




#endif