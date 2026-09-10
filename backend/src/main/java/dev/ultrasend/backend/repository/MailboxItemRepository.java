package dev.ultrasend.backend.repository;

import dev.ultrasend.backend.entity.MailboxItem;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface MailboxItemRepository extends JpaRepository<MailboxItem, Long> {

    @Query("""
            SELECT m FROM MailboxItem m
            WHERE m.userId = :userId
              AND m.id > :afterId
              AND m.expiresAt > :now
              AND (m.fromDeviceId IS NULL OR m.fromDeviceId <> :deviceId)
              AND (m.toDeviceId IS NULL OR m.toDeviceId = :deviceId)
            ORDER BY m.id ASC
            """)
    List<MailboxItem> findPending(
            @Param("userId") Long userId,
            @Param("deviceId") String deviceId,
            @Param("afterId") Long afterId,
            @Param("now") Instant now,
            Pageable pageable);

    void deleteByExpiresAtBefore(Instant time);
}
