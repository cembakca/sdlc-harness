# sdlc-harness

Yazılım ofisi: ticket'ı spec'ten teslime taşıyan, **kapıları ölçülü** bir hat.
Projeden bağımsızdır — projeye özgü her şey tüketen repodaki
`sdlc/project.json` dosyasındadır.

## Bağlama (submodule)

```bash
git submodule add git@github.com:<kullanici>/sdlc-harness.git sdlc-harness
sdlc-harness/scripts/sdlc/init.sh        # sdlc/project.json iskeletini üretir
```

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
| proje kökü | `<proje>/` | `sdlc/project.json`, `docs/sdlc/<ticket>/` |
| harness kökü | `<proje>/sdlc-harness/` | `gates/`, `scripts/sdlc/`, `sdlc/` |

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

## Kendini sınama

```bash
./scripts/sdlc/selftest.sh   # tüketen repo içinde
make selftest                # harness reposunda (örnek proje üretilir)
make selftest-shapes         # aynı suit üç proje biçimi üzerinde
```

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
