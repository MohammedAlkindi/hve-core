#!/usr/bin/env bash
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
# Detects file collisions before copying HVE-Core agents.
# Usage: collision-detection.sh <hve_core_base_path> <selection> [package_agents...]
#   selection: 'hve-core' for RPI core bundle, or marketplace package ID
#   package_agents: projected agent paths for non-default packages
set -euo pipefail

: "${1:?Usage: $0 <hve_core_base_path> <selection> [package_agents...]}"
selection="${2:?Usage: $0 <hve_core_base_path> <selection> [package_agents...]}"
shift 2

target_dir=".github/agents"

# Build file list based on selection
case "$selection" in
    hve-core)
        files_to_copy=(
            "hve-core/rpi-agent.agent.md"
            "hve-core/documentation.agent.md"
        )
        ;;
    *)
        files_to_copy=("$@")
        ;;
esac

# Check for collisions. The target is flat, so only the file name matters and
# two package agents sharing a name resolve to one target, reported once.
collisions=()
declare -A seen_targets
for file in ${files_to_copy[@]+"${files_to_copy[@]}"}; do
    filename=$(basename "$file")
    target_path="$target_dir/$filename"
    if [ -n "${seen_targets[$target_path]+x}" ]; then
        continue
    fi
    seen_targets["$target_path"]=1
    if [ -f "$target_path" ]; then
        collisions+=("$target_path")
    fi
done

if [ ${#collisions[@]} -gt 0 ]; then
    echo "COLLISIONS_DETECTED=true"
    IFS=','; echo "COLLISION_FILES=${collisions[*]}"
else
    echo "COLLISIONS_DETECTED=false"
fi
