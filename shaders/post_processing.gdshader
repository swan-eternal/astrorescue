// Post-processing shader for Astro Rescue.
//
// Runs on every screen pixel AFTER the scene is rendered, applying
// visual effects (vignette, bloom, etc.) before the final image is
// shown. Each effect lives in this single shader — keeps things
// simple and avoids multi-pass complexity for V1.
//
// Effects:
//   - Vignette (Phase 2): darkens screen corners, focuses eye to
//     center. Tunable via VisualSettings.get_vignette_intensity().
//   - Bloom (Phase 3): adds glow around bright objects — sun
//     strongly, planets weakly ("planetshine"). Not yet
//     implemented; see Astro-Rescue.md TODO entry.

shader_type canvas_item;
render_mode unshaded;

// hint_screen_texture tells Godot to inject the rendered scene as a
// texture the shader can sample from. Without this hint, the shader
// only sees the ColorRect's own pixels (empty/transparent).
//
// repeat_disable: prevents the texture from tiling if sampled outside
// the screen bounds (defensive — shouldn't happen with SCREEN_UV).
// filter_linear: smooth sampling instead of pixelated nearest-neighbor.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Vignette strength. 0 = no vignette (passthrough), 1 = strong
// vignette (corners near black). Default 0.3 = subtle.
//
// Driven by VisualSettings.get_vignette_intensity() via the script
// at scripts/post_processing_layer.gd, which polls each frame and
// pushes the value into the ShaderMaterial's uniform. The user
// controls it via the Vignette intensity slider in Settings → Visual.
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec4 color = texture(screen_texture, SCREEN_UV);

	// Vignette: darken the corners, focus the eye to the center.
	// SCREEN_UV is in [0, 1] across the screen. Distance from center
	// in UV space — corners are at ~0.707 (sqrt(0.5² + 0.5²)).
	// smoothstep(0.2, 0.7, dist) ramps from 0 at dist 0.2 to ~1 at
	// the corners, so the vignette smoothly fades in toward edges.
	vec2 centered_uv = SCREEN_UV - vec2(0.5);
	float dist = length(centered_uv);
	float vignette_mask = smoothstep(0.2, 0.7, dist);
	color.rgb *= 1.0 - vignette_mask * vignette_intensity;

	COLOR = color;
}