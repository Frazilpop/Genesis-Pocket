/* Genesis Plus GX (the libretro core RetroArch runs) without a window: a game from its ROM, a
 * save loaded as RetroArch loads one, buttons pressed on the frames a script names, frames
 * written as pictures, and the save written as RetroArch writes it. So a .srm made here is
 * byte for byte what RetroArch would leave, for testing the core's save path on one.
 *
 *   gpgx-save CORE.dylib ROM OUTDIR FRAMES [--srm IN] [--input SCRIPT] [--dump F,F,...]
 *
 * RetroArch reads at most the core's save size (64 KB here, asked before the first frame) and
 * drops the rest, and writes the size the core gives after running: Genesis Plus GX's sram.sram
 * up to its last byte that isn't FF. The save goes to OUTDIR/game.srm, a picture of each frame
 * named to OUTDIR/NNNNN.ppm. A script line is "FRAME LENGTH BUTTON...", the buttons held for
 * LENGTH frames from FRAME: up down left right a b c start (pad 1, three buttons).
 */
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libretro.h"

static unsigned pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
static const void *frame_data;
static unsigned frame_w, frame_h;
static size_t frame_pitch;
static char save_dir[4096];

static struct press { long from, len; unsigned mask; } presses[4096];
static int n_presses;
static long frame_no;

static void log_printf(enum retro_log_level level, const char *fmt, ...)
{
    if (level < RETRO_LOG_WARN) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

static bool environment(unsigned cmd, void *data)
{
    switch (cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
        pixel_format = *(const enum retro_pixel_format *)data;
        return true;
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback *)data)->log = log_printf;
        return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = save_dir;
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true;
    default:
        return false;
    }
}

static void video(const void *data, unsigned w, unsigned h, size_t pitch)
{
    if (data) { frame_data = data; frame_w = w; frame_h = h; frame_pitch = pitch; }
}
static void audio(int16_t l, int16_t r) { (void)l; (void)r; }
static size_t audio_batch(const int16_t *d, size_t n) { (void)d; return n; }
static void input_poll(void) {}

static unsigned held(void)
{
    unsigned m = 0;
    for (int i = 0; i < n_presses; i++)
        if (frame_no >= presses[i].from && frame_no < presses[i].from + presses[i].len) m |= presses[i].mask;
    return m;
}

static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
    (void)index;
    if (port != 0 || device != RETRO_DEVICE_JOYPAD) return 0;
    unsigned m = held();
    if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)m;
    return (m >> id) & 1;
}

static unsigned button(const char *name)
{
    /* Genesis Plus GX's own map: A on the RetroPad's Y, B on B, C on A */
    static const struct { const char *n; unsigned id; } map[] = {
        {"up", RETRO_DEVICE_ID_JOYPAD_UP}, {"down", RETRO_DEVICE_ID_JOYPAD_DOWN},
        {"left", RETRO_DEVICE_ID_JOYPAD_LEFT}, {"right", RETRO_DEVICE_ID_JOYPAD_RIGHT},
        {"a", RETRO_DEVICE_ID_JOYPAD_Y}, {"b", RETRO_DEVICE_ID_JOYPAD_B},
        {"c", RETRO_DEVICE_ID_JOYPAD_A}, {"start", RETRO_DEVICE_ID_JOYPAD_START},
    };
    for (size_t i = 0; i < sizeof map / sizeof map[0]; i++)
        if (!strcmp(name, map[i].n)) return 1u << map[i].id;
    fprintf(stderr, "no button %s\n", name);
    exit(2);
}

static void read_script(const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); exit(2); }
    char line[512];
    while (fgets(line, sizeof line, f)) {
        char *t = strtok(line, " \t\r\n");
        if (!t || *t == '#') continue;
        struct press *p = &presses[n_presses++];
        p->from = atol(t);
        t = strtok(NULL, " \t\r\n");
        p->len = t ? atol(t) : 1;
        p->mask = 0;
        while ((t = strtok(NULL, " \t\r\n"))) p->mask |= button(t);
    }
    fclose(f);
}

static void write_ppm(const char *dir, long n)
{
    if (!frame_data) return;
    char path[4200];
    snprintf(path, sizeof path, "%s/%05ld.ppm", dir, n);
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); return; }
    fprintf(f, "P6\n%u %u\n255\n", frame_w, frame_h);
    for (unsigned y = 0; y < frame_h; y++) {
        const unsigned char *row = (const unsigned char *)frame_data + y * frame_pitch;
        for (unsigned x = 0; x < frame_w; x++) {
            unsigned char rgb[3];
            if (pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
                const unsigned char *p = row + x * 4;
                rgb[0] = p[2]; rgb[1] = p[1]; rgb[2] = p[0];
            } else {
                unsigned v = ((const unsigned short *)row)[x];
                if (pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
                    rgb[0] = (v >> 11 & 31) << 3; rgb[1] = (v >> 5 & 63) << 2; rgb[2] = (v & 31) << 3;
                } else {
                    rgb[0] = (v >> 10 & 31) << 3; rgb[1] = (v >> 5 & 31) << 3; rgb[2] = (v & 31) << 3;
                }
            }
            fwrite(rgb, 1, 3, f);
        }
    }
    fclose(f);
}

