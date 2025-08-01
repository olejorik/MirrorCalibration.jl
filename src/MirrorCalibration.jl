module MirrorCalibration
using JLD2
using HDF5
using GLMakie
using LinearAlgebra
using PhasePlots
using PhaseUtils
using PhaseUtils: igram, diffirst
using EllipseGeometry
using PhaseFromInterferograms

include("DataIO.jl")
using .DataIO: load_responses, load_interferograms, save_voltages

include("Interferograms.jl")

include("HardwareInterface.jl")

export load_responses, load_interferograms, save_voltages
export process_interferograms, inspect_interferograms
export record_interferograms, MirrorCalibrationConfig

end
