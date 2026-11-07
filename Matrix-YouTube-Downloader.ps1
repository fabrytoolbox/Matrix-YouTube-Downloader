# Matrix-YouTube-Downloader.ps1 - v1.0 (Matrix Edition)
# Codename: "Church" (The Expendables)
# Downloader video/audio da YouTube e altri siti con GUI Matrix.
# Richiede PowerShell 7.2+ e yt-dlp.

#Requires -Version 7.2

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================
# CONFIGURAZIONE E PERCORSI
# ============================================================
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:logFile = $null
$global:ytdlpPath = $null
$global:ytdlpVersion = "N/D"

$global:downloadDir = Join-Path $scriptPath "Downloads"
if (-not (Test-Path $global:downloadDir)) {
    New-Item -ItemType Directory -Path $global:downloadDir -Force | Out-Null
}

# ============================================================
# AUTO-ELEVAZIONE ADMIN
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $pwshPath = Join-Path $PSHOME "pwsh.exe"
    if (-not (Test-Path $pwshPath)) { $pwshPath = "pwsh.exe" }
    Start-Process $pwshPath -ArgumentList "-NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ============================================================
# LOGGING
# ============================================================
function Start-Log {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:logFile = Join-Path $scriptPath "matrix_youtube_downloader_$timestamp.log"
    @(
        "============================================================",
        " MATRIX YOUTUBE DOWNLOADER v1.0 - CODENAME: CHURCH",
        "============================================================",
        "Data inizio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "PowerShell : $($PSVersionTable.PSVersion)",
        "============================================================",
        ""
    ) | Set-Content -Path $script:logFile -Encoding UTF8
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (-not $script:logFile) { return }
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $script:logFile -Value $line -Encoding UTF8
}

Start-Log

# ============================================================
# GESTIONE YT-DLP (Controllo e Auto-Download)
# ============================================================
function Test-YtDlp {
    $possiblePaths = @(
        (Join-Path $scriptPath "yt-dlp.exe"),
        "yt-dlp.exe" # nel PATH
    )
    foreach ($p in $possiblePaths) {
        if ($p -eq "yt-dlp.exe") {
            $cmd = Get-Command yt-dlp.exe -ErrorAction SilentlyContinue
            if ($cmd) { $global:ytdlpPath = $cmd.Source; break }
        } elseif (Test-Path $p) {
            $global:ytdlpPath = $p; break
        }
    }

    if ($global:ytdlpPath) {
        try {
            $v = & $global:ytdlpPath --version 2>&1 | Select-Object -First 1
            $global:ytdlpVersion = $v
        } catch { }
        Write-Log "yt-dlp trovato: $($global:ytdlpPath) (v$($global:ytdlpVersion))" "OK"
        return $true
    } else {
        Write-Log "yt-dlp NON trovato nel sistema." "WARN"
        return $false
    }
}

function Install-YtDlp {
    Write-Log "Richiesta installazione yt-dlp." "INFO"
    $msg = "yt-dlp non e' stato trovato nel sistema.`n`n" +
           "Vuoi scaricarlo automaticamente ora da GitHub?`n" +
           "(Verrà salvato nella cartella corrente: $scriptPath)"
    
    $resp = [System.Windows.Forms.MessageBox]::Show(
        $msg, "MATRIX - INSTALLA YT-DLP", 
        [System.Windows.Forms.MessageBoxButtons]::YesNo, 
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($resp -eq "Yes") {
        $destPath = Join-Path $scriptPath "yt-dlp.exe"
        $url = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        Write-Log "Download yt-dlp da: $url" "INFO"
        
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($url, $destPath)
            Write-Log "yt-dlp scaricato con successo in: $destPath" "OK"
            $global:ytdlpPath = $destPath
            return $true
        } catch {
            Write-Log "Errore download yt-dlp: $($_.Exception.Message)" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("Download fallito: $($_.Exception.Message)", "ERRORE", "OK", "Error") | Out-Null
            return $false
        }
    }
    return $false
}

