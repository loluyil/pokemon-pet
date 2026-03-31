shader_type canvas_item;

// Pokemon Black/White style battle transition:
// Rapid horizontal bars sweep across the screen with white flashes,
// then the whole screen goes black.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int bar_count : hint_range(1, 20) = 8;

void fragment() {
	float bar_index = floor(UV.y * float(bar_count));
	// Alternate bars sweep from left and right
	float direction = mod(bar_index, 2.0) == 0.0 ? 1.0 : -1.0;
	float x = direction > 0.0 ? UV.x : 1.0 - UV.x;

	// Stagger bars: each bar starts slightly later based on its index
	float stagger = bar_index / float(bar_count) * 0.15;
	float bar_progress = clamp((progress - stagger) / (1.0 - stagger), 0.0, 1.0);

	// Sharp edge sweep
	float sweep = step(x, bar_progress * 1.3);

	// White flash overlay
	float flash = flash_intensity;

	// Combine: black bars with white flash
	vec3 color = mix(vec3(0.0), vec3(1.0), flash * (1.0 - sweep));
	float alpha = max(sweep, flash * 0.5);

	COLOR = vec4(color, alpha);
}
