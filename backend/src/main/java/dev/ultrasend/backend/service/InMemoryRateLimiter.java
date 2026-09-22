package dev.ultrasend.backend.service;

import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class InMemoryRateLimiter {

    private final ConcurrentHashMap<String, Deque<Long>> hits = new ConcurrentHashMap<>();

    public record Snapshot(int used, int max, long retryAfterMs, boolean acquired) {
        public int remaining() {
            return Math.max(0, max - used);
        }

        public Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("used", used);
            m.put("limit", max);
            m.put("remaining", remaining());
            m.put("retryAfterMs", retryAfterMs);
            return m;
        }
    }

    public boolean tryAcquire(String key, int max, long windowMs) {
        return tryAcquireWithSnapshot(key, max, windowMs).acquired();
    }

    public Snapshot tryAcquireWithSnapshot(String key, int max, long windowMs) {
        return mutate(key, max, windowMs, true);
    }

    public Snapshot snapshot(String key, int max, long windowMs) {
        return mutate(key, max, windowMs, false);
    }

    private Snapshot mutate(String key, int max, long windowMs, boolean acquire) {
        if (key == null || key.isBlank()) {
            key = "unknown";
        }
        long now = System.currentTimeMillis();
        Deque<Long> q = hits.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && now - q.peekFirst() > windowMs) {
                q.pollFirst();
            }
            long retryAfterMs = retryAfterMs(q, now, windowMs);
            if (acquire) {
                if (q.size() >= max) {
                    return new Snapshot(q.size(), max, retryAfterMs, false);
                }
                q.addLast(now);
                return new Snapshot(q.size(), max, retryAfterMs(q, now, windowMs), true);
            }
            return new Snapshot(q.size(), max, retryAfterMs, q.size() < max);
        }
    }

    private static long retryAfterMs(Deque<Long> q, long now, long windowMs) {
        if (q.isEmpty()) {
            return 0L;
        }
        return Math.max(0L, windowMs - (now - q.peekFirst()));
    }
}
