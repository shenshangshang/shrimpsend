package dev.ultrasend.backend.service;

import dev.ultrasend.backend.controller.MembershipController;
import dev.ultrasend.backend.entity.MembershipOrder;
import dev.ultrasend.backend.entity.User;
import dev.ultrasend.backend.repository.MembershipOrderRepository;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.util.ReflectionTestUtils;
import java.time.Instant;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class MembershipOrderHistoryTest {
    @Test void listIsBoundToAuthenticatedAccountAndRejectsDeviceSessions() {
        var service = mock(MembershipService.class);
        var api = new MembershipController(service, null, null, null);
        var device = new UsernamePasswordAuthenticationToken("device-a", null, List.of(new SimpleGrantedAuthority("ROLE_DEVICE")));
        assertEquals(403, api.listOrders(device).getStatusCode().value());
        assertEquals(403, api.listOrders(null).getStatusCode().value());
        verifyNoInteractions(service);
        var owner = new UsernamePasswordAuthenticationToken("72", null, List.of(new SimpleGrantedAuthority("ROLE_USER")));
        when(service.listOrders(72L)).thenReturn(List.of());
        assertEquals(200, api.listOrders(owner).getStatusCode().value());
        verify(service).listOrders(72L);
    }
    @Test void readsBoundedNewestAccountOrdersWithoutTriggeringPayment() {
        var repository = mock(MembershipOrderRepository.class);
        var service = mock(MembershipService.class, CALLS_REAL_METHODS);
        ReflectionTestUtils.setField(service, "membershipOrderRepository", repository);
        var user = new User(); user.setId(72L);
        var order = MembershipOrder.builder().user(user).orderNo("qa-order").fromTier("FREE").toTier("PRO").payableAmountCent(100).currency("CNY").channel("ALIPAY").status("CREATED").createdAt(Instant.now()).updatedAt(Instant.now()).build();
        when(repository.findTop100ByUserIdOrderByCreatedAtDesc(72L)).thenReturn(List.of(order));
        var result = service.listOrders(72L);
        assertEquals("qa-order", result.get(0).getOrderNo());
        assertEquals("CREATED", result.get(0).getStatus());
        verify(repository).findTop100ByUserIdOrderByCreatedAtDesc(72L);
        verifyNoMoreInteractions(repository);
    }
}
