<#
  Protel R&A Importer - tek satirlik sunucu kurulumu.

  Onerilen kullanim -- TEK SATIR, cmd ve PowerShell'de ayni (surumden bagimsiz;
  guncel paketi surum.json'dan bulur). Bastaki [Net.ServicePointManager] kismi
  SART: Windows Server 2016'daki PowerShell 5.1 varsayilan TLS 1.0 kullanir,
  GitHub reddeder ("Could not create SSL/TLS secure channel", 18.09 The Marmara):

      powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; try { iwr -UseBasicParsing 'https://raw.githubusercontent.com/alperenkurbanoglu10/raimporter-dagitim/main/install.ps1' -OutFile 'C:\Windows\Temp\install.ps1' -ErrorAction Stop; & 'C:\Windows\Temp\install.ps1' -UpdateUrl 'https://raw.githubusercontent.com/alperenkurbanoglu10/raimporter-dagitim/main/surum.json' -Service } catch { throw }"

  Dosyayi kendi yerinizden (Google Drive / dosya sunucusu / IIS) dagitiyorsaniz:

      powershell -ExecutionPolicy Bypass -File install.ps1 -Url "<INDIRME_LINKI>"

  Parametreler:
      -Url        Istege bagli. Paketin (RAImporter-<surum>-win64.zip) ya da tek
                  dosya exe'nin DOGRUDAN indirme adresi. VERILMEZSE guncel paket
                  surum.json'dan bulunur (paket_url + paket_sha256): -UpdateUrl
                  verildiyse o adresten, yoksa dagitim deposundan.
                  DIKKAT: 08.09'dan beri release'te RAImporter.exe YOK; eski
                  ".../releases/latest/download/RAImporter.exe" adresi 404 doner.
      -Sha256     Istege bagli. Beklenen SHA-256 ozeti; tutmazsa kurulum durur.
                  VERILMEZSE: -Url yoksa surum.json'daki ozet, -Url varsa
                  "<Url>.sha256" adresi (GitHub release'teki kardes asset)
                  kullanilir. Talimattaki sablon metnini ("<...deger...>")
                  oldugu gibi yapistirmayin; betik bunu acikca reddeder.
      -Dir        Kurulum klasoru. VERILMEZSE betik dogru yeri KENDISI bulur:
                  once VAR OLAN kurulum (servis kaydi / calisan program / bilinen
                  klasorler) -- yukseltme hep oraya gider; yoksa sistem diski
                  disindaki ilk yazilabilir sabit veri diski (gelenek D:, sonra
                  en cok bos alanli); o da yoksa sistem diski. Takili DVD, USB ve
                  ag surucusu listeye hic girmez.
      -UpdateUrl  surum.json adresi. Verilirse config'e yazilir: otel bir daha
                  elle guncellenmez, program gece penceresinde kendi gecer.
      -Service    Kurduktan sonra Windows servisi olarak kur ve baslat.
      -Open       Kurulumdan sonra programi ac (servisi kurar/baslatir, arayuzu acar).

  Google Drive linki nasil dogrudan indirme olur:
      Paylasim linki : https://drive.google.com/file/d/DOSYA_ID/view?usp=sharing
      Indirme linki  : https://drive.google.com/uc?export=download^&id=DOSYA_ID
      (Dosyanin "Baglantiya sahip olan herkes" olarak paylasilmasi gerekir.)
#>

[CmdletBinding()]
param(
    [string]$Url = "",
    [string]$Sha256 = "",
    [string]$Dir = "",
    [string]$UpdateUrl = "",
    [switch]$Service,
    [switch]$Open
)

$ErrorActionPreference = "Stop"
$VarsayilanManifest = "https://raw.githubusercontent.com/alperenkurbanoglu10/raimporter-dagitim/main/surum.json"

function Say([string]$msg, [string]$color = "Gray") { Write-Host "  $msg" -ForegroundColor $color }
function Ok ([string]$msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Bad([string]$msg) { Write-Host "  [HATA] $msg" -ForegroundColor Red }
# PS saglayicisini atlayan silme: bazi makinelerde yol kisa-ad ('~' iceren)
# gelir ve Remove-Item PSArgumentException verir (sahada goruldu, 31.08).
function TmpSil([string]$p) { try { [IO.File]::Delete($p) } catch { } }

# Kurulum icin disk sirasi: once sistem diski DISINDAKI sabit veri diskleri
# (gelenek D:, sonra en cok bos alani olan), en sonda sistem diski. Takili DVD
# (17.09 sahada D: = CDRom/UDF, "Access to the path 'Protel' is denied"), USB
# ve ag surucusu listeye hic girmez; NTFS/ReFS disi bicimler (FAT32 USB, bulut
# senkron surucusu) de elenir. WMI/CIM kapali sunucularda da calissin diye
# IO.DriveInfo ile bakilir.
function SurucuSirasi {
    $sistem = "$env:SystemDrive"
    if (-not $sistem) { $sistem = "C:" }
    $veri = @()
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $d.IsReady) { continue }
            if ($d.DriveType -ne [IO.DriveType]::Fixed) { continue }
            if (@("NTFS", "ReFS") -notcontains $d.DriveFormat) { continue }
            $harf = $d.Name.Substring(0, 2)
            if ($harf -eq $sistem) { continue }
            if ($d.AvailableFreeSpace -lt 1GB) { continue }
            $veri += New-Object psobject -Property @{ Harf = $harf; Bos = [double]$d.AvailableFreeSpace }
        } catch { }
    }
    $sirali = $veri | Sort-Object @{ Expression = { if ($_.Harf -eq "D:") { 0 } else { 1 } } },
                                  @{ Expression = { $_.Bos }; Descending = $true }
    return @(@($sirali | ForEach-Object { $_.Harf }) + @($sistem))
}

