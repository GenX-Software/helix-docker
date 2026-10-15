#!/usr/bin/env bash
set -euo pipefail

tag=${1:-helix-p4d:2026.1}
docker build -t "$tag" --platform linux/amd64 .
echo "Built $tag"
