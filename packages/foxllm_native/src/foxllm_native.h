// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define FOXLLM_EXPORT __declspec(dllexport)
#else
#define FOXLLM_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*foxllm_token_callback)(
    const uint8_t* bytes,
    int32_t length,
    void* user_data);

FOXLLM_EXPORT void* foxllm_engine_create(void);
FOXLLM_EXPORT void foxllm_engine_destroy(void* engine);
FOXLLM_EXPORT int32_t foxllm_engine_load_model(void* engine, const char* model_path);
FOXLLM_EXPORT void foxllm_engine_unload_model(void* engine);
FOXLLM_EXPORT int32_t foxllm_engine_is_model_loaded(void* engine);
FOXLLM_EXPORT const char* foxllm_engine_model_description(void* engine);
FOXLLM_EXPORT uint64_t foxllm_engine_model_size_bytes(void* engine);
FOXLLM_EXPORT int32_t foxllm_engine_model_context_size(void* engine);
FOXLLM_EXPORT char* foxllm_engine_apply_chat_template(
    void* engine,
    const char* const* roles,
    const char* const* contents,
    int32_t message_count,
    int32_t add_assistant);
FOXLLM_EXPORT char* foxllm_engine_generate(void* engine, const char* prompt);
FOXLLM_EXPORT int32_t foxllm_engine_generate_stream(
    void* engine,
    const char* prompt,
    float temperature,
    float top_p,
    int32_t max_tokens,
    foxllm_token_callback callback,
    void* user_data);
FOXLLM_EXPORT void foxllm_engine_reset_stop(void* engine);
FOXLLM_EXPORT void foxllm_engine_stop(void* engine);
FOXLLM_EXPORT const char* foxllm_engine_last_error(void* engine);
FOXLLM_EXPORT const char* foxllm_native_version(void);
FOXLLM_EXPORT void foxllm_string_free(char* value);

#ifdef __cplusplus
}
#endif
