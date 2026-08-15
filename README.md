# dotfiles

Cross-platform developer environment, orchestrated by [chezmoi](https://chezmoi.io).
Targets macOS (Apple Silicon), Windows, Debian (bare metal and WSL2), and Fedora.

| Layer | Tool |
| --- | --- |
| Dotfiles and bootstrapping | chezmoi |
| Secrets | 1Password CLI (`op`) and the 1Password SSH agent |
| System packages | Homebrew, winget, apt, dnf |
| Developer toolchains | mise |

## Bootstrap a new machine

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jonnyasmith
```

## Day to day

```sh
chezmoi edit ~/.zshrc   # edit the source, not the target
chezmoi apply           # write changes to $HOME
chezmoi update          # git pull, then apply
chezmoi cd              # open a shell in the source directory
```

## Layout

`.chezmoiroot` points chezmoi at `home/`, so everything outside it — this README,
`docs/`, CI — is invisible to `chezmoi apply`.

```
.chezmoiroot              -> "home"
docs/                     runbooks and per-machine file examples
home/                     the chezmoi source directory
  .chezmoi.toml.tmpl      machine detection, rendered at `chezmoi init`
  .chezmoiignore          targets chezmoi must not manage
  .chezmoidata/           declarative lists the scripts render in
  .chezmoiscripts/        scripts that run but are never written to $HOME
  dot_zshenv              -> ~/.zshenv
  dot_config/…            -> ~/.config/…
```

## Packages

`home/.chezmoidata/packages.toml` holds every system package for every
platform. The scripts in `.chezmoiscripts/` render the relevant list into
themselves, so chezmoi's content hash — and therefore the decision to re-run —
tracks the list exactly. Add a package there, run `chezmoi apply`, and only the
one platform's install script re-runs.

Each script wraps its whole body in a `family` guard. A script that renders
empty is one chezmoi skips, so a Fedora box never even sees the apt logic.

| Script | Runs on |
| --- | --- |
| `05-repos-debian` / `05-repos-fedora` | third-party sources, before any install |
| `10-packages-<family>` | brew, apt, dnf, pacman, or winget |

Toolchains do not live here. Anything mise's registry can install belongs in
mise's config, so it is versioned and identical everywhere; a package earns a
place in `packages.toml` only when the registry cannot supply it, and says so
in a comment.

Under WSL the `desktop` lists and their repositories are skipped — each entry
duplicates an app on the Windows host.

## Toolchains

`~/.config/mise/config.toml` is an ordinary chezmoi-managed file. It declares
`[tools]`, `[settings]` and `[env]`, and nothing else — mise no longer
orchestrates anything, so the `[bootstrap.*]`, `[dotfiles]` and `[tasks.*]`
tables are gone. Three per-OS mise files collapse into one template.

The tool list is not branched by platform: a toolchain should be the same
everywhere. The two `os = [...]` filters that remain are mise's own, and they
are about which backends publish binaries, not about which machine this is.

`run_onchange_after_20-mise` installs mise, then runs `mise install`. It is an
`after` script because it reads the config file the same `chezmoi apply`
writes, and it carries a hash of that config in a comment — chezmoi keys
`run_onchange_` on the script, which would otherwise never change when a
toolchain is added.

`~/.config/mise/mise.lock` is deliberately unmanaged. It resolves the selectors
to exact versions per machine, and every `mise install` rewrites it. Two
machines upgraded on different days differ by a patch; that is not drift.

## Machine facts

`.chezmoi.toml.tmpl` resolves the machine once at `chezmoi init` and writes the
results to `~/.config/chezmoi/chezmoi.toml`. Templates branch on these rather
than re-deriving them:

| Variable | Values |
| --- | --- |
| `.family` | `darwin`, `debian`, `fedora`, `arch`, `windows`, `linux` |
| `.isWSL` | `true` on a Microsoft-kernel Linux |

These are **not** refreshed by `chezmoi apply`. Re-run `chezmoi init` after a
distro upgrade or a move between bare metal and WSL.

## Per-machine files

Untracked, and created by hand — they hold a work org and email:

- `~/.config/git/config.local` — from `docs/git-config.local.example`
- `~/.config/git/config.work` — the work identity alone

Git silently ignores an include that does not exist, so a machine without them
still gets a working personal config.

## Status

Built so far:

- [x] chezmoi skeleton and entrypoint
- [x] machine detection
- [x] shell and terminal core — zsh, starship, git, kitty
- [x] packages
- [x] mise toolchains
- [ ] secrets via 1Password
- [ ] externals — oh-my-zsh, tpm, `~/dev` checkouts
- [ ] remaining app configs — nvim, tmux, gh, btop, htop, claude, codex, omp
- [ ] OS and desktop settings — macOS defaults, GNOME dconf, COSMIC
- [ ] Debian, WSL, Fedora, Windows
- [ ] verification and CI
- [ ] per-OS runbooks

Applied end to end on macOS, and in containers on Debian 13 and Fedora 41 —
where the repo scripts were run for real, twice, and every package name checked
against the repositories they add. The WSL branch is verified by forcing
`isWSL`, since no container reports a Microsoft kernel. The Arch and Windows
branches render correctly but have not been run.
