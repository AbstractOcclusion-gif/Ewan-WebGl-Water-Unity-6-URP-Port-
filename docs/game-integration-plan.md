# Water in a game — integration plan (multi-body, PC + WebGPU)

Status: **plan / discussion** — no code yet. Target: multiple water bodies visible at once,
scalable across PC and the (working) WebGPU build. Ocean/open-world is explicitly out of scope.

## The core problem: it's a one-body system today

Everything the water needs is published with `Shader.SetGlobal*` — `_WaterTex`, `_CausticTex`,
`_FoamMask`, the `_Volume*` frame, the `_Wave*` bank, and the fog/foam params are all singletons.
A `WaterController` drives exactly one simulation. So the scene supports **one** body of water.
"Multiple simultaneous" means moving that state from global to **per-instance**. That refactor is
also what turns the demo into a drop-in prefab, so it's the backbone of everything below.

## What is per-body vs. shared

Per-body (each `WaterVolume` owns its own, pushed to its renderers via `MaterialPropertyBlock`):
- its sim state RT (`_WaterTex`) and foam RT (`_FoamMask`)
- its caustic RT (`_CausticTex`)
- its volume frame (`_VolumeCenter` / `_VolumeExtent` / `_VolumeRot`)
- its wave bank (`_WaveA/_WaveB/_WaveCount/_WaveMetersPerUnit/_WaveNormalStrength`)
- its fog (`_WaterFogColor/_Extinction/_Density`) and foam params — so different lakes can look different
- optionally its tile/pool albedo

Stays global (genuinely shared by the scene):
- the sun (`_LightDir`, `_SunColor`) and the environment (`_Sky`)
- the camera (`_Eye`) and a single shared `_WaveTime` clock

## Phase 1 — De-globalize into a `WaterVolume` component (the backbone)

Replace the editor scene-builder wiring with a self-contained component that owns a simulation, a
caustic pass, a wave bank, and the volume frame, and feeds ITS renderers (surface above/under, pool,
god rays) through a `MaterialPropertyBlock` instead of `Shader.SetGlobal`. Outcome: drop a
`WaterVolume` prefab into any scene, size/rotate it with the extent/rotation controls that already
exist, and it renders independently. One body works as a prefab; N bodies coexist.

Known cost: per-renderer MPB overrides break SRP-batching for the water renderers (fine for a handful
of bodies) and each body runs its own compute sim + caustic pass (budget via Phase 3).

## Phase 2 — Object ↔ body association (the genuinely hard part)

A floating crate must receive the caustics/fog of the lake it is actually in. With overlapping or
multiple bodies, each dynamic object needs to know its current body. Plan: a small
`WaterMembership` helper on interactables resolves the containing `WaterVolume` (point-in-volume test
against the TRS box), and pushes that body's `_WaterTex/_CausticTex/_Volume*`/fog onto the object's
receiver MPB each frame. Buoyancy (`TrySampleSubmersion`) queries that same body.

Scoping decision: **one object belongs to one body at a time** (the dominant containing volume).
True blending across two overlapping bodies is deferred — rare and expensive.

## Phase 3 — Performance: culling + quality tiers (PC and WebGPU)

- **Off-screen / distance culling:** a body that isn't visible (renderer culled) or is beyond a
  range pauses its sim step, caustic pass and readback. Idle lakes cost ~nothing.
- **Quality tiers** (a `WaterQuality` ScriptableObject): toggle SSR / planar / god rays, and scale
  sim resolution (256→128), caustic resolution, and god-ray steps. Pick a tier from a capability
  probe so the WebGPU/mobile path stays inside its budget (and the existing `navigator.gpu` gate).
- **Reflections don't scale the same way:** planar reflection is a second camera render *per body* —
  it does NOT scale to many bodies. For multi-body, default to SSR + a reflection probe and reserve
  planar for a single hero body. This is a real constraint worth deciding early.
- Readback latency (buoyancy) is per-body; cull distant bodies' readbacks too.

## Phase 4 — Gameplay API & hooks

The primitives exist (`TryGetWaterHeight`, `AddRipple`, buoyancy, submersion). Add the glue:
- submerge/emerge events (enter/exit water) for audio, VFX, swimming, oxygen, etc.
- ripple spawning helpers for projectiles, footsteps, boats (world-space `AddRipple` already there)
- a clean façade so gameplay code calls `WaterVolume.SampleHeight(worldPos)` etc. without touching
  internals.

## Phase 5 — Authoring

- Ship `WaterVolume` as a prefab with a tidy inspector.
- Scene-view gizmo: draggable handles for the TRS extent/rotation instead of typing Euler angles,
  drawn as the oriented box so you can see the volume.

## Decisions to lock before building

1. **Object-body association model** — confirm "one object, one body" is acceptable (recommended).
2. **Reflections at scale** — accept SSR + probe for multi-body, planar only for a hero body?
3. **Per-body sim budget** — rough max number of *active* (near-camera) bodies to design the culling
   around (e.g. 2–4 simulating at once, the rest paused)?
4. **Shared vs per-body wave clock** — one global `_WaveTime` is simplest; per-body phase offsets if
   you want lakes visibly out of sync.

## Suggested first milestone

Phase 1 only: a working `WaterVolume` prefab driving one body with zero `Shader.SetGlobal` for
per-body state, proven by dropping **two** instances in a scene and seeing both render correctly
(even if object-side caustics still pick one body). Everything else builds on that.