# "C:\Protel\RAImporter\RAImporter.exe" --service  ->  C:\...\RAImporter.exe
function ExeYolunuAyikla([string]$komut) {
    $k = ([string]$komut).Trim()
    if (-not $k) { return "" }
    if ($k.StartsWith([char]34)) {
        $son = $k.IndexOf([char]34, 1)
        if ($son -gt 1) { return $k.Substring(1, $son - 1) }
        return ""
    }
    $i = $k.IndexOf(".exe", [StringComparison]::OrdinalIgnoreCase)
    if ($i -gt 0) { return $k.Substring(0, $i + 4) }
    return ($k -split ' ')[0]
}

# VAR OLAN kurulumu bulur. Yukseltme HER ZAMAN mevcut klasore gitmeli: yoksa
# ikinci bir kurulum dogar, otel iki ayri surum ve iki zamanlayici kosturur
# (10.09 ADBRI: ayni dosya iki kez islendi). Sira: servis kaydi (en guvenilir),
# calisan program, sonra disk sirasindaki bilinen klasorler.
function VarOlanKurulum {
    $komut = ""
    try {
        $kayit = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\ProtelRAImporter" -ErrorAction Stop
        $komut = [string]$kayit.ImagePath
    } catch { }
    if (-not $komut) {
        try {
            $svc = Get-CimInstance Win32_Service -Filter "Name='ProtelRAImporter'" -ErrorAction Stop
            $komut = [string]$svc.PathName
        } catch { }
    }
    $yol = ExeYolunuAyikla $komut
    if ($yol -and [IO.File]::Exists($yol)) {
        return @{ Yol = [IO.Path]::GetDirectoryName($yol); Sebep = "var olan kurulum, servis"; Kesin = $true }
    }
    try {
        $pr = Get-Process -Name "RAImporter" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pr -and $pr.Path) {
            return @{ Yol = [IO.Path]::GetDirectoryName($pr.Path); Sebep = "var olan kurulum, calisan program"; Kesin = $true }
        }
    } catch { }
    foreach ($harf in (SurucuSirasi)) {
        $aday = $harf + "\Protel\RAImporter"
        if ([IO.File]::Exists([IO.Path]::Combine($aday, "RAImporter.exe"))) {
            return @{ Yol = $aday; Sebep = "var olan kurulum, $harf"; Kesin = $true }
        }
    }
    return $null
}

