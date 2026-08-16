# Fedora Workstation

Manual steps only. Everything `chezmoi apply` can converge on its own —
packages, repos, git checkouts, dotfiles, dnf tuning, GNOME and COSMIC settings
— is in the repo. This file is the list of things that need a human: physical
media, a GUI sign-in, a password prompt outside the terminal, or a reboot.

## 1. Install Fedora Workstation

1. Write the Fedora Workstation ISO to a USB stick (Fedora Media Writer, or
   `dd`).
2. Boot the installer. Enable **full-disk encryption** at the partitioning
   step — it cannot be turned on later without a reinstall.
3. Create the `jonny` user and make it an administrator.
4. Reboot into the installed system.

## 2. First boot

```shell
sudo dnf upgrade --refresh -y
sudo dnf install -y curl git
```

Reboot if the upgrade pulled a new kernel or `systemd`. Nothing below should be
attempted on a half-upgraded system.

## 3. Bootstrap

```shell
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init --apply --verbose jonnyasmith/dotfiles-new
exec zsh
```

`-b` keeps the binary out of the installer's default `./bin`, which is relative
and on no `PATH`, and `~/.local/bin` is what `.zshenv` exports. `chezmoi init` is
its own command rather than the installer's `-- init --apply`: run through the
installer it is `exec`ed out of sight, so a failure to launch looks the same as a
silent success. `--verbose` makes the apply narrate. See
[debian.md](debian.md#3-bootstrap).

There is no SSH key to generate first, and no key to paste into GitHub: the
clone is over HTTPS, and `31-dev-remotes` switches it to SSH on a later apply
once 1Password's agent is answering. The old runbook's `ssh-keygen` step existed
only because the clone came first.

The run asks whether this is a work machine, then handles:

- dnf tuning (`max_parallel_downloads`, `fastestmirror`)
- the RPM Fusion, 1Password, VS Code and Docker CE repos
- every package in `packages.fedora`
- oh-my-zsh, its plugins and tpm, as chezmoi externals
- the dotfiles, the GNOME dconf and the COSMIC config
- the mise `[tools]` — terraform, zig, starship, dotnet, node, python

## 4. 1Password — GUI sign-in and SSH agent

The package installs unattended; the account does not.

1. Launch **1Password** and sign in. If the browser hand-off does not fire,
   choose **Set up another device** on 1password.com → **Add your account
   directly**, or **Enter account details manually** in the app.
2. Settings → **Developer** → enable **Use the SSH agent**.
3. Settings → **Browser** → enable **Connect with 1Password in the browser**,
   then install the 1Password browser extension and approve the pairing dialog.

`~/.ssh/config` and `~/.config/1Password/ssh/agent.toml` both come from this
repo, so there is nothing to write by hand — the `IdentityAgent` line already
points at `~/.1password/agent.sock`.

Note: the Snap and Flatpak builds of 1Password **cannot** run the SSH agent or
system authentication. The dnf package from `downloads.1password.com` is the
only build that does — that is why it is a `dnf` package behind a repo script
rather than anything mise could supply.

## 5. Desktop settings

This laptop has **both** GNOME and COSMIC installed and switches between them at
the login screen, so both are configured. Nothing is keyed on which session
happens to be running.

| What | Applies when | Payload |
| --- | --- | --- |
| `40-desktop-dconf` | `dconf` on PATH | `.chezmoitemplates/desktop/gtk.dconf` — dark theme, font hinting/antialiasing, animations off, GTK3+GTK4 file-chooser |
| `40-desktop-dconf` | `gnome-shell` installed | `.chezmoitemplates/desktop/gnome.dconf` — touchpad, `caps:swapescape`, workspace keybindings, idle/night-light, titlebar buttons, plus `gnome-tweaks` |
| `dot_config/cosmic/` | always, as ordinary files | keyboard, shortcuts, panel/dock, idle, dark mode |

The two desktops share nothing: GNOME's state is dconf, COSMIC's is one file per
key under `~/.config/cosmic/<component>/v1/`. `caps:swapescape` is
`/org/gnome/desktop/input-sources/xkb-options` on one and
`com.system76.CosmicComp/v1/xkb_config` on the other, so it is declared twice —
once per payload. Neither is read by the other desktop.

COSMIC needs no script precisely because its config *is* files, so chezmoi owns
them directly. To pick up a change made in COSMIC **Settings**, run
`chezmoi add ~/.config/cosmic/...` and commit the result.

```shell
mise run check:dconf   # after editing .chezmoitemplates/desktop/*.dconf
```

### GNOME extensions

GNOME sessions only. Extensions are not automated — they come from
extensions.gnome.org through a browser connector.

```shell
sudo dnf install -y gnome-shell-extension-appindicator gnome-browser-connector
```

Then, in a browser, visit <https://extensions.gnome.org> and enable:

- **AppIndicator and KStatusNotifierItem Support** — required or the 1Password
  tray icon never appears.
- Anything else per taste.

**Log out and back in** after installing extensions. GNOME Shell will not load a
newly installed extension into a running session on Wayland.

On COSMIC there is no extension mechanism and none of this applies; the panel's
own applets cover the tray.

## 6. Things that need a logout or reboot

| Change | Why |
| --- | --- |
| GNOME extensions | Shell only loads them at session start (Wayland) |
| `caps:swapescape` | Set by dconf on GNOME, by `com.system76.CosmicComp/v1/xkb_config` on COSMIC; either way a running app may hold the old map |
| `docker` group | Group membership is read at login |
| Login shell → zsh | `35-login-shell` calls `chsh`; PAM only reads it at login |
| Kernel / `systemd` upgrade | Reboot |

`chsh` prompts for the account password. If the apply cannot get it, it says so
and changes nothing — run it by hand and log out:

```shell
chsh -s "$(command -v zsh)"
```

## 7. Nerd fonts

The old runbook piped a third-party installer into bash. Do not. Download the
release archive directly:

```shell
mkdir -p ~/.local/share/fonts
# unzip FiraCode.zip into ~/.local/share/fonts, then:
fc-cache -fv
```

Set the terminal font to **FiraCode Nerd Font Mono** afterwards — a GUI step in
kitty's config or the terminal's preferences.

## 8. Do not reintroduce

Each of these was in an older Fedora runbook and is now covered elsewhere.

- `ln -sf /home/jonny/.dotfiles/...` symlink scripts — chezmoi writes `$HOME`,
  with no hardcoded username.
- `nvm`, `dotnet-sdk-*` dnf packages, `sudo dnf install zig`, the starship
  `curl | sh` installer, and the HashiCorp rpm repo plus `dnf install terraform`
  — all superseded by mise `[tools]`, which pins one version per tool across
  every OS and needs no root-owned repo file.
- The oh-my-zsh `curl | sh` installer — it is a git clone, and
  `.chezmoiexternal.toml` does it idempotently.
- `packer.nvim` cloned into `~/.local/share/nvim/site/pack/packer/start` —
  unmaintained, and the path was hardcoded to one user. nvim uses lazy.nvim.
