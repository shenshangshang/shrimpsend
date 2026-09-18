package dev.ultrasend.backend.realtime;

public final class WukongimDeviceFlags {

    public static final int APP = 0;
    public static final int WEB = 1;
    public static final int DESKTOP = 2;
    public static final int SECONDARY = 0;

    private WukongimDeviceFlags() {}

    public static int fromPlatform(String platform) {
        if (platform == null || platform.isBlank()) {
            return APP;
        }
        return switch (platform.trim().toLowerCase()) {
            case "web", "browser" -> WEB;
            case "macos", "windows", "linux", "pc", "desktop" -> DESKTOP;
            case "android", "ios", "harmonyos", "harmony", "ohos", "iphone" -> APP;
            default -> APP;
        };
    }
}
