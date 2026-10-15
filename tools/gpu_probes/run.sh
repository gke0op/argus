#!/bin/zsh
# GPU probes: tiny Metal kernels that each isolate one cost on this Mac's GPU.
# Usage (from the repo root): make gpu-probes   or   tools/gpu_probes/run.sh [probe.metal ...]
# Each line: the harness's BGRA8 profile (median of 120 frames at 1920x1200).
# Compare within a group (00 vs 01, 10 vs 11 ...); absolute numbers vary with the chip.
# Findings are in .claude/skills/argus-metal-theme/SKILL.md section 5.
cd "${0:A:h}/../.."
probes=("$@")
(( ${#probes} )) || probes=(tools/gpu_probes/*.metal)
out=${TMPDIR:-/tmp}/argus_probe.png
for f in $probes; do
  r=$(make harness THEME=$f FRAMES=30 OUT=$out 2>&1)
  p=$(echo "$r" | grep "Profile" | sed 's/.*: //')
  e=$(echo "$r" | grep "error:" | head -1)
  printf "%-30s %s %s\n" "${f:t:r}" "$p" "$e"
done
