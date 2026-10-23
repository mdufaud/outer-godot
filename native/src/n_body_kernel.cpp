#include "n_body_kernel.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstddef>
#include <vector>

namespace outer
{

godot::Array NBodyKernel::advance(const godot::PackedFloat64Array &positions,
                                  const godot::PackedFloat64Array &velocities,
                                  const godot::Array &pair_mu,
                                  double delta,
                                  int64_t steps,
                                  double min_separation) const
{
    const int64_t count = pair_mu.size();
    std::vector<double> mu;
    mu.reserve(static_cast<size_t>(count * count));
    for (int64_t i = 0; i < count; ++i)
    {
        const godot::PackedFloat64Array row = pair_mu[i];
        for (int64_t j = 0; j < count; ++j)
            mu.push_back(row[j]);
    }

    godot::PackedFloat64Array next_positions = positions;
    godot::PackedFloat64Array next_velocities = velocities;
    double *position = next_positions.ptrw();
    double *velocity = next_velocities.ptrw();
    const int64_t value_count = next_positions.size();
    for (int64_t step = 0; step < steps; ++step)
    {
        for (int64_t i = 0; i < count; ++i)
        {
            const int64_t base = i * 3;
            const double x = position[base];
            const double y = position[base + 1];
            const double z = position[base + 2];
            godot::Vector3 acceleration;
            for (int64_t j = 0; j < count; ++j)
            {
                if (i == j)
                    continue;
                const int64_t other = j * 3;
                const godot::Vector3 delta_position(static_cast<real_t>(position[other] - x),
                                                    static_cast<real_t>(position[other + 1] - y),
                                                    static_cast<real_t>(position[other + 2] - z));
                const double distance = delta_position.length();
                if (distance < min_separation)
                    continue;
                acceleration += delta_position * static_cast<real_t>(mu[static_cast<size_t>(i * count + j)])
                                / static_cast<real_t>(distance * distance * distance);
            }
            velocity[base] += double(acceleration.x) * delta;
            velocity[base + 1] += double(acceleration.y) * delta;
            velocity[base + 2] += double(acceleration.z) * delta;
        }
        for (int64_t i = 0; i < value_count; ++i)
            position[i] += velocity[i] * delta;
    }
    return godot::Array::make(next_positions, next_velocities);
}

void NBodyKernel::_bind_methods()
{
    godot::ClassDB::bind_method(
        godot::D_METHOD("advance", "positions", "velocities", "pair_mu", "delta", "steps", "min_separation"),
        &NBodyKernel::advance);
}

} // namespace outer
