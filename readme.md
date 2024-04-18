# Keccak256 for Apple Metal

This is a test implementation of a keccak256 miner with GPU acceleration using a Metal shader. The shader is currently not optimized and should serve as a proof-of-concept to build upon. The gpu hash mining is unstable and does not work under certain conditions such as incorrectly choosing the number of thread groups and the number of threads per group. Please use with caution as incorrect usage could lead to a memory-leak.

## Features

- **CPU Mining**: Utilizes pure Rust code to perform hash mining on the CPU (single-threaded).
- **GPU Mining**: Harnesses the GPU's power using Metal to accelerate the mining process.
- **Dual Mining Verification**: Compares results from both CPU and GPU mining to ensure consistency.

## Prerequisites

- **Rust**: The project is built with Rust, so you'll need to have Rust and Cargo installed. You can install them from [rustup](https://rustup.rs/).
- **Metal API**: Required for GPU mining, thus this code is specifically for macOS systems equipped with Metal-compatible hardware.

## Setup and Running

1. **Clone the Repository**

   ```bash
   git clone https://github.com/tonton-sol/keccak256-metal.git
   cd keccak256-metal
   ```

2. **Configure for Your System**

   - Change the desired difficulty. Higher difficulty will take longer to test.
   - The Metal API automatically selects `threads_per_threadgroup` for your hardware.
   - Choose the `thread_groups_count` such that `threads_per_threadgroup * thread_groups_count` is the total number of threads you want to deploy. I have found for my processor (Apple M2), that `thread_groups_count < 8` is stable and will consistently find the correct hash.
   - Changing the input_data to something more than 64 bytes will cause a memory-leak if the metal shader code is not changed as well.

3. **Build the Code**

    ```bash
    cargo build --release
    ```

4. **Run the Test**

    ```bash
    cargo run --release
    ```

## Contributing

Contributions to this project are welcome! Please feel free to fork the repository, make changes, and submit a pull request.
