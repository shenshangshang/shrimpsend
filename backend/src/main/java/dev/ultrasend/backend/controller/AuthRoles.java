package dev.ultrasend.backend.controller;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;

final class AuthRoles {

    private AuthRoles() {}

    static boolean isDevice(Authentication auth) {
        if (auth == null) {
            return false;
        }
        for (GrantedAuthority authority : auth.getAuthorities()) {
            if ("ROLE_DEVICE".equals(authority.getAuthority())) {
                return true;
            }
        }
        return false;
    }

    static String deviceId(Authentication auth) {
        if (auth == null || !isDevice(auth)) {
            return null;
        }
        Object principal = auth.getPrincipal();
        return principal != null ? principal.toString() : null;
    }
}
