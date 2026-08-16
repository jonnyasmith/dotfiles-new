# WSL (Debian)

Everything in this file needs a human: a reboot, a GUI sign-in, a sudo password,
a Windows-side action, or a group membership that only takes effect after
re-login. Package installs, git clones and dotfiles are **not** here —
`chezmoi apply` owns those, including installing Docker and putting you in its
group.

The native-Windows side of the same machine is [windows.md](windows.md).

## 1. Install WSL (Windows side)

From an elevated PowerShell:

```powershell
wsl --install --distribution Debian
```

`wsl --list --online` shows the available distribution names.

This enables the Virtual Machine Platform and WSL features and **requires a
reboot** on a machine that has never had WSL enabled. Reference:
<https://learn.microsoft.com/en-us/windows/wsl/install>.

## 2. First run: create the UNIX user

The first launch of the distribution prompts for a UNIX username and password
interactively. There is no unattended path that also produces a sudo-capable
user, so do it by hand. The username does not have to match the Windows account;
nothing in this repo hardcodes it.

Then, once only:

```bash
sudo apt update && sudo apt install -y curl git
```

## 3. Bootstrap

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jonnyasmith
exec zsh
```

The clone is over HTTPS, so it needs no working SSH agent — which matters more
here than anywhere else, since the agent is on the Windows side (section 6).
`31-dev-remotes` switches the remotes to SSH on a later apply, once the agent
answers.

**How WSL is detected.** `chezmoi init` sets `isWSL` from the kernel release
string: WSL2 ships a Microsoft-built kernel, and that is the only signal a Linux
process can rely on. `$WSL_DISTRO_NAME` is environment, so it is absent from
anything not launched inside an interactive shell — a script run by chezmoi
included. `.chezmoi.os` is `linux` either way, so without the kernel probe
nothing could tell a WSL guest from bare metal.

That fact is resolved once, at init, and frozen. Moving a `$HOME` between bare
metal and WSL means re-running `chezmoi init`.

## 4. Docker

The repository and GPG key are added by `05-repos-debian`, the Docker CE
packages are `packages.debian.docker` — installed as their own batch, guarded on
that source existing — and `36-linux-services` adds you to the
`docker` group and enables the service where systemd is running. Two things
convergence deliberately will not do:

### /etc/wsl.conf

WSL has no systemd unless you turn it on, so there is no service to enable.
`37-wsl` **reports** the missing stanza rather than writing it: an apply should
not need sudo for a file outside `$HOME`, and appending blindly would have to
merge with any existing `[automount]`, `[network]` or `[user]` stanza. Add it
yourself:

```ini
[boot]
command="service docker start"
```

That is the SysV route and works on any WSL build. On builds that support
systemd you can instead set `systemd=true`, which lets `36-linux-services`
enable `docker.service` on the next apply. Pick one: with `systemd=true`,
`command=` still runs but `service docker start` is redundant. Either way the
change only takes effect after `wsl --terminate <distro>`.

### The group membership needs a re-login

`36-linux-services` prints this too. `usermod -aG docker` does not affect the
shell that ran it, and in WSL a plain `exec zsh` is not enough either — the login
session keeps the old supplementary groups. Terminate the distribution from
Windows and start it again:

```powershell
wsl --terminate Debian
```

Then verify without sudo:

```bash
docker run --rm hello-world
```

## 5. Portainer

Optional.

```bash
sudo mkdir /opt/portainer
sudo tee /opt/portainer/docker-compose.yml > /dev/null <<EOF
services:
  portainer:
    image: portainer/portainer-ce
    container_name: portainer
    restart: always
    ports:
      - "9000:9000"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/opt/portainer/data:/data"
