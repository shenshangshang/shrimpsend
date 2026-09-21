package dev.ultrasend.backend.controller;

import dev.ultrasend.backend.dto.DeviceUpdateRequest;
import dev.ultrasend.backend.service.DeviceIdentityService;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.web.server.ResponseStatusException;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class DeviceIdentityControllerTest {
    @Test void onlyAuthenticatedDeviceCanUpdateItsOwnIdentity() {
        var service = mock(DeviceIdentityService.class);
        var api = new DeviceIdentityController(service);
        var account = new UsernamePasswordAuthenticationToken("1", null, List.of(new SimpleGrantedAuthority("ROLE_USER")));
        var device = new UsernamePasswordAuthenticationToken("device-a", null, List.of(new SimpleGrantedAuthority("ROLE_DEVICE")));
        var request = new DeviceUpdateRequest(); request.setName("New Mac");
        assertThrows(ResponseStatusException.class, () -> api.rename(account, request));
        assertThrows(ResponseStatusException.class, () -> api.rename(null, request));
        verifyNoInteractions(service);
        api.rename(device, request);
        verify(service).rename("device-a", "New Mac");
    }
}
