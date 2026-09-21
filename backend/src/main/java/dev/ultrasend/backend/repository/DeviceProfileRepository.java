package dev.ultrasend.backend.repository;

import dev.ultrasend.backend.entity.DeviceProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.Instant;
import java.util.List;

public interface DeviceProfileRepository extends JpaRepository<DeviceProfile, String> {
    List<DeviceProfile> findByOnlineTrueAndLastSeenBefore(Instant cutoff);
}
