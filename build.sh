  #!/bin/sh
set -e

: "${PS3DEV:=/usr/local/ps3dev}"; export PS3DEV
PSL1GHT="$PS3DEV"; export PSL1GHT
export PATH="$PATH:$PS3DEV/bin:$PS3DEV/ppu/bin:$PS3DEV/spu/bin"

echo "== PS3DEV=$PS3DEV PSL1GHT=$PSL1GHT =="
ls "$PSL1GHT/ppu_rules"

# localiza cabecalhos e bibliotecas do PSL1GHT nesta imagem
HDR=$(find "$PS3DEV" -name ppu-types.h 2>/dev/null | head -n 1)
echo "ppu-types.h: $HDR"
if [ -z "$HDR" ]; then
  echo "ERRO: ppu-types.h nao encontrado na imagem"
  exit 1
fi
INCDIR=$(dirname "$HDR")

LIBIO=$(find "$PS3DEV" -name libio.a 2>/dev/null | head -n 1)
echo "libio.a: $LIBIO"
LIBDIR=""
if [ -n "$LIBIO" ]; then LIBDIR=$(dirname "$LIBIO"); fi

export C_INCLUDE_PATH="$INCDIR:$PS3DEV/portlibs/ppu/include"
export CPLUS_INCLUDE_PATH="$C_INCLUDE_PATH"
export LIBRARY_PATH="$LIBDIR:$PS3DEV/portlibs/ppu/lib"
echo "C_INCLUDE_PATH=$C_INCLUDE_PATH"
echo "LIBRARY_PATH=$LIBRARY_PATH"

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

OUT="$ROOT/work/blockburst"
rm -rf "$ROOT/work"
mkdir -p "$ROOT/work"
cp -r "$BASE" "$OUT"

find "$OUT/source" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) -delete
cp "$RSXC" "$OUT/source/rsxutil.c"
cp "$RSXH" "$OUT/source/rsxutil.h"
cp "$ROOT/source/main.c" "$OUT/source/main.c"

if [ -d "$OUT/data" ]; then rm -rf "$OUT"/data/*; fi

# a imagem usa o formato antigo de regras: troca o include do Makefile
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
