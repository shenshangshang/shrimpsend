package dev.ultrasend.backend.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class DeviceSendRateLimitTest {

    @Test
    void iceCandidatesUseSignalingBucket() {
        assertTrue(DeviceSendRateLimit.isSignaling("webrtc_ice_candidate"));
        assertTrue(DeviceSendRateLimit.isSignaling("webrtc_offer"));
        assertEquals("device-send-sig:dev-a", DeviceSendRateLimit.bucketKey("dev-a", "webrtc_ice_candidate"));
        assertEquals(600, DeviceSendRateLimit.maxPerWindow("webrtc_ice_candidate"));
    }

    @Test
    void textUsesMessageBucket() {
        assertFalse(DeviceSendRateLimit.isSignaling("text"));
        assertEquals("device-send-msg:dev-a", DeviceSendRateLimit.bucketKey("dev-a", "text"));
        assertEquals(90, DeviceSendRateLimit.maxPerWindow("text"));
    }

    @Test
    void envelopeTypeReadsMap() {
        assertEquals("webrtc_offer", DeviceSendRateLimit.envelopeType(
                java.util.Map.of("type", "webrtc_offer", "toDeviceId", "peer")));
        assertNull(DeviceSendRateLimit.envelopeType("not-a-map"));
        assertNull(DeviceSendRateLimit.envelopeType(null));
    }

    @Test
    void quotaViewReportsBothBuckets() {
        InMemoryRateLimiter limiter = new InMemoryRateLimiter();
        limiter.tryAcquire(DeviceSendRateLimit.bucketKey("dev-a", "text"), 90, 60_000L);
        limiter.tryAcquire(DeviceSendRateLimit.bucketKey("dev-a", "webrtc_ice_candidate"), 600, 60_000L);
        java.util.Map<String, Object> view = DeviceSendRateLimit.quotaView(limiter, "dev-a");
        @SuppressWarnings("unchecked")
        java.util.Map<String, Object> message = (java.util.Map<String, Object>) view.get("message");
        @SuppressWarnings("unchecked")
        java.util.Map<String, Object> signaling = (java.util.Map<String, Object>) view.get("signaling");
        assertEquals(1, message.get("used"));
        assertEquals(90, message.get("limit"));
        assertEquals(89, message.get("remaining"));
        assertEquals(1, signaling.get("used"));
        assertEquals(600, signaling.get("limit"));
    }
}
