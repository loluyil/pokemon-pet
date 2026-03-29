shader_type canvas_item;
uniform bool pressed = false;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (pressed) {
		COLOR = mix(tex, vec4(1.0, 1.0, 1.0, tex.a), 0.5);
	} else {
		COLOR = tex;
	}
}