#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <array>
#include <cstddef>
#include <cstdint>
#include <map>
#include <vector>

namespace outer
{

struct Crater
{
    godot::Vector3 centre;
    double radius = 0.0;
    double floor_height = 0.0;
    double smoothness = 0.0;
    double influence = 0.0;
};

struct Spike
{
    godot::Vector3 direction;
    double height = 0.0;
    double sharpness = 0.0;
    double taper = 0.0;
};

class PlanetSampler : public godot::RefCounted
{
    GDCLASS(PlanetSampler, godot::RefCounted)

public:
    void setup(const godot::Dictionary &state);
    [[nodiscard]] double sample_factor(const godot::Vector3 &direction) const;
    [[nodiscard]] godot::Vector4 sample_shading_data(const godot::Vector3 &direction) const;

protected:
    static void _bind_methods();

private:
    using Cell = std::array<int64_t, 3>;

    [[nodiscard]] double simple_noise(const godot::Vector3 &position, size_t index) const;
    [[nodiscard]] double shading_noise(const godot::Vector3 &position, size_t index) const;
    [[nodiscard]] double smoothed_ridge_noise(const godot::Vector3 &position, size_t index) const;
    [[nodiscard]] godot::Vector3 warp(const godot::Vector3 &position) const;
    [[nodiscard]] Cell crater_cell(const godot::Vector3 &position) const;
    [[nodiscard]] double crater_contribution(const godot::Vector3 &position, const Crater &crater) const;
    [[nodiscard]] double crater_depth(const godot::Vector3 &position) const;
    [[nodiscard]] double spike_height(const godot::Vector3 &position) const;
    [[nodiscard]] double earth_factor(const godot::Vector3 &position) const;
    [[nodiscard]] double moon_factor(const godot::Vector3 &position) const;
    [[nodiscard]] double alien_factor(const godot::Vector3 &position) const;
    [[nodiscard]] double mirage_factor(const godot::Vector3 &position) const;
    [[nodiscard]] double shattered_factor(const godot::Vector3 &position) const;
    [[nodiscard]] double moat_factor(const godot::Vector3 &position) const;
    [[nodiscard]] double ridged_radius_factor(const godot::Vector3 &position, double base_radius) const;
    [[nodiscard]] godot::Vector4 earth_shading_data(const godot::Vector3 &position) const;
    [[nodiscard]] godot::Vector4 moon_shading_data(const godot::Vector3 &position) const;

    int64_t height_kind = 0;
    std::vector<godot::Vector4> settings;
    std::vector<godot::Vector4> shading_settings;
    std::vector<godot::Vector4> moon_points;
    std::vector<godot::Vector4> ejecta_craters;
    std::vector<Crater> craters;
    double crater_cell_size = 0.0;
    std::map<Cell, std::vector<int32_t>> crater_cells;
    std::vector<Spike> spikes;
};

} // namespace outer
