#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <cstdint>

namespace outer
{

class NBodyKernel : public godot::RefCounted
{
    GDCLASS(NBodyKernel, godot::RefCounted)

public:
    [[nodiscard]] godot::Array advance(const godot::PackedFloat64Array &positions,
                                       const godot::PackedFloat64Array &velocities,
                                       const godot::Array &pair_mu,
                                       double delta,
                                       int64_t steps,
                                       double min_separation) const;

protected:
    static void _bind_methods();
};

} // namespace outer
