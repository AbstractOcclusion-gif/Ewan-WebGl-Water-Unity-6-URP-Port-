# Next-session prompt — Phase 4: water fog, god rays, splashes & foam

> Paste everything below the line into a new session to continue the work.
> It's written to onboard a fresh agent with no memory of the previous sessions.

---

You're helping me enhance a **Unity 6 / URP** water system. It started as a port of
Evan Wallace's *WebGL Water* and is now a full adaptation. The project is open in
Unity; you have file access to it and a Linux shell, but **you cannot compile Unity
shaders/scripts** — treat every shader/script edit as needing my in-editor check,
and call out anything you can't verify. Work **incrementally**: small reviewable
steps, new visual features behind **inspector toggles that default OFF** so the
current look never breaks until I switch them on.

We're on git branch **`full-enhance`**. Everything below is already done and
committed — do **not** redo it.

## What already exists

Code lives in `Assets/WebGLWater/` (`Shaders/`, `Scripts/`, `Editor/`).

**Simulation** — `Shaders/WaterSim.compute` (driven by `Scripts/WaterSimulation.cs`):
a 256×256 ping-pong **RGBAFloat** heightfield. Per-texel channels: `r = height`,
`g = velocity`, `ba = surface normal.xz`. Kernels: `Drop`, `Update` (wave eq),
`Normal`, `Obstacle` (object displacement), `Conserve` (volume). Sim texel (u,v)
maps to world (x,z): `u↔x, v↔z`.

**Coordinate convention:** pool spans `x,z ∈ [-1,1]`, water surface at `y = 0`,
floor at `y = -1`, walls up to `y = 2/12`.

**Controller** — `Scripts/WaterController.cs` orchestrates the sim, caustics, and
object interaction, and publishes these **shader globals** each frame:
`_WaterTex` (sim state), `_CausticTex` (`.r` = focus intensity, `.g` = occluder
shadow = 1), `_Tiles`, `_Sky` (cubemap), `_LightDir` (toward the sun),
`_SunColor` (sun.color × intensity), `_Eye`. It also runs an **`AsyncGPUReadback`**
of the height field and exposes `TryGetWaterHeight(x, z, out float h)` for buoyancy.

**Surface** — `Shaders/WaterSurface.shader` renders in the **Transparent queue**
(`ZWrite On`, `Blend Off`; it computes its own opaque-looking color). It has:
hybrid reflection (analytic sky → planar → SSR) and refraction (analytic pool, or
real screen-space refraction). Keyword toggles: `_USE_PLANAR`, `_USE_SSR`,
`_REAL_REFRACTION`. It samples `_CameraOpaqueTexture` / `_CameraDepthTexture`
(so **Depth Texture + Opaque Texture must be enabled on the URP asset**).
`Shaders/WaterCommon.hlsl` holds analytic helpers: `GetWallColor`, `IntersectCube`,
and constants `IOR_AIR`/`IOR_WATER`, `ABOVEWATER_COLOR`, `UNDERWATER_COLOR`,
`POOL_HEIGHT`.

**Lighting** — one Unity **Directional Light** ("Sun") is the single source of
truth; the controller derives `_LightDir`/`_SunColor` from it. Objects use
`Shaders/WaterReceiver.shader` (URP lit + cast/receive shadows + projected caustics
when submerged, plus a `DepthOnly` pass). `Shaders/PoolWall.shader` is URP forward,
keeps the analytic caustic look **and receives real object shadows**.
`Shaders/Caustics.shader` projects the water grid onto the floor.

**Object interaction (two-way):** `Scripts/WaterObstacle.cs` renders any
`WaterInteractable` top-down into a ping-pong footprint map (`Shaders/ObstacleDepth.shader`)
that the `Obstacle` kernel turns into surface displacement; `Scripts/WaterBuoyancy.cs`
makes objects float via the height readback. The old analytic sphere is fully removed.

**Scene builder** — `Editor/WaterSceneBuilder.cs`, menu **Tools ▸ WebGL Water**,
generates the whole scene (grid, sky cubemap, tiles, materials, pool, Sun light,
`PlanarReflection` on the camera, and a demo floating crate + floor collider).

**Known gotchas:** WebGPU is my target and it's experimental — `AsyncGPUReadback`
may be unavailable there (buoyancy then degrades, objects sink). Axis flips are the
usual blind spot: there are `obstacleFlipY` and caustic Y-flip escape hatches.

## What I want to build now (Phase 4)

Build in this order — each layer reads against the previous one:

1. **Water fog (Beer–Lambert depth absorption)** — *do this first.* In the surface's
   refraction path, reconstruct how far the view ray travels through water (surface
   depth vs scene depth from `_CameraDepthTexture`, or the analytic ray length) and
   apply `exp(-extinction · dist)` with **per-channel** extinction so red dies first,
   then green, leaving blue. Makes depth read correctly and grounds everything else.
   Toggle + tunable extinction color/density; default off.

2. **Foam** — (a) **advected foam**: add a foam buffer (extra sim channel or a
   separate R-texture) updated in the compute loop: generate where `|velocity|` or
   surface curvature is high, advect/diffuse, decay; the surface shader lerps toward
   a foam albedo and kills reflectivity where foam is thick. (b) **border foam**:
   shoreline foam against the pool walls (fade by distance to `x,z = ±1`) and
   depth-based contact foam where geometry pierces the surface (scene depth vs water
   depth + scrolling noise).

3. **Splashes** — the heightfield can't break, so fake it: on object impact (reuse
   the obstacle-entry / impact info the controller already has), inject a sharp
   ripple **and** a foam burst into the advected-foam buffer, optionally plus a VFX
   Graph particle burst. "Foam-splash" = the foam-ring injection so each splash
   leaves a fading foam scar.

4. **God rays (underwater light shafts)** — cheap stylized route: a screen-space
   radial god-ray pass from the sun's screen position, **masked by `_CausticTex`** so
   the shafts flicker in sync with the floor caustics. (Physically-grounded raymarch
   is the stretch option.)

Start by proposing a short plan and the first concrete step (water fog), then build
it. Keep the toggles-default-off, in-editor-verification discipline throughout.
