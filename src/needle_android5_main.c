/*
 * needle_android5_main.c
 *
 * Minimal Android 5.x / ARMv7 command-line wrapper for the official
 * Cactus Needle 2 static library.
 *
 * Uses the public native API:
 *   needle_load()
 *   needle_init()
 *   needle_complete()
 *   needle_reset()
 *
 * Build with build_android5.sh.
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "needle.h"

static void usage(const char *prog) {
    fprintf(stderr,
        "Needle 2 Android-5 ARMv7 wrapper\n"
        "\n"
        "Usage:\n"
        "  %s --help\n"
        "  %s --model needle2.cact --tools tools.json --prompt \"...\" [options]\n"
        "\n"
        "Options:\n"
        "  --model FILE         Needle .cact archive (required for inference)\n"
        "  --tools FILE         tools JSON file (required for this test wrapper)\n"
        "  --prompt TEXT        user input (required for inference)\n"
        "  --system TEXT        optional system prompt (default: empty)\n"
        "  --tool-index FILE    optional persisted tool-index path\n"
        "  --max-tokens N       maximum generated tokens (default: 128)\n"
        "  --help               print this help and exit\n",
        prog, prog);
}

static unsigned char *read_binary_file(const char *path, unsigned long long *size_out) {
    FILE *f;
    long n_long;
    size_t n;
    unsigned char *buf;

    *size_out = 0;

    f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "ERROR: cannot open model '%s': %s\n",
                path, strerror(errno));
        return NULL;
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fprintf(stderr, "ERROR: fseek failed for '%s'\n", path);
        fclose(f);
        return NULL;
    }

    n_long = ftell(f);
    if (n_long <= 0) {
        fprintf(stderr, "ERROR: invalid/empty model '%s'\n", path);
        fclose(f);
        return NULL;
    }

    if (fseek(f, 0, SEEK_SET) != 0) {
        fprintf(stderr, "ERROR: rewind failed for '%s'\n", path);
        fclose(f);
        return NULL;
    }

    n = (size_t)n_long;
    buf = (unsigned char *)malloc(n);
    if (!buf) {
        fprintf(stderr, "ERROR: cannot allocate %lu bytes for model\n",
                (unsigned long)n);
        fclose(f);
        return NULL;
    }

    if (fread(buf, 1, n, f) != n) {
        fprintf(stderr, "ERROR: short read for model '%s'\n", path);
        free(buf);
        fclose(f);
        return NULL;
    }

    fclose(f);
    *size_out = (unsigned long long)n;
    return buf;
}

static char *read_text_file(const char *path) {
    FILE *f;
    long n_long;
    size_t n;
    char *buf;

    f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "ERROR: cannot open text file '%s': %s\n",
                path, strerror(errno));
        return NULL;
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }

    n_long = ftell(f);
    if (n_long < 0) {
        fclose(f);
        return NULL;
    }

    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }

    n = (size_t)n_long;
    buf = (char *)malloc(n + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }

    if (n && fread(buf, 1, n, f) != n) {
        free(buf);
        fclose(f);
        return NULL;
    }

    fclose(f);
    buf[n] = '\0';
    return buf;
}

static int parse_positive_int(const char *s, int fallback) {
    char *end = NULL;
    long v;

    if (!s || !*s) return fallback;

    v = strtol(s, &end, 10);
    if (!end || *end != '\0' || v <= 0 || v > 4096) {
        return fallback;
    }
    return (int)v;
}

int main(int argc, char **argv) {
    const char *model_path = NULL;
    const char *tools_path = NULL;
    const char *prompt = NULL;
    const char *system_prompt = "";
    const char *tool_index_path = NULL;
    int max_tokens = 128;

    unsigned char *model = NULL;
    unsigned long long model_size = 0;
    char *tools_json = NULL;
    char *output = NULL;
    int rc;
    int i;

    if (argc == 1) {
        usage(argv[0]);
        return 0;
    }

    for (i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            usage(argv[0]);
            return 0;
        } else if (!strcmp(argv[i], "--model") && i + 1 < argc) {
            model_path = argv[++i];
        } else if (!strcmp(argv[i], "--tools") && i + 1 < argc) {
            tools_path = argv[++i];
        } else if (!strcmp(argv[i], "--prompt") && i + 1 < argc) {
            prompt = argv[++i];
        } else if (!strcmp(argv[i], "--system") && i + 1 < argc) {
            system_prompt = argv[++i];
        } else if (!strcmp(argv[i], "--tool-index") && i + 1 < argc) {
            tool_index_path = argv[++i];
        } else if (!strcmp(argv[i], "--max-tokens") && i + 1 < argc) {
            max_tokens = parse_positive_int(argv[++i], 128);
        } else {
            fprintf(stderr, "ERROR: unknown/incomplete option: %s\n", argv[i]);
            usage(argv[0]);
            return 2;
        }
    }

    if (!model_path || !tools_path || !prompt) {
        fprintf(stderr, "ERROR: --model, --tools and --prompt are required.\n\n");
        usage(argv[0]);
        return 2;
    }

    fprintf(stderr, "[1/4] Loading model file: %s\n", model_path);
    model = read_binary_file(model_path, &model_size);
    if (!model) return 3;
    fprintf(stderr, "      model bytes: %llu\n", model_size);

    fprintf(stderr, "[2/4] Loading tools file: %s\n", tools_path);
    tools_json = read_text_file(tools_path);
    if (!tools_json) {
        free(model);
        return 4;
    }

    fprintf(stderr, "[3/4] needle_load()...\n");
    rc = needle_load(model, model_size);
    fprintf(stderr, "      needle_load rc=%d\n", rc);
    if (rc < 0) {
        fprintf(stderr, "ERROR: needle_load failed\n");
        free(tools_json);
        free(model);
        return 5;
    }

    fprintf(stderr, "      needle_init()...\n");
    rc = needle_init(system_prompt, tools_json, tool_index_path);
    fprintf(stderr, "      needle_init rc=%d\n", rc);
    if (rc < 0) {
        fprintf(stderr, "ERROR: needle_init failed\n");
        needle_reset();
        free(tools_json);
        free(model);
        return 6;
    }

    /*
     * Tool-call JSON is normally small. 64 KiB is deliberately generous
     * while still being harmless on the Lenovo's 1 GiB RAM.
     */
    output = (char *)calloc(1, 65536);
    if (!output) {
        fprintf(stderr, "ERROR: output allocation failed\n");
        needle_reset();
        free(tools_json);
        free(model);
        return 7;
    }

    fprintf(stderr, "[4/4] needle_complete(max_tokens=%d)...\n", max_tokens);
    rc = needle_complete(prompt, max_tokens, output, 65536);
    fprintf(stderr, "      needle_complete rc=%d\n", rc);

    if (rc < 0) {
        fprintf(stderr, "ERROR: needle_complete failed\n");
        free(output);
        needle_reset();
        free(tools_json);
        free(model);
        return 8;
    }

    printf("%s\n", output);

    free(output);
    needle_reset();
    free(tools_json);
    free(model);
    return 0;
}
