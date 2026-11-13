package com.noisex.model.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Entity
@Table(name = "pending_compensation")
public class CompensationEntity {

    @Id
    @Column(length = 32)
    private String id;

    @Column(nullable = false, length = 64)
    private String operation;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String payload;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private CompensationStatus status;

    @Column(name = "retry_count", nullable = false)
    @Builder.Default
    private int retryCount = 0;

    @Column(name = "max_retries", nullable = false)
    @Builder.Default
    private int maxRetries = 3;

    @Column(name = "created_at", nullable = false)
    private long createdAt;

    @Column(name = "next_retry_at", nullable = false)
    private long nextRetryAt;

    public enum CompensationStatus {
        PENDING,
        RETRYING,
        DONE,
        FAILED
    }
}
