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
@Table(name = "admin_account")
public class AdminAccountEntity {
    @Id
    @Column(length = 32)
    private String id;

    @Column(length = 64, nullable = false, unique = true)
    private String username;

    @Column(length = 36, nullable = false, unique = true)
    private String userId;

    @Column(length = 100, nullable = false)
    private String passwordHash;

    @Builder.Default
    @Column(nullable = false)
    private boolean enabled = true;

    @Column(nullable = false)
    private long createdAt;

    @Column(nullable = false)
    private long updatedAt;

    private Long lastLoginAt;
}
