---
name: sdlc
description: Bir ticket'ı BRD'den UAT paketine kadar teslim hattından geçirir (hafıza → kademe → spec → kapı → plan → kapı → build → postbuild → review → kapı → test → UAT). Kullanıcı /sdlc yazdığında ya da bir ticket'ı uçtan uca teslim etmek istediğinde kullan.
disable-model-invocation: true
allowed-tools:
  - Bash(make sdlc-*)
  - Read
  - AskUserQuestion
---

# Teslim hattı

Argüman: ticket kimliği (`HKA-123`). Verilmemişse `AskUserQuestion` ile sor —
`docs/sdlc/` altındaki mevcut klasörleri seçenek olarak göster.

## 1. Ön koşullar

`make sdlc-doctor TICKET=<ticket>` çıktısına bak. Kritik eksik varsa kullanıcıya
göster ve devam etmeden önce sor: test fazı koşturulamayan bir ortamda
"testler geçti" cümlesi kurulamaz.

`docs/sdlc/<ticket>/intent.md` yoksa dur ve kullanıcıdan iste — bu hattın tek
insan-yazımı dosyası, onu senin doldurman hattın amacını bozar.

## 2. Çalıştır

```bash
make sdlc-orchestrate TICKET=<TICKET>
```

Sadece spec ve plan için `FLAGS=--spec-only` ekle. Dynamic Workflow yolunu
çalıştırma: güvenilir kapı ve onay sorgusu yalnızca Node yürütücüsünde var.

## 3. Sonuç

Komutun döndürdüğü `next` alanını olduğu gibi aktar. Kendi başına
tamamlama, land etme, kapı kararını yorumlama. Kapı `human` dediyse kullanıcıdan
açık onay iste; `block` dediyse hangi maddenin kapatılması gerektiğini söyle.

Hiçbir durumda worktree'yi ana branch'e taşıma — o karar insanın
(`make sdlc-land TICKET=<ticket>` ne taşınacağını gösterir).
