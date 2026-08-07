shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, shadows_disabled, fog_disabled, ambient_light_disabled;

// The anglerfish carries its own baked skin, so this shader only exists to hang
// the sequence on it: presence lifts it out of the dark as it arrives, flash
// carries the lightning from the storm in its throat. The maps come from the
// imported glTF material at runtime rather than from preloads, so re-importing
// the model can never leave the shader pointing at a stale texture.
//
// Fins and fangs are single sided sheets in the source mesh, so culling stays
// off: with back faces dropped every tooth reads as a hole from one side.

uniform sampler2D skin_albedo : source_color, filter_linear_mipmap;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D skin_glow : source_color, filter_linear_mipmap;
uniform float presence : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.16, 0.045, 0.30);
uniform float rim_power : hint_range(1.0, 12.0) = 4.4;
// Far out it is a silhouette against the galaxy; up close the lantern and the
// bolts have to find real skin. Presence is what walks between the two.
//
// Both stay low on purpose. The baked skin is a pale grey and the sun runs at
// 1.2 energy, so a faithful albedo comes back at the same brightness as a
// daylit sky and the creature crossing it reads as a cloud. Everything that
// makes the shape legible is edge: the rim, the lantern and the bolts.
uniform float dark_albedo : hint_range(0.0, 1.0) = 0.03;
uniform float lit_albedo : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	vec4 base = texture(skin_albedo, UV);
	ALBEDO = base.rgb * mix(dark_albedo, lit_albedo, presence);
	NORMAL_MAP = texture(skin_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = 0.74;
	METALLIC = 0.0;
	SPECULAR = 0.28;

	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), rim_power);
	// The lantern is the one part of it that is its own light source, and it is
	// the only thing visible while the body is still a hole in the sky.
	vec3 lantern = texture(skin_glow, UV).rgb;
	EMISSION = rim_color * rim * (0.22 + presence * 0.92) * (1.0 + flash * 2.1)
		+ lantern * (1.4 + flash * 3.0);
}
