# sdlc-harness

Yazılım ofisi: ticket'ı spec'ten teslime taşıyan, **kapıları ölçülü** bir hat.
Projeden bağımsızdır — projeye özgü her şey tüketen repodaki
`sdlc/project.json` dosyasındadır.

## Bağlama (submodule)

**Önerilen yol** — harness reposundan, hedefi göstererek. Submodule'ü bağlar,
sembolik bağları kurar, CI'yi kopyalar, iskeleti üretir ve kurulumu doğrular:

```bash
scripts/sdlc/init.sh --target /yol/projem
```

Zaten bağlıysa, **proje kökünden** iskeleti üretmek için:

```bash
cd /yol/projem
sdlc-harness/scripts/sdlc/init.sh
```

> Bu komutu harness'ın kendi deposunda çalıştırmak reddedilir. Submodule'ün
> kendi git deposu vardır; içinden sorulan "git üst dizini" submodule'ün
> kendisini döndürür ve yapılandırma tüketen projeye değil harness'ın içine
> düşerdi. Kök keşfi artık bunu tanıyor, `init.sh` de sesli reddediyor.

Projenin `Makefile`'ına üç satır ve bir include:

```make
SDLC = sdlc-harness/
SDLC_COMPOSE_PROJECT = <proje>-cognee
SDLC_PROJECT_DATASET = <proje>_project
include $(SDLC)sdlc.mk
```

CI: `sdlc/ci.yml` dosyasını `.github/workflows/` altına kopyalayın —
`make sdlc-selftest` bu kopyanın kaynakla birebir aynı olduğunu denetler.

## İki ayrı kök

| | nerede | ne var |
|---|---|---|
| proje kökü | `<proje>/` | `sdlc/project.json`, `sdlc/fixtures/`, `docs/sdlc/<ticket>/`, `.sdlc-worktrees/` |
| harness kökü | `<proje>/sdlc-harness/` | `gates/`, `scripts/sdlc/`, `sdlc/project.ts`, `sdlc/roster.ts` |

`sdlc/` karışık bir dizindir: `project.ts` ve `roster.ts` **harness kodudur**,
`project.json` ve `fixtures/` **proje verisidir**. Bu yüzden script'ler dizine
değil dosya adına bakar — ve selftest, harness kodunu proje kökünde arayan her
satırı yakalar.

Aynı repoda ikisi aynı dizindir; ayrıldığında değildir. Keşif açıktır:
`SDLC_PROJECT_ROOT` → yukarı yürüyüp `sdlc/project.json` → git üst dizini →
sesli hata (`gates/root.ts`, `scripts/sdlc/_root.sh`).

## Sürüm ve yapılandırma sözleşmesi

Tüketen repo bir **commit'e** sabitlenir; yükseltme açık bir harekettir
(`git submodule update --remote`). Yapılandırma şeması `sdlc/project.json`
içindeki `schemaVersion` ile taşınır — harness anladığından büyük bir sürüm
görürse durur ve "harness eski" der. Geçmiş: [CHANGELOG.md](CHANGELOG.md).

```bash
make sdlc-config    # yapılandırma alan-alan denetlenir (modelsiz)
```

Denetim, hattı **durdurmayan ama sessizce yanlış çalıştıran** şeyleri arar:
hiçbir yolu eşleştirmeyen `changedPattern`, var olmayan yığın dizini, watch
modunda açılan test komutu, derlenmeyen düzenli ifade, hafızaya verilmiş bir
sır yolu. Bozuk JSON artık varsayılanlara düşmez — sesli düşer.

## Akış: zincir kâğıtta mı, kapıda mı

Zincir (`gates/chain.ts`) yazılıydı ama **gerçek hiçbir komut ona bakmıyordu** —
yalnızca kuru koşum, hiç koşmamış orkestratör ve selftest okuyordu. Sonuç,
pilot projenin kendi defterinde görülebiliyor (ölçüldü 22 Eyl 2026):

- teslim kapısı **37 kez**, defterde UAT kanıtı yokken ölçtü
- blast kapısı planı, scope kararı verilmeden önce ölçtü

`gates/status.ts` bunu göremezdi: o bir **kontrol listesi**, hangi kapının
satırı var diye bakar — satırların dayanağına değil.

```bash
make sdlc-flow TICKET=X   # neredeyim, sırada ne var, dayanaksız ölçüm oldu mu
make sdlc-next TICKET=X   # yalnızca bir sonraki komut
```

