# Phase 3 — performance & scale (culling, quality tiers, reflections)

Branch: `experiment/multi-instance-water`. Prereq: Phases 1 & 2 done (per-body `MaterialPropertyBlock`
rendering, transform-driven frame, input router, object↔body association via `WaterMembership` +
`WaterController.BodyContaining`).

## Goal

Make N water bodies affordable on PC **and** the WebGPU/mobile budget. Idle lakes should cost ~nothing,
a body should be able to trade fidelity for speed, and reflections must not scale as "a full extra
camera render per body". Delivered in three independent slices.

---

## Slice A — sim & pass culling (all in `WaterController.cs`)

Only the bodies that matter run the heavy GPU work each frame; off-screen bodies also stop drawing.

A static, frame-guarded `EnsureSchedule` runs once per frame (whichever body `Update`s first computes
it for all, so it is order-independent) and sets two flags per body:

- **`_visible`** — the body's real oriented-box world AABB (`CullBounds`, the pool box x,z∈[-1,1],
  y∈[-1,0] plus a small wave margin) tested against the camera frustum with
  `GeometryUtility.CalculateFrustumPlanes`/`TestPlanesAABB` (non-alloc, one reused `Plane[6]`). This is
  necessary because the water renderers keep deliberately huge (1000-unit) bounds to avoid mis-culling
  under the volume transform, which makes Unity's own `renderer.isVisible` useless here.
- **`_simulate`** — `_visible` **and** within `activationDistance` of the camera **and** among the
  nearest `ActiveSimBudget` (= **4**) eligible bodies. `EnforceSimBudget` ranks alloc-free (O(n²) "how
  many eligible bodies are nearer than me", recomputing eligibility so its own writes can't skew the
  count).

Gating:

- `!_visible` → the body's four renderers are `.enabled = false` (stop drawing).
- `!_simulate` → skip `Step()` (obstacle + sim substeps + conserve + normals + foam), `UpdateCaustics()`
  and `RequestHeightReadback()`. The body **holds** its last heightfield/caustics.
- Always run: `ApplyBodyBlock()` (cheap MPB) and `_waveTime += dt` (unless manually paused). Because the
  wind waves are analytic (driven by the shared `_WaveTime` clock), a budget-paused **but visible** body
  keeps its ambient wind motion — only interactive ripples freeze.

Nice consequences: a paused body keeps `_heightReady` with its last readback, so **objects floating on
it keep floating**; the manual Space-pause still freezes everything (separate from culling).

Inspector: `enableCulling` (default ON — a no-op for a single visible body), `activationDistance`
(100, matches the far clip). A body with `enableCulling = false` always simulates and never consumes a
budget slot.

---

## Slice B — quality tiers (`WaterQuality.cs`, `WaterSimulation.cs`, `WaterController.cs`, builder)

Scales the **perf knobs only**: sim grid resolution, caustic resolution, god-ray steps/enable.
Reflection-path selection is slice C.

`WaterQuality` is a `[CreateAssetMenu("WebGL Water/Water Quality")]` ScriptableObject holding three
tiers as inspector fields plus a `selection` enum (`Auto`, `ForceLow/Medium/High`):

| Tier   | Sim res | Caustic res | God-ray steps | God rays |
|--------|---------|-------------|---------------|----------|
| High   | 256     | 1024        | 24            | on       |
| Medium | 128     | 512         | 16            | on       |
| Low    | 128     | 256         | 0             | **off**  |

`Resolve()` returns the forced tier, or under `Auto` runs `Probe()`: `RuntimePlatform.WebGLPlayer`
(this is how Unity ships WebGPU builds — avoids depending on the experimental `GraphicsDeviceType.WebGPU`
enum) **or** `Application.isMobilePlatform` **or** no async readback → **Low**; < 2 GB VRAM → Medium;
else High. Values are sanitised on read (sim resolution rounded to a multiple of 8). Static
`Tier.Default` = 256/1024/24/on = the original look.

