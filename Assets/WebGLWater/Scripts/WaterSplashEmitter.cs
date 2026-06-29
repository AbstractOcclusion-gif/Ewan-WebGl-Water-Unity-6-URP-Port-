// WebGL Water - shared splash particle emitter (Unity 6 / URP port)
// Owns (or references) a real Particle System so the splash is fully editable in
// the Inspector: select the "Splash Particles" object to tweak modules, and swap
// the droplet texture on its ParticleSystemRenderer material. Both object impacts
// (WaterSplash) and the mouse interaction (WaterController) emit through this.
//
// Droplets are tuned to DRIFT onto the surface, not plunge: low gravity plus
// velocity damping so they arc up/out, slow, and settle near the waterline.
using UnityEngine;

namespace WebGLWater
{
    [DisallowMultipleComponent]
    public class WaterSplashEmitter : MonoBehaviour
    {
        [Tooltip("The particle system to emit from. Auto-created if left empty.")]
        public ParticleSystem particles;

        [Header("Burst shaping")]
        [Range(1, 128)] public int maxParticlesPerBurst = 48;
        [Tooltip("Upward launch bias. Higher = droplets jump more before settling.")]
        [Range(0f, 3f)] public float upwardBias = 1.0f;
        [Tooltip("Outward (horizontal) spread, so droplets drift across the surface.")]
        [Range(0f, 3f)] public float outwardSpread = 1.3f;
        public float dropletSize = 0.02f;
        public Vector2 lifetime = new Vector2(0.35f, 0.7f);

        void Awake()
        {
            if (particles == null) particles = GetComponent<ParticleSystem>();
            if (particles == null)
            {
                particles = gameObject.AddComponent<ParticleSystem>();
                ConfigureForDrift(particles);
            }
        }

        /// <summary>Emit a splash at a surface point. strength is 0..1.</summary>
        public void EmitSplash(Vector3 surfacePos, float strength, float radius)
        {
            if (particles == null) return;
            strength = Mathf.Clamp01(strength);
            int count = Mathf.Clamp(Mathf.RoundToInt(strength * maxParticlesPerBurst), 3, maxParticlesPerBurst);

            var ep = new ParticleSystem.EmitParams();
            for (int i = 0; i < count; i++)
            {
                Vector2 r = Random.insideUnitCircle;
                Vector3 outward = new Vector3(r.x, 0f, r.y) * (radius * outwardSpread * Random.Range(0.4f, 1f));
                float up = Random.Range(0.5f, 1.2f) * upwardBias * (0.4f + 0.6f * strength);

                ep.position = surfacePos + new Vector3(r.x * radius * 0.5f, 0.01f, r.y * radius * 0.5f);
                ep.velocity = outward * Mathf.Max(0.4f, strength) + new Vector3(0f, up, 0f);
                ep.startLifetime = Random.Range(lifetime.x, lifetime.y);
                ep.startSize = dropletSize * Random.Range(0.6f, 1.3f);
                particles.Emit(ep, 1);
            }
        }

        /// <summary>Configure a particle system for drifting droplets (used by the
        /// scene builder and the auto-created fallback).</summary>
        public static void ConfigureForDrift(ParticleSystem ps)
        {
            var main = ps.main;
            main.simulationSpace = ParticleSystemSimulationSpace.World; // droplets live in world space
            main.gravityModifier = 0.4f;   // low -> they drift rather than dive
            main.startSpeed = 0f;          // velocity is set per-emit
            main.startLifetime = 0.5f;
            main.startSize = 0.02f;
            main.startColor = new Color(0.9f, 0.97f, 1.0f, 0.9f);
            main.maxParticles = 2000;
            main.playOnAwake = true;

            var emission = ps.emission; emission.enabled = false; // manual Emit only
            var shape = ps.shape; shape.enabled = false;

            // damping so droplets slow and settle onto the surface instead of plunging
            var lim = ps.limitVelocityOverLifetime;
            lim.enabled = true;
            lim.dampen = 0.2f;
            lim.drag = 1.5f;
            lim.multiplyDragByParticleSize = false;

            ps.Play();
        }
    }
}
