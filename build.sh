#!/bin/sh
set -e

: "${PS3DEV:=/usr/local/ps3dev}"; export PS3DEV
export PATH="$PATH:$PS3DEV/bin:$PS3DEV/ppu/bin:$PS3DEV/spu/bin"

echo "== PS3DEV=$PS3DEV  PSL1GHT(antes)=$PSL1GHT =="
ls "$PS3DEV" || true

# descobre onde ficam as regras de build do PSL1GHT nesta imagem
RULES_MK=$(find / -xdev -name ppu.mk 2>/dev/null | head -n 1)
RULES_OLD=$(find / -xdev -name ppu_rules 2>/dev/null | head -n 1)
echo "ppu.mk:    $RULES_MK"
echo "ppu_rules: $RULES_OLD"

if [ -n "$RULES_MK" ]; then
  case "$RULES_MK" in
    */host/ppu.mk) PSL1GHT=$(dirname "$(dirname "$RULES_MK")") ;;
    *) PSL1GHT=$(dirname "$RULES_MK") ;;
  esac
elif [ -n "$RULES_OLD" ]; then
  PSL1GHT=$(dirname "$RULES_OLD")
else
  echo "ERRO: regras de build do PSL1GHT nao encontradas na imagem"
  exit 1
fi
export PSL1GHT
echo "PSL1GHT agora: $PSL1GHT"

ROOT=$(pwd)
SAMPLES="$ROOT/PSL1GHT/samples"

RSXC=$(find "$SAMPLES" -name rsxutil.c | sort | head -n 1)
RSXH=$(find "$SAMPLES" -name rsxutil.h | sort | head -n 1)
if [ -z "$RSXC" ] || [ -z "$RSXH" ]; then
  echo "ERRO: rsxutil nao encontrado nos exemplos do PSL1GHT"
  exit 1
fi

# escolhe um exemplo cujo Makefile tenha o alvo pkg
BASE=""
for MK in $(find "$SAMPLES" -name Makefile | sort); do
  D=$(dirname "$MK")
  if grep -q '^pkg' "$MK" && ! grep -qi 'spu' "$MK" && [ -d "$D/source" ]; then
    BASE="$D"
    break
  fi
done
if [ -z "$BASE" ]; then
  echo "ERRO: nenhum exemplo com alvo pkg encontrado"
  exit 1
fi
echo "Usando exemplo base: $BASE"
echo "== includes do Makefile base =="
grep -n 'include' "$BASE/Makefile" || true

OUT="$ROOT/work/blockburst"
rm -rf "$ROOT/work"
mkdir -p "$ROOT/work"
cp -r "$BASE" "$OUT"

find "$OUT/source" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) -delete
cp "$RSXC" "$OUT/source/rsxutil.c"
cp "$RSXH" "$OUT/source/rsxutil.h"
cp "$ROOT/source/main.c" "$OUT/source/main.c"

if [ -d "$OUT/data" ]; then rm -rf "$OUT"/data/*; fi

cd "$OUT"
make clean || true
make pkg \
  TITLE="Block Burst" \
  APPID=BLKBURST0 \
  CONTENTID=UP0001-BLKBURST0_00-0000000000000000 \
  LIBS="-lrsx -lgcm_sys -lio -lsysutil -lrt -llv2 -lm"

mkdir -p "$ROOT/dist"
find "$OUT" -name '*.pkg' -exec cp {} "$ROOT/dist/BlockBurst.pkg" \;
ls -l "$ROOT/dist"
