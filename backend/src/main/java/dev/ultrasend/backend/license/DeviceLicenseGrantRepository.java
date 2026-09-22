package dev.ultrasend.backend.license;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;
public interface DeviceLicenseGrantRepository extends JpaRepository<DeviceLicenseGrant, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("SELECT g FROM DeviceLicenseGrant g WHERE g.deviceId=:id")
    Optional<DeviceLicenseGrant> lockByDeviceId(@Param("id") String id);
    List<DeviceLicenseGrant> findByOwnerUserIdAndRevokedAtIsNullOrderByActivatedAtAscDeviceIdAsc(Long ownerUserId);
}
