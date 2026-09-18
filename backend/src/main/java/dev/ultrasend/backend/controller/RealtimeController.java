package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.dto.RealtimeTokenResponse;
import dev.ultrasend.backend.realtime.WukongimTokenService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
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
        RealtimeTokenResponse tokens = wukongimTokenService.createToken(userId, platform, deviceId.trim());
        log.info("realtime/token userId={} deviceId={} flag={}", userId, deviceId.trim(), tokens.getDeviceFlag());
        return ResponseEntity.ok(tokens);
    }
}
