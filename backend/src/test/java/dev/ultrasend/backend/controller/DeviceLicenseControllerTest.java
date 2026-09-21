package dev.ultrasend.backend.controller;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.ultrasend.backend.license.*;
import dev.ultrasend.backend.dto.SendMessageRequest;
import dev.ultrasend.backend.service.MessageService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.web.server.ResponseStatusException;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class DeviceLicenseControllerTest {
    Authentication owner= new UsernamePasswordAuthenticationToken("1",null,List.of(new SimpleGrantedAuthority("ROLE_USER")));
    Authentication device= new UsernamePasswordAuthenticationToken("device-a",null,List.of(new SimpleGrantedAuthority("ROLE_DEVICE")));
    @Test void deviceCannotManagePurchaserAndAccountCannotPretendToBeADevice() {
        DeviceLicenseService service=mock(DeviceLicenseService.class);
        var api=new DeviceLicenseController(service);
        assertThrows(ResponseStatusException.class,()->api.issue(device));
        assertThrows(ResponseStatusException.class,()->api.list(device));
        assertThrows(ResponseStatusException.class,()->api.me(owner));
        assertThrows(ResponseStatusException.class,()->api.release(owner));
        verifyNoInteractions(service);
    }
    @Test void accountCannotReadDeviceMailboxOrMintItsRealtimeToken() {
        var mailbox=new MailboxController(mock(dev.ultrasend.backend.service.MailboxService.class));
        assertEquals(401,mailbox.pending(owner,"device-a",null).getStatusCode().value());
        assertEquals(403,mailbox.pending(device,"device-b",null).getStatusCode().value());
        var realtime=new RealtimeController(mock(dev.ultrasend.backend.realtime.WukongimTokenService.class),mock(dev.ultrasend.backend.service.DeviceCredentialService.class),mock(dev.ultrasend.backend.security.AppJwtService.class),mock(dev.ultrasend.backend.service.InMemoryRateLimiter.class));
        assertEquals(403,realtime.getToken(owner,new MockHttpServletRequest(),"device-a","web").getStatusCode().value());
        assertEquals(403,realtime.getToken(device,new MockHttpServletRequest(),"device-b","web").getStatusCode().value());
    }
    @Test void accountCannotImpersonateADeviceAndCompatibilityPathUsesSameQuota() {
        var service=mock(MessageService.class); var quota=mock(DeviceServiceQuota.class);
        var api=new MessageController(service,quota,new ObjectMapper());
        var req=new SendMessageRequest();
        var body=Map.of("type","text","fromDeviceId","device-a","toDeviceId","device-b"); req.setData(body);
        assertEquals(401,api.send(owner,req).getStatusCode().value());
        when(quota.view("device-a")).thenReturn(Map.of());
        when(quota.acquire("device-a",body)).thenReturn(false);
        assertEquals(429,api.send(device,req).getStatusCode().value()); verifyNoInteractions(service);
        when(quota.acquire("device-a",body)).thenReturn(true);
        assertEquals(204,api.send(device,req).getStatusCode().value()); verify(service).sendFromDevice("device-a",body);

        assertEquals(401,api.history(device,50,null,null).getStatusCode().value());
    }
}
