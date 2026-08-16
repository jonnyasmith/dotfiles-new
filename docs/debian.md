# Debian Desktop

Everything here needs a human: install media, a GUI sign-in, a sudo password, or
a re-login. Packages, repos, git checkouts, dotfiles and GNOME settings are
`chezmoi apply`'s job — do not do them by hand.

## 1. Install Debian

1. Write the Debian ISO to a USB stick and boot it.
2. At the partitioning step enable **full-disk encryption** — it cannot be added
   later without a reinstall.
3. **Leave the root password blank.** That is what makes the installer put your
   user in `sudo`; set one and nothing below can elevate.
4. Create the `jonny` user, finish, reboot.

Already installed with a root password? Fix it once, then log out and back in —
group membership is only read at login:

```shell
su -c '/usr/sbin/usermod -aG sudo jonny'
```

## 2. First boot

```shell
sudo apt update && sudo apt upgrade -y && sudo apt install -y curl git
```

Reboot if that pulled a new kernel. A minimal Debian has neither `curl` nor
`git`, and the line below needs both — `curl` to fetch chezmoi, `git` for the
clone it then does.

## 3. Bootstrap

Install the binary first, on its own:

```shell
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi --version
```

Two things there are deliberate. `-b` overrides the installer's default of
`./bin`, which is a *relative* path — it lands wherever you happened to be
standing, and on a machine that has never had a `~/bin` it is on no `PATH` at
all, so every `chezmoi` line in this runbook answers `command not found`.
`~/.local/bin` is the directory `.zshenv` puts on `PATH` permanently; the
`export` is only to reach it from this bash session, before zsh exists.

Then the run itself:

```shell
chezmoi init --apply --verbose jonnyasmith/dotfiles-new
```

Not the installer's `-- init --apply` form. That works by `exec`ing chezmoi from
inside the install script, which means a failure to launch it looks identical to
a successful silent run — the installer's own `installed bin/chezmoi` is the last
thing either prints. Run as its own command, `chezmoi init` is visible, has an
exit code you can read, and can be re-run without re-downloading anything.

The repository is named in full for a reason. `chezmoi init <name>` is not a
lookup of any kind — it is a string substitution into
`https://github.com/<name>/dotfiles.git`. So a bare `chezmoi init jonnyasmith`
asks for `jonnyasmith/dotfiles`: the *old* repo, which has no `.chezmoiroot` and
no `.chezmoiscripts`. It clones and applies without complaining, installs
nothing, and leaves a machine with no zsh and an apply that appeared to do
nothing at all. `jonnyasmith/dotfiles-new` is the `<owner>/<repo>` form, and it
is the whole difference between this runbook working and silently doing nothing.

`init` is also not how you change your mind. Once `~/.local/share/chezmoi`
exists, it is the source directory; a later `init` naming a different repository
pulls what is already there. Repointing it means deleting it first:

```shell
rm -rf ~/.local/share/chezmoi ~/.config/chezmoi
chezmoi init --apply --verbose jonnyasmith/dotfiles-new
```

`~/.config/chezmoi` goes too: it holds the answers to the work-machine prompt,
and `promptBoolOnce` reuses them rather than asking again.

`--verbose` is what makes the apply narrate. Without it chezmoi prints only the
scripts' own output, so a run with nothing left to do prints nothing at all and
reads as a hang or a no-op.

It clones over **HTTPS**, which is not a fallback but the only thing that can
work: SSH to GitHub needs the `IdentityAgent` line pointing ssh at 1Password's
socket, and that line is in this repo. Switching the remote to SSH is not a step
either — `31-dev-remotes` does it on the next apply, once 1Password is signed in
(step 4).

The run asks one question, whether this is a work machine, and then adds the
1Password, Docker, VS Code and Chrome apt repos, enables `contrib` and
`non-free` (the Microsoft fonts and `unrar` live there), installs every package
in `packages.debian`, the mise `[tools]`, the dotfiles and the GNOME dconf, sets
zsh as the login shell, and puts you in the `docker` group.

Wait for it to finish. The last lines it prints include

