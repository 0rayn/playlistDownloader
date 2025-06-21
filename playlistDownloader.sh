#!/bin/bash
set -e

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <PLAYLIST_URL> <OUTPUT_FORMAT> <QUALITY>"
    echo "For MP3, QUALITY can be one of: 0 (best), 1, ..., 9 (worst)."
    exit 1
fi


# === Install dependencies ===
echo "🔧 Checking dependencies..."
for pkg in jq ffmpeg curl; do
    if ! command -v "$pkg" &>/dev/null; then
        echo "📦 Installing $pkg..."
        sudo apt-get update && sudo apt-get install -y "$pkg"
    fi
done

if ! command -v yt-dlp &>/dev/null; then
    echo "📦 Installing yt-dlp..."
    sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
    sudo chmod a+rx /usr/local/bin/yt-dlp
fi

# Clean URL from backslashes, newlines, and trim spaces
PLAYLIST_URL=$(echo "$1" | tr -d '\\\n\r' | xargs)
echo "Cleaned URL: $PLAYLIST_URL"

OUTPUT_FORMAT="$2"
QUALITY="$3"

# Get channel and playlist name (underscored)
CHANNEL_NAME=$(yt-dlp --quiet --print "%(uploader)s" --playlist-items 1 "$PLAYLIST_URL" | sed 's/ /_/g')
PLAYLIST_NAME=$(yt-dlp --quiet --print "%(playlist_title)s" --playlist-items 1 "$PLAYLIST_URL" | sed 's/ /_/g')

# Create directory
mkdir -p "$CHANNEL_NAME/$PLAYLIST_NAME"
cd "$CHANNEL_NAME/$PLAYLIST_NAME" || exit

if [ "$OUTPUT_FORMAT" = "mp3" ]; then
    yt-dlp --extract-audio \
           --audio-format mp3 \
           --audio-quality "$QUALITY" \
           --restrict-filenames \
           --download-archive archive.txt \
           -o "%(playlist_index)03d - %(title).200B.%(ext)s" \
           "$PLAYLIST_URL"
else
    yt-dlp -f "bestvideo[height<=$QUALITY]+bestaudio/best[height<=$QUALITY]" \
           --merge-output-format "$OUTPUT_FORMAT" \
           --restrict-filenames \
           --download-archive archive.txt \
           -o "%(playlist_index)03d - %(title).200B.%(ext)s" \
           "$PLAYLIST_URL"
fi

# === Download YouTube thumbnail as folder.jpg for Jellyfin ===

# Get video ID of the first item in the playlist
FIRST_VIDEO_ID=$(yt-dlp --quiet --print "%(id)s" --playlist-items 1 "$PLAYLIST_URL")

# Get the thumbnail URL
THUMBNAIL_URL="https://i.ytimg.com/vi/$FIRST_VIDEO_ID/maxresdefault.jpg"

# Download it as folder.jpg
if [ -n "$THUMBNAIL_URL" ]; then
    curl -sL "$THUMBNAIL_URL" -o folder.jpg
    if [ $? -eq 0 ] && file folder.jpg | grep -qE 'image|JPEG'; then
        echo "✅ Downloaded high-res thumbnail as folder.jpg"
    else
        echo "⚠️ Thumbnail download failed or not an image. Trying fallback..."
        # fallback to standard thumbnail
        curl -sL "https://i.ytimg.com/vi/$FIRST_VIDEO_ID/hqdefault.jpg" -o folder.jpg
    fi
else
    echo "❌ No thumbnail URL provided"
fi


# === Generate tvshow.nfo for Jellyfin ===

# Get playlist metadata
TITLE=$(yt-dlp --quiet --print "%(playlist_title)s" --playlist-items 1 "$PLAYLIST_URL")
STUDIO=$(yt-dlp --quiet --print "%(uploader)s" --playlist-items 1 "$PLAYLIST_URL")
DESCRIPTION=$(yt-dlp --quiet --print "%(description)s" --playlist-items 1 "$PLAYLIST_URL")

# Clean up special XML characters in description
DESCRIPTION_ESCAPED=$(echo "$DESCRIPTION" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')

# Write tvshow.nfo
cat > tvshow.nfo <<EOF
<tvshow>
  <title>$TITLE</title>
  <studio>$STUDIO</studio>
  <plot>$DESCRIPTION_ESCAPED</plot>
  <genre>YouTube</genre>
  <tag>Auto-downloaded</tag>
</tvshow>
EOF

echo "✅ tvshow.nfo created for Jellyfin."

# === Generate .nfo metadata files for Jellyfin ===

echo "📄 Generating .nfo metadata for each video..."

yt-dlp --flat-playlist --print "%(id)s %(title)s %(playlist_index)s" "$PLAYLIST_URL_CLEAN" | while read -r VIDEO_ID TITLE INDEX; do
    # Fetch detailed metadata for this video
    METADATA=$(yt-dlp --print-json "https://www.youtube.com/watch?v=$VIDEO_ID")

    # Extract fields using jq (requires jq installed)
    TITLE_SAFE=$(echo "$METADATA" | jq -r '.title' | sed 's/&/&amp;/g')
    PLOT=$(echo "$METADATA" | jq -r '.description' | sed 's/&/&amp;/g')
    AIR_DATE=$(echo "$METADATA" | jq -r '.upload_date' | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')  # Format YYYY-MM-DD

    # Find the matching downloaded file (you can adapt the filename pattern if needed)
    FILENAME_PATTERN=$(printf "%03d" "$INDEX")\ -\ *
    FILE=$(ls -1 | grep "^$FILENAME_PATTERN" | head -n 1)

    if [ -n "$FILE" ]; then
        BASENAME="${FILE%.*}"
        NFO_FILE="${BASENAME}.nfo"

        cat > "$NFO_FILE" <<EOF
<episodedetails>
  <title>$TITLE_SAFE</title>
  <season>1</season>
  <episode>$INDEX</episode>
  <plot>$PLOT</plot>
  <aired>$AIR_DATE</aired>
</episodedetails>
EOF

        echo "✅ Created $NFO_FILE"
    else
        echo "⚠️ No file found for index $INDEX — skipping .nfo"
    fi
done



echo "✅ Download complete in:"
echo "$PWD"
