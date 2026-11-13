package com.noisex.model.repository;

import com.noisex.model.entity.CompensationEntity;
import com.noisex.model.entity.CompensationEntity.CompensationStatus;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CompensationRepository extends JpaRepository<CompensationEntity, String> {

    List<CompensationEntity> findByStatusAndNextRetryAtBefore(
            CompensationStatus status, long timestamp);

    List<CompensationEntity> findByStatus(CompensationStatus status);

    long countByStatus(CompensationStatus status);

    @Modifying
    @Query("UPDATE CompensationEntity c SET c.status = :status WHERE c.id = :id")
    void updateStatus(@Param("id") String id, @Param("status") CompensationStatus status);
}
