package dev.ultrasend.backend.realtime;

import java.util.Set;

/**
 * Envelope types that are signaling-only: broadcast (and mailbox), never chat history.
 */
public final class RealtimeEnvelopeTypes {

    public static final Set<String> EPHEMERAL = Set.of(
            "lan_file_offer",
            "lan_pull_probe",
            "lan_pull_probe_result",
            "lan_http_probe",
            "lan_http_probe_result",
            "lan_pull_cancelled",
            "webrtc_probe",
            "webrtc_probe_result",
            "webrtc_offer",
            "webrtc_answer",
            "webrtc_ice_candidate",
            "webrtc_transfer_cancel",
            "device_pair_hello");

    private RealtimeEnvelopeTypes() {}

    public static boolean isEphemeral(String type) {
        return type != null && EPHEMERAL.contains(type);
    }
}