```
  + login shell: /usr/bin/zsh (takes effect at the next login)
```

and only then is there a zsh to start:

```shell
exec zsh
```

If the apply stopped early instead, zsh is not installed yet and `exec zsh`
answers `not found` — that is the symptom, not the fault. Scroll back to the
first error. Re-running `chezmoi apply --verbose` is safe and is usually the
whole fix: every step is guarded, so an apply picks up where the last one
stopped.

`packages.debian` is three lists, and only the first is all-or-nothing:

| List | On failure |
| --- | --- |
| `core` | fatal — these are Debian's own packages, and one that will not resolve means a broken machine |
| `docker` | skipped with a `!` line if the Docker apt source is missing; `36-linux-services` then skips too |
| `desktop` | 1Password, Chrome, VS Code, VLC — installed one at a time, each survivable |

`core` carries zsh, which is why the other two are kept out of it. The `desktop`
list is also the one WSL skips wholesale (see [wsl.md](wsl.md)).

`chezmoi apply --dry-run -v` shows what a run would do; `chezmoi status` shows
what is out of sync. It is idempotent — re-run it any time.

## 4. 1Password — sign-in, SSH agent, and your keys

1. Launch **1Password** and sign in. If the browser hand-off does not fire,
   choose **Set up another device** on 1password.com → **Add your account
   directly**.
2. Settings → **Developer** → enable **Use the SSH agent**.
3. Settings → **Browser** → enable **Connect with 1Password in the browser**,
   then install the browser extension and approve the pairing dialog.

There is no key to generate. The private keys stay in 1Password; the agent
serves them, `~/.ssh/config` (from this repo) points `IdentityAgent` at
`~/.1password/agent.sock`, and the public-key stubs each `Match` block pins are
committed under `home/private_dot_ssh/private_1password/`. Check all three
accounts:

```shell
ssh -T git@github.com        # personal
ssh -T git@github-work       # work alias, rewritten by ~/.config/git/config.local
ssh -T git@ssh.dev.azure.com # azure
```

`Permission denied` with the agent running usually means the key set changed:
`~/.ssh/1password/refresh` rewrites the stubs from whatever the agent now
returns, and the result is a git diff to commit.

Then run `chezmoi apply` again. With the agent answering, `31-dev-remotes`
switches the source directory and both `~/dev` checkouts from HTTPS to SSH;
until then it says so and changes nothing.

## 5. GNOME extensions

```shell
sudo apt install -y gnome-shell-extension-appindicator gnome-browser-connector
```

Then browse <https://extensions.gnome.org> and enable what you want. **Log out
and back in** — GNOME Shell on Wayland will not load a newly installed extension
into a running session.

`gnome-tweaks` is installed by `40-desktop-dconf`, and the settings it exposes
are already written from `.chezmoitemplates/desktop/gnome.dconf`.

## 6. Terminal

The terminal is kitty, from Debian's own repositories, same as on every other
platform in this repo. It is deliberately not ghostty: ghostty pins an exact Zig
version and Zig breaks compatibility most releases, so Debian will not package
it and the only Linux builds are distro or community ones. Trixie's kitty lags
upstream by a few minor versions — that is the trade for having the distro own
the updates.

## 7. Things that need a logout or reboot

| Change | Why |
| --- | --- |
| GNOME extensions | Shell loads them only at session start |
| `docker` group | Group membership is read at login |
| Login shell → zsh | `chsh` is read by PAM at login |
| Kernel upgrade | Reboot |

## 8. tmux plugins

Once, inside tmux: `prefix + I`. chezmoi clones tpm as an external but cannot
press the key for you.

## 9. Portainer

`39-portainer` writes `/opt/portainer/docker-compose.yml` — sudo, because it is
outside `$HOME` — and runs `docker compose up -d`. Its gate is `docker info`,
which also answers the group question: until the re-login in section 7 has
happened this account cannot read the socket, so the script prints a `.` line
and defers, and the container arrives on the first apply after that.

Portainer's first-run admin account is created at <http://localhost:9000> and
the window times out if you leave it; `docker restart portainer` reopens it.
