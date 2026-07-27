#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D destination_color;

layout(push_constant, std430) uniform Params {
	ivec4 screen;
} params;

void main() {
	ivec2 coordinate = ivec2(gl_GlobalInvocationID.xy);
	if (coordinate.x >= params.screen.x || coordinate.y >= params.screen.y) {
		return;
	}
	vec2 screen_uv = (vec2(coordinate) + 0.5) / vec2(params.screen.xy);
	imageStore(destination_color, coordinate, vec4(texture(source_color, screen_uv).rgb, 1.0));
}
