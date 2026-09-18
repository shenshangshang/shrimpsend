package dev.ultrasend.backend.realtime;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class WukongimDeviceFlagsTest {

    @Test
    void mapsPlatforms() {
        assertEquals(0, WukongimDeviceFlags.fromPlatform("android"));
        assertEquals(0, WukongimDeviceFlags.fromPlatform("ios"));
        assertEquals(0, WukongimDeviceFlags.fromPlatform("harmonyos"));
        assertEquals(1, WukongimDeviceFlags.fromPlatform("web"));
        assertEquals(2, WukongimDeviceFlags.fromPlatform("macos"));
        assertEquals(2, WukongimDeviceFlags.fromPlatform("Windows"));
        assertEquals(2, WukongimDeviceFlags.fromPlatform("linux"));
        assertEquals(0, WukongimDeviceFlags.fromPlatform(null));
        assertEquals(0, WukongimDeviceFlags.SECONDARY);
    }
}
