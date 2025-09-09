# Hardware interface functions for mirror calibration
# Functions for interfacing with deformable mirrors using python_oko library

# Note: PythonCall should be configured in the main script before loading this package
# ENV["JULIA_CONDAPKG_BACKEND"] = "Null"  ## Don't install any conda packages
# ENV["JULIA_PYTHONCALL_EXE"] = "C:\\Users\\olegs\\miniconda3\\envs\\python_OKO\\python.exe"  ## Default Python environment
# @info "Using PythonCall with existing conda environment: $(ENV["JULIA_PYTHONCALL_EXE"])"
using PythonCall

"""
Configuration structure for mirror calibration workflow
"""
Base.@kwdef struct MirrorCalibrationConfig
    mirror_type::String = "PDM 37ch,trihex grid"  ## Type of deformable mirror (e.g., "OKO-37", "PDM30")
    dac_addresses::Vector{String} = ["D40V2q05"]  ## DAC addresses for mirror control (as strings)
    data_folder::String  ## Base folder for saving all data (required field)
    calibration_filename::String = "calibration.h5"  ## Name for calibration *.h5 file
    test_filename::String = "test"  ## Name for test *.h5 file (without extension)
    experiment_mode::String = "deg0set"  ## Experiment mode: "set", "degauss", "deg0set"
    dac_type::String = "USB DAC 40ch, 12bit"  ## DAC type (e.g., "USB DAC 40ch, 12bit")

    ## Additional fields for PDM30 testing
    n_actuators::Int = 37  ## Number of actuators in the mirror
    settle::Float64 = 0.5  ## Time to wait (in seconds) after setting voltages before acquiring data
    test_actuators::Vector{Int} = [1]  ## Selected actuators for poke testing
    n_poke_levels::Int = 5  ## Number of voltage levels for poke sequence
    poke_bias::Float64 = 0.0  ## Bias voltage for poke testing
    experiment_description::String = "Mirror calibration experiment"  ## Description for the experiment

    ## Optional pre-generated calibration sequences to store with the config
    ## Defaults are generated from other fields via `calibration_voltages`.
    calibration_names::Vector{String} = begin
        std_names, std_patterns = create_standard_patterns(
            n_actuators; patterns=[:bias, :min, :max]
        )
        acts = if (length(test_actuators) == 1 && first(test_actuators) == 1)
            collect(1:n_actuators)
        else
            test_actuators
        end
        first(
            calibration_voltages(
                n_actuators;
                nlevels=n_poke_levels,
                bias=poke_bias,
                actuators=acts,
                trace_PTT=true,
                standard_patterns=(std_names, std_patterns),
            ),
        )
    end
    calibration_patterns::Vector{Vector{Float64}} = begin
        std_names, std_patterns = create_standard_patterns(
            n_actuators; patterns=[:bias, :min, :max]
        )
        acts = if (length(test_actuators) == 1 && first(test_actuators) == 1)
            collect(1:n_actuators)
        else
            test_actuators
        end
        last(
            calibration_voltages(
                n_actuators;
                nlevels=n_poke_levels,
                bias=poke_bias,
                actuators=acts,
                trace_PTT=true,
                standard_patterns=(std_names, std_patterns),
            ),
        )
    end
end



"""
Validate configuration parameters
"""
function validate_config(config::MirrorCalibrationConfig)
    ## Check if data folder exists, create if needed
    if !isdir(config.data_folder)
        mkpath(config.data_folder)
        @info "Created data folder: $(config.data_folder)"
    end

    ## Validate DAC addresses
    if isempty(config.dac_addresses)
        error("DAC addresses cannot be empty")
    end


    return true
end


