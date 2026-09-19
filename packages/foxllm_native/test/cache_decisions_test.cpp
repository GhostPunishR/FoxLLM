// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

// Contrôles des deux décisions du cache KV.
//
// Le cache lui-même demande un modèle et un appareil ; ces deux fonctions,
// non. Ce sont pourtant elles qui décident ce qui est relu et quelle mémoire
// est réservée : une erreur ici donne une réponse incohérente ou un téléphone
// à court de mémoire, sans que rien ne le signale.
//
// Le fichier source est inclus tel quel : les deux fonctions vivent dans un
// espace de noms anonyme, et c'est la seule façon de les atteindre sans les
// exposer au reste du monde.
#include "../src/foxllm_native.cpp"

#include <cassert>
#include <cstdio>
#include <vector>

namespace {

void prefix_is_empty_when_nothing_matches() {
    assert(common_prefix_length({1, 2, 3}, {4, 5, 6}) == 0);
    assert(common_prefix_length({}, {1, 2}) == 0);
    assert(common_prefix_length({1, 2}, {}) == 0);
}

void prefix_covers_a_growing_conversation() {
    // Le cas ordinaire : le tour suivant reprend tout le précédent et ajoute
    // la réponse puis la nouvelle question. C'est ce qui rend le cache utile.
    const std::vector<int32_t> cached = {10, 11, 12, 13};
    const std::vector<int32_t> wanted = {10, 11, 12, 13, 14, 15};
    assert(common_prefix_length(cached, wanted) == 4);
}

void prefix_stops_at_the_first_difference() {
    // Une conversation modifiée diverge en son milieu : tout ce qui suit doit
    // être relu, sous peine de répondre à une question qui n'a pas été posée.
    const std::vector<int32_t> cached = {10, 11, 99, 13};
    const std::vector<int32_t> wanted = {10, 11, 12, 13};
    assert(common_prefix_length(cached, wanted) == 2);
}

void prefix_never_exceeds_the_shorter_side() {
    // Un fil raccourci, par une régénération ou une modification : le cache
    // en sait plus que le prompt, et ne doit pas prétendre le contraire.
    const std::vector<int32_t> cached = {10, 11, 12, 13, 14};
    const std::vector<int32_t> wanted = {10, 11, 12};
    assert(common_prefix_length(cached, wanted) == 3);
}

void context_holds_at_least_the_minimum() {
    // Une question d'une ligne ne doit pas se voir attribuer un contexte si
    // juste que la première réponse le fasse déborder.
    assert(context_size_for(0, 50, 0) == kMinimumContextSize);
}

void context_covers_what_is_needed() {
    const uint32_t needed = kMinimumContextSize * 3;
    assert(context_size_for(0, needed, 0) >= needed);
}

void context_doubles_rather_than_creeping() {
    // Sans doublement, chaque tour dépasserait d'un cheveu le contexte
    // précédent : il serait refait à chaque message, et le cache ne servirait
    // jamais.
    const uint32_t current = 2048;
    const uint32_t grown = context_size_for(current, current + 1, 0);
    assert(grown >= current * 2);
}

void context_never_exceeds_what_the_model_was_trained_for() {
    const uint32_t trained = 4096;
    const uint32_t grown = context_size_for(3000, 3500, trained);
    assert(grown <= trained);
    assert(grown >= 3500);
}

void context_still_covers_a_need_that_fills_the_training_window() {
    // Le plafond d'entraînement l'emporte sur le doublement, mais ne doit pas
    // rendre un contexte plus petit que ce que le prompt réclame.
    const uint32_t trained = 4096;
    assert(context_size_for(4096, 4096, trained) == trained);
}

}  // namespace

int main() {
    prefix_is_empty_when_nothing_matches();
    prefix_covers_a_growing_conversation();
    prefix_stops_at_the_first_difference();
    prefix_never_exceeds_the_shorter_side();
    context_holds_at_least_the_minimum();
    context_covers_what_is_needed();
    context_doubles_rather_than_creeping();
    context_never_exceeds_what_the_model_was_trained_for();
    context_still_covers_a_need_that_fills_the_training_window();
    std::printf("FoxLLM KV cache decisions: all checks passed.\n");
    return 0;
}
