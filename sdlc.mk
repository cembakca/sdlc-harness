# sdlc.mk — harness'in komut yuzeyi. Projenin Makefile'i bunu include eder:
#
#   SDLC = sdlc-harness/
#   SDLC_COMPOSE_PROJECT = <proje>-cognee
#   SDLC_PROJECT_DATASET = <proje>_project
#   include $(SDLC)sdlc.mk
#
# Neden ayri dosya: harness submodule olarak baglaninca komutlar da onunla
# gelmeli. Hedefleri projenin Makefile'ina kopyalamak, harness guncellendiginde
# sessizce eskiyen bir ikinci kaynak yaratir.
#
# SDLC bos birakilirsa harness proje koku ile ayni dizindedir (ayrilmadan onceki
# duzen); bu yuzden varsayilanlar da o hali korur.
SDLC ?=
SDLC_COMPOSE_PROJECT ?= sdlc-cognee
SDLC_PROJECT_DATASET ?= project

# ---------------------------------------------------------------- AI-native SDLC
#
# Ofis: kim ne yapiyor, kapilar ne olcuyor, is nerede duruyor.
# Taşinabilirlik: projeye ozgu her sey sdlc/project.json icinde.

## --- ticket yasam dongusu
sdlc-new: ## Yeni ticket: klasor + intent + DAL: make sdlc-new TICKET=HKA-123 TITLE="..."
	@$(SDLC)scripts/sdlc/new.sh $(TICKET) "$(TITLE)"

sdlc-status: ## Her ticket nerede duruyor
	@node $(SDLC)gates/status.ts

sdlc-defer: ## Ertelenen isi kendi ticket'ina tasi: make sdlc-defer FROM=F4-1 TICKET=F4-2 TITLE="..." WHY="..."
	@$(SDLC)scripts/sdlc/defer.sh $(FROM) $(TICKET) "$(TITLE)" "$(WHY)"

sdlc-github: ## Ticket'i GitHub'a aynala: make sdlc-github TICKET=F4-1 [PR=1]
	@$(SDLC)scripts/sdlc/sync-github.sh $(TICKET) $(if $(PR),--pr,)

## --- kadro ve kademe
sdlc: ## AI ekibinin kadrosunu bas (kim, hangi model, nerede)
	@node $(SDLC)sdlc/roster.ts

sdlc-check: ## Kadro kurallari (kodu yazan kendi kodunu denetlemesin + tek kaynak)
	@node $(SDLC)sdlc/roster.ts --check

sdlc-assign: ## Her rol hangi modelde kossun: make sdlc-assign TICKET=F4-1
	@node $(SDLC)gates/assign.ts $(TICKET)

## --- kapilar ve olcum
sdlc-gate: ## Tek kapi: make sdlc-gate GATE=spec ARTIFACT=docs/sdlc/F4-1/spec.md
	@node $(SDLC)gates/evaluate.ts $(GATE) $(ARTIFACT)

sdlc-diagnose: ## Hangi kabul kriteri puani cekiyor: make sdlc-diagnose ARTIFACT=docs/sdlc/F4-1/spec.md
	@node $(SDLC)gates/diagnose.ts $(ARTIFACT)

sdlc-cache: ## Kapi olcum onbellegi: kac kayit, ne kazandirdi ([--clear] ile sil)
	@node $(SDLC)gates/cache.ts $(if $(CLEAR),--clear,)

sdlc-calibrate-plan: ## Kalibrasyon dongusu saglam mi (MODELSIZ, bedava)
	@node $(SDLC)gates/calibrate.ts --plan

sdlc-calibrate: ## Kapilar iyiyi kotuden ayiriyor mu (bilinen orneklerle)
	@node $(SDLC)gates/calibrate.ts

sdlc-config: ## Yapilandirma gercekten okunabilir mi (alan-alan, modelsiz)
	@node $(SDLC)sdlc/validate.ts

sdlc-secrets: ## Repoya sir girmis mi (yol + icerik, modelsiz)
	@$(SDLC)scripts/sdlc/secret-scan.sh

sdlc-chain: ## Durum makinesi: fazlar, gecisler, olu faz var mi
	@node $(SDLC)gates/chain.ts

sdlc-dryrun: ## Orkestrasyonu MODELSIZ kostur (kontrol akisi, ~2 sn)
	@node $(SDLC)scripts/sdlc/workflow-dryrun.mjs

sdlc-selftest: ## Durdurucular gercekten durduruyor mu (kasitli kirmizi senaryolar)
	@$(SDLC)scripts/sdlc/selftest.sh

## --- build, test, teslim
sdlc-orchestrate: ## Bagimsiz orkestrator: make sdlc-orchestrate TICKET=HKA-123 [FLAGS=--spec-only]
	@node $(SDLC)scripts/sdlc/orchestrate.mjs $(TICKET) $(FLAGS)

sdlc-run: ## Kod tarafindaki omurga (kismi operator yardimcisi): make sdlc-run TICKET=F4-1
	@$(SDLC)scripts/sdlc/run.sh $(TICKET)

