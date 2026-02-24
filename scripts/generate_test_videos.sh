#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-/Users/test/XCodeProjects/CompressTarget_data}"
mkdir -p "$OUT_DIR"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required" >&2
  exit 1
fi
if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe is required" >&2
  exit 1
fi

resolutions=("1280x720" "1920x1080" "3840x2160")
durations_default=(5 30 60 120)
durations_4k=(5 30)
containers=("mov" "mp4")

manifest="$OUT_DIR/manifest.csv"
echo "file,codec,hdr,container,resolution,duration_seconds,size_bytes" > "$manifest"

make_video() {
  local codec="$1"
  local hdr="$2"
  local container="$3"
  local resolution="$4"
  local duration="$5"
  local bitrate
  case "$resolution" in
    "1280x720") bitrate="2500k" ;;
    "1920x1080") bitrate="5000k" ;;
    "3840x2160") bitrate="14000k" ;;
    *)
      echo "Unsupported resolution: $resolution" >&2
      exit 1
      ;;
  esac

  local out_file="$OUT_DIR/${codec}_${hdr}_${resolution}_${duration}s.${container}"
  local fmt_filter="format=yuv420p"
  local codec_args=()

  if [[ "$codec" == "h264" ]]; then
    codec_args=(
      -c:v libx264
      -profile:v high
      -pix_fmt yuv420p
      -preset veryfast
      -b:v "$bitrate"
      -maxrate "$bitrate"
      -bufsize "$bitrate"
    )
  elif [[ "$codec" == "hevc" && "$hdr" == "sdr" ]]; then
    codec_args=(
      -c:v libx265
      -pix_fmt yuv420p
      -preset veryfast
      -tag:v hvc1
      -b:v "$bitrate"
      -maxrate "$bitrate"
      -bufsize "$bitrate"
    )
  else
    fmt_filter="format=yuv420p10le"
    codec_args=(
      -c:v libx265
      -pix_fmt yuv420p10le
      -preset veryfast
      -tag:v hvc1
      -x265-params "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr-opt=1"
      -b:v "$bitrate"
      -maxrate "$bitrate"
      -bufsize "$bitrate"
    )
  fi

  echo "Generating $out_file"
  ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "testsrc2=size=${resolution}:rate=30" \
    -f lavfi -i "sine=frequency=1000:sample_rate=48000" \
    -t "$duration" -shortest \
    -vf "$fmt_filter" \
    "${codec_args[@]}" \
    -c:a aac -b:a 128k -movflags +faststart \
    "$out_file"

  local size_bytes
  size_bytes=$(stat -f "%z" "$out_file")
  echo "$(basename "$out_file"),$codec,$hdr,$container,$resolution,$duration,$size_bytes" >> "$manifest"
}

for resolution in "${resolutions[@]}"; do
  if [[ "$resolution" == "3840x2160" ]]; then
    durations=("${durations_4k[@]}")
  else
    durations=("${durations_default[@]}")
  fi

  for duration in "${durations[@]}"; do
    for container in "${containers[@]}"; do
      make_video "h264" "sdr" "$container" "$resolution" "$duration"
      make_video "hevc" "sdr" "$container" "$resolution" "$duration"
      make_video "hevc" "hdr" "$container" "$resolution" "$duration"
    done
  done

done

echo "Generated dataset at: $OUT_DIR"
echo "Manifest: $manifest"
