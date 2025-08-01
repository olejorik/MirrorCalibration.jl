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
    record_interferograms(voltage_dict, config::MirrorCalibrationConfig)

Record interferograms for a set of voltages using PythonCall interface to python_oko.

# Arguments
- `voltage_dict::Dict{String, Vector{Float64}}`: Dictionary with voltage pattern names as keys and voltage vectors as values
- `config::MirrorCalibrationConfig`: Configuration structure containing mirror and experiment parameters

# Returns
- `Bool`: true if experiment completed successfully, false otherwise

# Example
```julia
# Create voltage patterns
voltages = Dict(
    "bias" => zeros(37),
    "poke_1" => [1.0; zeros(36)]
)

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
success = record_interferograms(voltages, config)
```
"""
function record_interferograms(
    voltage_dict::Dict{String,Vector{Float64}}, config::MirrorCalibrationConfig
)
    ## Validate configuration
    validate_config(config)
    ## Log the start of the experiment
    @info "Recording interferograms using PythonCall interface..."
    @info "Voltage patterns: $(collect(keys(voltage_dict)))"
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

        ## Convert voltage dictionary to Python format (mimic generate_voltages output)
        voltage_names = collect(keys(voltage_dict))
        voltage_values = collect(values(voltage_dict))

        ## Ensure all voltage vectors have the correct length
        for (name, voltages) in voltage_dict
            if length(voltages) != config.n_actuators
                error(
                    "Voltage pattern '$name' has $(length(voltages)) elements, expected $(config.n_actuators)",
                )
            end
        end

        ## Create voltage arrays in the same format as Python generate_voltages function
        ## Convert each Julia vector to a numpy array, then create a list of arrays
        voltage_arrays = [np.array(v) for v in voltage_values]

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
    create_simple_voltage_patterns(n_actuators::Int; actuator_indices::Vector{Int}=[1])

Create simple voltage patterns for basic mirror testing.

# Arguments
- `n_actuators::Int`: Total number of actuators in the mirror
- `actuator_indices::Vector{Int}`: Indices of actuators to poke (default: [1])

# Returns
- `Dict{String, Vector{Float64}}`: Dictionary with voltage pattern names and voltage vectors

# Example
```julia
# Create patterns for a 37-actuator mirror, poking actuators 1 and 8
voltages = create_simple_voltage_patterns(37; actuator_indices=[1, 8])
```
"""
function create_simple_voltage_patterns(n_actuators::Int; actuator_indices::Vector{Int}=[1])
    voltage_dict = Dict{String,Vector{Float64}}()

    ## Bias pattern (all actuators at zero)
    voltage_dict["bias"] = zeros(Float64, n_actuators)

    ## Individual actuator poke patterns
    for idx in actuator_indices
        if idx < 1 || idx > n_actuators
            @warn "Actuator index $idx is out of range [1, $n_actuators], skipping"
            continue
        end

        pattern_name = "poke_$(idx)"
        voltages = zeros(Float64, n_actuators)
        voltages[idx] = 1.0
        voltage_dict[pattern_name] = voltages
    end

    @info "Created $(length(voltage_dict)) voltage patterns: $(collect(keys(voltage_dict)))"

    return voltage_dict
end
