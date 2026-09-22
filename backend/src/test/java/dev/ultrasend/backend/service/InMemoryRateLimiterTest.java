package dev.ultrasend.backend.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class InMemoryRateLimiterTest {

    @Test
    void tryAcquireWithSnapshotReportsUsedAndRejectsAtMax() {
        InMemoryRateLimiter limiter = new InMemoryRateLimiter();
        InMemoryRateLimiter.Snapshot first = limiter.tryAcquireWithSnapshot("k", 2, 60_000L);
        assertTrue(first.acquired());
        assertEquals(1, first.used());
        assertEquals(1, first.remaining());

        InMemoryRateLimiter.Snapshot second = limiter.tryAcquireWithSnapshot("k", 2, 60_000L);
        assertTrue(second.acquired());
        assertEquals(2, second.used());
        assertEquals(0, second.remaining());

        InMemoryRateLimiter.Snapshot denied = limiter.tryAcquireWithSnapshot("k", 2, 60_000L);
        assertFalse(denied.acquired());
        assertEquals(2, denied.used());
        assertEquals(0, denied.remaining());
        assertTrue(denied.retryAfterMs() > 0);
    }

    @Test
    void snapshotDoesNotConsume() {
        InMemoryRateLimiter limiter = new InMemoryRateLimiter();
        limiter.tryAcquire("k", 5, 60_000L);
        InMemoryRateLimiter.Snapshot a = limiter.snapshot("k", 5, 60_000L);
        InMemoryRateLimiter.Snapshot b = limiter.snapshot("k", 5, 60_000L);
        assertEquals(1, a.used());
        assertEquals(1, b.used());
        assertEquals(4, a.remaining());
    }
}
