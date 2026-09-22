package dev.ultrasend.backend.license;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
@Entity @Table(name="device_license_grants", indexes=@Index(name="idx_license_grant_owner",columnList="owner_user_id,revoked_at,activated_at"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DeviceLicenseGrant {
    @Id @Column(length=255) private String deviceId;
    @Column(nullable=false) private Long ownerUserId;
    @Column(length=128, nullable=false) private String name;
    @Column(length=32, nullable=false) private String platform;
    @Column(nullable=false) private Instant activatedAt;
    private Instant revokedAt;
    @Column(nullable=false) private boolean legacy;
}
