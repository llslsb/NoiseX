package com.noisex.model.repository;

import com.noisex.model.entity.ReportEntity;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ReportRepository extends JpaRepository<ReportEntity, String> {
    List<ReportEntity> findByStatus(ReportEntity.ReportStatus status);

    long countByStatus(ReportEntity.ReportStatus status);

    @Modifying
    @Query("DELETE FROM ReportEntity r WHERE r.reporterId = :reporterId")
    void deleteByReporterId(@Param("reporterId") String reporterId);
}
