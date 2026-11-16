# Ladislas Walewski’s website

A [personal site](https://lads-oxygen.github.io/) built with Franklin.jl, with posts on machine learning and mathematics, Julia research code and LaTeX resources.

## Local preview

Run this from the repository root.

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); using Franklin; serve()'
```

Open [localhost:8000](http://localhost:8000/). Franklin writes the generated site to `__site/`.
