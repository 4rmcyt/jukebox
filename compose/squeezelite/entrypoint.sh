#!/bin/sh
# Runs squeezelite only inside work hours; outside them Music Assistant has no player to play to.
set -eu

# Any arguments bypass the schedule (e.g. `-l` to list audio outputs while testing).
if [ "$#" -gt 0 ]; then
  exec squeezelite-pulseaudio "$@"
fi

: "${WORK_DAYS:?e.g. Mon Tue Wed Thu Fri}" "${WORK_START:?e.g. 07:00}" "${WORK_END:?e.g. 17:00}"
start=$(echo "$WORK_START" | tr -d :)
end=$(echo "$WORK_END" | tr -d :)

in_hours() {
  case " $WORK_DAYS " in
    *" $(LC_ALL=C date +%a) "*) ;;
    *) return 1 ;;
  esac
  now=$(date +%H%M)
  [ "$now" -ge "$start" ] && [ "$now" -lt "$end" ]
}

pid=""
stop_player() {
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    pid=""
  fi
}
trap 'stop_player; exit 0' TERM INT

while :; do
  if in_hours; then
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      # OUTPUT_DEVICE pins the sink (e.g. bluez_output.<MAC>.1); empty = PipeWire default sink.
      squeezelite-pulseaudio -s "${MA_HOST:-127.0.0.1}" -n "${PLAYER_NAME:-Jukebox}" ${OUTPUT_DEVICE:+-o "$OUTPUT_DEVICE"} &
      pid=$!
    fi
  else
    stop_player
  fi
  sleep 30 &
  wait $! || true
done
