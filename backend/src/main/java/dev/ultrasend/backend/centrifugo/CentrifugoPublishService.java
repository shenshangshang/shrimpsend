package dev.ultrasend.backend.centrifugo;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;

import dev.ultrasend.backend.realtime.RealtimePublisher;

/**
 * Publishes messages to Centrifugo user channel via HTTP API.
 */
@Service
@ConditionalOnProperty(name = "realtime.bus", havingValue = "centrifugo")
@RequiredArgsConstructor
@Slf4j
public class CentrifugoPublishService implements RealtimePublisher {

    private static final String CHANNEL_PREFIX = "user#";

    @Qualifier("centrifugoWebClient")
    private final WebClient centrifugoWebClient;
    private final ObjectMapper objectMapper;

    @Value("${centrifugo.publish-timeout-ms:2000}")
    private long publishTimeoutMs;

    public void publishToUser(String userId, Object data) {
        String channel = CHANNEL_PREFIX + userId;
        ObjectNode body = objectMapper.createObjectNode()
                .put("method", "publish")
                .set("params", objectMapper.createObjectNode()
                        .put("channel", channel)
                        .set("data", objectMapper.valueToTree(data)));
        Duration timeout = Duration.ofMillis(Math.max(200, publishTimeoutMs));
        try {
            centrifugoWebClient.post()
                    .uri("/api")
                    .bodyValue(body)
                    .retrieve()
                    .bodyToMono(String.class)
                    .timeout(timeout)
                    .block(timeout.plusMillis(200));
            log.info("Centrifugo publish ok channel={}", channel);
        } catch (Exception e) {
            log.error("Centrifugo publish failed for channel {}: {}", channel, e.getMessage());
            throw new RuntimeException("Failed to publish message", e);
        }
    }

    /** Persist/mailbox already succeeded; a slow or down bus must not fail the send API. */
    public void publishToUserBestEffort(String userId, Object data) {
        try {
            publishToUser(userId, data);
        } catch (Exception e) {
            log.warn("Centrifugo publish best-effort failed userId={}: {}", userId, e.getMessage());
        }
    }
}
