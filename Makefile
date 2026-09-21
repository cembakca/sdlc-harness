# Harness'in KENDI Makefile'i. Tuketen repo bunu kullanmaz; o kendi
# Makefile'ina "include $(SDLC)sdlc.mk" yazar.
#
# Burada bir PROJE yok: sdlc/project.json harness reposunda bulunmaz. Bu yuzden
# yapilandirmaya bakan hedefler once ornek bir proje uretir (fixtures/) ve
# kokunu acikca gecer — CI de ayni seyi yapar.
SDLC =
include sdlc.mk

SHAPES = tek coklu monorepo

.PHONY: selftest selftest-shapes
selftest: ## Durdurucular gercekten durduruyor mu (varsayilan ornek proje)
	@P="$$(fixtures/make-project.sh)" && echo "ornek proje: $$P" && \
	 SDLC_PROJECT_ROOT="$$P" scripts/sdlc/selftest.sh

# Harness'in "tasinabilir" iddiasinin tek kaniti uzerinde kostugu projelerdi ve
# o da TEK bir bicimdi. Cok yiginli ve ic ice duzenler farkli kod yollarini
# calistirir: yigin secimi, desen onceligi, yigin basina ortam dosyasi.
selftest-shapes: ## Ayni suiti uc proje bicimi uzerinde kostur
	@for s in $(SHAPES); do \
	  P="$$(fixtures/make-project.sh $$s)" || exit 1; \
	  echo "── bicim: $$s"; \
	  OUT="$$(SDLC_PROJECT_ROOT="$$P" scripts/sdlc/selftest.sh)"; RC=$$?; \
	  printf '%s\n' "$$OUT" | tail -2; \
	  [ "$$RC" = "0" ] || exit "$$RC"; \
	done
