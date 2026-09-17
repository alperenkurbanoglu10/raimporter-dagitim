# Protel R&A Importer — dağıtım

Oracle Cloud **Reports & Analytics** Excel export dosyalarını Oracle **veya
PostgreSQL** veritabanına aktarır ve mevcut bir Opera DWH Oracle şemasını
**PostgreSQL'e taşır** (şema + veri + sequence + indeks/kısıt + view +
PL/SQL paket portu). Tek klasör paketi: `RAImporter.exe` + `_internal\` —
Python, .NET, Oracle Instant Client, ODP.NET veya `tnsnames.ora` gerekmez.

Bu depo yalnızca **dağıtım** içindir. Kaynak kod ayrı ve özel bir depodadır.

---

## Kurulum

Program paketi bu deponun **Releases** bölümündedir
(`RAImporter-<sürüm>-win64.zip` + `.sha256`). Komut istemini (`cmd`) ya da
PowerShell'i **"Yönetici olarak çalıştır"** ile açın; aşağıdaki **tek satır**
ikisinde de aynı şekilde çalışır ve sürümden bağımsızdır (satırı bölmeyin):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -UseBasicParsing 'https://raw.githubusercontent.com/alperenkurbanoglu10/raimporter-dagitim/main/install.ps1' -OutFile 'C:\Windows\Temp\install.ps1'; & 'C:\Windows\Temp\install.ps1' -UpdateUrl 'https://raw.githubusercontent.com/alperenkurbanoglu10/raimporter-dagitim/main/surum.json' -Service"
```

`-Url` vermek gerekmez: betik güncel paketi `surum.json`'daki `paket_url`
adresinden indirir ve SHA-256'yı yine oradaki `paket_sha256` ile doğrular.

**Kurulum klasörünü betik kendisi bulur:** önce var olan kurulum (servis
kaydı, çalışan program, disklerdeki `…\Protel\RAImporter`) — yükseltme hep
oraya gider; kurulum yoksa sistem diski dışındaki ilk yazılabilir sabit veri
diski (gelenek `D:`, sonra en çok boş alanlı); o da yoksa
`C:\Protel\RAImporter`. Takılı DVD, USB, ağ sürücüsü ve NTFS/ReFS dışı
biçimler listeye girmez. Başka bir klasör için komuta
`-Dir "E:\Protel\RAImporter"` ekleyin — verdiğiniz yol sessizce değişmez.

> **Eski komut çalışmaz:** 08.09'dan (1.8.70) beri release'lerde `RAImporter.exe`
> yok; `.../releases/latest/download/RAImporter.exe` adresi 404 döner. Eski
> betik bunu "The connection was closed unexpectedly" diye gösterebilir — ağ
> sorunu değildir.

Paketi kendi yerinizden (dosya sunucusu / Drive) dağıtacaksanız `-Url` ile
zip'in doğrudan indirme adresini verin; `-Sha256` verilmezse betik özeti
`<Url>.sha256` adresinden almayı dener. Elle verecekseniz 64 haneli **gerçek**
değeri yazın — şablon/bozuk özet kuruluma başlamadan reddedilir.

`-UpdateUrl` verilirse sunucuya bir daha girmek gerekmez: program yeni sürümleri
kendi alır. `-Service` Windows servisi olarak kurar.

Elle kurmak isterseniz zip'i bir klasöre açın (`RAImporter.exe` ile
`_internal\` yan yana kalmalı) ve `RAImporter.exe`'yi çalıştırın; yönetim
arayüzü `http://127.0.0.1:8787/` adresinde açılır. Saha notları:
[KURULUM.txt](KURULUM.txt)

### İndirdiğinizi doğrulayın

```powershell
certutil -hashfile RAImporter-<sürüm>-win64.zip SHA256
```

Çıkan değer release'teki `RAImporter-<sürüm>-win64.zip.sha256` (ve
`surum.json`'daki `paket_sha256`) ile aynı olmalıdır. `install.ps1` bu
karşılaştırmayı zaten kendisi yapar ve tutmazsa kurulumu durdurur.

---

## Oracle → PostgreSQL taşıma (Taşıma sekmesi)

Arayüzdeki **Taşıma** sekmesi tüm geçişi adım adım yürütür; uzmanın SQL
yazması gerekmez:

1. **PostgreSQL hazırlığı** — hedef sunucuda PostgreSQL yoksa "PostgreSQL kur"
   düğmesi EDB kurulumunu indirir, sessiz kurar ve Protel standardını açar
   (veritabanı `protel`, şema `protel`, kullanıcı/şifre `protel`). Yönetici
   onayı (UAC) ister; başka bir şey gerekmez.
2. **İncele** — kaynak Oracle envanteri (tablo/satır/view/indeks/trigger/PLSQL).
3. **Şema kur** — referans Opera DWH modeline göre tablolar + PK + indeksler.
4. **Veri taşı** — sayarak, tablo tablo mutabakatla; iş kuralları otomatik
   (ör. BUSINESSDATE'te resort başına tek OPEN kalır, eskileri CLOSED yazılır).
5. **Doğrula** — kaynak/hedef satır sayıları karşılaştırılır.
6. **Paketleri kur** — Oracle PL/SQL paketlerinin PostgreSQL portu (paket =
   aynı adlı şema; `akbs` otelin kendi yapılandırmasından üretilir).
7. **View'ları taşı** — Oracle view'ları otomatik çevrilir ve kurulur;
   çevrilemeyen olursa orijinal + çeviri SQL yan yana raporlanır.

Her adım raporunu arayüzde gösterir; hiçbir adım Oracle tarafına yazmaz.

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

Güncelleme öncesi sürüm aynı klasörde bir sonraki açılışa kadar saklanır:
`RAImporter.<sürüm>.old.exe` **ve** `_internal.old\` (tek klasör paketinde
ikisi birlikte döner). Servisi durdurun (`sc stop ProtelRAImporter`),
`RAImporter.exe` ile `_internal\` klasörünü silin, `.old.exe` dosyasının adını
`RAImporter.exe`, `_internal.old\` klasörünün adını `_internal\` yapın, servisi
başlatın. Yalnızca exe'yi geri almak yetmez — exe ile `_internal\` aynı sürümden
olmalıdır.

---

## Sürümler

Sürüm notları Releases bölümündedir. Sürüm numarası yükselmedikçe hiçbir kurulum
kendini güncellemez.

---

## Destek

Protel — akurbanoglu@protel.com.tr
