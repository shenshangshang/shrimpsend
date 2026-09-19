package dev.ultrasend.backend.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(name = "device_credentials")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeviceCredential {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "device_id", nullable = false, unique = true, length = 255)
    private String deviceId;

    @Column(name = "secret_hash", nullable = false, length = 128)
    private String secretHash;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "last_issued_at")
    private Instant lastIssuedAt;
}
