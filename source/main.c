/*
 * BLOCK BURST - puzzle de blocos 8x8 para PS3 (PSL1GHT)
 *
 * Controles:
 *   D-Pad   mover a peça no tabuleiro
 *   L1 / R1 trocar de peça (das 3 disponíveis)
 *   X       colocar a peça
 *   START   novo jogo
 *
 * Regras: complete linhas ou colunas inteiras para limpá-las.
 * Limpar várias de uma vez dá combo (pontos = 10 * n * n).
 * Fim de jogo: nenhuma das peças restantes cabe no tabuleiro.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <malloc.h>
#include <unistd.h>
#include <ppu-types.h>
#include <sysutil/sysutil.h>
#include <io/pad.h>

#include "rsxutil.h"

#define HOST_SIZE (1024 * 1024)
#define N 8

/* ---------- Pecas ---------- */
typedef struct { int w, h; const char *m; } Shape;

static const Shape SH[] = {
    {1,1,"#"},
    {2,1,"##"}, {1,2,"##"},
    {3,1,"###"}, {1,3,"###"},
    {4,1,"####"}, {1,4,"####"},
    {5,1,"#####"}, {1,5,"#####"},
    {2,2,"####"},
    {3,3,"#########"},
    {2,3,"######"}, {3,2,"######"},
    {2,2,"#.##"}, {2,2,".###"}, {2,2,"###."}, {2,2,"##.#"},
    {3,3,"#..#..###"}, {3,3,"..#..####"},
    {3,2,"###.#."},
    {3,2,".####."}, {3,2,"##..##"},
};
#define NSH ((int)(sizeof(SH) / sizeof(SH[0])))

static const u32 COLORS[] = {
    0x00000000, 0x00E74C3C, 0x003498DB, 0x002ECC71,
    0x00F1C40F, 0x009B59B6, 0x00E67E22
};

/* Fonte 3x5 para digitos */
static const u16 DIGITS[10] = {
    0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9,
    0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF
};

/* ---------- Estado ---------- */
static int grid[N][N];
static int tray[3], trayColor[3], used[3];
static int sel, cx, cy;
static unsigned score, best;
static int over;
static int running = 1;
static int dirty = 2;       /* redesenha 2x (double buffer) */
static unsigned tick;

/* ---------- Desenho ---------- */
static u32 *fb;
static int W, H;

static void rect(int x, int y, int w, int h, u32 c)
{
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > W) w = W - x;
    if (y + h > H) h = H - y;
    if (w <= 0 || h <= 0) return;
    for (int j = 0; j < h; j++) {
        u32 *p = fb + (y + j) * W + x;
        for (int i = 0; i < w; i++) p[i] = c;
    }
}

static void number(int x, int y, unsigned v, int s, u32 c)
{
    char buf[16];
    snprintf(buf, sizeof(buf), "%u", v);
    for (char *p = buf; *p; p++) {
        u16 g = DIGITS[*p - '0'];
        for (int i = 0; i < 15; i++)
            if (g & (1 << (14 - i)))
                rect(x + (i % 3) * s, y + (i / 3) * s, s, s, c);
        x += 4 * s;
    }
}

/* ---------- Logica ---------- */
static int fits(int si, int x, int y)
{
    const Shape *s = &SH[si];
    if (x < 0 || y < 0 || x + s->w > N || y + s->h > N) return 0;
    for (int j = 0; j < s->h; j++)
        for (int i = 0; i < s->w; i++)
            if (s->m[j * s->w + i] == '#' && grid[y + j][x + i]) return 0;
    return 1;
}

static int anyFits(void)
{
    for (int k = 0; k < 3; k++) {
        if (used[k]) continue;
        for (int y = 0; y < N; y++)
            for (int x = 0; x < N; x++)
                if (fits(tray[k], x, y)) return 1;
    }
    return 0;
}

static void newTray(void)
{
    for (int i = 0; i < 3; i++) {
        tray[i] = rand() % NSH;
        trayColor[i] = 1 + rand() % 6;
        used[i] = 0;
    }
    sel = 0;
}

static void clampCursor(void)
{
    const Shape *s = &SH[tray[sel]];
    if (cx > N - s->w) cx = N - s->w;
    if (cy > N - s->h) cy = N - s->h;
    if (cx < 0) cx = 0;
    if (cy < 0) cy = 0;
}

static void newGame(void)
{
    srand(tick + 12345);
    memset(grid, 0, sizeof(grid));
    score = 0;
    over = 0;
    cx = cy = 3;
    newTray();
    clampCursor();
    dirty = 2;
}

static void placePiece(void)
{
    if (over || used[sel] || !fits(tray[sel], cx, cy)) return;

    const Shape *s = &SH[tray[sel]];
    for (int j = 0; j < s->h; j++)
        for (int i = 0; i < s->w; i++)
            if (s->m[j * s->w + i] == '#') {
                grid[cy + j][cx + i] = trayColor[sel];
                score++;
            }
    used[sel] = 1;

    /* detecta linhas/colunas completas antes de limpar */
    int rows[N] = {0}, cols[N] = {0}, n = 0;
    for (int y = 0; y < N; y++) {
        int full = 1;
        for (int x = 0; x < N; x++) if (!grid[y][x]) full = 0;
        rows[y] = full; n += full;
    }
    for (int x = 0; x < N; x++) {
        int full = 1;
        for (int y = 0; y < N; y++) if (!grid[y][x]) full = 0;
        cols[x] = full; n += full;
    }
    for (int y = 0; y < N; y++) if (rows[y]) for (int x = 0; x < N; x++) grid[y][x] = 0;
    for (int x = 0; x < N; x++) if (cols[x]) for (int y = 0; y < N; y++) grid[y][x] = 0;
    score += 10 * n * n;
    if (score > best) best = score;

    if (used[0] && used[1] && used[2]) newTray();
    else for (int k = 0; k < 3; k++) if (!used[k]) { sel = k; break; }

    clampCursor();
    if (!anyFits()) over = 1;
    dirty = 2;
}

