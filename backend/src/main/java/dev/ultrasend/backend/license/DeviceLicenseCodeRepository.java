package dev.ultrasend.backend.license;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;
public interface DeviceLicenseCodeRepository extends JpaRepository<DeviceLicenseCode, String> {
    Optional<DeviceLicenseCode> findByCodeHash(String hash);
    Optional<DeviceLicenseCode> findByQrHash(String hash);
    List<DeviceLicenseCode> findByOwnerUserIdAndStatusInOrderByCreatedAtDesc(Long owner, Collection<String> states);
    List<DeviceLicenseCode> findByDeviceIdAndStatusOrderByCreatedAtDesc(String deviceId, String status);
}
