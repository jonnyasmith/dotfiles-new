# Windows (native)

Everything in this file needs a human: a reboot, a GUI sign-in, an elevated
prompt, or a control panel. Packages, dev tools and dotfiles are **not** here —
`chezmoi apply` owns those. The winget IDs are in `.chezmoidata/packages.toml`
under `packages.windows`; the toolchains are `[tools]` in
`dot_config/mise/config.toml.tmpl`.

This is the native-Windows runbook. The Linux side of the same machine is
[wsl.md](wsl.md).

## 1. Windows Update

Settings → Windows Update → **Check for updates**, and keep going until it
reports nothing outstanding. Reboot when asked. Doing this first means WSL,
winget and the Store are all at a version the rest of this file assumes.

## 2. Prerequisites

Two things cannot bootstrap themselves:

- **winget** — ships with Windows 11. If `winget --version` is not found,
  install **App Installer** from the Microsoft Store.
- **git** — chezmoi clones with it:

  ```powershell
  winget install --id Git.Git --exact
  ```

  `Git.Git` is also in the winget list, so a later run reports it as already
  installed.

## 3. Bootstrap

Run **without** elevation. Everything here is per-user, and an elevated shell
installs the winget packages for the wrong profile.

```powershell
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -- init --apply jonnyasmith"
```

If PowerShell refuses to run it, the execution policy is stricter than the
default `RemoteSigned`:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

`-Scope Process` lasts for that shell only, so nothing is loosened permanently.

The run asks whether this is a work machine, installs the winget list, installs
the mise `[tools]`, applies the dotfiles, and installs the three PowerShell
Gallery modules the profile imports. It is idempotent — re-run it any time, and
`chezmoi apply --dry-run -v` shows what it would do first.

**Symlinks.** Creating one on Windows needs Developer Mode or an elevated shell,
so the four symlink targets in this repo — `~/.agents`, `~/.claude/CLAUDE.md`,
`~/.claude/skills`, and the `wt`/`worktree` wrappers — are dropped by
`.chezmoiignore` on Windows. They point into `~/dev` checkouts that live in the
WSL guest, not on the host, so every one of them would dangle anyway.

**Editing.** Always `chezmoi edit <path>` and then `chezmoi apply`. chezmoi
writes ordinary files, so editing an applied file in place changes the copy in
`$HOME` and nothing in the repo.

## 4. 1Password and the SSH agent

Sign in to the 1Password desktop app, then Settings → Developer → **Use the SSH
agent**. Windows' own OpenSSH client talks to it over the
`\\.\pipe\openssh-ssh-agent` named pipe, so nothing else is needed for
`git@github.com` remotes — *provided* git uses that ssh and not the one Git for
Windows bundles, which cannot reach the pipe.

`dot_config/git/config.os.tmpl` pins it in the Windows branch, together with
`autocrlf = input`:

```ini
[core]
    sshCommand = C:/Windows/System32/OpenSSH/ssh.exe
```

Verify with `ssh -T git@github.com`.

## 5. PowerShell and XDG

The profile is `home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`,
applied to `~\Documents\PowerShell\` — i.e. **pwsh 7+**
(`Microsoft.PowerShell`, from the winget list). Windows PowerShell 5.1 reads
`~\Documents\WindowsPowerShell\` instead and is deliberately unmanaged.

Windows has no XDG default, so the profile sets one:

```powershell
$env:XDG_CONFIG_HOME = Join-Path $env:USERPROFILE '.config'
```

That single line is what makes the `~\.config` tree chezmoi applies the one that
gets read. Without it nvim would look in `~\AppData\Local\nvim` and gh in
`~\AppData\Roaming\GitHub CLI`, and the shared config in this repo would be
ignored on exactly one platform. Both check `XDG_CONFIG_HOME` first on every OS.

The three Gallery modules the profile imports — PSFzf (pinned to 2.5.16),
Terminal-Icons and `z` — are installed by `22-psmodules` at `CurrentUser` scope,
so nothing prompts for elevation. The profile imports each only if present, so
the shell still works if one fails to install. `PSFzf` also needs the `fzf`
binary, which mise installs.

**Aliases deliberately not ported** from `dot_config/zsh/aliases.zsh`: `auu` /
`nuu` (apt and nala — those belong in WSL), `buu` (Homebrew), `wtc` / `wtr` /
`wtl` (the `worktree` helper is in the WSL guest), and `flush`, `sniff`,
`httpdump`, `cleanup`, `fs`, `emptytrash`, `hidedesktop`, `showdesktop`, the
`GET`/`HEAD`/`POST` `lwp-request` loop and the `grep`/`df`/`du` coreutils
wrappers — macOS- or GNU-only, with no Windows equivalent worth faking.

## 6. Nerd font

Windows Terminal's settings ask for **JetBrainsMono Nerd Font Mono**, and
`DEVCOM.JetBrainsMonoNerdFont` in the winget list installs it. This is the one
place the font differs from macOS, which uses Fira Mono: winget has no manifest
for a Fira Mono Nerd Font under any publisher.

## 7. PowerToys keyboard remaps

PowerToys → **Keyboard Manager** → Remap a key. This is the day-to-day path and
it replaces SharpKeys for anything that only has to work inside a desktop
session.

SharpKeys is still in the package list because it does something Keyboard
Manager cannot: it writes the `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard
Layout` scancode map, which applies before login and with no process running.
Use it for a remap you want at the logon screen — it needs a reboot to take
effect. Use PowerToys for everything else.

## 8. Power plan and lid close

Win+R → **`powercfg.cpl`**:

- *Change plan settings* on the active plan — set the display and sleep timeouts
  for battery and mains.
- *Choose what closing the lid does* — set the lid action for battery and mains.

There is no per-user setting for these; they are machine-wide and the dialog
elevates itself.

## 9. WSL

From an **elevated** PowerShell:

```powershell
wsl --install --distribution Debian
```

This enables the Virtual Machine Platform and WSL features and needs a reboot on
a machine that has never had WSL. Everything after that — creating the UNIX
user, the Linux dotfiles, reaching the Windows 1Password agent from inside WSL —
is in [wsl.md](wsl.md).

The Windows Terminal settings in this repo already carry a `Debian` profile
(`source: Windows.Terminal.Wsl`), so the distribution shows up in the tab
dropdown once it is installed.

## 10. Do not reintroduce

| Dropped | Why |
| --- | --- |
| `packer.nvim` cloned into `nvim-data\site\pack\packer\start`, and `:PackerInstall` | `dot_config/nvim` is an AstroNvim/lazy.nvim config; packer is archived upstream |
| `Copy-Item fzf.exe C:\Windows\System32` | mise installs fzf on PATH; nothing needs a binary in a system directory |
| Chocolatey, and `choco install nerd-fonts-FiraMono` | the font is a winget package — section 6 |
| A `New-Item -ItemType SymbolicLink` install script | chezmoi applies dotfiles on every OS |
| `nvm install lts`, `CoreyButler.NVMforWindows` | mise owns node |
| `npm i prettier -g` | a per-project dev dependency, not a machine-global tool |
| `Microsoft.DotNet.SDK.6`, `.7`, `.8` | mise installs the SDKs side by side |
| `Neovim.Neovim`, `Starship.Starship`, `junegunn.fzf`, `zig.zig` | all in mise's registry, so they are `[tools]` and identical on every OS |
| `Docker.DockerDesktop` | deliberately absent; `RedHat.Podman-Desktop` stays |
| A `curl \| iex` font installer | section 6 does it from winget |
