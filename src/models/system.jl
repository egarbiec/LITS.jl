function update_global_vars!(sys::PSY.System, x::AbstractArray)
    index = PSY.get_ext(sys)[GLOBAL_VARS][:ω_sys_index]
    index == 0 && return
    PSY.get_ext(sys)[GLOBAL_VARS][:ω_sys] = x[index]
    return
end

function system!(out::Vector{T}, dx, x, sys, t) where {T <: Real}

    #Index Setup
    bus_size = length(PSY.get_components(PSY.Bus, sys))
    bus_range = 1:(2 * bus_size)
    bus_vars_count = length(bus_range)
    injection_start = get_injection_pointer(sys)
    injection_count = 1
    branches_start = get_branches_pointer(sys)
    branches_count = 1
    update_global_vars!(sys, x)

    #Network quantities
    V_r = @view x[1:bus_size]
    V_i = @view x[(bus_size + 1):bus_vars_count]
    Sbase = PSY.get_basepower(sys)
    I_injections_r = zeros(T, bus_size)
    I_injections_i = zeros(T, bus_size)
    injection_ode = zeros(T, get_n_injection_states(sys))
    branches_ode = zeros(T, get_n_branches_states(sys))

    for d in PSY.get_components(PSY.DynamicInjection, sys)
        bus_n = PSY.get_number(PSY.get_bus(d)) # TODO: This requires that the bus numbers are indexed 1-N
        n_states = PSY.get_n_states(d)
        ix_range = range(injection_start, length = n_states)
        ode_range = range(injection_count, length = n_states)
        injection_count = injection_count + n_states
        injection_start = injection_start + n_states
        device!(
            x,
            injection_ode,
            view(V_r, bus_n),
            view(V_i, bus_n),
            view(I_injections_r, bus_n),
            view(I_injections_i, bus_n),
            ix_range,
            ode_range,
            d,
            sys,
        )
        out[ix_range] = injection_ode[ode_range] - dx[ix_range]
    end

    dyn_branches = PSY.get_components(DynamicLine, sys)
    if !(isempty(dyn_branches))
        for br in dyn_branches
            arc = PSY.get_arc(br)
            n_states = PSY.get_n_states(br)
            from_bus_number = PSY.get_number(arc.from)
            to_bus_number = PSY.get_number(arc.to)
            ix_dx = [
                from_bus_number,
                from_bus_number + bus_size,
                to_bus_number,
                to_bus_number + bus_size,
            ]
            ix_range = range(branches_start, length = n_states)
            ode_range = range(branches_count, length = n_states)
            branches_count = branches_count + n_states
            branch!(
                x,
                dx,
                branches_ode,
                #Get Voltage data
                view(V_r, from_bus_number),
                view(V_i, from_bus_number),
                view(V_r, to_bus_number),
                view(V_i, to_bus_number),
                #Get Current data
                view(I_injections_r, from_bus_number),
                view(I_injections_i, from_bus_number),
                view(I_injections_r, to_bus_number),
                view(I_injections_i, to_bus_number),
                ix_range,
                ix_dx,
                ode_range,
                br,
                sys,
            )
            out[ix_range] = branches_ode[ode_range] - dx[ix_range]
        end
    end

    for d in PSY.get_components(PSY.StaticInjection, sys)
        bus_n = PSY.get_number(PSY.get_bus(d))

        device!(
            view(V_r, bus_n),
            view(V_i, bus_n),
            view(I_injections_r, bus_n),
            view(I_injections_i, bus_n),
            d,
            sys,
        )
    end

    out[bus_range] = kcl(PSY.get_ext(sys)[YBUS], V_r, V_i, I_injections_r, I_injections_i)

end
