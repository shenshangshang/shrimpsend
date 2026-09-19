package dev.ultrasend.backend.realtime;

/**
 * Fan-out control-plane envelopes to every device of a user.
 */
public interface RealtimePublisher {

    void publishToUser(String userId, Object data);

    void publishToUserBestEffort(String userId, Object data);

    /** Deliver to a single device channel (WuKongIM uid = deviceId). */
    default void publishToDevice(String deviceId, Object data) {
        publishToUser(deviceId, data);
    }

    default void publishToDeviceBestEffort(String deviceId, Object data) {
        try {
            publishToDevice(deviceId, data);
        } catch (Exception ignored) {
            // implementers that need logs should override
        }
    }
}
