# Raspberry Pi (Raspberry Pi OS / Debian)

Headless ARM box. Raspberry Pi OS declares `ID_LIKE=debian`, so `chezmoi init`
resolves `family = "debian"` and the Debian branch runs unchanged — repos,
packages, Docker, the login shell. There is no desktop, so `40-desktop-dconf`
finds no `dconf` and no-ops, and `.chezmoiignore` drops the COSMIC tree because
`cosmic-comp` is absent.

Everything below needs a human.

## 1. Image the SD card

1. Raspberry Pi Imager → choose the 64-bit Raspberry Pi OS image.
2. In the Imager's advanced options (gear icon), set the hostname, create the
   `jonny` user, and **enable SSH with public-key authentication** — pasting the
   public key here is the only thing that keeps the first boot headless.
3. Write the card, insert it, power on.

## 2. First boot

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git
```

Reboot if the upgrade replaced the kernel or firmware. `rpi-eeprom-update`
changes and any `raspi-config` change to boot order, overclock or GPU memory
also require a reboot.

## 3. Bootstrap

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init --apply --verbose jonnyasmith
exec zsh
```

`-b` keeps the binary out of the installer's default `./bin`, which is relative
and on no `PATH`, and `~/.local/bin` is what `.zshenv` exports. `chezmoi init` is
its own command rather than the installer's `-- init --apply`: run through the
installer it is `exec`ed out of sight, so a failure to launch looks the same as a
silent success. `--verbose` makes the apply narrate. See
[debian.md](debian.md#3-bootstrap).

Run it **without** `sudo`. The old runbook's `sudo bash ./install.sh` wrote
root-owned files into `/home/jonny`, which is why several dotfiles ended up
unwritable. The scripts elevate the individual commands that need it.

There is no `ssh-keygen` step and no key to paste into GitHub: the clone is over
HTTPS, and `31-dev-remotes` switches to SSH on a later apply once 1Password's
agent answers. On a headless Pi that agent is usually never set up, in which
case the remotes stay on HTTPS and the script says so on every apply.

Docker is not a manual step any more either. `05-repos-debian` adds the Docker
CE repo with `arch=$(dpkg --print-architecture)`, so it resolves `arm64` here;
the packages are `packages.debian.docker`, installed as their own batch once
that source exists; and `36-linux-services` adds you to the `docker` group and
enables the service.

### The desktop apps will fail, and that is expected

`packages.debian.desktop` — 1Password, Chrome, VS Code, VLC — is skipped only
under WSL, not on a headless box. The 1Password apt source is `arch=amd64` and
Chrome has no arm64 Debian package at all, so those two cannot install here.
`10-packages-debian` installs the desktop list one package at a time precisely
so this is survivable: each prints

```
  ! could not install <pkg>
```

and the apply carries on. Nothing else is affected.

## 4. Grant permissions to `/opt`

Containers and hand-installed tooling on this box live under `/opt`. Chown it to
the user once:

```bash
sudo chown -R jonny /opt
```

Not automated: it needs root, it is destructive if `/opt` already holds packaged
software with deliberate ownership, and it hardcodes a username.

## 5. Login shell

`35-login-shell` runs `chsh` for you, but it prompts for the account password
and cannot answer that prompt. If it reports `! chsh failed, login shell
unchanged`, do it by hand:

```bash
chsh -s "$(command -v zsh)"
```

PAM only reads the new shell at the next login.

## 6. Things that need a logout or reboot

| Change | Why |
| --- | --- |
| `docker` group | Group membership is read at login |
| Login shell → zsh | PAM reads `chsh` at login |
| Kernel / firmware / `raspi-config` | Reboot |

## 7. Do not reintroduce

- `ln -sf /home/jonny/.dotfiles/raspberry-pi/dotfiles/...` symlinks — chezmoi
  writes `$HOME` with no hardcoded username and no per-platform dotfile copies.
- The oh-my-zsh `curl | sh` installer and the plugin `git clone` guards —
  oh-my-zsh and its plugins are git repos, and `.chezmoiexternal.toml`
  converges them idempotently.
- `curl -sS https://starship.rs/install.sh | sh` — mise owns starship.
