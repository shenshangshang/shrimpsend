package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.config.AdminProperties;

import dev.ultrasend.backend.entity.AppSetting;
import dev.ultrasend.backend.entity.Device;
import dev.ultrasend.backend.entity.MembershipEntitlement;
import dev.ultrasend.backend.entity.User;
import dev.ultrasend.backend.repository.AppSettingRepository;
import dev.ultrasend.backend.repository.DeviceRepository;
import dev.ultrasend.backend.repository.EmailVerificationCodeRepository;
import dev.ultrasend.backend.repository.MembershipEntitlementRepository;
import dev.ultrasend.backend.repository.UserRepository;
import dev.ultrasend.backend.service.AdminAuthService;
import dev.ultrasend.backend.service.AppSettingsService;
import dev.ultrasend.backend.service.DeviceService;
import dev.ultrasend.backend.service.MembershipService;
import dev.ultrasend.backend.service.SendCloudMailService;
import dev.ultrasend.backend.service.SmtpMailService;
import dev.ultrasend.backend.service.VerificationCodeService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Self-host admin API: user/device management, runtime-editable settings
 * (mail credentials etc. persisted in app_settings, applied without restart)
 * and a direct verification-code issuer. Gated on {@code app.admin.emails}.
 */
@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
@Slf4j
public class AdminController {

    private final AdminAuthService adminAuthService;
    private final AdminProperties adminProperties;
    private final UserRepository userRepository;
    private final DeviceRepository deviceRepository;
    private final MembershipEntitlementRepository entitlementRepository;
    private final EmailVerificationCodeRepository codeRepository;
    private final AppSettingRepository appSettingRepository;
    private final AppSettingsService settings;
    private final DeviceService deviceService;
    private final MembershipService membershipService;
    private final SendCloudMailService sendCloudMailService;
    private final SmtpMailService smtpMailService;
    private final SecureRandom random = new SecureRandom();

    // ---------------------------------------------------------------- overview

    @GetMapping("/overview")
    public Map<String, Object> overview(Authentication auth) {
        adminAuthService.requireAdmin(auth);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("users", userRepository.count());
        out.put("devices", deviceRepository.count());
        out.put("sendcloudConfigured", sendCloudMailService.isConfigured());
        out.put("smtpConfigured", smtpMailService.isConfigured());
        out.put("mailProvider", settings.get("mail.provider", "auto"));
        out.put("registerEnabled", settings.getBool("register.enabled", true));
        out.put("adminEmails", adminProperties.getEmails());
        return out;
    }

    // ------------------------------------------------------------------- users

    @GetMapping("/users")
    public List<Map<String, Object>> users(Authentication auth) {
        adminAuthService.requireAdmin(auth);
        List<Map<String, Object>> rows = new ArrayList<>();
        for (User u : userRepository.findAll()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("id", u.getId());
            row.put("email", u.getEmail());
            row.put("username", u.getUsername());
            var ent = entitlementRepository.findByUserId(u.getId()).orElse(null);
            row.put("tierCode", ent == null ? "FREE" : ent.getTierCode());
            row.put("deviceLimit", ent == null ? null : ent.getDeviceLimit());
            row.put("deviceCount", deviceRepository.countByUser_IdAndActiveTrue(u.getId()));
            rows.add(row);
        }
        return rows;
    }

    public record AdminUserPatch(String tierCode, Integer deviceLimit) {
    }

    @PatchMapping("/users/{id}")
    public ResponseEntity<Map<String, Object>> patchUser(
            Authentication auth, @PathVariable Long id, @RequestBody AdminUserPatch body) {
        adminAuthService.requireAdmin(auth);
        User user = userRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        MembershipEntitlement ent = entitlementRepository.findByUserId(id)
                .orElseGet(() -> MembershipEntitlement.builder()
                        .user(user)
                        .tierCode("FREE")
                        .deviceLimit(membershipService.resolveDeviceLimitForUser(id))
                        .addonPacks(0)
                        .isLifetime(false)
                        .effectiveAt(Instant.now())
                        .updatedAt(Instant.now())
                        .build());
        if (body.tierCode() != null && !body.tierCode().isBlank()) {
            ent.setTierCode(body.tierCode().trim().toUpperCase());
        }
        if (body.deviceLimit() != null && body.deviceLimit() > 0) {
            ent.setDeviceLimit(body.deviceLimit());
        }
        ent.setUpdatedAt(Instant.now());
        entitlementRepository.save(ent);
        log.info("admin patched user id={} tier={} limit={}", id, ent.getTierCode(), ent.getDeviceLimit());
        return ResponseEntity.ok(Map.of(
                "id", id,
                "tierCode", ent.getTierCode(),
                "deviceLimit", ent.getDeviceLimit()));
    }

