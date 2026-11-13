package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.service.PushService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class PushControllerTest {

    @Mock private PushService pushService;

    @InjectMocks private PushController pushController;

    @BeforeEach
    void setUp() {
        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth =
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                        "user-1", null, java.util.List.of());
        org.springframework.security.core.context.SecurityContextHolder.getContext()
                .setAuthentication(auth);
    }

    @Test
    void registerToken_shouldCallPushService() {
        ResponseEntity<?> response = pushController.registerToken("push-token-123", "hms");

        assertEquals(200, response.getStatusCode().value());
        verify(pushService).registerToken("user-1", "push-token-123", "hms");
    }

    @Test
    void unregisterToken_shouldCallPushService() {
        ResponseEntity<?> response = pushController.unregisterToken();

        assertEquals(200, response.getStatusCode().value());
        verify(pushService).unregisterToken("user-1");
    }

    @AfterEach
    void tearDown() {
        org.springframework.security.core.context.SecurityContextHolder.clearContext();
    }
}