"""
    record_interferograms(voltage_names, voltage_patterns, config::MirrorCalibrationConfig)

Record interferograms for a set of voltages using PythonCall interface to python_oko.

# Arguments
- `voltage_names::Vector{String}`: Names for each voltage pattern (must match length of voltage_patterns)
- `voltage_patterns::Vector{Vector{Float64}}`: Voltage vectors for each pattern (all must have length n_actuators)
- `config::MirrorCalibrationConfig`: Configuration structure containing mirror and experiment parameters

# Returns
- `Bool`: true if experiment completed successfully, false otherwise

# Example
```julia
# Create voltage patterns
names = ["bias", "poke_1", "poke_8"]
patterns = [zeros(37), [1.0; zeros(36)], [zeros(7); 1.0; zeros(29)]]

# Configure experiment
config = MirrorCalibrationConfig(
    data_folder = "test_data",
    calibration_filename = "calibration.h5",
    test_filename = "test",
    test_actuators = [1],
    poke_bias = -1.0,
    experiment_description = "Simple test experiment"
)

# Record interferograms
success = record_interferograms(names, patterns, config)
```
"""
function record_interferograms(
    voltage_names::Vector{String},
    voltage_patterns::Vector{Vector{Float64}},
    config::MirrorCalibrationConfig,
)
    ## Validate configuration
    validate_config(config)

    ## Check if output file already exists to prevent data loss
    output_filepath = joinpath(config.data_folder, config.test_filename * ".h5")
    if isfile(output_filepath)
        error(
            "Output file already exists: $output_filepath. Please use a different filename or move/delete the existing file to prevent data loss.",
        )
        ## TODO: Add functionality to automatically generate versioned filename (e.g., test_v001.h5, test_v002.h5)
    end

    ## Validate input arrays
    if length(voltage_names) != length(voltage_patterns)
        error(
            "voltage_names and voltage_patterns must have the same length (got $(length(voltage_names)) and $(length(voltage_patterns)))",
        )
    end

    if isempty(voltage_names)
        error("Must provide at least one voltage pattern")
    end

    ## Log the start of the experiment
    @info "Recording interferograms using PythonCall interface..."
    @info "Voltage patterns: $(voltage_names)"
    @info "Configuration: $(config.mirror_type), $(config.experiment_mode), $(config.n_actuators) actuators"

    try
        ## Import Python modules (exactly as in PDM30-37_test.py)
        np = pyimport("numpy")
        h5py = pyimport("h5py")
        os = pyimport("os")
        sys = pyimport("sys")

        ## Import from python_oko (exactly as in PDM30-37_test.py)
        DM = pyimport("python_oko.mirror.dm" => "DM")
        Experiment = pyimport("python_oko.experiment.acquisition" => "Experiment")
        makeFolder = pyimport("python_oko.utils.helpers" => "makeFolder")

        ## Configuration parameters from config struct
        DM_CHANNELS = config.n_actuators
        MIRROR_TYPE = config.mirror_type
        DAC_TYPE = config.dac_type
        EXPERIMENT_MODE = config.experiment_mode
        SETTLE = config.settle

        @info "Configuration: $DM_CHANNELS channels, $MIRROR_TYPE, $DAC_TYPE, $EXPERIMENT_MODE, $SETTLE time delay"

        ## Ensure all voltage vectors have the correct length
        for (i, voltages) in enumerate(voltage_patterns)
            if length(voltages) != config.n_actuators
                error(
                    "Voltage pattern '$(voltage_names[i])' has $(length(voltages)) elements, expected $(config.n_actuators)",
                )
            end
        end

        ## Create voltage arrays in the same format as Python generate_voltages function
        ## Convert each Julia vector to a numpy array, then create a list of arrays
        voltage_arrays = [np.array(v) for v in voltage_patterns]

        ## Stack the arrays (this mimics what Python's generate_voltages returns)
        test_voltages = np.stack(voltage_arrays)
        test_names = np.array(voltage_names)

        @info "Total voltage patterns: $(length(voltage_names))"
        @info "Pattern names: $(voltage_names)"
        @info "Voltage matrix shape: $(test_voltages.shape)"

        ## Create data folder if it doesn't exist
        mkpath(config.data_folder)

        ## Run the experiment (exactly as in PDM30-37_test.py structure)
        @info "Starting experiment..."

        ## Use pywith for context manager (equivalent to Python's 'with' statement)
        result = pywith(
            DM(;
                mirror_type=MIRROR_TYPE,
                dac_type=DAC_TYPE,
                dac_ids=config.dac_addresses,
                go=EXPERIMENT_MODE,
                settle=SETTLE,
            ),
        ) do dm
            # Check if dm.h is None (equivalent to Python's 'if dm.h is None:')
            if pyis(dm.h, pybuiltins.None)
                @error "ERROR: Failed to initialize the deformable mirror."
                return false
            end

            @info "Mirror initialized successfully. Starting experiment with $(length(voltage_names)) voltage patterns..."

            ## Use nested pywith for Experiment context manager
            pywith(
                Experiment(;
                    dm=dm,
                    voltages=test_voltages,
                    voltageNames=test_names,
                    descr=config.experiment_description,  # Use description from config
                    foldername=config.data_folder,       # Specify output folder
                    fn=config.test_filename,            # Specify output filename (without extension)
                    go=EXPERIMENT_MODE,
                ),
            ) do experiment
                experiment.run()  # This is the blocking call that runs the experiment
                @info "Experiment completed"
                return true
            end
        end

        if result
            @info "Experiment completed successfully"
            @info "Data saved to: $(config.data_folder)"
            return true
        else
            @error "Experiment failed"
            return false
        end

    catch e
        @error "Failed to record interferograms: $e"
        @error "Error type: $(typeof(e))"
        return false
    end
