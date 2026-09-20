// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

#include "foxllm_native.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#ifdef FOXLLM_WITH_LLAMA_CPP
#include "llama.h"

#include <memory>
#include <mutex>
#include <thread>
#endif

namespace {

struct Engine {
    std::string last_error;
    std::atomic<bool> stop_requested{false};

#ifdef FOXLLM_WITH_LLAMA_CPP
    llama_model* model = nullptr;
    std::string model_description;
    uint64_t model_size_bytes = 0;
    int32_t model_context_size = 0;
    std::mutex operation_mutex;

    // Contexte d'inférence gardé d'une génération à l'autre, avec les jetons
    // qu'il a déjà lus.
    //
    // Sans lui, chaque message recommençait la conversation entière : le
    // contexte était créé puis jeté à chaque réponse, donc tout le fil était
    // relu depuis le début. Le coût croissait avec la longueur de la
    // conversation, et c'était le poste dominant sur un téléphone.
    //
    // Une conversation ne fait qu'allonger son début : le prompt du tour
    // suivant commence par celui du tour précédent. Garder le contexte permet
    // de ne relire que ce qui a changé.
    llama_context* context = nullptr;

    // Jetons présents dans le cache du contexte, dans l'ordre. C'est la seule
    // source de vérité : ce qui n'y figure pas n'a pas été lu.
    std::vector<llama_token> cached_tokens;
#else
    std::string model_path;
#endif
};

Engine* as_engine(void* engine) {
    return static_cast<Engine*>(engine);
}

char* copy_string(const std::string& value) {
    auto* result = static_cast<char*>(std::malloc(value.size() + 1));
    if (result == nullptr) {
        return nullptr;
    }

    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

// Repli quand le GGUF ne porte pas de gabarit de conversation : ChatML est le
// format le plus répandu, et celui que la plupart des modèles récents
// reconnaissent même sans y avoir été entraînés.
// Neutralise les balises de tour de parole d'un texte recopié dans le prompt.
//
// Sans cela, un message contenant `<|im_end|>` ferme son propre tour et
// ouvre ce qu'il veut derrière : de quoi faire passer une instruction pour
// une consigne système, ou une invention pour une réponse du modèle. Le
// caractère inséré casse la balise sans rien retirer au sens du texte, que
// le modèle lit toujours.
std::string escape_chatml(const char* text) {
    static const char* const markers[] = {"<|im_start|>", "<|im_end|>"};
    std::string escaped = text != nullptr ? text : "";
    for (const char* marker : markers) {
        const std::string needle(marker);
        const std::string replacement = needle.substr(0, 2) + " " + needle.substr(2);
        size_t position = escaped.find(needle);
        while (position != std::string::npos) {
            escaped.replace(position, needle.size(), replacement);
            position = escaped.find(needle, position + replacement.size());
        }
    }
    return escaped;
}

std::string chatml_prompt(
    const char* const* roles,
    const char* const* contents,
    int32_t message_count,
    bool add_assistant) {
    std::string prompt;
    for (int32_t index = 0; index < message_count; ++index) {
        const char* role = roles[index] != nullptr ? roles[index] : "user";
        prompt += "<|im_start|>";
        prompt += escape_chatml(role);
        prompt += '\n';
        prompt += escape_chatml(contents[index]);
        prompt += "<|im_end|>\n";
    }

    if (add_assistant) {
        prompt += "<|im_start|>assistant\n";
    }

    return prompt;
}

// Contexte minimal demandé, même pour une question d'une ligne.
//
// En dessous, la première réponse un peu longue déborde et force à tout
// relire : le cache ne servirait jamais.
constexpr uint32_t kMinimumContextSize = 1024;

// Longueur du début commun à deux suites de jetons.
//
// C'est tout le cache : ce début est déjà lu par le contexte, seul ce qui
// suit doit l'être. Une réponse ajoutée au fil laisse intact le début du
// prompt suivant, d'où un préfixe qui couvre presque toute la conversation.
//
// Pure et hors du bloc llama.cpp, donc vérifiable par un test ordinaire,
// sans modèle, sans appareil et sans la bibliothèque. D'où le
// `maybe_unused` : la compilation du bouchon la voit sans l'appeler.
[[maybe_unused]] size_t common_prefix_length(
    const std::vector<int32_t>& cached,
    const std::vector<int32_t>& wanted) {
    const size_t limit = std::min(cached.size(), wanted.size());
    size_t shared = 0;
    while (shared < limit && cached[shared] == wanted[shared]) {
        ++shared;
    }
    return shared;
}

// Taille de contexte à demander pour tenir [needed] jetons.
//
// Ni trop grand ni trop juste. Trop grand, le cache réserve d'avance des
// centaines de mégaoctets qu'un téléphone n'a pas. Trop juste, la moindre
// réponse déborde et force à tout relire, ce qui annule le cache.
//
// D'où le doublement : le contexte suit la conversation par paliers, et
// change assez rarement pour que le cache serve entre deux.
[[maybe_unused]] uint32_t context_size_for(
    uint32_t current, uint32_t needed, uint32_t trained) {
    uint32_t target = std::max(needed, kMinimumContextSize);
    if (current > 0) {
        target = std::max(target, current * 2);
    }
    if (trained > 0) {
        target = std::min(target, trained);
        target = std::max(target, std::min(needed, trained));
    }
    return target;
}

#ifdef FOXLLM_WITH_LLAMA_CPP

// Nombre de threads de calcul, faute de valeur par défaut utilisable.
//
// `llama_context_default_params` en pose quatre quel que soit l'appareil, et
// llama.cpp note lui-même « TODO: better default » à cet endroit. Sur un
// téléphone à huit cœurs le compte tombe juste par hasard, mais il
// sursouscrit un appareil à deux cœurs et n'utilise qu'un tiers d'une tablette
// à douze.
//
// La règle appliquée ici est celle que llama.cpp retient pour ARM et Android :
// tous les cœurs jusqu'à quatre, la moitié au delà. Les cœurs lents d'un SoC
// mobile ne l'accélèrent pas, car ggml répartit chaque couche en parts égales
// et attend la plus lente.
// Taille d'un lot de lecture.
//
// Le contexte fixe cette taille une fois pour toutes, et un prompt plus long
// se lit en plusieurs lots. Sans ce découpage, un long fil échouerait faute
// de place dans un seul lot ; trop grand, il gonflerait les tampons de calcul
// sans rien accélérer sur un téléphone.
constexpr uint32_t kDecodeBatchSize = 512;

int32_t math_thread_count() {
    const unsigned int cores = std::thread::hardware_concurrency();
    if (cores == 0) {
        return 4;
    }
    return static_cast<int32_t>(cores <= 4 ? cores : cores / 2);
}

std::once_flag backend_once;

void initialize_backend() {
    std::call_once(backend_once, []() { ggml_backend_load_all(); });
}

// Libère le contexte et oublie ce qu'il contenait.
//
// Les deux vont ensemble : un cache décrit l'état d'un contexte précis, et
// survivrait à sa destruction en décrivant un état qui n'existe plus.
void release_context(Engine* engine) {
    if (engine->context != nullptr) {
        llama_free(engine->context);
        engine->context = nullptr;
    }
    engine->cached_tokens.clear();
}

void unload_model(Engine* engine) {
    release_context(engine);
    if (engine->model != nullptr) {
        llama_model_free(engine->model);
        engine->model = nullptr;
    }

    engine->model_description.clear();
    engine->model_size_bytes = 0;
    engine->model_context_size = 0;
    engine->stop_requested.store(false);
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

// Lit une suite de jetons et l'inscrit au cache.
//
// Découpée en lots : un contexte a une taille de lot fixe, et un prompt plus
// long que ce lot échouerait sans ce découpage. Le cache n'avance que de ce
// qui a été lu, afin qu'un échec au milieu ne laisse pas croire que la suite
// l'a été.
bool decode_tokens(
    Engine* instance,
    const llama_token* tokens,
    size_t count,
    uint32_t batch_size) {
    const size_t step = batch_size > 0 ? static_cast<size_t>(batch_size) : 1;
    size_t offset = 0;
    std::vector<llama_token> chunk;

    while (offset < count) {
        const size_t taken = std::min(step, count - offset);
        chunk.assign(tokens + offset, tokens + offset + taken);
        llama_batch batch =
            llama_batch_get_one(chunk.data(), static_cast<int32_t>(taken));
        const int32_t status = llama_decode(instance->context, batch);
        if (status != 0) {
            // Le contexte peut avoir gardé une partie du lot : le jeter en
            // entier est la seule façon d'être sûr de ce qu'il contient.
            release_context(instance);
            instance->last_error = status == 1
                ? "llama.cpp ran out of context while reading the prompt."
                : "llama.cpp failed while decoding.";
            return false;
        }
        instance->cached_tokens.insert(
            instance->cached_tokens.end(),
            chunk.begin(),
            chunk.end());
        offset += taken;
    }

    return true;
}

bool generate_internal(
    Engine* instance,
    const char* prompt,
    float temperature,
    float top_p,
    int32_t max_tokens,
    foxllm_token_callback callback,
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

    // Les modèles encodeur-décodeur relisent tout leur prompt par l'encodeur :
    // il n'y a rien à garder d'un tour sur l'autre. Le contexte repart donc à
    // neuf pour eux, comme avant le cache.
    const bool has_encoder = llama_model_has_encoder(instance->model);
    if (has_encoder) {
        release_context(instance);
    }

    const uint32_t needed =
        static_cast<uint32_t>(required_tokens) +
        static_cast<uint32_t>(predict_tokens);
    const uint32_t existing =
        instance->context != nullptr ? llama_n_ctx(instance->context) : 0;

    if (instance->context == nullptr || existing < needed) {
        // Le contexte ne peut pas grandir sur place : il est refait, et le
        // cache repart de zéro. Le doublement de `context_size_for` est ce qui
        // rend ce passage rare.
        release_context(instance);

        // Deux tentatives : cache quantifié d'abord, cache ordinaire ensuite.
        //
        // En `q8_0`, le cache tient dans la moitié de la mémoire d'un cache en
        // `f16` : à mémoire égale, c'est deux fois plus de conversation qu'un
        // téléphone peut garder, et la perte de qualité est négligeable à huit
        // bits.
        //
        // Mais llama.cpp marque ces deux réglages comme expérimentaux, et le
        // cache V quantifié demande l'attention flash, que tous les appareils
        // n'offrent pas. Sans repli, un téléphone qui la refuse se retrouverait
        // sans moteur local du tout : le gain ne vaut pas ce risque, la
        // seconde tentative le supprime.
        for (int attempt = 0; attempt < 2 && instance->context == nullptr;
             ++attempt) {
            llama_context_params context_params =
                llama_context_default_params();
            context_params.n_ctx = context_size_for(
                existing,
                needed,
                trained_context > 0 ? static_cast<uint32_t>(trained_context)
                                    : 0);
            context_params.n_batch =
                std::min<uint32_t>(context_params.n_ctx, kDecodeBatchSize);
            context_params.no_perf = true;

            // La lecture du prompt et l'écriture de la réponse ne sollicitent
            // pas la machine de la même façon : la première est du calcul
            // matriciel qui profite des cœurs, la seconde relit tous les poids
            // par jeton et bute sur la bande passante mémoire. llama.cpp leur
            // donne néanmoins le même compte sur mobile, faute qu'ajouter des
            // threads au décodage y gagne quoi que ce soit.
            const int32_t threads = math_thread_count();
            context_params.n_threads = threads;
            context_params.n_threads_batch = threads;

            if (attempt == 0) {
                context_params.type_k = GGML_TYPE_Q8_0;
                context_params.type_v = GGML_TYPE_Q8_0;
            }

            instance->context =
                llama_init_from_model(instance->model, context_params);
        }

        if (instance->context == nullptr) {
            instance->last_error =
                "llama.cpp could not create an inference context.";
            return false;
        }
    }

    const uint32_t batch_size = llama_n_batch(instance->context);
    llama_memory_t memory = llama_get_memory(instance->context);

    // Ce que le contexte a déjà lu et qui sert encore.
    size_t shared = has_encoder
        ? 0
        : common_prefix_length(instance->cached_tokens, prompt_tokens);

    // Il faut au moins un jeton à lire pour obtenir de quoi échantillonner :
    // un prompt entièrement en cache verrait sinon sa dernière position sans
    // logits. Relire son dernier jeton coûte une position, pas la
    // conversation.
    if (shared > 0 && shared == prompt_tokens.size()) {
        shared -= 1;
    }

    if (shared < instance->cached_tokens.size()) {
        if (llama_memory_seq_rm(
                memory,
                0,
                static_cast<llama_pos>(shared),
                -1)) {
            instance->cached_tokens.resize(shared);
        } else {
            // Un retrait partiel refusé ne laisse pas de demi-mesure : le
            // cache entier est jeté plutôt que d'être décrit à tort.
            llama_memory_clear(memory, true);
            instance->cached_tokens.clear();
            shared = 0;
        }
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

    if (has_encoder) {
        llama_batch encoder_batch = llama_batch_get_one(
            prompt_tokens.data(),
            static_cast<int32_t>(prompt_tokens.size()));
        if (llama_encode(instance->context, encoder_batch) != 0) {
            instance->last_error = "llama.cpp failed to encode the prompt.";
            return false;
        }

        llama_token decoder_start_token =
            llama_model_decoder_start_token(instance->model);
        if (decoder_start_token == LLAMA_TOKEN_NULL) {
            decoder_start_token = llama_vocab_bos(vocab);
        }
        if (!decode_tokens(instance, &decoder_start_token, 1, batch_size)) {
            return false;
        }
    } else if (!decode_tokens(
                   instance,
                   prompt_tokens.data() + shared,
                   prompt_tokens.size() - shared,
                   batch_size)) {
        return false;
    }

    int32_t generated = 0;
    while (generated < predict_tokens) {
        if (instance->stop_requested.load()) {
            break;
        }

        const llama_token sampled =
            llama_sampler_sample(sampler.get(), instance->context, -1);
        if (llama_vocab_is_eog(vocab, sampled)) {
            break;
        }

        const std::string piece = token_to_piece(vocab, sampled);
        if (collected_response != nullptr) {
            collected_response->append(piece);
        }
        if (callback != nullptr) {
            callback(
                reinterpret_cast<const uint8_t*>(piece.data()),
                static_cast<int32_t>(piece.size()),
                user_data);
        }

        generated += 1;
        if (generated >= predict_tokens) {
            // Le dernier jeton rendu n'a pas besoin d'être lu : plus rien ne
            // sera échantillonné après lui. Le tour suivant le relira avec le
            // reste de la réponse, une position à payer plutôt qu'une lecture
            // pour rien.
            break;
        }

        if (!decode_tokens(instance, &sampled, 1, batch_size)) {
            return false;
        }
    }

    instance->last_error.clear();
    return true;
}

#endif

}  // namespace

extern "C" {

void* foxllm_engine_create(void) {
    return new (std::nothrow) Engine();
}

void foxllm_engine_destroy(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    {
        std::lock_guard<std::mutex> lock(instance->operation_mutex);
        unload_model(instance);
    }
#endif

    delete instance;
}

int32_t foxllm_engine_load_model(void* engine, const char* model_path) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

    if (model_path == nullptr || model_path[0] == '\0') {
        instance->last_error = "Model path is empty.";
        return 0;
    }

    instance->stop_requested.store(false);

#ifdef FOXLLM_WITH_LLAMA_CPP
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

void foxllm_engine_unload_model(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    std::lock_guard<std::mutex> lock(instance->operation_mutex);
    unload_model(instance);
#else
    instance->model_path.clear();
    instance->stop_requested.store(false);
#endif

    instance->last_error.clear();
}

int32_t foxllm_engine_is_model_loaded(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    return instance->model != nullptr ? 1 : 0;
#else
    return 0;
#endif
}

const char* foxllm_engine_model_description(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return "";
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    return instance->model_description.c_str();
#else
    return "";
#endif
}

uint64_t foxllm_engine_model_size_bytes(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    return instance->model_size_bytes;
#else
    return 0;
#endif
}

int32_t foxllm_engine_model_context_size(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    return instance->model_context_size;
#else
    return 0;
#endif
}

char* foxllm_engine_apply_chat_template(
    void* engine,
    const char* const* roles,
    const char* const* contents,
    int32_t message_count,
    int32_t add_assistant) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return nullptr;
    }

    if (roles == nullptr || contents == nullptr || message_count <= 0) {
        instance->last_error = "No message to format.";
        return nullptr;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    std::lock_guard<std::mutex> lock(instance->operation_mutex);
    if (instance->model == nullptr) {
        instance->last_error = "No model is loaded.";
        return nullptr;
    }

    // Chaque modèle a sa propre façon de baliser les tours de parole. Le
    // gabarit est écrit dans le GGUF : l'utiliser est ce qui fait que le
    // modèle reconnaît la fin de son tour et s'arrête sur son jeton de fin,
    // au lieu de continuer en inventant la suite du dialogue.
    const char* chat_template = llama_model_chat_template(instance->model, nullptr);
    if (chat_template == nullptr) {
        instance->last_error.clear();
        return copy_string(
            chatml_prompt(roles, contents, message_count, add_assistant != 0));
    }

    std::vector<llama_chat_message> chat;
    chat.reserve(static_cast<size_t>(message_count));
    for (int32_t index = 0; index < message_count; ++index) {
        chat.push_back(llama_chat_message{
            roles[index] != nullptr ? roles[index] : "user",
            contents[index] != nullptr ? contents[index] : ""});
    }

    std::vector<char> buffer(4096);
    int32_t written = llama_chat_apply_template(
        chat_template,
        chat.data(),
        chat.size(),
        add_assistant != 0,
        buffer.data(),
        static_cast<int32_t>(buffer.size()));

    if (written > static_cast<int32_t>(buffer.size())) {
        buffer.resize(static_cast<size_t>(written));
        written = llama_chat_apply_template(
            chat_template,
            chat.data(),
            chat.size(),
            add_assistant != 0,
            buffer.data(),
            static_cast<int32_t>(buffer.size()));
    }

    if (written < 0) {
        // Gabarit non reconnu par llama.cpp : mieux vaut ChatML qu'un échec,
        // l'utilisateur veut discuter avec son modèle, pas lire une erreur.
        instance->last_error.clear();
        return copy_string(
            chatml_prompt(roles, contents, message_count, add_assistant != 0));
    }

    instance->last_error.clear();
    return copy_string(std::string(buffer.data(), static_cast<size_t>(written)));
#else
    instance->last_error.clear();
    return copy_string(
        chatml_prompt(roles, contents, message_count, add_assistant != 0));
#endif
}

char* foxllm_engine_generate(void* engine, const char* prompt) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return nullptr;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
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

int32_t foxllm_engine_generate_stream(
    void* engine,
    const char* prompt,
    float temperature,
    float top_p,
    int32_t max_tokens,
    foxllm_token_callback callback,
    void* user_data) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return 0;
    }

    if (callback == nullptr) {
        instance->last_error = "Token callback is null.";
        return 0;
    }

#ifdef FOXLLM_WITH_LLAMA_CPP
    // Comme `foxllm_engine_generate`. Sans cette remise à zéro, une
    // génération arrêtée laissait le drapeau levé : la suivante sortait de sa
    // boucle au premier tour et rendait une réponse vide, sans erreur pour
    // l'expliquer. Le worker Dart appelle bien `reset_stop` avant chaque
    // génération, mais faire dépendre la correction d'un appelant discipliné
    // n'est pas une garantie.
    instance->stop_requested.store(false);
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

void foxllm_engine_reset_stop(void* engine) {
    auto* instance = as_engine(engine);
    if (instance != nullptr) {
        instance->stop_requested.store(false);
    }
}

void foxllm_engine_stop(void* engine) {
    auto* instance = as_engine(engine);
    if (instance != nullptr) {
        instance->stop_requested.store(true);
    }
}

const char* foxllm_engine_last_error(void* engine) {
    auto* instance = as_engine(engine);
    if (instance == nullptr) {
        return "Invalid native engine handle.";
    }
    return instance->last_error.c_str();
}

const char* foxllm_native_version(void) {
#ifdef FOXLLM_WITH_LLAMA_CPP
    return "foxllm-native/0.4.0+llama-b10903";
#else
    return "foxllm-native/0.4.0+stub";
#endif
}

void foxllm_string_free(char* value) {
    std::free(value);
}

}  // extern "C"
