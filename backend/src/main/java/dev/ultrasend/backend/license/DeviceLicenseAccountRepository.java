package dev.ultrasend.backend.license;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;
public interface DeviceLicenseAccountRepository extends JpaRepository<DeviceLicenseAccount, Long> {
    
}
