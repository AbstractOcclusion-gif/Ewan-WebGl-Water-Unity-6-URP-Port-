// WebGL Water - shared underwater fog (Beer-Lambert absorption)
// Included by the water surface AND the lit receivers (objects, pool) so fog is
// consistent however you look at the water. Parameters are GLOBAL, published once
// per frame by WaterController, so there is a single place to tune them.
#ifndef WEBGL_WATER_FOG_INCLUDED
#define WEBGL_WATER_FOG_INCLUDED

float4 _WaterFogColor;    // deep-water colour (inscattering target)
float4 _WaterExtinction;  // per-channel extinction (red highest -> dies first)
float  _WaterFogDensity;   // overall multiplier
float  _WaterFogEnabled;   // 0 / 1

// Absorb 'color' over 'dist' world units of water. No-op when disabled.
float3 ApplyWaterFog(float3 color, float dist)
{
    if (_WaterFogEnabled < 0.5) return color;
    float3 absorb = exp(-_WaterExtinction.rgb * (_WaterFogDensity * max(0.0, dist)));
    return lerp(_WaterFogColor.rgb, color, absorb);
}

// Length of the camera->fragment segment that lies below the water plane y=level.
// Handles camera above or below the surface; returns 0 for fully-above segments.
float WaterPathLength(float3 fragWS, float3 camWS, float level)
{
    float len = length(fragWS - camWS);
    float yC = camWS.y, yF = fragWS.y;
    bool camUnder  = yC <= level;
    bool fragUnder = yF <= level;
    if (camUnder && fragUnder) return len;     // whole segment underwater
    if (!camUnder && !fragUnder) return 0.0;   // whole segment above water
    float t = (level - yC) / (yF - yC);        // crossing fraction in [0,1]
    return (fragUnder ? (1.0 - t) : t) * len;  // underwater portion only
}

#endif // WEBGL_WATER_FOG_INCLUDED
