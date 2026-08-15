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
  dot_zshenv              -> ~/.zshenv
  dot_config/…            -> ~/.config/…
```

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
- [ ] packages
- [ ] mise toolchains
- [ ] secrets via 1Password
- [ ] externals — oh-my-zsh, tpm, `~/dev` checkouts
- [ ] remaining app configs — nvim, tmux, gh, btop, htop, claude, codex, omp
- [ ] OS and desktop settings — macOS defaults, GNOME dconf, COSMIC
- [ ] Debian, WSL, Fedora, Windows
- [ ] verification and CI
- [ ] per-OS runbooks

Applied end to end on macOS, and in containers on Debian 13 and Fedora 41. The
WSL branch is verified by forcing `isWSL`, since no container reports a
Microsoft kernel. The Windows branch is written but unexercised.
