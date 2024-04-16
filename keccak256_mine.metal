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

void keccak256(device const uchar *input, device uchar *output, uint inputLength)  {
    const uint rsize = 136; // 1088 bits (136 bytes) for Keccak-256
    thread ulong state[25] = {0};
    uint i = 0;
    while (i < inputLength) {
        if (i + rsize <= inputLength) {
            for (uint j = 0; j < rsize / 8; j++) {
                ulong block = 0;
                for (int k = 0; k < 8; k++) {
                    block |= (ulong)(input[i + j * 8 + k]) << (8 * k);
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
                    block |= (ulong)(padded[j * 8 + k]) << (8 * k);
                }
                state[j] ^= block;
            }
            keccak_f(state);
            break;
        }
    }
    // Write the output
    for (uint j = 0; j < 32; j++) {
        output[j] = (uchar)((state[j / 8] >> (8 * (j % 8))) & 0xFF);
    }
}

bool check_hash(device uchar *hash, device uchar *target) {
    for (int i = 0; i < 32; i++) {
        if (hash[i] < target[i])
            return true;
        else if (hash[i] > target[i])
            return false;
    }
    return false; // Hash is equal to target, which is still a success
}

kernel void mining_kernel(
    device uchar *input [[buffer(0)]], // Input buffer
    device uchar *output [[buffer(1)]], // Hash output buffer
    device uchar *target [[buffer(2)]], // Difficulty target buffer
    constant uint *inputLength [[buffer(3)]], // Length of the input data
    device ulong *nonceFound [[buffer(4)]], // Buffer to store the found nonce
    device bool *success [[buffer(5)]], // Buffer to store success flag
    constant ulong *globalWorkSize [[buffer(6)]], // Total number of threads
    constant uint *threadsPerGroup [[buffer(7)]], // Number of threads per threadgroup
    uint3 tid [[thread_position_in_grid]], // Metal built-in to get the thread's position in the grid
    uint3 groupId [[threadgroup_position_in_grid]], // Metal built-in to get the threadgroup's position in grid
    uint3 tsize [[threads_per_threadgroup]] // Metal built-in to get the number of threads per threadgroup
) {
    uint globalID = groupId.x * tsize.x + tid.x; // Calculate global thread ID

    ulong nonce = globalID; // Use calculated global thread ID as initial nonce
    uint totalLength = *inputLength; // Initial input length without nonce

    while (true) {
        // Convert nonce to little-endian bytes and append it to the input
        for (int i = 0; i < 8; i++) {
            input[totalLength + i] = (uchar)((nonce >> (i * 8)) & 0xff);
        }

        keccak256(input, output, totalLength + 8); // Update length for 8 bytes of nonce

        if (check_hash(output, target)) {
            *nonceFound = nonce;
            *success = true;
            return;
        }

        nonce += *globalWorkSize; // Increment nonce by the total number of threads to avoid overlaps
        if (nonce > 0xFFFFFFFFFFFFFFFF) break; // Prevent overflow and endless loop
    }

    *success = false; // Indicate that no valid nonce was found
}