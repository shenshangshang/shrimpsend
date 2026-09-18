package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.dto.RealtimeTokenResponse;
import dev.ultrasend.backend.realtime.WukongimTokenService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/realtime")
@RequiredArgsConstructor
@Slf4j
public class RealtimeController {

    private final WukongimTokenService wukongimTokenService;

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
        String userId = (String) auth.getPrincipal();
        RealtimeTokenResponse tokens = wukongimTokenService.createToken(
                userId, platform, deviceId.trim(), requestHost(request));
        log.info("realtime/token userId={} deviceId={} flag={} ws={}",
                userId, deviceId.trim(), tokens.getDeviceFlag(), tokens.getWebsocketUrl());
        return ResponseEntity.ok(tokens);
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
}
