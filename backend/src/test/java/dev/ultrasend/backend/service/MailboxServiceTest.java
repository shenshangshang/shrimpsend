package dev.ultrasend.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.ultrasend.backend.entity.MailboxItem;
import dev.ultrasend.backend.repository.MailboxItemRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class MailboxServiceTest {

    @Mock
    private MailboxItemRepository mailboxItemRepository;

    private MailboxService mailboxService;

    @BeforeEach
    void setUp() {
        mailboxService = new MailboxService(mailboxItemRepository, new ObjectMapper());
        ReflectionTestUtils.setField(mailboxService, "mailboxTtlSec", 120L);
    }

    @Test
    void storeIfEphemeralPersistsLanOffer() {
        Map<String, Object> envelope = Map.of(
                "type", "lan_file_offer",
                "fromDeviceId", "phone",
                "toDeviceId", "desktop",
                "payload", Map.of("pullUrl", "http://lan/file"));

        mailboxService.storeIfEphemeral(9L, envelope);

        ArgumentCaptor<MailboxItem> captor = ArgumentCaptor.forClass(MailboxItem.class);
        verify(mailboxItemRepository).save(captor.capture());
        MailboxItem saved = captor.getValue();
        assertEquals(9L, saved.getUserId());
        assertEquals("phone", saved.getFromDeviceId());
        assertEquals("desktop", saved.getToDeviceId());
        assertEquals("lan_file_offer", saved.getType());
        assertTrue(saved.getExpiresAt().isAfter(saved.getCreatedAt()));
        assertTrue(saved.getData().contains("pullUrl"));
    }

    @Test
    void storeIfEphemeralIgnoresChatText() {
        mailboxService.storeIfEphemeral(1L, Map.of("type", "text", "fromDeviceId", "a"));
        verify(mailboxItemRepository, never()).save(any());
    }

    @Test
    void pendingMapsRowsAndSkipsBadJson() {
        MailboxItem ok = MailboxItem.builder()
                .id(4L)
                .userId(1L)
                .data("{\"type\":\"webrtc_offer\"}")
                .build();
        MailboxItem bad = MailboxItem.builder()
                .id(5L)
                .userId(1L)
                .data("not-json")
                .build();
        when(mailboxItemRepository.findPending(eq(1L), eq("desktop"), eq(2L), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(ok, bad));
        when(mailboxItemRepository.findPendingForDevice(eq("desktop"), eq(2L), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of());

        var items = mailboxService.pending(1L, "desktop", 2L);

        assertEquals(1, items.size());
        assertEquals(4L, items.get(0).getId());
        assertInstanceOf(Map.class, items.get(0).getData());
    }

    @Test
    void pendingRequiresDeviceId() {
        assertThrows(IllegalArgumentException.class, () -> mailboxService.pending(1L, "  ", null));
    }
}
