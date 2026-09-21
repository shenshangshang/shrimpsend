package dev.ultrasend.backend.license;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;
public interface LicenseRateBucketRepository extends JpaRepository<LicenseRateBucket, String> {
    @Modifying @Query(value="INSERT INTO license_rate_buckets (id, window_started_at, hits) VALUES (:id, :now, 0) ON DUPLICATE KEY UPDATE id=VALUES(id)", nativeQuery=true)
    void initialize(@Param("id") String id, @Param("now") long now);
    @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("SELECT b FROM LicenseRateBucket b WHERE b.id=:id")
    LicenseRateBucket lock(@Param("id") String id);
    @Modifying @Query("DELETE FROM LicenseRateBucket b WHERE b.windowStartedAt < :before")
    void prune(@Param("before") long before);
}
