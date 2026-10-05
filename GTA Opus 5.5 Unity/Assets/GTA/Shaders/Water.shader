Shader "Halcyon/Water"
{
    Properties
    {
        _ShallowColor("Shallow", Color) = (0.22, 0.74, 0.76, 0.55)
        _DeepColor("Deep", Color) = (0.04, 0.27, 0.42, 0.94)
        _FoamColor("Foam", Color) = (0.95, 0.98, 1.0, 1.0)
        _DepthRange("Depth Range", Float) = 7
        _WaveAmp("Wave Amplitude", Float) = 0.28
        _WaveLen("Wave Length", Float) = 16
        _WaveSpeed("Wave Speed", Float) = 1.1
        _Night("Night", Range(0, 1)) = 0
        _Storm("Storm", Range(0, 1)) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent-20" "RenderPipeline" = "UniversalPipeline" }
        Pass
        {
            Name "WaterForward"
            Tags { "LightMode" = "UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ShallowColor;
                half4 _DeepColor;
                half4 _FoamColor;
                float _DepthRange;
                float _WaveAmp;
                float _WaveLen;
                float _WaveSpeed;
                float _Night;
                float _Storm;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                float fogFactor : TEXCOORD2;
            };

            float Wave(float2 p, float t)
            {
                float k = 6.2831853 / _WaveLen;
                return sin(p.x * k + t) * 0.5
                     + sin((p.x * 0.7 + p.y) * k * 1.31 + t * 1.27) * 0.35
                     + sin((p.y - p.x * 0.43) * k * 0.61 - t * 0.83) * 0.45;
            }

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 ws = TransformObjectToWorld(input.positionOS.xyz);
                float t = _Time.y * _WaveSpeed;
                ws.y += Wave(ws.xz, t) * _WaveAmp * (1.0 + _Storm * 1.8);
                o.positionWS = ws;
                o.positionCS = TransformWorldToHClip(ws);
                o.screenPos = ComputeScreenPos(o.positionCS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i, bool front : SV_IsFrontFace) : SV_Target
            {
                // faceted (flat) normal from screen-space derivatives: fits the low-poly art direction
                float3 n = normalize(cross(ddy(i.positionWS), ddx(i.positionWS)));
                if (n.y < 0) n = -n;
                float2 uv = i.screenPos.xy / i.screenPos.w;
                float rawDepth = SampleSceneDepth(uv);
                float sceneEye = LinearEyeDepth(rawDepth, _ZBufferParams);
                float surfEye = i.screenPos.w;
                float depth = max(sceneEye - surfEye, 0.0);
                float dk = saturate(depth / _DepthRange);
                half4 col = lerp(_ShallowColor, _DeepColor, dk);

                float3 viewDir = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light mainLight = GetMainLight();
                float ndl = saturate(dot(n, mainLight.direction));
                float3 ambient = SampleSH(n);
                col.rgb = col.rgb * (ambient * 0.9 + mainLight.color * (0.35 + 0.65 * ndl));

                float fres = pow(1.0 - saturate(dot(n, viewDir)), 4.0);
                float3 skyCol = lerp(float3(0.62, 0.8, 0.93), float3(0.03, 0.05, 0.09), _Night);
                skyCol = lerp(skyCol, float3(0.35, 0.38, 0.42), _Storm);
                col.rgb = lerp(col.rgb, skyCol, fres * 0.55);

                float3 h = normalize(mainLight.direction + viewDir);
                float spec = pow(saturate(dot(n, h)), 160.0) * 3.0 * (1.0 - _Storm);
                col.rgb += spec * mainLight.color;

                float foam = saturate(1.0 - depth / 0.9);
                foam *= 0.6 + 0.4 * sin(_Time.y * 2.0 + i.positionWS.x * 0.7 + i.positionWS.z * 0.5);
                col.rgb = lerp(col.rgb, _FoamColor.rgb * (ambient + mainLight.color * 0.6), saturate(foam) * 0.85);
                col.a = saturate(max(col.a, foam));

                if (!front) { col.rgb *= 0.55; col.a = 0.75; }
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return col;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
