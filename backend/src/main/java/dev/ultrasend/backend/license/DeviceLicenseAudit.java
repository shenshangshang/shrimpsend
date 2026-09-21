package dev.ultrasend.backend.license;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
/** No activation secrets, payment details or file content in the audit trail. */
@Entity @Table(name="device_license_audit", indexes=@Index(name="idx_license_audit_owner_time",columnList="owner_user_id,created_at"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DeviceLicenseAudit {
    @Id @Column(length=36) private String id;
    @Column(nullable=false) private Long ownerUserId;
    @Column(length=32,nullable=false) private String action;
    private String deviceId;
    @Column(length=36) private String requestId;
    @Column(nullable=false) private Instant createdAt;
}
