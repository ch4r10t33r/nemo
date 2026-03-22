// Multi-arch build (always amd64 + arm64). Requires buildx and a registry for --push.
//   docker buildx bake --push
//   IMAGE_NAME=ghcr.io/you/nemo:v1 docker buildx bake --push

variable "IMAGE_NAME" {
  default = "nemo:latest"
}

group "default" {
  targets = ["nemo"]
}

target "nemo" {
  context    = "."
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags       = [IMAGE_NAME]
}
