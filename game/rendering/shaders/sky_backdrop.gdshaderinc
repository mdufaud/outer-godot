// The starless sky. Shared so the leviathan can hide stars behind it with the
// exact colour around it. Needs noise.gdshaderinc included first.
vec3 sky_backdrop(vec3 dir) {
	float haze = smoothstep(0.42, 0.82, fbm(dir * 2.4 + 17.0, 4, 2.1));
	return vec3(0.002, 0.004, 0.009) + vec3(0.008, 0.012, 0.022) * haze;
}
