# Wan2.2 TI2V-5B on Vulkan (Docker)

Local text-to-video and image-to-video with [Wan2.2-TI2V-5B](https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B).
The model runs through [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) in a Docker
container using the Vulkan backend (Mesa drivers), so no CUDA or ROCm is needed on the host.

Face swapping lives in a separate tool: see `faceswap.sh` and `Dockerfile.facefusion`.

## Requirements

- Docker, with your user allowed to run it
- A Vulkan GPU with Mesa drivers on the host (the target machine has an AMD RX 6650 XT on RADV). Its render node
  (`/dev/dri/renderD128`) is passed into the container.
- About 13 GB disk for the models, and about 8 GB of VRAM at Q8_0 (less with `QUANT=Q4_K_M`)

## Setup

```sh
./setup.sh                 # builds the wan-vulkan image and downloads the weights into models/
QUANT=Q4_K_M ./setup.sh    # smaller DiT quantization, if VRAM is tight
```

The downloads run inside the container and stay in `models/` on the host, so re-running `setup.sh`
skips anything already present.

| File | Source |
|---|---|
| `models/diffusion_models/Wan2.2-TI2V-5B-<QUANT>.gguf` | [QuantStack/Wan2.2-TI2V-5B-GGUF](https://huggingface.co/QuantStack/Wan2.2-TI2V-5B-GGUF) |
| `models/vae/wan2.2_vae.safetensors` | [Comfy-Org/Wan_2.2_ComfyUI_Repackaged](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged) |
| `models/text_encoders/umt5-xxl-encoder-Q8_0.gguf` | [city96/umt5-xxl-encoder-gguf](https://huggingface.co/city96/umt5-xxl-encoder-gguf) |

## Generate

```sh
# text to video
./generate.sh -p "a red fox running through snow, cinematic" -o out/fox.avi

# image + text to video (the image becomes the first frame)
./generate.sh -p "the cat turns its head toward the camera" -i photo.png -o out/cat.avi

./generate.sh --help       # all options
```

- Output goes to `out/` on the host. Paths you pass with `-o` and `-i` are resolved on the host and
  mounted into the container, so they can be anywhere on your disk.
- Defaults are 832x480, 33 frames at 24 fps (about 1.4 s), 50 steps, CFG 6.0. Width and height must be multiples of 16.
- Clip length is `-f` / `-r`: 33 frames at 24 fps is about 1.4 s. Raise `-f` for longer clips. The upstream docs use 33 and 81 frames, so stick to those counts.
- Fewer steps (`-s 4`) are only for quick tests: they give washed-out, nearly white frames.
- `-f` and `-s` increase time and memory.
- `IMAGE`, `QUANT`, and `RENDER_DEVICE` can be set as environment variables if your setup differs.

## Layout

```
Dockerfile.wan        sd-cli built with -DSD_VULKAN=ON, Mesa runtime
setup.sh              build the image and download the weights
generate.sh           run sd-cli in the container for T2V and I2V
models/               downloaded weights (git-ignored)
out/                  generated videos (git-ignored)
```

## Notes

- Low VRAM: use a smaller `QUANT`. `--offload-to-cpu` is on in `generate.sh`.
- If the output is black, NaN, or garbled, try `QUANT=Q8_0`, and check that the GPU shows up in the
  container's Vulkan device list.
- Only AMD and Intel GPUs have been considered here, through Mesa. NVIDIA would need the NVIDIA
  container toolkit and a different driver setup.
