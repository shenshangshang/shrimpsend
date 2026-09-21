package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.dto.*;
import dev.ultrasend.backend.service.DeviceIdentityService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController @RequestMapping("/api/devices/self") @RequiredArgsConstructor
public class DeviceIdentityController {
    private final DeviceIdentityService identity;
    private String deviceId(Authentication auth) {
        if (auth == null || !AuthRoles.isDevice(auth)) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        return AuthRoles.deviceId(auth);
    }
    @PostMapping("/presence")
    public DeviceDto heartbeat(Authentication auth, @Valid @RequestBody DeviceHeartbeatRequest request) {
        return identity.heartbeat(deviceId(auth), request);
    }
    @PatchMapping("/profile")
    public DeviceDto rename(Authentication auth, @Valid @RequestBody DeviceUpdateRequest request) {
        return identity.rename(deviceId(auth), request.getName());
    }
}
