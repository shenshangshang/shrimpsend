package dev.ultrasend.backend.repository;

import dev.ultrasend.backend.entity.DevicePairing;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.Instant;

import java.util.Optional;

public interface DevicePairingRepository extends JpaRepository<DevicePairing, Long> {

    java.util.List<DevicePairing> findByDeviceAOrDeviceB(String deviceA, String deviceB);

    void deleteByDeviceAAndDeviceB(String deviceA,String deviceB);

    Optional<DevicePairing> findByDeviceAAndDeviceB(String deviceA, String deviceB);

    @Modifying
    @Query(value = "INSERT INTO device_pairings (device_a, device_b, created_at) "
            + "VALUES (:a, :b, :createdAt) ON DUPLICATE KEY UPDATE device_a = device_a", nativeQuery = true)
    void insertIfAbsent(@Param("a") String a, @Param("b") String b,
                        @Param("createdAt") Instant createdAt);
}
