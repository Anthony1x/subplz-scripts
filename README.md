# SubPlz Wrapper

A convenient wrapper script for generating subtitles from YouTube URLs or local media files using the `subplz` Docker container. It automatically handles downloading (via `yt-dlp`), transcription (via `subplz` using OpenAI Whisper), and playback (via `mpv`).

## Prerequisites

- **Docker**: For running the transcription service.
- **NVIDIA GPU & Container Toolkit**: The `compose.yml` is configured for NVIDIA GPU acceleration.
- **yt-dlp**: Required for downloading videos from YouTube.
- **mpv**: Required for automatic playback of the video with generated subtitles.
- **sudo**: Required for the script to manage Docker services if they aren't already running.

## Setup

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd subplz
    ```

2.  **Configure Docker Compose:**
    The `compose.yml` is pre-configured to use the `kanjieater/subplz:latest` image and maps `./media` and `./config` directories. Ensure you have the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed if you plan to use GPU acceleration.

3.  **Permissions:**
    Make the script executable:
    ```bash
    chmod +x gen.sh
    ```

## Usage

The `gen.sh` script handles the entire lifecycle: starting Docker (if needed), downloading/linking the media, generating subtitles, and (optionally) opening the result in `mpv`.

### 1. Generate Subtitles for a YouTube Video (Default: Audio-only)
```bash
./gen.sh "https://www.youtube.com/watch?v=example_id"
```
Downloads only the audio, generates the subtitle file, and cleans up the audio file afterwards. This is the default behavior.

### 2. Full Video Workflow (Download & Play)
```bash
./gen.sh --video "https://www.youtube.com/watch?v=example_id"
```
This will download the full video, generate subtitles, and open it in `mpv`.

### 3. Local Media Files
```bash
./gen.sh /path/to/your/video.mp4
```
Generates subtitles for a local file. To also open the file in `mpv` after generation, add the `--video` flag:
```bash
./gen.sh --video /path/to/your/video.mp4
```

## How it Works

- **Docker Management**: The script checks if `docker.service` is running. If not, it starts it and ensures it's stopped after completion (only if it started it).
- **Service Isolation**: It uses `docker compose up -d` to manage the `subplz` container, stopping it only if it wasn't already running.
- **Transcription**: It uses the `turbo` model of Whisper for fast and accurate transcription.
- **Cleanup**: Temporary symlinks and downloaded audio-only files are automatically removed upon script exit.

## Configuration

- **Models**: You can change the Whisper model in `gen.sh` by modifying the `--model` flag (default is `turbo`).
- **Language**: The script currently uses `--lang-ext az`. Adjust this in `gen.sh` if you prefer a different language extension for the subtitle file.
