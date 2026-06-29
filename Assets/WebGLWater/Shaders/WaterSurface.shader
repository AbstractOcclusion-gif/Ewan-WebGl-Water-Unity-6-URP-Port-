// WebGL Water - water surface (Unity 6 / URP port)
// Hybrid reflection (analytic sky/pool -> planar -> SSR) and refraction (analytic
// pool, or real screen-space refraction of the live scene). All extras are
// keyword-gated and default off, so the base look matches the original.
// One material is instanced twice by the scene builder: an "above water" object
// (_Underwater = 0, Cull Front) and an "under water" object (_Underwater = 1,
// Cull Back), sharing the same displaced grid mesh.
Shader "WebGLWater/WaterSurface"
{
    Properties
    {
        _Underwater ("Underwater (0/1)", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 1 // Front
        _ReflectionStrength ("Reflection Strength", Range(0,1)) = 1.0

        [Header(Hybrid Reflections)]
        [Toggle(_USE_PLANAR)] _UsePlanar ("Use Planar Reflection", Float) = 0
        [Toggle(_USE_SSR)]    _UseSSR    ("Use Screen Space Reflection", Float) = 0
        _ReflectionDistortion ("Reflection Distortion", Range(0,0.2)) = 0.05
        _SSRStrength  ("SSR Strength", Range(0,1)) = 1.0
        _SSRStepSize  ("SSR Step Size (world units)", Range(0.005,0.2)) = 0.03
        _SSRMaxSteps  ("SSR Max Steps", Range(8,64)) = 24
        _SSRThickness ("SSR Thickness", Range(0.01,1.0)) = 0.2

        [Header(Real Transparency)]
        [Toggle(_REAL_REFRACTION)] _RealRefraction ("Real (Screen-Space) Refraction", Float) = 0
        _RefractionDistortion ("Refraction Distortion", Range(0,0.2)) = 0.05
    }
    SubShader
    {
        // Transparent queue so _CameraOpaqueTexture / _CameraDepthTexture hold the
        // scene WITHOUT the water (required for SSR and screen-space refraction).
        // Still ZWrite On + Blend Off: we compute the final opaque-looking colour
        // ourselves (incl. refraction), we just need to draw after the opaque copy.
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }
        Pass
        {
            Cull [_Cull]
            ZWrite On
            ZTest LEqual

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.0
            #pragma shader_feature_local _USE_PLANAR
            #pragma shader_feature_local _USE_SSR
            #pragma shader_feature_local _REAL_REFRACTION
            #include "UnityCG.cginc"
            #include "WaterCommon.hlsl"

            float _Underwater;
            float _ReflectionStrength;
            float3 _SunColor; // Unity directional light color * intensity (global)

            sampler2D _PlanarReflectionTex;
            float     _ReflectionDistortion;

            // URP scene textures (enable Opaque Texture + Depth Texture in the URP asset)
            sampler2D _CameraOpaqueTexture;
            sampler2D _CameraDepthTexture;

            float _SSRStrength, _SSRStepSize, _SSRMaxSteps, _SSRThickness;
            float _RefractionDistortion;

            // Screen-space ray march along 'dir' from world 'p0'. On a depth hit it
            // returns the scene colour and sets hit=1; otherwise hit=0 (caller falls
            // back to planar / analytic). Kept deliberately simple + linear; tune the
            // step size / thickness in the material.
            float3 MarchSSR(float3 p0, float3 dir, out float hit)
            {
                hit = 0.0;
                float3 p = p0;
                int maxSteps = (int)_SSRMaxSteps;
                [loop]
                for (int s = 0; s < maxSteps; s++)
                {
                    p += dir * _SSRStepSize;
                    float4 clip = mul(UNITY_MATRIX_VP, float4(p, 1.0));
                    if (clip.w <= 0.0) break;
                    float2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
                    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

                    // explicit-LOD samples: safe inside a divergent loop (WebGPU)
                    float sceneDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, float4(uv, 0, 0)));
                    float rayDepth   = -mul(UNITY_MATRIX_V, float4(p, 1.0)).z; // positive eye depth
                    if (rayDepth > sceneDepth && (rayDepth - sceneDepth) < _SSRThickness)
                    {
                        hit = 1.0;
                        return tex2Dlod(_CameraOpaqueTexture, float4(uv, 0, 0)).rgb;
                    }
                }
                return 0.0;
            }

            struct appdata { float4 vertex : POSITION; };
            struct v2f
            {
                float4 pos      : SV_POSITION;
                float3 position : TEXCOORD0;
                float4 screenPos: TEXCOORD1;
            };

            v2f vert(appdata v)
            {
                v2f o;
                float4 info = tex2Dlod(_WaterTex, float4(v.vertex.xy * 0.5 + 0.5, 0, 0));
                float3 position = v.vertex.xzy;   // grid XY plane -> world (x, 0, z)
                position.y += info.r;
                o.position = position;
                o.pos = mul(UNITY_MATRIX_VP, float4(position, 1.0));
                o.screenPos = ComputeScreenPos(o.pos);
                return o;
            }

            // Sample the planar reflection RT at the fragment's screen UV, nudged
            // by the surface normal so ripples wobble the mirror image.
            float3 SamplePlanarReflection(float4 screenPos, float3 normal)
            {
                float2 uv = screenPos.xy / max(screenPos.w, 1e-5);
                uv += normal.xz * _ReflectionDistortion;
                return tex2D(_PlanarReflectionTex, saturate(uv)).rgb;
            }

            float3 getSurfaceRayColor(float3 origin, float3 ray, float3 waterColor)
            {
                float3 color;
                if (ray.y < 0.0)
                {
                    float2 t = IntersectCube(origin, ray, float3(-1.0, -POOL_HEIGHT, -1.0), float3(1.0, 2.0, 1.0));
                    color = GetWallColor(origin + ray * t.y);
                }
                else
                {
                    float2 t = IntersectCube(origin, ray, float3(-1.0, -POOL_HEIGHT, -1.0), float3(1.0, 2.0, 1.0));
                    float3 hit = origin + ray * t.y;
                    if (hit.y < 2.0 / 12.0)
                    {
                        color = GetWallColor(hit);
                    }
                    else
                    {
                        color = texCUBE(_Sky, ray).rgb;
                        // sun glint - direction from _LightDir, tint/brightness from the Unity sun
                        color += float3(10.0, 8.0, 6.0) * _SunColor * pow(max(0.0, dot(_LightDir, ray)), 5000.0);
                    }
                }
                if (ray.y < 0.0) color *= waterColor;
                return color;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float2 coord = i.position.xz * 0.5 + 0.5;
                float4 info = tex2D(_WaterTex, coord);

                // make the water look more "peaked"
                [unroll]
                for (int k = 0; k < 5; k++)
                {
                    coord += info.ba * 0.005;
                    info = tex2D(_WaterTex, coord);
                }

                float3 normal = float3(info.b, sqrt(1.0 - dot(info.ba, info.ba)), info.a);
                float3 incomingRay = normalize(i.position - _Eye);

                if (_Underwater > 0.5)
                {
                    normal = -normal;
                    float3 reflectedRay = reflect(incomingRay, normal);
                    float3 refractedRay = refract(incomingRay, normal, IOR_WATER / IOR_AIR);
                    float fresnel = lerp(0.5, 1.0, pow(1.0 - dot(normal, -incomingRay), 3.0));

                    float3 reflectedColor = getSurfaceRayColor(i.position, reflectedRay, UNDERWATER_COLOR);
                    float3 refractedColor = getSurfaceRayColor(i.position, refractedRay, float3(1.0, 1.0, 1.0)) * float3(0.8, 1.0, 1.1);

                    float tUnder = (1.0 - fresnel) * length(refractedRay);
                    tUnder = lerp(1.0, tUnder, _ReflectionStrength); // strength 0 = fully refracted
                    return float4(lerp(reflectedColor, refractedColor, tUnder), 1.0);
                }
                else
                {
                    float3 reflectedRay = reflect(incomingRay, normal);
                    float3 refractedRay = refract(incomingRay, normal, IOR_AIR / IOR_WATER);
                    float fresnel = lerp(0.25, 1.0, pow(1.0 - dot(normal, -incomingRay), 3.0));

                    float3 reflectedColor = getSurfaceRayColor(i.position, reflectedRay, ABOVEWATER_COLOR);
                    float3 refractedColor = getSurfaceRayColor(i.position, refractedRay, ABOVEWATER_COLOR);

                    // ---- Reflection: analytic -> planar -> SSR (SSR wins where it hits) ----
                #if defined(_USE_PLANAR)
                    reflectedColor = SamplePlanarReflection(i.screenPos, normal);
                #endif
                #if defined(_USE_SSR)
                    float ssrHit;
                    float3 ssr = MarchSSR(i.position, reflectedRay, ssrHit);
                    reflectedColor = lerp(reflectedColor, ssr, ssrHit * _SSRStrength);
                #endif

                    // ---- Real transparency: sample the actual scene behind the surface,
                    // instead of the analytic pool. Beer-Lambert depth fog lands in Phase 4. ----
                #if defined(_REAL_REFRACTION)
                    float2 ruv = i.screenPos.xy / max(i.screenPos.w, 1e-5);
                    ruv += normal.xz * _RefractionDistortion;
                    refractedColor = tex2D(_CameraOpaqueTexture, saturate(ruv)).rgb * ABOVEWATER_COLOR;
                #endif

                    return float4(lerp(refractedColor, reflectedColor, fresnel * _ReflectionStrength), 1.0);
                }
            }
            ENDCG
        }
    }
}
