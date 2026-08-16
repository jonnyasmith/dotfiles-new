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
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init --apply --verbose jonnyasmith/dotfiles-new
```

Installing and initialising are two commands on purpose: the installer's
`-- init --apply` form `exec`s chezmoi from inside itself, where a failure to
launch is indistinguishable from a silent success, and its default `-b ./bin` is
a relative path that ends up on no `PATH`.

That covers every POSIX platform. On Windows, from an unelevated pwsh:

```powershell
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -- init --apply jonnyasmith/dotfiles-new"
```

Everything a machine needs that an apply *cannot* do — install media, GUI
sign-ins, licences, permissions, anything gated on a reboot — is in the runbook
for that platform:

[macOS](docs/macos.md) · [Windows](docs/windows.md) · [WSL](docs/wsl.md) ·
[Debian](docs/debian.md) · [Fedora](docs/fedora.md) · [Arch](docs/arch.md) ·
[Raspberry Pi](docs/raspberry-pi.md)

## Day to day

```sh
chezmoi edit ~/.zshrc   # edit the source, not the target
chezmoi apply           # write changes to $HOME
chezmoi update          # git pull, then apply
chezmoi cd              # open a shell in the source directory
```

## Layout

`.chezmoiroot` points chezmoi at `home/`, so everything outside it — this README,
`docs/`, `checks/` — is invisible to `chezmoi apply`.

```
.chezmoiroot              -> "home"
mise.toml                 tooling for working on this repo, not on a machine
checks/                   the check suite `mise run check` drives
docs/                     one runbook per platform, for what an apply cannot do
home/                     the chezmoi source directory
  .chezmoi.toml.tmpl      machine detection, rendered at `chezmoi init`
  .chezmoiignore          targets chezmoi must not manage
  .chezmoidata/           declarative lists the scripts render in
  .chezmoiexternal.toml   third-party trees chezmoi clones and refreshes
  .chezmoiscripts/        scripts that run but are never written to $HOME
  .chezmoitemplates/      payloads scripts inline, also never written to $HOME
  dot_zshenv              -> ~/.zshenv
  dot_config/…            -> ~/.config/…
  Documents/…             -> ~/Documents/… (Windows)
  AppData/…               -> ~/AppData/… (Windows)
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

`core` is one batch and fails the apply; `desktop`, and Debian's `docker`, are
installed separately and survivably. That split is not cosmetic — `core` is what
installs zsh, so anything in it that comes from a repository an earlier script
is allowed to skip would cost the machine its login shell.

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

Neovim is one of those tools, which makes the editor a place where mise and the
distro can both claim the same binary. `.zshenv` exports `EDITOR` and `VISUAL`
(the PowerShell profile sets the same pair), and `~/.local/bin` carries a `vi`
wrapper with `vim` and `editor` symlinked to it, so the fallbacks resolve to the
same nvim as the `$EDITOR` path does. All four spellings run `nvim` unqualified
and let `PATH` pick, because mise moves the install directory on every upgrade.
No package list may install neovim: apt's shipped three minor versions behind
what `dot_config/nvim` requires, and while it was installed it owned the `vi`
and `vim` alternatives.

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

## App configs, and the state beside them

Every remaining app config is a plain file: nvim, tmux, btop, htop, gh, herdr,
karabiner, claude, codex, and omp. None needs a template — their contents are
the same on every platform.

The awkward part is that most of these tools keep state in the same directory
as their config. `~/.claude` holds sessions and transcripts, `~/.omp/agent`
holds `agent.db` (a credential store), nvim writes `spell/` and `.netrwhist`
beside `init.lua`, karabiner drops `automatic_backups/`, herdr opens a socket
and a log. chezmoi manages only what is in its source directory and ignores
everything else in the target, so all of that is simply invisible — the long
denylist the previous setup needed to keep `agent.db` out of git is gone.

Where a tool chose `0600` for its own file or `0700` for its own directory,
the source name carries `private_` so an apply does not widen it.

Only `~/.config/karabiner` is gated, to macOS. tmux, btop and htop are skipped
on Windows.

### Configs a tool rewrites

btop, htop, gh, karabiner, codex, claude and omp all rewrite their own config —
from a TUI, or on exit. The previous setup symlinked some of these so those
edits landed back in the repo. chezmoi writes real files, so they do not: a
change made in the app is drift, and the next `chezmoi apply` reverts it.

The workflow is one command with no arguments:

```sh
chezmoi re-add       # pull every changed managed file back into the source
chezmoi diff         # ...then read what the app actually changed
```

