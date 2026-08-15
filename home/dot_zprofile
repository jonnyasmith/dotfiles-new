# Guarded: nothing in this repo installs Homebrew, so most machines have none
# and still need a working login shell.
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
	[ -x "$_brew" ] && eval "$("$_brew" shellenv)" && break
done
unset _brew

# OrbStack CLI integration — where `docker` and `orb` come from.
source "$HOME/.orbstack/shell/init.zsh" 2>/dev/null || :

# Put the shims back in front of the /opt/homebrew/bin brew just prepended.
mise-shims-first
