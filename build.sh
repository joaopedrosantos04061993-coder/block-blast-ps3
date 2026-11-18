#!/bin/sh
set -e

: "${PS3DEV:=/usr/local/ps3dev}"; export PS3DEV
PSL1GHT="$PS3DEV"; export PSL1GHT
export PATH="$PATH:$PS3DEV/bin:$PS3DEV/ppu/bin:$PS3DEV/spu/bin"

echo "== PS3DEV=$PS3DEV PSL1GHT=$PSL1GHT =="
ls "$PSL1GHT/ppu_rules"

HDR=$(find "$PS3DEV" -name ppu-types.h 2>/dev/null | head -n 1)
if [ -z "$HDR" ]; then
  echo "ERRO: ppu-types.h nao encontrado na imagem"
  exit 1
fi
INCDIR=$(dirname "$HDR")

LIBIO=$(find "$PS3DEV" -name libio.a 2>/dev/null | head -n 1)
LIBDIR=""
if [ -n "$LIBIO" ]; then LIBDIR=$(dirname "$LIBIO"); fi

export C_INCLUDE_PATH="$INCDIR:$PS3DEV/portlibs/ppu/include"
export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"
export LIBRARY_PATH="$LIBDIR:$PS3DEV/portlibs/ppu/lib"

ROOT=$(pwd)
SAMPLES="$ROOT/PSL1GHT/samples"

# escolhe a versao do rsxutil compativel com o jogo
PICK_H=""
PICK_C=""
FIRST_H=""
FIRST_C=""
echo "== variantes de rsxutil.h =="
for H in $(find "$SAMPLES" -name rsxutil.h | sort); do
  SD=$(dirname "$H")
  C=""
  for CAND in "$SD/rsxutil.c" "$SD/../source/rsxutil.c" "$SD/../rsxutil.c"; do
    if [ -z "$C" ] && [ -f "$CAND" ]; then C="$CAND"; fi
  done
  echo "-- $H"
  echo "   rsxutil.c: $C"
  grep -nE 'buffers|currentBuffer|waitFlip|waitflip|init_screen|flip\(' "$H" || true
  if [ -z "$FIRST_H" ] && [ -n "$C" ]; then FIRST_H="$H"; FIRST_C="$C"; fi
  if [ -z "$PICK_H" ] && [ -n "$C" ] \
     && grep -q 'currentBuffer' "$H" \
     && grep -q 'waitFlip' "$H" \
     && grep -q 'buffers' "$H"; then
    PICK_H="$H"; PICK_C="$C"
  fi
done

if [ -z "$PICK_H" ]; then
  echo "AVISO: nenhuma versao compativel de rsxutil encontrada; usando a primeira"
  PICK_H="$FIRST_H"; PICK_C="$FIRST_C"
fi
if [ -z "$PICK_H" ]; then
  echo "ERRO: rsxutil nao encontrado nos exemplos"
  exit 1
fi
echo "rsxutil escolhido: $PICK_H"

# escolhe um exemplo cujo Makefile tenha o alvo pkg
BASE=""
for MK in $(find "$SAMPLES" -name Makefile | sort); do
  D=$(dirname "$MK")
  if [ -z "$BASE" ] && grep -q '^pkg' "$MK" && ! grep -qi 'spu' "$MK" && [ -d "$D/source" ]; then
    BASE="$D"
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

find "$OUT/source" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) -delete
cp "$PICK_C" "$OUT/source/rsxutil.c"
cp "$PICK_H" "$OUT/source/rsxutil.h"
cp "$ROOT/source/main.c" "$OUT/source/main.c"

# usa o HOST_SIZE do proprio rsxutil.h
sed -i '/^#define HOST_SIZE/d' "$OUT/source/main.c"
# se o header so tem waitflip (minusculo), ajusta o nome
if ! grep -q 'waitFlip' "$OUT/source/rsxutil.h"; then
  sed -i 's/waitFlip/waitflip/g' "$OUT/source/main.c"
fi

if [ -d "$OUT/data" ]; then rm -rf "$OUT"/data/*; fi

sed -i 's#\$(PSL1GHT)/host/ppu.mk#$(PSL1GHT)/ppu_rules#' "$OUT/Makefile"

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
