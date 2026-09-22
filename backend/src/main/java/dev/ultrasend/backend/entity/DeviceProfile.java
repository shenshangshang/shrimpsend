package dev.ultrasend.backend.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;

/** Public device identity, independent of billing accounts and grants. */
@Entity @Table(name = "device_profiles", indexes = @Index(name = "idx_profile_presence", columnList = "online,last_seen"))
@Getter @Setter @NoArgsConstructor
public class DeviceProfile {
    @Id @Column(length = 255) private String deviceId;
    @Column(length = 128) private String name;
    @Column(length = 32) private String platform;
    @Column(length = 512) private String lanHttpUrl;
    private boolean online;
    private Instant lastSeen;
    private Instant updatedAt;
}
