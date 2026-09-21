# Ajan yürütme sözleşmesi (AgentRunner)

Orkestratörün tek akışı `.claude/workflows/sdlc.js` dosyasındadır. Bağımsız
`sdlc/orchestrator.mjs` aynı akışı çalıştırır ve faz geçişlerini zorlar.
Sağlayıcıyı `agent()` adapteri sağlar; bu belge sözleşmeyi tarif eder.

`scripts/sdlc/workflow-dryrun.mjs` aynı yürütücüyü sahte `agent()` ile
koşturur. Model çağrısı yapmadan geçişleri ve durma noktalarını sınar.

## Yüzey

```js
agent(prompt: string, opts?: {
  label?: string,      // faz/ajan etiketi; deftere ve ilerleme ağacına düşer
  model?: string,      // kadrodan gelir (sdlc/roster.json) — burada seçilmez
  effort?: string,     // kademeden gelir (gates/assign.ts)
}): Promise<string>    // ajanın son metni; kapı kararları buradan okunmaz

command(file: string, args: string[], allowedExitCodes?: number[]):
  Promise<{ stdout: string, stderr: string, code: number }> // kapılar doğrudan

parallel(thunks: (() => Promise<T>)[]): Promise<T[]>   // hepsini bekler
phase(title: string): void                              // durum geçişi işareti
log(message: string): void                              // insana tek satır
args: object                                            // { ticket, specOnly, ... }
budget: { total: number|null, spent(): number, remaining(): number }
```

Bu kadar. `pipeline` ve `workflow` şu an kullanılmıyor.

## Sağlayıcı nereye bağlanır

Orkestratör **model adı yazmaz** (tek istisna: defter tutan ucuz ajanlar için
`haiku`, o da kadroda tanımlı). Sağlayıcı üç yerden gelir:

| katman | nerede | ne yapar |
|---|---|---|
| **kadro** | `sdlc/roster.json` | rol → sağlayıcı + kademe başına model |
| **kademe** | `gates/assign.ts` | her rolün sinyalinden kademe → model |
| **yürütme** | harness'ın `agent()` uygulaması | o modeli gerçekten koşturur |

Yeni bir sağlayıcı eklemek için orkestratöre dokunulmaz:
kadroya bir satır, `agent()` uygulamasına bir dal.

## Codex neden farklı

`implementer` rolü `agent()` üzerinden **kod yazmaz**. Orkestratör bir kabuk
komutu çağırır (`scripts/sdlc/codex-build.sh`) ve o script Codex'i izole bir
git worktree'de, yazma yetkisiyle koşturur. Sebebi tasarım:

- kod yazan ajanın **dosya sistemine** ihtiyacı var, metin üretmeye değil;
- izolasyon (worktree) ve servis sağlama harness'ın işi, ajanın değil;
- kumsal ağa kapalı — test altyapısını harness dışarıdan verir
  (ölçüldü 21 Eyl 2026: Codex sağlanan servise ulaşamıyor, testleri
  hat kendisi koşturuyor).

Yani Codex bir `agent()` sağlayıcısı değil, bir **iş istasyonu**. Başka bir
kod yazma sağlayıcısı eklenecekse aynı yere — o script'in içine — bağlanır.

## Ne taşınır, ne taşınmaz

**Taşınır:** orkestratör, kapılar, kadro, script'ler. Projeye özgü tek kelime
geçmiyor (selftest bunu denetliyor: `mongo|postgres|pytest|vitest|.venv`
ve proje adı yasak).

**Taşınmaz:** `sdlc/project.json` — yığınlar, test komutları, servisler,
kritik yüzeyler, hafıza dataset'leri. Yeni repoda `scripts/sdlc/init.sh --target`
bunu üretir ve kurulumu kendi doğrular.

## Çalıştırma

`node scripts/sdlc/orchestrate.mjs <TICKET>` mevcut Claude CLI'ı yalnızca
içerik üretimi ve review için kullanır. Kapı, onay, build, test ve teslim
komutlarını Node doğrudan çalıştırır. Her fazın önünde `gates/chain.ts` geçişini kontrol eder;
geçersiz geçişte durur. `SDLC_TOKEN_BUDGET` isteğe bağlı faz öncesi durma
eşiğidir; tek bir model çağrısı bu eşiği aşabilir.
Cognee otomatik başlatılmaz; istenirse `MEMORY_AUTOSTART=1` verilir. Başka
repoda compose yolu için `SDLC_MEMORY_COMPOSE` da tanımlanır.
Model çağrılarında Bash aracı kapalıdır. İnsan onayı yalnızca interaktif
terminalde kaydedilir; bu yerel önlem kriptografik kimlik doğrulama değildir.

Claude Dynamic Workflow yolu kullanılmaz: `command()` yürütücüsü olmadan
akış başlamaz. `/sdlc` becerisi bağımsız komutu çağırır.

Yeni bir yürütücü `orchestrate({ agent, command, args, budget, log, onPhase })`
fonksiyonuna kendi `agent(prompt, opts)` ve doğrudan komut adapterini verir. Akış, kapılar ve
proje yapılandırması aynı kalır.