sdlc-postbuild: ## Build ciktisini plana karsi denetle: make sdlc-postbuild TICKET=F4-1
	@node $(SDLC)gates/postbuild.ts $(TICKET)

sdlc-commits: ## Ticket dalinin commit disiplini: make sdlc-commits TICKET=F4-1
	@$(SDLC)scripts/sdlc/commit-lint.sh $(TICKET)

sdlc-test: ## Test fazi (yapilandirmadaki yiginlar): make sdlc-test TICKET=F4-1
	@$(SDLC)scripts/sdlc/test.sh $(TICKET)

sdlc-merge-check: ## Birlesmis halde de yesil mi: make sdlc-merge-check TICKET=F4-1
	@$(SDLC)scripts/sdlc/merge-check.sh $(TICKET)

sdlc-ready: ## Teslim hazirligi (modelsiz): make sdlc-ready TICKET=F4-1
	@node $(SDLC)gates/readiness.ts $(TICKET)

sdlc-approve: ## Insan onayini kayda gecir: make sdlc-approve TICKET=F4-1 GATE=blast WHY="..."
	@$(SDLC)scripts/sdlc/approve.sh $(TICKET) $(GATE) "$(WHY)"

sdlc-land: ## Teslim kapisindan gecerse ana dala tasi: make sdlc-land TICKET=F4-1
	@test -n "$(TICKET)" || { echo "kullanim: make sdlc-land TICKET=HKA-123"; exit 1; }
	@$(SDLC)scripts/sdlc/land.sh $(TICKET)

## --- kayit, gecmis, saglik
sdlc-history: ## Kapilar ne karar verdi: make sdlc-history [TICKET=F4-1]
	@node $(SDLC)gates/history.ts $(TICKET)

sdlc-outcome: ## Teslim sonrasini kaydet: make sdlc-outcome TICKET=X R=shipped-clean WHAT="..."
	@$(SDLC)scripts/sdlc/outcome.sh $(TICKET) $(R) "$(WHAT)"

sdlc-hindsight: ## Kapilar ne dedi, gercekte ne oldu
	@node $(SDLC)gates/hindsight.ts

sdlc-doctor: ## Hat saglik kontrolu: make sdlc-doctor TICKET=F4-1
	@$(SDLC)scripts/sdlc/doctor.sh $(TICKET)

sdlc-init: ## Orkestratoru baska bir repoya tasi: sdlc/project.json iskeleti uret
	@$(SDLC)scripts/sdlc/init.sh

## --- kurum hafizasi
# Compose cagrisi TEK YERDE. Proje adi ve --env-file her cagride ayni olmali:
# -p unutulursa compose adi calisma dizininden turer ve BASKA birimlere baglanir
# (hafiza bos gorunur); --env-file unutulursa compose ".env icine GEMINI_API_KEY
# ekleyin" diye reddeder — anahtar .env'de dururken. Ikisi de olculdu (21 Eyl 2026).
COGNEE_COMPOSE = docker compose -p $(SDLC_COMPOSE_PROJECT) --env-file .env -f $(SDLC)ops/cognee/compose.yml

cognee-up: ## Hafizayi baslat — YALNIZCA backend (mcp/ui icin: cognee-full)
	@$(COGNEE_COMPOSE) up -d cognee-backend
	@echo "backend :8765 · mcp :8766 · arayuz :8767"

cognee-full: ## Backend + MCP + arayuz (ajanlar/insan haritaya bakacaksa)
	@$(COGNEE_COMPOSE) --profile full up -d
	@echo "backend :8765 · mcp :8766 · arayuz :8767  (+478 MB)"

cognee-down: ## Hafizayi durdur (veri volume'de kalir)
	@$(COGNEE_COMPOSE) --profile full down

cognee-logs: ## Hafiza backend loglari
	@$(COGNEE_COMPOSE) logs -f --tail 50 cognee-backend

# MALIYET AYRIMI (olculdu 21 Eyl 2026):
#   graf kurmak (cognify)  → yuz binlerce token, krediyi bitiren is
#   soru sormak (recall)   → ~330 token, ~$0.0001
# Bu yuzden dogru kurulum ikisini ayirmak: PAHALI olan yerelde, UCUZ olan
# bulutta. Yerel 3B model graf kurmaya yetiyor ama cevap sentezi zayif
# (olculdu: spesifik soruya genel ozet donuyor, kaynak gostermiyor).
cognee-local: ## LLM'i YERELE al (graf kurmak icin — bedava, yavas)
	@COGNEE_LLM_PROVIDER=ollama $(MAKE) cognee-up
	@echo "yerel: $${COGNEE_LLM_MODEL:-qwen2.5:3b-instruct} — graf kurmak icin uygun"

cognee-cloud: ## LLM'i BULUTA al (soru sormak icin — ~$0.0001/soru)
	@test -n "$$(grep -m1 '^GEMINI_API_KEY=' .env | cut -d= -f2-)" || { echo ".env icinde GEMINI_API_KEY yok"; exit 1; }
	@COGNEE_LLM_PROVIDER=gemini COGNEE_LLM_MODEL=gemini/gemini-3.1-flash-lite \
	 COGNEE_LLM_KEY="$$(grep -m1 '^GEMINI_API_KEY=' .env | cut -d= -f2-)" $(MAKE) cognee-up
	@echo "bulut: gemini-3.1-flash-lite — soru basina ~$$0.0001"

