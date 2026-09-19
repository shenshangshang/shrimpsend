package dev.ultrasend.backend.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.ultrasend.backend.entity.Device;
import dev.ultrasend.backend.repository.DeviceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
@ConditionalOnProperty(name = "realtime.bus", havingValue = "wukongim", matchIfMissing = true)
@RequiredArgsConstructor
@Slf4j
public class WukongimPublishService implements RealtimePublisher {

    public static final int CHANNEL_PERSON = 1;

    private final WukongimApiClient wukongimApiClient;
    private final ObjectMapper objectMapper;
    private final DeviceRepository deviceRepository;

    @Value("${wukongim.system-uid:ultrasend}")
    private String systemUid;

    @Value("${wukongim.signaling-expire-sec:120}")
    private int signalingExpireSec;

    @Value("${wukongim.roster-expire-sec:30}")
    private int rosterExpireSec;

    @Value("${wukongim.dual-write-user-channel:true}")
    private boolean dualWriteUserChannel;

    @Override
    public void publishToUser(String userId, Object data) {
        String payload = WukongimPayloads.encodeBase64(objectMapper, data);
        int expire = expireSec(data);
        Set<String> channels = new LinkedHashSet<>();
        if (dualWriteUserChannel && userId != null && !userId.isBlank()) {
            channels.add(userId);
        }
        Long uid = parseUserId(userId);
        if (uid != null) {
            List<Device> devices = deviceRepository.findAllByUser_IdAndActiveTrue(uid);
            if (devices != null) {
                for (Device device : devices) {
                    if (device.getDeviceId() != null && !device.getDeviceId().isBlank()) {
                        channels.add(device.getDeviceId());
                    }
                }
            }
        }
        if (channels.isEmpty() && userId != null && !userId.isBlank()) {
            channels.add(userId);
        }
        for (String channelId : channels) {
            sendChannel(channelId, payload, expire);
        }
        log.info("wukongim publish ok uid={} channels={} expire={}", userId, channels.size(), expire);
    }

    @Override
    public void publishToDevice(String deviceId, Object data) {
        if (deviceId == null || deviceId.isBlank()) {
            return;
        }
        String payload = WukongimPayloads.encodeBase64(objectMapper, data);
        int expire = expireSec(data);
        sendChannel(deviceId, payload, expire);
        log.info("wukongim publish device ok deviceId={} expire={}", deviceId, expire);
    }

    @Override
    public void publishToUserBestEffort(String userId, Object data) {
        try {
            publishToUser(userId, data);
        } catch (Exception e) {
            log.warn("wukongim publish best-effort failed userId={}: {}", userId, e.getMessage());
        }
    }

    @Override
    public void publishToDeviceBestEffort(String deviceId, Object data) {
        try {
            publishToDevice(deviceId, data);
        } catch (Exception e) {
            log.warn("wukongim publish best-effort failed deviceId={}: {}", deviceId, e.getMessage());
        }
    }

    private void sendChannel(String channelId, String payload, int expire) {
        String clientMsgNo = "shrimp-" + channelId + "-" + UUID.randomUUID();
        wukongimApiClient.sendMessage(
                systemUid,
                channelId,
                CHANNEL_PERSON,
                payload,
                expire,
                clientMsgNo);
    }

    private static Long parseUserId(String userId) {
        if (userId == null || userId.isBlank()) {
            return null;
        }
        try {
            return Long.valueOf(userId.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private int expireSec(Object data) {
        String type = envelopeType(data);
        if (DeviceRosterPublisherType.EVENT.equals(type)) {
            return Math.max(1, rosterExpireSec);
        }
        if (RealtimeEnvelopeTypes.isEphemeral(type)) {
            return Math.max(1, signalingExpireSec);
        }
        return 0;
    }

    private static String envelopeType(Object data) {
        if (data instanceof java.util.Map<?, ?> map) {
            Object type = map.get("type");
            return type != null ? type.toString() : null;
        }
        return null;
    }

    private static final class DeviceRosterPublisherType {
        static final String EVENT = "device_roster_patch";
    }
}
