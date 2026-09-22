package dev.ultrasend.backend.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(
        name = "device_pairings",
        uniqueConstraints = @UniqueConstraint(columnNames = {"device_a", "device_b"}))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DevicePairing {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "device_a", nullable = false, length = 255)
    private String deviceA;

    @Column(name = "device_b", nullable = false, length = 255)
    private String deviceB;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
}
