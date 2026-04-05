shader_type spatial;
render_mode unshaded, cull_disabled;

// Positive stat change shader: upward-moving bright particles / glow (3D sprite version).
uniform float intensity: hint_range(0.0, 1.0) = 0.0;
uniform vec4 boost_color: source_color = vec4(0.3, 1.0, 0.5, 1.0);
uniform float speed: hint_range(0.5, 5.0) = 2.0;
uniform sampler2D base_texture: source_color;

void fragment() {
	vec4 tex = texture(base_texture, UV);
	if (tex.a < 0.01) {
		discard;
	}
	// Rising sparkle pattern
	float t = TIME * speed;
	float wave = sin((UV.x * 12.0) + t) * 0.5 + 0.5;
	float rise = fract(UV.y + t * 0.3);
	float sparkle = smoothstep(0.85, 1.0, wave * rise);
	// Edge glow that pulses upward
	float glow = smoothstep(0.6, 0.0, UV.y) * sin(t * 3.0) * 0.5 + 0.5;
	vec3 effect = mix(tex.rgb, boost_color.rgb, (sparkle + glow * 0.3) * intensity);
	// Slight brightness boost
	effect += boost_color.rgb * intensity * 0.15;
	ALBEDO = effect;
	ALPHA = tex.a;
}
