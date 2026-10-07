/* Test adapter for the unmodified, separately fetched vecx emulator.
 * Including its implementation exposes CPU/RAM state without patching vecx.
 * This adapter and the game do not redistribute the Vectrex system BIOS.
 */
#include <stdio.h>
#include <string.h>
static unsigned long long emulated_cycles;
#define read8 cpu_read8
#define write8 cpu_write8
#include "../build/e6809.inc"
#undef read8
#undef write8
#include "../build/vecx.inc"

static vector_t captured[50000];
static long captured_count;
static unsigned renders;
void e8910_write(int r, int v) { (void)r; (void)v; }
void osint_render(void) {
    captured_count = vector_draw_cnt;
    if (captured_count > 50000) captured_count = 50000;
    memcpy(captured, vectors_draw, captured_count * sizeof(vector_t));
    renders++;
}
int emu_load(const char *bios, const char *game) {
    FILE *f = fopen(bios, "rb");
    if (!f) return 1;
    size_t n = fread(rom, 1, sizeof(rom), f);
    fclose(f);
    if (n != sizeof(rom)) return 2;
    f = fopen(game, "rb");
    if (!f) return 3;
    memset(cart, 0, sizeof(cart));
    n = fread(cart, 1, sizeof(cart), f);
    fclose(f);
    if (!n) return 4;
    vecx_reset();
    captured_count = 0;
    renders = 0;
    emulated_cycles = 0;
    return 0;
}
void emu_run(unsigned cycles) { vecx_emu(cycles); }
unsigned long long emu_cycles(void) { return emulated_cycles; }
int emu_until(unsigned pc, unsigned max_instructions) {
    for (unsigned i = 0; i < max_instructions; i++) {
        if (reg_pc == pc) return 0;
        vecx_emu(1);
    }
    return 1;
}
unsigned emu_pc(void) { return reg_pc; }
unsigned emu_sp(void) { return reg_s; }
unsigned emu_a(void) { return reg_a & 255; }
unsigned emu_read(unsigned address) { return e6809_read8(address); }
void emu_write(unsigned address, unsigned value) { e6809_write8(address, value); }
void emu_input(unsigned buttons, unsigned x, unsigned y) {
    snd_regs[14] = 0xff ^ (buttons & 15);
    alg_jch0 = x;
    alg_jch1 = y;
}
/* Execute an actual ROM subroutine with a sentinel RTS destination.
 * CPU-only calls are for game logic; BIOS/video checks use emu_run instead.
 */
int emu_call(unsigned address, unsigned a, unsigned b) {
    reg_s = 0xcbea;
    e6809_write8(--reg_s, 0x00);
    e6809_write8(--reg_s, 0x7f);
    reg_pc = address;
    reg_a = a;
    reg_b = b;
    reg_dp = 0xd0;
    reg_cc = 0x50;
    irq_status = IRQ_NORMAL;
    for (unsigned n = 0; n < 1000000; n++) {
        if (reg_pc == 0x7f00) return 0;
        e6809_sstep(0, 0);
    }
    return 1;
}
int emu_vectors(const char *path) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    for (long i = 0; i < captured_count; i++) {
        vector_t v = captured[i];
        fprintf(f, "%ld,%ld,%ld,%ld,%u\n", v.x0,v.y0,v.x1,v.y1,v.color);
    }
    fclose(f);
    return (int)captured_count;
}
