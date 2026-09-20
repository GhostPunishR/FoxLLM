// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

// Banc d'essai du cache KV, à travers le pont natif de FoxLLM.
//
// Le cache KV de FoxLLM n'avait jamais été vérifié à l'exécution, faute de
// modèle et d'appareil : seules la lecture du code et treize contrôles C++ sur
// les fonctions de décision le couvraient. Ce banc comble ce trou.
//
// Le principe tient en une phrase : avec un échantillonnage glouton, la
// réponse à un prompt donné ne dépend que du prompt. Un cache correct
// n'accélère que le calcul, il ne change pas un seul jeton. Donc si la réponse
// obtenue avec un cache chaud diffère de celle obtenue à froid, le cache est
// faux, et c'est la seule chose qui puisse l'expliquer.

#include "../src/foxllm_native.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

void collect(const uint8_t* bytes, int32_t length, void* user_data) {
    auto* out = static_cast<std::string*>(user_data);
    out->append(reinterpret_cast<const char*>(bytes), static_cast<size_t>(length));
}

// Une conversation, sous la forme que le pont attend.
struct Turn {
    const char* role;
    const char* content;
};

std::string prompt_for(void* engine, const std::vector<Turn>& turns) {
    std::vector<const char*> roles;
    std::vector<const char*> contents;
    for (const Turn& turn : turns) {
        roles.push_back(turn.role);
        contents.push_back(turn.content);
    }
    char* templated = foxllm_engine_apply_chat_template(
        engine,
        roles.data(),
        contents.data(),
        static_cast<int32_t>(turns.size()),
        1);
    if (templated == nullptr) {
        std::fprintf(stderr, "gabarit refusé : %s\n", foxllm_engine_last_error(engine));
        std::exit(1);
    }
    std::string prompt(templated);
    foxllm_string_free(templated);
    return prompt;
}

// Glouton : température nulle, donc aucun aléa. C'est ce qui rend la
// comparaison possible.
std::string answer(void* engine, const std::string& prompt, int32_t max_tokens) {
    std::string out;
    foxllm_engine_reset_stop(engine);
    const int32_t ok = foxllm_engine_generate_stream(
        engine, prompt.c_str(), 0.0f, 1.0f, max_tokens, collect, &out);
    if (ok == 0) {
        std::fprintf(stderr, "génération refusée : %s\n", foxllm_engine_last_error(engine));
        std::exit(1);
    }
    return out;
}

void* open_engine(const char* path) {
    void* engine = foxllm_engine_create();
    if (foxllm_engine_load_model(engine, path) == 0) {
        std::fprintf(stderr, "chargement refusé : %s\n", foxllm_engine_last_error(engine));
        std::exit(1);
    }
    return engine;
}

int failures = 0;

void expect_same(const char* what, const std::string& cold, const std::string& warm) {
    const bool ok = cold == warm;
    std::printf("%-58s %s\n", what, ok ? "identique" : "DIFFERENT");
    if (!ok) {
        std::printf("    à froid : %s\n", cold.c_str());
        std::printf("    à chaud : %s\n", warm.c_str());
        failures++;
    }
}

void expect_different(const char* what, const std::string& a, const std::string& b) {
    const bool ok = a != b;
    std::printf("%-58s %s\n", what, ok ? "différent" : "IDENTIQUE (suspect)");
    if (!ok) {
        failures++;
    }
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <modele.gguf>\n", argv[0]);
        return 2;
    }
    const char* path = argv[1];
    const int32_t kMax = 24;

    std::printf("pont natif : %s\n", foxllm_native_version());

    void* probe = open_engine(path);
    std::printf("modèle     : %s\n", foxllm_engine_model_description(probe));
    std::printf("contexte   : %d jetons\n\n", foxllm_engine_model_context_size(probe));
    foxllm_engine_destroy(probe);

    const std::vector<Turn> tour1 = {
        {"user", "Mon animal préféré est le chat."},
    };
    const std::vector<Turn> tour2 = {
        {"user", "Mon animal préféré est le chat."},
        {"assistant", "Très bien, je le note."},
        {"user", "Quel est mon animal préféré ?"},
    };
    const std::vector<Turn> tour3 = {
        {"user", "Mon animal préféré est le chat."},
        {"assistant", "Très bien, je le note."},
        {"user", "Quel est mon animal préféré ?"},
        {"assistant", "Un chat."},
        {"user", "Et sa couleur ?"},
    };
    // Le premier message modifié : le cache doit jeter tout ce qui suit.
    const std::vector<Turn> tour2_modifie = {
        {"user", "Mon animal préféré est le hérisson."},
        {"assistant", "Très bien, je le note."},
        {"user", "Quel est mon animal préféré ?"},
    };

    // --- 1. Un cache chaud ne change pas la réponse -----------------------
    //
    // À froid, un moteur neuf lit tout le prompt. À chaud, le même moteur a
    // déjà lu le tour précédent et ne relit que la suite. Même prompt, même
    // réponse attendue, au jeton près.
    {
        void* cold = open_engine(path);
        const std::string reference = answer(cold, prompt_for(cold, tour2), kMax);
        foxllm_engine_destroy(cold);

        void* warm = open_engine(path);
        answer(warm, prompt_for(warm, tour1), kMax);  // remplit le cache
        const std::string reused = answer(warm, prompt_for(warm, tour2), kMax);
        foxllm_engine_destroy(warm);

        expect_same("cache chaud sur un fil qui s'allonge", reference, reused);
    }

    // --- 2. Deux tours de suite, le cache se cumulant ---------------------
    {
        void* cold = open_engine(path);
        const std::string reference = answer(cold, prompt_for(cold, tour3), kMax);
        foxllm_engine_destroy(cold);

        void* warm = open_engine(path);
        answer(warm, prompt_for(warm, tour1), kMax);
        answer(warm, prompt_for(warm, tour2), kMax);
        const std::string reused = answer(warm, prompt_for(warm, tour3), kMax);
        foxllm_engine_destroy(warm);

        expect_same("cache cumulé sur trois tours", reference, reused);
    }

    // --- 3. Un message modifié invalide le cache --------------------------
    //
    // Le cas qui fait les bugs les plus vicieux : le début du prompt a changé,
    // le cache doit être tronqué au point de divergence. S'il ne l'est pas, la
    // réponse porte la marque de l'ancien texte.
    {
        void* cold = open_engine(path);
        const std::string reference = answer(cold, prompt_for(cold, tour2_modifie), kMax);
        foxllm_engine_destroy(cold);

        void* warm = open_engine(path);
        answer(warm, prompt_for(warm, tour2), kMax);  // cache pollué par « chat »
        const std::string reused = answer(warm, prompt_for(warm, tour2_modifie), kMax);
        foxllm_engine_destroy(warm);

        expect_same("cache invalidé après modification d'un message", reference, reused);
    }

    // --- 4. Le témoin : deux prompts différents donnent deux réponses ------
    //
    // Sans ce contrôle, les trois précédents passeraient aussi avec un modèle
    // qui répond toujours la même chose, et ne prouveraient rien.
    {
        void* engine = open_engine(path);
        const std::string a = answer(engine, prompt_for(engine, tour2), kMax);
        const std::string b = answer(engine, prompt_for(engine, tour2_modifie), kMax);
        foxllm_engine_destroy(engine);

        expect_different("témoin : « chat » et « hérisson » ne donnent pas le même", a, b);
    }

    std::printf("\n%s\n", failures == 0 ? "Cache KV : tous les contrôles passent."
                                        : "Cache KV : DES CONTROLES ECHOUENT.");
    return failures == 0 ? 0 : 1;
}
