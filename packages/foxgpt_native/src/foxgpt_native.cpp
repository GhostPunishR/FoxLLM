// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

#include "foxgpt_native.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>

#ifdef FOXGPT_WITH_LLAMA_CPP
#include "llama.h"

#include <algorithm>
#include <memory>
#include <mutex>
#include <vector>
#endif

namespace {

struct Engine {
    std::string last_error;
    std::atomic<bool> stop_requested{false};

#ifdef FOXGPT_WITH_LLAMA_CPP
    llama_model* model = nullptr;
    std::string model_description;
    uint64_t model_size_bytes = 0;
    int32_t model_context_size = 0;
    std::mutex operation_mutex;
#else
    std::string model_path;
#endif
};

Engine* as_engine(void* engine) {
    return static_cast<Engine*>(engine);
}

#ifdef FOXGPT_WITH_LLAMA_CPP

std::once_flag backend_once;

void initialize_backend() {
    std::call_once(backend_once, []() { ggml_backend_load_all(); });
}

void unload_model(Engine* engine) {
    if (engine->model != nullptr) {
        llama_model_free(engine->model);
        engine->model = nullptr;
    }

    engine->model_description.clear();
    engine->model_size_bytes = 0;
    engine->model_context_size = 0;
    engine->stop_requested.store(false);
}

char* copy_string(const std::string& value) {
    auto* result = static_cast<char*>(std::malloc(value.size() + 1));
    if (result == nullptr) {
        return nullptr;
    }

    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

std::string token_to_piece(const llama_vocab* vocab, llama_token token) {
    char stack_buffer[256];
    int32_t written = llama_token_to_piece(
        vocab,
        token,
        stack_buffer,
        sizeof(stack_buffer),
        0,
        true);

    if (written >= 0) {
        return std::string(stack_buffer, static_cast<size_t>(written));
    }

    std::vector<char> dynamic_buffer(static_cast<size_t>(-written));
    written = llama_token_to_piece(
        vocab,
        token,
        dynamic_buffer.data(),
        static_cast<int32_t>(dynamic_buffer.size()),
        0,
        true);

    if (written < 0) {
        return {};
    }

    return std::string(dynamic_buffer.data(), static_cast<size_t>(written));
}

bool generate_internal(
    Engine* instance,
    const char* prompt,
    float temperature,
    float top_p,
    int32_t max_tokens,
    foxgpt_token_callback callback,
    void* user_data,
    std::string* collected_response) {
    if (prompt == nullptr || prompt[0] == '\0') {
        instance->last_error = "Prompt is empty.";
        return false;
    }

    if (temperature < 0.0f) {
        instance->last_error = "Temperature must be greater than or equal to zero.";
        return false;
    }

    if (top_p <= 0.0f || top_p > 1.0f) {
        instance->last_error = "Top-p must be in the interval (0, 1].";
        return false;
    }

    if (max_tokens <= 0) {
        instance->last_error = "Max tokens must be greater than zero.";
        return false;
    }

    std::lock_guard<std::mutex> lock(instance->operation_mutex);

    if (instance->model == nullptr) {
        instance->last_error = "No GGUF model is loaded.";
        return false;
    }

    const llama_vocab* vocab = llama_model_get_vocab(instance->model);
    const size_t prompt_length = std::strlen(prompt);
    const int32_t required_tokens =
        -llama_tokenize(vocab, prompt, prompt_length, nullptr, 0, true, true);

    if (required_tokens <= 0) {
        instance->last_error = "Unable to tokenize the prompt.";
        return false;
    }

    std::vector<llama_token> prompt_tokens(
        static_cast<size_t>(required_tokens));
    const int32_t tokenized = llama_tokenize(
        vocab,
        prompt,
        prompt_length,
        prompt_tokens.data(),
        required_tokens,
        true,
        true);

    if (tokenized < 0) {
        instance->last_error = "Unable to tokenize the prompt.";
        return false;
    }

    int32_t predict_tokens = max_tokens;
    const int32_t trained_context = llama_model_n_ctx_train(instance->model);

    if (trained_context > 0) {
        const int32_t available = trained_context - required_tokens;
        if (available <= 0) {
            instance->last_error = "Prompt exceeds the model context window.";
            return false;
        }
        predict_tokens = std::min(predict_tokens, available);
    }

    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(required_tokens + predict_tokens);
    context_params.n_batch = static_cast<uint32_t>(required_tokens);
    context_params.no_perf = true;

    std::unique_ptr<llama_context, decltype(&llama_free)> context(
        llama_init_from_model(instance->model, context_params),
        &llama_free);
    if (!context) {
        instance->last_error = "llama.cpp could not create an inference context.";
        return false;
    }

    auto sampler_params = llama_sampler_chain_default_params();
    sampler_params.no_perf = true;
    std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(
        llama_sampler_chain_init(sampler_params),
        &llama_sampler_free);
    if (!sampler) {
        instance->last_error = "llama.cpp could not create a sampler.";
        return false;
    }

    if (temperature <= 0.0f) {
        llama_sampler_chain_add(sampler.get(), llama_sampler_init_greedy());
    } else {
        if (top_p < 1.0f) {
            llama_sampler_chain_add(
                sampler.get(),
                llama_sampler_init_top_p(top_p, 1));
        }
        llama_sampler_chain_add(
            sampler.get(),
            llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(
            sampler.get(),
            llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }

    llama_batch batch = llama_batch_get_one(
        prompt_tokens.data(),
        static_cast<int32_t>(prompt_tokens.size()));

    llama_token decoder_start_token = LLAMA_TOKEN_NULL;
    if (llama_model_has_encoder(instance->model)) {
        if (llama_encode(context.get(), batch) != 0) {
            instance->last_error = "llama.cpp failed to encode the prompt.";
            return false;
        }

        decoder_start_token = llama_model_decoder_start_token(instance->model);
        if (decoder_start_token == LLAMA_TOKEN_NULL) {
            decoder_start_token = llama_vocab_bos(vocab);
        }
        batch = llama_batch_get_one(&decoder_start_token, 1);
    }

    int32_t position = 0;
    const int32_t generation_limit = required_tokens + predict_tokens;

    while (position + batch.n_tokens < generation_limit) {
        if (instance->stop_requested.load()) {
            break;
        }

        if (llama_decode(context.get(), batch) != 0) {
            instance->last_error = "llama.cpp failed while decoding.";
            return false;
        }

        position += batch.n_tokens;
        llama_token token = llama_sampler_sample(sampler.get(), context.get(), -1);
        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        const std::string piece = token_to_piece(vocab, token);
        if (collected_response != nullptr) {
            collected_response->append(piece);
        }
        if (callback != nullptr) {
            callback(
                reinterpret_cast<const uint8_t*>(piece.data()),
                static_cast<int32_t>(piece.size()),
                user_data);
        }

        batch = llama_batch_get_one(&token, 1);
    }

    instance->last_error.clear();
    return true;
}

#endif

}  // namespace

extern "C" {

void* foxgpt_engine_create(void) {
    return new (std::nothrow) Engine();
}

void foxgpt_engine_destroy(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return;
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    {
        std::lock_guard<std::mutex> lock(instance->operation_mutex);
        unload_model(instance);
    }
#endif

    delete instance;
}

int32_t foxgpt_engine_load_model(void* engine, const char* model_path) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

    if (model_path == nullptr || model_path[0] == '\0') {
        instance->last_error = "Model path is empty.";
        return 0;
    }

    instance->stop_requested.store(false);

#ifdef FOXGPT_WITH_LLAMA_CPP
    std::lock_guard<std::mutex> lock(instance->operation_mutex);
    initialize_backend();
    unload_model(instance);

    llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0;

    instance->model = llama_model_load_from_file(model_path, params);
    if (instance->model == nullptr) {
        instance->last_error = "llama.cpp could not load the GGUF model.";
        return 0;
    }

    char description[256] = {0};
    llama_model_desc(instance->model, description, sizeof(description));
    instance->model_description = description;
    instance->model_size_bytes = llama_model_size(instance->model);
    instance->model_context_size = llama_model_n_ctx_train(instance->model);
    instance->last_error.clear();
    return 1;
#else
    instance->model_path = model_path;
    instance->last_error =
        "llama.cpp local inference is currently available only on Android arm64.";
    return 0;
#endif
}

void foxgpt_engine_unload_model(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return;
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    std::lock_guard<std::mutex> lock(instance->operation_mutex);
    unload_model(instance);
#else
    instance->model_path.clear();
    instance->stop_requested.store(false);
#endif

    instance->last_error.clear();
}

int32_t foxgpt_engine_is_model_loaded(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    return instance->model != nullptr ? 1 : 0;
#else
    return 0;
#endif
}

const char* foxgpt_engine_model_description(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return "";
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    return instance->model_description.c_str();
#else
    return "";
#endif
}

uint64_t foxgpt_engine_model_size_bytes(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    return instance->model_size_bytes;
#else
    return 0;
#endif
}

int32_t foxgpt_engine_model_context_size(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    return instance->model_context_size;
#else
    return 0;
#endif
}

char* foxgpt_engine_generate(void* engine, const char* prompt) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return nullptr;
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    instance->stop_requested.store(false);
    std::string response;
    if (!generate_internal(
            instance,
            prompt,
            0.0f,
            1.0f,
            128,
            nullptr,
            nullptr,
            &response)) {
        return nullptr;
    }
    return copy_string(response);
#else
    if (prompt == nullptr || prompt[0] == '\0') {
        instance->last_error = "Prompt is empty.";
    } else {
        instance->last_error =
            "llama.cpp local inference is currently available only on Android arm64.";
    }
    return nullptr;
#endif
}

int32_t foxgpt_engine_generate_stream(
    void* engine,
    const char* prompt,
    float temperature,
    float top_p,
    int32_t max_tokens,
    foxgpt_token_callback callback,
    void* user_data) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

    if (callback == nullptr) {
        instance->last_error = "Token callback is null.";
        return 0;
    }

#ifdef FOXGPT_WITH_LLAMA_CPP
    return generate_internal(
               instance,
               prompt,
               temperature,
               top_p,
               max_tokens,
               callback,
               user_data,
               nullptr)
        ? 1
        : 0;
#else
    (void) temperature;
    (void) top_p;
    (void) max_tokens;
    (void) user_data;
    if (prompt == nullptr || prompt[0] == '\0') {
        instance->last_error = "Prompt is empty.";
    } else {
        instance->last_error =
            "llama.cpp local inference is currently available only on Android arm64.";
    }
    return 0;
#endif
}

void foxgpt_engine_reset_stop(void* engine) {
    auto* instance = as_engine(engine);
    if (instance != nullptr) {
        instance->stop_requested.store(false);
    }
}

void foxgpt_engine_stop(void* engine) {
    auto* instance = as_engine(engine);
    if (instance != nullptr) {
        instance->stop_requested.store(true);
    }
}

const char* foxgpt_engine_last_error(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return "Invalid native engine handle.";
    }
    return instance->last_error.c_str();
}

const char* foxgpt_native_version(void) {
#ifdef FOXGPT_WITH_LLAMA_CPP
    return "foxgpt-native/0.3.0+llama-b10903";
#else
    return "foxgpt-native/0.3.0+stub";
#endif
}

void foxgpt_string_free(char* value) {
    std::free(value);
}

}  // extern "C"
