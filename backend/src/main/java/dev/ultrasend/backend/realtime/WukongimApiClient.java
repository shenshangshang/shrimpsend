package dev.ultrasend.backend.realtime;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.util.List;
import java.util.UUID;

@Component
@Slf4j
public class WukongimApiClient {

    private final WebClient webClient;
    private final ObjectMapper objectMapper;
    private final long timeoutMs;

    public WukongimApiClient(
            @Qualifier("wukongimWebClient") WebClient wukongimWebClient,
            ObjectMapper objectMapper,
            @Value("${wukongim.publish-timeout-ms:2000}") long timeoutMs) {
        this.webClient = wukongimWebClient;
        this.objectMapper = objectMapper;
        this.timeoutMs = timeoutMs;
    }

    public void updateUserToken(
            String uid,
            String token,
            int deviceFlag,
            int deviceLevel,
            String deviceId) {
        ObjectNode body = objectMapper.createObjectNode()
                .put("uid", uid)
                .put("token", token)
                .put("device_flag", deviceFlag)
                .put("device_level", deviceLevel);
        if (deviceId != null && !deviceId.isBlank()) {
            body.put("device_id", deviceId.trim());
        }
        post("/user/token", body);
    }

    public void addSystemUids(List<String> uids) {
        ObjectNode body = objectMapper.createObjectNode();
        ArrayNode arr = body.putArray("uids");
        uids.forEach(arr::add);
        post("/user/systemuids_add", body);
    }

    public void sendMessage(
            String fromUid,
            String channelId,
            int channelType,
            String payloadBase64,
            int expireSec,
            String clientMsgNo) {
        ObjectNode header = objectMapper.createObjectNode()
                .put("no_persist", 0)
                .put("red_dot", 0)
                .put("sync_once", 0);
        ObjectNode body = objectMapper.createObjectNode();
        body.set("header", header);
        body.put("from_uid", fromUid);
        body.put("channel_id", channelId);
        body.put("channel_type", channelType);
        body.put("expire", Math.max(0, expireSec));
        body.put("client_msg_no", clientMsgNo != null ? clientMsgNo : "shrimp-" + UUID.randomUUID());
        body.put("payload", payloadBase64);
        post("/message/send", body);
    }

    private void post(String path, ObjectNode body) {
        Duration timeout = Duration.ofMillis(Math.max(200, timeoutMs));
        try {
            String response = webClient.post()
                    .uri(path)
                    .contentType(MediaType.APPLICATION_JSON)
                    .bodyValue(body)
                    .retrieve()
                    .bodyToMono(String.class)
                    .timeout(timeout)
                    .block(timeout.plusMillis(200));
            log.debug("wukongim {} ok body={}", path, summarize(response));
        } catch (Exception e) {
            log.error("wukongim {} failed: {}", path, e.getMessage());
            throw new IllegalStateException("WuKongIM request failed: " + path, e);
        }
    }

    private String summarize(String response) {
        if (response == null || response.isBlank()) {
            return "";
        }
        try {
            JsonNode node = objectMapper.readTree(response);
            return node.has("status") ? node.get("status").asText() : "ok";
        } catch (Exception e) {
            return "ok";
        }
    }
}
