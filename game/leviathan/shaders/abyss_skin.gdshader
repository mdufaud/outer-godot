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
// The arrival is staged off the baked vertex masks (red = eyes, green = bulb):
// the lantern alone, then the eyes, while presence dithers the body in.
uniform float lure_glow : hint_range(0.0, 1.0) = 0.0;
uniform float eye_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 eye_color : source_color = vec3(1.0, 0.04, 0.02);
uniform float eye_energy = 6.0;
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
uniform float lit_albedo : hint_range(0.0, 1.0) = 0.08;
// The body first arrives as a patch of starless sky, then darkens a little.
uniform float backdrop_darkness : hint_range(0.0, 1.0) = 0.6;

#include "res://game/shared/shaders/noise.gdshaderinc"
#include "res://game/rendering/shaders/sky_backdrop.gdshaderinc"

void fragment() {
	float eye = COLOR.r * eye_glow;
	float bulb = COLOR.g * lure_glow;
	// The stars behind it go out first (screen door: no transparent pass for a
	// skinned mesh this size), then the shape surfaces from the dark.
	float occlude = smoothstep(0.0, 0.3, presence);
	float shade = smoothstep(0.35, 1.0, presence);
	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (eye <= 0.0 && bulb <= 0.0 && dither >= occlude) {
		discard;
	}
	// ponytail: no sun glow in the backdrop; the reveal happens opposite the sun.
	vec3 backdrop = sky_backdrop(normalize(mat3(INV_VIEW_MATRIX) * VERTEX))
		* (1.0 - backdrop_darkness * smoothstep(0.1, 0.5, presence));
	vec4 base = texture(skin_albedo, UV);
	ALBEDO = base.rgb * mix(dark_albedo, lit_albedo, presence) * shade;
	NORMAL_MAP = texture(skin_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = 0.74;
	METALLIC = 0.0;
	SPECULAR = 0.28 * shade;

	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), rim_power);
	// The lantern is the one part of it that is its own light source, and it is
	// the only thing visible while the body is still a hole in the sky.
	vec3 lantern = texture(skin_glow, UV).rgb;
	EMISSION = backdrop * (1.0 - shade)
		+ rim_color * rim * (0.22 + presence * 0.92) * (1.0 + flash * 2.1) * shade
		+ lantern * (1.4 + flash * 3.0) * lure_glow
		+ eye_color * eye * eye_energy;
}
