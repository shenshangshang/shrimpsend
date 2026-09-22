package dev.ultrasend.backend.service;

import dev.ultrasend.backend.realtime.RealtimeEnvelopeTypes;

/**
 * Guest {@code /api/messages/device-send} quotas. WebRTC trickle ICE
 * publishes one envelope per candidate; a shared 60/min bucket is exhausted
 * after one or two transfers and then blocks text as well.
 */
public final class DeviceSendRateLimit {

    public static final int MESSAGE_MAX_PER_WINDOW = 90;
    public static final int SIGNALING_MAX_PER_WINDOW = 600;
    public static final long WINDOW_MS = 60_000L;

    private DeviceSendRateLimit() {}

    public static String envelopeType(Object data) {
        if (data instanceof java.util.Map<?, ?> map) {
            Object type = map.get("type");
            return type != null ? type.toString() : null;
        }
        return null;
    }

    public static boolean isSignaling(String type) {
        return RealtimeEnvelopeTypes.isEphemeral(type);
    }

    public static String bucketKey(String deviceId, String type) {
        String prefix = isSignaling(type) ? "device-send-sig:" : "device-send-msg:";
        return prefix + (deviceId == null || deviceId.isBlank() ? "unknown" : deviceId);
    }

    public static int maxPerWindow(String type) {
        return isSignaling(type) ? SIGNALING_MAX_PER_WINDOW : MESSAGE_MAX_PER_WINDOW;
    }

    public static String kindForType(String type) {
        return isSignaling(type) ? "signaling" : "message";
    }

    public static java.util.Map<String, Object> quotaView(
            InMemoryRateLimiter limiter, String deviceId) {
        InMemoryRateLimiter.Snapshot message = limiter.snapshot(
                bucketKey(deviceId, "text"), MESSAGE_MAX_PER_WINDOW, WINDOW_MS);
        InMemoryRateLimiter.Snapshot signaling = limiter.snapshot(
                bucketKey(deviceId, "webrtc_ice_candidate"),
                SIGNALING_MAX_PER_WINDOW,
                WINDOW_MS);
        java.util.Map<String, Object> body = new java.util.LinkedHashMap<>();
        body.put("message", message.toMap());
        body.put("signaling", signaling.toMap());
        return body;
    }
}
