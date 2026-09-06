package dev.ultrasend.backend.service;

import dev.ultrasend.backend.entity.AppSetting;
import dev.ultrasend.backend.repository.AppSettingRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Runtime-editable settings stored in the {@code app_settings} table and
 * served with a short cache. The admin UI writes here; consumers (mail
 * dispatch etc.) read fresh values without a restart.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class AppSettingsService {

    /** Keys the admin UI is allowed to write; anything else is rejected. */
    public static final Map<String, String> ALLOWED_KEYS = Map.ofEntries(
            Map.entry("smtp.host", "SMTP 服务器"),
            Map.entry("smtp.port", "SMTP 端口"),
            Map.entry("smtp.username", "SMTP 用户名"),
            Map.entry("smtp.password", "SMTP 密码/授权码"),
            Map.entry("smtp.from", "发件人邮箱"),
            Map.entry("smtp.from-name", "发件人名称"),
            Map.entry("smtp.starttls", "STARTTLS (true/false)"),
            Map.entry("smtp.ssl", "SSL/TLS (true/false)"),
            Map.entry("mail.provider", "邮件通道 (auto|sendcloud|smtp)"),
            Map.entry("register.enabled", "开放注册 (true/false)"),
            Map.entry("default-device-limit", "默认设备数限制")
    );

    private static final long CACHE_TTL_MS = 15_000;

    private final AppSettingRepository repo;
    private final Map<String, CachedValue> cache = new ConcurrentHashMap<>();

    /** Returns the stored value, or {@code fallback} when unset/blank. */
    public String get(String key, String fallback) {
        CachedValue cached = cache.get(key);
        long now = System.currentTimeMillis();
        if (cached == null || now - cached.fetchedAt > CACHE_TTL_MS) {
            String value = repo.findById(key).map(AppSetting::getValue).orElse(null);
            cached = new CachedValue(value, now);
            cache.put(key, cached);
        }
        if (cached.value == null || cached.value.isBlank()) {
            return fallback;
        }
        return cached.value;
    }

    public boolean getBool(String key, boolean fallback) {
        String raw = get(key, null);
        if (raw == null) return fallback;
        return raw.equalsIgnoreCase("true") || raw.equals("1");
    }

    public void set(String key, String value) {
        if (!ALLOWED_KEYS.containsKey(key)) {
            throw new IllegalArgumentException("未知配置项: " + key);
        }
        AppSetting setting = repo.findById(key).orElseGet(() -> {
            AppSetting s = new AppSetting();
            s.setKey(key);
            return s;
        });
        setting.setValue(value == null || value.isBlank() ? null : value.trim());
        setting.setUpdatedAt(Instant.now());
        repo.save(setting);
        cache.remove(key);
        log.info("app setting updated key={}", key);
    }

    public void invalidate() {
        cache.clear();
    }

    private record CachedValue(String value, long fetchedAt) {
    }
}
