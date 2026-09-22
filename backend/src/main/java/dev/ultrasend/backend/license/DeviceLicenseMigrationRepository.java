package dev.ultrasend.backend.license;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;
public interface DeviceLicenseMigrationRepository extends JpaRepository<DeviceLicenseMigration, Integer> {
    @Modifying @Query(value="INSERT IGNORE INTO device_license_migration (id, completed) VALUES (1, false)", nativeQuery=true)
    void initialize();
    @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("SELECT m FROM DeviceLicenseMigration m WHERE m.id=1")
    DeviceLicenseMigration lockSingleton();
}
