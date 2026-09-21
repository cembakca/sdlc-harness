#!/usr/bin/env python3
"""Geri yuklenen veritabanini yedegin manifestiyle karsilastirir (D5).

Ayri bir dosya, cunku ilk hali kabuk icine gomulu tek satirlik python'du ve
kacis karakterleri yuzunden CALISMIYORDU — ama prova yine de yesil yaniyordu:
karsilastirma coktugu icin "sorun listesi" bos kaliyordu. Provanin en onemli
adimi, sessizce hicbir sey kontrol etmiyordu.

Kullanim:
    compare_restore.py <manifest.json> <restored-counts.json>

Cikis kodu 0 ise sayimlar ortusuyor.
"""
import json
import sys

SYSTEM_PREFIX = "system."


def main() -> int:
    if len(sys.argv) != 3:
        print("kullanim: compare_restore.py <manifest.json> <restored.json>", file=sys.stderr)
        return 2

    try:
        manifest = json.load(open(sys.argv[1]))["collections"]
        restored = json.load(open(sys.argv[2]))
    except (OSError, ValueError, KeyError) as exc:
        print(f"KARSILASTIRMA YAPILAMADI: {exc}", file=sys.stderr)
        return 2

    problems = []
    expected_total = 0
    for name, expected in sorted(manifest.items()):
        if name.startswith(SYSTEM_PREFIX):
            continue
        expected_total += expected
        got = restored.get(name)
        if got is None:
            problems.append(f"{name}: koleksiyon geri gelmedi (beklenen {expected})")
        elif got != expected:
            problems.append(f"{name}: {got} != {expected}")

    # Yedekte olmayan bir koleksiyonun geri yuklemede BELIRMESI de bir sorundur:
    # yanlis dump'i geri yukluyor olabiliriz.
    unexpected = sorted(set(restored) - set(manifest) - {"system.views"})
    for name in unexpected:
        problems.append(f"{name}: manifestte yok ama geri yuklemede var")

    counted = len([k for k in manifest if not k.startswith(SYSTEM_PREFIX)])
    print(f"{counted} koleksiyon / {expected_total} belge")
    for problem in problems:
        print(f"SORUN: {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
