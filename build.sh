#!/bin/sh
set -e

: "${PS3DEV:=/usr/local/ps3dev}"; export PS3DEV
: "${PSL1GHT:=$PS3DEV}"; export PSL1GHT
export PATH="$PATH:$PS3DEV/bin:$PS3DEV/ppu/bin:$PS3DEV/spu/bin"

ROOT=$(pwd)
SAMPLES="$ROOT/PSL1GHT/samples"

RSXC=$(find "$SAMPLES" -name rsxutil.c | sort | head -n 1)
RSXH=$(find "$SAMPLES" -name rsxutil.h | sort | head -n 1)
if [ -z "$RSXC" ] || [ -z "$RSXH" ]; then
  echo "ERRO: rsxutil nao encontrado nos exemplos do PSL1GHT"
  exit 1
fi
echo "rsxutil.c: $RSXC"
echo "rsxutil.h: $RSXH"

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

OUT="$ROOT/work/blockburst"
rm -rf "$ROOT/work"
mkdir -p "$ROOT/work"
cp -r "$BASE" "$OUT"

# troca os fontes do exemplo pelos do jogo
find "$OUT/source" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) -delete
cp "$RSXC" "$OUT/source/rsxutil.c"
cp "$RSXH" "$OUT/source/rsxutil.h"
cp "$ROOT/source/main.c" "$OUT/source/main.c"

# dados do exemplo (shaders etc.) nao sao necessarios
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
