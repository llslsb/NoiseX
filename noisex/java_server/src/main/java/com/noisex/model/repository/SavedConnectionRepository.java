package com.noisex.model.repository;

import com.noisex.model.entity.SavedConnectionEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SavedConnectionRepository extends JpaRepository<SavedConnectionEntity, String> {
    boolean existsByRoomId(String roomId);

    @Modifying
    @Query("DELETE FROM SavedConnectionEntity s WHERE s.userIdA = :userId OR s.userIdB = :userId")
    void deleteByUserId(@Param("userId") String userId);
}
