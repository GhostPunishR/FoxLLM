#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define FOXGPT_EXPORT __declspec(dllexport)
#else
#define FOXGPT_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

FOXGPT_EXPORT void* foxgpt_engine_create(void);
FOXGPT_EXPORT void foxgpt_engine_destroy(void* engine);
FOXGPT_EXPORT int32_t foxgpt_engine_load_model(void* engine, const char* model_path);
FOXGPT_EXPORT void foxgpt_engine_unload_model(void* engine);
FOXGPT_EXPORT int32_t foxgpt_engine_is_model_loaded(void* engine);
FOXGPT_EXPORT const char* foxgpt_engine_model_description(void* engine);
FOXGPT_EXPORT uint64_t foxgpt_engine_model_size_bytes(void* engine);
FOXGPT_EXPORT int32_t foxgpt_engine_model_context_size(void* engine);
FOXGPT_EXPORT char* foxgpt_engine_generate(void* engine, const char* prompt);
FOXGPT_EXPORT void foxgpt_engine_stop(void* engine);
FOXGPT_EXPORT const char* foxgpt_engine_last_error(void* engine);
FOXGPT_EXPORT const char* foxgpt_native_version(void);
FOXGPT_EXPORT void foxgpt_string_free(char* value);

#ifdef __cplusplus
}
#endif
