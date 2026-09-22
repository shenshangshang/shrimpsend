package dev.ultrasend.backend.dto;

import jakarta.validation.constraints.*;
import lombok.Data;

@Data
public class DeviceHeartbeatRequest {
    @NotBlank @Size(max = 128) private String sessionId;
    @Positive private long sequence;
    @NotBlank @Pattern(regexp = "online|offline") private String status;
    @Size(max = 80) private String name;
    @Size(max = 32) private String platform;
    @Size(max = 512) private String lanHttpUrl;
}