    // ----------------------------------------------------------------- devices

    @GetMapping("/devices")
    public List<Map<String, Object>> devices(
            Authentication auth, @RequestParam(required = false) Long userId) {
        adminAuthService.requireAdmin(auth);
        List<Device> devices = userId == null
                ? deviceRepository.findAll()
                : deviceRepository.findAllByUser_IdAndActiveTrue(userId);
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Device d : devices) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("deviceId", d.getDeviceId());
            row.put("userId", d.getUser() == null ? null : d.getUser().getId());
            row.put("name", d.getName());
            row.put("platform", d.getPlatform());
            row.put("active", d.isActive());
            row.put("presenceStatus", d.getPresenceStatus());
            row.put("lanHttpUrl", d.getLanHttpUrl());
            row.put("lastSeen", d.getLastSeen() == null ? null : d.getLastSeen().toString());
            rows.add(row);
        }
        return rows;
    }

    @DeleteMapping("/devices/{deviceId}")
    public ResponseEntity<Void> deleteDevice(
            Authentication auth, @PathVariable String deviceId, @RequestParam Long userId) {
        adminAuthService.requireAdmin(auth);
        deviceService.unregister(userId, deviceId);
        log.info("admin unregistered device={} userId={}", deviceId, userId);
        return ResponseEntity.noContent().build();
    }

    // ---------------------------------------------------------------- settings

    @GetMapping("/settings")
    public List<Map<String, Object>> settings(Authentication auth) {
        adminAuthService.requireAdmin(auth);
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Map.Entry<String, String> e : AppSettingsService.ALLOWED_KEYS.entrySet()) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("key", e.getKey());
            row.put("description", e.getValue());
            String stored = appSettingRepository.findById(e.getKey()).map(AppSetting::getValue).orElse(null);
            boolean secret = e.getKey().toLowerCase().contains("password");
            row.put("value", secret ? (stored == null || stored.isBlank() ? "" : "••••••") : stored);
            row.put("set", stored != null && !stored.isBlank());
            rows.add(row);
        }
        return rows;
    }

    public record SettingsPatch(Map<String, String> values) {
    }

    @PutMapping("/settings")
    public ResponseEntity<Void> putSettings(Authentication auth, @RequestBody SettingsPatch body) {
        adminAuthService.requireAdmin(auth);
        if (body.values() == null) {
            return ResponseEntity.badRequest().build();
        }
        body.values().forEach((k, v) -> {
            // Blank value clears the override; masked secrets are skipped so the
            // admin UI can round-trip the table without wiping credentials.
            if (v == null || k.toLowerCase().contains("password") && "••••••".equals(v)) {
                return;
            }
            settings.set(k, v);
        });
        return ResponseEntity.noContent().build();
    }

    // ------------------------------------------------------------------- codes

    public record CodeRequest(String email, String type) {
    }

    /** Issues a verification code directly (no mail), for self-hosted logins. */
    @PostMapping("/codes")
    public Map<String, Object> issueCode(Authentication auth, @RequestBody CodeRequest body) {
        adminAuthService.requireAdmin(auth);
        if (body.email() == null || body.email().isBlank()) {
            throw new IllegalArgumentException("email 必填");
        }
        String email = body.email().trim().toLowerCase();
        String type = body.type() == null || body.type().isBlank() ? "REGISTER" : body.type().trim().toUpperCase();
        String code = String.format("%06d", random.nextInt(1_000_000));
        var entity = dev.ultrasend.backend.entity.EmailVerificationCode.builder()
                .email(email)
                .code(code)
                .type(type)
                .createdAt(Instant.now())
                .expiresAt(Instant.now().plus(10, ChronoUnit.MINUTES))
                .used(false)
                .build();
        codeRepository.save(entity);
        log.info("admin issued code email={} type={}", email, type);
        return Map.of("email", email, "type", type, "code", code);
    }

    // --------------------------------------------------------------- test mail

    public record TestMailRequest(String to) {
    }

    @PostMapping("/mail/test")
    public Map<String, Object> testMail(Authentication auth, @RequestBody TestMailRequest body) {
        adminAuthService.requireAdmin(auth);
        smtpMailService.sendHtml(
                body.to(), "虾传 SMTP 测试邮件",
                "<p>这是一封来自虾传管理后台的 SMTP 测试邮件，收到即说明邮件服务配置成功。</p>");
        return Map.of("sent", true);
    }
}
