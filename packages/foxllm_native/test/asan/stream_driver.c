/* Copyright © 2026 GhostPunishR
   SPDX-License-Identifier: AGPL-3.0-only */

/* Charge le petit modèle et demande une génération en flux : plusieurs tours
   de la boucle de décodage, donc plusieurs réutilisations du batch. */
#include <stdio.h>
#include <stdint.h>

void* foxllm_engine_create(void);
void foxllm_engine_destroy(void* engine);
int32_t foxllm_engine_load_model(void* engine, const char* path);
int32_t foxllm_engine_generate_stream(
    void* engine, const char* prompt, float temperature, float top_p,
    int32_t max_tokens,
    void (*cb)(const uint8_t*, int32_t, void*), void* user_data);
const char* foxllm_engine_last_error(void* engine);

static int tokens = 0;
static void on_token(const uint8_t* bytes, int32_t len, void* user) {
    (void)bytes; (void)len; (void)user;
    tokens++;
}

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: driver <model.gguf>\n"); return 2; }
    void* engine = foxllm_engine_create();
    if (!foxllm_engine_load_model(engine, argv[1])) {
        fprintf(stderr, "load failed: %s\n", foxllm_engine_last_error(engine));
        return 1;
    }
    int ok = foxllm_engine_generate_stream(
        engine, "bonjour", 0.0f, 1.0f, 24, on_token, NULL);
    if (ok) {
        printf("generation ok, %d tokens\n", tokens);
    } else {
        printf("generation failed\n");
    }
    if (!ok) fprintf(stderr, "%s\n", foxllm_engine_last_error(engine));
    foxllm_engine_destroy(engine);
    return ok ? 0 : 1;
}
