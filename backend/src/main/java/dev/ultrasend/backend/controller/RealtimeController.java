package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.dto.DeviceSessionRequest;
import dev.ultrasend.backend.dto.RealtimeTokenResponse;
import dev.ultrasend.backend.realtime.WukongimTokenService;
import dev.ultrasend.backend.security.AppJwtService;
import dev.ultrasend.backend.service.DeviceCredentialService;
import dev.ultrasend.backend.service.InMemoryRateLimiter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/realtime")
@RequiredArgsConstructor
@Slf4j
public class RealtimeController {

    private final WukongimTokenService wukongimTokenService;
    private final DeviceCredentialService deviceCredentialService;
    private final AppJwtService appJwtService;
    private final InMemoryRateLimiter rateLimiter;

    @GetMapping("/token")
    public ResponseEntity<RealtimeTokenResponse> getToken(
            Authentication auth,
            HttpServletRequest request,
            @RequestParam String deviceId,
            @RequestParam(required = false) String platform) {
        if (auth == null || !auth.isAuthenticated()) {
            log.warn("realtime/token unauthenticated 401");
            return ResponseEntity.status(401).build();
        }
        if (deviceId == null || deviceId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        if (!AuthRoles.isDevice(auth) || !deviceId.trim().equals(AuthRoles.deviceId(auth))) {
            return ResponseEntity.status(403).build();
        }
        String userId = (String) auth.getPrincipal();
        RealtimeTokenResponse tokens = issueDeviceChannelToken(
                userId, platform, deviceId.trim(), request);
        log.info("realtime/token userId={} deviceId={} flag={} ws={}",
                userId, deviceId.trim(), tokens.getDeviceFlag(), tokens.getWebsocketUrl());
        return ResponseEntity.ok(tokens);
    }

    @PostMapping("/device-session")
    public ResponseEntity<RealtimeTokenResponse> deviceSession(
            HttpServletRequest request,
            @Valid @RequestBody DeviceSessionRequest body) {
        String ip = clientIp(request);
        if (!rateLimiter.tryAcquire("device-session:" + ip, 30, 60_000L)) {
            return ResponseEntity.status(429).build();
        }
        deviceCredentialService.registerOrVerify(body.getDeviceId(), body.getDeviceSecret());
        RealtimeTokenResponse tokens = issueDeviceChannelToken(
                body.getDeviceId(), body.getPlatform(), body.getDeviceId().trim(), request);
        tokens.setDeviceAccessToken(appJwtService.generateDeviceAccessToken(body.getDeviceId().trim()));
        log.info("realtime/device-session deviceId={} flag={} ws={}",
                body.getDeviceId(), tokens.getDeviceFlag(), tokens.getWebsocketUrl());
        return ResponseEntity.ok(tokens);
    }

    private RealtimeTokenResponse issueDeviceChannelToken(
            String userId, String platform, String deviceId, HttpServletRequest request) {
        return wukongimTokenService.createToken(
                userId, platform, deviceId, requestHost(request));
    }

    static String requestHost(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-Host");
        String raw = (forwarded != null && !forwarded.isBlank())
                ? forwarded.split(",")[0].trim()
                : request.getServerName();
        if (raw == null || raw.isBlank()) {
            return null;
        }
        int colon = raw.indexOf(':');
        return colon > 0 ? raw.substring(0, colon) : raw;
    }

    static String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
