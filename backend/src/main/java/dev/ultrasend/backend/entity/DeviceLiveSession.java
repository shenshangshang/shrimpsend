package dev.ultrasend.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;

@Entity @Table(name = "device_live_sessions",
    uniqueConstraints = @UniqueConstraint(columnNames = {"device_id", "session_id"}),
    indexes = @Index(name = "idx_live_device", columnList = "device_id,expires_at"))
@Getter @Setter @NoArgsConstructor
public class DeviceLiveSession {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) private Long id;
    @Column(name = "device_id", nullable = false, length = 255) private String deviceId;
    @Column(name = "session_id", nullable = false, length = 128) private String sessionId;
    private long sequence;
    private Instant expiresAt;
}
