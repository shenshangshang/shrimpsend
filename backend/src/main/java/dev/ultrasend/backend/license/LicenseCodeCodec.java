package dev.ultrasend.backend.license;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Locale;

@Component
public class LicenseCodeCodec {
    static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private final SecureRandom random = new SecureRandom();
    private final String secret;
    private final String namespace;
    public LicenseCodeCodec(@Value("${app.device-license.secret:${app.jwt.access-secret}}") String secret,
                            @Value("${app.device-license.namespace:C}") String namespace) {
        this.secret = secret;
        this.namespace = namespace.trim().toUpperCase(Locale.ROOT);
        if (secret.length() < 32 || this.namespace.length() != 1 || !ALPHABET.contains(this.namespace)) {
            throw new IllegalArgumentException("Device license secret or namespace is invalid");
        }
    }
    public String newCode() {
        StringBuilder value = new StringBuilder(namespace);
        for (int i = 1; i < 6; i++) value.append(ALPHABET.charAt(random.nextInt(ALPHABET.length())));
        return value.toString();
    }
    public String newQrToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
    public String normalize(String code) {
        String value = code == null ? "" : code.replaceAll("[\\s-]", "").toUpperCase(Locale.ROOT);
        if (value.length() != 6 || value.chars().anyMatch(c -> ALPHABET.indexOf(c) < 0)) return "";
        return value;
    }
    public String hash(String purpose, String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal((purpose + ":" + value).getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) { throw new IllegalStateException(error); }
    }
}
