#!/usr/bin/env bash
# Build the Wan/stable-diffusion.cpp Docker image and download the Wan2.2 TI2V-5B
# weights into ./models. Safe to re-run: finished downloads are skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${IMAGE:-wan-vulkan}"
QUANT="${QUANT:-Q8_0}"          # DiT quantization: Q2_K ... Q8_0 (smaller = less VRAM)
HF="https://huggingface.co"

mkdir -p "$ROOT/models" "$ROOT/out"

docker build -f "$ROOT/Dockerfile.wan" -t "$IMAGE" "$ROOT"

# Downloads run inside the container (it has curl), writing as the host user
read -r -d '' FETCH <<EOF || true
set -euo pipefail
fetch() {
    local url="\$1" dest="\$2"
    if [ ! -f "\$dest" ]; then
        echo "Downloading \$(basename "\$dest")"
        curl -L --fail -C - -o "\$dest.part" "\$url"
        mv "\$dest.part" "\$dest"
    fi
}
mkdir -p /models/diffusion_models /models/vae /models/text_encoders
fetch "$HF/QuantStack/Wan2.2-TI2V-5B-GGUF/resolve/main/Wan2.2-TI2V-5B-$QUANT.gguf" /models/diffusion_models/Wan2.2-TI2V-5B-$QUANT.gguf
fetch "$HF/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan2.2_vae.safetensors" /models/vae/wan2.2_vae.safetensors
fetch "$HF/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q8_0.gguf" /models/text_encoders/umt5-xxl-encoder-Q8_0.gguf
EOF

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$ROOT/models":/models \
    --entrypoint bash \
    "$IMAGE" -c "$FETCH"

echo "Setup complete. Run ./generate.sh --help"
