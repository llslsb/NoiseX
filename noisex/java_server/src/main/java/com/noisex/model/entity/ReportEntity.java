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
@Table(name = "report")
public class ReportEntity {
    @Id
    @Column(length = 32)
    private String id;

    @Column(name = "reporter_id", nullable = false, length = 36)
    private String reporterId;

    @Column(name = "room_id", nullable = false, length = 32)
    private String roomId;

    @Column(nullable = false, length = 500)
    private String reason;

    @Column(name = "phone_number", length = 200)
    private String phoneNumber;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ReportStatus status;

    @Column(name = "created_at", nullable = false)
    private long createdAt;

    @Column(name = "reviewed_at")
    private Long reviewedAt;

    public enum ReportStatus {
        pending,
        reviewed,
        dismissed,
        banned
    }
}
