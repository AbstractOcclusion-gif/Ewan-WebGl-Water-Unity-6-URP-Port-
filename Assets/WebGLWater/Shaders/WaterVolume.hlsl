// WebGL Water - volume placement frame (Unity 6 / URP port)
//
// Maps the normalised pool box (x,z in [-1,1], surface y=0, floor y=-1) into world
// space with a full transform so the volume can be moved, ROTATED (incl. tilt) and
// sized NON-UNIFORMLY (rectangular footprint + independent depth) without scaling any
// GameObject transforms:
//
//   world = center + Rotation * (pool * extent)        (extent applied per-axis)
//   pool  = (Rotation^-1 * (world - center)) / extent
//
// Because extent is non-uniform, directions are NOT angle-preserving under this map,
// so the surface shader does its reflection/refraction in WORLD space and only uses
// these helpers to move points/rays in and out of the unit box. Identity defaults
// (extent 1, rotation I) reproduce the original 1:1 pool exactly.
#ifndef WEBGL_WATER_VOLUME_INCLUDED
#define WEBGL_WATER_VOLUME_INCLUDED

float3   _VolumeCenter; // world position of the pool origin (centre of the surface)
float3   _VolumeExtent; // world half-size per pool unit, per axis (x,y,z)
float4x4 _VolumeRot;    // rotation (upper 3x3 used); identity when unset

float3 VolumeExtentSafe()
{
    return float3(_VolumeExtent.x > 1e-5 ? _VolumeExtent.x : 1.0,
                  _VolumeExtent.y > 1e-5 ? _VolumeExtent.y : 1.0,
                  _VolumeExtent.z > 1e-5 ? _VolumeExtent.z : 1.0);
}

// Rotation, guarded to identity when the global hasn't been published yet.
float3x3 VolumeRot()
{
    float3x3 r = (float3x3)_VolumeRot;
    return abs(determinant(r)) < 0.5 ? float3x3(1,0,0, 0,1,0, 0,0,1) : r;
}

float3 PoolToWorld(float3 poolPos)
{
    return _VolumeCenter + mul(VolumeRot(), poolPos * VolumeExtentSafe());
}

float3 WorldToPool(float3 worldPos)
{
    return mul(transpose(VolumeRot()), worldPos - _VolumeCenter) / VolumeExtentSafe();
}

// World direction -> pool direction (NOT normalised; valid for box intersection).
float3 WorldDirToPool(float3 worldDir)
{
    return mul(transpose(VolumeRot()), worldDir) / VolumeExtentSafe();
}

// Pool-space surface normal -> world normal (inverse-transpose of the linear map).
float3 PoolNormalToWorld(float3 poolNormal)
{
    return normalize(mul(VolumeRot(), poolNormal / VolumeExtentSafe()));
}

#endif // WEBGL_WATER_VOLUME_INCLUDED
