package dev.ultrasend.backend.realtime;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
@ConditionalOnProperty(name = "realtime.bus", havingValue = "wukongim", matchIfMissing = true)
@RequiredArgsConstructor
@Slf4j
public class WukongimPublishService implements RealtimePublisher {

    public static final int CHANNEL_PERSON = 1;

    private final WukongimApiClient wukongimApiClient;
    private final ObjectMapper objectMapper;

    @Value("${wukongim.system-uid:ultrasend}")
    private String systemUid;

    @Value("${wukongim.signaling-expire-sec:120}")
    private int signalingExpireSec;

    @Value("${wukongim.roster-expire-sec:30}")
    private int rosterExpireSec;

    @Override
    public void publishToUser(String userId, Object data) {
        String payload = WukongimPayloads.encodeBase64(objectMapper, data);
        int expire = expireSec(data);
        String clientMsgNo = "shrimp-" + userId + "-" + UUID.randomUUID();
        wukongimApiClient.sendMessage(
                systemUid,
                userId,
                CHANNEL_PERSON,
                payload,
                expire,
                clientMsgNo);
        log.info("wukongim publish ok uid={} expire={}", userId, expire);
    }

    @Override
    public void publishToUserBestEffort(String userId, Object data) {
        try {
            publishToUser(userId, data);
        } catch (Exception e) {
            log.warn("wukongim publish best-effort failed userId={}: {}", userId, e.getMessage());
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
