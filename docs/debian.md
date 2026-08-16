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

```shell
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jonnyasmith
```

That clones over **HTTPS**, which is not a fallback but the only thing that can
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
first error. Re-running is safe and is usually the whole fix: every step is
guarded, so an apply picks up where the last one stopped.

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
