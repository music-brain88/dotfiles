# Copilot Instructions

Personal dotfiles repo for Arch Linux (native + WSL2), managed declaratively with **Nix Flake + Home Manager**, with **mise** as the task runner.

## Build / Check / Apply

All routine operations go through `mise` tasks defined in `.mise.toml` — prefer them over raw `nix` commands.

| Task | Command |
|------|---------|
| Build Home Manager config | `mise run nix:build` |
| Build + activate | `mise run nix:switch` |
| Flake check (eval only) | `mise run nix:check` |
| Format check | `nix develop --command nixpkgs-fmt --check flake.nix home.nix nix/` |
| Update flake inputs | `mise run nix:update` |
| GC old generations | `mise run nix:gc` |
| Dev shell | `nix develop` |
| Docker build / run / exec | `mise run docker:{build,run,exec,stop,remove}` |
| Install Neovim plugins | `nvim --headless +"call dein#install()" +qall` |

There is no traditional unit-test suite. CI (`.github/workflows/nix.yml`) runs three checks: `nix flake check --no-build`, a `nixpkgs-fmt --check` format verification on `flake.nix home.nix nix/`, and a Home Manager build inside an Arch Linux Docker container. To reproduce CI locally, run the format check command above, then `mise run nix:check` and `mise run nix:build` — note that `mise run nix:check` omits `--no-build`, so it may build derivations CI does not.

## Architecture — the big picture

**Hybrid approach: Nix manages packages, symlinks manage configs.**

- `flake.nix` — entry point, pins inputs (nixpkgs, home-manager).
- `home.nix` — top-level Home Manager config; imports modules from `nix/modules/`.
- `nix/modules/*.nix` — split by concern: `base`, `shell`, `git`, `tmux`, `neovim`, `rust-tools`, `dev-tools`, `fonts`.
- `.config/` — native config files (TOML, fish, conf) consumed directly by each tool. Nix creates symlinks into `~/.config/`; **the files themselves are not rewritten as Nix expressions**. When adding a new tool, follow this pattern: install the package in a `nix/modules/*.nix` module, drop the native config under `.config/<tool>/`, and add a symlink (e.g. via `home.file` / `xdg.configFile`) in the appropriate module.

### Neovim subsystem
Plugin manager is **dein.vim**, configured via TOML, not Lua tables:
- `init.lua` loads multiple TOML files under `.config/nvim/`.
- One TOML per concern: `dein.toml` (startup), `dein_lazy.toml` (lazy), `ddu_settings.toml`, `ddc_settings.toml`, `lsp_settings.toml`, `treesitter_settings.toml`, `copilot.toml`, `dashboard.toml`, `style.toml`.
- Status line components live in `.config/nvim/status_line/`, mini.nvim configs in `.config/nvim/mini/`.
- When adding a plugin, add it to the appropriate TOML — do not edit `init.lua`.

### CI/CD
Hybrid Docker + Nix pipeline (`.github/workflows/nix.yml`):
1. `build-image` — pushes Arch+Nix base image to GHCR with `type=gha` layer cache.
2. `check` — `nix flake check --no-build`, uses `magic-nix-cache`.
3. `verify-docker` — runs `nix build .#homeConfigurations.archie.activationPackage` inside the container, uses `cache-nix-action` (magic-nix-cache doesn't work inside Docker).

The Home Manager username is hard-coded as `archie`; the activation target is `.#homeConfigurations.archie.activationPackage`.

## Conventions

- **Indentation**: 2 spaces everywhere (Nix, Lua, TOML, shell, fish).
- **File names / variables**: `snake_case`.
- **Shell scripts**: bash scripts start with `set -euo pipefail`. Interactive scripts prefer fish.
- **Neovim plugin config**: TOML only (dein format), never inline in `init.lua`.
- **Comments**: bilingual EN/JA for non-obvious or user-facing components — match the existing style in surrounding files.
- **Commits**: descriptive messages; CI/release notes are generated via `release-drafter`.
- **Do not** convert existing native configs into Nix expressions — that violates the hybrid design (see `docs/explanation/architecture.md`).
- **Do not** commit `result/`, `.backup/`, or anything from `.env` (already gitignored).

## Where to look first

| Topic | File |
|-------|------|
| Design philosophy / hybrid rationale | `docs/explanation/architecture.md` |
| CI pipeline + caching strategy | `docs/reference/ci-cd-pipeline.md` |
| CI/CD evolution history | `docs/explanation/cicd-evolution.md` |
| Nix/Home Manager usage | `docs/tutorials/getting-started.md`, `docs/how-to/install-and-update-packages.md` |
| Shell boot flow (bash → fish) | `docs/explanation/shell-boot-flow.md` |
| Neovim plugins & keymaps | `docs/reference/neovim-config.md` |
| Directory layout details | `docs/reference/directory-structure.md` |
| Claude Code context (overlaps heavily with this file) | `CLAUDE.md` |
