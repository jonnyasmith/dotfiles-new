# pwsh 7+ only. Windows PowerShell 5.1 reads ~\Documents\WindowsPowerShell\
# instead and is deliberately unmanaged.

# ---------------------------------------------------------------------- xdg --
# Windows has no XDG default, so tools each invent their own location:
# nvim would read ~\AppData\Local\nvim and gh would read
# ~\AppData\Roaming\GitHub CLI, neither of which this repo writes. Both check
# XDG_CONFIG_HOME first, on every platform, so naming it here is what makes the
# ~\.config tree chezmoi applies the one that gets read.
$env:XDG_CONFIG_HOME = Join-Path $env:USERPROFILE '.config'

# Same pair .zshenv exports, for the same reason: git and chezmoi shell out to
# an editor and fall back to `vi` when these are unset — a name Windows cannot
# resolve at all. mise owns this nvim, as it does everywhere else.
$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

# ------------------------------------------------------------------ helpers --
function Import-IfAvailable {
    param([Parameter(Mandatory)][string]$Name)

    if (Get-Module -Name $Name) { return $true }
    if (-not (Get-Module -ListAvailable -Name $Name)) { return $false }
    Import-Module -Name $Name -ErrorAction SilentlyContinue
    return [bool](Get-Module -Name $Name)
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

# ----------------------------------------------------------------- runtimes --
# Each of these is the idiom the tool's own docs give for PowerShell.
if (Test-Command 'mise') {
    (& mise activate pwsh) | Out-String | Invoke-Expression
}

if (Test-Command 'starship') {
    Invoke-Expression (& starship init powershell)
}

if (Test-Command 'zoxide') {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ------------------------------------------------------------------ modules --
# PSFzf only earns its keep when the fzf binary is there (mise installs it).
# Ctrl+f rather than PSFzf's default Ctrl+t, deliberately.
if ((Test-Command 'fzf') -and (Import-IfAvailable 'PSFzf')) {
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r'
}
$null = Import-IfAvailable 'Terminal-Icons'
$null = Import-IfAvailable 'z'

# Vi editing here is deliberate: zsh is on the default emacs bindings.
if (Import-IfAvailable 'PSReadLine') {
    Set-PSReadLineOption -EditMode Vi
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

# ------------------------------------------------------------------ aliases --
# PowerShell resolves aliases before functions, so pwsh's built-in gcm
# (Get-Command), gm (Get-Member) and gp (Get-ItemProperty) would shadow the git
# shortcuts below and silently do something else. They are ReadOnly, hence
# -Force; the Alias: drive is used because Remove-Alias does not exist in 5.1.
foreach ($shadow in 'gcm', 'gm', 'gp') {
    if (Test-Path -LiteralPath "Alias:\$shadow") {
        Remove-Item -LiteralPath "Alias:\$shadow" -Force -ErrorAction SilentlyContinue
    }
}

function reload { . $PROFILE }

Set-Alias -Name vim -Value nvim
Set-Alias -Name g   -Value git
Set-Alias -Name y   -Value yarn
Set-Alias -Name h   -Value Get-History

function lg { lazygit @args }
function k  { kubectl @args }
# No `d`/`dc` as zsh has: this host runs no Docker, so containers are a WSL
# shell's job — docs/wsl.md.

# The single letters are git aliases from home/.config/git/config (a = add
# -A, cm = commit -m, f = fetch --prune, ...).
function ga   { git a . @args }
function gcm  { git cm @args }
function gf   { git f @args }
function gd   { git d @args }
function gll  { git l -20 @args }
function gm   { git m @args }
function gp   { git p @args }
function gr   { git r @args }
function gs   { git s @args }
function push { git push @args }

function gac {
    git add -A
    git commit -m ($args -join ' ')
}

# `fa` in zsh cd's through ~/dev fetching every clone; -C avoids the cd.
function fa {
    $root = Join-Path $env:USERPROFILE 'dev'
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Warning "no $root"
        return
    }
    Get-ChildItem -LiteralPath $root -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } |
        ForEach-Object {
            Write-Host "fetching $($_.Name)" -ForegroundColor Yellow
            git -C $_.FullName fetch --all
        }
}

function clean-orig {
    Get-ChildItem -Recurse -File -Filter '*.orig' | Remove-Item -Force
}

function ..    { Set-Location '..' }
function ...   { Set-Location '../..' }
function ....  { Set-Location '../../..' }
function ..... { Set-Location '../../../..' }

function ll  { Get-ChildItem @args }
function la  { Get-ChildItem -Force @args }
function lla { Get-ChildItem -Force @args }
function lld { Get-ChildItem -Directory @args }
function rmf { Remove-Item -Recurse -Force @args }

function weather { curl.exe -s 'v2.wttr.in' }

# Same opendns trick as the zsh `ip` alias, via DnsClient instead of dig.
function ip {
    (Resolve-DnsName -Name 'myip.opendns.com' -Server 'resolver1.opendns.com' -Type A).IPAddress
}
function localip {
    (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL' }).IPAddress
}
function ips {
    (Get-NetIPAddress -AddressFamily IPv4).IPAddress
}
