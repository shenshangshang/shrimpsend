package dev.ultrasend.backend.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class DeviceSessionRequest {

    @NotBlank
    @Size(max = 255)
    private String deviceId;

    @NotBlank
    @Size(min = 16, max = 512)
    private String deviceSecret;

    @Size(max = 32)
    private String platform;
}