# Denenecek klasorler, sirayla. "Kesin" aday tutmazsa BASKA yere kurmayiz: var
# olan kurulumun ya da -Dir'in yerine sessizce ikinci kurulum acmak, izin
# sorununu duzeltmekten kotu bir sonuctur.
function KurulumAdaylari {
    $mevcut = VarOlanKurulum
    if ($mevcut) { return @($mevcut) }
    $liste = @()
    # @(...) SART: tek diskli makinede PowerShell diziyi duz metne cevirir
    # ve $sira[0] harf yerine ilk KARAKTERI verir ("C" -> C\Protel\...).
    $sira = @(SurucuSirasi)
    for ($i = 0; $i -lt $sira.Count; $i++) {
        # Listenin SONUNCUSU her zaman sistem diskidir (SurucuSirasi); logda
        # "veri diski C:" yazmamasi icin etiketi ayri.
        $etiket = if ($i -eq $sira.Count - 1) { "sistem diski " + $sira[$i] } else { "veri diski " + $sira[$i] }
        $liste += @{ Yol = ($sira[$i] + "\Protel\RAImporter"); Sebep = $etiket; Kesin = $false }
    }
    return $liste
}

# Klasoru olusturmayi VE icine yazmayi dener: kok dizinde klasor acabilip
# dosya yazamayan sunucular var, bunu kurulumun ortasinda degil basinda
# ogrenmek isteriz. Basariliysa "" doner, olmadiysa hata metnini dondurur.
function KlasorDene([string]$yol) {
    try {
        New-Item -ItemType Directory -Path $yol -Force -ErrorAction Stop | Out-Null
        $deneme = Join-Path $yol ("yazma-denemesi-" + [guid]::NewGuid().ToString("N") + ".tmp")
        [IO.File]::WriteAllText($deneme, "x")
        [IO.File]::Delete($deneme)
        return ""
    } catch { return $_.Exception.Message }
}

# Tasima/kopyalama ilk denemede olmayabilir: yeni acilmis dosyalari antivirus
# tariyorsa (Trend Micro vb.) klasor kisa sure kilitli kalir ve "Access to the
# path ... is denied" gelir (16.09 sahada goruldu: acilan paket klasorunun
# _internal'i). Birkac kez denenir, olmazsa dosya dosya kopyalanir.
function KlasorTasi([string]$kaynak, [string]$hedef) {
    for ($i = 1; $i -le 5; $i++) {
        try { Move-Item -LiteralPath $kaynak -Destination $hedef -Force -ErrorAction Stop; return $true }
        catch { if ($i -lt 5) { Start-Sleep -Seconds 2 } }
    }
    try {
        New-Item -ItemType Directory -Path $hedef -Force -ErrorAction Stop | Out-Null
        Copy-Item -LiteralPath (Join-Path $kaynak "*") -Destination $hedef -Recurse -Force -ErrorAction Stop
        return $true
    } catch { return $false }
}
function DosyaKopyala([string]$kaynak, [string]$hedef) {
    for ($i = 1; $i -le 5; $i++) {
        try { [IO.File]::Copy($kaynak, $hedef, $true); return $true }
        catch { if ($i -lt 5) { Start-Sleep -Seconds 2 } }
    }
    return $false
}

# Indirme yardimcisi ($dosya bos ise metni dondurur). GitHub 404'ten sonra
# baglantiyi kapatiyor; .NET Framework WebClient o baglantiyi yeniden
# kullaninca gercek hata yerine "The request was aborted: The connection was
# closed unexpectedly" gorunuyor (14.09 sahada: adres eskiydi, ileti ag sorunu
# sandirdi). Baglanti koptuysa havuzu bosaltip BIR kez daha deneriz; ikinci
# deneme gercek HTTP durumunu verir.
function WebAl([string]$adres, [string]$dosya = "") {
    for ($deneme = 1; ; $deneme++) {
        try {
            $w = New-Object Net.WebClient
            $w.Headers.Add("User-Agent", "RAImporter-Installer")
            if ($dosya) { $w.DownloadFile($adres, $dosya); return }
            return $w.DownloadString($adres)
        } catch {
            $we = $_.Exception
            while ($we -and -not ($we -is [Net.WebException])) { $we = $we.InnerException }
            if (-not $we) { throw }
            if ($we.Status -eq [Net.WebExceptionStatus]::ProtocolError -and $we.Response) {
                throw ("HTTP {0} ({1}): {2}" -f [int]$we.Response.StatusCode,
                       $we.Response.StatusDescription, $adres)
            }
            $kopma = @([Net.WebExceptionStatus]::ConnectionClosed,
                       [Net.WebExceptionStatus]::KeepAliveFailure,
                       [Net.WebExceptionStatus]::ReceiveFailure,
                       [Net.WebExceptionStatus]::RequestCanceled)
            if ($deneme -lt 2 -and $kopma -contains $we.Status) {
                try { [Net.ServicePointManager]::FindServicePoint([uri]$adres).CloseConnectionGroup("") | Out-Null } catch { }
                continue
            }
            throw ("{0} [{1}]: {2}" -f $we.Message, $we.Status, $adres)
        }
    }
}

