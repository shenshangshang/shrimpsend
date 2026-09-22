package dev.ultrasend.backend.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.ultrasend.backend.entity.Device;
import dev.ultrasend.backend.repository.DeviceRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Base64;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class WukongimPublishServiceTest {

    @Mock
    private WukongimApiClient apiClient;
    @Mock
    private DeviceRepository deviceRepository;

    private WukongimPublishService service;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        service = new WukongimPublishService(apiClient, objectMapper, deviceRepository);
        ReflectionTestUtils.setField(service, "systemUid", "ultrasend");
        ReflectionTestUtils.setField(service, "signalingExpireSec", 120);
        ReflectionTestUtils.setField(service, "rosterExpireSec", 30);
        ReflectionTestUtils.setField(service, "dualWriteUserChannel", true);
        lenient().when(deviceRepository.findAllByUser_IdAndActiveTrue(any())).thenReturn(List.of());
    }

    @Test
    void persistentTextHasZeroExpireAndWrappedPayload() throws Exception {
        Map<String, Object> envelope = Map.of("type", "text", "fromDeviceId", "a");
        service.publishToUser("9", envelope);
        ArgumentCaptor<String> payload = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<Integer> expire = ArgumentCaptor.forClass(Integer.class);
        verify(apiClient).sendMessage(eq("ultrasend"), eq("9"), eq(1), payload.capture(), expire.capture(),
                org.mockito.ArgumentMatchers.startsWith("shrimp-9-"));
        assertEquals(0, expire.getValue());
        Map<?, ?> decoded = objectMapper.readValue(Base64.getDecoder().decode(payload.getValue()), Map.class);
        assertEquals(200, ((Number) decoded.get("type")).intValue());
        assertEquals("text", ((Map<?, ?>) decoded.get("envelope")).get("type"));
    }

    @Test
    void ephemeralUsesSignalingExpire() {
        service.publishToUser("9", Map.of("type", "webrtc_offer"));
        ArgumentCaptor<Integer> expire = ArgumentCaptor.forClass(Integer.class);
        verify(apiClient).sendMessage(eq("ultrasend"), eq("9"), eq(1), org.mockito.ArgumentMatchers.anyString(),
                expire.capture(), org.mockito.ArgumentMatchers.anyString());
        assertEquals(120, expire.getValue());
    }

    @Test
    void rosterUsesShortExpire() {
        service.publishToUser("9", Map.of("type", "device_roster_patch"));
        ArgumentCaptor<Integer> expire = ArgumentCaptor.forClass(Integer.class);
        verify(apiClient).sendMessage(eq("ultrasend"), eq("9"), eq(1), org.mockito.ArgumentMatchers.anyString(),
                expire.capture(), org.mockito.ArgumentMatchers.anyString());
        assertEquals(30, expire.getValue());
        assertTrue(true);
    }

    @Test
    void publishToUserFansOutToBoundDevices() {
        Device device = Device.builder().deviceId("mac-1").build();
        when(deviceRepository.findAllByUser_IdAndActiveTrue(9L)).thenReturn(List.of(device));
        service.publishToUser("9", Map.of("type", "text"));
        verify(apiClient).sendMessage(eq("ultrasend"), eq("9"), eq(1), org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyString());
        verify(apiClient).sendMessage(eq("ultrasend"), eq("mac-1"), eq(1), org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.anyInt(), org.mockito.ArgumentMatchers.anyString());
    }
}
