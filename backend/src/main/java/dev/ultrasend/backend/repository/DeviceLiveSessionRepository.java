package dev.ultrasend.backend.repository;

import dev.ultrasend.backend.entity.DeviceLiveSession;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.Instant;
import java.util.Optional;

public interface DeviceLiveSessionRepository extends JpaRepository<DeviceLiveSession, Long> {
    Optional<DeviceLiveSession> findByDeviceIdAndSessionId(String deviceId, String sessionId);
    boolean existsByDeviceIdAndExpiresAtAfter(String deviceId, Instant now);
    void deleteByExpiresAtBefore(Instant cutoff);
}
