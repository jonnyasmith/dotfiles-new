# Arch Linux

Everything `chezmoi apply` can do — package installs, git clones, service
enablement, `vm.swappiness`, pacman colour — is in the repo and is **not**
repeated here. What remains are the steps a human has to perform: OS
installation, GUI sign-ins, firmware and bootloader edits, and anything gated on
a reboot.

Arch is not a target of the architecture this repo is built around, but one
machine runs it. Target: Dell XPS (Intel iGPU + NVIDIA dGPU), GNOME, LTS kernel.

## 1. Install the OS (`archinstall`)

Boot the Arch ISO. The installer needs a network first.

### Connect to wifi

```bash
iwctl
device list                        # e.g. wlan0
station <device> scan
station <device> connect <SSID>
exit
```

### `archinstall` answers

- Locale — keyboard UK, language `en_GB.UTF-8`, encoding UTF-8
- Mirrors and repositories: United Kingdom
- Partitioning: best-effort default layout, btrfs, compression on
- Swap: zram enabled
- Bootloader: GRUB
- Hostname: `dell-xps`
- Users: set a root password; create a user with a password and grant sudo
- Audio: PipeWire
- Kernels: remove `linux`, add `linux-lts`
- Network configuration: NetworkManager
- Additional packages: `gnome`
- Timezone: Europe/London, NTP enabled

Then reboot into the installed system.

### First boot — start the display manager

`archinstall` does not always leave GDM enabled. This runs before the repo
exists, so nothing in it can do the job:

```bash
sudo systemctl enable --now gdm.service
```

## 2. AUR: install `yay` before bootstrapping

**pacman installs from the official repositories only. It cannot install from
the AUR.** Several packages this machine needs are AUR-only:

| Package | Why it is AUR-only |
| --- | --- |
| `auto-cpufreq` | never packaged in `extra` |
| `envycontrol` | never packaged in `extra` |
| `1password`, `1password-cli` | proprietary; upstream ships AUR + a signed repo |
| `google-chrome` | no official Arch package |
| `visual-studio-code-bin` | proprietary MS build of the OSS `code` package |

`10-packages-arch` shells out to `yay` for those, but it cannot install `yay`
itself: bootstrapping it needs `base-devel` and a `makepkg` run that prompts for
your sudo password. Do it once by hand first — it is a prerequisite of the
automation, not a duplicate of it. Without it the apply reports the AUR list as
skipped and carries on.

```bash
if ! command -v yay >/dev/null 2>&1; then
    sudo pacman -S --noconfirm --needed git base-devel
    git clone https://aur.archlinux.org/yay.git ~/yay
    (cd ~/yay && makepkg -si --noconfirm)
    rm -rf ~/yay
fi
```

## 3. Bootstrap

```bash
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

Alongside the packages and dotfiles, `38-arch-services` enables TLP and
`NetworkManager-dispatcher`, masks `systemd-rfkill` (TLP owns radio state and
the two fight over the wifi and bluetooth blocks), installs the `auto-cpufreq`
unit, enables `fstrim.timer`, turns on pacman's colour output, and writes
`vm.swappiness=10`.

## 4. Sign in to 1Password

Open 1Password, sign in, and enable the SSH agent. The dotfiles point
`~/.ssh/config` and git at it, so the terminal will not authenticate to GitHub
until this is done. There is no headless path.

## 5. Install a Nerd Font

kitty and starship both expect one; glyphs render as boxes until it is present.
Take it from the official repos:

```bash
sudo pacman -S ttf-jetbrains-mono-nerd
```

Do not use the `curl | bash` nerd-fonts installer the old runbook suggested —
it is an interactive menu around a download you can do directly.

## 6. Verify power management

A **reboot** after the first apply is worth it, so every service starts cleanly.

Confirm the CPU governor is actually being driven — stats in one pane, load in
another:

```bash
auto-cpufreq --stats
stress -c 4
```

`auto-cpufreq` should switch the governor to `performance` under load and back
to `powersave` when `stress` exits.

Check idle draw. An optimised system should idle in the 5–8 W range:

```bash
upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep energy-rate
```

If the figure is well above 8 W, the NVIDIA card is probably still powered — see
the next section.

## 7. Switch to integrated graphics

Requires a reboot, so it stays manual:

```bash
sudo envycontrol -s integrated
```

Reboot for this to take effect. `sudo envycontrol -s hybrid` switches back.
Afterwards, confirm the NVIDIA card is gone from the PCI listing — if it is not
listed, it is genuinely powered off:

```bash
lspci -k | grep -A 2 -E "(VGA|3D)"
```

## 8. High-DPI display setup (GNOME)

Disable fractional scaling, use 200% integer scaling, and adjust font sizes to
compensate. `gnome-tweaks` is installed by `40-desktop-dconf`; the settings
themselves are per-user GUI state.

- Settings → Displays → Scale **200%**, fractional scaling **off**
- GNOME Tweaks → Fonts → reduce the scaling factor until text looks right

Re-check idle draw with the `upower` command in section 6 afterwards — a mis-set
scale can keep the GPU busy.

## 9. GNOME extensions

Extension Manager is in `packages.arch.core`. Its catalogue is a GUI with no
scriptable install path:

- Open **Extension Manager**
- Install **Space Bar**

## 10. Enable boot logging (GRUB)

Kernel and systemd messages are hidden by default.

```bash
sudo vi /etc/default/grub
```

Find `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"`. `quiet` suppresses most kernel
and systemd messages; `splash` drives a graphical splash screen. Remove both:

```bash
GRUB_CMDLINE_LINUX_DEFAULT=""
```

Then regenerate the config and reboot:

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

## 11. Portainer

`39-portainer` writes `/opt/portainer/docker-compose.yml` — sudo, because it is
outside `$HOME` — and runs `docker compose up -d`. Docker here is Arch's own
`docker` and `docker-compose` packages from `packages.arch.core`, and
`36-linux-services` enables the service and adds the group. `docker info` gates
the script, so before the group re-login it prints a `.` line and defers; the
container arrives on the first apply after that.

Portainer's first-run admin account is created at <http://localhost:9000> and
the window times out if you leave it; `docker restart portainer` reopens it.

## Reboot checklist

Three steps here ask for a reboot. Do them together, then reboot once:

1. First `chezmoi apply` completed — TLP and auto-cpufreq services started
2. `sudo envycontrol -s integrated`
3. The `vm.swappiness` sysctl and the GRUB `GRUB_CMDLINE_LINUX_DEFAULT` edit

Afterwards, run the section 6 and section 7 verification commands.
