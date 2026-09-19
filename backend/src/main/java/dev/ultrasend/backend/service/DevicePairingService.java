package dev.ultrasend.backend.service;

import dev.ultrasend.backend.entity.Device;
import dev.ultrasend.backend.entity.DevicePairing;
import dev.ultrasend.backend.repository.DevicePairingRepository;
import dev.ultrasend.backend.repository.DeviceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Instant;

@Service
@RequiredArgsConstructor
public class DevicePairingService {

    private final DevicePairingRepository devicePairingRepository;
    private final DeviceRepository deviceRepository;

    @Transactional
    public void pair(String deviceId, String peerDeviceId) {
        if (deviceId == null || peerDeviceId == null || deviceId.isBlank() || peerDeviceId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "deviceId required");
        }
        if (deviceId.equals(peerDeviceId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "cannot pair with self");
        }
        String a = orderedA(deviceId, peerDeviceId);
        String b = orderedB(deviceId, peerDeviceId);
        if (devicePairingRepository.findByDeviceAAndDeviceB(a, b).isPresent()) {
            return;
        }
        devicePairingRepository.save(DevicePairing.builder()
                .deviceA(a)
                .deviceB(b)
                .createdAt(Instant.now())
                .build());
    }

    @Transactional(readOnly = true)
    public boolean canSignal(String fromDeviceId, String toDeviceId) {
        if (fromDeviceId == null || toDeviceId == null || fromDeviceId.isBlank() || toDeviceId.isBlank()) {
            return false;
        }
        if (fromDeviceId.equals(toDeviceId)) {
            return true;
        }
        if (sameAccount(fromDeviceId, toDeviceId)) {
            return true;
        }
        String a = orderedA(fromDeviceId, toDeviceId);
        String b = orderedB(fromDeviceId, toDeviceId);
        return devicePairingRepository.findByDeviceAAndDeviceB(a, b).isPresent();
    }

    private boolean sameAccount(String fromDeviceId, String toDeviceId) {
        Device from = deviceRepository.findByDeviceId(fromDeviceId).orElse(null);
        Device to = deviceRepository.findByDeviceId(toDeviceId).orElse(null);
        if (from == null || to == null || !from.isActive() || !to.isActive()) {
            return false;
        }
        Long fromUid = from.getUser() != null ? from.getUser().getId() : null;
        Long toUid = to.getUser() != null ? to.getUser().getId() : null;
        return fromUid != null && fromUid.equals(toUid);
    }

    static String orderedA(String x, String y) {
        return x.compareTo(y) <= 0 ? x : y;
    }

    static String orderedB(String x, String y) {
        return x.compareTo(y) <= 0 ? y : x;
    }
}
