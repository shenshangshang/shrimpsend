package dev.ultrasend.backend.license;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
@Entity @Table(name="device_license_migration")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DeviceLicenseMigration {
    @Id private Integer id;
    @Column(nullable=false) private boolean completed;
}
