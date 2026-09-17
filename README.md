# vLLM OpenAI mirror on Cloudflare R2

This repository mirrors the official
[`vllm/vllm-openai`](https://hub.docker.com/r/vllm/vllm-openai) container
images and publishes them to a **static container registry on Cloudflare R2**:
`public-docker-registry.valendra.net`.

The CUDA images are copied as published. The ROCm release is built from a
pinned upstream vLLM revision by a manual release workflow.

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

### Available tags

The mirror currently publishes two CUDA variants for each vLLM version:

| CUDA variant | Docker Hub source tag | R2 registry tag |
| --- | --- | --- |
| CUDA 12.9 (`cu129`) | `v0.23.0-cu129-ubuntu2404` | `v0.23.0-cu129-ubuntu2404` |
| CUDA 13 (`cu13`) | `v0.23.0-ubuntu2404` | `v0.23.0-ubuntu2404` |

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

The tag is unchanged when the image is copied. Only the registry host and
repository name change.

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
  requested release or nightly commit. Enter `0.23.0`, `v0.23.0`, or a full
  40-character commit SHA in the **vllm_ref** input.
- [Mirror latest vLLM image](.github/workflows/mirror-vllm-daily.yml) runs every
  day at `03:17 UTC`, finds the newest version with both CUDA tags, and mirrors
  both variants. It can also be started manually.
- [Mirror vLLM image](.github/workflows/mirror-vllm-reusable.yml) contains the
  shared copy/upload logic and the `cu129`/`cu13` matrix.
- [Build vLLM ROCm release](.github/workflows/build-vllm-rocm.yml) manually
  builds the pinned vLLM `0.29.0` ROCm image for `linux/amd64` and publishes
  `v0.29.0-rocm72-ubuntu2204`. Enter `PUBLISH` in the dispatch confirmation
  input. The workflow rejects an existing tag and uses a conditional R2 write,
  so a published release tag cannot be overwritten.

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