Write-Host ""
Write-Host "  Protel R&A Importer - kurulum" -ForegroundColor Cyan
Write-Host "  ---------------------------------------------------------------"

# --- parametre sagligi ------------------------------------------------------
# Sahada goruldu (31.08): talimattaki "<RAImporter.exe.sha256 ... deger>"
# sablonu OLDUGU GIBI yapistirilmis, karsilastirma sablon metniyle yapilmisti.
if ($Sha256 -and $Sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    Bad "Sha256 gecerli bir ozet degil: $Sha256"
    Say "Gercek ozet, .sha256 dosyasinin ilk sozcugudur (64 hex)."
    Say "En kolayi: -Sha256'yi HIC vermeyin - betik ozeti yayindan kendisi alir."
    exit 1
}

# --- yonetici hakki ---------------------------------------------------------
# Servis kurulumu yonetici ister ve bu eskiden EN SONDA anlasiliyordu: paket
# inip dosyalar degistikten sonra "yonetici hakki gerekiyor" deniyordu.
$yonetici = ([Security.Principal.WindowsPrincipal] `
             [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Service -and -not $yonetici) {
    Bad "-Service verildi ama bu PowerShell yonetici degil."
    Say "Baslat menusunde Windows PowerShell'e sag tiklayip 'Yonetici olarak"
    Say "calistir' deyin ve ayni komutu tekrarlayin."
    exit 1
}

# --- hedef klasor -----------------------------------------------------------
# Uzman her sunucuda elle karar vermesin: dogru yeri betik bulur (bkz.
# KurulumAdaylari). Denenen her aday gercekten olusturulur ve icine yazilir --
# 17.09 sahada D: VARDI ama takili bir DVD idi, kurulum ham bir .NET hatasiyla
# ("Access to the path 'Protel' is denied") ilk adimda bitiyordu.
$dirVerildi = [bool]$Dir
if ($dirVerildi) { $adaylar = @(@{ Yol = $Dir; Sebep = "-Dir ile verildi"; Kesin = $true }) }
else             { $adaylar = KurulumAdaylari }

$Dir = ""; $sebep = ""; $hata = ""; $sonAday = $null
foreach ($aday in $adaylar) {
    $sonAday = $aday
    $h = KlasorDene $aday.Yol
    if (-not $h) { $Dir = $aday.Yol; $sebep = $aday.Sebep; break }
    $hata = $h
    if ($aday.Kesin) { break }
    Say ("{0} kullanilamadi ({1})" -f $aday.Yol, $h)
}

if (-not $Dir) {
    Bad "Kurulum klasoru olusturulamadi: $($sonAday.Yol)"
    Say "Sebep: $hata"
    $kok = ""
    try { $kok = [IO.Path]::GetPathRoot($sonAday.Yol) } catch { }
    if ($sonAday.Sebep -like "var olan kurulum*") {
        Say "Kurulum zaten burada ($($sonAday.Sebep)) ama klasore yazilamiyor."
        Say "Program acik olabilir; servisi durdurup tekrar deneyin:"
        Say "  sc stop ProtelRAImporter"
    } elseif ($kok -and -not (Test-Path $kok)) {
        Say "$kok surucusu bu makinede yok ya da hazir degil."
    } elseif (-not $yonetici) {
        Say "Bu PowerShell yonetici DEGIL. Baslat menusunde Windows PowerShell'e"
        Say "sag tiklayip 'Yonetici olarak calistir' deyin ve komutu tekrarlayin."
    } else {
        Say "Oturum yonetici; o halde diskin kendisi yazmiyor: surucu salt-okunur"
        Say "olabilir ya da guvenlik yazilimi (Trend Micro vb.) kok dizini koruyor."
    }
    Say "Kurulum yerini elle vermek icin -Dir kullanin, ornegin:"
    Say ("  -Dir " + $env:SystemDrive + "\Protel\RAImporter")
    exit 1
}
$exe = Join-Path $Dir "RAImporter.exe"
Ok "Klasor hazir: $Dir ($sebep)"

# -bor: TLS 1.2'yi EKLER, digerlerini kapatmaz (isletim sistemi TLS 1.3 sunuyorsa o da kalir).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- ne kurulacak -----------------------------------------------------------
# -Url verilmediyse guncel paket surum.json'dan bulunur; surumden bagimsiz tek
# komut budur. 08.09'dan beri release'te RAImporter.exe yok (tek klasor zip
# paketi); talimatlardaki eski ".../releases/latest/download/RAImporter.exe"
# adresi 404 donuyordu (14.09 sahada goruldu).
if (-not $Url) {
    $mAdres = if ($UpdateUrl) { $UpdateUrl } else { $VarsayilanManifest }
    try {
        $m = (WebAl $mAdres) | ConvertFrom-Json
    } catch {
        Bad "Surum bilgisi okunamadi: $($_.Exception.Message)"
        Say "Sunucudan bu adrese erisilebildiginden emin olun (proxy / guvenlik duvari)"
        Say "ya da -Url ile paketin indirme adresini verin."
        exit 1
    }
    if ($m.paket_url) { $Url = [string]$m.paket_url; $mOzet = [string]$m.paket_sha256 }
    else              { $Url = [string]$m.url;       $mOzet = [string]$m.sha256 }
    if (-not $Url) { Bad "surum.json'da indirme adresi yok: $mAdres"; exit 1 }
    if (-not $Sha256 -and $mOzet -match '^[0-9A-Fa-f]{64}$') { $Sha256 = $mOzet }
    Ok "Guncel surum: $($m.version) (surum.json)"
}

# Ozet hala yoksa yayindaki kardes ".sha256" dosyasindan almayi dene.
if (-not $Sha256) {
    try {
        $aday = ((WebAl ($Url + ".sha256")) -split '\s+')[0]
        if ($aday -match '^[0-9A-Fa-f]{64}$') {
            $Sha256 = $aday
            Ok "Beklenen ozet yayindan alindi: $($Url).sha256"
        }
    } catch {
        Say "Ozet dosyasina erisilemedi ($($_.Exception.Message));"
        Say "-Sha256 da verilmedigi icin dogrulama atlanacak."
    }
}

# --- indirme ----------------------------------------------------------------
# Gecici dosya TEMP'e DEGIL kurulum klasorune iner: bazi makinelerde TEMP
# kisa-ad yoluyla gelir (orn. kullanici 'protel.user' -> C:\Users\PROTEL~1.USE)
# ve PowerShell 5.1'in Move/Remove-Item komutlari '~' iceren yolda
# PSArgumentException ile patlar (sahada goruldu, 31.08). Kurulum klasoru hep
# duz addir ve ayni diskte kalindigi icin son tasima da kopyasiz olur.
$tmp = Join-Path $Dir ("RAImporter-indirme-" + [guid]::NewGuid().ToString("N") + ".tmp")

Say "Indiriliyor: $Url"
try {
    WebAl $Url $tmp
} catch {
    TmpSil $tmp
    Bad "Indirme basarisiz: $($_.Exception.Message)"
    if ($_.Exception.Message -like "HTTP 404*") {
        Say "Bu adreste dosya yok. Adres eski olabilir: 08.09'dan beri yayin"
        Say "RAImporter-<surum>-win64.zip paketidir, RAImporter.exe degil."
        Say "En kolayi: -Url vermeyin; betik guncel paketi surum.json'dan bulur."
    } else {
        Say "Sunucudan bu adrese erisilebildiginden emin olun (proxy / guvenlik duvari)."
    }
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

# Gercekten bir Windows programi ya da zip paketi mi? (Drive'in uyari
# sayfasi HTML doner). 08.09'dan itibaren dagitim TEK KLASOR zip paketidir
# (RAImporter.exe + _internal\); tek dosya exe de kurulabilir (eski surumler).
$head = [IO.File]::ReadAllBytes($tmp)[0..1]
$paketMi = ($head[0] -eq 0x50 -and $head[1] -eq 0x4B)       # "PK" = zip
if (-not $paketMi -and ($head[0] -ne 0x4D -or $head[1] -ne 0x5A)) {
    Bad "Inen dosya ne Windows programi (MZ) ne zip paketi (PK)."
    Say "Link bir onay/uyari sayfasi donduruyor olabilir. Dosyayi tarayicidan bir kere"
    Say "indirip dogrudan indirme adresini kontrol edin."
    TmpSil $tmp
    exit 1
}
Ok ("Indirildi: $([math]::Round($size/1MB,1)) MB" + $(if ($paketMi) { " (tek klasor paketi)" } else { "" }))

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

# --- calisan surumu durdur --------------------------------------------------
# Indirme ve dogrulama BITTIKTEN sonra: indirme yarida kalirsa calisan kurulum
# hic durdurulmamis olur. Once servis (duzgun kapanis), sonra kalan surecler.
# DURUMU HATIRLIYORUZ: kurulum bitince geri baslatilmazsa surum yukseltmesi
# "guncelleme yapildi ama servis kapali kaldi" olarak geri doner. -Service
# verilmeden yapilan yukseltmeler de bu yoldan gecer.
$svcCalisiyordu = $false
$svc = Get-Service -Name "ProtelRAImporter" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Say "Servis calisiyor, durduruluyor..."
    $svcCalisiyordu = $true
    Stop-Service -Name "ProtelRAImporter" -Force
    try { $svc.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(60)) }
    catch { Say "Servis 60 saniyede durmadi; yine de devam ediliyor." }
}
$running = Get-Process -Name "RAImporter" -ErrorAction SilentlyContinue
if ($running) {
    Say "Calisan RAImporter bulundu, durduruluyor..."
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# --- yerine koyma -----------------------------------------------------------
if ($paketMi) {
    # Zip paketi: gecici klasore ac, exe + _internal'i yerine koy. Eski
    # _internal (varsa) once kenara alinir; kopyalama bittikten sonra silinir.
    $acilan = Join-Path $Dir ("RAImporter-paket-" + [guid]::NewGuid().ToString("N"))
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($tmp, $acilan)
        $kaynakExe = Join-Path $acilan "RAImporter.exe"
        if (-not (Test-Path $kaynakExe)) {
            # Paket kok klasorlu olabilir (RAImporter\RAImporter.exe)
            $alt = Get-ChildItem $acilan -Directory | Select-Object -First 1
            if ($alt -and (Test-Path (Join-Path $alt.FullName "RAImporter.exe"))) { $acilan = $alt.FullName; $kaynakExe = Join-Path $acilan "RAImporter.exe" }
        }
        if (-not (Test-Path $kaynakExe) -or -not (Test-Path (Join-Path $acilan "_internal"))) {
            Bad "Paket beklenen yapida degil (RAImporter.exe ve _internal\ bulunmali)."
            TmpSil $tmp; Remove-Item $acilan -Recurse -Force -ErrorAction SilentlyContinue
            exit 1
        }
        # SIRA ONEMLI (16.09 saha): once yeni exe YEDEK ADLA kopyalanir, sonra
        # _internal yerine konur, en son exe degistirilir. Eskiden exe once
        # kopyalaniyordu; _internal tasinamayinca kurulum "yeni exe + _internal
        # YOK" halinde kaliyordu ve program hic acilmiyordu. Artik bir adim
        # duserse eski surum geri alinir, kurulum CALISIR kalir.
        $eskiIc = Join-Path $Dir "_internal"
        $yedekIc = "$eskiIc.old"
        $yeniExe = "$exe.yeni"
        if (-not (DosyaKopyala $kaynakExe $yeniExe)) {
            Bad "Yeni RAImporter.exe kurulum klasorune kopyalanamadi."
            Say "Hedef: $Dir - klasor yazilabilir mi, antivirus engelliyor mu?"
            TmpSil $tmp; Remove-Item $acilan -Recurse -Force -ErrorAction SilentlyContinue
            exit 1
        }
        if (Test-Path $eskiIc) {
            if (Test-Path $yedekIc) { Remove-Item $yedekIc -Recurse -Force -ErrorAction SilentlyContinue }
            if (-not (KlasorTasi $eskiIc $yedekIc)) {
                Bad "Eski _internal klasoru kenara alinamadi (kullanimda olabilir)."
                Say "Servisi durdurup tekrar deneyin:  sc stop ProtelRAImporter"
                TmpSil $tmp; TmpSil $yeniExe
                Remove-Item $acilan -Recurse -Force -ErrorAction SilentlyContinue
                exit 1
            }
        }
        if (-not (KlasorTasi (Join-Path $acilan "_internal") $eskiIc)) {
            Bad "Yeni _internal klasoru yerine konamadi (antivirus taramasi ya da acik dosya)."
            Remove-Item $eskiIc -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $yedekIc) {
                if (KlasorTasi $yedekIc $eskiIc) { Say "Eski surum geri alindi; kurulum calisir durumda kaldi." }
                else { Say "Eski _internal geri alinamadi: $yedekIc klasorunun adini _internal yapin." }
            }
            Say "Antivirus bu klasoru tariyorsa istisna tanimlayip tekrar deneyin."
            TmpSil $tmp; TmpSil $yeniExe
            Remove-Item $acilan -Recurse -Force -ErrorAction SilentlyContinue
            exit 1
        }
        if (-not (DosyaKopyala $yeniExe $exe)) {
            Bad "RAImporter.exe yerine konamadi (calisiyor olabilir)."
            if (Test-Path $yedekIc) {
                Remove-Item $eskiIc -Recurse -Force -ErrorAction SilentlyContinue
                if (KlasorTasi $yedekIc $eskiIc) { Say "Eski surum geri alindi; kurulum calisir durumda kaldi." }
            }
            Say "Programi kapatip kurulumu tekrar calistirin."
            TmpSil $tmp; TmpSil $yeniExe
            Remove-Item $acilan -Recurse -Force -ErrorAction SilentlyContinue
            exit 1
        }
        TmpSil $yeniExe
        Remove-Item $yedekIc -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $acilan -Recurse -Force -ErrorAction SilentlyContinue
        TmpSil $tmp
    } catch {
        Bad "Paket yerine konamadi: $($_.Exception.Message)"
        Say "Hedef: $Dir - eski surum hala acik olabilir; kapatip tekrar deneyin."
        TmpSil $tmp; Remove-Item $acilan -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }
    Ok "Kuruldu: $exe (+ _internal\)"
} else {
    # Tek dosya exe (eski surumler). PS saglayicisini atlayan .NET tasima
    # (Move-Item '~' iceren yollarda patlar).
    try {
        if (-not (DosyaKopyala $tmp $exe)) { throw "dosya kullanimda olabilir" }
        TmpSil $tmp
    } catch {
        Bad "Dosya yerine konamadi: $($_.Exception.Message)"
        Say "Hedef: $exe - eski surum hala acik olabilir; kapatip tekrar deneyin."
        TmpSil $tmp
        exit 1
    }
    Ok "Kuruldu: $exe"
}

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
    if (-not $yonetici) {
        Bad "Servis kurulumu yonetici hakki gerektiriyor."
        Say "PowerShell'i 'Yonetici olarak calistir' ile acip tekrar deneyin."
    } else {
        Say "Windows servisi kuruluyor..."
        & $exe install-service
        if ($LASTEXITCODE -eq 0) { Ok "Servis kuruldu ve baslatildi"; $svcCalisiyordu = $false }
        else { Bad "Servis kurulumu basarisiz (cikis kodu $LASTEXITCODE)" }
    }
}

# Kurulum icin durdurdugumuz servisi GERI baslat. Yoksa yeni exe yerinde
# durur ama hicbir sey kosmaz; disaridan bakinca "guncelleme surumu
# degistirmedi" gorunur.
if ($svcCalisiyordu) {
    Say "Servis yeni surumle yeniden baslatiliyor..."
    try {
        Start-Service -Name "ProtelRAImporter" -ErrorAction Stop
        (Get-Service -Name "ProtelRAImporter").WaitForStatus(
            "Running", [TimeSpan]::FromSeconds(60))
        Ok "Servis calisiyor (yeni surum devrede)"
    } catch {
        Bad "Servis baslatilamadi: $($_.Exception.Message)"
        Say "Elle baslatin:  sc start ProtelRAImporter"
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
Say "  1. $exe dosyasini calistirin (servis yoksa yonetici onayi ister,"
Say "     servisi kurup baslatir; arayuzu servis sunar)"
Say "  2. Tarayicida acilan arayuzde: Veritabani -> Kaynak -> Eslesmeler -> Kaydet"
Say "  3. 'Deneme calistir' ile dogrulayin"
Say ""
Say "Kurulumu dogrulamak icin (gercek DB'ye karsi uctan uca test):"
Say "  $exe selftest"
Write-Host ""

if ($Open) {
    # exe servisi kurar/baslatir ve arayuzu kendisi acar (v1.8.76+).
    Start-Process $exe
}
