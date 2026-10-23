// The incoming LOD keeps the pixels below the fade and the outgoing one the rest, so the planet never shows a hole.
instance uniform vec2 lod_dither_band = vec2(0.0, 1.0);

void lod_dither(vec2 pixel) {
	ivec2 p = ivec2(pixel) & ivec2(3);
	const float bayer[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	float threshold = (bayer[p.x + p.y * 4] + 0.5) / 16.0;
	if (threshold < lod_dither_band.x || threshold >= lod_dither_band.y) {
		discard;
	}
}
