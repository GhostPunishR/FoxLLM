#!/usr/bin/env bash
# Copyright © 2026 GhostPunishR
# SPDX-License-Identifier: AGPL-3.0-only
#
# Génère plusieurs tokens avec un vrai modèle, sous AddressSanitizer.
#
# La boucle de décodage confie au batch un pointeur vers le jeton échantillonné
# et `llama_decode` le relit au tour suivant. Une compilation propre ou une
# génération sans modèle ne dit rien de ce scénario : il faut décoder pour de
# bon, et instrumenter llama.cpp autant que le moteur, car c'est llama.cpp qui
# déréférence le pointeur.
#
# Durée : une dizaine de minutes, l'essentiel en compilation de llama.cpp.
# Prérequis : cmake, g++ avec ASan, python3 avec `gguf` et `numpy`.

set -euo pipefail

readonly LLAMA_COMMIT=481c65f091f74c5e7089dd0a3a1cc6b50cced31e
readonly HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SRC="$HERE/../../src"
readonly WORK="${1:-${TMPDIR:-/tmp}/foxllm-asan}"

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d llama.cpp ]; then
  echo "== récupération de llama.cpp $LLAMA_COMMIT"
  git clone --depth 1 https://github.com/ggml-org/llama.cpp llama.cpp
  git -C llama.cpp fetch --depth 1 origin "$LLAMA_COMMIT"
  git -C llama.cpp checkout FETCH_HEAD
fi

if [ ! -f llama.cpp/build/src/libllama.a ]; then
  echo "== compilation de llama.cpp sous AddressSanitizer"
  # `--target llama` seulement : les cibles annexes réclament un build-info.h
  # que cette configuration ne produit pas.
  cmake -S llama.cpp -B llama.cpp/build \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF \
    -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_C_FLAGS="-fsanitize=address -fsanitize-address-use-after-scope -g -O1" \
    -DCMAKE_CXX_FLAGS="-fsanitize=address -fsanitize-address-use-after-scope -g -O1" \
    > cmake-configure.log
  cmake --build llama.cpp/build -j"$(nproc)" --target llama > cmake-build.log
fi

if [ ! -f tiny.gguf ]; then
  echo "== fabrication du modèle de test"
  python3 "$HERE/tiny_gguf.py" tiny.gguf
fi

echo "== compilation du moteur FoxLLM avec llama.cpp"
g++ -std=c++17 -DFOXLLM_WITH_LLAMA_CPP \
  -I llama.cpp/include -I llama.cpp/ggml/include -I "$SRC" \
  -fsanitize=address -fsanitize-address-use-after-scope -g -O1 \
  -c "$SRC/foxllm_native.cpp" -o foxllm_native.o
gcc -w -c "$HERE/stream_driver.c" -o stream_driver.o
g++ -fsanitize=address -g foxllm_native.o stream_driver.o -o stream_check \
  llama.cpp/build/src/libllama.a \
  llama.cpp/build/ggml/src/libggml.a \
  llama.cpp/build/ggml/src/libggml-cpu.a \
  llama.cpp/build/ggml/src/libggml-base.a \
  -lpthread -lm -ldl

echo "== génération sous AddressSanitizer"
ASAN_OPTIONS=detect_stack_use_after_return=1 ./stream_check tiny.gguf
echo "== aucune erreur AddressSanitizer pendant la génération"
