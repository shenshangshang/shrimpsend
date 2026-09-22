package dev.ultrasend.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.ultrasend.backend.dto.MailboxPendingItemDto;
import dev.ultrasend.backend.entity.MailboxItem;
import dev.ultrasend.backend.realtime.RealtimeEnvelopeTypes;
import dev.ultrasend.backend.repository.MailboxItemRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Slf4j
public class MailboxService {

    private final MailboxItemRepository mailboxItemRepository;
    private final ObjectMapper objectMapper;

    @Value("${centrifugo.mailbox-ttl-sec:120}")
    private long mailboxTtlSec;

    @Transactional
    public void storeIfEphemeral(Long userId, Object data) {
        if (!(data instanceof Map<?, ?> map)) {
            return;
        }
        Object typeObj = map.get("type");
        String type = typeObj != null ? typeObj.toString() : null;
        if (!RealtimeEnvelopeTypes.isEphemeral(type) && !"text".equals(type) && !"file".equals(type) && !"control".equals(type)) {
            return;
        }
        String fromDeviceId = stringOrNull(map.get("fromDeviceId"));
        String toDeviceId = stringOrNull(map.get("toDeviceId"));
        // Only directed guest text belongs in the transient mailbox.
        if (!RealtimeEnvelopeTypes.isEphemeral(type) && (toDeviceId == null || toDeviceId.isBlank())) return;
        Instant now = Instant.now();
        String json;
        try {
            json = objectMapper.writeValueAsString(data);
        } catch (Exception e) {
            log.warn("mailbox serialize failed userId={} type={}: {}", userId, type, e.getMessage());
            return;
        }
        MailboxItem item = MailboxItem.builder()
                .userId(userId)
                .fromDeviceId(fromDeviceId)
                .toDeviceId(blankToNull(toDeviceId))
                .type(type)
                .data(json)
                .createdAt(now)
                .expiresAt(now.plusSeconds(Math.max(15, mailboxTtlSec)))
                .build();
        mailboxItemRepository.save(item);
        log.debug("mailbox stored userId={} type={} to={}", userId, type, toDeviceId);
    }

    @Transactional(readOnly = true)
    public List<MailboxPendingItemDto> pending(long userId, String deviceId, Long afterId) {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId required");
        }
        long after = afterId == null || afterId < 0 ? 0L : afterId;
        List<MailboxItem> rows = mailboxItemRepository.findPending(
                userId,
                deviceId,
                after,
                Instant.now(),
                PageRequest.of(0, 100));
        if (rows == null) {
            rows = List.of();
        }
        List<MailboxItem> deviceRows = mailboxItemRepository.findPendingForDevice(
                deviceId, after, Instant.now(), PageRequest.of(0, 100));
        if (deviceRows == null) {
            deviceRows = List.of();
        }
        java.util.LinkedHashMap<Long, MailboxItem> merged = new java.util.LinkedHashMap<>();
        for (MailboxItem row : rows) {
            merged.put(row.getId(), row);
        }
        for (MailboxItem row : deviceRows) {
            merged.putIfAbsent(row.getId(), row);
        }
        List<MailboxPendingItemDto> out = new ArrayList<>(merged.size());
        // One cursor covers both queries: return the earliest combined page,
        // otherwise a high ID in one source skips unread rows in the other.
        var page = merged.values().stream()
                .sorted(java.util.Comparator.comparing(MailboxItem::getId))
                .limit(100).toList();
        for (MailboxItem row : page) {
            Object parsed;
            try {
                parsed = objectMapper.readValue(row.getData(), Object.class);
            } catch (Exception e) {
                log.warn("mailbox parse failed id={}: {}", row.getId(), e.getMessage());
                continue;
            }
            out.add(MailboxPendingItemDto.builder().id(row.getId()).data(parsed).build());
        }
        return out;
    }

    @Transactional(readOnly = true)
    public List<MailboxPendingItemDto> pendingForDevice(String deviceId, Long afterId) {
        if (deviceId == null || deviceId.isBlank()) {
            throw new IllegalArgumentException("deviceId required");
        }
        long after = afterId == null || afterId < 0 ? 0L : afterId;
        List<MailboxItem> rows = mailboxItemRepository.findPendingForDevice(
                deviceId, after, Instant.now(), PageRequest.of(0, 100));
        if (rows == null) {
            rows = List.of();
        }
        List<MailboxPendingItemDto> out = new ArrayList<>(rows.size());
        for (MailboxItem row : rows) {
            Object parsed;
            try {
                parsed = objectMapper.readValue(row.getData(), Object.class);
            } catch (Exception e) {
                log.warn("mailbox parse failed id={}: {}", row.getId(), e.getMessage());
                continue;
            }
            out.add(MailboxPendingItemDto.builder().id(row.getId()).data(parsed).build());
        }
        return out;
    }

    @Scheduled(fixedDelayString = "${centrifugo.mailbox-sweep-ms:60000}")
    @Transactional
    public void sweepExpired() {
        mailboxItemRepository.deleteByExpiresAtBefore(Instant.now());
    }

    private static String stringOrNull(Object value) {
        return value == null ? null : value.toString();
    }

    private static String blankToNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value;
    }
}
