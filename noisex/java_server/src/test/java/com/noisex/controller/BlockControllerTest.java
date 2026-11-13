package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.service.BlockService;
import java.util.Set;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class BlockControllerTest {

    @Mock private BlockService blockService;

    @InjectMocks private BlockController blockController;

    @BeforeEach
    void setUp() {
        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth =
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                        "user-1", null, java.util.List.of());
        org.springframework.security.core.context.SecurityContextHolder.getContext()
                .setAuthentication(auth);
    }

    @Test
    void getBlockedList_shouldReturnBlockedUserIds() {
        when(blockService.getBlockedList("user-1")).thenReturn(Set.of("user-2", "user-3"));

        ResponseEntity<?> response = blockController.getBlockedList();

        assertEquals(200, response.getStatusCode().value());
        @SuppressWarnings("unchecked")
        var body = (com.noisex.model.dto.ApiResponse<Set<String>>) response.getBody();
        assertNotNull(body);
        assertNotNull(body.getData());
        assertEquals(2, body.getData().size());
        assertTrue(body.getData().contains("user-2"));
        assertTrue(body.getData().contains("user-3"));
        verify(blockService).getBlockedList("user-1");
    }

    @Test
    void unblockUser_shouldCallService() {
        doNothing().when(blockService).unblockUser("user-1", "user-2");

        ResponseEntity<?> response = blockController.unblockUser("user-2");

        assertEquals(200, response.getStatusCode().value());
        verify(blockService).unblockUser("user-1", "user-2");
    }

    @AfterEach
    void tearDown() {
        org.springframework.security.core.context.SecurityContextHolder.clearContext();
    }
}
