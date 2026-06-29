// WebGL Water - buoyancy (Unity 6 / URP port)
// The "water -> object" half of the two-way coupling: each FixedUpdate it samples
// the GPU height field (via WaterController's async readback) under the object and
// applies an Archimedes-style upward force plus in-water damping, so the object
// floats and bobs. The "object -> water" half is handled by WaterInteractable +
// the obstacle pass. Pair both components for full two-way interaction.
using UnityEngine;

namespace WebGLWater
{
    [RequireComponent(typeof(Rigidbody))]
    public class WaterBuoyancy : MonoBehaviour
    {
        [Tooltip("Float strength. Net buoyancy cancels gravity when " +
                 "buoyancy * submergedFraction = 1, so ~2.5 floats with the top out.")]
        public float buoyancy = 2.5f;

        [Tooltip("Linear damping applied while submerged (kills bobbing).")]
        public float waterLinearDamping = 2.0f;

        [Tooltip("Angular damping applied while submerged.")]
        public float waterAngularDamping = 1.0f;

        Rigidbody _rb;
        Collider _col;
        WaterController _ctrl;

        void Awake()
        {
            _rb = GetComponent<Rigidbody>();
            _col = GetComponent<Collider>();
        }

        void Start()
        {
            _ctrl = FindFirstObjectByType<WaterController>();
            if (_ctrl == null)
                Debug.LogWarning("WaterBuoyancy: no WaterController in the scene; object will not float.");
        }

        void FixedUpdate()
        {
            if (_ctrl == null) return;

            Vector3 p = _rb.worldCenterOfMass;
            if (!_ctrl.TryGetWaterHeight(p.x, p.z, out float surfaceY)) return;

            float half = _col != null ? Mathf.Max(0.01f, _col.bounds.extents.y) : 0.15f;
            float bottom = p.y - half;
            float submerged = Mathf.Clamp01((surfaceY - bottom) / (2f * half));
            if (submerged <= 0f) return;

            Vector3 up = -Physics.gravity.normalized;
            float g = Physics.gravity.magnitude;

            // Archimedes: upward acceleration proportional to submerged fraction.
            _rb.AddForce(up * (g * buoyancy * submerged), ForceMode.Acceleration);

            // In-water damping so it settles instead of bobbing forever.
            _rb.AddForce(-_rb.linearVelocity * (waterLinearDamping * submerged), ForceMode.Acceleration);
            _rb.AddTorque(-_rb.angularVelocity * (waterAngularDamping * submerged), ForceMode.Acceleration);
        }
    }
}
