package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.*;
import com.noisex.service.SonarService;
import java.util.Collections;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class SonarControllerTest {

    @Mock private SonarService sonarService;

    @InjectMocks private SonarController sonarController;

    @BeforeEach
    void setUp() {
        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth =
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                        "user-1", null, java.util.List.of());
        org.springframework.security.core.context.SecurityContextHolder.getContext()
                .setAuthentication(auth);
    }

    @Test
    void sendSonar_shouldReturnSonarId() {
        when(sonarService.sendSonar("user-1", "hello", "wtmkq8")).thenReturn("sonar-1");

        SendSonarRequest request = new SendSonarRequest();
        request.setContent("hello");
        request.setGeohash("wtmkq8");

        ResponseEntity<?> response = sonarController.sendSonar(request);

        assertEquals(200, response.getStatusCode().value());
        verify(sonarService).sendSonar("user-1", "hello", "wtmkq8");
    }

    @Test
    void getReceivedSonars_shouldReturnList() {
        when(sonarService.getReceivedSonars("user-1")).thenReturn(Collections.emptyList());

        ResponseEntity<?> response = sonarController.getReceivedSonars();

        assertEquals(200, response.getStatusCode().value());
        verify(sonarService).getReceivedSonars("user-1");
    }

    @Test
    void acceptSonar_shouldReturnAcceptResponse() {
        AcceptSonarResponse acceptResponse =
                new AcceptSonarResponse(
                        "room-1", "RX-1234", "hello", System.currentTimeMillis() + 7200000L);
        when(sonarService.acceptSonar("user-1", "sonar-1")).thenReturn(acceptResponse);

        ResponseEntity<?> response = sonarController.acceptSonar("sonar-1");

        assertEquals(200, response.getStatusCode().value());
        verify(sonarService).acceptSonar("user-1", "sonar-1");
    }

    @Test
    void ignoreSonar_shouldCallService() {
        ResponseEntity<?> response = sonarController.ignoreSonar("sonar-1");

        assertEquals(200, response.getStatusCode().value());
        verify(sonarService).ignoreSonar("user-1", "sonar-1");
    }

    @AfterEach
    void tearDown() {
        org.springframework.security.core.context.SecurityContextHolder.clearContext();
    }
}
