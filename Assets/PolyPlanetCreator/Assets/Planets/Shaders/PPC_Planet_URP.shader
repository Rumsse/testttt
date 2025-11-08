Shader "TS/PPC/Planet_URP"
{
    Properties
    {
        // [Header(Settings)]
        [KeywordEnum(Perspective, Orthographic)] _Camera("Camera", Float) = 0.0
        [KeywordEnum(Unity, Central, Custom)] _Lighting("Lighting", Float) = 0.0
        _LightDirection("Light Direction", Vector) = (-1,-1,0,0)
        [Toggle]_PolyLiquid("Poly Liquid", Float) = 0

        // [Header(Main)]
        [KeywordEnum(Average, Min, Max)] _TerrainColoring("Terrain Coloring", Float) = 0
        _DarkSide("Dark Side", Range(0.0, 1.0)) = 0.666

        // [Header(Liquid)]
        _LiquidColor("Liquid Color", Color) = (0.1,0.45,0.8,1)
        _LiquidHeight("Liquid Height", Range(0.99, 1.51)) = 0.99
        _SpecularColor("Specular Color", Color) = (1,1,1,1)
        _SpecularHighlight("Specular Highlight", Range(1.0, 64.0)) = 3.0

        // [Header(Core)]
        _CoreColor("Core Color", Color) = (1,0.8,0.4,1)

        // [Header(Rim)]
        _RimColor("Rim Color", Color) = (0.6,0.85,1.0,1.0)
        _RimPower("Rim Power", Range(1.0, 8.0)) = 3.0
        _RimOpacity("Rim Opacity", Range(0.0, 1.0)) = 0.5

        _MainTex("Main Tex", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 200

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "UnityCG.cginc"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 worldNormal : TEXCOORD1;
                float4 color : COLOR;
                float2 uv : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
                float _Camera;
                float _Lighting;
                float4 _LightDirection;
                float _PolyLiquid;
                float _TerrainColoring;
                float _DarkSide;
                float4 _LiquidColor;
                float _LiquidHeight;
                float4 _SpecularColor;
                float _SpecularHighlight;
                float4 _CoreColor;
                float4 _RimColor;
                float _RimPower;
                float _RimOpacity;
            CBUFFER_END

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            Varyings vert(Attributes v)
            {
                Varyings o;
                float4 worldPos4 = mul(unity_ObjectToWorld, v.positionOS);
                o.worldPos = worldPos4.xyz;
                o.worldNormal = normalize(mul((float3x3)unity_ObjectToWorld, v.normalOS));
                o.positionCS = TransformWorldToHClip(o.worldPos);
                o.color = v.color;
                o.uv = v.uv;

                // store vertex distance so frag can use it (approximation of original .w usage)
                o.color.a = length(v.positionOS.xyz);

                return o;
            }

            // simple Blinn-Phong-like lighting (approx)
            float3 SimpleLighting(float3 normalWS, float3 viewDir, float3 lightDir, out float NdotL)
            {
                NdotL = saturate(dot(normalWS, lightDir));
                float3 diffuse = NdotL * 1.0;
                float3 halfv = normalize(lightDir + viewDir);
                float NdotH = saturate(dot(normalWS, halfv));
                float spec = pow(NdotH, _SpecularHighlight);
                return float3(diffuse + spec, 0).rgb;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 baseCol = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                half4 albedo = baseCol * IN.color;

                float3 viewDir = normalize(_WorldSpaceCameraPos - IN.worldPos);
                float3 lightDir = normalize(_LightDirection.xyz);

                float NdotL;
                float3 lit = SimpleLighting(IN.worldNormal, viewDir, lightDir, NdotL);

                float darkFactor = lerp(1.0, _DarkSide, saturate(1.0 - NdotL));
                float finalLight = min(NdotL, 1.0) * darkFactor;

                float localRadius = IN.color.a;
                float liquidMask = step(localRadius, _LiquidHeight);

                float specular = 0.0;
                if (_PolyLiquid > 0.5)
                {
                    float3 refl = reflect(-normalize(lightDir * 2 + viewDir), IN.worldNormal);
                    specular = saturate(dot(refl, IN.worldNormal));
                    specular = specular * specular;
                    specular = pow(specular, _SpecularHighlight);
                }

                float3 color = albedo.rgb * finalLight;

                if (liquidMask > 0.5)
                {
                    if (_PolyLiquid > 0.5)
                        color = lerp(color, lerp(_LiquidColor.rgb, _SpecularColor.rgb, specular), 0.85);
                    else
                        color = lerp(color, _LiquidColor.rgb, 0.5);
                }

                float dist = saturate(localRadius * 2 - 1);
                float3 coreMix = lerp(_CoreColor.rgb * 3, _CoreColor.rgb, dist);
                color = lerp(coreMix, color, dist);

                float rimFactor = pow(saturate(1.0 - dot(viewDir, normalize(IN.worldNormal))), _RimPower) * _RimOpacity;
                color = lerp(color, _RimColor.rgb, rimFactor);

                return half4(color, 1.0);
            }

            ENDHLSL
        }
    }

    FallBack "Hidden/InternalErrorShader"
}