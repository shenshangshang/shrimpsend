package dev.ultrasend.backend.realtime;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class RealtimeEnvelopeTypesTest {

    @Test
    void lanPullCancelledIsEphemeral() {
        assertTrue(RealtimeEnvelopeTypes.isEphemeral("lan_pull_cancelled"));
        assertTrue(RealtimeEnvelopeTypes.isEphemeral("lan_file_offer"));
        assertTrue(RealtimeEnvelopeTypes.isEphemeral("device_pair_hello"));
        assertFalse(RealtimeEnvelopeTypes.isEphemeral("text"));
        assertFalse(RealtimeEnvelopeTypes.isEphemeral("file"));
        assertFalse(RealtimeEnvelopeTypes.isEphemeral(null));
    }
}
