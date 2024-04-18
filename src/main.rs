use logfather::{error, info, trace};
use metal::{CompileOptions, Device, MTLResourceOptions, MTLSize};
use solana_sdk::{
    keccak::{hashv, Hash},
    signature::Keypair,
    signer::Signer,
};
use std::{mem::size_of, slice, time::Instant};

fn mine_cpu(input_data: &[u8], difficulty: &[u8]) -> (Hash, u64) {
    info!("Starting CPU test...",);
    let mut hash: Hash;

    let difficulty_hash = Hash::new(difficulty);

    trace!("difficulty: {}", difficulty_hash.to_string());

    for nonce in 1_u64.. {
        hash = hashv(&[input_data, nonce.to_le_bytes().as_slice()]);
        if hash.le(&difficulty_hash) {
            trace!("nonce: {}", nonce);
            trace!("hash: {}", hash);
            return (hash, nonce);
        }
    }
    panic!("Could not find a valid hash")
}

fn mine_gpu(input_data: &[u8], difficulty: &[u8]) -> (Hash, u64) {
    info!("Starting GPU test...",);

    let difficulty_hash = Hash::new(difficulty);

    trace!("difficulty: {}", difficulty_hash.to_string());
    let device = Device::system_default().unwrap();
    let command_queue = device.new_command_queue();

    let source = include_str!("../keccak256_mine.metal");
    let options = CompileOptions::new();
    let library = device.new_library_with_source(source, &options).unwrap();
    let function = library.get_function("mining_kernel", None).unwrap();
    let pipeline_state = device
        .new_compute_pipeline_state_with_function(&function)
        .unwrap();

    let input_buffer = device.new_buffer_with_data(
        input_data.as_ptr() as *const _,
        input_data.len() as u64,
        MTLResourceOptions::StorageModeShared,
    );

    let input_length = input_data.len() as u32;
    let input_length_buffer = device.new_buffer_with_data(
        &input_length as *const _ as *const _,
        std::mem::size_of::<u32>() as u64,
        MTLResourceOptions::CPUCacheModeWriteCombined,
    );

    let difficulty_buffer = device.new_buffer_with_data(
        difficulty.as_ptr() as *const _,
        difficulty.len() as u64,
        MTLResourceOptions::StorageModeShared,
    );

    let threads_per_group = 256;
    let num_threadgroups = 1;
    let total_threads = threads_per_group * num_threadgroups;

    let output_buffer = device.new_buffer(32, MTLResourceOptions::StorageModeShared);
    let output_nonce_buffer = device.new_buffer(32, MTLResourceOptions::StorageModeShared);
    let found_buffer = device.new_buffer(
        size_of::<bool>() as u64,
        MTLResourceOptions::StorageModeShared,
    );

    let total_threads_buffer = device.new_buffer_with_data(
        &total_threads as *const _ as *const _,
        std::mem::size_of::<u64>() as u64,
        MTLResourceOptions::CPUCacheModeWriteCombined,
    );
    let nonces_buffer = device.new_buffer(
        (global_work_size as usize * size_of::<u64>()) as u64,
        MTLResourceOptions::StorageModeShared,
    );
    let loops_buffer = device.new_buffer(
        (global_work_size as usize * size_of::<u64>()) as u64,
        MTLResourceOptions::StorageModeShared,
    );

    let command_buffer = command_queue.new_command_buffer();
    let encoder = command_buffer.new_compute_command_encoder();
    encoder.set_compute_pipeline_state(&pipeline_state);
    encoder.set_buffer(0, Some(&input_buffer), 0);
    encoder.set_buffer(1, Some(&output_buffer), 0);
    encoder.set_buffer(2, Some(&difficulty_buffer), 0);
    encoder.set_buffer(3, Some(&input_length_buffer), 0);
    encoder.set_buffer(4, Some(&output_nonce_buffer), 0);
    encoder.set_buffer(5, Some(&found_buffer), 0);
    encoder.set_buffer(6, Some(&total_threads_buffer), 0);
    encoder.dispatch_thread_groups(
        MTLSize {
            width: threads_per_group,
            height: 1,
            depth: 1,
        },
        MTLSize {
            width: num_threadgroups,
            height: 1,
            depth: 1,
        },
    );

    encoder.end_encoding();

    command_buffer.commit();
    command_buffer.wait_until_completed();

    let nonce = unsafe {
        let ptr = output_nonce_buffer.contents() as *const u64;
        *ptr
    };

    let found = unsafe {
        let ptr = found_buffer.contents() as *const bool;
        *ptr
    };

    let hash = unsafe { slice::from_raw_parts(output_buffer.contents() as *const u8, 32).to_vec() };

    // let nonces = unsafe {
    //     slice::from_raw_parts(
    //         nonces_buffer.contents() as *const u64,
    //         global_work_size as usize,
    //     )
    //     .to_vec()
    // };

    // let loops = unsafe {
    //     slice::from_raw_parts(
    //         loops_buffer.contents() as *const u64,
    //         global_work_size as usize,
    //     )
    //     .to_vec()
    // };

    // warn!("nonces: {:?}", nonces);
    // warn!("loops: {:?}", loops);

    let hash_rs = Hash::new(&hash);

    if !found {
        error!("Hash not found!")
    }

    trace!("nonce: {}", nonce);
    trace!("hash: {}", hash_rs);
    return (hash_rs, nonce);
}

fn main() {

    let challenge = Keypair::new().pubkey();
    let pubkey = Keypair::new().pubkey();

    let data = [challenge.as_ref(), pubkey.as_ref()].concat();

    let difficulty = [
        0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    ]
    .as_ref();

    let start1 = Instant::now();
    let (hash_cpu, nonce_cpu) = mine_cpu(&data, difficulty);
    let duration1 = start1.elapsed();
    info!("CPU: {:?}", duration1);

    let start2 = Instant::now();
    let (hash_gpu, nonce_gpu) = mine_gpu(&data, difficulty);
    let duration2 = start2.elapsed();
    info!("GPU: {:?}", duration2);

    if hash_cpu == hash_gpu && nonce_cpu == nonce_gpu {
        info!("Success! Hashes match!")
    } else {
        error!("Failure! Hashes do not match!")
    }
}
