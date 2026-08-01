#!/usr/bin/env bash
set -euo pipefail

while true; do
  for entry in "8084 dev" "8085 stg" "8086 prod"; do
    read -r port env <<< "$entry"
    for path in hello bye; do
      code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/greetings/$path")
      echo "$(date '+%H:%M:%S') $env /$path -> $code"
    done
  done
  sleep 10
done
