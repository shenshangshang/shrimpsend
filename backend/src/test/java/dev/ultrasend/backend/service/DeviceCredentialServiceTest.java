package dev.ultrasend.backend.service;

import dev.ultrasend.backend.entity.DeviceCredential;
import dev.ultrasend.backend.repository.DeviceCredentialRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DeviceCredentialServiceTest {

    @Mock
    private DeviceCredentialRepository repository;
    private DeviceCredentialService service;

    @BeforeEach
    void setUp() {
        service = new DeviceCredentialService(repository);
        ReflectionTestUtils.setField(service, "pepper", "pepper");
    }

    @Test
    void firstRegisterPersistsHash() {
        when(repository.findByDeviceId("dev-1")).thenReturn(Optional.empty());
        service.registerOrVerify("dev-1", "secret-secret-secret");
        ArgumentCaptor<DeviceCredential> captor = ArgumentCaptor.forClass(DeviceCredential.class);
        verify(repository).save(captor.capture());
        assertEquals("dev-1", captor.getValue().getDeviceId());
        assertEquals(service.hashSecret("dev-1", "secret-secret-secret"), captor.getValue().getSecretHash());
    }

    @Test
    void mismatchRejected() {
        DeviceCredential existing = DeviceCredential.builder()
                .deviceId("dev-1")
                .secretHash(service.hashSecret("dev-1", "secret-secret-secret"))
                .build();
        when(repository.findByDeviceId("dev-1")).thenReturn(Optional.of(existing));
        assertThrows(ResponseStatusException.class,
                () -> service.registerOrVerify("dev-1", "other-secret-secret"));
    }
}
