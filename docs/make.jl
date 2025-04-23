using MirrorCalibration
using Documenter

DocMeta.setdocmeta!(MirrorCalibration, :DocTestSetup, :(using MirrorCalibration); recursive=true)

makedocs(;
    modules=[MirrorCalibration],
    authors="Oleg Soloviev",
    sitename="MirrorCalibration.jl",
    format=Documenter.HTML(;
        canonical="https://olejorik.github.io/MirrorCalibration.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/olejorik/MirrorCalibration.jl",
    devbranch="main",
)
