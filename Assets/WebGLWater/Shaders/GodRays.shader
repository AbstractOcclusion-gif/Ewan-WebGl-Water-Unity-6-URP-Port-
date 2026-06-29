// WebGL Water - underwater god rays (Unity 6 / URP port)
// A self-contained additive VOLUME: a box mesh spanning the pool interior
// (x,z in [-1,1], y in [-1,0]). The fragment ray-marches the view ray through the
// volume and accumulates the projected caustic intensity at each step, so bright
// focused light becomes vertical shafts that flicker in sync with the floor
// caustics and follow the sun. No post-processing feature required.
//
// Renders after the water (Transparent+100), additively, ignoring the water
// surface depth; occlusion against solid geometry is done per-step against the
// camera depth texture (which contains opaque geometry only).
Shader "WebGLWater/GodRays"
{
    Properties
    {
        _GodRayColor ("God Ray Color", Color) = (1.0, 0.97, 0.85, 1)
        _GodRayDensity ("Density", Range(0,6)) = 1.5
        _GodRaySteps ("Steps", Range(8,64)) = 24
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+100" }
        Pass
        {
            Blend One One       // additive glow
            ZWrite Off
            ZTest Always        // not occluded by the (transparent) water surface
            Cull Front          // render back faces so the volume covers the screen

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.0
            #include "UnityCG.cginc"
            #include "WaterCommon.hlsl"

            sampler2D _CameraDepthTexture;
            float3 _SunColor;            // global, sun colour * intensity
            float4 _GodRayColor;
            float  _GodRayDensity, _GodRaySteps;

            struct appdata { float4 vertex : POSITION; };
            struct v2f
            {
                float4 pos  : SV_POSITION;
                float3 wpos : TEXCOORD0;
                float4 spos : TEXCOORD1;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.wpos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.pos  = UnityObjectToClipPos(v.vertex);
                o.spos = ComputeScreenPos(o.pos);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 ro = _WorldSpaceCameraPos;
                float3 rd = normalize(i.wpos - ro);

                // clip the view ray to the pool interior (floor y=-1 to surface y=0)
                float2 t = IntersectCube(ro, rd, float3(-1.0, -1.0, -1.0), float3(1.0, 0.0, 1.0));
                float tEnter = max(t.x, 0.0);
                float tExit  = t.y;
                if (tExit <= tEnter) return fixed4(0,0,0,0);

                float2 uv = i.spos.xy / max(i.spos.w, 1e-5);
                float sceneEye = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));

                int steps = (int)_GodRaySteps;
                float dt = (tExit - tEnter) / steps;
                float3 refractedLight = -refract(-_LightDir, float3(0,1,0), IOR_AIR / IOR_WATER);

                float accum = 0.0;
                [loop]
                for (int s = 0; s < steps; s++)
                {
                    float tt = tEnter + (s + 0.5) * dt;
                    float3 p = ro + rd * tt;
                    float pe = -mul(UNITY_MATRIX_V, float4(p, 1.0)).z; // eye depth of sample
                    if (pe > sceneEye) break;                         // behind solid geometry

                    // project the sample down the refracted light onto the caustic map
                    float2 cuv = 0.75 * (p.xz - p.y * refractedLight.xz / refractedLight.y) * 0.5 + 0.5;
                    accum += tex2Dlod(_CausticTex, float4(cuv, 0, 0)).r;
                }
                accum *= dt * _GodRayDensity;

                return fixed4(_GodRayColor.rgb * _SunColor * accum, 1.0);
            }
            ENDCG
        }
    }
}
