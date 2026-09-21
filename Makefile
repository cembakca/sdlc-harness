# Harness'in KENDI Makefile'i. Tuketen repo bunu kullanmaz; o kendi
# Makefile'ina "include $(SDLC)sdlc.mk" yazar.
#
# Burada bir PROJE yok: sdlc/project.json harness reposunda bulunmaz. Bu yuzden
# yapilandirmaya bakan hedefler once ornek bir proje uretir (fixtures/) ve
# kokunu acikca gecer — CI de ayni seyi yapar.
SDLC =
include sdlc.mk

.PHONY: selftest
selftest: ## Durdurucular gercekten durduruyor mu (uretilen ornek proje uzerinde)
	@P="$$(fixtures/make-project.sh)" && echo "ornek proje: $$P" && \
	 SDLC_PROJECT_ROOT="$$P" scripts/sdlc/selftest.sh
