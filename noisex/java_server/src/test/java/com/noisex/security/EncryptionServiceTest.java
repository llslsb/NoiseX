package com.noisex.security;

import static org.assertj.core.api.Assertions.*;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class EncryptionServiceTest {

    private EncryptionService encryptionService;

    @BeforeEach
    void setUp() {
        encryptionService = new EncryptionService("local-encryption-key-change-in-prod-32b!");
    }

    @Test
    void encrypt_normalText_shouldReturnBase64() {
        String result = encryptionService.encrypt("hello world");

        assertThat(result).isNotNull().isNotEmpty();
        assertThat(result).doesNotContain("hello world");
    }

    @Test
    void encrypt_null_shouldReturnNull() {
        String result = encryptionService.encrypt(null);

        assertThat(result).isNull();
    }

    @Test
    void encrypt_empty_shouldReturnEmpty() {
        String result = encryptionService.encrypt("");

        assertThat(result).isEmpty();
    }

    @Test
    void decrypt_afterEncrypt_shouldReturnOriginal() {
        String original = "hello world";
        String encrypted = encryptionService.encrypt(original);
        String decrypted = encryptionService.decrypt(encrypted);

        assertThat(decrypted).isEqualTo(original);
    }

    @Test
    void decrypt_afterEncrypt_longText_shouldReturnOriginal() {
        String original = "a".repeat(10000);
        String encrypted = encryptionService.encrypt(original);
        String decrypted = encryptionService.decrypt(encrypted);

        assertThat(decrypted).isEqualTo(original);
    }

    @Test
    void decrypt_afterEncrypt_chineseText_shouldReturnOriginal() {
        String original = "你好世界，这是一个中文测试文本！";
        String encrypted = encryptionService.encrypt(original);
        String decrypted = encryptionService.decrypt(encrypted);

        assertThat(decrypted).isEqualTo(original);
    }

    @Test
    void decrypt_invalidBase64_shouldThrow() {
        assertThatThrownBy(() -> encryptionService.decrypt("not-valid-base64!!!"))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Decryption failed");
    }

    @Test
    void decrypt_tamperedCiphertext_shouldThrow() {
        String encrypted = encryptionService.encrypt("secret data");
        byte[] bytes = java.util.Base64.getDecoder().decode(encrypted);
        bytes[bytes.length - 1] ^= 0xFF;
        String tampered = java.util.Base64.getEncoder().encodeToString(bytes);

        assertThatThrownBy(() -> encryptionService.decrypt(tampered))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Decryption failed");
    }

    @Test
    void encrypt_differentCalls_shouldProduceDifferentCiphertext() {
        String plaintext = "same input";

        String encrypted1 = encryptionService.encrypt(plaintext);
        String encrypted2 = encryptionService.encrypt(plaintext);

        assertThat(encrypted1).isNotEqualTo(encrypted2);
    }
}
