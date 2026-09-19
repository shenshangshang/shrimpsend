package dev.ultrasend.backend.repository;

import dev.ultrasend.backend.entity.DevicePairing;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface DevicePairingRepository extends JpaRepository<DevicePairing, Long> {

    Optional<DevicePairing> findByDeviceAAndDeviceB(String deviceA, String deviceB);
}
