---
name: uat-packager
description: Tamamlanmış bir iş için UAT paketi üretir — test senaryoları, hazırlık adımları, bilinen sınırlar, rollback planı. Kullanıcı "bunu nasıl test ederiz", "UAT hazırla", "release notu çıkar" dediğinde veya sdlc workflow'unun uat fazında kullan.
---

# UAT paketleyici

Teknik olmayan birinin eline alıp doğrulayabileceği tek dosyayı üretirsin.

## Girdi / çıktı

- Girdi: `docs/sdlc/<ticket>/` altındaki `spec.md`, `plan.md`, `REVIEW.md` ve
  test çıktısı
- Çıktı: `docs/sdlc/<ticket>/UAT.md`
- Şablon: `docs/sdlc/templates/UAT.md`

## Yöntem

1. Her kabul kriteri → en az bir UAT senaryosu. Senaryolar **kullanıcı dilinde**
   (Türkçe), adım-adım, beklenen sonuçla birlikte.
2. Hazırlık: hangi ortam, hangi hesap/rol, hangi seed verisi, hangi feature flag.
3. `REVIEW.md`'de kapanmamış bulgu varsa "Bilinen sınırlar" altına taşı —
   sessizce yutma.
4. Test çıktısındaki başarısızlıkları aynen aktar.
5. Rollback adımını `plan.md`'den al, prod'da kimin çalıştıracağını yaz.
6. Blast radius `critical` ise en üste **İnsan onayı gerekiyor** kutusu koy ve
   hangi yüzeye dokunulduğunu yaz.

Kod değiştirme, test koşturma — sadece paketle.
