package dev.ultrasend.backend.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class DevicePairingServiceTest {

    @Test
    void ordersPairKeysLexicographically() {
        assertEquals("a", DevicePairingService.orderedA("b", "a"));
        assertEquals("b", DevicePairingService.orderedB("b", "a"));
        assertEquals("a", DevicePairingService.orderedA("a", "b"));
        assertEquals("b", DevicePairingService.orderedB("a", "b"));
    }
}
