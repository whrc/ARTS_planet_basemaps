#!/bin/bash

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate up to base_directory, then into data/
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$BASE_DIR/data"

INPUT_FILE="$DATA_DIR/planet_globus_manifest_renaming_manifest_redo.csv"
LOG_FILE="$DATA_DIR/globus_rename_log.txt"
BATCH_FILE="$DATA_DIR/batch_transfer.txt"
DELIMITER=","

ENDPOINT_ID="ff18481d-5e57-4aba-9d47-c91f6159cd36"

# # Define the parent directories to search (replace with your actual paths)
# PARENT_DIRS=(
#     "/global_quarterly/2016"
#     "/global_quarterly/2017"
#     "/global_quarterly/2018"
#     "/global_quarterly/2019"
#     "/global_quarterly/2020"
#     "/global_quarterly/2021"
#     "/global_quarterly/2022"
#     "/global_quarterly/2023"
# )

# Temporary file to store existing files
EXISTING_FILES_CACHE="$DATA_DIR/existing_files_cache.txt"

# echo "Building cache of existing files from parent directories..."

# # Clear the cache file
# > "$EXISTING_FILES_CACHE"

# # List all files recursively in each parent directory and cache them
# for parent_dir in "${PARENT_DIRS[@]}"; do
#     echo "Caching files from: $parent_dir"
#     globus ls --recursive "$ENDPOINT_ID:$parent_dir" 2>/dev/null | while read -r relative_path; do
#         # Construct full path: parent_dir + relative_path from recursive listing
#         echo "$parent_dir/$relative_path" >> "$EXISTING_FILES_CACHE"
#     done
# done

# echo "Cache built with $(wc -l < "$EXISTING_FILES_CACHE") files."
# echo "Processing transfer list..."

# Clear the batch file
> "$BATCH_FILE"
# > "$LOG_FILE"

# Process the CSV and build batch transfer file
while IFS="$DELIMITER" read -r old_name new_name; do
    # Skip empty lines or comments
    [[ -z "$old_name" || "$old_name" =~ ^# ]] && continue
    
    echo "Trimming whitespace."
    # Trim whitespace
    old_name=$(echo "$old_name" | xargs | tr -d '\r')
    new_name=$(echo "$new_name" | xargs | tr -d '\r')
    
    echo "Checking if destination exists."
    # Check if destination file already exists (using cache)
    if grep -qFx "$new_name" "$EXISTING_FILES_CACHE"; then
        echo "[SKIPPED] Destination exists: $new_name"
        echo "[SKIPPED] $old_name -> $new_name (destination exists)" >> "$LOG_FILE"
        continue
    fi
    
    echo "Checking if source file exists."
    # Check if source file exists (using cache or quick check)
    old_dir=$(dirname "$old_name")
    old_file=$(basename "$old_name")
    
    # Quick existence check - you could also cache source files
    if ! globus ls "$ENDPOINT_ID:$old_dir" 2>/dev/null | grep -q "^$old_file$"; then
        echo "[SKIPPED] Source not found: $old_name"
        echo "[SKIPPED] $old_name -> $new_name (source not found)" >> "$LOG_FILE"
        continue
    fi
    
    echo "Creating destination directory hierarchy."
    # Create destination directory hierarchy
    new_dir=$(dirname "$new_name")
    current_path=""
    IFS='/' read -ra PATH_PARTS <<< "$new_dir"
    for part in "${PATH_PARTS[@]}"; do
        if [[ -n "$part" ]]; then
            current_path="$current_path/$part"
            globus mkdir "$ENDPOINT_ID:$current_path" 2>/dev/null || true
        fi
    done
    
    echo "Adding to batch file."
    # Add to batch file (format: source_path destination_path)
    echo "$old_name $new_name" >> "$BATCH_FILE"
    echo "[QUEUED] $old_name -> $new_name" >> "$LOG_FILE"
    
done < "$INPUT_FILE"

# Check if there are any files to transfer
if [[ ! -s "$BATCH_FILE" ]]; then
    echo "No files to transfer. All files either exist or sources not found."
    exit 0
fi

# echo "Batch file created with $(wc -l < "$BATCH_FILE") transfers."
echo "Submitting batch transfer task..."

# Submit the batch transfer
TASK_OUTPUT=$(globus transfer "$ENDPOINT_ID" "$ENDPOINT_ID" \
    --label "Batch file reorganization" \
    --sync-level exists \
    --batch "$BATCH_FILE" 2>&1)

TASK_ID=$(echo "$TASK_OUTPUT" | grep -oP 'Task ID: \K[a-f0-9-]+')

if [[ -n "$TASK_ID" ]]; then
    echo "Task submitted: $TASK_ID"
    echo "Waiting for completion..."
    
    # Wait for task to complete
    globus task wait "$TASK_ID"
    EXIT_CODE=$?
    
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo "Batch transfer completed successfully!"
        # Mark all queued items as successful
        sed -i 's/\[QUEUED\]/[SUCCESS]/g' "$LOG_FILE"
    else
        echo "Batch transfer failed or partially completed."
        echo "Check task details with: globus task show $TASK_ID"
        
        # Get detailed task info to identify failures
        globus task show "$TASK_ID" --format json > "$DATA_DIR/task_result_${TASK_ID}.json"
        echo "Task details saved to: task_result_${TASK_ID}.json"
    fi
else
    echo "Failed to submit batch transfer task."
    echo "$TASK_OUTPUT"
    exit 1
fi

echo "Done. Check '$LOG_FILE' for results."

# Optionally clean up
# rm "$BATCH_FILE"
# rm "$EXISTING_FILES_CACHE"