cognee-ingest: ## Yerel modeli AC, hafizayi guncelle, modeli KAPAT (bellek serbest kalsin)
	@command -v ollama >/dev/null || { echo "ollama yok: brew install ollama"; exit 1; }
	@echo "== yerel model aciliyor (yalnizca bu is icin)"
	@curl -sf -m 10 http://localhost:11434/api/tags >/dev/null 2>&1 || { ollama serve >/dev/null 2>&1 & sleep 3; }
	@echo "   model isitiliyor (soguk baslangic Cognee'nin 30sn baglanti testini asiyor)"
	@curl -s -m 180 http://localhost:11434/api/generate \
	  -d '{"model":"$(or $(COGNEE_LLM_MODEL),qwen2.5:3b-instruct)","prompt":"ok","stream":false,"keep_alive":"60m"}' \
	  -o /dev/null -w "   hazir (%{time_total}s)\n"
	@$(MAKE) cognee-project
	@$(MAKE) cognee-skills
	@echo "== model bosaltiliyor"
	@ollama stop $${COGNEE_LLM_MODEL:-qwen2.5:3b-instruct} >/dev/null 2>&1 || true
	@echo "bitti — bellek serbest. Kanit icin: make sdlc-memory-verify"

cognee-project: ## Urunu hafizaya tanit (AYRI dataset)
	@$(SDLC)scripts/sdlc/memory.sh remember-project

cognee-skills: ## Is tariflerini (SKILL.md) hafizaya yaz
	@$(SDLC)scripts/sdlc/memory.sh skills

cognee-bootstrap: ## Cognee kullanicisi + API anahtari uret (.env'e yazar)
	@$(SDLC)scripts/sdlc/cognee-bootstrap.sh

cognee-agents: ## Kadrodaki her role Cognee kimligi ac
	@$(SDLC)scripts/sdlc/agents.sh sync

cognee-graph: ## Grafin boyutu ve dugum tipleri
	@$(SDLC)scripts/sdlc/memory.sh graph

cognee-reset: ## Hafizayi SIFIRLA ve yeniden kur (embedding modeli/boyutu degistiyse sart)
	@echo "DIKKAT: Cognee birimleri silinecek (belgeler repodan yeniden yuklenir)."
	@printf "devam? [e/H] " && read a && [ "$$a" = "e" ] || { echo "vazgecildi"; exit 1; }
	@$(COGNEE_COMPOSE) down -v
	@$(MAKE) cognee-up
	@echo "backend hazirlaniyor..."
	@for i in $$(seq 1 60); do curl -sf -m 5 http://localhost:8765/health >/dev/null 2>&1 && break || sleep 5; done
	@rm -f $(SDLC)ops/cognee/.ingest-state.json
	@$(SDLC)scripts/sdlc/cognee-bootstrap.sh
	@$(MAKE) cognee-project
	@$(MAKE) cognee-skills
	@$(SDLC)scripts/sdlc/memory.sh verify

cognee-rebuild: ## Grafi sifirdan kur (ham belgeler kalir)
	@$(SDLC)scripts/sdlc/memory.sh rebuild

cognee-ask: ## Urun hafizasina sor: make cognee-ask Q="..."
	@$(SDLC)scripts/sdlc/memory.sh recall-project "$(Q)"

sdlc-memory: ## Hafiza durumu
	@$(SDLC)scripts/sdlc/memory.sh status

sdlc-memory-quality: ## Hafiza DOGRU belgeyi buluyor mu (kaynagi bilinen sorularla)
	@COGNEE_DATASET=$${COGNEE_DATASET:-$(SDLC_PROJECT_DATASET)} $(SDLC)scripts/sdlc/memory.sh quality

sdlc-memory-verify: ## Hafiza GERCEKTEN calisiyor mu (yaz -> graf -> geri oku)
	@$(SDLC)scripts/sdlc/memory.sh verify

# ---------------------------------------------------------------- SDLC son

.PHONY: sdlc-cache sdlc-config sdlc-calibrate-plan cognee-agents cognee-ask cognee-bootstrap cognee-cloud cognee-down cognee-full cognee-graph cognee-ingest cognee-local cognee-logs cognee-project cognee-rebuild cognee-reset cognee-skills cognee-up sdlc sdlc-approve sdlc-assign sdlc-calibrate sdlc-chain sdlc-check sdlc-commits sdlc-defer sdlc-diagnose sdlc-doctor sdlc-dryrun sdlc-gate sdlc-github sdlc-hindsight sdlc-history sdlc-init sdlc-land sdlc-memory sdlc-memory-quality sdlc-memory-verify sdlc-merge-check sdlc-new sdlc-orchestrate sdlc-outcome sdlc-postbuild sdlc-ready sdlc-run sdlc-secrets sdlc-selftest sdlc-status sdlc-test 
