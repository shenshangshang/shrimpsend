package dev.ultrasend.backend.license;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

/** Shared across backend instances; rejected attempts commit even if redemption rolls back. */
@Service @RequiredArgsConstructor
public class LicenseAbuseGuard {
    private final LicenseRateBucketRepository buckets;
    private final PlatformTransactionManager transactions;
    private final LicenseCodeCodec codec;
    public void check(String key, int max, long windowMs) {
        TransactionTemplate tx = new TransactionTemplate(transactions);
        tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        boolean allowed = Boolean.TRUE.equals(tx.execute(status -> {
            long now = System.currentTimeMillis();
            String id = codec.hash("rate", key);
            buckets.initialize(id, now);
            LicenseRateBucket bucket = buckets.lock(id);
            if (now >= bucket.getWindowStartedAt() + windowMs) {
                bucket.setWindowStartedAt(now);
                bucket.setHits(0);
            }
            if (bucket.getHits() >= max) return false;
            bucket.setHits(bucket.getHits() + 1);
            buckets.save(bucket);
            return true;
        }));
        if (!allowed) throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "license_too_many_attempts");
    }
    @Scheduled(fixedDelay = 3600000)
    public void prune() {
        new TransactionTemplate(transactions).executeWithoutResult(s -> buckets.prune(System.currentTimeMillis() - 86400000));
    }
}
