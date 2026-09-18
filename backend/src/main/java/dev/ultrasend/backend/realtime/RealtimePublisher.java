package dev.ultrasend.backend.realtime;

/**
 * Fan-out control-plane envelopes to every device of a user.
 */
public interface RealtimePublisher {

    void publishToUser(String userId, Object data);

    void publishToUserBestEffort(String userId, Object data);
}
