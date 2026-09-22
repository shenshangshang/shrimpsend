package dev.ultrasend.backend.license;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
@Entity @Table(name="device_license_accounts")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DeviceLicenseAccount {
    @Id private Long userId;
    @Column(nullable=false) private int legacyExtraSlots;
    @Column(nullable=false) private Instant migratedAt;
}
