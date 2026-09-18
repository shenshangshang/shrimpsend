package dev.ultrasend.backend.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

public final class WukongimPayloads {

    public static final int TYPE_ENVELOPE = 200;

    private WukongimPayloads() {}

    public static Map<String, Object> wrap(Object envelope) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", TYPE_ENVELOPE);
        payload.put("v", 1);
        payload.put("envelope", envelope);
        return payload;
    }

    public static String encodeBase64(ObjectMapper objectMapper, Object envelope) {
        try {
            byte[] json = objectMapper.writeValueAsBytes(wrap(envelope));
            return Base64.getEncoder().encodeToString(json);
        } catch (Exception e) {
            throw new IllegalArgumentException("Failed to encode WuKongIM payload", e);
        }
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> unwrap(Object payload) {
        if (payload instanceof Map<?, ?> map) {
            Object type = map.get("type");
            if (type instanceof Number n && n.intValue() == TYPE_ENVELOPE && map.get("envelope") instanceof Map<?, ?> env) {
                return (Map<String, Object>) env;
            }
            if (type instanceof String) {
                return (Map<String, Object>) map;
            }
        }
        if (payload instanceof String s && !s.isBlank()) {
            try {
                byte[] raw = looksLikeJson(s)
                        ? s.getBytes(StandardCharsets.UTF_8)
                        : Base64.getDecoder().decode(s);
                Object decoded = new ObjectMapper().readValue(raw, Object.class);
                return unwrap(decoded);
            } catch (Exception ignored) {
                return Map.of();
            }
        }
        return Map.of();
    }

    private static boolean looksLikeJson(String s) {
        char c = s.charAt(0);
        return c == '{' || c == '[';
    }
}
