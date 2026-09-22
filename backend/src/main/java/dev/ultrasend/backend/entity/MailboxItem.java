package dev.ultrasend.backend.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;

@Entity
@Table(
        name = "signaling_mailbox",
        indexes = {
                @Index(name = "idx_mailbox_user_expires", columnList = "user_id, expires_at"),
                @Index(name = "idx_mailbox_user_id", columnList = "user_id, id")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MailboxItem {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id")
    private Long userId;

    @Column(name = "from_device_id", length = 255)
    private String fromDeviceId;

    @Column(name = "to_device_id", length = 255)
    private String toDeviceId;

    @Column(name = "type", nullable = false, length = 64)
    private String type;

    @Column(name = "data", nullable = false, columnDefinition = "MEDIUMTEXT")
    private String data;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;
}