`re-add` skips templates, so it cannot flatten `~/.ssh/config` or the git
identity files back into literal text.

`lazy-lock.json` is managed deliberately, unlike `mise.lock`. It is a shared
pin — the point is that every machine gets the same plugin revisions — so
`:Lazy sync` is followed by `chezmoi re-add`. `~/.config/gh/hosts.yml` holds
the OAuth token and stays unmanaged.

## OS and desktop settings

Three of these have no file to manage. macOS keeps preferences in a binary
plist that `cfprefsd` owns and rewrites; GTK and GNOME keep theirs in a dconf
database behind a daemon; the login shell lives in the account database. So
these are scripts, not managed files.

| Script | Does |
| --- | --- |
| `35-login-shell` | `chsh` to zsh — `/bin/zsh` on macOS, `/usr/bin/zsh` elsewhere |
| `40-macos-defaults` | Finder, Dock, trackpad and extension-visibility `defaults` |
| `40-desktop-dconf` | `dconf load` of the GTK payload, then the GNOME one |
| `21-dotnet-tools` | `ilspycmd`, a global .NET tool no toolchain manager owns |

The two dconf payloads live in `home/.chezmoitemplates/desktop/`, and
`40-desktop-dconf` inlines them into itself with `includeTemplate`. That puts
them inside the text `run_onchange_` hashes, so editing a payload is what
re-runs the script — the same trick `20-mise` uses for the mise config.
`.chezmoitemplates` is never written to `$HOME`, so the payloads stay out of
the target entirely.

`dconf load` reports success with nothing to write to when no session bus is
reachable, which is the normal case over SSH. The script names the bus itself
when it can find the socket, and checks the exit status rather than assuming
it, so a run that changed nothing says so.

`35-login-shell` carries neither `once_` nor `onchange_`, for the same reason
as `31-dev-remotes`: it can legitimately fail on the run that installs zsh, or
need a password nobody is there to type, so it has to keep trying. Once it has
succeeded the first comparison exits.

### COSMIC

COSMIC is the exception — its settings are one file per key under
`~/.config/cosmic`, so chezmoi manages them directly and no script is involved.
`cosmic-config` rewrites them from the GUI, which makes them the same
`chezmoi re-add` story as btop and gh.

The gate is a live probe rather than a machine fact:

```
{{ if not (lookPath "cosmic-comp") }}
.config/cosmic
{{ end }}
```

`.chezmoiignore` is re-rendered on every apply, so installing COSMIC later is
enough to bring the directory under management — unlike `.family`, no
`chezmoi init` is needed.

### Linux services and WSL

`36-linux-services` does the two things installing the docker package does not:
adds this account to the `docker` group, and enables `docker.service`. It
probes for `/run/systemd/system` rather than for `systemctl`, because WSL has
the binary either way and systemd only if `/etc/wsl.conf` turns it on.

`37-wsl` renders only where `chezmoi init` saw a Microsoft kernel. It creates
`~/.1password` — the directory `SSH_AUTH_SOCK` names, left empty unless the
optional npiperelay/socat relay is set up by hand — and reports when
`/etc/wsl.conf` has no docker boot stanza. It reports rather than writes: that
file is outside `$HOME`, may already carry `[automount]` or `[user]` stanzas,
and is read by the Windows side at boot.

Everything else WSL needs is conditional elsewhere: the desktop repos and apps
are skipped in `05-repos` and `10-packages`, `BROWSER` and `SSH_AUTH_SOCK`
branch in the mise config, git reaches the Windows 1Password agent through
`ssh.exe` in `config.os`, and `.chezmoiignore` drops `~/.config/1Password`
because the host owns it.

## Windows

Two targets sit outside `~/.config`, because Windows put them there: the
PowerShell profile has a fixed name under `~/Documents/PowerShell`, and Windows
Terminal is a Store app whose settings live under its package identity.

```
home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1
home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json
```

