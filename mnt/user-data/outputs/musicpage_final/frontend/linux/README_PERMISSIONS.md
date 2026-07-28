# linux/README_PERMISSIONS.md
# ─────────────────────────────
# On Linux, microphone access is handled through PulseAudio / PipeWire.
# No special manifest is required. However:
#
# 1. The user running the app must be in the `audio` group:
#       sudo usermod -aG audio $USER    # then log out/in
#
# 2. PipeWire / PulseAudio must be running (default on most modern distros).
#
# 3. If using a Flatpak build, add the microphone permission:
#       --device=all   or   --socket=pulseaudio
#
# The `record` Flutter package uses ALSA/PulseAudio automatically on Linux.
