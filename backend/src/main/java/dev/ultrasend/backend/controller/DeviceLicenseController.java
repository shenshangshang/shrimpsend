package dev.ultrasend.backend.controller;
import dev.ultrasend.backend.license.DeviceLicenseService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.util.Map;

@RestController @RequestMapping("/api/device-licenses") @RequiredArgsConstructor
public class DeviceLicenseController {
    private final DeviceLicenseService licenses;
    private Long owner(Authentication a) {
        if(a==null || !a.isAuthenticated() || AuthRoles.isDevice(a)) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        return Long.valueOf(a.getName());
    }
    private String device(Authentication a) {
        if(a==null || !a.isAuthenticated() || !AuthRoles.isDevice(a)) throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        return AuthRoles.deviceId(a);
    }
    public record Redeem(@Size(max=64) String code,@Size(max=128) String qrToken,@Size(max=128) String name,@Size(max=32) String platform) {}
    public record Rename(@Size(max=128) String name) {}
    @GetMapping public Map<String,Object> list(Authentication a) { return licenses.dashboard(owner(a)); }
    @GetMapping("/me") public Map<String,Object> me(Authentication a) { return licenses.mine(device(a)); }
    @PostMapping("/codes") public Map<String,Object> issue(Authentication a) { return licenses.issue(owner(a)); }
    @PostMapping("/redeem") public Map<String,Object> redeem(Authentication a,@Valid @RequestBody Redeem body,HttpServletRequest r) {
        // Never trust a caller-supplied forwarding header for brute-force protection.
        return licenses.redeem(device(a),body.code(),body.qrToken(),body.name(),body.platform(),r.getRemoteAddr());
    }
    @PostMapping("/requests/{id}/approve") public Map<String,Object> approve(Authentication a,@PathVariable String id) { return licenses.approve(owner(a),id); }
    @DeleteMapping("/requests/{id}") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cancel(Authentication a,@PathVariable String id) { licenses.cancel(owner(a),id); }
    @DeleteMapping("/devices/{id}") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revoke(Authentication a,@PathVariable String id) { licenses.revoke(owner(a),id); }
    @PatchMapping("/devices/{id}") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void rename(Authentication a,@PathVariable String id,@Valid @RequestBody Rename body) { licenses.rename(owner(a),id,body.name()); }
    @DeleteMapping("/me") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void release(Authentication a) { licenses.release(device(a)); }
}
