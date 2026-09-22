package dev.ultrasend.backend.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RealtimeTokenResponse {

    private String uid;
    private String token;
    private String websocketUrl;
    private int deviceFlag;
    private int deviceLevel;
    private String channelId;
    private int channelType;
    private String deviceAccessToken;
}
