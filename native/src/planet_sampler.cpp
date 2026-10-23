#include "planet_sampler.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

// Line-for-line mirror of the CPU sampler in planet_generator.gd: Vector3/Vector4 math stays float32
// and every GDScript float is a double, so both backends return the same bits.

namespace outer
{

namespace
{

using godot::real_t;
using godot::Vector3;
using godot::Vector4;
namespace Math = godot::Math;

// PlanetShapeProfile height kinds, as pushed to planet_height.comp.
enum HeightKind : int64_t
{
    earth = 0,
    moon = 1,
    alien = 2,
    shattered = 3,
    moat = 4,
    asteroid = 5,
    glacier = 6,
    mirage = 7,
};

const Vector3 one(1.0f, 1.0f, 1.0f);
const Vector3 up(0.0f, 1.0f, 0.0f);
const Vector4 one4(1.0f, 1.0f, 1.0f, 1.0f);
const Vector4 half4(0.5f, 0.5f, 0.5f, 0.5f);

Vector3 floor_vector3(const Vector3 &value)
{
    return Vector3(real_t(std::floor(double(value.x))), real_t(std::floor(double(value.y))),
                   real_t(std::floor(double(value.z))));
}

Vector4 floor_vector4(const Vector4 &value)
{
    return Vector4(real_t(std::floor(double(value.x))), real_t(std::floor(double(value.y))),
                   real_t(std::floor(double(value.z))), real_t(std::floor(double(value.w))));
}

Vector4 abs_vector4(const Vector4 &value)
{
    return Vector4(real_t(std::abs(double(value.x))), real_t(std::abs(double(value.y))),
                   real_t(std::abs(double(value.z))), real_t(std::abs(double(value.w))));
}

Vector3 minimum_vector3(const Vector3 &a, const Vector3 &b)
{
    return Vector3(real_t(Math::min(double(a.x), double(b.x))), real_t(Math::min(double(a.y), double(b.y))),
                   real_t(Math::min(double(a.z), double(b.z))));
}

Vector3 maximum_vector3(const Vector3 &a, const Vector3 &b)
{
    return Vector3(real_t(Math::max(double(a.x), double(b.x))), real_t(Math::max(double(a.y), double(b.y))),
                   real_t(Math::max(double(a.z), double(b.z))));
}

Vector4 maximum_vector4(const Vector4 &a, const Vector4 &b)
{
    return Vector4(real_t(Math::max(double(a.x), double(b.x))), real_t(Math::max(double(a.y), double(b.y))),
                   real_t(Math::max(double(a.z), double(b.z))), real_t(Math::max(double(a.w), double(b.w))));
}

Vector3 mod289(const Vector3 &value)
{
    return value - floor_vector3(value / real_t(289.0)) * real_t(289.0);
}

Vector4 permute(const Vector4 &value)
{
    const Vector4 transformed(real_t((double(value.x) * 34.0 + 1.0) * double(value.x)),
                              real_t((double(value.y) * 34.0 + 1.0) * double(value.y)),
                              real_t((double(value.z) * 34.0 + 1.0) * double(value.z)),
                              real_t((double(value.w) * 34.0 + 1.0) * double(value.w)));
    return transformed - floor_vector4(transformed / real_t(289.0)) * real_t(289.0);
}

double step(double edge, double value)
{
    return value < edge ? 0.0 : 1.0;
}

Vector4 step_vector4(const Vector4 &edge, const Vector4 &value)
{
    return Vector4(real_t(step(edge.x, value.x)), real_t(step(edge.y, value.y)), real_t(step(edge.z, value.z)),
                   real_t(step(edge.w, value.w)));
}

double dot_vector4(const Vector4 &a, const Vector4 &b)
{
    return double(a.x) * double(b.x) + double(a.y) * double(b.y) + double(a.z) * double(b.z)
           + double(a.w) * double(b.w);
}

double simplex_noise(const Vector3 &position)
{
    Vector3 lattice = floor_vector3(
        position + one * real_t(double(position.x) + double(position.y) + double(position.z)) / real_t(3.0));
    const Vector3 corner0
        = position - lattice + one * real_t(double(lattice.x) + double(lattice.y) + double(lattice.z)) / real_t(6.0);
    const Vector3 greater(real_t(step(corner0.y, corner0.x)), real_t(step(corner0.z, corner0.y)),
                          real_t(step(corner0.x, corner0.z)));
    const Vector3 lower = one - greater;
    const Vector3 corner1 = minimum_vector3(greater, Vector3(lower.z, lower.x, lower.y));
    const Vector3 corner2 = maximum_vector3(greater, Vector3(lower.z, lower.x, lower.y));
    const Vector3 position1 = corner0 - corner1 + one / real_t(6.0);
    const Vector3 position2 = corner0 - corner2 + one / real_t(3.0);
    const Vector3 position3 = corner0 - one * real_t(0.5);
    lattice = mod289(lattice);
    const Vector4 permutations = permute(
        permute(permute(Vector4(lattice.z, real_t(double(lattice.z) + double(corner1.z)),
                                real_t(double(lattice.z) + double(corner2.z)), real_t(double(lattice.z) + 1.0)))
                + Vector4(lattice.y, real_t(double(lattice.y) + double(corner1.y)),
                          real_t(double(lattice.y) + double(corner2.y)), real_t(double(lattice.y) + 1.0)))
        + Vector4(lattice.x, real_t(double(lattice.x) + double(corner1.x)), real_t(double(lattice.x) + double(corner2.x)),
                  real_t(double(lattice.x) + 1.0)));
    const Vector4 hashes = permutations - floor_vector4(permutations / real_t(49.0)) * real_t(49.0);
    const Vector4 x_index = floor_vector4(hashes / real_t(7.0));
    const Vector4 y_index = floor_vector4(hashes - x_index * real_t(7.0));
    const Vector4 x = (x_index * real_t(2.0) + half4) / real_t(7.0) - one4;
    const Vector4 y = (y_index * real_t(2.0) + half4) / real_t(7.0) - one4;
    const Vector4 h = one4 - abs_vector4(x) - abs_vector4(y);
    const Vector4 base0(x.x, x.y, y.x, y.y);
    const Vector4 base1(x.z, x.w, y.z, y.w);
    const Vector4 sign0 = floor_vector4(base0) * real_t(2.0) + one4;
    const Vector4 sign1 = floor_vector4(base1) * real_t(2.0) + one4;
    const Vector4 selector = -step_vector4(h, Vector4());
    const Vector4 adjusted0 = Vector4(base0.x, base0.z, base0.y, base0.w)
                              + Vector4(sign0.x, sign0.z, sign0.y, sign0.w)
                                    * Vector4(selector.x, selector.x, selector.y, selector.y);
    const Vector4 adjusted1 = Vector4(base1.x, base1.z, base1.y, base1.w)
                              + Vector4(sign1.x, sign1.z, sign1.y, sign1.w)
                                    * Vector4(selector.z, selector.z, selector.w, selector.w);
    Vector3 gradient0(adjusted0.x, adjusted0.y, h.x);
    Vector3 gradient1(adjusted0.z, adjusted0.w, h.y);
    Vector3 gradient2(adjusted1.x, adjusted1.y, h.z);
    Vector3 gradient3(adjusted1.z, adjusted1.w, h.w);
    const Vector4 normalization(real_t(1.79284291400159 - double(gradient0.length_squared()) * 0.85373472095314),
                                real_t(1.79284291400159 - double(gradient1.length_squared()) * 0.85373472095314),
                                real_t(1.79284291400159 - double(gradient2.length_squared()) * 0.85373472095314),
                                real_t(1.79284291400159 - double(gradient3.length_squared()) * 0.85373472095314));
    gradient0 *= normalization.x;
    gradient1 *= normalization.y;
    gradient2 *= normalization.z;
    gradient3 *= normalization.w;
    Vector4 attenuation = maximum_vector4(Vector4(real_t(0.6 - double(corner0.length_squared())),
                                                  real_t(0.6 - double(position1.length_squared())),
                                                  real_t(0.6 - double(position2.length_squared())),
                                                  real_t(0.6 - double(position3.length_squared()))),
                                          Vector4());
    attenuation *= attenuation;
    attenuation *= attenuation;
    return 42.0
           * dot_vector4(attenuation, Vector4(corner0.dot(gradient0), position1.dot(gradient1), position2.dot(gradient2),
                                              position3.dot(gradient3)));
}

double fbm_noise(const std::vector<Vector4> &layers, const Vector3 &position, size_t index)
{
    const Vector4 &first = layers[index];
    const Vector4 &second = layers[index + 1];
    const Vector4 &third = layers[index + 2];
    double sum = 0.0;
    double amplitude = 1.0;
    double frequency = second.z;
    const Vector3 offset(first.x, first.y, first.z);
    const auto layer_count = static_cast<int64_t>(first.w);
    for (int64_t layer = 0; layer < layer_count; ++layer)
    {
        sum += simplex_noise(position * real_t(frequency) + offset) * amplitude;
        amplitude *= second.x;
        frequency *= second.y;
    }
    return sum * second.w + third.x;
}

double ridge_noise(const std::vector<Vector4> &layers, const Vector3 &position, size_t index)
{
    const Vector4 &first = layers[index];
    const Vector4 &second = layers[index + 1];
    const Vector4 &third = layers[index + 2];
    double sum = 0.0;
    double amplitude = 1.0;
    double frequency = second.z;
    double weight = 1.0;
    const Vector3 offset(first.x, first.y, first.z);
    const auto layer_count = static_cast<int64_t>(first.w);
    for (int64_t layer = 0; layer < layer_count; ++layer)
    {
        double value = 1.0 - std::abs(simplex_noise(position * real_t(frequency) + offset));
        value = std::pow(std::abs(value), double(third.x));
        value *= weight;
        weight = Math::clamp(value * third.y, 0.0, 1.0);
        sum += value * amplitude;
        amplitude *= second.x;
        frequency *= second.y;
    }
    return sum * second.w + third.z;
}

double ridged_fbm(const Vector3 &position, int64_t layer_count, double lacunarity, double persistence, double scale)
{
    double noise = 0.0;
    double frequency = scale / 100.0;
    double amplitude = 1.0;
    for (int64_t layer = 0; layer < layer_count; ++layer)
    {
        const double value = 1.0 - std::abs(simplex_noise(position * real_t(frequency)) * 2.0 - 1.0);
        noise += value * amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
    }
    return noise;
}

double smooth_min(double a, double b, double smoothing)
{
    const double k = Math::max(0.0001, smoothing);
    const double h = Math::clamp((b - a + k) / (2.0 * k), 0.0, 1.0);
    return a * h + b * (1.0 - h) - k * h * (1.0 - h);
}

double smooth_max(double a, double b, double smoothing)
{
    const double k = Math::min(-0.0001, -smoothing);
    const double h = Math::clamp((b - a + k) / (2.0 * k), 0.0, 1.0);
    return a * h + b * (1.0 - h) - k * h * (1.0 - h);
}

double blend(double start_height, double blend_distance, double height)
{
    return Math::smoothstep(start_height - blend_distance * 0.5, start_height + blend_distance * 0.5, height);
}

double terrace_elevation(double elevation, const Vector4 &terrace)
{
    const double scaled = elevation * terrace.x;
    const double level = std::floor(scaled);
    const double t = scaled - level;
    const double stepped = (level + Math::smoothstep(0.5 - terrace.y, 0.5 + terrace.y, t)) / terrace.x;
    return Math::lerp(elevation, stepped, double(terrace.z));
}

template <typename T, typename Packed>
std::vector<T> to_vector(const Packed &packed)
{
    return std::vector<T>(packed.ptr(), packed.ptr() + packed.size());
}

} // namespace

void PlanetSampler::setup(const godot::Dictionary &state)
{
    height_kind = state["height_kind"];
    settings = to_vector<Vector4>(godot::PackedVector4Array(state["settings"]));
    shading_settings = to_vector<Vector4>(godot::PackedVector4Array(state["shading_settings"]));
    moon_points = to_vector<Vector4>(godot::PackedVector4Array(state["moon_points"]));
    ejecta_craters = to_vector<Vector4>(godot::PackedVector4Array(state["ejecta_craters"]));

    const godot::PackedVector3Array centres = state["crater_centres"];
    const godot::PackedFloat64Array radii = state["crater_radii"];
    const godot::PackedFloat64Array floors = state["crater_floors"];
    const godot::PackedFloat64Array smoothness = state["crater_smoothness"];
    const godot::PackedFloat64Array influences = state["crater_influences"];
    craters.clear();
    for (int64_t index = 0; index < centres.size(); ++index)
        craters.push_back({centres[index], radii[index], floors[index], smoothness[index], influences[index]});
    crater_cell_size = state["crater_cell_size"];
    crater_cells.clear();
    if (crater_cell_size > 0.0)
    {
        for (size_t index = 0; index < craters.size(); ++index)
            crater_cells[crater_cell(craters[index].centre)].push_back(static_cast<int32_t>(index));
    }

    const godot::PackedVector3Array directions = state["spike_directions"];
    const godot::PackedFloat64Array heights = state["spike_heights"];
    const godot::PackedFloat64Array sharpness = state["spike_sharpness"];
    const godot::PackedFloat64Array tapers = state["spike_tapers"];
    spikes.clear();
    for (int64_t index = 0; index < directions.size(); ++index)
        spikes.push_back({directions[index], heights[index], sharpness[index], tapers[index]});
}

double PlanetSampler::sample_factor(const Vector3 &direction) const
{
    switch (height_kind)
    {
    case moon:
        return moon_factor(direction);
    case alien:
        return alien_factor(direction);
    case shattered:
        return shattered_factor(direction);
    case moat:
        return moat_factor(direction);
    case asteroid:
        return ridged_radius_factor(direction, 18.0);
    case glacier:
        return ridged_radius_factor(direction, 24.0);
    case mirage:
        return mirage_factor(direction);
    default:
        return earth_factor(direction);
    }
}

Vector4 PlanetSampler::sample_shading_data(const Vector3 &direction) const
{
    if (height_kind == moon)
        return moon_shading_data(direction);
    return earth_shading_data(direction);
}

double PlanetSampler::simple_noise(const Vector3 &position, size_t index) const
{
    return fbm_noise(settings, position, index);
}

double PlanetSampler::shading_noise(const Vector3 &position, size_t index) const
{
    return fbm_noise(shading_settings, position, index);
}

double PlanetSampler::smoothed_ridge_noise(const Vector3 &position, size_t index) const
{
    const Vector4 &smoothing = settings[index + 2];
    const Vector3 normal = position.normalized();
    const Vector3 axis_a = normal.cross(up);
    const Vector3 axis_b = normal.cross(axis_a);
    const real_t offset = real_t(double(smoothing.w) * 0.01);
    return (ridge_noise(settings, position, index) + ridge_noise(settings, position - axis_a * offset, index)
            + ridge_noise(settings, position + axis_a * offset, index)
            + ridge_noise(settings, position - axis_b * offset, index)
            + ridge_noise(settings, position + axis_b * offset, index))
           * 0.2;
}

Vector3 PlanetSampler::warp(const Vector3 &position) const
{
    return Vector3(real_t(simple_noise(position, 9)), real_t(simple_noise(position - one * real_t(100.0), 9)),
                   real_t(simple_noise(position + one * real_t(100.0), 9)))
           * real_t(0.01);
}

PlanetSampler::Cell PlanetSampler::crater_cell(const Vector3 &position) const
{
    return {static_cast<int64_t>(std::floor((double(position.x) + 1.0) / crater_cell_size)),
            static_cast<int64_t>(std::floor((double(position.y) + 1.0) / crater_cell_size)),
            static_cast<int64_t>(std::floor((double(position.z) + 1.0) / crater_cell_size))};
}

double PlanetSampler::crater_contribution(const Vector3 &position, const Crater &crater) const
{
    const Vector4 &rim_settings = settings[19];
    const double distance = double(position.distance_to(crater.centre)) / Math::max(crater.radius, 0.0001);
    const double cavity = distance * distance - 1.0;
    const double rim_x = Math::min(distance - 1.0 - double(rim_settings.y), 0.0);
    const double rim = double(rim_settings.x) * rim_x * rim_x;
    double crater_shape = smooth_max(cavity, crater.floor_height, crater.smoothness);
    crater_shape = smooth_min(crater_shape, rim, crater.smoothness);
    return crater_shape * crater.radius;
}

double PlanetSampler::crater_depth(const Vector3 &position) const
{
    double height = 0.0;
    if (crater_cells.empty())
    {
        for (const Crater &crater : craters)
            height += crater_contribution(position, crater);
        return height;
    }
    const Cell centre = crater_cell(position);
    std::vector<int32_t> candidates;
    for (int64_t x = centre[0] - 1; x < centre[0] + 2; ++x)
        for (int64_t y = centre[1] - 1; y < centre[1] + 2; ++y)
            for (int64_t z = centre[2] - 1; z < centre[2] + 2; ++z)
                if (const auto it = crater_cells.find({x, y, z}); it != crater_cells.end())
                    candidates.insert(candidates.end(), it->second.begin(), it->second.end());
    std::ranges::sort(candidates);
    for (const int32_t index : candidates)
    {
        const Crater &crater = craters[static_cast<size_t>(index)];
        if (double(position.distance_to(crater.centre)) <= crater.influence)
            height += crater_contribution(position, crater);
    }
    return height;
}

double PlanetSampler::spike_height(const Vector3 &position) const
{
    if (spikes.empty())
        return 0.0;
    const Vector3 direction = position.normalized();
    double height = 0.0;
    for (const Spike &spike : spikes)
    {
        const double alignment = Math::max(double(spike.direction.dot(direction)), 0.0);
        double needle = std::pow(alignment, spike.sharpness);
        needle *= Math::lerp(1.0, needle, spike.taper);
        height = Math::max(height, spike.height * needle);
    }
    return height;
}

double PlanetSampler::earth_factor(const Vector3 &position) const
{
    double continent = simple_noise(position, 0);
    const Vector4 &earth_settings = settings[9];
    continent = smooth_max(continent, -double(earth_settings.y), earth_settings.z);
    if (continent < 0.0)
        continent *= 1.0 + double(earth_settings.x);
    const double ridge = smoothed_ridge_noise(position, 6);
    const double mask = blend(0.0, earth_settings.w, simple_noise(position, 3));
    return 1.0 + continent * 0.01 + ridge * 0.01 * mask;
}

double PlanetSampler::moon_factor(const Vector3 &position) const
{
    const double shape = simple_noise(position, 10);
    const double ridge = smoothed_ridge_noise(position, 13);
    const double ridge2 = smoothed_ridge_noise(position, 16);
    return 1.0 + crater_depth(position) + (shape + ridge + ridge2) * 0.01 + spike_height(position);
}

double PlanetSampler::alien_factor(const Vector3 &position) const
{
    const Vector3 warp_offset = warp(position);
    const Vector4 &config = settings[18];
    const Vector4 &parameters = settings[17];
    double continent = simple_noise(position + warp_offset * parameters.x, 0);
    continent = smooth_max(continent, -double(config.y), config.z);
    if (continent < 0.0)
        continent *= 1.0 + double(config.x);
    const double ridge = smoothed_ridge_noise(position + warp_offset * parameters.y, 6);
    const double mask = blend(0.0, config.w, simple_noise(position + warp_offset * parameters.z, 3));
    return 1.0 + continent * 0.01 + ridge * 0.01 * mask + crater_depth(position);
}

double PlanetSampler::mirage_factor(const Vector3 &position) const
{
    const Vector3 warp_offset = warp(position);
    const Vector4 &config = settings[18];
    const Vector4 &parameters = settings[17];
    double continent = simple_noise(position + warp_offset * parameters.x, 0);
    continent = smooth_max(continent, -double(config.y), config.z);
    if (continent < 0.0)
        continent *= 1.0 + double(config.x);
    const double ridge = smoothed_ridge_noise(position + warp_offset * parameters.y, 6);
    const double mask = blend(0.0, config.w, simple_noise(position + warp_offset * parameters.z, 3));
    const double elevation = terrace_elevation(continent + ridge * mask, settings[12]);
    return 1.0 + elevation * 0.01 + crater_depth(position);
}

double PlanetSampler::shattered_factor(const Vector3 &position) const
{
    const Vector3 warp_offset = warp(position);
    double continent = simple_noise(position + warp_offset, 0);
    continent = smooth_min(continent, settings[18].x, settings[18].y);
    return 1.0 + (continent + smoothed_ridge_noise(position, 3) + smoothed_ridge_noise(position, 6)) * 0.01
           + crater_depth(position);
}

double PlanetSampler::moat_factor(const Vector3 &position) const
{
    const Vector4 &config = settings[18];
    double continent = simple_noise(position, 0);
    continent *= 1.0 + continent / double(config.y) * double(config.x);
    if (continent < 0.0)
        continent *= 1.0 + double(config.w) * std::abs(continent);
    return 1.0 + continent * 0.01 + crater_depth(position);
}

double PlanetSampler::ridged_radius_factor(const Vector3 &position, double base_radius) const
{
    const Vector4 &shape = settings[0];
    const Vector4 &terrain = settings[1];
    double surface_radius = base_radius;
    for (int iteration = 0; iteration < 4; ++iteration)
    {
        const double noise = ridged_fbm(position * real_t(surface_radius), static_cast<int64_t>(shape.x), shape.y,
                                        shape.z, shape.w);
        surface_radius = base_radius - (noise - double(terrain.y)) * double(terrain.x);
    }
    return surface_radius / base_radius;
}

Vector4 PlanetSampler::earth_shading_data(const Vector3 &position) const
{
    const double large_noise = shading_noise(position, 6);
    const double small_noise = shading_noise(position, 9);
    const double detail_warp = shading_noise(position, 0);
    const double detail_noise = shading_noise(position + one * real_t(detail_warp) * real_t(0.1), 3);
    return Vector4(real_t(large_noise), real_t(detail_noise), real_t(small_noise), 0.0f);
}

Vector4 PlanetSampler::moon_shading_data(const Vector3 &position) const
{
    const Vector3 domain_warp(real_t(shading_noise(position, 0)),
                              real_t(shading_noise(position + one * real_t(100.0), 0)),
                              real_t(shading_noise(position - one * real_t(100.0), 0)));
    const double detail_warp = shading_noise(position, 3);
    const double detail_noise = shading_noise(position + one * real_t(detail_warp) * real_t(0.1), 6);
    double sphere_noise = std::numeric_limits<double>::infinity();
    for (const Vector4 &point : moon_points)
        sphere_noise = Math::min(sphere_noise,
                                 double((position + domain_warp * real_t(0.1)).distance_to(Vector3(point.x, point.y, point.z)))
                                     / double(point.w));
    godot::Vector2 ejecta_uv(1.0f, 1.0f);
    double closest = 999.0;
    for (const Vector4 &crater : ejecta_craters)
    {
        const Vector3 centre(crater.x, crater.y, crater.z);
        const double scaled_distance = double(position.distance_to(centre)) / double(crater.w);
        if (scaled_distance < closest)
        {
            closest = scaled_distance;
            const Vector3 crater_forward = centre.cross(up).normalized();
            const Vector3 forward = position.cross(centre).normalized();
            const double angle_sign = Math::sign(double(centre.dot(forward.cross(crater_forward))));
            ejecta_uv = godot::Vector2(
                real_t(std::acos(Math::clamp(double(crater_forward.dot(forward)), -1.0, 1.0)) * angle_sign),
                real_t(scaled_distance));
        }
    }
    return Vector4(ejecta_uv.x, ejecta_uv.y, real_t(detail_noise), real_t(sphere_noise));
}

void PlanetSampler::_bind_methods()
{
    godot::ClassDB::bind_method(godot::D_METHOD("setup", "state"), &PlanetSampler::setup);
    godot::ClassDB::bind_method(godot::D_METHOD("sample_factor", "direction"), &PlanetSampler::sample_factor);
    godot::ClassDB::bind_method(godot::D_METHOD("sample_shading_data", "direction"),
                                &PlanetSampler::sample_shading_data);
}

} // namespace outer