The profile is pwsh 7+ only. Windows PowerShell 5.1 reads
`~\Documents\WindowsPowerShell\` and is deliberately unmanaged.

chezmoi writes to `%USERPROFILE%\Documents`. If OneDrive has taken over Known
Folders, `$PROFILE` points inside OneDrive instead and the managed file is read
by nothing — check `$PROFILE` on a new machine before wondering why the shell
looks bare.

Windows Terminal rewrites its own `settings.json` on every GUI change and
whenever it discovers a profile fragment, so it belongs with btop and gh above:
`chezmoi re-add` after changing something in the UI.

The profile sets `XDG_CONFIG_HOME` to `~\.config`. Windows has no XDG default,
so tools each invent a location — nvim would read `~\AppData\Local\nvim`, gh
`~\AppData\Roaming\GitHub CLI` — and neither is a path this repo writes. Both
check `XDG_CONFIG_HOME` first on every platform, so one line makes the
`~\.config` tree chezmoi applies the one that gets read.

What Windows does *not* get: kitty (no Windows build), tmux, btop and htop
(POSIX process viewers), karabiner (macOS), and the zsh files. On a dual-boot or
WSL machine the guest has its own `$HOME` and its own apply, so a copy of
`.zshrc` on the host would be read by nothing.

`22-psmodules` installs the three PowerShell Gallery modules the profile imports
if present — PSFzf, Terminal-Icons and `z`. They are not in `packages.toml`
because they come from the Gallery rather than winget. The profile imports each
conditionally, so a machine that skipped this still gets a working shell.

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

To init with no terminal — a container, or any scripted run — answer the prompt
on the command line. The flag is keyed on the *prompt text*, not the data key:

```sh
chezmoi init --apply --promptBool "Work machine (adds a second git identity)=false"
```

## Verification

```sh
mise run check          # everything, in one render
mise run check:shell    # or one check at a time
```

Almost every check reads *rendered* output rather than the templates. A `.tmpl`
is not shell, TOML or JSON until Tera has run, and the branch that breaks is
usually the one the machine you are sitting at would never take. So
`checks/render.sh` renders the whole source state seven times — macOS personal
and work, Debian, Debian-as-WSL, Fedora, Arch, Windows — and the rest read that.

| check      | what it would catch                                                     |
| ---------- | ----------------------------------------------------------------------- |
| `render`   | a template that fails to render on some other OS                        |
| `shell`    | a rendered script that does not parse, or that shellcheck rejects       |
| `pwsh`     | the same for PowerShell; skipped, loudly, where pwsh is absent          |
| `config`   | a rendered config that stopped being valid TOML or JSON, a `.chezmoiignore` rule that drops the wrong file, a script gated onto a machine that cannot run it |
| `packages` | a package the mise registry could supply, or one declared for two Linux families and not the third |
| `comments` | a comment paragraph over the budget — prose that outgrew the file       |
| `dconf`    | a dconf path or key no installed schema defines; skipped off a desktop  |

`mise.toml` at the repo root exists only for this. It manages nothing about the
machine, and is never linked into `~/.config/mise` — that config is a chezmoi
target like everything else.

Nothing runs this suite for you: it is a command you type, before a commit or
after a merge. And rendering a script only proves it parses — it says nothing
about whether the repositories it adds exist or the packages it names are in
them. That still takes a real `chezmoi init --apply` in a Debian or Fedora
container, run by hand when a package list or an apt source changes.

## Status

Built so far:

- [x] chezmoi skeleton and entrypoint
- [x] machine detection
- [x] shell and terminal core — zsh, starship, git, kitty
- [x] packages
- [x] mise toolchains
- [x] secrets — 1Password SSH agent, ssh config, work identity
- [x] externals — oh-my-zsh, tpm, `~/dev` checkouts
- [x] remaining app configs — nvim, tmux, gh, btop, htop, claude, codex, omp
- [x] OS and desktop settings — macOS defaults, GNOME dconf, COSMIC
- [x] Debian, WSL, Fedora, Windows
- [x] verification
- [x] per-OS runbooks

Applied end to end on macOS, and in a Debian 13 container — where the repo
scripts were run for real, twice, and every package name checked against the
repositories they add. The WSL branch is verified the same way, by forcing
`isWSL`, since no container reports a Microsoft kernel. Fedora 41 passes the
same way, twice. An earlier Fedora run died at the mise step on GitHub's
anonymous API rate limit — the same failure then reproduced on a Debian
container that had passed an hour before, which is what identified it as the
limit rather than the distro. A container run wants `GITHUB_TOKEN` exported for
that reason.

On Arch, `38-arch-services` has been run twice in a container: it enables
`fstrim.timer`, uncomments pacman's `Color`, and writes `vm.swappiness` once
rather than appending. Its TLP and `auto-cpufreq` branches are guarded on those
packages being installed and have not been exercised. Nothing else on Arch, and
nothing at all on Windows, has been run — both render and parse, and the
PowerShell parses under `pwsh`, which is as far as a Mac and a Linux container
can get.
