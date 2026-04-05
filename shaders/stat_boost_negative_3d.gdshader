shader_type spatial;
render_mode unshaded, cull_disabled;

// Negative stat change shader: downward-sinking red/dark desaturation (3D sprite version).
uniform float intensity: hint_range(0.0, 1.0) = 0.0;
uniform vec4 debuff_color: source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float speed: hint_range(0.5, 5.0) = 2.0;
uniform sampler2D base_texture: source_color;

void fragment() {
	vec4 tex = texture(base_texture, UV);
	if (tex.a < 0.01) {
		discard;
	}
	// Falling drip pattern
	float t = TIME * speed;
	float wave = sin((UV.x * 10.0) - t) * 0.5 + 0.5;
	float fall = fract(-UV.y + t * 0.25);
	float drip = smoothstep(0.85, 1.0, wave * fall);
	// Dark vignette that sinks downward
	float shadow = smoothstep(0.0, 1.0, UV.y) * (sin(t * 2.5) * 0.3 + 0.7);
	// Desaturation
	float grey = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(tex.rgb, vec3(grey), intensity * 0.4);
	vec3 effect = desat;
	effect = mix(effect, debuff_color.rgb, (drip + shadow * 0.2) * intensity);
	// Slight darkness
	effect -= vec3(intensity * 0.1);
	ALBEDO = effect;
	ALPHA = tex.a;
}
