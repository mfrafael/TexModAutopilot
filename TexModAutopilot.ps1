# ============================================================
#  TexModAutopilot - opens TexMod, points it at the game, loads the
#  .tpf packages from the Mod folder (in the order set in
#  TexModAutopilot.ini) and clicks Run.
#
#  The automation talks directly to TexMod's window controls
#  through Win32 messages (BM_CLICK / WM_SETTEXT) - no blind
#  coordinate clicking - so it works at any DPI, resolution or
#  Windows language.
#
#  Usage:  TexModAutopilot.bat   (or: powershell -File TexModAutopilot.ps1)
#  Optional parameters:
#    -NoRun      ignore AutoRun and do NOT click Run (to inspect TexMod)
#    -TestMode   click Run, wait for the game window, then kill game + TexMod
# ============================================================
param(
    [switch]$NoRun,
    [switch]$TestMode
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$IniPath   = Join-Path $ScriptDir 'TexModAutopilot.ini'
$LogPath   = Join-Path $ScriptDir 'TexModAutopilot.log'

# --- logging -------------------------------------------------
Set-Content -Path $LogPath -Value '' -Encoding UTF8
function Log([string]$msg) {
    $line = '[{0:HH:mm:ss.fff}] {1}' -f (Get-Date), $msg
    Write-Host $line
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}
function Fail([string]$msg) {
    Log "ERROR: $msg"
    Log 'Tip: increase Delay in TexModAutopilot.ini and try again. See TexModAutopilot.log.'
    exit 1
}

# --- Win32 ---------------------------------------------------
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class ETM {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wp, string lp);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wp, StringBuilder lp);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    public const uint BM_CLICK = 0x00F5;
    public const uint WM_SETTEXT = 0x000C;
    public const uint WM_GETTEXT = 0x000D;
    public const uint WM_CLOSE = 0x0010;
}
'@

