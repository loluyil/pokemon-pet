shader_type spatial;
render_mode unshaded, cull_disabled;

// Pixelation shader for transformation effects on 3D sprites.
uniform float pixel_size: hint_range(1.0, 64.0, 1.0) = 1.0;
uniform float progress: hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_intensity: hint_range(0.0, 1.0) = 0.0;
uniform sampler2D base_texture: source_color;

void fragment() {
	vec2 tex_size = vec2(textureSize(base_texture, 0));
	float effective_pixel = mix(1.0, pixel_size, progress);
	vec2 grid = floor(UV * tex_size / effective_pixel) * effective_pixel / tex_size;
	vec4 tex = texture(base_texture, grid);
	ALBEDO = mix(tex.rgb, flash_color.rgb, flash_intensity);
	ALPHA = tex.a;
}
