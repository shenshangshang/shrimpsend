package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.service.DeviceService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * WuKongIM webhook. Presence stays REST-authoritative; online events only
 * touch a device when the payload includes deviceId.
 */
@RestController
@RequestMapping("/api/wukongim")
@RequiredArgsConstructor
@Slf4j
public class WukongimWebhookController {

    private final DeviceService deviceService;

    @Value("${wukongim.webhook-secret:}")
    private String webhookSecret;

    @PostMapping("/webhook")
    public ResponseEntity<String> webhook(
            @RequestParam(required = false) String event,
            @RequestHeader(value = "X-Webhook-Secret", required = false) String secret,
            @RequestBody(required = false) Object body) {
        if (webhookSecret != null && !webhookSecret.isBlank()
                && (secret == null || !webhookSecret.equals(secret))) {
            return ResponseEntity.status(401).body("unauthorized");
        }
        if ("user.onlinestatus".equals(event)) {
            applyOnlineStatus(body);
        }
        return ResponseEntity.ok("OK");
    }

    private void applyOnlineStatus(Object body) {
        if (!(body instanceof List<?> rows)) {
            return;
        }
        for (Object row : rows) {
            if (!(row instanceof Map<?, ?> map)) {
                continue;
            }
            Object deviceIdRaw = first(map, "deviceId", "device_id", "deviceID");
            if (deviceIdRaw == null || deviceIdRaw.toString().isBlank()) {
                continue;
            }
            Object uidRaw = first(map, "uid", "userId", "user_id");
            if (uidRaw == null) {
                continue;
            }
            try {
                Long userId = Long.valueOf(uidRaw.toString());
                deviceService.touchOnline(userId, deviceIdRaw.toString().trim(), null, null);
            } catch (Exception e) {
                log.debug("wukongim online ignored uid={} err={}", uidRaw, e.getMessage());
            }
        }
    }

    private static Object first(Map<?, ?> map, String... keys) {
        for (String key : keys) {
            if (map.containsKey(key) && map.get(key) != null) {
                return map.get(key);
            }
        }
        return null;
    }
}
