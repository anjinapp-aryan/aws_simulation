#!/usr/bin/env bash
# Real image lifecycle against the real local registry: build -> tag -> push.
# Usage: build-push.sh <v1|v2|bad>
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-v1}"
if [ "$TAG" = "bad" ]; then
  echo "Not building 'bad' - it's intentionally never pushed (Experiment R3-05)."
  exit 0
fi
sed -i.bak "s/VERSION = os.environ.get(\"VERSION\", \".*\")/VERSION = os.environ.get(\"VERSION\", \"${TAG#v}\")/" app/server.py
rm -f app/server.py.bak
docker build -t "localhost:5000/r3-app:${TAG}" ./app
docker push "localhost:5000/r3-app:${TAG}"
echo "Pushed localhost:5000/r3-app:${TAG}"
