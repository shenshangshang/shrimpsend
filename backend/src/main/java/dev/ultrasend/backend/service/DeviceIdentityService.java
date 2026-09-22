package dev.ultrasend.backend.service;

import dev.ultrasend.backend.dto.*;
import dev.ultrasend.backend.entity.*;
import dev.ultrasend.backend.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.time.Instant;
import java.util.Objects;

@Service @RequiredArgsConstructor
public class DeviceIdentityService {
    private final DeviceCredentialRepository credentials;
    private final DeviceProfileRepository profiles;
    private final DeviceLiveSessionRepository sessions;
    private final DeviceRepository legacyDevices;
    private final DeviceRosterPublisher publisher;
    private final jakarta.persistence.EntityManager entityManager;

    @Value("${app.device-identity.lease-seconds:45}") private long leaseSeconds = 45;

    /** Lock the durable credential to serialize concurrent tabs, first registration and expiry. */
    private void lock(String id) {
        credentials.lockByDeviceId(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED));
    }

    private DeviceProfile profile(String id) {
        return profiles.findById(id).orElseGet(() -> {
            DeviceProfile p = new DeviceProfile();
            p.setDeviceId(id);
            legacyDevices.findByDeviceId(id).ifPresent(d -> {
                p.setName(d.getName()); p.setPlatform(d.getPlatform()); p.setLanHttpUrl(d.getLanHttpUrl());
            });
            return p;
        });
    }

    @Transactional
    public DeviceDto heartbeat(String id, DeviceHeartbeatRequest request) {
        lock(id);
        DeviceProfile p = profile(id);
        DeviceLiveSession session = sessions.findByDeviceIdAndSessionId(id, request.getSessionId()).orElseGet(() -> {
            DeviceLiveSession s = new DeviceLiveSession(); s.setDeviceId(id); s.setSessionId(request.getSessionId()); return s;
        });
        // A delayed online request must not resurrect a session closed by pagehide.
        if (request.getSequence() <= session.getSequence()) return toDto(p);
        Instant now = Instant.now();
        session.setSequence(request.getSequence());
        boolean online = "online".equals(request.getStatus());
        session.setExpiresAt(online ? now.plusSeconds(leaseSeconds) : now);
        sessions.saveAndFlush(session);
        boolean changed = online && (!p.isOnline() || p.getLastSeen() == null || !p.getLastSeen().isAfter(now.minusSeconds(leaseSeconds)));
        if (online) {
            // Heartbeats cannot undo an explicit rename from another tab.
            if (p.getName() == null && request.getName() != null) { p.setName(cleanName(request.getName())); changed = true; }
            if (!Objects.equals(p.getPlatform(), request.getPlatform())) { p.setPlatform(request.getPlatform()); changed = true; }
            if (!Objects.equals(p.getLanHttpUrl(), request.getLanHttpUrl())) { p.setLanHttpUrl(request.getLanHttpUrl()); changed = true; }
            p.setLastSeen(now);
        }
        boolean live = sessions.existsByDeviceIdAndExpiresAtAfter(id, now);
        changed |= p.isOnline() != live;
        p.setOnline(live);
        if (changed || p.getUpdatedAt() == null) p.setUpdatedAt(nextRevision(p, now));
        profiles.save(p);
        if (changed) publisher.publishPeerUpsertAfterCommit(toDto(p));
        return toDto(p);
    }

    @Transactional
    public DeviceDto rename(String id, String name) {
        String clean = cleanName(name);
        lock(id);
        DeviceProfile p = profile(id);
        if (!Objects.equals(p.getName(), clean)) {
            p.setName(clean); p.setUpdatedAt(nextRevision(p, Instant.now())); profiles.save(p);
            publisher.publishPeerUpsertAfterCommit(toDto(p));
        }
        return toDto(p);
    }

    public static String cleanName(String name) {
        String value = name == null ? "" : name.strip();
        if (value.isEmpty() || value.length() > 80 || value.codePoints().anyMatch(Character::isISOControl))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Device name must contain 1–80 characters without control characters");
        return value;
    }

    private Instant nextRevision(DeviceProfile p, Instant now) {
        return Instant.ofEpochMilli(Math.max(now.toEpochMilli(), p.getUpdatedAt() == null ? 0 : p.getUpdatedAt().toEpochMilli() + 1));
    }

    @Transactional(readOnly = true)
    public DeviceDto describe(String id) {
        return toDto(profile(id));
    }

    public DeviceDto toDto(DeviceProfile p) {
        boolean live = p.isOnline() && p.getLastSeen() != null && p.getLastSeen().isAfter(Instant.now().minusSeconds(leaseSeconds));
        return DeviceDto.builder().deviceId(p.getDeviceId()).name(p.getName() == null ? p.getDeviceId() : p.getName())
            .platform(p.getPlatform()).lanHttpUrl(p.getLanHttpUrl()).presenceStatus(live ? "online" : "offline")
            .lastSeen(p.getLastSeen() == null ? null : p.getLastSeen().toEpochMilli())
            .presenceUpdatedAt(p.getUpdatedAt() == null ? null : p.getUpdatedAt().toEpochMilli()).build();
    }

    @Transactional
    @Scheduled(fixedDelayString = "${app.device-identity.sweep-ms:5000}")
    public void expire() {
        Instant now = Instant.now();
        for (DeviceProfile candidate : profiles.findByOnlineTrueAndLastSeenBefore(now.minusSeconds(leaseSeconds))) {
            lock(candidate.getDeviceId());
            entityManager.refresh(candidate, jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
            if (!candidate.isOnline() || !candidate.getLastSeen().isBefore(now.minusSeconds(leaseSeconds))) continue;
            // Check leases again after obtaining the lock; a heartbeat may have won the race.
            if (sessions.existsByDeviceIdAndExpiresAtAfter(candidate.getDeviceId(), now)) continue;
            candidate.setOnline(false); candidate.setUpdatedAt(nextRevision(candidate, now)); profiles.save(candidate);
            publisher.publishPeerUpsertAfterCommit(toDto(candidate));
        }
    }

    @Transactional @Scheduled(fixedDelay = 3600000)
    public void cleanOldSessions() { sessions.deleteByExpiresAtBefore(Instant.now().minusSeconds(86400)); }
}