# --- helpers -------------------------------------------------
function Get-WndText([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 1024
    [void][ETM]::SendMessage($h, [ETM]::WM_GETTEXT, [IntPtr]1024, $sb)
    $sb.ToString()
}
function Get-WndClass([IntPtr]$h) {
    $sb = New-Object System.Text.StringBuilder 256
    [void][ETM]::GetClassName($h, $sb, 256)
    $sb.ToString()
}
# Children (recursive, z-order) of $parent; empty $class = all of them
function Get-Children([IntPtr]$parent, [string]$class) {
    $script:__enum = New-Object System.Collections.ArrayList
    $script:__enumClass = $class
    $cb = [ETM+EnumProc]{
        param($h, $lp)
        if (-not $script:__enumClass -or (Get-WndClass $h) -eq $script:__enumClass) {
            [void]$script:__enum.Add($h)
        }
        return $true
    }
    [void][ETM]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    ,$script:__enum
}
# Child (recursive) with a given control ID and class
function Find-ChildById([IntPtr]$parent, [int]$id, [string]$class) {
    $script:__fidId = $id; $script:__fidClass = $class; $script:__fidFound = [IntPtr]::Zero
    $cb = [ETM+EnumProc]{
        param($h, $lp)
        if ([ETM]::GetDlgCtrlID($h) -eq $script:__fidId -and (-not $script:__fidClass -or (Get-WndClass $h) -eq $script:__fidClass)) {
            $script:__fidFound = $h; return $false
        }
        return $true
    }
    [void][ETM]::EnumChildWindows($parent, $cb, [IntPtr]::Zero)
    if ($script:__fidFound -eq [IntPtr]::Zero) { $null } else { $script:__fidFound }
}
# Visible top-level window of a process, filtered by class and/or title (regex).
# Note: FindWindow() fails to locate TexMod's 'tmlwndcls' window, so we must
# enumerate. Also note PowerShell treats [IntPtr]::Zero as truthy, hence $null.
function Find-TopWindow([uint32]$ownerPid, [string]$class, [string]$titleRegex) {
    $script:__found = [IntPtr]::Zero
    $script:__fPid = $ownerPid; $script:__fClass = $class; $script:__fTitle = $titleRegex
    $cb = [ETM+EnumProc]{
        param($h, $lp)
        if (-not [ETM]::IsWindowVisible($h)) { return $true }
        $wpid = [uint32]0
        [void][ETM]::GetWindowThreadProcessId($h, [ref]$wpid)
        if ($wpid -ne $script:__fPid) { return $true }
        if ($script:__fClass -and (Get-WndClass $h) -ne $script:__fClass) { return $true }
        if ($script:__fTitle -and (Get-WndText $h) -notmatch $script:__fTitle) { return $true }
        $script:__found = $h
        return $false
    }
    [void][ETM]::EnumWindows($cb, [IntPtr]::Zero)
    if ($script:__found -eq [IntPtr]::Zero) { $null } else { $script:__found }
}
function Wait-For([scriptblock]$cond, [int]$timeoutMs, [string]$what) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
        $r = & $cond
        if ($r) { return $r }
        Start-Sleep -Milliseconds 100
    }
    Fail "timed out waiting for: $what"
}
function Click-Button([IntPtr]$h) {
    [void][ETM]::PostMessage($h, [ETM]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
}
# Force a window to the foreground, working around Windows' foreground lock
# by temporarily attaching our thread input to the current foreground thread.
function Force-Foreground([IntPtr]$h) {
    $fg = [ETM]::GetForegroundWindow()
    $myThread = [ETM]::GetCurrentThreadId()
    $fgThread = [uint32]0
    if ($fg -ne [IntPtr]::Zero) { [void][ETM]::GetWindowThreadProcessId($fg, [ref]$fgThread) }
    $attached = $false
    if ($fgThread -ne 0 -and $fgThread -ne $myThread) {
        $attached = [ETM]::AttachThreadInput($myThread, $fgThread, $true)
    }
    [void][ETM]::ShowWindow($h, 9)   # SW_RESTORE (no-op if not minimized)
    [void][ETM]::BringWindowToTop($h)
    [void][ETM]::SetForegroundWindow($h)
    if ($attached) { [void][ETM]::AttachThreadInput($myThread, $fgThread, $false) }
}

# Clicks a TexMod browse button and waits for the file dialog to open.
# Depending on the TexMod build, the button opens the dialog directly OR
# shows a dropdown menu first (then we pick the first item, "Browse...",
# with down-arrow + Enter).
function Open-BrowseDialog([IntPtr]$mainWnd, [IntPtr]$btn, [uint32]$ownerPid, [string]$titleRegex, [string]$what) {
    # a posted click can occasionally get lost while TexMod is busy, so try twice
    foreach ($attempt in 1..2) {
        [void][ETM]::SetForegroundWindow($mainWnd)
        Start-Sleep -Milliseconds $Delay
        Click-Button $btn
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $menuKeysSent = $false
        while ($sw.ElapsedMilliseconds -lt 8000) {
            $dlg = Find-TopWindow $ownerPid '#32770' $titleRegex
            if ($dlg) { return $dlg }
            if (-not $menuKeysSent) {
                # Some TexMod builds show a dropdown menu (class #32768) instead of
                # opening the dialog directly; pick its first item ("Browse...").
                # Only menus owned by the TexMod process count (other apps' menus are
                # ignored), and the keys are POSTED to TexMod's own message queue -
                # focus-independent, nothing ever leaks into other applications.
                $menu = Find-TopWindow $ownerPid '#32768' ''
                if ($menu) {
                    Start-Sleep -Milliseconds $Delay
                    foreach ($vk in 0x28, 0x0D) {  # VK_DOWN, VK_RETURN
                        [void][ETM]::PostMessage($mainWnd, 0x0100, [IntPtr]$vk, [IntPtr]::Zero)  # WM_KEYDOWN
                        [void][ETM]::PostMessage($mainWnd, 0x0101, [IntPtr]$vk, [IntPtr]::Zero)  # WM_KEYUP
                        Start-Sleep -Milliseconds 100
                    }
                    $menuKeysSent = $true
                }
            }
            Start-Sleep -Milliseconds 100
        }
        if ($attempt -eq 1) { Log "  '$what' dialog did not open - clicking again..." }
    }
    Fail "timed out waiting for the dialog/menu of '$what'"
}

# Fills in the open-file dialog and confirms with OK (control id 1 = IDOK)
function Complete-FileDialog([IntPtr]$dlg, [string]$path, [string]$what) {
    Start-Sleep -Milliseconds $Delay
    # file name field: cmb13 (1148) in Explorer-style dialogs, edt1 (1152) in old-style
    $edit = [ETM]::GetDlgItem($dlg, 1148)
    if ($edit -eq [IntPtr]::Zero) { $edit = [ETM]::GetDlgItem($dlg, 1152) }
    if ($edit -eq [IntPtr]::Zero) {
        $edits = Get-Children $dlg 'Edit'
        if ($edits.Count -gt 0) { $edit = $edits[0] }
    }
    if ($edit -eq [IntPtr]::Zero) { Fail "could not find the file name field in the '$what' dialog" }
    [void][ETM]::SendMessage($edit, [ETM]::WM_SETTEXT, [IntPtr]::Zero, $path)
    Start-Sleep -Milliseconds $Delay
    $ok = [ETM]::GetDlgItem($dlg, 1)
    if ($ok -eq [IntPtr]::Zero) { Fail "could not find the OK button of the '$what' dialog" }
    Click-Button $ok
    Wait-For { -not ([ETM]::IsWindow($dlg) -and [ETM]::IsWindowVisible($dlg)) } 8000 "'$what' dialog to close" | Out-Null
    Start-Sleep -Milliseconds $Delay
}

# --- read the ini --------------------------------------------
if (-not (Test-Path $IniPath)) { Fail "TexModAutopilot.ini not found in $ScriptDir" }
$settings = @{}
$loadOrder = New-Object System.Collections.ArrayList
$section = ''
foreach ($raw in Get-Content $IniPath) {
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
    if ($line -match '^\[(.+)\]$') { $section = $matches[1]; continue }
    if ($section -eq 'Settings' -and $line -match '^([^=]+)=(.*)$') {
        $settings[$matches[1].Trim()] = $matches[2].Trim()
    } elseif ($section -eq 'LoadOrder') {
        # accepts "file.tpf" or "1=file.tpf"
        $v = if ($line -match '^\d+\s*=\s*(.+)$') { $matches[1].Trim() } else { $line }
        if ($v) { [void]$loadOrder.Add($v) }
    }
}

function Resolve-Rel([string]$p) {
    if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $ScriptDir $p }
}
$TexModExe = Resolve-Rel ($settings['TexMod'] + '')
$GameExe   = Resolve-Rel ($settings['Game'] + '')
$ModFolder = Resolve-Rel ($settings['ModFolder'] + '')
$Delay     = 300; if ($settings['Delay'] -match '^\d+$') { $Delay = [int]$settings['Delay'] }
$AutoRun   = ($settings['AutoRun'] -ne '0')
$CloseOnExit = ($settings['CloseTexModOnExit'] -ne '0')
if ($NoRun) { $AutoRun = $false }
if ($TestMode) { $AutoRun = $true }

