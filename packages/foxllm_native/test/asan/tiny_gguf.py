# Copyright © 2026 GhostPunishR
# SPDX-License-Identifier: AGPL-3.0-only
#
# Fabrique un GGUF llama minuscule mais complet, à poids aléatoires.
# Le but n'est pas la qualité des réponses : c'est d'avoir un modèle
# valide, de 170 Ko, qui fait tourner la boucle de décodage sur
# plusieurs tokens là où le batch réutilise le pointeur du jeton.
#
# Dépendances : pip install gguf numpy

import numpy as np
import sys

import gguf

EXTRA = 61
VOCAB = 3 + 256 + EXTRA
DIM = 32
FF = 64
HEADS = 2
LAYERS = 2
CTX = 128

rng = np.random.default_rng(7)
def t(*shape):
    return rng.standard_normal(shape).astype(np.float32) * 0.05

w = gguf.GGUFWriter(sys.argv[1] if len(sys.argv) > 1 else 'tiny.gguf', 'llama')
w.add_context_length(CTX)
w.add_embedding_length(DIM)
w.add_block_count(LAYERS)
w.add_feed_forward_length(FF)
w.add_head_count(HEADS)
w.add_head_count_kv(HEADS)
w.add_rope_dimension_count(DIM // HEADS)
w.add_layer_norm_rms_eps(1e-5)
w.add_file_type(gguf.LlamaFileType.ALL_F32)

# Le tokenizer SPM retombe sur les tokens d'octets pour tout caractère absent
# du vocabulaire : sans eux, il lève une exception dès le premier prompt.
tokens = ['<unk>', '<s>', '</s>']
types = [gguf.TokenType.UNKNOWN, gguf.TokenType.CONTROL, gguf.TokenType.CONTROL]
tokens += [f'<0x{i:02X}>' for i in range(256)]
types += [gguf.TokenType.BYTE] * 256
tokens += [f'\u2581t{i}' for i in range(EXTRA)]
types += [gguf.TokenType.NORMAL] * EXTRA
w.add_tokenizer_model('llama')
w.add_token_list(tokens)
w.add_token_scores([0.0] * VOCAB)
w.add_token_types(types)
w.add_bos_token_id(1)
w.add_eos_token_id(2)
w.add_unk_token_id(0)
w.add_add_bos_token(True)
w.add_add_eos_token(False)

w.add_tensor('token_embd.weight', t(VOCAB, DIM))
w.add_tensor('output_norm.weight', np.ones(DIM, dtype=np.float32))
w.add_tensor('output.weight', t(VOCAB, DIM))
for i in range(LAYERS):
    p = f'blk.{i}'
    w.add_tensor(f'{p}.attn_norm.weight', np.ones(DIM, dtype=np.float32))
    w.add_tensor(f'{p}.attn_q.weight', t(DIM, DIM))
    w.add_tensor(f'{p}.attn_k.weight', t(DIM, DIM))
    w.add_tensor(f'{p}.attn_v.weight', t(DIM, DIM))
    w.add_tensor(f'{p}.attn_output.weight', t(DIM, DIM))
    w.add_tensor(f'{p}.ffn_norm.weight', np.ones(DIM, dtype=np.float32))
    w.add_tensor(f'{p}.ffn_gate.weight', t(FF, DIM))
    w.add_tensor(f'{p}.ffn_up.weight', t(FF, DIM))
    w.add_tensor(f'{p}.ffn_down.weight', t(DIM, FF))

w.write_header_to_file()
w.write_kv_data_to_file()
w.write_tensors_to_file()
w.close()
print('tiny.gguf écrit')
