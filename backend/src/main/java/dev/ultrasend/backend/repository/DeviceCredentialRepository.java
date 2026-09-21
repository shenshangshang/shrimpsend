package dev.ultrasend.backend.repository;

import dev.ultrasend.backend.entity.DeviceCredential;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface DeviceCredentialRepository extends JpaRepository<DeviceCredential, Long> {

    @org.springframework.data.jpa.repository.Lock(jakarta.persistence.LockModeType.PESSIMISTIC_WRITE)
    @org.springframework.data.jpa.repository.Query("SELECT d FROM DeviceCredential d WHERE d.deviceId = :id")
    java.util.Optional<DeviceCredential> lockByDeviceId(@org.springframework.data.repository.query.Param("id") String id);

    Optional<DeviceCredential> findByDeviceId(String deviceId);
}