# ============================================================
# FUNZIONI HELPER
# ============================================================
function Get-VideoQualityArgs {
    param([string]$Quality)
    switch ($Quality) {
        "360p"  { return "-f `"bestvideo[height<=360]+bestaudio/best[height<=360]`"" }
        "720p"  { return "-f `"bestvideo[height<=720]+bestaudio/best[height<=720]`"" }
        "1080p" { return "-f `"bestvideo[height<=1080]+bestaudio/best[height<=1080]`"" }
        "BEST"  { return "-f `"bestvideo+bestaudio/best`"" }
        default { return "-f `"bestvideo+bestaudio/best`"" }
    }
}

function Get-UserAgentArgs {
    param([int]$Index)
    switch ($Index) {
        1 { return "--user-agent `"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1`"" }
        2 { return "--user-agent `"Mozilla/5.0 (Linux; Android 14; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36`"" }
        3 { return "--user-agent `"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Safari/537.36`"" }
        default { return "" }
    }
}

# ============================================================
# FUNZIONE DI DOWNLOAD (Il Motore)
# ============================================================
$global:ytdlpProcess = $null
$global:isDownloading = $false

function Start-YtDlpDownload {
    param(
        [string]$Url,
        [string]$Format,
        [string]$Quality,
        [bool]$IsPlaylist,
        [bool]$UseCookiesFile,
        [bool]$UseBrowserCookies,
        [bool]$EmbedSubtitles,
        [int]$UserAgentIndex,
        [bool]$UseJsRuntime,
        [bool]$BypassProtected
    )

    if ($global:isDownloading) {
        [System.Windows.Forms.MessageBox]::Show("C'e' gia' un download in corso.", "MATRIX - OCCUPATO", "OK", "Warning") | Out-Null
        return
    }

    # 1. Costruzione degli argomenti
    $argsList = @()
    $argsList += "`"$Url`""

    $fmtArg = ""
    if ($Format -match "mp3|flac") {
        $fmtArg = "--extract-audio --audio-format $Format --audio-quality 0"
    } else {
        $qualArg = Get-VideoQualityArgs -Quality $Quality
        $fmtArg = "$qualArg --merge-output-format $Format"
    }
    $argsList += $fmtArg

    if (-not $IsPlaylist) { $argsList += "--no-playlist" }
    if ($EmbedSubtitles) { $argsList += "--write-subs --sub-lang it,en --embed-subs" }

    $uaArg = Get-UserAgentArgs -Index $UserAgentIndex
    if ($uaArg) { $argsList += $uaArg }

    if ($UseJsRuntime) { $argsList += "--js-runtimes node,deno" }

    if ($UseCookiesFile) {
        $cookiePath = Join-Path $scriptPath "cookies.txt"
        if (Test-Path $cookiePath) { $argsList += "--cookies `"$cookiePath`"" }
    } elseif ($UseBrowserCookies) {
        $argsList += "--cookies-from-browser chrome"
    }

    if ($BypassProtected) {
        $argsList += "--add-header `"Referer: $Url`""
    }

    $outputTemplate = Join-Path $global:downloadDir "%(title)s.%(ext)s"
    $argsList += "--restrict-filenames"
    $argsList += "-o `"$outputTemplate`""
    $argsList += "--newline"

    $finalArgs = $argsList -join " "
    Write-Log "Avvio yt-dlp con argomenti: $finalArgs" "INFO"

    # 2. Configurazione del processo
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $global:ytdlpPath
        $psi.Arguments = $finalArgs
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $scriptPath

        $global:ytdlpProcess = New-Object System.Diagnostics.Process
        $global:ytdlpProcess.StartInfo = $psi
        
        $global:isDownloading = $true
        $global:ytdlpProcess.Start() | Out-Null

        # 3. Timer per leggere l'output
        $global:outputTimer = New-Object System.Windows.Forms.Timer
        $global:outputTimer.Interval = 200
        $global:outputTimer.Add_Tick({
            if ($global:ytdlpProcess -and -not $global:ytdlpProcess.HasExited) {
                while (-not $global:ytdlpProcess.StandardOutput.EndOfStream) {
                    $line = $global:ytdlpProcess.StandardOutput.ReadLine()
                    if ($line) { 
                        $global:txtLog.AppendText("$line`r`n")
                        $global:txtLog.SelectionStart = $global:txtLog.Text.Length
                        $global:txtLog.ScrollToCaret()

                        if ($line -match '\[download\]\s+([\d\.]+)%') {
                            $percent = [int][math]::Floor([double]$Matches[1])
                            $global:progressBar.Value = $percent
                        }
                    }
                }
                while (-not $global:ytdlpProcess.StandardError.EndOfStream) {
                    $errLine = $global:ytdlpProcess.StandardError.ReadLine()
                    if ($errLine) {
                        $global:txtLog.AppendText("$errLine`r`n")
                        $global:txtLog.SelectionStart = $global:txtLog.Text.Length
                        $global:txtLog.ScrollToCaret()
                    }
                }
            } else {
                $global:outputTimer.Stop()
                $global:isDownloading = $false
                
                if ($global:ytdlpProcess.ExitCode -eq 0) {
                    $global:txtLog.AppendText("`r`n[OK] Download completato con successo!`r`n")
                    $global:lblStatus.Text = "> Download completato."
                    $global:progressBar.Value = 100
                } else {
                    $global:txtLog.AppendText("`r`n[ERRORE] Download terminato con codice $($global:ytdlpProcess.ExitCode)`r`n")
                    $global:lblStatus.Text = "> Errore nel download."
                    $global:progressBar.Value = 0
                }
                
                $global:btnDownload.Enabled = $true
                $global:btnDownload.Text = "▶  INIZIA DOWNLOAD"
                $global:btnDownload.ForeColor = [System.Drawing.Color]::Lime
                $global:progressBar.Visible = $false
            }
        })
        $global:outputTimer.Start()

        $global:btnDownload.Enabled = $false
        $global:btnDownload.Text = "DOWNLOAD IN CORSO..."
        $global:btnDownload.ForeColor = [System.Drawing.Color]::Yellow
        $global:progressBar.Visible = $true
        $global:progressBar.Value = 0
        $global:txtLog.Clear()
        $global:txtLog.AppendText("[INFO] Connessione a yt-dlp...`r`n")
        $global:lblStatus.Text = "> Download in corso..."

    } catch {
        $global:isDownloading = $false
        Write-Log "Errore avvio yt-dlp: $($_.Exception.Message)" "ERROR"
        $global:txtLog.AppendText("[ERRORE CRITICO] $($_.Exception.Message)`r`n")
        [System.Windows.Forms.MessageBox]::Show("Impossibile avviare yt-dlp:`n$($_.Exception.Message)", "MATRIX - ERRORE", "OK", "Error") | Out-Null
    }
}

# ============================================================
# INTERFACCIA GRAFICA - MATRIX EDITION
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = "MATRIX YOUTUBE DOWNLOADER - CHURCH"
$form.Size            = New-Object System.Drawing.Size(820, 720)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox     = $false
$form.BackColor       = [System.Drawing.Color]::Black
$form.ForeColor       = [System.Drawing.Color]::Lime
$form.Font            = New-Object System.Drawing.Font("Consolas", 10)
$form.AllowDrop       = $true

# --- HEADER ---
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "MATRIX YOUTUBE DOWNLOADER v1.0"
$lblTitle.ForeColor = [System.Drawing.Color]::Lime
$lblTitle.Font      = New-Object System.Drawing.Font("Consolas", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location  = New-Object System.Drawing.Point(20, 15)
$lblTitle.Size      = New-Object System.Drawing.Size(760, 30)
$form.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text      = ":: CODENAME: CHURCH - VIDEO / AUDIO DOWNLOADER ::"
$lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 180, 0)
$lblSubtitle.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblSubtitle.Location  = New-Object System.Drawing.Point(20, 50)
$lblSubtitle.Size      = New-Object System.Drawing.Size(760, 18)
$form.Controls.Add($lblSubtitle)

# --- URL ---
$lblUrl = New-Object System.Windows.Forms.Label
$lblUrl.Text      = "URL VIDEO:"
$lblUrl.ForeColor = [System.Drawing.Color]::Lime
$lblUrl.Location  = New-Object System.Drawing.Point(20, 85)
$lblUrl.Size      = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($lblUrl)

$global:txtUrl = New-Object System.Windows.Forms.TextBox
$global:txtUrl.Location    = New-Object System.Drawing.Point(130, 82)
$global:txtUrl.Size        = New-Object System.Drawing.Size(650, 26)
$global:txtUrl.BackColor   = [System.Drawing.Color]::Black
$global:txtUrl.ForeColor   = [System.Drawing.Color]::Lime
$global:txtUrl.BorderStyle = "FixedSingle"
$global:txtUrl.PlaceholderText = "Trascina qui il link (https://...)"
$form.Controls.Add($global:txtUrl)

$form.Add_DragDrop({ $global:txtUrl.Text = $_.Data.GetData([Windows.Forms.DataFormats]::Text) })
$form.Add_DragEnter({ if($_.Data.GetDataPresent([Windows.Forms.DataFormats]::Text)){ $_.Effect = [Windows.Forms.DragDropEffects]::Copy } })

# --- GRUPPO IMPOSTAZIONI ---
$gbSettings = New-Object System.Windows.Forms.GroupBox
$gbSettings.Text      = "[ IMPOSTAZIONI ]"
$gbSettings.ForeColor = [System.Drawing.Color]::Lime
$gbSettings.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$gbSettings.Location  = New-Object System.Drawing.Point(20, 125)
$gbSettings.Size      = New-Object System.Drawing.Size(760, 160)
$form.Controls.Add($gbSettings)

# Formato
$lblFmt = New-Object System.Windows.Forms.Label
$lblFmt.Text = "Formato:"; $lblFmt.Location = "20,30"; $lblFmt.Size = "60,20"; $lblFmt.ForeColor = [System.Drawing.Color]::Lime
$gbSettings.Controls.Add($lblFmt)

$global:cmbFormat = New-Object System.Windows.Forms.ComboBox
$global:cmbFormat.Location = "90,28"; $global:cmbFormat.Size = "100,25"; $global:cmbFormat.DropDownStyle = "DropDownList"
$global:cmbFormat.BackColor = [System.Drawing.Color]::Black; $global:cmbFormat.ForeColor = [System.Drawing.Color]::Lime
$global:cmbFormat.Items.AddRange(@("mp4","mkv","mp3","flac")); $global:cmbFormat.SelectedIndex = 0
$gbSettings.Controls.Add($global:cmbFormat)

# Qualità
$lblQual = New-Object System.Windows.Forms.Label
$lblQual.Text = "Qualità:"; $lblQual.Location = "210,30"; $lblQual.Size = "60,20"; $lblQual.ForeColor = [System.Drawing.Color]::Lime
$gbSettings.Controls.Add($lblQual)

$global:cmbQuality = New-Object System.Windows.Forms.ComboBox
$global:cmbQuality.Location = "280,28"; $global:cmbQuality.Size = "100,25"; $global:cmbQuality.DropDownStyle = "DropDownList"
$global:cmbQuality.BackColor = [System.Drawing.Color]::Black; $global:cmbQuality.ForeColor = [System.Drawing.Color]::Lime
$global:cmbQuality.Items.AddRange(@("360p","720p","1080p","BEST")); $global:cmbQuality.SelectedIndex = 3
$gbSettings.Controls.Add($global:cmbQuality)

# Playlist
$global:radioSingle = New-Object System.Windows.Forms.RadioButton
$global:radioSingle.Text = "Video Singolo"; $global:radioSingle.Location = "420,28"; $global:radioSingle.Size = "120,20"
$global:radioSingle.Checked = $true; $global:radioSingle.ForeColor = [System.Drawing.Color]::Lime
$gbSettings.Controls.Add($global:radioSingle)

$global:radioPlaylist = New-Object System.Windows.Forms.RadioButton
$global:radioPlaylist.Text = "Intera Playlist"; $global:radioPlaylist.Location = "550,28"; $global:radioPlaylist.Size = "120,20"
$global:radioPlaylist.ForeColor = [System.Drawing.Color]::Lime
$gbSettings.Controls.Add($global:radioPlaylist)

# User-Agent
$lblUA = New-Object System.Windows.Forms.Label
$lblUA.Text = "User-Agent:"; $lblUA.Location = "20,70"; $lblUA.Size = "80,20"; $lblUA.ForeColor = [System.Drawing.Color]::Lime
$gbSettings.Controls.Add($lblUA)

$global:cmbUA = New-Object System.Windows.Forms.ComboBox
$global:cmbUA.Location = "110,68"; $global:cmbUA.Size = "200,25"; $global:cmbUA.DropDownStyle = "DropDownList"
$global:cmbUA.BackColor = [System.Drawing.Color]::Black; $global:cmbUA.ForeColor = [System.Drawing.Color]::Lime
$global:cmbUA.Items.AddRange(@("Default (Windows)","Mobile (iPhone)","Mobile (Android)","MacOS Safari")); $global:cmbUA.SelectedIndex = 0
$gbSettings.Controls.Add($global:cmbUA)

# Sottotitoli
$global:chkSubtitles = New-Object System.Windows.Forms.CheckBox
$global:chkSubtitles.Text = "Sottotitoli (.srt)"; $global:chkSubtitles.Location = "340,68"; $global:chkSubtitles.Size = "150,20"
$global:chkSubtitles.ForeColor = [System.Drawing.Color]::Lime; $global:chkSubtitles.BackColor = [System.Drawing.Color]::Black
$gbSettings.Controls.Add($global:chkSubtitles)

# JS Runtime
$global:chkJS = New-Object System.Windows.Forms.CheckBox
$global:chkJS.Text = "Attiva JS Runtime"; $global:chkJS.Location = "520,68"; $global:chkJS.Size = "150,20"
$global:chkJS.ForeColor = [System.Drawing.Color]::Lime; $global:chkJS.BackColor = [System.Drawing.Color]::Black
$global:chkJS.Checked = $true
$gbSettings.Controls.Add($global:chkJS)

# Cookies
$global:chkCookies = New-Object System.Windows.Forms.CheckBox
$global:chkCookies.Text = "Usa Cookies.txt"; $global:chkCookies.Location = "20,110"; $global:chkCookies.Size = "150,20"
$global:chkCookies.ForeColor = [System.Drawing.Color]::Lime; $global:chkCookies.BackColor = [System.Drawing.Color]::Black
$gbSettings.Controls.Add($global:chkCookies)

# Bypass
$global:chkBypass = New-Object System.Windows.Forms.CheckBox
$global:chkBypass.Text = "Bypass Protetto (Referer + cookies da browser)"; $global:chkBypass.Location = "190,110"; $global:chkBypass.Size = "350,20"
$global:chkBypass.ForeColor = [System.Drawing.Color]::Magenta; $global:chkBypass.BackColor = [System.Drawing.Color]::Black
$gbSettings.Controls.Add($global:chkBypass)

# --- PROGRESS BAR E LOG ---
$global:progressBar = New-Object System.Windows.Forms.ProgressBar
$global:progressBar.Location  = New-Object System.Drawing.Point(20, 300)
$global:progressBar.Size      = New-Object System.Drawing.Size(760, 20)
$global:progressBar.Minimum   = 0
$global:progressBar.Maximum   = 100
$global:progressBar.Value     = 0
$global:progressBar.Visible   = $false
$form.Controls.Add($global:progressBar)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "[ LOG DOWNLOAD ]"; $lblLog.Location = New-Object System.Drawing.Point(20, 330)
$lblLog.Size = New-Object System.Drawing.Size(200, 20); $lblLog.ForeColor = [System.Drawing.Color]::Lime
$lblLog.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblLog)

$global:txtLog = New-Object System.Windows.Forms.TextBox
$global:txtLog.Multiline    = $true
$global:txtLog.ScrollBars   = "Vertical"
$global:txtLog.ReadOnly     = $true
$global:txtLog.BackColor    = [System.Drawing.Color]::FromArgb(10, 10, 10)
$global:txtLog.ForeColor    = [System.Drawing.Color]::Lime
$global:txtLog.Font         = New-Object System.Drawing.Font("Consolas", 9)
$global:txtLog.Location     = New-Object System.Drawing.Point(20, 360)
$global:txtLog.Size         = New-Object System.Drawing.Size(760, 250)
$global:txtLog.BorderStyle  = "FixedSingle"
$form.Controls.Add($global:txtLog)

# --- PULSANTI AZIONE ---
$global:btnDownload = New-Object System.Windows.Forms.Button
$global:btnDownload.Text      = "▶  INIZIA DOWNLOAD"
$global:btnDownload.Location  = New-Object System.Drawing.Point(20, 630)
$global:btnDownload.Size      = New-Object System.Drawing.Size(600, 45)
$global:btnDownload.FlatStyle = "Flat"
$global:btnDownload.BackColor = [System.Drawing.Color]::Black
$global:btnDownload.ForeColor = [System.Drawing.Color]::Lime
$global:btnDownload.FlatAppearance.BorderColor = [System.Drawing.Color]::Lime
$global:btnDownload.FlatAppearance.BorderSize  = 2
$global:btnDownload.Font      = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($global:btnDownload)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text      = "EXIT"
$btnExit.Location  = New-Object System.Drawing.Point(640, 630)
$btnExit.Size      = New-Object System.Drawing.Size(140, 45)
$btnExit.FlatStyle = "Flat"
$btnExit.BackColor = [System.Drawing.Color]::Black
$btnExit.ForeColor = [System.Drawing.Color]::Red
$btnExit.FlatAppearance.BorderColor = [System.Drawing.Color]::Red
$btnExit.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$btnExit.Add_Click({ $form.Close() })
$form.Controls.Add($btnExit)

# --- STATUS BAR ---
$global:lblStatus = New-Object System.Windows.Forms.Label
$global:lblStatus.Text      = "> Pronto. Incolla un link e premi INIZIA DOWNLOAD."
$global:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 200, 0)
$global:lblStatus.Font      = New-Object System.Drawing.Font("Consolas", 9)
$global:lblStatus.Location  = New-Object System.Drawing.Point(20, 685)
$global:lblStatus.Size      = New-Object System.Drawing.Size(760, 20)
$form.Controls.Add($global:lblStatus)

function Update-StatusBar {
    param([string]$Text)
    $global:lblStatus.Text = "> $Text"
    $form.Refresh()
}

# ============================================================
# EVENTI E LOGICA DI AVVIO
# ============================================================
$global:btnDownload.Add_Click({
    $url = $global:txtUrl.Text.Trim()
    
    if ([string]::IsNullOrWhiteSpace($url)) {
        [System.Windows.Forms.MessageBox]::Show("Inserisci un URL valido!", "MATRIX - ATTENZIONE", "OK", "Warning") | Out-Null
        return
    }

    if ($url -notmatch '^https?://') {
        $url = "https://$url"
        $global:txtUrl.Text = $url
    }

    $format = $global:cmbFormat.SelectedItem.ToString()
    $quality = $global:cmbQuality.SelectedItem.ToString()
    $isPlaylist = $global:radioPlaylist.Checked
    $useCookiesFile = $global:chkCookies.Checked
    $useBrowserCookies = $global:chkBypass.Checked
    $embedSubtitles = $global:chkSubtitles.Checked
    $uaIndex = $global:cmbUA.SelectedIndex
    $useJsRuntime = $global:chkJS.Checked
    $bypass = $global:chkBypass.Checked

    Start-YtDlpDownload -Url $url `
                        -Format $format `
                        -Quality $quality `
                        -IsPlaylist $isPlaylist `
                        -UseCookiesFile $useCookiesFile `
                        -UseBrowserCookies $useBrowserCookies `
                        -EmbedSubtitles $embedSubtitles `
                        -UserAgentIndex $uaIndex `
                        -UseJsRuntime $useJsRuntime `
                        -BypassProtected $bypass
})

$global:cmbFormat.Add_SelectedIndexChanged({
    $selectedFormat = $global:cmbFormat.SelectedItem.ToString()
    if ($selectedFormat -match "mp3|flac") {
        $global:cmbQuality.Enabled = $false
        $global:cmbQuality.ForeColor = [System.Drawing.Color]::Gray
    } else {
        $global:cmbQuality.Enabled = $true
        $global:cmbQuality.ForeColor = [System.Drawing.Color]::Lime
    }
})

$form.Add_Load({
    Update-StatusBar "Inizializzazione..."
    
    # Forza il disegno della GUI prima di iniziare operazioni lunghe
    $form.Refresh()
    
    if (-not (Test-YtDlp)) {
        # 1. Segnala visivamente che sta scaricando
        $global:txtLog.AppendText("[WARN] yt-dlp non trovato. Download in corso da GitHub...`r`n")
        $global:txtLog.AppendText("[WARN] Attendere prego, potrebbe volerci qualche secondo.`r`n")
        Update-StatusBar "Download di yt-dlp in corso..."
        $global:btnDownload.Enabled = $false
        $global:btnDownload.Text = "ATTENDERE..."
        $global:btnDownload.ForeColor = [System.Drawing.Color]::Yellow
        
        # Forza il ridisegno per mostrare il messaggio
        $form.Refresh()
        
        if (Install-YtDlp) {
            $global:txtLog.AppendText("[OK] yt-dlp installato correttamente.`r`n")
            $global:btnDownload.Enabled = $true
            $global:btnDownload.Text = "▶  INIZIA DOWNLOAD"
            $global:btnDownload.ForeColor = [System.Drawing.Color]::Lime
        } else {
            $global:txtLog.AppendText("[ERROR] Impossibile installare yt-dlp. Il download non funzionera'.`r`n")
            $global:btnDownload.Enabled = $false
            $global:btnDownload.ForeColor = [System.Drawing.Color]::Gray
            $global:btnDownload.FlatAppearance.BorderColor = [System.Drawing.Color]::Gray
        }
    } else {
        $global:txtLog.AppendText("[OK] yt-dlp v$($global:ytdlpVersion) trovato.`r`n")
    }

    $global:txtLog.AppendText("[INFO] Log file: $(Split-Path $script:logFile -Leaf)`r`n")
    $global:txtLog.AppendText("[INFO] Cartella download: $global:downloadDir`r`n")
    $global:txtLog.AppendText("============================================================`r`n")
    
    Update-StatusBar "Pronto. Incolla un link e premi INIZIA DOWNLOAD."
})
[void]$form.ShowDialog()
