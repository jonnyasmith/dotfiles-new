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
home/                     the chezmoi source directory
  .chezmoi.toml.tmpl      machine detection, rendered at `chezmoi init`
  .chezmoiignore          targets chezmoi must not manage
  .chezmoidata/           declarative lists the scripts render in
  .chezmoiexternal.toml   third-party trees chezmoi clones and refreshes
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
| `.work`, `.workOrgs`, `.workEmail` | answers to the work-identity prompts |

These are **not** refreshed by `chezmoi apply`. Re-run `chezmoi init` after a
distro upgrade or a move between bare metal and WSL.

## Secrets

No private key and no token is stored in this repo, rendered by a template, or
written to disk by anything here.

**SSH keys** stay in 1Password and are served by its SSH agent.
`~/.config/1Password/ssh/agent.toml` lists which vault items the agent offers.
`~/.ssh/config` pins one key per host with `IdentitiesOnly`, naming a
**public-key stub** under `~/.ssh/1password/` — a `.pub` is all ssh needs to
say *which* agent key to use, and those are committed deliberately. Rotate a
key and `~/.ssh/1password/refresh` rewrites the stubs from whatever the agent
now holds, into the chezmoi source directory, for review as a normal diff.

The stubs used to be read out of the git working tree because the symlinks
planted in `~/.ssh/1password` kept vanishing, and ssh treats a missing
`IdentityFile` as fatal for the host — every remote broke at once. chezmoi
writes real files, so the stubs land in `~` from the first apply. It also owns
the mode: `private_` makes `~/.ssh` and `~/.ssh/1password` `0700`, where a git
checkout under Debian's `002` umask left them group-writable and ssh silently
ignored them.

**Tokens** are held by the tool that issued them — `gh` keeps its OAuth token
in `~/.config/gh/hosts.yml`, which is unmanaged. Nothing in this repo needs a
secret at apply time, so `onepasswordRead` is deliberately unused: `op` is a
package these very scripts install, so it does not exist on the run that would
need it, and a failed lookup aborts the whole apply. `op` is installed for
`op read` and `op run` by hand.

Under WSL there is no local agent at all: git is pointed at the Windows
`ssh.exe`, which reaches the host's 1Password over a named pipe.

## Checkouts

Two kinds of git repository land in `$HOME`, and they are handled differently
because one is read and the other is written.

**Vendor trees** — oh-my-zsh, its two plugins, and tpm — are externals in
`.chezmoiexternal.toml`. chezmoi clones them shallow, pulls them `--ff-only`
once a week, and nothing here ever edits them. The plugin clones sit inside
`~/.oh-my-zsh/custom/`, which oh-my-zsh's own `.gitignore` excludes, so its pull
never sees them. oh-my-zsh's installer is not used: its other two jobs are
`chsh` and writing a default `.zshrc` this repo would overwrite.

**Personal checkouts** under `~/dev` are cloned by a `run_once_` script instead.
An external would `git pull` over a dirty tree on a timer; these have commits in
them, so they are cloned once and then owned by hand.

They are cloned over HTTPS, because a fresh machine has no working key —
1Password is installed by the package script, but nobody has signed into it yet.
`31-dev-remotes` switches those origins to SSH, and it is the one script here
with neither `once_` nor `onchange_`: it has to keep retrying on later applies
until the agent answers. It costs nothing once done, because it reads the origin
URLs first and exits before touching the network.

What the checkouts wire into `$HOME` is declarative rather than scripted:

| Link | Target |
| --- | --- |
| `~/.agents/AGENTS.md`, `~/.claude/CLAUDE.md` | `~/dev/skills/AGENTS.md` |
| `~/.agents/skills`, `~/.claude/skills` | `~/dev/skills/skills` |
| `~/.local/bin/wt`, `~/.local/bin/worktree` | `~/dev/worktree-cli/dist/cli.js` |

These are `symlink_` entries, so `chezmoi diff` shows them and `chezmoi apply`
repairs them. They dangle harmlessly until the checkout exists. Only the
worktree-cli *build* needs a script, and it reports rather than fails: a broken
build must not take an apply down with it.

Windows gets none of this. It has no zsh and no tmux, the `~/dev` checkouts live
in the WSL guest, and creating a symlink there needs Developer Mode.

## Work identity

`chezmoi init` asks whether this is a work machine and, if so, for the work
GitHub org(s) and email. The answers go to `~/.config/chezmoi/chezmoi.toml`,
outside the repo, and render:

- `~/.config/git/config.local` — rewrites those orgs' remotes to the
  `github-work` ssh alias, which pins the work key
- `~/.config/git/config.work` — the work email, and nothing else

On a personal machine both templates render empty, chezmoi removes a target
that renders empty, and git ignores an include that is not there. To change an
answer later, edit `~/.config/chezmoi/chezmoi.toml` — the prompts only fire
when the key is absent.

## Status

Built so far:

- [x] chezmoi skeleton and entrypoint
- [x] machine detection
- [x] shell and terminal core — zsh, starship, git, kitty
- [x] packages
- [x] mise toolchains
- [x] secrets — 1Password SSH agent, ssh config, work identity
- [x] externals — oh-my-zsh, tpm, `~/dev` checkouts
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