static void changeSel(int dir)
{
    for (int k = 1; k <= 3; k++) {
        int t = (sel + dir * k + 6) % 3;
        if (!used[t]) { sel = t; break; }
    }
    clampCursor();
    dirty = 2;
}

/* ---------- Render ---------- */
static void drawShape(int si, int x, int y, int cs, u32 c)
{
    const Shape *s = &SH[si];
    for (int j = 0; j < s->h; j++)
        for (int i = 0; i < s->w; i++)
            if (s->m[j * s->w + i] == '#')
                rect(x + i * cs + 1, y + j * cs + 1, cs - 2, cs - 2, c);
}

static void draw(void)
{
    int cs = H / 12;
    int gx = (W - N * cs) / 2 - cs * 3;
    int gy = (H - N * cs) / 2;

    rect(0, 0, W, H, 0x00141420);

    /* placar */
    int ds = cs / 8 > 0 ? cs / 8 : 1;
    number(gx, gy - 8 * ds, score, ds, 0x00FFFFFF);
    number(gx + N * cs + cs, gy - 8 * ds, best, ds, 0x00F1C40F);

    /* tabuleiro */
    rect(gx - 6, gy - 6, N * cs + 12, N * cs + 12, over ? 0x00C0392B : 0x003A3A5C);
    for (int y = 0; y < N; y++)
        for (int x = 0; x < N; x++) {
            u32 c = grid[y][x] ? COLORS[grid[y][x]] : 0x00252538;
            rect(gx + x * cs + 1, gy + y * cs + 1, cs - 2, cs - 2, c);
        }

    /* sombra da peca selecionada */
    if (!over && !used[sel]) {
        u32 gc = fits(tray[sel], cx, cy) ? 0x00A0A0D0 : 0x00A04040;
        drawShape(tray[sel], gx + cx * cs, gy + cy * cs, cs, gc);
    }

    /* bandeja */
    int tcs = cs / 2;
    int box = 5 * tcs + 10;
    int tx = gx + N * cs + cs;
    for (int i = 0; i < 3; i++) {
        int ty = gy + i * (box + 12);
        rect(tx, ty, box, box, (i == sel && !over) ? 0x00FFFFFF : 0x003A3A5C);
        rect(tx + 3, ty + 3, box - 6, box - 6, 0x001C1C2E);
        if (!used[i]) {
            const Shape *s = &SH[tray[i]];
            int ox = tx + (box - s->w * tcs) / 2;
            int oy = ty + (box - s->h * tcs) / 2;
            drawShape(tray[i], ox, oy, tcs, COLORS[trayColor[i]]);
        }
    }
}

/* ---------- Sistema / Entrada ---------- */
static void sysutil_cb(u64 status, u64 param, void *usrdata)
{
    (void)param; (void)usrdata;
    if (status == SYSUTIL_EXIT_GAME) running = 0;
}

enum { B_L = 1, B_R = 2, B_U = 4, B_D = 8, B_X = 16, B_START = 32, B_L1 = 64, B_R1 = 128 };

static u32 buttons(const padData *d)
{
    return (d->BTN_LEFT ? B_L : 0) | (d->BTN_RIGHT ? B_R : 0) |
           (d->BTN_UP ? B_U : 0)   | (d->BTN_DOWN ? B_D : 0)  |
           (d->BTN_CROSS ? B_X : 0)| (d->BTN_START ? B_START : 0) |
           (d->BTN_L1 ? B_L1 : 0)  | (d->BTN_R1 ? B_R1 : 0);
}

int main(int argc, const char *argv[])
{
    (void)argc; (void)argv;

    void *host_addr = memalign(1024 * 1024, HOST_SIZE);
    init_screen(host_addr, HOST_SIZE);
    ioPadInit(7);
    sysUtilRegisterCallback(0, sysutil_cb, NULL);

    W = display_width;
    H = display_height;

    newGame();

    padInfo pinfo;
    padData pdata;
    u32 prev = 0;

    while (running) {
        sysUtilCheckCallback();
        tick++;

        /* le o primeiro controle conectado */
        u32 cur = 0;
        ioPadGetInfo(&pinfo);
        for (int i = 0; i < MAX_PADS; i++) {
            if (pinfo.status[i]) {
                ioPadGetData(i, &pdata);
                cur = buttons(&pdata);
                break;
            }
        }
        u32 press = cur & ~prev;
        prev = cur;

        if (press & B_START) newGame();
        if (!over) {
            if (press & B_L)  { cx--; clampCursor(); dirty = 2; }
            if (press & B_R)  { cx++; clampCursor(); dirty = 2; }
            if (press & B_U)  { cy--; clampCursor(); dirty = 2; }
            if (press & B_D)  { cy++; clampCursor(); dirty = 2; }
            if (press & B_L1) changeSel(-1);
            if (press & B_R1) changeSel(+1);
            if (press & B_X)  placePiece();
        }

        if (dirty) {
            waitFlip();
            fb = (u32 *)buffers[currentBuffer]->ptr;
            draw();
            flip(currentBuffer);
            currentBuffer = !currentBuffer;
            dirty--;
        } else {
            usleep(16000);
        }
    }

    ioPadEnd();
    return 0;
}
