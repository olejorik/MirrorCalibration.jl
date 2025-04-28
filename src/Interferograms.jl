

coligram = :linear_blue_95_50_c20_n256
coligramdiff = :diverging_gwr_55_95_c38_n256
phasemap = :cyclic_mygbm_30_95_c78_n256

function inspect_interferograms(
    folder,
    Nvolt,
    Nact,
    refpos,
    zeropos;
    width=300,
    height=300,
    colormap=coligram,
    title="",
    titlesize=20,
    hidedecorations=false,
    rot=2,
    kwargs...,
)
    GLMakie.activate!()
    f = jldopen(joinpath(folder, "data.h5"))
    voltagenames = keys(f["voltages"])
    sort!(voltagenames; by=(x -> parse(Int, x)))

    getvname(n, v; Nvolt=Nvolt) = voltagenames[(1 + (n - 1) * Nvolt + v)]

    fdirs = keys(f["images"])
    pathiterator = ["$(dir)/$s" for dir in fdirs for s in keys(f["images"][dir])]

    ## Preallocate multidimensional array based on the size of the first interferogram
    first_vname = getvname(1, 1)
    first_igram = f["images"][pathiterator[1]][first_vname]
    igrams = Observable(
        Array{eltype(first_igram)}(undef, size(first_igram)..., length(pathiterator))
    )

    ## Observables for actuator and voltage
    actuatorN = Observable(1)
    voltage = Observable(1)

    ## Update function to modify the interferograms based on slider values
    function update_interferograms()
        vname = getvname(actuatorN[], voltage[])
        for (i, p) in enumerate(pathiterator)
            igrams[][:, :, i] = f["images"][p][vname]
        end
        return notify(igrams)
    end

    ## Initial plot
    update_interferograms()
    ## Observable for the current slice index
    current_slice = lift(getvname, actuatorN[], voltage[])

    ## Create heatmaps for each slice in the table layout
    num_slices = size(igrams[], 3)
    num_rows = ceil(Int, sqrt(num_slices))
    num_cols = ceil(Int, num_slices / num_rows)

    fig = Figure(; size=(width * num_cols, height * num_rows))
    grid = GridLayout(fig[1, 1]; title="Interferograms")


    for i in 1:num_slices
        nr, nc = divrem(i - 1, num_cols)
        ax = Axis(
            grid[nr, nc];
            ## width=width,
            ## height=height,
            aspect=DataAspect(),
            title=pathiterator[i],
        )
        if hidedecorations
            hidedecorations!(ax)
        end
        hm = heatmap!(
            ax,
            lift(igrams) do data
                rotr90(data[:, :, i], rot)
                ## data[:, :, i]
            end;
            colormap=colormap,
            kwargs...,
        )
    end


    ## sliders for actuator and voltage
    slider_layout = fig[2, 1] = GridLayout()

    Label(slider_layout[1, 1]; text="Actuator")
    actuator_slider = Slider(slider_layout[1, 2]; range=1:Nact, startvalue=1)

    Label(slider_layout[2, 1]; text="Voltage")
    voltage_slider = Slider(slider_layout[2, 2]; range=1:Nvolt, startvalue=1)

    ## Connect sliders to observables
    on(actuator_slider.value) do val
        actuatorN[] = val
        update_interferograms()
    end

    on(voltage_slider.value) do val
        voltage[] = val
        update_interferograms()
    end


    ## Add colorbar below the heatmap table
    colorbar = Colorbar(fig[1, 2]; colormap=colormap, label="Intensity")

    ## Automatically update the colorbar limits to match the colorrange of all displayed slices
    lift(igrams) do data
        colorbar.limits[] = extrema(data)
    end

    if title != ""
        Label(fig[0, :], title; fontsize=titlesize)
    end

    resize_to_layout!(fig)
    screen = display(fig)

    ## Wait for user to press 'q' or close the window
    on(events(fig).keyboardbutton) do event
        if event.action == Keyboard.press &&
            (event.key == Keyboard.q || event.key == Keyboard.escape)
            println("q/esc is pressed, exiting.")
            close(screen)
        end
    end

    wait(screen)
    #TODO return to the original environment # CairoMakie.activate!(; type="png")
    return nothing
end


