<#
  Protel R&A Importer - tek satirlik sunucu kurulumu.

  Dosyayi her sunucuya elle kopyalamak yerine bir kere bir yere koyup
  (Google Drive / dosya sunucusu / IIS / GitHub release) her sunucuda:

      powershell -ExecutionPolicy Bypass -File install.ps1 -Url "<INDIRME_LINKI>"

  ya da betigi de ayni yere koyduysaniz tek satir:

      powershell -ExecutionPolicy Bypass -Command "& { iwr -UseBasicParsing '<BETIK_LINKI>' | iex }"

  Parametreler:
      -Url        Zorunlu. RAImporter.exe'nin DOGRUDAN indirme adresi.
      -Sha256     Istege bagli. Beklenen SHA-256 ozeti; tutmazsa kurulum durur.
                  VERILMEZSE betik ozeti "<Url>.sha256" adresinden kendisi
                  almayi dener (GitHub release'te RAImporter.exe.sha256
                  asset'i). Talimattaki sablon metnini ("<...deger...>")
                  oldugu gibi yapistirmayin; betik bunu acikca reddeder.
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
# PS saglayicisini atlayan silme: bazi makinelerde yol kisa-ad ('~' iceren)
# gelir ve Remove-Item PSArgumentException verir (sahada goruldu, 31.08).
function TmpSil([string]$p) { try { [IO.File]::Delete($p) } catch { } }

Write-Host ""
Write-Host "  Protel R&A Importer - kurulum" -ForegroundColor Cyan
Write-Host "  ---------------------------------------------------------------"

# --- parametre sagligi ------------------------------------------------------
# Sahada goruldu (31.08): talimattaki "<RAImporter.exe.sha256 ... deger>"
# sablonu OLDUGU GIBI yapistirilmis, karsilastirma sablon metniyle yapilmisti.
if ($Sha256 -and $Sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    Bad "Sha256 gecerli bir ozet degil: $Sha256"
    Say "Gercek ozet, RAImporter.exe.sha256 dosyasinin ilk sozcugudur (64 hex)."
    Say "En kolayi: -Sha256'yi HIC vermeyin - betik ozeti su adresten kendisi alir:"
    Say "  $($Url).sha256"
    exit 1
}

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

# Ozet verilmediyse yayindaki kardes ".sha256" dosyasindan almayi dene.
if (-not $Sha256) {
    try {
        $wcH = New-Object Net.WebClient
        $wcH.Headers.Add("User-Agent", "RAImporter-Installer")
        $aday = (($wcH.DownloadString($Url + ".sha256")) -split '\s+')[0]
        if ($aday -match '^[0-9A-Fa-f]{64}$') {
            $Sha256 = $aday
            Ok "Beklenen ozet yayindan alindi: $($Url).sha256"
        }
    } catch {
        Say "Ozet dosyasina erisilemedi ($($Url).sha256);"
        Say "-Sha256 da verilmedigi icin dogrulama atlanacak."
    }
}

# Gecici dosya TEMP'e DEGIL kurulum klasorune iner: bazi makinelerde TEMP
# kisa-ad yoluyla gelir (orn. kullanici 'protel.user' -> C:\Users\PROTEL~1.USE)
# ve PowerShell 5.1'in Move/Remove-Item komutlari '~' iceren yolda
# PSArgumentException ile patlar (sahada goruldu, 31.08). Kurulum klasoru hep
# duz addir ve ayni diskte kalindigi icin son tasima da kopyasiz olur.
$tmp = Join-Path $Dir ("RAImporter-indirme-" + [guid]::NewGuid().ToString("N") + ".tmp")

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

$size = ([IO.FileInfo]$tmp).Length
if ($size -lt 1MB) {
    Bad "Inen dosya cok kucuk ($([math]::Round($size/1KB,1)) KB)."
    Say "Link muhtemelen dosyayi degil bir HTML sayfasini donduruyor."
    Say "Google Drive kullaniyorsaniz DOGRUDAN indirme adresini verin:"
    Say "  https://drive.google.com/uc?export=download&id=DOSYA_ID"
    Say "ve dosyanin 'Baglantiya sahip olan herkes' ile paylasildigindan emin olun."
    TmpSil $tmp
    exit 1
}

# Gercekten bir Windows programi mi? (Drive'in uyari sayfasi HTML doner)
$head = [IO.File]::ReadAllBytes($tmp)[0..1]
if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A) {
    Bad "Inen dosya bir Windows programi degil (MZ imzasi yok)."
    Say "Link bir onay/uyari sayfasi donduruyor olabilir. Dosyayi tarayicidan bir kere"
    Say "indirip dogrudan indirme adresini kontrol edin."
    TmpSil $tmp
    exit 1
}
Ok "Indirildi: $([math]::Round($size/1MB,1)) MB"

# --- dogrulama --------------------------------------------------------------
$hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToUpper()
if ($Sha256) {
    if ($hash -ne $Sha256.ToUpper()) {
        Bad "SHA-256 tutmuyor - dosya bozuk ya da beklenen surum degil."
        Say "beklenen : $($Sha256.ToUpper())"
        Say "inen     : $hash"
        TmpSil $tmp
        exit 1
    }
    Ok "SHA-256 dogrulandi"
} else {
    Say "SHA-256 verilmedi, dogrulama atlandi. Inen dosyanin ozeti:"
    Say "  $hash"
}

# PS saglayicisini atlayan .NET tasima (Move-Item '~' iceren yollarda patlar).
try {
    [IO.File]::Copy($tmp, $exe, $true)
    TmpSil $tmp
} catch {
    Bad "Dosya yerine konamadi: $($_.Exception.Message)"
    Say "Hedef: $exe - eski surum hala acik olabilir; kapatip tekrar deneyin."
    TmpSil $tmp
    exit 1
}
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
