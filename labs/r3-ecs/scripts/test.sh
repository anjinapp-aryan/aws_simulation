#!/usr/bin/env bash
N="${1:-9}"
for i in $(seq 1 "$N"); do
  curl -s http://localhost:38080/
done