end


"""
    calibration_voltages(n_actuators::Int;
                        nlevels::Int=5,
                        bias::Float64=0.0,
                        actuators::Vector{Int}=collect(1:n_actuators),
                        trace_PTT::Bool=false,
                        reference_voltages::Union{Vector{Float64}, Nothing}=nothing,
                        standard_patterns::Union{Tuple{Vector{String}, Vector{Vector{Float64}}}, Nothing}=nothing)

Generate calibration voltage patterns for mirror characterization.

This function creates ordered voltage patterns where each actuator is tested
individually at multiple voltage levels while keeping all other actuators at a bias voltage.
Optionally, standard voltage patterns can be appended to the calibration sequence.

## Arguments
- `n_actuators::Int`: Total number of actuators in the mirror
- `nlevels::Int=5`: Number of voltage levels to test for each actuator (distributed from -1 to 1)
- `bias::Float64=0.0`: Bias voltage applied to all non-tested actuators (normalized -1 to 1)
- `actuators::Vector{Int}=collect(1:n_actuators)`: Which actuators to test (1-indexed)
- `trace_PTT::Bool=false`: If true, insert reference voltages between each test pattern
- `reference_voltages::Union{Vector{Float64}, Nothing}=nothing`: Custom reference pattern (defaults to bias pattern)
- `standard_patterns::Union{Tuple{Vector{String}, Vector{Vector{Float64}}}, Nothing}=nothing`: Optional tuple of (names, patterns) for standard voltage patterns to append

## Returns
- `Tuple{Vector{String}, Vector{Vector{Float64}}}`: Tuple of (voltage_names, voltage_patterns) where:
  - `voltage_names`: Ordered vector of descriptive pattern names
  - `voltage_patterns`: Ordered vector of voltage vectors (each normalized -1 to 1)

## Example
```julia
# Generate voltages for 37-actuator mirror, testing actuators 1, 8, 20 with 5 levels each
voltage_names, voltage_patterns = calibration_voltages(37;
    nlevels=5,
    bias=-0.5,
    actuators=[1, 8, 20],
    trace_PTT=true
)

# With standard patterns
std_names = ["bias", "min", "max"]
std_patterns = [zeros(37), fill(-1.0, 37), fill(1.0, 37)]
voltage_names, voltage_patterns = calibration_voltages(37;
    nlevels=3,
    actuators=[1, 8],
    trace_PTT=true,
    standard_patterns=(std_names, std_patterns)
)
```
"""
function calibration_voltages(
    n_actuators::Int;
    nlevels::Int=5,
    bias::Float64=0.0,
    actuators::Vector{Int}=collect(1:n_actuators),
    trace_PTT::Bool=false,
    reference_voltages::Union{Vector{Float64},Nothing}=nothing,
    standard_patterns::Union{Tuple{Vector{String},Vector{Vector{Float64}}},Nothing}=nothing,
)

    ## Validate inputs
    @assert n_actuators > 0 "Number of actuators must be positive"
    @assert nlevels > 0 "Number of levels must be positive"
    @assert -1.0 <= bias <= 1.0 "Bias voltage must be in range [-1, 1]"
    @assert all(1 <= act <= n_actuators for act in actuators) "All actuator indices must be in range [1, $n_actuators]"

    ## Validate standard patterns if provided
    if standard_patterns !== nothing
        std_names, std_patterns = standard_patterns
        @assert length(std_names) == length(std_patterns) "Standard pattern names and patterns must have the same length"
        @assert !isempty(std_names) "Standard patterns must not be empty if provided"

        for (i, pattern) in enumerate(std_patterns)
            @assert length(pattern) == n_actuators "Standard pattern '$(std_names[i])' must have length $n_actuators (got $(length(pattern)))"
            @assert all(-1.0 <= v <= 1.0 for v in pattern) "All voltages in standard pattern '$(std_names[i])' must be in range [-1, 1]"
        end
    end

    ## Set up reference voltage pattern
    if reference_voltages === nothing
        reference_voltages = fill(bias, n_actuators)
    else
        @assert length(reference_voltages) == n_actuators "Reference voltages must have length $n_actuators"
        @assert all(-1.0 <= v <= 1.0 for v in reference_voltages) "All reference voltages must be in range [-1, 1]"
    end

    ## Generate voltage levels for testing (linearly spaced from -1 to 1)
    test_levels = if nlevels == 1
        [0.0]  ## Single level at zero if only one level requested
    else
        range(-1.0, 1.0; length=nlevels)
    end

    ## Initialize ordered arrays for voltage names and patterns
    voltage_names = String[]
    voltage_patterns = Vector{Float64}[]

    ## Add initial reference pattern if trace_PTT is enabled
    if trace_PTT
        push!(voltage_names, "ref_initial")
        push!(voltage_patterns, copy(reference_voltages))
    end

    ## Generate voltage patterns for each actuator
    for actuator in actuators
        for (level_idx, voltage_level) in enumerate(test_levels)
            ## Start with bias/reference pattern
            pattern = copy(reference_voltages)

            ## Set the test actuator to the current voltage level
            pattern[actuator] = voltage_level

            ## Create descriptive name
            pattern_name = "act$(actuator)_lev$(level_idx)_v$(round(voltage_level, digits=2))"
            push!(voltage_names, pattern_name)
            push!(voltage_patterns, pattern)
        end

        ## Add reference pattern after completing all levels for this actuator if trace_PTT is enabled
        ## (but not after the last actuator - that's handled by final reference)
        if trace_PTT && actuator != actuators[end]
            ref_name = "ref_after_act$(actuator)"
            push!(voltage_names, ref_name)
            push!(voltage_patterns, copy(reference_voltages))
        end
    end

    ## Add standard patterns if provided
    if standard_patterns !== nothing
        std_names, std_patterns = standard_patterns

        ## Add reference pattern before standard patterns if trace_PTT is enabled and we have previous patterns
        if trace_PTT && !isempty(voltage_names)
            push!(voltage_names, "ref_before_standards")
            push!(voltage_patterns, copy(reference_voltages))
        end

        ## Add each standard pattern
        for (std_name, std_pattern) in zip(std_names, std_patterns)
            push!(voltage_names, std_name)
            push!(voltage_patterns, copy(std_pattern))

            ## Add reference pattern after each standard pattern if trace_PTT is enabled
            ## (except after the last standard pattern, handled by final reference below)
            # if trace_PTT && std_name != std_names[end]
            #     ref_name = "ref_after_$(std_name)"
            #     push!(voltage_names, ref_name)
            #     push!(voltage_patterns, copy(reference_voltages))
            # end
        end
    end

    ## Add final reference pattern if trace_PTT is enabled
    if trace_PTT
        push!(voltage_names, "ref_final")
        push!(voltage_patterns, copy(reference_voltages))
    end

    @info "Generated $(length(voltage_names)) voltage patterns for $(length(actuators)) actuators with $nlevels levels each"
    if trace_PTT
        @info "PTT tracing enabled: reference patterns inserted between test patterns"
    end
    if standard_patterns !== nothing
        std_names, _ = standard_patterns
        @info "Added $(length(std_names)) standard patterns: $(std_names)"
    end

    ## Validate that arrays have the same length
    @assert length(voltage_names) == length(voltage_patterns) "Voltage names and patterns arrays must have the same length"

    return voltage_names, voltage_patterns
