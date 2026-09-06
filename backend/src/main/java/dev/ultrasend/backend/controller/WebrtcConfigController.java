package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.membership.MembershipTier;
import dev.ultrasend.backend.service.AppSettingsService;
import dev.ultrasend.backend.service.MembershipService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * ICE server configuration for client WebRTC connections. STUN is handed to
 * everyone; TURN relay is restricted to paying tiers (rank &gt; 0) and only
 * served when the admin configured URL + credentials in {@code app_settings}
 * (keys {@code webrtc.turn-urls} / {@code webrtc.turn-username} /
 * {@code webrtc.turn-credential}). Self-hosters without a TURN setup simply
 * leave those keys empty and clients keep public-STUN-only connectivity.
 */
@RestController
@RequestMapping("/api/webrtc")
@RequiredArgsConstructor
@Slf4j
public class WebrtcConfigController {

    private final AppSettingsService settings;
    private final MembershipService membershipService;

    private static final String DEFAULT_STUN_URLS =
            "stun:stun.miwifi.com:3478,stun:stun.qq.com:3478,stun:stun.l.google.com:19302";

    private record IceServer(List<String> urls, String username, String credential) {
    }

    private record WebrtcConfig(List<IceServer> iceServers, boolean turnEnabled, String tier) {
    }

    @GetMapping("/config")
    public WebrtcConfig config(Authentication auth) {
        List<IceServer> servers = new ArrayList<>();
        List<String> stunUrls = splitUrls(settings.get("webrtc.stun-urls", DEFAULT_STUN_URLS));
        if (!stunUrls.isEmpty()) {
            servers.add(new IceServer(stunUrls, null, null));
        }

        boolean turnEnabled = false;
        String tierCode = null;
        if (auth != null && auth.getPrincipal() != null) {
            try {
                Long userId = Long.parseLong((String) auth.getPrincipal());
                MembershipTier tier = membershipService.getCurrentTier(userId);
                tierCode = tier.getCode();
                boolean vip = settings.getBool("webrtc.vip-only", true) ? tier.getRank() > 0 : true;
                if (vip) {
                    String username = settings.get("webrtc.turn-username", "");
                    String credential = settings.get("webrtc.turn-credential", "");
                    List<String> turnUrls = splitUrls(settings.get("webrtc.turn-urls", ""));
                    if (!username.isBlank() && !credential.isBlank() && !turnUrls.isEmpty()) {
                        servers.add(new IceServer(turnUrls, username, credential));
                        turnEnabled = true;
                    }
                }
            } catch (Exception e) {
                log.warn("webrtc config: failed to resolve membership tier: {}", e.getMessage());
            }
        }
        return new WebrtcConfig(List.copyOf(servers), turnEnabled, tierCode);
    }

    private static List<String> splitUrls(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }
        return Arrays.stream(raw.split("[,\\s]+"))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
    }
}
