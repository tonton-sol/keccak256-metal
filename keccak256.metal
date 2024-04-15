#include <metal_stdlib>
using namespace metal;

constant ulong RC[24] = {
    0x0000000000000001UL, 0x0000000000008082UL, 0x800000000000808aUL,
    0x8000000080008000UL, 0x000000000000808bUL, 0x0000000080000001UL,
    0x8000000080008081UL, 0x8000000000008009UL, 0x000000000000008aUL,
    0x0000000000000088UL, 0x0000000080008009UL, 0x000000008000000aUL,
    0x000000008000808bUL, 0x800000000000008bUL, 0x8000000000008089UL,
    0x8000000000008003UL, 0x8000000000008002UL, 0x8000000000000080UL,
    0x000000000000800aUL, 0x800000008000000aUL, 0x8000000080008081UL,
    0x8000000000008080UL, 0x0000000080000001UL, 0x8000000080008008UL
};

inline ulong ROTL64(ulong x, int y) {
    return (x << y) | (x >> (64 - y));
}

void keccak_f(thread ulong *state) {
    int piln[24] = { 10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1 };

    ulong C[5], D;
    for (int round = 0; round < 24; round++) {
        for (int i = 0; i < 5; i++) {
            C[i] = state[i] ^ state[i + 5] ^ state[i + 10] ^ state[i + 15] ^ state[i + 20];
        }

        for (int i = 0; i < 5; i++) {
            D = C[(i + 4) % 5] ^ ROTL64(C[(i + 1) % 5], 1);
            for (int j = 0; j < 25; j += 5) {
                state[j + i] ^= D;
            }
        }

        ulong tmp = state[1];
        for (int i = 0; i < 24; i++) {
            int j = piln[i];
            C[0] = state[j];
            state[j] = ROTL64(tmp, (i + 1) * (i + 2) / 2 % 64);
            tmp = C[0];
        }

        for (int j = 0; j < 25; j += 5) {
            ulong t0 = state[j + 0], t1 = state[j + 1], t2 = state[j + 2], t3 = state[j + 3], t4 = state[j + 4];
            state[j + 0] ^= ~t1 & t2;
            state[j + 1] ^= ~t2 & t3;
            state[j + 2] ^= ~t3 & t4;
            state[j + 3] ^= ~t4 & t0;
            state[j + 4] ^= ~t0 & t1;
        }

        state[0] ^= RC[round];
    }
}

kernel void hash_kernel(
    device const uchar *input [[buffer(0)]],
    device uchar *output [[buffer(1)]],
    constant uint &inputLength [[buffer(2)]]
) {
    thread ulong state[25] = {0};
    const uint rsize = 136; // 1088 bits (136 bytes) for Keccak-256

    uint i = 0;
    while (i < inputLength) {
        if (i + rsize <= inputLength) {
            for (uint j = 0; j < rsize / 8; j++) {
                ulong block = 0;
                for (int k = 0; k < 8; k++) {
                    block |= (ulong)(input[i + j*8 + k]) << (8 * k);
                }
                state[j] ^= block;
            }
            keccak_f(state);
            i += rsize;
        } else {
            // Handle the last block with padding
            uchar padded[rsize] = {0};
            for (uint j = 0; j < inputLength - i; j++) {
                padded[j] = input[i + j];
            }
            padded[inputLength - i] = 0x01; // Padding start
            padded[rsize - 1] |= 0x80; // Padding end
            for (uint j = 0; j < rsize / 8; j++) {
                ulong block = 0;
                for (int k = 0; k < 8; k++) {
                    block |= (ulong)(padded[j*8 + k]) << (8 * k);
                }
                state[j] ^= block;
            }
            keccak_f(state);
            break;
        }
    }

    // Writing output
    for (uint j = 0; j < 32; j++) {
        output[j] = (uchar)((state[j / 8] >> (8 * (j % 8))) & 0xFF);
    }
}
