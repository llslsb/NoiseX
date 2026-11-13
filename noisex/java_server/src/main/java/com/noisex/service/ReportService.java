package com.noisex.service;

import com.noisex.model.dto.ReportRequest;
import com.noisex.model.entity.ReportEntity;
import com.noisex.model.repository.ReportRepository;
import com.noisex.security.EncryptionService;
import com.noisex.util.IdGenerator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class ReportService {

    private final ReportRepository reportRepository;
    private final EncryptionService encryptionService;

    public String createReport(String reporterId, ReportRequest request) {
        // 加密手机号（如有提供）
        String encryptedPhone = null;
        if (request.getPhoneNumber() != null && !request.getPhoneNumber().isEmpty()) {
            encryptedPhone = encryptionService.encrypt(request.getPhoneNumber());
        }

        ReportEntity report =
                ReportEntity.builder()
                        .id(IdGenerator.nextId())
                        .reporterId(reporterId)
                        .roomId(request.getRoomId())
                        .reason(request.getReason())
                        .phoneNumber(encryptedPhone)
                        .status(ReportEntity.ReportStatus.pending)
                        .createdAt(System.currentTimeMillis())
                        .build();

        reportRepository.save(report);
        log.info(
                "Report created: id={}, reporter={}, room={}",
                report.getId(),
                reporterId,
                request.getRoomId());
        return report.getId();
    }

    /** 解密手机号（仅供管理员审核时使用） */
    public String decryptPhoneNumber(String encryptedPhone) {
        return encryptionService.decrypt(encryptedPhone);
    }
}
