#!/bin/bash

# Exit on error
set -e

# Get the absolute path of the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_DIR="$SCRIPT_DIR/media"
COMPOSE_FILE="$SCRIPT_DIR/compose.yml"

# Check if Docker is already running
if systemctl is-active --quiet docker.service; then
    DOCKER_ALREADY_RUNNING=true
else
    DOCKER_ALREADY_RUNNING=false
fi

# Check if subplz container is already running
if [ "$(docker ps -q -f name=subplz)" ]; then
    CONTAINER_ALREADY_RUNNING=true
else
    CONTAINER_ALREADY_RUNNING=false
fi

cleanup() {
    echo "--- Cleaning up ---"
    
    # If we created a symlink for a local file, remove it
    if [ "$IS_LINKED" = true ] && [ -L "$ACTUAL_FULL_PATH" ]; then
        echo "Removing temporary symlink..."
        rm "$ACTUAL_FULL_PATH"
    fi

    # Only stop the container if it wasn't running before
    if [ "$CONTAINER_ALREADY_RUNNING" = false ]; then
        echo "Stopping subplz container..."
        docker compose -f "$COMPOSE_FILE" stop
    fi

    # Only stop the docker service if it wasn't running before
    if [ "$DOCKER_ALREADY_RUNNING" = false ]; then
        echo "Stopping Docker services..."
        sudo systemctl stop docker.service docker.socket
    fi
    echo "Done."
}

# Ensure cleanup runs on exit (even on failure)
trap cleanup EXIT

# Start Docker if not running
if [ "$DOCKER_ALREADY_RUNNING" = false ]; then
    echo "--- Starting Docker services ---"
    sudo systemctl start docker.service
fi

# Start container if not running
echo "--- Ensuring subplz container is running ---"
docker compose -f "$COMPOSE_FILE" up -d

# Default values
VIDEO_MODE=false
INPUT=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --video) VIDEO_MODE=true ;;
        --audio) VIDEO_MODE=false ;; # Keep for backward compatibility/clarity
        *) INPUT="$1" ;;
    esac
    shift
done

if [ -z "$INPUT" ]; then
    echo "Usage: $0 [--video] <youtube-url|local-file>"
    exit 1
fi

mkdir -p "$MEDIA_DIR"

IS_LINKED=false
IS_LOCAL=false

if [ -f "$INPUT" ]; then
    IS_LOCAL=true
    echo "--- Using local file ---"
    ACTUAL_FILE=$(basename "$INPUT")
    ACTUAL_FULL_PATH="$MEDIA_DIR/$ACTUAL_FILE"
    
    # If the file is not in the media directory, create a symlink
    if [[ "$(realpath "$INPUT")" != "$(realpath "$ACTUAL_FULL_PATH" 2>/dev/null)" ]]; then
        ln -sf "$(realpath "$INPUT")" "$ACTUAL_FULL_PATH"
        IS_LINKED=true
    fi
else
    URL="$INPUT"
    if [ "$VIDEO_MODE" = false ]; then
        echo "--- Downloading audio only ---"
        FILENAME=$(yt-dlp --print filename -x -o "%(title)s [%(id)s].%(ext)s" "$URL")
        FULL_PATH="$MEDIA_DIR/$FILENAME"
        
        if [ ! -f "$FULL_PATH" ]; then
            yt-dlp -x -o "$FULL_PATH" "$URL"
        else
            echo "Audio already exists: $FILENAME"
        fi
        
        VIDEO_ID=$(yt-dlp --get-id "$URL")
        ACTUAL_FILE=$(ls "$MEDIA_DIR" | grep "\[$VIDEO_ID\]" | grep -v "\.srt$" | head -n 1)
        ACTUAL_FULL_PATH="$MEDIA_DIR/$ACTUAL_FILE"
    else
        echo "--- Downloading video ---"
        FILENAME=$(yt-dlp --print filename -o "%(title)s [%(id)s].%(ext)s" "$URL")
        FULL_PATH="$MEDIA_DIR/$FILENAME"

        if [ ! -f "$FULL_PATH" ]; then
            yt-dlp -o "$FULL_PATH" "$URL"
        else
            echo "Video already exists: $FILENAME"
        fi

        VIDEO_ID=$(yt-dlp --get-id "$URL")
        ACTUAL_FILE=$(ls "$MEDIA_DIR" | grep "\[$VIDEO_ID\]" | grep -v "\.srt$" | head -n 1)
        ACTUAL_FULL_PATH="$MEDIA_DIR/$ACTUAL_FILE"
    fi
fi

echo "Using file: $ACTUAL_FILE"

echo "--- Generating subtitles ---"
docker exec subplz subplz gen --audio "/media/$ACTUAL_FILE" --lang-ext az --model turbo --stable-ts

if [ "$VIDEO_MODE" = false ]; then
    if [ "$IS_LOCAL" = false ]; then
        echo "--- Cleaning up temporary audio file ---"
        rm "$ACTUAL_FULL_PATH"
        echo "Deleted $ACTUAL_FILE"
    fi
else
    BASENAME="${ACTUAL_FILE%.*}"
    SUB_FILE="$MEDIA_DIR/$BASENAME.az.srt"

    if [ -f "$SUB_FILE" ]; then
        echo "--- Opening in mpv ---"
        mpv "$ACTUAL_FULL_PATH" --sub-file="$SUB_FILE"
    else
        echo "Error: Subtitle file not found at $SUB_FILE"
        exit 1
    fi
fi
