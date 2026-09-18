package dev.ultrasend.backend.realtime;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class WukongimTokenServiceTest {

    @Mock
    private WukongimApiClient apiClient;

    @Test
    void issuesSecondaryDeviceToken() {
        WukongimTokenService service = new WukongimTokenService(apiClient);
        ReflectionTestUtils.setField(service, "wsPublicUrl", "ws://127.0.0.1:5200");
        ReflectionTestUtils.setField(service, "managerToken", "dev-wukongim-manager-token");
        var token = service.createToken("42", "macos", "mac-1");
        assertEquals("42", token.getUid());
        assertEquals(2, token.getDeviceFlag());
        assertEquals(0, token.getDeviceLevel());
        assertEquals("42", token.getChannelId());
        assertEquals(1, token.getChannelType());
        assertEquals("ws://127.0.0.1:5200", token.getWebsocketUrl());
        assertEquals(
                "ws://192.168.0.101:5200",
                service.createToken("42", "android", "phone-1", "192.168.0.101").getWebsocketUrl());
        ReflectionTestUtils.setField(service, "wsPublicUrl", "wss://api.xiachuan.net/wkws");
        assertEquals(
                "wss://api.xiachuan.net/wkws",
                service.createToken("42", "android", "phone-1", "192.168.0.101").getWebsocketUrl());
        assertEquals(service.stableToken("42", 2), token.getToken());
        var again = service.createToken("42", "macos", "mac-2");
        assertEquals(token.getToken(), again.getToken());
        verify(apiClient, times(2)).updateUserToken(eq("42"), eq(token.getToken()), eq(2), eq(0),
                org.mockito.ArgumentMatchers.anyString());
    }
}
