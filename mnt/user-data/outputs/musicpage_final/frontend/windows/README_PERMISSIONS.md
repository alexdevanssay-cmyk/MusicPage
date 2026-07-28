# windows/README_PERMISSIONS.md
# ────────────────────────────────
# Windows requires no special manifest entry for microphone access.
# The system will show a permission prompt on first run via the
# Windows privacy settings (Settings → Privacy → Microphone).
#
# If the app is distributed via the Microsoft Store, add the
# `microphone` capability to Package.appxmanifest:
#
#   <Capabilities>
#     <DeviceCapability Name="microphone"/>
#   </Capabilities>
#
# For MSIX packaging with flutter_distributor, this is added automatically
# when `record` is detected as a dependency.
