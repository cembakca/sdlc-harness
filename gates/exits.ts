/**
 * gates/exits.ts — çıkış kodu sözleşmesi, TEK KAYNAK.
 *
 * NEDEN VAR. Çıkış kodları hattın her yerinde anlam taşıyor ama hiçbir yerde
 * yazılı değildi: her çağıran kendi `allowed` listesini elle yazıyordu ve bir
 * kod atlanınca `command()` ham `Error` fırlatıp koşuyu çökertiyordu.
 *
 * Ölçüldü 22 Eylül 2026, M1'in build fazında: sekiz görev de bitti, 38 backend
 * + 4 frontend testi geçti, TypeScript temizdi — ve hat çöktü, çünkü izin
 * listesine `[0, 20]` yazılmış, **10 atlanmıştı**. Oysa postbuild kapısı tam da
 * o anda insana düşmüştü ve akışın devamında onay zaten aranıyordu.
 *
 * Aynı sınıftan ikinci bir örnek aynı taramada bulundu: `memory.sh` 11–16 arası
 * kod döndürüyor, akış ise yalnızca `[0, 13, 14]` kabul ediyordu.
 *
 * Buradaki kazanç listeyi bir yere yazmak değil: `selftest` bu tabloyu hem
 * akıştaki çağrılarla hem de SCRIPT'LERIN KENDI KAYNAGIYLA karşılaştırıyor.
 * Bir script yeni bir kod döndürmeye başladığında tablo güncellenmeden koşu
 * yeşile dönmüyor.
 */

/** Hattın her yerinde aynı anlama gelen üç kod. */
export const EXIT = {
  /** Geç. */
  PASS: 0,
  /** İNSANA düş: karar kapının değil, insanın. Kayıtlı onay arar. */
  HUMAN: 10,
  /** Durdur. */
  BLOCK: 20,
  /** Dayanak yok: faz kendinden önceki kararı okuyamadan ölçülemez. */
  FLOW: 21,
} as const;

/**
 * Komut → anlamlı çıkış kodları.
 *
 * `1` hiçbir sözleşmede YOKTUR: 1 gerçek bir çökmedir ve fırlaması doğrudur.
 * `"any"` = bu komut hattı asla durdurmaz (hafıza böyledir: hafızasız çalışmak
 * çalışmamaktan iyidir).
 */
export const CONTRACT: Record<string, number[] | "any"> = {
  // Kapılar: pass / insana düş / durdur.
  "gates/evaluate.ts": [EXIT.PASS, EXIT.HUMAN, EXIT.BLOCK],
  // Teslim kapısı insana düşmez: ya hazır ya değil. Engelin kendisi zaten
  // kayıtlı onay arıyor.
  "gates/readiness.ts": [EXIT.PASS, EXIT.BLOCK],
  // Teşhis bir kapı değil, rapor: 1 = kriter bulunamadı.
  "gates/diagnose.ts": [EXIT.PASS, 1],
  // Build, postbuild kapısının kodunu OLDUĞU GİBİ geçirir.
  "scripts/sdlc/codex-build.sh": [EXIT.PASS, EXIT.HUMAN, EXIT.BLOCK],
  "scripts/sdlc/merge-check.sh": [EXIT.PASS, EXIT.HUMAN, EXIT.BLOCK],
  "scripts/sdlc/test.sh": [EXIT.PASS, EXIT.HUMAN, EXIT.BLOCK],
  // --check: 0 onay var, 1 onay yok. 2 = interaktif terminal yok ya da insan
  // "EVET" yazmadı — onay bilerek yalnızca canlı terminalde kaydedilir.
  "scripts/sdlc/approve.sh": [EXIT.PASS, 1, 2],
  // Hafıza hattı DURDURMAZ. Kapalı, yavaş, dataset'siz, kotası dolmuş —
  // hepsi ayrı kod ve hiçbiri işin ilerlemesini engellemez.
  "scripts/sdlc/memory.sh": "any",
  // Toplu ölçüm: 0 ya da 1 (bilinmeyen aşama). Kapı kararı üretmez, JSON basar.
  "scripts/sdlc/measure.sh": [EXIT.PASS, 1],
  "scripts/sdlc/worktree-clean.sh": [EXIT.PASS, EXIT.BLOCK],
  "scripts/sdlc/ran.sh": [EXIT.PASS],
  "scripts/sdlc/review-scope.sh": [EXIT.PASS],
  // Commit disiplini kırıksa İNSANA düşer: "bir plan görevi = bir commit"
  // kuralını esneten gerekçe olabilir, ama kaydedilmelidir.
  "scripts/sdlc/commit-lint.sh": [EXIT.PASS, EXIT.HUMAN],
};
