# macOS (Apple Silicon)

The primary machine, and the one platform where a bare `chezmoi init --apply`
gets almost all the way on its own. Everything below needs a human: a GUI
sign-in, a licence, a system permission, or a keyboard the OS will not remap
from a config file.

## 1. Prerequisites

macOS ships `curl` and enough `git` for chezmoi to clone. Running the line in
section 2 triggers the Command Line Tools prompt if the tools are absent —
accept it and let it finish before continuing.

Xcode itself is not needed. Homebrew installs the Command Line Tools as part of
its own bootstrap if you get there first.

## 2. Bootstrap

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init --apply --verbose jonnyasmith
exec zsh
```

`-b` keeps the binary out of the installer's default `./bin`, which is relative
and on no `PATH`, and `~/.local/bin` is what `.zshenv` exports. `chezmoi init` is
its own command rather than the installer's `-- init --apply`: run through the
installer it is `exec`ed out of sight, so a failure to launch looks the same as a
silent success. `--verbose` makes the apply narrate.

It asks whether this is a work machine, then installs Homebrew if `/opt/homebrew`
is empty, every formula and cask in `packages.darwin`, the mise `[tools]`, the
dotfiles, and the `defaults` writes in section 5. Expect it to take a while the
first time: the cask list is most of a laptop's worth of applications.

`chezmoi apply --dry-run -v` shows what a run would do; `chezmoi status` shows
what is out of sync.

## 3. 1Password and the SSH agent

1. Launch **1Password** and sign in.
2. Settings → **Developer** → enable **Use the SSH agent**.
3. Settings → **Browser** → enable **Connect with 1Password in the browser**,
   then install the extension and approve the pairing.

There is no key to generate. `~/.ssh/config` comes from this repo and points
`IdentityAgent` at the group-container socket:

```
~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock
```

Check all three accounts:

```sh
ssh -T git@github.com        # personal
ssh -T git@github-work       # work alias, rewritten by ~/.config/git/config.local
ssh -T git@ssh.dev.azure.com # azure
```

`Permission denied` with the agent running usually means the key set changed:
`~/.ssh/1password/refresh` rewrites the committed public-key stubs from whatever
the agent now returns, and the result is a git diff to commit.

Then run `chezmoi apply` again — with the agent answering, `31-dev-remotes`
switches the source directory and the `~/dev` checkouts from HTTPS to SSH.

## 4. Applications that need a GUI step

| App | What it needs |
| --- | --- |
| Karabiner-Elements | Approve the driver extension in System Settings → Privacy & Security, then grant Input Monitoring. Its config *is* managed — `~/.config/karabiner` — but the permission cannot be scripted |
| Alfred | Powerpack licence, and Accessibility permission for window actions |
| Rectangle | Accessibility permission |
| Parallels | Licence and a VM image |
| Slack, Teams, Todoist, Obsidian, Miro, ChatGPT, Claude, Codex | Sign in |
| kitty, Ghostty | Nothing — both read their config from this repo |

Accessibility and Input Monitoring prompts appear on first launch. Granting them
in advance from System Settings → Privacy & Security is faster than waiting to
be asked one at a time.

## 5. What `40-macos-defaults` sets

`defaults` writes into a binary plist that `cfprefsd` owns and rewrites, so this
cannot be a managed file — it is a script, and it re-runs whenever its own text
changes.

| Setting | Effect |
| --- | --- |
| `AppleShowAllExtensions` | Every file extension is shown, so a `.txt` cannot pretend to be something else |
| `com.apple.dock autohide` | Dock hides |
| `FXDefaultSearchScope = SCcf` | A new Finder search starts in the current folder, not the whole Mac |
| `ShowStatusBar` | Finder status bar on |
| `FXEnableExtensionChangeWarning` | No prompt when renaming an extension |
| `WarnOnEmptyTrash` | No prompt when emptying the trash |
| `AppleBluetoothMultitouch.trackpad Clicking` | Tap to click, for the built-in trackpad and a Magic Trackpad both |

The script restarts Finder and Dock at the end, because `defaults write` does
not notify a running app — each re-reads its domain at launch.

Anything you want added goes in that script, not into System Settings by hand,
or the next machine will not have it.

## 6. Login shell

`35-login-shell` runs `chsh -s /bin/zsh`. macOS already defaults to zsh, so this
is usually a no-op — but it uses `/bin/zsh`, not the Homebrew `zsh`, because
only shells listed in `/etc/shells` are accepted and the Homebrew one is not
there by default.

If it reports `! chsh failed, login shell unchanged`, run it by hand; it prompts
for the account password, and the change takes effect at the next login.

## 7. Fonts

`font-fira-mono-nerd-font` is a cask, so it installs with everything else. kitty
and starship both expect a Nerd Font; glyphs render as boxes without one.

This is the one place the font differs from Windows, which uses JetBrains Mono —
winget has no manifest for a Fira Mono Nerd Font under any publisher.

## 8. tmux plugins

Once, inside tmux: `prefix + I`. chezmoi clones tpm as an external but cannot
press the key for you.
