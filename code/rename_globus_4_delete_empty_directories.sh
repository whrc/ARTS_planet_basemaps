#!/bin/bash

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate up to base_directory, then into data/
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$BASE_DIR/data"

LOG_FILE="$DATA_DIR/globus_empty_dir_delete_log.txt"

ENDPOINT_ID="ff18481d-5e57-4aba-9d47-c91f6159cd36"

# Define the parent directories to search (replace with your actual paths)
PARENT_DIRS=(
    "/global_quarterly/global_quarterly_2016q3_mosaic"
    "/global_quarterly/global_quarterly_2017q3_mosaic"
    "/global_quarterly/global_quarterly_2018q3_mosaic"
    "/global_quarterly/global_quarterly_2019q3_mosaic"
    "/global_quarterly/global_quarterly_2020q3_mosaic"
    "/global_quarterly/global_quarterly_2021q3_mosaic"
    "/global_quarterly/global_quarterly_2022q3_mosaic"
    "/global_quarterly/global_quarterly_2023q3_mosaic"
)

echo "Finding and deleting empty directories..."

# Process each parent directory
for parent_dir in "${PARENT_DIRS[@]}"; do
    echo "Processing: $parent_dir"
    
    # Get all directories recursively (ls with trailing slash shows directories)
    ALL_DIRS=$(globus ls --recursive "$ENDPOINT_ID:$parent_dir" 2>/dev/null | grep '/$')
    
    if [[ -z "$ALL_DIRS" ]]; then
        echo "No subdirectories found in $parent_dir"
        continue
    fi
    
    # Process directories from deepest to shallowest (reverse sort by depth)
    echo "$ALL_DIRS" | awk '{print length($0), $0}' | sort -rn | cut -d' ' -f2- | while read -r relative_dir; do
        # Remove trailing slash
        relative_dir="${relative_dir%/}"
        full_dir="$parent_dir/$relative_dir"
        
        # Check if directory is empty
        CONTENTS=$(globus ls "$ENDPOINT_ID:$full_dir" 2>/dev/null)
        
        if [[ -z "$CONTENTS" ]]; then
            echo "Deleting empty directory: $full_dir"
            
            # Try to delete the empty directory
            globus delete -r --notify off "$ENDPOINT_ID:$full_dir/" 2>&1
            DELETE_EXIT=$?
            
            if [[ $DELETE_EXIT -eq 0 ]]; then
                echo "[DELETED] $full_dir" >> "$LOG_FILE"
            else
                echo "[FAILED] $full_dir" >> "$LOG_FILE"
            fi
        else
            echo "Skipping (not empty): $full_dir"
        fi
    done
    
    # Also check if the parent directory itself is now empty
    PARENT_CONTENTS=$(globus ls "$ENDPOINT_ID:$parent_dir" 2>/dev/null)
    if [[ -z "$PARENT_CONTENTS" ]]; then
        echo "Parent directory is now empty: $parent_dir"
        globus delete "$ENDPOINT_ID:$parent_dir/" 2>&1
        echo "[DELETED] $parent_dir" >> "$LOG_FILE"
    fi
    
    echo ""
done

echo "Done. Check '$LOG_FILE' for results."