if (-not (Test-Path $TexModExe)) { Fail "TexMod not found: $TexModExe (edit TexModAutopilot.ini)" }
if (-not (Test-Path $GameExe))   { Fail "game executable not found: $GameExe (edit TexModAutopilot.ini)" }
if (-not (Test-Path $ModFolder)) { Fail "mod folder not found: $ModFolder (edit TexModAutopilot.ini)" }

# build the tpf list
$tpfs = New-Object System.Collections.ArrayList
if ($loadOrder.Count -gt 0) {
    foreach ($m in $loadOrder) {
        $p = if ([IO.Path]::IsPathRooted($m)) { $m } else { Join-Path $ModFolder $m }
        if (-not (Test-Path $p)) { Fail "LoadOrder mod not found: $p" }
        [void]$tpfs.Add((Get-Item $p).FullName)
    }
    Log ("LoadOrder defined in the ini: {0} mod(s)" -f $tpfs.Count)
} else {
    foreach ($f in (Get-ChildItem -Path $ModFolder -Filter *.tpf | Sort-Object Name)) {
        [void]$tpfs.Add($f.FullName)
    }
    Log ("LoadOrder is empty: loading every .tpf from '{0}' in alphabetical order ({1} mod(s))" -f $ModFolder, $tpfs.Count)
}
if ($tpfs.Count -eq 0) { Fail "no .tpf files found in $ModFolder" }

$gameProcName = [IO.Path]::GetFileNameWithoutExtension($GameExe)

# --- close a leftover TexMod, if one is open -----------------
foreach ($p in (Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($TexModExe)) -ErrorAction SilentlyContinue)) {
    Log "TexMod was already open (PID $($p.Id)) - closing it to start clean"
    $p.CloseMainWindow() | Out-Null
    if (-not $p.WaitForExit(3000)) { $p.Kill() }
}

# --- launch TexMod -------------------------------------------
Log "Launching TexMod: $TexModExe"
$tm = Start-Process -FilePath $TexModExe -WorkingDirectory $ScriptDir -PassThru
$tmPid = [uint32]$tm.Id

$main = Wait-For { Find-TopWindow $tmPid 'tmlwndcls' '' } 15000 'TexMod main window'
Log "TexMod window found (hwnd=$main)"
Start-Sleep -Milliseconds ($Delay * 2)

