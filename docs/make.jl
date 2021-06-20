using Documenter
using SyncBarriers

makedocs(
    sitename = "SyncBarriers",
    format = Documenter.HTML(),
    modules = [SyncBarriers]
)

deploydocs(
    repo = "github.com/tkf/SyncBarriers.jl",
    push_preview = true,
)
