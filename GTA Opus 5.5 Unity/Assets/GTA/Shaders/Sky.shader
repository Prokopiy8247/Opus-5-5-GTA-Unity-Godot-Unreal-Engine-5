Shader "Halcyon/Sky"
{
    Properties
    {
        _ZenithDay("Zenith Day", Color) = (0.20, 0.45, 0.82, 1)
        _HorizonDay("Horizon Day", Color) = (0.70, 0.85, 0.96, 1)
        _ZenithNight("Zenith Night", Color) = (0.008, 0.016, 0.045, 1)
        _HorizonNight("Horizon Night", Color) = (0.05, 0.08, 0.15, 1)
        _SunsetColor("Sunset", Color) = (1.0, 0.48, 0.22, 1)
        _SunDir("Sun Direction", Vector) = (0, 1, 0, 0)
        _Night("Night", Range(0, 1)) = 0
        _Cloud("Cloud Cover", Range(0, 1)) = 0.3
        _Overcast("Overcast", Range(0, 1)) = 0
    }
    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "PreviewType" = "Skybox" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ZenithDay, _HorizonDay, _ZenithNight, _HorizonNight, _SunsetColor;
                float4 _SunDir;
                float _Night, _Cloud, _Overcast;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 dir : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.dir = v.positionOS.xyz;
                return o;
            }

            float Hash(float3 p) { p = frac(p * 0.3183099 + 0.1); p *= 17.0; return frac(p.x * p.y * p.z * (p.x + p.y + p.z)); }
            float Noise(float2 p)
            {
                float2 i = floor(p); float2 f = frac(p);
                float a = Hash(float3(i, 1)), b = Hash(float3(i + float2(1, 0), 1)), c = Hash(float3(i + float2(0, 1), 1)), d = Hash(float3(i + float2(1, 1), 1));
                float2 u = f * f * (3 - 2 * f);
                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }
            float Fbm(float2 p) { float s = 0, a = 0.5; for (int k = 0; k < 4; k++) { s += Noise(p) * a; p *= 2.03; a *= 0.5; } return s; }

            half4 frag(Varyings i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float3 sunDir = normalize(_SunDir.xyz);
                float h = saturate(d.y);
                float horizonK = pow(1.0 - h, 3.0);
                float3 day = lerp(_ZenithDay.rgb, _HorizonDay.rgb, horizonK);
                float3 night = lerp(_ZenithNight.rgb, _HorizonNight.rgb, horizonK);
                float3 col = lerp(day, night, _Night);
                // sunset glow around the sun near the horizon
                float sunH = sunDir.y;
                float sunsetK = saturate(1.0 - abs(sunH) * 4.0);
                float towardSun = saturate(dot(d, sunDir) * 0.5 + 0.5);
                col = lerp(col, _SunsetColor.rgb, sunsetK * pow(towardSun, 4.0) * horizonK * 0.95);
                // sun disc & halo
                float sd = dot(d, sunDir);
                float disc = smoothstep(0.9993, 0.9997, sd);
                float halo = pow(saturate(sd), 180.0) * 0.6 + pow(saturate(sd), 12.0) * 0.12;
                col += (disc * 6.0 + halo) * lerp(float3(1, 0.95, 0.85), float3(1, 0.6, 0.35), sunsetK) * (1.0 - _Overcast * 0.85) * step(-0.05, sunH);
                // moon opposite to the sun
                float md = dot(d, -sunDir);
                col += smoothstep(0.9989, 0.9993, md) * float3(0.85, 0.9, 1.0) * _Night * 1.5;
                // stars
                float3 sp = floor(d * 380.0);
                float star = step(0.9965, Hash(sp)) * h * _Night * (1.0 - _Overcast);
                col += star * (0.6 + 0.4 * sin(_Time.y * 3.0 + sp.x));
                // clouds: projected plane
                if (d.y > 0.0)
                {
                    float2 cp = d.xz / (d.y + 0.12) * 1.6 + _Time.y * float2(0.012, 0.004);
                    float n = Fbm(cp * 2.2);
                    float cover = lerp(0.62, 0.18, saturate(_Cloud + _Overcast * 0.6));
                    float c = smoothstep(cover, cover + 0.22, n) * saturate(d.y * 6.0);
                    float3 cloudCol = lerp(float3(1, 1, 1), float3(0.55, 0.57, 0.6), _Overcast);
                    cloudCol = lerp(cloudCol, float3(0.08, 0.09, 0.12), _Night * 0.9);
                    cloudCol = lerp(cloudCol, _SunsetColor.rgb, sunsetK * 0.5);
                    col = lerp(col, cloudCol, c * (0.85 + _Overcast * 0.15));
                }
                col = lerp(col, lerp(float3(0.55, 0.58, 0.62), float3(0.04, 0.05, 0.07), _Night), _Overcast * 0.55);
                // below horizon: fade toward a sea-haze colour
                if (d.y < 0.0) col = lerp(col, lerp(float3(0.42, 0.55, 0.62), float3(0.02, 0.03, 0.05), _Night), saturate(-d.y * 6.0));
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
    FallBack Off
}
