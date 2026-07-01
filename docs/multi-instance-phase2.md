# Phase 2 — object ↔ body association ("which lake am I in?")

Branch: `experiment/multi-instance-water`. Prereq: Phase 1 done (per-body `MaterialPropertyBlock`,
transform-driven frame, input router, `WaterController.Primary`/`.Resolve()`, secondary-body menu).

## Goal

A floating object interacts with, and is lit by, the water body it is actually inside — not the
single global "primary" body it follows today. Drop the crate in lake B and it floats on lake B's
waterline and shows lake B's caustics/fog. This closes the seam left open in Phase 1.

Scoping (confirmed earlier): **one object belongs to one body at a time** (its containing body, or the
nearest if it's outside all of them). Blending two overlapping bodies is out of scope.

## Part A — physics side (small)

Objects currently cache `WaterController.Resolve()` (= `Primary`) in `Start`/`Awake`. Make it
per-object and dynamic:

1. Add a static resolver on `WaterController`:
   `public static WaterController BodyContaining(Vector3 worldPoint)` — iterate the `Bodies` registry,
   return the body whose TRS volume contains the point's horizontal footprint (`WorldToPool` xz in
   [-1,1]); if several overlap, pick the nearest by centre; if none, return `Primary` (fallback).
   Expose `Bodies` read-only or keep the query on `WaterController`.
2. `WaterBuoyancy`: re-resolve its body each `FixedUpdate` from `transform.position`
   (`_ctrl = WaterController.BodyContaining(pos)`), so an object that drifts between lakes switches.
   Cheap (a handful of bodies).
3. `WaterInteractable` and `WaterSplash`: same — resolve from the object's position rather than a
   one-time `Resolve()`. Replace the `TODO(Phase 2)` stubs.

## Part B — render side (the meatier bit)

Object receivers (`WaterReceiver`) read `_WaterTex/_CausticTex/_Volume*`/fog from GLOBALS today, so
every object shows the primary body. Give each object its own per-object override:

1. Refactor `WaterController.ApplyBodyBlock` to write into a passed block:
   `void WriteBodyProps(MaterialPropertyBlock mpb)` (the existing per-body sets), and have
   `ApplyBodyBlock` call it for its own renderers.
2. Add `public void WriteObjectBlock(MaterialPropertyBlock mpb)` (or reuse `WriteBodyProps`) so an
   external object can pull a body's uniforms.
3. New component `WaterMembership` on floating objects (add it in the builder next to
   `WaterBuoyancy`): each `LateUpdate`, resolve the containing body and push its props onto the
   object renderer's `MaterialPropertyBlock`. The receiver then samples the right lake's sim + caustic
   + fog. Objects WITHOUT this component keep falling back to the global (primary) — so it's additive.

## Part C — edge cases

- Object outside every footprint → `BodyContaining` returns the nearest / `Primary`; the receiver's
  per-fragment underwater test (`poolPos.y < simH`) still gates caustics/fog correctly.
- Object straddling two bodies → one body wins (nearest centre). Documented, acceptable.
- Overlapping volumes → nearest-centre tiebreak; a future `priority` field could override.

## Optional (fits here) — extract `WaterInput`

The input router currently lives on the primary `WaterController`. Optionally move it to a dedicated
`WaterInput` MonoBehaviour (camera/orbit/splash/ripple params + the raycast-and-route logic), leaving
`WaterController` purely a water body. Not required for Phase 2 correctness; do it if touching input.

## Verification

1. Two bodies with **different fog colours** (and/or wind). Drop a crate in each — each crate shows
   ITS lake's fog/caustics and floats on ITS waterline.
2. Push a crate from lake A into lake B — its fog/caustics/waterline switch as it crosses.
3. Regression: a single-body scene behaves exactly as before (membership resolves the only body).
4. WebGPU build still runs.

## Decisions still open (not blocking Phase 2)

- Reflections at scale: SSR + reflection probe for multi-body, planar only for a hero body.
- Active-sim budget for Phase 3 culling (how many bodies simulate near-camera at once).
- Cosmetic `WaterController` → `WaterVolume` rename (do via `git mv` so the .meta guid/scene refs
  survive).