Refactor: `WaterSimulation.Resolution` went from a `const 256` to an instance value set via
`new WaterSimulation(cs, resolution)` (validates it is a positive multiple of `ThreadGroupSize = 8`).
`WaterController.ApplyQuality()` at `OnEnable` sets `_simRes`, `causticResolution` and `_godRaysAllowed`
and writes `_GodRaySteps` to the god-ray material; it **early-returns when no asset is assigned**, so
`_simRes` keeps its default and existing scenes are untouched. `_simRes` threads into the sim, the
obstacle RT, `_heightMip` and `SamplePoolTexel`. The god-ray renderer is gated `on && _godRaysAllowed`
inside the cull path, so a tier that disables god-rays wins over culling.

The builder creates/loads `Generated/WaterQuality.asset` and assigns `ctrl.quality` (secondary bodies
inherit the primary's).

Note: resolutions are locked at `OnEnable`, so a tier change takes effect on the next play/restart, not
live mid-play.

---

## Slice C — reflections at scale (`WaterController.cs`, builder)

The surface does a hybrid reflection: analytic sky base → planar override (`_USE_PLANAR`) → SSR override
where it hits (`_USE_SSR`). Those are `shader_feature_local` toggles **on the surface material**, and all
bodies shared `matAbove`/`matUnder`, so every body was locked into the same mode. Planar is also a single
global plane (`_PlanarReflectionTex`, mirrored across one height) — it cannot serve N bodies.

Fix (no shader edits): a per-body `reflectionMode` enum — `SkyOnly`, `SSR` (default), `Planar`.

- **Per-body material instances:** at `OnEnable` the two surface renderers get their own `new Material`
  instances (play-mode only, so the scene asset is untouched; destroyed in `OnDisable`), and their
  `_USE_SSR`/`_USE_PLANAR` keywords are set from the mode. SSR scales to many bodies at zero extra camera
  renders.
- **Hero planar:** a `Planar` body binds the scene's `PlanarReflection` (on the camera) to its own plane
  (`enableReflection = true`, `waterHeight = transform.position.y`). Because the planar texture is one
  global plane, **only one hero body should use Planar mode** (with several, the last at `OnEnable`
  wins).
- Builder now defaults `planar.enableReflection = false` — planar renders only when a hero opts in (it
  used to render every frame even though nothing sampled it, so this is also a small perf win).

Environment base stays the procedural `_Sky` cubemap (a real scene-capturing URP reflection probe would
need a shader edit and is a possible later add-on).

---

## Inspector reference (new fields on the Water Controller)

- **Performance:** `quality` (WaterQuality asset), `enableCulling`, `activationDistance`.
- **Reflections:** `reflectionMode` (SkyOnly / SSR / Planar).

## Caveats

- **SSR needs Depth + Opaque Texture on the active URP asset** (see `webgpu` notes) — with the default
  SSR mode, missing those makes reflections sample black.
- **Default look changed** from sky-only to SSR (chosen deliberately). Set a body to `SkyOnly` to
  restore the old look.
- **Planar = one hero, horizontal plane.** A tilted body reflects wrong under planar; use SSR for tilted
  water. A moving hero would need per-frame plane tracking (currently set once at `OnEnable`).
- **Resolution is fixed at startup** — changing the quality tier takes a restart to resize the RTs.
- Reflection mode is **not** coupled to the quality tier yet (e.g. auto-SkyOnly on Low) — an easy
  follow-up if wanted.

## Verification

1. Single body you're looking at: unchanged behaviour (visible + in range + within budget → simulates).
2. Several bodies: only the 4 nearest simulate; off-screen ones stop drawing and pause; look back →
   instant resume; a crate in a paused lake keeps floating.
3. Quality: no asset → identical to before; Force Low → coarser ripples, smaller caustics, god-rays off,
   cheaper; Auto → High on desktop, Low on a web build.
4. Reflections: bodies default to SSR over the sky; set one lake to Planar and only it pays for the
   mirror pass, tracking its own height; SkyOnly restores the old look.
5. WebGPU build still runs.

## What's left

Phase 4 (gameplay API: enter/exit-water events, ripple helpers, a `SampleHeight` façade) and Phase 5
(authoring: `WaterVolume` prefab + scene gizmo, the cosmetic `WaterController` → `WaterVolume` rename).
Optional Phase 3 follow-ups: tier-driven reflection downgrade, and a real URP reflection probe base.
