package com.noisex.controller;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.ReportRequest;
import com.noisex.service.ReportService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.ResponseEntity;

@ExtendWith(MockitoExtension.class)
class ReportControllerTest {

    @Mock private ReportService reportService;

    @InjectMocks private ReportController reportController;

    @BeforeEach
    void setUp() {
        org.springframework.security.authentication.UsernamePasswordAuthenticationToken auth =
                new org.springframework.security.authentication.UsernamePasswordAuthenticationToken(
                        "user-1", null, java.util.List.of());
        org.springframework.security.core.context.SecurityContextHolder.getContext()
                .setAuthentication(auth);
    }

    @Test
    void createReport_shouldReturnReportId() {
        ReportRequest request = new ReportRequest();
        request.setRoomId("room-1");
        request.setReason("spam");
        request.setPhoneNumber("");

        when(reportService.createReport("user-1", request)).thenReturn("report-1");

        ResponseEntity<?> response = reportController.createReport(request);

        assertEquals(200, response.getStatusCode().value());
        verify(reportService).createReport("user-1", request);
    }

    @AfterEach
    void tearDown() {
        org.springframework.security.core.context.SecurityContextHolder.clearContext();
    }
}
