package dev.ultrasend.backend.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class PairDeviceRequest {

    @NotBlank
    @Size(max = 255)
    private String peerDeviceId;
}
