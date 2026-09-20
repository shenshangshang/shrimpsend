package dev.ultrasend.backend.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.ultrasend.backend.dto.SendMessageRequest;
import dev.ultrasend.backend.service.DeviceSendRateLimit;
import dev.ultrasend.backend.service.InMemoryRateLimiter;
import dev.ultrasend.backend.service.MessageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/messages")
@RequiredArgsConstructor
@Slf4j
public class MessageController {

    public static final String QUOTA_HEADER = "X-Device-Send-Quota";

    private final MessageService messageService;
    private final InMemoryRateLimiter rateLimiter;
    private final ObjectMapper objectMapper;

    @PostMapping("/send")
    public ResponseEntity<Void> send(Authentication auth, @RequestBody SendMessageRequest req) {
        if (auth == null || !auth.isAuthenticated() || AuthRoles.isDevice(auth)) {
            log.warn("messages/send unauthenticated 401");
            return ResponseEntity.status(401).build();
        }
        String userId = (String) auth.getPrincipal();
        Object data = req.getData();
        log.info("messages/send userId={}", userId);
        messageService.send(userId, data);
        log.debug("messages/send ok userId={}", userId);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/device-send")
    public ResponseEntity<?> deviceSend(Authentication auth, @RequestBody SendMessageRequest req) {
        if (auth == null || !auth.isAuthenticated() || !AuthRoles.isDevice(auth)) {
            return ResponseEntity.status(401).build();
        }
        String deviceId = AuthRoles.deviceId(auth);
        Object data = req.getData();
        String type = DeviceSendRateLimit.envelopeType(data);
        String kind = DeviceSendRateLimit.kindForType(type);
        String bucket = DeviceSendRateLimit.bucketKey(deviceId, type);
        int max = DeviceSendRateLimit.maxPerWindow(type);
        InMemoryRateLimiter.Snapshot hit = rateLimiter.tryAcquireWithSnapshot(
                bucket, max, DeviceSendRateLimit.WINDOW_MS);
        HttpHeaders headers = quotaHeaders(deviceId, kind);
        if (!hit.acquired()) {
            log.warn("messages/device-send 429 deviceId={} type={} bucket={}", deviceId, type, bucket);
            Map<String, Object> body = new LinkedHashMap<>(DeviceSendRateLimit.quotaView(rateLimiter, deviceId));
            body.put("error", "rate_limited");
            body.put("kind", kind);
            return ResponseEntity.status(429).headers(headers).body(body);
        }
        log.info("messages/device-send deviceId={} type={}", deviceId, type);
        messageService.sendFromDevice(deviceId, data);
        return ResponseEntity.noContent().headers(headers).build();
    }

    @GetMapping("/device-quota")
    public ResponseEntity<Map<String, Object>> deviceQuota(Authentication auth) {
        if (auth == null || !auth.isAuthenticated() || !AuthRoles.isDevice(auth)) {
            return ResponseEntity.status(401).build();
        }
        String deviceId = AuthRoles.deviceId(auth);
        Map<String, Object> body = DeviceSendRateLimit.quotaView(rateLimiter, deviceId);
        return ResponseEntity.ok().headers(quotaHeaders(deviceId, null)).body(body);
    }

    @DeleteMapping("/thread")
    public ResponseEntity<Void> deleteThread(
            Authentication auth,
            @RequestParam String threadKey) {
        if (auth == null || !auth.isAuthenticated()) {
            return ResponseEntity.status(401).build();
        }
        if (threadKey == null || threadKey.isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        Long userId = Long.parseLong((String) auth.getPrincipal());
        messageService.deleteMessagesByThreadKey(userId, threadKey);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(Authentication auth, @PathVariable Long id) {
        if (auth == null || !auth.isAuthenticated()) {
            return ResponseEntity.status(401).build();
        }
        Long userId = Long.parseLong((String) auth.getPrincipal());
        messageService.deleteMessage(userId, id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/history")
    public ResponseEntity<List<Map<String, Object>>> history(
            Authentication auth,
            @RequestParam(defaultValue = "50") int limit,
            @RequestParam(required = false) Long before,
            @RequestParam(required = false) String threadKey) {
        if (auth == null || !auth.isAuthenticated()) {
            return ResponseEntity.status(401).build();
        }
        Long userId = Long.parseLong((String) auth.getPrincipal());
        int safeLimit = Math.min(Math.max(1, limit), 100);
        List<Map<String, Object>> list = messageService.getHistory(userId, safeLimit, before, threadKey);
        return ResponseEntity.ok(list);
    }

    @GetMapping("/search")
    public ResponseEntity<List<Map<String, Object>>> search(
            Authentication auth,
            @RequestParam String q,
            @RequestParam(defaultValue = "50") int limit,
            @RequestParam(required = false) Long before,
            @RequestParam(required = false) String threadKey) {
        if (auth == null || !auth.isAuthenticated()) {
            return ResponseEntity.status(401).build();
        }
        log.info("messages/search disabled; cloud content search is no longer supported");
        return ResponseEntity.status(410).body(List.of());
    }

    private HttpHeaders quotaHeaders(String deviceId, String kind) {
        Map<String, Object> payload = new LinkedHashMap<>(DeviceSendRateLimit.quotaView(rateLimiter, deviceId));
        if (kind != null && !kind.isBlank()) {
            payload.put("kind", kind);
        }
        HttpHeaders headers = new HttpHeaders();
        try {
            headers.add(QUOTA_HEADER, objectMapper.writeValueAsString(payload));
        } catch (JsonProcessingException e) {
            log.warn("device-send quota header encode failed: {}", e.getMessage());
        }
        return headers;
    }
}