end

"""
    calibration_voltages(
        bias::AbstractVector{<:Real},
        modes::AbstractVector{<:AbstractVector{<:Real}};
        levels::Union{Nothing,AbstractVector{<:Real}}=nothing,
        nlevels::Int=5,
        mode_names::Union{Nothing,AbstractVector{<:AbstractString}}=nothing,
        trace_PTT::Bool=false,
        reference_voltages::Union{Nothing,AbstractVector{<:Real}}=nothing,
        standard_patterns::Union{Nothing,Tuple{Vector{String},Vector{Vector{Float64}}}}=nothing,
        scale_strategy::Symbol=:safe,
        clip_bounds::Tuple{Float64,Float64}=(-1.0, 1.0),
    ) -> Tuple{Vector{String},Vector{Vector{Float64}}}

Generate calibration voltage patterns using arbitrary "modes" instead of single‑actuator pokes.

Inputs
- bias: base voltage distribution (length Nact), values typically in [-1,1].
- modes: vector of mode vectors (each length Nact). Each pattern is bias + a*mode.

Keywords
- levels: explicit multipliers for each mode (e.g., -1:0.5:1). If `nothing`, uses `range(-1,1; length=nlevels)`.
- nlevels: number of levels when `levels === nothing`.
- mode_names: optional names mapped 1:1 to `modes` for pattern naming; defaults to ["mode1", ...].
- trace_PTT: insert reference frames (same behavior as scalar API): ref_initial, ref_after_mode<i>, ref_final.
- reference_voltages: custom reference vector; defaults to `bias`.
- standard_patterns: optional (names, vectors) appended after generated patterns.
- scale_strategy: how to handle bounds (clip_bounds):
  • :safe  — scale each mode so max symmetric |a| fits within bounds for all actuators, then apply levels∈[-1,1] as relative factors.
  • :raw   — use levels directly; warn if any values exceed bounds.
  • :clip  — use levels directly and clip final voltages to bounds.
- clip_bounds: (low, high) voltage limits; default (-1, 1).

Returns
- (voltage_names, voltage_patterns) compatible with the existing API.

Notes
- Modes with near‑zero magnitude under :safe imply zero allowable amplitude; patterns reduce to the bias.
- All outputs are Float64 vectors of length Nact.
"""
function calibration_voltages(
    bias::AbstractVector{<:Real},
    modes::AbstractVector{<:AbstractVector{<:Real}};
    levels::Union{Nothing,AbstractVector{<:Real}}=nothing,
    nlevels::Int=5,
    mode_names::Union{Nothing,AbstractVector{<:AbstractString}}=nothing,
    trace_PTT::Bool=false,
    reference_voltages::Union{Nothing,AbstractVector{<:Real}}=nothing,
    standard_patterns::Union{Nothing,Tuple{Vector{String},Vector{Vector{Float64}}}}=nothing,
    scale_strategy::Symbol=:safe,
    clip_bounds::Tuple{Float64,Float64}=(-1.0, 1.0),
)
    # --- validation ---
    @assert !isempty(bias) "bias vector must be non-empty"
    N = length(bias)
    @assert all(isfinite, bias) "bias must contain finite values"
    @assert clip_bounds[1] < clip_bounds[2] "clip_bounds must be (low < high)"
    @assert scale_strategy in (:safe, :raw, :clip) "scale_strategy must be :safe, :raw, or :clip"
    @assert all(length(m) == N for m in modes) "all mode vectors must have length == length(bias)"
    @assert all(all(isfinite, m) for m in modes) "modes must contain finite values"

    # reference pattern
    ref = if reference_voltages === nothing
        collect(Float64, bias)
    else
        collect(Float64, reference_voltages)
    end
    @assert length(ref) == N "reference_voltages must have same length as bias"
    @assert all(isfinite, ref) "reference_voltages must contain finite values"

    # levels
    lev = if levels === nothing
        collect(range(-1.0, 1.0; length=max(nlevels, 1)))
    else
        collect(Float64, levels)
    end
    @assert !isempty(lev) "levels must be non-empty"
    @assert all(isfinite, lev) "levels must be finite"

    # mode names
    mdnames = if mode_names === nothing
        ["mode$(i)" for i in 1:length(modes)]
    else
        collect(String, mode_names)
    end
    @assert length(mdnames) == length(modes) "mode_names length must equal number of modes"

    # helper: allowed interval [amin, amax] such that low <= bias + a*mode <= high for all entries
    low, high = clip_bounds
    function allowed_interval(b::AbstractVector{<:Real}, m::AbstractVector{<:Real})
        amin = -Inf
        amax = +Inf
        @inbounds for i in eachindex(b, m)
            bi = Float64(b[i])
            mi = Float64(m[i])
            if mi == 0.0
                # no constraint from this coordinate
                if bi < low - 1e-12 || bi > high + 1e-12
                    # bias already violates bounds; tighten to empty interval
                    return (1.0, 0.0)
                end
                continue
            end
            # Solve low <= bi + a*mi <= high for a
            a1 = (low - bi) / mi
            a2 = (high - bi) / mi
            lo = min(a1, a2)
            hi = max(a1, a2)
            amin = max(amin, lo)
            amax = min(amax, hi)
            if amin > amax
                return (1.0, 0.0)  # empty interval
            end
        end
        return (amin, amax)
    end

    # helper: build pattern with chosen strategy
    function build_patterns_for_mode!(names, patterns, b, m, mdname)
        if scale_strategy === :safe
            amin, amax = allowed_interval(b, m)
            sym = min(amax, -amin)
            sym = isfinite(sym) ? max(sym, 0.0) : 0.0
            if sym == 0.0
                @warn "Mode $(mdname) has zero allowable amplitude under :safe; generating bias-only patterns"
            end
            for (k, lv) in enumerate(lev)
                α = Float64(lv) * sym
                pat = collect(Float64, b .+ α .* m)
                # no need to clip; computed to stay within bounds
                push!(names, "mode=$(mdname)_lev=$(k)_s=$(round(α, digits=3))")
                push!(patterns, pat)
            end
        elseif scale_strategy === :raw
            for (k, lv) in enumerate(lev)
                pat = collect(Float64, b .+ Float64(lv) .* m)
                if any(p -> p < low - 1e-12 || p > high + 1e-12, pat)
                    @warn "Pattern for $(mdname) level $(k) exceeds bounds $(clip_bounds); consider :safe or :clip"
                end
                push!(names, "mode=$(mdname)_lev=$(k)_s=$(round(Float64(lv), digits=3))")
                push!(patterns, pat)
            end
        else # :clip
            for (k, lv) in enumerate(lev)
                pat = collect(Float64, b .+ Float64(lv) .* m)
                @inbounds for i in eachindex(pat)
                    if pat[i] < low
                        pat[i] = low
                    elseif pat[i] > high
                        pat[i] = high
                    end
                end
                push!(names, "mode=$(mdname)_lev=$(k)_s=$(round(Float64(lv), digits=3))")
                push!(patterns, pat)
            end
        end
        return nothing
    end

    # assemble sequence
    names = String[]
    patterns = Vector{Float64}[]

    if trace_PTT
        push!(names, "ref_initial")
        push!(patterns, copy(ref))
    end

    for i in 1:length(modes)
        build_patterns_for_mode!(names, patterns, bias, modes[i], mdnames[i])
        if trace_PTT && i != length(modes)
            push!(names, "ref_after_mode$(i)")
            push!(patterns, copy(ref))
        end
    end

    if standard_patterns !== nothing
        std_names, std_patterns = standard_patterns
        @assert length(std_names) == length(std_patterns) "Standard pattern names/patterns length mismatch"
        if trace_PTT && !isempty(names)
            push!(names, "ref_before_standards")
            push!(patterns, copy(ref))
        end
        for (sn, sp) in zip(std_names, std_patterns)
            @assert length(sp) == N "Standard pattern $(sn) must have length $(N)"
            push!(names, sn)
            push!(patterns, collect(Float64, sp))
        end
    end

    if trace_PTT
        push!(names, "ref_final")
        push!(patterns, copy(ref))
    end

    @assert length(names) == length(patterns)
    return names, patterns
