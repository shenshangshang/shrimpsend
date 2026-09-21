package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.dto.MailboxPendingItemDto;
import dev.ultrasend.backend.service.MailboxService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/mailbox")
@RequiredArgsConstructor
@Slf4j
public class MailboxController {

    private final MailboxService mailboxService;

    @GetMapping("/pending")
    public ResponseEntity<List<MailboxPendingItemDto>> pending(
            Authentication auth,
            @RequestParam String deviceId,
            @RequestParam(required = false) Long afterId) {
        if (auth == null || !auth.isAuthenticated() || !AuthRoles.isDevice(auth)) {
            return ResponseEntity.status(401).build();
        }
        if (deviceId == null || deviceId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        String authDeviceId = AuthRoles.deviceId(auth);
        if (!deviceId.trim().equals(authDeviceId)) return ResponseEntity.status(403).build();
        List<MailboxPendingItemDto> items = mailboxService.pendingForDevice(authDeviceId, afterId);
        return ResponseEntity.ok(items);
    }
}
