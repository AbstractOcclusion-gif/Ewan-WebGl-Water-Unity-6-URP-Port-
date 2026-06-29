// WebGL Water - obstacle footprint pass (Unity 6 / URP port)
// Drawn top-down by WaterObstacle via a CommandBuffer with an orthographic VP that
// maps the pool's x,z in [-1,1] onto the render target. Each interactable object is
// drawn with Cull Back so its silhouette covers each column once, writing a per-
// object "submerged amount" (set from C# in a MaterialPropertyBlock) into R.
// Additive blending lets several objects accumulate where they overlap.
Shader "WebGLWater/ObstacleDepth"
{
    Properties
    {
        _SubmergedAmount ("Submerged Amount", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        Pass
        {
            Cull Back
            ZWrite Off
            ZTest Always
            Blend One One   // additive across objects

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            float _SubmergedAmount;

            struct appdata { float4 vertex : POSITION; };
            struct v2f { float4 pos : SV_POSITION; };

            v2f vert(appdata v)
            {
                v2f o;
                // Uses the view/projection set on the CommandBuffer (top-down ortho).
                o.pos = UnityObjectToClipPos(v.vertex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                return fixed4(_SubmergedAmount, 0, 0, 0);
            }
            ENDCG
        }
    }
}
