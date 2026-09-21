# Değişiklik günlüğü

Tüketen repo harness'ın bir **commit'ine** sabitlenir (submodule). Yükseltmek
açık bir harekettir:

```bash
git submodule update --remote sdlc-harness
cp sdlc-harness/sdlc/ci.yml .github/workflows/sdlc-office.yml
make sdlc-config && make sdlc-selftest
```

Yapılandırma şeması `sdlc/project.json` içindeki `schemaVersion` ile taşınır.
Harness anladığından **büyük** bir sürüm görürse durur ve "harness eski" der;
sessizce yanlış okumaz.

## Şema 1 — 22 Eylül 2026

İlk sürümlenmiş şema. Alanlar: `name`, `stacks[]`
(`name`, `root`, `changedPattern`, `testCommand`, `soloCommand`,
`typecheckCommand`, `deps`, `envFile`/`envFiles`, `clearEnv`, `services`,
`testSelector`, `failureFilePattern`, `infraFailurePatterns`),
`criticalSurfaces[]`, `criticalPaths[]`, `memory`
(`processDataset`, `productDataset`, `productDocs`), `secrets.allowPaths`.

`schemaVersion` yazılmamışsa 1 varsayılır ve uyarı basılır.

Denetim ayrıca **gölgede kalan yığını** yakalar: yığın seçimi ilk eşleşmeyi
alır, o yüzden `^apps/` deseni `^apps/api/` deseninin önündeyse ikinci yığına
hiçbir değişiklik ulaşmaz ve testleri hiç koşmadan "geçti" görünür.

## Sürümsüz dönem — 21 Eylül 2026

Harness `dc-archive` reposunun içinde yaşıyordu. Kendi reposuna alındı ve
submodule olarak bağlandı; kök keşfi açık hale getirildi
(`gates/root.ts`, `scripts/sdlc/_root.sh`).
