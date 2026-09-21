#!/usr/bin/env bash
# Run every PR check. usage: check.sh [base-ref]
d=$(dirname "$0")
bash "$d/complexity.sh" "$@"
echo
bash "$d/drift.sh" "$@"