EOF
cd /opt/portainer && sudo docker compose up -d && cd
```

Portainer's first-run admin account is created in the browser at
<http://localhost:9000> and times out if you wait too long after the container
starts; if you miss the window, `docker restart portainer`.

## 6. Reaching the Windows 1Password SSH agent from WSL

The 1Password app runs on the Windows side. Its SSH agent listens on the Windows
named pipe `\\.\pipe\openssh-ssh-agent`, which a Linux process inside WSL cannot
open directly. Enable it first: 1Password → Settings → Developer → **Use the SSH
agent**.

The Linux desktop app is **not** installed here. `1password` and `1password-cli`
are in `packages.debian.desktop`, and the whole `desktop` list is skipped when
`isWSL` — as is the 1Password apt repo in `05-repos-debian`. `~/.config/1Password`
is dropped by `.chezmoiignore` for the same reason: the host owns it.

There are two ways across the boundary. **The dotfiles do Option A**; Option B is
here because it is what you reach for the day something other than git inside WSL
needs a key.

### Option A — `core.sshCommand ssh.exe` (what the dotfiles render)

Nothing to run. `dot_config/git/config.os.tmpl` renders

```ini
[core]
    sshCommand = ssh.exe
```

into `~/.config/git/config.os` when `isWSL`, and the tracked
`~/.config/git/config` includes that file *below* its own
`core.sshCommand = ssh`, so the WSL value wins. The template is the only place
this can live: `git config --global` would write into a file this repo manages
and follow you to macOS.

Git shells out to the Windows OpenSSH client, which talks to the named pipe
natively. The bare name resolves through WSL's Windows-PATH interop; no
`/mnt/c/...` path is needed.

Verify — `ssh -T` would prove nothing, since git is not using that binary:

```bash
ssh.exe -T git@github.com
git -C "$(chezmoi source-path)" ls-remote origin >/dev/null && echo ok
```

The first use raises a Windows Hello prompt that must be authorised in the GUI.

Limitations, all of them real:

- Only git benefits. `ssh`, `scp`, `rsync -e ssh` and anything else inside WSL
  still have no agent.
- `ssh.exe` is a Windows binary, so every path it is handed is interpreted as a
  Windows path. `~/.ssh/config`, `IdentityFile`, `UserKnownHostsFile` and `-o`
  overrides written for the Linux side do not resolve.
- A Win32 process launch per git operation is noticeably slower than a native
  one.

### Option B — relay the pipe to a UNIX socket

Bridge the named pipe to a real UNIX socket with
[npiperelay](https://github.com/jstarks/npiperelay) plus `socat`, and point
`SSH_AUTH_SOCK` at it. Every SSH client in the distribution then works, and the
shell config ends up the same shape as macOS, differing only in the path.

`socat` is already in `packages.debian.core`, and `37-wsl` creates
`~/.1password` — empty, because nothing listens there until you do this. The
relay itself is not installed: it needs a Windows-side binary at a path this
repo cannot know.

Windows side, once (PowerShell, with [scoop](https://scoop.sh)):

```powershell
scoop install npiperelay
```

Note the resulting path; the examples below assume
`/mnt/c/Users/<you>/scoop/shims/npiperelay.exe`.

If the distribution runs systemd (`[boot] systemd=true`), a user unit is the tidy
option — `~/.config/systemd/user/1password-agent.service`:

```ini
[Unit]
Description=1Password SSH agent relay to the Windows named pipe

[Service]
ExecStart=/usr/bin/socat UNIX-LISTEN:%h/.1password/agent.sock,fork EXEC:"/mnt/c/Users/<you>/scoop/shims/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now 1password-agent
```

Without systemd, start it lazily from the shell instead — this is the snippet the
WSL branch of `dot_config/zsh/os.zsh.tmpl` would carry:

```bash
export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
if ! pgrep -u "$USER" -f 'npiperelay.exe .*openssh-ssh-agent' >/dev/null 2>&1; then
  rm -f "$SSH_AUTH_SOCK"
  setsid socat "UNIX-LISTEN:$SSH_AUTH_SOCK,fork" \
    EXEC:'/mnt/c/Users/<you>/scoop/shims/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent',nofork \
    >/dev/null 2>&1 &
