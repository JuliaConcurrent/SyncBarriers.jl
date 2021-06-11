using Documenter
using Barriers

makedocs(
    sitename = "Barriers",
    format = Documenter.HTML(),
    modules = [Barriers]
)

deploydocs(
    repo = "github.com/tkf/Barriers.jl",
    push_preview = true,
)
