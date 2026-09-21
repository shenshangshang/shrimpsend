package dev.ultrasend.backend.license;
import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
@Entity @Table(name="license_rate_buckets", indexes=@Index(name="idx_license_rate_window",columnList="window_started_at"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class LicenseRateBucket {
    @Id @Column(length=255) private String id;
    @Column(nullable=false) private long windowStartedAt;
    @Column(nullable=false) private int hits;
}
