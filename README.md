# Protel R&A Importer — dağıtım

Oracle Cloud **Reports & Analytics** Excel export dosyalarını Oracle veritabanına
aktarır. Tek dosya: `RAImporter.exe` — Python, .NET, Oracle Instant Client,
ODP.NET veya `tnsnames.ora` gerekmez.

Bu depo yalnızca **dağıtım** içindir. Kaynak kod ayrı ve özel bir depodadır.

---

## Kurulum

Program dosyası bu deponun **Releases** bölümündedir.

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 `
  -Url "https://github.com/alperenkurbanoglu10/raimporter-dagitim/releases/download/v1.2.0/RAImporter.exe" `
  -Sha256 "<RAImporter.exe.sha256 dosyasindaki deger>" `
  -UpdateUrl "https://raw.githubusercontent.com/alperenkurbanoglu10/raimporter-dagitim/main/surum.json" `
  -Service
```

`-UpdateUrl` verilirse sunucuya bir daha girmek gerekmez: program yeni sürümleri
kendi alır. `-Service` Windows servisi olarak kurar.

Elle kurmak isterseniz exe'yi indirip çalıştırmanız yeterli; yönetim arayüzü
`http://127.0.0.1:8787/` adresinde açılır. Saha notları: [KURULUM.txt](KURULUM.txt)

### İndirdiğinizi doğrulayın

```powershell
certutil -hashfile RAImporter.exe SHA256
```

Çıkan değer [`RAImporter.exe.sha256`](RAImporter.exe.sha256) içindekiyle aynı
olmalıdır. `install.ps1` bunu `-Sha256` verdiğinizde kendisi yapar ve tutmazsa
kurulumu durdurur.

---

## Güncelleme

Kurulu program `surum.json` dosyasını günde bir kez okur. Yeni sürüm varsa gece
penceresinde (varsayılan 02:00–05:00) ve **o an çalışan bir aktarım yokken**
kendini günceller.

Kurmadan önce dört kapı vardır:

1. **İmza** — `surum.json`, Protel'in özel anahtarıyla imzalanır ve programın
   içine gömülü açık anahtarla doğrulanır (Ed25519). `surum.json.sig` eksikse
   ya da doğrulanmazsa güncelleme yapılmaz.
2. **SHA-256** — inen dosyanın özeti manifest'tekiyle aynı mı
3. **MZ imzası** — inen dosya gerçekten bir Windows programı mı
4. **Duman testi** — inen sürüm çalıştırılıp çıkış kodu kontrol edilir

Dördü de geçilmeden kurulu sürüme dokunulmaz. Bu, depoya yazma yetkisinin tek
başına bir kuruluma kod göndermeye yetmemesi anlamına gelir.

Adım adım hepsi `data/logs/<tarih>/<saat>_GUNCELLEME.log` dosyasına yazılır.

Elle:

```
RAImporter.exe version         hangi sürüm kurulu
RAImporter.exe check-update    yeni sürüm var mı
RAImporter.exe update          indir ve kur
```

**Güncelleme adresi HTTPS olmalıdır.** Program düz `http://` adresleri reddeder
(yalnızca localhost ve arayüzden açıkça açılan istisna hariç).

### Tek bir sunucuda eski sürüme dönmek

Güncelleme öncesi sürüm aynı klasörde `RAImporter.<sürüm>.old.exe` adıyla bir
sonraki açılışa kadar saklanır. Programı kapatın, `RAImporter.exe` dosyasını
silin, `.old.exe` dosyasının adını `RAImporter.exe` yapın.

---

## Sürümler

Sürüm notları Releases bölümündedir. Sürüm numarası yükselmedikçe hiçbir kurulum
kendini güncellemez.

---

## Destek

Protel — akurbanoglu@protel.com.tr
