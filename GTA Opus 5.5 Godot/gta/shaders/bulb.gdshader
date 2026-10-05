shader_type spatial;
render_mode unshaded, shadows_disabled;

// Emissive signal bulb – colour comes from MultiMesh instance colour.
void fragment() {
	ALBEDO = COLOR.rgb * 3.5;
}
