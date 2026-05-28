#!/bin/bash

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate up to base_directory, then into data/
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$BASE_DIR/data"

INPUT_FILE="$DATA_DIR/planet_globus_renaming_manifest.csv"
LOG_FILE="$DATA_DIR/globus_rename_log.txt"
DELIMITER=","

PARALLEL_JOBS=20  # Number of concurrent renames
ENDPOINT_ID="ff18481d-5e57-4aba-9d47-c91f6159cd36"

# Clear or create the log file
# > "$LOG_FILE"

# Define the rename function that will be called in parallel
rename_file() {
    old_name="$1"
    new_name="$2"
    log_file="$3"
    endpoint_id="$4"
    
    echo "================================"
    # Skip empty lines or comments
    [[ -z "$old_name" || "$old_name" =~ ^# ]] && return
    
    # Trim whitespace
    old_name=$(echo "$old_name" | xargs)
    new_name=$(echo "$new_name" | xargs)
    
    # Check if source file exists - list parent directory and grep for filename
    old_dir=$(dirname "$old_name")
    old_file=$(basename "$old_name")
    
    echo "DEBUG: Checking if file exists: $old_name"
    echo "DEBUG: Directory: $old_dir"
    echo "DEBUG: Filename: $old_file"
    
    globus ls "$endpoint_id:$old_dir" 2>/dev/null | grep -q "^$old_file$"
    if [[ $? -ne 0 ]]; then
        echo "[SKIPPED] File already transferred or doesn't exist: $old_name"
        echo "[SKIPPED] $old_name -> $new_name (file not found)" >> "$log_file"
        return
    fi
    
    # Extract the destination directory
    new_dir=$(dirname "$new_name")
    
    # Create directory hierarchy recursively
    current_path=""
    IFS='/' read -ra PATH_PARTS <<< "$new_dir"
    for part in "${PATH_PARTS[@]}"; do
        if [[ -n "$part" ]]; then
            current_path="$current_path/$part"
            echo "Attempting to create: $current_path"
            globus mkdir "$endpoint_id:$current_path"
            mkdir_exit=$?
            echo "  mkdir exit code: $mkdir_exit"
        fi
    done
    
    echo "Renaming: '$old_name' -> '$new_name'"
    
    # Globus rename
    globus rename $endpoint_id "$old_name" "$new_name"
    EXIT_CODE=$?
    
    echo "Rename exit code: $EXIT_CODE"
    
    # Log the result (append atomically)
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo "[SUCCESS] $old_name -> $new_name" >> "$log_file"
    else
        echo "[FAILED]  $old_name -> $new_name (exit code: $EXIT_CODE)" >> "$log_file"
    fi
}

# Export the function and variables so parallel can use them
export -f rename_file
export LOG_FILE

# Run renames in parallel
cat "$INPUT_FILE" | parallel -j "$PARALLEL_JOBS" --colsep "$DELIMITER" rename_file {1} {2} "$LOG_FILE" "$ENDPOINT_ID"

echo "Done. Check '$LOG_FILE' for results."