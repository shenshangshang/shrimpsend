package dev.ultrasend.backend.service;

import dev.ultrasend.backend.entity.Device;
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
    private final DeviceIdentityService identity;

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
        // Both peers may pair at once. Let the unique key make this atomic;
        // a check-then-insert races and produces a 500 on a valid pairing.
        devicePairingRepository.insertIfAbsent(a, b, Instant.now());
    }

    @Transactional
    public void unpair(String me,String peer) {
        devicePairingRepository.deleteByDeviceAAndDeviceB(orderedA(me,peer),orderedB(me,peer));
    }

    @Transactional(readOnly = true)
    public boolean canSignal(String fromDeviceId, String toDeviceId) {
        if (fromDeviceId == null || toDeviceId == null || fromDeviceId.isBlank() || toDeviceId.isBlank()) {
            return false;
        }
        if (fromDeviceId.equals(toDeviceId)) {
            return true;
        }
        String a = orderedA(fromDeviceId, toDeviceId);
        String b = orderedB(fromDeviceId, toDeviceId);
        return devicePairingRepository.findByDeviceAAndDeviceB(a, b).isPresent();
    }

    @Transactional(readOnly = true)
    public java.util.List<dev.ultrasend.backend.dto.DeviceDto> peers(String me) {
        return devicePairingRepository.findByDeviceAOrDeviceB(me, me).stream().map(pair -> {
            String id = me.equals(pair.getDeviceA()) ? pair.getDeviceB() : pair.getDeviceA();
            return identity.describe(id);
        }).toList();
    }

    static String orderedA(String x, String y) {
        return x.compareTo(y) <= 0 ? x : y;
    }

    static String orderedB(String x, String y) {
        return x.compareTo(y) <= 0 ? y : x;
    }
}
