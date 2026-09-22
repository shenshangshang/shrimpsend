package dev.ultrasend.backend.license;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
@Entity @Table(name="device_license_codes", indexes={@Index(name="idx_license_code_owner",columnList="owner_user_id,status"),@Index(name="idx_license_code_device",columnList="device_id,status")})
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DeviceLicenseCode {
    @Id @Column(length=36) private String id;
    @Column(nullable=false) private Long ownerUserId;
    @Column(length=64, nullable=false, unique=true) private String codeHash;
    @Column(length=64, nullable=false, unique=true) private String qrHash;
    @Column(length=16, nullable=false) private String status;
    @Column(nullable=false) private Instant createdAt;
    @Column(nullable=false) private Instant expiresAt;
    @Column(length=255) private String deviceId;
    @Column(length=128) private String deviceName;
    @Column(length=32) private String platform;
    private Instant redeemedAt;
}
