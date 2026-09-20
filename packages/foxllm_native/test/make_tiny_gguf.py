#!/usr/bin/env python3
# Copyright © 2026 GhostPunishR
# SPDX-License-Identifier: AGPL-3.0-only

"""Fabrique un modèle GGUF minuscule au format llama, pour les essais de FoxLLM.

Ce n'est pas un modèle entraîné : les poids sont tirés au hasard, et les
réponses sont donc du charabia. C'est voulu. L'objet ici n'est pas la qualité
du texte mais le chemin qui y mène : chargement du GGUF, tokenisation, gabarit
de conversation, cache KV, découpage en lots, arrêt en cours de route. Tout
cela se teste sans qu'un seul mot ait de sens.

Deux propriétés le rendent utile comme témoin :

  - il est déterministe. Même graine, mêmes poids, au bit près. Avec un
    échantillonnage glouton, une même suite de jetons donne toujours la même
    réponse, ce qui permet d'affirmer qu'un cache KV correct ne change rien au
    résultat : c'est exactement le contrôle qui manquait ;
  - il est minuscule. Quelques centaines de kilooctets, donc transportable
    dans un dépôt ou vers un téléphone sans y penser.

La dimension de tête est fixée à 64, valeur que les noyaux d'attention flash
de llama.cpp savent traiter : c'est ce qui permet d'exercer aussi le cache
quantifié en `q8_0`, qui la réclame.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import gguf

# Assez grand pour que les couches aient un comportement, assez petit pour que
# le fichier reste un témoin et non un modèle.
N_LAYER = 2
N_EMBD = 128
N_HEAD = 2
N_HEAD_KV = 1  # Moins de têtes K/V que de têtes Q : le cas GQA est exercé.
N_FF = 256
N_CTX = 4096

HEAD_DIM = N_EMBD // N_HEAD
N_EMBD_KV = HEAD_DIM * N_HEAD_KV

# ChatML, le gabarit que FoxLLM emploie en repli : le modèle le porte donc
# lui-même, ce qui exerce la lecture du gabarit plutôt que le repli.
CHAT_TEMPLATE = (
    "{% for message in messages %}"
    "{{'<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n'}}"
    "{% endfor %}"
    "{% if add_generation_prompt %}{{ '<|im_start|>assistant\n' }}{% endif %}"
)


def build_vocab() -> tuple[list[bytes], list[float], list[int]]:
    """Vocabulaire minimal : les jetons spéciaux, puis les 256 octets.

    Un vocabulaire d'octets accepte n'importe quel texte sans jamais échouer,
    accents et emoji compris, et tient en trois cents entrées. C'est le plus
    petit tokeniseur qui soit réellement universel.
    """
    tokens: list[bytes] = []
    scores: list[float] = []
    types: list[int] = []

    def add(piece: bytes, kind: int, score: float = 0.0) -> None:
        tokens.append(piece)
        scores.append(score)
        types.append(kind)

    add(b"<unk>", gguf.TokenType.UNKNOWN)
    add(b"<s>", gguf.TokenType.CONTROL)
    add(b"</s>", gguf.TokenType.CONTROL)
    # Les deux bornes de ChatML, pour que le gabarit ci-dessus ait un sens.
    add(b"<|im_start|>", gguf.TokenType.CONTROL)
    add(b"<|im_end|>", gguf.TokenType.CONTROL)

    # Les 256 octets. Le tokeniseur SPM de llama.cpp se rabat dessus dès
    # qu'aucune pièce plus longue ne correspond, ce qui est toujours le cas
    # ici : chaque caractère devient un jeton.
    for byte in range(256):
        add(f"<0x{byte:02X}>".encode("ascii"), gguf.TokenType.BYTE, -float(byte))

    return tokens, scores, types


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("foxllm-tiny-f16.gguf"),
        help="fichier GGUF à écrire",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=20260920,
        help="graine des poids ; même graine, même fichier au bit près",
    )
    parser.add_argument(
        "--f32",
        action="store_true",
        help="écrire en float32 plutôt qu'en float16 (fichier deux fois plus gros)",
    )
    args = parser.parse_args()

    dtype = np.float32 if args.f32 else np.float16
    rng = np.random.default_rng(args.seed)

    tokens, scores, types = build_vocab()
    n_vocab = len(tokens)

    def weights(*shape: int) -> np.ndarray:
        """Poids centrés, d'écart type modeste.

        L'échelle importe : trop grande, les activations saturent et le modèle
        ne produit qu'un seul jeton en boucle, ce qui ferait un mauvais témoin
        pour le cache. 0,02 est l'ordre de grandeur d'une initialisation
        classique de transformeur.
        """
        return rng.normal(0.0, 0.02, size=shape).astype(dtype)

    def norm(size: int) -> np.ndarray:
        """Poids de normalisation, autour de 1 : une RMSNorm part de l'identité.

        Toujours en float32, même quand le reste du modèle est en float16.
        Ce n'est pas un détail esthétique : ggml applique la normalisation par
        une multiplication terme à terme, et son noyau CPU refuse d'appareiller
        un f32 avec un f16. Un poids de norme en f16 fait tomber le processus
        au premier décodage, sur un « unsupported types » peu bavard. Tous les
        GGUF réels gardent ces tenseurs à une dimension en float32.
        """
        return (1.0 + rng.normal(0.0, 0.01, size=size)).astype(np.float32)

    writer = gguf.GGUFWriter(args.out, "llama")

    writer.add_name("FoxLLM Tiny")
    writer.add_description(
        "Modèle témoin de FoxLLM. Poids aléatoires : les réponses n'ont aucun "
        "sens, seul le chemin technique est réel."
    )
    writer.add_license("AGPL-3.0-only")
    writer.add_file_type(
        gguf.GGMLQuantizationType.F32 if args.f32 else gguf.GGMLQuantizationType.F16
    )

    writer.add_context_length(N_CTX)
    writer.add_embedding_length(N_EMBD)
    writer.add_block_count(N_LAYER)
    writer.add_feed_forward_length(N_FF)
    writer.add_head_count(N_HEAD)
    writer.add_head_count_kv(N_HEAD_KV)
    writer.add_rope_dimension_count(HEAD_DIM)
    writer.add_rope_freq_base(10000.0)
    writer.add_layer_norm_rms_eps(1e-5)
    writer.add_vocab_size(n_vocab)

    writer.add_tokenizer_model("llama")
    writer.add_token_list(tokens)
    writer.add_token_scores(scores)
    writer.add_token_types(types)
    writer.add_bos_token_id(1)
    writer.add_eos_token_id(4)  # <|im_end|> : ChatML termine le tour dessus.
    writer.add_unk_token_id(0)
    writer.add_add_bos_token(True)
    writer.add_add_eos_token(False)
    writer.add_chat_template(CHAT_TEMPLATE)

    # Les formes suivent la convention torch, (sortie, entrée) : le writer
    # inverse lui-même les dimensions pour GGUF.
    writer.add_tensor("token_embd.weight", weights(n_vocab, N_EMBD))

    for layer in range(N_LAYER):
        writer.add_tensor(f"blk.{layer}.attn_norm.weight", norm(N_EMBD))
        writer.add_tensor(f"blk.{layer}.attn_q.weight", weights(N_EMBD, N_EMBD))
        writer.add_tensor(f"blk.{layer}.attn_k.weight", weights(N_EMBD_KV, N_EMBD))
        writer.add_tensor(f"blk.{layer}.attn_v.weight", weights(N_EMBD_KV, N_EMBD))
        writer.add_tensor(f"blk.{layer}.attn_output.weight", weights(N_EMBD, N_EMBD))
        writer.add_tensor(f"blk.{layer}.ffn_norm.weight", norm(N_EMBD))
        writer.add_tensor(f"blk.{layer}.ffn_gate.weight", weights(N_FF, N_EMBD))
        writer.add_tensor(f"blk.{layer}.ffn_up.weight", weights(N_FF, N_EMBD))
        writer.add_tensor(f"blk.{layer}.ffn_down.weight", weights(N_EMBD, N_FF))

    writer.add_tensor("output_norm.weight", norm(N_EMBD))
    writer.add_tensor("output.weight", weights(n_vocab, N_EMBD))

    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_tensors_to_file()
    writer.close()

    size = args.out.stat().st_size
    print(f"{args.out} : {size / 1024:.1f} Kio, {n_vocab} jetons, {N_LAYER} couches")


if __name__ == "__main__":
    main()