**Ölçülen şey sıra değil, dayanaktır.** `measure.sh` birkaç kapıyı toplu ölçer,
kapılar yeniden koşturulur, iş yineler — komşuluğa bakan bir okuma bunların
hepsini "atlama" sayardı. Önkoşul ise sıralamadan bağımsızdır ve asıl
güvenceyi söyler: *blast ölçüldüyse ortada bir plan vardı, postbuild ölçüldüyse
build koştu.*

Dayanak geçişlidir: `plan.md`'nin diskte durması plan sayılmaz — spec ve scope
kapılarından geçmemişse ortada yalnızca bir dosya vardır.

Kapılar ölçmeden önce bunu sorar ve dayanak yoksa **durur** (exit 21). Geçmenin
tek yolu gerekçeyi deftere yazmaktır:

```bash
SDLC_FLOW_OVERRIDE="<neden>" node gates/evaluate.ts blast docs/sdlc/X/plan.md
```

Bu bir bypass değil, imzalı bir istisnadır: `flow:override` satırı defterin
mühür zincirine girer ve `make sdlc-history` onu gösterir.

## CI istisna politikası

Bilet belgesi (`docs/sdlc/<TICKET>/`) olmayan bir değişiklikte **commit
disiplini ve teslim hazırlığı atlanır**. Bu bilinçli bir istisnadır — her yazım
hatası düzeltmesi spec/plan/UAT üretmek zorunda değil. Ama istisna sessiz
değildir: iş özetine "OFİS DIŞINDA", sebebi, atlananlar ve koşanlar yazılır.

İstisnayı kapatmak isteyen proje:

```json
{ "ci": { "requireTicket": true } }
```

O zaman bilet belgesi olmayan PR düşer.

## Kendini sınama

```bash
./scripts/sdlc/selftest.sh   # tüketen repo içinde
make selftest                # harness reposunda (örnek proje üretilir)
make selftest-shapes         # aynı suit üç proje biçimi üzerinde
fixtures/consumer-smoke.sh . # GERÇEK submodule: kurulumdan teslime
```

`consumer-smoke.sh` ayrı durur çünkü selftest'in geri kalanı **proje kökünde**
koşar ve harness aynı repodaymış gibi davranan senaryolar kurar. İki kök aynı
dizin olduğunda "harness dosyasını proje kökünde aramak" sınıfındaki hatalar
görünmez — 100/100 geçen bir suit tam bunu kaçırdı. Bu senaryo gerçek bir
submodule kurup komutları sırayla koşturur; model çağrısı yoktur, ölçülen şey
kararlar değil **komutların ayakta olup olmadığı**.

`fixtures/make-project.sh [tek|coklu|monorepo]` örnek projeyi üretir:
tek yığın, iki yığın (`envFiles` + typecheck), iç içe monorepo. Biçimler farklı
kod yollarını koşturur — yığın seçimi, desen önceliği, yığın başına ortam
dosyası. Tek biçim, "taşınabilir" iddiasını kanıtlamıyordu.

Örnek proje **kendi git deposu olan** geçici bir dizindir. Harness reposunun
içinde dursaydı iç içe depo olurdu ve dal/HEAD sorguları harness'ın dalını
döndürürdü — o zaman "taban dal ilerledi" gibi
senaryolar ölçmedikleri şeyi ölçmüş olur.

## Ölçüm maliyeti ve kararlılık

Kapı ölçümü saf bir fonksiyondur: aynı belge + aynı sorular + aynı model → aynı
cevap. Buna rağmen F4-1'de `assign` kapısı aynı `plan.md`'yi **58 kez** ölçtü;
55'i birebir tekrardı ve tek başına **381 bin** input token yedi — biletin
toplam 587 bininin üçte ikisi (karar defterinden ölçüldü).

```bash
make sdlc-cache             # kaç kayıt, isabetlerle ne kazanıldı
make sdlc-cache CLEAR=1     # temizle
SDLC_GATE_NO_CACHE=1 ...    # tek koşu için kapat
```

Önbellek `<proje>/.sdlc-cache/` altında, git'e girmez. Anahtar **içeriktir**:
belge, sorular ve modelin o anki karşılığı. Üçünden biri değişirse kayıt
kendiliğinden geçersizdir; ayrıca bir yaş sınırı vardır
(`SDLC_GATE_CACHE_TTL_DAYS`, varsayılan 14).

### Ölç, doğrula, dondur

