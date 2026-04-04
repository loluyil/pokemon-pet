shader_type canvas_item;

// Pixelation shader for transformation effects.
// Increase pixel_size to pixelate, decrease to restore.
uniform float pixel_size: hint_range(1.0, 64.0, 1.0) = 1.0;
uniform float progress: hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_intensity: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	float effective_pixel = mix(1.0, pixel_size, progress);
	vec2 grid = floor(UV * tex_size / effective_pixel) * effective_pixel / tex_size;
	vec4 tex = texture(TEXTURE, grid);
	COLOR = mix(tex, flash_color, flash_intensity);
	COLOR.a = tex.a;
}