int main(int argc, char **argv)
{
    if (argc < 5) {
        fprintf(stderr, "gpgx-save CORE ROM OUTDIR FRAMES [--srm IN] [--input SCRIPT] [--dump F,F,...]\n");
        return 2;
    }
    const char *core = argv[1], *rom = argv[2], *out = argv[3];
    long frames = atol(argv[4]);
    const char *srm = NULL, *dump = "";
    for (int i = 5; i + 1 < argc; i += 2) {
        if (!strcmp(argv[i], "--srm")) srm = argv[i + 1];
        else if (!strcmp(argv[i], "--input")) read_script(argv[i + 1]);
        else if (!strcmp(argv[i], "--dump")) dump = argv[i + 1];
    }
    snprintf(save_dir, sizeof save_dir, "%s", out);

    void *h = dlopen(core, RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "%s\n", dlerror()); return 1; }
#define SYM(n) __typeof__(&n) n##_p = (__typeof__(&n))dlsym(h, #n); if (!n##_p) { fprintf(stderr, "no %s\n", #n); return 1; }
    SYM(retro_set_environment)
    SYM(retro_set_video_refresh)
    SYM(retro_set_audio_sample)
    SYM(retro_set_audio_sample_batch)
    SYM(retro_set_input_poll)
    SYM(retro_set_input_state)
    SYM(retro_init)
    SYM(retro_load_game)
    SYM(retro_run)
    SYM(retro_get_memory_data)
    SYM(retro_get_memory_size)
    SYM(retro_unload_game)
    SYM(retro_deinit)

    retro_set_environment_p(environment);
    retro_set_video_refresh_p(video);
    retro_set_audio_sample_p(audio);
    retro_set_audio_sample_batch_p(audio_batch);
    retro_set_input_poll_p(input_poll);
    retro_set_input_state_p(input_state);
    retro_init_p();
    struct retro_game_info info = { rom, NULL, 0, NULL };
    if (!retro_load_game_p(&info)) { fprintf(stderr, "the core would not load %s\n", rom); return 1; }

    /* RetroArch's load: at most the size the core asks before running, the rest dropped */
    if (srm) {
        FILE *f = fopen(srm, "rb");
        if (!f) { perror(srm); return 1; }
        unsigned char *mem = retro_get_memory_data_p(RETRO_MEMORY_SAVE_RAM);
        size_t cap = retro_get_memory_size_p(RETRO_MEMORY_SAVE_RAM);
        if (!mem || !cap) { fprintf(stderr, "the game has no save RAM\n"); return 1; }
        size_t n = fread(mem, 1, cap, f);
        if (fgetc(f) != EOF) fprintf(stderr, "save larger than %zu bytes: the rest dropped, as RetroArch does\n", cap);
        fclose(f);
        printf("loaded %zu bytes of %s\n", n, srm);
    }

    for (frame_no = 0; frame_no < frames; frame_no++) {
        retro_run_p();
        char key[32];
        snprintf(key, sizeof key, ",%ld,", frame_no);
        char list[8192];
        snprintf(list, sizeof list, ",%s,", dump);
        if (strstr(list, key)) write_ppm(out, frame_no);
        if (frame_no % 600 == 0) printf("%ld of %ld\n", frame_no, frames), fflush(stdout);
    }
    write_ppm(out, frames);

    /* RetroArch's write: the size the core gives now, which is Genesis Plus GX's last byte not FF */
    unsigned char *mem = retro_get_memory_data_p(RETRO_MEMORY_SAVE_RAM);
    size_t n = mem ? retro_get_memory_size_p(RETRO_MEMORY_SAVE_RAM) : 0;
    char path[4200];
    snprintf(path, sizeof path, "%s/game.srm", out);
    if (n) {
        FILE *f = fopen(path, "wb");
        fwrite(mem, 1, n, f);
        fclose(f);
        printf("wrote %zu bytes to %s\n", n, path);
    } else {
        printf("nothing to save (the save RAM is all FF): RetroArch writes no file\n");
    }
    retro_unload_game_p();
    retro_deinit_p();
    return 0;
}
