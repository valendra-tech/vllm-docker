# vLLM OpenAI mirror on Cloudflare R2

This repository mirrors the official
[`vllm/vllm-openai`](https://hub.docker.com/r/vllm/vllm-openai) container
images and publishes them to a **static container registry on Cloudflare R2**:
`public-docker-registry.valendra.net`.

Official CUDA images are mirrored when available. The custom CUDA 12.9 and
ROCm releases are built from pinned upstream vLLM revisions.

## Use the mirror

Replace the source image:

```text
docker.io/vllm/vllm-openai:<tag>
```

with the corresponding image from the R2 registry:

```text
public-docker-registry.valendra.net/vllm:<tag>
```

Pulls are public: no `docker login` is needed.

### Release tag mapping

The R2 tags use the same naming scheme for upstream mirrors and custom builds:

| CUDA variant | Source | R2 registry tag |
| --- | --- | --- |
| CUDA 12.9 (`cu129`) | `v0.23.0-cu129-ubuntu2404` | `v0.23.0-cu129-ubuntu2404` |
| CUDA 13 (`cu13`) | `v0.23.0-ubuntu2404` | `v0.23.0-ubuntu2404` |
| CUDA 13.0 (`cu13`) | `v0.34.0` | `v0.34.0-ubuntu2404` |
| CUDA 12.9 (`cu129`) | vLLM `0.34.0` source build, `linux/amd64` | `v0.34.0-cu129-ubuntu2404` |

The first ROCm release is published separately:

| ROCm variant | Source revision | R2 registry tag |
| --- | --- | --- |
| ROCm 7.2.3, Ubuntu 22.04 (`gfx942;gfx950`) | vLLM `0.29.0` (`98dff2a8`) | `v0.29.0-rocm72-ubuntu2204` |

Nightly images can also be mirrored by their full vLLM commit SHA. The source
uses different tag prefixes for the two CUDA variants:

| CUDA variant | Docker Hub source tag | R2 registry tag |
| --- | --- | --- |
| CUDA 12.9 (`cu129`) | `cu129-nightly-<commit>` | `cu129-nightly-<commit>` |
| CUDA 13 (`cu13`) | `nightly-<commit>` | `nightly-<commit>` |

Nightly tags are copied unchanged.

### Pull an image

```bash
docker pull public-docker-registry.valendra.net/vllm:v0.23.0-cu129-ubuntu2404
docker pull public-docker-registry.valendra.net/vllm:v0.23.0-ubuntu2404
```

For a reproducible pull, use an immutable digest reference:

```bash
docker pull public-docker-registry.valendra.net/vllm@sha256:<digest>
```

Use the image with the normal vLLM Docker command, for example:

```bash
docker run --gpus all --ipc=host --network host \
  public-docker-registry.valendra.net/vllm:v0.23.0-cu129-ubuntu2404 \
  --model <model-name>
```

## Keeping the mirror up to date

GitHub Actions keeps the R2 registry synchronized with Docker Hub:

- [Mirror vLLM reference](.github/workflows/mirror-vllm.yml) manually mirrors a
  requested release or nightly commit. Enter `0.34.0`, `v0.34.0`, or a full
  40-character commit SHA in the **vllm_ref** input. If Docker Hub has no
  CUDA 12.9 tag for `0.34.0`, the workflow calls
  [the custom CUDA build](.github/workflows/build-vllm-cu129.yml).
- [Mirror latest vLLM image](.github/workflows/mirror-vllm-daily.yml) runs every
  day at `03:17 UTC`, finds the newest stable CUDA release, and mirrors the
  variants that are available on Docker Hub. It can also be started manually.
- [Mirror vLLM image](.github/workflows/mirror-vllm-reusable.yml) contains the
  shared tag resolution and copy/upload logic. For CUDA 13 it prefers the
  `-ubuntu2404` source tag and verifies the CUDA version before using the
  unsuffixed source tag instead.
- [Build vLLM ROCm release](.github/workflows/build-vllm-rocm.yml) manually
  builds the pinned vLLM `0.29.0` ROCm image for `linux/amd64` and publishes
  `v0.29.0-rocm72-ubuntu2204`. Enter `PUBLISH` in the dispatch confirmation
  input. The workflow rejects an existing tag and uses a conditional R2 write,
  so a published release tag cannot be overwritten.

The custom `0.34.0` build uses CUDA 12.9.1 and PyTorch `2.13.0+cu129` because
PyTorch `2.14.0` has no CUDA 12.9 wheel. CI checks the installed vLLM, PyTorch,
and CUDA versions before publishing and verifies the R2 manifest digest.

To build CUDA 12.9 without mirroring CUDA 13 again, manually run
[Build vLLM 0.34.0 with CUDA 12.9](.github/workflows/build-vllm-cu129.yml) from
`main`. Only this build uses a runner with the `self-hosted`, `linux`, and
`x64` labels. Use a dedicated, isolated, preferably ephemeral runner for this
public repository. Restrict its access to trusted workflows on `main`.

Start with 16 vCPUs and 64 GB of RAM. The runner needs a local Docker daemon
accessible to the runner user, Git, cURL, jq, Skopeo, and an up-to-date AWS
CLI v2. The workflow checks for at least 8 logical CPUs, 28 GiB of available
RAM, and 100 GiB free on each filesystem used for Docker storage and
`RUNNER_TEMP`. It does not install packages, delete host SDKs, or require a GPU.

The mirror workflows copy the source image to a local OCI layout with `skopeo`,
upload the objects to the `public-docker-registry` R2 bucket (S3-compatible
API), and validate the published registry. The ROCm workflow downloads the
upstream Dockerfile at the pinned vLLM commit, verifies its SHA-256, validates
the pinned ROCm 7.2.3/Ubuntu 22.04 base metadata, exports an OCI layout, and
performs the same R2 upload and manifest validation. All workflows require
these repository secrets:
`R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY`, plus the repository variable
`R2_ENDPOINT` (the bucket name is fixed as `public-docker-registry`).

## How it works

The R2 bucket is public behind the `public-docker-registry.valendra.net`
custom domain and acts as a static container registry: objects are stored
under the exact keys the OCI Distribution protocol expects
(`v2/`, `v2/vllm/manifests/<tag|digest>`, `v2/vllm/blobs/<digest>`), so
`docker pull` works with plain GET/HEAD requests and no server. The Docker
client verifies every blob and manifest digest itself.
