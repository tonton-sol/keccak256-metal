use metal::{Device, MTLResourceOptions, MTLSize};
use tiny_keccak::{Hasher, Keccak};

fn main() {
    // Safely obtain the default GPU device
    let device = Device::system_default().expect("Failed to find the default system GPU.");
    let command_queue = device.new_command_queue();

    // Data to hash, matching the Metal shader input requirements
    let data = b"Hello World!";

    // Create a GPU buffer from the data
    let data_buffer = device.new_buffer_with_data(
        data.as_ptr() as *const _,
        data.len() as u64,
        MTLResourceOptions::StorageModeShared,
    );

    // Buffer to store the result from GPU
    let result_hash_buffer = device.new_buffer(
        32, // Keccak256 hash output size
        MTLResourceOptions::StorageModeShared,
    );

    // New: Create a buffer for the input length
    let input_length = data.len() as u32;
    let input_length_buffer = device.new_buffer_with_data(
        &input_length as *const _ as *const _,
        std::mem::size_of::<u32>() as u64,
        MTLResourceOptions::CPUCacheModeWriteCombined,
    );

    // Load the Metal shader source code
    let source = include_str!("../keccak256.metal");
    let options = metal::CompileOptions::new();
    let library = device.new_library_with_source(source, &options).unwrap();
    let function = library.get_function("hash_kernel", None).unwrap();
    let pipeline_state = device
        .new_compute_pipeline_state_with_function(&function)
        .unwrap();

    // Setup and dispatch the GPU compute job
    let command_buffer = command_queue.new_command_buffer();
    let encoder = command_buffer.new_compute_command_encoder();
    encoder.set_compute_pipeline_state(&pipeline_state);
    encoder.set_buffer(0, Some(&data_buffer), 0);
    encoder.set_buffer(1, Some(&result_hash_buffer), 0);
    encoder.set_buffer(2, Some(&input_length_buffer), 0);

    // Dispatching a single thread group as the work is not size dependent
    encoder.dispatch_thread_groups(
        MTLSize {
            width: 1,
            height: 1,
            depth: 1,
        },
        MTLSize {
            width: 1,
            height: 1,
            depth: 1,
        },
    );
    encoder.end_encoding();
    command_buffer.commit();
    command_buffer.wait_until_completed();

    // Read the result from GPU
    let gpu_result =
        unsafe { std::slice::from_raw_parts(result_hash_buffer.contents() as *const u8, 32) };

    // Perform CPU hashing for verification
    let mut keccak = Keccak::v256();
    let mut cpu_result = [0u8; 32];
    keccak.update(data);
    keccak.finalize(&mut cpu_result);

    // Compare GPU and CPU results
    println!("CPU Hash result: {}", to_hex_string(&cpu_result));
    println!("GPU Hash result: {}", to_hex_string(&gpu_result));
    if gpu_result == cpu_result {
        println!("Success: GPU and CPU results match.");
    } else {
        println!("Error: GPU and CPU results do not match.");
    }
}

fn to_hex_string(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{:02x}", byte)).collect()
}
