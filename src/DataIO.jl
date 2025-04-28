module DataIO

using JLD2
using HDF5

"""
    load_responses(file_path::AbstractString) -> NamedTuple{(:responses,:biases,:ap)}

Load responses, biases, and aperture from a JLD2 file.
"""
function load_responses(file_path::AbstractString)
    @info "Loading JLD2 responses from $file_path"
    jldopen(file_path, "r") do f
        responses = f["responses"]
        biases = f["biases"]
        ap = f["ap"]
        return (responses=responses, biases=biases, ap=ap)
    end
end

"""
    load_interferograms(file_path::AbstractString) -> Vector{Array{Float64}}

Load interferogram frames from an HDF5 file assuming structure /images/<subgroup>/<subgroup>.
"""
function load_interferograms(file_path::AbstractString)
    @info "Loading HDF5 interferograms from $file_path"
    h5open(file_path, "r") do f
        imgs = f["images"]
        # navigate two levels deep: e.g. images/o/1
        level1 = first(keys(imgs))
        grp1 = imgs[level1]
        level2 = first(keys(grp1))
        grp2 = grp1[level2]
        # collect and convert to Float64
        return [Float64.(grp2[name][]) for name in keys(grp2)]
    end
end

"""
    save_voltages(voltages::Dict{String,AbstractArray}, file_path::AbstractString)

Save a Dict of voltage arrays into an HDF5 file under group "voltages".
"""
function save_voltages(voltages::Dict{String,<:AbstractArray}, file_path::AbstractString)
    @info "Saving voltages to HDF5 file $file_path"
    h5open(file_path, "w") do f
        g = create_group(f, "voltages")
        for (name, data) in voltages
            g[name] = data
        end
    end
end

end # module DataIO
