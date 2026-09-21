package dev.ultrasend.backend.service;

import dev.ultrasend.backend.dto.DeviceHeartbeatRequest;
import dev.ultrasend.backend.entity.DeviceCredential;
import dev.ultrasend.backend.repository.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@DataJpaTest(properties = {"spring.datasource.url=jdbc:h2:mem:deviceidentity;MODE=MySQL;DB_CLOSE_DELAY=-1;LOCK_TIMEOUT=10000",
    "spring.datasource.driver-class-name=org.h2.Driver", "spring.datasource.username=sa", "spring.datasource.password=",
    "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false"})
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import(DeviceIdentityService.class)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class DeviceIdentityServiceTest {
    @Autowired DeviceIdentityService service;
    @Autowired DeviceCredentialRepository credentials;
    @Autowired DeviceProfileRepository profiles;
    @Autowired DeviceLiveSessionRepository sessions;
    @MockBean DeviceRosterPublisher publisher;
    String id;

    @BeforeEach void setup() {
        id = "presence-test-" + UUID.randomUUID();
        credentials.saveAndFlush(DeviceCredential.builder().deviceId(id).secretHash("test").createdAt(Instant.now()).build());
    }
    DeviceHeartbeatRequest request(String tab, long seq, String status) {
        var r = new DeviceHeartbeatRequest(); r.setSessionId(tab); r.setSequence(seq); r.setStatus(status);
        r.setName("My Mac"); r.setPlatform("macos"); return r;
    }
    @Test void worksWithoutAnAccountAndDoesNotPublishEveryHeartbeat() {
        assertEquals("online", service.heartbeat(id, request("a", 1, "online")).getPresenceStatus());
        assertEquals("My Mac", service.describe(id).getName());
        clearInvocations(publisher);
        service.heartbeat(id, request("a", 2, "online"));
        verifyNoInteractions(publisher);
    }
    @Test void closingOneTabDoesNotDisconnectTheOtherAndDelayedOnlineCannotReviveIt() {
        service.heartbeat(id, request("a", 1, "online"));
        service.heartbeat(id, request("b", 1, "online"));
        assertEquals("online", service.heartbeat(id, request("a", 3, "offline")).getPresenceStatus());
        assertEquals("offline", service.heartbeat(id, request("b", 2, "offline")).getPresenceStatus());
        assertEquals("offline", service.heartbeat(id, request("a", 2, "online")).getPresenceStatus());
        assertEquals("online", service.heartbeat(id, request("a", 4, "online")).getPresenceStatus());
    }
    @Test void renameIsTrimmedAndOldHeartbeatNamesCannotUndoItOrMarkOfflineDeviceOnline() {
        service.heartbeat(id, request("a", 1, "online"));
        service.rename(id, "  工作 Mac  ");
        service.heartbeat(id, request("a", 2, "online"));
        assertEquals("工作 Mac", service.describe(id).getName());
        service.heartbeat(id, request("a", 3, "offline"));
        assertEquals("offline", service.rename(id, "New Mac").getPresenceStatus());
        assertThrows(ResponseStatusException.class, () -> service.rename(id, "  "));
        assertThrows(ResponseStatusException.class, () -> service.rename(id, "line\nbreak"));
        assertThrows(ResponseStatusException.class, () -> service.rename(id, "a".repeat(81)));
    }
    @Test void leaseExpiryIsVisibleEvenBeforeSweepAndProducesOneOfflineEvent() {
        service.heartbeat(id, request("a", 1, "online"));
        var p = profiles.findById(id).orElseThrow(); p.setLastSeen(Instant.now().minusSeconds(50)); profiles.saveAndFlush(p);
        var s = sessions.findByDeviceIdAndSessionId(id, "a").orElseThrow(); s.setExpiresAt(Instant.now().minusSeconds(5)); sessions.saveAndFlush(s);
        assertEquals("offline", service.describe(id).getPresenceStatus());
        clearInvocations(publisher);
        service.expire(); service.expire();
        verify(publisher, times(1)).publishPeerUpsertAfterCommit(argThat(d -> id.equals(d.getDeviceId()) && "offline".equals(d.getPresenceStatus())));
    }
    @Test void concurrentFirstHeartbeatsHaveOneProfileAndIndependentLeases() throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            Future<?> a = executor.submit(() -> { await(start); service.heartbeat(id, request("a", 1, "online")); });
            Future<?> b = executor.submit(() -> { await(start); service.heartbeat(id, request("b", 1, "online")); });
            start.countDown(); a.get(10, TimeUnit.SECONDS); b.get(10, TimeUnit.SECONDS);
            assertEquals("online", service.heartbeat(id, request("a", 2, "offline")).getPresenceStatus());
            assertTrue(sessions.findByDeviceIdAndSessionId(id, "b").isPresent());
        } finally { executor.shutdownNow(); }
    }
    private static void await(CountDownLatch latch) { try { latch.await(); } catch (InterruptedException e) { throw new RuntimeException(e); } }
}
