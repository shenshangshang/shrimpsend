/// Wide layout breakpoint — keep in sync with web `deviceListPanelWidth.ts`.
const double kDeviceListWideBreakpoint = 768;

/// Sidebar width at the minimum wide viewport (768px).
const double kDeviceListPanelMinWidth = 220;

/// Sidebar width cap on very large screens.
const double kDeviceListPanelMaxWidth = 264;

/// Fraction of viewport width used for the device list on wide layouts.
const double kDeviceListPanelWidthRatio = 0.205;

/// Absolute minimum when the user drags the divider.
const double kDeviceListPanelDragMinWidth = 220;

/// Absolute maximum when the user drags the divider.
const double kDeviceListPanelDragMaxWidth = 320;

/// Resolve device-list sidebar width from viewport width.
double resolveDeviceListPanelWidth(double viewportWidth) {
  if (viewportWidth < kDeviceListWideBreakpoint) {
    return viewportWidth;
  }
  final raw = viewportWidth * kDeviceListPanelWidthRatio;
  return raw.clamp(kDeviceListPanelMinWidth, kDeviceListPanelMaxWidth);
}
