package dev.ultrasend.backend.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.ultrasend.backend.realtime.RealtimePublisher;
import dev.ultrasend.backend.config.MessageEncryptionProperties;
import dev.ultrasend.backend.config.UserDataEncryptionProperties;
import dev.ultrasend.backend.entity.Device;
import dev.ultrasend.backend.entity.Message;
import dev.ultrasend.backend.entity.User;
import dev.ultrasend.backend.repository.DeviceRepository;
import dev.ultrasend.backend.repository.MessageRepository;
import dev.ultrasend.backend.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.env.Environment;
import org.springframework.data.domain.Pageable;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class MessageServiceTest {

    @Mock
    private MessageRepository messageRepository;
    @Mock
    private RealtimePublisher realtimePublisher;
    @Mock
    private MailboxService mailboxService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private Environment environment;

    private MessageCryptoService cryptoService;
    private UserDataEncryptionService userDataEncryption;
    private MessageService messageService;
    @Mock
    private DevicePairingService devicePairingService;
    @Mock
    private DeviceRepository deviceRepository;
    private ObjectMapper objectMapper;

    private static final byte[] USER_KEK = "01234567890123456789012345678901".getBytes(StandardCharsets.UTF_8);

    @BeforeEach
    void setUp() {
        MessageEncryptionProperties properties = new MessageEncryptionProperties();
        properties.setKeyBase64(Base64.getEncoder().encodeToString(
                "12345678901234567890123456789012".getBytes(StandardCharsets.UTF_8)));
        cryptoService = new MessageCryptoService(properties, environment);
        cryptoService.init();

        UserDataEncryptionProperties userProperties = new UserDataEncryptionProperties();
        userProperties.setKekBase64(Base64.getEncoder().encodeToString(USER_KEK));
        userDataEncryption = new UserDataEncryptionService(userProperties, userRepository, environment);
        userDataEncryption.init();

        User user = User.builder().id(1L).build();
        lenient().when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        lenient().when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

        objectMapper = new ObjectMapper();
        messageService = new MessageService(
                messageRepository,
                realtimePublisher,
                mailboxService,
                objectMapper,
                cryptoService,
                userDataEncryption,
                devicePairingService,
                deviceRepository);
    }

    @Test
    void sendPersistsOnlyTextPayloadEncryptedButPublishesPlainEnvelope() throws Exception {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "text");
        envelope.put("payload", Map.of("text", "secret text"));
        envelope.put("fromDeviceId", "device_a");
        envelope.put("ts", 1L);

        messageService.send("1", envelope);

        ArgumentCaptor<Message> messageCaptor = ArgumentCaptor.forClass(Message.class);
        verify(messageRepository).save(messageCaptor.capture());
        Message saved = messageCaptor.getValue();
        assertFalse(cryptoService.isEncrypted(saved.getData()));
        assertFalse(saved.getData().contains("secret text"));
        assertTrue(saved.getData().contains("\"type\":\"text\""));
        assertTrue(saved.getData().contains("\"fromDeviceId\":\"device_a\""));
        @SuppressWarnings("unchecked")
        Map<String, Object> stored = objectMapper.readValue(saved.getData(), Map.class);
        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) stored.get("payload");
        assertTrue(userDataEncryption.isUserEncrypted(payload.get("text").toString()));
        verify(realtimePublisher).publishToUserBestEffort(eq("1"), same(envelope));
    }

    @Test
    void sendEphemeralStoresMailboxInsteadOfHistory() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "lan_file_offer");
        envelope.put("payload", Map.of("pullUrl", "http://10.0.0.2/f"));
        envelope.put("fromDeviceId", "device_a");
        envelope.put("ts", 1L);

        messageService.send("1", envelope);

        verify(messageRepository, never()).save(any());
        verify(mailboxService).storeIfEphemeral(eq(1L), same(envelope));
        verify(realtimePublisher).publishToUserBestEffort(eq("1"), same(envelope));
        verify(realtimePublisher, never()).publishToDeviceBestEffort(any(), any());
    }

    @Test
    void sendDirectedEphemeralAlsoPublishesToExternalDevice() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "lan_file_offer");
        envelope.put("payload", Map.of("pullUrl", "http://10.0.0.2/f"));
        envelope.put("fromDeviceId", "device_a");
        envelope.put("toDeviceId", "web-guest");
        envelope.put("ts", 1L);
        when(deviceRepository.findByDeviceId("web-guest")).thenReturn(Optional.empty());

        messageService.send("1", envelope);

        verify(realtimePublisher).publishToUserBestEffort(eq("1"), same(envelope));
        verify(realtimePublisher).publishToDeviceBestEffort(eq("web-guest"), same(envelope));
    }

    @Test
    void sendDirectedEphemeralDoesNotDoublePublishSameAccountDevice() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "lan_file_offer");
        envelope.put("payload", Map.of("pullUrl", "http://10.0.0.2/f"));
        envelope.put("fromDeviceId", "device_a");
        envelope.put("toDeviceId", "web-own");
        envelope.put("ts", 1L);
        User owner = User.builder().id(1L).build();
        Device web = Device.builder().deviceId("web-own").name("Web").user(owner).build();
        when(deviceRepository.findByDeviceId("web-own")).thenReturn(Optional.of(web));

        messageService.send("1", envelope);

        verify(realtimePublisher).publishToUserBestEffort(eq("1"), same(envelope));
        verify(realtimePublisher, never()).publishToDeviceBestEffort(any(), any());
    }

    @Test
    void sendLeavesFileMetadataReadable() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "file");
        envelope.put("payload", Map.of("fileName", "report.pdf", "key", "files/report.pdf"));
        envelope.put("fromDeviceId", "device_a");
        envelope.put("ts", 1L);

        messageService.send("1", envelope);

        ArgumentCaptor<Message> messageCaptor = ArgumentCaptor.forClass(Message.class);
        verify(messageRepository).save(messageCaptor.capture());
        String data = messageCaptor.getValue().getData();
        assertFalse(cryptoService.isEncrypted(data));
        assertTrue(data.contains("report.pdf"));
        assertTrue(data.contains("files/report.pdf"));
    }

    @Test
    void getHistoryDecryptsUserEncryptedTextPayloadField() throws Exception {
        String encryptedText = userDataEncryption.encryptForUser(1L, "user secret");
        String plaintext = objectMapper.writeValueAsString(Map.of(
                "type", "text",
                "payload", Map.of("text", encryptedText),
                "fromDeviceId", "device_a",
                "ts", 1L,
                "threadKey", "u:1|kind:legacy_broadcast"));
        Message message = Message.builder()
                .id(9L)
                .userId(1L)
                .data(plaintext)
                .build();
        when(messageRepository.findByUserIdOrderByCreatedAtDesc(eq(1L), any(Pageable.class)))
                .thenReturn(List.of(message));
        when(messageRepository.findByUserIdAndIdLessThanOrderByCreatedAtDesc(eq(1L), eq(9L), any(Pageable.class)))
                .thenReturn(List.of());

        List<Map<String, Object>> history = messageService.getHistory(1L, 50, null, null);

        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) history.get(0).get("payload");
        assertEquals("user secret", payload.get("text"));
    }

    @Test
    void getHistoryDecryptsTextPayloadField() {
        String encryptedText = cryptoService.encrypt("secret text");
        String plaintext = "{\"type\":\"text\",\"payload\":{\"text\":\"" + encryptedText + "\"},\"fromDeviceId\":\"device_a\",\"ts\":1,\"threadKey\":\"u:1|kind:legacy_broadcast\"}";
        Message message = Message.builder()
                .id(7L)
                .userId(1L)
                .data(plaintext)
                .build();
        when(messageRepository.findByUserIdOrderByCreatedAtDesc(eq(1L), any(Pageable.class)))
                .thenReturn(List.of(message));
        when(messageRepository.findByUserIdAndIdLessThanOrderByCreatedAtDesc(eq(1L), eq(7L), any(Pageable.class)))
                .thenReturn(List.of());

        List<Map<String, Object>> history = messageService.getHistory(1L, 50, null, null);

        assertEquals(1, history.size());
        assertEquals(7L, history.get(0).get("id"));
        assertEquals("text", history.get(0).get("type"));
        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) history.get(0).get("payload");
        assertEquals("secret text", payload.get("text"));
    }

    @Test
    void getHistoryStillSupportsLegacyWholeEnvelopeCiphertext() {
        String plaintext = "{\"type\":\"text\",\"payload\":{\"text\":\"secret text\"},\"fromDeviceId\":\"device_a\",\"ts\":1,\"threadKey\":\"u:1|kind:legacy_broadcast\"}";
        Message message = Message.builder()
                .id(8L)
                .userId(1L)
                .data(cryptoService.encrypt(plaintext))
                .build();
        when(messageRepository.findByUserIdOrderByCreatedAtDesc(eq(1L), any(Pageable.class)))
                .thenReturn(List.of(message));
        when(messageRepository.findByUserIdAndIdLessThanOrderByCreatedAtDesc(eq(1L), eq(8L), any(Pageable.class)))
                .thenReturn(List.of());

        List<Map<String, Object>> history = messageService.getHistory(1L, 50, null, null);

        @SuppressWarnings("unchecked")
        Map<String, Object> payload = (Map<String, Object>) history.get(0).get("payload");
        assertEquals("secret text", payload.get("text"));
    }

    @Test
    void deleteMessagesByThreadKeyDeletesOnlyMatchingThread() {
        String threadA = "u:1|d1:aaa|d2:bbb";
        String threadB = "u:1|d1:ccc|d2:ddd";
        Message msgA = Message.builder()
                .id(10L)
                .userId(1L)
                .data("{\"type\":\"text\",\"payload\":{\"text\":\"hi\"},\"fromDeviceId\":\"aaa\",\"ts\":1,\"threadKey\":\"" + threadA + "\"}")
                .build();
        Message msgB = Message.builder()
                .id(11L)
                .userId(1L)
                .data("{\"type\":\"text\",\"payload\":{\"text\":\"other\"},\"fromDeviceId\":\"ccc\",\"ts\":2,\"threadKey\":\"" + threadB + "\"}")
                .build();
        when(messageRepository.findByUserIdOrderByCreatedAtDesc(eq(1L), any(Pageable.class)))
                .thenReturn(List.of(msgA, msgB));

        int deleted = messageService.deleteMessagesByThreadKey(1L, threadA);

        assertEquals(1, deleted);
        verify(messageRepository).deleteByIdAndUserId(10L, 1L);
        verify(messageRepository, never()).deleteByIdAndUserId(11L, 1L);
    }

    @Test
    void deleteMessagesByThreadKeyRequiresNonBlankThreadKey() {
        assertThrows(IllegalArgumentException.class, () -> messageService.deleteMessagesByThreadKey(1L, "  "));
    }

    @Test
    void sendFromDeviceRejectsWhenUnpaired() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "lan_http_probe");
        envelope.put("toDeviceId", "peer");
        envelope.put("payload", Map.of("probeId", "p1"));
        when(devicePairingService.canSignal("dev-a", "peer")).thenReturn(false);
        assertThrows(org.springframework.web.server.ResponseStatusException.class,
                () -> messageService.sendFromDevice("dev-a", envelope));
        verify(realtimePublisher, never()).publishToDeviceBestEffort(any(), any());
    }

    @Test
    void sendFromDeviceRejectsNonSignalingNonText() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "file");
        envelope.put("toDeviceId", "peer");
        envelope.put("payload", Map.of("fileName", "a.bin"));

        assertThrows(org.springframework.web.server.ResponseStatusException.class,
                () -> messageService.sendFromDevice("dev-a", envelope));
        verify(realtimePublisher, never()).publishToDeviceBestEffort(any(), any());
        verify(messageRepository, never()).save(any());
    }

    @Test
    void sendFromDevicePublishesTextWithoutPersisting() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "text");
        envelope.put("toDeviceId", "peer");
        envelope.put("payload", Map.of("text", "hi", "localId", "l1"));
        when(devicePairingService.canSignal("dev-a", "peer")).thenReturn(true);
        when(deviceRepository.findByDeviceId("peer")).thenReturn(Optional.empty());

        messageService.sendFromDevice("dev-a", envelope);

        verify(mailboxService).storeIfEphemeral(isNull(), any());
        verify(realtimePublisher).publishToDeviceBestEffort(eq("peer"), any());
        verify(messageRepository, never()).save(any());
    }

    @Test
    void sendFromDevicePublishesToPairedPeer() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "lan_http_probe");
        envelope.put("toDeviceId", "peer");
        envelope.put("payload", Map.of("probeId", "p1"));
        when(devicePairingService.canSignal("dev-a", "peer")).thenReturn(true);
        when(deviceRepository.findByDeviceId("peer")).thenReturn(Optional.empty());

        messageService.sendFromDevice("dev-a", envelope);

        verify(mailboxService).storeIfEphemeral(isNull(), any());
        verify(realtimePublisher).publishToDeviceBestEffort(eq("peer"), any());
        verify(messageRepository, never()).save(any());
    }

    @Test
    void sendFromDevicePublishesLanFileOfferToPeer() {
        Map<String, Object> envelope = new java.util.HashMap<>();
        envelope.put("type", "lan_file_offer");
        envelope.put("toDeviceId", "peer");
        envelope.put("payload", Map.of("pullUrl", "http://10.0.0.2/f", "targetDeviceId", "peer"));
        when(devicePairingService.canSignal("dev-a", "peer")).thenReturn(true);
        when(deviceRepository.findByDeviceId("peer")).thenReturn(Optional.empty());

        messageService.sendFromDevice("dev-a", envelope);

        verify(realtimePublisher).publishToDeviceBestEffort(eq("peer"), any());
    }
}