Önbellek ucuzluk getirir ama kendi riskini yaratır: sınırda duran bir ölçüm
artık **günlerce donar**. Yazı-tura bir kez atılıp sonuç iki hafta servis
edilirse, kararlılık değil kararlılık *görüntüsü* elde edilir.

Bu yüzden önbelleğe yalnızca **doğrulanmış** ölçüm girer. Iskalamada ölçüm iki
kez alınır ve çağıranın **kendi saf karar fonksiyonuyla** karşılaştırılır —
nokta tahminleri değil, KARARLAR. (2.65 ile 2.72 arasındaki fark kimseyi
ilgilendirmez; kararı değiştirip değiştirmediği ilgilendirir.)

| iki ölçüm | ne olur |
|---|---|
| aynı kararı veriyor | önbelleğe girer, iş yürür |
| farklı karar veriyor | **ihtiyatlı** olan seçilir, önbelleğe **girmez**, kapı insana düşer |

Aynı girdide iki farklı ölçüm belirsizliktir — kapının düşük confidence'ta
zaten yaptığı şey: insana düşür. İhtiyat sırası kapıda `pass < human < block`,
kademede `mechanical < standard < deep`.

Maliyet **ıskalama başınadır, çağrı başına değil**. F4-1'in gerçek defteriyle:

| | input token | maliyet |
|---|---|---|
| bugünkü hâli (önbelleksiz) | 595.068 | $0.0250 |
| yalnızca önbellek | 94.997 | $0.0040 |
| önbellek + doğrulama | **189.994** | **$0.0080** |

Yani doğrulama dahil **%68 daha ucuz**, üstüne dondurulan her karar iki kez
ölçülmüş oluyor. Kapatmak için `SDLC_GATE_CONFIRM=0`.

**Nerede susması gerekir:** kalibrasyon. İşi tam da "aynı girdide aynı cevabı
veriyor mu" diye sormak; önbellekten okursa `flapping: 0` her zaman doğru çıkar
ve kontrol boş bir güvenceye dönüşür — `repeats: 1` hatasının aynısı, başka
kılıkta. `gates/calibrate.ts` her ölçümde önbelleği açıkça kapatır, selftest de
bunu denetler.

### Model bir takma addır

`jev-latest` istenir, `jev-1.13.0` döner. Model, isim değişmeden kayabilir; o
yüzden hem önbellek anahtarı hem kalibrasyon kaydı modelin o anki karşılığını
taşır (`GET /v1/models`, token harcamaz). Kalibrasyon bir modelle yapılıp
kapılar başkasıyla koşarsa `gates/readiness.ts` durdurur: kayıt hâlâ taze
görünür ama koşan kapı hakkında hiçbir şey söylemez — hiçbir şeyin kırmızıya
dönmediği bu durum, en sinsi kapı bozulmasıdır.

## Kalibrasyon

Kapılar sessizce bozulur: model sürümü değişir, eşik kayar, bir fixture artık
ayırt etmez. Ölçüm iki kaynaktan beslenir:

| | nerede | ne |
|---|---|---|
| genel vakalar | `gates/fixtures/` (harness) | projeden bağımsız, el yapımı |
| proje vakaları | `sdlc/fixtures/` (proje) | **gerçek** artifact'ler, `project.json` → `calibration.cases` |

El yapımı fixture'lar kapıyı kendi seçtiği sınavda başarılı gösterir: gerçek
bir `plan.md` girdiğinde sinyal 0.40'a çöküyordu ve fixture'larda öyle bir
girdi yoktu. O yüzden gerçek girdi vazgeçilmez — ama **projeye** aittir.

```bash
make sdlc-calibrate-plan   # MODELSİZ: hangi vaka hangi fixture'dan, eksik var mı
make sdlc-calibrate        # gerçek ölçüm (model çağırır, ücretli)
```

Eksik bir fixture **ölçülmeyen** bir vakadır: kapı o durumda hiç sınanmaz ama
rapor "hepsi tuttu" der. `--plan` bunu bedava yakalar; selftest ve CI koşturur.

## Kurallar

Hat'ın anayasası tüketen repodaki `.claude/CLAUDE.md` içindedir. Özet:
plan'sız build yok, kodu yazan modeli aynı sağlayıcı denetlemez, insan kapısı
blast radius'a bağlıdır, onay defterde kayıttır (bayrak değil), teslim
`gates/readiness.ts`'ten geçer.
