package dev.ultrasend.backend.repository;

import dev.ultrasend.backend.entity.DeviceCredential;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface DeviceCredentialRepository extends JpaRepository<DeviceCredential, Long> {

    Optional<DeviceCredential> findByDeviceId(String deviceId);
}
