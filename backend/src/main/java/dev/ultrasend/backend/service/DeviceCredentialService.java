package dev.ultrasend.backend.service;

import dev.ultrasend.backend.entity.DeviceCredential;
import dev.ultrasend.backend.repository.DeviceCredentialRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;

@Service
@RequiredArgsConstructor
public class DeviceCredentialService {

    private final DeviceCredentialRepository deviceCredentialRepository;

    @Value("${wukongim.manager-token:dev-wukongim-manager-token}")
    private String pepper;

    @Transactional
    public void registerOrVerify(String deviceId, String deviceSecret) {
        if (deviceId == null || deviceId.isBlank() || deviceSecret == null || deviceSecret.length() < 16) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "invalid device credential");
        }
        String hash = hashSecret(deviceId, deviceSecret);
        DeviceCredential existing = deviceCredentialRepository.findByDeviceId(deviceId.trim()).orElse(null);
        Instant now = Instant.now();
        if (existing == null) {
            deviceCredentialRepository.save(DeviceCredential.builder()
                    .deviceId(deviceId.trim())
                    .secretHash(hash)
                    .createdAt(now)
                    .lastIssuedAt(now)
                    .build());
            return;
        }
        if (!MessageDigest.isEqual(
                existing.getSecretHash().getBytes(StandardCharsets.UTF_8),
                hash.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "device secret mismatch");
        }
        existing.setLastIssuedAt(now);
        deviceCredentialRepository.save(existing);
    }

    String hashSecret(String deviceId, String deviceSecret) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            String key = (pepper == null || pepper.isBlank()) ? "dev-wukongim-manager-token" : pepper.trim();
            mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] digest = mac.doFinal((deviceId + ":" + deviceSecret).getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to hash device secret", e);
        }
    }
}
