package dev.ultrasend.backend.controller;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WukongimWebhookControllerTest {

    @Test
    void beforeSendAllowsSystemUidOnly() {
        WukongimWebhookController controller = new WukongimWebhookController(null);
        org.springframework.test.util.ReflectionTestUtils.setField(controller, "systemUid", "ultrasend");
        assertTrue(controller.allowSystemSend(Map.of("from_uid", "ultrasend", "payload", "x")));
        assertFalse(controller.allowSystemSend(Map.of("from_uid", "guest-device", "payload", "x")));
        assertTrue(WukongimWebhookController.isBeforeSend("msg.before_send", null));
        assertFalse(WukongimWebhookController.isBeforeSend("user.onlinestatus", Map.of()));
    }
}
