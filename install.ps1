<#
  Protel R&A Importer - tek satirlik sunucu kurulumu.

  Dosyayi her sunucuya elle kopyalamak yerine bir kere bir yere koyup
  (Google Drive / dosya sunucusu / IIS / GitHub release) her sunucuda:

      powershell -ExecutionPolicy Bypass -File install.ps1 -Url "<INDIRME_LINKI>"

  ya da betigi de ayni yere koyduysaniz tek satir:

      powershell -ExecutionPolicy Bypass -Command "& { iwr -UseBasicParsing '<BETIK_LINKI>' | iex }"

  Parametreler:
      -Url        Zorunlu. RAImporter.exe'nin DOGRUDAN indirme adresi.
      -Sha256     Onerilir. Dosyanin beklenen SHA-256 ozeti; tutmazsa kurulum durur.
      -Dir        Kurulum klasoru (varsayilan D:\Protel\RAImporter, D: yoksa C:).
      -UpdateUrl  surum.json adresi. Verilirse otel bir daha elle guncellenmez:
                  kurulum bu adresi yazar, program gece penceresinde kendi gecer.
      -Service    Indirdikten sonra Windows servisi olarak kur ve baslat.
      -Open       Kurulumdan sonra yonetim arayuzunu tarayicida ac.

  Google Drive linki nasil dogrudan indirme olur:
      Paylasim linki : https://drive.google.com/file/d/DOSYA_ID/view?usp=sharing
      Indirme linki  : https://drive.google.com/uc?export=download^&id=DOSYA_ID
      (Dosyanin "Baglantiya sahip olan herkes" olarak paylasilmasi gerekir.)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Sha256 = "",
    [string]$Dir = "",
    [string]$UpdateUrl = "",
    [switch]$Service,
    [switch]$Open
)

$ErrorActionPreference = "Stop"

