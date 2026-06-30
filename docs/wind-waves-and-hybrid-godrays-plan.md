# Wind-driven lake waves + hybrid shadow god rays — implementation plan

Status: **IMPLEMENTED** (2026-06-30). Built per the agreed direction below.
Defaults locked: pool half-extent **10 m**, wind **~3 m/s light breeze**, **from the west**
(`windFromDegrees = 0`, blowing toward +X).

Files added: `Shaders/WaterWaves.hlsl`, `Shaders/WaterVolume.hlsl`, `Scripts/WaterWaveBank.cs`.
Files changed: `Scripts/WaterController.cs`, `Scripts/WaterObstacle.cs`, `Shaders/WaterSurface.shader`,
`Shaders/PoolWall.shader`, `Shaders/WaterReceiver.shader`, `Shaders/GodRays.shader`,
`Editor/WaterSceneBuilder.cs`.

### Follow-up (2026-06-30): de-linearized waves + resizable/placeable volume

**Waves were too directional ("river flow").** `WaterWaveBank.Generate` now golden-ratio stratifies
headings across a ~83 deg fan and sends ~1/3 of components UPWIND, so crests cross and interfere.
Measured directional coherence fell from ~1.0 to 0.24. `waveDirectionSpread` default lowered 6 -> 2
(higher = tighter/river-like, lower = choppier).

**The volume is now resizable/placeable** via a uniform frame `world = _VolumeCenter + pool * _VolumeScale`
(`Shaders/WaterVolume.hlsl` + `volumeCenter`/`volumeScale` on the controller). Uniform scale keeps
directions/normals/refraction valid; defaults (center 0, scale 1) reproduce the original 1:1 pool exactly.
Routed through it: surface, pool walls, god rays (now a pool-space box mesh with identity transform),
the object receiver, buoyancy (`TryGet*` are now WORLD-space in/out), `AddRipple`, mouse-pick, splash,
and the obstacle ortho camera. Mesh bounds enlarged to avoid culling a scaled volume.