# TexMod 0.9b controls by control ID (mapped by inspecting the window);
# if not found, fall back to z-order position (same indexes TexModAutomator used).
$btnTargetBrowse  = Find-ChildById $main 100 'Button'   # "Target Application" browse button
$btnRun           = Find-ChildById $main 103 'Button'   # Run
$btnPackageBrowse = Find-ChildById $main 111 'Button'   # "Select Packages" browse button
$lstPackages      = Find-ChildById $main 110 'SysListView32'  # loaded packages list
if (-not ($btnTargetBrowse -and $btnRun -and $btnPackageBrowse)) {
    Log 'Warning: expected control IDs not found - falling back to button z-order positions.'
    $buttons = Get-Children $main 'Button'
    if ($buttons.Count -lt 12) { Fail "expected at least 12 buttons in the TexMod window, found $($buttons.Count). Is TexMod in Package Mode?" }
    $btnTargetBrowse  = $buttons[1]
    $btnRun           = $buttons[10]
    $btnPackageBrowse = $buttons[11]
}
$LVM_GETITEMCOUNT = 0x1004
function Get-PackageCount {
    if (-not $lstPackages) { return -1 }
    [int][ETM]::SendMessage($lstPackages, $LVM_GETITEMCOUNT, [IntPtr]::Zero, [IntPtr]::Zero)
}

# --- set the target game -------------------------------------
Log "Selecting target game: $GameExe"
$dlg = Open-BrowseDialog $main $btnTargetBrowse $tmPid '^Select Executable' 'Target Application'
Complete-FileDialog $dlg $GameExe 'Select Executable'
# once the target is accepted, the title becomes "TexMod - <EXE>"
$gameLeaf = [regex]::Escape((Split-Path $GameExe -Leaf))
Wait-For { (Get-WndText $main) -match $gameLeaf } 10000 'target game confirmation in the TexMod title' | Out-Null
Log ("Target game set: window title is now '{0}'" -f (Get-WndText $main))

# --- load the packages, one by one, in order -----------------
$i = 0
foreach ($tpf in $tpfs) {
    $i++
    Log ("Loading mod {0}/{1}: {2}" -f $i, $tpfs.Count, (Split-Path $tpf -Leaf))
    $dlg = Open-BrowseDialog $main $btnPackageBrowse $tmPid '^Select Texmod Packages' 'Select Packages'
    Complete-FileDialog $dlg $tpf 'Select Texmod Packages'
    if ($lstPackages) {
        $want = $i
        Wait-For { (Get-PackageCount) -ge $want } 15000 "package $i to show up in the TexMod list" | Out-Null
    }
}
Log ("All mods loaded. Packages in the TexMod list: {0}" -f (Get-PackageCount))

# --- Run -----------------------------------------------------
if (-not $AutoRun) {
    Log 'AutoRun is off: TexMod is left open with everything loaded. Click Run whenever you want.'
    exit 0
}

Log 'Clicking Run...'
[void][ETM]::SetForegroundWindow($main)
Start-Sleep -Milliseconds $Delay
Click-Button $btnRun

$game = Wait-For { Get-Process -Name $gameProcName -ErrorAction SilentlyContinue | Select-Object -First 1 } 60000 "game process ($gameProcName)"
Log ("Game process created (PID {0})." -f $game.Id)
Log 'TexMod is now loading the textures inside the game - with big mods this'
Log 'can take 1-2+ minutes with NOTHING on screen. Do NOT click Run again!'

# wait for the game window to actually show up
$swWin = [Diagnostics.Stopwatch]::StartNew()
$winOk = $false
$nextNotice = 15
while ($swWin.Elapsed.TotalSeconds -lt 300) {
    $game.Refresh()
    if ($game.HasExited) {
        Fail 'the game process exited before showing a window. Run TexModAutopilot again; if it keeps happening, open TexMod and click Run manually to see the error.'
    }
    if ($game.MainWindowHandle -ne [IntPtr]::Zero) { $winOk = $true; break }
    if ($swWin.Elapsed.TotalSeconds -ge $nextNotice) {
        Log ("  ... still loading textures ({0:N0}s)" -f $swWin.Elapsed.TotalSeconds)
        $nextNotice += 15
    }
    Start-Sleep -Seconds 2
}
if ($winOk) {
    Log ("Game window appeared after {0:N0}s." -f $swWin.Elapsed.TotalSeconds)
    Force-Foreground $game.MainWindowHandle
    Log 'Game brought to the foreground. Have fun!'
} else {
    Log 'Warning: 5 minutes and the game window has not appeared. Leaving it running - check TexMod.'
}

if ($TestMode) {
    Log 'TestMode: killing game + TexMod...'
    Get-Process -Name $gameProcName -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    Get-Process -Id $tmPid -ErrorAction SilentlyContinue | Stop-Process -Force
    Log 'TestMode finished.'
    exit 0
}

if ($CloseOnExit) {
    Log 'Waiting for the game to close so TexMod can be shut down...'
    while (Get-Process -Name $gameProcName -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
    Log 'Game closed - shutting down TexMod.'
    $tmProc = Get-Process -Id $tmPid -ErrorAction SilentlyContinue
    if ($tmProc) {
        [void][ETM]::PostMessage($main, [ETM]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
        if (-not $tmProc.WaitForExit(3000)) { $tmProc.Kill() }
    }
}
Log 'Done!'
exit 0
