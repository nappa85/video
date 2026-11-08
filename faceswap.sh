#!/usr/bin/env bash
# Swap the face in a video with the face from an image, using FaceFusion in Docker.
#
#   ./faceswap.sh setup
#   ./faceswap.sh -s face.jpg -t clip.mp4 -o out/swapped.mp4
#
# FaceFusion's ONNX Runtime builds have no Vulkan provider, so this runs on CPU.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${IMAGE:-facefusion}"
PROVIDER="${PROVIDER:-cpu}"     # cpu, or openvino (Intel GPU/NPU) if you have one

usage() {
    cat <<EOF
Usage:
  $0 setup                         build the Docker image (FaceFusion + dependencies)
  $0 -s SOURCE -t TARGET -o OUTPUT swap the face in TARGET with the face in SOURCE

  -s SOURCE   image containing the face to use
  -t TARGET   video (or image) whose face gets replaced
  -o OUTPUT   output path

Environment: PROVIDER (default cpu), IMAGE (default facefusion)
EOF
}

if [ "${1:-}" = "setup" ]; then
    docker build -f "$ROOT/Dockerfile.facefusion" -t "$IMAGE" "$ROOT"
    echo "Image built. Run: $0 -s SOURCE -t TARGET -o OUTPUT"
    exit 0
fi

SOURCE=""
TARGET=""
OUTPUT=""

while getopts "s:t:o:h" opt; do
    case "$opt" in
        s) SOURCE="$OPTARG" ;;
        t) TARGET="$OPTARG" ;;
        o) OUTPUT="$OPTARG" ;;
        h|*) usage; exit 0 ;;
    esac
done

if [ -z "$SOURCE" ] || [ -z "$TARGET" ] || [ -z "$OUTPUT" ]; then
    usage >&2
    exit 1
fi
if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
    echo "Image $IMAGE not found. Run $0 setup first." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

# Resolve host paths, then mount each file's directory into the container.
# Inside the container the files are /in/source/<name>, /in/target/<name>, /out/<name>.
SOURCE="$(realpath "$SOURCE")"
TARGET="$(realpath "$TARGET")"
OUTPUT="$(realpath -m "$OUTPUT")"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$(dirname "$SOURCE")":/in/source:ro \
    -v "$(dirname "$TARGET")":/in/target:ro \
    -v "$(dirname "$OUTPUT")":/out \
    "$IMAGE" \
    headless-run \
    --processors face_swapper \
    --source-paths "/in/source/$(basename "$SOURCE")" \
    --target-path "/in/target/$(basename "$TARGET")" \
    --output-path "/out/$(basename "$OUTPUT")" \
    --execution-providers "$PROVIDER"

echo "Wrote $OUTPUT"
