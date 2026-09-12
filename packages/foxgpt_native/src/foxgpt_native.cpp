#include "foxgpt_native.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

struct Engine {
    std::string last_error;
    std::string model_path;
    std::atomic<bool> stop_requested{false};
};

char* duplicate_string(const std::string& value) {
    auto* result = static_cast<char*>(std::malloc(value.size() + 1));
    if (result == nullptr) {
        return nullptr;
    }

    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

Engine* as_engine(void* engine) {
    return static_cast<Engine*>(engine);
}

}  // namespace

extern "C" {

void* foxgpt_engine_create(void) {
    return new Engine();
}

void foxgpt_engine_destroy(void* engine) {
    delete as_engine(engine);
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

    instance->model_path = model_path;
    instance->last_error =
        "Native bridge is ready, but llama.cpp is not linked yet.";
    return 0;
}

char* foxgpt_engine_generate(void* engine, const char* prompt) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return nullptr;
    }

    if (prompt == nullptr || prompt[0] == '\0') {
        instance->last_error = "Prompt is empty.";
        return nullptr;
    }

    instance->last_error =
        "Generation is unavailable until llama.cpp is integrated.";
    return nullptr;
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
    return "foxgpt-native/0.1.0";
}

void foxgpt_string_free(char* value) {
    std::free(value);
}

}  // extern "C"
