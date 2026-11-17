/opt/homebrew/bin/llama-server


# how to upgrade it 

brew list | grep llama
llama.cpp


brew upgrade llama-server

llama-server --version
load_backend: loaded BLAS backend from /opt/homebrew/Cellar/ggml/0.10.0/libexec/libggml-blas.so
ggml_metal_device_init: tensor API disabled for pre-M5 and pre-A19 devices
ggml_metal_library_init: using embedded metal library
ggml_metal_library_init: loaded in 0.009 sec
ggml_metal_rsets_init: creating a residency set collection (keep_alive = 180 s)
ggml_metal_device_init: GPU name:   MTL0
ggml_metal_device_init: GPU family: MTLGPUFamilyApple9  (1009)
ggml_metal_device_init: GPU family: MTLGPUFamilyCommon3 (3003)
ggml_metal_device_init: GPU family: MTLGPUFamilyMetal4  (5002)
ggml_metal_device_init: simdgroup reduction   = true
ggml_metal_device_init: simdgroup matrix mul. = true
ggml_metal_device_init: has unified memory    = true
ggml_metal_device_init: has bfloat            = true
ggml_metal_device_init: has tensor            = false
ggml_metal_device_init: use residency sets    = true
ggml_metal_device_init: use shared buffers    = true
ggml_metal_device_init: recommendedMaxWorkingSetSize  = 12713.12 MB
load_backend: loaded MTL backend from /opt/homebrew/Cellar/ggml/0.10.0/libexec/libggml-metal.so
load_backend: loaded CPU backend from /opt/homebrew/Cellar/ggml/0.10.0/libexec/libggml-cpu-apple_m4.so
version: 8920 (15fa3c493)
built with AppleClang 21.0.0.21000099 for Darwin arm64

## support .gguf




#  GGUF 和 safetensors 的区别是什么