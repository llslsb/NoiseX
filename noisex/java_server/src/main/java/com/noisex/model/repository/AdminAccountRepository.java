package com.noisex.model.repository;

import com.noisex.model.entity.AdminAccountEntity;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AdminAccountRepository extends JpaRepository<AdminAccountEntity, String> {
    Optional<AdminAccountEntity> findByUsername(String username);

    boolean existsByUsername(String username);

    boolean existsByUserId(String userId);
}
