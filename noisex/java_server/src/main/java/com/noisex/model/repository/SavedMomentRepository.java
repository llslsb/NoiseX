package com.noisex.model.repository;

import com.noisex.model.entity.SavedMomentEntity;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SavedMomentRepository extends JpaRepository<SavedMomentEntity, String> {

    List<SavedMomentEntity> findByUserIdOrderByCreatedAtDesc(String userId);

    @Query("SELECT s FROM SavedMomentEntity s WHERE s.userId = :userId AND s.roomId = :roomId")
    SavedMomentEntity findByUserIdAndRoomId(
            @Param("userId") String userId, @Param("roomId") String roomId);

    boolean existsByUserIdAndRoomId(String userId, String roomId);

    /**
     * 重置身份时删除该用户保存的全部片段（片段为用户主动提交的明文，不受端到端加密保护）。
     *
     * <p>2026-11-06 补：此前 AuthService.deleteUserData 漏删本表，重置身份后片段永久残留， 与隐私政策「重置身份即永久删除」承诺不符——勿删。
     */
    @Modifying
    @Query("DELETE FROM SavedMomentEntity s WHERE s.userId = :userId")
    void deleteByUserId(@Param("userId") String userId);
}
