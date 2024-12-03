#!/bin/bash

# Check if at least 3 arguments are passed
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <PLAYLIST_URL> <OUTPUT_FORMAT> <QUALITY>"
    echo "For MP3, QUALITY can be one of: 0 (best), 1, 2, ... 9 (worst)."
    exit 1
fi

# Assign arguments to variables
PLAYLIST_URL=$1
OUTPUT_FORMAT=$2
QUALITY=$3

# Retrieve channel and playlist names
CHANNEL_NAME=$(yt-dlp --quiet --print "%(uploader)s" --playlist-items 1 "$PLAYLIST_URL" | sed 's/ /_/g')
PLAYLIST_NAME=$(yt-dlp --quiet --print "%(playlist_title)s" --playlist-items 1 "$PLAYLIST_URL" | sed 's/ /_/g')

# Create directory structure
mkdir -p "$CHANNEL_NAME/$PLAYLIST_NAME"
cd "$CHANNEL_NAME/$PLAYLIST_NAME" || exit

if [ "$OUTPUT_FORMAT" = "mp3" ]; then
    # Download audio as MP3 with specified quality
    yt-dlp --extract-audio \
           --audio-format mp3 \
           --audio-quality "$QUALITY" \
           -o "%(playlist_index)s - %(title)s.%(ext)s" \
           "$PLAYLIST_URL"
else
    # Download video with specified quality
    yt-dlp -f "bestvideo[height<=$QUALITY]+bestaudio/best[height<=$QUALITY]" \
           --merge-output-format "$OUTPUT_FORMAT" \
           -o "%(playlist_index)s - %(title)s.%(ext)s" \
           "$PLAYLIST_URL"
fi

