#!/bin/bash
interval=$1
directory="/home/container/cronjobs/every-${interval}"

# List of file extensions to exclude from cron execution
EXCLUDE_EXTENSIONS=("pem" "log" "lock" "json" "conf" "crt" "key" "pem" "csr" "info")

# Get the list of files to process first
if [ -d "$directory" ]; then
    # Get all files and filter out excluded extensions
    file_list=()
    while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        extension="${filename##*.}"
        # Check if extension is not in exclude list
        if [[ ! " ${EXCLUDE_EXTENSIONS[@]} " =~ " $extension " ]]; then
            file_list+=("$file")
        fi
    done < <(find "$directory" -maxdepth 1 -type f -print0)
    
    # Log the file discovery
    echo "[$(date)] Found ${#file_list[@]} files to process in $directory"
    for file in "${file_list[@]}"; do
        filename=$(basename "$file")
        echo "[$(date)] - Will process: $filename"
    done
    
    # Process each file
    for file in "${file_list[@]}"; do
        filename=$(basename "$file")
        echo "[$(date)] Running cron job: $filename"
        
        # Make sure the file is executable before running
        if [ -f "$file" ]; then
            chmod +x "$file"
            echo "[$(date)] Made $filename executable"
        else
            echo "[$(date)] ERROR: File $filename not found"
            continue
        fi
        
        # Get file extension for supported types
        if [[ "$filename" == *.* ]]; then
            extension="${filename##*.}"
        else
            extension=""
        fi
        # Redirect output to console instead of log files
        case "$extension" in
            "php")
                # Execute PHP files as complete scripts
                echo "[$(date)] Running PHP job: $filename"
                php "$file" 2>&1 | while read line; do
                    echo "[$(date)] [PHP] $line"
                done
                ;;
            "sh")
                # Execute shell scripts
                echo "[$(date)] Running shell job: $filename"
                bash "$file" 2>&1 | while read line; do
                    echo "[$(date)] [SH] $line"
                done
                ;;
            "py")
                # Execute Python scripts
                echo "[$(date)] Running Python job: $filename"
                python3 "$file" 2>&1 | while read line; do
                    echo "[$(date)] [PY] $line"
                done
                ;;
            "go")

                temp_dir=$(mktemp -d)
                binary_name=$(basename "$file" .go)
                
                echo "[$(date)] Compiling Go job: $filename"
                
                # Compile the Go file
                GOOS=linux GOARCH=$(dpkg --print-architecture) go build -o "$temp_dir/$binary_name" "$file" 2>&1 | while read line; do
                    echo "[$(date)] [GO-COMPILE] $line"
                done
                
                compile_exit_code=$?
                if [ $compile_exit_code -eq 0 ]; then
                    echo "[$(date)] Compilation successful. Running binary."
                    # Execute the compiled binary
                    "$temp_dir/$binary_name" 2>&1 | while read line; do
                        echo "[$(date)] [GO-RUN] $line"
                    done
                else
                    echo "[$(date)] Compilation failed with exit code $compile_exit_code. Check output above for details."
                fi
                
                # Clean up the temporary directory
                rm -rf "$temp_dir"
                ;;
            "")
                # Execute files with no extension as a binary
                echo "[$(date)] Running binary job: $filename"
                
                # Double-check file exists and is executable
                if [ ! -f "$file" ]; then
                    echo "[$(date)] ERROR: File $filename not found"
                    continue
                fi
                
                # Check if file is executable
                if [ ! -x "$file" ]; then
                    echo "[$(date)] WARNING: File $filename is not executable, attempting to fix..."
                    chmod +x "$file"
                    if [ ! -x "$file" ]; then
                        echo "[$(date)] ERROR: Failed to make $filename executable"
                        continue
                    fi
                    echo "[$(date)] Successfully made $filename executable"
                fi
                
                # Try to execute the file
                echo "[$(date)] Executing $filename..."
                if "$file" 2>&1 | while read line; do
                    echo "[$(date)] [BINARY] $line"
                done; then
                    echo "[$(date)] Binary job $filename completed successfully"
                else
                    exit_code=$?
                    echo "[$(date)] ERROR: Binary execution failed with exit code $exit_code."
                    echo "[$(date)] This often means a missing library or dependency. Try running 'ldd $file' in your shell."
                fi
                ;;
            *)
                echo "[$(date)] Unsupported file type: $extension"
                ;;
        esac
    done
else
    echo "[$(date)] Cron directory not found: $directory"
fi
