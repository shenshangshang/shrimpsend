package dev.ultrasend.backend.service;

import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class InMemoryRateLimiter {

    private final ConcurrentHashMap<String, Deque<Long>> hits = new ConcurrentHashMap<>();

    public boolean tryAcquire(String key, int max, long windowMs) {
        if (key == null || key.isBlank()) {
            key = "unknown";
        }
        long now = System.currentTimeMillis();
        Deque<Long> q = hits.computeIfAbsent(key, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && now - q.peekFirst() > windowMs) {
                q.pollFirst();
            }
            if (q.size() >= max) {
                return false;
            }
            q.addLast(now);
            return true;
        }
    }
}