fi
```

Verify with `ssh-add -l`; the first use raises a Windows Hello prompt.

**When Option A stops being enough**, switch to B: it is the only one that gives
`ssh`, `scp` and `rsync -e ssh` inside WSL a key, and afterwards WSL behaves like
every other machine in this repo — one `SSH_AUTH_SOCK`, same as macOS. Nothing
needs undoing first; delete the `sshCommand` stanza from the `isWSL` branch of
`config.os.tmpl` when you do.

## 7. Desktop apps the Windows host already provides

WSLg is enabled on current WSL builds, so these *would* run — the reason they are
excluded is duplication, not capability. Each would keep a second profile, a
second update channel and a second few hundred megabytes beside the copy you
already reach on the Windows side, three of them installed there from the winget
list:

| Not installed under WSL | Use instead |
| --- | --- |
| `google-chrome-stable` | the Windows Chrome (`Google.Chrome`) |
| `code` | the Windows VS Code (`Microsoft.VisualStudioCode`) over Remote-WSL, which drops its own `code` shim in the distro on first connect |
| `vlc`, `libavcodec-extra` | the Windows player |
| `1password`, `1password-cli` | the Windows app and its CLI — section 6. `op.exe` is reachable over interop |

`kitty` **is** installed: Windows Terminal is what you actually use here, but
kitty is cheap and its config is applied on every OS anyway.

All of them are `packages.debian.desktop`, and both that list and the matching
apt repos in `05-repos-debian` are gated on `isWSL`. One fact, checked in two
places, resolved once at init.

### `xdg-open` needs `$BROWSER` once Chrome is gone

Interop does **not** route URLs to Windows on its own — that needs `wslview`, and
`wslu` is not in Debian's repos. With no local browser, `xdg-open` finds no
`x-scheme-handler/http` handler and falls through to a list of text browsers that
are also absent, so nvim's markdown preview goes nowhere.

The `[env]` section of `dot_config/mise/config.toml.tmpl` therefore exports, in
its `isWSL` branch only:

```sh
BROWSER='/mnt/c/Windows/System32/rundll32.exe url.dll,FileProtocolHandler %s'
```

`xdg-open` checks `$BROWSER` before its built-in list and substitutes the `%s`
itself. The branch renders nothing off WSL, so a real Linux desktop keeps its own
handler lookup.

### Removing them from a box bootstrapped earlier

Nothing purges them for you:

```bash
sudo apt-get purge -y google-chrome-stable code vlc libavcodec-extra 1password 1password-cli
sudo apt-get autoremove --purge -y
sudo rm -f /etc/apt/sources.list.d/google-chrome.list /usr/share/keyrings/google-chrome.gpg
sudo rm -f /etc/apt/sources.list.d/vscode.sources
```

Verify the browser hand-off afterwards — it should raise a tab on Windows:

```bash
xdg-open https://example.com
```

## 8. Environment differences from macOS

- `PNPM_HOME` is `$HOME/.local/share/pnpm` on Linux, not macOS's
  `$HOME/Library/pnpm`. This is pnpm's own global-bin directory (`pnpm add -g`
  shims: `wt`, `pn`, `pnpx`), unrelated to the pnpm binary, which mise owns.
- `SSH_AUTH_SOCK` is `$HOME/.1password/agent.sock` (section 6), not the macOS
  group-container path — and under WSL nothing listens there unless you do
  Option B.
- `BROWSER` points at the Windows `rundll32` URL handler (section 7) and is
  absent on every other Linux.
- All three come from `[env]` in the mise config, not from a shell file, so a
  shell that never runs `mise activate` does not see them.

## 9. Do not reintroduce

| Dropped | Why |
| --- | --- |
| `curl \| bash` nvm installer, `NVM_DIR` sourcing | mise owns node |
| `curl -sS https://starship.rs/install.sh \| sh` | mise owns starship |
| Neovim tarball into `/opt/nvim`, Zig 0.12.0 into `/opt/zig` | pinned to dead versions; mise installs both |
| `stow .`, and the `.zshrc.orig` / `.gitconfig.orig` renames | chezmoi applies dotfiles and reports conflicts |
| `git checkout wsl` | one branch, one machine fact |
| `/home/jonny` in `PATH` and `PNPM_HOME` | hardcoded home directory |
