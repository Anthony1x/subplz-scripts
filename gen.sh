#!/bin/bash

# Exit on error
set -e

# Get the absolute path of the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_DIR="$SCRIPT_DIR/media"
COMPOSE_FILE="$SCRIPT_DIR/compose.yml"

cleanup() {
    echo "--- Cleaning up Docker services ---"
    docker compose -f "$COMPOSE_FILE" stop
    sudo systemctl stop docker.service docker.socket
    echo "Docker services stopped."
}

# Ensure cleanup runs on exit (even on failure)
trap cleanup EXIT

echo "--- Starting Docker services ---"
sudo systemctl start docker.service
docker compose -f "$COMPOSE_FILE" up -d

# Default values
AUDIO_ONLY=false
URL=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --audio) AUDIO_ONLY=true ;;
        *) URL="$1" ;;
    esac
    shift
done

# Check if URL is provided
if [ -z "$URL" ]; then
    echo "Usage: $0 [--audio] <youtube-url>"
    exit 1
fi

mkdir -p "$MEDIA_DIR"

if [ "$AUDIO_ONLY" = true ]; then
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

    echo "Using audio file: $ACTUAL_FILE"

    echo "--- Generating subtitles ---"
    docker exec subplz subplz gen --audio "/media/$ACTUAL_FILE" --lang-ext az --model turbo --stable-ts

    echo "--- Cleaning up temporary audio file ---"
    rm "$ACTUAL_FULL_PATH"
    echo "Deleted $ACTUAL_FILE"
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

    echo "Using video file: $ACTUAL_FILE"

    echo "--- Generating subtitles ---"
    docker exec subplz subplz gen --audio "/media/$ACTUAL_FILE" --lang-ext az --model turbo --stable-ts

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
