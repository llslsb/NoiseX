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
@Table(name = "user_profile")
public class UserProfileEntity {
    @Id
    @Column(length = 36)
    private String userId;

    @Column(length = 200)
    private String signature;

    @Column(length = 50)
    private String city;

    @Column(length = 200)
    private String contact;

    @Builder.Default
    @Column(length = 10, nullable = false)
    private String role = "USER";

    @Column(nullable = false)
    private long updatedAt;
}
