package com.noisex.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

import com.noisex.model.dto.ReportRequest;
import com.noisex.model.repository.ReportRepository;
import com.noisex.security.EncryptionService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ReportServiceTest {

    @Mock private ReportRepository reportRepository;

    @Mock private EncryptionService encryptionService;

    @InjectMocks private ReportService reportService;

    @Test
    void createReport_withPhone_shouldEncryptAndSave() {
        when(encryptionService.encrypt("13800138000")).thenReturn("encrypted-phone");
        when(reportRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        ReportRequest request = new ReportRequest();
        request.setRoomId("room-1");
        request.setReason("spam");
        request.setPhoneNumber("13800138000");

        String reportId = reportService.createReport("user-1", request);

        assertNotNull(reportId);
        assertTrue(reportId.length() > 0);
        verify(encryptionService).encrypt("13800138000");
        verify(reportRepository).save(any());
    }

    @Test
    void createReport_withoutPhone_shouldNotEncrypt() {
        when(reportRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        ReportRequest request = new ReportRequest();
        request.setRoomId("room-1");
        request.setReason("abuse");
        request.setPhoneNumber("");

        String reportId = reportService.createReport("user-1", request);

        assertNotNull(reportId);
        verify(encryptionService, never()).encrypt(anyString());
        verify(reportRepository).save(any());
    }

    @Test
    void decryptPhoneNumber_shouldCallEncryptionService() {
        when(encryptionService.decrypt("encrypted-phone")).thenReturn("13800138000");

        String result = reportService.decryptPhoneNumber("encrypted-phone");

        assertEquals("13800138000", result);
        verify(encryptionService).decrypt("encrypted-phone");
    }
}
