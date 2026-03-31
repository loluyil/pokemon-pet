shader_type canvas_item;

// Classic Pokemon iris-wipe: a shrinking circle reveals black.
// progress 0.0 = fully transparent, 1.0 = fully black.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Center of the circle in UV space (0.5, 0.5 = screen center).
uniform vec2 center = vec2(0.5, 0.5);

void fragment() {
	// Correct for aspect ratio so the circle isn't squished
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float dist = length((UV - center) * aspect);
	// Max possible radius (corner distance) ~0.72 for a centered circle
	float radius = max(0.0, 1.0 - progress) * 0.75;
	float edge = smoothstep(radius, radius - 0.008, dist);
	COLOR = vec4(0.0, 0.0, 0.0, edge);
}
