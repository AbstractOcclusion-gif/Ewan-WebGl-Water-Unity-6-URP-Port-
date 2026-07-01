# Next-session prompt — Phase 5 authoring (prefab, gizmo, WaterVolume rename) + remaining polish

> Paste everything below the line into a new session to continue. It onboards a fresh agent with no
> memory of previous sessions. (Note: `docs/PHASE4_PROMPT.md` is STALE — it predates the multi-instance
> work and its features are long done. Ignore it. This file supersedes it.)

---

You're continuing work on a **Unity 6 / URP** water system — a port/adaptation of Evan Wallace's
*WebGL Water* (MIT). Everything is on git branch **`experiment/multi-instance-water`**.

## Ground rules (from the project's own instructions — follow strictly)

- **Ask before writing code.** Give a concrete implementation plan first; implement only after the user
  approves. Plan-first for every substantive item.
- **Never guess, always check.** Verify claims against the actual files before asserting.
- **You cannot compile in this environment.** The user compiles and eyeballs in the Unity editor and
  reports back. Treat every shader/script edit as needing their in-editor check. For risky/multi-file
  changes, run a subagent diff-review before handing back (it has already caught real bugs).
- **Coding standards:** no magic numbers (named consts), no hardcoded shader strings (consts/`PropertyToID`),
  short single-responsibility functions, early returns, fail fast, comments explain WHY, prefer
  immutability, minimize public API.
- **Filesystem quirk:** editing a file so it *shrinks* can leave trailing null bytes in the Linux-mount
  view (a caching artifact) and `grep` may flag the file "binary". The canonical file (what the Read/Write
  tools and Unity see) is fine — confirm with the Read tool, not the bash mount. If in doubt, rewrite the
  whole file with the Write tool.

## What's done (do NOT redo)

Code lives in `Assets/WebGLWater/` (`Scripts/`, `Editor/`, `Shaders/`).

- **Phase 1** — de-globalized into a per-body component. Each water body publishes its uniforms through a
  `MaterialPropertyBlock` on its own renderers instead of `Shader.SetGlobal`, so N bodies coexist. Frame is
  transform-driven (position/rotation from the GameObject; `volumeExtent` is a field). Class is still named
  `WaterController` (rename deferred — see below). See `docs/multi-instance-phase1.md`.
- **Phase 2** — object↔body association. `WaterController.BodyContaining(worldPoint)` resolves the lake an
  object is in; buoyancy/splash/interactable/splash-emitter resolve per-object; a `WaterMembership`
  component lights each floater with its containing lake. See `docs/multi-instance-phase2.md`.
- **Phase 3** — performance & scale: off-screen/distance sim culling + a 4-body active-sim budget;
  `WaterQuality` ScriptableObject tiers (sim/caustic resolution, god-ray steps) chosen by a capability
  probe; per-body reflection mode (SSR default, one hero body for planar). See `docs/multi-instance-phase3.md`.
- **Audit cleanup** (4 passes) — shader NaN/÷0 guards; hardcoded-string removal; a shared
  `Shaders/WaterShared.hlsl` (IOR/POOL consts, `IntersectCube`, `ProjectCausticUV`); C# magic-number
  naming; `WaterSimulation` de-stringing; the editor `Build()` decomposed into helpers. Full tracker with
  what's resolved vs open: `docs/water-system-audit.md`.

## What to build now — Phase 5 authoring (the user's next focus: "cosmetic work for prefab etc")

Plan each before coding. Suggested order:

1. **`WaterController` → `WaterVolume` cosmetic rename.** Do it with `git mv` so the script asset's
   `.meta` guid survives (currently `5b7c69d58eef6734798f9cf5eba11a88`), then rename the class to match the
   file (Unity binds MonoBehaviours by file-guid + matching class name), and update ALL references
   (`WaterController.Primary`/`.BodyContaining`/`.Resolve`, the builder, `WaterMembership`, buoyancy,
   splash, interactable, splash-emitter, doc cross-refs). Big mechanical rename — verify with a subagent.
2. **Clean `WaterVolume` prefab.** The existing `Assets/WebGL Water.prefab` is the whole demo scene root,
   not a reusable single-body prefab. Ship a tidy `WaterVolume` prefab (one body + its renderer refs) with
   a clean inspector, so it can be dropped into any scene.
3. **Scene-view gizmo + handles.** There is NO custom editor yet (`OnDrawGizmos`/`OnSceneGUI`/`CustomEditor`
   are absent). Draw the oriented volume box (`center` = transform, `extent`, rotation) as a gizmo, and add
   draggable scene handles for extent/rotation instead of typing Euler angles.

## Also pending (pick up as directed)

- **Phase 4 gameplay API / façade:** enter/exit-water (submerge/emerge) events for audio/VFX/swimming,
  ripple-spawn helpers (footsteps/projectiles/boats), and a clean `WaterVolume.SampleHeight(worldPos)`
  façade over the existing primitives (`TryGetWaterHeight`, `AddRipple`, `TrySampleSubmersion`).
- **Remaining audit items** (`docs/water-system-audit.md`): MPB-vs-global uniform de-dup (#10),
  per-frame body-resolution cache shared across buoyancy/splash/membership (#11), a few single-use shader
  nits (WaterSurface peaked-refine `5`/`0.005`, foam-nudge `0.1`, analytic box y-max, `length(p)`/`sqrt`
  guards in WaterCommon/Caustics), and deleting the deprecated `WaterSphere.shader` + `Generated/Sphere.mat`
  + `Generated/UnitSphere.asset` (do it from the Unity editor so it confirms no remaining references).
- **Open Phase 3 decisions:** tier-driven reflection downgrade (auto-SkyOnly on Low), and a real URP
  reflection-probe environment base (needs a shader edit).
- **WebGPU test debt:** WebGPU is the deployment target and is experimental. Build-test the recent work on
  WebGPU (the build uses `Mobile_RPAsset` — Depth + Opaque Texture must be ON, which the new default-SSR
  reflection mode also requires). Watch the known WebGPU issues (async-readback absence → buoyancy degrades;
  past stack-overflow crash on mobile).

## Deferred until the user is satisfied with the product (their explicit call — do NOT start unprompted)

- **Encapsulation** (`public` → `[SerializeField] private`/`internal`, audit #14) and **packaging** into
  `package/AbstractOcclusion/WebgpuWater/`: `package.json` (`com.abstractocclusion.webgpuwater`),
  `Runtime/` + `Editor/` asmdefs, `AbstractOcclusion.WebgpuWater` namespace, `Shaders/`, `Samples~/` (the
  demo scene), `LICENSE.md`, `README.md`, `CHANGELOG.md`. The asmdef split is what lets `#14` shrink the
  public API while the editor builder keeps `internal` access — so do #14 and packaging together, then.

## License

All code is MIT — Evan Wallace's original *WebGL Water* plus this port/adaptation; no other third-party
code. Publishing as a freebie is fine; add a `LICENSE.md` (original MIT notice + your port copyright) and
keep the source-header attributions before publishing. (Not legal advice — confirm before shipping.)

## Read first

`docs/multi-instance-phase1.md`, `-phase2.md`, `-phase3.md` (the build history), `docs/water-system-audit.md`
(open cleanup items), and `docs/game-integration-plan.md` (the overall roadmap). Confirm you're on branch
`experiment/multi-instance-water` before starting.