end

"""
    create_standard_patterns(n_actuators::Int; patterns::Vector{Symbol}=[:bias, :min, :max])

Create common standard voltage patterns for mirror testing.

## Arguments
- `n_actuators::Int`: Number of actuators in the mirror
- `patterns::Vector{Symbol}`: Which standard patterns to create (options: :bias, :min, :max, :flat_half, :flat_quarter, :ring1, :ring2, ..., :ringN)

## Returns
- `Tuple{Vector{String}, Vector{Vector{Float64}}}`: Tuple of (pattern_names, voltage_patterns)

## Available Patterns
- `:bias`: All actuators at 0.0
- `:min`: All actuators at -1.0
- `:max`: All actuators at +1.0
- `:flat_half`: All actuators at 0.5
- `:flat_quarter`: All actuators at 0.25
- `:ringN`: Actuators 1 to N at -1.0, remaining at +1.0 (e.g., :ring5, :ring10)

## Example
```julia
# Create standard patterns
std_names, std_patterns = create_standard_patterns(37; patterns=[:bias, :min, :max])

# Create patterns with rings
std_names, std_patterns = create_standard_patterns(37; patterns=[:bias, :ring5, :ring10, :max])

# Use with calibration_voltages
voltage_names, voltage_patterns = calibration_voltages(37;
    actuators=[1, 8, 20],
    standard_patterns=(std_names, std_patterns)
)
```
"""
function create_standard_patterns(
    n_actuators::Int; patterns::Vector{Symbol}=[:bias, :min, :max]
)
    pattern_names = String[]
    voltage_patterns = Vector{Float64}[]

    for pattern in patterns
        if pattern == :bias
            push!(pattern_names, "bias")
            push!(voltage_patterns, zeros(Float64, n_actuators))
        elseif pattern == :min
            push!(pattern_names, "min")
            push!(voltage_patterns, fill(-1.0, n_actuators))
        elseif pattern == :max
            push!(pattern_names, "max")
            push!(voltage_patterns, fill(1.0, n_actuators))
        elseif pattern == :flat_half
            push!(pattern_names, "flat_half")
            push!(voltage_patterns, fill(0.5, n_actuators))
        elseif pattern == :flat_quarter
            push!(pattern_names, "flat_quarter")
            push!(voltage_patterns, fill(0.25, n_actuators))
        elseif startswith(string(pattern), "ring")
            ## Extract the ring number from the pattern name (e.g., :ring5 -> 5)
            pattern_str = string(pattern)
            ring_match = match(r"ring(\d+)", pattern_str)

            if ring_match !== nothing
                ring_n = parse(Int, ring_match.captures[1])

                if ring_n > 0 && ring_n < n_actuators
                    ## Create ring pattern: actuators 1 to N at -1, rest at +1
                    ring_pattern = fill(1.0, n_actuators)
                    ring_pattern[1:ring_n] .= -1.0

                    push!(pattern_names, "ring$(ring_n)")
                    push!(voltage_patterns, ring_pattern)
                else
                    @warn "Ring pattern $(pattern): ring number $ring_n must be between 1 and $(n_actuators-1), skipping"
                end
            else
                @warn "Invalid ring pattern format: $(pattern), expected format like :ring5, skipping"
            end
        else
            @warn "Unknown standard pattern: $pattern, skipping"
        end
    end

    @info "Created $(length(pattern_names)) standard patterns: $(pattern_names)"
    return pattern_names, voltage_patterns
end
