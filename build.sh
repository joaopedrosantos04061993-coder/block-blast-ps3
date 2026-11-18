#!/bin/sh
set -e

: "${PS3DEV:=/usr/local/ps3dev}"; export PS3DEV
: "${PSL1GHT:=$PS3DEV}"; export PSL1GHT
export PATH="$PATH:$PS3DEV/bin:$PS3DEV/ppu/bin:$PS3DEV/spu/bin"

ROOT=$(pwd)

RSX=$(find "$ROOT/PSL1GHT/samples" -name rsxutil.c | sort | head -n 1)
if [ -z "$RSX" ]; then
  echo "ERRO: rsxutil.c nao encontrado nos exemplos do PSL1GHT"
  exit 1
fi

SRC=$(dirname "$RSX")
if [ "$(basename "$SRC")" = "source" ]; then
  SAMPLE=$(dirname "$SRC")
else
  SAMPLE="$SRC"
fi
echo "Usando exemplo base: $SAMPLE"

OUT="$ROOT/work/blockburst"
rm -rf "$ROOT/work"
mkdir -p "$ROOT/work"
cp -r "$SAMPLE" "$OUT"

OUTSRC="$OUT${SRC#$SAMPLE}"

find "$OUTSRC" -maxdepth 1 \( -name '*.c' -o -name '*.cpp' \) ! -name 'rsxutil.c' -delete
cp "$ROOT/source/main.c" "$OUTSRC/main.c"

[ -d "$OUT/data" ] && rm -rf "$OUT"/data/* || true

sed -i -E 's/^TITLE[[:space:]]*:?=.*/TITLE := Block Burst/' "$OUT/Makefile"
sed -i -E 's/^APPID[[:space:]]*:?=.*/APPID := BLKBURST0/' "$OUT/Makefile"
sed -i -E 's/^CONTENTID[[:space:]]*:?=.*/CONTENTID := UP0001-$(APPID)_00-0000000000000000/' "$OUT/Makefile"

cd "$OUT"
make clean || true
make pkg

mkdir -p "$ROOT/dist"
find "$OUT" -name '*.pkg' -exec cp {} "$ROOT/dist/BlockBurst.pkg" \;
ls -l "$ROOT/dist"
