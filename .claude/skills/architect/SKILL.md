---
name: architect
description: Onaylanmış bir spec.md'yi uygulanabilir plan.md'ye ayrıştırır — sıralı görevler, dokunulan dosyalar, test stratejisi, rollback ve blast-radius etiketi. Kod yazmadan önce, sdlc workflow'unun plan fazında veya "bunu nasıl yaparız" sorusunda kullan.
---

# Mimar

Kod düzenlenmeden önce plan üretilir. Bu skill kod yazmaz, diff üretmez.

## Girdi / çıktı

- Girdi: `docs/sdlc/<ticket>/spec.md`
- Çıktı: `docs/sdlc/<ticket>/plan.md` (İngilizce)
- Şablon: `docs/sdlc/templates/plan.md`

## Yöntem

1. Spec'teki her kabul kriterini en az bir göreve bağla; bağlanmayan kriter
   kalırsa plan eksiktir.
2. Görevleri **bağımlılık sırasına** göre diz. Her görev:
   - tek commit'e sığar,
   - dokunduğu dosyaları listeler (gerçek yollar — önce Grep'le doğrula),
   - "done" tanımını taşır (hangi test geçecek).
3. Test stratejisi: hangi seviyede (unit / integration / e2e), hangi araçla
   (server → pytest, client → vitest + playwright), hangi fixture gerekiyor.
4. **Rollback**: bu değişiklik prod'da geri nasıl alınır. Migration varsa
   geri alınabilir mi, veri kaybı olur mu — açıkça yaz.
5. **Blast radius** etiketi ver: `docs | config | logic | critical`.
   `critical` listesi `gates/questions.ts` → `CRITICAL_SURFACES`. Şüphedeysen
   yukarı yuvarla.
6. Riskli varsayımları "Assumptions" altında topla.

## Bitirince

`node gates/evaluate.ts blast docs/sdlc/<ticket>/plan.md` çalıştır. `human`
dönerse kullanıcıdan açık onay al; onaysız build fazını başlatma.
