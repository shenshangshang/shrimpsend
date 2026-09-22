package dev.ultrasend.backend.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.Base64;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WukongimPayloadsTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void wrapAndUnwrapEnvelope() throws Exception {
        Map<String, Object> envelope = Map.of("type", "text", "fromDeviceId", "phone");
        String b64 = WukongimPayloads.encodeBase64(objectMapper, envelope);
        Map<String, Object> decoded = objectMapper.readValue(Base64.getDecoder().decode(b64), Map.class);
        assertEquals(200, ((Number) decoded.get("type")).intValue());
        assertEquals(envelope, WukongimPayloads.unwrap(decoded));
        assertEquals("text", WukongimPayloads.unwrap(b64).get("type"));
    }

    @Test
    void unwrapLegacyStringTypedEnvelope() {
        Map<String, Object> raw = Map.of("type", "webrtc_offer", "fromDeviceId", "a");
        assertEquals("webrtc_offer", WukongimPayloads.unwrap(raw).get("type"));
        assertTrue(WukongimPayloads.unwrap("not-json").isEmpty());
    }
}