function Say([string]$msg, [string]$color = "Gray") { Write-Host "  $msg" -ForegroundColor $color }
function Ok ([string]$msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Bad([string]$msg) { Write-Host "  [HATA] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  Protel R&A Importer - kurulum" -ForegroundColor Cyan
Write-Host "  ---------------------------------------------------------------"

# --- hedef klasor -----------------------------------------------------------
if (-not $Dir) {
    $Dir = if (Test-Path "D:\") { "D:\Protel\RAImporter" } else { "C:\Protel\RAImporter" }
}
$exe = Join-Path $Dir "RAImporter.exe"

# Eski surum calisiyorsa once durdur
$running = Get-Process -Name "RAImporter" -ErrorAction SilentlyContinue
if ($running) {
    Say "Calisan RAImporter bulundu, durduruluyor..."
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}
$svc = Get-Service -Name "ProtelRAImporter" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Say "Servis calisiyor, durduruluyor..."
    Stop-Service -Name "ProtelRAImporter" -Force
    Start-Sleep -Seconds 2
}

New-Item -ItemType Directory -Path $Dir -Force | Out-Null
Ok "Klasor hazir: $Dir"

# --- indirme ----------------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tmp = Join-Path $env:TEMP ("RAImporter-" + [guid]::NewGuid().ToString("N") + ".tmp")

Say "Indiriliyor: $Url"
try {
    $wc = New-Object Net.WebClient
    $wc.Headers.Add("User-Agent", "RAImporter-Installer")
    $wc.DownloadFile($Url, $tmp)
} catch {
    Bad "Indirme basarisiz: $($_.Exception.Message)"
    Say "Sunucudan bu adrese erisilebildiginden emin olun (proxy / guvenlik duvari)."
    exit 1
}

$size = (Get-Item $tmp).Length
if ($size -lt 1MB) {
    Bad "Inen dosya cok kucuk ($([math]::Round($size/1KB,1)) KB)."
    Say "Link muhtemelen dosyayi degil bir HTML sayfasini donduruyor."
    Say "Google Drive kullaniyorsaniz DOGRUDAN indirme adresini verin:"
    Say "  https://drive.google.com/uc?export=download&id=DOSYA_ID"
    Say "ve dosyanin 'Baglantiya sahip olan herkes' ile paylasildigindan emin olun."
    Remove-Item $tmp -Force
    exit 1
}

# Gercekten bir Windows programi mi? (Drive'in uyari sayfasi HTML doner)
$head = [IO.File]::ReadAllBytes($tmp)[0..1]
if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A) {
    Bad "Inen dosya bir Windows programi degil (MZ imzasi yok)."
    Say "Link bir onay/uyari sayfasi donduruyor olabilir. Dosyayi tarayicidan bir kere"
    Say "indirip dogrudan indirme adresini kontrol edin."
    Remove-Item $tmp -Force
    exit 1
}
Ok "Indirildi: $([math]::Round($size/1MB,1)) MB"

# --- dogrulama --------------------------------------------------------------
$hash = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToUpper()
if ($Sha256) {
    if ($hash -ne $Sha256.ToUpper()) {
        Bad "SHA-256 tutmuyor - dosya bozuk ya da beklenen surum degil."
        Say "beklenen : $($Sha256.ToUpper())"
        Say "inen     : $hash"
        Remove-Item $tmp -Force
        exit 1
    }
    Ok "SHA-256 dogrulandi"
} else {
    Say "SHA-256 verilmedi, dogrulama atlandi. Inen dosyanin ozeti:"
    Say "  $hash"
}

Move-Item -Path $tmp -Destination $exe -Force
Ok "Kuruldu: $exe"

# --- surum ------------------------------------------------------------------
try {
    $v = (Get-Item $exe).VersionInfo.ProductVersion
    if ($v) { Ok "Surum: $v" }
} catch { }

# --- merkezi guncelleme adresi ----------------------------------------------
# Bunu simdi yazarsak otele bir daha girmek gerekmez: yeni surumleri program
# kendisi alir. Var olan ayarlara DOKUNMAZ, sadece update bolumunu yazar.
if ($UpdateUrl) {
    try {
        $dataDir = Join-Path $env:ProgramData "Protel\RAImporter"
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        $cfgPath = Join-Path $dataDir "config.json"
        if (Test-Path $cfgPath) {
            $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Copy-Item $cfgPath "$cfgPath.bak" -Force
        } else {
            $cfg = [pscustomobject]@{}
        }
        $upd = [pscustomobject]@{
            enabled      = $true
            manifest_url = $UpdateUrl
            window_start = "02:00"
            window_end   = "05:00"
        }
        if ($cfg.PSObject.Properties.Name -contains "update") { $cfg.update = $upd }
        else { $cfg | Add-Member -NotePropertyName update -NotePropertyValue $upd }
        # BOM'suz UTF-8: Set-Content -Encoding UTF8 (PowerShell 5.1) dosyanin
        # basina BOM koyar; bazi okuyucular icin bu bozuk dosya demektir.
        $json = $cfg | ConvertTo-Json -Depth 12
        [IO.File]::WriteAllText($cfgPath, $json, (New-Object Text.UTF8Encoding($false)))
        Ok "Guncelleme adresi yazildi: $UpdateUrl"
        Say "  Pencere: 02:00-05:00, aktarim calisirken guncelleme yapilmaz."
    } catch {
        Bad "Guncelleme adresi yazilamadi: $($_.Exception.Message)"
        Say "Arayuz > Guncelleme bolumunden elle girebilirsiniz."
    }
}

# --- servis -----------------------------------------------------------------
if ($Service) {
    $admin = ([Security.Principal.WindowsPrincipal] `
              [Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        Bad "Servis kurulumu yonetici hakki gerektiriyor."
        Say "PowerShell'i 'Yonetici olarak calistir' ile acip tekrar deneyin."
    } else {
        Say "Windows servisi kuruluyor..."
        & $exe install-service
        if ($LASTEXITCODE -eq 0) { Ok "Servis kuruldu ve baslatildi" }
        else { Bad "Servis kurulumu basarisiz (cikis kodu $LASTEXITCODE)" }
    }
}

# --- kisayol ----------------------------------------------------------------
try {
    $lnk = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Protel R&A Importer.lnk"
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $exe
    $s.WorkingDirectory = $Dir
    $s.IconLocation = "$exe,0"
    $s.Description = "Oracle Cloud R&A Excel -> Oracle aktarimi"
    $s.Save()
    Ok "Masaustu kisayolu olusturuldu"
} catch {
    Say "Kisayol olusturulamadi (onemli degil): $($_.Exception.Message)"
}

Write-Host "  ---------------------------------------------------------------"
Write-Host "  Kurulum tamam." -ForegroundColor Green
Write-Host ""
Say "Simdi ne yapmali:"
Say "  1. $exe dosyasini calistirin"
Say "  2. Tarayicida acilan arayuzde: Veritabani -> Kaynak -> Eslesmeler -> Kaydet"
Say "  3. 'Deneme calistir' ile dogrulayin"
Say "  4. Kalici calismasi icin: $exe install-service   (yonetici)"
Say ""
Say "Kurulumu dogrulamak icin (gercek DB'ye karsi uctan uca test):"
Say "  $exe selftest"
Write-Host ""

if ($Open) {
    Start-Process $exe
    Start-Sleep -Seconds 6
    Start-Process "http://127.0.0.1:8787/"
}
