package dev.ultrasend.backend.realtime;

import dev.ultrasend.backend.dto.RealtimeTokenResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * WuKongIM stores one CONNECT token per (uid, device_flag). Same-flag
 * secondary devices must share that token; device_id still distinguishes
 * connections.
 */
@Service
@RequiredArgsConstructor
public class WukongimTokenService {

    private final WukongimApiClient wukongimApiClient;

    @Value("${wukongim.ws-public-url:ws://127.0.0.1:5200}")
    private String wsPublicUrl;

    @Value("${wukongim.manager-token:dev-wukongim-manager-token}")
    private String managerToken;

    public RealtimeTokenResponse createToken(String userId, String platform, String deviceId) {
        int deviceFlag = WukongimDeviceFlags.fromPlatform(platform);
        String token = stableToken(userId, deviceFlag);
        wukongimApiClient.updateUserToken(
                userId,
                token,
                deviceFlag,
                WukongimDeviceFlags.SECONDARY,
                deviceId);
        return RealtimeTokenResponse.builder()
                .uid(userId)
                .token(token)
                .websocketUrl(wsPublicUrl)
                .deviceFlag(deviceFlag)
                .deviceLevel(WukongimDeviceFlags.SECONDARY)
                .channelId(userId)
                .channelType(WukongimPublishService.CHANNEL_PERSON)
                .build();
    }

    String stableToken(String userId, int deviceFlag) {
        String secret = (managerToken == null || managerToken.isBlank())
                ? "dev-wukongim-manager-token"
                : managerToken.trim();
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] digest = mac.doFinal((userId + ":" + deviceFlag).getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to derive WuKongIM token", e);
        }
    }
}
