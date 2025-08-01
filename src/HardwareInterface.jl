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
    test_actuators::Vector{Int} = [1]  ## Selected actuators for poke testing
    n_poke_levels::Int = 5  ## Number of voltage levels for poke sequence
    poke_bias::Float64 = 0.0  ## Bias voltage for poke testing
    experiment_description::String = "Mirror calibration experiment"  ## Description for the experiment
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

        @info "Configuration: $DM_CHANNELS channels, $MIRROR_TYPE, $DAC_TYPE, $EXPERIMENT_MODE"

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
                        reference_voltages::Union{Vector{Float64}, Nothing}=nothing)

Generate calibration voltage patterns for mirror characterization.

This function creates ordered voltage patterns where each actuator is tested
individually at multiple voltage levels while keeping all other actuators at a bias voltage.

## Arguments
- `n_actuators::Int`: Total number of actuators in the mirror
- `nlevels::Int=5`: Number of voltage levels to test for each actuator (distributed from -1 to 1)
- `bias::Float64=0.0`: Bias voltage applied to all non-tested actuators (normalized -1 to 1)
- `actuators::Vector{Int}=collect(1:n_actuators)`: Which actuators to test (1-indexed)
- `trace_PTT::Bool=false`: If true, insert reference voltages between each test pattern
- `reference_voltages::Union{Vector{Float64}, Nothing}=nothing`: Custom reference pattern (defaults to bias pattern)

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
```
"""
function calibration_voltages(
    n_actuators::Int;
    nlevels::Int=5,
    bias::Float64=0.0,
    actuators::Vector{Int}=collect(1:n_actuators),
    trace_PTT::Bool=false,
    reference_voltages::Union{Vector{Float64},Nothing}=nothing,
)

    ## Validate inputs
    @assert n_actuators > 0 "Number of actuators must be positive"
    @assert nlevels > 0 "Number of levels must be positive"
    @assert -1.0 <= bias <= 1.0 "Bias voltage must be in range [-1, 1]"
    @assert all(1 <= act <= n_actuators for act in actuators) "All actuator indices must be in range [1, $n_actuators]"

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

            ## Add reference pattern between test patterns if trace_PTT is enabled
            if trace_PTT &&
                !(actuator == actuators[end] && level_idx == length(test_levels))
                ref_name = "ref_after_act$(actuator)_lev$(level_idx)"
                push!(voltage_names, ref_name)
                push!(voltage_patterns, copy(reference_voltages))
            end
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

    ## Validate that arrays have the same length
    @assert length(voltage_names) == length(voltage_patterns) "Voltage names and patterns arrays must have the same length"

    return voltage_names, voltage_patterns
end