Interactions to remember:
- `poolHalfExtentMeters` (wave wavelength scale) and `volumeScale` are independent; set them equal for
  physically intuitive results (both = the pool's physical half-extent in metres).
- The orbit camera isn't auto-reframed; raise its distance/pivot for a large `volumeScale`.
- `volumeScale` is read once at startup for the obstacle map - set it before Play.

### Follow-up 2 (2026-06-30): full TRS volume + exact world-space refraction

The uniform `_VolumeScale` was upgraded to a **full transform**: `world = center + Rotation * (pool * extent)`
with `_VolumeCenter` (float3), `_VolumeExtent` (float3, per-axis half-size = width/depth/length) and
`_VolumeRot` (matrix). Controller fields are now `volumeCenter`, `volumeExtent`, `volumeEuler`. This gives
rotation, rectangular footprint, independent depth, and tilt.

Because non-uniform extent is not angle-preserving, the **surface reflection/refraction was rewritten to
world space**: the surface normal is transported with the inverse-transpose (`PoolNormalToWorld = R*(n/extent)`,
verified to keep normals perpendicular to transformed tangents), rays reflect/refract in world, the sky/sun
use world directions, and the pool box is intersected in pool space via `WorldDirToPool`. Fog distance is the
world chord. So rotated/rectangular volumes look correct, not sheared.

Interaction also moved to the frame: buoyancy samples submersion in pool space with lift along the volume up
(`TrySampleSubmersion`, works under tilt); mouse-pick intersects the oriented surface plane; the obstacle ortho
looks down the volume up axis with the right extents. The click ripple is world-sized (radius / horizontal
extent, height / depth extent) so it no longer scales with the pool. TRS round-trip verified exact (1.3e-15).

Caveats: tilt is exact for rendering; floating is evaluated in-frame so it also works tilted, but a steeply
tilted "lake" is physically odd. `volumeExtent`/`volumeEuler` are read once at startup for the obstacle map -
set before Play. Mesh bounds are large to avoid culling; keep `volumeCenter` within a few hundred units.

### Editor test checklist
1. Rebuild via Tools > WebGL Water > Build Scene (regenerates the god-ray box mesh).
2. Default scene (extent 1,1,1 / euler 0) should look identical to before.
3. `volumeExtent = (3,1,8)`: rectangular pool, reflections should NOT shear; crate floats; clicks ripple.
4. `volumeEuler.y = 30`: whole pool rotates; reflections/refraction stay correct.
5. `volumeExtent.y = 0.3`: shallow; `= 3`: deep - fog/floor depth should track.
6. Lower `waveDirectionSpread` toward 1.5 for choppier crests.
7. Watch the WebGPU console for the prior crash signature.

Verification done here: CPU<->HLSL evaluator parity is exact (height diff 0, slope diff 6.7e-16);
`Mobile_RPAsset` and `PC_RPAsset` both have Depth + Opaque textures ON; both support main-light
shadows (Mobile 1 cascade / PC 4); no screen-space-shadow feature, so the shadowmap-only keyword
set is correct. Still needs an in-editor compile + WebGPU smoke test on your machine.

## Decisions locked

1. **Wave layer = analytic, wind-driven** (Option B). An ambient spectral wave layer composited
   on top of the existing finite-difference heightfield sim. No FFT, no tiling textures.
2. **Objects ride the wind waves.** Buoyancy samples the same wave function the shader uses.
3. **God rays stay caustic-driven, gain shadow shafts** via `caustic x MainLightRealtimeShadow`
   (hybrid). The clean caustic flicker is preserved; occluders carve dark shafts.

## Why analytic waves solve the tiling question

The waves are evaluated as a continuous function of **world XZ**, so there is no repeating patch
and therefore no tiling to hide — the anti-tiling machinery FFT needs simply does not apply. Over
a 1-50 m view the only distance artifact is **normal aliasing** (short waves shimmering at grazing
angles), handled geometrically: fade out high-frequency wave octaves with distance and let surface
roughness rise to absorb the lost detail. No atlas, no domain-warp pass.

---

## Workstream A — wind-driven spectral wave layer

### Single source of truth: a wave bank

One `WaveBank` built in C# from the wind state, then (a) published to shaders as global arrays and
(b) evaluated on the CPU for buoyancy. The Gerstner/sine evaluator exists in both HLSL and C#, but
both are driven by the *same* generated parameters, so they stay in lockstep. Keep both evaluators
tiny and cross-check them in a test (see Verification).

Inputs (the only knobs an artist touches):

- `windDirection` (degrees) and `windSpeed` (m/s) — drive everything below.
- `metersPerPoolUnit` — maps the normalised `[-1,1]` pool to physical size (pool half-extent in
  metres). This is the "1 m to 50 m" control. Fetch is derived from it.
- `waveCount` — number of Gerstner/sine components (start ~8).

Derived per component from a **fetch-limited JONSWAP spectrum** (short fetch => small steep lake
chop, never a fully developed sea):

- peak frequency from `windSpeed` + fetch (Kitaigorodskii / JONSWAP relation),
- per-component amplitude from `sqrt(2 * S(f) * df)`,
- direction sampled around `windDirection` with a **narrow `cos^2s` spread** (lakes are
  directionally tight),
- wavenumber `k` from the deep-water dispersion `omega^2 = g*k`,
- random phase,
- per-component steepness `Q` clamped so crests never loop (trochoid stays single-valued).

No magic numbers in code: gravity, JONSWAP `gamma` (~3.3), spread exponent `s`, steepness clamp, and
the distance-LOD band are all named constants.

### Rendering (`WaterSurface.shader`, vertex + fragment)

- Vertex `vert()` currently does `position.y += info.r` from the sim. Add the wave-bank
  displacement at **world XZ** on top: `position += WaveDisplacement(worldXZ, _Time)`.
- Fragment: combine the analytic wave normal (from the bank's Jacobian) with the sampled heightfield
  normal in `info.ba`. The heightfield ripples ride on the wind-wave surface.
- Distance LOD: drop the highest-frequency components past a named distance band; raise roughness to
  compensate so the highlight doesn't sparkle-alias.

> The surface shader is legacy `CGPROGRAM`. The wave evaluator goes in a shared `.hlsl` include so it
> is written once and pulled into both the above-water and under-water passes.

### Scale / coordinate note

`worldXZ = poolXZ * metersPerPoolUnit`. The wave function takes metres, so changing
`metersPerPoolUnit` rescales the whole sea consistently (longer fetch => longer peak wavelength).

---

## Workstream B — objects ride the waves

### Integration point

`WaterController.TryGetSurface(x,z, out height, out flow)` and `TryGetWaterHeight` already feed
`WaterBuoyancy`. Add the wave-bank contribution there:

```
height += WaveHeightCPU(worldXZ, time);     // same bank, CPU evaluator
flow   += WaveSlopeCPU(worldXZ, time);      // adds wind-wave drift/tilt
```

Result: floating objects lift, tilt, and drift on the wind chop, with the existing interactive
ripples (drops, impacts, obstacle pushback) still layered on top.

### Important simplification

Full Gerstner displaces points **horizontally** too, which makes "height at world (x,z)" parametric
rather than a clean function — bad for the CPU sampler. For buoyancy use the **vertical-only
(sum-of-sines) approximation** of the bank: exact to sample, and at lake-scale low steepness the
difference from full Gerstner is visually negligible. The *shader* can still use the full Gerstner
pinch for the look. Document this as a deliberate accuracy/perf tradeoff.

---

## Workstream C — hybrid shadow shafts

### Port `GodRays.shader` from legacy CG to URP HLSL

Current pass is `CGPROGRAM` + `UnityCG.cginc`. Convert to `HLSLPROGRAM` and include the same URP
libraries already used by `WaterReceiver.shader` / `PoolWall.shader`:

```
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
```

### Inside the existing march loop

Per step, after computing the caustic contribution `c`, multiply by main-light shadow visibility:

```
float4 shadowCoord = TransformWorldToShadowCoord(p);   // p = current sample, world space
float shadow = MainLightRealtimeShadow(shadowCoord);   // cascade selected automatically
accum += c * shadow;
```

This keeps the focused, flickering caustic shafts **and** lets occluders (crate, floating objects)
punch dark silhouette beams through the haze. Both occluders compose: the rippled surface chops the
light into dancing shafts, solids carve clean voids.

### Cost / stability guards

- One shadow lookup per march step. Keep `_GodRaySteps` modest and consider a half-res pass given
  the prior **mobile WebGPU stack-overflow** history — gate behind the existing capability check.
- Keep the explicit-LOD sampling discipline already used elsewhere (safe inside divergent loops on
  the WebGPU backend).

---

## Mobile / WebGPU gates

Per the known issues, before merge:

- Confirm Opaque + Depth Texture remain ON in **Mobile_RPAsset** (the wave/fog/god-ray paths all
  depend on scene depth).
- Re-verify the `navigator.gpu` capability gate still short-circuits the heavy paths on phones.
- Profile the god-ray shadow loop on the WebGPU build specifically, not just the editor.

## Verification step (required)

1. **Evaluator parity test:** assert the C# `WaveHeightCPU` and the HLSL evaluator agree at a grid of
   sample points/times within tolerance (prevents shader and buoyancy drifting apart).
2. **Buoyancy sanity:** a floating crate's waterline tracks the rendered surface (visual + logged
   height delta).
3. **God-ray occlusion:** moving an object produces a visible dark shaft; removing the shadow
   multiply reverts to the current clean look (A/B toggle).
4. **WebGPU build smoke test** on the deployed demo, watching the console for the prior crash
   signature.

## Open inputs needed before coding

- Real-world target size: what does the pool half-extent represent in metres at the default
  (`metersPerPoolUnit`)? You said 1-50 m — pick a default.
- Default wind speed/direction for the lake "resting" look.