function process_interferograms(
    folder, Nvolt, Nact, refpos, zeropos; normals=nothing, dn=[0, 1], rn=[1, 0], Nbias=1
)
    ## debug block
    ## folder = datadir("exp_raw/interferogram/PDM30-37/2025-04-04/2") # This folder contains igrams for changing values of the actuator voltage
    ## refpos = 7 # the zero tilt igram
    ## zeropos = 7 # interferogram we use as zero tilt
    ## dn = [0, 1]
    ## rn = [1, 0]
    ## normals = nothing



    f = jldopen(joinpath(folder, "data.h5"))
    JLD2.printtoc(f; numlines=15)
    allvoltages = f["voltages"]
    voltagenames = keys(allvoltages)
    sort!(voltagenames; by=(x -> parse(Int, x)))

    getvname(n, v; Nvolt=Nvolt) = voltagenames[(Nbias + (n - 1) * Nvolt + v)]


    (Nbias + Nvolt * (Nact) == length(voltagenames)) || error("Wrong number of voltages")


    ## iteration by the tilts
    letter_to_normal = Dict("d" => dn, "r" => rn, "l" => -rn, "u" => -dn, "o" => [0, 0])
    fdirs = keys(f["images"])
    pathiterator = ["$(dir)/$s" for dir in fdirs for s in keys(f["images"][dir])]

    ## load one interferogram
    vname = getvname(1, 1; Nvolt=Nvolt)

    testigram = f["images"]["o/1"][vname]

    ## construct normals
    if isnothing(normals)
        normals = [letter_to_normal[dir] for dir in fdirs for s in keys(f["images"][dir])]
        popat!(normals, refpos) == [0, 0] || error("refpos is not zero")
    end

    ##  aperture construction
    elfile = joinpath(folder, "aperture.jld2")
    apfile = joinpath(folder, "ap.tif")

    el = draw_or_load_ellipse(elfile, testigram, apfile; saveap=true)
    #=  el = try
         el = load(elfile, "el")
         @info "Aperture loaded"
         el
     catch
         @info "Aperture not found, please draw it"
         GLMakie.activate!()
         el, ap = draw_ellipse(testigram)
         save(apfile, Gray{N0f8}.(ap))
         jldsave(elfile; el)
         CairoMakie.activate!(; type="png")
         el
     end =#

    ellipse = Ellipse(el)

    xc, yc = center(ellipse)
    EllipseGeometry.center!(ellipse, (size(testigram, 1) + 1 - yc, xc))
    angle!(ellipse, angle(ellipse) + π / 2)


    fig, ax, hm = heatmap(testigram; axis=(aspect=DataAspect(),), colormap=coligram)
    ax.aspect = DataAspect()
    lines!(ellipse; color=:red)
    fig |> display

    ap = mask_ellipse(testigram, ellipse)
    mask = ap2mask(ap)


    function get_phase(
        actuatorN,
        voltage;
        ap=ap,
        refpos=refpos,
        normals=normals,
        zeropos=zeropos,
        pathiterator=pathiterator,
    )

        @info "Reading igrams for actuator $actuatorN, voltage $voltage"
        vname = getvname(actuatorN, voltage)
        igrams = [f["images"][p][vname] for p in pathiterator]
        igramsF = [Float64.(i) for i in igrams]



        idiffs = diffirst(igramsF, refpos)

        tiltsalg = FineTilts(; normals=normals)
        tilts, taus, sigmas = tiltsalg(idiffs)
        insert!(tilts, refpos, zero(tilts[1]))
        phasealg = LSPSI()
        phase_hat = phasealg(igramsF, tilts)


        phase = phwrap(phase_hat .+ tilts[zeropos])

        phase_unwrapped = unwrap_LS(phase, ap)

        @info "Done with actuator =$actuatorN, voltage = $voltage"

        return phase_unwrapped

    end


    savefolder = replace(folder, "raw" => "pro")

    phase_file = "phases.h5"

    if !isfile(joinpath(savefolder, phase_file))

        mkpath(savefolder) # create the path
        save(joinpath(savefolder, phase_file))
        h5file = h5open(joinpath(savefolder, phase_file), "w")
        create_group(h5file, "phases")
        create_group(h5file, "voltages")
        if Nbias > 0
            bias = get_phase(1, 0)
            bv = allvoltages[getvname(1, 0)]
            h5file["phases"]["bias"] = bias
            h5file["voltages"]["bias"] = bv
        end
        firstphase = get_phase(1, 1)
        firstvoltage = allvoltages[getvname(1, 1)]
        create_dataset(
            h5file["phases"],
            "actuators",
            eltype(firstphase),
            (Nvolt, Nact, size(firstphase)...),
        )
        create_dataset(
            h5file["voltages"],
            "actuators",
            eltype(firstvoltage),
            (Nvolt, Nact, size(firstvoltage)...),
        )

        for i in 1:Nvolt
            for actuatorN in 1:Nact
                h5file["phases"]["actuators"][i, actuatorN, :, :] = get_phase(actuatorN, i)
                h5file["voltages"]["actuators"][i, actuatorN, :] = allvoltages[getvname(
                    actuatorN, i
                )]
            end
        end
        h5file["ap"] = ap
        h5file["ellipse_conic"] = collect(ellipse._conic)
        close(h5file)

    end

    return phasefile = h5open(joinpath(savefolder, phase_file), "r")
end
