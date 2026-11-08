#!/usr/bin/env bash
# Text-to-video, or image-to-video when an input image is given (Wan2.2 TI2V-5B).
# Runs sd-cli inside the wan-vulkan Docker image with the host GPU passed through.
#
#   ./generate.sh -p "a cat walking on a beach" -o out/cat.avi
#   ./generate.sh -p "the cat turns its head" -i photo.png -o out/cat_i2v.avi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${IMAGE:-wan-vulkan}"
QUANT="${QUANT:-Q8_0}"
RENDER_DEVICE="${RENDER_DEVICE:-/dev/dri/renderD128}"

PROMPT=""
INPUT_IMAGE=""
OUT="$ROOT/out/video_$(date +%Y%m%d_%H%M%S).avi"
NEGATIVE="blurry, static, low quality, distorted, watermark, text"
WIDTH=832
HEIGHT=480
FRAMES=33        # 33 latent-clean frame count from the upstream examples
FPS=24           # Wan2.2 TI2V-5B is trained for 24 fps; the model default is 16
STEPS=50         # the Wan reference sampler uses 50; fewer steps give washed-out frames
CFG=6.0
SEED=-1

usage() {
    cat <<EOF
Usage: $0 -p PROMPT [options]
  -p PROMPT     text prompt (required)
  -i IMAGE      first-frame image; enables image-to-video
  -o OUTPUT     output video path (default: out/video_<timestamp>.avi)
  -n NEGATIVE   negative prompt
  -W WIDTH      default $WIDTH (must be a multiple of 16)
  -H HEIGHT     default $HEIGHT (must be a multiple of 16)
  -f FRAMES     default $FRAMES (duration = FRAMES / FPS)
  -r FPS        default $FPS
  -s STEPS      default $STEPS
  -c CFG        CFG scale, default $CFG
  -S SEED       default -1 (random)
Environment: QUANT (default Q8_0, must match what setup.sh downloaded),
             RENDER_DEVICE (default /dev/dri/renderD128)
EOF
}

while getopts "p:i:o:n:W:H:f:r:s:c:S:h" opt; do
    case "$opt" in
        p) PROMPT="$OPTARG" ;;
        i) INPUT_IMAGE="$OPTARG" ;;
        o) OUT="$OPTARG" ;;
        n) NEGATIVE="$OPTARG" ;;
        W) WIDTH="$OPTARG" ;;
        H) HEIGHT="$OPTARG" ;;
        f) FRAMES="$OPTARG" ;;
        r) FPS="$OPTARG" ;;
        s) STEPS="$OPTARG" ;;
        c) CFG="$OPTARG" ;;
        S) SEED="$OPTARG" ;;
        h|*) usage; exit 0 ;;
    esac
done

if [ -z "$PROMPT" ]; then
    usage >&2
    exit 1
fi
if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
    echo "Image $IMAGE not found. Run ./setup.sh first." >&2
    exit 1
fi
if [ ! -e "$RENDER_DEVICE" ]; then
    echo "GPU render device $RENDER_DEVICE not found." >&2
    exit 1
fi
if [ ! -f "$ROOT/models/diffusion_models/Wan2.2-TI2V-5B-$QUANT.gguf" ]; then
    echo "Weights missing. Run ./setup.sh first." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"

# Extra sd-cli flags, split on spaces, e.g. EXTRA_ARGS="--backend vae=cpu"
EXTRA=()
if [ -n "${EXTRA_ARGS:-}" ]; then
    read -r -a EXTRA <<< "$EXTRA_ARGS"
fi

# Resolve host paths, then mount each file's directory into the container.
OUT="$(realpath -m "$OUT")"
MOUNTS=(
    -v "$ROOT/models":/models:ro
    -v "$(dirname "$OUT")":/out
)
INPUT_ARGS=()
if [ -n "$INPUT_IMAGE" ]; then
    INPUT_IMAGE="$(realpath "$INPUT_IMAGE")"
    MOUNTS+=(-v "$(dirname "$INPUT_IMAGE")":/in:ro)
    INPUT_ARGS=(-i "/in/$(basename "$INPUT_IMAGE")")
fi

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    --device /dev/dri \
    --group-add "$(stat -c %g "$RENDER_DEVICE")" \
    "${MOUNTS[@]}" \
    "$IMAGE" \
    -M vid_gen \
    --diffusion-model "/models/diffusion_models/Wan2.2-TI2V-5B-$QUANT.gguf" \
    --vae /models/vae/wan2.2_vae.safetensors \
    --t5xxl /models/text_encoders/umt5-xxl-encoder-Q8_0.gguf \
    -p "$PROMPT" \
    -n "$NEGATIVE" \
    -W "$WIDTH" -H "$HEIGHT" \
    --video-frames "$FRAMES" \
    --fps "$FPS" \
    --steps "$STEPS" \
    --cfg-scale "$CFG" \
    --sampling-method euler \
    --flow-shift 3.0 \
    --offload-to-cpu \
    --seed "$SEED" \
    -o "/out/$(basename "$OUT")" \
    "${INPUT_ARGS[@]}" \
    "${EXTRA[@]}" \
    -v

echo "Wrote $OUT"
